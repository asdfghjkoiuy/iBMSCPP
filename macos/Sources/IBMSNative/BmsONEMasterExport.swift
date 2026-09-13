import Foundation
import Darwin

/// 对照 `MasterCache::SampleRate` 和 `MasterOutDialog` 的混音、裁剪、写 WAV。
enum BmsONEClipKind: Int, Sendable {
    case soft = 0
    case hard = 1
    case normalize = 2
}

struct BmsONEMasterSample: Equatable, Sendable {
    var left: Float
    var right: Float
}

struct BmsONEExportWave: Equatable, Sendable {
    var sampleRate: Int
    var channels: Int
    var samples: [Int16]
}

enum BmsONEMasterExportError: Error, Equatable, Sendable {
    case cannotOpenFile
    case destinationExists
    case cancelled
}

enum BmsONEMasterExport {
    static let sampleRate = BmsONEDialogLayout.exportSampleRate
    static let sliderSteps = BmsONEDialogLayout.exportGainSteps

    static func dbGain(slider: Int) -> Double {
        Double(slider - sliderSteps / 2) * 10.0 / Double(sliderSteps / 2)
    }

    static func linearGain(slider: Int) -> Float {
        Float(pow(10.0, dbGain(slider: slider) / 20.0))
    }

    /// `OnSliderGain`：`%1dB (%2%)`，dB 两位小数，百分比是 `10^(dB/20)*100`。
    static func volumeLabel(slider: Int) -> String {
        let db = dbGain(slider: slider)
        let percent = pow(10.0, db / 20.0) * 100.0
        return String(format: "%.2fdB (%.2f%%)", db, percent)
    }

    /// 对照 `Document::GetAbsoluteTime`。
    static func absoluteTime(
        pulse: Int64,
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)],
        stopNotes: [(y: Int64, v: Double)] = []
    ) -> Double {
        let ticksPerBeat = Double(resolution > 0 ? resolution : BmsONEInfoDefaults.resolution)
        var cursor: Int64 = 0
        var seconds = 0.0
        var bpm = initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm
        let changes = bpmNotes.sorted(by: { $0.y < $1.y })
        for event in changes where event.y < pulse {
            seconds += Double(event.y - cursor) * 60.0 / (bpm * ticksPerBeat)
            cursor = event.y
            if event.v > 0 {
                bpm = event.v
            }
        }
        seconds += Double(pulse - cursor) * 60.0 / (bpm * ticksPerBeat)
        for stop in stopNotes where stop.y < pulse && stop.v > 0 && stop.v.isFinite {
            var stopBpm = initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm
            for event in changes where event.y <= stop.y {
                if event.v > 0 {
                    stopBpm = event.v
                }
            }
            seconds += stop.v / ticksPerBeat * 60.0 / stopBpm
        }
        return seconds
    }

    static func sampleIndex(
        pulse: Int64,
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)],
        stopNotes: [(y: Int64, v: Double)] = []
    ) -> Int {
        Int(
            absoluteTime(
                pulse: pulse,
                initBpm: initBpm,
                resolution: resolution,
                bpmNotes: bpmNotes,
                stopNotes: stopNotes
            ) * Double(sampleRate)
        )
    }

    /// 对照 `AddAllIntoMasterCache`：`c == true` 的续播不触发新声音。
    /// 后一个触发音会截断前一个。只读 PCM 16-bit。缺文件的通道跳过。
    static func mix(
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)],
        stopNotes: [(y: Int64, v: Double)] = [],
        channels: [(notes: [(y: Int64, c: Bool)], wave: BmsONEExportWave?)]
    ) -> [BmsONEMasterSample] {
        var mixed: [BmsONEMasterSample] = []
        for channel in channels {
            guard let wave = channel.wave, !wave.samples.isEmpty, wave.channels > 0 else { continue }
            let triggers = channel.notes.filter { !$0.c }.sorted { $0.y < $1.y }
            for (index, note) in triggers.enumerated() {
                let start = max(
                    sampleIndex(
                        pulse: note.y,
                        initBpm: initBpm,
                        resolution: resolution,
                        bpmNotes: bpmNotes,
                        stopNotes: stopNotes
                    ),
                    0
                )
                let waveFrames = resampledFrameCount(wave)
                let frames: Int
                if index + 1 < triggers.count {
                    let next = sampleIndex(
                        pulse: triggers[index + 1].y,
                        initBpm: initBpm,
                        resolution: resolution,
                        bpmNotes: bpmNotes,
                        stopNotes: stopNotes
                    )
                    frames = min(waveFrames, max(0, next - start))
                } else {
                    frames = waveFrames
                }
                if frames == 0 { continue }
                if start + frames > mixed.count {
                    mixed.append(contentsOf: Array(repeating: BmsONEMasterSample(left: 0, right: 0), count: start + frames - mixed.count))
                }
                for frame in 0..<frames {
                    let stereo = sample(wave, frame: frame)
                    mixed[start + frame].left += stereo.left
                    mixed[start + frame].right += stereo.right
                }
            }
        }
        return mixed
    }

    static func write(
        samples: [BmsONEMasterSample],
        slider: Int,
        clip: BmsONEClipKind,
        to url: URL,
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) throws -> String {
        let rendered = render(samples: samples, slider: slider, clip: clip)
        try writeWithoutOverwriting(rendered.data, to: url, shouldCancel: shouldCancel)
        return rendered.log + "\n" + BmsONEDialogLayout.exportComplete
    }

    /// 先在目标目录写临时文件，再以硬链接排他提交。`link` 在目标已存在时失败，
    /// 所以检查和提交之间出现同名文件也不会覆盖它；临时文件只会删除本次成功创建的路径。
    static func writeWithoutOverwriting(
        _ data: Data,
        to url: URL,
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            throw BmsONEMasterExportError.destinationExists
        }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BmsONEMasterExportError.cannotOpenFile }
        var openDescriptor: Int32? = descriptor
        defer {
            if let openDescriptor {
                _ = close(openDescriptor)
            }
            try? FileManager.default.removeItem(at: temporary)
        }
        let wroteAll = data.withUnsafeBytes { raw -> Bool in
            guard raw.count == 0 || raw.baseAddress != nil else { return false }
            var offset = 0
            while offset < raw.count {
                if shouldCancel() { return false }
                let count = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count > 0 {
                    offset += count
                } else if count == -1 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        if !wroteAll {
            if shouldCancel() { throw BmsONEMasterExportError.cancelled }
            throw BmsONEMasterExportError.cannotOpenFile
        }
        guard fsync(descriptor) == 0 else { throw BmsONEMasterExportError.cannotOpenFile }
        let closeResult = close(descriptor)
        openDescriptor = nil
        guard closeResult == 0 else { throw BmsONEMasterExportError.cannotOpenFile }
        if shouldCancel() { throw BmsONEMasterExportError.cancelled }
        let linkResult = link(temporary.path, url.path)
        let linkError = errno
        if linkResult == 0 { return }
        if linkError == EEXIST { throw BmsONEMasterExportError.destinationExists }
        throw BmsONEMasterExportError.cannotOpenFile
    }

    static func render(
        samples: [BmsONEMasterSample],
        slider: Int,
        clip: BmsONEClipKind
    ) -> (data: Data, log: String) {
        let db = dbGain(slider: slider)
        let gain = linearGain(slider: slider)
        var pcm: [Int16] = []
        pcm.reserveCapacity(samples.count * 2)
        var peakL: Float = 0
        var peakR: Float = 0
        var rmsL: Float = 0
        var rmsR: Float = 0
        var peakSatL: Float = 0
        var peakSatR: Float = 0
        var rmsSatL: Float = 0
        var rmsSatR: Float = 0
        var peakOrgL: Float = 0
        var peakOrgR: Float = 0

        if clip == .normalize {
            for sample in samples {
                peakOrgL = max(peakOrgL, abs(sample.left))
                peakOrgR = max(peakOrgR, abs(sample.right))
            }
        }
        let peak = max(peakOrgL, peakOrgR)
        let gainWithNorm: Float
        if clip == .normalize {
            gainWithNorm = peak * gain > 1 ? (peak > 0 ? 1 / peak : 0) : gain
        } else {
            gainWithNorm = gain
        }

        for sample in samples {
            let left: Float
            let right: Float
            let satL: Float
            let satR: Float
            switch clip {
            case .soft:
                left = sample.left * gain
                right = sample.right * gain
                satL = saturate(0.8, left)
                satR = saturate(0.8, right)
            case .hard:
                left = sample.left * gain
                right = sample.right * gain
                satL = min(1, max(-1, left))
                satR = min(1, max(-1, right))
            case .normalize:
                left = sample.left * gainWithNorm
                right = sample.right * gainWithNorm
                satL = min(1, max(-1, left))
                satR = min(1, max(-1, right))
            }
            pcm.append(int16(satL * 32767))
            pcm.append(int16(satR * 32767))
            let sl = left * left
            let sr = right * right
            let ssl = satL * satL
            let ssr = satR * satR
            rmsL += sl
            rmsR += sr
            rmsSatL += ssl
            rmsSatR += ssr
            peakL = max(peakL, sl)
            peakR = max(peakR, sr)
            peakSatL = max(peakSatL, ssl)
            peakSatR = max(peakSatR, ssr)
        }

        let log: String
        if samples.isEmpty {
            log = BmsONEDialogLayout.exportNoSample
        } else {
            let count = Float(samples.count)
            log = clipLog(
                clip: clip,
                samples: samples.count,
                db: db,
                gain: Double(gain),
                gainWithNorm: Double(gainWithNorm),
                peakL: sqrt(peakL),
                peakR: sqrt(peakR),
                rmsL: sqrt(rmsL / count),
                rmsR: sqrt(rmsR / count),
                peakSatL: sqrt(peakSatL),
                peakSatR: sqrt(peakSatR),
                rmsSatL: sqrt(rmsSatL / count),
                rmsSatR: sqrt(rmsSatR / count),
                peakOrgL: peakOrgL,
                peakOrgR: peakOrgR
            )
        }
        return (writeWav(pcm), log)
    }

    static func readPcm16(_ data: Data) -> BmsONEExportWave? {
        guard data.count >= 44,
              ascii(data, 0, 4) == "RIFF",
              ascii(data, 8, 4) == "WAVE"
        else {
            return nil
        }
        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bits = 0
        var pcm = false
        while offset + 8 <= data.count {
            let id = ascii(data, offset, 4)
            let size = Int(readUInt32(data, offset + 4))
            let body = offset + 8
            if id == "fmt ", size >= 16, body + 16 <= data.count {
                pcm = readUInt16(data, body) == 1
                channels = Int(readUInt16(data, body + 2))
                sampleRate = Int(readUInt32(data, body + 4))
                bits = Int(readUInt16(data, body + 14))
            } else if id == "data" {
                guard pcm, bits == 16, channels > 0, sampleRate > 0 else { return nil }
                let byteCount = min(size, data.count - body)
                let frameBytes = byteCount - (byteCount % 2)
                var samples = [Int16](repeating: 0, count: frameBytes / 2)
                data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress?.advanced(by: body) else { return }
                    for index in samples.indices {
                        samples[index] = Int16(littleEndian: base.load(fromByteOffset: index * 2, as: Int16.self))
                    }
                }
                return BmsONEExportWave(sampleRate: sampleRate, channels: channels, samples: samples)
            }
            offset = body + size + (size % 2)
        }
        return nil
    }

    static func loadWave(named name: String, directory: URL?) -> BmsONEExportWave? {
        guard !name.isEmpty else { return nil }
        let url: URL
        if name.hasPrefix("/") {
            url = URL(fileURLWithPath: name)
        } else if let directory {
            url = directory.appendingPathComponent(name)
        } else {
            url = URL(fileURLWithPath: name)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return readPcm16(data)
    }

    private static func int16(_ value: Float) -> Int16 {
        Int16(min(max(value, -32767), 32767))
    }

    private static func resampledFrameCount(_ wave: BmsONEExportWave) -> Int {
        let channels = max(wave.channels, 1)
        let frames = wave.samples.count / channels
        let rate = max(wave.sampleRate, 1)
        return Int(Double(frames) * Double(sampleRate) / Double(rate))
    }

    private static func sample(_ wave: BmsONEExportWave, frame: Int) -> BmsONEMasterSample {
        let channels = max(wave.channels, 1)
        let sourceFrames = max(wave.samples.count / channels, 1)
        let sourceRate = max(wave.sampleRate, 1)
        let sourcePosition = Double(frame) * Double(sourceRate) / Double(sampleRate)
        let index = min(max(Int(sourcePosition), 0), sourceFrames - 1)
        if channels == 1 {
            let value = Float(wave.samples[index]) / 32767
            return BmsONEMasterSample(left: value, right: value)
        }
        let left = Float(wave.samples[index * channels]) / 32767
        let right = Float(wave.samples[index * channels + 1]) / 32767
        return BmsONEMasterSample(left: left, right: right)
    }

    private static func sigmoid(_ x: Float) -> Float {
        if abs(x) < 1 {
            return x * (1.5 - 0.5 * x * x)
        }
        return x > 0 ? 1 : -1
    }

    private static func saturate(_ threshold: Float, _ x: Float) -> Float {
        if abs(x) < threshold {
            return x
        }
        let scale = (1 - threshold) * 1.5
        if x > 0 {
            return threshold + (1 - threshold) * sigmoid((x - threshold) / scale)
        }
        return -(threshold + (1 - threshold) * sigmoid((-x - threshold) / scale))
    }

    private static func clipLog(
        clip: BmsONEClipKind,
        samples: Int,
        db: Double,
        gain: Double,
        gainWithNorm: Double,
        peakL: Float,
        peakR: Float,
        rmsL: Float,
        rmsR: Float,
        peakSatL: Float,
        peakSatR: Float,
        rmsSatL: Float,
        rmsSatR: Float,
        peakOrgL: Float,
        peakOrgR: Float
    ) -> String {
        let afterName: String
        switch clip {
        case .soft: afterName = "After soft clipping"
        case .hard: afterName = "After hard clipping"
        case .normalize: afterName = "After normalization"
        }
        if clip == .normalize {
            return [
                "Wrote \(samples) samples.",
                "--------",
                "Original",
                dbPair("  Peak: ", Double(peakOrgL), Double(peakOrgR)),
                dbPair("  RMS: ", Double(rmsL) / gainWithNorm, Double(rmsR) / gain),
                "--------",
                String(format: "After volume gain %.2fdB", db),
                dbPair("  Peak: ", Double(peakOrgL) * gain, Double(peakOrgR) * gain),
                dbPair("  RMS: ", Double(rmsL) / gainWithNorm * gain, Double(rmsR) / gainWithNorm * gain),
                "--------",
                afterName,
                dbPair("  Peak: ", Double(peakSatL), Double(peakSatR)),
                dbPair("  RMS: ", Double(rmsSatL), Double(rmsSatR)),
                "--------"
            ].joined(separator: "\n")
        }
        return [
            "Wrote \(samples) samples.",
            "--------",
            "Original",
            dbPair("  Peak: ", Double(peakL) / gain, Double(peakR) / gain),
            dbPair("  RMS: ", Double(rmsL) / gain, Double(rmsR) / gain),
            "--------",
            String(format: "After volume gain %.2fdB", db),
            dbPair("  Peak: ", Double(peakL), Double(peakR)),
            dbPair("  RMS: ", Double(rmsL), Double(rmsR)),
            "--------",
            afterName,
            dbPair("  Peak: ", Double(peakSatL), Double(peakSatR)),
            dbPair("  RMS: ", Double(rmsSatL), Double(rmsSatR)),
            "--------"
        ].joined(separator: "\n")
    }

    private static func dbPair(_ prefix: String, _ left: Double, _ right: Double) -> String {
        String(format: "%@%.2fdB, %.2fdB", prefix, 20 * log10(max(left, 1e-12)), 20 * log10(max(right, 1e-12)))
    }

    private static func writeWav(_ samples: [Int16]) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(&data, UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(&data, 16)
        appendUInt16(&data, 1)
        appendUInt16(&data, 2)
        appendUInt32(&data, UInt32(sampleRate))
        appendUInt32(&data, UInt32(sampleRate * 4))
        appendUInt16(&data, 4)
        appendUInt16(&data, 16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(&data, UInt32(dataSize))
        for sample in samples {
            var value = sample.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func ascii(_ data: Data, _ start: Int, _ count: Int) -> String {
        String(bytes: data[start..<(start + count)], encoding: .ascii) ?? ""
    }

    private static func readUInt16(_ data: Data, _ start: Int) -> UInt16 {
        UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ start: Int) -> UInt32 {
        UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}

/// 对照 `MiniMapView::RmsCachePacket`：rms 存的是均方，画一行时再开方。
struct BmsONEMasterPacket: Equatable {
    var meanSquareL: Float
    var meanSquareR: Float
    var peakL: Float
    var peakR: Float
    var available: Bool

    static let empty = BmsONEMasterPacket(
        meanSquareL: 0,
        meanSquareR: 0,
        peakL: 0,
        peakR: 0,
        available: true
    )
}

struct BmsONEMasterRow: Equatable {
    var rmsL: Float
    var rmsR: Float
    var peakL: Float
    var peakR: Float
    var available: Bool

    static let empty = BmsONEMasterRow(rmsL: 0, rmsR: 0, peakL: 0, peakR: 0, available: true)
}

enum BmsONEMasterWaveform {
    /// `smp_prev .. smp` 一段。`smp_prev == smp` 时均方保持 0。
    static func packet(samples: [BmsONEMasterSample], start: Int, end: Int) -> BmsONEMasterPacket {
        var packet = BmsONEMasterPacket.empty
        let lo = max(0, start)
        let hi = min(samples.count, max(lo, end))
        guard hi > lo else { return packet }
        var sumL: Float = 0
        var sumR: Float = 0
        for index in lo..<hi {
            let sample = samples[index]
            sumL += sample.left * sample.left
            sumR += sample.right * sample.right
            packet.peakL = max(packet.peakL, abs(sample.left))
            packet.peakR = max(packet.peakR, abs(sample.right))
        }
        let count = Float(hi - lo)
        packet.meanSquareL = sumL / count
        packet.meanSquareR = sumR / count
        return packet
    }

    /// 画一行：把各 tick 的均方相加再 `sqrt(sum / n)`，peak 取 max。可用性看第一格。
    static func combine(_ packets: ArraySlice<BmsONEMasterPacket>) -> BmsONEMasterRow {
        guard let first = packets.first else { return .empty }
        var sumL: Float = 0
        var sumR: Float = 0
        var peakL: Float = 0
        var peakR: Float = 0
        for packet in packets {
            sumL += packet.meanSquareL
            sumR += packet.meanSquareR
            peakL = max(peakL, packet.peakL)
            peakR = max(peakR, packet.peakR)
        }
        let count = Float(packets.count)
        return BmsONEMasterRow(
            rmsL: sqrt(sumL / count),
            rmsR: sqrt(sumR / count),
            peakL: peakL,
            peakR: peakR,
            available: first.available
        )
    }
}

/// 主控 / 迷你地图共用的混音缓存。缺文件时 samples 为空，仍按 `viewLength` 画暗道。
final class BmsONEMasterWaveformCache {
    let samples: [BmsONEMasterSample]
    let viewLength: Int
    let actualLength: Int
    let resolution: Int
    let initBpm: Double
    let bpmNotes: [(y: Int64, v: Double)]
    let stopNotes: [(y: Int64, v: Double)]
    private var packets: [Int: BmsONEMasterPacket] = [:]
    private var sampleAtPulse: [Int: Int] = [:]

    init(
        samples: [BmsONEMasterSample],
        actualLength: Int,
        resolution: Int,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        stopNotes: [(y: Int64, v: Double)]
    ) {
        self.samples = samples
        self.actualLength = max(0, actualLength)
        self.resolution = max(resolution, 1)
        self.initBpm = initBpm
        self.bpmNotes = bpmNotes
        self.stopNotes = stopNotes
        self.viewLength = BmsONEMasterView.viewLength(actualLength: self.actualLength, resolution: self.resolution)
    }

    static func make(
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)],
        stopNotes: [(y: Int64, v: Double)],
        lengthNotes: [(y: Int64, l: Int64)],
        channels: [(notes: [(y: Int64, c: Bool)], wave: BmsONEExportWave?)]
    ) -> BmsONEMasterWaveformCache {
        BmsONEMasterWaveformCache(
            samples: BmsONEMasterExport.mix(
                initBpm: initBpm,
                resolution: resolution,
                bpmNotes: bpmNotes,
                stopNotes: stopNotes,
                channels: channels
            ),
            actualLength: BmsONEMasterView.actualLength(notes: lengthNotes),
            resolution: resolution,
            initBpm: initBpm,
            bpmNotes: bpmNotes,
            stopNotes: stopNotes
        )
    }

    func sampleIndex(pulse: Int) -> Int {
        if let cached = sampleAtPulse[pulse] { return cached }
        let index = BmsONEMasterExport.sampleIndex(
            pulse: Int64(pulse),
            initBpm: initBpm,
            resolution: resolution,
            bpmNotes: bpmNotes,
            stopNotes: stopNotes
        )
        sampleAtPulse[pulse] = index
        return index
    }

    /// `rmsCacheOfTicks[t]`，对应 Reconstruct 循环里的时间 `t+1`。
    func packet(at t: Int) -> BmsONEMasterPacket {
        guard t >= 0, t < max(0, viewLength - 1) else { return .empty }
        if samples.isEmpty { return .empty }
        if let cached = packets[t] { return cached }
        let built = BmsONEMasterWaveform.packet(
            samples: samples,
            start: sampleIndex(pulse: t),
            end: sampleIndex(pulse: t + 1)
        )
        packets[t] = built
        return built
    }

    func row(from t: Int, to t2: Int) -> BmsONEMasterRow {
        var start = t
        var end = t2
        let limit = max(0, viewLength - 1)
        if end > limit { end = limit }
        if start < 0 { start = 0 }
        guard end > start else { return .empty }
        if samples.isEmpty { return .empty }
        var collected: [BmsONEMasterPacket] = []
        collected.reserveCapacity(end - start)
        for index in start..<end {
            collected.append(packet(at: index))
        }
        return BmsONEMasterWaveform.combine(collected[...])
    }
}
