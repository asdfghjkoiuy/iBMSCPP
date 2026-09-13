import Foundation

/// 对照 `SequenceView::TransferSelectedNotesToBgm` / `ToKey` / `GetSomeVacantLane`。
/// 只改 BMSON `x` / `l`，不套 BMS 通道。空选不清空。
enum BmsonNoteTransfer {
    static let bgmLane: Int64 = 0

    struct Note: Equatable {
        var x: Int64
        var y: Int64
        var l: Int64
        var c: Bool
    }

    struct Address: Equatable {
        var channel: Int
        var y: Int64
    }

    static func toBGM(selected: [Address], channels: [[Note]]) -> [[Note]] {
        var next = channels
        for item in selected {
            guard let index = noteIndex(channel: item.channel, y: item.y, in: next) else { continue }
            next[item.channel][index].x = bgmLane
            next[item.channel][index].l = 0
        }
        return next
    }

    /// 已在键盘列的音不动。BGM 音按 Skin 从左到右找空列，默认刮盘 `x=8`。
    /// 空选返回 `nil`，对照原版会响一声。
    static func toKey(selected: [Address], channels: [[Note]], lanes: [Int64]) -> [[Note]]? {
        guard !selected.isEmpty else { return nil }
        var next = channels
        var reserved: [Int64: Set<Int64>] = [:]
        let ordered = selected.sorted { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.channel < rhs.channel
        }
        for item in ordered {
            guard let index = noteIndex(channel: item.channel, y: item.y, in: next) else { continue }
            var note = next[item.channel][index]
            if note.x == bgmLane {
                let lane = vacantLane(
                    location: note.y,
                    length: 0,
                    exclude: reserved[note.y] ?? [],
                    lanes: lanes,
                    notes: allNotes(next)
                )
                note.x = lane
                note.l = 0
                reserved[note.y, default: []].insert(lane)
            }
            next[item.channel][index] = note
        }
        return next
    }

    /// 对照 `SeparateLayeredNotes`：只拆同一脉冲叠在同一车道上的音。
    /// 第一声道留下；长度不一致则全体都搬（`IsIllegal`）。长音盖住后面的音不算叠层。
    static func separateLayered(selected: [Address], channels: [[Note]], lanes: [Int64]) -> [[Note]]? {
        guard !selected.isEmpty else { return nil }
        let groups = layeringGroups(channels)
        var next = channels
        var reserved: [Int64: Set<Int64>] = [:]
        let original = allNotes(channels)
        let ordered = selected.sorted { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.channel < rhs.channel
        }
        for item in ordered {
            guard let index = noteIndex(channel: item.channel, y: item.y, in: next) else { continue }
            var note = next[item.channel][index]
            guard note.x > bgmLane, let group = groups[LayerKey(x: note.x, y: note.y)], group.count >= 2 else {
                continue
            }
            let illegal = Set(group.map(\.l)).count > 1
            let main = group.map(\.channel).min() ?? item.channel
            if !illegal && item.channel == main {
                continue
            }
            let pivot = lanes.firstIndex(of: note.x) ?? 0
            var length = note.l
            var lane = vacantLane(
                location: note.y,
                length: length,
                exclude: reserved[note.y] ?? [],
                lanes: lanes,
                notes: original,
                pivot: pivot
            )
            if lane == bgmLane {
                length = 0
                lane = vacantLane(
                    location: note.y,
                    length: 0,
                    exclude: reserved[note.y] ?? [],
                    lanes: lanes,
                    notes: original,
                    pivot: pivot
                )
            }
            note.x = lane
            note.l = length
            reserved[note.y, default: []].insert(lane)
            next[item.channel][index] = note
        }
        return next
    }

    /// `GetSomeVacantLane`：从 `pivot` 起绕一圈。默认从左刮盘开始。
    static func vacantLane(
        location: Int64,
        length: Int64,
        exclude: Set<Int64>,
        lanes: [Int64],
        notes: [Note],
        pivot: Int = 0
    ) -> Int64 {
        guard !lanes.isEmpty else { return bgmLane }
        let start = min(max(pivot, 0), lanes.count - 1)
        var order: [Int] = []
        order.append(contentsOf: start..<lanes.count)
        order.append(contentsOf: 0..<start)
        for index in order {
            let lane = lanes[index]
            if exclude.contains(lane) { continue }
            if notes.contains(where: { occupied($0, lane: lane, location: location, length: length) }) {
                continue
            }
            return lane
        }
        return bgmLane
    }

    private struct LayerKey: Hashable {
        var x: Int64
        var y: Int64
    }

    private struct LayerMember {
        var channel: Int
        var l: Int64
    }

    /// 同一 `x`、同一 `y` 且 `x>0` 的音。对照 `FindConflictsByLanes` 的 `LAYERING_FLAG`。
    private static func layeringGroups(_ channels: [[Note]]) -> [LayerKey: [LayerMember]] {
        var groups: [LayerKey: [LayerMember]] = [:]
        for (channel, notes) in channels.enumerated() {
            for note in notes where note.x > bgmLane {
                let key = LayerKey(x: note.x, y: note.y)
                groups[key, default: []].append(LayerMember(channel: channel, l: note.l))
            }
        }
        return groups
    }

    private static func occupied(_ note: Note, lane: Int64, location: Int64, length: Int64) -> Bool {
        guard note.x == lane else { return false }
        return note.y <= location + length && location <= note.y + note.l
    }

    private static func allNotes(_ channels: [[Note]]) -> [Note] {
        channels.flatMap { $0 }
    }

    private static func noteIndex(channel: Int, y: Int64, in channels: [[Note]]) -> Int? {
        guard channel >= 0, channel < channels.count else { return nil }
        return channels[channel].firstIndex { $0.y == y }
    }
}
