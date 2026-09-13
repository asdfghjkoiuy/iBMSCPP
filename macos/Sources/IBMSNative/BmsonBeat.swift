import Foundation

/// 同一套 Beat 侧栏。打开 BMSON 时不套 `#mmm02`。
/// BmsONE 只有 `InsertBarLine` / `RemoveBarLine`，没有四种 Apply。
/// 这里按 iBMSC `ApplyBeat` 的四种模式改 `lines[]` 和脉冲，这是工作规则。
enum BmsonBeat {
    struct Timing: Equatable {
        var y: Int64
        var v: Double
    }

    struct BgaEvent: Equatable {
        var y: Int64
        var id: Int
    }

    struct State: Equatable {
        var lines: [Int64]
        var channels: [BmsonChartMapping.ChannelInput]
        var bpmNotes: [Timing]
        var stopNotes: [Timing]
        var bgaEvents: [BgaEvent] = []
        var layerEvents: [BgaEvent] = []
        var poorEvents: [BgaEvent] = []
        var resolution: Int
    }

    static func apply(
        measures: [Int],
        decimal: String,
        mode: LegacyBeat.Mode,
        to state: State
    ) -> State? {
        guard !measures.isEmpty else { return state }
        guard let ratio = parseRatio(decimal) else { return nil }
        var next = state
        for measure in measures {
            guard let applied = applyOne(measure: measure, ratio: ratio, mode: mode, to: next) else {
                return nil
            }
            next = applied
        }
        return next
    }

    static func parseRatio(_ decimal: String) -> Double? {
        let trimmed = decimal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite, value > 0, value < 1000 else {
            return nil
        }
        return value
    }

    private static func applyOne(
        measure: Int,
        ratio: Double,
        mode: LegacyBeat.Mode,
        to state: State
    ) -> State? {
        guard measure >= 0, measure < LegacyBeat.measureCount else { return nil }
        let resolution = state.resolution > 0 ? state.resolution : 240
        var measures = displayedMeasures(state)
        ensureMeasures(&measures, index: measure)
        guard measure < measures.count else { return nil }
        let oldStart = measures[measure].start
        let oldLength = measures[measure].length
        let newLength = ratio * BmsonChartMapping.defaultMeasureBeats
        guard oldLength > 0, newLength > 0 else { return nil }
        let oldEnd = oldStart + oldLength
        let newEnd = oldStart + newLength
        let oldStartP = BmsonChartMapping.pulse(beat: oldStart, resolution: resolution)
        let oldEndP = BmsonChartMapping.pulse(beat: oldEnd, resolution: resolution)
        let newEndP = BmsonChartMapping.pulse(beat: newEnd, resolution: resolution)
        let oldLenP = oldEndP - oldStartP
        let newLenP = newEndP - oldStartP
        let deltaP = newEndP - oldEndP

        var channels: [BmsonChartMapping.ChannelInput] = []
        for channel in state.channels {
            var notes: [BmsonChartMapping.NoteInput] = []
            for note in channel.notes {
                if let moved = transformHold(
                    start: note.y,
                    end: note.y + max(0, note.l),
                    mode: mode,
                    oldStart: oldStartP,
                    oldEnd: oldEndP,
                    newEnd: newEndP,
                    oldLength: oldLenP,
                    newLength: newLenP,
                    delta: deltaP
                ) {
                    var next = note
                    next.y = moved.start
                    next.l = max(0, moved.end - moved.start)
                    notes.append(next)
                }
            }
            channels.append(BmsonChartMapping.ChannelInput(name: channel.name, notes: notes))
        }

        let bpmNotes = state.bpmNotes.compactMap { event -> Timing? in
            guard let y = transformPulse(
                event.y,
                mode: mode,
                oldStart: oldStartP,
                oldEnd: oldEndP,
                newEnd: newEndP,
                oldLength: oldLenP,
                newLength: newLenP,
                delta: deltaP
            ) else {
                return nil
            }
            return Timing(y: y, v: event.v)
        }
        let stopNotes = state.stopNotes.compactMap { event -> Timing? in
            guard let y = transformPulse(
                event.y,
                mode: mode,
                oldStart: oldStartP,
                oldEnd: oldEndP,
                newEnd: newEndP,
                oldLength: oldLenP,
                newLength: newLenP,
                delta: deltaP
            ) else {
                return nil
            }
            return Timing(y: y, v: event.v)
        }
        let bgaEvents = transformBga(state.bgaEvents, mode: mode, oldStart: oldStartP, oldEnd: oldEndP, newEnd: newEndP, oldLength: oldLenP, newLength: newLenP, delta: deltaP)
        let layerEvents = transformBga(state.layerEvents, mode: mode, oldStart: oldStartP, oldEnd: oldEndP, newEnd: newEndP, oldLength: oldLenP, newLength: newLenP, delta: deltaP)
        let poorEvents = transformBga(state.poorEvents, mode: mode, oldStart: oldStartP, oldEnd: oldEndP, newEnd: newEndP, oldLength: oldLenP, newLength: newLenP, delta: deltaP)

        measures[measure].length = newLength
        for index in (measure + 1)..<measures.count {
            measures[index].start += newLength - oldLength
        }
        return State(
            lines: compactLines(measures, resolution: resolution),
            channels: channels,
            bpmNotes: bpmNotes,
            stopNotes: stopNotes,
            bgaEvents: bgaEvents,
            layerEvents: layerEvents,
            poorEvents: poorEvents,
            resolution: resolution
        )
    }

    static func displayedMeasures(_ state: State) -> [BmsonChartMapping.MeasureBeat] {
        BmsonChartMapping.measures(
            lines: state.lines,
            lastPulse: lastPulse(state),
            resolution: state.resolution
        )
    }

    static func lastPulse(_ state: State) -> Int64 {
        let notes = state.channels.flatMap(\.notes).map { $0.y + max(0, $0.l) }.max() ?? 0
        let timing = (state.bpmNotes.map(\.y) + state.stopNotes.map(\.y)).max() ?? 0
        let bga = (state.bgaEvents + state.layerEvents + state.poorEvents).map(\.y).max() ?? 0
        return max(notes, max(timing, bga))
    }

    static func compactLines(_ measures: [BmsonChartMapping.MeasureBeat], resolution: Int) -> [Int64] {
        var lastCustom = -1
        for measure in measures where abs(measure.length - BmsonChartMapping.defaultMeasureBeats) > 1e-9 {
            lastCustom = measure.index
        }
        guard lastCustom >= 0 else { return [] }
        return measures
            .filter { $0.index >= 1 && $0.index <= lastCustom + 1 }
            .map { BmsonChartMapping.pulse(beat: $0.start, resolution: resolution) }
    }

    private static func ensureMeasures(
        _ measures: inout [BmsonChartMapping.MeasureBeat],
        index: Int
    ) {
        let beatLength = BmsonChartMapping.defaultMeasureBeats
        while measures.count <= index {
            let start = measures.last.map { $0.start + $0.length } ?? 0
            measures.append(
                BmsonChartMapping.MeasureBeat(index: measures.count, start: start, length: beatLength)
            )
        }
    }

    private static func transformBga(
        _ events: [BgaEvent],
        mode: LegacyBeat.Mode,
        oldStart: Int64,
        oldEnd: Int64,
        newEnd: Int64,
        oldLength: Int64,
        newLength: Int64,
        delta: Int64
    ) -> [BgaEvent] {
        events.compactMap { event in
            guard let y = transformPulse(
                event.y,
                mode: mode,
                oldStart: oldStart,
                oldEnd: oldEnd,
                newEnd: newEnd,
                oldLength: oldLength,
                newLength: newLength,
                delta: delta
            ) else {
                return nil
            }
            return BgaEvent(y: y, id: event.id)
        }
    }

    private static func transformPulse(
        _ y: Int64,
        mode: LegacyBeat.Mode,
        oldStart: Int64,
        oldEnd: Int64,
        newEnd: Int64,
        oldLength: Int64,
        newLength: Int64,
        delta: Int64
    ) -> Int64? {
        switch mode {
        case .preserve:
            return y
        case .scale:
            if y >= oldEnd {
                return y + delta
            }
            if y >= oldStart, oldLength != 0 {
                return oldStart + (y - oldStart) * newLength / oldLength
            }
            return y
        case .measure:
            return y >= oldEnd ? y + delta : y
        case .cut:
            if delta < 0, y >= newEnd, y < oldEnd {
                return nil
            }
            return y >= oldEnd ? y + delta : y
        }
    }

    private static func transformHold(
        start: Int64,
        end: Int64,
        mode: LegacyBeat.Mode,
        oldStart: Int64,
        oldEnd: Int64,
        newEnd: Int64,
        oldLength: Int64,
        newLength: Int64,
        delta: Int64
    ) -> (start: Int64, end: Int64)? {
        if start == end {
            guard let y = transformPulse(
                start,
                mode: mode,
                oldStart: oldStart,
                oldEnd: oldEnd,
                newEnd: newEnd,
                oldLength: oldLength,
                newLength: newLength,
                delta: delta
            ) else {
                return nil
            }
            return (y, y)
        }
        if mode == .preserve {
            return (start, end)
        }
        if mode == .scale {
            let nextStart = transformPulse(
                start,
                mode: .scale,
                oldStart: oldStart,
                oldEnd: oldEnd,
                newEnd: newEnd,
                oldLength: oldLength,
                newLength: newLength,
                delta: delta
            ) ?? start
            let nextEnd = transformPulse(
                end,
                mode: .scale,
                oldStart: oldStart,
                oldEnd: oldEnd,
                newEnd: newEnd,
                oldLength: oldLength,
                newLength: newLength,
                delta: delta
            ) ?? end
            if nextEnd <= nextStart {
                return nil
            }
            return (nextStart, nextEnd)
        }
        var holdStart = start
        var holdEnd = end
        if mode == .cut, delta < 0 {
            if holdStart < newEnd {
                if holdEnd >= newEnd, holdEnd < oldEnd {
                    holdEnd = newEnd - 1
                }
            } else if holdStart < oldEnd {
                if holdEnd < oldEnd {
                    return nil
                }
                holdStart = oldEnd
            }
        }
        if holdStart >= oldEnd {
            holdStart += delta
            holdEnd += delta
        } else if holdEnd >= oldEnd {
            holdEnd += delta
        }
        if holdEnd <= holdStart {
            return nil
        }
        return (holdStart, holdEnd)
    }
}
