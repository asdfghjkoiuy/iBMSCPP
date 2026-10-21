import Foundation

@main
struct LegacyBmsonPreviewTests {
    @MainActor
    static func main() {
        testWavTableUsesChannelIndex()
        testEncodeWavTableRoundtrips()
        testAudioMetadataDocumentIsWavOnly()
        testNotesUsePulseOverResolution()
        testContinueFlagIsSilent()
        testEmptyNameChannelIsSilent()
        testScheduleAt120BPM()
        testPlayHereSkipsEarlierBeats()
        testBpmChangeUsesNewRate()
        testPreviewFileNameAcceptsTokenOrFile()
        testEmptyChartStillHasContext()
        testStopAddsOneBeatAt120()
        testZeroStopIsIgnored()
        testStopUsesBpmAtSamePulse()
        testPlayHereIncludesStopAtPointer()
        testLaneAndLengthDoNotChangeAudioHits()
        testShortNoteUsesSevenKeyColumn()
        testLongNoteSpanFollowsLength()
        testContinueStaysVisibleWithoutRetrigger()
        testBgmPulseIsNotAKeyLane()
        testUnnamedKeyNoteIsVisibleButSilent()
        testResolutionChangesBeat()
        testZeroResolutionUsesMapperFallback()
        testFourteenKeyKeepsScratchAtEachEnd()
        testFiveKeyDropsTheExtraKey()
        testPopnNineStaysPlayerOne()
        testBattleAliasUsesFourteenKeyLanes()
        testKeyboard36KeepsLanesPastSixteen()
        testKeyboardDoublePlayerFollowsMode()
        testBarLinesStayReal()
        testNotePastTheLastBarDoesNotPadThirtyTwoMeasures()
        testPlayHereKeepsEarlierVisualNotes()
        testContextCarriesTitleModeAndBars()
        testScratchOrderFollowsTheCaller()
        testBmsCollapsesPairedEndsAndSkipsNonKeys()
        testBmsKindsAndBmsonHeadersReachThePlayer()
        testBmsPlayerHeaderAndEventsChooseColumns()
        testBmsBgaMapsLayersWithoutDirectory()
        testBmsEndBeatIgnoresEmptyMeasurePad()
        testBmsonBgaCoversEndWithoutKeys()
        testSameSourceLineNormalNoteStillSounds()
        print("LegacyBmsonPreviewTests passed")
    }

    /// 声道 0 的 `kick.wav` 记在 `01`。
    private static func testWavTableUsesChannelIndex() {
        let table = LegacyBmsonPreview.wavTable(channelNames: ["kick.wav", "", "snare.ogg"])
        require(table["01"] == "kick.wav", "first named channel is 01")
        require(table["02"] == nil, "empty name is omitted")
        require(table["03"] == "snare.ogg", "third slot is 03")
    }

    /// 编成 `#WAV` 后再解析，文件名还在。
    private static func testEncodeWavTableRoundtrips() {
        let table = ["01": "kick.wav", "0A": "hat.ogg"]
        let parsed = LegacyPreviewAudio.parseWavTable(from: LegacyBmsonPreview.encodeWavTable(table))
        require(parsed["01"] == "kick.wav" && parsed["0A"] == "hat.ogg", "encoded table parses")
    }

    /// 音频元数据只留 `#WAV`，不带标题或 BGA，也不能当存档。
    private static func testAudioMetadataDocumentIsWavOnly() {
        let data = LegacyBmsonPreview.audioMetadataDocumentData(wavTable: ["01": "my kick.wav", "02": "shot.bmp"])
        let text = String(decoding: data, as: UTF8.self)
        let parsed = LegacyPreviewAudio.parseWavTable(from: data)
        require(parsed["01"] == "my kick.wav" && parsed["02"] == "shot.bmp", "audio metadata keeps both names")
        require(data == LegacyBmsonPreview.encodeWavTable(["01": "my kick.wav", "02": "shot.bmp"]), "helper is the wav table")
        require(!text.contains("#TITLE") && !text.contains("#BMP") && !text.contains("#PATH_WAV"), "audio metadata has no chart headers")
    }

    /// `y / resolution` 就是拍。默认 240：`y=240` 是拍 1。
    private static func testNotesUsePulseOverResolution() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 240, continueFlag: false)])],
            resolution: 240
        )
        require(notes.count == 1, "one audible note")
        require(notes[0].wavToken == "01" && abs(notes[0].beat - 1) < 0.000_001, "240/240 is beat 1")
    }

    /// `c == true` 不另起一发。
    private static func testContinueFlagIsSilent() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(
                name: "kick.wav",
                notes: [
                    LegacyBmsonPreview.SoundNote(y: 0, continueFlag: false),
                    LegacyBmsonPreview.SoundNote(y: 240, continueFlag: true)
                ]
            )],
            resolution: 240
        )
        require(notes.count == 1 && notes[0].beat == 0, "continue note is skipped")
    }

    /// 没文件名的声道不排进时间表。
    private static func testEmptyNameChannelIsSilent() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "", notes: [LegacyBmsonPreview.SoundNote(y: 0, continueFlag: false)])],
            resolution: 240
        )
        require(notes.isEmpty, "unnamed channel has no hits")
    }

    /// 120 BPM、`resolution 240`、`y=480` 是拍 2，从拍 0 起是 1.0 秒。
    private static func testScheduleAt120BPM() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 480, continueFlag: false)])],
            resolution: 240
        )
        let timing = LegacyBmsonPreview.timing(initBpm: 120, bpmNotes: [], resolution: 240)
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 0)
        require(hits.count == 1, "one hit")
        require(abs(hits[0].seconds - 1.0) < 0.000_001 && hits[0].wavToken == "01", "2 beats at 120 BPM is 1s")
    }

    /// 指针在拍 1 时，拍 0 的音不播；拍 2 的音从 0.5 秒起。
    private static func testPlayHereSkipsEarlierBeats() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(
                name: "kick.wav",
                notes: [
                    LegacyBmsonPreview.SoundNote(y: 0, continueFlag: false),
                    LegacyBmsonPreview.SoundNote(y: 480, continueFlag: false)
                ]
            )],
            resolution: 240
        )
        let timing = LegacyBmsonPreview.timing(initBpm: 120, bpmNotes: [], resolution: 240)
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 1)
        require(hits.count == 1, "Play Here drops the note before the pointer")
        require(abs(hits[0].seconds - 0.5) < 0.000_001, "1 beat at 120 BPM is 0.5s")
    }

    /// 拍 1 改成 240 BPM 后，拍 0 到拍 2：0.5 + 0.25 = 0.75 秒。
    private static func testBpmChangeUsesNewRate() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 480, continueFlag: false)])],
            resolution: 240
        )
        let timing = LegacyBmsonPreview.timing(
            initBpm: 120,
            bpmNotes: [(y: 240, v: 240)],
            resolution: 240
        )
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 0)
        require(hits.count == 1, "one hit after BPM change")
        require(abs(hits[0].seconds - 0.75) < 0.000_001, "1 beat at 120 then 1 beat at 240")
    }

    /// 点 `01` 或 `kick.wav` 都能找到文件名。
    private static func testPreviewFileNameAcceptsTokenOrFile() {
        let table = LegacyBmsonPreview.wavTable(channelNames: ["kick.wav"])
        require(LegacyBmsonPreview.previewFileName(token: "01", table: table) == "kick.wav", "token 01")
        require(LegacyBmsonPreview.previewFileName(token: "kick.wav", table: table) == "kick.wav", "file name")
        require(LegacyBmsonPreview.previewFileName(token: "missing.wav", table: table) == nil, "unknown name")
    }

    /// 空 BMSON 仍有预览上下文，F5 不再因为没有 BMS 会话直接停掉。
    private static func testEmptyChartStillHasContext() {
        let context = LegacyBmsonPreview.context(
            channelNames: [],
            channels: [],
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            chartDirectory: nil,
            playHereBeat: 2
        )
        require(context.notes.isEmpty, "empty chart has no notes")
        require(context.playHereBeat == 2, "Play Here still receives the pointer beat")
        require(context.timing.headerBPM == 120, "header BPM stays")
    }

    /// 拍 1 停 240 脉冲（1 拍）。120 BPM 下，拍 2 的音是 1.5 秒。
    private static func testStopAddsOneBeatAt120() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 480, continueFlag: false)])],
            resolution: 240
        )
        let timing = LegacyBmsonPreview.timing(
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            stopNotes: [(y: 240, v: 240)]
        )
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 0)
        require(hits.count == 1, "one hit with stop")
        require(abs(hits[0].seconds - 1.5) < 0.000_001, "1s travel plus 0.5s stop")
    }

    /// `v == 0` 不算停顿。
    private static func testZeroStopIsIgnored() {
        let timing = LegacyBmsonPreview.timing(
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            stopNotes: [(y: 240, v: 0)]
        )
        require(timing.stopEvents.isEmpty, "zero-length stop is dropped")
    }

    /// 拍 1 同时改成 240 BPM 再停 1 拍：0.5 + 0.25 + 0.25 = 1.0 秒。
    private static func testStopUsesBpmAtSamePulse() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 480, continueFlag: false)])],
            resolution: 240
        )
        let timing = LegacyBmsonPreview.timing(
            initBpm: 120,
            bpmNotes: [(y: 240, v: 240)],
            resolution: 240,
            stopNotes: [(y: 240, v: 240)]
        )
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 0)
        require(hits.count == 1, "one hit after BPM and stop")
        require(abs(hits[0].seconds - 1.0) < 0.000_001, "stop uses the BPM at the same pulse")
    }

    /// 指针在拍 1：停顿仍算进去，拍 2 的音是 1.0 秒。
    private static func testPlayHereIncludesStopAtPointer() {
        let notes = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 480, continueFlag: false)])],
            resolution: 240
        )
        let timing = LegacyBmsonPreview.timing(
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            stopNotes: [(y: 240, v: 240)]
        )
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: 1)
        require(hits.count == 1, "Play Here still has the later note")
        require(abs(hits[0].seconds - 1.0) < 0.000_001, "0.5s travel plus 0.5s stop at the pointer")
    }

    /// `x` / `l` 只给画面。同一发声仍是拍 1、键 `01`。
    private static func testLaneAndLengthDoNotChangeAudioHits() {
        let plain = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [LegacyBmsonPreview.SoundNote(y: 240, continueFlag: false)])],
            resolution: 240
        )
        let placed = LegacyBmsonPreview.notes(
            channels: [(name: "kick.wav", notes: [
                LegacyBmsonPreview.SoundNote(y: 240, continueFlag: false, x: 3, l: 480)
            ])],
            resolution: 240
        )
        require(plain[0].wavToken == placed[0].wavToken && near(plain[0].beat, placed[0].beat), "lane and length stay out of the hit time")
        require(plain[0].kind == .bgm && placed[0].kind == .key, "x <= 0 is bgm and x > 0 is key")
        require(plain.count == 1 && plain[0].wavToken == "01" && near(plain[0].beat, 1), "the hit is still beat 1")
    }

    /// Beat 7-key：`x=1` 落到 `11`，刮盘 `16` 在最左，2P 不出现。整列都是 1P。
    private static func testShortNoteUsesSevenKeyColumn() {
        let mapped = chart(notes: [note(x: 1, y: 240)], modeHint: "beat-7k")
        require(mapped.unsupportedNoteCount == 0 && mapped.partialDisplay.isEmpty, "7k can draw its own lanes")
        require(mapped.chart.lanes.map(\.id) == ["16", "11", "12", "13", "14", "15", "18", "19"], "7k column order")
        require(mapped.chart.lanes.allSatisfy { $0.player == 1 }, "7k is one player")
        require(mapped.chart.lanes.first?.isScratch == true, "left column is the scratch")
        require(mapped.chart.lanes.first { $0.id == "11" }?.isScratch == false, "key 1 is not a scratch")
        require(!mapped.chart.lanes.contains { $0.id == "21" || $0.id == "26" }, "7k has no 2P columns")
        require(mapped.chart.notes.count == 1, "one key note")
        require(mapped.chart.notes[0].laneID == "11" && near(mapped.chart.notes[0].startBeat, 1), "x=1 is column 11 at beat 1")
        require(near(mapped.chart.notes[0].endBeat, 1), "a short note has no tail")
    }

    /// `l=480`、resolution 240：从拍 0 拉到拍 2，落在 `x=3` → `13`。
    private static func testLongNoteSpanFollowsLength() {
        let mapped = chart(notes: [note(x: 3, y: 0, l: 480)], modeHint: "beat-7k")
        require(mapped.chart.notes.count == 1, "one long note")
        let drawn = mapped.chart.notes[0]
        require(drawn.laneID == "13" && near(drawn.startBeat, 0) && near(drawn.endBeat, 2), "two-beat hold on key 3")
    }

    /// 续播 `c=true` 不重新发声，但长音尾巴仍要画出来。
    private static func testContinueStaysVisibleWithoutRetrigger() {
        let channels = [(
            name: "hold.wav",
            notes: [
                note(x: 1, y: 0),
                note(x: 2, y: 480, l: 240, c: true)
            ]
        )]
        let audible = LegacyBmsonPreview.notes(channels: channels, resolution: 240)
        let mapped = LegacyBmsonPreview.visualChart(
            channels: channels,
            resolution: 240,
            modeHint: "beat-7k"
        )
        require(audible.count == 1 && near(audible[0].beat, 0), "continue flag does not schedule a second hit")
        require(mapped.chart.notes.count == 2, "both notes are drawn")
        let tail = mapped.chart.notes[1]
        require(tail.laneID == "12" && near(tail.startBeat, 2) && near(tail.endBeat, 3), "continue tail is a one-beat hold")
    }

    /// `x=0` 仍进发声表，键道里没有它，也没有 `01` 列。
    private static func testBgmPulseIsNotAKeyLane() {
        let channels = [(
            name: "song.ogg",
            notes: [
                note(x: 0, y: 0),
                note(x: 1, y: 240)
            ]
        )]
        let audible = LegacyBmsonPreview.notes(channels: channels, resolution: 240)
        let mapped = LegacyBmsonPreview.visualChart(channels: channels, resolution: 240, modeHint: "beat-7k")
        require(audible.count == 2, "BGM and the key both trigger audio")
        require(mapped.unsupportedNoteCount == 0, "BGM is omitted on purpose")
        require(mapped.chart.notes.count == 1 && mapped.chart.notes[0].laneID == "11", "only the key is drawn")
        require(!mapped.chart.lanes.contains { $0.id == "01" || $0.id == "B1" }, "no BGM column")
    }

    /// 没文件名的声道不发声，键上的音仍然要画。
    private static func testUnnamedKeyNoteIsVisibleButSilent() {
        let channels = [(name: "", notes: [note(x: 4, y: 240)])]
        require(LegacyBmsonPreview.notes(channels: channels, resolution: 240).isEmpty, "unnamed channel stays silent")
        let mapped = LegacyBmsonPreview.visualChart(channels: channels, resolution: 240, modeHint: "beat-7k")
        require(mapped.chart.notes.count == 1 && mapped.chart.notes[0].laneID == "14", "key 4 is still drawn")
    }

    /// 同一脉冲在 240 和 480 两种 resolution 下不是同一拍。
    private static func testResolutionChangesBeat() {
        let coarse = chart(notes: [note(x: 1, y: 480, l: 480)], resolution: 240)
        let fine = chart(notes: [note(x: 1, y: 480, l: 480)], resolution: 480)
        require(near(coarse.chart.notes[0].startBeat, 2) && near(coarse.chart.notes[0].endBeat, 4), "240: pulse 480 is beat 2")
        require(near(fine.chart.notes[0].startBeat, 1) && near(fine.chart.notes[0].endBeat, 2), "480: the same pulse is beat 1")
    }

    /// resolution 0 跟映射一样退回 240，音符还在。
    private static func testZeroResolutionUsesMapperFallback() {
        let mapped = chart(notes: [note(x: 1, y: 240)], resolution: 0)
        require(mapped.chart.notes.count == 1 && near(mapped.chart.notes[0].startBeat, 1), "240 pulses at fallback resolution is beat 1")
    }

    /// 14-key 含 1P/2P。1P 刮盘在最左，2P 刮盘在最右。`player` 按模式的 P2 键，不按通道号。
    private static func testFourteenKeyKeepsScratchAtEachEnd() {
        let mapped = chart(
            notes: [note(x: 9, y: 0), note(x: 16, y: 240)],
            modeHint: "beat-14k"
        )
        let ids = mapped.chart.lanes.map(\.id)
        require(
            ids == ["16", "11", "12", "13", "14", "15", "18", "19", "21", "22", "23", "24", "25", "28", "29", "26"],
            "14k follows the shared column order"
        )
        require(mapped.chart.lanes.first?.isScratch == true && mapped.chart.lanes.last?.isScratch == true, "scratches sit at the two ends")
        require(mapped.chart.lanes.first { $0.id == "16" }?.player == 1, "P1 scratch stays player 1")
        require(mapped.chart.lanes.first { $0.id == "21" }?.player == 2, "P2 key 1 is player 2")
        require(mapped.chart.lanes.first { $0.id == "21" }?.isScratch == false, "P2 key 1 is not a scratch")
        require(mapped.chart.lanes.first { $0.id == "26" }?.player == 2, "P2 scratch is player 2")
        require(mapped.partialDisplay.isEmpty && mapped.unsupportedNoteCount == 0, "14k draws every defined lane")
        let key = mapped.chart.notes.first { $0.laneID == "21" }
        let scratch = mapped.chart.notes.first { $0.laneID == "26" }
        require(key != nil && near(key?.startBeat ?? -1, 0), "x=9 is P2 key 1")
        require(scratch != nil && scratch?.endBeat == scratch?.startBeat && near(scratch?.startBeat ?? -1, 1), "x=16 is the P2 scratch")
    }

    /// 5-key 没有第 6 键。这颗音要计数，不能假装已经画上。模式自身的列是齐的。
    private static func testFiveKeyDropsTheExtraKey() {
        let mapped = chart(notes: [note(x: 1, y: 0), note(x: 6, y: 240)], modeHint: "beat-5k")
        require(mapped.chart.lanes.map(\.id) == ["16", "11", "12", "13", "14", "15"], "5k stops after key 5")
        require(mapped.chart.notes.count == 1 && mapped.chart.notes[0].laneID == "11", "only key 1 is drawn")
        require(mapped.unsupportedNoteCount == 1, "key 6 is reported, not dropped quietly")
        require(mapped.partialDisplay.isEmpty, "5k's own lanes all have columns")
    }

    /// Pop 9-key 的第 9 键通道是 `21`，名字是 Key 9，玩家仍是 1。不能因为通道号当成 2P。
    private static func testPopnNineStaysPlayerOne() {
        let mapped = chart(notes: [note(x: 8, y: 0), note(x: 9, y: 240)], modeHint: "popn-9k")
        let column = mapped.chart.lanes.first { $0.id == "16" }
        require(column?.isScratch == false, "popn column 16 is a key")
        require(column?.title == "Key 8", "the mode names that lane Key 8")
        require(column?.player == 1, "popn column 16 is player 1")
        let ninth = mapped.chart.lanes.first { $0.id == "21" }
        require(ninth?.title == "Key 9" && ninth?.player == 1, "channel 21 is still player 1")
        require(mapped.chart.lanes.allSatisfy { $0.player == 1 }, "popn-9k has no second player")
        require(mapped.chart.notes.contains { $0.laneID == "16" }, "x=8 lands on that key")
        require(mapped.chart.notes.contains { $0.laneID == "21" && near($0.startBeat, 1) }, "x=9 is drawn on channel 21")
        require(mapped.chart.lanes.map(\.id) == ["16", "11", "12", "13", "14", "15", "18", "19", "21"], "popn keeps the shared order")
    }

    /// `beat-7k-battle` 就是 14-key 的列，不是另一套通道号。
    private static func testBattleAliasUsesFourteenKeyLanes() {
        let battle = LegacyBmsonPreview.visualLanes(modeHint: "beat-7k-battle").map(\.id)
        let full = LegacyBmsonPreview.visualLanes(modeHint: "beat-14k").map(\.id)
        require(battle == full && battle.count == 16, "battle hint reuses the 14k columns")
    }

    /// 36-key 前 16 个 `x` 仍走共用列。`x=20` 用独立列 `x20`，不能悄悄丢掉。
    private static func testKeyboard36KeepsLanesPastSixteen() {
        let mapped = chart(notes: [note(x: 1, y: 0), note(x: 20, y: 240)], modeHint: "keyboard-36k")
        require(mapped.unsupportedNoteCount == 0 && mapped.partialDisplay.isEmpty, "defined keys past 16 are drawn")
        require(mapped.chart.notes.contains { $0.laneID == "16" && near($0.startBeat, 0) }, "x=1 uses the first shared column")
        require(mapped.chart.lanes.first { $0.id == "16" }?.isScratch == false, "keyboard column 16 is not a scratch")
        let extra = mapped.chart.lanes.first { $0.id == "x20" }
        require(extra?.player == 1, "keyboard-36k stays one player")
        require(extra?.title.isEmpty == false, "the extra lane keeps the mode name")
        require(mapped.chart.notes.contains { $0.laneID == "x20" && near($0.startBeat, 1) }, "x=20 is drawn on its own lane")
        require(mapped.chart.lanes.contains { $0.id == "x17" } && mapped.chart.lanes.contains { $0.id == "x38" }, "wheels and later keys get lanes")
        require(mapped.chart.lanes.filter { $0.id.hasPrefix("x") }.allSatisfy { $0.player == 1 }, "extra keys stay player 1")
    }

    /// 24-key double：`x=27` 接到通道 `21` 但仍是 2P；`x=35` 超出 16 列，独立列也是 2P。
    private static func testKeyboardDoublePlayerFollowsMode() {
        let mapped = chart(
            notes: [note(x: 1, y: 0), note(x: 27, y: 240), note(x: 35, y: 480)],
            modeHint: "keyboard-24k-double"
        )
        require(mapped.chart.lanes.first { $0.id == "16" }?.player == 1, "P1 key stays player 1")
        require(mapped.chart.lanes.first { $0.id == "21" }?.player == 2, "x=27 uses channel 21 as player 2")
        require(mapped.chart.notes.contains { $0.laneID == "21" && near($0.startBeat, 1) }, "x=27 is drawn")
        let later = mapped.chart.lanes.first { $0.id == "x35" }
        require(later?.player == 2, "x=35 is still P2")
        require(mapped.chart.notes.contains { $0.laneID == "x35" && near($0.startBeat, 2) }, "x=35 is not dropped")
        require(mapped.unsupportedNoteCount == 0, "the mode can show both sides")
    }

    /// 小节线 0、480、960 在 resolution 240 下是拍 0、2、4。后面不再补 32 小节。
    private static func testBarLinesStayReal() {
        let mapped = LegacyBmsonPreview.visualChart(
            title: "  Night  ",
            channels: [(name: "kick.wav", notes: [note(x: 1, y: 240)])],
            resolution: 240,
            modeHint: "beat-7k",
            barLines: [0, 960, 480, 960]
        )
        require(mapped.chart.title == "Night", "title is trimmed")
        require(mapped.chart.barBeats.count == 3, "three real bars")
        require(
            near(mapped.chart.barBeats[0], 0) && near(mapped.chart.barBeats[1], 2) && near(mapped.chart.barBeats[2], 4),
            "bars are 0, 2 and 4"
        )
        require(near(mapped.chart.endBeat, 4), "the chart ends at the last bar")
        require(mapped.chart.endBeat < 20, "no 32-measure editor pad")
    }

    /// 只有原点小节线、音符在拍 2：补到下一根默认 4 拍线，而不是再铺 32 小节。
    private static func testNotePastTheLastBarDoesNotPadThirtyTwoMeasures() {
        let mapped = chart(notes: [note(x: 1, y: 480)], barLines: [0])
        require(mapped.chart.barBeats.count == 2, "origin plus one default bar")
        require(near(mapped.chart.barBeats[0], 0) && near(mapped.chart.barBeats[1], 4), "default bar is 4 beats later")
        require(near(mapped.chart.endBeat, 4), "end covers the note's measure")
    }

    /// Play Here 只改发声起点。拍 0 的键仍留在画面里。
    private static func testPlayHereKeepsEarlierVisualNotes() {
        let context = LegacyBmsonPreview.context(
            channelNames: ["kick.wav"],
            channels: [(name: "kick.wav", notes: [note(x: 1, y: 0), note(x: 1, y: 480)])],
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            chartDirectory: nil,
            playHereBeat: 1,
            modeHint: "beat-7k"
        )
        let hits = LegacyPreviewAudio.scheduleHits(notes: context.notes, timing: context.timing, fromBeat: context.playHereBeat)
        require(hits.count == 1 && near(hits[0].seconds, 0.5), "audio starts at the pointer")
        require(context.visualChart.notes.count == 2, "the picture still contains the earlier key")
        require(context.visualChart.notes.contains { near($0.startBeat, 0) }, "beat 0 remains visible")
    }

    /// 标题、模式和真实小节线进上下文；续播不进发声表。
    private static func testContextCarriesTitleModeAndBars() {
        let context = LegacyBmsonPreview.context(
            channelNames: ["hold.wav"],
            channels: [(name: "hold.wav", notes: [note(x: 1, y: 0), note(x: 1, y: 240, c: true)])],
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            chartDirectory: URL(fileURLWithPath: "/tmp/charts"),
            playHereBeat: 0,
            title: "Night",
            modeHint: "beat-5k",
            barLines: [0, 960]
        )
        require(context.notes.count == 1 && near(context.notes[0].beat, 0), "continue note stays out of the hit list")
        require(context.visualChart.title == "Night", "context keeps the title")
        require(context.visualChart.lanes.map(\.id) == ["16", "11", "12", "13", "14", "15"], "context uses the requested mode")
        require(context.visualChart.notes.count == 2, "context draws the continue note")
        require(context.visualChart.barBeats.count == 2 && near(context.visualChart.endBeat, 4), "context keeps the two bar lines")
        require(context.appliesBmsonPlayhead, "BMSON playhead flag stays on")
        require(context.chartDirectory?.path == "/tmp/charts", "directory stays on the context")
        require(context.notes[0].kind == .key, "x > 0 is a key sound")
        let text = String(decoding: context.documentData, as: UTF8.self)
        require(text.contains("#TITLE Night") && text.contains("#PLAYER 1") && text.contains("#WAV01 hold.wav"), "single 5k preview text keeps title, player and wav")
        require(!text.contains("#RANK") && !text.contains("#PLAYLEVEL") && !text.contains("#PATH_WAV") && !text.contains("#BMP"), "missing info and bga stay out of the wav document")
    }

    /// 调用方把刮盘放到右边时，列顺序不动。7-key 里 `16` 仍是刮盘。
    private static func testScratchOrderFollowsTheCaller() {
        let moved = ["11", "12", "13", "14", "15", "18", "19", "16"]
        let lanes = LegacyBmsonPreview.lanes(
            channelsInOrder: moved,
            mode: BmsONEViewMode(kind: .beat7k)
        )
        require(lanes.map(\.id) == moved, "caller order is kept")
        require(lanes.last?.isScratch == true && lanes.last?.title == "Scratch", "the trailing 16 is still the scratch")
        require(lanes.allSatisfy { $0.player == 1 }, "caller-ordered 7k lanes stay player 1")
    }

    /// 一首里同时有短音、已配对长音、地雷、BGM、BPM、STOP、BGA 和 hidden。
    /// `display` 是这些通道经 `ChartLayout.displayChannel` 后的列。测试目标不链 ChartLayout。
    private static func testBmsCollapsesPairedEndsAndSkipsNonKeys() {
        let lanes = LegacyBmsonPreview.visualLanes(modeHint: "beat-14k")
        let mapped = LegacyBmsonPreview.bmsVisualChart(
            title: " Stage 1 ",
            events: [
                event("51", 0, "longNote", line: 10, token: "01", display: "11"),
                event("51", 2, "longNote", line: 11, token: "01", display: "11", numerator: 1, denominator: 2),
                event("51", 0, "normalNote", line: 10, token: "99", display: "11"),
                event("12", 1, "normalNote", line: 12, token: "02", display: "12"),
                event("31", 1, "hiddenNote", line: 20, token: "05", display: "11"),
                event("01", 0, "bgm", line: 21, token: "06", display: "B1"),
                event("03", 0, "bpm", line: 22, token: "07", display: "03"),
                event("08", 1, "extendedBpm", line: 23, token: "08", display: "03"),
                event("09", 2, "stop", line: 24, token: "09", display: "09"),
                event("04", 0, "bga", line: 25, token: "0A", display: "04"),
                event("D6", 3, "mine", line: 26, token: "0D", display: "16"),
                event("17", 1, "normalNote", line: 27, token: "0E", display: "17"),
                event("51", 5, "longNote", line: 40, token: "03", display: "11"),
                event("61", 4, "longNote", line: 50, token: "04", display: "21"),
                event("61", 6, "longNote", line: 51, token: "04", display: "21")
            ],
            longNotes: [
                longNote(channel: "51", display: "11", startBeat: 0, endBeat: 2, startLine: 10, endLine: 11, token: "01", endNumerator: 1, endDenominator: 2),
                longNote(channel: "61", display: "21", startBeat: 4, endBeat: 6, startLine: 50, endLine: 51, token: "04")
            ],
            measures: [
                LegacyBmsonPreview.BmsPreviewMeasure(start: 0, length: 4),
                LegacyBmsonPreview.BmsPreviewMeasure(start: 4, length: 4)
            ],
            lanes: lanes
        )
        require(mapped.chart.title == "Stage 1", "BMS title is trimmed")
        let drawnIDs = mapped.chart.lanes.map { lane in lane.id }
        let givenIDs = lanes.map { lane in lane.id }
        require(drawnIDs == givenIDs, "BMS keeps the lane list it was given")
        require(mapped.unplacedPlayableNoteCount == 1, "channel 17 has no key column")
        require(mapped.chart.barBeats == [0, 4], "measure starts stay in order")
        require(near(mapped.chart.endBeat, 8), "end beat is the later measure end")
        require(mapped.chart.notes.count == 6, "paired ends are not drawn again")
        require(contains(mapped.chart.notes, lane: "11", start: 0, end: 0), "a different token on the same line stays")
        require(contains(mapped.chart.notes, lane: "11", start: 0, end: 2), "1P long note is one span")
        require(contains(mapped.chart.notes, lane: "12", start: 1, end: 1), "short key remains")
        require(contains(mapped.chart.notes, lane: "16", start: 3, end: 3), "mine stays on the scratch column")
        require(contains(mapped.chart.notes, lane: "11", start: 5, end: 5), "unpaired long endpoint stays a short note")
        require(contains(mapped.chart.notes, lane: "21", start: 4, end: 6), "2P long note uses the mapped column")
        require(!mapped.chart.notes.contains { near($0.startBeat, 2) && $0.laneID == "11" && near($0.endBeat, 2) }, "the long-note tail is not a second note")
        let reversed = LegacyBmsonPreview.bmsVisualChart(
            title: "",
            events: [],
            longNotes: [longNote(channel: "11", display: "11", startBeat: 4, endBeat: 1, startLine: 1, endLine: 2, token: "01")],
            measures: [],
            lanes: lanes
        )
        require(
            reversed.chart.notes.count == 1
                && near(reversed.chart.notes[0].startBeat, 1)
                && near(reversed.chart.notes[0].endBeat, 4),
            "a reversed pair still spans the two beats"
        )
    }

    /// `#PLAYER` 1 且没有 2P 物件时只有八列。Couple/Double，或实际上有 2P 键，才是十六列。
    private static func testBmsPlayerHeaderAndEventsChooseColumns() {
        let single = LegacyBmsonPreview.bmsVisualLanes(playerHeader: "1", events: [], longNotes: [])
        require(single.map(\.id) == ["16", "11", "12", "13", "14", "15", "18", "19"], "single play is eight columns")
        require(single.allSatisfy { $0.player == 1 }, "single play lanes are player 1")
        let couple = LegacyBmsonPreview.bmsVisualLanes(playerHeader: "2", events: [], longNotes: [])
        let doubled = LegacyBmsonPreview.bmsVisualLanes(playerHeader: " 3 ", events: [], longNotes: [])
        require(couple.map(\.id) == doubled.map(\.id) && couple.count == 16, "couple and double both open 2P")
        require(couple.first { $0.id == "21" }?.player == 2, "opened 2P column is player 2")
        require(couple.first { $0.id == "16" }?.player == 1, "1P scratch stays player 1")
        let forced = LegacyBmsonPreview.bmsVisualLanes(
            playerHeader: "1",
            events: [event("21", 1, "normalNote", line: 3, token: "01", display: "21")],
            longNotes: []
        )
        require(forced.count == 16, "a real 2P note opens the second side")
        let hiddenOnly = LegacyBmsonPreview.bmsVisualLanes(
            playerHeader: "1",
            events: [event("41", 1, "hiddenNote", line: 4, token: "01", display: "21")],
            longNotes: []
        )
        require(hiddenOnly.count == 8, "hidden 2P does not open play columns")
    }

    /// `#BMP` 只留文件名。`04`/`07`/`06` 分成 base/layer/poor。目录不写进资源名。
    private static func testBmsBgaMapsLayersWithoutDirectory() {
        let lanes = LegacyBmsonPreview.visualLanes(modeHint: "beat-7k")
        let mapped = LegacyBmsonPreview.bmsVisualChart(
            title: "",
            events: [
                event("11", 1, "normalNote", line: 1, token: "01", display: "11"),
                event("04", 2, "bga", line: 2, token: "0a", display: "04"),
                event("07", 6, "bga", line: 3, token: "02", display: "07"),
                event("06", 50, "bga", line: 4, token: "03", display: "06"),
                event("04", 8, "bga", line: 5, token: "04", display: "04")
            ],
            longNotes: [],
            measures: paddedMeasures(count: 1000),
            lanes: lanes,
            bmpNames: ["01": " /tmp/charts/bg.bmp ", "02": "layer.png", "03": "poor.bmp", "ZZ": "unused.bmp"]
        )
        require(mapped.chart.notes.count == 1, "the key is still a note")
        require(mapped.chart.bgaAssets.map(\.id) == ["01", "02", "03", "ZZ"], "named BMPs become assets")
        require(mapped.chart.bgaAssets.first { $0.id == "01" }?.fileName == "/tmp/charts/bg.bmp", "stored name is trimmed, not joined to a directory")
        require(!mapped.chart.bgaAssets.contains { $0.fileName.contains("chartDirectory") }, "assets do not invent a directory key")
        require(mapped.chart.bgaEvents.count == 4, "base, layer, poor and a later base are kept")
        require(mapped.chart.bgaEvents[0].layer == .base && mapped.chart.bgaEvents[0].assetID == "0A" && near(mapped.chart.bgaEvents[0].beat, 2), "04 is base")
        require(mapped.chart.bgaEvents[1].layer == .layer && mapped.chart.bgaEvents[1].assetID == "02" && near(mapped.chart.bgaEvents[1].beat, 6), "07 is layer")
        require(mapped.chart.bgaEvents.contains { $0.layer == .poor && $0.assetID == "03" && near($0.beat, 50) }, "06 is poor")
        require(near(mapped.chart.endBeat, 12), "base at beat 8 extends through its measure")
        require(mapped.chart.endBeat < 100, "poor at beat 50 and the 1000-measure pad do not set the length")
    }

    /// 只有拍 2 的键，核心仍给出 1000 个空小节。结尾停在它所在的那一小节。
    private static func testBmsEndBeatIgnoresEmptyMeasurePad() {
        let lanes = LegacyBmsonPreview.visualLanes(modeHint: "beat-7k")
        let mapped = LegacyBmsonPreview.bmsVisualChart(
            title: "",
            events: [event("11", 2, "normalNote", line: 1, token: "01", display: "11")],
            longNotes: [],
            measures: paddedMeasures(count: 1000),
            lanes: lanes
        )
        require(near(mapped.chart.endBeat, 4), "the note's own measure ends at beat 4")
        require(mapped.chart.barBeats == [0], "later empty measures are not bar lines")
        require(mapped.chart.endBeat < 32, "a thousand default measures are not the chart")
    }

    /// 没有键音，只有 base/layer。结尾要盖住这些事件，并且不垫 32 小节。poor 不把谱面拉长。
    private static func testBmsonBgaCoversEndWithoutKeys() {
        let mapped = LegacyBmsonPreview.visualChart(
            channels: [],
            resolution: 240,
            modeHint: "beat-7k",
            barLines: [0],
            bgaHeaders: [(id: 1, name: " bg.png "), (id: 2, name: ""), (id: 4, name: "layer.png")],
            bgaEvents: [(y: 2400, id: 1)],
            layerEvents: [(y: 480, id: 4)],
            poorEvents: [(y: 9600, id: 9)]
        )
        require(mapped.chart.notes.isEmpty, "no keys to draw")
        require(mapped.chart.bgaAssets.map(\.id) == ["1", "4"], "empty header names are skipped")
        require(mapped.chart.bgaAssets.first { $0.id == "1" }?.fileName == "bg.png", "header name stays a file name")
        require(mapped.chart.bgaEvents.count == 3, "base, layer and poor are all listed")
        require(mapped.chart.bgaEvents.contains { $0.layer == .base && $0.assetID == "1" && near($0.beat, 10) }, "pulse 2400 is beat 10")
        require(mapped.chart.bgaEvents.contains { $0.layer == .layer && near($0.beat, 2) }, "layer is beat 2")
        require(mapped.chart.bgaEvents.contains { $0.layer == .poor && $0.assetID == "9" && near($0.beat, 40) }, "poor is kept")
        require(mapped.chart.endBeat >= 10 && mapped.chart.endBeat < 20, "base extends the chart, poor and the 32-bar pad do not")
        require(mapped.chart.barBeats.count < 10, "bars stop once the base event is covered")
        let context = LegacyBmsonPreview.context(
            channelNames: [],
            channels: [],
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            chartDirectory: URL(fileURLWithPath: "/tmp/song"),
            playHereBeat: 0,
            bgaHeaders: [(id: 1, name: "bg.png")],
            bgaEvents: [(y: 2400, id: 1)]
        )
        require(context.notes.isEmpty, "pure BGA does not invent key hits")
        require(context.visualChart.bgaEvents.count == 1 && context.visualChart.endBeat >= 10, "the picture still has the BGA")
        require(context.chartDirectory?.path == "/tmp/song", "the directory stays beside the file name")
    }

    /// 长音端点和同一行的另一颗普通音不能一起被行号抹掉。
    private static func testSameSourceLineNormalNoteStillSounds() {
        let events = [
            event("51", 0, "longNote", line: 10, token: "01", display: "11"),
            event("12", 0, "normalNote", line: 10, token: "02", display: "12"),
            event("51", 2, "longNote", line: 11, token: "01", display: "11", numerator: 1, denominator: 2)
        ]
        let longs = [
            longNote(channel: "51", display: "11", startBeat: 0, endBeat: 2, startLine: 10, endLine: 11, token: "01", endNumerator: 1, endDenominator: 2)
        ]
        let hits = LegacyBmsonPreview.audibleBmsNotes(events: events, longNotes: longs)
        require(hits.contains { $0.wavToken == "02" && near($0.beat, 0) && $0.kind == .key }, "the other note on the long-note line still plays")
        require(hits.filter { $0.wavToken == "01" && $0.kind == .key }.count == 1, "the long note sounds once from its head")
        require(!hits.contains { $0.wavToken == "01" && near($0.beat, 2) }, "the long-note tail is not a second hit")
    }

    /// BMS 的 bgm / hidden / 地雷 / 长音进真实播放器过滤。BMSON 的 x 与续播也走同一条 `setAudibleKinds`。
    @MainActor
    private static func testBmsKindsAndBmsonHeadersReachThePlayer() {
        let events = [
            event("11", 0, "normalNote", line: 1, token: "01", display: "11"),
            event("01", 1, "bgm", line: 2, token: "02", display: "01"),
            event("31", 1, "hiddenNote", line: 3, token: "01", display: "11"),
            event("D6", 1, "mine", line: 4, token: "0D", display: "16"),
            event("51", 0, "longNote", line: 5, token: "03", display: "13"),
            event("51", 2, "longNote", line: 6, token: "03", display: "13")
        ]
        let longs = [
            longNote(channel: "51", display: "13", startBeat: 0, endBeat: 2, startLine: 5, endLine: 6, token: "03")
        ]
        let audible = LegacyBmsonPreview.audibleBmsNotes(events: events, longNotes: longs)
        require(audible.contains { $0.kind == .key && $0.wavToken == "01" && near($0.beat, 0) }, "normal note is a key")
        require(audible.contains { $0.kind == .bgm && $0.wavToken == "02" && near($0.beat, 1) }, "bgm keeps its wav")
        require(audible.contains { $0.kind == .key && $0.wavToken == "01" && near($0.beat, 1) }, "hidden stays audible as a key")
        require(audible.contains { $0.kind == .mine && $0.wavToken.isEmpty && near($0.beat, 1) }, "mine kind is set without a chart wav token")
        require(!audible.contains { $0.wavToken == "0D" }, "mine does not play the chart wav")
        require(audible.contains { $0.kind == .key && $0.wavToken == "03" && near($0.beat, 0) }, "long-note head is a key")
        require(!audible.contains { $0.wavToken == "03" && near($0.beat, 2) }, "long-note tail is not a second key")
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [])
        let hits = LegacyPreviewAudio.scheduleHits(notes: audible, timing: timing, fromBeat: 0)
        require(!hits.contains { $0.kind == .mine || $0.wavToken == "0D" }, "schedule drops the mine because engine.ogg is not connected")
        require(hits.contains { $0.kind == .bgm && $0.wavToken == "02" }, "bgm reaches the hit list")
        require(hits.filter { $0.kind == .key && $0.wavToken == "01" }.count == 2, "normal and hidden are both key hits")
        let lanes = LegacyBmsonPreview.visualLanes(modeHint: "beat-7k")
        let picture = LegacyBmsonPreview.bmsVisualChart(
            title: "",
            events: events,
            longNotes: longs,
            measures: [LegacyBmsonPreview.BmsPreviewMeasure(start: 0, length: 4)],
            lanes: lanes
        )
        require(picture.chart.notes.contains { $0.laneID == "16" && near($0.startBeat, 1) }, "mine is still drawn")
        require(!picture.chart.notes.contains { near($0.startBeat, 1) && $0.laneID == "11" }, "hidden is not drawn")

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-um3-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent("key.wav"))
        try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent("bgm.wav"))
        try! toneWAV(duration: 0.05).write(to: folder.appendingPathComponent("hold.wav"))
        let played = audible.filter { $0.wavToken == "01" || $0.wavToken == "02" }
        let document = Data("#TITLE Mine\n#WAV01 key.wav\n#WAV02 bgm.wav\n".utf8)
        let player = LegacyPreviewAudioPlayer()
        player.recordOutputForTests = true
        player.setAudibleKinds([.key])
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: played,
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(player.diagnosticCueCount == 3, "key, hidden and bgm are cues; mine is not, count \(player.diagnosticCueCount)")
        require(
            waitUntil { player.soundingSampleCount >= 1 && player.diagnosticScheduledCues == 1 },
            "opening key did not sound, scheduled \(player.diagnosticScheduledCues) engine \(player.diagnosticEngineFailure ?? "none")"
        )
        pump(0.80)
        require(player.diagnosticScheduledCues == 2, "hidden key should pass the key filter and bgm should not, scheduled \(player.diagnosticScheduledCues)")
        player.stop()

        player.setAudibleKinds([.bgm, .key])
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: played,
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(
            waitUntil { player.diagnosticScheduledCues == 3 },
            "bgm was not scheduled with keys, scheduled \(player.diagnosticScheduledCues)"
        )
        player.stop()

        player.setAudibleKinds([.mine])
        player.playChart(
            documentData: document,
            chartDirectory: folder,
            notes: audible,
            timing: timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        pump(0.80)
        require(player.diagnosticScheduledCues == 0, "mine filter must not play the chart wav, scheduled \(player.diagnosticScheduledCues)")
        player.stop()

        let context = LegacyBmsonPreview.context(
            channelNames: ["key.wav", "bgm.wav"],
            channels: [
                (name: "key.wav", notes: [
                    note(x: 1, y: 0),
                    note(x: 1, y: 240, c: true)
                ]),
                (name: "bgm.wav", notes: [note(x: 0, y: 240)])
            ],
            initBpm: 120,
            bpmNotes: [],
            resolution: 240,
            chartDirectory: folder,
            playHereBeat: 0,
            title: "Snake",
            modeHint: "beat-14k",
            artist: "Ada",
            genre: "Drum",
            playLevel: 7,
            judgeRank: 100
        )
        require(context.notes.count == 2, "continuation is not a second trigger")
        require(context.notes.contains { $0.kind == .key && $0.wavToken == "01" && near($0.beat, 0) }, "x > 0 is key")
        require(context.notes.contains { $0.kind == .bgm && $0.wavToken == "02" && near($0.beat, 1) }, "x <= 0 is bgm")
        require(context.chartDirectory?.path == folder.path, "bga directory stays the chart directory")
        let song = String(decoding: context.documentData, as: UTF8.self)
        require(song.contains("#TITLE Snake") && song.contains("#ARTIST Ada") && song.contains("#GENRE Drum"), "bmson info is in the preview text")
        require(song.contains("#PLAYLEVEL 7") && song.contains("#PLAYER 3") && song.contains("#JUDGERANK 100"), "level, double player and judge rank are separate headers")
        require(!song.contains("#RANK ") && !song.contains("\n#RANK") && !song.hasPrefix("#RANK"), "judge rank 100 is not a BMS rank")
        require(!song.contains("#VOLWAV") && !song.contains("#PATH_WAV") && !song.contains("#BMP"), "volwav and bga are not invented")
        require(LegacyBmsonPreview.previewPlayerHeader(modeHint: "beat-7k-battle") == 2, "explicit battle is player 2")
        require(LegacyBmsonPreview.previewPlayerHeader(modeHint: "beat-10k") == 3, "10k double is player 3")
        require(LegacyBmsonPreview.previewPlayerHeader(modeHint: "popn-9k") == nil, "popn is outside the 5/7/10/14 skin")
        require(LegacyBmsonPreview.previewPlayerHeader(modeHint: "keyboard-36k") == nil, "36k is not given a fake playable player")
        let battle = String(decoding: LegacyBmsonPreview.previewDocumentData(wavTable: [:], modeHint: "beat-5k-battle"), as: UTF8.self)
        require(battle.contains("#PLAYER 2") && !battle.contains("#PLAYER 3"), "battle preview text is player 2")
        let popn = String(decoding: LegacyBmsonPreview.previewDocumentData(wavTable: ["01": "key.wav"], title: "Pop", modeHint: "popn-9k"), as: UTF8.self)
        require(popn.contains("#TITLE Pop") && popn.contains("#WAV01 key.wav") && !popn.contains("#PLAYER"), "unsupported mode keeps the title and omits player")

        player.setAudibleKinds([.key])
        player.playChart(
            documentData: context.documentData,
            chartDirectory: context.chartDirectory,
            notes: context.notes,
            timing: context.timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(player.diagnosticCueCount == 2, "bmson context has the key and the bgm cue")
        require(
            waitUntil { player.soundingSampleCount >= 1 && player.diagnosticScheduledCues == 1 },
            "bmson key did not sound, scheduled \(player.diagnosticScheduledCues)"
        )
        pump(0.80)
        require(player.diagnosticScheduledCues == 1, "x <= 0 bgm is filtered when only keys are audible, scheduled \(player.diagnosticScheduledCues)")
        player.stop()

        player.setAudibleKinds([.bgm, .key])
        player.playChart(
            documentData: context.documentData,
            chartDirectory: context.chartDirectory,
            notes: context.notes,
            timing: context.timing,
            fromBeat: 0,
            visualEndBeat: 4
        )
        require(
            waitUntil { player.diagnosticScheduledCues == 2 },
            "bmson bgm did not schedule, scheduled \(player.diagnosticScheduledCues)"
        )
        player.stop()
    }

    private static func note(x: Int64, y: Int64, l: Int64 = 0, c: Bool = false) -> LegacyBmsonPreview.SoundNote {
        LegacyBmsonPreview.SoundNote(y: y, continueFlag: c, x: x, l: l)
    }

    private static func chart(
        notes: [LegacyBmsonPreview.SoundNote],
        resolution: Int = 240,
        modeHint: String = "beat-7k",
        barLines: [Int64] = []
    ) -> LegacyBmsonPreview.VisualChartMapping {
        LegacyBmsonPreview.visualChart(
            channels: [(name: "kick.wav", notes: notes)],
            resolution: resolution,
            modeHint: modeHint,
            barLines: barLines
        )
    }

    private static func event(
        _ channel: String,
        _ beat: Double,
        _ kind: String,
        line: Int,
        token: String,
        display: String,
        measure: Int = 0,
        numerator: Int64 = 0,
        denominator: Int64 = 1
    ) -> LegacyBmsonPreview.BmsPreviewEvent {
        LegacyBmsonPreview.BmsPreviewEvent(
            channel: channel,
            beat: beat,
            kind: kind,
            sourceLine: line,
            measure: measure,
            fractionNumerator: numerator,
            fractionDenominator: denominator,
            token: token,
            displayChannel: display
        )
    }

    private static func longNote(
        channel: String,
        display: String,
        startBeat: Double,
        endBeat: Double,
        startLine: Int,
        endLine: Int,
        token: String,
        endNumerator: Int64 = 0,
        endDenominator: Int64 = 1
    ) -> LegacyBmsonPreview.BmsPreviewLongNote {
        LegacyBmsonPreview.BmsPreviewLongNote(
            channel: channel,
            start: LegacyBmsonPreview.BmsPreviewEndpoint(
                measure: 0,
                fractionNumerator: 0,
                fractionDenominator: 1,
                beat: startBeat,
                token: token,
                sourceLine: startLine
            ),
            end: LegacyBmsonPreview.BmsPreviewEndpoint(
                measure: 0,
                fractionNumerator: endNumerator,
                fractionDenominator: endDenominator,
                beat: endBeat,
                token: token,
                sourceLine: endLine
            ),
            displayChannel: display
        )
    }

    private static func paddedMeasures(count: Int) -> [LegacyBmsonPreview.BmsPreviewMeasure] {
        (0..<count).map { index in
            LegacyBmsonPreview.BmsPreviewMeasure(start: Double(index) * 4, length: 4)
        }
    }

    private static func contains(_ notes: [PreviewVisualNote], lane: String, start: Double, end: Double) -> Bool {
        notes.contains { $0.laneID == lane && near($0.startBeat, start) && near($0.endBeat, end) }
    }

    private static func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.000_001
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

    private static func toneWAV(duration: Double, sampleRate: Int = 44_100) -> Data {
        let frames = max(1, Int(duration * Double(sampleRate)))
        let dataSize = frames * 2
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
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        appendASCII("data")
        append32(UInt32(dataSize))
        for index in 0..<frames {
            let angle = 2 * Double.pi * 440 * Double(index) / Double(sampleRate)
            let sample = UInt16(bitPattern: Int16(sin(angle) * 6000))
            append16(sample)
        }
        return Data(bytes)
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
