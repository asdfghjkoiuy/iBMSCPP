import AppKit
import Foundation

@main
struct ChartThemeTests {
    static func main() throws {
        try importsAllBundledSourceThemes()
        try preservesPartialLoadInheritance()
        try rejectsMalformedAndOutOfRangeInput()
        verifiesZeroWidthAndLegacyARGBDerivation()
        try roundTripsThemeAppearance()
        parsesLegacyThemeCompatibility()
        print("ChartThemeTests passed")
    }

    private static func importsAllBundledSourceThemes() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("macos/Resources/Themes", isDirectory: true)
        let resources = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".Theme.xml") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        require(resources.count == 8, "expected all eight source themes")
        for url in resources {
            let result = try ChartThemeCodec.importTheme(data: Data(contentsOf: url))
            require(result.theme.columns.count == 28, "\(url.lastPathComponent) did not retain all legacy columns")
            require(result.theme.column(at: 6) != nil, "\(url.lastPathComponent) lost a lane header")
            require(result.theme.visual.noteHeight > 0, "\(url.lastPathComponent) did not load VisualSettings")
        }
    }

    private static func preservesPartialLoadInheritance() throws {
        let partial = """
        <?xml version="1.0" encoding="utf-8"?>
        <iBMSC><Columns><Column Index="6" Width="77" /></Columns><VisualSettings><kFont Name="Partial Face" /></VisualSettings></iBMSC>
        """
        let result = try ChartThemeCodec.importTheme(data: Data(partial.utf8))
        let inherited = ChartTheme.defaultTheme.column(at: 6)!
        let imported = result.theme.column(at: 6)!
        require(imported.width == 77 && imported.title == inherited.title, "missing Column attrs must inherit base state")
        require(imported.isVisible == inherited.isVisible, "missing Display must preserve base visibility")
        require(result.theme.visual.noteFont.name == "Partial Face", "provided font name was not loaded")
        require(result.theme.visual.noteFont.pointSize == ChartTheme.defaultTheme.visual.noteFont.pointSize,
                "missing font size must preserve base point size")
    }

    private static func rejectsMalformedAndOutOfRangeInput() throws {
        do {
            _ = try ChartThemeCodec.importTheme(data: Data("<iBMSC><Columns>".utf8))
            fail("malformed XML was accepted")
        } catch ThemeCodecError.malformedXML { }

        let source = "<iBMSC><Columns><Column Index=\"99\" Width=\"10\" /></Columns></iBMSC>"
        let result = try ChartThemeCodec.importTheme(data: Data(source.utf8))
        require(result.diagnostics.contains(.ignoredColumnIndex(99)), "out-of-range legacy index needs a diagnostic")
        require(result.theme == ChartTheme.defaultTheme, "out-of-range Column must not mutate the theme")

        let unsafe = "<iBMSC><Columns><Column Index=\"6\" Width=\"-1\" /></Columns><VisualSettings><kHeight Value=\"0\" /><kOpacity Value=\"2\" /><kFont Size=\"9999\" /></VisualSettings></iBMSC>"
        let safe = try ChartThemeCodec.importTheme(data: Data(unsafe.utf8))
        require(safe.theme.column(at: 6) == ChartTheme.defaultTheme.column(at: 6), "invalid width must retain the base column")
        require(safe.theme.visual.noteHeight == ChartTheme.defaultTheme.visual.noteHeight && safe.theme.visual.hiddenNoteOpacity == ChartTheme.defaultTheme.visual.hiddenNoteOpacity,
                "unsafe VisualSettings values must retain safe base drawing values")

        let nested = "<iBMSC><Ignored><VisualSettings><Bg Value=\"-1\" /></VisualSettings></Ignored></iBMSC>"
        let isolated = try ChartThemeCodec.importTheme(data: Data(nested.utf8))
        require(isolated.theme.visual.background == ChartTheme.defaultTheme.visual.background,
                "only exact iBMSC/VisualSettings leaf paths may alter the theme")
    }

    private static func verifiesZeroWidthAndLegacyARGBDerivation() {
        var zero = ChartTheme.defaultTheme.column(at: 6)!
        zero.width = 0
        zero.isVisible = true
        require(!zero.effectiveVisible, "Width=0 must disable/hide the effective lane")

        zero.noteColor = ThemeColor(argb: 0x80_80_80_80)
        let regular = zero.derivedColors(longNote: false, hidden: false, hiddenOpacity: 0.5)
        let hidden = zero.derivedColors(longNote: false, hidden: true, hiddenOpacity: 0.5)
        require(regular.bright.argb == 0x40_C0_C0_C0 && regular.dark.argb == 0x40_60_60_60,
                "legacy RGB bright/dark must be component-based with banker rounding and A²/255 alpha")
        require(hidden.bright.argb == 0x20_C0_C0_C0 && hidden.dark.argb == 0x20_60_60_60,
                "kOpacity must apply after A²/255 and only to hidden notes")
    }

    private static func roundTripsThemeAppearance() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = root.appendingPathComponent("macos/Resources/Themes/IIDX.Theme.xml")
        let original = try ChartThemeCodec.importTheme(data: Data(contentsOf: source)).theme
        let exported = try ChartThemeCodec.exportTheme(original)
        require(exported.starts(with: [0xFF, 0xFE]), "legacy export must be UTF-16LE with BOM")
        let restored = try ChartThemeCodec.importTheme(data: exported).theme
        require(restored == original, "theme XML roundtrip changed appearance")

        let future = "<iBMSC><VisualSettings><FutureBorder Width=\"2\" Color=\"-1\" /></VisualSettings></iBMSC>"
        let retained = try ChartThemeCodec.importTheme(data: Data(future.utf8)).theme
        let retainedXML = String(data: try ChartThemeCodec.exportTheme(retained).dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        require(retainedXML.contains("<FutureBorder Color=\"-1\" Width=\"2\" />"), "unsupported visual fields must survive export")
    }

    private static func parsesLegacyThemeCompatibility() {
        require(LegacyThemeCompatibility.recognizeHeader("  iBMSC Theme Format\r"),
                "trimmed iBMSC Theme Format must be a valid header")
        require(LegacyThemeCompatibility.recognizeHeader("iBMSC Configuration Settings Format"),
                "configuration header must be accepted")
        require(!LegacyThemeCompatibility.recognizeHeader("not a theme"), "unknown header must be rejected")

        var base = ChartTheme.defaultTheme
        base.visual.background = ThemeColor(signedARGB: 123)
        base.visual.noteHeight = 10
        base.visual.noteMouseOverEnd = ThemeColor(signedARGB: -16711681)
        if let column = base.columns.firstIndex(where: { $0.legacyIndex == 27 }) {
            base.columns[column].width = 77
        }

        let background = requiredParse(
            "iBMSC Theme Format\r\nVOBG=-1\r\n",
            base: base
        )
        require(background.visual.background == ThemeColor(signedARGB: -1), "VOBG must rewrite background")
        require(background.visual.noteHeight == base.visual.noteHeight, "unmentioned visual fields inherit base")
        require(background.column(at: 6)?.title == base.column(at: 6)?.title, "unmentioned columns inherit base")

        require(LegacyThemeCompatibility.parse("not a header\r\nVOBG=-1\r\n", base: base) == nil,
                "wrong first line must return nil")

        let lengths = requiredParse("iBMSC Theme Format\r\nKLENGTH=10,20\r\n", base: base)
        require(lengths.column(at: 0)?.width == 10, "KLENGTH column 0 must be 10")
        require(lengths.column(at: 1)?.width == 20, "KLENGTH column 1 must be 20")
        for index in 2...26 {
            require(lengths.column(at: index)?.width == 0, "missing KLENGTH parts through 26 must be 0")
        }
        require(lengths.column(at: 27)?.width == 77, "KLENGTH must not write column 27")

        let mouseOverEnd = requiredParse(
            "iBMSC Theme Format\r\nVKMOUSEOVERE=-16777216\r\n",
            base: base
        )
        require(mouseOverEnd.visual.noteMouseOverEnd == base.visual.noteMouseOverEnd,
                "VKMOUSEOVERE without the trailing-space Case must not change noteMouseOverEnd")

        let height = requiredParse("iBMSC Theme Format\r\nVKHEIGHT=12\r\n", base: base)
        require(height.visual.noteHeight == 12, "VKHEIGHT must set noteHeight")

        let fallback = ThemeFont(name: "Tahoma", pointSize: 8.25, style: 0)
        let font = LegacyThemeCompatibility.stringToFont("Verdana,9,1", fallback: fallback)
        require(font.name == "Verdana" && font.pointSize == 9 && font.style == 1,
                "three-part font must parse Name, Size, Style")
        require(LegacyThemeCompatibility.stringToFont("Verdana,9", fallback: fallback) == fallback,
                "two-part font must keep the fallback")
    }

    private static func requiredParse(_ text: String, base: ChartTheme) -> ChartTheme {
        guard let theme = LegacyThemeCompatibility.parse(text, base: base) else {
            fail("expected a parsed legacy theme")
            return base
        }
        return theme
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
