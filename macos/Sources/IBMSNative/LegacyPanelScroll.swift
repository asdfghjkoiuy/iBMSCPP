import Foundation

/// 对照 `MainWindow.vb` `VSValueChanged` / `cVSLock_CheckedChanged` / `SpL` / `SpR`。
/// 面板下标：0 左、1 中、2 右。原版滚动值 ≤ 0。
enum LegacyPanelScroll {
    static let count = 3
    static let splitterThickness = 5
    static let defaultSideWidth = 0

    static let prefLeftSplitter = 0x1000
    static let prefRightSplitter = 0x2000
    static let prefLockLeft = 0x4_000_000
    static let prefLockMiddle = 0x8_000_000
    static let prefLockRight = 0x10_000_000

    static func clampScroll(_ value: Int, minimum: Int) -> Int {
        if value > 0 { return 0 }
        if value < minimum { return minimum }
        return value
    }

    static func clampWidth(_ width: Int) -> Int {
        max(defaultSideWidth, width)
    }

    /// 原生 `offset.y` 在小节 0 最大，原版 `PanelVScroll` 在小节 0 是 0。
    static func winScroll(offsetY: Double, maxOffset: Double) -> Int {
        Int((offsetY - maxOffset).rounded())
    }

    static func offsetY(winScroll: Int, maxOffset: Double) -> Double {
        Double(winScroll) + maxOffset
    }

    /// `Keys.Home`：当前焦点块 `*PanelScroll.Value = 0`。
    static func homeWinScroll() -> Int { 0 }

    /// `Keys.End`：当前焦点块 `Value = *PanelScroll.Minimum`。
    static func endWinScroll(minimum: Int) -> Int { minimum }

    static func homeOffsetY(maxOffset: Double) -> Double {
        offsetY(winScroll: homeWinScroll(), maxOffset: maxOffset)
    }

    static func endOffsetY(maxOffset: Double) -> Double {
        offsetY(winScroll: endWinScroll(minimum: -Int(maxOffset.rounded())), maxOffset: maxOffset)
    }

    /// `SpL`：`PMainL.Width + e.X - tempResize`。
    static func resizeLeft(current: Int, mouseX: Int, grabX: Int) -> Int {
        clampWidth(current + mouseX - grabX)
    }

    /// `SpR`：`PMainR.Width - e.X + tempResize`。
    static func resizeRight(current: Int, mouseX: Int, grabX: Int) -> Int {
        clampWidth(current - mouseX + grabX)
    }

    /// 勾上锁时记下与相邻面板的差。
    static func diffs(locking index: Int, scrolls: [Int]) -> [Int] {
        var next = [0, 0, 0]
        guard count == scrolls.count, (0..<count).contains(index) else { return next }
        next[index] = scrolls[(index + 1) % count] - scrolls[index]
        next[(index + 2) % count] = scrolls[index] - scrolls[(index + 2) % count]
        return next
    }

    /// `VSValueChanged`：若下一块上锁，写 `scroll[i] + diff[i]`；若上一块上锁，写 `scroll[i] - diff[i+2]`。
    static func follow(
        source: Int,
        value: Int,
        locks: [Bool],
        diffs: [Int],
        minimum: Int
    ) -> [Int?] {
        var targets: [Int?] = [nil, nil, nil]
        guard (0..<count).contains(source), locks.count == count, diffs.count == count else { return targets }
        if locks[(source + 1) % count] {
            targets[(source + 1) % count] = clampScroll(value + diffs[source], minimum: minimum)
        }
        if locks[(source + 2) % count] {
            targets[(source + 2) % count] = clampScroll(value - diffs[(source + 2) % count], minimum: minimum)
        }
        return targets
    }
}
