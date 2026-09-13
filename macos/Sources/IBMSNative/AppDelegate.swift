import AppKit

@main
struct IBMSNativeApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = ApplicationState()
    private var previewMenuTarget: NSObject?
    private lazy var previewWindowController = PreviewWindowController(
        state: state,
        documentSource: { [weak self] in
            self?.mainWindowController.previewAudioContext()
        },
        onPlayheadBeat: { [weak self] beat in
            self?.mainWindowController.setPreviewPlayheadBeat(beat)
        }
    )
    private lazy var mainWindowController = MainWindowController(
        state: state,
        showPreview: { [weak self] in self?.showPreview() },
        hidePreview: { [weak self] in self?.hidePreview() },
        playFromBeginning: { [weak self] in self?.playPreview(fromBeginning: true) },
        playFromHere: { [weak self] in self?.playPreview(fromBeginning: false) },
        stopPreview: { [weak self] in self?.stopPreviewPlayback() }
    )
    private lazy var splashWindowController = SplashWindowController()
    private lazy var bmsoneWindowController = BmsONEWindowController()
    private lazy var bmhelperWindowController = BmhelperWindowController()
    private lazy var audioSlicerWindowController = AudioSlicerWindowController()
    private var didFinishLaunching = false
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeLocalization.configureDefaultLanguage()
        splashWindowController.presentCentered()
        previewMenuTarget = MenuBuilder.installMainMenu(
            mainWindowController: mainWindowController,
            showPreview: { [weak self] in self?.showPreview() },
            showBmsONE: { [weak self] in self?.mainWindowController.openEmptyBmson() },
            showBmhelper: { [weak self] in self?.bmhelperWindowController.present() },
            showWoslicer: { [weak self] in self?.audioSlicerWindowController.presentWoslicer() }
        )
        mainWindowController.installLanguageSupport()
        mainWindowController.applyRecentMenus()
        mainWindowController.showWindow(self)
        mainWindowController.window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        var skipRestore = false
        if LegacyLoadProgress.commandLineCandidate(ProcessInfo.processInfo.arguments) != nil {
            skipRestore = mainWindowController.handleCommandLineArguments(ProcessInfo.processInfo.arguments)
        } else if pendingOpenURLs.isEmpty == false {
            let opened = pendingOpenURLs
            pendingOpenURLs = []
            mainWindowController.openExternalURLs(opened)
            skipRestore = opened.count == 1 && LegacyLoadProgress.isAutosaveCommandLinePath(opened[0].path)
        }
        if !skipRestore {
            mainWindowController.offerAutosaveRestoreIfNeeded()
        }
        splashWindowController.dismiss()
        didFinishLaunching = true
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        if didFinishLaunching {
            mainWindowController.openDroppedURLs(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController.deleteAutoSaveFiles()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainWindowController.mayTerminateApplication()
    }

    @objc private func showPreview() {
        previewWindowController.showWindow(self)
        previewWindowController.window?.makeKeyAndOrderFront(self)
    }

    private func playPreview(fromBeginning: Bool) {
        showPreview()
        if fromBeginning {
            previewWindowController.playFromStart()
        } else {
            previewWindowController.playFromPointer()
        }
    }

    private func stopPreviewPlayback() {
        previewWindowController.stopPlayback()
    }

    /// 以后点音符预听可以走这里。这一轮谱面点击还没接。
    func previewNote(url: URL) {
        previewWindowController.previewNote(url: url)
    }

    private func hidePreview() {
        // 原版 ClickStopPreview 会 PreviewNote("", True)，先停再关。
        previewWindowController.stopPlayback()
        previewWindowController.window?.orderOut(self)
    }
}
