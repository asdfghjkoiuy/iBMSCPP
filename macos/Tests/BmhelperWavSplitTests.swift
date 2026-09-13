import Foundation

@main
struct BmhelperWavSplitTests {
    static func main() {
        testOneNoteSplitAtZero()
        testTwoClustersOneSecondApart()
        testOffsetShiftsTimes()
        testDuplicatePositionsAreUnique()
        testOutputNamesStartAt001()
        testSliceWritesTwoWavFiles()
        testMissingOutputDirectory()
        testUnreadableInput()
        print("BmhelperWavSplitTests passed")
    }

    /// 一条 C4 排在 0，BPM 120 → 切点 `0`。
    private static func testOneNoteSplitAtZero() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        let times = BmhelperWavSplit.splitPoints(
            notes: result.notes,
            quantize: result.quantize,
            bpm: 120,
            offsetMs: 0
        )
        require(times == [0], "one note → 0")
    }

    /// 速度拆成两簇后，第二簇在 960 tick。BPM 120、量化 480 → `0` 和 `1.0`。
    private static func testTwoClustersOneSecondApart() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 20),
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        ]
        var setting = BmhelperDivisionSetting.makeDefault(name: "snare", quantize: 480)
        setting.mlDefinition = false
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        let times = BmhelperWavSplit.splitPoints(
            notes: result.notes,
            quantize: 480,
            bpm: 120,
            offsetMs: 0
        )
        require(times.count == 2, "two times")
        require(abs(times[0] - 0) < 1e-9, "first 0")
        require(abs(times[1] - 1.0) < 1e-9, "second 1.0")
    }

    private static func testOffsetShiftsTimes() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let times = BmhelperWavSplit.splitPoints(notes: notes, quantize: 480, bpm: 120, offsetMs: 500)
        require(times.count == 1 && abs(times[0] - 0.5) < 1e-9, "offset 500ms")
    }

    private static func testDuplicatePositionsAreUnique() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 0, gate: 240, noteNum: 64, velocity: 80)
        ]
        let times = BmhelperWavSplit.splitPoints(notes: notes, quantize: 480, bpm: 120, offsetMs: 0)
        require(times == [0], "same position one time")
    }

    private static func testOutputNamesStartAt001() {
        require(BmhelperWavSplit.outputFileName(prefix: "melody", indexFromZero: 0) == "melody_001.wav", "_001")
        require(BmhelperWavSplit.outputFileName(prefix: "melody", indexFromZero: 1) == "melody_002.wav", "_002")
    }

    /// 2 秒、44100 Hz、单声道。前一半样本 1000，后一半 -2000。
    /// 切点 0 / 1.0 → `prefix_001.wav` 和 `prefix_002.wav` 各 1 秒。
    private static func testSliceWritesTwoWavFiles() {
        let sampleRate = 44100
        var samples = [Int16](repeating: 1000, count: sampleRate)
        samples += [Int16](repeating: -2000, count: sampleRate)
        let wav = BmhelperPcmWav(sampleRate: sampleRate, channels: 1, samples: samples)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-bmhelper-split-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("source.wav")
        try! BmhelperWavIO.write(wav).write(to: input)

        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 960, gate: 480, noteNum: 62, velocity: 100)
        ]
        let urls = try! BmhelperWavSplit.splitFile(
            input: input,
            outputDirectory: root,
            prefix: "kick",
            notes: notes,
            quantize: 480,
            bpm: 120,
            offsetMs: 0
        )
        require(urls.map(\.lastPathComponent) == ["kick_001.wav", "kick_002.wav"], "two names")

        let first = try! BmhelperWavIO.read(Data(contentsOf: urls[0]))
        let second = try! BmhelperWavIO.read(Data(contentsOf: urls[1]))
        require(first.sampleRate == 44100 && first.channels == 1, "first format")
        require(first.samples.count == 44100, "first 1s")
        require(second.samples.count == 44100, "second 1s")
        require(first.samples.allSatisfy { $0 == 1000 }, "first half")
        require(second.samples.allSatisfy { $0 == -2000 }, "second half")
    }

    private static func testMissingOutputDirectory() {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("missing-in.wav")
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-missing-\(UUID().uuidString)", isDirectory: true)
        do {
            _ = try BmhelperWavSplit.splitFile(
                input: input,
                outputDirectory: missing,
                prefix: "x",
                notes: [],
                quantize: 480,
                bpm: 120,
                offsetMs: 0
            )
            require(false, "missing dir should throw")
        } catch let error as BmhelperWavSplitError {
            require(error == .outputPathMissing, "missing")
            require(error.localizedDescription == "Output path does not exist", "missing text")
        } catch {
            require(false, "wrong error type")
        }
    }

    private static func testUnreadableInput() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-bmhelper-bad-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("not-audio.txt")
        try! Data("not wav".utf8).write(to: input)
        do {
            _ = try BmhelperWavSplit.splitFile(
                input: input,
                outputDirectory: root,
                prefix: "x",
                notes: [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)],
                quantize: 480,
                bpm: 120,
                offsetMs: 0
            )
            require(false, "bad wav should throw")
        } catch let error as BmhelperWavSplitError {
            if case .couldNotReadInput(let path) = error {
                require(path == input.path, "input path")
                require(
                    error.localizedDescription == "Couldn't read input audio file '\(input.path)'",
                    "read error text"
                )
            } else {
                require(false, "expected read error")
            }
        } catch {
            require(false, "wrong error type")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
