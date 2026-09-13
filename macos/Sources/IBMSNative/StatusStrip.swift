import AppKit

@MainActor
final class StatusStripView: NSView {
    private var labels: [String: NSTextField] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        var x: CGFloat = 0
        for field in MainWindowChrome.statusFields {
            let label = NSTextField(labelWithString: field.text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = field.bold ? LegacyChromeFont.segoeBold : LegacyChromeFont.segoe
            label.textColor = color(for: field.color)
            label.toolTip = field.tooltip.isEmpty ? nil : field.tooltip
            label.lineBreakMode = .byTruncatingTail
            label.identifier = NSUserInterfaceItemIdentifier(field.name)
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: field.width)
            ])
            labels[field.name] = label
            x += field.width
        }
    }

    required init?(coder: NSCoder) { nil }

    func setField(_ name: String, text: String) {
        labels[name]?.stringValue = text
    }

    func setNotice(_ text: String) {
        labels["FSP4"]?.stringValue = text
        labels["FSP4"]?.toolTip = text
    }

    func restoreDefaults() {
        for field in MainWindowChrome.statusFields {
            labels[field.name]?.stringValue = field.text
            labels[field.name]?.toolTip = field.tooltip.isEmpty ? nil : field.tooltip
        }
    }

    private func color(for token: StatusFieldLayout.ColorToken) -> NSColor {
        switch token {
        case .label: return .labelColor
        case .noteIndex: return NSColor(srgbRed: 128 / 255, green: 64 / 255, blue: 0, alpha: 1)
        case .teal: return NSColor(srgbRed: 0, green: 128 / 255, blue: 128 / 255, alpha: 1)
        case .maroon: return NSColor(srgbRed: 128 / 255, green: 0, blue: 0, alpha: 1)
        case .green: return NSColor(srgbRed: 0, green: 128 / 255, blue: 0, alpha: 1)
        case .olive: return NSColor(srgbRed: 128 / 255, green: 128 / 255, blue: 0, alpha: 1)
        case .blue: return .systemBlue
        case .red: return .systemRed
        }
    }
}
