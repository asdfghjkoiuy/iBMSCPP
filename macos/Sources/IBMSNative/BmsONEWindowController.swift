import AppKit
import UniformTypeIdentifiers

/// Native BmsONE main window. Chrome is the system title bar; this controller
/// does not install the iBMSC application menu.
@MainActor
final class BmsONEWindowController: NSWindowController, NSWindowDelegate {
    private let content: BmsONEMainWindowView
    /// BMSON document. Never a BMS `BmsDocument`.
    private var documentModel: BmsONEDocument
    /// BmsONE 命令菜单。绑在这个窗口上，不替换主程序的 `NSApp.mainMenu`。
    private(set) var bmsoneMenu: NSMenu
    private let importDialog = BmsONEImportWindowController()
    private let gridDialog = BmsONEGridSettingWindowController()
    private let exportWavDialog = BmsONEExportWavWindowController()

    init(document: BmsONEDocument = .empty()) {
        documentModel = document
        content = BmsONEMainWindowView()
        bmsoneMenu = BmsONEMenuBar.make()
        let size = BmsONEMainWindowLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = BmsONEWindowTitle.sourceTitle(filePath: document.filePath)
        window.setContentSize(size)
        window.minSize = NSSize(width: size.width, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        BmsONEMenuBar.bindItems(bmsoneMenu, to: self)
        NativeLocalization.registerKnownStaticMenu(bmsoneMenu)
        NativeLocalization.localize(menu: bmsoneMenu)
        content.onPlaceNote = { [weak self] lane, pulse in
            self?.placeShortNote(laneX: lane, pulseY: pulse)
        }
        content.apply(document)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        window?.center()
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(self)
        return false
    }

    func loadBmsonFile(at url: URL) throws {
        documentModel = try BmsONEDocument.open(url: url)
        refreshDocumentChrome()
    }

    func importBmsFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        importDialog.present(data: data, path: url.path) { [weak self] document in
            self?.documentModel = document
            self?.refreshDocumentChrome()
        }
    }

    func saveBmsonFile(to url: URL) throws {
        try documentModel.save(to: url)
        refreshDocumentChrome()
    }

    func saveBmsonFile() throws {
        try documentModel.save()
        refreshDocumentChrome()
    }

    func placeShortNote(laneX: Int64, pulseY: Int64) {
        do {
            try documentModel.insertShortNote(laneX: laneX, pulseY: pulseY)
            refreshDocumentChrome()
        } catch {
            presentBmsonError(error)
        }
    }

    @objc func newDocument(_ sender: Any?) {
        documentModel = .empty()
        refreshDocumentChrome()
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.bmsonTypes + Self.bmsTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if BmsONEFileTypes.isBmsURL(url) {
                try importBmsFile(at: url)
            } else {
                try loadBmsonFile(at: url)
            }
        } catch {
            presentBmsonError(error)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        if documentModel.filePath != nil {
            do {
                try saveBmsonFile()
            } catch {
                presentBmsonError(error)
            }
            return
        }
        saveDocumentAs(sender)
    }

    @objc func exportWav(_ sender: Any?) {
        exportWavDialog.present(document: documentModel)
    }

    @objc func showGridSetting(_ sender: Any?) {
        gridDialog.present()
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.bmsonTypes
        panel.nameFieldStringValue = suggestedSaveName()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saveBmsonFile(to: url)
        } catch {
            presentBmsonError(error)
        }
    }

    private func refreshDocumentChrome() {
        window?.title = BmsONEWindowTitle.sourceTitle(filePath: documentModel.filePath)
        content.apply(documentModel)
    }

    private func suggestedSaveName() -> String {
        if let filePath = documentModel.filePath {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        return "untitled.bmson"
    }

    private func presentBmsonError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "BMSON"
        alert.informativeText = error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static let bmsonTypes: [UTType] = {
        [UTType(filenameExtension: "bmson") ?? .json]
    }()

    private static let bmsTypes: [UTType] = {
        BmsONEFileTypes.bmsExtensions.compactMap { UTType(filenameExtension: $0) }
    }()
}

enum BmsONEMenuBar {
    static func make() -> NSMenu {
        let menu = NSMenu(title: BmsONEWindowTitle.appName)
        // macOS 将第一个顶层菜单解释为应用菜单。先放标准应用菜单，避免 File
        // 被系统吞入并改名为 IBMSNative。
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "IBMSNative")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let about = applicationMenu.addItem(
            withTitle: "About iBMSC",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        applicationMenu.addItem(.separator())
        let quit = applicationMenu.addItem(
            withTitle: "Quit IBMSNative",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(submenu("File", [
            "New", "Open...", "Save", "Save As...", "Export WAV..."
        ]))
        menu.addItem(submenu("Edit", [
            "Undo", "Redo", "Delete", "Move to Key Lanes", "Move to BGM Lanes",
            "Separate Layered Notes", "Edit Mode", "Write Mode",
            "Clear Master Cache", "Preferences"
        ]))
        menu.addItem(submenu("View", [
            "Views", "Toolbars", "View Mode", "Zoom", "Sound Channel Lanes Display",
            BmsONEDialogLayout.gridSettingMenuTitle, "Full Screen"
        ]))
        menu.addItem(submenu("Channel", [
            "Add...", "Select Previous", "Select Next", "Find", "Move Left", "Move Right",
            "Delete", "Select File...", "Preview Source Sound"
        ]))
        menu.addItem(submenu("Preview", []))
        menu.addItem(submenu("Help", ["About BmsONE", "About Qt"]))
        return menu
    }

    static func bindItems(_ menu: NSMenu, to target: BmsONEWindowController) {
        if let file = menu.item(withTitle: "File")?.submenu {
            bind(file, title: "New", action: #selector(BmsONEWindowController.newDocument(_:)), key: "n", target: target)
            bind(file, title: "Open...", action: #selector(BmsONEWindowController.openDocument(_:)), key: "o", target: target)
            bind(file, title: "Save", action: #selector(BmsONEWindowController.saveDocument(_:)), key: "s", target: target)
            bind(file, title: "Save As...", action: #selector(BmsONEWindowController.saveDocumentAs(_:)), key: "S", target: target)
            bind(file, title: "Export WAV...", action: #selector(BmsONEWindowController.exportWav(_:)), key: "", target: target)
        }
        if let view = menu.item(withTitle: "View")?.submenu {
            bind(
                view,
                title: BmsONEDialogLayout.gridSettingMenuTitle,
                action: #selector(BmsONEWindowController.showGridSetting(_:)),
                key: "",
                target: target
            )
        }
        // 独立 BmsONE 窗只实现文件操作、WAV 导出和网格设置；其余菜单保留
        // 为原版结构参考，但必须禁用，不能让用户误以为它是完整编辑器。
        disableUnboundItems(in: menu)
    }

    private static func disableUnboundItems(in menu: NSMenu) {
        menu.autoenablesItems = false
        for item in menu.items {
            if let submenu = item.submenu {
                disableUnboundItems(in: submenu)
            } else if item.action == nil {
                item.isEnabled = false
            }
        }
    }

    private static func bind(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        key: String,
        target: BmsONEWindowController
    ) {
        guard let item = menu.item(withTitle: title) else { return }
        item.action = action
        item.target = target
        item.keyEquivalent = key
    }

    private static func submenu(_ title: String, _ items: [String]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for name in items {
            menu.addItem(NSMenuItem(title: name, action: nil, keyEquivalent: ""))
        }
        item.submenu = menu
        return item
    }
}

@MainActor
private final class BmsONEMainWindowView: FlippedDialogView {
    var onPlaceNote: ((Int64, Int64) -> Void)?
    private let infoField = NSTextField(labelWithString: "")
    private let playingPane = BmsONEPlayingPaneView(frame: .zero)

    init() {
        super.init(frame: NSRect(origin: .zero, size: BmsONEMainWindowLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addDockColumn()
        addSequenceView()
        addStatusBar()
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ document: BmsONEDocument) {
        let shownTitle = document.title.isEmpty ? "(untitled)" : document.title
        infoField.stringValue = "\(shownTitle)  BPM \(Int(document.initialBpm.rounded()))"
        playingPane.document = document
        playingPane.needsDisplay = true
    }

    private func addDockColumn() {
        let column = BmsONEMainWindowLayout.dockColumnFrame
        let titles = [
            BmsONEMainWindowLayout.infoDockTitle,
            BmsONEMainWindowLayout.channelDockTitle,
            BmsONEMainWindowLayout.selectedObjectsDockTitle
        ]
        let slice = column.height / CGFloat(titles.count)
        for (index, title) in titles.enumerated() {
            let frame = CGRect(
                x: column.minX,
                y: column.minY + CGFloat(index) * slice,
                width: column.width,
                height: slice
            )
            let box = NSBox(frame: frame)
            box.title = NativeLocalization.text(title)
            NativeLocalization.markFixed(box, key: title)
            box.titlePosition = .atTop
            box.boxType = .primary
            if title == BmsONEMainWindowLayout.infoDockTitle {
                infoField.frame = CGRect(x: 8, y: 8, width: max(frame.width - 24, 0), height: 16)
                infoField.font = .systemFont(ofSize: 11)
                box.addSubview(infoField)
            }
            addSubview(box)
        }
    }

    private func addSequenceView() {
        let sequence = BmsONEMainWindowLayout.sequenceViewFrame
        let host = FlippedDialogView(frame: sequence)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedRed: 102 / 255, green: 102 / 255, blue: 102 / 255, alpha: 1).cgColor
        addSubview(host)

        let frames = BmsONESequenceLayout.mainWindowFrames
        let local = { (rect: CGRect) -> CGRect in
            CGRect(
                x: rect.minX - sequence.minX,
                y: rect.minY - sequence.minY,
                width: rect.width,
                height: rect.height
            )
        }
        addPane(to: host, frame: local(frames.timeLine), label: "Timeline")
        addPane(to: host, frame: local(frames.masterLane), label: "Master")
        playingPane.frame = local(frames.playingPane)
        playingPane.onPlaceNote = { [weak self] lane, pulse in
            self?.onPlaceNote?(lane, pulse)
        }
        host.addSubview(playingPane)
        addPane(to: host, frame: local(frames.footerCorner), label: "")
        addPane(to: host, frame: local(frames.footerMaster), label: "")
        addPane(to: host, frame: local(frames.footerPlaying), label: "")
    }

    private func addStatusBar() {
        let bar = FlippedDialogView(frame: BmsONEMainWindowLayout.statusBarFrame)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(bar)

        var x: CGFloat = 0
        let sections: [(String, CGSize)] = [
            ("Abs", BmsONEStatusBarLayout.absoluteLocation),
            ("Loc", BmsONEStatusBarLayout.location),
            ("Time", BmsONEStatusBarLayout.realTime),
            ("Lane", BmsONEStatusBarLayout.lane)
        ]
        for (title, size) in sections {
            let field = NSTextField(labelWithString: NativeLocalization.text(title))
            NativeLocalization.markFixed(field, key: title)
            field.frame = CGRect(x: x, y: 0, width: size.width, height: size.height)
            field.font = .systemFont(ofSize: 11)
            bar.addSubview(field)
            x += size.width
        }
    }

    private func addPane(to host: NSView, frame: CGRect, label: String) {
        guard frame.width > 0, frame.height > 0 else { return }
        let pane = FlippedDialogView(frame: frame)
        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        pane.layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 1).cgColor
        pane.layer?.borderWidth = 1
        if !label.isEmpty {
            let field = NSTextField(labelWithString: NativeLocalization.text(label))
            NativeLocalization.markFixed(field, key: label)
            field.frame = CGRect(x: 4, y: 4, width: max(frame.width - 8, 0), height: 16)
            field.textColor = .secondaryLabelColor
            field.font = .systemFont(ofSize: 10)
            pane.addSubview(field)
        }
        host.addSubview(pane)
    }
}

@MainActor
private final class BmsONEPlayingPaneView: FlippedDialogView {
    var document: BmsONEDocument?
    var onPlaceNote: ((Int64, Int64) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 1).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pane = bounds
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        pane.fill()

        let lanes = BmsONEPlayingLaneLayout.laneFrames(in: pane)
        for (index, lane) in lanes.enumerated() {
            let fill = index % 2 == 0
                ? NSColor(calibratedWhite: 0.22, alpha: 1)
                : NSColor(calibratedWhite: 0.16, alpha: 1)
            fill.setFill()
            lane.fill()
        }

        guard let document else { return }
        let resolution = document.resolution
        NSColor(calibratedRed: 0.85, green: 0.72, blue: 0.28, alpha: 1).setFill()
        for channel in document.soundChannels {
            for note in channel.notes {
                guard let rect = BmsONEPlayingLaneLayout.noteRect(
                    x: note.x,
                    y: note.y,
                    l: note.l,
                    resolution: resolution,
                    in: pane
                ) else { continue }
                rect.fill()
            }
        }

        let label = NSAttributedString(
            string: NativeLocalization.text("Playing"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        label.draw(in: CGRect(x: 4, y: 4, width: max(pane.width - 8, 0), height: 16))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let pane = bounds
        let resolution = document?.resolution ?? BmsONEInfoDefaults.resolution
        if let document {
            for channel in document.soundChannels {
                for note in channel.notes {
                    if let rect = BmsONEPlayingLaneLayout.noteRect(
                        x: note.x,
                        y: note.y,
                        l: note.l,
                        resolution: resolution,
                        in: pane
                    ), rect.contains(point) {
                        return
                    }
                }
            }
        }
        guard let lane = BmsONEPlayingLaneLayout.laneX(at: point, in: pane) else { return }
        let pulse = BmsONEPlayingLaneLayout.pulseY(at: point, in: pane, resolution: resolution)
        onPlaceNote?(lane, pulse)
    }
}
