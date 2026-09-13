import Foundation

enum MetadataEncoding: String, CaseIterable {
    case utf8 = "UTF-8"
    case shiftJIS = "Shift JIS"
    case eucKR = "EUC-KR"

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8:
            return .utf8
        case .shiftJIS:
            return .shiftJIS
        case .eucKR:
            return String.Encoding(rawValue: IBMSNSStringEncodingEucKR())
        }
    }
}

enum DocumentSessionError: LocalizedError {
    case bridge(NSError)
    case unsupportedMetadataEncoding
    case conditionalDocument
    case encodingChangeWithHistory

    var errorDescription: String? {
        switch self {
        case .bridge(let error):
            return error.localizedDescription
        case .unsupportedMetadataEncoding:
            return "The selected encoding cannot represent this metadata without changing its bytes."
        case .conditionalDocument:
            return "Metadata editing is unavailable for documents with conditional branches."
        case .encodingChangeWithHistory:
            return "Choose the encoding before editing metadata, or save and reopen the document before changing it."
        }
    }
}

@MainActor
final class DocumentSession {
    static let editableKeys = [
        "TITLE", "SUBTITLE", "ARTIST", "SUBARTIST", "GENRE",
        "PLAYER", "RANK", "PLAYLEVEL", "STAGEFILE", "BANNER", "BACKBMP",
        "DIFFICULTY", "EXRANK", "TOTAL", "COMMENT", "LNOBJ",
    ]

    /// Header 侧栏的 ExRank 对应原版写出的 `#DEFEXRANK`。
    static func storageKey(_ key: String) -> String {
        key == "EXRANK" ? "DEFEXRANK" : key
    }

    private let bridge: IBMSDocumentBridge
    private let sourceHasUTF8BOM: Bool
    private let documentHasConditionals: Bool
    private let supportedMetadataEncodings: [MetadataEncoding]
    private(set) var fileURL: URL?
    private(set) var metadataEncoding: MetadataEncoding?
    private(set) var chartSnapshot: ChartSnapshot
    private(set) var longNoteSnapshot: LongNoteSnapshotSet
    private(set) var timingSnapshot: TimingSnapshot

    init(data: Data, fileURL: URL? = nil) throws {
        let bridge = try IBMSDocumentBridge(data: data)
        self.bridge = bridge
        self.fileURL = fileURL
        sourceHasUTF8BOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        documentHasConditionals = try bridge.conditionalState().boolValue
        let candidates: [MetadataEncoding] = sourceHasUTF8BOM ? [.utf8] : MetadataEncoding.allCases
        supportedMetadataEncodings = try Self.supportedEncodings(
            bridge: bridge,
            sourceBytes: data,
            candidates: candidates
        )
        metadataEncoding = supportedMetadataEncodings.first
        chartSnapshot = try Self.chartSnapshot(from: bridge)
        longNoteSnapshot = try Self.longNoteSnapshot(from: bridge)
        timingSnapshot = try Self.timingSnapshot(
            from: bridge,
            chartEditable: chartSnapshot.editable,
            canEditInitialBPM: !documentHasConditionals
        )
    }

    var dirty: Bool { bridge.isDirty() }
    var canUndo: Bool { bridge.canUndo() }
    var canRedo: Bool { bridge.canRedo() }

    func discardHistory() {
        bridge.discardHistory()
    }

    func withCompound(_ body: () throws -> Void) throws {
        let beforeChart = chartSnapshot
        let beforeLong = longNoteSnapshot
        let beforeTiming = timingSnapshot
        try bridge.beginCompound()
        do {
            try body()
            try bridge.endCompound()
        } catch {
            bridge.abortCompound()
            // Abort restores bridge bytes; restore the already validated Swift snapshots too.
            chartSnapshot = beforeChart
            longNoteSnapshot = beforeLong
            timingSnapshot = beforeTiming
            throw error
        }
    }

    /// `TimeSelectionOps` / `MyO2`: `RedoRemoveNoteAll` then write notes, one `AddUndo`.
    /// Headers, WAV / BMP, expansion, and `#mmm02` stay on this document.
    func rewriteChart(_ insert: () throws -> Void) throws {
        try withCompound {
            let longs = longNoteSnapshot.notes
            for note in longs {
                try eraseLongNote(note)
            }
            let events = chartSnapshot.events.filter { $0.kind != "long_note" }
            for event in events {
                try eraseNote(event)
            }
            try insert()
        }
    }

    var hasConditionals: Bool { documentHasConditionals }
    var lineCount: Int { Int(bridge.lineCount()) }

    var availableEncodings: [MetadataEncoding] {
        supportedMetadataEncodings
    }

    var metadataEditingMessage: String? {
        if hasConditionals {
            return "Conditional documents retain their raw bytes and can be saved or copied, but metadata editing is temporarily read-only."
        }
        if metadataEncoding == nil {
            return "Metadata bytes do not round-trip with the available encodings. Editing is unavailable."
        }
        return nil
    }

    var canEditMetadata: Bool {
        !hasConditionals && metadataEncoding != nil
    }

    var encodingSelectionIsAmbiguous: Bool {
        availableEncodings.count > 1
    }

    func selectMetadataEncoding(_ encoding: MetadataEncoding) throws {
        guard !canUndo && !canRedo else {
            throw DocumentSessionError.encodingChangeWithHistory
        }
        guard availableEncodings.contains(encoding) else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        guard try currentBytesRoundTrip(using: encoding) else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        metadataEncoding = encoding
    }

    func metadataValue(for key: String) throws -> String {
        let data = try headerData(for: key)
        if data.isEmpty {
            return ""
        }
        guard let encoding = metadataEncoding,
              let value = String(data: data, encoding: encoding.stringEncoding),
              let encoded = value.data(using: encoding.stringEncoding, allowLossyConversion: false),
              encoded == data else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        return value
    }

    func replaceMetadata(_ value: String, for key: String) throws -> String {
        guard Self.editableKeys.contains(key) else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        guard canEditMetadata, let encoding = metadataEncoding else {
            throw hasConditionals ? DocumentSessionError.conditionalDocument : DocumentSessionError.unsupportedMetadataEncoding
        }
        let canonicalValue = trimASCIIWhitespace(value)
        guard let data = canonicalValue.data(using: encoding.stringEncoding, allowLossyConversion: false),
              String(data: data, encoding: encoding.stringEncoding) == canonicalValue else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }

        try bridge.setHeaderData(data, forKey: Self.storageKey(key))
        try refreshChartSnapshot()
        return try metadataValue(for: key)
    }

    @discardableResult
    func undo() throws -> Bool {
        guard canUndo else { return false }
        try bridge.undo()
        try refreshChartSnapshot()
        return true
    }

    @discardableResult
    func redo() throws -> Bool {
        guard canRedo else { return false }
        try bridge.redo()
        try refreshChartSnapshot()
        return true
    }

    /// The current document bytes, including unsaved edits.
    func currentBytes() throws -> Data {
        try bridge.serializedData()
    }

    struct SaveBmsReport: Equatable {
        var overlapping: Bool
        var bpmCount: Int
        var stopCount: Int
        var scrollCount: Int
    }

    @discardableResult
    func save(to url: URL, ntInput: Bool = true, gridLimit: Double = 1.0) throws -> SaveBmsReport {
        let report = try bridge.saveBmsReport(ntInput: ntInput, gridLimit: gridLimit)
        try report.data.write(to: url, options: .atomic)
        bridge.markSaved()
        fileURL = url
        return SaveBmsReport(
            overlapping: report.overlapping,
            bpmCount: report.bpmCount,
            stopCount: report.stopCount,
            scrollCount: report.scrollCount
        )
    }

    /// `save_bms()` bytes for a sidecar file. Does not mark the session saved.
    func exportSaveBmsData(ntInput: Bool = true, gridLimit: Double = 1.0) throws -> Data {
        try bridge.saveBmsReport(ntInput: ntInput, gridLimit: gridLimit).data
    }

    private static func supportedEncodings(
        bridge: IBMSDocumentBridge,
        sourceBytes: Data,
        candidates: [MetadataEncoding]
    ) throws -> [MetadataEncoding] {
        var supported: [MetadataEncoding] = []
        for encoding in candidates {
            guard Self.encodingRoundTrips(sourceBytes, using: encoding) else {
                continue
            }
            if try supportsMetadata(bridge: bridge, encoding: encoding) {
                supported.append(encoding)
            }
        }
        return supported
    }

    private static func supportsMetadata(bridge: IBMSDocumentBridge, encoding: MetadataEncoding) throws -> Bool {
        for key in Self.editableKeys {
            var error: NSError?
            let data = bridge.headerData(forKey: storageKey(key), error: &error)
            if let error { throw DocumentSessionError.bridge(error) }
            if data.isEmpty { continue }
            guard let value = String(data: data, encoding: encoding.stringEncoding),
                  let encoded = value.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
                return false
            }
            if encoded != data { return false }
        }
        return true
    }

    private func headerData(for key: String) throws -> Data {
        var error: NSError?
        let value = bridge.headerData(forKey: Self.storageKey(key), error: &error)
        if let error { throw DocumentSessionError.bridge(error) }
        return value
    }

    private func currentBytesRoundTrip(using encoding: MetadataEncoding) throws -> Bool {
        let data = try bridge.serializedData()
        return Self.encodingRoundTrips(data, using: encoding)
    }

    func insertNote(measure: Int, channel: String, gridSlot: Int, gridDivision: Int, token: String) throws {
        try bridge.insertNote(atMeasure: measure, channel: channel, gridSlot: gridSlot, gridDivision: gridDivision, token: token)
        try refreshChartSnapshot()
    }

    /// Time selection / MyO2 writeback: `MeasureAtDisplacement` with `#mmm02`.
    func insertNote(
        atVPosition vPosition: Double,
        channel: String,
        token: String,
        measureLengths: [Int: Double]
    ) throws {
        let grid = LegacyMeasureGrid.grid(from: vPosition, measureLengths: measureLengths)
        try insertNote(
            measure: grid.measure,
            channel: channel,
            fractionNumerator: Int64(grid.slot),
            fractionDenominator: Int64(grid.division),
            token: token
        )
    }

    func eraseNote(_ event: ChartEventSnapshot) throws {
        if ["03", "08", "09", "SC"].contains(event.channel) {
            try bridge.eraseTimingEvent(
                atMeasure: event.measure,
                channel: event.channel,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator
            )
        } else {
            try bridge.eraseNote(
                atMeasure: event.measure,
                channel: event.channel,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator
            )
        }
        try refreshChartSnapshot()
    }

    func moveNote(_ event: ChartEventSnapshot, toMeasure measure: Int, channel: String, gridSlot: Int, gridDivision: Int) throws {
        try bridge.moveNote(
            atMeasure: event.measure,
            channel: event.channel,
            fractionNumerator: event.fractionNumerator,
            fractionDenominator: event.fractionDenominator,
            toMeasure: measure,
            channel: channel,
            gridSlot: gridSlot,
            gridDivision: gridDivision
        )
        try refreshChartSnapshot()
    }

    func moveNote(_ event: ChartEventSnapshot, toChannel channel: String) throws {
        try bridge.moveNote(
            atMeasure: event.measure,
            channel: event.channel,
            fractionNumerator: event.fractionNumerator,
            fractionDenominator: event.fractionDenominator,
            toMeasure: event.measure,
            channel: channel,
            fractionNumerator: event.fractionNumerator,
            fractionDenominator: event.fractionDenominator
        )
        try refreshChartSnapshot()
    }

    /// 选择模式拖动：已选短音和长音一次搬，一笔撤销。
    func moveNotesAtVPosition(
        shorts: [ChartDuplicate.ShortCopy],
        longs: [ChartDuplicate.LongCopy]
    ) throws {
        guard !shorts.isEmpty || !longs.isEmpty else { return }
        try withCompound {
            let lengths = timingSnapshot.measureLengths()
            for copy in shorts {
                try moveNote(
                    copy.event,
                    toChannel: copy.channel,
                    vPosition: copy.vPosition,
                    measureLengths: lengths
                )
            }
            for copy in longs {
                let grid = LegacyMeasureGrid.grid(from: copy.vPosition, measureLengths: lengths)
                try moveLongNote(
                    copy.note,
                    toMeasure: grid.measure,
                    channel: copy.channel,
                    gridSlot: grid.slot,
                    gridDivision: grid.division
                )
            }
        }
    }

    func moveNote(
        _ event: ChartEventSnapshot,
        toChannel channel: String,
        vPosition: Double,
        measureLengths: [Int: Double]
    ) throws {
        let grid = LegacyMeasureGrid.grid(from: vPosition, measureLengths: measureLengths)
        try bridge.moveNote(
            atMeasure: event.measure,
            channel: event.channel,
            fractionNumerator: event.fractionNumerator,
            fractionDenominator: event.fractionDenominator,
            toMeasure: grid.measure,
            channel: channel,
            fractionNumerator: Int64(grid.slot),
            fractionDenominator: Int64(grid.division)
        )
        try refreshChartSnapshot()
    }

    func insertLongNote(
        channel: String,
        startMeasure: Int,
        startSlot: Int,
        endMeasure: Int,
        endSlot: Int,
        gridDivision: Int,
        token: String,
        endToken: String
    ) throws {
        try bridge.insertLongNote(
            onChannel: channel,
            startMeasure: startMeasure,
            startGridSlot: startSlot,
            startGridDivision: gridDivision,
            endMeasure: endMeasure,
            endGridSlot: endSlot,
            endGridDivision: gridDivision,
            startToken: token,
            endToken: endToken
        )
        try refreshChartSnapshot()
    }

    func insertLongNote(
        fromVPosition start: Double,
        length: Double,
        channel: String,
        token: String,
        measureLengths: [Int: Double]
    ) throws {
        let startGrid = LegacyMeasureGrid.grid(from: start, measureLengths: measureLengths)
        let endGrid = LegacyMeasureGrid.grid(from: start + length, measureLengths: measureLengths)
        try insertLongNote(
            channel: channel,
            startMeasure: startGrid.measure,
            startNumerator: Int64(startGrid.slot),
            startDenominator: Int64(startGrid.division),
            endMeasure: endGrid.measure,
            endNumerator: Int64(endGrid.slot),
            endDenominator: Int64(endGrid.division),
            startToken: token,
            endToken: token
        )
    }

    func insertLongNote(
        channel: String,
        startMeasure: Int,
        startNumerator: Int64,
        startDenominator: Int64,
        endMeasure: Int,
        endNumerator: Int64,
        endDenominator: Int64,
        startToken: String,
        endToken: String
    ) throws {
        try bridge.insertLongNote(
            onChannel: channel,
            startMeasure: startMeasure,
            startNumerator: startNumerator,
            startDenominator: startDenominator,
            endMeasure: endMeasure,
            endNumerator: endNumerator,
            endDenominator: endDenominator,
            startToken: startToken,
            endToken: endToken
        )
        try refreshChartSnapshot()
    }

    func moveLongNote(
        _ note: LongNoteSnapshot,
        toMeasure measure: Int,
        channel: String,
        gridSlot: Int,
        gridDivision: Int
    ) throws {
        try bridge.moveLongNote(
            onChannel: note.channel,
            startMeasure: note.start.measure,
            startNumerator: note.start.fractionNumerator,
            startDenominator: note.start.fractionDenominator,
            destinationChannel: channel,
            destinationStartMeasure: measure,
            destinationStartGridSlot: gridSlot,
            destinationStartGridDivision: gridDivision
        )
        try refreshChartSnapshot()
    }

    func moveLongNoteStart(
        _ note: LongNoteSnapshot,
        toMeasure measure: Int,
        gridSlot: Int,
        gridDivision: Int
    ) throws {
        try bridge.moveLongNoteStart(
            onChannel: note.channel,
            startMeasure: note.start.measure,
            startNumerator: note.start.fractionNumerator,
            startDenominator: note.start.fractionDenominator,
            destinationStartMeasure: measure,
            destinationStartGridSlot: gridSlot,
            destinationStartGridDivision: gridDivision
        )
        try refreshChartSnapshot()
    }

    func resizeLongNote(
        _ note: LongNoteSnapshot,
        endMeasure: Int,
        endSlot: Int,
        gridDivision: Int
    ) throws {
        try bridge.resizeLongNote(
            onChannel: note.channel,
            startMeasure: note.start.measure,
            startNumerator: note.start.fractionNumerator,
            startDenominator: note.start.fractionDenominator,
            endMeasure: endMeasure,
            endGridSlot: endSlot,
            endGridDivision: gridDivision
        )
        try refreshChartSnapshot()
    }

    func eraseLongNote(_ note: LongNoteSnapshot) throws {
        try bridge.eraseLongNote(
            onChannel: note.channel,
            startMeasure: note.start.measure,
            startNumerator: note.start.fractionNumerator,
            startDenominator: note.start.fractionDenominator
        )
        try refreshChartSnapshot()
    }

    func insertNote(
        measure: Int,
        channel: String,
        fractionNumerator: Int64,
        fractionDenominator: Int64,
        token: String
    ) throws {
        try bridge.insertNote(
            atMeasure: measure,
            channel: channel,
            fractionNumerator: fractionNumerator,
            fractionDenominator: fractionDenominator,
            token: token
        )
        try refreshChartSnapshot()
    }

    /// NT `POBShort` sets `Length = 0` (keep start). BMSE keeps both endpoints as short notes.
    func convertLongNoteToShort(_ note: LongNoteSnapshot, keepEnd: Bool) throws {
        let channel = ChartConvert.shortChannel(for: note.channel)
        let start = note.start
        let end = note.end
        try eraseLongNote(note)
        try insertNote(
            measure: start.measure,
            channel: channel,
            fractionNumerator: start.fractionNumerator,
            fractionDenominator: start.fractionDenominator,
            token: start.token
        )
        if keepEnd {
            try insertNote(
                measure: end.measure,
                channel: channel,
                fractionNumerator: end.fractionNumerator,
                fractionDenominator: end.fractionDenominator,
                token: end.token
            )
        }
    }

    /// BMSE `POBLong`：单颗配不成对的短音写成 `5x` / `6x`。
    func convertShortNoteToLongEndpoint(_ event: ChartEventSnapshot) throws {
        guard let channel = ChartConvert.longChannel(for: event.channel),
              !ChartConvert.isLongChannel(event.channel) else {
            return
        }
        try withCompound {
            try eraseNote(event)
            try insertNote(
                measure: event.measure,
                channel: channel,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator,
                token: event.token
            )
        }
    }

    /// BMSE `POBShort`：把不成对的 `5x` / `6x` 写回可见短音通道。
    func convertLongEndpointToShort(_ event: ChartEventSnapshot) throws {
        guard ChartConvert.isLongChannel(event.channel) else { return }
        let channel = ChartConvert.shortChannel(for: event.channel)
        try withCompound {
            try eraseNote(event)
            try insertNote(
                measure: event.measure,
                channel: channel,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator,
                token: event.token
            )
        }
    }

    /// BMSE `POBLong`：把同一列上的两颗短音写成一对 `5x` / `6x`。
    func convertShortNotesToLong(start: ChartEventSnapshot, end: ChartEventSnapshot) throws {
        guard let pair = ChartConvert.longNotePairs(from: [start, end]).first,
              let channel = ChartConvert.longChannel(for: pair.0.channel) else {
            return
        }
        try eraseNote(pair.0)
        try eraseNote(pair.1)
        try insertLongNote(
            channel: channel,
            startMeasure: pair.0.measure,
            startNumerator: pair.0.fractionNumerator,
            startDenominator: pair.0.fractionDenominator,
            endMeasure: pair.1.measure,
            endNumerator: pair.1.fractionNumerator,
            endDenominator: pair.1.fractionDenominator,
            startToken: pair.0.token,
            endToken: pair.1.token
        )
    }

    func copyNote(
        _ event: ChartEventSnapshot,
        toMeasure measure: Int,
        channel: String,
        gridSlot: Int,
        gridDivision: Int
    ) throws {
        try insertNote(
            measure: measure,
            channel: channel,
            gridSlot: gridSlot,
            gridDivision: gridDivision,
            token: event.token
        )
    }

    func copyNote(_ event: ChartEventSnapshot, toChannel channel: String, vPosition: Double) throws {
        let dest = channel.uppercased()
        let lengths = timingSnapshot.measureLengths()
        if ChartConvert.isNumericChannel(dest) {
            let decimal = LegacyClipboard.decimal(fromValue: clipboardValue(for: event))
            if dest == "03" || dest == "08" {
                guard let routed = ChartTiming.bpmWriteChannel(decimal),
                      let stored = ChartTiming.storedBpmDecimal(decimal) else { return }
                try insertTimingEvent(
                    atVPosition: vPosition,
                    channel: routed,
                    decimal: stored,
                    measureLengths: lengths
                )
            } else {
                try insertTimingEvent(
                    atVPosition: vPosition,
                    channel: dest,
                    decimal: decimal,
                    measureLengths: lengths
                )
            }
            return
        }
        let token = ChartConvert.isNumericChannel(event.channel)
            ? LegacyClipboard.token(fromValue: clipboardValue(for: event))
            : event.token
        try insertNote(
            atVPosition: vPosition,
            channel: dest,
            token: token,
            measureLengths: lengths
        )
    }

    func copyLongNote(
        _ note: LongNoteSnapshot,
        toChannel channel: String,
        vPosition: Double,
        length: Double
    ) throws {
        let start = LegacyClipboard.location(vPosition: vPosition)
        let end = LegacyClipboard.location(vPosition: vPosition + length)
        try insertLongNote(
            channel: channel,
            startMeasure: start.measure,
            startNumerator: start.numerator,
            startDenominator: start.denominator,
            endMeasure: end.measure,
            endNumerator: end.numerator,
            endDenominator: end.denominator,
            startToken: note.start.token,
            endToken: note.end.token
        )
    }

    func copyClipboard(events: [ChartEventSnapshot], longNotes: [LongNoteSnapshot], ntInput: Bool) -> String {
        LegacyClipboard.encode(clipboardNotes(events: events, longNotes: longNotes, ntInput: ntInput), ntInput: ntInput)
    }

    func cutClipboard(events: [ChartEventSnapshot], longNotes: [LongNoteSnapshot], ntInput: Bool) throws -> String {
        let text = copyClipboard(events: events, longNotes: longNotes, ntInput: ntInput)
        for note in longNotes {
            try eraseLongNote(note)
        }
        for event in events {
            try eraseNote(event)
        }
        return text
    }

    func pasteClipboard(_ text: String, baseVPosition: Double, ntInput: Bool) throws {
        guard let payload = LegacyClipboard.decode(text) else { return }
        var notes = payload.notes
        if ntInput && payload.format != .ibmscNT {
            notes = LegacyClipboard.convertBMSE2NT(notes, lnobj: currentLnobjIndex())
        } else if !ntInput && payload.format == .ibmscNT {
            notes = LegacyClipboard.convertNT2BMSE(notes)
        }
        let maxVPosition = 1000 * 192.0
        try insertConvertedNTNotes(
            LegacyClipboard.placed(notes, baseVPosition: baseVPosition).filter {
                $0.vPosition >= 0 && $0.vPosition < maxVPosition
            },
            ntInput: ntInput
        )
    }

    /// `TBNTInput_Click`：先收整谱，再 `ConvertBMSE2NT` / `ConvertNT2BMSE`，一笔撤销。
    /// IBMSC 导入只改界面旗，不要走这里。
    func convertNTInput(becomeNT: Bool, lnobj: Int? = nil) throws {
        let marker = lnobj ?? currentLnobjIndex()
        let longs = longNoteSnapshot.notes
        let events = chartSnapshot.events.filter { event in
            !Self.isLongEndpoint(event, longs: longs)
        }
        let source = clipboardNotes(
            events: events,
            longNotes: longs,
            ntInput: !becomeNT,
            markLongPairs: true
        )
        let converted = becomeNT
            ? LegacyNTConvert.convertBMSE2NT(source, lnobj: marker)
            : LegacyNTConvert.convertNT2BMSE(source)
        try rewriteChart {
            try insertConvertedNTNotes(converted, ntInput: becomeNT, originals: longs)
        }
    }

    private func currentLnobjIndex() -> Int {
        LegacyClipboard.tokenValue(longNoteSnapshot.lnobjToken) / 10_000
    }

    private static func isLongEndpoint(_ event: ChartEventSnapshot, longs: [LongNoteSnapshot]) -> Bool {
        longs.contains { pair in
            sameLongEndpoint(event, pair.start, channel: pair.channel)
                || sameLongEndpoint(event, pair.end, channel: pair.channel)
        }
    }

    private static func sameLongEndpoint(
        _ event: ChartEventSnapshot,
        _ endpoint: LongNoteEndpointSnapshot,
        channel: String
    ) -> Bool {
        event.channel.caseInsensitiveCompare(channel) == .orderedSame
            && event.measure == endpoint.measure
            && event.fractionNumerator == endpoint.fractionNumerator
            && event.fractionDenominator == endpoint.fractionDenominator
    }

    private func clipboardNotes(
        events: [ChartEventSnapshot],
        longNotes: [LongNoteSnapshot],
        ntInput: Bool,
        markLongPairs: Bool = false
    ) -> [LegacyClipboardNote] {
        var notes = events.map { event in
            var note = LegacyClipboard.note(
                channel: event.channel,
                measure: event.measure,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator,
                token: event.token
            )
            note.value = clipboardValue(for: event)
            return note
        }
        for pair in longNotes {
            let start = LegacyClipboard.vPosition(
                measure: pair.start.measure,
                fractionNumerator: pair.start.fractionNumerator,
                fractionDenominator: pair.start.fractionDenominator
            )
            let end = LegacyClipboard.vPosition(
                measure: pair.end.measure,
                fractionNumerator: pair.end.fractionNumerator,
                fractionDenominator: pair.end.fractionDenominator
            )
            if ntInput {
                notes.append(
                    LegacyClipboard.note(
                        channel: pair.channel,
                        measure: pair.start.measure,
                        fractionNumerator: pair.start.fractionNumerator,
                        fractionDenominator: pair.start.fractionDenominator,
                        token: pair.start.token,
                        length: end - start
                    )
                )
            } else {
                var startNote = LegacyClipboard.note(
                    channel: pair.channel,
                    measure: pair.start.measure,
                    fractionNumerator: pair.start.fractionNumerator,
                    fractionDenominator: pair.start.fractionDenominator,
                    token: pair.start.token
                )
                var endNote = LegacyClipboard.note(
                    channel: pair.channel,
                    measure: pair.end.measure,
                    fractionNumerator: pair.end.fractionNumerator,
                    fractionDenominator: pair.end.fractionDenominator,
                    token: pair.end.token
                )
                if markLongPairs {
                    startNote.longNote = true
                    endNote.longNote = true
                }
                notes.append(startNote)
                notes.append(endNote)
            }
        }
        return notes
    }

    private func insertConvertedNTNotes(
        _ notes: [LegacyClipboardNote],
        ntInput: Bool,
        originals: [LongNoteSnapshot] = []
    ) throws {
        if ntInput {
            for note in notes {
                if note.length > 0 {
                    try insertConvertedLong(
                        start: note,
                        endVPosition: note.vPosition + note.length,
                        startValue: note.value,
                        endValue: note.value,
                        originals: originals
                    )
                } else {
                    try insertClipboardNote(note, ntInput: true)
                }
            }
            return
        }
        var remaining = notes
        while !remaining.isEmpty {
            let start = remaining.removeFirst()
            if start.longNote,
               let endIndex = remaining.firstIndex(where: {
                   $0.longNote && $0.columnIndex == start.columnIndex
               }) {
                let end = remaining.remove(at: endIndex)
                try insertConvertedLong(
                    start: start,
                    endVPosition: end.vPosition,
                    startValue: start.value,
                    endValue: end.value,
                    originals: originals
                )
                continue
            }
            var shortNote = start
            shortNote.longNote = false
            try insertClipboardNote(shortNote, ntInput: false)
        }
    }

    /// `insert_note` 不接受 `5x`。已有 `#LNOBJ` 对必须仍走可见通道，不能改写成 `51`。
    private func insertConvertedLong(
        start: LegacyClipboardNote,
        endVPosition: Double,
        startValue: Int,
        endValue: Int,
        originals: [LongNoteSnapshot]
    ) throws {
        let length = endVPosition - start.vPosition
        guard length > 0 else {
            var shortNote = start
            shortNote.longNote = false
            try insertClipboardNote(shortNote, ntInput: false)
            return
        }
        let original = originals.first { pair in
            LegacyClipboard.columnIndex(forChannel: pair.channel) == start.columnIndex
                && abs(
                    LegacyClipboard.vPosition(
                        measure: pair.start.measure,
                        fractionNumerator: pair.start.fractionNumerator,
                        fractionDenominator: pair.start.fractionDenominator
                    ) - start.vPosition
                ) < 0.000_001
        }
        var flagged = start
        flagged.longNote = true
        flagged.length = length
        let channel = original?.channel ?? LegacyClipboard.writeChannel(flagged)
        guard let channel else {
            var shortNote = start
            shortNote.longNote = false
            try insertClipboardNote(shortNote, ntInput: false)
            return
        }
        let startLocation = LegacyClipboard.location(vPosition: start.vPosition)
        let endLocation = LegacyClipboard.location(vPosition: endVPosition)
        let startToken = original?.start.token ?? LegacyClipboard.token(fromValue: startValue)
        let endToken: String
        if original?.encoding == "lnobj" {
            endToken = original?.end.token ?? longNoteSnapshot.lnobjToken
        } else {
            endToken = original?.end.token ?? LegacyClipboard.token(fromValue: endValue)
        }
        try insertLongNote(
            channel: channel,
            startMeasure: startLocation.measure,
            startNumerator: startLocation.numerator,
            startDenominator: startLocation.denominator,
            endMeasure: endLocation.measure,
            endNumerator: endLocation.numerator,
            endDenominator: endLocation.denominator,
            startToken: startToken,
            endToken: endToken
        )
    }

    private func insertClipboardNote(_ note: LegacyClipboardNote, ntInput: Bool) throws {
        let token = LegacyClipboard.token(fromValue: note.value)
        if ntInput && note.length > 0 {
            var longNote = note
            longNote.longNote = true
            guard let channel = LegacyClipboard.writeChannel(longNote) else { return }
            let start = LegacyClipboard.location(vPosition: note.vPosition)
            let end = LegacyClipboard.location(vPosition: note.vPosition + note.length)
            try insertLongNote(
                channel: channel,
                startMeasure: start.measure,
                startNumerator: start.numerator,
                startDenominator: start.denominator,
                endMeasure: end.measure,
                endNumerator: end.numerator,
                endDenominator: end.denominator,
                startToken: token,
                endToken: token
            )
            return
        }
        guard let channel = LegacyClipboard.writeChannel(note) else { return }
        let location = LegacyClipboard.location(vPosition: note.vPosition)
        if ["03", "08", "09", "SC"].contains(channel) {
            let decimal = LegacyClipboard.decimal(fromValue: note.value)
            let fraction = TimingRational(numerator: location.numerator, denominator: location.denominator)
            if channel == "03" || channel == "08" {
                guard let routed = ChartTiming.bpmWriteChannel(decimal),
                      let stored = ChartTiming.storedBpmDecimal(decimal) else { return }
                try insertTimingEvent(measure: location.measure, channel: routed, fraction: fraction, decimal: stored)
            } else {
                try insertTimingEvent(measure: location.measure, channel: channel, fraction: fraction, decimal: decimal)
            }
            return
        }
        try insertNote(
            measure: location.measure,
            channel: channel,
            fractionNumerator: location.numerator,
            fractionDenominator: location.denominator,
            token: token
        )
    }

    func moveNotes(
        toDisplay display: String,
        events: [ChartEventSnapshot],
        longNotes: [LongNoteSnapshot],
        shiftFirstOnly: Bool
    ) throws {
        try withCompound {
            let moving = LegacyMoveNotes.notesToMove(
                sorted: Self.orderedSelection(events: events, longNotes: longNotes),
                shiftFirstOnly: shiftFirstOnly
            )
            for item in moving {
                switch item {
                case .short(let event):
                    guard let destination = LegacyMoveNotes.destination(source: event.channel, display: display),
                          destination != event.channel else { continue }
                    try moveNote(event, toChannel: destination)
                case .long(let note):
                    guard let destination = LegacyMoveNotes.destination(source: note.channel, display: display),
                          destination != note.channel else { continue }
                    try relocateLongNote(note, toChannel: destination)
                }
            }
        }
    }

    func moveNotesToBGM(
        events: [ChartEventSnapshot],
        longNotes: [LongNoteSnapshot],
        ntInput: Bool
    ) throws {
        try withCompound {
            for item in Self.orderedSelection(events: events, longNotes: longNotes) {
                let occupants = currentMoveOccupants()
                switch item {
                case .short(let event):
                    let moving = LegacyMoveNotes.Occupant(
                        channel: event.channel,
                        vPosition: ChartDuplicate.vPosition(beat: event.beat),
                        length: 0
                    )
                    let destination = LegacyMoveNotes.bgmDestination(
                        moving: moving,
                        occupants: occupants,
                        ntInput: ntInput
                    )
                    if destination != event.channel {
                        try moveNote(event, toChannel: destination)
                    }
                case .long(let note):
                    let start = ChartDuplicate.vPosition(beat: note.start.beat)
                    let moving = LegacyMoveNotes.Occupant(
                        channel: note.channel,
                        vPosition: start,
                        length: ChartDuplicate.vPosition(beat: note.end.beat) - start
                    )
                    let destination = LegacyMoveNotes.bgmDestination(
                        moving: moving,
                        occupants: occupants,
                        ntInput: ntInput
                    )
                    if destination != note.channel {
                        try relocateLongNote(note, toChannel: destination)
                    }
                }
            }
        }
    }

    private enum MoveSelectionItem {
        case short(ChartEventSnapshot)
        case long(LongNoteSnapshot)

        var beat: Double {
            switch self {
            case .short(let event): return event.beat
            case .long(let note): return note.start.beat
            }
        }

        var channel: String {
            switch self {
            case .short(let event): return event.channel
            case .long(let note): return note.channel
            }
        }
    }

    private static func orderedSelection(
        events: [ChartEventSnapshot],
        longNotes: [LongNoteSnapshot]
    ) -> [MoveSelectionItem] {
        (events.map(MoveSelectionItem.short) + longNotes.map(MoveSelectionItem.long)).sorted {
            if $0.beat != $1.beat { return $0.beat < $1.beat }
            return $0.channel < $1.channel
        }
    }

    private func currentMoveOccupants() -> [LegacyMoveNotes.Occupant] {
        var occupants: [LegacyMoveNotes.Occupant] = chartSnapshot.events.map { event in
            LegacyMoveNotes.Occupant(
                channel: event.channel,
                vPosition: ChartDuplicate.vPosition(beat: event.beat),
                length: 0
            )
        }
        occupants += longNoteSnapshot.notes.map { note in
            let start = ChartDuplicate.vPosition(beat: note.start.beat)
            return LegacyMoveNotes.Occupant(
                channel: note.channel,
                vPosition: start,
                length: ChartDuplicate.vPosition(beat: note.end.beat) - start
            )
        }
        return occupants
    }

    private func relocateLongNote(_ note: LongNoteSnapshot, toChannel channel: String) throws {
        try eraseLongNote(note)
        try insertLongNote(
            channel: channel,
            startMeasure: note.start.measure,
            startNumerator: note.start.fractionNumerator,
            startDenominator: note.start.fractionDenominator,
            endMeasure: note.end.measure,
            endNumerator: note.end.fractionNumerator,
            endDenominator: note.end.fractionDenominator,
            startToken: note.start.token,
            endToken: note.end.token
        )
    }

    func mirrorNotes(_ events: [ChartEventSnapshot]) throws {
        for event in events {
            guard let destination = ChartConvert.mirrorChannel(event.channel),
                  destination != event.channel else { continue }
            try moveNote(event, toChannel: destination)
        }
    }

    func mirrorLongNotes(_ notes: [LongNoteSnapshot]) throws {
        for note in notes {
            guard let destination = ChartConvert.mirrorChannel(note.channel),
                  destination != note.channel else { continue }
            try eraseLongNote(note)
            try insertLongNote(
                channel: destination,
                startMeasure: note.start.measure,
                startNumerator: note.start.fractionNumerator,
                startDenominator: note.start.fractionDenominator,
                endMeasure: note.end.measure,
                endNumerator: note.end.fractionNumerator,
                endDenominator: note.end.fractionDenominator,
                startToken: note.start.token,
                endToken: note.end.token
            )
        }
    }

    func modifyNoteLabels(_ events: [ChartEventSnapshot], label: String) throws {
        guard let token = ChartConvert.modifyLabel(label) else { return }
        for event in events where !ChartConvert.isNumericChannel(event.channel) {
            try eraseNote(event)
            try insertNote(
                measure: event.measure,
                channel: event.channel,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator,
                token: token
            )
        }
    }

    /// `fdrReplaceL`：改 `Notes(i).Value`，不先对齐到当前网格。
    func replaceFindLabels(
        events: [ChartEventSnapshot],
        longNotes: [LongNoteSnapshot],
        label: String
    ) throws {
        try withCompound {
            try modifyNoteLabels(events, label: label)
            guard let token = ChartConvert.modifyLabel(label) else { return }
            for note in longNotes {
                let endToken = note.encoding == "lnobj" ? note.end.token : token
                try eraseLongNote(note)
                try insertLongNote(
                    channel: note.channel,
                    startMeasure: note.start.measure,
                    startNumerator: note.start.fractionNumerator,
                    startDenominator: note.start.fractionDenominator,
                    endMeasure: note.end.measure,
                    endNumerator: note.end.fractionNumerator,
                    endDenominator: note.end.fractionDenominator,
                    startToken: token,
                    endToken: endToken
                )
            }
        }
    }

    /// `fdrReplaceV`：时值列改 Value。SCROLL 不在核心 `timing()` 里，走谱面事件。
    func replaceFindValues(
        timing: [TimingEventSnapshot],
        events: [ChartEventSnapshot],
        decimal: String
    ) throws {
        try withCompound {
            for event in timing {
                try replaceTimingEvent(event, decimal: decimal)
            }
            try modifyTimingValues(events, decimal: decimal)
        }
    }

    func wavNames() throws -> [String] {
        try resourceNames(directive: "WAV")
    }

    func bmpNames() throws -> [String] {
        try resourceNames(directive: "BMP")
    }

    func applyWavEdit(_ edit: WavListEdit, synchronizeLabels: Bool) throws {
        try applyResourceEdit(edit, directive: "WAV", synchronizeLabels: synchronizeLabels)
    }

    func applyBmpEdit(_ edit: WavListEdit, synchronizeLabels: Bool) throws {
        try applyResourceEdit(edit, directive: "BMP", synchronizeLabels: synchronizeLabels)
    }

    private func resourceNames(directive: String) throws -> [String] {
        let data = try currentBytes()
        let text: String
        if let encoding = metadataEncoding, let decoded = String(data: data, encoding: encoding.stringEncoding) {
            text = decoded
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        return LegacyWavList.names(from: LegacyWavList.parseTable(from: text, directive: directive))
    }

    private func applyResourceEdit(_ edit: WavListEdit, directive: String, synchronizeLabels: Bool) throws {
        guard canEditMetadata else {
            throw hasConditionals ? DocumentSessionError.conditionalDocument : DocumentSessionError.unsupportedMetadataEncoding
        }
        guard edit.names.count == LegacyWavList.slotCount else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        let current = try resourceNames(directive: directive)
        try withCompound {
            for slot in 0..<LegacyWavList.slotCount where current[slot] != edit.names[slot] {
                try writeResource(edit.names[slot], directive: directive, token: LegacyWavList.token(at: slot))
            }
            if synchronizeLabels {
                for pair in edit.labelSwaps {
                    try swapNoteLabels(pair.0, pair.1)
                }
            }
        }
        try refreshChartSnapshot()
    }

    private func writeResource(_ name: String, directive: String, token: String) throws {
        let data: Data
        if name.isEmpty {
            data = Data()
        } else if let encoding = metadataEncoding,
                  let encoded = name.data(using: encoding.stringEncoding, allowLossyConversion: false),
                  String(data: encoded, encoding: encoding.stringEncoding) == name {
            data = encoded
        } else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        try bridge.setHeaderData(data, forKey: LegacyWavList.headerKey(directive: directive, token: token))
    }

    private func swapNoteLabels(_ first: String, _ second: String) throws {
        let events = chartSnapshot.events.filter {
            !ChartConvert.isNumericChannel($0.channel) && ($0.token == first || $0.token == second)
        }
        let longs = longNoteSnapshot.notes
        for event in events {
            let token = event.token == first ? second : first
            try eraseNote(event)
            try insertNote(
                measure: event.measure,
                channel: event.channel,
                fractionNumerator: event.fractionNumerator,
                fractionDenominator: event.fractionDenominator,
                token: token
            )
        }
        for note in longs {
            var start = note.start.token
            var end = note.end.token
            if start == first { start = second } else if start == second { start = first }
            if note.encoding != "lnobj" {
                if end == first { end = second } else if end == second { end = first }
            }
            guard start != note.start.token || end != note.end.token else { continue }
            try eraseLongNote(note)
            try insertLongNote(
                channel: note.channel,
                startMeasure: note.start.measure,
                startNumerator: note.start.fractionNumerator,
                startDenominator: note.start.fractionDenominator,
                endMeasure: note.end.measure,
                endNumerator: note.end.fractionNumerator,
                endDenominator: note.end.fractionDenominator,
                startToken: start,
                endToken: end
            )
        }
    }

    func modifyTimingValues(_ events: [ChartEventSnapshot], decimal: String) throws {
        for event in events where ChartConvert.isNumericChannel(event.channel) {
            let fraction = TimingRational(numerator: event.fractionNumerator, denominator: event.fractionDenominator)
            try eraseNote(event)
            if event.channel == "03" || event.channel == "08" {
                guard let routed = ChartTiming.bpmWriteChannel(decimal),
                      let stored = ChartTiming.storedBpmDecimal(decimal) else { continue }
                try insertTimingEvent(measure: event.measure, channel: routed, fraction: fraction, decimal: stored)
            } else {
                try insertTimingEvent(measure: event.measure, channel: event.channel, fraction: fraction, decimal: decimal)
            }
        }
    }

    private func clipboardValue(for event: ChartEventSnapshot) -> Int {
        if event.channel == "03" {
            return LegacyClipboard.hexTokenValue(event.token)
        }
        if event.channel == "SC",
           let data = try? currentBytes(),
           let decimal = LegacyClipboard.scrollDecimal(
            token: event.token,
            in: String(decoding: data, as: UTF8.self)
           ) {
            return LegacyClipboard.numericValue(decimal)
        }
        if let timing = timingSnapshot.events.first(where: {
            $0.measure == event.measure
                && $0.channel == event.channel
                && $0.fraction.numerator == event.fractionNumerator
                && $0.fraction.denominator == event.fractionDenominator
        }) {
            return LegacyClipboard.numericValue(timing.valueDecimal)
        }
        return LegacyClipboard.tokenValue(event.token)
    }

    func setInitialBPM(_ decimal: String) throws {
        try bridge.setInitialBPM(decimal)
        try refreshChartSnapshot()
    }

    func setMeasureRatio(measure: Int, decimal: String) throws {
        try bridge.setMeasureRatio(measure, decimal: decimal)
        try refreshChartSnapshot()
    }

    func expansionText() throws -> String {
        let data = try bridge.expansionData()
        if data.isEmpty {
            return ""
        }
        if let encoding = metadataEncoding,
           let text = String(data: data, encoding: encoding.stringEncoding) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    func setExpansion(_ text: String) throws {
        let encoding = metadataEncoding?.stringEncoding ?? .utf8
        guard let data = text.data(using: encoding, allowLossyConversion: false) else {
            throw DocumentSessionError.unsupportedMetadataEncoding
        }
        try bridge.setExpansionData(data)
        try refreshChartSnapshot()
    }

    func applyBeat(measures: [Int], decimal: String, mode: Int) throws {
        try bridge.applyBeat(
            toMeasures: measures.map { NSNumber(value: $0) },
            decimal: decimal,
            mode: mode
        )
        try refreshChartSnapshot()
    }

    func insertTimingEvent(measure: Int, channel: String, fraction: TimingRational, decimal: String) throws {
        try bridge.insertTimingEvent(
            atMeasure: measure,
            channel: channel,
            fractionNumerator: fraction.numerator,
            fractionDenominator: fraction.denominator,
            decimal: decimal
        )
        try refreshChartSnapshot()
    }

    func insertTimingEvent(
        atVPosition vPosition: Double,
        channel: String,
        decimal: String,
        measureLengths: [Int: Double]
    ) throws {
        let grid = LegacyMeasureGrid.grid(from: vPosition, measureLengths: measureLengths)
        try insertTimingEvent(
            measure: grid.measure,
            channel: channel,
            fraction: TimingRational(numerator: Int64(grid.slot), denominator: Int64(grid.division)),
            decimal: decimal
        )
    }

    func insertTimingEvent(measure: Int, channel: String, gridSlot: Int, gridDivision: Int, decimal: String) throws {
        try bridge.insertTimingEvent(
            atMeasure: measure,
            channel: channel,
            gridSlot: gridSlot,
            gridDivision: gridDivision,
            decimal: decimal
        )
        try refreshChartSnapshot()
    }

    func replaceTimingEvent(_ event: TimingEventSnapshot, decimal: String) throws {
        try bridge.replaceTimingEvent(
            atMeasure: event.measure,
            channel: event.channel,
            fractionNumerator: event.fraction.numerator,
            fractionDenominator: event.fraction.denominator,
            decimal: decimal
        )
        try refreshChartSnapshot()
    }

    func eraseTimingEvent(_ event: TimingEventSnapshot) throws {
        try bridge.eraseTimingEvent(
            atMeasure: event.measure,
            channel: event.channel,
            fractionNumerator: event.fraction.numerator,
            fractionDenominator: event.fraction.denominator
        )
        try refreshChartSnapshot()
    }

    private func refreshChartSnapshot() throws {
        chartSnapshot = try Self.chartSnapshot(from: bridge)
        longNoteSnapshot = try Self.longNoteSnapshot(from: bridge)
        timingSnapshot = try Self.timingSnapshot(
            from: bridge,
            chartEditable: chartSnapshot.editable,
            canEditInitialBPM: !documentHasConditionals
        )
    }

    private static func chartSnapshot(from bridge: IBMSDocumentBridge) throws -> ChartSnapshot {
        let snapshot = try bridge.chartSnapshot()
        return ChartSnapshot(
            events: snapshot.events.map { event in
                ChartEventSnapshot(
                    measure: event.measure,
                    channel: event.kind == "bgm" ? ChartBGM.displayChannel(lane: Int(event.bgmLane)) : event.channel,
                    token: event.token,
                    fractionNumerator: event.fractionNumerator,
                    fractionDenominator: event.fractionDenominator,
                    beat: event.beat,
                    kind: event.kind,
                    sourceLine: Int(event.sourceLine)
                )
            },
            measures: snapshot.measures.map { measure in ChartMeasureSnapshot(measure: measure.measure, start: measure.start, length: measure.length) },
            diagnostics: snapshot.diagnostics.map { ChartDiagnosticSnapshot(sourceLine: Int($0.sourceLine), message: $0.message) },
            editable: snapshot.isEditable, editingReason: snapshot.editingReason
        )
    }

    private static func longNoteSnapshot(from bridge: IBMSDocumentBridge) throws -> LongNoteSnapshotSet {
        let snapshot = try bridge.longNoteSnapshot()
        return LongNoteSnapshotSet(
            notes: snapshot.notes.map { note in
                LongNoteSnapshot(
                    channel: note.channel,
                    start: LongNoteEndpointSnapshot(
                        measure: note.start.measure,
                        fractionNumerator: note.start.fractionNumerator,
                        fractionDenominator: note.start.fractionDenominator,
                        beat: note.start.beat,
                        token: note.start.token,
                        sourceLine: Int(note.start.sourceLine)
                    ),
                    end: LongNoteEndpointSnapshot(
                        measure: note.end.measure,
                        fractionNumerator: note.end.fractionNumerator,
                        fractionDenominator: note.end.fractionDenominator,
                        beat: note.end.beat,
                        token: note.end.token,
                        sourceLine: Int(note.end.sourceLine)
                    ),
                    encoding: note.encoding
                )
            },
            diagnostics: snapshot.diagnostics.map {
                LongNoteDiagnosticSnapshot(sourceLine: Int($0.sourceLine), message: $0.message)
            },
            editable: snapshot.isEditable,
            editingReason: snapshot.editingReason,
            lnobjToken: snapshot.lnobjToken
        )
    }

    private static func timingSnapshot(
        from bridge: IBMSDocumentBridge,
        chartEditable: Bool,
        canEditInitialBPM: Bool
    ) throws -> TimingSnapshot {
        let snapshot = try bridge.timingSnapshot()
        return TimingSnapshot(
            initialBPMDecimal: snapshot.initialBPMDecimal,
            measures: snapshot.measures.map { measure in
                TimingMeasureSnapshot(measure: measure.measure, ratioDecimal: measure.ratioDecimal)
            },
            events: snapshot.events.compactMap { event in
                guard let kind = TimingEventKind(rawValue: event.kind) else { return nil }
                return TimingEventSnapshot(
                    measure: event.measure,
                    channel: event.channel,
                    token: event.token,
                    fraction: TimingRational(
                        numerator: event.fractionNumerator,
                        denominator: event.fractionDenominator
                    ),
                    beat: TimingRational(
                        numerator: event.beatNumerator,
                        denominator: event.beatDenominator
                    ),
                    valueDecimal: event.valueDecimal,
                    kind: kind,
                    sourceLine: Int(event.sourceLine),
                    hasTime: event.hasTime,
                    secondsBeforeStop: event.secondsBeforeStop,
                    secondsAfterStop: event.secondsAfterStop
                )
            },
            diagnostics: snapshot.diagnostics.map { diagnostic in
                TimingDiagnosticSnapshot(sourceLine: Int(diagnostic.sourceLine), message: diagnostic.message)
            },
            available: snapshot.isAvailable,
            canEditInitialBPM: canEditInitialBPM,
            canEditTimeline: chartEditable,
            unavailableReason: snapshot.unavailableReason
        )
    }

    private static func encodingRoundTrips(_ source: Data, using encoding: MetadataEncoding) -> Bool {
        // Foundation consumes a UTF-8 BOM when decoding. It remains in the bridge's raw bytes.
        let payload = source.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(source.dropFirst(3)) : source
        guard let decoded = String(data: payload, encoding: encoding.stringEncoding),
              let encoded = decoded.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            return false
        }
        return encoded == payload
    }

    private func trimASCIIWhitespace(_ value: String) -> String {
        let whitespace = Set<UInt8>([0x09, 0x20])
        let bytes = Array(value.utf8)
        let first = bytes.firstIndex(where: { !whitespace.contains($0) })
        guard let first else { return "" }
        let last = bytes.lastIndex(where: { !whitespace.contains($0) })!
        return String(decoding: bytes[first...last], as: UTF8.self)
    }
}
