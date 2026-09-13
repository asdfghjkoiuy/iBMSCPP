import Foundation

/// woslicer 切片窗波形。帮助只写了「波形みれるように」，没有取样公式。
/// 列数和丢尾巴仿 `BmsonOverallWaveform`，这是工作规则，不是原版公式。
enum WoslicerWaveform {
    static let defaultWidth = 780
    static let defaultHeight = 80

    struct Column: Equatable, Sendable {
        var min: Float
        var max: Float
        var peak: Float
    }

    struct Payload: Equatable, Sendable {
        var columns: [Column]
        var duration: Double

        static let empty = Payload(columns: [], duration: 0)
    }

    /// 对照 `BmsonOverallWaveform.pcm16Float`：`/ 32768`。
    static func pcm16Float(_ sample: Int16) -> Float {
        Float(sample) / 32768
    }

    /// `frameCount / width`，向零取整。`width <= 0` 返回 0。
    static func samplesPerColumn(frameCount: Int, width: Int) -> Int {
        guard width > 0 else { return 0 }
        return max(frameCount, 0) / width
    }

    /// `seconds / duration * width`，向零取整，再夹到 `0 ... width-1`。
    static func markX(seconds: Double, duration: Double, width: Int) -> Int? {
        guard duration > 0, width > 0 else { return nil }
        let raw = Int(seconds / duration * Double(width))
        return min(max(raw, 0), width - 1)
    }

    /// 裁断线秒数走 `WoslicerSplit.splitPoints`（缺 `0` 会补上）。
    static func markXs(
        marks: [Double],
        offset: Double = 0,
        duration: Double,
        width: Int = defaultWidth
    ) -> [Int] {
        WoslicerSplit.splitPoints(marks: marks, offset: offset, duration: duration).compactMap { seconds in
            markX(seconds: seconds, duration: duration, width: width)
        }
    }

    static func columns(
        samples: [Int16],
        channels: Int,
        width: Int = defaultWidth
    ) -> [Column] {
        guard !samples.isEmpty, width > 0 else { return [] }
        let channelCount = max(channels, 1)
        let frameCount = samples.count / channelCount
        guard frameCount > 0 else { return [] }
        let per = samplesPerColumn(frameCount: frameCount, width: width)
        if per == 0 {
            return (0..<frameCount).map { frame in
                column(samples: samples, channels: channelCount, startFrame: frame, count: 1)
            }
        }
        return (0..<width).map { index in
            column(samples: samples, channels: channelCount, startFrame: index * per, count: per)
        }
    }

    /// 解码走 `AudioSlice.readPcm`，再去掉末端全 0 帧。缺文件或读失败返回空，不抛错。
    static func load(url: URL, width: Int = defaultWidth) -> Payload {
        guard let wav = try? AudioSlice.readPcm(url) else { return .empty }
        let trimmed = WoslicerTrim.trim(wav)
        let channelCount = max(trimmed.channels, 1)
        let frames = trimmed.samples.count / channelCount
        let duration = Double(frames) / Double(max(trimmed.sampleRate, 1))
        return Payload(
            columns: columns(samples: trimmed.samples, channels: trimmed.channels, width: width),
            duration: duration
        )
    }

    private static func column(
        samples: [Int16],
        channels: Int,
        startFrame: Int,
        count: Int
    ) -> Column {
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        let start = startFrame * channels
        let end = min(start + count * channels, samples.count)
        var index = start
        while index < end {
            let value = pcm16Float(samples[index])
            if value < minValue { minValue = value }
            if value > maxValue { maxValue = value }
            index += 1
        }
        guard minValue <= maxValue else {
            return Column(min: 0, max: 0, peak: 0)
        }
        return Column(
            min: minValue,
            max: maxValue,
            peak: max(abs(minValue), abs(maxValue))
        )
    }
}
