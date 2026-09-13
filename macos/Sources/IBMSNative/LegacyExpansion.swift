import CoreGraphics
import Foundation

/// 对照 `ChartIO.vb` `OpenBMS` 收集 `TExpansion`，以及保存时的展开区横幅。
enum LegacyExpansion {
    static let fieldBanner = "*---------------------- EXPANSION FIELD"
    static let boxHeight: CGFloat = 245

    static func displayText(from raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func sameLines(_ left: String, _ right: String) -> Bool {
        lines(of: left) == lines(of: right)
    }

    static func lines(of text: String) -> [String] {
        var normalized = displayText(from: text)
        if normalized.hasSuffix("\n") {
            normalized.removeLast()
        }
        if normalized.isEmpty {
            return []
        }
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
