import AppKit
import UniformTypeIdentifiers

@MainActor
final class OptionsSidebarView: NSScrollView, NSTextFieldDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var metadataFields: [String: NSTextField] = [:]
    var metadataPopups: [String: NSPopUpButton] = [:]
    /// 提交成功后的下拉索引。失败时回到这里，不能用刚选中的新值反查。
    private var committedPopupIndices: [String: Int] = [:]
    private var browseButtons: [String: NSButton] = [:]
    var onMetadataCommit: ((String, String) -> Bool)?
    var onMetadataDraft: ((String, String) -> Void)?
    var onBPMCommit: ((String) -> Bool)?
    var onDivisionChange: ((Int) -> Void)?
    var onSubDivisionChange: ((Int) -> Void)?
    var onSnapChange: ((Bool) -> Void)?
    var onVerticalMoveChange: ((Bool) -> Void)?
    var onScrollLockChange: ((Int, Bool) -> Void)?
    var slashValue = LegacyGridDivision.defaultSlash
    var onTokenChange: ((String) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    var onColumnScaleChange: ((CGFloat) -> Void)?
    var onBGMColumnChange: ((Int) -> Void)?
    var onNotice: ((String) -> Void)?
    var onWaveformLoad: ((URL) -> Void)?
    var onWaveformClear: (() -> Void)?
    var onWaveformLockChange: ((Bool) -> Void)?
    var onWaveformPositionChange: ((Double) -> Void)?
    var onWaveformDisplayChange: ((Int, Int, Int) -> Void)?
    var onWaveformTransparencyChange: ((Int) -> Void)?
    var onWaveformSaturationChange: ((Int) -> Void)?
    var onWavMoveUp: (() -> Void)?
    var onWavMoveDown: (() -> Void)?
    var onWavBrowse: (() -> Void)?
    var onWavRemove: (() -> Void)?
    var onBmpMoveUp: (() -> Void)?
    var onBmpMoveDown: (() -> Void)?
    var onBmpBrowse: (() -> Void)?
    var onBmpRemove: (() -> Void)?
    var onWavDrop: (([String]) -> Void)?
    var onBmpDrop: (([String]) -> Void)?
    var onResourceDragPreview: (([String]) -> Void)?
    var onBeatApply: (([Int], String, LegacyBeat.Mode) -> Bool)?
    var onExpansionCommit: ((String) -> Bool)?

    private var state = OptionsSidebarState.runtimeDefault
    private let document = FlippedSidebarDocumentView()
    private weak var infoDockView: BmsONEInfoDockView?
    private weak var selectedObjectsView: BmsONESelectedObjectsView?
    private var infoSection: BmsonAuxiliarySection?
    private var selectedSection: BmsonAuxiliarySection?
    private var showsBmsonDocks = false
    private var sectionViews: [OptionsSectionID: OptionsSectionView] = [:]
    private let wavTable = ResourceDropTableView()
    private var wavNames: [String: String] = [:]
    private let bmpTable = ResourceDropTableView()
    private var bmpNames: [String: String] = [:]
    private let divideField = NSTextField(string: "16")
    private let subField = NSTextField(string: "4")
    private let heightField = NSTextField(string: "1.00")
    private let heightSlider = NSSlider()
    private let widthField = NSTextField(string: "1.00")
    private let widthSlider = NSSlider()
    private let snapBox = NSButton(checkboxWithTitle: "Snap to grid (G)", target: nil, action: nil)
    private let bgmColumnsField = NSTextField(string: "15")
    private let verticalBox = NSButton(checkboxWithTitle: "Disable vertical moves (D)", target: nil, action: nil)
    private var lockButtons: [NSButton] = []
    private let bpmField = NSTextField(string: "120")
    private let waveformFileField = NSTextField(string: "(None)")
    private let waveformPositionField = NSTextField(string: "0.00")
    private let waveformPositionSlider = NSSlider()
    private let waveformLockButton = NSButton()
    private let waveformLeftField = NSTextField(string: "\(LegacyWaveform.defaultLeft)")
    private let waveformLeftSlider = NSSlider()
    private let waveformWidthField = NSTextField(string: "\(LegacyWaveform.defaultWidth)")
    private let waveformWidthSlider = NSSlider()
    private let waveformPrecisionField = NSTextField(string: "\(LegacyWaveform.defaultPrecision)")
    private let waveformPrecisionSlider = NSSlider()
    private let waveformTransparencyField = NSTextField(string: "\(LegacyWaveform.defaultTransparency)")
    private let waveformTransparencySlider = NSSlider()
    private let waveformSaturationField = NSTextField(string: "\(LegacyWaveform.defaultSaturation)")
    private let waveformSaturationSlider = NSSlider()
    private let channelFormatLabel = NSTextField(labelWithString: "")
    private let channelLengthLabel = NSTextField(labelWithString: "")
    private let channelInfoBar = FlippedSidebarDocumentView()
    private let channelWaveformView = BmsonOverallWaveformView()
    private var showsBmsonChannelInfo = false
    private let wavMultiSelectBox = NSButton(checkboxWithTitle: "Allow Multiple Selection", target: nil, action: nil)
    private let wavChangeLabelBox = NSButton(checkboxWithTitle: "Synchronize Note Labels", target: nil, action: nil)
    private let beatTable = NSTableView()
    private var beatItems = LegacyBeat.defaultItems()
    private let beatNumeratorField = NSTextField(string: "\(LegacyBeat.defaultNumerator)")
    private let beatDenominatorField = NSTextField(string: "\(LegacyBeat.defaultDenominator)")
    private let beatValueField = NSTextField(string: LegacyBeat.defaultValueText)
    private var beatMode: LegacyBeat.Mode = .preserve
    private var beatModeButtons: [LegacyBeat.Mode: NSButton] = [:]
    private let expansionView = NSTextView()
    private var isSettingExpansion = false

    var selectedToken: String {
        let row = wavTable.selectedRow
        guard row >= 0, row < BMS36Token.all.count else { return "01" }
        return BMS36Token.all[row]
    }

    var selectedBMPToken: String {
        let row = bmpTable.selectedRow
        guard row >= 0, row < BMS36Token.all.count else { return "01" }
        return BMS36Token.all[row]
    }

    var selectedDivision: Int {
        max(1, min(1920, Int(divideField.stringValue) ?? MainWindowChrome.defaultDivision))
    }

    var selectedSubDivision: Int {
        max(1, min(1920, Int(subField.stringValue) ?? MainWindowChrome.defaultSubDivision))
    }

    var selectedBGMColumnCount: Int {
        max(1, min(999, Int(bgmColumnsField.stringValue) ?? ChartBGM.defaultColumnCount))
    }

    func setBGMColumnCount(_ count: Int) {
        bgmColumnsField.stringValue = "\(max(1, min(999, count)))"
    }

    var snapEnabled: Bool {
        snapBox.state == .on
    }

    func setSnapEnabled(_ enabled: Bool) {
        snapBox.state = enabled ? .on : .off
    }

    var disableVerticalMove: Bool {
        verticalBox.state == .on
    }

    func setDisableVerticalMove(_ enabled: Bool) {
        verticalBox.state = enabled ? .on : .off
    }

    var scrollLocks: [Bool] {
        (0..<LegacyPanelScroll.count).map { index in
            lockButtons.indices.contains(index) && lockButtons[index].state == .on
        }
    }

    func setScrollLocks(_ locks: [Bool]) {
        for (index, enabled) in locks.enumerated() where lockButtons.indices.contains(index) {
            lockButtons[index].state = enabled ? .on : .off
        }
    }

    var gridHeight: CGFloat {
        CGFloat(Double(heightField.stringValue) ?? Double(MainWindowChrome.defaultGridHeight))
    }

    var gridWidth: CGFloat {
        CGFloat(ChartZoom.clampField(Double(widthField.stringValue) ?? 1))
    }

    func setDivisionValue(_ value: Int) {
        let clamped = LegacyGridDivision.clamp(value)
        divideField.stringValue = "\(clamped)"
        onDivisionChange?(clamped)
    }

    func setSubDivisionValue(_ value: Int) {
        let clamped = LegacyGridDivision.clamp(value)
        subField.stringValue = "\(clamped)"
        onSubDivisionChange?(clamped)
    }

    func setGridHeight(_ value: Double) {
        let next = ChartZoom.clampField(value)
        heightField.stringValue = String(format: "%.2f", next)
        heightSlider.doubleValue = Double(ChartZoom.trackValueFromField(next))
        onZoomChange?(MainWindowChrome.pixelsPerQuarterBeat(gridHeight: CGFloat(next)))
    }

    func setGridWidth(_ value: Double) {
        applyColumnScale(value)
    }

    func applySlashDivision() {
        setDivisionValue(slashValue)
    }

    func doubleDivision() {
        if let next = LegacyGridDivision.doubled(selectedDivision) {
            setDivisionValue(next)
        }
    }

    func halfDivision() {
        if let next = LegacyGridDivision.halved(selectedDivision) {
            setDivisionValue(next)
        }
    }

    func applyHeightNudge(up: Bool) {
        let next = ChartZoom.nudgeField(Double(gridHeight), up: up)
        heightField.stringValue = String(format: "%.2f", next)
        heightSlider.doubleValue = Double(ChartZoom.trackValueFromField(next))
        onZoomChange?(MainWindowChrome.pixelsPerQuarterBeat(gridHeight: CGFloat(next)))
    }

    func stepWavSelection(_ delta: Int) {
        let next = LegacyWavList.stepIndex(
            selected: wavTable.selectedRow,
            count: BMS36Token.all.count,
            delta: delta
        )
        selectWavSlots([next])
        onTokenChange?(selectedToken)
    }

    func applyCtrlWheelZoom(notches: Int) {
        guard notches != 0 else { return }
        let current = ChartZoom.trackValue(gridHeight: Double(gridHeight))
        let next = ChartZoom.nextTrackValue(current: current, wheelNotches: notches)
        heightSlider.doubleValue = Double(next)
        heightSliderChanged(heightSlider)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = .windowBackgroundColor
        document.wantsLayer = true
        document.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        documentView = document
        buildSections()
        NativeLocalization.localize(view: document)
        relayout()
    }

    required init?(coder: NSCoder) { nil }

    /// BMSON 专属分组与公共 BMS 分组共用同一滚动文档。
    func attachBmsonDocks(info: BmsONEInfoDockView, selected: BmsONESelectedObjectsView) {
        infoDockView = info
        selectedObjectsView = selected
        info.setDockTitleVisible(false)
        selected.setDockTitleVisible(false)
        let infoGroup = BmsonAuxiliarySection(title: BmsONEMainWindowLayout.infoDockTitle, content: info) { [weak self] in self?.relayout() }
        let selectedGroup = BmsonAuxiliarySection(title: BmsONEMainWindowLayout.selectedObjectsDockTitle, content: selected) { [weak self] in self?.relayout() }
        infoSection = infoGroup
        selectedSection = selectedGroup
        document.addSubview(infoGroup)
        document.addSubview(selectedGroup)
        relayout()
    }

    func setBmsonDocksVisible(_ visible: Bool) {
        showsBmsonDocks = visible
        relayout()
    }

    func setMetadataValue(_ key: String, text: String, placeholder: String?, enabled: Bool) {
        if let popup = metadataPopups[key] {
            popup.isEnabled = enabled
            let index = LegacyHeaderFields.popupIndex(key: key, stored: text)
            if index >= 0, index < popup.numberOfItems {
                popup.selectItem(at: index)
            }
            rememberPopupIndex(popup)
            return
        }
        guard let field = metadataFields[key] else { return }
        field.stringValue = text
        field.placeholderString = placeholder
        field.isEnabled = enabled
        browseButtons[key]?.isEnabled = enabled
    }

    func setBPM(_ decimal: String, enabled: Bool) {
        bpmField.stringValue = decimal
        bpmField.isEnabled = enabled
    }

    func setBmsonChannelInfo(
        visible: Bool,
        format: String,
        length: String,
        waveform: BmsonOverallWaveform.Payload = .empty
    ) {
        showsBmsonChannelInfo = visible
        channelFormatLabel.stringValue = format
        channelLengthLabel.stringValue = length
        channelWaveformView.payload = waveform
        if let view = sectionViews[.wav] {
            applyBmsonChannelInfoBar(in: view, switchOn: state.switchOn[.wav] == true)
        }
    }

    private func applyBmsonChannelInfoBar(in view: OptionsSectionView, switchOn: Bool) {
        let show = switchOn && showsBmsonChannelInfo
        channelInfoBar.isHidden = !show
        channelWaveformView.isHidden = !show
        guard let list = view.listHost else { return }
        let listHeight = MainWindowChrome.listBoxHeight
        let barHeight: CGFloat = 24
        let waveHeight = BmsonOverallWaveform.sidebarHeight
        if show {
            list.frame.size.height = listHeight - barHeight - waveHeight
            channelWaveformView.frame = NSRect(
                x: 3,
                y: list.frame.maxY,
                width: 177,
                height: waveHeight
            )
            channelInfoBar.frame = NSRect(
                x: 3,
                y: channelWaveformView.frame.maxY,
                width: 177,
                height: barHeight
            )
        } else {
            list.frame.size.height = listHeight
        }
    }

    func selectToken(_ token: String) {
        if let index = BMS36Token.all.firstIndex(of: token) {
            wavTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            wavTable.scrollRowToVisible(index)
        }
    }

    private func buildSections() {
        for section in OptionsSectionID.allCases {
            let view = OptionsSectionView(section: section)
            view.switchButton.target = self
            view.switchButton.action = #selector(toggleSection(_:))
            view.switchButton.identifier = NSUserInterfaceItemIdentifier(section.rawValue)
            view.switchButton.state = state.switchOn[section] == true ? .on : .off
            if let expander = view.expanderButton {
                expander.target = self
                expander.action = #selector(togglePart2(_:))
                expander.identifier = NSUserInterfaceItemIdentifier(section.rawValue)
            }
            switch section {
            case .header:
                fillHeader(view)
            case .grid:
                fillGrid(view)
            case .waveform:
                fillWaveform(view)
            case .wav:
                fillResourceList(view, table: wavTable, prefix: "WAV")
            case .bmp:
                fillResourceList(view, table: bmpTable, prefix: "BMP")
            case .beat:
                fillBeat(view)
            case .expansion:
                fillExpansion(view)
            }
            document.addSubview(view)
            sectionViews[section] = view
        }
    }

    private func fillHeader(_ view: OptionsSectionView) {
        for (index, row) in MainWindowChrome.headerPart1Rows.enumerated() {
            let y = CGFloat(index) * MainWindowChrome.headerFieldHeight
            addHeaderLabel(row.label, at: NSRect(x: 0, y: y, width: MainWindowChrome.headerPart1FieldX, height: MainWindowChrome.headerFieldHeight), in: view.part1)
            let fieldRect = NSRect(
                x: MainWindowChrome.headerPart1FieldX,
                y: y,
                width: MainWindowChrome.headerPart1FieldWidth,
                height: MainWindowChrome.headerFieldHeight
            )
            switch row.kind {
            case .bpm:
                configureField(bpmField, identifier: row.key, enabled: row.enabled)
                bpmField.frame = fieldRect
                view.part1.addSubview(bpmField)
            case .popup(let items):
                let popup = makePopup(items, enabled: row.enabled, key: row.key)
                popup.frame = fieldRect
                popup.selectItem(at: LegacyHeaderFields.popupIndex(key: row.key, stored: ""))
                rememberPopupIndex(popup)
                metadataPopups[row.key] = popup
                view.part1.addSubview(popup)
            default:
                let field = makeTextField(identifier: row.key, enabled: row.enabled)
                field.frame = fieldRect
                metadataFields[row.key] = field
                view.part1.addSubview(field)
            }
        }
        guard let part2 = view.part2 else { return }
        for (index, row) in MainWindowChrome.headerPart2Rows.enumerated() {
            let y = CGFloat(index) * MainWindowChrome.headerFieldHeight
            addHeaderLabel(row.label, at: NSRect(x: 0, y: y, width: MainWindowChrome.headerPart2FieldX, height: MainWindowChrome.headerFieldHeight), in: part2)
            var fieldWidth = MainWindowChrome.headerPart2FieldWidth
            if case .browse = row.kind { fieldWidth = 88 }
            if case .percent = row.kind { fieldWidth = 88 }
            let fieldRect = NSRect(x: MainWindowChrome.headerPart2FieldX, y: y, width: fieldWidth, height: MainWindowChrome.headerFieldHeight)
            switch row.kind {
            case .popup(let items):
                let popup = makePopup(items, enabled: row.enabled, key: row.key)
                popup.frame = NSRect(x: fieldRect.minX, y: y, width: 116, height: fieldRect.height)
                popup.selectItem(at: LegacyHeaderFields.popupIndex(key: row.key, stored: ""))
                rememberPopupIndex(popup)
                metadataPopups[row.key] = popup
                part2.addSubview(popup)
            case .lnobj:
                var items = ["None (#LnType 1)"]
                items.append(contentsOf: BMS36Token.all)
                let popup = makePopup(items, enabled: row.enabled, key: row.key)
                popup.frame = NSRect(x: fieldRect.minX, y: y, width: 116, height: fieldRect.height)
                popup.selectItem(at: LegacyHeaderFields.popupIndex(key: row.key, stored: ""))
                rememberPopupIndex(popup)
                metadataPopups[row.key] = popup
                part2.addSubview(popup)
            case .browse:
                let field = makeTextField(identifier: row.key, enabled: row.enabled)
                field.frame = fieldRect
                metadataFields[row.key] = field
                part2.addSubview(field)
                let browse = NSButton(frame: NSRect(x: 158, y: y, width: 25, height: 24))
                browse.title = "..."
                browse.bezelStyle = .shadowlessSquare
                browse.font = LegacyChromeFont.segoe
                browse.identifier = NSUserInterfaceItemIdentifier(row.key)
                browse.target = self
                browse.action = #selector(browseHeaderFile(_:))
                browse.isEnabled = row.enabled
                browseButtons[row.key] = browse
                part2.addSubview(browse)
            case .percent:
                let field = makeTextField(identifier: row.key, enabled: row.enabled)
                field.frame = fieldRect
                metadataFields[row.key] = field
                part2.addSubview(field)
                let suffix = NSTextField(labelWithString: "(%)")
                suffix.font = LegacyChromeFont.segoe
                suffix.frame = NSRect(x: 158, y: y, width: 25, height: 23)
                part2.addSubview(suffix)
            default:
                let field = makeTextField(identifier: row.key, enabled: row.enabled)
                field.frame = NSRect(x: fieldRect.minX, y: y, width: 116, height: fieldRect.height)
                metadataFields[row.key] = field
                part2.addSubview(field)
            }
        }
    }

    private func fillGrid(_ view: OptionsSectionView) {
        let icon = NSImageView(frame: NSRect(x: 3, y: 3, width: 24, height: 24))
        icon.image = LegacyChromeIcons.image(named: "lgpartition")
        icon.imageScaling = .scaleProportionallyDown
        view.part1.addSubview(icon)
        configureField(divideField, identifier: "CGDivide", enabled: true)
        divideField.frame = NSRect(x: 33, y: 3, width: 58, height: 23)
        divideField.alignment = .right
        view.part1.addSubview(divideField)
        configureField(subField, identifier: "CGSub", enabled: true)
        subField.frame = NSRect(x: 97, y: 3, width: 58, height: 23)
        subField.alignment = .right
        view.part1.addSubview(subField)
        let slash = iconButton("Shortcut", frame: NSRect(x: 158, y: 4, width: 22, height: 22), tooltip: "Division shortcuts")
        slash.action = #selector(slashClicked)
        view.part1.addSubview(slash)

        let heightIcon = NSImageView(frame: NSRect(x: 3, y: 30, width: 24, height: 24))
        heightIcon.image = LegacyChromeIcons.image(named: "lgheight")
        view.part1.addSubview(heightIcon)
        heightSlider.frame = NSRect(x: 30, y: 30, width: 107, height: 28)
        heightSlider.minValue = 1
        heightSlider.maxValue = 20
        heightSlider.doubleValue = 4
        heightSlider.target = self
        heightSlider.action = #selector(heightSliderChanged(_:))
        view.part1.addSubview(heightSlider)
        configureField(heightField, identifier: "CGHeight", enabled: true)
        heightField.frame = NSRect(x: 137, y: 30, width: 43, height: 23)
        view.part1.addSubview(heightField)

        let widthIcon = NSImageView(frame: NSRect(x: 3, y: 58, width: 24, height: 24))
        widthIcon.image = LegacyChromeIcons.image(named: "lgwidth")
        view.part1.addSubview(widthIcon)
        widthSlider.frame = NSRect(x: 30, y: 58, width: 107, height: 28)
        widthSlider.minValue = 1
        widthSlider.maxValue = 20
        widthSlider.doubleValue = 4
        widthSlider.target = self
        widthSlider.action = #selector(widthSliderChanged(_:))
        view.part1.addSubview(widthSlider)
        configureField(widthField, identifier: "CGWidth", enabled: true)
        widthField.frame = NSRect(x: 137, y: 58, width: 43, height: 23)
        view.part1.addSubview(widthField)

        snapBox.frame = NSRect(x: 3, y: 89, width: 162, height: 19)
        NativeLocalization.markFixed(snapBox, key: "Snap to grid (G)")
        snapBox.title = NativeLocalization.text("Snap to grid (G)")
        snapBox.font = LegacyChromeFont.segoe
        snapBox.state = .on
        snapBox.target = self
        snapBox.action = #selector(snapChanged)
        view.part1.addSubview(snapBox)
        verticalBox.frame = NSRect(x: 3, y: 108, width: 177, height: 19)
        NativeLocalization.markFixed(verticalBox, key: "Disable vertical moves (D)")
        verticalBox.title = NativeLocalization.text("Disable vertical moves (D)")
        verticalBox.font = LegacyChromeFont.segoe
        verticalBox.target = self
        verticalBox.action = #selector(verticalChanged)
        view.part1.addSubview(verticalBox)

        if let part2 = view.part2 {
            let columns = NSTextField(labelWithString: NativeLocalization.text("Number of B Columns"))
            NativeLocalization.markFixed(columns, key: "Number of B Columns")
            columns.font = LegacyChromeFont.segoe
            columns.alignment = .right
            columns.frame = NSRect(x: 3, y: 0, width: 126, height: 29)
            part2.addSubview(columns)
            configureField(bgmColumnsField, identifier: "CGB", enabled: true)
            bgmColumnsField.frame = NSRect(x: 135, y: 3, width: 45, height: 23)
            part2.addSubview(bgmColumnsField)
            let lockLabel = NSTextField(labelWithString: NativeLocalization.text("Vertical Scroll Lock"))
            NativeLocalization.markFixed(lockLabel, key: "Vertical Scroll Lock")
            lockLabel.font = LegacyChromeFont.segoe
            lockLabel.alignment = .right
            lockLabel.frame = NSRect(x: 3, y: 29, width: 106, height: 29)
            part2.addSubview(lockLabel)
            for (index, tip) in ["Lock Left Editing Panel", "Lock Middle Editing Panel", "Lock Right Editing Panel"].enumerated() {
                let lock = iconButton("x16Lock", frame: NSRect(x: 115 + CGFloat(index) * 23, y: 32, width: 23, height: 23), tooltip: tip)
                lock.setButtonType(.pushOnPushOff)
                lock.tag = index
                lock.action = #selector(scrollLockChanged(_:))
                part2.addSubview(lock)
                lockButtons.append(lock)
            }
        }
    }

    private func fillWaveform(_ view: OptionsSectionView) {
        let load = iconButton("x16Add", frame: NSRect(x: 0, y: 3, width: 24, height: 24), tooltip: "Load WaveForm")
        load.identifier = NSUserInterfaceItemIdentifier("BWLoad")
        load.action = #selector(loadWaveformFile)
        view.part1.addSubview(load)
        let clear = iconButton("x16Remove", frame: NSRect(x: 24, y: 3, width: 24, height: 24), tooltip: "Clear WaveForm")
        clear.identifier = NSUserInterfaceItemIdentifier("BWClear")
        clear.action = #selector(clearWaveformFile)
        view.part1.addSubview(clear)
        waveformLockButton.frame = NSRect(x: 48, y: 3, width: 24, height: 24)
        waveformLockButton.image = LegacyChromeIcons.image(named: "x16Lock")
        waveformLockButton.imagePosition = .imageOnly
        waveformLockButton.isBordered = true
        waveformLockButton.bezelStyle = .shadowlessSquare
        waveformLockButton.setButtonType(.pushOnPushOff)
        waveformLockButton.state = .on
        waveformLockButton.toolTip = "Lock to BGM"
        waveformLockButton.identifier = NSUserInterfaceItemIdentifier("BWLock")
        waveformLockButton.target = self
        waveformLockButton.action = #selector(toggleWaveformLock)
        view.part1.addSubview(waveformLockButton)
        configureField(waveformFileField, identifier: "TWFileName", enabled: false)
        waveformFileField.frame = NSRect(x: 81, y: 3, width: 99, height: 23)
        view.part1.addSubview(waveformFileField)
        let offset = NSImageView(frame: NSRect(x: 3, y: 30, width: 24, height: 24))
        offset.image = LegacyChromeIcons.image(named: "WAVOffset")
        view.part1.addSubview(offset)
        waveformPositionSlider.frame = NSRect(x: 30, y: 30, width: 91, height: 28)
        waveformPositionSlider.minValue = 0
        waveformPositionSlider.maxValue = Double(LegacyWaveform.sliderMaximum)
        waveformPositionSlider.doubleValue = Double(LegacyWaveform.sliderValue(LegacyWaveform.defaultPosition))
        waveformPositionSlider.altIncrementValue = 24
        waveformPositionSlider.numberOfTickMarks = 6
        waveformPositionSlider.isEnabled = false
        waveformPositionSlider.identifier = NSUserInterfaceItemIdentifier("TWPosition2")
        waveformPositionSlider.target = self
        waveformPositionSlider.action = #selector(waveformPositionSliderChanged(_:))
        view.part1.addSubview(waveformPositionSlider)
        configureField(waveformPositionField, identifier: "TWPosition", enabled: false)
        waveformPositionField.frame = NSRect(x: 121, y: 30, width: 59, height: 23)
        view.part1.addSubview(waveformPositionField)
        if let part2 = view.part2 {
            addWaveformDisplayRow(
                in: part2,
                y: 0,
                icon: "WAVLeft",
                field: waveformLeftField,
                slider: waveformLeftSlider,
                fieldID: "TWLeft",
                sliderID: "TWLeft2",
                value: LegacyWaveform.defaultLeft,
                maximum: 800,
                increment: 5
            )
            addWaveformDisplayRow(
                in: part2,
                y: 28,
                icon: "WAVWidth",
                field: waveformWidthField,
                slider: waveformWidthSlider,
                fieldID: "TWWidth",
                sliderID: "TWWidth2",
                value: LegacyWaveform.defaultWidth,
                maximum: 1000,
                increment: 10
            )
            addWaveformDisplayRow(
                in: part2,
                y: 56,
                icon: "WAVPrecision",
                field: waveformPrecisionField,
                slider: waveformPrecisionSlider,
                fieldID: "TWPrecision",
                sliderID: "TWPrecision2",
                value: LegacyWaveform.defaultPrecision,
                maximum: 50,
                increment: 1
            )
            addWaveformDisplayRow(
                in: part2,
                y: 84,
                icon: "WAVTransparency",
                field: waveformTransparencyField,
                slider: waveformTransparencySlider,
                fieldID: "TWTransparency",
                sliderID: "TWTransparency2",
                value: LegacyWaveform.defaultTransparency,
                maximum: 255,
                increment: 10
            )
            addWaveformDisplayRow(
                in: part2,
                y: 112,
                icon: "WAVSaturation",
                field: waveformSaturationField,
                slider: waveformSaturationSlider,
                fieldID: "TWSaturation",
                sliderID: "TWSaturation2",
                value: LegacyWaveform.defaultSaturation,
                maximum: 1000,
                increment: 50
            )
        }
    }

    func setWaveformPen(from color: ThemeColor) {
        let transparency = Int(color.alpha)
        let saturation = LegacyWaveform.saturationSlider(from: color)
        waveformTransparencyField.stringValue = "\(transparency)"
        waveformTransparencySlider.doubleValue = Double(transparency)
        waveformSaturationField.stringValue = "\(saturation)"
        waveformSaturationSlider.doubleValue = Double(saturation)
    }

    private func addWaveformDisplayRow(
        in parent: NSView,
        y: CGFloat,
        icon: String,
        field: NSTextField,
        slider: NSSlider,
        fieldID: String,
        sliderID: String,
        value: Int,
        maximum: Double,
        increment: Double
    ) {
        let image = NSImageView(frame: NSRect(x: 3, y: y, width: 24, height: 24))
        image.image = LegacyChromeIcons.image(named: icon)
        parent.addSubview(image)
        slider.frame = NSRect(x: 30, y: y, width: 107, height: 28)
        slider.minValue = 0
        slider.maxValue = maximum
        slider.doubleValue = Double(value)
        slider.altIncrementValue = increment
        slider.identifier = NSUserInterfaceItemIdentifier(sliderID)
        slider.target = self
        slider.action = #selector(waveformDisplaySliderChanged(_:))
        parent.addSubview(slider)
        configureField(field, identifier: fieldID, enabled: true)
        field.frame = NSRect(x: 137, y: y, width: 43, height: 23)
        field.stringValue = "\(value)"
        parent.addSubview(field)
    }

    func setWaveformFileName(_ text: String) {
        waveformFileField.stringValue = text
    }

    @objc private func loadWaveformFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.wav]
        if let ogg = UTType(filenameExtension: "ogg") {
            types.append(ogg)
        }
        panel.allowedContentTypes = types
        let parent = window
        let present: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.onWaveformLoad?(url)
        }
        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: present)
        } else {
            present(panel.runModal())
        }
    }

    @objc private func clearWaveformFile() {
        onWaveformClear?()
    }

    @objc private func toggleWaveformLock() {
        let locked = waveformLockButton.state == .on
        waveformPositionField.isEnabled = !locked
        waveformPositionSlider.isEnabled = !locked
        onWaveformLockChange?(locked)
    }

    var wavSynchronizeLabels: Bool { wavChangeLabelBox.state == .on }
    var wavAllowsMultipleSelection: Bool { wavMultiSelectBox.state == .on }

    func setWavListOptions(multiSelect: Bool, synchronizeLabels: Bool) {
        wavMultiSelectBox.state = multiSelect ? .on : .off
        wavChangeLabelBox.state = synchronizeLabels ? .on : .off
        wavMultiSelectChanged()
    }

    var selectedWavSlots: [Int] {
        wavTable.selectedRowIndexes.sorted()
    }

    var selectedWavIndex: Int { wavTable.selectedRow }

    func selectWavSlots(_ slots: [Int]) {
        wavTable.selectRowIndexes(IndexSet(slots), byExtendingSelection: false)
        if let first = slots.min() {
            wavTable.scrollRowToVisible(first)
        }
    }

    func currentWavNames() -> [String] {
        LegacyWavList.names(from: wavNames)
    }

    var selectedBmpSlots: [Int] {
        bmpTable.selectedRowIndexes.sorted()
    }

    func selectBmpSlots(_ slots: [Int]) {
        bmpTable.selectRowIndexes(IndexSet(slots), byExtendingSelection: false)
        if let first = slots.min() {
            bmpTable.scrollRowToVisible(first)
        }
    }

    func currentBmpNames() -> [String] {
        LegacyWavList.names(from: bmpNames)
    }

    private func fillResourceList(_ view: OptionsSectionView, table: NSTableView, prefix: String) {
        let names = ["x16Up", "x16Down", "x16PlayerBrowse", "x16Remove"]
        let tips = ["Move Up", "Move Down", "Browse", "Remove"]
        let wavIDs = ["BWAVUp", "BWAVDown", "BWAVBrowse", "BWAVRemove"]
        let bmpIDs = ["BBMPUp", "BBMPDown", "BBMPBrowse", "BBMPRemove"]
        for (index, name) in names.enumerated() {
            let button = iconButton(name, frame: NSRect(x: CGFloat(index) * 24, y: 3, width: 24, height: 24), tooltip: tips[index])
            if prefix == "WAV" {
                button.identifier = NSUserInterfaceItemIdentifier(wavIDs[index])
                switch index {
                case 0: button.action = #selector(wavMoveUp)
                case 1: button.action = #selector(wavMoveDown)
                case 2: button.action = #selector(wavBrowse)
                default: button.action = #selector(wavRemove)
                }
            } else if prefix == "BMP" {
                button.identifier = NSUserInterfaceItemIdentifier(bmpIDs[index])
                switch index {
                case 0: button.action = #selector(bmpMoveUp)
                case 1: button.action = #selector(bmpMoveDown)
                case 2: button.action = #selector(bmpBrowse)
                default: button.action = #selector(bmpRemove)
                }
            }
            view.part1.addSubview(button)
        }
        if let part2 = view.part2 {
            if prefix == "WAV" {
                NativeLocalization.markFixed(wavMultiSelectBox, key: "Allow Multiple Selection")
                wavMultiSelectBox.title = NativeLocalization.text("Allow Multiple Selection")
                wavMultiSelectBox.font = LegacyChromeFont.segoe
                wavMultiSelectBox.state = .on
                wavMultiSelectBox.frame = NSRect(x: 3, y: 0, width: 177, height: 19)
                wavMultiSelectBox.target = self
                wavMultiSelectBox.action = #selector(wavMultiSelectChanged)
                part2.addSubview(wavMultiSelectBox)
                wavChangeLabelBox.font = LegacyChromeFont.segoe
                NativeLocalization.markFixed(wavChangeLabelBox, key: "Synchronize Note Labels")
                wavChangeLabelBox.title = NativeLocalization.text("Synchronize Note Labels")
                wavChangeLabelBox.state = .on
                wavChangeLabelBox.frame = NSRect(x: 3, y: 19, width: 177, height: 19)
                part2.addSubview(wavChangeLabelBox)
            }
        }
        configureTable(table)
        table.allowsMultipleSelection = wavAllowsMultipleSelection
        let scroll = NSScrollView(frame: NSRect(x: 3, y: 0, width: 177, height: MainWindowChrome.listBoxHeight))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        view.listHost = scroll
        view.addSubview(scroll)
        if prefix == "WAV" {
            table.action = #selector(wavSelectionChanged)
            table.target = self
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            channelFormatLabel.font = LegacyChromeFont.segoe
            NativeLocalization.markTooltip(channelFormatLabel, key: "Format")
            channelFormatLabel.frame = NSRect(x: 4, y: 4, width: 104, height: 16)
            channelLengthLabel.font = LegacyChromeFont.segoe
            channelLengthLabel.alignment = .right
            NativeLocalization.markTooltip(channelLengthLabel, key: "Length")
            channelLengthLabel.frame = NSRect(x: 108, y: 4, width: 69, height: 16)
            channelInfoBar.wantsLayer = true
            channelInfoBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            channelInfoBar.addSubview(channelFormatLabel)
            channelInfoBar.addSubview(channelLengthLabel)
            channelInfoBar.isHidden = true
            channelWaveformView.isHidden = true
            view.addSubview(channelWaveformView)
            view.addSubview(channelInfoBar)
        } else {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func fillBeat(_ view: OptionsSectionView) {
        configureField(beatNumeratorField, identifier: "nBeatN", enabled: true)
        beatNumeratorField.frame = NSRect(x: 3, y: 3, width: 45, height: 23)
        view.part1.addSubview(beatNumeratorField)
        let slash = NSTextField(labelWithString: "/")
        slash.font = LegacyChromeFont.segoe
        slash.alignment = .center
        slash.frame = NSRect(x: 51, y: 7, width: 12, height: 15)
        view.part1.addSubview(slash)
        configureField(beatDenominatorField, identifier: "nBeatD", enabled: true)
        beatDenominatorField.frame = NSRect(x: 66, y: 3, width: 45, height: 23)
        view.part1.addSubview(beatDenominatorField)
        let applyFraction = NSButton(title: "Apply", target: self, action: #selector(applyBeatFraction))
        NativeLocalization.markFixed(applyFraction, key: "Apply")
        applyFraction.title = NativeLocalization.text("Apply")
        applyFraction.bezelStyle = .shadowlessSquare
        applyFraction.font = LegacyChromeFont.segoe
        applyFraction.frame = NSRect(x: 114, y: 2, width: 66, height: 25)
        view.part1.addSubview(applyFraction)
        configureField(beatValueField, identifier: "tBeatValue", enabled: true)
        beatValueField.frame = NSRect(x: 3, y: 30, width: 108, height: 23)
        view.part1.addSubview(beatValueField)
        let applyValue = NSButton(title: "Apply", target: self, action: #selector(applyBeatValue))
        NativeLocalization.markFixed(applyValue, key: "Apply")
        applyValue.title = NativeLocalization.text("Apply")
        applyValue.bezelStyle = .shadowlessSquare
        applyValue.font = LegacyChromeFont.segoe
        applyValue.frame = NSRect(x: 114, y: 29, width: 66, height: 25)
        view.part1.addSubview(applyValue)

        let titles: [(LegacyBeat.Mode, String)] = [
            (.preserve, "Keep absolute position"),
            (.measure, "Keep measure position"),
            (.cut, "Keep measure position and cut overflow"),
            (.scale, "Scale to measure length"),
        ]
        if let part2 = view.part2 {
            for (index, item) in titles.enumerated() {
                let button = NSButton(radioButtonWithTitle: NativeLocalization.text(item.1), target: self, action: #selector(beatModeChanged(_:)))
                NativeLocalization.markFixed(button, key: item.1)
                button.font = LegacyChromeFont.segoe
                button.tag = item.0.rawValue
                button.state = item.0 == .preserve ? .on : .off
                button.frame = NSRect(x: 3, y: CGFloat(index * 19), width: 177, height: 19)
                part2.addSubview(button)
                beatModeButtons[item.0] = button
            }
        }

        configureTable(beatTable)
        beatTable.allowsMultipleSelection = true
        let scroll = NSScrollView(frame: NSRect(x: 3, y: 0, width: 177, height: MainWindowChrome.listBoxHeight))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = beatTable
        view.listHost = scroll
        view.addSubview(scroll)
    }

    private func fillExpansion(_ view: OptionsSectionView) {
        expansionView.frame = NSRect(x: 0, y: 0, width: 183, height: MainWindowChrome.expansionBoxHeight)
        expansionView.font = LegacyChromeFont.list
        expansionView.isRichText = false
        expansionView.isAutomaticQuoteSubstitutionEnabled = false
        expansionView.isAutomaticDashSubstitutionEnabled = false
        expansionView.isAutomaticTextReplacementEnabled = false
        expansionView.usesFindBar = true
        expansionView.delegate = self
        expansionView.minSize = NSSize(width: 0, height: MainWindowChrome.expansionBoxHeight)
        expansionView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        expansionView.isVerticallyResizable = true
        expansionView.isHorizontallyResizable = true
        expansionView.textContainer?.widthTracksTextView = true
        expansionView.textContainer?.containerSize = NSSize(width: 183, height: CGFloat.greatestFiniteMagnitude)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 183, height: MainWindowChrome.expansionBoxHeight))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        scroll.documentView = expansionView
        view.listHost = scroll
        view.addSubview(scroll)
    }

    private func configureTable(_ table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("token"))
        column.width = 160
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 14
        table.font = LegacyChromeFont.list
        table.allowsMultipleSelection = true
        table.backgroundColor = .textBackgroundColor
        table.registerForDraggedTypes([.fileURL])
        if let table = table as? ResourceDropTableView {
            table.onDragExit = { [weak self] in self?.onResourceDragPreview?([]) }
        }
    }

    func containsResourceDrop(at windowPoint: NSPoint) -> Bool {
        wavTable.convert(wavTable.bounds, to: nil).contains(windowPoint)
            || bmpTable.convert(bmpTable.bounds, to: nil).contains(windowPoint)
    }

    private func addHeaderLabel(_ text: String, at frame: NSRect, in parent: NSView) {
        let label = NSTextField(labelWithString: NativeLocalization.text(text))
        NativeLocalization.markFixed(label, key: text)
        label.font = LegacyChromeFont.segoe
        label.alignment = .right
        label.frame = frame
        parent.addSubview(label)
    }

    private func makeTextField(identifier: String, enabled: Bool) -> NSTextField {
        let field = NSTextField(string: "")
        configureField(field, identifier: identifier, enabled: enabled)
        return field
    }

    private func configureField(_ field: NSTextField, identifier: String, enabled: Bool) {
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.font = LegacyChromeFont.segoe
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.isEnabled = enabled
        field.delegate = self
        field.target = self
        field.action = #selector(fieldCommitted(_:))
    }

    private func makePopup(_ items: [String], enabled: Bool, key: String) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        // 这些三组下拉项按索引写回谱面；只改显示文字，不改变保存值或选择索引。
        if key != "LNOBJ" {
            NativeLocalization.markFixed(popup, key: "header-popup-\(key)")
            for (source, item) in zip(items, popup.itemArray) {
                NativeLocalization.markFixed(item, key: source)
                item.title = NativeLocalization.text(source)
            }
        }
        popup.font = LegacyChromeFont.segoe
        popup.isEnabled = enabled
        popup.identifier = NSUserInterfaceItemIdentifier(key)
        popup.target = self
        popup.action = #selector(popupCommitted(_:))
        return popup
    }

    private func iconButton(_ icon: String, frame: NSRect, tooltip: String) -> NSButton {
        let button = NSButton(frame: frame)
        button.image = LegacyChromeIcons.image(named: icon)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.bezelStyle = .shadowlessSquare
        NativeLocalization.markTooltip(button, key: tooltip)
        button.target = self
        button.action = #selector(unimplementedControl(_:))
        return button
    }

    private func relayout() {
        var y: CGFloat = 0
        if showsBmsonDocks {
            if let infoSection { infoSection.isHidden = false; infoSection.frame = NSRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: infoSection.requiredHeight); y += infoSection.requiredHeight }
            if let selectedSection { selectedSection.isHidden = false; selectedSection.frame = NSRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: selectedSection.requiredHeight); y += selectedSection.requiredHeight }
        } else {
            infoSection?.isHidden = true
            selectedSection?.isHidden = true
        }
        for section in OptionsSectionID.allCases {
            guard let view = sectionViews[section] else { continue }
            let switchOn = state.switchOn[section] == true
            let part2 = state.part2Visible[section] == true
            let height = section.height(switchOn: switchOn, part2Visible: part2)
            view.frame = NSRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: height)
            view.apply(switchOn: switchOn, part2Visible: part2)
            if section == .wav {
                applyBmsonChannelInfoBar(in: view, switchOn: switchOn)
            }
            y += height
        }
        document.frame = NSRect(x: 0, y: 0, width: MainWindowChrome.optionsDocumentWidth, height: max(y, contentView.bounds.height))
    }

    @objc private func toggleSection(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let section = OptionsSectionID(rawValue: raw) else { return }
        state.switchOn[section] = sender.state == .on
        relayout()
    }

    @objc private func togglePart2(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let section = OptionsSectionID(rawValue: raw) else { return }
        let visible = sender.state == .on
        state.part2Visible[section] = visible
        let title = visible ? "Collapse..." : "Expand..."
        NativeLocalization.markFixed(sender, key: title)
        sender.title = NativeLocalization.text(title)
        relayout()
    }

    @objc private func fieldCommitted(_ sender: NSTextField) {
        guard let key = sender.identifier?.rawValue else { return }
        if key == "CGDivide" {
            onDivisionChange?(selectedDivision)
            return
        }
        if key == "CGSub" {
            onSubDivisionChange?(selectedSubDivision)
            return
        }
        if key == "CGHeight" {
            onZoomChange?(MainWindowChrome.pixelsPerQuarterBeat(gridHeight: gridHeight))
            return
        }
        if key == "CGWidth" {
            applyColumnScale(Double(widthField.stringValue) ?? 1)
            return
        }
        if key == "CGB" {
            let count = selectedBGMColumnCount
            sender.stringValue = "\(count)"
            onBGMColumnChange?(count)
            return
        }
        if key == "TWPosition" {
            commitWaveformPosition()
            return
        }
        if key == "TWLeft" || key == "TWWidth" || key == "TWPrecision" {
            commitWaveformDisplayFields()
            return
        }
        if key == "TWTransparency" {
            commitWaveformTransparency()
            return
        }
        if key == "TWSaturation" {
            commitWaveformSaturation()
            return
        }
        if key == "nBeatN" {
            sender.stringValue = "\(clampedBeatNumerator())"
            return
        }
        if key == "nBeatD" {
            sender.stringValue = "\(clampedBeatDenominator())"
            return
        }
        if key == "tBeatValue" {
            refreshBeatValueField()
            return
        }
        if key == "BPM" {
            if onBPMCommit?(sender.stringValue) != true {
                sender.selectText(nil)
            }
            return
        }
        if DocumentSession.editableKeys.contains(key) {
            if onMetadataCommit?(key, sender.stringValue) != true {
                sender.selectText(nil)
            }
        }
    }

    @objc private func slashClicked(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = LegacyGridDivision.prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "\(slashValue)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let next = LegacyGridDivision.parseSlash(field.stringValue) {
            slashValue = next
        }
    }

    @objc private func snapChanged(_ sender: NSButton) {
        onSnapChange?(sender.state == .on)
    }

    @objc private func verticalChanged(_ sender: NSButton) {
        onVerticalMoveChange?(sender.state == .on)
    }

    @objc private func scrollLockChanged(_ sender: NSButton) {
        onScrollLockChange?(sender.tag, sender.state == .on)
    }

    @objc private func heightSliderChanged(_ sender: NSSlider) {
        let value = sender.doubleValue / 4
        heightField.stringValue = String(format: "%.2f", value)
        onZoomChange?(MainWindowChrome.pixelsPerQuarterBeat(gridHeight: CGFloat(value)))
    }

    @objc private func widthSliderChanged(_ sender: NSSlider) {
        applyColumnScale(sender.doubleValue / 4)
    }

    private func applyColumnScale(_ value: Double) {
        let clamped = ChartZoom.clampField(value)
        widthField.stringValue = String(format: "%.2f", clamped)
        widthSlider.doubleValue = Double(ChartZoom.trackValueFromField(clamped))
        onColumnScaleChange?(CGFloat(clamped))
    }

    @objc private func waveformDisplaySliderChanged(_ sender: NSSlider) {
        switch sender.identifier?.rawValue {
        case "TWLeft2":
            let value = LegacyWaveform.clampLeft(Int(sender.doubleValue.rounded()))
            waveformLeftField.stringValue = "\(value)"
            sender.doubleValue = Double(value)
        case "TWWidth2":
            let value = LegacyWaveform.clampWidth(Int(sender.doubleValue.rounded()))
            waveformWidthField.stringValue = "\(value)"
            sender.doubleValue = Double(value)
        case "TWPrecision2":
            let value = LegacyWaveform.clampPrecision(Int(sender.doubleValue.rounded()))
            waveformPrecisionField.stringValue = "\(value)"
            sender.doubleValue = Double(value)
        case "TWTransparency2":
            let value = LegacyWaveform.clampTransparency(Int(sender.doubleValue.rounded()))
            waveformTransparencyField.stringValue = "\(value)"
            sender.doubleValue = Double(value)
            onWaveformTransparencyChange?(value)
            return
        case "TWSaturation2":
            let value = LegacyWaveform.clampSaturation(Int(sender.doubleValue.rounded()))
            waveformSaturationField.stringValue = "\(value)"
            sender.doubleValue = Double(value)
            onWaveformSaturationChange?(value)
            return
        default:
            return
        }
        emitWaveformDisplay()
    }

    @objc private func waveformPositionSliderChanged(_ sender: NSSlider) {
        let value = Double(min(LegacyWaveform.sliderMaximum, max(0, Int(sender.doubleValue.rounded(.towardZero)))))
        sender.doubleValue = value
        waveformPositionField.stringValue = String(format: "%.2f", value)
        onWaveformPositionChange?(value)
    }

    private func commitWaveformPosition() {
        let parsed = Double(waveformPositionField.stringValue) ?? LegacyWaveform.defaultPosition
        let value = LegacyWaveform.clampPosition(parsed)
        waveformPositionField.stringValue = String(format: "%.2f", value)
        waveformPositionSlider.doubleValue = Double(LegacyWaveform.sliderValue(value))
        onWaveformPositionChange?(value)
    }

    private func commitWaveformTransparency() {
        let value = LegacyWaveform.clampTransparency(Int(waveformTransparencyField.stringValue) ?? LegacyWaveform.defaultTransparency)
        waveformTransparencyField.stringValue = "\(value)"
        waveformTransparencySlider.doubleValue = Double(value)
        onWaveformTransparencyChange?(value)
    }

    private func commitWaveformSaturation() {
        let value = LegacyWaveform.clampSaturation(Int(waveformSaturationField.stringValue) ?? LegacyWaveform.defaultSaturation)
        waveformSaturationField.stringValue = "\(value)"
        waveformSaturationSlider.doubleValue = Double(value)
        onWaveformSaturationChange?(value)
    }

    private func commitWaveformDisplayFields() {
        let left = LegacyWaveform.clampLeft(Int(waveformLeftField.stringValue) ?? LegacyWaveform.defaultLeft)
        let width = LegacyWaveform.clampWidth(Int(waveformWidthField.stringValue) ?? LegacyWaveform.defaultWidth)
        let precision = LegacyWaveform.clampPrecision(Int(waveformPrecisionField.stringValue) ?? LegacyWaveform.defaultPrecision)
        waveformLeftField.stringValue = "\(left)"
        waveformWidthField.stringValue = "\(width)"
        waveformPrecisionField.stringValue = "\(precision)"
        waveformLeftSlider.doubleValue = Double(left)
        waveformWidthSlider.doubleValue = Double(width)
        waveformPrecisionSlider.doubleValue = Double(precision)
        emitWaveformDisplay()
    }

    private func emitWaveformDisplay() {
        onWaveformDisplayChange?(
            LegacyWaveform.clampLeft(Int(waveformLeftField.stringValue) ?? LegacyWaveform.defaultLeft),
            LegacyWaveform.clampWidth(Int(waveformWidthField.stringValue) ?? LegacyWaveform.defaultWidth),
            LegacyWaveform.clampPrecision(Int(waveformPrecisionField.stringValue) ?? LegacyWaveform.defaultPrecision)
        )
    }

    @objc private func wavSelectionChanged() {
        onTokenChange?(selectedToken)
    }

    @objc private func wavMultiSelectChanged() {
        wavTable.allowsMultipleSelection = wavAllowsMultipleSelection
        bmpTable.allowsMultipleSelection = wavAllowsMultipleSelection
        if !wavAllowsMultipleSelection, wavTable.numberOfSelectedRows > 1 {
            wavTable.selectRowIndexes(IndexSet(integer: max(0, wavTable.selectedRow)), byExtendingSelection: false)
        }
        if !wavAllowsMultipleSelection, bmpTable.numberOfSelectedRows > 1 {
            bmpTable.selectRowIndexes(IndexSet(integer: max(0, bmpTable.selectedRow)), byExtendingSelection: false)
        }
    }

    @objc private func wavMoveUp() { onWavMoveUp?() }
    @objc private func wavMoveDown() { onWavMoveDown?() }
    @objc private func wavBrowse() { onWavBrowse?() }
    @objc private func wavRemove() { onWavRemove?() }
    @objc private func bmpMoveUp() { onBmpMoveUp?() }
    @objc private func bmpMoveDown() { onBmpMoveDown?() }
    @objc private func bmpBrowse() { onBmpBrowse?() }
    @objc private func bmpRemove() { onBmpRemove?() }

    @objc private func beatModeChanged(_ sender: NSButton) {
        guard let mode = LegacyBeat.Mode(rawValue: sender.tag) else { return }
        beatMode = mode
        for (item, button) in beatModeButtons {
            button.state = item == mode ? .on : .off
        }
    }

    @objc private func applyBeatFraction() {
        let numerator = clampedBeatNumerator()
        let denominator = clampedBeatDenominator()
        beatNumeratorField.stringValue = "\(numerator)"
        beatDenominatorField.stringValue = "\(denominator)"
        guard let ratio = LegacyBeat.fractionRatio(numerator: numerator, denominator: denominator),
              let display = LegacyBeat.fractionDisplay(numerator: numerator, denominator: denominator) else {
            NSSound.beep()
            return
        }
        applyBeat(ratio: ratio, display: display)
    }

    @objc private func applyBeatValue() {
        refreshBeatValueField()
        guard let value = LegacyBeat.parseValue(beatValueField.stringValue) else {
            NSSound.beep()
            return
        }
        applyBeat(ratio: value, display: LegacyBeat.valueDisplay(value))
    }

    private func applyBeat(ratio: Double, display: String) {
        let measures = selectedBeatMeasures()
        guard !measures.isEmpty else { return }
        if onBeatApply?(measures, LegacyBeat.ratioDecimal(ratio), beatMode) == true {
            for measure in measures {
                beatItems[measure] = LegacyBeat.listItem(measure: measure, display: display)
            }
            beatTable.reloadData()
            beatTable.selectRowIndexes(IndexSet(measures), byExtendingSelection: false)
        }
    }

    private func selectedBeatMeasures() -> [Int] {
        beatTable.selectedRowIndexes.sorted().filter { $0 >= 0 && $0 < LegacyBeat.measureCount }
    }

    private func clampedBeatNumerator() -> Int {
        max(1, min(99_999, Int(beatNumeratorField.stringValue) ?? LegacyBeat.defaultNumerator))
    }

    private func clampedBeatDenominator() -> Int {
        max(1, min(10_000, Int(beatDenominatorField.stringValue) ?? LegacyBeat.defaultDenominator))
    }

    private func refreshBeatValueField() {
        let text = beatValueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(text), value.isFinite {
            beatValueField.stringValue = LegacyBeat.vbDouble(value)
            if value <= 0 || value >= 1000 {
                beatValueField.backgroundColor = NSColor(srgbRed: 1, green: 192 / 255, blue: 192 / 255, alpha: 1)
                beatValueField.drawsBackground = true
            } else {
                beatValueField.backgroundColor = NSColor.textBackgroundColor
                beatValueField.drawsBackground = true
            }
        }
    }

    func textDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextView === expansionView, !isSettingExpansion else { return }
        _ = onExpansionCommit?(expansionView.string)
    }

    @objc private func unimplementedControl(_ sender: Any?) {
        onNotice?("This options-panel control is not wired yet.")
    }

    @objc private func popupCommitted(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue else { return }
        let selected = sender.indexOfSelectedItem
        let previous = committedPopupIndices[key]
        let value = LegacyHeaderFields.storedValue(key: key, popupIndex: selected)
        if onMetadataCommit?(key, value) == true {
            committedPopupIndices[key] = selected
            return
        }
        if let previous, (0..<sender.numberOfItems).contains(previous) {
            sender.selectItem(at: previous)
        }
    }

    private func rememberPopupIndex(_ popup: NSPopUpButton) {
        guard let key = popup.identifier?.rawValue else { return }
        let index = popup.indexOfSelectedItem
        guard index >= 0 else { return }
        committedPopupIndices[key] = index
    }

    @objc private func browseHeaderFile(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .bmp, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let parent = window
        let present: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let name = panel.url?.lastPathComponent else { return }
            self?.metadataFields[key]?.stringValue = name
            _ = self?.onMetadataCommit?(key, name)
        }
        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: present)
        } else {
            present(panel.runModal())
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let key = field.identifier?.rawValue,
              DocumentSession.editableKeys.contains(key) else { return }
        onMetadataDraft?(key, field.stringValue)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === beatTable ? beatItems.count : BMS36Token.all.count
    }

    func setBeatFromChart(_ measures: [ChartMeasureSnapshot]) {
        let selected = beatTable.selectedRowIndexes
        var items = LegacyBeat.defaultItems()
        for measure in measures where measure.measure >= 0 && measure.measure < LegacyBeat.measureCount {
            let ratio = measure.length / 4
            if abs(ratio - 1) < 0.000_000_000_001 {
                continue
            }
            items[measure.measure] = LegacyBeat.loadedItem(measure: measure.measure, ratio: ratio)
        }
        beatItems = items
        beatTable.reloadData()
        beatTable.selectRowIndexes(selected.intersection(IndexSet(integersIn: 0..<LegacyBeat.measureCount)), byExtendingSelection: false)
    }

    func setExpansionText(_ text: String, enabled: Bool) {
        expansionView.isEditable = enabled
        let display = LegacyExpansion.displayText(from: text)
        guard !LegacyExpansion.sameLines(expansionView.string, display) else { return }
        isSettingExpansion = true
        expansionView.string = display
        isSettingExpansion = false
    }

    func setWavTable(_ table: [String: String]) {
        let selected = selectedWavSlots
        wavNames = table
        wavTable.reloadData()
        if !selected.isEmpty {
            selectWavSlots(selected.filter { $0 >= 0 && $0 < BMS36Token.all.count })
        }
    }

    func setBmpTable(_ table: [String: String]) {
        let selected = selectedBmpSlots
        bmpNames = table
        bmpTable.reloadData()
        if !selected.isEmpty {
            selectBmpSlots(selected.filter { $0 >= 0 && $0 < BMS36Token.all.count })
        }
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard tableView === wavTable || tableView === bmpTable else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        let paths = droppedFilePaths(from: info)
        guard !paths.isEmpty else { return [] }
        let extensions = tableView === wavTable ? LegacyWavList.audioExtensions : LegacyWavList.imageExtensions
        onResourceDragPreview?(LegacyWavList.filterDropped(paths: paths, extensions: extensions))
        return .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        onResourceDragPreview?([])
        let paths = droppedFilePaths(from: info)
        guard !paths.isEmpty else { return false }
        if tableView === wavTable {
            onWavDrop?(paths)
            return true
        }
        if tableView === bmpTable {
            onBmpDrop?(paths)
            return true
        }
        return false
    }

    private func droppedFilePaths(from info: NSDraggingInfo) -> [String] {
        let urls = (info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        return urls.map(\.path)
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if tableView === beatTable {
            return beatItems[row]
        }
        let token = BMS36Token.all[row]
        if tableView === wavTable {
            return LegacyWavList.displayLine(token: token, name: wavNames[token] ?? "")
        }
        if tableView === bmpTable {
            return LegacyWavList.displayLine(token: token, name: bmpNames[token] ?? "")
        }
        return "\(token):"
    }
}

@MainActor
private final class BmsonAuxiliarySection: NSView {
    private let header: NSButton
    private let content: NSView
    private let onChange: () -> Void
    private(set) var isExpanded = false

    var requiredHeight: CGFloat { isExpanded ? 20 + contentHeight : 20 }
    private var contentHeight: CGFloat {
        if let info = content as? BmsONEInfoDockView { return info.preferredHeight }
        if let selected = content as? BmsONESelectedObjectsView { return selected.preferredHeight }
        return content.frame.height
    }

    init(title: String, content: NSView, onChange: @escaping () -> Void) {
        self.header = NSButton(title: NativeLocalization.text(title, fallback: title), target: nil, action: nil)
        NativeLocalization.markFixed(self.header, key: title)
        self.content = content
        self.onChange = onChange
        super.init(frame: .zero)
        header.setButtonType(.toggle)
        header.bezelStyle = .shadowlessSquare
        header.font = LegacyChromeFont.segoeBold
        header.target = self
        header.action = #selector(toggle)
        addSubview(header)
        addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 20)
        content.frame = NSRect(x: 0, y: 20, width: bounds.width, height: contentHeight)
        content.isHidden = !isExpanded
    }

    @objc private func toggle() {
        isExpanded = header.state == .on
        onChange()
    }
}

@MainActor
private final class OptionsSectionView: NSView {
    let section: OptionsSectionID
    let switchButton = NSButton()
    let part1 = FlippedSidebarDocumentView()
    let part2: FlippedSidebarDocumentView?
    let expanderButton: NSButton?
    var listHost: NSView?

    init(section: OptionsSectionID) {
        self.section = section
        if section.hasExpander {
            let expander = NSButton()
            expander.title = NativeLocalization.text("Expand...")
            NativeLocalization.markFixed(expander, key: "Expand...")
            expander.bezelStyle = .shadowlessSquare
            expander.setButtonType(.toggle)
            expander.font = LegacyChromeFont.segoe
            expander.alignment = .center
            self.expanderButton = expander
            self.part2 = FlippedSidebarDocumentView()
        } else {
            self.expanderButton = nil
            self.part2 = nil
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        switchButton.title = NativeLocalization.text(section.title)
        NativeLocalization.markFixed(switchButton, key: section.title)
        switchButton.setButtonType(.toggle)
        switchButton.bezelStyle = .shadowlessSquare
        switchButton.font = LegacyChromeFont.segoeBold
        switchButton.alignment = .center
        addSubview(switchButton)
        addSubview(part1)
        if let expanderButton { addSubview(expanderButton) }
        if let part2 { addSubview(part2) }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func apply(switchOn: Bool, part2Visible: Bool) {
        switchButton.frame = NSRect(x: 0, y: 0, width: MainWindowChrome.optionsDocumentWidth, height: MainWindowChrome.sectionSwitchHeight)
        var y = MainWindowChrome.sectionSwitchHeight
        part1.isHidden = !switchOn
        expanderButton?.isHidden = !switchOn
        part2?.isHidden = !switchOn || !part2Visible
        listHost?.isHidden = !switchOn
        guard switchOn else { return }
        part1.frame = NSRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: section.part1Height)
        y += section.part1Height
        if let expanderButton {
            expanderButton.frame = NSRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: MainWindowChrome.expanderHeight)
            y += MainWindowChrome.expanderHeight
        }
        if let part2, part2Visible {
            part2.frame = NSRect(x: 0, y: y, width: MainWindowChrome.optionsDocumentWidth, height: section.part2Height)
            y += section.part2Height
        }
        if let listHost {
            listHost.frame = NSRect(
                x: listHost.frame.minX,
                y: y,
                width: listHost.frame.width,
                height: section == .expansion ? MainWindowChrome.expansionBoxHeight : MainWindowChrome.listBoxHeight
            )
        }
    }
}

@MainActor
private final class ResourceDropTableView: NSTableView {
    var onDragExit: (() -> Void)?

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDragExit?()
    }
}

@MainActor
final class FlippedSidebarDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// 对照 Channel Info 总图：先画 320×160，再按 `setScaledContents` 拉到侧栏。
@MainActor
private final class BmsonOverallWaveformView: NSView {
    var payload = BmsonOverallWaveform.Payload.empty {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard !payload.columns.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let width = BmsonOverallWaveform.imageWidth
        let height = BmsonOverallWaveform.imageHeight
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: bounds.width / CGFloat(width), y: bounds.height / CGFloat(height))
        let bands = BmsonOverallWaveform.bands(stereo: payload.stereo, height: height)
        let drawn = min(width, payload.columns.count)
        let peak = NSColor(
            srgbRed: 0,
            green: CGFloat(0x99) / 255,
            blue: 0,
            alpha: 1
        )
        let rms = NSColor(
            srgbRed: CGFloat(0x66) / 255,
            green: CGFloat(0xCC) / 255,
            blue: CGFloat(0x66) / 255,
            alpha: 1
        )
        func stroke(_ color: NSColor, _ x: Int, _ y0: Int, _ y1: Int) {
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y0)))
            path.line(to: NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y1)))
            path.stroke()
        }
        func draw(_ color: NSColor, peak: Bool) {
            let divisor = payload.stereo ? 4 : 2
            for index in 0..<drawn {
                let column = payload.columns[index]
                let leftAmp = peak ? column.peakL : column.rmsL
                let left = BmsonOverallWaveform.line(
                    center: bands.left.center,
                    height: height,
                    divisor: divisor,
                    amplitude: leftAmp
                )
                stroke(color, index, left.y0, left.y1)
                if let rightBand = bands.right {
                    let rightAmp = peak ? column.peakR : column.rmsR
                    let right = BmsonOverallWaveform.line(
                        center: rightBand.center,
                        height: height,
                        divisor: divisor,
                        amplitude: rightAmp
                    )
                    stroke(color, index, right.y0, right.y1)
                }
            }
        }
        draw(peak, peak: true)
        draw(rms, peak: false)
        context.restoreGState()
    }
}
