import Foundation

@main
struct BmsonChartMappingTests {
    static func main() {
        testSevenKeyLanes()
        testViewModeLanes()
        testPulseAndGrid()
        testMeasuresFromLine()
        testVisibleFixtureNote()
        testVisibleLongNote()
        testBgmLane()
        testNoteIdentity()
        testNoteActiveChannel()
        testLoadKindBmson()
        testVisibleTimingNotes()
        testVisibleBgaNotes()
        testStopDisplayUnits()
        testSoundLaneNotes()
        print("BmsonChartMappingTests passed")
    }

    private static func testSevenKeyLanes() {
        require(BmsonChartMapping.channel(forLaneX: 8, modeHint: "beat-7k") == "16", "scratch x=8 is 16")
        require(BmsonChartMapping.channel(forLaneX: 1, modeHint: "beat-7k") == "11", "key x=1 is 11")
        require(BmsonChartMapping.channel(forLaneX: 7, modeHint: "beat-7k") == "19", "key x=7 is 19")
        require(BmsonChartMapping.laneX(forChannel: "16", modeHint: "beat-7k") == 8, "16 writes x=8")
        require(BmsonChartMapping.laneX(forChannel: "12", modeHint: "beat-7k") == 2, "12 writes x=2")
        require(BmsonChartMapping.channel(forLaneX: 9, modeHint: "beat-7k") == nil, "7k has no x=9")
        require(BmsonChartMapping.channel(forLaneX: 9, modeHint: "beat-10k") == "21", "10k x=9 is 21")
        require(BmsonChartMapping.wavToken(channelIndex: 0) == "01", "first channel is 01")
        require(BmsonChartMapping.channelIndex(wavToken: "01") == 0, "01 is channel 0")
    }

    /// 对照 `ViewMode.cpp` 车道和共用 8+8 列。
    private static func testViewModeLanes() {
        require(BmsonChartMapping.channel(forLaneX: 6, modeHint: "beat-5k") == nil, "5k has no x=6")
        require(BmsonChartMapping.channel(forLaneX: 8, modeHint: "popn-5k") == nil, "pop 5k has no scratch")
        require(BmsonChartMapping.channel(forLaneX: 6, modeHint: "popn-9k") == "18", "pop 9k x=6 is 18")
        require(BmsonChartMapping.channel(forLaneX: 8, modeHint: "popn-9k") == "16", "pop 9k x=8 uses column 16")
        require(BmsonChartMapping.channel(forLaneX: 9, modeHint: "popn-9k") == "21", "pop 9k x=9 uses column 21")
        require(BmsonChartMapping.laneX(forChannel: "16", modeHint: "popn-9k") == 8, "column 16 writes pop key 8")
        require(
            BmsonChartMapping.channel(forLaneX: 9, modeHint: "beat-7k-battle") == "21",
            "7k-battle is 14k"
        )
        require(
            BmsonChartMapping.channel(forLaneX: 9, modeHint: "beat-5k-battle") == "21",
            "5k-battle is 10k"
        )
        require(BmsonChartMapping.channel(forLaneX: 6, modeHint: "") == "18", "empty hint is 7k")
        require(BmsonChartMapping.channel(forLaneX: 1, modeHint: "mystery") == "16", "Plain x=1 is column 16")
        require(BmsonChartMapping.channel(forLaneX: 17, modeHint: "keyboard-24k") == nil, "24k x=17 stays off")
        require(BmsonChartMapping.channel(forLaneX: 27, modeHint: "keyboard-24k-double") == "21", "24k double P2")
        let measures = BmsonChartMapping.measures(lines: [], lastPulse: 0, resolution: 240)
        let notes = BmsonChartMapping.visibleNotes(
            channels: [
                BmsonChartMapping.ChannelInput(
                    name: "pop.wav",
                    notes: [
                        BmsonChartMapping.NoteInput(x: 8, y: 0, l: 0, c: false),
                        BmsonChartMapping.NoteInput(x: 9, y: 0, l: 0, c: false)
                    ]
                )
            ],
            measures: measures,
            resolution: 240,
            modeHint: "popn-9k"
        )
        require(notes.map(\.channel) == ["16", "21"], "popn-9k x=8/9 are visible")
    }

    private static func testPulseAndGrid() {
        require(BmsonChartMapping.beat(pulse: 0, resolution: 240) == 0, "pulse 0")
        require(BmsonChartMapping.beat(pulse: 240, resolution: 240) == 1, "one beat")
        require(BmsonChartMapping.pulse(beat: 1, resolution: 240) == 240, "beat 1")
        require(
            BmsonChartMapping.pulse(measureStart: 0, slot: 0, division: 4, resolution: 240) == 0,
            "slot 0"
        )
        require(
            BmsonChartMapping.pulse(measureStart: 0, slot: 1, division: 4, resolution: 240) == 240,
            "slot 1 is one beat"
        )
    }

    private static func testMeasuresFromLine() {
        let measures = BmsonChartMapping.measures(lines: [240], lastPulse: 0, resolution: 240)
        require(measures.count > 1, "line plus trailing measures")
        require(measures[0].start == 0 && measures[0].length == 1, "first measure ends at line 240")
        require(measures[1].start == 1 && measures[1].length == 4, "then 4-beat measures")
    }

    private static func testVisibleFixtureNote() {
        let measures = BmsonChartMapping.measures(lines: [240], lastPulse: 0, resolution: 240)
        let notes = BmsonChartMapping.visibleNotes(
            channels: [
                BmsonChartMapping.ChannelInput(
                    name: "kick.wav",
                    notes: [BmsonChartMapping.NoteInput(x: 1, y: 0, l: 0, c: false)]
                )
            ],
            measures: measures,
            resolution: 240,
            modeHint: "beat-7k"
        )
        require(notes.count == 1, "one visible note")
        require(notes[0].channel == "11" && notes[0].beat == 0, "x=1 y=0 on channel 11")
        require(notes[0].token == "kick.wav" && notes[0].kind == "normal", "name and short")
        require(notes[0].measure == 0, "pulse 0 is measure 0")
    }

    private static func testVisibleLongNote() {
        let measures = BmsonChartMapping.measures(lines: [], lastPulse: 720, resolution: 240)
        let notes = BmsonChartMapping.visibleNotes(
            channels: [
                BmsonChartMapping.ChannelInput(
                    name: "synth.wav",
                    notes: [BmsonChartMapping.NoteInput(x: 2, y: 480, l: 240, c: true)]
                )
            ],
            measures: measures,
            resolution: 240,
            modeHint: "beat-7k"
        )
        require(notes.count == 1, "one long note")
        require(notes[0].channel == "12" && notes[0].beat == 2, "x=2 y=480 on channel 12")
        require(notes[0].kind == "longNote" && notes[0].lengthBeats == 1, "one-beat LN")
        require(notes[0].identity == BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0), "identity")
    }

    /// BmsONE Skin：`x=0` 是 BGM，主编辑器画在通道 `01`。
    private static func testBgmLane() {
        require(BmsonChartMapping.channel(forLaneX: 0, modeHint: "beat-7k") == "01", "x=0 is BGM 01")
        require(BmsonChartMapping.laneX(forChannel: "01", modeHint: "beat-7k") == 0, "01 writes x=0")
        require(BmsonChartMapping.laneX(forChannel: "B1", modeHint: "beat-7k") == 0, "B1 writes x=0")
        let measures = BmsonChartMapping.measures(lines: [], lastPulse: 0, resolution: 240)
        let notes = BmsonChartMapping.visibleNotes(
            channels: [
                BmsonChartMapping.ChannelInput(
                    name: "bgm.wav",
                    notes: [BmsonChartMapping.NoteInput(x: 0, y: 0, l: 0, c: false)]
                )
            ],
            measures: measures,
            resolution: 240,
            modeHint: "beat-7k"
        )
        require(notes.count == 1 && notes[0].channel == "01" && notes[0].beat == 0, "BGM note is visible")
    }

    private static func testNoteIdentity() {
        let identity = BmsonChartMapping.noteIdentity(channelIndex: 2, noteIndex: 4)
        let address = BmsonChartMapping.noteAddress(identity: identity)
        require(address?.channelIndex == 2 && address?.noteIndex == 4, "decode identity")
        require(BmsonChartMapping.noteAddress(identity: 0) == nil, "zero is not a note")
    }

    private static func testNoteActiveChannel() {
        let first = BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
        let other = BmsonChartMapping.noteIdentity(channelIndex: 1, noteIndex: 0)
        require(BmsonChartMapping.noteIsActiveChannel(identity: first, currentChannel: 0), "own channel")
        require(!BmsonChartMapping.noteIsActiveChannel(identity: other, currentChannel: 0), "other channel")
        require(
            BmsonChartMapping.noteIsActiveChannel(
                identity: BmsonChartMapping.timingIdentity(isStop: false, index: 0),
                currentChannel: 1
            ),
            "timing is not a sound channel"
        )
    }

    private static func testLoadKindBmson() {
        require(LegacyLoadProgress.kind(path: "demo.bmson") == .bmson, "kind bmson")
        require(LegacyLoadProgress.kind(path: "demo.BMSON") == .bmson, "kind lowercases")
        require(LegacyLoadProgress.extensionMatches("demo.bmson"), "drop accepts .bmson")
        require(!LegacyLoadProgress.extensionMatches("demo.BMSON"), "IndexOf stays case-sensitive")
    }

    /// BPM 画在通道 `03`，STOP 画在 `09`。STOP 的字是 BMS 单位：240 脉冲 → `48`。
    private static func testVisibleTimingNotes() {
        let measures = BmsonChartMapping.measures(lines: [], lastPulse: 480, resolution: 240)
        let notes = BmsonChartMapping.visibleTiming(
            bpmNotes: [(y: 240, v: 140)],
            stopNotes: [(y: 480, v: 240)],
            measures: measures,
            resolution: 240
        )
        require(notes.count == 2, "bpm and stop")
        require(notes[0].channel == "03" && notes[0].token == "140" && notes[0].kind == "bpm", "BPM caption")
        require(abs(notes[0].beat - 1) < 0.000_001, "BPM at beat 1")
        require(notes[1].channel == "09" && notes[1].token == "48" && notes[1].kind == "stop", "STOP caption")
        require(abs(notes[1].beat - 2) < 0.000_001, "STOP at beat 2")
    }

    private static func testVisibleBgaNotes() {
        require(BmsonChartMapping.bmpToken(id: 0) == "00", "id 0 is 00")
        require(BmsonChartMapping.bmpToken(id: 1) == "01", "id 1 is 01")
        require(BmsonChartMapping.bmpId(token: "02") == 2, "02 is id 2")
        require(BmsonChartMapping.BgaLane.parse(channel: "04") == .bga, "04 is BGA")
        require(BmsonChartMapping.BgaLane.parse(channel: "07") == .layer, "07 is Layer")
        require(BmsonChartMapping.BgaLane.parse(channel: "06") == .poor, "06 is Poor")
        let measures = BmsonChartMapping.measures(lines: [], lastPulse: 960, resolution: 240)
        let notes = BmsonChartMapping.visibleBga(
            bgaEvents: [(y: 0, id: 1)],
            layerEvents: [(y: 960, id: 2)],
            poorEvents: [(y: 0, id: 0)],
            measures: measures,
            resolution: 240
        )
        require(notes.map(\.channel) == ["04", "07", "06"], "BGA / Layer / Poor")
        require(notes[0].token == "01" && notes[0].kind == "bga", "BGA token")
        require(notes[1].token == "02" && abs(notes[1].beat - 4) < 1e-12, "layer at beat 4")
        require(notes[2].token == "00" && notes[2].kind == "poor", "miss default")
    }

    /// 写入 `48` 存成 240 脉冲；`0.5` 拍是 `24`。
    private static func testStopDisplayUnits() {
        require(abs(BmsonChartMapping.stopPulses(displayValue: 48, resolution: 240) - 240) < 0.000_001, "48 → 240")
        require(abs(BmsonChartMapping.stopDisplayValue(pulses: 240, resolution: 240) - 48) < 0.000_001, "240 → 48")
        require(BmsonChartMapping.formatTiming(140) == "140", "integer BPM")
        require(BmsonChartMapping.formatTiming(140.5) == "140.5", "fraction BPM")
    }

    /// 声道列画该道全部音，包括演奏区画不到的 `x`。长音也只记短记号。
    private static func testSoundLaneNotes() {
        let measures = BmsonChartMapping.measures(lines: [], lastPulse: 480, resolution: 240)
        let channels = [
            BmsonChartMapping.ChannelInput(
                name: "kick.wav",
                notes: [
                    BmsonChartMapping.NoteInput(x: 1, y: 0, l: 0, c: false),
                    BmsonChartMapping.NoteInput(x: 0, y: 240, l: 240, c: true)
                ]
            ),
            BmsonChartMapping.ChannelInput(
                name: "hat.wav",
                notes: [BmsonChartMapping.NoteInput(x: 9, y: 480, l: 0, c: false)]
            )
        ]
        let notes = BmsonChartMapping.soundLaneNotes(
            channels: channels,
            measures: measures,
            resolution: 240
        )
        require(notes.map(\.channel) == ["CH0", "CH0", "CH1"], "one column per channel")
        require(notes[0].identity == 1 && notes[1].identity == 2, "same identities as play notes")
        require(notes[2].identity == 1_000_003 + 1, "second channel stride")
        require(abs(notes[1].beat - 1) < 1e-12 && notes[1].lengthBeats == 0, "long note is a short mark")
        require(notes[2].token == "hat.wav", "token is file name")
        let hidden = BmsonChartMapping.soundLaneNotes(
            channels: channels,
            measures: measures,
            resolution: 240,
            shown: [false, true]
        )
        require(hidden.map(\.channel) == ["CH1"], "Show Hit omits collapsed lanes")
        require(BmsonChartMapping.channel(forLaneX: 9, modeHint: "beat-7k") == nil, "7k still hides x=9")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
