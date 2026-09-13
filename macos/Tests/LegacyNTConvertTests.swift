import Foundation

@main
struct LegacyNTConvertTests {
    static func main() {
        testSameColumnLongNotesBecomeLength()
        testLnObjStopsPairing()
        testSingleLongNoteClearsFlag()
        testDifferentColumnsDoNotPair()
        testNTLengthSplitsIntoTwoLongNotes()
        testHiddenCopiesToBothEnds()
        print("LegacyNTConvertTests passed")
    }

    /// 同列两颗 `LongNote`，vpos `0` / `192` → 一颗 `Length = 192`，`LongNote = False`。
    private static func testSameColumnLongNotesBecomeLength() {
        let converted = LegacyNTConvert.convertBMSE2NT([
            note(column: 6, vpos: 0, longNote: true),
            note(column: 6, vpos: 192, longNote: true)
        ])
        require(converted.count == 1, "paired longs collapse to one NT note")
        require(converted[0].length == 192 && !converted[0].longNote, "length is the vpos delta")
        require(converted[0].columnIndex == 6 && converted[0].vPosition == 0, "start stays")
    }

    /// 中间有 `Value \ 10000 = LnObj` 则停止搜索，两颗 Long 都不配对，最后 `LongNote` 全清。
    private static func testLnObjStopsPairing() {
        let converted = LegacyNTConvert.convertBMSE2NT(
            [
                note(column: 6, vpos: 0, longNote: true),
                note(column: 6, vpos: 96, value: 360_000),
                note(column: 6, vpos: 192, longNote: true)
            ],
            lnobj: 36
        )
        require(converted.count == 3, "LnObj does not delete either long")
        require(converted.allSatisfy { !$0.longNote && $0.length == 0 }, "all LongNote flags clear")
        require(converted[1].value == 360_000, "the LnObj cell stays")
    }

    /// 单颗 `LongNote` 配不成对：长度 0，旗清掉。
    private static func testSingleLongNoteClearsFlag() {
        let converted = LegacyNTConvert.convertBMSE2NT([
            note(column: 6, vpos: 0, longNote: true)
        ])
        require(converted.count == 1 && converted[0].length == 0 && !converted[0].longNote,
                "unpaired LongNote becomes a short")
    }

    /// 不同列不配对。
    private static func testDifferentColumnsDoNotPair() {
        let converted = LegacyNTConvert.convertBMSE2NT([
            note(column: 6, vpos: 0, longNote: true),
            note(column: 7, vpos: 192, longNote: true)
        ])
        require(converted.count == 2, "other columns stay")
        require(converted.allSatisfy { $0.length == 0 && !$0.longNote }, "no cross-column length")
    }

    /// NT `length 192` → 两颗 `LongNote`，终点 `Landmine = False`。
    private static func testNTLengthSplitsIntoTwoLongNotes() {
        let converted = LegacyNTConvert.convertNT2BMSE([
            note(column: 6, vpos: 0, length: 192, landmine: true)
        ])
        require(converted.count == 2, "NT length writes two BMSE longs")
        require(converted[0].longNote && converted[0].vPosition == 0 && converted[0].length == 0,
                "start is LongNote at the original vpos")
        require(converted[0].landmine, "start keeps Landmine")
        require(converted[1].longNote && converted[1].vPosition == 192 && !converted[1].landmine,
                "end is LongNote and Landmine is false")
    }

    /// Hidden 拷到两端。
    private static func testHiddenCopiesToBothEnds() {
        let converted = LegacyNTConvert.convertNT2BMSE([
            note(column: 6, vpos: 48, value: 20_000, length: 96, hidden: true)
        ])
        require(converted.count == 2, "hidden long splits")
        require(converted[0].hidden && converted[1].hidden, "Hidden copies to both ends")
        require(converted[0].value == 20_000 && converted[1].value == 20_000, "Value copies")
        require(converted[1].vPosition == 144, "end is start plus length")
    }

    private static func note(
        column: Int,
        vpos: Double,
        value: Int = 10_000,
        length: Double = 0,
        longNote: Bool = false,
        hidden: Bool = false,
        landmine: Bool = false
    ) -> LegacyClipboardNote {
        LegacyClipboardNote(
            columnIndex: column,
            vPosition: vpos,
            value: value,
            length: length,
            longNote: longNote,
            hidden: hidden,
            landmine: landmine
        )
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
