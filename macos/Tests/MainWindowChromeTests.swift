import Foundation

@main
struct MainWindowChromeTests {
    static func main() {
        require(MainWindowChrome.clientSize == CGSize(width: 1082, height: 730), "client size must match Designer")
        require(MainWindowChrome.optionsScrollWidth == 200 && MainWindowChrome.resizerWidth == 6, "options column geometry changed")
        require(MainWindowChrome.toolbarHeight == 25 && MainWindowChrome.statusHeight == 22 && MainWindowChrome.scrollbarSize == 17,
                "chrome strip sizes changed")
        require(MainToolbarLayout.height == 25, "TBMain height must be 25")
        require(MainToolbarLayout.frame(named: "TBNew") == CGRect(x: 0, y: 1, width: 23, height: 22), "TBNew frame")
        require(MainToolbarLayout.frame(named: "TBOpen") == CGRect(x: 23, y: 1, width: 32, height: 22), "TBOpen split frame")
        require(MainToolbarLayout.frame(named: "TBSelect") == CGRect(x: 485, y: 1, width: 23, height: 22), "TBSelect F2 frame")
        require(MainToolbarLayout.frame(named: "TBWrite") == CGRect(x: 508, y: 1, width: 23, height: 22), "TBWrite F3 frame")
        require(MainToolbarLayout.frame(named: "TBTheme") == CGRect(x: 710, y: 1, width: 29, height: 22), "TBTheme frame")
        require(MainToolbarLayout.frame(named: "POBStorm") == nil, "Storm is hidden at startup")
        require(MainToolbarLayout.totalWidth == 739, "visible toolbar width excluding Storm")
        require(MainToolbarLayout.items.first { $0.name == "TBNTInput" }?.checked == true, "NTInput starts checked")
        require(MainToolbarLayout.items.first { $0.name == "TBSelect" }?.checked == true, "Select starts checked")

        require(MainWindowChrome.statusFields.count == 11, "FStatus field count")
        require(MainWindowChrome.statusFieldTotalWidth == 887, "FStatus field widths")
        require(MainWindowChrome.statusFields[0].text == "BPM" && MainWindowChrome.statusFields[8].text == "Length = 0",
                "FStatus default captions")

        let state = OptionsSidebarState.runtimeDefault
        require(state.height(of: .header) == 206, "Header starts as Part1 + Expand, Part2 hidden")
        require(state.height(of: .grid) == 172, "Grid starts as Part1 + Expand, Part2 hidden")
        require(state.height(of: .waveform) == 20, "WaveForm starts collapsed")
        require(state.height(of: .wav) == 232, "WAV list starts without Expand options")
        require(state.height(of: .bmp) == 232, "BMP list starts without Expand options")
        require(state.height(of: .beat) == 20 && state.height(of: .expansion) == 20, "Beat and Expansion start collapsed")
        require(state.documentHeight == 902, "default options document height")
        let defaultFrames = state.frames()
        require(defaultFrames.map(\.section) == OptionsSectionID.allCases, "sidebar sections keep VB top to bottom order")
        require(defaultFrames[0].frame == CGRect(x: 0, y: 0, width: 183, height: 206), "Header starts at document top")
        require(defaultFrames[1].frame.minY == 206 && defaultFrames[2].frame.minY == 378, "Grid and WaveForm follow Header without overlap")
        var expandedExpansion = state
        expandedExpansion.switchOn[.expansion] = true
        require(expandedExpansion.height(of: .expansion) == 270, "Expansion inner is TExpansion 245 plus resizer 5")
        var expandedBeat = state
        expandedBeat.switchOn[.beat] = true
        require(expandedBeat.height(of: .beat) == 256, "Beat Part1 is Designer TableLayoutPanel7 54")
        expandedBeat.part2Visible[.beat] = true
        require(expandedBeat.height(of: .beat) == 332, "Beat Part2 is Designer POBeatPart2 76")
        require(MainWindowChrome.headerPart1Rows.map(\.label) == ["Title", "Artist", "Genre", "BPM", "Player", "Rank", "Play Level"],
                "Header Part1 labels")
        require(MainWindowChrome.headerPart2Rows.map(\.label) == [
            "SubTitle", "SubArtist", "Stage File", "Banner", "Back BMP", "Difficulty", "ExRank", "Total", "Comment", "LnObj"
        ], "Header Part2 labels")
        require(MainWindowChrome.headerPart1Rows.first { $0.key == "PLAYER" }?.enabled == true, "PLAYER is editable")
        require(MainWindowChrome.headerPart2Rows.first { $0.key == "STAGEFILE" }?.enabled == true, "STAGEFILE is editable")
        require(MainWindowChrome.headerPart2Rows.first { $0.key == "LNOBJ" }?.enabled == true, "LNOBJ is editable")
        require(LegacyHeaderFields.popupIndex(key: "PLAYER", stored: "2") == 1, "PLAYER 2 is Couple Play")
        require(LegacyHeaderFields.storedValue(key: "PLAYER", popupIndex: 0) == "1", "PLAYER index 0 writes 1")
        require(LegacyHeaderFields.popupIndex(key: "LNOBJ", stored: "") == 0, "None is index 0")
        require(LegacyHeaderFields.popupIndex(key: "LNOBJ", stored: "ZZ") == 1295, "ZZ is last token")
        require(LegacyHeaderFields.storedValue(key: "LNOBJ", popupIndex: 0) == "", "None writes empty")
        require(LegacyHeaderFields.storedValue(key: "LNOBJ", popupIndex: 1) == "01", "index 1 writes 01")
        require(LegacyHeaderFields.storedValue(key: "LNOBJ", popupIndex: 1295) == "ZZ", "last index writes ZZ")
        require(LegacyHeaderFields.popupIndex(key: "RANK", stored: "") == 3, "missing RANK shows Easy")
        require(LegacyHeaderFields.storedValue(key: "RANK", popupIndex: 3) == "3", "RANK Easy writes 3")
        require(LegacyHeaderFields.popupIndex(key: "DIFFICULTY", stored: "") == 0, "missing DIFFICULTY is None")

        require(BMS36Token.encode(1) == "01" && BMS36Token.encode(10) == "0A" && BMS36Token.encode(1295) == "ZZ",
                "C10to36 token encoding")
        require(BMS36Token.decode("01") == 1 && BMS36Token.decode("A") == 10 && BMS36Token.decode("ZZ") == 1295,
                "C36to10 token decoding")
        require(BMS36Token.all.count == 1295, "LWAV/LBMP fill 1...1295")
        require(MainWindowChrome.pixelsPerQuarterBeat(gridHeight: 1) == 48, "default gxHeight 1 maps to 48 px")

        require(MainWindowChrome.appTitle == "\u{03BC}BMSC Editor", "AssemblyTitle is μBMSC Editor")
        require(MainWindowChrome.appTitle.unicodeScalars.first?.value == 0x03BC, "mu is U+03BC, not U+00B5")
        require(MainWindowChrome.versionText(major: 3, minor: 2, build: 1) == "3.2.1", "AssemblyVersion 3.2.1.0 drops Revision")
        require(MainWindowChrome.versionText(major: 3, minor: 2, build: 0) == "3.2", "Build 0 is omitted")
        require(MainWindowChrome.fileTitle("/Users/me/song.bms") == "song.bms", "POSIX last segment")
        require(MainWindowChrome.fileTitle("C:\\charts\\song.bme") == "song.bme", "Windows last segment")
        require(MainWindowChrome.fileTitle("Untitled.bms") == "Untitled.bms", "bare name stays")
        require(MainWindowChrome.fileTitle("") == "Untitled.bms", "empty BMS path is Untitled.bms")
        require(MainWindowChrome.fileTitle("", untitled: MainWindowChrome.untitledBMSONFileName) == "Untitled.bmson",
                "empty BMSON path is Untitled.bmson")
        require(
            MainWindowChrome.windowTitle(fileName: "Untitled.bms", isSaved: true)
                == "Untitled.bms - \u{03BC}BMSC Editor 3.2.1",
            "clean untitled BMS title"
        )
        require(
            MainWindowChrome.windowTitle(fileName: "Untitled.bms", isSaved: false)
                == "*Untitled.bms - \u{03BC}BMSC Editor 3.2.1",
            "dirty untitled BMS title"
        )
        require(
            MainWindowChrome.windowTitle(fileName: "/tmp/a.bmson", isSaved: true)
                == "a.bmson - \u{03BC}BMSC Editor 3.2.1",
            "saved BMSON uses real file name"
        )
        require(
            MainWindowChrome.windowTitle(fileName: "", isSaved: true, untitled: MainWindowChrome.untitledBMSONFileName)
                == "Untitled.bmson - \u{03BC}BMSC Editor 3.2.1",
            "clean untitled BMSON title"
        )
        require(MainWindowChrome.saveOnExitPrompt == "Do you want to save changes?", "SaveOnExit body")
        require(
            MainWindowChrome.saveOnExitPromptShutdown
                == "You should tell me if you want to save changes before closing the computer. -_,-",
            "SaveOnExit1 whole sentence"
        )
        require(
            MainWindowChrome.saveOnExitPromptTaskManager
                == "You still need to tell me if you want to save changes even though you are closing the application with task manager. -_,-",
            "SaveOnExit2 whole sentence"
        )
        require(MainWindowChrome.saveOnExitYes == "Yes", "YesNoCancel Yes")
        require(MainWindowChrome.saveOnExitNo == "No", "YesNoCancel No")
        require(MainWindowChrome.saveOnExitCancel == "Cancel", "YesNoCancel Cancel")
        require(
            MainWindowChrome.saveOnExitDecision(isSaved: true, choice: .yes) == .proceedClean,
            "clean chart does not ask"
        )
        require(
            MainWindowChrome.saveOnExitDecision(isSaved: false, choice: .yes) == .proceedSave,
            "dirty Yes saves"
        )
        require(
            MainWindowChrome.saveOnExitDecision(isSaved: false, choice: .no) == .proceedDiscard,
            "dirty No continues without saving"
        )
        require(
            MainWindowChrome.saveOnExitDecision(isSaved: false, choice: .cancel) == .abort,
            "dirty Cancel aborts"
        )
        require(
            MainWindowChrome.saveOnExitMessage(isSystemShutdown: false) == MainWindowChrome.saveOnExitPrompt,
            "ordinary path keeps SaveOnExit"
        )
        require(
            MainWindowChrome.saveOnExitMessage(isSystemShutdown: true) == MainWindowChrome.saveOnExitPromptShutdown,
            "shutdown uses SaveOnExit1"
        )
        require(
            MainWindowChrome.windowTitle(fileName: "Untitled.bms", isSaved: true)
                == "Untitled.bms - \u{03BC}BMSC Editor 3.2.1",
            "clean untitled BMS title stays"
        )
        require(MainWindowChrome.clientSize == CGSize(width: 1082, height: 730), "client size fixture stays")
        require(MainWindowChrome.toolbarHeight == 25, "toolbar height fixture stays")

        let loc0 = LegacyStatus.location(vposMod: 0, measureLength: 192, vPosition: 0, measureIndex: 0)
        require(loc0.fsp1 == "0 / 16  ", "vpos 0 FSP1")
        require(loc0.fsp2 == "0 / 192  ", "vpos 0 FSP2")
        require(loc0.fsp3 == "1 / 1  ", "vpos 0 FSP3")
        require(loc0.fsp4 == "0  ", "vpos 0 FSP4")
        require(loc0.fsm == "000", "vpos 0 FSM")

        let loc96 = LegacyStatus.location(vposMod: 96, measureLength: 192, vPosition: 96, measureIndex: 0)
        require(loc96.fsp1 == "8 / 16  ", "vpos 96 FSP1")
        require(loc96.fsp2 == "96 / 192  ", "vpos 96 FSP2")
        require(loc96.fsp3 == "1 / 2  ", "vpos 96 FSP3")
        require(loc96.fsp4 == "96  ", "vpos 96 FSP4")
        require(loc96.fsm == "000", "vpos 96 FSM")

        let loc192 = LegacyStatus.location(vposMod: 0, measureLength: 192, vPosition: 192, measureIndex: 1)
        require(loc192.fsp1 == "0 / 16  ", "vpos 192 FSP1")
        require(loc192.fsm == "001", "vpos 192 FSM")
        require(loc192.fsp4 == "192  ", "vpos 192 FSP4")

        let header120 = [LegacyStatus.headerBPMNote(120)]
        require(LegacyStatus.timeF4(LegacyStatus.timeFromVPosition(0, bpmNotes: header120)) == "0.0000", "time at 0")
        require(LegacyStatus.timeF4(LegacyStatus.timeFromVPosition(48, bpmNotes: header120)) == "0.5000", "time at 48")
        require(LegacyStatus.timeF4(LegacyStatus.timeFromVPosition(192, bpmNotes: header120)) == "2.0000", "time at 192")
        require(
            LegacyStatus.timeF4(
                LegacyStatus.timeFromVPosition(
                    96,
                    bpmNotes: header120,
                    stopNotes: [LegacyStatus.TimingNote(vPosition: 48, value: 480_000)]
                )
            ) == "1.5000",
            "time at 96 with STOP 48"
        )

        require(LegacyStatus.writeFSW(slot: 0) == "01", "write slot 0 is 01")
        require(LegacyStatus.labelFSW(value: 10_000, numeric: false) == "01", "label 01")
        require(LegacyStatus.labelFSW(value: 1_400_000, numeric: true) == "140", "numeric 140")

        let idle = LegacyStatus.selectFields(
            mouseVPosition: 0,
            vposMod: 0,
            measureLength: 192,
            measureIndex: 0,
            columnTitle: "A1"
        )
        require(idle.fst == "" && idle.fsh == "" && idle.fse == "" && idle.fsw == "", "select idle clears FST/FSH/FSE/FSW")

        require(
            LegacyStatus.selectFST(ntInput: true, length: 192, longNote: true) == "Length = 192",
            "select NT long Length = 192"
        )
        require(LegacyStatus.hiddenText(true) == "Hidden", "select hover Hidden")
        require(LegacyStatus.errorText(true) == "Error", "select hover Error")

        let writeNT = LegacyStatus.writeFields(
            mouseVPosition: 48,
            vposMod: 48,
            measureLength: 192,
            measureIndex: 0,
            columnTitle: "A1",
            slot: 0,
            tempLength: 48,
            ntInput: true,
            shift: false,
            control: false
        )
        require(writeNT.fsw == "01" && writeNT.fst == "48", "write NT slot 0 TempLength 48")

        require(LegacyStatus.writeFST(ntInput: false, tempLength: 0, shift: true) == "LongNote", "write non-NT Shift")
        require(LegacyStatus.hiddenText(true) == "Hidden", "write Control Hidden")

        require(
            MainWindowChrome.windowTitle(fileName: "Untitled.bms", isSaved: true)
                == "Untitled.bms - \u{03BC}BMSC Editor 3.2.1",
            "clean untitled BMS title stays after MU-STATUS"
        )
        require(MainWindowChrome.saveOnExitPrompt == "Do you want to save changes?", "saveOnExit stays after MU-STATUS")
        print("MainWindowChromeTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
