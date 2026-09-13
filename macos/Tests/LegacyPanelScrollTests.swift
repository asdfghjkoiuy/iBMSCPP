import Foundation

@main
struct LegacyPanelScrollTests {
    static func main() {
        testDefaults()
        testLockDiffsAndFollow()
        testFollowClamps()
        testSplitterResize()
        testOffsetMapping()
        testHomeEnd()
        print("LegacyPanelScrollTests passed")
    }

    private static func testDefaults() {
        require(LegacyPanelScroll.defaultSideWidth == 0, "PMainL / PMainR Designer width is 0")
        require(LegacyPanelScroll.splitterThickness == 5, "SpL / SpR Designer width is 5")
    }

    /// 勾上中锁：记下中与左、中与右的差。中往下滚时左跟着走。
    private static func testLockDiffsAndFollow() {
        let captured = LegacyPanelScroll.diffs(locking: 1, scrolls: [-100, 0, 0])
        require(captured[1] == 0 && captured[0] == 100, "lock mid: diff mid=right-mid, diff left=mid-left")
        let locks = [true, false, false]
        let followed = LegacyPanelScroll.follow(
            source: 1, value: -50, locks: locks, diffs: captured, minimum: -10_000
        )
        require(followed[0] == -150 && followed[1] == nil && followed[2] == nil,
                "mid -50 with left locked: left = -50 - 100")
        require(
            LegacyPanelScroll.follow(
                source: 0, value: -80, locks: [false, true, false], diffs: [0, 0, 0], minimum: -10_000
            )[1] == -80,
            "left scrolls and mid is locked: mid gets left + diff[0]"
        )
    }

    private static func testFollowClamps() {
        require(LegacyPanelScroll.clampScroll(10, minimum: -1000) == 0, "scroll cannot go above 0")
        require(LegacyPanelScroll.clampScroll(-2000, minimum: -1000) == -1000, "scroll stops at Minimum")
        let targets = LegacyPanelScroll.follow(
            source: 0, value: 0, locks: [false, true, false], diffs: [50, 0, 0], minimum: -100
        )
        require(targets[1] == 0, "0 + 50 clamps to 0")
    }

    private static func testSplitterResize() {
        require(LegacyPanelScroll.resizeLeft(current: 0, mouseX: 40, grabX: 0) == 40, "SpL grows left panel")
        require(LegacyPanelScroll.resizeLeft(current: 10, mouseX: 0, grabX: 20) == 0, "SpL does not go negative")
        require(LegacyPanelScroll.resizeRight(current: 80, mouseX: 10, grabX: 0) == 70, "SpR shrinks when dragged right")
        require(LegacyPanelScroll.resizeRight(current: 5, mouseX: 20, grabX: 0) == 0, "SpR does not go negative")
    }

    private static func testOffsetMapping() {
        require(LegacyPanelScroll.winScroll(offsetY: 1000, maxOffset: 1000) == 0, "measure 0 maps to PanelVScroll 0")
        require(LegacyPanelScroll.winScroll(offsetY: 950, maxOffset: 1000) == -50, "later measures go negative")
        require(LegacyPanelScroll.offsetY(winScroll: -50, maxOffset: 1000) == 950, "round trip from PanelVScroll")
    }

    /// `Keys.Home` / `Keys.End`：只改当前块滚动，坐标走已有 `offsetY`。
    private static func testHomeEnd() {
        require(LegacyPanelScroll.homeWinScroll() == 0, "Home is PanelVScroll 0")
        require(LegacyPanelScroll.endWinScroll(minimum: -1000) == -1000, "End is PanelVScroll.Minimum")
        require(LegacyPanelScroll.endWinScroll(minimum: 0) == 0, "empty chart End minimum is 0")
        require(
            LegacyPanelScroll.homeOffsetY(maxOffset: 1000) == 1000
                && LegacyPanelScroll.homeOffsetY(maxOffset: 1000)
                == LegacyPanelScroll.offsetY(winScroll: 0, maxOffset: 1000),
            "Home offset.y is maxOffset"
        )
        require(
            LegacyPanelScroll.endOffsetY(maxOffset: 1000) == 0
                && LegacyPanelScroll.endOffsetY(maxOffset: 1000)
                == LegacyPanelScroll.offsetY(winScroll: -1000, maxOffset: 1000),
            "End offset.y is 0"
        )
        require(LegacyPanelScroll.homeOffsetY(maxOffset: 0) == 0, "empty chart Home offset.y is 0")
        require(LegacyPanelScroll.endOffsetY(maxOffset: 0) == 0, "empty chart End offset.y is 0")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
