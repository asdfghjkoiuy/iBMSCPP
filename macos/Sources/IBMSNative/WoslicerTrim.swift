import Foundation

/// 去掉末端全 0 帧。帮助只写了「末端無音除去」，没有阈值。
/// 只认 `Int16 == 0`，只去末尾连续静音帧。这是工作规则，不是原版公式。
enum WoslicerTrim {
    /// 从最后一帧往前数连续静音帧。立体声要这一帧所有声道都是 0。
    static func trailingSilentFrames(samples: [Int16], channels: Int) -> Int {
        let channelCount = max(channels, 1)
        let frameCount = samples.count / channelCount
        guard frameCount > 0 else { return 0 }
        var count = 0
        var frame = frameCount - 1
        while frame >= 0 {
            let base = frame * channelCount
            var silent = true
            var channel = 0
            while channel < channelCount {
                if samples[base + channel] != 0 {
                    silent = false
                    break
                }
                channel += 1
            }
            if !silent { break }
            count += 1
            frame -= 1
        }
        return count
    }

    /// 丢掉末端连续静音帧。开头和中间的 0 留下。全是 0 则样本变空。
    static func trim(_ wav: BmhelperPcmWav) -> BmhelperPcmWav {
        let dropped = trailingSilentFrames(samples: wav.samples, channels: wav.channels)
        guard dropped > 0 else { return wav }
        let channelCount = max(wav.channels, 1)
        let keep = max(wav.samples.count - dropped * channelCount, 0)
        return BmhelperPcmWav(
            sampleRate: wav.sampleRate,
            channels: wav.channels,
            samples: Array(wav.samples.prefix(keep))
        )
    }
}
