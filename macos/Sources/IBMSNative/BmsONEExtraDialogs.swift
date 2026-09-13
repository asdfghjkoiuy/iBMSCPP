import AppKit

/// 网格设置窗。对照 `GridSettingDialog`。客户区 `600 × 400`。
/// 底栏用 sizer，框是工作值。未截图。
@MainActor
final class BmsONEGridSettingWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmsONEGridSettingView
    private var sessionMedium = BmsONEGridSize.defaultMedium

    init() {
        let size = BmsONEDialogLayout.gridSettingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = BmsONEDialogLayout.gridSettingTitle
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        dialogView = BmsONEGridSettingView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.markFixed(window, key: BmsONEDialogLayout.gridSettingTitle)
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
        dialogView.onFinish = { [weak self] accepted in
            guard let window = self?.window else { return }
            NSApp.stopModal(withCode: accepted ? .OK : .cancel)
            window.orderOut(nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// 独立 BmsONE 窗仍走这一扇，只记预设，不扩成另一套主编辑器。
    func present() {
        _ = present(currentDivision: BmsONEGridSetting.fallbackDivision)
    }

    /// 用 `runModal`，不要和 sheet 混用。确定后写预设并返回细格 / 辅助格。
    func present(currentDivision: Int, defaults: UserDefaults = .standard) -> BmsONEGridApplyResult? {
        dialogView.load(
            BmsONEGridSettingDraft(
                grids: BmsONEGridSetting.load(from: defaults),
                medium: sessionMedium
            )
        )
        guard let window else { return nil }
        window.center()
        let code = NSApp.runModal(for: window)
        window.orderOut(nil)
        guard code == .OK else { return nil }
        let result = BmsONEGridSetting.accepted(
            draft: dialogView.draft,
            currentDivision: currentDivision
        )
        BmsONEGridSetting.save(result.grids, to: defaults)
        sessionMedium = result.medium
        return result
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.stopModal(withCode: .cancel)
        sender.orderOut(self)
        return false
    }
}

@MainActor
private final class BmsONEGridSettingView: FlippedDialogView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    var draft = BmsONEGridSettingDraft.makeDefault()
    var onFinish: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmsONEDialogLayout.gridSettingSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        table.headerView = NSTableHeaderView()
        addColumn(BmsONEDialogLayout.gridColumnDivision, width: 120, editable: true)
        addColumn(BmsONEDialogLayout.gridColumnLength, width: 120, editable: true)
        addColumn(BmsONEDialogLayout.gridColumnLabel, width: 160, editable: false)
        let aux = addColumn(BmsONEDialogLayout.gridColumnAux, width: 140, editable: false)
        let check = NSButtonCell()
        check.setButtonType(.switch)
        check.title = ""
        aux.dataCell = check
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true

        scroll.frame = NSRect(x: 8, y: 8, width: 584, height: 348)
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        scroll.borderType = .bezelBorder
        addSubview(scroll)

        let add = NSButton(title: BmsONEDialogLayout.gridAddTitle, target: nil, action: nil)
        add.frame = NSRect(x: 8, y: 364, width: 28, height: 28)
        add.bezelStyle = .rounded
        add.target = self
        add.action = #selector(addGrid)
        addSubview(add)

        let remove = NSButton(title: BmsONEDialogLayout.gridRemoveTitle, target: nil, action: nil)
        remove.frame = NSRect(x: 40, y: 364, width: 28, height: 28)
        remove.bezelStyle = .rounded
        remove.target = self
        remove.action = #selector(removeGrid)
        addSubview(remove)

        let restore = NSButton(title: BmsONEDialogLayout.gridRestoreTitle, target: nil, action: nil)
        restore.frame = NSRect(x: 76, y: 364, width: 140, height: 28)
        restore.bezelStyle = .rounded
        restore.target = self
        restore.action = #selector(restoreDefaults)
        addSubview(restore)

        let ok = NSButton(title: BmsONEDialogLayout.gridOkTitle, target: nil, action: nil)
        ok.frame = NSRect(x: 432, y: 364, width: 80, height: 28)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        ok.target = self
        ok.action = #selector(confirmGridSetting)
        addSubview(ok)

        let cancel = NSButton(title: BmsONEDialogLayout.gridCancelTitle, target: nil, action: nil)
        cancel.frame = NSRect(x: 516, y: 364, width: 76, height: 28)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelGridSetting)
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func load(_ draft: BmsONEGridSettingDraft) {
        self.draft = draft
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        draft.grids.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0, row < draft.grids.count, let identifier = tableColumn?.identifier.rawValue else {
            return nil
        }
        let grid = draft.grids[row]
        switch identifier {
        case BmsONEDialogLayout.gridColumnDivision:
            return Int(grid.denominator)
        case BmsONEDialogLayout.gridColumnLength:
            return Int(grid.numerator)
        case BmsONEDialogLayout.gridColumnLabel:
            return grid.displayText
        case BmsONEDialogLayout.gridColumnAux:
            return grid == draft.medium
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let identifier = tableColumn?.identifier.rawValue else { return }
        switch identifier {
        case BmsONEDialogLayout.gridColumnDivision:
            if let value = intValue(object), let next = draft.settingDenominator(at: row, value: value) {
                draft = next
            }
        case BmsONEDialogLayout.gridColumnLength:
            if let value = intValue(object), let next = draft.settingNumerator(at: row, value: value) {
                draft = next
            }
        case BmsONEDialogLayout.gridColumnAux:
            if let next = draft.selectingMedium(at: row) {
                draft = next
            }
        default:
            break
        }
        table.reloadData()
    }

    @objc private func addGrid() {
        let row = table.selectedRow >= 0 ? table.selectedRow : draft.grids.count
        draft = draft.inserting(at: row)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    @objc private func removeGrid() {
        let row = table.selectedRow
        guard let next = draft.removing(at: row) else { return }
        draft = next
        table.reloadData()
    }

    @objc private func restoreDefaults() {
        draft = draft.restoringDefault()
        table.reloadData()
    }

    @objc private func confirmGridSetting() {
        onFinish?(true)
    }

    @objc private func cancelGridSetting() {
        onFinish?(false)
    }

    @discardableResult
    private func addColumn(_ title: String, width: CGFloat, editable: Bool) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
        column.title = title
        column.width = width
        column.isEditable = editable
        table.addTableColumn(column)
        return column
    }

    private func intValue(_ object: Any?) -> Int? {
        if let number = object as? Int { return number }
        if let number = object as? NSNumber { return number.intValue }
        if let text = object as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

/// 导出 WAV 窗。对照 `MasterOutDialog`。客户区 `480 × 320`。
/// Export 按源码混音并写出 44100 Hz 立体声 PCM16。未截图。
private struct BmsONEExportChannelSnapshot: Sendable {
    let name: String
    let notes: [(y: Int64, c: Bool)]
}

private struct BmsONEExportSnapshot: Sendable {
    let initBpm: Double
    let resolution: Int
    let bpmNotes: [(y: Int64, v: Double)]
    let stopNotes: [(y: Int64, v: Double)]
    let channels: [BmsONEExportChannelSnapshot]
    let chartDirectory: URL?
    let slider: Int
    let clip: BmsONEClipKind
    let destination: URL
}

private enum BmsONEExportTaskResult: Sendable {
    case completed(String)
    case destinationExists
    case cannotOpen
    case cancelled
}

/// 后台导出只使用这份值快照；不得从此处访问 document 或任何 AppKit 对象。
private func performBmsONEExport(_ snapshot: BmsONEExportSnapshot) -> BmsONEExportTaskResult {
    let mixed = BmsONEMasterExport.mix(
        initBpm: snapshot.initBpm,
        resolution: snapshot.resolution,
        bpmNotes: snapshot.bpmNotes,
        stopNotes: snapshot.stopNotes,
        channels: snapshot.channels.map { channel in
            (
                notes: channel.notes,
                wave: loadBmsONEExportWave(named: channel.name, directory: snapshot.chartDirectory)
            )
        }
    )
    guard !Task.isCancelled else { return .cancelled }
    do {
        return .completed(try BmsONEMasterExport.write(
            samples: mixed,
            slider: snapshot.slider,
            clip: snapshot.clip,
            to: snapshot.destination,
            shouldCancel: { Task.isCancelled }
        ))
    } catch BmsONEMasterExportError.destinationExists {
        return .destinationExists
    } catch BmsONEMasterExportError.cancelled {
        return .cancelled
    } catch {
        return .cannotOpen
    }
}

/// PCM16 先按 `CheckFilename` 换扩展名；OGG 再解成 WAV。
/// 这是纯文件读取，后台导出时不会触碰界面或文档。
private func loadBmsONEExportWave(named name: String, directory: URL?) -> BmsONEExportWave? {
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

@MainActor
final class BmsONEExportWavWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmsONEExportWavView

    init() {
        let size = BmsONEDialogLayout.exportWavSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = BmsONEDialogLayout.exportWavTitle
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        dialogView = BmsONEExportWavView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.markFixed(window, key: BmsONEDialogLayout.exportWavTitle)
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(document: BmsONEDocument) {
        dialogView.apply(document: document)
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }

    func present(filePath: String?) {
        dialogView.apply(filePath: filePath)
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dialogView.cancelExport()
        sender.orderOut(self)
        return false
    }
}

@MainActor
private final class BmsONEExportWavView: FlippedDialogView {
    private let rangeValue = NSTextField(labelWithString: BmsONEDialogLayout.exportRangeTitle)
    private let output = NSTextField(string: "")
    private let refresh = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.exportRefreshTitle,
        target: nil,
        action: nil
    )
    private let volume = NSSlider()
    private let clip = NSPopUpButton(frame: .zero, pullsDown: false)
    private let export = NSButton(title: BmsONEDialogLayout.exportButtonTitle, target: nil, action: nil)
    private let close = NSButton(title: BmsONEDialogLayout.exportCloseTitle, target: nil, action: nil)
    private let log = NSTextView()
    private let volumeValue = NSTextField(labelWithString: "")
    private var document: BmsONEDocument?
    private var exportRequestID: UUID?
    private var exportTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmsONEDialogLayout.exportWavSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let rangeLabel = NSTextField(labelWithString: BmsONEDialogLayout.exportRangeLabel)
        rangeLabel.frame = NSRect(x: 8, y: 8, width: 80, height: 16)
        addSubview(rangeLabel)
        rangeValue.frame = NSRect(x: 96, y: 8, width: 376, height: 16)
        addSubview(rangeValue)

        let outputLabel = NSTextField(labelWithString: BmsONEDialogLayout.exportOutputTitle)
        outputLabel.frame = NSRect(x: 8, y: 32, width: 80, height: 16)
        addSubview(outputLabel)
        output.frame = NSRect(x: 96, y: 30, width: 376, height: 22)
        addSubview(output)

        refresh.frame = NSRect(x: 96, y: 58, width: 240, height: 20)
        refresh.state = .on
        addSubview(refresh)

        let volumeLabel = NSTextField(labelWithString: BmsONEDialogLayout.exportVolumeTitle)
        volumeLabel.frame = NSRect(x: 8, y: 84, width: 80, height: 16)
        addSubview(volumeLabel)
        volume.frame = NSRect(x: 96, y: 82, width: 280, height: 20)
        volume.minValue = 0
        volume.maxValue = Double(BmsONEDialogLayout.exportGainSteps)
        volume.doubleValue = Double(BmsONEDialogLayout.exportDefaultGain)
        volume.target = self
        volume.action = #selector(changeVolume)
        addSubview(volume)
        volumeValue.frame = NSRect(x: 384, y: 84, width: 88, height: 16)
        addSubview(volumeValue)
        refreshVolumeLabel()

        let clipLabel = NSTextField(labelWithString: BmsONEDialogLayout.exportClippingTitle)
        clipLabel.frame = NSRect(x: 8, y: 110, width: 80, height: 16)
        addSubview(clipLabel)
        clip.frame = NSRect(x: 96, y: 106, width: 200, height: 24)
        for title in BmsONEDialogLayout.exportClipTitles {
            clip.addItem(withTitle: title)
        }
        clip.selectItem(at: 0)
        addSubview(clip)

        log.frame = NSRect(x: 8, y: 136, width: 464, height: 140)
        log.isEditable = false
        log.isRichText = false
        log.string = ""
        addSubview(log)

        export.frame = NSRect(x: 316, y: 284, width: 80, height: 28)
        export.bezelStyle = .rounded
        export.keyEquivalent = "\r"
        export.target = self
        export.action = #selector(exportWav)
        addSubview(export)

        close.frame = NSRect(x: 400, y: 284, width: 72, height: 28)
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.target = self
        close.action = #selector(closeDialog)
        addSubview(close)
    }

    required init?(coder: NSCoder) { nil }

    func apply(document: BmsONEDocument) {
        self.document = document
        apply(filePath: document.filePath)
    }

    func apply(filePath: String?) {
        cancelExport()
        let base = BmsONEExportWav.suggestedBaseName(filePath: filePath)
        let directory = filePath.flatMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            return url.deletingLastPathComponent()
        } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        output.stringValue = BmsONEExportWav.uniqueOutputURL(
            directory: directory,
            base: base,
            exists: { FileManager.default.fileExists(atPath: $0.path) }
        ).path
        refresh.state = .on
        volume.doubleValue = Double(BmsONEDialogLayout.exportDefaultGain)
        clip.selectItem(at: 0)
        refreshVolumeLabel()
        log.string = ""
    }

    @objc private func changeVolume() {
        var slider = Int(volume.doubleValue.rounded())
        let db = BmsONEMasterExport.dbGain(slider: slider)
        if slider != BmsONEDialogLayout.exportDefaultGain && db > -0.999 && db < 0.999 {
            slider = BmsONEDialogLayout.exportDefaultGain
            volume.doubleValue = Double(slider)
        }
        refreshVolumeLabel()
    }

    @objc private func exportWav() {
        guard exportRequestID == nil else { return }
        let requestID = UUID()
        let snapshot = makeExportSnapshot()
        exportRequestID = requestID
        setExporting(true)
        log.string = NativeLocalization.text("Exporting WAV in the background…")
        exportTask = Task.detached(priority: .userInitiated) { [snapshot, weak self] in
            let result = performBmsONEExport(snapshot)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.finishExport(requestID: requestID, result: result)
            }
        }
    }

    @objc private func closeDialog() {
        cancelExport()
        window?.orderOut(self)
    }

    private func refreshVolumeLabel() {
        volumeValue.stringValue = BmsONEMasterExport.volumeLabel(slider: Int(volume.doubleValue.rounded()))
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportRequestID = nil
        setExporting(false)
    }

    private func makeExportSnapshot() -> BmsONEExportSnapshot {
        let directory = document?.filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        return BmsONEExportSnapshot(
            initBpm: document?.initialBpm ?? BmsONEInfoDefaults.initialBpm,
            resolution: document?.resolution ?? BmsONEInfoDefaults.resolution,
            bpmNotes: document?.bpmNotes.map { (y: $0.y, v: $0.v) } ?? [],
            stopNotes: document?.stopNotes.map { (y: $0.y, v: $0.v) } ?? [],
            channels: document?.soundChannels.map {
                BmsONEExportChannelSnapshot(name: $0.name, notes: $0.notes.map { (y: $0.y, c: $0.c) })
            } ?? [],
            chartDirectory: directory,
            slider: Int(volume.doubleValue.rounded()),
            clip: BmsONEClipKind(rawValue: clip.indexOfSelectedItem) ?? .soft,
            destination: URL(fileURLWithPath: output.stringValue)
        )
    }

    private func finishExport(requestID: UUID, result: BmsONEExportTaskResult) {
        guard exportRequestID == requestID else { return }
        exportRequestID = nil
        exportTask = nil
        setExporting(false)
        switch result {
        case .completed(let message):
            log.string = message
        case .destinationExists:
            log.string = NativeLocalization.text("Output file already exists. Choose a new file name.")
        case .cannotOpen:
            log.string = BmsONEDialogLayout.exportCannotOpen
        case .cancelled:
            break
        }
    }

    private func setExporting(_ exporting: Bool) {
        export.isEnabled = !exporting
        output.isEnabled = !exporting
        refresh.isEnabled = !exporting
        volume.isEnabled = !exporting
        clip.isEnabled = !exporting
    }
}

/// Convert Resolution 窗。对照 `InfoView::ResolutionClicked`。
/// 源码没有 `resize`。框是工作值。未截图。
@MainActor
final class BmsONEConvertResolutionWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmsONEConvertResolutionView

    init() {
        let size = CGSize(width: 360, height: 140)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = BmsONEDialogLayout.convertResolutionTitle
        window.isReleasedWhenClosed = false
        dialogView = BmsONEConvertResolutionView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.markFixed(window, key: BmsONEDialogLayout.convertResolutionTitle)
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
        dialogView.onFinish = { [weak self] accepted in
            guard let window = self?.window else { return }
            NSApp.stopModal(withCode: accepted ? .OK : .cancel)
            window.orderOut(nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// 用 `runModal`，不要和 sheet 混用。改成功返回 true。
    func present(document: BmsONEDocument) -> Bool {
        dialogView.prepare(current: document.resolution) { [weak document] value in
            document?.resolutionConversionLosesInformation(value) ?? false
        }
        guard let window else { return false }
        window.center()
        let code = NSApp.runModal(for: window)
        window.orderOut(nil)
        guard code == .OK, let next = dialogView.acceptedResolution else {
            return false
        }
        let previous = document.resolution
        do {
            try document.convertResolution(next)
            return document.resolution != previous
        } catch {
            NSSound.beep()
            return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.stopModal(withCode: .cancel)
        sender.orderOut(self)
        return false
    }
}

@MainActor
private final class BmsONEConvertResolutionView: FlippedDialogView {
    private let currentLabel = NSTextField(labelWithString: "")
    private let field = NSTextField()
    var acceptedResolution: Int?
    var onFinish: ((Bool) -> Void)?
    private var losesInformation: ((Int) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        currentLabel.frame = NSRect(x: 16, y: 16, width: 328, height: 18)
        addSubview(currentLabel)

        let newLabel = NSTextField(labelWithString: BmsONEDialogLayout.convertResolutionNewLabel)
        newLabel.frame = NSRect(x: 16, y: 44, width: 140, height: 18)
        addSubview(newLabel)

        field.frame = NSRect(x: 164, y: 42, width: 180, height: 22)
        field.isEditable = true
        addSubview(field)

        let ok = NSButton(title: BmsONEDialogLayout.gridOkTitle, target: nil, action: nil)
        ok.frame = NSRect(x: 184, y: 96, width: 76, height: 28)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        ok.target = self
        ok.action = #selector(confirm)
        addSubview(ok)

        let cancel = NSButton(title: BmsONEDialogLayout.gridCancelTitle, target: nil, action: nil)
        cancel.frame = NSRect(x: 268, y: 96, width: 76, height: 28)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelDialog)
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func prepare(current: Int, losesInformation: @escaping (Int) -> Bool) {
        self.losesInformation = losesInformation
        acceptedResolution = nil
        currentLabel.stringValue = "\(BmsONEDialogLayout.convertResolutionCurrentLabel) \(current)"
        field.stringValue = String(current)
    }

    @objc private func confirm() {
        guard let value = BmsONEResolutionConvert.parse(field.stringValue),
              BmsONEResolutionConvert.isAllowed(value)
        else {
            NSSound.beep()
            return
        }
        if losesInformation?(value) == true {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = BmsONEDialogLayout.convertResolutionWarningTitle
            alert.informativeText = BmsONEDialogLayout.convertResolutionWarning
            alert.addButton(withTitle: BmsONEDialogLayout.gridOkTitle)
            alert.addButton(withTitle: BmsONEDialogLayout.gridCancelTitle)
            NativeLocalization.localize(alert: alert)
            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
        }
        acceptedResolution = value
        onFinish?(true)
    }

    @objc private func cancelDialog() {
        acceptedResolution = nil
        onFinish?(false)
    }
}

/// Preferences. Contrasts `Preferences` / `PrefGeneralPage` / `PrefEditPage` / `PrefPreviewPage` / `PrefBmsPage`.
/// Source has no `resize`. Close is the default button. Store on close. Not a screenshot.
@MainActor
final class BmsONEPreferencesWindowController: NSWindowController, NSWindowDelegate {
    var onConfigureViewers: (() -> Void)? {
        get { dialogView.onConfigureViewers }
        set { dialogView.onConfigureViewers = newValue }
    }
    private let dialogView: BmsONEPreferencesView

    init() {
        let size = BmsONEDialogLayout.preferencesSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = BmsONEDialogLayout.preferencesTitle
        window.isReleasedWhenClosed = false
        dialogView = BmsONEPreferencesView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.markFixed(window, key: BmsONEDialogLayout.preferencesTitle)
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
        dialogView.onClose = { [weak self] in
            guard let window = self?.window else { return }
            NSApp.stopModal(withCode: .OK)
            window.orderOut(nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// `runModal`, not a sheet. Load on show, store on close.
    func present(defaults: UserDefaults = .standard) {
        dialogView.load(BmsONEPreferences.load(from: defaults))
        guard let window else { return }
        window.center()
        _ = NSApp.runModal(for: window)
        window.orderOut(nil)
        dialogView.commit()
        dialogView.draft.store(to: defaults)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.stopModal(withCode: .OK)
        sender.orderOut(self)
        return false
    }
}

@MainActor
private final class BmsONEPreferencesView: FlippedDialogView, NSTableViewDataSource, NSTableViewDelegate {
    var draft = BmsONEPreferences()
    var onClose: (() -> Void)?
    var onConfigureViewers: (() -> Void)?

    private let pages = [
        BmsONEDialogLayout.preferencesGeneralTitle,
        BmsONEDialogLayout.preferencesEditTitle,
        BmsONEDialogLayout.preferencesPreviewTitle,
        BmsONEDialogLayout.preferencesBmsImportTitle
    ]
    private let list = NSTableView()
    private let pageViews: [NSView]
    private let languagePopup = NSPopUpButton()
    private let saveFormatPopup = NSPopUpButton()
    private let jsonFormatPopup = NSPopUpButton()
    private let fontButton = NSButton(title: "", target: nil, action: nil)
    private let master = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesEnableMasterCache,
        target: nil,
        action: nil
    )
    private let showMasterLane = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesShowMasterLane,
        target: nil,
        action: nil
    )
    private let showMiniMap = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesShowMiniMap,
        target: nil,
        action: nil
    )
    private let fixMiniMap = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesFixMiniMap,
        target: nil,
        action: nil
    )
    private let miniMapOpacity = NSSlider()
    private let alwaysCursor = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesAlwaysShowCursor,
        target: nil,
        action: nil
    )
    private let snappedHit = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesSnappedHitTest,
        target: nil,
        action: nil
    )
    private let snappedSelect = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesSnappedSelection,
        target: nil,
        action: nil
    )
    private let delaySlider = NSSlider()
    private let delayValue = NSTextField(labelWithString: "")
    private let smoothing = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesSmoothBar,
        target: nil,
        action: nil
    )
    private let durationSlider = NSSlider()
    private let durationValue = NSTextField(labelWithString: "")
    private let softFade = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesSoftFadeOut,
        target: nil,
        action: nil
    )
    private let encodingPopup = NSPopUpButton()
    private let askEncoding = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let useRandom = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesGenerateRandom,
        target: nil,
        action: nil
    )
    private let askRandom = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let trustPlayer = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesTrustPlayer,
        target: nil,
        action: nil
    )
    private let ignoreExtension = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesIgnoreExtension,
        target: nil,
        action: nil
    )
    private let preferEx = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesPreferExModes,
        target: nil,
        action: nil
    )
    private let askGameMode = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let skipBetween = NSButton(
        checkboxWithTitle: BmsONEDialogLayout.preferencesSkipBetweenRandom,
        target: nil,
        action: nil
    )
    private let minimumResolution = NSTextField()
    private let maximumResolution = NSTextField()

    override init(frame frameRect: NSRect) {
        let general = NSView(frame: NSRect(x: 196, y: 8, width: 436, height: 360))
        let edit = NSView(frame: NSRect(x: 196, y: 8, width: 436, height: 360))
        let preview = NSView(frame: NSRect(x: 196, y: 8, width: 436, height: 360))
        let bms = NSView(frame: NSRect(x: 196, y: 8, width: 436, height: 360))
        pageViews = [general, edit, preview, bms]
        super.init(frame: NSRect(origin: .zero, size: BmsONEDialogLayout.preferencesSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = 164
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self
        list.delegate = self
        list.rowHeight = 36
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: 180, height: 360))
        scroll.documentView = list
        scroll.hasVerticalScroller = false
        scroll.borderType = .bezelBorder
        addSubview(scroll)

        for page in pageViews {
            page.isHidden = true
            addSubview(page)
        }
        buildGeneral(general)
        buildEdit(edit)
        buildPreview(preview)
        buildBms(bms)
        pageViews[0].isHidden = false
        list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        let close = NSButton(title: BmsONEDialogLayout.preferencesCloseTitle, target: nil, action: nil)
        close.frame = NSRect(x: 548, y: 380, width: 84, height: 28)
        close.bezelStyle = .rounded
        close.keyEquivalent = "\r"
        close.target = self
        close.action = #selector(closePreferences)
        addSubview(close)
    }

    required init?(coder: NSCoder) { nil }

    func commit() {
        changeResolutions()
    }

    func load(_ value: BmsONEPreferences) {
        draft = value
        languagePopup.selectItem(at: draft.languageIndex)
        saveFormatPopup.selectItem(at: max(0, BmsONEPreferenceFormat.saveFormatKeys.firstIndex(of: draft.saveFormat) ?? 0))
        jsonFormatPopup.selectItem(withTitle: draft.saveJsonFormat)
        updateFontButton()
        master.state = draft.enableMasterChannel ? .on : .off
        showMasterLane.state = draft.showMasterLane ? .on : .off
        showMiniMap.state = draft.showMiniMap ? .on : .off
        fixMiniMap.state = draft.fixMiniMap ? .on : .off
        miniMapOpacity.minValue = Double(BmsONEPreferenceFormat.miniMapOpacitySliderMinimum)
        miniMapOpacity.maxValue = Double(BmsONEPreferenceFormat.miniMapOpacitySliderMaximum)
        miniMapOpacity.doubleValue = Double(BmsONEPreferenceFormat.miniMapOpacitySlider(opacity: draft.miniMapOpacity))
        alwaysCursor.state = draft.alwaysShowCursorLineInEditMode ? .on : .off
        snappedHit.state = draft.snappedHitTestInEditMode ? .on : .off
        snappedSelect.state = draft.snappedSelectionInEditMode ? .on : .off
        delaySlider.minValue = 0
        delaySlider.maxValue = Double(BmsONEPreferenceFormat.delayRatioSliderLevels)
        delaySlider.doubleValue = Double(BmsONEPreferenceFormat.delaySlider(ratio: draft.previewDelayRatio))
        delayValue.stringValue = String(draft.previewDelayRatio)
        smoothing.state = draft.previewSmoothing ? .on : .off
        durationSlider.minValue = 0
        durationSlider.maxValue = Double(BmsONEPreferenceFormat.notePreviewDurations.count - 1)
        durationSlider.doubleValue = Double(BmsONEPreferenceFormat.durationIndex(draft.singleMaxDuration))
        durationValue.stringValue = BmsONEPreferenceFormat.durationTitle(draft.singleMaxDuration)
        softFade.state = draft.singleSoftFadeOut ? .on : .off
        encodingPopup.selectItem(at: BmsONETextEncoding.allCases.firstIndex(of: draft.defaultTextEncoding) ?? 0)
        askEncoding.state = draft.askTextEncoding ? .on : .off
        useRandom.state = draft.useRandomValues ? .on : .off
        askRandom.state = draft.askRandomValues ? .on : .off
        trustPlayer.state = draft.trustPlayerCommand ? .on : .off
        ignoreExtension.state = draft.ignoreExtension ? .on : .off
        preferEx.state = draft.preferExModes ? .on : .off
        askGameMode.state = draft.askGameMode ? .on : .off
        skipBetween.state = draft.skipBetweenRandomAndIf ? .on : .off
        minimumResolution.stringValue = String(draft.minimumResolution)
        maximumResolution.stringValue = String(draft.maximumResolution)
        refreshEnabled()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        pages[row]
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = max(0, list.selectedRow)
        for (index, page) in pageViews.enumerated() {
            page.isHidden = index != row
        }
    }

    private func buildGeneral(_ page: NSView) {
        addLabel(BmsONEDialogLayout.preferencesLanguageTitle, x: 8, y: 8, width: 120, on: page)
        languagePopup.frame = NSRect(x: 132, y: 6, width: 140, height: 24)
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: BmsONEPreferenceFormat.languageTitles)
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage)
        page.addSubview(languagePopup)
        addLabel(BmsONEDialogLayout.preferencesLanguageRestart, x: 280, y: 8, width: 148, on: page)

        addLabel(BmsONEDialogLayout.preferencesSaveFormatTitle, x: 8, y: 40, width: 120, on: page)
        saveFormatPopup.frame = NSRect(x: 132, y: 38, width: 292, height: 24)
        saveFormatPopup.removeAllItems()
        saveFormatPopup.addItems(withTitles: BmsONEPreferenceFormat.saveFormatTitles)
        saveFormatPopup.target = self
        saveFormatPopup.action = #selector(changeSaveFormat)
        page.addSubview(saveFormatPopup)

        addLabel(BmsONEDialogLayout.preferencesSaveJsonFormatTitle, x: 8, y: 72, width: 120, on: page)
        jsonFormatPopup.frame = NSRect(x: 132, y: 70, width: 292, height: 24)
        jsonFormatPopup.removeAllItems()
        jsonFormatPopup.addItems(withTitles: BmsONEPreferenceFormat.saveJsonFormats)
        jsonFormatPopup.target = self
        jsonFormatPopup.action = #selector(changeJsonFormat)
        page.addSubview(jsonFormatPopup)

        addLabel(BmsONEDialogLayout.preferencesUIFontTitle, x: 8, y: 104, width: 120, on: page)
        fontButton.frame = NSRect(x: 132, y: 102, width: 220, height: 24)
        fontButton.bezelStyle = .rounded
        fontButton.target = self
        fontButton.action = #selector(pickFont)
        page.addSubview(fontButton)
        let reset = NSButton(title: BmsONEDialogLayout.preferencesFontResetTitle, target: nil, action: nil)
        reset.frame = NSRect(x: 360, y: 102, width: 64, height: 24)
        reset.bezelStyle = .rounded
        reset.target = self
        reset.action = #selector(resetFont)
        page.addSubview(reset)
    }

    private func buildEdit(_ page: NSView) {
        place(master, x: 8, y: 8, width: 420, on: page, action: #selector(toggleMaster))
        place(showMasterLane, x: 24, y: 36, width: 404, on: page, action: #selector(toggleShowMasterLane))
        place(showMiniMap, x: 24, y: 64, width: 404, on: page, action: #selector(toggleShowMiniMap))
        place(fixMiniMap, x: 40, y: 92, width: 388, on: page, action: #selector(toggleFixMiniMap))
        addLabel(BmsONEDialogLayout.preferencesMiniMapOpacity, x: 40, y: 124, width: 160, on: page)
        miniMapOpacity.frame = NSRect(x: 200, y: 122, width: 220, height: 24)
        miniMapOpacity.target = self
        miniMapOpacity.action = #selector(changeMiniMapOpacity)
        page.addSubview(miniMapOpacity)
        addLabel(BmsONEDialogLayout.preferencesEditModeGroup, x: 8, y: 164, width: 200, on: page)
        place(alwaysCursor, x: 8, y: 192, width: 420, on: page, action: #selector(toggleAlwaysCursor))
        place(snappedHit, x: 8, y: 220, width: 420, on: page, action: #selector(toggleSnappedHit))
        place(snappedSelect, x: 8, y: 248, width: 420, on: page, action: #selector(toggleSnappedSelect))
    }

    private func buildPreview(_ page: NSView) {
        addLabel(BmsONEDialogLayout.preferencesChannelPreviewGroup, x: 8, y: 8, width: 420, on: page)
        addLabel(BmsONEDialogLayout.preferencesTimingAdjustment, x: 8, y: 36, width: 140, on: page)
        delaySlider.frame = NSRect(x: 148, y: 34, width: 220, height: 24)
        delaySlider.target = self
        delaySlider.action = #selector(changeDelay)
        page.addSubview(delaySlider)
        delayValue.frame = NSRect(x: 376, y: 36, width: 48, height: 18)
        page.addSubview(delayValue)
        place(smoothing, x: 8, y: 68, width: 420, on: page, action: #selector(toggleSmoothing))
        addLabel(BmsONEDialogLayout.preferencesSoundNotesGroup, x: 8, y: 104, width: 420, on: page)
        addLabel(BmsONEDialogLayout.preferencesMaxDuration, x: 8, y: 132, width: 140, on: page)
        durationSlider.frame = NSRect(x: 148, y: 130, width: 220, height: 24)
        durationSlider.target = self
        durationSlider.action = #selector(changeDuration)
        page.addSubview(durationSlider)
        durationValue.frame = NSRect(x: 376, y: 132, width: 48, height: 18)
        page.addSubview(durationValue)
        place(softFade, x: 8, y: 164, width: 420, on: page, action: #selector(toggleSoftFade))
        let viewers = NSButton(title: BmsONEDialogLayout.preferencesConfigureViewers, target: nil, action: nil)
        viewers.frame = NSRect(x: 8, y: 208, width: 260, height: 28)
        viewers.bezelStyle = .rounded
        viewers.target = self
        viewers.action = #selector(configureViewers)
        page.addSubview(viewers)
    }

    private func buildBms(_ page: NSView) {
        addLabel(BmsONEDialogLayout.preferencesDefaultColumn, x: 200, y: 8, width: 80, on: page)
        addLabel(BmsONEDialogLayout.preferencesAskColumn, x: 360, y: 8, width: 60, on: page)
        addLabel(BmsONEDialogLayout.preferencesTextEncoding, x: 8, y: 36, width: 180, on: page)
        encodingPopup.frame = NSRect(x: 188, y: 34, width: 160, height: 24)
        encodingPopup.removeAllItems()
        encodingPopup.addItems(withTitles: BmsONETextEncoding.allCases.map(\.displayName))
        encodingPopup.target = self
        encodingPopup.action = #selector(changeDefaultEncoding)
        page.addSubview(encodingPopup)
        askEncoding.frame = NSRect(x: 368, y: 34, width: 24, height: 24)
        askEncoding.target = self
        askEncoding.action = #selector(toggleAskEncoding)
        page.addSubview(askEncoding)

        addLabel(BmsONEDialogLayout.preferencesRandomCommand, x: 8, y: 68, width: 180, on: page)
        place(useRandom, x: 188, y: 66, width: 168, on: page, action: #selector(toggleUseRandom))
        askRandom.frame = NSRect(x: 368, y: 66, width: 24, height: 24)
        askRandom.target = self
        askRandom.action = #selector(toggleAskRandom)
        page.addSubview(askRandom)

        addLabel(BmsONEDialogLayout.preferencesGameMode, x: 8, y: 100, width: 180, on: page)
        place(trustPlayer, x: 188, y: 98, width: 168, on: page, action: #selector(toggleTrustPlayer))
        place(ignoreExtension, x: 188, y: 126, width: 168, on: page, action: #selector(toggleIgnoreExtension))
        place(preferEx, x: 188, y: 154, width: 168, on: page, action: #selector(togglePreferEx))
        askGameMode.frame = NSRect(x: 368, y: 126, width: 24, height: 24)
        askGameMode.target = self
        askGameMode.action = #selector(toggleAskGameMode)
        page.addSubview(askGameMode)

        addLabel(BmsONEDialogLayout.preferencesMiscellaneous, x: 8, y: 190, width: 200, on: page)
        place(skipBetween, x: 8, y: 218, width: 420, on: page, action: #selector(toggleSkipBetween))
        addLabel(BmsONEDialogLayout.preferencesConversionGroup, x: 8, y: 254, width: 200, on: page)
        addLabel(BmsONEDialogLayout.preferencesMinimumResolution, x: 8, y: 282, width: 160, on: page)
        minimumResolution.frame = NSRect(x: 188, y: 280, width: 120, height: 22)
        minimumResolution.target = self
        minimumResolution.action = #selector(changeResolutions)
        page.addSubview(minimumResolution)
        addLabel(BmsONEDialogLayout.preferencesMaximumResolution, x: 8, y: 310, width: 160, on: page)
        maximumResolution.frame = NSRect(x: 188, y: 308, width: 120, height: 22)
        maximumResolution.target = self
        maximumResolution.action = #selector(changeResolutions)
        page.addSubview(maximumResolution)
    }

    private func addLabel(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, on page: NSView) {
        let label = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(label, key: title)
        label.frame = NSRect(x: x, y: y, width: width, height: 18)
        page.addSubview(label)
    }

    private func place(
        _ button: NSButton,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        on page: NSView,
        action: Selector
    ) {
        button.frame = NSRect(x: x, y: y, width: width, height: 24)
        button.target = self
        button.action = action
        page.addSubview(button)
    }

    private func refreshEnabled() {
        showMasterLane.isEnabled = draft.masterGroupEnabled
        showMiniMap.isEnabled = draft.masterGroupEnabled
        fixMiniMap.isEnabled = draft.miniMapGroupEnabled
        miniMapOpacity.isEnabled = draft.miniMapOpacityEnabled
        softFade.isEnabled = draft.singleSoftFadeOutEnabled
    }

    private func updateFontButton() {
        let family = draft.uiFontFamily.isEmpty ? "System" : draft.uiFontFamily
        let size = draft.uiFontPointSize == 0 ? Double(NSFont.systemFontSize) : draft.uiFontPointSize
        fontButton.title = BmsONEPreferenceFormat.fontButtonTitle(
            family: family,
            pointSize: size,
            isDefault: draft.uiFontDefault
        )
    }

    @objc private func closePreferences() {
        changeResolutions()
        onClose?()
    }

    @objc private func changeLanguage() {
        draft.languageKey = BmsONEPreferenceFormat.languageKey(index: languagePopup.indexOfSelectedItem)
    }

    @objc private func changeSaveFormat() {
        let index = saveFormatPopup.indexOfSelectedItem
        if BmsONEPreferenceFormat.saveFormatKeys.indices.contains(index) {
            draft.saveFormat = BmsONEPreferenceFormat.saveFormatKeys[index]
        }
    }

    @objc private func changeJsonFormat() {
        draft.saveJsonFormat = jsonFormatPopup.titleOfSelectedItem ?? "Default"
    }

    @objc private func pickFont() {
        let size = draft.uiFontPointSize == 0 ? NSFont.systemFontSize : CGFloat(draft.uiFontPointSize)
        let current = NSFont(name: draft.uiFontFamily, size: size) ?? .systemFont(ofSize: size)
        NSFontManager.shared.setSelectedFont(current, isMultiple: false)
        NSFontManager.shared.target = self
        NSFontManager.shared.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        let size = draft.uiFontPointSize == 0 ? NSFont.systemFontSize : CGFloat(draft.uiFontPointSize)
        let current = NSFont(name: draft.uiFontFamily, size: size) ?? .systemFont(ofSize: size)
        let next = NSFontManager.shared.convert(current)
        draft.uiFontFamily = next.familyName ?? next.fontName
        draft.uiFontPointSize = Double(next.pointSize)
        draft.uiFontDefault = false
        updateFontButton()
    }

    @objc private func resetFont() {
        draft.uiFontDefault = true
        draft.uiFontFamily = NSFont.systemFont(ofSize: NSFont.systemFontSize).familyName ?? ""
        draft.uiFontPointSize = Double(NSFont.systemFontSize)
        updateFontButton()
    }

    @objc private func toggleMaster() {
        draft.enableMasterChannel = master.state == .on
        refreshEnabled()
    }

    @objc private func toggleShowMasterLane() {
        draft.showMasterLane = showMasterLane.state == .on
    }

    @objc private func toggleShowMiniMap() {
        draft.showMiniMap = showMiniMap.state == .on
        refreshEnabled()
    }

    @objc private func toggleFixMiniMap() {
        draft.fixMiniMap = fixMiniMap.state == .on
        refreshEnabled()
    }

    @objc private func changeMiniMapOpacity() {
        draft.miniMapOpacity = BmsONEPreferenceFormat.miniMapOpacity(slider: Int(miniMapOpacity.doubleValue))
    }

    @objc private func toggleAlwaysCursor() {
        draft.alwaysShowCursorLineInEditMode = alwaysCursor.state == .on
    }

    @objc private func toggleSnappedHit() {
        draft.snappedHitTestInEditMode = snappedHit.state == .on
    }

    @objc private func toggleSnappedSelect() {
        draft.snappedSelectionInEditMode = snappedSelect.state == .on
    }

    @objc private func changeDelay() {
        draft.previewDelayRatio = BmsONEPreferenceFormat.delayRatio(slider: Int(delaySlider.doubleValue))
        delayValue.stringValue = String(draft.previewDelayRatio)
    }

    @objc private func toggleSmoothing() {
        draft.previewSmoothing = smoothing.state == .on
    }

    @objc private func changeDuration() {
        draft.singleMaxDuration = BmsONEPreferenceFormat.durationValue(index: Int(durationSlider.doubleValue))
        durationValue.stringValue = BmsONEPreferenceFormat.durationTitle(draft.singleMaxDuration)
        refreshEnabled()
    }

    @objc private func toggleSoftFade() {
        draft.singleSoftFadeOut = softFade.state == .on
    }

    @objc private func configureViewers() {
        if let onConfigureViewers {
            onConfigureViewers()
            return
        }
        NSSound.beep()
    }

    @objc private func changeDefaultEncoding() {
        let index = encodingPopup.indexOfSelectedItem
        if BmsONETextEncoding.allCases.indices.contains(index) {
            draft.defaultTextEncodingKey = BmsONETextEncoding.allCases[index].rawValue
        }
    }

    @objc private func toggleAskEncoding() {
        draft.askTextEncoding = askEncoding.state == .on
    }

    @objc private func toggleUseRandom() {
        draft.useRandomValues = useRandom.state == .on
    }

    @objc private func toggleAskRandom() {
        draft.askRandomValues = askRandom.state == .on
    }

    @objc private func toggleTrustPlayer() {
        draft.trustPlayerCommand = trustPlayer.state == .on
    }

    @objc private func toggleIgnoreExtension() {
        draft.ignoreExtension = ignoreExtension.state == .on
    }

    @objc private func togglePreferEx() {
        draft.preferExModes = preferEx.state == .on
    }

    @objc private func toggleAskGameMode() {
        draft.askGameMode = askGameMode.state == .on
    }

    @objc private func toggleSkipBetween() {
        draft.skipBetweenRandomAndIf = skipBetween.state == .on
    }

    @objc private func changeResolutions() {
        let accepted = BmsONEPreferenceFormat.acceptedResolutions(
            minimumText: minimumResolution.stringValue,
            maximumText: maximumResolution.stringValue
        )
        draft.minimumResolution = accepted.0
        draft.maximumResolution = accepted.1
        minimumResolution.stringValue = String(draft.minimumResolution)
        maximumResolution.stringValue = String(draft.maximumResolution)
    }
}
