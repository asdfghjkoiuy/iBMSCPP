import CoreGraphics
import Foundation

@main
struct BmhelperDefinitionTests {
    static func main() {
        testZzEncoding()
        testFormatWavLineFixture()
        testAssignFromDefaultStart()
        testEmptyNameUsesUntitled()
        testFormatDefinitionBlock()
        testIncrementInFf()
        testOneToOneFromNoteCount()
        testBlockFromNoteCount()
        testTranspose()
        print("BmhelperDefinitionTests passed")
    }

    private static func testZzEncoding() {
        require(ZZNumber(0).to_string() == "00", "0 → 00")
        require(ZZNumber(1).to_string() == "01", "default start 1 → 01")
        require(ZZNumber(9).to_string() == "09", "9 → 09")
        require(ZZNumber(10).to_string() == "0A", "10 → 0A uppercase")
        require(ZZNumber(15).to_string() == "0F", "15 → 0F")
        require(ZZNumber(16).to_string() == "0G", "16 → 0G")
        require(ZZNumber(35).to_string() == "0Z", "35 → 0Z")
        require(ZZNumber(36).to_string() == "10", "36 → 10")
        require(ZZNumber(1295).to_string() == "ZZ", "1295 → ZZ")
        require(BmhelperDefDialogLayout.defaultStartDefinition == 1, "start default 1")
        require(BmhelperDefDialogLayout.clientSize == CGSize(width: 400, height: 300), "def size unchanged")
    }

    private static func testFormatWavLineFixture() {
        require(
            BmhelperDefinitions.formatWavLine(zz: "01", name: "kick", div: 0, offset: 1)
                == "#WAV01 kick_001.wav\r\n",
            "kick fixture"
        )
    }

    private static func testAssignFromDefaultStart() {
        require(
            BmhelperDefinitions.assignDefinitions(start: 1, zzEnabled: true, count: 3)
                == ["01", "02", "03"],
            "start=1 zz count=3"
        )
        require(
            BmhelperDefinitions.assignDefinitions(
                start: BmhelperDefDialogLayout.defaultStartDefinition,
                zzEnabled: true,
                count: 1
            ) != ["00"],
            "default start is not 00"
        )
    }

    private static func testEmptyNameUsesUntitled() {
        require(
            BmhelperDefinitions.formatWavLine(zz: "01", name: "", div: 0, offset: 1)
                == "#WAV01 untitled_001.wav\r\n",
            "empty name → untitled"
        )
        require(
            BmhelperDefinitions.resolvedName("") == BmhelperDefDialogLayout.defaultName,
            "resolved untitled"
        )
    }

    private static func testFormatDefinitionBlock() {
        let block = BmhelperDefinitions.formatDefinitionBlock(
            name: "kick",
            offset: 1,
            zzStrings: ["01", "02"],
            divs: [0, 1]
        )
        require(block == "#WAV01 kick_001.wav\r\n#WAV02 kick_002.wav\r\n", "two-line block")
    }

    private static func testIncrementInFf() {
        require(
            BmhelperDefinitions.assignDefinitions(start: 15, zzEnabled: false, count: 3)
                == ["0F", "10", "11"],
            "FF increment 0F → 10, not 0G"
        )
        var ff = ZZNumber(low: 15, high: 15)
        require(ff.to_string() == "FF", "FF is (15,15)")
        require(ff.in_ff(), "FF is in_ff")
        ff.increment_in_ff()
        require(ff.to_string() == "00", "FF wraps to 00")
        var zz = ZZNumber(15)
        zz.increment()
        require(zz.to_string() == "0G", "zz increment 0F → 0G")
    }

    private static func testOneToOneFromNoteCount() {
        let assigned = BmhelperDefinitions.assignOneToOne(noteCount: 1)
        require(assigned.zzStrings == ["01"] && assigned.divs == [0], "one MIDI note → 01 / div 0")
        require(
            BmhelperDefinitions.formatDefinitionBlock(
                name: "",
                offset: 0,
                zzStrings: assigned.zzStrings,
                divs: assigned.divs
            ) == "#WAV01 untitled_000.wav\r\n",
            "one-to-one untitled line"
        )
    }

    private static func testBlockFromNoteCount() {
        require(
            BmhelperDefinitions.formatDefinitionBlock(fromNoteCount: 1, name: "melody")
                == "#WAV01 melody_000.wav\r\n",
            "one MIDI note → one WAV line"
        )
        require(
            BmhelperMainLayout.fileMenuTitle == "File (&F)"
                && BmhelperMainLayout.newMenuTitle == "New...",
            "File New titles"
        )
        require(BmhelperMainLayout.clientSize == CGSize(width: 1000, height: 700), "main redesigned size")
    }

    /// 对照 `division.cpp` 三个 transpose，以及 `common.h` 的 `--` / `decrement_in_ff`。
    private static func testTranspose() {
        var from01 = ZZNumber(1)
        from01.decrement()
        require(from01.to_string() == "00", "decrement 01 → 00")
        var from00 = ZZNumber(0)
        from00.decrement()
        require(from00.to_string() == "ZZ", "decrement 00 → ZZ")

        var from10 = ZZNumber()
        require(from10.from_string("10"), "parse 10")
        from10.decrement_in_ff()
        require(from10.to_string() == "0F", "decrement_in_ff 10 → 0F")
        var fromFf00 = ZZNumber(0)
        fromFf00.decrement_in_ff()
        require(fromFf00.to_string() == "FF", "decrement_in_ff 00 → FF")

        require(
            BmhelperTranspose.up(zzEnabled: true, zzStrings: ["01", "02"]) == ["00", "01"],
            "up zzOn 01,02"
        )
        require(
            BmhelperTranspose.up(zzEnabled: false, zzStrings: ["10"]) == ["0F"],
            "up zzOff 10"
        )
        require(
            BmhelperTranspose.down(zzEnabled: true, zzStrings: ["01"]) == ["02"],
            "down zzOn 01"
        )
        require(
            BmhelperTranspose.down(zzEnabled: true, zzStrings: ["ZZ"]) == ["00"],
            "down zzOn ZZ"
        )
        require(
            BmhelperTranspose.to(zzEnabled: true, zzStrings: ["01", "02"], nbegin: "10")
                == ["10", "11"],
            "to zzOn 01,02 → 10"
        )
        require(
            BmhelperTranspose.to(zzEnabled: false, zzStrings: ["01", "02"], nbegin: "10")
                == ["10", "11"],
            "to zzOff increment_in_ff"
        )
        require(
            BmhelperTranspose.to(zzEnabled: true, zzStrings: [], nbegin: "10") == [],
            "to empty unchanged"
        )
        require(BmhelperTranspose.accept("0A", zzEnabled: true) == "0A", "accept 0A zzOn")
        require(BmhelperTranspose.accept("0G", zzEnabled: false) == nil, "accept 0G zzOff")
        require(BmhelperTranspose.accept("A", zzEnabled: true) == nil, "accept A")
        require(BmhelperTranspose.accept("", zzEnabled: true) == nil, "accept empty")
        require(
            BmhelperTranspose.up(zzEnabled: true, zzStrings: []) == [],
            "up empty stays empty"
        )
        require(
            BmhelperTranspose.down(zzEnabled: true, zzStrings: []) == [],
            "down empty stays empty"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
