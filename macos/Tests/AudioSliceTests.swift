import Foundation

@main
struct AudioSliceTests {
    static func main() {
        testModeTitles()
        testWoslicerPrependsZero()
        testWoslicerOffset()
        testWoslicerToggleMark()
        testNames()
        testWoslicerWritesTwoSlices()
        testWoslicerSplitsOgg()
        testWoslicerSplitsMp3()
        testBmhelperModeStillUsesDivisionTimes()
        testWoslicerPreviewCurrentAndPrevious()
        testWoslicerPreviewExtractsOneSecond()
        testWoslicerWaveformTwoSecondColumns()
        testWoslicerWaveformDropsLeftover()
        testWoslicerWaveformShortFileOneColumnPerFrame()
        testWoslicerWaveformStereoMinMax()
        testWoslicerWaveformMarkX()
        testWoslicerWaveformSplitMarkXs()
        testWoslicerWaveformLoadsOgg()
        testWoslicerWaveformEmptySamples()
        testAudioSlicerWorkingGeometry()
        testWoslicerTrimTrailingZeros()
        testWoslicerTrimKeepsLeadingZeros()
        testWoslicerTrimStereoSilentFrame()
        testWoslicerTrimStereoRightOnlyZero()
        testWoslicerTrimAllZeros()
        testWoslicerTrimNoZeros()
        testWoslicerSplitTrimsTrailingSilenceToOneSlice()
        testWoslicerSplitKeepsTwoSlicesAfterTrailingZeros()
        testWoslicerWaveformLoadUsesTrimmedDuration()
        testWoslicerTrimLayoutFlag()
        print("AudioSliceTests passed")
    }

    private static func testModeTitles() {
        require(AudioSliceMode.bmhelper.displayName == "bmhelper", "bmhelper mode")
        require(AudioSliceMode.woslicer.displayName == "woslicer", "woslicer mode")
        require(AudioSlicerLayout.title == "Audio Slicer", "window title")
        require(AudioSlicerLayout.originalClientSize == nil, "not measured")
        require(AudioSlicerLayout.menuTitle == "Audio Slicer…", "menu")
        require(AudioSlicerLayout.exportBMSETitle == "Export BMSE", "export")
        require(AudioSlicerLayout.importBMSETitle == "Import BMSE", "import")
        require(AudioSlicerLayout.ffDefinitionTitle == "FF definition", "FF")
    }

    private static func testWoslicerPrependsZero() {
        let times = WoslicerSplit.splitPoints(marks: [1.0], duration: 2)
        require(times.count == 2, "0 and 1")
        require(abs(times[0] - 0) < 1e-9 && abs(times[1] - 1) < 1e-9, "prepend 0")
        require(
            AudioSlice.splitPoints(.woslicer(marks: [1.0], offsetSeconds: 0, duration: 2)) == times,
            "engine uses woslicer points"
        )
    }

    private static func testWoslicerOffset() {
        let times = WoslicerSplit.splitPoints(marks: [0], offset: 0.5, duration: 2)
        require(times.count == 2, "file start stays")
        require(abs(times[0] - 0) < 1e-9 && abs(times[1] - 0.5) < 1e-9, "shift 0.5s")
    }

    private static func testWoslicerToggleMark() {
        let added = WoslicerSplit.toggleMark(1.0, in: [])
        require(added == [1.0], "add")
        let removed = WoslicerSplit.toggleMark(1.0, in: added)
        require(removed.isEmpty, "III Z deletes")
    }

    private static func testNames() {
        require(WoslicerSplit.outputFileName(base: "kick", indexFromZero: 0) == "kick_001.wav", "xxx")
        require(
            AudioSlice.outputFileName(mode: .woslicer, prefix: "kick", indexFromZero: 1) == "kick_002.wav",
            "second"
        )
        require(
            WoslicerSplit.defaultBaseName(input: URL(fileURLWithPath: "/tmp/snare.wav")) == "snare",
            "stem"
        )
    }

    /// 同一条 2 秒夹具：裁断线 `1.0` → `kick_001.wav` / `kick_002.wav` 各 1 秒。
    private static func testWoslicerWritesTwoSlices() {
        let sampleRate = 44100
        var samples = [Int16](repeating: 1000, count: sampleRate)
        samples += [Int16](repeating: -2000, count: sampleRate)
        let wav = BmhelperPcmWav(sampleRate: sampleRate, channels: 1, samples: samples)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-audio-slice-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("kick.wav")
        try! BmhelperWavIO.write(wav).write(to: input)

        let urls = try! AudioSlice.splitFile(
            mode: .woslicer,
            input: input,
            outputDirectory: root,
            prefix: WoslicerSplit.defaultBaseName(input: input),
            request: .woslicer(marks: [1.0], offsetSeconds: 0, duration: nil)
        )
        require(urls.map(\.lastPathComponent) == ["kick_001.wav", "kick_002.wav"], "woslicer names")
        let first = try! BmhelperWavIO.read(Data(contentsOf: urls[0]))
        let second = try! BmhelperWavIO.read(Data(contentsOf: urls[1]))
        require(first.samples.count == 44100 && first.samples.allSatisfy { $0 == 1000 }, "first")
        require(second.samples.count == 44100 && second.samples.allSatisfy { $0 == -2000 }, "second")
    }

    /// woslicer 帮助写了能读 ogg。切点仍按裁断线，输出仍是 PCM16 WAV。
    private static func testWoslicerSplitsOgg() {
        let input = audioFixtureURL("sine-440.ogg")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-audio-slice-ogg-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        AudioSlice.decodeToWav = { url in
            try? IBMSAudioBridge.pcmWav(fromFile: url.path)
        }
        defer { AudioSlice.decodeToWav = nil }
        let fullData = try! IBMSAudioBridge.pcmWav(fromFile: input.path)
        let full = WoslicerTrim.trim(try! BmhelperWavIO.read(fullData))
        let frames = full.samples.count / max(full.channels, 1)
        require(frames > 8, "ogg has frames")
        let mark = coveringMark(frames: frames, sampleRate: full.sampleRate)
        let urls = try! AudioSlice.splitFile(
            mode: .woslicer,
            input: input,
            outputDirectory: root,
            prefix: WoslicerSplit.defaultBaseName(input: input),
            request: .woslicer(marks: [mark], offsetSeconds: 0, duration: nil)
        )
        require(urls.map(\.lastPathComponent) == ["sine-440_001.wav", "sine-440_002.wav"], "ogg names")
        let first = try! BmhelperWavIO.read(Data(contentsOf: urls[0]))
        let second = try! BmhelperWavIO.read(Data(contentsOf: urls[1]))
        require(first.channels == full.channels && first.sampleRate == full.sampleRate, "same format")
        require(first.samples.count + second.samples.count == frames * max(full.channels, 1), "covers all")
        require(!first.samples.isEmpty && !second.samples.isEmpty, "both halves")
    }

    /// iBMSC 文件对话框认 `*.mp3`。切点仍按裁断线，输出仍是 PCM16 WAV。
    private static func testWoslicerSplitsMp3() {
        let input = audioFixtureURL("sine-440.mp3")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-audio-slice-mp3-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        AudioSlice.decodeToWav = { url in
            try? IBMSAudioBridge.pcmWav(fromFile: url.path)
        }
        defer { AudioSlice.decodeToWav = nil }
        let fullData = try! IBMSAudioBridge.pcmWav(fromFile: input.path)
        let full = WoslicerTrim.trim(try! BmhelperWavIO.read(fullData))
        let frames = full.samples.count / max(full.channels, 1)
        require(frames > 8, "mp3 has frames")
        let mark = coveringMark(frames: frames, sampleRate: full.sampleRate)
        let urls = try! AudioSlice.splitFile(
            mode: .woslicer,
            input: input,
            outputDirectory: root,
            prefix: WoslicerSplit.defaultBaseName(input: input),
            request: .woslicer(marks: [mark], offsetSeconds: 0, duration: nil)
        )
        require(urls.map(\.lastPathComponent) == ["sine-440_001.wav", "sine-440_002.wav"], "mp3 names")
        let first = try! BmhelperWavIO.read(Data(contentsOf: urls[0]))
        let second = try! BmhelperWavIO.read(Data(contentsOf: urls[1]))
        require(first.channels == full.channels && first.sampleRate == full.sampleRate, "same format")
        require(first.samples.count + second.samples.count == frames * max(full.channels, 1), "covers all")
        require(!first.samples.isEmpty && !second.samples.isEmpty, "both halves")
    }

    private static func testBmhelperModeStillUsesDivisionTimes() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 960, gate: 480, noteNum: 62, velocity: 100)
        ]
        let times = AudioSlice.splitPoints(
            .bmhelper(notes: notes, quantize: 480, bpm: 120, offsetMs: 0)
        )
        require(times.count == 2, "two division times")
        require(abs(times[0] - 0) < 1e-9 && abs(times[1] - 1) < 1e-9, "0 and 1s")
    }

    /// 120 BPM 夹具：裁断线 `1.0`、时长 2 秒。`[P]` 播 1…2，`[O]` 播 0…1。
    private static func testWoslicerPreviewCurrentAndPrevious() {
        let current = WoslicerPreview.currentSegment(current: 1.0, marks: [1.0], duration: 2)
        require(current != nil, "current exists")
        require(abs(current!.start - 1) < 1e-9 && abs(current!.end - 2) < 1e-9, "P is 1…2")
        let previous = WoslicerPreview.previousSegment(current: 1.0, marks: [1.0], duration: 2)
        require(previous != nil, "previous exists")
        require(abs(previous!.start - 0) < 1e-9 && abs(previous!.end - 1) < 1e-9, "O is 0…1")
        let first = WoslicerPreview.currentSegment(current: 0.5, marks: [1.0], duration: 2)
        require(first != nil && abs(first!.start - 0) < 1e-9 && abs(first!.end - 1) < 1e-9, "0.5 is 0…1")
        require(WoslicerPreview.previousSegment(current: 0.5, marks: [1.0], duration: 2) == nil, "first has no previous")
        let whole = WoslicerPreview.currentSegment(current: 0, marks: [], duration: 2)
        require(whole != nil && abs(whole!.start - 0) < 1e-9 && abs(whole!.end - 2) < 1e-9, "no marks plays all")
        require(WoslicerPreview.currentSegment(current: 1, marks: [1], duration: 0) == nil, "empty file")
    }

    /// 同一条 2 秒夹具：当前段取出后一半，样本全是 -2000。
    private static func testWoslicerPreviewExtractsOneSecond() {
        let sampleRate = 44100
        var samples = [Int16](repeating: 1000, count: sampleRate)
        samples += [Int16](repeating: -2000, count: sampleRate)
        let wav = BmhelperPcmWav(sampleRate: sampleRate, channels: 1, samples: samples)
        let range = WoslicerPreview.currentSegment(current: 1.0, marks: [1.0], duration: 2)!
        let part = AudioSlice.extract(wav: wav, start: range.start, end: range.end)
        require(part.samples.count == 44100, "one second")
        require(part.samples.allSatisfy { $0 == -2000 }, "second half")
        let previous = WoslicerPreview.previousSegment(current: 1.0, marks: [1.0], duration: 2)!
        let first = AudioSlice.extract(wav: wav, start: previous.start, end: previous.end)
        require(first.samples.count == 44100 && first.samples.allSatisfy { $0 == 1000 }, "first half")
    }

    /// 2 秒 44100 单声道、宽 2：前一半 1000，后一半 -2000。
    private static func testWoslicerWaveformTwoSecondColumns() {
        let sampleRate = 44100
        var samples = [Int16](repeating: 1000, count: sampleRate)
        samples += [Int16](repeating: -2000, count: sampleRate)
        let columns = WoslicerWaveform.columns(samples: samples, channels: 1, width: 2)
        require(columns.count == 2, "two columns")
        let first = WoslicerWaveform.pcm16Float(1000)
        let second = WoslicerWaveform.pcm16Float(-2000)
        require(columns[0].peak == first, "col0 peak")
        require(columns[0].min == first && columns[0].max == first, "col0 min/max")
        require(columns[1].peak == abs(second), "col1 peak")
        require(columns[1].min == second && columns[1].max == second, "col1 min/max")
    }

    /// 641 帧、宽 320：丢掉 1 帧尾巴，peak 都是 0.5。
    private static func testWoslicerWaveformDropsLeftover() {
        let samples = [Int16](repeating: 16384, count: 641)
        let columns = WoslicerWaveform.columns(samples: samples, channels: 1, width: 320)
        require(columns.count == 320, "drop leftover")
        require(columns.allSatisfy { $0.peak == 0.5 }, "peak 0.5")
    }

    /// 100 帧、宽 320：`per == 0`，每帧一列。
    private static func testWoslicerWaveformShortFileOneColumnPerFrame() {
        let samples = [Int16](repeating: 1, count: 100)
        let columns = WoslicerWaveform.columns(samples: samples, channels: 1, width: 320)
        require(columns.count == 100, "per == 0")
    }

    /// 立体声一帧：左 16384、右 0。
    private static func testWoslicerWaveformStereoMinMax() {
        let columns = WoslicerWaveform.columns(samples: [16384, 0], channels: 2, width: 780)
        require(columns.count == 1, "one column")
        require(columns[0].min == 0, "stereo min")
        require(columns[0].max == 0.5, "stereo max")
        require(columns[0].peak == 0.5, "stereo peak")
    }

    private static func testWoslicerWaveformMarkX() {
        require(WoslicerWaveform.markX(seconds: 1.0, duration: 2, width: 780) == 390, "1s")
        require(WoslicerWaveform.markX(seconds: 0, duration: 2, width: 780) == 0, "0s")
    }

    /// 裁断线 `[1.0]`、时长 2：切点 `[0, 1]`，横坐标含 0 和 390。
    private static func testWoslicerWaveformSplitMarkXs() {
        let times = WoslicerSplit.splitPoints(marks: [1.0], duration: 2)
        require(times.count == 2, "0 and 1")
        require(abs(times[0] - 0) < 1e-9 && abs(times[1] - 1) < 1e-9, "prepend 0")
        let xs = WoslicerWaveform.markXs(marks: [1.0], duration: 2, width: 780)
        require(xs.contains(0) && xs.contains(390), "mark x")
    }

    private static func testWoslicerWaveformLoadsOgg() {
        let input = audioFixtureURL("sine-440.ogg")
        AudioSlice.decodeToWav = { url in
            try? IBMSAudioBridge.pcmWav(fromFile: url.path)
        }
        defer { AudioSlice.decodeToWav = nil }
        let payload = WoslicerWaveform.load(url: input)
        require(!payload.columns.isEmpty, "ogg columns")
        require(payload.columns.contains(where: { $0.peak > 0 }), "ogg peak")
    }

    private static func testWoslicerWaveformEmptySamples() {
        require(WoslicerWaveform.columns(samples: [], channels: 1).isEmpty, "empty")
    }

    private static func testAudioSlicerWorkingGeometry() {
        require(AudioSlicerLayout.clientSize.width == 960, "width 960")
        require(AudioSlicerLayout.clientSize.height == 600, "height 600")
        require(AudioSlicerLayout.minimumSize == CGSize(width: 820, height: 520), "minimum size")
        require(AudioSlicerLayout.originalClientSize == nil, "not measured")
        require(AudioSlicerLayout.waveformMinimumHeight == 160, "wave minimum height")
        require(AudioSlicerLayout.contentInset == 16, "content inset")
        let initialWaveform = AudioSlicerLayout.waveformFrame(in: AudioSlicerLayout.clientSize)
        require(initialWaveform.width == 928 && initialWaveform.height == 240, "initial waveform bounds")
        let minimumWaveform = AudioSlicerLayout.waveformFrame(in: AudioSlicerLayout.minimumSize)
        require(minimumWaveform.width == 788 && minimumWaveform.height == 160, "minimum waveform bounds")
    }

    /// 44100 个 `1000` + 22050 个 `0`：只去末端，留下 1 秒有声。
    private static func testWoslicerTrimTrailingZeros() {
        var samples = [Int16](repeating: 1000, count: 44100)
        samples += [Int16](repeating: 0, count: 22050)
        require(WoslicerTrim.trailingSilentFrames(samples: samples, channels: 1) == 22050, "trailing")
        let trimmed = WoslicerTrim.trim(BmhelperPcmWav(sampleRate: 44100, channels: 1, samples: samples))
        require(trimmed.samples.count == 44100, "one second")
        require(trimmed.samples.allSatisfy { $0 == 1000 }, "kept 1000")
        require(trimmed.sampleRate == 44100 && trimmed.channels == 1, "format")
    }

    /// 开头静音不去。
    private static func testWoslicerTrimKeepsLeadingZeros() {
        var samples = [Int16](repeating: 0, count: 22050)
        samples += [Int16](repeating: 1000, count: 44100)
        require(WoslicerTrim.trailingSilentFrames(samples: samples, channels: 1) == 0, "no trailing")
        let wav = BmhelperPcmWav(sampleRate: 44100, channels: 1, samples: samples)
        require(WoslicerTrim.trim(wav) == wav, "keep leading")
    }

    /// 立体声末帧左右都是 0 才丢掉。
    private static func testWoslicerTrimStereoSilentFrame() {
        let samples: [Int16] = [1000, 0, 0, 0]
        require(WoslicerTrim.trailingSilentFrames(samples: samples, channels: 2) == 1, "one frame")
        let trimmed = WoslicerTrim.trim(BmhelperPcmWav(sampleRate: 44100, channels: 2, samples: samples))
        require(trimmed.samples == [1000, 0], "kept first frame")
    }

    /// 末帧只有右声道是 0：整段留下。
    private static func testWoslicerTrimStereoRightOnlyZero() {
        let samples: [Int16] = [1000, 1000, 1000, 0]
        require(WoslicerTrim.trailingSilentFrames(samples: samples, channels: 2) == 0, "not silent")
        let wav = BmhelperPcmWav(sampleRate: 44100, channels: 2, samples: samples)
        require(WoslicerTrim.trim(wav) == wav, "keep mixed frame")
    }

    /// 全是 0：样本变空，采样率和声道留下。
    private static func testWoslicerTrimAllZeros() {
        let wav = BmhelperPcmWav(sampleRate: 22050, channels: 2, samples: [Int16](repeating: 0, count: 200))
        let trimmed = WoslicerTrim.trim(wav)
        require(trimmed.samples.isEmpty, "empty")
        require(trimmed.sampleRate == 22050 && trimmed.channels == 2, "kept format")
        require(WoslicerTrim.trailingSilentFrames(samples: wav.samples, channels: 2) == 100, "100 frames")
    }

    /// 没有 0：和输入相等。
    private static func testWoslicerTrimNoZeros() {
        let wav = BmhelperPcmWav(sampleRate: 44100, channels: 1, samples: [1000, -2000, 3])
        require(WoslicerTrim.trim(wav) == wav, "unchanged")
        require(WoslicerTrim.trailingSilentFrames(samples: wav.samples, channels: 1) == 0, "none")
    }

    /// 1 秒 `1000` + 0.5 秒 `0`：trim 后时长 1 秒。没有中间裁断线，只补 `0`，只写出一段。
    private static func testWoslicerSplitTrimsTrailingSilenceToOneSlice() {
        var samples = [Int16](repeating: 1000, count: 44100)
        samples += [Int16](repeating: 0, count: 22050)
        let wav = BmhelperPcmWav(sampleRate: 44100, channels: 1, samples: samples)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-audio-trim-one-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("tone.wav")
        try! BmhelperWavIO.write(wav).write(to: input)

        let urls = try! AudioSlice.splitFile(
            mode: .woslicer,
            input: input,
            outputDirectory: root,
            prefix: WoslicerSplit.defaultBaseName(input: input),
            request: .woslicer(marks: [], offsetSeconds: 0, duration: nil)
        )
        require(urls.map(\.lastPathComponent) == ["tone_001.wav"], "one slice")
        let part = try! BmhelperWavIO.read(Data(contentsOf: urls[0]))
        require(part.samples.count == 44100, "trimmed length")
        require(part.samples.allSatisfy { $0 == 1000 }, "no trailing zeros")
    }

    /// 2 秒有声 + 0.5 秒 `0`、裁断线 `1.0`：仍是两段，没有第三段。
    private static func testWoslicerSplitKeepsTwoSlicesAfterTrailingZeros() {
        var samples = [Int16](repeating: 1000, count: 44100)
        samples += [Int16](repeating: -2000, count: 44100)
        samples += [Int16](repeating: 0, count: 22050)
        let wav = BmhelperPcmWav(sampleRate: 44100, channels: 1, samples: samples)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-audio-trim-two-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("kick.wav")
        try! BmhelperWavIO.write(wav).write(to: input)

        let urls = try! AudioSlice.splitFile(
            mode: .woslicer,
            input: input,
            outputDirectory: root,
            prefix: WoslicerSplit.defaultBaseName(input: input),
            request: .woslicer(marks: [1.0], offsetSeconds: 0, duration: nil)
        )
        require(urls.map(\.lastPathComponent) == ["kick_001.wav", "kick_002.wav"], "two slices")
        let first = try! BmhelperWavIO.read(Data(contentsOf: urls[0]))
        let second = try! BmhelperWavIO.read(Data(contentsOf: urls[1]))
        require(first.samples.count == 44100 && first.samples.allSatisfy { $0 == 1000 }, "first")
        require(second.samples.count == 44100 && second.samples.allSatisfy { $0 == -2000 }, "second")
        let extras = try! FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" && $0.lastPathComponent.hasPrefix("kick_") }
        require(extras.count == 2, "no third slice")
    }

    /// 同一条 1 秒 `1000` + 0.5 秒 `0`：`load` 按 1 秒算列，不再按 1.5 秒。
    private static func testWoslicerWaveformLoadUsesTrimmedDuration() {
        var samples = [Int16](repeating: 1000, count: 44100)
        samples += [Int16](repeating: 0, count: 22050)
        let wav = BmhelperPcmWav(sampleRate: 44100, channels: 1, samples: samples)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-audio-trim-wave-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("tone.wav")
        try! BmhelperWavIO.write(wav).write(to: input)

        let payload = WoslicerWaveform.load(url: input, width: 2)
        require(abs(payload.duration - 1) < 1e-9, "duration 1")
        require(payload.columns.count == 2, "two columns")
        let peak = WoslicerWaveform.pcm16Float(1000)
        require(payload.columns.allSatisfy { $0.peak == peak && $0.min == peak }, "no zero column")
    }

    private static func testWoslicerTrimLayoutFlag() {
        require(WoslicerLayout.trimImplemented, "trim flag")
        let status = WoslicerLayout.shellStatus
        require(
            status.contains("末端") || status.contains("静音") || status.contains("0 帧"),
            "shell mentions trailing zeros"
        )
        require(WoslicerLayout.originalClientSize == nil, "client size still unmeasured")
    }

    /// 现有切片用 `Int(秒 * 采样率)`，对半切会丢掉一帧。这里找一条能铺满的线。
    private static func coveringMark(frames: Int, sampleRate: Int) -> Double {
        let rate = max(sampleRate, 1)
        let duration = Double(frames) / Double(rate)
        var index = max(frames / 2, 1)
        while index > 0 {
            let mark = Double(index) / Double(rate)
            let first = Int(mark * Double(rate))
            let second = Int((duration - mark) * Double(rate))
            if first > 0, second > 0, first + second == frames {
                return mark
            }
            index -= 1
        }
        return duration / 2
    }

    private static func audioFixtureURL(_ name: String) -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            cwd.appendingPathComponent("tests/fixtures/audio/\(name)"),
            cwd.appendingPathComponent("../../tests/fixtures/audio/\(name)"),
            cwd.appendingPathComponent("../../../tests/fixtures/audio/\(name)")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        fputs("missing tests/fixtures/audio/\(name) from \(cwd.path)\n", stderr)
        exit(EXIT_FAILURE)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
