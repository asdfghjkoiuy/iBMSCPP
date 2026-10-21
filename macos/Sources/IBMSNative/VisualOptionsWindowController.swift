import AppKit

@MainActor
final class VisualOptionsWindowController: NSWindowController {
    private let content = VisualOptionsDialogView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: VisualOptionsLayout.clientSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Visual Options"
        NativeLocalization.markFixed(window, key: "Visual Options")
        window.isReleasedWhenClosed = false
        window.contentMinSize = VisualOptionsLayout.clientSize
        window.contentMaxSize = VisualOptionsLayout.clientSize
        super.init(window: window)
        window.contentView = content
        NativeLocalization.localize(window: window)
        content.onCancel = { [weak self] in self?.end(nil) }
        content.onOK = { [weak self] theme in self?.end(theme) }
    }

    required init?(coder: NSCoder) { nil }

    private var pendingResult: ChartTheme?

    func present(over parent: NSWindow, theme: ChartTheme, completion: @escaping (ChartTheme?) -> Void) {
        pendingResult = nil
        content.load(theme)
        guard let sheet = window else {
            completion(nil)
            return
        }
        parent.beginSheet(sheet) { [weak self] _ in
            self?.content.detachPanels()
            completion(self?.pendingResult)
        }
    }

    private func end(_ theme: ChartTheme?) {
        pendingResult = theme
        content.detachPanels()
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class VisualOptionsDialogView: FlippedDialogView {
    var onOK: ((ChartTheme) -> Void)?
    var onCancel: (() -> Void)?

    private var source = ChartTheme.defaultTheme
    private let colorPicker = ColorPickerWindowController()
    private var colorButtons: [String: LegacyColorButton] = [:]
    private var fontButtons: [String: LegacyFontButton] = [:]
    private var integerFields: [String: NSTextField] = [:]
    private var opacityField: NSTextField!
    private var columnWidths: [NSTextField] = []
    private var columnTitles: [NSTextField] = []
    private var columnShortNotes: [LegacyColorButton] = []
    private var columnShortLabels: [LegacyColorButton] = []
    private var columnLongNotes: [LegacyColorButton] = []
    private var columnLongLabels: [LegacyColorButton] = []
    private var columnBackgrounds: [LegacyColorButton] = []
    private weak var activeColorButton: LegacyColorButton?
    private weak var activeFontButton: LegacyFontButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: VisualOptionsLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildGlobalControls()
        addSubview(OptionDialogControls.rule(VisualOptionsLayout.divider))
        buildColumnPanel()
        let ok = OptionDialogControls.button("OK", frame: VisualOptionsLayout.ok, target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        addSubview(ok)
        let cancel = OptionDialogControls.button("Cancel", frame: VisualOptionsLayout.cancel, target: self, action: #selector(cancelDialog))
        cancel.keyEquivalent = "\u{1b}"
        addSubview(cancel)
    }

    required init?(coder: NSCoder) { nil }

    func load(_ theme: ChartTheme) {
        source = theme
        let visual = theme.visual
        colorButtons["columnTitle"]?.themeColor = visual.columnTitle
        colorButtons["background"]?.themeColor = visual.background
        colorButtons["grid"]?.themeColor = visual.grid
        colorButtons["subGrid"]?.themeColor = visual.subGrid
        colorButtons["verticalLine"]?.themeColor = visual.verticalLine
        colorButtons["measureLine"]?.themeColor = visual.measureLine
        colorButtons["bgmWaveform"]?.themeColor = visual.bgmWaveform
        colorButtons["noteMouseOver"]?.themeColor = visual.noteMouseOver
        colorButtons["noteSelected"]?.themeColor = visual.noteSelected
        colorButtons["noteMouseOverEnd"]?.themeColor = visual.noteMouseOverEnd
        colorButtons["selectionBox"]?.themeColor = visual.selectionBox
        colorButtons["timeSelectionCursor"]?.themeColor = visual.timeSelectionCursor
        colorButtons["timeSelectionHalf"]?.themeColor = visual.timeSelectionHalf
        colorButtons["timeSelectionMouseOver"]?.themeColor = visual.timeSelectionMouseOver
        colorButtons["timeSelectionSelection"]?.themeColor = visual.timeSelectionSelection
        colorButtons["timeSelectionBPM"]?.themeColor = visual.timeSelectionBPM
        fontButtons["columnTitleFont"]?.themeFont = visual.columnTitleFont
        fontButtons["noteFont"]?.themeFont = visual.noteFont
        fontButtons["measureFont"]?.themeFont = visual.measureFont
        fontButtons["timeSelectionBPMFont"]?.themeFont = visual.timeSelectionBPMFont
        integerFields["noteHeight"]?.integerValue = VisualOptionsLayout.clampNoteHeight(visual.noteHeight)
        integerFields["labelVerticalShift"]?.integerValue = VisualOptionsLayout.clampLabelShift(visual.labelVerticalShift)
        integerFields["labelHorizontalShift"]?.integerValue = VisualOptionsLayout.clampLabelShift(visual.labelHorizontalShift)
        integerFields["longLabelHorizontalShift"]?.integerValue = VisualOptionsLayout.clampLabelShift(visual.longLabelHorizontalShift)
        integerFields["timeSelectionDeltaMouseOver"]?.integerValue = min(
            VisualOptionsLayout.timeSelectionSensitivityRange.upperBound,
            max(VisualOptionsLayout.timeSelectionSensitivityRange.lowerBound, visual.timeSelectionDeltaMouseOver)
        )
        integerFields["middleDeltaRelease"]?.integerValue = min(
            VisualOptionsLayout.middleSensitivityRange.upperBound,
            max(VisualOptionsLayout.middleSensitivityRange.lowerBound, visual.middleDeltaRelease)
        )
        opacityField.doubleValue = VisualOptionsLayout.clampHiddenOpacity(visual.hiddenNoteOpacity)

        for index in 0..<VisualOptionsLayout.columnLefts.count {
            let column = theme.column(at: index) ?? ChartTheme.defaultTheme.column(at: index)
            guard let column else { continue }
            columnWidths[index].integerValue = min(
                VisualOptionsLayout.columnWidthRange.upperBound,
                max(VisualOptionsLayout.columnWidthRange.lowerBound, column.width)
            )
            columnTitles[index].stringValue = column.title
            columnShortNotes[index].themeColor = column.noteColor
            columnShortLabels[index].themeColor = column.textColor
            columnLongNotes[index].themeColor = column.longNoteColor
            columnLongLabels[index].themeColor = column.longTextColor
            columnBackgrounds[index].themeColor = column.backgroundColor
        }
    }

    func detachPanels() {
        colorPicker.dismissIfNeeded()
        NSFontManager.shared.target = nil
        NSFontManager.shared.fontPanel(false)?.orderOut(nil)
        activeColorButton = nil
        activeFontButton = nil
    }

    @objc private func confirm() {
        detachPanels()
        onOK?(makeTheme())
    }

    @objc private func cancelDialog() {
        detachPanels()
        onCancel?()
    }

    @objc private func pickColor(_ sender: LegacyColorButton) {
        activeFontButton = nil
        activeColorButton = sender
        guard let window else { return }
        colorPicker.present(over: window, color: sender.themeColor) { [weak sender] color in
            if let color {
                sender?.themeColor = color
            }
        }
    }

    @objc private func pickFont(_ sender: LegacyFontButton) {
        activeColorButton = nil
        activeFontButton = sender
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(fontPanelChanged(_:))
        manager.setSelectedFont(sender.themeFont.nsFont, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc private func fontPanelChanged(_ sender: NSFontManager) {
        guard let button = activeFontButton else { return }
        button.themeFont = ThemeFont(nsFont: sender.convert(button.themeFont.nsFont))
    }

    private func makeTheme() -> ChartTheme {
        var theme = source
        var visual = theme.visual
        visual.columnTitle = color("columnTitle", visual.columnTitle)
        visual.background = color("background", visual.background)
        visual.grid = color("grid", visual.grid)
        visual.subGrid = color("subGrid", visual.subGrid)
        visual.verticalLine = color("verticalLine", visual.verticalLine)
        visual.measureLine = color("measureLine", visual.measureLine)
        visual.bgmWaveform = color("bgmWaveform", visual.bgmWaveform)
        visual.noteMouseOver = color("noteMouseOver", visual.noteMouseOver)
        visual.noteSelected = color("noteSelected", visual.noteSelected)
        visual.noteMouseOverEnd = color("noteMouseOverEnd", visual.noteMouseOverEnd)
        visual.selectionBox = color("selectionBox", visual.selectionBox)
        visual.timeSelectionCursor = color("timeSelectionCursor", visual.timeSelectionCursor)
        visual.timeSelectionHalf = color("timeSelectionHalf", visual.timeSelectionHalf)
        visual.timeSelectionMouseOver = color("timeSelectionMouseOver", visual.timeSelectionMouseOver)
        visual.timeSelectionSelection = color("timeSelectionSelection", visual.timeSelectionSelection)
        visual.timeSelectionBPM = color("timeSelectionBPM", visual.timeSelectionBPM)
        visual.columnTitleFont = font("columnTitleFont", visual.columnTitleFont)
        visual.noteFont = font("noteFont", visual.noteFont)
        visual.measureFont = font("measureFont", visual.measureFont)
        visual.timeSelectionBPMFont = font("timeSelectionBPMFont", visual.timeSelectionBPMFont)
        visual.noteHeight = clampedInteger(
            "noteHeight",
            default: visual.noteHeight,
            range: VisualOptionsLayout.noteHeightRange
        )
        visual.labelVerticalShift = clampedInteger(
            "labelVerticalShift",
            default: visual.labelVerticalShift,
            range: VisualOptionsLayout.labelShiftRange
        )
        visual.labelHorizontalShift = clampedInteger(
            "labelHorizontalShift",
            default: visual.labelHorizontalShift,
            range: VisualOptionsLayout.labelShiftRange
        )
        visual.longLabelHorizontalShift = clampedInteger(
            "longLabelHorizontalShift",
            default: visual.longLabelHorizontalShift,
            range: VisualOptionsLayout.labelShiftRange
        )
        visual.hiddenNoteOpacity = OptionDialogControls.double(
            from: opacityField,
            default: visual.hiddenNoteOpacity,
            range: VisualOptionsLayout.hiddenOpacityRange
        )
        visual.timeSelectionDeltaMouseOver = clampedInteger(
            "timeSelectionDeltaMouseOver",
            default: visual.timeSelectionDeltaMouseOver,
            range: VisualOptionsLayout.timeSelectionSensitivityRange
        )
        visual.middleDeltaRelease = clampedInteger(
            "middleDeltaRelease",
            default: visual.middleDeltaRelease,
            range: VisualOptionsLayout.middleSensitivityRange
        )
        theme.visual = visual

        var columns = theme.columns
        for index in 0..<VisualOptionsLayout.columnLefts.count {
            guard let existing = columns.firstIndex(where: { $0.legacyIndex == index }) else { continue }
            columns[existing].width = OptionDialogControls.integer(
                from: columnWidths[index],
                default: columns[existing].width,
                range: VisualOptionsLayout.columnWidthRange
            )
            columns[existing].title = columnTitles[index].stringValue
            columns[existing].noteColor = columnShortNotes[index].themeColor
            columns[existing].textColor = columnShortLabels[index].themeColor
            columns[existing].longNoteColor = columnLongNotes[index].themeColor
            columns[existing].longTextColor = columnLongLabels[index].themeColor
            columns[existing].backgroundColor = columnBackgrounds[index].themeColor
        }
        theme.columns = columns
        return theme
    }

    private func clampedInteger(_ key: String, default fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let field = integerFields[key] else { return fallback }
        return OptionDialogControls.integer(from: field, default: fallback, range: range)
    }

    private func color(_ key: String, _ fallback: ThemeColor) -> ThemeColor {
        colorButtons[key]?.themeColor ?? fallback
    }

    private func font(_ key: String, _ fallback: ThemeFont) -> ThemeFont {
        fontButtons[key]?.themeFont ?? fallback
    }

    private func buildGlobalControls() {
        func addColor(_ key: String, title: String, label: CGRect, control: CGRect) {
            addSubview(OptionDialogControls.label(title, frame: label))
            let button = LegacyColorButton(frame: control, color: .init(argb: 0xFF00_0000))
            button.target = self
            button.action = #selector(pickColor(_:))
            colorButtons[key] = button
            addSubview(button)
        }
        func addFont(_ key: String, title: String, label: CGRect, control: CGRect) {
            addSubview(OptionDialogControls.label(title, frame: label))
            let button = LegacyFontButton(frame: control, font: ThemeFont(name: "Verdana", pointSize: 9, style: 0))
            button.target = self
            button.action = #selector(pickFont(_:))
            fontButtons[key] = button
            addSubview(button)
        }
        func addInteger(_ key: String, title: String, label: CGRect, control: CGRect, range: ClosedRange<Int>) {
            addSubview(OptionDialogControls.label(title, frame: label))
            let field = OptionDialogControls.integerField(frame: control, value: 0, range: range)
            integerFields[key] = field
            addSubview(field)
        }

        let rows = VisualOptionsLayout.globalRows
        addColor("columnTitle", title: rows[0].title, label: rows[0].label, control: rows[0].control)
        addFont("columnTitleFont", title: rows[1].title, label: rows[1].label, control: rows[1].control)
        addColor("background", title: rows[2].title, label: rows[2].label, control: rows[2].control)
        addColor("grid", title: rows[3].title, label: rows[3].label, control: rows[3].control)
        addColor("subGrid", title: rows[4].title, label: rows[4].label, control: rows[4].control)
        addColor("verticalLine", title: rows[5].title, label: rows[5].label, control: rows[5].control)
        addColor("measureLine", title: rows[6].title, label: rows[6].label, control: rows[6].control)
        addColor("bgmWaveform", title: rows[7].title, label: rows[7].label, control: rows[7].control)
        addInteger("noteHeight", title: rows[8].title, label: rows[8].label, control: rows[8].control, range: VisualOptionsLayout.noteHeightRange)
        addFont("noteFont", title: rows[9].title, label: rows[9].label, control: rows[9].control)
        addFont("measureFont", title: rows[10].title, label: rows[10].label, control: rows[10].control)
        addInteger("labelVerticalShift", title: rows[11].title, label: rows[11].label, control: rows[11].control, range: VisualOptionsLayout.labelShiftRange)
        addInteger("labelHorizontalShift", title: rows[12].title, label: rows[12].label, control: rows[12].control, range: VisualOptionsLayout.labelShiftRange)
        addInteger("longLabelHorizontalShift", title: rows[13].title, label: rows[13].label, control: rows[13].control, range: VisualOptionsLayout.labelShiftRange)
        addSubview(OptionDialogControls.label(rows[14].title, frame: rows[14].label))
        opacityField = OptionDialogControls.decimalField(
            frame: rows[14].control,
            value: 0.5,
            range: VisualOptionsLayout.hiddenOpacityRange,
            digits: 2
        )
        addSubview(opacityField)
        addColor("noteMouseOver", title: rows[15].title, label: rows[15].label, control: rows[15].control)
        addColor("noteSelected", title: rows[16].title, label: rows[16].label, control: rows[16].control)
        addColor("noteMouseOverEnd", title: rows[17].title, label: rows[17].label, control: rows[17].control)
        addColor("selectionBox", title: rows[18].title, label: rows[18].label, control: rows[18].control)
        addColor("timeSelectionCursor", title: rows[19].title, label: rows[19].label, control: rows[19].control)
        addColor("timeSelectionHalf", title: rows[20].title, label: rows[20].label, control: rows[20].control)
        addInteger("timeSelectionDeltaMouseOver", title: rows[21].title, label: rows[21].label, control: rows[21].control, range: VisualOptionsLayout.timeSelectionSensitivityRange)
        addColor("timeSelectionMouseOver", title: rows[22].title, label: rows[22].label, control: rows[22].control)
        addColor("timeSelectionSelection", title: rows[23].title, label: rows[23].label, control: rows[23].control)
        addColor("timeSelectionBPM", title: rows[24].title, label: rows[24].label, control: rows[24].control)
        addFont("timeSelectionBPMFont", title: rows[25].title, label: rows[25].label, control: rows[25].control)
        addInteger("middleDeltaRelease", title: rows[26].title, label: rows[26].label, control: rows[26].control, range: VisualOptionsLayout.middleSensitivityRange)
    }

    private func buildColumnPanel() {
        let panel = FlippedDialogView(frame: VisualOptionsLayout.columnPanel)
        for header in VisualOptionsLayout.columnRowHeaders {
            panel.addSubview(OptionDialogControls.multilineLabel(header.title, frame: header.frame))
        }
        for index in 0..<VisualOptionsLayout.columnLefts.count {
            let width = OptionDialogControls.integerField(
                frame: VisualOptionsLayout.columnFrame(index: index, row: .width),
                value: 0,
                range: VisualOptionsLayout.columnWidthRange
            )
            let title = OptionDialogControls.field(frame: VisualOptionsLayout.columnFrame(index: index, row: .title))
            let shortNote = colorSwatch(VisualOptionsLayout.columnFrame(index: index, row: .shortNote))
            let shortLabel = colorSwatch(VisualOptionsLayout.columnFrame(index: index, row: .shortLabel))
            let longNote = colorSwatch(VisualOptionsLayout.columnFrame(index: index, row: .longNote))
            let longLabel = colorSwatch(VisualOptionsLayout.columnFrame(index: index, row: .longLabel))
            let background = colorSwatch(VisualOptionsLayout.columnFrame(index: index, row: .background))
            columnWidths.append(width)
            columnTitles.append(title)
            columnShortNotes.append(shortNote)
            columnShortLabels.append(shortLabel)
            columnLongNotes.append(longNote)
            columnLongLabels.append(longLabel)
            columnBackgrounds.append(background)
            [width, title, shortNote, shortLabel, longNote, longLabel, background].forEach(panel.addSubview)
        }
        addSubview(panel)
    }

    private func colorSwatch(_ frame: CGRect) -> LegacyColorButton {
        let button = LegacyColorButton(frame: frame, color: .init(argb: 0xFF00_0000))
        button.target = self
        button.action = #selector(pickColor(_:))
        return button
    }
}
