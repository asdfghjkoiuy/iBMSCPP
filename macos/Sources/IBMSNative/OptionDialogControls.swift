import AppKit

@MainActor
enum OptionDialogControls {
    static func label(_ text: String, frame: CGRect, align: NSTextAlignment = .right) -> NSTextField {
        let field = NSTextField(labelWithString: NativeLocalization.text(text))
        NativeLocalization.markFixed(field, key: text)
        field.frame = frame
        field.font = LegacyChromeFont.segoe
        field.alignment = align
        field.lineBreakMode = .byClipping
        return field
    }

    static func multilineLabel(_ text: String, frame: CGRect, align: NSTextAlignment = .right) -> NSTextField {
        let field = label(text, frame: frame, align: align)
        field.maximumNumberOfLines = 0
        field.cell?.wraps = true
        return field
    }

    static func button(_ title: String, frame: CGRect, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: NativeLocalization.text(title), target: target, action: action)
        NativeLocalization.markFixed(button, key: title)
        button.frame = frame
        button.bezelStyle = .rounded
        button.font = LegacyChromeFont.segoe
        button.focusRingType = .none
        return button
    }

    static func checkbox(_ title: String, frame: CGRect, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(checkboxWithTitle: NativeLocalization.text(title), target: target, action: action)
        NativeLocalization.markFixed(button, key: title)
        button.frame = frame
        button.font = LegacyChromeFont.segoe
        button.focusRingType = .none
        return button
    }

    static func radio(_ title: String, frame: CGRect, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(radioButtonWithTitle: NativeLocalization.text(title), target: target, action: action)
        NativeLocalization.markFixed(button, key: title)
        button.frame = frame
        button.font = LegacyChromeFont.segoe
        button.focusRingType = .none
        return button
    }

    static func popup(titles: [String], frame: CGRect) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame, pullsDown: false)
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        popup.font = LegacyChromeFont.segoe
        popup.focusRingType = .none
        return popup
    }

    static func field(frame: CGRect, text: String = "") -> NSTextField {
        let field = NSTextField(string: text)
        field.frame = frame
        field.font = LegacyChromeFont.segoe
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        return field
    }

    static func integerField(frame: CGRect, value: Int, range: ClosedRange<Int>) -> NSTextField {
        let field = self.field(frame: frame, text: "\(value)")
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        formatter.allowsFloats = false
        field.formatter = formatter
        return field
    }

    static func decimalField(frame: CGRect, value: Double, range: ClosedRange<Double>, digits: Int) -> NSTextField {
        let field = self.field(frame: frame)
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.numberStyle = .decimal
        field.formatter = formatter
        field.doubleValue = value
        return field
    }

    static func rule(_ frame: CGRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = OptionDialogColor.rule.nsColor.cgColor
        return view
    }

    static func integer(from field: NSTextField, default fallback: Int, range: ClosedRange<Int>) -> Int {
        let parsed = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
        return min(range.upperBound, max(range.lowerBound, parsed))
    }

    static func double(from field: NSTextField, default fallback: Double, range: ClosedRange<Double>) -> Double {
        let parsed = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
        return min(range.upperBound, max(range.lowerBound, parsed))
    }
}

@MainActor
final class LegacyColorButton: NSButton {
    var themeColor: ThemeColor {
        didSet { refresh() }
    }

    init(frame: CGRect, color: ThemeColor) {
        themeColor = color
        super.init(frame: frame)
        bezelStyle = .shadowlessSquare
        isBordered = true
        font = LegacyChromeFont.segoe
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        title = OptionDialogColor.hexARGB(themeColor)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: LegacyChromeFont.segoe,
            .foregroundColor: OptionDialogColor.contrastingText(themeColor).nsColor
        ])
        wantsLayer = true
        layer?.backgroundColor = themeColor.nsColor.cgColor
    }
}

@MainActor
final class LegacyFontButton: NSButton {
    var themeFont: ThemeFont {
        didSet { refresh() }
    }

    init(frame: CGRect, font themeFont: ThemeFont) {
        self.themeFont = themeFont
        super.init(frame: frame)
        bezelStyle = .shadowlessSquare
        isBordered = true
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        title = themeFont.name
        font = NSFont(name: themeFont.name, size: MainWindowChrome.segoeUINinePointPixels)
            ?? LegacyChromeFont.segoe
    }
}
