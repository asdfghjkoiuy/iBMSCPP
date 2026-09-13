import Foundation

@main
struct LegacyWavListTests {
    static func main() {
        testFileNameTakesLastComponent()
        testDisplayLineAlwaysHasColonSpace()
        testMoveUpSwapsAdjacentAndLeavesTopBlock()
        testMoveDownSwapsAdjacent()
        testAssignFillsSelectedThenEmptySlots()
        testRemoveClearsSelectedNames()
        testParseTableSplitsOnAnyNewline()
        testPrepareDroppedFiltersAndSorts()
        testDragPreviewJoinsFilterOrder()
        testStepIndexMatchesAddSubtract()
        testAutoincreaseMatchesWriteAndRemove()
        testRightClickMatchesDeselectOrRemove()
        print("LegacyWavListTests passed")
    }

    /// `GetFileName`：最后一段 `/` 或 `\` 后面的名字。
    private static func testFileNameTakesLastComponent() {
        require(LegacyWavList.fileName(fromPath: #"C:\songs\kick.wav"#) == "kick.wav", "backslash name")
        require(LegacyWavList.fileName(fromPath: "/Users/me/snare.ogg") == "snare.ogg", "slash name")
        require(LegacyWavList.fileName(fromPath: "hat.mp3") == "hat.mp3", "bare name")
    }

    /// `C10to36(i) & ": " & hWAV(i)`，空名字仍留下冒号和空格。
    private static func testDisplayLineAlwaysHasColonSpace() {
        require(LegacyWavList.displayLine(token: "01", name: "kick.wav") == "01: kick.wav", "named slot")
        require(LegacyWavList.displayLine(token: "02", name: "") == "02: ", "empty slot keeps ': '")
    }

    /// `BWAVUp`：02 上移和 01 对调；01 自己上移不动。
    private static func testMoveUpSwapsAdjacentAndLeavesTopBlock() {
        var names = LegacyWavList.emptyNames()
        names[0] = "a.wav"
        names[1] = "b.wav"
        let moved = LegacyWavList.moveUp(names: names, selected: [1])
        require(moved.names[0] == "b.wav" && moved.names[1] == "a.wav", "02 moves onto 01")
        require(moved.selected == [0], "selection follows the slot")
        require(moved.labelSwaps.elementsEqual([("01", "02")], by: ==), "Synchronize swaps 01 and 02")

        let stuck = LegacyWavList.moveUp(names: names, selected: [0])
        require(stuck.names == names && stuck.selected == [0] && stuck.labelSwaps.isEmpty, "01 stays")
    }

    /// `BWAVDown`：01 下移和 02 对调。
    private static func testMoveDownSwapsAdjacent() {
        var names = LegacyWavList.emptyNames()
        names[0] = "a.wav"
        names[1] = "b.wav"
        let moved = LegacyWavList.moveDown(names: names, selected: [0])
        require(moved.names[0] == "b.wav" && moved.names[1] == "a.wav", "01 moves onto 02")
        require(moved.selected == [1], "selection follows the slot")
        require(moved.labelSwaps.elementsEqual([("02", "01")], by: ==), "down remap matches BWAVDown")
    }

    /// `AddToPOWAV`：先填已选，多出来的文件落到后面空位。
    private static func testAssignFillsSelectedThenEmptySlots() {
        var names = LegacyWavList.emptyNames()
        names[0] = "old.wav"
        names[2] = "keep.wav"
        let assigned = LegacyWavList.assign(
            paths: ["/tmp/a.wav", "/tmp/b.ogg", #"D:\c.mp3"#],
            selected: [0],
            names: names
        )
        require(assigned.names[0] == "a.wav", "first path overwrites the selection")
        require(assigned.names[1] == "b.ogg", "second path takes the next empty slot")
        require(assigned.names[2] == "keep.wav", "occupied 03 is skipped")
        require(assigned.names[3] == "c.mp3", "third path takes the next empty after skip")
        require(assigned.selected == [0, 1, 3], "selection covers written slots")
    }

    /// `BWAVRemove`：已选名字清空，选择留下。
    private static func testRemoveClearsSelectedNames() {
        var names = LegacyWavList.emptyNames()
        names[0] = "a.wav"
        names[1] = "b.wav"
        let removed = LegacyWavList.remove(names: names, selected: [0])
        require(removed.names[0].isEmpty && removed.names[1] == "b.wav", "only the selection is cleared")
        require(removed.selected == [0], "selection stays")
    }

    /// `#WAVxx` 按换行拆行，不能把 `\r\n` 当成一行。
    private static func testParseTableSplitsOnAnyNewline() {
        let table = LegacyWavList.parseTable(from: "#WAV01 a.wav\r\n#WAV02 b.wav\n#WAV00 skip.wav\n")
        require(table["01"] == "a.wav" && table["02"] == "b.wav", "two definitions")
        require(table["00"] == nil, "WAV00 is not a list slot")
        let bmp = LegacyWavList.parseTable(from: "#BMP01 bg.png\r\n#BMP02 poor.bmp\n", directive: "BMP")
        require(bmp["01"] == "bg.png" && bmp["02"] == "poor.bmp", "BMP definitions")
    }

    /// `FilterFileBySupported` 只留扩展名在表里的文件，目录只看一层，再 `Array.Sort`。
    private static func testPrepareDroppedFiltersAndSorts() {
        let dropped = LegacyWavList.prepareDropped(
            paths: ["/tmp/b.wav", "/tmp/skip.txt", "/tmp/folder", "/tmp/a.ogg"],
            extensions: LegacyWavList.audioExtensions,
            fileExists: { $0 != "/tmp/missing.wav" },
            isDirectory: { $0 == "/tmp/folder" },
            filesInDirectory: { _ in ["/tmp/folder/c.mp3", "/tmp/folder/note.txt"] }
        )
        require(dropped == ["/tmp/a.ogg", "/tmp/b.wav", "/tmp/folder/c.mp3"], "filter then sort")
        require(
            LegacyWavList.prepareDropped(
                paths: ["/tmp/missing.wav"],
                extensions: LegacyWavList.audioExtensions,
                fileExists: { _ in false },
                isDirectory: { _ in false },
                filesInDirectory: { _ in [] }
            ).isEmpty,
            "missing files are skipped"
        )
    }

    /// `DrawDragAndDrop` 用 `Join(DDFileName, vbCrLf)`。DragEnter 只过滤、不排序。
    private static func testDragPreviewJoinsFilterOrder() {
        let filtered = LegacyWavList.filterDropped(
            paths: ["/tmp/b.wav", "/tmp/skip.txt", "/tmp/folder", "/tmp/a.ogg"],
            extensions: LegacyWavList.audioExtensions,
            fileExists: { $0 != "/tmp/missing.wav" },
            isDirectory: { $0 == "/tmp/folder" },
            filesInDirectory: { _ in ["/tmp/folder/c.mp3", "/tmp/folder/note.txt"] }
        )
        require(filtered == ["/tmp/b.wav", "/tmp/folder/c.mp3", "/tmp/a.ogg"], "DragEnter keeps encounter order")
        require(
            LegacyWavList.dragPreviewText(filtered) == "/tmp/b.wav\r\n/tmp/folder/c.mp3\r\n/tmp/a.ogg",
            "Join(DDFileName, vbCrLf)"
        )
        require(LegacyWavList.dragPreviewARGB == 0xC0FF_FFFF, "Color.FromArgb(&HC0FFFFFF)")
        require(LegacyWavList.dragPreviewText([]).isEmpty, "empty DDFileName draws nothing")
    }

    /// `IncreaseCurrentWav` / `DecreaseCurrentWav`：没选中先落到 0，再夹在 0…Count-1。
    private static func testStepIndexMatchesAddSubtract() {
        require(LegacyWavList.stepIndex(selected: -1, count: 1295, delta: 1) == 0, "Add with no selection goes to 01")
        require(LegacyWavList.stepIndex(selected: -1, count: 1295, delta: -1) == 0, "Subtract with no selection goes to 01")
        require(LegacyWavList.stepIndex(selected: 0, count: 1295, delta: 1) == 1, "Add from 01 goes to 02")
        require(LegacyWavList.stepIndex(selected: 0, count: 1295, delta: -1) == 0, "Subtract at 01 stays")
        require(LegacyWavList.stepIndex(selected: 1294, count: 1295, delta: 1) == 1294, "Add at ZZ stays")
    }

    /// `TBWavIncrease`：写下后 `IncreaseCurrentWav`。`RemoveNote` 只在 `Value == SelectedIndex * 10000` 时减。
    private static func testAutoincreaseMatchesWriteAndRemove() {
        require(LegacyWavList.usesWavLabel("11") && LegacyWavList.usesWavLabel("01"),
                "playable and BGM writes use LWAV")
        require(!LegacyWavList.usesWavLabel("03") && !LegacyWavList.usesWavLabel("04"),
                "numeric and BGA columns do not autoincrease LWAV here")
        require(!LegacyWavList.shouldDecreaseAfterErase(enabled: false, selected: 1, token: "01"),
                "button off never steps backward")
        require(LegacyWavList.shouldDecreaseAfterErase(enabled: true, selected: 1, token: "01"),
                "after writing 01, SelectedIndex is 1 and Value is 10000")
        require(!LegacyWavList.shouldDecreaseAfterErase(enabled: true, selected: 0, token: "01"),
                "without autoincrease SelectedIndex stays 0")
        require(LegacyWavList.shouldDecreaseAfterErase(enabled: true, selected: 2, token: "02"),
                "after writing 02, SelectedIndex is 2")
    }

    /// `DeselectOrRemove`：`C10to36` 夹紧后再减 1；带 Control 不删。
    private static func testRightClickMatchesDeselectOrRemove() {
        require(LegacyWavList.rightClickWavSlot(valueDiv10000: 1) == 0, "label 01")
        require(LegacyWavList.rightClickWavSlot(valueDiv10000: 10) == 9, "label 0A")
        require(LegacyWavList.rightClickWavSlot(valueDiv10000: 1295) == 1294, "ZZ")
        require(LegacyWavList.rightClickWavSlot(valueDiv10000: 0) == 0, "C10to36 clamps <1 to 1")
        require(LegacyWavList.rightClickWavSlot(valueDiv10000: 1296) == 1294, "C10to36 clamps >1295")
        require(LegacyWavList.rightClickWavSlot(valueDiv10000: 140) == 139, "BPM 140 uses Value/10000")
        require(
            LegacyWavList.rightClickNoteAction(shift: false, control: false, hitNote: true) == .remove,
            "plain right click removes the hit note"
        )
        require(
            LegacyWavList.rightClickNoteAction(shift: true, control: false, hitNote: true) == .selectWav,
            "Shift right click selects WAV"
        )
        require(
            LegacyWavList.rightClickNoteAction(shift: false, control: false, hitNote: false) == .ignore,
            "miss does nothing"
        )
        require(
            LegacyWavList.rightClickNoteAction(shift: true, control: false, hitNote: false) == .ignore,
            "Shift miss does nothing"
        )
        require(
            LegacyWavList.rightClickNoteAction(shift: false, control: true, hitNote: true) == .ignore,
            "Control right click is not delete"
        )
        require(
            LegacyWavList.rightClickNoteAction(shift: true, control: true, hitNote: true) == .ignore,
            "Control+Shift right click is not delete"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
