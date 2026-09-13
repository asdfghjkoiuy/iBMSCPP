import AppKit

@MainActor
final class ImportSMWindowController: NSWindowController {
    private let content = ImportSMDialogView()
    private var pendingIndex: Int?

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ImportSMLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ImportSMLayout.title
        window.isReleasedWhenClosed = false
        window.contentMinSize = ImportSMLayout.clientSize
        window.contentMaxSize = ImportSMLayout.clientSize
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onOK = { [weak self] index in self?.end(index) }
        content.onCancel = { [weak self] in self?.end(nil) }
    }

    required init?(coder: NSCoder) { nil }

    func present(over parent: NSWindow, difficulties: [String], completion: @escaping (Int?) -> Void) {
        pendingIndex = nil
        content.load(difficulties)
        parent.beginSheet(window!) { [weak self] _ in
            completion(self?.pendingIndex)
        }
    }

    private func end(_ index: Int?) {
        pendingIndex = index
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class ImportSMDialogView: FlippedDialogView, NSTableViewDataSource, NSTableViewDelegate {
    var onOK: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    private var items: [String] = []
    private let table = NSTableView()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: ImportSMLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        addSubview(OptionDialogControls.label(ImportSMLayout.difficultyTitle, frame: ImportSMLayout.difficultyLabel, align: .left))
        let scroll = NSScrollView(frame: ImportSMLayout.list)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.focusRingType = .none
        table.headerView = nil
        table.rowHeight = ImportSMLayout.listItemHeight
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff")))
        table.dataSource = self
        table.delegate = self
        table.font = LegacyChromeFont.segoe
        scroll.documentView = table
        addSubview(scroll)
        addSubview(OptionDialogControls.multilineLabel(ImportSMLayout.noteText, frame: ImportSMLayout.note, align: .left))
        let ok = OptionDialogControls.button("OK", frame: ImportSMLayout.ok, target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        addSubview(ok)
        let cancel = OptionDialogControls.button("Cancel", frame: ImportSMLayout.cancel, target: self, action: #selector(cancelDialog))
        cancel.keyEquivalent = "\u{1b}"
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func load(_ difficulties: [String]) {
        items = difficulties
        table.reloadData()
        if !items.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = NSTextField(labelWithString: items[row])
        text.font = LegacyChromeFont.segoe
        return text
    }

    @objc private func confirm() {
        let row = table.selectedRow
        guard row >= 0 else { return }
        onOK?(row)
    }

    @objc private func cancelDialog() {
        onCancel?()
    }
}
