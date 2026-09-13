import Foundation

@main
struct BmhelperProjectTests {
    static func main() {
        testRoundtripOneC4()
        testRootFourByteNames()
        testNameIsUtf8()
        testTruncatedFileFails()
        testBadRootFails()
        testRenameFirstDivisionWritesName()
        testTwoDivisionNamesRoundtrip()
        testRenameSelectedDivision()
        testDeleteSecondDivision()
        testDeleteFirstDivision()
        testRegenerateSecondDivision()
        testRegenerateCancelKeepsBoth()
        testRegenerateStartDefinition()
        testTransposeSecondDivisionUp()
        testReplacingSourceKeepsDivisions()
        testEmptyDropLeavesProject()
        print("BmhelperProjectTests passed")
    }

    /// 一条 C4、量化 480、默认聚类。写出再读回：音符、zz、div、名字一致。
    private static func testRoundtripOneC4() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        let project = BmhelperProjectFile.make(sourceNotes: notes, quantize: 480, setting: setting)
        let data = BmhelperProjectFile.encode(project)
        let loaded = try! BmhelperProjectFile.decode(data)
        require(loaded.source.quantize == 480, "source quantize")
        require(loaded.source.notes == notes, "source notes")
        require(loaded.divisions.count == 1, "one division")
        let division = loaded.divisions[0]
        require(division.name == "melody", "division name")
        require(division.zzEnabled, "zz enabled")
        require(division.definitions.count == 1, "one definition")
        require(division.definitions[0].zz == "01", "zz 01")
        require(division.definitions[0].div == 0, "div 0")
        require(division.midi.notes.count == 1, "division notes")
        require(division.midi.notes[0] == notes[0], "timeline note")
        require(division.src2def == [0], "src2def")
        require(division.source.notes == notes, "Srcd notes")
    }

    /// 根节点名是 `BMHP`，源 MIDI 列表名是 `Src `（末尾空格）。
    /// 名字和长度都按 4 字节小端写，对照 Windows 上 `unsigned long` 的宽度，也对照 RIFF。
    private static func testRootFourByteNames() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "kick", quantize: 480)
        let data = BmhelperProjectFile.encode(
            BmhelperProjectFile.make(sourceNotes: notes, quantize: 480, setting: setting)
        )
        require(data.count >= 16, "has header")
        require(ascii(data, 0, 4) == "BMHP", "root BMHP")
        let rootSize = int32(data, 4)
        require(rootSize > 0 && 8 + rootSize == data.count, "root size covers file")
        require(ascii(data, 8, 4) == "Src ", "source list")
    }

    /// 名字按 UTF-8 字节写。没有 Windows UTF-16 夹具，不声称能打开那种文件。
    private static func testNameIsUtf8() {
        let notes = [MidiNoteEvent(position: 480, gate: 240, noteNum: 64, velocity: 80)]
        var setting = BmhelperDivisionSetting.makeDefault(name: "鼓", quantize: 480)
        setting.zzDefinition = false
        let loaded = try! BmhelperProjectFile.decode(
            BmhelperProjectFile.encode(
                BmhelperProjectFile.make(sourceNotes: notes, quantize: 480, setting: setting)
            )
        )
        require(loaded.divisions[0].name == "鼓", "utf8 name")
        require(!loaded.divisions[0].zzEnabled, "zz flag")
    }

    /// 改名只动第一个 division 的 name；音符、zz、div 原样写回。
    private static func testRenameFirstDivisionWritesName() {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let setting = BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        let project = BmhelperProjectFile.make(sourceNotes: notes, quantize: 480, setting: setting)
        let renamed = project.renamingFirstDivision("kick")
        require(renamed != nil, "rename applies")
        let loaded = try! BmhelperProjectFile.decode(BmhelperProjectFile.encode(renamed!))
        require(loaded.divisions[0].name == "kick", "renamed first division")
        require(loaded.divisions[0].definitions[0].zz == "01", "zz unchanged")
        require(loaded.divisions[0].definitions[0].div == 0, "div unchanged")
        require(loaded.source.notes == notes, "notes unchanged")
        require(project.renamingFirstDivision(nil) == nil, "cancel keeps name")
        let untitled = project.renamingFirstDivision("")
        require(untitled?.divisions[0].name == "untitled", "empty becomes untitled")
    }

    /// 两个 division 写出再读回，名字顺序不变。
    private static func testTwoDivisionNamesRoundtrip() {
        let project = twoDivisionProject()
        let loaded = try! BmhelperProjectFile.decode(BmhelperProjectFile.encode(project))
        require(loaded.divisionNames == ["melody", "kick"], "two names")
        require(loaded.divisions.count == 2, "two divisions")
    }

    /// 选中下标 1 再改名：只改第二项。音符 / zz / div 不动。取消返回 nil。
    private static func testRenameSelectedDivision() {
        let project = twoDivisionProject()
        let renamed = project.renamingDivision(at: 1, "snare")
        require(renamed != nil, "rename applies")
        require(renamed!.divisions[0].name == "melody", "first stays melody")
        require(renamed!.divisions[1].name == "snare", "second is snare")
        require(renamed!.divisions[0].definitions[0].zz == project.divisions[0].definitions[0].zz, "zz 0")
        require(renamed!.divisions[1].definitions[0].zz == project.divisions[1].definitions[0].zz, "zz 1")
        require(renamed!.divisions[0].definitions[0].div == project.divisions[0].definitions[0].div, "div 0")
        require(renamed!.divisions[1].definitions[0].div == project.divisions[1].definitions[0].div, "div 1")
        require(renamed!.source.notes == project.source.notes, "notes unchanged")
        require(renamed!.divisions[0].midi.notes == project.divisions[0].midi.notes, "midi 0")
        require(renamed!.divisions[1].midi.notes == project.divisions[1].midi.notes, "midi 1")
        require(project.renamingDivision(at: 1, nil) == nil, "cancel keeps name")
    }

    /// 两个 division 删下标 1 再读回：只剩 melody。源音符仍在。取消不删。
    private static func testDeleteSecondDivision() {
        let project = twoDivisionProject()
        let notes = project.source.notes
        let deleted = project.deletingDivision(at: 1, true)
        require(deleted != nil, "delete applies")
        let loaded = try! BmhelperProjectFile.decode(BmhelperProjectFile.encode(deleted!))
        require(loaded.divisions.count == 1, "one left")
        require(loaded.divisions[0].name == "melody", "melody remains")
        require(loaded.source.notes == notes, "source notes remain")
        require(loaded.divisions[0].definitions[0].zz == project.divisions[0].definitions[0].zz, "zz 0")
        require(loaded.divisions[0].definitions[0].div == project.divisions[0].definitions[0].div, "div 0")
        require(loaded.divisions[0].midi.notes == project.divisions[0].midi.notes, "midi 0")
        require(project.deletingDivision(at: 1, nil) == nil, "nil keeps both")
        require(project.deletingDivision(at: 1, false) == nil, "false keeps both")
        require(project.divisions.count == 2, "original still two")
        require(project.divisions[0].name == "melody", "cancel first melody")
        require(project.divisions[1].name == "kick", "cancel second kick")
    }

    /// 两个 division 重聚下标 1，名字改成 snare：条数仍是 2。第一项仍是 melody。源音符不动。
    private static func testRegenerateSecondDivision() {
        let project = twoDivisionProject()
        let setting = BmhelperDivisionSetting.makeDefault(name: "snare", quantize: 480)
        let originalSource = project.divisions[1].source.notes
        let regenerated = project.regeneratingDivision(at: 1, setting)
        require(regenerated != nil, "regen applies")
        require(regenerated!.divisions.count == 2, "still two")
        require(regenerated!.divisions[0].name == "melody", "first stays melody")
        require(regenerated!.divisions[1].name == "snare", "second is snare")
        require(regenerated!.divisions[1].source.notes == originalSource, "source notes remain")
        require(project.divisions.count == 2, "original still two")
        require(project.divisions[1].name == "kick", "original second kick")
    }

    /// 取消（nil / false）返回 nil，两项都在。
    private static func testRegenerateCancelKeepsBoth() {
        let project = twoDivisionProject()
        let setting = BmhelperDivisionSetting.makeDefault(name: "snare", quantize: 480)
        require(project.regeneratingDivision(at: 1, nil) == nil, "nil keeps both")
        require(project.regeneratingDivision(at: 1, setting, confirmed: false) == nil, "false keeps both")
        require(project.regeneratingDivision(at: 1, setting, confirmed: nil) == nil, "confirmed nil keeps both")
        require(project.divisions.count == 2, "original still two")
        require(project.divisions[0].name == "melody", "cancel first melody")
        require(project.divisions[1].name == "kick", "cancel second kick")
    }

    /// 重聚下标 1 且 startDefinition = 2：第二项 zz 是 02，第一项 zz 不动。
    private static func testRegenerateStartDefinition() {
        let project = twoDivisionProject()
        var setting = BmhelperDivisionSetting.makeDefault(name: "kick", quantize: 480)
        setting.startDefinition = 2
        let regenerated = project.regeneratingDivision(at: 1, setting)
        require(regenerated != nil, "regen start applies")
        require(regenerated!.divisions[0].definitions[0].zz == project.divisions[0].definitions[0].zz, "zz 0")
        require(regenerated!.divisions[1].definitions[0].zz == "02", "zz 1 is 02")
        require(project.divisions[0].definitions[0].zz == "01", "original zz 0")
        require(project.divisions[1].definitions[0].zz == "01", "original zz 1")
    }

    /// 两个 division 选中 1 再 up：只有第二项 zz 减一。第一项、音符、div 不动。
    private static func testTransposeSecondDivisionUp() {
        let project = twoDivisionProject()
        let transposed = project.transposingDefinitions(at: 1, .up)
        require(transposed != nil, "transpose applies")
        require(transposed!.divisions.count == 2, "still two")
        require(transposed!.divisions[0].name == "melody", "first stays melody")
        require(transposed!.divisions[1].name == "kick", "second stays kick")
        require(transposed!.divisions[0].definitions[0].zz == "01", "first zz stays 01")
        require(transposed!.divisions[1].definitions[0].zz == "00", "second zz down to 00")
        require(transposed!.divisions[0].definitions[0].div == project.divisions[0].definitions[0].div, "div 0")
        require(transposed!.divisions[1].definitions[0].div == project.divisions[1].definitions[0].div, "div 1")
        require(transposed!.source.notes == project.source.notes, "source notes")
        require(transposed!.divisions[0].midi.notes == project.divisions[0].midi.notes, "midi 0")
        require(transposed!.divisions[1].midi.notes == project.divisions[1].midi.notes, "midi 1")
        require(transposed!.divisions[0].src2def == project.divisions[0].src2def, "src2def 0")
        require(transposed!.divisions[1].src2def == project.divisions[1].src2def, "src2def 1")
        require(project.transposingDefinitions(at: 1, nil) == nil, "cancel keeps both")
        require(project.divisions[1].definitions[0].zz == "01", "original zz 1")
    }

    /// 两个 division 换源成一条新 C4：源变了，名单和时间线原样，干净仍干净。
    private static func testReplacingSourceKeepsDivisions() {
        let project = twoDivisionProject()
        let oldTimeline0 = project.divisions[0].midi.notes
        let oldTimeline1 = project.divisions[1].midi.notes
        let newC4 = [MidiNoteEvent(position: 240, gate: 240, noteNum: 60, velocity: 80)]
        let (next, changed) = project.applyingDroppedFiles(
            ["song.mid"],
            source: BmhelperMidiBlob(quantize: 480, notes: newC4),
            changed: false
        )
        require(next.source.notes == newC4, "source notes replaced")
        require(next.source.quantize == 480, "source quantize")
        require(next.divisions.count == 2, "still two divisions")
        require(next.divisions[0].name == "melody", "first name stays")
        require(next.divisions[1].name == "kick", "second name stays")
        require(next.divisions[0].midi.notes == oldTimeline0, "timeline 0 stays")
        require(next.divisions[1].midi.notes == oldTimeline1, "timeline 1 stays")
        require(changed == false, "clean stays clean")
        require(project.source.notes != newC4, "original source untouched")
        require(project.divisions.count == 2, "original still two")
    }

    /// 空文件列表不改工程，也不改脏标记。
    private static func testEmptyDropLeavesProject() {
        let project = twoDivisionProject()
        let newC4 = [MidiNoteEvent(position: 240, gate: 240, noteNum: 60, velocity: 80)]
        let (next, changed) = project.applyingDroppedFiles(
            [],
            source: BmhelperMidiBlob(quantize: 480, notes: newC4),
            changed: false
        )
        require(next == project, "empty drop keeps project")
        require(changed == false, "empty drop keeps clean")
        require(next.source.notes == project.source.notes, "source unchanged")
        require(next.divisions.count == 2, "divisions unchanged")
    }

    /// 删下标 0 再读回：只剩 kick。
    private static func testDeleteFirstDivision() {
        let project = twoDivisionProject()
        let deleted = project.deletingDivision(at: 0, true)
        require(deleted != nil, "delete first applies")
        let loaded = try! BmhelperProjectFile.decode(BmhelperProjectFile.encode(deleted!))
        require(loaded.divisions.count == 1, "one left after first")
        require(loaded.divisions[0].name == "kick", "kick remains")
        require(loaded.source.notes == project.source.notes, "source notes remain")
        require(loaded.divisions[0].definitions[0].zz == project.divisions[1].definitions[0].zz, "zz 1")
        require(loaded.divisions[0].definitions[0].div == project.divisions[1].definitions[0].div, "div 1")
        require(loaded.divisions[0].midi.notes == project.divisions[1].midi.notes, "midi 1")
    }

    private static func twoDivisionProject() -> BmhelperProject {
        let notes = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let melody = BmhelperProjectFile.make(
            sourceNotes: notes,
            quantize: 480,
            setting: BmhelperDivisionSetting.makeDefault(name: "melody", quantize: 480)
        )
        let kick = BmhelperProjectFile.make(
            sourceNotes: notes,
            quantize: 480,
            setting: BmhelperDivisionSetting.makeDefault(name: "kick", quantize: 480)
        )
        return BmhelperProject(source: melody.source, divisions: melody.divisions + kick.divisions)
    }

    private static func testTruncatedFileFails() {
        do {
            _ = try BmhelperProjectFile.decode(Data([0x42, 0x4D, 0x48]))
            require(false, "truncated should fail")
        } catch is BmhelperTreeError {
            return
        } catch {
            require(false, "unexpected error")
        }
    }

    private static func testBadRootFails() {
        var data = Data()
        data.append(contentsOf: Array("XXXX".utf8))
        data.append(contentsOf: [0, 0, 0, 0])
        do {
            _ = try BmhelperProjectFile.decode(data)
            require(false, "bad root should fail")
        } catch BmhelperTreeError.badRoot {
            return
        } catch {
            require(false, "unexpected error")
        }
    }

    private static func ascii(_ data: Data, _ offset: Int, _ count: Int) -> String {
        String(bytes: data[offset..<(offset + count)], encoding: .ascii) ?? ""
    }

    private static func int32(_ data: Data, _ offset: Int) -> Int {
        Int(Int32(bitPattern:
            UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        ))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
