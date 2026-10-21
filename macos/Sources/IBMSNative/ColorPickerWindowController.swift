import AppKit

@MainActor
final class ColorPickerWindowController: NSWindowController {
    private let content = ColorPickerDialogView()
    private var pendingResult: ThemeColor?

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ColorPickerLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ColorPicker"
        NativeLocalization.markFixed(window, key: "ColorPicker")
        window.isReleasedWhenClosed = false
        window.contentMinSize = ColorPickerLayout.clientSize
        window.contentMaxSize = ColorPickerLayout.clientSize
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onOK = { [weak self] color in self?.end(color) }
        content.onCancel = { [weak self] in self?.end(nil) }
    }

    required init?(coder: NSCoder) { nil }

    func present(over parent: NSWindow, color: ThemeColor, completion: @escaping (ThemeColor?) -> Void) {
        pendingResult = nil
        content.load(color)
        guard let sheet = window else {
            completion(nil)
            return
        }
        parent.beginSheet(sheet) { [weak self] _ in
            completion(self?.pendingResult)
        }
    }

    func dismissIfNeeded() {
        guard let window, window.sheetParent != nil else { return }
        pendingResult = nil
        window.sheetParent?.endSheet(window)
    }

    private func end(_ color: ThemeColor?) {
        pendingResult = color
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class ColorPickerDialogView: FlippedDialogView {
    var onOK: ((ThemeColor) -> Void)?
    var onCancel: (() -> Void)?

    private var origColor = ThemeColor(argb: 0xFF00_0000)
    private var current = ThemeColor(argb: 0xFF00_0000)
    private var channel = ColorPickerLayout.defaultChannel
    private var hue = 0
    private var saturation = 0
    private var lightness = 0
    private var red = 0
    private var green = 0
    private var blue = 0
    private var alpha = ColorPickerLayout.defaultAlpha
    private var precision = ColorPickerLayout.defaultPrecision
    private var passive = false

    private let preview = ColorPreviewView(frame: ColorPickerLayout.preview)
    private let mainSquare = ColorSquareView(frame: ColorPickerLayout.mainInner)
    private let sliderBar = ColorSliderView(frame: ColorPickerLayout.sliderInner)
    private let alphaBar = ColorAlphaView(frame: ColorPickerLayout.alphaInner)
    private let hexField = OptionDialogControls.field(frame: ColorPickerLayout.hexField, text: ColorPickerLayout.defaultHex)
    private var channelButtons: [ColorPickerChannel: NSButton] = [:]
    private var channelFields: [ColorPickerChannel: NSTextField] = [:]
    private var alphaField: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: ColorPickerLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        addBordered(ColorPickerLayout.main)
        addBordered(ColorPickerLayout.slider)
        addBordered(ColorPickerLayout.alpha)
        addBordered(ColorPickerLayout.preview)
        addSubview(preview)
        addSubview(mainSquare)
        addSubview(sliderBar)
        addSubview(alphaBar)

        mainSquare.onDrag = { [weak self] x, y in self?.dragMain(x: x, y: y) }
        sliderBar.onDrag = { [weak self] y in self?.dragSlider(y: y) }
        alphaBar.onDrag = { [weak self] x in self?.dragAlpha(x: x) }

        for item in ColorPickerLayout.channels {
            let button = OptionDialogControls.button(item.title, frame: item.button, target: self, action: #selector(selectChannel(_:)))
            button.bezelStyle = .shadowlessSquare
            button.setButtonType(.pushOnPushOff)
            button.tag = item.channel.rawValue
            channelButtons[item.channel] = button
            addSubview(button)
            let field = OptionDialogControls.integerField(frame: item.field, value: 0, range: item.range)
            field.tag = item.channel.rawValue
            field.target = self
            field.action = #selector(channelFieldChanged(_:))
            field.delegate = self
            channelFields[item.channel] = field
            addSubview(field)
        }
        let alphaButton = NSButton(title: "A (0-255)", target: nil, action: nil)
        alphaButton.frame = ColorPickerLayout.alphaButton
        alphaButton.bezelStyle = .shadowlessSquare
        alphaButton.font = LegacyChromeFont.segoe
        alphaButton.focusRingType = .none
        alphaButton.isEnabled = ColorPickerLayout.alphaEnabled
        addSubview(alphaButton)
        alphaField = OptionDialogControls.integerField(frame: ColorPickerLayout.alphaField, value: ColorPickerLayout.defaultAlpha, range: 0...255)
        alphaField.target = self
        alphaField.action = #selector(alphaFieldChanged)
        alphaField.delegate = self
        addSubview(alphaField)

        addSubview(OptionDialogControls.label("Precision:", frame: ColorPickerLayout.precisionLabel, align: .left))
        let slider = NSSlider(value: Double(ColorPickerLayout.defaultPrecision), minValue: 1, maxValue: 10, target: self, action: #selector(precisionChanged(_:)))
        slider.frame = ColorPickerLayout.precision
        slider.numberOfTickMarks = 10
        slider.allowsTickMarkValuesOnly = true
        slider.isVertical = false
        addSubview(slider)
        addSubview(OptionDialogControls.label("#", frame: ColorPickerLayout.hashLabel, align: .left))
        hexField.delegate = self
        addSubview(hexField)

        let ok = OptionDialogControls.button("OK", frame: ColorPickerLayout.ok, target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        addSubview(ok)
        let cancel = OptionDialogControls.button("Cancel", frame: ColorPickerLayout.cancel, target: self, action: #selector(cancelDialog))
        cancel.keyEquivalent = "\u{1b}"
        addSubview(cancel)
        refreshChannelButtons()
    }

    required init?(coder: NSCoder) { nil }

    func load(_ color: ThemeColor) {
        origColor = color
        apply(color, updateHex: true)
        hexField.stringValue = LegacyColorMath.hexARGB(color)
    }

    private func apply(_ color: ThemeColor, updateHex: Bool) {
        current = color
        let rgb = LegacyColorMath.rgba(from: color)
        let hsl = LegacyColorMath.netHSL(from: color)
        red = rgb.red
        green = rgb.green
        blue = rgb.blue
        alpha = rgb.alpha
        hue = hsl.hue
        saturation = hsl.saturation
        lightness = hsl.lightness
        writeFields()
        if updateHex {
            hexField.stringValue = LegacyColorMath.hexARGB(color)
        }
        refreshCanvases()
    }

    private func applyHSL() {
        current = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha))
        let rgb = LegacyColorMath.rgba(from: current)
        red = rgb.red
        green = rgb.green
        blue = rgb.blue
        writeFields()
        hexField.stringValue = LegacyColorMath.hexARGB(current)
        refreshCanvases()
    }

    private func applyRGB() {
        current = ColorPickerRGBA(red: red, green: green, blue: blue, alpha: alpha).themeColor
        let hsl = LegacyColorMath.netHSL(from: current)
        hue = hsl.hue
        saturation = hsl.saturation
        lightness = hsl.lightness
        writeFields()
        hexField.stringValue = LegacyColorMath.hexARGB(current)
        refreshCanvases()
    }

    private func writeFields() {
        passive = true
        channelFields[.hue]?.integerValue = hue
        channelFields[.saturation]?.integerValue = saturation
        channelFields[.lightness]?.integerValue = lightness
        channelFields[.red]?.integerValue = red
        channelFields[.green]?.integerValue = green
        channelFields[.blue]?.integerValue = blue
        alphaField.integerValue = alpha
        passive = false
    }

    private func refreshCanvases() {
        let cursor = LegacyColorMath.cursor(
            channel: channel, hue: hue, saturation: saturation, lightness: lightness,
            red: red, green: green, blue: blue, alpha: alpha
        )
        preview.origColor = origColor
        preview.newColor = current
        preview.origCaptionDark = LegacyColorMath.previewCaptionIsDark(lightness: origLightness(), alpha: Int(origColor.alpha))
        preview.newCaptionDark = LegacyColorMath.previewCaptionIsDark(lightness: lightness, alpha: alpha)
        mainSquare.channel = channel
        mainSquare.hue = hue
        mainSquare.saturation = saturation
        mainSquare.lightness = lightness
        mainSquare.red = red
        mainSquare.green = green
        mainSquare.blue = blue
        mainSquare.precision = precision
        mainSquare.cursor = CGPoint(x: CGFloat(cursor.main.x), y: CGFloat(cursor.main.y))
        mainSquare.cursorDark = LegacyColorMath.sliderCaptionIsDark(lightness: lightness)
        sliderBar.channel = channel
        sliderBar.hue = hue
        sliderBar.saturation = saturation
        sliderBar.lightness = lightness
        sliderBar.red = red
        sliderBar.green = green
        sliderBar.blue = blue
        sliderBar.precision = precision
        sliderBar.cursorY = CGFloat(cursor.slider)
        sliderBar.cursorDark = LegacyColorMath.sliderCaptionIsDark(lightness: lightness)
        alphaBar.red = red
        alphaBar.green = green
        alphaBar.blue = blue
        alphaBar.precision = precision
        alphaBar.cursorX = CGFloat(cursor.alpha)
        alphaBar.cursorDark = LegacyColorMath.alphaCaptionIsDark(lightness: lightness, alpha: alpha)
        preview.needsDisplay = true
        mainSquare.needsDisplay = true
        sliderBar.needsDisplay = true
        alphaBar.needsDisplay = true
    }

    private func origLightness() -> Int {
        LegacyColorMath.netHSL(from: origColor).lightness
    }

    private func dragMain(x: Int, y: Int) {
        let next = LegacyColorMath.applyMainCursor(
            channel: channel, x: x, y: y,
            hue: hue, saturation: saturation, lightness: lightness,
            red: red, green: green, blue: blue
        )
        hue = next.hue
        saturation = next.saturation
        lightness = next.lightness
        red = next.red
        green = next.green
        blue = next.blue
        if channel == .hue || channel == .saturation || channel == .lightness {
            applyHSL()
        } else {
            applyRGB()
        }
    }

    private func dragSlider(y: Int) {
        let next = LegacyColorMath.applySliderCursor(
            channel: channel, y: y,
            hue: hue, saturation: saturation, lightness: lightness,
            red: red, green: green, blue: blue
        )
        hue = next.hue
        saturation = next.saturation
        lightness = next.lightness
        red = next.red
        green = next.green
        blue = next.blue
        if channel == .hue || channel == .saturation || channel == .lightness {
            applyHSL()
        } else {
            applyRGB()
        }
    }

    private func dragAlpha(x: Int) {
        alpha = min(255, max(0, x))
        current = ColorPickerRGBA(red: red, green: green, blue: blue, alpha: alpha).themeColor
        writeFields()
        hexField.stringValue = LegacyColorMath.hexARGB(current)
        refreshCanvases()
    }

    @objc private func selectChannel(_ sender: NSButton) {
        guard let next = ColorPickerChannel(rawValue: sender.tag) else { return }
        channel = next
        refreshChannelButtons()
        refreshCanvases()
    }

    @objc private func channelFieldChanged(_ sender: NSTextField) {
        commitChannelField(sender)
    }

    @objc private func alphaFieldChanged() {
        guard !passive else { return }
        alpha = OptionDialogControls.integer(from: alphaField, default: alpha, range: 0...255)
        current = ColorPickerRGBA(red: red, green: green, blue: blue, alpha: alpha).themeColor
        hexField.stringValue = LegacyColorMath.hexARGB(current)
        refreshCanvases()
    }

    @objc private func precisionChanged(_ sender: NSSlider) {
        precision = min(ColorPickerLayout.precisionRange.upperBound, max(ColorPickerLayout.precisionRange.lowerBound, Int(sender.doubleValue.rounded())))
        refreshCanvases()
    }

    @objc private func confirm() {
        onOK?(current)
    }

    @objc private func cancelDialog() {
        onCancel?()
    }

    private func commitChannelField(_ sender: NSTextField) {
        guard !passive, let selected = ColorPickerChannel(rawValue: sender.tag) else { return }
        let value = OptionDialogControls.integer(from: sender, default: 0, range: 0...10_000)
        switch selected {
        case .hue:
            hue = LegacyColorMath.wrapHue(min(360, value))
            applyHSL()
        case .saturation:
            saturation = min(1000, max(0, value))
            applyHSL()
        case .lightness:
            lightness = min(1000, max(0, value))
            applyHSL()
        case .red:
            red = min(255, max(0, value))
            applyRGB()
        case .green:
            green = min(255, max(0, value))
            applyRGB()
        case .blue:
            blue = min(255, max(0, value))
            applyRGB()
        }
    }

    private func commitHex() {
        guard !passive else { return }
        if let color = LegacyColorMath.parseHex(hexField.stringValue) {
            apply(color, updateHex: true)
        } else {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "The hex value is not a valid 32-bit integer."
            alert.alertStyle = .critical
            if let window { alert.beginSheetModal(for: window, completionHandler: nil) }
            hexField.stringValue = LegacyColorMath.hexARGB(current)
        }
    }

    private func refreshChannelButtons() {
        for (item, button) in channelButtons {
            button.state = item == channel ? .on : .off
        }
    }

    private func addBordered(_ frame: CGRect) {
        let box = NSView(frame: frame)
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.windowFrameColor.cgColor
        box.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(box)
    }
}

extension ColorPickerDialogView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === hexField {
            commitHex()
        } else if field === alphaField {
            alphaFieldChanged()
        } else {
            commitChannelField(field)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === hexField, !passive else { return }
        if let color = LegacyColorMath.parseHex(field.stringValue) {
            apply(color, updateHex: false)
        }
    }
}

@MainActor
private final class ColorPreviewView: FlippedDialogView {
    var origColor = ThemeColor(argb: 0xFF00_0000)
    var newColor = ThemeColor(argb: 0xFF00_0000)
    var origCaptionDark = false
    var newCaptionDark = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        LegacyChromeIcons.image(named: ColorPickerLayout.transparentBackgroundName)?.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        origColor.nsColor.setFill()
        ColorPickerLayout.previewOrig.fill()
        NSColor.windowFrameColor.setStroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: CGFloat(ColorPickerLayout.previewDividerX) + 0.5, y: 0))
        divider.line(to: NSPoint(x: CGFloat(ColorPickerLayout.previewDividerX) + 0.5, y: 28))
        divider.stroke()
        newColor.nsColor.setFill()
        ColorPickerLayout.previewNew.fill()
        drawCaption("Orig", in: ColorPickerLayout.previewOrig, dark: origCaptionDark)
        drawCaption("New", in: ColorPickerLayout.previewNew, dark: newCaptionDark)
    }

    private func drawCaption(_ text: String, in rect: CGRect, dark: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: LegacyChromeFont.segoe,
            .foregroundColor: dark ? NSColor.black : NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        text.draw(at: origin, withAttributes: attributes)
    }
}

@MainActor
private final class ColorSquareView: FlippedDialogView {
    var channel = ColorPickerChannel.saturation
    var hue = 0
    var saturation = 0
    var lightness = 0
    var red = 0
    var green = 0
    var blue = 0
    var precision = 2
    var cursor = CGPoint.zero
    var cursorDark = false
    var onDrag: ((Int, Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let step = max(1, precision)
        for x in stride(from: 0, through: 255, by: step) {
            let width = CGFloat(min(step, 256 - x))
            switch channel {
            case .hue:
                let mid = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: scale(x, 1000), lightness: 500, alpha: 255))
                fillColumn(x: x, width: width, top: ThemeColor(argb: 0xFFFF_FFFF), mid: mid, bottom: ThemeColor(argb: 0xFF00_0000), split: true)
            case .saturation:
                let mid = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: scale(x, 360), saturation: saturation, lightness: 500, alpha: 255))
                fillColumn(x: x, width: width, top: ThemeColor(argb: 0xFFFF_FFFF), mid: mid, bottom: ThemeColor(argb: 0xFF00_0000), split: true)
            case .lightness:
                let top = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: scale(x, 360), saturation: 1000, lightness: lightness, alpha: 255))
                let bottom = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: scale(x, 360), saturation: 0, lightness: lightness, alpha: 255))
                fillColumn(x: x, width: width, top: top, mid: top, bottom: bottom, split: false)
            case .red:
                fillColumn(
                    x: x, width: width,
                    top: ThemeColor(argb: rgb(red, 255, x)),
                    mid: ThemeColor(argb: rgb(red, 255, x)),
                    bottom: ThemeColor(argb: rgb(red, 0, x)),
                    split: false
                )
            case .green:
                fillColumn(
                    x: x, width: width,
                    top: ThemeColor(argb: rgb(255, green, x)),
                    mid: ThemeColor(argb: rgb(255, green, x)),
                    bottom: ThemeColor(argb: rgb(0, green, x)),
                    split: false
                )
            case .blue:
                fillColumn(
                    x: x, width: width,
                    top: ThemeColor(argb: rgb(255, x, blue)),
                    mid: ThemeColor(argb: rgb(255, x, blue)),
                    bottom: ThemeColor(argb: rgb(0, x, blue)),
                    split: false
                )
            }
        }
        let color = cursorDark ? NSColor.black : NSColor.white
        color.setStroke()
        let oval = NSBezierPath(ovalIn: NSRect(x: cursor.x - 4, y: cursor.y - 4, width: 8, height: 8))
        oval.lineWidth = 1
        oval.stroke()
    }

    override func mouseDown(with event: NSEvent) { drag(event) }
    override func mouseDragged(with event: NSEvent) { drag(event) }

    private func drag(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onDrag?(Int(point.x.rounded(.toNearestOrEven)), Int(point.y.rounded(.toNearestOrEven)))
    }

    private func fillColumn(x: Int, width: CGFloat, top: ThemeColor, mid: ThemeColor, bottom: ThemeColor, split: Bool) {
        if split {
            NSGradient(starting: top.nsColor, ending: mid.nsColor)?.draw(
                in: NSRect(x: CGFloat(x), y: 0, width: width, height: 128),
                angle: 270
            )
            NSGradient(starting: mid.nsColor, ending: bottom.nsColor)?.draw(
                in: NSRect(x: CGFloat(x), y: 128, width: width, height: 128),
                angle: 270
            )
        } else {
            NSGradient(starting: top.nsColor, ending: bottom.nsColor)?.draw(
                in: NSRect(x: CGFloat(x), y: 0, width: width, height: 256),
                angle: 270
            )
        }
    }

    private func scale(_ x: Int, _ to: Int) -> Int {
        Int((Double(x) / 255 * Double(to)).rounded(.toNearestOrEven))
    }

    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        0xFF00_0000 | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }
}

@MainActor
private final class ColorSliderView: FlippedDialogView {
    var channel = ColorPickerChannel.saturation
    var hue = 0
    var saturation = 0
    var lightness = 0
    var red = 0
    var green = 0
    var blue = 0
    var precision = 2
    var cursorY: CGFloat = 0
    var cursorDark = false
    var onDrag: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let width = bounds.width
        let step = max(1, precision)
        switch channel {
        case .hue:
            for y in stride(from: 0, through: 255, by: step) {
                let color = LegacyColorMath.hsl2rgb(ColorPickerHSLA(
                    hue: Int((Double(255 - y) / 255 * 360).rounded(.toNearestOrEven)),
                    saturation: saturation,
                    lightness: lightness,
                    alpha: 255
                ))
                color.nsColor.setFill()
                NSRect(x: 0, y: CGFloat(y), width: width, height: CGFloat(min(step, 256 - y))).fill()
            }
        case .saturation:
            NSGradient(
                starting: LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: 1000, lightness: lightness, alpha: 255)).nsColor,
                ending: LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: 0, lightness: lightness, alpha: 255)).nsColor
            )?.draw(in: NSRect(x: 0, y: 0, width: width, height: 256), angle: 270)
        case .lightness:
            NSGradient(
                starting: LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: saturation, lightness: 1000, alpha: 255)).nsColor,
                ending: LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: saturation, lightness: 500, alpha: 255)).nsColor
            )?.draw(in: NSRect(x: 0, y: 0, width: width, height: 128), angle: 270)
            NSGradient(
                starting: LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: saturation, lightness: 500, alpha: 255)).nsColor,
                ending: LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: hue, saturation: saturation, lightness: 0, alpha: 255)).nsColor
            )?.draw(in: NSRect(x: 0, y: 128, width: width, height: 128), angle: 270)
        case .red:
            NSGradient(starting: ThemeColor(argb: rgb(255, green, blue)).nsColor, ending: ThemeColor(argb: rgb(0, green, blue)).nsColor)?
                .draw(in: NSRect(x: 0, y: 0, width: width, height: 256), angle: 270)
        case .green:
            NSGradient(starting: ThemeColor(argb: rgb(red, 255, blue)).nsColor, ending: ThemeColor(argb: rgb(red, 0, blue)).nsColor)?
                .draw(in: NSRect(x: 0, y: 0, width: width, height: 256), angle: 270)
        case .blue:
            NSGradient(starting: ThemeColor(argb: rgb(red, green, 255)).nsColor, ending: ThemeColor(argb: rgb(red, green, 0)).nsColor)?
                .draw(in: NSRect(x: 0, y: 0, width: width, height: 256), angle: 270)
        }
        let color = cursorDark ? NSColor.black : NSColor.white
        color.setFill()
        triangle(points: [NSPoint(x: 4, y: cursorY), NSPoint(x: -1, y: cursorY - 2), NSPoint(x: -1, y: cursorY + 2)])
        triangle(points: [NSPoint(x: width - 5, y: cursorY), NSPoint(x: width, y: cursorY - 2), NSPoint(x: width, y: cursorY + 2)])
    }

    override func mouseDown(with event: NSEvent) { drag(event) }
    override func mouseDragged(with event: NSEvent) { drag(event) }

    private func drag(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onDrag?(Int(point.y.rounded(.toNearestOrEven)))
    }

    private func triangle(points: [NSPoint]) {
        let path = NSBezierPath()
        path.move(to: points[0])
        path.line(to: points[1])
        path.line(to: points[2])
        path.close()
        path.fill()
    }

    private func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        0xFF00_0000 | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }
}

@MainActor
private final class ColorAlphaView: FlippedDialogView {
    var red = 0
    var green = 0
    var blue = 0
    var precision = 2
    var cursorX: CGFloat = 255
    var cursorDark = false
    var onDrag: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        LegacyChromeIcons.image(named: ColorPickerLayout.transparentBackgroundName)?.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        let step = max(1, precision)
        let height = bounds.height
        for x in stride(from: 0, through: 255, by: step) {
            ThemeColor(argb: (UInt32(x) << 24) | (UInt32(red) << 16) | (UInt32(green) << 8) | UInt32(blue)).nsColor.setFill()
            NSRect(x: CGFloat(x), y: 0, width: CGFloat(min(step, 256 - x)), height: height).fill()
        }
        let color = cursorDark ? NSColor.black : NSColor.white
        color.setFill()
        triangle(points: [NSPoint(x: cursorX, y: 4), NSPoint(x: cursorX - 2, y: -1), NSPoint(x: cursorX + 2, y: -1)])
        triangle(points: [NSPoint(x: cursorX, y: height - 5), NSPoint(x: cursorX - 2, y: height), NSPoint(x: cursorX + 2, y: height)])
    }

    override func mouseDown(with event: NSEvent) { drag(event) }
    override func mouseDragged(with event: NSEvent) { drag(event) }

    private func drag(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onDrag?(Int(point.x.rounded(.toNearestOrEven)))
    }

    private func triangle(points: [NSPoint]) {
        let path = NSBezierPath()
        path.move(to: points[0])
        path.line(to: points[1])
        path.line(to: points[2])
        path.close()
        path.fill()
    }
}
