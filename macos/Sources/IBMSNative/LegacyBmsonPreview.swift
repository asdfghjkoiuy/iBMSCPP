import Foundation

/// BMSON 预览：同一套播放器，时间表按脉冲 / `initBPM` / `bpmNotes` 算，不套 BMS 通道。
enum LegacyBmsonPreview {
    /// `x` / `l` 缺省是 0，旧的 `SoundNote(y:continueFlag:)` 仍能构造。
    /// `x <= 0` 是 BGM，不进键道；`l` 是长音脉冲。
    struct SoundNote: Equatable {
        var y: Int64
        var continueFlag: Bool
        var x: Int64 = 0
        var l: Int64 = 0
    }

    /// 交给预览窗的 BMSON 画面，以及没画上的键音数量。
    /// `partialDisplay` 非空表示这个模式有已定义车道接不到预览列。完整模式现在用独立列，正常是空串。
    struct VisualChartMapping: Equatable {
        var chart: PreviewChartSnapshot
        var unsupportedNoteCount: Int
        var partialDisplay: String
    }

    /// 主窗从 BMS 快照拆出来的一颗物件。身份字段对照 `ChartLayout` 的已配对长音端点。
    struct BmsPreviewEvent: Equatable {
        var channel: String
        var beat: Double
        var kind: String
        var sourceLine: Int
        var measure: Int = 0
        var fractionNumerator: Int64 = 0
        var fractionDenominator: Int64 = 1
        var token: String = ""
        /// `ChartLayout.displayChannel` 的结果。调用方查好再传进来。
        var displayChannel: String = ""
    }

    struct BmsPreviewEndpoint: Equatable, Hashable {
        var measure: Int
        var fractionNumerator: Int64
        var fractionDenominator: Int64
        var beat: Double
        var token: String
        var sourceLine: Int
    }

    struct BmsPreviewLongNote: Equatable {
        var channel: String
        var start: BmsPreviewEndpoint
        var end: BmsPreviewEndpoint
        /// `ChartLayout.displayChannel` 的结果。
        var displayChannel: String = ""
    }

    struct BmsPreviewMeasure: Equatable {
        var start: Double
        var length: Double
    }

    /// `unplacedPlayableNoteCount` 是种类属于可玩音符、但显示通道不在键道上的数量。
    struct BmsVisualChartMapping: Equatable {
        var chart: PreviewChartSnapshot
        var unplacedPlayableNoteCount: Int
    }

    /// 声道下标 0 → `01`。空名字的声道不进表。
    static func wavTable(channelNames: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for (index, name) in channelNames.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            table[BmsonChartMapping.wavToken(channelIndex: index)] = trimmed
        }
        return table
    }

    /// 编成 `#WAVxx` 行，给现有播放器解析。
    static func encodeWavTable(_ table: [String: String]) -> Data {
        let lines = table.keys.sorted().compactMap { key -> String? in
            guard let name = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            return "#WAV\(key) \(name)"
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// 只含 `#WAVxx` 的音频元数据。给播放器读文件名，不写回谱面。
    static func audioMetadataDocumentData(wavTable: [String: String]) -> Data {
        encodeWavTable(wavTable)
    }

    /// `c == true` 是续播，不重新触发声音，对照 `AddAllIntoMasterCache`。
    /// `x <= 0` 是 BGM，`x > 0` 是键音。续播两种都不重触发。
    static func notes(
        channels: [(name: String, notes: [SoundNote])],
        resolution: Int
    ) -> [PreviewAudioNote] {
        var result: [PreviewAudioNote] = []
        for (index, channel) in channels.enumerated() {
            let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let token = BmsonChartMapping.wavToken(channelIndex: index)
            for note in channel.notes where !note.continueFlag {
                result.append(
                    PreviewAudioNote(
                        beat: BmsonChartMapping.beat(pulse: note.y, resolution: resolution),
                        wavToken: token,
                        kind: note.x > 0 ? .key : .bgm
                    )
                )
            }
        }
        return result
    }

    static func timing(
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        resolution: Int,
        stopNotes: [(y: Int64, v: Double)] = []
    ) -> PreviewAudioTiming {
        let header = initBpm > 0 && initBpm.isFinite ? initBpm : 120
        let events = bpmNotes.compactMap { event -> (beat: Double, bpm: Double)? in
            guard event.v > 0, event.v.isFinite else { return nil }
            return (BmsonChartMapping.beat(pulse: event.y, resolution: resolution), event.v)
        }
        let stops = stopNotes.compactMap { event -> (beat: Double, durationSeconds: Double)? in
            guard let seconds = stopDurationSeconds(
                pulses: event.v,
                atPulse: event.y,
                initBpm: header,
                bpmNotes: bpmNotes,
                resolution: resolution
            ) else { return nil }
            return (BmsonChartMapping.beat(pulse: event.y, resolution: resolution), seconds)
        }
        return PreviewAudioTiming(headerBPM: header, bpmEvents: events, stopEvents: stops)
    }

    /// `v` 是脉冲停顿。秒数 = `(v / resolution) * 60 / 当时 BPM`。
    /// 同一脉冲上的 `bpmNotes` 先改速度，再算停顿。
    static func stopDurationSeconds(
        pulses: Double,
        atPulse: Int64,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        resolution: Int
    ) -> Double? {
        guard pulses > 0, pulses.isFinite else { return nil }
        let safe = resolution > 0 ? resolution : 240
        let bpm = bpmAt(pulse: atPulse, initBpm: initBpm, bpmNotes: bpmNotes)
        return pulses / Double(safe) * 60 / bpm
    }

    static func context(
        channelNames: [String],
        channels: [(name: String, notes: [SoundNote])],
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        resolution: Int,
        chartDirectory: URL?,
        playHereBeat: Double,
        stopNotes: [(y: Int64, v: Double)] = [],
        title: String = "",
        modeHint: String = "",
        barLines: [Int64] = [],
        bgaHeaders: [(id: Int, name: String)] = [],
        bgaEvents: [(y: Int64, id: Int)] = [],
        layerEvents: [(y: Int64, id: Int)] = [],
        poorEvents: [(y: Int64, id: Int)] = [],
        artist: String = "",
        genre: String = "",
        playLevel: Int? = nil,
        judgeRank: Double? = nil,
        volwav: String? = nil
    ) -> PreviewAudioDocumentContext {
        let table = wavTable(channelNames: channelNames)
        let picture = visualChart(
            title: title,
            channels: channels,
            resolution: resolution,
            modeHint: modeHint,
            barLines: barLines,
            bgaHeaders: bgaHeaders,
            bgaEvents: bgaEvents,
            layerEvents: layerEvents,
            poorEvents: poorEvents
        )
        return PreviewAudioDocumentContext(
            documentData: previewDocumentData(
                wavTable: table,
                title: title,
                artist: artist,
                genre: genre,
                playLevel: playLevel,
                judgeRank: judgeRank,
                modeHint: modeHint,
                volwav: volwav
            ),
            chartDirectory: chartDirectory,
            notes: notes(channels: channels, resolution: resolution),
            timing: timing(initBpm: initBpm, bpmNotes: bpmNotes, resolution: resolution, stopNotes: stopNotes),
            playHereBeat: playHereBeat,
            appliesBmsonPlayhead: true,
            visualChart: picture.chart
        )
    }

    /// 只给预览窗读的合成文本。不写回 BMSON。
    /// `#JUDGERANK` 是 BMSON 的 judge rank，不是 BMS `#RANK`。
    /// 双人 `beat-10k` / `beat-14k` 写 `#PLAYER 3`，明确的 battle 写 `2`，单人 5/7 写 `1`。
    /// 皮肤放不下的模式不写 `#PLAYER`，也不另造键列。没有 `#PATH_WAV`，BGA 目录不进这里。
    static func previewDocumentData(
        wavTable table: [String: String],
        title: String = "",
        artist: String = "",
        genre: String = "",
        playLevel: Int? = nil,
        judgeRank: Double? = nil,
        modeHint: String = "",
        volwav: String? = nil
    ) -> Data {
        var lines: [String] = []
        if let line = headerLine("TITLE", title) { lines.append(line) }
        if let line = headerLine("ARTIST", artist) { lines.append(line) }
        if let line = headerLine("GENRE", genre) { lines.append(line) }
        if let playLevel, let line = headerLine("PLAYLEVEL", String(playLevel)) { lines.append(line) }
        if let player = previewPlayerHeader(modeHint: modeHint), let line = headerLine("PLAYER", String(player)) {
            lines.append(line)
        }
        if let judgeRank, let text = headerNumber(judgeRank), let line = headerLine("JUDGERANK", text) {
            lines.append(line)
        }
        if let volwav, let line = headerLine("VOLWAV", volwav) { lines.append(line) }
        let wav = encodeWavTable(table)
        if lines.isEmpty { return wav }
        var text = lines.joined(separator: "\n")
        if !wav.isEmpty {
            text += "\n"
            text += String(decoding: wav, as: UTF8.self)
        }
        return Data(text.utf8)
    }

    /// 原版皮肤只有 5/7/10/14 键的列。空 hint 按 Beat 7-key。
    /// 返回值给 `#PLAYER`：1 单人，2 明确 battle，3 双人。其它模式是 `nil`。
    static func previewPlayerHeader(modeHint: String) -> Int? {
        switch modeHint {
        case "", "beat-7k", "beat-5k":
            return 1
        case "beat-7k-battle", "beat-5k-battle":
            return 2
        case "beat-14k", "beat-10k":
            return 3
        default:
            return nil
        }
    }

    /// 键道顺序用 `sharedPlayChannels`（对照 `ChartLanes`），再按模式丢掉隐藏列。
    /// 超过共用 16 列的已定义 `x` 另起 `xN` 列。刮盘看模式给出的车道名，不看通道数字。
    /// `player` 按模式的左右手，不按通道号：popn-9k 的第 9 键通道是 `21`，仍是 1P。
    static func visualLanes(modeHint: String) -> [PreviewVisualLane] {
        lanesForMode(BmsONEViewMode.resolve(modeHint))
    }

    static func lanes(channelsInOrder: [String], mode: BmsONEViewMode) -> [PreviewVisualLane] {
        let visible = mode.visiblePlayChannels
        let scratch = scratchChannels(mode: mode, visible: visible)
        var seen: Set<String> = []
        return channelsInOrder.compactMap { channel in
            guard visible.contains(channel), seen.insert(channel).inserted else { return nil }
            let title = mode.channelToLane[channel].flatMap { mode.definedLaneName($0) } ?? channel
            let player = mode.channelToLane[channel].map { previewPlayer(x: $0, mode: mode) } ?? 1
            return PreviewVisualLane(id: channel, title: title, isScratch: scratch.contains(channel), player: player)
        }
    }

    /// `#PLAYER` 2/3，或显示通道上已经有 2P 可玩音符，才铺开双人列。否则只留 1P 八列。
    static func bmsVisualLanes(
        playerHeader: String,
        events: [BmsPreviewEvent],
        longNotes: [BmsPreviewLongNote]
    ) -> [PreviewVisualLane] {
        let dual = bmsHeaderRequestsTwoPlayer(playerHeader) || hasTwoPlayerPerformance(events: events, longNotes: longNotes)
        return visualLanes(modeHint: dual ? "beat-14k" : "beat-7k")
    }

    /// 当前内存里的声道、`x` / `y` / `l` 和 `modeHint`。不写文档。
    /// `c == true` 仍画出音符；发声表继续跳过它。`x <= 0` 不进键道。
    /// 文件名只进 `bgaAssets`，目录留在调用方的 `chartDirectory`。
    static func visualChart(
        title: String = "",
        channels: [(name: String, notes: [SoundNote])],
        resolution: Int,
        modeHint: String = "",
        barLines: [Int64] = [],
        bgaHeaders: [(id: Int, name: String)] = [],
        bgaEvents: [(y: Int64, id: Int)] = [],
        layerEvents: [(y: Int64, id: Int)] = [],
        poorEvents: [(y: Int64, id: Int)] = []
    ) -> VisualChartMapping {
        let mode = BmsONEViewMode.resolve(modeHint)
        let pictureLanes = lanesForMode(mode)
        let laneIDs = Set(pictureLanes.map(\.id))
        var notes: [PreviewVisualNote] = []
        var unsupported = 0
        var cover = 0.0
        for channel in channels {
            for note in channel.notes {
                let start = BmsonChartMapping.beat(pulse: note.y, resolution: resolution)
                let length = BmsonChartMapping.beat(pulse: max(0, note.l), resolution: resolution)
                let end = start + length
                if end.isFinite {
                    cover = max(cover, end)
                }
                if note.x <= 0 {
                    continue
                }
                guard let laneID = previewLaneID(x: note.x, mode: mode, laneIDs: laneIDs) else {
                    unsupported += 1
                    continue
                }
                notes.append(PreviewVisualNote(laneID: laneID, startBeat: start, endBeat: end))
            }
        }
        sortNotes(&notes, lanes: pictureLanes)
        let pictureBGA = bmsonBGA(
            headers: bgaHeaders,
            bgaEvents: bgaEvents,
            layerEvents: layerEvents,
            poorEvents: poorEvents,
            resolution: resolution
        )
        for event in pictureBGA.events where event.layer == .base || event.layer == .layer {
            if event.beat.isFinite {
                cover = max(cover, event.beat)
            }
        }
        let bars = barBeats(lines: barLines, resolution: resolution, coverBeat: cover)
        let endBeat = max(bars.end, cover)
        return VisualChartMapping(
            chart: PreviewChartSnapshot(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                lanes: pictureLanes,
                notes: notes,
                barBeats: bars.beats,
                endBeat: endBeat,
                bgaAssets: pictureBGA.assets,
                bgaEvents: pictureBGA.events
            ),
            unsupportedNoteCount: unsupported,
            partialDisplay: ""
        )
    }

    /// BMS 画面。车道号用调用方已经查过的 `ChartLayout.displayChannel`。
    /// 已配对长音端点不再单独画成短音；BGM、BGA、BPM、STOP、hidden 不进键道。
    /// 小节线只收到有音符或 base/layer 的那一小节为止，不把核心里 0…999 的空小节当成谱面长度。
    static func bmsVisualChart(
        title: String,
        events: [BmsPreviewEvent],
        longNotes: [BmsPreviewLongNote],
        measures: [BmsPreviewMeasure],
        lanes: [PreviewVisualLane],
        bmpNames: [String: String] = [:]
    ) -> BmsVisualChartMapping {
        let laneIDs = Set(lanes.map(\.id))
        let paired = pairedEndpointIdentities(longNotes)
        var notes: [PreviewVisualNote] = []
        var unplaced = 0
        for event in events where !paired.contains(endpointIdentity(event)) {
            guard playablePreviewKinds.contains(event.kind) else { continue }
            guard event.beat.isFinite, laneIDs.contains(event.displayChannel) else {
                unplaced += 1
                continue
            }
            notes.append(
                PreviewVisualNote(laneID: event.displayChannel, startBeat: event.beat, endBeat: event.beat)
            )
        }
        for note in longNotes {
            let start = min(note.start.beat, note.end.beat)
            let end = max(note.start.beat, note.end.beat)
            guard start.isFinite, end.isFinite, laneIDs.contains(note.displayChannel) else {
                unplaced += 1
                continue
            }
            notes.append(PreviewVisualNote(laneID: note.displayChannel, startBeat: start, endBeat: end))
        }
        sortNotes(&notes, lanes: lanes)
        let pictureBGA = bmsBGA(bmpNames: bmpNames, events: events)
        var spans = notes.map { (start: $0.startBeat, end: $0.endBeat) }
        for event in pictureBGA.events where event.layer == .base || event.layer == .layer {
            spans.append((start: event.beat, end: event.beat))
        }
        let endBeat = previewEndBeat(spans: spans, measures: measures)
        let bars = uniqueSorted(measures.compactMap { measure -> Double? in
            guard measure.start.isFinite, measure.start < endBeat else { return nil }
            return measure.start
        })
        return BmsVisualChartMapping(
            chart: PreviewChartSnapshot(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                lanes: lanes,
                notes: notes,
                barBeats: bars,
                endBeat: endBeat,
                bgaAssets: pictureBGA.assets,
                bgaEvents: pictureBGA.events
            ),
            unplacedPlayableNoteCount: unplaced
        )
    }

    /// 发声表按端点身份去掉已配对长音，不用整行 `sourceLine`。
    /// 同一行上别的通道、别的键、别的位置仍要响。
    /// `bgm` → `.bgm`，`mine` → `.mine`，`hiddenNote` / 普通音 / 长音 → `.key`。
    /// 地雷不带谱面 `#WAV` 键。原版地雷音是 `sound/engine.ogg`，这里还没接，所以键是空的。
    /// hidden 能进可听通道时照键音发声，画面仍不画它。
    static func audibleBmsNotes(
        events: [BmsPreviewEvent],
        longNotes: [BmsPreviewLongNote]
    ) -> [PreviewAudioNote] {
        let paired = pairedEndpointIdentities(longNotes)
        var result: [PreviewAudioNote] = []
        for event in events {
            if paired.contains(endpointIdentity(event)) { continue }
            guard let kind = audioKind(forBmsEventKind: event.kind) else { continue }
            guard LegacyPreviewAudio.isAudibleChannel(event.channel) else { continue }
            let token = kind == .mine ? "" : event.token
            result.append(PreviewAudioNote(beat: event.beat, wavToken: token, kind: kind))
        }
        for note in longNotes {
            guard LegacyPreviewAudio.isAudibleChannel(note.channel) else { continue }
            result.append(PreviewAudioNote(beat: note.start.beat, wavToken: note.start.token, kind: .key))
        }
        return result
    }

    /// 点音符：两位键走声道表；文件名直接当 `#WAV` 的值。
    static func previewFileName(token: String, table: [String: String]) -> String? {
        if let name = LegacyPreviewAudio.fileName(forToken: token, in: table) {
            return name
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if table.values.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return trimmed
        }
        return nil
    }

    /// BMS 显示通道里的 2P 键。只用于决定要不要铺 2P 列，不拿来给 BMSON 标 `player`。
    static let bmsTwoPlayerDisplayChannels: Set<String> = [
        "21", "22", "23", "24", "25", "28", "29", "26"
    ]

    private struct BmsEndpointIdentity: Hashable {
        var channel: String
        var measure: Int
        var fractionNumerator: Int64
        var fractionDenominator: Int64
        var token: String
        var sourceLine: Int
    }

    private static let playablePreviewKinds: Set<String> = ["normalNote", "longNote", "mine"]

    private static func audioKind(forBmsEventKind kind: String) -> PreviewAudioKind? {
        switch kind {
        case "bgm":
            return .bgm
        case "mine":
            return .mine
        case "hiddenNote", "normalNote", "longNote":
            return .key
        default:
            return nil
        }
    }

    private static func headerLine(_ name: String, _ value: String) -> String? {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return "#\(name) \(cleaned)"
    }

    private static func headerNumber(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_000_001, abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        return String(value)
    }

    /// 对照 `ChartPlayerColumns.showsTwoPlayer`：`#PLAYER` 2 是 Couple，3 是 Double。
    private static func bmsHeaderRequestsTwoPlayer(_ stored: String) -> Bool {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return false }
        return value == 2 || value == 3
    }

    private static func hasTwoPlayerPerformance(
        events: [BmsPreviewEvent],
        longNotes: [BmsPreviewLongNote]
    ) -> Bool {
        if longNotes.contains(where: { bmsTwoPlayerDisplayChannels.contains($0.displayChannel) }) {
            return true
        }
        return events.contains { event in
            bmsTwoPlayerDisplayChannels.contains(event.displayChannel) && playablePreviewKinds.contains(event.kind)
        }
    }

    private static func lanesForMode(_ mode: BmsONEViewMode) -> [PreviewVisualLane] {
        let mapped = lanes(channelsInOrder: BmsONEViewMode.sharedPlayChannels, mode: mode)
        let mappedIDs = Set(mapped.map(\.id))
        var extras: [PreviewVisualLane] = []
        for x in definedLaneNumbers(mode) {
            if let channel = mode.laneToChannel[x], mappedIDs.contains(channel) {
                continue
            }
            let title = mode.definedLaneName(x) ?? "Lane \(x)"
            extras.append(
                PreviewVisualLane(
                    id: independentLaneID(x),
                    title: title,
                    isScratch: false,
                    player: previewPlayer(x: x, mode: mode)
                )
            )
        }
        return mapped + extras
    }

    /// 双人模式按该模式自己的左右手划分。单人模式一律 1，即使通道号落在 BMS 的 2P 段。
    private static func previewPlayer(x: Int64, mode: BmsONEViewMode) -> Int {
        switch mode.kind {
        case .beat10k, .beat14k:
            return x >= 9 ? 2 : 1
        case .circularDouble:
            return (5...8).contains(x) ? 2 : 1
        case .keyboard24Double:
            return x >= 27 ? 2 : 1
        default:
            return 1
        }
    }

    private static func definedLaneNumbers(_ mode: BmsONEViewMode) -> [Int64] {
        (1...99).compactMap { raw in
            let lane = Int64(raw)
            return mode.definedLaneName(lane) == nil ? nil : lane
        }
    }

    private static func independentLaneID(_ x: Int64) -> String {
        "x\(x)"
    }

    private static func previewLaneID(x: Int64, mode: BmsONEViewMode, laneIDs: Set<String>) -> String? {
        if let channel = mode.laneToChannel[x], channel != "01", laneIDs.contains(channel) {
            return channel
        }
        let independent = independentLaneID(x)
        return laneIDs.contains(independent) ? independent : nil
    }

    private static func scratchChannels(mode: BmsONEViewMode, visible: Set<String>) -> Set<String> {
        Set(mode.laneToChannel.compactMap { lane, channel in
            guard visible.contains(channel), let name = mode.definedLaneName(lane) else { return nil }
            return name.range(of: "Scratch", options: .caseInsensitive) == nil ? nil : channel
        })
    }

    private static func bmsonBGA(
        headers: [(id: Int, name: String)],
        bgaEvents: [(y: Int64, id: Int)],
        layerEvents: [(y: Int64, id: Int)],
        poorEvents: [(y: Int64, id: Int)],
        resolution: Int
    ) -> (assets: [PreviewBGAAsset], events: [PreviewBGAEvent]) {
        var names: [Int: String] = [:]
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            names[header.id] = name
        }
        let assets = names.keys.sorted().map { id in
            PreviewBGAAsset(id: bmsonAssetID(id), fileName: names[id] ?? "")
        }
        let events = sortedBGAEvents(
            timed(bgaEvents, layer: .base, resolution: resolution)
                + timed(layerEvents, layer: .layer, resolution: resolution)
                + timed(poorEvents, layer: .poor, resolution: resolution)
        )
        return (assets, events)
    }

    private static func bmsBGA(
        bmpNames: [String: String],
        events: [BmsPreviewEvent]
    ) -> (assets: [PreviewBGAAsset], events: [PreviewBGAEvent]) {
        var names: [String: String] = [:]
        for (token, name) in bmpNames {
            let key = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let file = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !file.isEmpty else { continue }
            names[key] = file
        }
        let assets = names.keys.sorted().map { PreviewBGAAsset(id: $0, fileName: names[$0] ?? "") }
        var picture: [PreviewBGAEvent] = []
        for event in events {
            guard let layer = bmsBGALayer(event.channel), event.beat.isFinite else { continue }
            let token = event.token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !token.isEmpty, token != "00" else { continue }
            picture.append(PreviewBGAEvent(beat: event.beat, assetID: token, layer: layer))
        }
        return (assets, sortedBGAEvents(picture))
    }

    /// `04` 基础层，`07` 图层，`06` 失误层。三种在核心里种类都叫 `bga`，层看通道。
    private static func bmsBGALayer(_ channel: String) -> PreviewBGALayer? {
        switch channel.uppercased() {
        case "04": return .base
        case "07": return .layer
        case "06": return .poor
        default: return nil
        }
    }

    private static func bmsonAssetID(_ id: Int) -> String {
        String(id)
    }

    private static func timed(
        _ events: [(y: Int64, id: Int)],
        layer: PreviewBGALayer,
        resolution: Int
    ) -> [PreviewBGAEvent] {
        events.compactMap { event in
            let beat = BmsonChartMapping.beat(pulse: event.y, resolution: resolution)
            guard beat.isFinite else { return nil }
            return PreviewBGAEvent(beat: beat, assetID: bmsonAssetID(event.id), layer: layer)
        }
    }

    private static func sortedBGAEvents(_ events: [PreviewBGAEvent]) -> [PreviewBGAEvent] {
        events.sorted { lhs, rhs in
            if lhs.beat != rhs.beat { return lhs.beat < rhs.beat }
            let left = bgaLayerRank(lhs.layer)
            let right = bgaLayerRank(rhs.layer)
            if left != right { return left < right }
            return lhs.assetID < rhs.assetID
        }
    }

    private static func bgaLayerRank(_ layer: PreviewBGALayer) -> Int {
        switch layer {
        case .base: return 0
        case .layer: return 1
        case .poor: return 2
        }
    }

    /// 点音落在某小节内部时，结尾收到该小节末尾。
    /// 长音占用 `[start, end)`，正好停在小节线上时不把下一空小节算进去。
    /// 没有任何内容时结尾是 0，后面的空小节（BMS 固定 1000 小节，BMSON 编辑器再垫 32 小节）都不算。
    private static func previewEndBeat(
        spans: [(start: Double, end: Double)],
        measures: [BmsPreviewMeasure]
    ) -> Double {
        var end = 0.0
        for span in spans {
            guard span.start.isFinite, span.end.isFinite else { continue }
            let lo = min(span.start, span.end)
            let hi = max(span.start, span.end)
            end = max(end, coverageEnd(lo: lo, hi: hi, measures: measures))
        }
        return end
    }

    private static func coverageEnd(
        lo: Double,
        hi: Double,
        measures: [BmsPreviewMeasure]
    ) -> Double {
        if lo == hi {
            var result = lo
            for measure in measures {
                guard let bounds = measureBounds(measure) else { continue }
                if bounds.start <= lo && lo < bounds.end {
                    result = max(result, bounds.end)
                }
            }
            return result
        }
        var result = hi
        for measure in measures {
            guard let bounds = measureBounds(measure) else { continue }
            let overlaps = bounds.start < hi && bounds.end > lo
            guard overlaps else { continue }
            if bounds.start < hi && hi < bounds.end {
                result = max(result, bounds.end)
            } else {
                result = max(result, min(bounds.end, hi))
            }
        }
        return result
    }

    private static func measureBounds(_ measure: BmsPreviewMeasure) -> (start: Double, end: Double)? {
        guard measure.start.isFinite, measure.length.isFinite, measure.length > 0 else { return nil }
        return (measure.start, measure.start + measure.length)
    }

    /// 小节线转成拍。内容超出最后一根线时，按默认 4 拍补到能盖住音符，不追加编辑用的 32 小节。
    private static func barBeats(
        lines: [Int64],
        resolution: Int,
        coverBeat: Double
    ) -> (beats: [Double], end: Double) {
        var starts = Set(lines.filter { $0 >= 0 }.map {
            BmsonChartMapping.beat(pulse: $0, resolution: resolution)
        })
        starts.insert(0)
        var sorted = uniqueSorted(Array(starts))
        let cover = coverBeat.isFinite ? max(0, coverBeat) : 0
        let step = BmsonChartMapping.defaultMeasureBeats
        if step > 0, var cursor = sorted.last {
            var added = 0
            while cursor < cover && added < 16_384 {
                let next = cursor + step
                if !next.isFinite || !(next > cursor) { break }
                cursor = next
                sorted.append(cursor)
                added += 1
            }
        }
        return (sorted, max(sorted.last ?? 0, cover))
    }

    private static func uniqueSorted(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() where value.isFinite {
            if result.last != value {
                result.append(value)
            }
        }
        return result
    }

    private static func sortNotes(_ notes: inout [PreviewVisualNote], lanes: [PreviewVisualLane]) {
        let order = Dictionary(uniqueKeysWithValues: lanes.enumerated().map { ($1.id, $0) })
        notes.sort { lhs, rhs in
            if lhs.startBeat != rhs.startBeat { return lhs.startBeat < rhs.startBeat }
            let left = order[lhs.laneID] ?? Int.max
            let right = order[rhs.laneID] ?? Int.max
            if left != right { return left < right }
            return lhs.endBeat < rhs.endBeat
        }
    }

    private static func pairedEndpointIdentities(_ longNotes: [BmsPreviewLongNote]) -> Set<BmsEndpointIdentity> {
        Set(longNotes.flatMap { note in
            [endpointIdentity(channel: note.channel, endpoint: note.start),
             endpointIdentity(channel: note.channel, endpoint: note.end)]
        })
    }

    private static func endpointIdentity(channel: String, endpoint: BmsPreviewEndpoint) -> BmsEndpointIdentity {
        BmsEndpointIdentity(
            channel: channel,
            measure: endpoint.measure,
            fractionNumerator: endpoint.fractionNumerator,
            fractionDenominator: endpoint.fractionDenominator,
            token: endpoint.token,
            sourceLine: endpoint.sourceLine
        )
    }

    private static func endpointIdentity(_ event: BmsPreviewEvent) -> BmsEndpointIdentity {
        BmsEndpointIdentity(
            channel: event.channel,
            measure: event.measure,
            fractionNumerator: event.fractionNumerator,
            fractionDenominator: event.fractionDenominator,
            token: event.token,
            sourceLine: event.sourceLine
        )
    }

    private static func bpmAt(
        pulse: Int64,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)]
    ) -> Double {
        var bpm = initBpm > 0 && initBpm.isFinite ? initBpm : 120
        for event in bpmNotes.sorted(by: { $0.y < $1.y }) where event.y <= pulse {
            if event.v > 0, event.v.isFinite {
                bpm = event.v
            }
        }
        return bpm
    }
}
