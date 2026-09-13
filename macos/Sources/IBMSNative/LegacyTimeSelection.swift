import CoreGraphics
import Foundation

enum TimeSelectionLine: Int, Equatable {
    case none = 0
    case start = 1
    case half = 2
    case end = 3
}

/// 时间选择条上三个可点数字，对照 `FSSS` / `FSSL` / `FSSH`。
enum TimeSelectionField: Equatable {
    case start
    case length
    case half
}

struct TimeSelection: Equatable {
    var start: Double
    var length: Double
    var half: Double

    static let legacyDefault = TimeSelection(start: 192, length: 0, half: 0)

    var lower: Double { length > 0 ? start : start + length }
    var upper: Double { length < 0 ? start : start + length }
    var halfPosition: Double { start + half }

    static func vPosition(beat: Double) -> Double { beat * 48 }
    static func beat(vPosition: Double) -> Double { vPosition / 48 }
}

enum TimeSelectionLayout {
    static let stripHeight: CGFloat = 22
    static let start = CGRect(x: 0, y: 1, width: 23, height: 20)
    static let length = CGRect(x: 23, y: 1, width: 23, height: 20)
    static let half = CGRect(x: 46, y: 1, width: 23, height: 20)
    static let reverse = CGRect(x: 69, y: 1, width: 102, height: 20)
    static let multiply = CGRect(x: 171, y: 2, width: 15, height: 17)
    static let numerator = CGRect(x: 186, y: 0, width: 60, height: 22)
    static let divide = CGRect(x: 246, y: 2, width: 15, height: 17)
    static let denominator = CGRect(x: 261, y: 0, width: 60, height: 22)
    static let apply = CGRect(x: 321, y: 1, width: 95, height: 20)
    static let bpm = CGRect(x: 416, y: 0, width: 80, height: 22)
    static let calculate = CGRect(x: 496, y: 1, width: 104, height: 20)
    static let convertStop = CGRect(x: 600, y: 1, width: 117, height: 20)
    static let startTooltip = "Selection Start Position"
    static let lengthTooltip = "Selection Length"
    static let halfTooltip = "Selection Split Position"
    static let reverseTitle = "Reverse Selection"
    static let applyTitle = "Expand By Ratio"
    static let calculateTitle = "Relocate By Value"
    static let convertTitle = "Transform Into Stop"
    static let defaultNumerator = "2"
    static let defaultDenominator = "1"
    static let defaultBPM = "120"
    static let fieldBackground = ThemeColor(argb: 0xFFFFC0C0)
    static let actionBackground = ThemeColor(argb: 0xFFC0C0FF)
}

enum LegacyTimeSelection {
    static func validate(_ selection: TimeSelection, maxVPosition: Double) -> TimeSelection {
        var next = selection
        let limit = max(0, maxVPosition - 1)
        if next.start < 0 {
            next.length += next.start
            next.half += next.start
            next.start = 0
        }
        if next.start > limit {
            next.length += next.start - limit
            next.half += next.start - limit
            next.start = limit
        }
        if next.start + next.length < 0 {
            next.length = -next.start
        }
        if next.start + next.length > limit {
            next.length = limit - next.start
        }
        if sign(next.half) != sign(next.length) {
            next.half = 0
        }
        if abs(next.half) > abs(next.length) {
            next.half = next.length
        }
        return next
    }

    static func reverse(_ selection: TimeSelection) -> TimeSelection {
        TimeSelection(
            start: selection.start + selection.length,
            length: -selection.length,
            half: selection.half - selection.length
        )
    }

    static func hitLine(
        pointerY: CGFloat,
        startY: CGFloat,
        halfY: CGFloat,
        endY: CGFloat,
        threshold: CGFloat
    ) -> TimeSelectionLine {
        if abs(pointerY - endY) <= threshold { return .end }
        if abs(pointerY - halfY) <= threshold { return .half }
        if abs(pointerY - startY) <= threshold { return .start }
        return .none
    }

    static func begin(
        at vPosition: Double,
        snapped: Double?,
        current: TimeSelection,
        line: TimeSelectionLine
    ) -> TimeSelection {
        let value = snapped ?? vPosition
        switch line {
        case .start:
            return TimeSelection(
                start: value,
                length: current.length + current.start - value,
                half: current.half + current.start - value
            )
        case .half:
            return TimeSelection(start: current.start, length: current.length, half: value - current.start)
        case .end:
            return TimeSelection(start: current.start, length: value - current.start, half: current.half)
        case .none:
            return TimeSelection(start: value, length: 0, half: 0)
        }
    }

    static func drag(
        to vPosition: Double,
        snapped: Double?,
        current: TimeSelection,
        line: TimeSelectionLine,
        noteVPosition: Double?
    ) -> TimeSelection {
        let raw = noteVPosition ?? vPosition
        let value = noteVPosition != nil ? raw : (snapped ?? raw)
        switch line {
        case .start:
            return TimeSelection(
                start: value,
                length: current.length + current.start - value,
                half: current.half + current.start - value
            )
        case .half:
            return TimeSelection(start: current.start, length: current.length, half: value - current.start)
        case .end:
            return TimeSelection(start: current.start, length: value - current.start, half: current.half)
        case .none:
            let end = value
            let length = end - current.start
            return TimeSelection(start: current.start, length: length, half: length / 2)
        }
    }

    static func fillRect(
        start: Double,
        length: Double,
        contentHeight: CGFloat,
        pixelsPerQuarterBeat: CGFloat,
        width: CGFloat
    ) -> CGRect {
        let gxHeight = pixelsPerQuarterBeat / 48
        let topV = start + (length > 0 ? length : 0)
        let topY = LegacyChartPaint.panelY(contentHeight: contentHeight, beat: beat(vPosition: topV), pixelsPerQuarterBeat: pixelsPerQuarterBeat)
        let extra: CGFloat = length == 0 ? 0 : 1
        return CGRect(x: 0, y: topY + extra, width: width, height: abs(length) * gxHeight)
    }

    static func lineY(
        vPosition: Double,
        contentHeight: CGFloat,
        pixelsPerQuarterBeat: CGFloat
    ) -> CGFloat {
        LegacyChartPaint.panelY(
            contentHeight: contentHeight,
            beat: beat(vPosition: vPosition),
            pixelsPerQuarterBeat: pixelsPerQuarterBeat
        )
    }

    static func hoverOutline(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - 1), height: max(0, rect.height - 1))
    }

    static func highlightColumn(_ color: ThemeColor, factor: Double = 2) -> ThemeColor {
        func clamp(_ value: Double) -> UInt8 {
            UInt8(min(255, max(0, value.rounded(.toNearestOrEven))))
        }
        return ThemeColor(argb:
            (UInt32(clamp(Double(color.alpha) * factor)) << 24)
            | (UInt32(clamp(Double(color.red) * factor)) << 16)
            | (UInt32(clamp(Double(color.green) * factor)) << 8)
            | UInt32(clamp(Double(color.blue) * factor))
        )
    }

    static func bpmAt(
        vPosition: Double,
        header: Double,
        events: [(vPosition: Double, value: Double)]
    ) -> Double {
        var current = header
        for event in events where event.vPosition <= vPosition {
            current = event.value
        }
        return current
    }

    static func convertAreaToStopAllowed(
        start: Double,
        length: Double,
        noteVPositions: [Double]
    ) -> Bool {
        guard length != 0 else { return false }
        let lower = length > 0 ? start : start + length
        let upper = length < 0 ? start : start + length
        return !noteVPositions.contains { $0 > lower && $0 <= upper }
    }

    static func stopValue(length: Double) -> Double {
        length * 10_000
    }

    static func formatField(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(value)
    }

    /// 对照 `InputBox` 标题，原文空串。
    static let fieldTitle = ""

    static func fieldValue(_ field: TimeSelectionField, of selection: TimeSelection) -> Double {
        switch field {
        case .start: return selection.start
        case .length: return selection.length
        case .half: return selection.half
        }
    }

    /// 对照 `FSSS_Click` / `FSSL_Click` / `FSSH_Click` 的 `xMin` / `xMax`。
    /// Half 在 `length < 0` 时会出现 `min > max`，按原文保留。
    static func bounds(
        _ field: TimeSelectionField,
        selection: TimeSelection,
        maxVPosition: Double
    ) -> (min: Double, max: Double) {
        switch field {
        case .start:
            let xMax = selection.length > 0 ? maxVPosition - selection.length : maxVPosition
            let xMin = selection.length < 0 ? -selection.length : 0
            return (xMin, xMax)
        case .length:
            return (-selection.start, maxVPosition - selection.start)
        case .half:
            let xMax = selection.length > 0 ? selection.length : 0
            let xMin = selection.length > 0 ? 0 : -selection.length
            return (xMin, xMax)
        }
    }

    static func fieldPrompt(min: Double, max: Double) -> String {
        "Please enter a number between \(formatField(min)) and \(formatField(max))."
    }

    /// VB `Val`：跳过前导空白；可选正负号；读数字和一个小数点；
    /// 第一个非法字符停；没有数字则 `0`。
    static func val(_ text: String) -> Double {
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

    /// 对照 `InputBoxDouble`。精确空串是取消；先夹到上限，再夹到下限。
    static func parseFieldInput(_ text: String, min: Double, max: Double) -> Double? {
        if text == "" { return nil }
        var value = val(text)
        if value > max { value = max }
        if value < min { value = min }
        return value
    }

    /// 写入对应分量，再走 `ValidateSelection`。
    static func applyField(
        _ field: TimeSelectionField,
        value: Double,
        to selection: TimeSelection,
        maxVPosition: Double
    ) -> TimeSelection {
        var next = selection
        switch field {
        case .start: next.start = value
        case .length: next.length = value
        case .half: next.half = value
        }
        return validate(next, maxVPosition: maxVPosition)
    }

    static func beat(vPosition: Double) -> Double {
        TimeSelection.beat(vPosition: vPosition)
    }

    static func maxVPosition(chartEndBeat: Double) -> Double {
        max(192_000, chartEndBeat * 48)
    }

    static func noteHoverOutline(laneLeft: CGFloat, laneWidth: CGFloat, anchorY: CGFloat, noteHeight: CGFloat) -> CGRect {
        hoverOutline(CGRect(x: laneLeft, y: anchorY - noteHeight - 1, width: laneWidth + 1, height: noteHeight + 3))
    }

    static func longNoteHoverOutline(
        laneLeft: CGFloat,
        laneWidth: CGFloat,
        startAnchorY: CGFloat,
        endAnchorY: CGFloat,
        noteHeight: CGFloat
    ) -> CGRect {
        let lengthPixels = startAnchorY - endAnchorY
        return hoverOutline(CGRect(
            x: laneLeft,
            y: endAnchorY - noteHeight - 1,
            width: laneWidth + 1,
            height: lengthPixels + noteHeight + 3
        ))
    }

    static func timeHoverRect(lineY: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: 0, y: lineY - 1, width: max(0, width - 1), height: 2)
    }

    /// 对照 `CalculateGreatestVPosition`。空则 0。NT 开看 `VPosition + Length`，关则只看 `VPosition`。
    static func greatestVPosition(
        notes: [(vPosition: Double, length: Double)],
        ntInput: Bool
    ) -> Double {
        var greatest = 0.0
        for note in notes {
            let value = ntInput ? note.vPosition + note.length : note.vPosition
            if value > greatest {
                greatest = value
            }
        }
        return greatest
    }

    /// 对照 `MeasureAtDisplacement`：`vpos` 刚好落在小节底时算下一小节。
    static func measureAtDisplacement(_ vPosition: Double, bottoms: [Double]) -> Int {
        var index = 1
        while index < bottoms.count {
            if vPosition < bottoms[index] { break }
            index += 1
        }
        return index - 1
    }

    static let defaultSelectAllBottoms: [Double] = (0...1000).map { Double($0) * 192 }

    /// `measures` 的 start / length 是拍，换成 vpos 小节底。没有变拍就按 192。
    static func measureBottoms(
        measures: [(start: Double, length: Double)],
        count: Int = 1001
    ) -> [Double] {
        var bottoms = (0..<count).map { Double($0) * 192 }
        guard !measures.isEmpty else { return bottoms }
        let ordered = measures.sorted { $0.start < $1.start }
        for (index, measure) in ordered.enumerated() where index < count {
            bottoms[index] = measure.start * 48
        }
        let last = ordered[min(ordered.count, count) - 1]
        let upperIndex = min(ordered.count, count - 1)
        bottoms[upperIndex] = (last.start + last.length) * 48
        if upperIndex + 1 < count {
            for index in (upperIndex + 1)..<count {
                bottoms[index] = bottoms[index - 1] + 192
            }
        }
        return bottoms
    }

    /// `MeasureBottom(m) + MeasureLength(m)`，也就是该小节上沿。
    static func selectAllTimeLength(greatestVPosition: Double, bottoms: [Double]) -> Double {
        let resolved = bottoms.isEmpty ? defaultSelectAllBottoms : bottoms
        let measure = measureAtDisplacement(greatestVPosition, bottoms: resolved)
        let bottom = (0..<resolved.count).contains(measure) ? resolved[measure] : Double(measure) * 192
        let next = measure + 1
        if (0..<resolved.count).contains(next) {
            return resolved[next]
        }
        return bottom + 192
    }

    /// 原文只写 `vSelStart` / `vSelLength`，不赋 half，也不走 `ValidateSelection`。
    static func selectAllTimeSelection(
        greatestVPosition: Double,
        currentHalf: Double,
        bottoms: [Double]
    ) -> TimeSelection {
        TimeSelection(
            start: 0,
            length: selectAllTimeLength(greatestVPosition: greatestVPosition, bottoms: bottoms),
            half: currentHalf
        )
    }

    /// `Selected = nEnabled(ColumnIndex)`。头音（下标 0）不进调用列表。
    static func selectAllIncludesNote(columnEnabled: Bool) -> Bool {
        columnEnabled
    }

    /// 对照 `Column.isNoteCol`。小节槽和间隔列不是音符列。
    static func isNoteColumn(legacyIndex: Int) -> Bool {
        switch legacyIndex {
        case 0, 4, 13, 22, 26: return false
        default: return true
        }
    }

    /// 对照 `isEnabledAfterAll = isVisible And isNoteCol And (Width <> 0)`。
    static func isEnabledAfterAll(isVisible: Bool, isNoteCol: Bool, width: Int) -> Bool {
        isVisible && isNoteCol && width != 0
    }

    static func contains(
        vPosition: Double,
        length: Double = 0,
        selection: TimeSelection,
        ntInput: Bool
    ) -> Bool {
        guard selection.length != 0 else { return false }
        if ntInput {
            return vPosition < selection.upper && vPosition + length >= selection.lower
        }
        return vPosition >= selection.lower && vPosition < selection.upper
    }

    static let convertBlockedMessage = "The selected area can't have notes anywhere but at the start."
    static let write1296Notice = "1296 BPM/STOP labels are stored, but the writer still uses the current core limits."

    static func write1296Notice(bpm1296: Bool, stop1296: Bool) -> String? {
        (bpm1296 || stop1296) ? write1296Notice : nil
    }

    private static func sign(_ value: Double) -> Int {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }
}

enum LegacyChartGrid {
    static func stepBeats(divisions: Int) -> Double {
        4.0 / Double(max(1, divisions))
    }

    static func positions(measureStart: Double, measureLength: Double, divisions: Int) -> [Double] {
        let step = stepBeats(divisions: divisions)
        var result: [Double] = []
        var slot = 0
        var current = measureStart
        let upper = measureStart + measureLength
        while current < upper - 0.000_000_1 {
            result.append(current)
            slot += 1
            current = measureStart + Double(slot) * step
        }
        return result
    }
}
