import Foundation

/// 对照 `Skin.cpp` `CreateDefaultGenericNKeys` / `SetupSkinGeneric6Keys` / `7Keys` 的 `color-scheme`。
/// 只改打开的 BMSON 的 Generic 列底色和音符底色数字，不写 `info`。
enum BmsONEColorScheme {
    static let menuTitle = "Color Scheme"
    static let settingsGroup = "SkinSettings"
    static let propertyKey = "color-scheme"
    static let defaultTitle = "Default"
    static let symmetricTitle = "Symmetric"
    static let djTitle = "DJ"

    struct Choice: Equatable {
        var stored: String
        var title: String
    }

    struct RGB: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    struct LanePaint: Equatable {
        var background: RGB
        var note: RGB
    }

    static let defaultStored = "default"
    static let ncWhite = RGB(red: 210, green: 210, blue: 210)
    static let defaultBackground = RGB(red: 39, green: 39, blue: 39)
    static let pcWhite = RGB(red: 51, green: 51, blue: 51)
    static let pnWhite = RGB(red: 210, green: 210, blue: 210)
    static let pcBlue = RGB(red: 26, green: 26, blue: 60)
    static let pnBlue = RGB(red: 150, green: 150, blue: 240)

    static func skinId(for kind: BmsONEViewModeKind) -> String? {
        switch kind {
        case .generic6: return "default-generic-6keys"
        case .generic7: return "default-generic-7keys"
        default: return nil
        }
    }

    static func settingsKey(for kind: BmsONEViewModeKind) -> String? {
        guard let id = skinId(for: kind) else { return nil }
        return "\(settingsGroup)/\(id)/\(propertyKey)"
    }

    static func choices(for kind: BmsONEViewModeKind) -> [Choice] {
        guard skinId(for: kind) != nil else { return [] }
        return [
            Choice(stored: "default", title: defaultTitle),
            Choice(stored: "symmetric", title: symmetricTitle),
            Choice(stored: "dj", title: djTitle)
        ]
    }

    /// `choices.indexOf`：对不上就用 Default。
    static func parse(_ text: String, kind: BmsONEViewModeKind) -> Choice? {
        let options = choices(for: kind)
        guard !options.isEmpty else { return nil }
        if let match = options.first(where: { $0.stored == text }) {
            return match
        }
        return options.first(where: { $0.stored == defaultStored }) ?? options[0]
    }

    static func load(kind: BmsONEViewModeKind, from defaults: UserDefaults = .standard) -> Choice? {
        guard let key = settingsKey(for: kind) else { return nil }
        let stored = defaults.string(forKey: key) ?? defaultStored
        return parse(stored, kind: kind)
    }

    static func save(_ stored: String, kind: BmsONEViewModeKind, to defaults: UserDefaults = .standard) {
        guard let key = settingsKey(for: kind), parse(stored, kind: kind)?.stored == stored else { return }
        defaults.set(stored, forKey: key)
    }

    static func paints(kind: BmsONEViewModeKind, scheme: Choice) -> [LanePaint] {
        switch kind {
        case .generic6:
            return generic6(scheme.stored)
        case .generic7:
            return generic7(scheme.stored)
        default:
            return []
        }
    }

    /// 车道 `1…N` 对到共用通道。
    static func playPaints(kind: BmsONEViewModeKind, scheme: Choice) -> [String: LanePaint] {
        let map = BmsONEViewMode(kind: kind).laneToChannel
        var result: [String: LanePaint] = [:]
        for (index, paint) in paints(kind: kind, scheme: scheme).enumerated() {
            if let channel = map[Int64(index + 1)] {
                result[channel] = paint
            }
        }
        return result
    }

    private static func generic6(_ stored: String) -> [LanePaint] {
        switch stored {
        case "symmetric":
            let purple = LanePaint(
                background: RGB(red: 51, green: 26, blue: 68),
                note: RGB(red: 180, green: 137, blue: 225)
            )
            let pink = LanePaint(
                background: RGB(red: 68, green: 20, blue: 34),
                note: RGB(red: 240, green: 137, blue: 150)
            )
            let blue = LanePaint(
                background: RGB(red: 17, green: 51, blue: 68),
                note: RGB(red: 123, green: 210, blue: 240)
            )
            return [purple, pink, blue, blue, pink, purple]
        case "dj":
            let white = LanePaint(background: pcWhite, note: pnWhite)
            let blue = LanePaint(background: pcBlue, note: pnBlue)
            return [white, blue, white, white, blue, white]
        default:
            return Array(repeating: LanePaint(background: defaultBackground, note: ncWhite), count: 6)
        }
    }

    private static func generic7(_ stored: String) -> [LanePaint] {
        switch stored {
        case "symmetric":
            let purple = LanePaint(
                background: RGB(red: 51, green: 26, blue: 68),
                note: RGB(red: 180, green: 137, blue: 225)
            )
            let pink = LanePaint(
                background: RGB(red: 68, green: 20, blue: 34),
                note: RGB(red: 240, green: 137, blue: 150)
            )
            let blue = LanePaint(
                background: RGB(red: 17, green: 51, blue: 68),
                note: RGB(red: 123, green: 210, blue: 240)
            )
            let green = LanePaint(
                background: RGB(red: 26, green: 57, blue: 26),
                note: RGB(red: 150, green: 240, blue: 150)
            )
            return [purple, pink, blue, green, blue, pink, purple]
        case "dj":
            let white = LanePaint(background: pcWhite, note: pnWhite)
            let blue = LanePaint(background: pcBlue, note: pnBlue)
            let brown = LanePaint(
                background: RGB(red: 60, green: 39, blue: 20),
                note: RGB(red: 225, green: 180, blue: 137)
            )
            return [white, blue, white, brown, white, blue, white]
        default:
            return Array(repeating: LanePaint(background: defaultBackground, note: ncWhite), count: 7)
        }
    }
}
