import AppKit

@MainActor
final class TimeSelectionStripView: NSView, NSTextFieldDelegate {
    var onReverse: (() -> Void)?
    var onEditField: ((TimeSelectionField) -> Void)?
    var onExpand: ((Double, Double) -> Void)?
    var onRelocate: ((Double) -> Void)?
    var onConvertStop: (() -> Void)?

    private let startButton = NSButton(title: "0", target: nil, action: nil)
    private let lengthButton = NSButton(title: "0", target: nil, action: nil)
    private let halfButton = NSButton(title: "0", target: nil, action: nil)
    private let numeratorField = NSTextField(string: TimeSelectionLayout.defaultNumerator)
    private let denominatorField = NSTextField(string: TimeSelectionLayout.defaultDenominator)
    private let bpmField = NSTextField(string: TimeSelectionLayout.defaultBPM)
    private let noticeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addValue(startButton, frame: TimeSelectionLayout.start, tooltip: TimeSelectionLayout.startTooltip, action: #selector(editStart))
        addValue(lengthButton, frame: TimeSelectionLayout.length, tooltip: TimeSelectionLayout.lengthTooltip, action: #selector(editLength))
        addValue(halfButton, frame: TimeSelectionLayout.half, tooltip: TimeSelectionLayout.halfTooltip, action: #selector(editHalf))
        addAction(
            TimeSelectionLayout.reverseTitle,
            frame: TimeSelectionLayout.reverse,
            action: #selector(reverse)
        )
        addCaption("×", frame: TimeSelectionLayout.multiply)
        addPinkField(numeratorField, frame: TimeSelectionLayout.numerator)
        addCaption("÷", frame: TimeSelectionLayout.divide)
        addPinkField(denominatorField, frame: TimeSelectionLayout.denominator)
        addAction(
            TimeSelectionLayout.applyTitle,
            frame: TimeSelectionLayout.apply,
            action: #selector(expand),
            tooltip: "This will expand notes and selection by the ratio next to this button. Ignores center bar."
        )
        addPinkField(bpmField, frame: TimeSelectionLayout.bpm)
        addAction(
            TimeSelectionLayout.calculateTitle,
            frame: TimeSelectionLayout.calculate,
            action: #selector(relocate),
            tooltip: "This will move notes within the selection and preserve the selection, given the BPM value next to this button. Considers center bar."
        )
        addAction(
            TimeSelectionLayout.convertTitle,
            frame: TimeSelectionLayout.convertStop,
            action: #selector(convertStop),
            tooltip: "This will move notes within the selection and preserve the selection, given the BPM value next to this button. Considers center bar."
        )
        noticeLabel.font = LegacyChromeFont.segoe
        noticeLabel.textColor = .secondaryLabelColor
        noticeLabel.lineBreakMode = .byTruncatingTail
        noticeLabel.frame = NSRect(x: 722, y: 2, width: 140, height: 18)
        addSubview(noticeLabel)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func setSelection(_ selection: TimeSelection) {
        startButton.title = LegacyTimeSelection.formatField(selection.start)
        lengthButton.title = LegacyTimeSelection.formatField(selection.length)
        halfButton.title = LegacyTimeSelection.formatField(selection.half)
    }

    func setNotice(_ text: String) {
        noticeLabel.stringValue = text
        noticeLabel.toolTip = text.isEmpty ? nil : text
    }

    @objc private func reverse() {
        onReverse?()
    }

    @objc private func editStart() {
        onEditField?(.start)
    }

    @objc private func editLength() {
        onEditField?(.length)
    }

    @objc private func editHalf() {
        onEditField?(.half)
    }

    @objc private func expand() {
        onExpand?(Double(numeratorField.stringValue) ?? 2, Double(denominatorField.stringValue) ?? 1)
    }

    @objc private func relocate() {
        onRelocate?(Double(bpmField.stringValue) ?? 120)
    }

    @objc private func convertStop() {
        onConvertStop?()
    }

    private func addValue(_ button: NSButton, frame: CGRect, tooltip: String, action: Selector) {
        button.frame = frame
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.font = LegacyChromeFont.segoeBold
        button.alignment = .center
        button.focusRingType = .none
        button.toolTip = tooltip
        button.target = self
        button.action = action
        addSubview(button)
    }

    private func addCaption(_ text: String, frame: CGRect) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = LegacyChromeFont.segoe
        label.alignment = .center
        addSubview(label)
    }

    private func addPinkField(_ field: NSTextField, frame: CGRect) {
        field.frame = frame
        field.font = LegacyChromeFont.segoeBold
        field.alignment = .center
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = TimeSelectionLayout.fieldBackground.nsColor
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
    }

    private func addAction(_ title: String, frame: CGRect, action: Selector, tooltip: String? = nil) {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.font = LegacyChromeFont.segoe
        button.focusRingType = .none
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.backgroundColor = TimeSelectionLayout.actionBackground.nsColor.cgColor
        addSubview(button)
    }
}
