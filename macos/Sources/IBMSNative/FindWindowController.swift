import AppKit

@MainActor
final class FindWindowController: NSWindowController, NSWindowDelegate {
    var invalidLabelText = "Invalid label."
    var onSelect: ((FindQuery) -> String?)?
    var onUnselect: ((FindQuery) -> String?)?
    var onDelete: ((FindQuery) -> String?)?
    var onReplaceLabel: ((FindQuery) -> String?)?
    var onReplaceValue: ((FindQuery) -> String?)?

    private let content = FindDialogView()

    init() {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: FindDialogLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Find / Delete / Replace"
        NativeLocalization.markFixed(window, key: "Find / Delete / Replace")
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = FindDialogLayout.clientSize
        window.contentMaxSize = FindDialogLayout.clientSize
        super.init(window: window)
        window.delegate = self
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onClose = { [weak self] in self?.window?.orderOut(nil) }
        content.onAction = { [weak self] action in
            self?.perform(action)
        }
    }

    required init?(coder: NSCoder) { nil }

    func present(over parent: NSWindow?) {
        guard let window else { return }
        if !window.isVisible, let parent {
            let parentFrame = parent.frame
            let origin = NSPoint(
                x: parentFrame.midX - FindDialogLayout.clientSize.width / 2,
                y: parentFrame.midY - FindDialogLayout.clientSize.height / 2
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

    private func perform(_ action: FindDialogView.Action) {
        do {
            let query = try content.makeQuery(requiresReplaceLabel: action == .replaceLabel)
            let message: String?
            switch action {
            case .select: message = onSelect?(query)
            case .unselect: message = onUnselect?(query)
            case .delete: message = onDelete?(query)
            case .replaceLabel: message = onReplaceLabel?(query)
            case .replaceValue: message = onReplaceValue?(query)
            }
            if let message {
                presentNotice(message)
            }
        } catch FindDialogError.invalidLabel {
            presentNotice(invalidLabelText)
        } catch {
            presentNotice(error.localizedDescription)
        }
    }

    private func presentNotice(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        NativeLocalization.localize(alert: alert)
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}

@MainActor
private final class FindDialogView: FlippedDialogView {
    enum Action {
        case select, unselect, delete, replaceLabel, replaceValue
    }

    var onAction: ((Action) -> Void)?
    var onClose: (() -> Void)?

    private let selectedButton = toggle("Selected", frame: FindDialogLayout.selected)
    private let unselectedButton = toggle("Unselected", frame: FindDialogLayout.unselected)
    private let shortButton = toggle("Short", frame: FindDialogLayout.shortNote)
    private let longButton = toggle("Long", frame: FindDialogLayout.longNote)
    private let hiddenButton = toggle("Hidden", frame: FindDialogLayout.hidden)
    private let visibleButton = toggle("Visible", frame: FindDialogLayout.visible)
    private let measureLowField = field(FindDialogLayout.measureLow, text: "0")
    private let measureHighField = field(FindDialogLayout.measureHigh, text: "999")
    private let labelLowField = field(FindDialogLayout.labelLow, text: "01")
    private let labelHighField = field(FindDialogLayout.labelHigh, text: "ZZ")
    private let valueLowField = field(FindDialogLayout.valueLow, text: "0.0001")
    private let valueHighField = field(FindDialogLayout.valueHigh, text: "65535.9999")
    private let replaceLabelField = field(FindDialogLayout.replaceLabelField, text: "01")
    private let replaceValueField = field(FindDialogLayout.replaceValueField, text: "120")
    private var columnButtons: [NSButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: FindDialogLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addCaption("Note Range", frame: FindDialogLayout.noteRangeLabel, align: .right)
        addCaption("Measure Range", frame: FindDialogLayout.measureRangeLabel, align: .right)
        addCaption("Label Range", frame: FindDialogLayout.labelRangeLabel, align: .right)
        addCaption("Value Range", frame: FindDialogLayout.valueRangeLabel, align: .right)
        addCaption("to", frame: FindDialogLayout.measureTo, align: .center)
        addCaption("to", frame: FindDialogLayout.labelTo, align: .center)
        addCaption("to", frame: FindDialogLayout.valueTo, align: .center)
        let columnCaption = addCaption("Column", frame: FindDialogLayout.columnCaption, align: .left)
        columnCaption.font = LegacyChromeFont.segoeBold
        let operationCaption = addCaption("Operation", frame: FindDialogLayout.operationCaption, align: .left)
        operationCaption.font = LegacyChromeFont.segoeBold

        [selectedButton, unselectedButton, shortButton, longButton, hiddenButton, visibleButton].forEach(addSubview)
        [measureLowField, measureHighField, labelLowField, labelHighField, valueLowField, valueHighField, replaceLabelField, replaceValueField].forEach(addSubview)

        addRule(FindDialogLayout.columnRule)
        addRule(FindDialogLayout.operationRule)
        addRule(FindDialogLayout.operationDivider)

        let panel = NSScrollView(frame: FindDialogLayout.columnPanel)
        panel.hasVerticalScroller = true
        panel.hasHorizontalScroller = false
        panel.borderType = .noBorder
        panel.drawsBackground = false
        let document = FlippedDialogView()
        let buttons = FindDialogLayout.columnButtons()
        let contentHeight = buttons.map(\.frame.maxY).max() ?? 131
        document.frame = NSRect(x: 0, y: 0, width: 302, height: max(contentHeight, 131))
        for item in buttons {
            let button = Self.toggle(item.title, frame: item.frame)
            button.tag = item.columnIndex
            document.addSubview(button)
            columnButtons.append(button)
        }
        panel.documentView = document
        addSubview(panel)

        addCommand("Select All", frame: FindDialogLayout.selectAll, action: #selector(selectAllColumns))
        addCommand("Select Inverse", frame: FindDialogLayout.selectInverse, action: #selector(invertColumns))
        addCommand("Unselect All", frame: FindDialogLayout.unselectAll, action: #selector(clearColumns))
        addCommand("Replace with Label:", frame: FindDialogLayout.replaceLabel, action: #selector(replaceWithLabel))
        addCommand("Replace with Value:", frame: FindDialogLayout.replaceValue, action: #selector(replaceWithValue))
        let select = addCommand("Select", frame: FindDialogLayout.select, action: #selector(selectNotes))
        select.font = LegacyChromeFont.segoeBold
        addCommand("Unselect", frame: FindDialogLayout.unselect, action: #selector(unselectNotes))
        addCommand("Delete", frame: FindDialogLayout.delete, action: #selector(deleteNotes))
        addCommand("Close", frame: FindDialogLayout.close, action: #selector(closeDialog))
    }

    required init?(coder: NSCoder) { nil }

    func makeQuery(requiresReplaceLabel: Bool) throws -> FindQuery {
        let labels = [labelLowField.stringValue, labelHighField.stringValue]
        for text in labels {
            guard BMS36Token.isValidLabel(text) else { throw FindDialogError.invalidLabel }
        }
        if requiresReplaceLabel {
            guard BMS36Token.isValidLabel(replaceLabelField.stringValue) else { throw FindDialogError.invalidLabel }
        }
        var query = FindQuery()
        query.includeSelected = selectedButton.state == .on
        query.includeUnselected = unselectedButton.state == .on
        query.includeShort = shortButton.state == .on
        query.includeLong = longButton.state == .on
        query.includeHidden = hiddenButton.state == .on
        query.includeVisible = visibleButton.state == .on
        query.measureLow = clampInt(measureLowField.stringValue, default: 0, min: 0, max: 999)
        query.measureHigh = clampInt(measureHighField.stringValue, default: 999, min: 0, max: 999)
        query.labelLow = labelLowField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        query.labelHigh = labelHighField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        query.valueLow = clampDouble(valueLowField.stringValue, default: 0.0001, min: 0.0001, max: 65535.9999)
        query.valueHigh = clampDouble(valueHighField.stringValue, default: 65535.9999, min: 0.0001, max: 65535.9999)
        query.replaceLabel = replaceLabelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        query.replaceValue = clampDouble(replaceValueField.stringValue, default: 120, min: 0.0001, max: 65535.9999)
        query.columns = Set(columnButtons.filter { $0.state == .on }.map(\.tag))
        return query
    }

    @objc private func selectAllColumns() { columnButtons.forEach { $0.state = .on } }
    @objc private func invertColumns() { columnButtons.forEach { $0.state = $0.state == .on ? .off : .on } }
    @objc private func clearColumns() { columnButtons.forEach { $0.state = .off } }
    @objc private func selectNotes() { onAction?(.select) }
    @objc private func unselectNotes() { onAction?(.unselect) }
    @objc private func deleteNotes() { onAction?(.delete) }
    @objc private func replaceWithLabel() { onAction?(.replaceLabel) }
    @objc private func replaceWithValue() { onAction?(.replaceValue) }
    @objc private func closeDialog() { onClose?() }

    @discardableResult
    private func addCaption(_ text: String, frame: CGRect, align: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        NativeLocalization.markFixed(label, key: text)
        label.frame = frame
        label.font = LegacyChromeFont.segoe
        label.alignment = align
        addSubview(label)
        return label
    }

    @discardableResult
    private func addCommand(_ title: String, frame: CGRect, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        NativeLocalization.markFixed(button, key: title)
        button.frame = frame
        button.bezelStyle = .rounded
        button.font = LegacyChromeFont.segoe
        addSubview(button)
        return button
    }

    private func addRule(_ frame: CGRect) {
        let rule = NSView(frame: frame)
        rule.wantsLayer = true
        rule.layer?.backgroundColor = FindDialogLayout.ruleColor.nsColor.cgColor
        addSubview(rule)
    }

    private static func toggle(_ title: String, frame: CGRect) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        NativeLocalization.markFixed(button, key: title)
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .shadowlessSquare
        button.font = LegacyChromeFont.segoe
        button.state = .on
        return button
    }

    private static func field(_ frame: CGRect, text: String) -> NSTextField {
        let field = NSTextField(string: text)
        field.frame = frame
        field.font = LegacyChromeFont.segoe
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        return field
    }

    private func clampInt(_ text: String, default fallback: Int, min: Int, max: Int) -> Int {
        let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
        return Swift.min(max, Swift.max(min, value))
    }

    private func clampDouble(_ text: String, default fallback: Double, min: Double, max: Double) -> Double {
        let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
        return Swift.min(max, Swift.max(min, value))
    }
}

private enum FindDialogError: LocalizedError {
    case invalidLabel

    var errorDescription: String? {
        switch self {
        case .invalidLabel:
            return "Invalid label."
        }
    }
}
