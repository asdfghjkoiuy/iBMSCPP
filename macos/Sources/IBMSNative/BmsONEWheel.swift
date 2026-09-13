import Foundation

/// 对照 `Skin.cpp` `CreateDefaultKeyboardSingle` / `K24kDouble` 的 `wheel`。
/// 只改搬到键盘的空列顺序，不改前 16 列显示，不写 `info`。
enum BmsONEWheel {
    static let menuTitle = "Wheel"
    static let settingsGroup = "SkinSettings"
    static let propertyKey = "wheel"
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
        case .keyboard24Single: return "default-keyboard-24k-single"
        case .keyboard36: return "default-keyboard-36k-single"
        case .keyboard48: return "default-keyboard-48k-single"
        case .keyboard60: return "default-keyboard-60k-single"
        case .keyboard24Double: return "default-keyboard-24k-double"
        default: return nil
        }
    }

    static func settingsKey(for kind: BmsONEViewModeKind) -> String? {
        guard let id = skinId(for: kind) else { return nil }
        return "\(settingsGroup)/\(id)/\(propertyKey)"
    }

    static func defaultStored(for kind: BmsONEViewModeKind) -> String {
        switch kind {
        case .keyboard24Single, .keyboard36, .keyboard48, .keyboard60:
            return "l"
        case .keyboard24Double:
            return "lr"
        default:
            return ""
        }
    }

    static func keyCount(for kind: BmsONEViewModeKind) -> Int? {
        switch kind {
        case .keyboard24Single: return 24
        case .keyboard36: return 36
        case .keyboard48: return 48
        case .keyboard60: return 60
        default: return nil
        }
    }

    static func choices(for kind: BmsONEViewModeKind) -> [Choice] {
        switch kind {
        case .keyboard24Single, .keyboard36, .keyboard48, .keyboard60:
            return [
                Choice(stored: "l", title: leftTitle, player1Left: true, player2Left: true),
                Choice(stored: "r", title: rightTitle, player1Left: false, player2Left: false)
            ]
        case .keyboard24Double:
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

    /// `SetupSkinKeyboardSingle` / `K24kDouble` 从左到右的车道，含画不到的轮盘。
    static func keyLanes(kind: BmsONEViewModeKind, wheel: Choice) -> [Int64] {
        if let keys = keyCount(for: kind) {
            let board = (1...Int64(keys)).map { $0 }
            let wheels = [Int64(keys + 1), Int64(keys + 2)]
            return wheel.player1Left ? wheels + board : board + wheels
        }
        guard kind == .keyboard24Double else { return [] }
        let firstKeys = Array(1...Int64(24))
        let firstWheels: [Int64] = [25, 26]
        let secondKeys = Array(27...Int64(50))
        let secondWheels: [Int64] = [51, 52]
        let first = wheel.player1Left ? firstWheels + firstKeys : firstKeys + firstWheels
        let second = wheel.player2Left ? secondWheels + secondKeys : secondKeys + secondWheels
        return first + second
    }

    static func keyLanes(mode: BmsONEViewMode, wheel: Choice?) -> [Int64] {
        guard let wheel, !choices(for: mode.kind).isEmpty else {
            return mode.keyLanes
        }
        return keyLanes(kind: mode.kind, wheel: wheel)
    }
}
