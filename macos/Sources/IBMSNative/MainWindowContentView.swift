import AppKit
import UniformTypeIdentifiers

@MainActor
final class MainWindowContentView: NSView {
    private let actions = EditorActionTarget()
    private let toolbar = MainToolbarView()
    private let optionsSidebar = OptionsSidebarView()
    private let rightColumn = NSView()
    private let selectedObjectsView = BmsONESelectedObjectsView()
    private let infoDockView = BmsONEInfoDockView()
    private let statusStrip = StatusStripView()
    private let timeStrip = TimeSelectionStripView()
    private var pendingMetadata: [String: String] = [:]
    private let panes: [ChartEditorPane] = [
        ChartEditorPane(index: 0, fillsWidth: false),
        ChartEditorPane(index: 1, fillsWidth: true),
        ChartEditorPane(index: 2, fillsWidth: false)
    ]
    private let leftSplitter = ChartSplitterView()
    private let rightSplitter = ChartSplitterView()
    private var panelFocus = 1
    private var scrollDiffs = [0, 0, 0]
    private var suppressScrollFollow = false
    private var suppressSelectionSync = false
    private var chartSurface: ChartSurfaceView { panes[panelFocus].surface }
    private var showGrid = true
    private var showSubGrid = true
    private var showMeasureBar = true
    private var showBackground = true
    private var showMeasureNumber = true
    private var showVerticalLine = true
    private var showColumnCaption = true
    private var toolbarVisible = true
    private var optionsPanelVisible = true
    private var statusBarVisible = true
    private var toolbarHeightConstraint: NSLayoutConstraint?
    private var statusHeightConstraint: NSLayoutConstraint?
    private var optionsWidthConstraint: NSLayoutConstraint?
    private var optionsDividerWidthConstraint: NSLayoutConstraint?
    private var selectedObjectsHeightConstraint: NSLayoutConstraint?
    private var infoDockHeightConstraint: NSLayoutConstraint?
    private var selectedObjectsWanted = false
    var onChartSelectionChange: (() -> Void)?
    var onBmsonVisibleRangeChange: (() -> Void)?
    var onBmsonChannelInfoNeeded: (() -> Void)?
    var onBmsonFooterSelect: ((Int) -> Void)?
    var onBmsonFooterPreview: ((Int) -> Void)?
    var onBmsonFooterHeight: ((Int) -> Void)?
    var onBmsonFooterMenu: ((Int, NSPoint) -> Void)?
    var onBmsonPlayingFooterMenu: ((NSPoint) -> Void)?
    var onSelectedNoteLengthCommit: ((String) -> Bool)?
    var onSelectedNoteExtraCommit: ((String) -> Bool)?
    var onInfoExtraCommit: ((String) -> Bool)?
    private var showsScrollColumn = true
    private var showsBPMColumn = true
    private var showsStopColumn = true
    private var showsBGAColumns = true
    private var chartTheme = ChartTheme.defaultTheme
    private var selectedSide: ChartSide = .onePlayer
    private var selectedZoom: CGFloat = MainWindowChrome.defaultPixelsPerQuarterBeat
    private var selectedColumnScale: CGFloat = 1
    private var selectedBGMColumnCount = ChartBGM.defaultColumnCount
    var currentBGMColumnCount: Int { selectedBGMColumnCount }

    func setBGMColumnCount(_ count: Int) {
        let clamped = max(1, min(999, count))
        selectedBGMColumnCount = clamped
        optionsSidebar.setBGMColumnCount(clamped)
    }
    var selectedDivision: Int { optionsSidebar.selectedDivision }
    var selectedSubDivision: Int { optionsSidebar.selectedSubDivision }
    var gridHeightValue: Double { ChartZoom.clampField(Double(optionsSidebar.gridHeight)) }
    var gridWidthValue: Double { Double(optionsSidebar.gridWidth) }
    var slashValue: Int { optionsSidebar.slashValue }

    func setDivision(_ value: Int) {
        optionsSidebar.setDivisionValue(value)
    }

    func setSubDivision(_ value: Int) {
        optionsSidebar.setSubDivisionValue(value)
    }

    func setGridHeight(_ value: Double) {
        optionsSidebar.setGridHeight(value)
    }

    func setGridWidth(_ value: Double) {
        optionsSidebar.setGridWidth(value)
    }

    func setSlashValue(_ value: Int) {
        optionsSidebar.slashValue = LegacyGridDivision.clamp(value)
    }
    var ntInputEnabled: Bool { chartSurface.ntInputEnabled }

    /// `PanelVScroll(PanelFocus)` of the focused editor pane.
    func focusedPanelVScroll() -> Double {
        chartSurface.panelVScroll()
    }
    var gridVisible: Bool { showGrid }
    var subGridVisible: Bool { showSubGrid }
    var measureBarVisible: Bool { showMeasureBar }
    var backgroundVisible: Bool { showBackground }
    var measureNumberVisible: Bool { showMeasureNumber }
    var verticalLineVisible: Bool { showVerticalLine }
    var columnCaptionVisible: Bool { showColumnCaption }
    var toolBarVisible: Bool { toolbarVisible }
    var optionsVisible: Bool { optionsPanelVisible }
    var statusVisible: Bool { statusBarVisible }
    var errorCheckEnabled: Bool { toolbar.isChecked("TBErrorCheck") }
    var previewOnClickEnabled: Bool { toolbar.isChecked("TBPreviewOnClick") }
    var scrollColumnVisible: Bool { showsScrollColumn }
    var bpmColumnVisible: Bool { showsBPMColumn }
    var stopColumnVisible: Bool { showsStopColumn }
    var bgaColumnsVisible: Bool { showsBGAColumns }
    var currentTool: ChartTool { chartSurface.tool }
    private var idleErrorText = "Error"
    private var idleStatusLength = "Length = 0"
    private var statusLabels = LegacyStatus.Labels.english

    var leftSplitterVisible: Bool { leftSplitter.splitterVisible }
    var rightSplitterVisible: Bool { rightSplitter.splitterVisible }
    var scrollLocks: [Bool] { optionsSidebar.scrollLocks }

    func setLeftSplitterVisible(_ visible: Bool) {
        leftSplitter.splitterVisible = visible
    }

    func setRightSplitterVisible(_ visible: Bool) {
        rightSplitter.splitterVisible = visible
    }

    func setScrollLocks(_ locks: [Bool]) {
        optionsSidebar.setScrollLocks(locks)
        for (index, locked) in locks.enumerated() where locked {
            captureScrollDiffs(locking: index)
        }
    }

    func setNTInputEnabled(_ enabled: Bool) {
        forEachSurface { $0.ntInputEnabled = enabled }
        toolbar.setChecked("TBNTInput", enabled)
        toolbar.refreshConversionMenu()
    }

    func performChromeCommand(_ command: String) {
        handleToolbar(command)
    }

    func setPreviewPlayback(
        fromBeginning: @escaping () -> Void,
        fromHere: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        actions.playFromBeginning = fromBeginning
        actions.playFromHere = fromHere
        actions.stopPreview = stop
    }

    var snapEnabled: Bool { optionsSidebar.snapEnabled }

    func setSnapEnabled(_ enabled: Bool) {
        optionsSidebar.setSnapEnabled(enabled)
        BmsONESnap.save(enabled)
        forEachSurface { $0.snapEnabled = enabled }
    }

    func applyBmsonGrid(_ result: BmsONEGridApplyResult) {
        optionsSidebar.setDivisionValue(result.division)
        optionsSidebar.setSubDivisionValue(result.subDivision)
        setBmsonFineGrid(result.fineGrid)
        bmsonCoarseGrid = result.medium
        BmsONESnap.saveCoarseGrid(result.medium)
        if var context = bmsonStatus {
            context.coarseGrid = result.medium
            bmsonStatus = context
        }
        forEachSurface {
            $0.setDivision(result.division)
            $0.setSubDivision(result.subDivision)
        }
        refreshHoverStatus()
    }

    func setBmsonFineGrid(_ grid: BmsONEGridSize) {
        bmsonFineGrid = grid
        BmsONESnap.saveFineGrid(grid)
    }

    func pushBmsonSnap(applies: Bool, resolution: Int, bars: [Int64]) {
        let prefs = BmsONEPreferences.load()
        forEachSurface { surface in
            surface.applyBmsonSnap(
                applies: applies,
                resolution: resolution,
                fineGrid: bmsonFineGrid,
                bars: bars,
                snapHitTestInEdit: prefs.snappedHitTestInEditMode,
                snapSelectionInEdit: prefs.snappedSelectionInEditMode,
                viewMode: bmsonViewMode ?? BmsONEViewMode.resolve("")
            )
        }
    }

    func pushBmsonStatus(
        applies: Bool,
        resolution: Int = 240,
        bars: [Int64] = [],
        explicitBars: [Int64] = [0],
        initBpm: Double = 120,
        bpmNotes: [(y: Int64, v: Double)] = [],
        viewMode: BmsONEViewMode = BmsONEViewMode.resolve("")
    ) {
        if applies {
            bmsonStatus = BmsONEStatusContext(
                resolution: max(resolution, 1),
                bars: bars,
                explicitBars: explicitBars,
                initBpm: initBpm,
                bpmNotes: bpmNotes,
                viewMode: viewMode,
                coarseGrid: bmsonCoarseGrid
            )
        } else if bmsonStatus != nil {
            bmsonStatus = nil
            restoreIbmsStatusLocationFields()
        }
    }

    func pushBmsonViewMode(_ mode: BmsONEViewMode?) {
        bmsonViewMode = mode
    }

    func pushBmsonSoundLaneMode(_ mode: BmsONESoundChannelLaneMode?) {
        bmsonSoundLaneMode = mode
    }

    func pushBmsonZoom(applies: Bool, resolution: Int) {
        if applies {
            let first = bmsonZoomResolution == nil
            let safeResolution = max(resolution, 1)
            let resolutionChanged = bmsonZoomResolution != safeResolution
            if first {
                storedBmsGridHeight = Double(optionsSidebar.gridHeight)
                bmsonZoomY = BmsONEZoom.load()
            }
            bmsonZoomResolution = safeResolution
            if first || resolutionChanged {
                applyBmsonZoomY(bmsonZoomY)
            }
        } else if bmsonZoomResolution != nil {
            BmsONEZoom.save(bmsonZoomY)
            bmsonZoomResolution = nil
            if let restored = storedBmsGridHeight {
                storedBmsGridHeight = nil
                optionsSidebar.setGridHeight(restored)
            }
        }
    }

    func zoomBmsonIn() {
        guard let resolution = bmsonZoomResolution else { return }
        applyBmsonZoomY(BmsONEZoom.zoomIn(bmsonZoomY, resolution: resolution))
    }

    func zoomBmsonOut() {
        guard let resolution = bmsonZoomResolution else { return }
        applyBmsonZoomY(BmsONEZoom.zoomOut(bmsonZoomY, resolution: resolution))
    }

    func zoomBmsonReset() {
        guard let resolution = bmsonZoomResolution else { return }
        applyBmsonZoomY(BmsONEZoom.resetZoomY(resolution: resolution))
    }

    func pushBmsonLaneWaveform(_ state: BmsonLaneWaveform.State?) {
        forEachSurface { $0.applyLaneWaveform(state) }
    }

    func setBmsonFooterHeight(_ height: Int) {
        bmsonFooterHeight = CGFloat(BmsONEFooter.clampHeight(height))
        refreshBmsonFooter()
    }

    func pushBmsonFooter(visible: Bool) {
        if !visible {
            bmsonFooterSelected = []
        }
        refreshBmsonFooter(visible: visible)
    }

    func pushBmsonMaster(applies: Bool, waveform: BmsONEMasterWaveformCache?) {
        let prefs = BmsONEPreferences.load()
        let showLane = applies && prefs.canShowMasterLane
        let showMap = applies && prefs.canShowMiniMap
        forEachSurface { surface in
            surface.applyMasterOverlay(
                showLane: showLane,
                showMiniMap: showMap,
                pinned: prefs.fixMiniMap,
                opacity: prefs.miniMapOpacity,
                waveform: waveform
            )
        }
    }

    var disableVerticalMove: Bool { optionsSidebar.disableVerticalMove }
    private var darkensInactiveBmsonNotes = BmsONENoteDarken.load()
    var darkensInactiveBmsonChannels: Bool { darkensInactiveBmsonNotes }
    private var bmsonFineGrid = BmsONESnap.loadFineGrid()
    private var bmsonCoarseGrid = BmsONESnap.loadCoarseGrid()
    private var bmsonStatus: BmsONEStatusContext?
    var currentBmsonFineGrid: BmsONEGridSize { bmsonFineGrid }
    private var bmsonViewMode: BmsONEViewMode?
    private var bmsonSoundLaneMode: BmsONESoundChannelLaneMode?
    private var soundChannelNames: [String] = []
    private var shownSoundChannels: [Bool]?
    private var bmsonFooterSelected: Set<Int> = []
    private var bmsonFooterHeight = CGFloat(BmsONEFooter.defaultHeight)
    private var bmsonZoomResolution: Int?
    private var storedBmsGridHeight: Double?
    private var bmsonZoomY = BmsONEZoom.load()
    private var applyingBmsonZoom = false

    private func applyBmsonZoomY(_ zoomY: Double) {
        guard let resolution = bmsonZoomResolution else { return }
        let clamped = BmsONEZoom.clampZoomY(zoomY, resolution: resolution)
        bmsonZoomY = clamped
        BmsONEZoom.save(clamped)
        applyingBmsonZoom = true
        optionsSidebar.setGridHeight(BmsONEZoom.gridHeight(zoomY: clamped, resolution: resolution))
        applyingBmsonZoom = false
    }

    private func applyBmsonZoomWheel(_ event: ChartZoomWheelEvent) {
        guard let resolution = bmsonZoomResolution else { return }
        applyBmsonZoomY(
            BmsONEZoom.applyWheel(
                zoomY: bmsonZoomY,
                resolution: resolution,
                pixelDeltaY: Double(event.pixelDeltaY),
                hasPrecisePixels: event.hasPrecisePixels,
                notches: event.notches
            )
        )
    }

    func setBmsonChannelInfo(
        visible: Bool,
        format: String,
        length: String,
        waveform: BmsonOverallWaveform.Payload = .empty
    ) {
        optionsSidebar.setBmsonChannelInfo(
            visible: visible,
            format: format,
            length: length,
            waveform: waveform
        )
    }

    func setDarkensInactiveBmsonChannels(_ enabled: Bool) {
        darkensInactiveBmsonNotes = enabled
        BmsONENoteDarken.save(enabled)
        pushBmsonNoteDarken()
    }

    func pushBmsonNoteDarken(applies: Bool? = nil, currentChannel: Int? = nil) {
        let on = applies ?? (panes.contains { $0.surface.writesBmsonContinue })
        let channel = currentChannel ?? (selectedWavIndex >= 0 ? selectedWavIndex : 0)
        forEachSurface { surface in
            surface.applyBmsonNoteDarken(
                applies: on,
                enabled: darkensInactiveBmsonNotes,
                currentChannel: channel
            )
        }
    }

    func setDisableVerticalMove(_ enabled: Bool) {
        optionsSidebar.setDisableVerticalMove(enabled)
        forEachSurface { $0.disableVerticalMove = enabled }
    }

    var showFileNameEnabled: Bool { toolbar.isChecked("TBShowFileName") }

    func setShowFileNameEnabled(_ enabled: Bool) {
        toolbar.setChecked("TBShowFileName", enabled)
        toolbar.setIcon("TBShowFileName", icon: enabled ? "x16ShowFileName" : "x16ShowFileNameN")
        forEachSurface { $0.invalidateNoteLabels() }
    }

    func setErrorCheckEnabled(_ enabled: Bool) {
        toolbar.setChecked("TBErrorCheck", enabled)
        toolbar.setIcon("TBErrorCheck", icon: enabled ? LegacyErrorCheck.onIcon : LegacyErrorCheck.offIcon)
        forEachSurface { $0.errorCheckEnabled = enabled }
    }

    func setPreviewOnClickEnabled(_ enabled: Bool) {
        toolbar.setChecked("TBPreviewOnClick", enabled)
        forEachSurface { $0.previewOnClick = enabled }
    }

    func setToolBarVisible(_ visible: Bool) {
        toolbarVisible = visible
        toolbarHeightConstraint?.constant = visible ? MainWindowChrome.toolbarHeight : 0
        toolbar.isHidden = !visible
    }

    func setOptionsVisible(_ visible: Bool) {
        optionsPanelVisible = visible
        optionsWidthConstraint?.constant = visible ? MainWindowChrome.optionsScrollWidth : 0
        optionsDividerWidthConstraint?.constant = visible ? MainWindowChrome.resizerWidth : 0
        optionsSidebar.isHidden = !visible
        applySelectedObjectsVisibility()
    }

    func setSelectedObjectsVisible(_ visible: Bool) {
        selectedObjectsWanted = visible
        applySelectedObjectsVisibility()
    }

    func applySelectedObjects(_ display: BmsonSelectedObjects.Display) {
        selectedObjectsView.apply(display)
    }

    func applyBmsonInfo(_ fields: [String: String], extraText: String = "") {
        infoDockView.apply(fields, extraText: extraText)
    }

    func setStatusVisible(_ visible: Bool) {
        statusBarVisible = visible
        statusHeightConstraint?.constant = visible ? MainWindowChrome.statusHeight : 0
        applyBottomStripVisibility()
    }

    var wavAllowsMultipleSelection: Bool { optionsSidebar.wavAllowsMultipleSelection }
    var wavSynchronizeLabels: Bool { optionsSidebar.wavSynchronizeLabels }

    func setWavListOptions(multiSelect: Bool, synchronizeLabels: Bool) {
        optionsSidebar.setWavListOptions(multiSelect: multiSelect, synchronizeLabels: synchronizeLabels)
    }

    init(state: ApplicationState) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let editorRegion = makeEditorRegion()
        let divider = makeDivider()
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        [editorRegion, divider, rightColumn].forEach(addSubview)
        rightColumn.addSubview(optionsSidebar)
        optionsSidebar.attachBmsonDocks(info: infoDockView, selected: selectedObjectsView)
        infoDockView.onHeightChange = { [weak self] in
            guard let self else { return }
            self.optionsSidebar.setBmsonDocksVisible(self.optionsPanelVisible && self.selectedObjectsWanted)
        }
        selectedObjectsView.onHeightChange = { [weak self] in
            guard let self else { return }
            self.optionsSidebar.setBmsonDocksVisible(self.optionsPanelVisible && self.selectedObjectsWanted)
        }
        let dividerWidth = divider.widthAnchor.constraint(equalToConstant: MainWindowChrome.resizerWidth)
        let optionsWidth = rightColumn.widthAnchor.constraint(equalToConstant: MainWindowChrome.optionsScrollWidth)
        optionsDividerWidthConstraint = dividerWidth
        optionsWidthConstraint = optionsWidth
        infoDockView.onFieldCommit = { [weak self] key, value in
            guard let self, self.actions.isBusy?() != true else { return false }
            if self.actions.commitMetadata(key: key, value: value) {
                self.actions.refresh?()
                return true
            }
            return false
        }
        infoDockView.onExtraCommit = { [weak self] text in
            self?.onInfoExtraCommit?(text) ?? false
        }
        selectedObjectsView.onLengthCommit = { [weak self] text in
            self?.onSelectedNoteLengthCommit?(text) ?? false
        }
        selectedObjectsView.onExtraCommit = { [weak self] text in
            self?.onSelectedNoteExtraCommit?(text) ?? false
        }
        NSLayoutConstraint.activate([
            editorRegion.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorRegion.topAnchor.constraint(equalTo: topAnchor),
            editorRegion.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: editorRegion.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerWidth,
            rightColumn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightColumn.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: bottomAnchor),
            optionsWidth,
            optionsSidebar.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            optionsSidebar.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            optionsSidebar.topAnchor.constraint(equalTo: rightColumn.topAnchor),
            optionsSidebar.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor)
        ])
        wireChrome()
        registerForDraggedTypes([.fileURL])
    }

    var openDroppedURLs: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateChartFileDragPreview(from: sender)
        return droppedURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if optionsSidebar.containsResourceDrop(at: sender.draggingLocation) {
            return droppedURLs(from: sender).isEmpty ? [] : .copy
        }
        updateChartFileDragPreview(from: sender)
        return droppedURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        forEachSurface { $0.dragPreviewPaths = [] }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        forEachSurface { $0.dragPreviewPaths = [] }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        forEachSurface { $0.dragPreviewPaths = [] }
        let urls = droppedURLs(from: sender)
        guard !urls.isEmpty else { return false }
        openDroppedURLs?(urls)
        return true
    }

    private func updateChartFileDragPreview(from sender: NSDraggingInfo) {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let paths = LegacyLoadProgress.filterExisting(urls).map(\.path)
        forEachSurface { $0.dragPreviewPaths = paths }
    }

    private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return LegacyLoadProgress.filterExisting(urls)
    }

    required init?(coder: NSCoder) { nil }

    func installActions(
        isBusy: @escaping () -> Bool,
        newDocument: @escaping () -> Void,
        openDocument: @escaping () -> Void,
        saveDocument: @escaping () -> Void,
        saveDocumentAs: @escaping () -> Void,
        undo: @escaping () -> Void,
        redo: @escaping () -> Void,
        showPreview: @escaping () -> Void,
        setMetadata: @escaping (String, String) -> Bool,
        selectEncoding: @escaping (MetadataEncoding) -> Bool,
        setInitialBPM: @escaping (String) -> Bool,
        writeNote: @escaping (String, Int, Int, Int, String, Bool) -> Bool,
        writeTiming: @escaping (String, Int, Int, Int) -> Bool,
        moveNote: @escaping (ChartEventSnapshot, String, Int, Int, Int) -> Bool,
        convertNote: @escaping (ChartEventSnapshot, String) -> Bool,
        eraseNote: @escaping (ChartEventSnapshot) -> Bool,
        insertLongNote: @escaping (String, Int, Int, Int, Int, Int, String, String, Bool) -> Bool,
        moveLongNote: @escaping (LongNoteSnapshot, String, Int, Int, Int) -> Bool,
        moveLongNoteStart: @escaping (LongNoteSnapshot, Int, Int, Int) -> Bool,
        resizeLongNote: @escaping (LongNoteSnapshot, Int, Int, Int) -> Bool,
        eraseLongNote: @escaping (LongNoteSnapshot) -> Bool,
        convertLongNoteToShort: @escaping (LongNoteSnapshot, Bool) -> Bool,
        convertShortNotesToLong: @escaping (ChartEventSnapshot, ChartEventSnapshot) -> Bool,
        convertShortNoteToLongEndpoint: @escaping (ChartEventSnapshot) -> Bool,
        convertLongEndpointToShort: @escaping (ChartEventSnapshot) -> Bool,
        showFind: @escaping () -> Void,
        showStatistics: @escaping () -> Void,
        showVisualOptions: @escaping () -> Void,
        showGeneralOptions: @escaping () -> Void,
        showPlayerOptions: @escaping () -> Void,
        importSM: @escaping () -> Void,
        importIBMSC: @escaping () -> Void,
        exportIBMSC: @escaping () -> Void,
        showMyO2: @escaping () -> Void,
        hidePreview: @escaping () -> Void,
        refresh: @escaping () -> Void
    ) {
        actions.isBusy = isBusy
        actions.newDocument = newDocument
        actions.openDocument = openDocument
        actions.saveDocument = saveDocument
        actions.saveDocumentAs = saveDocumentAs
        actions.undo = undo
        actions.redo = redo
        actions.showPreview = showPreview
        actions.setMetadata = setMetadata
        actions.selectEncoding = selectEncoding
        actions.setInitialBPM = setInitialBPM
        actions.writeNote = writeNote
        actions.writeTiming = writeTiming
        actions.moveNote = moveNote
        actions.convertNote = convertNote
        actions.eraseNote = eraseNote
        actions.insertLongNote = insertLongNote
        actions.moveLongNote = moveLongNote
        actions.moveLongNoteStart = moveLongNoteStart
        actions.resizeLongNote = resizeLongNote
        actions.eraseLongNote = eraseLongNote
        actions.convertLongNoteToShort = convertLongNoteToShort
        actions.convertShortNotesToLong = convertShortNotesToLong
        actions.convertShortNoteToLongEndpoint = convertShortNoteToLongEndpoint
        actions.convertLongEndpointToShort = convertLongEndpointToShort
        actions.showFind = showFind
        actions.showStatistics = showStatistics
        actions.showVisualOptions = showVisualOptions
        actions.showGeneralOptions = showGeneralOptions
        actions.showPlayerOptions = showPlayerOptions
        actions.importSM = importSM
        actions.importIBMSC = importIBMSC
        actions.exportIBMSC = exportIBMSC
        actions.showMyO2 = showMyO2
        actions.hidePreview = hidePreview
        actions.refresh = refresh
    }

    func bindBmsonPulseWrites(
        writeNote: @escaping (String, Int64, String, Bool) -> Bool,
        writeTiming: @escaping (String, Int64) -> Bool,
        moveNote: @escaping (ChartEventSnapshot, String, Int64) -> Bool,
        insertLong: @escaping (String, Int64, Int64, String, Bool) -> Bool,
        moveLong: @escaping (LongNoteSnapshot, String, Int64) -> Bool,
        moveLongStart: @escaping (LongNoteSnapshot, Int64) -> Bool,
        resizeLong: @escaping (LongNoteSnapshot, Int64) -> Bool
    ) {
        actions.writeNoteAtPulse = writeNote
        actions.writeTimingAtPulse = writeTiming
        actions.moveNoteAtPulse = moveNote
        actions.insertLongAtPulse = insertLong
        actions.moveLongAtPulse = moveLong
        actions.moveLongStartAtPulse = moveLongStart
        actions.resizeLongAtPulse = resizeLong
    }

    func bindBmsonSoundChannelLane(_ handler: @escaping (Int) -> Bool) {
        actions.activateSoundChannelLane = handler
    }

    func setOpenRecent(_ handler: @escaping (Int) -> Void) {
        actions.openRecent = handler
    }

    func applyRecentSlots(_ slots: [String], noneWord: String = LegacyRecent.noneWord) {
        toolbar.setRecentSlots(slots, noneWord: noneWord)
    }

    func onTimeSelectionCommand(_ handler: @escaping (TimeSelectionCommand) -> Void) {
        actions.performTimeSelection = handler
    }

    func onEditBmsonBarLine(_ handler: @escaping (Double, Bool) -> Bool) {
        actions.editBmsonBarLine = handler
    }

    func onPasteClipboard(_ handler: @escaping (String, Double, Bool) -> Bool) {
        actions.pasteClipboard = handler
    }

    func onEraseSelection(
        _ handler: @escaping (Set<ChartEventSnapshot>, Set<LongNoteSnapshot>) -> Bool
    ) {
        actions.eraseSelection = handler
    }

    func onToggleNTInput(_ handler: @escaping (Bool) -> Void) {
        actions.toggleNTInput = handler
    }

    func onCopyNoteAtVPosition(_ handler: @escaping (ChartEventSnapshot, String, Double) -> Bool) {
        actions.copyNoteAtVPosition = handler
    }

    func onCopyLongNoteAtVPosition(_ handler: @escaping (LongNoteSnapshot, String, Double, Double) -> Bool) {
        actions.copyLongNoteAtVPosition = handler
    }

    func onCopyNotesAtVPosition(
        _ handler: @escaping ([ChartDuplicate.ShortCopy], [ChartDuplicate.LongCopy]) -> Bool
    ) {
        actions.copyNotesAtVPosition = handler
    }

    func onMoveNotesAtVPosition(
        _ handler: @escaping ([ChartDuplicate.ShortCopy], [ChartDuplicate.LongCopy]) -> Bool
    ) {
        actions.moveNotesAtVPosition = handler
    }

    func onMirrorSelected(_ handler: @escaping () -> Void) {
        actions.mirrorSelected = handler
    }

    func onMoveSelectedToColumn(_ handler: @escaping (String, Bool) -> Bool) {
        actions.moveSelectedToColumn = handler
    }

    func onMoveSelectedToBGM(_ handler: @escaping () -> Bool) {
        actions.moveSelectedToBGM = handler
    }

    func onModifySelected(_ handler: @escaping () -> Void) {
        actions.modifySelected = handler
    }

    func onDoubleClickNote(_ handler: @escaping (ChartEventSnapshot) -> Void) {
        actions.doubleClickNote = handler
    }

    func onDoubleClickLongNote(_ handler: @escaping (LongNoteSnapshot) -> Void) {
        actions.doubleClickLongNote = handler
    }

    func onApplyWavEdit(_ handler: @escaping (WavListEdit, Bool) -> Bool) {
        actions.applyWavEdit = handler
    }

    func onApplyBmpEdit(_ handler: @escaping (WavListEdit, Bool) -> Bool) {
        actions.applyBmpEdit = handler
    }

    func onApplyWaveformColor(_ handler: @escaping (ThemeColor) -> Void) {
        actions.applyWaveformColor = handler
    }

    func onApplyBeat(_ handler: @escaping ([Int], String, LegacyBeat.Mode) -> Bool) {
        actions.applyBeat = handler
    }

    func onApplyExpansion(_ handler: @escaping (String) -> Bool) {
        actions.applyExpansion = handler
    }

    func selectWavSlots(_ slots: [Int]) {
        optionsSidebar.selectWavSlots(slots)
    }

    var selectedWavIndex: Int { optionsSidebar.selectedWavIndex }

    func selectBmpSlots(_ slots: [Int]) {
        optionsSidebar.selectBmpSlots(slots)
    }

    func copyChartNotes() {
        let items = selectedChartItems()
        guard !items.events.isEmpty || !items.longNotes.isEmpty else { return }
        writeClipboard(encodeSelection(items))
        applySelection(events: [], longNotes: [])
    }

    func cutChartNotes() {
        let items = selectedChartItems()
        guard !items.events.isEmpty || !items.longNotes.isEmpty else { return }
        writeClipboard(encodeSelection(items))
        deleteSelectedNotes()
    }

    func pasteChartNotes() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        _ = actions.pasteClipboard?(text, chartSurface.clipboardPasteBaseVPosition(), ntInputEnabled)
    }

    func deleteSelectedNotes() {
        let items = selectedChartItems()
        if let eraseSelection = actions.eraseSelection {
            _ = eraseSelection(items.events, items.longNotes)
        } else {
            for note in items.longNotes {
                _ = actions.eraseLongNote?(note)
            }
            for event in items.events {
                _ = actions.eraseNote?(event)
            }
        }
        applySelection(events: [], longNotes: [])
    }

    func selectAllChartNotes() {
        forEachSurface { $0.selectAllNotes() }
    }

    func scrollToMeasure(_ measure: Int) {
        chartSurface.scrollToMeasure(measure)
    }

    func loadWaveform(from url: URL) {
        let wav: BmhelperPcmWav?
        if let data = try? Data(contentsOf: url), let parsed = try? BmhelperWavIO.read(data) {
            wav = parsed
        } else if let data = try? IBMSAudioBridge.pcmWav(fromFile: url.path),
                  let parsed = try? BmhelperWavIO.read(data) {
            wav = parsed
        } else {
            setNotice("Could not load waveform.")
            return
        }
        guard let wav else { return }
        let interleaved: [Float]
        if wav.channels <= 1 {
            interleaved = wav.samples.flatMap { sample in
                let value = Float(sample) / 32768
                return [value, value]
            }
        } else {
            interleaved = wav.samples.map { Float($0) / 32768 }
        }
        let split = LegacyWaveform.deinterleaveStereo(interleaved)
        forEachSurface { $0.setWaveform(left: split.left, right: split.right, sampleRate: wav.sampleRate) }
        optionsSidebar.setWaveformFileName(url.path)
    }

    func clearWaveform() {
        forEachSurface { $0.clearWaveform() }
        optionsSidebar.setWaveformFileName("(None)")
    }

    private func applyWavList(_ transform: ([String], [Int]) -> WavListEdit) {
        guard actions.isBusy?() != true else { return }
        let selected = optionsSidebar.selectedWavSlots
        guard !selected.isEmpty else { return }
        let edit = transform(optionsSidebar.currentWavNames(), selected)
        if actions.applyWavEdit?(edit, optionsSidebar.wavSynchronizeLabels) == true {
            optionsSidebar.selectWavSlots(edit.selected)
        }
    }

    private func applyBmpList(_ transform: ([String], [Int]) -> WavListEdit) {
        guard actions.isBusy?() != true else { return }
        let selected = optionsSidebar.selectedBmpSlots
        guard !selected.isEmpty else { return }
        let edit = transform(optionsSidebar.currentBmpNames(), selected)
        if actions.applyBmpEdit?(edit, optionsSidebar.wavSynchronizeLabels) == true {
            optionsSidebar.selectBmpSlots(edit.selected)
        }
    }

    private func browseWavFiles() {
        guard actions.isBusy?() != true else { return }
        guard !optionsSidebar.selectedWavSlots.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = optionsSidebar.wavAllowsMultipleSelection
        var types: [UTType] = [.wav, .mp3]
        if let ogg = UTType(filenameExtension: "ogg") {
            types.append(ogg)
        }
        panel.allowedContentTypes = types
        let parent = window
        let present: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK else { return }
            let edit = LegacyWavList.assign(
                paths: panel.urls.map(\.path),
                selected: self.optionsSidebar.selectedWavSlots,
                names: self.optionsSidebar.currentWavNames()
            )
            if self.actions.applyWavEdit?(edit, false) == true {
                self.optionsSidebar.selectWavSlots(edit.selected)
            }
        }
        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: present)
        } else {
            present(panel.runModal())
        }
    }

    private func dropResourceFiles(_ paths: [String], extensions: [String], bmp: Bool) {
        guard actions.isBusy?() != true else { return }
        let kept = LegacyWavList.prepareDropped(paths: paths, extensions: extensions)
        guard !kept.isEmpty else { return }
        let selected = bmp ? optionsSidebar.selectedBmpSlots : optionsSidebar.selectedWavSlots
        guard !selected.isEmpty else { return }
        let names = bmp ? optionsSidebar.currentBmpNames() : optionsSidebar.currentWavNames()
        let edit = LegacyWavList.assign(paths: kept, selected: selected, names: names)
        if bmp {
            if actions.applyBmpEdit?(edit, false) == true {
                optionsSidebar.selectBmpSlots(edit.selected)
            }
        } else if actions.applyWavEdit?(edit, false) == true {
            optionsSidebar.selectWavSlots(edit.selected)
        }
    }

    private func browseBmpFiles() {
        guard actions.isBusy?() != true else { return }
        guard !optionsSidebar.selectedBmpSlots.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = optionsSidebar.wavAllowsMultipleSelection
        var types: [UTType] = [.bmp, .png, .jpeg, .gif, .mpeg4Movie]
        if let mpg = UTType(filenameExtension: "mpg") { types.append(mpg) }
        if let m1v = UTType(filenameExtension: "m1v") { types.append(m1v) }
        if let m2v = UTType(filenameExtension: "m2v") { types.append(m2v) }
        if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
        if let wmv = UTType(filenameExtension: "wmv") { types.append(wmv) }
        if let webm = UTType(filenameExtension: "webm") { types.append(webm) }
        panel.allowedContentTypes = types
        let parent = window
        let present: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK else { return }
            let edit = LegacyWavList.assign(
                paths: panel.urls.map(\.path),
                selected: self.optionsSidebar.selectedBmpSlots,
                names: self.optionsSidebar.currentBmpNames()
            )
            if self.actions.applyBmpEdit?(edit, false) == true {
                self.optionsSidebar.selectBmpSlots(edit.selected)
            }
        }
        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: present)
        } else {
            present(panel.runModal())
        }
    }

    func onPreviewNote(_ handler: @escaping (String) -> Void) {
        actions.previewNoteToken = handler
    }

    func applyEditorSettings(_ settings: EditorSettings) {
        forEachSurface { $0.applyEditorSettings(settings) }
    }

    func setNotice(_ text: String) {
        statusStrip.setNotice(text)
        timeStrip.setNotice(text)
    }

    /// 对照 `SequenceView::GetCurrentLocation`：视口底边再吸到细格。
    func currentBmsonLocation(resolution: Int, bars: [Int64]) -> Int {
        let time = chartSurface.chartLayout.beat(atY: chartSurface.viewport.maxY) * Double(max(resolution, 1))
        return BmsONEExternalViewer.currentLocation(
            time: time,
            bars: bars,
            resolution: resolution,
            fineGrid: bmsonFineGrid
        )
    }

    /// 对照 `GetVisibleRangeExtended`：当前焦点编辑区的可见脉冲，已按 4 像素边和 1.5 倍拉长。
    func visibleBmsonPulseRange(resolution: Int) -> (Int, Int) {
        let surface = chartSurface
        return BmsONEVisibleRange.pulses(
            viewport: surface.viewport,
            resolution: resolution,
            beatAtY: { surface.chartLayout.beat(atY: $0) }
        )
    }

    func selectedChartItems() -> (events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>) {
        chartSurface.selectedChartItems()
    }

    private func applySelectedObjectsVisibility() {
        let show = optionsPanelVisible && selectedObjectsWanted
        optionsSidebar.setBmsonDocksVisible(show)
    }

    func applySelection(events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>) {
        suppressSelectionSync = true
        forEachSurface { $0.applySelection(events: events, longNotes: longNotes) }
        suppressSelectionSync = false
        onChartSelectionChange?()
    }

    var timeSelection: TimeSelection { chartSurface.timeSelection }

    var timeStretchOrigin: TimeSelection? { chartSurface.timeStretchOrigin }

    var lastPointerBeat: Double { chartSurface.lastPointerBeat }

    func setPreviewPlayheadBeat(_ beat: Double?) {
        forEachSurface { $0.setPreviewPlayheadBeat(beat) }
    }

    var chartEndBeat: Double {
        chartSurface.chartLayout.snapshot.measures.map { $0.start + $0.length }.max() ?? 4
    }

    func applyTimeSelection(_ selection: TimeSelection) {
        forEachSurface { $0.applyTimeSelection(selection) }
        timeStrip.setSelection(selection)
    }

    /// 对照 `FSSS_Click` / `FSSL_Click` / `FSSH_Click`：只改选择，不改谱。
    private func editTimeSelectionField(_ field: TimeSelectionField) {
        let selection = chartSurface.timeSelection
        let maxV = LegacyTimeSelection.maxVPosition(chartEndBeat: chartEndBeat)
        let range = LegacyTimeSelection.bounds(field, selection: selection, maxVPosition: maxV)
        let alert = NSAlert()
        alert.messageText = LegacyTimeSelection.fieldTitle
        alert.informativeText = LegacyTimeSelection.fieldPrompt(min: range.min, max: range.max)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = LegacyTimeSelection.formatField(LegacyTimeSelection.fieldValue(field, of: selection))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let value = LegacyTimeSelection.parseFieldInput(input.stringValue, min: range.min, max: range.max) else {
            return
        }
        applyTimeSelection(
            LegacyTimeSelection.applyField(field, value: value, to: selection, maxVPosition: maxV)
        )
    }

    func setThemeMenu(_ menu: NSMenu) {
        toolbar.setThemeMenu(menu)
    }

    func setLanguageMenu(_ menu: NSMenu) {
        toolbar.setLanguageMenu(menu)
    }

    func setLanguageActions(
        reset: @escaping () -> Void,
        refresh: @escaping () -> Void,
        load: @escaping (String) -> Void
    ) {
        actions.resetLanguagePreference = reset
        actions.refreshLanguageMenu = refresh
        actions.loadLanguageFile = load
    }

    /// 点语言包后换 BMS 底栏 Length / LongNote / Hidden / Error。不改 BMSON 四格。
    func applyLocaleStatusLabels(length: String, longNote: String, hidden: String, error: String) {
        statusLabels = LegacyStatus.Labels(
            length: length,
            longNote: longNote,
            hidden: hidden,
            error: error
        )
        refreshHoverStatus()
    }

    func setChartSide(_ side: ChartSide) {
        selectedSide = side
        forEachSurface { $0.setSide(side) }
    }

    func commitActiveMetadataEditor() -> Bool {
        forEachSurface { $0.cancelDrag() }
        let pending = pendingMetadata
        for key in DocumentSession.editableKeys {
            guard let value = pending[key] else { continue }
            guard actions.commitMetadata(key: key, value: value) else {
                actions.refresh?()
                return false
            }
            pendingMetadata.removeValue(forKey: key)
        }
        actions.refresh?()
        window?.makeFirstResponder(nil)
        return true
    }

    func discardPendingMetadata() {
        pendingMetadata.removeAll()
    }

    func applyChartTheme(_ theme: ChartTheme) {
        chartTheme = theme
        optionsSidebar.setWaveformPen(from: theme.visual.bgmWaveform)
        broadcastChartUpdate(theme: theme)
    }

    func setChartTool(_ tool: ChartTool) {
        switch tool {
        case .select:
            forEachSurface { $0.tool = .select }
            toolbar.setChecked("TBSelect", true)
            toolbar.setChecked("TBWrite", false)
            toolbar.setChecked("TBTimeSelect", false)
            setTimeSelectionVisible(false)
        case .write:
            forEachSurface { $0.tool = .write }
            toolbar.setChecked("TBSelect", false)
            toolbar.setChecked("TBWrite", true)
            toolbar.setChecked("TBTimeSelect", false)
            setTimeSelectionVisible(false)
        case .timeSelect:
            forEachSurface { surface in
                surface.tool = .timeSelect
                surface.applySelection(events: [], longNotes: [])
                surface.applyTimeSelection(chartSurface.timeSelection)
            }
            toolbar.setChecked("TBSelect", false)
            toolbar.setChecked("TBWrite", false)
            toolbar.setChecked("TBTimeSelect", true)
            timeStrip.setSelection(chartSurface.timeSelection)
            setTimeSelectionVisible(true)
        case .longNote:
            forEachSurface { $0.tool = .longNote }
            toolbar.setChecked("TBSelect", false)
            toolbar.setChecked("TBWrite", true)
            toolbar.setChecked("TBTimeSelect", false)
            setTimeSelectionVisible(false)
        }
        refreshHoverStatus()
    }

    func setGridVisibility(
        showGrid: Bool? = nil,
        showSubGrid: Bool? = nil,
        showMeasureBar: Bool? = nil,
        showBackground: Bool? = nil,
        showMeasureNumber: Bool? = nil,
        showVerticalLine: Bool? = nil,
        showColumnCaption: Bool? = nil
    ) {
        if let showGrid { self.showGrid = showGrid }
        if let showSubGrid { self.showSubGrid = showSubGrid }
        if let showMeasureBar { self.showMeasureBar = showMeasureBar }
        if let showBackground { self.showBackground = showBackground }
        if let showMeasureNumber { self.showMeasureNumber = showMeasureNumber }
        if let showVerticalLine { self.showVerticalLine = showVerticalLine }
        if let showColumnCaption { self.showColumnCaption = showColumnCaption }
        forEachSurface {
            $0.setGridVisibility(
                showGrid: showGrid,
                showSubGrid: showSubGrid,
                showMeasureBar: showMeasureBar,
                showBackground: showBackground,
                showMeasureNumber: showMeasureNumber,
                showVerticalLine: showVerticalLine,
                showColumnCaption: showColumnCaption
            )
        }
    }

    func setColumnVisibility(
        scroll: Bool? = nil,
        bpm: Bool? = nil,
        stop: Bool? = nil,
        bga: Bool? = nil
    ) {
        if let scroll { showsScrollColumn = scroll }
        if let bpm { showsBPMColumn = bpm }
        if let stop { showsStopColumn = stop }
        if let bga { showsBGAColumns = bga }
        actions.refresh?()
    }

    private func setTimeSelectionVisible(_ visible: Bool) {
        applyBottomStripVisibility(timeSelection: visible)
    }

    private func applyBottomStripVisibility(timeSelection: Bool? = nil) {
        let timeOn = timeSelection ?? (currentTool == .timeSelect)
        let showSlot = statusBarVisible
        statusHeightConstraint?.constant = showSlot ? MainWindowChrome.statusHeight : 0
        timeStrip.isHidden = !(showSlot && timeOn)
        statusStrip.isHidden = !showSlot || timeOn
    }

    func update(
        document: DocumentSession?,
        chartSource: MainEditorChartSource? = nil,
        resetChartPosition: Bool = false,
        extraCanUndo: Bool = false,
        extraCanRedo: Bool = false
    ) {
        let canEdit = document?.canEditMetadata == true
        for key in DocumentSession.editableKeys {
            if let pending = pendingMetadata[key] {
                optionsSidebar.setMetadataValue(key, text: pending, placeholder: nil, enabled: canEdit)
            } else if let document {
                if let value = try? document.metadataValue(for: key) {
                    optionsSidebar.setMetadataValue(key, text: value, placeholder: nil, enabled: canEdit)
                } else {
                    optionsSidebar.setMetadataValue(key, text: "", placeholder: "Unavailable", enabled: false)
                }
            } else if let chartSource {
                let enabled = chartSource.editableHeaderKeys.contains(key)
                optionsSidebar.setMetadataValue(
                    key,
                    text: chartSource.headerFields[key] ?? "",
                    placeholder: nil,
                    enabled: enabled
                )
            } else {
                optionsSidebar.setMetadataValue(key, text: "", placeholder: nil, enabled: false)
            }
        }

        let timing = document?.timingSnapshot
        optionsSidebar.setBPM(
            chartSource.map { String($0.headerBPM) } ?? timing?.initialBPMDecimal ?? "120",
            enabled: (document != nil && timing?.canEditInitialBPM == true)
                || (chartSource?.canEditHeaderBPM == true)
        )

        let hasChart = document != nil || chartSource != nil
        toolbar.setEnabled("TBSave", document != nil || chartSource?.canSave == true)
        toolbar.setEnabled("TBUndo", extraCanUndo || (chartSource?.canUndo ?? (document?.canUndo == true)))
        toolbar.setEnabled("TBRedo", extraCanRedo || (chartSource?.canRedo ?? (document?.canRedo == true)))
        toolbar.setEnabled(
            "TBWrite",
            chartSource?.canWrite ?? (document != nil && document?.chartSnapshot.editable == true)
        )
        toolbar.setEnabled("TBSelect", hasChart)
        toolbar.setEnabled("TBTimeSelect", document != nil)
        let wavTable: [String: String]
        let bmpTable: [String: String]
        if let chartSource {
            soundChannelNames = chartSource.soundChannelNames
            shownSoundChannels = chartSource.shownSoundChannels
            wavTable = chartSource.wavTable
            bmpTable = chartSource.bmpTable
            optionsSidebar.setWavTable(wavTable)
            optionsSidebar.setBmpTable(bmpTable)
            optionsSidebar.setBeatFromChart(chartSource.chart.measures)
            optionsSidebar.setExpansionText("", enabled: false)
        } else if let data = try? document?.currentBytes() {
            wavTable = LegacyPreviewAudio.parseWavTable(from: data)
            bmpTable = LegacyWavList.parseTable(
                from: LegacyPreviewAudio.decodeBMSText(data), directive: "BMP"
            )
            optionsSidebar.setWavTable(wavTable)
            optionsSidebar.setBmpTable(bmpTable)
            optionsSidebar.setBeatFromChart(document?.chartSnapshot.measures ?? [])
            optionsSidebar.setExpansionText((try? document?.expansionText()) ?? "", enabled: document != nil)
        } else {
            wavTable = [:]
            bmpTable = [:]
            optionsSidebar.setWavTable([:])
            optionsSidebar.setBmpTable([:])
            optionsSidebar.setBeatFromChart([])
            optionsSidebar.setExpansionText("", enabled: false)
        }
        let headerBPM = chartSource?.headerBPM
            ?? Double(timing?.initialBPMDecimal ?? "120")
            ?? 120
        let bpmEvents = (timing?.events ?? []).compactMap { event -> (Double, Double)? in
            guard event.kind == .bpm else { return nil }
            let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
            return (TimeSelection.vPosition(beat: beat), Double(event.valueDecimal) ?? 120)
        }
        let stopEvents = (timing?.events ?? []).compactMap { event -> (Double, Double)? in
            guard event.kind == .stop else { return nil }
            let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
            return (TimeSelection.vPosition(beat: beat), Double(event.valueDecimal) ?? 0)
        }
        forEachSurface { surface in
            surface.wavTable = wavTable
            surface.bmpTable = bmpTable
            surface.headerBPM = headerBPM
            surface.bpmEvents = bpmEvents
            surface.stopEvents = stopEvents
            surface.writesBmsonContinue = chartSource != nil
            surface.appliesBmsonNoteDarken = chartSource != nil
            surface.appliesBmsonSnap = chartSource != nil
            surface.darkensInactiveBmsonChannels = darkensInactiveBmsonNotes
            surface.bmsonCurrentChannelIndex = selectedWavIndex >= 0 ? selectedWavIndex : 0
            surface.bmsonFineGrid = bmsonFineGrid
        }
        let playerHeader = (try? document?.metadataValue(for: "PLAYER")) ?? ""
        let showsTwoPlayer: Bool
        let hiddenPlay: Set<String>
        let playOrders: (one: [(String, Int)]?, two: [(String, Int)]?)
        let playSkinColors: [String: ChartPlaySkinColor]
        if chartSource != nil, let mode = bmsonViewMode {
            if let count = BmsONEPlainLanes.load(kind: mode.kind) {
                hiddenPlay = BmsONEPlainLanes.hiddenPlayChannels(count: count)
                showsTwoPlayer = false
                playOrders = (
                    ChartLanes.pairs(for: BmsONEPlainLanes.visibleChannels(count: count)),
                    nil
                )
                playSkinColors = [:]
            } else if let order = BmsONELaneOrder.load(kind: mode.kind) {
                hiddenPlay = mode.hiddenPlayChannels
                showsTwoPlayer = false
                playOrders = (
                    ChartLanes.pairs(for: BmsONELaneOrder.channels(kind: mode.kind, order: order)),
                    nil
                )
                playSkinColors = [:]
            } else {
                hiddenPlay = mode.hiddenPlayChannels
                showsTwoPlayer = mode.showsTwoPlayer
                playOrders = bmsonPlayOrders(mode: mode)
                playSkinColors = bmsonPlaySkinColors(mode: mode)
            }
        } else {
            showsTwoPlayer = document == nil || ChartPlayerColumns.showsTwoPlayer(playerHeader)
            hiddenPlay = []
            playOrders = (nil, nil)
            playSkinColors = [:]
        }
        if chartSource == nil {
            soundChannelNames = []
            shownSoundChannels = nil
            pushBmsonMaster(applies: false, waveform: nil)
            pushBmsonLaneWaveform(nil)
            pushBmsonFooter(visible: false)
        }
        broadcastChartUpdate(
            snapshot: chartSource?.chart ?? document?.chartSnapshot ?? .empty,
            longNotes: chartSource?.longNotes ?? document?.longNoteSnapshot ?? .empty,
            showsTwoPlayer: showsTwoPlayer,
            hiddenPlayChannels: hiddenPlay,
            onePlayerOrder: playOrders.one,
            twoPlayerOrder: playOrders.two,
            playSkinColors: playSkinColors
        )
        if chartSource != nil {
            refreshBmsonFooter(visible: true)
        }
        syncSelection(from: chartSurface)
        if resetChartPosition {
            suppressScrollFollow = true
            forEachSurface { $0.resetToMeasureZero() }
            suppressScrollFollow = false
        }
        let notes = LegacyChartQuery.collect(
            chart: chartSource?.chart ?? document?.chartSnapshot ?? .empty,
            longNotes: chartSource?.longNotes ?? document?.longNoteSnapshot ?? .empty,
            timing: document?.timingSnapshot ?? .unavailable,
            selectedEvents: chartSurface.selectedChartItems().events,
            selectedLongNotes: chartSurface.selectedChartItems().longNotes,
            bmsonLabels: chartSource != nil
        )
        toolbar.setStatisticsTitle("\(LegacyChartQuery.playableNoteCount(from: notes, ntInput: chartSurface.ntInputEnabled))")
        refreshErrorMarks(
            notes: notes,
            headerBPM: chartSurface.headerBPM,
            lnobjToken: chartSource?.longNotes.lnobjToken ?? document?.longNoteSnapshot.lnobjToken ?? ""
        )
        statusStrip.setField("FSW", text: optionsSidebar.selectedToken)
        if let message = document?.metadataEditingMessage {
            statusStrip.setNotice(message)
        } else if let document {
            idleErrorText = idleErrorField(for: document)
            refreshHoverStatus()
        } else if let chartSource {
            idleStatusLength = chartSource.statusLength
            statusStrip.setField("FST", text: chartSource.statusLength)
            statusStrip.setField("FSC", text: chartSource.titleBPM)
            idleErrorText = "Error"
            refreshHoverStatus()
        } else {
            statusStrip.restoreDefaults()
            statusStrip.setField("FSW", text: optionsSidebar.selectedToken)
            idleErrorText = "Error"
            forEachSurface { $0.errorAnchors = [] }
        }
    }

    private func wireChrome() {
        toolbar.onCommand = { [weak self] name in
            self?.handleToolbar(name)
        }
        optionsSidebar.onMetadataCommit = { [weak self] key, value in
            guard let self, self.actions.isBusy?() != true else { return false }
            if self.actions.commitMetadata(key: key, value: value) {
                self.pendingMetadata.removeValue(forKey: key)
                self.actions.refresh?()
                return true
            }
            return false
        }
        optionsSidebar.onMetadataDraft = { [weak self] key, value in
            self?.pendingMetadata[key] = value
        }
        optionsSidebar.onBPMCommit = { [weak self] value in
            self?.actions.setInitialBPM?(value) ?? false
        }
        optionsSidebar.onDivisionChange = { [weak self] value in
            guard let self else { return }
            self.setBmsonFineGrid(BmsONEGridSize(denominator: UInt(max(1, value))))
            self.forEachSurface { $0.setDivision(value) }
        }
        optionsSidebar.onSubDivisionChange = { [weak self] value in
            self?.forEachSurface { $0.setSubDivision(value) }
        }
        optionsSidebar.onSnapChange = { [weak self] enabled in
            BmsONESnap.save(enabled)
            self?.forEachSurface { $0.snapEnabled = enabled }
        }
        optionsSidebar.onVerticalMoveChange = { [weak self] enabled in
            self?.forEachSurface { $0.disableVerticalMove = enabled }
        }
        optionsSidebar.onScrollLockChange = { [weak self] index, enabled in
            guard let self, enabled else { return }
            self.captureScrollDiffs(locking: index)
        }
        optionsSidebar.onTokenChange = { [weak self] token in
            self?.statusStrip.setField("FSW", text: token)
            self?.refreshHoverStatus()
            self?.pushBmsonNoteDarken()
            self?.onBmsonChannelInfoNeeded?()
        }
        optionsSidebar.onZoomChange = { [weak self] zoom in
            guard let self else { return }
            if let resolution = self.bmsonZoomResolution, !self.applyingBmsonZoom {
                let zoomY = BmsONEZoom.clampZoomY(
                    BmsONEZoom.zoomY(pixelsPerQuarterBeat: zoom, resolution: resolution),
                    resolution: resolution
                )
                let height = BmsONEZoom.gridHeight(zoomY: zoomY, resolution: resolution)
                let clampedZoom = MainWindowChrome.pixelsPerQuarterBeat(gridHeight: CGFloat(height))
                if abs(clampedZoom - zoom) > 1e-6 {
                    self.applyBmsonZoomY(zoomY)
                    return
                }
                self.bmsonZoomY = zoomY
                BmsONEZoom.save(zoomY)
            }
            self.selectedZoom = zoom
            self.forEachSurface { $0.setZoom(zoom) }
        }
        optionsSidebar.onColumnScaleChange = { [weak self] scale in
            self?.selectedColumnScale = scale
            self?.forEachSurface { $0.setColumnScale(scale) }
        }
        optionsSidebar.onBGMColumnChange = { [weak self] count in
            guard let self else { return }
            self.selectedBGMColumnCount = count
            self.actions.refresh?()
        }
        optionsSidebar.onBeatApply = { [weak self] measures, decimal, mode in
            self?.actions.applyBeat?(measures, decimal, mode) ?? false
        }
        optionsSidebar.onExpansionCommit = { [weak self] text in
            self?.actions.applyExpansion?(text) ?? false
        }
        optionsSidebar.onNotice = { [weak self] message in
            self?.setNotice(message)
        }
        optionsSidebar.onWaveformLoad = { [weak self] url in
            self?.loadWaveform(from: url)
        }
        optionsSidebar.onWaveformClear = { [weak self] in
            self?.clearWaveform()
        }
        optionsSidebar.onWaveformLockChange = { [weak self] locked in
            self?.forEachSurface { $0.setWaveformLocked(locked) }
        }
        optionsSidebar.onWaveformPositionChange = { [weak self] position in
            self?.forEachSurface { $0.setWaveformPosition(position) }
        }
        optionsSidebar.onWaveformDisplayChange = { [weak self] left, width, precision in
            self?.forEachSurface { $0.setWaveformDisplay(left: left, width: width, precision: precision) }
        }
        optionsSidebar.onWaveformTransparencyChange = { [weak self] alpha in
            guard let self else { return }
            self.actions.applyWaveformColor?(
                LegacyWaveform.applyTransparency(self.chartTheme.visual.bgmWaveform, alpha: alpha)
            )
        }
        optionsSidebar.onWaveformSaturationChange = { [weak self] saturation in
            guard let self else { return }
            self.actions.applyWaveformColor?(
                LegacyWaveform.applySaturation(self.chartTheme.visual.bgmWaveform, saturation: saturation)
            )
        }
        optionsSidebar.onWavMoveUp = { [weak self] in
            self?.applyWavList { LegacyWavList.moveUp(names: $0, selected: $1) }
        }
        optionsSidebar.onWavMoveDown = { [weak self] in
            self?.applyWavList { LegacyWavList.moveDown(names: $0, selected: $1) }
        }
        optionsSidebar.onWavBrowse = { [weak self] in
            self?.browseWavFiles()
        }
        optionsSidebar.onWavRemove = { [weak self] in
            self?.applyWavList { LegacyWavList.remove(names: $0, selected: $1) }
        }
        optionsSidebar.onBmpMoveUp = { [weak self] in
            self?.applyBmpList { LegacyWavList.moveUp(names: $0, selected: $1) }
        }
        optionsSidebar.onBmpMoveDown = { [weak self] in
            self?.applyBmpList { LegacyWavList.moveDown(names: $0, selected: $1) }
        }
        optionsSidebar.onBmpBrowse = { [weak self] in
            self?.browseBmpFiles()
        }
        optionsSidebar.onBmpRemove = { [weak self] in
            self?.applyBmpList { LegacyWavList.remove(names: $0, selected: $1) }
        }
        optionsSidebar.onWavDrop = { [weak self] paths in
            self?.dropResourceFiles(paths, extensions: LegacyWavList.audioExtensions, bmp: false)
        }
        optionsSidebar.onBmpDrop = { [weak self] paths in
            self?.dropResourceFiles(paths, extensions: LegacyWavList.imageExtensions, bmp: true)
        }
        optionsSidebar.onResourceDragPreview = { [weak self] paths in
            self?.forEachSurface { $0.dragPreviewPaths = paths }
        }
        setSnapEnabled(BmsONESnap.load())
        forEachSurface { surface in
            surface.ntInputEnabled = true
            surface.snapEnabled = optionsSidebar.snapEnabled
            surface.disableVerticalMove = optionsSidebar.disableVerticalMove
        }
        timeStrip.onReverse = { [weak self] in
            guard let self else { return }
            let reversed = LegacyTimeSelection.reverse(self.chartSurface.timeSelection)
            self.forEachSurface { $0.applyTimeSelection(reversed) }
        }
        timeStrip.onEditField = { [weak self] field in
            self?.editTimeSelectionField(field)
        }
        timeStrip.onExpand = { [weak self] numerator, denominator in
            guard let self else { return }
            if numerator <= 0 || denominator <= 0 {
                self.setNotice(LegacyTimeSelectionOps.factorMustBePositive)
                return
            }
            self.actions.performTimeSelection?(.expand(ratio: numerator / denominator))
        }
        timeStrip.onRelocate = { [weak self] value in
            guard let self else { return }
            if self.chartSurface.timeSelection.length == 0 { return }
            self.actions.performTimeSelection?(.relocate(value: value * 10_000))
        }
        timeStrip.onConvertStop = { [weak self] in
            self?.actions.performTimeSelection?(.convertStop)
        }
        timeStrip.setSelection(chartSurface.timeSelection)
        timeStrip.isHidden = true
    }

    private func refreshErrorMarks(notes: [QueryNote], headerBPM: Double, lnobjToken: String) {
        let headerValue = Int((headerBPM * 10_000).rounded())
        let lnObj = lnobjToken.isEmpty ? 0 : BMS36Token.decode(lnobjToken)
        var body = [
            ErrorCheckNote(vPosition: -1, columnIndex: EditorColumn.bpm, value: headerValue, length: 0, hidden: false)
        ]
        body.append(contentsOf: notes.map(errorNote(from:)))
        let marked = LegacyErrorCheck.markNT(body, lnObj: lnObj)
        let anchors = zip(notes, marked.dropFirst()).compactMap { note, item in
            item.hasError ? errorAnchor(from: note) : nil
        }
        forEachSurface { $0.errorAnchors = anchors }
    }

    private func errorNote(from note: QueryNote) -> ErrorCheckNote {
        let value: Int
        if let numeric = note.numericValue {
            value = Int((numeric * 10_000).rounded())
        } else {
            value = BMS36Token.decode(note.labelToken) * 10_000
        }
        switch note.source {
        case .event(let event):
            return ErrorCheckNote(
                vPosition: TimeSelection.vPosition(beat: event.beat),
                columnIndex: note.columnIndex,
                value: value,
                length: 0,
                hidden: note.isHidden
            )
        case .longNote(let longNote):
            let start = TimeSelection.vPosition(beat: longNote.start.beat)
            return ErrorCheckNote(
                vPosition: start,
                columnIndex: note.columnIndex,
                value: value,
                length: TimeSelection.vPosition(beat: longNote.end.beat) - start,
                hidden: note.isHidden
            )
        case .timing(let event):
            let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
            return ErrorCheckNote(
                vPosition: TimeSelection.vPosition(beat: beat),
                columnIndex: note.columnIndex,
                value: value,
                length: 0,
                hidden: false
            )
        }
    }

    private func errorAnchor(from note: QueryNote) -> ErrorAnchor {
        switch note.source {
        case .event(let event):
            return ErrorAnchor(channel: event.channel, beat: event.beat)
        case .longNote(let longNote):
            return ErrorAnchor(channel: longNote.channel, beat: longNote.start.beat)
        case .timing(let event):
            let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
            return ErrorAnchor(channel: event.channel, beat: beat)
        }
    }

    private func idleErrorField(for document: DocumentSession) -> String {
        let errors = document.chartSnapshot.diagnostics.count + document.timingSnapshot.diagnostics.count
        return errors == 0 ? "Error" : "\(errors)"
    }

    private func refreshHoverStatus() {
        if currentTool == .timeSelect {
            return
        }
        if bmsonStatus != nil {
            if toolbar.isChecked("TBSelect"), chartSurface.hasHoverNote {
                statusStrip.setField("FSE", text: chartSurface.hoverHasError ? LegacyErrorCheck.hoverErrorText : "")
            } else {
                statusStrip.setField("FSE", text: idleErrorText)
            }
            applyBmsonHoverStatus()
            return
        }
        applyBmsHoverStatus()
    }

    private func applyBmsHoverStatus() {
        let surface = chartSurface
        let writeTool = surface.tool == .write || surface.tool == .longNote
        if writeTool, !surface.statusHasColumn {
            return
        }
        let divide = Double(optionsSidebar.selectedDivision)
        let header = [LegacyStatus.headerBPMNote(surface.headerBPM)]
        let chartBPM = surface.bpmEvents
            .filter { $0.vPosition > 0 }
            .map { LegacyStatus.TimingNote(vPosition: $0.vPosition, value: $0.value * 10_000) }
        let stops = surface.stopEvents.map {
            LegacyStatus.TimingNote(vPosition: $0.vPosition, value: $0.value * 10_000)
        }
        let flags = NSEvent.modifierFlags
        let fields: LegacyStatus.Fields
        if writeTool {
            let place = statusMeasure(for: surface.statusMouseVPosition)
            fields = LegacyStatus.writeFields(
                mouseVPosition: surface.statusMouseVPosition,
                vposMod: place.mod,
                measureLength: place.length,
                measureIndex: place.index,
                columnTitle: surface.statusColumnTitle,
                slot: max(0, optionsSidebar.selectedWavIndex),
                tempLength: surface.statusWriteLength,
                ntInput: surface.ntInputEnabled,
                shift: flags.contains(.shift),
                control: flags.contains(.control),
                divide: divide,
                bpmNotes: header + chartBPM,
                stopNotes: stops,
                labels: statusLabels
            )
        } else {
            let hover: LegacyStatus.HoverNote?
            if surface.hasHoverNote {
                hover = LegacyStatus.HoverNote(
                    vPosition: surface.statusHoverVPosition,
                    columnTitle: surface.statusHoverColumnTitle,
                    value: surface.statusHoverValue,
                    length: surface.statusHoverLength,
                    hidden: surface.statusHoverHidden,
                    hasError: surface.hoverHasError,
                    numeric: surface.statusHoverNumeric,
                    longNote: surface.statusHoverLongNote
                )
            } else {
                hover = nil
            }
            let place = statusMeasure(for: hover?.vPosition ?? surface.statusMouseVPosition)
            fields = LegacyStatus.selectFields(
                mouseVPosition: surface.statusMouseVPosition,
                vposMod: place.mod,
                measureLength: place.length,
                measureIndex: place.index,
                columnTitle: surface.statusColumnTitle,
                divide: divide,
                hover: hover,
                ntInput: surface.ntInputEnabled,
                bpmNotes: header + chartBPM,
                stopNotes: stops,
                labels: statusLabels
            )
        }
        applyLegacyStatusFields(fields, writeFSE: !writeTool)
    }

    private func statusMeasure(for vPosition: Double) -> (index: Int, mod: Double, length: Double) {
        let bottoms = LegacyTimeSelection.measureBottoms(
            measures: chartSurface.chartLayout.snapshot.measures.map { (start: $0.start, length: $0.length) }
        )
        let index = LegacyTimeSelection.measureAtDisplacement(vPosition, bottoms: bottoms)
        let bottom = (0..<bottoms.count).contains(index) ? bottoms[index] : Double(index) * 192
        let next = index + 1
        let length = (0..<bottoms.count).contains(next) ? bottoms[next] - bottom : 192
        return (index, vPosition - bottom, max(length, 0))
    }

    private func applyLegacyStatusFields(_ fields: LegacyStatus.Fields, writeFSE: Bool) {
        statusStrip.setField("FSC", text: fields.fsc)
        statusStrip.setField("FSW", text: fields.fsw)
        statusStrip.setField("FSM", text: fields.fsm)
        statusStrip.setField("FSP1", text: fields.fsp1)
        statusStrip.setField("FSP2", text: fields.fsp2)
        statusStrip.setField("FSP3", text: fields.fsp3)
        statusStrip.setField("FSP4", text: fields.fsp4)
        statusStrip.setField("TimeStatusLabel", text: fields.time)
        statusStrip.setField("FST", text: fields.fst)
        statusStrip.setField("FSH", text: fields.fsh)
        if writeFSE {
            statusStrip.setField("FSE", text: fields.fse)
        }
    }

    private func applyBmsonHoverStatus() {
        guard let context = bmsonStatus else { return }
        guard let cursor = chartSurface.bmsonCursor else {
            statusStrip.setField("FSP4", text: "")
            statusStrip.setField("FSP2", text: "")
            statusStrip.setField("TimeStatusLabel", text: "")
            statusStrip.setField("FSC", text: "")
            statusStrip.setField("FST", text: idleStatusLength)
            return
        }
        if let begin = cursor.rangeBegin, let end = cursor.rangeEnd {
            statusStrip.setField(
                "FSP4",
                text: BmsONEStatus.absoluteLocationRange(begin: Int(begin), end: Int(end))
            )
            statusStrip.setField(
                "FSP2",
                text: BmsONEStatus.compositeLocationRange(
                    begin: Int(begin),
                    end: Int(end),
                    bars: context.bars,
                    resolution: context.resolution,
                    coarseGrid: context.coarseGrid
                )
            )
            statusStrip.setField(
                "TimeStatusLabel",
                text: BmsONEStatus.realTimeRange(
                    begin: Int(begin),
                    end: Int(end),
                    initBpm: context.initBpm,
                    resolution: context.resolution,
                    bpmNotes: context.bpmNotes
                )
            )
            statusStrip.setField("FSC", text: "")
            statusStrip.setField("FST", text: idleStatusLength)
            return
        }
        let pulse = Int(cursor.pulse)
        statusStrip.setField("FSP4", text: BmsONEStatus.absoluteLocation(pulse))
        statusStrip.setField(
            "FSP2",
            text: BmsONEStatus.compositeLocation(
                pulse: pulse,
                bars: context.bars,
                resolution: context.resolution,
                coarseGrid: context.coarseGrid
            )
        )
        statusStrip.setField(
            "TimeStatusLabel",
            text: BmsONEStatus.realTime(
                BmsONEStatus.absoluteSeconds(
                    pulse: pulse,
                    initBpm: context.initBpm,
                    resolution: context.resolution,
                    bpmNotes: context.bpmNotes
                )
            )
        )
        if let channel = cursor.channel, let lane = BmsONEStatus.laneX(channel: channel, mode: context.viewMode) {
            statusStrip.setField("FSC", text: BmsONEStatus.laneName(lane, mode: context.viewMode))
        } else {
            statusStrip.setField("FSC", text: "")
        }
        let hint = BmsONEStatus.objectHint(
            writeMode: cursor.writeMode,
            channel: cursor.channel,
            pulse: cursor.pulse,
            hitLength: cursor.hitLength,
            inMeasureArea: cursor.inMeasureArea,
            viewMode: context.viewMode,
            notes: bmsonNoteRefs(context: context),
            explicitBars: Set(context.explicitBars),
            allBars: Set(context.bars),
            initBpm: context.initBpm,
            bpmNotes: context.bpmNotes
        )
        statusStrip.setField("FST", text: hint.isEmpty ? idleStatusLength : hint)
    }

    /// 共用谱面上的音换成 BMSON 的 `x` / `y` / `l`，给叠层和盖住判定用。
    private func bmsonNoteRefs(context: BmsONEStatusContext) -> [(x: Int64, y: Int64, l: Int64)] {
        let resolution = context.resolution
        let mode = context.viewMode
        var notes: [(x: Int64, y: Int64, l: Int64)] = []
        for event in chartSurface.chartEvents {
            guard let lane = BmsONEStatus.laneX(channel: event.channel, mode: mode) else { continue }
            notes.append(
                (
                    x: lane,
                    y: BmsonChartMapping.pulse(beat: event.beat, resolution: resolution),
                    l: 0
                )
            )
        }
        for note in chartSurface.chartLongNotes {
            guard let lane = BmsONEStatus.laneX(channel: note.channel, mode: mode) else { continue }
            let start = BmsonChartMapping.pulse(beat: note.start.beat, resolution: resolution)
            let end = BmsonChartMapping.pulse(beat: note.end.beat, resolution: resolution)
            notes.append((x: lane, y: start, l: max(0, end - start)))
        }
        return notes
    }

    private func restoreIbmsStatusLocationFields() {
        for name in ["FSP2", "FSP4", "TimeStatusLabel", "FST"] {
            if let field = MainWindowChrome.statusFields.first(where: { $0.name == name }) {
                statusStrip.setField(name, text: field.text)
            }
        }
    }

    private func handleToolbar(_ name: String) {
        switch name {
        case "TBNew": actions.newDocument(nil)
        case "TBOpen": actions.openDocument(nil)
        case "TBOpenR0": actions.openRecent?(0)
        case "TBOpenR1": actions.openRecent?(1)
        case "TBOpenR2": actions.openRecent?(2)
        case "TBOpenR3": actions.openRecent?(3)
        case "TBOpenR4": actions.openRecent?(4)
        case "TBSave": actions.saveDocument(nil)
        case "TBSaveAs": actions.saveDocumentAs?()
        case "TBUndo": actions.undo(nil)
        case "TBRedo": actions.redo(nil)
        case "TBSelect":
            setChartTool(.select)
        case "TBWrite":
            setChartTool(.write)
        case "TBTimeSelect":
            setChartTool(.timeSelect)
        case "TBNTInput":
            let becomeNT = !toolbar.isChecked("TBNTInput")
            if let handler = actions.toggleNTInput {
                handler(becomeNT)
            } else {
                setNTInputEnabled(becomeNT)
            }
        case "TBErrorCheck":
            setErrorCheckEnabled(!toolbar.isChecked("TBErrorCheck"))
        case "TBPreviewOnClick":
            setPreviewOnClickEnabled(!toolbar.isChecked(name))
        case "TBShowFileName":
            setShowFileNameEnabled(!toolbar.isChecked("TBShowFileName"))
        case "TBWavIncrease":
            toolbar.setChecked(name, !toolbar.isChecked(name))
        case "TBPlayB":
            actions.playFromBeginning?()
        case "TBPlay":
            actions.playFromHere?()
        case "TBStop":
            actions.stopPreview?()
        case "TBFind":
            actions.showFind?()
        case "TBStatistics":
            actions.showStatistics?()
        case "TBVOptions":
            actions.showVisualOptions?()
        case "TBGOptions":
            actions.showGeneralOptions?()
        case "TBPOptions":
            actions.showPlayerOptions?()
        case "TBImportSM":
            actions.importSM?()
        case "TBImportIBMSC":
            actions.importIBMSC?()
        case "TBExport":
            actions.exportIBMSC?()
        case "TBMyO2":
            actions.showMyO2?()
        case "TBLangDef":
            actions.resetLanguagePreference?()
        case "TBLangRefresh":
            actions.refreshLanguageMenu?()
        case "TBCut":
            cutChartNotes()
        case "TBCopy":
            copyChartNotes()
        case "TBPaste":
            pasteChartNotes()
        case "POBLong":
            if !ChartConvert.longNoteMenuEnabled(ntInput: chartSurface.ntInputEnabled) {
                return
            }
            convertSelectedShortNotesToLong()
        case "POBLongShort":
            if !ChartConvert.longNoteMenuEnabled(ntInput: chartSurface.ntInputEnabled) {
                return
            }
            convertSelectedLongNotesToShort()
            convertSelectedShortNotesToLong()
        case "POBShort":
            convertSelectedLongNotesToShort()
        case "POBHidden":
            convertSelectedNotes(.hide)
        case "POBVisible":
            convertSelectedNotes(.show)
        case "POBHiddenVisible":
            convertSelectedNotes(.toggle)
        case "POBMirror":
            actions.mirrorSelected?()
        case "POBModify":
            actions.modifySelected?()
        default:
            if let path = LegacyLocale.path(fromFileCommand: name) {
                actions.loadLanguageFile?(path)
                return
            }
            statusStrip.setNotice(toolbarTooltip(name))
        }
    }

    private func autoincreaseWavIfNeeded(channel: String) {
        guard toolbar.isChecked("TBWavIncrease"), LegacyWavList.usesWavLabel(channel) else { return }
        optionsSidebar.stepWavSelection(1)
    }

    private func autodecreaseWavIfNeeded(token: String) {
        guard LegacyWavList.shouldDecreaseAfterErase(
            enabled: toolbar.isChecked("TBWavIncrease"),
            selected: optionsSidebar.selectedWavIndex,
            token: token
        ) else { return }
        optionsSidebar.stepWavSelection(-1)
    }

    private func writeClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func encodeSelection(
        _ items: (events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>)
    ) -> String {
        var notes = items.events.map { event in
            LegacyClipboard.note(
                channel: event.channel,
                measure: event.measure,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator,
                token: event.token
            )
        }
        for pair in items.longNotes {
            let start = LegacyClipboard.vPosition(
                measure: pair.start.measure,
                fractionNumerator: pair.start.fractionNumerator,
                fractionDenominator: pair.start.fractionDenominator
            )
            let end = LegacyClipboard.vPosition(
                measure: pair.end.measure,
                fractionNumerator: pair.end.fractionNumerator,
                fractionDenominator: pair.end.fractionDenominator
            )
            if ntInputEnabled {
                notes.append(
                    LegacyClipboard.note(
                        channel: pair.channel,
                        measure: pair.start.measure,
                        fractionNumerator: pair.start.fractionNumerator,
                        fractionDenominator: pair.start.fractionDenominator,
                        token: pair.start.token,
                        length: end - start
                    )
                )
            } else {
                notes.append(
                    LegacyClipboard.note(
                        channel: pair.channel,
                        measure: pair.start.measure,
                        fractionNumerator: pair.start.fractionNumerator,
                        fractionDenominator: pair.start.fractionDenominator,
                        token: pair.start.token
                    )
                )
                notes.append(
                    LegacyClipboard.note(
                        channel: pair.channel,
                        measure: pair.end.measure,
                        fractionNumerator: pair.end.fractionNumerator,
                        fractionDenominator: pair.end.fractionDenominator,
                        token: pair.end.token
                    )
                )
            }
        }
        return LegacyClipboard.encode(notes, ntInput: ntInputEnabled)
    }

    private func convertSelectedShortNotesToLong() {
        let events = Array(chartSurface.selectedChartItems().events)
        for pair in ChartConvert.longNotePairs(from: events) {
            guard actions.convertShortNotesToLong?(pair.0, pair.1) == true else { return }
        }
        for leftover in ChartConvert.unpairedLongNotes(from: events) {
            guard actions.convertShortNoteToLongEndpoint?(leftover) == true else { return }
        }
    }

    private func convertSelectedLongNotesToShort() {
        let keepEnd = ChartConvert.longNoteMenuEnabled(ntInput: chartSurface.ntInputEnabled)
        let items = chartSurface.selectedChartItems()
        let notes = items.longNotes.sorted {
            ($0.start.measure, $0.channel, $0.start.fractionNumerator, $0.start.fractionDenominator)
                < ($1.start.measure, $1.channel, $1.start.fractionNumerator, $1.start.fractionDenominator)
        }
        for note in notes {
            guard actions.convertLongNoteToShort?(note, keepEnd) == true else { return }
        }
        for leftover in ChartConvert.unpairedLongEndpoints(
            from: Array(items.events),
            longs: chartSurface.currentLongNotes.notes
        ) {
            guard actions.convertLongEndpointToShort?(leftover) == true else { return }
        }
    }

    private func moveSelectedNotes(digit: Int, shiftFirstOnly: Bool) {
        if digit == 0 {
            _ = actions.moveSelectedToBGM?()
            return
        }
        guard let display = LegacyMoveNotes.playableDisplay(forDigit: digit) else { return }
        let lanes = Set(chartSurface.chartLayout.lanes.map(\.channel))
        guard lanes.contains(display) else { return }
        _ = actions.moveSelectedToColumn?(display, shiftFirstOnly)
    }

    private func moveSelectedNotesByArrow(direction: LegacyArrowMove.Direction, control: Bool) {
        let items = chartSurface.selectedChartItems()
        let events = Array(items.events)
        let longs = Array(items.longNotes)
        guard !events.isEmpty || !longs.isEmpty else { return }
        let lanes = chartSurface.chartLayout.lanes.map(\.channel)
        let enabled = Array(repeating: true, count: lanes.count)
        func realColumn(of channel: String) -> Int? {
            lanes.firstIndex(of: ChartLayout.displayChannel(channel))
        }
        var notes: [LegacyArrowMove.Note] = []
        var shortSources: [ChartEventSnapshot] = []
        var longSources: [LongNoteSnapshot] = []
        for event in events {
            guard let real = realColumn(of: event.channel) else { continue }
            notes.append(
                LegacyArrowMove.Note(
                    realColumn: real,
                    vPosition: ChartDuplicate.vPosition(beat: event.beat),
                    length: 0,
                    channel: event.channel
                )
            )
            shortSources.append(event)
        }
        for note in longs {
            guard let real = realColumn(of: note.channel) else { continue }
            let start = ChartDuplicate.vPosition(beat: note.start.beat)
            notes.append(
                LegacyArrowMove.Note(
                    realColumn: real,
                    vPosition: start,
                    length: ChartDuplicate.vPosition(beat: note.end.beat) - start,
                    channel: note.channel
                )
            )
            longSources.append(note)
        }
        let result = LegacyArrowMove.move(
            notes: notes,
            direction: direction,
            enabled: enabled,
            divide: selectedDivision,
            control: control,
            ntInput: ntInputEnabled,
            displays: lanes
        )
        guard result.recordUndo, result.moved else { return }
        var shorts: [ChartDuplicate.ShortCopy] = []
        var longCopies: [ChartDuplicate.LongCopy] = []
        for (event, destination) in zip(shortSources, result.destinations.prefix(shortSources.count))
            where destination.moved {
            shorts.append(
                ChartDuplicate.ShortCopy(
                    event: event,
                    channel: destination.channel,
                    vPosition: destination.vPosition
                )
            )
        }
        for (note, destination) in zip(longSources, result.destinations.dropFirst(shortSources.count))
            where destination.moved {
            let start = ChartDuplicate.vPosition(beat: note.start.beat)
            longCopies.append(
                ChartDuplicate.LongCopy(
                    note: note,
                    channel: destination.channel,
                    vPosition: destination.vPosition,
                    length: ChartDuplicate.vPosition(beat: note.end.beat) - start
                )
            )
        }
        guard !shorts.isEmpty || !longCopies.isEmpty else { return }
        _ = actions.moveNotesAtVPosition?(shorts, longCopies)
    }

    private func convertSelectedNotes(_ action: ChartConvert.HiddenAction) {
        let events = chartSurface.selectedChartItems().events.sorted {
            ($0.measure, $0.channel, $0.fractionNumerator, $0.fractionDenominator)
                < ($1.measure, $1.channel, $1.fractionNumerator, $1.fractionDenominator)
        }
        for event in events {
            guard let destination = ChartConvert.destinationChannel(for: event.channel, action: action) else { continue }
            guard actions.convertNote?(event, destination) == true else { return }
        }
    }

    private func toolbarTooltip(_ name: String) -> String {
        MainToolbarLayout.items.first { $0.name == name }?.tooltip
            ?? "This command is not implemented yet."
    }

    private func makeEditorRegion() -> NSView {
        let region = NSView()
        region.translatesAutoresizingMaskIntoConstraints = false
        let editor = makeEditorArea()
        [toolbar, editor, statusStrip, timeStrip].forEach(region.addSubview)
        let toolbarHeight = toolbar.heightAnchor.constraint(equalToConstant: MainWindowChrome.toolbarHeight)
        let statusHeight = statusStrip.heightAnchor.constraint(equalToConstant: MainWindowChrome.statusHeight)
        toolbarHeightConstraint = toolbarHeight
        statusHeightConstraint = statusHeight
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: region.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: region.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: region.topAnchor),
            toolbarHeight,
            editor.leadingAnchor.constraint(equalTo: region.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: region.trailingAnchor),
            editor.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            editor.bottomAnchor.constraint(equalTo: statusStrip.topAnchor),
            statusStrip.leadingAnchor.constraint(equalTo: region.leadingAnchor),
            statusStrip.trailingAnchor.constraint(equalTo: region.trailingAnchor),
            statusStrip.bottomAnchor.constraint(equalTo: region.bottomAnchor),
            statusHeight,
            timeStrip.leadingAnchor.constraint(equalTo: statusStrip.leadingAnchor),
            timeStrip.trailingAnchor.constraint(equalTo: statusStrip.trailingAnchor),
            timeStrip.topAnchor.constraint(equalTo: statusStrip.topAnchor),
            timeStrip.bottomAnchor.constraint(equalTo: statusStrip.bottomAnchor)
        ])
        return region
    }

    private func makeEditorArea() -> NSView {
        let editor = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = NSColor.black.cgColor
        leftSplitter.onResize = { [weak self] mouseX, grabX in
            guard let self else { return }
            self.panes[0].sideWidth = CGFloat(LegacyPanelScroll.resizeLeft(
                current: Int(self.panes[0].sideWidth.rounded()),
                mouseX: mouseX,
                grabX: grabX
            ))
        }
        rightSplitter.onResize = { [weak self] mouseX, grabX in
            guard let self else { return }
            self.panes[2].sideWidth = CGFloat(LegacyPanelScroll.resizeRight(
                current: Int(self.panes[2].sideWidth.rounded()),
                mouseX: mouseX,
                grabX: grabX
            ))
        }
        [panes[0], leftSplitter, panes[1], rightSplitter, panes[2]].forEach(editor.addSubview)
        NSLayoutConstraint.activate([
            panes[0].leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            panes[0].topAnchor.constraint(equalTo: editor.topAnchor),
            panes[0].bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            leftSplitter.leadingAnchor.constraint(equalTo: panes[0].trailingAnchor),
            leftSplitter.topAnchor.constraint(equalTo: editor.topAnchor),
            leftSplitter.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            panes[1].leadingAnchor.constraint(equalTo: leftSplitter.trailingAnchor),
            panes[1].topAnchor.constraint(equalTo: editor.topAnchor),
            panes[1].bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            rightSplitter.leadingAnchor.constraint(equalTo: panes[1].trailingAnchor),
            rightSplitter.topAnchor.constraint(equalTo: editor.topAnchor),
            rightSplitter.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            panes[2].leadingAnchor.constraint(equalTo: rightSplitter.trailingAnchor),
            panes[2].trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            panes[2].topAnchor.constraint(equalTo: editor.topAnchor),
            panes[2].bottomAnchor.constraint(equalTo: editor.bottomAnchor)
        ])
        for pane in panes {
            pane.onScrollChange = { [weak self] pane in
                self?.panelDidScroll(pane)
            }
            pane.onBecomeActive = { [weak self] index in
                self?.panelFocus = index
            }
            bindChart(pane.surface)
            bindFooter(pane)
        }
        actions.chartSurface = panes[1].surface
        return editor
    }

    private func forEachSurface(_ body: (ChartSurfaceView) -> Void) {
        for pane in panes { body(pane.surface) }
    }

    private func broadcastChartUpdate(
        snapshot: ChartSnapshot? = nil,
        longNotes: LongNoteSnapshotSet? = nil,
        theme: ChartTheme? = nil,
        showsTwoPlayer: Bool? = nil,
        hiddenPlayChannels: Set<String>? = nil,
        onePlayerOrder: [(String, Int)]? = nil,
        twoPlayerOrder: [(String, Int)]? = nil,
        playSkinColors: [String: ChartPlaySkinColor]? = nil
    ) {
        let source = chartSurface
        suppressScrollFollow = true
        defer { suppressScrollFollow = false }
        forEachSurface { surface in
            surface.update(
                snapshot: snapshot ?? source.chartLayout.snapshot,
                longNotes: longNotes ?? source.chartLayout.longNotes,
                theme: theme ?? chartTheme,
                side: selectedSide,
                pixelsPerQuarterBeat: selectedZoom,
                division: selectedDivision,
                subDivision: selectedSubDivision,
                showGrid: showGrid,
                showSubGrid: showSubGrid,
                showMeasureBar: showMeasureBar,
                showBackground: showBackground,
                showMeasureNumber: showMeasureNumber,
                showVerticalLine: showVerticalLine,
                showColumnCaption: showColumnCaption,
                showsTwoPlayerColumns: showsTwoPlayer,
                bgmColumnCount: selectedBGMColumnCount,
                showsScrollColumn: showsScrollColumn,
                showsBPMColumn: showsBPMColumn,
                showsStopColumn: showsStopColumn,
                showsBGAColumns: showsBGAColumns,
                gxWidth: selectedColumnScale,
                showMasterLane: source.showsMasterLane,
                hiddenPlayChannels: hiddenPlayChannels,
                soundChannelLanes: soundChannelLanes(theme: theme ?? chartTheme),
                onePlayerOrder: onePlayerOrder,
                twoPlayerOrder: twoPlayerOrder,
                playSkinColors: playSkinColors
            )
        }
    }

    private func refreshBmsonFooter(visible: Bool? = nil) {
        let on = visible ?? !soundChannelNames.isEmpty
        let current = selectedWavIndex >= 0 ? selectedWavIndex : 0
        if on {
            bmsonFooterSelected.insert(current)
        }
        let visibleIndices = BmsonSoundLane.visibleIndices(
            count: soundChannelNames.count,
            shown: shownSoundChannels
        )
        for pane in panes {
            pane.setFooterHeight(bmsonFooterHeight, visible: on)
            let layout = pane.surface.chartLayout
            var cells = BmsONEFooter.channelCells(
                names: soundChannelNames,
                frames: layout.laneFrames,
                visible: visibleIndices,
                height: on ? bmsonFooterHeight : 0
            )
            if let mode = bmsonViewMode {
                cells.append(contentsOf: playingFooterCells(layout: layout, mode: mode))
            }
            pane.footer.cells = cells
            pane.footer.currentIndex = current
            pane.footer.selectedIndices = bmsonFooterSelected
            pane.footer.contentOffsetX = pane.surface.scrollOffset.x
            pane.footer.gutterWidth = ChartLayout.measureGutter * selectedColumnScale
            pane.footer.masterFrame = layout.masterLaneFrame
            pane.footer.footerHeight = on ? bmsonFooterHeight : 0
        }
    }

    private func currentBmsonScratch() -> BmsONEScratch.Choice? {
        guard let mode = bmsonViewMode else { return nil }
        return BmsONEScratch.load(kind: mode.kind)
    }

    private func bmsonPlaySkinColors(mode: BmsONEViewMode) -> [String: ChartPlaySkinColor] {
        guard let scheme = BmsONEColorScheme.load(kind: mode.kind) else { return [:] }
        return Dictionary(uniqueKeysWithValues: BmsONEColorScheme.playPaints(kind: mode.kind, scheme: scheme).map { channel, paint in
            (
                channel,
                ChartPlaySkinColor(
                    note: ThemeColor(
                        red: paint.note.red,
                        green: paint.note.green,
                        blue: paint.note.blue
                    ),
                    background: ThemeColor(
                        red: paint.background.red,
                        green: paint.background.green,
                        blue: paint.background.blue
                    )
                )
            )
        })
    }

    private func bmsonPlayOrders(mode: BmsONEViewMode) -> (one: [(String, Int)]?, two: [(String, Int)]?) {
        guard let scratch = BmsONEScratch.load(kind: mode.kind) else {
            return (nil, nil)
        }
        let one = BmsONEScratch.player1Channels(kind: mode.kind, scratch: scratch)
        let two = BmsONEScratch.player2Channels(kind: mode.kind, scratch: scratch)
        return (
            one.isEmpty ? nil : ChartLanes.pairs(for: one),
            two.isEmpty ? nil : ChartLanes.pairs(for: two)
        )
    }

    private func currentBmsonLaneOrder() -> BmsONELaneOrder.Choice? {
        guard let mode = bmsonViewMode else { return nil }
        return BmsONELaneOrder.load(kind: mode.kind)
    }

    private func playingKeyLanes(mode: BmsONEViewMode) -> [Int64] {
        if let count = BmsONEPlainLanes.load(kind: mode.kind) {
            return BmsONEPlainLanes.keyLanes(count: count)
        }
        if let scratch = currentBmsonScratch() {
            return BmsONEScratch.keyLanes(kind: mode.kind, scratch: scratch)
        }
        if let order = currentBmsonLaneOrder() {
            return BmsONELaneOrder.keyLanes(kind: mode.kind, order: order)
        }
        if let wheel = BmsONEWheel.load(kind: mode.kind) {
            return BmsONEWheel.keyLanes(kind: mode.kind, wheel: wheel)
        }
        return mode.keyLanes
    }

    private func playingFooterCells(layout: ChartLayout, mode: BmsONEViewMode) -> [BmsONEFooter.Cell] {
        playingKeyLanes(mode: mode).compactMap { lane in
            guard let channel = mode.laneToChannel[lane],
                  let frame = layout.laneFrames[channel],
                  frame.width > 0
            else { return nil }
            let image: String
            switch mode.kind {
            case .beat5k, .beat7k, .beat10k, .beat14k:
                if lane == 8 || lane == 16 {
                    image = "scratch"
                } else {
                    image = lane % 2 == 1 ? "wkey" : "bkey"
                }
            case .circularSingle, .circularDouble:
                if let order = currentBmsonLaneOrder() {
                    image = BmsONELaneOrder.imageName(kind: mode.kind, lane: lane, order: order)
                } else {
                    image = ""
                }
            default:
                image = ""
            }
            return BmsONEFooter.Cell(
                kind: .playing(label: String(lane), imageName: image),
                frame: CGRect(x: frame.minX, y: 0, width: frame.width, height: bmsonFooterHeight)
            )
        }
    }

    private func bindFooter(_ pane: ChartEditorPane) {
        pane.footer.onHit = { [weak self] hit in
            self?.handleBmsonFooterHit(hit)
        }
        pane.footer.onHeightDrag = { [weak self] height in
            guard let self else { return }
            self.bmsonFooterHeight = CGFloat(height)
            self.refreshBmsonFooter(visible: true)
            self.onBmsonFooterHeight?(height)
        }
        pane.footer.onMenu = { [weak self] index, point in
            self?.onBmsonFooterSelect?(index)
            self?.onBmsonFooterMenu?(index, point)
        }
        pane.footer.onPlayingMenu = { [weak self] point in
            self?.onBmsonPlayingFooterMenu?(point)
        }
    }

    private func handleBmsonFooterHit(_ hit: BmsONEFooter.Hit) {
        switch hit {
        case .grip, .none:
            return
        case .select(let index):
            let next = BmsONEFooter.applyClick(
                current: selectedWavIndex >= 0 ? selectedWavIndex : 0,
                selected: bmsonFooterSelected,
                clicked: index,
                toggle: false
            )
            bmsonFooterSelected = next.selected
            onBmsonFooterSelect?(index)
            refreshBmsonFooter(visible: true)
        case .toggle(let index):
            let next = BmsONEFooter.applyClick(
                current: selectedWavIndex >= 0 ? selectedWavIndex : 0,
                selected: bmsonFooterSelected,
                clicked: index,
                toggle: true
            )
            bmsonFooterSelected = next.selected
            refreshBmsonFooter(visible: true)
        case .preview(let index):
            let next = BmsONEFooter.applyClick(
                current: selectedWavIndex >= 0 ? selectedWavIndex : 0,
                selected: bmsonFooterSelected,
                clicked: index,
                toggle: false
            )
            bmsonFooterSelected = next.selected
            onBmsonFooterSelect?(index)
            onBmsonFooterPreview?(index)
            refreshBmsonFooter(visible: true)
        }
    }

    private func soundChannelLanes(theme: ChartTheme) -> [ChartLane] {
        guard let mode = bmsonSoundLaneMode else { return [] }
        return BmsonSoundLane.visibleIndices(count: soundChannelNames.count, shown: shownSoundChannels)
            .compactMap { index in
                let name = soundChannelNames[index]
                return ChartLanes.fixedWidthLane(
                    channel: BmsonSoundLane.displayChannel(index: index),
                    title: name.isEmpty ? BmsonChartMapping.wavToken(channelIndex: index) : name,
                    width: mode.width,
                    theme: theme
                )
            }
    }

    private func winScroll(of pane: ChartEditorPane) -> Int {
        let maxOffset = max(0, pane.surface.chartLayout.contentSize.height - pane.surface.bounds.height)
        return LegacyPanelScroll.winScroll(
            offsetY: Double(pane.surface.scrollOffset.y),
            maxOffset: Double(maxOffset)
        )
    }

    private func setWinScroll(_ pane: ChartEditorPane, _ value: Int) {
        let maxOffset = max(0, pane.surface.chartLayout.contentSize.height - pane.surface.bounds.height)
        let y = LegacyPanelScroll.offsetY(winScroll: value, maxOffset: Double(maxOffset))
        pane.surface.setOffset(CGPoint(x: pane.surface.scrollOffset.x, y: CGFloat(y)))
    }

    private func winMinimum(of pane: ChartEditorPane) -> Int {
        -Int(max(0, pane.surface.chartLayout.contentSize.height - pane.surface.bounds.height).rounded())
    }

    private func captureScrollDiffs(locking index: Int) {
        scrollDiffs = LegacyPanelScroll.diffs(locking: index, scrolls: panes.map(winScroll(of:)))
    }

    private func panelDidScroll(_ pane: ChartEditorPane) {
        guard !suppressScrollFollow else { return }
        let source = pane.index
        let scrolls = panes.map(winScroll(of:))
        let minimum = panes.map(winMinimum(of:)).min() ?? 0
        let targets = LegacyPanelScroll.follow(
            source: source,
            value: scrolls[source],
            locks: optionsSidebar.scrollLocks,
            diffs: scrollDiffs,
            minimum: minimum
        )
        suppressScrollFollow = true
        for (index, target) in targets.enumerated() {
            if let target {
                setWinScroll(panes[index], target)
            }
        }
        suppressScrollFollow = false
        let after = panes.map(winScroll(of:))
        scrollDiffs[source] = after[(source + 1) % 3] - after[source]
        scrollDiffs[(source + 2) % 3] = after[source] - after[(source + 2) % 3]
        onBmsonVisibleRangeChange?()
    }

    private func syncSelection(from source: ChartSurfaceView) {
        guard !suppressSelectionSync else { return }
        suppressSelectionSync = true
        let items = source.selectedChartItems()
        let time = source.timeSelection
        forEachSurface { surface in
            guard surface !== source else { return }
            surface.applySelection(events: items.events, longNotes: items.longNotes)
            surface.applyTimeSelection(time)
        }
        suppressSelectionSync = false
        onChartSelectionChange?()
    }

    private func bindChart(_ chart: ChartSurfaceView) {
        chart.writeRequested = { [weak self] channel, measure, slot, continueFlag in
            guard let self else { return }
            if BmsonSoundLane.index(display: channel) != nil {
                let token = self.optionsSidebar.selectedToken
                _ = self.actions.writeNote?(
                    channel, measure.measure, slot, self.selectedDivision, token, continueFlag
                )
                return
            }
            if ["03", "09", "SC"].contains(channel) {
                _ = self.actions.writeTiming?(channel, measure.measure, slot, self.selectedDivision)
                return
            }
            let token = ["04", "06", "07"].contains(channel)
                ? self.optionsSidebar.selectedBMPToken
                : self.optionsSidebar.selectedToken
            guard Self.validToken(token) else {
                self.statusStrip.setNotice(
                    ["04", "06", "07"].contains(channel)
                        ? "Choose a BMP token from 01 through ZZ."
                        : "Choose a WAV token from 01 through ZZ."
                )
                return
            }
            if self.actions.writeNote?(
                channel, measure.measure, slot, self.selectedDivision, token, continueFlag
            ) == true {
                self.autoincreaseWavIfNeeded(channel: channel)
            }
        }
        chart.activateSoundChannelLaneRequested = { [weak self] index in
            self?.actions.activateSoundChannelLane?(index) ?? true
        }
        chart.writeAtPulseRequested = { [weak self] channel, pulse, continueFlag in
            guard let self else { return }
            if BmsonSoundLane.index(display: channel) != nil {
                let token = self.optionsSidebar.selectedToken
                _ = self.actions.writeNoteAtPulse?(channel, pulse, token, continueFlag)
                return
            }
            if ["03", "09", "SC"].contains(channel) {
                _ = self.actions.writeTimingAtPulse?(channel, pulse)
                return
            }
            let token = ["04", "06", "07"].contains(channel)
                ? self.optionsSidebar.selectedBMPToken
                : self.optionsSidebar.selectedToken
            guard Self.validToken(token) else {
                self.statusStrip.setNotice(
                    ["04", "06", "07"].contains(channel)
                        ? "Choose a BMP token from 01 through ZZ."
                        : "Choose a WAV token from 01 through ZZ."
                )
                return
            }
            if self.actions.writeNoteAtPulse?(channel, pulse, token, continueFlag) == true {
                self.autoincreaseWavIfNeeded(channel: channel)
            }
        }
        chart.moveRequested = { [weak self] event, channel, measure, slot in
            guard let self else { return false }
            return self.actions.moveNote?(event, channel, measure.measure, slot, self.selectedDivision) ?? false
        }
        chart.moveAtPulseRequested = { [weak self] event, channel, pulse in
            guard let self else { return false }
            return self.actions.moveNoteAtPulse?(event, channel, pulse) ?? false
        }
        chart.zoomWheelRequested = { [weak self] event in
            guard let self else { return }
            if self.bmsonZoomResolution != nil {
                self.applyBmsonZoomWheel(event)
            } else if event.notches != 0 {
                self.optionsSidebar.applyCtrlWheelZoom(notches: event.notches)
            }
        }
        chart.copyRequested = { [weak self] event, channel, measure, slot in
            guard let self else { return false }
            return self.actions.writeNote?(
                channel,
                measure,
                slot,
                self.selectedDivision,
                event.token,
                false
            ) ?? false
        }
        chart.copyAtVPositionRequested = { [weak self] event, channel, vPosition in
            guard let self else { return false }
            return self.actions.copyNoteAtVPosition?(event, channel, vPosition) ?? false
        }
        chart.copyLongAtVPositionRequested = { [weak self] note, channel, vPosition, length in
            guard let self else { return false }
            return self.actions.copyLongNoteAtVPosition?(note, channel, vPosition, length) ?? false
        }
        chart.copyBatchAtVPositionRequested = { [weak self] shorts, longs in
            guard let self else { return false }
            return self.actions.copyNotesAtVPosition?(shorts, longs) ?? false
        }
        chart.moveBatchAtVPositionRequested = { [weak self] shorts, longs in
            guard let self else { return false }
            return self.actions.moveNotesAtVPosition?(shorts, longs) ?? false
        }
        chart.eraseRequested = { [weak self] event in
            guard let self else { return }
            if self.actions.eraseNote?(event) == true {
                self.autodecreaseWavIfNeeded(token: event.token)
            }
        }
        chart.doubleClickNoteRequested = { [weak self] event in
            self?.actions.doubleClickNote?(event)
        }
        chart.doubleClickLongNoteRequested = { [weak self] note in
            self?.actions.doubleClickLongNote?(note)
        }
        chart.wavSelectRequested = { [weak self] slot in
            self?.selectWavSlots([slot])
        }
        chart.insertLongNoteRequested = { [weak self] channel, startMeasure, startSlot, endMeasure, endSlot, isLongChannel, continueFlag in
            guard let self else { return false }
            let token = self.optionsSidebar.selectedToken
            guard Self.validToken(token) else {
                self.statusStrip.setNotice("Choose a WAV token from 01 through ZZ.")
                return false
            }
            let ok = self.actions.insertLongNote?(
                channel,
                startMeasure.measure,
                startSlot,
                endMeasure.measure,
                endSlot,
                self.selectedDivision,
                token,
                isLongChannel ? token : "",
                continueFlag
            ) ?? false
            if ok {
                self.autoincreaseWavIfNeeded(channel: channel)
            }
            return ok
        }
        chart.insertLongAtPulseRequested = { [weak self] channel, startPulse, endPulse, continueFlag in
            guard let self else { return false }
            let token = self.optionsSidebar.selectedToken
            guard Self.validToken(token) else {
                self.statusStrip.setNotice("Choose a WAV token from 01 through ZZ.")
                return false
            }
            let ok = self.actions.insertLongAtPulse?(
                channel,
                startPulse,
                endPulse,
                token,
                continueFlag
            ) ?? false
            if ok {
                self.autoincreaseWavIfNeeded(channel: channel)
            }
            return ok
        }
        chart.moveLongNoteRequested = { [weak self] note, channel, measure, slot in
            guard let self else { return false }
            return self.actions.moveLongNote?(note, channel, measure.measure, slot, self.selectedDivision) ?? false
        }
        chart.moveLongAtPulseRequested = { [weak self] note, channel, pulse in
            guard let self else { return false }
            return self.actions.moveLongAtPulse?(note, channel, pulse) ?? false
        }
        chart.moveLongNoteStartRequested = { [weak self] note, measure, slot in
            guard let self else { return false }
            return self.actions.moveLongNoteStart?(note, measure.measure, slot, self.selectedDivision) ?? false
        }
        chart.moveLongStartAtPulseRequested = { [weak self] note, pulse in
            guard let self else { return false }
            return self.actions.moveLongStartAtPulse?(note, pulse) ?? false
        }
        chart.resizeLongNoteRequested = { [weak self] note, measure, slot in
            guard let self else { return false }
            return self.actions.resizeLongNote?(note, measure.measure, slot, self.selectedDivision) ?? false
        }
        chart.resizeLongAtPulseRequested = { [weak self] note, pulse in
            guard let self else { return false }
            return self.actions.resizeLongAtPulse?(note, pulse) ?? false
        }
        chart.eraseLongNoteRequested = { [weak self] note in
            guard let self else { return }
            if self.actions.eraseLongNote?(note) == true {
                self.autodecreaseWavIfNeeded(token: note.start.token)
            }
        }
        chart.isShowFileNameEnabled = { [weak self] in
            self?.toolbar.isChecked("TBShowFileName") ?? false
        }
        chart.previewOnClick = toolbar.isChecked("TBPreviewOnClick")
        chart.previewNoteRequested = { [weak self] token in
            self?.actions.previewNoteToken?(token)
        }
        chart.unsupportedGesture = { [weak self] message in
            self?.statusStrip.setNotice(message)
        }
        chart.chartClicked = { [weak self] in
            self?.actions.hidePreview?()
        }
        chart.timeSelectionDidChange = { [weak self] selection in
            self?.timeStrip.setSelection(selection)
        }
        chart.toggleSnapRequested = { [weak self] in
            guard let self else { return }
            self.setSnapEnabled(!self.optionsSidebar.snapEnabled)
        }
        chart.toggleDisableVerticalMoveRequested = { [weak self] in
            guard let self else { return }
            let enabled = !self.optionsSidebar.disableVerticalMove
            self.optionsSidebar.setDisableVerticalMove(enabled)
            self.forEachSurface { $0.disableVerticalMove = enabled }
        }
        chart.barLineEditRequested = { [weak self] beat, remove in
            self?.actions.editBmsonBarLine?(beat, remove) ?? false
        }
        chart.masterLanePreviewRequested = { [weak self] _ in
            self?.actions.playFromHere?()
        }
        chart.applySlashDivisionRequested = { [weak self] in
            self?.optionsSidebar.applySlashDivision()
        }
        chart.doubleDivisionRequested = { [weak self] in
            self?.optionsSidebar.doubleDivision()
        }
        chart.halfDivisionRequested = { [weak self] in
            self?.optionsSidebar.halfDivision()
        }
        chart.moveDigitRequested = { [weak self] digit, shiftFirstOnly in
            self?.moveSelectedNotes(digit: digit, shiftFirstOnly: shiftFirstOnly)
        }
        chart.moveArrowRequested = { [weak self] direction, control in
            self?.moveSelectedNotesByArrow(direction: direction, control: control)
        }
        chart.heightNudgeRequested = { [weak self] up in
            guard let self else { return }
            if self.bmsonZoomResolution != nil {
                if up {
                    self.zoomBmsonIn()
                } else {
                    self.zoomBmsonOut()
                }
            } else {
                self.optionsSidebar.applyHeightNudge(up: up)
            }
        }
        chart.wavStepRequested = { [weak self] delta in
            self?.optionsSidebar.stepWavSelection(delta)
        }
        chart.convertShortcutRequested = { [weak self] shortcut in
            switch shortcut {
            case .long:
                self?.handleToolbar("POBLong")
            case .short:
                self?.handleToolbar("POBShort")
            }
        }
        chart.timeSelectKeyRequested = { [weak self] tool in
            self?.setChartTool(tool)
        }
        chart.timeSelectionCommandRequested = { [weak self] command in
            self?.actions.performTimeSelection?(command)
        }
        chart.hoverDidChange = { [weak self] in
            self?.refreshHoverStatus()
        }
        chart.copyChartRequested = { [weak self] in self?.copyChartNotes() }
        chart.cutChartRequested = { [weak self] in self?.cutChartNotes() }
        chart.pasteChartRequested = { [weak self] in self?.pasteChartNotes() }
        chart.deleteChartRequested = { [weak self] in self?.deleteSelectedNotes() }
        chart.selectAllChartRequested = { [weak self] in self?.selectAllChartNotes() }
        chart.ctrlEditRequested = { [weak self] action in
            guard let self else { return }
            switch action {
            case .undo:
                self.actions.undo(nil)
            case .redo:
                self.actions.redo(nil)
            case .cut:
                self.cutChartNotes()
            case .copy:
                self.copyChartNotes()
            case .paste:
                self.pasteChartNotes()
            case .selectAll:
                self.selectAllChartNotes()
            case .find:
                self.actions.showFind?()
            case .statistics:
                self.actions.showStatistics?()
            }
        }
        chart.snapshotDidChange = { [weak self, weak chart] _ in
            guard let self, let chart else { return }
            self.syncSelection(from: chart)
        }
    }

    private static func validToken(_ token: String) -> Bool {
        guard token.utf8.count == 2 else { return false }
        return token.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) } && token != "00"
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return divider
    }
}

@MainActor
final class EditorActionTarget: NSObject {
    var isBusy: (() -> Bool)?
    var newDocument: (() -> Void)?
    var openDocument: (() -> Void)?
    var openRecent: ((Int) -> Void)?
    var saveDocument: (() -> Void)?
    var saveDocumentAs: (() -> Void)?
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    var showPreview: (() -> Void)?
    var playFromBeginning: (() -> Void)?
    var playFromHere: (() -> Void)?
    var stopPreview: (() -> Void)?
    var setMetadata: ((String, String) -> Bool)?
    var selectEncoding: ((MetadataEncoding) -> Bool)?
    var setInitialBPM: ((String) -> Bool)?
    var refresh: (() -> Void)?
    weak var chartSurface: ChartSurfaceView?
    var writeNote: ((String, Int, Int, Int, String, Bool) -> Bool)?
    var writeNoteAtPulse: ((String, Int64, String, Bool) -> Bool)?
    var activateSoundChannelLane: ((Int) -> Bool)?
    var writeTiming: ((String, Int, Int, Int) -> Bool)?
    var writeTimingAtPulse: ((String, Int64) -> Bool)?
    var moveNote: ((ChartEventSnapshot, String, Int, Int, Int) -> Bool)?
    var moveNoteAtPulse: ((ChartEventSnapshot, String, Int64) -> Bool)?
    var insertLongAtPulse: ((String, Int64, Int64, String, Bool) -> Bool)?
    var moveLongAtPulse: ((LongNoteSnapshot, String, Int64) -> Bool)?
    var moveLongStartAtPulse: ((LongNoteSnapshot, Int64) -> Bool)?
    var resizeLongAtPulse: ((LongNoteSnapshot, Int64) -> Bool)?
    var convertNote: ((ChartEventSnapshot, String) -> Bool)?
    var eraseNote: ((ChartEventSnapshot) -> Bool)?
    var insertLongNote: ((String, Int, Int, Int, Int, Int, String, String, Bool) -> Bool)?
    var moveLongNote: ((LongNoteSnapshot, String, Int, Int, Int) -> Bool)?
    var moveLongNoteStart: ((LongNoteSnapshot, Int, Int, Int) -> Bool)?
    var resizeLongNote: ((LongNoteSnapshot, Int, Int, Int) -> Bool)?
    var eraseLongNote: ((LongNoteSnapshot) -> Bool)?
    var convertLongNoteToShort: ((LongNoteSnapshot, Bool) -> Bool)?
    var convertShortNotesToLong: ((ChartEventSnapshot, ChartEventSnapshot) -> Bool)?
    var convertShortNoteToLongEndpoint: ((ChartEventSnapshot) -> Bool)?
    var convertLongEndpointToShort: ((ChartEventSnapshot) -> Bool)?
    var showFind: (() -> Void)?
    var showStatistics: (() -> Void)?
    var showVisualOptions: (() -> Void)?
    var showGeneralOptions: (() -> Void)?
    var showPlayerOptions: (() -> Void)?
    var importSM: (() -> Void)?
    var importIBMSC: (() -> Void)?
    var exportIBMSC: (() -> Void)?
    var showMyO2: (() -> Void)?
    var hidePreview: (() -> Void)?
    var performTimeSelection: ((TimeSelectionCommand) -> Void)?
    var previewNoteToken: ((String) -> Void)?
    var pasteClipboard: ((String, Double, Bool) -> Bool)?
    var eraseSelection: ((Set<ChartEventSnapshot>, Set<LongNoteSnapshot>) -> Bool)?
    var toggleNTInput: ((Bool) -> Void)?
    var copyNoteAtVPosition: ((ChartEventSnapshot, String, Double) -> Bool)?
    var copyLongNoteAtVPosition: ((LongNoteSnapshot, String, Double, Double) -> Bool)?
    var copyNotesAtVPosition: (([ChartDuplicate.ShortCopy], [ChartDuplicate.LongCopy]) -> Bool)?
    var moveNotesAtVPosition: (([ChartDuplicate.ShortCopy], [ChartDuplicate.LongCopy]) -> Bool)?
    var mirrorSelected: (() -> Void)?
    var moveSelectedToColumn: ((String, Bool) -> Bool)?
    var moveSelectedToBGM: (() -> Bool)?
    var modifySelected: (() -> Void)?
    var doubleClickNote: ((ChartEventSnapshot) -> Void)?
    var doubleClickLongNote: ((LongNoteSnapshot) -> Void)?
    var applyWavEdit: ((WavListEdit, Bool) -> Bool)?
    var applyBmpEdit: ((WavListEdit, Bool) -> Bool)?
    var applyWaveformColor: ((ThemeColor) -> Void)?
    var applyBeat: (([Int], String, LegacyBeat.Mode) -> Bool)?
    var editBmsonBarLine: ((Double, Bool) -> Bool)?
    var applyExpansion: ((String) -> Bool)?
    var resetLanguagePreference: (() -> Void)?
    var refreshLanguageMenu: (() -> Void)?
    var loadLanguageFile: ((String) -> Void)?

    @objc func newDocument(_ sender: Any?) { runWhenReady(newDocument) }
    @objc func openDocument(_ sender: Any?) { runWhenReady(openDocument) }
    @objc func saveDocument(_ sender: Any?) { runWhenReady(saveDocument) }
    @objc func undo(_ sender: Any?) { runWhenReady(undo) }
    @objc func redo(_ sender: Any?) { runWhenReady(redo) }
    @objc func showPreview(_ sender: Any?) { runWhenReady(showPreview) }
    @objc func verticalScrolled(_ sender: NSScroller) { chartSurface?.setVerticalFraction(CGFloat(sender.doubleValue)) }
    @objc func horizontalScrolled(_ sender: NSScroller) { chartSurface?.setHorizontalFraction(CGFloat(sender.doubleValue)) }

    func commitMetadata(key: String, value: String) -> Bool {
        setMetadata?(key, value) ?? false
    }

    private func runWhenReady(_ action: (() -> Void)?) {
        guard isBusy?() != true else { return }
        action?()
    }
}
