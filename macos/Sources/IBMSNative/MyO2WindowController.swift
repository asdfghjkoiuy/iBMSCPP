import AppKit

@MainActor
final class MyO2WindowController: NSWindowController, NSWindowDelegate {
    private let content = MyO2DialogView()

    var currentBPM: () -> Double = { MyO2Layout.defaultBPM }
    var notes: () -> [MyO2Note] = { [] }
    var ntInput: () -> Bool = { true }
    var gridLimit: () -> Double = { 1 }
    var applyNotes: ([MyO2Note]) -> Void = { _ in }

    init() {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: MyO2Layout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = MyO2Layout.title
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = MyO2Layout.clientSize
        window.contentMaxSize = MyO2Layout.clientSize
        super.init(window: window)
        window.delegate = self
        window.contentView = content
        content.onConstBPM = { [weak self] bpm in self?.applyConstBPM(bpm) }
        content.onCheck = { [weak self] in self?.runCheck() }
        content.onAdjust = { [weak self] in self?.runAdjust() }
    }

    required init?(coder: NSCoder) { nil }

    func present(over parent: NSWindow?) {
        guard let window else { return }
        content.setBPM(currentBPM())
        if !window.isVisible, let parent {
            let origin = NSPoint(
                x: parent.frame.midX - MyO2Layout.clientSize.width / 2,
                y: parent.frame.midY - MyO2Layout.clientSize.height / 2
            )
            window.setFrameOrigin(origin)
        }
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(self)
        return false
    }

    private func applyConstBPM(_ bpm: Double) {
        let target = bankersRound(bpm * 10_000)
        applyNotes(LegacyMyO2.constBPM(notes(), target: target, ntInput: ntInput()))
    }

    private func runCheck() {
        content.setAdjustments(LegacyMyO2.gridCheck(notes(), ntInput: ntInput(), gridLimit: gridLimit()))
    }

    private func runAdjust() {
        applyNotes(LegacyMyO2.gridAdjust(notes(), adjustments: content.adjustments, ntInput: ntInput()))
        NSSound.beep()
    }
}

@MainActor
private final class MyO2DialogView: FlippedDialogView, NSTableViewDataSource, NSTableViewDelegate {
    var onConstBPM: ((Double) -> Void)?
    var onCheck: (() -> Void)?
    var onAdjust: (() -> Void)?
    private(set) var adjustments: [MyO2Adjustment] = []
    private let bpmField = OptionDialogControls.decimalField(
        frame: MyO2Layout.bpmField,
        value: MyO2Layout.defaultBPM,
        range: MyO2Layout.bpmRange,
        digits: MyO2Layout.bpmDigits
    )
    private let table = NSTableView()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: MyO2Layout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        addSubview(OptionDialogControls.label(MyO2Layout.bpmTitle, frame: MyO2Layout.bpmLabel, align: .left))
        addSubview(bpmField)
        addSubview(OptionDialogControls.button(MyO2Layout.applyConstTitle, frame: MyO2Layout.applyConst, target: self, action: #selector(constBPM)))
        addSubview(OptionDialogControls.label(MyO2Layout.gridTitle, frame: MyO2Layout.gridLabel, align: .left))
        addSubview(OptionDialogControls.button(MyO2Layout.applyCheckTitle, frame: MyO2Layout.applyCheck, target: self, action: #selector(check)))
        addSubview(OptionDialogControls.button(MyO2Layout.applyAdjustTitle, frame: MyO2Layout.applyAdjust, target: self, action: #selector(adjust)))

        let scroll = NSScrollView(frame: MyO2Layout.table)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.focusRingType = .none
        table.rowHeight = 18
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.usesAlternatingRowBackgroundColors = true
        table.font = LegacyChromeFont.list
        table.dataSource = self
        table.delegate = self
        for column in MyO2Layout.columns {
            let item = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            item.title = column.title
            item.width = column.width
            item.minWidth = column.width
            item.maxWidth = column.width
            item.isEditable = column.editable
            table.addTableColumn(item)
        }
        scroll.documentView = table
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { nil }

    func setBPM(_ value: Double) {
        bpmField.doubleValue = min(MyO2Layout.bpmRange.upperBound, max(MyO2Layout.bpmRange.lowerBound, value))
    }

    func setAdjustments(_ items: [MyO2Adjustment]) {
        adjustments = items
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { adjustments.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, adjustments.indices.contains(row) else { return nil }
        let item = adjustments[row]
        let text: String
        switch id {
        case "Index": text = "\(row)"
        case "Measure": text = "\(item.measure)"
        case "ColumnName": text = item.columnName
        case "Grid": text = item.grid
        case "LongNote": text = item.longNote ? "1" : "0"
        case "Hidden": text = item.hidden ? "1" : "0"
        case "AdjTo64":
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleAdj(_:)))
            button.state = item.adjTo64 ? .on : .off
            button.tag = row
            return button
        case "D64": text = "\(item.d64)"
        case "D48": text = "\(item.d48)"
        default: text = ""
        }
        let field = NSTextField(labelWithString: text)
        field.font = LegacyChromeFont.list
        field.alignment = .center
        return field
    }

    @objc private func constBPM() {
        onConstBPM?(OptionDialogControls.double(from: bpmField, default: MyO2Layout.defaultBPM, range: MyO2Layout.bpmRange))
    }

    @objc private func check() { onCheck?() }
    @objc private func adjust() { onAdjust?() }

    @objc private func toggleAdj(_ sender: NSButton) {
        guard adjustments.indices.contains(sender.tag) else { return }
        adjustments[sender.tag].adjTo64 = sender.state == .on
    }
}

private func bankersRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}
