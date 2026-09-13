import Foundation

/// BMSON 预览：同一套播放器，时间表按脉冲 / `initBPM` / `bpmNotes` 算，不套 BMS 通道。
enum LegacyBmsonPreview {
    struct SoundNote: Equatable {
        var y: Int64
        var continueFlag: Bool
    }

    /// 声道下标 0 → `01`。空名字的声道不进表。
    static func wavTable(channelNames: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for (index, name) in channelNames.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            table[BmsonChartMapping.wavToken(channelIndex: index)] = trimmed
        }
        return table
    }

    /// 编成 `#WAVxx` 行，给现有播放器解析。
    static func encodeWavTable(_ table: [String: String]) -> Data {
        let lines = table.keys.sorted().compactMap { key -> String? in
            guard let name = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            return "#WAV\(key) \(name)"
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// `c == true` 是续播，不重新触发声音，对照 `AddAllIntoMasterCache`。
    static func notes(
        channels: [(name: String, notes: [SoundNote])],
        resolution: Int
    ) -> [PreviewAudioNote] {
        var result: [PreviewAudioNote] = []
        for (index, channel) in channels.enumerated() {
            let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let token = BmsonChartMapping.wavToken(channelIndex: index)
            for note in channel.notes where !note.continueFlag {
                result.append(
                    PreviewAudioNote(
                        beat: BmsonChartMapping.beat(pulse: note.y, resolution: resolution),
                        wavToken: token
                    )
                )
            }
        }
        return result
    }

    static func timing(
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        resolution: Int,
        stopNotes: [(y: Int64, v: Double)] = []
    ) -> PreviewAudioTiming {
        let header = initBpm > 0 && initBpm.isFinite ? initBpm : 120
        let events = bpmNotes.compactMap { event -> (beat: Double, bpm: Double)? in
            guard event.v > 0, event.v.isFinite else { return nil }
            return (BmsonChartMapping.beat(pulse: event.y, resolution: resolution), event.v)
        }
        let stops = stopNotes.compactMap { event -> (beat: Double, durationSeconds: Double)? in
            guard let seconds = stopDurationSeconds(
                pulses: event.v,
                atPulse: event.y,
                initBpm: header,
                bpmNotes: bpmNotes,
                resolution: resolution
            ) else { return nil }
            return (BmsonChartMapping.beat(pulse: event.y, resolution: resolution), seconds)
        }
        return PreviewAudioTiming(headerBPM: header, bpmEvents: events, stopEvents: stops)
    }

    /// `v` 是脉冲停顿。秒数 = `(v / resolution) * 60 / 当时 BPM`。
    /// 同一脉冲上的 `bpmNotes` 先改速度，再算停顿。
    static func stopDurationSeconds(
        pulses: Double,
        atPulse: Int64,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        resolution: Int
    ) -> Double? {
        guard pulses > 0, pulses.isFinite else { return nil }
        let safe = resolution > 0 ? resolution : 240
        let bpm = bpmAt(pulse: atPulse, initBpm: initBpm, bpmNotes: bpmNotes)
        return pulses / Double(safe) * 60 / bpm
    }

    static func context(
        channelNames: [String],
        channels: [(name: String, notes: [SoundNote])],
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)],
        resolution: Int,
        chartDirectory: URL?,
        playHereBeat: Double,
        stopNotes: [(y: Int64, v: Double)] = []
    ) -> PreviewAudioDocumentContext {
        let table = wavTable(channelNames: channelNames)
        return PreviewAudioDocumentContext(
            documentData: encodeWavTable(table),
            chartDirectory: chartDirectory,
            notes: notes(channels: channels, resolution: resolution),
            timing: timing(initBpm: initBpm, bpmNotes: bpmNotes, resolution: resolution, stopNotes: stopNotes),
            playHereBeat: playHereBeat,
            appliesBmsonPlayhead: true
        )
    }

    private static func bpmAt(
        pulse: Int64,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)]
    ) -> Double {
        var bpm = initBpm > 0 && initBpm.isFinite ? initBpm : 120
        for event in bpmNotes.sorted(by: { $0.y < $1.y }) where event.y <= pulse {
            if event.v > 0, event.v.isFinite {
                bpm = event.v
            }
        }
        return bpm
    }

    /// 点音符：两位键走声道表；文件名直接当 `#WAV` 的值。
    static func previewFileName(token: String, table: [String: String]) -> String? {
        if let name = LegacyPreviewAudio.fileName(forToken: token, in: table) {
            return name
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if table.values.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return trimmed
        }
        return nil
    }
}
