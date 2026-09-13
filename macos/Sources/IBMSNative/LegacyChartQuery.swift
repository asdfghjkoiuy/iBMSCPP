import CoreGraphics
import Foundation

/// Column indices from `EditorColumns.vb`. Find dialog Designer tags are these
/// values minus one; matching must use the real `ni*` indices or notes never hit.
enum EditorColumn {
    static let measure = 0
    static let scroll = 1
    static let bpm = 2
    static let stop = 3
    static let spacer1 = 4
    static let a1 = 5
    static let a2 = 6
    static let a3 = 7
    static let a4 = 8
    static let a5 = 9
    static let a6 = 10
    static let a7 = 11
    static let a8 = 12
    static let spacer2 = 13
    static let d1 = 14
    static let d2 = 15
    static let d3 = 16
    static let d4 = 17
    static let d5 = 18
    static let d6 = 19
    static let d7 = 20
    static let d8 = 21
    static let spacer3 = 22
    static let bga = 23
    static let layer = 24
    static let poor = 25
    static let spacer4 = 26
    static let bgm = 27

    static let playable = Set(a1...a8)
    static let twoPlayer = Set(d1...d8)

    static func index(forChannel channel: String) -> Int {
        switch channel.uppercased() {
        case "01": return bgm
        case let channel where ChartBGM.lane(display: channel) != nil:
            return bgm + (ChartBGM.lane(display: channel) ?? 0)
        case "03", "08": return bpm
        case "09": return stop
        case "SC": return scroll
        case "04": return bga
        case "07": return layer
        case "06": return poor
        case "16", "36", "56", "76", "D6": return a1
        case "11", "31", "51", "71", "D1": return a2
        case "12", "32", "52", "72", "D2": return a3
        case "13", "33", "53", "73", "D3": return a4
        case "14", "34", "54", "74", "D4": return a5
        case "15", "35", "55", "75", "D5": return a6
        case "18", "38", "58", "78", "D8": return a7
        case "19", "39", "59", "79", "D9": return a8
        case "21", "41", "61", "81", "E1": return d1
        case "22", "42", "62", "82", "E2": return d2
        case "23", "43", "63", "83", "E3": return d3
        case "24", "44", "64", "84", "E4": return d4
        case "25", "45", "65", "85", "E5": return d5
        case "28", "48", "68", "88", "E8": return d6
        case "29", "49", "69", "89", "E9": return d7
        case "26", "46", "66", "86", "E6": return d8
        default: return measure
        }
    }

    static func isNumeric(_ column: Int) -> Bool {
        column == bpm || column == stop || column == scroll
    }
}

enum QueryNoteIdentity: Hashable {
    case event(measure: Int, channel: String, numerator: Int64, denominator: Int64)
    case longNote(channel: String, startMeasure: Int, startNumerator: Int64, startDenominator: Int64)
    case timing(measure: Int, channel: String, numerator: Int64, denominator: Int64)
}

enum QueryNoteSource {
    case event(ChartEventSnapshot)
    case longNote(LongNoteSnapshot)
    case timing(TimingEventSnapshot)
}

struct QueryNote {
    var identity: QueryNoteIdentity
    var columnIndex: Int
    var measure: Int
    var isLong: Bool
    var isHidden: Bool
    var isNumeric: Bool
    var labelToken: String
    var numericValue: Double?
    var selected: Bool
    var hasError: Bool
    var isLnObj: Bool
    var source: QueryNoteSource
}

enum StatisticsColumn: Int, CaseIterable {
    case short = 0
    case long = 1
    case lnObj = 2
    case hidden = 3
    case errors = 4
    case total = 5
}

enum StatisticsRow: Int, CaseIterable {
    case bpm = 0
    case stop = 1
    case scroll = 2
    case playable = 3
    case twoPlayer = 4
    case bgm = 5
    case total = 6

    static func category(for columnIndex: Int) -> StatisticsRow {
        switch columnIndex {
        case EditorColumn.bpm: return .bpm
        case EditorColumn.stop: return .stop
        case EditorColumn.scroll: return .scroll
        case EditorColumn.a1...EditorColumn.a8: return .playable
        case EditorColumn.d1...EditorColumn.d8: return .twoPlayer
        case let column where column >= EditorColumn.bgm: return .bgm
        default: return .total
        }
    }
}

struct StatisticsMatrix: Equatable {
    var cells: [[Int]]

    static let zero = StatisticsMatrix(cells: Array(repeating: Array(repeating: 0, count: 6), count: 7))

    subscript(row: StatisticsRow, column: StatisticsColumn) -> Int {
        get { cells[row.rawValue][column.rawValue] }
        set { cells[row.rawValue][column.rawValue] = newValue }
    }

    func value(_ row: Int, _ column: Int) -> Int {
        cells[row][column]
    }
}

struct FindQuery: Equatable {
    var includeSelected = true
    var includeUnselected = true
    var includeShort = true
    var includeLong = true
    var includeHidden = true
    var includeVisible = true
    var measureLow = 0
    var measureHigh = 999
    var labelLow = "01"
    var labelHigh = "ZZ"
    var valueLow = 0.0001
    var valueHigh = 65535.9999
    var columns: Set<Int> = []
    var replaceLabel = "01"
    var replaceValue = 120.0

    static let valueScale = 10_000

    var rangeFactors: Int {
        var value = 1
        if includeSelected { value *= 2 }
        if includeUnselected { value *= 3 }
        if includeShort { value *= 5 }
        if includeLong { value *= 7 }
        if includeHidden { value *= 11 }
        if includeVisible { value *= 13 }
        return value
    }

    static func fromRangeFactors(_ value: Int) -> FindQuery {
        var query = FindQuery()
        query.includeSelected = value % 2 == 0
        query.includeUnselected = value % 3 == 0
        query.includeShort = value % 5 == 0
        query.includeLong = value % 7 == 0
        query.includeHidden = value % 11 == 0
        query.includeVisible = value % 13 == 0
        return query
    }
}

enum LegacyChartQuery {
    /// `MainWindow.fdrRangeS`. Both limits on → always true; only one on →
    /// match that side; both off → always false.
    static func rangeS(_ limit1: Bool, _ limit2: Bool, value: Bool) -> Bool {
        (!limit1 && limit2 && value) || (limit1 && !limit2 && !value) || (limit1 && limit2)
    }

    /// BMSON 声道身份步长，与 `BmsonChartMapping.noteIdentityStride` 相同。
    /// 写在这里，避免 ChartQuery 测试去链 BMSON 映射。
    static let bmsonNoteIdentityStride = 1_000_003

    /// 侧栏声道列是 `CH0`、`CH1`…，和演奏区同一颗音。Find / Statistics 只数演奏区。
    static func isSoundLaneChannel(_ channel: String) -> Bool {
        let key = channel.uppercased()
        guard key.hasPrefix("CH") else { return false }
        let rest = key.dropFirst(2)
        return !rest.isEmpty && rest.allSatisfy(\.isNumber)
    }

    static func collect(
        chart: ChartSnapshot,
        longNotes: LongNoteSnapshotSet,
        timing: TimingSnapshot,
        selectedEvents: Set<ChartEventSnapshot> = [],
        selectedLongNotes: Set<LongNoteSnapshot> = [],
        selectedTimingIDs: Set<TimingEventSnapshot.EventID> = [],
        bmsonLabels: Bool = false
    ) -> [QueryNote] {
        let paired = Set(longNotes.notes.flatMap { note -> [PairedEndpoint] in
            [PairedEndpoint(channel: note.channel, endpoint: note.start), PairedEndpoint(channel: note.channel, endpoint: note.end)]
        })
        var timingByKey: [TimingKey: TimingEventSnapshot] = [:]
        for event in timing.events {
            timingByKey[TimingKey(measure: event.measure, channel: event.channel, numerator: event.fraction.numerator, denominator: event.fraction.denominator)] = event
        }
        var usedTiming: Set<TimingEventSnapshot.EventID> = []
        var notes: [QueryNote] = []

        for event in chart.events {
            if isSoundLaneChannel(event.channel) { continue }
            if paired.contains(PairedEndpoint(event: event)) { continue }
            if event.kind == "longNote" && !ChartConvert.isLongChannel(event.channel) { continue }
            let key = TimingKey(
                measure: event.measure,
                channel: event.channel,
                numerator: event.fractionNumerator,
                denominator: event.fractionDenominator
            )
            if let timingEvent = timingByKey[key] {
                usedTiming.insert(timingEvent.id)
                notes.append(note(
                    from: timingEvent,
                    selected: selectedTimingIDs.contains(timingEvent.id) || selectedEvents.contains(event),
                    lnobjToken: longNotes.lnobjToken,
                    bmsonLabels: bmsonLabels
                ))
                continue
            }
            notes.append(note(
                from: event,
                selected: selectedEvents.contains(event),
                lnobjToken: longNotes.lnobjToken,
                bmsonLabels: bmsonLabels
            ))
        }

        for longNote in longNotes.notes {
            if isSoundLaneChannel(longNote.channel) { continue }
            notes.append(note(
                from: longNote,
                selected: selectedLongNotes.contains(longNote),
                lnobjToken: longNotes.lnobjToken,
                bmsonLabels: bmsonLabels
            ))
        }

        return notes
    }

    static func statistics(from notes: [QueryNote], ntInput: Bool = true) -> StatisticsMatrix {
        var matrix = StatisticsMatrix.zero
        for note in notes {
            let category = StatisticsRow.category(for: note.columnIndex)
            add(note, to: &matrix, row: category, ntInput: ntInput)
            if category != .total {
                add(note, to: &matrix, row: .total, ntInput: ntInput)
            }
        }
        return matrix
    }

    static func playableNoteCount(from notes: [QueryNote], ntInput: Bool = true) -> Int {
        notes.reduce(0) { total, note in
            guard EditorColumn.playable.contains(note.columnIndex) else { return total }
            return total + 1 + (ntInput && note.isLong ? 1 : 0)
        }
    }

    static func passesRange(_ note: QueryNote, query: FindQuery) -> Bool {
        let selectedGate = (query.includeSelected && note.selected) || (query.includeUnselected && !note.selected)
        return selectedGate
            && rangeS(query.includeShort, query.includeLong, value: note.isLong)
            && rangeS(query.includeVisible, query.includeHidden, value: note.isHidden)
    }

    static func passesCheck(_ note: QueryNote, query: FindQuery) -> Bool {
        guard note.measure >= query.measureLow, note.measure <= query.measureHigh else { return false }
        guard query.columns.contains(note.columnIndex) else { return false }
        if note.isNumeric {
            guard let value = note.numericValue else { return false }
            let scaled = Int((value * Double(FindQuery.valueScale)).rounded(.towardZero))
            let low = Int((query.valueLow * Double(FindQuery.valueScale)).rounded(.towardZero))
            let high = Int((query.valueHigh * Double(FindQuery.valueScale)).rounded(.towardZero))
            return scaled >= low && scaled <= high
        }
        let token = BMS36Token.decode(note.labelToken) * FindQuery.valueScale
        let low = BMS36Token.decode(query.labelLow) * FindQuery.valueScale
        let high = BMS36Token.decode(query.labelHigh) * FindQuery.valueScale
        return token >= low && token <= high
    }

    static func applySelect(_ notes: [QueryNote], query: FindQuery) -> [QueryNote] {
        notes.map { note in
            var next = note
            if passesRange(note, query: query) {
                next.selected = passesCheck(note, query: query)
            }
            return next
        }
    }

    static func applyUnselect(_ notes: [QueryNote], query: FindQuery) -> [QueryNote] {
        notes.map { note in
            var next = note
            if passesRange(note, query: query) {
                next.selected = !passesCheck(note, query: query)
            }
            return next
        }
    }

    static func matchesForEdit(_ notes: [QueryNote], query: FindQuery) -> [QueryNote] {
        notes.filter { passesRange($0, query: query) && passesCheck($0, query: query) }
    }

    static func gridSlot(beat: Double, measureStart: Double, division: Int) -> Int? {
        guard division > 0, beat.isFinite, measureStart.isFinite else { return nil }
        let exact = (beat - measureStart) * Double(division) / 4.0
        let slot = Int(exact.rounded())
        if abs(exact - Double(slot)) < 1e-6, slot >= 0 { return slot }
        return nil
    }

    static func selectedSets(from notes: [QueryNote]) -> (events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>, timing: Set<TimingEventSnapshot.EventID>) {
        var events: Set<ChartEventSnapshot> = []
        var longNotes: Set<LongNoteSnapshot> = []
        var timing: Set<TimingEventSnapshot.EventID> = []
        for note in notes where note.selected {
            switch note.source {
            case .event(let event):
                events.insert(event)
            case .longNote(let longNote):
                longNotes.insert(longNote)
            case .timing(let event):
                timing.insert(event.id)
            }
        }
        return (events, longNotes, timing)
    }

    private static func add(_ note: QueryNote, to matrix: inout StatisticsMatrix, row: StatisticsRow, ntInput: Bool) {
        let unit = ntInput && note.isLong ? 2 : 1
        if ntInput {
            if note.isLong {
                matrix[row, .long] += 2
            } else {
                matrix[row, .short] += 1
            }
        } else {
            if note.isLong {
                matrix[row, .long] += 1
            } else {
                matrix[row, .short] += 1
            }
        }
        if note.isLnObj { matrix[row, .lnObj] += unit }
        if note.isHidden { matrix[row, .hidden] += unit }
        if note.hasError { matrix[row, .errors] += unit }
        matrix[row, .total] += unit
    }

    private static func note(
        from event: ChartEventSnapshot,
        selected: Bool,
        lnobjToken: String,
        bmsonLabels: Bool
    ) -> QueryNote {
        let column = EditorColumn.index(forChannel: event.channel)
        let label = labelToken(channel: event.channel, token: event.token, sourceLine: event.sourceLine, bmsonLabels: bmsonLabels)
        return QueryNote(
            identity: .event(
                measure: event.measure,
                channel: event.channel,
                numerator: event.fractionNumerator,
                denominator: event.fractionDenominator
            ),
            columnIndex: column,
            measure: event.measure,
            isLong: ChartConvert.isLongChannel(event.channel),
            isHidden: event.kind == "hiddenNote",
            isNumeric: EditorColumn.isNumeric(column),
            labelToken: label,
            numericValue: numericValue(channel: event.channel, token: event.token, bmsonLabels: bmsonLabels),
            selected: selected,
            hasError: false,
            isLnObj: !lnobjToken.isEmpty && event.token.caseInsensitiveCompare(lnobjToken) == .orderedSame,
            source: .event(event)
        )
    }

    private static func note(
        from longNote: LongNoteSnapshot,
        selected: Bool,
        lnobjToken: String,
        bmsonLabels: Bool
    ) -> QueryNote {
        let column = EditorColumn.index(forChannel: longNote.channel)
        let label = labelToken(
            channel: longNote.channel,
            token: longNote.start.token,
            sourceLine: longNote.start.sourceLine,
            bmsonLabels: bmsonLabels
        )
        return QueryNote(
            identity: .longNote(
                channel: longNote.channel,
                startMeasure: longNote.start.measure,
                startNumerator: longNote.start.fractionNumerator,
                startDenominator: longNote.start.fractionDenominator
            ),
            columnIndex: column,
            measure: longNote.start.measure,
            isLong: true,
            isHidden: false,
            isNumeric: false,
            labelToken: label,
            numericValue: nil,
            selected: selected,
            hasError: false,
            isLnObj: !lnobjToken.isEmpty && longNote.start.token.caseInsensitiveCompare(lnobjToken) == .orderedSame,
            source: .longNote(longNote)
        )
    }

    private static func note(
        from event: TimingEventSnapshot,
        selected: Bool,
        lnobjToken _: String,
        bmsonLabels _: Bool
    ) -> QueryNote {
        let column = EditorColumn.index(forChannel: event.channel)
        return QueryNote(
            identity: .timing(
                measure: event.measure,
                channel: event.channel,
                numerator: event.fraction.numerator,
                denominator: event.fraction.denominator
            ),
            columnIndex: column,
            measure: event.measure,
            isLong: false,
            isHidden: false,
            isNumeric: true,
            labelToken: event.token,
            numericValue: Double(event.valueDecimal),
            selected: selected,
            hasError: false,
            isLnObj: false,
            source: .timing(event)
        )
    }

    /// `identity > 0` 才是声音音，标签用声道下标的三十六进制。BGA / BPM / STOP 保持画面上的字。
    private static func labelToken(channel _: String, token: String, sourceLine: Int, bmsonLabels: Bool) -> String {
        guard bmsonLabels, sourceLine > 0 else { return token }
        let channelIndex = (sourceLine - 1) / bmsonNoteIdentityStride
        return BMS36Token.encode(channelIndex + 1)
    }

    private static func numericValue(channel: String, token: String, bmsonLabels: Bool = false) -> Double? {
        switch channel.uppercased() {
        case "03":
            if bmsonLabels {
                return Double(token)
            }
            return Int(token, radix: 16).map(Double.init)
        case "08", "09":
            if bmsonLabels {
                return Double(token)
            }
            return nil
        default:
            return nil
        }
    }

    private struct PairedEndpoint: Hashable {
        let channel: String
        let measure: Int
        let numerator: Int64
        let denominator: Int64
        let token: String
        let sourceLine: Int

        init(channel: String, endpoint: LongNoteEndpointSnapshot) {
            self.channel = channel
            measure = endpoint.measure
            numerator = endpoint.fractionNumerator
            denominator = endpoint.fractionDenominator
            token = endpoint.token
            sourceLine = endpoint.sourceLine
        }

        init(event: ChartEventSnapshot) {
            channel = event.channel
            measure = event.measure
            numerator = event.fractionNumerator
            denominator = event.fractionDenominator
            token = event.token
            sourceLine = event.sourceLine
        }
    }

    private struct TimingKey: Hashable {
        let measure: Int
        let channel: String
        let numerator: Int64
        let denominator: Int64
    }
}

enum StatisticsDialogLayout {
    static let clientSize = CGSize(width: 482, height: 254)
    static let iconFrame = CGRect(x: 12, y: 9, width: 42, height: 42)
    static let tableFrame = CGRect(x: 64, y: 12, width: 387, height: 188)
    static let okFrame = CGRect(x: 381, y: 212, width: 78, height: 27)
    static let labelColumnWidth: CGFloat = 50
    static let headerRowHeight: CGFloat = 25
    static let stripe = ThemeColor(argb: 0x10000000)
    static let rowTitles = ["BPM", "STOP", "SCROLL", "A1-A8", "D1-D8", "BGM", "Total"]
    static let columnTitles = ["Short", "Long", "LnObj", "Hidden", "Errors", "Total"]

    static var dataColumnWidth: CGFloat { (tableFrame.width - labelColumnWidth) / 6 }

    static var dataRowHeight: CGFloat { (tableFrame.height - headerRowHeight) / 7 }

    static func headerFrame(column: Int) -> CGRect {
        CGRect(
            x: tableFrame.minX + labelColumnWidth + CGFloat(column) * dataColumnWidth,
            y: tableFrame.minY,
            width: dataColumnWidth,
            height: headerRowHeight
        )
    }

    static func rowLabelFrame(row: Int) -> CGRect {
        CGRect(
            x: tableFrame.minX,
            y: tableFrame.minY + headerRowHeight + CGFloat(row) * dataRowHeight,
            width: labelColumnWidth,
            height: dataRowHeight
        )
    }

    static func cellFrame(row: Int, column: Int) -> CGRect {
        CGRect(
            x: tableFrame.minX + labelColumnWidth + CGFloat(column) * dataColumnWidth,
            y: tableFrame.minY + headerRowHeight + CGFloat(row) * dataRowHeight,
            width: dataColumnWidth,
            height: dataRowHeight
        )
    }

    static func rowIsStriped(_ row: Int) -> Bool {
        row % 2 == 0
    }
}

struct FindColumnButton: Equatable {
    let title: String
    let columnIndex: Int
    let frame: CGRect
}

enum FindDialogLayout {
    static let clientSize = CGSize(width: 474, height: 422)
    static let defaultGreatestColumn = 41
    static let noteRangeLabel = CGRect(x: 26, y: 20, width: 120, height: 17)
    static let selected = CGRect(x: 152, y: 16, width: 100, height: 25)
    static let unselected = CGRect(x: 152, y: 41, width: 100, height: 25)
    static let shortNote = CGRect(x: 258, y: 16, width: 70, height: 25)
    static let longNote = CGRect(x: 258, y: 41, width: 70, height: 25)
    static let hidden = CGRect(x: 334, y: 16, width: 80, height: 25)
    static let visible = CGRect(x: 334, y: 41, width: 80, height: 25)
    static let measureRangeLabel = CGRect(x: 26, y: 73, width: 120, height: 17)
    static let measureLow = CGRect(x: 152, y: 72, width: 70, height: 23)
    static let measureHigh = CGRect(x: 258, y: 72, width: 70, height: 23)
    static let measureTo = CGRect(x: 221, y: 74, width: 39, height: 16)
    static let labelRangeLabel = CGRect(x: 26, y: 103, width: 120, height: 17)
    static let labelLow = CGRect(x: 152, y: 101, width: 70, height: 23)
    static let labelHigh = CGRect(x: 258, y: 101, width: 70, height: 23)
    static let labelTo = CGRect(x: 221, y: 103, width: 39, height: 16)
    static let valueRangeLabel = CGRect(x: 26, y: 131, width: 120, height: 17)
    static let valueLow = CGRect(x: 152, y: 130, width: 70, height: 23)
    static let valueHigh = CGRect(x: 258, y: 130, width: 100, height: 23)
    static let valueTo = CGRect(x: 221, y: 132, width: 39, height: 16)
    static let columnCaption = CGRect(x: 12, y: 165, width: 80, height: 15)
    static let columnRule = CGRect(x: 12, y: 173, width: 450, height: 1)
    static let columnPanel = CGRect(x: 26, y: 186, width: 302, height: 131)
    static let selectAll = CGRect(x: 334, y: 189, width: 120, height: 23)
    static let selectInverse = CGRect(x: 334, y: 218, width: 120, height: 23)
    static let unselectAll = CGRect(x: 334, y: 247, width: 120, height: 23)
    static let operationCaption = CGRect(x: 12, y: 327, width: 80, height: 15)
    static let operationRule = CGRect(x: 12, y: 335, width: 450, height: 1)
    static let operationDivider = CGRect(x: 289, y: 354, width: 1, height: 52)
    static let replaceLabel = CGRect(x: 26, y: 354, width: 178, height: 23)
    static let replaceLabelField = CGRect(x: 210, y: 354, width: 70, height: 23)
    static let replaceValue = CGRect(x: 26, y: 383, width: 178, height: 23)
    static let replaceValueField = CGRect(x: 210, y: 383, width: 70, height: 23)
    static let select = CGRect(x: 298, y: 354, width: 85, height: 23)
    static let unselect = CGRect(x: 298, y: 383, width: 85, height: 23)
    static let delete = CGRect(x: 389, y: 354, width: 65, height: 23)
    static let close = CGRect(x: 389, y: 383, width: 65, height: 23)
    static let ruleColor = ThemeColor(argb: 0xFF404040)

    static func columnButtons(greatestColumn: Int = defaultGreatestColumn) -> [FindColumnButton] {
        var buttons = [
            FindColumnButton(title: "BPM", columnIndex: EditorColumn.bpm, frame: CGRect(x: 3, y: 2, width: 50, height: 25)),
            FindColumnButton(title: "STOP", columnIndex: EditorColumn.stop, frame: CGRect(x: 53, y: 2, width: 50, height: 25)),
            FindColumnButton(title: "A1", columnIndex: EditorColumn.a1, frame: CGRect(x: 3, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A2", columnIndex: EditorColumn.a2, frame: CGRect(x: 38, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A3", columnIndex: EditorColumn.a3, frame: CGRect(x: 73, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A4", columnIndex: EditorColumn.a4, frame: CGRect(x: 108, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A5", columnIndex: EditorColumn.a5, frame: CGRect(x: 143, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A6", columnIndex: EditorColumn.a6, frame: CGRect(x: 178, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A7", columnIndex: EditorColumn.a7, frame: CGRect(x: 213, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "A8", columnIndex: EditorColumn.a8, frame: CGRect(x: 248, y: 27, width: 35, height: 25)),
            FindColumnButton(title: "D1", columnIndex: EditorColumn.d1, frame: CGRect(x: 3, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D2", columnIndex: EditorColumn.d2, frame: CGRect(x: 38, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D3", columnIndex: EditorColumn.d3, frame: CGRect(x: 73, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D4", columnIndex: EditorColumn.d4, frame: CGRect(x: 108, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D5", columnIndex: EditorColumn.d5, frame: CGRect(x: 143, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D6", columnIndex: EditorColumn.d6, frame: CGRect(x: 178, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D7", columnIndex: EditorColumn.d7, frame: CGRect(x: 213, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "D8", columnIndex: EditorColumn.d8, frame: CGRect(x: 248, y: 52, width: 35, height: 25)),
            FindColumnButton(title: "BGA", columnIndex: EditorColumn.bga, frame: CGRect(x: 3, y: 77, width: 55, height: 25)),
            FindColumnButton(title: "LAYER", columnIndex: EditorColumn.layer, frame: CGRect(x: 58, y: 77, width: 55, height: 25)),
            FindColumnButton(title: "POOR", columnIndex: EditorColumn.poor, frame: CGRect(x: 113, y: 77, width: 55, height: 25)),
            FindColumnButton(title: "B1", columnIndex: EditorColumn.bgm, frame: CGRect(x: 3, y: 102, width: 35, height: 25))
        ]
        if greatestColumn >= 27 {
            for index in 27...greatestColumn {
                let offset = index - 26
                buttons.append(FindColumnButton(
                    title: "B\(index - 25)",
                    columnIndex: index + 1,
                    frame: CGRect(
                        x: CGFloat(offset % 8) * 35 + 3,
                        y: CGFloat(offset / 8) * 25 + 103,
                        width: 35,
                        height: 25
                    )
                ))
            }
        }
        return buttons
    }
}
