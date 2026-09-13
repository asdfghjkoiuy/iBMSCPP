import AppKit

/// MIDI 导入设置窗。对照 `LoadSmfDialog`。
///
/// 客户区按源码构造 `wxSize(290, 130)`。源码随即 `SetSizerAndFit`，
/// 最终客户区不能从源码定死。未截图，不能写成像素已通过。
@MainActor
final class BmhelperMidiImportWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmhelperMidiImportView

    init() {
        let size = BmhelperMidiImportLayout.clientSize
        var style: NSWindow.StyleMask = [.titled]
        if BmhelperMidiImportLayout.hasCloseBox {
            style.insert(.closable)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text(BmhelperMidiImportLayout.title)
        NativeLocalization.markFixed(window, key: BmhelperMidiImportLayout.title)
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentMaxSize = size
        dialogView = BmhelperMidiImportView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(file: BmhelperMidiFile, onOK: @escaping (BmhelperMidiImportSettings) -> Void) {
        dialogView.apply(file: file, onOK: onOK)
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
private final class BmhelperMidiImportView: FlippedDialogView {
    private let tracksLabel = NSTextField(labelWithString: NativeLocalization.text(BmhelperMidiImportLayout.tracksTitle))
    private let tracksChoice = NSPopUpButton(frame: BmhelperMidiImportLayout.tracksChoice, pullsDown: false)
    private let channelsLabel = NSTextField(labelWithString: NativeLocalization.text(BmhelperMidiImportLayout.channelsTitle))
    private let channelBoxes: [NSButton]
    private let okButton = NSButton(title: NativeLocalization.text(BmhelperMidiImportLayout.okTitle), target: nil, action: nil)
    private var onOK: ((BmhelperMidiImportSettings) -> Void)?

    override init(frame frameRect: NSRect) {
        channelBoxes = (0..<16).map { index in
            let box = NSButton(checkboxWithTitle: BmhelperMidiImportText.channelTitle(index), target: nil, action: nil)
            box.state = .on
            box.frame = BmhelperMidiImportLayout.channelFrame(index)
            return box
        }
        super.init(frame: NSRect(origin: .zero, size: BmhelperMidiImportLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        NativeLocalization.markFixed(tracksLabel, key: BmhelperMidiImportLayout.tracksTitle)
        NativeLocalization.markFixed(channelsLabel, key: BmhelperMidiImportLayout.channelsTitle)
        NativeLocalization.markFixed(okButton, key: BmhelperMidiImportLayout.okTitle)

        tracksLabel.frame = BmhelperMidiImportLayout.tracksLabel
        addSubview(tracksLabel)
        addSubview(tracksChoice)
        channelsLabel.frame = BmhelperMidiImportLayout.channelsLabel
        addSubview(channelsLabel)
        for box in channelBoxes {
            addSubview(box)
        }
        okButton.frame = BmhelperMidiImportLayout.ok
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.target = self
        okButton.action = #selector(confirm)
        addSubview(okButton)
    }

    required init?(coder: NSCoder) { nil }

    func apply(file: BmhelperMidiFile, onOK: @escaping (BmhelperMidiImportSettings) -> Void) {
        self.onOK = onOK
        tracksChoice.removeAllItems()
        for track in file.tracks {
            tracksChoice.addItem(withTitle: BmhelperMidiImportText.trackChoice(index: track.index, name: track.name))
        }
        let defaults = BmhelperMidiImportSettings.makeDefault(for: file)
        if file.tracks.indices.contains(defaults.selectedTrackIndex) {
            tracksChoice.selectItem(at: defaults.selectedTrackIndex)
        }
        for (index, box) in channelBoxes.enumerated() {
            box.state = defaults.channelMask[index] ? .on : .off
        }
    }

    @objc private func confirm() {
        var mask = Array(repeating: false, count: 16)
        for (index, box) in channelBoxes.enumerated() {
            mask[index] = box.state == .on
        }
        let settings = BmhelperMidiImportSettings(
            selectedTrackIndex: max(tracksChoice.indexOfSelectedItem, 0),
            channelMask: mask
        )
        onOK?(settings)
        window?.orderOut(self)
    }
}
