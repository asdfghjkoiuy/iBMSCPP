import AppKit

/// BmsONE `ExternalViewerConfigDialog`. Hung on the shared app, not a second main window.
@MainActor
final class BmsONEExternalViewerWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmsONEExternalViewerView

    init() {
        let size = BmsONEDialogLayout.externalViewerSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text(BmsONEDialogLayout.externalViewerTitle)
        window.isReleasedWhenClosed = false
        dialogView = BmsONEExternalViewerView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.markFixed(window, key: BmsONEDialogLayout.externalViewerTitle)
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
        dialogView.onFinish = { [weak self] accepted in
            guard let window = self?.window else { return }
            NSApp.stopModal(withCode: accepted ? .OK : .cancel)
            window.orderOut(nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    @discardableResult
    func present(defaults: UserDefaults = .standard) -> Bool {
        dialogView.apply(BmsONEExternalViewerStore.load(from: defaults))
        guard let window else { return false }
        window.center()
        let code = NSApp.runModal(for: window)
        window.orderOut(nil)
        guard code == .OK else { return false }
        dialogView.commitCurrentField()
        dialogView.store.store(to: defaults)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dialogView.onFinish?(false)
        return false
    }
}

@MainActor
final class BmsONEExternalViewerView: FlippedDialogView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onFinish: ((Bool) -> Void)?
    private(set) var store = BmsONEExternalViewerStore.empty

    private let list = NSTableView()
    private let nameField = NSTextField()
    private let programField = NSTextField()
    private let directoryField = NSTextField()
    private let playBegField = NSTextField()
    private let playHereField = NSTextField()
    private let stopField = NSTextField()
    private let upButton = NSButton()
    private let downButton = NSButton()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let browseButton = NSButton(title: "...", target: nil, action: nil)
    private var acceptingFields: [NSTextField] = []
    private var lastAcceptingField: NSTextField?
    private var isApplying = false

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmsONEDialogLayout.externalViewerSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 140
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self
        list.delegate = self
        list.rowHeight = 28
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 44, width: 168, height: 348))
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        addSubview(scroll)

        configureIconButton(upButton, title: "▲", tooltip: "Up", action: #selector(moveViewerUp))
        configureIconButton(downButton, title: "▼", tooltip: "Down", action: #selector(moveViewerDown))
        configureIconButton(removeButton, title: "−", tooltip: "Remove", action: #selector(removeViewer))
        configureIconButton(addButton, title: "+", tooltip: "Add", action: #selector(addViewer))
        upButton.frame = NSRect(x: 52, y: 12, width: 28, height: 24)
        downButton.frame = NSRect(x: 84, y: 12, width: 28, height: 24)
        removeButton.frame = NSRect(x: 116, y: 12, width: 28, height: 24)
        addButton.frame = NSRect(x: 148, y: 12, width: 28, height: 24)

        addLabeledField(BmsONEDialogLayout.externalViewerNameLabel, field: nameField, x: 188, y: 16, width: 520)
        addLabeledField(BmsONEDialogLayout.externalViewerProgramLabel, field: programField, x: 188, y: 44, width: 476)
        browseButton.frame = NSRect(x: 668, y: 42, width: 40, height: 24)
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(selectProgram)
        addSubview(browseButton)
        addLabeledField(BmsONEDialogLayout.externalViewerDirectoryLabel, field: directoryField, x: 188, y: 72, width: 520)

        let args = NSBox(frame: NSRect(x: 188, y: 108, width: 524, height: 112))
        args.title = NativeLocalization.text(BmsONEDialogLayout.externalViewerArgumentsTitle)
        NativeLocalization.markFixed(args, key: BmsONEDialogLayout.externalViewerArgumentsTitle)
        args.boxType = .primary
        addSubview(args)
        addBoxedField(BmsONEDialogLayout.externalViewerPlayBegLabel, field: playBegField, on: args, y: 68)
        addBoxedField(BmsONEDialogLayout.externalViewerPlayHereLabel, field: playHereField, on: args, y: 40)
        addBoxedField(BmsONEDialogLayout.externalViewerStopLabel, field: stopField, on: args, y: 12)

        let vars = NSBox(frame: NSRect(x: 188, y: 228, width: 524, height: 164))
        vars.title = NativeLocalization.text(BmsONEDialogLayout.externalViewerVariablesTitle)
        NativeLocalization.markFixed(vars, key: BmsONEDialogLayout.externalViewerVariablesTitle)
        vars.boxType = .primary
        addSubview(vars)
        addVariable(BmsONEDialogLayout.externalViewerFilenameVar, BmsONEDialogLayout.externalViewerFilenameDesc, on: vars, x: 8, y: 112)
        addVariable(BmsONEDialogLayout.externalViewerDirectoryVar, BmsONEDialogLayout.externalViewerDirectoryDesc, on: vars, x: 8, y: 76)
        addVariable(BmsONEDialogLayout.externalViewerExeDirVar, BmsONEDialogLayout.externalViewerExeDirDesc, on: vars, x: 8, y: 40)
        addVariable(BmsONEDialogLayout.externalViewerMeasureVar, BmsONEDialogLayout.externalViewerMeasureDesc, on: vars, x: 268, y: 112)
        addVariable(BmsONEDialogLayout.externalViewerTimeVar, BmsONEDialogLayout.externalViewerTimeDesc, on: vars, x: 268, y: 76)
        addVariable(BmsONEDialogLayout.externalViewerTicksVar, BmsONEDialogLayout.externalViewerTicksDesc, on: vars, x: 268, y: 40)

        acceptingFields = [playBegField, playHereField, stopField, directoryField]
        for field in acceptingFields {
            field.delegate = self
        }
        nameField.delegate = self
        programField.delegate = self

        let ok = NSButton(title: NativeLocalization.text(BmsONEDialogLayout.gridOkTitle), target: nil, action: nil)
        NativeLocalization.markFixed(ok, key: BmsONEDialogLayout.gridOkTitle)
        ok.frame = NSRect(x: 536, y: 404, width: 84, height: 28)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        ok.target = self
        ok.action = #selector(acceptDialog)
        let cancel = NSButton(title: NativeLocalization.text(BmsONEDialogLayout.gridCancelTitle), target: nil, action: nil)
        NativeLocalization.markFixed(cancel, key: BmsONEDialogLayout.gridCancelTitle)
        cancel.frame = NSRect(x: 628, y: 404, width: 84, height: 28)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelDialog)
        addSubview(ok)
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ next: BmsONEExternalViewerStore) {
        store = next
        reloadList()
    }

    func commitCurrentField() {
        writeCurrentFields()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.viewers.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        store.viewers.indices.contains(row) ? store.viewers[row].displayName : ""
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplying else { return }
        writeCurrentFields()
        store.setCurrentIndex(list.selectedRow)
        showCurrent()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        writeCurrentFields()
        reloadListKeepingSelection()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, acceptingFields.contains(field) {
            lastAcceptingField = field
        }
    }

    @objc private func acceptDialog() {
        writeCurrentFields()
        onFinish?(true)
    }

    @objc private func cancelDialog() {
        onFinish?(false)
    }

    @objc private func addViewer() {
        writeCurrentFields()
        store.add(at: store.viewers.isEmpty ? 0 : max(store.currentIndex, 0))
        reloadList()
    }

    @objc private func removeViewer() {
        writeCurrentFields()
        store.remove(at: store.currentIndex)
        reloadList()
    }

    @objc private func moveViewerUp() {
        writeCurrentFields()
        store.moveUp(at: store.currentIndex)
        reloadList()
    }

    @objc private func moveViewerDown() {
        writeCurrentFields()
        store.moveDown(at: store.currentIndex)
        reloadList()
    }

    @objc private func selectProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = NativeLocalization.text("OK")
        if !programField.stringValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: programField.stringValue).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        programField.stringValue = url.path
        writeCurrentFields()
        reloadListKeepingSelection()
    }

    @objc private func insertVariable(_ sender: NSButton) {
        let token = sender.title
        let field = lastAcceptingField ?? acceptingFields.first
        guard let field, field.isEnabled else { return }
        field.stringValue += token
        window?.makeFirstResponder(field)
        writeCurrentFields()
    }

    private func reloadList() {
        isApplying = true
        list.reloadData()
        if store.isPlayable {
            list.selectRowIndexes(IndexSet(integer: store.currentIndex), byExtendingSelection: false)
        } else {
            list.deselectAll(nil)
        }
        isApplying = false
        showCurrent()
    }

    private func reloadListKeepingSelection() {
        let row = store.currentIndex
        isApplying = true
        list.reloadData()
        if store.viewers.indices.contains(row) {
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        isApplying = false
    }

    private func showCurrent() {
        let enabled = store.isPlayable
        [nameField, programField, directoryField, playBegField, playHereField, stopField, browseButton,
         upButton, downButton, removeButton].forEach { $0.isEnabled = enabled }
        addButton.isEnabled = true
        guard enabled else {
            nameField.stringValue = ""
            programField.stringValue = ""
            directoryField.stringValue = ""
            playBegField.stringValue = ""
            playHereField.stringValue = ""
            stopField.stringValue = ""
            return
        }
        let viewer = store.viewers[store.currentIndex]
        nameField.stringValue = viewer.displayName
        programField.stringValue = viewer.programPath
        directoryField.stringValue = viewer.executionDirectory
        playBegField.stringValue = viewer.argumentFormatPlayBeg
        playHereField.stringValue = viewer.argumentFormatPlayHere
        stopField.stringValue = viewer.argumentFormatStop
    }

    private func writeCurrentFields() {
        guard store.isPlayable else { return }
        store.viewers[store.currentIndex].displayName = nameField.stringValue
        store.viewers[store.currentIndex].programPath = programField.stringValue
        store.viewers[store.currentIndex].executionDirectory = directoryField.stringValue
        store.viewers[store.currentIndex].argumentFormatPlayBeg = playBegField.stringValue
        store.viewers[store.currentIndex].argumentFormatPlayHere = playHereField.stringValue
        store.viewers[store.currentIndex].argumentFormatStop = stopField.stringValue
    }

    private func configureIconButton(_ button: NSButton, title: String, tooltip: String, action: Selector) {
        button.title = title
        NativeLocalization.markTooltip(button, key: tooltip)
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        addSubview(button)
    }

    private func addLabeledField(_ title: String, field: NSTextField, x: CGFloat, y: CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(label, key: title)
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: x, y: y, width: 128, height: 16)
        field.frame = NSRect(x: x + 132, y: y - 4, width: width - 132, height: 22)
        field.font = .systemFont(ofSize: 11)
        addSubview(label)
        addSubview(field)
    }

    private func addBoxedField(_ title: String, field: NSTextField, on box: NSBox, y: CGFloat) {
        let label = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(label, key: title)
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: 8, y: y, width: 160, height: 16)
        field.frame = NSRect(x: 172, y: y - 4, width: 336, height: 22)
        field.font = .systemFont(ofSize: 11)
        (box.contentView ?? box).addSubview(label)
        (box.contentView ?? box).addSubview(field)
    }

    private func addVariable(_ token: String, _ description: String, on box: NSBox, x: CGFloat, y: CGFloat) {
        let button = NSButton(title: token, target: nil, action: nil)
        button.frame = NSRect(x: x, y: y, width: 110, height: 24)
        button.bezelStyle = .rounded
        button.focusRingType = .none
        button.target = self
        button.action = #selector(insertVariable(_:))
        let label = NSTextField(labelWithString: NativeLocalization.text(description))
        NativeLocalization.markFixed(label, key: description)
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: x + 114, y: y + 4, width: 130, height: 16)
        (box.contentView ?? box).addSubview(button)
        (box.contentView ?? box).addSubview(label)
    }
}
