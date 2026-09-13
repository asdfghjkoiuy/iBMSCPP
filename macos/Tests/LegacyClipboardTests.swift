import Foundation

@main
struct LegacyClipboardTests {
    static func main() {
        testTokenValueUsesC36to10Times10000()
        testEncodeBMSEShortNote()
        testEncodeNTUsesLengthAndXNTHeader()
        testEncodeSubtractsMinMeasureBottom()
        testEncodeWritesMinusOneForTrueFlags()
        testDecodeBMSERoundtrip()
        testDecodeBMSEObjectFormat()
        testEncodeObjectRoundtrip()
        testEncodeObjectBGMChannel()
        testPasteBaseAtScrollZeroIsMeasureOne()
        testWriteChannelKeepsHiddenMineAndLong()
        testWriteChannelMapsBColumns()
        testWriteChannelRoutesBPMAndSCROLL()
        testNumericValueFromDecimal()
        print("LegacyClipboardTests passed")
    }

    /// `Utilities.C36to10` × 10000。WAV `01` → 10000。
    private static func testTokenValueUsesC36to10Times10000() {
        require(LegacyClipboard.tokenValue("01") == 10000, "WAV 01 is 10000")
        require(LegacyClipboard.tokenValue("0A") == 100_000, "WAV 0A is 100000")
        require(LegacyClipboard.token(fromValue: 10000) == "01", "10000 writes back as 01")
    }

    /// `CopyNotes` BMSE 行：`ColumnIndex VPosition Value Long Hidden Landmine`。
    private static func testEncodeBMSEShortNote() {
        let text = LegacyClipboard.encode(
            [
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ],
            ntInput: false
        )
        require(
            text == "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
            "BMSE clipboard is header plus one space-separated line"
        )
    }

    /// NT 打开时头是 `iBMSC Clipboard Data xNT`，第四列是 Length。
    private static func testEncodeNTUsesLengthAndXNTHeader() {
        let text = LegacyClipboard.encode(
            [
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 96,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ],
            ntInput: true
        )
        require(
            text == "iBMSC Clipboard Data xNT\r\n6 0 10000 96 0 0",
            "NT clipboard stores Length, not the LongNote flag"
        )
    }

    /// 相对时间减去已选里最小小节的 `MeasureBottom`。
    private static func testEncodeSubtractsMinMeasureBottom() {
        let text = LegacyClipboard.encode(
            [
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 192,
                    value: 10000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ],
            ntInput: false
        )
        require(
            text == "iBMSC Clipboard Data\r\n6 0 10000 0 0 0",
            "a note at vpos 192 copies as relative 0"
        )
    }

    /// VB.NET `CInt(True)` 是 -1。粘贴时 `CBool(Val(...))` 把非 0 当成 True。
    private static func testEncodeWritesMinusOneForTrueFlags() {
        let text = LegacyClipboard.encode(
            [
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: true,
                    hidden: true,
                    landmine: true
                )
            ],
            ntInput: false
        )
        require(
            text == "iBMSC Clipboard Data\r\n6 0 10000 -1 -1 -1",
            "True flags encode as -1"
        )
    }

    /// 解码后加上粘贴基准，再写回通道。
    private static func testDecodeBMSERoundtrip() {
        let payload = LegacyClipboard.decode("iBMSC Clipboard Data\r\n6 0 10000 0 0 0")
        require(payload?.format == .ibmscBMSE, "BMSE header")
        require(payload?.notes.count == 1, "one note")
        require(payload?.notes.first?.columnIndex == 6, "column A2")
        require(payload?.notes.first?.value == 10000, "token 01")
        let placed = LegacyClipboard.placed(payload?.notes ?? [], baseVPosition: 0)
        require(placed.first?.vPosition == 0, "injected base 0 keeps beat 0")
    }

    /// `BMSE ClipBoard Object Data Format`：`Mid` 切 3+1+7+值。
    private static func testDecodeBMSEObjectFormat() {
        let payload = LegacyClipboard.decode("BMSE ClipBoard Object Data Format\r\n0110000000001")
        require(payload?.format == .bmseObject, "BMSE object header")
        require(payload?.notes.first?.columnIndex == 6, "011 maps to column A2")
        require(payload?.notes.first?.vPosition == 0, "seven-digit position 0")
        require(payload?.notes.first?.value == 10000, "trailing 1 is token 01")
        require(payload?.notes.first?.longNote == false, "attribute 0 is a short note")
    }

    /// 写出再读回：`011` 是 A2，属性 `0`，位置 7 位。
    private static func testEncodeObjectRoundtrip() {
        let note = LegacyClipboardNote(
            columnIndex: 6,
            vPosition: 0,
            value: 10000,
            length: 0,
            longNote: false,
            hidden: false,
            landmine: false
        )
        let text = LegacyClipboard.encodeObject([note])
        require(text == "BMSE ClipBoard Object Data Format\r\n011000000001", "A2 object line")
        let payload = LegacyClipboard.decode(text)
        require(payload?.format == .bmseObject, "object header")
        require(payload?.notes == [note], "roundtrip")
        let hidden = LegacyClipboardNote(
            columnIndex: 6,
            vPosition: 0,
            value: 10000,
            length: 0,
            longNote: false,
            hidden: true,
            landmine: false
        )
        require(
            LegacyClipboard.encodeObject([hidden]) == "BMSE ClipBoard Object Data Format\r\n011100000001",
            "attribute 1 is hidden"
        )
    }

    /// B1 的 BMSE 通道号是 `101`。
    private static func testEncodeObjectBGMChannel() {
        let note = LegacyClipboardNote(
            columnIndex: 27,
            vPosition: 96,
            value: 20000,
            length: 0,
            longNote: false,
            hidden: false,
            landmine: false
        )
        require(
            LegacyClipboard.encodeObject([note]) == "BMSE ClipBoard Object Data Format\r\n101000000962",
            "B1 at vpos 96 is 101…962"
        )
        let payload = LegacyClipboard.decode(LegacyClipboard.encodeObject([note]))
        require(payload?.notes.first?.columnIndex == 27, "B1")
        require(payload?.notes.first?.vPosition == 96, "96")
        require(payload?.notes.first?.value == 20000, "02")
    }

    /// `MeasureBottom(MeasureAtDisplacement(-xVS) + 1)`。滚动为 0 时落到小节 1。
    private static func testPasteBaseAtScrollZeroIsMeasureOne() {
        require(LegacyClipboard.pasteBaseVPosition(scrollVS: 0) == 192, "scroll 0 pastes at measure 1")
        require(LegacyClipboard.pasteBaseVPosition(scrollVS: -192) == 384, "scroll -192 pastes at measure 2")
    }

    /// `GetBMSChannelBy`：Long 优先于 Hidden，Hidden 优先于 Landmine。
    private static func testWriteChannelKeepsHiddenMineAndLong() {
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "11",
            "A2 short writes 11"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: false,
                    hidden: true,
                    landmine: false
                )
            ) == "31",
            "A2 hidden writes 31"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: true,
                    hidden: false,
                    landmine: false
                )
            ) == "51",
            "A2 long writes 51"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: true
                )
            ) == "D1",
            "A2 landmine writes D1"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 6,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: true,
                    hidden: true,
                    landmine: true
                )
            ) == "51",
            "Long wins over Hidden and Landmine"
        )
    }

    /// 所有 B 列在原版都写通道 `01`，这里用 `B1`/`B2` 区分行。
    private static func testWriteChannelMapsBColumns() {
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 27,
                    vPosition: 0,
                    value: 10000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "B1",
            "column 27 is B1"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 28,
                    vPosition: 0,
                    value: 20000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "B2",
            "column 28 is B2"
        )
    }

    /// `GetBMSChannelBy`：整数 1–255 走 `03`，256 或小数走 `08`，SCROLL 是 `SC`。
    private static func testWriteChannelRoutesBPMAndSCROLL() {
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 2,
                    vPosition: 0,
                    value: 1_400_000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "03",
            "BPM 140 writes channel 03"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 2,
                    vPosition: 0,
                    value: 2_560_000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "08",
            "BPM 256 writes channel 08"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 1,
                    vPosition: 0,
                    value: 5000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "SC",
            "column 1 writes SC"
        )
        require(
            LegacyClipboard.writeChannel(
                LegacyClipboardNote(
                    columnIndex: 3,
                    vPosition: 0,
                    value: 480_000,
                    length: 0,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            ) == "09",
            "STOP writes channel 09"
        )
    }

    /// 剪贴板数值是十进制 × 10000。
    private static func testNumericValueFromDecimal() {
        require(LegacyClipboard.numericValue("140") == 1_400_000, "BPM 140")
        require(LegacyClipboard.numericValue("0.5") == 5000, "SCROLL 0.5")
        require(LegacyClipboard.numericValue("-0.5") == -5000, "negative SCROLL")
        require(LegacyClipboard.decimal(fromValue: 1_400_000) == "140", "1400000 writes back as 140")
        require(LegacyClipboard.decimal(fromValue: 5000) == "0.5", "5000 writes back as 0.5")
        require(LegacyClipboard.decimal(fromValue: -5000) == "-0.5", "negative 5000 writes back as -0.5")
        require(LegacyClipboard.hexTokenValue("8C") == 1_400_000, "channel 03 token 8C is 140")
        require(LegacyClipboard.scrollDecimal(token: "01", in: "#SCROLL01 0.5\r\n") == "0.5",
                "SCROLL 01 is 0.5")
        require(LegacyClipboard.scrollDecimal(token: "01", in: "#SCROLL01 -0.5\n") == "-0.5",
                "negative SCROLL keeps the minus")
        require(LegacyClipboard.scrollDecimal(token: "02", in: "#SCROLL01 0.5\n") == nil,
                "missing token is nil")
        require(
            LegacyClipboard.scrollDecimal(token: "01", in: "#SCROLL01 0.5\r\n#000SC:01\r\n") == "0.5",
            "CRLF file keeps only the decimal"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
