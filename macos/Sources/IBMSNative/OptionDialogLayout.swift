import AppKit
import Foundation

enum OptionDialogColor {
    static let rule = ThemeColor(argb: 0xFF40_4040)
    static let invalidField = ThemeColor(argb: 0xFFFF_C0C0)

    static func hexARGB(_ color: ThemeColor) -> String {
        String(format: "%08X", color.argb)
    }

    /// `Color.GetBrightness` is `(max+min)/2` in 0...1. The original caption
    /// picks black when `brightness * 255 + 255 - A >= 128`.
    static func contrastingText(_ color: ThemeColor) -> ThemeColor {
        let red = Double(color.red)
        let green = Double(color.green)
        let blue = Double(color.blue)
        let brightness = (max(red, max(green, blue)) + min(red, min(green, blue))) / 2
        let lightCaption = brightness + 255 - Double(color.alpha) >= 128
        return ThemeColor(argb: lightCaption ? 0xFF00_0000 : 0xFFFF_FFFF)
    }

    static func themeColor(from nsColor: NSColor) -> ThemeColor {
        let converted = nsColor.usingColorSpace(.deviceRGB)
            ?? NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: nsColor.alphaComponent)
        func channel(_ value: CGFloat) -> UInt8 {
            UInt8(clamping: Int((Double(value) * 255).rounded(.toNearestOrEven)))
        }
        return ThemeColor(argb:
            (UInt32(channel(converted.alphaComponent)) << 24)
            | (UInt32(channel(converted.redComponent)) << 16)
            | (UInt32(channel(converted.greenComponent)) << 8)
            | UInt32(channel(converted.blueComponent))
        )
    }
}

extension ThemeFont {
    var nsFont: NSFont {
        let size = CGFloat(pointSize)
        let base = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        var traits = base.fontDescriptor.symbolicTraits
        if style & 1 != 0 { traits.insert(.bold) }
        if style & 2 != 0 { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    init(nsFont: NSFont) {
        name = nsFont.familyName ?? nsFont.fontName
        pointSize = Double(nsFont.pointSize)
        let traits = nsFont.fontDescriptor.symbolicTraits
        var style = 0
        if traits.contains(.bold) { style |= 1 }
        if traits.contains(.italic) { style |= 2 }
        self.style = style
    }
}

enum VisualOptionsLayout {
    static let clientSize = CGSize(width: 1026, height: 713)
    static let divider = CGRect(x: 10, y: 259, width: 1000, height: 1)
    static let columnPanel = CGRect(x: 10, y: 263, width: 1004, height: 402)
    static let ok = CGRect(x: 871, y: 675, width: 67, height: 23)
    static let cancel = CGRect(x: 944, y: 675, width: 67, height: 23)

    static let noteHeightRange = 0...100
    static let labelShiftRange = (-100)...100
    static let hiddenOpacityRange = 0.0...1.0
    static let timeSelectionSensitivityRange = 0...20
    static let middleSensitivityRange = 0...1_000_000
    static let columnWidthRange = 0...999

    /// Runtime `lLeft` in `OpVisual.vb`, one slot per `column[0...27]`.
    static let columnLefts: [Int] = [
        78, 110, 142, 174, 208, 240, 272, 304, 336, 368, 400, 432, 464, 498,
        530, 562, 594, 626, 658, 690, 722, 754, 788, 820, 852, 884, 918, 950
    ]

    static let columnRowHeaders: [(title: String, frame: CGRect)] = [
        ("Width", CGRect(x: 12, y: 15, width: 60, height: 15)),
        ("Caption", CGRect(x: 12, y: 37, width: 60, height: 15)),
        ("Note", CGRect(x: 12, y: 63, width: 60, height: 66)),
        ("Label", CGRect(x: 12, y: 128, width: 60, height: 66)),
        ("Long\nNote", CGRect(x: 12, y: 193, width: 60, height: 66)),
        ("Long\nNote\nLabel", CGRect(x: 12, y: 258, width: 60, height: 66)),
        ("Bg", CGRect(x: 12, y: 324, width: 60, height: 65))
    ]

    static let globalRows: [LabeledControl] = [
        LabeledControl(title: "Column Caption", label: CGRect(x: 42, y: 20, width: 160, height: 15), control: CGRect(x: 204, y: 16, width: 80, height: 23)),
        LabeledControl(title: "Column Caption Font", label: CGRect(x: 42, y: 42, width: 160, height: 15), control: CGRect(x: 204, y: 38, width: 80, height: 23)),
        LabeledControl(title: "Background", label: CGRect(x: 42, y: 64, width: 160, height: 15), control: CGRect(x: 204, y: 60, width: 80, height: 23)),
        LabeledControl(title: "Grid", label: CGRect(x: 42, y: 93, width: 160, height: 15), control: CGRect(x: 204, y: 89, width: 80, height: 23)),
        LabeledControl(title: "Sub", label: CGRect(x: 42, y: 115, width: 160, height: 15), control: CGRect(x: 204, y: 111, width: 80, height: 23)),
        LabeledControl(title: "Vertical Line", label: CGRect(x: 42, y: 137, width: 160, height: 15), control: CGRect(x: 204, y: 133, width: 80, height: 23)),
        LabeledControl(title: "Measure BarLine", label: CGRect(x: 42, y: 159, width: 160, height: 15), control: CGRect(x: 204, y: 155, width: 80, height: 23)),
        LabeledControl(title: "BGM Waveform", label: CGRect(x: 42, y: 181, width: 160, height: 15), control: CGRect(x: 204, y: 177, width: 80, height: 23)),
        LabeledControl(title: "Note Height", label: CGRect(x: 315, y: 20, width: 220, height: 15), control: CGRect(x: 537, y: 16, width: 80, height: 23)),
        LabeledControl(title: "Note Label", label: CGRect(x: 315, y: 42, width: 220, height: 15), control: CGRect(x: 537, y: 38, width: 80, height: 23)),
        LabeledControl(title: "Measure Label", label: CGRect(x: 315, y: 64, width: 220, height: 15), control: CGRect(x: 537, y: 60, width: 80, height: 23)),
        LabeledControl(title: "Note Label Vertical Shift", label: CGRect(x: 315, y: 86, width: 220, height: 15), control: CGRect(x: 537, y: 82, width: 80, height: 23)),
        LabeledControl(title: "Note Label Horizontal Shift", label: CGRect(x: 315, y: 108, width: 220, height: 15), control: CGRect(x: 537, y: 104, width: 80, height: 23)),
        LabeledControl(title: "LongNote Label Horizontal Shift", label: CGRect(x: 315, y: 130, width: 220, height: 15), control: CGRect(x: 537, y: 126, width: 80, height: 23)),
        LabeledControl(title: "Hidden Note Opacity", label: CGRect(x: 315, y: 152, width: 220, height: 15), control: CGRect(x: 537, y: 148, width: 80, height: 23)),
        LabeledControl(title: "Note Border on MouseOver", label: CGRect(x: 315, y: 181, width: 220, height: 15), control: CGRect(x: 537, y: 177, width: 80, height: 23)),
        LabeledControl(title: "Note Border on Selection", label: CGRect(x: 315, y: 203, width: 220, height: 15), control: CGRect(x: 537, y: 199, width: 80, height: 23)),
        LabeledControl(title: "Note Border on Adjusting Length", label: CGRect(x: 315, y: 225, width: 220, height: 15), control: CGRect(x: 537, y: 221, width: 80, height: 23)),
        LabeledControl(title: "Selection Box Border", label: CGRect(x: 648, y: 20, width: 220, height: 15), control: CGRect(x: 870, y: 16, width: 80, height: 23)),
        LabeledControl(title: "Time Selection Cursor", label: CGRect(x: 648, y: 42, width: 220, height: 15), control: CGRect(x: 870, y: 38, width: 80, height: 23)),
        LabeledControl(title: "Time Selection Splitter", label: CGRect(x: 648, y: 64, width: 220, height: 15), control: CGRect(x: 870, y: 60, width: 80, height: 23)),
        LabeledControl(title: "Time Selection Cursor Sensitivity", label: CGRect(x: 648, y: 86, width: 220, height: 15), control: CGRect(x: 870, y: 82, width: 80, height: 23)),
        LabeledControl(title: "Time Selection MouseOver Border", label: CGRect(x: 648, y: 108, width: 220, height: 15), control: CGRect(x: 870, y: 104, width: 80, height: 23)),
        LabeledControl(title: "Time Selection Fill", label: CGRect(x: 648, y: 130, width: 220, height: 15), control: CGRect(x: 870, y: 126, width: 80, height: 23)),
        LabeledControl(title: "Time Selection BPM", label: CGRect(x: 648, y: 152, width: 220, height: 15), control: CGRect(x: 870, y: 148, width: 80, height: 23)),
        LabeledControl(title: "Time Selection BPM Font", label: CGRect(x: 648, y: 174, width: 220, height: 15), control: CGRect(x: 870, y: 170, width: 80, height: 23)),
        LabeledControl(title: "Middle Button Release Sensitivity", label: CGRect(x: 648, y: 203, width: 220, height: 15), control: CGRect(x: 870, y: 199, width: 80, height: 23))
    ]

    struct LabeledControl {
        let title: String
        let label: CGRect
        let control: CGRect
    }

    enum ColumnRow: Int {
        case width = 0
        case title
        case shortNote
        case shortLabel
        case longNote
        case longLabel
        case background

        var originY: CGFloat {
            switch self {
            case .width: return 12
            case .title: return 34
            case .shortNote: return 63
            case .shortLabel: return 128
            case .longNote: return 193
            case .longLabel: return 258
            case .background: return 323
            }
        }

        var size: CGSize {
            switch self {
            case .width, .title: return CGSize(width: 33, height: 23)
            default: return CGSize(width: 33, height: 66)
            }
        }
    }

    static func columnFrame(index: Int, row: ColumnRow) -> CGRect {
        precondition((0..<columnLefts.count).contains(index), "legacy column index is 0...27")
        let size = row.size
        return CGRect(x: CGFloat(columnLefts[index]), y: row.originY, width: size.width, height: size.height)
    }

    static func clampNoteHeight(_ value: Int) -> Int {
        min(noteHeightRange.upperBound, max(noteHeightRange.lowerBound, value))
    }

    static func clampLabelShift(_ value: Int) -> Int {
        min(labelShiftRange.upperBound, max(labelShiftRange.lowerBound, value))
    }

    static func clampHiddenOpacity(_ value: Double) -> Double {
        min(hiddenOpacityRange.upperBound, max(hiddenOpacityRange.lowerBound, value))
    }
}

enum GeneralOptionsLayout {
    static let clientSize = CGSize(width: 413, height: 510)
    static let divider = CGRect(x: 20, y: 253, width: 375, height: 1)
    static let ok = CGRect(x: 232, y: 466, width: 78, height: 27)
    static let cancel = CGRect(x: 317, y: 466, width: 78, height: 27)

    static let encodingLabel = CGRect(x: -5, y: 20, width: 136, height: 17)
    static let encoding = CGRect(x: 137, y: 18, width: 254, height: 23)
    static let associateLabel = CGRect(x: -5, y: 50, width: 136, height: 17)
    static let associateBMS = CGRect(x: 137, y: 47, width: 122, height: 23)
    static let associateIBMSC = CGRect(x: 265, y: 47, width: 127, height: 23)
    static let associateBME = CGRect(x: 137, y: 78, width: 76, height: 23)
    static let associateBML = CGRect(x: 219, y: 78, width: 85, height: 23)
    static let associatePMS = CGRect(x: 310, y: 78, width: 81, height: 23)
    static let gridPartitionLabel = CGRect(x: 44, y: 108, width: 169, height: 17)
    static let gridPartition = CGRect(x: 219, y: 107, width: 79, height: 23)
    static let autoSave = CGRect(x: 32, y: 144, width: 76, height: 19)
    static let autoSaveMinutes = CGRect(x: 171, y: 142, width: 62, height: 23)
    static let minutesLabel = CGRect(x: 239, y: 144, width: 73, height: 17)
    static let beep = CGRect(x: 32, y: 169, width: 116, height: 19)
    static let bpm1296 = CGRect(x: 32, y: 194, width: 253, height: 19)
    static let stop1296 = CGRect(x: 32, y: 219, width: 198, height: 19)
    static let wheelLabel = CGRect(x: 12, y: 271, width: 136, height: 17)
    static let wheel = CGRect(x: 154, y: 269, width: 237, height: 23)
    static let pageLabel = CGRect(x: 12, y: 300, width: 136, height: 17)
    static let page = CGRect(x: 154, y: 298, width: 237, height: 23)
    static let middleLabel = CGRect(x: 12, y: 328, width: 136, height: 17)
    static let middleAuto = CGRect(x: 157, y: 327, width: 135, height: 19)
    static let middleDrag = CGRect(x: 157, y: 346, width: 102, height: 19)
    static let mouseEnterFocus = CGRect(x: 34, y: 379, width: 322, height: 19)
    static let firstClickDisabled = CGRect(x: 34, y: 404, width: 293, height: 19)
    static let stopPreview = CGRect(x: 34, y: 429, width: 253, height: 19)

    static let encodingTitles = [
        "ANSI (Locale dependant)",
        "Little Endian UTF16",
        "ASCII",
        "Big Endian UTF16",
        "Little Endian UTF32",
        "UTF7",
        "UTF8",
        "Shift-JIS",
        "EUC-KR"
    ]
    static let wheelTitles = ["1", "1 / 2", "1 / 3", "1 / 4"]
    static let wheelValues = [192, 96, 64, 48]
    static let pageTitles = ["8", "6", "4", "3", "2", "1", "1 / 2"]
    static let pageValues = [1536, 1152, 768, 576, 384, 192, 96]
    static let gridPartitionRange = 8...10_000
    static let autoSaveMinuteRange = 1.0...60.0

    static func wheelIndex(for value: Int) -> Int {
        wheelValues.firstIndex(of: value) ?? 1
    }

    static func pageIndex(for value: Int) -> Int {
        pageValues.firstIndex(of: value) ?? 4
    }

    static func wheelValue(at index: Int) -> Int {
        guard wheelValues.indices.contains(index) else { return 96 }
        return wheelValues[index]
    }

    static func pageValue(at index: Int) -> Int {
        guard pageValues.indices.contains(index) else { return 384 }
        return pageValues[index]
    }

    static func autoSaveMilliseconds(enabled: Bool, minutes: Double) -> Int {
        guard enabled else { return 0 }
        let clamped = min(autoSaveMinuteRange.upperBound, max(autoSaveMinuteRange.lowerBound, minutes))
        return Int((clamped * 60_000).rounded(.toNearestOrEven))
    }

    /// Mirrors `OpGeneral.New`: out-of-range intervals only uncheck AutoSave
    /// and leave the minutes box at its Designer default of 2.
    static func autoSaveDisplay(milliseconds: Int) -> (enabled: Bool, minutes: Double) {
        let minutes = Double(milliseconds) / 60_000
        if minutes < autoSaveMinuteRange.lowerBound || minutes > autoSaveMinuteRange.upperBound {
            return (false, 2)
        }
        return (true, minutes)
    }
}

enum PlayerOptionsLayout {
    static let clientSize = CGSize(width: 382, height: 351)
    static let currentPlayerLabel = CGRect(x: 12, y: 9, width: 85, height: 15)
    static let playerList = CGRect(x: 12, y: 27, width: 225, height: 55)
    static let add = CGRect(x: 243, y: 12, width: 117, height: 23)
    static let remove = CGRect(x: 243, y: 41, width: 117, height: 23)
    static let pathLabel = CGRect(x: 0, y: 101, width: 45, height: 15)
    static let path = CGRect(x: 51, y: 98, width: 288, height: 23)
    static let browse = CGRect(x: 345, y: 98, width: 24, height: 23)
    static let argumentsLabel = CGRect(x: 12, y: 126, width: 66, height: 15)
    static let divider = CGRect(x: 12, y: 134, width: 357, height: 1)
    static let playFromBeginningLabel = CGRect(x: 14, y: 153, width: 157, height: 15)
    static let playFromBeginning = CGRect(x: 177, y: 150, width: 192, height: 23)
    static let playFromMeasureLabel = CGRect(x: 14, y: 182, width: 157, height: 15)
    static let playFromMeasure = CGRect(x: 177, y: 179, width: 192, height: 23)
    static let stopLabel = CGRect(x: 14, y: 211, width: 157, height: 15)
    static let stop = CGRect(x: 177, y: 208, width: 192, height: 23)
    static let references = CGRect(x: 14, y: 244, width: 225, height: 60)
    static let ok = CGRect(x: 72, y: 316, width: 78, height: 23)
    static let cancel = CGRect(x: 156, y: 316, width: 78, height: 23)
    static let restoreDefault = CGRect(x: 240, y: 316, width: 130, height: 23)

    static let referencesText = """
    References (case-sensitive):
    <apppath> = Directory of the application
    <measure> = Current measure
    <filename> = File Name
    """

    static func fileName(from path: String) -> String {
        let slash = path.lastIndex(of: "/")
        let backslash = path.lastIndex(of: "\\")
        guard let cut = [slash, backslash].compactMap({ $0 }).max() else { return path }
        return String(path[path.index(after: cut)...])
    }

    static func hasInvalidPathCharacters(_ text: String) -> Bool {
        var cleaned = text
        for token in ["<apppath>", "<measure>", "<filename>", "\""] {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned.unicodeScalars.contains { invalidPathCharacters.contains($0) }
    }

    /// `OpPlayer.BAdd`: insert a copy of the current row immediately after it.
    static func insertingCopy(players: [PlayerArguments], currentIndex: Int) -> (players: [PlayerArguments], currentIndex: Int)? {
        guard players.indices.contains(currentIndex) else { return nil }
        var next = players
        let inserted = currentIndex + 1
        next.insert(players[currentIndex], at: inserted)
        return (next, inserted)
    }

    /// `OpPlayer.BRemove`: the last remaining player cannot be deleted.
    static func removing(players: [PlayerArguments], currentIndex: Int) -> (players: [PlayerArguments], currentIndex: Int)? {
        guard players.count > 1, players.indices.contains(currentIndex) else { return nil }
        var next = players
        next.remove(at: currentIndex)
        return (next, min(currentIndex, next.count - 1))
    }

    private static let invalidPathCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "\"<>|")
        if let low = UnicodeScalar(0), let high = UnicodeScalar(31) {
            set.insert(charactersIn: low...high)
        }
        return set
    }()
}
