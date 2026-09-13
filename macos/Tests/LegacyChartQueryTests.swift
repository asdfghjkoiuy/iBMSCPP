import Foundation

@main
struct LegacyChartQueryTests {
    static func main() {
        testTokens()
        testRangeS()
        testColumnMap()
        testStatistics()
        testFind()
        testLayouts()
        testSoundLaneExcludedFromCollect()
        testBmsonLabelsUseChannelIndex()
        testBmsonLabelsDecimalTiming()
        testBmsHexBpmStill120()
        print("LegacyChartQueryTests passed")
    }

    private static func testTokens() {
        require(BMS36Token.encode(1) == "01" && BMS36Token.encode(10) == "0A" && BMS36Token.encode(1295) == "ZZ", "C10to36")
        require(BMS36Token.decode("01") == 1 && BMS36Token.decode("A") == 10 && BMS36Token.decode("ZZ") == 1295, "C36to10")
        require(BMS36Token.decode("0A") == 10, "one-character labels pad like original C36to10")
        require(LegacyChartQuery.gridSlot(beat: 5, measureStart: 4, division: 16) == 4, "1/4 beat at 16ths is slot 4")
        require(LegacyChartQuery.gridSlot(beat: 8.0 / 3.0, measureStart: 0, division: 16) == nil,
                "2/3 of a 4-beat measure is off the default 16 grid")
        require(BMS36Token.isValidLabel("01") && BMS36Token.isValidLabel("A") && BMS36Token.isValidLabel("ZZ"), "valid labels")
        require(!BMS36Token.isValidLabel("00") && !BMS36Token.isValidLabel("0") && !BMS36Token.isValidLabel("") && !BMS36Token.isValidLabel("ABC"), "invalid labels")
    }

    private static func testRangeS() {
        require(LegacyChartQuery.rangeS(true, true, value: false), "both limits on is always true")
        require(LegacyChartQuery.rangeS(true, true, value: true), "both limits on ignores value")
        require(LegacyChartQuery.rangeS(true, false, value: false), "only first limit matches the false side")
        require(!LegacyChartQuery.rangeS(true, false, value: true), "only first limit rejects the true side")
        require(LegacyChartQuery.rangeS(false, true, value: true), "only second limit matches the true side")
        require(!LegacyChartQuery.rangeS(false, true, value: false), "only second limit rejects the false side")
        require(!LegacyChartQuery.rangeS(false, false, value: true) && !LegacyChartQuery.rangeS(false, false, value: false), "both off is always false")
    }

    private static func testColumnMap() {
        require(EditorColumn.index(forChannel: "16") == EditorColumn.a1, "A1 is channel 16")
        require(EditorColumn.index(forChannel: "11") == EditorColumn.a2, "A2 is channel 11")
        require(EditorColumn.index(forChannel: "51") == EditorColumn.a2, "long A2 stays on niA2")
        require(EditorColumn.index(forChannel: "31") == EditorColumn.a2, "hidden A2 stays on niA2")
        require(EditorColumn.index(forChannel: "21") == EditorColumn.d1, "D1")
        require(EditorColumn.index(forChannel: "01") == EditorColumn.bgm, "BGM")
        require(EditorColumn.index(forChannel: "B2") == EditorColumn.bgm + 1, "B2 is niB+1")
        require(EditorColumn.index(forChannel: "03") == EditorColumn.bpm && EditorColumn.index(forChannel: "08") == EditorColumn.bpm, "BPM channels")
        require(EditorColumn.index(forChannel: "SC") == EditorColumn.scroll, "SCROLL")
        require(EditorColumn.index(forChannel: "04") == EditorColumn.bga, "BGA")
        require(EditorColumn.bpm == 2 && EditorColumn.stop == 3 && EditorColumn.a1 == 5, "ni* constants")
        require(EditorColumn.bpm != 1, "Designer BPM Tag=1 is niSCROLL; matching must not use that tag")
    }

    private static func testStatistics() {
        let shortA = event(measure: 1, channel: "16", token: "01", kind: "normalNote", line: 4)
        let hiddenA = event(measure: 1, channel: "31", token: "02", kind: "hiddenNote", line: 5)
        let bgm = event(measure: 2, channel: "01", token: "03", kind: "bgm", line: 6)
        let bga = event(measure: 2, channel: "04", token: "01", kind: "bga", line: 7)
        let bpm = event(measure: 0, channel: "03", token: "78", kind: "bpm", line: 8)
        let longA = LongNoteSnapshot(
            channel: "11",
            start: LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 0, fractionDenominator: 1, beat: 0, token: "0A", sourceLine: 9),
            end: LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 1, fractionDenominator: 2, beat: 2, token: "0A", sourceLine: 10),
            encoding: "channel"
        )
        let longHead = event(measure: 0, channel: "11", token: "0A", kind: "normalNote", line: 9)
        let notes = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [shortA, hiddenA, bgm, bga, bpm, longHead], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: LongNoteSnapshotSet(notes: [longA], diagnostics: [], editable: true, editingReason: "", lnobjToken: "ZZ"),
            timing: .unavailable
        )
        require(notes.count == 6, "five unpaired events plus one NT long; the paired head is not a second short")
        require(notes.filter(\.isLong).count == 1, "one NT long note")
        require(!notes.contains { $0.columnIndex == EditorColumn.a2 && !$0.isLong && $0.labelToken == "0A" },
                "paired A2 head is absorbed into the long note")
        let matrix = LegacyChartQuery.statistics(from: notes, ntInput: true)
        require(matrix[.playable, .short] == 2 && matrix[.playable, .hidden] == 1 && matrix[.playable, .long] == 2, "A1-A8 NT counts")
        require(matrix[.playable, .total] == 4, "A1-A8 total is two shorts plus NT long")
        require(matrix[.bgm, .short] == 1 && matrix[.bgm, .total] == 1, "BGM row")
        require(matrix[.bpm, .short] == 1 && matrix[.bpm, .total] == 1, "header BPM is Notes(0) and is not in the chart snapshot")
        require(matrix[.total, .short] == 5 && matrix[.total, .long] == 2 && matrix[.total, .total] == 7, "BGA is counted only in Total")
        require(matrix[.total, .hidden] == 1, "hidden uses the NT unit")
        require(LegacyChartQuery.playableNoteCount(from: notes, ntInput: true) == 4, "toolbar counts every A1-A8 note; NT long adds one extra")

        let nonNT = LegacyChartQuery.statistics(from: notes, ntInput: false)
        require(nonNT[.playable, .long] == 1 && nonNT[.playable, .total] == 3, "non-NT long counts as one")

        let lnobjNotes = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [event(measure: 0, channel: "16", token: "ZZ", kind: "normalNote", line: 11)], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: LongNoteSnapshotSet(notes: [], diagnostics: [], editable: true, editingReason: "", lnobjToken: "ZZ"),
            timing: .unavailable
        )
        require(LegacyChartQuery.statistics(from: lnobjNotes)[.playable, .lnObj] == 1, "LnObj matches the configured token")
    }

    private static func testFind() {
        var query = FindQuery()
        query.columns = [EditorColumn.a1, EditorColumn.a2]
        query.measureLow = 0
        query.measureHigh = 2
        query.labelLow = "01"
        query.labelHigh = "0A"

        let selected = queryNote(channel: "16", token: "01", measure: 1, selected: true)
        let other = queryNote(channel: "16", token: "0B", measure: 1, selected: false)
        let longNote = queryNote(channel: "11", token: "02", measure: 1, selected: false, isLong: true)
        let far = queryNote(channel: "16", token: "01", measure: 8, selected: false)
        let bpm = queryNote(channel: "03", token: "78", measure: 0, selected: false, numeric: 120)

        require(LegacyChartQuery.passesCheck(selected, query: query), "label 01 is inside 01-0A")
        require(!LegacyChartQuery.passesCheck(other, query: query), "label 0B is outside 01-0A")
        require(LegacyChartQuery.passesCheck(longNote, query: query), "A2 long note uses niA2")
        require(!LegacyChartQuery.passesCheck(far, query: query), "measure 8 is outside 0-2")

        query.includeLong = false
        require(LegacyChartQuery.passesRange(selected, query: query), "short-only includes short notes")
        require(!LegacyChartQuery.passesRange(longNote, query: query), "short-only excludes long notes")
        query.includeLong = true
        query.includeShort = false
        require(LegacyChartQuery.passesRange(longNote, query: query) && !LegacyChartQuery.passesRange(selected, query: query), "long-only")

        query.includeShort = true
        query.columns = [EditorColumn.bpm]
        query.valueLow = 100
        query.valueHigh = 140
        require(LegacyChartQuery.passesCheck(bpm, query: query), "BPM 120 is inside 100-140")
        query.valueHigh = 110
        require(!LegacyChartQuery.passesCheck(bpm, query: query), "BPM 120 is outside 100-110")

        var selectQuery = FindQuery()
        selectQuery.columns = [EditorColumn.a1]
        selectQuery.labelHigh = "0A"
        let applied = LegacyChartQuery.applySelect([selected, other], query: selectQuery)
        require(applied[0].selected && !applied[1].selected, "Select sets Selected = fdrCheck")
        let unselected = LegacyChartQuery.applyUnselect([selected, other], query: selectQuery)
        require(!unselected[0].selected && unselected[1].selected, "Unselect sets Selected = Not fdrCheck")

        require(FindQuery.fromRangeFactors(2 * 3 * 5 * 7 * 11 * 13).includeVisible, "default range product")
        require(!FindQuery.fromRangeFactors(2 * 3 * 5).includeLong, "missing factor 7 means Long is off")
    }

    private static func testLayouts() {
        require(StatisticsDialogLayout.clientSize == CGSize(width: 482, height: 254), "statistics client size")
        require(StatisticsDialogLayout.iconFrame == CGRect(x: 12, y: 9, width: 42, height: 42), "Statistics3 frame")
        require(StatisticsDialogLayout.tableFrame == CGRect(x: 64, y: 12, width: 387, height: 188), "statistics table")
        require(StatisticsDialogLayout.okFrame == CGRect(x: 381, y: 212, width: 78, height: 27), "statistics OK")
        require(StatisticsDialogLayout.rowTitles == ["BPM", "STOP", "SCROLL", "A1-A8", "D1-D8", "BGM", "Total"], "row captions")
        require(StatisticsDialogLayout.columnTitles == ["Short", "Long", "LnObj", "Hidden", "Errors", "Total"], "column captions")
        require(StatisticsDialogLayout.rowIsStriped(0) && !StatisticsDialogLayout.rowIsStriped(1), "even data rows use &H10000000")
        require(abs(StatisticsDialogLayout.headerFrame(column: 5).maxX - StatisticsDialogLayout.tableFrame.maxX) < 0.001, "last header meets table right")
        require(abs(StatisticsDialogLayout.cellFrame(row: 6, column: 5).maxY - StatisticsDialogLayout.tableFrame.maxY) < 0.001, "last cell meets table bottom")

        require(FindDialogLayout.clientSize == CGSize(width: 474, height: 422), "find client size")
        require(FindDialogLayout.selected == CGRect(x: 152, y: 16, width: 100, height: 25), "Selected")
        require(FindDialogLayout.columnPanel == CGRect(x: 26, y: 186, width: 302, height: 131), "column panel")
        require(FindDialogLayout.select == CGRect(x: 298, y: 354, width: 85, height: 23), "Select")
        require(FindDialogLayout.close == CGRect(x: 389, y: 383, width: 65, height: 23), "Close")
        let buttons = FindDialogLayout.columnButtons()
        require(buttons.contains { $0.title == "BPM" && $0.columnIndex == EditorColumn.bpm && $0.frame == CGRect(x: 3, y: 2, width: 50, height: 25) }, "BPM button uses niBPM")
        require(buttons.contains { $0.title == "A1" && $0.columnIndex == 5 && $0.frame.origin == CGPoint(x: 3, y: 27) }, "A1")
        require(buttons.contains { $0.title == "B1" && $0.columnIndex == 27 && $0.frame == CGRect(x: 3, y: 102, width: 35, height: 25) }, "B1")
        require(buttons.contains { $0.title == "B2" && $0.columnIndex == 28 && $0.frame == CGRect(x: 38, y: 103, width: 35, height: 25) }, "B2 from gColumns loop")
        require(buttons.contains { $0.title == "B16" && $0.columnIndex == 42 }, "CGB=15 still emits B16 like the original loop 27...41")
        require(buttons.filter { $0.title.first == "B" && $0.title.dropFirst().allSatisfy(\.isNumber) }.count == 16, "B1 plus 27...41")
    }

    /// 侧栏 `CH0` 和演奏区是同一颗音，不能进 Find / Statistics。
    private static func testSoundLaneExcludedFromCollect() {
        let playable = event(measure: 0, channel: "11", token: "kick.wav", kind: "normalNote", line: 1)
        let lane = event(measure: 0, channel: "CH0", token: "kick.wav", kind: "normalNote", line: 1)
        let notes = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [playable, lane], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: .empty,
            timing: .unavailable
        )
        require(notes.count == 1, "CH* is not a second note")
        require(notes[0].columnIndex == EditorColumn.a2, "kept the playable copy")
        require(!notes.contains { $0.columnIndex == EditorColumn.measure }, "CH0 must not land on measure")
        let matrix = LegacyChartQuery.statistics(from: notes)
        require(matrix[.total, .total] == 1, "Total does not count the sound-lane copy")
        require(LegacyChartQuery.isSoundLaneChannel("CH0") && LegacyChartQuery.isSoundLaneChannel("CH12"), "CH plus digits")
        require(!LegacyChartQuery.isSoundLaneChannel("CH") && !LegacyChartQuery.isSoundLaneChannel("11"), "not a sound lane")
    }

    /// 打开 BMSON 时标签是声道三十六进制，不是文件名。
    private static func testBmsonLabelsUseChannelIndex() {
        let kick = event(measure: 0, channel: "11", token: "kick.wav", kind: "normalNote", line: 1)
        let notes = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [kick], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: .empty,
            timing: .unavailable,
            bmsonLabels: true
        )
        require(notes.count == 1 && notes[0].labelToken == "01", "channel 0 is label 01")
        let plain = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [kick], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: .empty,
            timing: .unavailable
        )
        require(plain[0].labelToken == "kick.wav", "BMS path still uses the snapshot token")
    }

    /// BMSON 的 BPM / STOP 按十进制匹配。
    private static func testBmsonLabelsDecimalTiming() {
        let bpm = event(measure: 0, channel: "03", token: "140", kind: "bpm", line: -1)
        let notes = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [bpm], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: .empty,
            timing: .unavailable,
            bmsonLabels: true
        )
        require(notes.count == 1 && notes[0].numericValue == 140, "140 decimal, not hex 320")
    }

    /// 现有 BMS 夹具 `78` 仍是十六进制 120。
    private static func testBmsHexBpmStill120() {
        let bpm = event(measure: 0, channel: "03", token: "78", kind: "bpm", line: 8)
        let notes = LegacyChartQuery.collect(
            chart: ChartSnapshot(events: [bpm], measures: [], diagnostics: [], editable: true, editingReason: ""),
            longNotes: .empty,
            timing: .unavailable
        )
        require(notes.count == 1 && notes[0].numericValue == 120, "BMS 03 stays hex")
    }

    private static func event(measure: Int, channel: String, token: String, kind: String, line: Int) -> ChartEventSnapshot {
        ChartEventSnapshot(
            measure: measure,
            channel: channel,
            token: token,
            fractionNumerator: 0,
            fractionDenominator: 1,
            beat: Double(measure) * 4,
            kind: kind,
            sourceLine: line
        )
    }

    private static func queryNote(
        channel: String,
        token: String,
        measure: Int,
        selected: Bool,
        isLong: Bool = false,
        numeric: Double? = nil
    ) -> QueryNote {
        let snapshot = event(measure: measure, channel: channel, token: token, kind: "normalNote", line: 1)
        let column = EditorColumn.index(forChannel: channel)
        return QueryNote(
            identity: .event(measure: measure, channel: channel, numerator: 0, denominator: 1),
            columnIndex: column,
            measure: measure,
            isLong: isLong,
            isHidden: false,
            isNumeric: numeric != nil,
            labelToken: token,
            numericValue: numeric,
            selected: selected,
            hasError: false,
            isLnObj: false,
            source: .event(snapshot)
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
