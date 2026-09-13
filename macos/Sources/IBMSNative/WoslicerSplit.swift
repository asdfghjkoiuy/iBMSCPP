import Foundation

/// woslicer 切点。帮助只写了裁断线，没有公式。
/// 裁断线加上起点 `0`，最后一段切到文件末尾。这是工作规则，不是从 exe 反出来的。
enum WoslicerSplit {
    /// 帮助：`原文件名_xxx.wav`。三位序号从 1 起。
    static func outputFileName(base: String, indexFromZero: Int) -> String {
        String(format: "%@_%03d.wav", base, indexFromZero + 1)
    }

    static func defaultBaseName(input: URL) -> String {
        let stem = input.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "slice" : stem
    }

    /// `offset` 是秒。帮助没写 `[8][7]` 的步长，这里只提供可测的整体平移。
    static func splitPoints(marks: [Double], offset: Double = 0, duration: Double? = nil) -> [Double] {
        var times = marks.map { $0 + offset }
        if let duration {
            times = times.map { min(max($0, 0), max(duration, 0)) }
        } else {
            times = times.map { max($0, 0) }
        }
        if times.contains(where: { abs($0) < 1e-12 }) == false {
            times.append(0)
        }
        var unique = Set<Double>()
        for time in times {
            unique.insert(time)
        }
        return unique.sorted()
    }

    static func toggleMark(_ mark: Double, in marks: [Double], tolerance: Double = 1e-9) -> [Double] {
        if let index = marks.firstIndex(where: { abs($0 - mark) <= tolerance }) {
            var next = marks
            next.remove(at: index)
            return next
        }
        return (marks + [mark]).sorted()
    }
}

/// woslicer 预览区间。II `[P]`/`[Enter]` 播当前段，III `[O]` 播前一段。
/// 帮助没写起止秒。切点与切片同一套（缺 `0` 补上），末尾接到文件时长。这是工作规则。
enum WoslicerPreview {
    static func boundaries(marks: [Double], duration: Double, offset: Double = 0) -> [Double] {
        let safeDuration = max(duration, 0)
        var points = WoslicerSplit.splitPoints(marks: marks, offset: offset, duration: safeDuration)
        if safeDuration > 0, points.last.map({ abs($0 - safeDuration) > 1e-12 }) ?? true {
            points.append(safeDuration)
        }
        return points.filter { $0 <= safeDuration + 1e-12 }
    }

    static func currentSegment(
        current: Double,
        marks: [Double],
        duration: Double,
        offset: Double = 0
    ) -> (start: Double, end: Double)? {
        let points = boundaries(marks: marks, duration: duration, offset: offset)
        guard points.count >= 2 else { return nil }
        let time = min(max(current, 0), max(duration, 0))
        var index = 0
        for candidate in 0..<(points.count - 1) where points[candidate] <= time + 1e-12 {
            index = candidate
        }
        let start = points[index]
        let end = points[index + 1]
        guard end > start + 1e-12 else { return nil }
        return (start, end)
    }

    static func previousSegment(
        current: Double,
        marks: [Double],
        duration: Double,
        offset: Double = 0
    ) -> (start: Double, end: Double)? {
        let points = boundaries(marks: marks, duration: duration, offset: offset)
        guard let current = currentSegment(
            current: current,
            marks: marks,
            duration: duration,
            offset: offset
        ) else {
            return nil
        }
        guard let index = points.firstIndex(where: { abs($0 - current.start) <= 1e-12 }), index >= 1 else {
            return nil
        }
        let start = points[index - 1]
        let end = points[index]
        guard end > start + 1e-12 else { return nil }
        return (start, end)
    }
}
