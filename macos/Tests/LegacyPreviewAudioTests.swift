import Foundation

@main
struct LegacyPreviewAudioTests {
    static func main() {
        testParseWavDefinitions()
        testScheduleHitsAt120BPM()
        testFileNameLookupAndPlayHere()
        testStopAddsCoreDuration()
        testCheckFilenameSwapsWavAndOgg()
        testBeatAfterSeconds()
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

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
