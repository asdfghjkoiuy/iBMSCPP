import Foundation

/// 时间选择 / MyO2 的 vpos 列值 ↔ BMSON 脉冲。计算仍走 iBMSC 公式；这里只做写回换算。
enum BmsonTimeSelection {
    /// 对照 `EditorColumn`。测试目标不链 `LegacyChartQuery`，数字写在这里。
    static let scroll = 1
    static let bpm = 2
    static let stop = 3
    static let a1 = 5
    static let a2 = 6
    static let a8 = 12
    static let d1 = 14
    static let d8 = 21
    static let bga = 23
    static let layer = 24
    static let poor = 25
    static let bgm = 27

    /// 对照 `LegacyMyO2.identifiersByColumn`。长音和 Hidden 都走短音通道。
    static let identifiersByColumn: [Int: Int] = [
        1: 99, 2: 3, 3: 9,
        5: 16, 6: 11, 7: 12, 8: 13, 9: 14, 10: 15, 11: 18, 12: 19,
        14: 21, 15: 22, 16: 23, 17: 24, 18: 25, 19: 28, 20: 29, 21: 26,
        23: 4, 24: 7, 25: 6, 27: 1
    ]

    struct SoundWrite: Equatable {
        var channelIndex: Int
        var x: Int64
        var y: Int64
        var l: Int64
    }

    struct TimingWrite: Equatable {
        var y: Int64
        var v: Double
    }

    struct BgaWrite: Equatable {
        var y: Int64
        var id: Int
    }

    struct PlannedWrite: Equatable {
        var sounds: [SoundWrite]
        var bpmNotes: [TimingWrite]
        var stopNotes: [TimingWrite]
        var bgaEvents: [BgaWrite]
        var layerEvents: [BgaWrite]
        var poorEvents: [BgaWrite]
    }

    static func shortChannel(for column: Int) -> String {
        String(format: "%02d", identifiersByColumn[column] ?? 0)
    }

    static func pulse(vPosition: Double, resolution: Int) -> Int64 {
        BmsonChartMapping.pulse(beat: vPosition / 48.0, resolution: resolution)
    }

    static func plan(
        notes: [(vPosition: Double, columnIndex: Int, value: Int, length: Double)],
        resolution: Int,
        mode: BmsONEViewMode,
        preserveStartBpm: Bool,
        initialBpm: Double
    ) -> PlannedWrite {
        var sounds: [SoundWrite] = []
        var bpmNotes: [TimingWrite] = []
        var stopNotes: [TimingWrite] = []
        var bgaEvents: [BgaWrite] = []
        var layerEvents: [BgaWrite] = []
        var poorEvents: [BgaWrite] = []

        for note in notes where note.vPosition >= 0 {
            let column = note.columnIndex
            if column == scroll {
                continue
            }
            let y = pulse(vPosition: note.vPosition, resolution: resolution)
            if column == bpm {
                bpmNotes.append(TimingWrite(y: y, v: Double(note.value) / 10_000.0))
                continue
            }
            if column == stop {
                let display = Double(note.value) / 10_000.0
                stopNotes.append(
                    TimingWrite(
                        y: y,
                        v: BmsonChartMapping.stopPulses(displayValue: display, resolution: resolution)
                    )
                )
                continue
            }
            if column == bga {
                bgaEvents.append(BgaWrite(y: y, id: bgaId(note.value)))
                continue
            }
            if column == layer {
                layerEvents.append(BgaWrite(y: y, id: bgaId(note.value)))
                continue
            }
            if column == poor {
                poorEvents.append(BgaWrite(y: y, id: bgaId(note.value)))
                continue
            }
            let isPlayable = (a1...a8).contains(column) || (d1...d8).contains(column)
            let isBgm = column >= bgm
            if !isPlayable && !isBgm {
                continue
            }
            let channelIndex = max(0, note.value / 10_000 - 1)
            let x: Int64
            if column >= bgm {
                x = 0
            } else {
                x = BmsonChartMapping.laneX(forChannel: shortChannel(for: column), mode: mode)
            }
            let length = note.length > 0
                ? pulse(vPosition: note.length, resolution: resolution)
                : 0
            sounds.append(SoundWrite(channelIndex: channelIndex, x: x, y: y, l: length))
        }

        if preserveStartBpm {
            if let index = bpmNotes.firstIndex(where: { $0.y == 0 }) {
                bpmNotes[index].v = initialBpm
            } else {
                bpmNotes.insert(TimingWrite(y: 0, v: initialBpm), at: 0)
            }
        }

        return PlannedWrite(
            sounds: sounds,
            bpmNotes: bpmNotes,
            stopNotes: stopNotes,
            bgaEvents: bgaEvents,
            layerEvents: layerEvents,
            poorEvents: poorEvents
        )
    }

    private static func bgaId(_ value: Int) -> Int {
        let token = String(format: "%02d", max(0, value / 10_000))
        return BmsonChartMapping.bmpId(token: token) ?? max(0, value / 10_000)
    }
}
