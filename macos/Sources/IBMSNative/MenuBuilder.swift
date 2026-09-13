import AppKit

@MainActor
enum MenuBuilder {
    static func installMainMenu(
        mainWindowController: MainWindowController,
        showPreview: @escaping () -> Void,
        showBmsONE: @escaping () -> Void = {},
        showBmhelper: @escaping () -> Void = {},
        showWoslicer: @escaping () -> Void = {}
    ) -> NSObject {
        let mainMenu = NSMenu()

        let previewTarget = NativeToolsMenuTarget(
            showPreview: showPreview,
            showBmsONE: showBmsONE,
            showBmhelper: showBmhelper,
            showWoslicer: showWoslicer
        )

        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "IBMSNative")
        applicationItem.submenu = applicationMenu
        let aboutItem = applicationMenu.addItem(withTitle: "About iBMSC", action: #selector(MainWindowController.showAbout(_:)), keyEquivalent: "")
        aboutItem.target = mainWindowController
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit IBMSNative", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        fileItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.file)
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let newItem = fileMenu.addItem(withTitle: "New", action: #selector(MainWindowController.newDocument(_:)), keyEquivalent: "n")
        newItem.target = mainWindowController
        newItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileNew)
        let openItem = fileMenu.addItem(withTitle: "Open…", action: #selector(MainWindowController.openDocument(_:)), keyEquivalent: "o")
        openItem.target = mainWindowController
        openItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileOpen)
        let importSMItem = fileMenu.addItem(withTitle: "Import from .SM file", action: #selector(MainWindowController.importSM(_:)), keyEquivalent: "")
        importSMItem.target = mainWindowController
        importSMItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileImportSM)
        let importIBMSCItem = fileMenu.addItem(withTitle: "Import from .IBMSC file", action: #selector(MainWindowController.importIBMSC(_:)), keyEquivalent: "")
        importIBMSCItem.target = mainWindowController
        importIBMSCItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileImportIBMSC)
        let importBmsAsBmsonItem = fileMenu.addItem(
            withTitle: "Import BMS as BMSON…",
            action: #selector(MainWindowController.importBmsAsBmson(_:)),
            keyEquivalent: ""
        )
        importBmsAsBmsonItem.target = mainWindowController
        fileMenu.addItem(.separator())
        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(MainWindowController.saveDocument(_:)), keyEquivalent: "s")
        saveItem.target = mainWindowController
        saveItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileSave)
        let saveAsItem = fileMenu.addItem(withTitle: "Save As…", action: #selector(MainWindowController.saveDocumentAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = mainWindowController
        saveAsItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileSaveAs)
        let exportItem = fileMenu.addItem(withTitle: "Export .IBMSC file", action: #selector(MainWindowController.exportIBMSC(_:)), keyEquivalent: "")
        exportItem.target = mainWindowController
        exportItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.fileExportIBMSC)
        let exportWavItem = fileMenu.addItem(
            withTitle: "Export WAV…",
            action: #selector(MainWindowController.exportBmsonWav(_:)),
            keyEquivalent: ""
        )
        exportWavItem.target = mainWindowController
        let convertResolutionItem = fileMenu.addItem(
            withTitle: BmsONEDialogLayout.convertResolutionMenuTitle,
            action: #selector(MainWindowController.convertBmsonResolution(_:)),
            keyEquivalent: ""
        )
        convertResolutionItem.target = mainWindowController
        let audioSlicerItem = fileMenu.addItem(
            withTitle: AudioSlicerLayout.menuTitle,
            action: #selector(NativeToolsMenuTarget.openWoslicer(_:)),
            keyEquivalent: ""
        )
        audioSlicerItem.target = previewTarget
        fileMenu.addItem(.separator())
        for index in 0..<LegacyRecent.slotCount {
            let recentItem = fileMenu.addItem(
                withTitle: LegacyRecent.emptyTitle,
                action: #selector(MainWindowController.openRecent(_:)),
                keyEquivalent: ""
            )
            recentItem.target = mainWindowController
            recentItem.tag = index
            recentItem.isEnabled = false
        }

        let editItem = NSMenuItem()
        editItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.edit)
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        let undoItem = editMenu.addItem(withTitle: "Undo", action: #selector(MainWindowController.undoDocument(_:)), keyEquivalent: "z")
        undoItem.target = mainWindowController
        undoItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editUndo)
        let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(MainWindowController.redoDocument(_:)), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = mainWindowController
        redoItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editRedo)
        editMenu.addItem(.separator())
        tag(
            editMenu.addItem(withTitle: "Cut", action: #selector(ChartSurfaceView.cut(_:)), keyEquivalent: "x"),
            LegacyLocale.ID.editCut
        )
        tag(
            editMenu.addItem(withTitle: "Copy", action: #selector(ChartSurfaceView.copy(_:)), keyEquivalent: "c"),
            LegacyLocale.ID.editCopy
        )
        tag(
            editMenu.addItem(withTitle: "Paste", action: #selector(ChartSurfaceView.paste(_:)), keyEquivalent: "v"),
            LegacyLocale.ID.editPaste
        )
        tag(
            editMenu.addItem(withTitle: "Delete", action: #selector(ChartSurfaceView.delete(_:)), keyEquivalent: ""),
            LegacyLocale.ID.editDelete
        )
        tag(
            editMenu.addItem(withTitle: "Select All", action: #selector(ChartSurfaceView.selectAll(_:)), keyEquivalent: "a"),
            LegacyLocale.ID.editSelectAll
        )
        let transferKeyItem = editMenu.addItem(
            withTitle: BmsONEMainWindowLayout.transferToKeyTitle,
            action: #selector(MainWindowController.transferBmsonNotesToKey(_:)),
            keyEquivalent: ""
        )
        transferKeyItem.target = mainWindowController
        transferKeyItem.identifier = NSUserInterfaceItemIdentifier("editTransferToKey")
        let transferBgmItem = editMenu.addItem(
            withTitle: BmsONEMainWindowLayout.transferToBgmTitle,
            action: #selector(MainWindowController.transferBmsonNotesToBGM(_:)),
            keyEquivalent: ""
        )
        transferBgmItem.target = mainWindowController
        transferBgmItem.identifier = NSUserInterfaceItemIdentifier("editTransferToBgm")
        let separateItem = editMenu.addItem(
            withTitle: BmsONEMainWindowLayout.separateLayeredTitle,
            action: #selector(MainWindowController.separateBmsonLayeredNotes(_:)),
            keyEquivalent: ""
        )
        separateItem.target = mainWindowController
        separateItem.identifier = NSUserInterfaceItemIdentifier("editSeparateLayered")
        let clearMasterItem = editMenu.addItem(
            withTitle: BmsONEMainWindowLayout.clearMasterCacheTitle,
            action: #selector(MainWindowController.clearBmsonMasterCache(_:)),
            keyEquivalent: ""
        )
        clearMasterItem.target = mainWindowController
        clearMasterItem.identifier = NSUserInterfaceItemIdentifier("editClearMasterCache")
        let preferencesItem = editMenu.addItem(
            withTitle: BmsONEDialogLayout.preferencesMenuTitle,
            action: #selector(MainWindowController.showBmsonPreferences(_:)),
            keyEquivalent: ","
        )
        preferencesItem.target = mainWindowController
        preferencesItem.identifier = NSUserInterfaceItemIdentifier("editBmsonPreferences")
        let gotoItem = editMenu.addItem(
            withTitle: "Go To Measure...",
            action: #selector(MainWindowController.gotoMeasure(_:)),
            keyEquivalent: "g"
        )
        gotoItem.target = mainWindowController
        editMenu.addItem(.separator())
        let encodingItem = NSMenuItem(title: "Encoding", action: nil, keyEquivalent: "")
        encodingItem.submenu = mainWindowController.encodingMenu
        editMenu.addItem(encodingItem)
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(withTitle: "Find / Delete / Replace", action: #selector(MainWindowController.showFind(_:)), keyEquivalent: "f")
        findItem.target = mainWindowController
        findItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editFind)
        let statisticsItem = editMenu.addItem(withTitle: "Statistics", action: #selector(MainWindowController.showStatistics(_:)), keyEquivalent: "t")
        statisticsItem.target = mainWindowController
        statisticsItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editStat)
        editMenu.addItem(.separator())
        let timeSelectItem = editMenu.addItem(
            withTitle: "Time Selection Tool",
            action: #selector(MainWindowController.selectTimeTool(_:)),
            keyEquivalent: ""
        )
        timeSelectItem.target = mainWindowController
        timeSelectItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editTimeSelect)
        assignFunctionKey(timeSelectItem, "F1")
        let selectItem = editMenu.addItem(
            withTitle: "Select Tool",
            action: #selector(MainWindowController.selectSelectTool(_:)),
            keyEquivalent: ""
        )
        selectItem.target = mainWindowController
        selectItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editSelect)
        assignFunctionKey(selectItem, "F2")
        let writeItem = editMenu.addItem(
            withTitle: "Write Tool",
            action: #selector(MainWindowController.selectWriteTool(_:)),
            keyEquivalent: ""
        )
        writeItem.target = mainWindowController
        writeItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editWrite)
        assignFunctionKey(writeItem, "F3")
        let editModeItem = editMenu.addItem(
            withTitle: BmsONEMainWindowLayout.editModeTitle,
            action: #selector(MainWindowController.selectSelectTool(_:)),
            keyEquivalent: "1"
        )
        editModeItem.target = mainWindowController
        editModeItem.identifier = NSUserInterfaceItemIdentifier("editMode")
        let writeModeItem = editMenu.addItem(
            withTitle: BmsONEMainWindowLayout.writeModeTitle,
            action: #selector(MainWindowController.selectWriteTool(_:)),
            keyEquivalent: "2"
        )
        writeModeItem.target = mainWindowController
        writeModeItem.identifier = NSUserInterfaceItemIdentifier("writeMode")
        editMenu.addItem(.separator())
        let myO2Item = editMenu.addItem(withTitle: "MyO2 ToolBox (Chinese Only)", action: #selector(MainWindowController.showMyO2(_:)), keyEquivalent: "")
        myO2Item.target = mainWindowController
        myO2Item.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.editMyO2)

        let viewItem = NSMenuItem()
        viewItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.view)
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let timingItem = viewMenu.addItem(withTitle: "Timing…", action: #selector(MainWindowController.showTiming(_:)), keyEquivalent: "t")
        timingItem.keyEquivalentModifierMask = [.command, .option]
        timingItem.target = mainWindowController
        viewMenu.addItem(.separator())
        for side in ChartSide.allCases {
            let item = viewMenu.addItem(withTitle: side.rawValue, action: #selector(MainWindowController.setChartSide(_:)), keyEquivalent: "")
            item.target = mainWindowController
            item.representedObject = side.rawValue
        }
        viewMenu.addItem(.separator())
        let toolbarItem = viewMenu.addItem(withTitle: "ToolBar", action: #selector(MainWindowController.toggleToolBar(_:)), keyEquivalent: "")
        toolbarItem.target = mainWindowController
        let optionsItem = viewMenu.addItem(withTitle: "Options Panel", action: #selector(MainWindowController.toggleOptionsPanel(_:)), keyEquivalent: "")
        optionsItem.target = mainWindowController
        let statusItem = viewMenu.addItem(withTitle: "Status Bar", action: #selector(MainWindowController.toggleStatusBar(_:)), keyEquivalent: "")
        statusItem.target = mainWindowController
        let leftSplitterItem = viewMenu.addItem(withTitle: "Left Splitter", action: #selector(MainWindowController.toggleLeftSplitter(_:)), keyEquivalent: "")
        leftSplitterItem.target = mainWindowController
        let rightSplitterItem = viewMenu.addItem(withTitle: "Right Splitter", action: #selector(MainWindowController.toggleRightSplitter(_:)), keyEquivalent: "")
        rightSplitterItem.target = mainWindowController
        viewMenu.addItem(.separator())
        let gridItem = viewMenu.addItem(withTitle: "Grid", action: #selector(MainWindowController.toggleGrid(_:)), keyEquivalent: "")
        gridItem.target = mainWindowController
        let subItem = viewMenu.addItem(withTitle: "Sub", action: #selector(MainWindowController.toggleSubGrid(_:)), keyEquivalent: "")
        subItem.target = mainWindowController
        let backgroundItem = viewMenu.addItem(withTitle: "BackGround", action: #selector(MainWindowController.toggleBackground(_:)), keyEquivalent: "")
        backgroundItem.target = mainWindowController
        let measureIndexItem = viewMenu.addItem(withTitle: "Measure Index", action: #selector(MainWindowController.toggleMeasureIndex(_:)), keyEquivalent: "")
        measureIndexItem.target = mainWindowController
        let measureItem = viewMenu.addItem(withTitle: "Measure Line", action: #selector(MainWindowController.toggleMeasureLine(_:)), keyEquivalent: "")
        measureItem.target = mainWindowController
        let verticalItem = viewMenu.addItem(withTitle: "Vertical Line", action: #selector(MainWindowController.toggleVerticalLine(_:)), keyEquivalent: "")
        verticalItem.target = mainWindowController
        let captionItem = viewMenu.addItem(withTitle: "Column Caption", action: #selector(MainWindowController.toggleColumnCaption(_:)), keyEquivalent: "")
        captionItem.target = mainWindowController
        viewMenu.addItem(.separator())
        let scrollItem = viewMenu.addItem(withTitle: "SCROLL", action: #selector(MainWindowController.toggleScrollColumn(_:)), keyEquivalent: "")
        scrollItem.target = mainWindowController
        let bpmItem = viewMenu.addItem(withTitle: "BPM", action: #selector(MainWindowController.toggleBPMColumn(_:)), keyEquivalent: "")
        bpmItem.target = mainWindowController
        let stopItem = viewMenu.addItem(withTitle: "STOP", action: #selector(MainWindowController.toggleStopColumn(_:)), keyEquivalent: "")
        stopItem.target = mainWindowController
        let bgaItem = viewMenu.addItem(withTitle: "BGA / Layer / Poor", action: #selector(MainWindowController.toggleBGAColumns(_:)), keyEquivalent: "")
        bgaItem.target = mainWindowController
        viewMenu.addItem(.separator())
        let viewModeItem = NSMenuItem()
        viewModeItem.title = BmsONEViewMode.menuTitle
        viewModeItem.identifier = NSUserInterfaceItemIdentifier("viewMode")
        let viewModeMenu = NSMenu(title: BmsONEViewMode.menuTitle)
        for mode in BmsONEViewMode.menuModes {
            let item = viewModeMenu.addItem(
                withTitle: mode.name,
                action: #selector(MainWindowController.selectBmsonViewMode(_:)),
                keyEquivalent: ""
            )
            item.target = mainWindowController
            item.representedObject = mode.canonicalHint
            item.identifier = NSUserInterfaceItemIdentifier("viewMode.\(mode.canonicalHint)")
        }
        viewModeItem.submenu = viewModeMenu
        viewMenu.addItem(viewModeItem)
        let scratchItem = NSMenuItem()
        scratchItem.title = BmsONEScratch.menuTitle
        scratchItem.identifier = NSUserInterfaceItemIdentifier("viewScratch")
        let scratchMenu = NSMenu(title: BmsONEScratch.menuTitle)
        scratchMenu.delegate = mainWindowController
        scratchItem.submenu = scratchMenu
        viewMenu.addItem(scratchItem)
        let laneOrderItem = NSMenuItem()
        laneOrderItem.title = BmsONELaneOrder.menuTitle
        laneOrderItem.identifier = NSUserInterfaceItemIdentifier("viewLaneOrder")
        let laneOrderMenu = NSMenu(title: BmsONELaneOrder.menuTitle)
        laneOrderMenu.delegate = mainWindowController
        laneOrderItem.submenu = laneOrderMenu
        viewMenu.addItem(laneOrderItem)
        let laneCountItem = viewMenu.addItem(
            withTitle: BmsONEPlainLanes.menuTitle(count: BmsONEPlainLanes.defaultCount),
            action: #selector(MainWindowController.showBmsonLaneCount(_:)),
            keyEquivalent: ""
        )
        laneCountItem.target = mainWindowController
        laneCountItem.identifier = NSUserInterfaceItemIdentifier("viewLaneCount")
        let colorSchemeItem = NSMenuItem()
        colorSchemeItem.title = BmsONEColorScheme.menuTitle
        colorSchemeItem.identifier = NSUserInterfaceItemIdentifier("viewColorScheme")
        let colorSchemeMenu = NSMenu(title: BmsONEColorScheme.menuTitle)
        colorSchemeMenu.delegate = mainWindowController
        colorSchemeItem.submenu = colorSchemeMenu
        viewMenu.addItem(colorSchemeItem)
        let wheelItem = NSMenuItem()
        wheelItem.title = BmsONEWheel.menuTitle
        wheelItem.identifier = NSUserInterfaceItemIdentifier("viewWheel")
        let wheelMenu = NSMenu(title: BmsONEWheel.menuTitle)
        wheelMenu.delegate = mainWindowController
        wheelItem.submenu = wheelMenu
        viewMenu.addItem(wheelItem)
        let gridSettingItem = viewMenu.addItem(
            withTitle: BmsONEDialogLayout.gridSettingMenuTitle,
            action: #selector(MainWindowController.showBmsonGridSetting(_:)),
            keyEquivalent: ""
        )
        gridSettingItem.target = mainWindowController
        gridSettingItem.identifier = NSUserInterfaceItemIdentifier("viewGridSetting")
        let darkenItem = viewMenu.addItem(
            withTitle: BmsONEMainWindowLayout.darkenInactiveChannelsTitle,
            action: #selector(MainWindowController.toggleDarkenInactiveBmsonChannels(_:)),
            keyEquivalent: "d"
        )
        darkenItem.target = mainWindowController
        darkenItem.identifier = NSUserInterfaceItemIdentifier("viewDarkenInactiveChannels")
        let snapItem = viewMenu.addItem(
            withTitle: BmsONEMainWindowLayout.snapToGridTitle,
            action: #selector(MainWindowController.toggleBmsonSnapToGrid(_:)),
            keyEquivalent: "t"
        )
        snapItem.target = mainWindowController
        snapItem.identifier = NSUserInterfaceItemIdentifier("viewSnapToGrid")
        let zoomMenuItem = NSMenuItem()
        zoomMenuItem.title = BmsONEZoom.menuTitle
        zoomMenuItem.identifier = NSUserInterfaceItemIdentifier("viewZoom")
        let zoomMenu = NSMenu(title: BmsONEZoom.menuTitle)
        let zoomIn = zoomMenu.addItem(
            withTitle: BmsONEZoom.zoomInTitle,
            action: #selector(MainWindowController.zoomBmsonIn(_:)),
            keyEquivalent: "+"
        )
        zoomIn.target = mainWindowController
        zoomIn.identifier = NSUserInterfaceItemIdentifier("viewZoomIn")
        let zoomOut = zoomMenu.addItem(
            withTitle: BmsONEZoom.zoomOutTitle,
            action: #selector(MainWindowController.zoomBmsonOut(_:)),
            keyEquivalent: "-"
        )
        zoomOut.target = mainWindowController
        zoomOut.identifier = NSUserInterfaceItemIdentifier("viewZoomOut")
        zoomMenu.addItem(.separator())
        let zoomReset = zoomMenu.addItem(
            withTitle: BmsONEZoom.resetTitle,
            action: #selector(MainWindowController.zoomBmsonReset(_:)),
            keyEquivalent: "0"
        )
        zoomReset.target = mainWindowController
        zoomReset.identifier = NSUserInterfaceItemIdentifier("viewZoomReset")
        zoomMenuItem.submenu = zoomMenu
        viewMenu.addItem(zoomMenuItem)
        let laneModeItem = NSMenuItem()
        laneModeItem.title = BmsONESoundChannelLaneMode.menuTitle
        laneModeItem.identifier = NSUserInterfaceItemIdentifier("viewSoundChannelLanes")
        let laneModeMenu = NSMenu(title: BmsONESoundChannelLaneMode.menuTitle)
        for mode in BmsONESoundChannelLaneMode.allCases {
            let item = laneModeMenu.addItem(
                withTitle: mode.title,
                action: #selector(MainWindowController.selectBmsonSoundChannelLaneMode(_:)),
                keyEquivalent: ""
            )
            item.target = mainWindowController
            item.representedObject = mode.storedValue
            item.identifier = NSUserInterfaceItemIdentifier("viewSoundChannelLanes.\(mode.storedValue)")
        }
        laneModeItem.submenu = laneModeMenu
        viewMenu.addItem(laneModeItem)

        let channelMenuItem = NSMenuItem()
        channelMenuItem.identifier = NSUserInterfaceItemIdentifier("channel")
        mainMenu.addItem(channelMenuItem)
        let channelMenu = NSMenu(title: BmsONEMainWindowLayout.channelMenuTitle)
        channelMenuItem.submenu = channelMenu
        let addChannel = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelAddTitle,
            action: #selector(MainWindowController.addBmsonChannel(_:)),
            keyEquivalent: "n"
        )
        addChannel.keyEquivalentModifierMask = [.command, .shift]
        addChannel.target = mainWindowController
        addChannel.identifier = NSUserInterfaceItemIdentifier("channelAdd")
        channelMenu.addItem(.separator())
        let prevChannel = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelPreviousTitle,
            action: #selector(MainWindowController.selectPreviousBmsonChannel(_:)),
            keyEquivalent: "["
        )
        prevChannel.target = mainWindowController
        prevChannel.identifier = NSUserInterfaceItemIdentifier("channelPrevious")
        let nextChannel = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelNextTitle,
            action: #selector(MainWindowController.selectNextBmsonChannel(_:)),
            keyEquivalent: "]"
        )
        nextChannel.target = mainWindowController
        nextChannel.identifier = NSUserInterfaceItemIdentifier("channelNext")
        let findMenu = NSMenu(title: "Find")
        let findNext = findMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelFindNextTitle,
            action: #selector(MainWindowController.findNextBmsonChannel(_:)),
            keyEquivalent: ""
        )
        findNext.target = mainWindowController
        findNext.identifier = NSUserInterfaceItemIdentifier("channelFindNext")
        let findPrev = findMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelFindPreviousTitle,
            action: #selector(MainWindowController.findPreviousBmsonChannel(_:)),
            keyEquivalent: ""
        )
        findPrev.target = mainWindowController
        findPrev.identifier = NSUserInterfaceItemIdentifier("channelFindPrevious")
        findMenu.addItem(.separator())
        let findActive = findMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelFindActiveOnlyTitle,
            action: #selector(MainWindowController.toggleBmsonFindActiveChannelsOnly(_:)),
            keyEquivalent: "d"
        )
        findActive.keyEquivalentModifierMask = [.command, .shift]
        findActive.target = mainWindowController
        findActive.identifier = NSUserInterfaceItemIdentifier("channelFindActiveOnly")
        let findHide = findMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelFindHideOthersTitle,
            action: #selector(MainWindowController.toggleBmsonFindHideOthers(_:)),
            keyEquivalent: "f"
        )
        findHide.keyEquivalentModifierMask = [.command, .shift]
        findHide.target = mainWindowController
        findHide.identifier = NSUserInterfaceItemIdentifier("channelFindHideOthers")
        let channelFindItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        channelFindItem.submenu = findMenu
        channelMenu.addItem(channelFindItem)
        channelMenu.addItem(.separator())
        let moveLeft = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelMoveLeftTitle,
            action: #selector(MainWindowController.moveBmsonChannelLeft(_:)),
            keyEquivalent: ""
        )
        moveLeft.target = mainWindowController
        moveLeft.identifier = NSUserInterfaceItemIdentifier("channelMoveLeft")
        let moveRight = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelMoveRightTitle,
            action: #selector(MainWindowController.moveBmsonChannelRight(_:)),
            keyEquivalent: ""
        )
        moveRight.target = mainWindowController
        moveRight.identifier = NSUserInterfaceItemIdentifier("channelMoveRight")
        channelMenu.addItem(.separator())
        let deleteChannel = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelDeleteTitle,
            action: #selector(MainWindowController.destroyBmsonChannel(_:)),
            keyEquivalent: ""
        )
        deleteChannel.target = mainWindowController
        deleteChannel.identifier = NSUserInterfaceItemIdentifier("channelDelete")
        channelMenu.addItem(.separator())
        let selectFile = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelSelectFileTitle,
            action: #selector(MainWindowController.selectBmsonChannelFile(_:)),
            keyEquivalent: ""
        )
        selectFile.target = mainWindowController
        selectFile.identifier = NSUserInterfaceItemIdentifier("channelSelectFile")
        let previewSource = channelMenu.addItem(
            withTitle: BmsONEMainWindowLayout.channelPreviewSourceTitle,
            action: #selector(MainWindowController.previewBmsonChannelSource(_:)),
            keyEquivalent: ""
        )
        previewSource.target = mainWindowController
        previewSource.identifier = NSUserInterfaceItemIdentifier("channelPreviewSource")

        let optionsMenuItem = NSMenuItem()
        optionsMenuItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.options)
        mainMenu.addItem(optionsMenuItem)
        let optionsMenu = NSMenu(title: "Options")
        optionsMenuItem.submenu = optionsMenu
        addChromeEntries(LegacyChromeMenu.options, to: optionsMenu, target: mainWindowController)

        let conversionsMenuItem = NSMenuItem()
        conversionsMenuItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.conversion)
        mainMenu.addItem(conversionsMenuItem)
        let conversionsMenu = NSMenu(title: "Conversions")
        conversionsMenuItem.submenu = conversionsMenu
        conversionsMenu.autoenablesItems = false
        addChromeEntries(LegacyChromeMenu.conversions, to: conversionsMenu, target: mainWindowController)

        let previewMenuItem = NSMenuItem()
        previewMenuItem.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.preview)
        mainMenu.addItem(previewMenuItem)
        let previewMenu = NSMenu(title: "Preview")
        previewMenuItem.submenu = previewMenu
        addChromeEntries(LegacyChromeMenu.preview, to: previewMenu, target: mainWindowController)
        previewMenu.addItem(.separator())
        let playBegExternal = previewMenu.addItem(
            withTitle: BmsONEDialogLayout.externalViewerPlayBegMenu,
            action: #selector(MainWindowController.playExternalViewerFromBeginning(_:)),
            keyEquivalent: ""
        )
        playBegExternal.target = mainWindowController
        playBegExternal.identifier = NSUserInterfaceItemIdentifier("previewExternalPlayBeg")
        let playHereExternal = previewMenu.addItem(
            withTitle: BmsONEDialogLayout.externalViewerPlayHereMenu,
            action: #selector(MainWindowController.playExternalViewerFromHere(_:)),
            keyEquivalent: ""
        )
        playHereExternal.target = mainWindowController
        playHereExternal.identifier = NSUserInterfaceItemIdentifier("previewExternalPlayHere")
        let stopExternal = previewMenu.addItem(
            withTitle: BmsONEDialogLayout.externalViewerStopMenu,
            action: #selector(MainWindowController.stopExternalViewer(_:)),
            keyEquivalent: ""
        )
        stopExternal.target = mainWindowController
        stopExternal.identifier = NSUserInterfaceItemIdentifier("previewExternalStop")
        let viewerMenu = NSMenu(title: BmsONEDialogLayout.externalViewerMenuTitle)
        let viewerItem = NSMenuItem(
            title: BmsONEDialogLayout.externalViewerMenuTitle,
            action: nil,
            keyEquivalent: ""
        )
        viewerItem.submenu = viewerMenu
        viewerItem.identifier = NSUserInterfaceItemIdentifier("previewExternalViewer")
        previewMenu.addItem(viewerItem)
        let configureViewers = previewMenu.addItem(
            withTitle: BmsONEDialogLayout.preferencesConfigureViewers,
            action: #selector(MainWindowController.showExternalViewerConfig(_:)),
            keyEquivalent: ""
        )
        configureViewers.target = mainWindowController
        configureViewers.identifier = NSUserInterfaceItemIdentifier("previewConfigureViewers")
        viewerMenu.delegate = mainWindowController

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let bmsoneItem = windowMenu.addItem(
            withTitle: BmsONEWindowTitle.appName,
            action: #selector(NativeToolsMenuTarget.openBmsONE(_:)),
            keyEquivalent: ""
        )
        bmsoneItem.target = previewTarget
        let bmhelperItem = windowMenu.addItem(
            withTitle: BmhelperMainLayout.title,
            action: #selector(NativeToolsMenuTarget.openBmhelper(_:)),
            keyEquivalent: ""
        )
        bmhelperItem.target = previewTarget
        let woslicerItem = windowMenu.addItem(
            withTitle: WoslicerLayout.windowTitle,
            action: #selector(NativeToolsMenuTarget.openWoslicer(_:)),
            keyEquivalent: ""
        )
        woslicerItem.target = previewTarget
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: BmsONEAbout.helpMenuTitle)
        helpItem.submenu = helpMenu
        let aboutBmson = helpMenu.addItem(
            withTitle: BmsONEAbout.title,
            action: #selector(MainWindowController.showBmsonAbout(_:)),
            keyEquivalent: ""
        )
        aboutBmson.target = mainWindowController
        aboutBmson.identifier = NSUserInterfaceItemIdentifier("helpBmsonAbout")

        NativeLocalization.localize(menu: mainMenu)
        NSApp.mainMenu = mainMenu
        return previewTarget
    }

    private static func addChromeEntries(
        _ entries: [LegacyChromeMenu.Entry],
        to menu: NSMenu,
        target: MainWindowController
    ) {
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let title):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                if title == "Theme" {
                    item.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.optionsTheme)
                    item.submenu = target.themeMenu
                } else if title == "Language" {
                    item.identifier = NSUserInterfaceItemIdentifier(LegacyLocale.ID.optionsLanguage)
                    item.submenu = target.languageMenu
                }
                menu.addItem(item)
            case .item(let title, let command, let shortcut, _, _):
                let item = menu.addItem(
                    withTitle: title,
                    action: #selector(MainWindowController.performChromeCommand(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = command
                if let identifier = LegacyLocale.itemID(command: command) {
                    item.identifier = NSUserInterfaceItemIdentifier(identifier)
                }
                if let shortcut {
                    assignFunctionKey(item, shortcut)
                }
            }
        }
    }

    /// 包里有的菜单项才改标题。缺元素保持 Designer 英文。
    static func applyLocale(_ pack: LegacyLocalePack, to menu: NSMenu) {
        for item in menu.items {
            if let identifier = item.identifier?.rawValue,
               let path = LegacyLocale.menuPaths[identifier],
               let title = LegacyLocale.menuDisplay(pack, path: path) {
                item.title = title
                item.submenu?.title = title
            }
            if let submenu = item.submenu {
                applyLocale(pack, to: submenu)
            }
        }
    }

    static func menuItem(in menu: NSMenu?, id: String) -> NSMenuItem? {
        menu?.items.first { $0.identifier?.rawValue == id }
    }

    @discardableResult
    private static func tag(_ item: NSMenuItem, _ identifier: String) -> NSMenuItem {
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        return item
    }

    private static func assignFunctionKey(_ item: NSMenuItem, _ name: String) {
        let key: Int
        switch name {
        case "F1": key = Int(NSF1FunctionKey)
        case "F2": key = Int(NSF2FunctionKey)
        case "F3": key = Int(NSF3FunctionKey)
        case "F5": key = Int(NSF5FunctionKey)
        case "F6": key = Int(NSF6FunctionKey)
        case "F7": key = Int(NSF7FunctionKey)
        case "F8": key = Int(NSF8FunctionKey)
        default:
            return
        }
        item.keyEquivalent = String(utf16CodeUnits: [unichar(key)], count: 1)
        item.keyEquivalentModifierMask = []
    }
}

@MainActor
private final class NativeToolsMenuTarget: NSObject {
    private let showPreview: () -> Void
    private let showBmsONE: () -> Void
    private let showBmhelper: () -> Void
    private let showWoslicer: () -> Void

    init(
        showPreview: @escaping () -> Void,
        showBmsONE: @escaping () -> Void,
        showBmhelper: @escaping () -> Void,
        showWoslicer: @escaping () -> Void
    ) {
        self.showPreview = showPreview
        self.showBmsONE = showBmsONE
        self.showBmhelper = showBmhelper
        self.showWoslicer = showWoslicer
    }

    @objc func openPreview(_ sender: Any?) {
        showPreview()
    }

    @objc func openBmsONE(_ sender: Any?) {
        showBmsONE()
    }

    @objc func openBmhelper(_ sender: Any?) {
        showBmhelper()
    }

    @objc func openWoslicer(_ sender: Any?) {
        showWoslicer()
    }
}
