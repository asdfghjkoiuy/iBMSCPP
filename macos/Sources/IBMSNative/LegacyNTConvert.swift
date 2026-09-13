import Foundation

/// 对照 `MainWindow.ConvertBMSE2NT` / `ConvertNT2BMSE`。
enum LegacyNTConvert {
    /// BMSE 的 `LongNote` 两两配成长度。同一列上若先碰到 `Value \ 10000 = LnObj`，停止搜索、不配对。
    /// 我们的数组没有原版 `Notes(0)` 头 BPM，从下标 0 起。
    static func convertBMSE2NT(_ notes: [LegacyClipboardNote], lnobj: Int = 0) -> [LegacyClipboardNote] {
        var next = notes.sorted { $0.vPosition < $1.vPosition }
        for index in next.indices {
            next[index].length = 0
        }
        var index = 0
        while index < next.count {
            if !next[index].longNote {
                index += 1
                continue
            }
            var partner = index + 1
            while partner < next.count {
                if next[partner].columnIndex != next[index].columnIndex {
                    partner += 1
                    continue
                }
                if next[partner].longNote {
                    next[index].length = next[partner].vPosition - next[index].vPosition
                    next.remove(at: partner)
                    break
                }
                if next[partner].value / 10_000 == lnobj {
                    break
                }
                partner += 1
            }
            index += 1
        }
        for index in next.indices {
            next[index].longNote = false
        }
        return next
    }

    /// `Length > 0` 拆成两颗 `LongNote`。终点 `Landmine = False`，Hidden / Value 拷过去。
    static func convertNT2BMSE(_ notes: [LegacyClipboardNote]) -> [LegacyClipboardNote] {
        var result: [LegacyClipboardNote] = []
        for note in notes {
            var start = note
            start.length = 0
            start.longNote = note.length > 0
            result.append(start)
            if note.length > 0 {
                var end = start
                end.longNote = true
                end.landmine = false
                end.vPosition = note.vPosition + note.length
                result.append(end)
            }
        }
        return result
    }
}
