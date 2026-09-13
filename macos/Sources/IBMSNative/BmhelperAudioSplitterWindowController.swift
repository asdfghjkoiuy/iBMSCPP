import AppKit
import UniformTypeIdentifiers

/// 对照 `AudioSplitter`。宽按源码 `800`，高用工作值 `360`。不可改大小。未截图。
@MainActor
final class BmhelperAudioSplitterWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmhelperAudioSplitterView

    init() {
        let size = BmhelperAudioSplitterLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.format(
            "Audio splitter (division: \"%@\")",
            BmhelperDefDialogLayout.defaultName
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentMaxSize = size
        dialogView = BmhelperAudioSplitterView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(divisionName: String, notes: [MidiNoteEvent], quantize: Int) {
        window?.title = NativeLocalization.format("Audio splitter (division: \"%@\")", divisionName)
        dialogView.apply(divisionName: divisionName, notes: notes, quantize: quantize)
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
private final class BmhelperAudioSplitterView: FlippedDialogView, NSTextFieldDelegate {
    private let inputField = NSTextField(string: "")
    private let outputField = NSTextField(string: "")
    private let prefixField = NSTextField(string: "")
    private let bpmField = NSTextField(string: "120")
    private let offsetField = NSTextField(string: "0")
    private var notes: [MidiNoteEvent] = []
    private var quantize = 480

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmhelperAudioSplitterLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])

        addLabel(BmhelperAudioSplitterLayout.audioFileTitle, x: 10, y: 10, width: 200)
        addLabel(BmhelperAudioSplitterLayout.dropHint, x: 10, y: 32, width: 780)
        inputField.frame = NSRect(x: 10, y: 56, width: 680, height: 22)
        addSubview(inputField)
        addButton(BmhelperAudioSplitterLayout.browseTitle, x: 700, y: 52, width: 90, action: #selector(browseInput))

        addLabel(BmhelperAudioSplitterLayout.outputDirectoryTitle, x: 10, y: 92, width: 200)
        outputField.frame = NSRect(x: 10, y: 116, width: 680, height: 22)
        addSubview(outputField)
        addButton(BmhelperAudioSplitterLayout.browseTitle, x: 700, y: 112, width: 90, action: #selector(browseOutput))

        addLabel(BmhelperAudioSplitterLayout.prefixTitle, x: 10, y: 152, width: 220)
        prefixField.frame = NSRect(x: 230, y: 148, width: 240, height: 22)
        addSubview(prefixField)

        addLabel(BmhelperAudioSplitterLayout.sliceParametersTitle, x: 10, y: 188, width: 200)
        addLabel(BmhelperAudioSplitterLayout.bpmTitle, x: 10, y: 216, width: 50)
        bpmField.frame = NSRect(x: 60, y: 212, width: 80, height: 22)
        addSubview(bpmField)
        addLabel(BmhelperAudioSplitterLayout.offsetTitle, x: 160, y: 216, width: 120)
        offsetField.frame = NSRect(x: 280, y: 212, width: 80, height: 22)
        addSubview(offsetField)

        addButton(BmhelperAudioSplitterLayout.splitTitle, x: 620, y: 320, width: 80, action: #selector(split))
        addButton(BmhelperAudioSplitterLayout.closeTitle, x: 710, y: 320, width: 80, action: #selector(closeSplitter))
    }

    required init?(coder: NSCoder) { nil }

    func apply(divisionName: String, notes: [MidiNoteEvent], quantize: Int) {
        self.notes = notes
        self.quantize = max(quantize, 1)
        prefixField.stringValue = divisionName.isEmpty ? BmhelperDefDialogLayout.defaultName : divisionName
        bpmField.stringValue = String(format: "%.\(BmhelperAudioSplitterLayout.bpmDigits)f", BmhelperAudioSplitterLayout.defaultBpm)
        offsetField.stringValue = String(Int(BmhelperAudioSplitterLayout.defaultOffsetMs))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first
        else {
            return false
        }
        setInput(url)
        return true
    }

    @objc private func browseInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.wav]
        panel.message = NativeLocalization.text(BmhelperAudioSplitterLayout.selectAudioTitle)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setInput(url)
    }

    @objc private func browseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NativeLocalization.text(BmhelperAudioSplitterLayout.selectOutputTitle)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputField.stringValue = url.path
        if !outputField.stringValue.hasSuffix("/") {
            outputField.stringValue += "/"
        }
    }

    @objc private func split() {
        let input = URL(fileURLWithPath: inputField.stringValue)
        let output = URL(fileURLWithPath: outputField.stringValue, isDirectory: true)
        let prefix = prefixField.stringValue.isEmpty
            ? BmhelperDefDialogLayout.defaultName
            : prefixField.stringValue
        let bpm = clamped(
            Double(bpmField.stringValue) ?? BmhelperAudioSplitterLayout.defaultBpm,
            BmhelperAudioSplitterLayout.bpmMinimum,
            BmhelperAudioSplitterLayout.bpmMaximum
        )
        let offset = clamped(
            Double(offsetField.stringValue) ?? BmhelperAudioSplitterLayout.defaultOffsetMs,
            BmhelperAudioSplitterLayout.offsetMinimum,
            BmhelperAudioSplitterLayout.offsetMaximum
        )
        do {
            _ = try BmhelperWavSplit.splitFile(
                input: input,
                outputDirectory: output,
                prefix: prefix,
                notes: notes,
                quantize: quantize,
                bpm: bpm,
                offsetMs: offset
            )
        } catch {
            presentSplitError(error)
        }
    }

    @objc private func closeSplitter() {
        window?.orderOut(self)
    }

    private func setInput(_ url: URL) {
        inputField.stringValue = url.path
        if outputField.stringValue.isEmpty {
            outputField.stringValue = url.deletingLastPathComponent().path
            if !outputField.stringValue.hasSuffix("/") {
                outputField.stringValue += "/"
            }
        }
    }

    private func presentSplitError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = NativeLocalization.text(BmhelperAudioSplitterLayout.errorTitle)
        if let splitError = error as? BmhelperWavSplitError {
            alert.informativeText = splitError.localizedDescription
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.alertStyle = .critical
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func clamped(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    private func addLabel(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        let field = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(field, key: title)
        field.frame = NSRect(x: x, y: y, width: width, height: 16)
        addSubview(field)
    }

    private func addButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) {
        let button = NSButton(title: NativeLocalization.text(title), target: self, action: action)
        NativeLocalization.markFixed(button, key: title)
        button.frame = NSRect(x: x, y: y, width: width, height: 28)
        button.bezelStyle = .rounded
        addSubview(button)
    }
}
