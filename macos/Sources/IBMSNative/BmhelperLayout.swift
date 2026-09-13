import CoreGraphics
import Foundation

enum BmhelperMainLayout {
    /// 以可读的钢琴卷和操作检查器为目标的工作尺寸，不是 Windows 原版测量值。
    static let clientSize = CGSize(width: 1000, height: 700)
    static let title = "Be-Music Helper"
    static let splitter = CGRect(x: 0, y: 0, width: 1000, height: 700)
    static let sashGravity = 0.5
    static let minimumPaneSize: CGFloat = 120
    static let minimumWindowSize = CGSize(width: 860, height: 600)
    static let projectToolbarHeight: CGFloat = 40

    static func contentSplitFrame(size: CGSize, statusHeight: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: projectToolbarHeight,
            width: max(size.width, 0),
            height: max(size.height - projectToolbarHeight - statusHeight, 0)
        )
    }
    static let statusFieldWidths = [-1, 180, 120]
    /// `frame.cpp` 菜单栏。只在本窗口是 key 时接到系统菜单栏。
    static let fileMenuTitle = "File (&F)"
    static let newMenuTitle = "New..."
    static let openProjectMenuTitle = "Open project (&O)..."
    static let saveProjectMenuTitle = "Save project (&S)"
    static let saveProjectAsMenuTitle = "Save project as (&A)..."
    static let openProjectPrompt = "Open project file"
    static let divisionsMenuTitle = "Divisions (&D)"
    static let defOutMenuTitle = "BMS WAV definitions"
    static let newDivisionMenuTitle = "New division (&N)..."
    static let openCutterMenuTitle = "Open built-in audio cutter"
    static let helpMenuTitle = "Help (&H)"
    static let openFailedTitle = "Couldn't open file"
}

/// 对照 `frame.cpp` 状态栏三列：`SetStatusWidths` / `ProjectChanged` / `UpdateDivision`。
/// `%zu` 后面的 n / d 是原文里的字母，不是 notes 单词。
/// 第 0 列默认空串；两个 MidiView 悬停都写左列，后移上去的那份生效。
/// 中列 / 右列保持 BH-STAT。状态栏里不把空名换成 untitled。
enum BmhelperStatus {
    static let fieldWidths = BmhelperMainLayout.statusFieldWidths

    static func source(_ notes: Int) -> String {
        "source: \(notes)n"
    }

    static func division(name: String, notes: Int, definitions: Int) -> String {
        "\(name): \(notes)n/\(definitions)d"
    }

    static func fields(
        hasProject: Bool,
        selectedName: String? = nil,
        notes: Int = 0,
        definitions: Int = 0,
        sourceNotes: Int = 0,
        hover: String = ""
    ) -> [String] {
        guard hasProject else {
            return ["", "", ""]
        }
        let middle: String
        if let selectedName {
            middle = division(name: selectedName, notes: notes, definitions: definitions)
        } else {
            middle = ""
        }
        return [hover, middle, source(sourceNotes)]
    }
}

/// 对照 `frame.cpp` 的 `ProjectChangeFlagChanged`。
/// 无工程只显示程序名。未命名永远是 `New project*`，不管 `Changed()`。
/// 已命名时星号跟在文件名后面，再接空格短横空格和程序名。
/// `{title}` 是路径最后一段去掉 `.bmh`。
enum BmhelperTitle {
    static let empty = BmhelperMainLayout.title

    static func untitled(changed _: Bool = false) -> String {
        "New project* - \(empty)"
    }

    static func titled(name: String, changed: Bool) -> String {
        if changed {
            return "\(name)* - \(empty)"
        }
        return "\(name) - \(empty)"
    }

    static func fileTitle(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func caption(
        hasProject: Bool,
        titled: Bool,
        changed: Bool,
        fileTitle: String
    ) -> String {
        guard hasProject else { return empty }
        if !titled {
            return untitled(changed: changed)
        }
        return Self.titled(name: fileTitle, changed: changed)
    }
}

/// 对照 `frame.cpp` 的 `OnCloseProject` / `_AskCloseProject`。
/// 系统提示框，没有手写客户区。脏了才问。没有工程不问也不改。
enum BmhelperClose {
    static let menuTitle = "Close project (&C)"
    static let prompt = "The project has been modified. Do you want to save?"
    static let windowTitle = BmhelperMainLayout.title
    static let yesTitle = "Yes"
    static let noTitle = "No"
    static let cancelTitle = "Cancel"

    enum Answer {
        case yes
        case no
        case cancel
    }

    enum Decision: Equatable {
        case ignore
        case close
        case abort
        case saveThenClose
        case saveAsThenClose
    }

    static func decide(
        hasProject: Bool,
        changed: Bool = false,
        answer: Answer = .cancel,
        titled: Bool = false,
        saveAsSucceeded: Bool = false
    ) -> Decision {
        guard hasProject else { return .ignore }
        guard changed else { return .close }
        switch answer {
        case .cancel:
            return .abort
        case .no:
            return .close
        case .yes:
            if titled {
                return .saveThenClose
            }
            return saveAsSucceeded ? .saveAsThenClose : .abort
        }
    }
}

/// 对照 `frame.cpp` 的 `OnDropFiles` 和 `project.cpp` 的 `SetNewSource`。
/// 不先问保存。多个文件按顺序试，第一个成功就停。
/// 没有工程：MIDI 走 New，`.bmh` 走 Open。
/// 有工程：一律换源（`.bmh` 会在 `load_smf` 失败）。不重建 division，不设脏。
enum BmhelperDrop {
    enum Action: Equatable {
        case none
        case newFromMidi
        case openProject
        case replaceSource
    }

    static let projectExtension = "bmh"

    static func dropFailedMessage(_ path: String) -> String {
        "Couldn't open file:\r\n\(path)"
    }

    static func decide(hasProject: Bool, files: [String]) -> Action {
        guard let file = files.first else { return .none }
        if hasProject {
            return .replaceSource
        }
        if isProjectFile(file) {
            return .openProject
        }
        return .newFromMidi
    }

    /// 对照 `OnDropFiles`：前面失败就继续，第一个成功返回下标。
    static func firstSuccess(_ files: [String], tryOpen: (String) -> Bool) -> Int? {
        for (index, file) in files.enumerated() {
            if tryOpen(file) {
                return index
            }
        }
        return nil
    }

    /// 对照 `SetNewSource`：不设脏。原来干净仍干净，原来脏仍脏。
    static func changeFlagAfterReplace(wasChanged: Bool) -> Bool {
        wasChanged
    }

    static func isProjectFile(_ path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.lowercased() == projectExtension
    }
}

/// 对照 `divview.cpp` 的 `DivisionsView` 左栏。
/// 按钮文案是左栏 `wxButton` 的 `New division...`，不是菜单上的 `New division (&N)...`。
/// 列表项是 `get_name()`，顺序与工程里的 divisions 相同。
/// 打开后有条目则选中 0；追加后选中最后一项；越界点选无效。
/// 对照 `divedit.cpp`：`SplitHorizontally(midi, transpose_panel, -60)`，`SetSashGravity(1)`。
/// sash `-60` 只说明下面那条是短的，不是截图像素。
enum BmhelperDivisionEditor {
    static let sashGravity: CGFloat = 1
}

enum BmhelperDivisionList {
    static let buttonTitle = "New division..."

    static func names(_ names: [String]) -> [String] {
        names
    }

    static func selectionAfterLoad(count: Int) -> Int? {
        count > 0 ? 0 : nil
    }

    /// `count` 是追加之后的条目数。有条目则选中最后一项。
    static func selectionAfterAppend(count: Int) -> Int? {
        count > 0 ? count - 1 : nil
    }

    static func select(_ index: Int, count: Int) -> Int? {
        (0..<count).contains(index) ? index : nil
    }
}

/// 对照 `divedit.cpp` 右侧五个按钮；`divview.cpp` 左右分栏。
/// `SplitVertically(left, right, -200)`，`SetSashGravity(1)`，`SetMinimumPaneSize(125)`。
/// 有选中的 division 则五个都 Enable(true)，没有则五个都 false。
/// 只接线。定义条和时间线钢琴卷在左栏，见 `BmhelperDefinitionView` / `BmhelperDivisionEditor`。
enum BmhelperRightPane {
    static let titles = [
        "Write MIDI File",
        "Copy woslicer II Cutting Positions",
        "Open built-in audio cutter",
        "Open BMS WAV definitions...",
        "Copy BMS Data to Clipboard"
    ]
    static let proportions = [2, 1, 1, 2, 2]
    /// 对照 sash `-200`：右栏提示宽 200。
    static let rightPaneWidthHint: CGFloat = 200
    /// 对照 `divview.cpp` 的 `SetMinimumPaneSize(125)`。
    static let minimumPaneSize: CGFloat = 125
    /// 重力在左边，拉大时左栏变宽。
    static let sashGravity: CGFloat = 1
    /// 剪贴板打不开时的原文。按钮和菜单共用这一句。
    static let clipboardUnavailable = "Clipboard is not available."

    static func buttonsEnabled(hasProject: Bool, hasSelection: Bool) -> Bool {
        hasProject && hasSelection
    }
}

/// 对照 `defview.cpp` 的 `DefinitionView`。
/// `item_width = 30`。`ReloadDivision` 只填 zz / div，`selected` 永远是 false。
/// 绘制不看 selected，不要发明点选高亮。
/// 没有 division 则 items 空、虚拟宽 0。有则 `VirtualSize(count*30, 0)`。
/// `sx = scrollPos * 30`。第 i 格 zz `(i*30+3-sx, 3)`，div `(i*30+3-sx, 20)`。
/// `page = client.x / 30`（整数除法）。scroll 夹到 `[0, count-page]`；`count <= page` 时为 0。
/// transpose 面板里定义条比例 8、按钮列比例 1。只显示，不在条上改号。
enum BmhelperDefinitionView {
    static let itemWidth = 30
    static let zzInsetX = 3
    static let zzInsetY = 3
    static let divInsetX = 3
    static let divInsetY = 20
    static let barDefProportion = 8
    static let barButtonProportion = 1

    struct Item: Equatable {
        var zz: String
        var divText: String
        var selected: Bool
    }

    struct Point: Equatable {
        var x: Int
        var y: Int
    }

    static func items(_ definitions: [(zz: String, div: Int)]?) -> [Item] {
        guard let definitions else { return [] }
        return definitions.map { definition in
            Item(
                zz: definition.zz,
                divText: String(format: "%d", definition.div),
                selected: false
            )
        }
    }

    static func virtualWidth(_ items: [Item]) -> Int {
        items.count * itemWidth
    }

    static func page(clientWidth: Int) -> Int {
        clientWidth / itemWidth
    }

    static func clampScroll(pos: Int, count: Int, page: Int) -> Int {
        if count <= page { return 0 }
        let maxPos = count - page
        if pos < 0 { return 0 }
        if pos > maxPos { return maxPos }
        return pos
    }

    static func zzPoint(index: Int, scrollPos: Int) -> Point {
        let sx = scrollPos * itemWidth
        return Point(x: index * itemWidth + zzInsetX - sx, y: zzInsetY)
    }

    static func divPoint(index: Int, scrollPos: Int) -> Point {
        let sx = scrollPos * itemWidth
        return Point(x: index * itemWidth + divInsetX - sx, y: divInsetY)
    }
}

/// 对照 `divedit.cpp` 的 `OnDivRegenerate`；`division.cpp` 的 `change_division_settings`。
/// 就地重聚当前选中项，不是追加。
/// 设置窗按 `DivisionSetting(name, quantize)` 重新用默认值，只带上当前名字。
enum BmhelperRegenerate {
    static let menuTitle = "Regenerate division (&E)..."

    /// 对照 `makeDefault`：名字带上当前项，阈值按量化重新算。
    struct Prefill: Equatable {
        var name: String
        var gateThreshold: Int
        var sortType: String
        var startDefinition: Int
    }

    static func prefills(name: String, quantize: Int) -> Prefill {
        let safeQuantize = max(quantize, 1)
        return Prefill(
            name: name,
            gateThreshold: safeQuantize / 8,
            sortType: "nnGateVel",
            startDefinition: BmhelperDefDialogLayout.defaultStartDefinition
        )
    }

    /// `applied == nil` 或 `false` 表示取消，不应用。
    static func commit(_ applied: Bool?) -> Bool {
        applied == true
    }
}

/// 对照 `divedit.cpp:368-373` 的 `wxTextEntryDialog`。
/// 系统输入框，没有手写客户区。空串或全空白按 `untitled`。
enum BmhelperRename {
    static let windowTitle = "Rename division"
    static let menuTitle = "Rename division"

    static func displayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BmhelperDefDialogLayout.defaultName
            : name
    }

    static func prompt(current: String) -> String {
        "Rename '\(displayName(current))' to"
    }

    static func appliedName(_ entered: String) -> String {
        displayName(entered)
    }

    /// `entered == nil` 表示取消，不改名。
    static func commit(_ entered: String?) -> String? {
        entered.map(appliedName)
    }
}

/// 对照 `division.cpp` 的 `get_bms_sequence_data`。
/// 源 MIDI 音符位置，不是聚类后的 Division 时间线。
/// 只拼 BMSE 剪贴板文本，不写进主编辑器。
enum BmhelperSequence {
    static let menuTitle = "Copy BMS sequence to clipboard (&S)"
    static let header = "BMSE ClipBoard Object Data Format\r\n"
    static let clipboardUnavailable = BmhelperRightPane.clipboardUnavailable
    /// `192 / 4`，对照原文 `bmse_quantize`。
    static let bmseQuantize = 48

    /// 没有工程或没有选中时不写剪贴板。
    static func shouldCopy(hasProject: Bool, hasSelection: Bool) -> Bool {
        hasProject && hasSelection
    }

    /// `position * 48 / quantize`，向零取整。quantize 至少为 1。
    static func pulse(position: Int, quantize: Int) -> Int {
        position * bmseQuantize / max(quantize, 1)
    }

    /// `1` + `%02d` lane + `%08d` 脉冲 + `%d` zz 整数 + `\r\n`。
    static func line(lane: Int, pulse: Int, zz: Int) -> String {
        String(format: "1%02d%08d%d\r\n", lane, pulse, zz)
    }

    /// 对照 `ZZNumber::from_string` 再取整数：`01`→1，`0A`→10。
    static func zzInteger(_ text: String) -> Int? {
        let chars = Array(text)
        guard chars.count >= 2 else { return nil }
        let high = digitValue(chars[0])
        let low = digitValue(chars[1])
        guard high < 36, low < 36 else { return nil }
        return high * 36 + low
    }

    /// 按源音符顺序拼整段。`src2def[i]` 对不上定义则跳过该音。
    static func format(
        positions: [Int],
        zzStrings: [String],
        src2def: [Int],
        quantize: Int
    ) -> String {
        var data = header
        var lanes: [Int: Int] = [:]
        let safeQuantize = max(quantize, 1)
        for index in positions.indices {
            guard src2def.indices.contains(index) else { continue }
            let definitionIndex = src2def[index]
            guard zzStrings.indices.contains(definitionIndex) else { continue }
            guard let zz = zzInteger(zzStrings[definitionIndex]) else { continue }
            let pulse = Self.pulse(position: positions[index], quantize: safeQuantize)
            let lane: Int
            if let existing = lanes[pulse] {
                let next = existing + 1
                lanes[pulse] = next
                lane = next
            } else {
                lanes[pulse] = 1
                lane = 1
            }
            data += line(lane: lane, pulse: pulse, zz: zz)
        }
        return data
    }

    private static func digitValue(_ character: Character) -> Int {
        if character >= "0" && character <= "9" {
            return Int(character.asciiValue! - Character("0").asciiValue!)
        }
        if character >= "A" && character <= "Z" {
            return Int(character.asciiValue! - Character("A").asciiValue!) + 10
        }
        if character >= "a" && character <= "z" {
            return Int(character.asciiValue! - Character("a").asciiValue!) + 10
        }
        return 36
    }
}

/// 对照 `division.cpp` 的 `get_div_sequence_data`。
/// Division 时间线位置，不是源 MIDI。
/// 只拼 BMSE 剪贴板文本，不写进主编辑器。右侧按钮走同一套动作。
enum BmhelperDivCopy {
    static let menuTitle = "Copy division (&W)"
    static let header = BmhelperSequence.header
    static let clipboardUnavailable = BmhelperRightPane.clipboardUnavailable

    /// 没有工程或没有选中时不写剪贴板。
    static func shouldCopy(hasProject: Bool, hasSelection: Bool) -> Bool {
        BmhelperSequence.shouldCopy(hasProject: hasProject, hasSelection: hasSelection)
    }

    /// `011` + `%08zu` 脉冲 + `1` + `\r\n`。没有 lane、没有 zz。
    static func line(pulse: Int) -> String {
        String(format: "011%08d1\r\n", pulse)
    }

    /// 按时间线位置顺序拼整段。quantize 至少为 1。
    static func format(positions: [Int], quantize: Int) -> String {
        var data = header
        let safeQuantize = max(quantize, 1)
        for position in positions {
            let pulse = BmhelperSequence.pulse(position: position, quantize: safeQuantize)
            data += line(pulse: pulse)
        }
        return data
    }
}

/// 对照 `divview.cpp` 的 `OnDeleteDivision`。
/// 系统提示框，没有手写客户区。Yes 才删。空名或全空白按 `untitled`。
enum BmhelperDelete {
    static let menuTitle = "Delete division (&D)"
    static let windowTitle = BmhelperMainLayout.title

    static func displayName(_ name: String) -> String {
        BmhelperRename.displayName(name)
    }

    static func prompt(_ name: String) -> String {
        "Are you sure you want to delete \(displayName(name))?"
    }

    /// `confirmed == nil` 或 `false` 表示取消 / No，不删。
    static func commit(_ confirmed: Bool?) -> Bool {
        confirmed == true
    }

    /// `remaining` 是删完之后的条数。
    /// `deleted < remaining` → 选中同一个下标（后面的项顶上来）。
    /// 否则若 `remaining > 0` → 选中最后一项。
    /// `remaining == 0` → `nil`。
    static func selectionAfterDelete(deleted: Int, remaining: Int) -> Int? {
        if remaining <= 0 { return nil }
        if deleted < remaining { return deleted }
        return remaining - 1
    }
}

/// 对照 `frame.cpp` 菜单 `Write modified MIDI File (&M)...`；`divedit.cpp` `_SmfOut`。
/// 写出选中 division 的时间线 MIDI，不是源 MIDI。右侧按钮走同一套动作。
enum BmhelperSmfOut {
    static let menuTitle = "Write modified MIDI File (&M)..."
    static let failedMessage = "Failed to export MIDI file."
    static let saveTitle = "MIDI files"
    static let defaultExtension = "mid"

    /// 没有工程或没有选中时不弹另存为。
    static func shouldExport(hasProject: Bool, hasSelection: Bool) -> Bool {
        hasProject && hasSelection
    }
}

/// 对照 `app.cpp:20-25` 的 `wxGetSingleChoiceIndex`。
/// 系统列表，没有手写客户区。这一轮只存选项原文，不换界面文案。
/// 键名只给 bmhelper 用，不要写 iBMSC / BmsONE 的语言键。
enum BmhelperLanguage {
    static let title = "Language"
    static let prompt = "Please choose language:"
    static let options = [
        "System",
        "English",
        "Español",
        "Norsk (Bokmål)",
        "日本語",
    ]
    static let defaultsKey = "bmhelper.language"
    static let defaultIndex = 0

    static func resolved(_ stored: String?) -> String? {
        guard let stored, options.contains(stored) else { return nil }
        return stored
    }

    static func load(from defaults: UserDefaults = .standard) -> String? {
        resolved(defaults.string(forKey: defaultsKey))
    }

    static func load(from box: [String: String]) -> String? {
        resolved(box[defaultsKey])
    }

    /// `option == nil` 表示取消，不写。对不上的旧值也不写。
    static func save(_ option: String?, to defaults: UserDefaults = .standard) {
        guard let option, resolved(option) != nil else { return }
        defaults.set(option, forKey: defaultsKey)
    }

    static func save(_ option: String?, into box: inout [String: String]) {
        guard let option, resolved(option) != nil else { return }
        box[defaultsKey] = option
    }
}

/// 对照 `frame.cpp:269-271` 的 `wxMessageBox`。系统关于框，没有手写客户区。
/// 不写 `__DATE__` / `__TIME__`，也不写 `Qt`。
enum BmhelperAbout {
    static let menuTitle = "About"
    static let windowTitle = BmhelperMainLayout.title
    static let messageText = "Be-Music Helper (beta 6 (wyrmin))"
    static let informativeText = " by exclusion\n forked by zardoru"
    static let message = messageText + "\n" + informativeText
}

/// 对照 `AudioSplitter`。源码构造宽 `800`、高 `-1`，随即 `SetSizerAndFit`。
/// 这一轮原生窗客户区用工作尺寸 `800 × 360`。高度不是原版客户区。未截图。
enum BmhelperAudioSplitterLayout {
    static let clientSize = CGSize(width: 800, height: 360)
    static let sourceWidth: CGFloat = 800
    static let originalClientSize: CGSize? = nil
    static let canResize = false
    static let canMaximize = false
    static let defaultBpm = 120.0
    static let bpmMinimum = 1.0
    static let bpmMaximum = 5000.0
    static let bpmDigits = 2
    static let defaultOffsetMs = 0.0
    static let offsetMinimum = -10000.0
    static let offsetMaximum = 10000.0
    static let audioFileTitle = "Audio File"
    static let dropHint = "You can drag and drop a .wav file into this window."
    static let browseTitle = "Browse..."
    static let outputDirectoryTitle = "Output Directory"
    static let prefixTitle = "Output sound file prefix:"
    static let sliceParametersTitle = "Slice Parameters"
    static let bpmTitle = "BPM:"
    static let offsetTitle = "Offset (MS):"
    static let splitTitle = "Split"
    static let closeTitle = "Close"
    static let selectAudioTitle = "Select audio file..."
    static let selectOutputTitle = "Select audio output directory..."
    static let errorTitle = "Error while splitting file"

    static func title(divisionName: String) -> String {
        "Audio splitter (division: \"\(divisionName)\")"
    }
}

/// 对照 `DivisionSettingDialog`。构造 `330 × 455`，随即 `SetSizerAndFit`。
/// 这一轮按任务把构造尺寸当作客户区。未截图。
enum BmhelperDivisionSettingLayout {
    static let clientSize = CGSize(width: 330, height: 455)
    static let title = "Division settings"
    static let nameTitle = "Name (&N):"
    static let midiBoxTitle = "MIDI settings"
    static let srcCopyTitle = "Leave MIDI unaltered (&C)"
    static let headMarginTitle = "Leading silence (&H):"
    static let minIntervalTitle = "Min. interval gap (&I):"
    static let sortTitle = "Sorting method (&S):"
    static let differenceBoxTitle = "Minimum difference in:"
    static let gateTitle = " Length (&G):"
    static let velocityTitle = " Velocity (&V):"
    static let definitionBoxTitle = "Definition settings"
    static let zzTitle = "Use base-36 range(00-ZZ) (&Z)"
    static let mlTitle = "Use overloading (&M)"
    static let startTitle = "Starting BMS Index (&D):"
    static let mlIntervalTitle = "Overloading Interval (&L):"
    static let okTitle = "OK"
    static let cancelTitle = "Cancel"
    static let sortTitles = [
        "None",
        "nn/gate/vel",
        "nn/vel/gate",
        "gate/nn/vel",
        "gate/vel/nn",
        "vel/nn/gate",
        "vel/gate/nn"
    ]
}

enum BmhelperDefTransposeLayout {
    static let clientSize = CGSize(width: 200, height: 120)
    static let title = "WAV definitions"
    static let okTitle = "OK"
    /// 下半窗格三个按钮。对照 `divedit.cpp` 的 `<` / `>` / `Transpose to...`。
    static let upTitle = "<"
    static let downTitle = ">"
    static let toTitle = "Transpose to..."

    static func edit(in size: CGSize) -> CGRect {
        CGRect(x: 5, y: 5, width: size.width - 10, height: size.height - 40)
    }

    static func ok(in size: CGSize) -> CGRect {
        CGRect(x: 5, y: size.height - 30, width: size.width - 10, height: 25)
    }

    static let edit = edit(in: clientSize)
    static let ok = ok(in: clientSize)
}

enum BmhelperDefDialogLayout {
    static let clientSize = CGSize(width: 400, height: 300)
    static let title = "BMS WAV definitions"
    static let filenameTitle = "Filename (&F):"
    static let copyTitle = "Copy to clipboard (&C)"
    static let closeTitle = "Close (&W)"
    static let defaultName = "untitled"
    /// 对照 `DivisionSetting` 默认 `start_definition = 1`，第一个是 `01` 不是 `00`。
    static let defaultStartDefinition = 1
    static let wavLineTerminator = "\r\n"
    static let filenameLabel = CGRect(x: 5, y: 8, width: 80, height: 15)

    static func name(in size: CGSize) -> CGRect {
        CGRect(x: 85, y: 5, width: size.width - 90, height: 18)
    }

    static func data(in size: CGSize) -> CGRect {
        CGRect(x: 5, y: 30, width: size.width - 10, height: size.height - 65)
    }

    static func copy(in size: CGSize) -> CGRect {
        CGRect(x: 5, y: size.height - 30, width: (size.width - 10) / 2, height: 25)
    }

    static func close(in size: CGSize) -> CGRect {
        CGRect(x: (size.width - 10) / 2 + 5, y: size.height - 30, width: (size.width - 10) / 2, height: 25)
    }

    static let name = name(in: clientSize)
    static let data = data(in: clientSize)
    static let copy = copy(in: clientSize)
    static let close = close(in: clientSize)
}

/// MIDI 导入设置窗。对照 `midi_smfin.cpp` 的 `LoadSmfDialog`。
///
/// 源码构造 `wxSize(290, 130)`。wx 这份尺寸可能是外框，不一定等于客户区。
/// 构造后立刻 `SetSizerAndFit`，最终客户区不能从源码定死。
/// 这一轮按任务要求，把 `290 × 130` 当作原生窗客户区。
/// 未截图，不能写成像素已通过。
enum BmhelperMidiImportLayout {
    static let clientSize = CGSize(width: 290, height: 130)
    static let title = "MIDI file import settings"
    static let hasCloseBox = false
    static let tracksTitle = "Tracks (&T):"
    static let channelsTitle = "Channels (&C):"
    static let okTitle = "OK"
    static let tracksLabel = CGRect(x: 5, y: 8, width: 85, height: 15)
    static let tracksChoice = CGRect(x: 95, y: 5, width: 185, height: 22)
    static let channelsLabel = CGRect(x: 5, y: 34, width: 85, height: 15)
    static let channelGridOrigin = CGPoint(x: 95, y: 34)
    static let channelCell = CGSize(width: 42, height: 16)
    static let channelGap: CGFloat = 2
    static let ok = CGRect(x: 200, y: 105, width: 80, height: 20)

    static func channelFrame(_ index: Int) -> CGRect {
        let column = index % 4
        let row = index / 4
        return CGRect(
            x: channelGridOrigin.x + CGFloat(column) * (channelCell.width + channelGap),
            y: channelGridOrigin.y + CGFloat(row) * (channelCell.height + channelGap),
            width: channelCell.width,
            height: channelCell.height
        )
    }
}
