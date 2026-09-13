import Foundation

@main
struct LegacyChromeMenuTests {
    static func main() {
        testOptionsTitlesAndDefaults()
        testConversionTitlesAndNTDisable()
        testPreviewShortcutsAndBeats()
        print("LegacyChromeMenuTests passed")
    }

    /// `mnOptions`：NT / Error Check / Preview on Click / Show File Name，再接三扇选项窗。
    private static func testOptionsTitlesAndDefaults() {
        require(
            LegacyChromeMenu.titles(of: LegacyChromeMenu.options) == [
                "LN Input Style - NT/BMSE",
                "Error Check",
                "Preview on Click",
                "Show File Name on Notes",
                "General Options",
                "Visual Options",
                "Player Options",
                "Language",
                "Theme"
            ],
            "Options titles follow Designer"
        )
        guard case .item(_, let ntCommand, let shortcut, _, let ntChecked) = LegacyChromeMenu.options[0] else {
            fputs("NT item missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        require(ntCommand == "TBNTInput" && shortcut == "F8" && ntChecked, "NT is F8 and starts on")
        guard case .item(_, _, _, _, let showName) = LegacyChromeMenu.options[3] else {
            fputs("Show File Name item missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        require(!showName, "Show File Name starts off")
    }

    /// `cmnConversion` 文案对 Designer；NT 打开时 → Long 和 Long ↔ Short 禁用。
    private static func testConversionTitlesAndNTDisable() {
        require(
            LegacyChromeMenu.titles(of: LegacyChromeMenu.conversions) == [
                "→ Long Note",
                "→ Short Note",
                "Long Note ↔ Short Note",
                "→ Hidden Note",
                "→ Visible Note",
                "Hidden Note ↔ Visible Note",
                "Modify Labels",
                "Mirror"
            ],
            "Conversions titles follow Designer"
        )
        require(!LegacyChromeMenu.conversionEnabled(command: "POBLong", ntInput: true), "NT disables → Long")
        require(!LegacyChromeMenu.conversionEnabled(command: "POBLongShort", ntInput: true), "NT disables Long ↔ Short")
        require(LegacyChromeMenu.conversionEnabled(command: "POBShort", ntInput: true), "→ Short stays enabled")
        require(LegacyChromeMenu.conversionEnabled(command: "POBLong", ntInput: false), "BMSE enables → Long")
        require(LegacyChromeMenu.conversionEnabled(command: "POBMirror", ntInput: true), "Mirror stays enabled")
    }

    /// `mnPreview`：F5 从拍 0，F6 从鼠标拍，F7 停止。不启动外置播放器。
    private static func testPreviewShortcutsAndBeats() {
        require(
            LegacyChromeMenu.titles(of: LegacyChromeMenu.preview) == [
                "Play from beginning",
                "Play from here",
                "Stop"
            ],
            "Preview titles follow Designer"
        )
        require(LegacyChromeMenu.previewCommand(toolbar: "TBPlayB") == .playFromBeginning, "TBPlayB is beginning")
        require(LegacyChromeMenu.previewCommand(toolbar: "TBPlay") == .playFromHere, "TBPlay is here")
        require(LegacyChromeMenu.previewCommand(toolbar: "TBStop") == .stop, "TBStop is stop")
        require(
            LegacyChromeMenu.playFromBeat(.playFromBeginning, pointerBeat: 4) == 0,
            "beginning ignores the pointer"
        )
        require(LegacyChromeMenu.playFromBeat(.playFromHere, pointerBeat: 2) == 2, "here uses the pointer beat")
        require(LegacyChromeMenu.playFromBeat(.stop, pointerBeat: 2) == nil, "stop has no start beat")
        guard case .item(_, _, let f5, _, _) = LegacyChromeMenu.preview[0],
              case .item(_, _, let f6, _, _) = LegacyChromeMenu.preview[1],
              case .item(_, _, let f7, _, _) = LegacyChromeMenu.preview[2] else {
            fputs("Preview shortcuts missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        require(f5 == "F5" && f6 == "F6" && f7 == "F7", "F5 / F6 / F7")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
