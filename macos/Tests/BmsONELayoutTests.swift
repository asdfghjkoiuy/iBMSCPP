import Foundation

@main
struct BmsONELayoutTests {
    static func main() {
        testMainWindowClient()
        testSequenceFrames()
        testStatusAndDialogs()
        testDefaults()
        testGridAndExportDefaults()
        testGridSettingModel()
        testPreferencesDefaultsAndConversions()
        testSelectedObjectsCopy()
        testVisibleRangeExtended()
        testNoteDarken()
        testSnapToGrid()
        testPreviewDelayAndDuration()
        testMasterView()
        testViewMode()
        testZoom()
        testSoundChannelLanes()
        testFooter()
        testScratch()
        testLaneOrder()
        testPlainLanes()
        testColorScheme()
        testWheel()
        testStatus()
        testObjectHint()
        testInfoDock()
        testInfoExtraFields()
        testExternalViewer()
        testAbout()
        print("BmsONELayoutTests passed")
    }

    private static func testMainWindowClient() {
        require(BmsONEMainWindowLayout.clientSize == CGSize(width: 960, height: 640), "main client 960x640")
        require(BmsONEMainWindowLayout.channelDockWidth == 334, "Channel dock width")
        require(BmsONEMainWindowLayout.statusBarHeight == 18, "status BaseHeight")
        require(BmsONEMainWindowLayout.toolBarIconSize == CGSize(width: 18, height: 18), "toolbar icon")
        require(
            BmsONEMainWindowLayout.sequenceViewFrame
                == CGRect(x: 334, y: 0, width: 626, height: 622),
            "sequence view after dock and status"
        )
        require(
            BmsONEMainWindowLayout.dockColumnFrame
                == CGRect(x: 0, y: 0, width: 334, height: 622),
            "left dock column"
        )
        require(
            BmsONEMainWindowLayout.statusBarFrame
                == CGRect(x: 0, y: 622, width: 960, height: 18),
            "status bar"
        )
        require(
            BmsONEWindowTitle.sourceTitle(filePath: nil) == "untitled [*] - BmsONE",
            "untitled title template"
        )
        require(BmsONEWindowTitle.appName == "BmsONE", "APP_NAME")
        require(BmsONEWindowTitle.version == "beta 0.2.1", "APP_VERSION_STRING")
        require(BmsONEMainWindowLayout.transferToKeyTitle == "Move to Key Lanes", "Move to Key")
        require(BmsONEMainWindowLayout.transferToBgmTitle == "Move to BGM Lanes", "Move to BGM")
        require(
            BmsONEMainWindowLayout.separateLayeredTitle == "Separate Layered Notes",
            "Separate Layered Notes"
        )
        require(BmsONEMainWindowLayout.editModeTitle == "Edit Mode", "Edit Mode")
        require(BmsONEMainWindowLayout.writeModeTitle == "Write Mode", "Write Mode")
        require(BmsONEMainWindowLayout.channelAddTitle == "Add...", "Channel Add")
        require(
            BmsONEMainWindowLayout.channelFindActiveOnlyTitle == "Active Channels Only",
            "Active Channels Only"
        )
        require(
            BmsONEMainWindowLayout.channelFindHideOthersTitle == "Show Hit Channels Only",
            "Show Hit Channels Only"
        )
        require(
            BmsONEMainWindowLayout.darkenInactiveChannelsTitle
                == "Darken Notes in Inactive Channels",
            "Darken Notes title"
        )
        require(BmsONEMainWindowLayout.snapToGridTitle == "Snap to Grid", "Snap to Grid title")
        require(BmsONEMainWindowLayout.viewModeMenuTitle == "View Mode", "View Mode title")
        require(BmsONEViewMode.menuTitle == "View Mode", "View Mode menu")
        require(BmsONEMainWindowLayout.zoomMenuTitle == "Zoom", "Zoom menu title")
        require(BmsONEMainWindowLayout.zoomInTitle == "Zoom In", "Zoom In title")
        require(BmsONEMainWindowLayout.zoomOutTitle == "Zoom Out", "Zoom Out title")
        require(BmsONEMainWindowLayout.zoomResetTitle == "Reset", "Zoom Reset title")
        require(BmsONEZoom.menuTitle == "Zoom", "Zoom menu")
        require(
            BmsONEMainWindowLayout.soundChannelLanesMenuTitle == "Sound Channel Lanes Display",
            "Sound Channel Lanes Display"
        )
        require(BmsONEMainWindowLayout.soundChannelLaneNormalTitle == "Normal", "Normal")
        require(BmsONEMainWindowLayout.soundChannelLaneCompactTitle == "Compact", "Compact")
        require(BmsONEMainWindowLayout.soundChannelLaneSimpleTitle == "Simple", "Simple")
        require(BmsONEMainWindowLayout.channelDeleteTitle == "Delete", "Channel Delete")
        require(
            BmsONEMainWindowLayout.channelPreviewSourceTitle == "Preview Source Sound",
            "Preview Source"
        )
        require(
            BmsONEMainWindowLayout.clearMasterCacheTitle == "Clear Master Cache",
            "Clear Master Cache"
        )
    }

    private static func testSequenceFrames() {
        require(BmsONESequenceLayout.timeLineWidth == 54, "20+34")
        require(BmsONESequenceLayout.headerHeight == 0, "headerHeight")
        require(BmsONESequenceLayout.masterLaneWidth == 64, "master lane")
        require(BmsONESequenceLayout.defaultFooterHeight == 60, "48+6*2")
        require(BmsONESequenceLayout.beat7kPlayingWidth == 210, "Beat 7-key playing width")
        require(BmsONESequenceLayout.largeSoundChannelWidth == 64, "normal BGM lane")
        require(BmsONESequenceLayout.smallSoundChannelWidth == 32, "compact/simple BGM lane")
        require(BmsONESequenceLayout.miniMapWidth == 50, "minimap")

        let frames = BmsONESequenceLayout.mainWindowFrames
        require(frames.timeLine == CGRect(x: 334, y: 0, width: 54, height: 562), "timeline")
        require(frames.masterLane == CGRect(x: 388, y: 0, width: 64, height: 562), "master lane frame")
        require(frames.playingPane == CGRect(x: 452, y: 0, width: 210, height: 562), "playing pane")
        require(frames.footerCorner == CGRect(x: 334, y: 562, width: 54, height: 60), "footer corner")
        require(frames.footerMaster == CGRect(x: 388, y: 562, width: 64, height: 60), "footer master")
        require(frames.footerPlaying == CGRect(x: 452, y: 562, width: 210, height: 60), "footer playing")
    }

    private static func testStatusAndDialogs() {
        require(BmsONEStatusBarLayout.absoluteLocation == CGSize(width: 120, height: 18), "Abs")
        require(BmsONEStatusBarLayout.location == CGSize(width: 180, height: 18), "Loc")
        require(BmsONEStatusBarLayout.realTime == CGSize(width: 160, height: 18), "Time")
        require(BmsONEStatusBarLayout.lane == CGSize(width: 100, height: 18), "Lane")
        require(BmsONEStatusBarLayout.objectHint == CGSize(width: 320, height: 18), "object hint")
        require(BmsONEDialogLayout.bmsImportSize == CGSize(width: 640, height: 480), "BMS Import")
        require(BmsONEDialogLayout.bmsImportTitle == "BMS Import", "BMS Import title")
        require(BmsONEDialogLayout.bmsImportNextTitle == "Next", "Next")
        require(BmsONEDialogLayout.bmsImportFinishTitle == "Finish", "Finish")
        require(BmsONEDialogLayout.bmsImportCancelTitle == "Cancel", "Cancel")
        require(BmsONEDialogLayout.bmsImportSkipTitle == "Skip Questions", "Skip Questions")
        require(BmsONEDialogLayout.bmsImportProgressMaximum == 100, "progress max")
        require(BmsONEDialogLayout.bmsImportSucceeded == "Succeeded to import BMS.", "success text")
        require(BmsONEDialogLayout.gridSettingSize == CGSize(width: 600, height: 400), "Grid Setting")
        require(BmsONEDialogLayout.exportWavSize == CGSize(width: 480, height: 320), "Export WAV")
        require(BmsONEDialogLayout.gridSettingTitle == "Grid Setting", "Grid Setting title")
        require(BmsONEDialogLayout.gridSettingMenuTitle == "Grid Setting...", "Grid Setting menu")
        require(BmsONEDialogLayout.gridColumnDivision == "Division", "Division header")
        require(BmsONEDialogLayout.gridColumnLength == "Length", "Length header")
        require(BmsONEDialogLayout.gridColumnLabel == "Label", "Label header")
        require(BmsONEDialogLayout.gridColumnAux == "Aux. Grid", "Aux header")
        require(BmsONEDialogLayout.convertResolutionTitle == "Convert Resolution", "Convert Resolution title")
        require(BmsONEDialogLayout.convertResolutionMenuTitle == "Convert Resolution...", "Convert Resolution menu")
        require(BmsONEDialogLayout.convertResolutionCurrentLabel == "Current resolution:", "current label")
        require(BmsONEDialogLayout.convertResolutionNewLabel == "New resolution:", "new label")
        require(BmsONEDialogLayout.convertResolutionWarningTitle == "Warning", "warning title")
        require(
            BmsONEDialogLayout.convertResolutionWarning
                == "Some information will be lost through this conversion and it is IRREVERSIBLE. Are you sure?",
            "irreversible warning"
        )
        require(BmsONEDialogLayout.convertResolutionMinimum == 48, "min 48")
        require(BmsONEDialogLayout.convertResolutionMaximum == 24000, "max 24000")
        require(BmsONEResolutionConvert.parse("480") == 480, "parse 480")
        require(BmsONEResolutionConvert.parse("480abc") == nil, "parse junk")
        require(!BmsONEResolutionConvert.isAllowed(47), "47 rejected")
        require(BmsONEDialogLayout.exportWavTitle == "Export WAV", "Export WAV title")
        require(BmsONEDialogLayout.exportRefreshTitle == "Refresh Master Cache", "refresh cache")
        require(BmsONEDialogLayout.exportGainSteps == 200, "SliderGainSteps")
        require(BmsONEDialogLayout.exportDefaultGain == 100, "default half")
        require(BmsONEDialogLayout.exportClipTitles == ["Soft Clip", "Hard Clip", "Normalize"], "clip items")
        require(BmsONEDialogLayout.exportUntitledBase == "NewProject", "untitled wav base")
        require(BmsONEDialogLayout.exportSampleRate == 44100, "MasterCache SampleRate")
        require(BmsONEDialogLayout.exportCannotOpen == "Cannot open file.", "Cannot open file")
        require(BmsONEDialogLayout.exportComplete == "Export complete.", "Export complete")
        require(BmsONEDialogLayout.exportNoSample == "No sample was given.", "No sample")
        require(BmsONEDialogLayout.preferencesTitle == "Preferences", "Preferences title")
        require(BmsONEDialogLayout.preferencesMenuTitle == "Preferences...", "Preferences menu")
        require(BmsONEDialogLayout.preferencesCloseTitle == "Close", "Close")
        require(BmsONEDialogLayout.preferencesGeneralTitle == "General", "General")
        require(BmsONEDialogLayout.preferencesEditTitle == "Edit", "Edit")
        require(BmsONEDialogLayout.preferencesPreviewTitle == "Preview", "Preview")
        require(BmsONEDialogLayout.preferencesBmsImportTitle == "BMS Import", "BMS Import")
        require(BmsONEDialogLayout.preferencesPreferExModes == "Prefer 7/14/9key to 5/10/5key.", "prefer ex")
        require(BmsONEDialogLayout.preferencesSize == CGSize(width: 640, height: 420), "working size")
        require(BmsONEDialogLayout.preferencesListMaximumWidth == 180, "list max 180")
        require(BmsONEDialogLayout.preferencesIconSize == CGSize(width: 32, height: 32), "icon 32")
        require(BmsONEImportQuestion.prompt == "Select game mode:", "AskGameMode prompt")
        require(BmsONEImportQuestion.encodingPrompt == "Select text encoding:", "AskTextEncoding")
        require(BmsONEImportQuestion.randomPrompt == "Select random value:", "AskRandomValue")
        require(BmsONETextEncoding.localeDefault.displayName == "(default)", "default codec title")
        require(BmsONETextEncoding.shiftJIS.rawValue == "Shift-JIS", "Shift-JIS name")
        require(BmsONETextEncoding.utf8.rawValue == "UTF-8", "UTF-8 name")
        require(BmsONETextEncoding.allCases.count == 3, "three codecs")
        require(
            BmsONEImportQuestion.resolvedEncoding(skipQuestions: true, selected: .shiftJIS) == .localeDefault,
            "Skip uses empty codec"
        )
        require(
            BmsONEImportQuestion.resolvedRandomValue(skipQuestions: true, isRandom: true, selected: 2) == 1,
            "Skip RANDOM is 1"
        )
        require(
            BmsONEImportQuestion.resolvedRandomValue(skipQuestions: false, isRandom: true, selected: 2) == 0,
            "Random checkbox is 0"
        )
        require(BmsONEDialogLayout.bmsImportRandomCheckboxTitle == "Random", "Random checkbox")
        require(BmsONEDialogLayout.bmsImportGameModeOkMark == "O", "O")
        require(BmsONEDialogLayout.bmsImportGameModeErrorMark == "!", "!")
        require(BmsONEBmsMode.mode7k.longName == "7key (BMS)", "7k long name")
        require(BmsONEBmsMode.modePms5k.longName == "5key (PMS)", "pms 5k long name")
        require(
            BmsONEImportQuestion.resolvedMode(skipQuestions: true, detected: .mode5k, selected: .mode7k) == .mode5k,
            "Skip uses GetMode"
        )
        require(
            BmsONEImportQuestion.resolvedMode(skipQuestions: false, detected: .mode5k, selected: .mode7k) == .mode7k,
            "Next uses selected radio"
        )
        let choices = BmsONEImportQuestion.choices(errorByMode: [.mode5k: true, .mode7k: false])
        require(choices[0].mark == "!" && choices[1].mark == "O", "O / !")
        require(choices.count == 6, "six modes")
    }

    private static func testDefaults() {
        require(BmsONEInfoDefaults.modeHint == "beat-7k", "modeHint")
        require(BmsONEInfoDefaults.resolution == 240, "DefaultResolution")
        require(BmsONEInfoDefaults.initialBpm == 120, "initBpm")
        require(BmsONEInfoDefaults.judgeRank == 100, "judgeRank")
        require(BmsONEInfoDefaults.total == 100, "total")
        require(BmsONEInfoDefaults.level == 1, "level")
        let empty = BmsONEEmptyDocument()
        require(empty.filePath == nil && empty.isModified == false, "empty document stand-in")
        require(empty.title.isEmpty, "empty BMSON title")
        require(empty.initialBpm == BmsONEInfoDefaults.initialBpm, "empty BMSON initBPM")
        require(empty.modeHint == "beat-7k", "empty BMSON modeHint")
        require(empty.resolution == 240, "empty BMSON resolution")
        require(BmsONEFileTypes.bmsExtensions == ["bms", "bme", "bml", "pms"], "BMS Open filters")

        let pane = CGRect(x: 0, y: 0, width: 210, height: 100)
        let lanes = BmsONEPlayingLaneLayout.laneFrames(in: pane)
        require(lanes.count == 8, "beat-7k lane count")
        require(lanes[0].width == 32 && lanes[1].width == 24, "scratch then key widths")
        require(BmsONEPlayingLaneLayout.laneX(at: CGPoint(x: 6, y: 10), in: pane) == 8, "left scratch is Skin x=8")
        require(BmsONEPlayingLaneLayout.laneX(at: CGPoint(x: 40, y: 10), in: pane) == 1, "first key is Skin x=1")
        require(
            BmsONEPlayingLaneLayout.pulseY(at: CGPoint(x: 40, y: 52), in: pane, resolution: 240) == 240,
            "48 px from the bottom is one beat"
        )
    }

    private static func testGridAndExportDefaults() {
        let presets = BmsONEGridSize.defaultPresets
        require(presets.map(\.displayText) == ["4", "8", "12", "16", "24", "32", "48", "64", "192"], "DefaultGrids text")
        require(BmsONEGridSize.defaultMedium.displayText == "4", "medium 4/4")
        require(BmsONEExportWav.suggestedBaseName(filePath: nil) == "NewProject", "empty path")
        require(
            BmsONEExportWav.suggestedBaseName(filePath: "/tmp/demo.bmson") == "demo",
            "bmson stem"
        )
        let dir = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let first = BmsONEExportWav.uniqueOutputURL(directory: dir, base: "demo", exists: { _ in false })
        require(first.lastPathComponent == "demo.wav", "first wav name")
        let second = BmsONEExportWav.uniqueOutputURL(directory: dir, base: "demo", exists: { $0.lastPathComponent == "demo.wav" })
        require(second.lastPathComponent == "demo_1.wav", "collision suffix")
    }

    /// 对照 `GridSetting` / `UpdateSmallGrid`。不改谱。细格接到 `CGDivide`，辅助格接到 `CGSub`。
    private static func testGridSettingModel() {
        require(BmsONEGridSize(denominator: 16) == BmsONEGridSize(numerator: 8, denominator: 32), "cross-multiply equal")
        require(BmsONEGridSize(denominator: 16).linesPerMeasure == 16, "16 lines")
        require(BmsONEGridSize(numerator: 1, denominator: 8).displayText == "32", "(1)8 still standard 32")
        require(BmsONEGridSize(numerator: 3, denominator: 8).displayText == "(3)8", "custom label")
        require(BmsONEGridSize(numerator: 3, denominator: 8).linesPerMeasure == nil, "custom has no CGDivide")
        require(BmsONEGridSetting.parseComponent(0) == nil, "0 rejected")
        require(BmsONEGridSetting.parseComponent(65537) == nil, "65537 rejected")
        require(BmsONEGridSetting.parseComponent(65536) == 65536, "65536 allowed")

        let defaults = BmsONEGridSettingDraft.makeDefault()
        let inserted = defaults.inserting(at: 0)
        require(inserted.grids.count == 10, "insert copies row")
        require(inserted.grids[0].displayText == "4" && inserted.grids[1].displayText == "4", "copy first")
        let atEnd = defaults.inserting(at: 9)
        require(atEnd.grids.count == 10 && atEnd.grids[9].displayText == "192", "append copies last")
        let emptyInsert = BmsONEGridSettingDraft(grids: [], medium: .defaultMedium).inserting(at: 0)
        require(emptyInsert.grids[0] == .fallbackFine, "empty insert is 16")
        require(defaults.removing(at: 0)?.grids.count == 8, "remove first")
        require(defaults.removing(at: -1) == nil && defaults.removing(at: 9) == nil, "remove bounds")
        require(defaults.selectingMedium(at: 3)?.medium.displayText == "16", "aux 16")
        require(defaults.settingDenominator(at: 3, value: 0) == nil, "d=0")
        require(defaults.settingNumerator(at: 3, value: 65537) == nil, "n overflow")
        require(defaults.settingDenominator(at: 3, value: 32)?.grids[3].displayText == "32", "edit d")

        let restored = inserted.restoringDefault()
        require(restored.grids.map(\.displayText) == defaults.grids.map(\.displayText), "restore")
        require(restored.medium == .defaultMedium, "restore medium")

        let keep = BmsONEGridSetting.accepted(draft: defaults, currentDivision: 16)
        require(keep.division == 16 && keep.subDivision == 4, "keep 16 / medium 4")
        require(keep.fineGrid == BmsONEGridSize.fallbackFine, "keep fine 16")
        let custom = BmsONEGridSetting.accepted(
            draft: BmsONEGridSettingDraft(
                grids: [BmsONEGridSize(numerator: 3, denominator: 8)],
                medium: .defaultMedium
            ),
            currentDivision: 16
        )
        require(custom.fineGrid == BmsONEGridSize(numerator: 3, denominator: 8), "custom fine stays")
        require(custom.division == 16, "custom has no CGDivide")
        var without16 = defaults
        without16.grids.removeAll { $0 == BmsONEGridSize.fallbackFine }
        let snapped = BmsONEGridSetting.accepted(draft: without16, currentDivision: 16)
        require(snapped.division == 4, "no 16 falls to first")
        let empty = BmsONEGridSetting.accepted(
            draft: BmsONEGridSettingDraft(grids: [], medium: BmsONEGridSize(denominator: 8)),
            currentDivision: 12
        )
        require(empty.grids.count == 9 && empty.division == 12, "empty list restores defaults, keep 12")
        require(empty.subDivision == 8, "medium 8 -> CGSub 8")

        let text = BmsONEGridSetting.serialize([BmsONEGridSize(denominator: 32)])
        let loaded = BmsONEGridSetting.deserialize(text)
        require(loaded.count == 1 && loaded[0].displayText == "32", "roundtrip 32")
        require(BmsONEGridSetting.deserialize("[]").count == 9, "empty json is defaults")
        require(BmsONEGridSetting.deserialize(#"[{"d":0,"n":4}]"#).count == 9, "zero d dropped")
        require(
            BmsONEGridSetting.deserialize(#"[{"d":24,"n":4},{"d":0,"n":1}]"#).map(\.displayText) == ["24"],
            "skip zero keep 24"
        )

        let suite = UserDefaults(suiteName: "org.ibmsc.native.tests.grid-setting")!
        suite.removePersistentDomain(forName: "org.ibmsc.native.tests.grid-setting")
        BmsONEGridSetting.save([BmsONEGridSize(denominator: 48)], to: suite)
        require(BmsONEGridSetting.load(from: suite).map(\.displayText) == ["48"], "UserDefaults store")
    }

    private static func testPreferencesDefaultsAndConversions() {
        let defaults = BmsONEPreferences()
        require(defaults.languageKey.isEmpty && defaults.languageIndex == 0, "system language")
        require(BmsONEPreferenceFormat.languageKey(index: 1) == "en", "en")
        require(BmsONEPreferenceFormat.languageKey(index: 2) == "ja", "ja")
        require(BmsONEPreferenceFormat.languageIndex("fr") == 0, "unknown language")
        require(defaults.saveFormat == "Default" && defaults.saveJsonFormat == "Default", "save defaults")
        require(
            BmsONEPreferenceFormat.saveFormatTitles == ["Default(1.0)", "Latest(1.0)", "1.0", "0.21"],
            "SaveFormatDescriptionList"
        )
        require(defaults.enableMasterChannel && defaults.showMasterLane && defaults.showMiniMap, "master on")
        require(!defaults.fixMiniMap && defaults.canShowMasterLane && defaults.canShowMiniMap, "CanShow")
        require(defaults.snappedSelectionInEditMode && !defaults.snappedHitTestInEditMode, "edit mode defaults")
        require(defaults.previewDelayRatio == 1 && defaults.previewSmoothing, "preview delay 1")
        require(defaults.singleMaxDuration == 0 && defaults.singleSoftFadeOut, "duration +inf")
        require(!defaults.singleSoftFadeOutEnabled, "+inf disables fade")
        require(defaults.askTextEncoding && defaults.askRandomValues && defaults.askGameMode, "ask defaults")
        require(defaults.minimumResolution == 240 && defaults.maximumResolution == 10000, "resolution defaults")
        require(!defaults.preferExModes && !defaults.skipBetweenRandomAndIf, "GetMode defaults")

        var offMaster = defaults
        offMaster.enableMasterChannel = false
        require(!offMaster.canShowMasterLane && !offMaster.miniMapGroupEnabled, "master off hides")
        offMaster.enableMasterChannel = true
        offMaster.showMiniMap = false
        require(!offMaster.miniMapOpacityEnabled, "no mini map no opacity")
        offMaster.showMiniMap = true
        offMaster.fixMiniMap = true
        require(!offMaster.miniMapOpacityEnabled, "fix disables opacity")

        require(BmsONEPreferenceFormat.delaySlider(ratio: 1) == 8, "delay slider 8")
        require(BmsONEPreferenceFormat.delayRatio(slider: 8) == 1, "delay 1")
        require(BmsONEPreferenceFormat.miniMapOpacitySlider(opacity: 0.67) == 43909, "0.67 * 65536")
        require(BmsONEPreferenceFormat.notePreviewDurations.count == 21, "duration steps")
        require(BmsONEPreferenceFormat.durationIndex(0) == 20, "+inf last")
        require(BmsONEPreferenceFormat.durationTitle(0) == "+inf", "+inf text")
        require(BmsONEPreferenceFormat.durationValue(index: 0) == 0.05, "first 0.05")
        require(
            BmsONEPreferenceFormat.acceptedResolutions(minimumText: "abc", maximumText: "50") == (1, 50),
            "junk min is 1"
        )
        require(
            BmsONEPreferenceFormat.acceptedResolutions(minimumText: "240", maximumText: "0") == (240, 240),
            "max follows min"
        )
        require(
            BmsONEPreferenceFormat.acceptedResolutions(minimumText: "240", maximumText: "2000000") == (240, 1_000_000),
            "cap 1e6"
        )
        require(
            BmsONEPreferenceFormat.fontButtonTitle(family: "System", pointSize: 13, isDefault: true)
                == "Default (System, 13pt)",
            "default font caption"
        )
        require(
            BmsONEPreferenceFormat.fontButtonTitle(family: "HelveticaNeue", pointSize: 12.5, isDefault: false)
                == "HelveticaNeu..., 12.5pt",
            "truncate family"
        )

        let options = defaults.importOptions
        require(
            options.resolvedEncoding(skipQuestions: true, selected: .shiftJIS) == .localeDefault,
            "skip encoding uses empty"
        )
        require(
            options.resolvedRandomValue(skipQuestions: true, isRandom: true, selected: 2) == 1,
            "skip random is 1"
        )
        var randomPrefs = defaults
        randomPrefs.useRandomValues = true
        randomPrefs.defaultTextEncodingKey = "Shift-JIS"
        randomPrefs.askTextEncoding = false
        let askedOff = randomPrefs.importOptions
        require(askedOff.defaultTextEncoding == .shiftJIS, "stored Shift-JIS")
        require(!askedOff.shouldAskEncoding(skipQuestions: false), "ask off")
        require(
            askedOff.resolvedEncoding(skipQuestions: false, selected: .utf8) == .shiftJIS,
            "no ask uses default"
        )
        require(
            askedOff.resolvedRandomValue(skipQuestions: true, isRandom: false, selected: 2) == 0,
            "useRandomValues skip is 0"
        )

        let suiteName = "org.ibmsc.native.tests.bmsone-preferences"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        var stored = BmsONEPreferences()
        stored.languageKey = "ja"
        stored.saveFormat = "0.21"
        stored.saveJsonFormat = "Compact"
        stored.preferExModes = true
        stored.skipBetweenRandomAndIf = true
        stored.minimumResolution = 120
        stored.previewDelayRatio = 0.5
        stored.store(to: suite)
        let loaded = BmsONEPreferences.load(from: suite)
        require(loaded.languageKey == "ja" && loaded.languageIndex == 2, "store ja")
        require(loaded.saveFormat == "0.21" && loaded.saveJsonFormat == "Compact", "store formats")
        require(loaded.preferExModes && loaded.skipBetweenRandomAndIf, "store import flags")
        require(loaded.minimumResolution == 120 && loaded.previewDelayRatio == 0.5, "store numbers")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `NoteEditView`。文案和尺寸提示，不是截图。
    private static func testSelectedObjectsCopy() {
        require(BmsONESelectedObjectsLayout.dockTitle == "Selected Objects", "dock title")
        require(BmsONESelectedObjectsLayout.sizeHint == CGSize(width: 200, height: 180), "size hint")
        require(BmsONESelectedObjectsLayout.sizeHint == BmsONEInfoDefaults.extraFieldsHint, "same 200x180")
        require(BmsONESelectedObjectsLayout.lengthLabel == "Length", "Length")
        require(BmsONESelectedObjectsLayout.extraFieldsTitle == "Extra fields", "Extra fields")
        require(BmsONESelectedObjectsLayout.oneNote == "1 selected note", "one note")
        require(BmsONESelectedObjectsLayout.notesCount(2) == "2 selected notes", "two notes")
        require(BmsONESelectedObjectsLayout.multipleValuesPlaceholder == "multiple values", "placeholder")
        require(BmsONESelectedObjectsLayout.multipleValuesText == "(multiple values)", "mixed extra")
        require(BmsONESelectedObjectsLayout.showExtraFieldsKey == "NoteEditView/ShowExtraFields", "key")
        require(!BmsonSelectedObjects.loadShowExtraFields(from: UserDefaults(suiteName: "org.ibmsc.native.tests.note-edit")!), "default extra collapsed")
        require(BmsonSelectedObjects.parseLength("2147483647") == 2_147_483_647, "int max")
        require(BmsonSelectedObjects.parseLength("2147483648") == nil, "int overflow")
        require(
            BmsonSelectedObjects.formatExtraFields(objectJSON: #"{"b":1,"a":"x"}"#) == "\"a\": \"x\",\n\"b\": 1",
            "sorted extra keys"
        )
        require(BmsonSelectedObjects.preparedExtraObjectJSON("\"tag\": 2,") == "{\"tag\": 2}", "strip comma")
        require(BmsonSelectedObjects.preparedExtraObjectJSON("{") == nil, "bad extra")
    }

    private static func testVisibleRangeExtended() {
        let range = BmsONEVisibleRange.fromScroll(
            viewLength: 1920,
            scrollY: 0,
            viewportHeight: 400,
            zoomY: 48.0 / 240.0
        )
        require(range.0 == -1120 && range.1 == 2960, "GetVisibleRangeExtended 400px at 0.2")
        let truncated = BmsONEVisibleRange.extended(tBegin: -100.7, tEnd: 1940.3)
        require(truncated.0 == -1121 && truncated.1 == 2960, "qreal to int toward zero")
        let pulses = BmsONEVisibleRange.pulses(
            viewport: CGRect(x: 0, y: 100, width: 200, height: 400),
            resolution: 240,
            beatAtY: { y in Double(800 - y) / 48 }
        )
        require(pulses.0 == 460 && pulses.1 == 4540, "editor viewport 1.5x")
    }

    /// 对照 `SequenceDef.h` / `SnapToLowerFineGrid` / `WriteModeContext`。
    private static func testSnapToGrid() {
        require(BmsONESnap.menuTitle == "Snap to Grid", "menu title")
        require(BmsONESnap.settingsKey == "SequenceView/SnapToGrid", "snap key")
        require(BmsONESnap.fineGridKey == "SequenceView/FineGrid", "fine grid key")
        require(BmsONESnap.coarseGridKey == "SequenceView/CoarseGrid", "coarse grid key")
        require(BmsONESnap.defaultEnabled, "default on")
        require(BmsONESnap.defaultFineGrid == BmsONEGridSize.fallbackFine, "default 16")
        require(BmsONESnap.defaultCoarseGrid == BmsONEGridSize.defaultMedium, "default coarse 4/4")

        let grid16 = BmsONEGridSize(denominator: 16)
        require(grid16.nthGrid(timeBase: 240, n: 1) == 60, "16th is 60 ticks")
        require(grid16.gridNumber(timeBase: 240, time: 60) == 1, "60 is grid 1")
        require(grid16.gridNumber(timeBase: 240, time: 59) == 0, "59 floors to 0")
        require(grid16.interval(timeBase: 240) == 60, "interval 60")
        require(grid16.isIntervalInteger(timeBase: 240), "16 is integer")

        let custom = BmsONEGridSize(numerator: 3, denominator: 8)
        require(custom.nthGrid(timeBase: 240, n: 1) == 90, "(3)8 first tick 90")
        require(custom.gridNumber(timeBase: 240, time: 100) == 1, "100 -> grid 1")
        require(custom.nthGrid(timeBase: 240, n: 1) == 90, "snap target 90")

        let bars: [Int64] = [0, 960]
        require(
            BmsONESnap.snapToLowerFineGrid(time: 90, bars: bars, resolution: 240, fineGrid: grid16) == 60,
            "90 -> 60"
        )
        require(
            BmsONESnap.snapToLowerFineGrid(time: 0, bars: bars, resolution: 240, fineGrid: grid16) == 0,
            "on first bar stays"
        )
        require(
            BmsONESnap.snapToLowerFineGrid(time: 960, bars: bars, resolution: 240, fineGrid: grid16) == 960,
            "on next bar stays"
        )
        require(
            BmsONESnap.snapToLowerFineGrid(time: 100, bars: bars, resolution: 240, fineGrid: custom) == 90,
            "custom 100 -> 90"
        )
        require(
            BmsONESnap.snapToUpperFineGrid(time: 61, bars: bars, resolution: 240, fineGrid: grid16) == 120,
            "upper 61 -> 120"
        )
        require(
            BmsONESnap.writePulse(time: 90.9, snap: false, bars: bars, resolution: 240, fineGrid: grid16) == 90,
            "off truncates"
        )
        require(
            BmsONESnap.writePulse(time: 90.9, snap: true, bars: bars, resolution: 240, fineGrid: grid16) == 60,
            "on snaps truncated 90"
        )
        require(
            BmsONESnap.writePulse(time: 100, snap: true, bars: bars, resolution: 240, fineGrid: custom) == 90,
            "custom write 90"
        )

        let emptyBars: [Int64] = []
        require(
            BmsONESnap.snapToLowerFineGrid(time: 48, bars: emptyBars, resolution: 240, fineGrid: grid16) == 48,
            "no bar returns time"
        )

        let suite = UserDefaults(suiteName: "org.ibmsc.native.tests.bmson-snap")!
        suite.removePersistentDomain(forName: "org.ibmsc.native.tests.bmson-snap")
        require(BmsONESnap.load(from: suite), "missing key is on")
        BmsONESnap.save(false, to: suite)
        require(!BmsONESnap.load(from: suite), "saved off")
        require(BmsONESnap.loadFineGrid(from: suite) == BmsONEGridSize.fallbackFine, "missing fine 16")
        BmsONESnap.saveFineGrid(custom, to: suite)
        require(BmsONESnap.loadFineGrid(from: suite) == custom, "saved (3)8")
    }

    /// 对照 `MasterPlayer` / `SoundChannelNotePreviewer`：延迟是播放头补偿。
    private static func testPreviewDelayAndDuration() {
        require(BmsONEPreviewTiming.bufferSampleCount == 4096, "buffer 4096")
        require(BmsONEPreviewTiming.delayMilliseconds(ratio: 1) == 92, "ratio 1 is 92ms")
        require(BmsONEPreviewTiming.delayMilliseconds(ratio: 0.5) == 46, "ratio 0.5 is 46ms")
        require(BmsONEPreviewTiming.delayMilliseconds(ratio: 0) == 0, "ratio 0 is 0")
        require(BmsONEPreviewTiming.delayMilliseconds(ratio: 2) == 185, "ratio 2 is 185ms")
        require(
            abs(BmsONEPreviewTiming.playheadSeconds(audioSeconds: 0.092, ratio: 1)) < 0.000_001,
            "first 92ms stay at 0"
        )
        require(
            abs(BmsONEPreviewTiming.playheadSeconds(audioSeconds: 1.092, ratio: 1) - 1) < 0.000_001,
            "1.092s audio -> 1s playhead"
        )
        let displayed = BmsONEPreviewTiming.playheadSeconds(audioSeconds: 1.092, ratio: 1)
        require(abs(displayed * 120 / 60 - 2) < 0.000_001, "1s at 120 BPM is beat 2")
        require(BmsONEPreviewTiming.durationInSamples(0) == 0, "+inf is 0 samples")
        require(BmsONEPreviewTiming.durationInSamples(0.05) == 2205, "0.05s is 2205")
        require(
            !BmsONEPreviewTiming.shouldStartFade(currentSampleCount: 0, samplesRead: 2205, duration: 0.05),
            "equal limit does not fade"
        )
        require(
            BmsONEPreviewTiming.shouldStartFade(currentSampleCount: 2200, samplesRead: 10, duration: 0.05),
            "2210 > 2205 starts fade"
        )
        require(abs(BmsONEPreviewTiming.fadeGain(index: 0, soft: true) - 1) < 0.000_001, "first sample 1")
        require(
            abs(BmsONEPreviewTiming.fadeGain(index: 1, soft: true) - 0.9998) < 0.000_000_1,
            "soft second sample"
        )
        require(
            abs(BmsONEPreviewTiming.fadeGain(index: 1, soft: false) - 0.9992) < 0.000_000_1,
            "hard second sample"
        )
        require(BmsONEPreviewTiming.fadeOutSeconds(soft: true) > BmsONEPreviewTiming.fadeOutSeconds(soft: false),
                "soft lasts longer")
    }

    /// 对照 `UpdateTotalLength` / `MiniMapView`。不是截图。
    private static func testMasterView() {
        require(BmsONEMasterView.viewLength(actualLength: 0, resolution: 240) == 30720, "empty 32*4*240")
        require(BmsONEMasterView.actualLength(notes: [(y: 240, l: 0), (y: 100, l: 50)]) == 240, "max y+l")
        require(BmsONEMasterView.viewLength(actualLength: 240, resolution: 240) == 30960, "note plus empty")
        require(
            abs(BmsONEMasterView.zoomY(pixelsPerQuarterBeat: 48, resolution: 240) - 0.2) < 1e-12,
            "default zoomY"
        )
        require(BmsONEMasterView.peakColor(available: true) == BmsONEMasterView.peakAvailable, "peak ready")
        require(BmsONEMasterView.peakColor(available: false) == BmsONEMasterView.peakMissing, "peak missing")
        require(BmsONEMasterView.rmsColor(available: true, miniMap: false) == BmsONEMasterView.rmsAvailable, "rms ready")
        require(BmsONEMasterView.rmsColor(available: false, miniMap: false) == BmsONEMasterView.rmsMasterMissing, "master missing rms")
        require(BmsONEMasterView.rmsColor(available: false, miniMap: true) == BmsONEMasterView.rmsMiniMissing, "mini missing rms")
        require(BmsONEMasterView.miniMapTime(y: 0, height: 400, viewLength: 30720) == 0, "buffer y0 is time 0")
        require(
            BmsONEMasterView.miniMapClickTime(y: 100, height: 400, viewLength: 30720) == 23040,
            "(400-100)*30720/400"
        )
        require(
            BmsONEMasterView.miniMapScrollDelta(dy: 10, zoomY: 0.2, viewLength: 30720, height: 400) == 153,
            "10*0.2*30720/400 toward zero"
        )
        let bar = BmsONEMasterView.viewportBar(
            tBegin: 28720,
            tEnd: 30720,
            height: 400,
            viewLength: 30720
        )
        require(bar.yEnd == 0 && bar.yBegin == 26, "scroll 0 bar at top of extra empty")
        require(BmsONEMasterView.showsUnpinnedMiniMap(mouseX: 900, boundsWidth: 940, pinned: false), "near edge")
        require(!BmsONEMasterView.showsUnpinnedMiniMap(mouseX: 10, boundsWidth: 940, pinned: false), "away")
        require(BmsONEMasterView.showsUnpinnedMiniMap(mouseX: 10, boundsWidth: 940, pinned: true), "pinned always")
    }

    /// 对照 `SetNoteColor`：`QColor(c.red()/2, …)`。不是截图。
    private static func testNoteDarken() {
        require(BmsONENoteDarken.menuTitle == "Darken Notes in Inactive Channels", "menu title")
        require(
            BmsONENoteDarken.settingsKey == "SequenceView/DarkenNotesInInactiveChannels",
            "settings key"
        )
        require(BmsONENoteDarken.defaultEnabled, "default on")
        require(BmsONENoteDarken.identityStride == 1_000_003, "same stride as note identity")
        require(BmsONENoteDarken.channel(210, active: true, enabled: true) == 210, "active keeps")
        require(BmsONENoteDarken.channel(210, active: false, enabled: false) == 210, "off keeps")
        require(BmsONENoteDarken.channel(210, active: false, enabled: true) == 105, "210/2")
        require(BmsONENoteDarken.channel(255, active: false, enabled: true) == 127, "255/2")
        require(
            BmsONENoteDarken.argb(0xFFD2D2D2, active: false, enabled: true) == 0xFF696969,
            "BGM 210,210,210 halves"
        )
        require(
            BmsONENoteDarken.argb(0xFFFF0000, active: false, enabled: true) == 0xFF7F0000,
            "red halves"
        )
        require(
            BmsONENoteDarken.argb(0xFF4080C0, active: true, enabled: true) == 0xFF4080C0,
            "active argb"
        )
        let first = 1
        let second = 1_000_003 + 1
        require(
            BmsONENoteDarken.isPaintedActive(identity: first, currentChannel: 0, hoverIdentity: nil),
            "channel 0 is current"
        )
        require(
            !BmsONENoteDarken.isPaintedActive(identity: second, currentChannel: 0, hoverIdentity: nil),
            "channel 1 is inactive"
        )
        require(
            BmsONENoteDarken.isPaintedActive(
                identity: second,
                currentChannel: 0,
                hoverIdentity: second
            ),
            "hover stays bright"
        )
        require(
            BmsONENoteDarken.isPaintedActive(identity: -1, currentChannel: 0, hoverIdentity: nil),
            "timing stays bright"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-note-darken"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONENoteDarken.load(from: suite), "missing key is default on")
        BmsONENoteDarken.save(false, to: suite)
        require(!BmsONENoteDarken.load(from: suite), "store off")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `ViewMode.cpp` `GetViewMode` / `GetAllViewModes`。不写 `info.modeHint`。
    private static func testViewMode() {
        require(
            BmsONEViewMode.menuModes.map(\.name) == [
                "Beat 7-key",
                "Beat 14-key",
                "Beat 5-key",
                "Beat 10-key",
                "Pop 5-key",
                "Pop 9-key",
                "CircularRhythm-single",
                "CircularRhythm-double",
                "Generic 6 Keys",
                "Generic 7 Keys",
                "Keyboard 24-key (single)",
                "Keyboard 24-key (double)"
            ],
            "GetAllViewModes titles"
        )
        require(BmsONEViewMode.menuModes.count == 12, "twelve public modes")
        require(!BmsONEViewMode.menuModes.contains { $0.kind == .plain }, "Plain stays out of the menu")
        require(
            BmsONEViewMode.menuHints == [
                "beat-7k",
                "beat-14k",
                "beat-7k-battle",
                "beat-5k",
                "beat-10k",
                "beat-5k-battle",
                "popn-5k",
                "popn-9k",
                "circularrhythm-single",
                "circularrhythm-double",
                "generic-6keys",
                "generic-7keys",
                "keyboard-24k",
                "keyboard-24k-double"
            ],
            "GetAllModeHints"
        )
        require(BmsONEViewMode.resolve("").kind == .beat7k, "empty hint is Beat 7-key")
        require(BmsONEViewMode.resolve("beat-7k").kind == .beat7k, "beat-7k")
        require(BmsONEViewMode.resolve("beat-7k-battle").kind == .beat14k, "7k-battle is 14k")
        require(BmsONEViewMode.resolve("beat-5k-battle").kind == .beat10k, "5k-battle is 10k")
        require(BmsONEViewMode.resolve("keyboard-24k-single").kind == .keyboard24Single, "hidden 24k alias")
        require(BmsONEViewMode.resolve("keyboard-36k").kind == .keyboard36, "hidden 36k")
        require(!BmsONEViewMode.resolve("keyboard-36k").inMenu, "36k is hidden")
        require(BmsONEViewMode.resolve("unknown-mode").kind == .plain, "unknown is Plain")
        require(BmsONEViewMode.resolve("BEAT-7K").kind == .plain, "hint match is exact")
        let five = BmsONEViewMode.resolve("beat-5k")
        require(five.laneToChannel[6] == nil && five.laneToChannel[8] == "16", "5k has scratch, no key 6")
        require(five.hiddenPlayChannels.contains("18") && five.hiddenPlayChannels.contains("19"), "5k hides 18/19")
        require(!five.showsTwoPlayer, "5k hides 2P")
        let pop9 = BmsONEViewMode.resolve("popn-9k")
        require(pop9.laneToChannel[8] == "16" && pop9.laneToChannel[9] == "21", "popn-9k x=8/9")
        require(pop9.laneToChannel[6] == "18" && pop9.showsTwoPlayer, "popn-9k key 6 and key 9")
        require(!pop9.visiblePlayChannels.contains("22"), "popn-9k does not use the rest of 2P")
        let keys = BmsONEViewMode.resolve("keyboard-24k")
        require(keys.laneToChannel[1] == "16" && keys.laneToChannel[16] == "26", "24k first 16 columns")
        require(keys.laneToChannel[17] == nil, "24k x>=17 stays off the shared columns")
        let plain = BmsONEViewMode.resolve("plain")
        require(plain.kind == .plain && plain.laneToChannel[16] == "26", "Plain maps 1...16")
        require(plain.laneToChannel[17] == nil, "Plain x>=17 stays off")
        let opened = BmsONEViewMode.resolve("beat-5k")
        require(opened.canonicalHint == "beat-5k", "opening a 5k chart checks Beat 5-key")
        require(opened.canonicalHint != "beat-7k", "View Mode does not rewrite the stored hint")
    }

    /// 对照 `SequenceView::ZoomIn` / `ZoomOut` / `ZoomReset` / `wheelEventVp`。
    private static func testZoom() {
        require(abs(BmsONEZoom.defaultZoomY - 0.2) < 1e-12, "default 48/240")
        require(abs(BmsONEZoom.zoomIn(0.2, resolution: 240) - 0.25) < 1e-12, "zoom in 0.25")
        require(
            abs(BmsONEZoom.pixelsPerQuarterBeat(zoomY: 0.25, resolution: 240) - 60) < 1e-12,
            "ppq 60"
        )
        require(abs(BmsONEZoom.gridHeight(zoomY: 0.25, resolution: 240) - 1.25) < 1e-12, "height 1.25")
        require(abs(BmsONEZoom.zoomOut(0.2, resolution: 240) - 0.16) < 1e-12, "zoom out 0.16")
        require(
            abs(BmsONEZoom.pixelsPerQuarterBeat(zoomY: 0.16, resolution: 240) - 38.4) < 1e-12,
            "ppq 38.4"
        )
        require(abs(BmsONEZoom.clampZoomY(0.05, resolution: 240) - 0.1) < 1e-12, "min 0.1")
        require(abs(BmsONEZoom.clampZoomY(2.0, resolution: 240) - 1.6) < 1e-12, "max 1.6")
        require(abs(BmsONEZoom.resetZoomY(resolution: 240) - 0.2) < 1e-12, "reset 240")
        require(
            abs(BmsONEZoom.pixelsPerQuarterBeat(zoomY: 0.2, resolution: 480) - 96) < 1e-12,
            "480 default ppq"
        )
        require(abs(BmsONEZoom.resetZoomY(resolution: 480) - 0.1) < 1e-12, "reset 480")
        require(
            abs(BmsONEZoom.pixelsPerQuarterBeat(zoomY: 0.1, resolution: 480) - 48) < 1e-12,
            "reset ppq 48"
        )
        require(abs(BmsONEZoom.zoomIn(1.6, resolution: 240) - 1.6) < 1e-12, "clamp zoom in")
        let pinched = BmsONEZoom.applyPixelDelta(0.2, pixels: 10, resolution: 240)
        require(abs(pinched - 0.2 * pow(1.01, 10)) < 1e-12, "pixel 1.01^y")
        require(
            abs(
                BmsONEZoom.applyWheel(
                    zoomY: 0.2,
                    resolution: 240,
                    pixelDeltaY: 0,
                    hasPrecisePixels: false,
                    notches: 1
                ) - 0.25
            ) < 1e-12,
            "notch zoom in"
        )
        require(
            abs(
                BmsONEZoom.applyWheel(
                    zoomY: 0.2,
                    resolution: 240,
                    pixelDeltaY: 0,
                    hasPrecisePixels: false,
                    notches: -1
                ) - 0.16
            ) < 1e-12,
            "notch zoom out"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-zoom"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(abs(BmsONEZoom.load(from: suite) - 0.2) < 1e-12, "missing key is 0.2")
        BmsONEZoom.save(0.25, to: suite)
        require(abs(BmsONEZoom.load(from: suite) - 0.25) < 1e-12, "store 0.25")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `SequenceViewChannelLaneMode` / `ChannelLaneWidth` / `DrawsWaveform`。
    private static func testSoundChannelLanes() {
        require(BmsONESoundChannelLaneMode.menuTitle == "Sound Channel Lanes Display", "menu title")
        require(
            BmsONESoundChannelLaneMode.settingsKey == "SequenceView/SoundChannelLaneMode",
            "settings key"
        )
        require(BmsONESoundChannelLaneMode.defaultMode == .normal, "default normal")
        require(BmsONESoundChannelLaneMode.normal.width == 64, "normal 64")
        require(BmsONESoundChannelLaneMode.compact.width == 32, "compact 32")
        require(BmsONESoundChannelLaneMode.simple.width == 32, "simple 32")
        require(BmsONESoundChannelLaneMode.normal.drawsWaveform, "normal draws waveform")
        require(BmsONESoundChannelLaneMode.compact.drawsWaveform, "compact draws waveform")
        require(!BmsONESoundChannelLaneMode.simple.drawsWaveform, "simple skips waveform")
        require(BmsONESoundChannelLaneMode.parse("NORMAL") == .normal, "toLower normal")
        require(BmsONESoundChannelLaneMode.parse("Compact") == .compact, "toLower compact")
        require(BmsONESoundChannelLaneMode.parse("simple") == .simple, "simple")
        require(BmsONESoundChannelLaneMode.parse("other") == .normal, "unknown is normal")
        require(BmsONESoundChannelLaneMode.normal.storedValue == "normal", "store normal")
        require(BmsonSoundLane.displayChannel(index: 0) == "CH0", "first lane CH0")
        require(BmsonSoundLane.displayChannel(index: 12) == "CH12", "twelfth lane")
        require(BmsonSoundLane.index(display: "CH0") == 0, "CH0 is 0")
        require(BmsonSoundLane.index(display: "ch3") == 3, "ch3 is 3")
        require(BmsonSoundLane.index(display: "SC") == nil, "SCROLL is not a sound lane")
        require(BmsonSoundLane.index(display: "B1") == nil, "B1 is not a sound lane")
        require(
            BmsonSoundLane.visibleIndices(count: 3, shown: nil) == [0, 1, 2],
            "hide others off keeps all"
        )
        require(
            BmsonSoundLane.visibleIndices(count: 3, shown: [false, true, false]) == [1],
            "hide others width 0"
        )
        require(
            BmsONESoundChannelLaneMode.continuesAfterClick(current: 0, clicked: 0),
            "current column writes"
        )
        require(
            !BmsONESoundChannelLaneMode.continuesAfterClick(current: 0, clicked: 1),
            "other column only selects"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-sound-lanes"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONESoundChannelLaneMode.load(from: suite) == .normal, "missing key is normal")
        BmsONESoundChannelLaneMode.save(.compact, to: suite)
        require(BmsONESoundChannelLaneMode.load(from: suite) == .compact, "store compact")
        BmsONESoundChannelLaneMode.save(.simple, to: suite)
        require(BmsONESoundChannelLaneMode.load(from: suite) == .simple, "store simple")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `SoundChannelFooter` / `SetFooterHeight` / `QFileInfo::baseName`。
    private static func testFooter() {
        require(BmsONEFooter.gripWidth == 6, "grip 6")
        require(BmsONEFooter.minHeight == 60, "48+6*2")
        require(BmsONEFooter.maxHeight == 180, "max 180")
        require(BmsONEFooter.defaultHeight == 60, "default min")
        require(BmsONEFooter.fontSize == 12, "pixel 12")
        require(BmsONEFooter.areaColor == 0x666666, "102,102,102")
        require(BmsONEFooter.clampHeight(10) == 60, "clamp low")
        require(BmsONEFooter.clampHeight(200) == 180, "clamp high")
        require(BmsONEFooter.clampHeight(90) == 90, "clamp mid")
        require(
            BmsONEFooter.heightAfterWindowDrag(startHeight: 60, startWindowY: 100, currentWindowY: 80)
                == 80,
            "drag up +20"
        )
        require(
            BmsONEFooter.heightAfterWindowDrag(startHeight: 80, startWindowY: 100, currentWindowY: 140)
                == 60,
            "drag down clamp"
        )
        require(BmsONEFooter.textMode(internalWidth: 32, height: 60) == .verticalSingle, "compact vertical")
        require(BmsONEFooter.textMode(internalWidth: 64, height: 60) == .horizontal, "normal horizontal")
        require(BmsONEFooter.textMode(internalWidth: 64, height: 120) == .verticalWrap, "tall wrap")
        let horizontal = BmsONEFooter.textRect(internalWidth: 64, height: 60, mode: .horizontal)
        require(horizontal == CGRect(x: 2, y: 8, width: 60, height: 50), "horizontal margins")
        let vertical = BmsONEFooter.textRect(internalWidth: 32, height: 60, mode: .verticalSingle)
        require(vertical == CGRect(x: 6, y: 2, width: 46, height: 28), "vertical margins")
        require(!BmsONEFooter.canDrawText(in: CGRect(x: 0, y: 0, width: 3, height: 10)), "min 4")
        require(BmsONEFooter.displayName("kick.wav") == "kick", "baseName wav")
        require(BmsONEFooter.displayName("/song/hat.ogg") == "hat", "baseName path")
        require(BmsONEFooter.displayName("plain") == "plain", "no suffix")
        let wide = CGRect(x: 0, y: 0, width: 200, height: 20)
        func countMeasure(_ text: String) -> CGSize {
            CGSize(width: CGFloat(text.utf16.count) * 8, height: 12)
        }
        require(
            BmsONEFooter.displayedName(name: "kick", textRect: wide, measure: countMeasure) == "kick",
            "fits whole"
        )
        let tight = CGRect(x: 0, y: 0, width: 56, height: 20)
        require(
            BmsONEFooter.displayedName(name: "kick.wav", textRect: tight, measure: countMeasure)
                == "kic...v",
            "first 3 then drop tail to 56px"
        )
        let tiny = CGRect(x: 0, y: 0, width: 40, height: 20)
        require(
            BmsONEFooter.displayedName(name: "kick.wav", textRect: tiny, measure: countMeasure)
                == "kic...v",
            "count 1 stops dropping"
        )
        require(
            BmsONEFooter.displayedName(
                name: "ab",
                textRect: CGRect(x: 0, y: 0, width: 8, height: 20),
                measure: countMeasure
            ) == "...b",
            "short name uses dots"
        )
        require(
            BmsONEFooter.displayedName(
                name: "x",
                textRect: CGRect(x: 0, y: 0, width: 3, height: 3),
                measure: countMeasure
            ) == nil,
            "too small"
        )
        let click = BmsONEFooter.applyClick(current: 0, selected: [0], clicked: 2, toggle: false)
        require(click.current == 2 && click.selected == [2], "plain click replaces")
        let keep = BmsONEFooter.applyClick(current: 0, selected: [0, 2], clicked: 2, toggle: false)
        require(keep.current == 2 && keep.selected == [0, 2], "already selected keeps")
        let toggled = BmsONEFooter.applyClick(current: 0, selected: [0], clicked: 2, toggle: true)
        require(toggled.current == 0 && toggled.selected == [0, 2], "command adds")
        let dropped = BmsONEFooter.applyClick(current: 0, selected: [0, 2], clicked: 2, toggle: true)
        require(dropped.current == 0 && dropped.selected == [0], "command removes")
        let cells = BmsONEFooter.channelCells(
            names: ["kick.wav", "snare.wav"],
            frames: [
                "CH0": CGRect(x: 400, y: 0, width: 64, height: 1),
                "CH1": CGRect(x: 464, y: 0, width: 64, height: 1)
            ],
            visible: [0, 1],
            height: 60
        )
        require(cells.count == 2, "two channel cells")
        require(cells[0].kind == .channel(index: 0, name: "kick"), "cell baseName")
        require(cells[0].frame == CGRect(x: 400, y: 0, width: 64, height: 60), "cell frame")
        require(BmsONEFooter.hitChannel(x: 20, cells: cells, offsetX: 400) == 0, "hit first")
        require(BmsONEFooter.hitChannel(x: 80, cells: cells, offsetX: 400) == 1, "hit second")
        require(
            BmsONEFooter.hit(
                point: CGPoint(x: 20, y: 3),
                cells: cells,
                offsetX: 400,
                command: false,
                doubleClick: false,
                middle: false
            ) == .grip,
            "grip"
        )
        require(
            BmsONEFooter.hit(
                point: CGPoint(x: 20, y: 20),
                cells: cells,
                offsetX: 400,
                command: false,
                doubleClick: false,
                middle: false
            ) == .select(0),
            "select"
        )
        require(
            BmsONEFooter.hit(
                point: CGPoint(x: 20, y: 20),
                cells: cells,
                offsetX: 400,
                command: true,
                doubleClick: false,
                middle: false
            ) == .toggle(0),
            "toggle"
        )
        require(
            BmsONEFooter.hit(
                point: CGPoint(x: 20, y: 20),
                cells: cells,
                offsetX: 400,
                command: false,
                doubleClick: true,
                middle: false
            ) == .preview(0),
            "double preview"
        )
        require(
            BmsONEFooter.hit(
                point: CGPoint(x: 20, y: 20),
                cells: cells,
                offsetX: 400,
                command: false,
                doubleClick: false,
                middle: true
            ) == .preview(0),
            "middle preview"
        )
        let playing = BmsONEFooter.playingLabelFrame(left: 5, width: 32, imageName: "scratch")
        require(playing == CGRect(x: 5, y: 6, width: 32, height: 48), "key image 48")
        require(
            BmsONEFooter.playingLabelFrame(left: 0, width: 24, imageName: "")
                == CGRect(x: 0, y: 6, width: 24, height: 24),
            "number 24"
        )
        require(BmsONEFooter.hitsPlaying(x: 10, cells: cells, offsetX: 400) == false, "channel is not playing")
        let playingCell = BmsONEFooter.Cell(
            kind: .playing(label: "8", imageName: "scratch"),
            frame: CGRect(x: 100, y: 0, width: 32, height: 60)
        )
        require(BmsONEFooter.hitsPlaying(x: 10, cells: [playingCell], offsetX: 100), "playing hit")
        require(BmsONEFooter.beat7kImageNames[0] == "scratch", "scratch image")
        require(BmsONEFooter.beat7kImageNames[1] == "wkey", "white key")
        require(BmsONEFooter.beat7kImageNames[2] == "bkey", "black key")
        let suiteName = "org.ibmsc.native.tests.bmsone-footer"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONEFooter.load(from: suite) == 60, "missing is 60")
        BmsONEFooter.save(90, to: suite)
        require(BmsONEFooter.load(from: suite) == 90, "store 90")
        BmsONEFooter.save(12, to: suite)
        require(BmsONEFooter.load(from: suite) == 60, "store clamps")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `Skin.cpp` 刮盘左右。
    private static func testScratch() {
        require(BmsONEScratch.menuTitle == "Scratch", "menu title")
        require(
            BmsONEScratch.settingsKey(for: .beat7k) == "SkinSettings/default-beat-7k/scratch",
            "7k key"
        )
        require(BmsONEScratch.defaultStored(for: .beat7k) == "l", "7k default left")
        require(BmsONEScratch.defaultStored(for: .beat5k) == "r", "5k default right")
        require(BmsONEScratch.defaultStored(for: .beat10k) == "rr", "10k default rr")
        require(BmsONEScratch.defaultStored(for: .beat14k) == "lr", "14k default lr")
        require(BmsONEScratch.choices(for: .beat7k).map(\.title) == ["Left", "Right"], "7k titles")
        require(
            BmsONEScratch.choices(for: .beat14k).map(\.stored) == ["ll", "lr", "rl", "rr"],
            "14k stored"
        )
        require(BmsONEScratch.parse("r", kind: .beat7k)?.player1Left == false, "7k right")
        require(BmsONEScratch.parse("other", kind: .beat7k)?.stored == "l", "unknown is default")
        require(BmsONEScratch.skinId(for: .popn9k) == nil, "popn has no scratch")
        let sevenLeft = BmsONEScratch.parse("l", kind: .beat7k)!
        require(
            BmsONEScratch.player1Channels(kind: .beat7k, scratch: sevenLeft)
                == ["16", "11", "12", "13", "14", "15", "18", "19"],
            "7k left columns"
        )
        require(
            BmsONEScratch.keyLanes(kind: .beat7k, scratch: sevenLeft)
                == [8, 1, 2, 3, 4, 5, 6, 7],
            "7k left lanes"
        )
        let sevenRight = BmsONEScratch.parse("r", kind: .beat7k)!
        require(
            BmsONEScratch.player1Channels(kind: .beat7k, scratch: sevenRight)
                == ["11", "12", "13", "14", "15", "18", "19", "16"],
            "7k right columns"
        )
        require(
            BmsONEScratch.keyLanes(kind: .beat7k, scratch: sevenRight)
                == [1, 2, 3, 4, 5, 6, 7, 8],
            "7k right lanes"
        )
        let fiveRight = BmsONEScratch.parse("r", kind: .beat5k)!
        require(
            BmsONEScratch.player1Channels(kind: .beat5k, scratch: fiveRight)
                == ["11", "12", "13", "14", "15", "16"],
            "5k right columns"
        )
        require(
            BmsONEScratch.keyLanes(kind: .beat5k, scratch: fiveRight) == [1, 2, 3, 4, 5, 8],
            "5k right lanes"
        )
        let tenRR = BmsONEScratch.parse("rr", kind: .beat10k)!
        require(
            BmsONEScratch.player1Channels(kind: .beat10k, scratch: tenRR)
                == ["11", "12", "13", "14", "15", "16"],
            "10k P1 right"
        )
        require(
            BmsONEScratch.player2Channels(kind: .beat10k, scratch: tenRR)
                == ["21", "22", "23", "24", "25", "26"],
            "10k P2 right"
        )
        require(
            BmsONEScratch.keyLanes(kind: .beat10k, scratch: tenRR)
                == [1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 16],
            "10k rr lanes"
        )
        let fourteenLR = BmsONEScratch.parse("lr", kind: .beat14k)!
        require(
            BmsONEScratch.player1Channels(kind: .beat14k, scratch: fourteenLR).first == "16",
            "14k P1 left"
        )
        require(
            BmsONEScratch.player2Channels(kind: .beat14k, scratch: fourteenLR).last == "26",
            "14k P2 right"
        )
        require(
            BmsONEScratch.keyLanes(kind: .beat14k, scratch: fourteenLR)
                == [8, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16],
            "14k lr lanes"
        )
        let fourteenLL = BmsONEScratch.parse("ll", kind: .beat14k)!
        require(
            BmsONEScratch.player2Channels(kind: .beat14k, scratch: fourteenLL).first == "26",
            "14k P2 left"
        )
        let beat7k = BmsONEViewMode(kind: .beat7k)
        require(
            BmsONEScratch.keyLanes(mode: beat7k, scratch: nil) == beat7k.keyLanes,
            "nil keeps mode order"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-scratch"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONEScratch.load(kind: .beat7k, from: suite)?.stored == "l", "missing 7k is l")
        require(BmsONEScratch.load(kind: .beat5k, from: suite)?.stored == "r", "missing 5k is r")
        BmsONEScratch.save("r", kind: .beat7k, to: suite)
        require(BmsONEScratch.load(kind: .beat7k, from: suite)?.stored == "r", "store 7k right")
        BmsONEScratch.save("nope", kind: .beat7k, to: suite)
        require(BmsONEScratch.load(kind: .beat7k, from: suite)?.stored == "r", "reject garbage")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `Skin.cpp` Circular `lane-order`。
    private static func testLaneOrder() {
        require(BmsONELaneOrder.menuTitle == "Lane Order", "menu title")
        require(
            BmsONELaneOrder.settingsKey(for: .circularSingle)
                == "SkinSettings/default-circular-single/lane-order",
            "single key"
        )
        require(BmsONELaneOrder.defaultStored(for: .circularSingle) == "l", "single default left")
        require(BmsONELaneOrder.defaultStored(for: .circularDouble) == "lr", "double default lr")
        require(BmsONELaneOrder.choices(for: .circularSingle).map(\.title) == ["Left", "Right"], "single titles")
        require(
            BmsONELaneOrder.choices(for: .circularDouble).map(\.stored) == ["ll", "lr", "rl", "rr"],
            "double stored"
        )
        require(BmsONELaneOrder.parse("other", kind: .circularSingle)?.stored == "l", "unknown is default")
        require(BmsONELaneOrder.skinId(for: .beat7k) == nil, "beat has no lane-order")
        let singleLeft = BmsONELaneOrder.parse("l", kind: .circularSingle)!
        require(
            BmsONELaneOrder.keyLanes(kind: .circularSingle, order: singleLeft) == [4, 3, 2, 1, 5],
            "single left lanes"
        )
        require(
            BmsONELaneOrder.channels(kind: .circularSingle, order: singleLeft)
                == ["14", "13", "12", "11", "15"],
            "single left columns"
        )
        require(
            BmsONELaneOrder.cells(kind: .circularSingle, order: singleLeft).map(\.imageName)
                == ["c-L-blue", "c-L-green", "c-L-yellow", "c-L-red", "c-Space"],
            "single left images"
        )
        let singleRight = BmsONELaneOrder.parse("r", kind: .circularSingle)!
        require(
            BmsONELaneOrder.keyLanes(kind: .circularSingle, order: singleRight) == [5, 1, 2, 3, 4],
            "single right lanes"
        )
        require(
            BmsONELaneOrder.channels(kind: .circularSingle, order: singleRight)
                == ["15", "11", "12", "13", "14"],
            "single right columns"
        )
        let doubleLR = BmsONELaneOrder.parse("lr", kind: .circularDouble)!
        require(
            BmsONELaneOrder.keyLanes(kind: .circularDouble, order: doubleLR)
                == [4, 3, 2, 1, 9, 5, 6, 7, 8],
            "double lr lanes"
        )
        require(
            BmsONELaneOrder.channels(kind: .circularDouble, order: doubleLR)
                == ["14", "13", "12", "11", "21", "15", "18", "19", "16"],
            "double lr columns"
        )
        require(
            BmsONELaneOrder.channels(kind: .circularDouble, order: doubleLR)[4] == "21",
            "double space is 21"
        )
        let doubleLL = BmsONELaneOrder.parse("ll", kind: .circularDouble)!
        require(
            Array(BmsONELaneOrder.keyLanes(kind: .circularDouble, order: doubleLL).suffix(4))
                == [8, 7, 6, 5],
            "double ll right side L"
        )
        let doubleRR = BmsONELaneOrder.parse("rr", kind: .circularDouble)!
        require(
            Array(BmsONELaneOrder.keyLanes(kind: .circularDouble, order: doubleRR).prefix(4))
                == [1, 2, 3, 4],
            "double rr left side R"
        )
        require(BmsONELaneOrder.showsTwoPlayer(kind: .circularDouble) == false, "one pane")
        require(BmsONELaneOrder.showsTwoPlayer(kind: .beat7k) == nil, "beat unchanged")
        let circular = BmsONEViewMode(kind: .circularSingle)
        require(
            BmsONELaneOrder.keyLanes(mode: circular, order: nil) == circular.keyLanes,
            "nil keeps mode order"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-lane-order"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONELaneOrder.load(kind: .circularSingle, from: suite)?.stored == "l", "missing single is l")
        require(BmsONELaneOrder.load(kind: .circularDouble, from: suite)?.stored == "lr", "missing double is lr")
        BmsONELaneOrder.save("r", kind: .circularSingle, to: suite)
        require(BmsONELaneOrder.load(kind: .circularSingle, from: suite)?.stored == "r", "store single right")
        BmsONELaneOrder.save("nope", kind: .circularSingle, to: suite)
        require(BmsONELaneOrder.load(kind: .circularSingle, from: suite)?.stored == "r", "reject garbage")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `Skin.cpp` Plain `lane-count`。
    private static func testPlainLanes() {
        require(BmsONEPlainLanes.displayName == "Lane Count", "display name")
        require(BmsONEPlainLanes.menuTitle(count: 4) == "Lane Count: 4", "menu title")
        require(BmsONEPlainLanes.dialogLabel == "Lane Count:", "dialog label")
        require(
            BmsONEPlainLanes.settingsKey(for: .plain) == "SkinSettings/default-plain/lane-count",
            "settings key"
        )
        require(BmsONEPlainLanes.settingsKey(for: .beat7k) == nil, "beat has no lane-count")
        require(BmsONEPlainLanes.defaultCount == 4, "default 4")
        require(BmsONEPlainLanes.clamp(0) == 1 && BmsONEPlainLanes.clamp(100) == 99, "clamp 1...99")
        require(BmsONEPlainLanes.parse("nope") == 1, "garbage toInt is 0 then 1")
        require(BmsONEPlainLanes.parse("8foo") == 8, "toInt stops at letters")
        require(
            BmsONEPlainLanes.visibleChannels(count: 4) == ["16", "11", "12", "13"],
            "4 columns"
        )
        require(
            BmsONEPlainLanes.visibleChannels(count: 8)
                == ["16", "11", "12", "13", "14", "15", "18", "19"],
            "8 is full 1P"
        )
        require(
            BmsONEPlainLanes.visibleChannels(count: 99) == BmsONEViewMode.sharedPlayChannels,
            "99 caps at 16"
        )
        require(
            BmsONEPlainLanes.hiddenPlayChannels(count: 4).contains("14")
                && BmsONEPlainLanes.hiddenPlayChannels(count: 4).contains("18")
                && BmsONEPlainLanes.hiddenPlayChannels(count: 4).contains("21"),
            "4 hides later play columns"
        )
        require(BmsONEPlainLanes.keyLanes(count: 4) == [1, 2, 3, 4], "4 vacant lanes")
        require(BmsONEPlainLanes.keyLanes(count: 99) == Array(1...16), "99 vacant cap 16")
        require(BmsONEPlainLanes.showsTwoPlayer(kind: .plain) == false, "one pane")
        require(BmsONEPlainLanes.showsTwoPlayer(kind: .beat7k) == nil, "beat unchanged")
        let plain = BmsONEViewMode(kind: .plain)
        require(
            BmsONEPlainLanes.keyLanes(mode: plain, count: nil) == plain.keyLanes,
            "nil keeps mode lanes"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-plain-lanes"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 4, "missing is 4")
        require(BmsONEPlainLanes.load(kind: .beat7k, from: suite) == nil, "beat load is nil")
        suite.set(0, forKey: BmsONEPlainLanes.settingsKey(for: .plain)!)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 1, "0 clamps to 1")
        suite.set(100, forKey: BmsONEPlainLanes.settingsKey(for: .plain)!)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 99, "100 clamps to 99")
        suite.set("8", forKey: BmsONEPlainLanes.settingsKey(for: .plain)!)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 8, "string 8")
        suite.set("nope", forKey: BmsONEPlainLanes.settingsKey(for: .plain)!)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 1, "string garbage is 1")
        BmsONEPlainLanes.save(4, kind: .plain, to: suite)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 4, "store 4")
        BmsONEPlainLanes.save(0, kind: .plain, to: suite)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 1, "save 0 stores 1")
        BmsONEPlainLanes.save(12, kind: .beat7k, to: suite)
        require(BmsONEPlainLanes.load(kind: .plain, from: suite) == 1, "reject other kind")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `Skin.cpp` Generic `color-scheme`。
    private static func testColorScheme() {
        require(BmsONEColorScheme.menuTitle == "Color Scheme", "menu title")
        require(
            BmsONEColorScheme.settingsKey(for: .generic6)
                == "SkinSettings/default-generic-6keys/color-scheme",
            "6k key"
        )
        require(
            BmsONEColorScheme.settingsKey(for: .generic7)
                == "SkinSettings/default-generic-7keys/color-scheme",
            "7k key"
        )
        require(BmsONEColorScheme.skinId(for: .beat7k) == nil, "beat has no color-scheme")
        require(
            BmsONEColorScheme.choices(for: .generic6).map(\.stored) == ["default", "symmetric", "dj"],
            "stored"
        )
        require(
            BmsONEColorScheme.choices(for: .generic6).map(\.title) == ["Default", "Symmetric", "DJ"],
            "titles"
        )
        require(BmsONEColorScheme.parse("other", kind: .generic6)?.stored == "default", "unknown is default")
        let sixDefault = BmsONEColorScheme.parse("default", kind: .generic6)!
        let sixPaints = BmsONEColorScheme.paints(kind: .generic6, scheme: sixDefault)
        require(sixPaints.count == 6, "6 paints")
        require(sixPaints[0].note == BmsONEColorScheme.ncWhite, "default note")
        require(sixPaints[0].background == BmsONEColorScheme.defaultBackground, "default bg")
        let sixSym = BmsONEColorScheme.parse("symmetric", kind: .generic6)!
        let sixSymPaints = BmsONEColorScheme.paints(kind: .generic6, scheme: sixSym)
        require(
            sixSymPaints[0].note == BmsONEColorScheme.RGB(red: 180, green: 137, blue: 225)
                && sixSymPaints[0].background == BmsONEColorScheme.RGB(red: 51, green: 26, blue: 68),
            "6 symmetric lane 1"
        )
        require(sixSymPaints[2] == sixSymPaints[3], "6 symmetric 3 == 4")
        require(
            BmsONEColorScheme.playPaints(kind: .generic6, scheme: sixSym)["11"]?.note
                == BmsONEColorScheme.RGB(red: 180, green: 137, blue: 225),
            "lane 1 is 11"
        )
        let sixDJ = BmsONEColorScheme.parse("dj", kind: .generic6)!
        require(
            BmsONEColorScheme.paints(kind: .generic6, scheme: sixDJ)[1].note == BmsONEColorScheme.pnBlue
                && BmsONEColorScheme.paints(kind: .generic6, scheme: sixDJ)[1].background
                    == BmsONEColorScheme.pcBlue,
            "6 DJ lane 2"
        )
        let sevenSym = BmsONEColorScheme.parse("symmetric", kind: .generic7)!
        require(
            BmsONEColorScheme.paints(kind: .generic7, scheme: sevenSym)[3].note
                == BmsONEColorScheme.RGB(red: 150, green: 240, blue: 150)
                && BmsONEColorScheme.paints(kind: .generic7, scheme: sevenSym)[3].background
                    == BmsONEColorScheme.RGB(red: 26, green: 57, blue: 26),
            "7 symmetric lane 4"
        )
        let sevenDJ = BmsONEColorScheme.parse("dj", kind: .generic7)!
        require(
            BmsONEColorScheme.paints(kind: .generic7, scheme: sevenDJ)[3].note
                == BmsONEColorScheme.RGB(red: 225, green: 180, blue: 137)
                && BmsONEColorScheme.paints(kind: .generic7, scheme: sevenDJ)[3].background
                    == BmsONEColorScheme.RGB(red: 60, green: 39, blue: 20),
            "7 DJ lane 4"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-color-scheme"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONEColorScheme.load(kind: .generic6, from: suite)?.stored == "default", "missing is default")
        require(BmsONEColorScheme.load(kind: .beat7k, from: suite) == nil, "beat load is nil")
        BmsONEColorScheme.save("symmetric", kind: .generic6, to: suite)
        require(BmsONEColorScheme.load(kind: .generic6, from: suite)?.stored == "symmetric", "store symmetric")
        BmsONEColorScheme.save("nope", kind: .generic6, to: suite)
        require(BmsONEColorScheme.load(kind: .generic6, from: suite)?.stored == "symmetric", "reject garbage")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `Skin.cpp` Keyboard `wheel`。
    private static func testWheel() {
        require(BmsONEWheel.menuTitle == "Wheel", "menu title")
        require(
            BmsONEWheel.settingsKey(for: .keyboard24Single)
                == "SkinSettings/default-keyboard-24k-single/wheel",
            "24k single key"
        )
        require(
            BmsONEWheel.settingsKey(for: .keyboard24Double)
                == "SkinSettings/default-keyboard-24k-double/wheel",
            "24k double key"
        )
        require(
            BmsONEWheel.settingsKey(for: .keyboard36)
                == "SkinSettings/default-keyboard-36k-single/wheel",
            "36k key"
        )
        require(BmsONEWheel.skinId(for: .beat7k) == nil, "beat has no wheel")
        require(BmsONEWheel.defaultStored(for: .keyboard24Single) == "l", "single default left")
        require(BmsONEWheel.defaultStored(for: .keyboard24Double) == "lr", "double default lr")
        require(BmsONEWheel.choices(for: .keyboard24Single).map(\.title) == ["Left", "Right"], "single titles")
        require(
            BmsONEWheel.choices(for: .keyboard24Double).map(\.stored) == ["ll", "lr", "rl", "rr"],
            "double stored"
        )
        require(BmsONEWheel.parse("other", kind: .keyboard24Single)?.stored == "l", "unknown is default")
        let singleLeft = BmsONEWheel.parse("l", kind: .keyboard24Single)!
        let leftLanes = BmsONEWheel.keyLanes(kind: .keyboard24Single, wheel: singleLeft)
        require(leftLanes.prefix(2).elementsEqual([25, 26]), "24k left wheels first")
        require(leftLanes.dropFirst(2).prefix(3).elementsEqual([1, 2, 3]), "24k left then keys")
        require(leftLanes.count == 26, "24k 24 keys + 2 wheels")
        require(leftLanes.contains(17), "vacant can use x=17")
        let singleRight = BmsONEWheel.parse("r", kind: .keyboard24Single)!
        let rightLanes = BmsONEWheel.keyLanes(kind: .keyboard24Single, wheel: singleRight)
        require(rightLanes.prefix(3).elementsEqual([1, 2, 3]), "24k right keys first")
        require(rightLanes.suffix(2).elementsEqual([25, 26]), "24k right wheels last")
        let thirtySix = BmsONEWheel.parse("l", kind: .keyboard36)!
        require(
            BmsONEWheel.keyLanes(kind: .keyboard36, wheel: thirtySix).prefix(2).elementsEqual([37, 38]),
            "36k wheels are 37/38"
        )
        let doubleLR = BmsONEWheel.parse("lr", kind: .keyboard24Double)!
        let doubleLanes = BmsONEWheel.keyLanes(kind: .keyboard24Double, wheel: doubleLR)
        require(doubleLanes.prefix(2).elementsEqual([25, 26]), "double lr P1 wheels first")
        require(doubleLanes.suffix(2).elementsEqual([51, 52]), "double lr P2 wheels last")
        require(doubleLanes.contains(27) && doubleLanes.contains(50), "double has P2 keys")
        require(doubleLanes.count == 52, "24+2 + 24+2")
        let doubleRL = BmsONEWheel.parse("rl", kind: .keyboard24Double)!
        require(
            BmsONEWheel.keyLanes(kind: .keyboard24Double, wheel: doubleRL).prefix(2).elementsEqual([1, 2]),
            "double rl P1 keys first"
        )
        require(
            BmsONEWheel.keyLanes(kind: .keyboard24Double, wheel: doubleRL).contains(51)
                && BmsONEWheel.keyLanes(kind: .keyboard24Double, wheel: doubleRL).firstIndex(of: 51)
                    ?? 99 < BmsONEWheel.keyLanes(kind: .keyboard24Double, wheel: doubleRL).firstIndex(of: 27) ?? 0,
            "double rl P2 wheels before keys"
        )
        let keyboard = BmsONEViewMode(kind: .keyboard24Single)
        require(
            BmsONEWheel.keyLanes(mode: keyboard, wheel: nil) == keyboard.keyLanes,
            "nil keeps displayed lanes"
        )
        require(
            keyboard.keyLanes == Array(1...16),
            "displayed mapping still 1...16"
        )
        require(
            keyboard.laneToChannel[25] == nil && keyboard.laneToChannel[17] == nil,
            "wheels and x>=17 stay off shared columns"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-wheel"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(BmsONEWheel.load(kind: .keyboard24Single, from: suite)?.stored == "l", "missing single is l")
        require(BmsONEWheel.load(kind: .keyboard24Double, from: suite)?.stored == "lr", "missing double is lr")
        BmsONEWheel.save("r", kind: .keyboard24Single, to: suite)
        require(BmsONEWheel.load(kind: .keyboard24Single, from: suite)?.stored == "r", "store right")
        BmsONEWheel.save("nope", kind: .keyboard24Single, to: suite)
        require(BmsONEWheel.load(kind: .keyboard24Single, from: suite)?.stored == "r", "reject garbage")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `SequenceViewCursor` Absolute / Composite / Real Time / Lane。
    private static func testStatus() {
        let bars: [Int64] = [0, 960]
        let beat7k = BmsONEViewMode.resolve("beat-7k")
        require(BmsONEStatus.absoluteLocation(240) == "240", "absolute 240")
        require(BmsONEStatus.absoluteLocation(0) == "0", "absolute 0")
        require(
            BmsONEStatus.compositeLocation(pulse: 0, bars: bars, resolution: 240) == "0:00:000",
            "composite 0"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 240, bars: bars, resolution: 240) == "0:01:000",
            "composite one beat"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 90, bars: bars, resolution: 240) == "0:00:090",
            "composite 90"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 960, bars: bars, resolution: 240) == "1:00:000",
            "composite next bar"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 961, bars: bars, resolution: 240) == "1:00:001",
            "composite 961"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 959, bars: bars, resolution: 240) == "0:03:239",
            "composite last tick of bar 0"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 12, bars: bars, resolution: 48) == "0:00:12",
            "tick width 2"
        )
        require(
            BmsONEStatus.compositeLocation(pulse: 0, bars: bars, resolution: 24000) == "0:00:00000",
            "tick width 5"
        )
        let sixteenth = BmsONEGridSize(numerator: 4, denominator: 16)
        require(
            BmsONEStatus.compositeLocation(
                pulse: 60,
                bars: bars,
                resolution: 240,
                coarseGrid: sixteenth
            ) == "0:01:000",
            "coarse 16th"
        )
        require(BmsONEStatus.realTime(0) == "0:00.000", "real 0")
        require(BmsONEStatus.realTime(1.5) == "0:01.500", "real 1.5")
        require(BmsONEStatus.realTime(61.5) == "1:01.500", "real 61.5")
        require(BmsONEStatus.realTime(10.5) == "0:10.500", "real 10.5")
        let half = BmsONEStatus.absoluteSeconds(pulse: 240, initBpm: 120, resolution: 240)
        require(abs(half - 0.5) < 1e-12, "120 BPM one beat is 0.5s")
        require(BmsONEStatus.realTime(half) == "0:00.500", "real 0.5")
        let changed = BmsONEStatus.absoluteSeconds(
            pulse: 480,
            initBpm: 120,
            resolution: 240,
            bpmNotes: [(y: 240, v: 240)]
        )
        require(abs(changed - 0.75) < 1e-12, "BPM change before query")
        require(BmsONEStatus.realTime(changed) == "0:00.750", "real 0.75")
        let onEvent = BmsONEStatus.absoluteSeconds(
            pulse: 240,
            initBpm: 120,
            resolution: 240,
            bpmNotes: [(y: 240, v: 240)]
        )
        require(abs(onEvent - 0.5) < 1e-12, "BPM on query pulse not applied")
        require(BmsONEStatus.laneName(0, mode: beat7k) == "BGM", "lane 0 is BGM")
        require(BmsONEStatus.laneName(-1, mode: beat7k) == "BGM", "negative lane is BGM")
        require(BmsONEStatus.laneName(1, mode: beat7k) == "Key 1", "7k key 1")
        require(BmsONEStatus.laneName(8, mode: beat7k) == "Scratch", "7k scratch")
        require(BmsONEStatus.laneName(99, mode: beat7k) == "?", "unknown lane")
        require(BmsONEStatus.laneX(channel: "01", mode: beat7k) == 0, "01 is BGM")
        require(BmsONEStatus.laneX(channel: "B1", mode: beat7k) == 0, "B1 is BGM")
        require(BmsONEStatus.laneX(channel: "16", mode: beat7k) == 8, "16 is scratch")
        require(BmsONEStatus.laneX(channel: "03", mode: beat7k) == nil, "BPM has no lane")
        let beat14 = BmsONEViewMode.resolve("beat-14k")
        require(BmsONEStatus.laneName(16, mode: beat14) == "P2 Scratch", "14k P2 scratch")
        require(BmsONEStatus.laneName(9, mode: beat14) == "P2 Key 1", "14k P2 key 1")
        require(BmsONEStatus.laneName(6, mode: BmsONEViewMode.resolve("beat-5k")) == "?", "5k has no key 6")
        require(BmsONEStatus.laneName(9, mode: BmsONEViewMode.resolve("popn-9k")) == "Key 9", "pop 9")
        require(
            BmsONEStatus.laneName(1, mode: BmsONEViewMode.resolve("circularrhythm-single")) == "Key Red",
            "circular red"
        )
        require(BmsONEStatus.noteName(0) == "C1", "C1")
        require(BmsONEStatus.noteName(23) == "B2", "B2")
        require(
            BmsONEStatus.laneName(1, mode: BmsONEViewMode.resolve("keyboard-24k")) == "Key C1",
            "24k first key"
        )
        require(
            BmsONEStatus.laneName(27, mode: BmsONEViewMode.resolve("keyboard-24k-double")) == "P2 Key C1",
            "24k double P2"
        )
        require(BmsONEStatus.laneName(1, mode: BmsONEViewMode.resolve("plain")) == "Lane 1", "plain lane")
        require(BmsONEStatus.range("0", "240") == "0 - 240", "range text")
        require(BmsONEStatus.absoluteLocationRange(begin: 0, end: 240) == "0 - 240", "abs range")
        require(
            BmsONEStatus.compositeLocationRange(begin: 0, end: 240, bars: bars, resolution: 240)
                == "0:00:000 - 0:01:000",
            "composite range"
        )
        require(
            BmsONEStatus.realTimeRange(begin: 0, end: 240, initBpm: 120, resolution: 240)
                == "0:00.000 - 0:00.500",
            "real range"
        )
        let fine = BmsONEGridSize.fallbackFine
        let down = BmsONEStatus.rubberBandTimes(
            origin: 0,
            time: 240,
            snapToGrid: false,
            snapSelection: true,
            bars: bars,
            resolution: 240,
            fineGrid: fine
        )
        require(down.begin == 0 && down.end == 240 && down.cursor == 240, "drag down")
        let up = BmsONEStatus.rubberBandTimes(
            origin: 240,
            time: 0,
            snapToGrid: false,
            snapSelection: true,
            bars: bars,
            resolution: 240,
            fineGrid: fine
        )
        require(up.begin == 0 && up.end == 240 && up.cursor == 0, "drag up")
        let lower90 = BmsONESnap.snapToLowerFineGrid(
            time: 90,
            bars: bars,
            resolution: 240,
            fineGrid: fine
        )
        let upper90 = BmsONESnap.snapToUpperFineGrid(
            time: 90,
            bars: bars,
            resolution: 240,
            fineGrid: fine
        )
        require(
            BmsONEStatus.rubberBandOriginPulse(
                time: 90,
                snapToGrid: true,
                snapSelection: true,
                bars: bars,
                resolution: 240,
                fineGrid: fine
            ) == lower90,
            "origin snapped lower"
        )
        require(
            BmsONEStatus.rubberBandOriginPulse(
                time: 90.8,
                snapToGrid: true,
                snapSelection: false,
                bars: bars,
                resolution: 240,
                fineGrid: fine
            ) == 90,
            "origin unsnapped truncates"
        )
        let snappedDown = BmsONEStatus.rubberBandTimes(
            origin: 0,
            time: 90,
            snapToGrid: true,
            snapSelection: true,
            bars: bars,
            resolution: 240,
            fineGrid: fine
        )
        require(
            snappedDown.begin == 0 && snappedDown.end == upper90 && snappedDown.cursor == upper90,
            "snapped drag down uses upper"
        )
        require(!BmsONEStatus.containsNote(location: 240, length: 0, begin: 0, end: 240), "short at end excluded")
        require(BmsONEStatus.containsNote(location: 0, length: 240, begin: 0, end: 240), "long covers range")
        require(BmsONEStatus.containsEvent(location: 0, begin: 0, end: 240), "bpm at begin")
        require(!BmsONEStatus.containsEvent(location: 240, begin: 0, end: 240), "bpm at end excluded")
        require(BmsONEStatus.rubberBandKind(channel: "11", mode: beat7k) == .keys, "11 is keys")
        require(BmsONEStatus.rubberBandKind(channel: "16", mode: beat7k) == .keys, "scratch is keys")
        require(BmsONEStatus.rubberBandKind(channel: "B1", mode: beat7k) == .bgm, "B1 is bgm")
        require(BmsONEStatus.rubberBandKind(channel: "01", mode: beat7k) == .bgm, "01 is bgm")
        require(BmsONEStatus.rubberBandKind(channel: "03", mode: beat7k) == .bpm, "03 is bpm")
        require(BmsONEStatus.rubberBandKind(channel: "09", mode: beat7k) == nil, "STOP has no band")
        require(BmsONEStatus.rubberBandKind(channel: "04", mode: beat7k) == nil, "BGA has no band")
        require(BmsONEStatus.rubberBandKind(channel: "CH0", mode: beat7k) == .sound, "CH0 is sound")
        require(BmsONEStatus.laneX(channel: "CH1", mode: beat7k) == 0, "sound lane writes BGM")
        let keys = ["16", "11", "12", "13", "14", "15", "18", "19"]
        require(
            BmsONEStatus.rubberBandChannels(origin: "11", current: "13", visualOrder: keys)
                == ["11", "12", "13"],
            "key span"
        )
        require(
            BmsONEStatus.rubberBandChannels(origin: "13", current: "11", visualOrder: keys)
                == ["11", "12", "13"],
            "key span reversed"
        )
        let frames: [String: CGRect] = [
            "11": CGRect(x: 10, y: 0, width: 20, height: 1),
            "13": CGRect(x: 50, y: 0, width: 20, height: 1),
        ]
        require(
            BmsONEStatus.clampedRubberBandChannel(
                current: "12",
                visualOrder: ["11", "12", "13"],
                pointX: 0,
                frames: frames
            ) == "12",
            "current stays"
        )
        require(
            BmsONEStatus.clampedRubberBandChannel(
                current: nil,
                visualOrder: ["11", "12", "13"],
                pointX: 0,
                frames: frames
            ) == "11",
            "left of kind clamps first"
        )
        require(
            BmsONEStatus.clampedRubberBandChannel(
                current: "B1",
                visualOrder: ["11", "12", "13"],
                pointX: 80,
                frames: frames
            ) == "13",
            "other kind clamps last"
        )
        let suiteName = "org.ibmsc.native.tests.bmsone-status-coarse"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        require(
            BmsONESnap.loadCoarseGrid(from: suite) == BmsONEGridSize.defaultMedium,
            "missing coarse is 4/4"
        )
        BmsONESnap.saveCoarseGrid(sixteenth, to: suite)
        require(BmsONESnap.loadCoarseGrid(from: suite) == sixteenth, "store coarse 4/16")
        suite.removePersistentDomain(forName: suiteName)
    }

    /// 对照 `SequenceViewCursor` Object 段和 `FindConflictsByLanes`。
    private static func testObjectHint() {
        let mode = BmsONEViewMode.resolve("beat-7k")
        let empty: [(x: Int64, y: Int64, l: Int64)] = []
        require(BmsONEStatus.soundNote == "Sound note", "sound note")
        require(BmsONEStatus.clickAddSoundNote == "Click to add a sound note", "click add sound")
        require(BmsONEStatus.bpmEvent(140) == "BPM event: 140", "bpm 140")
        require(BmsONEStatus.bpmEvent(120.5) == "BPM event: 120.5", "bpm 120.5")
        require(
            BmsONEStatus.clickAddBpmEvent(120) == "Click to add a BPM event: 120",
            "click add bpm"
        )
        require(BmsONEStatus.barLine == "Bar line", "bar line")
        require(BmsONEStatus.temporaryBarLine == "Temporary bar line", "temp bar")
        require(BmsONEStatus.clickAddBarLine == "Click to add a bar line", "click add bar")
        let one: [(x: Int64, y: Int64, l: Int64)] = [(x: 1, y: 0, l: 0)]
        require(
            BmsONEStatus.soundNoteObject(pulse: 0, lane: 1, hitLength: 0, notes: one) == "Sound note",
            "single sound"
        )
        let layered: [(x: Int64, y: Int64, l: Int64)] = [(x: 1, y: 0, l: 0), (x: 1, y: 0, l: 0)]
        require(
            BmsONEStatus.soundNoteObject(pulse: 0, lane: 1, hitLength: 0, notes: layered)
                == "Layered sound note",
            "same length layered"
        )
        let uneven: [(x: Int64, y: Int64, l: Int64)] = [(x: 1, y: 0, l: 240), (x: 1, y: 0, l: 0)]
        require(
            BmsONEStatus.soundNoteObject(pulse: 0, lane: 1, hitLength: 0, notes: uneven)
                == "Sound note  [Layered notes have different lengths]",
            "nonuniform layering"
        )
        let cover: [(x: Int64, y: Int64, l: Int64)] = [(x: 1, y: 0, l: 480), (x: 1, y: 240, l: 0)]
        require(
            BmsONEStatus.soundNoteObject(pulse: 240, lane: 1, hitLength: 0, notes: cover)
                == "Sound note  [Overlapping with a long note]",
            "overlapping long"
        )
        require(
            BmsONEStatus.inferredBpm(pulse: 240, initBpm: 120, bpmNotes: [(y: 240, v: 180)]) == 120,
            "bpm on query not applied"
        )
        require(
            BmsONEStatus.inferredBpm(pulse: 241, initBpm: 120, bpmNotes: [(y: 240, v: 180)]) == 180,
            "bpm before query"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: true,
                channel: "11",
                pulse: 0,
                hitLength: nil,
                inMeasureArea: false,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: []
            ) == "Click to add a sound note",
            "write empty key"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: false,
                channel: "11",
                pulse: 0,
                hitLength: nil,
                inMeasureArea: false,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: []
            ).isEmpty,
            "edit empty key has no object"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: true,
                channel: "03",
                pulse: 240,
                hitLength: nil,
                inMeasureArea: false,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: [(y: 240, v: 140)]
            ) == "BPM event: 140",
            "existing bpm"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: true,
                channel: "03",
                pulse: 120,
                hitLength: nil,
                inMeasureArea: false,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: [(y: 240, v: 140)]
            ) == "Click to add a BPM event: 120",
            "new bpm uses init"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: true,
                channel: nil,
                pulse: 0,
                hitLength: nil,
                inMeasureArea: true,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: []
            ) == "Bar line",
            "explicit bar"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: true,
                channel: nil,
                pulse: 960,
                hitLength: nil,
                inMeasureArea: true,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: []
            ) == "Temporary bar line",
            "ephemeral bar"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: true,
                channel: nil,
                pulse: 120,
                hitLength: nil,
                inMeasureArea: true,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: []
            ) == "Click to add a bar line",
            "new bar"
        )
        require(
            BmsONEStatus.objectHint(
                writeMode: false,
                channel: nil,
                pulse: 120,
                hitLength: nil,
                inMeasureArea: true,
                viewMode: mode,
                notes: empty,
                explicitBars: [0],
                allBars: [0, 960],
                initBpm: 120,
                bpmNotes: []
            ).isEmpty,
            "edit empty measure is SetTime"
        )
    }

    private static func testInfoDock() {
        require(BmsONEMainWindowLayout.infoDockTitle == "Info", "Info dock title")
        require(BmsONEMainWindowLayout.infoChartNameLabel == "Chart Name", "Chart Name")
        require(BmsONEMainWindowLayout.infoJudgeRankLabel == "Judge Rank", "Judge Rank")
        require(BmsONEMainWindowLayout.infoModeHintLabel == "Mode Hint", "Mode Hint")
        require(BmsONEMainWindowLayout.infoTitleImageLabel == "Title Image", "Title Image")
        require(BmsONEMainWindowLayout.infoPreviewMusicLabel == "Preview Music", "Preview Music")
        require(BmsONEMainWindowLayout.infoExtraFieldsTitle == "Extra fields", "Extra fields title")
        require(
            BmsONEMainWindowLayout.infoShowExtraFieldsKey == "DocumentInfoView/ShowExtraFields",
            "Info extra settings key"
        )
        require(BmsONEMainWindowLayout.infoDockSize == CGSize(width: 200, height: 258), "Info dock working size")
        require(BmsONEInfoDefaults.extraFieldsHint == CGSize(width: 200, height: 180), "Info extra size hint")
    }

    private static func testInfoExtraFields() {
        require(
            BmsonSelectedObjects.formatExtraFields(objectJSON: #"{"field_2":[0,240,480],"field_1":"14:00 2015/11/14"}"#)
                == "\"field_1\": \"14:00 2015/11/14\",\n\"field_2\": [0,240,480]",
            "Info extra display sorts keys"
        )
        require(BmsonSelectedObjects.formatExtraFields(objectJSON: #"{"banner":"bn.png"}"#) == "\"banner\": \"bn.png\"", "format keeps banner text")
        require(BmsonSelectedObjects.preparedExtraObjectJSON("\"field_1\": \"14:00\",") == "{\"field_1\": \"14:00\"}", "Info extra strips comma")
        require(BmsonSelectedObjects.preparedExtraObjectJSON("") == "{}", "empty Extra fields is {}")
        require(BmsonSelectedObjects.preparedExtraObjectJSON("nope") == nil, "plain extra rejected")
        require(BmsonSelectedObjects.preparedExtraObjectJSON("{") == nil, "truncated extra rejected")
        let defaults = UserDefaults(suiteName: "IBMSNative.InfoExtraTest")!
        defaults.removePersistentDomain(forName: "IBMSNative.InfoExtraTest")
        require(!BmsONEInfoDefaults.loadShowExtraFields(from: defaults), "Info extra default off")
        BmsONEInfoDefaults.storeShowExtraFields(true, to: defaults)
        require(BmsONEInfoDefaults.loadShowExtraFields(from: defaults), "Info extra stored on")
        defaults.removePersistentDomain(forName: "IBMSNative.InfoExtraTest")
    }

    /// 对照 `ExternalViewer` / `ExternalViewerConfigDialog`。
    private static func testExternalViewer() {
        require(
            BmsONEDialogLayout.externalViewerTitle == "External Viewer Configuration",
            "viewer title"
        )
        require(BmsONEDialogLayout.externalViewerSize == CGSize(width: 720, height: 440), "viewer working size")
        require(BmsONEDialogLayout.externalViewerListMinimum == CGSize(width: 80, height: 80), "list min")
        require(BmsONEDialogLayout.externalViewerListMaximumWidth == 200, "list max width")
        require(BmsONEDialogLayout.externalViewerIconSize == CGSize(width: 32, height: 32), "list icon")
        require(BmsONEDialogLayout.externalViewerButtonIconSize == CGSize(width: 20, height: 20), "edit icon")
        require(BmsONEDialogLayout.externalViewerNewName == "New Viewer", "new name")
        require(BmsONEDialogLayout.externalViewerDefaultDirectory == "$(exedir)", "default dir")
        require(BmsONEDialogLayout.externalViewerFilenameVar == "$(filename)", "filename var")
        require(BmsONEDialogLayout.externalViewerExeDirDesc == "application directory", "exedir caption")

        let created = BmsONEExternalViewerConfig.createNew()
        require(created.displayName == "New Viewer", "CreateNewConfig name")
        require(created.programPath.isEmpty && created.argumentFormatPlayBeg.isEmpty, "CreateNewConfig empty")
        require(created.executionDirectory == "$(exedir)", "CreateNewConfig dir")

        var store = BmsONEExternalViewerStore.empty
        require(!store.isPlayable, "empty is not playable")
        store.add()
        require(store.isPlayable && store.currentIndex == 0, "add makes playable")
        store.add(at: 0)
        require(store.viewers.count == 2 && store.currentIndex == 0, "add at current")
        require(store.viewers[0].displayName == "New Viewer", "inserted new")
        store.viewers[0].displayName = "First"
        store.viewers[1].displayName = "Second"
        store.moveDown(at: 0)
        require(store.viewers[0].displayName == "Second" && store.currentIndex == 1, "move down")
        store.moveUp(at: 1)
        require(store.viewers[0].displayName == "First" && store.currentIndex == 0, "move up")
        store.remove(at: 0)
        require(store.viewers[0].displayName == "Second" && store.currentIndex == 0, "remove clamps")
        store.setViewers(store.viewers, index: 9)
        require(store.currentIndex == 0, "invalid index becomes 0")
        store.setViewers([], index: 3)
        require(!store.isPlayable, "empty after set")

        let defaults = UserDefaults(suiteName: "IBMSNative.ExternalViewerTest")!
        defaults.removePersistentDomain(forName: "IBMSNative.ExternalViewerTest")
        var saved = BmsONEExternalViewerStore.empty
        saved.add()
        saved.viewers[0].displayName = "LR2"
        saved.viewers[0].programPath = "/opt/player"
        saved.viewers[0].argumentFormatPlayBeg = "$(filename)"
        saved.store(to: defaults)
        let loaded = BmsONEExternalViewerStore.load(from: defaults)
        require(loaded.viewers.count == 1 && loaded.viewers[0].displayName == "LR2", "stored name")
        require(loaded.viewers[0].programPath == "/opt/player", "stored path")
        require(loaded.viewers[0].argumentFormatPlayBeg == "$(filename)", "stored play beg")
        require(loaded.currentIndex == 0 && loaded.isPlayable, "stored index")
        defaults.removePersistentDomain(forName: "IBMSNative.ExternalViewerTest")

        require(
            BmsONEExternalViewer.evaluateArgument(
                "$(directory)/$(filename) $(missing)",
                environment: ["directory": "/song", "filename": "t.bmson"]
            ) == "/song/t.bmson ",
            "unknown var empty"
        )
        require(
            BmsONEExternalViewer.evaluateArgument("pre$(filename)post", environment: ["filename": "a.bmson"])
                == "prea.bmsonpost",
            "adjacent text"
        )
        require(BmsONEExternalViewer.evaluateArgument("$(1bad)", environment: ["1bad": "x"]) == "$(1bad)", "bad name")
        require(BmsONEExternalViewer.barNumber(pulse: 0, bars: [0, 960]) == 0, "bar 0")
        require(BmsONEExternalViewer.barNumber(pulse: 960, bars: [0, 960]) == 1, "bar 1")
        require(BmsONEExternalViewer.qtNumber(0.5) == "0.5", "qt 0.5")
        require(BmsONEExternalViewer.qtNumber(1) == "1", "qt 1")

        let playHere = BmsONEExternalViewer.environment(
            directory: "/song",
            filename: "/song/__bmsone_temp_0.bmson",
            programPath: "/opt/player/bin",
            pulse: 240,
            bars: [0, 960],
            initBpm: 120,
            resolution: 240
        )
        require(playHere["directory"] == "/song", "env directory")
        require(playHere["filename"] == "/song/__bmsone_temp_0.bmson", "env filename")
        require(playHere["exedir"] == "/opt/player", "env exedir")
        require(playHere["ticks"] == "240", "env ticks")
        require(playHere["time"] == "0.5", "env time 0.5s")
        require(playHere["measure"] == "0", "env measure")
        let playBeg = BmsONEExternalViewer.environment(
            directory: "/song",
            filename: "/song/t.bmson",
            programPath: "/opt/player/bin"
        )
        require(playBeg["ticks"] == nil && playBeg["time"] == nil && playBeg["measure"] == nil, "beg has no time")
        require(
            BmsONEExternalViewer.evaluateArgument("$(exedir)", environment: playBeg) == "/opt/player",
            "default dir eval"
        )

        require(
            BmsONEExternalViewer.tempFileName(directory: "/song", exists: { _ in false })
                == "/song/__bmsone_temp_0.bmson",
            "first temp"
        )
        require(
            BmsONEExternalViewer.tempFileName(directory: "/song", exists: { $0.hasSuffix("_0.bmson") })
                == "/song/__bmsone_temp_1.bmson",
            "skip used temp"
        )
        require(
            BmsONEExternalViewer.tempFileName(directory: "/song", exists: { _ in true }) == nil,
            "temp exhausted"
        )
        require(
            BmsONEExternalViewer.macosCommand(program: "/opt/player/bin", argument: "a.bmson")
                == "\"/opt/player/bin\" a.bmson",
            "macos command"
        )
        require(BmsONEDialogLayout.externalViewerPlayBegMenu.hasSuffix("(External Viewer)"), "play beg menu")
        require(BmsONEDialogLayout.externalViewerPlayHereMenu.hasSuffix("(External Viewer)"), "play here menu")
        require(BmsONEDialogLayout.externalViewerStopMenu.hasSuffix("(External Viewer)"), "stop menu")
        require(BmsONEExternalViewer.projectDirectory(filePath: nil) == nil, "untitled has no dir")
        require(BmsONEExternalViewer.projectDirectory(filePath: "/song.bmson") == nil, "root file")
        require(BmsONEExternalViewer.projectDirectory(filePath: "/song/t.bmson") == "/song", "project dir")
        require(
            BmsONEExternalViewer.currentLocation(
                time: 90,
                bars: [0, 960],
                resolution: 240,
                fineGrid: BmsONEGridSize.fallbackFine
            ) == 60,
            "GetCurrentLocation snap"
        )
        require(
            BmsONEExternalViewer.currentLocation(
                viewLength: 30720,
                scrollY: 0,
                viewportHeight: 400,
                zoomY: 0.2,
                bars: [0],
                resolution: 240,
                fineGrid: BmsONEGridSize.fallbackFine
            ) == 28680,
            "viewport bottom 28720 -> 28680"
        )
        require(BmsONEExternalViewer.splitCommandArguments("") == [], "empty args")
        require(BmsONEExternalViewer.splitCommandArguments("a b") == ["a", "b"], "split args")
        require(BmsONEExternalViewer.splitCommandArguments("\"a b\" c") == ["a b", "c"], "quoted args")

        var playStore = BmsONEExternalViewerStore.empty
        let ignoredEmpty = BmsONEExternalViewer.plan(
            kind: .beginning,
            store: playStore,
            filePath: "/song/t.bmson",
            json: "{}",
            currentTempPath: nil
        )
        require(ignoredEmpty.0 == .ignored, "empty store ignored")
        playStore.add()
        playStore.viewers[0].programPath = "/usr/bin/true"
        playStore.viewers[0].argumentFormatPlayBeg = "$(filename)"
        playStore.viewers[0].argumentFormatPlayHere = "$(filename) $(ticks)"
        playStore.viewers[0].argumentFormatStop = "--stop"
        let ignoredUntitled = BmsONEExternalViewer.plan(
            kind: .beginning,
            store: playStore,
            filePath: nil,
            json: "{}",
            currentTempPath: nil
        )
        require(ignoredUntitled.0 == .ignored, "untitled ignored")
        let ignoredRoot = BmsONEExternalViewer.plan(
            kind: .beginning,
            store: playStore,
            filePath: "/t.bmson",
            json: "{}",
            currentTempPath: nil
        )
        require(ignoredRoot.0 == .ignored, "root ignored")
        let ignoredStop = BmsONEExternalViewer.plan(
            kind: .stop,
            store: playStore,
            filePath: "/song/t.bmson",
            json: "{}",
            currentTempPath: nil
        )
        require(ignoredStop.0 == .ignored, "stop without temp")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IBMSNative.ExternalViewerPlay.\(ProcessInfo.processInfo.globallyUniqueString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let chart = dir.appendingPathComponent("chart.bmson")
        try! Data().write(to: chart)
        let json = #"{"version":"1.0.0"}"#
        let play = BmsONEExternalViewer.plan(
            kind: .beginning,
            store: playStore,
            filePath: chart.path,
            json: json,
            currentTempPath: nil
        )
        guard case .run(let launch) = play.0 else {
            require(false, "play beginning runs")
            return
        }
        require(launch.tempFilePath.hasSuffix("/__bmsone_temp_0.bmson"), "temp 0")
        require((try! String(contentsOfFile: launch.tempFilePath, encoding: .utf8)) == json, "wrote json")
        require(launch.argument == launch.tempFilePath, "beg filename")
        require(launch.workingDirectory == "/usr/bin", "exedir")
        require(
            launch.command == "\"/usr/bin/true\" \(launch.tempFilePath)",
            "beg command"
        )
        let here = BmsONEExternalViewer.plan(
            kind: .here,
            store: playStore,
            filePath: chart.path,
            json: json,
            currentTempPath: play.1,
            pulse: 240,
            bars: [0, 960],
            initBpm: 120,
            resolution: 240
        )
        guard case .run(let hereLaunch) = here.0 else {
            require(false, "play here runs")
            return
        }
        require(hereLaunch.argument.hasSuffix(" 240"), "here ticks")
        let stop = BmsONEExternalViewer.plan(
            kind: .stop,
            store: playStore,
            filePath: chart.path,
            json: json,
            currentTempPath: here.1
        )
        guard case .run(let stopLaunch) = stop.0 else {
            require(false, "stop runs")
            return
        }
        require(stopLaunch.argument == "--stop", "stop arg")
        require(stop.1 == here.1, "stop keeps temp")
        require(
            BmsONEExternalViewer.start(
                BmsONEExternalViewerLaunch(
                    program: "/usr/bin/true",
                    argument: "",
                    workingDirectory: dir.path,
                    command: "\"/usr/bin/true\" ",
                    tempFilePath: hereLaunch.tempFilePath
                )
            ),
            "true starts"
        )
        require(
            !BmsONEExternalViewer.start(
                BmsONEExternalViewerLaunch(
                    program: "",
                    argument: "",
                    workingDirectory: dir.path,
                    command: "\"\" ",
                    tempFilePath: ""
                )
            ),
            "empty program fails"
        )
        require(
            !BmsONEExternalViewer.start(
                BmsONEExternalViewerLaunch(
                    program: "/no/such/external-viewer",
                    argument: "",
                    workingDirectory: dir.path,
                    command: "\"/no/such/external-viewer\" ",
                    tempFilePath: ""
                )
            ),
            "missing program fails"
        )
        require(BmsONEExternalViewer.cleanTempFile(here.1), "clean temp")
        if let path = here.1 {
            require(!FileManager.default.fileExists(atPath: path), "temp removed")
        }
        for index in 0..<99 {
            try! Data().write(to: dir.appendingPathComponent("__bmsone_temp_\(index).bmson"))
        }
        let exhausted = BmsONEExternalViewer.plan(
            kind: .beginning,
            store: playStore,
            filePath: chart.path,
            json: json,
            currentTempPath: nil
        )
        require(exhausted.0 == .failed, "99 temps fail")
    }

    /// 对照 `MainWindow::HelpAbout`。
    private static func testAbout() {
        require(BmsONEAbout.title == "About BmsONE", "about title")
        require(BmsONEAbout.helpMenuTitle == "Help", "Help menu")
        require(BmsONEAbout.versionLine == "version beta 0.2.1 macOS", "version line")
        require(BmsONEAbout.copyright == "Copyright 2015-2017 exclusion", "copyright")
        require(BmsONEAbout.url == "https://github.com/excln/BmsONE", "url")
        require(BmsONEAbout.oggVersion == "Xiph.Org libOgg 1.3.2", "ogg")
        require(BmsONEAbout.vorbisVersion == "Xiph.Org libVorbis 1.3.5", "vorbis")
        require(BmsONEAbout.html.contains("<h2>BmsONE</h2>"), "html title")
        require(BmsONEAbout.html.contains("libogg"), "html ogg")
        require(BmsONEAbout.html.contains("libvorbis"), "html vorbis")
        require(BmsONEAbout.html.contains("http://www.qt.io/"), "html qt url")
        require(!BmsONEAbout.informativeText.contains("__DATE__"), "no compile date")
        require(BmsONEAbout.informativeText.contains(BmsONEAbout.librariesTitle), "libraries")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
