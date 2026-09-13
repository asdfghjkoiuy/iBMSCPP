import Foundation

/// Swift face of `ibms::BmsonDocument` via `IBMSBmsonBridge`.
/// This is not `BmsDocument` and does not call BMS `insert_note`.
final class BmsONEDocument: BmsONEDocumentModel {
    private var bridge: IBMSBmsonBridge
    private(set) var filePath: String?
    private(set) var isModified: Bool
    /// Sound-channel index used when placing a note. Out of range falls back to 0.
    var selectedChannelIndex: Int
    private var undoJSON: [String] = []
    private var redoJSON: [String] = []
    private var cleanJSON: String
    private var hasSavedClean: Bool

    private init(bridge: IBMSBmsonBridge, filePath: String?, isModified: Bool) {
        self.bridge = bridge
        self.filePath = filePath
        self.isModified = isModified
        self.selectedChannelIndex = 0
        self.hasSavedClean = !isModified
        self.cleanJSON = self.hasSavedClean ? ((try? bridge.jsonString()) ?? "") : ""
    }

    var canUndo: Bool { !undoJSON.isEmpty }
    var canRedo: Bool { !redoJSON.isEmpty }

    static func empty() -> BmsONEDocument {
        BmsONEDocument(bridge: IBMSBmsonBridge.emptyDocument(), filePath: nil, isModified: false)
    }

    static func fromJSON(_ text: String, filePath: String? = nil) throws -> BmsONEDocument {
        do {
            let bridge = try IBMSBmsonBridge(jsonString: text)
            return BmsONEDocument(bridge: bridge, filePath: filePath, isModified: false)
        } catch {
            throw BmsONEDocumentError.parse(error.localizedDescription)
        }
    }

    static func open(url: URL) throws -> BmsONEDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try fromJSON(text, filePath: url.path)
    }

    /// BMS → BMSON。对照 `Document::LoadBms`。结果不是 `BmsDocument`。
    /// 导入后标成已修改，也没有 BMSON 路径。
    /// 先按所选编码解成 UTF-8，再按 RANDOM 值滤掉没选中的分支。
    static func importBms(
        data: Data,
        path: String? = nil,
        mode: BmsONEBmsMode? = nil,
        encoding: BmsONETextEncoding = BmsONEImportQuestion.defaultEncoding,
        randomValues: [Int] = [],
        options: BmsONEImportOptions = BmsONEImportOptions()
    ) throws -> BmsONEDocument {
        do {
            let prepared = try prepareBmsData(
                data,
                encoding: encoding,
                randomValues: randomValues,
                options: options
            )
            let bridge = try IBMSBmsonBridge.fromBmsData(
                prepared,
                path: path,
                options: bridgeOptions(options, mode: mode)
            )
            return BmsONEDocument(bridge: bridge, filePath: nil, isModified: true)
        } catch {
            throw BmsONEDocumentError.parse(error.localizedDescription)
        }
    }

    static func importBms(
        url: URL,
        mode: BmsONEBmsMode? = nil,
        encoding: BmsONETextEncoding = BmsONEImportQuestion.defaultEncoding,
        randomValues: [Int] = [],
        options: BmsONEImportOptions = BmsONEImportOptions()
    ) throws -> BmsONEDocument {
        let data = try Data(contentsOf: url)
        return try importBms(
            data: data,
            path: url.path,
            mode: mode,
            encoding: encoding,
            randomValues: randomValues,
            options: options
        )
    }

    static func prepareBmsData(
        _ data: Data,
        encoding: BmsONETextEncoding = BmsONEImportQuestion.defaultEncoding,
        randomValues: [Int] = [],
        options: BmsONEImportOptions = BmsONEImportOptions()
    ) throws -> Data {
        let decoded = encoding.decode(data)
        let maxima = try randomMaxima(from: decoded)
        let values = randomValues.isEmpty
            ? options.defaultRandomValues(maxima: maxima)
            : randomValues
        return try IBMSBmsonBridge.applyRandom(
            to: decoded,
            values: values.map { NSNumber(value: $0) },
            skipBetweenRandomAndIf: options.skipBetweenRandomAndIf
        )
    }

    private static func bridgeOptions(
        _ options: BmsONEImportOptions,
        mode: BmsONEBmsMode?
    ) -> IBMSBmsonFromBmsOptions {
        let value = IBMSBmsonFromBmsOptions()
        value.trustPlayerCommand = options.trustPlayerCommand
        value.ignoreExtension = options.ignoreExtension
        value.preferExModes = options.preferExModes
        value.skipBetweenRandomAndIf = options.skipBetweenRandomAndIf
        value.mode = mode?.rawValue ?? -1
        return value
    }

    static func randomMaxima(from data: Data) throws -> [Int] {
        do {
            return try IBMSBmsonBridge.randomMaxima(fromBmsData: data).map(\.intValue)
        } catch {
            throw BmsONEDocumentError.parse(error.localizedDescription)
        }
    }

    static func encodingPreviews(from data: Data) -> [(encoding: BmsONETextEncoding, preview: String)] {
        BmsONETextEncoding.allCases.map { encoding in
            (encoding, encoding.preview(from: data))
        }
    }

    static func detectGameMode(
        data: Data,
        path: String? = nil,
        encoding: BmsONETextEncoding = BmsONEImportQuestion.defaultEncoding,
        randomValues: [Int] = [],
        options: BmsONEImportOptions = BmsONEImportOptions()
    ) throws -> BmsONEBmsMode {
        let prepared = try prepareBmsData(
            data,
            encoding: encoding,
            randomValues: randomValues,
            options: options
        )
        let raw: NSNumber
        do {
            raw = try IBMSBmsonBridge.detectedMode(
                fromBmsData: prepared,
                path: path,
                options: bridgeOptions(options, mode: nil)
            )
        } catch {
            throw BmsONEDocumentError.parse(error.localizedDescription)
        }
        guard let mode = BmsONEBmsMode(rawValue: raw.intValue) else {
            throw BmsONEDocumentError.parse("Unknown game mode \(raw.intValue)")
        }
        return mode
    }

    static func gameModeQuestion(
        data: Data,
        path: String? = nil,
        encoding: BmsONETextEncoding = BmsONEImportQuestion.defaultEncoding,
        randomValues: [Int] = [],
        options: BmsONEImportOptions = BmsONEImportOptions()
    ) throws -> (detected: BmsONEBmsMode, choices: [BmsONEGameModeChoice]) {
        let prepared = try prepareBmsData(
            data,
            encoding: encoding,
            randomValues: randomValues,
            options: options
        )
        let detected = try detectGameMode(
            data: data,
            path: path,
            encoding: encoding,
            randomValues: randomValues,
            options: options
        )
        var errorByMode: [BmsONEBmsMode: Bool] = [:]
        for mode in BmsONEBmsMode.allCases {
            do {
                let offsets = try IBMSBmsonBridge.errorOffsets(fromBmsData: prepared, path: path, mode: mode.rawValue)
                errorByMode[mode] = !offsets.isEmpty
            } catch {
                throw BmsONEDocumentError.parse(error.localizedDescription)
            }
        }
        return (detected, BmsONEImportQuestion.choices(errorByMode: errorByMode))
    }

    var title: String { bridge.info.title }
    var initialBpm: Double { bridge.info.initBPM }
    var modeHint: String { bridge.info.modeHint }
    var resolution: Int { Int(bridge.info.resolution) }
    var judgeRank: Double { bridge.info.judgeRank }
    var total: Double { bridge.info.total }
    var level: Int { Int(bridge.info.level) }
    var version: String { bridge.version }
    var info: IBMSBmsonInfoSnapshot { bridge.info }
    var lines: [IBMSBmsonBarLineSnapshot] { bridge.lines }
    var bpmNotes: [IBMSBmsonBpmNoteSnapshot] { bridge.bpmNotes }
    var stopNotes: [IBMSBmsonStopNoteSnapshot] { bridge.stopNotes }
    var soundChannels: [IBMSBmsonSoundChannelSnapshot] { bridge.soundChannels }
    var bgaHeaders: [IBMSBmsonBgaHeaderSnapshot] { bridge.bgaHeaders }
    var bgaEvents: [IBMSBmsonBgaEventSnapshot] { bridge.bgaEvents }
    var layerEvents: [IBMSBmsonBgaEventSnapshot] { bridge.layerEvents }
    var poorEvents: [IBMSBmsonBgaEventSnapshot] { bridge.poorEvents }

    func insertShortNote(laneX: Int64, pulseY: Int64, continueFlag: Bool = false) throws {
        try insertNote(laneX: laneX, pulseY: pulseY, length: 0, continueFlag: continueFlag)
    }

    func insertNote(laneX: Int64, pulseY: Int64, length: Int64, continueFlag: Bool = false) throws {
        let channel = resolvedChannelIndex()
        try commitEdit {
            try bridge.insertSoundNote(
                onChannel: UInt(channel),
                x: laneX,
                y: pulseY,
                l: length,
                c: continueFlag
            )
        }
    }

    func eraseNote(atPulse pulseY: Int64, channelIndex: Int? = nil) throws {
        let channel = channelIndex ?? resolvedChannelIndex()
        try commitEdit {
            try bridge.eraseSoundNote(onChannel: UInt(channel), y: pulseY)
        }
    }

    func eraseNote(identity: Int) throws {
        let located = try note(at: identity)
        try eraseNote(atPulse: located.note.y, channelIndex: located.channelIndex)
    }

    /// 菜单 / 工具条 Cut、Delete 一批一笔。同一 identity 只删一次。找不到的跳过。
    /// `identity == 0` 当作声道 0 第 0 颗。长音只按起点 identity 删。
    func eraseNotes(
        identities: [Int] = [],
        bpmPulses: [Int64] = [],
        stopPulses: [Int64] = [],
        bgaEvents: [(lane: BmsonChartMapping.BgaLane, pulseY: Int64)] = []
    ) throws {
        var seenIdentities = Set<Int>()
        var sounds: [(channel: Int, y: Int64)] = []
        for raw in identities {
            let identity = raw == 0
                ? BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
                : raw
            guard seenIdentities.insert(identity).inserted else { continue }
            guard let located = try? note(at: identity) else { continue }
            sounds.append((located.channelIndex, located.note.y))
        }

        var bpms: [Int64] = []
        var seenBpm = Set<Int64>()
        for pulse in bpmPulses {
            guard seenBpm.insert(pulse).inserted else { continue }
            guard bpmNotes.contains(where: { $0.y == pulse }) else { continue }
            bpms.append(pulse)
        }

        var stops: [Int64] = []
        var seenStop = Set<Int64>()
        for pulse in stopPulses {
            guard seenStop.insert(pulse).inserted else { continue }
            guard stopNotes.contains(where: { $0.y == pulse }) else { continue }
            stops.append(pulse)
        }

        var bgaTargets: [EraseBgaKey] = []
        var seenBga = Set<EraseBgaKey>()
        for event in bgaEvents {
            let key = EraseBgaKey(lane: event.lane, y: event.pulseY)
            guard seenBga.insert(key).inserted else { continue }
            guard self.bgaEvents(on: event.lane).contains(where: { $0.y == event.pulseY }) else {
                continue
            }
            bgaTargets.append(key)
        }

        guard !sounds.isEmpty || !bpms.isEmpty || !stops.isEmpty || !bgaTargets.isEmpty else {
            return
        }
        try commitEditRestoring {
            for sound in sounds {
                try bridge.eraseSoundNote(onChannel: UInt(sound.channel), y: sound.y)
            }
            for y in bpms {
                try bridge.eraseBpmNote(y: y)
            }
            for y in stops {
                try bridge.eraseStopNote(y: y)
            }
            for event in bgaTargets {
                try bridge.eraseBgaEvent(onLane: event.lane.rawValue, y: event.y)
            }
        }
    }

    func replaceNote(
        atPulse oldY: Int64,
        laneX: Int64,
        pulseY: Int64,
        length: Int64,
        continueFlag: Bool = false,
        channelIndex: Int? = nil
    ) throws {
        let channel = channelIndex ?? resolvedChannelIndex()
        try commitEdit {
            try bridge.replaceSoundNote(
                onChannel: UInt(channel),
                oldY: oldY,
                x: laneX,
                y: pulseY,
                l: length,
                c: continueFlag
            )
        }
    }

    func replaceNote(
        identity: Int,
        laneX: Int64,
        pulseY: Int64,
        length: Int64,
        continueFlag: Bool = false
    ) throws {
        let located = try note(at: identity)
        try replaceNote(
            atPulse: located.note.y,
            laneX: laneX,
            pulseY: pulseY,
            length: length,
            continueFlag: continueFlag,
            channelIndex: located.channelIndex
        )
    }

    /// 对照 `NoteEditView`。空选、非法数字、小于 0 返回 false，不记撤销。
    @discardableResult
    func applySelectedNoteLength(identities: [Int], text: String) -> Bool {
        guard let length = BmsonSelectedObjects.parseLength(text) else { return false }
        let located = identities.compactMap { try? note(at: $0) }
        guard !located.isEmpty else { return true }
        if located.allSatisfy({ $0.note.l == length }) {
            return true
        }
        do {
            try commitEdit {
                for item in located {
                    try bridge.replaceSoundNote(
                        onChannel: UInt(item.channelIndex),
                        oldY: item.note.y,
                        x: item.note.x,
                        y: item.note.y,
                        l: length,
                        c: item.note.c
                    )
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// 对照 `NoteEditView` Extra fields。`(multiple values)` 原样提交当作没改。
    @discardableResult
    func applySelectedNoteExtraFields(identities: [Int], text: String) -> Bool {
        if BmsonSelectedObjects.isUnchangedMultipleValues(text) {
            return true
        }
        guard let objectJSON = BmsonSelectedObjects.preparedExtraObjectJSON(text) else {
            return false
        }
        let located = identities.compactMap { try? note(at: $0) }
        guard !located.isEmpty else { return true }
        do {
            try commitEdit {
                for item in located {
                    try bridge.replaceNoteExtraJSON(
                        onChannel: UInt(item.channelIndex),
                        y: item.note.y,
                        json: objectJSON
                    )
                }
            }
            return true
        } catch {
            return false
        }
    }

    func selectedObjectsDisplay(identities: [Int]) -> BmsonSelectedObjects.Display {
        BmsonSelectedObjects.display(notes: selectedObjectNotes(identities: identities))
    }

    private func selectedObjectNotes(identities: [Int]) -> [BmsonSelectedObjects.Note] {
        identities.compactMap { identity in
            guard let located = try? note(at: identity),
                  let extra = try? bridge.noteExtraJSON(onChannel: UInt(located.channelIndex), y: located.note.y)
            else {
                return nil
            }
            return BmsonSelectedObjects.Note(length: located.note.l, extraObjectJSON: extra)
        }
    }

    func upsertBpmNote(pulseY: Int64, bpm: Double) throws {
        try commitEdit {
            try bridge.upsertBpmNote(y: pulseY, v: bpm)
        }
    }

    func eraseBpmNote(pulseY: Int64) throws {
        try commitEdit {
            try bridge.eraseBpmNote(y: pulseY)
        }
    }

    func upsertStopNote(pulseY: Int64, pulses: Double) throws {
        try commitEdit {
            try bridge.upsertStopNote(y: pulseY, v: pulses)
        }
    }

    func eraseStopNote(pulseY: Int64) throws {
        try commitEdit {
            try bridge.eraseStopNote(y: pulseY)
        }
    }

    func moveBpmNote(from oldY: Int64, to newY: Int64, bpm: Double) throws {
        try commitEdit {
            try bridge.upsertBpmNote(y: newY, v: bpm)
            if oldY != newY {
                try bridge.eraseBpmNote(y: oldY)
            }
        }
    }

    func upsertBgaEvent(lane: BmsonChartMapping.BgaLane, pulseY: Int64, identifier: Int) throws {
        try commitEdit {
            try bridge.upsertBgaEvent(onLane: lane.rawValue, y: pulseY, identifier: Int32(identifier))
            if !bgaHeaders.contains(where: { Int($0.identifier) == identifier }) {
                try bridge.upsertBgaHeader(identifier: Int32(identifier), name: "")
            }
        }
    }

    func eraseBgaEvent(lane: BmsonChartMapping.BgaLane, pulseY: Int64) throws {
        try commitEdit {
            try bridge.eraseBgaEvent(onLane: lane.rawValue, y: pulseY)
        }
    }

    func moveBgaEvent(
        lane: BmsonChartMapping.BgaLane,
        from oldY: Int64,
        to newY: Int64,
        identifier: Int
    ) throws {
        try commitEdit {
            try bridge.upsertBgaEvent(onLane: lane.rawValue, y: newY, identifier: Int32(identifier))
            if oldY != newY {
                try bridge.eraseBgaEvent(onLane: lane.rawValue, y: oldY)
            }
        }
    }

    func moveStopNote(from oldY: Int64, to newY: Int64, pulses: Double) throws {
        try commitEdit {
            try bridge.upsertStopNote(y: newY, v: pulses)
            if oldY != newY {
                try bridge.eraseStopNote(y: oldY)
            }
        }
    }

    /// 共用 Find 删除。一次撤销，对照 µBMSC `AddUndo`。
    func deleteFindMatches(identities: [Int]) throws {
        let targets = try resolveFindDeletes(identities)
        guard !targets.isEmpty else { return }
        try commitEdit {
            for target in targets {
                switch target {
                case .sound(let channel, let y):
                    try bridge.eraseSoundNote(onChannel: UInt(channel), y: y)
                case .bpm(let y):
                    try bridge.eraseBpmNote(y: y)
                case .stop(let y):
                    try bridge.eraseStopNote(y: y)
                case .bga(let lane, let y):
                    try bridge.eraseBgaEvent(onLane: lane.rawValue, y: y)
                }
            }
        }
    }

    /// 声音音换标签是换声道；BGA 换标签是改 `id`。一次撤销。
    func replaceFindLabels(identities: [Int], label: String) throws {
        let destChannel = BmsonChartMapping.channelIndex(wavToken: label)
        let destBmp = BmsonChartMapping.bmpId(token: label)
        let sounds = try resolveFindSoundMoves(identities)
        let bgaEvents = try resolveFindBgaTargets(identities)
        guard !sounds.isEmpty || !bgaEvents.isEmpty else { return }
        try validateSoundMoves(sounds, destChannel: destChannel)
        try commitEdit {
            try padSoundChannels(to: destChannel + 1)
            for move in sounds {
                try bridge.eraseSoundNote(onChannel: UInt(move.channel), y: move.y)
            }
            for move in sounds {
                try bridge.insertSoundNote(
                    onChannel: UInt(destChannel),
                    x: move.x,
                    y: move.y,
                    l: move.l,
                    c: move.c
                )
                try bridge.replaceNoteExtraJSON(
                    onChannel: UInt(destChannel),
                    y: move.y,
                    json: move.extra
                )
            }
            if let destBmp {
                for event in bgaEvents {
                    try bridge.upsertBgaEvent(
                        onLane: event.lane.rawValue,
                        y: event.y,
                        identifier: Int32(destBmp)
                    )
                    if !bgaHeaders.contains(where: { Int($0.identifier) == destBmp }) {
                        try bridge.upsertBgaHeader(identifier: Int32(destBmp), name: "")
                    }
                }
            }
        }
    }

    /// BPM 写 `v`；STOP 输入是 BMS 单位。SCROLL 没有 BMSON 模型，跳过。
    func replaceFindValues(identities: [Int], value: Double) throws {
        guard value > 0, value.isFinite else {
            throw BmsONEDocumentError.parse("Find replace value must be positive")
        }
        let timings = try resolveFindTimingTargets(identities)
        guard !timings.isEmpty else { return }
        try commitEdit {
            for item in timings {
                if item.isStop {
                    let pulses = BmsonChartMapping.stopPulses(displayValue: value, resolution: resolution)
                    guard pulses > 0, pulses.isFinite else {
                        throw BmsONEDocumentError.parse("Find replace value must be positive")
                    }
                    try bridge.upsertStopNote(y: item.y, v: pulses)
                } else {
                    try bridge.upsertBpmNote(y: item.y, v: value)
                }
            }
        }
    }

    /// 共用 iBMSC `POBModify`。数值、标签各一笔撤销；空身份或 `nil` 的那一段不写。
    func modifyNotes(
        valueIdentities: [Int],
        value: Double?,
        labelIdentities: [Int],
        label: String?
    ) throws {
        if let value, !valueIdentities.isEmpty {
            try replaceFindValues(identities: valueIdentities, value: value)
        }
        if let label, !labelIdentities.isEmpty {
            try replaceFindLabels(identities: labelIdentities, label: label)
        }
    }

    /// 共用 iBMSC `POBLong`。两颗短音配成一颗 `l>0` 的长音，一次撤销。
    /// 较早那颗留下；较晚那颗删掉。不走 `replaceSoundChannels`，以免清 extra。
    func convertShortPairToLong(startIdentity: Int, endIdentity: Int) throws {
        guard startIdentity > 0, endIdentity > 0 else { return }
        guard let startLocated = try? note(at: startIdentity),
              let endLocated = try? note(at: endIdentity)
        else {
            return
        }
        let earlier: (channelIndex: Int, note: IBMSBmsonNoteSnapshot)
        let later: (channelIndex: Int, note: IBMSBmsonNoteSnapshot)
        if startLocated.note.y <= endLocated.note.y {
            earlier = startLocated
            later = endLocated
        } else {
            earlier = endLocated
            later = startLocated
        }
        guard earlier.note.x == later.note.x else { return }
        let length = later.note.y - earlier.note.y
        guard length > 0 else { return }
        try validateConvertInterval(
            x: earlier.note.x,
            y: earlier.note.y,
            l: length,
            channelIndex: earlier.channelIndex,
            leaving: [
                MirrorNoteKey(channelIndex: earlier.channelIndex, y: earlier.note.y),
                MirrorNoteKey(channelIndex: later.channelIndex, y: later.note.y)
            ]
        )
        try commitEditRestoring {
            try bridge.eraseSoundNote(onChannel: UInt(later.channelIndex), y: later.note.y)
            try bridge.replaceSoundNote(
                onChannel: UInt(earlier.channelIndex),
                oldY: earlier.note.y,
                x: earlier.note.x,
                y: earlier.note.y,
                l: length,
                c: earlier.note.c
            )
        }
    }

    /// BMSON 没有 `51`。配不成对的短音成功返回，不改谱。
    func convertShortNoteToLongEndpoint(identity: Int) {
        _ = identity
    }

    /// BMSON 显示层不会出现 `51` 事件。不成对端点成功返回，不改谱。
    func convertLongEndpointToShort(identity: Int) {
        _ = identity
    }

    /// 共用 iBMSC `POBShort`。`keepEnd=false` 只把 `l` 改成 0；`keepEnd=true` 再插终点短音。
    /// 先缩再插，避免和新终点叠在自己的长音区间上。已经是短音则不写。
    func convertLongToShort(identity: Int, keepEnd: Bool) throws {
        guard identity > 0 else { return }
        guard let located = try? note(at: identity) else { return }
        guard located.note.l > 0 else { return }
        let destY = located.note.y + located.note.l
        if keepEnd {
            try validateConvertInterval(
                x: located.note.x,
                y: destY,
                l: 0,
                channelIndex: located.channelIndex,
                leaving: [MirrorNoteKey(channelIndex: located.channelIndex, y: located.note.y)]
            )
        }
        try commitEditRestoring {
            try bridge.replaceSoundNote(
                onChannel: UInt(located.channelIndex),
                oldY: located.note.y,
                x: located.note.x,
                y: located.note.y,
                l: 0,
                c: located.note.c
            )
            if keepEnd {
                try bridge.insertSoundNote(
                    onChannel: UInt(located.channelIndex),
                    x: located.note.x,
                    y: destY,
                    l: 0,
                    c: false
                )
            }
        }
    }

    /// 目标区间上已有不会被这次删掉的可玩列冲突 → `Overlapping notes`。
    private func validateConvertInterval(
        x: Int64,
        y: Int64,
        l: Int64,
        channelIndex: Int,
        leaving: Set<MirrorNoteKey>
    ) throws {
        if x > 0 {
            for (otherIndex, channel) in soundChannels.enumerated() {
                for existing in channel.notes where existing.x > 0 && existing.x == x {
                    if leaving.contains(MirrorNoteKey(channelIndex: otherIndex, y: existing.y)) {
                        continue
                    }
                    if pulsesOverlap(existing.y, existing.l, y, l) {
                        throw BmsONEDocumentError.parse("Overlapping notes")
                    }
                }
            }
        } else if channelIndex >= 0, channelIndex < soundChannels.count {
            for existing in soundChannels[channelIndex].notes where existing.x <= 0 {
                if leaving.contains(MirrorNoteKey(channelIndex: channelIndex, y: existing.y)) {
                    continue
                }
                if existing.y == y {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
        }
        guard channelIndex >= 0, channelIndex < soundChannels.count else { return }
        for existing in soundChannels[channelIndex].notes where existing.y == y {
            if leaving.contains(MirrorNoteKey(channelIndex: channelIndex, y: existing.y)) {
                continue
            }
            throw BmsONEDocumentError.parse("Overlapping notes")
        }
    }

    private struct EraseBgaKey: Hashable {
        var lane: BmsonChartMapping.BgaLane
        var y: Int64
    }

    private enum FindDeleteTarget {
        case sound(channel: Int, y: Int64)
        case bpm(y: Int64)
        case stop(y: Int64)
        case bga(lane: BmsonChartMapping.BgaLane, y: Int64)
    }

    private struct FindSoundMove {
        var channel: Int
        var y: Int64
        var x: Int64
        var l: Int64
        var c: Bool
        var extra: String
    }

    private struct FindBgaTarget {
        var lane: BmsonChartMapping.BgaLane
        var y: Int64
    }

    private struct FindTimingTarget {
        var isStop: Bool
        var y: Int64
    }

    private func resolveFindDeletes(_ identities: [Int]) throws -> [FindDeleteTarget] {
        var targets: [FindDeleteTarget] = []
        for identity in identities {
            switch BmsonChartMapping.findIdentity(identity) {
            case .sound(let channel, let noteIndex):
                let located = try soundNote(channel: channel, noteIndex: noteIndex)
                targets.append(.sound(channel: channel, y: located.y))
            case .bpm(let index):
                guard bpmNotes.indices.contains(index) else {
                    throw BmsONEDocumentError.parse("no BPM note at the requested pulse")
                }
                targets.append(.bpm(y: bpmNotes[index].y))
            case .stop(let index):
                guard stopNotes.indices.contains(index) else {
                    throw BmsONEDocumentError.parse("no STOP note at the requested pulse")
                }
                targets.append(.stop(y: stopNotes[index].y))
            case .bga(let lane, let index):
                let events = bgaEvents(on: lane)
                guard events.indices.contains(index) else {
                    throw BmsONEDocumentError.parse("no BGA event at the requested pulse")
                }
                targets.append(.bga(lane: lane, y: events[index].y))
            case nil:
                continue
            }
        }
        return targets
    }

    private func resolveFindSoundMoves(_ identities: [Int]) throws -> [FindSoundMove] {
        var moves: [FindSoundMove] = []
        for identity in identities {
            guard case .sound(let channel, let noteIndex) = BmsonChartMapping.findIdentity(identity) else {
                continue
            }
            let located = try soundNote(channel: channel, noteIndex: noteIndex)
            let extra = (try? bridge.noteExtraJSON(onChannel: UInt(channel), y: located.y)) ?? "{}"
            moves.append(
                FindSoundMove(
                    channel: channel,
                    y: located.y,
                    x: located.x,
                    l: located.l,
                    c: located.c,
                    extra: extra
                )
            )
        }
        return moves
    }

    private func resolveFindBgaTargets(_ identities: [Int]) throws -> [FindBgaTarget] {
        var targets: [FindBgaTarget] = []
        for identity in identities {
            guard case .bga(let lane, let index) = BmsonChartMapping.findIdentity(identity) else {
                continue
            }
            let events = bgaEvents(on: lane)
            guard events.indices.contains(index) else {
                throw BmsONEDocumentError.parse("no BGA event at the requested pulse")
            }
            targets.append(FindBgaTarget(lane: lane, y: events[index].y))
        }
        return targets
    }

    private func resolveFindTimingTargets(_ identities: [Int]) throws -> [FindTimingTarget] {
        var targets: [FindTimingTarget] = []
        for identity in identities {
            switch BmsonChartMapping.findIdentity(identity) {
            case .bpm(let index):
                guard bpmNotes.indices.contains(index) else {
                    throw BmsONEDocumentError.parse("no BPM note at the requested pulse")
                }
                targets.append(FindTimingTarget(isStop: false, y: bpmNotes[index].y))
            case .stop(let index):
                guard stopNotes.indices.contains(index) else {
                    throw BmsONEDocumentError.parse("no STOP note at the requested pulse")
                }
                targets.append(FindTimingTarget(isStop: true, y: stopNotes[index].y))
            default:
                continue
            }
        }
        return targets
    }

    private func soundNote(channel: Int, noteIndex: Int) throws -> IBMSBmsonNoteSnapshot {
        guard channel >= 0,
              channel < soundChannels.count,
              noteIndex >= 0,
              noteIndex < soundChannels[channel].notes.count
        else {
            throw BmsONEDocumentError.parse("no sound note at the requested pulse")
        }
        return soundChannels[channel].notes[noteIndex]
    }

    private func bgaEvents(on lane: BmsonChartMapping.BgaLane) -> [IBMSBmsonBgaEventSnapshot] {
        switch lane {
        case .bga: return bgaEvents
        case .layer: return layerEvents
        case .poor: return poorEvents
        }
    }

    /// 同一目标声道同一 `y` 已有别的音则拒绝，不要默默覆盖。
    /// 可玩车道重叠对照核心的 `Overlapping notes`。
    private func validateSoundMoves(_ moves: [FindSoundMove], destChannel: Int) throws {
        var destYs = Set<Int64>()
        for move in moves {
            if destYs.contains(move.y) {
                throw BmsONEDocumentError.parse("Overlapping notes")
            }
            destYs.insert(move.y)
        }
        let leaving = Set(moves.map { "\($0.channel):\($0.y)" })
        if destChannel < soundChannels.count {
            for note in soundChannels[destChannel].notes {
                if leaving.contains("\(destChannel):\(note.y)") { continue }
                if destYs.contains(note.y) {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
        }
        var remaining: [(x: Int64, y: Int64, l: Int64)] = []
        for (channelIndex, channel) in soundChannels.enumerated() {
            for note in channel.notes {
                if leaving.contains("\(channelIndex):\(note.y)") { continue }
                remaining.append((note.x, note.y, note.l))
            }
        }
        for move in moves where move.x > 0 {
            for existing in remaining where existing.x > 0 && existing.x == move.x {
                if existing.y <= move.y + move.l && move.y <= existing.y + existing.l {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
            remaining.append((move.x, move.y, move.l))
        }
    }

    /// `insert_sound_note` 在下标越界时会写到通道 0，必须先补空声道。
    /// `replace_sound_channels` 会清 extra，所以先读出来，补完再写回去。
    private func padSoundChannels(to count: Int) throws {
        let current = channelInputs()
        guard current.count < count else { return }
        var extras: [(channel: Int, y: Int64, json: String)] = []
        for (channelIndex, channel) in soundChannels.enumerated() {
            for note in channel.notes {
                extras.append(
                    (
                        channel: channelIndex,
                        y: note.y,
                        json: (try? bridge.noteExtraJSON(onChannel: UInt(channelIndex), y: note.y)) ?? "{}"
                    )
                )
            }
        }
        var next = current
        while next.count < count {
            next.append(BmsonChartMapping.ChannelInput(name: "", notes: []))
        }
        try replaceSoundChannels(next)
        for extra in extras {
            try bridge.replaceNoteExtraJSON(onChannel: UInt(extra.channel), y: extra.y, json: extra.json)
        }
    }

    func replaceInfo(_ fields: BmsonInfoFields) throws {
        try commitEdit {
            try applyInfo(fields)
        }
    }

    /// 共用 iBMSC `POBMirror`。只改声音音的车道 `x`，一次撤销。
    func mirrorNotes(identities: [Int], mode: BmsONEViewMode? = nil) throws {
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        var planned: [MirrorMove] = []
        var seen = Set<MirrorNoteKey>()
        for identity in identities {
            guard identity > 0 else { continue }
            guard let located = try? note(at: identity) else { continue }
            let key = MirrorNoteKey(channelIndex: located.channelIndex, y: located.note.y)
            if seen.contains(key) { continue }
            seen.insert(key)
            guard let source = viewMode.laneToChannel[located.note.x] else { continue }
            guard let destChannel = ChartConvert.mirrorChannel(source) else { continue }
            guard let destX = viewMode.channelToLane[destChannel] else { continue }
            if destX == located.note.x { continue }
            planned.append(
                MirrorMove(channelIndex: located.channelIndex, note: located.note, destX: destX)
            )
        }
        guard !planned.isEmpty else { return }
        try validateMirrorMoves(planned)
        let snapshot = try jsonString()
        do {
            try commitEdit {
                for (index, move) in planned.enumerated() {
                    try bridge.replaceSoundNote(
                        onChannel: UInt(move.channelIndex),
                        oldY: move.note.y,
                        x: 1_000_000 + Int64(index),
                        y: move.note.y,
                        l: move.note.l,
                        c: move.note.c
                    )
                }
                for move in planned {
                    try bridge.replaceSoundNote(
                        onChannel: UInt(move.channelIndex),
                        oldY: move.note.y,
                        x: move.destX,
                        y: move.note.y,
                        l: move.note.l,
                        c: move.note.c
                    )
                }
            }
        } catch {
            if let restored = try? IBMSBmsonBridge(jsonString: snapshot) {
                bridge = restored
            }
            throw error
        }
    }

    /// 共用 iBMSC 数字键 `1`–`8`。只改声音音的车道 `x`，一次撤销。
    func moveNotes(
        identities: [Int],
        toDisplay display: String,
        shiftFirstOnly: Bool,
        mode: BmsONEViewMode? = nil
    ) throws {
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        guard let destX = viewMode.channelToLane[display] else { return }
        try applyLaneMoves(identities: identities, destX: destX, shiftFirstOnly: shiftFirstOnly)
    }

    /// 共用 iBMSC 数字键 `0`。写成 `x=0`，不发明第二列 B。
    func moveNotesToBGM(identities: [Int], mode: BmsONEViewMode? = nil) throws {
        _ = mode
        try applyLaneMoves(identities: identities, destX: 0, shiftFirstOnly: false)
    }

    /// 共用 iBMSC `POBHidden` / `POBVisible`。只改声音音的车道 `x`。
    /// 目标通道在当前 View Mode 没有车道则跳过，不写成 `x=0`。
    func convertNote(identity: Int, toChannel: String, mode: BmsONEViewMode? = nil) throws {
        guard identity > 0 else { return }
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        guard let destX = viewMode.channelToLane[toChannel] else { return }
        try applyLaneMoves(identities: [identity], destX: destX, shiftFirstOnly: false)
    }

    /// 菜单公式：用当前 `x` 换成显示通道，再 `ChartConvert.destinationChannel`。一次撤销。
    func convertHiddenNotes(
        identities: [Int],
        action: ChartConvert.HiddenAction,
        mode: BmsONEViewMode? = nil
    ) throws {
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        var planned: [MirrorMove] = []
        var seen = Set<MirrorNoteKey>()
        for identity in identities {
            guard identity > 0 else { continue }
            guard let located = try? note(at: identity) else { continue }
            let key = MirrorNoteKey(channelIndex: located.channelIndex, y: located.note.y)
            if seen.contains(key) { continue }
            seen.insert(key)
            guard let source = viewMode.laneToChannel[located.note.x] else { continue }
            guard let destChannel = ChartConvert.destinationChannel(for: source, action: action) else {
                continue
            }
            guard let destX = viewMode.channelToLane[destChannel] else { continue }
            if destX == located.note.x { continue }
            planned.append(
                MirrorMove(channelIndex: located.channelIndex, note: located.note, destX: destX)
            )
        }
        try applyPlannedLaneMoves(planned)
    }

    /// 对照 `TransferSelectedNotesToBgm` / `ToKey`。一次撤销。
    func transferNotes(
        identities: [Int],
        toBGM: Bool,
        lanes: [Int64] = BmsONEPlayingLaneLayout.beat7kLaneXs
    ) throws {
        let selected = identities.compactMap { identity -> BmsonNoteTransfer.Address? in
            guard let located = try? note(at: identity) else { return nil }
            return BmsonNoteTransfer.Address(channel: located.channelIndex, y: located.note.y)
        }
        let notes = soundChannels.map { channel in
            channel.notes.map {
                BmsonNoteTransfer.Note(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
            }
        }
        let next: [[BmsonNoteTransfer.Note]]
        if toBGM {
            next = BmsonNoteTransfer.toBGM(selected: selected, channels: notes)
        } else {
            guard let moved = BmsonNoteTransfer.toKey(
                selected: selected,
                channels: notes,
                lanes: lanes
            ) else {
                throw BmsONEDocumentError.parse("no notes to move to key lanes")
            }
            next = moved
        }
        var payload: [BmsonChartMapping.ChannelInput] = []
        payload.reserveCapacity(soundChannels.count)
        for (index, channel) in soundChannels.enumerated() {
            payload.append(
                BmsonChartMapping.ChannelInput(
                    name: channel.name,
                    notes: next[index].map {
                        BmsonChartMapping.NoteInput(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
                    }
                )
            )
        }
        if next == notes { return }
        try commitEdit {
            try replaceSoundChannels(payload)
        }
    }

    /// 对照 `SeparateLayeredNotes`。一次撤销。
    func separateLayeredNotes(
        identities: [Int],
        lanes: [Int64] = BmsONEPlayingLaneLayout.beat7kLaneXs
    ) throws {
        let selected = identities.compactMap { identity -> BmsonNoteTransfer.Address? in
            guard let located = try? note(at: identity) else { return nil }
            return BmsonNoteTransfer.Address(channel: located.channelIndex, y: located.note.y)
        }
        let notes = soundChannels.map { channel in
            channel.notes.map {
                BmsonNoteTransfer.Note(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
            }
        }
        guard let next = BmsonNoteTransfer.separateLayered(
            selected: selected,
            channels: notes,
            lanes: lanes
        ) else {
            throw BmsONEDocumentError.parse("no notes to separate")
        }
        var payload: [BmsonChartMapping.ChannelInput] = []
        payload.reserveCapacity(soundChannels.count)
        for (index, channel) in soundChannels.enumerated() {
            payload.append(
                BmsonChartMapping.ChannelInput(
                    name: channel.name,
                    notes: next[index].map {
                        BmsonChartMapping.NoteInput(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
                    }
                )
            )
        }
        if next == notes { return }
        try commitEdit {
            try replaceSoundChannels(payload)
        }
    }

    /// 对照 `InsertBarLine`。已有线（含 4 拍虚线）返回 `false`，不记撤销。
    @discardableResult
    func insertBarLine(pulseY: Int64) -> Bool {
        let current = lines.map(\.y)
        guard let next = BmsonBarLine.insert(
            pulse: pulseY,
            lines: current,
            lastPulse: BmsonBeat.lastPulse(beatState()),
            resolution: resolution
        ) else {
            return false
        }
        if Set(next) == Set(current) || (next.isEmpty && current.isEmpty) {
            return false
        }
        do {
            try commitEdit {
                try replaceLines(next)
            }
            return true
        } catch {
            return false
        }
    }

    /// 对照 `InsertNewSoundChannels`。一次撤销。
    func addSoundChannels(paths: [String], at index: Int = -1) throws {
        let current = channelInputs()
        guard let next = BmsonChannel.add(names: paths, to: current, at: index) else {
            throw BmsONEDocumentError.parse("no sound channels to add")
        }
        try commitEdit {
            try replaceSoundChannels(next)
        }
    }

    /// 对照 `DestroySoundChannel`。整道连音符一起删，不是只清名字。
    @discardableResult
    func destroySoundChannel(at index: Int) -> Bool {
        let current = channelInputs()
        guard let next = BmsonChannel.destroy(index: index, in: current) else { return false }
        do {
            try commitEdit {
                try replaceSoundChannels(next)
            }
            selectedChannelIndex = BmsonChannel.selectionAfterDestroy(
                current: index,
                countBefore: current.count
            )
            return true
        } catch {
            return false
        }
    }

    /// 对照 `MoveSoundChannel`。成功后当前声道跟着走。
    @discardableResult
    func moveSoundChannel(from index: Int, to destination: Int) -> Bool {
        let current = channelInputs()
        guard let next = BmsonChannel.move(from: index, to: destination, in: current) else {
            return false
        }
        do {
            try commitEdit {
                try replaceSoundChannels(next)
            }
            selectedChannelIndex = min(max(0, destination), next.count - 1)
            return true
        } catch {
            return false
        }
    }

    /// 对照 `SetSourceFile`。只写文件名，音符不动。
    @discardableResult
    func setSoundChannelName(at index: Int, path: String) -> Bool {
        let current = channelInputs()
        guard let next = BmsonChannel.setName(index: index, path: path, in: current) else {
            return false
        }
        do {
            try commitEdit {
                try replaceSoundChannels(next)
            }
            return true
        } catch {
            return false
        }
    }

    /// 对照 `RemoveBarLine`。只能删写进 `lines[]` 的线；`y=0` 和 4 拍虚线会回来。
    @discardableResult
    func removeBarLine(pulseY: Int64) -> Bool {
        let current = lines.map(\.y)
        guard let next = BmsonBarLine.remove(
            pulse: pulseY,
            lines: current,
            lastPulse: BmsonBeat.lastPulse(beatState()),
            resolution: resolution
        ) else {
            return false
        }
        if Set(next) == Set(current) || (next.isEmpty && current.allSatisfy({ $0 == 0 })) {
            return false
        }
        do {
            try commitEdit {
                try replaceLines(next)
            }
            return true
        } catch {
            return false
        }
    }

    /// 同一套 Beat 侧栏。只改 `lines[]` 和脉冲，不写 `#mmm02`。
    func applyBeat(measures: [Int], decimal: String, mode: Int) throws {
        guard !measures.isEmpty else { return }
        guard let beatMode = LegacyBeat.Mode(rawValue: mode) else {
            throw BmsONEDocumentError.parse("unknown beat change mode")
        }
        guard let next = BmsonBeat.apply(
            measures: measures,
            decimal: decimal,
            mode: beatMode,
            to: beatState()
        ) else {
            throw BmsONEDocumentError.parse("measure ratio must be a positive decimal")
        }
        try commitEdit {
            try replaceLines(next.lines)
            try replaceSoundChannels(next.channels)
            try replaceTiming(next.bpmNotes, stops: next.stopNotes)
            try replaceBga(
                headers: bgaHeaders.map { BmsonBmpList.Header(id: Int($0.identifier), name: $0.name) },
                bgaEvents: next.bgaEvents,
                layerEvents: next.layerEvents,
                poorEvents: next.poorEvents
            )
        }
    }

    /// 同一套 BMP 侧栏。只改 `bga.bga_header` / 事件 `id`，不写 BMS `#BMP`。
    func applyBmpEdit(_ edit: WavListEdit, synchronizeLabels: Bool) throws {
        guard let next = BmsonBmpList.apply(
            edit,
            headers: bgaHeaders.map { BmsonBmpList.Header(id: Int($0.identifier), name: $0.name) },
            bgaEvents: bgaEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: Int($0.identifier)) },
            layerEvents: layerEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: Int($0.identifier)) },
            poorEvents: poorEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: Int($0.identifier)) },
            synchronizeLabels: synchronizeLabels
        ) else {
            throw BmsONEDocumentError.parse("invalid BMSON BMP list edit")
        }
        try commitEdit {
            try replaceBga(
                headers: next.headers,
                bgaEvents: next.bgaEvents,
                layerEvents: next.layerEvents,
                poorEvents: next.poorEvents
            )
        }
    }

    /// 同一套 WAV 侧栏。只改 `soundChannels`，不写 BMS `#WAV`。
    func applyWavEdit(_ edit: WavListEdit, synchronizeLabels: Bool) throws {
        guard let next = BmsonWavList.apply(
            edit,
            to: BmsonWavList.channels(from: soundChannels),
            synchronizeLabels: synchronizeLabels
        ) else {
            throw BmsONEDocumentError.parse("invalid BMSON WAV list edit")
        }
        try commitEdit {
            try replaceSoundChannels(next)
        }
    }

    /// BmsONE `ConvertResolution`。脉冲按整数 `y * new / old` 换算。
    func convertResolution(_ newResolution: Int) throws {
        if newResolution == resolution {
            return
        }
        try commitEdit {
            try bridge.convertResolution(newResolution)
        }
    }

    func resolutionConversionLosesInformation(_ newResolution: Int) -> Bool {
        bridge.resolutionConversionLosesInformation(newResolution)
    }

    var acceptableResolutionDivider: Int { bridge.acceptableResolutionDivider() }

    func infoExtraString(_ key: String) -> String {
        bridge.infoExtraString(forKey: key)
    }

    /// 对照 `InfoView::SetExtraFields`。不含 banner 等官方图键。
    func infoExtraFieldsText() -> String {
        BmsonSelectedObjects.formatExtraFields(objectJSON: bridge.infoExtraObjectJSON())
    }

    /// 对照 `InfoView::ExtraFieldsEdited`。非法 JSON 返回 false，不记撤销。
    @discardableResult
    func applyInfoExtraFields(_ text: String) -> Bool {
        guard let objectJSON = BmsonSelectedObjects.preparedExtraObjectJSON(text) else {
            return false
        }
        if infoExtraFieldsText() == BmsonSelectedObjects.formatExtraFields(objectJSON: objectJSON) {
            return true
        }
        do {
            try commitEdit {
                try bridge.replaceInfoExtraObjectJSON(objectJSON)
            }
            return true
        } catch {
            return false
        }
    }

    func infoExtras() -> [String: String] {
        Dictionary(uniqueKeysWithValues: BmsonHeaderMapping.infoExtraJSONKeys.map { key in
            (key, infoExtraString(key))
        })
    }

    func headerFields() -> [String: String] {
        BmsonHeaderMapping.fields(from: info, extras: infoExtras())
    }

    func replaceHeader(key: String, value: String) throws {
        if let extraKey = BmsonHeaderMapping.infoExtraJSONKey(forHeader: key) {
            if infoExtraString(extraKey) == value {
                return
            }
            try commitEdit {
                try bridge.setInfoExtraString(value, forKey: extraKey)
            }
            return
        }
        var fields = BmsonInfoFields(info)
        let before = fields
        guard BmsonHeaderMapping.apply(key: key, value: value, to: &fields) else {
            throw BmsONEDocumentError.parse("unsupported BMSON header field")
        }
        if fields == before {
            return
        }
        try replaceInfo(fields)
    }

    /// 共用 iBMSC 剪贴板。只编码声音音。`identity == 0` 当作声道 0 第 0 颗。
    /// NT 关掉时只写起点短音；NT 打开时 Length 用 vpos。
    func copyClipboard(
        identities: [Int],
        ntInput: Bool,
        mode: BmsONEViewMode? = nil
    ) -> String {
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        let safeResolution = max(resolution, 1)
        var notes: [LegacyClipboardNote] = []
        for raw in identities {
            let identity = raw == 0
                ? BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
                : raw
            guard identity > 0, let located = try? note(at: identity) else { continue }
            let channel: String
            if located.note.x == 0 {
                channel = "01"
            } else if let mapped = viewMode.laneToChannel[located.note.x] {
                channel = mapped
            } else {
                continue
            }
            let length = ntInput
                ? Double(located.note.l) * 48.0 / Double(safeResolution)
                : 0
            notes.append(
                LegacyClipboardNote(
                    columnIndex: LegacyClipboard.columnIndex(forChannel: channel),
                    vPosition: Double(located.note.y) * 48.0 / Double(safeResolution),
                    value: (located.channelIndex + 1) * 10_000,
                    length: length,
                    longNote: false,
                    hidden: false,
                    landmine: false
                )
            )
        }
        return LegacyClipboard.encode(notes, ntInput: ntInput)
    }

    /// 共用 iBMSC 剪贴板。追加写入，一次撤销。Hidden 走可见列，不写成 `x=0`。
    func pasteClipboard(
        _ text: String,
        baseVPosition: Double,
        ntInput: Bool,
        mode: BmsONEViewMode? = nil
    ) throws {
        guard let payload = LegacyClipboard.decode(text) else { return }
        var notes = payload.notes
        if ntInput && payload.format != .ibmscNT {
            notes = LegacyClipboard.convertBMSE2NT(notes)
        } else if !ntInput && payload.format == .ibmscNT {
            notes = LegacyClipboard.convertNT2BMSE(notes)
        }
        try writeClipboardNotes(
            LegacyClipboard.placed(notes, baseVPosition: baseVPosition),
            mode: mode ?? BmsONEViewMode.resolve(modeHint)
        )
    }

    /// 选择模式拖动搬移。原音搬走，一次撤销。不用 `laneX` 缺键默认 0。
    struct VPositionMove: Equatable {
        var identity: Int?
        var channel: String
        var destChannel: String
        var destVPosition: Double
    }

    func moveNotesAtVPosition(
        shorts: [ChartDuplicate.ShortCopy],
        longs: [ChartDuplicate.LongCopy],
        mode: BmsONEViewMode? = nil
    ) throws {
        var moves: [VPositionMove] = shorts.map {
            VPositionMove(
                identity: $0.event.sourceLine,
                channel: $0.event.channel,
                destChannel: $0.channel,
                destVPosition: $0.vPosition
            )
        }
        moves += longs.map {
            VPositionMove(
                identity: $0.note.start.sourceLine,
                channel: $0.note.channel,
                destChannel: $0.channel,
                destVPosition: $0.vPosition
            )
        }
        try moveNotesAtVPosition(moves, mode: mode)
    }

    func moveNotesAtVPosition(
        _ notes: [(identity: Int?, channel: String, destChannel: String, destVPosition: Double)],
        mode: BmsONEViewMode? = nil
    ) throws {
        try moveNotesAtVPosition(
            notes.map {
                VPositionMove(
                    identity: $0.identity,
                    channel: $0.channel,
                    destChannel: $0.destChannel,
                    destVPosition: $0.destVPosition
                )
            },
            mode: mode
        )
    }

    func moveNotesAtVPosition(_ notes: [VPositionMove], mode: BmsONEViewMode? = nil) throws {
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        var soundMoves: [SoundVMove] = []
        var seenSound = Set<SoundNoteKey>()
        var seenSoundIdentity = Set<Int>()
        var bpmMoves: [(oldY: Int64, newY: Int64, v: Double)] = []
        var seenBpm = Set<Int64>()
        var stopMoves: [(oldY: Int64, newY: Int64, v: Double)] = []
        var seenStop = Set<Int64>()
        var bgaMoves: [(lane: BmsonChartMapping.BgaLane, oldY: Int64, newY: Int64, id: Int)] = []
        var seenBga = Set<EraseBgaKey>()

        for item in notes {
            if item.destVPosition < 0 { continue }
            let source = item.channel.uppercased()
            let dest = item.destChannel.uppercased()
            if source == "SC" || dest == "SC" {
                continue
            }
            let destY = BmsonTimeSelection.pulse(vPosition: item.destVPosition, resolution: resolution)

            if let raw = item.identity, raw >= 0 {
                let identity = raw == 0
                    ? BmsonChartMapping.noteIdentity(channelIndex: 0, noteIndex: 0)
                    : raw
                if !seenSoundIdentity.insert(identity).inserted { continue }
                guard let located = try? note(at: identity) else { continue }
                let key = SoundNoteKey(channelIndex: located.channelIndex, x: located.note.x, y: located.note.y)
                if seenSound.contains(key) { continue }
                guard let destX = playableDestLaneX(dest, mode: viewMode) else { continue }
                if destX == located.note.x && destY == located.note.y { continue }
                seenSound.insert(key)
                soundMoves.append(
                    SoundVMove(
                        channelIndex: located.channelIndex,
                        note: located.note,
                        destX: destX,
                        destY: destY
                    )
                )
                continue
            }

            if let raw = item.identity, let found = BmsonChartMapping.findIdentity(raw) {
                switch found {
                case .sound:
                    break
                case .bpm(let index):
                    guard bpmNotes.indices.contains(index) else { continue }
                    let event = bpmNotes[index]
                    if !seenBpm.insert(event.y).inserted { continue }
                    if destY == event.y { continue }
                    bpmMoves.append((event.y, destY, event.v))
                case .stop(let index):
                    guard stopNotes.indices.contains(index) else { continue }
                    let event = stopNotes[index]
                    if !seenStop.insert(event.y).inserted { continue }
                    if destY == event.y { continue }
                    stopMoves.append((event.y, destY, event.v))
                case .bga(let lane, let index):
                    let events = bgaEvents(on: lane)
                    guard events.indices.contains(index) else { continue }
                    let event = events[index]
                    let key = EraseBgaKey(lane: lane, y: event.y)
                    if !seenBga.insert(key).inserted { continue }
                    if destY == event.y { continue }
                    bgaMoves.append((lane, event.y, destY, Int(event.identifier)))
                }
                continue
            }

            if source == "03" || source == "08" {
                guard let event = bpmNotes.first(where: { !seenBpm.contains($0.y) }) else { continue }
                seenBpm.insert(event.y)
                if destY != event.y {
                    bpmMoves.append((event.y, destY, event.v))
                }
                continue
            }
            if source == "09" {
                guard let event = stopNotes.first(where: { !seenStop.contains($0.y) }) else { continue }
                seenStop.insert(event.y)
                if destY != event.y {
                    stopMoves.append((event.y, destY, event.v))
                }
                continue
            }
            if let lane = BmsonChartMapping.BgaLane.parse(channel: source) {
                guard let event = bgaEvents(on: lane).first(where: {
                    !seenBga.contains(EraseBgaKey(lane: lane, y: $0.y))
                }) else { continue }
                seenBga.insert(EraseBgaKey(lane: lane, y: event.y))
                if destY != event.y {
                    bgaMoves.append((lane, event.y, destY, Int(event.identifier)))
                }
            }
        }

        guard !soundMoves.isEmpty
            || !bpmMoves.isEmpty
            || !stopMoves.isEmpty
            || !bgaMoves.isEmpty
        else {
            return
        }
        try validateSoundVMoves(soundMoves)
        try commitEditRestoring {
            if !soundMoves.isEmpty {
                try applySoundVMoves(soundMoves)
            }
            for bpm in bpmMoves {
                try bridge.upsertBpmNote(y: bpm.newY, v: bpm.v)
                if bpm.oldY != bpm.newY {
                    try bridge.eraseBpmNote(y: bpm.oldY)
                }
            }
            for stop in stopMoves {
                try bridge.upsertStopNote(y: stop.newY, v: stop.v)
                if stop.oldY != stop.newY {
                    try bridge.eraseStopNote(y: stop.oldY)
                }
            }
            for event in bgaMoves {
                try bridge.upsertBgaEvent(
                    onLane: event.lane.rawValue,
                    y: event.newY,
                    identifier: Int32(event.id)
                )
                if event.oldY != event.newY {
                    try bridge.eraseBgaEvent(onLane: event.lane.rawValue, y: event.oldY)
                }
            }
        }
    }

    /// 可玩列用 `channelToLane`。没有车道就跳过，不写成 `x=0`。BGM 才是 `x=0`。
    private func playableDestLaneX(_ destChannel: String, mode: BmsONEViewMode) -> Int64? {
        let dest = destChannel.uppercased()
        if dest == "SC" || dest == "03" || dest == "08" || dest == "09" {
            return nil
        }
        if BmsonChartMapping.BgaLane.parse(channel: dest) != nil {
            return nil
        }
        if dest == "01" || ChartBGM.lane(display: dest) != nil {
            return 0
        }
        let visible = ChartLayout.displayChannel(dest)
        if visible == "01" || ChartBGM.lane(display: visible) != nil {
            return 0
        }
        return mode.channelToLane[visible]
    }

    /// 选择模式 Ctrl 拖复制。追加写入，一次撤销。规则与 `pasteClipboard` 相同。
    /// Hidden / Mine / `5x` 通道按可见列写，不用 `laneX` 缺键默认 0。
    func duplicateNotes(
        _ notes: [(channel: String, vPosition: Double, token: String, length: Double)],
        mode: BmsONEViewMode? = nil
    ) throws {
        let converted = notes.map { item -> LegacyClipboardNote in
            let flags = LegacyClipboard.flags(forChannel: item.channel)
            return LegacyClipboardNote(
                columnIndex: LegacyClipboard.columnIndex(forChannel: item.channel),
                vPosition: item.vPosition,
                value: duplicateClipboardValue(token: item.token, destChannel: item.channel),
                length: item.length,
                longNote: flags.longNote,
                hidden: flags.hidden,
                landmine: flags.landmine
            )
        }
        try writeClipboardNotes(converted, mode: mode ?? BmsONEViewMode.resolve(modeHint))
    }

    private func duplicateClipboardValue(token: String, destChannel: String) -> Int {
        let dest = destChannel.uppercased()
        if dest == "03" || dest == "08" || dest == "09" || dest == "SC" {
            return LegacyClipboard.numericValue(token)
        }
        return LegacyClipboard.tokenValue(token)
    }

    private func writeClipboardNotes(_ notes: [LegacyClipboardNote], mode: BmsONEViewMode) throws {
        let accepted = notes.compactMap {
            note -> (vPosition: Double, columnIndex: Int, value: Int, length: Double)? in
            guard note.vPosition >= 0 else { return nil }
            guard acceptsClipboardColumn(note.columnIndex, mode: mode) else { return nil }
            return (note.vPosition, note.columnIndex, note.value, note.length)
        }
        let planned = BmsonTimeSelection.plan(
            notes: accepted,
            resolution: resolution,
            mode: mode,
            preserveStartBpm: false,
            initialBpm: initialBpm
        )
        var allowedBgm: Set<[Int64]> = []
        for note in accepted where note.columnIndex >= BmsonTimeSelection.bgm {
            let channelIndex = Int64(max(0, note.value / 10_000 - 1))
            let y = BmsonTimeSelection.pulse(vPosition: note.vPosition, resolution: resolution)
            allowedBgm.insert([channelIndex, y])
        }
        let sounds = planned.sounds.filter { sound in
            if sound.x != 0 { return true }
            return allowedBgm.contains([Int64(sound.channelIndex), sound.y])
        }
        let hasWork = !sounds.isEmpty
            || !planned.bpmNotes.isEmpty
            || !planned.stopNotes.isEmpty
            || !planned.bgaEvents.isEmpty
            || !planned.layerEvents.isEmpty
            || !planned.poorEvents.isEmpty
        guard hasWork else { return }
        try validatePasteSounds(sounds)
        try commitEditRestoring {
            try appendClipboardSounds(sounds)
            for bpm in planned.bpmNotes {
                try bridge.upsertBpmNote(y: bpm.y, v: bpm.v)
            }
            for stop in planned.stopNotes {
                try bridge.upsertStopNote(y: stop.y, v: stop.v)
            }
            try writeClipboardBga(planned.bgaEvents, lane: .bga)
            try writeClipboardBga(planned.layerEvents, lane: .layer)
            try writeClipboardBga(planned.poorEvents, lane: .poor)
        }
    }

    /// `insert_sound_note` 同一声道同一脉冲会改掉原音。复制必须追加。
    private func appendClipboardSounds(_ sounds: [BmsonTimeSelection.SoundWrite]) throws {
        guard !sounds.isEmpty else { return }
        var extras: [(channel: Int, y: Int64, json: String)] = []
        for (channelIndex, channel) in soundChannels.enumerated() {
            for note in channel.notes {
                extras.append(
                    (
                        channel: channelIndex,
                        y: note.y,
                        json: (try? bridge.noteExtraJSON(onChannel: UInt(channelIndex), y: note.y)) ?? "{}"
                    )
                )
            }
        }
        var channels = channelInputs()
        let needed = sounds.map(\.channelIndex).max().map { $0 + 1 } ?? 0
        while channels.count < needed {
            channels.append(BmsonChartMapping.ChannelInput(name: "", notes: []))
        }
        for sound in sounds {
            channels[sound.channelIndex].notes.append(
                BmsonChartMapping.NoteInput(x: sound.x, y: sound.y, l: sound.l, c: false)
            )
        }
        try replaceSoundChannels(channels)
        for extra in extras {
            try bridge.replaceNoteExtraJSON(onChannel: UInt(extra.channel), y: extra.y, json: extra.json)
        }
    }

    /// 可玩列必须在当前 View Mode 有车道。SCROLL 不写。BGM 列允许 `x=0`。
    private func acceptsClipboardColumn(_ column: Int, mode: BmsONEViewMode) -> Bool {
        if column == BmsonTimeSelection.scroll {
            return false
        }
        if column == BmsonTimeSelection.bpm || column == BmsonTimeSelection.stop {
            return true
        }
        if column == BmsonTimeSelection.bga
            || column == BmsonTimeSelection.layer
            || column == BmsonTimeSelection.poor
        {
            return true
        }
        if column >= BmsonTimeSelection.bgm {
            return true
        }
        let playable = (BmsonTimeSelection.a1...BmsonTimeSelection.a8).contains(column)
            || (BmsonTimeSelection.d1...BmsonTimeSelection.d8).contains(column)
        guard playable else { return false }
        return mode.channelToLane[BmsonTimeSelection.shortChannel(for: column)] != nil
    }

    private func validatePasteSounds(_ sounds: [BmsonTimeSelection.SoundWrite]) throws {
        for sound in sounds where sound.x > 0 {
            for channel in soundChannels {
                for existing in channel.notes where existing.x > 0 && existing.x == sound.x {
                    if pulsesOverlap(existing.y, existing.l, sound.y, sound.l) {
                        throw BmsONEDocumentError.parse("Overlapping notes")
                    }
                }
            }
        }
        for index in 0..<sounds.count {
            guard sounds[index].x > 0 else { continue }
            for other in (index + 1)..<sounds.count {
                guard sounds[other].x == sounds[index].x else { continue }
                if pulsesOverlap(
                    sounds[index].y,
                    sounds[index].l,
                    sounds[other].y,
                    sounds[other].l
                ) {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
        }
    }

    private func writeClipboardBga(
        _ events: [BmsonTimeSelection.BgaWrite],
        lane: BmsonChartMapping.BgaLane
    ) throws {
        for event in events {
            try bridge.upsertBgaEvent(onLane: lane.rawValue, y: event.y, identifier: Int32(event.id))
            if !bgaHeaders.contains(where: { Int($0.identifier) == event.id }) {
                try bridge.upsertBgaHeader(identifier: Int32(event.id), name: "")
            }
        }
    }

    /// 时间选择 / MyO2 一次写回。`vPosition < 0` 的只用于头 BPM，不写进 `bpmNotes`。
    func applyChartNotes(
        _ notes: [(vPosition: Double, columnIndex: Int, value: Int, length: Double)],
        initialBpm: Double,
        mode: BmsONEViewMode? = nil
    ) throws {
        guard initialBpm > 0, initialBpm.isFinite else {
            throw BmsONEDocumentError.parse("initBPM must be positive")
        }
        let viewMode = mode ?? BmsONEViewMode.resolve(modeHint)
        let hadStartNote = bpmNotes.contains { $0.y == 0 }
        let planned = BmsonTimeSelection.plan(
            notes: notes,
            resolution: resolution,
            mode: viewMode,
            preserveStartBpm: hadStartNote,
            initialBpm: initialBpm
        )
        var fields = BmsonInfoFields(info)
        fields.initBPM = initialBpm
        var channels = soundChannels.map {
            BmsonChartMapping.ChannelInput(name: $0.name, notes: [])
        }
        let needed = planned.sounds.map(\.channelIndex).max().map { $0 + 1 } ?? 0
        while channels.count < needed {
            channels.append(BmsonChartMapping.ChannelInput(name: "", notes: []))
        }
        var headers = bgaHeaders.map { BmsonBmpList.Header(id: Int($0.identifier), name: $0.name) }
        let usedIds = Set(
            planned.bgaEvents.map(\.id) + planned.layerEvents.map(\.id) + planned.poorEvents.map(\.id)
        )
        for identifier in usedIds.sorted() where !headers.contains(where: { $0.id == identifier }) {
            headers.append(BmsonBmpList.Header(id: identifier, name: ""))
        }
        try commitEdit {
            try applyInfo(fields)
            try replaceSoundChannels(channels)
            for sound in planned.sounds {
                try bridge.insertSoundNote(
                    onChannel: UInt(sound.channelIndex),
                    x: sound.x,
                    y: sound.y,
                    l: sound.l,
                    c: false
                )
            }
            try replaceTiming(
                planned.bpmNotes.map { BmsonBeat.Timing(y: $0.y, v: $0.v) },
                stops: planned.stopNotes.map { BmsonBeat.Timing(y: $0.y, v: $0.v) }
            )
            try replaceBga(
                headers: headers,
                bgaEvents: planned.bgaEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: $0.id) },
                layerEvents: planned.layerEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: $0.id) },
                poorEvents: planned.poorEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: $0.id) }
            )
        }
    }

    /// Header 的 BPM 写 `info.initBPM`。夹具里若已有 `y=0` 的 `bpmNotes`，同一笔一起改。
    func setInitialBPM(_ decimal: String) throws {
        guard let bpm = BmsonHeaderMapping.parseBPM(decimal) else {
            throw BmsONEDocumentError.parse("initBPM must be positive")
        }
        var fields = BmsonInfoFields(info)
        fields.initBPM = bpm
        let hasStartNote = bpmNotes.contains { $0.y == 0 }
        try commitEdit {
            try applyInfo(fields)
            if hasStartNote {
                try bridge.upsertBpmNote(y: 0, v: bpm)
            }
        }
    }

    private func channelInputs() -> [BmsonChartMapping.ChannelInput] {
        soundChannels.map { channel in
            BmsonChartMapping.ChannelInput(
                name: channel.name,
                notes: channel.notes.map {
                    BmsonChartMapping.NoteInput(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
                }
            )
        }
    }

    private func beatState() -> BmsonBeat.State {
        BmsonBeat.State(
            lines: lines.map(\.y),
            channels: soundChannels.map { channel in
                BmsonChartMapping.ChannelInput(
                    name: channel.name,
                    notes: channel.notes.map {
                        BmsonChartMapping.NoteInput(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
                    }
                )
            },
            bpmNotes: bpmNotes.map { BmsonBeat.Timing(y: $0.y, v: $0.v) },
            stopNotes: stopNotes.map { BmsonBeat.Timing(y: $0.y, v: $0.v) },
            bgaEvents: bgaEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: Int($0.identifier)) },
            layerEvents: layerEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: Int($0.identifier)) },
            poorEvents: poorEvents.map { BmsonBeat.BgaEvent(y: $0.y, id: Int($0.identifier)) },
            resolution: resolution
        )
    }

    private func replaceLines(_ pulses: [Int64]) throws {
        try bridge.replaceLines(pulses.map { NSNumber(value: $0) })
    }

    private func replaceTiming(_ bpm: [BmsonBeat.Timing], stops: [BmsonBeat.Timing]) throws {
        try bridge.replaceBpmNotes(bpm.map { event in
            let item = IBMSBmsonTimingFields()
            item.y = event.y
            item.v = event.v
            return item
        })
        try bridge.replaceStopNotes(stops.map { event in
            let item = IBMSBmsonTimingFields()
            item.y = event.y
            item.v = event.v
            return item
        })
    }

    private func replaceBga(
        headers: [BmsonBmpList.Header],
        bgaEvents: [BmsonBeat.BgaEvent],
        layerEvents: [BmsonBeat.BgaEvent],
        poorEvents: [BmsonBeat.BgaEvent]
    ) throws {
        try bridge.replaceBga(
            headers: headers.map { header in
                let item = IBMSBmsonBgaHeaderFields()
                item.identifier = Int32(header.id)
                item.name = header.name
                return item
            },
            bgaEvents: bgaEventFields(bgaEvents),
            layerEvents: bgaEventFields(layerEvents),
            poorEvents: bgaEventFields(poorEvents)
        )
    }

    private func bgaEventFields(_ events: [BmsonBeat.BgaEvent]) -> [IBMSBmsonBgaEventFields] {
        events.map { event in
            let item = IBMSBmsonBgaEventFields()
            item.y = event.y
            item.identifier = Int32(event.id)
            return item
        }
    }

    private func replaceSoundChannels(_ channels: [BmsonChartMapping.ChannelInput]) throws {
        let payload: [IBMSBmsonSoundChannelFields] = channels.map { channel in
            let item = IBMSBmsonSoundChannelFields()
            item.name = channel.name
            item.notes = channel.notes.map { note in
                let written = IBMSBmsonNoteFields()
                written.x = note.x
                written.y = note.y
                written.l = note.l
                written.c = note.c
                return written
            }
            return item
        }
        try bridge.replaceSoundChannels(payload)
    }

    private func applyInfo(_ fields: BmsonInfoFields) throws {
        let payload = IBMSBmsonInfoFields()
        payload.title = fields.title
        payload.subtitle = fields.subtitle
        payload.artist = fields.artist
        payload.subartists = fields.subartists
        payload.genre = fields.genre
        payload.modeHint = fields.modeHint
        payload.chartName = fields.chartName
        payload.level = fields.level
        payload.initBPM = fields.initBPM
        payload.judgeRank = fields.judgeRank
        payload.total = fields.total
        payload.resolution = fields.resolution
        try bridge.replaceInfo(payload)
    }

    func jsonString() throws -> String {
        do {
            return try bridge.jsonString()
        } catch {
            throw BmsONEDocumentError.serialize(error.localizedDescription)
        }
    }

    func undo() -> Bool {
        guard let previous = undoJSON.popLast() else { return false }
        guard let current = try? jsonString(),
              let restored = try? IBMSBmsonBridge(jsonString: previous)
        else {
            undoJSON.append(previous)
            return false
        }
        redoJSON.append(current)
        bridge = restored
        refreshModified()
        return true
    }

    func redo() -> Bool {
        guard let next = redoJSON.popLast() else { return false }
        guard let current = try? jsonString(),
              let restored = try? IBMSBmsonBridge(jsonString: next)
        else {
            redoJSON.append(next)
            return false
        }
        undoJSON.append(current)
        bridge = restored
        refreshModified()
        return true
    }

    func save(to url: URL) throws {
        let text = try jsonString()
        try text.write(to: url, atomically: true, encoding: .utf8)
        filePath = url.path
        cleanJSON = text
        hasSavedClean = true
        isModified = false
    }

    func save() throws {
        guard let filePath else {
            throw BmsONEDocumentError.io("This BMSON document has no file path.")
        }
        try save(to: URL(fileURLWithPath: filePath))
    }

    private func commitEdit(_ body: () throws -> Void) throws {
        let before = try jsonString()
        do {
            try body()
        } catch {
            // Bridge mutators are not transactional. Restore the complete document
            // before propagating the failure, including edits made before the throw.
            do {
                bridge = try IBMSBmsonBridge(jsonString: before)
            } catch {
                throw BmsONEDocumentError.parse("Edit failed and rollback failed: \(error.localizedDescription)")
            }
            throw BmsONEDocumentError.parse(error.localizedDescription)
        }
        undoJSON.append(before)
        redoJSON.removeAll()
        isModified = true
    }

    /// 写回中途失败时用 JSON 快照恢复，对照 `mirrorNotes`。
    private func commitEditRestoring(_ body: () throws -> Void) throws {
        try commitEdit(body)
    }

    private func refreshModified() {
        if !hasSavedClean {
            isModified = true
            return
        }
        isModified = ((try? jsonString()) ?? "") != cleanJSON
    }

    private func resolvedChannelIndex() -> Int {
        let count = soundChannels.count
        if count == 0 {
            return 0
        }
        if selectedChannelIndex >= 0 && selectedChannelIndex < count {
            return selectedChannelIndex
        }
        return 0
    }

    private struct MirrorMove {
        var channelIndex: Int
        var note: IBMSBmsonNoteSnapshot
        var destX: Int64
    }

    private struct SoundVMove {
        var channelIndex: Int
        var note: IBMSBmsonNoteSnapshot
        var destX: Int64
        var destY: Int64
    }

    private struct MirrorNoteKey: Hashable {
        var channelIndex: Int
        var y: Int64
    }

    private func applyLaneMoves(identities: [Int], destX: Int64, shiftFirstOnly: Bool) throws {
        var collected: [MirrorMove] = []
        var seen = Set<MirrorNoteKey>()
        for identity in identities {
            guard identity > 0 else { continue }
            guard let located = try? note(at: identity) else { continue }
            let key = MirrorNoteKey(channelIndex: located.channelIndex, y: located.note.y)
            if seen.contains(key) { continue }
            seen.insert(key)
            collected.append(
                MirrorMove(channelIndex: located.channelIndex, note: located.note, destX: destX)
            )
        }
        if shiftFirstOnly {
            collected.sort {
                if $0.note.y != $1.note.y { return $0.note.y < $1.note.y }
                return $0.channelIndex < $1.channelIndex
            }
            collected = Array(collected.prefix(1))
        }
        let planned = collected.filter { $0.note.x != destX }
        try applyPlannedLaneMoves(planned)
    }

    /// 两阶段搬到目标 `x`，占用预检和 `moveNotes` 同一套。
    private func applyPlannedLaneMoves(_ planned: [MirrorMove]) throws {
        guard !planned.isEmpty else { return }
        try validateLaneMoves(planned)
        let snapshot = try jsonString()
        do {
            try commitEdit {
                for (index, move) in planned.enumerated() {
                    try bridge.replaceSoundNote(
                        onChannel: UInt(move.channelIndex),
                        oldY: move.note.y,
                        x: 1_000_000 + Int64(index),
                        y: move.note.y,
                        l: move.note.l,
                        c: move.note.c
                    )
                }
                for move in planned {
                    try bridge.replaceSoundNote(
                        onChannel: UInt(move.channelIndex),
                        oldY: move.note.y,
                        x: move.destX,
                        y: move.note.y,
                        l: move.note.l,
                        c: move.note.c
                    )
                }
            }
        } catch {
            if let restored = try? IBMSBmsonBridge(jsonString: snapshot) {
                bridge = restored
            }
            throw error
        }
    }

    private struct SoundNoteKey: Hashable {
        var channelIndex: Int
        var x: Int64
        var y: Int64
    }

    /// 整表写回声音音，避免同一声道同一 `y` 上 `replaceSoundNote` 互相覆盖。
    /// extra 先按原 `y` 读出，写完再按目标 `y` 放回去。
    private func applySoundVMoves(_ planned: [SoundVMove]) throws {
        var destByKey: [SoundNoteKey: (x: Int64, y: Int64)] = [:]
        for move in planned {
            destByKey[SoundNoteKey(channelIndex: move.channelIndex, x: move.note.x, y: move.note.y)] = (
                move.destX,
                move.destY
            )
        }
        var extras: [(channel: Int, y: Int64, json: String)] = []
        var channels = channelInputs()
        for (channelIndex, channel) in channels.enumerated() {
            for index in channel.notes.indices {
                let note = channels[channelIndex].notes[index]
                let extra = (try? bridge.noteExtraJSON(onChannel: UInt(channelIndex), y: note.y)) ?? "{}"
                let key = SoundNoteKey(channelIndex: channelIndex, x: note.x, y: note.y)
                if let dest = destByKey[key] {
                    channels[channelIndex].notes[index].x = dest.x
                    channels[channelIndex].notes[index].y = dest.y
                    extras.append((channel: channelIndex, y: dest.y, json: extra))
                } else {
                    extras.append((channel: channelIndex, y: note.y, json: extra))
                }
            }
        }
        try replaceSoundChannels(channels)
        for extra in extras where extra.json != "{}" {
            try bridge.replaceNoteExtraJSON(onChannel: UInt(extra.channel), y: extra.y, json: extra.json)
        }
    }

    /// 可玩列占用预检。搬走的原位不算占用。对调同一脉冲先预检再两阶段搬。
    private func validateSoundVMoves(_ planned: [SoundVMove]) throws {
        let leaving = Set(planned.map { SoundNoteKey(channelIndex: $0.channelIndex, x: $0.note.x, y: $0.note.y) })
        for move in planned where move.destX > 0 {
            for (channelIndex, channel) in soundChannels.enumerated() {
                for existing in channel.notes where existing.x == move.destX && existing.x > 0 {
                    if leaving.contains(SoundNoteKey(channelIndex: channelIndex, x: existing.x, y: existing.y)) {
                        continue
                    }
                    if pulsesOverlap(existing.y, existing.l, move.destY, move.note.l) {
                        throw BmsONEDocumentError.parse("Overlapping notes")
                    }
                }
            }
        }
        for index in 0..<planned.count {
            guard planned[index].destX > 0 else { continue }
            for other in (index + 1)..<planned.count {
                guard planned[other].destX == planned[index].destX else { continue }
                if pulsesOverlap(
                    planned[index].destY,
                    planned[index].note.l,
                    planned[other].destY,
                    planned[other].note.l
                ) {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
        }
    }

    /// 可玩列按镜像同一套占用预检。BGM 只查同一声道。
    private func validateLaneMoves(_ planned: [MirrorMove]) throws {
        let leaving = Set(planned.map { MirrorNoteKey(channelIndex: $0.channelIndex, y: $0.note.y) })
        for move in planned {
            if move.destX > 0 {
                for (channelIndex, channel) in soundChannels.enumerated() {
                    for existing in channel.notes where existing.x == move.destX && existing.x > 0 {
                        if leaving.contains(MirrorNoteKey(channelIndex: channelIndex, y: existing.y)) {
                            continue
                        }
                        if pulsesOverlap(existing.y, existing.l, move.note.y, move.note.l) {
                            throw BmsONEDocumentError.parse("Overlapping notes")
                        }
                    }
                }
            } else if move.channelIndex >= 0, move.channelIndex < soundChannels.count {
                for existing in soundChannels[move.channelIndex].notes where existing.x <= 0 {
                    if leaving.contains(MirrorNoteKey(channelIndex: move.channelIndex, y: existing.y)) {
                        continue
                    }
                    if pulsesOverlap(existing.y, existing.l, move.note.y, move.note.l) {
                        throw BmsONEDocumentError.parse("Overlapping notes")
                    }
                }
            }
        }
        for index in 0..<planned.count {
            for other in (index + 1)..<planned.count {
                if planned[index].destX > 0 {
                    guard planned[index].destX == planned[other].destX else { continue }
                } else {
                    guard planned[index].channelIndex == planned[other].channelIndex else { continue }
                }
                if pulsesOverlap(
                    planned[index].note.y,
                    planned[index].note.l,
                    planned[other].note.y,
                    planned[other].note.l
                ) {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
        }
    }

    /// 目标车道上、脉冲重叠、且不会被这次镜像搬走的音 → `Overlapping notes`。
    private func validateMirrorMoves(_ planned: [MirrorMove]) throws {
        let leaving = Set(planned.map { MirrorNoteKey(channelIndex: $0.channelIndex, y: $0.note.y) })
        for move in planned {
            for (channelIndex, channel) in soundChannels.enumerated() {
                for existing in channel.notes where existing.x == move.destX && existing.x > 0 {
                    if leaving.contains(MirrorNoteKey(channelIndex: channelIndex, y: existing.y)) {
                        continue
                    }
                    if pulsesOverlap(existing.y, existing.l, move.note.y, move.note.l) {
                        throw BmsONEDocumentError.parse("Overlapping notes")
                    }
                }
            }
        }
        for index in 0..<planned.count {
            for other in (index + 1)..<planned.count {
                guard planned[index].destX == planned[other].destX else { continue }
                if pulsesOverlap(
                    planned[index].note.y,
                    planned[index].note.l,
                    planned[other].note.y,
                    planned[other].note.l
                ) {
                    throw BmsONEDocumentError.parse("Overlapping notes")
                }
            }
        }
    }

    private func pulsesOverlap(_ leftY: Int64, _ leftL: Int64, _ rightY: Int64, _ rightL: Int64) -> Bool {
        leftY <= rightY + rightL && rightY <= leftY + leftL
    }

    private func note(at identity: Int) throws -> (channelIndex: Int, note: IBMSBmsonNoteSnapshot) {
        guard let address = BmsonChartMapping.noteAddress(identity: identity),
              address.channelIndex >= 0,
              address.channelIndex < soundChannels.count,
              address.noteIndex >= 0,
              address.noteIndex < soundChannels[address.channelIndex].notes.count
        else {
            throw BmsONEDocumentError.parse("no sound note at the requested pulse")
        }
        return (address.channelIndex, soundChannels[address.channelIndex].notes[address.noteIndex])
    }
}

enum BmsONEDocumentError: LocalizedError {
    case parse(String)
    case serialize(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .parse(let message), .serialize(let message), .io(let message):
            return message
        }
    }
}
