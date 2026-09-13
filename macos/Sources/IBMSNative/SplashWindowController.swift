import AppKit

@MainActor
final class SplashWindowController: NSWindowController {
    init() {
        let size = SplashDialogLayout.clientSize
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = SplashDialogLayout.background.nsColor
        window.hasShadow = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        super.init(window: window)
        let view = FlippedDialogView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = SplashDialogLayout.background.nsColor.cgColor
        window.contentView = view
    }

    required init?(coder: NSCoder) { nil }

    func presentCentered() {
        window?.center()
        showWindow(self)
        window?.orderFrontRegardless()
    }

    func dismiss() {
        window?.orderOut(self)
    }
}
