import CoreGraphics
import Foundation

@main
struct BmhelperDivisionTests {
    static func main() {
        testDefaultSettings()
        testOneNoteMatchesOneToOne()
        testFarNotesShareOneDefinition()
        testOverlappingNotesNeedTwoDefinitions()
        testVelocitySplitsClusters()
        testSrcCopyKeepsEveryNote()
        testLayoutNumbers()
        testSequenceFromDefaultCluster()
        testDivCopyFromDefaultCluster()
        testEditorBindsClusteredTimeline()
        print("BmhelperDivisionTests passed")
    }

    /// 量化 480 时：gate 阈 60，vel 阈 5，多重阈值 240，起始 01。
    private static func testDefaultSettings() {
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        require(setting.srcCopy == false, "src_copy default false")
        require(setting.headMargin == 0, "head_margin 0")
        require(setting.minInterval == 480, "min_interval = quantize")
        require(setting.sortType == .nnGateVel, "SORT_NN_GATE_V")
        require(setting.gateThreshold == 60, "quantize/8")
        require(setting.velocityThreshold == 5, "vel 5")
        require(setting.zzDefinition && setting.mlDefinition, "zz and ml on")
        require(setting.startDefinition == 1, "start 1")
        require(setting.mlThreshold == 240, "quantize/2")
        require(setting.name == "melody", "name")
    }

    private static func testOneNoteMatchesOneToOne() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.definitions == [BmhelperDivisionDefinition(zz: "01", div: 0)], "one def")
        require(result.src2def == [0], "note 0 → def 0")
        require(
            result.notes == [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)],
            "one cluster at 0"
        )
        require(result.quantize == 480, "quantize kept")
        require(
            BmhelperDivision.formatDefinitionBlock(name: "melody", offset: 0, result: result)
                == "#WAV01 melody_000.wav\r\n",
            "one note text"
        )
    }

    /// 间隔 520 ≥ 240，同一聚类只要一条定义。
    private static func testFarNotesShareOneDefinition() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 1000, gate: 480, noteNum: 60, velocity: 100)
        ]
        let setting = BmhelperDivisionSetting.makeDefault(name: "kick", quantize: 480)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.definitions.count == 1, "one cluster one def")
        require(
            result.notes == [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)],
            "one laid note at 0"
        )
        require(result.definitions[0] == BmhelperDivisionDefinition(zz: "01", div: 0), "01 / 0")
        require(result.src2def == [0, 0], "both notes share 01")
        require(
            BmhelperDivision.formatDefinitionBlock(name: "kick", offset: 0, result: result)
                == "#WAV01 kick_000.wav\r\n",
            "shared def text"
        )
    }

    /// 同拍重叠：mint = -480 < 240，多重定义 2 条，div 都是 0。
    private static func testOverlappingNotesNeedTwoDefinitions() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        ]
        let setting = BmhelperDivisionSetting.makeDefault(name: "hat", quantize: 480)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.definitions.count == 2, "overload 2")
        require(result.notes.count == 1 && result.notes[0].position == 0, "one cluster note")
        require(result.definitions[0] == BmhelperDivisionDefinition(zz: "01", div: 0), "01")
        require(result.definitions[1] == BmhelperDivisionDefinition(zz: "02", div: 0), "02 same div")
        require(result.src2def == [0, 1], "alternate defs")
        require(
            BmhelperDivision.formatDefinitionBlock(name: "hat", offset: 0, result: result)
                == "#WAV01 hat_000.wav\r\n#WAV02 hat_000.wav\r\n",
            "two lines same div index"
        )
    }

    private static func testVelocitySplitsClusters() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 20),
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        ]
        var setting = BmhelperDivisionSetting.makeDefault(name: "snare", quantize: 480)
        setting.mlDefinition = false
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.definitions.count == 2, "vel 80 > 5")
        require(result.definitions[0].zz == "01" && result.definitions[1].zz == "02", "two zz")
        require(result.src2def[1] == 0, "vel 100 sorts first")
        require(result.src2def[0] == 1, "vel 20 sorts second")
        require(result.notes.count == 2, "two laid notes")
        require(result.notes[0].position == 0 && result.notes[0].velocity == 100, "high vel at 0")
        require(result.notes[1].position == 960 && result.notes[1].velocity == 20, "next at 960")
    }

    private static func testSrcCopyKeepsEveryNote() {
        let notes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 1000, gate: 480, noteNum: 60, velocity: 100)
        ]
        var setting = BmhelperDivisionSetting.makeDefault(name: "copy", quantize: 480)
        setting.srcCopy = true
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.definitions.count == 2, "src_copy no cluster")
        require(result.definitions.map(\.div) == [0, 1], "one div each")
        require(result.src2def == [0, 1], "1:1")
        require(result.notes.map(\.position) == [0, 1000], "src positions kept")
    }

    private static func testLayoutNumbers() {
        require(BmhelperDivisionSettingLayout.clientSize == CGSize(width: 330, height: 455), "330x455")
        require(BmhelperDivisionSettingLayout.title == "Division settings", "title")
        require(BmhelperDivisionSettingLayout.sortTitles[1] == "nn/gate/vel", "default sort label")
        require(BmhelperMainLayout.newDivisionMenuTitle == "New division (&N)...", "New division")
        require(BmhelperMainLayout.openCutterMenuTitle == "Open built-in audio cutter", "cutter menu")
        require(BmhelperAudioSplitterLayout.clientSize.width == 800, "splitter width")
        require(BmhelperAudioSplitterLayout.originalClientSize == nil, "height not from source")
        require(BmhelperAudioSplitterLayout.title(divisionName: "melody") == "Audio splitter (division: \"melody\")", "splitter title")
        require(BmhelperAudioSplitterLayout.defaultBpm == 120, "default BPM")
        require(BmhelperAudioSplitterLayout.defaultOffsetMs == 0, "default offset")
        require(BmhelperMainLayout.clientSize == CGSize(width: 1000, height: 700), "main redesigned size")
        require(BmhelperMainLayout.minimumWindowSize == CGSize(width: 860, height: 600), "main minimum size")
        var zz = ZZNumber()
        require(zz.from_string("0G"), "from_string 0G")
        require(zz.to_string() == "0G" && zz.integerValue == 16, "0G is 16")
    }

    /// 默认聚类一条 C4：源位置 0、zz `01`，拷出来仍是 header + `101000000001`。
    private static func testSequenceFromDefaultCluster() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.definitions[0].zz == "01", "cluster zz 01")
        var zz = ZZNumber()
        require(zz.from_string(result.definitions[0].zz), "from_string 01")
        require(zz.integerValue == 1, "01 integer is 1")
        require(
            BmhelperSequence.format(
                positions: notes.map(\.position),
                zzStrings: result.definitions.map(\.zz),
                src2def: result.src2def,
                quantize: result.quantize
            ) == BmhelperSequence.header + "101000000001\r\n",
            "default C4 sequence"
        )
    }

    /// 默认聚类一条 C4：时间线位置 0，拷出来是 header + `011000000001`。
    private static func testDivCopyFromDefaultCluster() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: 480)
        require(result.notes.count == 1 && result.notes[0].position == 0, "timeline at 0")
        require(
            BmhelperDivCopy.format(
                positions: result.notes.map(\.position),
                quantize: result.quantize
            ) == BmhelperSequence.header + "011000000001\r\n",
            "default C4 division copy"
        )
    }

    /// 对照已有 BH-DIV 夹具：第二份钢琴卷绑聚类后的时间线，不是源位置。
    private static func testEditorBindsClusteredTimeline() {
        let farNotes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 1000, gate: 480, noteNum: 60, velocity: 100)
        ]
        let farSetting = BmhelperDivisionSetting.makeDefault(name: "kick", quantize: 480)
        let far = BmhelperDivision.divide(notes: farNotes, setting: farSetting, quantize: 480)
        require(farNotes.count == 2, "source two C4")
        require(far.notes.count == 1 && far.notes[0].position == 0, "timeline one at 0")
        let boundFar = BmhelperMidiView.notesToShow(
            source: farNotes,
            timeline: far.notes,
            hasSelection: true
        )
        require(boundFar?.count == 1, "bind 1 not 2")
        require(boundFar?[0].position == 0, "bound at 0")
        require(
            BmhelperMidiView.notesToShow(
                source: farNotes,
                timeline: far.notes,
                hasSelection: false
            ) == nil,
            "no selection nil"
        )

        let velNotes = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 20),
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        ]
        var velSetting = BmhelperDivisionSetting.makeDefault(name: "snare", quantize: 480)
        velSetting.mlDefinition = false
        let vel = BmhelperDivision.divide(notes: velNotes, setting: velSetting, quantize: 480)
        require(vel.notes.count == 2, "vel two laid")
        require(vel.notes[1].position == 960, "second timeline 960")
        let boundVel = BmhelperMidiView.notesToShow(
            source: velNotes,
            timeline: vel.notes,
            hasSelection: true
        )
        require(boundVel?.count == 2, "selected uses two timeline notes")
        require(boundVel?[0].position == 0 && boundVel?[1].position == 960, "not source 0,0")
        require(boundVel?[1].position != velNotes[1].position || velNotes[1].position != 960, "source stays 0")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
