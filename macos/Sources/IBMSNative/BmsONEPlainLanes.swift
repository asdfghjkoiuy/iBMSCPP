import Foundation

/// 对照 `Skin.cpp` `CreateDefaultPlain` / `SetupSkinDefaultPlain` 的 `lane-count`。
/// 只改打开的 BMSON 的列数和搬到键盘的空列，不写 `info`。
enum BmsONEPlainLanes {
    static let displayName = "Lane Count"
    static let settingsGroup = "SkinSettings"
    static let skinId = "default-plain"
    static let propertyKey = "lane-count"
    static let defaultCount = 4
    static let minimum = 1
    static let maximum = 99
    /// 共用编辑器只接前 16 个 `x`，和 `BO-VIEW` 同一条。
    static let sharedCap = 16

    static func applies(to kind: BmsONEViewModeKind) -> Bool {
        kind == .plain
    }

    static func settingsKey(for kind: BmsONEViewModeKind) -> String? {
        applies(to: kind) ? "\(settingsGroup)/\(skinId)/\(propertyKey)" : nil
    }

    static func clamp(_ value: Int) -> Int {
        min(maximum, max(minimum, value))
    }

    /// `QString::toInt`：跳过前导空白，读可选正负号和连续数字。
    static func parseInt(_ text: String) -> Int {
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        var sign = 1
        if index < text.endIndex {
            if text[index] == "-" {
                sign = -1
                index = text.index(after: index)
            } else if text[index] == "+" {
                index = text.index(after: index)
            }
        }
        var digits = ""
        while index < text.endIndex, text[index].isNumber {
            digits.append(text[index])
            index = text.index(after: index)
        }
        guard !digits.isEmpty, let value = Int(digits) else { return 0 }
        return sign * value
    }

    static func parse(_ text: String) -> Int {
        clamp(parseInt(text))
    }

    static func load(kind: BmsONEViewModeKind, from defaults: UserDefaults = .standard) -> Int? {
        guard let key = settingsKey(for: kind) else { return nil }
        guard let object = defaults.object(forKey: key) else { return defaultCount }
        if let number = object as? NSNumber {
            return clamp(number.intValue)
        }
        if let text = object as? String {
            return parse(text)
        }
        return clamp(defaults.integer(forKey: key))
    }

    static func save(_ count: Int, kind: BmsONEViewModeKind, to defaults: UserDefaults = .standard) {
        guard let key = settingsKey(for: kind) else { return }
        defaults.set(clamp(count), forKey: key)
    }

    static func displayedCount(_ count: Int) -> Int {
        min(clamp(count), sharedCap)
    }

    static func visibleChannels(count: Int) -> [String] {
        Array(BmsONEViewMode.sharedPlayChannels.prefix(displayedCount(count)))
    }

    static func hiddenPlayChannels(count: Int) -> Set<String> {
        Set(BmsONEViewMode.sharedPlayChannels).subtracting(visibleChannels(count: count))
    }

    static func keyLanes(count: Int) -> [Int64] {
        Array(1...Int64(displayedCount(count)))
    }

    static func keyLanes(mode: BmsONEViewMode, count: Int?) -> [Int64] {
        guard let count, applies(to: mode.kind) else {
            return mode.keyLanes
        }
        return keyLanes(count: count)
    }

    /// `"%1: %2".arg(Lane Count).arg(n)`
    static func menuTitle(count: Int) -> String {
        "\(displayName): \(clamp(count))"
    }

    /// `tr("%1:").arg(Lane Count)`
    static let dialogLabel = "\(displayName):"

    /// Skin 是一条演奏区，不拆 1P / 2P。
    static func showsTwoPlayer(kind: BmsONEViewModeKind) -> Bool? {
        applies(to: kind) ? false : nil
    }
}
