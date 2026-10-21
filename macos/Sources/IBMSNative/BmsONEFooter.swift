import CoreGraphics
import Foundation

/// 对照 `SequenceView` 底栏：`FooterHeight` / `SoundChannelFooter` / `paintEventPlayingFooter`。
/// 只改打开的 BMSON 的画面，不另开窗。
enum BmsONEFooter {
    static let settingsKey = "SequenceView/FooterHeight"
    static let gripWidth = Int(BmsONESequenceLayout.footerGripWidth)
    static let minHeight = Int(BmsONESequenceLayout.minFooterHeight)
    static let maxHeight = Int(BmsONESequenceLayout.maxFooterHeight)
    static let defaultHeight = minHeight
    static let fontSize = 12
    static let verticalSingleWidth = 40
    static let verticalWrapHeight = 100
    static let minTextSide = 4
    static let areaColor: UInt32 = 0x666666
    static let textColor: UInt32 = 0x000000
    static let prefixMark = "..."

    enum TextMode: Equatable, Hashable {
        case horizontal
        case verticalWrap
        case verticalSingle
    }

    enum Kind: Equatable {
        case corner
        case master
        case playing(label: String, imageName: String)
        case channel(index: Int, name: String)
    }

    struct Cell: Equatable {
        var kind: Kind
        var frame: CGRect
    }

    struct Selection: Equatable {
        var current: Int
        var selected: Set<Int>
    }

    enum Hit: Equatable {
        case grip
        case select(Int)
        case toggle(Int)
        case preview(Int)
        case none
    }

    static func clampHeight(_ height: Int) -> Int {
        min(maxHeight, max(minHeight, height))
    }

    /// `SetFooterHeight`：夹到 `60…180`。
    static func load(from defaults: UserDefaults = .standard) -> Int {
        if defaults.object(forKey: settingsKey) == nil {
            return defaultHeight
        }
        return clampHeight(defaults.integer(forKey: settingsKey))
    }

    static func save(_ height: Int, to defaults: UserDefaults = .standard) {
        defaults.set(clampHeight(height), forKey: settingsKey)
    }

    /// 窗口坐标 Y 向上。往上拖加高，往下拖缩短。
    static func heightAfterWindowDrag(
        startHeight: Int,
        startWindowY: CGFloat,
        currentWindowY: CGFloat
    ) -> Int {
        let delta = startWindowY - currentWindowY
        return clampHeight(startHeight + Int(delta.rounded()))
    }

    /// `internalWidth < 40` 竖排单行；`height > 100` 竖排换行；否则横排。
    static func textMode(internalWidth: Int, height: Int) -> TextMode {
        if internalWidth < verticalSingleWidth {
            return .verticalSingle
        }
        if height > verticalWrapHeight {
            return .verticalWrap
        }
        return .horizontal
    }

    /// 横排 `QMargins(2, 8, 2, 2)`；竖排 `QMargins(6, 2, 8, 2)`。
    static func textRect(internalWidth: Int, height: Int, mode: TextMode) -> CGRect {
        let box = CGRect(x: 0, y: 0, width: CGFloat(internalWidth), height: CGFloat(height))
        switch mode {
        case .horizontal:
            return box.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: 8).intersection(
                CGRect(x: 2, y: 8, width: CGFloat(internalWidth) - 4, height: CGFloat(height) - 10)
            )
        case .verticalSingle, .verticalWrap:
            return CGRect(
                x: 6,
                y: 2,
                width: CGFloat(height) - 14,
                height: CGFloat(internalWidth) - 4
            )
        }
    }

    static func canDrawText(in rect: CGRect) -> Bool {
        rect.width >= CGFloat(minTextSide) && rect.height >= CGFloat(minTextSide)
    }

    /// `QFileInfo(fileName).baseName()`：去掉最后一段扩展名。
    static func displayName(_ fileName: String) -> String {
        let last = (fileName as NSString).lastPathComponent
        if last.isEmpty { return "" }
        let stem = (last as NSString).deletingPathExtension
        return stem
    }

    /// 对照 `SoundChannelFooter::paintEvent` 的截断。长度按 UTF-16。
    static func displayedName(
        name: String,
        textRect: CGRect,
        measure: (String) -> CGSize
    ) -> String? {
        if !canDrawText(in: textRect) { return nil }
        var remaining = name
        var prefix = prefixMark
        var prefixed = false
        func bounds(for text: String) -> CGRect {
            let size = measure(text)
            return CGRect(x: textRect.minX, y: textRect.minY, width: size.width, height: size.height)
        }
        var box = bounds(for: remaining)
        while utf16Count(remaining) > 1 && !textRect.contains(box) {
            if !prefixed && utf16Count(remaining) > 3 {
                prefix = utf16Prefix(remaining, count: 3) + prefixMark
                remaining = utf16Drop(remaining, count: 3)
            }
            remaining = utf16Drop(remaining, count: 1)
            box = bounds(for: prefix + remaining)
            prefixed = true
        }
        if remaining.isEmpty { return nil }
        return prefixed ? prefix + remaining : remaining
    }

    /// 普通点：不在已选里就清空，再选中并改当前。Command 只切换已选，不改当前。
    static func applyClick(current: Int, selected: Set<Int>, clicked: Int, toggle: Bool) -> Selection {
        if toggle {
            var next = selected
            if next.contains(clicked) {
                next.remove(clicked)
            } else {
                next.insert(clicked)
            }
            return Selection(current: current, selected: next)
        }
        var next = selected
        if !next.contains(clicked) {
            next = []
        }
        next.insert(clicked)
        return Selection(current: clicked, selected: next)
    }

    static func hit(
        point: CGPoint,
        cells: [Cell],
        offsetX: CGFloat,
        command: Bool,
        doubleClick: Bool,
        middle: Bool
    ) -> Hit {
        if point.y >= 0 && point.y < CGFloat(gripWidth) {
            return .grip
        }
        guard let index = hitChannel(x: point.x, cells: cells, offsetX: offsetX) else {
            return .none
        }
        if middle || doubleClick {
            return .preview(index)
        }
        return command ? .toggle(index) : .select(index)
    }

    static func hitChannel(x: CGFloat, cells: [Cell], offsetX: CGFloat) -> Int? {
        let contentX = x + offsetX
        for cell in cells {
            guard contentX >= cell.frame.minX && contentX < cell.frame.maxX else { continue }
            if case .channel(let index, _) = cell.kind {
                return index
            }
        }
        return nil
    }

    static func hitsPlaying(x: CGFloat, cells: [Cell], offsetX: CGFloat) -> Bool {
        let contentX = x + offsetX
        return cells.contains { cell in
            guard contentX >= cell.frame.minX && contentX < cell.frame.maxX else { return false }
            if case .playing = cell.kind { return true }
            return false
        }
    }

    static func channelCells(
        names: [String],
        frames: [String: CGRect],
        visible: [Int],
        height: CGFloat
    ) -> [Cell] {
        visible.compactMap { index in
            let channel = BmsonSoundLane.displayChannel(index: index)
            guard let frame = frames[channel], frame.width > 0 else { return nil }
            let raw = names.indices.contains(index) ? names[index] : ""
            return Cell(
                kind: .channel(index: index, name: displayName(raw)),
                frame: CGRect(x: frame.minX, y: 0, width: frame.width, height: height)
            )
        }
    }

    static func playingLabelFrame(left: CGFloat, width: CGFloat, imageName: String) -> CGRect {
        let labelHeight: CGFloat = imageName.isEmpty ? 24 : 48
        return CGRect(x: left, y: CGFloat(gripWidth), width: width, height: labelHeight)
    }

    /// Beat 7-key 默认刮盘在左：`scratch` / `wkey` / `bkey`。
    static var beat7kImageNames: [String] {
        ["scratch", "wkey", "bkey", "wkey", "bkey", "wkey", "bkey", "wkey"]
    }

    static func playingCells(playingPane: CGRect, height: CGFloat) -> [Cell] {
        let frames = BmsONEPlayingLaneLayout.laneFrames(in: playingPane)
        let names = beat7kImageNames
        return zip(BmsONEPlayingLaneLayout.beat7kLaneXs, frames).enumerated().map { item in
            let image = item.offset < names.count ? names[item.offset] : ""
            return Cell(
                kind: .playing(label: String(item.element.0), imageName: image),
                frame: CGRect(
                    x: item.element.1.minX,
                    y: 0,
                    width: item.element.1.width,
                    height: height
                )
            )
        }
    }

    static func entityFrame(x: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: height)
    }

    private static func utf16Count(_ text: String) -> Int {
        text.utf16.count
    }

    private static func utf16Prefix(_ text: String, count: Int) -> String {
        let units = Array(text.utf16)
        let length = min(max(0, count), units.count)
        return String(utf16CodeUnits: Array(units.prefix(length)), count: length)
    }

    private static func utf16Drop(_ text: String, count: Int) -> String {
        let units = Array(text.utf16)
        if count >= units.count { return "" }
        let rest = Array(units.dropFirst(max(0, count)))
        return String(utf16CodeUnits: rest, count: rest.count)
    }
}
