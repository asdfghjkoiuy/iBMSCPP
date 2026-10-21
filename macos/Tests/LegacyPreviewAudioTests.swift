import Foundation
import os

@main
struct LegacyPreviewAudioTests {
    @MainActor
    static func main() {
        if let ac = ProcessInfo.processInfo.environment["AC_ONLY"] {
            switch ac {
            case "offline": testAcOfflineReset()
            case "audible": testAcAudibleSource()
            case "all":
                testAcOfflineReset()
                testAcAudibleSource()
            default:
                fputs("unknown AC_ONLY \(ac)\n", stderr)
                exit(EXIT_FAILURE)
            }
            print("AC \(ac) ok")
            fflush(stdout)
            return
        }
        if ProcessInfo.processInfo.environment["UA8_ONLY"] == "tail" {
            testDenseNonOverlappingFileNotes()
            testDynamicRateKeepsTheTone()
            print("tail ok")
            return
        }
        if let aw = ProcessInfo.processInfo.environment["AW_ONLY"] {
            switch aw {
            case "empty-sync": testEmptyChartStillCompletesSynchronously()
            case "missing": testMissingFileVisualEndWaitsForAdapterReady()
            case "paused": testAudibleStartPausedWaitsForWorkerReady()
            case "runtime": testRuntimeFailureUsesStoppedNotNaturalFinish()
            case "replay": testRuntimeFailureReplayDoesNotStopNewGeneration()
            case "silent-chart": testSilentChartSitsThroughStopUntilVisualEnd()
            case "empty-old": testEmptyChartWithoutVisualEndDoesNotSpin()
            case "clock": testClockTicksNearSixtyHertz()
            case "tail": testSampleTailSurvivesNaturalEnd()
            case "external-empty": testExternalEmptyChartFinishesOnce()
            case "external-gen": testExternalGenerationsFinishOnce()
            case "external-final": testDisablingExternalInsideFinalSampleDoesNotFinishNextGeneration()
            case "external-release": testExternalReleaseDoesNotLeakClock()
            case "start-paused-silent": testStartPausedFreezesSilentTimelines()
            case "pause": testPauseAndResumeKeepElapsed()
            case "ready-callback": testReadyCallbackCannotEmitStaleElapsed()
            case "finish-callback": testFinishAndElapsedCallbacksCannotResumeOldTimeline()
            default:
                fputs("unknown AW_ONLY \(aw)\n", stderr)
                exit(EXIT_FAILURE)
            }
            print("AW \(aw) ok")
            fflush(stdout)
            return
        }
        if let ov = ProcessInfo.processInfo.environment["OV_ONLY"] {
            guard ov == "overlap" else {
                fputs("unknown OV_ONLY \(ov)\n", stderr)
                exit(EXIT_FAILURE)
            }
            let folder = makeChartFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            testSharedFileTwoOffsets(folder: folder)
            print("OV overlap ok")
            fflush(stdout)
            return
        }
        testParseWavDefinitions()
        testScheduleHitsAt120BPM()
        testFileNameLookupAndPlayHere()
        testStopAddsCoreDuration()
        testCheckFilenameSwapsWavAndOgg()
        testBeatAfterSeconds()
        testUnsavedChartSnapshotStaysOnContext()
        testSilentChartSitsThroughStopUntilVisualEnd()
        testEmptyChartWithoutVisualEndDoesNotSpin()
        testClockTicksNearSixtyHertz()
        testSampleTailSurvivesNaturalEnd()
        testLaterNoteOutlivesEarlierPictureEnd()
        testStopCutsSoundAndClock()
        testReplayDropsThePreviousNote()
        testSingleNoteFadeDoesNotCutTheNextChart()
        testNoteAndClockShareOneStart()
        testReleasedPlayerDoesNotKeepTicking()
        testExternalClockDoesNotDoubleTick()
        testExternalEmptyChartFinishesOnce()
        testExternalGenerationsFinishOnce()
        testDisablingExternalInsideFinalSampleDoesNotFinishNextGeneration()
        testExternalReleaseDoesNotLeakClock()
        testChartHitsDoNotReadOnMainAndStayCached()
        testSameWavOverlaps()
        testPrepareCancelAndReplayDropsStaleLoad()
        testDecodeToWavLeavesTheMainThread()
        testVoiceCapStealsInsteadOfGrowing()
        testSparseNotesAreNotCutByLookahead()
        testWorkingSetStaysAudibleInsideBudget()
        testSmallBudgetStillAudibleOffMain()
        testSpillStillPlaysLaterNotes()
        testUnsupportedFileDoesNotReady()
        testLongBGMStreamsAndSeeks()
        testPauseAndResumeKeepElapsed()
        testStartPausedFreezesSilentTimelines()
        testAudibleKindsFilterLaterCues()
        testPlaybackRateChangesPitchAndTimeline()
        testRateCeilingIgnoresSampleRate()
        testDenseNonOverlappingFileNotes()
        testSparseNotesAtFourX()
        testDynamicRateKeepsTheTone()
        testLongStreamStaysContinuousAtFourX()
        testFormatPoolReconfiguresAcrossCharts()
        testReadyCallbackCannotEmitStaleElapsed()
        testFinishAndElapsedCallbacksCannotResumeOldTimeline()
        testScheduleCursorDoesNotRescanTheChart()
        testVoicesShareOneHostOrigin()
        testSurroundChannelsFailPrepare()
        testLateBindingStaysSilentAcrossRebind()
        testEmptyChartStillCompletesSynchronously()
        testMissingFileVisualEndWaitsForAdapterReady()
        testAudibleStartPausedWaitsForWorkerReady()
        testRuntimeFailureUsesStoppedNotNaturalFinish()
        testRuntimeFailureReplayDoesNotStopNewGeneration()
        print("LegacyPreviewAudioTests passed")
    }

    private static func testParseWavDefinitions() {
        let text = """
        #TITLE demo
        #WAV01 a.wav
        #wav02 b.wav
        #RANDOM 2
        #IF 1
        #WAV03 inside.wav
        #ENDIF
        #WAV01 overwrite.wav
        """
        let table = LegacyPreviewAudio.parseWavTable(from: text)
        require(table["01"] == "overwrite.wav", "later #WAV01 overwrites")
        require(table["02"] == "b.wav", "lowercase #wav02")
        require(table["03"] == "inside.wav", "WAV inside IF is still collected; RANDOM is not expanded")
        require(table["RANDOM"] == nil, "RANDOM is not a WAV key")
        require(table["IF"] == nil, "IF is not a WAV key")
    }

    private static func testScheduleHitsAt120BPM() {
        let notes = [
            PreviewAudioNote(beat: 0, wavToken: "01"),
            PreviewAudioNote(beat: 4, wavToken: "02")
        ]
        let hits = LegacyPreviewAudio.scheduleHits(
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0
        )
        require(hits.count == 2, "two audible notes")
        require(hits[0].wavToken == "01" && abs(hits[0].seconds) < 0.000_001, "first hit at 0s")
        require(hits[1].wavToken == "02" && abs(hits[1].seconds - 2.0) < 0.000_001, "4 beats / (120/60) = 2s")
    }

    private static func testFileNameLookupAndPlayHere() {
        let table = LegacyPreviewAudio.parseWavTable(from: "#WAV0A kick.wav\n#WAV0B \n")
        require(LegacyPreviewAudio.fileName(forToken: "0a", in: table) == "kick.wav", "lookup is case-insensitive")
        require(LegacyPreviewAudio.fileName(forToken: "0B", in: table) == nil, "empty definition is missing")
        require(LegacyPreviewAudio.fileName(forToken: "ZZ", in: table) == nil, "undefined token")
        let folder = URL(fileURLWithPath: "/tmp/chart", isDirectory: true)
        require(
            LegacyPreviewAudio.resolveWavURL(fileName: "kick.wav", chartDirectory: folder)?.path == "/tmp/chart/kick.wav",
            "relative name joins the chart folder"
        )
        let notes = [
            PreviewAudioNote(beat: 0, wavToken: "01"),
            PreviewAudioNote(beat: 4, wavToken: "02")
        ]
        let fromHere = LegacyPreviewAudio.scheduleHits(
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 2
        )
        require(fromHere.count == 1, "Play Here skips notes before the pointer")
        require(fromHere[0].wavToken == "02" && abs(fromHere[0].seconds - 1.0) < 0.000_001, "2 beats at 120 BPM is 1s")
    }

    /// 核心 `seconds_for_stop`：48 单位、120 BPM 是 1 秒。这里直接用核心已经给出的秒数。
    private static func testStopAddsCoreDuration() {
        let notes = [
            PreviewAudioNote(beat: 0, wavToken: "01"),
            PreviewAudioNote(beat: 4, wavToken: "02")
        ]
        let timing = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [],
            stopEvents: [(beat: 2, durationSeconds: 1.0)]
        )
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 0)
        require(abs(hits[0].seconds) < 0.000_001, "note at the start is not delayed")
        require(abs(hits[1].seconds - 3.0) < 0.000_001, "2s travel + 1s STOP")
        let fromStop = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 2)
        require(fromStop.count == 1, "Play Here from the STOP beat")
        require(abs(fromStop[0].seconds - 2.0) < 0.000_001, "1s remaining travel + the STOP at beat 2")
        let sameBeat = LegacyPreviewAudio.scheduleHits(
            notes: [PreviewAudioNote(beat: 2, wavToken: "03")],
            timing: timing,
            fromBeat: 0
        )
        require(abs(sameBeat[0].seconds - 1.0) < 0.000_001, "note on the STOP beat plays before the pause")
    }

    /// iBMSC `Audio.vb` `CheckFilename`：要 OGG 没有文件时改用同名 WAV，反过来也一样。
    private static func testCheckFilenameSwapsWavAndOgg() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-preview-check-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = folder.appendingPathComponent("kick.wav")
        try! Data([0]).write(to: wav)
        let fromOgg = LegacyPreviewAudio.resolveAudioURL(fileName: "kick.ogg", chartDirectory: folder)
        require(fromOgg?.path == wav.path, "missing ogg uses wav")
        try! FileManager.default.removeItem(at: wav)
        let ogg = folder.appendingPathComponent("kick.ogg")
        try! Data([0]).write(to: ogg)
        let fromWav = LegacyPreviewAudio.resolveAudioURL(fileName: "kick.wav", chartDirectory: folder)
        require(fromWav?.path == ogg.path, "missing wav uses ogg")
        let missing = LegacyPreviewAudio.resolveAudioURL(fileName: "snare.ogg", chartDirectory: folder)
        require(missing?.path == folder.appendingPathComponent("snare.ogg").path, "neither file keeps the requested path")
    }

    /// 播出秒数反查拍，和 `scheduleHits` 同一套 STOP / BPM。
    private static func testBeatAfterSeconds() {
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 0, fromBeat: 0, timing: timing)) < 0.000_001,
            "0s stays"
        )
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 1, fromBeat: 0, timing: timing) - 2) < 0.000_001,
            "1s at 120 BPM is beat 2"
        )
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 1, fromBeat: 2, timing: timing) - 4) < 0.000_001,
            "from beat 2 + 1s is beat 4"
        )
        let stopped = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [],
            stopEvents: [(beat: 2, durationSeconds: 1.0)]
        )
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 1, fromBeat: 0, timing: stopped) - 2) < 0.000_001,
            "arrive at STOP"
        )
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 1.5, fromBeat: 0, timing: stopped) - 2) < 0.000_001,
            "sit on STOP"
        )
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 2.5, fromBeat: 0, timing: stopped) - 3) < 0.000_001,
            "0.5s after STOP is beat 3"
        )
        let faster = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [(beat: 2, bpm: 240)]
        )
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: 1.5, fromBeat: 0, timing: faster) - 4) < 0.000_001,
            "after 240 BPM, 0.5s is 2 beats"
        )
        let noteAtStop = LegacyPreviewAudio.scheduleHits(
            notes: [PreviewAudioNote(beat: 2, wavToken: "01")],
            timing: stopped,
            fromBeat: 0
        )
        require(abs(noteAtStop[0].seconds - 1) < 0.000_001, "note on STOP still at 1s")
        let toFour = LegacyPreviewAudio.scheduleHits(
            notes: [PreviewAudioNote(beat: 4, wavToken: "02")],
            timing: stopped,
            fromBeat: 0
        )
        require(abs(toFour[0].seconds - 3) < 0.000_001, "beat 4 is 3s with STOP")
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: toFour[0].seconds, fromBeat: 0, timing: stopped) - 4)
                < 0.000_001,
            "inverse of 3s is beat 4"
        )
    }

    /// 未保存谱的车道快照挂在上下文上。不写临时文件，旧的构造调用可以不传画面。
    private static func testUnsavedChartSnapshotStaysOnContext() {
        var context = PreviewAudioDocumentContext(
            documentData: Data("#TITLE unsaved\n".utf8),
            chartDirectory: nil,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 130, bpmEvents: []),
            playHereBeat: 3
        )
        require(context.visualChart == PreviewChartSnapshot(), "callers that omit the picture get an empty chart")
        require(context.appliesBmsonPlayhead == false, "BMS context does not apply the BMSON playhead")
        context.visualChart = PreviewChartSnapshot(
            title: "unsaved",
            lanes: [
                PreviewVisualLane(id: "scratch", title: "SC", isScratch: true),
                PreviewVisualLane(id: "key1", title: "1")
            ],
            notes: [
                PreviewVisualNote(laneID: "key1", startBeat: 1, endBeat: 1),
                PreviewVisualNote(laneID: "scratch", startBeat: 0, endBeat: 4)
            ],
            barBeats: [0, 4],
            endBeat: 8
        )
        require(context.visualChart.title == "unsaved", "title stays on the snapshot")
        require(context.visualChart.lanes[0].isScratch, "scratch lane keeps its flag")
        require(context.visualChart.lanes[0].player == 1, "lanes default to 1P")
        require(PreviewVisualLane(id: "key1", title: "1").player == 1, "omitted player is 1P")
        var sideTwo = context.visualChart.lanes[1]
        sideTwo.player = 2
        require(sideTwo.player == 2 && sideTwo != context.visualChart.lanes[1], "2P is a different lane")
        require(!context.visualChart.lanes[1].isScratch, "a key lane is not scratch unless marked")
        require(
            context.visualChart.bgaAssets.isEmpty && context.visualChart.bgaEvents.isEmpty,
            "BGA lists default empty"
        )
        require(
            PreviewPlayerSide.allCases == [.both, .onePlayer, .twoPlayer],
            "side order is both, 1P, 2P"
        )
        require(
            PreviewPlayerSide.both.rawValue == "both"
                && PreviewPlayerSide.onePlayer.rawValue == "onePlayer"
                && PreviewPlayerSide.twoPlayer.rawValue == "twoPlayer",
            "side raw values stay stable"
        )
        require(
            PreviewBGALayer.base != .layer && PreviewBGALayer.poor.rawValue == "poor",
            "BGA layers stay distinct"
        )
        var withBGA = context.visualChart
        withBGA.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "bg.bmp")]
        withBGA.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "01", layer: .base),
            PreviewBGAEvent(beat: 4, assetID: "01", layer: .poor)
        ]
        require(withBGA != context.visualChart, "BGA events change the snapshot")
        require(
            withBGA.bgaEvents[1].layer == .poor && withBGA.bgaAssets[0].fileName == "bg.bmp",
            "poor stays on its own event"
        )
        require(
            context.visualChart.notes[1].laneID == "scratch"
                && abs(context.visualChart.notes[1].endBeat - 4) < 0.000_001,
            "long note keeps lane and end beat"
        )
        require(context.visualChart.barBeats == [0, 4] && abs(context.visualChart.endBeat - 8) < 0.000_001, "bars and chart end")
        require(context.playHereBeat == 3 && context.notes.count == 1, "audio fields stay beside the picture")
        let same = context.visualChart
        require(same == context.visualChart, "equal snapshots compare equal")
        var changed = same
        changed.endBeat = 16
        require(changed != context.visualChart, "a different end beat is a different snapshot")
    }

    /// 音频文件不存在，第 0 拍有一颗音符。240 BPM，第 0.5 拍停 0.2 秒，画面结束在第 1 拍。
    /// 0.45 秒才到终点：0.125 秒走到停顿，停 0.2 秒，再走 0.125 秒。
    @MainActor
    private static func testSilentChartSitsThroughStopUntilVisualEnd() {
        let timing = PreviewAudioTiming(
            headerBPM: 240,
            bpmEvents: [],
            stopEvents: [(beat: 0.5, durationSeconds: 0.2)]
        )
        let oracle = LegacyPreviewAudio.scheduleHits(
            notes: [PreviewAudioNote(beat: 1, wavToken: "01")],
            timing: timing,
            fromBeat: 0
        )
        require(oracle.count == 1 && abs(oracle[0].seconds - 0.45) < 0.000_001, "visual end is 0.45s with the STOP")
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        var elapsedAtFinish = -1.0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = {
            finishes += 1
            elapsedAtFinish = samples.last ?? -1
        }
        player.playChart(
            documentData: Data("#WAV01 missing.wav\n".utf8),
            chartDirectory: URL(fileURLWithPath: "/tmp/ibms-preview-missing", isDirectory: true),
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 1
        )
        require(waitUntil { !samples.isEmpty }, "missing wav chart never became ready")
        require(samples.first == 0, "playback reports the shared start at the visual origin")
        require((samples.last ?? 1) < 0.08, "clock ran ahead of the ready observation, got \(samples.last ?? -1)")
        require(player.soundingSampleCount == 0, "a missing wav does not start a voice")
        require(stops == 0, "starting the chart is not a stop")
        pump(0.20)
        guard let mid = samples.last else {
            require(false, "clock produced no sample")
            return
        }
        require(mid > 0.14 && mid < 0.30, "after 0.20s the clock is inside the STOP window, got \(mid)")
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: mid, fromBeat: 0, timing: timing) - 0.5) < 0.000_001,
            "inside the STOP the picture stays on beat 0.5, elapsed \(mid)"
        )
        require(stops == 0 && finishes == 0, "the STOP is not the end of the chart")
        pump(0.55)
        guard let end = samples.last else {
            require(false, "clock produced no final sample")
            return
        }
        require(abs(end - 0.45) < 0.000_001, "final elapsed is the visual end, got \(end)")
        require(finishes == 1 && abs(elapsedAtFinish - 0.45) < 0.000_001, "natural end notifies once with the final elapsed")
        require(
            abs(LegacyPreviewAudio.beat(afterSeconds: end, fromBeat: 0, timing: timing) - 1) < 0.000_001,
            "final elapsed maps back to beat 1"
        )
        let finishedCount = samples.count
        require(stops == 0, "natural end does not emit the stop callback")
        pump(0.20)
        require(samples.count == finishedCount && finishes == 1, "the timer is gone after the chart ends")
        player.stop()
        require(stops == 1 && finishes == 1, "an explicit stop after the chart still notifies, without a second finish")
    }

    /// 空谱面没有音符，也没有 visualEndBeat。时钟报一次 0 后停，不能再空转。
    @MainActor
    private static func testEmptyChartWithoutVisualEndDoesNotSpin() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        var elapsedAtFinish: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = {
            finishes += 1
            elapsedAtFinish.append(samples.last ?? -1)
        }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0
        )
        require(samples == [0], "empty chart reports the start once")
        require(finishes == 1 && elapsedAtFinish == [0], "empty chart finishes once at elapsed 0")
        require(stops == 0, "natural end is not stop()")
        pump(0.30)
        require(samples == [0] && finishes == 1, "no timer keeps spinning or finishing again")

        samples.removeAll()
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 4,
            visualEndBeat: 1
        )
        require(samples == [0], "a playhead already past the picture reports one start sample")
        require(finishes == 2 && elapsedAtFinish == [0, 0], "past-the-end chart finishes once more")
        pump(0.25)
        require(samples == [0] && finishes == 2 && stops == 0, "past-the-end chart does not spin or stop")
    }

    @MainActor
    private static func testClockTicksNearSixtyHertz() {
        let player = LegacyPreviewAudioPlayer()
        var marks: [(elapsed: Double, uptime: TimeInterval)] = []
        var finishes = 0
        var stops = 0
        player.onElapsedSeconds = { elapsed in
            marks.append((elapsed, ProcessInfo.processInfo.systemUptime))
        }
        player.onTimelineFinished = { finishes += 1 }
        player.onPlaybackStopped = { stops += 1 }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        pump(0.45)
        player.stop()
        require(marks.first?.elapsed == 0, "first sample is the start")
        let ticks = Array(marks.dropFirst())
        require(ticks.count >= 20, "0.45s at 60Hz should yield at least 20 ticks, got \(ticks.count)")
        require(ticks.count <= 40, "ticks ran faster than the 60Hz clock, got \(ticks.count)")
        let span = ticks.last!.uptime - ticks.first!.uptime
        let rate = Double(ticks.count - 1) / span
        require(rate > 48 && rate < 78, "timer rate \(rate) Hz over \(span)s is not about 60Hz")
        let origin = marks[0].uptime
        for sample in ticks {
            let drift = abs(sample.elapsed - (sample.uptime - origin))
            require(drift < 0.02, "elapsed \(sample.elapsed) drifted \(drift)s from the monotonic clock")
        }
        require(ticks.last!.elapsed > 0.35 && ticks.last!.elapsed < 0.55, "clock advanced about the pumped time")
        require(finishes == 0 && stops == 1, "stopping before the picture end is not a natural finish")
    }

    @MainActor
    private static func testSampleTailSurvivesNaturalEnd() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = folder.appendingPathComponent("hit.wav")
        try! toneWAV(duration: 0.70).write(to: wav)
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 0
        )
        require(
            waitUntil { finishes == 1 && player.soundingSampleCount == 1 },
            "the note at the start beat did not start with the origin, engine \(player.diagnosticEngineFailure ?? "ok")"
        )
        require(samples == [0], "a zero-length chart reports the start and no further clock")
        require(finishes == 1, "a zero-length chart finishes once at the start")
        require(stops == 0, "reaching the visual end is not stop()")
        pump(0.15)
        require(player.soundingSampleCount == 1, "natural end left the sample tail playing")
        require(samples == [0] && finishes == 1, "no timer remains to move the picture or finish again")
        let tailDeadline = ProcessInfo.processInfo.systemUptime + 1.5
        while ProcessInfo.processInfo.systemUptime < tailDeadline && player.soundingSampleCount > 0 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        require(player.soundingSampleCount == 0, "the sample finished on its own after the tail")
        require(stops == 0 && finishes == 1, "the sample finishing does not emit stop() or a second finish")
    }

    /// 画面先到，后面的音符仍要响。时间轴取较晚的那个时刻，结束时不砍采样尾音。
    @MainActor
    private static func testLaterNoteOutlivesEarlierPictureEnd() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.80).write(to: folder.appendingPathComponent("hit.wav"))
        let timing = PreviewAudioTiming(headerBPM: 240, bpmEvents: [])
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var finishes = 0
        var stops = 0
        var elapsedAtFinish = -1.0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = {
            finishes += 1
            elapsedAtFinish = samples.last ?? -1
        }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 2, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 1
        )
        require(waitUntil { !samples.isEmpty }, "later-note chart never became ready")
        require(player.soundingSampleCount == 0 && finishes == 0, "beat 2 is still ahead of the picture end")
        require((samples.last ?? 1) < 0.08, "clock ran before the timed section, got \(samples.last ?? -1)")
        pump(0.20)
        require(player.soundingSampleCount == 0, "0.20s is before the note at 0.50s")
        require((samples.last ?? 0) < 0.40, "clock is still before the note, got \(samples.last ?? -1)")
        let deadline = ProcessInfo.processInfo.systemUptime + 0.55
        while ProcessInfo.processInfo.systemUptime < deadline && finishes == 0 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        require(finishes == 1, "timeline finishes once at the later note")
        require(abs(elapsedAtFinish - 0.5) < 0.000_001, "final elapsed is the note at 0.5s, got \(elapsedAtFinish)")
        require(stops == 0, "natural end is not stop")
        require(player.soundingSampleCount == 1, "finishing the timeline leaves the sample tail")
        pump(0.12)
        require(finishes == 1 && player.soundingSampleCount == 1, "finish is once and the tail is still playing")
        player.stop()
        require(stops == 1 && finishes == 1, "explicit stop does not finish again")
    }

    @MainActor
    private static func testStopCutsSoundAndClock() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.80).write(to: folder.appendingPathComponent("hit.wav"))
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(
            waitUntil { player.soundingSampleCount == 1 && !samples.isEmpty },
            "chart note did not become ready, engine \(player.diagnosticEngineFailure ?? "ok")"
        )
        pump(0.12)
        require((samples.last ?? 0) > 0.05, "clock moved before stop")
        let count = samples.count
        player.stop()
        require(stops == 1 && finishes == 0, "stop notifies once and does not finish the timeline")
        require(player.soundingSampleCount == 0, "stop cuts the sounding sample")
        pump(0.25)
        require(samples.count == count && finishes == 0, "stop cancels later clock ticks, count \(samples.count)")
    }

    /// 第一遍把音符排在 0.40 秒。马上重播另一份没有这颗音符的谱。旧回调不能在新的一遍里出声。
    @MainActor
    private static func testReplayDropsThePreviousNote() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.40).write(to: folder.appendingPathComponent("hit.wav"))
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0.8, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        samples.removeAll()
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 0.2
        )
        pump(0.60)
        require(player.soundingSampleCount == 0, "the cancelled note from the first pass must not sound")
        guard let end = samples.last else {
            require(false, "replay produced no elapsed samples")
            return
        }
        require(samples.first == 0, "replay starts again at 0")
        require(abs(end - 0.1) < 0.000_001, "second chart ends at beat 0.2 / 120 BPM = 0.1s, got \(end)")
        let finished = samples.count
        pump(0.20)
        require(samples.count == finished && finishes == 1, "first chart's clock must not keep running or finish again after replay")
    }

    /// 单音预听的淡出如果在下一遍谱面开始后才到点，不能把新的采样停掉。
    @MainActor
    private static func testSingleNoteFadeDoesNotCutTheNextChart() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = folder.appendingPathComponent("hit.wav")
        try! toneWAV(duration: 1.20).write(to: wav)
        let player = LegacyPreviewAudioPlayer()
        var stops = 0
        var finishes = 0
        var samples: [Double] = []
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.onElapsedSeconds = { samples.append($0) }
        player.playFile(url: wav, maxDurationSeconds: 0.05, fadeOutSeconds: 0.40)
        require(stops == 1 && finishes == 0, "single-note preview still halts the previous session")
        require(player.soundingSampleCount == 1, "single note started")
        stops = 0
        samples.removeAll()
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(stops == 0, "replacing the single note with a chart does not count as a user stop")
        pump(0.70)
        require(player.soundingSampleCount == 1, "the chart sample is still in its tail after the old fade deadline")
        require(stops == 0 && finishes == 0, "the old fade must not halt or finish the chart")
        require((samples.last ?? 0) > 0.55, "chart clock kept moving, last \(samples.last ?? -1)")
        player.stop()
        require(player.soundingSampleCount == 0 && finishes == 0, "explicit stop still cuts the chart without finishing the timeline")
    }

    /// 第 1 拍、240 BPM 是 0.25 秒。出声时刻和时钟读数都从这一次起播算。
    @MainActor
    private static func testNoteAndClockShareOneStart() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.30).write(to: folder.appendingPathComponent("hit.wav"))
        let timing = PreviewAudioTiming(headerBPM: 240, bpmEvents: [])
        let oracle = LegacyPreviewAudio.scheduleHits(
            notes: [PreviewAudioNote(beat: 1, wavToken: "01")],
            timing: timing,
            fromBeat: 0
        )
        require(abs(oracle[0].seconds - 0.25) < 0.000_001, "note is due at 0.25s")
        let player = LegacyPreviewAudioPlayer()
        var origin: TimeInterval?
        var samples: [Double] = []
        player.onElapsedSeconds = { elapsed in
            if origin == nil {
                origin = ProcessInfo.processInfo.systemUptime
            }
            samples.append(elapsed)
        }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 1, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(player.soundingSampleCount == 0, "the note at beat 1 does not sound at the start")
        let deadline = ProcessInfo.processInfo.systemUptime + 0.60
        var heardAt: TimeInterval?
        while ProcessInfo.processInfo.systemUptime < deadline {
            if player.soundingSampleCount > 0 {
                heardAt = ProcessInfo.processInfo.systemUptime
                break
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard let heardAt, let origin else {
            require(false, "note did not start")
            return
        }
        let delta = heardAt - origin
        let clock = samples.last ?? -1
        require(abs(delta - 0.25) < 0.08, "note became audible \(delta)s after the start, expected 0.25s")
        require(abs(clock - 0.25) < 0.08, "clock read \(clock) when the note became audible, expected near 0.25s")
        player.stop()
    }

    @MainActor
    private static func testReleasedPlayerDoesNotKeepTicking() {
        let clocksBefore = LegacyPreviewAudioPlayer.liveElapsedClockCount
        var player: LegacyPreviewAudioPlayer? = LegacyPreviewAudioPlayer()
        var ticks = 0
        player?.onElapsedSeconds = { _ in ticks += 1 }
        player?.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(ticks == 1, "only the synchronous start sample exists before the run loop")
        require(
            LegacyPreviewAudioPlayer.liveElapsedClockCount == clocksBefore + 1,
            "the chart clock is alive while the player is"
        )
        player = nil
        let frozen = ticks
        require(
            LegacyPreviewAudioPlayer.liveElapsedClockCount == clocksBefore,
            "releasing the player left \(LegacyPreviewAudioPlayer.liveElapsedClockCount - clocksBefore) clock(s)"
        )
        pump(0.30)
        require(ticks == frozen, "timer kept the player alive and delivered \(ticks - frozen) more samples")
        require(
            LegacyPreviewAudioPlayer.liveElapsedClockCount == clocksBefore,
            "the timer resurrected a clock after the player was released"
        )
    }

    /// 外部驱动关掉时，`advancePresentationClock` 不得采样。打开后 60Hz 定时器停，每次 advance 只走一拍，停一次。
    @MainActor
    private static func testExternalClockDoesNotDoubleTick() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        pump(0.12)
        let timed = samples.count
        require(timed >= 2, "default timer still samples before external mode, got \(timed)")
        player.advancePresentationClock()
        require(samples.count == timed, "advance while external is off must not sample")
        require(finishes == 0 && stops == 0, "a disabled advance must not stop or finish")

        player.setPresentationClockExternallyDriven(true)
        player.setPresentationClockExternallyDriven(true)
        let frozen = samples.count
        pump(0.20)
        require(
            samples.count == frozen,
            "external mode left the 60Hz timer running, got \(samples.count - frozen) extra"
        )
        player.advancePresentationClock()
        require(samples.count == frozen + 1, "one advance is one sample")
        let advanced = samples.last ?? -1
        require(
            advanced > 0.25 && advanced < 1.0,
            "external sample stays on the original origin, got \(advanced)"
        )
        player.advancePresentationClock()
        require(samples.count == frozen + 2, "second advance is one more sample")
        pump(0.12)
        require(samples.count == frozen + 2, "pump between advances must not add timer ticks")

        player.stop()
        require(stops == 1 && finishes == 0, "stop while externally driven notifies once and does not finish")
        let afterStop = samples.count
        player.advancePresentationClock()
        player.setPresentationClockExternallyDriven(false)
        player.advancePresentationClock()
        pump(0.20)
        require(
            samples.count == afterStop && finishes == 0 && stops == 1,
            "after stop, advances and the timer stay silent"
        )
    }

    /// 空谱在外部驱动下仍在起播时收尾一次。advance 和空转都不会再收一次。
    @MainActor
    private static func testExternalEmptyChartFinishesOnce() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var finishes = 0
        var stops = 0
        player.setPresentationClockExternallyDriven(true)
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0
        )
        require(samples == [0] && finishes == 1 && stops == 0, "empty chart still finishes once at the start")
        player.advancePresentationClock()
        pump(0.15)
        require(samples == [0] && finishes == 1 && stops == 0, "empty chart does not tick or finish again")
    }

    /// 120 BPM 下 0.2 拍是 0.1 秒，2 拍是 1 秒。两代各自自然结束一次。
    /// 第二代打开后立刻关掉外部驱动：这时的 advance 不能把第二代收尾，origin 也不换一条。
    @MainActor
    private static func testExternalGenerationsFinishOnce() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var finishes = 0
        var stops = 0
        var elapsedAtFinish: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = {
            finishes += 1
            elapsedAtFinish.append(samples.last ?? -1)
        }
        player.setPresentationClockExternallyDriven(true)
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 0.2
        )
        require(samples == [0] && finishes == 0, "first generation waits for an external sample")
        pump(0.16)
        require(samples == [0] && finishes == 0, "wall time past the end does not finish an external clock")
        player.advancePresentationClock()
        require(
            finishes == 1 && elapsedAtFinish.count == 1 && abs(elapsedAtFinish[0] - 0.1) < 0.000_001,
            "first generation finishes once at 0.1s, got \(elapsedAtFinish)"
        )
        let afterFirst = samples.count
        player.advancePresentationClock()
        pump(0.10)
        require(samples.count == afterFirst && finishes == 1 && stops == 0, "first generation does not finish again")

        let beforeSecond = ProcessInfo.processInfo.systemUptime
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 2
        )
        let secondAge = ProcessInfo.processInfo.systemUptime - beforeSecond
        require(samples.last == 0 && finishes == 1 && stops == 0, "second generation starts without a finish or stop")
        player.advancePresentationClock()
        let opened = samples.last ?? -1
        require(finishes == 1, "an immediate advance does not finish the new generation")
        require(
            opened >= 0 && opened < secondAge + 0.05,
            "new generation elapsed \(opened) kept the previous origin; this generation is \(secondAge)s old"
        )
        let beforeDisable = samples.count
        player.setPresentationClockExternallyDriven(false)
        player.advancePresentationClock()
        require(
            samples.count == beforeDisable && finishes == 1 && stops == 0,
            "advance while external is off does not sample or finish the new generation"
        )
        player.setPresentationClockExternallyDriven(true)
        pump(0.20)
        player.advancePresentationClock()
        let continued = samples.last ?? -1
        require(finishes == 1 && stops == 0, "toggling external drive does not finish the new generation")
        require(
            continued > opened + 0.15 && continued < opened + 0.50,
            "same origin continued across the toggle, \(opened) -> \(continued)"
        )
        pump(1.00)
        require(finishes == 1, "external mode still does not finish until advance")
        player.advancePresentationClock()
        require(
            finishes == 2 && stops == 0 && elapsedAtFinish.count == 2 && abs(elapsedAtFinish[1] - 1.0) < 0.000_001,
            "second generation finishes once at 1.0s, got \(elapsedAtFinish)"
        )
        let afterSecond = samples.count
        player.advancePresentationClock()
        pump(0.12)
        require(samples.count == afterSecond && finishes == 2 && stops == 0, "no third finish and no timer ticks")
    }

    /// 第一代的最终采样里关掉外部驱动并重播。收尾必须仍认调用前的 generation，不能把下一代关掉。
    @MainActor
    private static func testDisablingExternalInsideFinalSampleDoesNotFinishNextGeneration() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var finishes = 0
        var stops = 0
        var replaced = false
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.onElapsedSeconds = { elapsed in
            samples.append(elapsed)
            if !replaced && abs(elapsed - 0.1) < 0.000_001 {
                replaced = true
                player.setPresentationClockExternallyDriven(false)
                player.playChart(
                    documentData: Data(),
                    chartDirectory: nil,
                    notes: [],
                    timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
                    fromBeat: 0,
                    visualEndBeat: 8
                )
            }
        }
        player.setPresentationClockExternallyDriven(true)
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 0.2
        )
        pump(0.16)
        require(!replaced && finishes == 0 && samples == [0], "first generation has not been advanced yet")
        player.advancePresentationClock()
        require(replaced, "the final sample of the first generation ran")
        require(
            finishes == 0 && stops == 0,
            "the in-flight advance must not finish the chart started from that sample"
        )
        require(samples.last == 0, "the replacement chart reported its own start")
        let afterReplace = samples.count
        player.advancePresentationClock()
        require(
            samples.count == afterReplace && finishes == 0,
            "external is off, so a stale advance must not sample the next generation"
        )
        pump(0.20)
        require(finishes == 0 && stops == 0, "the restored timer must not end the next generation immediately")
        require(samples.count > afterReplace, "timer fallback samples the next generation")
        require(
            (samples.last ?? 99) < 1.0,
            "next generation elapsed stayed on its own origin, got \(samples.last ?? -1)"
        )
        player.stop()
        require(stops == 1 && finishes == 0, "stopping the next generation is one stop and still no natural finish")
    }

    @MainActor
    private static func testExternalReleaseDoesNotLeakClock() {
        let clocksBefore = LegacyPreviewAudioPlayer.liveElapsedClockCount
        var player: LegacyPreviewAudioPlayer? = LegacyPreviewAudioPlayer()
        var ticks = 0
        player?.setPresentationClockExternallyDriven(true)
        player?.onElapsedSeconds = { _ in ticks += 1 }
        player?.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(ticks == 1, "only the synchronous start sample exists")
        require(
            LegacyPreviewAudioPlayer.liveElapsedClockCount == clocksBefore + 1,
            "external mode still uses the one clock owned by the player"
        )
        player?.advancePresentationClock()
        require(ticks == 2, "advance reached the player before release")
        pump(0.20)
        require(ticks == 2, "no timer was running while the player was alive")
        player = nil
        require(
            LegacyPreviewAudioPlayer.liveElapsedClockCount == clocksBefore,
            "releasing the player left \(LegacyPreviewAudioPlayer.liveElapsedClockCount - clocksBefore) clock(s)"
        )
        let frozen = ticks
        pump(0.25)
        require(ticks == frozen, "a released external clock delivered \(ticks - frozen) more samples")
        require(
            LegacyPreviewAudioPlayer.liveElapsedClockCount == clocksBefore,
            "the run loop resurrected a clock after release"
        )
    }

    /// 多音符 `playChart` 先返回。读盘在后台，每个 wav 只读一次；提前量之外的 hit 不再读资源。
    @MainActor
    private static func testChartHitsDoNotReadOnMainAndStayCached() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.30).write(to: folder.appendingPathComponent("kick.wav"))
        try! toneWAV(duration: 0.30).write(to: folder.appendingPathComponent("snare.wav"))
        let reads = OSAllocatedUnfairLock(initialState: LoadProbe())
        let player = LegacyPreviewAudioPlayer()
        player.readResourceBytes = { url in
            reads.withLock { probe in
                probe.calls += 1
                if Thread.isMainThread {
                    probe.mainCalls += 1
                }
            }
            return try? Data(contentsOf: url)
        }
        var samples: [Double] = []
        var readyAt: TimeInterval?
        player.onPreparationStateChanged = { state in
            if state == .ready, readyAt == nil {
                readyAt = ProcessInfo.processInfo.systemUptime
            }
        }
        player.onElapsedSeconds = { samples.append($0) }
        var notes: [PreviewAudioNote] = []
        for index in 0..<40 {
            notes.append(PreviewAudioNote(
                beat: Double(index) * 0.1,
                wavToken: index.isMultiple(of: 2) ? "01" : "02"
            ))
        }
        notes.append(PreviewAudioNote(beat: 1.2, wavToken: "01"))
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let document = Data("#WAV01 kick.wav\n#WAV02 snare.wav\n".utf8)
        let called = ProcessInfo.processInfo.systemUptime
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: notes,
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8
        )
        let returned = ProcessInfo.processInfo.systemUptime - called
        require(returned < 0.05, "playChart blocked the main thread for \(returned * 1000) ms")
        require(samples.isEmpty, "visual origin started before resources were ready")
        require(
            waitUntil { samples.first == 0 },
            "chart did not become ready, engine \(player.diagnosticEngineFailure ?? "ok")"
        )
        let readyDelay = (readyAt ?? ProcessInfo.processInfo.systemUptime) - called
        require(player.diagnosticMainThreadResourceLoads == 0, "resource load ran on the main thread")
        require(player.diagnosticResourceLoads == 2, "expected one load per wav, got \(player.diagnosticResourceLoads)")
        let probe = reads.withLock { $0 }
        require(probe.calls == 2 && probe.mainCalls == 0, "reader calls \(probe.calls), main \(probe.mainCalls)")
        require(player.soundingSampleCount >= 1, "the downbeat was silent when the visual origin started")
        let loadsAtReady = player.diagnosticResourceLoads
        require(
            waitUntil { player.diagnosticDeferredScheduleCount >= 1 },
            "a note outside the lookahead never scheduled"
        )
        require(player.diagnosticResourceLoads == loadsAtReady, "a later hit loaded another resource")
        require(player.diagnosticMainThreadResourceLoads == 0, "a later hit read on the main thread")
        require(
            player.diagnosticMaxDeferredScheduleSeconds < 0.008,
            "deferred hit took \(player.diagnosticMaxDeferredScheduleSeconds * 1000) ms"
        )
        require(player.diagnosticVoiceCreations <= PreviewAudioLimits.maxVoices, "voice pool exceeded the cap")
        print(String(
            format: "UA2 chart-path: playChartReturn=%.3fms readyDelay=%.3fms deferredHit=%.3fms loads=%d voices=%d",
            returned * 1000,
            readyDelay * 1000,
            player.diagnosticMaxDeferredScheduleSeconds * 1000,
            player.diagnosticResourceLoads,
            player.diagnosticVoiceCreations
        ))
        player.stop()

        samples.removeAll()
        let again = ProcessInfo.processInfo.systemUptime
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        let againReturn = ProcessInfo.processInfo.systemUptime - again
        require(player.diagnosticResourceLoads == 0, "a cached wav was read again")
        require(againReturn < 0.05, "cached playChart returned in \(againReturn * 1000) ms")
        require(
            waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 },
            "cached playback did not share the start with the downbeat"
        )
        player.stop()
    }

    /// 同一 keysound 在时长重叠时要同时响，而不是后一个截掉前一个。
    @MainActor
    private static func testSameWavOverlaps() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.40).write(to: folder.appendingPathComponent("kick.wav"))
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 kick.wav\n".utf8),
            chartDirectory: folder,
            notes: [
                PreviewAudioNote(beat: 0, wavToken: "01"),
                PreviewAudioNote(beat: 0.1, wavToken: "01")
            ],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(
            waitUntil { samples.first == 0 && player.soundingSampleCount >= 2 },
            "same wav did not overlap, sounding \(player.soundingSampleCount), engine \(player.diagnosticEngineFailure ?? "ok")"
        )
        require(player.diagnosticResourceLoads == 1, "overlap reloaded the wav, loads \(player.diagnosticResourceLoads)")
        require(player.diagnosticStolenVoices == 0, "the second note stole the first voice")
        require((samples.last ?? 1) < 0.20, "overlap was observed after the notes should still both be playing")
        player.stop()
        require(player.soundingSampleCount == 0, "stop left an overlapping voice running")
    }

    /// 准备完成前 stop / 重播：旧加载可以结束，但不能打开旧时间轴，也不能把声音灌进下一代。
    @MainActor
    private static func testPrepareCancelAndReplayDropsStaleLoad() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.30).write(to: folder.appendingPathComponent("kick.wav"))
        let player = LegacyPreviewAudioPlayer()
        player.readResourceBytes = { url in
            Thread.sleep(forTimeInterval: 0.35)
            return try? Data(contentsOf: url)
        }
        var states: [PreviewAudioPreparationState] = []
        var samples: [Double] = []
        var finishes = 0
        var stops = 0
        player.onPreparationStateChanged = { states.append($0) }
        player.onElapsedSeconds = { samples.append($0) }
        player.onTimelineFinished = { finishes += 1 }
        player.onPlaybackStopped = { stops += 1 }
        player.playChart(
            documentData: Data("#WAV01 kick.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(states == [.preparing], "playChart did not report preparing before return, got \(states)")
        require(samples.isEmpty, "origin started while the load was still running")
        player.stop()
        require(stops == 1, "stop during prepare did not notify")
        require(states.contains(.cancelled), "prepare stop did not cancel, got \(states)")
        require(finishes == 0 && player.soundingSampleCount == 0, "prepare stop finished or sounded the chart")
        samples.removeAll()
        states.removeAll()
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 0.2
        )
        require(samples.first == 0, "the replacement chart did not start")
        require(waitUntil { finishes == 1 }, "the replacement chart did not finish")
        pump(0.45)
        require(player.soundingSampleCount == 0, "the cancelled load sounded during the next chart")
        require(finishes == 1, "the cancelled load finished the next chart again")
    }

    /// OGG/无法直接解析的文件仍走 `decodeToWav`，并且不在主线程。
    @MainActor
    private static func testDecodeToWavLeavesTheMainThread() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! Data(repeating: 0, count: 64).write(to: folder.appendingPathComponent("junk.wav"))
        let decoded = OSAllocatedUnfairLock(initialState: LoadProbe())
        let wav = toneWAV(duration: 0.20)
        let player = LegacyPreviewAudioPlayer()
        player.decodeToWav = { _ in
            decoded.withLock { probe in
                probe.calls += 1
                if Thread.isMainThread {
                    probe.mainCalls += 1
                }
            }
            return wav
        }
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 junk.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(
            waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 },
            "decoded note did not start with the origin"
        )
        let probe = decoded.withLock { $0 }
        require(probe.calls == 1 && probe.mainCalls == 0, "decodeToWav calls \(probe.calls), main \(probe.mainCalls)")
        require(player.diagnosticMainThreadResourceLoads == 0, "decode was counted on the main thread")
        player.stop()
    }

    /// 33 个同时重叠的音符只能占用 32 个声部，多出来的抢占最早的，而不是继续分配。
    @MainActor
    private static func testVoiceCapStealsInsteadOfGrowing() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.40).write(to: folder.appendingPathComponent("kick.wav"))
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        let notes = Array(repeating: PreviewAudioNote(beat: 0, wavToken: "01"), count: PreviewAudioLimits.maxVoices + 1)
        player.playChart(
            documentData: Data("#WAV01 kick.wav\n".utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(
            waitUntil { samples.first == 0 },
            "capped chart never became ready, engine \(player.diagnosticEngineFailure ?? "ok")"
        )
        require(player.diagnosticResourceLoads == 1, "the capped chord reloaded the wav")
        require(
            player.diagnosticVoiceCreations <= PreviewAudioLimits.maxVoices,
            "created \(player.diagnosticVoiceCreations) voices"
        )
        require(player.soundingSampleCount <= PreviewAudioLimits.maxVoices, "sounding \(player.soundingSampleCount)")
        require(player.diagnosticStolenVoices >= 1, "the extra note did not steal a voice")
        player.stop()
        require(player.soundingSampleCount == 0, "stop did not clear the stolen voices")
    }

    /// 50ms 音每 100ms 一颗。预排不能 stop 掉已经排上的 buffer。
    @MainActor
    private static func testSparseNotesAreNotCutByLookahead() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent("hit.wav"))
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        let notes = (0..<10).map { index in
            PreviewAudioNote(beat: Double(index) * 0.2, wavToken: "01")
        }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 }, "sparse chart did not become ready")
        require(player.diagnosticStolenVoices == 0, "lookahead stole \(player.diagnosticStolenVoices) at ready")
        require(player.diagnosticScheduleStops == 0, "lookahead stopped a node at ready")
        require(player.diagnosticVoiceCreations == 1, "sparse chart used \(player.diagnosticVoiceCreations) voices")
        require(
            waitUntil({ player.diagnosticScheduledCues == 10 }, timeout: 2.5),
            "scheduled \(player.diagnosticScheduledCues) of 10"
        )
        pump(0.30)
        require(player.diagnosticStolenVoices == 0, "later notes stole \(player.diagnosticStolenVoices)")
        require(player.diagnosticDroppedVoices == 0, "sparse notes were dropped")
        let bursts = burstCount(
            player.outputTapSamples(),
            rate: player.outputTapSampleRate,
            minGap: 0.02,
            threshold: 0.02
        )
        require(
            bursts == 10,
            "sparse PCM bursts \(bursts), samples \(player.outputTapSamples().count) at \(player.outputTapSampleRate)"
        )
        player.stop()
    }

    /// 140 和 500 个不同资源都在默认预算里，不能被 128 的空闲缓存上限静音。
    @MainActor
    private static func testWorkingSetStaysAudibleInsideBudget() {
        playUniqueChart(count: 140, tone: 0.03, spacing: 0.06, timeout: 12)
        playUniqueChart(count: 500, tone: 0.012, spacing: 0.02, timeout: 16)
    }

    @MainActor
    private static func playUniqueChart(count: Int, tone: Double, spacing: Double, timeout: Double) {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines = ""
        var notes: [PreviewAudioNote] = []
        for index in 0..<count {
            let token = wavToken(index)
            let name = "k\(index).wav"
            try! toneWAV(duration: tone).write(to: folder.appendingPathComponent(name))
            lines += "#WAV\(token) \(name)\n"
            notes.append(PreviewAudioNote(beat: Double(index) * spacing * 2, wavToken: token))
        }
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data(lines.utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: Double(count) * spacing * 2 + 4
        )
        require(
            waitUntil({ samples.first == 0 && player.diagnosticScheduledCues == count }, timeout: timeout),
            "\(count) unique scheduled \(player.diagnosticScheduledCues), shortfall \(player.diagnosticShortfallCues), resident \(player.diagnosticResidentResources)"
        )
        require(player.diagnosticShortfallCues == 0, "\(count) unique reported shortfall")
        require(player.diagnosticDroppedVoices == 0, "\(count) unique dropped voices")
        require(
            player.diagnosticResidentPCMBytes <= PreviewAudioLimits.maxCachedBytes,
            "\(count) unique resident PCM \(player.diagnosticResidentPCMBytes)"
        )
        require(player.diagnosticScheduleStops == 0, "\(count) unique stopped a voice")
        require(player.diagnosticResidentResources == count, "resident \(player.diagnosticResidentResources) of \(count)")
        require(player.diagnosticStolenVoices == 0, "\(count) unique stole")
        if spacing >= 0.05 {
            pump(0.50)
        }
        let tap = player.outputTapSamples()
        require(peak(tap) > 0.02, "\(count) unique opening tap was silent, frames \(tap.count)")
        if spacing >= 0.05 {
            let bursts = burstCount(tap, rate: player.outputTapSampleRate, minGap: spacing * 0.45, threshold: 0.02)
            require(bursts == count, "\(count) unique PCM bursts \(bursts)")
        }
        player.stop()
    }

    /// 预算小于一条 PCM 时仍准备并出声，读文件不在主线程。
    @MainActor
    private static func testSmallBudgetStillAudibleOffMain() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines = ""
        var notes: [PreviewAudioNote] = []
        for index in 0..<4 {
            let token = wavToken(index)
            let name = "b\(index).wav"
            try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent(name))
            lines += "#WAV\(token) \(name)\n"
            notes.append(PreviewAudioNote(beat: Double(index) * 1.6, wavToken: token))
        }
        let probe = OSAllocatedUnfairLock(initialState: LoadProbe())
        let opens = OSAllocatedUnfairLock(initialState: LoadProbe())
        let player = LegacyPreviewAudioPlayer()
        player.resourceByteBudget = 1000
        player.recordOutputForTests = true
        player.traceDiskAccess = { _ in
            probe.withLock { state in
                state.calls += 1
                if Thread.isMainThread { state.mainCalls += 1 }
            }
        }
        player.traceFileOpen = { isMain in
            opens.withLock { state in
                state.calls += 1
                if isMain { state.mainCalls += 1 }
            }
        }
        var states: [PreviewAudioPreparationState] = []
        var samples: [Double] = []
        player.onPreparationStateChanged = { states.append($0) }
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data(lines.utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(waitUntil { samples.first == 0 }, "small budget did not become ready, states \(states)")
        require(!states.contains(.failed), "small budget failed \(player.diagnosticPreparationFailure ?? "")")
        require(player.diagnosticShortfallCues == 0, "small budget reported shortfall")
        let disk = probe.withLock { $0 }
        require(disk.calls > 0 && disk.mainCalls == 0, "disk calls \(disk.calls), main \(disk.mainCalls)")
        let opened = opens.withLock { $0 }
        require(opened.calls >= 4 && opened.mainCalls == 0, "file opens \(opened.calls), main \(opened.mainCalls)")
        require(player.diagnosticResidentPCMBytes <= 1000, "small budget resident \(player.diagnosticResidentPCMBytes)")
        require(
            waitUntil({ player.diagnosticScheduledCues == 4 }, timeout: 4),
            "small budget scheduled \(player.diagnosticScheduledCues)"
        )
        pump(0.45)
        let bursts = burstCount(player.outputTapSamples(), rate: player.outputTapSampleRate, minGap: 0.40, threshold: 0.02)
        require(bursts == 4, "small budget bursts \(bursts)")
        player.stop()

        let encoded = toneWAV(duration: 0.40)
        try! Data([1, 2, 3, 4]).write(to: folder.appendingPathComponent("song.ogg"))
        let writes = OSAllocatedUnfairLock(initialState: LoadProbe())
        player.traceDiskAccess = { isWrite in
            guard isWrite else { return }
            writes.withLock { state in
                state.calls += 1
                if Thread.isMainThread { state.mainCalls += 1 }
            }
        }
        player.decodeToWav = { _ in encoded }
        player.recordOutputForTests = true
        samples.removeAll()
        player.playChart(
            documentData: Data("#WAV01 song.ogg\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 }, "decoded overflow did not sound")
        let wrote = writes.withLock { $0 }
        require(wrote.calls > 0 && wrote.mainCalls == 0, "temp wav writes \(wrote.calls), main \(wrote.mainCalls)")
        require(player.diagnosticPeakDecodedBytes < 256 * 1024, "decoded peak \(player.diagnosticPeakDecodedBytes)")
        player.stop()
    }

    /// 存在但解不了的文件要失败，不能当成缺文件静音并 ready。
    @MainActor
    private static func testUnsupportedFileDoesNotReady() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! Data(repeating: 0xAB, count: 64).write(to: folder.appendingPathComponent("junk.bin"))
        let player = LegacyPreviewAudioPlayer()
        var states: [PreviewAudioPreparationState] = []
        var samples: [Double] = []
        player.onPreparationStateChanged = { states.append($0) }
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 junk.bin\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { states.contains(.failed) }, "unsupported file did not fail, states \(states)")
        require(!states.contains(.ready), "unsupported file became ready")
        require(player.diagnosticPreparationFailure != nil, "missing failure reason")
        pump(0.15)
        require(samples.isEmpty, "failed chart emitted elapsed \(samples)")
    }

    /// 预算只够开场时，后面的音写到临时 PCM，临近时再装回来，不能把早音删掉。
    @MainActor
    private static func testSpillStillPlaysLaterNotes() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines = ""
        var notes: [PreviewAudioNote] = []
        for index in 0..<4 {
            let token = wavToken(index)
            let name = "s\(index).wav"
            try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent(name))
            lines += "#WAV\(token) \(name)\n"
            notes.append(PreviewAudioNote(beat: Double(index) * 1.6, wavToken: token))
        }
        let opens = OSAllocatedUnfairLock(initialState: LoadProbe())
        let player = LegacyPreviewAudioPlayer()
        player.resourceByteBudget = 10_000
        player.recordOutputForTests = true
        player.traceFileOpen = { isMain in
            opens.withLock { state in
                state.calls += 1
                if isMain { state.mainCalls += 1 }
            }
        }
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data(lines.utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(waitUntil { samples.first == 0 }, "spill chart did not become ready, states shortfall \(player.diagnosticShortfallCues)")
        require(player.diagnosticShortfallCues == 0, "opening window was treated as shortfall")
        require(player.diagnosticResidentPCMBytes <= 10_000, "resident PCM \(player.diagnosticResidentPCMBytes) exceeded 10000")
        require(player.diagnosticResidentPCMBytes > 0, "budget chart inlined nothing")
        require(player.diagnosticFileBackedResources >= 3, "file-backed \(player.diagnosticFileBackedResources)")
        let opened = opens.withLock { $0 }
        require(opened.calls >= 3 && opened.mainCalls == 0, "budget file opens \(opened.calls), main \(opened.mainCalls)")
        require(player.soundingSampleCount >= 1, "the earliest note was evicted")
        require(
            waitUntil({ player.diagnosticScheduledCues == 4 && player.diagnosticLateResourceMisses == 0 }, timeout: 4),
            "scheduled \(player.diagnosticScheduledCues), late \(player.diagnosticLateResourceMisses)"
        )
        pump(0.45)
        let bursts = burstCount(player.outputTapSamples(), rate: player.outputTapSampleRate, minGap: 0.40, threshold: 0.02)
        require(bursts == 4, "spilled notes produced \(bursts) bursts")
        require(player.diagnosticStolenVoices == 0, "spill playback stole a voice")
        player.stop()
    }

    /// 1/2/4 倍的 file 与 inline 都要在变速之后的 PCM 里逐格有能量。4 倍的静音缝只有 0.25ms。
    @MainActor
    private static func testDenseNonOverlappingFileNotes() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.005).write(to: folder.appendingPathComponent("tick.wav"))
        try! toneWAV(duration: 0.020, hz: 2200).write(to: folder.appendingPathComponent("mark.wav"))
        let notes = (0..<100).map { PreviewAudioNote(beat: Double($0) * 0.012, wavToken: "01") }
        let markerCharts = [0.19, 0.196, 0.202, 0.208, 0.39, 0.396, 0.402, 0.408]
        var mixed = notes
        for chart in markerCharts {
            mixed.append(PreviewAudioNote(beat: chart * 2, wavToken: "02"))
        }
        for playback in [1.0, 2.0, 4.0] {
            for budget in [1, 1_000_000] {
                let kind = budget == 1 ? "file" : "inline"
                let captured = playPressure(
                    folder: folder,
                    document: "#WAV01 tick.wav\n",
                    notes: notes,
                    budget: budget,
                    playback: playback
                )
                let slots = pressureSlots(captured.pcm, rate: captured.sampleRate, count: 100, playback: playback)
                let bands = slotBands(captured.pcm, rate: captured.sampleRate, count: 100, playback: playback)
                if playback == 4, budget == 1 {
                    writeTapWAV(captured.pcm, rate: captured.sampleRate, name: "rate4-file.wav")
                    let tail = pressureTail(captured.pcm, rate: captured.sampleRate, count: 100, playback: playback)
                    print(String(
                        format: "UA8 4x file: hits=%d bands=%d minRMS=%.4f gap=%.2fms opens=%d voices=%d steals=%d drops=%d prepare=%.1fms ready=%.1fms steady=%.1fms onset=%.1fms interval=%.3fms last2=%.4f,%.4f copies=%d late=%d",
                        slots.hits, bands, slots.minRMS, slots.gap * 1000,
                        captured.opens, captured.voices, captured.steals, captured.drops,
                        captured.prepare * 1000, captured.ready * 1000, captured.steady * 1000,
                        captured.onset * 1000, tail.interval * 1000, tail.lastPeaks.0, tail.lastPeaks.1,
                        captured.copies, captured.late
                    ))
                    require(captured.opens == 1 && captured.mainOpens == 0, "4x file opens \(captured.opens) main \(captured.mainOpens)")
                    require(captured.copies == 0, "4x file copied PCM \(captured.copies)")
                    require(captured.late == 0, "4x file late schedules \(captured.late)")
                    require(captured.onset > 0.02 && captured.onset < 0.15, "4x file onset \(captured.onset)")
                    require(abs(tail.interval - 0.0015) < 0.0004, "4x file interval \(tail.interval)")
                    require(captured.voices == 1, "4x file voices \(captured.voices)")
                }
                if playback == 4, budget != 1 {
                    writeTapWAV(captured.pcm, rate: captured.sampleRate, name: "rate4-inline.wav")
                    let tail = pressureTail(captured.pcm, rate: captured.sampleRate, count: 100, playback: playback)
                    print(String(
                        format: "UA8 4x inline: hits=%d bands=%d minRMS=%.4f gap=%.2fms onset=%.1fms interval=%.3fms last2=%.4f,%.4f copies=%d late=%d",
                        slots.hits, bands, slots.minRMS, slots.gap * 1000,
                        captured.onset * 1000, tail.interval * 1000, tail.lastPeaks.0, tail.lastPeaks.1,
                        captured.copies, captured.late
                    ))
                    require(captured.copies == 0, "4x inline copied PCM \(captured.copies)")
                    require(captured.late == 0, "4x inline late schedules \(captured.late)")
                }
                require(captured.scheduled == 100, "\(kind) \(playback)x scheduled \(captured.scheduled)")
                require(captured.drops == 0 && captured.steals == 0, "\(kind) \(playback)x drops \(captured.drops) steals \(captured.steals)")
                require(slots.hits == 100, "\(kind) \(playback)x slots \(slots.hits) minRMS \(slots.minRMS)")
                require(bands == 100, "\(kind) \(playback)x bands \(bands)")
                require(slots.gap <= 0.003, "\(kind) \(playback)x gap \(slots.gap)")
            }
        }
        let many = (0..<200).map { PreviewAudioNote(beat: Double($0) * 0.012, wavToken: "01") }
        for budget in [1, 1_000_000] {
            let kind = budget == 1 ? "file" : "inline"
            let captured = playPressure(
                folder: folder,
                document: "#WAV01 tick.wav\n",
                notes: many,
                budget: budget,
                playback: 4,
                pump: 0.55
            )
            let slots = pressureSlots(captured.pcm, rate: captured.sampleRate, count: 200, playback: 4)
            let bands = slotBands(captured.pcm, rate: captured.sampleRate, count: 200, playback: 4)
            let tail = pressureTail(captured.pcm, rate: captured.sampleRate, count: 200, playback: 4)
            writeTapWAV(captured.pcm, rate: captured.sampleRate, name: "rate4-\(kind)-200.wav")
            print(String(
                format: "UA8 4x %@ 200: hits=%d bands=%d minRMS=%.4f gap=%.2fms opens=%d voices=%d copies=%d late=%d last2=%.4f,%.4f",
                kind, slots.hits, bands, slots.minRMS, slots.gap * 1000,
                captured.opens, captured.voices, captured.copies, captured.late, tail.lastPeaks.0, tail.lastPeaks.1
            ))
            require(captured.scheduled == 200, "\(kind) 4x 200 scheduled \(captured.scheduled)")
            require(slots.hits == 200 && bands == 200, "\(kind) 4x 200 slots \(slots.hits) bands \(bands)")
            require(slots.gap <= 0.003, "\(kind) 4x 200 gap \(slots.gap)")
            require(captured.copies == 0 && captured.late == 0, "\(kind) 4x 200 copies \(captured.copies) late \(captured.late)")
            if budget == 1 {
                require(captured.opens == 1 && captured.voices == 1, "\(kind) 4x 200 opens \(captured.opens) voices \(captured.voices)")
            }
        }
        for budget in [1, 1_000_000] {
            let kind = budget == 1 ? "file" : "inline"
            let captured = playPressure(
                folder: folder,
                document: "#WAV01 tick.wav\n#WAV02 mark.wav\n",
                notes: mixed,
                budget: budget,
                playback: 4
            )
            let present = markerHits(captured.pcm, rate: captured.sampleRate, playback: 4, charts: markerCharts)
            writeTapWAV(captured.pcm, rate: captured.sampleRate, name: "rate4-\(kind)-markers.wav")
            print("UA8 markers \(kind): \(present)/\(markerCharts.count) scheduled=\(captured.scheduled) voices=\(captured.voices) steals=\(captured.steals) drops=\(captured.drops) late=\(captured.late) opens=\(captured.opens)")
            require(present == markerCharts.count, "\(kind) markers \(present)")
        }
    }

    @MainActor
    private static func testSparseNotesAtFourX() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.040).write(to: folder.appendingPathComponent("hit.wav"))
        let notes = (0..<8).map { PreviewAudioNote(beat: Double($0) * 1.0, wavToken: "01") }
        let captured = playPressure(folder: folder, document: "#WAV01 hit.wav\n", notes: notes, budget: 1, playback: 4, pump: 1.2)
        let slots = pressureSlots(captured.pcm, rate: captured.sampleRate, count: 8, playback: 4, spacing: 0.50, tone: 0.040)
        require(slots.hits == 8, "sparse 4x slots \(slots.hits) minRMS \(slots.minRMS)")
        require(captured.mainOpens == 0, "sparse 4x opened on main")
    }

    @MainActor
    private static func testDynamicRateKeepsTheTone() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 3.0).write(to: folder.appendingPathComponent("tone.wav"))
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        player.setPlaybackRate(1)
        var ready = false
        var elapsed = 0.0
        var callbackCount = 0
        var stops = 0
        var finishes = 0
        player.onElapsedSeconds = { sample in
            elapsed = sample
            callbackCount += 1
            if sample == 0 { ready = true }
        }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data("#WAV01 tone.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(waitUntil { ready && player.soundingSampleCount >= 1 }, "dynamic chart did not start")
        pump(0.12)
        require(recentTone(player, hz: 440, against: 1760), "rate 1 was not 440Hz")
        player.setPlaybackRate(4)
        require(abs(player.requestedPlaybackRate - 4) < 0.001, "dynamic 4x became \(player.requestedPlaybackRate)")
        pump(0.12)
        require(recentTone(player, hz: 1760, against: 440), "rate 4 was not 1760Hz")
        let before = elapsed
        let callbacksBefore = callbackCount
        player.pauseChart()
        let frozen = elapsed
        let frozenWall = player.presentationWallElapsedSeconds
        let pausedCallbacks = callbackCount
        require(frozen >= before, "pause rewound \(before) to \(frozen)")
        require(pausedCallbacks == callbacksBefore + 1, "pause missed the final sample \(pausedCallbacks) from \(callbacksBefore)")
        require(player.isChartPaused, "pause did not stick")
        pump(0.12)
        require(abs(elapsed - frozen) < 0.000_1, "elapsed moved while paused \(elapsed) from \(frozen)")
        require(abs(player.presentationWallElapsedSeconds - frozenWall) < 0.000_1, "pause did not freeze wall time")
        require(callbackCount == pausedCallbacks, "paused callbacks moved \(callbackCount) from \(pausedCallbacks)")
        player.setPlaybackRate(0.5)
        require(abs(player.requestedPlaybackRate - 0.5) < 0.001, "paused rate became \(player.requestedPlaybackRate)")
        pump(0.12)
        require(abs(elapsed - frozen) < 0.000_1, "paused rate change moved elapsed \(elapsed) from \(frozen)")
        require(abs(player.presentationWallElapsedSeconds - frozenWall) < 0.000_1, "paused rate change moved wall")
        require(callbackCount == pausedCallbacks, "paused rate change moved callbacks \(callbackCount) from \(pausedCallbacks)")
        require(player.isChartPaused, "paused rate change cleared the pause")
        require(stops == 0 && finishes == 0, "pause ended the chart")
        player.resumeChart()
        require(abs(player.requestedPlaybackRate - 0.5) < 0.001, "resume left \(player.requestedPlaybackRate)")
        pump(0.20)
        require(elapsed > frozen + 0.05, "resume did not advance \(elapsed)")
        require(recentTone(player, hz: 220, against: 440), "rate 0.5 was not 220Hz")
        player.stop()
    }

    /// 超过内联上限的连续音，4 倍速要跨过 3 秒分块的接缝。
    @MainActor
    private static func testLongStreamStaysContinuousAtFourX() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 4.0, channels: 2).write(to: folder.appendingPathComponent("stream.wav"))
        let captured = playPressure(
            folder: folder,
            document: "#WAV01 stream.wav\n",
            notes: [PreviewAudioNote(beat: 0, wavToken: "01", kind: .bgm)],
            budget: PreviewAudioLimits.maxCachedBytes,
            playback: 4,
            pump: 1.05
        )
        let gap = interiorGap(captured.pcm, rate: captured.sampleRate)
        require(captured.streamBlock > 1_000_000, "4x stream block \(captured.streamBlock)")
        require(gap <= 0.003, "4x stream gap \(gap)")
        require(
            toneWins(captured.pcm, rate: captured.sampleRate, hz: 1760, against: 440),
            "4x stream was not 1760Hz"
        )
        require(captured.mainOpens == 0, "4x stream opened on main")
        print(String(format: "UA7 stream: block=%d gap=%.2fms", captured.streamBlock, gap * 1000))
    }

    /// 上限固定为 4，不随 44100、48000、96000、192000 改变。2 倍在高采样率上仍是 2 倍。
    @MainActor
    private static func testRateCeilingIgnoresSampleRate() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.20).write(to: folder.appendingPathComponent("plain.wav"))
        for sampleRate in [44_100, 48_000, 96_000, 192_000] {
            let name = "rate\(sampleRate).wav"
            try! toneWAV(duration: 0.30, sampleRate: sampleRate).write(to: folder.appendingPathComponent(name))
            let player = LegacyPreviewAudioPlayer()
            player.recordOutputForTests = sampleRate >= 96_000
            player.setPlaybackRate(.nan)
            player.setPlaybackRate(.infinity)
            require(abs(player.requestedPlaybackRate - 1) < 0.001, "non-finite request changed the default at \(sampleRate)")
            player.setPlaybackRate(8)
            var ready = false
            player.onElapsedSeconds = { sample in
                if sample == 0 { ready = true }
            }
            player.playChart(
                documentData: Data("#WAV01 \(name)\n".utf8),
                chartDirectory: folder,
                notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
                timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
                fromBeat: 0,
                visualEndBeat: 4
            )
            require(waitUntil { ready }, "\(sampleRate) chart did not become ready")
            require(abs(player.requestedPlaybackRate - 4) < 0.001, "\(sampleRate) prepared at \(player.requestedPlaybackRate)")
            player.setPlaybackRate(.nan)
            player.setPlaybackRate(.infinity)
            require(abs(player.requestedPlaybackRate - 4) < 0.001, "non-finite request cleared \(sampleRate)")
            player.pauseChart()
            require(abs(player.requestedPlaybackRate - 4) < 0.001, "\(sampleRate) pause moved the rate")
            player.resumeChart()
            require(abs(player.requestedPlaybackRate - 4) < 0.001, "\(sampleRate) resume moved the rate")
            player.stop()
            ready = false
            player.playChart(
                documentData: Data("#WAV01 \(name)\n".utf8),
                chartDirectory: folder,
                notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
                timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
                fromBeat: 0,
                visualEndBeat: 4
            )
            require(waitUntil { ready }, "\(sampleRate) replay did not become ready")
            require(abs(player.requestedPlaybackRate - 4) < 0.001, "\(sampleRate) replay moved the rate")
            player.stop()
        }

        for sampleRate in [96_000, 192_000] {
            let name = "pitch\(sampleRate).wav"
            try! toneWAV(duration: 0.40, sampleRate: sampleRate).write(to: folder.appendingPathComponent(name))
            let player = LegacyPreviewAudioPlayer()
            player.recordOutputForTests = true
            player.setPlaybackRate(2)
            var ready = false
            player.onElapsedSeconds = { sample in
                if sample == 0 { ready = true }
            }
            player.playChart(
                documentData: Data("#WAV01 \(name)\n".utf8),
                chartDirectory: folder,
                notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
                timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
                fromBeat: 0,
                visualEndBeat: 4
            )
            require(waitUntil { ready && player.soundingSampleCount >= 1 }, "\(sampleRate) 2x did not sound")
            require(abs(player.requestedPlaybackRate - 2) < 0.001, "\(sampleRate) 2x became \(player.requestedPlaybackRate)")
            pump(0.22)
            require(
                toneWins(player.outputTapSamples(), rate: player.outputTapSampleRate, hz: 880, against: 440),
                "\(sampleRate) 2x tap was not 880Hz"
            )
            player.pauseChart()
            player.resumeChart()
            require(abs(player.requestedPlaybackRate - 2) < 0.001, "\(sampleRate) pause resume left \(player.requestedPlaybackRate)")
            player.stop()
            ready = false
            player.playChart(
                documentData: Data("#WAV02 plain.wav\n".utf8),
                chartDirectory: folder,
                notes: [PreviewAudioNote(beat: 0, wavToken: "02")],
                timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
                fromBeat: 0,
                visualEndBeat: 4
            )
            require(waitUntil { ready }, "resource switch did not become ready")
            require(abs(player.requestedPlaybackRate - 2) < 0.001, "resource switch left \(player.requestedPlaybackRate)")
            player.stop()
        }
        print("UA6 ceiling: 44100/48000/96000/192000=4 96k/192k-2x=2")
    }

    /// 32 个 44.1k 声部停掉之后，48k 和立体声必须能改接空闲声部。
    @MainActor
    private static func testFormatPoolReconfiguresAcrossCharts() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.30).write(to: folder.appendingPathComponent("a.wav"))
        try! toneWAV(duration: 0.30, sampleRate: 48_000, channels: 2).write(to: folder.appendingPathComponent("b.wav"))
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        let chord = Array(repeating: PreviewAudioNote(beat: 0, wavToken: "01"), count: 32)
        player.playChart(
            documentData: Data("#WAV01 a.wav\n".utf8),
            chartDirectory: folder,
            notes: chord,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 }, "44.1k chord did not become ready")
        require(player.diagnosticVoiceCreations == 32, "created \(player.diagnosticVoiceCreations)")
        player.stop()
        let created = player.diagnosticVoiceCreations
        samples.removeAll()
        player.recordOutputForTests = true
        player.playChart(
            documentData: Data("#WAV01 b.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 }, "48k chart did not become ready")
        require(player.diagnosticDroppedVoices == 0, "48k note was dropped")
        require(player.diagnosticVoiceCreations == created, "48k allocated a new voice, creations \(player.diagnosticVoiceCreations)")
        require(player.diagnosticScheduledCues == 1, "48k note was not scheduled")
        pump(0.12)
        require(peak(player.outputTapSamples()) > 0.02, "48k note produced no PCM")
        player.stop()

        samples.removeAll()
        player.playChart(
            documentData: Data("#WAV01 a.wav\n#WAV02 b.wav\n".utf8),
            chartDirectory: folder,
            notes: [
                PreviewAudioNote(beat: 0, wavToken: "01"),
                PreviewAudioNote(beat: 0, wavToken: "02")
            ],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 && player.diagnosticScheduledCues == 2 }, "mixed formats did not both schedule")
        require(player.diagnosticDroppedVoices == 0, "mixed formats dropped a note")
        require(
            waitUntil { player.diagnosticVoiceTimelineSeconds().count == 2 },
            "mixed formats did not both start, clocks \(player.diagnosticVoiceTimelineSeconds())"
        )
        let clocks = player.diagnosticVoiceTimelineSeconds()
        require(
            abs(clocks[0] - clocks[1]) < 0.02,
            "voice timelines drifted \(clocks)"
        )
        pump(0.12)
        let mixedTap = player.outputTapSamples()
        require(peak(mixedTap) > 0.02, "mixed formats produced no PCM, frames \(mixedTap.count) peak \(peak(mixedTap))")
        player.stop()
    }

    /// ready 回调里 stop 或重播，旧的 elapsed 0 不能再写出来。
    @MainActor
    private static func testReadyCallbackCannotEmitStaleElapsed() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.20).write(to: folder.appendingPathComponent("hit.wav"))
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let document = Data("#WAV01 hit.wav\n".utf8)
        let player = LegacyPreviewAudioPlayer()
        var events: [String] = []
        player.onPreparationStateChanged = { state in
            events.append("\(state)")
            if state == .ready {
                player.stop()
            }
        }
        player.onElapsedSeconds = { events.append("elapsed:\($0)") }
        player.onPlaybackStopped = { events.append("stopped") }
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { events.contains("stopped") }, "ready callback stop did not run, events \(events)")
        pump(0.20)
        require(
            events == ["preparing", "ready", "stopped"],
            "stop inside ready produced \(events)"
        )

        events.removeAll()
        var readyCount = 0
        player.onPreparationStateChanged = { state in
            events.append("\(state)")
            if state == .ready {
                readyCount += 1
                if readyCount == 1 {
                    player.playChart(
                        documentData: Data(),
                        chartDirectory: nil,
                        notes: [],
                        timing: timing,
                        fromBeat: 0,
                        visualEndBeat: 0
                    )
                }
            }
        }
        player.onElapsedSeconds = { events.append("elapsed:\($0)") }
        player.onPlaybackStopped = { events.append("stopped") }
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { events.contains("elapsed:0.0") }, "replay from ready produced \(events)")
        pump(0.20)
        require(readyCount == 2, "replay ready count \(readyCount), events \(events)")
        require(
            events.filter { $0.hasPrefix("elapsed") } == ["elapsed:0.0"],
            "stale elapsed leaked, events \(events)"
        )
    }

    /// 自然结束和 elapsed 回调里换谱，旧收尾不能关掉新时间轴。
    @MainActor
    private static func testFinishAndElapsedCallbacksCannotResumeOldTimeline() {
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let player = LegacyPreviewAudioPlayer()
        var finishes = 0
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.onTimelineFinished = {
            finishes += 1
            if finishes == 1 {
                player.playChart(
                    documentData: Data(),
                    chartDirectory: nil,
                    notes: [],
                    timing: timing,
                    fromBeat: 0,
                    visualEndBeat: 8
                )
            }
        }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 0.2
        )
        require(waitUntil { samples.contains { $0 > 0.3 } && finishes == 1 }, "replacement chart did not keep its clock, finishes \(finishes) samples \(samples)")
        player.stop()

        samples.removeAll()
        finishes = 0
        var replaced = false
        player.onTimelineFinished = { finishes += 1 }
        player.onElapsedSeconds = { elapsed in
            samples.append(elapsed)
            if !replaced, elapsed >= 0.1 {
                replaced = true
                player.playChart(
                    documentData: Data(),
                    chartDirectory: nil,
                    notes: [],
                    timing: timing,
                    fromBeat: 0,
                    visualEndBeat: 8
                )
            }
        }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 0.2
        )
        require(
            waitUntil { samples.contains { $0 > 0.3 } && finishes == 0 },
            "elapsed callback replacement was closed, finishes \(finishes) samples \(samples)"
        )
        player.stop()
    }

    /// 数万个音只碰提前量里新进入的那几颗，不能每轮扫全谱。
    @MainActor
    private static func testScheduleCursorDoesNotRescanTheChart() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent("hit.wav"))
        let player = LegacyPreviewAudioPlayer()
        let count = 20_000
        let notes = (0..<count).map { index in
            PreviewAudioNote(beat: Double(index) * 4, wavToken: "01")
        }
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 }, "cursor chart did not become ready")
        require(player.diagnosticCueCount == count, "cue count \(player.diagnosticCueCount)")
        pump(0.40)
        require(
            player.diagnosticMaxPumpCueTouches < 32,
            "a pump touched \(player.diagnosticMaxPumpCueTouches) of \(count)"
        )
        require(
            player.diagnosticTotalCueTouches < 100,
            "pumps touched \(player.diagnosticTotalCueTouches) cue slots"
        )
        require(player.diagnosticTotalCueTouches > 0, "the cursor never ran")
        player.stop()
    }

    /// 不同采样率和声道的声部从同一个 host 起点起算。
    @MainActor
    private static func testVoicesShareOneHostOrigin() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.40).write(to: folder.appendingPathComponent("mono.wav"))
        try! toneWAV(duration: 0.40, sampleRate: 48_000, channels: 2).write(to: folder.appendingPathComponent("stereo.wav"))
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 mono.wav\n#WAV02 stereo.wav\n".utf8),
            chartDirectory: folder,
            notes: [
                PreviewAudioNote(beat: 0, wavToken: "01"),
                PreviewAudioNote(beat: 0, wavToken: "02")
            ],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 }, "shared origin chart did not become ready")
        require(
            waitUntil { player.diagnosticVoiceTimelineSeconds().count == 2 },
            "both voices did not report a timeline, \(player.diagnosticVoiceTimelineSeconds())"
        )
        let clocks = player.diagnosticVoiceTimelineSeconds()
        require(abs(clocks[0] - clocks[1]) < 0.02, "host origins diverged \(clocks)")
        pump(0.12)
        let sharedTap = player.outputTapSamples()
        require(peak(sharedTap) > 0.02, "shared origin produced no PCM, frames \(sharedTap.count)")
        require(player.soundingSampleCount >= 1, "shared origin was silent")
        player.stop()
    }

    /// 约 4 分钟立体声 WAV。开头和 seek 到尾部都要听到对应频率，峰值不能是整段 Float32。
    @MainActor
    private static func testLongBGMStreamsAndSeeks() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("bgm.wav")
        let seconds = 4.0 * 60.0
        let tailAt = seconds - 0.45
        writeLongWAV(url: url, seconds: seconds, headSeconds: 0.35, tailAt: tailAt, tailSeconds: 0.45)
        let sourceSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        require(sourceSize > 40_000_000, "long wav is \(sourceSize) bytes")
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let document = Data("#WAV01 bgm.wav\n".utf8)
        let opens = OSAllocatedUnfairLock(initialState: LoadProbe())
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        player.traceFileOpen = { isMain in
            opens.withLock { state in
                state.calls += 1
                if isMain { state.mainCalls += 1 }
            }
        }
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01", kind: .bgm)],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(waitUntil { samples.first == 0 }, "long BGM did not become ready \(player.diagnosticPreparationFailure ?? "")")
        require(player.diagnosticSourceFileBytes > 40_000_000, "source bytes \(player.diagnosticSourceFileBytes)")
        require(player.diagnosticPeakDecodedBytes < 2_000_000, "decoded peak \(player.diagnosticPeakDecodedBytes)")
        require(
            player.diagnosticStreamBlockBytes > 1_000_000 && player.diagnosticStreamBlockBytes < 2_000_000,
            "stream block \(player.diagnosticStreamBlockBytes)"
        )
        pump(0.25)
        let head = player.outputTapSamples()
        require(toneWins(head, rate: player.outputTapSampleRate, hz: 440, against: 880), "head tap was not 440Hz, frames \(head.count)")
        let opened = opens.withLock { $0 }
        require(opened.calls >= 1 && opened.mainCalls == 0, "long BGM file opens \(opened.calls), main \(opened.mainCalls)")
        print(String(
            format: "UA4 long-bgm: sourceBytes=%d peakDecoded=%d streamBlock=%d",
            player.diagnosticSourceFileBytes,
            player.diagnosticPeakDecodedBytes,
            player.diagnosticStreamBlockBytes
        ))
        player.stop()

        samples.removeAll()
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01", kind: .bgm)],
            timing: timing,
            fromBeat: tailAt * 2,
            visualEndBeat: tailAt * 2 + 4
        )
        require(waitUntil { samples.first == 0 }, "seeked BGM did not become ready")
        pump(0.30)
        let tail = player.outputTapSamples()
        require(toneWins(tail, rate: player.outputTapSampleRate, hz: 880, against: 440), "tail tap was not 880Hz, frames \(tail.count)")
        require(player.diagnosticPeakDecodedBytes < 2_000_000, "seek decoded peak \(player.diagnosticPeakDecodedBytes)")
        player.stop()
    }

    @MainActor
    private static func testPauseAndResumeKeepElapsed() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.80).write(to: folder.appendingPathComponent("hit.wav"))
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { (samples.last ?? 0) > 0.12 }, "pause chart did not advance")
        let loads = player.diagnosticResourceLoads
        player.pauseChart()
        require(player.isChartPaused, "pause did not stick")
        require(stops == 0 && finishes == 0, "pause ended the chart")
        let frozen = samples.last ?? -1
        pump(0.30)
        require(abs((samples.last ?? -2) - frozen) < 0.000_1, "elapsed moved while paused \(samples)")
        require(player.soundingSampleCount >= 1, "pause dropped the sounding note")
        player.resumeChart()
        require(!player.isChartPaused, "resume left the chart paused")
        require(
            waitUntil { (samples.last ?? 0) > frozen + 0.12 },
            "resume did not continue elapsed, frozen \(frozen) samples \(samples)"
        )
        require(player.diagnosticResourceLoads == loads, "resume loaded resources again")
        player.stop()

        samples.removeAll()
        stops = 0
        finishes = 0
        player.recordOutputForTests = true
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4,
            startPaused: true
        )
        require(waitUntil { samples.first == 0 && player.isChartPaused }, "startPaused did not prepare")
        require(player.soundingSampleCount == 0, "startPaused already sounded")
        require(stops == 0 && finishes == 0, "startPaused stopped or finished")
        pump(0.20)
        require(samples == [0], "startPaused clock ran \(samples)")
        require(peak(player.outputTapSamples()) < 0.02, "startPaused produced PCM \(peak(player.outputTapSamples()))")
        let preparedLoads = player.diagnosticResourceLoads
        player.resumeChart()
        require(
            waitUntil { player.soundingSampleCount >= 1 && (samples.last ?? 0) > 0.05 },
            "resume from startPaused did not continue"
        )
        require(player.diagnosticResourceLoads == preparedLoads, "startPaused resume reloaded")
        player.stop()
    }

    @MainActor
    private static func testAudibleKindsFilterLaterCues() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.20).write(to: folder.appendingPathComponent("key.wav"))
        try! toneWAV(duration: 0.20).write(to: folder.appendingPathComponent("mine.wav"))
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 key.wav\n#WAV02 mine.wav\n".utf8),
            chartDirectory: folder,
            notes: [
                PreviewAudioNote(beat: 0, wavToken: "01", kind: .key),
                PreviewAudioNote(beat: 0, wavToken: "02", kind: .mine),
                PreviewAudioNote(beat: 1, wavToken: "02", kind: .mine)
            ],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 }, "key note did not sound")
        require(player.diagnosticResourceLoads == 2, "inaudible mine was not prepared, loads \(player.diagnosticResourceLoads)")
        pump(0.05)
        require(player.diagnosticScheduledCues == 1, "mine at the start was scheduled")
        player.setAudibleKinds([.key, .bgm, .mine])
        require(
            waitUntil { player.diagnosticScheduledCues == 2 },
            "later mine did not become audible, scheduled \(player.diagnosticScheduledCues)"
        )
        player.stop()
    }

    /// 无声、缺文件和只有画面终点的时间轴也要停在 startPaused，续播不启动空引擎。
    @MainActor
    private static func testStartPausedFreezesSilentTimelines() {
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var stops = 0
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onPlaybackStopped = { stops += 1 }
        player.onTimelineFinished = { finishes += 1 }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8,
            startPaused: true
        )
        require(waitUntil { samples.first == 0 && player.isChartPaused }, "silent startPaused did not prepare")
        pump(0.35)
        require(samples == [0], "silent startPaused elapsed moved \(samples)")
        require(player.isChartPaused, "silent startPaused cleared the pause")
        require(stops == 0 && finishes == 0, "silent startPaused ended the timeline")
        require(abs(player.presentationWallElapsedSeconds) < 0.000_1, "silent wall elapsed \(player.presentationWallElapsedSeconds)")
        player.resumeChart()
        require(!player.isChartPaused, "silent resume stayed paused")
        require(
            waitUntil { (samples.last ?? 0) > 0.20 },
            "silent resume did not advance \(samples)"
        )
        require(stops == 0 && finishes == 0, "silent resume stopped or finished")
        player.stop()

        samples.removeAll()
        stops = 0
        finishes = 0
        player.playChart(
            documentData: Data("#WAV01 missing.wav\n".utf8),
            chartDirectory: URL(fileURLWithPath: "/tmp/ibms-preview-missing", isDirectory: true),
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8,
            startPaused: true
        )
        require(waitUntil { samples.first == 0 && player.isChartPaused }, "missing-file startPaused did not prepare")
        pump(0.35)
        require(samples == [0], "missing-file startPaused elapsed moved \(samples)")
        require(player.isChartPaused, "missing-file startPaused cleared the pause")
        player.resumeChart()
        require(
            waitUntil { (samples.last ?? 0) > 0.20 && !player.isChartPaused },
            "missing-file resume did not advance \(samples)"
        )
        player.stop()
    }

    /// 倍率必须改变 tap 里的音高和音符间隔。elapsed 只用来核对谱面秒，不代替变频。
    @MainActor
    private static func testPlaybackRateChangesPitchAndTimeline() {
        let cold = LegacyPreviewAudioPlayer()
        cold.setPlaybackRate(9)
        require(abs(cold.requestedPlaybackRate - 4) < 0.001, "unknown-rate ceiling \(cold.requestedPlaybackRate)")
        cold.setPlaybackRate(0.05)
        require(abs(cold.requestedPlaybackRate - 0.25) < 0.001, "rate floor \(cold.requestedPlaybackRate)")

        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 1.4).write(to: folder.appendingPathComponent("tone.wav"))
        try! toneWAV(duration: 0.08).write(to: folder.appendingPathComponent("tick.wav"))
        try! toneWAV(duration: 2.0).write(to: folder.appendingPathComponent("long.wav"))
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        player.setPlaybackRate(1)
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 tone.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 }, "rate chart did not start")
        pump(0.18)
        require(
            toneWins(player.outputTapSamples(), rate: player.outputTapSampleRate, hz: 440, against: 880),
            "rate 1 tap was not 440Hz"
        )
        let chartBefore = samples.last ?? 0
        require(chartBefore > 0.08, "chart did not advance before the rate change \(chartBefore)")
        player.setPlaybackRate(2)
        require(abs(player.requestedPlaybackRate - 2) < 0.001, "applied rate \(player.requestedPlaybackRate)")
        let chartAtChange = samples.last ?? 0
        require(chartAtChange + 0.03 >= chartBefore, "rate change rewound \(chartBefore) to \(chartAtChange)")
        let wallAtChange = player.playbackWallElapsedSeconds()
        require(abs(wallAtChange - player.presentationWallElapsedSeconds) < 0.000_1, "wall accessors diverged")
        pump(0.28)
        let chartLater = samples.last ?? 0
        let wallLater = player.presentationWallElapsedSeconds
        require(chartLater > chartAtChange + 0.40, "chart seconds did not track rate 2, \(chartAtChange) -> \(chartLater)")
        require(
            wallLater - wallAtChange < (chartLater - chartAtChange) * 0.8,
            "wall elapsed \(wallLater - wallAtChange) was scaled with chart \(chartLater - chartAtChange)"
        )
        require(
            toneWins(player.outputTapSamples(), rate: player.outputTapSampleRate, hz: 880, against: 440),
            "live rate 2 tap was not 880Hz"
        )
        player.pauseChart()
        let frozen = samples.last ?? -1
        let frozenWall = player.presentationWallElapsedSeconds
        pump(0.20)
        require(abs((samples.last ?? -2) - frozen) < 0.000_1, "pause did not freeze chart time")
        require(abs(player.presentationWallElapsedSeconds - frozenWall) < 0.000_1, "pause did not freeze wall time")
        player.setPlaybackRate(2)
        pump(0.12)
        require(abs((samples.last ?? -2) - frozen) < 0.000_1, "rate change while paused moved elapsed")
        player.resumeChart()
        require(
            waitUntil { (samples.last ?? 0) > frozen + 0.15 },
            "resume after rate change did not continue from \(frozen)"
        )
        require(
            toneWins(player.outputTapSamples(), rate: player.outputTapSampleRate, hz: 880, against: 440),
            "resume at rate 2 tap was not 880Hz"
        )
        player.setPlaybackRate(9)
        let ceiling = player.requestedPlaybackRate
        require(abs(ceiling - PreviewAudioLimits.maximumPlaybackRate) < 0.001, "rate ceiling \(ceiling)")
        player.stop()

        samples.removeAll()
        player.setPlaybackRate(2)
        player.playChart(
            documentData: Data("#WAV02 tick.wav\n".utf8),
            chartDirectory: folder,
            notes: [
                PreviewAudioNote(beat: 0, wavToken: "02"),
                PreviewAudioNote(beat: 1, wavToken: "02")
            ],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 }, "interval chart did not start")
        pump(0.55)
        let gaps = burstStarts(player.outputTapSamples(), rate: player.outputTapSampleRate, minGap: 0.08, threshold: 0.02)
        require(gaps.count >= 2, "rate 2 produced \(gaps.count) bursts")
        let interval = gaps[1] - gaps[0]
        require(interval > 0.15 && interval < 0.38, "500ms chart gap became wall \(interval)s, bursts \(gaps)")
        let heard = player.outputTapSamples()
        let opening = Array(heard.prefix(min(heard.count, Int(player.outputTapSampleRate * 0.12))))
        require(
            toneWins(opening, rate: player.outputTapSampleRate, hz: 880, against: 440),
            "interval taps were not 880Hz"
        )
        player.stop()

        samples.removeAll()
        let stopped = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [],
            stopEvents: [(beat: 1, durationSeconds: 1)]
        )
        let stopNotes = [
            PreviewAudioNote(beat: 0, wavToken: "02"),
            PreviewAudioNote(beat: 2, wavToken: "02")
        ]
        let hits = LegacyPreviewAudio.scheduleHits(
            notes: stopNotes,
            timing: stopped,
            fromBeat: 0
        )
        require(hits.count == 2 && hits[1].seconds > hits[0].seconds + 1, "stop schedule \(hits.map(\.seconds))")
        let chartGap = hits[1].seconds - hits[0].seconds
        player.setPlaybackRate(2)
        player.playChart(
            documentData: Data("#WAV02 tick.wav\n".utf8),
            chartDirectory: folder,
            notes: stopNotes,
            timing: stopped,
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(waitUntil { samples.first == 0 }, "stop-rate chart did not start")
        pump(chartGap / 2 + 0.35)
        let stopGaps = burstStarts(player.outputTapSamples(), rate: player.outputTapSampleRate, minGap: 0.12, threshold: 0.02)
        require(stopGaps.count >= 2, "rate 2 STOP produced \(stopGaps.count) bursts")
        let stopWall = stopGaps[1] - stopGaps[0]
        require(
            abs(stopWall - chartGap / 2) < 0.12,
            "STOP wall \(stopWall)s, chart gap \(chartGap)s at rate 2"
        )
        player.stop()

        samples.removeAll()
        player.setPlaybackRate(2)
        player.playChart(
            documentData: Data("#WAV03 long.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "03")],
            timing: timing,
            fromBeat: 2,
            visualEndBeat: 8
        )
        require(waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 }, "Here chart did not carry audio")
        require(samples.allSatisfy { $0 >= 0 }, "Here emitted a negative elapsed \(samples)")
        pump(0.22)
        require(
            toneWins(player.outputTapSamples(), rate: player.outputTapSampleRate, hz: 880, against: 440),
            "Here at rate 2 tap was not 880Hz"
        )
        let hereChart = samples.last ?? 0
        let hereWall = player.presentationWallElapsedSeconds
        require(hereChart > hereWall * 1.4, "Here chart \(hereChart) did not outrun wall \(hereWall)")
        require(hereWall > 0.05, "Here wall origin stayed negative \(hereWall)")
        print(String(
            format: "UA6 rate: ceiling=%.2f interval=%.3f stopWall=%.3f hereChart=%.3f hereWall=%.3f",
            ceiling,
            interval,
            stopWall,
            hereChart,
            hereWall
        ))
        player.stop()

        testChordInflightIsSeparateFromResidentBudget(folder: folder)
    }

    /// 开场大和弦的在途缓冲可以大于驻留 PCM。句柄在准备时打开。
    @MainActor
    private static func testChordInflightIsSeparateFromResidentBudget(folder: URL) {
        var lines = ""
        var notes: [PreviewAudioNote] = []
        for index in 0..<32 {
            let token = wavToken(index + 20)
            let name = "c\(index).wav"
            try! toneWAV(duration: 0.50).write(to: folder.appendingPathComponent(name))
            lines += "#WAV\(token) \(name)\n"
            notes.append(PreviewAudioNote(beat: 0, wavToken: token))
        }
        let opens = OSAllocatedUnfairLock(initialState: LoadProbe())
        let player = LegacyPreviewAudioPlayer()
        player.resourceByteBudget = 1000
        player.recordOutputForTests = true
        player.traceFileOpen = { isMain in
            opens.withLock { state in
                state.calls += 1
                if isMain { state.mainCalls += 1 }
            }
        }
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data(lines.utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 && player.diagnosticScheduledCues == 32 }, "chord scheduled \(player.diagnosticScheduledCues)")
        require(player.diagnosticDroppedVoices == 0, "chord dropped \(player.diagnosticDroppedVoices)")
        require(player.diagnosticResidentPCMBytes <= 1000, "chord resident \(player.diagnosticResidentPCMBytes)")
        require(
            player.diagnosticInflightScheduledBytes > player.diagnosticResidentPCMBytes,
            "inflight \(player.diagnosticInflightScheduledBytes) was not listed apart from resident \(player.diagnosticResidentPCMBytes)"
        )
        let opened = opens.withLock { $0 }
        require(opened.calls >= 32 && opened.mainCalls == 0, "chord file opens \(opened.calls), main \(opened.mainCalls)")
        pump(0.12)
        require(peak(player.outputTapSamples()) > 0.02, "chord tap was silent")
        player.stop()

        testSharedFileTwoOffsets(folder: folder)
    }

    /// 同一份文件可以只打开一次。两声仍要落在各自的采样位置。
    /// 前 0.10 秒 440Hz，后 0.30 秒 880Hz，第二声晚 0.10 秒。
    /// 参考由源 PCM 独立相加，再乘混音器声明的输出增益 0.5。
    @MainActor
    private static func testSharedFileTwoOffsets(folder: URL) {
        let sampleRate = 48_000
        let outputGain: Float = 0.5
        let delayFrames = sampleRate / 10
        let cycle = 1_200
        // 稳定窗离开分段边界 0.02 秒，与起点间隔、结束时间用的既有时间容差相同。幅度仍按 0.02。
        let smear = sampleRate / 50
        let material = overlapSegmentPCM(sampleRate: sampleRate, headFrames: delayFrames, tailFrames: delayFrames * 3)
        try! material.wav.write(to: folder.appendingPathComponent("overlap.wav"))
        let source = material.source
        var reference = [Float](repeating: 0, count: source.count + delayFrames)
        for index in 0..<reference.count {
            let first = index < source.count ? source[index] : 0
            let earlier = index - delayFrames
            let second = (earlier >= 0 && earlier < source.count) ? source[earlier] : 0
            reference[index] = outputGain * (first + second)
        }
        let referencePeak = peak(reference)
        require(referencePeak < 1, "overlap reference peaks at \(referencePeak) and would clip")

        let overlapOpens = OSAllocatedUnfairLock(initialState: LoadProbe())
        let overlap = LegacyPreviewAudioPlayer()
        overlap.resourceByteBudget = 1000
        overlap.recordOutputForTests = true
        overlap.traceFileOpen = { isMain in
            overlapOpens.withLock { state in
                state.calls += 1
                if isMain { state.mainCalls += 1 }
            }
        }
        var overlapSamples: [Double] = []
        overlap.onElapsedSeconds = { overlapSamples.append($0) }
        overlap.playChart(
            documentData: Data("#WAV01 overlap.wav\n".utf8),
            chartDirectory: folder,
            notes: [
                PreviewAudioNote(beat: 0, wavToken: "01"),
                PreviewAudioNote(beat: 0.2, wavToken: "01")
            ],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        let heardTail = waitUntil({
            guard overlapSamples.first == 0, overlap.diagnosticScheduledCues == 2 else { return false }
            let tap = overlap.outputTapSamples()
            let rate = overlap.outputTapSampleRate
            guard rate > 0, let onset = tap.firstIndex(where: { abs($0) > 0.02 }) else { return false }
            return Double(tap.count - onset) / rate >= 0.70
        }, timeout: 4)
        let tap = overlap.outputTapSamples()
        let tapRate = overlap.outputTapSampleRate
        let opened = overlapOpens.withLock { $0 }
        let dropped = overlap.diagnosticDroppedVoices
        let scheduled = overlap.diagnosticScheduledCues
        let lag = alignOverlap(tap, reference, rate: tapRate)
        let solo = windowError(tap, reference, lag: lag, start: cycle, end: delayFrames - smear)
        let dual = windowError(tap, reference, lag: lag, start: delayFrames + smear, end: delayFrames * 2 - smear)
        let stack = windowError(tap, reference, lag: lag, start: delayFrames * 2 + smear, end: delayFrames * 4 - smear)
        let tail = windowError(tap, reference, lag: lag, start: delayFrames * 4 + smear, end: delayFrames * 5 - cycle)
        let stepped = steppedOverlapError(
            tap,
            reference,
            lag: lag,
            windows: [
                cycle..<(delayFrames - smear),
                (delayFrames + smear)..<(delayFrames * 2 - smear),
                (delayFrames * 2 + smear)..<(delayFrames * 4 - smear),
                (delayFrames * 4 + smear)..<(delayFrames * 5 - cycle)
            ],
            step: cycle
        )
        let soloSlice = slice(tap, lag: lag, start: cycle, end: cycle * 3)
        let dualSlice = slice(tap, lag: lag, start: cycle * 5, end: cycle * 7)
        let stackSlice = slice(tap, lag: lag, start: cycle * 9, end: cycle * 15)
        let tailSlice = slice(tap, lag: lag, start: cycle * 17, end: cycle * 19)
        let interval = secondVoiceDeparture(
            tap,
            source: source,
            gain: outputGain,
            lag: lag,
            rate: tapRate,
            delayFrames: delayFrames
        )
        let endTime = overlapEndTime(tap, lag: lag, rate: tapRate)
        let quiet = overlapInteriorQuiet(tap, lag: lag, rate: tapRate, from: cycle, to: delayFrames * 5 - cycle)
        let soloRMS = windowRMS(tap, reference, lag: lag, start: cycle, end: delayFrames - smear)
        let dualRMS = windowRMS(tap, reference, lag: lag, start: delayFrames + smear, end: delayFrames * 2 - smear)
        let stackRMS = windowRMS(tap, reference, lag: lag, start: delayFrames * 2 + smear, end: delayFrames * 4 - smear)
        let tailRMS = windowRMS(tap, reference, lag: lag, start: delayFrames * 4 + smear, end: delayFrames * 5 - cycle)
        let soloAt = worstErrorTime(tap, reference, lag: lag, rate: tapRate, start: cycle, end: delayFrames - smear)
        let dualAt = worstErrorTime(tap, reference, lag: lag, rate: tapRate, start: delayFrames + smear, end: delayFrames * 2 - smear)
        let stackAt = worstErrorTime(tap, reference, lag: lag, rate: tapRate, start: delayFrames * 2 + smear, end: delayFrames * 4 - smear)
        let tailAt = worstErrorTime(tap, reference, lag: lag, rate: tapRate, start: delayFrames * 4 + smear, end: delayFrames * 5 - cycle)
        print(String(
            format: "OV overlap: opens=%d main=%d dropped=%d scheduled=%d frames=%d rate=%.0f lag=%d solo=%.5f@%.4f dual=%.5f@%.4f stack=%.5f@%.4f tail=%.5f@%.4f step=%.5f soloRMS=%.5f dualRMS=%.5f stackRMS=%.5f tailRMS=%.5f interval=%.4f end=%.4f quiet=%.4f refPeak=%.4f",
            opened.calls,
            opened.mainCalls,
            dropped,
            scheduled,
            tap.count,
            tapRate,
            lag,
            solo,
            soloAt,
            dual,
            dualAt,
            stack,
            stackAt,
            tail,
            tailAt,
            stepped,
            soloRMS,
            dualRMS,
            stackRMS,
            tailRMS,
            interval,
            endTime,
            quiet,
            referencePeak
        ))
        fflush(stdout)
        require(heardTail, "overlap tail was not recorded, scheduled \(scheduled), frames \(tap.count), drops \(dropped)")
        require(dropped == 0, "overlapping file dropped a voice")
        require(opened.calls >= 1 && opened.mainCalls == 0, "overlap opens \(opened.calls), main \(opened.mainCalls)")
        require(abs(tapRate - Double(sampleRate)) < 0.5, "overlap tap rate \(tapRate)")
        require(lag >= 0, "overlap PCM did not align to the source reference")
        require(
            solo <= 0.02 && dual <= 0.02 && stack <= 0.02 && tail <= 0.02,
            "overlap reference error solo \(solo) dual \(dual) stack \(stack) tail \(tail)"
        )
        require(stepped <= 0.02, "overlap stepped reference error \(stepped)")
        require(toneWins(soloSlice, rate: tapRate, hz: 440, against: 880), "first solo was not 440Hz, frames \(soloSlice.count)")
        require(bothOverlapBands(dualSlice, rate: tapRate), "overlap window lost one offset, frames \(dualSlice.count)")
        require(toneWins(stackSlice, rate: tapRate, hz: 880, against: 440), "stacked overlap was not 880Hz, frames \(stackSlice.count)")
        require(toneWins(tailSlice, rate: tapRate, hz: 880, against: 440), "second solo tail was not 880Hz, frames \(tailSlice.count)")
        require(abs(interval - 0.10) < 0.02, "second voice interval \(interval)s")
        require(abs(endTime - 0.50) < 0.02, "overlap ended at \(endTime)s")
        require(quiet < 0.02, "overlap interior quiet \(quiet)s")
        let after = lag + delayFrames * 5 + cycle
        if lag >= 0, after < tap.count {
            let trailing = Array(tap[after..<min(tap.count, after + cycle * 2)])
            require(peak(trailing) < 0.02, "overlap continued after the second tail, peak \(peak(trailing))")
        }
        overlap.stop()
    }

    /// 16-bit PCM，幅度与 `toneWAV` 相同。前段 440Hz，后段 880Hz。源数组就是文件里的量化样本。
    private static func overlapSegmentPCM(sampleRate: Int, headFrames: Int, tailFrames: Int) -> (wav: Data, source: [Float]) {
        let frames = headFrames + tailFrames
        let blockAlign = 2
        let dataSize = frames * blockAlign
        var bytes = [UInt8]()
        bytes.reserveCapacity(44 + dataSize)
        func appendASCII(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func append32(_ value: UInt32) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 24) & 0xff))
        }
        func append16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
        }
        appendASCII("RIFF")
        append32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * blockAlign))
        append16(UInt16(blockAlign))
        append16(16)
        appendASCII("data")
        append32(UInt32(dataSize))
        var source = [Float](repeating: 0, count: frames)
        for index in 0..<frames {
            let hz = index < headFrames ? 440.0 : 880.0
            let angle = 2 * Double.pi * hz * Double(index) / Double(sampleRate)
            let quantized = Int16(sin(angle) * 6000)
            source[index] = Float(quantized) / 32768
            append16(UInt16(bitPattern: quantized))
        }
        return (Data(bytes), source)
    }

    /// 440Hz 自相关会锁到周期旁瓣。先对齐短时能量，能量台阶只在分段边界出现一次，再按样本误差收紧。
    private static func alignOverlap(_ captured: [Float], _ reference: [Float], rate: Double) -> Int {
        guard rate > 0, reference.count > 1_200, captured.count > reference.count else { return -1 }
        let hop = 48
        func energy(_ samples: [Float], count: Int) -> [Double] {
            let bins = count / hop
            var out = [Double](repeating: 0, count: max(bins, 0))
            for bin in 0..<bins {
                var sum = 0.0
                let start = bin * hop
                for index in start..<(start + hop) {
                    let sample = Double(samples[index])
                    sum += sample * sample
                }
                out[bin] = sum
            }
            return out
        }
        let refCount = reference.count - (reference.count % hop)
        let capCount = min(captured.count, reference.count + Int(rate * 0.40))
        let capBins = capCount - (capCount % hop)
        let refEnv = energy(reference, count: refCount)
        let capEnv = energy(captured, count: capBins)
        let maxBin = capEnv.count - refEnv.count
        guard maxBin >= 0, !refEnv.isEmpty else { return -1 }
        var bestBin = 0
        var bestScore = -Double.greatestFiniteMagnitude
        for bin in 0...maxBin {
            var sum = 0.0
            for index in 0..<refEnv.count {
                sum += capEnv[bin + index] * refEnv[index]
            }
            if sum > bestScore {
                bestScore = sum
                bestBin = bin
            }
        }
        let center = bestBin * hop
        let lower = max(0, center - hop)
        let upper = min(captured.count - reference.count, center + hop)
        guard lower <= upper else { return -1 }
        func sse(_ lag: Int) -> Double {
            var sum = 0.0
            var index = 0
            while index < reference.count {
                let delta = Double(captured[lag + index]) - Double(reference[index])
                sum += delta * delta
                index += 8
            }
            return sum
        }
        var bestLag = center
        var bestError = Double.greatestFiniteMagnitude
        for candidate in lower...upper {
            let value = sse(candidate)
            if value < bestError {
                bestError = value
                bestLag = candidate
            }
        }
        let refineLower = max(lower, bestLag - 8)
        let refineUpper = min(upper, bestLag + 8)
        bestError = Double.greatestFiniteMagnitude
        for candidate in refineLower...refineUpper {
            var sum = 0.0
            for index in 0..<reference.count {
                let delta = Double(captured[candidate + index]) - Double(reference[index])
                sum += delta * delta
            }
            if sum < bestError {
                bestError = sum
                bestLag = candidate
            }
        }
        return bestLag
    }

    private static func worstErrorTime(
        _ captured: [Float],
        _ reference: [Float],
        lag: Int,
        rate: Double,
        start: Int,
        end: Int
    ) -> Double {
        guard lag >= 0, end > start, rate > 0 else { return -1 }
        var worst: Float = -1
        var at = start
        for index in start..<end {
            let cursor = lag + index
            if cursor < 0 || cursor >= captured.count || index >= reference.count { return -1 }
            let delta = abs(captured[cursor] - reference[index])
            if delta > worst {
                worst = delta
                at = index
            }
        }
        return Double(at) / rate
    }

    private static func windowRMS(_ captured: [Float], _ reference: [Float], lag: Int, start: Int, end: Int) -> Float {
        guard lag >= 0, end > start else { return 999 }
        var energy = 0.0
        var count = 0
        for index in start..<end {
            let cursor = lag + index
            if cursor < 0 || cursor >= captured.count || index >= reference.count {
                return 999
            }
            let delta = Double(captured[cursor] - reference[index])
            energy += delta * delta
            count += 1
        }
        guard count > 0 else { return 999 }
        return Float((energy / Double(count)).squareRoot())
    }

    private static func windowError(_ captured: [Float], _ reference: [Float], lag: Int, start: Int, end: Int) -> Float {
        guard lag >= 0, start >= 0, end > start else { return 999 }
        var worst: Float = 0
        for index in start..<end {
            let cursor = lag + index
            if cursor < 0 || cursor >= captured.count || index >= reference.count {
                return 999
            }
            worst = max(worst, abs(captured[cursor] - reference[index]))
        }
        return worst
    }

    private static func steppedOverlapError(
        _ captured: [Float],
        _ reference: [Float],
        lag: Int,
        windows: [Range<Int>],
        step: Int
    ) -> Float {
        guard step > 0 else { return 999 }
        var worst: Float = 0
        for window in windows {
            var start = window.lowerBound
            while start < window.upperBound {
                let end = min(window.upperBound, start + step)
                worst = max(worst, windowError(captured, reference, lag: lag, start: start, end: end))
                start += step
            }
        }
        return worst
    }

    private static func slice(_ captured: [Float], lag: Int, start: Int, end: Int) -> [Float] {
        guard lag >= 0, end > start else { return [] }
        let lower = lag + start
        let upper = lag + end
        guard lower >= 0, upper <= captured.count else { return [] }
        return Array(captured[lower..<upper])
    }

    private static func bothOverlapBands(_ samples: [Float], rate: Double) -> Bool {
        guard samples.count > 64, rate > 0 else { return false }
        let low = goertzel(samples, rate: rate, hz: 440)
        let high = goertzel(samples, rate: rate, hz: 880)
        return low > 1 && high > 1 && low > high / 1.5 && high > low / 1.5
    }

    private static func secondVoiceDeparture(
        _ captured: [Float],
        source: [Float],
        gain: Float,
        lag: Int,
        rate: Double,
        delayFrames: Int
    ) -> Double {
        guard lag >= 0, rate > 0, delayFrames > 0 else { return -1 }
        let begin = 1_200
        let limit = min(source.count, delayFrames + 2_400)
        guard begin < limit else { return -1 }
        for index in begin..<limit {
            let cursor = lag + index
            if cursor < 0 || cursor >= captured.count { return -1 }
            if abs(captured[cursor] - gain * source[index]) > 0.02 {
                return Double(index) / rate
            }
        }
        return -1
    }

    private static func overlapEndTime(_ captured: [Float], lag: Int, rate: Double) -> Double {
        guard lag >= 0, lag < captured.count, rate > 0 else { return -1 }
        var last = -1
        for index in lag..<captured.count {
            if abs(captured[index]) > 0.02 {
                last = index
            }
        }
        guard last >= lag else { return -1 }
        return Double(last - lag) / rate
    }

    private static func overlapInteriorQuiet(_ captured: [Float], lag: Int, rate: Double, from: Int, to: Int) -> Double {
        guard lag >= 0, rate > 0, to > from else { return 999 }
        let start = lag + from
        let end = lag + to - 1
        guard start >= 0, end < captured.count else { return 999 }
        return longestQuiet(captured, from: start, to: end, rate: rate, floor: 0.008)
    }

    private struct LoadProbe: Sendable {
        var calls = 0
        var mainCalls = 0
    }

    @MainActor
    private static func waitUntil(_ predicate: () -> Bool, timeout: Double = 2) -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            if predicate() {
                return true
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return predicate()
    }

    @MainActor
    private static func pump(_ seconds: Double) {
        let end = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < end {
            let slice = min(0.02, end - ProcessInfo.processInfo.systemUptime)
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(max(slice, 0.001)))
        }
    }

    private static func makeChartFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-preview-life-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func writeLongWAV(
        url: URL,
        seconds: Double,
        sampleRate: Int = 44_100,
        channels: Int = 2,
        headSeconds: Double,
        tailAt: Double,
        tailSeconds: Double
    ) {
        let frames = max(1, Int(seconds * Double(sampleRate)))
        let blockAlign = channels * 2
        let dataSize = frames * blockAlign
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try! FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = [UInt8]()
        func appendASCII(_ text: String) { header.append(contentsOf: text.utf8) }
        func append32(_ value: UInt32) {
            header.append(UInt8(value & 0xff))
            header.append(UInt8((value >> 8) & 0xff))
            header.append(UInt8((value >> 16) & 0xff))
            header.append(UInt8((value >> 24) & 0xff))
        }
        func append16(_ value: UInt16) {
            header.append(UInt8(value & 0xff))
            header.append(UInt8((value >> 8) & 0xff))
        }
        appendASCII("RIFF")
        append32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * blockAlign))
        append16(UInt16(blockAlign))
        append16(16)
        appendASCII("data")
        append32(UInt32(dataSize))
        try! handle.write(contentsOf: Data(header))
        let headFrames = Int(headSeconds * Double(sampleRate))
        let tailStart = Int(tailAt * Double(sampleRate))
        var block = [UInt8]()
        block.reserveCapacity(4096 * blockAlign)
        func flush() {
            if block.isEmpty { return }
            try! handle.write(contentsOf: Data(block))
            block.removeAll(keepingCapacity: true)
        }
        for frame in 0..<frames {
            let hz: Double
            if frame < headFrames {
                hz = 440
            } else if frame >= tailStart {
                hz = 880
            } else {
                hz = 0
            }
            let sample = hz == 0 ? 0 : Int16(sin(2 * Double.pi * hz * Double(frame) / Double(sampleRate)) * 6000)
            let bits = UInt16(bitPattern: sample)
            for _ in 0..<channels {
                block.append(UInt8(bits & 0xff))
                block.append(UInt8((bits >> 8) & 0xff))
            }
            if block.count >= 4096 * blockAlign { flush() }
        }
        flush()
        _ = tailSeconds
    }

    private static func toneWins(_ samples: [Float], rate: Double, hz: Double, against other: Double) -> Bool {
        let window = Array(samples.suffix(min(samples.count, Int(rate * 0.20))))
        guard window.count > 64 else { return false }
        return goertzel(window, rate: rate, hz: hz) > goertzel(window, rate: rate, hz: other) * 1.5
    }

    private static func goertzel(_ samples: [Float], rate: Double, hz: Double) -> Double {
        guard rate > 0, samples.count > 8 else { return 0 }
        let coefficient = 2 * cos(2 * Double.pi * hz / rate)
        var previous = 0.0
        var older = 0.0
        for sample in samples {
            let current = Double(sample) + coefficient * previous - older
            older = previous
            previous = current
        }
        return previous * previous + older * older - coefficient * previous * older
    }

    private static func wavToken(_ index: Int) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let value = index + 1
        return "\(alphabet[value / 36])\(alphabet[value % 36])"
    }

    private static func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    private static func burstStarts(_ samples: [Float], rate: Double, minGap: Double, threshold: Float) -> [Double] {
        guard rate > 0, !samples.isEmpty else { return [] }
        let quietNeeded = max(1, Int(minGap * rate))
        var starts: [Double] = []
        var quiet = quietNeeded
        var inside = false
        for (index, sample) in samples.enumerated() {
            if abs(sample) > threshold {
                if !inside {
                    starts.append(Double(index) / rate)
                    inside = true
                }
                quiet = 0
            } else {
                quiet += 1
                if quiet >= quietNeeded {
                    inside = false
                }
            }
        }
        return starts
    }

    /// 从第一下起音对齐，每格只量音中间的能量，避免过零和邻音泄漏被当成多一记或少一记。
    private struct PressureCapture {
        var pcm: [Float]
        var sampleRate: Double
        var scheduled: Int
        var drops: Int
        var steals: Int
        var voices: Int
        var opens: Int
        var mainOpens: Int
        var prepare: Double
        var ready: Double
        var steady: Double
        var streamBlock: Int
        var copies: Int
        var late: Int
        var onset: Double
    }

    @MainActor
    private static func playPressure(
        folder: URL,
        document: String,
        notes: [PreviewAudioNote],
        budget: Int,
        playback: Double,
        pump seconds: Double = 0
    ) -> PressureCapture {
        let opens = OSAllocatedUnfairLock(initialState: LoadProbe())
        let player = LegacyPreviewAudioPlayer()
        player.resourceByteBudget = budget
        player.recordOutputForTests = true
        player.traceFileOpen = { isMain in
            opens.withLock { state in
                state.calls += 1
                if isMain { state.mainCalls += 1 }
            }
        }
        player.setPlaybackRate(playback)
        var ready = false
        player.onElapsedSeconds = { sample in
            if sample == 0 { ready = true }
        }
        let started = Date()
        player.playChart(
            documentData: Data(document.utf8),
            chartDirectory: folder,
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 16
        )
        let prepare = Date().timeIntervalSince(started)
        require(waitUntil { ready }, "pressure \(playback) budget \(budget) did not become ready")
        let readyAt = Date().timeIntervalSince(started)
        require(
            waitUntil({ player.diagnosticScheduledCues >= notes.count }, timeout: 2),
            "pressure scheduled \(player.diagnosticScheduledCues) of \(notes.count)"
        )
        let hold = seconds > 0 ? seconds : 0.20 + 0.75 / max(playback, 0.25)
        let steadyStart = Date()
        pump(hold)
        let steady = Date().timeIntervalSince(steadyStart)
        let opened = opens.withLock { $0 }
        let pcm = player.outputTapSamples()
        let sampleRate = player.outputTapSampleRate
        let onset = pcm.firstIndex(where: { abs($0) > 0.02 }).map { Double($0) / max(sampleRate, 1) } ?? 999
        let captured = PressureCapture(
            pcm: pcm,
            sampleRate: sampleRate,
            scheduled: player.diagnosticScheduledCues,
            drops: player.diagnosticDroppedVoices,
            steals: player.diagnosticStolenVoices,
            voices: player.diagnosticVoiceCreations,
            opens: opened.calls,
            mainOpens: opened.mainCalls,
            prepare: prepare,
            ready: readyAt,
            steady: steady,
            streamBlock: player.diagnosticStreamBlockBytes,
            copies: player.diagnosticPCMCopies,
            late: player.diagnosticLateSchedules,
            onset: onset
        )
        player.stop()
        return captured
    }

    private static func pressureSlots(
        _ samples: [Float],
        rate: Double,
        count: Int,
        playback: Double,
        spacing chartSpacing: Double = 0.006,
        tone chartTone: Double = 0.005
    ) -> (hits: Int, minRMS: Double, gap: Double) {
        let spacing = chartSpacing / playback
        let tone = chartTone / playback
        guard rate > 0, count > 0, let first = samples.firstIndex(where: { abs($0) > 0.02 }) else {
            return (0, 0, 999)
        }
        let inner = max(8, Int((tone * 0.50 * rate).rounded()))
        var hits = 0
        var minRMS = Double.greatestFiniteMagnitude
        for index in 0..<count {
            let start = first + Int(((Double(index) * spacing + tone * 0.15) * rate).rounded())
            let end = start + inner
            guard start >= 0, end <= samples.count else { continue }
            var energy = 0.0
            for sample in samples[start..<end] {
                energy += Double(sample) * Double(sample)
            }
            let rms = sqrt(energy / Double(inner))
            minRMS = min(minRMS, rms)
            if rms > 0.02 { hits += 1 }
        }
        let last = min(samples.count - 1, first + Int(((Double(count - 1) * spacing + tone) * rate).rounded()))
        let gap = longestQuiet(samples, from: first, to: last, rate: rate, floor: 0.008)
        return (hits, minRMS == .greatestFiniteMagnitude ? 0 : minRMS, gap)
    }

    /// 每格整段音色对 440×rate，用来确认变速后的频带，而不是只数静音缝。
    private static func slotBands(
        _ samples: [Float],
        rate: Double,
        count: Int,
        playback: Double,
        spacing chartSpacing: Double = 0.006,
        tone chartTone: Double = 0.005,
        hz: Double = 440
    ) -> Int {
        let spacing = chartSpacing / playback
        let tone = chartTone / playback
        guard rate > 0, count > 0, let first = samples.firstIndex(where: { abs($0) > 0.02 }) else { return 0 }
        let width = max(16, Int((tone * rate).rounded()))
        var hits = 0
        for index in 0..<count {
            let start = first + Int((Double(index) * spacing * rate).rounded())
            guard start >= 0, start + width <= samples.count else { continue }
            let window = Array(samples[start..<(start + width)])
            let fundamental = goertzel(window, rate: rate, hz: hz * playback)
            let lower = goertzel(window, rate: rate, hz: hz * playback * 0.5)
            if fundamental > lower * 1.4, fundamental > 1 { hits += 1 }
        }
        return hits
    }

    private static func pressureTail(
        _ samples: [Float],
        rate: Double,
        count: Int,
        playback: Double,
        spacing chartSpacing: Double = 0.006,
        tone chartTone: Double = 0.005
    ) -> (interval: Double, lastPeaks: (Double, Double)) {
        let spacing = chartSpacing / playback
        let tone = chartTone / playback
        guard rate > 0, count >= 2, let first = samples.firstIndex(where: { abs($0) > 0.02 }) else {
            return (999, (0, 0))
        }
        func peak(at index: Int) -> (time: Double, value: Double) {
            let start = first + Int(((Double(index) * spacing + tone * 0.15) * rate).rounded())
            let end = min(samples.count, start + max(8, Int((tone * 0.50 * rate).rounded())))
            guard start >= 0, start < end else { return (999, 0) }
            var best = 0.0
            var at = start
            for cursor in start..<end {
                let value = abs(Double(samples[cursor]))
                if value > best {
                    best = value
                    at = cursor
                }
            }
            return (Double(at) / rate, best)
        }
        let firstPeak = peak(at: 0)
        let secondPeak = peak(at: 1)
        let penultimate = peak(at: count - 2)
        let last = peak(at: count - 1)
        return (secondPeak.time - firstPeak.time, (penultimate.value, last.value))
    }

    private static func interiorGap(_ samples: [Float], rate: Double) -> Double {
        guard rate > 0,
              let first = samples.firstIndex(where: { abs($0) > 0.02 }),
              let last = samples.lastIndex(where: { abs($0) > 0.02 }),
              last > first else { return 999 }
        return longestQuiet(samples, from: first, to: last, rate: rate, floor: 0.008)
    }

    private static func longestQuiet(_ samples: [Float], from: Int, to: Int, rate: Double, floor: Float) -> Double {
        var run = 0
        var worst = 0
        let end = min(to, samples.count - 1)
        guard from <= end else { return 999 }
        for sample in samples[from...end] {
            if abs(sample) < floor {
                run += 1
                worst = max(worst, run)
            } else {
                run = 0
            }
        }
        return Double(worst) / rate
    }

    private static func markerHits(_ samples: [Float], rate: Double, playback: Double, charts: [Double]) -> Int {
        guard rate > 0, let first = samples.firstIndex(where: { abs($0) > 0.02 }) else { return 0 }
        var present = 0
        for chart in charts {
            let wall = 0.020 / playback
            let start = first + Int(((chart / playback) * rate).rounded())
            let count = max(32, Int((wall * rate).rounded()))
            guard start >= 0, start + count <= samples.count else { continue }
            let window = Array(samples[start..<(start + count)])
            let marker = goertzel(window, rate: rate, hz: 2200 * playback)
            let pressure = goertzel(window, rate: rate, hz: 440 * playback)
            if marker > pressure * 1.4, marker > 1 { present += 1 }
        }
        return present
    }

    @MainActor
    private static func recentTone(_ player: LegacyPreviewAudioPlayer, hz: Double, against other: Double) -> Bool {
        let rate = player.outputTapSampleRate
        let window = Array(player.outputTapSamples().suffix(min(player.outputTapSamples().count, Int(rate * 0.08))))
        guard window.count > 64 else { return false }
        return goertzel(window, rate: rate, hz: hz) > goertzel(window, rate: rate, hz: other) * 1.5
    }

    private static func writeTapWAV(_ samples: [Float], rate: Double, name: String) {
        let dir = URL(fileURLWithPath: "out/validation/ubmplay-parity-20261020/UA8-pcm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var bytes = [UInt8]()
        let dataSize = samples.count * 2
        func appendASCII(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func append32(_ value: UInt32) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 24) & 0xff))
        }
        func append16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
        }
        appendASCII("RIFF")
        append32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(rate.rounded()))
        append32(UInt32(rate.rounded()) * 2)
        append16(2)
        append16(16)
        appendASCII("data")
        append32(UInt32(dataSize))
        for sample in samples {
            let clipped = min(1, max(-1, sample))
            append16(UInt16(bitPattern: Int16(clipped * 32767)))
        }
        try? Data(bytes).write(to: dir.appendingPathComponent(name))
    }

    private static func burstCount(_ samples: [Float], rate: Double, minGap: Double, threshold: Float) -> Int {
        guard rate > 0, !samples.isEmpty else { return 0 }
        let quietNeeded = max(1, Int(minGap * rate))
        var count = 0
        var quiet = quietNeeded
        var inside = false
        for sample in samples {
            if abs(sample) > threshold {
                if !inside {
                    count += 1
                    inside = true
                }
                quiet = 0
            } else {
                quiet += 1
                if quiet >= quietNeeded {
                    inside = false
                }
            }
        }
        return count
    }

    private static func toneWAV(duration: Double, sampleRate: Int = 44_100, channels: Int = 1, hz: Double = 440) -> Data {
        let frames = max(1, Int(duration * Double(sampleRate)))
        let channelCount = max(1, channels)
        let blockAlign = channelCount * 2
        let dataSize = frames * blockAlign
        var bytes = [UInt8]()
        bytes.reserveCapacity(44 + dataSize)
        func appendASCII(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func append32(_ value: UInt32) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 24) & 0xff))
        }
        func append16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
        }
        appendASCII("RIFF")
        append32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(UInt16(channelCount))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * blockAlign))
        append16(UInt16(blockAlign))
        append16(16)
        appendASCII("data")
        append32(UInt32(dataSize))
        for index in 0..<frames {
            let angle = 2 * Double.pi * hz * Double(index) / Double(sampleRate)
            let sample = UInt16(bitPattern: Int16(sin(angle) * 6000))
            for _ in 0..<channelCount {
                append16(sample)
            }
        }
        return Data(bytes)
    }

    /// 超过两声道不把中心/环绕丢掉当成立体声。准备失败，不进入 ready。
    @MainActor
    private static func testSurroundChannelsFailPrepare() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! surroundWAV(channels: 3).write(to: folder.appendingPathComponent("wide.wav"))
        let player = LegacyPreviewAudioPlayer()
        var states: [PreviewAudioPreparationState] = []
        var samples: [Double] = []
        player.onPreparationStateChanged = { states.append($0) }
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 wide.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { states.contains(.failed) }, "surround file did not fail, states \(states)")
        require(!states.contains(.ready), "surround file became ready")
        require(player.diagnosticPreparationFailure != nil, "surround failure was not named")
        pump(0.1)
        require(samples.isEmpty, "surround failure emitted elapsed \(samples)")
    }

    /// 旧 binding 的迟到 drive 必须静音，并且不把正在响的新节点停掉。100 次不能把 holder 堆上去。
    @MainActor
    private static func testLateBindingStaysSilentAcrossRebind() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.80).write(to: folder.appendingPathComponent("hit.wav"))
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        var samples: [Double] = []
        player.onElapsedSeconds = { samples.append($0) }
        player.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(waitUntil { samples.first == 0 && player.soundingSampleCount >= 1 }, "rebind chart did not start")
        for cycle in 0..<100 {
            guard let stale = player.debugReplaceRenderBinding() else {
                require(false, "cycle \(cycle) did not capture a binding")
                return
            }
            var late = [Float](repeating: 0.5, count: 32)
            let status = late.withUnsafeMutableBufferPointer { raw in
                stale.drive(ibms_preview_mix_host_ticks(), frames: 16, interleaved: raw.baseAddress)
            }
            require(status == IBMS_PREVIEW_MIX_OK, "stale drive status \(status)")
            require(late.allSatisfy { abs($0) < 0.001 }, "stale binding wrote audio on cycle \(cycle)")
        }
        pump(0.05)
        require(player.debugRenderHolderCount() < 8, "render holders leaked to \(player.debugRenderHolderCount())")
        pump(0.12)
        require(peak(player.outputTapSamples()) > 0.02, "live chart went silent after rebind")
        player.stop()
    }

    private static func surroundWAV(channels: Int) -> Data {
        let frames = 32
        let channelCount = channels
        let blockAlign = channelCount * 2
        let dataSize = frames * blockAlign
        var bytes = [UInt8]()
        func appendASCII(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func append32(_ value: UInt32) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 24) & 0xff))
        }
        func append16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
        }
        appendASCII("RIFF")
        append32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(UInt16(channelCount))
        append32(44_100)
        append32(UInt32(44_100 * blockAlign))
        append16(UInt16(blockAlign))
        append16(16)
        appendASCII("data")
        append32(UInt32(dataSize))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: dataSize))
        return Data(bytes)
    }

    /// 空谱没有资源槽。playChart 返回前就要有起点，不能等 worker。
    @MainActor
    private static func testEmptyChartStillCompletesSynchronously() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var workerHits = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.testBeforeWorkerReady = { _ in workerHits += 1 }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(
            samples == [0] && workerHits == 0,
            "empty visual chart did not complete synchronously, samples \(samples) worker \(workerHits)"
        )
        player.stop()
    }

    /// 缺文件仍有画面终点。ready 必须来自 adapter 的 onReady，不能在资源验证前交出 elapsed 0。
    @MainActor
    private static func testMissingFileVisualEndWaitsForAdapterReady() {
        let player = LegacyPreviewAudioPlayer()
        var samples: [Double] = []
        var states: [PreviewAudioPreparationState] = []
        var workerHits = 0
        var readyAfterWorker = false
        var finishes = 0
        player.onElapsedSeconds = { samples.append($0) }
        player.onTimelineFinished = { finishes += 1 }
        player.testBeforeWorkerReady = { _ in workerHits += 1 }
        player.onPreparationStateChanged = { state in
            if state == .ready {
                readyAfterWorker = workerHits > 0
            }
            states.append(state)
        }
        player.playChart(
            documentData: Data("#WAV01 missing.wav\n".utf8),
            chartDirectory: URL(fileURLWithPath: "/tmp/ibms-preview-missing-aw", isDirectory: true),
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(states == [.preparing] && samples.isEmpty, "missing-file chart readied inside playChart, \(states) \(samples)")
        require(
            waitUntil { states.contains(.ready) && samples.first == 0 },
            "adapter ready did not arrive, states \(states) failure \(player.diagnosticPreparationFailure ?? "") engine \(player.diagnosticEngineFailure ?? "")"
        )
        require(readyAfterWorker && workerHits == 1, "ready did not follow adapter onReady, hits \(workerHits) states \(states)")
        require(!states.contains(.failed) && finishes == 0, "silent visual end failed or finished, states \(states)")
        player.stop()
    }

    /// 有声 startPaused：worker 验证前不能 ready。验证失败不先报 ready/elapsed 0，也不额外 stopped。
    @MainActor
    private static func testAudibleStartPausedWaitsForWorkerReady() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.20).write(to: folder.appendingPathComponent("hit.wav"))
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let document = Data("#WAV01 hit.wav\n".utf8)
        let notes = [PreviewAudioNote(beat: 0, wavToken: "01")]
        let player = LegacyPreviewAudioPlayer()
        player.testSuppressSessionSubmit = true
        var events: [String] = []
        player.onPreparationStateChanged = { events.append("\($0)") }
        player.onElapsedSeconds = { events.append("elapsed:\($0)") }
        player.onPlaybackStopped = { events.append("stopped") }
        player.onTimelineFinished = { events.append("finished") }
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: notes,
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4,
            startPaused: true
        )
        require(
            waitUntil { player.diagnosticResourceLoads == 1 },
            "audible startPaused did not finish preparing"
        )
        require(events == ["preparing"] && player.isChartPaused, "startPaused readied before worker ack \(events)")
        player.testInjectWorkerReady()
        require(events == ["preparing", "ready", "elapsed:0.0"], "worker ready sequence \(events)")
        require(
            !events.contains("stopped") && !events.contains("finished") && player.isChartPaused,
            "startPaused ended early \(events)"
        )
        player.stop()
        let failedPlayer = LegacyPreviewAudioPlayer()
        var failureEvents: [String] = []
        var stops = 0
        var finishes = 0
        failedPlayer.onPlaybackStopped = {
            stops += 1
            failureEvents.append("stopped")
        }
        failedPlayer.onTimelineFinished = {
            finishes += 1
            failureEvents.append("finished")
        }
        failedPlayer.onElapsedSeconds = { failureEvents.append("elapsed:\($0)") }
        failedPlayer.testBeforeWorkerReady = { _ in
            failedPlayer.testBeforeWorkerReady = nil
            failedPlayer.testInjectWorkerFailure("io")
        }
        failedPlayer.onPreparationStateChanged = { state in
            failureEvents.append("\(state)")
            if state == .failed {
                failureEvents.append(failedPlayer.diagnosticPreparationFailure == "io" ? "io" : "diag:\(failedPlayer.diagnosticPreparationFailure ?? "")")
                let job = failedPlayer.testJobState()
                failureEvents.append(job.stopped ? "prep-job-stopped" : "prep-job-live")
                failedPlayer.playChart(
                    documentData: Data(),
                    chartDirectory: nil,
                    notes: [],
                    timing: timing,
                    fromBeat: 0,
                    visualEndBeat: 8
                )
            }
        }
        failedPlayer.playChart(
            documentData: Data("#WAV01 missing.wav\n".utf8),
            chartDirectory: URL(fileURLWithPath: "/tmp/ibms-preview-missing-aw", isDirectory: true),
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8,
            startPaused: true
        )
        require(
            waitUntil { failureEvents.contains("failed") && failureEvents.contains("ready") },
            "resource failure did not fail and replay \(failureEvents) failure \(failedPlayer.diagnosticPreparationFailure ?? "")"
        )
        let failedAt = failureEvents.firstIndex(of: "failed") ?? failureEvents.count
        require(
            !failureEvents.prefix(failedAt).contains { $0 == "ready" || $0.hasPrefix("elapsed") },
            "ready or elapsed arrived before failure \(failureEvents)"
        )
        require(failureEvents.contains("io"), "preparation failure lost the io diagnostic \(failureEvents)")
        require(failureEvents.contains("prep-job-live"), "preparation failure stopped the old job \(failureEvents)")
        require(stops == 0 && finishes == 0, "preparation failure stopped or finished, events \(failureEvents)")
        require(!failedPlayer.testJobState().stopped, "old preparation failure stopped the replayed job \(failedPlayer.testJobState())")
        require(failureEvents.filter { $0.hasPrefix("elapsed") } == ["elapsed:0.0"], "replay elapsed \(failureEvents)")
        failedPlayer.stop()
    }

    /// ready 之后的 src/device 失败停本代，走 stopped，不报自然结束。迟到 ready 不能把时钟救活。
    @MainActor
    private static func testRuntimeFailureUsesStoppedNotNaturalFinish() {
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        for reason in ["src", "device"] {
            let player = LegacyPreviewAudioPlayer()
            player.setPresentationClockExternallyDriven(true)
            var events: [String] = []
            var finishes = 0
            player.onElapsedSeconds = { events.append("elapsed:\($0)") }
            player.onPlaybackStopped = { events.append("stopped") }
            player.onTimelineFinished = {
                finishes += 1
                events.append("finished")
            }
            player.onPreparationStateChanged = { events.append("\($0)") }
            player.playChart(
                documentData: Data(),
                chartDirectory: nil,
                notes: [],
                timing: timing,
                fromBeat: 0,
                visualEndBeat: 8
            )
            require(events == ["ready", "elapsed:0.0"], "\(reason) setup \(events)")
            let watched = player.testJobState().generation
            var stoppedBeforeCallback = false
            player.onPreparationStateChanged = { state in
                events.append("\(state)")
                if state == .failed {
                    let job = player.testJobState()
                    stoppedBeforeCallback = job.stopped && job.generation == watched
                }
            }
            player.testInjectWorkerFailure(reason)
            require(stoppedBeforeCallback, "\(reason) did not stop generation \(watched) before the callback, events \(events)")
            require(finishes == 0 && !events.contains("finished"), "\(reason) pretended to finish \(events)")
            require(events.contains("failed") && events.contains("stopped"), "\(reason) did not settle stopped \(events)")
            if let failedAt = events.firstIndex(of: "failed"), let stoppedAt = events.firstIndex(of: "stopped") {
                require(failedAt < stoppedAt, "\(reason) stopped before failed \(events)")
            }
            let elapsedCount = events.filter { $0.hasPrefix("elapsed") }.count
            player.testInjectWorkerReady()
            player.advancePresentationClock()
            require(
                events.filter { $0.hasPrefix("elapsed") }.count == elapsedCount && finishes == 0,
                "\(reason) late ready revived the clock \(events)"
            )
            require(player.diagnosticPreparationFailure == reason, "\(reason) diagnostic \(player.diagnosticPreparationFailure ?? "")")
            if reason == "device" {
                require(player.diagnosticEngineFailure == "device", "device engine diagnostic \(player.diagnosticEngineFailure ?? "")")
            } else {
                require(player.diagnosticEngineFailure == nil, "src stored an engine failure \(player.diagnosticEngineFailure ?? "")")
            }
            player.stop()
        }
    }

    /// failed 里重播不能被本代随后的 stop 打掉。stopped 里重播同样不能在回调返回后停新代。
    @MainActor
    private static func testRuntimeFailureReplayDoesNotStopNewGeneration() {
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let player = LegacyPreviewAudioPlayer()
        player.setPresentationClockExternallyDriven(true)
        var events: [String] = []
        var finishes = 0
        player.onElapsedSeconds = { events.append("elapsed:\($0)") }
        player.onTimelineFinished = { finishes += 1 }
        player.onPlaybackStopped = { events.append("stopped") }
        player.onPreparationStateChanged = { state in
            events.append("\(state)")
            if state == .failed {
                let job = player.testJobState()
                events.append(job.stopped ? "old-stopped" : "old-live")
                player.playChart(
                    documentData: Data(),
                    chartDirectory: nil,
                    notes: [],
                    timing: timing,
                    fromBeat: 0,
                    visualEndBeat: 8
                )
            }
        }
        player.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8
        )
        require(events.contains("elapsed:0.0"), "runtime replay setup \(events)")
        events.removeAll()
        player.testInjectWorkerFailure("src")
        require(events.contains("old-stopped"), "failed callback saw a live old job \(events)")
        require(!events.contains("stopped"), "old stop ran after replay \(events)")
        require(finishes == 0, "replayed failure finished the new chart")
        require(events.contains("ready"), "replay from failed did not ready \(events)")
        require(events.filter { $0.hasPrefix("elapsed") } == ["elapsed:0.0"], "replay elapsed \(events)")
        require(!player.testJobState().stopped, "old stop cleared the replayed job \(player.testJobState())")
        let beforeAdvance = events.filter { $0.hasPrefix("elapsed") }.count
        player.advancePresentationClock()
        require(
            events.filter { $0.hasPrefix("elapsed") }.count > beforeAdvance && finishes == 0,
            "replayed chart did not accept a later sample \(events)"
        )
        player.stop()
        let replacement = LegacyPreviewAudioPlayer()
        replacement.setPresentationClockExternallyDriven(true)
        var replaced: [String] = []
        replacement.onElapsedSeconds = { replaced.append("elapsed:\($0)") }
        replacement.onTimelineFinished = { replaced.append("finished") }
        replacement.onPreparationStateChanged = { replaced.append("\($0)") }
        replacement.onPlaybackStopped = {
            replaced.append("stopped")
            replacement.playChart(
                documentData: Data(),
                chartDirectory: nil,
                notes: [],
                timing: timing,
                fromBeat: 0,
                visualEndBeat: 8
            )
        }
        replacement.playChart(
            documentData: Data(),
            chartDirectory: nil,
            notes: [],
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 8
        )
        replaced.removeAll()
        replacement.testInjectWorkerFailure("device")
        require(replaced.contains("failed") && replaced.contains("stopped"), "stopped replay events \(replaced)")
        if let failedAt = replaced.firstIndex(of: "failed"), let stoppedAt = replaced.firstIndex(of: "stopped") {
            require(failedAt < stoppedAt, "device failure stopped before failed \(replaced)")
        }
        require(!replaced.contains("finished"), "device failure finished \(replaced)")
        require(replaced.contains("ready"), "replay from stopped did not ready \(replaced)")
        require(!replacement.testJobState().stopped, "callback-after stop cleared the new job \(replacement.testJobState())")
        require(
            replaced.filter { $0.hasPrefix("elapsed") } == ["elapsed:0.0"],
            "stopped replay elapsed \(replaced)"
        )
        replacement.stop()
    }

    @MainActor
    private static func testAcOfflineReset() {
        let result = PreviewMixerOwnershipProbe.resetRetire(cycles: 100)
        require(result == "ok", "mixer ownership \(result)")
        print("AC offline 100 ok")
    }

    @MainActor
    private static func testAcAudibleSource() {
        let folder = makeChartFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.6, sampleRate: 48_000).write(to: folder.appendingPathComponent("hit.wav"))
        var player: LegacyPreviewAudioPlayer? = LegacyPreviewAudioPlayer()
        player?.recordOutputForTests = true
        player?.playChart(
            documentData: Data("#WAV01 hit.wav\n".utf8),
            chartDirectory: folder,
            notes: [PreviewAudioNote(beat: 0, wavToken: "01")],
            timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: []),
            fromBeat: 0,
            visualEndBeat: 8
        )
        let heard = waitUntil({
            guard let player else { return false }
            return player.outputTapSamples().contains { abs($0) > 0.02 } && player.testStoredDeviceTapRate() > 0
        }, timeout: 4)
        let samples = player?.outputTapSamples() ?? []
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let rate = player?.testStoredDeviceTapRate() ?? -1
        print("AC audible frames=\(samples.count) peak=\(peak) tapRate=\(rate) engine=\(player?.diagnosticEngineFailure ?? "ok")")
        require(heard && peak > 0.02 && rate > 0, "source callback missing frames=\(samples.count) peak=\(peak) rate=\(rate) engine=\(player?.diagnosticEngineFailure ?? "ok")")
        let before = PreviewAudioRetirementOwner.shared.acceptedCount()
        player?.stop()
        player = nil
        require(
            PreviewAudioRetirementOwner.shared.waitUntilReleased(atLeast: before + 1, timeout: 3),
            "audible lease was not released"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
