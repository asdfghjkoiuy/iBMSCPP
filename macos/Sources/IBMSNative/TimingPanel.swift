import AppKit

struct TimingRational: Equatable, Hashable {
    let numerator: Int64
    let denominator: Int64

    var fractionText: String {
        "\(numerator)/\(denominator)"
    }
}

enum TimingEventKind: String, Equatable {
    case bpm
    case stop

    var displayName: String {
        switch self {
        case .bpm:
            return "BPM"
        case .stop:
            return "STOP"
        }
    }
}

struct TimingEventSnapshot: Equatable, Identifiable {
    let measure: Int
    let channel: String
    let token: String
    let fraction: TimingRational
    let beat: TimingRational
    let valueDecimal: String
    let kind: TimingEventKind
    let sourceLine: Int
    let hasTime: Bool
    let secondsBeforeStop: Double
    let secondsAfterStop: Double

    var id: EventID {
        EventID(
            sourceLine: sourceLine,
            measure: measure,
            channel: channel,
            fraction: fraction
        )
    }

    struct EventID: Equatable, Hashable {
        let sourceLine: Int
        let measure: Int
        let channel: String
        let fraction: TimingRational
    }

    var sourceDescription: String {
        "\(kind.displayName) \(channel)"
    }

    var timeBeforeStopText: String {
        guard hasTime else { return "—" }
        return Self.secondsFormatter.string(from: NSNumber(value: secondsBeforeStop)) ?? "—"
    }

    var timeAfterStopText: String {
        guard hasTime else { return "—" }
        return Self.secondsFormatter.string(from: NSNumber(value: secondsAfterStop)) ?? "—"
    }

    private static let secondsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }()
}

struct TimingMeasureSnapshot: Equatable {
    let measure: Int
    let ratioDecimal: String
}

struct TimingDiagnosticSnapshot: Equatable {
    let sourceLine: Int
    let message: String
}

struct TimingSnapshot: Equatable {
    let initialBPMDecimal: String
    let measures: [TimingMeasureSnapshot]
    let events: [TimingEventSnapshot]
    let diagnostics: [TimingDiagnosticSnapshot]
    let available: Bool
    let canEditInitialBPM: Bool
    let canEditTimeline: Bool
    let unavailableReason: String

    static let unavailable = TimingSnapshot(
        initialBPMDecimal: "120",
        measures: [],
        events: [],
        diagnostics: [],
        available: false,
        canEditInitialBPM: false,
        canEditTimeline: false,
        unavailableReason: "Timing data is unavailable for this document."
    )

    func ratio(for measure: Int) -> String? {
        measures.first(where: { $0.measure == measure })?.ratioDecimal
    }

    /// `#mmm02` ratio × 192, matching iBMSC `MeasureLength`.
    func measureLengths() -> [Int: Double] {
        LegacyMeasureGrid.lengths(from: measures)
    }

    /// `MeasureAtDisplacement` then a 192-slot index inside that measure.
    func grid(from vPosition: Double) -> (measure: Int, slot: Int, division: Int) {
        LegacyMeasureGrid.grid(from: vPosition, measureLengths: measureLengths())
    }
}

/// iBMSC `MeasureAtDisplacement` + `relativeMeasurePos / MeasureLength * 192`.
enum LegacyMeasureGrid {
    static let defaultLength = 192.0

    static func lengths(from measures: [TimingMeasureSnapshot]) -> [Int: Double] {
        var lengths: [Int: Double] = [:]
        for measure in measures {
            if let ratio = Double(measure.ratioDecimal) {
                lengths[measure.measure] = ratio * defaultLength
            }
        }
        return lengths
    }

    static func grid(
        from vPosition: Double,
        measureLengths: [Int: Double]
    ) -> (measure: Int, slot: Int, division: Int) {
        var bottom = 0.0
        for measure in 0...999 {
            let length = measureLengths[measure] ?? defaultLength
            let next = bottom + length
            if vPosition < next || measure == 999 {
                let slot = Int(((vPosition - bottom) / length * defaultLength).rounded(.toNearestOrEven))
                return (measure, min(191, max(0, slot)), 192)
            }
            bottom = next
        }
        return (0, 0, 192)
    }
}

@MainActor
final class TimingWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let initialBPMField = NSTextField(string: "120")
    private let measureField = NSTextField(string: "0")
    private let ratioField = NSTextField(string: "1")
    private let channelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let eventMeasureField = NSTextField(string: "0")
    private let fractionField = NSTextField(string: "0/1")
    private let valueField = NSTextField(string: "120")
    private let tableView = NSTableView()
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let initialApplyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let ratioApplyButton = NSButton(title: "Scale measure", target: nil, action: nil)
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace value", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete selected", target: nil, action: nil)
    private var snapshot = TimingSnapshot.unavailable
    private var selectedEventID: TimingEventSnapshot.EventID?
    private var displayedSessionID: ObjectIdentifier?
    private var initialBPMDraftDirty = false
    private var ratioDraftDirty = false
    private var eventDraftDirty = false

    var applyInitialBPM: ((String) -> String?)?
    var scaleMeasure: ((Int, String) -> String?)?
    var addEvent: ((Int, String, TimingRational, String) -> String?)?
    var replaceEvent: ((TimingEventSnapshot, String) -> String?)?
    var deleteEvent: ((TimingEventSnapshot) -> String?)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Timing"
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
        NativeLocalization.localize(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(snapshot: TimingSnapshot, sessionID: ObjectIdentifier?) {
        let sessionChanged = sessionID != displayedSessionID
        let priorSelection = selectedEventID
        self.snapshot = snapshot
        displayedSessionID = sessionID

        if sessionChanged {
            clearDrafts(for: snapshot)
        } else {
            if !initialBPMDraftDirty {
                initialBPMField.stringValue = snapshot.initialBPMDecimal
            }
            if !ratioDraftDirty,
               let measure = Self.measureNumber(from: measureField.stringValue),
               let ratio = snapshot.ratio(for: measure) {
                ratioField.stringValue = ratio
            }
        }
        selectedEventID = sessionChanged ? nil : priorSelection.flatMap { id in
            snapshot.events.contains(where: { $0.id == id }) ? id : nil
        }
        reloadTableSelection()
        updateControls()
        updateNotice()
    }

    private func clearDrafts(for snapshot: TimingSnapshot) {
        initialBPMField.stringValue = snapshot.initialBPMDecimal
        measureField.stringValue = "0"
        ratioField.stringValue = snapshot.ratio(for: 0) ?? "1"
        channelPopup.selectItem(at: 1)
        eventMeasureField.stringValue = "0"
        fractionField.stringValue = "0/1"
        valueField.stringValue = "120"
        initialBPMDraftDirty = false
        ratioDraftDirty = false
        eventDraftDirty = false
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let topControls = makeTopControls()
        let tableScroll = makeTableScrollView()
        let eventControls = makeEventControls()
        let footer = makeFooter()
        [topControls, tableScroll, eventControls, footer].forEach(root.addSubview)

        NSLayoutConstraint.activate([
            topControls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            topControls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            topControls.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            tableScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tableScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            tableScroll.topAnchor.constraint(equalTo: topControls.bottomAnchor, constant: 14),
            tableScroll.bottomAnchor.constraint(equalTo: eventControls.topAnchor, constant: -14),
            eventControls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            eventControls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            eventControls.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        return root
    }

    private func makeTopControls() -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8

        let heading = NSTextField(labelWithString: "Timing")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        container.addArrangedSubview(heading)

        let initialRow = formRow(label: "Initial BPM", field: initialBPMField, button: initialApplyButton)
        initialApplyButton.target = self
        initialApplyButton.action = #selector(applyInitialBPMValue(_:))
        initialBPMField.placeholderString = "120"
        initialBPMField.toolTip = "Enter an exact decimal BPM value."
        initialBPMField.delegate = self
        container.addArrangedSubview(initialRow)

        let measureRow = NSStackView()
        measureRow.orientation = .horizontal
        measureRow.alignment = .centerY
        measureRow.spacing = 8
        measureRow.addArrangedSubview(label("Measure", width: 76))
        measureField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        measureField.delegate = self
        measureField.toolTip = "Measures run from 0 through 999."
        measureRow.addArrangedSubview(measureField)
        measureRow.addArrangedSubview(label("Ratio", width: 42))
        ratioField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        ratioField.placeholderString = "1"
        ratioField.toolTip = "Enter an exact decimal measure ratio, where 1 is a four-beat measure."
        ratioField.delegate = self
        measureRow.addArrangedSubview(ratioField)
        ratioApplyButton.target = self
        ratioApplyButton.action = #selector(applyMeasureRatio(_:))
        measureRow.addArrangedSubview(ratioApplyButton)
        let scaleExplanation = NSTextField(wrappingLabelWithString: "Keeps event fractions; shifts later measures. Scale only.")
        scaleExplanation.textColor = .secondaryLabelColor
        scaleExplanation.font = .systemFont(ofSize: 11)
        scaleExplanation.preferredMaxLayoutWidth = 220
        measureRow.addArrangedSubview(scaleExplanation)
        container.addArrangedSubview(measureRow)
        return container
    }

    private func makeTableScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.delegate = self
        tableView.dataSource = self
        [
            column("Kind", identifier: "kind", width: 88),
            column("Measure", identifier: "measure", width: 72),
            column("Fraction", identifier: "fraction", width: 108),
            column("Value", identifier: "value", width: 110),
            column("Time before STOP", identifier: "before", width: 128),
            column("Time after STOP", identifier: "after", width: 122),
            column("Source", identifier: "source", width: 78)
        ].forEach(tableView.addTableColumn)
        scrollView.documentView = tableView
        return scrollView
    }

    private func makeEventControls() -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6

        let heading = NSTextField(labelWithString: "Timing event")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        container.addArrangedSubview(heading)

        let fields = NSStackView()
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 6
        let coordinateRow = NSStackView()
        coordinateRow.orientation = .horizontal
        coordinateRow.alignment = .centerY
        coordinateRow.spacing = 8
        let valueRow = NSStackView()
        valueRow.orientation = .horizontal
        valueRow.alignment = .centerY
        valueRow.spacing = 8
        addChannel(title: "BPM — integer (03)", channel: "03")
        addChannel(title: "BPM — decimal (08)", channel: "08")
        addChannel(title: "STOP (09)", channel: "09")
        channelPopup.selectItem(at: 1)
        channelPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        channelPopup.toolTip = "03 accepts integer BPM values from 1 through 255. 08 accepts positive exact decimal BPM values."
        eventMeasureField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        eventMeasureField.placeholderString = "0"
        eventMeasureField.delegate = self
        fractionField.widthAnchor.constraint(equalToConstant: 118).isActive = true
        fractionField.placeholderString = "0/1"
        fractionField.toolTip = "Exact measure fraction: numerator/denominator."
        fractionField.delegate = self
        valueField.widthAnchor.constraint(equalToConstant: 132).isActive = true
        valueField.placeholderString = "Exact decimal value"
        valueField.toolTip = "Enter an exact decimal. STOP values use 48 units per quarter beat."
        valueField.delegate = self
        coordinateRow.addArrangedSubview(label("Kind", width: 54))
        coordinateRow.addArrangedSubview(channelPopup)
        coordinateRow.addArrangedSubview(label("Measure", width: 58))
        coordinateRow.addArrangedSubview(eventMeasureField)
        coordinateRow.addArrangedSubview(label("Fraction", width: 60))
        coordinateRow.addArrangedSubview(fractionField)
        valueRow.addArrangedSubview(label("Value", width: 54))
        valueRow.addArrangedSubview(valueField)
        fields.addArrangedSubview(coordinateRow)
        fields.addArrangedSubview(valueRow)
        container.addArrangedSubview(fields)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        addButton.target = self
        addButton.action = #selector(addTimingEvent(_:))
        replaceButton.target = self
        replaceButton.action = #selector(replaceTimingEvent(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteTimingEvent(_:))
        actions.addArrangedSubview(addButton)
        actions.addArrangedSubview(replaceButton)
        actions.addArrangedSubview(deleteButton)
        let stopUnits = NSTextField(wrappingLabelWithString: "STOP units: 48 = one quarter beat. Replace updates the selected event’s exact value.")
        stopUnits.font = .systemFont(ofSize: 11)
        stopUnits.textColor = .secondaryLabelColor
        actions.addArrangedSubview(stopUnits)
        container.addArrangedSubview(actions)
        return container
    }

    private func makeFooter() -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        noticeLabel.textColor = .secondaryLabelColor
        noticeLabel.font = .systemFont(ofSize: 11)
        noticeLabel.maximumNumberOfLines = 2
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.maximumNumberOfLines = 3
        container.addArrangedSubview(noticeLabel)
        container.addArrangedSubview(detailLabel)
        return container
    }

    private func formRow(label title: String, field: NSTextField, button: NSButton) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(label(title, width: 76))
        field.widthAnchor.constraint(equalToConstant: 160).isActive = true
        row.addArrangedSubview(field)
        row.addArrangedSubview(button)
        return row
    }

    private func label(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func column(_ title: String, identifier: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = width
        return column
    }

    private func selectedEvent() -> TimingEventSnapshot? {
        guard let selectedEventID else { return nil }
        return snapshot.events.first(where: { $0.id == selectedEventID })
    }

    private func reloadTableSelection() {
        tableView.reloadData()
        guard let selectedEventID,
              let row = snapshot.events.firstIndex(where: { $0.id == selectedEventID }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func updateControls() {
        let canEditInitialBPM = snapshot.canEditInitialBPM && applyInitialBPM != nil
        let canEditTimeline = snapshot.canEditTimeline
        let hasSelection = selectedEvent() != nil
        initialBPMField.isEnabled = canEditInitialBPM
        initialApplyButton.isEnabled = canEditInitialBPM
        [measureField, ratioField, channelPopup, eventMeasureField, fractionField, valueField].forEach {
            $0.isEnabled = canEditTimeline
        }
        ratioApplyButton.isEnabled = canEditTimeline && scaleMeasure != nil
        addButton.isEnabled = canEditTimeline && addEvent != nil
        replaceButton.isEnabled = canEditTimeline && hasSelection && replaceEvent != nil
        deleteButton.isEnabled = canEditTimeline && hasSelection && deleteEvent != nil
    }

    private func updateNotice() {
        if snapshot.available {
            noticeLabel.stringValue = NativeLocalization.text(
                "Times are supplied by the chart timing map. They are not playback controls."
            )
        } else {
            noticeLabel.stringValue = snapshot.unavailableReason
        }
        let details = snapshot.diagnostics.map { diagnostic in
            NativeLocalization.format("Line %d: %@", diagnostic.sourceLine + 1, diagnostic.message)
        }
        detailLabel.stringValue = details.joined(separator: "\n")
        detailLabel.toolTip = details.isEmpty ? nil : details.joined(separator: "\n")
    }

    private func presentResult(_ result: String?) {
        guard let result else { return }
        noticeLabel.stringValue = NativeLocalization.text(result)
    }

    @objc private func applyInitialBPMValue(_ sender: Any?) {
        let result = applyInitialBPM?(initialBPMField.stringValue)
        if result == nil {
            initialBPMDraftDirty = false
        }
        presentResult(result)
    }

    @objc private func applyMeasureRatio(_ sender: Any?) {
        guard let measure = Self.measureNumber(from: measureField.stringValue) else {
            presentResult("Measure must be an integer from 0 through 999.")
            return
        }
        let result = scaleMeasure?(measure, ratioField.stringValue)
        if result == nil {
            ratioDraftDirty = false
        }
        presentResult(result)
    }

    @objc private func addTimingEvent(_ sender: Any?) {
        guard let coordinate = eventCoordinate() else { return }
        let result = addEvent?(coordinate.measure, coordinate.channel, coordinate.fraction, valueField.stringValue)
        if result == nil {
            eventDraftDirty = false
        }
        presentResult(result)
    }

    @objc private func replaceTimingEvent(_ sender: Any?) {
        guard let event = selectedEvent() else {
            presentResult("Select a timing event to replace its value.")
            return
        }
        let result = replaceEvent?(event, valueField.stringValue)
        if result == nil {
            eventDraftDirty = false
        }
        presentResult(result)
    }

    @objc private func deleteTimingEvent(_ sender: Any?) {
        guard let event = selectedEvent() else {
            presentResult("Select a timing event to delete.")
            return
        }
        presentResult(deleteEvent?(event))
    }

    private func eventCoordinate() -> (measure: Int, channel: String, fraction: TimingRational)? {
        guard let measure = Self.measureNumber(from: eventMeasureField.stringValue) else {
            presentResult("Measure must be an integer from 0 through 999.")
            return nil
        }
        guard let fraction = Self.fraction(from: fractionField.stringValue) else {
            presentResult("Fraction must be an exact numerator/denominator value in the measure.")
            return nil
        }
        return (measure, selectedChannel ?? "08", fraction)
    }

    private static func measureNumber(from value: String) -> Int? {
        guard let measure = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), (0...999).contains(measure) else {
            return nil
        }
        return measure
    }

    private static func fraction(from value: String) -> TimingRational? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let numerator = Int64(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let denominator = Int64(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              denominator > 0,
              numerator >= 0,
              numerator < denominator else {
            return nil
        }
        return TimingRational(numerator: numerator, denominator: denominator)
    }

    private var selectedChannel: String? {
        channelPopup.selectedItem?.representedObject as? String
    }

    private func addChannel(title: String, channel: String) {
        channelPopup.addItem(withTitle: title)
        channelPopup.lastItem?.representedObject = channel
    }

    private func selectChannel(_ channel: String) {
        guard let item = channelPopup.itemArray.first(where: {
            ($0.representedObject as? String) == channel
        }) else {
            return
        }
        channelPopup.select(item)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        snapshot.events.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let event = snapshot.events[row]
        let identifier = tableColumn.identifier
        let text: String
        switch identifier.rawValue {
        case "kind": text = event.sourceDescription
        case "measure": text = String(format: "%03d", event.measure)
        case "fraction": text = event.fraction.fractionText
        case "value": text = event.valueDecimal
        case "before": text = event.timeBeforeStopText
        case "after": text = event.timeAfterStopText
        case "source": text = "Line \(event.sourceLine + 1)"
        default: return nil
        }
        let cellIdentifier = NSUserInterfaceItemIdentifier("TimingCell.\(identifier.rawValue)")
        let view: NSTableCellView
        if let reusable = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            view = reusable
        } else {
            view = NSTableCellView()
            view.identifier = cellIdentifier
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            view.addSubview(label)
            view.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
        view.textField?.stringValue = text
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard snapshot.events.indices.contains(row) else {
            selectedEventID = nil
            updateControls()
            return
        }
        let event = snapshot.events[row]
        selectedEventID = event.id
        selectChannel(event.channel)
        eventMeasureField.stringValue = String(event.measure)
        fractionField.stringValue = event.fraction.fractionText
        valueField.stringValue = event.valueDecimal
        eventDraftDirty = false
        updateControls()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === initialBPMField {
            initialBPMDraftDirty = true
        } else if field === ratioField {
            ratioDraftDirty = true
        } else if field === eventMeasureField || field === fractionField || field === valueField {
            eventDraftDirty = true
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === measureField,
              !ratioDraftDirty,
              let measure = Self.measureNumber(from: measureField.stringValue),
              let ratio = snapshot.ratio(for: measure) else {
            return
        }
        ratioField.stringValue = ratio
    }
}
