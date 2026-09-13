import Foundation

@main
struct LegacyGotoMeasureTests {
    static func main() {
        testParseMeasure()
        testScrollIsNegativeMeasureBottom()
        print("LegacyGotoMeasureTests passed")
    }

    /// `Int32.TryParse`，只要 0–999。
    private static func testParseMeasure() {
        require(LegacyGotoMeasure.parse("0") == 0, "measure 0")
        require(LegacyGotoMeasure.parse("12") == 12, "measure 12")
        require(LegacyGotoMeasure.parse("999") == 999, "measure 999")
        require(LegacyGotoMeasure.parse("-1") == nil, "negative rejected")
        require(LegacyGotoMeasure.parse("1000") == nil, "1000 rejected")
        require(LegacyGotoMeasure.parse("abc") == nil, "text rejected")
        require(LegacyGotoMeasure.parse("") == nil, "empty rejected")
    }

    /// `PanelVScroll = -MeasureBottom(i)`。
    private static func testScrollIsNegativeMeasureBottom() {
        require(LegacyGotoMeasure.scrollVS(measure: 0) == 0, "measure 0 is scroll 0")
        require(LegacyGotoMeasure.scrollVS(measure: 1) == -192, "measure 1 is -192")
        require(LegacyGotoMeasure.scrollVS(measure: 2) == -384, "measure 2 is -384")
        require(LegacyGotoMeasure.scrollVS(measure: 1000) == nil, "out of range")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
