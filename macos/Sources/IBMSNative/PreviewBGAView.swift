import AppKit
import AVFoundation
import ImageIO
import QuartzCore

/// 预览 BGA。画面时钟只使用调用方传入的拍和 elapsed，这里不建定时器。
/// 基础层、叠加层和 POOR 用 `CALayer.contents` 合成。MP4 仍用 `AVPlayerLayer`。
/// WMV/ASF 走 `PreviewVideoClock`，按调用方给出的媒体秒取帧。
/// 键 5 五态见 `PreviewBGADisplayMode`。通常显示不解码 POOR。
/// 关闭态不解析路径、不解码、不准备视频。叠加层按透明阈值做黑键，基础层和 POOR 保留原色。
@MainActor
final class PreviewBGAView: NSView {
    private let base = PreviewBGAChannel(blackKey: false)
    private let overlay = PreviewBGAChannel(blackKey: true)
    private let poorChannel = PreviewBGAChannel(blackKey: false)
    private let cache = PreviewBGAImageCache()
    private let statusField = NSTextField(labelWithString: PreviewBGAChrome.empty)

    private var generation: UInt64 = 0
    private var chartDirectory: URL?
    private var timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
    private var playbackOrigin: Double = 0
    private var assets: [String: String] = [:]
    private var index = PreviewBGAEventIndex(events: [])
    private var eventIndexBuildCount = 0
    private var poorAssetID: String?
    private var poorFileName: String?
    private var imageDecodeCount = 0
    private var wantsPlayback = false
    private var displayMode: PreviewBGADisplayMode = .normal
    private var transparencyThreshold: UInt8 = 0
    private var lastBeat: Double = 0
    private var lastElapsed: Double = 0
    private var lastPlaying = false
    private let stage = CALayer()
    private let column = CALayer()
    private var script = PreviewBGAScript.Map()
    private var scriptParseCount = 0
    private var usesBMSIndex = false
    private var originX: Double = 0
    private var canvasSize = CGSize(width: 256, height: 256)
    /// 未设置时为 1，和原来的 `play()` 一致。0.25…4 以外的值不覆盖。
    private var playbackRate: Double = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setChart(
        _ chart: PreviewChartSnapshot,
        chartDirectory: URL?,
        timing: PreviewAudioTiming,
        fromBeat: Double,
        documentData: Data? = nil
    ) {
        generation &+= 1
        self.chartDirectory = chartDirectory
        self.timing = timing
        playbackOrigin = fromBeat.isFinite ? fromBeat : 0
        assets = [:]
        for asset in chart.bgaAssets {
            let id = asset.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            assets[id] = asset.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let documentData {
            script = PreviewBGAScript.parse(documentData)
            scriptParseCount += 1
        } else {
            script = PreviewBGAScript.Map()
        }
        usesBMSIndex = script.hasHeaders
        for (bmpIndex, name) in script.bmps {
            let key = PreviewBGAScript.token(bmpIndex)
            if assets[key] == nil {
                assets[key] = name
            }
        }
        index = PreviewBGAEventIndex(events: chart.bgaEvents)
        eventIndexBuildCount += 1
        poorAssetID = nil
        poorFileName = nil
        wantsPlayback = false
        base.reset()
        overlay.reset()
        poorChannel.reset()
        apply(beat: playbackOrigin, elapsedSeconds: 0, isPlaying: false)
    }

    /// 名义列左缘和整舞台客户区。默认 0、256×256，单视图仍可直接用。
    /// 窗口以后传 173 或 331，以及 587×256。非法尺寸保持原布局。
    func setStageLayout(bgaOriginX: Double, nativeCanvasSize: CGSize) {
        guard bgaOriginX.isFinite, abs(bgaOriginX) <= Double(PreviewBGAGeometry.maxAbsCoordinate),
              nativeCanvasSize.width.isFinite, nativeCanvasSize.height.isFinite,
              nativeCanvasSize.width > 0, nativeCanvasSize.height > 0,
              nativeCanvasSize.width <= 4096, nativeCanvasSize.height <= 4096 else { return }
        originX = bgaOriginX
        canvasSize = nativeCanvasSize
        placeLayers()
    }

    /// uBMplay 键 5。`mode` 为 0…4，见 `PreviewBGADisplayMode`。非法值保持原态。
    /// 立刻按上次保存的拍、elapsed、播放状态重铺当前层，不重建事件索引，不调用 `setChart`。
    func setDisplayMode(_ mode: Int) {
        guard let next = PreviewBGADisplayMode(rawValue: mode) else { return }
        displayMode = next
        apply(beat: lastBeat, elapsedSeconds: lastElapsed, isPlaying: lastPlaying)
    }

    /// uBMplay ini `Transparent`。0 只抠 RGB 全 0，255 叠加层全透明。只在解码时应用一次。
    func setTransparencyThreshold(_ threshold: UInt8) {
        transparencyThreshold = threshold
        apply(beat: lastBeat, elapsedSeconds: lastElapsed, isPlaying: lastPlaying)
    }

    func setPlayback(beat: Double, elapsedSeconds: Double, isPlaying: Bool) {
        let shownBeat = beat.isFinite ? beat : playbackOrigin
        apply(beat: shownBeat, elapsedSeconds: elapsedSeconds, isPlaying: isPlaying)
    }

    /// 窗口转发 `engine.requestedPlaybackRate`。只接受有限的 0.25…4。
    /// 换谱、换事件、切模式都保留这个值。暂停时播放器速率归零，请求值仍在。
    func setPlaybackRate(_ rate: Double) {
        guard rate.isFinite, rate >= 0.25, rate <= 4 else { return }
        guard playbackRate != rate else { return }
        playbackRate = rate
        base.adoptRate(rate)
        overlay.adoptRate(rate)
        poorChannel.adoptRate(rate)
    }

    func inspection() -> PreviewBGAInspection {
        let channels = [base, overlay, poorChannel]
        let players = channels.compactMap { $0.player }
        let nativeOpen = channels.contains { $0.nativeAttached }
        let playerMuted = players.allSatisfy { $0.isMuted && $0.volume == 0 }
        let nativeMuted = channels.filter(\.nativeAttached).allSatisfy(\.nativeSilenced)
        let muted = (!players.isEmpty || nativeOpen) && (players.isEmpty || playerMuted) && (!nativeOpen || nativeMuted)
        let playerTime = players.first?.currentTime().seconds
        let nativeTime = channels.compactMap { $0.nativePresentedSeconds }.first
        let current: Double? = playerTime?.isFinite == true ? playerTime : nativeTime
        var rates = players.map(\.rate)
        rates.append(contentsOf: channels.compactMap { $0.nativeOutputRate })
        let native = channels.map { $0.nativeSnapshot() }
        return PreviewBGAInspection(
            status: statusField.stringValue,
            baseAssetID: base.assetID,
            layerAssetID: overlay.assetID,
            poorAssetID: poorAssetID,
            poorFileName: poorFileName,
            imageDecodeCount: imageDecodeCount,
            videoSeekCount: channels.reduce(0) { $0 + $1.seekCount },
            lastVideoSeekSeconds: channels.compactMap { $0.lastSeekSeconds }.first,
            expectedVideoSeconds: channels.compactMap { $0.expectedMediaSeconds }.first,
            currentVideoSeconds: current?.isFinite == true ? current : nil,
            videoAttached: !players.isEmpty || nativeOpen,
            videoMuted: muted,
            videoAudioDisabled: channels.contains { $0.audioDisabled },
            videoAudioTrackCount: channels.map { $0.audioTrackCount }.max() ?? 0,
            videoItemError: channels.compactMap { $0.player?.currentItem?.error?.localizedDescription }.first
                ?? channels.compactMap { $0.nativeError }.first,
            pathResolveCount: channels.reduce(0) { $0 + $1.pathResolveCount },
            timingEvaluationCount: channels.reduce(0) { $0 + $1.timingEvaluationCount },
            videoOpenCount: channels.reduce(0) { $0 + $1.videoOpenCount },
            videoRate: players.first?.rate ?? channels.compactMap { $0.nativeOutputRate }.first,
            videoRates: rates,
            requestedPlaybackRate: playbackRate,
            enabledAudioTrackCount: channels.reduce(0) { count, channel in
                count + channel.enabledAudioTrackCount
            },
            videoTransportCount: channels.reduce(0) { $0 + $1.transportCommandCount },
            videoLayoutCount: channels.reduce(0) { $0 + $1.videoLayoutCount },
            videoItemKept: players.contains { $0.currentItem != nil } || channels.contains { $0.nativeItemKept },
            baseImageReady: base.imageReady,
            layerImageReady: overlay.imageReady,
            poorImageReady: poorChannel.imageReady,
            generation: generation,
            displayMode: displayMode.rawValue,
            transparencyThreshold: transparencyThreshold,
            eventIndexBuildCount: eventIndexBuildCount,
            scriptParseCount: scriptParseCount,
            nativeCodecName: native.compactMap { $0.codec.isEmpty ? nil : $0.codec }.first ?? "",
            nativeFormatName: native.compactMap { $0.format.isEmpty ? nil : $0.format }.first ?? "",
            nativePresentedPTS: native.compactMap(\.pts).first,
            nativeResidentBytes: native.reduce(0) { $0 + $1.residentBytes },
            nativePeakResidentBytes: native.map(\.peakResidentBytes).max() ?? 0,
            nativeDecodedFrameCount: native.reduce(0) { $0 + $1.decodedFrames },
            nativeAudioDecodedPackets: native.reduce(0) { $0 + $1.audioDecodedPackets },
            nativeAudioDiscardedPackets: native.reduce(0) { $0 + $1.audioDiscardedPackets },
            nativeDroppedStale: native.reduce(0) { $0 + $1.droppedStale },
            nativeOriginalWidth: native.map(\.originalWidth).max() ?? 0,
            nativeOriginalHeight: native.map(\.originalHeight).max() ?? 0
        )
    }

    func presentedNativeVideo(_ layer: PreviewBGALayer) -> PreviewNativeVideoPicture? {
        switch layer {
        case .base: return base.nativePicture()
        case .layer: return overlay.nativePicture()
        case .poor: return poorChannel.nativePicture()
        }
    }

    override func layout() {
        super.layout()
        placeLayers()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            base.holdFrame()
            overlay.holdFrame()
            poorChannel.holdFrame()
            wantsPlayback = false
            updateChrome()
        }
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = PreviewBGAChrome.clear
        layer?.masksToBounds = true
        stage.masksToBounds = true
        stage.backgroundColor = PreviewBGAChrome.clear
        column.backgroundColor = PreviewBGAChrome.background
        column.zPosition = -1
        if stage.superlayer == nil {
            layer?.addSublayer(stage)
            stage.addSublayer(column)
        }
        statusField.alignment = .center
        statusField.textColor = NSColor(srgbRed: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        statusField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusField.maximumNumberOfLines = 3
        statusField.lineBreakMode = .byWordWrapping
        statusField.cell?.wraps = true
        statusField.cell?.isScrollable = false
        addSubview(statusField)
        base.install(on: stage)
        overlay.install(on: stage)
        poorChannel.install(on: stage)
        base.onChange = { [weak self] in self?.updateChrome() }
        overlay.onChange = { [weak self] in self?.updateChrome() }
        poorChannel.onChange = { [weak self] in self?.updateChrome() }
        clipsToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        placeLayers()
        updateChrome()
    }

    private func placeLayers() {
        guard let root = layer else { return }
        let bounds = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        root.bounds = CGRect(origin: .zero, size: bounds.size)
        root.backgroundColor = PreviewBGAChrome.clear
        root.masksToBounds = true
        root.contentsScale = 1
        stage.contentsScale = 1
        column.contentsScale = 1
        let metrics = PreviewBGAStageMetrics(viewSize: bounds.size, canvas: canvasSize)
        stage.frame = metrics.contentFrame
        stage.bounds = CGRect(origin: .zero, size: metrics.contentFrame.size)
        column.frame = metrics.columnFrame(originX: originX)
        let scale = metrics.scale
        base.updatePlan(picturePlan(for: base.presentedItem), scale: scale)
        overlay.updatePlan(picturePlan(for: overlay.presentedItem), scale: scale)
        poorChannel.updatePlan(picturePlan(for: poorChannel.presentedItem), scale: scale)
        let height: CGFloat = 48
        statusField.frame = CGRect(
            x: 8,
            y: max(0, (bounds.height - height) / 2),
            width: max(0, bounds.width - 16),
            height: height
        )
        CATransaction.commit()
    }

    private func apply(beat: Double, elapsedSeconds: Double, isPlaying: Bool) {
        let shownBeat = beat.isFinite ? beat : playbackOrigin
        let elapsed = elapsedSeconds.isFinite ? max(0, elapsedSeconds) : 0
        lastBeat = shownBeat
        lastElapsed = elapsed
        lastPlaying = isPlaying
        wantsPlayback = isPlaying
        let showBase = displayMode == .baseOnly || displayMode == .normal
        let showLayer = displayMode == .layerOnly || displayMode == .normal
        let showPoor = displayMode == .alwaysPoor
        sync(
            base,
            event: showBase ? drawableEvent(index.event(at: shownBeat, layer: .base), layer: .base) : nil,
            enabled: showBase,
            elapsed: elapsed,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
        sync(
            overlay,
            event: showLayer ? drawableEvent(index.event(at: shownBeat, layer: .layer), layer: .layer) : nil,
            enabled: showLayer,
            elapsed: elapsed,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
        sync(
            poorChannel,
            event: showPoor ? poorEvent(at: shownBeat) : nil,
            enabled: showPoor,
            elapsed: elapsed,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
        storePoor(at: shownBeat)
        updateChrome()
    }

    private func drawableEvent(
        _ event: PreviewBGAEventIndex.Item?,
        layer: PreviewBGALayer
    ) -> PreviewBGAEventIndex.Item? {
        guard let event else { return nil }
        if layer != .poor, usesBMSIndex, PreviewBGAScript.index(from: event.assetID) == 0 {
            return nil
        }
        return event
    }

    private func poorEvent(at beat: Double) -> PreviewBGAEventIndex.Item? {
        if let event = index.event(at: beat, layer: .poor) {
            return event
        }
        guard usesBMSIndex, poorSourceAvailable() else { return nil }
        return PreviewBGAEventIndex.Item(beat: beat, assetID: "00", sequence: -1)
    }

    private func poorSourceAvailable() -> Bool {
        if let crop = script.crops[0], crop.source >= 0 {
            return fileName(bmp: crop.source) != nil
        }
        return fileName(bmp: 0) != nil
    }

    private func fileName(bmp index: Int) -> String? {
        let key = PreviewBGAScript.token(index)
        guard let name = assets[key], !name.isEmpty else { return nil }
        return name
    }

    private func preferredFile(for event: PreviewBGAEventIndex.Item?) -> String? {
        guard let event, let index = PreviewBGAScript.index(from: event.assetID),
              let crop = script.crops[index], crop.source >= 0 else { return nil }
        return fileName(bmp: crop.source) ?? ""
    }

    private func picturePlan(for event: PreviewBGAEventIndex.Item?) -> PreviewBGAPicturePlan {
        var crop: PreviewBGACropBox?
        if let event, let index = PreviewBGAScript.index(from: event.assetID),
           let defined = script.crops[index], defined.source >= 0 {
            crop = defined.box
        }
        return PreviewBGAPicturePlan(
            crop: crop,
            originX: Int(originX.rounded(.towardZero)),
            stageWidth: Int(canvasSize.width.rounded(.towardZero)),
            stageHeight: Int(canvasSize.height.rounded(.towardZero))
        )
    }

    private func sync(
        _ channel: PreviewBGAChannel,
        event: PreviewBGAEventIndex.Item?,
        enabled: Bool,
        elapsed: Double,
        isPlaying: Bool,
        playbackRate: Double
    ) {
        let metrics = PreviewBGAStageMetrics(viewSize: bounds.size, canvas: canvasSize)
        channel.sync(
            event: event,
            assets: assets,
            chartDirectory: chartDirectory,
            playbackOrigin: playbackOrigin,
            elapsed: elapsed,
            timing: timing,
            isPlaying: isPlaying,
            generation: generation,
            threshold: transparencyThreshold,
            enabled: enabled,
            cache: cache,
            preferredFile: preferredFile(for: event),
            plan: picturePlan(for: event),
            scale: metrics.scale,
            playbackRate: playbackRate,
            scheduleDecode: { [weak self] in self?.imageDecodeCount += 1 }
        )
    }

    private func storePoor(at beat: Double) {
        if let event = index.event(at: beat, layer: .poor) {
            let id = event.assetID.trimmingCharacters(in: .whitespacesAndNewlines)
            poorAssetID = id.isEmpty ? nil : id
            poorFileName = id.isEmpty ? nil : assets[id]
            return
        }
        if displayMode == .alwaysPoor, usesBMSIndex, poorSourceAvailable() {
            poorAssetID = "00"
            poorFileName = fileName(bmp: 0)
            return
        }
        poorAssetID = nil
        poorFileName = nil
    }

    private func updateChrome() {
        let channels = [base, overlay, poorChannel]
        let failures = channels.compactMap { $0.failure }
        let showingImage = channels.contains { $0.imageReady }
        let showingVideo = channels.contains { $0.player != nil || $0.nativeAttached }
        let waitingVideo = channels.contains { $0.kind == .video && $0.player == nil && !$0.nativeAttached && $0.failure == nil }
            && !showingVideo && failures.isEmpty
        let loadingImage = channels.contains { $0.kind == .image && !$0.imageReady && $0.failure == nil }
        if showingImage || showingVideo {
            statusField.isHidden = true
            statusField.stringValue = failures.isEmpty ? "BGA" : failures.joined(separator: "\n")
        } else if waitingVideo {
            statusField.isHidden = false
            statusField.stringValue = PreviewBGAChrome.videoIdle
        } else if let failure = failures.first {
            statusField.isHidden = false
            statusField.stringValue = failures.count == 1 ? failure : failures.joined(separator: "\n")
        } else if loadingImage {
            statusField.isHidden = true
            statusField.stringValue = "BGA"
        } else {
            statusField.isHidden = false
            statusField.stringValue = PreviewBGAChrome.empty
        }
        setAccessibilityLabel(statusField.stringValue)
    }
}

struct PreviewBGAInspection: Equatable {
    var status: String
    var baseAssetID: String?
    var layerAssetID: String?
    var poorAssetID: String?
    var poorFileName: String?
    var imageDecodeCount: Int
    var videoSeekCount: Int
    var lastVideoSeekSeconds: Double?
    var expectedVideoSeconds: Double?
    var currentVideoSeconds: Double?
    var videoAttached: Bool
    var videoMuted: Bool
    var videoAudioDisabled: Bool
    var videoAudioTrackCount: Int
    var videoItemError: String?
    var pathResolveCount: Int
    var timingEvaluationCount: Int
    var videoOpenCount: Int
    var videoRate: Float?
    var videoRates: [Float]
    var requestedPlaybackRate: Double
    var enabledAudioTrackCount: Int
    var videoTransportCount: Int
    var videoLayoutCount: Int
    var videoItemKept: Bool
    var baseImageReady: Bool
    var layerImageReady: Bool
    var poorImageReady: Bool
    var generation: UInt64
    var displayMode: Int
    var transparencyThreshold: UInt8
    var eventIndexBuildCount: Int
    var scriptParseCount: Int
    var nativeCodecName: String = ""
    var nativeFormatName: String = ""
    var nativePresentedPTS: Double? = nil
    var nativeResidentBytes: Int = 0
    var nativePeakResidentBytes: Int = 0
    var nativeDecodedFrameCount: Int = 0
    var nativeAudioDecodedPackets: Int = 0
    var nativeAudioDiscardedPackets: Int = 0
    var nativeDroppedStale: Int = 0
    var nativeOriginalWidth: Int = 0
    var nativeOriginalHeight: Int = 0
}

/// uBMplay 键 5 的五态。raw 与说明书顺序一致，窗口传 `Int`。
/// 名字不与 `PreviewUbmBGAMode` 重名。
enum PreviewBGADisplayMode: Int, Equatable, Sendable {
    case off = 0
    case baseOnly = 1
    case layerOnly = 2
    case normal = 3
    case alwaysPoor = 4
}

enum PreviewBGAChrome {
    static let empty = "无 BGA"
    static let videoIdle = "视频未播放"
    static let background = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let clear = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    static func missing(_ name: String) -> String { "缺少 \(name)" }
    static func undefined(_ name: String) -> String { "未定义 \(name)" }
    static func unreadable(_ name: String) -> String { "无法读取 \(name)" }
    static func unplayable(_ name: String) -> String { "无法播放 \(name)" }
}

/// 路径规则跟 `LegacyPreviewAudio.resolveWavURL`：绝对路径原样用，其余拼到谱面目录。
/// 扩展名回退用本地 `LegacyWavList.imageExtensions`。要的文件不在时，按这张表换同名扩展。
/// 不访问网络。
enum PreviewBGAFiles {
    static let mediaExtensions = [
        "bmp", "png", "jpg", "jpeg", "gif", "mpg", "mpeg", "avi",
        "m1v", "m2v", "m4v", "mp4", "webm", "wmv"
    ]
    static let videoExtensions: Set<String> = [
        "mpg", "mpeg", "avi", "m1v", "m2v", "m4v", "mp4", "webm", "wmv", "mov"
    ]

    static func resolve(fileName: String, chartDirectory: URL?) -> URL? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isRemote(trimmed) { return nil }
        if trimmed.lowercased().hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            return existingOrOriginal(url)
        }
        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let url: URL
        if normalized.hasPrefix("/") {
            url = URL(fileURLWithPath: normalized)
        } else if let chartDirectory {
            url = chartDirectory.appendingPathComponent(normalized)
        } else {
            url = URL(fileURLWithPath: normalized)
        }
        guard url.isFileURL else { return nil }
        return existingOrOriginal(url)
    }

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isRemote(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://")
            || lowered.hasPrefix("ftp://")
    }

    private static func existingOrOriginal(_ url: URL) -> URL {
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let current = url.pathExtension.lowercased()
        for ext in mediaExtensions where ext != current {
            let candidate = url.deletingPathExtension().appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return url
    }
}

enum PreviewBGAClock {
    /// 跟 `LegacyPreviewAudio.scheduleHits` 同一套积分：先走 BPM，再把区间里的 STOP 秒数加进去。
    static func seconds(fromBeat: Double, toBeat: Double, timing: PreviewAudioTiming) -> Double {
        guard fromBeat.isFinite, toBeat.isFinite, toBeat >= fromBeat else { return 0 }
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
        var time = 0.0
        var cursor = fromBeat
        for event in changes where event.beat > fromBeat && event.beat < toBeat {
            time += (event.beat - cursor) * 60 / bpm
            cursor = event.beat
            bpm = usableBPM(event.bpm)
        }
        time += (toBeat - cursor) * 60 / bpm
        for stop in stops where fromBeat <= stop.beat && stop.beat < toBeat {
            time += stop.durationSeconds
        }
        return time
    }

    /// 视频在事件拍启动。Here 用起点拍补上已经过去的媒体时间；STOP 期间 elapsed 继续走，视频也不停。
    static func mediaSeconds(
        eventBeat: Double,
        playbackOrigin: Double,
        elapsedSeconds: Double,
        timing: PreviewAudioTiming
    ) -> Double {
        let elapsed = elapsedSeconds.isFinite ? max(0, elapsedSeconds) : 0
        guard eventBeat.isFinite, playbackOrigin.isFinite else { return elapsed }
        if eventBeat <= playbackOrigin {
            return elapsed + seconds(fromBeat: eventBeat, toBeat: playbackOrigin, timing: timing)
        }
        return elapsed - seconds(fromBeat: playbackOrigin, toBeat: eventBeat, timing: timing)
    }

    private static func usableBPM(_ bpm: Double) -> Double {
        bpm > 0 && bpm.isFinite ? bpm : 120
    }
}

final class PreviewBGAEventIndex {
    struct Item: Equatable {
        var beat: Double
        var assetID: String
        var sequence: Int
    }

    private var base: [Item] = []
    private var overlay: [Item] = []
    private var poor: [Item] = []
    private(set) var lastLookupSteps = 0

    init(events: [PreviewBGAEvent]) {
        for (sequence, event) in events.enumerated() where event.beat.isFinite {
            let item = Item(beat: event.beat, assetID: event.assetID, sequence: sequence)
            switch event.layer {
            case .base: base.append(item)
            case .layer: overlay.append(item)
            case .poor: poor.append(item)
            }
        }
        sort(&base)
        sort(&overlay)
        sort(&poor)
    }

    func event(at beat: Double, layer: PreviewBGALayer) -> Item? {
        switch layer {
        case .base: return latest(base, beat: beat)
        case .layer: return latest(overlay, beat: beat)
        case .poor: return latest(poor, beat: beat)
        }
    }

    private func sort(_ items: inout [Item]) {
        items.sort { lhs, rhs in
            if lhs.beat != rhs.beat { return lhs.beat < rhs.beat }
            return lhs.sequence < rhs.sequence
        }
    }

    private func latest(_ items: [Item], beat: Double) -> Item? {
        guard beat.isFinite, !items.isEmpty else {
            lastLookupSteps = 0
            return nil
        }
        var low = 0
        var high = items.count
        var steps = 0
        while low < high {
            steps += 1
            let mid = (low + high) / 2
            if items[mid].beat <= beat {
                low = mid + 1
            } else {
                high = mid
            }
        }
        lastLookupSteps = steps
        let found = low - 1
        guard found >= 0 else { return nil }
        return items[found]
    }
}

enum PreviewBGAVideoSync {
    static let driftThreshold = 0.12
    static let minimumSeekInterval = 0.35
    /// 只认同一请求率上的浮点噪声。键步进是 0.05，不能把 1.95 当成 2。
    static let achievedRateSlop: Float = 0.001

    static func shouldSeek(
        force: Bool,
        expected: Double,
        actual: Double?,
        duration: Double?,
        lastSeekUptime: TimeInterval?,
        now: TimeInterval
    ) -> Bool {
        guard expected.isFinite else { return false }
        if force { return true }
        guard let actual, actual.isFinite else { return false }
        if let duration, duration.isFinite, duration > 0.05,
           expected >= duration - 0.05, actual >= duration - 0.25 {
            return false
        }
        guard abs(expected - actual) >= driftThreshold else { return false }
        if let lastSeekUptime, now - lastSeekUptime < minimumSeekInterval {
            return false
        }
        return true
    }
}

enum PreviewBGAImageCacheKey {
    /// 路径、是否黑键、透明阈值。同一张图换阈值不能命中旧图。
    static func make(path: String, blackKey: Bool, threshold: UInt8) -> String {
        "\(path)|black:\(blackKey ? 1 : 0)|t:\(threshold)"
    }
}

enum PreviewBGAImageLoader {
    nonisolated(unsafe) static var beforeDecode: (@Sendable () -> Void)?

    struct Transfer: @unchecked Sendable {
        var image: CGImage?
    }

    /// `blackKey` 为假时保留原色。为真时只扫一遍：阈值 0 仅 RGB 全 0，255 全部透明。
    nonisolated static func decode(url: URL, blackKey: Bool, threshold: UInt8) -> Transfer {
        beforeDecode?()
        guard url.isFileURL, !isRemote(url) else { return Transfer(image: nil) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return Transfer(image: nil)
        }
        let imageOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, imageOptions) else {
            return Transfer(image: nil)
        }
        guard blackKey else { return Transfer(image: image) }
        return Transfer(image: punchBlack(image, threshold: threshold) ?? image)
    }

    private nonisolated static func isRemote(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "ftp"
    }

    private nonisolated static func punchBlack(_ image: CGImage, threshold: UInt8) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        let byteCount = height * bytesPerRow
        guard byteCount <= 32 * 1024 * 1024 else { return image }
        let pixels = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        defer { pixels.deallocate() }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let raw = pixels.bindMemory(to: UInt8.self, capacity: byteCount)
        var index = 0
        while index + 3 < byteCount {
            if raw[index] <= threshold, raw[index + 1] <= threshold, raw[index + 2] <= threshold {
                raw[index] = 0
                raw[index + 1] = 0
                raw[index + 2] = 0
                raw[index + 3] = 0
            }
            index += 4
        }
        let data = Data(bytes: pixels, count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

@MainActor
final class PreviewBGAImageCache {
    private let cache = NSCache<NSString, PreviewBGAImageBox>()

    init() {
        cache.countLimit = 24
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func store(_ image: CGImage, for key: String) {
        let cost = min(image.width * image.height * 4, Int.max / 4)
        cache.setObject(PreviewBGAImageBox(image), forKey: key as NSString, cost: cost)
    }
}

private final class PreviewBGAImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

struct PreviewBGACropBox: Equatable {
    var x1: Int
    var y1: Int
    var x2: Int
    var y2: Int
    var dx: Int
    var dy: Int
}

struct PreviewBGAPicturePlan: Equatable {
    var crop: PreviewBGACropBox?
    var originX: Int
    var stageWidth: Int
    var stageHeight: Int

    static let identity = PreviewBGAPicturePlan(crop: nil, originX: 0, stageWidth: 256, stageHeight: 256)
}

struct PreviewBGAVideoPlacement: Equatable {
    var sourceX: Double
    var sourceY: Double
    var sourceWidth: Double
    var sourceHeight: Double
    var destX: Double
    var destY: Double
    var destWidth: Double
    var destHeight: Double
    var originalWidth: Int
    var originalHeight: Int
}

struct PreviewBGASlice: Equatable {
    var sourceX: Int
    var sourceY: Int
    var sourceWidth: Int
    var sourceHeight: Int
    var destX: Int
    var destY: Int
}

enum PreviewBGAGeometry {
    static let nominalColumn = 256
    static let maxAbsCoordinate = 1_000_000

    static func directImage(
        originX: Int,
        imageWidth: Int,
        imageHeight: Int,
        stageWidth: Int,
        stageHeight: Int
    ) -> PreviewBGASlice? {
        guard imageWidth > 0, imageHeight > 0,
              imageWidth <= maxAbsCoordinate, imageHeight <= maxAbsCoordinate,
              stageWidth > 0, stageHeight > 0 else { return nil }
        let shownHeight = imageHeight < nominalColumn ? imageHeight : nominalColumn
        guard let destX = adding(originX, nominalColumn / 2 - imageWidth / 2) else { return nil }
        return clip(
            sourceX: 0,
            sourceY: 0,
            sourceWidth: imageWidth,
            sourceHeight: shownHeight,
            destX: destX,
            destY: 0,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            stageWidth: stageWidth,
            stageHeight: stageHeight
        )
    }

    static func crop(
        originX: Int,
        box: PreviewBGACropBox,
        imageWidth: Int,
        imageHeight: Int,
        stageWidth: Int,
        stageHeight: Int
    ) -> PreviewBGASlice? {
        guard imageWidth > 0, imageHeight > 0, stageWidth > 0, stageHeight > 0 else { return nil }
        guard within(box.x1), within(box.y1), within(box.x2), within(box.y2),
              within(box.dx), within(box.dy), within(originX) else { return nil }
        var left = box.x1
        var right = box.x2
        var top = box.y1
        var bottom = box.y2
        if left > right { swap(&left, &right) }
        if top > bottom { swap(&top, &bottom) }
        guard let width = subtracting(right, left), let height = subtracting(bottom, top),
              width > 0, height > 0 else { return nil }
        guard let destX = adding(originX, box.dx) else { return nil }
        return clip(
            sourceX: left,
            sourceY: top,
            sourceWidth: width,
            sourceHeight: height,
            destX: destX,
            destY: box.dy,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            stageWidth: stageWidth,
            stageHeight: stageHeight
        )
    }

    /// 视频先收到显示尺寸，再把显示坐标换回原像素。目标顶对齐，不加 +0x48 的垂直居中。
    static func video(
        originX: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        crop: PreviewBGACropBox?,
        stageWidth: Int,
        stageHeight: Int
    ) -> PreviewBGAVideoPlacement? {
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth <= 8192, pixelHeight <= 8192,
              stageWidth > 0, stageHeight > 0 else { return nil }
        let longEdge = max(pixelWidth, pixelHeight)
        let scale = Float(longEdge) / 256
        guard scale.isFinite, scale > 0,
              let displayWidth = bankRound(Float(pixelWidth) / scale),
              let displayHeight = bankRound(Float(pixelHeight) / scale),
              displayWidth > 0, displayHeight > 0 else { return nil }
        let shownLeft: Int
        let shownTop: Int
        let shownRight: Int
        let shownBottom: Int
        let destX: Int
        let destY: Int
        if let crop {
            guard within(crop.x1), within(crop.y1), within(crop.x2), within(crop.y2),
                  within(crop.dx), within(crop.dy), within(originX) else { return nil }
            var left = crop.x1
            var right = crop.x2
            var top = crop.y1
            var bottom = crop.y2
            if left > right { swap(&left, &right) }
            if top > bottom { swap(&top, &bottom) }
            guard let spanWidth = subtracting(right, left), let spanHeight = subtracting(bottom, top),
                  spanWidth > 0, spanHeight > 0,
                  let placedX = adding(originX, crop.dx) else { return nil }
            shownLeft = left
            shownTop = top
            shownRight = right
            shownBottom = bottom
            destX = placedX
            destY = crop.dy
        } else {
            guard within(originX), let placedX = adding(originX, nominalColumn / 2 - displayWidth / 2) else { return nil }
            shownLeft = 0
            shownTop = 0
            shownRight = displayWidth
            shownBottom = min(displayHeight, nominalColumn)
            destX = placedX
            destY = 0
        }
        guard shownRight > shownLeft, shownBottom > shownTop else { return nil }
        guard let originalLeft = bankRound(Float(shownLeft) * scale),
              let originalRight = bankRound(Float(shownRight) * scale),
              let originalTop = bankRound(Float(shownTop) * scale),
              let originalBottom = bankRound(Float(shownBottom) * scale),
              originalRight > originalLeft, originalBottom > originalTop else { return nil }
        return fitVideo(
            sourceLeft: originalLeft,
            sourceTop: originalTop,
            sourceRight: originalRight,
            sourceBottom: originalBottom,
            destX: Double(destX),
            destY: Double(destY),
            destWidth: Double(shownRight - shownLeft),
            destHeight: Double(shownBottom - shownTop),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            stageWidth: stageWidth,
            stageHeight: stageHeight
        )
    }

    /// `__vbaFpI4` 的银行家舍入。半值靠偶数。运行库本体没有单步。
    static func bankRound(_ value: Float) -> Int? {
        guard value.isFinite, abs(value) <= Float(maxAbsCoordinate) else { return nil }
        let rounded = Double(value).rounded(.toNearestOrEven)
        guard rounded.isFinite, abs(rounded) <= Double(maxAbsCoordinate) else { return nil }
        return Int(rounded)
    }

    private static func fitVideo(
        sourceLeft: Int,
        sourceTop: Int,
        sourceRight: Int,
        sourceBottom: Int,
        destX: Double,
        destY: Double,
        destWidth: Double,
        destHeight: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        stageWidth: Int,
        stageHeight: Int
    ) -> PreviewBGAVideoPlacement? {
        let spanWidth = sourceRight - sourceLeft
        let spanHeight = sourceBottom - sourceTop
        guard spanWidth > 0, spanHeight > 0, destWidth > 0, destHeight > 0,
              destWidth.isFinite, destHeight.isFinite, destX.isFinite, destY.isFinite else { return nil }
        let clippedLeft = min(max(sourceLeft, 0), pixelWidth)
        let clippedRight = min(max(sourceRight, 0), pixelWidth)
        let clippedTop = min(max(sourceTop, 0), pixelHeight)
        let clippedBottom = min(max(sourceBottom, 0), pixelHeight)
        guard clippedRight > clippedLeft, clippedBottom > clippedTop else { return nil }
        let leftFraction = Double(clippedLeft - sourceLeft) / Double(spanWidth)
        let rightFraction = Double(sourceRight - clippedRight) / Double(spanWidth)
        let topFraction = Double(clippedTop - sourceTop) / Double(spanHeight)
        let bottomFraction = Double(sourceBottom - clippedBottom) / Double(spanHeight)
        guard leftFraction >= 0, rightFraction >= 0, topFraction >= 0, bottomFraction >= 0,
              leftFraction + rightFraction < 1, topFraction + bottomFraction < 1 else { return nil }
        var x = destX + destWidth * leftFraction
        var y = destY + destHeight * topFraction
        var width = destWidth * (1 - leftFraction - rightFraction)
        var height = destHeight * (1 - topFraction - bottomFraction)
        var sourceX = Double(clippedLeft)
        var sourceY = Double(clippedTop)
        var sourceWidth = Double(clippedRight - clippedLeft)
        var sourceHeight = Double(clippedBottom - clippedTop)
        if x < 0 {
            let fraction = min(1, (-x) / width)
            sourceX += sourceWidth * fraction
            sourceWidth *= 1 - fraction
            width *= 1 - fraction
            x = 0
        }
        if y < 0 {
            let fraction = min(1, (-y) / height)
            sourceY += sourceHeight * fraction
            sourceHeight *= 1 - fraction
            height *= 1 - fraction
            y = 0
        }
        let stageRight = Double(stageWidth)
        let stageBottom = Double(stageHeight)
        if x >= stageRight || y >= stageBottom { return nil }
        if x + width > stageRight {
            let fraction = (x + width - stageRight) / width
            sourceWidth *= 1 - fraction
            width = stageRight - x
        }
        if y + height > stageBottom {
            let fraction = (y + height - stageBottom) / height
            sourceHeight *= 1 - fraction
            height = stageBottom - y
        }
        guard width > 0, height > 0, sourceWidth > 0, sourceHeight > 0,
              width.isFinite, height.isFinite, sourceWidth.isFinite, sourceHeight.isFinite else { return nil }
        return PreviewBGAVideoPlacement(
            sourceX: sourceX,
            sourceY: sourceY,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            destX: x,
            destY: y,
            destWidth: width,
            destHeight: height,
            originalWidth: pixelWidth,
            originalHeight: pixelHeight
        )
    }

    static func videoHostFrame(
        _ placement: PreviewBGAVideoPlacement,
        scale: CGFloat,
        stageHeight: CGFloat
    ) -> CGRect {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        return CGRect(
            x: placement.destX * safeScale,
            y: (stageHeight - placement.destY - placement.destHeight) * safeScale,
            width: placement.destWidth * safeScale,
            height: placement.destHeight * safeScale
        )
    }

    /// 父裁切框里的整段视频。源区域靠位移和缩放对准，不用 contentsRect。
    static func videoPlayerFrame(hostSize: CGSize, placement: PreviewBGAVideoPlacement) -> CGRect {
        guard placement.sourceWidth > 0, placement.sourceHeight > 0,
              placement.originalWidth > 0, placement.originalHeight > 0,
              hostSize.width > 0, hostSize.height > 0 else { return .zero }
        let playerWidth = hostSize.width * CGFloat(placement.originalWidth) / CGFloat(placement.sourceWidth)
        let playerHeight = hostSize.height * CGFloat(placement.originalHeight) / CGFloat(placement.sourceHeight)
        let playerX = -hostSize.width * CGFloat(placement.sourceX) / CGFloat(placement.sourceWidth)
        let playerY = hostSize.height * CGFloat(placement.sourceHeight + placement.sourceY - Double(placement.originalHeight)) / CGFloat(placement.sourceHeight)
        return CGRect(x: playerX, y: playerY, width: playerWidth, height: playerHeight)
    }

    static func contentsRect(slice: PreviewBGASlice, imageWidth: Int, imageHeight: Int) -> CGRect {
        guard imageWidth > 0, imageHeight > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)
        return CGRect(
            x: CGFloat(slice.sourceX) / width,
            y: CGFloat(imageHeight - slice.sourceY - slice.sourceHeight) / height,
            width: CGFloat(slice.sourceWidth) / width,
            height: CGFloat(slice.sourceHeight) / height
        )
    }

    static func layerFrame(slice: PreviewBGASlice, scale: CGFloat, stageHeight: CGFloat) -> CGRect {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        return CGRect(
            x: CGFloat(slice.destX) * safeScale,
            y: (stageHeight - CGFloat(slice.destY) - CGFloat(slice.sourceHeight)) * safeScale,
            width: CGFloat(slice.sourceWidth) * safeScale,
            height: CGFloat(slice.sourceHeight) * safeScale
        )
    }

    private static func clip(
        sourceX: Int,
        sourceY: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        destX: Int,
        destY: Int,
        imageWidth: Int,
        imageHeight: Int,
        stageWidth: Int,
        stageHeight: Int
    ) -> PreviewBGASlice? {
        var sx = sourceX
        var sy = sourceY
        var sw = sourceWidth
        var sh = sourceHeight
        var dx = destX
        var dy = destY
        if sx < 0 {
            guard let nextWidth = adding(sw, sx) else { return nil }
            sw = nextWidth
            dx -= sx
            sx = 0
        }
        if sy < 0 {
            guard let nextHeight = adding(sh, sy) else { return nil }
            sh = nextHeight
            dy -= sy
            sy = 0
        }
        if let end = adding(sx, sw), end > imageWidth {
            sw = imageWidth - sx
        }
        if let end = adding(sy, sh), end > imageHeight {
            sh = imageHeight - sy
        }
        guard sw > 0, sh > 0, sx >= 0, sy >= 0 else { return nil }
        if dx < 0 {
            guard let nextWidth = adding(sw, dx) else { return nil }
            sw = nextWidth
            sx -= dx
            dx = 0
        }
        if dy < 0 {
            guard let nextHeight = adding(sh, dy) else { return nil }
            sh = nextHeight
            sy -= dy
            dy = 0
        }
        if let end = adding(dx, sw), end > stageWidth {
            sw = stageWidth - dx
        }
        if let end = adding(dy, sh), end > stageHeight {
            sh = stageHeight - dy
        }
        guard sw > 0, sh > 0, sx >= 0, sy >= 0 else { return nil }
        guard let sourceRight = adding(sx, sw), let sourceBottom = adding(sy, sh),
              sourceRight <= imageWidth, sourceBottom <= imageHeight else { return nil }
        return PreviewBGASlice(
            sourceX: sx,
            sourceY: sy,
            sourceWidth: sw,
            sourceHeight: sh,
            destX: dx,
            destY: dy
        )
    }

    private static func within(_ value: Int) -> Bool {
        abs(value) <= maxAbsCoordinate
    }

    private static func adding(_ lhs: Int, _ rhs: Int) -> Int? {
        let sum = lhs.addingReportingOverflow(rhs)
        guard !sum.overflow else { return nil }
        return sum.partialValue
    }

    private static func subtracting(_ lhs: Int, _ rhs: Int) -> Int? {
        let difference = lhs.subtractingReportingOverflow(rhs)
        guard !difference.overflow else { return nil }
        return difference.partialValue
    }
}

struct PreviewBGAStageMetrics {
    var scale: CGFloat
    var contentFrame: CGRect
    var stageWidth: CGFloat
    var stageHeight: CGFloat

    init(viewSize: CGSize, canvas: CGSize) {
        let canvasWidth = canvas.width
        let canvasHeight = canvas.height
        guard canvasWidth > 0, canvasHeight > 0, canvasWidth.isFinite, canvasHeight.isFinite,
              viewSize.width > 0, viewSize.height > 0, viewSize.width.isFinite, viewSize.height.isFinite else {
            scale = 1
            contentFrame = .zero
            stageWidth = 256
            stageHeight = 256
            return
        }
        scale = min(viewSize.width / canvasWidth, viewSize.height / canvasHeight)
        let contentWidth = canvasWidth * scale
        let contentHeight = canvasHeight * scale
        contentFrame = CGRect(
            x: (viewSize.width - contentWidth) / 2,
            y: (viewSize.height - contentHeight) / 2,
            width: contentWidth,
            height: contentHeight
        )
        stageWidth = canvasWidth
        stageHeight = canvasHeight
    }

    func columnFrame(originX: Double) -> CGRect {
        guard originX.isFinite, stageWidth > 0, stageHeight > 0, scale > 0 else { return .zero }
        let start = max(0, min(stageWidth, originX))
        let end = max(0, min(stageWidth, originX + CGFloat(PreviewBGAGeometry.nominalColumn)))
        guard end > start else { return .zero }
        return CGRect(x: start * scale, y: 0, width: (end - start) * scale, height: stageHeight * scale)
    }
}

enum PreviewBGAScript {
    struct Crop {
        var source: Int
        var box: PreviewBGACropBox
    }

    struct Map {
        var bmps: [Int: String] = [:]
        var crops: [Int: Crop] = [:]
        var hasHeaders: Bool { !bmps.isEmpty || !crops.isEmpty }
    }

    static func token(_ index: Int) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let clamped = min(max(index, 0), 1295)
        return String([alphabet[clamped / 36], alphabet[clamped % 36]])
    }

    static func index(from text: String) -> Int? {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty, upper.count <= 4 else { return nil }
        var value = 0
        for scalar in upper.unicodeScalars {
            let digit: Int
            if scalar.value >= 48 && scalar.value <= 57 {
                digit = Int(scalar.value - 48)
            } else if scalar.value >= 65 && scalar.value <= 90 {
                digit = Int(scalar.value - 65) + 10
            } else {
                return nil
            }
            value = value * 36 + digit
        }
        return value
    }

    /// 与 `PreviewBmsSource.decodePreviewText` 同一顺序：去 BOM，先 UTF-8，再 Shift-JIS。失败就不造文本。
    static func parse(_ data: Data) -> Map {
        guard let text = decode(data) else { return Map() }
        var map = Map()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.first == "#" else { continue }
            let body = line.dropFirst()
            guard let space = body.firstIndex(of: " ") else { continue }
            let command = String(body[..<space])
            let rest = body[body.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard command.count >= 3 else { continue }
            let name = command.dropLast(2).uppercased()
            let slotText = String(command.suffix(2))
            guard let slot = index(from: slotText), slot < 1296 else { continue }
            if name == "BMP" {
                let file = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !file.isEmpty {
                    map.bmps[slot] = file
                }
            } else if name == "BGA" {
                map.crops[slot] = crop(from: rest)
            }
        }
        return map
    }

    private static func decode(_ data: Data) -> String? {
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        if let text = String(data: payload, encoding: .shiftJIS) {
            return text
        }
        return nil
    }

    private static func crop(from rest: String) -> Crop {
        var words: [String] = []
        var current = ""
        for character in rest {
            if character == " " {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
            if words.count == 7 { break }
        }
        if !current.isEmpty, words.count < 7 {
            words.append(current)
        }
        while words.count < 7 {
            words.append("")
        }
        let sourceWord = words[0]
        let source: Int
        if sourceWord.hasPrefix("-") {
            source = signed(sourceWord)
        } else if let parsed = index(from: sourceWord) {
            source = parsed > 1295 ? 0 : parsed
        } else {
            source = 0
        }
        var x1 = signed(words[1])
        var y1 = signed(words[2])
        var x2 = signed(words[3])
        var y2 = signed(words[4])
        let dx = signed(words[5])
        let dy = signed(words[6])
        if x1 > x2 { swap(&x1, &x2) }
        if y1 > y2 { swap(&y1, &y2) }
        return Crop(
            source: source,
            box: PreviewBGACropBox(x1: x1, y1: y1, x2: x2, y2: y2, dx: dx, dy: dy)
        )
    }

    private static func signed(_ word: String) -> Int {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        var sign = 1
        var digits = trimmed[...]
        if digits.first == "-" {
            sign = -1
            digits = digits.dropFirst()
        } else if digits.first == "+" {
            digits = digits.dropFirst()
        }
        var value = 0
        var sawDigit = false
        for character in digits {
            guard let digit = character.wholeNumberValue, digit < 10 else { break }
            sawDigit = true
            if value > PreviewBGAGeometry.maxAbsCoordinate / 10 {
                return sign * (PreviewBGAGeometry.maxAbsCoordinate + 1)
            }
            value = value * 10 + digit
        }
        guard sawDigit else { return 0 }
        return sign * value
    }
}

@MainActor
private final class PreviewBGAChannel {
    let blackKey: Bool
    let imageLayer = CALayer()
    let playerLayer = AVPlayerLayer()
    let nativeLayer = CALayer()
    let videoHost = CALayer()
    var onChange: (() -> Void)?
    private(set) var presentedItem: PreviewBGAEventIndex.Item?
    private(set) var player: AVPlayer?
    private(set) var assetID: String?
    private(set) var kind: PreviewBGAChannelKind = .none
    private(set) var failure: String?
    private(set) var imageReady = false
    private(set) var seekCount = 0
    private(set) var lastSeekSeconds: Double?
    private(set) var expectedMediaSeconds: Double?
    private(set) var audioDisabled = false
    private(set) var audioTrackCount = 0
    private(set) var pathResolveCount = 0
    private(set) var timingEvaluationCount = 0
    private(set) var videoOpenCount = 0

    private var boundKey: PreviewBGAEventKey?
    private var boundURL: URL?
    private var mediaOffset = 0.0
    private var fileName = ""
    private var request = 0
    private var seenGeneration: UInt64 = 0
    private var appliedSeekRequest = -1
    private var lastSeekUptime: TimeInterval?
    private var silenceRequest = -1
    private var wantsPlayback = false
    private var armed = false
    private var threshold: UInt8 = 0
    private var resolutionCache: [String: PreviewBGAResolved] = [:]
    private var preferredFile: String?
    private var plan = PreviewBGAPicturePlan.identity
    private var stageScale: CGFloat = 1
    private var videoPixelSize: CGSize?
    private var shownImage: CGImage?
    private var requestedRate: Double = 1
    private var lastTransportCommand: Float = -1
    private var seekInFlight = false
    private(set) var transportCommandCount = 0
    private(set) var videoLayoutCount = 0
    private var appliedVideoKey: String?
    private var nativeClock: PreviewVideoClock?
    private var nativeBackend = false
    private var nativeImage: CGImage?
    private var nativePTS: Double?
    private var nativeErrorText: String?

    var nativeAttached: Bool { nativeClock?.attached == true }
    var nativeSilenced: Bool { nativeAttached }
    var nativeItemKept: Bool { nativeAttached }
    var nativePresentedSeconds: Double? { nativePTS }
    var nativeOutputRate: Float? { nativeAttached ? nativeClock?.outputRate : nil }
    var nativeError: String? { nativeErrorText }

    func nativeSnapshot() -> PreviewVideoStats {
        nativeClock?.stats ?? .empty
    }

    func nativePicture() -> PreviewNativeVideoPicture? {
        guard let nativeImage else { return nil }
        return PreviewNativeVideoPicture(
            image: nativeImage,
            pts: nativePTS ?? 0,
            hostFrame: videoHost.frame,
            imageFrame: nativeLayer.frame,
            originalWidth: Int((videoPixelSize?.width ?? 0).rounded(.towardZero)),
            originalHeight: Int((videoPixelSize?.height ?? 0).rounded(.towardZero))
        )
    }

    var enabledAudioTrackCount: Int {
        guard let tracks = player?.currentItem?.tracks else { return 0 }
        return tracks.reduce(0) { count, track in
            guard track.assetTrack?.mediaType == .audio, track.isEnabled else { return count }
            return count + 1
        }
    }

    init(blackKey: Bool) {
        self.blackKey = blackKey
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.contentsScale = 1
        imageLayer.isOpaque = false
        imageLayer.backgroundColor = nil
        playerLayer.videoGravity = .resize
        playerLayer.contentsScale = 1
        playerLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        playerLayer.backgroundColor = nil
        playerLayer.isHidden = true
        nativeLayer.name = "ibms.native.video"
        nativeLayer.contentsGravity = .resize
        nativeLayer.contentsScale = 1
        nativeLayer.backgroundColor = nil
        nativeLayer.isHidden = true
        videoHost.masksToBounds = true
        videoHost.contentsScale = 1
        videoHost.backgroundColor = nil
        videoHost.isHidden = true
        imageLayer.isHidden = true
    }

    func install(on root: CALayer?) {
        guard let root else { return }
        if imageLayer.superlayer == nil {
            root.addSublayer(imageLayer)
            videoHost.addSublayer(playerLayer)
            videoHost.addSublayer(nativeLayer)
            root.addSublayer(videoHost)
        }
    }

    func updatePlan(_ plan: PreviewBGAPicturePlan, scale: CGFloat) {
        self.plan = plan
        stageScale = scale.isFinite && scale > 0 ? scale : 1
        imageLayer.zPosition = blackKey ? 1 : 0
        videoHost.zPosition = blackKey ? 1 : 0
        layoutPicture()
    }

    func reset() {
        armed = false
        request &+= 1
        boundKey = nil
        boundURL = nil
        mediaOffset = 0
        assetID = nil
        fileName = ""
        presentedItem = nil
        kind = .none
        failure = nil
        expectedMediaSeconds = nil
        preferredFile = nil
        videoPixelSize = nil
        shownImage = nil
        resolutionCache.removeAll()
        releasePlayer()
        clearImage()
    }

    /// 播放中改倍率只发一次传输命令。暂停时播放器保持 0，请求值留下次恢复。
    func adoptRate(_ rate: Double) {
        guard rate.isFinite, rate >= 0.25, rate <= 4 else { return }
        guard requestedRate != rate else { return }
        requestedRate = rate
        if nativeClock != nil {
            pushNative(expected: expectedMediaSeconds ?? 0)
            return
        }
        guard let player else { return }
        if wantsPlayback {
            lastTransportCommand = -1
        }
        applyTransport(player)
    }

    /// 关掉这一层：作废进行中的解码，暂停并拆掉视频，清掉画面。路径缓存留着，切回来不用再 stat。
    private func disarm() {
        wantsPlayback = false
        let idle = !armed && player == nil && !imageReady && boundKey == nil && kind == .none && failure == nil
        guard !idle else { return }
        armed = false
        request &+= 1
        boundKey = nil
        boundURL = nil
        mediaOffset = 0
        assetID = nil
        fileName = ""
        presentedItem = nil
        kind = .none
        failure = nil
        expectedMediaSeconds = nil
        videoPixelSize = nil
        releasePlayer()
        clearImage()
    }

    /// 暂停并留住当前帧。停止播放不等于拆掉播放器。
    func holdFrame() {
        wantsPlayback = false
        if nativeClock != nil {
            pushNative(expected: expectedMediaSeconds ?? 0)
            return
        }
        guard let player else { return }
        applyTransport(player)
    }

    func releasePlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer.player = nil
        player = nil
        nativeClock?.close()
        nativeClock = nil
        nativeBackend = false
        nativeImage = nil
        nativePTS = nil
        nativeErrorText = nil
        nativeLayer.contents = nil
        nativeLayer.isHidden = true
        playerLayer.isHidden = true
        videoHost.isHidden = true
        appliedVideoKey = nil
        appliedSeekRequest = -1
        audioDisabled = false
        audioTrackCount = 0
        silenceRequest = -1
        seekInFlight = false
        lastTransportCommand = -1
    }

    func sync(
        event: PreviewBGAEventIndex.Item?,
        assets: [String: String],
        chartDirectory: URL?,
        playbackOrigin: Double,
        elapsed: Double,
        timing: PreviewAudioTiming,
        isPlaying: Bool,
        generation: UInt64,
        threshold: UInt8,
        enabled: Bool,
        cache: PreviewBGAImageCache,
        preferredFile: String?,
        plan: PreviewBGAPicturePlan,
        scale: CGFloat,
        playbackRate: Double,
        scheduleDecode: () -> Void
    ) {
        seenGeneration = generation
        self.threshold = threshold
        self.preferredFile = preferredFile
        self.plan = plan
        stageScale = scale.isFinite && scale > 0 ? scale : 1
        if playbackRate.isFinite, playbackRate >= 0.25, playbackRate <= 4 {
            requestedRate = playbackRate
        }
        presentedItem = enabled ? event : nil
        wantsPlayback = enabled && isPlaying
        if !enabled {
            disarm()
            return
        }
        let key = PreviewBGAEventKey(event: event, generation: generation, threshold: threshold)
        if key == boundKey {
            advanceSameEvent(elapsed: elapsed, isPlaying: isPlaying)
            layoutPicture()
            return
        }
        bind(
            event: event,
            key: key,
            assets: assets,
            chartDirectory: chartDirectory,
            playbackOrigin: playbackOrigin,
            elapsed: elapsed,
            timing: timing,
            isPlaying: isPlaying,
            generation: generation,
            cache: cache,
            scheduleDecode: scheduleDecode
        )
    }

    private func advanceSameEvent(elapsed: Double, isPlaying: Bool) {
        guard kind == .video else { return }
        let media = max(0, elapsed + mediaOffset)
        expectedMediaSeconds = media
        if isPlaying {
            if player == nil, nativeClock == nil, let url = boundURL {
                openVideo(url: url, name: fileName)
            }
            updateVideo(expected: media)
        } else {
            holdFrame()
        }
    }

    private func bind(
        event: PreviewBGAEventIndex.Item?,
        key: PreviewBGAEventKey,
        assets: [String: String],
        chartDirectory: URL?,
        playbackOrigin: Double,
        elapsed: Double,
        timing: PreviewAudioTiming,
        isPlaying: Bool,
        generation: UInt64,
        cache: PreviewBGAImageCache,
        scheduleDecode: () -> Void
    ) {
        armed = true
        request &+= 1
        boundKey = key
        let resolved = resolve(
            event: event,
            assets: assets,
            chartDirectory: chartDirectory,
            generation: generation
        )
        boundURL = resolved.url
        assetID = resolved.assetID
        fileName = resolved.fileName
        kind = resolved.kind
        failure = resolved.failure
        releasePlayer()
        clearImage()
        guard resolved.kind == .video else {
            mediaOffset = 0
            expectedMediaSeconds = nil
            if resolved.kind == .image, let url = resolved.url {
                showImage(
                    url: url,
                    generation: generation,
                    cache: cache,
                    scheduleDecode: scheduleDecode
                )
            }
            return
        }
        let eventBeat = event?.beat ?? playbackOrigin
        mediaOffset = PreviewBGAClock.mediaSeconds(
            eventBeat: eventBeat,
            playbackOrigin: playbackOrigin,
            elapsedSeconds: 0,
            timing: timing
        )
        timingEvaluationCount += 1
        let media = max(0, elapsed + mediaOffset)
        expectedMediaSeconds = media
        if isPlaying, let url = resolved.url {
            openVideo(url: url, name: fileName)
            updateVideo(expected: media)
        }
    }

    private func resolve(
        event: PreviewBGAEventIndex.Item?,
        assets: [String: String],
        chartDirectory: URL?,
        generation: UInt64
    ) -> PreviewBGAResolved {
        guard let event else { return PreviewBGAResolved(identity: nil, assetID: nil, fileName: "", url: nil, kind: .none, failure: nil) }
        let id = event.assetID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(generation)|\(event.sequence)|\(event.beat)|\(id)|\(preferredFile ?? "*")"
        if let cached = resolutionCache[cacheKey] {
            return cached
        }
        let result: PreviewBGAResolved
        let chosenFile: String?
        if let preferredFile {
            chosenFile = preferredFile.isEmpty ? nil : preferredFile
        } else if let name = assets[id], !name.isEmpty {
            chosenFile = name
        } else {
            chosenFile = nil
        }
        if id.isEmpty {
            result = PreviewBGAResolved(identity: "clear:\(event.beat)", assetID: nil, fileName: "", url: nil, kind: .none, failure: nil)
        } else if chosenFile == nil, preferredFile == nil, assets[id] == nil {
            result = PreviewBGAResolved(
                identity: "missing-id:\(event.beat):\(id)",
                assetID: id,
                fileName: id,
                url: nil,
                kind: .missing,
                failure: PreviewBGAChrome.undefined(id)
            )
        } else if chosenFile == nil, preferredFile == nil {
            result = PreviewBGAResolved(identity: "clear:\(event.beat):\(id)", assetID: nil, fileName: "", url: nil, kind: .none, failure: nil)
        } else if chosenFile == nil {
            result = PreviewBGAResolved(
                identity: "missing-source:\(event.beat):\(id)",
                assetID: id,
                fileName: id,
                url: nil,
                kind: .missing,
                failure: PreviewBGAChrome.undefined(id)
            )
        } else {
            let fileName = chosenFile ?? ""
            pathResolveCount += 1
            if let url = PreviewBGAFiles.resolve(fileName: fileName, chartDirectory: chartDirectory) {
                let label = url.lastPathComponent
                if FileManager.default.fileExists(atPath: url.path) {
                    let kind: PreviewBGAChannelKind = PreviewBGAFiles.isVideo(url) ? .video : .image
                    result = PreviewBGAResolved(
                        identity: "\(kind):\(event.beat):\(url.path)",
                        assetID: id,
                        fileName: label,
                        url: url,
                        kind: kind,
                        failure: nil
                    )
                } else {
                    result = PreviewBGAResolved(
                        identity: "absent:\(event.beat):\(url.path)",
                        assetID: id,
                        fileName: label,
                        url: url,
                        kind: .missing,
                        failure: PreviewBGAChrome.missing(label)
                    )
                }
            } else {
                let label = URL(fileURLWithPath: fileName).lastPathComponent
                result = PreviewBGAResolved(
                    identity: "remote:\(event.beat):\(fileName)",
                    assetID: id,
                    fileName: label,
                    url: nil,
                    kind: .missing,
                    failure: PreviewBGAChrome.missing(label)
                )
            }
        }
        resolutionCache[cacheKey] = result
        return result
    }

    private func showImage(
        url: URL,
        generation: UInt64,
        cache: PreviewBGAImageCache,
        scheduleDecode: () -> Void
    ) {
        let key = PreviewBGAImageCacheKey.make(path: url.path, blackKey: blackKey, threshold: threshold)
        if let image = cache.image(for: key) {
            display(image)
            return
        }
        let token = request
        let capturedGeneration = generation
        let capturedBlackKey = blackKey
        let capturedThreshold = threshold
        scheduleDecode()
        Task { [weak self] in
            let decoded = await Task.detached {
                PreviewBGAImageLoader.decode(
                    url: url,
                    blackKey: capturedBlackKey,
                    threshold: capturedThreshold
                )
            }.value
            self?.applyDecoded(decoded, token: token, generation: capturedGeneration, key: key, cache: cache)
        }
    }

    private func applyDecoded(
        _ decoded: PreviewBGAImageLoader.Transfer,
        token: Int,
        generation: UInt64,
        key: String,
        cache: PreviewBGAImageCache
    ) {
        guard let image = decoded.image else {
            guard request == token, seenGeneration == generation else { return }
            failure = PreviewBGAChrome.unreadable(fileName)
            clearImage()
            onChange?()
            return
        }
        cache.store(image, for: key)
        guard request == token, seenGeneration == generation else { return }
        display(image)
    }

    private func display(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        shownImage = image
        imageReady = true
        failure = nil
        layoutPicture()
        CATransaction.commit()
        onChange?()
    }

    private func layoutPicture() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if kind == .image, let image = shownImage {
            let slice = plan.crop == nil
                ? PreviewBGAGeometry.directImage(
                    originX: plan.originX,
                    imageWidth: image.width,
                    imageHeight: image.height,
                    stageWidth: plan.stageWidth,
                    stageHeight: plan.stageHeight
                )
                : plan.crop.flatMap {
                    PreviewBGAGeometry.crop(
                        originX: plan.originX,
                        box: $0,
                        imageWidth: image.width,
                        imageHeight: image.height,
                        stageWidth: plan.stageWidth,
                        stageHeight: plan.stageHeight
                    )
                }
            guard let slice else {
                imageLayer.isHidden = true
                hideVideoHost()
                return
            }
            imageLayer.contentsScale = 1
        imageLayer.contentsRect = PreviewBGAGeometry.contentsRect(
                slice: slice,
                imageWidth: image.width,
                imageHeight: image.height
            )
            imageLayer.frame = PreviewBGAGeometry.layerFrame(
                slice: slice,
                scale: stageScale,
                stageHeight: CGFloat(plan.stageHeight)
            )
            imageLayer.isHidden = false
            hideVideoHost()
            return
        }
        guard kind == .video, let size = videoPixelSize, size.width > 1, size.height > 1 else {
            if kind == .video {
                hideVideoHost()
            }
            return
        }
        guard let placement = PreviewBGAGeometry.video(
            originX: plan.originX,
            pixelWidth: Int(size.width.rounded(.towardZero)),
            pixelHeight: Int(size.height.rounded(.towardZero)),
            crop: plan.crop,
            stageWidth: plan.stageWidth,
            stageHeight: plan.stageHeight
        ) else {
            hideVideoHost()
            return
        }
        applyVideoPlacement(placement)
    }

    private func hideVideoHost() {
        playerLayer.isHidden = true
        nativeLayer.isHidden = true
        videoHost.isHidden = true
    }

    private func applyVideoPlacement(_ placement: PreviewBGAVideoPlacement) {
        let key = String(
            format: "%.4f,%.4f,%.4f,%.4f|%.4f,%.4f,%.4f,%.4f|%d,%d|%.4f|%d",
            placement.sourceX, placement.sourceY, placement.sourceWidth, placement.sourceHeight,
            placement.destX, placement.destY, placement.destWidth, placement.destHeight,
            placement.originalWidth, placement.originalHeight, stageScale, plan.stageHeight
        )
        videoHost.isHidden = false
        if nativeBackend {
            playerLayer.isHidden = true
            nativeLayer.isHidden = false
        } else {
            nativeLayer.isHidden = true
            playerLayer.isHidden = false
            playerLayer.transform = CATransform3DIdentity
            playerLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        guard key != appliedVideoKey else { return }
        appliedVideoKey = key
        videoLayoutCount += 1
        let hostFrame = PreviewBGAGeometry.videoHostFrame(
            placement,
            scale: stageScale,
            stageHeight: CGFloat(plan.stageHeight)
        )
        videoHost.contentsScale = 1
        videoHost.masksToBounds = true
        videoHost.frame = hostFrame
        let fitted = PreviewBGAGeometry.videoPlayerFrame(hostSize: hostFrame.size, placement: placement)
        if nativeBackend {
            nativeLayer.contentsScale = 1
            nativeLayer.contentsGravity = .resize
            nativeLayer.frame = fitted
        } else {
            playerLayer.contentsScale = 1
            playerLayer.videoGravity = .resize
            playerLayer.frame = fitted
        }
    }

    private func clearImage() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        shownImage = nil
        imageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        imageLayer.isHidden = true
        CATransaction.commit()
        imageReady = false
    }

    private func openVideo(url: URL, name: String) {
        guard url.isFileURL else {
            failure = PreviewBGAChrome.missing(name)
            return
        }
        if PreviewVideoClock.usesNativeFile(url) {
            openNativeVideo(url: url, name: name)
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        videoOpenCount += 1
        playerLayer.player = player
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        imageLayer.isHidden = true
        imageReady = false
        playerLayer.isHidden = true
        CATransaction.commit()
        silence(item: item, player: player)
        layoutPicture()
    }

    private func silence(item: AVPlayerItem, player: AVPlayer) {
        player.isMuted = true
        player.volume = 0
        let token = request
        guard silenceRequest != token else { return }
        silenceRequest = token
        Task { @MainActor [weak self, weak player] in
            let tracks = (try? await item.asset.loadTracks(withMediaType: .audio)) ?? []
            guard let self, let player, self.player === player, self.request == token else { return }
            self.audioTrackCount = tracks.count
            guard !tracks.isEmpty else { return }
            let mix = AVMutableAudioMix()
            mix.inputParameters = tracks.map { track in
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.setVolume(0, at: .zero)
                return parameters
            }
            item.audioMix = mix
            for playerTrack in item.tracks {
                if playerTrack.assetTrack?.mediaType == .audio {
                    playerTrack.isEnabled = false
                }
            }
            player.isMuted = true
            player.volume = 0
            self.audioDisabled = true
            self.onChange?()
        }
    }

    private func openNativeVideo(url: URL, name: String) {
        nativeBackend = true
        nativeErrorText = nil
        let clock = PreviewVideoClock()
        clock.open(url: url, generation: seenGeneration)
        guard clock.attached else {
            nativeBackend = false
            failure = PreviewBGAChrome.unplayable(name)
            return
        }
        nativeClock = clock
        videoOpenCount += 1
        audioDisabled = true
        audioTrackCount = 0
        player = nil
        playerLayer.player = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        imageLayer.isHidden = true
        imageReady = false
        playerLayer.isHidden = true
        CATransaction.commit()
        pushNative(expected: expectedMediaSeconds ?? 0)
    }

    private func pushNative(expected: Double) {
        guard let clock = nativeClock else { return }
        let playing = wantsPlayback
        if clock.noteTransport(playing: playing, rate: requestedRate) {
            transportCommandCount += 1
        }
        clock.command(
            mediaSeconds: expected,
            rate: requestedRate,
            playing: playing,
            generation: seenGeneration
        )
        clock.poll(blackKey: blackKey, threshold: threshold)
        let snapshot = clock.stats
        seekCount = snapshot.seekCount
        if snapshot.hasLastSeek {
            lastSeekSeconds = snapshot.lastSeekSeconds
        }
        audioTrackCount = snapshot.audioStreams
        audioDisabled = snapshot.audioDecodedPackets == 0
        nativeErrorText = snapshot.failed ? snapshot.error : nil
        if snapshot.failed {
            failure = PreviewBGAChrome.unplayable(fileName)
            releasePlayer()
            kind = .missing
            return
        }
        guard let image = clock.image else { return }
        nativeImage = image
        nativePTS = snapshot.pts
        let coded = CGSize(width: snapshot.originalWidth, height: snapshot.originalHeight)
        if coded.width > 1, coded.height > 1, videoPixelSize != coded {
            videoPixelSize = coded
            layoutPicture()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nativeLayer.contents = image
        if nativeBackend {
            nativeLayer.isHidden = false
            playerLayer.isHidden = true
            videoHost.isHidden = videoPixelSize == nil
        }
        CATransaction.commit()
    }

    private func updateVideo(expected: Double) {
        if nativeClock != nil {
            pushNative(expected: expected)
            return
        }
        guard let player else { return }
        guard let item = player.currentItem else { return }
        if item.status == .failed {
            failure = PreviewBGAChrome.unplayable(fileName)
            releasePlayer()
            kind = .missing
            return
        }
        guard item.status == .readyToPlay else { return }
        let natural = item.presentationSize
        if natural.width > 1, natural.height > 1,
           videoPixelSize?.width != natural.width || videoPixelSize?.height != natural.height {
            videoPixelSize = natural
            layoutPicture()
        }
        let actual = player.currentTime().seconds
        let duration = item.duration.seconds
        let now = ProcessInfo.processInfo.systemUptime
        let force = appliedSeekRequest != request
        guard PreviewBGAVideoSync.shouldSeek(
            force: force,
            expected: expected,
            actual: actual.isFinite ? actual : nil,
            duration: duration.isFinite ? duration : nil,
            lastSeekUptime: lastSeekUptime,
            now: now
        ) else {
            applyTransport(player)
            return
        }
        var target = max(0, expected)
        if duration.isFinite, duration > 0.05 {
            target = min(target, max(0, duration - 0.001))
        }
        appliedSeekRequest = request
        lastSeekUptime = now
        seekInFlight = true
        seekCount += 1
        lastSeekSeconds = target
        let time = CMTime(seconds: target, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.02, preferredTimescale: 600)
        let token = request
        let generation = seenGeneration
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player,
                      self.player === player,
                      self.request == token,
                      self.seenGeneration == generation else { return }
                self.seekInFlight = false
                self.lastTransportCommand = -1
                self.applyTransport(player)
            }
        }
    }

    /// 不调用 `play()`。暂停命令和起播命令都只在目标变化时发一次。
    private func applyTransport(_ player: AVPlayer) {
        keepSilent(player)
        let desired: Float = wantsPlayback ? Float(requestedRate) : 0
        if desired == 0 {
            if player.rate != 0 {
                player.pause()
                transportCommandCount += 1
            }
            if !seekInFlight {
                lastTransportCommand = 0
            }
            return
        }
        guard !seekInFlight else { return }
        if lastTransportCommand == desired {
            return
        }
        guard player.currentItem?.status == .readyToPlay else { return }
        if abs(player.rate - desired) < PreviewBGAVideoSync.achievedRateSlop {
            lastTransportCommand = desired
            return
        }
        player.playImmediately(atRate: desired)
        lastTransportCommand = desired
        transportCommandCount += 1
        keepSilent(player)
    }

    private func keepSilent(_ player: AVPlayer) {
        if !player.isMuted || player.volume != 0 {
            player.isMuted = true
            player.volume = 0
        }
        guard audioDisabled, let item = player.currentItem else { return }
        for track in item.tracks where track.assetTrack?.mediaType == .audio && track.isEnabled {
            track.isEnabled = false
        }
    }
}

private enum PreviewBGAChannelKind: Equatable {
    case none
    case missing
    case image
    case video
}

private struct PreviewBGAEventKey: Equatable {
    var generation: UInt64
    var sequence: Int?
    var beat: Double
    var assetID: String
    var threshold: UInt8

    init(event: PreviewBGAEventIndex.Item?, generation: UInt64, threshold: UInt8) {
        self.generation = generation
        self.threshold = threshold
        if let event {
            sequence = event.sequence
            beat = event.beat
            assetID = event.assetID
        } else {
            sequence = nil
            beat = 0
            assetID = ""
        }
    }
}

private struct PreviewBGAResolved {
    var identity: String?
    var assetID: String?
    var fileName: String
    var url: URL?
    var kind: PreviewBGAChannelKind
    var failure: String?
}
