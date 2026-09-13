import AppKit

@MainActor
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let size = AboutDialogLayout.runtimeClientSize
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "About"
        NativeLocalization.markFixed(window, key: "About")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        super.init(window: window)
        window.delegate = self
        window.contentView = AboutDialogView(frame: NSRect(origin: .zero, size: size)) { [weak self] in
            self?.closeAbout()
        }
        NativeLocalization.localize(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(self)
        return false
    }

    private func closeAbout() {
        window?.orderOut(self)
    }
}

@MainActor
private final class AboutDialogView: FlippedDialogView {
    private let onClose: () -> Void

    init(frame: NSRect, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let imageView = NSImageView(frame: bounds)
        imageView.image = LegacyChromeIcons.image(named: AboutDialogLayout.imageName)
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.isEnabled = false
        addSubview(imageView)

        let copy = NSButton(title: AboutDialogLayout.clickToCopyTitle, target: self, action: #selector(copyEmail))
        copy.frame = AboutDialogLayout.clickToCopy
        copy.bezelStyle = .shadowlessSquare
        copy.isBordered = false
        copy.font = LegacyChromeFont.segoe
        copy.toolTip = AboutDialogLayout.email
        addSubview(copy)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onClose()
    }

    override func mouseUp(with event: NSEvent) {
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            onClose()
            return
        }
        super.mouseUp(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onClose()
    }

    @objc private func copyEmail() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AboutDialogLayout.email, forType: .string)
        NSSound.beep()
    }
}
