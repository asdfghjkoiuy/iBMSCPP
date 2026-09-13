import Foundation

@main
struct LegacyImportTests {
    static func main() {
        testLayouts()
        testSMParse()
        testIBMSCRoundTrip()
        testIBMSCUndo()
        testMyO2()
        print("LegacyImportTests passed")
    }

    private static func testLayouts() {
        require(ImportSMLayout.clientSize == CGSize(width: 210, height: 203), "Import SM client size")
        require(ImportSMLayout.ok == CGRect(x: 55, y: 165, width: 67, height: 23), "Import SM OK")
        require(ImportSMLayout.cancel == CGRect(x: 128, y: 165, width: 67, height: 23), "Import SM Cancel")
        require(ImportSMLayout.list == CGRect(x: 15, y: 27, width: 183, height: 64), "Import SM list")
        require(MyO2Layout.clientSize == CGSize(width: 559, height: 552), "MyO2 client size")
        require(MyO2Layout.table == CGRect(x: 27, y: 82, width: 505, height: 448), "MyO2 table")
        require(MyO2Layout.applyConst == CGRect(x: 283, y: 21, width: 249, height: 25), "恒速化")
        require(MyO2Layout.columns.count == 9 && MyO2Layout.columns[6].editable, "AdjTo64 is the only editable column")
    }

    private static func testSMParse() {
        let text = """
        #TITLE:Song//comment
        ;
        #SUBTITLE:Mix;
        #ARTIST:Author;
        #GENRE:Game;
        #BPMS:0=140,4=160;
        #NOTES:dance-single:desc:Easy:4:0:2000,2000;
        #NOTES:dance-single:desc:Hard:8:0:0001;
        """
        let labels = LegacySMImport.difficulties(in: text)
        require(labels == ["Easy : 4", "Hard : 8"], "SM difficulty labels")
        let easy = LegacySMImport.parse(text, difficulty: 0, convertToNT: true)
        require(easy.title == "Song Mix", "subtitle is appended to title")
        require(easy.artist == "Author" && easy.genre == "Game", "SM metadata")
        require(easy.initialBPM == 1_400_000, "BPM at beat 0 becomes Notes(0)")
        require(easy.bpmEvents.count == 1 && easy.bpmEvents[0].vPosition == 192 && easy.bpmEvents[0].value == 1_600_000, "beat 4 * 48 = 192")
        require(easy.playLevel == "4", "meter becomes play level")
        require(easy.notes.count == 1 && easy.notes[0].columnIndex == EditorColumn.a1 && easy.notes[0].length == 192, "2/3 marks pair into an NT long note")
        let hard = LegacySMImport.parse(text, difficulty: 1, convertToNT: false)
        require(hard.notes.count == 1 && hard.notes[0].columnIndex == EditorColumn.a4 && hard.notes[0].vPosition == 0, "second chart uses A4")
        let grid = LegacySMImport.grid(from: 240)
        require(grid.measure == 1 && grid.slot == 48 && grid.division == 192, "240 vpos is measure 1 slot 48")
    }

    private static func testIBMSCRoundTrip() {
        let header = IBMSCHeader(title: "T", artist: "A", genre: "G", subtitle: "S", subartist: "SA", bpmValue: 1_300_000, playLevel: "5")
        let notes = [
            IBMSCNote(vPosition: 48, columnIndex: EditorColumn.a2, value: 10_000, longNote: false, length: 0, hidden: false, landmine: false)
        ]
        let data = LegacyIBMSC.writeSubset(header: header, notes: notes, ntInput: true, measureLengths: [0: 192])
        guard let parsed = LegacyIBMSC.parse(data) else {
            require(false, "IBMSC parse")
            return
        }
        require(parsed.magicOK && parsed.ntInput && parsed.slash == 192, "IBMSC magic, NTInput and default gSlash")
        require(
            parsed.divide == 16 && parsed.sub == 4 && parsed.height == 1 && parsed.width == 1 && parsed.bgmColumns == 0,
            "subset writes Designer gDivide 16 / gSub 4 / gxHeight 1 / gxWidth 1 and leaves CGB 0"
        )
        let gridded = LegacyIBMSC.writeSubset(
            header: header, notes: notes, ntInput: true,
            divide: 32, sub: 8, slash: 64, height: 1.25, width: 2, bgmColumns: 20,
            measureLengths: [0: 192]
        )
        guard let gridDoc = LegacyIBMSC.parse(gridded) else {
            require(false, "IBMSC grid-number parse")
            return
        }
        require(
            gridDoc.divide == 32 && gridDoc.sub == 8 && gridDoc.slash == 64
                && gridDoc.height == 1.25 && gridDoc.width == 2 && gridDoc.bgmColumns == 20,
            "ChartIO Pref stores CGDivide / CGSub / gSlash / gxHeight / gxWidth / CGB"
        )
        let slashed = LegacyIBMSC.writeSubset(
            header: header, notes: notes, ntInput: true, slash: 64, measureLengths: [0: 192]
        )
        guard let slashDoc = LegacyIBMSC.parse(slashed) else {
            require(false, "IBMSC slash parse")
            return
        }
        require(slashDoc.slash == 64, "IBMSC preferences store gSlash after gSub")
        require(parsed.snap && !parsed.disableVerticalMove,
                "default SaveIBMSC writes gSnap and leaves DisableVerticalMove off")
        require(LegacyIBMSC.packPreferences(ntInput: true, snap: true, disableVerticalMove: true)
                    == Int32(0x1 | 0x1000000 | 0x2000000),
                "pref packs NTInput, gSnap, DisableVerticalMove")
        let locked = LegacyIBMSC.writeSubset(
            header: header, notes: notes, ntInput: true, snap: false, disableVerticalMove: true,
            measureLengths: [0: 192]
        )
        guard let lockedDoc = LegacyIBMSC.parse(locked) else {
            require(false, "IBMSC snap/vertical parse")
            return
        }
        require(!lockedDoc.snap && lockedDoc.disableVerticalMove && lockedDoc.ntInput,
                "pref 0x2000000 is DisableVerticalMove; 0x1000000 is gSnap")
        require(!parsed.showFileName, "default SaveIBMSC leaves ShowFileName off")
        require(LegacyIBMSC.packPreferences(
            ntInput: true, snap: false, disableVerticalMove: false, showFileName: true
        ) == Int32(0x1 | 0x8), "pref 0x8 is ShowFileName")
        let named = LegacyIBMSC.writeSubset(
            header: header, notes: notes, ntInput: true, showFileName: true, measureLengths: [0: 192]
        )
        guard let namedDoc = LegacyIBMSC.parse(named) else {
            require(false, "IBMSC ShowFileName parse")
            return
        }
        require(namedDoc.showFileName && namedDoc.snap, "ShowFileName bit survives a round trip")
        require(!parsed.showLeftSplitter && !parsed.lockMiddleScroll,
                "default SaveIBMSC leaves splitters and panel locks off")
        require(
            LegacyIBMSC.packPreferences(
                ntInput: true, snap: true, disableVerticalMove: false,
                showLeftSplitter: true, lockMiddleScroll: true
            ) == Int32(0x1 | 0x1000 | 0x1000000 | 0x8000000),
            "pref 0x1000 is Left Splitter; 0x8000000 is lock mid"
        )
        let panels = LegacyIBMSC.writeSubset(
            header: header, notes: notes, ntInput: true,
            showLeftSplitter: true, showRightSplitter: true,
            lockLeftScroll: true, lockMiddleScroll: true, lockRightScroll: true,
            measureLengths: [0: 192]
        )
        guard let panelDoc = LegacyIBMSC.parse(panels) else {
            require(false, "IBMSC panel lock parse")
            return
        }
        require(
            panelDoc.showLeftSplitter && panelDoc.showRightSplitter
                && panelDoc.lockLeftScroll && panelDoc.lockMiddleScroll && panelDoc.lockRightScroll,
            "splitter and lock bits survive a round trip"
        )
        require(!parsed.errorCheck && !parsed.previewOnClick && !parsed.showGrid,
                "subset write leaves ErrorCheck / PreviewOnClick / Grid off unless packed")
        let packedGuides = LegacyIBMSC.packPreferences(
            ntInput: true, snap: true, disableVerticalMove: false,
            errorCheck: true, previewOnClick: true,
            showToolbar: true, showOptionsPanel: true, showStatusBar: true,
            showGrid: true, showSubGrid: true, showBackground: true,
            showMeasureNumber: true, showMeasureBar: true,
            showVerticalLine: true, showColumnCaption: true,
            showBPMColumn: true, showStopColumn: true,
            showBGAColumns: true, showScrollColumn: true
        )
        var expectedGuides: Int32 = 0x1
        expectedGuides |= 0x2
        expectedGuides |= 0x4
        expectedGuides |= 0x200
        expectedGuides |= 0x400
        expectedGuides |= 0x800
        expectedGuides |= 0x4000
        expectedGuides |= 0x8000
        expectedGuides |= 0x10000
        expectedGuides |= 0x20000
        expectedGuides |= 0x40000
        expectedGuides |= 0x80000
        expectedGuides |= 0x100000
        expectedGuides |= 0x200000
        expectedGuides |= 0x400000
        expectedGuides |= 0x800000
        expectedGuides |= 0x1000000
        expectedGuides |= 0x20000000
        require(packedGuides == expectedGuides, "ChartIO pref packs ErrorCheck, PreviewOnClick, chrome, grid, columns")
        let guides = LegacyIBMSC.writeSubset(
            header: header, notes: notes, ntInput: true,
            errorCheck: true, previewOnClick: true,
            showToolbar: true, showOptionsPanel: true, showStatusBar: true,
            showGrid: true, showSubGrid: true, showBackground: false,
            showMeasureNumber: true, showMeasureBar: true,
            showVerticalLine: false, showColumnCaption: true,
            showBPMColumn: true, showStopColumn: true,
            showBGAColumns: true, showScrollColumn: true,
            measureLengths: [0: 192]
        )
        guard let guideDoc = LegacyIBMSC.parse(guides) else {
            require(false, "IBMSC view-guide parse")
            return
        }
        require(
            guideDoc.errorCheck && guideDoc.previewOnClick
                && guideDoc.showToolbar && guideDoc.showOptionsPanel && guideDoc.showStatusBar
                && guideDoc.showGrid && guideDoc.showSubGrid && !guideDoc.showBackground
                && guideDoc.showMeasureNumber && guideDoc.showMeasureBar
                && !guideDoc.showVerticalLine && guideDoc.showColumnCaption
                && guideDoc.showBPMColumn && guideDoc.showStopColumn
                && guideDoc.showBGAColumns && guideDoc.showScrollColumn,
            "view-guide bits survive a round trip"
        )
        require(parsed.header.title == "T" && parsed.header.artist == "A" && parsed.header.bpmValue == 1_300_000 && parsed.header.playLevel == "5", "IBMSC header")
        require(LegacyIBMSC.packPlayerRank(playerIndex: 1, rankIndex: 3) == 0x31, "Couple Play | Easy << 4")
        require(LegacyIBMSC.playerIndex(from: 0x31) == 1 && LegacyIBMSC.rankIndex(from: 0x31) == 3, "unpack Player/Rank")
        var full = header
        full.playerRank = 0x31
        full.stageFile = "stage.png"
        full.banner = "bn.png"
        full.backBMP = "back.bmp"
        full.difficulty = 3
        full.exRank = "80"
        full.total = "300"
        full.comment = "hi"
        full.lnObjIndex = 1
        let headed = LegacyIBMSC.writeSubset(header: full, notes: notes, ntInput: true, measureLengths: [0: 192])
        guard let restored = LegacyIBMSC.parse(headed) else {
            require(false, "IBMSC extra header parse")
            return
        }
        require(restored.header.playerRank == 0x31, "Player/Rank packed byte")
        require(restored.header.stageFile == "stage.png" && restored.header.banner == "bn.png" && restored.header.backBMP == "back.bmp", "Stage File / Banner / Back BMP")
        require(restored.header.difficulty == 3 && restored.header.exRank == "80" && restored.header.total == "300", "Difficulty / ExRank / Total")
        require(restored.header.comment == "hi" && restored.header.lnObjIndex == 1, "Comment and LnObj SelectedIndex")
        require(parsed.notes.count == 1 && parsed.notes[0].vPosition == 48 && parsed.notes[0].columnIndex == EditorColumn.a2, "IBMSC note")
        require(parsed.expansion.isEmpty, "subset without expansion text still parses")
        let withExpansion = LegacyIBMSC.writeSubset(
            header: header,
            notes: notes,
            ntInput: true,
            measureLengths: [0: 192],
            expansion: "#FOO bar\r\n#RANDOM 2"
        )
        guard let expanded = LegacyIBMSC.parse(withExpansion) else {
            require(false, "IBMSC expansion parse")
            return
        }
        require(expanded.expansion == "#FOO bar\r\n#RANDOM 2", "Expn block is TExpansion.Text")
        require(expanded.notes.count == 1 && expanded.notes[0].columnIndex == EditorColumn.a2, "notes still follow Expn")
        let withLists = LegacyIBMSC.writeSubset(
            header: header,
            notes: notes,
            ntInput: true,
            measureLengths: [0: 192],
            expansion: "",
            wavs: [1: "kick.wav", 36: "snare.ogg"],
            bmps: [2: "bg.bmp"],
            wavOptions: 1
        )
        guard let listed = LegacyIBMSC.parse(withLists) else {
            require(false, "IBMSC WAV/BMP parse")
            return
        }
        require(listed.wavOptions == 1, "WAV options byte keeps MultiSelect")
        require(listed.wavs[1] == "kick.wav" && listed.wavs[36] == "snare.ogg", "WAV list is index plus .NET string")
        require(listed.bmps[2] == "bg.bmp", "BMP list is index plus .NET string")
        require(listed.wavs[2] == nil && listed.bmps[1] == nil, "empty slots are omitted")
        let expnID = Data([0x45, 0x78, 0x70, 0x6E])
        require(data.range(of: expnID) != nil, "SaveIBMSC always writes the Expn block")
        require(data.range(of: Data([0x57, 0x41, 0x56, 0x00])) != nil, "SaveIBMSC always writes the WAV block")
        require(data.range(of: Data([0x42, 0x4D, 0x50, 0x00])) != nil, "SaveIBMSC always writes the BMP block")
        require(LegacyIBMSC.parse(Data([0, 1, 2, 3])) == nil, "bad magic is rejected")
        let grid = LegacyIBMSC.grid(from: 240, measureLengths: [:])
        require(grid.measure == 1 && grid.slot == 48, "IBMSC grid uses 192-length measures by default")
        let halfMeasure = LegacyIBMSC.grid(from: 96, measureLengths: [0: 96])
        require(halfMeasure.measure == 1 && halfMeasure.slot == 0,
                "vpos 96 after a 96-length measure is the start of measure 1")
        let stretched = LegacyIBMSC.grid(from: 192, measureLengths: [0: 96])
        require(stretched.measure == 1 && stretched.slot == 96,
                "vpos 192 after a 96-length measure is slot 96 of measure 1")
        require(data.range(of: Data([0x55, 0x6E, 0x64, 0x6F])) != nil, "SaveIBMSC always writes the Undo block")
    }

    private static func testIBMSCUndo() {
        require(IBMSCUndoHistory.slotCount == 100, "sUndo(99) is 100 slots")
        require(IBMSCUndoHistory.cleared.nextPointer == 1, "sIA from 0")
        require(IBMSCUndoHistory.cleared.previousPointer == 99, "sIM from 0")
        var wrap = IBMSCUndoHistory.cleared
        wrap.pointer = 99
        require(wrap.nextPointer == 0 && wrap.previousPointer == 98, "ring wraps at 99")
        require(!IBMSCUndoHistory.cleared.canUndo && !IBMSCUndoHistory.cleared.canRedo, "ClearUndo leaves NoOperation")

        let note = IBMSCNote(
            vPosition: 48, columnIndex: EditorColumn.a2, value: 10_000,
            longNote: false, length: 0, hidden: false, landmine: false
        )
        var history = IBMSCUndoHistory.cleared
        history.add(undo: [.removeNote(note)], redo: [.addNote(note)])
        require(history.pointer == 1 && history.canUndo && !history.canRedo, "AddUndo after a write")

        var notes = [note]
        require(history.undo(notes: &notes, ntInput: true), "TBUndo runs sUndo(sI)")
        require(notes.isEmpty && history.pointer == 0 && history.canRedo, "RemoveNote undoes the add")
        require(history.redo(notes: &notes, ntInput: true), "TBRedo runs sRedo(sIA)")
        require(notes == [note] && history.pointer == 1 && history.canUndo, "AddNote redoes the write")

        let encoded = IBMSCUndoCommand.removeNote(note).toBytes()
        require(encoded.first == IBMSCUndoOp.removeNote.rawValue, "opRemoveNote is 2")
        require(encoded.count == 32, "type byte plus Note.WriteBinWriter 31 bytes")
        require(IBMSCUndoCommand.fromBytes(encoded) == .removeNote(note), "fromBytes reads the note fields")

        let header = IBMSCHeader(
            title: "T", artist: "A", genre: "G", subtitle: "S", subartist: "SA",
            bpmValue: 1_200_000, playLevel: "1"
        )
        let data = LegacyIBMSC.writeSubset(
            header: header, notes: [note], ntInput: true, measureLengths: [0: 192], undo: history
        )
        guard let parsed = LegacyIBMSC.parse(data) else {
            require(false, "IBMSC undo parse")
            return
        }
        require(parsed.undo.pointer == 1, "sI is written after the slot count")
        require(parsed.undo.slots[1].undo == [.removeNote(note)], "slot undo list")
        require(parsed.undo.slots[1].redo == [.addNote(note)], "slot redo list")
        require(parsed.undo.slots[2].undo == [.noOperation], "AddUndo writes NoOperation at sIA")
        var restored = parsed.notes
        var parsedHistory = parsed.undo
        require(parsedHistory.undo(notes: &restored, ntInput: true) && restored.isEmpty, "imported Undo removes the note")
    }

    private static func testMyO2() {
        require(abs(LegacyMyO2.gcd(192, 48, limit: 1) - 48) < 0.000_001, "GCD(192, 48)")
        require(LegacyMyO2.channel(for: MyO2Note(vPosition: 0, columnIndex: EditorColumn.a1, value: 10_000, longNote: false, length: 0, hidden: false)) == "16", "A1 short channel")
        require(LegacyMyO2.channel(for: MyO2Note(vPosition: 0, columnIndex: EditorColumn.a1, value: 10_000, longNote: true, length: 0, hidden: false)) == "56", "A1 long channel")
        require(LegacyMyO2.isChannelLongNote("56") && !LegacyMyO2.isChannelLongNote("16"), "long-note channel range")
        let header = MyO2Note(vPosition: -1, columnIndex: EditorColumn.bpm, value: 1_200_000, longNote: false, length: 0, hidden: false)
        let note = MyO2Note(vPosition: 192, columnIndex: EditorColumn.a2, value: 10_000, longNote: false, length: 0, hidden: false)
        let doubled = LegacyMyO2.constBPM([header, note], target: 2_400_000, ntInput: true)
        require(doubled.count == 2 && doubled[0].value == 2_400_000 && abs(doubled[1].vPosition - 384) < 0.000_001, "doubling BPM doubles vpos")
        let offGrid = MyO2Note(vPosition: 1, columnIndex: EditorColumn.a2, value: 10_000, longNote: false, length: 0, hidden: false)
        let checks = LegacyMyO2.gridCheck([header, offGrid], ntInput: true, gridLimit: 1)
        require(checks.count == 1 && checks[0].columnIndex == EditorColumn.a2 && checks[0].grid == "192", "1-tick note reports 192-grid")
        require(checks[0].serialized.contains("_-1_") || checks[0].longNote == false, "CInt(False) serializes as 0")
        let adjusted = LegacyMyO2.gridAdjust([header, offGrid], adjustments: checks, ntInput: true)
        require(abs(adjusted[1].vPosition - 0) < 0.000_001, "align-to-48 snaps 1 to 0")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
