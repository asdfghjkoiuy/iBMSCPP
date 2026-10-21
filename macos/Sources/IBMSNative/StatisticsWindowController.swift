import AppKit

@MainActor
final class StatisticsWindowController: NSWindowController {
    private let content = StatisticsDialogView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: StatisticsDialogLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Statistics"
        NativeLocalization.markFixed(window, key: "Statistics")
        window.isReleasedWhenClosed = false
        window.contentMinSize = StatisticsDialogLayout.clientSize
        window.contentMaxSize = StatisticsDialogLayout.clientSize
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onClose = { [weak self] in
            guard let window = self?.window else { return }
            if let parent = window.sheetParent {
                parent.endSheet(window)
            } else {
                window.orderOut(nil)
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func present(over parent: NSWindow, matrix: StatisticsMatrix, completion: @escaping () -> Void) {
        content.update(matrix)
        guard let sheet = window else {
            completion()
            return
        }
        parent.beginSheet(sheet) { _ in completion() }
    }
}

@MainActor
private final class StatisticsDialogView: FlippedDialogView {
    var onClose: (() -> Void)?
    private var valueLabels: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: StatisticsDialogLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let icon = NSImageView(frame: StatisticsDialogLayout.iconFrame)
        icon.image = LegacyChromeIcons.image(named: "Statistics3")
        icon.imageScaling = .scaleNone
        addSubview(icon)

        for (index, title) in StatisticsDialogLayout.columnTitles.enumerated() {
            addLabel(title, frame: StatisticsDialogLayout.headerFrame(column: index), align: .center, bold: false)
        }
        for (index, title) in StatisticsDialogLayout.rowTitles.enumerated() {
            let label = addLabel(title, frame: StatisticsDialogLayout.rowLabelFrame(row: index), align: .right, bold: false)
            label.alignment = .right
            if StatisticsDialogLayout.rowIsStriped(index) {
                label.drawsBackground = true
                label.backgroundColor = StatisticsDialogLayout.stripe.nsColor
            }
        }
        for row in 0..<7 {
            for column in 0..<6 {
                let label = addLabel("", frame: StatisticsDialogLayout.cellFrame(row: row, column: column), align: .center, bold: true)
                if StatisticsDialogLayout.rowIsStriped(row) {
                    label.drawsBackground = true
                    label.backgroundColor = StatisticsDialogLayout.stripe.nsColor
                }
                valueLabels.append(label)
            }
        }

        let ok = NSButton(title: "OK", target: self, action: #selector(closeDialog))
        NativeLocalization.markFixed(ok, key: "OK")
        ok.frame = StatisticsDialogLayout.okFrame
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        addSubview(ok)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ matrix: StatisticsMatrix) {
        for row in 0..<7 {
            for column in 0..<6 {
                let value = matrix.value(row, column)
                valueLabels[row * 6 + column].stringValue = value == 0 ? "" : "\(value)"
            }
        }
    }

    @objc private func closeDialog() {
        onClose?()
    }

    @discardableResult
    private func addLabel(_ text: String, frame: CGRect, align: NSTextAlignment, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        if !text.isEmpty { NativeLocalization.markFixed(label, key: text) }
        label.frame = frame
        label.font = bold ? LegacyChromeFont.segoeBold : LegacyChromeFont.segoe
        label.alignment = align
        label.lineBreakMode = .byClipping
        addSubview(label)
        return label
    }
}

class FlippedDialogView: NSView {
    override var isFlipped: Bool { true }
}
