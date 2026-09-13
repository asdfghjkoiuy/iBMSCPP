import Foundation

@main
struct LegacyPanelGuidesTests {
    static func main() {
        testMeasureCaption()
        testBackgroundBrightness()
        print("LegacyPanelGuidesTests passed")
    }

    /// `PanelDraw.DrawPanelLines`：` "[" & Add3Zeros(Measure) & "]" `
    private static func testMeasureCaption() {
        require(LegacyPanelGuides.measureCaption(0) == "[000]", "measure 0 is [000]")
        require(LegacyPanelGuides.measureCaption(12) == "[012]", "measure 12 is [012]")
        require(LegacyPanelGuides.measureCaption(999) == "[999]", "measure 999 is [999]")
    }

    /// `GetColumn.cBG.GetBrightness = 0` 时不填列底色。黑底（RGB 全 0）亮度为 0。
    private static func testBackgroundBrightness() {
        require(!LegacyPanelGuides.shouldFillBackground(red: 0, green: 0, blue: 0), "black column skips fill")
        require(LegacyPanelGuides.shouldFillBackground(red: 0x14, green: 0, blue: 0), "A2 tint is drawn")
        require(LegacyPanelGuides.shouldFillBackground(red: 0xFF, green: 0xFF, blue: 0xFF), "white wash is drawn")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
