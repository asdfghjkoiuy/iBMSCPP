import Foundation

struct LegacyClipboardNote: Equatable {
    var columnIndex: Int
    var vPosition: Double
    var value: Int
    var length: Double
    var longNote: Bool
    var hidden: Bool
    var landmine: Bool
}

enum LegacyClipboardFormat: Equatable {
    case ibmscBMSE
    case ibmscNT
    case bmseObject
}

struct LegacyClipboardPayload: Equatable {
    var format: LegacyClipboardFormat
    var notes: [LegacyClipboardNote]
}

/// 对照 `MainWindow.CopyNotes` / `AddNotesFromClipboard` / `GetBMSChannelBy`。
enum LegacyClipboard {
    static let bmseHeader = "iBMSC Clipboard Data"
    static let ntHeader = "iBMSC Clipboard Data xNT"
    static let objectHeader = "BMSE ClipBoard Object Data Format"

    private static let columnCount = 1000
    private static let defaultMeasureLength = 192.0
    private static let niSCROLL = 1
    private static let niBPM = 2
    private static let niSTOP = 3
    private static let niA1 = 5
    private static let niA8 = 12
    private static let niD1 = 14
    private static let niD8 = 21
    private static let niBGA = 23
    private static let niLAYER = 24
    private static let niPOOR = 25
    private static let niB = 27
    private static let idflBPM = 5

    private static let playableIdentifiers: [Int: Int] = [
        5: 16, 6: 11, 7: 12, 8: 13, 9: 14, 10: 15, 11: 18, 12: 19,
        14: 21, 15: 22, 16: 23, 17: 24, 18: 25, 19: 28, 20: 29, 21: 26,
        23: 4, 24: 7, 25: 6
    ]

    static func tokenValue(_ token: String) -> Int {
        c36to10(token) * 10000
    }

    static func token(fromValue value: Int) -> String {
        c10to36(value / 10000)
    }

    static func numericValue(_ decimal: String) -> Int {
        Int(((Double(decimal.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) * 10000.0).rounded())
    }

    static func decimal(fromValue value: Int) -> String {
        if value % 10000 == 0 {
            return String(value / 10000)
        }
        return formatNumber(Double(value) / 10000.0)
    }

    /// Channel `03` labels are hexadecimal, not base 36.
    static func hexTokenValue(_ token: String) -> Int {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return (Int(trimmed, radix: 16) ?? 0) * 10000
    }

    /// `#SCROLLxx` 后面的十进制。标签永远三十六进制。
    /// Swift 把 `\r\n` 当成一个换行字符，不能按单独的 `\r` / `\n` 拆。
    static func scrollDecimal(token: String, in text: String) -> String? {
        let needle = "#SCROLL" + token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix(needle) else { continue }
            let rest = line.dropFirst(needle.count)
            guard rest.first?.isWhitespace == true else { continue }
            guard let value = rest.split(whereSeparator: \.isWhitespace).first, !value.isEmpty else { continue }
            return String(value)
        }
        return nil
    }

    static func encode(_ notes: [LegacyClipboardNote], ntInput: Bool) -> String {
        var lines = [ntInput ? ntHeader : bmseHeader]
        guard !notes.isEmpty else { return lines[0] }
        let bottoms = defaultMeasureBottoms()
        var minMeasure = 999
        for note in notes {
            let measure = measureAtDisplacement(note.vPosition, bottoms: bottoms)
            if measure < minMeasure { minMeasure = measure }
        }
        let origin = measureBottom(minMeasure, bottoms: bottoms)
        for note in notes {
            let relative = formatNumber(note.vPosition - origin)
            let value = formatNumber(Double(note.value))
            if ntInput {
                lines.append(
                    "\(note.columnIndex) \(relative) \(value) \(formatNumber(note.length)) \(boolInt(note.hidden)) \(boolInt(note.landmine))"
                )
            } else {
                lines.append(
                    "\(note.columnIndex) \(relative) \(value) \(boolInt(note.longNote)) \(boolInt(note.hidden)) \(boolInt(note.landmine))"
                )
            }
        }
        return lines.joined(separator: "\r\n")
    }

    /// `BMSE ClipBoard Object Data Format`：3 位通道 + 1 位属性 + 7 位位置 + 值。
    /// 对照 `AddNotesFromClipboard` 的 `Mid` 切法。位置四舍五入成整数，因为原版只读 7 个字符。
    static func encodeObject(_ notes: [LegacyClipboardNote]) -> String {
        var lines = [objectHeader]
        for note in notes {
            lines.append(encodeObjectLine(note))
        }
        return lines.joined(separator: "\r\n")
    }

    static func decode(_ text: String) -> LegacyClipboardPayload? {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }
        guard let header = lines.first else { return nil }
        switch header {
        case bmseHeader:
            return LegacyClipboardPayload(format: .ibmscBMSE, notes: decodeIBMSCLines(lines.dropFirst(), ntInput: false))
        case ntHeader:
            return LegacyClipboardPayload(format: .ibmscNT, notes: decodeIBMSCLines(lines.dropFirst(), ntInput: true))
        case objectHeader:
            return LegacyClipboardPayload(format: .bmseObject, notes: lines.dropFirst().compactMap(decodeObjectLine))
        default:
            return nil
        }
    }

    static func placed(_ notes: [LegacyClipboardNote], baseVPosition: Double) -> [LegacyClipboardNote] {
        notes.map { note in
            var placed = note
            placed.vPosition = note.vPosition + baseVPosition
            return placed
        }
    }

    static func defaultMeasureBottoms(count: Int = columnCount) -> [Double] {
        (0..<count).map { Double($0) * defaultMeasureLength }
    }

    static func measureAtDisplacement(_ vPosition: Double, bottoms: [Double] = defaultMeasureBottoms()) -> Int {
        var index = 1
        while index < bottoms.count {
            if vPosition < bottoms[index] { break }
            index += 1
        }
        return index - 1
    }

    static func pasteBaseVPosition(scrollVS: Double, bottoms: [Double] = defaultMeasureBottoms()) -> Double {
        measureBottom(measureAtDisplacement(-scrollVS, bottoms: bottoms) + 1, bottoms: bottoms)
    }

    static func writeChannel(_ note: LegacyClipboardNote) -> String? {
        if note.columnIndex == niSCROLL { return "SC" }
        if note.columnIndex >= niB {
            return "B\(note.columnIndex - niB + 1)"
        }
        var identifier = columnIdentifier(note.columnIndex)
        if note.columnIndex == niBPM {
            let bpm = Double(note.value) / 10000.0
            if bpm != bpm.rounded(.towardZero) || note.value >= 2_560_000 || note.value < 0 {
                identifier += idflBPM
            }
        }
        if (niA1...niA8).contains(note.columnIndex) {
            if note.longNote { return hexChannel(identifier + 0x50 - 10) }
            if note.hidden { return hexChannel(identifier + 0x30 - 10) }
            if note.landmine { return hexChannel(identifier + 0xD0 - 10) }
        }
        if (niD1...niD8).contains(note.columnIndex) {
            if note.longNote { return hexChannel(identifier + 0x60 - 20) }
            if note.hidden { return hexChannel(identifier + 0x40 - 20) }
            if note.landmine { return hexChannel(identifier + 0xE0 - 20) }
        }
        return add2Zeros(identifier)
    }

    static func location(vPosition: Double, bottoms: [Double] = defaultMeasureBottoms()) -> (measure: Int, numerator: Int64, denominator: Int64) {
        let measure = measureAtDisplacement(vPosition, bottoms: bottoms)
        let relative = vPosition - measureBottom(measure, bottoms: bottoms)
        let ticks = Int64((relative * 192.0 / defaultMeasureLength).rounded())
        let divisor = gcd(abs(ticks), 192)
        if ticks == 0 { return (measure, 0, 1) }
        return (measure, ticks / divisor, 192 / divisor)
    }

    static func vPosition(
        measure: Int,
        fractionNumerator: Int64,
        fractionDenominator: Int64,
        bottoms: [Double] = defaultMeasureBottoms()
    ) -> Double {
        guard fractionDenominator != 0 else { return measureBottom(measure, bottoms: bottoms) }
        return measureBottom(measure, bottoms: bottoms)
            + Double(fractionNumerator) / Double(fractionDenominator) * defaultMeasureLength
    }

    static func columnIndex(forChannel channel: String) -> Int {
        let upper = channel.uppercased()
        if upper == "01" { return niB }
        if upper.first == "B", let lane = Int(upper.dropFirst()), lane >= 1 {
            return niB + lane - 1
        }
        switch upper {
        case "03", "08": return niBPM
        case "09": return niSTOP
        case "SC": return niSCROLL
        case "04": return niBGA
        case "07": return niLAYER
        case "06": return niPOOR
        case "16", "36", "56", "76", "D6": return niA1
        case "11", "31", "51", "71", "D1": return 6
        case "12", "32", "52", "72", "D2": return 7
        case "13", "33", "53", "73", "D3": return 8
        case "14", "34", "54", "74", "D4": return 9
        case "15", "35", "55", "75", "D5": return 10
        case "18", "38", "58", "78", "D8": return 11
        case "19", "39", "59", "79", "D9": return 12
        case "21", "41", "61", "81", "E1": return niD1
        case "22", "42", "62", "82", "E2": return 15
        case "23", "43", "63", "83", "E3": return 16
        case "24", "44", "64", "84", "E4": return 17
        case "25", "45", "65", "85", "E5": return 18
        case "28", "48", "68", "88", "E8": return 19
        case "29", "49", "69", "89", "E9": return 20
        case "26", "46", "66", "86", "E6": return 21
        default: return 0
        }
    }

    static func flags(forChannel channel: String) -> (longNote: Bool, hidden: Bool, landmine: Bool) {
        guard let family = channel.uppercased().first else { return (false, false, false) }
        switch family {
        case "5", "6": return (true, false, false)
        case "3", "4": return (false, true, false)
        case "D", "E": return (false, false, true)
        default: return (false, false, false)
        }
    }

    static func convertBMSE2NT(_ notes: [LegacyClipboardNote], lnobj: Int = 0) -> [LegacyClipboardNote] {
        LegacyNTConvert.convertBMSE2NT(notes, lnobj: lnobj)
    }

    static func convertNT2BMSE(_ notes: [LegacyClipboardNote]) -> [LegacyClipboardNote] {
        LegacyNTConvert.convertNT2BMSE(notes)
    }

    static func note(
        channel: String,
        measure: Int,
        fractionNumerator: Int64,
        fractionDenominator: Int64,
        token: String,
        length: Double = 0
    ) -> LegacyClipboardNote {
        let flags = flags(forChannel: channel)
        return LegacyClipboardNote(
            columnIndex: columnIndex(forChannel: channel),
            vPosition: vPosition(
                measure: measure,
                fractionNumerator: fractionNumerator,
                fractionDenominator: fractionDenominator
            ),
            value: tokenValue(token),
            length: length,
            longNote: flags.longNote,
            hidden: flags.hidden,
            landmine: flags.landmine
        )
    }

    private static func decodeIBMSCLines<S: Sequence>(_ lines: S, ntInput: Bool) -> [LegacyClipboardNote]
        where S.Element == String
    {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6,
                  let column = vbValInt(parts[0]),
                  let vPosition = vbVal(parts[1]),
                  let value = vbValInt(parts[2]) else {
                return nil
            }
            if ntInput {
                guard let length = vbVal(parts[3]) else { return nil }
                return LegacyClipboardNote(
                    columnIndex: column,
                    vPosition: vPosition,
                    value: value,
                    length: length,
                    longNote: false,
                    hidden: vbBool(parts[4]),
                    landmine: vbBool(parts[5])
                )
            }
            return LegacyClipboardNote(
                columnIndex: column,
                vPosition: vPosition,
                value: value,
                length: 0,
                longNote: vbBool(parts[3]),
                hidden: vbBool(parts[4]),
                landmine: vbBool(parts[5])
            )
        }
    }

    private static func encodeObjectLine(_ note: LegacyClipboardNote) -> String {
        let ident = objectChannelIdent(note.columnIndex)
        let attribute: String
        if note.longNote {
            attribute = "2"
        } else if note.hidden {
            attribute = "1"
        } else {
            attribute = "0"
        }
        let ticks = Int(note.vPosition.rounded())
        let position = String(format: "%07d", min(9_999_999, max(0, ticks)))
        return ident + attribute + position + formatNumber(Double(note.value) / 10000.0)
    }

    private static func objectChannelIdent(_ column: Int) -> String {
        if column >= niB {
            return String(format: "%03d", 101 + (column - niB))
        }
        let identifier = columnIdentifier(column)
        if identifier > 0 {
            return String(format: "%03d", identifier)
        }
        return "101"
    }

    private static func decodeObjectLine(_ line: String) -> LegacyClipboardNote? {
        guard line.count > 11 else { return nil }
        let ident = mid(line, start: 1, length: 3)
        let attribute = mid(line, start: 4, length: 1)
        let position = vbVal(mid(line, start: 5, length: 7)) ?? 0
        let value = Int((vbVal(mid(line, start: 12)) ?? 0) * 10000)
        let column = bmseChannelToColumnIndex(ident)
        guard column > 0 else { return nil }
        return LegacyClipboardNote(
            columnIndex: column,
            vPosition: position,
            value: value,
            length: 0,
            longNote: attribute == "2",
            hidden: attribute == "1",
            landmine: false
        )
    }

    private static func bmseChannelToColumnIndex(_ ident: String) -> Int {
        let value = vbVal(ident) ?? 0
        if value > 100 {
            return niB + Int(value) - 101
        }
        if value > 0 && value < 100 {
            return columnIndex(forChannel: mid(ident, start: 2, length: 2))
        }
        return niB
    }

    private static func measureBottom(_ measure: Int, bottoms: [Double]) -> Double {
        guard measure >= 0, measure < bottoms.count else { return Double(max(0, measure)) * defaultMeasureLength }
        return bottoms[measure]
    }

    private static func columnIdentifier(_ column: Int) -> Int {
        if column == niBPM { return 3 }
        if column == niSTOP { return 9 }
        return playableIdentifiers[column] ?? 0
    }

    private static func hexChannel(_ value: Int) -> String {
        String(value, radix: 16, uppercase: true)
    }

    private static func add2Zeros(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private static func boolInt(_ value: Bool) -> String {
        value ? "-1" : "0"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.isFinite && value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    private static func vbBool(_ text: String) -> Bool {
        (vbVal(text) ?? 0) != 0
    }

    private static func vbValInt(_ text: String) -> Int? {
        guard let value = vbVal(text) else { return nil }
        return Int(value)
    }

    /// VB `Val`：读到第一个非数字字符为止。
    private static func vbVal(_ text: String) -> Double? {
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
        return Double(String(String.UnicodeScalarView(scalars[index..<end])))
    }

    private static func mid(_ text: String, start: Int, length: Int? = nil) -> String {
        let characters = Array(text)
        let begin = max(0, start - 1)
        if begin >= characters.count { return "" }
        if let length {
            let end = min(characters.count, begin + max(0, length))
            return String(characters[begin..<end])
        }
        return String(characters[begin...])
    }

    private static func c36to10(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let padded = String(("00" + trimmed).suffix(2))
        let characters = Array(padded)
        return digit(characters[0]) * 36 + digit(characters[1])
    }

    private static func c10to36(_ value: Int) -> String {
        let clamped = min(1295, max(1, value))
        let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String([digits[clamped / 36], digits[clamped % 36]])
    }

    private static func digit(_ character: Character) -> Int {
        guard let value = character.asciiValue else { return 0 }
        if value >= 48 && value <= 57 { return Int(value - 48) }
        if value >= 65 && value <= 90 { return Int(value - 55) }
        return 0
    }

    private static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return a == 0 ? 1 : a
    }
}
