import AppKit

@MainActor
final class WoslicerWindowController: NSWindowController, NSWindowDelegate {
    init() {
        // Working size for the command list only. Not an original client size.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = WoslicerLayout.windowTitle
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = WoslicerShellView(frame: window.contentView?.bounds ?? .zero)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(self)
        return false
    }
}

@MainActor
private final class WoslicerShellView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        addSubview(stack)

        let title = NSTextField(labelWithString: WoslicerLayout.windowTitle)
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        stack.addArrangedSubview(title)

        let status = NSTextField(wrappingLabelWithString: WoslicerLayout.shellStatus)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 0
        stack.addArrangedSubview(status)

        let geometry = NSTextField(wrappingLabelWithString: WoslicerLayout.originalClientSizeNote)
        geometry.textColor = .secondaryLabelColor
        geometry.maximumNumberOfLines = 0
        stack.addArrangedSubview(geometry)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        let listing = NSTextView()
        listing.isEditable = false
        listing.isSelectable = true
        listing.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        listing.string = WoslicerLayout.commandListing
        listing.textContainerInset = NSSize(width: 8, height: 8)
        listing.minSize = NSSize(width: 0, height: 0)
        listing.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        listing.isVerticallyResizable = true
        listing.isHorizontallyResizable = false
        listing.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        listing.textContainer?.widthTracksTextView = true
        scroll.documentView = listing
        stack.addArrangedSubview(scroll)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
    }

    required init?(coder: NSCoder) { nil }
}
