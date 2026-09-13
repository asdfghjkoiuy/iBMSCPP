import Darwin
import Foundation

@main
struct LegacyClipboardSessionTests {
    @MainActor
    static func main() {
        do {
            try run()
            print("LegacyClipboardSessionTests passed")
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func run() throws {
        try testPasteShortNoteAtInjectedBaseZero()
        try testPasteAtScrollZeroLandsOnMeasureOne()
        try testCopySelectedShortNote()
        try testPasteHiddenNoteWritesHiddenChannel()
        try testCutRemovesOriginalAndKeepsClipboard()
        try testPasteBPMStopAndScroll()
        try testCopyIntegerBPMUsesHexToken()
        try testPasteNTLongNote()
        try testCopyScrollUsesDecimal()
        try testNTInputRoundtripKeepsPairedLong()
        try testNTInputLnObjPairStaysEditable()
    }

    /// 夹具一行 `6 0 10000 0 0 0`，基准 0 → `#00011:01`。
    @MainActor
    private static func testPasteShortNoteAtInjectedBaseZero() throws {
        let session = try DocumentSession(data: Data())
        try session.pasteClipboard("iBMSC Clipboard Data\r\n6 0 10000 0 0 0", baseVPosition: 0, ntInput: false)
        require(
            session.chartSnapshot.events.contains {
                $0.channel == "11" && $0.token == "01" && $0.measure == 0 && $0.fractionNumerator == 0
            },
            "BMSE clipboard at base 0 writes 11 at measure 0"
        )
    }

    /// 滚动为 0 时 `MeasureBottom(1) = 192`，落到小节 1。
    @MainActor
    private static func testPasteAtScrollZeroLandsOnMeasureOne() throws {
        let session = try DocumentSession(data: Data())
        try session.pasteClipboard(
            "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
            baseVPosition: LegacyClipboard.pasteBaseVPosition(scrollVS: 0),
            ntInput: false
        )
        require(
            session.chartSnapshot.events.contains {
                $0.channel == "11" && $0.token == "01" && $0.measure == 1 && $0.fractionNumerator == 0
            },
            "scroll 0 pastes onto measure 1"
        )
    }

    /// `#00011:01` 复制成 BMSE 文本，原音留下。
    @MainActor
    private static func testCopySelectedShortNote() throws {
        let session = try DocumentSession(data: Data("#00011:01\n".utf8))
        guard let event = session.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("copy fixture is missing channel 11")
        }
        let text = session.copyClipboard(events: [event], longNotes: [], ntInput: false)
        require(
            text == "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
            "copy writes the iBMSC BMSE line"
        )
        require(
            session.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
            "copy leaves the original note"
        )
    }

    /// Hidden 行写回通道 `31`。
    @MainActor
    private static func testPasteHiddenNoteWritesHiddenChannel() throws {
        let session = try DocumentSession(data: Data())
        try session.pasteClipboard("iBMSC Clipboard Data\r\n6 0 10000 0 -1 0", baseVPosition: 0, ntInput: false)
        require(
            session.chartSnapshot.events.contains { $0.channel == "31" && $0.token == "01" },
            "hidden flag writes channel 31"
        )
    }

    /// Cut = Copy + Remove。
    @MainActor
    private static func testCutRemovesOriginalAndKeepsClipboard() throws {
        let session = try DocumentSession(data: Data("#00011:01\n".utf8))
        guard let event = session.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("cut fixture is missing channel 11")
        }
        let text = try session.cutClipboard(events: [event], longNotes: [], ntInput: false)
        require(
            text == "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
            "cut copies the same BMSE line"
        )
        require(
            session.chartSnapshot.events.filter { $0.channel == "11" && $0.token != "00" }.isEmpty,
            "cut removes the original note"
        )
    }

    /// 列 BPM / STOP / SCROLL 按 `Value / 10000` 写回时值事件。
    @MainActor
    private static func testPasteBPMStopAndScroll() throws {
        let session = try DocumentSession(data: Data())
        try session.pasteClipboard("iBMSC Clipboard Data\r\n2 0 1400000 0 0 0", baseVPosition: 0, ntInput: false)
        require(
            session.chartSnapshot.events.contains { $0.channel == "03" && $0.token == "8C" },
            "BPM 140 pastes onto channel 03"
        )
        try session.pasteClipboard("iBMSC Clipboard Data\r\n3 0 480000 0 0 0", baseVPosition: 0, ntInput: false)
        require(
            session.timingSnapshot.events.contains { $0.channel == "09" && $0.valueDecimal == "48" },
            "STOP 48 pastes onto channel 09"
        )
        try session.pasteClipboard("iBMSC Clipboard Data\r\n1 0 5000 0 0 0", baseVPosition: 0, ntInput: false)
        require(
            session.chartSnapshot.events.contains { $0.channel == "SC" && $0.kind == "scroll" },
            "SCROLL 0.5 pastes onto channel SC"
        )
        let saved = try saveAndRead(session)
        let text = String(decoding: saved, as: UTF8.self)
        require(text.contains("#SCROLL") && text.contains("0.5"), "SCROLL 0.5 writes #SCROLL 0.5")
    }

    /// 通道 `03` 的标签是十六进制，不能按三十六进制去乘 10000。
    @MainActor
    private static func testCopyIntegerBPMUsesHexToken() throws {
        let session = try DocumentSession(data: Data())
        try session.insertTimingEvent(measure: 0, channel: "03", gridSlot: 0, gridDivision: 16, decimal: "140")
        guard let event = session.chartSnapshot.events.first(where: { $0.channel == "03" }) else {
            throw TestFailure("BPM copy fixture is missing channel 03")
        }
        let text = session.copyClipboard(events: [event], longNotes: [], ntInput: false)
        require(
            text == "iBMSC Clipboard Data\r\n2 0 1400000 0 0 0",
            "copy of BPM 140 writes value 1400000"
        )
    }

    /// `#SCROLL01 0.5` 复制成 Value 5000，不能按标签 `01` 走三十六进制。
    @MainActor
    private static func testCopyScrollUsesDecimal() throws {
        let session = try DocumentSession(data: Data())
        try session.insertTimingEvent(measure: 0, channel: "SC", gridSlot: 0, gridDivision: 16, decimal: "0.5")
        guard let event = session.chartSnapshot.events.first(where: { $0.channel == "SC" }) else {
            throw TestFailure("SCROLL copy fixture is missing channel SC")
        }
        let text = session.copyClipboard(events: [event], longNotes: [], ntInput: false)
        require(
            text == "iBMSC Clipboard Data\r\n1 0 5000 0 0 0",
            "copy of SCROLL 0.5 writes value 5000"
        )
    }

    /// NT 头第四列是 Length。96 vpos 是半小节。
    @MainActor
    private static func testPasteNTLongNote() throws {
        let session = try DocumentSession(data: Data())
        try session.pasteClipboard("iBMSC Clipboard Data xNT\r\n6 0 10000 96 0 0", baseVPosition: 0, ntInput: true)
        require(session.longNoteSnapshot.notes.count == 1, "NT length 96 writes one long note")
        require(session.longNoteSnapshot.notes[0].channel == "51", "A2 long writes 51")
        require(
            session.longNoteSnapshot.notes[0].start.fractionNumerator == 0
                && session.longNoteSnapshot.notes[0].end.fractionNumerator == 1
                && session.longNoteSnapshot.notes[0].end.fractionDenominator == 2,
            "96 vpos is the halfway point of a default measure"
        )
    }

    /// `#00051:01` + `#00151:01` 来回切不要把谱拆坏，可撤销。不对 `51` 调 `insert_note`。
    @MainActor
    private static func testNTInputRoundtripKeepsPairedLong() throws {
        let session = try DocumentSession(data: Data("#00051:01\n#00151:01\n#00012:02\n".utf8))
        require(session.longNoteSnapshot.notes.count == 1, "fixture is one 51 pair")
        require(session.chartSnapshot.editable, "51 pair starts editable")
        try session.convertNTInput(becomeNT: false)
        require(session.longNoteSnapshot.notes.count == 1, "BMSE convert keeps the pair")
        require(session.longNoteSnapshot.notes[0].channel == "51", "pair stays on 51")
        require(
            session.chartSnapshot.events.contains { $0.channel == "12" && $0.token == "02" },
            "short 12 survives BMSE convert"
        )
        require(session.chartSnapshot.editable, "BMSE convert stays editable")
        try session.convertNTInput(becomeNT: true)
        require(session.longNoteSnapshot.notes.count == 1, "NT convert keeps the pair")
        require(
            session.longNoteSnapshot.notes[0].channel == "51"
                && session.longNoteSnapshot.notes[0].start.beat == 0
                && session.longNoteSnapshot.notes[0].end.beat == 4,
            "roundtrip keeps measure 0 to 1"
        )
        require(
            session.chartSnapshot.events.contains { $0.channel == "12" && $0.token == "02" },
            "short 12 survives the roundtrip"
        )
        require(session.chartSnapshot.editable, "roundtrip stays editable")
        let undoConvertBack = try session.undo()
        require(undoConvertBack, "second convert is one undo")
        require(session.longNoteSnapshot.notes.count == 1, "undo keeps the pair")
        let undoConvertOut = try session.undo()
        require(undoConvertOut, "first convert is one undo")
        require(
            session.longNoteSnapshot.notes.count == 1
                && session.longNoteSnapshot.notes[0].channel == "51",
            "undo restores the original pair"
        )
        require(
            session.chartSnapshot.events.contains { $0.channel == "12" && $0.token == "02" },
            "undo restores the short"
        )
    }

    /// `#LNOBJ` 配对写回后仍可编辑，不能变成只读。
    @MainActor
    private static func testNTInputLnObjPairStaysEditable() throws {
        let session = try DocumentSession(data: Data("#LNOBJ AA\n#00011:01\n#00111:AA\n".utf8))
        require(session.longNoteSnapshot.notes.count == 1, "LnObj fixture is one pair")
        require(session.chartSnapshot.editable, "LnObj pair starts editable")
        try session.convertNTInput(becomeNT: false)
        require(session.chartSnapshot.editable, "BMSE convert of LnObj stays editable")
        require(session.longNoteSnapshot.notes.count == 1, "LnObj convert keeps one long")
        try session.convertNTInput(becomeNT: true)
        require(session.chartSnapshot.editable, "NT convert of LnObj stays editable")
        require(session.longNoteSnapshot.notes.count == 1, "LnObj roundtrip keeps one long")
        require(
            session.longNoteSnapshot.notes[0].encoding == "lnobj"
                && session.longNoteSnapshot.notes[0].channel == "11",
            "LnObj pair stays on the visible channel"
        )
    }

    @MainActor
    private static func saveAndRead(_ session: DocumentSession) throws -> Data {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibmsnative-clipboard-\(UUID().uuidString).bms")
        defer { try? FileManager.default.removeItem(at: output) }
        try session.save(to: output)
        return try Data(contentsOf: output)
    }
}

private struct TestFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
