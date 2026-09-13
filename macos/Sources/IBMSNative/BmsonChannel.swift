import Foundation

/// 对照 BmsONE `InsertNewSoundChannels` / `DestroySoundChannel` / `MoveSoundChannel`
/// 和 `MatchChannelNameKeyword`。只改 BMSON `soundChannels`，不套 `#WAV`。
/// 对照 `SequenceViewWriteMode.cpp`：`SoundNote(iTime, lane, 0, Shift ? 0 : 1)`。
/// `noteType > 0` 写出 `c == true`。不按 Shift 是续播，按 Shift 是新触发。
enum BmsonWriteContinue {
    static func flag(shiftHeld: Bool) -> Bool {
        !shiftHeld
    }
}

enum BmsonChannel {
    typealias Channel = BmsonChartMapping.ChannelInput

    /// `InsertNewSoundChannels`：`index < 0` 接到末尾。
    static func add(names: [String], to channels: [Channel], at index: Int = -1) -> [Channel]? {
        let trimmed = names.map { fileName(from: $0) }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(where: hasNewline) { return nil }
        var next = channels
        var insertAt = index < 0 ? next.count : index
        insertAt = min(max(0, insertAt), next.count)
        for (offset, name) in trimmed.enumerated() {
            next.insert(Channel(name: name, notes: []), at: insertAt + offset)
        }
        return next
    }

    static func destroy(index: Int, in channels: [Channel]) -> [Channel]? {
        guard channels.indices.contains(index) else { return nil }
        var next = channels
        next.remove(at: index)
        return next
    }

    /// `MoveSoundChannel`：目标下标夹在 `0…count-1`。相同则不动。
    static func move(from index: Int, to destination: Int, in channels: [Channel]) -> [Channel]? {
        guard channels.indices.contains(index) else { return nil }
        let clamped = min(max(0, destination), channels.count - 1)
        if clamped == index { return nil }
        var next = channels
        let item = next.remove(at: index)
        next.insert(item, at: clamped)
        return next
    }

    static func setName(index: Int, path: String, in channels: [Channel]) -> [Channel]? {
        guard channels.indices.contains(index) else { return nil }
        let name = fileName(from: path)
        if hasNewline(name) { return nil }
        if channels[index].name == name { return nil }
        var next = channels
        next[index].name = name
        return next
    }

    /// `ChannelPrev`：没有当前声道则不动。
    static func selectPrevious(current: Int, count: Int) -> Int? {
        guard count > 0, current >= 0 else { return nil }
        return current == 0 ? count - 1 : current - 1
    }

    /// `ChannelNext`：没有当前声道则不动。
    static func selectNext(current: Int, count: Int) -> Int? {
        guard count > 0, current >= 0 else { return nil }
        return current == count - 1 ? 0 : current + 1
    }

    /// `QString::contains`，区分大小写。空关键字对得上每一项。
    /// Foundation 里 `String.contains("")` 是假，这里按 Qt 写成真。
    static func matches(_ name: String, keyword: String) -> Bool {
        if keyword.isEmpty { return true }
        return name.contains(keyword)
    }

    /// `ChannelDisplayFilteringConditionsChanged`：
    /// `show = !hideOthers || (match && (!filterActive || active))`。
    static func isShown(
        hideOthers: Bool,
        name: String,
        keyword: String,
        isActive: Bool,
        filterActive: Bool
    ) -> Bool {
        if !hideOthers { return true }
        return matches(name, keyword: keyword) && (!filterActive || isActive)
    }

    static func shownMask(
        hideOthers: Bool,
        names: [String],
        keyword: String,
        activeInRegion: [Bool]?,
        filterActive: Bool
    ) -> [Bool] {
        names.enumerated().map { index, name in
            let active = activeInRegion?[index] ?? false
            return isShown(
                hideOthers: hideOthers,
                name: name,
                keyword: keyword,
                isActive: active,
                filterActive: filterActive
            )
        }
    }

    /// 没对上的声道留下名字、清空音符。共用谱面用来藏住该道的音。
    static func visibleChannels(_ channels: [Channel], shown: [Bool]?) -> [Channel] {
        guard let shown else { return channels }
        return channels.enumerated().map { index, channel in
            if shown.indices.contains(index), !shown[index] {
                return Channel(name: channel.name, notes: [])
            }
            return channel
        }
    }

    /// 对照 `DocumentDef.h` `WaveSummary`。`FrameCount > 0` 才算有效。
    struct WaveSummary: Equatable {
        var frameCount: Int64
        var sampleRate: Double
        var channelCount: Int
        var sampleSize: Int

        init(frameCount: Int64, sampleRate: Double, channelCount: Int = 0, sampleSize: Int = 16) {
            self.frameCount = frameCount
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.sampleSize = sampleSize
        }

        /// 对照 `WaveSummary::IsValid`：只看 `FrameCount > 0`。
        var isValid: Bool { frameCount > 0 }
    }

    /// 交错 PCM：`samples.count / channels` 是帧数。
    static func waveSummary(
        sampleCount: Int,
        channels: Int,
        sampleRate: Int,
        sampleSize: Int = 16
    ) -> WaveSummary {
        WaveSummary(
            frameCount: Int64(max(sampleCount, 0) / max(channels, 1)),
            sampleRate: Double(sampleRate),
            channelCount: max(channels, 0),
            sampleSize: sampleSize
        )
    }

    /// 对照 `ChannelInfoView::TextForSamplingRate`。
    static func textForSamplingRate(_ rate: Int) -> String {
        if rate % 1000 == 0 {
            return "\(rate / 1000)kHz"
        }
        if rate % 100 == 0 {
            return "\(rate / 1000).\((rate / 100) % 10)kHz"
        }
        if rate % 10 == 0 {
            return "\(rate / 1000).\((rate / 100) % 10)\((rate / 10) % 10)kHz"
        }
        return "\(rate / 1000).\((rate / 100) % 10)\((rate / 10) % 10)\(rate % 10)kHz"
    }

    /// 对照 `ChannelInfoView::WaveSummaryUpdated`：`%1bit/%2ch/%3` 和 `%1 sec`。
    /// `QString::arg(qreal)` 默认 `g`、精度 6。无效摘要两段都空。
    static func channelInfoLabels(_ wave: WaveSummary?) -> (format: String, length: String) {
        guard let wave, wave.isValid, wave.sampleRate > 0 else {
            return ("", "")
        }
        let rate = Int(wave.sampleRate)
        let channels = max(wave.channelCount, 1)
        let bits = wave.sampleSize > 0 ? wave.sampleSize : 16
        let seconds = Double(wave.frameCount) / wave.sampleRate
        return (
            "\(bits)bit/\(channels)ch/\(textForSamplingRate(rate))",
            "\(qtGeneral(seconds)) sec"
        )
    }

    /// 对照 `QString::arg(double)` 默认 `g` / 6。
    static func qtGeneral(_ value: Double) -> String {
        String(format: "%g", value)
    }

    /// 对照 `SoundChannel::CacheEntry`。
    struct PlaybackCacheEntry: Equatable {
        var key: Int
        var currentSamplePosition: Int64
        var prevSamplePosition: Int64
        var currentTempo: Double
        var prevTempo: Double
    }

    /// `SoundChannel::IsActiveInRegion` 的音符部分。
    /// `QMap::upperBound`：起点在 `(tBegin, tEnd]`。
    /// `tBegin >= tEnd` 为假。
    static func isActiveInRegion(locations: [Int64], tBegin: Int, tEnd: Int) -> Bool {
        guard tBegin < tEnd else { return false }
        let begin = Int64(tBegin)
        let end = Int64(tEnd)
        return locations.contains { $0 > begin && $0 <= end }
    }

    /// 对照完整 `IsActiveInRegion`。
    /// 没有波形摘要时只看音符，兼容已有夹具。
    /// 摘要无效（文件没解开）时整道不算活动。
    /// 有效时：缓存里 `currentSamplePosition >= 0` 算还在响，音符仍看 `(tBegin, tEnd]`。
    /// `c == true` 不重新触发，对照 `noteType != 0`。
    static func isActiveInRegion(
        notes: [(y: Int64, c: Bool)],
        tBegin: Int,
        tEnd: Int,
        wave: WaveSummary?,
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)] = []
    ) -> Bool {
        guard tBegin < tEnd else { return false }
        if let wave {
            guard wave.isValid else { return false }
            let cache = playbackCache(
                notes: notes,
                wave: wave,
                initBpm: initBpm,
                resolution: resolution,
                bpmNotes: bpmNotes
            )
            if cacheIsPlaying(cache, tBegin: tBegin, tEnd: tEnd) {
                return true
            }
        }
        return isActiveInRegion(locations: notes.map(\.y), tBegin: tBegin, tEnd: tEnd)
    }

    /// 对照 `SoundChannel::UpdateCache`。只给 `IsActiveInRegion` 用。
    static func playbackCache(
        notes: [(y: Int64, c: Bool)],
        wave: WaveSummary,
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)] = []
    ) -> [PlaybackCacheEntry] {
        guard wave.isValid, wave.sampleRate > 0 else { return [] }
        let triggers = uniqueLocations(notes.filter { !$0.c }.map(\.y))
        let tempos = uniqueTempoEvents(bpmNotes)
        var iNote = 0
        var iTempo = 0
        var loc = 0
        var soundEndsAt = -1
        var currentSamplesPerTick = samplesPerTick(
            sampleRate: wave.sampleRate,
            tempo: initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm,
            resolution: resolution
        )
        var entry = PlaybackCacheEntry(
            key: 0,
            currentSamplePosition: -1,
            prevSamplePosition: -1,
            currentTempo: initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm,
            prevTempo: initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm
        )
        var cache: [PlaybackCacheEntry] = []
        func insert() {
            var stored = entry
            stored.key = loc
            cache.append(stored)
        }
        while true {
            let hasNote = iNote < triggers.count
            let hasTempo = iTempo < tempos.count
            if hasNote, !hasTempo || triggers[iNote] < tempos[iTempo].y {
                if entry.currentSamplePosition < 0 {
                    entry.prevSamplePosition = -1
                    entry.currentSamplePosition = 0
                    entry.prevTempo = entry.currentTempo
                    loc = triggers[iNote]
                    insert()
                    soundEndsAt = loc + Int(Double(wave.frameCount) / currentSamplesPerTick)
                    iNote += 1
                } else if soundEndsAt < triggers[iNote] {
                    entry.prevSamplePosition = wave.frameCount
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = -1
                    loc = soundEndsAt
                    insert()
                } else {
                    let played = entry.currentSamplePosition
                        + Int64(Double(triggers[iNote] - loc) * currentSamplesPerTick)
                    entry.prevSamplePosition = min(played, wave.frameCount)
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = 0
                    loc = triggers[iNote]
                    insert()
                    soundEndsAt = loc + Int(Double(wave.frameCount) / currentSamplesPerTick)
                    iNote += 1
                }
            } else if hasNote, hasTempo, triggers[iNote] == tempos[iTempo].y {
                if entry.currentSamplePosition < 0 {
                    entry.prevSamplePosition = -1
                    entry.currentSamplePosition = 0
                    entry.prevTempo = entry.currentTempo
                    entry.currentTempo = tempos[iTempo].v
                    currentSamplesPerTick = samplesPerTick(
                        sampleRate: wave.sampleRate,
                        tempo: tempos[iTempo].v,
                        resolution: resolution
                    )
                    loc = triggers[iNote]
                    insert()
                    soundEndsAt = loc + Int(Double(wave.frameCount) / currentSamplesPerTick)
                    iNote += 1
                    iTempo += 1
                } else if soundEndsAt < triggers[iNote] {
                    entry.prevSamplePosition = wave.frameCount
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = -1
                    loc = soundEndsAt
                    insert()
                } else {
                    let played = entry.currentSamplePosition
                        + Int64(Double(triggers[iNote] - loc) * currentSamplesPerTick)
                    entry.prevSamplePosition = min(played, wave.frameCount)
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = 0
                    entry.currentTempo = tempos[iTempo].v
                    currentSamplesPerTick = samplesPerTick(
                        sampleRate: wave.sampleRate,
                        tempo: tempos[iTempo].v,
                        resolution: resolution
                    )
                    loc = triggers[iNote]
                    insert()
                    soundEndsAt = loc + Int(Double(wave.frameCount) / currentSamplesPerTick)
                    iNote += 1
                    iTempo += 1
                }
            } else if hasTempo {
                if entry.currentSamplePosition < 0 {
                    entry.prevSamplePosition = -1
                    entry.prevTempo = entry.currentTempo
                    entry.currentTempo = tempos[iTempo].v
                    currentSamplesPerTick = samplesPerTick(
                        sampleRate: wave.sampleRate,
                        tempo: tempos[iTempo].v,
                        resolution: resolution
                    )
                    loc = tempos[iTempo].y
                    insert()
                    iTempo += 1
                } else if soundEndsAt < tempos[iTempo].y {
                    entry.prevSamplePosition = wave.frameCount
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = -1
                    loc = soundEndsAt
                    insert()
                } else {
                    let played = entry.currentSamplePosition
                        + Int64(Double(tempos[iTempo].y - loc) * currentSamplesPerTick)
                    entry.prevSamplePosition = min(played, wave.frameCount)
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = entry.prevSamplePosition
                    entry.currentTempo = tempos[iTempo].v
                    currentSamplesPerTick = samplesPerTick(
                        sampleRate: wave.sampleRate,
                        tempo: tempos[iTempo].v,
                        resolution: resolution
                    )
                    loc = tempos[iTempo].y
                    insert()
                    soundEndsAt = loc + Int(Double(wave.frameCount - entry.currentSamplePosition) / currentSamplesPerTick)
                    iTempo += 1
                }
            } else if entry.currentSamplePosition < 0 {
                break
            } else if loc == soundEndsAt {
                if let index = cache.firstIndex(where: { $0.key == loc }) {
                    cache[index].currentSamplePosition = -1
                } else {
                    entry.prevSamplePosition = wave.frameCount
                    entry.prevTempo = entry.currentTempo
                    entry.currentSamplePosition = -1
                    loc = soundEndsAt
                    insert()
                }
                break
            } else {
                entry.prevSamplePosition = wave.frameCount
                entry.prevTempo = entry.currentTempo
                entry.currentSamplePosition = -1
                loc = soundEndsAt
                insert()
                break
            }
        }
        var sentinel = entry
        sentinel.key = Int.max
        sentinel.prevSamplePosition = -1
        sentinel.currentSamplePosition = -1
        sentinel.prevTempo = sentinel.currentTempo
        cache.append(sentinel)
        return cache
    }

    /// `icache = cache.upperBound(tBegin); if not begin, --;` 再走到 `upperBound(tEnd)`。
    static func cacheIsPlaying(_ cache: [PlaybackCacheEntry], tBegin: Int, tEnd: Int) -> Bool {
        guard !cache.isEmpty else { return false }
        func upperBoundCache(_ tick: Int) -> Int {
            var lower = 0
            var upper = cache.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if cache[middle].key <= tick { lower = middle + 1 } else { upper = middle }
            }
            return lower
        }
        var index = upperBoundCache(tBegin)
        if index > 0 {
            index -= 1
        }
        let end = cache.firstIndex { $0.key > tEnd } ?? cache.count
        while index != end {
            if cache[index].currentSamplePosition >= 0 {
                return true
            }
            index += 1
        }
        return false
    }

    static func samplesPerTick(sampleRate: Double, tempo: Double, resolution: Int) -> Double {
        let bpm = tempo > 0 ? tempo : BmsONEInfoDefaults.initialBpm
        let ticks = Double(max(resolution, 1))
        return sampleRate * 60.0 / (bpm * ticks)
    }

    private static func uniqueLocations(_ values: [Int64]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for value in values.sorted() {
            let pulse = Int(value)
            if seen.insert(pulse).inserted {
                result.append(pulse)
            }
        }
        return result
    }

    private static func uniqueTempoEvents(_ events: [(y: Int64, v: Double)]) -> [(y: Int, v: Double)] {
        var seen = Set<Int>()
        var result: [(y: Int, v: Double)] = []
        for event in events.sorted(by: { $0.y < $1.y }) where event.v > 0 {
            let pulse = Int(event.y)
            if seen.insert(pulse).inserted {
                result.append((y: pulse, v: event.v))
            }
        }
        return result
    }

    /// `ChannelFindNext`：从下一个起绕一圈，最后再看当前。
    /// `activeInRegion` 对照 `FiltersActive()`：有表时只接受该下标为真的声道。
    static func findNext(
        keyword: String,
        current: Int,
        names: [String],
        activeInRegion: [Bool]? = nil
    ) -> Int? {
        findChannel(
            keyword: keyword,
            current: current,
            names: names,
            activeInRegion: activeInRegion,
            previous: false
        )
    }

    /// `ChannelFindPrev`：从上一道起反向绕一圈。
    static func findPrevious(
        keyword: String,
        current: Int,
        names: [String],
        activeInRegion: [Bool]? = nil
    ) -> Int? {
        findChannel(
            keyword: keyword,
            current: current,
            names: names,
            activeInRegion: activeInRegion,
            previous: true
        )
    }

    private static func findChannel(
        keyword: String,
        current: Int,
        names: [String],
        activeInRegion: [Bool]?,
        previous: Bool
    ) -> Int? {
        guard names.indices.contains(current) else { return nil }
        if let activeInRegion, activeInRegion.count != names.count { return nil }
        func accepted(_ index: Int) -> Bool {
            guard matches(names[index], keyword: keyword) else { return false }
            guard let activeInRegion else { return true }
            return activeInRegion[index]
        }
        if previous {
            if current > 0 {
                for index in stride(from: current - 1, through: 0, by: -1) where accepted(index) {
                    return index
                }
            }
            for index in stride(from: names.count - 1, through: current, by: -1) where accepted(index) {
                return index
            }
        } else {
            if current + 1 < names.count {
                for index in (current + 1)..<names.count where accepted(index) {
                    return index
                }
            }
            for index in 0...current where accepted(index) {
                return index
            }
        }
        return nil
    }

    static func fileName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    static func selectionAfterDestroy(current: Int, countBefore: Int) -> Int {
        let remaining = countBefore - 1
        if remaining <= 0 { return -1 }
        return min(current, remaining - 1)
    }

    private static func hasNewline(_ name: String) -> Bool {
        name.contains(where: { $0 == "\n" || $0 == "\r" })
    }
}

/// 对照 `SoundChannelResourceManager::TaskDrawOverallWaveformAndRmsCache`。
/// 只给 Channel Info 总图用。列内 RMS 缓存包不在这里。
enum BmsonOverallWaveform {
    static let imageWidth = 320
    static let imageHeight = 160
    /// 侧栏工作高度，不是截图量出来的。原版 label 最小 1、最大 320，会撑开。
    static let sidebarHeight: CGFloat = 64
    static let peakColor: UInt32 = 0x009900
    static let rmsColor: UInt32 = 0x66CC66

    struct Frame: Equatable {
        var left: Float
        var right: Float
    }

    struct Column: Equatable {
        var peakL: UInt8
        var peakR: UInt8
        var rmsL: UInt8
        var rmsR: UInt8
    }

    struct Band: Equatable {
        var center: Int
        var half: Int
    }

    struct Payload: Equatable {
        var stereo: Bool
        var columns: [Column]

        static let empty = Payload(stereo: false, columns: [])
    }

    /// 对照 `EnumerateAllAsFloat` 的 16-bit SignedInt：`/ 32768`。
    static func pcm16Float(_ sample: Int16) -> Float {
        Float(sample) / 32768
    }

    static func frames(samples: [Int16], channels: Int) -> [Frame] {
        let count = max(channels, 1)
        if count == 1 {
            return samples.map { value in
                let sample = pcm16Float(value)
                return Frame(left: sample, right: sample)
            }
        }
        var result: [Frame] = []
        result.reserveCapacity(samples.count / count)
        var index = 0
        while index + 1 < samples.count {
            result.append(
                Frame(
                    left: pcm16Float(samples[index]),
                    right: pcm16Float(samples[index + 1])
                )
            )
            index += count
        }
        return result
    }

    /// `FrameCount / width`，向零取整。帧数不够宽时是 0，每一帧出一列。
    static func samplesPerPixel(frameCount: Int, width: Int = imageWidth) -> Int {
        guard width > 0 else { return 0 }
        return max(frameCount, 0) / width
    }

    /// `width / FrameCount`。
    static func dx(frameCount: Int, width: Int = imageWidth) -> Float {
        guard frameCount > 0 else { return 0 }
        return Float(width) / Float(frameCount)
    }

    /// `static_cast<quint8>(float)`：有限且落在 `0…255` 时向零取整。
    static func cacheByte(_ value: Float) -> UInt8 {
        guard value.isFinite else { return 0 }
        if value <= 0 { return 0 }
        if value >= 255 { return 255 }
        return UInt8(value)
    }

    static func payload(
        samples: [Int16],
        channels: Int,
        width: Int = imageWidth
    ) -> Payload {
        let stereo = channels != 1
        let frames = frames(samples: samples, channels: channels)
        return Payload(
            stereo: stereo,
            columns: columns(frames: frames, stereo: stereo, width: width)
        )
    }

    /// 对照逐帧累加。凑不满一列的尾巴丢掉。
    static func columns(
        frames: [Frame],
        stereo: Bool,
        width: Int = imageWidth
    ) -> [Column] {
        guard !frames.isEmpty, width > 0 else { return [] }
        let perPixel = samplesPerPixel(frameCount: frames.count, width: width)
        let step = dx(frameCount: frames.count, width: width)
        var peakL: Float = -1
        var peakR: Float = -1
        var sumL: Float = 0
        var sumR: Float = 0
        var counted = 0
        var result: [Column] = []
        func emit() {
            if stereo {
                result.append(
                    Column(
                        peakL: cacheByte(peakL * 255),
                        peakR: cacheByte(peakR * 255),
                        rmsL: cacheByte(sqrt(sumL * step) * 255),
                        rmsR: cacheByte(sqrt(sumR * step) * 255)
                    )
                )
            } else {
                let peak = cacheByte(peakL * 255)
                let rms = cacheByte(sqrt(sumL * step) * 255)
                result.append(Column(peakL: peak, peakR: peak, rmsL: rms, rmsR: rms))
            }
            peakL = -1
            peakR = -1
            sumL = 0
            sumR = 0
            counted = 0
        }
        for frame in frames {
            if stereo {
                sumL += frame.left * frame.left
                sumR += frame.right * frame.right
                let left = abs(frame.left)
                let right = abs(frame.right)
                if left > peakL { peakL = left }
                if right > peakR { peakR = right }
            } else {
                sumL += frame.left * frame.left
                let value = abs(frame.left)
                if value > peakL { peakL = value }
            }
            counted += 1
            if counted >= perPixel {
                emit()
            }
        }
        return result
    }

    /// 单声道一条带；立体声上下两条。整数除法对照 `height/2`、`height/4`。
    static func bands(stereo: Bool, height: Int = imageHeight) -> (left: Band, right: Band?) {
        if stereo {
            let half = height / 4
            return (Band(center: half, half: half), Band(center: height * 3 / 4, half: half))
        }
        let half = height / 2
        return (Band(center: half, half: half), nil)
    }

    /// `amplitude * height / divisor / 255`，对照 `L*height/2/255`。
    static func line(center: Int, height: Int, divisor: Int, amplitude: UInt8) -> (y0: Int, y1: Int) {
        let extent = Int(amplitude) * height / divisor / 255
        return (center - extent, center + extent)
    }
}

/// 对照声道列波形：`RmsCacheBlockSize` / `DrawRmsGraph` / `DrawActivityGraph`。
/// SIMPLE 不画 RMS，改画活动条。列内压缩包只用来按 16384 样本切片查找。
enum BmsonLaneWaveform {
    static let blockSize = 64
    static let packetSize = 256
    static let packetSampleCount = blockSize * packetSize
    static let gain: Float = 2
    static let bgmColor: UInt32 = 0x009900
    static let keyColor: UInt32 = 0xCC9933

    struct Entry: Equatable {
        var left: UInt8
        var right: UInt8
    }

    struct Span: Equatable {
        var left: Int
        var right: Int
    }

    struct Activity: Equatable {
        var keyLane: Bool
        var tBegin: Int
        var tEnd: Int
    }

    struct State: Equatable {
        var drawsWaveform: Bool
        var resolution: Int
        var channels: [Channel]
    }

    struct Channel: Equatable {
        var entries: [Entry]
        var cache: [BmsonChannel.PlaybackCacheEntry]
        var notes: [(y: Int64, x: Int64)]
        var frameCount: Int
        var sampleRate: Double

        static func == (lhs: Channel, rhs: Channel) -> Bool {
            lhs.entries == rhs.entries
                && lhs.cache == rhs.cache
                && lhs.notes.elementsEqual(rhs.notes, by: { $0.y == $1.y && $0.x == $1.x })
                && lhs.frameCount == rhs.frameCount
                && lhs.sampleRate == rhs.sampleRate
        }
    }

    /// 每 64 个样本一格：`sqrt(均方) * 127`。尾巴不满 64 丢掉。
    static func entries(frames: [BmsonOverallWaveform.Frame]) -> [Entry] {
        var result: [Entry] = []
        var sumL: Float = 0
        var sumR: Float = 0
        var counted = 0
        for frame in frames {
            sumL += frame.left * frame.left
            sumR += frame.right * frame.right
            counted += 1
            if counted >= blockSize {
                result.append(
                    Entry(
                        left: BmsonOverallWaveform.cacheByte(sqrt(sumL / Float(blockSize)) * 127),
                        right: BmsonOverallWaveform.cacheByte(sqrt(sumR / Float(blockSize)) * 127)
                    )
                )
                sumL = 0
                sumR = 0
                counted = 0
            }
        }
        return result
    }

    static func entries(samples: [Int16], channels: Int) -> [Entry] {
        entries(frames: BmsonOverallWaveform.frames(samples: samples, channels: channels))
    }

    /// 对照 `pos + 0.5` 再转 `int`，向零取整。超出 `Int` 时夹紧，避免 Swift 崩溃。
    static func sampleIndex(_ position: Double) -> Int {
        let rounded = position + 0.5
        if !rounded.isFinite { return 0 }
        if rounded >= Double(Int.max) { return Int.max }
        if rounded <= Double(Int.min) { return Int.min }
        return Int(rounded)
    }

    /// `cache.lowerBound(ticks)`：第一项 `key >= ticks`，用它的 prev 往回插。
    static func samplePosition(
        ticks: Double,
        cache: [BmsonChannel.PlaybackCacheEntry],
        sampleRate: Double,
        resolution: Int
    ) -> Double? {
        var lower = 0
        var upper = cache.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Double(cache[middle].key) < ticks {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < cache.count else { return nil }
        let entry = cache[lower]
        let tempo = entry.prevTempo > 0 ? entry.prevTempo : BmsONEInfoDefaults.initialBpm
        let scale = 60.0 * sampleRate / (tempo * Double(max(resolution, 1)))
        return Double(entry.prevSamplePosition) - (Double(entry.key) - ticks) * scale
    }

    /// 只查 `pos` 所在的那一包。跨包时原版也不看下一包。
    static func mixed(
        entries: [Entry],
        position: Double,
        nextPosition: Double,
        frameCount: Int
    ) -> (left: Float, right: Float)? {
        var iPos = sampleIndex(position)
        var iNextPos = sampleIndex(nextPosition)
        if iPos >= frameCount || iNextPos <= 0 { return nil }
        if iPos < 0 { iPos = 0 }
        if iNextPos > frameCount { iNextPos = frameCount }
        guard iPos < iNextPos, !entries.isEmpty else { return nil }
        let packet: Int
        if position.isFinite, position > 0 {
            let index = position / Double(packetSampleCount)
            packet = index >= Double(Int.max / packetSampleCount)
                ? (Int.max / packetSampleCount) * packetSampleCount
                : Int(index) * packetSampleCount
        } else {
            packet = 0
        }
        let packetEntries = packetSlice(entries, position: packet)
        guard !packetEntries.isEmpty else { return nil }
        let begin = min(max(0, packetEntries.count - 1), max(0, (iPos - packet) / blockSize))
        let end = min(packetEntries.count, max(begin + 1, (iNextPos - packet) / blockSize))
        guard end > begin else { return nil }
        var sumL = 0
        var sumR = 0
        for index in begin..<end {
            let entry = packetEntries[index]
            sumL += Int(entry.left) * Int(entry.left)
            sumR += Int(entry.right) * Int(entry.right)
        }
        let count = Float(end - begin)
        return (
            sqrt(Float(sumL) / count) / 127,
            sqrt(Float(sumR) / count) / 127
        )
    }

    static func rms(
        ticks: Double,
        nextTicks: Double,
        channel: Channel,
        resolution: Int
    ) -> (left: Float, right: Float)? {
        guard channel.frameCount > 0, channel.sampleRate > 0 else { return nil }
        guard let position = samplePosition(
            ticks: ticks,
            cache: channel.cache,
            sampleRate: channel.sampleRate,
            resolution: resolution
        ) else {
            return nil
        }
        guard let nextPosition = samplePosition(
            ticks: nextTicks,
            cache: channel.cache,
            sampleRate: channel.sampleRate,
            resolution: resolution
        ) else {
            return nil
        }
        return mixed(
            entries: channel.entries,
            position: position,
            nextPosition: nextPosition,
            frameCount: channel.frameCount
        )
    }

    /// `gain = 2`。半开区间 `[left, right)`，左右各留 2 像素。
    static func span(width: Int, left: Float, right: Float) -> Span? {
        guard width > 4 else { return nil }
        let half = width / 2
        let lo = max(2, half - Int(Float(half) * left * gain))
        let hi = min(width - 2, half + Int(Float(half) * right * gain) + 1)
        guard lo < hi else { return nil }
        return Span(left: lo, right: hi)
    }

    /// 最后一个 `y <= t` 的音。没有前一个音时用 BGM 绿，对照未初始化时的 `setPen(0,170,0)` 意图。
    static func color(notes: [(y: Int64, x: Int64)], ticks: Double) -> UInt32 {
        guard ticks.isFinite else { return bgmColor }
        let pulse: Int64 = ticks >= Double(Int64.max) ? Int64.max : ticks <= Double(Int64.min) ? Int64.min : Int64(ticks)
        // 保留公共辅助函数对无序输入和同拍最后一项的旧语义。
        var chosen: (y: Int64, x: Int64)?
        for note in notes where note.y <= pulse {
            if chosen == nil || note.y >= chosen!.y { chosen = note }
        }
        guard let lane = chosen?.x else { return bgmColor }
        return lane == 0 ? bgmColor : keyColor
    }

    /// 渲染状态在创建时按拍稳定排序，可在每个像素调用中二分查找。
    static func colorSorted(notes: [(y: Int64, x: Int64)], ticks: Double) -> UInt32 {
        guard ticks.isFinite, !notes.isEmpty else { return bgmColor }
        let pulse: Int64 = ticks >= Double(Int64.max) ? Int64.max : ticks <= Double(Int64.min) ? Int64.min : Int64(ticks)
        var lower = 0
        var upper = notes.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if notes[middle].y <= pulse { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return bgmColor }
        return notes[lower - 1].x == 0 ? bgmColor : keyColor
    }

    /// SIMPLE：`graphWidth/2 - graphWidth/8`，宽 `graphWidth/4`。
    static func activityBand(width: Int) -> Span {
        let x = width / 2 - width / 8
        return Span(left: x, right: x + width / 4)
    }

    /// 对照 `DrawActivityGraph`。只看解码缓存还在响的区间，再按音符改颜色。
    static func activities(
        cache: [BmsonChannel.PlaybackCacheEntry],
        notes: [(y: Int64, x: Int64)],
        tBegin: Int,
        tEnd: Int
    ) -> [Activity] {
        guard tBegin < tEnd, !cache.isEmpty else { return [] }
        func upperBoundCache(_ tick: Int) -> Int {
            var lower = 0
            var upper = cache.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if cache[middle].key <= tick { lower = middle + 1 } else { upper = middle }
            }
            return lower
        }
        func upperBoundNotes(_ tick: Int) -> Int {
            var lower = 0
            var upper = notes.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if notes[middle].y <= Int64(tick) { lower = middle + 1 } else { upper = middle }
            }
            return lower
        }
        var index = upperBoundCache(tBegin)
        if index > 0 {
            index -= 1
        }
        let endIndex = upperBoundCache(tEnd)
        var result: [Activity] = []
        var cursor = index
        while cursor != endIndex {
            while cursor != endIndex, cache[cursor].currentSamplePosition < 0 {
                cursor += 1
            }
            if cursor == endIndex { break }
            var time = cache[cursor].key
            while cursor != endIndex, cache[cursor].currentSamplePosition >= 0 {
                cursor += 1
            }
            let timeEnd = cursor == endIndex ? tEnd : cache[cursor].key
            var noteIndex = upperBoundNotes(time)
            if noteIndex > 0 {
                noteIndex -= 1
            }
            guard noteIndex < notes.count else {
                result.append(Activity(keyLane: false, tBegin: time, tEnd: timeEnd))
                continue
            }
            var keyLane = notes[noteIndex].x > 0
            let noteEnd = upperBoundNotes(timeEnd)
            noteIndex += 1
            while noteIndex < noteEnd {
                let nextKey = notes[noteIndex].x > 0
                if nextKey != keyLane {
                    result.append(
                        Activity(keyLane: keyLane, tBegin: time, tEnd: Int(notes[noteIndex].y))
                    )
                    time = Int(notes[noteIndex].y)
                    keyLane = nextKey
                }
                noteIndex += 1
            }
            result.append(Activity(keyLane: keyLane, tBegin: time, tEnd: timeEnd))
        }
        return result
    }

    private static func packetSlice(_ entries: [Entry], position: Int) -> [Entry] {
        let start = max(0, position / blockSize)
        guard start < entries.count else { return [] }
        let end = min(entries.count, start + packetSize)
        return Array(entries[start..<end])
    }
}
