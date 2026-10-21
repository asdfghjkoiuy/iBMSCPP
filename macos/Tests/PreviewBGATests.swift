import AppKit
import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct PreviewBGATests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        do {
            testClockMatchesScheduleHits()
            testHereOffsetAndStopKeepsVideoTimeMoving()
            testSeekGate()
            testEventIndexBinarySearch()
            try testResolvePaths()
            try testEmptyMissingAndPoorIsStoredOnly()
            try testBlackKeyCompositeDoesNotShowPoor()
            try testRepeatedTicksDoNotDecodeAgain()
            try testMissingFileIsResolvedOncePerChart()
            try testStaleDecodeDoesNotReplaceTheNewChart()
            try testJPEGAndBMPFallback()
            try testVideoHereStopMuteAndHoldFrame()
            try testDisplayModeOffLoadsNothing()
            try testDisplayModesSelectLayersAndReuseCache()
            try testStaleDecodeDoesNotPaintAcrossMode()
            try testTransparencyThresholdPixelsAndCacheKey()
            try testModeSwitchKeepsVideoTimeMuted()
            try testStageCropAndFullCanvas()
            try testPlaybackRateTracksWallClock()
            try testRateStepReachesThePlayer()
            try testVideoDisplayScaleAndCrop()
        } catch {
            fail("\(error)")
        }
        print("PreviewBGATests passed")
    }

    @MainActor
    private static func testClockMatchesScheduleHits() {
        let timing = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [(beat: 4, bpm: 60)],
            stopEvents: [(beat: 2, durationSeconds: 1.5)]
        )
        let hits = LegacyPreviewAudio.scheduleHits(
            notes: [PreviewAudioNote(beat: 8, wavToken: "01")],
            timing: timing,
            fromBeat: 0
        )
        let seconds = PreviewBGAClock.seconds(fromBeat: 0, toBeat: 8, timing: timing)
        require(hits.count == 1, "schedule a note at beat 8")
        require(abs(hits[0].seconds - seconds) < 0.000001, "BGA clock matches scheduleHits, got \(seconds) vs \(hits[0].seconds)")
        require(abs(seconds - 7.5) < 0.000001, "120 BPM to beat 4, STOP 1.5s, then 60 BPM to beat 8 is 7.5s")
    }

    @MainActor
    private static func testHereOffsetAndStopKeepsVideoTimeMoving() {
        let timing = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [],
            stopEvents: [(beat: 2, durationSeconds: 1.5)]
        )
        let here = PreviewBGAClock.mediaSeconds(eventBeat: 0, playbackOrigin: 4, elapsedSeconds: 0, timing: timing)
        require(abs(here - 3.5) < 0.000001, "Here at beat 4 starts the beat-0 video 3.5s in, including the STOP")
        let duringStop = PreviewBGAClock.mediaSeconds(eventBeat: 0, playbackOrigin: 0, elapsedSeconds: 2.5, timing: timing)
        require(abs(duringStop - 2.5) < 0.000001, "STOP keeps the chart beat still while video time follows elapsed")
        let atEvent = PreviewBGAClock.mediaSeconds(eventBeat: 4, playbackOrigin: 0, elapsedSeconds: 3.5, timing: timing)
        require(abs(atEvent) < 0.000001, "a later event starts its own media clock at 0")
    }

    private static func testSeekGate() {
        let now: TimeInterval = 10
        require(PreviewBGAVideoSync.shouldSeek(force: true, expected: 1, actual: 1, duration: 4, lastSeekUptime: now, now: now), "event change seeks immediately")
        require(!PreviewBGAVideoSync.shouldSeek(force: false, expected: 1.05, actual: 1, duration: 4, lastSeekUptime: nil, now: now), "small drift does not seek")
        require(!PreviewBGAVideoSync.shouldSeek(force: false, expected: 2, actual: 1, duration: 4, lastSeekUptime: now - 0.1, now: now), "large drift inside the interval does not seek")
        require(PreviewBGAVideoSync.shouldSeek(force: false, expected: 2, actual: 1, duration: 4, lastSeekUptime: now - 0.4, now: now), "large drift after the interval seeks once")
        require(!PreviewBGAVideoSync.shouldSeek(force: false, expected: 9, actual: 3.9, duration: 4, lastSeekUptime: nil, now: now), "past the end does not keep seeking")
    }

    private static func testEventIndexBinarySearch() {
        var events: [PreviewBGAEvent] = []
        events.reserveCapacity(100_003)
        for beat in stride(from: 99_999, through: 0, by: -1) {
            events.append(PreviewBGAEvent(beat: Double(beat), assetID: "n\(beat)", layer: .base))
        }
        events.append(PreviewBGAEvent(beat: 20, assetID: "late", layer: .base))
        events.append(PreviewBGAEvent(beat: 5, assetID: "L", layer: .layer))
        events.append(PreviewBGAEvent(beat: 5, assetID: "P", layer: .poor))
        let index = PreviewBGAEventIndex(events: events)
        let late = index.event(at: 20, layer: .base)
        require(late?.assetID == "late", "the later event at the same beat wins")
        require(index.lastLookupSteps > 0 && index.lastLookupSteps <= 24, "100000 events resolve in \(index.lastLookupSteps) comparisons")
        require(index.event(at: 19.5, layer: .base)?.assetID == "n19", "lookup stays on the previous event")
        require(index.event(at: -1, layer: .base) == nil, "before the first event there is no BGA")
        require(index.event(at: 5, layer: .layer)?.assetID == "L", "layer events stay on the layer")
        require(index.event(at: 5, layer: .poor)?.assetID == "P", "poor events stay on poor")
        require(index.event(at: 5, layer: .base)?.assetID == "n5", "a layer event does not replace the base event")
    }

    @MainActor
    private static func testResolvePaths() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let png = nested.appendingPathComponent("shot.png")
        let bmp = root.appendingPathComponent("only.bmp")
        try writePNG(png, width: 4, height: 4) { _, _ in (10, 20, 30, 255) }
        try writeBitmap(bmp, width: 4, height: 4, type: .bmp) { _, _ in (1, 2, 3, 255) }
        let relative = PreviewBGAFiles.resolve(fileName: "nested/shot.png", chartDirectory: root)
        require(relative?.standardizedFileURL.path == png.standardizedFileURL.path, "relative path joins the chart directory")
        let slashed = PreviewBGAFiles.resolve(fileName: "nested\\shot.png", chartDirectory: root)
        require(slashed?.standardizedFileURL.path == png.standardizedFileURL.path, "backslash paths join the chart directory")
        let elsewhere = URL(fileURLWithPath: "/tmp")
        let absolute = PreviewBGAFiles.resolve(fileName: png.path, chartDirectory: elsewhere)
        require(absolute?.standardizedFileURL.path == png.standardizedFileURL.path, "an absolute path ignores the chart directory")
        let fallback = PreviewBGAFiles.resolve(fileName: "only.png", chartDirectory: root)
        require(fallback?.pathExtension.lowercased() == "bmp", "a missing png falls back through the local image extension list")
        try writePNG(root.appendingPathComponent("only.png"), width: 2, height: 2) { _, _ in (4, 5, 6, 255) }
        let exact = PreviewBGAFiles.resolve(fileName: "only.png", chartDirectory: root)
        require(exact?.pathExtension.lowercased() == "png", "an existing file is not replaced by another extension")
        require(PreviewBGAFiles.resolve(fileName: "https://example.com/a.png", chartDirectory: root) == nil, "http paths are refused")
        require(PreviewBGAFiles.resolve(fileName: "ftp://example.com/a.mpg", chartDirectory: root) == nil, "ftp paths are refused")
    }

    @MainActor
    private static func testEmptyMissingAndPoorIsStoredOnly() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        view.setChart(PreviewChartSnapshot(), chartDirectory: root, timing: steady, fromBeat: 0)
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        var state = view.inspection()
        require(state.status == "无 BGA", "an empty chart says there is no BGA")
        require(state.imageDecodeCount == 0 && !state.videoAttached, "empty chart does not decode or open a player")
        require(view.clipsToBounds, "BGA stays inside its own view")

        var poorOnly = PreviewChartSnapshot()
        poorOnly.bgaAssets = [PreviewBGAAsset(id: "P", fileName: "miss.png")]
        poorOnly.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "P", layer: .poor)]
        try writePNG(root.appendingPathComponent("miss.png"), width: 8, height: 8) { _, _ in (0, 0, 255, 255) }
        view.setChart(poorOnly, chartDirectory: root, timing: steady, fromBeat: 0)
        view.setPlayback(beat: 1, elapsedSeconds: 0.5, isPlaying: true)
        state = view.inspection()
        require(state.poorAssetID == "P" && state.poorFileName == "miss.png", "poor is stored")
        require(state.baseAssetID == nil && state.layerAssetID == nil, "poor is not shown on base or layer")
        require(state.status == "无 BGA", "stored poor is not a visible BGA")
        require(state.imageDecodeCount == 0, "poor is not decoded")

        var missing = PreviewChartSnapshot()
        missing.bgaAssets = [
            PreviewBGAAsset(id: "01", fileName: "gone.png"),
            PreviewBGAAsset(id: "web", fileName: "https://example.com/remote.png")
        ]
        missing.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "ZZ", layer: .base),
            PreviewBGAEvent(beat: 2, assetID: "01", layer: .base),
            PreviewBGAEvent(beat: 4, assetID: "web", layer: .layer)
        ]
        view.setChart(missing, chartDirectory: root, timing: steady, fromBeat: 0)
        state = view.inspection()
        require(state.status.contains("未定义"), "an unknown asset id is reported, status=\(state.status)")
        view.setPlayback(beat: 2, elapsedSeconds: 1, isPlaying: false)
        state = view.inspection()
        require(state.status.contains("缺少") && state.status.contains("gone.png"), "a missing file is reported, status=\(state.status)")
        require(state.imageDecodeCount == 0, "missing files are not decoded")
        view.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: true)
        state = view.inspection()
        require(state.status.contains("缺少"), "a network path is refused, status=\(state.status)")
        require(!state.videoAttached && state.imageDecodeCount == 0, "a network path does not open a player or decoder")
    }

    @MainActor
    private static func testBlackKeyCompositeDoesNotShowPoor() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(root.appendingPathComponent("base.png"), width: 160, height: 120) { _, _ in (220, 0, 0, 255) }
        try writePNG(root.appendingPathComponent("layer.png"), width: 160, height: 120) { x, y in
            if (60..<100).contains(x), (40..<80).contains(y) {
                return (255, 255, 255, 255)
            }
            return (0, 0, 0, 255)
        }
        try writePNG(root.appendingPathComponent("poor.png"), width: 160, height: 120) { _, _ in (0, 0, 255, 255) }
        var chart = PreviewChartSnapshot(title: "BGA")
        chart.bgaAssets = [
            PreviewBGAAsset(id: "B", fileName: "base.png"),
            PreviewBGAAsset(id: "L", fileName: "layer.png"),
            PreviewBGAAsset(id: "P", fileName: "poor.png")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "B", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "L", layer: .layer),
            PreviewBGAEvent(beat: 0, assetID: "P", layer: .poor)
        ]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        wait(view, timeout: 4) { $0.baseImageReady && $0.layerImageReady }
        let state = view.inspection()
        require(state.imageDecodeCount == 2, "base and layer decode once each, count=\(state.imageDecodeCount)")
        require(state.poorAssetID == "P" && state.poorFileName == "poor.png", "poor stays stored beside the visible layers")
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        let counts = pixelCounts(render(view))
        try writeCounts(counts, name: "bga-composite.png", image: render(view))
        require(counts.red > 8_000, "black-keyed layer lets the red base show, counts=\(counts)")
        require(counts.white > 800, "the opaque part of the layer stays on top, counts=\(counts)")
        require(counts.blue == 0, "poor blue is not composited, counts=\(counts)")
        _ = window
    }

    @MainActor
    private static func testRepeatedTicksDoNotDecodeAgain() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(root.appendingPathComponent("still.png"), width: 16, height: 16) { _, _ in (0, 180, 0, 255) }
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "still.png")]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "01", layer: .base),
            PreviewBGAEvent(beat: 4, assetID: "", layer: .base)
        ]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        require(view.inspection().pathResolveCount == 1, "setChart resolves the image path once")
        for step in 0..<400 {
            view.setPlayback(beat: Double(step) / 400, elapsedSeconds: Double(step) / 60, isPlaying: true)
        }
        require(view.inspection().imageDecodeCount == 1, "hundreds of ticks do not decode again")
        require(view.inspection().pathResolveCount == 1, "hundreds of ticks do not resolve the path again")
        wait(view, timeout: 3) { $0.baseImageReady }
        for step in 0..<400 {
            view.setPlayback(beat: 1 + Double(step) / 200, elapsedSeconds: 0.5 + Double(step) / 60, isPlaying: true)
        }
        let held = view.inspection()
        require(held.imageDecodeCount == 1 && held.pathResolveCount == 1, "the same event does not touch the file again")
        require(held.timingEvaluationCount == 0, "a still image does not integrate BPM")
        view.setPlayback(beat: 5, elapsedSeconds: 2.5, isPlaying: true)
        let cleared = view.inspection()
        require(cleared.baseAssetID == nil && !cleared.baseImageReady, "an empty asset id clears the base layer")
        require(cleared.status == "无 BGA", "a cleared layer returns to the empty state")
        require(cleared.imageDecodeCount == 1 && cleared.pathResolveCount == 1, "clearing does not decode or stat the old file")
    }

    @MainActor
    private static func testMissingFileIsResolvedOncePerChart() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "gone.png")]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        for step in 0..<400 {
            view.setPlayback(beat: Double(step) / 50, elapsedSeconds: Double(step) / 60, isPlaying: true)
        }
        let once = view.inspection()
        require(once.pathResolveCount == 1, "a missing file is resolved once, count=\(once.pathResolveCount)")
        require(once.imageDecodeCount == 0, "a missing file is not decoded")
        require(once.status.contains("缺少"), "the missing file stays visible as a status")
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        for _ in 0..<40 {
            view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        }
        require(view.inspection().pathResolveCount == 2, "opening the chart again retries the missing file")
    }

    @MainActor
    private static func testStaleDecodeDoesNotReplaceTheNewChart() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(root.appendingPathComponent("red.png"), width: 32, height: 24) { _, _ in (210, 0, 0, 255) }
        try writePNG(root.appendingPathComponent("green.png"), width: 32, height: 24) { _, _ in (0, 190, 0, 255) }
        let gate = DecodeGate()
        PreviewBGAImageLoader.beforeDecode = { gate.enter() }
        defer { PreviewBGAImageLoader.beforeDecode = nil }
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)
        view.setChart(imageChart(id: "R", file: "red.png"), chartDirectory: root, timing: steady, fromBeat: 0)
        let started = Date()
        while gate.startedCount < 1 && Date().timeIntervalSince(started) < 3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        require(gate.startedCount >= 1, "the first decode started")
        view.setChart(imageChart(id: "G", file: "green.png"), chartDirectory: root, timing: steady, fromBeat: 0)
        gate.unblock()
        wait(view, timeout: 4) { $0.baseImageReady && $0.baseAssetID == "G" }
        let settle = Date()
        while Date().timeIntervalSince(settle) < 0.4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        let counts = pixelCounts(render(view))
        require(counts.green > 400, "the newer chart stays on screen, counts=\(counts)")
        require(counts.red < 40, "the old chart's decode does not paint over it, counts=\(counts)")
        require(view.inspection().generation >= 2, "each chart bumps the generation")
        _ = window
    }

    @MainActor
    private static func testJPEGAndBMPFallback() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeBitmap(root.appendingPathComponent("photo.jpg"), width: 80, height: 60, type: .jpeg) { _, _ in (0, 170, 0, 255) }
        try writeBitmap(root.appendingPathComponent("plate.bmp"), width: 80, height: 60, type: .bmp) { _, _ in (230, 210, 0, 255) }
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)
        var jpeg = PreviewChartSnapshot()
        jpeg.bgaAssets = [PreviewBGAAsset(id: "J", fileName: "photo.jpg")]
        jpeg.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "J", layer: .base)]
        view.setChart(jpeg, chartDirectory: root, timing: steady, fromBeat: 0)
        wait(view, timeout: 4) { $0.baseImageReady }
        window.displayIfNeeded()
        var counts = pixelCounts(render(view))
        require(counts.green > 1_000, "JPEG base is composited, counts=\(counts)")

        var bmp = PreviewChartSnapshot()
        bmp.bgaAssets = [PreviewBGAAsset(id: "B", fileName: "plate.png")]
        bmp.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "B", layer: .base)]
        view.setChart(bmp, chartDirectory: root, timing: steady, fromBeat: 0)
        wait(view, timeout: 4) { $0.baseImageReady && $0.baseAssetID == "B" }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        counts = pixelCounts(render(view))
        try writeCounts(counts, name: "bga-bmp.png", image: render(view))
        require(counts.yellow > 1_000, "a png name falls back to bmp and is composited, counts=\(counts)")
        _ = window
    }

    @MainActor
    private static func testVideoHereStopMuteAndHoldFrame() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("clip.m4v")
        try writeClip(videoURL, seconds: 3)
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = awaitTracks(asset)
        require(!audioTracks.isEmpty, "the local test clip has an audio track so mute can be checked")
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [PreviewBGAAsset(id: "V", fileName: "clip.m4v")]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "V", layer: .base)]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        let window = host(view)
        let here = 0.5
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 1)
        var state = view.inspection()
        require(abs((state.expectedVideoSeconds ?? -1) - here) < 0.000001, "Here at beat 1 expects 0.5s of media before play")
        require(state.status == "视频未播放" && !state.videoAttached, "video stays closed until playback")
        pump(view, beat: 1, elapsed: 0, playing: true, timeout: 6) {
            $0.videoSeekCount >= 1 && abs(($0.currentVideoSeconds ?? -1) - here) < 0.35
        }
        state = view.inspection()
        require(state.videoAttached && state.videoMuted, "the playing clip is muted, error=\(state.videoItemError ?? "")")
        require(abs((state.expectedVideoSeconds ?? -1) - here) < 0.000001, "expected media time stays on the shared elapsed clock")
        require(abs((state.currentVideoSeconds ?? -1) - here) < 0.35, "player time follows the Here offset, current=\(state.currentVideoSeconds ?? -1) error=\(state.videoItemError ?? "")")
        let afterOpen = state.videoSeekCount
        for step in 0..<12 {
            view.setPlayback(beat: 1, elapsedSeconds: 0.02 + Double(step) * 0.004, isPlaying: true)
        }
        require(view.inspection().videoSeekCount == afterOpen, "small elapsed steps do not seek again")
        let jump = 1.5
        let beforeJump = view.inspection().videoSeekCount
        let jumpStarted = Date()
        while Date().timeIntervalSince(jumpStarted) < 0.55 {
            view.setPlayback(beat: 1, elapsedSeconds: 1.0, isPlaying: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let jumped = view.inspection().videoSeekCount - beforeJump
        require(jumped == 1, "a STOP-sized elapsed jump seeks once, not every tick, delta=\(jumped)")
        pump(view, beat: 1, elapsed: 1.0, playing: true, timeout: 3) {
            abs(($0.currentVideoSeconds ?? -1) - jump) < 0.4
        }
        state = view.inspection()
        require(abs((state.expectedVideoSeconds ?? -1) - jump) < 0.000001, "beat stays at 1 while elapsed moves the video to 1.5s")
        require(abs((state.currentVideoSeconds ?? -1) - jump) < 0.4, "player time continues through STOP, current=\(state.currentVideoSeconds ?? -1)")
        pump(view, beat: 1, elapsed: 1.0, playing: true, timeout: 3) { $0.videoAudioTrackCount > 0 && $0.videoAudioDisabled }
        state = view.inspection()
        require(state.videoAudioTrackCount > 0 && state.videoAudioDisabled, "the video audio mix is silenced, tracks=\(state.videoAudioTrackCount)")
        require(state.timingEvaluationCount == 1, "Here and STOP reuse one cached offset, count=\(state.timingEvaluationCount)")
        require(state.pathResolveCount == 1 && state.videoOpenCount == 1, "playback does not resolve or reopen the clip")
        let frozen = state
        for _ in 0..<400 {
            view.setPlayback(beat: 1, elapsedSeconds: 1.0, isPlaying: false)
        }
        state = view.inspection()
        require(state.videoAttached && state.videoItemKept, "natural end keeps the last video frame")
        require(state.videoRate == 0, "pause stops playback")
        require(state.videoMuted && state.videoAudioDisabled, "paused video stays muted")
        require(state.videoSeekCount == frozen.videoSeekCount, "pause does not seek")
        require(state.videoOpenCount == frozen.videoOpenCount, "pause does not rebuild the player")
        require(state.pathResolveCount == frozen.pathResolveCount && state.timingEvaluationCount == frozen.timingEvaluationCount, "pause does not resolve or retime")
        require(abs((state.currentVideoSeconds ?? -1) - (frozen.currentVideoSeconds ?? -2)) < 0.35, "the held frame stays at the paused media time")
        window.contentView = NSView()
        state = view.inspection()
        require(state.videoAttached && state.videoItemKept && state.videoRate == 0 && state.videoMuted, "closing the window pauses without sound or tearing down the item")
        require(state.videoOpenCount == frozen.videoOpenCount && state.videoSeekCount == frozen.videoSeekCount, "closing the window does not seek or rebuild")
        view.setChart(PreviewChartSnapshot(), chartDirectory: root, timing: steady, fromBeat: 0)
        state = view.inspection()
        require(!state.videoAttached && !state.videoItemKept, "the next chart releases the old player")
        _ = window
    }

    @MainActor
    private static func testDisplayModeOffLoadsNothing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(root.appendingPathComponent("base.png"), width: 8, height: 8) { _, _ in (220, 0, 0, 255) }
        try writePNG(root.appendingPathComponent("layer.png"), width: 8, height: 8) { _, _ in (0, 180, 0, 255) }
        try writePNG(root.appendingPathComponent("poor.png"), width: 8, height: 8) { _, _ in (0, 0, 220, 255) }
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: root.appendingPathComponent("clip.m4v"))
        let chart = layeredChart()
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        let fresh = view.inspection()
        require(fresh.displayMode == 3 && fresh.transparencyThreshold == 0, "default is normal and pure-black key, mode=\(fresh.displayMode) t=\(fresh.transparencyThreshold)")
        view.setDisplayMode(0)
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        view.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: true)
        for step in 0..<40 {
            view.setPlayback(beat: Double(step % 6), elapsedSeconds: Double(step) / 10, isPlaying: true)
        }
        var state = view.inspection()
        require(state.displayMode == 0, "mode stays off")
        require(state.pathResolveCount == 0 && state.imageDecodeCount == 0 && state.videoOpenCount == 0, "off does not resolve, decode, or open, \(state.pathResolveCount)/\(state.imageDecodeCount)/\(state.videoOpenCount)")
        require(!state.videoAttached && !state.videoItemKept && state.baseAssetID == nil && state.layerAssetID == nil && !state.poorImageReady, "off keeps every layer unloaded")
        require(state.eventIndexBuildCount == 1, "ticks do not rebuild the event index, count=\(state.eventIndexBuildCount)")
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        view.setDisplayMode(3)
        wait(view, timeout: 4) { $0.baseImageReady && $0.layerImageReady }
        state = view.inspection()
        require(state.imageDecodeCount == 2 && state.videoOpenCount == 0 && !state.poorImageReady, "normal loads base and layer only, decode=\(state.imageDecodeCount) open=\(state.videoOpenCount)")
        require(state.poorAssetID == "P" && state.poorFileName == "poor.png", "normal still remembers poor without reading it")
        require(state.eventIndexBuildCount == 1 && state.generation == 1, "turning the mode back on does not call setChart")
        view.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        state = view.inspection()
        require(state.videoOpenCount == 1 && state.imageDecodeCount == 2 && !state.poorImageReady, "the video beat is real, so off was not an empty chart, open=\(state.videoOpenCount) decode=\(state.imageDecodeCount)")
        view.setDisplayMode(9)
        require(view.inspection().displayMode == 3, "an unknown mode does not change the current one")
        view.setDisplayMode(0)
        state = view.inspection()
        require(!state.videoAttached && !state.videoItemKept && state.videoOpenCount == 1, "turning off pauses and releases the player, open=\(state.videoOpenCount)")
    }

    @MainActor
    private static func testDisplayModesSelectLayersAndReuseCache() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(root.appendingPathComponent("base.png"), width: 160, height: 120) { _, _ in (220, 0, 0, 255) }
        try writePNG(root.appendingPathComponent("layer.png"), width: 160, height: 120) { _, _ in (0, 180, 0, 255) }
        try writePNG(root.appendingPathComponent("poor.png"), width: 160, height: 120) { _, _ in (0, 0, 220, 255) }
        let chart = layeredChart()
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)

        view.setDisplayMode(1)
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        wait(view, timeout: 4) { $0.baseImageReady }
        var state = view.inspection()
        require(state.baseAssetID == "B" && state.layerAssetID == nil && !state.poorImageReady, "base only ignores layer and poor")
        require(state.imageDecodeCount == 1 && state.pathResolveCount == 1 && state.videoOpenCount == 0, "base only reads the base file, decode=\(state.imageDecodeCount) resolve=\(state.pathResolveCount)")
        window.displayIfNeeded()
        var counts = pixelCounts(render(view))
        require(counts.red > 8_000 && counts.green == 0 && counts.blue == 0, "base only pixels are the base image, \(counts)")

        view.setDisplayMode(2)
        wait(view, timeout: 4) { $0.layerImageReady && !$0.baseImageReady }
        state = view.inspection()
        require(state.baseAssetID == nil && state.layerAssetID == "L" && !state.poorImageReady, "layer only clears base")
        require(state.imageDecodeCount == 2 && state.pathResolveCount == 2, "layer only reads the layer file, decode=\(state.imageDecodeCount) resolve=\(state.pathResolveCount)")
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.green > 8_000 && counts.red == 0 && counts.blue == 0, "layer only pixels are the layer image, \(counts)")

        view.setDisplayMode(4)
        wait(view, timeout: 4) { $0.poorImageReady && !$0.baseImageReady && !$0.layerImageReady }
        state = view.inspection()
        require(state.baseAssetID == nil && state.layerAssetID == nil && state.poorAssetID == "P", "always poor shows poor and not the other layers")
        require(state.imageDecodeCount == 3 && state.pathResolveCount == 3, "always poor reads the poor file, decode=\(state.imageDecodeCount) resolve=\(state.pathResolveCount)")
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.blue > 8_000 && counts.red == 0 && counts.green == 0, "always poor pixels are the poor image, \(counts)")

        let warmed = state
        for _ in 0..<6 {
            view.setDisplayMode(1)
            view.setDisplayMode(2)
            view.setDisplayMode(4)
            view.setDisplayMode(3)
            view.setDisplayMode(0)
        }
        view.setDisplayMode(3)
        wait(view, timeout: 4) { $0.baseImageReady && $0.layerImageReady && !$0.poorImageReady }
        state = view.inspection()
        require(state.imageDecodeCount == warmed.imageDecodeCount && state.pathResolveCount == warmed.pathResolveCount, "repeating modes reuses decoded images and resolved paths, decode=\(state.imageDecodeCount) resolve=\(state.pathResolveCount)")
        require(state.eventIndexBuildCount == 1, "mode switches do not rebuild the index or call setChart")
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.green > 8_000 && counts.blue == 0, "normal after always poor shows the layer again, \(counts)")

        let missing = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let missingWindow = host(missing)
        var missingChart = chart
        missingChart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "B", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "L", layer: .layer)
        ]
        missing.setDisplayMode(4)
        missing.setChart(missingChart, chartDirectory: root, timing: steady, fromBeat: 0)
        missing.setPlayback(beat: 1, elapsedSeconds: 0.2, isPlaying: true)
        state = missing.inspection()
        require(state.status == "无 BGA" && state.poorAssetID == nil && state.baseAssetID == nil && !state.baseImageReady, "missing poor is an empty state, status=\(state.status)")
        require(state.imageDecodeCount == 0 && state.pathResolveCount == 0, "missing poor does not fall back to base, decode=\(state.imageDecodeCount) resolve=\(state.pathResolveCount)")
        missingWindow.displayIfNeeded()
        counts = pixelCounts(render(missing))
        require(counts.red == 0 && counts.green == 0 && counts.blue == 0, "missing poor does not paint another layer, \(counts)")
        _ = window
        _ = missingWindow
    }

    @MainActor
    private static func testStaleDecodeDoesNotPaintAcrossMode() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(root.appendingPathComponent("red.png"), width: 32, height: 24) { _, _ in (210, 0, 0, 255) }
        let gate = DecodeGate()
        PreviewBGAImageLoader.beforeDecode = { gate.enter() }
        defer { PreviewBGAImageLoader.beforeDecode = nil }
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)
        view.setChart(imageChart(id: "R", file: "red.png"), chartDirectory: root, timing: steady, fromBeat: 0)
        let started = Date()
        while gate.startedCount < 1 && Date().timeIntervalSince(started) < 3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        require(gate.startedCount >= 1, "the normal decode started")
        let generation = view.inspection().generation
        view.setDisplayMode(0)
        gate.unblock()
        let settle = Date()
        while Date().timeIntervalSince(settle) < 0.5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        var state = view.inspection()
        require(!state.baseImageReady && state.displayMode == 0, "off stays blank while the old decode finishes")
        window.displayIfNeeded()
        var counts = pixelCounts(render(view))
        require(counts.red == 0, "the in-flight decode does not paint the disabled layer, \(counts)")
        view.setDisplayMode(2)
        let layerSettle = Date()
        while Date().timeIntervalSince(layerSettle) < 0.3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        state = view.inspection()
        require(!state.baseImageReady && state.layerAssetID == nil, "layer only does not revive the base decode")
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.red == 0, "the finished base decode stays off the layer-only frame, \(counts)")
        let decodes = state.imageDecodeCount
        view.setDisplayMode(3)
        wait(view, timeout: 4) { $0.baseImageReady && $0.baseAssetID == "R" }
        state = view.inspection()
        require(state.imageDecodeCount == decodes, "turning normal back on reuses the decode that finished while off, count=\(state.imageDecodeCount)")
        require(state.generation == generation && state.eventIndexBuildCount == 1, "the mode round trip keeps the same chart")
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.red > 400, "the current chart paints after the mode returns, \(counts)")
        _ = window
    }

    @MainActor
    private static func testTransparencyThresholdPixelsAndCacheKey() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let black = root.appendingPathComponent("black.png")
        let eight = root.appendingPathComponent("eight.png")
        let nine = root.appendingPathComponent("nine.png")
        let dark = root.appendingPathComponent("dark.png")
        let white = root.appendingPathComponent("white.png")
        try writePNG(black, width: 2, height: 2) { _, _ in (0, 0, 0, 255) }
        try writePNG(eight, width: 2, height: 2) { _, _ in (8, 8, 8, 255) }
        try writePNG(nine, width: 2, height: 2) { _, _ in (9, 0, 0, 255) }
        try writePNG(dark, width: 2, height: 2) { _, _ in (12, 0, 0, 255) }
        try writePNG(white, width: 2, height: 2) { _, _ in (255, 255, 255, 255) }

        var pixel = try sampleDecode(black, blackKey: true, threshold: 0)
        require(pixel.3 == 0, "threshold 0 keys only RGB 0, got \(pixel)")
        pixel = try sampleDecode(eight, blackKey: true, threshold: 0)
        require(pixel == (8, 8, 8, 255), "threshold 0 keeps RGB 8, got \(pixel)")
        pixel = try sampleDecode(eight, blackKey: true, threshold: 8)
        require(pixel.3 == 0, "threshold 8 keys RGB 8, got \(pixel)")
        pixel = try sampleDecode(nine, blackKey: true, threshold: 8)
        require(pixel.0 == 9 && pixel.3 == 255, "threshold 8 keeps a channel above 8, got \(pixel)")
        pixel = try sampleDecode(white, blackKey: true, threshold: 255)
        require(pixel.3 == 0, "threshold 255 keys every overlay pixel, got \(pixel)")
        pixel = try sampleDecode(dark, blackKey: false, threshold: 255)
        require(pixel == (12, 0, 0, 255), "base keeps its color at threshold 255, got \(pixel)")
        pixel = try sampleDecode(black, blackKey: false, threshold: 255)
        require(pixel == (0, 0, 0, 255), "base keeps pure black, got \(pixel)")

        let key0 = PreviewBGAImageCacheKey.make(path: eight.path, blackKey: true, threshold: 0)
        let key8 = PreviewBGAImageCacheKey.make(path: eight.path, blackKey: true, threshold: 8)
        let key255 = PreviewBGAImageCacheKey.make(path: eight.path, blackKey: true, threshold: 255)
        let baseKey = PreviewBGAImageCacheKey.make(path: eight.path, blackKey: false, threshold: 255)
        require(key0 != key8 && key8 != key255 && key0 != baseKey, "cache keys change with threshold and black key")
        require(key0.hasSuffix("|black:1|t:0"), "threshold 0 is in the cache key, \(key0)")
        require(key8.hasSuffix("|black:1|t:8"), "threshold 8 is in the cache key, \(key8)")
        require(key255.hasSuffix("|black:1|t:255"), "threshold 255 is in the cache key, \(key255)")
        require(baseKey.hasSuffix("|black:0|t:255"), "base entries are a separate key, \(baseKey)")

        try writePNG(root.appendingPathComponent("base.png"), width: 80, height: 60) { _, _ in (220, 0, 0, 255) }
        try writePNG(root.appendingPathComponent("layer.png"), width: 80, height: 60) { _, _ in (8, 8, 8, 255) }
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [
            PreviewBGAAsset(id: "B", fileName: "base.png"),
            PreviewBGAAsset(id: "L", fileName: "layer.png")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "B", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "L", layer: .layer)
        ]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        wait(view, timeout: 4) { $0.baseImageReady && $0.layerImageReady }
        window.displayIfNeeded()
        var center = topPixel(render(view), width: 256, height: 256, x: 88, y: 0)
        require(center.0 <= 20 && center.1 <= 20 && center.2 <= 20, "threshold 0 leaves RGB 8 opaque over the base, \(center)")
        require(view.inspection().imageDecodeCount == 2, "first composite decodes base and layer")
        view.setTransparencyThreshold(8)
        wait(view, timeout: 4) { $0.baseImageReady && $0.layerImageReady && $0.imageDecodeCount == 4 }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        var counts = pixelCounts(render(view))
        require(counts.red > 1_000, "threshold 8 keys RGB 8 and shows the red base, \(counts)")
        let decoded = view.inspection().imageDecodeCount
        view.setTransparencyThreshold(0)
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        center = topPixel(render(view), width: 256, height: 256, x: 88, y: 0)
        require(center.0 <= 20 && center.1 <= 20 && center.2 <= 20, "returning to threshold 0 restores the dark overlay from cache, \(center)")
        require(view.inspection().imageDecodeCount == decoded, "the threshold 0 key is reused, count=\(view.inspection().imageDecodeCount)")
        view.setTransparencyThreshold(255)
        wait(view, timeout: 4) { $0.imageDecodeCount > decoded && $0.layerImageReady }
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.red > 1_000, "threshold 255 makes the whole overlay transparent, \(counts)")
        let after255 = view.inspection().imageDecodeCount
        view.setTransparencyThreshold(8)
        require(view.inspection().imageDecodeCount == after255, "threshold 8 was already cached")
        window.displayIfNeeded()
        counts = pixelCounts(render(view))
        require(counts.red > 1_000, "cached threshold 8 still shows the base, \(counts)")

        let baseOnly = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let baseWindow = host(baseOnly)
        var darkChart = PreviewChartSnapshot()
        darkChart.bgaAssets = [PreviewBGAAsset(id: "D", fileName: "dark.png")]
        darkChart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "D", layer: .base)]
        baseOnly.setDisplayMode(1)
        baseOnly.setTransparencyThreshold(255)
        baseOnly.setChart(darkChart, chartDirectory: root, timing: steady, fromBeat: 0)
        wait(baseOnly, timeout: 4) { $0.baseImageReady }
        baseWindow.displayIfNeeded()
        center = topPixel(render(baseOnly), width: 256, height: 256, x: 127, y: 0)
        require(center.0 >= 8 && center.0 <= 24 && center.1 == 0 && center.2 == 0, "base only keeps dark red at threshold 255, \(center)")
        _ = window
        _ = baseWindow
    }

    @MainActor
    private static func testModeSwitchKeepsVideoTimeMuted() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("clip.m4v")
        try writeClip(videoURL, seconds: 3)
        let timing = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [],
            stopEvents: [(beat: 0.5, durationSeconds: 0.4)]
        )
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [PreviewBGAAsset(id: "V", fileName: "clip.m4v")]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "V", layer: .base)]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        let window = host(view)
        view.setChart(chart, chartDirectory: root, timing: timing, fromBeat: 1)
        var state = view.inspection()
        require(abs((state.expectedVideoSeconds ?? -1) - 0.9) < 0.000001, "Here plus STOP expects 0.9s")
        pump(view, beat: 1, elapsed: 0, playing: true, timeout: 6) {
            $0.videoSeekCount >= 1 && abs(($0.currentVideoSeconds ?? -1) - 0.9) < 0.35
        }
        state = view.inspection()
        require(state.videoMuted && state.videoAttached, "playback starts muted")
        let opened = state.videoOpenCount
        let resolved = state.pathResolveCount
        view.setPlayback(beat: 1, elapsedSeconds: 0.6, isPlaying: true)
        view.setDisplayMode(0)
        state = view.inspection()
        require(!state.videoAttached && !state.videoItemKept, "off releases the playing item instead of only hiding it")
        require(state.videoOpenCount == opened && state.pathResolveCount == resolved, "off does not reopen or resolve during the seek")
        require(state.eventIndexBuildCount == 1, "the seek and mode change keep the chart")
        for _ in 0..<20 {
            view.setPlayback(beat: 1, elapsedSeconds: 0.6, isPlaying: true)
        }
        state = view.inspection()
        require(!state.videoAttached && state.videoOpenCount == opened && state.pathResolveCount == resolved, "ticks while off stay quiet")
        view.setDisplayMode(1)
        pump(view, beat: 1, elapsed: 0.6, playing: true, timeout: 6) {
            $0.videoAttached && $0.videoMuted && abs(($0.currentVideoSeconds ?? -1) - 1.5) < 0.4
        }
        state = view.inspection()
        require(abs((state.expectedVideoSeconds ?? -1) - 1.5) < 0.000001, "media time stays on the shared elapsed clock, expected=\(state.expectedVideoSeconds ?? -1)")
        require(abs((state.currentVideoSeconds ?? -1) - 1.5) < 0.4, "the clip does not restart at zero, current=\(state.currentVideoSeconds ?? -1)")
        require(state.videoMuted && state.videoOpenCount == opened + 1, "reopening seeks the picture and stays muted, open=\(state.videoOpenCount)")
        require(state.pathResolveCount == resolved, "the path cache survives the mode switch, resolve=\(state.pathResolveCount)")
        let heldOpen = state.videoOpenCount
        view.setDisplayMode(3)
        state = view.inspection()
        require(state.videoOpenCount == heldOpen && state.videoAttached && state.videoMuted, "normal keeps the same muted base clip")
        require(abs((state.currentVideoSeconds ?? -1) - 1.5) < 0.45, "switching to normal does not rewind, current=\(state.currentVideoSeconds ?? -1)")
        view.setDisplayMode(2)
        state = view.inspection()
        require(!state.videoAttached && !state.videoItemKept && state.baseAssetID == nil, "layer only clears the base video")
        view.setDisplayMode(3)
        pump(view, beat: 1, elapsed: 0.6, playing: true, timeout: 6) {
            $0.videoMuted && abs(($0.expectedVideoSeconds ?? -1) - 1.5) < 0.000001
                && abs(($0.currentVideoSeconds ?? -1) - 1.5) < 0.4
        }
        pump(view, beat: 1, elapsed: 0.6, playing: true, timeout: 3) { $0.videoAudioDisabled && $0.videoMuted }
        state = view.inspection()
        require(state.videoMuted && state.videoAudioDisabled, "the restored clip stays silent")
        require(abs((state.currentVideoSeconds ?? -1) - 1.5) < 0.4, "restoring base keeps the STOP media time, current=\(state.currentVideoSeconds ?? -1)")
        require(state.eventIndexBuildCount == 1, "video mode switches do not rebuild the index")
        _ = window
    }

    @MainActor
    private static func testStageCropAndFullCanvas() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pattern = root.appendingPathComponent("pattern.png")
        try writePNG(pattern, width: 4, height: 4) { x, y in patternPixel(x, y) }
        try writePNG(root.appendingPathComponent("red.png"), width: 8, height: 8) { _, _ in (220, 0, 0, 255) }
        try writePNG(root.appendingPathComponent("blue.png"), width: 8, height: 8) { _, _ in (0, 0, 220, 255) }
        try writeWideMarkers(root.appendingPathComponent("wide.png"))

        let direct = try showStage(
            root: root,
            files: ["01": "pattern.png"],
            events: [(id: "01", layer: PreviewBGALayer.base)],
            script: "#BMP01 pattern.png\n",
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        for y in 0..<4 {
            for x in 0..<4 {
                let pixel = topPixel(direct.bytes, width: 256, height: 256, x: 126 + x, y: y)
                require(pixel == patternPixel(x, y), "direct 4x4 at \(x),\(y) is \(pixel), not aspect-fit")
            }
        }

        let wide = try showStage(
            root: root,
            files: ["01": "wide.png"],
            events: [(id: "01", layer: .base)],
            script: nil,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(topPixel(wide.bytes, width: 256, height: 256, x: 0, y: 0) == (0, 255, 0, 255), "512-wide image shows source x=128 at the stage edge")
        require(topPixel(wide.bytes, width: 256, height: 256, x: 255, y: 0) == (0, 0, 255, 255), "the visible right edge is source x=383")
        require(topPixel(wide.bytes, width: 256, height: 256, x: 0, y: 255) == (255, 255, 0, 255), "height stops at the top 256 rows")
        require(topPixel(wide.bytes, width: 256, height: 256, x: 0, y: 0) != (255, 0, 0, 255), "source x=0 stays outside the stage")

        let aliasScript = """
        #BMP00 pattern.png
        #BMP01 pattern.png
        #BMP05 red.png
        #BGA05 00 0 0 4 4 10 4
        #BGA01 01 0 0 4 4 0 0
        #BGA01 01 1 1 2 2 20 8
        #BGA02 01 3 2 0 0 30 6
        #BGA03 01
        #BGA04 01 -1 -1 2 2 40 10
        #BGA06 01 0 0 4 4 999999999 0
        """
        let alias = try showStage(
            root: root,
            files: ["05": "red.png", "00": "pattern.png", "01": "pattern.png"],
            events: [(id: "05", layer: .base)],
            script: aliasScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(alias.state.imageDecodeCount == 1, "alias reads BMP00 once, decode=\(alias.state.imageDecodeCount)")
        require(topPixel(alias.bytes, width: 256, height: 256, x: 10, y: 4) == patternPixel(0, 0), "alias pixels come from BMP00")
        require(topPixel(alias.bytes, width: 256, height: 256, x: 10, y: 4) != (220, 0, 0, 255), "alias does not draw the same-id BMP")

        let replaced = try showStage(
            root: root,
            files: ["01": "pattern.png"],
            events: [(id: "01", layer: .base)],
            script: aliasScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(topPixel(replaced.bytes, width: 256, height: 256, x: 20, y: 8) == patternPixel(1, 1), "the later #BGA wins")
        require(topPixel(replaced.bytes, width: 256, height: 256, x: 0, y: 0) == (0, 0, 0, 255), "the replaced full-frame crop is gone")

        let inverse = try showStage(
            root: root,
            files: ["02": "pattern.png"],
            events: [(id: "02", layer: .base)],
            script: aliasScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(topPixel(inverse.bytes, width: 256, height: 256, x: 30, y: 6) == patternPixel(0, 0), "reversed coordinates are swapped, not rejected")
        require(topPixel(inverse.bytes, width: 256, height: 256, x: 32, y: 7) == patternPixel(2, 1), "the swapped rect keeps source order")

        let missing = try showStage(
            root: root,
            files: ["03": "pattern.png"],
            events: [(id: "03", layer: .base)],
            script: aliasScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(topPixel(missing.bytes, width: 256, height: 256, x: 126, y: 0) == (0, 0, 0, 255), "missing crop words stay empty instead of direct-fitting")

        let negative = try showStage(
            root: root,
            files: ["04": "pattern.png"],
            events: [(id: "04", layer: .base)],
            script: aliasScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(topPixel(negative.bytes, width: 256, height: 256, x: 40, y: 10) == (0, 0, 0, 255), "source outside the bitmap is not stretched back")
        require(topPixel(negative.bytes, width: 256, height: 256, x: 41, y: 11) == patternPixel(0, 0), "the clipped remainder keeps its pixel")
        require(topPixel(negative.bytes, width: 256, height: 256, x: 42, y: 12) == patternPixel(1, 1), "the second remaining pixel is not scaled")

        let huge = try showStage(
            root: root,
            files: ["06": "pattern.png"],
            events: [(id: "06", layer: .base)],
            script: aliasScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(topPixel(huge.bytes, width: 256, height: 256, x: 126, y: 0) == (0, 0, 0, 255), "a huge dx draws nothing")
        require(huge.state.imageDecodeCount == 1, "a huge dx still decodes the source once")

        for scale in [1, 2, 3] {
            let packed = try showStage(
                root: root,
                files: ["07": "pattern.png"],
                events: [(id: "07", layer: .base)],
                script: "#BGA07 07 0 0 4 4 -40 2\n#BMP07 pattern.png\n",
                origin: 331,
                canvas: CGSize(width: 587, height: 256),
                scale: scale,
                under: (1, 0, 1)
            )
            let canvas = CGSize(width: 587, height: 256)
            expect(packed.bytes, canvas: canvas, scale: scale, x: 291, y: 2, color: patternPixel(0, 0), label: "packed \(scale)x crosses the nominal column")
            expect(packed.bytes, canvas: canvas, scale: scale, x: 100, y: 20, color: (255, 0, 255, 255), label: "packed \(scale)x outside the column stays clear")
            expect(packed.bytes, canvas: canvas, scale: scale, x: 400, y: 20, color: (0, 0, 0, 255), label: "packed \(scale)x column is black")
            let separate = try showStage(
                root: root,
                files: ["08": "pattern.png"],
                events: [(id: "08", layer: .base)],
                script: "#BMP08 pattern.png\n",
                origin: 173,
                canvas: canvas,
                scale: scale,
                under: (1, 0, 1)
            )
            expect(separate.bytes, canvas: canvas, scale: scale, x: 299, y: 0, color: patternPixel(0, 0), label: "separate \(scale)x centers in the 173 column")
            expect(separate.bytes, canvas: canvas, scale: scale, x: 100, y: 40, color: (255, 0, 255, 255), label: "separate \(scale)x left of the column is clear")
            expect(separate.bytes, canvas: canvas, scale: scale, x: 200, y: 40, color: (0, 0, 0, 255), label: "separate \(scale)x column is black")
        }

        let edge = try showStage(
            root: root,
            files: ["09": "pattern.png"],
            events: [(id: "09", layer: .base)],
            script: "#BGA09 09 0 0 4 4 254 0\n#BMP09 pattern.png\n",
            origin: 331,
            canvas: CGSize(width: 587, height: 256),
            scale: 1
        )
        require(topPixel(edge.bytes, width: 587, height: 256, x: 585, y: 0) == patternPixel(0, 0), "stage clip keeps the first source column")
        require(topPixel(edge.bytes, width: 587, height: 256, x: 586, y: 0) == patternPixel(1, 0), "stage clip does not squeeze the hidden columns")

        let zeroScript = "#BMP00 blue.png\n#BMP01 red.png\n"
        let hiddenZero = try showStage(
            root: root,
            files: ["00": "blue.png", "01": "red.png"],
            events: [(id: "00", layer: .base), (id: "01", layer: .layer)],
            script: zeroScript,
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        require(hiddenZero.state.baseAssetID == nil && hiddenZero.state.imageDecodeCount == 1, "BMS base 00 is not drawn, decode=\(hiddenZero.state.imageDecodeCount)")
        require(topPixel(hiddenZero.bytes, width: 256, height: 256, x: 124, y: 0) != (0, 0, 220, 255), "base 00 does not paint BMP00")

        var poorChart = PreviewChartSnapshot()
        poorChart.bgaAssets = [
            PreviewBGAAsset(id: "00", fileName: "blue.png"),
            PreviewBGAAsset(id: "01", fileName: "red.png")
        ]
        poorChart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        let poorView = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let poorWindow = host(poorView)
        poorView.setDisplayMode(4)
        poorView.setChart(poorChart, chartDirectory: root, timing: steady, fromBeat: 0, documentData: Data(zeroScript.utf8))
        wait(poorView, timeout: 4) { $0.poorImageReady }
        let poorState = poorView.inspection()
        require(poorState.imageDecodeCount == 1 && poorState.baseAssetID == nil, "always poor with no event reads BMP00 only")
        poorWindow.displayIfNeeded()
        require(topPixel(render(poorView), width: 256, height: 256, x: 124, y: 0) == (0, 0, 220, 255), "BMP00 is the always-poor picture")

        var bmson = PreviewChartSnapshot()
        bmson.bgaAssets = [PreviewBGAAsset(id: "0", fileName: "red.png")]
        bmson.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "0", layer: .base)]
        let bmsonView = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        _ = host(bmsonView)
        bmsonView.setChart(bmson, chartDirectory: root, timing: steady, fromBeat: 0)
        wait(bmsonView, timeout: 4) { $0.baseImageReady && $0.baseAssetID == "0" }
        require(bmsonView.inspection().imageDecodeCount == 1, "a BMSON id 0 still decodes")

        let preload = try showStage(
            root: root,
            files: ["01": "pattern.png"],
            events: [(id: "01", layer: .base)],
            script: "#BMP01 pattern.png\n#BGA01 01 0 0 2 2 4 4\n",
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        let parsed = preload.state.scriptParseCount
        let decoded = preload.state.imageDecodeCount
        let resolved = preload.state.pathResolveCount
        for step in 0..<1000 {
            preload.view.setPlayback(beat: Double(step) / 1000, elapsedSeconds: Double(step) / 1000, isPlaying: true)
        }
        let after = preload.view.inspection()
        require(after.scriptParseCount == parsed && after.imageDecodeCount == decoded && after.pathResolveCount == resolved, "ticks do not parse, decode, or resolve again")
        require(after.eventIndexBuildCount == 1, "ticks do not rebuild the index")

        let off = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        off.setDisplayMode(0)
        var offChart = PreviewChartSnapshot()
        offChart.bgaAssets = [
            PreviewBGAAsset(id: "01", fileName: "pattern.png"),
            PreviewBGAAsset(id: "02", fileName: "red.png"),
            PreviewBGAAsset(id: "03", fileName: "blue.png"),
            PreviewBGAAsset(id: "04", fileName: "clip.m4v")
        ]
        offChart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "01", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "02", layer: .layer),
            PreviewBGAEvent(beat: 0, assetID: "03", layer: .poor),
            PreviewBGAEvent(beat: 1, assetID: "04", layer: .base)
        ]
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("clip.m4v"))
        off.setChart(offChart, chartDirectory: root, timing: steady, fromBeat: 0, documentData: Data("#BMP01 pattern.png\n#BGA01 01 0 0 1 1 0 0\n".utf8))
        off.setPlayback(beat: 1, elapsedSeconds: 0.2, isPlaying: true)
        let offState = off.inspection()
        require(offState.scriptParseCount == 1 && offState.pathResolveCount == 0 && offState.imageDecodeCount == 0 && offState.videoOpenCount == 0, "off still does no file work, \(offState.pathResolveCount)/\(offState.imageDecodeCount)/\(offState.videoOpenCount)")
        _ = poorWindow
    }

    @MainActor
    private static func testPlaybackRateTracksWallClock() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("clip.m4v")
        try writeClip(videoURL, seconds: 16)
        let asset = AVURLAsset(url: videoURL)
        require(!awaitTracks(asset).isEmpty, "the rate clip has an audio track")
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [
            PreviewBGAAsset(id: "V", fileName: "clip.m4v"),
            PreviewBGAAsset(id: "W", fileName: "clip.m4v")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "V", layer: .base),
            PreviewBGAEvent(beat: 4, assetID: "W", layer: .base)
        ]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        let window = host(view)
        var keptRate = 1.0
        for round in 1...2 {
            if round == 1 {
                require(view.inspection().requestedPlaybackRate == 1, "unset rate stays 1")
                let before = view.inspection().requestedPlaybackRate
                view.setPlaybackRate(.nan)
                view.setPlaybackRate(.infinity)
                view.setPlaybackRate(-1)
                view.setPlaybackRate(0)
                view.setPlaybackRate(0.24)
                view.setPlaybackRate(4.01)
                require(view.inspection().requestedPlaybackRate == before, "rates outside 0.25...4 are ignored")
                view.setPlaybackRate(0.25)
                view.setPlaybackRate(4)
                require(view.inspection().requestedPlaybackRate == 4, "0.25 and 4 are stored")
                view.setPlaybackRate(1)
            } else {
                require(abs(view.inspection().requestedPlaybackRate - keptRate) < 0.001, "round 2 starts from the previous rate")
            }
            let parsed = view.inspection().scriptParseCount
            let indexed = view.inspection().eventIndexBuildCount
            view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
            require(abs(view.inspection().requestedPlaybackRate - (round == 1 ? 1 : keptRate)) < 0.001, "setChart keeps the requested rate")
            require(view.inspection().scriptParseCount == parsed && view.inspection().eventIndexBuildCount == indexed + 1, "setChart still parses nothing without document data and builds the index once")
            measureRate(view, round: round, rate: 1, beat: 0, elapsed: 0.4)
            measureRate(view, round: round, rate: 2, beat: 0, elapsed: 1.2)
            measureRate(view, round: round, rate: 0.5, beat: 0, elapsed: 2.2)
            let fast = prime(view, beat: 0, elapsed: 3.0, rate: 4, requireRate: false)
            if fast != nil {
                let sample = sampleClock(view, round: round, label: "4x", seconds: 0.45)
                require(sample.ratio >= 2.6 && sample.ratio <= 5.2, "4x wall clock moved the media clock, \(sample.line)")
                let extra = trackSeeks(view, beat: 0, rate: 4, seconds: 0.8)
                require(extra <= 1, "4x tracking seeks \(extra) times instead of every 0.35s")
                print(String(format: "UG3-clock round=%d 4x-track extraSeeks=%d", round, extra))
            }
            let frozenAt = view.inspection().currentVideoSeconds ?? 3
            view.setPlayback(beat: 0, elapsedSeconds: frozenAt, isPlaying: false)
            view.setPlaybackRate(2)
            let paused = Date()
            while Date().timeIntervalSince(paused) < 0.4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            let held = view.inspection()
            require(held.videoRate == 0, "paused player rate is 0, \(held.videoRate ?? -1)")
            require(abs(held.requestedPlaybackRate - 2) < 0.001, "pause keeps the requested rate")
            require(abs((held.currentVideoSeconds ?? -1) - frozenAt) < 0.08, "paused media time stays put, from \(frozenAt) to \(held.currentVideoSeconds ?? -1)")
            measureRate(view, round: round, rate: 2, beat: 0, elapsed: min(frozenAt + 0.2, 8))
            let jump: Double = 5
            let opens = view.inspection().videoOpenCount
            view.setPlayback(beat: 0, elapsedSeconds: jump, isPlaying: true)
            view.setDisplayMode(0)
            let quiet = Date()
            while Date().timeIntervalSince(quiet) < 0.4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            var state = view.inspection()
            require(!state.videoAttached && !state.videoItemKept, "a stale seek callback must not keep or restart the player")
            require(state.videoOpenCount == opens, "off during seek does not open another item, open=\(state.videoOpenCount)")
            require(abs(state.requestedPlaybackRate - 2) < 0.001, "off keeps the requested rate")
            view.setDisplayMode(3)
            pump(view, beat: 0, elapsed: jump, playing: true, timeout: 6) {
                $0.videoAttached && $0.videoMuted && abs(($0.currentVideoSeconds ?? -1) - jump) < 0.4
                    && abs(Double($0.videoRate ?? 0) - 2) < 0.25
            }
            state = view.inspection()
            require(abs((state.expectedVideoSeconds ?? -1) - jump) < 0.000001, "re-enable uses the current chart second")
            require(abs((state.currentVideoSeconds ?? -1) - jump) < 0.4, "re-enable does not restart at zero, current=\(state.currentVideoSeconds ?? -1)")
            require(state.enabledAudioTrackCount == 0 && state.videoAudioDisabled, "rate and reopen leave audio disabled, enabled=\(state.enabledAudioTrackCount)")
            pump(view, beat: 4, elapsed: 2, playing: true, timeout: 6) {
                $0.baseAssetID == "W" && $0.videoMuted && abs(($0.currentVideoSeconds ?? -1) - 0) < 0.45
                    && abs(Double($0.videoRate ?? 0) - 2) < 0.25
            }
            state = view.inspection()
            require(abs(state.requestedPlaybackRate - 2) < 0.001, "event switch keeps the rate")
            require(state.enabledAudioTrackCount == 0 && state.videoMuted, "event switch stays silent")
            require(state.eventIndexBuildCount == indexed + 1, "rate changes do not rebuild the index")
            keptRate = state.requestedPlaybackRate
        }
        try checkLayersStaySilent(root: root, view: view)
        _ = window
    }

    @MainActor
    private static func checkLayersStaySilent(root: URL, view: PreviewBGAView) throws {
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [
            PreviewBGAAsset(id: "V", fileName: "clip.m4v"),
            PreviewBGAAsset(id: "L", fileName: "clip.m4v"),
            PreviewBGAAsset(id: "P", fileName: "clip.m4v")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "V", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "L", layer: .layer),
            PreviewBGAEvent(beat: 0, assetID: "P", layer: .poor)
        ]
        view.setDisplayMode(3)
        view.setPlaybackRate(2)
        let openedBefore = view.inspection().videoOpenCount
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
        pump(view, beat: 0, elapsed: 0.3, playing: true, timeout: 6) {
            $0.videoRates.count == 2 && $0.videoRates.allSatisfy { abs(Double($0) - 2) < 0.25 }
                && $0.videoMuted && $0.videoAudioDisabled && $0.enabledAudioTrackCount == 0
                && $0.videoAudioTrackCount > 0
        }
        var state = view.inspection()
        require(state.poorAssetID == "P" && state.videoOpenCount == openedBefore + 2, "normal opens base and layer only, open=\(state.videoOpenCount - openedBefore)")
        view.setDisplayMode(4)
        pump(view, beat: 0, elapsed: 0.3, playing: true, timeout: 6) {
            $0.videoRates.count == 1 && abs(Double($0.videoRates[0]) - 2) < 0.25
                && $0.videoMuted && $0.enabledAudioTrackCount == 0 && $0.baseAssetID == nil
        }
        state = view.inspection()
        require(state.videoAttached && state.videoAudioTrackCount > 0 && state.enabledAudioTrackCount == 0, "always poor plays the muted poor clip")
        let resolved = state.pathResolveCount
        let opened = state.videoOpenCount
        view.setDisplayMode(0)
        view.setPlaybackRate(4)
        view.setPlayback(beat: 0, elapsedSeconds: 0.3, isPlaying: true)
        state = view.inspection()
        require(!state.videoAttached && state.pathResolveCount == resolved && state.videoOpenCount == opened, "off still does no path or player work when the rate changes")
        require(abs(state.requestedPlaybackRate - 4) < 0.001, "off keeps a later rate request")
    }

    @MainActor
    private static func measureRate(
        _ view: PreviewBGAView,
        round: Int,
        rate: Double,
        beat: Double,
        elapsed: Double
    ) {
        _ = prime(view, beat: beat, elapsed: elapsed, rate: rate, requireRate: true)
        let sample = sampleClock(view, round: round, label: "\(rate)x", seconds: 0.6)
        let low: Double
        let high: Double
        if rate == 0.5 {
            low = 0.28
            high = 0.72
        } else if rate == 2 {
            low = 1.45
            high = 2.75
        } else {
            low = 0.65
            high = 1.40
        }
        require(sample.ratio >= low && sample.ratio <= high, "\(rate)x media/wall \(sample.ratio) outside \(low)...\(high), \(sample.line)")
        if rate >= 2 {
            let extra = trackSeeks(view, beat: beat, rate: rate, seconds: 0.8)
            require(extra <= 1, "\(rate)x tracking seeks \(extra) times")
            print(String(format: "UG3-clock round=%d %@-track extraSeeks=%d", round, "\(rate)x", extra))
        }
    }

    @MainActor
    private static func prime(
        _ view: PreviewBGAView,
        beat: Double,
        elapsed: Double,
        rate: Double,
        requireRate: Bool
    ) -> PreviewBGAInspection? {
        view.setPlaybackRate(rate)
        let end = Date().addingTimeInterval(6)
        var last = view.inspection()
        while Date() < end {
            view.setPlayback(beat: beat, elapsedSeconds: elapsed, isPlaying: true)
            last = view.inspection()
            let actual = last.currentVideoSeconds ?? -1
            let playerRate = Double(last.videoRate ?? 0)
            if last.videoSeekCount >= 1, abs(actual - elapsed) < 0.35, abs(playerRate - rate) < 0.25 {
                return last
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let playerRate = Double(last.videoRate ?? -1)
        if !requireRate, playerRate < 3 {
            let line = String(format: "4x unsupported playerRate=%.3f current=%.3f seeks=%d", playerRate, last.currentVideoSeconds ?? -1, last.videoSeekCount)
            print("UG3-clock \(line)")
            fflush(stdout)
            return nil
        }
        fail("prime \(rate) timed out playerRate=\(playerRate) current=\(last.currentVideoSeconds ?? -1) expected=\(elapsed) seeks=\(last.videoSeekCount) error=\(last.videoItemError ?? "")")
    }

    private struct ClockSample {
        var wall: Double
        var delta: Double
        var ratio: Double
        var line: String
    }

    @MainActor
    private static func sampleClock(
        _ view: PreviewBGAView,
        round: Int,
        label: String,
        seconds: Double
    ) -> ClockSample {
        guard let start = view.inspection().currentVideoSeconds else { fail("\(label) has no media time") }
        let seeks = view.inspection().videoSeekCount
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let wall = Date().timeIntervalSince(started)
        guard let end = view.inspection().currentVideoSeconds else { fail("\(label) lost media time") }
        let delta = end - start
        let ratio = wall > 0 ? delta / wall : 0
        let line = String(
            format: "round=%d %@ wall=%.3f delta=%.3f ratio=%.3f playerRate=%.3f extraSeeks=%d",
            round, label, wall, delta, ratio, view.inspection().videoRate ?? -1, view.inspection().videoSeekCount - seeks
        )
        print("UG3-clock \(line)")
        fflush(stdout)
        require(view.inspection().videoSeekCount == seeks, "free-run \(label) sought again, \(line)")
        return ClockSample(wall: wall, delta: delta, ratio: ratio, line: line)
    }

    @MainActor
    private static func trackSeeks(
        _ view: PreviewBGAView,
        beat: Double,
        rate: Double,
        seconds: Double
    ) -> Int {
        let caught = view.inspection().currentVideoSeconds ?? 0
        view.setPlayback(beat: beat, elapsedSeconds: caught, isPlaying: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let baseline = view.inspection().videoSeekCount
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            let wall = Date().timeIntervalSince(started)
            view.setPlayback(beat: beat, elapsedSeconds: caught + wall * rate, isPlaying: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return view.inspection().videoSeekCount - baseline
    }

    @MainActor
    private static func testRateStepReachesThePlayer() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("clip.m4v")
        try writeClip(videoURL, seconds: 22)
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [
            PreviewBGAAsset(id: "V", fileName: "clip.m4v"),
            PreviewBGAAsset(id: "W", fileName: "clip.m4v")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "V", layer: .base),
            PreviewBGAEvent(beat: 4, assetID: "W", layer: .base)
        ]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        let window = host(view)
        for round in 1...2 {
            view.setDisplayMode(3)
            view.setPlaybackRate(1)
            view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0)
            waitUntilRate(view, rate: 1, beat: 0, elapsed: 0.3, timeout: 6)
            stepRate(view, to: 1.05, beat: 0)
            proveStable(view, round: round, rate: 1.05, seconds: 2)
            holdTicks(view, rate: 1.05, beat: 0)
            stepRate(view, to: 1.95, beat: 0)
            stepRate(view, to: 2, beat: 0)
            proveStable(view, round: round, rate: 2, seconds: 2)
            holdTicks(view, rate: 2, beat: 0)
            stepRate(view, to: 1.95, beat: 0)
            proveStable(view, round: round, rate: 1.95, seconds: 0.8)
            holdTicks(view, rate: 1.95, beat: 0)
            stepRate(view, to: 0.95, beat: 0)
            stepRate(view, to: 1, beat: 0)
            proveStable(view, round: round, rate: 1, seconds: 0.8)
            holdTicks(view, rate: 1, beat: 0)
            pauseThenResume(view, round: round, rate: 1.05, beat: 0)
            let opens = view.inspection().videoOpenCount
            let jumped = (view.inspection().currentVideoSeconds ?? 0) + 1.2
            view.setPlayback(beat: 0, elapsedSeconds: jumped, isPlaying: true)
            view.setDisplayMode(0)
            let quiet = Date()
            while Date().timeIntervalSince(quiet) < 0.4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            let state = view.inspection()
            require(!state.videoAttached && state.videoOpenCount == opens, "stale 1.05 callback must not reopen, open=\(state.videoOpenCount)")
            require(abs(state.requestedPlaybackRate - 1.05) < 0.000001, "off keeps 1.05")
            view.setDisplayMode(3)
            pump(view, beat: 0, elapsed: jumped, playing: true, timeout: 6) {
                abs(Double($0.videoRate ?? 0) - 1.05) < 0.01
                    && abs(($0.currentVideoSeconds ?? -1) - jumped) < 0.4
                    && $0.videoMuted && $0.enabledAudioTrackCount == 0
            }
            pump(view, beat: 4, elapsed: 2, playing: true, timeout: 6) {
                $0.baseAssetID == "W" && abs(Double($0.videoRate ?? 0) - 1.05) < 0.01
                    && abs(($0.currentVideoSeconds ?? -1) - 0) < 0.45
                    && $0.videoMuted && $0.enabledAudioTrackCount == 0
            }
        }
        _ = window
    }

    @MainActor
    private static func waitUntilRate(
        _ view: PreviewBGAView,
        rate: Double,
        beat: Double,
        elapsed: Double,
        timeout: Double
    ) {
        let end = Date().addingTimeInterval(timeout)
        var last = view.inspection()
        while Date() < end {
            view.setPlayback(beat: beat, elapsedSeconds: elapsed, isPlaying: true)
            last = view.inspection()
            let playerRate = Double(last.videoRate ?? -1)
            if last.videoSeekCount >= 1, abs((last.currentVideoSeconds ?? -1) - elapsed) < 0.35,
               abs(playerRate - rate) < 0.01 {
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        fail("wait \(rate) timed out playerRate=\(last.videoRate ?? -1) current=\(last.currentVideoSeconds ?? -1)")
    }

    @MainActor
    private static func catchUp(_ view: PreviewBGAView, beat: Double) -> Int {
        let now = view.inspection().currentVideoSeconds ?? 0
        let seeks = view.inspection().videoSeekCount
        view.setPlayback(beat: beat, elapsedSeconds: now, isPlaying: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return view.inspection().videoSeekCount - seeks
    }

    @MainActor
    private static func stepRate(_ view: PreviewBGAView, to rate: Double, beat: Double) {
        let corrective = catchUp(view, beat: beat)
        let before = view.inspection()
        let origin = before.currentVideoSeconds ?? 0
        view.setPlaybackRate(rate)
        let started = Date()
        let deadline = started.addingTimeInterval(4)
        var matched = false
        while Date() < deadline {
            let wall = Date().timeIntervalSince(started)
            view.setPlayback(beat: beat, elapsedSeconds: origin + wall * rate, isPlaying: true)
            let state = view.inspection()
            let playerRate = Double(state.videoRate ?? -1)
            if abs(state.requestedPlaybackRate - rate) < 0.000001, abs(playerRate - rate) < 0.01 {
                matched = true
                break
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let after = view.inspection()
        let line = String(
            format: "step %.2f playerRate=%.5f transport+%d seek+%d corrective=%d",
            rate, after.videoRate ?? -1, after.videoTransportCount - before.videoTransportCount,
            after.videoSeekCount - before.videoSeekCount, corrective
        )
        print("UG4-step \(line)")
        fflush(stdout)
        require(matched, "timed out \(line)")
        require(after.videoTransportCount == before.videoTransportCount + 1, "expected one transport command, \(line)")
        require(after.videoOpenCount == before.videoOpenCount && after.imageDecodeCount == before.imageDecodeCount, "step touched io, \(line)")
        require(after.videoSeekCount == before.videoSeekCount, "step sought, \(line)")
    }

    @MainActor
    private static func proveStable(_ view: PreviewBGAView, round: Int, rate: Double, seconds: Double) {
        guard let start = view.inspection().currentVideoSeconds else { fail("no media time at \(rate)") }
        let seeks = view.inspection().videoSeekCount
        let started = Date()
        while Date().timeIntervalSince(started) < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let wall = Date().timeIntervalSince(started)
        guard let end = view.inspection().currentVideoSeconds else { fail("lost media time at \(rate)") }
        let ratio = wall > 0 ? (end - start) / wall : 0
        let playerRate = Double(view.inspection().videoRate ?? -1)
        let line = String(
            format: "round=%d rate=%.2f wall=%.3f delta=%.3f ratio=%.5f playerRate=%.5f extraSeeks=%d",
            round, rate, wall, end - start, ratio, playerRate, view.inspection().videoSeekCount - seeks
        )
        print("UG4-clock \(line)")
        fflush(stdout)
        require(view.inspection().videoSeekCount == seeks, "stable segment sought, \(line)")
        require(abs(playerRate - rate) < 0.01, "player rate left the request, \(line)")
        require(abs(ratio - rate) <= 0.02, "raw ratio misses \(rate) by more than 0.02, \(line)")
    }

    @MainActor
    private static func holdTicks(_ view: PreviewBGAView, rate: Double, beat: Double) {
        _ = catchUp(view, beat: beat)
        let before = view.inspection()
        let origin = before.currentVideoSeconds ?? 0
        let started = Date()
        for _ in 0..<500 {
            let wall = Date().timeIntervalSince(started)
            view.setPlayback(beat: beat, elapsedSeconds: origin + wall * rate, isPlaying: true)
        }
        let after = view.inspection()
        require(after.videoTransportCount == before.videoTransportCount, "500 ticks at \(rate) added transport \(after.videoTransportCount - before.videoTransportCount)")
        require(after.videoOpenCount == before.videoOpenCount, "500 ticks at \(rate) opened a player")
        require(after.imageDecodeCount == before.imageDecodeCount, "500 ticks at \(rate) decoded")
        require(after.videoSeekCount == before.videoSeekCount, "500 ticks at \(rate) sought \(after.videoSeekCount - before.videoSeekCount)")
    }

    @MainActor
    private static func pauseThenResume(_ view: PreviewBGAView, round: Int, rate: Double, beat: Double) {
        _ = catchUp(view, beat: beat)
        let frozen = view.inspection().currentVideoSeconds ?? 0
        let before = view.inspection().videoTransportCount
        view.setPlayback(beat: beat, elapsedSeconds: frozen, isPlaying: false)
        view.setPlaybackRate(rate)
        let paused = Date()
        while Date().timeIntervalSince(paused) < 0.4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let held = view.inspection()
        require(held.videoRate == 0, "pause rate is \(held.videoRate ?? -1)")
        require(abs(held.requestedPlaybackRate - rate) < 0.000001, "pause stored \(held.requestedPlaybackRate)")
        require(abs((held.currentVideoSeconds ?? -1) - frozen) < 0.08, "pause moved media from \(frozen) to \(held.currentVideoSeconds ?? -1)")
        require(held.videoTransportCount == before + 1, "pause issued \(held.videoTransportCount - before) commands")
        let origin = held.currentVideoSeconds ?? frozen
        let started = Date()
        let deadline = started.addingTimeInterval(4)
        var matched = false
        while Date() < deadline {
            let wall = Date().timeIntervalSince(started)
            view.setPlayback(beat: beat, elapsedSeconds: origin + wall * rate, isPlaying: true)
            let playerRate = Double(view.inspection().videoRate ?? -1)
            if abs(playerRate - rate) < 0.01 {
                matched = true
                break
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        require(matched, "resume \(rate) timed out at \(view.inspection().videoRate ?? -1)")
        require(view.inspection().videoTransportCount == before + 2, "resume added extra transport \(view.inspection().videoTransportCount - before)")
        proveStable(view, round: round, rate: rate, seconds: 0.8)
    }

    @MainActor
    private static func testVideoDisplayScaleAndCrop() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let wide = root.appendingPathComponent("wide.m4v")
        let small = root.appendingPathComponent("small.m4v")
        let odd = root.appendingPathComponent("odd.m4v")
        try writeClip(wide, seconds: 0.4, width: 640, height: 360, paint: quadrantPaint(width: 640, height: 360))
        try writeClip(small, seconds: 0.4, width: 128, height: 64)
        try writeClip(odd, seconds: 0.4, width: 641, height: 257)
        let quadrants = try quadrantSamples(wide)
        print("UG5-file quadrants \(quadrants)")
        fflush(stdout)
        require(quadrants.contains("tl=red") && quadrants.contains("tr=green") && quadrants.contains("bl=blue") && quadrants.contains("br=white"), "the source file keeps four quadrant colors, \(quadrants)")
        for round in 1...2 {
            try expectDirect(root: root, file: "wide.m4v", round: round, origin: 0, canvas: CGSize(width: 256, height: 256), scale: 1, host: CGRect(x: 0, y: 112, width: 256, height: 144), playerFillsHost: true)
            try expectDirect(root: root, file: "small.m4v", round: round, origin: 0, canvas: CGSize(width: 256, height: 256), scale: 1, host: CGRect(x: 0, y: 128, width: 256, height: 128), playerFillsHost: true)
            let oddHeight = 103.0 * 257.0 / 258.0
            try expectDirect(root: root, file: "odd.m4v", round: round, origin: 0, canvas: CGSize(width: 256, height: 256), scale: 1, host: CGRect(x: 0, y: 256 - oddHeight, width: 256, height: oddHeight), playerFillsHost: true)
            try expectAlias(root: root, round: round)
            try expectStageEdges(root: root, round: round)
            let steadyVideo = try openVideo(root: root, file: "wide.m4v", script: "#BMP01 wide.m4v\n", origin: 0, canvas: CGSize(width: 256, height: 256), scale: 1)
            let layout = steadyVideo.view.inspection().videoLayoutCount
            let opened = steadyVideo.view.inspection().videoOpenCount
            let resolved = steadyVideo.view.inspection().pathResolveCount
            let decoded = steadyVideo.view.inspection().imageDecodeCount
            let sought = steadyVideo.view.inspection().videoSeekCount
            let playerID = ObjectIdentifier(steadyVideo.player)
            let hostID = ObjectIdentifier(steadyVideo.host)
            let hostFrame = steadyVideo.host.frame
            let playerFrame = steadyVideo.player.frame
            let started = Date()
            for _ in 0..<500 {
                let wall = Date().timeIntervalSince(started)
                steadyVideo.view.setPlayback(beat: 0, elapsedSeconds: wall, isPlaying: true)
            }
            let after = steadyVideo.view.inspection()
            require(after.videoLayoutCount == layout && after.videoOpenCount == opened && after.pathResolveCount == resolved && after.imageDecodeCount == decoded && after.videoSeekCount == sought, "500 ticks added layout/io, layout=\(after.videoLayoutCount - layout) open=\(after.videoOpenCount - opened) seek=\(after.videoSeekCount - sought)")
            require(ObjectIdentifier(steadyVideo.player) == playerID && ObjectIdentifier(steadyVideo.host) == hostID, "500 ticks replaced the video layers")
            require(steadyVideo.host.frame == hostFrame && steadyVideo.player.frame == playerFrame, "500 ticks moved the video layout")
            _ = steadyVideo.window
        }
        let cropped = try openVideo(root: root, file: "wide.m4v", script: "#BMP01 wide.m4v\n#BGA01 01 0 0 128 72 0 0\n", origin: 0, canvas: CGSize(width: 256, height: 256), scale: 1)
        cropped.window.displayIfNeeded()
        let rendered = render(cropped.view)
        let sample = topPixel(rendered, width: 256, height: 256, x: 20, y: 10)
        if sample.0 < 8, sample.1 < 8, sample.2 < 8 {
            print("UG5-pixel layer.render has no AVPlayerLayer samples at the crop, \(sample)")
            fflush(stdout)
        } else {
            require(sample.0 > 200 && sample.1 < 40 && sample.2 < 40, "cropped quadrant is not the top-left red, \(sample)")
        }
        _ = cropped.window
    }

    private struct VideoShot {
        var view: PreviewBGAView
        var window: NSWindow
        var player: AVPlayerLayer
        var host: CALayer
    }

    @MainActor
    private static func openVideo(
        root: URL,
        file: String,
        script: String,
        origin: Double,
        canvas: CGSize,
        scale: Int
    ) throws -> VideoShot {
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [PreviewBGAAsset(id: "01", fileName: file)]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: canvas.width * CGFloat(scale), height: canvas.height * CGFloat(scale)))
        let window = host(view)
        view.setStageLayout(bgaOriginX: origin, nativeCanvasSize: canvas)
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0, documentData: Data(script.utf8))
        let end = Date().addingTimeInterval(6)
        var shot: VideoShot?
        while Date() < end {
            view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
            view.layoutSubtreeIfNeeded()
            flattenScale(view.layer)
            if let found = visiblePlayer(in: view.layer), found.player.superlayer?.isHidden == false {
                shot = VideoShot(view: view, window: window, player: found.player, host: found.host)
                if found.player.videoRect.width > 1 { break }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard let shot else { fail("video layer did not appear for \(file)") }
        require(shot.host.masksToBounds, "the crop parent clips")
        require(shot.player.contentsRect == CGRect(x: 0, y: 0, width: 1, height: 1), "video crop is not an unproven contentsRect")
        require(CATransform3DIsIdentity(shot.player.transform), "video mapping keeps an identity transform")
        require(shot.player.videoRect.width > 1 && shot.player.videoRect.height > 1, "videoRect stayed empty, \(shot.player.videoRect)")
        near(shot.player.videoRect, CGRect(origin: .zero, size: shot.player.bounds.size), tolerance: 2, label: "videoRect fills the player layer")
        return shot
    }

    @MainActor
    private static func expectDirect(
        root: URL,
        file: String,
        round: Int,
        origin: Double,
        canvas: CGSize,
        scale: Int,
        host: CGRect,
        playerFillsHost: Bool
    ) throws {
        let shot = try openVideo(root: root, file: file, script: "#BMP01 \(file)\n", origin: origin, canvas: canvas, scale: scale)
        let presented = shot.player.player?.currentItem?.presentationSize ?? .zero
        print("UG5-present round=\(round) \(file) presentation=\(presented.width)x\(presented.height) host=\(shot.host.frame)")
        fflush(stdout)
        if file == "odd.m4v" {
            require(presented == CGSize(width: 641, height: 257), "odd clip presentation is \(presented)")
        }
        let scaled = host.applying(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        near(shot.host.frame, scaled, tolerance: 0.6, label: "round \(round) \(file) direct host \(shot.host.frame) vs \(scaled)")
        if playerFillsHost {
            near(shot.player.frame, CGRect(origin: .zero, size: shot.host.bounds.size), tolerance: 0.6, label: "round \(round) \(file) player fills the top-aligned host")
        }
        _ = shot.window
    }

    @MainActor
    private static func expectAlias(root: URL, round: Int) throws {
        let shot = try openVideo(
            root: root,
            file: "wide.m4v",
            script: "#BMP01 wide.m4v\n#BGA01 01 1 1 2 2 10 4\n",
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        near(shot.host.frame, CGRect(x: 10, y: 251, width: 1, height: 1), tolerance: 0.05, label: "round \(round) alias host")
        near(shot.player.frame, CGRect(x: -2.0 / 3.0, y: -355.0 / 3.0, width: 640.0 / 3.0, height: 120), tolerance: 0.05, label: "round \(round) alias player maps 2...5 not 2...4")
        let negative = try openVideo(
            root: root,
            file: "wide.m4v",
            script: "#BMP01 wide.m4v\n#BGA01 01 -1 1 2 2 10 4\n",
            origin: 0,
            canvas: CGSize(width: 256, height: 256),
            scale: 1
        )
        let keptWidth = 3.0 * 5.0 / 7.0
        let shiftedX = 10.0 + 3.0 * 2.0 / 7.0
        near(negative.host.frame, CGRect(x: shiftedX, y: 251, width: keptWidth, height: 1), tolerance: 0.05, label: "round \(round) negative source shrinks dest")
        near(
            negative.player.frame,
            CGRect(x: 0, y: -355.0 / 3.0, width: keptWidth * 640.0 / 5.0, height: 120),
            tolerance: 0.08,
            label: "round \(round) negative source player"
        )
        _ = shot.window
        _ = negative.window
    }

    @MainActor
    private static func expectStageEdges(root: URL, round: Int) throws {
        for scale in [1, 2, 3] {
            let packed = try openVideo(
                root: root,
                file: "wide.m4v",
                script: "#BMP01 wide.m4v\n#BGA01 01 0 0 20 8 250 2\n",
                origin: 331,
                canvas: CGSize(width: 587, height: 256),
                scale: scale
            )
            let host = CGRect(x: 581, y: 246, width: 6, height: 8).applying(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
            near(packed.host.frame, host, tolerance: 0.6, label: "round \(round) packed \(scale)x stage edge")
            require(packed.player.frame.width > packed.host.bounds.width * 2, "round \(round) packed edge does not stretch the remaining source")
            let separate = try openVideo(
                root: root,
                file: "small.m4v",
                script: "#BMP01 small.m4v\n",
                origin: 173,
                canvas: CGSize(width: 587, height: 256),
                scale: scale
            )
            let direct = CGRect(x: 173, y: 128, width: 256, height: 128).applying(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
            near(separate.host.frame, direct, tolerance: 0.6, label: "round \(round) separate \(scale)x enlarged column")
            near(separate.player.frame, CGRect(origin: .zero, size: separate.host.bounds.size), tolerance: 0.6, label: "round \(round) separate player has no vertical center")
            _ = packed.window
            _ = separate.window
        }
    }

    private static func quadrantPaint(width: Int, height: Int) -> @Sendable (Int, Int, Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let midX = width / 2
        let midY = height / 2
        return { x, y, _ in
            let left = x < midX
            let top = y < midY
            if left && top { return (255, 0, 0, 255) }
            if !left && top { return (0, 255, 0, 255) }
            if left && !top { return (0, 0, 255, 255) }
            return (255, 255, 255, 255)
        }
    }

    @MainActor
    private static func quadrantSamples(_ url: URL) throws -> String {
        let box = ImageBox()
        let source = url
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                let result = try await generator.image(at: .zero)
                box.image = result.image
            } catch {
                box.message = error.localizedDescription
            }
            box.finished = true
        }
        let end = Date().addingTimeInterval(6)
        while !box.finished && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard let image = box.image else { fail(box.message ?? "quadrant frame was not generated") }
        func pixel(_ x: Int, _ y: Int) -> String {
            guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return "none" }
            let info = image.bitmapInfo.rawValue
            let alpha = info & CGBitmapInfo.alphaInfoMask.rawValue
            let order = info & CGBitmapInfo.byteOrderMask.rawValue
            let row = image.bytesPerRow
            let index = y * row + x * 4
            guard index + 3 < CFDataGetLength(data) else { return "oob" }
            let raw = (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
            let alphaFirst = alpha == CGImageAlphaInfo.premultipliedFirst.rawValue || alpha == CGImageAlphaInfo.first.rawValue || alpha == CGImageAlphaInfo.noneSkipFirst.rawValue
            let little = order == CGBitmapInfo.byteOrder32Little.rawValue
            let channels: (UInt8, UInt8, UInt8)
            if alphaFirst && little {
                channels = (raw.2, raw.1, raw.0)
            } else if alphaFirst {
                channels = (raw.1, raw.2, raw.3)
            } else {
                channels = (raw.0, raw.1, raw.2)
            }
            return "\(Self.colorName(channels)):\(channels.0),\(channels.1),\(channels.2)"
        }
        let midX = image.width / 2
        let midY = image.height / 2
        return "\(image.width)x\(image.height) tl=\(pixel(midX / 2, midY / 2)) tr=\(pixel(midX + midX / 2, midY / 2)) bl=\(pixel(midX / 2, midY + midY / 2)) br=\(pixel(midX + midX / 2, midY + midY / 2))"
    }

    private static func colorName(_ channels: (UInt8, UInt8, UInt8)) -> String {
        let red = Int(channels.0)
        let green = Int(channels.1)
        let blue = Int(channels.2)
        if red > 200, green < 50, blue < 50 { return "red" }
        if green > 200, red < 50, blue < 50 { return "green" }
        if blue > 200, red < 50, green < 50 { return "blue" }
        if red > 200, green > 200, blue > 200 { return "white" }
        return "other"
    }

    private static func visiblePlayer(in layer: CALayer?) -> (player: AVPlayerLayer, host: CALayer)? {
        guard let layer else { return nil }
        if let player = layer as? AVPlayerLayer, let host = player.superlayer {
            return (player, host)
        }
        for child in layer.sublayers ?? [] {
            if let found = visiblePlayer(in: child) { return found }
        }
        return nil
    }

    private static func near(_ actual: CGRect, _ expected: CGRect, tolerance: CGFloat, label: String) {
        let mismatch = abs(actual.origin.x - expected.origin.x) > tolerance
            || abs(actual.origin.y - expected.origin.y) > tolerance
            || abs(actual.size.width - expected.size.width) > tolerance
            || abs(actual.size.height - expected.size.height) > tolerance
        require(!mismatch, "\(label) actual \(actual)")
    }

    private struct StageShot {
        var view: PreviewBGAView
        var bytes: [UInt8]
        var state: PreviewBGAInspection
    }

    @MainActor
    private static func showStage(
        root: URL,
        files: [String: String],
        events: [(id: String, layer: PreviewBGALayer)],
        script: String?,
        origin: Double,
        canvas: CGSize,
        scale: Int,
        under: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
    ) throws -> StageShot {
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = files.map { PreviewBGAAsset(id: $0.key, fileName: $0.value) }
        chart.bgaEvents = events.map { PreviewBGAEvent(beat: 0, assetID: $0.id, layer: $0.layer) }
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: canvas.width * CGFloat(scale), height: canvas.height * CGFloat(scale)))
        let window = host(view)
        view.setStageLayout(bgaOriginX: origin, nativeCanvasSize: canvas)
        view.setChart(chart, chartDirectory: root, timing: steady, fromBeat: 0, documentData: script.map { Data($0.utf8) })
        let end = Date().addingTimeInterval(4)
        while Date() < end {
            let state = view.inspection()
            if state.baseImageReady || state.layerImageReady || state.poorImageReady {
                break
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        let bytes = render(view, under: under)
        return StageShot(view: view, bytes: bytes, state: view.inspection())
    }

    private static func expect(
        _ bytes: [UInt8],
        canvas: CGSize,
        scale: Int,
        x: Int,
        y: Int,
        color: (UInt8, UInt8, UInt8, UInt8),
        label: String
    ) {
        let width = Int(canvas.width) * scale
        let height = Int(canvas.height) * scale
        for dy in 0..<scale {
            for dx in 0..<scale {
                let pixel = topPixel(bytes, width: width, height: height, x: x * scale + dx, y: y * scale + dy)
                require(pixel == color, "\(label) at \(x),\(y) block \(dx),\(dy) is \(pixel)")
            }
        }
    }

    private static func patternPixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let rows: [[(UInt8, UInt8, UInt8, UInt8)]] = [
            [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (255, 255, 0, 255)],
            [(255, 0, 255, 255), (0, 255, 255, 255), (255, 255, 255, 255), (10, 20, 30, 255)],
            [(1, 2, 3, 255), (4, 5, 6, 255), (7, 8, 9, 255), (11, 12, 13, 255)],
            [(20, 0, 0, 255), (0, 21, 0, 255), (0, 0, 22, 255), (30, 30, 30, 255)]
        ]
        return rows[y][x]
    }

    private static func writeWideMarkers(_ url: URL) throws {
        try writePNG(url, width: 512, height: 300) { x, y in
            if x == 0, y == 0 { return (255, 0, 0, 255) }
            if x == 128, y == 0 { return (0, 255, 0, 255) }
            if x == 383, y == 0 { return (0, 0, 255, 255) }
            if x == 128, y == 255 { return (255, 255, 0, 255) }
            if x == 128, y == 299 { return (255, 0, 255, 255) }
            return (2, 2, 2, 255)
        }
    }

    private static func layeredChart() -> PreviewChartSnapshot {
        var chart = PreviewChartSnapshot(title: "modes")
        chart.bgaAssets = [
            PreviewBGAAsset(id: "B", fileName: "base.png"),
            PreviewBGAAsset(id: "L", fileName: "layer.png"),
            PreviewBGAAsset(id: "P", fileName: "poor.png"),
            PreviewBGAAsset(id: "V", fileName: "clip.m4v")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "B", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "L", layer: .layer),
            PreviewBGAEvent(beat: 0, assetID: "P", layer: .poor),
            PreviewBGAEvent(beat: 4, assetID: "V", layer: .base)
        ]
        return chart
    }

    private static func flattenScale(_ layer: CALayer?) {
        guard let layer else { return }
        layer.contentsScale = 1
        layer.sublayers?.forEach { flattenScale($0) }
    }

    private static func topPixel(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        x: Int,
        y: Int
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        let row = y
        guard x >= 0, row >= 0, x < width, row < height else { return (0, 0, 0, 0) }
        let index = (row * width + x) * 4
        guard index + 3 < bytes.count else { return (0, 0, 0, 0) }
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    private static func centerPixel(_ bytes: [UInt8], width: Int, height: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return (0, 0, 0, 0) }
        let index = ((height / 2) * width + width / 2) * 4
        guard index + 3 < bytes.count else { return (0, 0, 0, 0) }
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    private static func sampleDecode(_ url: URL, blackKey: Bool, threshold: UInt8) throws -> (UInt8, UInt8, UInt8, UInt8) {
        guard let image = PreviewBGAImageLoader.decode(url: url, blackKey: blackKey, threshold: threshold).image else {
            fail("decode failed \(url.lastPathComponent)")
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: max(width * height * 4, 4))
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    private static var steady: PreviewAudioTiming {
        PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
    }

    @MainActor
    private static func imageChart(id: String, file: String) -> PreviewChartSnapshot {
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [PreviewBGAAsset(id: id, fileName: file)]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: id, layer: .base)]
        return chart
    }

    @MainActor
    private static func host(_ view: PreviewBGAView) -> NSWindow {
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame = window.contentView?.bounds ?? view.frame
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    private static func wait(
        _ view: PreviewBGAView,
        timeout: TimeInterval,
        _ ready: (PreviewBGAInspection) -> Bool
    ) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if ready(view.inspection()) { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        fail("timed out: \(view.inspection())")
    }

    @MainActor
    private static func pump(
        _ view: PreviewBGAView,
        beat: Double,
        elapsed: Double,
        playing: Bool,
        timeout: TimeInterval,
        _ ready: (PreviewBGAInspection) -> Bool
    ) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            view.setPlayback(beat: beat, elapsedSeconds: elapsed, isPlaying: playing)
            if ready(view.inspection()) { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        fail("timed out: \(view.inspection())")
    }

    @MainActor
    private static func render(
        _ view: PreviewBGAView,
        under: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
    ) -> [UInt8] {
        view.layoutSubtreeIfNeeded()
        flattenScale(view.layer)
        let width = max(Int(view.bounds.width.rounded()), 1)
        let height = max(Int(view.bounds.height.rounded()), 1)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return }
            context.setFillColor(CGColor(srgbRed: under.0, green: under.1, blue: under.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .none
            view.layer?.render(in: context)
        }
        return bytes
    }

    private static func pixelCounts(_ bytes: [UInt8]) -> PixelCounts {
        var counts = PixelCounts()
        var index = 0
        while index + 3 < bytes.count {
            let red = Double(bytes[index]) / 255
            let green = Double(bytes[index + 1]) / 255
            let blue = Double(bytes[index + 2]) / 255
            if red > 0.75, green < 0.28, blue < 0.28 {
                counts.red += 1
            } else if green > 0.45, red < 0.35, blue < 0.35 {
                counts.green += 1
            } else if blue > 0.75, red < 0.28, green < 0.28 {
                counts.blue += 1
            } else if red > 0.82, green > 0.82, blue > 0.82 {
                counts.white += 1
            } else if red > 0.65, green > 0.55, blue < 0.35 {
                counts.yellow += 1
            } else if red < 0.08, green < 0.08, blue < 0.08 {
                counts.black += 1
            } else {
                counts.other += 1
            }
            index += 4
        }
        return counts
    }

    private static func writePNG(_ url: URL, width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) throws {
        try writeBitmap(url, width: width, height: height, type: .png, fill: fill)
    }

    private static func writeBitmap(
        _ url: URL,
        width: Int,
        height: Int,
        type: UTType,
        fill: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
    ) throws {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = fill(x, y)
                let index = (y * width + x) * 4
                bytes[index] = pixel.0
                bytes[index + 1] = pixel.1
                bytes[index + 2] = pixel.2
                bytes[index + 3] = pixel.3
            }
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { fail("no provider") }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { fail("no image") }
        if type == .bmp {
            let rep = NSBitmapImageRep(cgImage: image)
            guard let encoded = rep.representation(using: .bmp, properties: [:]) else {
                fail("bmp encode failed")
            }
            try encoded.write(to: url)
            return
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            fail("destination \(type.identifier)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fail("finalize \(url.lastPathComponent)") }
    }

    private static func writeCounts(_ counts: PixelCounts, name: String, image: [UInt8]) throws {
        let directory = URL(fileURLWithPath: "/tmp/ibms-bga-f3", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = "red=\(counts.red) green=\(counts.green) blue=\(counts.blue) white=\(counts.white) yellow=\(counts.yellow) black=\(counts.black) other=\(counts.other)\n"
        try note.write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        _ = image
    }

    @MainActor
    private static func writeClip(
        _ url: URL,
        seconds: Double,
        width: Int = 64,
        height: Int = 48,
        paint: (@Sendable (Int, Int, Int) -> (UInt8, UInt8, UInt8, UInt8))? = nil
    ) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let codedWidth = width % 2 == 0 ? width : width + 1
        let codedHeight = height % 2 == 0 ? height : height + 1
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: codedWidth,
            AVVideoHeightKey: codedHeight
        ]
        if codedWidth != width || codedHeight != height {
            videoSettings[AVVideoCleanApertureKey] = [
                AVVideoCleanApertureWidthKey: width,
                AVVideoCleanApertureHeightKey: height,
                AVVideoCleanApertureHorizontalOffsetKey: 0,
                AVVideoCleanApertureVerticalOffsetKey: 0
            ]
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: codedWidth,
            kCVPixelBufferHeightKey as String: codedHeight
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 64_000
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { fail("cannot add clip tracks") }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else { fail(writer.error?.localizedDescription ?? "startWriting") }
        writer.startSession(atSourceTime: .zero)
        let build = ClipBuild(
            writer: writer,
            videoInput: videoInput,
            audioInput: audioInput,
            adaptor: adaptor,
            frames: Int(seconds * 10),
            width: codedWidth,
            height: codedHeight,
            paint: paint
        )
        let queue = DispatchQueue(label: "ibms-bga-clip")
        videoInput.requestMediaDataWhenReady(on: queue) { build.appendVideoFrames() }
        audioInput.requestMediaDataWhenReady(on: queue) { build.appendAudioChunks() }
        let end = Date().addingTimeInterval(20)
        while !build.isCompleted && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        if let error = build.errorText { fail(error) }
        guard build.isCompleted, writer.status == .completed else {
            fail(writer.error?.localizedDescription ?? "clip writer did not finish, status=\(writer.status.rawValue)")
        }
    }

    fileprivate static func sampleBuffer(from buffer: AVAudioPCMBuffer, at time: CMTime) -> CMSampleBuffer? {
        let frames = CMItemCount(buffer.frameLength)
        guard frames > 0 else { return nil }
        var asbd = buffer.format.streamDescription.pointee
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        ) == noErr, let description else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: description,
            sampleCount: frames,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sample,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: buffer.audioBufferList
        ) == noErr else { return nil }
        return sample
    }

    @MainActor
    private static func awaitTracks(_ asset: AVURLAsset) -> [AVAssetTrack] {
        let box = TrackBox()
        Task {
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            box.tracks = tracks
            box.finished = true
        }
        let end = Date().addingTimeInterval(5)
        while !box.finished && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return box.tracks
    }

    private static func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ibms-bga-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("PreviewBGATests failed: \(message)\n", stderr)
        exit(1)
    }
}

private struct PixelCounts: CustomStringConvertible {
    var red = 0
    var green = 0
    var blue = 0
    var white = 0
    var yellow = 0
    var black = 0
    var other = 0
    var colored: Int { red + green + blue + white + yellow }
    var description: String {
        "red=\(red) green=\(green) blue=\(blue) white=\(white) yellow=\(yellow) black=\(black) other=\(other)"
    }
}

private final class DecodeGate: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var entries = 0
    private var open = false

    var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func enter() {
        lock.lock()
        entries += 1
        let shouldWait = entries == 1 && !open
        lock.unlock()
        if shouldWait {
            release.wait()
        }
    }

    func unblock() {
        lock.lock()
        open = true
        lock.unlock()
        release.signal()
    }
}

private final class ImageBox: @unchecked Sendable {
    var image: CGImage?
    var message: String?
    var finished = false
}

private final class TrackBox: @unchecked Sendable {
    var tracks: [AVAssetTrack] = []
    var finished = false
}

private final class ClipBuild: @unchecked Sendable {
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let frames: Int
    let width: Int
    let height: Int
    let paint: (@Sendable (Int, Int, Int) -> (UInt8, UInt8, UInt8, UInt8))?
    private var frame = 0
    private var audioConsumed = 0
    private let audioChunk = 1024
    private let audioTotal: Int
    private var videoDone = false
    private var audioDone = false
    private var didFinish = false
    private var completed = false
    private var error: String?
    private let lock = NSLock()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44_100,
        channels: 1,
        interleaved: false
    )

    init(
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        audioInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        frames: Int,
        width: Int,
        height: Int,
        paint: (@Sendable (Int, Int, Int) -> (UInt8, UInt8, UInt8, UInt8))? = nil
    ) {
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.adaptor = adaptor
        self.frames = frames
        self.width = width
        self.height = height
        self.paint = paint
        audioTotal = (frames / 10) * 44_100 / 1024 * 1024
    }

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    var errorText: String? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }

    func appendVideoFrames() {
        guard error == nil else { return }
        while videoInput.isReadyForMoreMediaData && frame < frames {
            guard let pool = adaptor.pixelBufferPool else { return }
            var pixel: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else {
                failBoth("no pixel buffer")
                return
            }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let base = CVPixelBufferGetBaseAddress(pixel) {
                let row = CVPixelBufferGetBytesPerRow(pixel)
                let shade = UInt8((frame * 8) % 255)
                for y in 0..<height {
                    let line = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        if let paint {
                            let sample = paint(x, y, frame)
                            line[x * 4] = sample.2
                            line[x * 4 + 1] = sample.1
                            line[x * 4 + 2] = sample.0
                            line[x * 4 + 3] = sample.3
                        } else {
                            line[x * 4] = 20
                            line[x * 4 + 1] = shade
                            line[x * 4 + 2] = 200
                            line[x * 4 + 3] = 255
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            let time = CMTime(value: CMTimeValue(frame), timescale: 10)
            guard adaptor.append(pixel, withPresentationTime: time) else {
                failBoth(writer.error?.localizedDescription ?? "append video")
                return
            }
            frame += 1
        }
        if frame >= frames && !videoDone {
            videoDone = true
            videoInput.markAsFinished()
            finishIfPossible()
        }
    }

    func appendAudioChunks() {
        guard error == nil, let format else {
            failBoth("audio format")
            return
        }
        while audioInput.isReadyForMoreMediaData && audioConsumed < audioTotal {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioChunk)) else {
                failBoth("audio buffer")
                return
            }
            buffer.frameLength = AVAudioFrameCount(audioChunk)
            if let channel = buffer.floatChannelData?[0] {
                var cursor = Float(audioConsumed)
                for index in 0..<audioChunk {
                    let angle = (cursor / 44_100) * 440 * 2 * Float.pi
                    channel[index] = sin(angle) * 0.2
                    cursor += 1
                }
            }
            let time = CMTime(seconds: Double(audioConsumed) / 44_100, preferredTimescale: 44_100)
            guard let sample = PreviewBGATests.sampleBuffer(from: buffer, at: time) else {
                failBoth("audio sample")
                return
            }
            guard audioInput.append(sample) else {
                failBoth(writer.error?.localizedDescription ?? "append audio")
                return
            }
            audioConsumed += audioChunk
        }
        if audioConsumed >= audioTotal && !audioDone {
            audioDone = true
            audioInput.markAsFinished()
            finishIfPossible()
        }
    }

    private func failBoth(_ message: String) {
        lock.lock()
        error = message
        lock.unlock()
        if !videoDone {
            videoDone = true
            videoInput.markAsFinished()
        }
        if !audioDone {
            audioDone = true
            audioInput.markAsFinished()
        }
        finishIfPossible()
    }

    private func finishIfPossible() {
        guard videoDone, audioDone, !didFinish else { return }
        didFinish = true
        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.completed = true
            self.lock.unlock()
        }
    }
}
