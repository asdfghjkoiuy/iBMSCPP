import AppKit
import Foundation

/// Swift only uses display doubles. The bridge retains the exact raw rational
/// positions that identify an event when it asks the core to edit it.
struct ChartEventSnapshot: Hashable {
    let measure: Int
    let channel: String
    let token: String
    let fractionNumerator: Int64
    let fractionDenominator: Int64
    let beat: Double
    let kind: String
    let sourceLine: Int
}

struct ChartMeasureSnapshot: Hashable {
    let measure: Int
    /// Start and length are measured in quarter beats for display only.
    let start: Double
    let length: Double
}

struct ChartDiagnosticSnapshot: Hashable {
    /// The exact zero-based source-line coordinate from core, when present.
    let sourceLine: Int
    let message: String
}

struct ChartSnapshot: Hashable {
    var events: [ChartEventSnapshot]
    var measures: [ChartMeasureSnapshot]
    var diagnostics: [ChartDiagnosticSnapshot]
    var editable: Bool
    var editingReason: String

    static let empty = ChartSnapshot(events: [], measures: [], diagnostics: [], editable: false,
                                     editingReason: "Open a BMS chart to edit notes.")
}

enum ChartSide: String, CaseIterable {
    case onePlayer = "1P"
    case twoPlayer = "2P"
    case both = "Both"
}

/// iBMSC `CHPlayer_SelectedIndexChanged`：`iPlayer <> 0` 时显示 2P 列。
enum ChartPlayerColumns {
    static func showsTwoPlayer(_ storedPlayer: String) -> Bool {
        let trimmed = storedPlayer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return false }
        return value == 2 || value == 3
    }
}

enum ChartBGM {
    static let defaultColumnCount = 15
    static let themeColumnIndex = 27

    static func displayChannel(lane: Int) -> String {
        "B\(max(0, lane) + 1)"
    }

    static func lane(display: String) -> Int? {
        let upper = display.uppercased()
        if upper == "01" { return 0 }
        guard upper.first == "B", let index = Int(upper.dropFirst()), index >= 1 else { return nil }
        return index - 1
    }
}

/// 对照 `EditorColumns.GetBMSChannelBy` 和 `PanelEvents` 数值列写入。
enum ChartTiming {
    static func bpmWriteChannel(_ decimal: String) -> String? {
        let text = decimal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let value = Double(text) else { return nil }
        if value == 0 { return nil }
        let stored = value < 0 ? 1.0 : value
        if stored == stored.rounded(.towardZero), (1...255).contains(Int(stored)) {
            return "03"
        }
        return "08"
    }

    static func storedBpmDecimal(_ decimal: String) -> String? {
        guard bpmWriteChannel(decimal) != nil else { return nil }
        let text = decimal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text) else { return nil }
        return value < 0 ? "1" : text
    }
}

enum ChartConvert {
    enum HiddenAction {
        case hide
        case show
        case toggle
    }

    /// `PanelEvents`：`Keys.L` → `POBLong`，`Keys.S` → `POBShort`（`POBNormal_Click`）。
    enum ConvertShortcut {
        case long
        case short
    }

    static func convertShortcut(fromKeyCode keyCode: UInt16) -> ConvertShortcut? {
        switch keyCode {
        case 37:
            return .long
        case 1:
            return .short
        default:
            return nil
        }
    }

    static func destinationChannel(for source: String, action: HiddenAction) -> String? {
        let upper = source.uppercased()
        guard upper.count == 2 else { return nil }
        let family = String(upper.prefix(1))
        guard ["1", "2", "3", "4", "D", "E"].contains(family) else { return nil }
        let visible = ChartLayout.displayChannel(upper)
        let hidden = ChartWriteChannel.source(display: visible, hidden: true, mine: false)
        let isHidden = family == "3" || family == "4"
        switch action {
        case .hide:
            return isHidden ? nil : hidden
        case .show:
            return isHidden ? visible : nil
        case .toggle:
            return isHidden ? visible : hidden
        }
    }

    static func shortChannel(for source: String) -> String {
        ChartLayout.displayChannel(source)
    }

    /// 对照 `GetBMSChannelBy`：`LongNote` 优先于 Hidden / Landmine，1P 写 `5x`，2P 写 `6x`。
    static func longChannel(for source: String) -> String? {
        let visible = ChartLayout.displayChannel(source.uppercased())
        guard visible.count == 2 else { return nil }
        switch visible.first {
        case "1":
            return "5\(visible.dropFirst())"
        case "2":
            return "6\(visible.dropFirst())"
        default:
            return nil
        }
    }

    static func isLongChannel(_ source: String) -> Bool {
        let first = source.uppercased().first
        return first == "5" || first == "6"
    }

    /// `POBLong` 后 `UpdatePairing`：同一可见列上按时间两两配对。
    static func longNotePairs(from events: [ChartEventSnapshot]) -> [(ChartEventSnapshot, ChartEventSnapshot)] {
        var groups: [String: [ChartEventSnapshot]] = [:]
        for event in events {
            let upper = event.channel.uppercased()
            guard let destination = longChannel(for: upper) else { continue }
            if isLongChannel(upper) { continue }
            groups[destination, default: []].append(event)
        }
        var pairs: [(ChartEventSnapshot, ChartEventSnapshot)] = []
        for destination in groups.keys.sorted() {
            let ordered = (groups[destination] ?? []).sorted(by: earlierNote)
            var index = 0
            while index + 1 < ordered.count {
                pairs.append((ordered[index], ordered[index + 1]))
                index += 2
            }
        }
        return pairs
    }

    /// `POBLong` 配完对之后剩下的那一颗短音。
    static func unpairedLongNotes(from events: [ChartEventSnapshot]) -> [ChartEventSnapshot] {
        var groups: [String: [ChartEventSnapshot]] = [:]
        for event in events {
            let upper = event.channel.uppercased()
            guard let destination = longChannel(for: upper) else { continue }
            if isLongChannel(upper) { continue }
            groups[destination, default: []].append(event)
        }
        var leftovers: [ChartEventSnapshot] = []
        for destination in groups.keys.sorted() {
            let ordered = (groups[destination] ?? []).sorted(by: earlierNote)
            var index = 0
            while index + 1 < ordered.count {
                index += 2
            }
            leftovers.append(contentsOf: ordered[index...])
        }
        return leftovers
    }

    /// 已经写成 `5x` / `6x`、但还没配成对的端点。
    static func unpairedLongEndpoints(
        from events: [ChartEventSnapshot],
        longs: [LongNoteSnapshot]
    ) -> [ChartEventSnapshot] {
        let paired = Set(longs.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        return events.filter { isLongChannel($0.channel) && !paired.contains($0.sourceLine) }
            .sorted(by: earlierNote)
    }

    static func longNoteMenuEnabled(ntInput: Bool) -> Bool {
        !ntInput
    }

    /// `POBMirror`：`niA1`↔`niA7`、`niA2`↔`niA6`、`niA3`↔`niA5`，`niA4` 不动。A8 / 2P / B 列不改。
    static func mirrorChannel(_ source: String) -> String? {
        let upper = source.uppercased()
        guard upper.count == 2 else { return nil }
        let family = String(upper.prefix(1))
        guard ["1", "3", "5", "D"].contains(family) else { return nil }
        let mapped: Character
        switch upper.last {
        case "1": mapped = "5"
        case "2": mapped = "4"
        case "3": mapped = "3"
        case "4": mapped = "2"
        case "5": mapped = "1"
        case "6": mapped = "8"
        case "8": mapped = "6"
        default: return nil
        }
        return "\(family)\(mapped)"
    }

    /// `POBModify` 标签：`UCase(Trim)`，只要 1–2 位 0-9/A-Z，不要 `0` / `00`。
    static func modifyLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.isEmpty || trimmed == "0" || trimmed == "00" { return nil }
        guard trimmed.count == 1 || trimmed.count == 2 else { return nil }
        let valid = trimmed.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
        }
        guard valid else { return nil }
        return String(("00" + trimmed).suffix(2))
    }

    /// `Val(InputBox) * 10000`：0 不改；小于等于 0 写成 Value `1`。
    static func modifyNumeric(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed) else { return nil }
        var stored = parsed * 10000
        if stored == 0 { return nil }
        if stored <= 0 { stored = 1 }
        if stored == stored.rounded(), Int(stored) % 10000 == 0 {
            return String(Int(stored) / 10000)
        }
        return String(stored / 10000)
    }

    /// `DoubleClickNoteIndex`：按列选英文提示。其它数值不发明文案。
    static func doubleClickPrompt(channel: String) -> String {
        switch channel.uppercased() {
        case "03", "08":
            return "Please enter a BPM value."
        case "09":
            return "Please enter a STOP value."
        case "SC":
            return "Please enter a SCROLL value."
        default:
            return "Please enter a label."
        }
    }

    /// `Val(valstr)`。只有（SCROLL 且 `valstr` 精确等于 `"0"`）或结果不是 0 才改。
    /// 不要套 `modifyNumeric` 的「小于等于 0 写成 Value 1」。
    static func doubleClickNumeric(text: String, channel: String) -> Double? {
        if channel.uppercased() == "SC", text == "0" {
            return 0
        }
        let value = vbVal(text)
        if value == 0 { return nil }
        return value
    }

    /// 双击写回用的十进制文本。整数不带小数点。
    static func doubleClickNumericText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == 0 { return "0" }
        if value == value.rounded(), value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }

    /// 对照下标 0：小节 0、拍 0、通道 `03`。
    static func isHeaderBpm(_ event: ChartEventSnapshot) -> Bool {
        event.channel.uppercased() == "03"
            && event.measure == 0
            && event.fractionNumerator == 0
    }

    static func isNumericChannel(_ channel: String) -> Bool {
        ["03", "08", "09", "SC"].contains(channel.uppercased())
    }

    /// VB `Val`：跳过前导空白，可读正负号、数字和一个小数点，第一个非法字符停。
    private static func vbVal(_ text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count && CharacterSet.whitespaces.contains(scalars[index]) {
            index += 1
        }
        guard index < scalars.count else { return 0 }
        var end = index
        if scalars[end] == "+" || scalars[end] == "-" { end += 1 }
        var sawDigit = false
        var sawDot = false
        while end < scalars.count {
            let value = scalars[end].value
            if value >= 48 && value <= 57 {
                sawDigit = true
                end += 1
                continue
            }
            if scalars[end] == "." && !sawDot {
                sawDot = true
                end += 1
                continue
            }
            break
        }
        if !sawDigit { return 0 }
        return Double(String(String.UnicodeScalarView(scalars[index..<end]))) ?? 0
    }

    private static func earlierNote(_ lhs: ChartEventSnapshot, _ rhs: ChartEventSnapshot) -> Bool {
        if lhs.measure != rhs.measure { return lhs.measure < rhs.measure }
        let left = Double(lhs.fractionNumerator) / Double(max(lhs.fractionDenominator, 1))
        let right = Double(rhs.fractionNumerator) / Double(max(rhs.fractionDenominator, 1))
        if left != right { return left < right }
        return lhs.beat < rhs.beat
    }
}

/// Ctrl 滚轮交给侧栏：BMS 走格子，BMSON 再按来源公式。
struct ChartZoomWheelEvent: Equatable {
    var notches: Int
    var pixelDeltaY: CGFloat
    var hasPrecisePixels: Bool
}

/// 对照 `PMain_Scroll` / `CGHeight` / `CGWidth`：滑条 1–20，数字框 = 滑条 / 4。
enum ChartZoom {
    static let trackMinimum = 1
    static let trackMaximum = 20
    /// Designer `CGHeight` / `CGWidth`：`Minimum = 0.25`，`Maximum = 99`。
    static let fieldMinimum = 0.25
    static let fieldMaximum = 99.0

    static func wheelNotches(scrollingDeltaY: CGFloat, precise: Bool) -> Int {
        if precise {
            return Int((scrollingDeltaY / 120).rounded())
        }
        if scrollingDeltaY == 0 { return 0 }
        return scrollingDeltaY > 0 ? 1 : -1
    }

    static func nextTrackValue(current: Int, wheelNotches: Int) -> Int {
        min(trackMaximum, max(trackMinimum, current + wheelNotches))
    }

    static func gridHeight(trackValue: Int) -> Double {
        Double(trackValue) / 4
    }

    static func trackValue(gridHeight: Double) -> Int {
        Int((gridHeight * 4).rounded())
    }

    static func clampField(_ value: Double) -> Double {
        guard value.isFinite else { return fieldMinimum }
        return min(fieldMaximum, max(fieldMinimum, value))
    }

    /// `CGHeight` Designer Increment `0.25`。`OemPlus` / `OemMinus` 在两端改成加到 Maximum / 减到 Minimum。
    static let fieldIncrement = 0.25

    static func nudgeField(_ value: Double, up: Bool) -> Double {
        let current = clampField(value)
        if up {
            if current > fieldMaximum - fieldIncrement {
                return fieldMaximum
            }
            return clampField(current + fieldIncrement)
        }
        if current < fieldMinimum + fieldIncrement {
            return fieldMinimum
        }
        return clampField(current - fieldIncrement)
    }

    /// `CGWidth2.Value = IIf(CGWidth.Value * 4 < Maximum, CDec(...), Maximum)`。
    static func trackValueFromField(_ value: Double) -> Int {
        let product = clampField(value) * 4
        if product >= Double(trackMaximum) { return trackMaximum }
        if product <= Double(trackMinimum) { return trackMinimum }
        return Int(product.rounded())
    }
}

/// 对照 `gSlash` / `BGSlash_Click` / `Keys.Oemcomma` / `OemPeriod` / `OemQuestion`。
enum LegacyGridDivision {
    static let minimum = 1
    static let maximum = 1920
    static let defaultSlash = 192
    static let prompt = "When the slash key (\"/\") is pressed, change grid division to:"

    static func clamp(_ value: Int) -> Int {
        min(maximum, max(minimum, value))
    }

    static func doubled(_ divide: Int) -> Int? {
        let next = divide * 2
        return next <= maximum ? next : nil
    }

    static func halved(_ divide: Int) -> Int? {
        let next = divide / 2
        return next >= minimum ? next : nil
    }

    /// `Val` 为 0 则取消；否则夹到 `CGDivide` 的 1…1920。
    static func parseSlash(_ text: String) -> Int? {
        let value = vbVal(text)
        if value == 0 { return nil }
        return clamp(Int(value.rounded(.towardZero)))
    }

    /// VB `Val`：读到第一个非数字字符为止。
    private static func vbVal(_ text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count && CharacterSet.whitespaces.contains(scalars[index]) {
            index += 1
        }
        guard index < scalars.count else { return 0 }
        var end = index
        if scalars[end] == "+" || scalars[end] == "-" { end += 1 }
        var sawDigit = false
        var sawDot = false
        while end < scalars.count {
            let value = scalars[end].value
            if value >= 48 && value <= 57 {
                sawDigit = true
                end += 1
                continue
            }
            if scalars[end] == "." && !sawDot {
                sawDot = true
                end += 1
                continue
            }
            break
        }
        if !sawDigit { return 0 }
        return Double(String(String.UnicodeScalarView(scalars[index..<end]))) ?? 0
    }
}

/// 对照 `MoveToColumn` / `MoveToBGM`：数字键把已选音换到 A1–A8 或第一列空的 B。
enum LegacyMoveNotes {
    struct Occupant: Equatable {
        var channel: String
        var vPosition: Double
        var length: Double
    }

    static func playableDisplay(forDigit digit: Int) -> String? {
        switch digit {
        case 1: return "16"
        case 2: return "11"
        case 3: return "12"
        case 4: return "13"
        case 5: return "14"
        case 6: return "15"
        case 7: return "18"
        case 8: return "19"
        default: return nil
        }
    }

    static func destination(source: String, display: String) -> String? {
        ChartDuplicate.writeChannel(source: source, display: display)
    }

    static func notesToMove<T>(sorted: [T], shiftFirstOnly: Bool) -> [T] {
        if shiftFirstOnly {
            return Array(sorted.prefix(1))
        }
        return sorted
    }

    static func digit(fromKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 29, 82: return 0
        case 18, 83: return 1
        case 19, 84: return 2
        case 20, 85: return 3
        case 21, 86: return 4
        case 23, 87: return 5
        case 22, 88: return 6
        case 26, 89: return 7
        case 28, 91: return 8
        default: return nil
        }
    }

    static func bgmDestination(moving: Occupant, occupants: [Occupant], ntInput: Bool) -> String {
        var lane = 0
        while lane < 999 {
            let channel = ChartBGM.displayChannel(lane: lane)
            let blocked = occupants.contains { other in
                other.channel == channel && overlaps(moving, other, ntInput: ntInput)
            }
            if !blocked {
                return channel
            }
            lane += 1
        }
        return ChartBGM.displayChannel(lane: 998)
    }

    static func requiredBGMColumnCount(destination: String, current: Int) -> Int {
        guard let lane = ChartBGM.lane(display: destination) else { return current }
        return max(current, lane + 1)
    }

    private static func overlaps(_ moving: Occupant, _ other: Occupant, ntInput: Bool) -> Bool {
        if ntInput {
            return other.vPosition <= moving.vPosition + moving.length
                && other.vPosition + other.length >= moving.vPosition
        }
        return other.vPosition == moving.vPosition
    }
}

/// 对照 `PMainInPreviewKeyDown` 方向键。从头 BPM（下标 0）之后的已选开始搬。
enum LegacyArrowMove {
    enum Direction: Equatable {
        case up
        case down
        case left
        case right

        static func fromKeyCode(_ keyCode: UInt16) -> Direction? {
            switch keyCode {
            case 126: return .up
            case 125: return .down
            case 123: return .left
            case 124: return .right
            default: return nil
            }
        }
    }

    static func direction(fromKeyCode keyCode: UInt16) -> Direction? {
        Direction.fromKeyCode(keyCode)
    }

    struct Note: Equatable {
        var realColumn: Int
        var vPosition: Double
        var length: Double
        var channel: String
    }

    struct Destination: Equatable {
        var realColumn: Int
        var vPosition: Double
        var channel: String
        var moved: Bool
    }

    struct Result: Equatable {
        var destinations: [Destination]
        var recordUndo: Bool
        var moved: Bool

        static let idle = Result(destinations: [], recordUndo: false, moved: false)
    }

    /// 默认 `GetMaxVPosition()` = `MeasureUpper(999)`，全 192 格是 192000。
    static let defaultMaxVPosition: Double = 192_000
    /// 原文 `muVPosition -= 191999`，不是再减一次 `maxV - 1`。
    static let upwardSubtractLiteral: Double = 191_999

    static func step(divide: Int, control: Bool, up: Bool) -> Double {
        if control {
            return up ? 1 : -1
        }
        let magnitude = 192.0 / Double(divide)
        return up ? magnitude : -magnitude
    }

    /// `ColumnArrayIndexToEnabledColumnIndex`：按 `nEnabled` 跳过未启用列。
    static func enabledIndex(real: Int, enabled: [Bool]) -> Int {
        var current = real
        guard real > 0 else { return current }
        for index in 0..<real {
            let isOn = index < enabled.count && enabled[index]
            if !isOn {
                current -= 1
            }
        }
        return current
    }

    /// `EnabledColumnIndexToColumnArrayIndex`。超出最后一列启用列时返回 `nil`，不发明非法车道。
    static func realIndex(enabled enabledColumn: Int, enabled: [Bool]) -> Int? {
        var target = enabledColumn
        var index = 0
        let count = enabled.count
        while true {
            if index >= count { break }
            if !enabled[index] {
                target += 1
            }
            if index >= target { break }
            index += 1
        }
        if target < 0 || target >= count || !enabled[target] {
            return nil
        }
        return target
    }

    /// Up / Down：`xVPosition - clamp <> 0`。Left：`-1 - mLeft <> 0`。Right：有音真的动了才记。
    static func shouldRecordUndo(
        direction: Direction,
        step: Double = 0,
        clamp: Double = 0,
        mLeft: Int = 0,
        moved: Bool = false
    ) -> Bool {
        switch direction {
        case .up, .down:
            return step - clamp != 0
        case .left:
            return -1 - mLeft != 0
        case .right:
            return moved
        }
    }

    static func move(
        notes: [Note],
        direction: Direction,
        enabled: [Bool],
        divide: Int = 16,
        control: Bool = false,
        step explicitStep: Double? = nil,
        ntInput: Bool = false,
        maxVPosition: Double = defaultMaxVPosition,
        displays: [String]? = nil
    ) -> Result {
        guard !notes.isEmpty else { return .idle }
        switch direction {
        case .up:
            let delta = explicitStep ?? step(divide: divide, control: control, up: true)
            return moveVertical(
                notes: notes,
                step: delta,
                ntInput: ntInput,
                maxVPosition: maxVPosition,
                upward: true
            )
        case .down:
            let delta = explicitStep ?? step(divide: divide, control: control, up: false)
            return moveVertical(
                notes: notes,
                step: delta,
                ntInput: ntInput,
                maxVPosition: maxVPosition,
                upward: false
            )
        case .left:
            return moveLeft(notes: notes, enabled: enabled, displays: displays)
        case .right:
            return moveRight(notes: notes, enabled: enabled, displays: displays)
        }
    }

    private static func moveVertical(
        notes: [Note],
        step: Double,
        ntInput: Bool,
        maxVPosition: Double,
        upward: Bool
    ) -> Result {
        let participants = notes.filter { !isScroll($0.channel) }
        guard !participants.isEmpty else {
            return Result(destinations: notes.map(unchanged), recordUndo: false, moved: false)
        }
        let clamp: Double
        if upward {
            var muV = maxVPosition - 1
            for note in participants {
                let end = note.vPosition + (ntInput ? note.length : 0) + step
                if end > muV {
                    muV = end
                }
            }
            muV -= upwardSubtractLiteral
            clamp = muV
        } else {
            var mV = 0.0
            for note in participants {
                let next = note.vPosition + step
                if next < mV {
                    mV = next
                }
            }
            clamp = mV
        }
        let record = shouldRecordUndo(direction: upward ? .up : .down, step: step, clamp: clamp)
        let destinations = notes.map { note -> Destination in
            if isScroll(note.channel) {
                return unchanged(note)
            }
            let vPosition = note.vPosition + step - clamp
            return Destination(
                realColumn: note.realColumn,
                vPosition: vPosition,
                channel: note.channel,
                moved: vPosition != note.vPosition
            )
        }
        return Result(
            destinations: destinations,
            recordUndo: record,
            moved: destinations.contains(where: \.moved)
        )
    }

    private static func moveLeft(notes: [Note], enabled: [Bool], displays: [String]?) -> Result {
        let participants = notes.filter { !isScroll($0.channel) }
        guard !participants.isEmpty else {
            return Result(destinations: notes.map(unchanged), recordUndo: false, moved: false)
        }
        var mLeft = 0
        for note in participants {
            let index = enabledIndex(real: note.realColumn, enabled: enabled)
            if index - 1 < mLeft {
                mLeft = index - 1
            }
        }
        let record = shouldRecordUndo(direction: .left, mLeft: mLeft)
        let destinations = notes.map { note -> Destination in
            if isScroll(note.channel) {
                return unchanged(note)
            }
            let index = enabledIndex(real: note.realColumn, enabled: enabled)
            return destination(
                note: note,
                newEnabled: index - 1 - mLeft,
                enabled: enabled,
                displays: displays
            )
        }
        return Result(
            destinations: destinations,
            recordUndo: record,
            moved: destinations.contains(where: \.moved)
        )
    }

    private static func moveRight(notes: [Note], enabled: [Bool], displays: [String]?) -> Result {
        let destinations = notes.map { note -> Destination in
            if isScroll(note.channel) {
                return unchanged(note)
            }
            let index = enabledIndex(real: note.realColumn, enabled: enabled)
            return destination(
                note: note,
                newEnabled: index + 1,
                enabled: enabled,
                displays: displays
            )
        }
        let moved = destinations.contains(where: \.moved)
        return Result(
            destinations: destinations,
            recordUndo: shouldRecordUndo(direction: .right, moved: moved),
            moved: moved
        )
    }

    private static func destination(
        note: Note,
        newEnabled: Int,
        enabled: [Bool],
        displays: [String]?
    ) -> Destination {
        guard let newReal = realIndex(enabled: newEnabled, enabled: enabled) else {
            return unchanged(note)
        }
        let channel = writeChannel(source: note.channel, realColumn: newReal, displays: displays)
        guard let channel, !isScroll(channel) else {
            return unchanged(note)
        }
        return Destination(
            realColumn: newReal,
            vPosition: note.vPosition,
            channel: channel,
            moved: newReal != note.realColumn || channel != note.channel
        )
    }

    private static func writeChannel(source: String, realColumn: Int, displays: [String]?) -> String? {
        guard let displays, displays.indices.contains(realColumn) else {
            return source
        }
        let display = displays[realColumn]
        if isScroll(display) {
            return nil
        }
        return ChartDuplicate.writeChannel(source: source, display: display) ?? display
    }

    private static func unchanged(_ note: Note) -> Destination {
        Destination(
            realColumn: note.realColumn,
            vPosition: note.vPosition,
            channel: note.channel,
            moved: false
        )
    }

    private static func isScroll(_ channel: String) -> Bool {
        channel.uppercased() == "SC"
    }
}

/// 对照 `DuplicateSelectedNotes`：列偏移加网格偏移，并带上鼠标下的那颗音。
enum ChartDuplicate {
    struct GridPoint: Equatable {
        var measure: Int
        var slot: Int
    }

    static func shiftedChannel(source: String, origin: String, target: String, lanes: [String]) -> String? {
        let sourceDisplay = ChartLayout.displayChannel(source)
        let originDisplay = ChartLayout.displayChannel(origin)
        let targetDisplay = ChartLayout.displayChannel(target)
        guard let sourceIndex = lanes.firstIndex(of: sourceDisplay),
              let originIndex = lanes.firstIndex(of: originDisplay),
              let targetIndex = lanes.firstIndex(of: targetDisplay) else {
            return nil
        }
        let destination = sourceIndex + (targetIndex - originIndex)
        guard lanes.indices.contains(destination), !lanes[destination].isEmpty else { return nil }
        return lanes[destination]
    }

    static func writeChannel(source: String, origin: String, target: String, lanes: [String]) -> String? {
        guard let display = shiftedChannel(source: source, origin: origin, target: target, lanes: lanes) else {
            return nil
        }
        return writeChannel(source: source, display: display)
    }

    /// 对照 `GetBMSChannelBy`：Hidden / Mine / Long 跟源音走，可见列用位移后的车道。
    static func writeChannel(source: String, display: String) -> String? {
        let family = source.uppercased().first
        if family == "5" || family == "6" {
            return ChartConvert.longChannel(for: display)
        }
        let hidden = family == "3" || family == "4"
        let mine = family == "D" || family == "E"
        return ChartWriteChannel.source(display: display, hidden: hidden, mine: mine)
    }

    struct NoteRef: Equatable {
        var columnIndex: Int
        var vPosition: Double
        var length: Double
    }

    struct Shift: Equatable {
        var columnDelta: Int
        var vPositionDelta: Double

        var isZero: Bool { columnDelta == 0 && vPositionDelta == 0 }
    }

    /// 对照 `OnDuplicateSelectedNotes`：列差和 vpos 差先算，再按左界 0、上界 `191999` 夹紧。
    static func shift(
        notes: [NoteRef],
        origin: NoteRef,
        mouseColumn: Int,
        mouseVPosition: Double,
        ntInput: Bool,
        disableVerticalMove: Bool = false,
        maxVPosition: Double = 191_999
    ) -> Shift {
        let mouseV = disableVerticalMove ? origin.vPosition : mouseVPosition
        let dVPosition = mouseV - origin.vPosition
        let colChange = mouseColumn - origin.columnIndex
        var dstColumn = 0
        var minVPosition = 0.0
        var maxEnd = maxVPosition
        for note in notes {
            let column = note.columnIndex + colChange
            if column < dstColumn {
                dstColumn = column
            }
            let vPosition = note.vPosition + dVPosition
            if vPosition < minVPosition {
                minVPosition = vPosition
            }
            let end = note.vPosition + (ntInput ? note.length : 0) + dVPosition
            if end > maxEnd {
                maxEnd = end
            }
        }
        return Shift(
            columnDelta: colChange - dstColumn,
            vPositionDelta: dVPosition - minVPosition - (maxEnd - maxVPosition)
        )
    }

    static func vPosition(beat: Double) -> Double { beat * 48 }

    static func beat(vPosition: Double) -> Double { vPosition / 48 }

    struct ShortCopy: Equatable {
        var event: ChartEventSnapshot
        var channel: String
        var vPosition: Double
    }

    struct LongCopy: Equatable {
        var note: LongNoteSnapshot
        var channel: String
        var vPosition: Double
        var length: Double
    }

    /// 对照第一次 `DuplicateSelectedNotes`：用源音加夹紧后的位移，得到副本落点。
    static func plan(
        shorts: [ChartEventSnapshot],
        longs: [LongNoteSnapshot],
        originChannel: String,
        originVPosition: Double,
        originLength: Double,
        mouseChannel: String,
        mouseVPosition: Double,
        lanes: [String],
        ntInput: Bool,
        disableVerticalMove: Bool = false
    ) -> (shorts: [ShortCopy], longs: [LongCopy])? {
        func column(of channel: String) -> Int? {
            lanes.firstIndex(of: ChartLayout.displayChannel(channel))
        }
        guard let originColumn = column(of: originChannel),
              let mouseColumn = column(of: mouseChannel) else {
            return nil
        }
        var refs: [NoteRef] = []
        for event in shorts {
            guard let index = column(of: event.channel) else { continue }
            refs.append(NoteRef(columnIndex: index, vPosition: vPosition(beat: event.beat), length: 0))
        }
        for note in longs {
            guard let index = column(of: note.channel) else { continue }
            let start = vPosition(beat: note.start.beat)
            refs.append(NoteRef(
                columnIndex: index,
                vPosition: start,
                length: vPosition(beat: note.end.beat) - start
            ))
        }
        let origin = NoteRef(columnIndex: originColumn, vPosition: originVPosition, length: originLength)
        if !refs.contains(where: {
            $0.columnIndex == origin.columnIndex && $0.vPosition == origin.vPosition && $0.length == origin.length
        }) {
            refs.append(origin)
        }
        let moved = shift(
            notes: refs,
            origin: origin,
            mouseColumn: mouseColumn,
            mouseVPosition: mouseVPosition,
            ntInput: ntInput,
            disableVerticalMove: disableVerticalMove
        )
        if moved.isZero {
            return nil
        }
        var shortCopies: [ShortCopy] = []
        for event in shorts {
            guard let index = column(of: event.channel) else { continue }
            let destination = index + moved.columnDelta
            guard lanes.indices.contains(destination), !lanes[destination].isEmpty,
                  let channel = writeChannel(source: event.channel, display: lanes[destination]) else {
                continue
            }
            shortCopies.append(ShortCopy(
                event: event,
                channel: channel,
                vPosition: vPosition(beat: event.beat) + moved.vPositionDelta
            ))
        }
        var longCopies: [LongCopy] = []
        for note in longs {
            guard let index = column(of: note.channel) else { continue }
            let destination = index + moved.columnDelta
            guard lanes.indices.contains(destination), !lanes[destination].isEmpty,
                  let channel = writeChannel(source: note.channel, display: lanes[destination]) else {
                continue
            }
            let start = vPosition(beat: note.start.beat)
            longCopies.append(LongCopy(
                note: note,
                channel: channel,
                vPosition: start + moved.vPositionDelta,
                length: vPosition(beat: note.end.beat) - start
            ))
        }
        if shortCopies.isEmpty && longCopies.isEmpty {
            return nil
        }
        return (shortCopies, longCopies)
    }

    static func previewEvent(_ copy: ShortCopy) -> ChartEventSnapshot {
        ChartEventSnapshot(
            measure: 0,
            channel: copy.channel,
            token: copy.event.token,
            fractionNumerator: 0,
            fractionDenominator: 1,
            beat: beat(vPosition: copy.vPosition),
            kind: copy.event.kind,
            sourceLine: -1
        )
    }

    static func previewLong(_ copy: LongCopy) -> LongNoteSnapshot {
        let startBeat = beat(vPosition: copy.vPosition)
        let endBeat = beat(vPosition: copy.vPosition + copy.length)
        return LongNoteSnapshot(
            channel: copy.channel,
            start: LongNoteEndpointSnapshot(
                measure: 0,
                fractionNumerator: 0,
                fractionDenominator: 1,
                beat: startBeat,
                token: copy.note.start.token,
                sourceLine: -1
            ),
            end: LongNoteEndpointSnapshot(
                measure: 0,
                fractionNumerator: 0,
                fractionDenominator: 1,
                beat: endBeat,
                token: copy.note.end.token,
                sourceLine: -1
            ),
            encoding: copy.note.encoding
        )
    }

    static func shiftedGrid(source: GridPoint, origin: GridPoint, target: GridPoint, slotsPerMeasure: Int) -> GridPoint? {
        guard slotsPerMeasure > 0, source.measure >= 0, origin.measure >= 0, target.measure >= 0 else {
            return nil
        }
        let sourceIndex = source.measure * slotsPerMeasure + source.slot
        let originIndex = origin.measure * slotsPerMeasure + origin.slot
        let targetIndex = target.measure * slotsPerMeasure + target.slot
        let destination = sourceIndex + (targetIndex - originIndex)
        guard destination >= 0 else { return nil }
        let measure = destination / slotsPerMeasure
        if measure > 999 { return nil }
        return GridPoint(measure: measure, slot: destination % slotsPerMeasure)
    }

    static func gridPoint(
        measure: Int,
        fractionNumerator: Int64,
        fractionDenominator: Int64,
        division: Int
    ) -> GridPoint? {
        guard division > 0, fractionDenominator > 0, measure >= 0 else { return nil }
        let slot = fractionNumerator * Int64(division) / fractionDenominator
        if slot < 0 { return nil }
        return GridPoint(measure: measure, slot: Int(slot))
    }

    static func notesToCopy<T: Hashable>(selected: Set<T>, origin: T) -> [T] {
        var notes = selected
        notes.insert(origin)
        return Array(notes)
    }
}

/// 对照 `EditorColumns.GetColumn`：隐藏是 `+0x30/-10` 或 `+0x40/-20`，地雷是 `+0xD0/-10` 或 `+0xE0/-20`。
enum ChartWriteChannel {
    static func source(display: String, hidden: Bool, mine: Bool) -> String {
        guard display.count == 2 else { return display }
        if mine {
            switch display[display.startIndex] {
            case "1": return "D\(display.dropFirst())"
            case "2": return "E\(display.dropFirst())"
            default: return display
            }
        }
        if hidden {
            switch display[display.startIndex] {
            case "1": return "3\(display.dropFirst())"
            case "2": return "4\(display.dropFirst())"
            default: return display
            }
        }
        return display
    }
}

enum ChartTool: String {
    case select = "Select"
    case write = "Write"
    case longNote = "Long note"
    case timeSelect = "Time selection"
}

enum ChartGridKind: Hashable {
    case grid
    case sub
    case measure
}

enum ChartInput {
    static let dragThreshold: CGFloat = 3

    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragThreshold
    }

    /// Notes draw above their time anchor. Keeping this offset makes a drag
    /// started in the middle of a note land at the same time when released.
    static func pointForAnchor(from pointer: CGPoint, anchorOffsetY: CGFloat) -> CGPoint {
        CGPoint(x: pointer.x, y: pointer.y + anchorOffsetY)
    }
}

enum ChartSelection {
    static func movedEvent(
        from source: ChartEventSnapshot,
        toMeasure measure: ChartMeasureSnapshot,
        channel: String,
        excludingSourceLines sourceLinesBeforeMove: Set<Int>,
        in snapshot: ChartSnapshot
    ) -> ChartEventSnapshot? {
        return snapshot.events.first {
            $0.measure == measure.measure
                && $0.channel == channel
                && $0.token == source.token
                && !sourceLinesBeforeMove.contains($0.sourceLine)
        }
    }
}

struct LongNoteEndpointSnapshot: Hashable {
    let measure: Int
    let fractionNumerator: Int64
    let fractionDenominator: Int64
    let beat: Double
    let token: String
    let sourceLine: Int
}

struct LongNoteSnapshot: Hashable {
    let channel: String
    let start: LongNoteEndpointSnapshot
    let end: LongNoteEndpointSnapshot
    let encoding: String
}

struct LongNoteDiagnosticSnapshot: Hashable {
    let sourceLine: Int
    let message: String
}

struct LongNoteSnapshotSet: Hashable {
    let notes: [LongNoteSnapshot]
    let diagnostics: [LongNoteDiagnosticSnapshot]
    let editable: Bool
    let editingReason: String
    let lnobjToken: String

    static let empty = LongNoteSnapshotSet(
        notes: [],
        diagnostics: [],
        editable: false,
        editingReason: "Open a BMS chart to edit long notes.",
        lnobjToken: ""
    )
}

struct ChartPlaySkinColor: Equatable {
    var note: ThemeColor
    var background: ThemeColor
}

struct ChartLane {
    let channel: String
    let title: String
    let width: CGFloat
    let normalColors: ThemeGradientColors
    let hiddenColors: ThemeGradientColors
    let longColors: ThemeGradientColors
    let textColor: NSColor
    let longTextColor: NSColor
    let backgroundColor: NSColor
    let backgroundThemeColor: ThemeColor
    let editable: Bool

    /// 共用绘制仍走主题的 `AdjustBrightness`。这里只换底色和音符底色数字。
    func applyingSkin(note: ThemeColor, background: ThemeColor, hiddenOpacity: Double) -> ChartLane {
        let column = ThemeColumn(
            legacyIndex: 0,
            width: max(1, Int(width.rounded())),
            title: title,
            isVisible: true,
            noteColor: note,
            textColor: ThemeColor(red: 255, green: 255, blue: 255),
            longNoteColor: note,
            longTextColor: ThemeColor(red: 255, green: 255, blue: 255),
            backgroundColor: background
        )
        return ChartLane(
            channel: channel,
            title: title,
            width: width,
            normalColors: column.derivedColors(longNote: false, hidden: false, hiddenOpacity: hiddenOpacity),
            hiddenColors: column.derivedColors(longNote: false, hidden: true, hiddenOpacity: hiddenOpacity),
            longColors: column.derivedColors(longNote: true, hidden: false, hiddenOpacity: hiddenOpacity),
            textColor: textColor,
            longTextColor: longTextColor,
            backgroundColor: background.nsColor,
            backgroundThemeColor: background,
            editable: editable
        )
    }
}

enum ChartLanes {
    static let onePlayer = [("16", 5), ("11", 6), ("12", 7), ("13", 8), ("14", 9), ("15", 10), ("18", 11), ("19", 12)]
    static let twoPlayer = [("21", 14), ("22", 15), ("23", 16), ("24", 17), ("25", 18), ("28", 19), ("29", 20), ("26", 21)]

    /// 按给定通道顺序取主题列宽。刮盘左右只改顺序。
    static func pairs(for channels: [String]) -> [(String, Int)] {
        let widths = Dictionary(uniqueKeysWithValues: onePlayer + twoPlayer)
        return channels.compactMap { channel in
            widths[channel].map { (channel, $0) }
        }
    }

    static func lane(channel: String, themeIndex: Int, theme: ChartTheme) -> ChartLane? {
        guard let column = theme.column(at: themeIndex), column.width != 0 else { return nil }
        return ChartLane(
            channel: channel,
            title: column.title,
            width: CGFloat(column.width),
            normalColors: column.derivedColors(longNote: false, hidden: false, hiddenOpacity: theme.visual.hiddenNoteOpacity),
            hiddenColors: column.derivedColors(longNote: false, hidden: true, hiddenOpacity: theme.visual.hiddenNoteOpacity),
            longColors: column.derivedColors(longNote: true, hidden: false, hiddenOpacity: theme.visual.hiddenNoteOpacity),
            textColor: column.textColor.nsColor,
            longTextColor: column.longTextColor.nsColor,
            backgroundColor: column.backgroundColor.nsColor,
            backgroundThemeColor: column.backgroundColor,
            editable: true
        )
    }

    static func timingLanes(scroll: Bool, bpm: Bool, stop: Bool, theme: ChartTheme) -> [ChartLane] {
        var lanes: [ChartLane] = []
        if scroll, let lane = lane(channel: "SC", themeIndex: 1, theme: theme) { lanes.append(lane) }
        if bpm, let lane = lane(channel: "03", themeIndex: 2, theme: theme) { lanes.append(lane) }
        if stop, let lane = lane(channel: "09", themeIndex: 3, theme: theme) { lanes.append(lane) }
        return lanes
    }

    static func bgaLanes(theme: ChartTheme) -> [ChartLane] {
        [("04", 23), ("07", 24), ("06", 25)].compactMap { lane(channel: $0.0, themeIndex: $0.1, theme: theme) }
    }

    static func bgmLanes(count: Int, theme: ChartTheme) -> [ChartLane] {
        guard count > 0, let column = theme.column(at: ChartBGM.themeColumnIndex), column.width != 0 else {
            return []
        }
        return (0..<count).map { lane in
            ChartLane(
                channel: ChartBGM.displayChannel(lane: lane),
                title: "B\(lane + 1)",
                width: CGFloat(column.width),
                normalColors: column.derivedColors(longNote: false, hidden: false, hiddenOpacity: theme.visual.hiddenNoteOpacity),
                hiddenColors: column.derivedColors(longNote: false, hidden: true, hiddenOpacity: theme.visual.hiddenNoteOpacity),
                longColors: column.derivedColors(longNote: true, hidden: false, hiddenOpacity: theme.visual.hiddenNoteOpacity),
                textColor: column.textColor.nsColor,
                longTextColor: column.longTextColor.nsColor,
                backgroundColor: column.backgroundColor.nsColor,
                backgroundThemeColor: column.backgroundColor,
                editable: true
            )
        }
    }

    /// 声道列宽按 BmsONE 像素，不跟 `gxWidth` 缩放。
    static func fixedWidthLane(
        channel: String,
        title: String,
        width: CGFloat,
        theme: ChartTheme
    ) -> ChartLane? {
        guard width > 0 else { return nil }
        let column = theme.column(at: ChartBGM.themeColumnIndex)
        let hiddenOpacity = theme.visual.hiddenNoteOpacity
        return ChartLane(
            channel: channel,
            title: title,
            width: width,
            normalColors: column?.derivedColors(longNote: false, hidden: false, hiddenOpacity: hiddenOpacity)
                ?? ThemeGradientColors(bright: ThemeColor(argb: 0xFFD2D2D2), dark: ThemeColor(argb: 0xFF696969)),
            hiddenColors: column?.derivedColors(longNote: false, hidden: true, hiddenOpacity: hiddenOpacity)
                ?? ThemeGradientColors(bright: ThemeColor(argb: 0xFFD2D2D2), dark: ThemeColor(argb: 0xFF696969)),
            longColors: column?.derivedColors(longNote: true, hidden: false, hiddenOpacity: hiddenOpacity)
                ?? ThemeGradientColors(bright: ThemeColor(argb: 0xFFD2D2D2), dark: ThemeColor(argb: 0xFF696969)),
            textColor: column?.textColor.nsColor ?? .white,
            longTextColor: column?.longTextColor.nsColor ?? .white,
            backgroundColor: column?.backgroundColor.nsColor ?? NSColor(red: 34 / 255, green: 34 / 255, blue: 34 / 255, alpha: 1),
            backgroundThemeColor: column?.backgroundColor ?? ThemeColor(argb: 0xFF222222),
            editable: true
        )
    }

    static func lanes(for pairs: [(String, Int)], theme: ChartTheme) -> [ChartLane] {
        pairs.compactMap { channel, index in
            // Side selection controls whether the 1P or 2P bank is shown. Legacy themes often
            // save 2P columns with Display=false while retaining a valid width, so honoring that
            // persisted flag here would make the selected 2P editor blank. Width=0 remains the
            // source-supported way to remove a lane from the selected bank.
            guard let column = theme.column(at: index), column.width != 0 else { return nil }
            return ChartLane(
                channel: channel,
                title: column.title,
                width: CGFloat(column.width),
                normalColors: column.derivedColors(longNote: false, hidden: false, hiddenOpacity: theme.visual.hiddenNoteOpacity),
                hiddenColors: column.derivedColors(longNote: false, hidden: true, hiddenOpacity: theme.visual.hiddenNoteOpacity),
                longColors: column.derivedColors(longNote: true, hidden: false, hiddenOpacity: theme.visual.hiddenNoteOpacity),
                textColor: column.textColor.nsColor,
                longTextColor: column.longTextColor.nsColor,
                backgroundColor: column.backgroundColor.nsColor,
                backgroundThemeColor: column.backgroundColor,
                editable: true
            )
        }
    }
}

struct ChartNoteRect: Hashable {
    let event: ChartEventSnapshot
    /// Legacy outline rectangle. Existing hit/layout tests treat `maxY` as the time anchor.
    let rect: CGRect
    let fill: CGRect
    let selection: CGRect
    let hit: CGRect
    let gradientStart: CGPoint
    let gradientEnd: CGPoint
    let labelOrigin: CGPoint
}

struct ChartLongNoteRect: Hashable {
    let note: LongNoteSnapshot
    let body: CGRect
    let startCap: CGRect
    let endCap: CGRect
    let fill: CGRect
    let outline: CGRect
    let selection: CGRect
    let startHit: CGRect
    let endHit: CGRect
    let gradientStart: CGPoint
    let gradientEnd: CGPoint
    let labelOrigin: CGPoint
}

/// 按拍查询长音。保留原数组下标，因此重叠时仍按旧代码的后画优先顺序命中。
private struct LongNoteIntervalIndex {
    private indirect enum Node {
        case leaf(indices: [Int], lower: Double, upper: Double)
        case branch(left: Node, right: Node, lower: Double, upper: Double)

        func collect(overlapping lower: Double, _ upper: Double, into result: inout [Int]) {
            let bounds: (Double, Double)
            switch self {
            case let .leaf(_, nodeLower, nodeUpper), let .branch(_, _, nodeLower, nodeUpper):
                bounds = (nodeLower, nodeUpper)
            }
            guard bounds.0 <= upper, bounds.1 >= lower else { return }
            switch self {
            case let .leaf(indices, _, _): result.append(contentsOf: indices)
            case let .branch(left, right, _, _):
                left.collect(overlapping: lower, upper, into: &result)
                right.collect(overlapping: lower, upper, into: &result)
            }
        }
    }

    private let root: Node?

    init(notes: [LongNoteSnapshot]) {
        let indices = notes.indices.sorted {
            min(notes[$0].start.beat, notes[$0].end.beat) < min(notes[$1].start.beat, notes[$1].end.beat)
        }
        func make(_ values: ArraySlice<Int>) -> Node? {
            guard !values.isEmpty else { return nil }
            let lower = values.map { min(notes[$0].start.beat, notes[$0].end.beat) }.min() ?? 0
            let upper = values.map { max(notes[$0].start.beat, notes[$0].end.beat) }.max() ?? 0
            if values.count <= 24 { return .leaf(indices: Array(values), lower: lower, upper: upper) }
            let middle = values.index(values.startIndex, offsetBy: values.count / 2)
            guard let left = make(values[..<middle]), let right = make(values[middle...]) else { return nil }
            return .branch(left: left, right: right, lower: lower, upper: upper)
        }
        root = make(indices[...])
    }

    func indices(overlapping lower: Double, _ upper: Double) -> [Int] {
        var result: [Int] = []
        root?.collect(overlapping: lower, upper, into: &result)
        return result.sorted()
    }
}

private struct PairedLongEndpointIdentity: Hashable {
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

struct ChartGridLine: Hashable {
    let y: CGFloat
    let kind: ChartGridKind
    var major: Bool { kind == .measure }

    init(y: CGFloat, major: Bool) {
        self.y = y
        self.kind = major ? .measure : .grid
    }

    init(y: CGFloat, kind: ChartGridKind) {
        self.y = y
        self.kind = kind
    }
}

struct ChartLayout {
    static let measureGutter: CGFloat = 50
    /// 对照 BmsONE `SequenceView.cpp` 主控道宽。不跟 `gxWidth` 缩放。
    static let masterLaneWidth: CGFloat = 64
    static let laneGap: CGFloat = 5
    static let noteHeight: CGFloat = 10
    private static let maximumRenderableBeat = 1_000_000_000.0

    let snapshot: ChartSnapshot
    let longNotes: LongNoteSnapshotSet
    let theme: ChartTheme
    let side: ChartSide
    let pixelsPerQuarterBeat: CGFloat
    let gxWidth: CGFloat
    let division: Int
    let subDivision: Int
    let showGrid: Bool
    let showSubGrid: Bool
    let showMeasureBar: Bool
    let showBackground: Bool
    let showMeasureNumber: Bool
    let showVerticalLine: Bool
    let showColumnCaption: Bool
    let showMasterLane: Bool
    let lanes: [ChartLane]
    let laneFrames: [String: CGRect]
    let contentSize: CGSize
    let masterLaneFrame: CGRect
    private let eventsByBeat: [ChartEventSnapshot]
    private let measuresByStart: [ChartMeasureSnapshot]
    private let pairedLongEndpoints: Set<PairedLongEndpointIdentity>
    private let longNoteIntervals: LongNoteIntervalIndex

    init(
        snapshot: ChartSnapshot,
        longNotes: LongNoteSnapshotSet = .empty,
        theme: ChartTheme = .defaultTheme,
        side: ChartSide,
        pixelsPerQuarterBeat: CGFloat,
        division: Int,
        subDivision: Int = 4,
        showGrid: Bool = true,
        showSubGrid: Bool = true,
        showMeasureBar: Bool = true,
        showBackground: Bool = true,
        showMeasureNumber: Bool = true,
        showVerticalLine: Bool = true,
        showColumnCaption: Bool = true,
        showsTwoPlayerColumns: Bool = true,
        bgmColumnCount: Int = 0,
        showsScrollColumn: Bool = false,
        showsBPMColumn: Bool = false,
        showsStopColumn: Bool = false,
        showsBGAColumns: Bool = false,
        gxWidth: CGFloat = 1,
        showMasterLane: Bool = false,
        hiddenPlayChannels: Set<String> = [],
        soundChannelLanes: [ChartLane] = [],
        onePlayerOrder: [(String, Int)]? = nil,
        twoPlayerOrder: [(String, Int)]? = nil,
        playSkinColors: [String: ChartPlaySkinColor] = [:]
    ) {
        precondition((1...1920).contains(division))
        precondition((1...1920).contains(subDivision))
        var sanitizedSnapshot = snapshot
        sanitizedSnapshot.measures = snapshot.measures.filter { measure in
            measure.start.isFinite && measure.length.isFinite
                && measure.start >= 0 && measure.length > 0
                && measure.start <= Self.maximumRenderableBeat
                && measure.length <= Self.maximumRenderableBeat - measure.start
        }
        sanitizedSnapshot.events = snapshot.events.filter { event in
            event.beat.isFinite && event.beat >= 0 && event.beat <= Self.maximumRenderableBeat
        }
        let omittedMeasures = snapshot.measures.count - sanitizedSnapshot.measures.count
        let omittedEvents = snapshot.events.count - sanitizedSnapshot.events.count
        if omittedMeasures > 0 || omittedEvents > 0 {
            sanitizedSnapshot.editable = false
            sanitizedSnapshot.editingReason = "Chart editing is unavailable because some positions are outside the native canvas range."
            let omittedSummary = "The native canvas omitted \(omittedMeasures) measures and \(omittedEvents) chart objects outside its renderable range."
            sanitizedSnapshot.diagnostics.append(ChartDiagnosticSnapshot(
                sourceLine: 0,
                message: omittedSummary
            ))
        }
        self.snapshot = sanitizedSnapshot
        self.longNotes = longNotes
        self.longNoteIntervals = LongNoteIntervalIndex(notes: longNotes.notes)
        self.theme = theme
        self.side = side
        self.pixelsPerQuarterBeat = pixelsPerQuarterBeat
        self.gxWidth = max(0.000_1, gxWidth)
        self.division = division
        self.subDivision = subDivision
        self.showGrid = showGrid
        self.showSubGrid = showSubGrid
        self.showMeasureBar = showMeasureBar
        self.showBackground = showBackground
        self.showMeasureNumber = showMeasureNumber
        self.showVerticalLine = showVerticalLine
        self.showColumnCaption = showColumnCaption
        self.showMasterLane = showMasterLane
        let oneSource = onePlayerOrder ?? ChartLanes.onePlayer
        let twoSource = twoPlayerOrder ?? ChartLanes.twoPlayer
        let onePlayer = ChartLanes.lanes(
            for: oneSource.filter { !hiddenPlayChannels.contains($0.0) },
            theme: theme
        )
        let twoPlayer = showsTwoPlayerColumns
            ? ChartLanes.lanes(
                for: twoSource.filter { !hiddenPlayChannels.contains($0.0) },
                theme: theme
            )
            : []
        var resolved: [ChartLane]
        switch side {
        case .onePlayer: resolved = onePlayer
        case .twoPlayer: resolved = twoPlayer.isEmpty ? onePlayer : twoPlayer
        case .both:
            let divider = ChartLane(
                channel: "",
                title: "",
                width: Self.laneGap,
                normalColors: ThemeGradientColors(bright: ThemeColor(argb: 0), dark: ThemeColor(argb: 0)),
                hiddenColors: ThemeGradientColors(bright: ThemeColor(argb: 0), dark: ThemeColor(argb: 0)),
                longColors: ThemeGradientColors(bright: ThemeColor(argb: 0), dark: ThemeColor(argb: 0)),
                textColor: .clear,
                longTextColor: .clear,
                backgroundColor: .clear,
                backgroundThemeColor: ThemeColor(argb: 0),
                editable: false
            )
            resolved = twoPlayer.isEmpty ? onePlayer : onePlayer + [divider] + twoPlayer
        }
        if !playSkinColors.isEmpty {
            resolved = resolved.map { lane in
                guard let skin = playSkinColors[lane.channel] else { return lane }
                return lane.applyingSkin(
                    note: skin.note,
                    background: skin.background,
                    hiddenOpacity: theme.visual.hiddenNoteOpacity
                )
            }
        }
        var withExtras = ChartLanes.timingLanes(
            scroll: showsScrollColumn,
            bpm: showsBPMColumn,
            stop: showsStopColumn,
            theme: theme
        )
        withExtras += resolved
        if showsBGAColumns {
            withExtras += ChartLanes.bgaLanes(theme: theme)
        }
        if bgmColumnCount > 0 {
            withExtras += ChartLanes.bgmLanes(count: bgmColumnCount, theme: theme)
        }
        let extras = soundChannelLanes.filter { !$0.channel.isEmpty && $0.width > 0 }
        lanes = withExtras + extras
        var frames: [String: CGRect] = [:]
        let scale = self.gxWidth
        let gutter = Self.measureGutter * scale
        let masterWidth = showMasterLane ? Self.masterLaneWidth : 0
        var x = gutter + masterWidth
        for lane in withExtras {
            let width = lane.width * scale
            if !lane.channel.isEmpty { frames[lane.channel] = CGRect(x: x, y: 0, width: width, height: 1) }
            x += width
        }
        for lane in extras {
            frames[lane.channel] = CGRect(x: x, y: 0, width: lane.width, height: 1)
            x += lane.width
        }
        laneFrames = frames
        eventsByBeat = sanitizedSnapshot.events.sorted { ($0.beat, $0.sourceLine) < ($1.beat, $1.sourceLine) }
        measuresByStart = sanitizedSnapshot.measures.sorted { $0.start < $1.start }
        pairedLongEndpoints = Set(longNotes.notes.flatMap { note in
            [
                PairedLongEndpointIdentity(channel: note.channel, endpoint: note.start),
                PairedLongEndpointIdentity(channel: note.channel, endpoint: note.end)
            ]
        })
        let chartEnd = max(4, sanitizedSnapshot.measures.map { $0.start + $0.length }.max() ?? 4)
        let height = ceil(chartEnd * pixelsPerQuarterBeat) + 8
        contentSize = CGSize(width: x + 12, height: height)
        masterLaneFrame = showMasterLane
            ? CGRect(x: gutter, y: 0, width: Self.masterLaneWidth, height: height)
            : .zero
    }

    func y(forBeat beat: Double) -> CGFloat {
        LegacyChartPaint.panelY(contentHeight: contentSize.height, beat: beat, pixelsPerQuarterBeat: pixelsPerQuarterBeat)
    }

    func beat(atY y: CGFloat) -> Double {
        LegacyChartPaint.beat(contentHeight: contentSize.height, y: y, pixelsPerQuarterBeat: pixelsPerQuarterBeat)
    }

    func eventRect(_ event: ChartEventSnapshot) -> ChartNoteRect? {
        guard let lane = laneFrames[displayChannel(for: event.channel)] else { return nil }
        let paint = LegacyChartPaint.shortNote(
            laneLeft: lane.minX,
            laneWidth: lane.width,
            anchorY: y(forBeat: event.beat),
            noteHeight: CGFloat(theme.visual.noteHeight),
            labelShift: CGPoint(
                x: CGFloat(theme.visual.labelHorizontalShift),
                y: CGFloat(theme.visual.labelVerticalShift)
            )
        )
        return ChartNoteRect(
            event: event,
            rect: paint.outline,
            fill: paint.fill,
            selection: paint.selection,
            hit: paint.hit,
            gradientStart: paint.gradientStart,
            gradientEnd: paint.gradientEnd,
            labelOrigin: paint.labelOrigin
        )
    }

    func visibleNoteRects(in viewport: CGRect) -> [ChartNoteRect] {
        let beatRange = visibleBeatRange(in: viewport)
        let start = lowerBound(eventsByBeat, beat: beatRange.lowerBound - Double(CGFloat(theme.visual.noteHeight) / pixelsPerQuarterBeat), value: \.beat)
        let end = upperBound(eventsByBeat, beat: beatRange.upperBound, value: \.beat)
        return eventsByBeat[start..<end]
            .filter { !isPairedLongEndpoint($0) }
            .compactMap(eventRect)
            .filter { $0.rect.intersects(viewport) }
    }

    func hitTest(_ point: CGPoint) -> ChartEventSnapshot? {
        let beat = beat(atY: point.y)
        let tolerance = Double(CGFloat(theme.visual.noteHeight + 1) / pixelsPerQuarterBeat)
        let start = lowerBound(eventsByBeat, beat: beat - tolerance, value: \.beat)
        let end = upperBound(eventsByBeat, beat: beat + tolerance, value: \.beat)
        return eventsByBeat[start..<end]
            .reversed()
            .filter { !isPairedLongEndpoint($0) }
            .compactMap(eventRect)
            .first(where: { $0.hit.contains(point) })?.event
    }

    func longNoteRect(_ note: LongNoteSnapshot) -> ChartLongNoteRect? {
        guard let lane = laneFrames[displayChannel(for: note.channel)], note.start.beat.isFinite, note.end.beat.isFinite else {
            return nil
        }
        let paint = LegacyChartPaint.longNote(
            laneLeft: lane.minX,
            laneWidth: lane.width,
            startAnchorY: y(forBeat: note.start.beat),
            endAnchorY: y(forBeat: note.end.beat),
            noteHeight: CGFloat(theme.visual.noteHeight),
            labelShift: CGPoint(
                x: CGFloat(theme.visual.longLabelHorizontalShift),
                y: CGFloat(theme.visual.labelVerticalShift)
            )
        )
        return ChartLongNoteRect(
            note: note,
            body: paint.fill,
            startCap: paint.startCap.outline,
            endCap: paint.endCap.outline,
            fill: paint.fill,
            outline: paint.outline,
            selection: paint.selection,
            startHit: paint.startCap.hit,
            endHit: paint.endCap.hit,
            gradientStart: paint.gradientStart,
            gradientEnd: paint.gradientEnd,
            labelOrigin: paint.labelOrigin
        )
    }

    func visibleLongNoteRects(in viewport: CGRect) -> [ChartLongNoteRect] {
        let beats = visibleBeatRange(in: viewport)
        return longNoteIntervals.indices(overlapping: beats.lowerBound, beats.upperBound)
            .compactMap { longNoteRect(longNotes.notes[$0]) }.filter {
            $0.fill.intersects(viewport) || $0.outline.intersects(viewport)
                || $0.startCap.intersects(viewport) || $0.endCap.intersects(viewport)
        }
    }

    func hitTestLongNote(_ point: CGPoint) -> (note: LongNoteSnapshot, part: LongNoteHitPart)? {
        let beat = beat(atY: point.y)
        let tolerance = Double(CGFloat(theme.visual.noteHeight + 1) / pixelsPerQuarterBeat)
        let candidates = longNoteIntervals.indices(overlapping: beat - tolerance, beat + tolerance)
        for index in candidates.reversed() {
            guard let item = longNoteRect(longNotes.notes[index]) else { continue }
            if item.startHit.contains(point) {
                return (item.note, .startCap)
            }
            if item.endHit.contains(point) {
                return (item.note, .endCap)
            }
            if item.fill.contains(point) {
                return (item.note, .body)
            }
        }
        return nil
    }

    func lane(at point: CGPoint) -> ChartLane? {
        lanes.first { lane in
            guard let frame = laneFrames[lane.channel] else { return false }
            return point.x >= frame.minX && point.x < frame.maxX
        }
    }

    /// 对照 BmsONE 时间线左侧小节列。主控道在沟槽右边，不能算小节列。
    func isMeasureArea(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.x < Self.measureGutter * gxWidth
    }

    func isMasterLane(_ point: CGPoint) -> Bool {
        showMasterLane && point.x >= masterLaneFrame.minX && point.x < masterLaneFrame.maxX
    }

    var gridLeadingX: CGFloat {
        showMasterLane ? masterLaneFrame.maxX : 0
    }

    func measure(at point: CGPoint) -> ChartMeasureSnapshot? {
        let beat = beat(atY: point.y)
        let index = upperBound(measuresByStart, beat: beat, value: \.start)
        guard index > 0 else { return nil }
        let candidate = measuresByStart[index - 1]
        return beat >= candidate.start && beat < candidate.start + candidate.length ? candidate : nil
    }

    /// Mirrors MainWindow.SnapToGrid: floor from measure bottom, with a step
    /// of 4/division quarter beats. It deliberately does not divide a measure
    /// into `division` equal fractions.
    func snapTarget(at point: CGPoint) -> (measure: ChartMeasureSnapshot, slot: Int)? {
        guard let measure = measure(at: point) else { return nil }
        let beat = beat(atY: point.y)
        let rawSlot = Int(floor((beat - measure.start) * Double(division) / 4.0))
        let slots = max(1, Int(ceil(measure.length * Double(division) / 4.0)))
        return (measure, min(max(0, rawSlot), slots - 1))
    }

    func anchorY(for target: (measure: ChartMeasureSnapshot, slot: Int)) -> CGFloat {
        let beat = target.measure.start + Double(target.slot) * 4.0 / Double(division)
        return y(forBeat: beat)
    }

    static func displayChannel(_ sourceChannel: String) -> String {
        if sourceChannel == "01" { return ChartBGM.displayChannel(lane: 0) }
        if sourceChannel == "08" { return "03" }
        if sourceChannel == "SC" { return "SC" }
        if ChartBGM.lane(display: sourceChannel) != nil { return sourceChannel.uppercased() }
        guard sourceChannel.count == 2 else { return sourceChannel }
        let characters = Array(sourceChannel)
        switch characters[0] {
        case "3", "5", "D": return "1\(characters[1])"
        case "4", "6", "E": return "2\(characters[1])"
        default: return sourceChannel
        }
    }

    func displayChannel(for sourceChannel: String) -> String {
        Self.displayChannel(sourceChannel)
    }

    func fillsColumnBackground(_ lane: ChartLane) -> Bool {
        guard showBackground else { return false }
        let color = lane.backgroundThemeColor
        return LegacyPanelGuides.shouldFillBackground(red: color.red, green: color.green, blue: color.blue)
    }

    func measureCaption(for measure: ChartMeasureSnapshot) -> String {
        LegacyPanelGuides.measureCaption(measure.measure)
    }

    var measureLabelColor: NSColor {
        theme.columns.first { $0.legacyIndex == 0 }?.textColor.nsColor
            ?? theme.visual.columnTitle.nsColor
    }

    private func isPairedLongEndpoint(_ event: ChartEventSnapshot) -> Bool {
        pairedLongEndpoints.contains(PairedLongEndpointIdentity(event: event))
    }

    func gridLines(in viewport: CGRect) -> [ChartGridLine] {
        var result: [ChartGridLine] = []
        let beatRange = visibleBeatRange(in: viewport)
        let lower = lowerBound(measuresByStart, beat: beatRange.lowerBound, value: \.start)
        let first = lower > 0 ? lower - 1 : 0
        let last = upperBound(measuresByStart, beat: beatRange.upperBound, value: \.start)
        for measure in measuresByStart[first..<last] where measure.start + measure.length >= beatRange.lowerBound && measure.start <= beatRange.upperBound {
            if showGrid {
                appendSlots(measure: measure, divisions: division, kind: .grid, beatRange: beatRange, viewport: viewport, into: &result)
            }
            if showSubGrid {
                appendSlots(measure: measure, divisions: subDivision, kind: .sub, beatRange: beatRange, viewport: viewport, into: &result)
            }
            if showMeasureBar {
                let startY = y(forBeat: measure.start)
                if startY >= viewport.minY - 1 && startY <= viewport.maxY + 1 {
                    result.append(ChartGridLine(y: startY, kind: .measure))
                }
            }
            // Native extra: the exclusive MeasureUpper is still drawn so a
            // partial-ratio measure keeps an exact final boundary.
            let endY = y(forBeat: measure.start + measure.length)
            if endY >= viewport.minY - 1 && endY <= viewport.maxY + 1 {
                result.append(ChartGridLine(y: endY, kind: .measure))
            }
        }
        return result
    }

    private func appendSlots(
        measure: ChartMeasureSnapshot,
        divisions: Int,
        kind: ChartGridKind,
        beatRange: ClosedRange<Double>,
        viewport: CGRect,
        into result: inout [ChartGridLine]
    ) {
        let step = 4.0 / Double(max(1, divisions))
        let firstSlot = max(0, Int(ceil((beatRange.lowerBound - measure.start) / step - 0.000_000_1)))
        let lastSlot = min(
            Int(floor((measure.length - 0.000_000_1) / step)),
            Int(floor((beatRange.upperBound - measure.start) / step))
        )
        guard firstSlot <= lastSlot else { return }
        for slot in firstSlot...lastSlot {
            let lineY = y(forBeat: measure.start + Double(slot) * step)
            if lineY >= viewport.minY - 1 && lineY <= viewport.maxY + 1 {
                result.append(ChartGridLine(y: lineY, kind: kind))
            }
        }
    }

    private func visibleBeatRange(in viewport: CGRect) -> ClosedRange<Double> {
        let low = beat(atY: viewport.maxY)
        let high = beat(atY: viewport.minY)
        return min(low, high)...max(low, high)
    }

    private func lowerBound<T>(_ values: [T], beat: Double, value: (T) -> Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if value(values[middle]) < beat {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func upperBound<T>(_ values: [T], beat: Double, value: (T) -> Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if value(values[middle]) <= beat {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

enum LongNoteHitPart {
    case startCap
    case endCap
    case body
}
