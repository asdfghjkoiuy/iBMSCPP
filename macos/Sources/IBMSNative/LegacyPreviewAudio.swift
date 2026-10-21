import AVFoundation
import Foundation
import os

/// 谱面音的类别。过滤只影响还没触发的 cue，不丢掉已经准备好的资源。
enum PreviewAudioKind: Hashable, Sendable {
    case bgm
    case key
    case mine
}

/// 一条要发声的音符：拍点 + `#WAVxx` 两位键。`kind` 缺省是 keysound。
struct PreviewAudioNote: Equatable {
    var beat: Double
    var wavToken: String
    var kind: PreviewAudioKind = .key
}

/// 预听用的速度信息。STOP 的停顿秒数必须来自核心时间表，不在这里用单位自己换算。
struct PreviewAudioTiming: Equatable {
    var headerBPM: Double
    var bpmEvents: [(beat: Double, bpm: Double)]
    var stopEvents: [(beat: Double, durationSeconds: Double)]

    init(
        headerBPM: Double,
        bpmEvents: [(beat: Double, bpm: Double)],
        stopEvents: [(beat: Double, durationSeconds: Double)] = []
    ) {
        self.headerBPM = headerBPM
        self.bpmEvents = bpmEvents
        self.stopEvents = stopEvents
    }

    static func == (lhs: PreviewAudioTiming, rhs: PreviewAudioTiming) -> Bool {
        lhs.headerBPM == rhs.headerBPM
            && lhs.bpmEvents.count == rhs.bpmEvents.count
            && zip(lhs.bpmEvents, rhs.bpmEvents).allSatisfy { $0.beat == $1.beat && $0.bpm == $1.bpm }
            && lhs.stopEvents.count == rhs.stopEvents.count
            && zip(lhs.stopEvents, rhs.stopEvents).allSatisfy {
                $0.beat == $1.beat && $0.durationSeconds == $1.durationSeconds
            }
    }
}

/// 排好的一发：从 `fromBeat` 算起的秒数，以及要播的 WAV 键。
struct PreviewAudioHit: Equatable {
    var seconds: Double
    var wavToken: String
    var kind: PreviewAudioKind = .key
}

/// 预览要显示哪一侧。画面和 BGA 共用这一份，不各做一套播放器。
enum PreviewPlayerSide: String, CaseIterable {
    case both
    case onePlayer
    case twoPlayer
}

/// BGA 叠层。`poor` 只在失误时盖住基础层，正常自动播放不盖。
enum PreviewBGALayer: String, Equatable {
    case base
    case layer
    case poor
}

struct PreviewBGAAsset: Equatable {
    var id: String
    var fileName: String
}

struct PreviewBGAEvent: Equatable {
    var beat: Double
    var assetID: String
    var layer: PreviewBGALayer
}

/// 一条可见车道。播放器不绘制；画面只消费这份快照。
/// `player` 为 1 或 2，缺省是 1P，旧调用不用改。
struct PreviewVisualLane: Equatable {
    var id: String
    var title: String
    var isScratch: Bool = false
    var player: Int = 1
}

/// 一颗可见音符。长音的头尾都落在同一条车道上，短音起止拍相同。
struct PreviewVisualNote: Equatable {
    var laneID: String
    var startBeat: Double
    var endBeat: Double
}

/// 当前未保存谱面的画面快照。播放器不读它，窗口用 `endBeat` 决定画面走到哪一拍。
struct PreviewChartSnapshot: Equatable {
    var title: String = ""
    var lanes: [PreviewVisualLane] = []
    var notes: [PreviewVisualNote] = []
    var barBeats: [Double] = []
    var endBeat: Double = 0
    var bgaAssets: [PreviewBGAAsset] = []
    var bgaEvents: [PreviewBGAEvent] = []
}

/// 预览窗向主窗要的当前谱面。Play Here 的拍由调用方给。
struct PreviewAudioDocumentContext {
    var documentData: Data
    var chartDirectory: URL?
    var notes: [PreviewAudioNote]
    var timing: PreviewAudioTiming
    /// 谱面区没有独立播放头。拿不到当前拍时用 0。
    var playHereBeat: Double
    /// 打开 BMSON 时，播放头按 BmsONE 的缓冲延迟走，BMS 不套。
    var appliesBmsonPlayhead = false
    /// 当前未保存内容的车道和音符。默认空，旧调用可以不传。
    var visualChart: PreviewChartSnapshot = PreviewChartSnapshot()
}

/// 原版 `#WAV` 解析和按拍排时间表。不读 BMSON，不启动外置播放器。
enum LegacyPreviewAudio {
    /// 从 BMS 文本读 `#WAVxx` 定义。键是两位 01–ZZ，大小写不敏感，后写覆盖先写。
    /// 不展开 RANDOM / IF；这些行本身不会当成 WAV。
    static func parseWavTable(from text: String) -> [String: String] {
        var table: [String: String] = [:]
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 6 else { return }
            let prefixEnd = trimmed.index(trimmed.startIndex, offsetBy: 4)
            guard trimmed[trimmed.startIndex..<prefixEnd].uppercased() == "#WAV" else { return }
            let keyEnd = trimmed.index(prefixEnd, offsetBy: 2)
            let key = String(trimmed[prefixEnd..<keyEnd])
            guard isWavKey(key) else { return }
            let fileName = String(trimmed[keyEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty else { return }
            table[key.uppercased()] = fileName
        }
        return table
    }

    static func parseWavTable(from data: Data) -> [String: String] {
        parseWavTable(from: decodeBMSText(data))
    }

    /// 两位键对应的文件名。没有定义时是 `nil`。
    static func fileName(forToken token: String, in table: [String: String]) -> String? {
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isWavKey(key) else { return nil }
        let name = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// 原版只存文件名时，拼到谱面所在目录。已经是绝对路径就原样用。
    static func resolveWavURL(fileName: String, chartDirectory: URL?) -> URL? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        if let chartDirectory {
            return chartDirectory.appendingPathComponent(trimmed)
        }
        return URL(fileURLWithPath: trimmed)
    }

    /// iBMSC `CheckFilename`：要的 `.ogg` / `.wav` 不在时，改用同名的另一种。
    /// 两种都没有时仍返回原来的路径，由播放器再判断文件在不在。
    static func resolveAudioURL(fileName: String, chartDirectory: URL?) -> URL? {
        guard let url = resolveWavURL(fileName: fileName, chartDirectory: chartDirectory) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let ext = url.pathExtension.lowercased()
        let swap: String?
        if ext == "ogg" {
            swap = "wav"
        } else if ext == "wav" {
            swap = "ogg"
        } else {
            swap = nil
        }
        if let swap {
            let other = url.deletingPathExtension().appendingPathExtension(swap)
            if FileManager.default.fileExists(atPath: other.path) {
                return other
            }
        }
        return url
    }

    /// 已播出的秒数对应哪一拍。和 `scheduleHits` 同一套积分：先走 BPM，再把区间里的 STOP 加进去。
    /// 停在某一拍上时，播放头停在那一拍，等停顿过完再往前。
    static func beat(afterSeconds: Double, fromBeat: Double, timing: PreviewAudioTiming) -> Double {
        guard afterSeconds.isFinite, fromBeat.isFinite else { return fromBeat }
        if afterSeconds <= 0 {
            return fromBeat
        }
        let header = usableBPM(timing.headerBPM)
        let changes = timing.bpmEvents
            .filter { $0.bpm > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        let stops = timing.stopEvents
            .filter { $0.durationSeconds > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        var bpm = header
        for event in changes where event.beat <= fromBeat {
            bpm = usableBPM(event.bpm)
        }
        var remaining = afterSeconds
        var cursor = fromBeat
        var changeIndex = changes.firstIndex { $0.beat > fromBeat } ?? changes.count
        var stopIndex = stops.firstIndex { $0.beat >= fromBeat } ?? stops.count
        while remaining > 0 {
            let nextChange = changeIndex < changes.count ? changes[changeIndex].beat : Double.infinity
            let nextStop = stopIndex < stops.count ? stops[stopIndex].beat : Double.infinity
            if nextStop <= nextChange, nextStop.isFinite {
                if nextStop > cursor {
                    let segment = (nextStop - cursor) * 60 / bpm
                    if remaining <= segment {
                        return cursor + remaining * bpm / 60
                    }
                    remaining -= segment
                    cursor = nextStop
                }
                while stopIndex < stops.count && stops[stopIndex].beat == cursor {
                    let pause = stops[stopIndex].durationSeconds
                    if remaining <= pause {
                        return cursor
                    }
                    remaining -= pause
                    stopIndex += 1
                }
            } else if nextChange.isFinite {
                let segment = (nextChange - cursor) * 60 / bpm
                if remaining <= segment {
                    return cursor + remaining * bpm / 60
                }
                remaining -= segment
                cursor = nextChange
                bpm = usableBPM(changes[changeIndex].bpm)
                changeIndex += 1
            } else {
                return cursor + remaining * bpm / 60
            }
        }
        return cursor
    }

    /// 按拍点排成（秒, WAV 键）。BPM 段用 60/BPM 积分；STOP 把核心给出的停顿秒数加进去。
    /// 同拍的 STOP 加在该拍音符之后：`fromBeat <= stopBeat < noteBeat`。
    /// 恒速、无 STOP 时：秒数 = (拍 - 起点拍) × 60 / BPM。例如 120 BPM 下 4 拍是 2 秒。
    static func scheduleHits(
        notes: [PreviewAudioNote],
        timing: PreviewAudioTiming,
        fromBeat: Double
    ) -> [PreviewAudioHit] {
        let prepared = preparedTiming(timing)
        return notes
            .compactMap { note -> PreviewAudioHit? in
                guard note.beat.isFinite, note.beat >= fromBeat else { return nil }
                let token = note.wavToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isWavKey(token) else { return nil }
                let seconds = seconds(
                    fromBeat: fromBeat,
                    toBeat: note.beat,
                    headerBPM: prepared.headerBPM,
                    bpmEvents: prepared.changes,
                    stopEvents: prepared.stops
                )
                return PreviewAudioHit(seconds: seconds, wavToken: token.uppercased(), kind: note.kind)
            }
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return lhs.wavToken < rhs.wavToken
            }
    }

    /// BPM / STOP / 小节比 / 背景图通道不发声。
    static func isAudibleChannel(_ channel: String) -> Bool {
        switch channel.uppercased() {
        case "02", "03", "04", "06", "07", "08", "09", "SC":
            return false
        default:
            return !channel.isEmpty
        }
    }

    static func decodeBMSText(_ data: Data) -> String {
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        if let text = String(data: payload, encoding: .shiftJIS) {
            return text
        }
        return String(decoding: payload, as: UTF8.self)
    }

    static func isWavKey(_ key: String) -> Bool {
        guard key.count == 2 else { return false }
        let chars = Array(key.uppercased())
        guard let high = base36Value(chars[0]), let low = base36Value(chars[1]) else { return false }
        let index = high * 36 + low
        return index >= 1 && index <= 1295
    }

    private static func base36Value(_ character: Character) -> Int? {
        switch character {
        case "0"..."9":
            return Int(character.asciiValue! - UInt8(ascii: "0"))
        case "A"..."Z":
            return Int(character.asciiValue! - UInt8(ascii: "A")) + 10
        default:
            return nil
        }
    }

    private static func usableBPM(_ bpm: Double) -> Double {
        bpm > 0 && bpm.isFinite ? bpm : 120
    }

    /// BPM / STOP 先滤一次再排序。`scheduleHits` 和逐音符的 `travelSeconds` 共用这一份。
    fileprivate struct PreparedAudioTiming {
        var headerBPM: Double
        var changes: [(beat: Double, bpm: Double)]
        var stops: [(beat: Double, durationSeconds: Double)]
    }

    fileprivate static func preparedTiming(_ timing: PreviewAudioTiming) -> PreparedAudioTiming {
        PreparedAudioTiming(
            headerBPM: usableBPM(timing.headerBPM),
            changes: timing.bpmEvents
                .filter { $0.bpm > 0 && $0.beat.isFinite }
                .sorted { $0.beat < $1.beat },
            stops: timing.stopEvents
                .filter { $0.durationSeconds > 0 && $0.beat.isFinite }
                .sorted { $0.beat < $1.beat }
        )
    }

    /// 从起点拍走到目标拍的秒数，和 `scheduleHits` 用同一套 BPM / STOP 积分。
    /// 目标不在起点之后时是 0。画面结束拍走这里，避免和音符各算各的。
    fileprivate static func travelSeconds(
        fromBeat: Double,
        toBeat: Double,
        timing: PreviewAudioTiming
    ) -> Double {
        travelSeconds(fromBeat: fromBeat, toBeat: toBeat, prepared: preparedTiming(timing))
    }

    fileprivate static func travelSeconds(
        fromBeat: Double,
        toBeat: Double,
        prepared: PreparedAudioTiming
    ) -> Double {
        guard fromBeat.isFinite, toBeat.isFinite, toBeat > fromBeat else { return 0 }
        return seconds(
            fromBeat: fromBeat,
            toBeat: toBeat,
            headerBPM: prepared.headerBPM,
            bpmEvents: prepared.changes,
            stopEvents: prepared.stops
        )
    }

    private static func seconds(
        fromBeat: Double,
        toBeat: Double,
        headerBPM: Double,
        bpmEvents: [(beat: Double, bpm: Double)],
        stopEvents: [(beat: Double, durationSeconds: Double)]
    ) -> Double {
        var bpm = headerBPM
        for event in bpmEvents where event.beat <= fromBeat {
            bpm = usableBPM(event.bpm)
        }
        var time = 0.0
        var cursor = fromBeat
        for event in bpmEvents where event.beat > fromBeat && event.beat < toBeat {
            time += (event.beat - cursor) * 60 / bpm
            cursor = event.beat
            bpm = usableBPM(event.bpm)
        }
        time += (toBeat - cursor) * 60 / bpm
        for stop in stopEvents where fromBeat <= stop.beat && stop.beat < toBeat {
            time += stop.durationSeconds
        }
        return time
    }
}

/// 60Hz 画面时钟。`Timer` 强引用本对象，本对象只弱引用播放器。
/// 定时器加在主线程 RunLoop 上，回调用 `MainActor.assumeIsolated` 进入播放器，
/// 不靠 `@unchecked Sendable` 把跨线程访问藏起来。播放器释放时拆掉定时器，避免 RunLoop 把时钟留住。
@MainActor
private final class PreviewElapsedClock: NSObject {
    static var liveCount = 0
    weak var player: LegacyPreviewAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        Self.liveCount += 1
    }

    func start() {
        invalidate()
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(fire(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    /// ObjC 定时器回调不在 Swift 的主 actor 隔离里，但这个定时器只加在 `RunLoop.main`。
    /// 不在主 actor 上就会在 `assumeIsolated` 处停住，而不是静默改别的线程上的状态。
    @objc nonisolated func fire(_ timer: Timer) {
        MainActor.assumeIsolated {
            guard let player = self.player else {
                self.invalidate()
                return
            }
            // 外部驱动已经接管时，这一拍不能再交给定时器，否则和 advance 各走一次。
            guard !player.presentationClockExternallyDriven else {
                self.invalidate()
                return
            }
            player.tickElapsed()
        }
    }

    isolated deinit {
        invalidate()
        Self.liveCount -= 1
    }
}

/// 谱面资源缓存和同时发声的上限。超过后按 UA2 说明淘汰或抢占，不按音符个数分配播放器。
enum PreviewAudioLimits {
    static let maxCachedResources = 128
    static let maxCachedBytes = 64 * 1024 * 1024
    static let maxVoices = 32
    /// 墙上提前量。谱面地平线是它乘当前倍率，避免 4 倍时负 origin 把开场队列削没。
    static let wallLookahead = 0.20
    /// 声部和画面共用的提前量，让 play(at:) 落在排程完成之后。
    static let originLead = 0.05
    /// 回补间隔。短于 32 个密集音在 4 倍速下的墙钟覆盖。
    static let pumpInterval = 0.04
    /// 不超过这一大小的 Float32 可以留在内存。更长的 PCM WAV 按文件分块播放。
    static let maxInlinePCMBytes = 1024 * 1024
    /// 长 BGM 每一块至少 3 秒，避免 4 倍速把 1 秒块压成过短的墙钟。
    static let streamChunkSeconds = 3.0

    static func chartLookahead(rate: Double) -> Double {
        let scale = min(max(rate, minimumPlaybackRate), maximumPlaybackRate)
        return wallLookahead * scale
    }
    /// `AVAudioUnitVarispeed` 的范围。不按文件采样率或旧的 100000 Hz 再收紧。
    static let minimumPlaybackRate = 0.25
    static let maximumPlaybackRate = 4.0

    /// 非有限或非正的请求返回 nil，调用方保持原倍率。
    static func clampPlaybackRate(_ rate: Double) -> Double? {
        guard rate.isFinite, rate > 0 else { return nil }
        return min(max(rate, minimumPlaybackRate), maximumPlaybackRate)
    }
}

/// 谱面资源准备状态。窗口可以不设置回调；播放器仍会在 `.ready` 同一轮交出 elapsed 0。
enum PreviewAudioPreparationState: Equatable, Sendable {
    /// 后台还在读这一代资源。画面时钟还没有起点。
    case preparing
    /// 开场资源已钉住，声部共用同一个未来 host 起点，随后交出 elapsed 0。
    case ready
    /// 这一代在就绪前被 stop、重播或切谱取消。
    case cancelled
    /// 本谱开场窗口放不进工作集预算。预算不够现在改为分块准备，不再走这里。
    case shortfall
    /// 解码、格式或引擎失败。不发 `.ready`。原因在 `diagnosticPreparationFailure`。
    case failed
}

private struct VoiceFormat: Hashable {
    var sampleRate: Int
    var channels: Int
}

private struct PreviewPreparedPCM: Sendable {
    var sampleRate: Double
    var channelCount: Int
    var frameCount: Int
    /// 每个声道一块连续 Float32，声道之间首尾相接。
    var planarFloat32: Data

    var duration: Double {
        guard sampleRate > 0, frameCount > 0 else { return 0 }
        return Double(frameCount) / sampleRate
    }

    var format: VoiceFormat {
        VoiceFormat(sampleRate: Int(sampleRate.rounded()), channels: channelCount)
    }
}

enum PreviewAudioLoadFailure: String, Equatable, Sendable {
    case missingFile
    case unsupported
    case decodeFailed
    case capacity
}

struct PreviewFileAudio: Sendable {
    var url: URL
    var sampleRate: Double
    var channelCount: Int
    var frameCount: Int
    var sourceBytes: Int
    var temporary: Bool
}

/// 一条 cue 会占用文件句柄的时间。worker 用它决定要开几份 `AVAudioFile`。
private struct PreviewFileCue: Sendable {
    var chartSeconds: Double
    var fileOffset: Double
}

/// 把已经打开的 `AVAudioFile` 从准备线程交到主 actor。
/// 盒子本身可以跨线程传递；文件对象只有当前持有者能碰。`take()` 之后原来的一方必须放手。
private final class PreviewAudioFileHandoff: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var taken = false

    init(file: AVAudioFile) {
        self.file = file
    }

    func take() -> AVAudioFile? {
        lock.lock()
        defer { lock.unlock() }
        guard !taken else { return nil }
        taken = true
        let value = file
        file = nil
        return value
    }
}

private struct PreviewLoadResult: Sendable {
    var pcm: PreviewPreparedPCM?
    var file: PreviewFileAudio?
    var failure: PreviewAudioLoadFailure?
    var readOnMain: Bool
    /// 这一次真正物化的解码字节。文件分块播放时是 0；解码器交回整段 WAV 时是那份 Data。
    var decodedBytes: Int = 0
    var sourceBytes: Int = 0
    /// 后台已经打开的读句柄。主 actor 取走后，触发路径不再 `AVAudioFile(forReading:)`。
    var handles: [PreviewAudioFileHandoff] = []
}

private enum PreviewPCMDecoder {
    static func load(
        url: URL,
        inlineRoom: Int,
        uses: [PreviewFileCue],
        reader: (@Sendable (URL) -> Data?)?,
        decoder: (@Sendable (URL) -> Data?)?,
        disk: (@Sendable (Bool) -> Void)?,
        traceOpen: (@Sendable (Bool) -> Void)?
    ) -> PreviewLoadResult {
        let readOnMain = Thread.isMainThread
        let resolved = LegacyPreviewAudio.resolveAudioURL(
            fileName: url.lastPathComponent,
            chartDirectory: url.deletingLastPathComponent()
        ) ?? url
        disk?(false)
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return PreviewLoadResult(failure: .missingFile, readOnMain: readOnMain)
        }
        if let layout = inspectWAV(url: resolved, disk: disk), layout.isIntegerPCM {
            let sourceBytes = fileSize(resolved)
            if layout.channels > 2 {
                return PreviewLoadResult(failure: .unsupported, readOnMain: readOnMain, sourceBytes: sourceBytes)
            }
            if layout.floatBytes > 0,
               layout.floatBytes <= PreviewAudioLimits.maxInlinePCMBytes,
               layout.floatBytes <= max(inlineRoom, 0) {
                if let pcm = inlinePCM(url: resolved, reader: reader, disk: disk) {
                    return PreviewLoadResult(
                        pcm: pcm,
                        readOnMain: readOnMain,
                        decodedBytes: pcm.planarFloat32.count,
                        sourceBytes: sourceBytes
                    )
                }
                return PreviewLoadResult(failure: .decodeFailed, readOnMain: readOnMain, sourceBytes: sourceBytes)
            }
            if layout.floatBytes <= 0 {
                return PreviewLoadResult(failure: .unsupported, readOnMain: readOnMain, sourceBytes: sourceBytes)
            }
            _ = uses
            _ = traceOpen
            return fileResult(
                url: resolved,
                layout: layout,
                sourceBytes: sourceBytes,
                temporary: false,
                decodedBytes: 0,
                readOnMain: readOnMain
            )
        }
        guard let decoder else {
            return PreviewLoadResult(failure: .unsupported, readOnMain: readOnMain, sourceBytes: fileSize(resolved))
        }
        guard let wav = decoder(resolved) else {
            return PreviewLoadResult(failure: .decodeFailed, readOnMain: readOnMain, sourceBytes: fileSize(resolved))
        }
        return adoptDecodedWAV(
            wav,
            readOnMain: readOnMain,
            inlineRoom: inlineRoom,
            uses: uses,
            disk: disk,
            traceOpen: traceOpen
        )
    }

    /// 解码器只能交回整段 WAV。小的留在内存；大的写成临时文件再分块，不再转成整段 Float32。
    private static func adoptDecodedWAV(
        _ wav: Data,
        readOnMain: Bool,
        inlineRoom: Int,
        uses: [PreviewFileCue],
        disk: (@Sendable (Bool) -> Void)?,
        traceOpen: (@Sendable (Bool) -> Void)?
    ) -> PreviewLoadResult {
        guard let layout = inspectWAV(data: wav), layout.isIntegerPCM, layout.floatBytes > 0, layout.channels <= 2 else {
            return PreviewLoadResult(failure: .decodeFailed, readOnMain: readOnMain, decodedBytes: wav.count)
        }
        if layout.floatBytes <= PreviewAudioLimits.maxInlinePCMBytes, layout.floatBytes <= max(inlineRoom, 0),
           let pcm = parseWAV(wav) {
            return PreviewLoadResult(
                pcm: pcm,
                readOnMain: readOnMain,
                decodedBytes: pcm.planarFloat32.count,
                sourceBytes: wav.count
            )
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-preview-wav-\(UUID().uuidString).wav")
        disk?(true)
        do {
            try wav.write(to: url, options: .atomic)
        } catch {
            return PreviewLoadResult(failure: .capacity, readOnMain: readOnMain, decodedBytes: wav.count)
        }
        _ = uses
        _ = traceOpen
        return fileResult(
            url: url,
            layout: layout,
            sourceBytes: wav.count,
            temporary: true,
            decodedBytes: wav.count,
            readOnMain: readOnMain
        )
    }

    private static func fileResult(
        url: URL,
        layout: WAVLayout,
        sourceBytes: Int,
        temporary: Bool,
        decodedBytes: Int,
        readOnMain: Bool
    ) -> PreviewLoadResult {
        return PreviewLoadResult(
            file: PreviewFileAudio(
                url: url,
                sampleRate: Double(layout.sampleRate),
                channelCount: layout.channels,
                frameCount: layout.frameCount,
                sourceBytes: sourceBytes,
                temporary: temporary
            ),
            readOnMain: readOnMain,
            decodedBytes: decodedBytes,
            sourceBytes: sourceBytes
        )
    }

    /// 句柄只跟真实发声重叠走。不重叠的音可以共用一个文件，把多段 sampleTime 排进去。
    private static func readerCount(duration: Double, uses: [PreviewFileCue]) -> Int {
        guard duration > 0 else { return 1 }
        var intervals: [(Double, Double)] = []
        for use in uses {
            let remain = duration - max(0, use.fileOffset)
            guard remain > 0.001 else { continue }
            intervals.append((use.chartSeconds, use.chartSeconds + remain))
        }
        let overlap = max(1, maxOverlap(intervals))
        return min(PreviewAudioLimits.maxVoices, overlap)
    }

    private static func maxOverlap(_ intervals: [(Double, Double)]) -> Int {
        var events: [(time: Double, delta: Int)] = []
        for (start, end) in intervals where end > start {
            events.append((start, 1))
            events.append((end, -1))
        }
        events.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.delta < rhs.delta
        }
        var current = 0
        var peak = 0
        for event in events {
            current += event.delta
            peak = max(peak, current)
        }
        return peak
    }

    /// 在准备线程打开。回调参数是这次打开是否发生在主线程。
    private static func openReadHandles(
        url: URL,
        count: Int,
        trace: (@Sendable (Bool) -> Void)?
    ) -> [PreviewAudioFileHandoff]? {
        guard count > 0 else { return nil }
        var opened: [PreviewAudioFileHandoff] = []
        opened.reserveCapacity(count)
        for _ in 0..<count {
            trace?(Thread.isMainThread)
            guard let file = try? AVAudioFile(
                forReading: url,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            ) else { return nil }
            opened.append(PreviewAudioFileHandoff(file: file))
        }
        return opened
    }

    private static func inlinePCM(
        url: URL,
        reader: (@Sendable (URL) -> Data?)?,
        disk: (@Sendable (Bool) -> Void)?
    ) -> PreviewPreparedPCM? {
        let bytes: Data?
        if let reader {
            bytes = reader(url)
        } else {
            disk?(false)
            bytes = try? Data(contentsOf: url)
        }
        guard let bytes else { return nil }
        return parseWAV(bytes)
    }

    private struct WAVLayout {
        var audioFormat: Int
        var channels: Int
        var sampleRate: Int
        var bits: Int
        var frameCount: Int
        var isIntegerPCM: Bool {
            audioFormat == 1 && channels >= 1 && channels <= 8 && sampleRate > 0 && (bits == 8 || bits == 16)
        }
        var floatBytes: Int {
            guard isIntegerPCM else { return 0 }
            return frameCount * channels * MemoryLayout<Float>.size
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size ?? 0
    }

    private static func inspectWAV(url: URL, disk: (@Sendable (Bool) -> Void)?) -> WAVLayout? {
        disk?(false)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        guard end >= 12 else { return nil }
        try? handle.seek(toOffset: 0)
        guard let riff = try? handle.read(upToCount: 12), riff.count == 12,
              riff.prefix(4) == Data("RIFF".utf8),
              riff.dropFirst(8).prefix(4) == Data("WAVE".utf8) else { return nil }
        var cursor = 12
        var audioFormat = 0
        var channels = 0
        var sampleRate = 0
        var bits = 0
        var dataBytes: Int?
        while cursor + 8 <= end {
            try? handle.seek(toOffset: UInt64(cursor))
            guard let chunk = try? handle.read(upToCount: 8), chunk.count == 8 else { return nil }
            let size = Int(u32(chunk, 4))
            let payload = cursor + 8
            guard size >= 0, payload <= end else { return nil }
            if chunk.prefix(4) == Data("fmt ".utf8), size >= 16 {
                guard let fmt = try? handle.read(upToCount: 16), fmt.count >= 16 else { return nil }
                audioFormat = Int(u16(fmt, 0))
                channels = Int(u16(fmt, 2))
                sampleRate = Int(u32(fmt, 4))
                bits = Int(u16(fmt, 14))
            } else if chunk.prefix(4) == Data("data".utf8) {
                dataBytes = size
                break
            }
            let padded = size + (size & 1)
            cursor = payload + padded
        }
        guard let dataBytes, channels > 0, bits > 0 else { return nil }
        let bytesPerFrame = channels * max(bits, 1) / 8
        guard bytesPerFrame > 0 else { return nil }
        return WAVLayout(
            audioFormat: audioFormat,
            channels: channels,
            sampleRate: sampleRate,
            bits: bits,
            frameCount: dataBytes / bytesPerFrame
        )
    }

    private static func inspectWAV(data: Data) -> WAVLayout? {
        guard data.count >= 12,
              data.prefix(4) == Data("RIFF".utf8),
              data.dropFirst(8).prefix(4) == Data("WAVE".utf8) else { return nil }
        var offset = 12
        var audioFormat = 0
        var channels = 0
        var sampleRate = 0
        var bits = 0
        var dataBytes: Int?
        while offset + 8 <= data.count {
            let size = Int(u32(data, offset + 4))
            let payload = offset + 8
            guard size >= 0, payload <= data.count else { return nil }
            if data.subdata(in: offset..<(offset + 4)) == Data("fmt ".utf8), size >= 16, payload + 16 <= data.count {
                audioFormat = Int(u16(data, payload))
                channels = Int(u16(data, payload + 2))
                sampleRate = Int(u32(data, payload + 4))
                bits = Int(u16(data, payload + 14))
            } else if data.subdata(in: offset..<(offset + 4)) == Data("data".utf8) {
                dataBytes = min(size, data.count - payload)
                break
            }
            offset = payload + size + (size & 1)
        }
        guard let dataBytes, channels > 0, bits > 0 else { return nil }
        let bytesPerFrame = channels * max(bits, 1) / 8
        guard bytesPerFrame > 0 else { return nil }
        return WAVLayout(
            audioFormat: audioFormat,
            channels: channels,
            sampleRate: sampleRate,
            bits: bits,
            frameCount: dataBytes / bytesPerFrame
        )
    }

    /// 只接受整数 PCM WAV。其余格式交给 `decodeToWav` 先变成这种 WAV。
    private static func parseWAV(_ data: Data) -> PreviewPreparedPCM? {
        guard data.count >= 12 else { return nil }
        guard data.subdata(in: 0..<4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else { return nil }
        var offset = 12
        var audioFormat = 0
        var channels = 0
        var sampleRate = 0
        var bits = 0
        var pcm: Data?
        while offset + 8 <= data.count {
            let identifier = data.subdata(in: offset..<(offset + 4))
            let size = Int(u32(data, offset + 4))
            let payload = offset + 8
            guard size >= 0, payload + size <= data.count else { return nil }
            if identifier == Data("fmt ".utf8), size >= 16 {
                audioFormat = Int(u16(data, payload))
                channels = Int(u16(data, payload + 2))
                sampleRate = Int(u32(data, payload + 4))
                bits = Int(u16(data, payload + 14))
            } else if identifier == Data("data".utf8) {
                pcm = data.subdata(in: payload..<(payload + size))
            }
            offset = payload + size + (size & 1)
        }
        guard audioFormat == 1, channels >= 1, channels <= 8, sampleRate > 0, pcm != nil else { return nil }
        guard bits == 8 || bits == 16 else { return nil }
        let bytesPerFrame = channels * bits / 8
        guard bytesPerFrame > 0, let pcm else { return nil }
        let frames = pcm.count / bytesPerFrame
        guard frames > 0 else { return nil }
        let sampleCount = frames * channels
        var planes = [Float](repeating: 0, count: sampleCount)
        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let sampleIndex = frame * channels + channel
                    let planeIndex = channel * frames + frame
                    if bits == 8 {
                        let byte = base.load(fromByteOffset: sampleIndex, as: UInt8.self)
                        planes[planeIndex] = (Float(byte) - 128) / 128
                    } else {
                        let byteOffset = sampleIndex * 2
                        let low = UInt16(base.load(fromByteOffset: byteOffset, as: UInt8.self))
                        let high = UInt16(base.load(fromByteOffset: byteOffset + 1, as: UInt8.self))
                        let signed = Int16(bitPattern: low | (high << 8))
                        planes[planeIndex] = Float(signed) / 32768
                    }
                }
            }
        }
        var packed = Data(count: planes.count * MemoryLayout<Float>.size)
        packed.withUnsafeMutableBytes { destination in
            planes.withUnsafeBytes { source in
                destination.copyMemory(from: source)
            }
        }
        return PreviewPreparedPCM(
            sampleRate: Double(sampleRate),
            channelCount: channels,
            frameCount: frames,
            planarFloat32: packed
        )
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

/// 串行解码，避免同时进入可能不可重入的 `decodeToWav`。不占用主 actor。
/// `inlineRemaining` 是这一代还能放进驻留预算的 PCM 字节，按调用顺序扣减。
private actor PreviewAudioPrepareWorker {
    private var inlineRemaining = 0

    func beginInlineBudget(_ bytes: Int) {
        inlineRemaining = max(0, bytes)
    }

    func load(
        url: URL,
        uses: [PreviewFileCue],
        reader: (@Sendable (URL) -> Data?)?,
        decoder: (@Sendable (URL) -> Data?)?,
        disk: (@Sendable (Bool) -> Void)?,
        traceOpen: (@Sendable (Bool) -> Void)?
    ) -> PreviewLoadResult {
        let result = PreviewPCMDecoder.load(
            url: url,
            inlineRoom: inlineRemaining,
            uses: uses,
            reader: reader,
            decoder: decoder,
            disk: disk,
            traceOpen: traceOpen
        )
        if let pcm = result.pcm {
            inlineRemaining = max(0, inlineRemaining - pcm.planarFloat32.count)
        }
        return result
    }

    func removeTemporary(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}


final class LegacyPreviewAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static var liveElapsedClockCount: Int { PreviewElapsedClock.liveCount }

    private var players: [AVAudioPlayer] = []
    private var pending: [DispatchWorkItem] = []
    private let elapsedClock = PreviewElapsedClock()
    private let prepareWorker = PreviewAudioPrepareWorker()
    private let session = PreviewUnifiedAudioSession()
    private var cues: [ChartCue] = []
    private var carries: [CarryCue] = []
    private var prepared: [String: PreparedAsset] = [:]
    private var prepareLeft = 0
    private var preparationOutstanding = false
    private var anchorItem: DispatchWorkItem?
    private var originEmitted = false
    /// 这一代已经把 `.ready` 交给调用方。halt 置位的 `originEmitted` 只是拦住迟到起点，不能当成已就绪。
    private var readyDelivered = false
    private var transportCut = false
    private var baselineScheduled = 0
    private var chartEndSeconds = 0.0
    private var timelineOpen = false
    private var playbackGeneration: UInt = 0
    fileprivate var presentationClockExternallyDriven = false
    var decodeToWav: (@Sendable (URL) -> Data?)?
    var readResourceBytes: (@Sendable (URL) -> Data?)?
    var onPreparationStateChanged: ((PreviewAudioPreparationState) -> Void)?
    /// 测试在 worker/adapter 的 onReady 进入 `emitOrigin` 之前插入。生产路径保持 nil，不增加播放公共面。
    var testBeforeWorkerReady: ((UInt) -> Void)?
    /// 测试不把这一代交给真实设备。生产路径保持 false。
    var testSuppressSessionSubmit = false
    private(set) var diagnosticMainThreadResourceLoads = 0
    private(set) var diagnosticResourceLoads = 0
    private(set) var diagnosticEngineFailure: String?
    var resourceByteBudget = PreviewAudioLimits.maxCachedBytes
    var traceDiskAccess: (@Sendable (Bool) -> Void)?
    var traceFileOpen: (@Sendable (Bool) -> Void)?
    private var audibleKinds: Set<PreviewAudioKind> = [.bgm, .key]
    public private(set) var isChartPaused = false
    private var pausedBeforeStart = false
    private var pausedElapsed: Double?
    private var pausedWall: Double?
    private var requestedRateRaw = 1.0
    private var chartRate = 1.0
    private var preparedVoicePlan: [VoiceFormat: Int] = [:]
    private var loadFailures: [String: PreviewAudioLoadFailure] = [:]
    private(set) var requestedPlaybackRate: Double = 1
    private(set) var diagnosticSourceFileBytes = 0
    private(set) var diagnosticPeakDecodedBytes = 0
    private var decodedHeld = 0
    var diagnosticStreamBlockBytes: Int { session.stats().streamBlockBytes }
    var diagnosticPCMCopies: Int { session.stats().pcmCopies }
    var diagnosticLateSchedules: Int { session.stats().late }
    var diagnosticResidentPCMBytes: Int { session.stats().residentBytes }
    var diagnosticInflightScheduledBytes: Int { session.stats().inflightBytes }
    var diagnosticFileBackedResources: Int { session.stats().fileBacked }
    private(set) var diagnosticPreparationFailure: String?
    var recordOutputForTests = false
    private(set) var diagnosticShortfallCues = 0
    private(set) var diagnosticLateResourceMisses = 0
    private(set) var diagnosticCueCount = 0
    var diagnosticLastPumpCueTouches: Int { session.stats().cueTouchesLast }
    var diagnosticMaxPumpCueTouches: Int { session.stats().cueTouchesMax }
    var diagnosticTotalCueTouches: Int { session.stats().cueTouchesTotal }
    var diagnosticScheduledCues: Int { session.stats().scheduled }
    var diagnosticScheduleStops: Int { session.stats().scheduleStops }
    var diagnosticSpilledResources: Int { session.stats().fileBacked }
    var diagnosticCurrentlySpilled: Int { session.stats().fileBacked }
    var diagnosticResidentResources: Int { session.stats().residentResources }
    var diagnosticVoiceCreations: Int { session.stats().voiceSlots }
    var diagnosticStolenVoices: Int { session.stats().stolen }
    var diagnosticDroppedVoices: Int { session.stats().dropped }
    var diagnosticDeferredScheduleCount: Int { max(0, session.stats().scheduled - baselineScheduled) }
    var diagnosticMaxDeferredScheduleSeconds: Double { session.stats().maxScheduleSeconds }
    var diagnosticClockSource: String { session.stats().clockSource }
    func outputTapSamples() -> [Float] { session.tapLeft() }
    var outputTapSampleRate: Double { 48_000 }
    func diagnosticVoiceTimelineSeconds() -> [Double] { session.stats().voiceStarts }
    var onElapsedSeconds: ((Double) -> Void)?
    public var presentationWallElapsedSeconds: Double { currentWallElapsed() }
    public func playbackWallElapsedSeconds() -> Double { currentWallElapsed() }
    var onPlaybackStopped: (() -> Void)?
    var onTimelineFinished: (() -> Void)?

    var soundingSampleCount: Int {
        if transportCut { return players.count }
        return players.count + session.stats().activeVoices
    }

    private struct ChartCue {
        var seconds: Double
        var key: String?
        var duration: Double
        var format: VoiceFormat?
        var kind: PreviewAudioKind = .key
        var fileOffsetSeconds: Double = 0
    }

    private struct CarryCue {
        var key: String
        var kind: PreviewAudioKind
        var offset: Double
    }

    private struct PreparedAsset {
        var pcm: PreviewPreparedPCM?
        var file: PreviewFileAudio?
    }

    override init() {
        super.init()
        session.onReady = { [weak self] generation in
            self?.receiveWorkerReady(generation: generation)
        }
        session.onFailed = { [weak self] generation, reason in
            self?.failPreparation(generation: generation, reason: reason)
        }
    }

    func playFile(url: URL, maxDurationSeconds: Double = 0, fadeOutSeconds: Double = 0) {
        halt(notify: true)
        startPlayer(url: url)
        scheduleDurationLimit(maxDurationSeconds: maxDurationSeconds, fadeOutSeconds: fadeOutSeconds)
    }

    func stop() { halt(notify: true) }

    public func pauseChart() {
        guard timelineOpen, !isChartPaused else { return }
        pausedElapsed = max(0, currentElapsed())
        pausedWall = max(0, currentWallElapsed())
        isChartPaused = true
        elapsedClock.invalidate()
        var job = session.currentJob()
        job.paused = true
        session.update(job)
        let generation = playbackGeneration
        onElapsedSeconds?(pausedElapsed ?? 0)
        guard playbackGeneration == generation, timelineOpen else { return }
    }

    public func resumeChart() {
        guard timelineOpen, isChartPaused else { return }
        let generation = playbackGeneration
        isChartPaused = false
        pausedBeforeStart = false
        pausedElapsed = nil
        pausedWall = nil
        var job = session.currentJob()
        job.paused = false
        job.rate = chartRate
        session.update(job)
        guard playbackGeneration == generation, timelineOpen, !isChartPaused else { return }
        if chartEndSeconds > 0 {
            startElapsedClock()
        } else {
            onElapsedSeconds?(0)
            closeTimeline(generation: generation)
        }
    }

    public func setPlaybackRate(_ rate: Double) {
        guard let clamped = PreviewAudioLimits.clampPlaybackRate(rate) else { return }
        requestedRateRaw = clamped
        chartRate = clamped
        requestedPlaybackRate = clamped
        guard timelineOpen else { return }
        var job = session.currentJob()
        job.rate = clamped
        session.update(job)
    }

    public func setAudibleKinds(_ kinds: Set<PreviewAudioKind>) {
        audibleKinds = kinds
        guard timelineOpen else { return }
        var job = session.currentJob()
        job.audible = kinds
        session.update(job)
    }

    func setPresentationClockExternallyDriven(_ enabled: Bool) {
        guard presentationClockExternallyDriven != enabled else { return }
        presentationClockExternallyDriven = enabled
        guard timelineOpen, chartEndSeconds > 0 else {
            elapsedClock.invalidate()
            return
        }
        if enabled {
            elapsedClock.invalidate()
        } else if !isChartPaused {
            startElapsedClock()
        }
    }

    func advancePresentationClock() {
        guard presentationClockExternallyDriven else { return }
        tickElapsed()
    }

    func debugCaptureRenderToken() -> PreviewRenderToken? { session.debugCaptureToken() }
    func debugReplaceRenderBinding() -> PreviewRenderToken? { session.debugReplaceBinding() }
    func debugRenderHolderCount() -> Int { session.debugHolderCount() }
    var diagnosticDeviceOutputRate: Double { session.deviceOutputRate }
    var diagnosticOutputNodeRate: Double { session.outputNodeRate }

    func playChart(
        documentData: Data,
        chartDirectory: URL?,
        notes: [PreviewAudioNote],
        timing: PreviewAudioTiming,
        fromBeat: Double,
        visualEndBeat: Double? = nil,
        startPaused: Bool = false
    ) {
        halt(notify: false)
        let generation = playbackGeneration
        diagnosticResourceLoads = 0
        diagnosticMainThreadResourceLoads = 0
        diagnosticEngineFailure = nil
        diagnosticShortfallCues = 0
        diagnosticLateResourceMisses = 0
        diagnosticCueCount = 0
        diagnosticPreparationFailure = nil
        diagnosticSourceFileBytes = 0
        diagnosticPeakDecodedBytes = 0
        decodedHeld = 0
        baselineScheduled = 0
        loadFailures.removeAll()
        prepared.removeAll()
        pausedBeforeStart = startPaused
        isChartPaused = false
        pausedElapsed = nil
        pausedWall = nil
        if let clamped = PreviewAudioLimits.clampPlaybackRate(requestedRateRaw) {
            chartRate = clamped
            requestedPlaybackRate = clamped
        }
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: fromBeat)
        chartEndSeconds = chartTimelineEnd(hits: hits, fromBeat: fromBeat, timing: timing, visualEndBeat: visualEndBeat)
        let table = LegacyPreviewAudio.parseWavTable(from: documentData)
        var unique: [String: URL] = [:]
        var built: [ChartCue] = []
        for hit in hits {
            guard let fileName = table[hit.wavToken],
                  let url = LegacyPreviewAudio.resolveWavURL(fileName: fileName, chartDirectory: chartDirectory)
            else {
                built.append(ChartCue(seconds: hit.seconds, key: nil, duration: 0, format: nil, kind: hit.kind))
                continue
            }
            let key = url.path
            built.append(ChartCue(seconds: hit.seconds, key: key, duration: 0, format: nil, kind: hit.kind))
            unique[key] = url
        }
        var carried: [CarryCue] = []
        let startBeat = fromBeat.isFinite ? fromBeat : 0
        let preparedClock = LegacyPreviewAudio.preparedTiming(timing)
        for note in notes where note.beat.isFinite && note.beat < startBeat {
            guard let fileName = table[note.wavToken.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()],
                  let url = LegacyPreviewAudio.resolveWavURL(fileName: fileName, chartDirectory: chartDirectory)
            else { continue }
            let key = url.path
            let offset = LegacyPreviewAudio.travelSeconds(fromBeat: note.beat, toBeat: startBeat, prepared: preparedClock)
            guard offset > 0 else { continue }
            carried.append(CarryCue(key: key, kind: note.kind, offset: offset))
            unique[key] = url
        }
        cues = built
        carries = carried
        diagnosticCueCount = cues.count
        guard playbackGeneration == generation else { return }
        if unique.isEmpty {
            commitPreparedChart(generation: generation)
            return
        }
        var firstSeconds: [String: Double] = [:]
        for cue in built where cue.key != nil && firstSeconds[cue.key!] == nil {
            firstSeconds[cue.key!] = cue.seconds
        }
        let ordered = unique.keys.sorted { lhs, rhs in
            let left = firstSeconds[lhs] ?? 0
            let right = firstSeconds[rhs] ?? 0
            if left != right { return left < right }
            return lhs < rhs
        }
        var uses: [String: [PreviewFileCue]] = [:]
        for cue in built {
            if let key = cue.key {
                uses[key, default: []].append(PreviewFileCue(chartSeconds: cue.seconds, fileOffset: cue.fileOffsetSeconds))
            }
        }
        for carry in carried {
            uses[carry.key, default: []].append(PreviewFileCue(chartSeconds: 0, fileOffset: carry.offset))
        }
        prepareLeft = ordered.count
        preparationOutstanding = true
        onPreparationStateChanged?(.preparing)
        guard playbackGeneration == generation, preparationOutstanding else { return }
        let reader = readResourceBytes
        let decoder = decodeToWav
        let worker = prepareWorker
        let room = resourceByteBudget
        let disk = traceDiskAccess
        let traceOpen = traceFileOpen
        let pairs = ordered.compactMap { key -> (String, URL)? in
            guard let url = unique[key] else { return nil }
            return (key, url)
        }
        Task { [weak self] in
            await worker.beginInlineBudget(room)
            for (key, url) in pairs {
                let result = await worker.load(
                    url: url,
                    uses: uses[key] ?? [],
                    reader: reader,
                    decoder: decoder,
                    disk: disk,
                    traceOpen: traceOpen
                )
                self?.completeLoad(generation: generation, key: key, result: result)
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        players.removeAll { $0 === player }
    }

    isolated deinit {
        pending.forEach { $0.cancel() }
        pending.removeAll()
        anchorItem?.cancel()
        for player in players {
            player.delegate = nil
            player.stop()
        }
        players.removeAll()
        session.shutdown()
        elapsedClock.player = nil
        elapsedClock.invalidate()
    }

    private func chartTimelineEnd(
        hits: [PreviewAudioHit],
        fromBeat: Double,
        timing: PreviewAudioTiming,
        visualEndBeat: Double?
    ) -> Double {
        let audioEnd = hits.map(\.seconds).max() ?? 0
        guard let visualEndBeat, visualEndBeat.isFinite else { return max(0, audioEnd) }
        let start = fromBeat.isFinite ? fromBeat : 0
        let pictureEnd = LegacyPreviewAudio.travelSeconds(
            fromBeat: start,
            toBeat: max(start, visualEndBeat),
            timing: timing
        )
        return max(audioEnd, pictureEnd)
    }

    private func completeLoad(generation: UInt, key: String, result: PreviewLoadResult) {
        guard playbackGeneration == generation, preparationOutstanding else { return }
        if let pcm = result.pcm {
            prepared[key] = PreparedAsset(pcm: pcm, file: nil)
            noteDecoded(result.decodedBytes)
        } else if let file = result.file {
            prepared[key] = PreparedAsset(pcm: nil, file: file)
            diagnosticSourceFileBytes = max(diagnosticSourceFileBytes, file.sourceBytes)
            noteDecoded(result.decodedBytes)
        }
        if let failure = result.failure {
            loadFailures[key] = failure
        }
        diagnosticResourceLoads += 1
        if result.readOnMain { diagnosticMainThreadResourceLoads += 1 }
        prepareLeft -= 1
        if prepareLeft <= 0 {
            commitPreparedChart(generation: generation)
        }
    }

    private func commitPreparedChart(generation: UInt) {
        guard playbackGeneration == generation, !timelineOpen else { return }
        preparationOutstanding = false
        for index in cues.indices {
            guard let key = cues[index].key, let asset = prepared[key] else { continue }
            let duration = assetDuration(asset)
            let offset = min(max(0, cues[index].fileOffsetSeconds), duration)
            cues[index].fileOffsetSeconds = offset
            cues[index].duration = max(0, duration - offset)
            cues[index].format = assetFormat(asset)
        }
        for carry in carries {
            guard let asset = prepared[carry.key] else { continue }
            let duration = assetDuration(asset)
            guard carry.offset + 0.001 < duration else { continue }
            cues.append(ChartCue(
                seconds: 0,
                key: carry.key,
                duration: duration - carry.offset,
                format: assetFormat(asset),
                kind: carry.kind,
                fileOffsetSeconds: carry.offset
            ))
        }
        carries.removeAll()
        let playable = cues.contains { $0.format != nil }
        let wide = prepared.values.contains { asset in
            (asset.pcm?.channelCount ?? asset.file?.channelCount ?? 0) > 2
        }
        if wide {
            diagnosticPreparationFailure = "channels"
            onPreparationStateChanged?(.failed)
            guard playbackGeneration == generation else { return }
            return
        }
        let hardFailure = loadFailures.values.contains { $0 != .missingFile }
        if !playable && hardFailure {
            diagnosticPreparationFailure = loadFailures.values.map(\.rawValue).sorted().joined(separator: ",")
            onPreparationStateChanged?(.failed)
            guard playbackGeneration == generation else { return }
            return
        }
        cues.sort { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
            return (lhs.key ?? "") < (rhs.key ?? "")
        }
        preparedVoicePlan = voicePlan()
        let audible = preparedVoicePlan.values.contains { $0 > 0 } || playable
        if pausedBeforeStart {
            isChartPaused = true
            pausedElapsed = 0
            pausedWall = 0
        }
        originEmitted = false
        readyDelivered = false
        transportCut = false
        timelineOpen = true
        let job = makeJob(generation: generation, audible: audible)
        if !testSuppressSessionSubmit {
            session.submit(job)
        }
        // 有声必须等 worker onReady 完成打开/格式/暂停起点验证，startPaused 不能在这里直接 ready。
        // 没有资源槽的空谱，以及没有画面长度的无声谱，仍同步完成。
        // 有资源槽但不可播、且还有画面终点：等静音 adapter 的 onReady，主线程不空等。
        let resourceSlot = cues.contains { $0.key != nil }
        if !audible && (chartEndSeconds <= 0 || !resourceSlot) {
            emitOrigin(generation: generation)
        }
    }

    private func makeJob(generation: UInt, audible: Bool) -> PreviewUnifiedJob {
        var assets: [PreviewUnifiedAsset] = []
        for (key, asset) in prepared {
            if let pcm = asset.pcm {
                assets.append(PreviewUnifiedAsset(
                    key: key,
                    sampleRate: pcm.sampleRate,
                    channels: pcm.channelCount,
                    frameCount: pcm.frameCount,
                    planar: pcm.planarFloat32,
                    fileURL: nil,
                    temporary: false,
                    sourceBytes: pcm.planarFloat32.count
                ))
            } else if let file = asset.file {
                assets.append(PreviewUnifiedAsset(
                    key: key,
                    sampleRate: file.sampleRate,
                    channels: file.channelCount,
                    frameCount: file.frameCount,
                    planar: nil,
                    fileURL: file.url,
                    temporary: file.temporary,
                    sourceBytes: file.sourceBytes
                ))
            }
        }
        let unified = cues.map { cue in
            PreviewUnifiedCue(
                seconds: cue.seconds,
                key: cue.key,
                kind: cue.kind,
                fileOffset: cue.fileOffsetSeconds,
                duration: cue.duration
            )
        }
        return PreviewUnifiedJob(
            generation: generation,
            assets: assets,
            cues: unified,
            rate: chartRate,
            paused: isChartPaused,
            stopped: false,
            seekSerial: generation,
            seekChart: 0,
            audible: audibleKinds,
            voiceSlots: preparedVoicePlan.values.reduce(0, +),
            budget: resourceByteBudget,
            record: recordOutputForTests,
            silent: !audible,
            quit: false,
            traceOpen: traceFileOpen,
            traceDisk: traceDiskAccess
        )
    }

    private func assetDuration(_ asset: PreparedAsset) -> Double {
        if let pcm = asset.pcm { return pcm.duration }
        if let file = asset.file, file.sampleRate > 0 { return Double(file.frameCount) / file.sampleRate }
        return 0
    }

    private func assetFormat(_ asset: PreparedAsset) -> VoiceFormat? {
        if let pcm = asset.pcm { return pcm.format }
        if let file = asset.file {
            return VoiceFormat(sampleRate: Int(file.sampleRate.rounded()), channels: file.channelCount)
        }
        return nil
    }

    private func receiveWorkerReady(generation: UInt) {
        guard playbackGeneration == generation, timelineOpen, !originEmitted else { return }
        testBeforeWorkerReady?(generation)
        guard playbackGeneration == generation, timelineOpen, !originEmitted else { return }
        emitOrigin(generation: generation)
    }

    /// 测试按 worker 失败回调进入同一条失败路径。
    func testInjectWorkerFailure(_ reason: String) {
        failPreparation(generation: playbackGeneration, reason: reason)
    }

    /// 测试按 worker 就绪回调进入同一条起点路径。
    func testInjectWorkerReady() {
        receiveWorkerReady(generation: playbackGeneration)
    }

    func testStoredDeviceTapRate() -> Double { session.storedDeviceTapRate() }

    func testJobState() -> (generation: UInt, stopped: Bool, paused: Bool) {
        let job = session.currentJob()
        return (job.generation, job.stopped, job.paused)
    }

    private func emitOrigin(generation: UInt) {
        guard playbackGeneration == generation, timelineOpen, !originEmitted else { return }
        if session.failure() != nil {
            failPreparation(generation: generation, reason: session.failure() ?? "failed")
            return
        }
        originEmitted = true
        readyDelivered = true
        baselineScheduled = session.stats().scheduled
        onPreparationStateChanged?(.ready)
        guard playbackGeneration == generation, timelineOpen else { return }
        onElapsedSeconds?(0)
        guard playbackGeneration == generation, timelineOpen, !isChartPaused else { return }
        if chartEndSeconds <= 0 {
            closeTimeline(generation: generation)
            return
        }
        startElapsedClock()
    }

    private func failPreparation(generation: UInt, reason: String) {
        guard playbackGeneration == generation else { return }
        if diagnosticPreparationFailure != nil { return }
        let runtime = readyDelivered
        let stillRunning = timelineOpen
        diagnosticPreparationFailure = reason
        if reason == "engine" || reason == "device" { diagnosticEngineFailure = reason }
        if runtime {
            // 先停本代 job，再进用户回调。回调里重播会换代，之后不能再读 currentJob。
            var job = session.currentJob()
            if job.generation == generation {
                job.stopped = true
                job.paused = true
                session.update(job)
            }
        }
        guard playbackGeneration == generation else { return }
        timelineOpen = false
        originEmitted = true
        elapsedClock.invalidate()
        onPreparationStateChanged?(.failed)
        guard playbackGeneration == generation else { return }
        // 准备期失败，以及已经自然结束后的失败，不额外 stopped。运行中的失败走既有 stopped。
        guard runtime, stillRunning else { return }
        onPlaybackStopped?()
        guard playbackGeneration == generation else { return }
    }

    private func voicePlan() -> [VoiceFormat: Int] {
        var grouped: [VoiceFormat: [(Double, Double)]] = [:]
        for cue in cues {
            guard let format = cue.format, cue.duration > 0 else { continue }
            grouped[format, default: []].append((cue.seconds, cue.seconds + cue.duration))
        }
        var plan: [VoiceFormat: Int] = [:]
        for (format, intervals) in grouped {
            let overlap = maxOverlap(intervals)
            if overlap > 0 { plan[format] = overlap }
        }
        let total = plan.values.reduce(0, +)
        guard total > PreviewAudioLimits.maxVoices else { return plan }
        let scale = Double(PreviewAudioLimits.maxVoices) / Double(total)
        for format in plan.keys {
            plan[format] = max(1, Int((Double(plan[format] ?? 0) * scale).rounded(.down)))
        }
        while plan.values.reduce(0, +) > PreviewAudioLimits.maxVoices {
            guard let busiest = plan.max(by: { $0.value < $1.value })?.key, (plan[busiest] ?? 0) > 1 else { break }
            plan[busiest, default: 0] -= 1
        }
        while plan.values.reduce(0, +) > PreviewAudioLimits.maxVoices {
            guard let smallest = plan.min(by: { $0.value < $1.value })?.key else { break }
            plan.removeValue(forKey: smallest)
        }
        return plan
    }

    private func maxOverlap(_ intervals: [(Double, Double)]) -> Int {
        var events: [(time: Double, delta: Int)] = []
        for (start, end) in intervals where end > start {
            events.append((start, 1))
            events.append((end, -1))
        }
        events.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.delta < rhs.delta
        }
        var current = 0
        var peak = 0
        for event in events {
            current += event.delta
            peak = max(peak, current)
        }
        return peak
    }

    private func currentElapsed() -> Double {
        if let pausedElapsed { return pausedElapsed }
        guard timelineOpen else { return 0 }
        return session.mappedClock(generation: playbackGeneration).chart
    }

    private func currentWallElapsed() -> Double {
        if let pausedWall { return pausedWall }
        guard timelineOpen else { return 0 }
        return session.mappedClock(generation: playbackGeneration).wall
    }

    private func noteDecoded(_ bytes: Int) {
        guard bytes > 0 else { return }
        decodedHeld += bytes
        diagnosticPeakDecodedBytes = max(diagnosticPeakDecodedBytes, decodedHeld)
    }

    private func halt(notify: Bool) {
        let cancelPrepare = preparationOutstanding
        playbackGeneration &+= 1
        let haltedGeneration = playbackGeneration
        preparationOutstanding = false
        prepareLeft = 0
        timelineOpen = false
        originEmitted = true
        readyDelivered = false
        transportCut = true
        pending.forEach { $0.cancel() }
        pending.removeAll()
        anchorItem?.cancel()
        anchorItem = nil
        isChartPaused = false
        pausedBeforeStart = false
        pausedElapsed = nil
        pausedWall = nil
        carries.removeAll()
        cues.removeAll()
        prepared.removeAll()
        players.forEach { $0.stop() }
        players.removeAll()
        var job = session.currentJob()
        job.stopped = true
        job.paused = true
        session.update(job)
        endTimelineClock()
        if cancelPrepare {
            onPreparationStateChanged?(.cancelled)
            guard playbackGeneration == haltedGeneration else { return }
        }
        if notify { onPlaybackStopped?() }
    }

    private func endTimelineClock() { elapsedClock.invalidate() }

    private func closeTimeline(generation: UInt) {
        guard playbackGeneration == generation, timelineOpen else { return }
        timelineOpen = false
        endTimelineClock()
        onTimelineFinished?()
        guard playbackGeneration == generation else { return }
    }

    private func startElapsedClock() {
        elapsedClock.player = self
        if presentationClockExternallyDriven {
            elapsedClock.invalidate()
            return
        }
        elapsedClock.start()
    }

    fileprivate func tickElapsed() {
        let generation = playbackGeneration
        guard timelineOpen, !isChartPaused else { return }
        let fault = session.consumeRenderFault()
        if fault != 0 {
            failPreparation(generation: generation, reason: "render")
            return
        }
        let elapsed = currentElapsed()
        if elapsed < 0 { return }
        if chartEndSeconds > 0, elapsed >= chartEndSeconds {
            onElapsedSeconds?(chartEndSeconds)
            guard playbackGeneration == generation, timelineOpen else { return }
            closeTimeline(generation: generation)
            return
        }
        onElapsedSeconds?(elapsed)
        guard playbackGeneration == generation, timelineOpen else { return }
    }

    private func scheduleDurationLimit(maxDurationSeconds: Double, fadeOutSeconds: Double) {
        guard maxDurationSeconds > 0, maxDurationSeconds.isFinite else { return }
        let generation = playbackGeneration
        let startFade = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.playbackGeneration == generation else { return }
                self.beginVolumeFade(seconds: fadeOutSeconds, generation: generation)
            }
        }
        pending.append(startFade)
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDurationSeconds, execute: startFade)
    }

    private func beginVolumeFade(seconds: Double, generation: UInt) {
        guard playbackGeneration == generation else { return }
        guard seconds > 0, seconds.isFinite else {
            halt(notify: true)
            return
        }
        let steps = 20
        let dt = seconds / Double(steps)
        for step in 0...steps {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.playbackGeneration == generation else { return }
                    let gain = max(0, 1.0 - Double(step) / Double(steps))
                    self.players.forEach { $0.volume = Float(gain) }
                    if step == steps { self.halt(notify: true) }
                }
            }
            pending.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + dt * Double(step), execute: item)
        }
    }

    private func startPlayer(url: URL) {
        let resolved = LegacyPreviewAudio.resolveAudioURL(
            fileName: url.lastPathComponent,
            chartDirectory: url.deletingLastPathComponent()
        ) ?? url
        guard FileManager.default.fileExists(atPath: resolved.path) else { return }
        if playSystemFile(resolved) { return }
        if let data = decodeToWav?(resolved) { playWavData(data) }
    }

    @discardableResult
    private func playSystemFile(_ url: URL) -> Bool {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { return false }
            players.append(player)
            return true
        } catch {
            return false
        }
    }

    private func playWavData(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { return }
            players.append(player)
        } catch {
            return
        }
    }
}
