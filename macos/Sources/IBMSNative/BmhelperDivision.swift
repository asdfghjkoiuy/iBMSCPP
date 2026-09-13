import Foundation

/// 对照 `DivisionSetting::SortType`。
enum BmhelperDivisionSort: Int {
    case none = 0
    case nnGateVel = 1
    case nnVelGate = 2
    case gateNnVel = 3
    case gateVelNn = 4
    case velNnGate = 5
    case velGateNn = 6
}

/// 对照 `division.cpp` 的 `DivisionSetting` 默认值。
struct BmhelperDivisionSetting: Equatable {
    var name: String
    var srcCopy: Bool
    var headMargin: Int
    var minInterval: Int
    var sortType: BmhelperDivisionSort
    var gateThreshold: Int
    var velocityThreshold: Int
    var zzDefinition: Bool
    var mlDefinition: Bool
    var startDefinition: Int
    var mlThreshold: Int

    /// `DivisionSetting(name, quantize)`：`src_copy=false`，`min_interval=quantize`，
    /// 排序 `nn/gate/vel`，`gate_threshold=quantize/8`，`velocity_threshold=5`，
    /// ZZ 和多重定义打开，起始 `1`，`ml_threshold=quantize/2`。
    static func makeDefault(name: String, quantize: Int) -> BmhelperDivisionSetting {
        let safeQuantize = max(quantize, 1)
        return BmhelperDivisionSetting(
            name: name,
            srcCopy: false,
            headMargin: 0,
            minInterval: safeQuantize,
            sortType: .nnGateVel,
            gateThreshold: safeQuantize / 8,
            velocityThreshold: 5,
            zzDefinition: true,
            mlDefinition: true,
            startDefinition: BmhelperDefDialogLayout.defaultStartDefinition,
            mlThreshold: safeQuantize / 2
        )
    }
}

struct BmhelperDivisionDefinition: Equatable {
    var zz: String
    var div: Int
}

struct BmhelperDivisionResult: Equatable {
    var definitions: [BmhelperDivisionDefinition]
    var src2def: [Int]
    /// 对照 `divide_from_data` 写进 Division 的时间线，切片按这些音符算切点。
    var notes: [MidiNoteEvent]
    var quantize: Int
}

/// 对照 `Division::divide_from_data`。聚类后会排出 Division 时间线，给切片用。
enum BmhelperDivision {
    static func divide(
        notes: [MidiNoteEvent],
        setting: BmhelperDivisionSetting,
        quantize: Int
    ) -> BmhelperDivisionResult {
        var tempDivs: [ReferredNote] = []
        var src2div = Array(repeating: 0, count: notes.count)

        if setting.srcCopy {
            tempDivs = notes.enumerated().map { index, note in
                ReferredNote(nn: note.noteNum, gate: note.gate, vel: note.velocity, referrers: [index])
            }
            src2div = Array(notes.indices)
        } else {
            divideNotes(notes, src2div: &src2div, tempDivs: &tempDivs, setting: setting)
            sortNotes(&tempDivs, src2div: &src2div, sortType: setting.sortType)
        }

        var zz = ZZNumber(setting.startDefinition)
        if !setting.zzDefinition, !zz.in_ff() {
            zz.increment_in_ff()
        }

        var definitions: [BmhelperDivisionDefinition] = []
        var src2def = Array(repeating: 0, count: notes.count)
        for (divIndex, cluster) in tempDivs.enumerated() {
            let overloadCount = overloadCount(for: cluster, notes: notes, setting: setting)
            let firstDefinition = definitions.count
            for _ in 0..<overloadCount {
                definitions.append(BmhelperDivisionDefinition(zz: zz.to_string(), div: divIndex))
                if setting.zzDefinition {
                    zz.increment()
                } else {
                    zz.increment_in_ff()
                }
            }
            var slot = 0
            for referrer in cluster.referrers {
                src2def[referrer] = firstDefinition + slot
                slot += 1
                if slot == overloadCount {
                    slot = 0
                }
            }
        }
        let safeQuantize = max(quantize, 1)
        let laidNotes = layoutNotes(
            source: notes,
            tempDivs: tempDivs,
            setting: setting,
            quantize: safeQuantize
        )
        return BmhelperDivisionResult(
            definitions: definitions,
            src2def: src2def,
            notes: laidNotes,
            quantize: safeQuantize
        )
    }

    /// 对照 `divide_from_data` 把聚类结果排进 Division MIDI。
    /// `src_copy` 时保留原位置并加上 `head_margin`；否则从 `head_margin` 起按 `min_interval + gate` 排列，再对齐量化。
    private static func layoutNotes(
        source: [MidiNoteEvent],
        tempDivs: [ReferredNote],
        setting: BmhelperDivisionSetting,
        quantize: Int
    ) -> [MidiNoteEvent] {
        if setting.srcCopy {
            return zip(source, tempDivs).map { src, tempDiv in
                MidiNoteEvent(
                    position: src.position + setting.headMargin,
                    gate: tempDiv.gate,
                    noteNum: tempDiv.nn,
                    velocity: tempDiv.vel
                )
            }
        }
        var position = setting.headMargin
        var laid: [MidiNoteEvent] = []
        laid.reserveCapacity(tempDivs.count)
        for tempDiv in tempDivs {
            laid.append(
                MidiNoteEvent(
                    position: position,
                    gate: tempDiv.gate,
                    noteNum: tempDiv.nn,
                    velocity: tempDiv.vel
                )
            )
            position += setting.minInterval + tempDiv.gate
            let remainder = position % quantize
            if remainder != 0 {
                position += quantize - remainder
            }
        }
        return laid
    }

    static func formatDefinitionBlock(
        name: String,
        offset: Int,
        result: BmhelperDivisionResult
    ) -> String {
        BmhelperDefinitions.formatDefinitionBlock(
            name: name,
            offset: offset,
            zzStrings: result.definitions.map(\.zz),
            divs: result.definitions.map(\.div)
        )
    }

    private struct BasicNote {
        var nn: Int
        var gate: Int
        var vel: Int

        func accepts(_ note: BasicNote, gateThreshold: Int, velocityThreshold: Int) -> Bool {
            nn == note.nn
                && abs(gate - note.gate) <= gateThreshold
                && abs(vel - note.vel) <= velocityThreshold
        }
    }

    private struct IndexedNote {
        var basic: BasicNote
        var index: Int
    }

    private struct ReferredNote {
        var nn: Int
        var gate: Int
        var vel: Int
        var referrers: [Int]
    }

    private struct NotesCluster {
        var notes: [IndexedNote]

        mutating func accept(
            _ note: IndexedNote,
            gateThreshold: Int,
            velocityThreshold: Int
        ) -> Bool {
            for existing in notes where existing.basic.accepts(
                note.basic,
                gateThreshold: gateThreshold,
                velocityThreshold: velocityThreshold
            ) {
                notes.append(note)
                return true
            }
            return false
        }

        func divide(
            src2div: inout [Int],
            tempDivs: inout [ReferredNote],
            gateThreshold: Int,
            velocityThreshold: Int
        ) {
            guard let first = notes.first else { return }
            var gateMin = first.basic.gate
            var gateMax = first.basic.gate
            var velMin = first.basic.vel
            var velMax = first.basic.vel
            for note in notes {
                gateMin = min(gateMin, note.basic.gate)
                gateMax = max(gateMax, note.basic.gate)
                velMin = min(velMin, note.basic.vel)
                velMax = max(velMax, note.basic.vel)
            }
            gateMax += 1
            velMax += 1
            let gateDiv = (gateMax - gateMin + gateThreshold) / (gateThreshold + 1)
            let velDiv = (velMax - velMin + velocityThreshold) / (velocityThreshold + 1)
            var gateStart = gateMin
            for gateIndex in 0..<gateDiv {
                let gateNext = gateMin + (gateIndex + 1) * abs(gateMax - gateMin) / gateDiv
                var velStart = velMin
                for velIndex in 0..<velDiv {
                    let velNext = velMin + (velIndex + 1) * abs(velMax - velMin) / velDiv
                    var count = 0
                    let divIndex = tempDivs.count
                    var referred = ReferredNote(nn: 0, gate: 0, vel: 0, referrers: [])
                    for note in notes {
                        if note.basic.gate >= gateStart && note.basic.gate < gateNext
                            && note.basic.vel >= velStart && note.basic.vel < velNext
                        {
                            src2div[note.index] = divIndex
                            referred.referrers.append(note.index)
                            referred.nn += note.basic.nn
                            referred.gate += note.basic.gate
                            referred.vel += note.basic.vel
                            count += 1
                        }
                    }
                    if count > 0 {
                        referred.nn /= count
                        referred.gate /= count
                        referred.vel /= count
                        tempDivs.append(referred)
                    }
                    velStart = velNext
                }
                gateStart = gateNext
            }
        }
    }

    private static func divideNotes(
        _ notes: [MidiNoteEvent],
        src2div: inout [Int],
        tempDivs: inout [ReferredNote],
        setting: BmhelperDivisionSetting
    ) {
        var clusters: [NotesCluster] = []
        for (index, note) in notes.enumerated() {
            let indexed = IndexedNote(
                basic: BasicNote(nn: note.noteNum, gate: note.gate, vel: note.velocity),
                index: index
            )
            var accepted = false
            for clusterIndex in clusters.indices {
                if clusters[clusterIndex].accept(
                    indexed,
                    gateThreshold: setting.gateThreshold,
                    velocityThreshold: setting.velocityThreshold
                ) {
                    accepted = true
                    break
                }
            }
            if !accepted {
                clusters.append(NotesCluster(notes: [indexed]))
            }
        }
        for cluster in clusters {
            cluster.divide(
                src2div: &src2div,
                tempDivs: &tempDivs,
                gateThreshold: setting.gateThreshold,
                velocityThreshold: setting.velocityThreshold
            )
        }
    }

    private static func sortNotes(
        _ tempDivs: inout [ReferredNote],
        src2div: inout [Int],
        sortType: BmhelperDivisionSort
    ) {
        guard sortType != .none, tempDivs.count > 1 else { return }
        let compares = comparers(for: sortType)
        for first in 0..<(tempDivs.count - 1) {
            for second in (first + 1)..<tempDivs.count {
                if shouldSwap(tempDivs[first], tempDivs[second], compares: compares) {
                    tempDivs.swapAt(first, second)
                    for referrer in tempDivs[first].referrers {
                        src2div[referrer] = first
                    }
                    for referrer in tempDivs[second].referrers {
                        src2div[referrer] = second
                    }
                }
            }
        }
    }

    private static func comparers(for sortType: BmhelperDivisionSort) -> [(ReferredNote, ReferredNote) -> Int] {
        let nnAsc: (ReferredNote, ReferredNote) -> Int = { $0.nn - $1.nn }
        let gateDesc: (ReferredNote, ReferredNote) -> Int = { $1.gate - $0.gate }
        let velDesc: (ReferredNote, ReferredNote) -> Int = { $1.vel - $0.vel }
        switch sortType {
        case .none:
            return []
        case .nnGateVel:
            return [nnAsc, gateDesc, velDesc]
        case .nnVelGate:
            return [nnAsc, velDesc, gateDesc]
        case .gateNnVel:
            return [gateDesc, nnAsc, velDesc]
        case .gateVelNn:
            return [gateDesc, velDesc, nnAsc]
        case .velNnGate:
            return [velDesc, nnAsc, gateDesc]
        case .velGateNn:
            return [velDesc, gateDesc, nnAsc]
        }
    }

    private static func shouldSwap(
        _ left: ReferredNote,
        _ right: ReferredNote,
        compares: [(ReferredNote, ReferredNote) -> Int]
    ) -> Bool {
        for compare in compares {
            let value = compare(left, right)
            if value != 0 {
                return value > 0
            }
        }
        return false
    }

    private static func overloadCount(
        for cluster: ReferredNote,
        notes: [MidiNoteEvent],
        setting: BmhelperDivisionSetting
    ) -> Int {
        guard setting.mlDefinition, !cluster.referrers.isEmpty else {
            return 1
        }
        var count = 1
        while count <= cluster.referrers.count {
            var minimumGap = Int.max
            for start in 0..<count {
                var end = notes[cluster.referrers[start]].position + notes[cluster.referrers[start]].gate
                var cursor = start
                while cursor < cluster.referrers.count - count {
                    let next = cluster.referrers[cursor + count]
                    let nextPosition = notes[next].position
                    let nextEnd = nextPosition + notes[next].gate
                    minimumGap = min(minimumGap, nextPosition - end)
                    end = nextEnd
                    cursor += count
                }
            }
            if minimumGap >= setting.mlThreshold {
                break
            }
            count += 1
        }
        return count
    }
}
