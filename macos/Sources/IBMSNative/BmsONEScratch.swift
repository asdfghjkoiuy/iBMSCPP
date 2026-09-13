import Foundation

/// 对照 `Skin.cpp` `CreateDefault5k` / `7k` / `10k` / `14k` 的 `scratch`。
/// 只改打开的 BMSON 的列顺序，不写 `info`。
enum BmsONEScratch {
    static let menuTitle = "Scratch"
    static let settingsGroup = "SkinSettings"
    static let propertyKey = "scratch"
    static let leftTitle = "Left"
    static let rightTitle = "Right"
    static let leftLeftTitle = "Left/Left"
    static let leftRightTitle = "Left/Right"
    static let rightLeftTitle = "Right/Left"
    static let rightRightTitle = "Right/Right"

    struct Choice: Equatable {
        var stored: String
        var title: String
        var player1Left: Bool
        var player2Left: Bool
    }

    static func skinId(for kind: BmsONEViewModeKind) -> String? {
        switch kind {
        case .beat5k: return "default-beat-5k"
        case .beat7k: return "default-beat-7k"
        case .beat10k: return "default-beat-10k"
        case .beat14k: return "default-beat-14k"
        default: return nil
        }
    }

    static func settingsKey(for kind: BmsONEViewModeKind) -> String? {
        guard let id = skinId(for: kind) else { return nil }
        return "\(settingsGroup)/\(id)/\(propertyKey)"
    }

    static func defaultStored(for kind: BmsONEViewModeKind) -> String {
        switch kind {
        case .beat5k: return "r"
        case .beat7k: return "l"
        case .beat10k: return "rr"
        case .beat14k: return "lr"
        default: return ""
        }
    }

    static func choices(for kind: BmsONEViewModeKind) -> [Choice] {
        switch kind {
        case .beat5k, .beat7k:
            return [
                Choice(stored: "l", title: leftTitle, player1Left: true, player2Left: true),
                Choice(stored: "r", title: rightTitle, player1Left: false, player2Left: false)
            ]
        case .beat10k, .beat14k:
            return [
                Choice(stored: "ll", title: leftLeftTitle, player1Left: true, player2Left: true),
                Choice(stored: "lr", title: leftRightTitle, player1Left: true, player2Left: false),
                Choice(stored: "rl", title: rightLeftTitle, player1Left: false, player2Left: true),
                Choice(stored: "rr", title: rightRightTitle, player1Left: false, player2Left: false)
            ]
        default:
            return []
        }
    }

    /// `choices.indexOf`：对不上就用该模式默认值。
    static func parse(_ text: String, kind: BmsONEViewModeKind) -> Choice? {
        let options = choices(for: kind)
        guard !options.isEmpty else { return nil }
        if let match = options.first(where: { $0.stored == text }) {
            return match
        }
        return options.first(where: { $0.stored == defaultStored(for: kind) }) ?? options[0]
    }

    static func load(kind: BmsONEViewModeKind, from defaults: UserDefaults = .standard) -> Choice? {
        guard let key = settingsKey(for: kind) else { return nil }
        let stored = defaults.string(forKey: key) ?? defaultStored(for: kind)
        return parse(stored, kind: kind)
    }

    static func save(_ stored: String, kind: BmsONEViewModeKind, to defaults: UserDefaults = .standard) {
        guard let key = settingsKey(for: kind), parse(stored, kind: kind)?.stored == stored else { return }
        defaults.set(stored, forKey: key)
    }

    static func player1Keys(kind: BmsONEViewModeKind) -> [String] {
        switch kind {
        case .beat5k, .beat10k:
            return ["11", "12", "13", "14", "15"]
        case .beat7k, .beat14k:
            return ["11", "12", "13", "14", "15", "18", "19"]
        default:
            return []
        }
    }

    static func player2Keys(kind: BmsONEViewModeKind) -> [String] {
        switch kind {
        case .beat10k:
            return ["21", "22", "23", "24", "25"]
        case .beat14k:
            return ["21", "22", "23", "24", "25", "28", "29"]
        default:
            return []
        }
    }

    static func arranged(keys: [String], scratch: String, left: Bool) -> [String] {
        left ? [scratch] + keys : keys + [scratch]
    }

    static func player1Channels(kind: BmsONEViewModeKind, scratch: Choice) -> [String] {
        let keys = player1Keys(kind: kind)
        guard !keys.isEmpty else { return [] }
        return arranged(keys: keys, scratch: "16", left: scratch.player1Left)
    }

    static func player2Channels(kind: BmsONEViewModeKind, scratch: Choice) -> [String] {
        let keys = player2Keys(kind: kind)
        guard !keys.isEmpty else { return [] }
        return arranged(keys: keys, scratch: "26", left: scratch.player2Left)
    }

    /// 搬到键盘时从左到右找空列，对照 Skin 车道顺序。
    static func keyLanes(kind: BmsONEViewModeKind, scratch: Choice) -> [Int64] {
        let firstKeys: [Int64]
        switch kind {
        case .beat5k, .beat10k:
            firstKeys = [1, 2, 3, 4, 5]
        case .beat7k, .beat14k:
            firstKeys = [1, 2, 3, 4, 5, 6, 7]
        default:
            return []
        }
        var lanes = arrangedLanes(keys: firstKeys, scratch: 8, left: scratch.player1Left)
        let secondKeys: [Int64]
        switch kind {
        case .beat10k:
            secondKeys = [9, 10, 11, 12, 13]
        case .beat14k:
            secondKeys = [9, 10, 11, 12, 13, 14, 15]
        default:
            return lanes
        }
        lanes += arrangedLanes(keys: secondKeys, scratch: 16, left: scratch.player2Left)
        return lanes
    }

    static func keyLanes(mode: BmsONEViewMode, scratch: Choice?) -> [Int64] {
        guard let scratch, !choices(for: mode.kind).isEmpty else {
            return mode.keyLanes
        }
        return keyLanes(kind: mode.kind, scratch: scratch)
    }

    private static func arrangedLanes(keys: [Int64], scratch: Int64, left: Bool) -> [Int64] {
        left ? [scratch] + keys : keys + [scratch]
    }
}
