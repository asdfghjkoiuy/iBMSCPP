import Foundation

/// 对照 `Skin.cpp` `CreateDefaultCircularSingle` / `Double` 的 `lane-order`。
/// 只改打开的 BMSON 的列顺序，不写 `info`。
enum BmsONELaneOrder {
    static let menuTitle = "Lane Order"
    static let settingsGroup = "SkinSettings"
    static let propertyKey = "lane-order"
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

    struct LaneCell: Equatable {
        var lane: Int64
        var imageName: String
    }

    static func skinId(for kind: BmsONEViewModeKind) -> String? {
        switch kind {
        case .circularSingle: return "default-circular-single"
        case .circularDouble: return "default-circular-double"
        default: return nil
        }
    }

    static func settingsKey(for kind: BmsONEViewModeKind) -> String? {
        guard let id = skinId(for: kind) else { return nil }
        return "\(settingsGroup)/\(id)/\(propertyKey)"
    }

    static func defaultStored(for kind: BmsONEViewModeKind) -> String {
        switch kind {
        case .circularSingle: return "l"
        case .circularDouble: return "lr"
        default: return ""
        }
    }

    static func choices(for kind: BmsONEViewModeKind) -> [Choice] {
        switch kind {
        case .circularSingle:
            return [
                Choice(stored: "l", title: leftTitle, player1Left: true, player2Left: true),
                Choice(stored: "r", title: rightTitle, player1Left: false, player2Left: false)
            ]
        case .circularDouble:
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

    /// `SetupSkinCircularSingle` / `Double` 从左到右的车道。
    static func cells(kind: BmsONEViewModeKind, order: Choice) -> [LaneCell] {
        switch kind {
        case .circularSingle:
            return circularSide(left: order.player1Left, space: 5, keys: [1, 2, 3, 4])
        case .circularDouble:
            return circularSide(left: order.player1Left, space: nil, keys: [1, 2, 3, 4])
                + [LaneCell(lane: 9, imageName: "c-Space")]
                + circularSide(left: order.player2Left, space: nil, keys: [5, 6, 7, 8])
        default:
            return []
        }
    }

    static func keyLanes(kind: BmsONEViewModeKind, order: Choice) -> [Int64] {
        cells(kind: kind, order: order).map(\.lane)
    }

    static func keyLanes(mode: BmsONEViewMode, order: Choice?) -> [Int64] {
        guard let order, !choices(for: mode.kind).isEmpty else {
            return mode.keyLanes
        }
        return keyLanes(kind: mode.kind, order: order)
    }

    static func channels(kind: BmsONEViewModeKind, order: Choice) -> [String] {
        let map = BmsONEViewMode(kind: kind).laneToChannel
        return keyLanes(kind: kind, order: order).compactMap { map[$0] }
    }

    static func imageName(kind: BmsONEViewModeKind, lane: Int64, order: Choice) -> String {
        cells(kind: kind, order: order).first(where: { $0.lane == lane })?.imageName ?? ""
    }

    /// Circular Skin 是一条演奏区，不拆 1P / 2P。
    static func showsTwoPlayer(kind: BmsONEViewModeKind) -> Bool? {
        choices(for: kind).isEmpty ? nil : false
    }

    private static func circularSide(left: Bool, space: Int64?, keys: [Int64]) -> [LaneCell] {
        let colored: [LaneCell]
        if left {
            colored = [
                LaneCell(lane: keys[3], imageName: "c-L-blue"),
                LaneCell(lane: keys[2], imageName: "c-L-green"),
                LaneCell(lane: keys[1], imageName: "c-L-yellow"),
                LaneCell(lane: keys[0], imageName: "c-L-red")
            ]
        } else {
            colored = [
                LaneCell(lane: keys[0], imageName: "c-R-red"),
                LaneCell(lane: keys[1], imageName: "c-R-yellow"),
                LaneCell(lane: keys[2], imageName: "c-R-green"),
                LaneCell(lane: keys[3], imageName: "c-R-blue")
            ]
        }
        guard let space else { return colored }
        let spaceCell = LaneCell(lane: space, imageName: "c-Space")
        return left ? colored + [spaceCell] : [spaceCell] + colored
    }
}
