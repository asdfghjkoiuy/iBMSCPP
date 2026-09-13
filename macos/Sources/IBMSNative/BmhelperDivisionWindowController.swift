import AppKit

/// Division 设置窗。对照 `DivisionSettingDialog`。
/// 客户区按源码构造 `330 × 455`。随后 `SetSizerAndFit`，未截图。
@MainActor
final class BmhelperDivisionSettingWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmhelperDivisionSettingView

    init() {
        let size = BmhelperDivisionSettingLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text(BmhelperDivisionSettingLayout.title)
        NativeLocalization.markFixed(window, key: BmhelperDivisionSettingLayout.title)
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        dialogView = BmhelperDivisionSettingView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.registerKnownStaticControls(in: dialogView)
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(setting: BmhelperDivisionSetting, quantize: Int, onOK: @escaping (BmhelperDivisionSetting) -> Void) {
        dialogView.apply(setting: setting, quantize: quantize, onOK: onOK)
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
private final class BmhelperDivisionSettingView: FlippedDialogView {
    private let name = NSTextField(string: "")
    private let srcCopy = NSButton(
        checkboxWithTitle: BmhelperDivisionSettingLayout.srcCopyTitle,
        target: nil,
        action: nil
    )
    private let headMargin = NSTextField(string: "0")
    private let minInterval = NSTextField(string: "1")
    private let sort = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gate = NSTextField(string: "0")
    private let velocity = NSTextField(string: "5")
    private let zz = NSButton(
        checkboxWithTitle: BmhelperDivisionSettingLayout.zzTitle,
        target: nil,
        action: nil
    )
    private let ml = NSButton(
        checkboxWithTitle: BmhelperDivisionSettingLayout.mlTitle,
        target: nil,
        action: nil
    )
    private let start = NSTextField(string: "01")
    private let mlInterval = NSTextField(string: "0.5")
    private var quantize = 480
    private var onOK: ((BmhelperDivisionSetting) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmhelperDivisionSettingLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        NativeLocalization.markFixed(srcCopy, key: BmhelperDivisionSettingLayout.srcCopyTitle)
        NativeLocalization.markFixed(zz, key: BmhelperDivisionSettingLayout.zzTitle)
        NativeLocalization.markFixed(ml, key: BmhelperDivisionSettingLayout.mlTitle)

        addLabel(BmhelperDivisionSettingLayout.nameTitle, x: 8, y: 8, width: 80)
        name.frame = NSRect(x: 96, y: 6, width: 226, height: 22)
        addSubview(name)

        srcCopy.frame = NSRect(x: 8, y: 36, width: 314, height: 20)
        addSubview(srcCopy)

        addLabel(BmhelperDivisionSettingLayout.headMarginTitle, x: 8, y: 64, width: 160)
        headMargin.frame = NSRect(x: 176, y: 62, width: 146, height: 22)
        addSubview(headMargin)
        addLabel(BmhelperDivisionSettingLayout.minIntervalTitle, x: 8, y: 92, width: 160)
        minInterval.frame = NSRect(x: 176, y: 90, width: 146, height: 22)
        addSubview(minInterval)
        addLabel(BmhelperDivisionSettingLayout.sortTitle, x: 8, y: 120, width: 160)
        sort.frame = NSRect(x: 176, y: 118, width: 146, height: 24)
        for title in BmhelperDivisionSettingLayout.sortTitles {
            sort.addItem(withTitle: title)
        }
        addSubview(sort)

        addLabel(BmhelperDivisionSettingLayout.gateTitle, x: 8, y: 156, width: 160)
        gate.frame = NSRect(x: 176, y: 154, width: 146, height: 22)
        addSubview(gate)
        addLabel(BmhelperDivisionSettingLayout.velocityTitle, x: 8, y: 184, width: 160)
        velocity.frame = NSRect(x: 176, y: 182, width: 146, height: 22)
        addSubview(velocity)

        zz.frame = NSRect(x: 8, y: 220, width: 314, height: 20)
        addSubview(zz)
        ml.frame = NSRect(x: 8, y: 244, width: 314, height: 20)
        addSubview(ml)
        addLabel(BmhelperDivisionSettingLayout.startTitle, x: 8, y: 272, width: 160)
        start.frame = NSRect(x: 176, y: 270, width: 146, height: 22)
        addSubview(start)
        addLabel(BmhelperDivisionSettingLayout.mlIntervalTitle, x: 8, y: 300, width: 160)
        mlInterval.frame = NSRect(x: 176, y: 298, width: 146, height: 22)
        addSubview(mlInterval)

        let ok = NSButton(title: BmhelperDivisionSettingLayout.okTitle, target: nil, action: nil)
        ok.frame = NSRect(x: 166, y: 419, width: 76, height: 28)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        ok.target = self
        ok.action = #selector(confirm)
        addSubview(ok)

        let cancel = NSButton(title: BmhelperDivisionSettingLayout.cancelTitle, target: nil, action: nil)
        cancel.frame = NSRect(x: 246, y: 419, width: 76, height: 28)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelDialog)
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func apply(
        setting: BmhelperDivisionSetting,
        quantize: Int,
        onOK: @escaping (BmhelperDivisionSetting) -> Void
    ) {
        self.quantize = max(quantize, 1)
        self.onOK = onOK
        name.stringValue = setting.name
        srcCopy.state = setting.srcCopy ? .on : .off
        headMargin.stringValue = beatsString(setting.headMargin)
        minInterval.stringValue = beatsString(setting.minInterval)
        sort.selectItem(at: setting.sortType.rawValue)
        gate.stringValue = beatsString(setting.gateThreshold)
        velocity.stringValue = String(setting.velocityThreshold)
        zz.state = setting.zzDefinition ? .on : .off
        ml.state = setting.mlDefinition ? .on : .off
        start.stringValue = ZZNumber(setting.startDefinition).to_string()
        mlInterval.stringValue = beatsString(setting.mlThreshold)
    }

    @objc private func confirm() {
        var zzNumber = ZZNumber(BmhelperDefDialogLayout.defaultStartDefinition)
        _ = zzNumber.from_string(start.stringValue)
        let setting = BmhelperDivisionSetting(
            name: name.stringValue,
            srcCopy: srcCopy.state == .on,
            headMargin: ticks(fromBeats: headMargin.stringValue),
            minInterval: ticks(fromBeats: minInterval.stringValue),
            sortType: BmhelperDivisionSort(rawValue: max(sort.indexOfSelectedItem, 0)) ?? .nnGateVel,
            gateThreshold: ticks(fromBeats: gate.stringValue),
            velocityThreshold: Int(velocity.stringValue) ?? 5,
            zzDefinition: zz.state == .on,
            mlDefinition: ml.state == .on,
            startDefinition: zzNumber.integerValue,
            mlThreshold: ticks(fromBeats: mlInterval.stringValue)
        )
        onOK?(setting)
        window?.orderOut(self)
    }

    @objc private func cancelDialog() {
        window?.orderOut(self)
    }

    private func beatsString(_ ticks: Int) -> String {
        String(Double(ticks) / Double(quantize))
    }

    private func ticks(fromBeats text: String) -> Int {
        Int((Double(text) ?? 0) * Double(quantize))
    }

    private func addLabel(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        let field = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(field, key: title)
        field.frame = NSRect(x: x, y: y, width: width, height: 16)
        addSubview(field)
    }
}
