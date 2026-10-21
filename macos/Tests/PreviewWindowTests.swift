import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

/// 测试里的轻量状态。正式的 `ApplicationState` 会拉起音频桥，窗口测试不需要那一层。
@MainActor
final class ApplicationState {
    let previewPlayer: LegacyPreviewAudioPlayer
    var previewAudioIsImplemented: Bool

    init(audioImplemented: Bool = true) {
        previewPlayer = LegacyPreviewAudioPlayer()
        previewAudioIsImplemented = audioImplemented
    }
}

@main
struct PreviewWindowTests {
    @MainActor
    static func main() {
        let defaults = UserDefaults(suiteName: "IBMSPreviewWindowTests") ?? .standard
        defaults.removePersistentDomain(forName: "IBMSPreviewWindowTests")
        NativeLocalization.setDefaultsForTesting(defaults)
        NativeLocalization.useChineseSimplified()
        defer { NativeLocalization.setDefaultsForTesting(nil) }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        testOpenShowsChartParked()
        testNaturalEndKeepsTheLastBeat()
        testStopAndCloseSilenceAndIgnoreLateTicks()
        testPlayHereRecapturesAndDropsTheOldOrigin()
        testPlayerSideDoesNotRestartPlayback()
        testBGAAndPlayfieldShareOneClock()
        testStageKeepsUbmRatio()
        testScrollSpeedAndMenuMethods()
        testSpeedDetentsOnTheController()
        testEditorCursorClearsOnStartAndStopOnly()
        testDisplayStepPresentsWithoutRebuildingTheEditor()
        testHiddenClockFinishesOnceAndDoesNotRender()
        testFastBGAImageEventsStayOnTheDisplayClock()
        testPreparationDoesNotRunUntilReady()
        testBmsonDelayAndMissingDocument()
        testTimingIndexMatchesTheAudioClock()
        testDenseTimingTicksStayLogarithmic()
        testInfoKeepsFontGradientAndOneScale()
        testPlayInfoClockFollowsUnifiedPlayback()
        testUbmKeysDriveViewAudioAndBGA()
        testUbmStageTimingAndRate()
        testUbmDualClockAndFullStageBGA()
        testVideoRateFollowsEngine()
        testHiddenLogicKeepsLongNotes()
        testHiddenClockTextSkipsStageAndSyncsBGAOnce()
        testWindowContentScreenshot()
        print("PreviewWindowTests passed")
    }
}

private let bpm120 = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])

@MainActor
private func testOpenShowsChartParked() {
    let chart = stageChart(title: "Night Stage")
    let folder = chartFolder()
    let (controller, _) = makeController {
        context(chart: chart, timing: bpm120, playHere: 3, bmson: false, directory: folder)
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let display = controller.previewDisplay
    require(display.chart == chart, "open keeps the unsaved chart")
    require(!display.isPlaying && !display.isFinished && abs(display.beat) < 0.000_001, "opening parks at beat 0")
    require(display.visualEndBeat == nil, "idle open does not start a playback end")
    require(display.playerSide == .both, "default side is both")
    require(display.windowTitle == "Night Stage", "window title uses the chart title")
    require(controller.window?.title == "Night Stage", "NSWindow title follows the chart")
    require(display.bgaChartTitle == "Night Stage", "BGA receives the chart title")
    require(display.bgaDirectoryPath == folder.path, "BGA receives the chart directory")
    require(abs(display.bgaFromBeat) < 0.000_001 && !display.bgaIsPlaying, "parked BGA is at the start and not playing")
    require(
        display.statusText == "\(NativeLocalization.text("Stop")) · 120 BPM",
        "idle status got \(display.statusText)"
    )
    require(controller.window?.contentMinSize == PreviewWindowPlayback.minimumContentSize, "minimum size")
    let size = controller.window?.contentView?.bounds.size ?? .zero
    require(
        abs(size.width - PreviewWindowPlayback.defaultContentSize.width) < 1
            && abs(size.height - PreviewWindowPlayback.defaultContentSize.height) < 1,
        "default content size \(size)"
    )
    require(PreviewUbmStyle.canvasSize == CGSize(width: 587, height: 256), "canvas \(PreviewUbmStyle.canvasSize)")
    require(PreviewUbmStyle.playfieldSize == CGSize(width: 331, height: 256), "playfield \(PreviewUbmStyle.playfieldSize)")
    require(PreviewUbmStyle.bgaSize == CGSize(width: 256, height: 256), "bga \(PreviewUbmStyle.bgaSize)")
    let info = controller.previewInfoText
    require(info.contains("Play") && info.contains("BPM"), "default info is the play block \(info)")
    require(!info.contains("Night Stage") && !info.contains("NOTES") && !info.contains("BOTH"), "song lines stay hidden \(info)")
    require(info.contains("HS 1.00") && info.contains("RATE 1.00"), "play info shows both speeds \(info)")
    require(!info.contains("RANDOM") && !info.contains("GREAT") && !info.contains("AUTO") && !info.contains("RealHS"), "info invented a status \(info)")
    require(!info.contains("LEVEL") && !info.contains("RANK"), "missing headers stay blank \(info)")
    let blankFacts = PreviewUbmChartFacts.parse(Data("#TITLE only\n#RANKING 9\n".utf8))
    require(blankFacts.playLevel == nil && blankFacts.rank == nil, "ranking is not rank, facts \(blankFacts)")
    controller.stopPlayback()
}

@MainActor
private func testNaturalEndKeepsTheLastBeat() {
    let (controller, state) = makeController {
        context(chart: stageChart(title: "Night Stage"), timing: bpm120, playHere: 0, bmson: false)
    }
    controller.playFromStart()
    let display = controller.previewDisplay
    require(display.isPlaying && !display.isFinished, "a chart with an end beat stays playing")
    require(display.visualEndBeat == 16, "playback asks the clock to run through the chart end")
    let boundCharts = controller.previewBGAChartUpdates
    let tick = state.previewPlayer.onElapsedSeconds
    tick?(2)
    require(controller.previewBGAChartUpdates == boundCharts, "a playback tick must not rebind BGA")
    require(abs(controller.previewDisplay.beat - 4) < 0.000_001, "2s at 120 BPM is beat 4, got \(controller.previewDisplay.beat)")
    require(controller.previewDisplay.statusText == "0:02.00 · 4.00 · 120 BPM", "status \(controller.previewDisplay.statusText)")
    let playfieldUpdates = controller.previewPlayfieldPlaybackUpdates
    let bgaUpdates = controller.previewBGAPlaybackUpdates
    require(playfieldUpdates == bgaUpdates && playfieldUpdates > 0, "playfield and BGA were both driven")
    state.previewPlayer.onTimelineFinished?()
    require(controller.previewBGAChartUpdates == boundCharts, "natural end must not rebind BGA")
    let finished = controller.previewDisplay
    require(!finished.isPlaying && finished.isFinished, "natural end leaves the playing flag")
    require(abs(finished.beat - 4) < 0.000_001, "natural end keeps beat 4, got \(finished.beat)")
    require(abs(finished.elapsedSeconds - 2) < 0.000_001, "natural end keeps the final elapsed")
    require(abs(finished.bgaBeat - 4) < 0.000_001 && !finished.bgaIsPlaying, "BGA pauses on the same beat")
    require(
        finished.statusText == "0:02.00 · 4.00 · 120 BPM · \(NativeLocalization.text("Stop"))",
        "finished status got \(finished.statusText)"
    )
    tick?(9)
    require(
        !controller.previewDisplay.isPlaying && abs(controller.previewDisplay.beat - 4) < 0.000_001,
        "a late tick after the end does not resume playback"
    )
    state.previewPlayer.onPlaybackStopped?()
    require(controller.previewDisplay.isFinished && abs(controller.previewDisplay.beat - 4) < 0.000_001, "the same epoch's stop notice keeps the last beat")
    controller.stopPlayback()
    require(!controller.previewDisplay.isPlaying && !controller.previewDisplay.isFinished, "explicit stop clears the finished flag")
    require(abs(controller.previewDisplay.beat) < 0.000_001, "explicit stop parks at beat 0")

    var empty = stageChart(title: "Empty End")
    empty.notes = []
    empty.endBeat = 0
    controller.setDocumentSource { context(chart: empty, timing: bpm120, playHere: 0, bmson: false) }
    controller.playFromStart()
    require(!controller.previewDisplay.isPlaying && controller.previewDisplay.isFinished, "a zero-length timeline finishes immediately")
    require(abs(controller.previewDisplay.beat) < 0.000_001 && !controller.previewDisplay.bgaIsPlaying, "the empty end stays on its last beat")
    controller.stopPlayback()
}

@MainActor
private func testStopAndCloseSilenceAndIgnoreLateTicks() {
    let chart = stageChart(title: "Night Stage")
    let (controller, state) = makeController {
        context(chart: chart, timing: bpm120, playHere: 0, bmson: false)
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    controller.playFromStart()
    let tick = state.previewPlayer.onElapsedSeconds
    tick?(2)
    require(controller.previewDisplay.isPlaying, "playing before stop")
    controller.stopPlayback()
    require(!controller.previewDisplay.isPlaying && !controller.previewDisplay.bgaIsPlaying, "stop pauses the picture and BGA")
    require(controller.previewDisplay.chart == chart, "stop keeps the chart")
    require(state.previewPlayer.onElapsedSeconds == nil, "stop detaches the elapsed callback")
    tick?(9)
    require(!controller.previewDisplay.isPlaying && abs(controller.previewDisplay.beat) < 0.000_001, "a captured old tick cannot resume playback")

    controller.playFromStart()
    state.previewPlayer.onElapsedSeconds?(1)
    guard let window = controller.window else { fail("missing window") }
    window.makeKeyAndOrderFront(nil)
    require(window.isVisible, "preview is on screen")
    require(controller.windowShouldClose(window) == false, "close hides the window instead of destroying it")
    require(!window.isVisible, "close orders the window out")
    require(!controller.previewDisplay.isPlaying && !controller.previewDisplay.bgaIsPlaying, "close stops picture and BGA")
    require(state.previewPlayer.onElapsedSeconds == nil && state.previewPlayer.onTimelineFinished == nil, "close detaches timeline callbacks")
    controller.stopPlayback()
}

@MainActor
private func testPlayHereRecapturesAndDropsTheOldOrigin() {
    var fetches = 0
    var current = context(chart: stageChart(title: "Draft"), timing: bpm120, playHere: 2, bmson: false)
    let unsaved = context(
        chart: stageChart(title: "Unsaved Take"),
        timing: bpm120,
        playHere: 8,
        bmson: false,
        directory: chartFolder()
    )
    let (controller, state) = makeController {
        fetches += 1
        return current
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    require(fetches == 1, "opening reads the document once, fetches \(fetches)")
    require(controller.previewDisplay.chart.title == "Draft", "open shows the first unsaved title")
    current = unsaved
    controller.playFromPointer()
    require(fetches == 2, "Play Here reads the document again, fetches \(fetches)")
    require(controller.previewDisplay.chart == unsaved.visualChart, "playback uses the chart captured at play time")
    require(abs(controller.previewDisplay.beat - 8) < 0.000_001, "Play Here starts at the cursor, got \(controller.previewDisplay.beat)")
    require(abs(controller.previewDisplay.bgaFromBeat - 8) < 0.000_001, "BGA seek origin is the cursor")
    require(controller.previewDisplay.bgaDirectoryPath == unsaved.chartDirectory?.path, "BGA directory follows the recaptured chart")
    let stale = state.previewPlayer.onElapsedSeconds
    controller.playFromStart()
    stale?(5)
    require(abs(controller.previewDisplay.beat) < 0.000_001, "an elapsed callback from the previous play does not move the new one, got \(controller.previewDisplay.beat)")
    state.previewPlayer.onElapsedSeconds?(1)
    require(controller.previewDisplay.isPlaying, "replay is playing")
    require(abs(controller.previewDisplay.beat - 2) < 0.000_001, "replay from the start, 1s is beat 2, got \(controller.previewDisplay.beat)")
    require(abs(controller.previewDisplay.bgaBeat - controller.previewDisplay.beat) < 0.000_001, "BGA follows the restarted beat")
    controller.stopPlayback()
}

@MainActor
private func testPlayerSideDoesNotRestartPlayback() {
    var fetches = 0
    let chart = stageChart(title: "Double")
    let (controller, state) = makeController {
        fetches += 1
        return context(chart: chart, timing: bpm120, playHere: 0, bmson: false)
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    controller.playFromStart()
    state.previewPlayer.onElapsedSeconds?(1)
    let fetchesWhilePlaying = fetches
    let appliesBefore = controller.previewPlayerSideApplies
    selectSide(controller, segment: 1)
    require(controller.previewDisplay.playerSide == .onePlayer, "1P is selected")
    require(controller.previewDisplay.isPlaying && abs(controller.previewDisplay.beat - 2) < 0.000_001, "switching side does not restart the clock")
    require(fetches == fetchesWhilePlaying, "switching side does not recapture the document")
    require(controller.previewDisplay.chart.lanes.count == 16, "the controller still hands both sides to the playfield")
    require(controller.previewPlayerSideApplies > appliesBefore, "setPlayerSide ran")
    selectSide(controller, segment: 2)
    require(controller.previewDisplay.playerSide == .twoPlayer, "2P is selected")
    selectSide(controller, segment: 0)
    require(controller.previewDisplay.playerSide == .both && controller.previewDisplay.isPlaying, "Both returns without stopping")
    controller.stopPlayback()
}

@MainActor
private func testBGAAndPlayfieldShareOneClock() {
    let stopped = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 2, durationSeconds: 1)])
    let folder = chartFolder()
    let (controller, state) = makeController {
        context(chart: stageChart(title: "Hold"), timing: stopped, playHere: 0, bmson: false, directory: folder)
    }
    controller.playFromStart()
    let before = controller.previewBGAPlaybackUpdates
    state.previewPlayer.onElapsedSeconds?(1.5)
    let display = controller.previewDisplay
    require(abs(display.beat - 2) < 0.000_001, "1.5s sits on the STOP at beat 2, got \(display.beat)")
    require(abs(display.bgaBeat - display.beat) < 0.000_001, "BGA beat matches the playfield")
    require(abs(display.bgaElapsedSeconds - display.elapsedSeconds) < 0.000_001, "BGA elapsed matches the playfield")
    require(display.bgaIsPlaying && display.isPlaying, "both surfaces are playing")
    require(controller.previewBGAPlaybackUpdates > before, "the STOP tick reached BGA")
    require(controller.previewPlayfieldPlaybackUpdates == controller.previewBGAPlaybackUpdates, "each tick drives both surfaces")
    require(display.bgaDirectoryPath == folder.path, "BGA keeps the chart directory")
    require(display.statusText == "0:01.50 · 2.00 · 120 BPM", "status \(display.statusText)")
    controller.stopPlayback()
    require(!controller.previewDisplay.bgaIsPlaying, "stop clears the BGA playing flag")

    let faster = PreviewAudioTiming(headerBPM: 120, bpmEvents: [(beat: 2, bpm: 240)])
    controller.setDocumentSource { context(chart: stageChart(title: "Rush"), timing: faster, playHere: 0, bmson: false) }
    controller.playFromStart()
    state.previewPlayer.onElapsedSeconds?(1.5)
    require(abs(controller.previewDisplay.beat - 4) < 0.000_001, "1.5s with the 240 change is beat 4, got \(controller.previewDisplay.beat)")
    require(abs(controller.previewDisplay.bgaBeat - 4) < 0.000_001, "BGA uses the same tempo map")
    require(controller.previewDisplay.statusText == "0:01.50 · 4.00 · 240 BPM", "status \(controller.previewDisplay.statusText)")
    controller.stopPlayback()
}

@MainActor
private func testStageKeepsUbmRatio() {
    let (controller, _) = makeController {
        context(
            chart: stageChart(title: "Night Stage"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Night Stage\n#PLAYLEVEL 12\n#RANK 3\n".utf8)
        )
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let wide = controller.previewLayout
    require(wide.sideBySide, "default window keeps the playfield beside the BGA")
    require(!wide.packed, "a chart without #PLAYER 3 stays separated")
    require(abs(wide.stageScale - 2) < 0.001, "default scale \(wide.stageScale)")
    require(abs(wide.playfieldFrame.minX - 30) < 1 && abs(wide.playfieldFrame.width - 316) < 1, "1P strip \(wide.playfieldFrame)")
    require(abs(wide.playfieldFrame.height - 512) < 1, "playfield height \(wide.playfieldFrame)")
    require(abs(wide.bgaFrame.minX - 346) < 1 && abs(wide.bgaFrame.width - 512) < 1, "centered BGA \(wide.bgaFrame)")
    require(abs(wide.bgaFrame.height - 512) < 1, "bga height \(wide.bgaFrame)")
    require(abs(wide.secondPlayfieldFrame.minX - 858) < 1 && abs(wide.secondPlayfieldFrame.width - 316) < 1, "2P strip \(wide.secondPlayfieldFrame)")
    require(abs(wide.playfieldFrame.maxX - wide.bgaFrame.minX) < 1, "1P meets the BGA")
    require(abs(wide.bgaFrame.maxX - wide.secondPlayfieldFrame.minX) < 1, "BGA meets 2P")
    require(wide.playfieldFrame.minX < wide.bgaFrame.minX, "playfield is on the left")
    let wideOverlap = wide.playfieldFrame.intersection(wide.bgaFrame)
    require(wideOverlap.isNull || wideOverlap.width < 1, "side by side panes do not cover each other")
    require(find(id: "PreviewSplit", in: controller.window?.contentView) == nil, "the arbitrary split is gone")
    require(wide.controlsFrame == .zero, "the default client area has no control strip \(wide.controlsFrame)")
    let info = controller.previewInfoText
    let infoLines = info.split(separator: "\n", omittingEmptySubsequences: false)
    let infoColumns = infoLines.map(\.count).max() ?? 0
    require(
        abs(wide.infoFrame.width - CGFloat(infoColumns) * PreviewUbmInfoView.cellAdvance * wide.stageScale) < 1,
        "info width follows 8px advance \(wide.infoFrame) columns \(infoColumns)"
    )
    require(
        abs(wide.infoFrame.height - CGFloat(infoLines.count) * PreviewUbmInfoView.cellHeight * wide.stageScale) < 1,
        "info height follows the 12px cell \(wide.infoFrame)"
    )
    if let infoView = find(id: "PreviewUbmInfo", in: controller.window?.contentView) {
        require(!infoView.wantsLayer && infoView.layer?.backgroundColor == nil, "info has no modern background")
    } else {
        fail("missing info view")
    }
    require(
        abs(controller.previewInfoLayoutSize.width - CGFloat(infoColumns) * PreviewUbmInfoView.cellAdvance) < 1,
        "the font box stays at native 8px cells \(controller.previewInfoLayoutSize)"
    )
    require(wide.bgaFrame.contains(wide.infoFrame), "info stays on the BGA \(wide.infoFrame) bga \(wide.bgaFrame)")
    require(wide.infoFrame.width < wide.bgaFrame.width && wide.infoFrame.height < wide.bgaFrame.height * 0.5, "info does not cover the BGA")
    require(!info.contains("LEVEL") && !info.contains("RANK"), "play-only info hides the header \(info)")
    controller.previewSendKeyDown(keyEvent("9", window: controller.window))
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let song = controller.previewInfoText
    require(song.contains("Song") && song.contains("LEVEL 12") && song.contains("RANK 3"), "header facts \(song)")
    require(!song.contains("RealHS"), "RealHS is not shown as active \(song)")

    layout(controller, size: NSSize(width: 1800, height: 800))
    let larger = controller.previewLayout
    require(larger.sideBySide && abs(larger.stageScale - 3) < 0.001, "1800x800 uses scale 3, got \(larger.stageScale)")
    require(abs(larger.playfieldFrame.width / larger.bgaFrame.width - 158.0 / 256.0) < 0.01, "integer scale keeps the 158px panel")

    layout(controller, size: NSSize(width: 640, height: 480))
    let narrow = controller.previewLayout
    require(narrow.sideBySide, "a narrower window still places the panes side by side")
    require(abs(narrow.stageScale - 1) < 0.001, "640pt window stays at 1x, got \(narrow.stageScale)")
    require(abs(narrow.playfieldFrame.width / narrow.bgaFrame.width - 158.0 / 256.0) < 0.01, "narrow ratio")

    let tiny = PreviewWindowPlayback.stageFrames(in: CGRect(x: 0, y: 0, width: 300, height: 120))
    require(tiny.scale < 1, "below 1x the stage scales uniformly, got \(tiny.scale)")
    require(abs(tiny.playfield.width / tiny.bga.width - 331.0 / 256.0) < 0.02, "fractional scale keeps the ratio")
    require(abs(tiny.playfield.maxX - tiny.bga.minX) < 0.5, "fractional panes stay adjacent")

    guard let root = controller.window?.contentView,
          let showItem = root.menu?.items.first(where: { $0.identifier?.rawValue == "PreviewControlsMenu" }),
          let action = showItem.action else {
        fail("missing controls menu")
    }
    require(NSApp.sendAction(action, to: showItem.target, from: showItem), "the menu shows the controls")
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let shownControls = controller.previewLayout
    require(shownControls.controlsFrame.height > 1, "the menu reveals the strip")
    require(
        shownControls.sideBySide && abs(shownControls.playfieldFrame.width / shownControls.bgaFrame.width - 158.0 / 256.0) < 0.01,
        "showing controls keeps the separated panels"
    )
    guard let toggle = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command, .shift],
        timestamp: 0,
        windowNumber: controller.window?.windowNumber ?? 0,
        context: nil,
        characters: "h",
        charactersIgnoringModifiers: "h",
        isARepeat: false,
        keyCode: 4
    ) else {
        fail("could not build the controls shortcut")
    }
    require(root.performKeyEquivalent(with: toggle), "command-shift-H toggles the strip")
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    require(controller.previewLayout.controlsFrame == .zero, "the shortcut hides the strip again")
    controller.stopPlayback()
}

@MainActor
private func testScrollSpeedAndMenuMethods() {
    var fetches = 0
    let chart = stageChart(title: "Night Stage")
    let (controller, _) = makeController(source: {
        fetches += 1
        return context(chart: chart, timing: bpm120, playHere: 5, bmson: false)
    }, audio: false)
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    guard let root = controller.window?.contentView else { fail("missing content") }
    for identifier in ["PreviewPlayFromStart", "PreviewPlayHere", "PreviewStop"] {
        guard let button = find(id: identifier, in: root) as? NSButton else { fail("missing \(identifier)") }
        require(!button.isEnabled, "\(identifier) is disabled without preview audio")
        button.performClick(nil)
    }
    require(fetches == 1 && !controller.previewDisplay.isPlaying, "disabled buttons do not start playback")
    controller.setPreviewScrollPixelsPerBeat(10_000)
    require(
        abs(controller.previewPlayfieldPixelsPerBeat - PreviewWindowPlayback.maximumPixelsPerBeat) < 0.001,
        "scroll caps at \(controller.previewPlayfieldPixelsPerBeat)"
    )
    controller.setPreviewScrollPixelsPerBeat(-4)
    require(
        abs(controller.previewPlayfieldPixelsPerBeat - 24) < 0.001,
        "non-positive scroll snaps to the 0.50 detent, not the 16px floor"
    )
    require(abs(controller.previewHiSpeed - 0.5) < 0.001, "stored HiSpeed follows the snapped pixels")
    controller.setPreviewScrollPixelsPerBeat(.nan)
    require(
        abs(controller.previewDisplay.pixelsPerBeat - PreviewWindowPlayback.defaultPixelsPerBeat) < 0.001,
        "non-finite scroll returns to the default"
    )
    guard let slider = find(id: "PreviewScrollSpeed", in: root) as? NSSlider else { fail("missing scroll slider") }
    slider.doubleValue = 64
    require(slider.sendAction(slider.action, to: slider.target), "slider action")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 60) < 0.001, "slider snaps 64px to the 1.25 detent")
    require(abs(controller.previewHiSpeed - 1.25) < 0.001, "slider writes the HiSpeed detent")

    controller.playFromStart()
    require(fetches == 2 && controller.previewDisplay.isPlaying && abs(controller.previewDisplay.beat) < 0.000_001, "F5 still plays from the start")
    controller.playFromPointer()
    require(fetches == 3 && abs(controller.previewDisplay.beat - 5) < 0.000_001, "F6 still plays from the cursor")
    controller.stopPlayback()
    require(!controller.previewDisplay.isPlaying, "F7 stops")
    controller.playFromStart()
    controller.setDocumentSource { context(chart: stageChart(title: "While Playing"), timing: bpm120, playHere: 0, bmson: false) }
    require(controller.previewDisplay.isPlaying && controller.previewDisplay.chart.title == "Night Stage", "replacing the source during playback keeps the running chart")
    controller.stopPlayback()
    controller.setDocumentSource { context(chart: stageChart(title: "After Stop"), timing: bpm120, playHere: 1, bmson: false) }
    require(!controller.previewDisplay.isPlaying && controller.previewDisplay.chart.title == "After Stop", "after stop, a new source refreshes the parked chart")
}

@MainActor
private func testEditorCursorClearsOnStartAndStopOnly() {
    var beats: [Double] = []
    var nils = 0
    let (bms, state) = makeController(
        source: { context(chart: stageChart(title: "BMS"), timing: bpm120, playHere: 0, bmson: false) },
        onBeat: { value in
            if let value { beats.append(value) } else { nils += 1 }
        }
    )
    require(nils == 0 && beats.isEmpty, "opening does not touch the editor")
    bms.playFromStart()
    require(nils == 1 && beats.isEmpty, "start clears the editor once, nils \(nils)")
    for seconds in [0.05, 0.5, 1.0, 2.0] {
        state.previewPlayer.onElapsedSeconds?(seconds)
    }
    bms.stepPresentationDisplayLink()
    require(nils == 1 && beats.isEmpty, "ticks and a display step stay off the editor")
    bms.stopPlayback()
    require(nils == 2 && beats.isEmpty, "stop clears once more, nils \(nils)")
    bms.stopPlayback()
    require(nils == 2, "a second stop does not clear again")

    nils = 0
    beats.removeAll()
    let (bmson, bmsonState) = makeController(
        source: { context(chart: stageChart(title: "BMSON"), timing: bpm120, playHere: 0, bmson: true) },
        onBeat: { value in
            if let value { beats.append(value) } else { nils += 1 }
        }
    )
    bmson.delayRatioSource = { 1 }
    bmson.playFromStart()
    require(nils == 1 && beats.isEmpty, "BMSON start clears once")
    bmsonState.previewPlayer.onElapsedSeconds?(2)
    require(abs(bmson.previewDisplay.beat - 3.816) < 0.000_001, "the preview clock still uses the delayed beat, got \(bmson.previewDisplay.beat)")
    bmson.stepPresentationDisplayLink()
    require(nils == 1 && beats.isEmpty, "BMSON playback does not forward the cursor")
    bmson.stopPlayback()
    require(nils == 2 && beats.isEmpty, "BMSON stop clears once")
}

@MainActor
private func testDisplayStepPresentsWithoutRebuildingTheEditor() {
    var editorCalls = 0
    let (controller, state) = makeController(
        source: { context(chart: stageChart(title: "Sync"), timing: bpm120, playHere: 0, bmson: false) },
        onBeat: { _ in editorCalls += 1 }
    )
    controller.previewDisplayLinkSuppressed = true
    controller.playFromStart()
    require(!controller.previewDisplayLinkAttached, "suppressed playback does not attach a display link")
    require(!controller.previewUsesExternalPresentationClock, "suppressed playback keeps the timer fallback")
    let presented = controller.previewPresentedFrameCount
    let bga = controller.previewBGAPlaybackUpdates
    let rasters = controller.previewInfoRasterCount
    let started = Date()
    for _ in 0..<30 {
        controller.stepPresentationDisplayLink()
    }
    let elapsed = Date().timeIntervalSince(started)
    require(controller.previewPresentedFrameCount == presented + 30, "each display step submits one frame, got \(controller.previewPresentedFrameCount - presented)")
    require(editorCalls == 1, "display steps do not rebuild the editor, calls \(editorCalls)")
    require(
        controller.previewBGAPlaybackUpdates - bga == 30,
        "every display step checks the BGA event, updates \(controller.previewBGAPlaybackUpdates - bga)"
    )
    if elapsed < 0.25 {
        require(controller.previewInfoRasterCount - rasters <= 2, "info rasterized \(controller.previewInfoRasterCount - rasters) times in \(elapsed)s")
    }
    state.previewPlayer.onElapsedSeconds?(2)
    require(abs(controller.previewDisplay.beat - 4) < 0.000_001, "timer fallback still accepts an elapsed sample")
    controller.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification))
    controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
    require(!controller.previewDisplayLinkAttached, "a hidden window does not keep the link")
    controller.stopPlayback()

    let (shown, _) = makeController {
        context(chart: stageChart(title: "Screen"), timing: bpm120, playHere: 0, bmson: false)
    }
    layout(shown, size: PreviewWindowPlayback.defaultContentSize)
    shown.playFromStart()
    if let screen = shown.window?.screen, screen.maximumFramesPerSecond > 0 {
        require(shown.previewDisplayLinkAttached, "a visible window follows its screen")
        require(shown.previewDisplayLinkFramesPerSecond == screen.maximumFramesPerSecond, "link rate \(shown.previewDisplayLinkFramesPerSecond)")
        require(shown.previewUsesExternalPresentationClock, "the screen drives the audio clock")
        shown.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
        require(!shown.previewDisplayLinkAttached && shown.previewDisplay.isPlaying, "miniaturize detaches without stopping playback")
        require(!shown.previewUsesExternalPresentationClock, "hiding restores the timer on the same origin")
        require(shown.previewPictureSuppressed, "hiding suppresses the picture")
        shown.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification))
        require(shown.previewDisplayLinkAttached, "returning to the screen attaches again")
        shown.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification))
        require(shown.previewDisplayLinkFramesPerSecond == screen.maximumFramesPerSecond, "moving screens keeps the current rate")
    } else {
        require(!shown.previewDisplayLinkAttached, "no screen means no display link")
        require(!shown.previewUsesExternalPresentationClock, "no screen keeps the timer fallback")
    }
    let before = shown.previewPresentedFrameCount
    shown.stepPresentationDisplayLink()
    require(shown.previewPresentedFrameCount == before + 1, "a display step still submits when the window is up")
    shown.stopPlayback()
    require(!shown.previewDisplayLinkAttached, "stop detaches the display link")
    require(!shown.previewUsesExternalPresentationClock, "stop leaves the external clock off")
}

@MainActor
private func testHiddenClockFinishesOnceAndDoesNotRender() {
    var fetches = 0
    var chart = stageChart(title: "Short")
    chart.endBeat = 0.4
    let (controller, _) = makeController(source: {
        fetches += 1
        return context(chart: chart, timing: bpm120, playHere: 0, bmson: false)
    })
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    controller.playFromStart()
    let startedFetches = fetches
    require(controller.previewDisplay.isPlaying && !controller.previewDisplay.isFinished, "the short chart is playing before it is hidden")
    let presented = controller.previewPresentedFrameCount
    let playfield = controller.previewPlayfieldPlaybackUpdates
    let steps = controller.previewDisplayStepCount
    hidePreview(controller)
    require(controller.previewPictureSuppressed && controller.previewDisplay.isPlaying, "hiding keeps the song running")
    require(!controller.previewUsesExternalPresentationClock, "hiding gives the clock back to the timer")
    pump(0.75)
    require(controller.previewDisplay.isFinished && !controller.previewDisplay.isPlaying, "a hidden chart finishes on the timer")
    require(abs(controller.previewDisplay.beat - 0.4) < 0.02, "the finished beat stays at the chart end, got \(controller.previewDisplay.beat)")
    require(controller.previewPresentedFrameCount == presented, "hiding does not present, frames \(controller.previewPresentedFrameCount - presented)")
    require(controller.previewPlayfieldPlaybackUpdates == playfield, "hiding does not rebuild the playfield")
    require(controller.previewDisplayStepCount == steps, "hiding does not keep the display step running")
    let finishedBeat = controller.previewDisplay.beat
    controller.showWindow(nil)
    pump(0.25)
    require(fetches == startedFetches, "showing the finished preview does not start again, fetches \(fetches)")
    require(controller.previewDisplay.isFinished && !controller.previewDisplay.isPlaying, "showing does not replay")
    require(abs(controller.previewDisplay.beat - finishedBeat) < 0.001, "showing keeps the finished beat")
    controller.stopPlayback()

    var continuedFetches = 0
    let (continued, _) = makeController(source: {
        continuedFetches += 1
        return context(chart: stageChart(title: "Long"), timing: bpm120, playHere: 0, bmson: false)
    })
    layout(continued, size: PreviewWindowPlayback.defaultContentSize)
    continued.playFromStart()
    let continuedStarts = continuedFetches
    require(continued.previewDisplay.isPlaying, "the long chart starts")
    hidePreview(continued)
    let hiddenElapsed = continued.previewDisplay.elapsedSeconds
    let hiddenPresented = continued.previewPresentedFrameCount
    let hiddenPlayfield = continued.previewPlayfieldPlaybackUpdates
    pump(0.4)
    require(continued.previewDisplay.isPlaying && !continued.previewDisplay.isFinished, "hiding does not stop a chart that has not ended")
    require(
        continued.previewDisplay.elapsedSeconds > hiddenElapsed + 0.12,
        "the timer keeps the same origin, elapsed \(continued.previewDisplay.elapsedSeconds)"
    )
    require(continued.previewPresentedFrameCount == hiddenPresented, "a hidden chart does not present")
    require(continued.previewPlayfieldPlaybackUpdates == hiddenPlayfield, "a hidden chart does not redraw the playfield")
    let resumedElapsed = continued.previewDisplay.elapsedSeconds
    continued.showWindow(nil)
    require(continued.previewDisplay.isPlaying, "showing continues playback")
    require(continued.previewDisplay.elapsedSeconds + 0.05 >= resumedElapsed, "showing does not rewind, elapsed \(continued.previewDisplay.elapsedSeconds)")
    require(continuedFetches == continuedStarts, "showing does not replay, fetches \(continuedFetches)")
    if continued.window?.screen?.maximumFramesPerSecond ?? 0 > 0 {
        require(continued.previewUsesExternalPresentationClock, "a visible window takes the display clock back")
    }
    continued.stopPlayback()
    require(!continued.previewDisplay.isPlaying && !continued.previewUsesExternalPresentationClock, "stop still halts everything")

    let clip = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("promo/preview/vfx.mp4")
    require(FileManager.default.fileExists(atPath: clip.path), "video hold needs \(clip.path)")
    var videoChart = stageChart(title: "Video")
    videoChart.bgaAssets = [PreviewBGAAsset(id: "V", fileName: clip.lastPathComponent)]
    videoChart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "V", layer: .base)]
    let (video, _) = makeController {
        context(chart: videoChart, timing: bpm120, playHere: 0, bmson: false, directory: clip.deletingLastPathComponent())
    }
    layout(video, size: PreviewWindowPlayback.defaultContentSize)
    video.playFromStart()
    guard let videoView = find(id: "PreviewBGA", in: video.window?.contentView) as? PreviewBGAView else {
        fail("missing BGA view")
    }
    pump(0.3)
    let opened = videoView.inspection()
    require(opened.videoAttached && opened.videoItemKept, "playback opens the video, status \(opened.status)")
    let opens = opened.videoOpenCount
    hidePreview(video)
    let held = videoView.inspection()
    require((held.videoRate ?? 0) == 0, "hiding pauses the video, rate \(held.videoRate ?? -1)")
    require(held.videoItemKept, "hiding keeps the current frame instead of releasing the player")
    let heldPresented = video.previewPresentedFrameCount
    pump(0.35)
    let still = videoView.inspection()
    require(still.videoOpenCount == opens, "hiding does not reopen the video, opens \(still.videoOpenCount)")
    require((still.videoRate ?? 0) == 0, "the held video stays paused")
    require(video.previewPresentedFrameCount == heldPresented, "a held video does not keep presenting")
    require(video.previewDisplay.isPlaying, "the song is still going while the video is held")
    video.showWindow(nil)
    require(video.previewDisplay.isPlaying, "showing resumes the same playback")
    require(videoView.inspection().videoOpenCount <= opens + 1, "resume does not keep reopening the video")
    video.stopPlayback()
    require(!video.previewDisplay.isPlaying, "stop halts the held video playback")
}

@MainActor
private func testFastBGAImageEventsStayOnTheDisplayClock() {
    var chart = stageChart(title: "Fast")
    chart.bgaEvents = [
        PreviewBGAEvent(beat: 0, assetID: "AA", layer: .base),
        PreviewBGAEvent(beat: 0.04, assetID: "BB", layer: .base),
        PreviewBGAEvent(beat: 0.08, assetID: "CC", layer: .base),
        PreviewBGAEvent(beat: 0, assetID: "L1", layer: .layer),
        PreviewBGAEvent(beat: 0.04, assetID: "L2", layer: .layer)
    ]
    let (controller, _) = makeController {
        context(chart: chart, timing: bpm120, playHere: 0, bmson: false)
    }
    controller.previewDisplayLinkSuppressed = true
    controller.playFromStart()
    guard let view = find(id: "PreviewBGA", in: controller.window?.contentView) as? PreviewBGAView else {
        fail("missing BGA view")
    }
    var bases: [String] = []
    var layers: [String] = []
    for sample in [0.0, 0.020, 0.040] {
        controller.previewPresentSampledElapsed(sample)
        let seen = view.inspection()
        bases.append(seen.baseAssetID ?? "")
        layers.append(seen.layerAssetID ?? "")
    }
    require(bases == ["AA", "BB", "CC"], "image events closer than 33ms stay in order \(bases)")
    require(layers == ["L1", "L2", "L2"], "the layer follows the same samples \(layers)")
    controller.stopPlayback()
}

@MainActor
private func testPreparationDoesNotRunUntilReady() {
    let note = PreviewAudioNote(beat: 0, wavToken: "01")
    let document = Data("#WAV01 click.wav\n".utf8)
    let gate = PrepareGate()
    let (controller, state) = makeController {
        context(
            chart: stageChart(title: "Prep"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            directory: chartFolder(),
            audioNotes: [note],
            documentData: document
        )
    }
    let wav = tinyWav()
    state.previewPlayer.readResourceBytes = { _ in
        while !gate.isOpen {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return wav
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let presented = controller.previewPresentedFrameCount
    controller.playFromStart()
    require(!controller.previewDisplay.isPlaying, "preparing does not pretend the playhead is running")
    require(!controller.previewDisplayLinkAttached && !controller.previewUsesExternalPresentationClock, "preparing does not engage the display clock")
    require(controller.previewPresentedFrameCount == presented, "preparing does not present")
    controller.playFromStart()
    require(!controller.previewDisplay.isPlaying && !controller.previewDisplay.isFinished, "a replay cancel does not finish or start the old generation")
    gate.open()
    pump(1.0)
    require(controller.previewDisplay.isPlaying && !controller.previewDisplay.isFinished, "only the new ready generation starts")
    if controller.window?.screen?.maximumFramesPerSecond ?? 0 > 0 {
        require(controller.previewDisplayLinkAttached && controller.previewUsesExternalPresentationClock, "ready engages the display clock")
    }
    controller.stopPlayback()

    gate.close()
    controller.playFromStart()
    require(!controller.previewDisplay.isPlaying, "a new prepare waits again")
    controller.stopPlayback()
    gate.open()
    pump(0.4)
    require(!controller.previewDisplay.isPlaying && !controller.previewDisplay.isFinished, "cancelling prepare does not start playback later")
}

@MainActor
private func testBmsonDelayAndMissingDocument() {
    var beats: [Double] = []
    var nilCount = 0
    let (bmson, bmsonState) = makeController(
        source: { context(chart: stageChart(title: "BMSON"), timing: bpm120, playHere: 0, bmson: true) },
        onBeat: { value in
            if let value {
                beats.append(value)
            } else {
                nilCount += 1
            }
        }
    )
    bmson.delayRatioSource = { 1 }
    bmson.playFromStart()
    beats.removeAll()
    nilCount = 0
    bmsonState.previewPlayer.onElapsedSeconds?(0.05)
    require(abs(bmson.previewDisplay.beat) < 0.000_001, "50ms is still inside the buffer, got \(bmson.previewDisplay.beat)")
    bmsonState.previewPlayer.onElapsedSeconds?(2)
    require(abs(bmson.previewDisplay.beat - 3.816) < 0.000_001, "2s minus 92ms is beat 3.816, got \(bmson.previewDisplay.beat)")
    require(bmson.previewDisplay.statusText == "0:01.91 · 3.82 · 120 BPM", "status \(bmson.previewDisplay.statusText)")
    require(beats.isEmpty && nilCount == 0, "BMSON ticks do not rebuild the editor, beats \(beats.count) nils \(nilCount)")
    bmson.stopPlayback()

    beats.removeAll()
    nilCount = 0
    let (plain, plainState) = makeController(
        source: { context(chart: stageChart(title: "BMS"), timing: bpm120, playHere: 0, bmson: false) },
        onBeat: { value in
            if let value {
                beats.append(value)
            } else {
                nilCount += 1
            }
        }
    )
    plain.delayRatioSource = { 1 }
    plain.playFromStart()
    beats.removeAll()
    nilCount = 0
    plainState.previewPlayer.onElapsedSeconds?(0.05)
    require(abs(plain.previewDisplay.beat - 0.1) < 0.000_001, "BMS does not eat the buffer delay, got \(plain.previewDisplay.beat)")
    plainState.previewPlayer.onElapsedSeconds?(2)
    require(abs(plain.previewDisplay.beat - 4) < 0.000_001, "BMS 2s is beat 4")
    require(beats.isEmpty && nilCount == 0, "BMS ticks do not rebuild the editor, nils \(nilCount)")
    plain.delayRatioSource = { -.infinity }
    plain.playFromStart()
    plainState.previewPlayer.onElapsedSeconds?(2)
    require(abs(plain.previewDisplay.beat - 4) < 0.000_001, "a non-finite delay ratio does not move the beat")
    plain.delayRatioSource = { -2 }
    plain.playFromPointer()
    plainState.previewPlayer.onElapsedSeconds?(2)
    require(abs(plain.previewDisplay.beat - 4) < 0.000_001, "a negative finite ratio keeps the old zero-delay meaning")
    plainState.previewPlayer.onElapsedSeconds?(.nan)
    require(plain.previewDisplay.isPlaying, "a non-finite tick does not stop playback")
    require(abs(plain.previewDisplay.beat) < 0.000_001, "a non-finite tick holds the start beat, got \(plain.previewDisplay.beat)")
    require(!plain.previewDisplay.statusText.lowercased().contains("nan"), "status \(plain.previewDisplay.statusText)")

    var endless = stageChart(title: "Open")
    endless.endBeat = .nan
    endless.notes = []
    plain.setDocumentSource {
        context(
            chart: endless,
            timing: bpm120,
            playHere: 0,
            bmson: false,
            audioNotes: [PreviewAudioNote(beat: 4, wavToken: "01")]
        )
    }
    plain.playFromStart()
    require(plain.previewDisplay.visualEndBeat == nil, "a non-finite chart end is not sent as the visual end")
    require(plain.previewDisplay.isPlaying, "an audio hit keeps the timeline open")
    plain.stopPlayback()

    var present = true
    plain.setDocumentSource {
        present ? context(chart: stageChart(title: "Night Stage"), timing: bpm120, playHere: 0, bmson: false) : nil
    }
    plain.showWindow(nil)
    present = false
    plain.showWindow(nil)
    require(plain.previewDisplay.chart == PreviewChartSnapshot(), "no document clears the old chart")
    require(plain.previewDisplay.bgaChartTitle.isEmpty, "BGA drops the old chart")
    require(plain.previewDisplay.windowTitle == NativeLocalization.text("Preview"), "empty title falls back to Preview")
    plain.playFromStart()
    require(!plain.previewDisplay.isPlaying && plain.previewDisplay.chart.lanes.isEmpty, "play with no document stays empty")
    plain.stopPlayback()
    bmson.stopPlayback()
}

@MainActor
private func testTimingIndexMatchesTheAudioClock() {
    let cases: [(String, PreviewAudioTiming, Double)] = [
        ("steady", bpm120, 0),
        ("from-later", bpm120, 5),
        ("stop-plateau", PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 2, durationSeconds: 1)]), 0),
        (
            "same-beat-stop-then-bpm",
            PreviewAudioTiming(
                headerBPM: 120,
                bpmEvents: [(beat: 4, bpm: 240)],
                stopEvents: [(beat: 4, durationSeconds: 1)]
            ),
            0
        ),
        (
            "origin-bpm-before-stop",
            PreviewAudioTiming(
                headerBPM: 120,
                bpmEvents: [(beat: 4, bpm: 240)],
                stopEvents: [(beat: 4, durationSeconds: 1)]
            ),
            4
        ),
        ("no-events", PreviewAudioTiming(headerBPM: 90, bpmEvents: [], stopEvents: []), 3),
        (
            "ignored-junk",
            PreviewAudioTiming(
                headerBPM: .nan,
                bpmEvents: [(beat: .nan, bpm: 10), (beat: 2, bpm: 0), (beat: 2, bpm: 180), (beat: 2, bpm: 200)],
                stopEvents: [(beat: 1, durationSeconds: 0), (beat: .infinity, durationSeconds: 1), (beat: 2, durationSeconds: 0.5)]
            ),
            0
        ),
        (
            "infinite-bpm-becomes-header-speed",
            PreviewAudioTiming(headerBPM: 180, bpmEvents: [(beat: 0, bpm: .infinity)], stopEvents: []),
            0
        ),
        (
            "infinite-stop",
            PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 2, durationSeconds: .infinity)]),
            0
        )
    ]
    let samples = [0.0, 0.05, 1, 1.5, 2, 2.5, 3, 3.5, 8, -1, .nan, .infinity]
    for (name, timing, origin) in cases {
        var index = PreviewTimingIndex(timing: timing, fromBeat: origin)
        for seconds in samples {
            let got = index.beat(afterSeconds: seconds)
            let expected = LegacyPreviewAudio.beat(afterSeconds: seconds, fromBeat: origin, timing: timing)
            require(abs(got - expected) < 0.000_001 || (got.isNaN && expected.isNaN), "\(name) \(seconds)s got \(got) reference \(expected)")
            let beat = seconds.isFinite ? got : origin
            let bpm = index.activeBPM(at: beat)
            require(abs(bpm - referenceBPM(at: beat, timing: timing)) < 0.000_001, "\(name) bpm at \(beat)")
        }
        var missingOrigin = PreviewTimingIndex(timing: timing, fromBeat: .nan)
        require(missingOrigin.beat(afterSeconds: 2).isNaN, "\(name) keeps a non-finite origin")
    }

    var random = SplitMix64(state: 0xD4_71_3E)
    var bpmEvents: [(beat: Double, bpm: Double)] = []
    var stopEvents: [(beat: Double, durationSeconds: Double)] = []
    var cursor = 0.0
    for index in 0..<12_000 {
        cursor += 0.25 + random.unit()
        if index.isMultiple(of: 17) {
            let shared = cursor
            bpmEvents.append((shared, 80 + random.unit() * 160))
            stopEvents.append((shared, 0.02 + random.unit() * 0.08))
        } else if index.isMultiple(of: 2) {
            bpmEvents.append((cursor, 40 + random.unit() * 220))
        } else {
            stopEvents.append((cursor, 0.01 + random.unit() * 0.15))
        }
    }
    bpmEvents.append((1, .nan))
    stopEvents.append((1, -1))
    let dense = PreviewAudioTiming(headerBPM: 120, bpmEvents: bpmEvents, stopEvents: stopEvents)
    let origins = [0.0, 40.0, cursor * 0.5]
    for origin in origins {
        var index = PreviewTimingIndex(timing: dense, fromBeat: origin)
        let before = index.queryComparisons
        var worst = 0.0
        for _ in 0..<240 {
            let seconds = random.unit() * 4_000
            let got = index.beat(afterSeconds: seconds)
            let expected = LegacyPreviewAudio.beat(afterSeconds: seconds, fromBeat: origin, timing: dense)
            worst = max(worst, abs(got - expected))
            let bpm = index.activeBPM(at: got)
            require(abs(bpm - referenceBPM(at: got, timing: dense)) < 0.000_001, "dense bpm drifted at beat \(got)")
        }
        require(worst < 0.000_1, "dense beat drifted by \(worst) from origin \(origin)")
        let comparisons = index.queryComparisons - before
        let perQuery = Double(comparisons) / 240
        require(perQuery <= 64, "dense origin \(origin) averaged \(perQuery) comparisons over 240 queries (\(comparisons) total)")
        require(comparisons < 240 * bpmEvents.count, "dense queries walked the BPM table once per query: \(comparisons)")
    }
}

@MainActor
private func testDenseTimingTicksStayLogarithmic() {
    var bpmEvents: [(beat: Double, bpm: Double)] = []
    var stopEvents: [(beat: Double, durationSeconds: Double)] = []
    for index in 0..<20_000 {
        let beat = Double(index) * 0.5
        if index.isMultiple(of: 2) {
            bpmEvents.append((beat, index.isMultiple(of: 4) ? 180 : 90))
            stopEvents.append((beat, 0.05))
        }
    }
    let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: bpmEvents, stopEvents: stopEvents)
    var chart = stageChart(title: "Dense")
    chart.endBeat = 1_000_000
    let (controller, state) = makeController {
        context(chart: chart, timing: timing, playHere: 12, bmson: false)
    }
    controller.playFromPointer()
    let charts = controller.previewBGAChartUpdates
    let afterBind = controller.previewTimingQueryComparisons
    require(abs(controller.previewDisplay.beat - 12) < 0.000_001, "dense play starts at the cursor")
    require(abs(controller.previewDisplay.bgaFromBeat - 12) < 0.000_001, "BGA origin is the cursor")
    var previous = afterBind
    for step in 1...30 {
        let seconds = Double(step) * 0.2
        state.previewPlayer.onElapsedSeconds?(seconds)
        let display = controller.previewDisplay
        let expected = LegacyPreviewAudio.beat(afterSeconds: seconds, fromBeat: 12, timing: timing)
        require(abs(display.beat - expected) < 0.000_1, "tick \(step) beat \(display.beat) reference \(expected)")
        require(abs(display.bgaBeat - display.beat) < 0.000_001, "BGA uses the same beat")
        require(abs(display.bgaElapsedSeconds - display.elapsedSeconds) < 0.000_001, "BGA uses the same elapsed")
        require(display.isPlaying && display.bgaIsPlaying, "dense tick stays playing")
        let delta = controller.previewTimingQueryComparisons - previous
        require(delta > 0 && delta <= 80, "tick \(step) comparisons \(delta)")
        previous = controller.previewTimingQueryComparisons
    }
    require(controller.previewBGAChartUpdates == charts, "dense ticks must not rebind the chart")
    let chartsAtEnd = controller.previewBGAChartUpdates
    state.previewPlayer.onTimelineFinished?()
    require(!controller.previewDisplay.isPlaying && controller.previewDisplay.isFinished, "dense chart can finish")
    require(controller.previewBGAChartUpdates == chartsAtEnd, "finishing the dense chart must not rebind BGA")
    controller.stopPlayback()
}

@MainActor
private func testUbmStageTimingAndRate() {
    var fetches = 0
    var beatReports = 0
    var current = context(
        chart: stageChart(title: "Single"),
        timing: bpm120,
        playHere: 0,
        bmson: false,
        documentData: Data("#TITLE Single\n#PLAYER 1\n#PLAYLEVEL 12\n#RANK 3\n".utf8)
    )
    let (controller, _) = makeController(source: {
        fetches += 1
        return current
    }, onBeat: { value in
        if value != nil { beatReports += 1 }
    })
    func tap(_ text: String) {
        controller.previewSendKeyDown(keyEvent(text, window: controller.window))
        controller.previewSendKeyUp(keyEvent(text, window: controller.window, keyUp: true))
    }
    func spin() {
        pump(0.02)
        if controller.previewDisplay.isPlaying {
            controller.stepPresentationDisplayLink()
        }
    }
    layout(controller, size: NSSize(width: 587, height: 256))
    let idleFrames = controller.previewPresentedFrameCount
    pump(0.08)
    require(controller.previewPresentedFrameCount == idleFrames, "an idle window does not present")
    let native = controller.previewLayout
    require(!native.packed && abs(native.stageScale - 1) < 0.001, "native stage \(native)")
    require(abs(native.playfieldFrame.minX - 15) < 0.5 && abs(native.playfieldFrame.width - 158) < 0.5, "1P \(native.playfieldFrame)")
    require(abs(native.bgaFrame.minX - 173) < 0.5 && abs(native.bgaFrame.width - 256) < 0.5, "BGA \(native.bgaFrame)")
    require(abs(native.secondPlayfieldFrame.minX - 429) < 0.5 && abs(native.secondPlayfieldFrame.width - 158) < 0.5, "2P \(native.secondPlayfieldFrame)")
    guard let content = controller.window?.contentView,
          let primary = find(id: "PreviewPlayfield", in: content) as? PreviewPlayfieldView,
          let secondary = find(id: "PreviewPlayfieldSecondary", in: content) as? PreviewPlayfieldView,
          let primaryClip = find(id: "PreviewPlayfieldClip", in: content),
          let secondaryClip = find(id: "PreviewPlayfieldClipSecondary", in: content)
    else {
        fail("missing a stage surface")
    }
    require(abs(primary.bounds.width - 331) < 1 && abs(secondary.bounds.width - 331) < 1, "both views stay 331 wide")
    require(abs(primaryClip.bounds.width - 158) < 1 && abs(secondaryClip.bounds.width - 158) < 1, "clips are the 158px panels")
    require(abs(secondary.frame.minX - (-173)) < 1, "2P view offset \(secondary.frame)")
    require(primaryClip.layer?.masksToBounds == true && secondaryClip.layer?.masksToBounds == true, "clips mask the full 331 image")
    let primaryLanes = controller.previewPlayfieldScene().lanes
    let secondaryLanes = controller.previewSecondaryScene().lanes
    require(primaryLanes.contains { $0.player == 1 && $0.rect.maxX <= 158 }, "1P lanes stay in the native panel")
    require(primaryLanes.contains { $0.player == 2 && $0.rect.minX >= 173 }, "2P lanes stay at the native seed")
    require(secondaryLanes.map(\.id) == primaryLanes.map(\.id), "the side view draws the same lanes")
    _ = primary.drawMetalViewNow()
    _ = secondary.drawMetalViewNow()
    let primaryReadback = primary.renderMetalReadback()
    let secondaryReadback = secondary.renderMetalReadback()
    require(primaryReadback.usedMetal && secondaryReadback.usedMetal, "stage readback left Metal \(primaryReadback.failure ?? "") \(secondaryReadback.failure ?? "")")
    let leftBand = pixelHash(primaryReadback, nativeX: 0, nativeWidth: 158)
    let rightBand = pixelHash(primaryReadback, nativeX: 173, nativeWidth: 158)
    require(leftBand != rightBand, "1P and 2P panels are not the same pixels")
    require(pixelHash(secondaryReadback, nativeX: 0, nativeWidth: 158) == leftBand, "the side view repeats the native 331 image")
    let sample = primaryReadback.components(x: 4, y: primaryReadback.height / 2)
    let sampleTwin = secondaryReadback.components(x: 4, y: secondaryReadback.height / 2)
    let pixelsMatch = sample != nil && sampleTwin != nil
        && abs((sample?.r ?? 0) - (sampleTwin?.r ?? 1)) < 0.04
        && abs((sample?.g ?? 0) - (sampleTwin?.g ?? 1)) < 0.04
        && abs((sample?.b ?? 0) - (sampleTwin?.b ?? 1)) < 0.04
    require(pixelsMatch, "a native pixel matches on both views")

    layout(controller, size: NSSize(width: 1800, height: 800))
    let triple = controller.previewLayout
    require(abs(triple.stageScale - 3) < 0.001, "3x scale \(triple.stageScale)")
    require(abs(triple.playfieldFrame.minX - 64.5) < 1 && abs(triple.playfieldFrame.minY - 16) < 1, "3x letterbox \(triple.playfieldFrame)")
    require(abs(triple.bgaFrame.minX - 538.5) < 1 && abs(triple.bgaFrame.width - 768) < 1, "3x BGA \(triple.bgaFrame)")
    require(abs(triple.playfieldFrame.height - triple.bgaFrame.height) < 1, "3x does not stretch the stage")
    require(abs(primary.bounds.width - 331 * 3) < 1, "3x keeps native note pixels inside the 331 view")

    layout(controller, size: NSSize(width: 587, height: 256))
    let bgaBeforeSide = controller.previewLayout.bgaFrame
    let chartsBeforeSide = controller.previewBGAChartUpdates
    selectSide(controller, segment: 1)
    require(Set(controller.previewPlayfieldScene().lanes.map(\.player)) == [1], "1P hides 2P lanes")
    require(Set(controller.previewSecondaryScene().lanes.map(\.player)) == [1], "the side view follows 1P")
    require(controller.previewLayout.bgaFrame == bgaBeforeSide, "1P does not move the BGA")
    selectSide(controller, segment: 2)
    require(Set(controller.previewPlayfieldScene().lanes.map(\.player)) == [2], "2P hides 1P lanes")
    require(controller.previewLayout.bgaFrame == bgaBeforeSide, "2P does not move the BGA")
    selectSide(controller, segment: 0)
    require(Set(controller.previewPlayfieldScene().lanes.map(\.player)) == [1, 2], "Both restores both panels")
    require(controller.previewBGAChartUpdates == chartsBeforeSide, "side switches rebind the chart")

    let chartsBeforeF2 = controller.previewBGAChartUpdates
    tap(functionKey(PreviewUbmFunctionScalar.f2))
    let packed = controller.previewLayout
    require(packed.packed, "F2 packs when #PLAYER is 1")
    require(abs(packed.playfieldFrame.minX) < 0.5 && abs(packed.playfieldFrame.width - 331) < 0.5, "packed playfield \(packed.playfieldFrame)")
    require(abs(packed.bgaFrame.minX - 331) < 0.5 && abs(packed.bgaFrame.width - 256) < 0.5, "packed BGA \(packed.bgaFrame)")
    require(packed.secondPlayfieldFrame == .zero, "the second strip is hidden while packed")
    require(!controller.previewDisplay.isPlaying, "F2 does not start playback")
    require(controller.previewBGAChartUpdates == chartsBeforeF2, "F2 rebinds the chart")
    tap(functionKey(PreviewUbmFunctionScalar.f2))
    require(!controller.previewLayout.packed && abs(controller.previewLayout.bgaFrame.minX - 173) < 0.5, "F2 returns the centered BGA")

    let (doublePlay, _) = makeController {
        context(
            chart: stageChart(title: "DP"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE DP\n#PLAYER 3\n#PLAYLEVEL 7\n#RANK 4\n".utf8)
        )
    }
    layout(doublePlay, size: NSSize(width: 587, height: 256))
    require(doublePlay.previewLayout.packed && abs(doublePlay.previewLayout.bgaFrame.minX - 331) < 0.5, "PLAYER 3 stays packed")
    doublePlay.previewSendKeyDown(keyEvent(functionKey(PreviewUbmFunctionScalar.f2), window: doublePlay.window))
    doublePlay.previewSendKeyUp(keyEvent(functionKey(PreviewUbmFunctionScalar.f2), window: doublePlay.window, keyUp: true))
    require(doublePlay.previewLayout.packed, "F2 cannot separate PLAYER 3")
    doublePlay.previewSendKeyDown(keyEvent("9", window: doublePlay.window))
    doublePlay.previewSendKeyUp(keyEvent("9", window: doublePlay.window, keyUp: true))
    require(doublePlay.previewInfoText.contains("LEVEL 7") && doublePlay.previewInfoText.contains("RANK 4"), "DP header \(doublePlay.previewInfoText)")
    doublePlay.stopPlayback()

    let (couple, _) = makeController {
        context(
            chart: stageChart(title: "Couple"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Couple\n#PLAYER 2\n".utf8)
        )
    }
    layout(couple, size: NSSize(width: 587, height: 256))
    require(!couple.previewLayout.packed && abs(couple.previewLayout.bgaFrame.minX - 173) < 0.5, "PLAYER 2 stays separated")
    couple.stopPlayback()

    let (jsonChart, _) = makeController {
        context(
            chart: stageChart(title: "JSON"),
            timing: bpm120,
            playHere: 0,
            bmson: true,
            documentData: Data("{\"version\":\"1.0.0\"}".utf8)
        )
    }
    layout(jsonChart, size: NSSize(width: 587, height: 256))
    require(!jsonChart.previewLayout.packed, "JSON is not invented as PLAYER 3")
    jsonChart.previewSendKeyDown(keyEvent("9", window: jsonChart.window))
    jsonChart.previewSendKeyUp(keyEvent("9", window: jsonChart.window, keyUp: true))
    require(!jsonChart.previewInfoText.contains("LEVEL") && !jsonChart.previewInfoText.contains("RANK"), "JSON has no placeholder header \(jsonChart.previewInfoText)")
    jsonChart.stopPlayback()

    var stopped = stageChart(title: "Stop")
    stopped.notes = [
        PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4),
        PreviewVisualNote(laneID: "1p-k3", startBeat: 6, endBeat: 6),
        PreviewVisualNote(laneID: "1p-k2", startBeat: 8, endBeat: 8)
    ]
    current = context(
        chart: stopped,
        timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 4, durationSeconds: 1)]),
        playHere: 0,
        bmson: false,
        documentData: Data("#TITLE Stop\n#PLAYER 1\n".utf8)
    )
    controller.playFromStart()
    let playingDeadline = Date().addingTimeInterval(2)
    while Date() < playingDeadline, !controller.previewDisplay.isPlaying {
        pump(0.02)
    }
    require(controller.previewDisplay.isPlaying, "the STOP chart did not start")
    let fetchesAtPlay = fetches
    let chartsAtPlay = controller.previewBGAChartUpdates
    var didHome = false
    var sawFrozenMark = false
    var frozenMarkY: CGFloat?
    var sawStopBlock = false
    var sawStopRelease = false
    let stopDeadline = Date().addingTimeInterval(12)
    while Date() < stopDeadline, !sawStopRelease {
        spin()
        let elapsed = controller.previewDisplay.elapsedSeconds
        let beat = controller.previewDisplay.beat
        if !didHome, beat > 1, elapsed < 1.8 {
            didHome = true
            tap(functionKey(PreviewUbmFunctionScalar.home))
            require(fetches == fetchesAtPlay, "Home re-read the document")
            require(controller.previewBGAChartUpdates == chartsAtPlay, "Home rebinds the chart")
            require(controller.previewDisplay.beat < 0.35, "Home returns to the start, beat \(controller.previewDisplay.beat)")
            continue
        }
        let scene = controller.previewPlayfieldScene()
        let twin = controller.previewSecondaryScene()
        if elapsed >= 2.2, elapsed < 2.85 {
            require(abs(beat - 4) < 0.05, "STOP holds beat 4, got \(beat)")
            require(abs(scene.playbackBeat - twin.playbackBeat) < 0.001, "both views share the frozen beat")
            let mark = scene.marks.first { $0.laneID == "1p-k2" }?.rect.minY
            let twinMark = twin.marks.first { $0.laneID == "1p-k2" }?.rect.minY
            require(mark != nil && mark == twinMark, "the future note matches on both views")
            if let frozenMarkY {
                require(abs((mark ?? 0) - frozenMarkY) < 0.5, "the note frame moved during STOP")
                sawFrozenMark = true
            } else {
                frozenMarkY = mark
            }
        }
        let earlyHit = scene.hits.contains { $0.laneID == "1p-k3" }
        if elapsed >= 3.2, elapsed < 3.8 {
            require(!earlyHit, "the note after STOP exploded early")
            require(!twin.hits.contains { $0.laneID == "1p-k3" }, "the side view exploded early")
            sawStopBlock = true
        }
        if elapsed >= 4.03, elapsed < 4.2, earlyHit {
            sawStopRelease = true
            require(twin.hits.contains { $0.laneID == "1p-k3" }, "the side view missed the post-STOP hit")
        }
    }
    require(didHome, "Home did not run")
    require(sawFrozenMark && sawStopBlock && sawStopRelease, "STOP timeline frozen \(sawFrozenMark) blocked \(sawStopBlock) released \(sawStopRelease)")
    require(beatReports == 0, "ticks reported beats to the editor")
    controller.stopPlayback()

    var rushed = stageChart(title: "Rush")
    rushed.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 6, endBeat: 6)]
    current = context(
        chart: rushed,
        timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: [(beat: 4, bpm: 240)]),
        playHere: 0,
        bmson: false,
        documentData: Data("#TITLE Rush\n#PLAYER 1\n".utf8)
    )
    controller.playFromStart()
    var sawBPMHit = false
    let bpmDeadline = Date().addingTimeInterval(6)
    while Date() < bpmDeadline, !sawBPMHit {
        pump(0.02)
        if controller.previewDisplay.isPlaying {
            controller.stepPresentationDisplayLink()
        }
        let elapsed = controller.previewDisplay.elapsedSeconds
        guard elapsed >= 2.55, elapsed < 2.9 else { continue }
        let scene = controller.previewPlayfieldScene()
        let twin = controller.previewSecondaryScene()
        if scene.hits.contains(where: { $0.laneID == "1p-k1" }) {
            require(twin.hits.contains { $0.laneID == "1p-k1" }, "BPM arrival differs between views")
            require(controller.previewDisplay.beat > 6, "the 240 change did not move the beat, \(controller.previewDisplay.beat)")
            sawBPMHit = true
        }
    }
    require(sawBPMHit, "the BPM change did not bring the note in before a flat 120 clock")
    let pausedBeat = controller.previewDisplay.beat
    let presented = controller.previewPresentedFrameCount
    tap("0")
    require(controller.previewDisplay.isPaused && controller.previewChartPaused, "pause matches the engine")
    hidePreview(controller)
    pump(0.25)
    require(controller.previewPictureSuppressed, "hiding uses the real occlusion state")
    require(!controller.previewDisplayLinkAttached, "a hidden window detaches the display link")
    require(abs(controller.previewDisplay.beat - pausedBeat) < 0.001, "a hidden pause holds the beat")
    require(controller.previewPresentedFrameCount == presented, "a hidden pause does not present")
    controller.stopPlayback()

    var rated = stageChart(title: "Rate")
    rated.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 0, endBeat: 0)]
    let (rateController, rateState) = makeController {
        context(
            chart: rated,
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Rate\n#PLAYER 1\n".utf8)
        )
    }
    layout(rateController, size: NSSize(width: 587, height: 256))
    rateState.previewPlayer.setPlaybackRate(2)
    rateController.playFromStart()
    var sawRate = false
    let rateDeadline = Date().addingTimeInterval(3)
    while Date() < rateDeadline, !sawRate {
        pump(0.02)
        if rateController.previewDisplay.isPlaying {
            rateController.stepPresentationDisplayLink()
        }
        let wall = rateState.previewPlayer.playbackWallElapsedSeconds()
        let chart = rateController.previewDisplay.elapsedSeconds
        guard wall >= 0.04, wall <= 0.11, chart > wall * 1.6 else { continue }
        let scene = rateController.previewPlayfieldScene()
        guard abs(scene.elapsedSeconds - wall) < 0.05 else { continue }
        guard abs(rateController.previewDisplay.bgaElapsedSeconds - chart) < 0.000_1 else { continue }
        if let age = scene.hits.first(where: { $0.laneID == "1p-k1" })?.ageMilliseconds {
            let wallAge = wall * 1000
            let chartAge = chart * 1000
            guard abs(Double(age) - wallAge) + 20 < abs(Double(age) - chartAge) else { continue }
            sawRate = true
        }
    }
    require(sawRate, "RealHS did not split the chart clock from the effect clock")
    rateController.stopPlayback()
}

@MainActor
private func testUbmDualClockAndFullStageBGA() {
    let (layoutController, _) = makeController {
        context(
            chart: stageChart(title: "Layout"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Layout\n#PLAYER 1\n".utf8)
        )
    }
    let sizes: [(NSSize, CGFloat, CGFloat)] = [
        (NSSize(width: 587, height: 256), 1, 0),
        (NSSize(width: 1174, height: 512), 2, 0),
        (NSSize(width: 1800, height: 800), 3, 19.5)
    ]
    layout(layoutController, size: sizes[0].0)
    let chartsAtLayout = layoutController.previewBGAChartUpdates
    var scratchTaps = 0
    var separate = true
    for (size, scale, origin) in sizes {
        layout(layoutController, size: size)
        for _ in 0..<2 {
            for side in 0..<3 {
                selectSide(layoutController, segment: side)
                for _ in 0..<4 {
                    let placed = layoutController.previewLayout
                    let expectedOrigin = (separate ? 173.0 : 331.0) * scale + origin
                    require(abs(placed.nominalBGAFrame.minX - expectedOrigin) < 1.5, "nominal column \(placed.nominalBGAFrame) scale \(scale)")
                    require(abs(placed.nominalBGAFrame.width - 256 * scale) < 1.5, "nominal width \(placed.nominalBGAFrame)")
                    require(abs(placed.actualStageFrame.width - 587 * scale) < 1.5, "stage width \(placed.actualStageFrame)")
                    require(abs(placed.actualStageFrame.height - 256 * scale) < 1.5, "stage height \(placed.actualStageFrame)")
                    require(placed.nominalBGAFrame != placed.actualStageFrame, "nominal column collapsed into the stage")
                    require(placed.bgaFrame == placed.nominalBGAFrame, "the 256-column frame was dropped")
                    if separate {
                        require(!placed.packed && abs(placed.playfieldFrame.width - 158 * scale) < 1.5, "separate panel \(placed.playfieldFrame)")
                        require(abs(placed.secondPlayfieldFrame.width - 158 * scale) < 1.5, "2P panel missing")
                    } else {
                        require(placed.packed && abs(placed.playfieldFrame.width - 331 * scale) < 1.5, "packed panel \(placed.playfieldFrame)")
                        require(placed.secondPlayfieldFrame == .zero, "packed layout showed the second strip")
                    }
                    let scene = layoutController.previewPlayfieldScene()
                    require(scene.scratchRaw == scratchTaps % 4, "scratch \(scene.scratchRaw) after \(scratchTaps)")
                    let players = Set(scene.lanes.map(\.player))
                    let expectedPlayers: Set<Int> = side == 1 ? [1] : side == 2 ? [2] : [1, 2]
                    require(players == expectedPlayers, "side \(side) lanes \(players)")
                    require(layoutController.previewSecondaryScene().scratchRaw == scene.scratchRaw, "side view scratch diverged")
                    layoutController.previewSendKeyDown(keyEvent("8", window: layoutController.window))
                    layoutController.previewSendKeyUp(keyEvent("8", window: layoutController.window, keyUp: true))
                    scratchTaps += 1
                }
            }
            layoutController.previewSendKeyDown(keyEvent(functionKey(PreviewUbmFunctionScalar.f2), window: layoutController.window))
            layoutController.previewSendKeyUp(keyEvent(functionKey(PreviewUbmFunctionScalar.f2), window: layoutController.window, keyUp: true))
            separate.toggle()
        }
    }
    require(scratchTaps == 72, "layout combinations \(scratchTaps)")
    require(!layoutController.previewDisplay.isPlaying, "layout switches started playback")
    require(layoutController.previewBGAChartUpdates == chartsAtLayout, "layout switches called setChart")
    guard let layoutRoot = layoutController.window?.contentView,
          let bgaView = find(id: "PreviewBGA", in: layoutRoot),
          let clip = find(id: "PreviewPlayfieldClip", in: layoutRoot) else {
        fail("missing stage views")
    }
    let bgaIndex = layoutRoot.subviews.firstIndex(of: bgaView) ?? 0
    let clipIndex = layoutRoot.subviews.firstIndex(of: clip) ?? 0
    require(bgaIndex < clipIndex, "the full-stage BGA is above the notes")
    layoutController.stopPlayback()

    let (packedController, _) = makeController {
        context(
            chart: stageChart(title: "Packed"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Packed\n#PLAYER 3\n".utf8)
        )
    }
    layout(packedController, size: NSSize(width: 587, height: 256))
    let packedCharts = packedController.previewBGAChartUpdates
    require(packedController.previewLayout.packed && abs(packedController.previewLayout.nominalBGAFrame.minX - 331) < 1, "PLAYER 3 nominal column")
    require(abs(packedController.previewLayout.actualStageFrame.width - 587) < 1, "PLAYER 3 stage")
    packedController.previewSendKeyDown(keyEvent(functionKey(PreviewUbmFunctionScalar.f2), window: packedController.window))
    packedController.previewSendKeyUp(keyEvent(functionKey(PreviewUbmFunctionScalar.f2), window: packedController.window, keyUp: true))
    require(packedController.previewLayout.packed, "F2 unpacked PLAYER 3")
    require(packedController.previewBGAChartUpdates == packedCharts, "PLAYER 3 F2 called setChart")
    packedController.stopPlayback()

    let folder = URL(fileURLWithPath: "/tmp/ibms-uw5-bga", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    writeSolidPNG(folder.appendingPathComponent("red.png"), red: 0.9, green: 0.05, blue: 0.05)
    writeSolidPNG(folder.appendingPathComponent("blue.png"), red: 0.05, green: 0.15, blue: 0.9)
    writeBandPNG(folder.appendingPathComponent("wide.png"))
    func cropChart(player: Int) -> PreviewAudioDocumentContext {
        var chart = stageChart(title: "Crop \(player)")
        chart.bgaAssets = [
            PreviewBGAAsset(id: "00", fileName: "red.png"),
            PreviewBGAAsset(id: "01", fileName: "blue.png")
        ]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        let text = "#TITLE Crop\n#PLAYER \(player)\n#BMP00 red.png\n#BMP01 blue.png\n#BGA01 00 0 0 16 16 -30 0\n"
        return context(chart: chart, timing: bpm120, playHere: 0, bmson: false, directory: folder, documentData: Data(text.utf8))
    }
    func wideChart(player: Int) -> PreviewAudioDocumentContext {
        var chart = stageChart(title: "Wide \(player)")
        chart.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "wide.png")]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        let text = "#TITLE Wide\n#PLAYER \(player)\n#BMP01 wide.png\n"
        return context(chart: chart, timing: bpm120, playHere: 0, bmson: false, directory: folder, documentData: Data(text.utf8))
    }
    let cropSizes: [(NSSize, CGFloat)] = [
        (NSSize(width: 587, height: 256), 1),
        (NSSize(width: 1174, height: 512), 2),
        (NSSize(width: 1800, height: 800), 3)
    ]
    for player in [1, 3] {
        let (cropController, _) = makeController { cropChart(player: player) }
        for (size, scale) in cropSizes {
            layout(cropController, size: size)
            guard let view = find(id: "PreviewBGA", in: cropController.window?.contentView) as? PreviewBGAView else {
                fail("missing crop BGA")
            }
            let ready = Date().addingTimeInterval(2)
            while Date() < ready, !view.inspection().baseImageReady {
                pump(0.02)
            }
            require(view.inspection().baseImageReady, "crop image did not decode for PLAYER \(player)")
            let bitmap = renderedPixels(view)
            let origin = player == 3 ? 331.0 : 173.0
            let redX = Int(((origin - 30) * scale).rounded()) + 4
            require(bitmapHasColor(bitmap, x: redX, red: 200, green: 40, blue: 40), "alias BMP00 was not drawn at \(redX) scale \(scale) player \(player)")
            let columnX = Int(((origin + 80) * scale).rounded())
            require(bitmapHasColor(bitmap, x: columnX, red: 8, green: 8, blue: 8, alphaAtLeast: 200), "nominal column is not black at \(columnX)")
            require(!bitmapHasColor(bitmap, x: 4, red: 200, green: 40, blue: 40), "the crop covered the left margin")
        }
        cropController.stopPlayback()
        let (wideController, _) = makeController { wideChart(player: player) }
        layout(wideController, size: NSSize(width: 587, height: 256))
        guard let wideView = find(id: "PreviewBGA", in: wideController.window?.contentView) as? PreviewBGAView else {
            fail("missing wide BGA")
        }
        let wideReady = Date().addingTimeInterval(2)
        while Date() < wideReady, !wideView.inspection().baseImageReady {
            pump(0.02)
        }
        require(wideView.inspection().baseImageReady, "wide image did not decode")
        let widePixels = renderedPixels(wideView)
        let wideOrigin = player == 3 ? 331 : 173
        let greenX = wideOrigin - 128 + 4
        require(bitmapHasColor(widePixels, x: greenX, red: 20, green: 180, blue: 40), "512-wide image was scaled into the column, green \(greenX)")
        if player == 1 {
            require(bitmapHasColor(widePixels, x: 545, red: 20, green: 40, blue: 180), "the wide image did not keep its right edge")
        }
        require(abs(wideController.previewLayout.nominalBGAFrame.width - 256) < 1, "wide image changed the nominal column")
        require(abs(wideController.previewLayout.actualStageFrame.width - 587) < 1, "wide image changed the stage")
        wideController.stopPlayback()
    }

    var clockChart = stageChart(title: "Clock")
    clockChart.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4)]
    let (clock, clockState) = makeController {
        context(
            chart: clockChart,
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Clock\n#PLAYER 1\n".utf8)
        )
    }
    layout(clock, size: NSSize(width: 587, height: 256))
    func tapClock(_ text: String) {
        clock.previewSendKeyDown(keyEvent(text, window: clock.window))
        clock.previewSendKeyUp(keyEvent(text, window: clock.window, keyUp: true))
    }
    for _ in 0..<4 { tapClock("4") }
    require(clock.previewRealHS == 200, "RealHS \(clock.previewRealHS)")
    require(abs(clockState.previewPlayer.requestedPlaybackRate - 2) < 0.001, "player rate \(clockState.previewPlayer.requestedPlaybackRate)")
    guard let menu = clock.window?.contentView?.menu?.items.first(where: { $0.identifier?.rawValue == "PreviewRealHSMenu" }) else {
        fail("missing RealHS menu")
    }
    require(menu.title.contains("2.00"), "menu does not show the player rate \(menu.title)")
    clock.playFromStart()
    let startDeadline = Date().addingTimeInterval(2)
    while Date() < startDeadline, !clock.previewDisplay.isPlaying {
        pump(0.02)
    }
    require(clock.previewDisplay.isPlaying, "2x chart did not start")
    var earlyHash: Int?
    var sawArrival = false
    let arrivalDeadline = Date().addingTimeInterval(4)
    while Date() < arrivalDeadline, !sawArrival {
        pump(0.02)
        clock.stepPresentationDisplayLink()
        let wall = clockState.previewPlayer.playbackWallElapsedSeconds()
        let chartSeconds = clock.previewDisplay.elapsedSeconds
        guard let view = find(id: "PreviewPlayfield", in: clock.window?.contentView) as? PreviewPlayfieldView else {
            fail("missing clock playfield")
        }
        if wall > 0.15, wall < 0.45, earlyHash == nil {
            _ = view.drawMetalViewNow()
            let readback = view.renderMetalReadback()
            require(readback.usedMetal, "early readback left Metal")
            earlyHash = pixelHash(readback, nativeX: 0, nativeWidth: 158)
        }
        guard wall >= 0.92, wall <= 1.12, chartSeconds > wall * 1.7 else { continue }
        let scene = clock.previewPlayfieldScene()
        guard abs(scene.playbackBeat - 4) < 0.25,
              let hit = scene.hits.first(where: { $0.laneID == "1p-k1" }) else { continue }
        guard PreviewUbmStyle.beamVisible(ageMilliseconds: hit.ageMilliseconds),
              PreviewUbmStyle.bombVisible(ageMilliseconds: hit.ageMilliseconds, isLong: false) else { continue }
        guard let twin = clock.previewSecondaryScene().hits.first(where: { $0.laneID == "1p-k1" }),
              abs(twin.ageMilliseconds - hit.ageMilliseconds) <= 1 else { continue }
        _ = view.drawMetalViewNow()
        let readback = view.renderMetalReadback()
        guard readback.usedMetal, !readback.bgra.isEmpty, let earlyHash else { continue }
        let arrivalHash = pixelHash(readback, nativeX: 0, nativeWidth: 158)
        guard arrivalHash != earlyHash else { continue }
        sawArrival = true
    }
    require(sawArrival, "beat 4 at 2x did not reach the line with beam and bomb")
    let rateAtHit = clockState.previewPlayer.requestedPlaybackRate
    let pausedAge = clock.previewPlayfieldScene().hits.first { $0.laneID == "1p-k1" }?.ageMilliseconds
    let pausedWall = clockState.previewPlayer.playbackWallElapsedSeconds()
    tapClock("0")
    require(clock.previewChartPaused, "pause did not reach the engine")
    pump(0.3)
    require(abs(clockState.previewPlayer.requestedPlaybackRate - rateAtHit) < 0.001, "pause reset the rate")
    require(clock.previewRealHS == 200, "pause reset RealHS")
    require(abs(clockState.previewPlayer.playbackWallElapsedSeconds() - pausedWall) < 0.02, "pause did not freeze the wall clock")
    require(clock.previewPlayfieldScene().hits.first { $0.laneID == "1p-k1" }?.ageMilliseconds == pausedAge, "pause aged the effect")
    let chartsWhilePlaying = clock.previewBGAChartUpdates
    tapClock(functionKey(PreviewUbmFunctionScalar.f2))
    require(clock.previewLayout.packed, "F2 during playback did not pack")
    require(clock.previewDisplay.isPlaying == false && clock.previewChartPaused, "F2 resumed or restarted playback")
    require(clock.previewBGAChartUpdates == chartsWhilePlaying, "F2 during playback called setChart")
    clock.stopPlayback()
    require(abs(clockState.previewPlayer.requestedPlaybackRate - 2) < 0.001, "stop reset the rate")

    var halfChart = stageChart(title: "Half")
    halfChart.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4)]
    let (half, halfState) = makeController {
        context(chart: halfChart, timing: bpm120, playHere: 0, bmson: false, documentData: Data("#TITLE Half\n#PLAYER 1\n".utf8))
    }
    layout(half, size: NSSize(width: 587, height: 256))
    for _ in 0..<2 {
        half.previewSendKeyDown(keyEvent("3", window: half.window))
        half.previewSendKeyUp(keyEvent("3", window: half.window, keyUp: true))
    }
    require(half.previewRealHS == 50, "half RealHS \(half.previewRealHS)")
    require(abs(halfState.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "half rate \(halfState.previewPlayer.requestedPlaybackRate)")
    half.playFromStart()
    var sawHalf = false
    let halfDeadline = Date().addingTimeInterval(8)
    while Date() < halfDeadline, !sawHalf {
        pump(0.02)
        if half.previewDisplay.isPlaying { half.stepPresentationDisplayLink() }
        let wall = halfState.previewPlayer.playbackWallElapsedSeconds()
        let chartSeconds = half.previewDisplay.elapsedSeconds
        guard wall >= 3.9, wall <= 4.2, chartSeconds < wall * 0.7 else { continue }
        guard let hit = half.previewPlayfieldScene().hits.first(where: { $0.laneID == "1p-k1" }),
              PreviewUbmStyle.beamVisible(ageMilliseconds: hit.ageMilliseconds),
              PreviewUbmStyle.bombVisible(ageMilliseconds: hit.ageMilliseconds, isLong: false),
              abs(half.previewDisplay.beat - 4) < 0.3 else { continue }
        sawHalf = true
    }
    require(sawHalf, "0.5x did not put beat 4 on the line at about 4 wall seconds")
    half.stopPlayback()
    require(abs(halfState.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "stopping the slow chart reset the rate")

    var quadChart = stageChart(title: "Quad")
    quadChart.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4)]
    let (quad, quadState) = makeController {
        context(chart: quadChart, timing: bpm120, playHere: 0, bmson: false, documentData: Data("#TITLE Quad\n#PLAYER 1\n".utf8))
    }
    layout(quad, size: NSSize(width: 587, height: 256))
    for _ in 0..<12 {
        quad.previewSendKeyDown(keyEvent("4", window: quad.window))
        quad.previewSendKeyUp(keyEvent("4", window: quad.window, keyUp: true))
    }
    require(quad.previewRealHS == 400, "4x RealHS \(quad.previewRealHS)")
    require(abs(quadState.previewPlayer.requestedPlaybackRate - 4) < 0.001, "4x engine rate \(quadState.previewPlayer.requestedPlaybackRate)")
    quad.playFromStart()
    var sawQuad = false
    let quadDeadline = Date().addingTimeInterval(3)
    while Date() < quadDeadline, !sawQuad {
        pump(0.02)
        if quad.previewDisplay.isPlaying { quad.stepPresentationDisplayLink() }
        let wall = quadState.previewPlayer.playbackWallElapsedSeconds()
        let chartSeconds = quad.previewDisplay.elapsedSeconds
        guard wall >= 0.40, wall <= 0.70, chartSeconds > wall * 3.2 else { continue }
        guard let hit = quad.previewPlayfieldScene().hits.first(where: { $0.laneID == "1p-k1" }),
              PreviewUbmStyle.beamVisible(ageMilliseconds: hit.ageMilliseconds),
              PreviewUbmStyle.bombVisible(ageMilliseconds: hit.ageMilliseconds, isLong: false),
              abs(quad.previewDisplay.beat - 4) < 0.35 else { continue }
        sawQuad = true
    }
    require(sawQuad, "4x did not put beat 4 on the line near half a wall second, beat \(quad.previewDisplay.beat) wall \(quadState.previewPlayer.playbackWallElapsedSeconds())")
    require(abs(quadState.previewPlayer.requestedPlaybackRate - 4) < 0.001, "4x playback changed the engine rate")
    quad.stopPlayback()

    var hereChart = stageChart(title: "Here")
    hereChart.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4)]
    let (here, _) = makeController {
        context(chart: hereChart, timing: bpm120, playHere: 4, bmson: false, documentData: Data("#TITLE Here\n#PLAYER 1\n".utf8))
    }
    layout(here, size: NSSize(width: 587, height: 256))
    let chartsBeforeHere = here.previewBGAChartUpdates
    here.playFromPointer()
    let hereDeadline = Date().addingTimeInterval(2)
    while Date() < hereDeadline, !here.previewDisplay.isPlaying {
        pump(0.02)
    }
    here.stepPresentationDisplayLink()
    let hereHit = here.previewPlayfieldScene().hits.first { $0.laneID == "1p-k1" }
    require(abs(here.previewDisplay.beat - 4) < 0.2, "Here beat \(here.previewDisplay.beat)")
    require(hereHit != nil && PreviewUbmStyle.beamVisible(ageMilliseconds: hereHit?.ageMilliseconds ?? -1), "Here did not light the note")
    require(PreviewUbmStyle.bombVisible(ageMilliseconds: hereHit?.ageMilliseconds ?? -1, isLong: false), "Here bomb was missing")
    let chartsAfterHere = here.previewBGAChartUpdates
    here.previewSendKeyDown(keyEvent(functionKey(PreviewUbmFunctionScalar.home), window: here.window))
    here.previewSendKeyUp(keyEvent(functionKey(PreviewUbmFunctionScalar.home), window: here.window, keyUp: true))
    let homeDeadline = Date().addingTimeInterval(2)
    while Date() < homeDeadline, !here.previewDisplay.isPlaying {
        pump(0.02)
    }
    require(here.previewBGAChartUpdates == chartsAfterHere, "seek called setChart")
    require(here.previewBGAChartUpdates >= chartsBeforeHere, "Here did not bind")
    require(here.previewDisplay.beat < 0.4, "Home after Here stayed at beat 4")
    here.stopPlayback()
}

@MainActor
private func testVideoRateFollowsEngine() {
    let folder = URL(fileURLWithPath: "/tmp/ibms-uw6-video", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let clip = folder.appendingPathComponent("rate.mp4")
    writeRateClip(clip, seconds: 8)

    func videoChart(title: String) -> PreviewChartSnapshot {
        var chart = stageChart(title: title)
        chart.notes = [PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4)]
        chart.bgaAssets = [PreviewBGAAsset(id: "V", fileName: clip.lastPathComponent)]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "V", layer: .base)]
        return chart
    }
    func tap(_ controller: PreviewWindowController, _ text: String, times: Int = 1) {
        for _ in 0..<times {
            controller.previewSendKeyDown(keyEvent(text, window: controller.window))
            controller.previewSendKeyUp(keyEvent(text, window: controller.window, keyUp: true))
        }
    }
    func bgaView(_ controller: PreviewWindowController) -> PreviewBGAView {
        guard let view = find(id: "PreviewBGA", in: controller.window?.contentView) as? PreviewBGAView else {
            fail("missing BGA view")
        }
        return view
    }
    func waitUntilPlaying(_ controller: PreviewWindowController) {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !controller.previewDisplay.isPlaying {
            pump(0.02)
        }
        require(controller.previewDisplay.isPlaying, "video chart did not start")
    }

    let (off, _) = makeController {
        context(chart: videoChart(title: "Off"), timing: bpm120, playHere: 0, bmson: false, directory: folder, documentData: Data("#TITLE Off\n#PLAYER 1\n".utf8))
    }
    layout(off, size: NSSize(width: 587, height: 256))
    tap(off, "5", times: 2)
    require(bgaView(off).inspection().displayMode == 0, "two BGA key presses did not reach Off, mode \(bgaView(off).inspection().displayMode)")
    tap(off, "4", times: 4)
    require(off.previewRealHS == 200, "Off chart RealHS \(off.previewRealHS)")
    let opensBefore = bgaView(off).inspection().videoOpenCount
    off.playFromStart()
    waitUntilPlaying(off)
    pump(0.35)
    off.stepPresentationDisplayLink()
    tap(off, "4", times: 4)
    pump(0.2)
    let offState = bgaView(off).inspection()
    require(offState.videoOpenCount == opensBefore, "Off opened a video when the rate changed, opens \(offState.videoOpenCount)")
    require(!offState.videoAttached, "Off attached a video player")
    off.stopPlayback()

    let (clock, state) = makeController {
        context(chart: videoChart(title: "Rate"), timing: bpm120, playHere: 0, bmson: false, directory: folder, documentData: Data("#TITLE Rate\n#PLAYER 1\n".utf8))
    }
    layout(clock, size: NSSize(width: 587, height: 256))
    tap(clock, "4", times: 4)
    require(abs(state.previewPlayer.requestedPlaybackRate - 2) < 0.001, "engine did not reach 2x")
    let chartsAtStart = clock.previewBGAChartUpdates
    clock.playFromStart()
    waitUntilPlaying(clock)
    let readyDeadline = Date().addingTimeInterval(4)
    var readyRate: Float?
    while Date() < readyDeadline, readyRate == nil {
        pump(0.05)
        clock.stepPresentationDisplayLink()
        let sample = bgaView(clock).inspection()
        if sample.videoAttached, let rate = sample.videoRate, abs(Double(rate) - 2) < 0.2, sample.currentVideoSeconds != nil {
            readyRate = rate
        }
    }
    require(readyRate != nil, "engine 2x did not become a playing video rate, inspection \(bgaView(clock).inspection().videoRate ?? -1)")
    let first = videoProgress(bgaView(clock), controller: clock)
    pump(0.55)
    clock.stepPresentationDisplayLink()
    let second = videoProgress(bgaView(clock), controller: clock)
    let wall = second.uptime - first.uptime
    let media = second.media - first.media
    let ratio = wall > 0.2 ? media / wall : -1
    require(
        ratio > 1.6 && ratio < 2.5,
        "2x video media moved \(media) over wall \(wall), ratio \(ratio), seeks \(second.seeks - first.seeks), rate \(second.rate)"
    )
    require(abs(Double(second.rate) - 2) < 0.2, "playing video rate left 2x, rate \(second.rate)")
    require(second.opens == first.opens, "steady 2x playback reopened the video")
    require(clock.previewBGAChartUpdates == chartsAtStart, "playback called setChart again")
    let chartAtSample = clock.previewDisplay.elapsedSeconds
    tap(clock, functionKey(PreviewUbmFunctionScalar.f2))
    require(clock.previewBGAChartUpdates == chartsAtStart, "F2 rebound the video chart")
    require(clock.previewDisplay.isPlaying, "F2 stopped the video chart")
    require(clock.previewDisplay.elapsedSeconds + 0.02 >= chartAtSample, "F2 rewound the chart clock")

    let frozenMedia = bgaView(clock).inspection().currentVideoSeconds
    let frozenSeeks = bgaView(clock).inspection().videoSeekCount
    tap(clock, "0")
    require(clock.previewChartPaused, "pause did not reach the engine")
    let chartFrozen = clock.previewDisplay.elapsedSeconds
    let wallFrozen = state.previewPlayer.playbackWallElapsedSeconds()
    let effectFrozen = clock.previewPlayfieldScene().elapsedSeconds
    tap(clock, "4", times: 4)
    require(abs(state.previewPlayer.requestedPlaybackRate - 3) < 0.001, "paused rate change missed the engine, rate \(state.previewPlayer.requestedPlaybackRate)")
    require(clock.previewRealHS == 300, "paused RealHS \(clock.previewRealHS)")
    require(abs(bgaView(clock).inspection().requestedPlaybackRate - 3) < 0.001, "pause stored a zero video rate")
    let pauseStarted = ProcessInfo.processInfo.systemUptime
    pump(0.4)
    let paused = bgaView(clock).inspection()
    let pauseWall = ProcessInfo.processInfo.systemUptime - pauseStarted
    require(pauseWall >= 0.3, "pause wait was too short")
    require(
        abs((paused.currentVideoSeconds ?? -1) - (frozenMedia ?? -2)) < 0.08,
        "paused rate change moved video time from \(frozenMedia ?? -1) to \(paused.currentVideoSeconds ?? -1)"
    )
    require(paused.videoSeekCount <= frozenSeeks + 1, "paused rate change kept seeking, seeks \(paused.videoSeekCount)")
    require(abs(clock.previewDisplay.elapsedSeconds - chartFrozen) < 0.08, "pause dropped the chart integral")
    require(abs(state.previewPlayer.playbackWallElapsedSeconds() - wallFrozen) < 0.08, "pause dropped the wall integral")
    require(abs(clock.previewPlayfieldScene().elapsedSeconds - effectFrozen) < 0.001, "pause reset the effect clock")
    tap(clock, "0")
    waitUntilPlaying(clock)
    let resumedFirst = videoProgress(bgaView(clock), controller: clock)
    pump(0.45)
    clock.stepPresentationDisplayLink()
    let resumedSecond = videoProgress(bgaView(clock), controller: clock)
    let resumedWall = resumedSecond.uptime - resumedFirst.uptime
    let resumedMedia = resumedSecond.media - resumedFirst.media
    let resumedRatio = resumedWall > 0.2 ? resumedMedia / resumedWall : -1
    require(
        resumedRatio > 2.4 && resumedRatio < 3.6,
        "resumed 3x video media moved \(resumedMedia) over wall \(resumedWall), ratio \(resumedRatio), rate \(resumedSecond.rate)"
    )
    require(abs(Double(resumedSecond.rate) - 3) < 0.25, "resume did not play at the stored rate \(resumedSecond.rate)")
    clock.stopPlayback()

    let (fast, fastState) = makeController {
        context(chart: videoChart(title: "Fast"), timing: bpm120, playHere: 0, bmson: false, directory: folder, documentData: Data("#TITLE Fast\n#PLAYER 1\n".utf8))
    }
    layout(fast, size: NSSize(width: 587, height: 256))
    tap(fast, "4", times: 12)
    require(abs(fastState.previewPlayer.requestedPlaybackRate - 4) < 0.001, "4x video engine \(fastState.previewPlayer.requestedPlaybackRate)")
    fast.playFromStart()
    waitUntilPlaying(fast)
    let fastReady = Date().addingTimeInterval(4)
    var fastPlaying = false
    while Date() < fastReady, !fastPlaying {
        pump(0.05)
        fast.stepPresentationDisplayLink()
        let sample = bgaView(fast).inspection()
        if sample.videoAttached, let rate = sample.videoRate, rate > 3.2, sample.currentVideoSeconds != nil {
            fastPlaying = true
        }
    }
    require(fastPlaying, "4x engine was not applied to the video, rate \(bgaView(fast).inspection().videoRate ?? -1)")
    let fastFirst = videoProgress(bgaView(fast), controller: fast)
    pump(0.4)
    fast.stepPresentationDisplayLink()
    let fastSecond = videoProgress(bgaView(fast), controller: fast)
    let fastWall = fastSecond.uptime - fastFirst.uptime
    let fastMedia = fastSecond.media - fastFirst.media
    let fastRatio = fastWall > 0.15 ? fastMedia / fastWall : -1
    require(
        fastRatio > 3.2 && fastRatio < 4.8,
        "4x video media moved \(fastMedia) over wall \(fastWall), ratio \(fastRatio), rate \(fastSecond.rate)"
    )
    fast.stopPlayback()

    let (here, hereState) = makeController {
        context(chart: videoChart(title: "Here"), timing: bpm120, playHere: 4, bmson: false, directory: folder, documentData: Data("#TITLE Here\n#PLAYER 1\n".utf8))
    }
    layout(here, size: NSSize(width: 587, height: 256))
    tap(here, "4", times: 4)
    require(abs(hereState.previewPlayer.requestedPlaybackRate - 2) < 0.001, "Here engine rate \(hereState.previewPlayer.requestedPlaybackRate)")
    here.playFromPointer()
    waitUntilPlaying(here)
    let hereCharts = here.previewBGAChartUpdates
    let hereDeadline = Date().addingTimeInterval(4)
    var hereMedia: Double?
    while Date() < hereDeadline, hereMedia == nil {
        pump(0.05)
        here.stepPresentationDisplayLink()
        let sample = bgaView(here).inspection()
        if sample.videoAttached, let media = sample.currentVideoSeconds, let rate = sample.videoRate, abs(Double(rate) - 2) < 0.2 {
            hereMedia = media
        }
    }
    let hereWall = hereState.previewPlayer.playbackWallElapsedSeconds()
    require(
        hereMedia != nil && (hereMedia ?? 0) > 1.5 && (hereMedia ?? 0) < 2.0 + hereWall * 2.6 + 0.35,
        "Here video time \(hereMedia ?? -1) did not include the beat-4 offset at 2x, wall \(hereWall)"
    )
    require(here.previewBGAChartUpdates == hereCharts, "Here playback rebound after the pointer start")
    here.stopPlayback()
}

private struct VideoProgress {
    var uptime: Double
    var media: Double
    var rate: Float
    var seeks: Int
    var opens: Int
}

@MainActor
private func videoProgress(_ view: PreviewBGAView, controller: PreviewWindowController) -> VideoProgress {
    if controller.previewDisplay.isPlaying {
        controller.stepPresentationDisplayLink()
    }
    let sample = view.inspection()
    guard let media = sample.currentVideoSeconds, let rate = sample.videoRate else {
        fail("video clock was missing, attached \(sample.videoAttached) status \(sample.status)")
    }
    return VideoProgress(
        uptime: ProcessInfo.processInfo.systemUptime,
        media: media,
        rate: rate,
        seeks: sample.videoSeekCount,
        opens: sample.videoOpenCount
    )
}

@MainActor
private func testHiddenLogicKeepsLongNotes() {
    func tap(_ controller: PreviewWindowController, _ text: String, times: Int = 1) {
        for _ in 0..<times {
            controller.previewSendKeyDown(keyEvent(text, window: controller.window))
            controller.previewSendKeyUp(keyEvent(text, window: controller.window, keyUp: true))
        }
    }
    func longChart(title: String, startBeat: Double = 0, endBeat: Double) -> PreviewChartSnapshot {
        var chart = stageChart(title: title)
        chart.endBeat = 64
        chart.notes = [
            PreviewVisualNote(laneID: "1p-k1", startBeat: startBeat, endBeat: endBeat),
            PreviewVisualNote(laneID: "2p-k1", startBeat: startBeat, endBeat: endBeat)
        ]
        chart.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "hold.png")]
        chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        return chart
    }
    let folder = URL(fileURLWithPath: "/tmp/ibms-uw7-hidden", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    writeSolidPNG(folder.appendingPathComponent("hold.png"), red: 0.1, green: 0.2, blue: 0.3)
    func host(
        _ title: String,
        startBeat: Double = 0,
        endBeat: Double,
        playHere: Double = 0
    ) -> (PreviewWindowController, ApplicationState) {
        makeController {
            context(
                chart: longChart(title: title, startBeat: startBeat, endBeat: endBeat),
                timing: bpm120,
                playHere: playHere,
                bmson: false,
                directory: folder,
                documentData: Data("#TITLE \(title)\n#PLAYER 1\n".utf8)
            )
        }
    }
    func playfields(_ controller: PreviewWindowController) -> [PreviewPlayfieldView] {
        guard let root = controller.window?.contentView else { fail("missing content") }
        let primary = find(id: "PreviewPlayfield", in: root) as? PreviewPlayfieldView
        let secondary = find(id: "PreviewPlayfieldSecondary", in: root) as? PreviewPlayfieldView
        guard let primary, let secondary else { fail("missing playfields") }
        return [primary, secondary]
    }
    func geometryBuilds(_ controller: PreviewWindowController) -> Int {
        playfields(controller).reduce(0) { $0 + $1.geometryBuildCount }
    }
    func held(_ scene: PreviewPlayfieldScene, lane: String) -> PreviewPlayfieldHit? {
        scene.hits.first { $0.laneID == lane && $0.isLong && $0.tailAgeMilliseconds == nil }
    }

    let (clock, state) = host("Hold", endBeat: 32)
    layout(clock, size: NSSize(width: 587, height: 256))
    tap(clock, "4", times: 4)
    require(abs(state.previewPlayer.requestedPlaybackRate - 2) < 0.001, "hidden host engine \(state.previewPlayer.requestedPlaybackRate)")
    clock.playFromStart()
    var sawHold = false
    let holdDeadline = Date().addingTimeInterval(3)
    while Date() < holdDeadline, !sawHold {
        pump(0.02)
        if clock.previewDisplay.isPlaying { clock.stepPresentationDisplayLink() }
        let chartSeconds = clock.previewDisplay.elapsedSeconds
        let wall = state.previewPlayer.playbackWallElapsedSeconds()
        guard chartSeconds >= 1.5, chartSeconds <= 2.8, wall >= 0.6, wall <= 1.5,
              held(clock.previewPlayfieldScene(), lane: "1p-k1") != nil,
              held(clock.previewSecondaryScene(), lane: "2p-k1") != nil else { continue }
        sawHold = true
    }
    require(sawHold, "2x long note was not holding before hide, beat \(clock.previewDisplay.beat)")
    let comboBefore = clock.previewPlayfieldScene().combo
    let secondaryCombo = clock.previewSecondaryScene().combo
    hidePreview(clock)
    let occlusion = clock.window?.occlusionState.rawValue ?? 0
    fputs("UW7 occlusion=\(occlusion) suppressed=\(clock.previewPictureSuppressed)\n", stderr)
    require(clock.previewPictureSuppressed, "orderOut plus occlusion did not suppress the picture, occlusion \(occlusion)")
    require(clock.previewDisplay.isPlaying, "hiding stopped the long note")
    require(!clock.previewUsesExternalPresentationClock, "hiding kept the display link clock")
    let hiddenChart = clock.previewDisplay.elapsedSeconds
    let hiddenWall = state.previewPlayer.playbackWallElapsedSeconds()
    let presented = clock.previewPresentedFrameCount
    let playfieldUpdates = clock.previewPlayfieldPlaybackUpdates
    let geometry = geometryBuilds(clock)
    let bgaUpdates = clock.previewBGAPlaybackUpdates
    let bga = clock.previewBGAInspection()
    let charts = clock.previewBGAChartUpdates
    pump(2)
    let chartGain = clock.previewDisplay.elapsedSeconds - hiddenChart
    let wallGain = state.previewPlayer.playbackWallElapsedSeconds() - hiddenWall
    require(clock.previewDisplay.isPlaying && !clock.previewDisplay.isFinished, "hidden long note stopped")
    require(chartGain > 3.2 && chartGain < 5.0, "hidden 2x chart moved \(chartGain)")
    require(wallGain > 1.6 && wallGain < 2.6, "hidden wall moved \(wallGain)")
    require(clock.previewDisplay.elapsedSeconds < 16, "hidden clock reached the long-note tail, chart \(clock.previewDisplay.elapsedSeconds)")
    require(clock.previewPresentedFrameCount == presented, "hidden logic presented frames")
    require(clock.previewPlayfieldPlaybackUpdates == playfieldUpdates, "hidden logic rebuilt playback")
    require(geometryBuilds(clock) == geometry, "hidden logic rebuilt geometry")
    require(clock.previewBGAPlaybackUpdates == bgaUpdates, "hidden logic pushed BGA")
    require(clock.previewBGAInspection().imageDecodeCount == bga.imageDecodeCount, "hidden logic decoded BGA")
    require(clock.previewBGAInspection().videoOpenCount == bga.videoOpenCount, "hidden logic opened video")
    require(abs(state.previewPlayer.requestedPlaybackRate - 2) < 0.001, "hidden logic changed the rate")
    clock.showWindow(nil)
    if clock.previewDisplay.isPlaying { clock.stepPresentationDisplayLink() }
    let primary = held(clock.previewPlayfieldScene(), lane: "1p-k1")
    let secondary = held(clock.previewSecondaryScene(), lane: "2p-k1")
    require(primary != nil && secondary != nil, "unhide lost the held long note")
    require(clock.previewPlayfieldScene().combo == comboBefore, "unhide judged again, combo \(clock.previewPlayfieldScene().combo)")
    require(clock.previewSecondaryScene().combo == secondaryCombo, "unhide judged the other side")
    require(
        clock.previewPlayfieldScene().sideJudges.allSatisfy { $0.ageMilliseconds > 500 },
        "unhide replayed a head GREAT"
    )
    require(clock.previewBGAChartUpdates == charts, "unhide rebound the chart")
    let chartsBeforeF2 = clock.previewBGAChartUpdates
    tap(clock, functionKey(PreviewUbmFunctionScalar.f2))
    require(clock.previewBGAChartUpdates == chartsBeforeF2, "F2 rebound after unhide")
    require(abs(state.previewPlayer.requestedPlaybackRate - 2) < 0.001, "F2 changed the rate")
    require(held(clock.previewPlayfieldScene(), lane: "1p-k1") != nil, "F2 cleared the held note")
    clock.stopPlayback()

    let (tail, _) = host("Tail", endBeat: 4)
    layout(tail, size: NSSize(width: 587, height: 256))
    tap(tail, "4", times: 4)
    tail.playFromStart()
    var sawTailHold = false
    let tailHoldDeadline = Date().addingTimeInterval(2)
    while Date() < tailHoldDeadline, !sawTailHold {
        pump(0.02)
        if tail.previewDisplay.isPlaying { tail.stepPresentationDisplayLink() }
        guard tail.previewDisplay.elapsedSeconds >= 0.2, tail.previewDisplay.elapsedSeconds <= 1.2,
              held(tail.previewPlayfieldScene(), lane: "1p-k1") != nil else { continue }
        sawTailHold = true
    }
    require(sawTailHold, "tail note was not holding before hide")
    hidePreview(tail)
    require(tail.previewPictureSuppressed, "tail hide did not suppress the picture")
    pump(3)
    require(tail.previewDisplay.elapsedSeconds > 4, "hidden playback did not cross the tail, chart \(tail.previewDisplay.elapsedSeconds)")
    tail.showWindow(nil)
    if tail.previewDisplay.isPlaying { tail.stepPresentationDisplayLink() }
    let tailHit = tail.previewPlayfieldScene().hits.first { $0.laneID == "1p-k1" }
    let tailTwin = tail.previewSecondaryScene().hits.first { $0.laneID == "2p-k1" }
    require(tailHit == nil && tailTwin == nil, "tail older than 120 ms remained, age \(tailHit?.tailAgeMilliseconds ?? -1)")
    require(tail.previewPlayfieldScene().hits.contains { $0.laneID == "1p-k1" } == false, "expired lane left a ghost")
    tail.stopPlayback()

    let (paused, pausedState) = host("Pause", endBeat: 32)
    layout(paused, size: NSSize(width: 587, height: 256))
    tap(paused, "3", times: 2)
    require(abs(pausedState.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "0.5x engine \(pausedState.previewPlayer.requestedPlaybackRate)")
    paused.playFromStart()
    var sawSlow = false
    let slowDeadline = Date().addingTimeInterval(3)
    while Date() < slowDeadline, !sawSlow {
        pump(0.02)
        if paused.previewDisplay.isPlaying { paused.stepPresentationDisplayLink() }
        guard paused.previewDisplay.elapsedSeconds >= 0.3,
              held(paused.previewPlayfieldScene(), lane: "1p-k1") != nil else { continue }
        sawSlow = true
    }
    require(sawSlow, "0.5x long note was not holding")
    tap(paused, "0")
    require(paused.previewChartPaused, "pause did not reach the engine")
    let pausedChart = paused.previewDisplay.elapsedSeconds
    let pausedWall = pausedState.previewPlayer.playbackWallElapsedSeconds()
    hidePreview(paused)
    require(paused.previewPictureSuppressed, "pause hide did not suppress the picture")
    pump(0.4)
    require(abs(paused.previewDisplay.elapsedSeconds - pausedChart) < 0.05, "pause-hidden moved the chart")
    require(abs(pausedState.previewPlayer.playbackWallElapsedSeconds() - pausedWall) < 0.05, "pause-hidden moved the wall")
    require(abs(pausedState.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "pause-hidden changed the rate")
    paused.showWindow(nil)
    require(paused.previewChartPaused, "showing resumed a paused chart")
    tap(paused, "0")
    let resumeDeadline = Date().addingTimeInterval(2)
    while Date() < resumeDeadline, !paused.previewDisplay.isPlaying {
        pump(0.02)
    }
    require(paused.previewDisplay.isPlaying, "resume after hide did not play")
    pump(0.4)
    if paused.previewDisplay.isPlaying { paused.stepPresentationDisplayLink() }
    require(pausedState.previewPlayer.playbackWallElapsedSeconds() > pausedWall + 0.15, "resume wall stayed frozen")
    require(held(paused.previewPlayfieldScene(), lane: "1p-k1") != nil, "resume lost the held note")
    let slowCharts = paused.previewBGAChartUpdates
    tap(paused, functionKey(PreviewUbmFunctionScalar.home))
    require(paused.previewBGAChartUpdates == slowCharts, "seek rebound the chart")
    require(abs(pausedState.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "seek changed the rate")
    paused.stopPlayback()

    let (here, hereState) = host("Here", startBeat: 4, endBeat: 32, playHere: 4)
    layout(here, size: NSSize(width: 587, height: 256))
    tap(here, "4", times: 4)
    let hereCharts = here.previewBGAChartUpdates
    here.playFromPointer()
    let hereDeadline = Date().addingTimeInterval(2)
    while Date() < hereDeadline, !here.previewDisplay.isPlaying {
        pump(0.02)
    }
    here.stepPresentationDisplayLink()
    require(here.previewDisplay.isPlaying, "Here did not start")
    require(held(here.previewPlayfieldScene(), lane: "1p-k1") != nil, "Here did not keep the long note")
    require(here.previewBGAChartUpdates <= hereCharts + 1, "Here rebound more than once")
    require(abs(hereState.previewPlayer.requestedPlaybackRate - 2) < 0.001, "Here changed the rate")
    here.stopPlayback()

    let (logic, logicState) = host("Logic", endBeat: 32)
    layout(logic, size: NSSize(width: 587, height: 256))
    logic.playFromStart()
    let logicStart = Date().addingTimeInterval(2)
    while Date() < logicStart, !logic.previewDisplay.isPlaying {
        pump(0.02)
    }
    require(logic.previewDisplay.isPlaying, "logic chart did not start")
    hidePreview(logic)
    require(logic.previewPictureSuppressed, "logic hide did not suppress the picture")
    let logicPresented = logic.previewPresentedFrameCount
    let logicUpdates = logic.previewPlayfieldPlaybackUpdates
    let logicGeometry = geometryBuilds(logic)
    let logicBGA = logic.previewBGAPlaybackUpdates
    let logicRate = logicState.previewPlayer.requestedPlaybackRate
    var sample = logic.previewDisplay.elapsedSeconds
    for _ in 0..<2000 {
        sample += 0.01
        logic.previewPresentSampledElapsed(sample)
    }
    require(logic.previewPresentedFrameCount == logicPresented, "2000 logic ticks presented")
    require(logic.previewPlayfieldPlaybackUpdates == logicUpdates, "2000 logic ticks rebuilt playback")
    require(geometryBuilds(logic) == logicGeometry, "2000 logic ticks rebuilt geometry")
    require(logic.previewBGAPlaybackUpdates == logicBGA, "2000 logic ticks pushed BGA")
    require(abs(logicState.previewPlayer.requestedPlaybackRate - logicRate) < 0.001, "2000 logic ticks changed the rate")
    require(logic.previewPlayfieldScene().hits.count <= 4, "logic hits grew to \(logic.previewPlayfieldScene().hits.count)")
    require(logic.previewSecondaryScene().hits.count <= 4, "secondary logic hits grew to \(logic.previewSecondaryScene().hits.count)")
    require(logic.previewPlayfieldScene().sideJudges.count <= 2, "logic judges grew")
    logic.showWindow(nil)
    require(logic.previewPlayfieldScene().hits.count <= 4, "restore after logic ticks grew hits")
    logic.stopPlayback()
}

@MainActor
private func testHiddenClockTextSkipsStageAndSyncsBGAOnce() {
    var chart = stageChart(title: "Hidden Clock")
    chart.endBeat = 64
    let (controller, state) = makeController {
        context(
            chart: chart,
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Hidden Clock\n#PLAYER 1\n".utf8)
        )
    }
    controller.previewDisplayLinkSuppressed = true
    layout(controller, size: NSSize(width: 587, height: 256))
    controller.playFromStart()
    state.previewPlayer.onElapsedSeconds?(1)
    require(controller.previewDisplay.isPlaying, "hidden clock probe did not start")
    require(playClockLine(controller.previewInfoText) == "0:01.00", "opening clock \(controller.previewInfoText)")
    require(
        controller.previewInfoText.contains("HS 1.00 RATE 1.00"),
        "default speeds missing before hide \(controller.previewInfoText)"
    )
    guard let info = find(id: "PreviewUbmInfo", in: controller.window?.contentView) else {
        fail("missing info view")
    }
    hidePreview(controller)
    state.previewPlayer.onElapsedSeconds = nil
    state.previewPlayer.onTimelineFinished = nil
    require(controller.previewPictureSuppressed, "clock probe did not suppress the picture")
    let frameBefore = info.frame
    let presented = controller.previewPresentedFrameCount
    let playfieldUpdates = controller.previewPlayfieldPlaybackUpdates
    let geometry = geometryBuilds(controller)
    let bgaUpdates = controller.previewBGAPlaybackUpdates
    let bga = controller.previewBGAInspection()
    let rasters = controller.previewInfoRasterCount
    let boxBefore = controller.previewInfoLayoutSize
    require(!info.needsDisplay, "info stayed dirty after the visible tick")

    func hiddenSample(_ seconds: Double, clock: String) {
        controller.previewPresentSampledElapsed(seconds)
        require(playClockLine(controller.previewInfoText) == clock, "hidden clock \(controller.previewInfoText) wanted \(clock)")
        require(
            controller.previewInfoText.contains("HS 1.00 RATE 1.00"),
            "hidden text lost the default speeds \(controller.previewInfoText)"
        )
        require(controller.previewBGAPlaybackUpdates == bgaUpdates, "hidden clock pushed BGA at \(clock)")
        require(controller.previewPresentedFrameCount == presented, "hidden clock presented at \(clock)")
        require(controller.previewPlayfieldPlaybackUpdates == playfieldUpdates, "hidden clock rebuilt playback at \(clock)")
        require(geometryBuilds(controller) == geometry, "hidden clock rebuilt geometry at \(clock)")
        require(controller.previewBGAInspection().videoLayoutCount == bga.videoLayoutCount, "hidden clock laid out video at \(clock)")
        require(controller.previewBGAInspection().imageDecodeCount == bga.imageDecodeCount, "hidden clock decoded BGA at \(clock)")
        require(controller.previewBGAInspection().videoOpenCount == bga.videoOpenCount, "hidden clock opened video at \(clock)")
        require(info.frame == frameBefore, "hidden clock laid out the stage at \(clock)")
        require(!info.needsDisplay, "hidden clock drew the info at \(clock)")
    }

    hiddenSample(59.5, clock: "0:59.50")
    hiddenSample(60, clock: "1:00.00")
    hiddenSample(599.5, clock: "9:59.50")
    let beforeWide = controller.previewInfoText.count
    hiddenSample(600, clock: "10:00.00")
    require(controller.previewInfoText.count > beforeWide, "minute tens did not lengthen the text")
    require(abs(controller.previewInfoLayoutSize.width - boxBefore.width) < 0.5, "10:00.00 changed the info box \(controller.previewInfoLayoutSize)")
    let wideSeconds = 100_000_000_000.0 * 60
    hiddenSample(wideSeconds, clock: "100000000000:00.00")
    require(
        controller.previewInfoLayoutSize.width > boxBefore.width,
        "long clock did not widen the internal box \(controller.previewInfoLayoutSize) from \(boxBefore)"
    )
    require(controller.previewInfoRasterCount > rasters, "hidden text was not stored")
    controller.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification))
    controller.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification))
    require(controller.previewPictureSuppressed, "repeat occlusion cleared the hidden flag")
    require(controller.previewBGAPlaybackUpdates == bgaUpdates, "repeat occlusion pushed BGA")
    require(info.frame == frameBefore, "repeat occlusion laid out the stage")
    require(playClockLine(controller.previewInfoText) == "100000000000:00.00", "occlusion rewound the hidden clock")

    controller.showWindow(nil)
    require(!controller.previewPictureSuppressed, "show did not restore the picture")
    require(controller.previewBGAPlaybackUpdates == bgaUpdates + 1, "restore synced BGA \(controller.previewBGAPlaybackUpdates - bgaUpdates) times")
    require(playClockLine(controller.previewInfoText) == "100000000000:00.00", "restore showed \(controller.previewInfoText)")
    require(
        controller.previewInfoText.contains("HS 1.00 RATE 1.00"),
        "restore lost the default speeds \(controller.previewInfoText)"
    )
    require(info.frame.width > frameBefore.width, "restore did not lay out the longer clock \(info.frame)")
    require(!info.needsDisplay, "restore left the info undrawn")
    let restored = compositedInfoPixels(controller)
    require(restored.contains { $0 != 0 }, "restored info image is blank")
    controller.stopPlayback()
}

@MainActor
private func geometryBuilds(_ controller: PreviewWindowController) -> Int {
    guard let root = controller.window?.contentView else { return 0 }
    let primary = find(id: "PreviewPlayfield", in: root) as? PreviewPlayfieldView
    let secondary = find(id: "PreviewPlayfieldSecondary", in: root) as? PreviewPlayfieldView
    return (primary?.geometryBuildCount ?? 0) + (secondary?.geometryBuildCount ?? 0)
}

@MainActor
private func testWindowContentScreenshot() {
    let folder = URL(fileURLWithPath: "/tmp/ibms-d4-preview", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let imageURL = folder.appendingPathComponent("panel.png")
    if let skin = PreviewUbmStyle.skinDirectory()?.appendingPathComponent("skin_02.png"),
       FileManager.default.fileExists(atPath: skin.path) {
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.copyItem(at: skin, to: imageURL)
    } else {
        writeSolidPNG(imageURL, red: 0.15, green: 0.55, blue: 0.85)
    }
    var chart = stageChart(title: "Window Shot")
    chart.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "panel.png")]
    chart.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
    let (controller, state) = makeController {
        context(chart: chart, timing: bpm120, playHere: 0, bmson: false, directory: folder)
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    controller.window?.orderFrontRegardless()
    guard let content = controller.window?.contentView else { fail("missing content") }
    guard let bga = find(id: "PreviewBGA", in: content) as? PreviewBGAView else { fail("missing BGA") }
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline, !bga.inspection().baseImageReady {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    require(bga.inspection().baseImageReady, "static BGA image did not become ready: \(bga.inspection().status)")
    let generation = bga.inspection().generation
    let charts = controller.previewBGAChartUpdates
    controller.playFromStart()
    state.previewPlayer.onElapsedSeconds?(1)
    require(controller.previewBGAChartUpdates == charts, "screenshot playback must not rebind BGA")
    require(bga.inspection().generation == generation, "playback tick changed the BGA generation")
    require(abs(controller.previewDisplay.beat - 2) < 0.000_001, "screenshot clock is beat 2")
    require(abs(controller.previewDisplay.bgaElapsedSeconds - 1) < 0.000_001, "BGA elapsed matches the clock")
    guard let playfield = find(id: "PreviewPlayfield", in: content) as? PreviewPlayfieldView else { fail("missing playfield") }
    _ = playfield.drawMetalViewNow()
    let readback = playfield.renderMetalReadback()
    require(readback.usedMetal && readback.width > 0 && !readback.bgra.isEmpty, "Metal readback was empty \(readback.failure ?? "")")
    content.layoutSubtreeIfNeeded()
    let bounds = content.bounds
    guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { fail("no bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.windowBackgroundColor.setFill()
    NSBezierPath(rect: bounds).fill()
    NSGraphicsContext.restoreGraphicsState()
    content.cacheDisplay(in: bounds, to: rep)
    let layout = controller.previewLayout
    require(!layout.packed, "the screenshot chart is separated")
    require(abs(layout.nominalBGAFrame.width - 512) < 1 && abs(layout.nominalBGAFrame.minX - 346) < 1, "nominal BGA column \(layout.nominalBGAFrame)")
    require(abs(layout.actualStageFrame.width - 1174) < 1 && abs(layout.actualStageFrame.height - 512) < 1, "actual stage \(layout.actualStageFrame)")
    require(layout.nominalBGAFrame != layout.actualStageFrame, "the 256 column is not the whole stage")
    renderLayer(bga.layer, into: rep, frame: layout.actualStageFrame)
    composite(readback, into: rep, frame: layout.playfieldFrame, source: metalCrop(readback, nativeX: 0, nativeWidth: 158))
    guard let secondary = find(id: "PreviewPlayfieldSecondary", in: content) as? PreviewPlayfieldView else {
        fail("missing secondary playfield")
    }
    _ = secondary.drawMetalViewNow()
    let secondReadback = secondary.renderMetalReadback()
    require(secondReadback.usedMetal && secondReadback.width > 0, "secondary Metal readback was empty \(secondReadback.failure ?? "")")
    composite(
        secondReadback,
        into: rep,
        frame: layout.secondPlayfieldFrame,
        source: metalCrop(secondReadback, nativeX: 173, nativeWidth: 158)
    )
    if let infoImage = controller.previewInfoSourceImage {
        drawImage(infoImage, into: rep, frame: layout.infoFrame)
    }
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("png encode failed") }
    let output = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("out/validation/ubmplay-parity-20261020/preview-window-content.png")
    try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        try png.write(to: output)
    } catch {
        fail("could not write \(output.path): \(error)")
    }
    require(png.count > 8_000, "screenshot is unexpectedly small")
    controller.stopPlayback()
}

private func referenceBPM(at beat: Double, timing: PreviewAudioTiming) -> Double {
    let header = timing.headerBPM.isFinite && timing.headerBPM > 0 ? timing.headerBPM : 120
    guard beat.isFinite else { return header }
    var bpm = header
    for event in timing.bpmEvents.sorted(by: { $0.beat < $1.beat }) {
        guard event.beat.isFinite, event.bpm.isFinite, event.bpm > 0 else { continue }
        if event.beat <= beat {
            bpm = event.bpm
        } else {
            break
        }
    }
    return bpm
}

private struct SplitMix64 {
    var state: UInt64
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

@MainActor
private func testInfoKeepsFontGradientAndOneScale() {
    let (controller, _) = makeController {
        context(chart: stageChart(title: "Font"), timing: bpm120, playHere: 0, bmson: false)
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let text = controller.previewInfoText
    guard let shown = controller.previewInfoSourceImage,
          let kept = PreviewUbmStyle.textImage(text),
          let tinted = PreviewUbmStyle.textImage(text, color: NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1))
    else {
        fail("info image missing for \(text)")
    }
    let shownBytes = pixelBytes(shown)
    require(shownBytes == pixelBytes(kept), "info view kept the font.png RGB")
    require(shownBytes != pixelBytes(tinted), "pure cyan tint is a different image")
    let opaque = stride(from: 0, to: shownBytes.count, by: 4).contains { index in
        let red = shownBytes[index]
        let green = shownBytes[index + 1]
        let blue = shownBytes[index + 2]
        let alpha = shownBytes[index + 3]
        return alpha > 0 && !(red == 0 && green == 255 && blue == 255) && !(red == 0 && green == 0 && blue == 0)
    }
    require(opaque, "a font pixel is neither flat cyan nor empty")
    let columns = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
    require(
        abs(controller.previewInfoLayoutSize.width - CGFloat(columns) * 8) < 0.1,
        "layout size is not premultiplied by the stage scale"
    )
    controller.stopPlayback()
}

@MainActor
private func testPlayInfoClockFollowsUnifiedPlayback() {
    let (controller, state) = makeController {
        context(
            chart: stageChart(title: "Clock"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Clock\n#PLAYER 1\n".utf8)
        )
    }
    controller.previewDisplayLinkSuppressed = true
    parkPreview(controller)
    controller.playFromStart()
    state.previewPlayer.onElapsedSeconds?(1.11)
    let earlyText = controller.previewInfoText
    let earlyClock = playClockLine(earlyText)
    require(earlyClock == "0:01.11", "deferred clock \(earlyText)")
    require(abs(clockSeconds(earlyClock) - controller.previewDisplay.elapsedSeconds) < 0.001, "info clock left the unified elapsed")
    let earlyPixels = compositedInfoPixels(controller)
    let earlyPresented = presentedInfoPixels(controller)
    let earlyRasters = controller.previewInfoRasterCount
    state.previewPlayer.onElapsedSeconds?(1.11)
    require(controller.previewInfoRasterCount == earlyRasters, "the same centisecond rasterized again")
    controller.previewPresentSampledElapsed(2.34)
    let laterText = controller.previewInfoText
    let laterClock = playClockLine(laterText)
    require(laterClock == "0:02.34", "display-step clock \(laterText)")
    require(laterClock != earlyClock, "two playback moments share one clock string")
    let laterPixels = compositedInfoPixels(controller)
    let laterPresented = presentedInfoPixels(controller)
    require(laterPixels != earlyPixels, "composited info image did not change")
    require(laterPresented != earlyPresented, "presented info image did not change")
    require(controller.previewInfoRasterCount == earlyRasters + 1, "display step did not publish one new string")

    controller.previewSendKeyDown(keyEvent("0", window: controller.window))
    controller.previewSendKeyUp(keyEvent("0", window: controller.window, keyUp: true))
    require(controller.previewInfoText.contains("PAUSE"), "pause is shown \(controller.previewInfoText)")
    require(playClockLine(controller.previewInfoText) == "0:02.34", "pause rewrote the clock")
    let pausedPixels = compositedInfoPixels(controller)
    state.previewPlayer.onElapsedSeconds?(9)
    controller.previewPresentSampledElapsed(9)
    require(playClockLine(controller.previewInfoText) == "0:02.34", "paused clock ran")
    require(compositedInfoPixels(controller) == pausedPixels, "paused info image changed")
    controller.previewSendKeyDown(keyEvent("0", window: controller.window))
    controller.previewSendKeyUp(keyEvent("0", window: controller.window, keyUp: true))
    state.previewPlayer.onElapsedSeconds?(2.5)
    require(playClockLine(controller.previewInfoText) == "0:02.50", "resume clock \(controller.previewInfoText)")
    require(!controller.previewInfoText.contains("PAUSE"), "resume left PAUSE on screen")

    controller.previewSendKeyDown(keyEvent(functionKey(PreviewUbmFunctionScalar.down), window: controller.window))
    require(abs(controller.previewDisplay.beat - 8) < 0.001, "seek beat \(controller.previewDisplay.beat)")
    require(playClockLine(controller.previewInfoText) == "0:04.00", "seek clock \(controller.previewInfoText)")
    require(abs(controller.previewDisplay.elapsedSeconds) < 0.001, "seek kept a stale relative elapsed")
    let stale = state.previewPlayer.onElapsedSeconds
    controller.stopPlayback()
    require(playClockLine(controller.previewInfoText) == "0:00.00", "stop clock \(controller.previewInfoText)")
    stale?(8)
    require(playClockLine(controller.previewInfoText) == "0:00.00", "old epoch wrote the clock after stop")
    controller.playFromStart()
    stale?(8)
    require(playClockLine(controller.previewInfoText) == "0:00.00", "old epoch wrote the replay")
    state.previewPlayer.onElapsedSeconds?(0.5)
    require(playClockLine(controller.previewInfoText) == "0:00.50", "replay clock \(controller.previewInfoText)")
    controller.stopPlayback()

    let stopped = PreviewAudioTiming(
        headerBPM: 120,
        bpmEvents: [],
        stopEvents: [(beat: 2, durationSeconds: 1)]
    )
    let (here, hereState) = makeController {
        context(
            chart: stageChart(title: "Here"),
            timing: stopped,
            playHere: 4,
            bmson: false,
            documentData: Data("#TITLE Here\n#PLAYER 1\n".utf8)
        )
    }
    here.previewDisplayLinkSuppressed = true
    parkPreview(here)
    here.playFromPointer()
    require(playClockLine(here.previewInfoText) == "0:03.00", "Here absolute time \(here.previewInfoText)")
    let herePixels = compositedInfoPixels(here)
    hereState.previewPlayer.onElapsedSeconds?(0.75)
    require(playClockLine(here.previewInfoText) == "0:03.75", "Here continued \(here.previewInfoText)")
    require(compositedInfoPixels(here) != herePixels, "Here image stayed on the opening time")
    here.stopPlayback()

    for rate in [0.5, 2.0, 4.0] {
        let (rated, ratedState) = makeController {
            context(
                chart: stageChart(title: "Rate \(rate)"),
                timing: bpm120,
                playHere: 0,
                bmson: false,
                documentData: Data("#TITLE Rate\n#PLAYER 1\n".utf8)
            )
        }
        rated.previewDisplayLinkSuppressed = true
        parkPreview(rated)
        ratedState.previewPlayer.setPlaybackRate(rate)
        rated.playFromStart()
        let deadline = Date().addingTimeInterval(2.5)
        var started = false
        var startWall = 0.0
        var startChart = 0.0
        var checked = false
        while Date() < deadline, !checked {
            pump(0.05)
            guard rated.previewDisplay.isPlaying else { continue }
            if !started {
                started = true
                startWall = ratedState.previewPlayer.playbackWallElapsedSeconds()
                startChart = rated.previewDisplay.elapsedSeconds
                continue
            }
            let wall = ratedState.previewPlayer.playbackWallElapsedSeconds() - startWall
            let chart = rated.previewDisplay.elapsedSeconds - startChart
            guard wall >= 0.12, chart > 0 else { continue }
            let shown = clockSeconds(playClockLine(rated.previewInfoText))
            require(
                abs(shown - rated.previewDisplay.elapsedSeconds) < 0.02,
                "rate \(rate) info \(shown) left chart elapsed \(rated.previewDisplay.elapsedSeconds)"
            )
            require(
                chart > wall * rate * 0.45 && chart < wall * rate * 1.8,
                "rate \(rate) chart \(chart) wall \(wall)"
            )
            checked = true
        }
        require(checked, "rate \(rate) unified clock did not advance")
        rated.stopPlayback()
    }
}

@MainActor
private func parkPreview(_ controller: PreviewWindowController, size: NSSize = NSSize(width: 900, height: 480)) {
    controller.window?.setFrame(NSRect(x: -24000, y: -24000, width: size.width, height: size.height), display: false)
    layout(controller, size: size)
}

private func playClockLine(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let play = lines.firstIndex(of: "Play"), lines.indices.contains(play + 1) else {
        fail("play clock missing in \(text)")
    }
    return lines[play + 1]
}

private func clockSeconds(_ line: String) -> Double {
    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else {
        fail("clock \(line)")
    }
    return minutes * 60 + seconds
}

@MainActor
private func presentedInfoPixels(_ controller: PreviewWindowController) -> [UInt8] {
    guard let image = controller.previewInfoPresentedImage else { fail("presented info image missing") }
    let bytes = pixelBytes(image)
    require(bytes.contains { $0 != 0 }, "presented info image is blank")
    return bytes
}

@MainActor
private func compositedInfoPixels(_ controller: PreviewWindowController) -> [UInt8] {
    guard let info = find(id: "PreviewUbmInfo", in: controller.window?.contentView) else {
        fail("missing info view")
    }
    require(!info.wantsLayer, "info grew its own layer")
    require(!info.isHidden && info.bounds.width > 8 && info.bounds.height > 8, "info is not visible \(info.frame)")
    guard let rep = info.bitmapImageRepForCachingDisplay(in: info.bounds) else { fail("info bitmap") }
    info.cacheDisplay(in: info.bounds, to: rep)
    guard let image = rep.cgImage else { fail("info bitmap has no image") }
    let bytes = pixelBytes(image)
    require(bytes.contains { $0 != 0 }, "drawn info image is blank \(info.bounds)")
    return bytes
}

@MainActor
private func testUbmKeysDriveViewAudioAndBGA() {
    let folder = URL(fileURLWithPath: "/tmp/ibms-ubm-keys", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    writeSolidPNG(folder.appendingPathComponent("base.png"), red: 0.8, green: 0.1, blue: 0.1)
    writeSolidPNG(folder.appendingPathComponent("layer.png"), red: 0.1, green: 0.7, blue: 0.2)
    writeSolidPNG(folder.appendingPathComponent("poor.png"), red: 0.1, green: 0.2, blue: 0.8)
    var chart = stageChart(title: "Keys")
    chart.barBeats = [0, 4, 8, 12, 16]
    chart.bgaAssets = [
        PreviewBGAAsset(id: "AA", fileName: "base.png"),
        PreviewBGAAsset(id: "LL", fileName: "layer.png"),
        PreviewBGAAsset(id: "PP", fileName: "poor.png")
    ]
    chart.bgaEvents = [
        PreviewBGAEvent(beat: 0, assetID: "AA", layer: .base),
        PreviewBGAEvent(beat: 0, assetID: "LL", layer: .layer),
        PreviewBGAEvent(beat: 0, assetID: "PP", layer: .poor)
    ]
    let box = ReloadBox()
    let (controller, state) = makeController {
        box.make(chart)
    }
    controller.setReloadHandler {
        box.handlerCalls += 1
        box.generation += 1
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    func tap(_ text: String, flags: NSEvent.ModifierFlags = []) {
        controller.previewSendKeyDown(keyEvent(text, window: controller.window, flags: flags))
        controller.previewSendKeyUp(keyEvent(text, window: controller.window, flags: flags, keyUp: true))
    }
    let chartsAtOpen = controller.previewBGAChartUpdates
    let scratchBefore = controller.previewPlayfieldScene().lanes.first { $0.id == "1p-sc" }?.rect.minX
    require(controller.previewPlayfieldScene().scratchRaw == 0, "scratch starts on the view")
    require(controller.previewPlayfieldScene().effectsRaw == 7, "effects start on the view")
    require(controller.previewPlayfieldScene().autoSeparate, "auto separate starts on the view")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 48) < 0.001, "HiSpeed 1 is 48 px/beat")
    tap("8")
    let scratchAfter = controller.previewPlayfieldScene()
    require(scratchAfter.scratchRaw == 1, "key 8 writes scratch into the view")
    require(scratchAfter.lanes.first { $0.id == "1p-sc" }?.rect.minX != scratchBefore, "scratch column moved")
    tap("6")
    require(controller.previewPlayfieldScene().effectsRaw == 0, "key 6 clears the effect bits on the view")
    tap(functionKey(PreviewUbmFunctionScalar.f2))
    require(!controller.previewPlayfieldScene().autoSeparate, "F2 packs the lanes on the view")
    tap("7")
    require(controller.window?.level == .floating, "key 7 raises the window")
    tap("7")
    require(controller.window?.level == .normal, "key 7 lowers the window")
    require(controller.previewBGAChartUpdates == chartsAtOpen, "appearance keys rebinding the chart")
    tap("5")
    require(controller.previewBGAInspection().displayMode == 4, "key 5 reaches always-poor")
    require(controller.previewBGAInspection().poorAssetID == "PP", "poor image is the poor asset")
    require(controller.previewBGAInspection().baseAssetID == nil, "always-poor hides the base image")
    tap("5")
    require(controller.previewBGAInspection().displayMode == 0, "key 5 reaches off")
    require(controller.previewBGAInspection().baseAssetID == nil && controller.previewBGAInspection().layerAssetID == nil, "off clears images")
    tap("5")
    require(controller.previewBGAInspection().displayMode == 1 && controller.previewBGAInspection().baseAssetID == "AA", "base only")
    require(controller.previewBGAInspection().layerAssetID == nil, "base only hides the layer")
    tap("5")
    require(controller.previewBGAInspection().displayMode == 2 && controller.previewBGAInspection().layerAssetID == "LL", "layer only")
    require(controller.previewBGAInspection().baseAssetID == nil, "layer only hides the base")
    controller.previewPerformMenu("PreviewBGAMenu")
    require(controller.previewBGAInspection().displayMode == 3, "the menu returns to normal")
    require(controller.previewBGAInspection().baseAssetID == "AA" && controller.previewBGAInspection().layerAssetID == "LL", "normal shows both images")
    require(controller.previewBGAChartUpdates == chartsAtOpen, "BGA mode rebinding the chart")
    let speed = controller.previewPlayfieldPixelsPerBeat
    controller.previewSendKeyDown(keyEvent("2", window: controller.window, flags: .command))
    require(abs(controller.previewPlayfieldPixelsPerBeat - speed) < 0.001, "command-2 is left for the system")
    controller.previewSendKeyDown(keyEvent("2", window: controller.window, flags: .numericPad))
    require(abs(controller.previewHiSpeed - 1.25) < 0.001, "keypad 2 raises HiSpeed")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 60) < 0.001, "1.25x is 60 px/beat, not the window scale")
    Thread.sleep(forTimeInterval: 0.06)
    for _ in 0..<12 {
        controller.previewSendKeyDown(keyEvent("2", window: controller.window, flags: .numericPad, repeatKey: true))
    }
    require(abs(controller.previewHiSpeed - 1.25) < 0.001, "system repeat does not leave the first detent")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 60) < 0.001, "repeat does not write another HiSpeed")
    controller.previewSendKeyUp(keyEvent("2", window: controller.window, flags: .numericPad, keyUp: true))
    controller.previewSendKeyDown(keyEvent("2", window: controller.window, flags: .numericPad))
    controller.previewSendKeyUp(keyEvent("2", window: controller.window, flags: .numericPad, keyUp: true))
    require(abs(controller.previewHiSpeed - 1.5) < 0.001, "release then press moves one detent")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 72) < 0.001, "the next detent is 72 px/beat")
    let realBefore = controller.previewRealHS
    controller.previewPerformMenu("PreviewRealHSMenu")
    require(controller.previewRealHS == realBefore, "the RealHS menu title does not step the rate")
    tap("4")
    require(controller.previewRealHS == 125, "key 4 stores the next RealHS detent")
    require(abs(state.previewPlayer.requestedPlaybackRate - 1.25) < 0.001, "key 4 sets the real playback rate")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 72) < 0.001, "RealHS does not change HiSpeed pixels")
    require(controller.previewInfoText.contains("HS 1.50") && controller.previewInfoText.contains("RATE 1.25"), "play info shows the effective speeds \(controller.previewInfoText)")
    require(!controller.previewInfoText.contains("RealHS"), "info does not use the hidden RealHS label \(controller.previewInfoText)")
    tap("9")
    require(controller.previewInfoText.contains("KEY&BGM"), "default audible kinds are key and BGM \(controller.previewInfoText)")
    require(!controller.previewInfoText.contains("RealHS"), "option lines still omit RealHS")
    let chartsBeforeSound = controller.previewBGAChartUpdates
    tap(functionKey(PreviewUbmFunctionScalar.f1))
    require(controller.previewInfoText.contains("MINE ONLY"), "F1 passes the next audible set \(controller.previewInfoText)")
    require(controller.previewBGAChartUpdates == chartsBeforeSound, "F1 reloads the chart")
    tap(functionKey(PreviewUbmFunctionScalar.f1))
    require(controller.previewInfoText.contains("KEY&BGM&MINE"), "the next sound set includes keys \(controller.previewInfoText)")
    require(controller.previewBGAChartUpdates == chartsBeforeSound, "sound changes reload the chart")
    try? tinyWav().write(to: folder.appendingPathComponent("click.wav"))
    state.previewPlayer.readResourceBytes = { _ in tinyWav() }
    controller.previewDisplayLinkSuppressed = true
    controller.playFromStart()
    let playingDeadline = Date().addingTimeInterval(2)
    while Date() < playingDeadline, !controller.previewDisplay.isPlaying {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    let fetchesAfterPlay = box.fetches
    let chartsAfterPlay = controller.previewBGAChartUpdates
    state.previewPlayer.onElapsedSeconds?(2)
    require(controller.previewDisplay.beat >= 4 && controller.previewDisplay.beat < 8, "playback reached the second measure, got \(controller.previewDisplay.beat)")
    require(
        state.previewPlayer.diagnosticCueCount > 0,
        "the chart loaded no cues, failure \(state.previewPlayer.diagnosticPreparationFailure ?? "none") engine \(state.previewPlayer.diagnosticEngineFailure ?? "none")"
    )
    tap("0")
    require(controller.previewChartPaused && !controller.previewDisplay.isPlaying, "pauseChart freezes the first playback")
    tap("0")
    require(controller.previewDisplay.isPlaying && !controller.previewChartPaused, "resumeChart continues the first playback")
    tap(functionKey(PreviewUbmFunctionScalar.up))
    require(abs(controller.previewDisplay.beat) < 0.001, "Up moves one measure back to 0")
    require(box.fetches == fetchesAfterPlay, "Up re-rolled the chart")
    require(controller.previewBGAChartUpdates == chartsAfterPlay, "seek rebinding BGA media")
    tap(functionKey(PreviewUbmFunctionScalar.down))
    let downDeadline = Date().addingTimeInterval(2)
    while Date() < downDeadline, !controller.previewDisplay.isPlaying {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    require(controller.previewDisplay.beat >= 4 && controller.previewDisplay.beat < 5, "Down moves one measure forward, got \(controller.previewDisplay.beat)")
    tap("0")
    let frozenBeat = controller.previewDisplay.beat
    let frozenElapsed = controller.previewDisplay.elapsedSeconds
    require(controller.previewDisplay.isPaused && !controller.previewDisplay.isPlaying && !controller.previewDisplay.isFinished, "pause matches the engine flags")
    require(controller.previewChartPaused && controller.previewBehaviorPaused, "pauseChart is the pause")
    require(!controller.previewDisplay.bgaIsPlaying, "BGA holds while paused")
    state.previewPlayer.onElapsedSeconds?(9)
    require(abs(controller.previewDisplay.elapsedSeconds - frozenElapsed) < 0.001, "a later tick does not run the paused clock")
    require(abs(controller.previewDisplay.beat - frozenBeat) < 0.001, "pause keeps the beat")
    tap(functionKey(PreviewUbmFunctionScalar.end))
    let pausedDeadline = Date().addingTimeInterval(2)
    while Date() < pausedDeadline, !controller.previewChartPaused {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    require(abs(controller.previewDisplay.beat - 12) < 0.001, "End uses the last content measure, not the end sentinel")
    require(controller.previewDisplay.isPaused && controller.previewChartPaused, "paused seek stays silent")
    require(box.fetches == fetchesAfterPlay, "End re-rolled the chart")
    require(controller.previewBGAChartUpdates == chartsAfterPlay, "paused seek rebinding BGA media")
    tap(functionKey(PreviewUbmFunctionScalar.home))
    let homeDeadline = Date().addingTimeInterval(2)
    while Date() < homeDeadline, !controller.previewChartPaused {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    require(abs(controller.previewDisplay.beat) < 0.001 && controller.previewDisplay.isPaused, "Home stays on the same branch")
    require(box.fetches == fetchesAfterPlay, "Home re-rolled the chart")
    tap("0")
    require(controller.previewDisplay.isPlaying && !controller.previewChartPaused && !controller.previewDisplay.isPaused, "resume continues")
    state.previewPlayer.onElapsedSeconds?(0.5)
    require(
        controller.previewDisplay.beat > 0.2 && controller.previewDisplay.beat < 4,
        "resume continues from the seek, got \(controller.previewDisplay.beat)"
    )
    let handlerBefore = box.handlerCalls
    controller.previewSendKeyDown(keyEvent(" ", window: controller.window))
    Thread.sleep(forTimeInterval: 0.55)
    controller.previewSendKeyDown(keyEvent(" ", window: controller.window, repeatKey: true))
    require(box.handlerCalls == handlerBefore + 1, "space asks the editor to clear random")
    require(box.fetches > fetchesAfterPlay, "space re-reads the document")
    require(controller.previewDisplay.windowTitle == "Keys 1", "reloaded title \(controller.previewDisplay.windowTitle)")
    let generationAfterReload = box.generation
    controller.previewSendKeyUp(keyEvent(" ", window: controller.window, keyUp: true))
    controller.setReloadHandler(nil)
    let fetchesWithoutHandler = box.fetches
    controller.previewSendKeyDown(keyEvent(" ", window: controller.window))
    Thread.sleep(forTimeInterval: 0.55)
    controller.previewSendKeyDown(keyEvent(" ", window: controller.window, repeatKey: true))
    require(box.handlerCalls == handlerBefore + 1, "no handler means the editor is not told to re-roll")
    require(box.generation == generationAfterReload, "the window does not invent a new random")
    require(box.fetches > fetchesWithoutHandler, "the current document is still read again")
    controller.stopPlayback()
}

private final class ReloadBox: @unchecked Sendable {
    var generation = 0
    var fetches = 0
    var handlerCalls = 0

    @MainActor
    func make(_ chart: PreviewChartSnapshot) -> PreviewAudioDocumentContext {
        fetches += 1
        var titled = chart
        titled.title = "Keys \(generation)"
        return context(
            chart: titled,
            timing: bpm120,
            playHere: 0,
            bmson: false,
            directory: URL(fileURLWithPath: "/tmp/ibms-ubm-keys", isDirectory: true),
            audioNotes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            documentData: Data("#TITLE Keys \(generation)\n#PLAYLEVEL 3\n#RANK 2\n#RANKING 9\n#WAV01 click.wav\n".utf8)
        )
    }
}

@MainActor
private func testSpeedDetentsOnTheController() {
    let (controller, state) = makeController {
        context(
            chart: stageChart(title: "Speed"),
            timing: bpm120,
            playHere: 0,
            bmson: false,
            documentData: Data("#TITLE Speed\n#PLAYER 1\n".utf8)
        )
    }
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    let info = controller.previewInfoText
    require(info.contains("HS 1.00") && info.contains("RATE 1.00"), "default play info shows the speeds \(info)")
    require(!info.contains("0.25"), "default info does not show a floored 0.25 \(info)")
    let fitted = controller.previewLayout
    let native = controller.previewInfoLayoutSize
    require(
        fitted.infoFrame.width + 1 >= native.width * fitted.stageScale
            && fitted.infoFrame.height + 1 >= native.height * fitted.stageScale,
        "speed line is clipped \(fitted.infoFrame) native \(native) scale \(fitted.stageScale)"
    )
    require(fitted.bgaFrame.contains(fitted.infoFrame), "speed line left the BGA \(fitted.infoFrame)")

    guard let root = controller.window?.contentView, let menu = root.menu else { fail("missing preview menu") }
    guard let hiMenu = menu.items.first(where: { $0.identifier?.rawValue == "PreviewHiSpeedMenu" }),
          let rateMenu = menu.items.first(where: { $0.identifier?.rawValue == "PreviewRealHSMenu" }),
          let helpMenu = menu.items.first(where: { $0.identifier?.rawValue == "PreviewShortcutMenu" }) else {
        fail("missing speed menus")
    }
    require(hiMenu.submenu?.items.count == 19, "HiSpeed submenu \(hiMenu.submenu?.items.count ?? 0)")
    require(rateMenu.submenu?.items.count == 16, "Rate submenu \(rateMenu.submenu?.items.count ?? 0)")
    let help = helpMenu.submenu?.items.map(\.title).joined(separator: "\n") ?? ""
    require(help.contains("Fn") && help.contains("编辑器") && help.contains("1") && help.contains("3"), "shortcut help \(help)")
    let hiItem = hiMenu.submenu?.items.first
    let rateItem = rateMenu.submenu?.items.first
    controller.setPreviewControlsVisible(true)
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)
    guard let controls = find(id: "PreviewControls", in: root),
          let hsLabel = find(id: "PreviewHiSpeedValue", in: root) as? NSTextField,
          let rateLabel = find(id: "PreviewRateValue", in: root) as? NSTextField,
          let hsUp = find(id: "PreviewHiSpeedUp", in: root) as? NSButton,
          let rateDown = find(id: "PreviewRateDown", in: root) as? NSButton else {
        fail("missing speed controls")
    }
    func fullyVisible(_ view: NSView) -> Bool {
        let frame = view.convert(view.bounds, to: controls)
        return controls.bounds.insetBy(dx: -1, dy: -1).contains(frame) && frame.width > 8 && frame.height > 8
    }
    require(hsLabel.stringValue == "1.00" && rateLabel.stringValue == "1.00x", "labels \(hsLabel.stringValue) \(rateLabel.stringValue)")
    require(fullyVisible(hsLabel) && fullyVisible(rateLabel) && fullyVisible(hsUp), "speed controls are clipped \(controls.bounds)")
    layout(controller, size: NSSize(width: 587, height: 320))
    require(fullyVisible(hsLabel) && fullyVisible(rateLabel), "speed controls clip at 587pt \(hsLabel.frame) \(rateLabel.frame)")
    layout(controller, size: PreviewWindowPlayback.defaultContentSize)

    controller.previewSendKeyDown(keyEvent("2", window: controller.window))
    for _ in 0..<30 {
        controller.previewSendKeyDown(keyEvent("2", window: controller.window, repeatKey: true))
    }
    require(abs(controller.previewHiSpeed - 1.25) < 0.001, "repeats ran away to \(controller.previewHiSpeed)")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 60) < 0.001, "repeat pixels \(controller.previewPlayfieldPixelsPerBeat)")
    controller.previewSendKeyUp(keyEvent("2", window: controller.window, keyUp: true))
    controller.previewSendKeyDown(keyEvent("2", window: controller.window))
    controller.previewSendKeyUp(keyEvent("2", window: controller.window, keyUp: true))
    require(abs(controller.previewHiSpeed - 1.5) < 0.001, "second press \(controller.previewHiSpeed)")
    require(hsLabel.stringValue == "1.50", "label did not follow the key \(hsLabel.stringValue)")
    require(hiMenu.title.contains("1.50"), "menu title \(hiMenu.title)")

    hsUp.performClick(nil)
    require(abs(controller.previewHiSpeed - 1.75) < 0.001 && hsLabel.stringValue == "1.75", "plus button \(controller.previewHiSpeed)")
    controller.previewPerformMenu("PreviewHiSpeedDetent-18")
    require(abs(controller.previewHiSpeed - 5) < 0.001, "menu detent \(controller.previewHiSpeed)")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 240) < 0.001, "5.00 is 240px")
    controller.previewSendKeyDown(keyEvent("2", window: controller.window))
    controller.previewSendKeyUp(keyEvent("2", window: controller.window, keyUp: true))
    require(abs(controller.previewHiSpeed - 5) < 0.001, "top detent moved")
    controller.previewPerformMenu("PreviewHiSpeedDetent-0")
    require(abs(controller.previewHiSpeed - 0.5) < 0.001, "bottom menu detent")
    require(abs(controller.previewPlayfieldPixelsPerBeat - 24) < 0.001, "0.50 is 24px")
    controller.previewSendKeyDown(keyEvent("1", window: controller.window))
    controller.previewSendKeyUp(keyEvent("1", window: controller.window, keyUp: true))
    require(abs(controller.previewHiSpeed - 0.5) < 0.001, "bottom detent moved")

    controller.previewPerformMenu("PreviewRealHSMenu")
    require(controller.previewRealHS == 100, "parent rate menu stepped")
    controller.previewPerformMenu("PreviewRateDetent-50")
    require(controller.previewRealHS == 50, "rate menu \(controller.previewRealHS)")
    require(abs(state.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "menu rate did not reach the engine")
    require(rateLabel.stringValue == "0.50x", "rate label \(rateLabel.stringValue)")
    require(controller.previewInfoText.contains("RATE 0.50"), "info rate \(controller.previewInfoText)")
    rateDown.performClick(nil)
    require(controller.previewRealHS == 25, "rate minus \(controller.previewRealHS)")
    rateDown.performClick(nil)
    require(controller.previewRealHS == 25, "rate floor moved")

    controller.previewSendKeyDown(keyEvent("1", window: controller.window))
    controller.previewSendKeyDown(keyEvent("2", window: controller.window))
    require(abs(controller.previewHiSpeed - 0.75) < 0.001, "1 and 2 together move toward 1.00, got \(controller.previewHiSpeed)")
    controller.previewSendKeyUp(keyEvent("2", window: controller.window, keyUp: true))
    controller.previewSendKeyUp(keyEvent("1", window: controller.window, keyUp: true))

    controller.setPreviewScrollPixelsPerBeat(16)
    require(abs(controller.previewPlayfieldPixelsPerBeat - 24) < 0.001, "16px displays as \(controller.previewPlayfieldPixelsPerBeat)")
    require(controller.previewInfoText.contains("HS 0.50") && !controller.previewInfoText.contains("HS 0.25"), "effective HiSpeed \(controller.previewInfoText)")
    require(hsLabel.stringValue == "0.50", "label shows the effective detent \(hsLabel.stringValue)")

    controller.playFromStart()
    let started = Date().addingTimeInterval(2)
    while Date() < started, !controller.previewDisplay.isPlaying {
        pump(0.02)
    }
    require(controller.previewDisplay.isPlaying, "speed chart did not start")
    controller.previewSendKeyDown(keyEvent("0", window: controller.window))
    controller.previewSendKeyUp(keyEvent("0", window: controller.window, keyUp: true))
    require(controller.previewChartPaused && controller.previewDisplay.isPaused, "pause before the rate change")
    controller.previewSendKeyDown(keyEvent("4", window: controller.window))
    for _ in 0..<20 {
        controller.previewSendKeyDown(keyEvent("4", window: controller.window, repeatKey: true))
        controller.stepPresentationDisplayLink()
    }
    controller.previewSendKeyUp(keyEvent("4", window: controller.window, keyUp: true))
    require(controller.previewRealHS == 50 && abs(state.previewPlayer.requestedPlaybackRate - 0.5) < 0.001, "paused repeat changed the rate to \(controller.previewRealHS)")
    require(controller.previewChartPaused, "rate change resumed playback")
    require(controller.previewInfoText.contains("PAUSE") && controller.previewInfoText.contains("RATE 0.50"), "paused info \(controller.previewInfoText)")
    controller.previewSendKeyUp(keyEvent("4", window: controller.window, keyUp: true))
    controller.previewSendKeyDown(keyEvent("4", window: controller.window))
    controller.previewSendKeyUp(keyEvent("4", window: controller.window, keyUp: true))
    require(controller.previewRealHS == 75, "release then press while paused \(controller.previewRealHS)")
    require(controller.previewChartPaused, "the next detent resumed playback")
    require(hiMenu.submenu?.items.count == 19 && rateMenu.submenu?.items.count == 16, "playback rebuilt the detent menus")
    require(hiMenu.submenu?.items.first === hiItem && rateMenu.submenu?.items.first === rateItem, "playback replaced the detent items")
    controller.stopPlayback()
}

@MainActor
private func keyEvent(
    _ characters: String,
    window: NSWindow?,
    flags: NSEvent.ModifierFlags = [],
    repeatKey: Bool = false,
    keyUp: Bool = false
) -> NSEvent {
    guard let event = NSEvent.keyEvent(
        with: keyUp ? .keyUp : .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window?.windowNumber ?? 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: repeatKey,
        keyCode: 0
    ) else {
        fail("could not build a key event")
    }
    return event
}

private func functionKey(_ scalar: UInt32) -> String {
    String(UnicodeScalar(scalar)!)
}

private func pixelBytes(_ image: CGImage) -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return []
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

private final class RateClipFinished: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func finish() {
        lock.lock()
        done = true
        lock.unlock()
    }

    func isDone() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }
}

private func writeRateClip(_ url: URL, seconds: Double) {
    if FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.removeItem(at: url)
    }
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
        fail("could not create the rate clip")
    }
    let width = 64
    let height = 48
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ])
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ])
    guard writer.canAdd(videoInput) else { fail("could not add the rate clip track") }
    writer.add(videoInput)
    guard writer.startWriting() else { fail(writer.error?.localizedDescription ?? "rate clip did not start") }
    writer.startSession(atSourceTime: .zero)
    let frameCount = max(1, Int((seconds * 10).rounded()))
    var frame = 0
    let deadline = Date().addingTimeInterval(20)
    while frame < frameCount && Date() < deadline {
        guard videoInput.isReadyForMoreMediaData else {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            continue
        }
        var pixel: CVPixelBuffer?
        let created = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixel
        )
        guard created == kCVReturnSuccess, let pixel else { fail("could not allocate a rate-clip frame") }
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) {
            let row = CVPixelBufferGetBytesPerRow(pixel)
            memset(base, frame % 2 == 0 ? 40 : 180, row * height)
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        let time = CMTime(value: CMTimeValue(frame), timescale: 10)
        guard adaptor.append(pixel, withPresentationTime: time) else {
            fail(writer.error?.localizedDescription ?? "could not append a rate-clip frame")
        }
        frame += 1
    }
    require(frame == frameCount, "rate clip stopped at frame \(frame)")
    videoInput.markAsFinished()
    let finished = RateClipFinished()
    writer.finishWriting {
        finished.finish()
    }
    let finishDeadline = Date().addingTimeInterval(10)
    while !finished.isDone(), Date() < finishDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    require(finished.isDone() && writer.status == .completed, "rate clip status \(writer.status.rawValue)")
}

private func writeSolidPNG(_ url: URL, red: Double, green: Double, blue: Double) {
    let width = 32
    let height = 32
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )
    guard let rep, let raw = rep.bitmapData else { fail("could not allocate the BGA image") }
    let r = UInt8((min(1, max(0, red)) * 255).rounded())
    let g = UInt8((min(1, max(0, green)) * 255).rounded())
    let b = UInt8((min(1, max(0, blue)) * 255).rounded())
    for pixel in 0..<(width * height) {
        let offset = pixel * 4
        raw[offset] = r
        raw[offset + 1] = g
        raw[offset + 2] = b
        raw[offset + 3] = 255
    }
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("could not encode the BGA image") }
    do {
        try data.write(to: url)
    } catch {
        fail("could not write \(url.path): \(error)")
    }
}

private func writeBandPNG(_ url: URL) {
    let width = 512
    let height = 16
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )
    guard let rep, let raw = rep.bitmapData else { fail("could not allocate the wide BGA") }
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let green = x < 16
            let blue = x >= 496
            raw[offset] = blue ? 20 : 0
            raw[offset + 1] = green ? 220 : 0
            raw[offset + 2] = blue ? 220 : 0
            raw[offset + 3] = 255
        }
    }
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("could not encode the wide BGA") }
    do {
        try data.write(to: url)
    } catch {
        fail("could not write \(url.path): \(error)")
    }
}

private struct RenderedBitmap {
    var width: Int
    var height: Int
    var bytes: [UInt8]
}

@MainActor
private func renderedPixels(_ view: NSView) -> RenderedBitmap {
    view.layoutSubtreeIfNeeded()
    let width = max(1, Int(view.bounds.width.rounded()))
    let height = max(1, Int(view.bounds.height.rounded()))
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("could not render the BGA")
    }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    view.layer?.render(in: context)
    return RenderedBitmap(width: width, height: height, bytes: bytes)
}

private func bitmapHasColor(
    _ bitmap: RenderedBitmap,
    x: Int,
    red: Int,
    green: Int,
    blue: Int,
    alphaAtLeast: Int = 200
) -> Bool {
    guard bitmap.width > 0, bitmap.height > 0 else { return false }
    let sampleX = min(max(x, 0), bitmap.width - 1)
    for y in stride(from: 0, to: bitmap.height, by: 2) {
        let offset = (y * bitmap.width + sampleX) * 4
        guard offset + 3 < bitmap.bytes.count else { continue }
        let r = Int(bitmap.bytes[offset])
        let g = Int(bitmap.bytes[offset + 1])
        let b = Int(bitmap.bytes[offset + 2])
        let a = Int(bitmap.bytes[offset + 3])
        if a >= alphaAtLeast && abs(r - red) < 48 && abs(g - green) < 48 && abs(b - blue) < 48 {
            return true
        }
    }
    return false
}

private func pixelHash(_ readback: PreviewPlayfieldMetalReadback, nativeX: Int, nativeWidth: Int) -> Int {
    guard readback.width > 1, readback.height > 1 else { return 0 }
    let x0 = min(readback.width - 1, max(0, readback.width * nativeX / 331))
    let x1 = min(readback.width, max(x0 + 1, readback.width * (nativeX + nativeWidth) / 331))
    var hash = 0
    var y = 0
    let stepY = max(1, readback.height / 24)
    let stepX = max(1, (x1 - x0) / 12)
    while y < readback.height {
        var x = x0
        while x < x1 {
            if let pixel = readback.components(x: x, y: y) {
                hash = hash &* 33 &+ Int((pixel.r * 255).rounded()) &* 3
                    &+ Int((pixel.g * 255).rounded()) &* 5
                    &+ Int((pixel.b * 255).rounded())
            }
            x += stepX
        }
        y += stepY
    }
    return hash
}

private func metalCrop(_ readback: PreviewPlayfieldMetalReadback, nativeX: Int, nativeWidth: Int) -> CGRect {
    let x = readback.width * nativeX / 331
    let width = max(1, readback.width * nativeWidth / 331)
    let clamped = min(width, max(1, readback.width - x))
    return CGRect(x: x, y: 0, width: clamped, height: readback.height)
}

private func composite(
    _ readback: PreviewPlayfieldMetalReadback,
    into rep: NSBitmapImageRep,
    frame: CGRect,
    source: CGRect? = nil
) {
    let data = readback.bgra as CFData
    guard let provider = CGDataProvider(data: data) else { return }
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )
    guard var image = CGImage(
        width: readback.width,
        height: readback.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: readback.bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else { return }
    if let source, let cropped = image.cropping(to: source.integral) {
        image = cropped
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .none
    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
}

private func renderLayer(_ layer: CALayer?, into rep: NSBitmapImageRep, frame: CGRect) {
    guard let layer, frame.width > 1, frame.height > 1 else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let context = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return
    }
    context.saveGState()
    context.translateBy(x: frame.minX, y: frame.minY)
    layer.render(in: context)
    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
}

private func drawImage(_ image: CGImage, into rep: NSBitmapImageRep, frame: CGRect) {
    guard frame.width > 1, frame.height > 1 else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .none
    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(
        in: frame,
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
}

private func stageChart(title: String) -> PreviewChartSnapshot {
    var lanes: [PreviewVisualLane] = []
    lanes.append(PreviewVisualLane(id: "1p-sc", title: "SC", isScratch: true, player: 1))
    for key in 1...7 {
        lanes.append(PreviewVisualLane(id: "1p-k\(key)", title: "\(key)", isScratch: false, player: 1))
    }
    lanes.append(PreviewVisualLane(id: "2p-sc", title: "SC", isScratch: true, player: 2))
    for key in 1...7 {
        lanes.append(PreviewVisualLane(id: "2p-k\(key)", title: "\(key)", isScratch: false, player: 2))
    }
    return PreviewChartSnapshot(
        title: title,
        lanes: lanes,
        notes: [
            PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4),
            PreviewVisualNote(laneID: "2p-sc", startBeat: 4, endBeat: 8)
        ],
        barBeats: [0, 4, 8, 12],
        endBeat: 16
    )
}

private func chartFolder() -> URL {
    URL(fileURLWithPath: "/tmp/ibms-preview-chart", isDirectory: true)
}

private func context(
    chart: PreviewChartSnapshot,
    timing: PreviewAudioTiming,
    playHere: Double,
    bmson: Bool,
    directory: URL? = nil,
    audioNotes: [PreviewAudioNote] = [],
    documentData: Data = Data("#TITLE visual-only\n".utf8)
) -> PreviewAudioDocumentContext {
    PreviewAudioDocumentContext(
        documentData: documentData,
        chartDirectory: directory,
        notes: audioNotes,
        timing: timing,
        playHereBeat: playHere,
        appliesBmsonPlayhead: bmson,
        visualChart: chart
    )
}

@MainActor
private func makeController(
    source: @escaping () -> PreviewAudioDocumentContext?,
    audio: Bool = true,
    onBeat: ((Double?) -> Void)? = nil
) -> (PreviewWindowController, ApplicationState) {
    let state = ApplicationState(audioImplemented: audio)
    let controller = PreviewWindowController(state: state, documentSource: source, onPlayheadBeat: onBeat)
    return (controller, state)
}

private func tinyWav() -> Data {
    let frames = 8
    let dataSize = frames * 2
    var bytes = Data()
    func append(_ text: String) { bytes.append(contentsOf: text.utf8) }
    func append16(_ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
    }
    func append32(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
    }
    append("RIFF")
    append32(UInt32(36 + dataSize))
    append("WAVE")
    append("fmt ")
    append32(16)
    append16(1)
    append16(1)
    append32(8_000)
    append32(16_000)
    append16(2)
    append16(16)
    append("data")
    append32(UInt32(dataSize))
    bytes.append(Data(count: dataSize))
    return bytes
}

private final class PrepareGate: @unchecked Sendable {
    private let lock = NSLock()
    private var openFlag = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return openFlag
    }

    func open() {
        lock.lock()
        openFlag = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        openFlag = false
        lock.unlock()
    }
}

@MainActor
private func hidePreview(_ controller: PreviewWindowController) {
    controller.window?.orderOut(nil)
    controller.windowDidChangeOcclusionState(Notification(name: NSWindow.didChangeOcclusionStateNotification))
}

@MainActor
private func pump(_ seconds: Double) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

@MainActor
private func layout(_ controller: PreviewWindowController, size: NSSize) {
    controller.showWindow(nil)
    controller.window?.setContentSize(size)
    controller.window?.layoutIfNeeded()
    controller.window?.contentView?.layoutSubtreeIfNeeded()
}

@MainActor
private func selectSide(_ controller: PreviewWindowController, segment: Int) {
    guard let root = controller.window?.contentView,
          let control = find(id: "PreviewPlayerSide", in: root) as? NSSegmentedControl else {
        fail("missing player side control")
    }
    control.selectedSegment = segment
    require(control.sendAction(control.action, to: control.target), "player side action")
}

@MainActor
private func find(id: String, in view: NSView?) -> NSView? {
    guard let view else { return nil }
    if view.identifier?.rawValue == id || view.accessibilityIdentifier() == id { return view }
    for subview in view.subviews {
        if let found = find(id: id, in: subview) { return found }
    }
    return nil
}

private func require(_ condition: Bool, _ message: String) {
    if !condition {
        fail(message)
    }
}

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}
