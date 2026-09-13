import Foundation

/// woslicer `[V]` / `[B]` / `[A][S]` / `[N]`。帮助只写了 BMSE 剪贴板和连号，没有公式。
/// 秒 → vpos、缺 `0` 时补上、默认起点 `1`、FF 全用 `FF`，都是工作规则，不是从 exe 反出来的。
enum WoslicerClipboard {
    static let defaultBPM = 120.0
    static let defaultSequenceStart = 1
    static let ticksPerBeat = 48.0
    static let ffToken = "FF"
    static let minSequence = 1
    static let maxSequence = 1295

    static func vPosition(seconds: Double, bpm: Double) -> Double {
        seconds * bpm / 60.0 * ticksPerBeat
    }

    static func seconds(vPosition: Double, bpm: Double) -> Double {
        vPosition * 60.0 / (bpm * ticksPerBeat)
    }

    static func nudgeSequenceStart(_ start: Int, delta: Int) -> Int {
        min(maxSequence, max(minSequence, start + delta))
    }

    static func encode(
        marks: [Double],
        offset: Double = 0,
        bpm: Double,
        sequenceStart: Int = defaultSequenceStart,
        ffDefinition: Bool = false
    ) -> String? {
        guard bpm > 0, bpm.isFinite else { return nil }
        let times = WoslicerSplit.splitPoints(marks: marks.filter(\.isFinite), offset: offset)
            .filter(\.isFinite)
        guard !times.isEmpty else { return nil }
        let start = nudgeSequenceStart(sequenceStart, delta: 0)
        let column = LegacyClipboard.columnIndex(forChannel: "01")
        let notes = times.enumerated().map { index, time in
            LegacyClipboardNote(
                columnIndex: column,
                vPosition: vPosition(seconds: time, bpm: bpm),
                value: noteValue(sequenceStart: start, index: index, ffDefinition: ffDefinition),
                length: 0,
                longNote: false,
                hidden: false,
                landmine: false
            )
        }
        return LegacyClipboard.encodeObject(notes)
    }

    /// 读 BMSE Object 或 iBMSC 剪贴板。vpos 按原样换算成秒，不加编辑器粘贴那种小节偏移。
    static func decodeMarks(_ text: String, bpm: Double) -> [Double]? {
        guard bpm > 0, bpm.isFinite else { return nil }
        guard let payload = LegacyClipboard.decode(text), !payload.notes.isEmpty else {
            return nil
        }
        var times: [Double] = []
        for note in payload.notes {
            let time = seconds(vPosition: note.vPosition, bpm: bpm)
            guard time.isFinite, time >= 0 else { continue }
            if times.contains(where: { abs($0 - time) <= 1e-9 }) { continue }
            times.append(time)
        }
        if times.isEmpty { return nil }
        return times.sorted()
    }

    private static func noteValue(sequenceStart: Int, index: Int, ffDefinition: Bool) -> Int {
        if ffDefinition {
            return LegacyClipboard.tokenValue(ffToken)
        }
        return nudgeSequenceStart(sequenceStart, delta: index) * 10000
    }
}
