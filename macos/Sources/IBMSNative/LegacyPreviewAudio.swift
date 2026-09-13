import AVFoundation
import Foundation

/// 一条要发声的音符：拍点 + `#WAVxx` 两位键。
struct PreviewAudioNote: Equatable {
    var beat: Double
    var wavToken: String
}

/// 预听用的速度信息。STOP 的停顿秒数必须来自核心时间表，不在这里用单位自己换算。
struct PreviewAudioTiming: Equatable {
    var headerBPM: Double
    var bpmEvents: [(beat: Double, bpm: Double)]
    var stopEvents: [(beat: Double, durationSeconds: Double)]

    init(
        headerBPM: Double,
        bpmEvents: [(beat: Double, bpm: Double)],
        stopEvents: [(beat: Double, durationSeconds: Double)] = []
    ) {
        self.headerBPM = headerBPM
        self.bpmEvents = bpmEvents
        self.stopEvents = stopEvents
    }

    static func == (lhs: PreviewAudioTiming, rhs: PreviewAudioTiming) -> Bool {
        lhs.headerBPM == rhs.headerBPM
            && lhs.bpmEvents.count == rhs.bpmEvents.count
            && zip(lhs.bpmEvents, rhs.bpmEvents).allSatisfy { $0.beat == $1.beat && $0.bpm == $1.bpm }
            && lhs.stopEvents.count == rhs.stopEvents.count
            && zip(lhs.stopEvents, rhs.stopEvents).allSatisfy {
                $0.beat == $1.beat && $0.durationSeconds == $1.durationSeconds
            }
    }
}

/// 排好的一发：从 `fromBeat` 算起的秒数，以及要播的 WAV 键。
struct PreviewAudioHit: Equatable {
    var seconds: Double
    var wavToken: String
}

/// 预览窗向主窗要的当前谱面。Play Here 的拍由调用方给。
struct PreviewAudioDocumentContext {
    var documentData: Data
    var chartDirectory: URL?
    var notes: [PreviewAudioNote]
    var timing: PreviewAudioTiming
    /// 谱面区没有独立播放头。拿不到当前拍时用 0。
    var playHereBeat: Double
    /// 打开 BMSON 时，播放头按 BmsONE 的缓冲延迟走，BMS 不套。
    var appliesBmsonPlayhead = false
}

/// 原版 `#WAV` 解析和按拍排时间表。不读 BMSON，不启动外置播放器。
enum LegacyPreviewAudio {
    /// 从 BMS 文本读 `#WAVxx` 定义。键是两位 01–ZZ，大小写不敏感，后写覆盖先写。
    /// 不展开 RANDOM / IF；这些行本身不会当成 WAV。
    static func parseWavTable(from text: String) -> [String: String] {
        var table: [String: String] = [:]
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 6 else { return }
            let prefixEnd = trimmed.index(trimmed.startIndex, offsetBy: 4)
            guard trimmed[trimmed.startIndex..<prefixEnd].uppercased() == "#WAV" else { return }
            let keyEnd = trimmed.index(prefixEnd, offsetBy: 2)
            let key = String(trimmed[prefixEnd..<keyEnd])
            guard isWavKey(key) else { return }
            let fileName = String(trimmed[keyEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty else { return }
            table[key.uppercased()] = fileName
        }
        return table
    }

    static func parseWavTable(from data: Data) -> [String: String] {
        parseWavTable(from: decodeBMSText(data))
    }

    /// 两位键对应的文件名。没有定义时是 `nil`。
    static func fileName(forToken token: String, in table: [String: String]) -> String? {
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isWavKey(key) else { return nil }
        let name = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// 原版只存文件名时，拼到谱面所在目录。已经是绝对路径就原样用。
    static func resolveWavURL(fileName: String, chartDirectory: URL?) -> URL? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        if let chartDirectory {
            return chartDirectory.appendingPathComponent(trimmed)
        }
        return URL(fileURLWithPath: trimmed)
    }

    /// iBMSC `CheckFilename`：要的 `.ogg` / `.wav` 不在时，改用同名的另一种。
    /// 两种都没有时仍返回原来的路径，由播放器再判断文件在不在。
    static func resolveAudioURL(fileName: String, chartDirectory: URL?) -> URL? {
        guard let url = resolveWavURL(fileName: fileName, chartDirectory: chartDirectory) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let ext = url.pathExtension.lowercased()
        let swap: String?
        if ext == "ogg" {
            swap = "wav"
        } else if ext == "wav" {
            swap = "ogg"
        } else {
            swap = nil
        }
        if let swap {
            let other = url.deletingPathExtension().appendingPathExtension(swap)
            if FileManager.default.fileExists(atPath: other.path) {
                return other
            }
        }
        return url
    }

    /// 已播出的秒数对应哪一拍。和 `scheduleHits` 同一套积分：先走 BPM，再把区间里的 STOP 加进去。
    /// 停在某一拍上时，播放头停在那一拍，等停顿过完再往前。
    static func beat(afterSeconds: Double, fromBeat: Double, timing: PreviewAudioTiming) -> Double {
        guard afterSeconds.isFinite, fromBeat.isFinite else { return fromBeat }
        if afterSeconds <= 0 {
            return fromBeat
        }
        let header = usableBPM(timing.headerBPM)
        let changes = timing.bpmEvents
            .filter { $0.bpm > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        let stops = timing.stopEvents
            .filter { $0.durationSeconds > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        var bpm = header
        for event in changes where event.beat <= fromBeat {
            bpm = usableBPM(event.bpm)
        }
        var remaining = afterSeconds
        var cursor = fromBeat
        var changeIndex = changes.firstIndex { $0.beat > fromBeat } ?? changes.count
        var stopIndex = stops.firstIndex { $0.beat >= fromBeat } ?? stops.count
        while remaining > 0 {
            let nextChange = changeIndex < changes.count ? changes[changeIndex].beat : Double.infinity
            let nextStop = stopIndex < stops.count ? stops[stopIndex].beat : Double.infinity
            if nextStop <= nextChange, nextStop.isFinite {
                if nextStop > cursor {
                    let segment = (nextStop - cursor) * 60 / bpm
                    if remaining <= segment {
                        return cursor + remaining * bpm / 60
                    }
                    remaining -= segment
                    cursor = nextStop
                }
                while stopIndex < stops.count && stops[stopIndex].beat == cursor {
                    let pause = stops[stopIndex].durationSeconds
                    if remaining <= pause {
                        return cursor
                    }
                    remaining -= pause
                    stopIndex += 1
                }
            } else if nextChange.isFinite {
                let segment = (nextChange - cursor) * 60 / bpm
                if remaining <= segment {
                    return cursor + remaining * bpm / 60
                }
                remaining -= segment
                cursor = nextChange
                bpm = usableBPM(changes[changeIndex].bpm)
                changeIndex += 1
            } else {
                return cursor + remaining * bpm / 60
            }
        }
        return cursor
    }

    /// 按拍点排成（秒, WAV 键）。BPM 段用 60/BPM 积分；STOP 把核心给出的停顿秒数加进去。
    /// 同拍的 STOP 加在该拍音符之后：`fromBeat <= stopBeat < noteBeat`。
    /// 恒速、无 STOP 时：秒数 = (拍 - 起点拍) × 60 / BPM。例如 120 BPM 下 4 拍是 2 秒。
    static func scheduleHits(
        notes: [PreviewAudioNote],
        timing: PreviewAudioTiming,
        fromBeat: Double
    ) -> [PreviewAudioHit] {
        let header = usableBPM(timing.headerBPM)
        let changes = timing.bpmEvents
            .filter { $0.bpm > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        let stops = timing.stopEvents
            .filter { $0.durationSeconds > 0 && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        return notes
            .compactMap { note -> PreviewAudioHit? in
                guard note.beat.isFinite, note.beat >= fromBeat else { return nil }
                let token = note.wavToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isWavKey(token) else { return nil }
                let seconds = seconds(
                    fromBeat: fromBeat,
                    toBeat: note.beat,
                    headerBPM: header,
                    bpmEvents: changes,
                    stopEvents: stops
                )
                return PreviewAudioHit(seconds: seconds, wavToken: token.uppercased())
            }
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return lhs.wavToken < rhs.wavToken
            }
    }

    /// BPM / STOP / 小节比 / 背景图通道不发声。
    static func isAudibleChannel(_ channel: String) -> Bool {
        switch channel.uppercased() {
        case "02", "03", "04", "06", "07", "08", "09", "SC":
            return false
        default:
            return !channel.isEmpty
        }
    }

    static func decodeBMSText(_ data: Data) -> String {
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        if let text = String(data: payload, encoding: .shiftJIS) {
            return text
        }
        return String(decoding: payload, as: UTF8.self)
    }

    static func isWavKey(_ key: String) -> Bool {
        guard key.count == 2 else { return false }
        let chars = Array(key.uppercased())
        guard let high = base36Value(chars[0]), let low = base36Value(chars[1]) else { return false }
        let index = high * 36 + low
        return index >= 1 && index <= 1295
    }

    private static func base36Value(_ character: Character) -> Int? {
        switch character {
        case "0"..."9":
            return Int(character.asciiValue! - UInt8(ascii: "0"))
        case "A"..."Z":
            return Int(character.asciiValue! - UInt8(ascii: "A")) + 10
        default:
            return nil
        }
    }

    private static func usableBPM(_ bpm: Double) -> Double {
        bpm > 0 && bpm.isFinite ? bpm : 120
    }

    private static func seconds(
        fromBeat: Double,
        toBeat: Double,
        headerBPM: Double,
        bpmEvents: [(beat: Double, bpm: Double)],
        stopEvents: [(beat: Double, durationSeconds: Double)]
    ) -> Double {
        var bpm = headerBPM
        for event in bpmEvents where event.beat <= fromBeat {
            bpm = usableBPM(event.bpm)
        }
        var time = 0.0
        var cursor = fromBeat
        for event in bpmEvents where event.beat > fromBeat && event.beat < toBeat {
            time += (event.beat - cursor) * 60 / bpm
            cursor = event.beat
            bpm = usableBPM(event.bpm)
        }
        time += (toBeat - cursor) * 60 / bpm
        for stop in stopEvents where fromBeat <= stop.beat && stop.beat < toBeat {
            time += stop.durationSeconds
        }
        return time
    }
}

/// 用系统 `AVAudioPlayer` 播本地 WAV / MP3。OGG 和系统播不了的 MP3 先解成 PCM16 WAV 再播，不启动外置播放器。
final class LegacyPreviewAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var players: [AVAudioPlayer] = []
    private var pending: [DispatchWorkItem] = []
    private var elapsedTimer: Timer?
    private var playbackStartedAt: Date?
    /// 把 OGG 等系统播不了的文件解成 WAV 字节。预览测试目标没有 C++ 桥，可以不设。
    var decodeToWav: ((URL) -> Data?)?
    /// 已经播出的秒数。给 BMSON 播放头用，不是起播延迟。
    var onElapsedSeconds: ((Double) -> Void)?
    var onPlaybackStopped: (() -> Void)?

    func playFile(url: URL, maxDurationSeconds: Double = 0, fadeOutSeconds: Double = 0) {
        halt(notify: true)
        startPlayer(url: url)
        scheduleDurationLimit(maxDurationSeconds: maxDurationSeconds, fadeOutSeconds: fadeOutSeconds)
    }

    func stop() {
        halt(notify: true)
    }

    func playChart(
        documentData: Data,
        chartDirectory: URL?,
        notes: [PreviewAudioNote],
        timing: PreviewAudioTiming,
        fromBeat: Double
    ) {
        halt(notify: false)
        startElapsedClock()
        let table = LegacyPreviewAudio.parseWavTable(from: documentData)
        let hits = LegacyPreviewAudio.scheduleHits(notes: notes, timing: timing, fromBeat: fromBeat)
        for hit in hits {
            guard let fileName = table[hit.wavToken],
                  let url = LegacyPreviewAudio.resolveAudioURL(fileName: fileName, chartDirectory: chartDirectory)
            else { continue }
            if hit.seconds <= 0 {
                startPlayer(url: url)
                continue
            }
            let item = DispatchWorkItem { [weak self] in
                self?.startPlayer(url: url)
            }
            pending.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + hit.seconds, execute: item)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        players.removeAll { $0 === player }
    }

    private func halt(notify: Bool) {
        pending.forEach { $0.cancel() }
        pending.removeAll()
        players.forEach { $0.stop() }
        players.removeAll()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        playbackStartedAt = nil
        if notify {
            onPlaybackStopped?()
        }
    }

    private func startElapsedClock() {
        playbackStartedAt = Date()
        elapsedTimer?.invalidate()
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(tickElapsed),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
        onElapsedSeconds?(0)
    }

    @objc private func tickElapsed() {
        guard let start = playbackStartedAt else { return }
        onElapsedSeconds?(Date().timeIntervalSince(start))
    }

    private func scheduleDurationLimit(maxDurationSeconds: Double, fadeOutSeconds: Double) {
        guard maxDurationSeconds > 0, maxDurationSeconds.isFinite else { return }
        let startFade = DispatchWorkItem { [weak self] in
            self?.beginVolumeFade(seconds: fadeOutSeconds)
        }
        pending.append(startFade)
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDurationSeconds, execute: startFade)
    }

    private func beginVolumeFade(seconds: Double) {
        guard seconds > 0, seconds.isFinite else {
            halt(notify: true)
            return
        }
        let steps = 20
        let dt = seconds / Double(steps)
        for step in 0...steps {
            let item = DispatchWorkItem { [weak self] in
                let gain = max(0, 1.0 - Double(step) / Double(steps))
                self?.players.forEach { $0.volume = Float(gain) }
                if step == steps {
                    self?.halt(notify: true)
                }
            }
            pending.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + dt * Double(step), execute: item)
        }
    }

    private func startPlayer(url: URL) {
        let resolved = LegacyPreviewAudio.resolveAudioURL(
            fileName: url.lastPathComponent,
            chartDirectory: url.deletingLastPathComponent()
        ) ?? url
        guard FileManager.default.fileExists(atPath: resolved.path) else { return }
        if playSystemFile(resolved) {
            return
        }
        if let data = decodeToWav?(resolved) {
            playWavData(data)
        }
    }

    @discardableResult
    private func playSystemFile(_ url: URL) -> Bool {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { return false }
            players.append(player)
            return true
        } catch {
            return false
        }
    }

    private func playWavData(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { return }
            players.append(player)
        } catch {
            return
        }
    }
}
