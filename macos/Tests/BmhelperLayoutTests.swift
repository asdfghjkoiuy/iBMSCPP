import Foundation

@main
struct BmhelperLayoutTests {
    static func main() {
        testMainWindow()
        testDefTranspose()
        testDefDialog()
        testAbout()
        testRename()
        testRegenerate()
        testLanguage()
        testDivisionList()
        testDelete()
        testStatus()
        testTitle()
        testClose()
        testDrop()
        testSequence()
        testDivCopy()
        testSmfOut()
        testRightPane()
        testDefinitionView()
        testDivisionEditorSash()
        print("BmhelperLayoutTests passed")
    }

    private static func testMainWindow() {
        require(BmhelperMainLayout.clientSize == CGSize(width: 1000, height: 700), "main client size")
        require(BmhelperMainLayout.splitter == CGRect(x: 0, y: 0, width: 1000, height: 700), "main splitter")
        require(BmhelperMainLayout.title == "Be-Music Helper", "main title")
        require(BmhelperMainLayout.sashGravity == 0.5, "sash gravity")
        require(BmhelperMainLayout.minimumPaneSize == 120, "minimum pane")
        require(BmhelperMainLayout.minimumWindowSize == CGSize(width: 860, height: 600), "minimum window")
        require(BmhelperMainLayout.projectToolbarHeight == 40, "project toolbar")
        let initialContent = BmhelperMainLayout.contentSplitFrame(size: BmhelperMainLayout.clientSize, statusHeight: 18)
        require(initialContent.origin.y == 40 && initialContent.height == 642, "initial split bounds")
        let resizedContent = BmhelperMainLayout.contentSplitFrame(size: CGSize(width: 860, height: 600), statusHeight: 18)
        require(resizedContent.width == 860 && resizedContent.height == 542, "resize split bounds")
        require(BmhelperMainLayout.statusFieldWidths == [-1, 180, 120], "status widths")
        require(BmhelperMainLayout.fileMenuTitle == "File (&F)", "File menu")
        require(BmhelperMainLayout.newMenuTitle == "New...", "New MIDI")
        require(BmhelperMainLayout.openProjectMenuTitle == "Open project (&O)...", "Open project")
        require(BmhelperMainLayout.saveProjectMenuTitle == "Save project (&S)", "Save project")
        require(BmhelperMainLayout.saveProjectAsMenuTitle == "Save project as (&A)...", "Save as")
        require(BmhelperMainLayout.openProjectPrompt == "Open project file", "open prompt")
        require(BmhelperMainLayout.divisionsMenuTitle == "Divisions (&D)", "Divisions menu")
        require(BmhelperMainLayout.defOutMenuTitle == "BMS WAV definitions", "DefOut")
        require(BmhelperMainLayout.newDivisionMenuTitle == "New division (&N)...", "New division")
        require(BmhelperMainLayout.openCutterMenuTitle == "Open built-in audio cutter", "cutter")
        require(BmhelperDivisionSettingLayout.clientSize == CGSize(width: 330, height: 455), "division settings")
        require(BmhelperAudioSplitterLayout.sourceWidth == 800, "splitter source width")
        require(BmhelperAudioSplitterLayout.originalClientSize == nil, "splitter height unknown")
        require(
            BmhelperAudioSplitterLayout.title(divisionName: "kick") == "Audio splitter (division: \"kick\")",
            "splitter title"
        )
        require(BmhelperAudioSplitterLayout.defaultBpm == 120, "BPM 120")
        require(BmhelperAudioSplitterLayout.canResize == false, "no resize")
        require(BmhelperDivisionSettingLayout.title == "Division settings", "division title")
    }

    private static func testDefTranspose() {
        require(BmhelperDefTransposeLayout.clientSize == CGSize(width: 200, height: 120), "transpose client size")
        require(BmhelperDefTransposeLayout.edit == CGRect(x: 5, y: 5, width: 190, height: 80), "transpose edit")
        require(BmhelperDefTransposeLayout.ok == CGRect(x: 5, y: 90, width: 190, height: 25), "transpose OK")
        require(BmhelperDefTransposeLayout.title == "WAV definitions", "transpose title")
        require(BmhelperDefTransposeLayout.okTitle == "OK", "transpose OK text")
        require(BmhelperDefTransposeLayout.upTitle == "<", "transpose up")
        require(BmhelperDefTransposeLayout.downTitle == ">", "transpose down")
        require(BmhelperDefTransposeLayout.toTitle == "Transpose to...", "transpose to")
    }

    private static func testDefDialog() {
        require(BmhelperDefDialogLayout.clientSize == CGSize(width: 400, height: 300), "def client size")
        require(BmhelperDefDialogLayout.filenameLabel == CGRect(x: 5, y: 8, width: 80, height: 15), "Filename label")
        require(BmhelperDefDialogLayout.name == CGRect(x: 85, y: 5, width: 310, height: 18), "Filename field")
        require(BmhelperDefDialogLayout.data == CGRect(x: 5, y: 30, width: 390, height: 235), "definition text")
        require(BmhelperDefDialogLayout.copy == CGRect(x: 5, y: 270, width: 195, height: 25), "Copy")
        require(BmhelperDefDialogLayout.close == CGRect(x: 200, y: 270, width: 195, height: 25), "Close")
        require(BmhelperDefDialogLayout.title == "BMS WAV definitions", "def title")
        require(BmhelperDefDialogLayout.filenameTitle == "Filename (&F):", "Filename text")
        require(BmhelperDefDialogLayout.copyTitle == "Copy to clipboard (&C)", "Copy text")
        require(BmhelperDefDialogLayout.closeTitle == "Close (&W)", "Close text")
        require(BmhelperDefDialogLayout.defaultName == "untitled", "untitled default")
        require(BmhelperDefDialogLayout.defaultStartDefinition == 1, "start definition 1")
        require(BmhelperDefDialogLayout.wavLineTerminator == "\r\n", "wav CRLF")
    }

    /// 对照 `frame.cpp:269-271`。`BmhelperMenuBar` 不在本夹具里，菜单绑定测不到。
    private static func testAbout() {
        require(BmhelperAbout.windowTitle == "Be-Music Helper", "about window title")
        require(BmhelperAbout.menuTitle == "About", "about menu title")
        require(
            BmhelperAbout.message == "Be-Music Helper (beta 6 (wyrmin))\n by exclusion\n forked by zardoru",
            "about message"
        )
        require(BmhelperAbout.message.contains("beta 6 (wyrmin)"), "wyrmin")
        require(BmhelperAbout.message.contains("exclusion"), "exclusion")
        require(BmhelperAbout.message.contains("zardoru"), "zardoru")
        require(!BmhelperAbout.message.contains("__DATE__"), "no DATE")
        require(!BmhelperAbout.message.contains("__TIME__"), "no TIME")
        require(!BmhelperAbout.message.contains("Qt"), "no Qt")
        require(BmhelperMainLayout.helpMenuTitle == "Help (&H)", "Help menu")
    }

    /// 对照 `divedit.cpp:368-373`。空串和全空白都当成 untitled。
    private static func testRename() {
        require(BmhelperRename.prompt(current: "melody") == "Rename 'melody' to", "rename prompt melody")
        require(BmhelperRename.prompt(current: "") == "Rename 'untitled' to", "rename prompt empty")
        require(BmhelperRename.prompt(current: "  ") == "Rename 'untitled' to", "rename prompt blank")
        require(BmhelperRename.appliedName("kick") == "kick", "applied kick")
        require(BmhelperRename.appliedName("") == "untitled", "applied empty")
        require(BmhelperRename.windowTitle == "Rename division", "rename title")
        require(BmhelperRename.menuTitle == "Rename division", "rename menu")
        require(BmhelperRename.commit(nil) == nil, "rename cancel")
        require(BmhelperRename.commit("") == "untitled", "rename commit empty")
    }

    /// 对照 `divedit.cpp` 的 `OnDivRegenerate`。设置窗用默认值加当前名。
    private static func testRegenerate() {
        require(
            BmhelperRegenerate.menuTitle == "Regenerate division (&E)...",
            "regen menu"
        )
        let prefilled = BmhelperRegenerate.prefills(name: "melody", quantize: 480)
        require(prefilled.name == "melody", "prefill name")
        require(prefilled.gateThreshold == 60, "prefill gate 480/8")
        require(prefilled.sortType == "nnGateVel", "prefill sort nn/gate/vel")
        require(prefilled.startDefinition == 1, "prefill start 1")
        require(BmhelperRegenerate.commit(nil) == false, "regen cancel")
    }

    /// 对照 `app.cpp:20-25` / `Configuration.cpp:12-18`。选项顺序和原文必须一致。
    private static func testLanguage() {
        require(BmhelperLanguage.title == "Language", "language title")
        require(BmhelperLanguage.prompt == "Please choose language:", "language prompt")
        require(BmhelperLanguage.options.count == 5, "language option count")
        require(BmhelperLanguage.options[0] == "System", "option 0 System")
        require(BmhelperLanguage.options[1] == "English", "option 1 English")
        require(BmhelperLanguage.options[2] == "Español", "option 2 Español")
        require(BmhelperLanguage.options[3] == "Norsk (Bokmål)", "option 3 Norsk")
        require(BmhelperLanguage.options[4] == "日本語", "option 4 日本語")
        require(BmhelperLanguage.resolved(nil) == nil, "resolved nil")
        require(BmhelperLanguage.resolved("English") == "English", "resolved English")
        require(BmhelperLanguage.resolved("French") == nil, "resolved French")
        require(BmhelperLanguage.resolved("system") == nil, "resolved system case")

        var box: [String: String] = [:]
        require(BmhelperLanguage.load(from: box) == nil, "empty box")
        BmhelperLanguage.save(nil, into: &box)
        require(box.isEmpty, "cancel does not write")
        BmhelperLanguage.save("French", into: &box)
        require(box.isEmpty, "invalid does not write")
        BmhelperLanguage.save("English", into: &box)
        require(BmhelperLanguage.load(from: box) == "English", "box stores English")
        require(box[BmhelperLanguage.defaultsKey] == "English", "key is bmhelper.language")
    }

    /// 对照 `divview.cpp` 的 `DivisionsView`。名单顺序、打开选中 0、追加选中末项。
    private static func testDivisionList() {
        require(BmhelperDivisionList.buttonTitle == "New division...", "button title")
        require(BmhelperDivisionList.names(["melody", "kick"]) == ["melody", "kick"], "names order")
        require(BmhelperDivisionList.selectionAfterLoad(count: 2) == 0, "load selects 0")
        require(BmhelperDivisionList.selectionAfterLoad(count: 0) == nil, "empty load")
        require(BmhelperDivisionList.selectionAfterAppend(count: 2) == 1, "append selects last")
        require(BmhelperDivisionList.select(1, count: 2) == 1, "select 1")
        require(BmhelperDivisionList.select(-1, count: 2) == nil, "select -1")
        require(BmhelperDivisionList.select(5, count: 2) == nil, "select 5")
    }

    /// 对照 `divview.cpp` 的 `OnDeleteDivision`。空串和全空白都当成 untitled。
    private static func testDelete() {
        require(BmhelperDelete.menuTitle == "Delete division (&D)", "delete menu")
        require(BmhelperDelete.windowTitle == "Be-Music Helper", "delete window title")
        require(
            BmhelperDelete.prompt("melody") == "Are you sure you want to delete melody?",
            "delete prompt melody"
        )
        require(
            BmhelperDelete.prompt("") == "Are you sure you want to delete untitled?",
            "delete prompt empty"
        )
        require(
            BmhelperDelete.prompt("  ") == "Are you sure you want to delete untitled?",
            "delete prompt blank"
        )
        require(BmhelperDelete.commit(nil) == false, "delete cancel nil")
        require(BmhelperDelete.commit(false) == false, "delete cancel no")
        require(BmhelperDelete.commit(true) == true, "delete yes")
        require(BmhelperDelete.selectionAfterDelete(deleted: 1, remaining: 2) == 1, "delete mid")
        require(BmhelperDelete.selectionAfterDelete(deleted: 2, remaining: 2) == 1, "delete last")
        require(BmhelperDelete.selectionAfterDelete(deleted: 0, remaining: 0) == nil, "delete all")
    }

    /// 对照 `frame.cpp` 状态栏。`%zu` 后面的 n / d 是字母。
    private static func testStatus() {
        require(BmhelperStatus.fieldWidths == [-1, 180, 120], "status widths")
        require(BmhelperStatus.fieldWidths == BmhelperMainLayout.statusFieldWidths, "reuse widths")
        require(BmhelperStatus.source(1) == "source: 1n", "source 1")
        require(BmhelperStatus.source(0) == "source: 0n", "source 0")
        require(
            BmhelperStatus.division(name: "melody", notes: 1, definitions: 1) == "melody: 1n/1d",
            "division melody"
        )
        require(
            BmhelperStatus.division(name: "kick", notes: 2, definitions: 3) == "kick: 2n/3d",
            "division kick"
        )
        require(
            BmhelperStatus.fields(hasProject: false) == ["", "", ""],
            "no project"
        )
        require(
            BmhelperStatus.fields(hasProject: true, sourceNotes: 1) == ["", "", "source: 1n"],
            "project no selection"
        )
        require(
            BmhelperStatus.fields(
                hasProject: true,
                selectedName: "melody",
                notes: 1,
                definitions: 1,
                sourceNotes: 1
            ) == ["", "melody: 1n/1d", "source: 1n"],
            "project melody"
        )
    }

    /// 对照 `frame.cpp` 的 `ProjectChangeFlagChanged`。未命名不管 Changed()。
    private static func testTitle() {
        require(BmhelperTitle.empty == "Be-Music Helper", "empty title")
        require(
            BmhelperTitle.untitled(changed: false) == "New project* - Be-Music Helper",
            "untitled clean"
        )
        require(
            BmhelperTitle.untitled(changed: true) == "New project* - Be-Music Helper",
            "untitled dirty"
        )
        require(
            BmhelperTitle.titled(name: "song", changed: false) == "song - Be-Music Helper",
            "titled clean"
        )
        require(
            BmhelperTitle.titled(name: "song", changed: true) == "song* - Be-Music Helper",
            "titled dirty"
        )
        require(
            BmhelperTitle.fileTitle(URL(fileURLWithPath: "/tmp/song.bmh")) == "song",
            "file title basename"
        )
        require(
            BmhelperTitle.caption(
                hasProject: false,
                titled: true,
                changed: true,
                fileTitle: "song"
            ) == "Be-Music Helper",
            "caption no project"
        )
        require(
            BmhelperTitle.caption(
                hasProject: true,
                titled: false,
                changed: false,
                fileTitle: "song"
            ) == "New project* - Be-Music Helper",
            "caption untitled"
        )
    }

    /// 对照 `frame.cpp` 的 `OnCloseProject` / `_AskCloseProject`。
    /// 没有工程不问。不脏直接关。脏了才问 Yes / No / Cancel。
    private static func testClose() {
        require(BmhelperClose.menuTitle == "Close project (&C)", "close menu")
        require(
            BmhelperClose.prompt == "The project has been modified. Do you want to save?",
            "close prompt"
        )
        require(BmhelperClose.windowTitle == "Be-Music Helper", "close window title")
        require(BmhelperClose.yesTitle == "Yes", "close yes")
        require(BmhelperClose.noTitle == "No", "close no")
        require(BmhelperClose.cancelTitle == "Cancel", "close cancel")
        require(BmhelperClose.decide(hasProject: false) == .ignore, "no project ignore")
        require(
            BmhelperClose.decide(hasProject: true, changed: false) == .close,
            "clean close"
        )
        require(
            BmhelperClose.decide(hasProject: true, changed: true, answer: .cancel) == .abort,
            "cancel abort"
        )
        require(
            BmhelperClose.decide(hasProject: true, changed: true, answer: .no) == .close,
            "no close"
        )
        require(
            BmhelperClose.decide(hasProject: true, changed: true, answer: .yes, titled: true)
                == .saveThenClose,
            "yes titled"
        )
        require(
            BmhelperClose.decide(
                hasProject: true,
                changed: true,
                answer: .yes,
                titled: false,
                saveAsSucceeded: false
            ) == .abort,
            "yes untitled cancel"
        )
        require(
            BmhelperClose.decide(
                hasProject: true,
                changed: true,
                answer: .yes,
                titled: false,
                saveAsSucceeded: true
            ) == .saveAsThenClose,
            "yes untitled save as"
        )
    }

    /// 对照 `OnDropFiles` / `SetNewSource`。失败带路径。空列表不动作。
    private static func testDrop() {
        require(
            BmhelperDrop.dropFailedMessage("/tmp/a.mid") == "Couldn't open file:\r\n/tmp/a.mid",
            "drop failed message"
        )
        require(
            BmhelperDrop.decide(hasProject: false, files: ["song.mid"]) == .newFromMidi,
            "no project midi is new"
        )
        require(
            BmhelperDrop.decide(hasProject: false, files: ["song.bmh"]) == .openProject,
            "no project bmh is open"
        )
        require(
            BmhelperDrop.decide(hasProject: true, files: ["song.mid"]) == .replaceSource,
            "has project midi replaces"
        )
        require(
            BmhelperDrop.decide(hasProject: true, files: ["song.bmh"]) == .replaceSource,
            "has project bmh still replaces"
        )
        require(
            BmhelperDrop.decide(hasProject: false, files: []) == .none,
            "empty files no action"
        )
        require(
            BmhelperDrop.decide(hasProject: true, files: []) == .none,
            "empty files keep project"
        )
        require(
            BmhelperDrop.changeFlagAfterReplace(wasChanged: false) == false,
            "clean stays clean"
        )
        require(
            BmhelperDrop.changeFlagAfterReplace(wasChanged: true) == true,
            "dirty stays dirty"
        )
    }

    /// 对照 `division.cpp` 的 `get_bms_sequence_data`。源位置，不是聚类时间线。
    private static func testSequence() {
        require(
            BmhelperSequence.menuTitle == "Copy BMS sequence to clipboard (&S)",
            "sequence menu"
        )
        require(
            BmhelperSequence.header == "BMSE ClipBoard Object Data Format\r\n",
            "sequence header"
        )
        require(BmhelperSequence.pulse(position: 0, quantize: 480) == 0, "pulse 0")
        require(BmhelperSequence.pulse(position: 480, quantize: 480) == 48, "pulse 48")
        require(
            BmhelperSequence.line(lane: 1, pulse: 0, zz: 1) == "101000000001\r\n",
            "line lane 1 pulse 0"
        )
        require(
            BmhelperSequence.line(lane: 1, pulse: 48, zz: 1) == "101000000481\r\n",
            "line lane 1 pulse 48"
        )
        require(
            BmhelperSequence.line(lane: 2, pulse: 0, zz: 1) == "102000000001\r\n",
            "line lane 2"
        )
        require(
            BmhelperSequence.line(lane: 1, pulse: 0, zz: 10) == "1010000000010\r\n",
            "line zz 0A"
        )
        require(
            BmhelperSequence.zzInteger("01") == 1,
            "zz 01 is 1"
        )
        require(
            BmhelperSequence.zzInteger("0A") == 10,
            "zz 0A is 10"
        )
        require(
            BmhelperSequence.format(
                positions: [0],
                zzStrings: ["01"],
                src2def: [0],
                quantize: 480
            ) == BmhelperSequence.header + "101000000001\r\n",
            "one note at 0"
        )
        require(
            BmhelperSequence.format(
                positions: [0, 0],
                zzStrings: ["01", "01"],
                src2def: [0, 0],
                quantize: 480
            ) == BmhelperSequence.header + "101000000001\r\n" + "102000000001\r\n",
            "two notes same pulse"
        )
        require(
            BmhelperSequence.format(
                positions: [],
                zzStrings: [],
                src2def: [],
                quantize: 480
            ) == BmhelperSequence.header,
            "empty notes header only"
        )
        require(
            BmhelperSequence.shouldCopy(hasProject: false, hasSelection: true) == false,
            "no project no copy"
        )
        require(
            BmhelperSequence.shouldCopy(hasProject: true, hasSelection: false) == false,
            "no selection no copy"
        )
    }

    /// 对照 `division.cpp` 的 `get_div_sequence_data`。时间线位置，不是源 MIDI。
    private static func testDivCopy() {
        require(
            BmhelperDivCopy.menuTitle == "Copy division (&W)",
            "div copy menu"
        )
        require(
            BmhelperDivCopy.line(pulse: 0) == "011000000001\r\n",
            "div line pulse 0"
        )
        require(
            BmhelperDivCopy.line(pulse: 48) == "011000000481\r\n",
            "div line pulse 48"
        )
        require(
            BmhelperDivCopy.format(positions: [0], quantize: 480)
                == BmhelperSequence.header + "011000000001\r\n",
            "one timeline at 0"
        )
        require(
            BmhelperDivCopy.format(positions: [0, 480], quantize: 480)
                == BmhelperSequence.header + "011000000001\r\n" + "011000000481\r\n",
            "two timeline notes"
        )
        require(
            BmhelperDivCopy.format(positions: [], quantize: 480) == BmhelperSequence.header,
            "empty timeline header only"
        )
    }

    /// 对照 `frame.cpp` 菜单和 `divedit.cpp` `_SmfOut` 文案。
    private static func testSmfOut() {
        require(
            BmhelperSmfOut.menuTitle == "Write modified MIDI File (&M)...",
            "smf out menu"
        )
        require(
            BmhelperSmfOut.failedMessage == "Failed to export MIDI file.",
            "smf out failed"
        )
        require(BmhelperSmfOut.saveTitle == "MIDI files", "smf out save title")
        require(BmhelperSmfOut.defaultExtension == "mid", "smf out mid")
        require(
            BmhelperSmfOut.shouldExport(hasProject: false, hasSelection: true) == false,
            "no project no export"
        )
        require(
            BmhelperSmfOut.shouldExport(hasProject: true, hasSelection: false) == false,
            "no selection no export"
        )
        require(
            BmhelperSmfOut.shouldExport(hasProject: true, hasSelection: true),
            "export when selected"
        )
    }

    /// 对照 `divedit.cpp` 右侧五个按钮；`divview.cpp` 左右分栏。
    private static func testRightPane() {
        require(
            BmhelperRightPane.titles == [
                "Write MIDI File",
                "Copy woslicer II Cutting Positions",
                "Open built-in audio cutter",
                "Open BMS WAV definitions...",
                "Copy BMS Data to Clipboard"
            ],
            "right titles"
        )
        require(BmhelperRightPane.proportions == [2, 1, 1, 2, 2], "right proportions")
        require(BmhelperRightPane.rightPaneWidthHint == 200, "right width hint")
        require(BmhelperRightPane.minimumPaneSize == 125, "right min pane")
        require(
            BmhelperRightPane.buttonsEnabled(hasProject: false, hasSelection: true) == false,
            "no project disables"
        )
        require(
            BmhelperRightPane.buttonsEnabled(hasProject: true, hasSelection: false) == false,
            "no selection disables"
        )
        require(
            BmhelperRightPane.buttonsEnabled(hasProject: true, hasSelection: true) == true,
            "selected enables"
        )
        require(
            BmhelperRightPane.clipboardUnavailable == "Clipboard is not available.",
            "clipboard unavailable"
        )
        require(
            BmhelperSequence.clipboardUnavailable == BmhelperRightPane.clipboardUnavailable,
            "sequence shares clipboard text"
        )
        require(
            BmhelperDivCopy.clipboardUnavailable == BmhelperRightPane.clipboardUnavailable,
            "div copy shares clipboard text"
        )
    }

    /// 对照 `defview.cpp`：格宽 30，只显示 zz / div，不点选。
    private static func testDefinitionView() {
        require(BmhelperDefinitionView.itemWidth == 30, "item width 30")

        let one = BmhelperDefinitionView.items([(zz: "01", div: 0)])
        require(one.count == 1, "one item")
        require(BmhelperDefinitionView.virtualWidth(one) == 30, "one virtual width 30")
        require(one[0].zz == "01", "one zz 01")
        require(one[0].divText == "0", "one div text 0")
        require(one[0].selected == false, "reload selected false")

        let two = BmhelperDefinitionView.items([(zz: "01", div: 0), (zz: "02", div: 1)])
        require(two.count == 2, "two items")
        require(BmhelperDefinitionView.virtualWidth(two) == 60, "two virtual width 60")

        require(BmhelperDefinitionView.zzPoint(index: 0, scrollPos: 0) == .init(x: 3, y: 3), "cell 0 zz")
        require(BmhelperDefinitionView.divPoint(index: 0, scrollPos: 0) == .init(x: 3, y: 20), "cell 0 div")
        require(BmhelperDefinitionView.zzPoint(index: 1, scrollPos: 0) == .init(x: 33, y: 3), "cell 1 zz scroll 0")
        require(BmhelperDefinitionView.zzPoint(index: 1, scrollPos: 1) == .init(x: 3, y: 3), "cell 1 zz scroll 1")

        let emptyList = BmhelperDefinitionView.items([])
        require(emptyList.isEmpty, "empty list items")
        require(BmhelperDefinitionView.virtualWidth(emptyList) == 0, "empty list width")
        let noDivision = BmhelperDefinitionView.items(nil)
        require(noDivision.isEmpty, "nil items")
        require(BmhelperDefinitionView.virtualWidth(noDivision) == 0, "nil width")

        require(BmhelperDefinitionView.page(clientWidth: 90) == 3, "page 90")
        require(BmhelperDefinitionView.page(clientWidth: 89) == 2, "page 89")

        require(
            BmhelperDefinitionView.clampScroll(pos: 5, count: 4, page: 3) == 1,
            "clamp 5 → 1"
        )
        require(
            BmhelperDefinitionView.clampScroll(pos: -1, count: 4, page: 3) == 0,
            "clamp -1 → 0"
        )
        require(
            BmhelperDefinitionView.clampScroll(pos: 5, count: 3, page: 3) == 0,
            "count == page → 0"
        )
        require(
            BmhelperDefinitionView.clampScroll(pos: 2, count: 2, page: 3) == 0,
            "count < page → 0"
        )

        // 对照 BmhelperTranspose.up(zzEnabled: true, ["01","02"]) → ["00","01"]
        let afterUp = BmhelperDefinitionView.items([(zz: "00", div: 0), (zz: "01", div: 1)])
        require(afterUp.map(\.zz) == ["00", "01"], "up zzOn 01,02 → 00,01 on bar")
    }

    /// sash `-60` 只说明下面短。重力在钢琴卷。
    private static func testDivisionEditorSash() {
        require(BmhelperDivisionEditor.sashGravity == 1, "editor sash gravity 1")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
