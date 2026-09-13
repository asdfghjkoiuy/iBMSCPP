import Foundation

enum Legacy1296Kind: Equatable {
    case bpm
    case stop
}

/// 原版 `ChartIO.vb`：开关关掉时，`#BPM` / `#STOP` 和通道 `08` / `09` 的标签用十六进制 `01`–`FF`（上限 255）。打开时用三十六进制 `01`–`ZZ`（上限 1295）。超限仍写出，只弹警告。
///
/// 核心插入和读入已按 `IndexedTimingRadix` 走同一套进制。通道 `03` 永远十六进制。
/// 保存时按当前开关改写已经在文件里的 `#BPM` / `#STOP` 和通道 `08` / `09` 标签。
enum Legacy1296Write {
    static let warning = "Warning: "
    static let noteOverlap = "Note operlapping detected. Increasing Maximum Grid Partition will resolve this."
    static let bpmOverflow = "Numbers of multi-byte BPMs has exceeded supported maximum: "
    static let stopOverflow = "Numbers of STOPs has exceeded supported maximum: "
    static let scrollOverflow = "Numbers of multi-byte SCROLLs has exceeded supported maximum: "
    static let savedFileWillContainErrors = "The saved file will contain errors."

    struct MessageLabels: Equatable {
        var warning: String = Legacy1296Write.warning
        var noteOverlap: String = Legacy1296Write.noteOverlap
        var bpmOverflow: String = Legacy1296Write.bpmOverflow
        var stopOverflow: String = Legacy1296Write.stopOverflow
        var scrollOverflow: String = Legacy1296Write.scrollOverflow
        var savedFileWillContainErrors: String = Legacy1296Write.savedFileWillContainErrors

        static let english = MessageLabels()
    }

    static func limit(enabled: Bool) -> Int {
        enabled ? 1295 : 255
    }

    static func isChannel03BPM(_ value: Int) -> Bool {
        value % 10_000 == 0 && (1...255).contains(value / 10_000)
    }

    static func uniqueCount(_ values: [Int]) -> Int {
        Set(values).count
    }

    static func uniqueExtendedBPMCount(_ values: [Int]) -> Int {
        uniqueCount(values.filter { !isChannel03BPM($0) })
    }

    static func overflowMessage(
        kind: Legacy1296Kind,
        count: Int,
        enabled: Bool,
        labels: MessageLabels = .english
    ) -> String? {
        let maximum = limit(enabled: enabled)
        guard count > maximum else { return nil }
        let body = kind == .bpm ? labels.bpmOverflow : labels.stopOverflow
        return labels.warning + "\n" + body + "\(count) > \(maximum)\n" + labels.savedFileWillContainErrors
    }

    static func messages(
        bpmValues: [Int],
        stopValues: [Int],
        bpm1296: Bool,
        stop1296: Bool,
        labels: MessageLabels = .english
    ) -> [String] {
        [
            overflowMessage(
                kind: .bpm, count: uniqueExtendedBPMCount(bpmValues), enabled: bpm1296, labels: labels
            ),
            overflowMessage(kind: .stop, count: uniqueCount(stopValues), enabled: stop1296, labels: labels)
        ].compactMap { $0 }
    }

    static func overlapMessage(labels: MessageLabels = .english) -> String {
        labels.warning + "\n" + labels.noteOverlap + "\n" + labels.savedFileWillContainErrors
    }

    static func scrollOverflowMessage(count: Int, labels: MessageLabels = .english) -> String? {
        guard count > 1295 else { return nil }
        return labels.warning + "\n" + labels.scrollOverflow + "\(count) > 1295\n" + labels.savedFileWillContainErrors
    }

    /// `ChartIO.SaveBMS` 318–330: overlap, then `UBound(hBPM)` / `hSTOP` / `hSCROLL`.
    static func saveMessages(
        overlapping: Bool,
        bpmCount: Int,
        stopCount: Int,
        scrollCount: Int,
        bpm1296: Bool,
        stop1296: Bool,
        labels: MessageLabels = .english
    ) -> [String] {
        var result: [String] = []
        if overlapping {
            result.append(overlapMessage(labels: labels))
        }
        if let message = overflowMessage(kind: .bpm, count: bpmCount, enabled: bpm1296, labels: labels) {
            result.append(message)
        }
        if let message = overflowMessage(kind: .stop, count: stopCount, enabled: stop1296, labels: labels) {
            result.append(message)
        }
        if let message = scrollOverflowMessage(count: scrollCount, labels: labels) {
            result.append(message)
        }
        return result
    }

    static func integerValue(decimal: String) -> Int? {
        guard let parsed = Double(decimal) else { return nil }
        return Int((parsed * 10_000).rounded())
    }
}
