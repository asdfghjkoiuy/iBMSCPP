import Foundation

/// 对照 `MainWindow.mnGotoMeasure_Click`。
enum LegacyGotoMeasure {
    static let prompt = "Please enter a measure (0-999)."
    static let title = "Enter Measure"

    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (0...999).contains(value) else { return nil }
        return value
    }

    static func scrollVS(measure: Int, bottoms: [Double] = LegacyClipboard.defaultMeasureBottoms()) -> Double? {
        guard (0...999).contains(measure) else { return nil }
        if measure < bottoms.count {
            return -bottoms[measure]
        }
        return -Double(measure) * 192
    }
}
