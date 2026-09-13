import AppKit

/// BmsONE Info 栏里 Header 对不上的字段。挂在共用主编辑器右侧，不是第二扇主程序窗。
@MainActor
final class BmsONEInfoDockView: FlippedDialogView, NSTextFieldDelegate, NSComboBoxDelegate, NSTextViewDelegate {
    var onFieldCommit: ((String, String) -> Bool)?
    var onExtraCommit: ((String) -> Bool)?
    var onHeightChange: (() -> Void)?
    var preferredHeight: CGFloat { extraExpanded ? 258 : 170 }
    func setDockTitleVisible(_ visible: Bool) { titleLabel.isHidden = !visible }

    private let titleLabel = NSTextField(labelWithString: NativeLocalization.text(BmsONEMainWindowLayout.infoDockTitle))
    private let chartNameField = NSTextField()
    private let judgeRankField = NSTextField()
    private let modeHintBox = NSComboBox()
    private let titleImageField = NSTextField()
    private let previewMusicField = NSTextField()
    private let extraToggle = NSButton(
        checkboxWithTitle: NativeLocalization.text(BmsONEMainWindowLayout.infoExtraFieldsTitle),
        target: nil,
        action: nil
    )
    private let extraScroll = NSScrollView()
    private let extraView = NSTextView()
    private var isApplying = false
    private var extraExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmsONEMainWindowLayout.infoDockSize))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = .boldSystemFont(ofSize: 11)
        NativeLocalization.markFixed(titleLabel, key: BmsONEMainWindowLayout.infoDockTitle)
        titleLabel.frame = NSRect(x: 8, y: 6, width: 167, height: 16)
        addSubview(titleLabel)

        addLabeledField(
            BmsONEMainWindowLayout.infoChartNameLabel,
            field: chartNameField,
            key: "CHARTNAME",
            y: 28
        )
        addLabeledField(
            BmsONEMainWindowLayout.infoJudgeRankLabel,
            field: judgeRankField,
            key: "JUDGERANK",
            y: 52
        )
        addModeHint(y: 76)
        addLabeledField(
            BmsONEMainWindowLayout.infoTitleImageLabel,
            field: titleImageField,
            key: "TITLEIMAGE",
            y: 100
        )
        addLabeledField(
            BmsONEMainWindowLayout.infoPreviewMusicLabel,
            field: previewMusicField,
            key: "PREVIEWMUSIC",
            y: 124
        )
        extraToggle.font = .systemFont(ofSize: 11)
        NativeLocalization.markFixed(extraToggle, key: BmsONEMainWindowLayout.infoExtraFieldsTitle)
        extraToggle.frame = NSRect(x: 8, y: 148, width: 167, height: 18)
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
        extraScroll.frame = NSRect(x: 8, y: 170, width: 167, height: 80)
        extraView.frame = extraScroll.contentView.bounds
        extraExpanded = BmsONEInfoDefaults.loadShowExtraFields()
        extraToggle.state = extraExpanded ? .on : .off
        extraScroll.isHidden = !extraExpanded
        addSubview(extraToggle)
        addSubview(extraScroll)
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ fields: [String: String], extraText: String) {
        isApplying = true
        chartNameField.stringValue = fields["CHARTNAME"] ?? ""
        judgeRankField.stringValue = fields["JUDGERANK"] ?? ""
        modeHintBox.stringValue = fields["MODEHINT"] ?? ""
        titleImageField.stringValue = fields["TITLEIMAGE"] ?? ""
        previewMusicField.stringValue = fields["PREVIEWMUSIC"] ?? ""
        extraView.string = extraText
        DispatchQueue.main.async { [weak self] in
            self?.isApplying = false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isApplying else { return }
        if let combo = obj.object as? NSComboBox {
            commit("MODEHINT", combo.stringValue)
            return
        }
        guard let field = obj.object as? NSTextField,
              let key = field.identifier?.rawValue else { return }
        commit(key, field.stringValue)
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard !isApplying else { return }
        commit("MODEHINT", modeHintBox.stringValue)
    }

    func textDidEndEditing(_ notification: Notification) {
        commitExtra()
    }

    @objc private func modeHintFinished(_ sender: NSComboBox) {
        guard !isApplying else { return }
        commit("MODEHINT", sender.stringValue)
    }

    @objc private func toggleExtraFields() {
        extraExpanded = extraToggle.state == .on
        extraScroll.isHidden = !extraExpanded
        BmsONEInfoDefaults.storeShowExtraFields(extraExpanded)
        onHeightChange?()
    }

    private func commit(_ key: String, _ value: String) {
        if onFieldCommit?(key, value) != true {
            NSSound.beep()
        }
    }

    private func commitExtra() {
        guard !isApplying else { return }
        if onExtraCommit?(extraView.string) != true {
            NSSound.beep()
        }
    }

    private func addLabeledField(_ title: String, field: NSTextField, key: String, y: CGFloat) {
        let label = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(label, key: title)
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: 0, y: y, width: 65, height: 16)
        field.frame = NSRect(x: 65, y: y - 4, width: 118, height: 21)
        field.font = .systemFont(ofSize: 11)
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.delegate = self
        addSubview(label)
        addSubview(field)
    }

    private func addModeHint(y: CGFloat) {
        let label = NSTextField(labelWithString: NativeLocalization.text(BmsONEMainWindowLayout.infoModeHintLabel))
        NativeLocalization.markFixed(label, key: BmsONEMainWindowLayout.infoModeHintLabel)
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: 0, y: y, width: 65, height: 16)
        modeHintBox.frame = NSRect(x: 65, y: y - 4, width: 118, height: 21)
        modeHintBox.font = .systemFont(ofSize: 11)
        modeHintBox.isEditable = true
        modeHintBox.completes = false
        modeHintBox.numberOfVisibleItems = 8
        modeHintBox.addItems(withObjectValues: BmsONEViewMode.menuHints)
        modeHintBox.identifier = NSUserInterfaceItemIdentifier("MODEHINT")
        modeHintBox.delegate = self
        modeHintBox.target = self
        modeHintBox.action = #selector(modeHintFinished(_:))
        addSubview(label)
        addSubview(modeHintBox)
    }
}
