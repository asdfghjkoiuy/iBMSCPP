import Foundation

/// BMSON pulse / Skin `x` ↔ 主编辑器 beat / BMS 通道。
/// 两套模型仍分开；这里只做显示和点选用的换算。
enum BmsonChartMapping {
    static let defaultMeasureBeats = 4.0
    static let trailingMeasureCount = 32
    static let noteIdentityStride = 1_000_003

    static func noteIdentity(channelIndex: Int, noteIndex: Int) -> Int {
        channelIndex * noteIdentityStride + noteIndex + 1
    }

    static func noteAddress(identity: Int) -> (channelIndex: Int, noteIndex: Int)? {
        guard identity > 0 else { return nil }
        let raw = identity - 1
        return (raw / noteIdentityStride, raw % noteIdentityStride)
    }

    /// Find 写回用：先解出种类和下标，再去文档里取 `y` / 车道。
    enum FindIdentity: Equatable {
        case sound(channelIndex: Int, noteIndex: Int)
        case bpm(index: Int)
        case stop(index: Int)
        case bga(lane: BgaLane, index: Int)
    }

    static func findIdentity(_ identity: Int) -> FindIdentity? {
        if identity > 0 {
            guard let address = noteAddress(identity: identity) else { return nil }
            return .sound(channelIndex: address.channelIndex, noteIndex: address.noteIndex)
        }
        let raw = -identity
        if raw <= 0 { return nil }
        if raw < 100_000 {
            return .bpm(index: raw - 1)
        }
        if raw < 200_000 {
            return .stop(index: raw - 100_001)
        }
        let laneValue = raw / 100_000 - 2
        let index = raw % 100_000 - 1
        guard let lane = BgaLane(rawValue: laneValue), index >= 0 else { return nil }
        return .bga(lane: lane, index: index)
    }

    /// 时值身份解不出声道，当作当前声道，避免暗化 BPM / STOP。
    static func noteIsActiveChannel(identity: Int, currentChannel: Int) -> Bool {
        guard let address = noteAddress(identity: identity) else { return true }
        return address.channelIndex == currentChannel
    }

    struct NoteInput: Equatable {
        var x: Int64
        var y: Int64
        var l: Int64
        var c: Bool
    }

    struct ChannelInput: Equatable {
        var name: String
        var notes: [NoteInput]
    }

    struct VisibleNote: Equatable {
        var channel: String
        var beat: Double
        var measure: Int
        var token: String
        var kind: String
        var lengthBeats: Double
        var identity: Int
    }

    struct MeasureBeat: Equatable {
        var index: Int
        var start: Double
        var length: Double
    }

    static func beat(pulse: Int64, resolution: Int) -> Double {
        let safe = resolution > 0 ? resolution : 240
        return Double(pulse) / Double(safe)
    }

    static func pulse(beat: Double, resolution: Int) -> Int64 {
        let safe = resolution > 0 ? resolution : 240
        return Int64((beat * Double(safe)).rounded())
    }

    /// 对照 `ChartLayout.snapTarget`：`beat = start + slot * 4 / division`。
    static func pulse(measureStart: Double, slot: Int, division: Int, resolution: Int) -> Int64 {
        let step = 4.0 / Double(max(1, division))
        return pulse(beat: measureStart + Double(slot) * step, resolution: resolution)
    }

    static func channel(forLaneX x: Int64, modeHint: String) -> String? {
        channel(forLaneX: x, mode: BmsONEViewMode.resolve(modeHint))
    }

    static func channel(forLaneX x: Int64, mode: BmsONEViewMode) -> String? {
        mode.laneToChannel[x]
    }

    static func laneX(forChannel channel: String, modeHint: String) -> Int64 {
        laneX(forChannel: channel, mode: BmsONEViewMode.resolve(modeHint))
    }

    static func laneX(forChannel channel: String, mode: BmsONEViewMode) -> Int64 {
        let key = channel.uppercased()
        if key == "B1" { return 0 }
        return mode.channelToLane[key] ?? 0
    }

    /// BMS `#STOP` 单位：48 = 1 拍。对照 `bmson_from_bms` 的 `resolution * stop / 48`。
    static let stopUnitsPerBeat = 48.0

    static func formatTiming(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if abs(value - value.rounded()) < 0.000_000_1 {
            return String(Int(value.rounded()))
        }
        var text = String(format: "%.6f", value)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    static func stopDisplayValue(pulses: Double, resolution: Int) -> Double {
        let safe = Double(resolution > 0 ? resolution : 240)
        return pulses * stopUnitsPerBeat / safe
    }

    static func stopPulses(displayValue: Double, resolution: Int) -> Double {
        let safe = Double(resolution > 0 ? resolution : 240)
        return displayValue * safe / stopUnitsPerBeat
    }

    enum BgaLane: Int {
        case bga = 0
        case layer = 1
        case poor = 2

        var channel: String {
            switch self {
            case .bga: return "04"
            case .layer: return "07"
            case .poor: return "06"
            }
        }

        var kind: String {
            switch self {
            case .bga: return "bga"
            case .layer: return "layer"
            case .poor: return "poor"
            }
        }

        static func parse(channel: String) -> BgaLane? {
            switch channel {
            case "04": return .bga
            case "07": return .layer
            case "06": return .poor
            default: return nil
            }
        }
    }

    static func bmpToken(id: Int) -> String {
        let value = min(1295, max(0, id))
        let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String([digits[value / 36], digits[value % 36]])
    }

    static func bmpId(token: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let padded = String(("00" + trimmed).suffix(2))
        let characters = Array(padded)
        guard characters.count == 2 else { return nil }
        let high = digit(characters[0])
        let low = digit(characters[1])
        if high == 0 && low == 0 && padded != "00" {
            return nil
        }
        let value = high * 36 + low
        guard value >= 0 && value <= 1295 else { return nil }
        return value
    }

    static func bgaIdentity(lane: BgaLane, index: Int) -> Int {
        -( (lane.rawValue + 2) * 100_000 + index + 1 )
    }

    static func timingIdentity(isStop: Bool, index: Int) -> Int {
        let raw = (isStop ? 1 : 0) * 100_000 + index + 1
        return -raw
    }

    static func visibleTiming(
        bpmNotes: [(y: Int64, v: Double)],
        stopNotes: [(y: Int64, v: Double)],
        measures: [MeasureBeat],
        resolution: Int
    ) -> [VisibleNote] {
        var notes: [VisibleNote] = []
        for (index, event) in bpmNotes.enumerated() where event.v > 0 && event.v.isFinite {
            let startBeat = beat(pulse: event.y, resolution: resolution)
            notes.append(
                VisibleNote(
                    channel: "03",
                    beat: startBeat,
                    measure: measureIndex(beat: startBeat, in: measures),
                    token: formatTiming(event.v),
                    kind: "bpm",
                    lengthBeats: 0,
                    identity: timingIdentity(isStop: false, index: index)
                )
            )
        }
        for (index, event) in stopNotes.enumerated() where event.v > 0 && event.v.isFinite {
            let startBeat = beat(pulse: event.y, resolution: resolution)
            notes.append(
                VisibleNote(
                    channel: "09",
                    beat: startBeat,
                    measure: measureIndex(beat: startBeat, in: measures),
                    token: formatTiming(stopDisplayValue(pulses: event.v, resolution: resolution)),
                    kind: "stop",
                    lengthBeats: 0,
                    identity: timingIdentity(isStop: true, index: index)
                )
            )
        }
        return notes
    }

    static func visibleBga(
        bgaEvents: [(y: Int64, id: Int)],
        layerEvents: [(y: Int64, id: Int)],
        poorEvents: [(y: Int64, id: Int)],
        measures: [MeasureBeat],
        resolution: Int
    ) -> [VisibleNote] {
        var notes: [VisibleNote] = []
        let lanes: [(BgaLane, [(y: Int64, id: Int)])] = [
            (.bga, bgaEvents),
            (.layer, layerEvents),
            (.poor, poorEvents)
        ]
        for (lane, events) in lanes {
            for (index, event) in events.enumerated() {
                let startBeat = beat(pulse: event.y, resolution: resolution)
                notes.append(
                    VisibleNote(
                        channel: lane.channel,
                        beat: startBeat,
                        measure: measureIndex(beat: startBeat, in: measures),
                        token: bmpToken(id: event.id),
                        kind: lane.kind,
                        lengthBeats: 0,
                        identity: bgaIdentity(lane: lane, index: index)
                    )
                )
            }
        }
        return notes
    }

    static func wavToken(channelIndex: Int) -> String {
        let value = min(1295, max(1, channelIndex + 1))
        let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String([digits[value / 36], digits[value % 36]])
    }

    static func channelIndex(wavToken: String) -> Int {
        let trimmed = wavToken.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let padded = String(("00" + trimmed).suffix(2))
        let characters = Array(padded)
        let value = digit(characters[0]) * 36 + digit(characters[1])
        return max(0, value - 1)
    }

    static func measures(
        lines: [Int64],
        lastPulse: Int64,
        resolution: Int
    ) -> [MeasureBeat] {
        let safe = resolution > 0 ? resolution : 240
        let measurePulses = Int64(defaultMeasureBeats) * Int64(safe)
        var points = Set(lines.filter { $0 >= 0 })
        points.insert(0)
        let sorted = points.sorted()
        var result: [MeasureBeat] = []
        for index in 0..<(sorted.count - 1) {
            let start = beat(pulse: sorted[index], resolution: safe)
            let length = beat(pulse: sorted[index + 1] - sorted[index], resolution: safe)
            if length > 0 {
                result.append(MeasureBeat(index: result.count, start: start, length: length))
            }
        }
        var cursor = sorted.last ?? 0
        let end = max(cursor, max(0, lastPulse)) + Int64(trailingMeasureCount) * measurePulses
        if result.isEmpty {
            cursor = 0
        }
        while cursor < end {
            result.append(
                MeasureBeat(
                    index: result.count,
                    start: beat(pulse: cursor, resolution: safe),
                    length: defaultMeasureBeats
                )
            )
            cursor += measurePulses
        }
        if result.isEmpty {
            result.append(MeasureBeat(index: 0, start: 0, length: defaultMeasureBeats))
        }
        return result
    }

    static func visibleNotes(
        channels: [ChannelInput],
        measures: [MeasureBeat],
        resolution: Int,
        modeHint: String
    ) -> [VisibleNote] {
        visibleNotes(
            channels: channels,
            measures: measures,
            resolution: resolution,
            mode: BmsONEViewMode.resolve(modeHint)
        )
    }

    static func visibleNotes(
        channels: [ChannelInput],
        measures: [MeasureBeat],
        resolution: Int,
        mode: BmsONEViewMode
    ) -> [VisibleNote] {
        var notes: [VisibleNote] = []
        for (channelIndex, channel) in channels.enumerated() {
            let token = channel.name.isEmpty ? wavToken(channelIndex: channelIndex) : channel.name
            for (noteIndex, note) in channel.notes.enumerated() {
                guard let lane = self.channel(forLaneX: note.x, mode: mode) else { continue }
                let startBeat = beat(pulse: note.y, resolution: resolution)
                let lengthBeats = beat(pulse: max(0, note.l), resolution: resolution)
                notes.append(
                    VisibleNote(
                        channel: lane,
                        beat: startBeat,
                        measure: measureIndex(beat: startBeat, in: measures),
                        token: token,
                        kind: note.l > 0 ? "longNote" : "normal",
                        lengthBeats: lengthBeats,
                        identity: noteIdentity(channelIndex: channelIndex, noteIndex: noteIndex)
                    )
                )
            }
        }
        return notes
    }

    /// 声道列画该道全部音。长音在原版列里也只画短记号，这里同样写成短音。
    static func soundLaneNotes(
        channels: [ChannelInput],
        measures: [MeasureBeat],
        resolution: Int,
        shown: [Bool]? = nil
    ) -> [VisibleNote] {
        var notes: [VisibleNote] = []
        for (channelIndex, channel) in channels.enumerated() {
            guard BmsonSoundLane.isVisible(index: channelIndex, shown: shown) else { continue }
            let token = channel.name.isEmpty ? wavToken(channelIndex: channelIndex) : channel.name
            let lane = BmsonSoundLane.displayChannel(index: channelIndex)
            for (noteIndex, note) in channel.notes.enumerated() {
                let startBeat = beat(pulse: note.y, resolution: resolution)
                notes.append(
                    VisibleNote(
                        channel: lane,
                        beat: startBeat,
                        measure: measureIndex(beat: startBeat, in: measures),
                        token: token,
                        kind: "normal",
                        lengthBeats: 0,
                        identity: noteIdentity(channelIndex: channelIndex, noteIndex: noteIndex)
                    )
                )
            }
        }
        return notes
    }

    static func measureIndex(beat: Double, in measures: [MeasureBeat]) -> Int {
        for measure in measures {
            if beat >= measure.start && beat < measure.start + measure.length {
                return measure.index
            }
        }
        return measures.last?.index ?? 0
    }

    private static func digit(_ character: Character) -> Int {
        guard let value = character.asciiValue else { return 0 }
        if value >= 48 && value <= 57 { return Int(value - 48) }
        if value >= 65 && value <= 90 { return Int(value - 55) }
        return 0
    }
}
