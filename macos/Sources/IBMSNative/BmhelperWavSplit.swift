import Foundation

/// 对照 `wavsplit.cpp` 的切点和切片。只处理 PCM 16-bit WAV。
enum BmhelperWavSplitError: Error, Equatable, LocalizedError {
    case couldNotReadInput(String)
    case outputPathNotDirectory
    case outputPathMissing
    case outputPathNotWritable
    case couldNotOpenOutput(String)

    var errorDescription: String? {
        switch self {
        case .couldNotReadInput(let path):
            return "Couldn't read input audio file '\(path)'"
        case .outputPathNotDirectory:
            return "Output path is not a directory"
        case .outputPathMissing:
            return "Output path does not exist"
        case .outputPathNotWritable:
            return "Output path is not writeable"
        case .couldNotOpenOutput(let path):
            return "Couldn't open \(path) for output."
        }
    }

    var localizedDescription: String {
        errorDescription ?? ""
    }
}

struct BmhelperPcmWav: Equatable {
    var sampleRate: Int
    var channels: Int
    var samples: [Int16]
}

enum BmhelperWavIO {
    /// RIFF 的 `36 + dataSize` 必须放进 `UInt32`。超出就失败，避免转换时整数溢出崩溃。
    static func write(_ wav: BmhelperPcmWav) throws -> Data {
        let channels = max(wav.channels, 1)
        let sampleRate = max(wav.sampleRate, 1)
        let maxDataBytes = Int(UInt32.max) - 36
        guard channels <= Int(UInt16.max) / 2, wav.samples.count <= maxDataBytes / 2 else {
            throw BmhelperWavSplitError.couldNotOpenOutput("WAV exceeds 4GB")
        }
        let blockAlign = channels * 2
        guard blockAlign > 0, sampleRate <= Int(UInt32.max) / blockAlign else {
            throw BmhelperWavSplitError.couldNotOpenOutput("WAV exceeds 4GB")
        }
        let dataSize = wav.samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(&data, UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(&data, 16)
        appendUInt16(&data, 1)
        appendUInt16(&data, UInt16(channels))
        appendUInt32(&data, UInt32(sampleRate))
        appendUInt32(&data, UInt32(sampleRate * blockAlign))
        appendUInt16(&data, UInt16(blockAlign))
        appendUInt16(&data, 16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(&data, UInt32(dataSize))
        wav.samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    static func read(_ data: Data) throws -> BmhelperPcmWav {
        guard data.count >= 44,
              ascii(data, 0, 4) == "RIFF",
              ascii(data, 8, 4) == "WAVE"
        else {
            throw BmhelperWavSplitError.couldNotReadInput("")
        }
        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bits = 0
        var pcm = false
        var samples: [Int16] = []
        var foundData = false
        while true {
            let (headerEnd, headerOverflow) = offset.addingReportingOverflow(8)
            if headerOverflow || headerEnd > data.count { break }
            let id = ascii(data, offset, 4)
            let size = Int(readUInt32(data, offset + 4))
            let body = headerEnd
            if id == "fmt ", size >= 16 {
                let (fmtEnd, fmtOverflow) = body.addingReportingOverflow(16)
                if !fmtOverflow, fmtEnd <= data.count {
                    pcm = readUInt16(data, body) == 1
                    channels = Int(readUInt16(data, body + 2))
                    sampleRate = Int(readUInt32(data, body + 4))
                    bits = Int(readUInt16(data, body + 14))
                }
            } else if id == "data" {
                guard pcm, bits == 16, channels > 0, sampleRate > 0 else {
                    throw BmhelperWavSplitError.couldNotReadInput("")
                }
                let byteCount = min(size, data.count - body)
                let frameBytes = byteCount - (byteCount % 2)
                samples = [Int16](repeating: 0, count: frameBytes / 2)
                data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress?.advanced(by: body) else { return }
                    for index in samples.indices {
                        samples[index] = Int16(littleEndian: base.load(fromByteOffset: index * 2, as: Int16.self))
                    }
                }
                foundData = true
                break
            }
            guard let next = advancedChunkOffset(from: offset, body: body, size: size) else {
                throw BmhelperWavSplitError.couldNotReadInput("")
            }
            offset = next
        }
        guard foundData else {
            throw BmhelperWavSplitError.couldNotReadInput("")
        }
        return BmhelperPcmWav(sampleRate: sampleRate, channels: channels, samples: samples)
    }

    /// chunk 长度来自文件。加法溢出或步进不前进都当损坏头，避免越界或死循环。
    private static func advancedChunkOffset(from offset: Int, body: Int, size: Int) -> Int? {
        let (chunkEnd, chunkOverflow) = body.addingReportingOverflow(size)
        if chunkOverflow { return nil }
        let (next, padOverflow) = chunkEnd.addingReportingOverflow(size % 2)
        if padOverflow || next <= offset { return nil }
        return next
    }

    private static func ascii(_ data: Data, _ start: Int, _ count: Int) -> String {
        String(bytes: data[start..<(start + count)], encoding: .ascii) ?? ""
    }

    private static func readUInt16(_ data: Data, _ start: Int) -> UInt16 {
        UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ start: Int) -> UInt32 {
        UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}

/// 对照 `wavsplit.cpp` 的 `GetSplitPoints` / `SplitFile`。
enum BmhelperWavSplit {
    /// `beat = position / quantize`，`time = (60 / bpm) * beat + offset_ms / 1000`。
    /// 同一时刻只保留一个切点，再按时间排序。
    static func splitPoints(
        notes: [MidiNoteEvent],
        quantize: Int,
        bpm: Double,
        offsetMs: Double
    ) -> [Double] {
        let safeQuantize = max(quantize, 1)
        let safeBpm = bpm == 0 ? 120 : bpm
        let secondsPerBeat = 60 / safeBpm
        var unique = Set<Double>()
        for note in notes {
            let beat = Double(note.position) / Double(safeQuantize)
            unique.insert(secondsPerBeat * beat + offsetMs / 1000)
        }
        return unique.sorted()
    }

    /// 对照 `"%s/%s_%03d.wav"`，下标从 1 起。
    static func outputFileName(prefix: String, indexFromZero: Int) -> String {
        String(format: "%@_%03d.wav", prefix, indexFromZero + 1)
    }

    /// 每个切点对应 `[start, end)` 采样下标，含全部声道。最后一段接到文件末尾。
    static func sliceRanges(wav: BmhelperPcmWav, times: [Double]) -> [(start: Int, end: Int)] {
        let channels = max(wav.channels, 1)
        let sampleRate = max(wav.sampleRate, 1)
        let totalFrames = wav.samples.count / channels
        let duration = Double(totalFrames) / Double(sampleRate)
        var ranges: [(start: Int, end: Int)] = []
        ranges.reserveCapacity(times.count)
        for (index, startTime) in times.enumerated() {
            let endTime = index + 1 < times.count ? times[index + 1] : duration
            let startFrame = max(Int(startTime * Double(sampleRate)), 0)
            let frameCount = max(Int((endTime - startTime) * Double(sampleRate)), 0)
            let clampedStart = min(startFrame, totalFrames)
            let clampedCount = min(frameCount, max(totalFrames - clampedStart, 0))
            let startSample = clampedStart * channels
            let endSample = startSample + clampedCount * channels
            ranges.append((start: startSample, end: endSample))
        }
        return ranges
    }

    static func slice(wav: BmhelperPcmWav, times: [Double]) -> [BmhelperPcmWav] {
        let channels = max(wav.channels, 1)
        let sampleRate = max(wav.sampleRate, 1)
        return sliceRanges(wav: wav, times: times).map { range in
            BmhelperPcmWav(
                sampleRate: sampleRate,
                channels: channels,
                samples: Array(wav.samples[range.start..<range.end])
            )
        }
    }

    static func splitFile(
        input: URL,
        outputDirectory: URL,
        prefix: String,
        notes: [MidiNoteEvent],
        quantize: Int,
        bpm: Double,
        offsetMs: Double
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
        let wav: BmhelperPcmWav
        do {
            wav = try BmhelperWavIO.read(Data(contentsOf: input))
        } catch {
            throw BmhelperWavSplitError.couldNotReadInput(input.path)
        }
        let times = splitPoints(notes: notes, quantize: quantize, bpm: bpm, offsetMs: offsetMs)
        let parts = slice(wav: wav, times: times)
        var urls: [URL] = []
        for (index, part) in parts.enumerated() {
            let name = outputFileName(prefix: prefix, indexFromZero: index)
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
}
