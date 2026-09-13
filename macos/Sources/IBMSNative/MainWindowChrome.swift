import CoreGraphics
import Foundation

/// Client-area geometry taken from `MainWindow.designer.vb` and the Form_Load defaults
/// in `MainWindow.vb` (`POHeaderPart2` / `POGridPart2` / `POWaveFormPart2` start hidden).
enum MainWindowChrome {
    static let clientSize = CGSize(width: 1082, height: 730)
    static let optionsScrollWidth: CGFloat = 200
    static let optionsDocumentWidth: CGFloat = 183
    static let resizerWidth: CGFloat = 6
    static let toolbarHeight: CGFloat = 25
    static let statusHeight: CGFloat = 22
    static let scrollbarSize: CGFloat = 17
    static let editorWidth: CGFloat = 866
    static let editorHeight: CGFloat = 660
    static let sectionSwitchHeight: CGFloat = 20
    static let expanderHeight: CGFloat = 25
    static let headerPart1Height: CGFloat = 161
    static let headerPart2Height: CGFloat = 233
    static let gridPart1Height: CGFloat = 127
    static let gridPart2Height: CGFloat = 58
    static let waveformPart1Height: CGFloat = 58
    static let waveformPart2Height: CGFloat = 140
    static let listToolbarHeight: CGFloat = 30
    static let listPart2Height: CGFloat = 38
    static let beatPart1Height: CGFloat = 54
    static let beatPart2Height: CGFloat = 76
    static let listBoxHeight: CGFloat = 152
    static let expansionBoxHeight: CGFloat = 245
    static let listResizerHeight: CGFloat = 5
    static let headerFieldHeight: CGFloat = 23
    static let headerPart1FieldX: CGFloat = 65
    static let headerPart1FieldWidth: CGFloat = 118
    static let headerPart2FieldX: CGFloat = 67
    static let headerPart2FieldWidth: CGFloat = 116
    static let headerPart2BrowseWidth: CGFloat = 25
    static let segoeUINinePointPixels: CGFloat = 12
    static let defaultPixelsPerQuarterBeat: CGFloat = 48
    static let defaultGridHeight: CGFloat = 1
    static let defaultGridWidth: CGFloat = 1
    static let defaultDivision = 16
    static let defaultSubDivision = 4
    static let wavTokenCount = 1295

    /// `AssemblyInfo.vb` `AssemblyTitle`：希腊字母 μ（U+03BC），不是微符号 U+00B5。
    static let appTitle = "\u{03BC}BMSC Editor"
    static let untitledBMSFileName = "Untitled.bms"
    static let untitledBMSONFileName = "Untitled.bmson"
    static let assemblyMajor = 3
    static let assemblyMinor = 2
    static let assemblyBuild = 1

    /// `MainWindow.vb` `xVersion`：`Major.Minor`，`Build != 0` 再加 `.Build`。不写 Revision。
    static func versionText(major: Int, minor: Int, build: Int) -> String {
        if build != 0 {
            return "\(major).\(minor).\(build)"
        }
        return "\(major).\(minor)"
    }

    /// `GetFileName`：最后一个 `/` 或 `\` 后面的一段。没有斜杠就整串。空路径用未命名默认名。
    static func fileTitle(_ path: String, untitled: String = untitledBMSFileName) -> String {
        if path.isEmpty { return untitled }
        if let index = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            return String(path[path.index(after: index)...])
        }
        return path
    }

    /// `SetIsSaved`：`IIf(isSaved, "", "*") & GetFileName(FileName) & " - " & Title & " " & xVersion`
    static func windowTitle(
        fileName: String,
        isSaved: Bool,
        untitled: String = untitledBMSFileName
    ) -> String {
        let mark = isSaved ? "" : "*"
        let name = fileTitle(fileName, untitled: untitled)
        let version = versionText(major: assemblyMajor, minor: assemblyMinor, build: assemblyBuild)
        return "\(mark)\(name) - \(appTitle) \(version)"
    }

    /// `Strings.vb` `SaveOnExit`。File → New / Open、关主窗、普通退出都用这一句。
    static let saveOnExitPrompt = "Do you want to save changes?"
    /// `Strings.vb` `SaveOnExit1`。只有能明确判断是关机时才用。
    static let saveOnExitPromptShutdown =
        "You should tell me if you want to save changes before closing the computer. -_,-"
    /// `Strings.vb` `SaveOnExit2`。不要拿来冒充普通退出。
    static let saveOnExitPromptTaskManager =
        "You still need to tell me if you want to save changes even though you are closing the application with task manager. -_,-"
    /// `MsgBoxStyle.YesNoCancel` 三个按钮，不要写成 Save / Don't Save。
    static let saveOnExitYes = "Yes"
    static let saveOnExitNo = "No"
    static let saveOnExitCancel = "Cancel"

    /// 对照 `ClosingPopSave` / `Form1_FormClosing`：干净不问；脏了按 Yes / No / Cancel。
    static func saveOnExitDecision(isSaved: Bool, choice: SaveOnExitChoice) -> SaveOnExitDecision {
        if isSaved { return .proceedClean }
        switch choice {
        case .yes: return .proceedSave
        case .no: return .proceedDiscard
        case .cancel: return .abort
        }
    }

    /// 能明确判断是关机才换第二句；判断不了仍用第一句。不要用第三句冒充普通退出。
    static func saveOnExitMessage(isSystemShutdown: Bool) -> String {
        isSystemShutdown ? saveOnExitPromptShutdown : saveOnExitPrompt
    }

    static let statusFields: [StatusFieldLayout] = [
        StatusFieldLayout(name: "FSC", width: 70, text: "BPM", tooltip: "Column Caption", color: .label, bold: false),
        StatusFieldLayout(name: "FSW", width: 40, text: "01", tooltip: "Note Index", color: .noteIndex, bold: false),
        StatusFieldLayout(name: "FSM", width: 40, text: "000", tooltip: "Measure Index", color: .teal, bold: false),
        StatusFieldLayout(name: "FSP1", width: 170, text: "9.41176470588235 / 9999", tooltip: "Grid Resolution", color: .label, bold: true),
        StatusFieldLayout(name: "FSP3", width: 85, text: "9999 / 9999", tooltip: "Reduced Resolution", color: .maroon, bold: true),
        StatusFieldLayout(name: "FSP2", width: 170, text: "112.941176470588 / 9999", tooltip: "Measure Resolution", color: .green, bold: true),
        StatusFieldLayout(name: "FSP4", width: 115, text: "112.941176470588", tooltip: "Absolute Position", color: .label, bold: false),
        StatusFieldLayout(name: "TimeStatusLabel", width: 55, text: "00:00:000", tooltip: "", color: .label, bold: false),
        StatusFieldLayout(name: "FST", width: 64, text: "Length = 0", tooltip: "", color: .olive, bold: false),
        StatusFieldLayout(name: "FSH", width: 46, text: "Hidden", tooltip: "", color: .blue, bold: false),
        StatusFieldLayout(name: "FSE", width: 32, text: "Error", tooltip: "", color: .red, bold: false)
    ]

    static let headerPart1Rows: [HeaderFieldLayout] = [
        HeaderFieldLayout(key: "TITLE", label: "Title", kind: .text, enabled: true),
        HeaderFieldLayout(key: "ARTIST", label: "Artist", kind: .text, enabled: true),
        HeaderFieldLayout(key: "GENRE", label: "Genre", kind: .text, enabled: true),
        HeaderFieldLayout(key: "BPM", label: "BPM", kind: .bpm, enabled: true),
        HeaderFieldLayout(key: "PLAYER", label: "Player", kind: .popup(["1 - Single Play", "2 - Couple Play", "3 - Double Play"]), enabled: true),
        HeaderFieldLayout(key: "RANK", label: "Rank", kind: .popup(["0 - Very Hard", "1 - Hard", "2 - Normal", "3 - Easy", "4 - Very Easy"]), enabled: true),
        HeaderFieldLayout(key: "PLAYLEVEL", label: "Play Level", kind: .text, enabled: true)
    ]

    static let headerPart2Rows: [HeaderFieldLayout] = [
        HeaderFieldLayout(key: "SUBTITLE", label: "SubTitle", kind: .text, enabled: true),
        HeaderFieldLayout(key: "SUBARTIST", label: "SubArtist", kind: .text, enabled: true),
        HeaderFieldLayout(key: "STAGEFILE", label: "Stage File", kind: .browse, enabled: true),
        HeaderFieldLayout(key: "BANNER", label: "Banner", kind: .browse, enabled: true),
        HeaderFieldLayout(key: "BACKBMP", label: "Back BMP", kind: .browse, enabled: true),
        HeaderFieldLayout(key: "DIFFICULTY", label: "Difficulty", kind: .popup([
            "None", "1 - EZ / Beginner", "2 - NM / Normal", "3 - HD / Hyper", "4 - MX / Another", "5 - SC / Insane"
        ]), enabled: true),
        HeaderFieldLayout(key: "EXRANK", label: "ExRank", kind: .percent, enabled: true),
        HeaderFieldLayout(key: "TOTAL", label: "Total", kind: .percent, enabled: true),
        HeaderFieldLayout(key: "COMMENT", label: "Comment", kind: .text, enabled: true),
        HeaderFieldLayout(key: "LNOBJ", label: "LnObj", kind: .lnobj, enabled: true)
    ]

    static var statusFieldTotalWidth: CGFloat {
        statusFields.reduce(0) { $0 + $1.width }
    }

    static func pixelsPerQuarterBeat(gridHeight: CGFloat) -> CGFloat {
        defaultPixelsPerQuarterBeat * gridHeight
    }
}

struct StatusFieldLayout: Equatable {
    enum ColorToken: Equatable {
        case label
        case noteIndex
        case teal
        case maroon
        case green
        case olive
        case blue
        case red
    }

    let name: String
    let width: CGFloat
    let text: String
    let tooltip: String
    let color: ColorToken
    let bold: Bool
}

struct HeaderFieldLayout: Equatable {
    enum Kind: Equatable {
        case text
        case bpm
        case browse
        case percent
        case popup([String])
        case lnobj
    }

    let key: String
    let label: String
    let kind: Kind
    let enabled: Bool
}

enum SaveOnExitChoice: Equatable {
    case yes
    case no
    case cancel
}

enum SaveOnExitDecision: Equatable {
    case proceedSave
    case proceedDiscard
    case abort
    case proceedClean
}

/// µBMSC `POStatusRefresh` / `GetTimeFromVPosition` / `GCD`。只给打开 BMS 时的普通底栏用。
enum LegacyStatus {
    /// 可选覆盖。不传就用 Designer 英文，这样 Chrome 夹具不用编 Locale。
    struct Labels: Equatable {
        var length: String
        var longNote: String
        var hidden: String
        var error: String

        static let english = Labels(length: "Length", longNote: "LongNote", hidden: "Hidden", error: "Error")

        var lengthPrefix: String { "\(length) = " }
    }

    static let lengthPrefix = Labels.english.lengthPrefix
    static let longNoteText = Labels.english.longNote
    static let hiddenLabel = Labels.english.hidden
    static let errorLabel = Labels.english.error
    static let defaultGridLimit = 1.0
    static let defaultMeasureLength = 192.0
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    struct TimingNote: Equatable {
        var vPosition: Double
        var value: Double
    }

    struct HoverNote: Equatable {
        var vPosition: Double
        var columnTitle: String
        var value: Double
        var length: Double
        var hidden: Bool
        var hasError: Bool
        var numeric: Bool
        var longNote: Bool
    }

    struct Fields: Equatable {
        var fsc: String
        var fsw: String
        var fsm: String
        var fsp1: String
        var fsp2: String
        var fsp3: String
        var fsp4: String
        var time: String
        var fst: String
        var fsh: String
        var fse: String
    }

    static func headerBPMNote(_ bpm: Double) -> TimingNote {
        TimingNote(vPosition: 0, value: bpm * 10_000)
    }

    /// VB `Double.ToString`：整数不带小数点，小数点固定是 `.`。
    static func vbDouble(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value.rounded()))
        }
        return String(value)
    }

    static func pair(_ left: Double, _ right: Double) -> String {
        "\(vbDouble(left)) / \(vbDouble(right))  "
    }

    static func absolute(_ vPosition: Double) -> String {
        "\(vbDouble(vPosition))  "
    }

    static func timeF4(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? seconds : 0
        var text = String(format: "%.4f", safe)
        if text.contains(",") {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        return text
    }

    /// `Utilities.Add3Zeros`：只留最后三位。
    static func add3Zeros(_ measure: Int) -> String {
        let text = "000\(measure)"
        return String(text.suffix(3))
    }

    /// `MainWindow.vb` `GCD`。默认 `BMSGridLimit = 1.0`。
    static func gcd(_ first: Double, _ second: Double, limit: Double = defaultGridLimit) -> Double {
        var xNMax = first
        var xNMin = second
        if first < second {
            xNMax = second
            xNMin = first
        }
        while xNMin >= limit {
            let remainder = xNMax - floor(xNMax / xNMin) * xNMin
            xNMax = xNMin
            xNMin = remainder
        }
        return xNMax
    }

    static func gridPair(vposMod: Double, measureLength: Double, divide: Double = 16) -> String {
        pair(vposMod * divide / 192, measureLength * divide / 192)
    }

    static func measurePair(vposMod: Double, measureLength: Double) -> String {
        pair(vposMod, measureLength)
    }

    /// 约分用 GCD 的那个输入：小节起点 `vposMod = 0` 时改用小节长，这样 `0` 是 `1 / 1`。
    static func reducedPair(
        vposMod: Double,
        measureLength: Double,
        limit: Double = defaultGridLimit
    ) -> String {
        let gcdInput = vposMod == 0 ? measureLength : vposMod
        let divisor = gcd(gcdInput, measureLength, limit: limit)
        return pair(Double(vbCInt(gcdInput / divisor)), Double(vbCInt(measureLength / divisor)))
    }

    static func location(
        vposMod: Double,
        measureLength: Double,
        vPosition: Double,
        measureIndex: Int,
        divide: Double = 16,
        limit: Double = defaultGridLimit
    ) -> (fsp1: String, fsp2: String, fsp3: String, fsp4: String, fsm: String) {
        (
            gridPair(vposMod: vposMod, measureLength: measureLength, divide: divide),
            measurePair(vposMod: vposMod, measureLength: measureLength),
            reducedPair(vposMod: vposMod, measureLength: measureLength, limit: limit),
            absolute(vPosition),
            add3Zeros(measureIndex)
        )
    }

    /// 只看 BPM / STOP。头 BPM 当成 vpos `0`。`value` 是原版 `Value`（BPM `120` 是 `1200000`）。
    static func timeFromVPosition(
        _ vpos: Double,
        bpmNotes: [TimingNote],
        stopNotes: [TimingNote] = []
    ) -> Double {
        var bpm_contrib = 0.0
        var stop_contrib = 0.0
        let bpm = bpmNotes
        guard !bpm.isEmpty else { return 0 }
        for index in bpm.indices {
            let current = bpm[index]
            let notevpos = max(0, current.vPosition)
            let duration: Double
            if index + 1 != bpm.count {
                duration = bpm[index + 1].vPosition - notevpos
            } else {
                duration = vpos - notevpos
            }
            let current_bps = 60 / (current.value / 10_000)
            bpm_contrib += current_bps * duration / 48
            let stop_beats = stopNotes
                .filter { $0.vPosition >= notevpos && $0.vPosition < notevpos + duration }
                .reduce(0.0) { $0 + $1.value / 10_000 } / 48
            stop_contrib += current_bps * stop_beats
        }
        return stop_contrib + bpm_contrib
    }

    static func encode36(_ value: Int) -> String {
        let clamped = min(1_295, max(1, value))
        return String([digits[clamped / 36], digits[clamped % 36]])
    }

    static func labelFSW(value: Double, numeric: Bool) -> String {
        if numeric {
            return vbDouble(value / 10_000)
        }
        return encode36(Int(value / 10_000))
    }

    static func writeFSW(slot: Int) -> String {
        encode36(slot + 1)
    }

    static func selectFST(
        ntInput: Bool,
        length: Double,
        longNote: Bool,
        labels: Labels = .english
    ) -> String {
        if ntInput {
            return "\(labels.lengthPrefix)\(vbDouble(length))"
        }
        return longNote ? labels.longNote : ""
    }

    static func writeFST(
        ntInput: Bool,
        tempLength: Double,
        shift: Bool,
        labels: Labels = .english
    ) -> String {
        if ntInput {
            return vbDouble(tempLength)
        }
        return shift ? labels.longNote : ""
    }

    static func hiddenText(_ hidden: Bool, labels: Labels = .english) -> String {
        hidden ? labels.hidden : ""
    }

    static func errorText(_ hasError: Bool, labels: Labels = .english) -> String {
        hasError ? labels.error : ""
    }

    static func selectFields(
        mouseVPosition: Double,
        vposMod: Double,
        measureLength: Double,
        measureIndex: Int,
        columnTitle: String,
        divide: Double = 16,
        hover: HoverNote? = nil,
        ntInput: Bool = true,
        bpmNotes: [TimingNote] = [headerBPMNote(120)],
        stopNotes: [TimingNote] = [],
        labels: Labels = .english
    ) -> Fields {
        let loc = location(
            vposMod: vposMod,
            measureLength: measureLength,
            vPosition: hover?.vPosition ?? mouseVPosition,
            measureIndex: measureIndex,
            divide: divide
        )
        let time = timeF4(timeFromVPosition(mouseVPosition, bpmNotes: bpmNotes, stopNotes: stopNotes))
        if let hover {
            return Fields(
                fsc: hover.columnTitle,
                fsw: labelFSW(value: hover.value, numeric: hover.numeric),
                fsm: loc.fsm,
                fsp1: loc.fsp1,
                fsp2: loc.fsp2,
                fsp3: loc.fsp3,
                fsp4: loc.fsp4,
                time: time,
                fst: selectFST(ntInput: ntInput, length: hover.length, longNote: hover.longNote, labels: labels),
                fsh: hiddenText(hover.hidden, labels: labels),
                fse: errorText(hover.hasError, labels: labels)
            )
        }
        return Fields(
            fsc: columnTitle,
            fsw: "",
            fsm: loc.fsm,
            fsp1: loc.fsp1,
            fsp2: loc.fsp2,
            fsp3: loc.fsp3,
            fsp4: loc.fsp4,
            time: time,
            fst: "",
            fsh: "",
            fse: ""
        )
    }

    static func writeFields(
        mouseVPosition: Double,
        vposMod: Double,
        measureLength: Double,
        measureIndex: Int,
        columnTitle: String,
        slot: Int,
        tempLength: Double,
        ntInput: Bool,
        shift: Bool,
        control: Bool,
        divide: Double = 16,
        bpmNotes: [TimingNote] = [headerBPMNote(120)],
        stopNotes: [TimingNote] = [],
        labels: Labels = .english
    ) -> Fields {
        let loc = location(
            vposMod: vposMod,
            measureLength: measureLength,
            vPosition: mouseVPosition,
            measureIndex: measureIndex,
            divide: divide
        )
        return Fields(
            fsc: columnTitle,
            fsw: writeFSW(slot: slot),
            fsm: loc.fsm,
            fsp1: loc.fsp1,
            fsp2: loc.fsp2,
            fsp3: loc.fsp3,
            fsp4: loc.fsp4,
            time: timeF4(timeFromVPosition(mouseVPosition, bpmNotes: bpmNotes, stopNotes: stopNotes)),
            fst: writeFST(ntInput: ntInput, tempLength: tempLength, shift: shift, labels: labels),
            fsh: hiddenText(control, labels: labels),
            fse: ""
        )
    }

    private static func vbCInt(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }
}

enum LegacyHeaderFields {
    static func popupIndex(key: String, stored: String) -> Int {
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        if key == "RANK", trimmed.isEmpty { return 3 }
        if key == "LNOBJ" {
            let token = trimmed.uppercased()
            if token.isEmpty { return 0 }
            if let index = BMS36Token.all.firstIndex(of: token) {
                return index + 1
            }
            return 0
        }
        guard let value = Int(trimmed) else {
            return key == "PLAYER" ? 0 : 0
        }
        switch key {
        case "PLAYER":
            return (1...3).contains(value) ? value - 1 : 0
        case "RANK":
            return (0...4).contains(value) ? value : 3
        case "DIFFICULTY":
            return (0...5).contains(value) ? value : 0
        default:
            return 0
        }
    }

    static func storedValue(key: String, popupIndex: Int) -> String {
        switch key {
        case "PLAYER":
            return String(min(3, max(0, popupIndex)) + 1)
        case "LNOBJ":
            if popupIndex <= 0 { return "" }
            let tokenIndex = min(BMS36Token.all.count, popupIndex) - 1
            return BMS36Token.all[tokenIndex]
        case "RANK":
            return String(min(4, max(0, popupIndex)))
        case "DIFFICULTY":
            return String(min(5, max(0, popupIndex)))
        default:
            return ""
        }
    }
}

enum MainToolbarItemKind: Equatable {
    case button
    case split
    case separator
    case statistics
}

struct MainToolbarItem: Equatable {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let icon: String?
    let tooltip: String
    let kind: MainToolbarItemKind
    let checked: Bool
    let visible: Bool
}

enum MainToolbarLayout {
    static let height: CGFloat = 25
    static let itemTop: CGFloat = 1
    static let items: [MainToolbarItem] = [
        item("TBNew", 23, icon: "x16New", tip: "New (Ctrl+N)"),
        item("TBOpen", 32, icon: "x16Open", tip: "Open (Ctrl+O)", kind: .split),
        item("TBSave", 32, icon: "x16Save", tip: "Save (Ctrl+S)", kind: .split),
        separator("ToolStripSeparator1"),
        item("TBCut", 23, icon: "x16Cut", tip: "Cut (Ctrl+X)"),
        item("TBCopy", 23, icon: "x16Copy", tip: "Copy (Ctrl+C)"),
        item("TBPaste", 23, icon: "x16Paste", tip: "Paste (Ctrl+V)"),
        item("TBFind", 23, icon: "x16Find", tip: "Find / Delete / Replace (Ctrl+F)"),
        separator("ToolStripSeparator24"),
        item("TBStatistics", 34, icon: "x16Statistics", tip: "Statistics (Ctrl+T)", kind: .statistics),
        item("POConvert", 29, icon: "ConvertNotes", tip: "Convert Notes", kind: .split),
        item("TBMyO2", 23, icon: "x16MyO2", tip: "MyO2 ToolBox (Chinese Only)"),
        separator("ToolStripSeparator4"),
        item("TBErrorCheck", 23, icon: "x16CheckError", tip: "Error Check", checked: true),
        item("TBPreviewOnClick", 23, icon: "x16PreviewOnClick", tip: "Preview On Click", checked: true),
        item("TBShowFileName", 23, icon: "x16ShowFileNameN", tip: "Show File Name on Notes"),
        separator("ToolStripSeparator8"),
        item("TBNTInput", 23, icon: "x16NTInput", tip: "LongNote Input Style - NoteTool/BMSE", checked: true),
        item("TBWavIncrease", 23, icon: "x16WavIncrease", tip: "Autoincrease WAV when writing"),
        separator("ToolStripSeparator2"),
        item("TBUndo", 23, icon: "x16Undo", tip: "Undo (Ctrl+Z)"),
        item("TBRedo", 23, icon: "x16Redo", tip: "Redo (Ctrl+Y)"),
        separator("ToolStripSeparator5"),
        item("TBTimeSelect", 23, icon: "x16TimeSelection", tip: "Time Selection Tool (F1)"),
        item("TBSelect", 23, icon: "x16Select", tip: "Select Tool (F2)", checked: true),
        item("TBWrite", 23, icon: "x16Pen", tip: "Write Tool (F3)"),
        separator("ToolStripSeparator3"),
        item("TBPlayB", 23, icon: "x16PlayB", tip: "Play from beginning (F5)"),
        item("TBPlay", 23, icon: "x16Play", tip: "Play from here (F6)"),
        item("TBStop", 23, icon: "x16Stop", tip: "Stop (F7)"),
        item("TBPOptions", 23, icon: "x16PlayerOptions", tip: "Player Options"),
        separator("ToolStripSeparator7"),
        item("TBVOptions", 23, icon: "x16VisualOptions", tip: "Visual Options"),
        item("TBGOptions", 23, icon: "x16GeneralOptions", tip: "General Options"),
        item("TBLanguage", 29, icon: "x16Language", tip: "Language", kind: .split),
        item("TBTheme", 29, icon: "x16Theme", tip: "Theme", kind: .split),
        item("POBStorm", 23, icon: "x16Storm", tip: "Storm", visible: false)
    ]

    static var visibleItems: [MainToolbarItem] { items.filter(\.visible) }

    static var totalWidth: CGFloat {
        visibleItems.reduce(0) { $0 + $1.width }
    }

    static func frames() -> [(item: MainToolbarItem, frame: CGRect)] {
        var x: CGFloat = 0
        return visibleItems.map { item in
            let frame = CGRect(x: x, y: itemTop, width: item.width, height: item.height)
            x += item.width
            return (item, frame)
        }
    }

    static func frame(named name: String) -> CGRect? {
        frames().first { $0.item.name == name }?.frame
    }

    private static func item(
        _ name: String,
        _ width: CGFloat,
        icon: String?,
        tip: String,
        kind: MainToolbarItemKind = .button,
        checked: Bool = false,
        visible: Bool = true
    ) -> MainToolbarItem {
        MainToolbarItem(name: name, width: width, height: 22, icon: icon, tooltip: tip, kind: kind, checked: checked, visible: visible)
    }

    private static func separator(_ name: String) -> MainToolbarItem {
        MainToolbarItem(name: name, width: 6, height: 25, icon: nil, tooltip: "", kind: .separator, checked: false, visible: true)
    }
}

enum OptionsSectionID: String, CaseIterable {
    case header
    case grid
    case waveform
    case wav
    case bmp
    case beat
    case expansion

    var title: String {
        switch self {
        case .header: return "Header"
        case .grid: return "Grid"
        case .waveform: return "WaveForm"
        case .wav: return "#WAV (Sounds List)"
        case .bmp: return "#BMP (Images List)"
        case .beat: return "Beat"
        case .expansion: return "Expansion Code"
        }
    }

    var startsExpanded: Bool {
        switch self {
        case .header, .grid, .wav, .bmp: return true
        case .waveform, .beat, .expansion: return false
        }
    }

    var startsShowingPart2: Bool { false }

    var part1Height: CGFloat {
        switch self {
        case .header: return MainWindowChrome.headerPart1Height
        case .grid: return MainWindowChrome.gridPart1Height
        case .waveform: return MainWindowChrome.waveformPart1Height
        case .beat:
            return MainWindowChrome.beatPart1Height
        case .expansion:
            return 0
        case .wav, .bmp:
            return MainWindowChrome.listToolbarHeight
        }
    }

    var part2Height: CGFloat {
        switch self {
        case .header: return MainWindowChrome.headerPart2Height
        case .grid: return MainWindowChrome.gridPart2Height
        case .waveform: return MainWindowChrome.waveformPart2Height
        case .beat: return MainWindowChrome.beatPart2Height
        case .wav, .bmp: return MainWindowChrome.listPart2Height
        case .expansion: return 0
        }
    }

    var hasList: Bool {
        switch self {
        case .wav, .bmp, .beat, .expansion: return true
        case .header, .grid, .waveform: return false
        }
    }

    var hasExpander: Bool {
        self != .expansion
    }

    func innerHeight(part2Visible: Bool) -> CGFloat {
        var height = part1Height
        if hasExpander {
            height += MainWindowChrome.expanderHeight
        }
        if part2Visible {
            height += part2Height
        }
        if hasList {
            let box = self == .expansion ? MainWindowChrome.expansionBoxHeight : MainWindowChrome.listBoxHeight
            height += box + MainWindowChrome.listResizerHeight
        }
        return height
    }

    func height(switchOn: Bool, part2Visible: Bool) -> CGFloat {
        guard switchOn else { return MainWindowChrome.sectionSwitchHeight }
        return MainWindowChrome.sectionSwitchHeight + innerHeight(part2Visible: part2Visible)
    }
}

struct OptionsSidebarState: Equatable {
    var switchOn: [OptionsSectionID: Bool]
    var part2Visible: [OptionsSectionID: Bool]

    static let runtimeDefault = OptionsSidebarState(
        switchOn: Dictionary(uniqueKeysWithValues: OptionsSectionID.allCases.map { ($0, $0.startsExpanded) }),
        part2Visible: Dictionary(uniqueKeysWithValues: OptionsSectionID.allCases.map { ($0, $0.startsShowingPart2) })
    )

    func height(of section: OptionsSectionID) -> CGFloat {
        section.height(switchOn: switchOn[section] ?? false, part2Visible: part2Visible[section] ?? false)
    }

    var documentHeight: CGFloat {
        OptionsSectionID.allCases.reduce(0) { $0 + height(of: $1) }
    }

    func frames() -> [(section: OptionsSectionID, frame: CGRect)] {
        var y: CGFloat = 0
        return OptionsSectionID.allCases.map { section in
            let height = height(of: section)
            let frame = CGRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: height)
            y += height
            return (section, frame)
        }
    }
}

enum BMS36Token {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func encode(_ value: Int) -> String {
        let clamped = min(MainWindowChrome.wavTokenCount, max(1, value))
        return String([digits[clamped / 36], digits[clamped % 36]])
    }

    /// `Utilities.C36to10`: pad to two characters, then `digit0 * 36 + digit1`.
    static func decode(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let padded = String(("00" + trimmed).suffix(2))
        let characters = Array(padded)
        return digit(characters[0]) * 36 + digit(characters[1])
    }

    /// `diagFind.ValidLabel`: one or two 0-9/A-Z characters, not `0` / `00`.
    static func isValidLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.isEmpty || trimmed == "0" || trimmed == "00" { return false }
        guard trimmed.count == 1 || trimmed.count == 2 else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
        }
    }

    static let all: [String] = (1...MainWindowChrome.wavTokenCount).map(encode)

    private static func digit(_ character: Character) -> Int {
        guard let value = character.asciiValue else { return 0 }
        if value >= 48 && value <= 57 { return Int(value - 48) }
        if value >= 65 && value <= 90 { return Int(value - 55) }
        return 0
    }
}
