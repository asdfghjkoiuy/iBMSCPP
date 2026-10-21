import Foundation

@main
struct BmsONEDocumentTests {
    static func main() {
        testEmptyGoesThroughCpp()
        testMinimalFixture()
        testInsertThenRoundtrip()
        testEraseThenRoundtrip()
        testInsertLongNote()
        testReplaceNote()
        testUndoInsertAndRedo()
        testParseErrorUsesBmsonMessage()
        testLaneHitUsesSkinNumbers()
        testImportMinimalBms()
        testImportTenKeyBms()
        testGameModeQuestion()
        testForcedSevenKeyOnMinimal()
        testRandomIfBranch()
        testShiftJISTitle()
        testStopNotesFromJSON()
        testUpsertTimingAndDisplay()
        testImportBgaEvents()
        testUpsertBgaAndUndo()
        testBmpListRenameAndSynchronize()
        testBmpListWritesJSON()
        testBeatScaleMovesBga()
        testConvertResolutionScalesBga()
        testHeaderMappingReadsFixture()
        testHeaderMappingSubartistsAndNumbers()
        testReplaceTitleAndUndo()
        testReplaceArtistGenreLevelTotal()
        testHeaderBPMUpdatesStartNote()
        testHeaderBPMOnEmptyDoesNotCreateNote()
        testMoveMissingBpmRollsBack()
        testInvalidAndUnsupportedHeader()
        testInfoFieldsAndImageExtras()
        testInfoExtraFieldsAndUndo()
        testWavListRenameKeepsNotes()
        testWavListSynchronizeSwapsChannels()
        testWavListAssignPadsEmptyChannel()
        testWavListRemoveClearsName()
        testWavListRejectsNewline()
        testReplaceWavNameAndUndo()
        testWavListSynchronizeWritesJSON()
        testConvertResolutionDoublesPulsesAndUndo()
        testConvertResolutionRejectsRange()
        testConvertResolutionLossyPulse()
        testBeatScaleDoublesFirstMeasureAndShiftsLaterNote()
        testBeatPreserveKeepsPulses()
        testBeatMeasureOverflowsAndCutDeletes()
        testBeatCutTrimsLongNote()
        testBeatApplyAndUndo()
        testTransferKeyNoteToBGM()
        testTransferBGMToFirstVacantKey()
        testTransferSkipsOccupiedScratch()
        testTransferTwoBGMNotesGetDifferentLanes()
        testTransferToKeyKeepsExistingKey()
        testTransferToBGMClearsLengthAndUndo()
        testSeparateKeepsMainAndMovesOther()
        testSeparateIllegalMovesBoth()
        testSeparateIgnoresLongCover()
        testSeparateAndUndo()
        testInsertBarLineSplitsDefaultMeasure()
        testInsertBarLineSkipsEphemeralFourBeat()
        testInsertBarLineMaterializesEarlierEphemeral()
        testRemoveBarLineAndUndo()
        testChannelAddAppendsEmptyNotes()
        testChannelDestroyRemovesNotes()
        testChannelMoveAndSelectWrap()
        testChannelFindContainsCaseSensitive()
        testChannelFindActiveInVisibleRange()
        testChannelPlaybackCacheStillPlaying()
        testChannelInfoLabels()
        testOverallWaveform()
        testLaneWaveform()
        testShowHitChannelsOnly()
        testWriteContinueFlagFromShift()
        testChannelSetNameAndUndo()
        testPreferExModesPromotesFiveKey()
        testPreferExModesPromotesPms()
        testIgnoreExtensionTreatsPmsAsBms()
        testSkipBetweenDropsHeaderAfterRandom()
        testSelectedObjectsEmptyAndOneNote()
        testSelectedObjectsMixedLengthAndExtra()
        testSelectedObjectsRejectsBadLength()
        testSelectedObjectsWritesLengthKeepsExtra()
        testSelectedObjectsWritesExtraAndUndo()
        testFindDeleteShortNoteAndUndo()
        testFindReplaceLabelMovesChannelAndUndo()
        testFindReplaceTwoNotesOneUndo()
        testFindReplaceBgaLabelAndUndo()
        testFindReplaceBpmAndStopAndUndo()
        testFindReplaceLabelPadsEmptyChannel()
        testTimeSelectionRewritesFixtureInPlace()
        testTimeSelectionMovesPulseAndUndo()
        testTimeSelectionHeaderBPMUpdatesStartNote()
        testTimeSelectionMovesToSecondChannel()
        testTimeSelectionWritesLongNoteLength()
        testTimeSelectionWritesBgaEvent()
        testTimeSelectionWritesStopPulses()
        testTimeSelectionSkipsScroll()
        testTimeSelectionTwoNotesOneUndo()
        testMirrorFixtureShortNote()
        testMirrorFixtureShortNoteUndo()
        testMirrorScratchLane()
        testMirrorCenterKeyDoesNotUndo()
        testMirrorA8Stays()
        testMirrorBGMStays()
        testMirrorLongNoteKeepsLengthAndExtra()
        testMirrorTwoNotesOneUndo()
        testMirrorSwapSamePulse()
        testMirrorBeat5kScratchSkipsMissingLane()
        testMirrorOccupiedDestinationRejected()
        testMirrorLeavesTimingBgaAndLines()
        testMoveDigitFixtureShortNote()
        testMoveDigitFixtureShortNoteUndo()
        testMoveDigitScratchLane()
        testMoveDigitSeven()
        testMoveDigitAlreadyOnTargetDoesNotUndo()
        testMoveDigitTwoNotesOneUndo()
        testMoveDigitShiftMovesEarliestOnly()
        testMoveDigitLongNoteKeepsLengthAndExtra()
        testMoveDigitZeroToBGMKeepsLength()
        testMoveDigitZeroTwoChannelsSamePulse()
        testMoveDigitBeat5kMissingLaneDoesNotMove()
        testMoveDigitOccupiedDestinationRejected()
        testMoveDigitTwoSelectedSamePulseRejected()
        testMoveDigitLeavesTimingBgaAndLines()
        testModifyNotesFixtureLabelA()
        testModifyNotesFixtureLabelAUndo()
        testModifyNotesPadsEmptyChannel()
        testModifyNotesLongNoteKeepsLengthAndExtra()
        testModifyNotesBgaIdAndUndo()
        testModifyNotesBpmAndUndo()
        testModifyNotesStopPulses()
        testModifyNotesSkipsScroll()
        testModifyNotesValueAndLabelTwoUndos()
        testModifyNotesEmptyLabelIdentitiesDoesNotMoveChannel()
        testModifyNotesTwoNotesOneUndo()
        testConvertShortPairToLongSameChannel()
        testConvertShortPairToLongUndo()
        testConvertUnpairedShortStays()
        testConvertShortPairToLongDifferentChannelsSameLane()
        testConvertShortPairDifferentXDoesNotWrite()
        testConvertLongToShortNTKeepsStart()
        testConvertLongToShortBMSEInsertsEnd()
        testConvertAlreadyShortDoesNotWrite()
        testConvertShortPairOccupiedIntervalRejected()
        testConvertLeavesTimingBgaAndLines()
        testConvertHiddenFixtureDoesNotChange()
        testConvertVisibleAlreadyVisibleDoesNotWrite()
        testConvertToggleDoesNotWriteX0()
        testConvertNoteTo31DoesNotWriteX0()
        testConvertNoteToVisibleLaneAndUndo()
        testConvertNoteLongKeepsLengthAndExtra()
        testConvertNoteBeat5kMissingLaneDoesNotWriteX0()
        testConvertNoteOccupiedDestinationRejected()
        testConvertHiddenLeavesTimingBgaAndLines()
        testConvertHiddenTwoNotesDoesNotUndo()
        testCopyClipboardFixtureShortNote()
        testPasteClipboardShortNoteEmptyAndUndo()
        testPasteClipboardAppendsWithoutReplacingFixture()
        testPasteClipboardHiddenIsVisibleLane()
        testPasteClipboardNTLongNote()
        testPasteClipboardBPM()
        testPasteClipboardStop()
        testPasteClipboardSkipsScroll()
        testPasteClipboardBga()
        testPasteClipboardOccupiedRejected()
        testPasteClipboardBeat5kMissingLaneDoesNotWriteX0()
        testPasteClipboardBGMWritesX0()
        testDuplicateNotesFixtureShortSamePulseAndUndo()
        testDuplicateNotesFixtureShortToVpos48()
        testDuplicateNotesHiddenWritesVisibleLane()
        testDuplicateNotesNTLongNote()
        testDuplicateNotesBPM()
        testDuplicateNotesStop()
        testDuplicateNotesSkipsScroll()
        testDuplicateNotesBga()
        testDuplicateNotesOccupiedRejected()
        testDuplicateNotesBeat5kMissingLaneDoesNotWriteX0()
        testDuplicateNotesBGMWritesX0()
        testDuplicateNotesTwoSoundsOneUndo()
        testCutClipboardFixtureShortNoteAndUndo()
        testCutTwoSoundNotesOneUndo()
        testEraseTwoSoundNotesOneUndo()
        testEraseBpmLeavesSoundAndUndo()
        testEraseStopPulsesAndUndo()
        testEraseBgaEventAndUndo()
        testEraseLongNoteOnceNo51()
        testEraseNotesEmptyDoesNotUndo()
        testEraseSoundAndBpmOneUndo()
        testMoveNotesAtVPositionFixtureShortSamePulseAndUndo()
        testMoveNotesAtVPositionFixtureShortToVpos48()
        testMoveNotesAtVPositionHiddenWritesVisibleLane()
        testMoveNotesAtVPositionLongKeepsLengthAndExtra()
        testMoveNotesAtVPositionTwoSoundsOneUndo()
        testMoveNotesAtVPositionBPM()
        testMoveNotesAtVPositionStop()
        testMoveNotesAtVPositionSkipsScroll()
        testMoveNotesAtVPositionBga()
        testMoveNotesAtVPositionOccupiedRejected()
        testMoveNotesAtVPositionBeat5kMissingLaneDoesNotWriteX0()
        testMoveNotesAtVPositionBGMWritesX0()
        testMoveNotesAtVPositionDisableVerticalKeepsVpos()
        print("BmsONEDocumentTests passed")
    }

    private static func testEmptyGoesThroughCpp() {
        let document = BmsONEDocument.empty()
        require(document.title.isEmpty, "empty title")
        require(document.initialBpm == 120, "empty initBPM")
        require(document.modeHint == "beat-7k", "empty modeHint")
        require(document.resolution == 240, "empty resolution")
        require(document.lines.isEmpty && document.soundChannels.isEmpty && document.stopNotes.isEmpty, "empty arrays")
        let json = try! document.jsonString()
        let again = try! BmsONEDocument.fromJSON(json)
        require(again.modeHint == "beat-7k" && again.resolution == 240, "empty JSON via C++")
    }

    private static func testMinimalFixture() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        require(document.title == "Demo", "fixture title")
        require(abs(document.initialBpm - 140) < 1e-9, "fixture initBPM")
        require(document.lines.count == 1 && document.lines[0].y == 240, "fixture line y=240")
        require(document.soundChannels.count == 1, "one sound channel")
        require(document.soundChannels[0].name == "kick.wav", "fixture wav name")
        require(document.soundChannels[0].notes.count == 1, "one short note")
        require(document.soundChannels[0].notes[0].x == 1, "BMSON lane 1")
        require(document.soundChannels[0].notes[0].y == 0, "note pulse 0")
        require(document.soundChannels[0].notes[0].l == 0, "short")
        require(document.soundChannels[0].notes[0].c == false, "not continue")
    }

    private static func testInsertThenRoundtrip() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.insertShortNote(laneX: 2, pulseY: 240)
        require(document.soundChannels[0].notes.count == 2, "appended short note")
        require(document.soundChannels[0].notes[1].x == 2, "inserted lane")
        require(document.soundChannels[0].notes[1].y == 240, "inserted pulse")
        require(document.soundChannels[0].notes[1].l == 0, "inserted short")
        require(document.isModified, "insert marks modified")

        let json = try! document.jsonString()
        let again = try! BmsONEDocument.fromJSON(json)
        require(again.title == "Demo", "roundtrip title")
        require(again.soundChannels[0].notes.count == 2, "roundtrip note count")
        require(again.soundChannels[0].notes[0].x == 1, "original lane kept")
        require(again.soundChannels[0].notes[1].x == 2 && again.soundChannels[0].notes[1].y == 240,
                "inserted note survives C++ from_json")
    }

    private static func testEraseThenRoundtrip() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.eraseNote(atPulse: 0)
        require(document.soundChannels[0].notes.isEmpty, "erased short note")
        require(document.isModified, "erase marks modified")
        let json = try! document.jsonString()
        let again = try! BmsONEDocument.fromJSON(json)
        require(again.soundChannels[0].notes.isEmpty, "erased note stays gone")
    }

    private static func testInsertLongNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.insertNote(laneX: 1, pulseY: 0, length: 240)
        require(document.soundChannels[0].notes.count == 1, "same pulse updates")
        require(document.soundChannels[0].notes[0].l == 240, "one-beat LN")
        require(document.isModified, "long insert marks modified")
        let json = try! document.jsonString()
        let again = try! BmsONEDocument.fromJSON(json)
        require(again.soundChannels[0].notes[0].l == 240, "LN survives C++ from_json")
    }

    private static func testReplaceNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.replaceNote(atPulse: 0, laneX: 2, pulseY: 240, length: 240)
        require(document.soundChannels[0].notes.count == 1, "replace keeps one")
        require(document.soundChannels[0].notes[0].x == 2, "moved lane")
        require(document.soundChannels[0].notes[0].y == 240, "moved pulse")
        require(document.soundChannels[0].notes[0].l == 240, "resized length")
    }

    private static func testUndoInsertAndRedo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        require(!document.canUndo && !document.canRedo, "open has no history")
        try! document.insertShortNote(laneX: 2, pulseY: 240)
        require(document.soundChannels[0].notes.count == 2, "inserted")
        require(document.canUndo && !document.canRedo && document.isModified, "insert is undoable")
        require(document.undo(), "undo insert")
        require(document.soundChannels[0].notes.count == 1, "fixture note remains")
        require(document.soundChannels[0].notes[0].x == 1, "original lane")
        require(!document.isModified && document.canRedo, "undo to opened file is clean")
        require(document.redo(), "redo insert")
        require(document.soundChannels[0].notes.count == 2, "redo restores insert")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 240, "redone note")
        require(document.isModified && document.canUndo, "redo is dirty again")
    }

    private static func testParseErrorUsesBmsonMessage() {
        do {
            _ = try BmsONEDocument.fromJSON("not json")
            fail("bad JSON must throw")
        } catch {
            let text = error.localizedDescription
            require(!text.isEmpty, "BmsonParseError text")
            require(!text.contains("#WAV"), "must not look like a BMS error")
        }
    }

    private static func testLaneHitUsesSkinNumbers() {
        let pane = CGRect(x: 0, y: 0, width: 210, height: 100)
        require(BmsONEPlayingLaneLayout.laneX(at: CGPoint(x: 6, y: 10), in: pane) == 8, "scratch x=8")
        require(BmsONEPlayingLaneLayout.laneX(at: CGPoint(x: 40, y: 10), in: pane) == 1, "first key x=1")
        let short = BmsONEPlayingLaneLayout.noteRect(x: 1, y: 0, l: 0, resolution: 240, in: pane)
        require(short != nil && short!.height == 8, "short note box")
        let long = BmsONEPlayingLaneLayout.noteRect(x: 2, y: 0, l: 240, resolution: 240, in: pane)
        require(long != nil && long!.height == 48, "one-beat LN is 48 px")
    }

    private static func testImportMinimalBms() {
        let document = try! BmsONEDocument.importBms(url: bmsImportURL())
        require(document.title == "ImportDemo", "imported title")
        require(abs(document.initialBpm - 130) < 1e-9, "imported initBPM")
        require(document.modeHint == "beat-5k", "only 11 -> GetMode 5K")
        require(document.isModified, "LoadBms marks dirty")
        require(document.filePath == nil, "imported BMSON has no path")
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].name == "kick.wav", "imported wav")
        require(document.soundChannels[0].notes[0].x == 1, "11 -> x=1")
        require(document.soundChannels[0].notes[0].y == 0, "pulse 0")
        require(document.lines.count == 3, "0, 960, 1920")
        require(document.lines[1].y == 960 && document.lines[2].y == 1920, "extra measure line")
        require(!BmsONEFileTypes.isBmsURL(fixtureURL()), "bmson is not bms")
        require(BmsONEFileTypes.isBmsURL(bmsImportURL()), "bms extension")
    }

    private static func testImportTenKeyBms() {
        let document = try! BmsONEDocument.importBms(url: bmsImportURL("two-player-10k.bms"))
        require(document.modeHint == "beat-10k", "21 without 18 -> 10K")
        require(document.soundChannels.count == 2, "two WAVs")
        require(document.soundChannels[0].notes[0].x == 1, "11 -> x=1")
        require(document.soundChannels[1].notes[0].x == 9, "21 -> x=9")
    }

    private static func testGameModeQuestion() {
        let url = bmsImportURL("scratch-and-keys.bms")
        let data = try! Data(contentsOf: url)
        let question = try! BmsONEDocument.gameModeQuestion(data: data, path: url.path)
        require(question.detected == .mode7k, "18/19 default 7K")
        require(question.choices[0].mode == .mode5k && question.choices[0].mark == "!", "5K !")
        require(question.choices[1].mode == .mode7k && question.choices[1].mark == "O", "7K O")
        require(
            BmsONEImportQuestion.resolvedMode(
                skipQuestions: true,
                detected: question.detected,
                selected: .mode14k
            ) == .mode7k,
            "Skip keeps GetMode"
        )
    }

    private static func testForcedSevenKeyOnMinimal() {
        let document = try! BmsONEDocument.importBms(url: bmsImportURL(), mode: .mode7k)
        require(document.modeHint == "beat-7k", "forced 7K")
        require(document.soundChannels[0].notes[0].x == 1, "11 still x=1")
    }

    /// `#RANDOM 2` + `#ELSEIF 2` 留下通道 `12`。
    private static func testRandomIfBranch() {
        let url = bmsImportURL("random-if.bms")
        let data = try! Data(contentsOf: url)
        require(try! BmsONEDocument.randomMaxima(from: data) == [2], "one RANDOM 2")
        let first = try! BmsONEDocument.importBms(url: url, randomValues: [1])
        require(first.title == "RandomDemo", "title")
        require(first.soundChannels.count == 2, "both WAV defs")
        require(first.soundChannels[0].name == "kick.wav", "IF 1")
        require(first.soundChannels[0].notes[0].x == 1, "11")
        require(first.soundChannels[1].notes.isEmpty, "IF 1 drops 12")
        let second = try! BmsONEDocument.importBms(url: url, randomValues: [2])
        require(second.soundChannels[1].name == "snare.wav", "ELSEIF 2")
        require(second.soundChannels[0].notes.isEmpty, "ELSEIF 2 drops 11")
        require(second.soundChannels[1].notes[0].x == 2, "12")
    }

    /// Shift-JIS 的 `#TITLE テスト`。选 Shift-JIS 能读出日文；默认 UTF-8 读不出这个标题。
    private static func testShiftJISTitle() {
        let data = try! Data(contentsOf: bmsImportURL("shift-jis-title.bms"))
        let previews = BmsONEDocument.encodingPreviews(from: data)
        require(previews.count == 3, "three previews")
        require(previews[1].encoding == .shiftJIS && previews[1].preview.contains("テスト"), "SJIS preview")
        require(previews[0].preview.hasSuffix("..."), "preview ellipsis")
        let decoded = try! BmsONEDocument.importBms(data: data, encoding: .shiftJIS)
        require(decoded.title == "テスト", "SJIS title")
        let asUtf8 = try! BmsONEDocument.importBms(data: data, encoding: .utf8)
        require(asUtf8.title != "テスト", "UTF-8 does not yield テスト")
    }

    /// `stopNotes.v` 是脉冲停顿，桥接原样读出。
    private static func testStopNotesFromJSON() {
        let document = try! BmsONEDocument.fromJSON(
            """
            {"info":{"initBPM":120,"resolution":240},"stopNotes":[{"y":240,"v":240}]}
            """
        )
        require(document.stopNotes.count == 1, "one stop")
        require(document.stopNotes[0].y == 240, "stop pulse")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "stop length in pulses")
    }

    /// 同一脉冲再写 BPM / STOP 会改值。擦掉后两笔撤销能回来。
    private static func testUpsertTimingAndDisplay() {
        let document = BmsONEDocument.empty()
        try! document.upsertBpmNote(pulseY: 240, bpm: 140)
        try! document.upsertStopNote(pulseY: 480, pulses: 240)
        require(document.bpmNotes.count == 1 && abs(document.bpmNotes[0].v - 140) < 1e-9, "bpm 140")
        require(document.stopNotes.count == 1 && abs(document.stopNotes[0].v - 240) < 1e-9, "stop 240")
        try! document.upsertBpmNote(pulseY: 240, bpm: 180)
        require(document.bpmNotes.count == 1 && abs(document.bpmNotes[0].v - 180) < 1e-9, "same pulse replaces")
        try! document.eraseBpmNote(pulseY: 240)
        try! document.eraseStopNote(pulseY: 480)
        require(document.bpmNotes.isEmpty && document.stopNotes.isEmpty, "erased")
        require(document.undo() && document.undo(), "two undos")
        require(document.stopNotes.count == 1 && document.bpmNotes.count == 1, "timing restored")
    }

    private static func testImportBgaEvents() {
        let document = try! BmsONEDocument.importBms(url: bmsImportURL("bga-and-layer.bms"))
        require(document.bgaHeaders.count == 3, "three BMP defs")
        require(Int(document.bgaHeaders[0].identifier) == 0 && document.bgaHeaders[0].name == "miss.png", "BMP00")
        require(Int(document.bgaHeaders[1].identifier) == 1 && document.bgaHeaders[1].name == "bg.png", "BMP01")
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 0, "BGA at 0")
        require(Int(document.bgaEvents[0].identifier) == 1, "BGA id 1")
        require(document.layerEvents.count == 1 && document.layerEvents[0].y == 960, "layer at 960")
        require(document.poorEvents.count == 1 && Int(document.poorEvents[0].identifier) == 0, "miss default")
        let json = try! document.jsonString()
        require(json.contains("\"bga_header\""), "1.0 header key")
        require(json.contains("\"poor_events\""), "1.0 poor key")
    }

    private static func testUpsertBgaAndUndo() {
        let document = BmsONEDocument.empty()
        try! document.upsertBgaEvent(lane: .bga, pulseY: 240, identifier: 1)
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 240, "wrote BGA")
        require(document.bgaHeaders.contains { Int($0.identifier) == 1 }, "header for id 1")
        try! document.upsertBgaEvent(lane: .bga, pulseY: 240, identifier: 2)
        require(document.bgaEvents.count == 1 && Int(document.bgaEvents[0].identifier) == 2, "same pulse replaces")
        try! document.eraseBgaEvent(lane: .bga, pulseY: 240)
        require(document.bgaEvents.isEmpty, "erased")
        require(document.undo(), "undo erase")
        require(document.bgaEvents.count == 1 && Int(document.bgaEvents[0].identifier) == 2, "id 2 back")
    }

    private static func testBmpListRenameAndSynchronize() {
        let renamed = BmsonBmpList.apply(
            WavListEdit(names: ["bg.png", "layer.png"], selected: [0], labelSwaps: []),
            headers: [BmsonBmpList.Header(id: 1, name: "old.png")],
            bgaEvents: [BmsonBeat.BgaEvent(y: 0, id: 1)],
            layerEvents: [],
            poorEvents: [],
            synchronizeLabels: false
        )!
        require(renamed.headers.contains { $0.id == 1 && $0.name == "bg.png" }, "renamed 01")
        require(renamed.bgaEvents[0].id == 1, "id stays when sync is off")
        let swapped = BmsonBmpList.apply(
            WavListEdit(names: ["layer.png", "bg.png"], selected: [0], labelSwaps: [("01", "02")]),
            headers: [
                BmsonBmpList.Header(id: 1, name: "bg.png"),
                BmsonBmpList.Header(id: 2, name: "layer.png")
            ],
            bgaEvents: [BmsonBeat.BgaEvent(y: 0, id: 1)],
            layerEvents: [BmsonBeat.BgaEvent(y: 240, id: 2)],
            poorEvents: [],
            synchronizeLabels: true
        )!
        require(swapped.bgaEvents[0].id == 2, "sync swaps event id")
        require(swapped.layerEvents[0].id == 1, "sync swaps the other id")
        require(BmsonBmpList.apply(
            WavListEdit(names: ["a\nb.png"], selected: [0], labelSwaps: []),
            headers: [],
            bgaEvents: [],
            layerEvents: [],
            poorEvents: [],
            synchronizeLabels: false
        ) == nil, "newline rejected")
    }

    private static func testBmpListWritesJSON() {
        let document = BmsONEDocument.empty()
        try! document.upsertBgaEvent(lane: .bga, pulseY: 0, identifier: 1)
        try! document.applyBmpEdit(
            WavListEdit(names: ["bg.png"], selected: [0], labelSwaps: []),
            synchronizeLabels: false
        )
        let json = try! document.jsonString()
        require(json.contains("bg.png"), "BMP 01 name in JSON")
        require(json.contains("\"bga_header\""), "header key")
        require(document.undo(), "undo rename")
        require(!document.bgaHeaders.contains { $0.name == "bg.png" }, "name restored")
    }

    private static func testBeatScaleMovesBga() {
        var state = twoNoteState()
        state.bgaEvents = [BmsonBeat.BgaEvent(y: 960, id: 1)]
        let next = BmsonBeat.apply(measures: [0], decimal: "2", mode: .scale, to: state)!
        require(next.bgaEvents.count == 1 && next.bgaEvents[0].y == 1920, "later BGA shifts")
        require(next.bgaEvents[0].id == 1, "id stays")
    }

    /// Header 侧栏读 `info`，不套 BMS `#TITLE`。
    private static func testHeaderMappingReadsFixture() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let fields = BmsonHeaderMapping.fields(from: document.info)
        require(fields["TITLE"] == "Demo", "TITLE is info.title")
        require(fields["ARTIST"] == "", "missing artist is empty")
        require(fields["PLAYLEVEL"] == "1", "default level")
        require(fields["TOTAL"] == "100", "default total")
        require(!BmsonHeaderMapping.editableKeys.contains("PLAYER"), "PLAYER is BMS-only")
        require(!BmsonHeaderMapping.editableKeys.contains("RANK"), "RANK is not judgeRank")
        require(BmsonHeaderMapping.editableKeys.contains("BANNER"), "BANNER maps to info extra")
        require(BmsonHeaderMapping.editableKeys.contains("CHARTNAME"), "CHARTNAME is info.chartName")
        require(BmsonHeaderMapping.infoExtraJSONKey(forHeader: "STAGEFILE") == "eyecatchImage", "Stage File")
        require(BmsonHeaderMapping.infoExtraJSONKey(forHeader: "BACKBMP") == "backImage", "Back BMP")
        require(fields["JUDGERANK"] == "100", "default judgeRank")
        require(fields["MODEHINT"] == "beat-7k" || fields["MODEHINT"] == document.modeHint, "modeHint present")
    }

    /// `#SUBARTIST` 在 BMSON 里是数组；侧栏一格用逗号。
    private static func testHeaderMappingSubartistsAndNumbers() {
        require(BmsonHeaderMapping.splitSubartists("A, B") == ["A", "B"], "split")
        require(BmsonHeaderMapping.joinSubartists(["A", "B"]) == "A, B", "join")
        require(BmsonHeaderMapping.splitSubartists("  ").isEmpty, "blank is empty")
        require(BmsonHeaderMapping.parseBPM("180") == 180, "BPM 180")
        require(BmsonHeaderMapping.parseBPM("0") == nil, "zero BPM rejected")
        require(BmsonHeaderMapping.parseBPM("abc") == nil, "text BPM rejected")
        var fields = BmsonInfoFields(BmsONEDocument.empty().info)
        require(BmsonHeaderMapping.apply(key: "PLAYLEVEL", value: "12", to: &fields), "level parses")
        require(fields.level == 12, "level 12")
        require(!BmsonHeaderMapping.apply(key: "PLAYLEVEL", value: "12abc", to: &fields), "level rejects junk")
        require(!BmsonHeaderMapping.apply(key: "PLAYER", value: "2", to: &fields), "PLAYER stays off")
        require(BmsonHeaderMapping.apply(key: "TOTAL", value: "300", to: &fields) && fields.total == 300, "total")
    }

    /// 改 title 写进 JSON，一笔撤销回到 Demo。
    private static func testReplaceTitleAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.replaceHeader(key: "TITLE", value: "Edited")
        require(document.title == "Edited", "title written")
        require((try! document.jsonString()).contains("\"title\": \"Edited\""), "JSON has Edited")
        require(document.undo(), "undo title")
        require(document.title == "Demo", "title restored")
    }

    private static func testReplaceArtistGenreLevelTotal() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.replaceHeader(key: "ARTIST", value: "Author")
        try! document.replaceHeader(key: "GENRE", value: "Game")
        try! document.replaceHeader(key: "SUBTITLE", value: "Mix")
        try! document.replaceHeader(key: "SUBARTIST", value: "Guest, Extra")
        try! document.replaceHeader(key: "PLAYLEVEL", value: "12")
        try! document.replaceHeader(key: "TOTAL", value: "300")
        require(document.info.artist == "Author", "artist")
        require(document.info.genre == "Game", "genre")
        require(document.info.subtitle == "Mix", "subtitle")
        require(document.info.subartists == ["Guest", "Extra"], "subartists array")
        require(document.level == 12, "level")
        require(abs(document.total - 300) < 1e-9, "total")
        let json = try! document.jsonString()
        require(json.contains("\"artist\": \"Author\""), "artist in JSON")
        require(json.contains("\"Guest\""), "subartist in JSON")
    }

    /// 夹具已有 `y=0` 的 bpmNote，Header BPM 同一笔改两条。
    private static func testHeaderBPMUpdatesStartNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.setInitialBPM("180")
        require(abs(document.initialBpm - 180) < 1e-9, "initBPM")
        require(document.bpmNotes.contains { $0.y == 0 && abs($0.v - 180) < 1e-9 }, "start note")
        require(document.undo(), "one undo reverts both")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM restored")
        require(document.bpmNotes.contains { $0.y == 0 && abs($0.v - 140) < 1e-9 }, "start note restored")
    }

    private static func testHeaderBPMOnEmptyDoesNotCreateNote() {
        let document = BmsONEDocument.empty()
        try! document.setInitialBPM("150")
        require(abs(document.initialBpm - 150) < 1e-9, "empty initBPM")
        require(document.bpmNotes.isEmpty, "no new bpmNote")
    }

    private static func testInvalidAndUnsupportedHeader() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        do {
            try document.setInitialBPM("0")
            fail("zero BPM should throw")
        } catch {
            require(document.initialBpm == 140, "zero BPM leaves fixture")
        }
        do {
            try document.replaceHeader(key: "PLAYER", value: "2")
            fail("PLAYER should throw")
        } catch {
            require(document.title == "Demo", "PLAYER does not write")
        }
        do {
            try document.replaceHeader(key: "JUDGERANK", value: "nope")
            fail("JUDGERANK junk should throw")
        } catch {
            require(abs(document.judgeRank - 100) < 1e-9 || abs(document.judgeRank - 100) < 1, "judgeRank unchanged")
        }
    }

    /// 对照 `InfoView`：Chart Name / Judge Rank / Mode Hint 写 `info`；图写 extra。
    private static func testInfoFieldsAndImageExtras() {
        let extras = try! BmsONEDocument.open(url: fixtureURL("unknown-fields.bmson"))
        require(extras.headerFields()["BANNER"] == "bn.png", "banner extra in Header")
        try! extras.replaceHeader(key: "BANNER", value: "new-bn.png")
        require(extras.infoExtraString("banner") == "new-bn.png", "banner written")
        require((try! extras.jsonString()).contains("\"banner\": \"new-bn.png\""), "banner in JSON")
        require(extras.undo(), "undo banner")
        require(extras.infoExtraString("banner") == "bn.png", "banner restored")

        try! extras.replaceHeader(key: "STAGEFILE", value: "eye.png")
        try! extras.replaceHeader(key: "BACKBMP", value: "bg.png")
        try! extras.replaceHeader(key: "TITLEIMAGE", value: "title.png")
        try! extras.replaceHeader(key: "PREVIEWMUSIC", value: "prev.ogg")
        let json = try! extras.jsonString()
        require(json.contains("\"eyecatchImage\": \"eye.png\""), "eyecatchImage")
        require(json.contains("\"backImage\": \"bg.png\""), "backImage")
        require(json.contains("\"titleImage\": \"title.png\""), "titleImage")
        require(json.contains("\"previewMusic\": \"prev.ogg\""), "previewMusic")
        try! extras.replaceHeader(key: "BANNER", value: "")
        require(extras.headerFields()["BANNER"] == "", "empty banner")
        require(!(try! extras.jsonString()).contains("\"banner\""), "banner key removed")

        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.replaceHeader(key: "CHARTNAME", value: "Hyper")
        try! document.replaceHeader(key: "JUDGERANK", value: "80")
        try! document.replaceHeader(key: "MODEHINT", value: "beat-5k")
        require(document.info.chartName == "Hyper", "chartName")
        require(abs(document.judgeRank - 80) < 1e-9, "judgeRank 80")
        require(document.modeHint == "beat-5k", "modeHint written")
        require((try! document.jsonString()).contains("\"chart_name\": \"Hyper\""), "chart_name in JSON")
        require(document.undo() && document.undo() && document.undo(), "undo info fields")
        require(document.info.chartName.isEmpty, "chartName restored")
        require(document.modeHint != "beat-5k" || document.info.modeHint == "beat-7k", "modeHint restored")
    }

    /// 对照 `InfoView` Extra fields。banner 不进折叠，写回不改官方图键。
    private static func testInfoExtraFieldsAndUndo() {
        let bannerOnly = try! BmsONEDocument.open(url: fixtureURL("unknown-fields.bmson"))
        require(bannerOnly.infoExtraFieldsText() == "", "banner is not Extra fields")
        require(bannerOnly.applyInfoExtraFields("\"field_1\": \"14:00\","), "write unknown extra")
        require(bannerOnly.infoExtraFieldsText() == "\"field_1\": \"14:00\"", "field_1 shown")
        require((try! bannerOnly.jsonString()).contains("\"field_1\""), "field_1 in JSON")
        require(bannerOnly.infoExtraString("banner") == "bn.png", "banner stays")
        require(bannerOnly.undo(), "undo extra")
        require(bannerOnly.infoExtraFieldsText() == "", "extra cleared")
        require(bannerOnly.infoExtraString("banner") == "bn.png", "banner after undo")

        let extras = try! BmsONEDocument.open(url: fixtureURL("info-extra-fields.bmson"))
        require(
            extras.infoExtraFieldsText() == "\"field_1\": \"14:00 2015/11/14\",\n\"field_2\": [0,240,480]",
            "fixture extras"
        )
        require(
            extras.applyInfoExtraFields("\"banner\": \"hack.png\", \"title\": \"hack\""),
            "supported keys ignored"
        )
        require(extras.infoExtraFieldsText() == "", "supported keys do not become extras")
        require(extras.infoExtraString("banner") == "bn.png", "banner ignored in Extra fields")
        require(extras.title == "Extra", "title ignored in Extra fields")
        require(extras.applyInfoExtraFields("\"field_2\": [0, 240, 480]"), "rewrite field_2")
        require(extras.infoExtraFieldsText() == "\"field_2\": [0,240,480]", "field_2 only")
        require(!extras.applyInfoExtraFields("nope"), "plain extra rejected")
        require(!extras.applyInfoExtraFields("{"), "truncated extra rejected")
        require(extras.infoExtraFieldsText() == "\"field_2\": [0,240,480]", "reject does not write")
        require(extras.applyInfoExtraFields(""), "empty Extra fields")
        require(extras.infoExtraFieldsText() == "", "empty clears unknown")
        require(extras.infoExtraString("banner") == "bn.png", "empty Extra keeps banner")
    }

    /// 只改 `name` 时音符留在原下标。
    private static func testWavListRenameKeepsNotes() {
        let next = BmsonWavList.apply(
            WavListEdit(names: names(["snare.wav", "kick.wav"]), selected: [0, 1]),
            to: twoChannels(),
            synchronizeLabels: false
        )
        require(next?.count == 2, "two channels")
        require(next?[0].name == "snare.wav" && next?[1].name == "kick.wav", "names swapped")
        require(next?[0].notes[0].x == 1 && next?[1].notes[0].x == 2, "notes stay")
    }

    /// Synchronize 打开时整条声道对调，音符跟着文件走。
    private static func testWavListSynchronizeSwapsChannels() {
        let edit = LegacyWavList.moveUp(names: names(["kick.wav", "snare.wav"]), selected: [1])
        let next = BmsonWavList.apply(edit, to: twoChannels(), synchronizeLabels: true)
        require(next?[0].name == "snare.wav" && next?[1].name == "kick.wav", "files follow")
        require(next?[0].notes[0].x == 2 && next?[1].notes[0].x == 1, "notes follow files")
    }

    private static func testWavListAssignPadsEmptyChannel() {
        let edit = LegacyWavList.assign(
            paths: ["/tmp/hat.wav"],
            selected: [2],
            names: names(["kick.wav"])
        )
        let next = BmsonWavList.apply(
            edit,
            to: [BmsonChartMapping.ChannelInput(name: "kick.wav", notes: [])],
            synchronizeLabels: false
        )
        require(next?.count == 3, "pad 02 empty")
        require(next?[0].name == "kick.wav" && next?[1].name == "" && next?[2].name == "hat.wav", "03 is hat")
    }

    /// Remove 只清空名字，有音符的声道留下。
    private static func testWavListRemoveClearsName() {
        let edit = LegacyWavList.remove(names: names(["kick.wav"]), selected: [0])
        let next = BmsonWavList.apply(edit, to: twoChannels().prefix(1).map { $0 }, synchronizeLabels: false)
        require(next?.count == 1, "channel stays")
        require(next?[0].name == "" && next?[0].notes[0].x == 1, "name cleared")
    }

    private static func testWavListRejectsNewline() {
        var bad = names(["kick.wav"])
        bad[0] = "a\nb.wav"
        require(
            BmsonWavList.apply(
                WavListEdit(names: bad, selected: [0]),
                to: twoChannels().prefix(1).map { $0 },
                synchronizeLabels: false
            ) == nil,
            "newline rejected"
        )
    }

    /// `minimal-roundtrip.bmson` 的 kick.wav 改成 snare.wav，可撤销。
    private static func testReplaceWavNameAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        var renamed = LegacyWavList.emptyNames()
        renamed[0] = "snare.wav"
        try! document.applyWavEdit(WavListEdit(names: renamed, selected: [0]), synchronizeLabels: false)
        require(document.soundChannels[0].name == "snare.wav", "renamed")
        require(document.soundChannels[0].notes[0].x == 1, "note stays")
        require((try! document.jsonString()).contains("\"name\": \"snare.wav\""), "JSON name")
        require(!(try! document.jsonString()).contains("#WAV"), "not BMS WAV")
        require(document.undo(), "undo rename")
        require(document.soundChannels[0].name == "kick.wav", "name restored")
    }

    /// 两声道、Synchronize 打开：上移 02 后音符跟着文件。
    private static func testWavListSynchronizeWritesJSON() {
        let document = try! BmsONEDocument.fromJSON(
            """
            {"version":"1.0.0","info":{"title":"Demo","initBPM":140},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"snare.wav","notes":[{"x":2,"y":240,"l":0,"c":false}]}]}
            """
        )
        let edit = LegacyWavList.moveUp(
            names: names(["kick.wav", "snare.wav"]),
            selected: [1]
        )
        try! document.applyWavEdit(edit, synchronizeLabels: true)
        require(document.soundChannels[0].name == "snare.wav", "02 became 01")
        require(document.soundChannels[0].notes[0].x == 2, "snare notes moved")
        require(document.soundChannels[1].name == "kick.wav" && document.soundChannels[1].notes[0].x == 1, "kick is 02")
        require(document.undo(), "undo swap")
        require(document.soundChannels[0].name == "kick.wav" && document.soundChannels[0].notes[0].x == 1, "order restored")
    }

    private static func testConvertResolutionDoublesPulsesAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        require(!document.resolutionConversionLosesInformation(480), "240→480 lossless")
        try! document.convertResolution(480)
        require(document.resolution == 480, "resolution 480")
        require(document.lines[0].y == 480, "line doubles")
        require(document.soundChannels[0].notes[0].y == 0, "note y=0 stays")
        require(document.soundChannels[0].notes[0].x == 1, "lane stays")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "tempo stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        let json = try! document.jsonString()
        require(json.contains("\"resolution\": 480") || json.contains("\"resolution\":480"), "JSON resolution")
        require(document.undo(), "undo convert")
        require(document.resolution == 240, "resolution restored")
        require(document.lines[0].y == 240, "line restored")
    }

    private static func testConvertResolutionRejectsRange() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        do {
            try document.convertResolution(47)
            fail("47 should reject")
        } catch {
            require(document.resolution == 240, "47 leaves resolution")
        }
        do {
            try document.convertResolution(24001)
            fail("24001 should reject")
        } catch {
            require(document.resolution == 240, "24001 leaves resolution")
        }
        try! document.convertResolution(240)
        require(!document.isModified, "same resolution is a no-op")
        require(BmsONEResolutionConvert.parse(" 480 ") == 480, "trim")
        require(BmsONEResolutionConvert.parse("480abc") == nil, "junk")
        require(BmsONEResolutionConvert.isAllowed(48) && BmsONEResolutionConvert.isAllowed(24000), "bounds")
        require(!BmsONEResolutionConvert.isAllowed(47) && !BmsONEResolutionConvert.isAllowed(24001), "outside")
    }

    private static func testConvertResolutionLossyPulse() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":1,"l":0,"c":false}]}]}"#
        )
        require(document.acceptableResolutionDivider == 1, "divider 1")
        require(document.resolutionConversionLosesInformation(120), "120 loses")
        require(!document.resolutionConversionLosesInformation(480), "480 keeps")
        try! document.convertResolution(120)
        require(document.soundChannels[0].notes[0].y == 0, "1 * 120 / 240 → 0")
        require(document.resolution == 120, "lossy written")
    }

    private static func testConvertResolutionScalesBga() {
        let document = BmsONEDocument.empty()
        try! document.upsertBgaEvent(lane: .bga, pulseY: 240, identifier: 1)
        try! document.convertResolution(480)
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 480, "BGA y doubles")
        require(Int(document.bgaEvents[0].identifier) == 1, "id stays")
        require(document.undo(), "undo convert")
        require(document.bgaEvents[0].y == 240, "BGA y restored")
    }

    /// 空 `lines`、拍 0 和拍 4 各一颗。Scale `2` 后第一小节 8 拍，后音到 `y=1920`。
    private static func testBeatScaleDoublesFirstMeasureAndShiftsLaterNote() {
        let state = twoNoteState()
        let next = BmsonBeat.apply(measures: [0], decimal: "2", mode: .scale, to: state)!
        require(next.lines == [1920], "line at 8 beats")
        require(next.channels[0].notes[0].y == 0 && next.channels[0].notes[0].x == 1, "first stays")
        require(next.channels[0].notes[1].y == 1920 && next.channels[0].notes[1].x == 2, "later shifts")
        require(abs(next.bpmNotes[0].v - 140) < 1e-9 && next.bpmNotes[0].y == 0, "tempo stays")
    }

    /// Preserve 只改线，脉冲不动。拍 4 的音仍在 `y=960`，落到加长后的第一小节。
    private static func testBeatPreserveKeepsPulses() {
        let next = BmsonBeat.apply(measures: [0], decimal: "2", mode: .preserve, to: twoNoteState())!
        require(next.lines == [1920], "line at 8 beats")
        require(next.channels[0].notes[0].y == 0, "y=0 stays")
        require(next.channels[0].notes[1].y == 960, "y=960 stays")
        let measures = BmsonBeat.displayedMeasures(next)
        require(abs(measures[0].length - 8) < 1e-9, "measure 0 is 8 beats")
        require(BmsonChartMapping.measureIndex(beat: 4, in: measures) == 0, "beat 4 is still measure 0")
    }

    /// Measure `0.5`：半小节上的音溢到下一小节。Cut 则删掉。
    private static func testBeatMeasureOverflowsAndCutDeletes() {
        let mid = oneNoteState(y: 480)
        let measured = BmsonBeat.apply(measures: [0], decimal: "0.5", mode: .measure, to: mid)!
        require(measured.lines == [480], "2-beat line")
        require(measured.channels[0].notes[0].y == 480, "pulse stays")
        let measures = BmsonBeat.displayedMeasures(measured)
        require(BmsonChartMapping.measureIndex(beat: 2, in: measures) == 1, "overflows to measure 1")
        let cut = BmsonBeat.apply(measures: [0], decimal: "0.5", mode: .cut, to: mid)!
        require(cut.channels[0].notes.isEmpty, "cut deletes")
        require(BmsonBeat.apply(measures: [0], decimal: "0", mode: .scale, to: mid) == nil, "zero ratio")
        require(BmsonBeat.apply(measures: [], decimal: "2", mode: .scale, to: mid) == mid, "empty selection")
    }

    /// `#00051:0101` 一类：一拍长音 Cut `0.5` 后收到新边界前一个脉冲。
    private static func testBeatCutTrimsLongNote() {
        var state = oneNoteState(y: 0)
        state.channels[0].notes[0].l = 720
        let cut = BmsonBeat.apply(measures: [0], decimal: "0.5", mode: .cut, to: state)!
        require(cut.channels[0].notes[0].y == 0, "start stays")
        require(cut.channels[0].notes[0].l == 479, "trim to newEnd-1")
        var four = oneNoteState(y: 0)
        four.channels[0].notes[0].l = 960
        let cutFour = BmsonBeat.apply(measures: [0], decimal: "0.5", mode: .cut, to: four)!
        require(cutFour.channels[0].notes[0].l == 480, "end at oldEnd only shifts")
    }

    private static func testBeatApplyAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":960,"l":0,"c":false}]}]}"#
        )
        try! document.applyBeat(measures: [0], decimal: "2", mode: LegacyBeat.Mode.scale.rawValue)
        require(document.lines.map(\.y) == [1920], "document line")
        require(document.soundChannels[0].notes[1].y == 1920, "document later note")
        require(document.undo(), "undo beat")
        require(document.lines.isEmpty, "lines restored")
        require(document.soundChannels[0].notes[1].y == 960, "note restored")
    }

    private static func testTransferKeyNoteToBGM() {
        let lanes = BmsONEPlayingLaneLayout.beat7kLaneXs
        let next = BmsonNoteTransfer.toBGM(
            selected: [BmsonNoteTransfer.Address(channel: 0, y: 0)],
            channels: [[BmsonNoteTransfer.Note(x: 1, y: 0, l: 240, c: false)]]
        )
        require(next[0][0].x == 0 && next[0][0].l == 0, "key becomes BGM short")
        require(lanes.first == 8, "scratch first")
    }

    private static func testTransferBGMToFirstVacantKey() {
        let next = BmsonNoteTransfer.toKey(
            selected: [BmsonNoteTransfer.Address(channel: 0, y: 0)],
            channels: [[BmsonNoteTransfer.Note(x: 0, y: 0, l: 0, c: false)]],
            lanes: BmsONEPlayingLaneLayout.beat7kLaneXs
        )!
        require(next[0][0].x == 8, "first vacant is scratch")
        require(BmsonNoteTransfer.toKey(selected: [], channels: [[]], lanes: [8, 1]) == nil, "empty selection")
    }

    private static func testTransferSkipsOccupiedScratch() {
        let next = BmsonNoteTransfer.toKey(
            selected: [BmsonNoteTransfer.Address(channel: 1, y: 0)],
            channels: [
                [BmsonNoteTransfer.Note(x: 8, y: 0, l: 0, c: false)],
                [BmsonNoteTransfer.Note(x: 0, y: 0, l: 0, c: false)]
            ],
            lanes: BmsONEPlayingLaneLayout.beat7kLaneXs
        )!
        require(next[1][0].x == 1, "scratch taken so first key")
        require(next[0][0].x == 8, "occupant stays")
    }

    private static func testTransferTwoBGMNotesGetDifferentLanes() {
        let next = BmsonNoteTransfer.toKey(
            selected: [
                BmsonNoteTransfer.Address(channel: 0, y: 0),
                BmsonNoteTransfer.Address(channel: 1, y: 0)
            ],
            channels: [
                [BmsonNoteTransfer.Note(x: 0, y: 0, l: 0, c: false)],
                [BmsonNoteTransfer.Note(x: 0, y: 0, l: 0, c: false)]
            ],
            lanes: BmsONEPlayingLaneLayout.beat7kLaneXs
        )!
        require(next[0][0].x == 8 && next[1][0].x == 1, "two BGM get 8 then 1")
    }

    private static func testTransferToKeyKeepsExistingKey() {
        let next = BmsonNoteTransfer.toKey(
            selected: [BmsonNoteTransfer.Address(channel: 0, y: 0)],
            channels: [[BmsonNoteTransfer.Note(x: 3, y: 0, l: 120, c: true)]],
            lanes: BmsONEPlayingLaneLayout.beat7kLaneXs
        )!
        require(next[0][0].x == 3 && next[0][0].l == 120 && next[0][0].c, "key note stays")
    }

    private static func testTransferToBGMClearsLengthAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":240,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.transferNotes(identities: [identity], toBGM: true)
        require(document.soundChannels[0].notes[0].x == 0, "document BGM")
        require(document.soundChannels[0].notes[0].l == 0, "length cleared")
        require(document.undo(), "undo transfer")
        require(document.soundChannels[0].notes[0].x == 1, "key restored")
        require(document.soundChannels[0].notes[0].l == 240, "length restored")
        try! document.transferNotes(identities: [identity], toBGM: false)
        require(document.soundChannels[0].notes[0].x == 1, "already key")
    }

    private static func testSeparateKeepsMainAndMovesOther() {
        let lanes = BmsONEPlayingLaneLayout.beat7kLaneXs
        let next = BmsonNoteTransfer.separateLayered(
            selected: [
                BmsonNoteTransfer.Address(channel: 0, y: 0),
                BmsonNoteTransfer.Address(channel: 1, y: 0)
            ],
            channels: [
                [BmsonNoteTransfer.Note(x: 1, y: 0, l: 0, c: false)],
                [BmsonNoteTransfer.Note(x: 1, y: 0, l: 0, c: false)]
            ],
            lanes: lanes
        )!
        require(next[0][0].x == 1, "main stays")
        require(next[1][0].x == 2, "other takes next vacant key")
        require(BmsonNoteTransfer.separateLayered(selected: [], channels: [[]], lanes: lanes) == nil, "empty")
    }

    private static func testSeparateIllegalMovesBoth() {
        let next = BmsonNoteTransfer.separateLayered(
            selected: [
                BmsonNoteTransfer.Address(channel: 0, y: 0),
                BmsonNoteTransfer.Address(channel: 1, y: 0)
            ],
            channels: [
                [BmsonNoteTransfer.Note(x: 1, y: 0, l: 240, c: false)],
                [BmsonNoteTransfer.Note(x: 1, y: 0, l: 0, c: false)]
            ],
            lanes: BmsONEPlayingLaneLayout.beat7kLaneXs
        )!
        require(next[0][0].x == 2 && next[0][0].l == 240, "illegal main moves")
        require(next[1][0].x == 3 && next[1][0].l == 0, "illegal other next lane")
    }

    private static func testSeparateIgnoresLongCover() {
        let next = BmsonNoteTransfer.separateLayered(
            selected: [
                BmsonNoteTransfer.Address(channel: 0, y: 0),
                BmsonNoteTransfer.Address(channel: 1, y: 240)
            ],
            channels: [
                [BmsonNoteTransfer.Note(x: 1, y: 0, l: 480, c: false)],
                [BmsonNoteTransfer.Note(x: 1, y: 240, l: 0, c: false)]
            ],
            lanes: BmsONEPlayingLaneLayout.beat7kLaneXs
        )!
        require(next[0][0].x == 1 && next[1][0].x == 1, "cover is overlapping not layering")
    }

    private static func testSeparateAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        try! document.separateLayeredNotes(identities: [first, second])
        require(document.soundChannels[0].notes[0].x == 1, "document main")
        require(document.soundChannels[1].notes[0].x == 2, "document other")
        require(document.undo(), "undo separate")
        require(document.soundChannels[1].notes[0].x == 1, "stacked again")
    }

    private static func testInsertBarLineSplitsDefaultMeasure() {
        let next = BmsonBarLine.insert(pulse: 480, lines: [], lastPulse: 0, resolution: 240)!
        require(next == [0, 480], "mid-measure line")
        require(
            BmsonBarLine.insert(pulse: -1, lines: [], lastPulse: 0, resolution: 240) == nil,
            "negative"
        )
    }

    private static func testInsertBarLineSkipsEphemeralFourBeat() {
        require(
            BmsonBarLine.insert(pulse: 960, lines: [], lastPulse: 0, resolution: 240) == nil,
            "default 4/4 stays ephemeral"
        )
        require(
            BmsonBarLine.remove(pulse: 960, lines: [], lastPulse: 0, resolution: 240) == nil,
            "ephemeral comes back"
        )
        require(
            BmsonBarLine.remove(pulse: 0, lines: [0, 480], lastPulse: 0, resolution: 240) == nil,
            "zero returns"
        )
    }

    private static func testInsertBarLineMaterializesEarlierEphemeral() {
        let next = BmsonBarLine.insert(pulse: 1440, lines: [], lastPulse: 0, resolution: 240)!
        require(next == [0, 960, 1440], "earlier 4/4 becomes real")
    }

    private static func testRemoveBarLineAndUndo() {
        let document = try! BmsONEDocument.fromJSON(#"{"info":{"resolution":240},"soundChannels":[]}"#)
        require(document.insertBarLine(pulseY: 480), "insert")
        require(document.lines.map(\.y) == [0, 480], "stored split")
        require(!document.insertBarLine(pulseY: 480), "already there")
        require(document.removeBarLine(pulseY: 480), "remove")
        require(document.lines.isEmpty, "back to default")
        require(document.undo(), "undo remove")
        require(document.lines.map(\.y) == [0, 480], "split again")
    }

    private static func testChannelAddAppendsEmptyNotes() {
        let added = BmsonChannel.add(
            names: ["/tmp/kick.wav", "snare.ogg"],
            to: [BmsonChartMapping.ChannelInput(name: "hat.wav", notes: [])]
        )!
        require(added.count == 3, "appended two")
        require(added[1].name == "kick.wav" && added[1].notes.isEmpty, "basename empty notes")
        require(added[2].name == "snare.ogg", "second name")
        require(BmsonChannel.add(names: [], to: []) == nil, "empty add")
        require(BmsonChannel.fileName(from: "/a/b/c.wav") == "c.wav", "basename")
    }

    private static func testChannelDestroyRemovesNotes() {
        let channels = [
            BmsonChartMapping.ChannelInput(
                name: "a.wav",
                notes: [BmsonChartMapping.NoteInput(x: 1, y: 0, l: 0, c: false)]
            ),
            BmsonChartMapping.ChannelInput(name: "b.wav", notes: [])
        ]
        let next = BmsonChannel.destroy(index: 0, in: channels)!
        require(next.count == 1 && next[0].name == "b.wav", "notes gone with channel")
        require(BmsonChannel.selectionAfterDestroy(current: 0, countBefore: 2) == 0, "keep index")
        require(BmsonChannel.selectionAfterDestroy(current: 1, countBefore: 2) == 0, "last falls back")
        require(BmsonChannel.selectionAfterDestroy(current: 0, countBefore: 1) == -1, "empty")
    }

    private static func testChannelMoveAndSelectWrap() {
        let channels = [
            BmsonChartMapping.ChannelInput(name: "a.wav", notes: []),
            BmsonChartMapping.ChannelInput(name: "b.wav", notes: []),
            BmsonChartMapping.ChannelInput(name: "c.wav", notes: [])
        ]
        let left = BmsonChannel.move(from: 1, to: 0, in: channels)!
        require(left.map(\.name) == ["b.wav", "a.wav", "c.wav"], "move left")
        require(BmsonChannel.move(from: 0, to: -1, in: channels) == nil, "already first")
        require(BmsonChannel.selectPrevious(current: 0, count: 3) == 2, "wrap prev")
        require(BmsonChannel.selectNext(current: 2, count: 3) == 0, "wrap next")
        require(BmsonChannel.selectNext(current: -1, count: 3) == nil, "no current")
    }

    private static func testChannelFindContainsCaseSensitive() {
        let names = ["Kick.wav", "snare.wav", "hat.wav"]
        require(BmsonChannel.matches("Kick.wav", keyword: "Kick"), "exact case")
        require(!BmsonChannel.matches("Kick.wav", keyword: "kick"), "case sensitive")
        require(BmsonChannel.matches("Kick.wav", keyword: ""), "empty keyword")
        require(BmsonChannel.findNext(keyword: "wav", current: 0, names: names) == 1, "next wav")
        require(BmsonChannel.findPrevious(keyword: "hat", current: 0, names: names) == 2, "wrap prev")
        require(BmsonChannel.findNext(keyword: "none", current: 0, names: names) == nil, "no hit")
    }

    private static func testChannelFindActiveInVisibleRange() {
        require(!BmsonChannel.isActiveInRegion(locations: [480], tBegin: 600, tEnd: 200), "empty interval")
        require(!BmsonChannel.isActiveInRegion(locations: [200], tBegin: 200, tEnd: 600), "exclude tBegin")
        require(BmsonChannel.isActiveInRegion(locations: [600], tBegin: 200, tEnd: 600), "include tEnd")
        require(BmsonChannel.isActiveInRegion(locations: [480], tBegin: 200, tEnd: 600), "inside")
        require(!BmsonChannel.isActiveInRegion(locations: [], tBegin: 200, tEnd: 600), "no notes")

        let names = ["kick.wav", "snare.wav", "hat.wav"]
        let active = [false, true, false]
        require(
            BmsonChannel.findNext(keyword: "wav", current: 0, names: names, activeInRegion: active) == 1,
            "skip inactive snare-next"
        )
        require(
            BmsonChannel.findNext(keyword: "wav", current: 1, names: names, activeInRegion: active) == 1,
            "wrap stays on only active"
        )
        require(
            BmsonChannel.findPrevious(keyword: "", current: 2, names: names, activeInRegion: active) == 1,
            "prev empty keyword hits active"
        )
        require(
            BmsonChannel.findNext(keyword: "wav", current: 0, names: names, activeInRegion: [false, false, false]) == nil,
            "none active beeps"
        )

        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"snare.wav","notes":[{"x":2,"y":480,"l":0,"c":false}]},{"name":"hat.wav","notes":[{"x":3,"y":960,"l":0,"c":false}]}]}"#
        )
        let locations = document.soundChannels.map { $0.notes.map(\.y) }
        let mask = locations.map { BmsonChannel.isActiveInRegion(locations: $0, tBegin: 200, tEnd: 600) }
        require(mask == [false, true, false], "document notes in (200, 600]")
        require(
            BmsonChannel.findNext(
                keyword: "",
                current: 0,
                names: document.soundChannels.map(\.name),
                activeInRegion: mask
            ) == 1,
            "empty keyword next active"
        )
    }

    /// 对照 `UpdateCache` / `IsActiveInRegion` 的解码缓存。
    /// 44100 帧、44100 Hz、120 BPM、分辨率 240：1 秒 = 480 脉冲。
    private static func testChannelPlaybackCacheStillPlaying() {
        let wave = BmsonChannel.WaveSummary(frameCount: 44100, sampleRate: 44100, channelCount: 2)
        require(
            BmsonChannel.waveSummary(sampleCount: 88200, channels: 2, sampleRate: 44100) == wave,
            "stereo frames"
        )
        let trigger: [(y: Int64, c: Bool)] = [(y: 0, c: false)]
        require(
            abs(
                BmsonChannel.samplesPerTick(sampleRate: 44100, tempo: 120, resolution: 240) - 91.875
            ) < 1e-12,
            "samples per tick"
        )
        require(
            BmsonChannel.isActiveInRegion(
                notes: trigger,
                tBegin: 200,
                tEnd: 400,
                wave: wave,
                initBpm: 120,
                resolution: 240
            ),
            "still playing after start"
        )
        require(
            !BmsonChannel.isActiveInRegion(
                notes: trigger,
                tBegin: 480,
                tEnd: 600,
                wave: wave,
                initBpm: 120,
                resolution: 240
            ),
            "ended at 480"
        )
        require(
            !BmsonChannel.isActiveInRegion(
                notes: [(y: 0, c: true)],
                tBegin: 200,
                tEnd: 400,
                wave: wave,
                initBpm: 120,
                resolution: 240
            ),
            "continue does not start"
        )
        require(
            BmsonChannel.isActiveInRegion(
                notes: [(y: 300, c: true)],
                tBegin: 200,
                tEnd: 400,
                wave: wave,
                initBpm: 120,
                resolution: 240
            ),
            "continue note still counts as a note"
        )
        require(
            !BmsonChannel.isActiveInRegion(
                notes: trigger,
                tBegin: 200,
                tEnd: 400,
                wave: BmsonChannel.WaveSummary(frameCount: 0, sampleRate: 44100),
                initBpm: 120,
                resolution: 240
            ),
            "invalid wave is not active"
        )
        require(
            BmsonChannel.isActiveInRegion(
                notes: [(y: 480, c: false)],
                tBegin: 200,
                tEnd: 600,
                wave: nil,
                initBpm: 120,
                resolution: 240
            ),
            "missing wave keeps note-only"
        )
        let faster: [(y: Int64, v: Double)] = [(y: 240, v: 240)]
        require(
            BmsonChannel.isActiveInRegion(
                notes: trigger,
                tBegin: 500,
                tEnd: 600,
                wave: wave,
                initBpm: 120,
                resolution: 240,
                bpmNotes: faster
            ),
            "BPM during play extends to 720"
        )
        require(
            !BmsonChannel.isActiveInRegion(
                notes: trigger,
                tBegin: 720,
                tEnd: 800,
                wave: wave,
                initBpm: 120,
                resolution: 240,
                bpmNotes: faster
            ),
            "ended after BPM stretch"
        )
        let restart: [(y: Int64, c: Bool)] = [(y: 0, c: false), (y: 240, c: false)]
        require(
            BmsonChannel.isActiveInRegion(
                notes: restart,
                tBegin: 500,
                tEnd: 600,
                wave: wave,
                initBpm: 120,
                resolution: 240
            ),
            "restart before end"
        )
    }

    /// 对照 `ChannelInfoView::TextForSamplingRate` / `WaveSummaryUpdated`。
    private static func testChannelInfoLabels() {
        require(BmsonChannel.textForSamplingRate(48000) == "48kHz", "48k")
        require(BmsonChannel.textForSamplingRate(44100) == "44.1kHz", "44.1k")
        require(BmsonChannel.textForSamplingRate(22050) == "22.05kHz", "22.05k")
        require(BmsonChannel.textForSamplingRate(44101) == "44.101kHz", "44.101k")
        require(BmsonChannel.qtGeneral(1) == "1", "1 sec number")
        require(BmsonChannel.qtGeneral(0.5) == "0.5", "0.5 sec number")
        let stereo = BmsonChannel.WaveSummary(
            frameCount: 44100,
            sampleRate: 44100,
            channelCount: 2,
            sampleSize: 16
        )
        let labels = BmsonChannel.channelInfoLabels(stereo)
        require(labels.format == "16bit/2ch/44.1kHz", "format")
        require(labels.length == "1 sec", "1 sec")
        let half = BmsonChannel.WaveSummary(frameCount: 22050, sampleRate: 44100, channelCount: 1)
        require(BmsonChannel.channelInfoLabels(half).length == "0.5 sec", "0.5 sec")
        require(BmsonChannel.channelInfoLabels(nil) == ("", ""), "missing")
        require(
            BmsonChannel.channelInfoLabels(BmsonChannel.WaveSummary(frameCount: 0, sampleRate: 44100))
                == ("", ""),
            "invalid"
        )
    }

    /// 对照 `TaskDrawOverallWaveformAndRmsCache`。不是截图。
    private static func testOverallWaveform() {
        require(BmsonOverallWaveform.imageWidth == 320, "320")
        require(BmsonOverallWaveform.imageHeight == 160, "160")
        require(BmsonOverallWaveform.sidebarHeight == 64, "sidebar working height")
        require(BmsonOverallWaveform.peakColor == 0x009900, "peak 0x009900")
        require(BmsonOverallWaveform.rmsColor == 0x66CC66, "rms 0x66CC66")
        require(BmsonOverallWaveform.pcm16Float(16384) == 0.5, "16384/32768")
        require(BmsonOverallWaveform.samplesPerPixel(frameCount: 640) == 2, "640/320")
        require(BmsonOverallWaveform.samplesPerPixel(frameCount: 100) == 0, "short file every frame")
        require(BmsonOverallWaveform.dx(frameCount: 640) == 0.5, "320/640")
        let half = [Int16](repeating: 16384, count: 640)
        let mono = BmsonOverallWaveform.payload(samples: half, channels: 1)
        require(!mono.stereo, "mono flag")
        require(mono.columns.count == 320, "exact columns")
        require(mono.columns[0].peakL == 127 && mono.columns[0].peakR == 127, "peak 0.5*255")
        require(mono.columns[0].rmsL == 127 && mono.columns[0].rmsR == 127, "rms sqrt(0.25)")
        let leftover = [Int16](repeating: 16384, count: 641)
        require(
            BmsonOverallWaveform.payload(samples: leftover, channels: 1).columns.count == 320,
            "drop remainder"
        )
        let short = [Int16](repeating: 16384, count: 100)
        let shortColumns = BmsonOverallWaveform.payload(samples: short, channels: 1).columns
        require(shortColumns.count == 100, "spp 0 emits every frame")
        require(shortColumns[0].peakL == 127, "short peak")
        require(shortColumns[0].rmsL == 228, "sqrt(0.8)*255")
        var stereoSamples: [Int16] = []
        stereoSamples.reserveCapacity(1280)
        for _ in 0..<640 {
            stereoSamples.append(16384)
            stereoSamples.append(0)
        }
        let stereo = BmsonOverallWaveform.payload(samples: stereoSamples, channels: 2)
        require(stereo.stereo, "stereo flag")
        require(stereo.columns.count == 320, "stereo columns")
        require(stereo.columns[0].peakL == 127 && stereo.columns[0].peakR == 0, "L/R peak")
        require(stereo.columns[0].rmsL == 127 && stereo.columns[0].rmsR == 0, "L/R rms")
        let monoBands = BmsonOverallWaveform.bands(stereo: false)
        require(monoBands.left.center == 80 && monoBands.left.half == 80, "mono band")
        require(monoBands.right == nil, "mono one band")
        let stereoBands = BmsonOverallWaveform.bands(stereo: true)
        require(stereoBands.left.center == 40 && stereoBands.left.half == 40, "stereo L")
        require(stereoBands.right?.center == 120 && stereoBands.right?.half == 40, "stereo R")
        let peakLine = BmsonOverallWaveform.line(center: 80, height: 160, divisor: 2, amplitude: 127)
        require(peakLine.y0 == 41 && peakLine.y1 == 119, "127*160/2/255")
        let stereoLine = BmsonOverallWaveform.line(center: 40, height: 160, divisor: 4, amplitude: 127)
        require(stereoLine.y0 == 21 && stereoLine.y1 == 59, "127*160/4/255")
        require(BmsonOverallWaveform.payload(samples: [], channels: 1) == .empty, "empty")
        require(BmsonOverallWaveform.columns(frames: [], stereo: false).isEmpty, "no frames")
    }

    /// 对照 `RmsCacheBlockSize` / `DrawRmsGraph` / `DrawActivityGraph`。不是截图。
    private static func testLaneWaveform() {
        require(BmsonLaneWaveform.blockSize == 64, "64")
        require(BmsonLaneWaveform.packetSampleCount == 16384, "64*256")
        require(BmsonLaneWaveform.gain == 2, "gain 2")
        require(BmsonLaneWaveform.bgmColor == 0x009900, "BGM green")
        require(BmsonLaneWaveform.keyColor == 0xCC9933, "key gold")
        let half = [Int16](repeating: 16384, count: 64)
        let one = BmsonLaneWaveform.entries(samples: half, channels: 1)
        require(one.count == 1, "one block")
        require(one[0].left == 63 && one[0].right == 63, "0.5*127")
        require(BmsonLaneWaveform.entries(samples: Array(half.dropLast()), channels: 1).isEmpty, "drop tail")
        require(BmsonLaneWaveform.entries(samples: half + half, channels: 1).count == 2, "two blocks")
        let mixed = BmsonLaneWaveform.mixed(
            entries: one,
            position: 0,
            nextPosition: 64,
            frameCount: 64
        )
        require(mixed != nil && abs(mixed!.left - 63.0 / 127.0) < 1e-6, "mix 63/127")
        let span64 = BmsonLaneWaveform.span(width: 64, left: 0.5, right: 0.5)
        require(span64 == BmsonLaneWaveform.Span(left: 2, right: 62), "full-ish 64")
        let span32 = BmsonLaneWaveform.span(width: 32, left: 0.25, right: 0.25)
        require(span32 == BmsonLaneWaveform.Span(left: 8, right: 25), "compact 0.25")
        require(BmsonLaneWaveform.span(width: 64, left: 0, right: 0) == BmsonLaneWaveform.Span(left: 32, right: 33), "center tick")
        require(
            BmsonLaneWaveform.color(notes: [(y: 0, x: 0)], ticks: 0) == 0x009900,
            "BGM note"
        )
        require(
            BmsonLaneWaveform.color(notes: [(y: 0, x: 1)], ticks: 10) == 0xCC9933,
            "key note"
        )
        require(BmsonLaneWaveform.color(notes: [], ticks: 0) == 0x009900, "no note")
        require(
            BmsonLaneWaveform.activityBand(width: 32) == BmsonLaneWaveform.Span(left: 12, right: 20),
            "simple 32"
        )
        require(
            BmsonLaneWaveform.activityBand(width: 64) == BmsonLaneWaveform.Span(left: 24, right: 40),
            "simple 64"
        )
        let wave = BmsonChannel.WaveSummary(frameCount: 44100, sampleRate: 44100)
        let cache = BmsonChannel.playbackCache(
            notes: [(y: 0, c: false)],
            wave: wave,
            initBpm: 120,
            resolution: 240
        )
        let at240 = BmsonLaneWaveform.samplePosition(
            ticks: 240,
            cache: cache,
            sampleRate: 44100,
            resolution: 240
        )
        require(at240 != nil && abs(at240! - 22050) < 1e-6, "halfway sample")
        let channel = BmsonLaneWaveform.Channel(
            entries: Array(repeating: BmsonLaneWaveform.Entry(left: 63, right: 63), count: 700),
            cache: cache,
            notes: [(y: 0, x: 1)],
            frameCount: 44100,
            sampleRate: 44100
        )
        let row = BmsonLaneWaveform.rms(ticks: 240, nextTicks: 245, channel: channel, resolution: 240)
        require(row != nil && abs(row!.left - 63.0 / 127.0) < 1e-5, "playing row")
        let silent = BmsonLaneWaveform.rms(ticks: 600, nextTicks: 605, channel: channel, resolution: 240)
        require(silent == nil, "after end")
        let acts = BmsonLaneWaveform.activities(
            cache: cache,
            notes: [(y: 0, x: 1)],
            tBegin: 0,
            tEnd: 400
        )
        require(acts == [BmsonLaneWaveform.Activity(keyLane: true, tBegin: 0, tEnd: 400)], "clip end")
        let bgm = BmsonLaneWaveform.activities(
            cache: cache,
            notes: [(y: 0, x: 0)],
            tBegin: 0,
            tEnd: 480
        )
        require(bgm == [BmsonLaneWaveform.Activity(keyLane: false, tBegin: 0, tEnd: 480)], "BGM to end")
        require(BmsONESoundChannelLaneMode.normal.drawsWaveform, "normal draws")
        require(!BmsONESoundChannelLaneMode.simple.drawsWaveform, "simple activity")
    }

    /// 对照 `ChannelDisplayFilteringConditionsChanged`。共用谱面藏音，不另开车道。
    private static func testShowHitChannelsOnly() {
        require(
            BmsonChannel.isShown(
                hideOthers: false,
                name: "snare.wav",
                keyword: "kick",
                isActive: false,
                filterActive: true
            ),
            "hide off shows all"
        )
        require(
            BmsonChannel.isShown(
                hideOthers: true,
                name: "Kick.wav",
                keyword: "kick",
                isActive: true,
                filterActive: false
            ) == false,
            "case sensitive hide"
        )
        require(
            BmsonChannel.isShown(
                hideOthers: true,
                name: "snare.wav",
                keyword: "",
                isActive: false,
                filterActive: false
            ),
            "empty keyword shows"
        )
        require(
            !BmsonChannel.isShown(
                hideOthers: true,
                name: "snare.wav",
                keyword: "",
                isActive: false,
                filterActive: true
            ),
            "empty keyword still needs active"
        )
        require(
            BmsonChannel.isShown(
                hideOthers: true,
                name: "snare.wav",
                keyword: "wav",
                isActive: true,
                filterActive: true
            ),
            "match and active"
        )

        let names = ["kick.wav", "snare.wav", "hat.wav"]
        let active = [false, true, false]
        require(
            BmsonChannel.shownMask(
                hideOthers: true,
                names: names,
                keyword: "",
                activeInRegion: active,
                filterActive: true
            ) == [false, true, false],
            "hide + active keeps snare"
        )
        require(
            BmsonChannel.shownMask(
                hideOthers: true,
                names: names,
                keyword: "hat",
                activeInRegion: nil,
                filterActive: false
            ) == [false, false, true],
            "keyword hat only"
        )

        let channels = [
            BmsonChartMapping.ChannelInput(
                name: "kick.wav",
                notes: [BmsonChartMapping.NoteInput(x: 1, y: 0, l: 0, c: false)]
            ),
            BmsonChartMapping.ChannelInput(
                name: "snare.wav",
                notes: [BmsonChartMapping.NoteInput(x: 2, y: 480, l: 0, c: false)]
            ),
            BmsonChartMapping.ChannelInput(
                name: "hat.wav",
                notes: [BmsonChartMapping.NoteInput(x: 3, y: 960, l: 0, c: false)]
            )
        ]
        let shown = BmsonChannel.shownMask(
            hideOthers: true,
            names: channels.map(\.name),
            keyword: "",
            activeInRegion: [false, true, false],
            filterActive: true
        )
        let visible = BmsonChartMapping.visibleNotes(
            channels: BmsonChannel.visibleChannels(channels, shown: shown),
            measures: BmsonChartMapping.measures(lines: [], lastPulse: 960, resolution: 240),
            resolution: 240,
            modeHint: "beat-7k"
        )
        require(visible.count == 1, "only snare note remains")
        require(
            visible[0].identity == BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0),
            "kept channel 1"
        )
        require(
            BmsonChannel.visibleChannels(channels, shown: nil)[0].notes.count == 1,
            "nil mask keeps notes"
        )
    }

    private static func testWriteContinueFlagFromShift() {
        require(BmsonWriteContinue.flag(shiftHeld: false) == true, "no shift is continue")
        require(BmsonWriteContinue.flag(shiftHeld: true) == false, "shift is new attack")
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[]}]}"#
        )
        try! document.insertNote(
            laneX: 1,
            pulseY: 0,
            length: 0,
            continueFlag: BmsonWriteContinue.flag(shiftHeld: false)
        )
        try! document.insertNote(
            laneX: 2,
            pulseY: 240,
            length: 0,
            continueFlag: BmsonWriteContinue.flag(shiftHeld: true)
        )
        require(document.soundChannels[0].notes[0].c == true, "click writes c")
        require(document.soundChannels[0].notes[1].c == false, "shift click writes attack")
        try! document.insertNote(laneX: 3, pulseY: 480, length: 240, continueFlag: true)
        require(document.soundChannels[0].notes[2].c == true, "long keep c")
        require(document.soundChannels[0].notes[2].l == 240, "long length")
        require(document.undo(), "undo long")
        require(document.soundChannels[0].notes.count == 2, "two left")
    }

    private static func testChannelSetNameAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[]}]}"#
        )
        try! document.addSoundChannels(paths: ["c.wav"])
        require(document.soundChannels.count == 3, "added")
        require(document.soundChannels[2].name == "c.wav", "new empty")
        require(document.destroySoundChannel(at: 0), "destroy first")
        require(document.soundChannels.count == 2, "two left")
        require(document.soundChannels[0].name == "b.wav", "notes left with b")
        require(document.soundChannels[0].notes.isEmpty, "first notes were destroyed")
        require(document.moveSoundChannel(from: 0, to: 1), "move")
        require(document.soundChannels.map(\.name) == ["c.wav", "b.wav"], "order")
        require(document.setSoundChannelName(at: 0, path: "/tmp/hat.ogg"), "rename")
        require(document.soundChannels[0].name == "hat.ogg", "basename")
        require(document.undo(), "undo rename")
        require(document.soundChannels[0].name == "c.wav", "name back")
    }

    private static func testPreferExModesPromotesFiveKey() {
        let url = bmsImportURL()
        let plain = try! BmsONEDocument.importBms(url: url)
        require(plain.modeHint == "beat-5k", "default GetMode 5K")
        var options = BmsONEImportOptions()
        options.preferExModes = true
        let promoted = try! BmsONEDocument.importBms(url: url, options: options)
        require(promoted.modeHint == "beat-7k", "preferExModes 7K")
    }

    private static func testPreferExModesPromotesPms() {
        let url = bmsImportURL("pms-5k.pms")
        let plain = try! BmsONEDocument.importBms(url: url)
        require(plain.modeHint == "popn-5k", "default PMS 5K")
        var options = BmsONEImportOptions()
        options.preferExModes = true
        let promoted = try! BmsONEDocument.importBms(url: url, options: options)
        require(promoted.modeHint == "popn-9k", "preferExModes PMS 9K")
    }

    private static func testIgnoreExtensionTreatsPmsAsBms() {
        var options = BmsONEImportOptions()
        options.ignoreExtension = true
        let document = try! BmsONEDocument.importBms(url: bmsImportURL("pms-5k.pms"), options: options)
        require(document.modeHint == "beat-5k", "ignore .pms -> GetMode BMS 5K")
    }

    private static func testSkipBetweenDropsHeaderAfterRandom() {
        let url = bmsImportURL("random-skip-between.bms")
        let kept = try! BmsONEDocument.importBms(url: url, randomValues: [1])
        require(kept.soundChannels.map(\.name) == ["kick.wav", "skipped.wav"], "keep WAV02")
        var options = BmsONEImportOptions()
        options.skipBetweenRandomAndIf = true
        let dropped = try! BmsONEDocument.importBms(url: url, randomValues: [1], options: options)
        require(dropped.soundChannels.map(\.name) == ["kick.wav"], "skip WAV02")
        require(dropped.soundChannels[0].notes[0].x == 1, "IF 1 keeps 11")
    }

    private static func twoNoteState() -> BmsonBeat.State {
        BmsonBeat.State(
            lines: [],
            channels: [
                BmsonChartMapping.ChannelInput(
                    name: "a.wav",
                    notes: [
                        BmsonChartMapping.NoteInput(x: 1, y: 0, l: 0, c: false),
                        BmsonChartMapping.NoteInput(x: 2, y: 960, l: 0, c: false)
                    ]
                )
            ],
            bpmNotes: [BmsonBeat.Timing(y: 0, v: 140)],
            stopNotes: [],
            resolution: 240
        )
    }

    private static func oneNoteState(y: Int64) -> BmsonBeat.State {
        BmsonBeat.State(
            lines: [],
            channels: [
                BmsonChartMapping.ChannelInput(
                    name: "a.wav",
                    notes: [BmsonChartMapping.NoteInput(x: 1, y: y, l: 0, c: false)]
                )
            ],
            bpmNotes: [],
            stopNotes: [],
            resolution: 240
        )
    }

    private static func twoChannels() -> [BmsonChartMapping.ChannelInput] {
        [
            BmsonChartMapping.ChannelInput(
                name: "kick.wav",
                notes: [BmsonChartMapping.NoteInput(x: 1, y: 0, l: 0, c: false)]
            ),
            BmsonChartMapping.ChannelInput(
                name: "snare.wav",
                notes: [BmsonChartMapping.NoteInput(x: 2, y: 240, l: 0, c: false)]
            )
        ]
    }

    private static func names(_ values: [String]) -> [String] {
        var names = LegacyWavList.emptyNames()
        for (index, value) in values.enumerated() {
            names[index] = value
        }
        return names
    }

    private static func testSelectedObjectsEmptyAndOneNote() {
        let empty = BmsonSelectedObjects.display(notes: [])
        require(empty.message.isEmpty && !empty.lengthEnabled, "empty message")
        require(empty.lengthText.isEmpty && empty.extraText.isEmpty, "empty fields")

        let document = try! BmsONEDocument.fromJSON(selectedObjectsJSON)
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let shown = document.selectedObjectsDisplay(identities: [first])
        require(shown.message == "1 selected note", "one note")
        require(shown.lengthEnabled && shown.lengthText == "240", "length 240")
        require(shown.lengthPlaceholder.isEmpty, "one length placeholder")
        require(shown.extraText == "\"comment\": \"first beat\"", "comment extra")
        require(BmsonSelectedObjects.parseLength("240") == 240, "parse 240")
        require(BmsonSelectedObjects.parseLength("  +240 ") == 240, "parse plus")
        require(BmsonSelectedObjects.parseLength("240abc") == nil, "junk")
        require(BmsonSelectedObjects.parseLength("-1") == nil, "negative")
        require(BmsonSelectedObjects.parseLength("") == nil, "empty length")
    }

    private static func testSelectedObjectsMixedLengthAndExtra() {
        let document = try! BmsONEDocument.fromJSON(selectedObjectsJSON)
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        let shown = document.selectedObjectsDisplay(identities: [first, second])
        require(shown.message == "2 selected notes", "two notes")
        require(shown.lengthText.isEmpty, "mixed length empty")
        require(shown.lengthPlaceholder == "multiple values", "length placeholder")
        require(shown.extraText == "(multiple values)", "extra mixed is text")
        require(BmsonSelectedObjects.isUnchangedMultipleValues("(multiple values)"), "keep mixed extra")
        require(document.applySelectedNoteExtraFields(identities: [first, second], text: "(multiple values)"), "no-op mixed")
        require(document.selectedObjectsDisplay(identities: [first]).extraText == "\"comment\": \"first beat\"", "mixed extra stays")
    }

    private static func testSelectedObjectsRejectsBadLength() {
        let document = try! BmsONEDocument.fromJSON(selectedObjectsJSON)
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.applySelectedNoteLength(identities: [first], text: "nope"), "reject junk")
        require(document.soundChannels[0].notes[0].l == 240, "length unchanged")
        require(!document.canUndo, "reject does not undo")
        require(!document.applySelectedNoteExtraFields(identities: [first], text: "{"), "reject extra")
        require(
            document.selectedObjectsDisplay(identities: [first]).extraText == "\"comment\": \"first beat\"",
            "bad extra stays"
        )
    }

    private static func testSelectedObjectsWritesLengthKeepsExtra() {
        let document = try! BmsONEDocument.fromJSON(selectedObjectsJSON)
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(document.applySelectedNoteLength(identities: [first], text: "480"), "apply length")
        require(document.soundChannels[0].notes[0].l == 480, "wrote length")
        let json = try! document.jsonString()
        require(json.contains("first beat"), "extra still in JSON")
        require(document.undo(), "undo length")
        require(document.soundChannels[0].notes[0].l == 240, "length restored")
    }

    private static func testSelectedObjectsWritesExtraAndUndo() {
        let document = try! BmsONEDocument.fromJSON(selectedObjectsJSON)
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        require(
            document.applySelectedNoteExtraFields(identities: [first, second], text: "\"tag\": 2,"),
            "trailing comma extra"
        )
        require(document.soundChannels[0].notes[0].l == 240, "length stays")
        require(document.soundChannels[0].notes[1].l == 120, "second length stays")
        let json = try! document.jsonString()
        require(json.contains("\"tag\""), "wrote tag")
        require(!json.contains("first beat"), "old extra replaced")
        let shown = document.selectedObjectsDisplay(identities: [first, second])
        require(shown.extraText == "\"tag\": 2", "uniform extra")
        require(document.undo(), "undo extra")
        require(
            document.selectedObjectsDisplay(identities: [first]).extraText == "\"comment\": \"first beat\"",
            "comment back"
        )
    }

    /// 删除夹具短音，一笔撤销回来。
    private static func testFindDeleteShortNoteAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.deleteFindMatches(identities: [identity])
        require(document.soundChannels[0].notes.isEmpty, "deleted short note")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "note back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "same pulse")
    }

    /// 标签 `01`→`02` 是换声道，文件名仍是 `kick.wav`。
    private static func testFindReplaceLabelMovesChannelAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let note = document.soundChannels[0].notes[0]
        try! document.replaceFindLabels(identities: [identity], label: "02")
        require(document.soundChannels.count == 2, "second channel created")
        require(document.soundChannels[0].name == "kick.wav", "name stays on 01")
        require(document.soundChannels[0].notes.isEmpty, "old channel empty")
        require(document.soundChannels[1].notes.count == 1, "moved to 02")
        require(
            document.soundChannels[1].notes[0].x == note.x
                && document.soundChannels[1].notes[0].y == note.y
                && document.soundChannels[1].notes[0].l == note.l
                && document.soundChannels[1].notes[0].c == note.c,
            "x/y/l/c stay"
        )
        require(document.undo(), "one undo")
        require(document.soundChannels.count == 1 && document.soundChannels[0].notes.count == 1, "back on 01")
        require(document.soundChannels[0].name == "kick.wav", "name restored")
    }

    /// 两颗音一次替换，一笔撤销两颗都回去。
    private static func testFindReplaceTwoNotesOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            """
            {"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}
            """
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.replaceFindLabels(identities: [first, second], label: "02")
        require(document.soundChannels[0].notes.isEmpty, "both left 01")
        require(document.soundChannels[1].notes.count == 2, "both on 02")
        require(document.soundChannels[1].notes.contains { $0.x == 1 && $0.y == 0 }, "first kept")
        require(document.soundChannels[1].notes.contains { $0.x == 2 && $0.y == 240 }, "second kept")
        require(document.undo(), "one undo")
        require(document.soundChannels.count == 1, "pad undone")
        require(document.soundChannels[0].notes.count == 2, "both back")
    }

    /// BGA 换标签改事件 `id`。
    private static func testFindReplaceBgaLabelAndUndo() {
        let document = BmsONEDocument.empty()
        try! document.upsertBgaEvent(lane: .bga, pulseY: 240, identifier: 1)
        let identity = BmsonChartMapping.bgaIdentity(lane: .bga, index: 0)
        try! document.replaceFindLabels(identities: [identity], label: "02")
        require(document.bgaEvents.count == 1 && Int(document.bgaEvents[0].identifier) == 2, "id 2")
        require(document.bgaHeaders.contains { Int($0.identifier) == 2 }, "header for 02")
        require(document.undo(), "one undo")
        require(Int(document.bgaEvents[0].identifier) == 1, "id 1 back")
    }

    /// BPM 写 `v`；STOP 输入是 BMS 单位。
    private static func testFindReplaceBpmAndStopAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            """
            {"info":{"initBPM":140,"resolution":240},"bpmNotes":[{"y":240,"v":140}],"stopNotes":[{"y":480,"v":240}]}
            """
        )
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        try! document.replaceFindValues(identities: [bpm], value: 180)
        require(document.bpmNotes.count == 1 && abs(document.bpmNotes[0].v - 180) < 1e-9, "BPM 180")
        require(document.undo(), "undo BPM")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "BPM 140 back")

        let stop = BmsonChartMapping.timingIdentity(isStop: true, index: 0)
        try! document.replaceFindValues(identities: [stop], value: 24)
        require(document.stopNotes.count == 1 && abs(document.stopNotes[0].v - 120) < 1e-9, "24 units at 240 res is 120 pulses")
        require(document.undo(), "undo STOP")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "240 pulses back")
    }

    /// `01`→`03` 会留下空的 `02`。
    private static func testFindReplaceLabelPadsEmptyChannel() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.replaceFindLabels(identities: [identity], label: "03")
        require(document.soundChannels.count == 3, "padded to 03")
        require(document.soundChannels[0].name == "kick.wav" && document.soundChannels[0].notes.isEmpty, "01 name stays")
        require(document.soundChannels[1].name == "" && document.soundChannels[1].notes.isEmpty, "empty 02")
        require(document.soundChannels[2].notes.count == 1, "note on 03")
        require(document.soundChannels[2].notes[0].x == 1 && document.soundChannels[2].notes[0].y == 0, "same x/y")
    }

    /// 夹具短音原位写回：声道 0、`x=1 y=0`，名字和标题、线不动。
    private static func testTimeSelectionRewritesFixtureInPlace() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let title = document.title
        let lineY = document.lines[0].y
        try! document.applyChartNotes([timeNote()], initialBpm: 140)
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.soundChannels[0].notes.count == 1, "one note")
        require(document.soundChannels[0].notes[0].x == 1, "x=1")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].c == false, "c false")
        require(document.title == title, "title stays")
        require(document.lines.count == 1 && document.lines[0].y == lineY, "line stays")
    }

    /// vpos `48` → `y=240`，一笔撤销回到 `y=0`。
    private static func testTimeSelectionMovesPulseAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.applyChartNotes([timeNote(vPosition: 48)], initialBpm: 140)
        require(document.soundChannels[0].notes[0].y == 240, "y=240")
        require(document.soundChannels[0].notes[0].x == 1, "x stays 1")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].y == 0, "y=0 back")
    }

    /// 头 BPM 改 `initBPM`；已有 `y=0` 的 bpmNote 同一笔改，没有则不新造。
    private static func testTimeSelectionHeaderBPMUpdatesStartNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.applyChartNotes([timeNote()], initialBpm: 180)
        require(abs(document.initialBpm - 180) < 1e-9, "initBPM 180")
        require(document.bpmNotes.contains { $0.y == 0 && abs($0.v - 180) < 1e-9 }, "start note 180")
        require(document.undo(), "one undo")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140 back")
        require(document.bpmNotes.contains { $0.y == 0 && abs($0.v - 140) < 1e-9 }, "start note 140 back")

        let empty = BmsONEDocument.empty()
        try! empty.applyChartNotes([], initialBpm: 150)
        require(abs(empty.initialBpm - 150) < 1e-9, "empty initBPM")
        require(empty.bpmNotes.isEmpty, "no new bpmNote")
    }

    /// value `20000` 到第二声道，第一声道名字仍是 `kick.wav`。
    private static func testTimeSelectionMovesToSecondChannel() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.applyChartNotes([timeNote(value: 20_000)], initialBpm: 140)
        require(document.soundChannels.count == 2, "padded to 02")
        require(document.soundChannels[0].name == "kick.wav", "01 name stays")
        require(document.soundChannels[0].notes.isEmpty, "01 empty")
        require(document.soundChannels[1].notes.count == 1, "note on 02")
        require(document.soundChannels[1].notes[0].x == 1 && document.soundChannels[1].notes[0].y == 0, "same x/y")
    }

    /// length `48` → `l=240`。
    private static func testTimeSelectionWritesLongNoteLength() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.applyChartNotes([timeNote(length: 48)], initialBpm: 140)
        require(document.soundChannels[0].notes[0].l == 240, "l=240")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "same x/y")
    }

    /// BGA 列 value `10000`、vpos `48` → `bga_events` `y=240` `id=1`。
    private static func testTimeSelectionWritesBgaEvent() {
        let document = BmsONEDocument.empty()
        try! document.applyChartNotes(
            [timeNote(vPosition: 48, columnIndex: BmsonTimeSelection.bga, value: 10_000)],
            initialBpm: 120
        )
        require(document.bgaEvents.count == 1, "one BGA")
        require(document.bgaEvents[0].y == 240, "y=240")
        require(Int(document.bgaEvents[0].identifier) == 1, "id=1")
        require(document.bgaHeaders.contains { Int($0.identifier) == 1 }, "header for 1")
    }

    /// STOP 显示 48、分辨率 240 → `stopNotes.v == 240`。
    private static func testTimeSelectionWritesStopPulses() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240}}"#
        )
        try! document.applyChartNotes(
            [timeNote(columnIndex: BmsonTimeSelection.stop, value: 480_000)],
            initialBpm: 140
        )
        require(document.stopNotes.count == 1, "one STOP")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "48 units at 240 res is 240 pulses")
    }

    /// 只给 SCROLL 列时不写新音，也不发明 scroll 数组。
    private static func testTimeSelectionSkipsScroll() {
        let document = BmsONEDocument.empty()
        try! document.applyChartNotes(
            [timeNote(columnIndex: BmsonTimeSelection.scroll, value: 10_000)],
            initialBpm: 120
        )
        require(document.soundChannels.isEmpty, "no new sound")
        let json = try! document.jsonString()
        require(!json.contains("scroll"), "no scroll array")
    }

    /// 夹具短音 `x=1` 镜像到 `x=5`，标题 / 线 / BPM / 名字不动。
    private static func testMirrorFixtureShortNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity])
        let note = document.soundChannels[0].notes[0]
        require(note.x == 5, "fixture x=1 -> x=5")
        require(note.y == 0 && note.l == 0 && note.c == false, "y/l/c stay")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.title == "Demo", "title stays")
        require(document.lines[0].y == 240, "line y=240")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140")
    }

    /// 夹具那一笔镜像只 `undo()` 一次就回到 `x=1`。
    private static func testMirrorFixtureShortNoteUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 5, "mirrored")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].x == 1, "x=1 back")
    }

    /// 刮盘 `x=8`（`16`）镜像到 `x=6`（`18`）。
    private static func testMirrorScratchLane() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"scratch.wav","notes":[{"x":8,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 6, "x=8 -> x=6")
    }

    /// 只选 `x=3`（A4）时文档不动，也不记撤销。
    private static func testMirrorCenterKeyDoesNotUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":3,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.mirrorNotes(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 3, "A4 stays")
        require(!document.canUndo, "no undo for A4")
    }

    /// `x=7`（A8，`19`）公式返回 nil，不动。
    private static func testMirrorA8Stays() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":7,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 7, "A8 stays")
        require(!document.canUndo, "no undo for A8")
    }

    /// BGM `x=0` 不镜像。
    private static func testMirrorBGMStays() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":0,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 0, "BGM stays")
        require(!document.canUndo, "no undo for BGM")
    }

    /// 长音只改起点 `x`，`l` 和 extra comment 留下。
    private static func testMirrorLongNoteKeepsLengthAndExtra() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"keep me"}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 5, "long x=1 -> x=5")
        require(document.soundChannels[0].notes[0].l == 240, "length stays")
        let extra = document.selectedObjectsDisplay(identities: [identity]).extraText
        require(extra.contains("keep me"), "comment extra stays")
        let json = try! document.jsonString()
        require(json.contains("keep me"), "comment still in JSON")
    }

    /// `x=1` 与 `x=8` 一次镜像，一笔撤销两颗都回去。
    private static func testMirrorTwoNotesOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":8,"y":240,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let scratch = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.mirrorNotes(identities: [first, scratch])
        require(document.soundChannels[0].notes[0].x == 5, "x=1 -> x=5")
        require(document.soundChannels[0].notes[1].x == 6, "x=8 -> x=6")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].x == 1, "first back")
        require(document.soundChannels[0].notes[1].x == 8, "scratch back")
    }

    /// 同一脉冲 `x=1` 与 `x=5` 对调成功，一笔撤销。
    private static func testMirrorSwapSamePulse() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":5,"y":0,"l":0,"c":false}]}]}"#
        )
        let left = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let right = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        try! document.mirrorNotes(identities: [left, right])
        require(document.soundChannels[0].notes[0].x == 5, "left to x=5")
        require(document.soundChannels[1].notes[0].x == 1, "right to x=1")
        require(document.undo(), "one undo swap")
        require(document.soundChannels[0].notes[0].x == 1, "left back")
        require(document.soundChannels[1].notes[0].x == 5, "right back")
    }

    /// beat-5k 刮盘 `x=8` 目标 `18` 没有车道，不写成 `x=0`，不记撤销。
    private static func testMirrorBeat5kScratchSkipsMissingLane() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"modeHint":"beat-5k","resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":8,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.mirrorNotes(identities: [identity], mode: BmsONEViewMode.resolve("beat-5k"))
        require(document.soundChannels[0].notes[0].x == 8, "5k scratch stays")
        require(document.soundChannels[0].notes[0].x != 0, "not written as BGM")
        require(!document.canUndo, "no undo when dest lane missing")
    }

    /// 未选中的音占着目标车道且脉冲重叠：拒绝，原 `x` 不变，不记撤销。
    private static func testMirrorOccupiedDestinationRejected() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":5,"y":0,"l":0,"c":false}]}]}"#
        )
        let left = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        do {
            try document.mirrorNotes(identities: [left])
            fail("occupied dest must throw")
        } catch {
            let text = error.localizedDescription
            require(text.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels[0].notes[0].x == 1, "left stays")
        require(document.soundChannels[1].notes[0].x == 5, "occupant stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// 只镜像声音音；BPM / STOP / BGA / 线不动。
    private static func testMirrorLeavesTimingBgaAndLines() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"lines":[{"y":240}],"bpmNotes":[{"y":0,"v":140}],"stopNotes":[{"y":240,"v":240}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}],"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":240,"id":1}]}}"#
        )
        let sound = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        let stop = BmsonChartMapping.timingIdentity(isStop: true, index: 0)
        let bga = BmsonChartMapping.bgaIdentity(lane: .bga, index: 0)
        try! document.mirrorNotes(identities: [sound, bpm, stop, bga])
        require(document.soundChannels[0].notes[0].x == 5, "sound mirrored")
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 0, "bpm y")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "bpm v")
        require(document.stopNotes.count == 1 && document.stopNotes[0].y == 240, "stop y")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "stop v")
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 240, "bga y")
        require(document.bgaEvents[0].identifier == 1, "bga id")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
    }

    /// 夹具短音按 `4`：`toDisplay "13"` 后 `x=1` → `x=3`，标题 / 线 / BPM / 名字不动。
    private static func testMoveDigitFixtureShortNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotes(identities: [identity], toDisplay: "13", shiftFirstOnly: false)
        let note = document.soundChannels[0].notes[0]
        require(note.x == 3, "fixture x=1 -> x=3")
        require(note.y == 0 && note.l == 0 && note.c == false, "y/l/c stay")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.title == "Demo", "title stays")
        require(document.lines[0].y == 240, "line y=240")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140")
    }

    /// 夹具那一笔搬列只 `undo()` 一次就回到 `x=1`。
    private static func testMoveDigitFixtureShortNoteUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotes(identities: [identity], toDisplay: "13", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 3, "moved")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].x == 1, "x=1 back")
    }

    /// 数字 `1`：显示 `16`，`x=1` → `x=8`。
    private static func testMoveDigitScratchLane() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotes(identities: [identity], toDisplay: "16", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 8, "x=1 -> x=8")
    }

    /// 数字 `7`：显示 `18`，`x=1` → `x=6`。
    private static func testMoveDigitSeven() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotes(identities: [identity], toDisplay: "18", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 6, "x=1 -> x=6")
    }

    /// 只选 `x=3`、`toDisplay "13"`：不动，不记撤销。
    private static func testMoveDigitAlreadyOnTargetDoesNotUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":3,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.moveNotes(identities: [identity], toDisplay: "13", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 3, "already on 13")
        require(!document.canUndo, "no undo when already on target")
    }

    /// `x=1 y=0` 与 `x=2 y=240` 一次搬到 `x=3`，一笔撤销两颗都回去。
    private static func testMoveDigitTwoNotesOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.moveNotes(identities: [first, second], toDisplay: "13", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 3, "y=0 to x=3")
        require(document.soundChannels[0].notes[1].x == 3, "y=240 to x=3")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].x == 1, "first back")
        require(document.soundChannels[0].notes[1].x == 2, "second back")
    }

    /// Shift 只搬最早：只有 `y=0` 到 `x=3`，`y=240` 仍是 `x=2`。
    private static func testMoveDigitShiftMovesEarliestOnly() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.moveNotes(identities: [second, first], toDisplay: "13", shiftFirstOnly: true)
        require(document.soundChannels[0].notes[0].x == 3, "earliest y=0 moves")
        require(document.soundChannels[0].notes[1].x == 2, "later y=240 stays")
    }

    /// 长音只改 `x`，`l` 和 extra comment 留下。
    private static func testMoveDigitLongNoteKeepsLengthAndExtra() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"keep me"}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotes(identities: [identity], toDisplay: "13", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 3, "long x=1 -> x=3")
        require(document.soundChannels[0].notes[0].l == 240, "length stays")
        let extra = document.selectedObjectsDisplay(identities: [identity]).extraText
        require(extra.contains("keep me"), "comment extra stays")
        let json = try! document.jsonString()
        require(json.contains("keep me"), "comment still in JSON")
    }

    /// 数字 `0`：`x=1 l=240` → `x=0`，不清除长度。
    private static func testMoveDigitZeroToBGMKeepsLength() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotesToBGM(identities: [identity])
        require(document.soundChannels[0].notes[0].x == 0, "x=1 -> x=0")
        require(document.soundChannels[0].notes[0].l == 240, "length stays on BGM")
    }

    /// 两颗不同声道同一脉冲按 `0` 都变成 `x=0`，一笔撤销。
    private static func testMoveDigitZeroTwoChannelsSamePulse() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":2,"y":0,"l":0,"c":false}]}]}"#
        )
        let left = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let right = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        try! document.moveNotesToBGM(identities: [left, right])
        require(document.soundChannels[0].notes[0].x == 0, "left to BGM")
        require(document.soundChannels[1].notes[0].x == 0, "right to BGM")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].x == 1, "left back")
        require(document.soundChannels[1].notes[0].x == 2, "right back")
    }

    /// beat-5k 目标 `19` 没有车道：整次不搬，不写成 `x=0`，不记撤销。
    private static func testMoveDigitBeat5kMissingLaneDoesNotMove() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"modeHint":"beat-5k","resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotes(
            identities: [identity],
            toDisplay: "19",
            shiftFirstOnly: false,
            mode: BmsONEViewMode.resolve("beat-5k")
        )
        require(document.soundChannels[0].notes[0].x == 1, "5k x=1 stays")
        require(document.soundChannels[0].notes[0].x != 0, "not written as BGM")
        require(!document.canUndo, "no undo when dest lane missing")
    }

    /// 未选中的音占着目标可玩车道且脉冲重叠：拒绝，原 `x` 不变，不记撤销。
    private static func testMoveDigitOccupiedDestinationRejected() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":3,"y":0,"l":0,"c":false}]}]}"#
        )
        let left = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        do {
            try document.moveNotes(identities: [left], toDisplay: "13", shiftFirstOnly: false)
            fail("occupied dest must throw")
        } catch {
            let text = error.localizedDescription
            require(text.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels[0].notes[0].x == 1, "left stays")
        require(document.soundChannels[1].notes[0].x == 3, "occupant stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// 两颗选中音同一脉冲搬到同一可玩列：拒绝 `Overlapping notes`。
    private static func testMoveDigitTwoSelectedSamePulseRejected() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":2,"y":0,"l":0,"c":false}]}]}"#
        )
        let left = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let right = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        do {
            try document.moveNotes(identities: [left, right], toDisplay: "13", shiftFirstOnly: false)
            fail("same-pulse dest must throw")
        } catch {
            let text = error.localizedDescription
            require(text.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels[0].notes[0].x == 1, "left stays")
        require(document.soundChannels[1].notes[0].x == 2, "right stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// 只搬声音音；BPM / STOP / BGA / 线不动。
    private static func testMoveDigitLeavesTimingBgaAndLines() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"lines":[{"y":240}],"bpmNotes":[{"y":0,"v":140}],"stopNotes":[{"y":240,"v":240}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}],"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":240,"id":1}]}}"#
        )
        let sound = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        let stop = BmsonChartMapping.timingIdentity(isStop: true, index: 0)
        let bga = BmsonChartMapping.bgaIdentity(lane: .bga, index: 0)
        try! document.moveNotes(identities: [sound, bpm, stop, bga], toDisplay: "13", shiftFirstOnly: false)
        require(document.soundChannels[0].notes[0].x == 3, "sound moved")
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 0, "bpm y")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "bpm v")
        require(document.stopNotes.count == 1 && document.stopNotes[0].y == 240, "stop y")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "stop v")
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 240, "bga y")
        require(document.bgaEvents[0].identifier == 1, "bga id")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
    }

    /// 夹具短音改标签 `A` → `0A`，音到声道下标 9；名字 / 标题 / 线 / BPM 不动。
    private static func testModifyNotesFixtureLabelA() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let token = ChartConvert.modifyLabel("A")
        require(token == "0A", "A -> 0A")
        try! document.modifyNotes(
            valueIdentities: [],
            value: nil,
            labelIdentities: [identity],
            label: token
        )
        require(document.soundChannels.count >= 10, "padded to 0A")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.soundChannels[0].notes.isEmpty, "left channel 0")
        require(document.soundChannels[9].notes.count == 1, "note on index 9")
        require(
            document.soundChannels[9].notes[0].x == 1
                && document.soundChannels[9].notes[0].y == 0
                && document.soundChannels[9].notes[0].l == 0
                && document.soundChannels[9].notes[0].c == false,
            "x=1 y=0 l=0 c=false"
        )
        require(document.title == "Demo", "title stays")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line y=240")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140")
    }

    /// 上面那笔 `undo()` 一次回到声道 0、`x=1`。
    private static func testModifyNotesFixtureLabelAUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.modifyNotes(
            valueIdentities: [],
            value: nil,
            labelIdentities: [identity],
            label: ChartConvert.modifyLabel("A")
        )
        require(document.soundChannels[9].notes.count == 1, "moved")
        require(document.undo(), "one undo")
        require(document.soundChannels.count == 1, "pad undone")
        require(document.soundChannels[0].notes.count == 1, "back on 01")
        require(document.soundChannels[0].notes[0].x == 1, "x=1 back")
        require(document.soundChannels[0].name == "kick.wav", "name restored")
    }

    /// 标签 `03` 后共 3 个声道，中间 `02` 名字为空。
    private static func testModifyNotesPadsEmptyChannel() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.modifyNotes(
            valueIdentities: [],
            value: nil,
            labelIdentities: [identity],
            label: ChartConvert.modifyLabel("03")
        )
        require(document.soundChannels.count == 3, "padded to 03")
        require(document.soundChannels[0].name == "kick.wav" && document.soundChannels[0].notes.isEmpty, "01 name stays")
        require(document.soundChannels[1].name == "" && document.soundChannels[1].notes.isEmpty, "empty 02")
        require(document.soundChannels[2].notes.count == 1, "note on 03")
        require(document.soundChannels[2].notes[0].x == 1 && document.soundChannels[2].notes[0].y == 0, "same x/y")
    }

    /// 长音换到 `02` 后 `l` 仍 `240`，extra comment 留下。
    private static func testModifyNotesLongNoteKeepsLengthAndExtra() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"keep me"}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.modifyNotes(
            valueIdentities: [],
            value: nil,
            labelIdentities: [identity],
            label: ChartConvert.modifyLabel("02")
        )
        require(document.soundChannels[0].notes.isEmpty, "left 01")
        require(document.soundChannels[1].notes.count == 1, "on 02")
        require(document.soundChannels[1].notes[0].l == 240, "length stays")
        let dest = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        let extra = document.selectedObjectsDisplay(identities: [dest]).extraText
        require(extra.contains("keep me"), "comment extra stays")
        let json = try! document.jsonString()
        require(json.contains("keep me"), "comment still in JSON")
    }

    /// BGA 改事件 `id` 1→2，可撤销。
    private static func testModifyNotesBgaIdAndUndo() {
        let document = BmsONEDocument.empty()
        try! document.upsertBgaEvent(lane: .bga, pulseY: 240, identifier: 1)
        let identity = BmsonChartMapping.bgaIdentity(lane: .bga, index: 0)
        try! document.modifyNotes(
            valueIdentities: [],
            value: nil,
            labelIdentities: [identity],
            label: ChartConvert.modifyLabel("02")
        )
        require(document.bgaEvents.count == 1 && Int(document.bgaEvents[0].identifier) == 2, "id 2")
        require(document.undo(), "one undo")
        require(Int(document.bgaEvents[0].identifier) == 1, "id 1 back")
    }

    /// BPM `y=240 v=140` 改成 `180`，可撤销。
    private static func testModifyNotesBpmAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240},"bpmNotes":[{"y":240,"v":140}]}"#
        )
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        try! document.modifyNotes(
            valueIdentities: [bpm],
            value: 180,
            labelIdentities: [],
            label: nil
        )
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 240, "y stays")
        require(abs(document.bpmNotes[0].v - 180) < 1e-9, "BPM 180")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        require(document.undo(), "undo BPM")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "BPM 140 back")
    }

    /// STOP 显示 48、分辨率 240 存 `v=240`；改成 `24` 后 `v=120`。
    private static func testModifyNotesStopPulses() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240},"stopNotes":[{"y":480,"v":240}]}"#
        )
        require(document.stopNotes.count == 1 && abs(document.stopNotes[0].v - 240) < 1e-9, "48 units stored as 240")
        let stop = BmsonChartMapping.timingIdentity(isStop: true, index: 0)
        try! document.modifyNotes(
            valueIdentities: [stop],
            value: 24,
            labelIdentities: [],
            label: nil
        )
        require(abs(document.stopNotes[0].v - 120) < 1e-9, "24 units at 240 res is 120 pulses")
        require(document.undo(), "undo STOP")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "240 pulses back")
    }

    /// 只给解不出的 SCROLL 身份：不发明 scroll 数组，声音音不动。
    private static func testModifyNotesSkipsScroll() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.modifyNotes(
            valueIdentities: [0],
            value: 0.5,
            labelIdentities: [],
            label: nil
        )
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes.count == 1, "sound stays")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "same x/y")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        let json = try! document.jsonString()
        require(!json.contains("scroll"), "no scroll array")
        require(!document.canUndo, "no undo when nothing written")
        try! document.modifyNotes(
            valueIdentities: [identity],
            value: 0.5,
            labelIdentities: [],
            label: nil
        )
        require(document.soundChannels[0].notes.count == 1, "sound identity as value still skipped")
        require(!json.contains("scroll") && !(try! document.jsonString()).contains("scroll"), "still no scroll")
        require(!document.canUndo, "resolve skip does not undo")
    }

    /// 同一谱既改 BPM 又改声音标签：`undo()` 一次只回一档，两次才全部回去。
    private static func testModifyNotesValueAndLabelTwoUndos() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240},"bpmNotes":[{"y":240,"v":140}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let sound = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        try! document.modifyNotes(
            valueIdentities: [bpm],
            value: 180,
            labelIdentities: [sound],
            label: ChartConvert.modifyLabel("02")
        )
        require(abs(document.bpmNotes[0].v - 180) < 1e-9, "BPM 180")
        require(document.soundChannels[0].notes.isEmpty, "left 01")
        require(document.soundChannels[1].notes.count == 1, "sound on 02")
        require(document.undo(), "first undo")
        require(abs(document.bpmNotes[0].v - 180) < 1e-9, "BPM still 180")
        require(document.soundChannels.count == 1 && document.soundChannels[0].notes.count == 1, "sound back")
        require(document.undo(), "second undo")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "BPM 140 back")
        require(document.soundChannels[0].notes[0].x == 1, "x stays")
    }

    /// 只传数值、标签身份为空：不换声道。
    private static func testModifyNotesEmptyLabelIdentitiesDoesNotMoveChannel() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240},"bpmNotes":[{"y":240,"v":140}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        try! document.modifyNotes(
            valueIdentities: [bpm],
            value: 180,
            labelIdentities: [],
            label: ChartConvert.modifyLabel("02")
        )
        require(abs(document.bpmNotes[0].v - 180) < 1e-9, "BPM 180")
        require(document.soundChannels.count == 1, "no pad")
        require(document.soundChannels[0].notes.count == 1, "sound stays on 01")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// 两颗音一次改标签到 `02`，一笔撤销两颗都回去。
    private static func testModifyNotesTwoNotesOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.modifyNotes(
            valueIdentities: [],
            value: nil,
            labelIdentities: [first, second],
            label: ChartConvert.modifyLabel("02")
        )
        require(document.soundChannels[0].notes.isEmpty, "both left 01")
        require(document.soundChannels[1].notes.count == 2, "both on 02")
        require(document.soundChannels[1].notes.contains { $0.x == 1 && $0.y == 0 }, "first kept")
        require(document.soundChannels[1].notes.contains { $0.x == 2 && $0.y == 240 }, "second kept")
        require(document.undo(), "one undo")
        require(document.soundChannels.count == 1, "pad undone")
        require(document.soundChannels[0].notes.count == 2, "both back")
    }

    /// 同一声道 `x=1 y=0` 与 `x=1 y=240` 配成长音：只剩一颗，`y=0 l=240`，`c` / 名字不动。
    private static func testConvertShortPairToLongSameChannel() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":1,"y":240,"l":0,"c":false}]}]}"#
        )
        let start = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let end = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.convertShortPairToLong(startIdentity: start, endIdentity: end)
        require(document.resolution == 240, "resolution 240")
        require(document.soundChannels[0].notes.count == 1, "one note left")
        require(document.soundChannels[0].notes[0].x == 1, "x stays")
        require(document.soundChannels[0].notes[0].y == 0, "earlier y stays")
        require(document.soundChannels[0].notes[0].l == 240, "l = 240")
        require(document.soundChannels[0].notes[0].c == false, "c stays")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// 上面那笔 `undo()` 一次回到两颗短音。
    private static func testConvertShortPairToLongUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":1,"y":240,"l":0,"c":false}]}]}"#
        )
        let start = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let end = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.convertShortPairToLong(startIdentity: start, endIdentity: end)
        require(document.soundChannels[0].notes.count == 1, "paired")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 2, "two shorts back")
        require(document.soundChannels[0].notes.contains { $0.x == 1 && $0.y == 0 && $0.l == 0 }, "start back")
        require(document.soundChannels[0].notes.contains { $0.x == 1 && $0.y == 240 && $0.l == 0 }, "end back")
    }

    /// 夹具单颗短音走不成对路径：仍是 `x=1 y=0 l=0`，不记撤销。
    private static func testConvertUnpairedShortStays() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        document.convertShortNoteToLongEndpoint(identity: identity)
        require(document.soundChannels[0].notes.count == 1, "still one")
        require(
            document.soundChannels[0].notes[0].x == 1
                && document.soundChannels[0].notes[0].y == 0
                && document.soundChannels[0].notes[0].l == 0,
            "x=1 y=0 l=0"
        )
        require(!document.canUndo, "unpaired does not undo")
    }

    /// 不同声道同一车道：留下声道 0 的 `l=240`，声道 1 那颗删掉。
    private static func testConvertShortPairToLongDifferentChannelsSameLane() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":1,"y":240,"l":0,"c":false}]}]}"#
        )
        let start = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let end = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        try! document.convertShortPairToLong(startIdentity: start, endIdentity: end)
        require(document.soundChannels[0].notes.count == 1, "start stays")
        require(document.soundChannels[0].notes[0].l == 240, "channel 0 l=240")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "x/y stay")
        require(document.soundChannels[0].name == "a.wav", "name stays")
        require(document.soundChannels[1].notes.isEmpty, "channel 1 deleted")
    }

    /// `x` 不同不配：都不动，不记撤销。
    private static func testConvertShortPairDifferentXDoesNotWrite() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}"#
        )
        let start = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let end = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        require(!document.canUndo, "open has no history")
        try! document.convertShortPairToLong(startIdentity: start, endIdentity: end)
        require(document.soundChannels[0].notes.count == 2, "both stay")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].l == 0, "x=1 stays")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].l == 0, "x=2 stays")
        require(!document.canUndo, "no undo when x differs")
    }

    /// NT → Short：`l=240` 加 comment 后 `l=0`，仍一颗，extra 还在。
    private static func testConvertLongToShortNTKeepsStart() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"keep me"}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.convertLongToShort(identity: identity, keepEnd: false)
        require(document.soundChannels[0].notes.count == 1, "still one")
        require(document.soundChannels[0].notes[0].l == 0, "l=0")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "x/y stay")
        let extra = document.selectedObjectsDisplay(identities: [identity]).extraText
        require(extra.contains("keep me"), "comment extra stays")
        let json = try! document.jsonString()
        require(json.contains("keep me"), "comment still in JSON")
    }

    /// BMSE → Short：原位 `l=0`，同一声道同一 `x` 在 `y=240` 多一颗 `l=0`；一次撤销两颗都回去。
    private static func testConvertLongToShortBMSEInsertsEnd() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.convertLongToShort(identity: identity, keepEnd: true)
        require(document.soundChannels[0].notes.count == 2, "start plus end")
        require(document.soundChannels[0].notes.contains { $0.x == 1 && $0.y == 0 && $0.l == 0 }, "start short")
        require(document.soundChannels[0].notes.contains { $0.x == 1 && $0.y == 240 && $0.l == 0 && $0.c == false }, "end short")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "one long back")
        require(document.soundChannels[0].notes[0].y == 0 && document.soundChannels[0].notes[0].l == 240, "l=240 back")
    }

    /// 已经是短音 → Short：不写、不记撤销。
    private static func testConvertAlreadyShortDoesNotWrite() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.convertLongToShort(identity: identity, keepEnd: true)
        require(document.soundChannels[0].notes.count == 1, "still one")
        require(document.soundChannels[0].notes[0].l == 0, "still short")
        require(!document.canUndo, "no undo for already short")
    }

    /// 未选中占用区间：`y=0` 与 `y=480` 要配、中间 `y=240` 有未选中同 `x` 音则拒绝。
    private static func testConvertShortPairOccupiedIntervalRejected() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":1,"y":240,"l":0,"c":false},{"x":1,"y":480,"l":0,"c":false}]}]}"#
        )
        let start = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let end = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 2)
        do {
            try document.convertShortPairToLong(startIdentity: start, endIdentity: end)
            fail("occupied interval must throw")
        } catch {
            let text = error.localizedDescription
            require(text.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels[0].notes.count == 3, "all three stay")
        require(document.soundChannels[0].notes.contains { $0.y == 0 && $0.l == 0 }, "y=0 stays")
        require(document.soundChannels[0].notes.contains { $0.y == 240 && $0.l == 0 }, "y=240 stays")
        require(document.soundChannels[0].notes.contains { $0.y == 480 && $0.l == 0 }, "y=480 stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// 带 `bpmNotes` / `bga` / `lines` 的谱只改声音音。
    private static func testConvertLeavesTimingBgaAndLines() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"lines":[{"y":240}],"bpmNotes":[{"y":0,"v":140}],"stopNotes":[{"y":240,"v":240}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":1,"y":240,"l":0,"c":false}]}],"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":240,"id":1}]}}"#
        )
        let start = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let end = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.convertShortPairToLong(startIdentity: start, endIdentity: end)
        require(document.soundChannels[0].notes.count == 1, "one long")
        require(document.soundChannels[0].notes[0].l == 240, "l=240")
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 0, "bpm y")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "bpm v")
        require(document.stopNotes.count == 1 && document.stopNotes[0].y == 240, "stop y")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "stop v")
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 240, "bga y")
        require(document.bgaEvents[0].identifier == 1, "bga id")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        require(document.title == "Demo", "title stays")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// 菜单 Hidden 不改夹具：仍是 `x=1 y=0 l=0 c=false`，不记撤销，不发明 `31`。
    private static func testConvertHiddenFixtureDoesNotChange() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.convertHiddenNotes(identities: [identity], action: .hide)
        let note = document.soundChannels[0].notes[0]
        require(note.x == 1, "fixture x stays 1")
        require(note.x != 0, "not written as x=0")
        require(note.y == 0 && note.l == 0 && note.c == false, "y/l/c stay")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.title == "Demo", "title stays")
        require(document.lines[0].y == 240, "line y=240")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140")
        require(!document.canUndo, "hide skip does not undo")
        let json = try! document.jsonString()
        require(!json.contains("\"31\""), "no 31 channel")
        require(!json.contains("hidden"), "no hidden key")
    }

    /// Visible 已可见：同一夹具 `.show` 不写、不记撤销。
    private static func testConvertVisibleAlreadyVisibleDoesNotWrite() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.convertHiddenNotes(identities: [identity], action: .show)
        require(document.soundChannels[0].notes[0].x == 1, "x stays 1")
        require(document.soundChannels[0].notes[0].y == 0 && document.soundChannels[0].notes[0].l == 0, "y/l stay")
        require(!document.canUndo, "show skip does not undo")
    }

    /// Toggle 不写成 `x=0`：同一夹具 `.toggle` 仍是 `x=1`，不记撤销。
    private static func testConvertToggleDoesNotWriteX0() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.convertHiddenNotes(identities: [identity], action: .toggle)
        require(document.soundChannels[0].notes[0].x == 1, "toggle stays x=1")
        require(document.soundChannels[0].notes[0].x != 0, "not written as x=0")
        require(!document.canUndo, "toggle skip does not undo")
    }

    /// `convertNote` 到 `31` 不写 `x=0`，不记撤销。
    private static func testConvertNoteTo31DoesNotWriteX0() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        require(!document.canUndo, "open has no history")
        try! document.convertNote(identity: identity, toChannel: "31")
        require(document.soundChannels[0].notes[0].x == 1, "31 skip stays x=1")
        require(document.soundChannels[0].notes[0].x != 0, "not written as x=0")
        require(!document.canUndo, "31 skip does not undo")
    }

    /// `convertNote` 到可见列 `13`：`x=1` → `x=3`，一笔撤销回到 `x=1`。
    private static func testConvertNoteToVisibleLaneAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.convertNote(identity: identity, toChannel: "13")
        let note = document.soundChannels[0].notes[0]
        require(note.x == 3, "x=1 -> x=3")
        require(note.y == 0 && note.l == 0 && note.c == false, "y/l/c stay")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.title == "Demo", "title stays")
        require(document.lines[0].y == 240, "line y=240")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes[0].x == 1, "x=1 back")
    }

    /// 长音加 extra：`toChannel: "13"` 后 `x=3`，`l` 仍 `240`，comment 留下。
    private static func testConvertNoteLongKeepsLengthAndExtra() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"keep me"}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.convertNote(identity: identity, toChannel: "13")
        require(document.soundChannels[0].notes[0].x == 3, "long x=1 -> x=3")
        require(document.soundChannels[0].notes[0].l == 240, "length stays")
        require(document.soundChannels[0].notes[0].y == 0 && document.soundChannels[0].notes[0].c == false, "y/c stay")
        let extra = document.selectedObjectsDisplay(identities: [identity]).extraText
        require(extra.contains("keep me"), "comment extra stays")
        let json = try! document.jsonString()
        require(json.contains("keep me"), "comment still in JSON")
    }

    /// beat-5k 缺车道：`toChannel: "19"` 仍是 `x=1`，不写成 `x=0`。
    private static func testConvertNoteBeat5kMissingLaneDoesNotWriteX0() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"modeHint":"beat-5k","resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.convertNote(
            identity: identity,
            toChannel: "19",
            mode: BmsONEViewMode.resolve("beat-5k")
        )
        require(document.soundChannels[0].notes[0].x == 1, "5k missing 19 stays")
        require(document.soundChannels[0].notes[0].x != 0, "not written as BGM")
        require(!document.canUndo, "no undo when dest lane missing")
    }

    /// 未选中的音占着目标列同一脉冲：拒绝，原 `x` 不变。
    private static func testConvertNoteOccupiedDestinationRejected() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":3,"y":0,"l":0,"c":false}]}]}"#
        )
        let left = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        do {
            try document.convertNote(identity: left, toChannel: "13")
            fail("occupied dest must throw")
        } catch {
            let text = error.localizedDescription
            require(text.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels[0].notes[0].x == 1, "left stays")
        require(document.soundChannels[1].notes[0].x == 3, "occupant stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// Hidden 或 `toChannel: "31"` 之后时值 / BGA / 线不动。负 identity 不写。
    private static func testConvertHiddenLeavesTimingBgaAndLines() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"lines":[{"y":240}],"bpmNotes":[{"y":0,"v":140}],"stopNotes":[{"y":240,"v":240}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}],"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":240,"id":1}]}}"#
        )
        let sound = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let bpm = BmsonChartMapping.timingIdentity(isStop: false, index: 0)
        let stop = BmsonChartMapping.timingIdentity(isStop: true, index: 0)
        let bga = BmsonChartMapping.bgaIdentity(lane: .bga, index: 0)
        try! document.convertHiddenNotes(identities: [sound, bpm, stop, bga], action: .hide)
        try! document.convertNote(identity: sound, toChannel: "31")
        try! document.convertNote(identity: -1, toChannel: "13")
        try! document.convertNote(identity: bpm, toChannel: "13")
        require(document.soundChannels[0].notes[0].x == 1, "sound stays")
        require(document.soundChannels[0].notes[0].x != 0, "not written as x=0")
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 0, "bpm y")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "bpm v")
        require(document.stopNotes.count == 1 && document.stopNotes[0].y == 240, "stop y")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "stop v")
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 240, "bga y")
        require(document.bgaEvents[0].identifier == 1, "bga id")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        require(!document.canUndo, "timing skip does not undo")
    }

    /// 两颗可见音 Hidden 一笔也不记：都不动，`canUndo == false`。
    private static func testConvertHiddenTwoNotesDoesNotUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        require(!document.canUndo, "open has no history")
        try! document.convertHiddenNotes(identities: [first, second], action: .hide)
        require(document.soundChannels[0].notes[0].x == 1, "first stays")
        require(document.soundChannels[0].notes[1].x == 2, "second stays")
        require(document.soundChannels[0].notes[0].x != 0 && document.soundChannels[0].notes[1].x != 0, "not x=0")
        require(!document.canUndo, "two hide skips do not undo")
    }

    /// 夹具短音 identity 0（声道 0 第 0 颗）复制成 BMSE 一行。NT 关。
    private static func testCopyClipboardFixtureShortNote() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let text = document.copyClipboard(identities: [0], ntInput: false)
        require(text == "iBMSC Clipboard Data\r\n6 0 10000 0 0 0", "copy fixture short")
    }

    /// 空谱粘贴短音：声道 0、`x=1 y=0 l=0`，一笔撤销清空。
    private static func testPasteClipboardShortNoteEmptyAndUndo() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes.count == 1, "one note")
        require(document.soundChannels[0].notes[0].x == 1, "x=1")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].l == 0, "l=0")
        require(document.soundChannels[0].notes[0].c == false, "c false")
        require(document.undo(), "one undo")
        require(document.soundChannels.isEmpty, "empty after undo")
    }

    /// 夹具已有 `x=1 y=0`。再粘 `02` 到 vpos 48：原音留下，新音追加。
    private static func testPasteClipboardAppendsWithoutReplacingFixture() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let title = document.title
        let lineY = document.lines[0].y
        let initBPM = document.initialBpm
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n6 48 20000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.soundChannels.count == 2, "padded to 02")
        require(document.soundChannels[0].name == "kick.wav", "01 name stays")
        require(document.soundChannels[0].notes.count == 1, "original stays")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture x/y")
        require(document.soundChannels[1].notes.count == 1, "new note")
        require(document.soundChannels[1].notes[0].x == 1 && document.soundChannels[1].notes[0].y == 240, "new x=1 y=240")
        require(document.title == title, "title stays")
        require(document.lines.count == 1 && document.lines[0].y == lineY, "line stays")
        require(abs(document.initialBpm - initBPM) < 1e-9, "initBPM stays")
        require(document.undo(), "one undo")
        require(document.soundChannels.count == 1, "one channel back")
        require(document.soundChannels[0].notes.count == 1, "only fixture note")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture back")
        require(document.soundChannels[0].name == "kick.wav", "name back")
    }

    /// Hidden 行当成可见列普通音，不写成 `x=0`，JSON 无 `"31"`。
    private static func testPasteClipboardHiddenIsVisibleLane() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n6 0 10000 0 -1 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes[0].x == 1, "Hidden -> x=1")
        require(document.soundChannels[0].notes[0].x != 0, "not BGM")
        let json = try! document.jsonString()
        require(!json.contains("\"31\""), "no 31 channel")
    }

    /// NT 长音 length 48 → `l=240`，不发明第二颗音。
    private static func testPasteClipboardNTLongNote() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data xNT\r\n6 0 10000 48 0 0",
            baseVPosition: 0,
            ntInput: true
        )
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes.count == 1, "one long note")
        require(document.soundChannels[0].notes[0].x == 1, "x=1")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].l == 240, "l=240")
    }

    /// BPM 列写 `bpmNotes`，声音音不增。
    private static func testPasteClipboardBPM() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n2 0 1400000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.soundChannels.isEmpty, "no sound")
        require(document.bpmNotes.count == 1, "one BPM")
        require(document.bpmNotes[0].y == 0, "y=0")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "v=140")
    }

    /// STOP 显示 48、分辨率 240 → `stopNotes.v == 240`。
    private static func testPasteClipboardStop() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240}}"#
        )
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n3 0 480000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.stopNotes.count == 1, "one STOP")
        require(document.stopNotes[0].y == 0, "y=0")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "48 units at 240 res is 240 pulses")
        require(document.soundChannels.isEmpty, "no sound")
    }

    /// SCROLL 不写声音音，也不发明 scroll 数组。
    private static func testPasteClipboardSkipsScroll() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n1 0 5000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.soundChannels.isEmpty, "no new sound")
        require(!document.canUndo, "skip does not undo")
        let json = try! document.jsonString()
        require(!json.contains("scroll"), "no scroll array")
    }

    /// 列 23、value `10000` → `bga_events` `y=0 id=1`。
    private static func testPasteClipboardBga() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n23 0 10000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.bgaEvents.count == 1, "one BGA")
        require(document.bgaEvents[0].y == 0, "y=0")
        require(Int(document.bgaEvents[0].identifier) == 1, "id=1")
        require(document.soundChannels.isEmpty, "no sound")
    }

    /// 夹具 `x=1 y=0` 再粘同一格 → `Overlapping notes`，谱不动，不记撤销。
    private static func testPasteClipboardOccupiedRejected() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        do {
            try document.pasteClipboard(
                "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
                baseVPosition: 0,
                ntInput: false
            )
            fail("occupied paste must throw")
        } catch {
            require(error.localizedDescription.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes.count == 1, "one note")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture stays")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// beat-5k 没有 A8（通道 `19`）车道：不写，不写成 `x=0`。
    private static func testPasteClipboardBeat5kMissingLaneDoesNotWriteX0() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n12 0 10000 0 0 0",
            baseVPosition: 0,
            ntInput: false,
            mode: BmsONEViewMode(kind: .beat5k)
        )
        require(document.soundChannels.isEmpty, "A8 skipped")
        require(!document.canUndo, "missing lane does not undo")
        let json = try! document.jsonString()
        require(!json.contains("\"x\":0") && !json.contains("\"x\": 0"), "not written as x=0")
    }

    /// BGM 列 27 写成 `x=0`。
    private static func testPasteClipboardBGMWritesX0() {
        let document = BmsONEDocument.empty()
        try! document.pasteClipboard(
            "iBMSC Clipboard Data\r\n27 0 10000 0 0 0",
            baseVPosition: 0,
            ntInput: false
        )
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes[0].x == 0, "BGM x=0")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].l == 0, "l=0")
    }

    /// 夹具短音复制到 `12`、vpos `0`：原音留下，新音 `x=2 y=0`，一笔撤销。
    private static func testDuplicateNotesFixtureShortSamePulseAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.duplicateNotes([
            (channel: "12", vPosition: 0, token: "01", length: 0)
        ])
        require(document.soundChannels.count == 1, "same channel")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.soundChannels[0].notes.count == 2, "original plus copy")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "original")
        require(document.soundChannels[0].notes[0].l == 0, "original short")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 0, "copy x=2 y=0")
        require(document.soundChannels[0].notes[1].l == 0, "copy short")
        require(document.title == "Demo", "title stays")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        require(document.undo(), "one undo")
        require(document.soundChannels.count == 1, "one channel back")
        require(document.soundChannels[0].notes.count == 1, "only fixture")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture back")
        require(document.soundChannels[0].name == "kick.wav", "name back")
    }

    /// 同一夹具复制到 `12`、vpos `48` → 新音 `x=2 y=240`。
    private static func testDuplicateNotesFixtureShortToVpos48() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.duplicateNotes([
            (channel: "12", vPosition: 48, token: "01", length: 0)
        ])
        require(document.soundChannels[0].notes.count == 2, "original plus copy")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "original stays")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 240, "copy y=240")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// Hidden 目标通道 `31` 写成可见列 `x=1`，JSON 无 `"31"`。
    private static func testDuplicateNotesHiddenWritesVisibleLane() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.duplicateNotes([
            (channel: "31", vPosition: 48, token: "01", length: 0)
        ])
        require(document.soundChannels[0].notes.count == 2, "original plus copy")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "original")
        require(document.soundChannels[0].notes[1].x == 1, "Hidden -> visible x=1")
        require(document.soundChannels[0].notes[1].x != 0, "not BGM")
        require(document.soundChannels[0].notes[1].y == 240, "copy y=240")
        let json = try! document.jsonString()
        require(!json.contains("\"31\""), "no 31 channel")
    }

    /// NT 长音 length 48 → 一颗 `l=240`，不发明 `5x`。
    private static func testDuplicateNotesNTLongNote() {
        let document = BmsONEDocument.empty()
        try! document.duplicateNotes([
            (channel: "12", vPosition: 0, token: "01", length: 48)
        ])
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes.count == 1, "one long note")
        require(document.soundChannels[0].notes[0].x == 2, "x=2")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].l == 240, "l=240")
        let json = try! document.jsonString()
        require(!json.contains("\"51\"") && !json.contains("5x"), "no 5x")
    }

    /// 通道 `03`、token `140` → `bpmNotes`，声音音不增。
    private static func testDuplicateNotesBPM() {
        let document = BmsONEDocument.empty()
        try! document.duplicateNotes([
            (channel: "03", vPosition: 0, token: "140", length: 0)
        ])
        require(document.soundChannels.isEmpty, "no sound")
        require(document.bpmNotes.count == 1, "one BPM")
        require(document.bpmNotes[0].y == 0, "y=0")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "v=140")
    }

    /// STOP 显示 48、分辨率 240 → `stopNotes.v == 240`。
    private static func testDuplicateNotesStop() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"initBPM":140,"resolution":240}}"#
        )
        try! document.duplicateNotes([
            (channel: "09", vPosition: 0, token: "48", length: 0)
        ])
        require(document.stopNotes.count == 1, "one STOP")
        require(document.stopNotes[0].y == 0, "y=0")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "48 units at 240 res is 240 pulses")
        require(document.soundChannels.isEmpty, "no sound")
    }

    /// SCROLL 不写新音，也不发明 scroll 数组。
    private static func testDuplicateNotesSkipsScroll() {
        let document = BmsONEDocument.empty()
        try! document.duplicateNotes([
            (channel: "SC", vPosition: 0, token: "0.5", length: 0)
        ])
        require(document.soundChannels.isEmpty, "no new sound")
        require(!document.canUndo, "skip does not undo")
        let json = try! document.jsonString()
        require(!json.contains("scroll"), "no scroll array")
    }

    /// 列 23 / 通道 `04`、token `01` → `bga_events` `id=1`。
    private static func testDuplicateNotesBga() {
        let document = BmsONEDocument.empty()
        try! document.duplicateNotes([
            (channel: "04", vPosition: 0, token: "01", length: 0)
        ])
        require(document.bgaEvents.count == 1, "one BGA")
        require(document.bgaEvents[0].y == 0, "y=0")
        require(Int(document.bgaEvents[0].identifier) == 1, "id=1")
        require(document.soundChannels.isEmpty, "no sound")
    }

    /// 夹具再复制到同一格 `11`、vpos `0` → `Overlapping notes`。
    private static func testDuplicateNotesOccupiedRejected() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        do {
            try document.duplicateNotes([
                (channel: "11", vPosition: 0, token: "01", length: 0)
            ])
            fail("occupied duplicate must throw")
        } catch {
            require(error.localizedDescription.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].notes.count == 1, "one note")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture stays")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// beat-5k 复制到 A8（通道 `19`）不写，不写成 `x=0`。
    private static func testDuplicateNotesBeat5kMissingLaneDoesNotWriteX0() {
        let document = BmsONEDocument.empty()
        try! document.duplicateNotes(
            [(channel: "19", vPosition: 0, token: "01", length: 0)],
            mode: BmsONEViewMode(kind: .beat5k)
        )
        require(document.soundChannels.isEmpty, "A8 skipped")
        require(!document.canUndo, "missing lane does not undo")
        let json = try! document.jsonString()
        require(!json.contains("\"x\":0") && !json.contains("\"x\": 0"), "not written as x=0")
    }

    /// 复制到 BGM（通道 `01`）写成 `x=0`，原音留下。
    private static func testDuplicateNotesBGMWritesX0() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.duplicateNotes([
            (channel: "01", vPosition: 0, token: "01", length: 0)
        ])
        require(document.soundChannels[0].notes.count == 2, "original plus BGM")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "original stays")
        require(document.soundChannels[0].notes[1].x == 0, "BGM x=0")
        require(document.soundChannels[0].notes[1].y == 0, "BGM y=0")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// 夹具短音 identity 0：剪贴板一行，谱上消失，一笔撤销回来。
    private static func testCutClipboardFixtureShortNoteAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        let text = document.copyClipboard(identities: [0], ntInput: false)
        require(text == "iBMSC Clipboard Data\r\n6 0 10000 0 0 0", "cut clipboard fixture short")
        try! document.eraseNotes(identities: [0])
        require(document.soundChannels[0].notes.isEmpty, "cut note gone")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.title == "Demo", "title stays")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "note back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "same pulse")
        require(document.soundChannels[0].name == "kick.wav", "name back")
    }

    /// 两颗声音音一次剪切：两颗都消失，剪贴板两行，一笔撤销都回来。
    private static func testCutTwoSoundNotesOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":0,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        let text = document.copyClipboard(identities: [first, second], ntInput: false)
        require(text.hasPrefix("iBMSC Clipboard Data\r\n"), "cut header")
        let rows = text.split(separator: "\r\n", omittingEmptySubsequences: false)
        require(rows.count == 3, "header plus two note rows")
        try! document.eraseNotes(identities: [first, second, first])
        require(document.soundChannels[0].notes.isEmpty, "both cut")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 2, "both back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "first back")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 0, "second back")
        require(!document.undo(), "second undo does not exist")
    }

    /// 两颗声音音一次删除：不要求剪贴板，一笔撤销都回来。
    private static func testEraseTwoSoundNotesOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.eraseNotes(identities: [first, second])
        require(document.soundChannels[0].notes.isEmpty, "both deleted")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 2, "both back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "first back")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 240, "second back")
        require(!document.undo(), "second undo does not exist")
    }

    /// 删除一条 `bpmNotes` `y=0 v=140`：BPM 没了，声音音不动。
    private static func testEraseBpmLeavesSoundAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"bpmNotes":[{"y":0,"v":140}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        try! document.eraseNotes(bpmPulses: [0])
        require(document.bpmNotes.isEmpty, "BPM gone")
        require(document.soundChannels[0].notes.count == 1, "sound stays")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "sound pulse")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.undo(), "one undo")
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 0, "BPM back")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "BPM v")
        require(document.soundChannels[0].notes.count == 1, "sound still there")
    }

    /// 删除 STOP 显示 48、分辨率 240（存 `v=240`）。
    private static func testEraseStopPulsesAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"stopNotes":[{"y":0,"v":240}]}"#
        )
        try! document.eraseNotes(stopPulses: [0])
        require(document.stopNotes.isEmpty, "STOP gone")
        require(document.undo(), "one undo")
        require(document.stopNotes.count == 1 && document.stopNotes[0].y == 0, "STOP back")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "STOP v")
    }

    /// 删除 BGA `y=0 id=1`：`bga_events` 空。
    private static func testEraseBgaEventAndUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":0,"id":1}]}}"#
        )
        try! document.eraseNotes(bgaEvents: [(lane: .bga, pulseY: 0)])
        require(document.bgaEvents.isEmpty, "BGA gone")
        require(document.bgaHeaders.count == 1, "header stays")
        require(document.undo(), "one undo")
        require(document.bgaEvents.count == 1 && document.bgaEvents[0].y == 0, "BGA back")
        require(Int(document.bgaEvents[0].identifier) == 1, "BGA id")
    }

    /// 删除长音 `x=1 y=0 l=240`：只少一颗声音音，JSON 无 `"51"`。
    private static func testEraseLongNoteOnceNo51() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.eraseNotes(identities: [identity, identity])
        require(document.soundChannels[0].notes.isEmpty, "long note gone once")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        let json = try! document.jsonString()
        require(!json.contains("\"51\""), "no 51 channel")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "long back")
        require(document.soundChannels[0].notes[0].l == 240, "length back")
    }

    /// 空选、找不到的 identity、已不在的时值：不记撤销。
    private static func testEraseNotesEmptyDoesNotUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        require(!document.canUndo, "open has no history")
        try! document.eraseNotes()
        try! document.eraseNotes(identities: [])
        try! document.eraseNotes(identities: [9_999_999])
        try! document.eraseNotes(bpmPulses: [480], stopPulses: [480], bgaEvents: [(lane: .bga, pulseY: 480)])
        require(document.soundChannels[0].notes.count == 1, "fixture stays")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(!document.canUndo, "empty or skip does not undo")
    }

    /// 一颗声音音 + 一条 BPM 一次删除：一笔撤销两样都回来。
    private static func testEraseSoundAndBpmOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"lines":[{"y":240}],"bpmNotes":[{"y":0,"v":140}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.eraseNotes(identities: [identity], bpmPulses: [0])
        require(document.soundChannels[0].notes.isEmpty, "sound gone")
        require(document.bpmNotes.isEmpty, "BPM gone")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.title == "Demo", "title stays")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        let json = try! document.jsonString()
        require(!json.contains("#WAV"), "no #WAV")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "sound back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "sound pulse")
        require(document.bpmNotes.count == 1 && document.bpmNotes[0].y == 0, "BPM back")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "BPM v")
        require(!document.undo(), "second undo does not exist")
    }

    /// 两颗声音音一次复制，`undo()` 一次两颗副本都消失。
    private static func testDuplicateNotesTwoSoundsOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":0,"l":0,"c":false}]}]}"#
        )
        try! document.duplicateNotes([
            (channel: "13", vPosition: 48, token: "01", length: 0),
            (channel: "14", vPosition: 48, token: "01", length: 0)
        ])
        require(document.soundChannels[0].notes.count == 4, "two originals plus two copies")
        require(document.soundChannels[0].notes.contains { $0.x == 3 && $0.y == 240 }, "copy A3")
        require(document.soundChannels[0].notes.contains { $0.x == 4 && $0.y == 240 }, "copy A4")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 2, "copies gone")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "first original")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 0, "second original")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// 夹具短音搬到 `12`、vpos `0`：只剩一颗 `x=2 y=0`，一笔撤销。
    private static func testMoveNotesAtVPositionFixtureShortSamePulseAndUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition([
            (identity: 0, channel: "11", destChannel: "12", destVPosition: 0)
        ])
        require(document.soundChannels.count == 1, "one channel")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.soundChannels[0].notes.count == 1, "original moved, not copied")
        require(document.soundChannels[0].notes[0].x == 2, "x=2")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].l == 0, "l=0")
        require(document.title == "Demo", "title stays")
        require(document.lines.count == 1 && document.lines[0].y == 240, "line stays")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM stays")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "one note back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture back")
        require(document.soundChannels[0].name == "kick.wav", "name back")
        require(!document.undo(), "second undo does not exist")
    }

    /// 同一夹具搬到 `12`、vpos `48` → `x=2 y=240`，仍一颗。
    private static func testMoveNotesAtVPositionFixtureShortToVpos48() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition([
            (identity: 0, channel: "11", destChannel: "12", destVPosition: 48)
        ])
        require(document.soundChannels[0].notes.count == 1, "still one note")
        require(document.soundChannels[0].notes[0].x == 2, "x=2")
        require(document.soundChannels[0].notes[0].y == 240, "y=240")
        require(document.soundChannels[0].notes[0].l == 0, "l=0")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// Hidden 目标通道 `31`：写成可见列 `x=1`，JSON 无 `"31"`。
    private static func testMoveNotesAtVPositionHiddenWritesVisibleLane() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition([
            (identity: 0, channel: "11", destChannel: "31", destVPosition: 48)
        ])
        require(document.soundChannels[0].notes.count == 1, "still one note")
        require(document.soundChannels[0].notes[0].x == 1, "Hidden -> visible x=1")
        require(document.soundChannels[0].notes[0].x != 0, "not BGM")
        require(document.soundChannels[0].notes[0].y == 240, "y=240")
        let json = try! document.jsonString()
        require(!json.contains("\"31\""), "no 31 channel")
    }

    /// 长音 `l=240` 加 comment 搬到 `12` 同一脉冲：`x=2`，extra 还在。
    private static func testMoveNotesAtVPositionLongKeepsLengthAndExtra() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"keep me"}]}]}"#
        )
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        try! document.moveNotesAtVPosition([
            (identity: identity, channel: "11", destChannel: "12", destVPosition: 0)
        ])
        require(document.soundChannels[0].notes.count == 1, "still one long")
        require(document.soundChannels[0].notes[0].x == 2, "x=2")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].notes[0].l == 240, "length stays")
        let extra = document.selectedObjectsDisplay(identities: [identity]).extraText
        require(extra.contains("keep me"), "comment extra stays")
        let json = try! document.jsonString()
        require(json.contains("keep me"), "comment still in JSON")
        require(!json.contains("\"51\""), "no 51 channel")
    }

    /// 两颗音一次搬到 `13`/`14`、vpos `48`：一笔撤销两颗都回去。
    private static func testMoveNotesAtVPositionTwoSoundsOneUndo() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":0,"l":0,"c":false}]}]}"#
        )
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let second = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 1)
        try! document.moveNotesAtVPosition([
            (identity: first, channel: "11", destChannel: "13", destVPosition: 48),
            (identity: second, channel: "12", destChannel: "14", destVPosition: 48),
            (identity: first, channel: "11", destChannel: "13", destVPosition: 48)
        ])
        require(document.soundChannels[0].notes.count == 2, "both moved, not copied")
        require(document.soundChannels[0].notes.contains { $0.x == 3 && $0.y == 240 }, "first x=3 y=240")
        require(document.soundChannels[0].notes.contains { $0.x == 4 && $0.y == 240 }, "second x=4 y=240")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 2, "both back")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "first back")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 0, "second back")
        require(!document.undo(), "second undo does not exist")
    }

    /// 通道 `03` 的 BPM `y=0 v=140` 搬到 vpos `48`：`y=240`，声音音不动。
    private static func testMoveNotesAtVPositionBPM() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"bpmNotes":[{"y":0,"v":140}],"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]}"#
        )
        try! document.moveNotesAtVPosition([
            (identity: nil, channel: "03", destChannel: "03", destVPosition: 48)
        ])
        require(document.bpmNotes.count == 1, "one BPM")
        require(document.bpmNotes[0].y == 240, "BPM y=240")
        require(abs(document.bpmNotes[0].v - 140) < 1e-9, "BPM v stays")
        require(document.soundChannels[0].notes.count == 1, "sound stays")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "sound pulse")
    }

    /// STOP 显示 48、分辨率 240（`v=240`）搬到 vpos `48`：`y=240`，`v` 仍 240。
    private static func testMoveNotesAtVPositionStop() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"stopNotes":[{"y":0,"v":240}]}"#
        )
        try! document.moveNotesAtVPosition([
            (identity: nil, channel: "09", destChannel: "09", destVPosition: 48)
        ])
        require(document.stopNotes.count == 1, "one STOP")
        require(document.stopNotes[0].y == 240, "STOP y=240")
        require(abs(document.stopNotes[0].v - 240) < 1e-9, "STOP v stays")
    }

    /// SCROLL 不搬、不发明 scroll、不记撤销。
    private static func testMoveNotesAtVPositionSkipsScroll() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition([
            (identity: nil, channel: "SC", destChannel: "SC", destVPosition: 48)
        ])
        require(document.soundChannels[0].notes.count == 1, "sound stays")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "fixture stays")
        require(!document.canUndo, "SCROLL does not undo")
        let json = try! document.jsonString()
        require(!json.contains("scroll"), "no scroll array")
    }

    /// BGA `y=0 id=1` 搬到 vpos `48`：`y=240`，车道仍是 BGA。
    private static func testMoveNotesAtVPositionBga() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"resolution":240},"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":0,"id":1}]}}"#
        )
        try! document.moveNotesAtVPosition([
            (identity: nil, channel: "04", destChannel: "04", destVPosition: 48)
        ])
        require(document.bgaEvents.count == 1, "one BGA")
        require(document.bgaEvents[0].y == 240, "BGA y=240")
        require(Int(document.bgaEvents[0].identifier) == 1, "id stays")
        require(document.layerEvents.isEmpty, "still BGA lane")
        require(document.poorEvents.isEmpty, "not Poor")
    }

    /// 夹具再搬到同一格已被占用的可玩列 → `Overlapping notes`，谱不动。
    private static func testMoveNotesAtVPositionOccupiedRejected() {
        let document = try! BmsONEDocument.fromJSON(
            #"{"info":{"title":"Demo","initBPM":140,"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":0,"l":0,"c":false}]}]}"#
        )
        do {
            try document.moveNotesAtVPosition([
                (identity: 0, channel: "11", destChannel: "12", destVPosition: 0)
            ])
            fail("occupied move must throw")
        } catch {
            require(error.localizedDescription.contains("Overlapping notes"), "Overlapping notes")
        }
        require(document.soundChannels[0].notes.count == 2, "both stay")
        require(document.soundChannels[0].notes[0].x == 1 && document.soundChannels[0].notes[0].y == 0, "first stays")
        require(document.soundChannels[0].notes[1].x == 2 && document.soundChannels[0].notes[1].y == 0, "second stays")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
        require(!document.canUndo, "reject does not undo")
    }

    /// beat-5k 搬到 `19`：不写 `x=0`，原音不动，不记撤销。
    private static func testMoveNotesAtVPositionBeat5kMissingLaneDoesNotWriteX0() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition(
            [(identity: 0, channel: "11", destChannel: "19", destVPosition: 0)],
            mode: BmsONEViewMode(kind: .beat5k)
        )
        require(document.soundChannels[0].notes.count == 1, "fixture stays")
        require(document.soundChannels[0].notes[0].x == 1, "not x=0")
        require(document.soundChannels[0].notes[0].y == 0, "y stays")
        require(!document.canUndo, "missing lane does not undo")
        let json = try! document.jsonString()
        require(!json.contains("\"x\":0") && !json.contains("\"x\": 0"), "not written as x=0")
    }

    /// 搬到 BGM（`01`）→ `x=0`，原音搬走。
    private static func testMoveNotesAtVPositionBGMWritesX0() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition([
            (identity: 0, channel: "11", destChannel: "01", destVPosition: 0)
        ])
        require(document.soundChannels[0].notes.count == 1, "original moved")
        require(document.soundChannels[0].notes[0].x == 0, "BGM x=0")
        require(document.soundChannels[0].notes[0].y == 0, "y=0")
        require(document.soundChannels[0].name == "kick.wav", "name stays")
    }

    /// `disableVerticalMove`：列差生效，vpos 差为 0。
    private static func testMoveNotesAtVPositionDisableVerticalKeepsVpos() {
        let origin = ChartDuplicate.NoteRef(columnIndex: 1, vPosition: 0, length: 0)
        let shifted = ChartDuplicate.shift(
            notes: [origin],
            origin: origin,
            mouseColumn: 2,
            mouseVPosition: 48,
            ntInput: true,
            disableVerticalMove: true
        )
        require(shifted.columnDelta == 1, "column delta")
        require(shifted.vPositionDelta == 0, "vpos delta locked")
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.moveNotesAtVPosition([
            (identity: 0, channel: "11", destChannel: "12", destVPosition: 0)
        ])
        require(document.soundChannels[0].notes[0].x == 2, "column moves")
        require(document.soundChannels[0].notes[0].y == 0, "vpos stays")
    }

    /// 头 BPM 加一颗音只 `undo()` 一次就全部回去。
    private static func testTimeSelectionTwoNotesOneUndo() {
        let document = try! BmsONEDocument.open(url: fixtureURL())
        try! document.applyChartNotes(
            [
                timeNote(),
                timeNote(vPosition: 48, columnIndex: BmsonTimeSelection.a2, value: 10_000)
            ],
            initialBpm: 180
        )
        require(document.soundChannels[0].notes.count == 2, "two notes")
        require(abs(document.initialBpm - 180) < 1e-9, "initBPM 180")
        require(document.undo(), "one undo")
        require(document.soundChannels[0].notes.count == 1, "one note back")
        require(document.soundChannels[0].notes[0].y == 0, "y=0 back")
        require(abs(document.initialBpm - 140) < 1e-9, "initBPM 140 back")
    }

    private static func timeNote(
        vPosition: Double = 0,
        columnIndex: Int = BmsonTimeSelection.a2,
        value: Int = 10_000,
        length: Double = 0
    ) -> (vPosition: Double, columnIndex: Int, value: Int, length: Double) {
        (vPosition: vPosition, columnIndex: columnIndex, value: value, length: length)
    }

    private static func testMoveMissingBpmRollsBack() {
        let document = BmsONEDocument.empty()
        let before = try! document.jsonString()
        do {
            try document.moveBpmNote(from: 999, to: 120, bpm: 150)
            fail("moving a missing BPM unexpectedly succeeded")
        } catch { }
        require((try! document.jsonString()) == before, "failed BPM move changed JSON")
        require(!document.isModified && !document.canUndo && !document.canRedo && document.filePath == nil,
                "failed BPM move changed document state")
    }

    private static let selectedObjectsJSON =
        #"{"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"first beat"},{"x":2,"y":240,"l":120,"c":false}]}]}"#

    private static func fixtureURL(_ name: String = "minimal-roundtrip.bmson") -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("tests/fixtures/bmson/\(name)"),
            cwd.appendingPathComponent("../../tests/fixtures/bmson/\(name)"),
            cwd.appendingPathComponent("../../../tests/fixtures/bmson/\(name)")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        fputs("missing tests/fixtures/bmson/\(name) from \(cwd.path)\n", stderr)
        exit(EXIT_FAILURE)
    }

    private static func bmsImportURL(_ name: String = "minimal-7k.bms") -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("tests/fixtures/bms-import/\(name)"),
            cwd.appendingPathComponent("../../tests/fixtures/bms-import/\(name)"),
            cwd.appendingPathComponent("../../../tests/fixtures/bms-import/\(name)")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        fputs("missing tests/fixtures/bms-import/\(name) from \(cwd.path)\n", stderr)
        exit(EXIT_FAILURE)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
