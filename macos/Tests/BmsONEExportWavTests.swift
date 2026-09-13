import Foundation

@main
struct BmsONEExportWavTests {
    static func main() async {
        testVolumeLabelAtUnity()
        testAbsoluteTimeHalfBeat()
        testEmptyWritesNoSampleLog()
        testOneNoteHardClip()
        testSecondNoteCutsFirst()
        testContinueDoesNotTrigger()
        testStopShiftsLaterNote()
        testWriteWithoutOverwritingPreservesExistingFile()
        testWriteWithoutOverwritingCreatesValidWav()
        testFailedWriteLeavesNoDestination()
        testCancelledWriteLeavesNoOutput()
        await testConcurrentWritesLeaveOneCompleteOutput()
        testMasterWaveformPackets()
        print("BmsONEExportWavTests passed")
    }

    private static func testVolumeLabelAtUnity() {
        require(BmsONEMasterExport.dbGain(slider: 100) == 0, "default 0 dB")
        require(abs(BmsONEMasterExport.linearGain(slider: 100) - 1) < 1e-6, "gain 1")
        require(BmsONEMasterExport.volumeLabel(slider: 100) == "0.00dB (100.00%)", "0dB label")
        require(BmsONEDialogLayout.exportCannotOpen == "Cannot open file.", "open error")
        require(BmsONEDialogLayout.exportComplete == "Export complete.", "complete")
        require(BmsONEDialogLayout.exportNoSample == "No sample was given.", "empty")
        require(BmsONEDialogLayout.exportSampleRate == 44100, "SampleRate")
    }

    /// initBPM 120、分辨率 240，脉冲 240 是半拍 = 0.5 秒 = 22050 样本。
    private static func testAbsoluteTimeHalfBeat() {
        let seconds = BmsONEMasterExport.absoluteTime(pulse: 240, initBpm: 120, resolution: 240, bpmNotes: [])
        require(abs(seconds - 0.5) < 1e-9, "half beat")
        require(
            BmsONEMasterExport.sampleIndex(pulse: 240, initBpm: 120, resolution: 240, bpmNotes: []) == 22050,
            "22050 samples"
        )
    }

    private static func testEmptyWritesNoSampleLog() {
        let rendered = BmsONEMasterExport.render(samples: [], slider: 100, clip: .hard)
        require(rendered.log == BmsONEDialogLayout.exportNoSample, "empty log")
        let wave = BmsONEMasterExport.readPcm16(rendered.data)
        require(wave != nil && wave!.samples.isEmpty, "empty data chunk")
        require(wave!.sampleRate == 44100 && wave!.channels == 2, "stereo 44100 header")
    }

    /// 100 个单声道样本 10000。0 dB 硬裁剪后左右都是 10000。
    private static func testOneNoteHardClip() {
        let wave = BmsONEExportWave(sampleRate: 44100, channels: 1, samples: [Int16](repeating: 10000, count: 100))
        let mixed = BmsONEMasterExport.mix(
            initBpm: 120,
            resolution: 240,
            bpmNotes: [],
            channels: [(notes: [(y: 0, c: false)], wave: wave)]
        )
        require(mixed.count == 100, "100 frames")
        require(abs(mixed[0].left - 10000 / 32767) < 1e-6, "float left")
        let rendered = BmsONEMasterExport.render(samples: mixed, slider: 100, clip: .hard)
        require(rendered.log.contains("Wrote 100 samples."), "wrote count")
        require(rendered.log.contains("After hard clipping"), "hard title")
        let out = BmsONEMasterExport.readPcm16(rendered.data)!
        require(out.channels == 2 && out.samples.count == 200, "stereo pcm")
        require(out.samples[0] == 10000 && out.samples[1] == 10000, "identity 10000")
    }

    /// 同一通道两个触发音。第二个在 240，截断第一段到 22050。
    private static func testSecondNoteCutsFirst() {
        let wave = BmsONEExportWave(
            sampleRate: 44100,
            channels: 1,
            samples: [Int16](repeating: 8000, count: 44100)
        )
        let mixed = BmsONEMasterExport.mix(
            initBpm: 120,
            resolution: 240,
            bpmNotes: [],
            channels: [(notes: [(y: 0, c: false), (y: 240, c: false)], wave: wave)]
        )
        require(mixed.count == 22050 + 44100, "cut plus full restart")
        require(abs(mixed[0].left - 8000 / 32767) < 1e-6, "first starts")
        require(abs(mixed[22050].left - 8000 / 32767) < 1e-6, "second restarts")
    }

    /// `c == true` 对照 `noteType > 0`，不触发主控。
    private static func testContinueDoesNotTrigger() {
        let wave = BmsONEExportWave(sampleRate: 44100, channels: 1, samples: [2000, 2000, 2000, 2000])
        let mixed = BmsONEMasterExport.mix(
            initBpm: 120,
            resolution: 240,
            bpmNotes: [],
            channels: [(notes: [(y: 0, c: true)], wave: wave)]
        )
        require(mixed.isEmpty, "continue is silent")
    }

    /// 拍 0 停 240 脉冲（1 拍）。120 BPM 下，脉冲 240 是 1.0 秒 = 44100 样本。
    private static func testStopShiftsLaterNote() {
        let seconds = BmsONEMasterExport.absoluteTime(
            pulse: 240,
            initBpm: 120,
            resolution: 240,
            bpmNotes: [],
            stopNotes: [(y: 0, v: 240)]
        )
        require(abs(seconds - 1.0) < 1e-9, "travel 0.5s plus stop 0.5s")
        require(
            BmsONEMasterExport.sampleIndex(
                pulse: 240,
                initBpm: 120,
                resolution: 240,
                bpmNotes: [],
                stopNotes: [(y: 0, v: 240)]
            ) == 44100,
            "44100 samples"
        )
        let atStop = BmsONEMasterExport.absoluteTime(
            pulse: 0,
            initBpm: 120,
            resolution: 240,
            bpmNotes: [],
            stopNotes: [(y: 0, v: 240)]
        )
        require(abs(atStop) < 1e-9, "stop at the query pulse is not included")
    }

    private static func testWriteWithoutOverwritingPreservesExistingFile() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("existing.wav")
        let original = Data("do not replace".utf8)
        try! original.write(to: output)
        do {
            try BmsONEMasterExport.writeWithoutOverwriting(Data("replacement".utf8), to: output)
            require(false, "existing destination must reject export")
        } catch let error as BmsONEMasterExportError {
            require(error == .destinationExists, "existing destination error")
        } catch {
            require(false, "unexpected existing destination error")
        }
        require((try? Data(contentsOf: output)) == original, "existing file contents remain unchanged")
        require(directoryContents(directory) == ["existing.wav"], "existing rejection leaves no temporary file")
    }

    private static func testWriteWithoutOverwritingCreatesValidWav() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("success.wav")
        let rendered = BmsONEMasterExport.render(
            samples: [BmsONEMasterSample(left: 0.25, right: -0.25)],
            slider: 100,
            clip: .hard
        )
        do {
            try BmsONEMasterExport.writeWithoutOverwriting(rendered.data, to: output)
        } catch {
            require(false, "successful export write")
        }
        let data = try? Data(contentsOf: output)
        let wave = data.flatMap(BmsONEMasterExport.readPcm16)
        require(wave?.channels == 2 && wave?.samples.count == 2, "successful output is a valid stereo WAV")
        require(directoryContents(directory) == ["success.wav"], "successful export cleans its temporary file")
    }

    private static func testFailedWriteLeavesNoDestination() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingDirectory = directory.appendingPathComponent("missing", isDirectory: true)
        let output = missingDirectory.appendingPathComponent("failure.wav")
        do {
            try BmsONEMasterExport.writeWithoutOverwriting(Data([1, 2, 3]), to: output)
            require(false, "missing parent must reject export")
        } catch let error as BmsONEMasterExportError {
            require(error == .cannotOpenFile, "missing parent error")
        } catch {
            require(false, "unexpected missing parent error")
        }
        require(!FileManager.default.fileExists(atPath: output.path), "failed export leaves no destination")
        require(!FileManager.default.fileExists(atPath: missingDirectory.path), "failed export creates no directory")
    }

    private static func testCancelledWriteLeavesNoOutput() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("cancelled.wav")
        do {
            try BmsONEMasterExport.writeWithoutOverwriting(
                Data(repeating: 0x33, count: 16_384),
                to: output,
                shouldCancel: { true }
            )
            require(false, "cancelled export must not commit")
        } catch let error as BmsONEMasterExportError {
            require(error == .cancelled, "cancelled export error")
        } catch {
            require(false, "unexpected cancelled export error")
        }
        require(directoryContents(directory).isEmpty, "cancelled export cleans temporary file")
    }

    private static func testConcurrentWritesLeaveOneCompleteOutput() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("race.wav")
        let first = Data(repeating: 0x11, count: 16_384)
        let second = Data(repeating: 0x22, count: 16_384)
        let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for data in [first, second] {
                group.addTask {
                    do {
                        try BmsONEMasterExport.writeWithoutOverwriting(data, to: output)
                        return true
                    } catch BmsONEMasterExportError.destinationExists {
                        return false
                    } catch {
                        return false
                    }
                }
            }
            var values: [Bool] = []
            for await outcome in group { values.append(outcome) }
            return values
        }
        require(outcomes.filter { $0 }.count == 1, "exactly one concurrent export commits")
        let written = try? Data(contentsOf: output)
        require(written == first || written == second, "concurrent export commits one complete payload")
        require(directoryContents(directory) == ["race.wav"], "concurrent export cleans both temporary files")
    }

    private static func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IBMSNativeExportTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func directoryContents(_ directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()) ?? []
    }

    /// 对照 `ReconstructRmsCache` / `UpdateBuffer`。rms 先存均方，画一行再开方。
    private static func testMasterWaveformPackets() {
        let samples = Array(repeating: BmsONEMasterSample(left: 0.5, right: -0.5), count: 4)
        let packet = BmsONEMasterWaveform.packet(samples: samples, start: 0, end: 4)
        require(abs(packet.meanSquareL - 0.25) < 1e-6, "mean square 0.25")
        require(abs(packet.peakL - 0.5) < 1e-6 && abs(packet.peakR - 0.5) < 1e-6, "peak 0.5")
        let empty = BmsONEMasterWaveform.packet(samples: samples, start: 2, end: 2)
        require(empty.meanSquareL == 0 && empty.peakL == 0, "empty interval")
        let loud = BmsONEMasterPacket(meanSquareL: 1, meanSquareR: 1, peakL: 1, peakR: 1, available: true)
        let row = BmsONEMasterWaveform.combine([packet, loud][...])
        require(abs(row.rmsL - Float(0.625).squareRoot()) < 1e-6, "sqrt mean of mean-squares")
        require(abs(row.peakL - 1) < 1e-6, "peak max")
        let cache = BmsONEMasterWaveformCache(
            samples: [],
            actualLength: 0,
            resolution: 240,
            initBpm: 120,
            bpmNotes: [],
            stopNotes: []
        )
        require(cache.viewLength == 30720, "empty cache viewLength")
        require(cache.row(from: 0, to: 8) == .empty, "no samples stay empty")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
