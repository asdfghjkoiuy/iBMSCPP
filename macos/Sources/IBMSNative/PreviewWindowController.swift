import AppKit
import QuartzCore

/// 预览窗把播放器给出的秒数换成画面拍，并让谱面和 BGA 共用这一拍。
/// BMS 直接用播出秒数；BMSON 先按原有缓冲延迟换算，再走同一套拍点。
/// 播放客户区按 uBMplay 的 587×256，谱面 331 与 BGA 256 并排，整数倍放大，多出来的空间留边。
@MainActor
enum PreviewWindowPlayback {
    static let defaultScale: CGFloat = 2
    /// 两行：原来的播放条，加上 HiSpeed / Rate 的当前值和一次一档按钮。
    static let controlStripHeight: CGFloat = 56
    /// 默认客户区就是 2× 的 587×256，不再把控制条算进高度。控制条按需盖在舞台外面。
    static var defaultContentSize: NSSize {
        NSSize(
            width: PreviewUbmStyle.canvasSize.width * defaultScale,
            height: PreviewUbmStyle.canvasSize.height * defaultScale
        )
    }
    static var minimumContentSize: NSSize {
        NSSize(
            width: PreviewUbmStyle.canvasSize.width,
            height: PreviewUbmStyle.canvasSize.height
        )
    }
    /// 1 倍 HiSpeed 的拍距。原版一个四分音符的刻度，不把窗口 2 倍客户区乘进去。
    static let hiSpeedBasePixelsPerBeat = 48.0
    static let defaultPixelsPerBeat = hiSpeedBasePixelsPerBeat
    static let minimumPixelsPerBeat = 16.0
    static let maximumPixelsPerBeat = 240.0

    /// 在 `rect` 里放一块 587×256 的舞台。放得下整数倍时取整数倍，否则整块等比缩小，不分开拉伸谱面和 BGA。
    static func stageFrames(in rect: CGRect) -> (playfield: CGRect, bga: CGRect, scale: CGFloat) {
        let canvas = PreviewUbmStyle.canvasSize
        let playfieldSize = PreviewUbmStyle.playfieldSize
        let bgaSize = PreviewUbmStyle.bgaSize
        guard rect.width > 1, rect.height > 1, canvas.width > 1, canvas.height > 1 else {
            return (.zero, .zero, 1)
        }
        let fit = min(rect.width / canvas.width, rect.height / canvas.height)
        let whole = floor(fit + 0.000_1)
        let scale: CGFloat = whole >= 1 ? whole : max(fit, 0.01)
        let stageWidth = canvas.width * scale
        let stageHeight = canvas.height * scale
        let originX = rect.minX + (rect.width - stageWidth) / 2
        let originY = rect.minY + (rect.height - stageHeight) / 2
        let playfield = CGRect(
            x: originX,
            y: originY,
            width: playfieldSize.width * scale,
            height: playfieldSize.height * scale
        )
        let bga = CGRect(
            x: originX + playfieldSize.width * scale,
            y: originY,
            width: bgaSize.width * scale,
            height: bgaSize.height * scale
        )
        return (playfield, bga, scale)
    }

    /// 587 舞台。`packed` 时 331 谱面在左、BGA 在右。
    /// 分离时只在自动分离打开且 `#PLAYER` 不是 3：1P 面板落在 15…173，BGA 在 173…429，2P 面板在 429…587。
    /// 两个 331 视图用容器裁切，1P 原生 0…157 平移 +15，2P 原生 173…331 平移 +256。音符不再单独缩放。
    static func arrangedStage(in rect: CGRect, packed: Bool) -> PreviewUbmArrangedStage {
        let fitted = stageFrames(in: rect)
        guard fitted.playfield.width > 1, fitted.scale > 0 else {
            return PreviewUbmArrangedStage(
                scale: fitted.scale,
                packed: packed,
                stage: .zero,
                primaryClip: .zero,
                secondaryClip: .zero,
                playfieldSize: .zero,
                secondaryViewX: 0,
                bga: .zero
            )
        }
        let scale = fitted.scale
        let originX = fitted.playfield.minX
        let originY = fitted.playfield.minY
        let height = fitted.playfield.height
        let fullWidth = fitted.playfield.width
        let canvas = PreviewUbmStyle.canvasSize
        let stage = CGRect(x: originX, y: originY, width: canvas.width * scale, height: canvas.height * scale)
        if packed {
            return PreviewUbmArrangedStage(
                scale: scale,
                packed: true,
                stage: stage,
                primaryClip: fitted.playfield,
                secondaryClip: .zero,
                playfieldSize: CGSize(width: fullWidth, height: height),
                secondaryViewX: 0,
                bga: fitted.bga
            )
        }
        let panel = 158 * scale
        return PreviewUbmArrangedStage(
            scale: scale,
            packed: false,
            stage: stage,
            primaryClip: CGRect(x: originX + 15 * scale, y: originY, width: panel, height: height),
            secondaryClip: CGRect(x: originX + 429 * scale, y: originY, width: panel, height: height),
            playfieldSize: CGSize(width: fullWidth, height: height),
            secondaryViewX: -173 * scale,
            bga: CGRect(
                x: originX + 173 * scale,
                y: originY,
                width: fitted.bga.width,
                height: height
            )
        )
    }

    static func stageIsPacked(autoSeparate: Bool, playerHeader: Int?) -> Bool {
        !autoSeparate || playerHeader == 3
    }

    static func clampedScroll(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPixelsPerBeat }
        return min(max(value, minimumPixelsPerBeat), maximumPixelsPerBeat)
    }

    /// 非有限的延迟比不当成延迟。有限值，包括负数，仍交给原来的 `playheadSeconds`。
    static func storedDelayRatio(appliesBmsonPlayhead: Bool, stored: Double) -> Double {
        guard appliesBmsonPlayhead, stored.isFinite else { return 0 }
        return stored
    }

    static func visualSeconds(elapsed: Double, appliesBmsonPlayhead: Bool, delayRatio: Double) -> Double {
        let audio = elapsed.isFinite ? max(0, elapsed) : 0
        guard appliesBmsonPlayhead else { return audio }
        let delayed = BmsONEPreviewTiming.playheadSeconds(audioSeconds: audio, ratio: delayRatio)
        return delayed.isFinite ? max(0, delayed) : 0
    }

    static func requestedEndBeat(_ endBeat: Double) -> Double? {
        endBeat.isFinite ? endBeat : nil
    }

    static func statusText(
        isPlaying: Bool,
        isFinished: Bool,
        visualSeconds: Double,
        beat: Double,
        bpm: Double?
    ) -> String {
        let seconds = visualSeconds.isFinite ? max(0, visualSeconds) : 0
        let shownBeat = beat.isFinite ? beat : 0
        let clock = formatClock(seconds)
        let beatText = String(format: "%.2f", locale: posix, shownBeat)
        let stop = NativeLocalization.text("Stop")
        if isPlaying {
            guard let bpm, bpm.isFinite, bpm > 0 else { return "\(clock) · \(beatText)" }
            return "\(clock) · \(beatText) · \(formatBPM(bpm)) BPM"
        }
        if isFinished {
            guard let bpm, bpm.isFinite, bpm > 0 else { return "\(clock) · \(beatText) · \(stop)" }
            return "\(clock) · \(beatText) · \(formatBPM(bpm)) BPM · \(stop)"
        }
        guard let bpm, bpm.isFinite, bpm > 0 else { return stop }
        return "\(stop) · \(formatBPM(bpm)) BPM"
    }

    /// 按信息位拼行。缺的曲信息留空。选项只写已经作用到画面或声音上的项。
    static func infoOverlayText(
        showsPlay: Bool,
        showsSong: Bool,
        showsOptions: Bool,
        title: String,
        visualSeconds: Double,
        bpm: Double?,
        noteCount: Int,
        playLevel: String?,
        rank: String?,
        paused: Bool,
        optionLines: [String],
        hiSpeed: Double,
        playbackRate: Double
    ) -> String {
        var lines: [String] = []
        if showsPlay {
            lines.append("Play")
            lines.append(formatClock(visualSeconds.isFinite ? max(0, visualSeconds) : 0))
            if let bpm, bpm.isFinite, bpm > 0 {
                lines.append("BPM \(formatBPM(bpm))")
            }
            lines.append("HS \(formatDetent(hiSpeed)) RATE \(formatDetent(playbackRate))")
            if paused {
                lines.append("PAUSE")
            }
        }
        if showsSong {
            lines.append("Song")
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                lines.append(trimmedTitle)
            }
            if let playLevel, !playLevel.isEmpty {
                lines.append("LEVEL \(playLevel)")
            }
            if let rank, !rank.isEmpty {
                lines.append("RANK \(rank)")
            }
            lines.append("NOTES \(max(0, noteCount))")
        }
        if showsOptions, !optionLines.isEmpty {
            lines.append("[Option]")
            lines.append(contentsOf: optionLines)
        }
        return lines.joined(separator: "\n")
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
    static let optionLocale = posix

    private static func formatClock(_ seconds: Double) -> String {
        let clamped = seconds.isFinite ? max(0, seconds) : 0
        var minutes = Int(clamped / 60)
        let remain = clamped - Double(minutes) * 60
        var text = String(format: "%.2f", locale: posix, remain)
        if text == "60.00" {
            minutes += 1
            text = "00.00"
        }
        if text.count < 5 {
            text = String(repeating: "0", count: 5 - text.count) + text
        }
        return "\(minutes):\(text)"
    }

    static func formatDetent(_ value: Double) -> String {
        let shown = value.isFinite ? value : 0
        return String(format: "%.2f", locale: posix, shown)
    }

    private static func formatBPM(_ bpm: Double) -> String {
        if abs(bpm.rounded() - bpm) < 0.05 {
            return String(format: "%.0f", locale: posix, bpm)
        }
        return String(format: "%.2f", locale: posix, bpm)
    }
}

/// 窗口当前交给谱面和 BGA 的同一时刻。自然结束保留末拍，`isPlaying` 为假。
@MainActor
struct PreviewWindowDisplay: Equatable {
    var chart = PreviewChartSnapshot()
    var beat = 0.0
    var elapsedSeconds = 0.0
    var isPlaying = false
    var isPaused = false
    var isFinished = false
    var pixelsPerBeat = PreviewWindowPlayback.defaultPixelsPerBeat
    var statusText = ""
    var visualEndBeat: Double?
    var windowTitle = ""
    var playerSide = PreviewPlayerSide.both
    var bgaBeat = 0.0
    var bgaElapsedSeconds = 0.0
    var bgaIsPlaying = false
    var bgaFromBeat = 0.0
    var bgaChartTitle = ""
    var bgaDirectoryPath: String?
}

/// 谱面和 BGA 在内容坐标系里的可见框。整块 587 舞台按整数倍缩放，放不下时均匀留边。
@MainActor
struct PreviewWindowLayout: Equatable {
    var sideBySide = false
    var packed = false
    var playfieldFrame = CGRect.zero
    var secondPlayfieldFrame = CGRect.zero
    /// 名义 256 列，信息仍摆在这里。
    var bgaFrame = CGRect.zero
    var nominalBGAFrame = CGRect.zero
    /// BGA 视图的实际框，等于整块 587×256 舞台。
    var actualStageFrame = CGRect.zero
    var stageScale: CGFloat = 1
    var controlsFrame = CGRect.zero
    var infoFrame = CGRect.zero
}

/// 587 舞台上两个裁切容器和 BGA 的位置。视图本身仍是 331 宽。
struct PreviewUbmArrangedStage: Equatable {
    var scale: CGFloat
    var packed: Bool
    var stage: CGRect
    var primaryClip: CGRect
    var secondaryClip: CGRect
    var playfieldSize: CGSize
    var secondaryViewX: CGFloat
    /// 名义 256 列。不是 BGA 视图的实际框。
    var bga: CGRect
}

/// 从谱面文本里读得到的等级和段位。读不到就空着，不补一个假状态。
struct PreviewUbmChartFacts: Equatable {
    var playLevel: String?
    var rank: String?

    static func parse(_ data: Data) -> PreviewUbmChartFacts {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? ""
        if text.first == "{" { return PreviewUbmChartFacts() }
        var level: String?
        var rank: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.first == "#" else { continue }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("#PLAYLEVEL") {
                level = value(from: trimmed, header: "#PLAYLEVEL")
            } else if upper.hasPrefix("#RANK"), !upper.hasPrefix("#RANKING") {
                rank = value(from: trimmed, header: "#RANK")
            }
        }
        return PreviewUbmChartFacts(playLevel: level, rank: rank)
    }

    /// `#PLAYER` 只认 1、2、3。没有这条头、或正文是 JSON，就保持空，不补成 3。
    static func playerHeader(from data: Data) -> Int? {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? ""
        if text.first == "{" { return nil }
        var player: Int?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.first == "#" else { continue }
            let upper = trimmed.uppercased()
            guard upper.hasPrefix("#PLAYER") else { continue }
            let marker = upper.dropFirst("#PLAYER".count)
            guard marker.first == nil || marker.first == " " || marker.first == "\t" else { continue }
            guard let raw = value(from: trimmed, header: "#PLAYER") else { continue }
            let token = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? raw
            if token == "1" || token == "2" || token == "3" {
                player = Int(token)
            }
        }
        return player
    }

    private static func value(from line: String, header: String) -> String? {
        let raw = line.dropFirst(header.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 32 else { return nil }
        guard raw.allSatisfy({ $0.isASCII && !$0.isNewline }) else { return nil }
        return String(raw)
    }
}

/// 起播时排好的 BPM / STOP 分段。之后用二分把秒数换成拍，不再每拍排序。
/// 分段规则和 `LegacyPreviewAudio.beat` 相同：起点上的 BPM 先生效，之后同拍先停再换速。
struct PreviewTimingIndex {
    private struct Piece {
        var startSeconds: Double
        var endSeconds: Double
        var startBeat: Double
        var bpm: Double
        var isStop: Bool
    }

    private var pieces: [Piece]
    private var bpmBeats: [Double]
    private var bpmValues: [Double]
    private let headerBPM: Double
    private let origin: Double
    /// 查询里的二分比较次数。构造时的排序不计入。
    private(set) var queryComparisons = 0

    var pieceCount: Int { pieces.count }

    init(timing: PreviewAudioTiming, fromBeat: Double) {
        let header = Self.usableBPM(timing.headerBPM)
        headerBPM = header
        origin = fromBeat
        let changes = timing.bpmEvents
            .filter { $0.bpm > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        let stops = timing.stopEvents
            .filter { $0.durationSeconds > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        let displayed = changes.filter { $0.bpm.isFinite }
        bpmBeats = displayed.map(\.beat)
        bpmValues = displayed.map(\.bpm)
        guard fromBeat.isFinite else {
            pieces = []
            return
        }

        var bpm = header
        var changeIndex = 0
        while changeIndex < changes.count, changes[changeIndex].beat <= fromBeat {
            bpm = Self.usableBPM(changes[changeIndex].bpm)
            changeIndex += 1
        }
        var stopIndex = stops.firstIndex { $0.beat >= fromBeat } ?? stops.count
        var cursor = fromBeat
        var seconds = 0.0
        var built: [Piece] = []
        built.reserveCapacity(changes.count + stops.count + 1)

        while changeIndex < changes.count || stopIndex < stops.count {
            let nextChange = changeIndex < changes.count ? changes[changeIndex].beat : Double.infinity
            let nextStop = stopIndex < stops.count ? stops[stopIndex].beat : Double.infinity
            if nextStop <= nextChange, nextStop.isFinite {
                if nextStop > cursor {
                    seconds = Self.appendMotion(
                        from: cursor,
                        to: nextStop,
                        bpm: bpm,
                        seconds: seconds,
                        into: &built
                    )
                    cursor = nextStop
                }
                while stopIndex < stops.count && stops[stopIndex].beat == cursor {
                    let pause = stops[stopIndex].durationSeconds
                    stopIndex += 1
                    guard pause.isFinite else {
                        built.append(Piece(
                            startSeconds: seconds,
                            endSeconds: .infinity,
                            startBeat: cursor,
                            bpm: bpm,
                            isStop: true
                        ))
                        pieces = built
                        return
                    }
                    if pause > 0 {
                        built.append(Piece(
                            startSeconds: seconds,
                            endSeconds: seconds + pause,
                            startBeat: cursor,
                            bpm: bpm,
                            isStop: true
                        ))
                        seconds += pause
                    }
                }
            } else if nextChange.isFinite {
                if nextChange > cursor {
                    seconds = Self.appendMotion(
                        from: cursor,
                        to: nextChange,
                        bpm: bpm,
                        seconds: seconds,
                        into: &built
                    )
                    cursor = nextChange
                }
                bpm = Self.usableBPM(changes[changeIndex].bpm)
                changeIndex += 1
            } else {
                break
            }
        }
        built.append(Piece(
            startSeconds: seconds,
            endSeconds: .infinity,
            startBeat: cursor,
            bpm: bpm,
            isStop: false
        ))
        pieces = built
    }

    mutating func beat(afterSeconds seconds: Double) -> Double {
        guard seconds.isFinite, origin.isFinite else { return origin }
        if seconds <= 0 || pieces.isEmpty { return origin }
        let index = pieceIndex(containing: seconds)
        if index > 0 {
            let previous = pieces[index - 1]
            // STOP 的结束点仍停在那一拍，和 `remaining <= pause` 相同。
            if previous.isStop, seconds <= previous.endSeconds {
                return previous.startBeat
            }
        }
        let piece = pieces[index]
        if piece.isStop { return piece.startBeat }
        let beat = piece.startBeat + (seconds - piece.startSeconds) * piece.bpm / 60
        return beat.isFinite ? beat : origin
    }

    mutating func activeBPM(at beat: Double) -> Double {
        guard beat.isFinite else { return headerBPM }
        guard let index = lastBPMIndex(atOrBefore: beat) else { return headerBPM }
        return bpmValues[index]
    }

    private static func usableBPM(_ bpm: Double) -> Double {
        bpm > 0 && bpm.isFinite ? bpm : 120
    }

    private static func appendMotion(
        from start: Double,
        to end: Double,
        bpm: Double,
        seconds: Double,
        into pieces: inout [Piece]
    ) -> Double {
        let duration = (end - start) * 60 / bpm
        guard duration > 0, duration.isFinite else { return seconds }
        pieces.append(Piece(
            startSeconds: seconds,
            endSeconds: seconds + duration,
            startBeat: start,
            bpm: bpm,
            isStop: false
        ))
        return seconds + duration
    }

    private mutating func pieceIndex(containing seconds: Double) -> Int {
        var low = 0
        var high = pieces.count
        while low < high {
            queryComparisons += 1
            let mid = (low + high) / 2
            if pieces[mid].startSeconds <= seconds {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }

    private mutating func lastBPMIndex(atOrBefore beat: Double) -> Int? {
        var low = 0
        var high = bpmBeats.count
        while low < high {
            queryComparisons += 1
            let mid = (low + high) / 2
            if bpmBeats[mid] <= beat {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }
}

@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let player: LegacyPreviewAudioPlayer
    private let content: PreviewWindowContentView
    private var documentSource: () -> PreviewAudioDocumentContext?
    private var onPlayheadBeat: ((Double?) -> Void)?
    private var playheadFromBeat = 0.0
    /// 这一次播放起点在曲首时间轴上的秒。信息时钟用它加上相对 elapsed，得到绝对谱面时间。
    private var infoOriginSeconds = 0.0
    private var playheadContext: PreviewAudioDocumentContext?
    private var playheadDelayRatio = 0.0
    private var idleTiming: PreviewAudioTiming?
    private var playheadIndex = PreviewTimingIndex(timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []), fromBeat: 0)
    private var playheadSuppliesBPM = false
    private var display = PreviewWindowDisplay()
    /// 每次起播加一。闭包抓住自己的代号，旧回调进不了新的一次播放。
    private var playbackEpoch = 0
    /// 这一代号已经自然结束。之后的 elapsed 和同代号的 stop 通知都不能把末拍清掉。
    private var finishedEpoch: Int?
    /// 这一代号还在等音频准备完成。准备期间画面停在起点，不接显示器时钟。
    private var awaitingReady = false
    /// `playChart` 会先取消上一轮准备。那个 `.cancelled` 打到新代号上时丢掉。
    private var ignorePreparationCancel = false
    /// 窗口已经显示过。从没显示过的测试窗仍走原来的定时器回放，不把“未显示”当成隐藏。
    private var windowHasShown = false
    /// 最小化、遮挡或离开屏幕。声音和时间轴继续，画面和视频停住。
    private var pictureSuppressed = false
    /// 同一次恢复里 layout 可能再投递遮挡通知。不要因此再采样、再推一次 BGA。
    private var resumingPicture = false
    /// 默认读 BmsONE 偏好。测试可换成固定值，避免碰用户的偏好文件。
    var delayRatioSource: @MainActor () -> Double = { BmsONEPreferences.load().previewDelayRatio }
    /// 测试里关掉显示器同步，走播放器自己的定时器，也不去问屏幕。
    var previewDisplayLinkSuppressed = false
    private let displaySync = PreviewDisplaySync()
    private var externalClockWanted = false
    private var displayedBPM: Double?
    private var chartFacts = PreviewUbmChartFacts()
    /// 谱面头里的 `#PLAYER`。没有这条头时是 `nil`，不当成双人 packed。
    private var chartPlayer: Int?
    /// 效果用的墙上秒。不乘 RealHS。谱面拍和 BGA 仍走 `onElapsedSeconds`。
    private var effectElapsed = 0.0
    private var loadedDocument: Data?
    /// 曲头只跟文档字节和音符数走。同一块缓冲在播放时钟里反复读，不再逐帧扫全文。
    private var cachedSongDocument: Data?
    private var cachedSongNoteCount = -1
    private var cachedSongMetadata: PreviewBmsMetadata?
    private var editorClearArmed = false
    private var displayStepActive = false
    private var presentedThisStep = false
    private(set) var previewDisplayStepCount = 0
    private var behavior = PreviewUbmBehavior()
    private var onReloadPreview: (() -> Void)?
    private var heldSince: [PreviewUbmCommand: TimeInterval] = [:]
    /// `setAudibleKinds` 已经把当前种类交给播放器。选项行在这之后才写声音。
    private var soundFilterApplied = false

    init(
        state: ApplicationState,
        documentSource: @escaping () -> PreviewAudioDocumentContext? = { nil },
        onPlayheadBeat: ((Double?) -> Void)? = nil,
        onReloadPreview: (() -> Void)? = nil
    ) {
        player = state.previewPlayer
        self.documentSource = documentSource
        self.onPlayheadBeat = onPlayheadBeat
        self.onReloadPreview = onReloadPreview
        content = PreviewWindowContentView(audioImplemented: state.previewAudioIsImplemented)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PreviewWindowPlayback.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text("Preview")
        window.isReleasedWhenClosed = false
        window.contentMinSize = PreviewWindowPlayback.minimumContentSize
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("IBMSPreviewUbmStage")
        displaySync.owner = self
        content.onPlayFromStart = { [weak self] in self?.playFromStart() }
        content.onPlayHere = { [weak self] in self?.playFromPointer() }
        content.onStop = { [weak self] in self?.stopPlayback() }
        content.onScroll = { [weak self] value in self?.setPreviewScrollPixelsPerBeat(value) }
        content.onPlayerSide = { [weak self] side in self?.setPlayerSide(side) }
        content.onPreviewKeyDown = { [weak self] event in
            self?.handlePreviewKey(event, phase: .keyDown) ?? false
        }
        content.onPreviewKeyUp = { [weak self] event in
            self?.handlePreviewKey(event, phase: .keyUp) ?? false
        }
        content.onPreviewScroll = { [weak self] event in
            self?.handlePreviewScroll(event) ?? false
        }
        content.onUbmToken = { [weak self] token in
            self?.handleUbmToken(token)
        }
        content.onHiSpeedStep = { [weak self] direction in
            self?.stepSpeed(direction < 0 ? .hiSpeedDown : .hiSpeedUp)
        }
        content.onRealHSStep = { [weak self] direction in
            self?.stepSpeed(direction < 0 ? .realHSDown : .realHSUp)
        }
        content.onHiSpeedIndex = { [weak self] index in
            self?.selectHiSpeedDetent(index)
        }
        content.onRealHSPercent = { [weak self] percent in
            self?.selectRealHSPercent(percent)
        }
        NativeLocalization.localize(window: window)
        behavior.pauseEnabled = false
        behavior.hasReloadPath = false
        behavior.canSeek = false
        applyHiSpeed()
        applyBGAMode()
        applyAppearance()
        applyAudibleKinds()
        applyRealHS()
        setPlayerSide(.both)
        bindClock(
            chart: PreviewChartSnapshot(),
            directory: nil,
            fromBeat: 0,
            beat: 0,
            elapsed: 0,
            isPlaying: false,
            isFinished: false,
            timing: nil,
            visualEndBeat: nil
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    isolated deinit {
        displaySync.detach()
    }

    var previewDisplay: PreviewWindowDisplay { display }

    var previewPlayfieldPixelsPerBeat: Double { content.playfieldPixelsPerBeat }

    var previewPlayfieldPlaybackUpdates: Int { content.playfieldPlaybackUpdates }

    var previewBGAPlaybackUpdates: Int { content.bgaPlaybackUpdates }

    var previewBGAChartUpdates: Int { content.bgaChartUpdates }

    var previewPlayerSideApplies: Int { content.playerSideApplies }

    /// 只统计秒数到拍、以及当前 BPM 的查找比较。建索引的排序不算在里面。
    var previewTimingQueryComparisons: Int { playheadIndex.queryComparisons }

    var previewPresentedFrameCount: Int { content.presentedFrameCount }

    var previewInfoText: String { content.infoText }

    var previewInfoRasterCount: Int { content.infoRasterCount }

    var previewInfoSourceImage: CGImage? { content.infoSourceImage }

    /// 信息视图图层上正在显示的图。和 `previewInfoSourceImage` 同一缓存，供探针读屏幕内容。
    var previewInfoPresentedImage: CGImage? { content.infoPresentedImage }

    var previewInfoLayoutSize: CGSize { content.infoLayoutSize }

    var previewChartPaused: Bool { player.isChartPaused }

    var previewBehaviorPaused: Bool { behavior.paused }

    var previewHiSpeed: Double { behavior.hiSpeed }

    var previewRealHS: Int { behavior.realHS }

    func previewPlayfieldScene() -> PreviewPlayfieldScene { content.playfieldScene() }

    func previewSecondaryScene() -> PreviewPlayfieldScene { content.secondaryScene() }

    func previewBGAInspection() -> PreviewBGAInspection { content.bgaInspection() }

    func previewSendKeyDown(_ event: NSEvent) { content.keyDown(with: event) }

    func previewSendKeyUp(_ event: NSEvent) { content.keyUp(with: event) }

    func previewSendScroll(_ event: NSEvent) { content.scrollWheel(with: event) }

    func previewPerformMenu(_ identifier: String) { content.performMenuIdentifier(identifier) }

    var previewDisplayLinkAttached: Bool { displaySync.isAttached }

    var previewDisplayLinkFramesPerSecond: Int { displaySync.framesPerSecond }

    var previewUsesExternalPresentationClock: Bool { externalClockWanted }

    var previewPictureSuppressed: Bool { pictureSuppressed }

    var previewLayout: PreviewWindowLayout {
        content.layoutSubtreeIfNeeded()
        return content.layoutSnapshot()
    }

    /// 和显示器回调走同一条采样、再提交一帧。测试不必真有屏幕。
    func stepPresentationDisplayLink() {
        performDisplayStep(fromDisplayCallback: false)
    }

    /// 显示同步已经采样到的秒数，走提交帧的那条路。用来检查比 30Hz 更密的 BGA 事件。
    func previewPresentSampledElapsed(_ seconds: Double) {
        guard display.isPlaying, finishedEpoch != playbackEpoch, playheadContext != nil else { return }
        displayStepActive = true
        presentedThisStep = false
        updatePlayhead(elapsed: seconds, epoch: playbackEpoch)
        displayStepActive = false
    }

    override func showWindow(_ sender: Any?) {
        windowHasShown = true
        if !display.isPlaying, !display.isPaused, !display.isFinished {
            captureIdleSnapshot()
        }
        super.showWindow(sender)
        window?.makeFirstResponder(content)
        if pictureSuppressed {
            resumePicture()
        } else if display.isPlaying {
            engageDisplaySync()
        }
    }

    func setDocumentSource(_ source: @escaping () -> PreviewAudioDocumentContext?) {
        documentSource = source
        if !display.isPlaying {
            captureIdleSnapshot()
        }
    }

    /// 主编辑器另外把 `reloadPreviewRandomization` 交进来。这里不改 AppDelegate。
    func setReloadHandler(_ handler: (() -> Void)?) {
        onReloadPreview = handler
    }

    func previewNote(url: URL) {
        silencePlayback()
        settleStopped()
        player.stop()
        player.setPresentationClockExternallyDriven(false)
        externalClockWanted = false
        player.playFile(url: url)
    }

    func stopPlayback() {
        pictureSuppressed = false
        awaitingReady = false
        ignorePreparationCancel = false
        behavior.paused = false
        behavior.pauseEnabled = false
        display.isPaused = false
        silencePlayback()
        player.stop()
        player.setPresentationClockExternallyDriven(false)
        externalClockWanted = false
        settleStopped()
    }

    func playFromStart() {
        behavior.paused = false
        play(explicitBeat: 0, startPaused: false, context: nil, rebindSurfaces: true)
    }

    func playFromPointer() {
        behavior.paused = false
        play(explicitBeat: nil, startPaused: false, context: nil, rebindSurfaces: true)
    }

    func setPreviewScrollPixelsPerBeat(_ value: Double) {
        let clamped = PreviewWindowPlayback.clampedScroll(value)
        let detent = PreviewUbmBehavior.nearestHiSpeedDetent(
            clamped / PreviewWindowPlayback.hiSpeedBasePixelsPerBeat
        )
        let pixels = PreviewWindowPlayback.hiSpeedBasePixelsPerBeat * detent
        behavior.hiSpeed = detent
        content.setPlayfieldPixelsPerBeat(pixels)
        let applied = content.playfieldPixelsPerBeat
        display.pixelsPerBeat = applied
        content.setScroll(applied)
        content.refreshSpeedPresentation(hiSpeed: detent, playbackRate: displayedPlaybackRate())
        syncCurrentInfo(throttle: false)
    }

    func setPlayerSide(_ side: PreviewPlayerSide) {
        display.playerSide = side
        content.applyPlayerSide(side)
        syncCurrentInfo(throttle: false)
    }

    func setPreviewControlsVisible(_ visible: Bool) {
        content.setControlsVisible(visible)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopPlayback()
        sender.orderOut(self)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        stopPlayback()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        suspendPicture()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard windowCanHostLink() else { return }
        resumePicture()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard display.isPlaying || display.isPaused || awaitingReady || pictureSuppressed else { return }
        if windowCanHostLink() {
            resumePicture()
        } else {
            suspendPicture()
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard display.isPlaying || display.isPaused || awaitingReady || pictureSuppressed else { return }
        if isActivelyOnScreen() {
            resumePicture()
        } else {
            suspendPicture()
        }
    }

    private func play(
        explicitBeat: Double?,
        startPaused: Bool,
        context reused: PreviewAudioDocumentContext?,
        rebindSurfaces: Bool
    ) {
        guard let context = reused ?? documentSource() else {
            silencePlayback()
            player.stop()
            player.setPresentationClockExternallyDriven(false)
            externalClockWanted = false
            clearChart()
            return
        }
        let start = explicitBeat ?? (context.playHereBeat.isFinite ? context.playHereBeat : 0)
        let safeStart = start.isFinite ? start : 0
        playheadFromBeat = safeStart
        playheadContext = context
        playheadDelayRatio = PreviewWindowPlayback.storedDelayRatio(
            appliesBmsonPlayhead: context.appliesBmsonPlayhead,
            stored: delayRatioSource()
        )
        idleTiming = context.timing
        adoptDocument(context.documentData)
        let endBeat = PreviewWindowPlayback.requestedEndBeat(context.visualChart.endBeat)
        if windowHasShown {
            if window?.isVisible != true || window?.isMiniaturized == true {
                pictureSuppressed = true
            } else if isActivelyOnScreen() {
                pictureSuppressed = false
            }
        }
        behavior.paused = startPaused
        behavior.pauseEnabled = true
        effectElapsed = 0
        behavior.hasReloadPath = true
        behavior.canSeek = true
        armPlaybackCallbacks()
        bindClock(
            chart: context.visualChart,
            directory: context.chartDirectory,
            fromBeat: safeStart,
            beat: safeStart,
            elapsed: 0,
            isPlaying: false,
            isFinished: false,
            isPaused: startPaused,
            timing: context.timing,
            visualEndBeat: endBeat,
            rebindSurfaces: rebindSurfaces
        )
        player.setPresentationClockExternallyDriven(false)
        externalClockWanted = false
        ignorePreparationCancel = true
        player.playChart(
            documentData: context.documentData,
            chartDirectory: context.chartDirectory,
            notes: context.notes,
            timing: context.timing,
            fromBeat: safeStart,
            visualEndBeat: endBeat,
            startPaused: startPaused
        )
        ignorePreparationCancel = false
    }

    private func armPlaybackCallbacks() {
        playbackEpoch += 1
        finishedEpoch = nil
        awaitingReady = true
        onPlayheadBeat?(nil)
        editorClearArmed = true
        let epoch = playbackEpoch
        player.onElapsedSeconds = { [weak self] elapsed in
            self?.updatePlayhead(elapsed: elapsed, epoch: epoch)
        }
        player.onTimelineFinished = { [weak self] in
            self?.finishTimeline(epoch: epoch)
        }
        player.onPlaybackStopped = { [weak self] in
            self?.handlePlaybackStopped(epoch: epoch)
        }
        player.onPreparationStateChanged = { [weak self] state in
            self?.handlePreparation(state, epoch: epoch)
        }
    }

    /// 先摘掉闭包再停表。播放器若同步回调，也只可能打到空回调。
    private func silencePlayback() {
        displaySync.detach()
        playbackEpoch += 1
        finishedEpoch = nil
        awaitingReady = false
        player.onElapsedSeconds = nil
        player.onTimelineFinished = nil
        player.onPlaybackStopped = nil
        player.onPreparationStateChanged = nil
    }

    /// 准备完成才把这一代接到显示器。旧代号的 ready/cancelled 进不来。
    private func handlePreparation(_ state: PreviewAudioPreparationState, epoch: Int) {
        guard epoch == playbackEpoch else { return }
        switch state {
        case .preparing:
            awaitingReady = true
            displaySync.detach()
            externalClockWanted = false
            player.setPresentationClockExternallyDriven(false)
        case .cancelled, .shortfall, .failed:
            if state == .cancelled, ignorePreparationCancel { return }
            awaitingReady = false
            displaySync.detach()
            externalClockWanted = false
            player.setPresentationClockExternallyDriven(false)
        case .ready:
            guard awaitingReady else { return }
            awaitingReady = false
            forwardEngineRateToBGA(force: true)
            if behavior.paused {
                player.pauseChart()
                display.isPaused = true
                display.isPlaying = false
                displaySync.detach()
                player.setPresentationClockExternallyDriven(true)
                externalClockWanted = true
                if !pictureSuppressed {
                    content.syncBGA(beat: display.beat, elapsedSeconds: display.elapsedSeconds, isPlaying: false)
                }
                syncCurrentInfo(throttle: false)
                return
            }
            let link = canAttachDisplayLink()
            player.setPresentationClockExternallyDriven(link)
            externalClockWanted = link
            if link, !attachDisplayLink() {
                externalClockWanted = false
                player.setPresentationClockExternallyDriven(false)
            }
        }
    }

    private func updatePlayhead(elapsed: Double, epoch: Int) {
        guard epoch == playbackEpoch, finishedEpoch != epoch, let context = playheadContext else { return }
        if display.isPaused || behavior.paused { return }
        let visualSeconds = PreviewWindowPlayback.visualSeconds(
            elapsed: elapsed,
            appliesBmsonPlayhead: context.appliesBmsonPlayhead,
            delayRatio: playheadDelayRatio
        )
        let beat = playheadIndex.beat(afterSeconds: visualSeconds)
        let wall = player.playbackWallElapsedSeconds()
        effectElapsed = wall.isFinite ? max(0, wall) : 0
        let bpm = playheadSuppliesBPM ? playheadIndex.activeBPM(at: beat) : nil
        let presentation: ClockPresentation
        if pictureSuppressed {
            presentation = .logic
        } else if displayStepActive {
            presentation = .display
        } else {
            presentation = .deferred
        }
        writeClock(
            beat: beat,
            elapsed: visualSeconds,
            isPlaying: true,
            isFinished: false,
            bpm: bpm,
            presentation: presentation
        )
    }

    /// 最终 elapsed 已经在上一拍写进画面。这里只改状态并暂停 BGA，不再 setChart。
    private func finishTimeline(epoch: Int) {
        guard epoch == playbackEpoch, finishedEpoch != epoch, playheadContext != nil else { return }
        finishedEpoch = epoch
        behavior.paused = false
        behavior.pauseEnabled = false
        player.onElapsedSeconds = nil
        player.onTimelineFinished = nil
        displaySync.detach()
        externalClockWanted = false
        player.setPresentationClockExternallyDriven(false)
        let bpm = playheadSuppliesBPM ? playheadIndex.activeBPM(at: display.beat) : nil
        writeClock(
            beat: display.beat,
            elapsed: display.elapsedSeconds,
            isPlaying: false,
            isFinished: true,
            bpm: bpm,
            presentation: pictureSuppressed ? .logic : .deferred
        )
    }

    private func handlePlaybackStopped(epoch: Int) {
        guard epoch == playbackEpoch else { return }
        if finishedEpoch == epoch { return }
        settleStopped()
    }

    private func captureIdleSnapshot() {
        guard let context = documentSource() else {
            clearChart()
            return
        }
        idleTiming = context.timing
        adoptDocument(context.documentData)
        bindClock(
            chart: context.visualChart,
            directory: context.chartDirectory,
            fromBeat: 0,
            beat: 0,
            elapsed: 0,
            isPlaying: false,
            isFinished: false,
            isPaused: false,
            timing: context.timing,
            visualEndBeat: nil,
            rebindSurfaces: true
        )
        behavior.hasReloadPath = true
        behavior.canSeek = false
    }

    private func settleStopped() {
        playheadContext = nil
        playheadFromBeat = 0
        playheadDelayRatio = 0
        if editorClearArmed {
            editorClearArmed = false
            onPlayheadBeat?(nil)
        }
        bindClock(
            chart: display.chart,
            directory: directoryURL(display.bgaDirectoryPath),
            fromBeat: 0,
            beat: 0,
            elapsed: 0,
            isPlaying: false,
            isFinished: false,
            isPaused: false,
            timing: idleTiming,
            visualEndBeat: nil,
            rebindSurfaces: true
        )
        behavior.paused = false
        behavior.pauseEnabled = false
        behavior.canSeek = false
    }

    private func clearChart() {
        playheadContext = nil
        playheadFromBeat = 0
        playheadDelayRatio = 0
        idleTiming = nil
        chartFacts = PreviewUbmChartFacts()
        chartPlayer = nil
        loadedDocument = nil
        effectElapsed = 0
        refreshStageArrangement()
        if editorClearArmed {
            editorClearArmed = false
            onPlayheadBeat?(nil)
        }
        bindClock(
            chart: PreviewChartSnapshot(),
            directory: nil,
            fromBeat: 0,
            beat: 0,
            elapsed: 0,
            isPlaying: false,
            isFinished: false,
            timing: nil,
            visualEndBeat: nil
        )
        behavior.hasReloadPath = false
        behavior.canSeek = false
        behavior.pauseEnabled = false
        behavior.paused = false
    }

    private func directoryURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 起播、空闲和文档来源变化才重建谱面、BGA 和时间索引。
    private func bindClock(
        chart: PreviewChartSnapshot,
        directory: URL?,
        fromBeat: Double,
        beat: Double,
        elapsed: Double,
        isPlaying: Bool,
        isFinished: Bool,
        isPaused: Bool = false,
        timing: PreviewAudioTiming?,
        visualEndBeat: Double?,
        rebindSurfaces: Bool = true
    ) {
        let safeFrom = fromBeat.isFinite ? fromBeat : 0
        let resolved = timing ?? PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        playheadIndex = PreviewTimingIndex(timing: resolved, fromBeat: safeFrom)
        infoOriginSeconds = PreviewPlayfieldClock.arrivalSeconds(beat: safeFrom, origin: 0, timing: resolved)
        playheadSuppliesBPM = timing != nil
        if rebindSurfaces {
            content.bindSurfaces(
                chart,
                chartDirectory: directory,
                timing: resolved,
                fromBeat: safeFrom,
                documentData: loadedDocument
            )
        }
        content.applyTiming(resolved, fromBeat: safeFrom)
        let safeBeat = beat.isFinite ? beat : safeFrom
        let bpm = playheadSuppliesBPM ? playheadIndex.activeBPM(at: safeBeat) : nil
        let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowTitle = title.isEmpty ? NativeLocalization.text("Preview") : title
        if window?.title != windowTitle {
            window?.title = windowTitle
        }
        display.chart = chart
        display.visualEndBeat = visualEndBeat
        display.windowTitle = windowTitle
        display.bgaFromBeat = content.bgaFromBeat
        display.bgaChartTitle = content.bgaChartTitle
        display.bgaDirectoryPath = content.bgaDirectoryPath
        writeClock(
            beat: safeBeat,
            elapsed: elapsed,
            isPlaying: isPlaying,
            isFinished: isFinished,
            isPaused: isPaused,
            bpm: bpm
        )
        if rebindSurfaces {
            forwardEngineRateToBGA(force: true)
        }
    }

    /// 播放中的 tick 和自然结束只改拍、状态和 BGA 暂停，不比较整份谱面，也不把游标送回编辑器。
    private func writeClock(
        beat: Double,
        elapsed: Double,
        isPlaying: Bool,
        isFinished: Bool,
        isPaused: Bool = false,
        bpm: Double?,
        presentation: ClockPresentation = .deferred
    ) {
        let safeBeat = beat.isFinite ? beat : 0
        let safeElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let status = PreviewWindowPlayback.statusText(
            isPlaying: isPlaying,
            isFinished: isFinished,
            visualSeconds: safeElapsed,
            beat: safeBeat,
            bpm: bpm
        )
        let sounding = isPlaying && !isPaused && !isFinished
        display.beat = safeBeat
        display.elapsedSeconds = safeElapsed
        display.isPlaying = sounding
        display.isPaused = isPaused && !isFinished
        display.isFinished = isFinished
        display.statusText = status
        display.bgaBeat = safeBeat
        display.bgaElapsedSeconds = safeElapsed
        display.bgaIsPlaying = sounding
        displayedBPM = bpm
        switch presentation {
        case .display:
            content.presentPlaybackFrame(
                beat: safeBeat,
                chartElapsed: safeElapsed,
                effectElapsed: effectElapsed,
                isPlaying: sounding
            )
            content.syncBGA(beat: safeBeat, elapsedSeconds: safeElapsed, isPlaying: sounding)
            presentedThisStep = true
            syncCurrentInfo(throttle: true)
        case .deferred:
            content.showPlayback(
                beat: safeBeat,
                chartElapsed: safeElapsed,
                effectElapsed: effectElapsed,
                isPlaying: sounding
            )
            syncCurrentInfo(throttle: false)
        case .logic:
            content.advancePlaybackClock(
                beat: safeBeat,
                chartElapsedSeconds: safeElapsed,
                effectElapsedSeconds: effectElapsed,
                isPlaying: sounding
            )
            syncCurrentInfo(throttle: true)
        }
    }

    /// 隐藏时只留下文字缓存。可见时才画，框变了才摆舞台。
    private func syncCurrentInfo(throttle: Bool) {
        content.syncInfo(currentInfoText(), throttle: throttle, presents: !pictureSuppressed)
    }

    /// 绝对谱面秒。起点秒在 `bindClock` 里按曲首算好，相对 elapsed 仍是统一播放时钟。
    private func infoClockSeconds() -> Double {
        let origin = infoOriginSeconds.isFinite ? infoOriginSeconds : 0
        let elapsed = display.elapsedSeconds.isFinite ? display.elapsedSeconds : 0
        let sum = origin + elapsed
        return sum.isFinite ? max(0, sum) : 0
    }

    private func currentInfoText() -> String {
        if !behavior.showsPlayInfo && !behavior.showsSongInfo && !behavior.showsOptionInfo {
            return ""
        }
        return PreviewWindowPlayback.infoOverlayText(
            showsPlay: behavior.showsPlayInfo,
            showsSong: behavior.showsSongInfo,
            showsOptions: behavior.showsOptionInfo,
            title: songTitle(),
            visualSeconds: infoClockSeconds(),
            bpm: displayedBPM,
            noteCount: songNoteCount(),
            playLevel: songLevel(),
            rank: songRank(),
            paused: display.isPaused,
            optionLines: effectiveOptionLines(),
            hiSpeed: displayedHiSpeed(),
            playbackRate: displayedPlaybackRate()
        )
    }

    /// 画面上的拍距除以 48。档位落定时就是 0.50…5.00 里的一档。
    private func displayedHiSpeed() -> Double {
        let ratio = content.playfieldPixelsPerBeat / PreviewWindowPlayback.hiSpeedBasePixelsPerBeat
        return ratio.isFinite ? ratio : behavior.hiSpeed
    }

    /// 引擎已经接受的播放速率。还没有速率时用当前 RealHS 档。
    private func displayedPlaybackRate() -> Double {
        let actual = player.requestedPlaybackRate
        if actual.isFinite, actual > 0 { return actual }
        return Double(behavior.realHS) / 100
    }

    private func songMetadata() -> PreviewBmsMetadata? {
        let data = playheadContext?.documentData ?? loadedDocument
        guard let data else {
            cachedSongDocument = nil
            cachedSongNoteCount = -1
            cachedSongMetadata = nil
            return nil
        }
        let noteCount = display.chart.notes.count
        if let cachedSongMetadata,
           cachedSongNoteCount == noteCount,
           let cachedSongDocument,
           cachedSongDocument.count == data.count,
           sharesDocumentStorage(cachedSongDocument, data) {
            return cachedSongMetadata
        }
        let parsed = PreviewBmsSource.metadata(from: data, noteCount: noteCount)
        cachedSongDocument = data
        cachedSongNoteCount = noteCount
        cachedSongMetadata = parsed
        return parsed
    }

    /// 同一份 `Data` 的拷贝共用底层缓冲。播放时钟只比指针和长度，不比较全文。
    private func sharesDocumentStorage(_ stored: Data, _ current: Data) -> Bool {
        stored.withUnsafeBytes { left in
            current.withUnsafeBytes { right in
                left.baseAddress == right.baseAddress && left.count == right.count
            }
        }
    }

    private func songTitle() -> String {
        if let title = songMetadata()?.title, !title.isEmpty { return title }
        return display.chart.title
    }

    private func songLevel() -> String? {
        let level = songMetadata()?.playLevel
        return (level?.isEmpty == false) ? level : nil
    }

    private func songRank() -> String? {
        let rank = songMetadata()?.rank
        return (rank?.isEmpty == false) ? rank : nil
    }

    private func songNoteCount() -> Int {
        display.chart.notes.count
    }

    /// 只写已经作用到画面或声音上的项。HiSpeed 用当前拍距除以 48，不写一个被夹紧吃掉的倍率。
    private func effectiveOptionLines() -> [String] {
        var lines: [String] = []
        lines.append(
            "HiSpeed \(PreviewWindowPlayback.formatDetent(displayedHiSpeed()))"
        )
        switch behavior.bgaRaw {
        case 0: lines.append("OFF")
        case 1: lines.append("BASE ONLY")
        case 2: lines.append("LAYER ONLY")
        case 4: lines.append("ALWAYS MISS")
        default: break
        }
        if soundFilterApplied {
            switch behavior.sound {
            case .bgm: lines.append("BGM ONLY")
            case .key: lines.append("KEY ONLY")
            case .keyAndBGM: lines.append("KEY&BGM")
            case .mine: lines.append("MINE ONLY")
            case .keyBGMAndMine: lines.append("KEY&BGM&MINE")
            }
        }
        return lines
    }

    private func contentMeasures() -> PreviewUbmMeasures {
        let chart = playheadContext?.visualChart ?? display.chart
        let end = playheadContext?.visualChart.endBeat ?? display.visualEndBeat
        let starts = chart.barBeats.filter { start in
            guard start.isFinite else { return false }
            guard let end, end.isFinite, end > 0 else { return true }
            return start < end - 0.000_001
        }
        return PreviewUbmMeasures(starts: starts)
    }

    private func refreshBehaviorFlags() {
        let running = display.isPlaying || display.isPaused || awaitingReady
        behavior.canSeek = running
        behavior.pauseEnabled = running
        behavior.hasReloadPath = playheadContext != nil || behavior.hasReloadPath
    }

    @discardableResult
    private func handlePreviewKey(_ event: NSEvent, phase: PreviewUbmInputPhase) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""
        guard let command = PreviewUbmBehavior.command(
            for: characters,
            keyCode: event.keyCode,
            isKeypad: event.modifierFlags.contains(.numericPad),
            commandModifier: flags.contains(.command)
        ) else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        switch phase {
        case .keyUp:
            let start = heldSince[command] ?? now
            heldSince[command] = nil
            applyUbm(command, phase: .keyUp, elapsedMilliseconds: (now - start) * 1000)
        case .keyDown:
            if event.isARepeat {
                let start = heldSince[command] ?? now
                applyUbm(command, phase: .keyRepeat, elapsedMilliseconds: (now - start) * 1000)
            } else {
                heldSince[command] = now
                applyUbm(command, phase: .keyDown, elapsedMilliseconds: 0)
            }
        case .keyRepeat:
            let start = heldSince[command] ?? now
            applyUbm(command, phase: .keyRepeat, elapsedMilliseconds: (now - start) * 1000)
        }
        return true
    }

    private func handlePreviewScroll(_ event: NSEvent) -> Bool {
        guard event.scrollingDeltaY != 0 else { return false }
        refreshBehaviorFlags()
        let delta = event.scrollingDeltaY > 0 ? -1 : 1
        let action = behavior.seekByMeasures(delta, currentBeat: display.beat, measures: contentMeasures())
        dispatch(action)
        return !action.isEmpty
    }

    private func handleUbmToken(_ token: String) {
        guard let command = PreviewUbmBehavior.command(
            for: token,
            keyCode: 0,
            isKeypad: false,
            commandModifier: false
        ) else { return }
        heldSince[command] = ProcessInfo.processInfo.systemUptime
        applyUbm(command, phase: .keyDown, elapsedMilliseconds: 0)
        heldSince[command] = nil
        applyUbm(command, phase: .keyUp, elapsedMilliseconds: 0)
    }

    private func pollHeldKeys() {
        let now = ProcessInfo.processInfo.systemUptime
        for (command, start) in heldSince {
            applyUbm(command, phase: .keyRepeat, elapsedMilliseconds: (now - start) * 1000)
        }
    }

    private func applyUbm(_ command: PreviewUbmCommand, phase: PreviewUbmInputPhase, elapsedMilliseconds: Double) {
        refreshBehaviorFlags()
        let action = behavior.apply(
            command,
            phase: phase,
            elapsedMilliseconds: elapsedMilliseconds,
            currentBeat: display.beat,
            measures: contentMeasures()
        )
        dispatch(action)
    }

    private func dispatch(_ action: PreviewUbmAction) {
        if action.hiSpeedChanged { applyHiSpeed() }
        if action.realHSChanged || action.realHSExceedsCeiling {
            applyRealHS()
        }
        if action.bgaChanged { applyBGAMode() }
        if action.effectsChanged || action.layoutChanged { applyAppearance() }
        if action.alwaysOnTopChanged {
            window?.level = behavior.alwaysOnTop ? .floating : .normal
        }
        if action.soundChanged { applyAudibleKinds() }
        if action.infoChanged || action.hiSpeedChanged || action.realHSChanged || action.bgaChanged || action.soundChanged || action.playback != nil {
            syncCurrentInfo(throttle: false)
        }
        if let playback = action.playback {
            switch playback {
            case .pause: pauseEngine()
            case .resume: resumeEngine()
            }
        }
        if let seek = action.seek {
            seekReusingContext(to: seek.beat, paused: !seek.emitsSound)
        }
        if action.reloadChart {
            reloadFromCurrentDocument()
        }
    }

    private func applyHiSpeed() {
        behavior.hiSpeed = PreviewUbmBehavior.nearestHiSpeedDetent(behavior.hiSpeed)
        let pixels = PreviewWindowPlayback.hiSpeedBasePixelsPerBeat * behavior.hiSpeed
        setPreviewScrollPixelsPerBeat(pixels)
    }

    /// 按钮和菜单一次只提交一档，随即松开，避免把键留在按住集合里。
    private func stepSpeed(_ command: PreviewUbmCommand) {
        applyUbm(command, phase: .keyDown, elapsedMilliseconds: 0)
        applyUbm(command, phase: .keyUp, elapsedMilliseconds: 0)
    }

    private func selectHiSpeedDetent(_ index: Int) {
        let table = PreviewUbmBehavior.hiSpeedDetents
        guard table.indices.contains(index) else { return }
        behavior.hiSpeed = table[index]
        applyHiSpeed()
    }

    private func selectRealHSPercent(_ percent: Int) {
        behavior.realHS = percent
        applyRealHS()
        syncCurrentInfo(throttle: false)
    }

    private func applyBGAMode() {
        content.setBGADisplayMode(behavior.bgaRaw)
    }

    private func applyAppearance() {
        content.setUbmAppearance(
            scratchRaw: behavior.scratchRaw,
            effectsRaw: behavior.effectsRaw,
            autoSeparate: behavior.autoSeparate
        )
        refreshStageArrangement()
    }

    private func adoptDocument(_ data: Data) {
        chartFacts = PreviewUbmChartFacts.parse(data)
        chartPlayer = PreviewUbmChartFacts.playerHeader(from: data)
        loadedDocument = data
        refreshStageArrangement()
    }

    /// F2 只改 587 上的裁切和 BGA 位置。不重新 `setChart`，也不重开播放。
    private func refreshStageArrangement() {
        let packed = PreviewWindowPlayback.stageIsPacked(
            autoSeparate: behavior.autoSeparate,
            playerHeader: chartPlayer
        )
        guard content.setStagePacked(packed) else { return }
        content.layoutSubtreeIfNeeded()
        content.replayVisibleFrame()
    }

    /// 谱面秒走 `onElapsedSeconds`。这里只把 RealHS 交给播放速率，效果时钟不乘它。
    private func applyRealHS() {
        behavior.realHS = PreviewUbmBehavior.nearestRealHSDetent(behavior.realHS, ceiling: behavior.realHSCeiling)
        _ = behavior.clampRealHSToCeiling()
        player.setPlaybackRate(Double(behavior.realHS) / 100)
        let actual = player.requestedPlaybackRate
        if actual.isFinite, actual > 0 {
            let percent = Int((actual * 100).rounded())
            let snapped = PreviewUbmBehavior.nearestRealHSDetent(percent, ceiling: behavior.realHSCeiling)
            if snapped != behavior.realHS {
                behavior.realHS = snapped
                if abs(Double(snapped) / 100 - actual) > 0.001 {
                    player.setPlaybackRate(Double(snapped) / 100)
                }
            }
        }
        content.refreshSpeedPresentation(hiSpeed: displayedHiSpeed(), playbackRate: displayedPlaybackRate())
        forwardEngineRateToBGA()
    }

    /// 只把引擎已经生效的倍率交给 BGA。暂停不把这个值写成 0，帧循环也不调用这里。
    private func forwardEngineRateToBGA(force: Bool = false) {
        let actual = player.requestedPlaybackRate
        guard actual.isFinite, actual > 0 else { return }
        content.setBGAPlaybackRate(actual, force: force)
    }

    private func applyAudibleKinds() {
        player.setAudibleKinds(audibleKinds())
        soundFilterApplied = true
    }

    private func audibleKinds() -> Set<PreviewAudioKind> {
        var kinds = Set<PreviewAudioKind>()
        if behavior.allows(.bgm) { kinds.insert(.bgm) }
        if behavior.allows(.key) { kinds.insert(.key) }
        if behavior.allows(.mine) { kinds.insert(.mine) }
        return kinds
    }

    private func pauseEngine() {
        player.pauseChart()
        displaySync.detach()
        player.setPresentationClockExternallyDriven(true)
        externalClockWanted = true
        writeClock(
            beat: display.beat,
            elapsed: display.elapsedSeconds,
            isPlaying: false,
            isFinished: false,
            isPaused: true,
            bpm: displayedBPM,
            presentation: pictureSuppressed ? .logic : .deferred
        )
    }

    private func resumeEngine() {
        player.resumeChart()
        writeClock(
            beat: display.beat,
            elapsed: display.elapsedSeconds,
            isPlaying: true,
            isFinished: false,
            isPaused: false,
            bpm: displayedBPM,
            presentation: pictureSuppressed ? .logic : .deferred
        )
        if pictureSuppressed || !windowCanHostLink() {
            externalClockWanted = false
            player.setPresentationClockExternallyDriven(false)
            content.holdBGA(beat: display.beat, elapsedSeconds: display.elapsedSeconds)
        } else {
            engageDisplaySync()
        }
    }

    private func seekReusingContext(to beat: Double, paused: Bool) {
        guard let context = playheadContext else { return }
        play(
            explicitBeat: beat,
            startPaused: paused,
            context: context,
            rebindSurfaces: false
        )
    }

    private func reloadFromCurrentDocument() {
        let paused = behavior.paused
        onReloadPreview?()
        guard let context = documentSource() else { return }
        play(
            explicitBeat: 0,
            startPaused: paused,
            context: context,
            rebindSurfaces: true
        )
    }

    private func canAttachDisplayLink() -> Bool {
        guard !previewDisplayLinkSuppressed, !pictureSuppressed, windowCanHostLink() else { return false }
        return true
    }

    @discardableResult
    private func attachDisplayLink() -> Bool {
        guard canAttachDisplayLink(), let view = window?.contentView, let screen = window?.screen else {
            displaySync.detach()
            return false
        }
        return displaySync.attach(to: view, screen: screen)
    }

    private func engageDisplaySync() {
        guard display.isPlaying, !pictureSuppressed, !previewDisplayLinkSuppressed else { return }
        guard windowCanHostLink() else { return }
        player.setPresentationClockExternallyDriven(true)
        externalClockWanted = true
        if !attachDisplayLink() {
            externalClockWanted = false
            player.setPresentationClockExternallyDriven(false)
        }
    }

    /// 隐藏时关掉外部驱动，让播放器自己的定时器沿同一条 origin 走到终点。不停止播放。
    /// 已经藏起时再来的遮挡通知不再 `holdBGA`，否则隐藏期间每条通知都推一次视频。
    private func suspendPicture() {
        let alreadyHidden = pictureSuppressed
        displaySync.detach()
        pictureSuppressed = true
        if externalClockWanted {
            externalClockWanted = false
            player.setPresentationClockExternallyDriven(false)
        }
        guard display.isPlaying, !alreadyHidden else { return }
        content.holdBGA(beat: display.beat, elapsedSeconds: display.elapsedSeconds)
    }

    /// 重新可见后按同一条 origin 采样，不重新起播。嵌套调用不再推第二次 BGA。
    private func resumePicture() {
        let wasHidden = pictureSuppressed
        pictureSuppressed = false
        guard wasHidden || display.isPlaying else { return }
        guard !resumingPicture else { return }
        resumingPicture = true
        defer { resumingPicture = false }
        if display.isPlaying {
            engageDisplaySync()
            sampleSharedOrigin()
        } else {
            content.showPlayback(
                beat: display.beat,
                chartElapsed: display.elapsedSeconds,
                effectElapsed: effectElapsed,
                isPlaying: false
            )
            syncCurrentInfo(throttle: false)
        }
    }

    private func sampleSharedOrigin() {
        guard display.isPlaying else { return }
        presentedThisStep = false
        if externalClockWanted {
            displayStepActive = true
            player.advancePresentationClock()
            displayStepActive = false
        }
        if !presentedThisStep {
            writeClock(
                beat: display.beat,
                elapsed: display.elapsedSeconds,
                isPlaying: true,
                isFinished: false,
                bpm: displayedBPM,
                presentation: .display
            )
        }
    }

    /// 窗口还在屏幕上，可以挂显示器回调。遮挡与否由遮挡通知单独处理。
    private func windowCanHostLink() -> Bool {
        guard let window, window.isVisible, !window.isMiniaturized, window.contentView != nil else { return false }
        guard let screen = window.screen, screen.maximumFramesPerSecond > 0 else { return false }
        return true
    }

    private func isActivelyOnScreen() -> Bool {
        guard windowCanHostLink() else { return false }
        let occlusion = window?.occlusionState ?? []
        if occlusion.isEmpty { return true }
        return occlusion.contains(.visible)
    }

    fileprivate func performDisplayStep(fromDisplayCallback: Bool) {
        if display.isPlaying, !pictureSuppressed, windowCanHostLink() {
            pollHeldKeys()
        }
        guard display.isPlaying else {
            displaySync.detach()
            return
        }
        if pictureSuppressed {
            return
        }
        if fromDisplayCallback, !windowCanHostLink() {
            suspendPicture()
            return
        }
        previewDisplayStepCount += 1
        presentedThisStep = false
        if externalClockWanted {
            displayStepActive = true
            player.advancePresentationClock()
            displayStepActive = false
        }
        if !presentedThisStep, display.isPlaying {
            writeClock(
                beat: display.beat,
                elapsed: display.elapsedSeconds,
                isPlaying: true,
                isFinished: false,
                bpm: displayedBPM,
                presentation: .display
            )
        }
    }
}

private enum ClockPresentation {
    case deferred
    case display
    /// 隐藏期间只把拍、谱面秒和效果秒送进谱面逻辑。不提交画面，也不推动视频。
    case logic
}

/// 显示器垂直同步。回调如果落在后台线程，只跳回主线程，不在那边碰 AppKit。
@MainActor
private final class PreviewDisplaySync: NSObject {
    weak var owner: PreviewWindowController?
    private var link: CADisplayLink?
    private(set) var framesPerSecond = 0

    var isAttached: Bool { link != nil }

    func attach(to view: NSView, screen: NSScreen) -> Bool {
        let fps = screen.maximumFramesPerSecond
        guard fps > 0 else {
            detach()
            return false
        }
        if link == nil {
            let created = view.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            created.add(to: .main, forMode: .common)
            link = created
        }
        let rate = Float(fps)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        link?.isPaused = false
        framesPerSecond = fps
        return true
    }

    func detach() {
        link?.invalidate()
        link = nil
        framesPerSecond = 0
    }

    @objc nonisolated func handleDisplayLink(_ link: CADisplayLink) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.owner?.performDisplayStep(fromDisplayCallback: true)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.owner?.performDisplayStep(fromDisplayCallback: true)
                }
            }
        }
    }
}

@MainActor
private final class PreviewWindowContentView: NSView {
    private let playfield = PreviewPlayfieldView(frame: .zero)
    private let secondaryPlayfield = PreviewPlayfieldView(frame: .zero)
    private let primaryClip = NSView(frame: .zero)
    private let secondaryClip = NSView(frame: .zero)
    private(set) var stagePacked = false
    private var shownBeat = 0.0
    private var shownChartElapsed = 0.0
    private var shownEffectElapsed = 0.0
    private var shownPlaying = false
    private var nominalBGAFrame = CGRect.zero
    private var actualStageFrame = CGRect.zero
    private let bga = PreviewBGAView(frame: .zero)
    private let info = PreviewUbmInfoView(frame: .zero)
    private let controls = NSView()
    private let scrollValueLabel = NSTextField(labelWithString: "")
    private let sideControl: NSSegmentedControl
    private let scrollSlider = NSSlider(
        value: PreviewWindowPlayback.defaultPixelsPerBeat,
        minValue: PreviewWindowPlayback.minimumPixelsPerBeat,
        maxValue: PreviewWindowPlayback.maximumPixelsPerBeat,
        target: nil,
        action: nil
    )
    private let controlsToggle: NSButton
    private let hiSpeedValue = NSTextField(labelWithString: "1.00")
    private let rateValue = NSTextField(labelWithString: "1.00x")
    private let hiSpeedMenu = NSMenu(title: "HiSpeed")
    private let rateMenu = NSMenu(title: "Rate")
    private let shortcutMenu = NSMenu(title: "Shortcuts")
    private var hiSpeedMenuItem: NSMenuItem?
    private var rateMenuItem: NSMenuItem?
    private var bgaBinding: BGABinding?
    private var layingOut = false
    private var infoLayoutDeferred = false
    private(set) var controlsVisible = false
    private(set) var stageScale: CGFloat = 1
    private(set) var playfieldPlaybackUpdates = 0
    private(set) var bgaPlaybackUpdates = 0
    private(set) var bgaChartUpdates = 0
    private var appliedBGAPlaybackRate: Double?
    private(set) var playerSideApplies = 0
    private(set) var presentedFrameCount = 0
    private(set) var bgaFromBeat = 0.0
    private(set) var bgaChartTitle = ""
    private(set) var bgaDirectoryPath: String?

    var onPlayFromStart: (() -> Void)?
    var onPlayHere: (() -> Void)?
    var onStop: (() -> Void)?
    var onScroll: ((Double) -> Void)?
    var onPlayerSide: ((PreviewPlayerSide) -> Void)?
    var onPreviewKeyDown: ((NSEvent) -> Bool)?
    var onPreviewKeyUp: ((NSEvent) -> Bool)?
    var onPreviewScroll: ((NSEvent) -> Bool)?
    var onUbmToken: ((String) -> Void)?
    var onHiSpeedStep: ((Int) -> Void)?
    var onRealHSStep: ((Int) -> Void)?
    var onHiSpeedIndex: ((Int) -> Void)?
    var onRealHSPercent: ((Int) -> Void)?

    var playfieldPixelsPerBeat: Double { playfield.pixelsPerBeat }
    var infoText: String { info.text }
    var infoRasterCount: Int { info.rasterCount }
    var infoSourceImage: CGImage? { info.sourceImage }
    var infoPresentedImage: CGImage? { info.presentedImage }
    var infoLayoutSize: CGSize { info.layoutSize() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onPreviewKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if onPreviewKeyUp?(event) == true { return }
        super.keyUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if onPreviewScroll?(event) == true { return }
        super.scrollWheel(with: event)
    }

    func setBGADisplayMode(_ raw: Int) {
        bga.setDisplayMode(raw)
    }

    /// 只改已经建好的标题和勾。不新建菜单，也不重画点阵。
    func refreshSpeedPresentation(hiSpeed: Double, playbackRate: Double) {
        let hiText = PreviewWindowPlayback.formatDetent(hiSpeed)
        let rateText = PreviewWindowPlayback.formatDetent(playbackRate)
        if hiSpeedValue.stringValue != hiText {
            hiSpeedValue.stringValue = hiText
        }
        let rateLabel = "\(rateText)x"
        if rateValue.stringValue != rateLabel {
            rateValue.stringValue = rateLabel
        }
        hiSpeedMenuItem?.title = "HiSpeed \(hiText)"
        rateMenuItem?.title = "Rate \(rateLabel)"
        let hiIndex = PreviewUbmBehavior.hiSpeedDetents.firstIndex { abs($0 - hiSpeed) < 0.001 } ?? -1
        for item in hiSpeedMenu.items {
            item.state = item.tag == hiIndex ? .on : .off
        }
        let percent = Int((playbackRate * 100).rounded())
        for item in rateMenu.items {
            item.state = item.tag == percent ? .on : .off
        }
    }

    func setUbmAppearance(scratchRaw: Int, effectsRaw: Int, autoSeparate: Bool) {
        eachPlayfield {
            $0.setUbmAppearance(scratchRaw: scratchRaw, effectsRaw: effectsRaw, autoSeparate: autoSeparate)
        }
    }

    /// 分离和 packed 只改容器。`false` 表示 BGA 居中，不是把 331 再裁掉一截。
    @discardableResult
    func setStagePacked(_ packed: Bool) -> Bool {
        guard packed != stagePacked else { return false }
        stagePacked = packed
        needsLayout = true
        return true
    }

    func playfieldScene() -> PreviewPlayfieldScene {
        playfield.currentScene()
    }

    func secondaryScene() -> PreviewPlayfieldScene {
        secondaryPlayfield.currentScene()
    }

    func applyTiming(_ timing: PreviewAudioTiming, fromBeat: Double) {
        eachPlayfield { $0.setTiming(timing, fromBeat: fromBeat) }
    }

    func replayVisibleFrame() {
        presentPlaybackFrame(
            beat: shownBeat,
            chartElapsed: shownChartElapsed,
            effectElapsed: shownEffectElapsed,
            isPlaying: shownPlaying
        )
        syncBGA(beat: shownBeat, elapsedSeconds: shownChartElapsed, isPlaying: shownPlaying)
    }

    private func eachPlayfield(_ body: (PreviewPlayfieldView) -> Void) {
        body(playfield)
        body(secondaryPlayfield)
    }

    private func configureClip(_ clip: NSView, identifier: String) {
        clip.translatesAutoresizingMaskIntoConstraints = true
        clip.wantsLayer = true
        clip.clipsToBounds = true
        clip.layer?.masksToBounds = true
        clip.identifier = NSUserInterfaceItemIdentifier(identifier)
    }

    func bgaInspection() -> PreviewBGAInspection {
        bga.inspection()
    }

    func performMenuIdentifier(_ identifier: String) {
        guard let item = menuItem(identifier, in: menu) else { return }
        guard item.submenu == nil else { return }
        guard item.isEnabled, let action = item.action else { return }
        perform(action, with: item)
    }

    private func menuItem(_ identifier: String, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.identifier?.rawValue == identifier { return item }
            if let found = menuItem(identifier, in: item.submenu) { return found }
        }
        return nil
    }

    init(audioImplemented: Bool) {
        let sideLabels = [
            NativeLocalization.text("Both"),
            NativeLocalization.text("1P"),
            NativeLocalization.text("2P")
        ]
        sideControl = NSSegmentedControl(
            labels: sideLabels,
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        controlsToggle = NSButton(title: "Show", target: nil, action: nil)
        super.init(frame: NSRect(origin: .zero, size: PreviewWindowPlayback.defaultContentSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playfield.translatesAutoresizingMaskIntoConstraints = true
        playfield.identifier = NSUserInterfaceItemIdentifier("PreviewPlayfield")
        playfield.setAccessibilityIdentifier("PreviewPlayfield")
        secondaryPlayfield.translatesAutoresizingMaskIntoConstraints = true
        secondaryPlayfield.identifier = NSUserInterfaceItemIdentifier("PreviewPlayfieldSecondary")
        secondaryPlayfield.setAccessibilityIdentifier("PreviewPlayfieldSecondary")
        configureClip(primaryClip, identifier: "PreviewPlayfieldClip")
        configureClip(secondaryClip, identifier: "PreviewPlayfieldClipSecondary")
        bga.translatesAutoresizingMaskIntoConstraints = true
        bga.identifier = NSUserInterfaceItemIdentifier("PreviewBGA")
        bga.setAccessibilityIdentifier("PreviewBGA")
        info.translatesAutoresizingMaskIntoConstraints = true

        controls.translatesAutoresizingMaskIntoConstraints = true
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1).cgColor
        controls.identifier = NSUserInterfaceItemIdentifier("PreviewControls")

        let start = makeButton(
            "Play from Start",
            identifier: "PreviewPlayFromStart",
            action: #selector(playFromStartClicked),
            enabled: audioImplemented
        )
        let here = makeButton(
            "Play Here",
            identifier: "PreviewPlayHere",
            action: #selector(playHereClicked),
            enabled: audioImplemented
        )
        let stop = makeButton(
            "Stop",
            identifier: "PreviewStop",
            action: #selector(stopClicked),
            enabled: audioImplemented
        )

        sideControl.translatesAutoresizingMaskIntoConstraints = false
        sideControl.identifier = NSUserInterfaceItemIdentifier("PreviewPlayerSide")
        sideControl.setAccessibilityIdentifier("PreviewPlayerSide")
        sideControl.segmentStyle = .automatic
        sideControl.controlSize = .small
        sideControl.trackingMode = .selectOne
        sideControl.selectedSegment = 0
        sideControl.target = self
        sideControl.action = #selector(playerSideChanged(_:))
        sideControl.setContentHuggingPriority(.required, for: .horizontal)
        NativeLocalization.markFixed(sideControl, key: "Both")

        let scrollCaption = NSTextField(labelWithString: "SCROLL")
        NativeLocalization.markFixed(scrollCaption, key: "SCROLL")
        scrollCaption.stringValue = NativeLocalization.text("SCROLL")
        scrollCaption.font = .systemFont(ofSize: 11, weight: .medium)
        scrollCaption.textColor = NSColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1)

        scrollSlider.translatesAutoresizingMaskIntoConstraints = false
        scrollSlider.identifier = NSUserInterfaceItemIdentifier("PreviewScrollSpeed")
        scrollSlider.target = self
        scrollSlider.action = #selector(scrollChanged)
        scrollSlider.isContinuous = true
        scrollSlider.controlSize = .small
        scrollValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        scrollValueLabel.textColor = NSColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1)
        scrollValueLabel.alignment = .right

        controlsToggle.translatesAutoresizingMaskIntoConstraints = false
        controlsToggle.identifier = NSUserInterfaceItemIdentifier("PreviewControlsToggle")
        controlsToggle.bezelStyle = .rounded
        controlsToggle.controlSize = .small
        controlsToggle.target = self
        controlsToggle.action = #selector(toggleControls)
        controlsToggle.title = "Hide"

        configureSpeedLabel(hiSpeedValue, identifier: "PreviewHiSpeedValue")
        configureSpeedLabel(rateValue, identifier: "PreviewRateValue")
        hiSpeedValue.toolTip = "下落速度。1 降低，2 提高。0.50 到 5.00，每档 0.25。"
        rateValue.toolTip = "播放倍速。3 降低，4 提高。0.25x 到 4.00x，每档 0.25。不超过当前上限。"
        let hiDown = speedStepButton("-", identifier: "PreviewHiSpeedDown", action: #selector(hiSpeedDownClicked))
        let hiUp = speedStepButton("+", identifier: "PreviewHiSpeedUp", action: #selector(hiSpeedUpClicked))
        let rateDown = speedStepButton("-", identifier: "PreviewRateDown", action: #selector(rateDownClicked))
        let rateUp = speedStepButton("+", identifier: "PreviewRateUp", action: #selector(rateUpClicked))
        let hiCaption = speedCaption("HS")
        let rateCaption = speedCaption("Rate")
        let shortcuts = speedStepButton("Keys", identifier: "PreviewShortcutButton", action: #selector(shortcutButtonClicked))
        shortcuts.toolTip = "预览窗口焦点下的快捷键。编辑器焦点时数字键仍移动音符。"

        let transport = NSStackView(views: [start, here, stop, sideControl, scrollCaption, scrollSlider, scrollValueLabel, controlsToggle])
        transport.translatesAutoresizingMaskIntoConstraints = false
        transport.orientation = .horizontal
        transport.alignment = .centerY
        transport.spacing = 6
        let speeds = NSStackView(views: [
            hiCaption, hiDown, hiSpeedValue, hiUp,
            rateCaption, rateDown, rateValue, rateUp,
            shortcuts
        ])
        speeds.translatesAutoresizingMaskIntoConstraints = false
        speeds.orientation = .horizontal
        speeds.alignment = .centerY
        speeds.spacing = 4
        let rows = NSStackView(views: [transport, speeds])
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        controls.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: controls.trailingAnchor, constant: -8),
            rows.topAnchor.constraint(equalTo: controls.topAnchor, constant: 4),
            scrollSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            scrollSlider.widthAnchor.constraint(lessThanOrEqualToConstant: 96)
        ])

        primaryClip.addSubview(playfield)
        secondaryClip.addSubview(secondaryPlayfield)
        addSubview(bga)
        addSubview(primaryClip)
        addSubview(secondaryClip)
        addSubview(info)
        addSubview(controls)
        installMenu()
        applyPlayerSide(.both)
        setScroll(PreviewWindowPlayback.defaultPixelsPerBeat)
        setPlayfieldPixelsPerBeat(PreviewWindowPlayback.defaultPixelsPerBeat)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard !layingOut else { return }
        layingOut = true
        defer { layingOut = false }
        let strip = controlsVisible ? PreviewWindowPlayback.controlStripHeight : 0
        controls.frame = CGRect(x: 0, y: bounds.height - strip, width: bounds.width, height: strip)
        controls.isHidden = !controlsVisible
        let stage = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - strip))
        let placed = PreviewWindowPlayback.arrangedStage(in: stage, packed: stagePacked)
        stageScale = placed.scale
        primaryClip.frame = placed.primaryClip
        playfield.frame = CGRect(origin: .zero, size: placed.playfieldSize)
        secondaryClip.isHidden = placed.packed
        secondaryPlayfield.isHidden = placed.packed
        if placed.packed {
            secondaryClip.frame = .zero
        } else {
            secondaryClip.frame = placed.secondaryClip
            secondaryPlayfield.frame = CGRect(
                x: placed.secondaryViewX,
                y: 0,
                width: placed.playfieldSize.width,
                height: placed.playfieldSize.height
            )
        }
        nominalBGAFrame = placed.bga
        actualStageFrame = placed.stage
        bga.frame = placed.stage
        if placed.stage.width > 1, placed.stage.height > 1 {
            let origin = placed.packed ? 331.0 : 173.0
            bga.setStageLayout(bgaOriginX: origin, nativeCanvasSize: PreviewUbmStyle.canvasSize)
        }
        info.setMagnification(placed.scale)
        placeInfo(on: placed.bga)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "h" {
            toggleControls()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func bindSurfaces(
        _ chart: PreviewChartSnapshot,
        chartDirectory: URL?,
        timing: PreviewAudioTiming,
        fromBeat: Double,
        documentData: Data?
    ) {
        let binding = BGABinding(
            chart: chart,
            directoryPath: chartDirectory?.path,
            fromBeat: fromBeat,
            timing: timing,
            documentData: documentData
        )
        guard binding != bgaBinding else { return }
        bgaBinding = binding
        bgaChartUpdates += 1
        bgaFromBeat = fromBeat
        bgaChartTitle = chart.title
        bgaDirectoryPath = chartDirectory?.path
        eachPlayfield { $0.setChart(chart) }
        eachPlayfield { $0.setTiming(timing, fromBeat: fromBeat) }
        bga.setChart(
            chart,
            chartDirectory: chartDirectory,
            timing: timing,
            fromBeat: fromBeat,
            documentData: documentData
        )
    }

    func showPlayback(beat: Double, chartElapsed: Double, effectElapsed: Double, isPlaying: Bool) {
        rememberFrame(beat: beat, chartElapsed: chartElapsed, effectElapsed: effectElapsed, isPlaying: isPlaying)
        playfieldPlaybackUpdates += 1
        eachPlayfield {
            $0.setPlayback(
                beat: beat,
                chartElapsedSeconds: chartElapsed,
                effectElapsedSeconds: effectElapsed,
                isPlaying: isPlaying
            )
        }
        syncBGA(beat: beat, elapsedSeconds: chartElapsed, isPlaying: isPlaying)
    }

    func presentPlaybackFrame(
        beat: Double,
        chartElapsed: Double,
        effectElapsed: Double,
        isPlaying: Bool
    ) {
        rememberFrame(beat: beat, chartElapsed: chartElapsed, effectElapsed: effectElapsed, isPlaying: isPlaying)
        presentedFrameCount += 1
        playfield.presentPlaybackFrame(
            beat: beat,
            chartElapsedSeconds: chartElapsed,
            effectElapsedSeconds: effectElapsed,
            isPlaying: isPlaying
        )
        if !secondaryPlayfield.isHidden {
            secondaryPlayfield.presentPlaybackFrame(
                beat: beat,
                chartElapsedSeconds: chartElapsed,
                effectElapsedSeconds: effectElapsed,
                isPlaying: isPlaying
            )
        }
    }

    private func rememberFrame(
        beat: Double,
        chartElapsed: Double,
        effectElapsed: Double,
        isPlaying: Bool
    ) {
        shownBeat = beat
        shownChartElapsed = chartElapsed
        shownEffectElapsed = effectElapsed
        shownPlaying = isPlaying
    }

    func advancePlaybackClock(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool
    ) {
        rememberFrame(
            beat: beat,
            chartElapsed: chartElapsedSeconds,
            effectElapsed: effectElapsedSeconds,
            isPlaying: isPlaying
        )
        eachPlayfield {
            $0.advancePlaybackClock(
                beat: beat,
                chartElapsedSeconds: chartElapsedSeconds,
                effectElapsedSeconds: effectElapsedSeconds,
                isPlaying: isPlaying
            )
        }
    }

    func setBGAPlaybackRate(_ rate: Double, force: Bool = false) {
        guard rate.isFinite, rate > 0 else { return }
        if !force, let appliedBGAPlaybackRate, abs(appliedBGAPlaybackRate - rate) <= 0.000_001 {
            return
        }
        appliedBGAPlaybackRate = rate
        bga.setPlaybackRate(rate)
    }

    func syncBGA(beat: Double, elapsedSeconds: Double, isPlaying: Bool) {
        bgaPlaybackUpdates += 1
        bga.setPlayback(beat: beat, elapsedSeconds: elapsedSeconds, isPlaying: isPlaying)
    }

    /// 同一条时间轴还在走，只让视频停在当前帧。
    func holdBGA(beat: Double, elapsedSeconds: Double) {
        bgaPlaybackUpdates += 1
        bga.setPlayback(beat: beat, elapsedSeconds: elapsedSeconds, isPlaying: false)
    }

    /// 相同文字不栅格化。只有行数或列数变了才重新摆框，时钟百分秒不带动整块舞台。
    /// `throttle` 保留给显示器拍和其余更新；两种都立刻换字，不再按 0.25 秒丢掉。
    /// `presents == false` 时只改缓存：不画、不 `layoutSubtreeIfNeeded`，因此不会进到 `layout` 里的 `setStageLayout`。
    func syncInfo(_ text: String, throttle _: Bool, presents: Bool = true) {
        let previousSize = info.layoutSize()
        if text != info.text {
            if presents {
                info.setText(text)
            } else {
                info.rememberText(text)
            }
            info.setAccessibilityValue(text)
            info.setAccessibilityIdentifier("PreviewStatus")
        }
        let sizeChanged = info.layoutSize() != previousSize
        if !presents {
            if sizeChanged { infoLayoutDeferred = true }
            return
        }
        if info.needsPresentation {
            info.presentStoredImage()
        }
        guard sizeChanged || infoLayoutDeferred else { return }
        infoLayoutDeferred = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        info.presentStoredImage()
    }

    func setControlsVisible(_ visible: Bool) {
        guard visible != controlsVisible else { return }
        controlsVisible = visible
        let title = visible ? "Hide" : "Show"
        controlsToggle.title = title
        if let item = menu?.items.first(where: { $0.identifier?.rawValue == "PreviewControlsMenu" }) {
            item.title = title
        }
        needsLayout = true
    }

    func applyPlayerSide(_ side: PreviewPlayerSide) {
        playerSideApplies += 1
        eachPlayfield { $0.setPlayerSide(side) }
        let index: Int
        switch side {
        case .onePlayer: index = 1
        case .twoPlayer: index = 2
        case .both: index = 0
        }
        if sideControl.selectedSegment != index {
            sideControl.selectedSegment = index
        }
    }

    func setScroll(_ pixelsPerBeat: Double) {
        scrollSlider.doubleValue = pixelsPerBeat
        scrollValueLabel.stringValue = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), pixelsPerBeat)
    }

    func setPlayfieldPixelsPerBeat(_ pixelsPerBeat: Double) {
        eachPlayfield { $0.pixelsPerBeat = pixelsPerBeat }
    }

    func layoutSnapshot() -> PreviewWindowLayout {
        let playfieldFrame = primaryClip.frame
        let secondFrame = secondaryClip.isHidden ? CGRect.zero : secondaryClip.frame
        let nominal = nominalBGAFrame
        let adjacent = playfieldFrame.width > 1 && nominal.width > 1
            && abs(playfieldFrame.maxX - nominal.minX) < 1
            && abs(playfieldFrame.minY - nominal.minY) < 1
        return PreviewWindowLayout(
            sideBySide: adjacent,
            packed: stagePacked,
            playfieldFrame: playfieldFrame,
            secondPlayfieldFrame: secondFrame,
            bgaFrame: nominal,
            nominalBGAFrame: nominal,
            actualStageFrame: actualStageFrame,
            stageScale: stageScale,
            controlsFrame: controlsVisible ? controls.frame : .zero,
            infoFrame: info.isHidden ? .zero : info.frame
        )
    }

    private func placeInfo(on bgaFrame: CGRect) {
        guard bgaFrame.width > 8, bgaFrame.height > 8, !info.text.isEmpty else {
            info.isHidden = true
            info.frame = .zero
            return
        }
        info.isHidden = false
        info.clipsToBounds = true
        let inset = max(4, 4 * stageScale)
        let maxWidth = max(1, bgaFrame.width * 0.90)
        let maxHeight = max(1, bgaFrame.height * 0.42)
        let native = info.layoutSize()
        let scale = stageScale > 0 ? stageScale : 1
        var frame = CGRect(
            x: 0,
            y: 0,
            width: min(max(native.width * scale, 1), maxWidth),
            height: min(max(native.height * scale, 1), maxHeight)
        )
        frame.origin.x = min(bgaFrame.minX + inset, bgaFrame.maxX - frame.width - 1)
        frame.origin.y = bgaFrame.maxY - inset - frame.height
        if frame.minX < bgaFrame.minX { frame.origin.x = bgaFrame.minX }
        if frame.minY < bgaFrame.minY { frame.origin.y = bgaFrame.minY }
        if frame.maxX > bgaFrame.maxX { frame.size.width = max(1, bgaFrame.maxX - frame.minX - 1) }
        if frame.maxY > bgaFrame.maxY { frame.size.height = max(1, bgaFrame.maxY - frame.minY - 1) }
        info.frame = frame
    }

    private func installMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Play from Start", action: #selector(playFromStartClicked)))
        menu.addItem(menuItem("Play Here", action: #selector(playHereClicked)))
        menu.addItem(menuItem("Stop", action: #selector(stopClicked)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Show", action: #selector(toggleControls), identifier: "PreviewControlsMenu"))
        menu.addItem(.separator())
        menu.addItem(tokenItem("Pause", token: "0", identifier: "PreviewPauseMenu"))
        menu.addItem(tokenItem("BGA", token: "5", identifier: "PreviewBGAMenu"))
        menu.addItem(tokenItem("Effect", token: "6", identifier: "PreviewEffectMenu"))
        menu.addItem(tokenItem("Always on Top", token: "7", identifier: "PreviewTopMenu"))
        menu.addItem(tokenItem("Scratch", token: "8", identifier: "PreviewScratchMenu"))
        menu.addItem(tokenItem("Info", token: "9", identifier: "PreviewInfoMenu"))
        menu.addItem(tokenItem("Sound", token: "\u{F704}", identifier: "PreviewSoundMenu"))
        menu.addItem(tokenItem("Auto Separate", token: "\u{F705}", identifier: "PreviewSeparateMenu"))
        installSpeedMenus(into: menu)
        self.menu = menu
        refreshSpeedPresentation(hiSpeed: 1, playbackRate: 1)
    }

    /// 档位和快捷键说明只在这里建一次。之后刷新只改标题和勾选。
    private func installSpeedMenus(into menu: NSMenu) {
        hiSpeedMenu.autoenablesItems = false
        for (index, detent) in PreviewUbmBehavior.hiSpeedDetents.enumerated() {
            let title = PreviewWindowPlayback.formatDetent(detent)
            let item = NSMenuItem(title: title, action: #selector(hiSpeedDetentClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.identifier = NSUserInterfaceItemIdentifier("PreviewHiSpeedDetent-\(index)")
            hiSpeedMenu.addItem(item)
        }
        let hiSpeed = NSMenuItem(title: "HiSpeed 1.00", action: nil, keyEquivalent: "")
        hiSpeed.identifier = NSUserInterfaceItemIdentifier("PreviewHiSpeedMenu")
        hiSpeed.submenu = hiSpeedMenu
        hiSpeedMenuItem = hiSpeed
        menu.addItem(hiSpeed)

        rateMenu.autoenablesItems = false
        for percent in PreviewUbmBehavior.realHSDetents {
            let title = "\(PreviewWindowPlayback.formatDetent(Double(percent) / 100))x"
            let item = NSMenuItem(title: title, action: #selector(rateDetentClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            item.identifier = NSUserInterfaceItemIdentifier("PreviewRateDetent-\(percent)")
            rateMenu.addItem(item)
        }
        let rate = NSMenuItem(title: "Rate 1.00x", action: nil, keyEquivalent: "")
        rate.identifier = NSUserInterfaceItemIdentifier("PreviewRealHSMenu")
        rate.submenu = rateMenu
        rateMenuItem = rate
        menu.addItem(rate)

        shortcutMenu.autoenablesItems = false
        let help = [
            "1  降低下落速度一档",
            "2  提高下落速度一档",
            "同时按住 1 和 2：朝 1.00 移动一档",
            "3  降低播放倍速一档",
            "4  提高播放倍速一档",
            "同时按住 3 和 4：朝 1.00x 移动一档",
            "松开后再按才进入下一档。按住不会连跳。",
            "HiSpeed 档位 0.50…5.00，每档 0.25。",
            "播放倍速 0.25x…4.00x，每档 0.25，不超过当前上限。",
            "F1、F2、方向键、Page、Home、End 若被系统占用，请同时按 Fn。",
            "数字键只在预览窗口获得键盘焦点时生效。",
            "编辑器获得焦点时，数字键仍移动已选音符。"
        ]
        for (index, line) in help.enumerated() {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.identifier = NSUserInterfaceItemIdentifier("PreviewShortcutHelp-\(index)")
            shortcutMenu.addItem(item)
        }
        let shortcuts = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        shortcuts.identifier = NSUserInterfaceItemIdentifier("PreviewShortcutMenu")
        shortcuts.submenu = shortcutMenu
        menu.addItem(shortcuts)
    }

    private func tokenItem(_ title: String, token: String, identifier: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ubmTokenClicked(_:)), keyEquivalent: "")
        item.target = self
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        item.representedObject = token
        return item
    }

    @objc private func ubmTokenClicked(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String else { return }
        onUbmToken?(token)
    }

    private func menuItem(_ key: String, action: Selector, identifier: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: NativeLocalization.text(key), action: action, keyEquivalent: "")
        item.target = self
        if let identifier {
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        return item
    }

    private func makeButton(
        _ key: String,
        identifier: String,
        action: Selector,
        enabled: Bool
    ) -> NSButton {
        let button = NSButton(title: key, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.isEnabled = enabled
        NativeLocalization.markFixed(button, key: key)
        button.title = NativeLocalization.text(key)
        return button
    }

    @objc private func playFromStartClicked() {
        onPlayFromStart?()
    }

    @objc private func playHereClicked() {
        onPlayHere?()
    }

    @objc private func stopClicked() {
        onStop?()
    }

    @objc private func scrollChanged() {
        onScroll?(scrollSlider.doubleValue)
    }

    @objc private func playerSideChanged(_ sender: NSSegmentedControl) {
        let side: PreviewPlayerSide
        switch sender.selectedSegment {
        case 1: side = .onePlayer
        case 2: side = .twoPlayer
        default: side = .both
        }
        onPlayerSide?(side)
    }

    @objc private func toggleControls() {
        setControlsVisible(!controlsVisible)
    }

    private func configureSpeedLabel(_ label: NSTextField, identifier: String) {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1)
        label.alignment = .right
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.setAccessibilityIdentifier(identifier)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.lineBreakMode = .byClipping
    }

    private func speedCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(srgbRed: 0.75, green: 0.78, blue: 0.82, alpha: 1)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func speedStepButton(_ title: String, identifier: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.isContinuous = false
        button.setButtonType(.momentaryPushIn)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    @objc private func hiSpeedDownClicked() {
        onHiSpeedStep?(-1)
    }

    @objc private func hiSpeedUpClicked() {
        onHiSpeedStep?(1)
    }

    @objc private func rateDownClicked() {
        onRealHSStep?(-1)
    }

    @objc private func rateUpClicked() {
        onRealHSStep?(1)
    }

    @objc private func hiSpeedDetentClicked(_ sender: NSMenuItem) {
        onHiSpeedIndex?(sender.tag)
    }

    @objc private func rateDetentClicked(_ sender: NSMenuItem) {
        onRealHSPercent?(sender.tag)
    }

    @objc private func shortcutButtonClicked(_ sender: NSButton) {
        shortcutMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
}

private struct BGABinding: Equatable {
    var chart: PreviewChartSnapshot
    var directoryPath: String?
    var fromBeat: Double
    var timing: PreviewAudioTiming
    var documentData: Data?
}
