import Foundation

/// 对照 `Waveform.vb` 读入和 `PanelDraw.DrawWaveform` 的采样公式。
enum LegacyWaveform {
    struct Segment: Equatable {
        var vPosition: Double
        var bpm: Double
    }

    struct Buffer {
        var left: [Float]
        var right: [Float]
        var sampleRate: Int
        var locked: Bool = true
        var position: Double = 0
        var leftInset: Int = LegacyWaveform.defaultLeft
        var width: Int = LegacyWaveform.defaultWidth
        var precision: Int = LegacyWaveform.defaultPrecision
    }

    /// Designer `TWLeft.Value`。`Waveform.vb` 的字段初值会被 `ValueChanged` 盖掉。
    static let defaultLeft = 50
    /// Designer `TWWidth.Value`。
    static let defaultWidth = 200
    /// Designer `TWPrecision.Value`。
    static let defaultPrecision = 5
    /// Designer `TWTransparency.Value`。
    static let defaultTransparency = 80
    /// Designer `TWSaturation` 没有初值，NumericUpDown 默认 0。灰波形的 `.NET` 饱和度也是 0。
    static let defaultSaturation = 0
    /// `Waveform.vb` 的 `wPosition` 默认 `0`。Designer 启动文案是 `0.00`。
    static let defaultPosition: Double = 0
    /// Designer `TWPosition.Maximum`。没写 Minimum，NumericUpDown 默认 0。
    static let positionMaximum: Double = 192_000
    /// Designer `TWPosition2.Maximum`。
    static let sliderMaximum = 960

    static func clampLeft(_ value: Int) -> Int { min(max(value, 0), 800) }
    static func clampWidth(_ value: Int) -> Int { min(max(value, 0), 1000) }
    static func clampPrecision(_ value: Int) -> Int { min(max(value, 0), 50) }
    static func clampTransparency(_ value: Int) -> Int { min(max(value, 0), 255) }
    static func clampSaturation(_ value: Int) -> Int { min(max(value, 0), 1000) }

    /// 夹到 `0…192000`。边界只比整数，避免银行家舍入争议。
    static func clampPosition(_ value: Double) -> Double {
        if value < 0 { return 0 }
        if value > positionMaximum { return positionMaximum }
        return value
    }

    /// `TWPosition2.Value = IIf(wPosition > Maximum, Maximum, wPosition)`。整数向零取整。
    static func sliderValue(_ position: Double) -> Int {
        let truncated = Int(clampPosition(position).rounded(.towardZero))
        return min(sliderMaximum, max(0, truncated))
    }

    /// 锁开：第一颗 B 列音的 vpos，没有则 0。锁关：数字框里的 `wPosition`。
    /// 锁开时不把这个值写回数字框。
    static func drawingPosition(
        locked: Bool,
        fieldPosition: Double,
        firstBGMVPosition: Double?
    ) -> Double {
        if locked {
            return lockPosition(firstBGMVPosition: firstBGMVPosition)
        }
        return clampPosition(fieldPosition)
    }

    /// `Color.FromArgb(TWTransparency.Value, vo.pBGMWav.Color)`：只改 Alpha。
    static func applyTransparency(_ color: ThemeColor, alpha: Int) -> ThemeColor {
        color.replacing(alpha: UInt8(clampTransparency(alpha)))
    }

    /// `HSL2RGB(GetHue, TWSaturation.Value, GetBrightness * 1000, A)`。
    static func applySaturation(_ color: ThemeColor, saturation: Int) -> ThemeColor {
        let hsl = LegacyColorMath.netHSL(from: color)
        return LegacyColorMath.hsl2rgb(ColorPickerHSLA(
            hue: hsl.hue,
            saturation: clampSaturation(saturation),
            lightness: hsl.lightness,
            alpha: hsl.alpha
        ))
    }

    /// `GetSaturation * 1000`，给侧栏数字框用。
    static func saturationSlider(from color: ThemeColor) -> Int {
        clampSaturation(LegacyColorMath.netHSL(from: color).saturation)
    }

    /// `Dim xPts(xTHeight * wPrecision)`。精度 0 时 `DrawWaveform` 整段跳过。
    static func sampleCount(height: Int, precision: Int) -> Int {
        let steps = clampPrecision(precision)
        if steps <= 0 || height < 0 { return 0 }
        return height * steps + 1
    }

    static func pointY(index: Int, precision: Int) -> Double {
        let steps = clampPrecision(precision)
        guard steps > 0 else { return 0 }
        return Double(index) / Double(steps)
    }

    /// 每格 vpos 对应 `1.25 / BPM` 秒：48 vpos 一拍，`60 / 48 = 1.25`。
    static let secondsPerVPositionAtBPM1 = 1.25

    static func deinterleaveStereo(_ samples: [Float]) -> (left: [Float], right: [Float]) {
        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity((samples.count + 1) / 2)
        right.reserveCapacity(samples.count / 2)
        var index = 0
        while index < samples.count {
            left.append(samples[index])
            if index + 1 < samples.count {
                right.append(samples[index + 1])
            }
            index += 2
        }
        return (left, right)
    }

    static func lockPosition(firstBGMVPosition: Double?) -> Double {
        firstBGMVPosition ?? 0
    }

    static func segments(
        headBPM: Double,
        bpmEvents: [(vPosition: Double, bpm: Double)],
        lockPosition: Double
    ) -> [Segment] {
        var initial = headBPM
        var later: [Segment] = []
        for event in bpmEvents.sorted(by: { $0.vPosition < $1.vPosition }) {
            if event.vPosition >= lockPosition {
                later.append(Segment(vPosition: event.vPosition, bpm: event.bpm))
            } else {
                initial = event.bpm
            }
        }
        return [Segment(vPosition: lockPosition, bpm: initial)] + later
    }

    /// 一次波形构建共用。`segments` 需按 `vPosition` 升序，`segments()` 的结果满足这一点。
    struct SampleLookup {
        private let segments: [Segment]
        private let originSamples: [Double]
        let sampleRate: Int

        init(segments: [Segment], sampleRate: Int) {
            self.segments = segments
            self.sampleRate = sampleRate
            var origins: [Double] = []
            origins.reserveCapacity(segments.count)
            var accumulated = 0.0
            for index in segments.indices {
                origins.append(accumulated)
                let next = index + 1
                if next < segments.count {
                    accumulated += LegacyWaveform.deltaSamples(
                        from: segments[index].vPosition,
                        to: segments[next].vPosition,
                        bpm: segments[index].bpm,
                        sampleRate: sampleRate
                    )
                }
            }
            originSamples = origins
        }

        func sampleIndex(vPosition: Double) -> Double {
            guard segments.first != nil, sampleRate > 0 else { return 0 }
            let index = segmentIndex(atOrBefore: vPosition)
            let segment = segments[index]
            return originSamples[index] + LegacyWaveform.deltaSamples(
                from: segment.vPosition,
                to: vPosition,
                bpm: segment.bpm,
                sampleRate: sampleRate
            )
        }

        private func segmentIndex(atOrBefore vPosition: Double) -> Int {
            var low = 0
            var high = segments.count
            while low < high {
                let middle = (low + high) / 2
                if segments[middle].vPosition <= vPosition {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return max(0, low - 1)
        }
    }

    static func sampleIndex(vPosition: Double, segments: [Segment], sampleRate: Int) -> Double {
        SampleLookup(segments: segments, sampleRate: sampleRate).sampleIndex(vPosition: vPosition)
    }

    static func pointX(sample: Float, width: Int, left: Int) -> Double {
        Double(sample) * Double(width) + Double(left)
    }

    private static func deltaSamples(from: Double, to: Double, bpm: Double, sampleRate: Int) -> Double {
        guard bpm != 0 else { return 0 }
        return (to - from) * secondsPerVPositionAtBPM1 * Double(sampleRate) / bpm
    }
}
