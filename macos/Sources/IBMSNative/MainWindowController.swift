import AppKit
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    private enum Transition {
        case newDocument
        case openDocument
    }

    private enum FileTypes {
        static let allowed: [UTType] = {
            guard let bms = UTType(filenameExtension: "bms", conformingTo: .text),
                  let bme = UTType(filenameExtension: "bme", conformingTo: .text),
                  let bml = UTType(filenameExtension: "bml", conformingTo: .text),
                  let pms = UTType(filenameExtension: "pms", conformingTo: .text),
                  let txt = UTType(filenameExtension: "txt", conformingTo: .plainText) else {
                preconditionFailure("Unable to create BMS document content types")
            }
            return [bms, bme, bml, pms, txt]
        }()

        static let sm: [UTType] = {
            [UTType(filenameExtension: "sm") ?? .plainText]
        }()

        static let ibmsc: [UTType] = {
            [UTType(filenameExtension: "ibmsc") ?? .data]
        }()

        static let bmson: [UTType] = {
            [UTType(filenameExtension: "bmson") ?? .json]
        }()

        static var openTypes: [UTType] { allowed + bmson }

        static let sound: [UTType] = {
            var types: [UTType] = [.wav, .mp3]
            if let ogg = UTType(filenameExtension: "ogg") {
                types.append(ogg)
            }
            return types
        }()
    }

    private let state: ApplicationState
    private let playFromBeginningHandler: () -> Void
    private let playFromHereHandler: () -> Void
    private let stopPreviewHandler: () -> Void
    private let content: MainWindowContentView
    private var session: DocumentSession?
    /// BMSON 文档。和 `session` 互斥，不套进 BMS。
    private var bmsonDocument: BmsONEDocument?
    /// 对照 `MainWindow::viewMode`。只改画面，不写 `info.modeHint`。
    private var bmsonViewMode = BmsONEViewMode.resolve("beat-7k")
    /// 对照 `SequenceView::channelLaneMode`。只改打开的 BMSON 的声道列。
    private var bmsonSoundLaneMode = BmsONESoundChannelLaneMode.load()
    private var lastBmsonChannelKeyword = ""
    /// `ChannelFindTools::FiltersActive`，默认关。
    private var bmsonFindActiveChannelsOnly = false
    /// `ChannelFindTools::HidesOthers`，默认关。原版工具栏藏起时会关掉；这里没有那条工具栏。
    private var bmsonFindHideOthers = false
    private var lastShownBmsonChannels: [Bool] = []
    /// 对照 `WaveSummary`。按谱目录加文件名缓存，滚动时不重新解码。
    private var bmsonWaveSummaries: [String: BmsonChannel.WaveSummary] = [:]
    /// 对照 Channel Info 总图。和摘要同一把钥匙，解码一次两份都有。
    private var bmsonOverallWaveforms: [String: BmsonOverallWaveform.Payload] = [:]
    /// 声道列 RMS 格。和摘要同一把钥匙。
    private var bmsonLaneRms: [String: [BmsonLaneWaveform.Entry]] = [:]
    private var bmsonWaveSummaryDocument: String?
    private var masterWaveform: BmsONEMasterWaveformCache?
    private var masterWaveformKey = ""
    /// IBMSC 文件里的 100 槽撤销。导入后还在、会话没有补丁时用它。
    private var ibmscSnapshot: IBMSCDocument?
    private lazy var timingWindowController = TimingWindowController()
    private lazy var findWindowController = FindWindowController()
    private lazy var statisticsWindowController = StatisticsWindowController()
    private lazy var visualOptionsWindowController = VisualOptionsWindowController()
    private lazy var generalOptionsWindowController = GeneralOptionsWindowController()
    private lazy var playerOptionsWindowController = PlayerOptionsWindowController()
    private lazy var aboutWindowController = AboutWindowController()
    private lazy var importSMWindowController = ImportSMWindowController()
    private lazy var myO2WindowController = MyO2WindowController()
    private lazy var loadProgressWindowController = LoadProgressWindowController()
    private let bmsonImportDialog = BmsONEImportWindowController()
    private let bmsonExportWavDialog = BmsONEExportWavWindowController()
    private let bmsonConvertResolutionDialog = BmsONEConvertResolutionWindowController()
    private let bmsonGridSettingDialog = BmsONEGridSettingWindowController()
    private let bmsonPreferencesDialog = BmsONEPreferencesWindowController()
    private let bmsonExternalViewerDialog = BmsONEExternalViewerWindowController()
    private var externalViewerTempPath: String?
    /// Last BMS folder, matching `InitPath` after open / save.
    private var lastBmsInitPath: String?
    private let editorSettingsStore = EditorSettingsStore()
    private var autoSaveTimer: Timer?
    private var previousAutoSavedFileName: URL?
    private var recoveredAutoSaveFiles: [URL] = []
    private var importedDocumentTitle: String?
    private lazy var editorThemeController = EditorThemeController(
        apply: { [weak self] theme in self?.content.applyChartTheme(theme) },
        sheetParent: { [weak self] in self?.window },
        beginSheet: { [weak self] in self?.beginSheet() ?? false },
        endSheet: { [weak self] in self?.finishSheet() },
        beepWhileSaved: { [weak self] in self?.editorSettingsStore.settings.beepWhileSaved ?? true }
    )
    private var isPresentingSheet = false
    private var queuedErrors: [Error] = []
    private var allowWindowClose = false
    private var skipNextTerminationPrompt = false
    private var terminationReplyPending = false
    /// `NSWorkspace.willPowerOffNotification`：能明确判断是关机 / 注销时才换 `SaveOnExit1`。
    private var systemIsPoweringOff = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var recentSlots = LegacyRecent.load()

    init(
        state: ApplicationState,
        showPreview: @escaping () -> Void,
        hidePreview: @escaping () -> Void,
        playFromBeginning: @escaping () -> Void,
        playFromHere: @escaping () -> Void,
        stopPreview: @escaping () -> Void
    ) {
        self.state = state
        playFromBeginningHandler = playFromBeginning
        playFromHereHandler = playFromHere
        stopPreviewHandler = stopPreview
        content = MainWindowContentView(state: state)
        let clientSize = NSSize(width: 1082, height: 730)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: clientSize), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = MainWindowChrome.windowTitle(fileName: "", isSaved: true)
        window.setContentSize(clientSize)
        // The chart controls and fixed metadata sidebar fit without clipping at
        // the initial width; do not permit a narrower content layout.
        window.minSize = NSSize(width: clientSize.width, height: 600)
        window.center()
        window.contentView = content
        super.init(window: window)
        // Start in the same clean empty-document state as File → New.
        // Open/restore flows replace this session later; this does not touch them.
        session = try? DocumentSession(data: Data())
        window.delegate = self
        let powerOff = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.systemIsPoweringOff = true
            }
        }
        workspaceObservers.append(powerOff)
        bmsonPreferencesDialog.onConfigureViewers = { [weak self] in
            self?.bmsonExternalViewerDialog.present()
        }
        content.installActions(
            isBusy: { [weak self] in self?.isPresentingSheet ?? true },
            newDocument: { [weak self] in self?.newDocument(nil) },
            openDocument: { [weak self] in self?.openDocument(nil) },
            saveDocument: { [weak self] in self?.saveDocument(nil) },
            saveDocumentAs: { [weak self] in self?.saveDocumentAs(nil) },
            undo: { [weak self] in self?.undoDocument(nil) },
            redo: { [weak self] in self?.redoDocument(nil) },
            showPreview: { [weak self] in
                guard let self, !self.isPresentingSheet else { return }
                showPreview()
            },
            setMetadata: { [weak self] key, value in self?.setMetadata(key: key, value: value) ?? false },
            selectEncoding: { [weak self] encoding in self?.selectEncoding(encoding) ?? false },
            setInitialBPM: { [weak self] decimal in self?.setHeaderBPM(decimal) ?? false },
            writeNote: { [weak self] channel, measure, slot, division, token, continueFlag in
                self?.writeNote(
                    channel: channel,
                    measure: measure,
                    slot: slot,
                    division: division,
                    token: token,
                    continueFlag: continueFlag
                ) ?? false
            },
            writeTiming: { [weak self] channel, measure, slot, division in self?.writeTiming(channel: channel, measure: measure, slot: slot, division: division) ?? false },
            moveNote: { [weak self] event, channel, measure, slot, division in self?.moveNote(event, channel: channel, measure: measure, slot: slot, division: division) ?? false },
            convertNote: { [weak self] event, channel in self?.convertNote(event, to: channel) ?? false },
            eraseNote: { [weak self] event in self?.eraseNote(event) ?? false },
            insertLongNote: { [weak self] channel, startMeasure, startSlot, endMeasure, endSlot, division, token, endToken, continueFlag in
                self?.insertLongNote(
                    channel: channel,
                    startMeasure: startMeasure,
                    startSlot: startSlot,
                    endMeasure: endMeasure,
                    endSlot: endSlot,
                    division: division,
                    token: token,
                    endToken: endToken,
                    continueFlag: continueFlag
                ) ?? false
            },
            moveLongNote: { [weak self] note, channel, measure, slot, division in
                self?.moveLongNote(note, channel: channel, measure: measure, slot: slot, division: division) ?? false
            },
            moveLongNoteStart: { [weak self] note, measure, slot, division in
                self?.moveLongNoteStart(note, measure: measure, slot: slot, division: division) ?? false
            },
            resizeLongNote: { [weak self] note, measure, slot, division in
                self?.resizeLongNote(note, measure: measure, slot: slot, division: division) ?? false
            },
            eraseLongNote: { [weak self] note in self?.eraseLongNote(note) ?? false },
            convertLongNoteToShort: { [weak self] note, keepEnd in self?.convertLongNoteToShort(note, keepEnd: keepEnd) ?? false },
            convertShortNotesToLong: { [weak self] start, end in self?.convertShortNotesToLong(start, end: end) ?? false },
            convertShortNoteToLongEndpoint: { [weak self] event in self?.convertShortNoteToLongEndpoint(event) ?? false },
            convertLongEndpointToShort: { [weak self] event in self?.convertLongEndpointToShort(event) ?? false },
            showFind: { [weak self] in self?.showFind(nil) },
            showStatistics: { [weak self] in self?.showStatistics(nil) },
            showVisualOptions: { [weak self] in self?.showVisualOptions(nil) },
            showGeneralOptions: { [weak self] in self?.showGeneralOptions(nil) },
            showPlayerOptions: { [weak self] in self?.showPlayerOptions(nil) },
            importSM: { [weak self] in self?.importSM(nil) },
            importIBMSC: { [weak self] in self?.importIBMSC(nil) },
            exportIBMSC: { [weak self] in self?.exportIBMSC(nil) },
            showMyO2: { [weak self] in self?.showMyO2(nil) },
            hidePreview: hidePreview,
            refresh: { [weak self] in self?.refreshWindow() }
        )
        content.setOpenRecent { [weak self] index in
            self?.openRecentSlot(index)
        }
        content.setPreviewPlayback(
            fromBeginning: { [weak self] in self?.playFromBeginning(nil) },
            fromHere: { [weak self] in self?.playFromHere(nil) },
            stop: { [weak self] in self?.stopPreview(nil) }
        )
        content.applyRecentSlots(recentSlots)
        content.openDroppedURLs = { [weak self] urls in
            self?.openDroppedURLs(urls)
        }
        content.onChartSelectionChange = { [weak self] in
            self?.refreshSelectedObjects()
        }
        content.onBmsonVisibleRangeChange = { [weak self] in
            self?.refreshBmsonHideOthersIfNeeded()
        }
        content.onBmsonChannelInfoNeeded = { [weak self] in
            self?.refreshBmsonChannelInfo()
        }
        content.onBmsonFooterSelect = { [weak self] index in
            self?.syncBmsonChannelSelection(index)
            self?.refreshWindow(waveformInputMayHaveChanged: false)
        }
        content.onBmsonFooterPreview = { [weak self] index in
            self?.previewBmsonFooterChannel(index)
        }
        content.onBmsonFooterHeight = { height in
            BmsONEFooter.save(height)
        }
        content.onBmsonFooterMenu = { [weak self] _, point in
            self?.showBmsonFooterChannelMenu(at: point)
        }
        content.onBmsonPlayingFooterMenu = { [weak self] point in
            self?.showBmsonSkinPropertyMenu(at: point)
        }
        content.setBmsonFooterHeight(BmsONEFooter.load())
        content.onSelectedNoteLengthCommit = { [weak self] text in
            self?.commitSelectedBmsonLength(text) ?? false
        }
        content.onSelectedNoteExtraCommit = { [weak self] text in
            self?.commitSelectedBmsonExtra(text) ?? false
        }
        content.onInfoExtraCommit = { [weak self] text in
            self?.commitBmsonInfoExtra(text) ?? false
        }
        content.bindBmsonPulseWrites(
            writeNote: { [weak self] channel, pulse, token, continueFlag in
                self?.writeNote(channel: channel, pulseY: pulse, token: token, continueFlag: continueFlag) ?? false
            },
            writeTiming: { [weak self] channel, pulse in
                self?.writeBmsonTiming(channel: channel, pulseY: pulse) ?? false
            },
            moveNote: { [weak self] event, channel, pulse in
                self?.moveNote(event, channel: channel, pulseY: pulse) ?? false
            },
            insertLong: { [weak self] channel, start, end, token, continueFlag in
                self?.insertLongNote(
                    channel: channel,
                    startPulse: start,
                    endPulse: end,
                    token: token,
                    continueFlag: continueFlag
                ) ?? false
            },
            moveLong: { [weak self] note, channel, pulse in
                self?.moveLongNote(note, channel: channel, pulseY: pulse) ?? false
            },
            moveLongStart: { [weak self] note, pulse in
                self?.moveLongNoteStart(note, pulseY: pulse) ?? false
            },
            resizeLong: { [weak self] note, pulse in
                self?.resizeLongNote(note, pulseY: pulse) ?? false
            }
        )
        content.bindBmsonSoundChannelLane { [weak self] index in
            self?.activateBmsonSoundChannelLane(index) ?? true
        }
        myO2WindowController.currentBPM = { [weak self] in
            Double(self?.session?.timingSnapshot.initialBPMDecimal ?? "") ?? MyO2Layout.defaultBPM
        }
        myO2WindowController.notes = { [weak self] in self?.currentMyO2Notes() ?? [] }
        myO2WindowController.ntInput = { [weak self] in self?.content.ntInputEnabled ?? true }
        myO2WindowController.gridLimit = { [weak self] in
            let partition = self?.editorSettingsStore.settings.gridPartition ?? 192
            return 192.0 / Double(max(1, partition))
        }
        myO2WindowController.applyNotes = { [weak self] notes in self?.applyMyO2Notes(notes) }
        content.onTimeSelectionCommand { [weak self] command in
            self?.performTimeSelection(command)
        }
        content.onEditBmsonBarLine { [weak self] beat, remove in
            self?.editBmsonBarLine(beat: beat, remove: remove) ?? false
        }
        content.onPasteClipboard { [weak self] text, baseVPosition, ntInput in
            self?.pasteClipboard(text, baseVPosition: baseVPosition, ntInput: ntInput) ?? false
        }
        content.onEraseSelection { [weak self] events, longNotes in
            self?.eraseSelection(events: events, longNotes: longNotes) ?? false
        }
        content.onToggleNTInput { [weak self] becomeNT in
            self?.toggleNTInput(becomeNT)
        }
        content.onCopyNoteAtVPosition { [weak self] event, channel, vPosition in
            self?.copyNoteAtVPosition(event, channel: channel, vPosition: vPosition) ?? false
        }
        content.onCopyLongNoteAtVPosition { [weak self] note, channel, vPosition, length in
            self?.copyLongNoteAtVPosition(note, channel: channel, vPosition: vPosition, length: length) ?? false
        }
        content.onCopyNotesAtVPosition { [weak self] shorts, longs in
            self?.copyNotesAtVPosition(shorts: shorts, longs: longs) ?? false
        }
        content.onMoveNotesAtVPosition { [weak self] shorts, longs in
            self?.moveNotesAtVPosition(shorts: shorts, longs: longs) ?? false
        }
        content.onMirrorSelected { [weak self] in
            self?.mirrorSelectedNotes()
        }
        content.onMoveSelectedToColumn { [weak self] display, shiftFirstOnly in
            self?.moveSelectedNotes(toDisplay: display, shiftFirstOnly: shiftFirstOnly) ?? false
        }
        content.onMoveSelectedToBGM { [weak self] in
            self?.moveSelectedNotesToBGM() ?? false
        }
        content.onModifySelected { [weak self] in
            self?.modifySelectedNotes()
        }
        content.onDoubleClickNote { [weak self] event in
            self?.doubleClickNote(event)
        }
        content.onDoubleClickLongNote { [weak self] note in
            self?.doubleClickLongNote(note)
        }
        content.onApplyWavEdit { [weak self] edit, synchronize in
            self?.applyWavEdit(edit, synchronizeLabels: synchronize) ?? false
        }
        content.onApplyBmpEdit { [weak self] edit, synchronize in
            self?.applyBmpEdit(edit, synchronizeLabels: synchronize) ?? false
        }
        content.onApplyWaveformColor { [weak self] color in
            self?.applyWaveformColor(color)
        }
        content.onApplyBeat { [weak self] measures, decimal, mode in
            self?.applyBeat(measures: measures, decimal: decimal, mode: mode) ?? false
        }
        content.onApplyExpansion { [weak self] text in
            self?.applyExpansion(text) ?? false
        }
        content.onPreviewNote { [weak self] token in
            self?.previewNote(token: token)
        }
        configureTimingActions()
        configureFindActions()
        _ = editorThemeController
        content.setThemeMenu(editorThemeController.menu)
        content.setLanguageMenu(languageMenu)
        content.setLanguageActions(
            reset: { [weak self] in self?.resetLanguagePreference() },
            refresh: { [weak self] in self?.refreshLanguageMenu(alertErrors: true) },
            load: { [weak self] path in self?.loadLanguage(path: path, remember: true) }
        )
        fillLanguageMenu(listings: [])
        content.applyEditorSettings(editorSettingsStore.settings)
        applyIndexedTimingRadix(editorSettingsStore.settings)
        scheduleAutoSave(editorSettingsStore.settings.autoSaveMilliseconds)
        rebuildEncodingMenu()
        refreshWindow()
    }

    required init?(coder: NSCoder) { nil }

    /// The current document bytes (with unsaved edits) and its file location,
    /// for consumers such as the built-in preview. Returns nil when no document
    /// is open or the bytes cannot be produced.
    func currentDocumentBytes() -> (data: Data, fileURL: URL?)? {
        guard let session, let data = try? session.currentBytes() else { return nil }
        return (data, session.fileURL)
    }

    func setPreviewPlayheadBeat(_ beat: Double?) {
        content.setPreviewPlayheadBeat(beat)
    }

    /// 内置预听用的谱面字节、目录、音符和速度。Play Here 用鼠标所在拍。
    func previewAudioContext() -> PreviewAudioDocumentContext? {
        if let bmsonDocument {
            return bmsonPreviewContext(bmsonDocument)
        }
        guard let (data, fileURL) = currentDocumentBytes() else { return nil }
        let timingSnapshot = session?.timingSnapshot ?? .unavailable
        let headerBPM = Double(timingSnapshot.initialBPMDecimal) ?? 120
        var bpmEvents: [(beat: Double, bpm: Double)] = []
        var stopEvents: [(beat: Double, durationSeconds: Double)] = []
        if timingSnapshot.available {
            for event in timingSnapshot.events {
                let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
                switch event.kind {
                case .bpm:
                    if let bpm = Double(event.valueDecimal), bpm > 0 {
                        bpmEvents.append((beat, bpm))
                    }
                case .stop:
                    guard event.hasTime else { continue }
                    let duration = event.secondsAfterStop - event.secondsBeforeStop
                    if duration > 0 {
                        stopEvents.append((beat, duration))
                    }
                }
            }
        }
        var notes: [PreviewAudioNote] = []
        let pairedLines = Set((session?.longNoteSnapshot.notes ?? []).flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        for event in session?.chartSnapshot.events ?? [] {
            if pairedLines.contains(event.sourceLine) { continue }
            guard LegacyPreviewAudio.isAudibleChannel(event.channel) else { continue }
            notes.append(PreviewAudioNote(beat: event.beat, wavToken: event.token))
        }
        for longNote in session?.longNoteSnapshot.notes ?? [] {
            guard LegacyPreviewAudio.isAudibleChannel(longNote.channel) else { continue }
            notes.append(PreviewAudioNote(beat: longNote.start.beat, wavToken: longNote.start.token))
        }
        return PreviewAudioDocumentContext(
            documentData: data,
            chartDirectory: fileURL?.deletingLastPathComponent(),
            notes: notes,
            timing: PreviewAudioTiming(headerBPM: headerBPM, bpmEvents: bpmEvents, stopEvents: stopEvents),
            playHereBeat: content.lastPointerBeat
        )
    }

    /// 原版 `PreviewNote`：按 `#WAVxx` 文件名拼谱面目录再播。
    func previewNote(token: String) {
        if let bmsonDocument {
            let table = LegacyBmsonPreview.wavTable(channelNames: bmsonDocument.soundChannels.map(\.name))
            guard let name = LegacyBmsonPreview.previewFileName(token: token, table: table) else { return }
            let directory = bmsonDocument.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            guard let url = LegacyPreviewAudio.resolveAudioURL(fileName: name, chartDirectory: directory) else {
                return
            }
            let prefs = BmsONEPreferences.load()
            state.previewPlayer.playFile(
                url: url,
                maxDurationSeconds: prefs.singleMaxDuration,
                fadeOutSeconds: BmsONEPreviewTiming.fadeOutSeconds(soft: prefs.singleSoftFadeOut)
            )
            return
        }
        guard let (data, fileURL) = currentDocumentBytes() else { return }
        let table = LegacyPreviewAudio.parseWavTable(from: data)
        guard let name = LegacyPreviewAudio.fileName(forToken: token, in: table),
              let url = LegacyPreviewAudio.resolveAudioURL(
                fileName: name,
                chartDirectory: fileURL?.deletingLastPathComponent()
              )
        else { return }
        state.previewPlayer.playFile(url: url)
    }

    private func bmsonPreviewContext(_ document: BmsONEDocument) -> PreviewAudioDocumentContext {
        LegacyBmsonPreview.context(
            channelNames: document.soundChannels.map(\.name),
            channels: document.soundChannels.map { channel in
                (
                    name: channel.name,
                    notes: channel.notes.map {
                        LegacyBmsonPreview.SoundNote(y: $0.y, continueFlag: $0.c)
                    }
                )
            },
            initBpm: document.initialBpm,
            bpmNotes: document.bpmNotes.map { ($0.y, $0.v) },
            resolution: document.resolution,
            chartDirectory: document.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() },
            playHereBeat: content.lastPointerBeat,
            stopNotes: document.stopNotes.map { ($0.y, $0.v) }
        )
    }

    func previewNote(url: URL) {
        state.previewPlayer.playFile(url: url)
    }

    var themeMenu: NSMenu { editorThemeController.menu }
    let languageMenu = NSMenu(title: "Language")
    let encodingMenu = NSMenu(title: "Encoding")
    private var currentLocalePack: LegacyLocalePack?
    private var currentRuntime = LegacyLocale.RuntimeStrings.designer

    @objc func newDocument(_ sender: Any?) {
        requestTransition(.newDocument)
    }

    @objc func openDocument(_ sender: Any?) {
        requestTransition(.openDocument)
    }

    @objc func performChromeCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        switch LegacyChromeMenu.previewCommand(toolbar: command) {
        case .playFromBeginning:
            playFromBeginning(sender)
        case .playFromHere:
            playFromHere(sender)
        case .stop:
            stopPreview(sender)
        case nil:
            content.performChromeCommand(command)
        }
    }

    @objc func playFromBeginning(_ sender: Any?) {
        guard !isPresentingSheet else { return }
        playFromBeginningHandler()
    }

    @objc func playFromHere(_ sender: Any?) {
        guard !isPresentingSheet else { return }
        playFromHereHandler()
    }

    @objc func stopPreview(_ sender: Any?) {
        guard !isPresentingSheet else { return }
        stopPreviewHandler()
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        openRecentSlot(sender.tag)
    }

    func applyRecentMenus() {
        let noneWord = currentLocalePack.flatMap { LegacyLocale.text($0, path: "None") } ?? LegacyRecent.noneWord
        content.applyRecentSlots(recentSlots, noneWord: noneWord)
        guard let fileMenu = MenuBuilder.menuItem(in: NSApp.mainMenu, id: LegacyLocale.ID.file)?.submenu else { return }
        for item in fileMenu.items where item.action == #selector(openRecent(_:)) {
            let path = recentSlots.indices.contains(item.tag) ? recentSlots[item.tag] : ""
            item.title = LegacyRecent.menuTitle(path, noneWord: noneWord)
            item.toolTip = LegacyRecent.tooltip(path)
            item.isEnabled = LegacyRecent.isEnabled(path)
        }
    }

    /// `Form_Load` 会先 Refresh，再按保存的 `DispLang` 加载。
    func installLanguageSupport() {
        content.setLanguageMenu(languageMenu)
        refreshLanguageMenu(alertErrors: false)
        applySavedLanguage()
    }

    /// `TBLangRefresh_Click`：重扫 `Data/*.Lang.xml`。启动时不弹解析错误。
    func refreshLanguageMenu(alertErrors: Bool) {
        let scan: LegacyLocaleScan
        if let directory = LegacyLocale.bundledDataDirectory() {
            scan = LegacyLocale.scan(directory: directory)
        } else {
            scan = LegacyLocaleScan(listings: [], errors: [])
        }
        fillLanguageMenu(listings: scan.listings)
        guard alertErrors else { return }
        for message in scan.errors {
            presentLocaleAlert(message)
        }
    }

    /// `TBLangDef_Click`：只清 `DispLang` 并提示下次启动生效，不立刻改回英文。
    func resetLanguagePreference() {
        LegacyLocale.saveRelativeName("")
        let message = currentLocalePack.flatMap { LegacyLocale.text($0, path: "Messages/PreferencePostpone") }
            ?? LegacyLocale.defaultPostpone
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: currentLocalePack.flatMap { LegacyLocale.text($0, path: "OK") } ?? "OK")
        alert.runModal()
    }

    func loadLanguage(path: String, remember: Bool) {
        do {
            let pack = try LegacyLocale.parse(url: URL(fileURLWithPath: path))
            currentLocalePack = pack
            if remember {
                LegacyLocale.saveRelativeName(LegacyLocale.relativeName(path: path))
            }
            if let menu = NSApp.mainMenu {
                MenuBuilder.applyLocale(pack, to: menu)
            }
            applyRecentMenus()
            applyRuntimeLocale(LegacyLocale.runtime(pack))
        } catch {
            presentLocaleAlert("\(path)\n\n\(error.localizedDescription)")
        }
    }

    private func applySavedLanguage() {
        let relative = LegacyLocale.savedRelativeName()
        guard !relative.isEmpty, let directory = LegacyLocale.bundledDataDirectory() else { return }
        let url = LegacyLocale.resolve(relative: relative, dataDirectory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        loadLanguage(path: url.path, remember: false)
    }

    private func fillLanguageMenu(listings: [LegacyLocaleListing]) {
        languageMenu.removeAllItems()
        let chinese = languageMenu.addItem(
            withTitle: NativeLocalization.text("Simplified Chinese"),
            action: #selector(useSimplifiedChinese(_:)),
            keyEquivalent: ""
        )
        chinese.target = self
        chinese.state = NativeLocalization.language == .chineseSimplified ? .on : .off
        let english = languageMenu.addItem(
            withTitle: "English",
            action: #selector(useEnglish(_:)),
            keyEquivalent: ""
        )
        english.target = self
        english.state = NativeLocalization.language == .english ? .on : .off
        languageMenu.addItem(.separator())
        for entry in LegacyLocale.languageMenuEntries(listings: listings) {
            switch entry {
            case .separator:
                languageMenu.addItem(.separator())
            case .item(let title, let command, let tooltip):
                let item = languageMenu.addItem(
                    withTitle: title,
                    action: #selector(performChromeCommand(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = command
                if !tooltip.isEmpty {
                    item.toolTip = tooltip
                }
            }
        }
    }

    @objc private func useSimplifiedChinese(_ sender: Any?) {
        NativeLocalization.useChineseSimplified()
        LegacyLocale.saveRelativeName("")
        currentLocalePack = nil
        currentRuntime = .designer
        NativeLocalization.refreshVisibleInterface()
        refreshLanguageMenu(alertErrors: false)
    }

    @objc private func useEnglish(_ sender: Any?) {
        NativeLocalization.useEnglish()
        LegacyLocale.saveRelativeName("")
        currentLocalePack = nil
        currentRuntime = .designer
        NativeLocalization.refreshVisibleInterface()
        refreshLanguageMenu(alertErrors: false)
    }

    private func presentLocaleAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: currentLocalePack.flatMap { LegacyLocale.text($0, path: "OK") } ?? "OK")
        alert.runModal()
    }

    @objc func saveDocument(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        saveCurrentDocument(forceSaveAs: false) { _ in }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        saveCurrentDocument(forceSaveAs: true) { _ in }
    }

    @objc func undoDocument(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        if let bmsonDocument {
            guard bmsonDocument.undo() else { return }
            refreshWindow()
            return
        }
        if applyIBMSCUndo(redo: false) {
            refreshWindow()
            return
        }
        guard let session else { return }
        do {
            guard try session.undo() else { return }
            refreshWindow()
        } catch {
            presentErrorSheet(error)
        }
    }

    @objc func redoDocument(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        if let bmsonDocument {
            guard bmsonDocument.redo() else { return }
            refreshWindow()
            return
        }
        if applyIBMSCUndo(redo: true) {
            refreshWindow()
            return
        }
        guard let session else { return }
        do {
            guard try session.redo() else { return }
            refreshWindow()
        } catch {
            presentErrorSheet(error)
        }
    }

    @objc func setChartSide(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let side = ChartSide(rawValue: raw) else { return }
        content.setChartSide(side)
    }

    @objc func selectTimeTool(_ sender: Any?) {
        content.setChartTool(.timeSelect)
    }

    @objc func selectSelectTool(_ sender: Any?) {
        content.setChartTool(.select)
    }

    @objc func selectWriteTool(_ sender: Any?) {
        content.setChartTool(.write)
    }

    @objc func toggleGrid(_ sender: Any?) {
        content.setGridVisibility(showGrid: !content.gridVisible)
    }

    @objc func toggleSubGrid(_ sender: Any?) {
        content.setGridVisibility(showSubGrid: !content.subGridVisible)
    }

    @objc func toggleMeasureLine(_ sender: Any?) {
        content.setGridVisibility(showMeasureBar: !content.measureBarVisible)
    }

    @objc func toggleBackground(_ sender: Any?) {
        content.setGridVisibility(showBackground: !content.backgroundVisible)
    }

    @objc func toggleMeasureIndex(_ sender: Any?) {
        content.setGridVisibility(showMeasureNumber: !content.measureNumberVisible)
    }

    @objc func toggleVerticalLine(_ sender: Any?) {
        content.setGridVisibility(showVerticalLine: !content.verticalLineVisible)
    }

    @objc func toggleColumnCaption(_ sender: Any?) {
        content.setGridVisibility(showColumnCaption: !content.columnCaptionVisible)
    }

    @objc func toggleToolBar(_ sender: Any?) {
        content.setToolBarVisible(!content.toolBarVisible)
    }

    @objc func toggleOptionsPanel(_ sender: Any?) {
        content.setOptionsVisible(!content.optionsVisible)
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        content.setStatusVisible(!content.statusVisible)
    }

    @objc func toggleScrollColumn(_ sender: Any?) {
        content.setColumnVisibility(scroll: !content.scrollColumnVisible)
    }

    @objc func toggleBPMColumn(_ sender: Any?) {
        content.setColumnVisibility(bpm: !content.bpmColumnVisible)
    }

    @objc func toggleStopColumn(_ sender: Any?) {
        content.setColumnVisibility(stop: !content.stopColumnVisible)
    }

    @objc func toggleBGAColumns(_ sender: Any?) {
        content.setColumnVisibility(bga: !content.bgaColumnsVisible)
    }

    @objc func toggleLeftSplitter(_ sender: Any?) {
        content.setLeftSplitterVisible(!content.leftSplitterVisible)
    }

    @objc func toggleRightSplitter(_ sender: Any?) {
        content.setRightSplitterVisible(!content.rightSplitterVisible)
    }

    @objc func showTiming(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        updateTimingWindow()
        timingWindowController.showWindow(self)
        timingWindowController.window?.makeKeyAndOrderFront(self)
    }

    @objc func showAbout(_ sender: Any?) {
        aboutWindowController.present()
    }

    @objc func importSM(_ sender: Any?) {
        requestImport { [weak self] in self?.presentSMOpenPanel() }
    }

    @objc func importIBMSC(_ sender: Any?) {
        requestImport { [weak self] in self?.presentIBMSCOpenPanel() }
    }

    @objc func importBmsAsBmson(_ sender: Any?) {
        requestImport { [weak self] in self?.presentBmsAsBmsonOpenPanel() }
    }

    @objc func exportBmsonWav(_ sender: Any?) {
        guard !isPresentingSheet, let bmsonDocument else { return }
        bmsonExportWavDialog.present(document: bmsonDocument)
    }

    @objc func convertBmsonResolution(_ sender: Any?) {
        guard !isPresentingSheet, let bmsonDocument else { return }
        if bmsonConvertResolutionDialog.present(document: bmsonDocument) {
            refreshWindow()
        }
    }

    @objc func clearBmsonMasterCache(_ sender: Any?) {
        guard bmsonDocument != nil, BmsONEPreferences.load().enableMasterChannel else { return }
        refreshMasterWaveform(force: true)
    }

    @objc func showBmsonPreferences(_ sender: Any?) {
        guard !isPresentingSheet else { return }
        bmsonPreferencesDialog.present()
        refreshMasterWaveform(force: true)
        if let document = bmsonDocument {
            content.pushBmsonSnap(
                applies: true,
                resolution: document.resolution,
                bars: BmsonChartAdapter.barPulses(from: document)
            )
        }
    }

    @objc func showExternalViewerConfig(_ sender: Any?) {
        guard !isPresentingSheet else { return }
        bmsonExternalViewerDialog.present()
    }

    @objc func playExternalViewerFromBeginning(_ sender: Any?) {
        runExternalViewer(kind: .beginning)
    }

    @objc func playExternalViewerFromHere(_ sender: Any?) {
        runExternalViewer(kind: .here)
    }

    @objc func stopExternalViewer(_ sender: Any?) {
        runExternalViewer(kind: .stop)
    }

    @objc func showBmsonAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = BmsONEAbout.appName
        alert.informativeText = BmsONEAbout.informativeText
        alert.alertStyle = .informational
        alert.window.title = BmsONEAbout.title
        alert.runModal()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == BmsONEScratch.menuTitle {
            rebuildScratchMenu(menu)
            return
        }
        if menu.title == BmsONELaneOrder.menuTitle {
            rebuildLaneOrderMenu(menu)
            return
        }
        if menu.title == BmsONEColorScheme.menuTitle {
            rebuildColorSchemeMenu(menu)
            return
        }
        if menu.title == BmsONEWheel.menuTitle {
            rebuildWheelMenu(menu)
            return
        }
        guard menu.title == BmsONEDialogLayout.externalViewerMenuTitle else { return }
        menu.removeAllItems()
        let store = BmsONEExternalViewerStore.load()
        if store.viewers.isEmpty {
            let empty = menu.addItem(withTitle: "<None>", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return
        }
        for (index, viewer) in store.viewers.enumerated() {
            let item = menu.addItem(
                withTitle: viewer.displayName,
                action: #selector(selectExternalViewer(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = index == store.currentIndex ? .on : .off
        }
    }

    private func rebuildScratchMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let kind = bmsonViewMode.kind
        let current = BmsONEScratch.load(kind: kind)
        for choice in BmsONEScratch.choices(for: kind) {
            let item = menu.addItem(
                withTitle: choice.title,
                action: #selector(selectBmsonScratch(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice.stored
            item.state = choice.stored == current?.stored ? .on : .off
        }
        if menu.items.isEmpty {
            let empty = menu.addItem(withTitle: "<None>", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
    }

    @objc func selectBmsonScratch(_ sender: NSMenuItem) {
        guard bmsonDocument != nil,
              let stored = sender.representedObject as? String,
              BmsONEScratch.parse(stored, kind: bmsonViewMode.kind)?.stored == stored
        else { return }
        BmsONEScratch.save(stored, kind: bmsonViewMode.kind)
        refreshWindow()
    }

    private func currentBmsonKeyLanes() -> [Int64] {
        if let count = BmsONEPlainLanes.load(kind: bmsonViewMode.kind) {
            return BmsONEPlainLanes.keyLanes(count: count)
        }
        if let scratch = BmsONEScratch.load(kind: bmsonViewMode.kind) {
            return BmsONEScratch.keyLanes(kind: bmsonViewMode.kind, scratch: scratch)
        }
        if let order = BmsONELaneOrder.load(kind: bmsonViewMode.kind) {
            return BmsONELaneOrder.keyLanes(kind: bmsonViewMode.kind, order: order)
        }
        if let wheel = BmsONEWheel.load(kind: bmsonViewMode.kind) {
            return BmsONEWheel.keyLanes(kind: bmsonViewMode.kind, wheel: wheel)
        }
        return bmsonViewMode.keyLanes
    }

    private func rebuildLaneOrderMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let kind = bmsonViewMode.kind
        let current = BmsONELaneOrder.load(kind: kind)
        for choice in BmsONELaneOrder.choices(for: kind) {
            let item = menu.addItem(
                withTitle: choice.title,
                action: #selector(selectBmsonLaneOrder(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice.stored
            item.state = choice.stored == current?.stored ? .on : .off
        }
        if menu.items.isEmpty {
            let empty = menu.addItem(withTitle: "<None>", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
    }

    @objc func selectBmsonLaneOrder(_ sender: NSMenuItem) {
        guard bmsonDocument != nil,
              let stored = sender.representedObject as? String,
              BmsONELaneOrder.parse(stored, kind: bmsonViewMode.kind)?.stored == stored
        else { return }
        BmsONELaneOrder.save(stored, kind: bmsonViewMode.kind)
        refreshWindow()
    }

    private func showBmsonSkinPropertyMenu(at point: NSPoint) {
        guard bmsonDocument != nil, let window = window else { return }
        let kind = bmsonViewMode.kind
        let title: String
        if !BmsONEScratch.choices(for: kind).isEmpty {
            title = BmsONEScratch.menuTitle
        } else if !BmsONELaneOrder.choices(for: kind).isEmpty {
            title = BmsONELaneOrder.menuTitle
        } else if !BmsONEColorScheme.choices(for: kind).isEmpty {
            title = BmsONEColorScheme.menuTitle
        } else if !BmsONEWheel.choices(for: kind).isEmpty {
            title = BmsONEWheel.menuTitle
        } else if BmsONEPlainLanes.applies(to: kind) {
            title = BmsONEPlainLanes.menuTitle(
                count: BmsONEPlainLanes.load(kind: kind) ?? BmsONEPlainLanes.defaultCount
            )
        } else {
            return
        }
        let menu = NSMenu(title: title)
        if title == BmsONEScratch.menuTitle {
            rebuildScratchMenu(menu)
        } else if title == BmsONELaneOrder.menuTitle {
            rebuildLaneOrderMenu(menu)
        } else if title == BmsONEColorScheme.menuTitle {
            rebuildColorSchemeMenu(menu)
        } else if title == BmsONEWheel.menuTitle {
            rebuildWheelMenu(menu)
        } else {
            rebuildLaneCountMenu(menu)
        }
        menu.popUp(
            positioning: nil,
            at: window.contentView?.convert(point, from: nil) ?? point,
            in: window.contentView
        )
    }

    private func rebuildLaneCountMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        guard BmsONEPlainLanes.applies(to: bmsonViewMode.kind) else {
            let empty = menu.addItem(withTitle: "<None>", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return
        }
        let count = BmsONEPlainLanes.load(kind: .plain) ?? BmsONEPlainLanes.defaultCount
        let item = menu.addItem(
            withTitle: BmsONEPlainLanes.menuTitle(count: count),
            action: #selector(showBmsonLaneCount(_:)),
            keyEquivalent: ""
        )
        item.target = self
    }

    private func rebuildColorSchemeMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let kind = bmsonViewMode.kind
        let current = BmsONEColorScheme.load(kind: kind)
        for choice in BmsONEColorScheme.choices(for: kind) {
            let item = menu.addItem(
                withTitle: choice.title,
                action: #selector(selectBmsonColorScheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice.stored
            item.state = choice.stored == current?.stored ? .on : .off
        }
        if menu.items.isEmpty {
            let empty = menu.addItem(withTitle: "<None>", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
    }

    private func rebuildWheelMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let kind = bmsonViewMode.kind
        let current = BmsONEWheel.load(kind: kind)
        for choice in BmsONEWheel.choices(for: kind) {
            let item = menu.addItem(
                withTitle: choice.title,
                action: #selector(selectBmsonWheel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice.stored
            item.state = choice.stored == current?.stored ? .on : .off
        }
        if menu.items.isEmpty {
            let empty = menu.addItem(withTitle: "<None>", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
    }

    @objc func selectBmsonWheel(_ sender: NSMenuItem) {
        guard bmsonDocument != nil,
              let stored = sender.representedObject as? String,
              BmsONEWheel.parse(stored, kind: bmsonViewMode.kind)?.stored == stored
        else { return }
        BmsONEWheel.save(stored, kind: bmsonViewMode.kind)
        refreshWindow()
    }

    @objc func selectBmsonColorScheme(_ sender: NSMenuItem) {
        guard bmsonDocument != nil,
              let stored = sender.representedObject as? String,
              BmsONEColorScheme.parse(stored, kind: bmsonViewMode.kind)?.stored == stored
        else { return }
        BmsONEColorScheme.save(stored, kind: bmsonViewMode.kind)
        refreshWindow()
    }

    @objc func showBmsonLaneCount(_ sender: Any?) {
        guard bmsonDocument != nil, BmsONEPlainLanes.applies(to: bmsonViewMode.kind) else { return }
        let current = BmsONEPlainLanes.load(kind: .plain) ?? BmsONEPlainLanes.defaultCount
        let alert = NSAlert()
        alert.messageText = BmsONEPlainLanes.dialogLabel
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(current)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BmsONEPlainLanes.save(BmsONEPlainLanes.parse(field.stringValue), kind: .plain)
        refreshWindow()
    }

    @objc func selectExternalViewer(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        var store = BmsONEExternalViewerStore.load()
        store.setCurrentIndex(item.tag)
        store.store()
    }

    private func cleanExternalViewerTemp() {
        _ = BmsONEExternalViewer.cleanTempFile(externalViewerTempPath)
        externalViewerTempPath = nil
    }

    private func runExternalViewer(kind: BmsONEExternalViewerKind) {
        if session != nil {
            let mapped: LegacyExternalPlayerKind
            switch kind {
            case .beginning:
                mapped = .begin
            case .here:
                mapped = .here
            case .stop:
                mapped = .stop
            }
            runBmsExternalPlayer(kind: mapped)
            return
        }
        guard !isPresentingSheet, let document = bmsonDocument else { return }
        let store = BmsONEExternalViewerStore.load()
        let bars = BmsonChartAdapter.barPulses(from: document)
        let pulse: Int?
        if kind == .here {
            pulse = content.currentBmsonLocation(resolution: document.resolution, bars: bars)
        } else {
            pulse = nil
        }
        let json: String
        do {
            json = try document.jsonString()
        } catch {
            presentExternalViewerFailed()
            return
        }
        let (action, nextTemp) = BmsONEExternalViewer.plan(
            kind: kind,
            store: store,
            filePath: document.filePath,
            json: json,
            currentTempPath: externalViewerTempPath,
            pulse: pulse,
            bars: bars,
            initBpm: document.initialBpm,
            resolution: document.resolution,
            bpmNotes: document.bpmNotes.map { ($0.y, $0.v) }
        )
        externalViewerTempPath = nextTemp
        switch action {
        case .ignored:
            return
        case .failed:
            presentExternalViewerFailed()
        case .run(let launch):
            if !BmsONEExternalViewer.start(launch) {
                presentExternalViewerFailed()
            }
        }
    }

    private func presentExternalViewerFailed() {
        let alert = NSAlert()
        alert.messageText = BmsONEDialogLayout.externalViewerErrorTitle
        alert.informativeText = BmsONEDialogLayout.externalViewerFailed
        alert.alertStyle = .warning
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func runtimePlayerAppPath() -> String {
        let directory = LegacyAutoSave.directory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    private func runBmsExternalPlayer(kind: LegacyExternalPlayerKind) {
        guard !isPresentingSheet, let session else { return }
        let appPath = runtimePlayerAppPath()
        var settings = editorSettingsStore.settings
        guard var player = settings.currentPlayerArguments else { return }

        var program = LegacyExternalPlayer.programPath(player.path, appPath: appPath)
        if !FileManager.default.fileExists(atPath: program) {
            presentPlayerMissingPrompt(resolvedPath: program, appPath: appPath)
            settings = editorSettingsStore.settings
            guard let updated = settings.currentPlayerArguments else { return }
            player = updated
            program = LegacyExternalPlayer.programPath(player.path, appPath: appPath)
        }
        guard FileManager.default.fileExists(atPath: program) else { return }

        let named = session.fileURL?.path
        let fileName = LegacyExternalPlayer.pathIsValid(named) ? named : nil
        let tempPath = LegacyExternalPlayer.tempBMSPath(
            fileName: fileName,
            initPath: lastBmsInitPath,
            appPath: appPath
        )
        if LegacyExternalPlayer.writesTempFile(kind) {
            do {
                let data = try session.exportSaveBmsData(
                    ntInput: content.ntInputEnabled,
                    gridLimit: settings.bmsGridLimit
                )
                let encoded = LegacyExternalPlayer.encodedSaveData(
                    data,
                    encoding: session.metadataEncoding?.stringEncoding ?? .utf8
                )
                try encoded.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
            } catch {
                presentErrorSheet(error)
                return
            }
        }

        let measure = LegacyExternalPlayer.measureFromScroll(content.focusedPanelVScroll())
        let arguments = LegacyExternalPlayer.substitute(
            LegacyExternalPlayer.argumentTemplate(player, kind: kind),
            appPath: appPath,
            measure: measure,
            fileName: tempPath
        )
        let workingDirectory = URL(fileURLWithPath: tempPath).deletingLastPathComponent().path
        let launch = BmsONEExternalViewerLaunch(
            program: program,
            argument: arguments,
            workingDirectory: workingDirectory,
            command: "\(program) \(arguments)",
            tempFilePath: tempPath
        )
        _ = BmsONEExternalViewer.start(launch)
    }

    private func presentPlayerMissingPrompt(resolvedPath: String, appPath: String) {
        let alert = NSAlert()
        alert.messageText = LegacyExternalPlayer.missingTitle
        alert.informativeText = LegacyExternalPlayer.missingMessage(resolvedPath)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let folder = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            panel.directoryURL = folder
        } else {
            panel.directoryURL = URL(fileURLWithPath: appPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editorSettingsStore.updateCurrentPlayerPath(
            LegacyExternalPlayer.storePickedPath(picked: url.path, appPath: appPath)
        )
    }

    @objc func showBmsonGridSetting(_ sender: Any?) {
        guard !isPresentingSheet else { return }
        guard let result = bmsonGridSettingDialog.present(currentDivision: content.selectedDivision) else {
            return
        }
        content.applyBmsonGrid(result)
        if let document = bmsonDocument {
            content.pushBmsonSnap(
                applies: true,
                resolution: document.resolution,
                bars: BmsonChartAdapter.barPulses(from: document)
            )
        }
    }

    @objc func toggleBmsonSnapToGrid(_ sender: Any?) {
        content.setSnapEnabled(!content.snapEnabled)
    }

    @objc func zoomBmsonIn(_ sender: Any?) {
        guard bmsonDocument != nil else { return }
        content.zoomBmsonIn()
    }

    @objc func zoomBmsonOut(_ sender: Any?) {
        guard bmsonDocument != nil else { return }
        content.zoomBmsonOut()
    }

    @objc func zoomBmsonReset(_ sender: Any?) {
        guard bmsonDocument != nil else { return }
        content.zoomBmsonReset()
    }

    @objc func selectBmsonViewMode(_ sender: NSMenuItem) {
        guard bmsonDocument != nil, let hint = sender.representedObject as? String else { return }
        bmsonViewMode = BmsONEViewMode.resolve(hint)
        refreshWindow()
    }

    @objc func selectBmsonSoundChannelLaneMode(_ sender: NSMenuItem) {
        guard bmsonDocument != nil, let raw = sender.representedObject as? String else { return }
        bmsonSoundLaneMode = BmsONESoundChannelLaneMode.parse(raw)
        BmsONESoundChannelLaneMode.save(bmsonSoundLaneMode)
        refreshWindow()
    }

    @objc func transferBmsonNotesToKey(_ sender: Any?) {
        transferBmsonNotes(toBGM: false)
    }

    @objc func transferBmsonNotesToBGM(_ sender: Any?) {
        transferBmsonNotes(toBGM: true)
    }

    @objc func separateBmsonLayeredNotes(_ sender: Any?) {
        guard !isPresentingSheet, let bmsonDocument else { return }
        do {
            try bmsonDocument.separateLayeredNotes(
                identities: selectedBmsonNoteIdentities(),
                lanes: currentBmsonKeyLanes()
            )
            refreshWindow()
        } catch {
            NSSound.beep()
        }
    }

    @objc func addBmsonChannel(_ sender: Any?) {
        guard !isPresentingSheet, bmsonDocument != nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = FileTypes.sound
        panel.message = BmsONEMainWindowLayout.channelAddTitle
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        do {
            try bmsonDocument?.addSoundChannels(paths: panel.urls.map(\.path))
            refreshWindow()
        } catch {
            NSSound.beep()
        }
    }

    @objc func selectPreviousBmsonChannel(_ sender: Any?) {
        shiftBmsonChannel(previous: true)
    }

    @objc func selectNextBmsonChannel(_ sender: Any?) {
        shiftBmsonChannel(previous: false)
    }

    @objc func moveBmsonChannelLeft(_ sender: Any?) {
        guard !isPresentingSheet, let index = currentBmsonChannelIndex() else { return }
        guard bmsonDocument?.moveSoundChannel(from: index, to: index - 1) == true else {
            NSSound.beep()
            return
        }
        syncBmsonChannelSelection(index - 1)
        refreshWindow()
    }

    @objc func moveBmsonChannelRight(_ sender: Any?) {
        guard !isPresentingSheet, let index = currentBmsonChannelIndex() else { return }
        guard bmsonDocument?.moveSoundChannel(from: index, to: index + 1) == true else {
            NSSound.beep()
            return
        }
        syncBmsonChannelSelection(index + 1)
        refreshWindow()
    }

    @objc func destroyBmsonChannel(_ sender: Any?) {
        guard !isPresentingSheet, let index = currentBmsonChannelIndex() else { return }
        guard bmsonDocument?.destroySoundChannel(at: index) == true else {
            NSSound.beep()
            return
        }
        if let document = bmsonDocument {
            syncBmsonChannelSelection(document.selectedChannelIndex)
        }
        refreshWindow()
    }

    @objc func selectBmsonChannelFile(_ sender: Any?) {
        guard !isPresentingSheet, let index = currentBmsonChannelIndex() else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = FileTypes.sound
        panel.message = BmsONEMainWindowLayout.channelSelectFileTitle
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard bmsonDocument?.setSoundChannelName(at: index, path: url.path) == true else {
            NSSound.beep()
            return
        }
        refreshWindow()
    }

    @objc func previewBmsonChannelSource(_ sender: Any?) {
        guard !isPresentingSheet, let index = currentBmsonChannelIndex() else { return }
        previewNote(token: BmsonChartMapping.wavToken(channelIndex: index))
    }

    @objc func findNextBmsonChannel(_ sender: Any?) {
        findBmsonChannel(previous: false)
    }

    @objc func findPreviousBmsonChannel(_ sender: Any?) {
        findBmsonChannel(previous: true)
    }

    @objc func toggleBmsonFindActiveChannelsOnly(_ sender: Any?) {
        guard bmsonDocument != nil else { return }
        bmsonFindActiveChannelsOnly.toggle()
        if bmsonFindHideOthers {
            refreshWindow()
        }
    }

    @objc func toggleBmsonFindHideOthers(_ sender: Any?) {
        guard bmsonDocument != nil else { return }
        if bmsonFindHideOthers {
            bmsonFindHideOthers = false
            refreshWindow()
            return
        }
        if lastBmsonChannelKeyword.isEmpty {
            guard let keyword = promptChannelKeyword() else { return }
            lastBmsonChannelKeyword = keyword
        }
        bmsonFindHideOthers = true
        refreshWindow()
    }

    @objc func toggleDarkenInactiveBmsonChannels(_ sender: Any?) {
        guard bmsonDocument != nil else { return }
        content.setDarkensInactiveBmsonChannels(!content.darkensInactiveBmsonChannels)
    }

    private func findBmsonChannel(previous: Bool) {
        guard !isPresentingSheet, let document = bmsonDocument,
              let current = currentBmsonChannelIndex()
        else { return }
        guard let keyword = promptChannelKeyword() else { return }
        lastBmsonChannelKeyword = keyword
        let names = document.soundChannels.map(\.name)
        let active = bmsonFindActiveChannelsOnly ? activeBmsonChannels(in: document) : nil
        let found = previous
            ? BmsonChannel.findPrevious(
                keyword: keyword,
                current: current,
                names: names,
                activeInRegion: active
            )
            : BmsonChannel.findNext(
                keyword: keyword,
                current: current,
                names: names,
                activeInRegion: active
            )
        guard let found else {
            NSSound.beep()
            return
        }
        syncBmsonChannelSelection(found)
        refreshWindow()
    }

    private func activeBmsonChannels(in document: BmsONEDocument) -> [Bool] {
        if document.filePath != bmsonWaveSummaryDocument {
            bmsonWaveSummaries.removeAll()
            bmsonOverallWaveforms.removeAll()
            bmsonLaneRms.removeAll()
            bmsonWaveSummaryDocument = document.filePath
        }
        let range = content.visibleBmsonPulseRange(resolution: document.resolution)
        let directory = document.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let bpm = document.bpmNotes.map { (y: $0.y, v: $0.v) }
        return document.soundChannels.map { channel in
            BmsonChannel.isActiveInRegion(
                notes: channel.notes.map { (y: $0.y, c: $0.c) },
                tBegin: range.0,
                tEnd: range.1,
                wave: bmsonWaveSummary(named: channel.name, directory: directory),
                initBpm: document.initialBpm,
                resolution: document.resolution,
                bpmNotes: bpm
            )
        }
    }

    private func bmsonWaveCacheKey(named name: String, directory: URL?) -> String {
        (directory?.path ?? "") + "\u{1e}" + name
    }

    private func ensureBmsonWaveCache(named name: String, directory: URL?) {
        let key = bmsonWaveCacheKey(named: name, directory: directory)
        if bmsonWaveSummaries[key] != nil { return }
        if let wave = loadMasterWave(named: name, directory: directory) {
            bmsonWaveSummaries[key] = BmsonChannel.waveSummary(
                sampleCount: wave.samples.count,
                channels: wave.channels,
                sampleRate: wave.sampleRate
            )
            bmsonOverallWaveforms[key] = BmsonOverallWaveform.payload(
                samples: wave.samples,
                channels: wave.channels
            )
            bmsonLaneRms[key] = BmsonLaneWaveform.entries(
                samples: wave.samples,
                channels: wave.channels
            )
        } else {
            bmsonWaveSummaries[key] = BmsonChannel.WaveSummary(frameCount: 0, sampleRate: 0)
            bmsonOverallWaveforms[key] = .empty
            bmsonLaneRms[key] = []
        }
    }

    private func bmsonWaveSummary(named name: String, directory: URL?) -> BmsonChannel.WaveSummary {
        ensureBmsonWaveCache(named: name, directory: directory)
        return bmsonWaveSummaries[bmsonWaveCacheKey(named: name, directory: directory)]
            ?? BmsonChannel.WaveSummary(frameCount: 0, sampleRate: 0)
    }

    private func bmsonOverallWaveform(named name: String, directory: URL?) -> BmsonOverallWaveform.Payload {
        ensureBmsonWaveCache(named: name, directory: directory)
        return bmsonOverallWaveforms[bmsonWaveCacheKey(named: name, directory: directory)] ?? .empty
    }

    private func refreshBmsonChannelInfo() {
        guard let document = bmsonDocument else {
            content.setBmsonChannelInfo(visible: false, format: "", length: "")
            return
        }
        let index = max(content.selectedWavIndex, 0)
        guard document.soundChannels.indices.contains(index) else {
            content.setBmsonChannelInfo(visible: true, format: "", length: "")
            return
        }
        let directory = document.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let name = document.soundChannels[index].name
        let labels = BmsonChannel.channelInfoLabels(bmsonWaveSummary(named: name, directory: directory))
        content.setBmsonChannelInfo(
            visible: true,
            format: labels.format,
            length: labels.length,
            waveform: bmsonOverallWaveform(named: name, directory: directory)
        )
    }

    /// `isVisible() && HidesOthers()`。共用谱面藏音，不另开车道。
    private func shownBmsonChannels(in document: BmsONEDocument) -> [Bool]? {
        guard bmsonFindHideOthers else { return nil }
        let active = bmsonFindActiveChannelsOnly ? activeBmsonChannels(in: document) : nil
        return BmsonChannel.shownMask(
            hideOthers: true,
            names: document.soundChannels.map(\.name),
            keyword: lastBmsonChannelKeyword,
            activeInRegion: active,
            filterActive: bmsonFindActiveChannelsOnly
        )
    }

    private func refreshBmsonHideOthersIfNeeded() {
        guard let document = bmsonDocument, bmsonFindHideOthers, bmsonFindActiveChannelsOnly else { return }
        let shown = shownBmsonChannels(in: document) ?? []
        guard shown != lastShownBmsonChannels else { return }
        refreshWindow()
    }

    private func shiftBmsonChannel(previous: Bool) {
        guard !isPresentingSheet, let document = bmsonDocument,
              let current = currentBmsonChannelIndex()
        else { return }
        let next = previous
            ? BmsonChannel.selectPrevious(current: current, count: document.soundChannels.count)
            : BmsonChannel.selectNext(current: current, count: document.soundChannels.count)
        guard let next else { return }
        syncBmsonChannelSelection(next)
        refreshWindow()
    }

    private func currentBmsonChannelIndex() -> Int? {
        guard let document = bmsonDocument else { return nil }
        let wav = content.selectedWavIndex
        if wav >= 0, wav < document.soundChannels.count {
            return wav
        }
        if document.selectedChannelIndex >= 0,
           document.selectedChannelIndex < document.soundChannels.count
        {
            return document.selectedChannelIndex
        }
        return document.soundChannels.isEmpty ? nil : 0
    }

    private func syncBmsonChannelSelection(_ index: Int) {
        bmsonDocument?.selectedChannelIndex = index
        if index >= 0 {
            content.selectWavSlots([index])
        }
    }

    /// 声道列第一下只改当前声道。已经是当前列则返回 true。
    private func activateBmsonSoundChannelLane(_ index: Int) -> Bool {
        guard let document = bmsonDocument, document.soundChannels.indices.contains(index) else {
            return false
        }
        if BmsONESoundChannelLaneMode.continuesAfterClick(
            current: currentBmsonChannelIndex(),
            clicked: index
        ) {
            return true
        }
        syncBmsonChannelSelection(index)
        refreshWindow()
        return false
    }

    private func previewBmsonFooterChannel(_ index: Int) {
        guard bmsonDocument?.soundChannels.indices.contains(index) == true else { return }
        syncBmsonChannelSelection(index)
        previewNote(token: BmsonChartMapping.wavToken(channelIndex: index))
    }

    private func showBmsonFooterChannelMenu(at point: NSPoint) {
        guard bmsonDocument != nil, let window = window else { return }
        let menu = NSMenu()
        menu.addItem(
            withTitle: BmsONEMainWindowLayout.channelPreviewSourceTitle,
            action: #selector(previewBmsonChannelSource(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: BmsONEMainWindowLayout.channelMoveLeftTitle,
            action: #selector(moveBmsonChannelLeft(_:)),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: BmsONEMainWindowLayout.channelMoveRightTitle,
            action: #selector(moveBmsonChannelRight(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: BmsONEMainWindowLayout.channelDeleteTitle,
            action: #selector(destroyBmsonChannel(_:)),
            keyEquivalent: ""
        )
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: window.contentView?.convert(point, from: nil) ?? point, in: window.contentView)
    }

    private func promptChannelKeyword() -> String? {
        let alert = NSAlert()
        alert.messageText = "Find"
        alert.informativeText = "Channel name contains:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = lastBmsonChannelKeyword
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func editBmsonBarLine(beat: Double, remove: Bool) -> Bool {
        guard !isPresentingSheet, let bmsonDocument else { return false }
        let pulse = BmsonChartMapping.pulse(beat: beat, resolution: bmsonDocument.resolution)
        let changed = remove
            ? bmsonDocument.removeBarLine(pulseY: pulse)
            : bmsonDocument.insertBarLine(pulseY: pulse)
        if changed {
            refreshWindow()
            return true
        }
        NSSound.beep()
        return false
    }

    private func transferBmsonNotes(toBGM: Bool) {
        guard !isPresentingSheet, let bmsonDocument else { return }
        let identities = selectedBmsonNoteIdentities()
        do {
            try bmsonDocument.transferNotes(
                identities: identities,
                toBGM: toBGM,
                lanes: currentBmsonKeyLanes()
            )
            refreshWindow()
        } catch {
            NSSound.beep()
        }
    }

    private func selectedBmsonNoteIdentities() -> [Int] {
        let items = content.selectedChartItems()
        var identities: [Int] = []
        for event in items.events where event.sourceLine > 0 {
            let channel = event.channel.uppercased()
            if channel == "03" || channel == "08" || channel == "09" || channel == "SC" {
                continue
            }
            identities.append(event.sourceLine)
        }
        for note in items.longNotes where note.start.sourceLine > 0 {
            identities.append(note.start.sourceLine)
        }
        return identities
    }

    @objc func exportIBMSC(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor(), let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = FileTypes.ibmsc
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = exportIBMSCName()
        guard beginSheet() else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let url = panel.url else { return }
                do {
                    try self.currentIBMSCData().write(to: url)
                    self.rememberCurrentDocumentPath()
                    if self.editorSettingsStore.settings.beepWhileSaved {
                        NSSound.beep()
                    }
                } catch {
                    self.presentErrorSheet(error)
                }
            }
        }
    }

    @objc func showMyO2(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        myO2WindowController.present(over: window)
    }

    func handleCommandLineArguments(_ arguments: [String]) -> Bool {
        guard let path = LegacyLoadProgress.commandLineCandidate(arguments) else { return false }
        readFile(at: URL(fileURLWithPath: path))
        return LegacyLoadProgress.isAutosaveCommandLinePath(path)
    }

    func openExternalURLs(_ urls: [URL]) {
        if urls.count == 1 {
            readFile(at: urls[0])
            return
        }
        openDroppedURLs(urls)
    }

    func openDroppedURLs(_ urls: [URL]) {
        guard !isPresentingSheet else { return }
        let files = LegacyLoadProgress.filterExisting(urls)
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        let isSaved = !hasUnsavedChanges
        guard beginSheet() else { return }
        loadProgressWindowController.present(
            paths: paths,
            isSaved: isSaved,
            loadCurrent: { [weak self] path in self?.readFile(at: URL(fileURLWithPath: path)) },
            loadNewProcess: { [weak self] path in self?.launchNewInstance(URL(fileURLWithPath: path)) },
            completion: { [weak self] in self?.finishSheet() }
        )
    }

    func offerAutosaveRestoreIfNeeded() {
        guard isOnlyRunningInstance() else { return }
        let folder = LegacyAutoSave.directory()
        let files = LegacyAutoSave.listSnapshots(in: folder)
        guard !files.isEmpty, let window else { return }
        recoveredAutoSaveFiles = files
        let alert = NSAlert()
        alert.messageText = LegacyAutoSave.restoreMessage(count: files.count)
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                for file in files {
                    self.launchNewInstance(file)
                }
            }
        }
    }

    func deleteAutoSaveFiles() {
        let victims = recoveredAutoSaveFiles + [previousAutoSavedFileName].compactMap { $0 }
        for url in victims {
            try? FileManager.default.removeItem(at: url)
        }
        recoveredAutoSaveFiles = []
        previousAutoSavedFileName = nil
    }

    func windowWillClose(_ notification: Notification) {
        deleteAutoSaveFiles()
    }

    private func readFile(at url: URL) {
        switch LegacyLoadProgress.kind(path: url.path) {
        case .bms:
            loadBMS(from: url)
        case .sm:
            loadSM(from: url)
        case .ibmsc:
            loadIBMSC(from: url)
        case .bmson:
            loadBmson(from: url)
        case nil:
            break
        }
    }

    private func loadBMS(from url: URL, remember: Bool = true) {
        do {
            let loaded = try DocumentSession(data: Data(contentsOf: url), fileURL: url)
            dismissAuxiliaryWindows()
            importedDocumentTitle = nil
            cleanExternalViewerTemp()
            bmsonDocument = nil
            ibmscSnapshot = nil
            session = loaded
            lastBmsInitPath = url.deletingLastPathComponent().path
            content.discardPendingMetadata()
            refreshWindow(resetChartPosition: true)
            if remember {
                rememberRecent(url)
            }
        } catch {
            presentErrorSheet(error)
        }
    }

    /// 对照 `MainWindow::ReplaceDocument`：打开谱时按 `GetViewMode(modeHint)` 勾上对应项。
    private func adoptBmsonDocument(_ document: BmsONEDocument) {
        cleanExternalViewerTemp()
        bmsonDocument = document
        bmsonViewMode = BmsONEViewMode.resolve(document.modeHint)
        bmsonWaveSummaries.removeAll()
        bmsonOverallWaveforms.removeAll()
        bmsonLaneRms.removeAll()
        bmsonWaveSummaryDocument = document.filePath
    }

    private func loadBmson(from url: URL, remember: Bool = true) {
        do {
            let loaded = try BmsONEDocument.open(url: url)
            dismissAuxiliaryWindows()
            importedDocumentTitle = nil
            session = nil
            adoptBmsonDocument(loaded)
            content.discardPendingMetadata()
            refreshWindow(resetChartPosition: true)
            if remember {
                rememberRecent(url)
            }
        } catch {
            presentErrorSheet(error)
        }
    }

    func openEmptyBmson() {
        requestTransitionToBmson()
    }

    private func requestTransitionToBmson() {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        resolveDiscardingChanges { [weak self] approved in
            guard approved, let self else { return }
            self.dismissAuxiliaryWindows()
            self.importedDocumentTitle = nil
            self.session = nil
            self.adoptBmsonDocument(.empty())
            self.content.discardPendingMetadata()
            self.refreshWindow(resetChartPosition: true)
        }
    }

    private var hasUnsavedChanges: Bool {
        session?.dirty == true || bmsonDocument?.isModified == true
    }

    /// `SetIsSaved`：路径或脏状态变化后写主窗标题。`hasUnsavedChanges` 是 `IsSaved` 的反面。
    private func applyWindowTitle() {
        let isSaved = !hasUnsavedChanges
        if bmsonDocument != nil {
            window?.title = MainWindowChrome.windowTitle(
                fileName: bmsonDocument?.filePath ?? "",
                isSaved: isSaved,
                untitled: MainWindowChrome.untitledBMSONFileName
            )
            return
        }
        let fileName = session?.fileURL?.path ?? importedDocumentTitle ?? ""
        window?.title = MainWindowChrome.windowTitle(fileName: fileName, isSaved: isSaved)
    }

    private func launchNewInstance(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [url.path]
        let application = Bundle.main.bundleURL
        if application.pathExtension == "app" {
            NSWorkspace.shared.openApplication(at: application, configuration: configuration)
            return
        }
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = [url.path]
        try? process.run()
    }

    private func isOnlyRunningInstance() -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? "org.ibmsc.native"
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count <= 1
    }

    private func scheduleAutoSave(_ milliseconds: Int) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        guard milliseconds > 0 else { return }
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(milliseconds) / 1000,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.writeAutoSaveSnapshot()
            }
        }
    }

    private func writeAutoSaveSnapshot() {
        guard bmsonDocument == nil, session != nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: LegacyAutoSave.directory(),
                withIntermediateDirectories: true
            )
            let destination = LegacyAutoSave.directory().appendingPathComponent(LegacyAutoSave.fileName(at: Date()))
            try currentIBMSCData().write(to: destination)
            if let previous = previousAutoSavedFileName {
                try? FileManager.default.removeItem(at: previous)
            }
            previousAutoSavedFileName = destination
        } catch {
            return
        }
    }

    private func requestImport(_ action: @escaping () -> Void) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        resolveDiscardingChanges { approved in
            guard approved else { return }
            action()
        }
    }

    private func presentSMOpenPanel() {
        guard let window, beginSheet() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileTypes.sm
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let url = panel.url else { return }
                self.loadSM(from: url)
            }
        }
    }

    private func presentIBMSCOpenPanel() {
        guard let window, beginSheet() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileTypes.ibmsc
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let url = panel.url else { return }
                self.loadIBMSC(from: url)
            }
        }
    }

    private func presentBmsAsBmsonOpenPanel() {
        guard let window, beginSheet() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileTypes.allowed
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let url = panel.url else { return }
                self.importBmsFileAsBmson(from: url)
            }
        }
    }

    private func importBmsFileAsBmson(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            bmsonImportDialog.present(data: data, path: url.path) { [weak self] document in
                guard let self else { return }
                self.dismissAuxiliaryWindows()
                self.importedDocumentTitle = nil
                self.session = nil
                self.adoptBmsonDocument(document)
                self.content.discardPendingMetadata()
                self.refreshWindow(resetChartPosition: true)
            }
        } catch {
            presentErrorSheet(error)
        }
    }

    private func loadSM(from url: URL) {
        do {
            let text = try decodeImportedText(Data(contentsOf: url))
            let difficulties = LegacySMImport.difficulties(in: text)
            if difficulties.count > 1, let window {
                importSMWindowController.present(over: window, difficulties: difficulties) { [weak self] index in
                    guard let index else { return }
                    self?.applySM(text, difficulty: index)
                }
            } else {
                applySM(text, difficulty: 0)
            }
        } catch {
            presentErrorSheet(error)
        }
    }

    private func applySM(_ text: String, difficulty: Int) {
        do {
            let lnobj = BMS36Token.decode(session?.longNoteSnapshot.lnobjToken ?? "")
            let result = LegacySMImport.parse(
                text,
                difficulty: difficulty,
                convertToNT: content.ntInputEnabled,
                lnobj: lnobj
            )
            importedDocumentTitle = "Untitled.bms"
            cleanExternalViewerTemp()
            bmsonDocument = nil
            ibmscSnapshot = nil
            session = try DocumentSession(data: Data())
            content.discardPendingMetadata()
            try applyImportedMetadata(title: result.title, artist: result.artist, genre: result.genre)
            try session?.setInitialBPM(bpmDecimal(result.initialBPM))
            for event in result.bpmEvents {
                let grid = LegacySMImport.grid(from: event.vPosition)
                try session?.insertTimingEvent(
                    measure: grid.measure,
                    channel: timingChannel(for: event.value),
                    fraction: TimingRational(numerator: Int64(grid.slot), denominator: Int64(grid.division)),
                    decimal: bpmDecimal(event.value)
                )
            }
            for note in result.notes {
                try insertImportedNote(note)
            }
            refreshWindow(resetChartPosition: true)
        } catch {
            presentErrorSheet(error)
        }
    }

    private func loadIBMSC(from url: URL, remember: Bool = true) {
        do {
            guard let document = LegacyIBMSC.parse(try Data(contentsOf: url)) else { return }
            importedDocumentTitle = "Imported_" + url.lastPathComponent
            cleanExternalViewerTemp()
            bmsonDocument = nil
            ibmscSnapshot = document
            session = try DocumentSession(data: Data())
            content.discardPendingMetadata()
            content.setNTInputEnabled(document.ntInput)
            content.setSnapEnabled(document.snap)
            content.setDisableVerticalMove(document.disableVerticalMove)
            applyIBMSCViewState(document)
            applyIBMSCGridState(document)
            content.setSlashValue(document.slash)
            try applyImportedMetadata(
                title: document.header.title,
                artist: document.header.artist,
                genre: document.header.genre,
                subtitle: document.header.subtitle,
                subartist: document.header.subartist,
                playLevel: document.header.playLevel
            )
            try applyIBMSCExtraHeader(document.header)
            try session?.setInitialBPM(bpmDecimal(Int(document.header.bpmValue)))
            for (measure, length) in document.measureLengths where abs(length - 192) > 0.000_001 {
                try session?.setMeasureRatio(measure: measure, decimal: String(length / 192))
            }
            for note in document.notes {
                try insertIBMSCNote(note, measureLengths: document.measureLengths, ntInput: document.ntInput)
            }
            try applyImportedResources(document.wavs, directive: "WAV")
            try applyImportedResources(document.bmps, directive: "BMP")
            content.setWavListOptions(
                multiSelect: document.wavOptions & 0x1 != 0,
                synchronizeLabels: document.wavOptions & 0x2 != 0
            )
            try session?.setExpansion(document.expansion)
            session?.discardHistory()
            refreshWindow(resetChartPosition: true)
            if remember {
                rememberRecent(url)
            }
        } catch {
            presentErrorSheet(error)
        }
    }

    private func applyImportedMetadata(
        title: String,
        artist: String,
        genre: String,
        subtitle: String = "",
        subartist: String = "",
        playLevel: String = ""
    ) throws {
        guard let session else { return }
        _ = try session.replaceMetadata(title, for: "TITLE")
        _ = try session.replaceMetadata(subtitle, for: "SUBTITLE")
        _ = try session.replaceMetadata(artist, for: "ARTIST")
        _ = try session.replaceMetadata(subartist, for: "SUBARTIST")
        _ = try session.replaceMetadata(genre, for: "GENRE")
        _ = try session.replaceMetadata(playLevel, for: "PLAYLEVEL")
    }

    private func applyIBMSCExtraHeader(_ header: IBMSCHeader) throws {
        guard let session else { return }
        let player = min(2, LegacyIBMSC.playerIndex(from: header.playerRank))
        let rank = min(4, LegacyIBMSC.rankIndex(from: header.playerRank))
        _ = try session.replaceMetadata(
            LegacyHeaderFields.storedValue(key: "PLAYER", popupIndex: player), for: "PLAYER")
        _ = try session.replaceMetadata(
            LegacyHeaderFields.storedValue(key: "RANK", popupIndex: rank), for: "RANK")
        _ = try session.replaceMetadata(header.stageFile, for: "STAGEFILE")
        _ = try session.replaceMetadata(header.banner, for: "BANNER")
        _ = try session.replaceMetadata(header.backBMP, for: "BACKBMP")
        _ = try session.replaceMetadata(
            LegacyHeaderFields.storedValue(key: "DIFFICULTY", popupIndex: Int(header.difficulty)),
            for: "DIFFICULTY")
        _ = try session.replaceMetadata(header.exRank, for: "EXRANK")
        _ = try session.replaceMetadata(header.total, for: "TOTAL")
        _ = try session.replaceMetadata(header.comment, for: "COMMENT")
        _ = try session.replaceMetadata(
            LegacyHeaderFields.storedValue(key: "LNOBJ", popupIndex: max(0, Int(header.lnObjIndex))),
            for: "LNOBJ")
    }

    private func applyImportedResources(_ slots: [Int: String], directive: String) throws {
        guard !slots.isEmpty else { return }
        var names = LegacyWavList.emptyNames()
        for (index, name) in slots where index >= 1 && index <= LegacyWavList.slotCount {
            names[index - 1] = name
        }
        let edit = WavListEdit(names: names, selected: [])
        if directive == "BMP" {
            try session?.applyBmpEdit(edit, synchronizeLabels: false)
        } else {
            try session?.applyWavEdit(edit, synchronizeLabels: false)
        }
    }

    private func occupiedIBMSCSlots(_ names: [String]) -> [Int: String] {
        var slots: [Int: String] = [:]
        for (index, name) in names.enumerated() where !name.isEmpty {
            slots[index + 1] = name
        }
        return slots
    }

    private func insertImportedNote(_ note: SMImportedNote) throws {
        let channel = LegacySMImport.visibleChannel(for: note.columnIndex)
        let token = LegacySMImport.token(for: note.value)
        if note.length > 0 {
            let start = LegacySMImport.grid(from: note.vPosition)
            let end = LegacySMImport.grid(from: note.vPosition + note.length)
            try session?.insertLongNote(
                channel: channel,
                startMeasure: start.measure,
                startSlot: start.slot,
                endMeasure: end.measure,
                endSlot: end.slot,
                gridDivision: start.division,
                token: token,
                endToken: token
            )
        } else {
            let grid = LegacySMImport.grid(from: note.vPosition)
            try session?.insertNote(
                measure: grid.measure,
                channel: channel,
                gridSlot: grid.slot,
                gridDivision: grid.division,
                token: token
            )
        }
    }

    private func insertIBMSCNote(_ note: IBMSCNote, measureLengths: [Int: Double], ntInput: Bool) throws {
        let model = MyO2Note(
            vPosition: note.vPosition,
            columnIndex: note.columnIndex,
            value: Int(note.value),
            longNote: note.longNote,
            length: note.length,
            hidden: note.hidden
        )
        let channel = LegacyMyO2.channel(for: model)
        let token = BMS36Token.encode(max(1, Int(note.value / 10_000)))
        if ntInput, note.length > 0 {
            let start = LegacyIBMSC.grid(from: note.vPosition, measureLengths: measureLengths)
            let end = LegacyIBMSC.grid(from: note.vPosition + note.length, measureLengths: measureLengths)
            try session?.insertLongNote(
                channel: LegacyMyO2.shortChannel(for: note.columnIndex),
                startMeasure: start.measure,
                startSlot: start.slot,
                endMeasure: end.measure,
                endSlot: end.slot,
                gridDivision: start.division,
                token: token,
                endToken: token
            )
        } else {
            let grid = LegacyIBMSC.grid(from: note.vPosition, measureLengths: measureLengths)
            try session?.insertNote(
                measure: grid.measure,
                channel: channel,
                gridSlot: grid.slot,
                gridDivision: grid.division,
                token: token
            )
        }
    }

    private func currentMyO2Notes() -> [MyO2Note] {
        let headerBpm: Double
        if let bmsonDocument {
            headerBpm = bmsonDocument.initialBpm
        } else {
            let timing = session?.timingSnapshot ?? .unavailable
            headerBpm = Double(timing.initialBPMDecimal) ?? 120
        }
        let headerValue = Int((headerBpm * 10_000).rounded(.toNearestOrEven))
        var notes = [
            MyO2Note(vPosition: -1, columnIndex: EditorColumn.bpm, value: headerValue, longNote: false, length: 0, hidden: false)
        ]
        for item in currentQueryNotes() {
            notes.append(myO2Note(from: item))
        }
        return notes
    }

    private func myO2Note(from item: QueryNote) -> MyO2Note {
        let value: Int
        if let numeric = item.numericValue {
            value = Int((numeric * 10_000).rounded(.toNearestOrEven))
        } else {
            value = BMS36Token.decode(item.labelToken) * 10_000
        }
        switch item.source {
        case .event(let event):
            return MyO2Note(
                vPosition: event.beat * 48,
                columnIndex: item.columnIndex,
                value: value,
                longNote: item.isLong,
                length: 0,
                hidden: item.isHidden
            )
        case .longNote(let note):
            return MyO2Note(
                vPosition: note.start.beat * 48,
                columnIndex: item.columnIndex,
                value: value,
                longNote: false,
                length: (note.end.beat - note.start.beat) * 48,
                hidden: item.isHidden
            )
        case .timing(let event):
            let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
            return MyO2Note(
                vPosition: beat * 48,
                columnIndex: item.columnIndex,
                value: value,
                longNote: false,
                length: 0,
                hidden: false
            )
        }
    }

    @discardableResult
    private func applyMyO2Notes(_ notes: [MyO2Note]) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            do {
                let header = notes.first(where: { $0.vPosition < 0 })
                let initialBpm = header.map { Double($0.value) / 10_000.0 } ?? bmsonDocument.initialBpm
                let body = notes.compactMap { note -> (vPosition: Double, columnIndex: Int, value: Int, length: Double)? in
                    guard note.vPosition >= 0 else { return nil }
                    return (
                        vPosition: note.vPosition,
                        columnIndex: note.columnIndex,
                        value: note.value,
                        length: note.length
                    )
                }
                try bmsonDocument.applyChartNotes(body, initialBpm: initialBpm, mode: bmsonViewMode)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        guard let session else { return false }
        do {
            let measureLengths = session.timingSnapshot.measureLengths()
            try session.rewriteChart {
                if let header = notes.first {
                    try session.setInitialBPM(bpmDecimal(header.value))
                }
                for note in notes.dropFirst() {
                    try insertMyO2ChartNote(note, measureLengths: measureLengths)
                }
            }
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func insertMyO2ChartNote(_ note: MyO2Note, measureLengths: [Int: Double]) throws {
        guard let session else { return }
        if note.columnIndex == EditorColumn.bpm {
            try session.insertTimingEvent(
                atVPosition: note.vPosition,
                channel: timingChannel(for: note.value),
                decimal: bpmDecimal(note.value),
                measureLengths: measureLengths
            )
        } else if note.columnIndex == EditorColumn.stop {
            try session.insertTimingEvent(
                atVPosition: note.vPosition,
                channel: "09",
                decimal: bpmDecimal(note.value),
                measureLengths: measureLengths
            )
        } else if note.length > 0 {
            try session.insertLongNote(
                fromVPosition: note.vPosition,
                length: note.length,
                channel: LegacyMyO2.shortChannel(for: note.columnIndex),
                token: BMS36Token.encode(max(1, note.value / 10_000)),
                measureLengths: measureLengths
            )
        } else {
            try session.insertNote(
                atVPosition: note.vPosition,
                channel: LegacyMyO2.channel(for: note),
                token: BMS36Token.encode(max(1, note.value / 10_000)),
                measureLengths: measureLengths
            )
        }
    }

    private func performTimeSelection(_ command: TimeSelectionCommand) {
        let notes = currentMyO2Notes().map {
            TimeSelectionNote(
                vPosition: $0.vPosition,
                columnIndex: $0.columnIndex,
                value: $0.value,
                length: $0.length,
                hidden: $0.hidden
            )
        }
        let selection = content.timeStretchOrigin ?? content.timeSelection
        let maxVPosition = LegacyTimeSelection.maxVPosition(chartEndBeat: content.chartEndBeat)
        let result: TimeSelectionWriteResult
        switch command {
        case .expand(let ratio):
            result = LegacyTimeSelectionOps.expandByRatio(
                notes: notes,
                selection: selection,
                ratio: ratio,
                maxVPosition: maxVPosition
            )
        case .stretchHalf(let delta):
            result = LegacyTimeSelectionOps.stretchByHalfDelta(
                notes: notes,
                selection: selection,
                delta: delta,
                maxVPosition: maxVPosition
            )
        case .relocate(let value):
            result = LegacyTimeSelectionOps.relocateByValue(
                notes: notes,
                selection: selection,
                value: value,
                maxVPosition: maxVPosition
            )
        case .convertStop:
            result = LegacyTimeSelectionOps.convertAreaToStop(notes: notes, selection: selection)
        }
        switch result {
        case .applied(let nextNotes, let nextSelection):
            let applied = applyMyO2Notes(nextNotes.map {
                MyO2Note(
                    vPosition: $0.vPosition,
                    columnIndex: $0.columnIndex,
                    value: $0.value,
                    longNote: $0.length > 0,
                    length: $0.length,
                    hidden: $0.hidden
                )
            })
            guard applied else { return }
            content.applyTimeSelection(nextSelection)
            NSSound.beep()
        case .blocked(let message):
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            alert.runModal()
        case .skipped:
            break
        }
    }

    private func currentEditableMetadata() throws -> [String: String] {
        guard let session else { return [:] }
        var values: [String: String] = [:]
        for key in DocumentSession.editableKeys {
            values[key] = (try? session.metadataValue(for: key)) ?? ""
        }
        return values
    }

    private func currentIBMSCData() throws -> Data {
        let timing = session?.timingSnapshot ?? .unavailable
        let meta: (String) -> String = { (try? self.session?.metadataValue(for: $0)) ?? "" }
        let header = IBMSCHeader(
            title: meta("TITLE"),
            artist: meta("ARTIST"),
            genre: meta("GENRE"),
            subtitle: meta("SUBTITLE"),
            subartist: meta("SUBARTIST"),
            bpmValue: Int64(((Double(timing.initialBPMDecimal) ?? 120) * 10_000).rounded(.toNearestOrEven)),
            playLevel: meta("PLAYLEVEL"),
            playerRank: LegacyIBMSC.packPlayerRank(
                playerIndex: LegacyHeaderFields.popupIndex(key: "PLAYER", stored: meta("PLAYER")),
                rankIndex: LegacyHeaderFields.popupIndex(key: "RANK", stored: meta("RANK"))
            ),
            stageFile: meta("STAGEFILE"),
            banner: meta("BANNER"),
            backBMP: meta("BACKBMP"),
            difficulty: UInt8(clamping: LegacyHeaderFields.popupIndex(key: "DIFFICULTY", stored: meta("DIFFICULTY"))),
            exRank: meta("EXRANK"),
            total: meta("TOTAL"),
            comment: meta("COMMENT"),
            lnObjIndex: Int16(clamping: LegacyHeaderFields.popupIndex(key: "LNOBJ", stored: meta("LNOBJ")))
        )
        let measureLengths = timing.measureLengths()
        let notes = currentMyO2Notes().dropFirst().map { note in
            IBMSCNote(
                vPosition: note.vPosition,
                columnIndex: note.columnIndex,
                value: Int64(note.value),
                longNote: note.longNote,
                length: note.length,
                hidden: note.hidden,
                landmine: false
            )
        }
        return LegacyIBMSC.writeSubset(
            header: header,
            notes: Array(notes),
            ntInput: content.ntInputEnabled,
            snap: content.snapEnabled,
            disableVerticalMove: content.disableVerticalMove,
            showFileName: content.showFileNameEnabled,
            showLeftSplitter: content.leftSplitterVisible,
            showRightSplitter: content.rightSplitterVisible,
            lockLeftScroll: content.scrollLocks.indices.contains(0) && content.scrollLocks[0],
            lockMiddleScroll: content.scrollLocks.indices.contains(1) && content.scrollLocks[1],
            lockRightScroll: content.scrollLocks.indices.contains(2) && content.scrollLocks[2],
            errorCheck: content.errorCheckEnabled,
            previewOnClick: content.previewOnClickEnabled,
            showToolbar: content.toolBarVisible,
            showOptionsPanel: content.optionsVisible,
            showStatusBar: content.statusVisible,
            showGrid: content.gridVisible,
            showSubGrid: content.subGridVisible,
            showBackground: content.backgroundVisible,
            showMeasureNumber: content.measureNumberVisible,
            showMeasureBar: content.measureBarVisible,
            showVerticalLine: content.verticalLineVisible,
            showColumnCaption: content.columnCaptionVisible,
            showBPMColumn: content.bpmColumnVisible,
            showStopColumn: content.stopColumnVisible,
            showBGAColumns: content.bgaColumnsVisible,
            showScrollColumn: content.scrollColumnVisible,
            divide: content.selectedDivision,
            sub: content.selectedSubDivision,
            slash: content.slashValue,
            height: content.gridHeightValue,
            width: content.gridWidthValue,
            bgmColumns: content.currentBGMColumnCount,
            measureLengths: measureLengths,
            expansion: (try? session?.expansionText()) ?? "",
            wavs: occupiedIBMSCSlots(try session?.wavNames() ?? []),
            bmps: occupiedIBMSCSlots(try session?.bmpNames() ?? []),
            wavOptions: (content.wavAllowsMultipleSelection ? 0x1 : 0) | (content.wavSynchronizeLabels ? 0x2 : 0),
            undo: exportedIBMSCUndo()
        )
    }

    private func applyIBMSCGridState(_ document: IBMSCDocument) {
        content.setDivision(document.divide)
        content.setSubDivision(document.sub)
        content.setGridHeight(document.height)
        content.setGridWidth(document.width)
        if document.bgmColumns >= 1 {
            content.setBGMColumnCount(document.bgmColumns)
        }
    }

    private func applyIBMSCViewState(_ document: IBMSCDocument) {
        content.setShowFileNameEnabled(document.showFileName)
        content.setLeftSplitterVisible(document.showLeftSplitter)
        content.setRightSplitterVisible(document.showRightSplitter)
        content.setScrollLocks([
            document.lockLeftScroll, document.lockMiddleScroll, document.lockRightScroll
        ])
        let hasViewBits = document.errorCheck || document.previewOnClick || document.showToolbar
            || document.showOptionsPanel || document.showStatusBar || document.showGrid
            || document.showSubGrid || document.showBackground || document.showMeasureNumber
            || document.showMeasureBar || document.showVerticalLine || document.showColumnCaption
            || document.showBPMColumn || document.showStopColumn || document.showBGAColumns
            || document.showScrollColumn
        guard hasViewBits else { return }
        content.setErrorCheckEnabled(document.errorCheck)
        content.setPreviewOnClickEnabled(document.previewOnClick)
        content.setToolBarVisible(document.showToolbar)
        content.setOptionsVisible(document.showOptionsPanel)
        content.setStatusVisible(document.showStatusBar)
        content.setGridVisibility(
            showGrid: document.showGrid,
            showSubGrid: document.showSubGrid,
            showMeasureBar: document.showMeasureBar,
            showBackground: document.showBackground,
            showMeasureNumber: document.showMeasureNumber,
            showVerticalLine: document.showVerticalLine,
            showColumnCaption: document.showColumnCaption
        )
        content.setColumnVisibility(
            scroll: document.showScrollColumn,
            bpm: document.showBPMColumn,
            stop: document.showStopColumn,
            bga: document.showBGAColumns
        )
    }

    private func exportedIBMSCUndo() -> IBMSCUndoHistory {
        if session?.canUndo != true, session?.canRedo != true, let undo = ibmscSnapshot?.undo {
            return undo
        }
        return .cleared
    }

    private func applyIBMSCUndo(redo: Bool) -> Bool {
        guard session?.canUndo != true, session?.canRedo != true else { return false }
        guard var snapshot = ibmscSnapshot else { return false }
        var notes = snapshot.notes
        let changed = redo
            ? snapshot.undo.redo(notes: &notes, ntInput: snapshot.ntInput)
            : snapshot.undo.undo(notes: &notes, ntInput: snapshot.ntInput)
        guard changed else { return false }
        snapshot.notes = notes
        do {
            try reloadIBMSCNotes(snapshot)
            ibmscSnapshot = snapshot
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func reloadIBMSCNotes(_ document: IBMSCDocument) throws {
        session = try DocumentSession(data: Data())
        content.discardPendingMetadata()
        content.setNTInputEnabled(document.ntInput)
        content.setSnapEnabled(document.snap)
        content.setDisableVerticalMove(document.disableVerticalMove)
        applyIBMSCViewState(document)
        applyIBMSCGridState(document)
        content.setSlashValue(document.slash)
        try applyImportedMetadata(
            title: document.header.title,
            artist: document.header.artist,
            genre: document.header.genre,
            subtitle: document.header.subtitle,
            subartist: document.header.subartist,
            playLevel: document.header.playLevel
        )
        try applyIBMSCExtraHeader(document.header)
        try session?.setInitialBPM(bpmDecimal(Int(document.header.bpmValue)))
        for (measure, length) in document.measureLengths where abs(length - 192) > 0.000_001 {
            try session?.setMeasureRatio(measure: measure, decimal: String(length / 192))
        }
        for note in document.notes {
            try insertIBMSCNote(note, measureLengths: document.measureLengths, ntInput: document.ntInput)
        }
        try applyImportedResources(document.wavs, directive: "WAV")
        try applyImportedResources(document.bmps, directive: "BMP")
        content.setWavListOptions(
            multiSelect: document.wavOptions & 0x1 != 0,
            synchronizeLabels: document.wavOptions & 0x2 != 0
        )
        try session?.setExpansion(document.expansion)
        session?.discardHistory()
    }

    private func exportIBMSCName() -> String {
        let base = session?.fileURL?.deletingPathExtension().lastPathComponent
            ?? importedDocumentTitle?.replacingOccurrences(of: ".bms", with: "")
            ?? "Untitled"
        return base + ".ibmsc"
    }

    private func decodeImportedText(_ data: Data) throws -> String {
        let encoding: String.Encoding
        switch editorSettingsStore.settings.textEncodingIndex {
        case 1: encoding = .utf16LittleEndian
        case 3: encoding = .utf16BigEndian
        case 4: encoding = .utf32LittleEndian
        case 6: encoding = .utf8
        case 7: encoding = .shiftJIS
        case 8: encoding = String.Encoding(rawValue: IBMSNSStringEncodingEucKR())
        default: encoding = .isoLatin1
        }
        if let text = String(data: data, encoding: encoding) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        throw DocumentSessionError.unsupportedMetadataEncoding
    }

    private func bpmDecimal(_ value: Int) -> String {
        if value % 10_000 == 0 {
            return String(value / 10_000)
        }
        return String(Double(value) / 10_000)
    }

    private func timingChannel(for value: Int) -> String {
        let whole = value / 10_000
        if value % 10_000 == 0, (1...255).contains(whole) {
            return "03"
        }
        return "08"
    }

    @objc func showFind(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        findWindowController.invalidLabelText = currentRuntime.invalidLabel
        findWindowController.present(over: window)
    }

    @objc func gotoMeasure(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        let alert = NSAlert()
        alert.messageText = LegacyGotoMeasure.title
        alert.informativeText = LegacyGotoMeasure.prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let measure = LegacyGotoMeasure.parse(field.stringValue) else { return }
        content.scrollToMeasure(measure)
    }

    @objc func showStatistics(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor(), let window, beginSheet() else { return }
        statisticsWindowController.present(over: window, matrix: currentStatistics()) { [weak self] in
            self?.finishSheet()
        }
    }

    @objc func showVisualOptions(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor(), let window, beginSheet() else { return }
        visualOptionsWindowController.present(over: window, theme: editorThemeController.currentTheme) { [weak self] theme in
            guard let self else { return }
            self.finishSheet()
            guard let theme else { return }
            do {
                try self.editorThemeController.applyEditedTheme(theme, name: self.editorThemeController.currentThemeName)
            } catch {
                self.presentErrorSheet(error)
            }
        }
    }

    @objc func showGeneralOptions(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor(), let window, beginSheet() else { return }
        generalOptionsWindowController.present(over: window, settings: editorSettingsStore.settings) { [weak self] settings in
            guard let self else { return }
            self.finishSheet()
            if let settings {
                self.editorSettingsStore.replace(settings)
                self.content.applyEditorSettings(settings)
                self.applyIndexedTimingRadix(settings)
                self.scheduleAutoSave(settings.autoSaveMilliseconds)
                self.refreshWindow()
            }
        }
    }

    @objc func showPlayerOptions(_ sender: Any?) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor(), let window, beginSheet() else { return }
        playerOptionsWindowController.present(over: window, settings: editorSettingsStore.settings) { [weak self] settings in
            guard let self else { return }
            self.finishSheet()
            if let settings {
                self.editorSettingsStore.replace(settings)
                self.content.setNotice("Player arguments are saved. Built-in preview still does not launch these programs.")
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowWindowClose {
            allowWindowClose = false
            return true
        }
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return false }
        resolveDiscardingChanges { [weak self] approved in
            guard approved, let self else { return }
            self.scheduleApprovedWindowClose()
        }
        return false
    }

    func mayTerminateApplication() -> NSApplication.TerminateReply {
        if skipNextTerminationPrompt {
            skipNextTerminationPrompt = false
            return .terminateNow
        }
        guard !terminationReplyPending else { return .terminateLater }

        if isPresentingSheet {
            return .terminateCancel
        }

        guard content.commitActiveMetadataEditor() else { return .terminateCancel }
        guard hasUnsavedChanges else { return .terminateNow }

        terminationReplyPending = true
        beginTerminationDecision()
        return .terminateLater
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if isPresentingSheet { return false }
        switch menuItem.action {
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)):
            return session != nil || bmsonDocument != nil
        case #selector(openRecent(_:)):
            return recentSlots.indices.contains(menuItem.tag) && LegacyRecent.isEnabled(recentSlots[menuItem.tag])
        case #selector(performChromeCommand(_:)):
            return validateChromeCommand(menuItem)
        case #selector(exportBmsonWav(_:)), #selector(convertBmsonResolution(_:)):
            return bmsonDocument != nil
        case #selector(clearBmsonMasterCache(_:)):
            return bmsonDocument != nil && BmsONEPreferences.load().enableMasterChannel
        case #selector(playExternalViewerFromBeginning(_:)),
             #selector(playExternalViewerFromHere(_:)),
             #selector(stopExternalViewer(_:)):
            if session != nil { return true }
            return bmsonDocument != nil && BmsONEExternalViewerStore.load().isPlayable
        case #selector(transferBmsonNotesToKey(_:)), #selector(transferBmsonNotesToBGM(_:)),
             #selector(separateBmsonLayeredNotes(_:)):
            return bmsonDocument != nil && !selectedBmsonNoteIdentities().isEmpty
        case #selector(addBmsonChannel(_:)):
            return bmsonDocument != nil
        case #selector(selectPreviousBmsonChannel(_:)), #selector(selectNextBmsonChannel(_:)),
             #selector(moveBmsonChannelLeft(_:)), #selector(moveBmsonChannelRight(_:)),
             #selector(destroyBmsonChannel(_:)), #selector(selectBmsonChannelFile(_:)),
             #selector(previewBmsonChannelSource(_:)), #selector(findNextBmsonChannel(_:)),
             #selector(findPreviousBmsonChannel(_:)):
            return currentBmsonChannelIndex() != nil
        case #selector(toggleBmsonFindActiveChannelsOnly(_:)):
            menuItem.state = bmsonFindActiveChannelsOnly ? .on : .off
            return bmsonDocument != nil
        case #selector(toggleBmsonFindHideOthers(_:)):
            menuItem.state = bmsonFindHideOthers ? .on : .off
            return bmsonDocument != nil
        case #selector(toggleDarkenInactiveBmsonChannels(_:)):
            menuItem.state = content.darkensInactiveBmsonChannels ? .on : .off
            return bmsonDocument != nil
        case #selector(toggleBmsonSnapToGrid(_:)):
            menuItem.state = content.snapEnabled ? .on : .off
            return true
        case #selector(zoomBmsonIn(_:)), #selector(zoomBmsonOut(_:)), #selector(zoomBmsonReset(_:)):
            return bmsonDocument != nil
        case #selector(selectBmsonViewMode(_:)):
            if let hint = menuItem.representedObject as? String {
                let selected = BmsONEViewMode.resolve(hint)
                menuItem.state = bmsonViewMode.inMenu && bmsonViewMode.kind == selected.kind ? .on : .off
            }
            return bmsonDocument != nil
        case #selector(selectBmsonScratch(_:)):
            if let stored = menuItem.representedObject as? String {
                menuItem.state = BmsONEScratch.load(kind: bmsonViewMode.kind)?.stored == stored ? .on : .off
            }
            return bmsonDocument != nil && !BmsONEScratch.choices(for: bmsonViewMode.kind).isEmpty
        case #selector(selectBmsonLaneOrder(_:)):
            if let stored = menuItem.representedObject as? String {
                menuItem.state = BmsONELaneOrder.load(kind: bmsonViewMode.kind)?.stored == stored ? .on : .off
            }
            return bmsonDocument != nil && !BmsONELaneOrder.choices(for: bmsonViewMode.kind).isEmpty
        case #selector(showBmsonLaneCount(_:)):
            let count = BmsONEPlainLanes.load(kind: bmsonViewMode.kind) ?? BmsONEPlainLanes.defaultCount
            menuItem.title = BmsONEPlainLanes.menuTitle(count: count)
            return bmsonDocument != nil && BmsONEPlainLanes.applies(to: bmsonViewMode.kind)
        case #selector(selectBmsonColorScheme(_:)):
            if let stored = menuItem.representedObject as? String {
                menuItem.state = BmsONEColorScheme.load(kind: bmsonViewMode.kind)?.stored == stored ? .on : .off
            }
            return bmsonDocument != nil && !BmsONEColorScheme.choices(for: bmsonViewMode.kind).isEmpty
        case #selector(selectBmsonWheel(_:)):
            if let stored = menuItem.representedObject as? String {
                menuItem.state = BmsONEWheel.load(kind: bmsonViewMode.kind)?.stored == stored ? .on : .off
            }
            return bmsonDocument != nil && !BmsONEWheel.choices(for: bmsonViewMode.kind).isEmpty
        case #selector(selectBmsonSoundChannelLaneMode(_:)):
            if let raw = menuItem.representedObject as? String {
                menuItem.state = BmsONESoundChannelLaneMode.parse(raw) == bmsonSoundLaneMode ? .on : .off
            }
            return bmsonDocument != nil
        case #selector(undoDocument(_:)):
            return session?.canUndo == true || ibmscSnapshot?.undo.canUndo == true || bmsonDocument?.canUndo == true
        case #selector(redoDocument(_:)):
            return session?.canRedo == true || ibmscSnapshot?.undo.canRedo == true || bmsonDocument?.canRedo == true
        case #selector(selectTimeTool(_:)):
            menuItem.state = content.currentTool == .timeSelect ? .on : .off
            return true
        case #selector(selectSelectTool(_:)):
            menuItem.state = content.currentTool == .select ? .on : .off
            return true
        case #selector(selectWriteTool(_:)):
            menuItem.state = content.currentTool == .write ? .on : .off
            return true
        case #selector(toggleGrid(_:)):
            menuItem.state = content.gridVisible ? .on : .off
            return true
        case #selector(toggleSubGrid(_:)):
            menuItem.state = content.subGridVisible ? .on : .off
            return true
        case #selector(toggleMeasureLine(_:)):
            menuItem.state = content.measureBarVisible ? .on : .off
            return true
        case #selector(toggleBackground(_:)):
            menuItem.state = content.backgroundVisible ? .on : .off
            return true
        case #selector(toggleMeasureIndex(_:)):
            menuItem.state = content.measureNumberVisible ? .on : .off
            return true
        case #selector(toggleVerticalLine(_:)):
            menuItem.state = content.verticalLineVisible ? .on : .off
            return true
        case #selector(toggleColumnCaption(_:)):
            menuItem.state = content.columnCaptionVisible ? .on : .off
            return true
        case #selector(toggleToolBar(_:)):
            menuItem.state = content.toolBarVisible ? .on : .off
            return true
        case #selector(toggleOptionsPanel(_:)):
            menuItem.state = content.optionsVisible ? .on : .off
            return true
        case #selector(toggleStatusBar(_:)):
            menuItem.state = content.statusVisible ? .on : .off
            return true
        case #selector(toggleScrollColumn(_:)):
            menuItem.state = content.scrollColumnVisible ? .on : .off
            return true
        case #selector(toggleBPMColumn(_:)):
            menuItem.state = content.bpmColumnVisible ? .on : .off
            return true
        case #selector(toggleStopColumn(_:)):
            menuItem.state = content.stopColumnVisible ? .on : .off
            return true
        case #selector(toggleBGAColumns(_:)):
            menuItem.state = content.bgaColumnsVisible ? .on : .off
            return true
        case #selector(toggleLeftSplitter(_:)):
            menuItem.state = content.leftSplitterVisible ? .on : .off
            return true
        case #selector(toggleRightSplitter(_:)):
            menuItem.state = content.rightSplitterVisible ? .on : .off
            return true
        default:
            return true
        }
    }

    private func validateChromeCommand(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.representedObject as? String else { return true }
        switch command {
        case "TBNTInput":
            menuItem.state = content.ntInputEnabled ? .on : .off
            return true
        case "TBErrorCheck":
            menuItem.state = content.errorCheckEnabled ? .on : .off
            return true
        case "TBPreviewOnClick":
            menuItem.state = content.previewOnClickEnabled ? .on : .off
            return true
        case "TBShowFileName":
            menuItem.state = content.showFileNameEnabled ? .on : .off
            return true
        default:
            return LegacyChromeMenu.conversionEnabled(command: command, ntInput: content.ntInputEnabled)
        }
    }

    private func requestTransition(_ transition: Transition) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        resolveDiscardingChanges { [weak self] approved in
            guard approved else { return }
            self?.perform(transition)
        }
    }

    private func perform(_ transition: Transition) {
        switch transition {
        case .newDocument:
            do {
                dismissAuxiliaryWindows()
                importedDocumentTitle = nil
                cleanExternalViewerTemp()
                bmsonDocument = nil
                ibmscSnapshot = nil
                session = try DocumentSession(data: Data())
                content.discardPendingMetadata()
                refreshWindow(resetChartPosition: true)
            } catch {
                presentErrorSheet(error)
            }
        case .openDocument:
            presentOpenPanel()
        }
    }

    private func presentOpenPanel() {
        guard let window, beginSheet() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileTypes.openTypes
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let url = panel.url else { return }
                self.readFile(at: url)
            }
        }
    }

    private func setMetadata(key: String, value: String) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            guard BmsonHeaderMapping.editableKeys.contains(key) else { return false }
            do {
                try bmsonDocument.replaceHeader(key: key, value: value)
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        guard let session else { return false }
        do {
            _ = try session.replaceMetadata(value, for: key)
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func setHeaderBPM(_ decimal: String) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            do {
                try bmsonDocument.setInitialBPM(decimal)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        guard let session else { return false }
        do {
            try session.setInitialBPM(decimal)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func applyExpansion(_ text: String) -> Bool {
        guard !isPresentingSheet, let session else { return false }
        do {
            try session.setExpansion(text)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func applyBeat(measures: [Int], decimal: String, mode: LegacyBeat.Mode) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            do {
                try bmsonDocument.applyBeat(measures: measures, decimal: decimal, mode: mode.rawValue)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        guard let session else { return false }
        do {
            try session.applyBeat(measures: measures, decimal: decimal, mode: mode.rawValue)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func selectEncoding(_ encoding: MetadataEncoding) -> Bool {
        guard !isPresentingSheet else { return false }
        guard content.commitActiveMetadataEditor() else {
            refreshWindow()
            return false
        }
        guard let session else { return false }
        do {
            try session.selectMetadataEncoding(encoding)
            refreshWindow()
            return true
        } catch {
            refreshWindow()
            presentErrorSheet(error)
            return false
        }
    }

    private func writeNote(
        channel: String,
        measure: Int,
        slot: Int,
        division: Int,
        token: String,
        continueFlag: Bool = false
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return writeNote(
                channel: channel,
                pulseY: BmsonChartAdapter.insertPulse(
                    measure: measure,
                    slot: slot,
                    division: division,
                    document: bmsonDocument
                ),
                token: token,
                continueFlag: continueFlag
            )
        }
        guard let session else { return false }
        do { try session.insertNote(measure: measure, channel: channel, gridSlot: slot, gridDivision: division, token: token); refreshWindow(); return true }
        catch { presentErrorSheet(error); return false }
    }

    private func writeNote(
        channel: String,
        pulseY: Int64,
        token: String,
        continueFlag: Bool
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        guard let bmsonDocument else { return false }
        if let lane = BmsonChartMapping.BgaLane.parse(channel: channel) {
            guard let identifier = BmsonChartMapping.bmpId(token: token) else { return false }
            do {
                try bmsonDocument.upsertBgaEvent(lane: lane, pulseY: pulseY, identifier: identifier)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        do {
            if let index = BmsonSoundLane.index(display: channel) {
                if !BmsONESoundChannelLaneMode.continuesAfterClick(
                    current: currentBmsonChannelIndex(),
                    clicked: index
                ) {
                    syncBmsonChannelSelection(index)
                    refreshWindow()
                    return true
                }
                try bmsonDocument.insertShortNote(
                    laneX: 0,
                    pulseY: pulseY,
                    continueFlag: continueFlag
                )
                refreshWindow()
                return true
            }
            bmsonDocument.selectedChannelIndex = BmsonChartMapping.channelIndex(wavToken: token)
            try bmsonDocument.insertShortNote(
                laneX: BmsonChartMapping.laneX(forChannel: channel, mode: bmsonViewMode),
                pulseY: pulseY,
                continueFlag: continueFlag
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func writeTiming(channel: String, measure: Int, slot: Int, division: Int) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return writeBmsonTiming(
                document: bmsonDocument,
                channel: channel,
                pulseY: BmsonChartAdapter.insertPulse(
                    measure: measure,
                    slot: slot,
                    division: division,
                    document: bmsonDocument
                )
            )
        }
        guard let session else { return false }
        let message = currentRuntime.writeTimingPrompt(channel: channel)
        guard let decimal = promptTimingValue(message: message) else { return false }
        let writeChannel: String
        let writeDecimal: String
        if channel == "03" {
            guard let routed = ChartTiming.bpmWriteChannel(decimal),
                  let stored = ChartTiming.storedBpmDecimal(decimal) else {
                return false
            }
            writeChannel = routed
            writeDecimal = stored
        } else {
            writeChannel = channel
            writeDecimal = decimal
        }
        do {
            try session.insertTimingEvent(
                measure: measure,
                channel: writeChannel,
                gridSlot: slot,
                gridDivision: division,
                decimal: writeDecimal
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func writeBmsonTiming(channel: String, pulseY: Int64) -> Bool {
        guard let bmsonDocument else { return false }
        return writeBmsonTiming(document: bmsonDocument, channel: channel, pulseY: pulseY)
    }

    private func writeBmsonTiming(
        document: BmsONEDocument,
        channel: String,
        pulseY: Int64
    ) -> Bool {
        if channel == "SC" { return false }
        let message = currentRuntime.writeTimingPrompt(channel: channel)
        guard let decimal = promptTimingValue(message: message),
              let value = Double(decimal),
              value > 0,
              value.isFinite
        else { return false }
        do {
            if channel == "09" {
                try document.upsertStopNote(
                    pulseY: pulseY,
                    pulses: BmsonChartMapping.stopPulses(displayValue: value, resolution: document.resolution)
                )
            } else {
                try document.upsertBpmNote(pulseY: pulseY, bpm: value)
            }
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveBmsonTiming(
        document: BmsONEDocument,
        event: ChartEventSnapshot,
        channel: String,
        measure: Int,
        slot: Int,
        division: Int
    ) throws {
        try moveBmsonTiming(
            document: document,
            event: event,
            channel: channel,
            pulseY: BmsonChartAdapter.insertPulse(
                measure: measure,
                slot: slot,
                division: division,
                document: document
            )
        )
    }

    private func moveBmsonTiming(
        document: BmsONEDocument,
        event: ChartEventSnapshot,
        channel: String,
        pulseY newPulse: Int64
    ) throws {
        let oldPulse = BmsonChartMapping.pulse(beat: event.beat, resolution: document.resolution)
        if channel == "09" {
            guard event.channel == "09" else {
                throw BmsONEDocumentError.parse("BMSON timing stays on BPM or STOP")
            }
            let pulses = BmsonChartMapping.stopPulses(
                displayValue: Double(event.token) ?? 0,
                resolution: document.resolution
            )
            guard pulses > 0 else {
                throw BmsONEDocumentError.parse("stopNotes.v must be positive")
            }
            try document.moveStopNote(from: oldPulse, to: newPulse, pulses: pulses)
            return
        }
        if channel == "03" || channel == "08" {
            guard event.channel == "03" || event.channel == "08" else {
                throw BmsONEDocumentError.parse("BMSON timing stays on BPM or STOP")
            }
            guard let bpm = Double(event.token), bpm > 0 else {
                throw BmsONEDocumentError.parse("bpmNotes.v must be positive")
            }
            try document.moveBpmNote(from: oldPulse, to: newPulse, bpm: bpm)
            return
        }
        throw BmsONEDocumentError.parse("BMSON timing stays on BPM or STOP")
    }

    private func promptTimingValue(message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func moveNote(_ event: ChartEventSnapshot, channel: String, measure: Int, slot: Int, division: Int) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return moveNote(
                event,
                channel: channel,
                pulseY: BmsonChartAdapter.insertPulse(
                    measure: measure,
                    slot: slot,
                    division: division,
                    document: bmsonDocument
                )
            )
        }
        guard let session else { return false }
        do { try session.moveNote(event, toMeasure: measure, channel: channel, gridSlot: slot, gridDivision: division); refreshWindow(); return true }
        catch { presentErrorSheet(error); return false }
    }

    private func moveNote(_ event: ChartEventSnapshot, channel: String, pulseY: Int64) -> Bool {
        guard !isPresentingSheet, let bmsonDocument else { return false }
        do {
            if event.channel == "03" || event.channel == "08" || event.channel == "09" {
                try moveBmsonTiming(
                    document: bmsonDocument,
                    event: event,
                    channel: channel,
                    pulseY: pulseY
                )
            } else if let from = BmsonChartMapping.BgaLane.parse(channel: event.channel) {
                guard let to = BmsonChartMapping.BgaLane.parse(channel: channel), to == from else {
                    throw BmsONEDocumentError.parse("BMSON BGA stays on BGA / Layer / Poor")
                }
                guard let identifier = BmsonChartMapping.bmpId(token: event.token) else {
                    throw BmsONEDocumentError.parse("BMSON BGA id is missing")
                }
                let oldPulse = BmsonChartMapping.pulse(beat: event.beat, resolution: bmsonDocument.resolution)
                try bmsonDocument.moveBgaEvent(
                    lane: from,
                    from: oldPulse,
                    to: pulseY,
                    identifier: identifier
                )
            } else {
                let address = BmsonChartMapping.noteAddress(identity: event.sourceLine)
                let existing = address.flatMap { location -> IBMSBmsonNoteSnapshot? in
                    guard bmsonDocument.soundChannels.indices.contains(location.channelIndex),
                          bmsonDocument.soundChannels[location.channelIndex].notes.indices.contains(location.noteIndex)
                    else {
                        return nil
                    }
                    return bmsonDocument.soundChannels[location.channelIndex].notes[location.noteIndex]
                }
                let laneX: Int64
                if BmsonSoundLane.index(display: channel) != nil {
                    laneX = existing?.x ?? 0
                } else if let mapped = playableBmsonLaneX(channel) {
                    laneX = mapped
                } else {
                    return false
                }
                try bmsonDocument.replaceNote(
                    identity: event.sourceLine,
                    laneX: laneX,
                    pulseY: pulseY,
                    length: existing?.l ?? 0,
                    continueFlag: existing?.c ?? false
                )
            }
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveSelectedNotes(toDisplay display: String, shiftFirstOnly: Bool) -> Bool {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return false }
        let items = content.selectedChartItems()
        do {
            if let session {
                try session.moveNotes(
                    toDisplay: display,
                    events: Array(items.events),
                    longNotes: Array(items.longNotes),
                    shiftFirstOnly: shiftFirstOnly
                )
            } else if let bmsonDocument {
                try bmsonDocument.moveNotes(
                    identities: selectedBmsonNoteIdentities(),
                    toDisplay: display,
                    shiftFirstOnly: shiftFirstOnly,
                    mode: bmsonViewMode
                )
            } else {
                return false
            }
            refreshWindow()
            if shiftFirstOnly {
                previewEarliestMovedNote(items: items)
            }
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveSelectedNotesToBGM() -> Bool {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return false }
        let items = content.selectedChartItems()
        do {
            if let session {
                try session.moveNotesToBGM(
                    events: Array(items.events),
                    longNotes: Array(items.longNotes),
                    ntInput: content.ntInputEnabled
                )
                let needed = session.chartSnapshot.events.compactMap { ChartBGM.lane(display: $0.channel) }.max().map { $0 + 1 } ?? 0
                if needed > content.currentBGMColumnCount {
                    content.setBGMColumnCount(needed)
                }
            } else if let bmsonDocument {
                try bmsonDocument.moveNotesToBGM(
                    identities: selectedBmsonNoteIdentities(),
                    mode: bmsonViewMode
                )
            } else {
                return false
            }
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func previewEarliestMovedNote(
        items: (events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>)
    ) {
        let shorts = items.events.map { (beat: $0.beat, identity: $0.sourceLine, token: $0.token) }
        let longs = items.longNotes.map {
            (beat: $0.start.beat, identity: $0.start.sourceLine, token: $0.start.token)
        }
        let earliest = (shorts + longs).sorted {
            if $0.beat != $1.beat { return $0.beat < $1.beat }
            return $0.identity < $1.identity
        }.first
        guard let earliest else { return }
        if bmsonDocument != nil, earliest.identity > 0,
           let address = BmsonChartMapping.noteAddress(identity: earliest.identity) {
            previewNote(token: BmsonChartMapping.wavToken(channelIndex: address.channelIndex))
            return
        }
        previewNote(token: earliest.token)
    }

    private func mirrorSelectedNotes() {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        do {
            if let session {
                let items = content.selectedChartItems()
                try session.mirrorNotes(Array(items.events))
                try session.mirrorLongNotes(Array(items.longNotes))
            } else if let bmsonDocument {
                try bmsonDocument.mirrorNotes(
                    identities: selectedBmsonNoteIdentities(),
                    mode: bmsonViewMode
                )
            } else {
                return
            }
            refreshWindow()
        } catch {
            presentErrorSheet(error)
        }
    }

    private func applyWaveformColor(_ color: ThemeColor) {
        guard !isPresentingSheet else { return }
        var theme = editorThemeController.currentTheme
        theme.visual.bgmWaveform = color
        do {
            try editorThemeController.applyEditedTheme(theme, name: editorThemeController.currentThemeName)
        } catch {
            presentErrorSheet(error)
        }
    }

    private func applyWavEdit(_ edit: WavListEdit, synchronizeLabels: Bool) -> Bool {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return false }
        do {
            if let session {
                try session.applyWavEdit(edit, synchronizeLabels: synchronizeLabels)
            } else if let bmsonDocument {
                try bmsonDocument.applyWavEdit(edit, synchronizeLabels: synchronizeLabels)
            } else {
                return false
            }
            refreshWindow()
            content.selectWavSlots(edit.selected)
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func applyBmpEdit(_ edit: WavListEdit, synchronizeLabels: Bool) -> Bool {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return false }
        do {
            if let session {
                try session.applyBmpEdit(edit, synchronizeLabels: synchronizeLabels)
            } else if let bmsonDocument {
                try bmsonDocument.applyBmpEdit(edit, synchronizeLabels: synchronizeLabels)
            } else {
                return false
            }
            refreshWindow()
            content.selectBmpSlots(edit.selected)
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func modifySelectedNotes() {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        if let session {
            let items = content.selectedChartItems()
            let numeric = items.events.filter { ChartConvert.isNumericChannel($0.channel) }
            let labels = items.events.filter { !ChartConvert.isNumericChannel($0.channel) }
            if numeric.isEmpty && labels.isEmpty && items.longNotes.isEmpty { return }
            do {
                if !numeric.isEmpty {
                    guard let text = promptTimingValue(message: currentRuntime.promptEnterNumeric) else { return }
                    guard let decimal = ChartConvert.modifyNumeric(text) else { return }
                    try session.modifyTimingValues(Array(numeric), decimal: decimal)
                }
                if !labels.isEmpty || !items.longNotes.isEmpty {
                    guard let text = promptModifyLabel() else { return }
                    guard let token = ChartConvert.modifyLabel(text) else {
                        presentInvalidLabel()
                        return
                    }
                    try session.modifyNoteLabels(Array(labels), label: token)
                    for note in items.longNotes {
                        try session.eraseLongNote(note)
                        try session.insertLongNote(
                            channel: note.channel,
                            startMeasure: note.start.measure,
                            startNumerator: note.start.fractionNumerator,
                            startDenominator: note.start.fractionDenominator,
                            endMeasure: note.end.measure,
                            endNumerator: note.end.fractionNumerator,
                            endDenominator: note.end.fractionDenominator,
                            startToken: token,
                            endToken: note.encoding == "lnobj" ? note.end.token : token
                        )
                    }
                }
                refreshWindow()
            } catch {
                presentErrorSheet(error)
            }
            return
        }
        guard let bmsonDocument else { return }
        let items = content.selectedChartItems()
        var valueIdentities: [Int] = []
        var labelIdentities: [Int] = []
        for event in items.events {
            let channel = event.channel.uppercased()
            if channel == "03" || channel == "08" || channel == "09" {
                valueIdentities.append(event.sourceLine)
            } else if !ChartConvert.isNumericChannel(channel) {
                labelIdentities.append(event.sourceLine)
            }
        }
        for note in items.longNotes where note.start.sourceLine > 0 {
            labelIdentities.append(note.start.sourceLine)
        }
        if valueIdentities.isEmpty && labelIdentities.isEmpty { return }
        do {
            if !valueIdentities.isEmpty {
                guard let text = promptTimingValue(message: currentRuntime.promptEnterNumeric) else { return }
                if let decimal = ChartConvert.modifyNumeric(text), let parsed = Double(decimal) {
                    try bmsonDocument.modifyNotes(
                        valueIdentities: valueIdentities,
                        value: parsed,
                        labelIdentities: [],
                        label: nil
                    )
                }
            }
            if !labelIdentities.isEmpty {
                guard let text = promptModifyLabel() else {
                    refreshWindow()
                    return
                }
                guard let token = ChartConvert.modifyLabel(text) else {
                    presentInvalidLabel()
                    refreshWindow()
                    return
                }
                try bmsonDocument.modifyNotes(
                    valueIdentities: [],
                    value: nil,
                    labelIdentities: labelIdentities,
                    label: token
                )
            }
            refreshWindow()
        } catch {
            presentErrorSheet(error)
        }
    }

    private func doubleClickNote(_ event: ChartEventSnapshot) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        if ChartConvert.isNumericChannel(event.channel) {
            doubleClickNumeric(event)
        } else {
            doubleClickLabel(event: event, longNote: nil)
        }
    }

    private func doubleClickLongNote(_ note: LongNoteSnapshot) {
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        doubleClickLabel(event: nil, longNote: note)
    }

    private func doubleClickNumeric(_ event: ChartEventSnapshot) {
        if bmsonDocument != nil, event.channel.uppercased() == "SC" {
            return
        }
        guard let text = promptDoubleClickText(currentRuntime.doubleClickPrompt(channel: event.channel)) else {
            return
        }
        guard let value = ChartConvert.doubleClickNumeric(text: text, channel: event.channel) else {
            return
        }
        let decimal = ChartConvert.doubleClickNumericText(value)
        if let session {
            do {
                try session.withCompound {
                    try session.modifyTimingValues([event], decimal: decimal)
                    if ChartConvert.isHeaderBpm(event) {
                        let header = ChartTiming.storedBpmDecimal(decimal) ?? decimal
                        try session.setInitialBPM(header)
                    }
                }
                refreshWindow()
            } catch {
                presentErrorSheet(error)
            }
            return
        }
        guard let bmsonDocument, event.sourceLine > 0 else { return }
        do {
            try bmsonDocument.modifyNotes(
                valueIdentities: [event.sourceLine],
                value: value,
                labelIdentities: [],
                label: nil
            )
            refreshWindow()
        } catch {
            presentErrorSheet(error)
        }
    }

    private func doubleClickLabel(event: ChartEventSnapshot?, longNote: LongNoteSnapshot?) {
        let channel = event?.channel ?? longNote?.channel ?? "11"
        guard let text = promptDoubleClickText(currentRuntime.doubleClickPrompt(channel: channel)) else {
            return
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        guard let token = ChartConvert.modifyLabel(text) else {
            presentInvalidLabel()
            return
        }
        if let session {
            do {
                try session.withCompound {
                    if let event {
                        try session.modifyNoteLabels([event], label: token)
                    }
                    if let note = longNote {
                        try session.eraseLongNote(note)
                        try session.insertLongNote(
                            channel: note.channel,
                            startMeasure: note.start.measure,
                            startNumerator: note.start.fractionNumerator,
                            startDenominator: note.start.fractionDenominator,
                            endMeasure: note.end.measure,
                            endNumerator: note.end.fractionNumerator,
                            endDenominator: note.end.fractionDenominator,
                            startToken: token,
                            endToken: note.encoding == "lnobj" ? note.end.token : token
                        )
                    }
                }
                refreshWindow()
            } catch {
                presentErrorSheet(error)
            }
            return
        }
        guard let bmsonDocument else { return }
        var identities: [Int] = []
        if let event, event.sourceLine > 0 {
            identities.append(event.sourceLine)
        }
        if let note = longNote, note.start.sourceLine > 0 {
            identities.append(note.start.sourceLine)
        }
        guard !identities.isEmpty else { return }
        do {
            try bmsonDocument.modifyNotes(
                valueIdentities: [],
                value: nil,
                labelIdentities: identities,
                label: token
            )
            refreshWindow()
        } catch {
            presentErrorSheet(error)
        }
    }

    /// 对照 `InputBox(..., Me.Text)`。不先去空白，好留下 SCROLL 精确 `"0"`。
    private func promptDoubleClickText(_ message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.title = window?.title ?? ""
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func promptModifyLabel() -> String? {
        let alert = NSAlert()
        alert.messageText = currentRuntime.promptEnter
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func presentInvalidLabel() {
        let alert = NSAlert()
        alert.messageText = currentRuntime.invalidLabel
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.window.title = currentRuntime.err
        alert.runModal()
    }

    private func convertNote(_ event: ChartEventSnapshot, to channel: String) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.moveNote(event, toChannel: channel)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        } else if let bmsonDocument {
            do {
                try bmsonDocument.convertNote(
                    identity: event.sourceLine,
                    toChannel: channel,
                    mode: bmsonViewMode
                )
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        return false
    }

    private func eraseNote(_ event: ChartEventSnapshot) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            do {
                let pulse = BmsonChartMapping.pulse(beat: event.beat, resolution: bmsonDocument.resolution)
                if event.channel == "09" {
                    try bmsonDocument.eraseStopNote(pulseY: pulse)
                } else if event.channel == "03" || event.channel == "08" {
                    try bmsonDocument.eraseBpmNote(pulseY: pulse)
                } else if let lane = BmsonChartMapping.BgaLane.parse(channel: event.channel) {
                    try bmsonDocument.eraseBgaEvent(lane: lane, pulseY: pulse)
                } else {
                    try bmsonDocument.eraseNote(identity: event.sourceLine)
                }
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        guard let session else { return false }
        do { try session.eraseNote(event); refreshWindow(); return true }
        catch { presentErrorSheet(error); return false }
    }

    private func insertLongNote(
        channel: String,
        startMeasure: Int,
        startSlot: Int,
        endMeasure: Int,
        endSlot: Int,
        division: Int,
        token: String,
        endToken: String,
        continueFlag: Bool = false
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return insertLongNote(
                channel: channel,
                startPulse: BmsonChartAdapter.insertPulse(
                    measure: startMeasure,
                    slot: startSlot,
                    division: division,
                    document: bmsonDocument
                ),
                endPulse: BmsonChartAdapter.insertPulse(
                    measure: endMeasure,
                    slot: endSlot,
                    division: division,
                    document: bmsonDocument
                ),
                token: token,
                continueFlag: continueFlag
            )
        }
        guard let session else { return false }
        do {
            try session.insertLongNote(
                channel: channel,
                startMeasure: startMeasure,
                startSlot: startSlot,
                endMeasure: endMeasure,
                endSlot: endSlot,
                gridDivision: division,
                token: token,
                endToken: endToken
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func insertLongNote(
        channel: String,
        startPulse: Int64,
        endPulse: Int64,
        token: String,
        continueFlag: Bool
    ) -> Bool {
        guard !isPresentingSheet, let bmsonDocument else { return false }
        do {
            bmsonDocument.selectedChannelIndex = BmsonChartMapping.channelIndex(wavToken: token)
            try bmsonDocument.insertNote(
                laneX: BmsonChartMapping.laneX(forChannel: channel, mode: bmsonViewMode),
                pulseY: min(startPulse, endPulse),
                length: abs(endPulse - startPulse),
                continueFlag: continueFlag
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveLongNote(_ note: LongNoteSnapshot, channel: String, measure: Int, slot: Int, division: Int) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return moveLongNote(
                note,
                channel: channel,
                pulseY: BmsonChartAdapter.insertPulse(
                    measure: measure,
                    slot: slot,
                    division: division,
                    document: bmsonDocument
                )
            )
        }
        guard let session else { return false }
        do {
            try session.moveLongNote(note, toMeasure: measure, channel: channel, gridSlot: slot, gridDivision: division)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveLongNote(_ note: LongNoteSnapshot, channel: String, pulseY: Int64) -> Bool {
        guard !isPresentingSheet, let bmsonDocument else { return false }
        do {
            let length = BmsonChartMapping.pulse(
                beat: note.end.beat - note.start.beat,
                resolution: bmsonDocument.resolution
            )
            try bmsonDocument.replaceNote(
                identity: note.start.sourceLine,
                laneX: BmsonChartMapping.laneX(forChannel: channel, mode: bmsonViewMode),
                pulseY: pulseY,
                length: max(0, length)
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveLongNoteStart(_ note: LongNoteSnapshot, measure: Int, slot: Int, division: Int) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return moveLongNoteStart(
                note,
                pulseY: BmsonChartAdapter.insertPulse(
                    measure: measure,
                    slot: slot,
                    division: division,
                    document: bmsonDocument
                )
            )
        }
        guard let session else { return false }
        do {
            try session.moveLongNoteStart(note, toMeasure: measure, gridSlot: slot, gridDivision: division)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func moveLongNoteStart(_ note: LongNoteSnapshot, pulseY: Int64) -> Bool {
        guard !isPresentingSheet, let bmsonDocument else { return false }
        do {
            let end = BmsonChartMapping.pulse(beat: note.end.beat, resolution: bmsonDocument.resolution)
            try bmsonDocument.replaceNote(
                identity: note.start.sourceLine,
                laneX: BmsonChartMapping.laneX(forChannel: note.channel, mode: bmsonViewMode),
                pulseY: min(pulseY, end),
                length: abs(end - pulseY)
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func resizeLongNote(_ note: LongNoteSnapshot, measure: Int, slot: Int, division: Int) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            return resizeLongNote(
                note,
                pulseY: BmsonChartAdapter.insertPulse(
                    measure: measure,
                    slot: slot,
                    division: division,
                    document: bmsonDocument
                )
            )
        }
        guard let session else { return false }
        do {
            try session.resizeLongNote(note, endMeasure: measure, endSlot: slot, gridDivision: division)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func resizeLongNote(_ note: LongNoteSnapshot, pulseY: Int64) -> Bool {
        guard !isPresentingSheet, let bmsonDocument else { return false }
        do {
            let start = BmsonChartMapping.pulse(beat: note.start.beat, resolution: bmsonDocument.resolution)
            try bmsonDocument.replaceNote(
                identity: note.start.sourceLine,
                laneX: BmsonChartMapping.laneX(forChannel: note.channel, mode: bmsonViewMode),
                pulseY: min(start, pulseY),
                length: abs(pulseY - start)
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func eraseLongNote(_ note: LongNoteSnapshot) -> Bool {
        guard !isPresentingSheet else { return false }
        if let bmsonDocument {
            do {
                try bmsonDocument.eraseNote(identity: note.start.sourceLine)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        guard let session else { return false }
        do {
            try session.eraseLongNote(note)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func convertShortNotesToLong(_ start: ChartEventSnapshot, end: ChartEventSnapshot) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.convertShortNotesToLong(start: start, end: end)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        } else if let bmsonDocument {
            do {
                try bmsonDocument.convertShortPairToLong(
                    startIdentity: start.sourceLine,
                    endIdentity: end.sourceLine
                )
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        return false
    }

    private func convertShortNoteToLongEndpoint(_ event: ChartEventSnapshot) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.convertShortNoteToLongEndpoint(event)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        } else if let bmsonDocument {
            bmsonDocument.convertShortNoteToLongEndpoint(identity: event.sourceLine)
            return true
        }
        return false
    }

    private func convertLongEndpointToShort(_ event: ChartEventSnapshot) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.convertLongEndpointToShort(event)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        } else if let bmsonDocument {
            bmsonDocument.convertLongEndpointToShort(identity: event.sourceLine)
            return true
        }
        return false
    }

    private func copyNoteAtVPosition(_ event: ChartEventSnapshot, channel: String, vPosition: Double) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.copyNote(event, toChannel: channel, vPosition: vPosition)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        if let document = bmsonDocument {
            return duplicateBmsonNotes(
                document: document,
                notes: [(channel: channel, vPosition: vPosition, token: event.token, length: 0)]
            )
        }
        return false
    }

    private func copyLongNoteAtVPosition(
        _ note: LongNoteSnapshot,
        channel: String,
        vPosition: Double,
        length: Double
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.copyLongNote(note, toChannel: channel, vPosition: vPosition, length: length)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        if let document = bmsonDocument {
            return duplicateBmsonNotes(
                document: document,
                notes: [(channel: channel, vPosition: vPosition, token: note.start.token, length: length)]
            )
        }
        return false
    }

    private func copyNotesAtVPosition(
        shorts: [ChartDuplicate.ShortCopy],
        longs: [ChartDuplicate.LongCopy]
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                for copy in shorts {
                    try session.copyNote(copy.event, toChannel: copy.channel, vPosition: copy.vPosition)
                }
                for copy in longs {
                    try session.copyLongNote(
                        copy.note,
                        toChannel: copy.channel,
                        vPosition: copy.vPosition,
                        length: copy.length
                    )
                }
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        if let document = bmsonDocument {
            var notes: [(channel: String, vPosition: Double, token: String, length: Double)] = []
            notes.append(contentsOf: shorts.map {
                (channel: $0.channel, vPosition: $0.vPosition, token: $0.event.token, length: 0)
            })
            notes.append(contentsOf: longs.map {
                (channel: $0.channel, vPosition: $0.vPosition, token: $0.note.start.token, length: $0.length)
            })
            return duplicateBmsonNotes(document: document, notes: notes)
        }
        return false
    }

    private func moveNotesAtVPosition(
        shorts: [ChartDuplicate.ShortCopy],
        longs: [ChartDuplicate.LongCopy]
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        if let document = bmsonDocument {
            do {
                try document.moveNotesAtVPosition(shorts: shorts, longs: longs, mode: bmsonViewMode)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        if let session {
            do {
                try session.moveNotesAtVPosition(shorts: shorts, longs: longs)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        return false
    }

    /// 可玩列用当前 View Mode 的 `channelToLane`。没有车道则跳过，不用 `laneX` 缺键默认 0。
    private func playableBmsonLaneX(_ channel: String) -> Int64? {
        let dest = channel.uppercased()
        if dest == "01" || ChartBGM.lane(display: dest) != nil {
            return 0
        }
        let visible = ChartLayout.displayChannel(dest)
        if visible == "01" || ChartBGM.lane(display: visible) != nil {
            return 0
        }
        return bmsonViewMode.channelToLane[visible]
    }

    private func duplicateBmsonNotes(
        document: BmsONEDocument,
        notes: [(channel: String, vPosition: Double, token: String, length: Double)]
    ) -> Bool {
        do {
            try document.duplicateNotes(notes)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func toggleNTInput(_ becomeNT: Bool) {
        guard !isPresentingSheet else { return }
        if becomeNT == content.ntInputEnabled { return }
        if let session, bmsonDocument == nil {
            do {
                try session.convertNTInput(becomeNT: becomeNT)
                content.setNTInputEnabled(becomeNT)
                refreshWindow()
                content.applySelection(events: [], longNotes: [])
            } catch {
                presentErrorSheet(error)
            }
            return
        }
        content.setNTInputEnabled(becomeNT)
        refreshWindow()
    }

    private func pasteClipboard(_ text: String, baseVPosition: Double, ntInput: Bool) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            let beforeEvents = Set(session.chartSnapshot.events)
            let beforeLongs = Set(session.longNoteSnapshot.notes)
            do {
                try session.pasteClipboard(text, baseVPosition: baseVPosition, ntInput: ntInput)
                let addedEvents = Set(session.chartSnapshot.events.filter { !beforeEvents.contains($0) })
                let addedLongs = Set(session.longNoteSnapshot.notes.filter { !beforeLongs.contains($0) })
                refreshWindow()
                content.applySelection(events: addedEvents, longNotes: addedLongs)
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        if bmsonDocument != nil {
            return pasteBmsonClipboard(text, baseVPosition: baseVPosition, ntInput: ntInput)
        }
        return false
    }

    private func pasteBmsonClipboard(_ text: String, baseVPosition: Double, ntInput: Bool) -> Bool {
        guard let document = bmsonDocument else { return false }
        do {
            try document.pasteClipboard(text, baseVPosition: baseVPosition, ntInput: ntInput)
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    /// 打开 BMSON 时 Cut / Delete 一批一笔。BMS 仍逐条擦。
    private func eraseSelection(
        events: Set<ChartEventSnapshot>,
        longNotes: Set<LongNoteSnapshot>
    ) -> Bool {
        guard !isPresentingSheet else { return false }
        if let document = bmsonDocument {
            return eraseBmsonSelection(events: events, longNotes: longNotes, document: document)
        }
        var changed = false
        for note in longNotes {
            if eraseLongNote(note) { changed = true }
        }
        for event in events {
            if eraseNote(event) { changed = true }
        }
        return changed
    }

    private func eraseBmsonSelection(
        events: Set<ChartEventSnapshot>,
        longNotes: Set<LongNoteSnapshot>,
        document: BmsONEDocument
    ) -> Bool {
        var identities: [Int] = []
        var bpmPulses: [Int64] = []
        var stopPulses: [Int64] = []
        var bgaEvents: [(lane: BmsonChartMapping.BgaLane, pulseY: Int64)] = []
        for note in longNotes where note.start.sourceLine > 0 {
            identities.append(note.start.sourceLine)
        }
        for event in events {
            let pulse = BmsonChartMapping.pulse(beat: event.beat, resolution: document.resolution)
            if event.channel == "09" {
                stopPulses.append(pulse)
            } else if event.channel == "03" || event.channel == "08" {
                bpmPulses.append(pulse)
            } else if let lane = BmsonChartMapping.BgaLane.parse(channel: event.channel) {
                bgaEvents.append((lane: lane, pulseY: pulse))
            } else if event.sourceLine > 0 {
                identities.append(event.sourceLine)
            }
        }
        do {
            try document.eraseNotes(
                identities: identities,
                bpmPulses: bpmPulses,
                stopPulses: stopPulses,
                bgaEvents: bgaEvents
            )
            refreshWindow()
            return true
        } catch {
            presentErrorSheet(error)
            return false
        }
    }

    private func convertLongNoteToShort(_ note: LongNoteSnapshot, keepEnd: Bool) -> Bool {
        guard !isPresentingSheet else { return false }
        if let session {
            do {
                try session.convertLongNoteToShort(note, keepEnd: keepEnd)
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        } else if let bmsonDocument {
            do {
                try bmsonDocument.convertLongToShort(
                    identity: note.start.sourceLine,
                    keepEnd: keepEnd
                )
                refreshWindow()
                return true
            } catch {
                presentErrorSheet(error)
                return false
            }
        }
        return false
    }

    private func configureFindActions() {
        findWindowController.onSelect = { [weak self] query in self?.applyFindSelection(query, unselect: false) }
        findWindowController.onUnselect = { [weak self] query in self?.applyFindSelection(query, unselect: true) }
        findWindowController.onDelete = { [weak self] query in self?.deleteMatchingNotes(query) }
        findWindowController.onReplaceLabel = { [weak self] query in self?.replaceMatchingLabels(query) }
        findWindowController.onReplaceValue = { [weak self] query in self?.replaceMatchingValues(query) }
    }

    private func currentQueryNotes() -> [QueryNote] {
        let selection = content.selectedChartItems()
        var notes: [QueryNote]
        let headerBPMText: String
        let lnObjToken: String
        if let bmsonDocument {
            let shown = shownBmsonChannels(in: bmsonDocument)
            let source = BmsonChartAdapter.display(
                from: bmsonDocument,
                shownChannels: shown,
                viewMode: bmsonViewMode
            )
            notes = LegacyChartQuery.collect(
                chart: source.chart,
                longNotes: source.longNotes,
                timing: .unavailable,
                selectedEvents: selection.events,
                selectedLongNotes: selection.longNotes,
                bmsonLabels: true
            )
            headerBPMText = String(bmsonDocument.initialBpm)
            lnObjToken = source.longNotes.lnobjToken
        } else {
            notes = LegacyChartQuery.collect(
                chart: session?.chartSnapshot ?? .empty,
                longNotes: session?.longNoteSnapshot ?? .empty,
                timing: session?.timingSnapshot ?? .unavailable,
                selectedEvents: selection.events,
                selectedLongNotes: selection.longNotes
            )
            headerBPMText = session?.timingSnapshot.initialBPMDecimal ?? "120"
            lnObjToken = session?.longNoteSnapshot.lnobjToken ?? ""
        }
        let headerValue = Int(((Double(headerBPMText) ?? 120) * 10_000).rounded())
        let lnObj = BMS36Token.decode(lnObjToken)
        var body = [
            ErrorCheckNote(vPosition: -1, columnIndex: EditorColumn.bpm, value: headerValue, length: 0, hidden: false)
        ]
        body.append(contentsOf: notes.map { note in
            let value: Int
            if let numeric = note.numericValue {
                value = Int((numeric * 10_000).rounded())
            } else {
                value = BMS36Token.decode(note.labelToken) * 10_000
            }
            let vPosition: Double
            let length: Double
            switch note.source {
            case .event(let event):
                vPosition = TimeSelection.vPosition(beat: event.beat)
                length = 0
            case .longNote(let longNote):
                vPosition = TimeSelection.vPosition(beat: longNote.start.beat)
                length = TimeSelection.vPosition(beat: longNote.end.beat) - vPosition
            case .timing(let event):
                let beat = Double(event.beat.numerator) / Double(max(1, event.beat.denominator))
                vPosition = TimeSelection.vPosition(beat: beat)
                length = 0
            }
            return ErrorCheckNote(
                vPosition: vPosition,
                columnIndex: note.columnIndex,
                value: value,
                length: length,
                hidden: note.isHidden
            )
        })
        let marked = LegacyErrorCheck.markNT(body, lnObj: lnObj)
        for index in notes.indices {
            notes[index].hasError = marked[index + 1].hasError
        }
        return notes
    }

    private func currentStatistics() -> StatisticsMatrix {
        LegacyChartQuery.statistics(from: currentQueryNotes(), ntInput: content.ntInputEnabled)
    }

    private func applyFindSelection(_ query: FindQuery, unselect: Bool) -> String? {
        let notes = unselect
            ? LegacyChartQuery.applyUnselect(currentQueryNotes(), query: query)
            : LegacyChartQuery.applySelect(currentQueryNotes(), query: query)
        let selected = LegacyChartQuery.selectedSets(from: notes)
        content.applySelection(events: selected.events, longNotes: selected.longNotes)
        return nil
    }

    private func deleteMatchingNotes(_ query: FindQuery) -> String? {
        guard !isPresentingSheet else { return "Open or create a document before deleting notes." }
        if let bmsonDocument {
            let matches = LegacyChartQuery.matchesForEdit(currentQueryNotes(), query: query)
            do {
                try bmsonDocument.deleteFindMatches(identities: findIdentities(from: matches))
                refreshWindow()
                return nil
            } catch {
                refreshWindow()
                return error.localizedDescription
            }
        }
        guard let session else { return "Open or create a document before deleting notes." }
        let matches = LegacyChartQuery.matchesForEdit(currentQueryNotes(), query: query)
        do {
            for note in matches {
                switch note.source {
                case .longNote(let longNote):
                    try session.eraseLongNote(longNote)
                case .timing(let event):
                    try session.eraseTimingEvent(event)
                case .event(let event):
                    try session.eraseNote(event)
                }
            }
            refreshWindow()
            return nil
        } catch {
            refreshWindow()
            return error.localizedDescription
        }
    }

    private func replaceMatchingLabels(_ query: FindQuery) -> String? {
        guard !isPresentingSheet else { return "Open or create a document before replacing labels." }
        if let bmsonDocument {
            let matches = LegacyChartQuery.matchesForEdit(currentQueryNotes(), query: query)
                .filter { !$0.isNumeric }
            do {
                try bmsonDocument.replaceFindLabels(
                    identities: findIdentities(from: matches),
                    label: query.replaceLabel
                )
                refreshWindow()
                return nil
            } catch {
                refreshWindow()
                return error.localizedDescription
            }
        }
        guard let session else { return "Open or create a document before replacing labels." }
        let matches = LegacyChartQuery.matchesForEdit(currentQueryNotes(), query: query)
            .filter { !$0.isNumeric }
        var events: [ChartEventSnapshot] = []
        var longNotes: [LongNoteSnapshot] = []
        for note in matches {
            switch note.source {
            case .event(let event):
                events.append(event)
            case .longNote(let longNote):
                longNotes.append(longNote)
            case .timing:
                break
            }
        }
        do {
            try session.replaceFindLabels(events: events, longNotes: longNotes, label: query.replaceLabel)
            refreshWindow()
            return nil
        } catch {
            refreshWindow()
            return error.localizedDescription
        }
    }

    private func replaceMatchingValues(_ query: FindQuery) -> String? {
        guard !isPresentingSheet else { return "Open or create a document before replacing values." }
        if let bmsonDocument {
            let matches = LegacyChartQuery.matchesForEdit(currentQueryNotes(), query: query)
                .filter(\.isNumeric)
            do {
                try bmsonDocument.replaceFindValues(
                    identities: findIdentities(from: matches),
                    value: query.replaceValue
                )
                refreshWindow()
                return nil
            } catch {
                refreshWindow()
                return error.localizedDescription
            }
        }
        guard let session else { return "Open or create a document before replacing values." }
        let matches = LegacyChartQuery.matchesForEdit(currentQueryNotes(), query: query)
            .filter(\.isNumeric)
        var timing: [TimingEventSnapshot] = []
        var events: [ChartEventSnapshot] = []
        var skipped = 0
        for note in matches {
            switch note.source {
            case .timing(let event):
                timing.append(event)
            case .event(let event):
                events.append(event)
            case .longNote:
                skipped += 1
            }
        }
        do {
            try session.replaceFindValues(
                timing: timing,
                events: events,
                decimal: formatFindValue(query.replaceValue)
            )
            refreshWindow()
            return skipped == 0 ? nil : "Value replace skipped \(skipped) notes that are not BPM, STOP, or SCROLL."
        } catch {
            refreshWindow()
            return error.localizedDescription
        }
    }

    /// BMSON 身份在 `sourceLine`。第一次 erase 后旧 identity 会失效，所以先收集再一次性写回。
    private func findIdentities(from notes: [QueryNote]) -> [Int] {
        notes.compactMap { note in
            switch note.source {
            case .event(let event):
                return event.sourceLine
            case .longNote(let longNote):
                return longNote.start.sourceLine
            case .timing:
                return nil
            }
        }
    }

    private func formatFindValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func configureTimingActions() {
        timingWindowController.applyInitialBPM = { [weak self] decimal in
            self?.performTimingEdit { session in
                try session.setInitialBPM(decimal)
            }
        }
        timingWindowController.scaleMeasure = { [weak self] measure, decimal in
            self?.performTimingEdit { session in
                try session.setMeasureRatio(measure: measure, decimal: decimal)
            }
        }
        timingWindowController.addEvent = { [weak self] measure, channel, fraction, decimal in
            self?.performTimingEdit { session in
                try session.insertTimingEvent(
                    measure: measure,
                    channel: channel,
                    fraction: fraction,
                    decimal: decimal
                )
            }
        }
        timingWindowController.replaceEvent = { [weak self] event, decimal in
            self?.performTimingEdit { session in
                try session.replaceTimingEvent(event, decimal: decimal)
            }
        }
        timingWindowController.deleteEvent = { [weak self] event in
            self?.performTimingEdit { session in
                try session.eraseTimingEvent(event)
            }
        }
    }

    private func performTimingEdit(_ operation: (DocumentSession) throws -> Void) -> String? {
        guard !isPresentingSheet else {
            return "Finish the open dialog before editing timing."
        }
        guard content.commitActiveMetadataEditor() else {
            return "Finish or correct the pending metadata edit before changing timing."
        }
        guard let session else {
            return "Open or create a document before editing timing."
        }
        do {
            try operation(session)
            refreshWindow()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func saveCurrentDocument(forceSaveAs: Bool, completion: @escaping (Bool) -> Void) {
        if let bmsonDocument {
            if !forceSaveAs, let path = bmsonDocument.filePath {
                write(bmsonDocument, to: URL(fileURLWithPath: path), completion: completion)
                return
            }
            presentSavePanel(for: bmsonDocument, completion: completion)
            return
        }
        guard let session else { completion(false); return }
        if !forceSaveAs, let destination = session.fileURL {
            write(session, to: destination, completion: completion)
            return
        }
        presentSavePanel(for: session, completion: completion)
    }

    private func presentSavePanel(for session: DocumentSession, completion: @escaping (Bool) -> Void) {
        guard let window, beginSheet() else {
            completion(false)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = FileTypes.allowed
        panel.nameFieldStringValue = session.fileURL?.lastPathComponent ?? "Untitled.bms"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let destination = panel.url else {
                    completion(false)
                    return
                }
                self.write(session, to: destination, completion: completion)
            }
        }
    }

    private func presentSavePanel(for document: BmsONEDocument, completion: @escaping (Bool) -> Void) {
        guard let window, beginSheet() else {
            completion(false)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = FileTypes.bmson
        panel.nameFieldStringValue = document.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "untitled.bmson"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                guard response == .OK, let destination = panel.url else {
                    completion(false)
                    return
                }
                self.write(document, to: destination, completion: completion)
            }
        }
    }

    private func write(_ document: BmsONEDocument, to destination: URL, completion: (Bool) -> Void) {
        do {
            try document.save(to: destination)
            rememberRecent(destination)
            refreshWindow()
            if editorSettingsStore.settings.beepWhileSaved {
                NSSound.beep()
            }
            completion(true)
        } catch {
            completion(false)
            presentErrorSheet(error)
        }
    }

    private func write(_ session: DocumentSession, to destination: URL, completion: (Bool) -> Void) {
        do {
            let settings = editorSettingsStore.settings
            let report = try session.save(
                to: destination,
                ntInput: content.ntInputEnabled,
                gridLimit: settings.bmsGridLimit
            )
            lastBmsInitPath = destination.deletingLastPathComponent().path
            presentSaveWarnings(report, bpm1296: settings.bpm1296, stop1296: settings.stop1296)
            rememberRecent(destination)
            refreshWindow()
            if settings.beepWhileSaved {
                NSSound.beep()
            }
            completion(true)
        } catch {
            completion(false)
            presentErrorSheet(error)
        }
    }

    private func presentSaveWarnings(
        _ report: DocumentSession.SaveBmsReport,
        bpm1296: Bool,
        stop1296: Bool
    ) {
        let labels = Legacy1296Write.MessageLabels(
            warning: currentRuntime.saveWarning,
            noteOverlap: currentRuntime.noteOverlapError,
            bpmOverflow: currentRuntime.bpmOverflowError,
            stopOverflow: currentRuntime.stopOverflowError,
            scrollOverflow: currentRuntime.scrollOverflowError,
            savedFileWillContainErrors: currentRuntime.savedFileWillContainErrors
        )
        for message in Legacy1296Write.saveMessages(
            overlapping: report.overlapping,
            bpmCount: report.bpmCount,
            stopCount: report.stopCount,
            scrollCount: report.scrollCount,
            bpm1296: bpm1296,
            stop1296: stop1296,
            labels: labels
        ) {
            let alert = NSAlert()
            alert.messageText = labels.warning.trimmingCharacters(in: .whitespaces)
            alert.informativeText = String(
                message.dropFirst(labels.warning.count).trimmingCharacters(in: .newlines)
            )
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func rememberRecent(_ url: URL) {
        rememberRecentPath(url.path)
    }

    private func rememberCurrentDocumentPath() {
        if let url = session?.fileURL {
            rememberRecent(url)
            return
        }
        if let path = bmsonDocument?.filePath, !path.isEmpty {
            rememberRecentPath(path)
        }
    }

    private func rememberRecentPath(_ path: String) {
        recentSlots = LegacyRecent.insert(path, into: recentSlots)
        LegacyRecent.save(recentSlots)
        applyRecentMenus()
    }

    private func openRecentSlot(_ index: Int) {
        guard recentSlots.indices.contains(index) else { return }
        let path = recentSlots[index]
        guard LegacyRecent.isEnabled(path) else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            presentCannotFind(path)
            return
        }
        guard !isPresentingSheet, content.commitActiveMetadataEditor() else { return }
        resolveDiscardingChanges { [weak self] approved in
            guard approved, let self else { return }
            self.openRecentPath(path)
        }
    }

    private func openRecentPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        switch LegacyRecent.kind(path: path) {
        case .bms:
            loadBMS(from: url, remember: false)
        case .ibmsc:
            loadIBMSC(from: url, remember: false)
        case .bmson:
            loadBmson(from: url, remember: false)
        case .unsupported:
            break
        }
    }

    private func presentCannotFind(_ path: String) {
        let alert = NSAlert()
        alert.messageText = currentRuntime.cannotFindMessage(path: path)
        alert.alertStyle = .critical
        if let window, beginSheet() {
            alert.beginSheetModal(for: window) { [weak self] _ in
                self?.finishSheet()
            }
        } else {
            alert.runModal()
        }
    }

    /// 点包立刻换已经接上的关脏谱、BMS 底栏和对话框句子。Default 不走这里。
    private func applyRuntimeLocale(_ runtime: LegacyLocale.RuntimeStrings) {
        currentRuntime = runtime
        content.applyLocaleStatusLabels(
            length: runtime.length,
            longNote: runtime.longNote,
            hidden: runtime.hidden,
            error: runtime.error
        )
        if findWindowController.window?.isVisible != true {
            findWindowController.invalidLabelText = runtime.invalidLabel
        }
    }

    /// 关脏谱正文用 runtime，不要写死 `MainWindowChrome.saveOnExitPrompt`。
    private func saveOnExitMessage(isSystemShutdown: Bool) -> String {
        isSystemShutdown ? currentRuntime.saveOnExit1 : currentRuntime.saveOnExit
    }

    /// 对照 `ClosingPopSave` / `Form1_FormClosing`：干净不问。脏了弹 `SaveOnExit`，标题是当前主窗标题。
    private func resolveDiscardingChanges(completion: @escaping (Bool) -> Void) {
        let isSaved = !hasUnsavedChanges
        if MainWindowChrome.saveOnExitDecision(isSaved: isSaved, choice: .yes) == .proceedClean {
            completion(true)
            return
        }
        guard let window, beginSheet() else {
            completion(false)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = saveOnExitMessage(isSystemShutdown: isSystemShutdownQuit)
        alert.addButton(withTitle: MainWindowChrome.saveOnExitYes)
        alert.addButton(withTitle: MainWindowChrome.saveOnExitNo)
        alert.addButton(withTitle: MainWindowChrome.saveOnExitCancel)
        alert.window.title = window.title
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.finishSheet {
                let choice: SaveOnExitChoice
                switch response {
                case .alertFirstButtonReturn:
                    choice = .yes
                case .alertSecondButtonReturn:
                    choice = .no
                default:
                    choice = .cancel
                }
                switch MainWindowChrome.saveOnExitDecision(isSaved: false, choice: choice) {
                case .proceedSave:
                    self.saveCurrentDocument(forceSaveAs: false, completion: completion)
                case .proceedDiscard:
                    completion(true)
                case .abort, .proceedClean:
                    completion(false)
                }
            }
        }
    }

    /// 关机 / 注销能从 `willPowerOff` 或退出 Apple Event 的 reason 看出来。看不出来仍用第一句。
    private var isSystemShutdownQuit: Bool {
        if systemIsPoweringOff { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication) else { return false }
        let why = AEKeyword(0x7768793F) // 'why?' == keyAEQuitReason
        guard let reason = event.paramDescriptor(forKeyword: why) else { return false }
        switch reason.enumCodeValue {
        case 0x73687574, 0x72657374, 0x726C676F: // 'shut' / 'rest' / 'rlgo'
            return true
        default:
            return false
        }
    }

    private func presentErrorSheet(_ error: Error) {
        if isPresentingSheet || !queuedErrors.isEmpty {
            queuedErrors.append(error)
            return
        }
        showErrorSheet(error)
    }

    private func showErrorSheet(_ error: Error) {
        guard let window, beginSheet() else {
            queuedErrors.append(error)
            return
        }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window) { [weak self] _ in
            guard let self else { return }
            self.finishSheet()
        }
    }

    private func beginTerminationDecision() {
        resolveDiscardingChanges { [weak self] approved in
            self?.replyToTermination(allow: approved)
        }
    }

    private func replyToTermination(allow: Bool) {
        guard terminationReplyPending else { return }
        terminationReplyPending = false
        DispatchQueue.main.async {
            NSApp.reply(toApplicationShouldTerminate: allow)
        }
    }

    @discardableResult
    private func beginSheet() -> Bool {
        guard !isPresentingSheet else { return false }
        isPresentingSheet = true
        return true
    }

    private func finishSheet(_ completion: () -> Void = {}) {
        isPresentingSheet = false
        completion()
        guard !isPresentingSheet else { return }
        guard let error = queuedErrors.first else { return }
        queuedErrors.removeFirst()
        showErrorSheet(error)
    }

    private func scheduleApprovedWindowClose() {
        // Closing from inside windowShouldClose would re-enter the delegate before
        // AppKit has finished the current close request.
        allowWindowClose = true
        skipNextTerminationPrompt = true
        DispatchQueue.main.async { [weak self] in
            self?.window?.performClose(nil)
        }
    }

    @objc func chooseEncoding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let encoding = MetadataEncoding(rawValue: raw) else { return }
        _ = selectEncoding(encoding)
    }

    private func rebuildEncodingMenu() {
        encodingMenu.removeAllItems()
        let encodings = session?.availableEncodings ?? MetadataEncoding.allCases
        for encoding in encodings {
            let item = encodingMenu.addItem(withTitle: encoding.rawValue, action: #selector(chooseEncoding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = encoding.rawValue
            item.state = encoding == session?.metadataEncoding ? .on : .off
        }
        if encodings.isEmpty {
            let item = encodingMenu.addItem(withTitle: "Unavailable", action: nil, keyEquivalent: "")
            item.isEnabled = false
        }
    }

    private func applyIndexedTimingRadix(_ settings: EditorSettings) {
        IBMSDocumentBridge.setIndexedTimingRadix(bpm: settings.bpm1296, stop: settings.stop1296)
    }

    private func refreshWindow(
        resetChartPosition: Bool = false,
        waveformInputMayHaveChanged: Bool = true
    ) {
        if let bmsonDocument {
            let shown = shownBmsonChannels(in: bmsonDocument)
            lastShownBmsonChannels = shown ?? []
            let source = BmsonChartAdapter.display(
                from: bmsonDocument,
                shownChannels: shown,
                viewMode: bmsonViewMode
            )
            content.pushBmsonViewMode(bmsonViewMode)
            content.pushBmsonSoundLaneMode(bmsonSoundLaneMode)
            content.pushBmsonStatus(
                applies: true,
                resolution: bmsonDocument.resolution,
                bars: BmsonChartAdapter.barPulses(from: bmsonDocument),
                explicitBars: ([Int64(0)] + bmsonDocument.lines.map(\.y)).sorted(),
                initBpm: bmsonDocument.initialBpm,
                bpmNotes: bmsonDocument.bpmNotes.map { (y: $0.y, v: $0.v) },
                viewMode: bmsonViewMode
            )
            content.update(document: nil, chartSource: source, resetChartPosition: resetChartPosition)
            content.pushBmsonNoteDarken(applies: true, currentChannel: currentBmsonChannelIndex() ?? 0)
            content.pushBmsonSnap(
                applies: true,
                resolution: bmsonDocument.resolution,
                bars: BmsonChartAdapter.barPulses(from: bmsonDocument)
            )
            content.pushBmsonZoom(applies: true, resolution: bmsonDocument.resolution)
            refreshMasterWaveform(inputMayHaveChanged: waveformInputMayHaveChanged)
            refreshLaneWaveform()
            content.pushBmsonFooter(visible: true)
            refreshBmsonChannelInfo()
            window?.isDocumentEdited = bmsonDocument.isModified
            window?.representedURL = bmsonDocument.filePath.map { URL(fileURLWithPath: $0) }
            applyWindowTitle()
        } else {
            content.pushBmsonViewMode(nil)
            content.pushBmsonSoundLaneMode(nil)
            content.pushBmsonStatus(applies: false)
            content.update(
                document: session,
                resetChartPosition: resetChartPosition,
                extraCanUndo: ibmscSnapshot?.undo.canUndo == true,
                extraCanRedo: ibmscSnapshot?.undo.canRedo == true
            )
            content.pushBmsonSnap(applies: false, resolution: 240, bars: [])
            content.pushBmsonZoom(applies: false, resolution: 240)
            masterWaveform = nil
            masterWaveformKey = ""
            content.pushBmsonMaster(applies: false, waveform: nil)
            content.pushBmsonLaneWaveform(nil)
            content.pushBmsonFooter(visible: false)
            refreshBmsonChannelInfo()
            window?.isDocumentEdited = session?.dirty == true
            window?.representedURL = session?.fileURL
            applyWindowTitle()
        }
        rebuildEncodingMenu()
        if timingWindowController.window?.isVisible == true {
            updateTimingWindow()
        }
        refreshSelectedObjects()
    }

    private func refreshMasterWaveform(force: Bool = false, inputMayHaveChanged: Bool = true) {
        guard let document = bmsonDocument else {
            masterWaveform = nil
            masterWaveformKey = ""
            content.pushBmsonMaster(applies: false, waveform: nil)
            return
        }
        let prefs = BmsONEPreferences.load()
        guard prefs.canShowMasterLane || prefs.canShowMiniMap else {
            masterWaveform = nil
            masterWaveformKey = ""
            content.pushBmsonMaster(applies: true, waveform: nil)
            return
        }
        // 选择、焦点和元数据不会改变音频/时序输入，直接复用已混好的结果。
        if !force, !inputMayHaveChanged, masterWaveform != nil {
            content.pushBmsonMaster(applies: true, waveform: masterWaveform)
            return
        }
        let key = masterMixKey(document)
        if !force, key == masterWaveformKey, masterWaveform != nil {
            content.pushBmsonMaster(applies: true, waveform: masterWaveform)
            return
        }
        let directory = document.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        masterWaveform = BmsONEMasterWaveformCache.make(
            initBpm: document.initialBpm,
            resolution: document.resolution,
            bpmNotes: document.bpmNotes.map { (y: $0.y, v: $0.v) },
            stopNotes: document.stopNotes.map { (y: $0.y, v: $0.v) },
            lengthNotes: document.soundChannels.flatMap { channel in
                channel.notes.map { (y: $0.y, l: $0.l) }
            },
            channels: document.soundChannels.map { channel in
                (
                    notes: channel.notes.map { (y: $0.y, c: $0.c) },
                    wave: loadMasterWave(named: channel.name, directory: directory)
                )
            }
        )
        masterWaveformKey = key
        content.pushBmsonMaster(applies: true, waveform: masterWaveform)
    }

    private func refreshLaneWaveform() {
        guard let document = bmsonDocument else {
            content.pushBmsonLaneWaveform(nil)
            return
        }
        let directory = document.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let bpm = document.bpmNotes.map { (y: $0.y, v: $0.v) }
        let channels: [BmsonLaneWaveform.Channel] = document.soundChannels.map { channel in
            let summary = bmsonWaveSummary(named: channel.name, directory: directory)
            let key = bmsonWaveCacheKey(named: channel.name, directory: directory)
            return BmsonLaneWaveform.Channel(
                entries: bmsonLaneRms[key] ?? [],
                cache: BmsonChannel.playbackCache(
                    notes: channel.notes.map { (y: $0.y, c: $0.c) },
                    wave: summary,
                    initBpm: document.initialBpm,
                    resolution: document.resolution,
                    bpmNotes: bpm
                ),
                notes: channel.notes.enumerated().sorted {
                    $0.element.y == $1.element.y ? $0.offset < $1.offset : $0.element.y < $1.element.y
                }.map { (y: $0.element.y, x: $0.element.x) },
                frameCount: Int(summary.frameCount),
                sampleRate: summary.sampleRate
            )
        }
        content.pushBmsonLaneWaveform(
            BmsonLaneWaveform.State(
                drawsWaveform: bmsonSoundLaneMode.drawsWaveform,
                resolution: document.resolution,
                channels: channels
            )
        )
    }

    private func masterMixKey(_ document: BmsONEDocument) -> String {
        var parts = [
            document.filePath ?? "",
            "\(document.resolution)",
            "\(document.initialBpm)"
        ]
        for note in document.bpmNotes {
            parts.append("b\(note.y):\(note.v)")
        }
        for note in document.stopNotes {
            parts.append("s\(note.y):\(note.v)")
        }
        for channel in document.soundChannels {
            parts.append(channel.name)
            for note in channel.notes {
                parts.append("\(note.y):\(note.l):\(note.c ? 1 : 0)")
            }
        }
        return parts.joined(separator: "|")
    }

    /// PCM16 先按 `CheckFilename` 换扩展名；OGG 再解成 WAV。
    private func loadMasterWave(named name: String, directory: URL?) -> BmsONEExportWave? {
        let resolved = LegacyPreviewAudio.resolveAudioURL(fileName: name, chartDirectory: directory)
        if let resolved,
           let wave = BmsONEMasterExport.loadWave(
            named: resolved.lastPathComponent,
            directory: resolved.deletingLastPathComponent()
           )
        {
            return wave
        }
        guard let resolved, let data = try? IBMSAudioBridge.pcmWav(fromFile: resolved.path) else {
            return BmsONEMasterExport.loadWave(named: name, directory: directory)
        }
        return BmsONEMasterExport.readPcm16(data)
    }

    private func refreshSelectedObjects() {
        guard let bmsonDocument else {
            content.setSelectedObjectsVisible(false)
            return
        }
        content.setSelectedObjectsVisible(true)
        content.applyBmsonInfo(
            bmsonDocument.headerFields(),
            extraText: bmsonDocument.infoExtraFieldsText()
        )
        content.applySelectedObjects(
            bmsonDocument.selectedObjectsDisplay(identities: selectedBmsonNoteIdentities())
        )
    }

    private func commitSelectedBmsonLength(_ text: String) -> Bool {
        guard let bmsonDocument else { return false }
        let ok = bmsonDocument.applySelectedNoteLength(
            identities: selectedBmsonNoteIdentities(),
            text: text
        )
        if ok {
            refreshWindow()
        } else {
            refreshSelectedObjects()
        }
        return ok
    }

    private func commitBmsonInfoExtra(_ text: String) -> Bool {
        guard let bmsonDocument else { return false }
        let ok = bmsonDocument.applyInfoExtraFields(text)
        if ok {
            refreshWindow(waveformInputMayHaveChanged: false)
        } else {
            refreshSelectedObjects()
        }
        return ok
    }

    private func commitSelectedBmsonExtra(_ text: String) -> Bool {
        guard let bmsonDocument else { return false }
        let ok = bmsonDocument.applySelectedNoteExtraFields(
            identities: selectedBmsonNoteIdentities(),
            text: text
        )
        if ok {
            refreshWindow(waveformInputMayHaveChanged: false)
        } else {
            refreshSelectedObjects()
        }
        return ok
    }

    private func updateTimingWindow() {
        timingWindowController.update(
            snapshot: session?.timingSnapshot ?? .unavailable,
            sessionID: session.map(ObjectIdentifier.init)
        )
    }

    private func dismissTimingWindow() {
        timingWindowController.window?.orderOut(self)
    }

    private func dismissAuxiliaryWindows() {
        dismissTimingWindow()
        findWindowController.window?.orderOut(self)
        aboutWindowController.window?.orderOut(self)
        myO2WindowController.window?.orderOut(self)
        for controller in [visualOptionsWindowController, generalOptionsWindowController, playerOptionsWindowController] as [NSWindowController] {
            if let sheet = controller.window, sheet.sheetParent != nil {
                sheet.sheetParent?.endSheet(sheet)
            }
        }
        if let statistics = statisticsWindowController.window, statistics.sheetParent != nil {
            statistics.sheetParent?.endSheet(statistics)
        } else {
            statisticsWindowController.window?.orderOut(self)
        }
    }
}
