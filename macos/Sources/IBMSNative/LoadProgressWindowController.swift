import AppKit

@MainActor
final class LoadProgressWindowController: NSWindowController {
    private let content = LoadProgressDialogView()
    private var cancelled = false
    private var running = false

    init() {
        let size = LoadProgressLayout.clientSize
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = LoadProgressLayout.title
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.moveToActiveSpace, .transient]
        window.contentMinSize = size
        window.contentMaxSize = size
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        window.defaultButtonCell = content.cancelButton.cell as? NSButtonCell
        content.onCancel = { [weak self] in self?.cancel() }
    }

    required init?(coder: NSCoder) { nil }

    func present(
        paths: [String],
        isSaved: Bool,
        loadCurrent: @escaping (String) -> Void,
        loadNewProcess: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        guard !paths.isEmpty, !running else {
            completion()
            return
        }
        cancelled = false
        running = true
        content.prepare(count: paths.count)
        window?.center()
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
        DispatchQueue.main.async { [weak self] in
            self?.run(paths: paths, isSaved: isSaved, loadCurrent: loadCurrent, loadNewProcess: loadNewProcess, completion: completion)
        }
    }

    private func run(
        paths: [String],
        isSaved: Bool,
        loadCurrent: @escaping (String) -> Void,
        loadNewProcess: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        for index in paths.indices {
            content.update(index: index, count: paths.count, path: paths[index])
            pump()
            if cancelled { break }
            switch LegacyLoadProgress.destination(index: index, isSaved: isSaved) {
            case .currentWindow:
                loadCurrent(paths[index])
            case .newProcess:
                loadNewProcess(paths[index])
            }
        }
        window?.orderOut(self)
        running = false
        completion()
    }

    private func cancel() {
        cancelled = true
        window?.orderOut(self)
    }

    private func pump() {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
}

@MainActor
private final class LoadProgressDialogView: FlippedDialogView {
    var onCancel: (() -> Void)?
    let cancelButton: NSButton
    private let label: NSTextField
    private let progress: NSProgressIndicator

    override init(frame frameRect: NSRect) {
        label = NSTextField(wrappingLabelWithString: "")
        progress = NSProgressIndicator(frame: LoadProgressLayout.progress)
        cancelButton = NSButton(title: LoadProgressLayout.cancelTitle, target: nil, action: nil)
        super.init(frame: NSRect(origin: .zero, size: LoadProgressLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        label.frame = LoadProgressLayout.label
        label.font = LegacyChromeFont.segoe
        label.alignment = .left
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        addSubview(label)

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.controlSize = .small
        addSubview(progress)

        cancelButton.frame = LoadProgressLayout.cancel
        cancelButton.bezelStyle = .rounded
        cancelButton.font = LegacyChromeFont.segoe
        cancelButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        addSubview(cancelButton)
    }

    required init?(coder: NSCoder) { nil }

    func prepare(count: Int) {
        progress.maxValue = Double(LegacyLoadProgress.progressMaximum(fileCount: count))
        progress.doubleValue = 0
        label.stringValue = ""
    }

    func update(index: Int, count: Int, path: String) {
        label.stringValue = LegacyLoadProgress.statusText(index: index, count: count, path: path)
        progress.doubleValue = Double(LegacyLoadProgress.progressValue(beforeLoading: index))
        displayIfNeeded()
    }

    override func cancelOperation(_ sender: Any?) {
        cancel()
    }

    @objc private func cancel() {
        onCancel?()
    }
}
