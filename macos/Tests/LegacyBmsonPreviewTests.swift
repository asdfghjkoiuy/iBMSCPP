import Foundation

@main
struct LegacyBmsonPreviewTests {
    static func main() {
        testWavTableUsesChannelIndex()
        testEncodeWavTableRoundtrips()
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
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
