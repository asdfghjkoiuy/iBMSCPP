import AppKit

@MainActor
final class GeneralOptionsWindowController: NSWindowController {
    private let content = GeneralOptionsDialogView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: GeneralOptionsLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "General Options"
        NativeLocalization.markFixed(window, key: "General Options")
        window.isReleasedWhenClosed = false
        window.contentMinSize = GeneralOptionsLayout.clientSize
        window.contentMaxSize = GeneralOptionsLayout.clientSize
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onCancel = { [weak self] in self?.end(nil) }
        content.onOK = { [weak self] settings in self?.end(settings) }
    }

    required init?(coder: NSCoder) { nil }

    private var pendingResult: EditorSettings?

    func present(over parent: NSWindow, settings: EditorSettings, completion: @escaping (EditorSettings?) -> Void) {
        pendingResult = nil
        content.load(settings)
        guard let sheet = window else {
            completion(nil)
            return
        }
        parent.beginSheet(sheet) { [weak self] _ in
            completion(self?.pendingResult)
        }
    }

    private func end(_ settings: EditorSettings?) {
        pendingResult = settings
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class GeneralOptionsDialogView: FlippedDialogView {
    var onOK: ((EditorSettings) -> Void)?
    var onCancel: (() -> Void)?

    private let encoding = OptionDialogControls.popup(titles: GeneralOptionsLayout.encodingTitles, frame: GeneralOptionsLayout.encoding)
    private let wheel = OptionDialogControls.popup(titles: GeneralOptionsLayout.wheelTitles, frame: GeneralOptionsLayout.wheel)
    private let page = OptionDialogControls.popup(titles: GeneralOptionsLayout.pageTitles, frame: GeneralOptionsLayout.page)
    private let gridPartition = OptionDialogControls.integerField(
        frame: GeneralOptionsLayout.gridPartition,
        value: 192,
        range: GeneralOptionsLayout.gridPartitionRange
    )
    private let autoSaveMinutes = OptionDialogControls.decimalField(
        frame: GeneralOptionsLayout.autoSaveMinutes,
        value: 2,
        range: GeneralOptionsLayout.autoSaveMinuteRange,
        digits: 1
    )
    private var autoSave: NSButton!
    private var beep: NSButton!
    private var bpm1296: NSButton!
    private var stop1296: NSButton!
    private var mouseEnterFocus: NSButton!
    private var firstClickDisabled: NSButton!
    private var stopPreview: NSButton!
    private var middleAuto: NSButton!
    private var middleDrag: NSButton!
    private var draft = EditorSettings.legacyDefault

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: GeneralOptionsLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addSubview(OptionDialogControls.label("Text Encoding", frame: GeneralOptionsLayout.encodingLabel))
        addSubview(encoding)
        addSubview(OptionDialogControls.label("Associate Filetype", frame: GeneralOptionsLayout.associateLabel))
        addAssociate("*.bms", frame: GeneralOptionsLayout.associateBMS)
        addAssociate("*.ibmsc", frame: GeneralOptionsLayout.associateIBMSC)
        addAssociate("*.bme", frame: GeneralOptionsLayout.associateBME)
        addAssociate("*.bml", frame: GeneralOptionsLayout.associateBML)
        addAssociate("*.pms", frame: GeneralOptionsLayout.associatePMS)
        addSubview(OptionDialogControls.label("Max Grid Partition in BMS", frame: GeneralOptionsLayout.gridPartitionLabel))
        addSubview(gridPartition)

        autoSave = OptionDialogControls.checkbox("AutoSave", frame: GeneralOptionsLayout.autoSave, target: self, action: #selector(toggleAutoSave))
        addSubview(autoSave)
        addSubview(autoSaveMinutes)
        addSubview(OptionDialogControls.label("minutes", frame: GeneralOptionsLayout.minutesLabel, align: .left))
        beep = OptionDialogControls.checkbox("Beep while saved", frame: GeneralOptionsLayout.beep, target: nil, action: nil)
        addSubview(beep)
        bpm1296 = OptionDialogControls.checkbox("Extend number of multi-byte BPMs to 1296", frame: GeneralOptionsLayout.bpm1296, target: nil, action: nil)
        addSubview(bpm1296)
        stop1296 = OptionDialogControls.checkbox("Extend number of STOPs to 1296", frame: GeneralOptionsLayout.stop1296, target: nil, action: nil)
        addSubview(stop1296)

        addSubview(OptionDialogControls.rule(GeneralOptionsLayout.divider))
        addSubview(OptionDialogControls.label("Mouse Wheel", frame: GeneralOptionsLayout.wheelLabel))
        addSubview(wheel)
        addSubview(OptionDialogControls.label("PageUp / PageDown", frame: GeneralOptionsLayout.pageLabel))
        addSubview(page)
        addSubview(OptionDialogControls.label("Mouse Middle Button", frame: GeneralOptionsLayout.middleLabel))
        middleAuto = OptionDialogControls.radio("Click and Auto Scroll", frame: GeneralOptionsLayout.middleAuto, target: self, action: #selector(selectMiddleAuto))
        middleDrag = OptionDialogControls.radio("Click and Drag", frame: GeneralOptionsLayout.middleDrag, target: self, action: #selector(selectMiddleDrag))
        addSubview(middleAuto)
        addSubview(middleDrag)
        mouseEnterFocus = OptionDialogControls.checkbox(
            "Automatically set focus to editing panel on mouse enter",
            frame: GeneralOptionsLayout.mouseEnterFocus,
            target: nil,
            action: nil
        )
        addSubview(mouseEnterFocus)
        firstClickDisabled = OptionDialogControls.checkbox(
            "Disable first click if the editing panel is not focused",
            frame: GeneralOptionsLayout.firstClickDisabled,
            target: nil,
            action: nil
        )
        addSubview(firstClickDisabled)
        stopPreview = OptionDialogControls.checkbox(
            "Stop preview if clicked on the editing panel",
            frame: GeneralOptionsLayout.stopPreview,
            target: nil,
            action: nil
        )
        addSubview(stopPreview)

        let ok = OptionDialogControls.button("OK", frame: GeneralOptionsLayout.ok, target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        addSubview(ok)
        let cancel = OptionDialogControls.button("Cancel", frame: GeneralOptionsLayout.cancel, target: self, action: #selector(cancelDialog))
        cancel.keyEquivalent = "\u{1b}"
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func load(_ settings: EditorSettings) {
        draft = settings
        let encodingIndex = settings.textEncodingIndex
        if (0..<encoding.numberOfItems).contains(encodingIndex) {
            encoding.selectItem(at: encodingIndex)
        }
        wheel.selectItem(at: GeneralOptionsLayout.wheelIndex(for: settings.wheelStep))
        page.selectItem(at: GeneralOptionsLayout.pageIndex(for: settings.pageStep))
        gridPartition.integerValue = settings.gridPartition
        let autosave = GeneralOptionsLayout.autoSaveDisplay(milliseconds: settings.autoSaveMilliseconds)
        autoSave.state = autosave.enabled ? .on : .off
        autoSaveMinutes.doubleValue = autosave.minutes
        autoSaveMinutes.isEnabled = autosave.enabled
        beep.state = settings.beepWhileSaved ? .on : .off
        bpm1296.state = settings.bpm1296 ? .on : .off
        stop1296.state = settings.stop1296 ? .on : .off
        middleAuto.state = settings.middleButtonMoveMethod == 0 ? .on : .off
        middleDrag.state = settings.middleButtonMoveMethod == 1 ? .on : .off
        mouseEnterFocus.state = settings.mouseEnterFocus ? .on : .off
        firstClickDisabled.state = settings.firstClickDisabled ? .on : .off
        stopPreview.state = settings.stopPreviewOnClick ? .on : .off
    }

    @objc private func toggleAutoSave() {
        autoSaveMinutes.isEnabled = autoSave.state == .on
    }

    @objc private func selectMiddleAuto() {
        middleAuto.state = .on
        middleDrag.state = .off
    }

    @objc private func selectMiddleDrag() {
        middleAuto.state = .off
        middleDrag.state = .on
    }

    @objc private func confirm() {
        var next = draft
        next.textEncodingIndex = max(0, encoding.indexOfSelectedItem)
        next.wheelStep = GeneralOptionsLayout.wheelValue(at: wheel.indexOfSelectedItem)
        next.pageStep = GeneralOptionsLayout.pageValue(at: page.indexOfSelectedItem)
        next.gridPartition = OptionDialogControls.integer(
            from: gridPartition,
            default: 192,
            range: GeneralOptionsLayout.gridPartitionRange
        )
        next.autoSaveMilliseconds = GeneralOptionsLayout.autoSaveMilliseconds(
            enabled: autoSave.state == .on,
            minutes: OptionDialogControls.double(
                from: autoSaveMinutes,
                default: 2,
                range: GeneralOptionsLayout.autoSaveMinuteRange
            )
        )
        next.beepWhileSaved = beep.state == .on
        next.bpm1296 = bpm1296.state == .on
        next.stop1296 = stop1296.state == .on
        next.middleButtonMoveMethod = middleDrag.state == .on ? 1 : 0
        next.mouseEnterFocus = mouseEnterFocus.state == .on
        next.firstClickDisabled = firstClickDisabled.state == .on
        next.stopPreviewOnClick = stopPreview.state == .on
        onOK?(next)
    }

    @objc private func cancelDialog() {
        onCancel?()
    }

    @objc private func associateFileType() {
        let alert = NSAlert()
        alert.messageText = "File association is a Windows registry setting."
        alert.informativeText = "macOS does not write those keys. Use Finder → Get Info → Open with to choose this app."
        NativeLocalization.localize(alert: alert)
        alert.alertStyle = .informational
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func addAssociate(_ title: String, frame: CGRect) {
        addSubview(OptionDialogControls.button(title, frame: frame, target: self, action: #selector(associateFileType)))
    }
}
