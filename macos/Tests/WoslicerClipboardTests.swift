import Foundation

@main
struct WoslicerClipboardTests {
    static func main() {
        testSecondsToVPosition()
        testNudgeSequenceStart()
        testEncodeSequentialBGM()
        testEncodeFFDefinition()
        testEncodeSequenceStart()
        testDecodeObjectMarks()
        testDecodeIBMSCMarks()
        testRoundtripAddsImplicitZero()
        testRejectsNonPositiveBPM()
        testRejectsUnknownClipboard()
        print("WoslicerClipboardTests passed")
    }

    /// 工作规则：`vpos = seconds * BPM / 60 * 48`。120 BPM 的 1 秒是 96。
    private static func testSecondsToVPosition() {
        require(abs(WoslicerClipboard.vPosition(seconds: 1, bpm: 120) - 96) < 1e-9, "1s at 120")
        require(abs(WoslicerClipboard.seconds(vPosition: 96, bpm: 120) - 1) < 1e-9, "96 vpos is 1s")
        require(abs(WoslicerClipboard.vPosition(seconds: 0.5, bpm: 120) - 48) < 1e-9, "one beat")
    }

    /// `[A]` 加 1，`[S]` 减 1。夹在 1…1295，对上三十六进制 `01`…`ZZ`。
    private static func testNudgeSequenceStart() {
        require(WoslicerClipboard.nudgeSequenceStart(1, delta: -1) == 1, "floor")
        require(WoslicerClipboard.nudgeSequenceStart(1295, delta: 1) == 1295, "ceiling")
        require(WoslicerClipboard.nudgeSequenceStart(5, delta: 1) == 6, "A")
        require(WoslicerClipboard.nudgeSequenceStart(5, delta: -1) == 4, "S")
    }

    /// 裁断线 `1.0` 会补 `0`。B 列 ident 是 `101`。连号从 1 起。
    private static func testEncodeSequentialBGM() {
        let text = WoslicerClipboard.encode(marks: [1.0], bpm: 120)
        require(
            text == "BMSE ClipBoard Object Data Format\r\n101000000001\r\n101000000962",
            "two BGM notes at 0 and 96"
        )
        let payload = LegacyClipboard.decode(text ?? "")
        require(payload?.format == .bmseObject, "object header")
        require(payload?.notes.count == 2, "two notes")
        require(payload?.notes[0].columnIndex == 27, "B1")
        require(payload?.notes[0].value == 10000, "01")
        require(payload?.notes[1].value == 20000, "02")
        require(abs((payload?.notes[1].vPosition ?? 0) - 96) < 1e-9, "1s")
    }

    /// `[N]` 打开时两条都写 `FF`（十进制 555）。位置仍按裁断线。
    private static func testEncodeFFDefinition() {
        let text = WoslicerClipboard.encode(marks: [1.0], bpm: 120, ffDefinition: true)
        require(
            text == "BMSE ClipBoard Object Data Format\r\n10100000000555\r\n10100000096555",
            "FF is 555"
        )
        require(LegacyClipboard.tokenValue("FF") == 5_550_000, "FF token")
        let payload = LegacyClipboard.decode(text ?? "")
        require(payload?.notes.allSatisfy { $0.value == 5_550_000 } == true, "both FF")
    }

    /// `[A][S]` 改起点。10 起是 `0A`、`0B`，Object 值是 10、11。
    private static func testEncodeSequenceStart() {
        let text = WoslicerClipboard.encode(marks: [1.0], bpm: 120, sequenceStart: 10)
        require(
            text == "BMSE ClipBoard Object Data Format\r\n1010000000010\r\n1010000009611",
            "start 10"
        )
        let payload = LegacyClipboard.decode(text ?? "")
        require(payload?.notes[0].value == 100_000, "0A")
        require(payload?.notes[1].value == 110_000, "0B")
        require(LegacyClipboard.token(fromValue: 100_000) == "0A", "token 0A")
    }

    private static func testDecodeObjectMarks() {
        let marks = WoslicerClipboard.decodeMarks(
            "BMSE ClipBoard Object Data Format\r\n1010000000001\r\n1010000009602",
            bpm: 120
        )
        require(marks?.count == 2, "two marks")
        require(abs((marks?[0] ?? -1) - 0) < 1e-9 && abs((marks?[1] ?? -1) - 1) < 1e-9, "0 and 1s")
    }

    private static func testDecodeIBMSCMarks() {
        let marks = WoslicerClipboard.decodeMarks(
            "iBMSC Clipboard Data\r\n27 0 10000 0 0 0\r\n27 96 20000 0 0 0",
            bpm: 120
        )
        require(marks?.count == 2, "iBMSC two marks")
        require(abs((marks?[1] ?? -1) - 1) < 1e-9, "96 vpos is 1s")
    }

    private static func testRoundtripAddsImplicitZero() {
        let text = WoslicerClipboard.encode(marks: [1.0], bpm: 120)
        let marks = WoslicerClipboard.decodeMarks(text ?? "", bpm: 120)
        require(marks == [0, 1.0] || (marks?.count == 2 && abs((marks?[0] ?? 1) ) < 1e-9), "keeps 0")
        let again = WoslicerClipboard.encode(marks: marks ?? [], bpm: 120)
        require(again == text, "stable after import")
    }

    private static func testRejectsNonPositiveBPM() {
        require(WoslicerClipboard.encode(marks: [1.0], bpm: 0) == nil, "bpm 0")
        require(WoslicerClipboard.encode(marks: [1.0], bpm: -120) == nil, "negative bpm")
        require(WoslicerClipboard.decodeMarks("BMSE ClipBoard Object Data Format\r\n1010000000001", bpm: 0) == nil,
                "decode bpm 0")
    }

    private static func testRejectsUnknownClipboard() {
        require(WoslicerClipboard.decodeMarks("not a clipboard", bpm: 120) == nil, "unknown")
        require(WoslicerClipboard.decodeMarks("BMSE ClipBoard Object Data Format", bpm: 120) == nil, "header only")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
