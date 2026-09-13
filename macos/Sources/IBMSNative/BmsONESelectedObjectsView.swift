import AppKit

/// BmsONE Selected Objects dock. Hung on the shared main editor, not a second main window.
@MainActor
final class BmsONESelectedObjectsView: FlippedDialogView, NSTextFieldDelegate, NSTextViewDelegate {
    var onLengthCommit: ((String) -> Bool)?
    var onExtraCommit: ((String) -> Bool)?
    var onHeightChange: (() -> Void)?
    private var hasSelection = false
    var preferredHeight: CGFloat { hasSelection ? (extraExpanded ? 180 : 92) : 36 }
    func setDockTitleVisible(_ visible: Bool) { titleLabel.isHidden = !visible }

    private let titleLabel = NSTextField(labelWithString: NativeLocalization.text(BmsONESelectedObjectsLayout.dockTitle))
    private let messageLabel = NSTextField(labelWithString: "")
    private let lengthTitle = NSTextField(labelWithString: NativeLocalization.text(BmsONESelectedObjectsLayout.lengthLabel))
    private let lengthField = NSTextField()
    private let extraToggle = NSButton(checkboxWithTitle: NativeLocalization.text(BmsONESelectedObjectsLayout.extraFieldsTitle), target: nil, action: nil)
    private let extraScroll = NSScrollView()
    private let extraView = NSTextView()
    private var isApplyingDisplay = false
    private var extraExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmsONESelectedObjectsLayout.sizeHint))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = .boldSystemFont(ofSize: 11)
        NativeLocalization.markFixed(titleLabel, key: BmsONESelectedObjectsLayout.dockTitle)
        titleLabel.frame = NSRect(x: 8, y: 6, width: 167, height: 16)
        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.frame = NSRect(x: 8, y: 24, width: 167, height: 16)
        lengthTitle.font = .systemFont(ofSize: 11)
        NativeLocalization.markFixed(lengthTitle, key: BmsONESelectedObjectsLayout.lengthLabel)
        lengthTitle.frame = NSRect(x: 8, y: 48, width: 52, height: 16)
        lengthField.frame = NSRect(x: 65, y: 44, width: 118, height: 21)
        lengthField.font = .systemFont(ofSize: 11)
        lengthField.delegate = self
        extraToggle.font = .systemFont(ofSize: 11)
        NativeLocalization.markFixed(extraToggle, key: BmsONESelectedObjectsLayout.extraFieldsTitle)
        extraToggle.frame = NSRect(x: 8, y: 70, width: 167, height: 18)
        extraToggle.target = self
        extraToggle.action = #selector(toggleExtraFields)
        extraView.delegate = self
        extraView.font = .systemFont(ofSize: 11)
        extraView.isRichText = false
        extraView.usesFindBar = false
        extraView.isVerticallyResizable = true
        extraView.isHorizontallyResizable = false
        extraView.minSize = NSSize(width: 0, height: 0)
        extraView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        extraView.autoresizingMask = [.width]
        extraView.textContainer?.widthTracksTextView = true
        extraView.textContainer?.containerSize = NSSize(width: 167, height: CGFloat.greatestFiniteMagnitude)
        extraScroll.borderType = .bezelBorder
        extraScroll.hasVerticalScroller = true
        extraScroll.documentView = extraView
        extraScroll.frame = NSRect(x: 8, y: 92, width: 167, height: 80)
        extraView.frame = extraScroll.contentView.bounds
        extraExpanded = BmsonSelectedObjects.loadShowExtraFields()
        extraToggle.state = extraExpanded ? .on : .off
        extraScroll.isHidden = !extraExpanded

        [titleLabel, messageLabel, lengthTitle, lengthField, extraToggle, extraScroll].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ display: BmsonSelectedObjects.Display) {
        isApplyingDisplay = true
        let selectionChanged = hasSelection != display.lengthEnabled
        hasSelection = display.lengthEnabled
        let messageKey = display.message.isEmpty ? "No objects selected" : display.message
        NativeLocalization.markFixed(messageLabel, key: messageKey)
        messageLabel.stringValue = NativeLocalization.text(messageKey, fallback: messageKey)
        lengthField.isEnabled = display.lengthEnabled
        lengthField.stringValue = display.lengthText
        lengthField.placeholderString = display.lengthPlaceholder
        extraView.string = display.extraText
        extraView.isEditable = display.lengthEnabled
        let contentVisible = display.lengthEnabled
        messageLabel.frame.origin.y = contentVisible ? 24 : 10
        lengthTitle.isHidden = !contentVisible
        lengthField.isHidden = !contentVisible
        extraToggle.isHidden = !contentVisible
        extraScroll.isHidden = !contentVisible || !extraExpanded
        if selectionChanged { onHeightChange?() }
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingDisplay = false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitLength()
    }

    func textDidEndEditing(_ notification: Notification) {
        commitExtra()
    }

    @objc private func toggleExtraFields() {
        extraExpanded = extraToggle.state == .on
        extraScroll.isHidden = !extraExpanded
        BmsonSelectedObjects.storeShowExtraFields(extraExpanded)
        onHeightChange?()
    }

    private func commitLength() {
        guard !isApplyingDisplay else { return }
        if onLengthCommit?(lengthField.stringValue) != true {
            NSSound.beep()
        }
    }

    private func commitExtra() {
        guard !isApplyingDisplay else { return }
        if onExtraCommit?(extraView.string) != true {
            NSSound.beep()
        }
    }
}
