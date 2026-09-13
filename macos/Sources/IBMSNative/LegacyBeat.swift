import Foundation

/// 对照 `MainWindow.vb` `ApplyBeat` / `BBeatApply` / `BBeatApplyV` 和 `Utilities.GetDenominator`。
enum LegacyBeat {
    enum Mode: Int, CaseIterable {
        case preserve = 0
        case measure = 1
        case cut = 2
        case scale = 3
    }

    static let measureCount = 1000
    static let defaultNumerator = 4
    static let defaultDenominator = 4
    static let defaultValueText = "1"
    static let defaultItemSuffix = "1 ( 4 / 4 )"

    static func add3Zeros(_ measure: Int) -> String {
        String(format: "%03d", measure)
    }

    static func defaultItem(measure: Int) -> String {
        "\(add3Zeros(measure)): \(defaultItemSuffix)"
    }

    static func defaultItems() -> [String] {
        (0..<measureCount).map(defaultItem(measure:))
    }

    static func fractionRatio(numerator: Int, denominator: Int) -> Double? {
        guard numerator >= 1, numerator <= 99_999, denominator >= 1, denominator <= 10_000 else {
            return nil
        }
        return Double(numerator) / Double(denominator)
    }

    static func vbDouble(_ value: Double) -> String {
        if value.rounded() == value,
           value >= Double(Int64.min),
           value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(value)
    }

    static func fractionDisplay(numerator: Int, denominator: Int) -> String? {
        guard let ratio = fractionRatio(numerator: numerator, denominator: denominator) else {
            return nil
        }
        return "\(vbDouble(ratio)) ( \(numerator) / \(denominator) ) "
    }

    static func parseValue(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > 0, value < 1000 else {
            return nil
        }
        return value
    }

    /// `Utilities.GetDenominator`：连分数，上限默认 `&H7FFFFFFF`。
    static func denominator(of value: Double, maxDenom: Int64 = 0x7FFF_FFFF) -> Int64 {
        var m00: Int64 = 1
        var m01: Int64 = 0
        var m10: Int64 = 0
        var m11: Int64 = 1
        var x = value
        var ai = Int64(x.rounded(.towardZero))
        while true {
            if ai < 0 { break }
            if ai > 0 {
                if m10 > (maxDenom - m11) / ai { break }
            } else if m11 > maxDenom {
                break
            }
            let next00 = m00 * ai + m01
            m01 = m00
            m00 = next00
            let next10 = m10 * ai + m11
            m11 = m10
            m10 = next10
            if x == Double(ai) { break }
            let frac = x - Double(ai)
            if frac == 0 { break }
            x = 1 / frac
            if x > Double(Int64.max) { break }
            ai = Int64(x.rounded(.towardZero))
        }
        return m10
    }

    static func valueDisplay(_ value: Double) -> String {
        let denom = denominator(of: value)
        if denom > 10_000 {
            return "\(value)"
        }
        let numer = Int64((value * Double(denom)).rounded())
        return "\(vbDouble(value)) ( \(numer) / \(denom) ) "
    }

    static func listItem(measure: Int, display: String) -> String {
        "\(add3Zeros(measure)): \(display)"
    }

    /// 打开谱时按 `ChartIO`：`xRatio` 加 `GetDenominator` 分数。
    static func loadedItem(measure: Int, ratio: Double) -> String {
        listItem(measure: measure, display: valueDisplay(ratio))
    }

    static func ratioDecimal(_ ratio: Double) -> String {
        if ratio.rounded() == ratio {
            return String(Int(ratio))
        }
        return String(ratio)
    }
}
