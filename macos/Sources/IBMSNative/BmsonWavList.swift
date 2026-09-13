import Foundation

/// 主编辑器同一套 WAV 侧栏 ↔ BMSON `soundChannels`。
/// 不套 `#WAVxx`。下标 0 起对应 `01`、`02`…。
enum BmsonWavList {
    static func channels(from snapshots: [IBMSBmsonSoundChannelSnapshot]) -> [BmsonChartMapping.ChannelInput] {
        snapshots.map { channel in
            BmsonChartMapping.ChannelInput(
                name: channel.name,
                notes: channel.notes.map { note in
                    BmsonChartMapping.NoteInput(x: note.x, y: note.y, l: note.l, c: note.c)
                }
            )
        }
    }

    static func apply(
        _ edit: WavListEdit,
        to channels: [BmsonChartMapping.ChannelInput],
        synchronizeLabels: Bool
    ) -> [BmsonChartMapping.ChannelInput]? {
        let names = padded(edit.names)
        if names.contains(where: hasNewline) {
            return nil
        }
        var drafts = channels
        if synchronizeLabels && !edit.labelSwaps.isEmpty {
            for pair in edit.labelSwaps {
                let first = BmsonChartMapping.channelIndex(wavToken: pair.0)
                let second = BmsonChartMapping.channelIndex(wavToken: pair.1)
                guard first < LegacyWavList.slotCount, second < LegacyWavList.slotCount else {
                    return nil
                }
                pad(&drafts, to: max(first, second))
                drafts.swapAt(first, second)
            }
        } else {
            let lastNamed = names.lastIndex(where: { !$0.isEmpty }) ?? -1
            let lastKept = max(drafts.count - 1, lastNamed)
            if lastKept >= 0 {
                pad(&drafts, to: lastKept)
            }
            for index in drafts.indices {
                drafts[index].name = names[index]
            }
        }
        while let last = drafts.last, last.name.isEmpty && last.notes.isEmpty {
            drafts.removeLast()
        }
        return drafts
    }

    private static func padded(_ names: [String]) -> [String] {
        if names.count >= LegacyWavList.slotCount {
            return Array(names.prefix(LegacyWavList.slotCount))
        }
        return names + Array(repeating: "", count: LegacyWavList.slotCount - names.count)
    }

    private static func pad(_ drafts: inout [BmsonChartMapping.ChannelInput], to index: Int) {
        while drafts.count <= index {
            drafts.append(BmsonChartMapping.ChannelInput(name: "", notes: []))
        }
    }

    private static func hasNewline(_ name: String) -> Bool {
        name.contains(where: { $0 == "\n" || $0 == "\r" })
    }
}
