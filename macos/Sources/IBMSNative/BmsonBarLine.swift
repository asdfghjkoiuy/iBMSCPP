import Foundation

/// 对照 `Document::InsertBarLine` / `RemoveBarLine`。
/// 只改 BMSON `lines[]`，不写 `#mmm02`，也不改音符脉冲。
enum BmsonBarLine {
    /// `UpdateTotalLength` 在曲子后面再铺 32 个 4 拍小节。
    static let trailingMeasures = BmsonChartMapping.trailingMeasureCount

    static func insert(pulse y: Int64, lines: [Int64], lastPulse: Int64, resolution: Int) -> [Int64]? {
        guard y >= 0 else { return nil }
        let bars = displayed(lines: lines, lastPulse: lastPulse, resolution: resolution)
        if bars.all.contains(y) { return nil }
        var explicit = bars.explicit
        for pulse in bars.ephemeral where pulse < y {
            explicit.insert(pulse)
        }
        explicit.insert(y)
        explicit.insert(0)
        return stored(explicit)
    }

    static func remove(pulse y: Int64, lines: [Int64], lastPulse: Int64, resolution: Int) -> [Int64]? {
        guard y > 0 else { return nil }
        let bars = displayed(lines: lines, lastPulse: lastPulse, resolution: resolution)
        if !bars.explicit.contains(y) { return nil }
        var explicit = bars.explicit
        explicit.remove(y)
        explicit.insert(0)
        return stored(explicit)
    }

    static func displayed(
        lines: [Int64],
        lastPulse: Int64,
        resolution: Int
    ) -> (explicit: Set<Int64>, ephemeral: Set<Int64>, all: Set<Int64>) {
        let step = measurePulses(resolution)
        var explicit = Set(lines.filter { $0 >= 0 })
        explicit.insert(0)
        let lastExplicit = explicit.max() ?? 0
        let limit = max(lastExplicit, max(0, lastPulse)) + Int64(trailingMeasures) * step
        var ephemeral: Set<Int64> = []
        var cursor = lastExplicit + step
        while cursor < limit {
            ephemeral.insert(cursor)
            cursor += step
        }
        return (explicit, ephemeral, explicit.union(ephemeral))
    }

    private static func stored(_ explicit: Set<Int64>) -> [Int64] {
        let sorted = explicit.sorted()
        if sorted == [0] { return [] }
        return sorted
    }

    private static func measurePulses(_ resolution: Int) -> Int64 {
        let safe = resolution > 0 ? resolution : 240
        return Int64(BmsonChartMapping.defaultMeasureBeats) * Int64(safe)
    }
}
