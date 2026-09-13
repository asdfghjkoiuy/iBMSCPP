import AppKit
import Foundation

/// An iBMSC colour stored in the same `AARRGGBB` representation as `Color.ToArgb()`.
struct ThemeColor: Equatable, Sendable {
    let argb: UInt32

    init(argb: UInt32) { self.argb = argb }
    init(signedARGB: Int32) { self.argb = UInt32(bitPattern: signedARGB) }
    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.argb = (UInt32(alpha) << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)
    }

    var signedARGB: Int32 { Int32(bitPattern: argb) }
    var alpha: UInt8 { UInt8((argb >> 24) & 0xFF) }
    var red: UInt8 { UInt8((argb >> 16) & 0xFF) }
    var green: UInt8 { UInt8((argb >> 8) & 0xFF) }
    var blue: UInt8 { UInt8(argb & 0xFF) }

    var nsColor: NSColor {
        NSColor(calibratedRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
    }

    func replacing(alpha: UInt8) -> ThemeColor {
        ThemeColor(argb: (UInt32(alpha) << 24) | (argb & 0x00FF_FFFF))
    }
}

/// GDI+ font information as represented by the legacy XML. `pointSize` is deliberately
/// in points: use `logicalPixelSize` when drawing at the source application's 96 DPI scale.
struct ThemeFont: Equatable, Sendable {
    var name: String
    var pointSize: Double
    var style: Int

    /// `Font.SizeInPoints` in legacy XML, converted to the source's 96-DPI logical pixels.
    var logicalPixelSize: Double { pointSize * 4.0 / 3.0 }
}

struct ThemeGradientColors: Equatable, Sendable {
    let bright: ThemeColor
    let dark: ThemeColor
}

/// A forward-compatible VisualSettings leaf retained exactly as attributes. The legacy format
/// uses attribute-only leaves, so retaining this representation does not import any runtime state.
struct PreservedThemeElement: Equatable, Sendable {
    let name: String
    let attributes: [String: String]
}

/// A legacy `Column` record. `legacyIndex` is the EditorColumns array index, not a BMS channel.
struct ThemeColumn: Equatable, Sendable {
    let legacyIndex: Int
    var width: Int
    var title: String
    var isVisible: Bool
    var noteColor: ThemeColor
    var textColor: ThemeColor
    var longNoteColor: ThemeColor
    var longTextColor: ThemeColor
    var backgroundColor: ThemeColor

    /// Matches `Column.isEnabledAfterAll` for display purposes: zero-width lanes disappear.
    var effectiveVisible: Bool { isVisible && width != 0 }

    /// Source-compatible endpoint colours. Opacity is applied only when the note itself is
    /// hidden; regular and long-note bodies otherwise use `hidden: false`.
    func derivedColors(longNote: Bool, hidden: Bool, hiddenOpacity: Double) -> ThemeGradientColors {
        let base = longNote ? longNoteColor : noteColor
        // Imported themes are range-checked, and this additional clamp keeps direct callers
        // from feeding invalid opacity into the source-compatible rounding calculation.
        let requestedOpacity = hidden ? hiddenOpacity : 1
        let opacity = requestedOpacity.isFinite ? min(max(requestedOpacity, 0), 1) : 0
        return ThemeGradientColors(
            bright: ThemeColumn.adjustBrightness(base, percent: 50, finalOpacity: opacity),
            dark: ThemeColumn.adjustBrightness(base, percent: -25, finalOpacity: opacity)
        )
    }

    // `Utilities.AdjustBrightness` is component-wise, with VB/.NET banker rounding.  The
    // legacy callers first pass A / 255, producing A² / 255 before `kOpacity` is applied.
    private static func adjustBrightness(_ color: ThemeColor, percent: Double, finalOpacity: Double) -> ThemeColor {
        guard color.alpha != 0 else { return ThemeColor(argb: 0) }
        let magnitude = abs(percent)
        func channel(_ component: UInt8) -> UInt8 {
            let value = Double(component) * (100 - magnitude) / 100 + (percent >= 0 ? magnitude * 2.55 : 0)
            return UInt8(clamping: bankersRound(value))
        }
        let cacheAlpha = bankersRound(Double(color.alpha) * Double(color.alpha) / 255)
        let alpha = UInt8(clamping: bankersRound(Double(cacheAlpha) * finalOpacity))
        return ThemeColor(argb: (UInt32(alpha) << 24) | (UInt32(channel(color.red)) << 16)
                          | (UInt32(channel(color.green)) << 8) | UInt32(channel(color.blue)))
    }
}

struct ThemeVisualSettings: Equatable, Sendable {
    var columnTitle: ThemeColor
    var columnTitleFont: ThemeFont
    var background: ThemeColor
    var grid: ThemeColor
    var subGrid: ThemeColor
    var verticalLine: ThemeColor
    var measureLine: ThemeColor
    var bgmWaveform: ThemeColor
    var selectionBox: ThemeColor
    var timeSelectionCursor: ThemeColor
    var timeSelectionHalf: ThemeColor
    var timeSelectionDeltaMouseOver: Int
    var timeSelectionMouseOver: ThemeColor
    var timeSelectionSelection: ThemeColor
    var timeSelectionBPM: ThemeColor
    var timeSelectionBPMFont: ThemeFont
    var middleDeltaRelease: Int
    var noteHeight: Int
    var noteFont: ThemeFont
    var measureFont: ThemeFont
    var labelVerticalShift: Int
    var labelHorizontalShift: Int
    var longLabelHorizontalShift: Int
    var noteMouseOver: ThemeColor
    var noteMouseOverEnd: ThemeColor
    var noteSelected: ThemeColor
    /// Legacy `kOpacity`: only pass this to hidden note endpoints, never globally to LN bodies.
    var hiddenNoteOpacity: Double
}

/// Native menu contract for the two named original skins. Other source files can be discovered
/// by enumerating the Themes resource directory.
enum ThemeBuiltin: String, CaseIterable, Sendable {
    case iidx = "IIDX"
    case o2Mania = "O2Mania"
}

/// Appearance-only state. It has no chart, document, undo, playback, or player-path fields.
struct ChartTheme: Equatable, Sendable {
    static let maximumLegacyColumnIndex = 27

    var columns: [ThemeColumn]
    var visual: ThemeVisualSettings
    /// Unsupported VisualSettings leaves retained for lossless forward-compatible re-export.
    var preservedVisualElements: [PreservedThemeElement] = []

    var laneHeaders: [Int: ThemeColumn] {
        Dictionary(uniqueKeysWithValues: columns.map { ($0.legacyIndex, $0) })
    }

    func column(at legacyIndex: Int) -> ThemeColumn? {
        columns.first { $0.legacyIndex == legacyIndex }
    }

    /// The default EditorColumns/VisualSettings state used when a partial legacy theme omits a field.
    static let defaultTheme = ChartTheme(columns: defaultColumns, visual: defaultVisual)

    /// Reads the verbatim UTF-16 source resource after the app has bundled `Resources/Themes`.
    static func bundledTheme(named name: String, bundle: Bundle = .main) throws -> ChartTheme {
        guard let url = bundle.url(forResource: name, withExtension: "Theme.xml", subdirectory: "Themes") else {
            throw ThemeCodecError.resourceNotFound(name)
        }
        return try ChartThemeCodec.importTheme(data: Data(contentsOf: url)).theme
    }

    static func bundledTheme(_ builtin: ThemeBuiltin, bundle: Bundle = .main) throws -> ChartTheme {
        try bundledTheme(named: builtin.rawValue, bundle: bundle)
    }

    /// These deliberately surface a missing or malformed bundle resource instead of silently
    /// presenting the default theme as IIDX/O2Mania.
    static func builtInIIDX(bundle: Bundle = .main) throws -> ChartTheme {
        try bundledTheme(.iidx, bundle: bundle)
    }

    static func builtInO2Mania(bundle: Bundle = .main) throws -> ChartTheme {
        try bundledTheme(.o2Mania, bundle: bundle)
    }
}

enum ThemeDiagnostic: Equatable, Sendable, CustomStringConvertible {
    case unsupportedElement(String)
    case preservedVisualElement(String)
    case unsupportedAttribute(element: String, attribute: String)
    case ignoredColumnIndex(Int)
    case invalidValue(element: String, attribute: String, value: String)
    case duplicateColumn(Int)

    var description: String {
        switch self {
        case .unsupportedElement(let name): return "Ignored unsupported theme element <\(name)>."
        case .preservedVisualElement(let name): return "Preserved unsupported VisualSettings element <\(name)> for export."
        case .unsupportedAttribute(let element, let attribute): return "Ignored unsupported attribute \(attribute) on <\(element)>."
        case .ignoredColumnIndex(let index): return "Ignored Column Index \(index); supported range is 0...\(ChartTheme.maximumLegacyColumnIndex)."
        case .invalidValue(let element, let attribute, let value): return "Ignored invalid \(attribute)='\(value)' on <\(element)>."
        case .duplicateColumn(let index): return "Column Index \(index) appeared more than once; the final record was used."
        }
    }
}

struct ThemeImportResult: Sendable {
    let theme: ChartTheme
    let diagnostics: [ThemeDiagnostic]
}

enum ThemeCodecError: Error, Equatable, Sendable, LocalizedError {
    case inputTooLarge(Int)
    case unsupportedEncoding
    case forbiddenDTD
    case malformedXML(String)
    case invalidRoot
    case resourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .inputTooLarge(let count): return "Theme input is \(count) bytes; the 1 MiB limit prevents unbounded parsing."
        case .unsupportedEncoding: return "Theme XML must be UTF-8 or UTF-16."
        case .forbiddenDTD: return "Theme XML may not contain a DTD or entity declaration."
        case .malformedXML(let message): return "Malformed theme XML: \(message)"
        case .invalidRoot: return "Theme XML requires an <iBMSC> root element."
        case .resourceNotFound(let name): return "Bundled theme \(name).Theme.xml was not found."
        }
    }
}

enum ChartThemeCodec {
    static let maximumInputBytes = 1_048_576

    static func importTheme(data: Data, base: ChartTheme = .defaultTheme) throws -> ThemeImportResult {
        guard data.count <= maximumInputBytes else { throw ThemeCodecError.inputTooLarge(data.count) }
        guard let text = decodedText(data) else { throw ThemeCodecError.unsupportedEncoding }
        let upper = text.uppercased()
        guard !upper.contains("<!DOCTYPE"), !upper.contains("<!ENTITY") else { throw ThemeCodecError.forbiddenDTD }

        let delegate = ThemeXMLDelegate(base: base)
        // Parse the original bytes so an XML declaration such as `encoding="utf-16"`
        // remains truthful. `text` above is used only for bounded DTD/entity screening.
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            if let failure = delegate.failure { throw failure }
            throw ThemeCodecError.malformedXML(parser.parserError?.localizedDescription ?? "unknown parser error")
        }
        if let failure = delegate.failure { throw failure }
        guard delegate.sawRoot else { throw ThemeCodecError.invalidRoot }
        return ThemeImportResult(theme: delegate.theme, diagnostics: delegate.diagnostics)
    }

    /// Exports the legacy theme-only envelope in UTF-16LE with a BOM, matching XmlTextWriter(Encoding.Unicode).
    static func exportTheme(_ theme: ChartTheme) throws -> Data {
        guard theme.columns.count <= ChartTheme.maximumLegacyColumnIndex + 1 else {
            throw ThemeCodecError.malformedXML("too many theme columns")
        }
        var lines = ["<?xml version=\"1.0\" encoding=\"utf-16\"?>", "<iBMSC>", "    <Columns>"]
        for column in theme.columns.sorted(by: { $0.legacyIndex < $1.legacyIndex }) {
            guard (0...ChartTheme.maximumLegacyColumnIndex).contains(column.legacyIndex) else { continue }
            lines.append("        <Column Index=\"\(column.legacyIndex)\" Width=\"\(column.width)\" Title=\"\(escape(column.title))\" Display=\"\(column.isVisible)\" NoteColor=\"\(column.noteColor.signedARGB)\" TextColor=\"\(column.textColor.signedARGB)\" LongNoteColor=\"\(column.longNoteColor.signedARGB)\" LongTextColor=\"\(column.longTextColor.signedARGB)\" BG=\"\(column.backgroundColor.signedARGB)\" />")
        }
        lines.append("    </Columns>")
        lines.append("    <VisualSettings>")
        let v = theme.visual
        func value(_ name: String, _ color: ThemeColor) { lines.append("        <\(name) Value=\"\(color.signedARGB)\" />") }
        func integer(_ name: String, _ value: Int) { lines.append("        <\(name) Value=\"\(value)\" />") }
        func number(_ name: String, _ value: Double) { lines.append("        <\(name) Value=\"\(decimal(value))\" />") }
        func font(_ name: String, _ font: ThemeFont) { lines.append("        <\(name) Name=\"\(escape(font.name))\" Size=\"\(decimal(font.pointSize))\" Style=\"\(font.style)\" />") }
        value("ColumnTitle", v.columnTitle); font("ColumnTitleFont", v.columnTitleFont)
        value("Bg", v.background); value("Grid", v.grid); value("Sub", v.subGrid); value("VLine", v.verticalLine); value("MLine", v.measureLine); value("BGMWav", v.bgmWaveform)
        value("SelBox", v.selectionBox); value("TSCursor", v.timeSelectionCursor); value("TSHalf", v.timeSelectionHalf); integer("TSDeltaMouseOver", v.timeSelectionDeltaMouseOver)
        value("TSMouseOver", v.timeSelectionMouseOver); value("TSSel", v.timeSelectionSelection); value("TSBPM", v.timeSelectionBPM); font("TSBPMFont", v.timeSelectionBPMFont); integer("MiddleDeltaRelease", v.middleDeltaRelease)
        integer("kHeight", v.noteHeight); font("kFont", v.noteFont); font("kMFont", v.measureFont); integer("kLabelVShift", v.labelVerticalShift); integer("kLabelHShift", v.labelHorizontalShift); integer("kLabelHShiftL", v.longLabelHorizontalShift)
        value("kMouseOver", v.noteMouseOver); value("kMouseOverE", v.noteMouseOverEnd); value("kSelected", v.noteSelected); number("kOpacity", v.hiddenNoteOpacity)
        for preserved in theme.preservedVisualElements {
            let attributes = preserved.attributes.keys.sorted().map { key in
                " \(key)=\"\(escape(preserved.attributes[key] ?? ""))\""
            }.joined()
            lines.append("        <\(preserved.name)\(attributes) />")
        }
        lines.append("    </VisualSettings>")
        lines.append("</iBMSC>")
        let payload = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xFF, 0xFE]) + (payload.data(using: .utf16LittleEndian) ?? Data())
    }

    private static func decodedText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if data.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        return String(data: data, encoding: .utf8)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private final class ThemeXMLDelegate: NSObject, XMLParserDelegate {
    private let supportedVisualValues: [String: WritableKeyPath<ThemeVisualSettings, ThemeColor>] = [
        "ColumnTitle": \.columnTitle, "Bg": \.background, "Grid": \.grid, "Sub": \.subGrid,
        "VLine": \.verticalLine, "MLine": \.measureLine, "BGMWav": \.bgmWaveform,
        "SelBox": \.selectionBox, "TSCursor": \.timeSelectionCursor, "TSHalf": \.timeSelectionHalf,
        "TSMouseOver": \.timeSelectionMouseOver, "TSSel": \.timeSelectionSelection,
        "TSBPM": \.timeSelectionBPM, "kMouseOver": \.noteMouseOver, "kMouseOverE": \.noteMouseOverEnd,
        "kSelected": \.noteSelected
    ]
    private let supportedVisualIntegers: [String: WritableKeyPath<ThemeVisualSettings, Int>] = [
        "TSDeltaMouseOver": \.timeSelectionDeltaMouseOver, "MiddleDeltaRelease": \.middleDeltaRelease,
        "kHeight": \.noteHeight, "kLabelVShift": \.labelVerticalShift, "kLabelHShift": \.labelHorizontalShift,
        "kLabelHShiftL": \.longLabelHorizontalShift
    ]
    private let supportedFonts: [String: WritableKeyPath<ThemeVisualSettings, ThemeFont>] = [
        "ColumnTitleFont": \.columnTitleFont, "TSBPMFont": \.timeSelectionBPMFont,
        "kFont": \.noteFont, "kMFont": \.measureFont
    ]

    var theme: ChartTheme
    var diagnostics = [ThemeDiagnostic]()
    var failure: ThemeCodecError?
    var sawRoot = false
    private var stack = [String]()
    private var elementCount = 0
    private var seenColumns = Set<Int>()

    init(base: ChartTheme) { self.theme = base }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elementCount += 1
        if elementCount > 128 || stack.count >= 4 {
            failure = .malformedXML("theme nesting or element count exceeds the compatibility limit")
            parser.abortParsing()
            return
        }
        stack.append(elementName)
        if stack.count == 1 {
            guard elementName == "iBMSC" else { failure = .invalidRoot; parser.abortParsing(); return }
            sawRoot = true
            checkAttributes(elementName, attributeDict, allowed: ["Major", "Minor", "Build"])
            return
        }
        if stack == ["iBMSC", "Columns"] || stack == ["iBMSC", "VisualSettings"] {
            checkAttributes(elementName, attributeDict, allowed: [])
        } else if stack == ["iBMSC", "Columns", "Column"] {
            loadColumn(attributeDict)
        } else if stack.count == 3 && stack[0] == "iBMSC" && stack[1] == "VisualSettings" {
            loadVisual(elementName, attributes: attributeDict)
        } else {
            diagnostics.append(.unsupportedElement(elementName))
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }

    private func loadColumn(_ attributes: [String: String]) {
        checkAttributes("Column", attributes, allowed: ["Index", "Width", "Title", "Display", "NoteColor", "TextColor", "LongNoteColor", "LongTextColor", "BG"])
        guard let rawIndex = attributes["Index"], let index = Int(rawIndex) else {
            diagnostics.append(.invalidValue(element: "Column", attribute: "Index", value: attributes["Index"] ?? "")); return
        }
        guard (0...ChartTheme.maximumLegacyColumnIndex).contains(index) else { diagnostics.append(.ignoredColumnIndex(index)); return }
        guard let position = theme.columns.firstIndex(where: { $0.legacyIndex == index }) else { return }
        if !seenColumns.insert(index).inserted { diagnostics.append(.duplicateColumn(index)) }
        var column = theme.columns[position]
        if let value = attributes["Width"] { assignBoundedInt(value, element: "Column", attribute: "Width", range: 0...10_000) { column.width = $0 } }
        if let value = attributes["Title"] { column.title = value }
        if let value = attributes["Display"] { assignBool(value, element: "Column", attribute: "Display") { column.isVisible = $0 } }
        if let value = attributes["NoteColor"] { assignColor(value, element: "Column", attribute: "NoteColor") { column.noteColor = $0 } }
        if let value = attributes["TextColor"] { assignColor(value, element: "Column", attribute: "TextColor") { column.textColor = $0 } }
        if let value = attributes["LongNoteColor"] { assignColor(value, element: "Column", attribute: "LongNoteColor") { column.longNoteColor = $0 } }
        if let value = attributes["LongTextColor"] { assignColor(value, element: "Column", attribute: "LongTextColor") { column.longTextColor = $0 } }
        if let value = attributes["BG"] { assignColor(value, element: "Column", attribute: "BG") { column.backgroundColor = $0 } }
        theme.columns[position] = column
    }

    private func loadVisual(_ element: String, attributes: [String: String]) {
        if let path = supportedVisualValues[element] {
            checkAttributes(element, attributes, allowed: ["Value"])
            if let value = attributes["Value"] { assignColor(value, element: element, attribute: "Value") { theme.visual[keyPath: path] = $0 } }
        } else if let path = supportedVisualIntegers[element] {
            checkAttributes(element, attributes, allowed: ["Value"])
            if let value = attributes["Value"] { assignBoundedInt(value, element: element, attribute: "Value", range: integerRange(for: element)) { theme.visual[keyPath: path] = $0 } }
        } else if let path = supportedFonts[element] {
            checkAttributes(element, attributes, allowed: ["Name", "Size", "Style"])
            var font = theme.visual[keyPath: path]
            if let name = attributes["Name"] { font.name = name }
            if let size = attributes["Size"] { assignBoundedDouble(size, element: element, attribute: "Size", range: 0.1...512) { font.pointSize = $0 } }
            if let style = attributes["Style"] { assignInt(style, element: element, attribute: "Style") { font.style = $0 } }
            theme.visual[keyPath: path] = font
        } else if element == "kOpacity" {
            checkAttributes(element, attributes, allowed: ["Value"])
            if let value = attributes["Value"] { assignBoundedDouble(value, element: element, attribute: "Value", range: 0...1) { theme.visual.hiddenNoteOpacity = $0 } }
        } else {
            theme.preservedVisualElements.append(PreservedThemeElement(name: element, attributes: attributes))
            diagnostics.append(.preservedVisualElement(element))
        }
    }

    private func checkAttributes(_ element: String, _ attributes: [String: String], allowed: Set<String>) {
        for attribute in attributes.keys where !allowed.contains(attribute) { diagnostics.append(.unsupportedAttribute(element: element, attribute: attribute)) }
    }

    private func assignInt(_ value: String, element: String, attribute: String, assign: (Int) -> Void) {
        guard let parsed = Int(value) else { diagnostics.append(.invalidValue(element: element, attribute: attribute, value: value)); return }
        assign(parsed)
    }
    private func assignBoundedInt(_ value: String, element: String, attribute: String, range: ClosedRange<Int>, assign: (Int) -> Void) {
        guard let parsed = Int(value), range.contains(parsed) else { diagnostics.append(.invalidValue(element: element, attribute: attribute, value: value)); return }
        assign(parsed)
    }
    private func assignDouble(_ value: String, element: String, attribute: String, assign: (Double) -> Void) {
        guard let parsed = Double(value), parsed.isFinite else { diagnostics.append(.invalidValue(element: element, attribute: attribute, value: value)); return }
        assign(parsed)
    }
    private func assignBoundedDouble(_ value: String, element: String, attribute: String, range: ClosedRange<Double>, assign: (Double) -> Void) {
        guard let parsed = Double(value), parsed.isFinite, range.contains(parsed) else { diagnostics.append(.invalidValue(element: element, attribute: attribute, value: value)); return }
        assign(parsed)
    }
    private func assignBool(_ value: String, element: String, attribute: String, assign: (Bool) -> Void) {
        if value.caseInsensitiveCompare("true") == .orderedSame { assign(true) }
        else if value.caseInsensitiveCompare("false") == .orderedSame { assign(false) }
        else { diagnostics.append(.invalidValue(element: element, attribute: attribute, value: value)) }
    }
    private func assignColor(_ value: String, element: String, attribute: String, assign: (ThemeColor) -> Void) {
        guard let parsed = Int64(value), let signed = Int32(exactly: parsed) else { diagnostics.append(.invalidValue(element: element, attribute: attribute, value: value)); return }
        assign(ThemeColor(signedARGB: signed))
    }

    private func integerRange(for element: String) -> ClosedRange<Int> {
        switch element {
        case "kHeight": return 1...4_096
        case "kLabelVShift", "kLabelHShift", "kLabelHShiftL": return -4_096...4_096
        case "TSDeltaMouseOver", "MiddleDeltaRelease": return 0...4_096
        default: return -4_096...4_096
        }
    }
}

private func bankersRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}

private let defaultColumns: [ThemeColumn] = [
    c(0, 50, "Measure", true, 0, 0xFF00FFFF, 0, 0xFF00FFFF, 0), c(1, 60, "SCROLL", true, 0, 0xFFFF0000, 0, 0xFFFF0000, 0), c(2, 60, "BPM", true, 0, 0xFFFF0000, 0, 0xFFFF0000, 0), c(3, 50, "STOP", true, 0, 0xFFFF0000, 0, 0xFFFF0000, 0), c(4, 5, "", true, 0, 0, 0, 0, 0),
    c(5, 42, "A1", true, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(6, 30, "A2", true, 0xFF62B0FF, 0xFF000000, 0xFF6AB0F7, 0xFF000000, 0x140033FF), c(7, 42, "A3", true, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(8, 45, "A4", true, 0xFFFFC862, 0xFF000000, 0xFFF7C66A, 0xFF000000, 0x16F38B0C), c(9, 42, "A5", true, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(10, 30, "A6", true, 0xFF62B0FF, 0xFF000000, 0xFF6AB0F7, 0xFF000000, 0x140033FF), c(11, 42, "A7", true, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(12, 40, "A8", true, 0xFF808080, 0xFF000000, 0xFF909090, 0xFF000000, 0), c(13, 5, "", true, 0, 0, 0, 0, 0),
    c(14, 42, "D1", false, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(15, 30, "D2", false, 0xFF62B0FF, 0xFF000000, 0xFF6AB0F7, 0xFF000000, 0x140033FF), c(16, 42, "D3", false, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(17, 45, "D4", false, 0xFFFFC862, 0xFF000000, 0xFFF7C66A, 0xFF000000, 0x16F38B0C), c(18, 42, "D5", false, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(19, 30, "D6", false, 0xFF62B0FF, 0xFF000000, 0xFF6AB0F7, 0xFF000000, 0x140033FF), c(20, 42, "D7", false, 0xFFB0B0B0, 0xFF000000, 0xFFC0C0C0, 0xFF000000, 0x14FFFFFF), c(21, 40, "D8", false, 0xFF808080, 0xFF000000, 0xFF909090, 0xFF000000, 0), c(22, 5, "", false, 0, 0, 0, 0, 0),
    c(23, 40, "BGA", false, 0xFF8CD78A, 0xFF000000, 0xFF90D38E, 0xFF000000, 0), c(24, 40, "LAYER", false, 0xFF8CD78A, 0xFF000000, 0xFF90D38E, 0xFF000000, 0), c(25, 40, "POOR", false, 0xFF8CD78A, 0xFF000000, 0xFF90D38E, 0xFF000000, 0), c(26, 5, "", false, 0, 0, 0, 0, 0), c(27, 40, "B", true, 0xFFE18080, 0xFF000000, 0xFFDC8585, 0xFF000000, 0)
]

private func c(_ index: Int, _ width: Int, _ title: String, _ visible: Bool, _ note: UInt32, _ text: UInt32, _ longNote: UInt32, _ longText: UInt32, _ background: UInt32) -> ThemeColumn {
    ThemeColumn(legacyIndex: index, width: width, title: title, isVisible: visible, noteColor: ThemeColor(argb: note), textColor: ThemeColor(argb: text), longNoteColor: ThemeColor(argb: longNote), longTextColor: ThemeColor(argb: longText), backgroundColor: ThemeColor(argb: background))
}

private let defaultVisual = ThemeVisualSettings(
    columnTitle: ThemeColor(signedARGB: -16711936), columnTitleFont: ThemeFont(name: "Tahoma", pointSize: 8.25, style: 0), background: ThemeColor(signedARGB: -16777216), grid: ThemeColor(signedARGB: 893008442), subGrid: ThemeColor(signedARGB: 1530542650), verticalLine: ThemeColor(signedARGB: -13158601), measureLine: ThemeColor(signedARGB: 1599230546), bgmWaveform: ThemeColor(signedARGB: 851493056), selectionBox: ThemeColor(signedARGB: -1056964609), timeSelectionCursor: ThemeColor(signedARGB: -1056997248), timeSelectionHalf: ThemeColor(signedARGB: -2139062017), timeSelectionDeltaMouseOver: 5, timeSelectionMouseOver: ThemeColor(signedARGB: -2130739072), timeSelectionSelection: ThemeColor(signedARGB: 855605376), timeSelectionBPM: ThemeColor(signedARGB: 855605376), timeSelectionBPMFont: ThemeFont(name: "Verdana", pointSize: 9, style: 1), middleDeltaRelease: 10, noteHeight: 10, noteFont: ThemeFont(name: "Verdana", pointSize: 9, style: 1), measureFont: ThemeFont(name: "Verdana", pointSize: 9, style: 0), labelVerticalShift: -2, labelHorizontalShift: 0, longLabelHorizontalShift: 2, noteMouseOver: ThemeColor(signedARGB: -16711936), noteMouseOverEnd: ThemeColor(signedARGB: -16711681), noteSelected: ThemeColor(signedARGB: -65536), hiddenNoteOpacity: 0.5
)

/// iBMSC 2.x `.th` loader. Keys and the `VKMOUSEOVERE ` trailing-space Case match
/// `LoadThemeComptability` in `EditorPersistent.vb`.
enum LegacyThemeCompatibility {
    static func recognizeHeader(_ firstLine: String) -> Bool {
        let trimmed = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        return trimmed == "iBMSC Configuration Settings Format" || trimmed == "iBMSC Theme Format"
    }

    /// First line must be a recognized header; otherwise `nil`. Remaining lines patch a copy of `base`.
    static func parse(_ text: String, base: ChartTheme) -> ChartTheme? {
        let lines = splitLines(text)
        guard let first = lines.first, recognizeHeader(first) else { return nil }
        var theme = base
        for line in lines {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).uppercased()
            let value = String(line[line.index(after: equals)...])
            apply(key: key, value: value, to: &theme)
        }
        return theme
    }

    /// Comma-split, then `ReDim Preserve` to index 26 (27 parts).
    static func split26(_ line: String) -> [String] {
        var parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.count < 27 {
            parts.append(contentsOf: Array(repeating: "", count: 27 - parts.count))
        } else if parts.count > 27 {
            parts = Array(parts.prefix(27))
        }
        return parts
    }

    /// `StringToFont`: exactly three comma parts, else `fallback`. Size and Style use VB `Val`.
    static func stringToFont(_ text: String, fallback: ThemeFont) -> ThemeFont {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return fallback }
        return ThemeFont(name: parts[0], pointSize: val(parts[1]), style: intValue(parts[2]))
    }

    private static func apply(key: String, value: String, to theme: inout ChartTheme) {
        switch key {
        case "VOTITLE": theme.visual.columnTitle = themeColor(value)
        case "VOTITLEFONT": theme.visual.columnTitleFont = stringToFont(value, fallback: theme.visual.columnTitleFont)
        case "VOBG": theme.visual.background = themeColor(value)
        case "VOGRID": theme.visual.grid = themeColor(value)
        case "VOSUB": theme.visual.subGrid = themeColor(value)
        case "VOVLINE": theme.visual.verticalLine = themeColor(value)
        case "VOMLINE": theme.visual.measureLine = themeColor(value)
        case "VOBGMWAV": theme.visual.bgmWaveform = themeColor(value)
        case "VOSELBOX": theme.visual.selectionBox = themeColor(value)
        case "VOPECURSOR": theme.visual.timeSelectionCursor = themeColor(value)
        case "VOPEHALF": theme.visual.timeSelectionHalf = themeColor(value)
        case "VOPEDELTAMOUSEOVER": theme.visual.timeSelectionDeltaMouseOver = intValue(value)
        case "VOPEMOUSEOVER": theme.visual.timeSelectionMouseOver = themeColor(value)
        case "VOPESEL": theme.visual.timeSelectionSelection = themeColor(value)
        case "VOPEBPM": theme.visual.timeSelectionBPM = themeColor(value)
        case "VOPEBPMFONT": theme.visual.timeSelectionBPMFont = stringToFont(value, fallback: theme.visual.timeSelectionBPMFont)
        case "VKHEIGHT": theme.visual.noteHeight = intValue(value)
        case "VKFONT": theme.visual.noteFont = stringToFont(value, fallback: theme.visual.noteFont)
        case "VKMFONT": theme.visual.measureFont = stringToFont(value, fallback: theme.visual.measureFont)
        case "VKLABELVSHIFT": theme.visual.labelVerticalShift = intValue(value)
        case "VKLABELHSHIFT": theme.visual.labelHorizontalShift = intValue(value)
        case "VKLABELHSHIFTL": theme.visual.longLabelHorizontalShift = intValue(value)
        case "VKMOUSEOVER": theme.visual.noteMouseOver = themeColor(value)
        case "VKMOUSEOVERE ": theme.visual.noteMouseOverEnd = themeColor(value)
        case "VKSELECTED": theme.visual.noteSelected = themeColor(value)
        case "KLENGTH":
            applyColumns(split26(value), to: &theme) { column, part in column.width = intValue(part) }
        case "KTITLE":
            applyColumns(split26(value), to: &theme) { column, part in column.title = part }
        case "KCOLOR":
            applyColumns(split26(value), to: &theme) { column, part in column.noteColor = themeColor(part) }
        case "KCOLORL":
            applyColumns(split26(value), to: &theme) { column, part in column.longNoteColor = themeColor(part) }
        case "KFORECOLOR":
            applyColumns(split26(value), to: &theme) { column, part in column.textColor = themeColor(part) }
        case "KFORECOLORL":
            applyColumns(split26(value), to: &theme) { column, part in column.longTextColor = themeColor(part) }
        case "KBGCOLOR":
            applyColumns(split26(value), to: &theme) { column, part in column.backgroundColor = themeColor(part) }
        default:
            break
        }
    }

    private static func applyColumns(_ parts: [String], to theme: inout ChartTheme, assign: (inout ThemeColumn, String) -> Void) {
        for index in 0...26 {
            guard let position = theme.columns.firstIndex(where: { $0.legacyIndex == index }) else { continue }
            assign(&theme.columns[position], parts[index])
        }
    }

    private static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func themeColor(_ text: String) -> ThemeColor {
        ThemeColor(signedARGB: int32Value(text))
    }

    private static func intValue(_ text: String) -> Int {
        let rounded = val(text).rounded(.toNearestOrEven)
        if rounded >= Double(Int.max) { return Int.max }
        if rounded <= Double(Int.min) { return Int.min }
        return Int(rounded)
    }

    private static func int32Value(_ text: String) -> Int32 {
        let rounded = val(text).rounded(.toNearestOrEven)
        if rounded >= Double(Int32.max) { return Int32.max }
        if rounded <= Double(Int32.min) { return Int32.min }
        return Int32(rounded)
    }

    /// VB `Val`: skip leading whitespace; optional sign; digits and one dot; stop at the first illegal character.
    private static func val(_ text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count && CharacterSet.whitespaces.contains(scalars[index]) {
            index += 1
        }
        guard index < scalars.count else { return 0 }
        var end = index
        if scalars[end] == "+" || scalars[end] == "-" { end += 1 }
        var sawDigit = false
        var sawDot = false
        while end < scalars.count {
            let value = scalars[end].value
            if value >= 48 && value <= 57 {
                sawDigit = true
                end += 1
                continue
            }
            if scalars[end] == "." && !sawDot {
                sawDot = true
                end += 1
                continue
            }
            break
        }
        if !sawDigit { return 0 }
        return Double(String(String.UnicodeScalarView(scalars[index..<end]))) ?? 0
    }
}
