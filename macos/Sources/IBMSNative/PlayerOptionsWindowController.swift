import AppKit
import UniformTypeIdentifiers

@MainActor
final class PlayerOptionsWindowController: NSWindowController {
    private let content = PlayerOptionsDialogView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PlayerOptionsLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Player Arguments Options"
        NativeLocalization.markFixed(window, key: "Player Arguments Options")
        window.isReleasedWhenClosed = false
        window.contentMinSize = PlayerOptionsLayout.clientSize
        window.contentMaxSize = PlayerOptionsLayout.clientSize
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onCancel = { [weak self] in self?.end(nil) }
        content.onOK = { [weak self] settings in self?.end(settings) }
    }

    required init?(coder: NSCoder) { nil }

    private var pendingResult: EditorSettings?

    func present(over parent: NSWindow, settings: EditorSettings, completion: @escaping (EditorSettings?) -> Void) {
        pendingResult = nil
        content.load(settings)
        guard let sheet = window else {
            completion(nil)
            return
        }
        parent.beginSheet(sheet) { [weak self] _ in
            completion(self?.pendingResult)
        }
    }

    private func end(_ settings: EditorSettings?) {
        pendingResult = settings
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class PlayerOptionsDialogView: FlippedDialogView, NSTextFieldDelegate {
    var onOK: ((EditorSettings) -> Void)?
    var onCancel: (() -> Void)?

    private let list = NSTableView()
    private let listScroll = NSScrollView()
    private let pathField = OptionDialogControls.field(frame: PlayerOptionsLayout.path)
    private let playFromBeginning = OptionDialogControls.field(frame: PlayerOptionsLayout.playFromBeginning)
    private let playFromMeasure = OptionDialogControls.field(frame: PlayerOptionsLayout.playFromMeasure)
    private let stopField = OptionDialogControls.field(frame: PlayerOptionsLayout.stop)
    private var players: [PlayerArguments] = PlayerArguments.legacyDefaults
    private var currentIndex = 0
    private var draft = EditorSettings.legacyDefault

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: PlayerOptionsLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addSubview(OptionDialogControls.label("Current Player:", frame: PlayerOptionsLayout.currentPlayerLabel, align: .left))
        configureList()
        addSubview(OptionDialogControls.button("Add", frame: PlayerOptionsLayout.add, target: self, action: #selector(addPlayer)))
        addSubview(OptionDialogControls.button("Remove", frame: PlayerOptionsLayout.remove, target: self, action: #selector(removePlayer)))
        addSubview(OptionDialogControls.label("Path", frame: PlayerOptionsLayout.pathLabel))
        pathField.delegate = self
        addSubview(pathField)
        addSubview(OptionDialogControls.button("...", frame: PlayerOptionsLayout.browse, target: self, action: #selector(browse)))
        addSubview(OptionDialogControls.label("Arguments", frame: PlayerOptionsLayout.argumentsLabel, align: .left))
        addSubview(OptionDialogControls.rule(PlayerOptionsLayout.divider))
        addSubview(OptionDialogControls.label("Play from beginning", frame: PlayerOptionsLayout.playFromBeginningLabel))
        playFromBeginning.delegate = self
        addSubview(playFromBeginning)
        addSubview(OptionDialogControls.label("Play from current measure", frame: PlayerOptionsLayout.playFromMeasureLabel))
        playFromMeasure.delegate = self
        addSubview(playFromMeasure)
        addSubview(OptionDialogControls.label("Stop", frame: PlayerOptionsLayout.stopLabel))
        stopField.delegate = self
        addSubview(stopField)
        let references = OptionDialogControls.multilineLabel(
            PlayerOptionsLayout.referencesText,
            frame: PlayerOptionsLayout.references,
            align: .left
        )
        addSubview(references)

        let ok = OptionDialogControls.button("OK", frame: PlayerOptionsLayout.ok, target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        addSubview(ok)
        let cancel = OptionDialogControls.button("Cancel", frame: PlayerOptionsLayout.cancel, target: self, action: #selector(cancelDialog))
        cancel.keyEquivalent = "\u{1b}"
        addSubview(cancel)
        addSubview(OptionDialogControls.button("Restore Default", frame: PlayerOptionsLayout.restoreDefault, target: self, action: #selector(restoreDefault)))
    }

    required init?(coder: NSCoder) { nil }

    func load(_ settings: EditorSettings) {
        draft = settings
        players = settings.players
        currentIndex = settings.currentPlayer
        reloadList(selecting: currentIndex)
        showCurrent()
    }

    func controlTextDidChange(_ obj: Notification) {
        saveCurrent()
        if (obj.object as? NSTextField) === pathField {
            list.reloadData()
            list.selectRowIndexes(IndexSet(integer: currentIndex), byExtendingSelection: false)
        }
        validateFields()
    }

    @objc private func addPlayer() {
        saveCurrent()
        guard let next = PlayerOptionsLayout.insertingCopy(players: players, currentIndex: currentIndex) else { return }
        players = next.players
        currentIndex = next.currentIndex
        reloadList(selecting: currentIndex)
        showCurrent()
    }

    @objc private func removePlayer() {
        saveCurrent()
        guard let next = PlayerOptionsLayout.removing(players: players, currentIndex: currentIndex) else {
            presentNotice("There must exist at least one player.")
            return
        }
        players = next.players
        currentIndex = next.currentIndex
        reloadList(selecting: currentIndex)
        showCurrent()
    }

    @objc private func browse() {
        saveCurrent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        if let exe = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exe, .unixExecutable, .executable]
        }
        let expanded = pathField.stringValue.replacingOccurrences(of: "<apppath>", with: Bundle.main.bundlePath)
        panel.directoryURL = URL(fileURLWithPath: expanded).deletingLastPathComponent()
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let appPath = Bundle.main.bundlePath
            var path = url.path
            if path.hasPrefix(appPath) {
                path = "<apppath>" + path.dropFirst(appPath.count)
            }
            self.pathField.stringValue = path
            self.saveCurrent()
            self.reloadList(selecting: self.currentIndex)
            self.validateFields()
        }
    }

    @objc private func restoreDefault() {
        let alert = NSAlert()
        alert.messageText = "Restore default settings?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        NativeLocalization.localize(alert: alert)
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.players = PlayerArguments.legacyDefaults
            self.currentIndex = 0
            self.reloadList(selecting: 0)
            self.showCurrent()
        }
    }

    @objc private func confirm() {
        saveCurrent()
        var next = draft
        next.players = players
        next.currentPlayer = currentIndex
        onOK?(next)
    }

    @objc private func cancelDialog() {
        onCancel?()
    }

    private func configureList() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("player"))
        column.width = PlayerOptionsLayout.playerList.width - 4
        list.addTableColumn(column)
        list.headerView = nil
        list.rowHeight = 15
        list.font = LegacyChromeFont.segoe
        list.allowsEmptySelection = false
        list.allowsMultipleSelection = false
        list.dataSource = self
        list.delegate = self
        listScroll.frame = PlayerOptionsLayout.playerList
        listScroll.documentView = list
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        addSubview(listScroll)
    }

    private func reloadList(selecting index: Int) {
        list.reloadData()
        if players.indices.contains(index) {
            list.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    private func showCurrent() {
        guard players.indices.contains(currentIndex) else { return }
        let player = players[currentIndex]
        pathField.stringValue = player.path
        playFromBeginning.stringValue = player.playFromBeginning
        playFromMeasure.stringValue = player.playFromMeasure
        stopField.stringValue = player.stop
        validateFields()
    }

    private func saveCurrent() {
        guard players.indices.contains(currentIndex) else { return }
        players[currentIndex].path = pathField.stringValue
        players[currentIndex].playFromBeginning = playFromBeginning.stringValue
        players[currentIndex].playFromMeasure = playFromMeasure.stringValue
        players[currentIndex].stop = stopField.stringValue
    }

    private func validateFields() {
        for field in [pathField, playFromBeginning, playFromMeasure, stopField] {
            field.backgroundColor = PlayerOptionsLayout.hasInvalidPathCharacters(field.stringValue)
                ? OptionDialogColor.invalidField.nsColor
                : NSColor.textBackgroundColor
            field.drawsBackground = true
        }
    }

    private func presentNotice(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        NativeLocalization.localize(alert: alert)
        if let window { alert.beginSheetModal(for: window, completionHandler: nil) }
        else { alert.runModal() }
    }
}

extension PlayerOptionsDialogView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { players.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard players.indices.contains(row) else { return nil }
        return PlayerOptionsLayout.fileName(from: players[row].path)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = list.selectedRow
        guard players.indices.contains(row), row != currentIndex else { return }
        saveCurrent()
        currentIndex = row
        showCurrent()
    }
}
