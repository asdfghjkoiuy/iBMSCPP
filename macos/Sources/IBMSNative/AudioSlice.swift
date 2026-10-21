import Foundation

/// 一套切片入口。切点按来源分模式，写出共用 PCM 16-bit。
enum AudioSliceMode: String, CaseIterable {
    case bmhelper
    case woslicer

    var displayName: String {
        switch self {
        case .bmhelper: return AudioSlicerLayout.bmhelperModeTitle
        case .woslicer: return AudioSlicerLayout.woslicerModeTitle
        }
    }
}

enum AudioSliceRequest {
    case bmhelper(notes: [MidiNoteEvent], quantize: Int, bpm: Double, offsetMs: Double)
    case woslicer(marks: [Double], offsetSeconds: Double, duration: Double?)
}

enum AudioSlice {
    /// 把 OGG 等解成 PCM16 WAV。应用启动时接 `IBMSAudioBridge`；切片测试也可以设。
    /// 解码本身不绑主线程，闭包按 `@Sendable` 交给切片和预听共用。
    nonisolated(unsafe) static var decodeToWav: (@Sendable (URL) -> Data?)?
    private static let pcmDecodeCache = PcmDecodeCache()

    static func readPcm(_ url: URL) throws -> BmhelperPcmWav {
        if let stamp = fileStamp(url),
           let cached = pcmDecodeCache.load(path: url.path, modified: stamp.modified, size: stamp.size) {
            return cached
        }
        let wav = try loadPcm(url)
        if let stamp = fileStamp(url) {
            pcmDecodeCache.store(path: url.path, modified: stamp.modified, size: stamp.size, wav: wav)
        }
        return wav
    }

    /// 最近一次成功解码。路径、修改时间和大小都没变就不再读盘。
    private static func fileStamp(_ url: URL) -> (modified: Date, size: Int)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let modified = values.contentModificationDate,
              let size = values.fileSize
        else {
            return nil
        }
        return (modified, size)
    }

    private static func loadPcm(_ url: URL) throws -> BmhelperPcmWav {
        if let data = try? Data(contentsOf: url), let wav = try? BmhelperWavIO.read(data) {
            return wav
        }
        if let data = decodeToWav?(url), let wav = try? BmhelperWavIO.read(data) {
            return wav
        }
        throw BmhelperWavSplitError.couldNotReadInput(url.path)
    }

    static func splitPoints(_ request: AudioSliceRequest) -> [Double] {
        switch request {
        case .bmhelper(let notes, let quantize, let bpm, let offsetMs):
            return BmhelperWavSplit.splitPoints(
                notes: notes,
                quantize: quantize,
                bpm: bpm,
                offsetMs: offsetMs
            )
        case .woslicer(let marks, let offsetSeconds, let duration):
            return WoslicerSplit.splitPoints(marks: marks, offset: offsetSeconds, duration: duration)
        }
    }

    static func outputFileName(mode: AudioSliceMode, prefix: String, indexFromZero: Int) -> String {
        switch mode {
        case .bmhelper:
            return BmhelperWavSplit.outputFileName(prefix: prefix, indexFromZero: indexFromZero)
        case .woslicer:
            return WoslicerSplit.outputFileName(base: prefix, indexFromZero: indexFromZero)
        }
    }

    static func splitFile(
        mode: AudioSliceMode,
        input: URL,
        outputDirectory: URL,
        prefix: String,
        request: AudioSliceRequest
    ) throws -> [URL] {
        try splitFile(
            mode: mode,
            wav: try readPcm(input),
            outputDirectory: outputDirectory,
            prefix: prefix,
            request: request
        )
    }

    /// 切已经解码的 PCM。界面加载过波形后再导出时走这里，不再读同一份文件。
    static func splitFile(
        mode: AudioSliceMode,
        wav source: BmhelperPcmWav,
        outputDirectory: URL,
        prefix: String,
        request: AudioSliceRequest
    ) throws -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory) else {
            throw BmhelperWavSplitError.outputPathMissing
        }
        guard isDirectory.boolValue else {
            throw BmhelperWavSplitError.outputPathNotDirectory
        }
        guard fileManager.isWritableFile(atPath: outputDirectory.path) else {
            throw BmhelperWavSplitError.outputPathNotWritable
        }
        var wav = source
        if mode == .woslicer {
            wav = WoslicerTrim.trim(wav)
        }
        let duration = Double(wav.samples.count / max(wav.channels, 1)) / Double(max(wav.sampleRate, 1))
        let resolved: AudioSliceRequest
        if case .woslicer(let marks, let offset, _) = request {
            resolved = .woslicer(marks: marks, offsetSeconds: offset, duration: duration)
        } else {
            resolved = request
        }
        let times = splitPoints(resolved)
        let parts = BmhelperWavSplit.slice(wav: wav, times: times)
        var urls: [URL] = []
        for (index, part) in parts.enumerated() {
            let name = outputFileName(mode: mode, prefix: prefix, indexFromZero: index)
            let url = outputDirectory.appendingPathComponent(name)
            do {
                try BmhelperWavIO.write(part).write(to: url)
            } catch {
                throw BmhelperWavSplitError.couldNotOpenOutput(url.path)
            }
            urls.append(url)
        }
        return urls
    }

    /// 取出 `[start, end)` 这段 PCM，给 woslicer 预览用。不是再切一整份文件。
    static func extract(wav: BmhelperPcmWav, start: Double, end: Double) -> BmhelperPcmWav {
        let channels = max(wav.channels, 1)
        let sampleRate = max(wav.sampleRate, 1)
        let totalFrames = wav.samples.count / channels
        let startFrame = min(max(Int(start * Double(sampleRate)), 0), totalFrames)
        let endFrame = min(max(Int(end * Double(sampleRate)), startFrame), totalFrames)
        let startSample = startFrame * channels
        let endSample = endFrame * channels
        return BmhelperPcmWav(
            sampleRate: sampleRate,
            channels: channels,
            samples: Array(wav.samples[startSample..<endSample])
        )
    }
}

/// 只留一条。路径、修改时间或大小变了就作废。
private final class PcmDecodeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?
    private var modified: Date?
    private var size: Int?
    private var wav: BmhelperPcmWav?

    func load(path: String, modified: Date, size: Int) -> BmhelperPcmWav? {
        lock.lock()
        defer { lock.unlock() }
        guard self.path == path, self.modified == modified, self.size == size else { return nil }
        return wav
    }

    func store(path: String, modified: Date, size: Int, wav: BmhelperPcmWav) {
        lock.lock()
        defer { lock.unlock() }
        self.path = path
        self.modified = modified
        self.size = size
        self.wav = wav
    }
}
