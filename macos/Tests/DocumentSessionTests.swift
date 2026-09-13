import Darwin
import Foundation

@main
struct DocumentSessionTests {
    @MainActor
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func run() throws {
        let emptySession = try DocumentSession(data: Data())
        let emptyUndo = try emptySession.undo()
        let emptyRedo = try emptySession.redo()
        require(!emptyUndo && !emptyRedo, "Undo and redo must report false with no history.")

        let source = Data([
            0x23, 0x54, 0x49, 0x54, 0x4C, 0x45, 0x20, 0xB0, 0xA1, 0xB3, 0xAA, 0xB4, 0xD9, 0x0A,
            0x23, 0x57, 0x41, 0x56, 0x30, 0x31, 0x20, 0xB0, 0xE6, 0xB7, 0xCE, 0x2E, 0x77, 0x61, 0x76, 0x0A
        ])
        let session = try DocumentSession(data: source)
        require(session.availableEncodings.contains(.eucKR), "EUC-KR was not offered for Korean source bytes.")
        try session.selectMetadataEncoding(.eucKR)
        require(try session.metadataValue(for: "TITLE") == "가나다", "EUC-KR title did not decode correctly.")

        require(try session.replaceMetadata(" \t라마\t ", for: "TITLE") == "라마", "ASCII whitespace was not canonicalized.")
        require(session.dirty && session.canUndo, "Metadata edit did not create dirty undo state.")

        let unwritableDestination = FileManager.default.temporaryDirectory
        do {
            try session.save(to: unwritableDestination)
            throw TestFailure("Saving to a directory unexpectedly succeeded.")
        } catch is TestFailure {
            throw TestFailure("Saving to a directory unexpectedly succeeded.")
        } catch {
            require(session.dirty && session.fileURL == nil && session.canUndo,
                    "Failed save changed dirty state, URL, or history.")
        }

        require(try session.undo(), "Undo after failed save did not run.")
        require(!session.dirty && session.canRedo, "Undo did not restore clean state.")
        require(try session.redo(), "Redo did not restore edited metadata.")

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("ibmsnative-session-\(UUID().uuidString).bms")
        defer { try? FileManager.default.removeItem(at: output) }
        try session.save(to: output)
        let saved = try Data(contentsOf: output)
        require(!session.dirty && session.fileURL == output, "Successful save did not update clean state and URL.")
        require(saved.range(of: Data([0xB0, 0xE6, 0xB7, 0xCE, 0x2E, 0x77, 0x61, 0x76])) != nil,
                "Saving changed non-metadata EUC-KR resource bytes.")

        try testFullSourceEncodingChoice()
        try testAmbiguousASCIIEncodingSelection()
        try testUnsupportedRawSourceIsReadOnly()
        try testConditionalSourceSavesRawAndRejectsEdits()
        try testEncodingChangeAfterEditAndUndoIsRejected()
        try testUnrepresentableShiftJISEditPreservesBytesAndHistory()
        try testBOMRestrictsEncodingToUTF8()
        try testChartSnapshotAndSave()
        try testBGMColumnsAndHiddenConvert()
        try testMirrorAndModifyLabels()
        try testMoveToColumnAndBGM()
        try testFindReplaceExactFractionsAndScroll()
        try testLongNoteSessionPipeline()
        try testTimingSnapshotUsesCoreExactValues()
        try testExtraHeaderKeys()
        try testWavListBrowseRemoveAndMoveUp()
        try testBmpListBrowseRemoveAndMoveUp()
        try testRewriteChartKeepsHeadersAndOneUndo()
        try testRewriteChartUsesMeasureRatios()
        try testSaveBmsReportOverlapAndGridLimit()
        try testCompoundRollbackRestoresSnapshots()
    }

    @MainActor
    private static func testCompoundRollbackRestoresSnapshots() throws {
        let session = try DocumentSession(data: Data("#TITLE:before\n".utf8))
        let bytes = try session.currentBytes()
        let chart = session.chartSnapshot
        let longs = session.longNoteSnapshot
        let timing = session.timingSnapshot
        let dirty = session.dirty
        let undo = session.canUndo
        let redo = session.canRedo
        do {
            try session.withCompound {
                try session.insertNote(measure: 0, channel: "11", gridSlot: 0, gridDivision: 16, token: "01")
                throw TestFailure("forced compound failure")
            }
            throw TestFailure("compound unexpectedly succeeded")
        } catch is TestFailure { }
        require(try session.currentBytes() == bytes, "compound rollback changed bytes")
        require(session.chartSnapshot == chart && session.longNoteSnapshot == longs && session.timingSnapshot == timing,
                "compound rollback changed snapshots")
        require(session.dirty == dirty && session.canUndo == undo && session.canRedo == redo,
                "compound rollback changed history or dirty state")
    }

    @MainActor
    private static func testExtraHeaderKeys() throws {
        require(DocumentSession.storageKey("EXRANK") == "DEFEXRANK", "ExRank writes DEFEXRANK")
        require(DocumentSession.storageKey("PLAYER") == "PLAYER", "PLAYER keeps its own key")
        let session = try DocumentSession(data: Data("#TITLE Song\n".utf8))
        require(try session.replaceMetadata("2", for: "PLAYER") == "2", "PLAYER stores 2")
        require(try session.replaceMetadata("12", for: "PLAYLEVEL") == "12", "PLAYLEVEL stores 12")
        require(try session.replaceMetadata("stage.png", for: "STAGEFILE") == "stage.png", "STAGEFILE stores the file name")
        require(try session.replaceMetadata("80", for: "EXRANK") == "80", "EXRANK stores 80")
        require(try session.replaceMetadata("ZZ", for: "LNOBJ") == "ZZ", "LNOBJ stores ZZ")
        require(try session.replaceMetadata("hello", for: "COMMENT") == "hello", "COMMENT stores unquoted text")
        let text = String(data: try session.currentBytes(), encoding: .utf8) ?? ""
        require(text.contains("#PLAYER 2"), "PLAYER is written as #PLAYER")
        require(text.contains("#LNOBJ ZZ"), "LNOBJ is written as #LNOBJ")
        require(text.contains("#COMMENT \"hello\""), "COMMENT is written with quotes")
        require(text.contains("#PLAYLEVEL 12"), "PLAYLEVEL is written as #PLAYLEVEL")
        require(text.contains("#STAGEFILE stage.png"), "STAGEFILE is written as #STAGEFILE")
        require(text.contains("#DEFEXRANK 80"), "EXRANK is written as #DEFEXRANK")
        require(!text.contains("#EXRANK "), "do not write a #EXRANK line")
        _ = try session.replaceMetadata("", for: "STAGEFILE")
        require(!(String(data: try session.currentBytes(), encoding: .utf8) ?? "").contains("#STAGEFILE"),
                "empty STAGEFILE removes the line")
    }

    @MainActor
    private static func testFullSourceEncodingChoice() throws {
        let source = makeShiftJISSource(titleBytes: Array("ASCII TITLE".utf8))
        let session = try DocumentSession(data: source)

        require(session.availableEncodings.contains(.shiftJIS),
                "A source with Shift-JIS resource bytes must offer Shift JIS.")
        require(!session.availableEncodings.contains(.utf8),
                "A source with actual Shift-JIS resource bytes must not offer UTF-8.")
        try session.selectMetadataEncoding(.shiftJIS)
        require(try session.metadataValue(for: "TITLE") == "ASCII TITLE",
                "Explicit Shift-JIS selection did not decode the ASCII title.")
    }

    @MainActor
    private static func testBOMRestrictsEncodingToUTF8() throws {
        var source = Data([0xEF, 0xBB, 0xBF])
        source.append(contentsOf: Array("#TITLE BOM UTF-8\n#ARTIST 示例\n".utf8))
        let session = try DocumentSession(data: source)

        let offered = session.availableEncodings.map(\.rawValue).joined(separator: ", ")
        require(session.availableEncodings == [.utf8],
                "A UTF-8 BOM must restrict the encoding choices to UTF-8; offered: [\(offered)].")
        require(!session.encodingSelectionIsAmbiguous,
                "A UTF-8 BOM must remove encoding ambiguity.")
        try session.selectMetadataEncoding(.utf8)
        require(session.metadataEncoding == .utf8 && !session.dirty && !session.canUndo && !session.canRedo,
                "Explicit UTF-8 selection for a BOM source must succeed without creating history.")
        requireThrows({ try session.selectMetadataEncoding(.shiftJIS) }, matches: { error in
            if case DocumentSessionError.unsupportedMetadataEncoding = error { return true }
            return false
        }, message: "Selecting Shift JIS for a UTF-8 BOM source must be rejected.")

        let originalSaved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(originalSaved.contains("#TITLE BOM UTF-8") && originalSaved.contains("#ARTIST 示例")
                    && originalSaved.contains("*---------------------- HEADER FIELD"),
                "File Save rewrites through SaveBMS and keeps the title and artist.")

        _ = try session.replaceMetadata("BOM changed", for: "TITLE")
        let changedSaved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(changedSaved.contains("#TITLE BOM changed") && changedSaved.contains("#ARTIST 示例"),
                "SaveBMS writes the new title and keeps the artist.")
    }

    @MainActor
    private static func testAmbiguousASCIIEncodingSelection() throws {
        let source = Data("#TITLE ASCII\n#ARTIST Synthetic\n#WAV01 tone.wav\n".utf8)
        let session = try DocumentSession(data: source)

        require(session.availableEncodings.count > 1,
                "An ASCII-only source must expose an ambiguous encoding choice.")
        require(session.encodingSelectionIsAmbiguous,
                "An ASCII-only source must report ambiguous encoding selection.")
        try session.selectMetadataEncoding(.shiftJIS)
        require(session.metadataEncoding == .shiftJIS,
                "An explicit Shift-JIS choice was not retained.")
        require(try session.metadataValue(for: "TITLE") == "ASCII",
                "The explicitly selected encoding did not read the ASCII title.")
    }

    @MainActor
    private static func testUnsupportedRawSourceIsReadOnly() throws {
        var source = Data("#TITLE ".utf8)
        source.append(0xFF)
        source.append(contentsOf: Array("\n#WAV01 ".utf8))
        source.append(0xFE)
        source.append(contentsOf: Array(".wav\n".utf8))
        let session = try DocumentSession(data: source)

        require(session.availableEncodings.isEmpty,
                "A source unsupported by every display encoding must offer no encoding.")
        require(session.metadataEncoding == nil && !session.canEditMetadata,
                "An unsupported raw source must be read-only.")
        require(session.metadataEditingMessage != nil,
                "An unsupported raw source must expose a read-only explanation.")

        let saved = try saveAndRead(session)
        require(saved.range(of: Data([0xFF])) != nil && saved.range(of: Data([0xFE])) != nil,
                "SaveBMS keeps the raw TITLE and WAV bytes that no encoding can display.")
    }

    @MainActor
    private static func testConditionalSourceSavesRawAndRejectsEdits() throws {
        let source = Data("#RANDOM 2\n#IF 1\n#TITLE Inside\n#ENDIF\n#ENDRANDOM\n".utf8)
        let session = try DocumentSession(data: source)

        require(session.hasConditionals && !session.canEditMetadata,
                "Conditional source must be exposed as read-only metadata.")
        requireThrows({ _ = try session.replaceMetadata("Blocked", for: "TITLE") }, matches: { error in
            if case DocumentSessionError.conditionalDocument = error { return true }
            return false
        }, message: "Conditional metadata edits must be rejected explicitly.")
        require(!session.dirty && !session.canUndo && !session.canRedo,
                "A rejected conditional edit must not create history.")

        let saved = try saveAndRead(session)
        require(saved == source, "Saving a conditional source must preserve its raw bytes.")
    }

    @MainActor
    private static func testEncodingChangeAfterEditAndUndoIsRejected() throws {
        let source = Data("#TITLE ASCII\n#ARTIST Synthetic\n".utf8)
        let session = try DocumentSession(data: source)
        try session.selectMetadataEncoding(.shiftJIS)
        _ = try session.replaceMetadata("Edited", for: "TITLE")

        requireThrows({ try session.selectMetadataEncoding(.utf8) }, matches: { error in
            if case DocumentSessionError.encodingChangeWithHistory = error { return true }
            return false
        }, message: "Changing encoding after an edit must be rejected.")
        let editedTitle = try session.metadataValue(for: "TITLE")
        require(session.metadataEncoding == .shiftJIS
                    && editedTitle == "Edited"
                    && session.dirty && session.canUndo && !session.canRedo,
                "Rejected encoding change after edit must preserve content and history.")

        require(try session.undo(), "Undo before the second encoding-history check failed.")
        require(!session.dirty && !session.canUndo && session.canRedo,
                "Undo must preserve the redo history needed for the encoding guard.")
        requireThrows({ try session.selectMetadataEncoding(.utf8) }, matches: { error in
            if case DocumentSessionError.encodingChangeWithHistory = error { return true }
            return false
        }, message: "Changing encoding after undo with redo history must be rejected.")
        let undoneTitle = try session.metadataValue(for: "TITLE")
        require(session.metadataEncoding == .shiftJIS
                    && undoneTitle == "ASCII"
                    && !session.dirty && !session.canUndo && session.canRedo,
                "Rejected encoding change after undo must preserve content and history.")
    }

    @MainActor
    private static func testUnrepresentableShiftJISEditPreservesBytesAndHistory() throws {
        let titleBytes: [UInt8] = [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA]
        let source = makeShiftJISSource(titleBytes: titleBytes)
        let session = try DocumentSession(data: source)
        try session.selectMetadataEncoding(.shiftJIS)
        let originalTitle = try session.metadataValue(for: "TITLE")

        requireThrows({ _ = try session.replaceMetadata("😀", for: "TITLE") }, matches: { error in
            if case DocumentSessionError.unsupportedMetadataEncoding = error { return true }
            return false
        }, message: "An emoji that Shift JIS cannot represent must be rejected.")
        require(try session.metadataValue(for: "TITLE") == originalTitle
                    && !session.dirty && !session.canUndo && !session.canRedo,
                "An unrepresentable Shift-JIS edit must preserve content and history.")

        let saved = try saveAndRead(session)
        require(saved.range(of: Data(titleBytes)) != nil,
                "SaveBMS keeps the Shift-JIS title bytes after a rejected edit.")
    }

    @MainActor
    private static func testChartSnapshotAndSave() throws {
        let session = try DocumentSession(data: Data("#00016:0001\n#00102:.5\n".utf8))
        require(session.chartSnapshot.events.count == 1 && session.chartSnapshot.measures[1].length == 2,
                "The session did not expose the bridge chart snapshot.")
        try session.insertNote(measure: 1, channel: "16", gridSlot: 7, gridDivision: 16, token: "0A")
        require(session.chartSnapshot.events.count == 2 && session.dirty && session.canUndo,
                "A session note insertion did not update its cached snapshot and history.")
        let saved = try saveAndRead(session)
        require(String(decoding: saved, as: UTF8.self).contains("#00116:"),
                "Saving after a native note insertion did not serialize the core edit.")
        require(try session.undo(), "Undo after saving a native note insertion failed.")
        require(session.chartSnapshot.events.count == 1 && session.canRedo,
                "Undo did not replace the session's cached chart snapshot.")
    }

    @MainActor
    private static func testBGMColumnsAndHiddenConvert() throws {
        let session = try DocumentSession(data: Data("#TITLE One\n#00001:01\n#00001:02\n#00011:03\n".utf8))
        let bgm = session.chartSnapshot.events.filter { $0.kind == "bgm" }.sorted { $0.channel < $1.channel }
        require(bgm.count == 2 && bgm[0].channel == "B1" && bgm[1].channel == "B2",
                "each #01 row must appear as its own B column")
        try session.insertNote(measure: 0, channel: "B2", gridSlot: 8, gridDivision: 16, token: "04")
        require(session.chartSnapshot.events.contains { $0.channel == "B2" && $0.token == "04" },
                "B2 insert must merge into the second #01 row")
        try session.eraseNote(bgm[0])
        require(!session.chartSnapshot.events.contains { $0.channel == "B1" && $0.token == "01" },
                "erasing B1 must clear that cell")
        guard let visible = session.chartSnapshot.events.first(where: { $0.channel == "11" && $0.token == "03" }) else {
            throw TestFailure("The visible note used for convert is missing.")
        }
        try session.moveNote(visible, toChannel: "31")
        require(session.chartSnapshot.events.contains { $0.channel == "31" && $0.token == "03" },
                "→ Hidden must keep the same token and fraction")
        require(!session.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "03" },
                "→ Hidden must leave the visible cell")
        let bga = try DocumentSession(data: Data("#TITLE One\n".utf8))
        try bga.insertNote(measure: 0, channel: "04", gridSlot: 8, gridDivision: 16, token: "01")
        require(bga.chartSnapshot.events.contains { $0.channel == "04" && $0.token == "01" },
                "BGA insert must expose channel 04")
        try bga.insertTimingEvent(measure: 0, channel: "03", gridSlot: 0, gridDivision: 16, decimal: "140")
        require(bga.chartSnapshot.events.contains { $0.channel == "03" && $0.token == "8C" },
                "channel 03 BPM 140 is hex 8C")
        try bga.insertTimingEvent(measure: 0, channel: "08", gridSlot: 8, gridDivision: 16, decimal: "256")
        require(bga.chartSnapshot.events.contains { $0.channel == "08" },
                "BPM 256 uses extended channel 08")
        try bga.insertTimingEvent(measure: 1, channel: "SC", gridSlot: 0, gridDivision: 16, decimal: "0.5")
        require(bga.chartSnapshot.events.contains { $0.channel == "SC" && $0.kind == "scroll" },
                "SCROLL insert must expose channel SC")
        try bga.insertTimingEvent(measure: 1, channel: "SC", gridSlot: 8, gridDivision: 16, decimal: "-0.5")
        let savedScroll = String(decoding: try saveAndRead(bga), as: UTF8.self)
        require(savedScroll.contains("#SCROLL") && savedScroll.contains("-0.5"),
                "negative SCROLL must write #SCROLL with the minus sign")
    }

    @MainActor
    private static func testMoveToColumnAndBGM() throws {
        let keys = try DocumentSession(data: Data("#00011:01\n#00112:02\n#00031:03\n".utf8))
        guard let a2 = keys.chartSnapshot.events.first(where: { $0.channel == "11" }),
              let a3 = keys.chartSnapshot.events.first(where: { $0.channel == "12" }),
              let hidden = keys.chartSnapshot.events.first(where: { $0.channel == "31" }) else {
            throw TestFailure("MoveToColumn fixture is missing 11 / 12 / 31")
        }
        try keys.moveNotes(toDisplay: "13", events: [a2, a3], longNotes: [], shiftFirstOnly: false)
        require(keys.chartSnapshot.events.contains { $0.channel == "13" && $0.token == "01" }
                    && keys.chartSnapshot.events.contains { $0.channel == "13" && $0.token == "02" },
                "digit without Shift moves every selected short note")
        require(!keys.chartSnapshot.events.contains { $0.channel == "11" || $0.channel == "12" },
                "MoveToColumn leaves the source cells")
        try keys.moveNotes(toDisplay: "16", events: [hidden], longNotes: [], shiftFirstOnly: false)
        require(keys.chartSnapshot.events.contains { $0.channel == "36" && $0.token == "03" },
                "Hidden notes keep the 3x family")

        let shifted = try DocumentSession(data: Data("#00011:01\n#00012:02\n".utf8))
        guard let first = shifted.chartSnapshot.events.first(where: { $0.channel == "11" }),
              let second = shifted.chartSnapshot.events.first(where: { $0.channel == "12" }) else {
            throw TestFailure("Shift MoveToColumn fixture is missing")
        }
        try shifted.moveNotes(toDisplay: "15", events: [first, second], longNotes: [], shiftFirstOnly: true)
        require(shifted.chartSnapshot.events.contains { $0.channel == "15" && $0.token == "01" },
                "Shift+digit moves the first selected note")
        require(shifted.chartSnapshot.events.contains { $0.channel == "12" && $0.token == "02" },
                "Shift+digit leaves later selected notes")

        let longs = try DocumentSession(data: Data("#00051:01\n#00151:01\n".utf8))
        guard let hold = longs.longNoteSnapshot.notes.first else {
            throw TestFailure("MoveToColumn long fixture is missing")
        }
        try longs.moveNotes(toDisplay: "12", events: [], longNotes: [hold], shiftFirstOnly: false)
        require(longs.longNoteSnapshot.notes.contains { $0.channel == "52" },
                "NT longs keep the 5x family")

        let bgm = try DocumentSession(data: Data("#00011:01\n#00012:02\n".utf8))
        guard let key = bgm.chartSnapshot.events.first(where: { $0.channel == "11" }),
              let other = bgm.chartSnapshot.events.first(where: { $0.channel == "12" }) else {
            throw TestFailure("MoveToBGM fixture is missing")
        }
        try bgm.moveNotesToBGM(events: [key, other], longNotes: [], ntInput: true)
        require(bgm.chartSnapshot.events.contains { $0.channel == "B1" && $0.token == "01" },
                "first selected note goes to B1")
        require(bgm.chartSnapshot.events.contains { $0.channel == "B2" && $0.token == "02" },
                "the next selected note at the same time goes to B2")
        require(try bgm.undo(), "MoveToBGM is one undo")
        require(bgm.chartSnapshot.events.contains { $0.channel == "11" } && bgm.chartSnapshot.events.contains { $0.channel == "12" },
                "undo restores both key notes")
    }

    @MainActor
    private static func testMirrorAndModifyLabels() throws {
        let session = try DocumentSession(data: Data("#00011:01\n#00016:02\n#00031:03\n".utf8))
        guard let key = session.chartSnapshot.events.first(where: { $0.channel == "11" }),
              let scratch = session.chartSnapshot.events.first(where: { $0.channel == "16" }),
              let hidden = session.chartSnapshot.events.first(where: { $0.channel == "31" }) else {
            throw TestFailure("mirror fixture is missing 11 / 16 / 31")
        }
        try session.mirrorNotes([key, scratch, hidden])
        require(session.chartSnapshot.events.contains { $0.channel == "15" && $0.token == "01" },
                "A2 mirrors to A6 (11 → 15)")
        require(session.chartSnapshot.events.contains { $0.channel == "18" && $0.token == "02" },
                "A1 mirrors to A7 (16 → 18)")
        require(session.chartSnapshot.events.contains { $0.channel == "35" && $0.token == "03" },
                "hidden A2 mirrors to hidden A6 (31 → 35)")
        require(!session.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
                "the original 11 cell is gone")
        let labels = try DocumentSession(data: Data("#00011:01\n".utf8))
        guard let note = labels.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("modify-label fixture is missing 11")
        }
        try labels.modifyNoteLabels([note], label: "A")
        require(labels.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "0A" },
                "Modify Labels A writes token 0A")
        let timing = try DocumentSession(data: Data())
        try timing.insertTimingEvent(measure: 0, channel: "SC", gridSlot: 0, gridDivision: 16, decimal: "1")
        guard let scroll = timing.chartSnapshot.events.first(where: { $0.channel == "SC" }) else {
            throw TestFailure("modify-numeric fixture is missing SC")
        }
        try timing.modifyTimingValues([scroll], decimal: "0.5")
        let saved = String(decoding: try saveAndRead(timing), as: UTF8.self)
        require(saved.contains("0.5"), "Modify Labels numeric rewrite writes SCROLL 0.5")
    }

    @MainActor
    private static func testFindReplaceExactFractionsAndScroll() throws {
        let offGrid = try DocumentSession(data: Data("#00011:000001\n".utf8))
        guard let note = offGrid.chartSnapshot.events.first(where: { $0.channel == "11" && $0.token == "01" }) else {
            throw TestFailure("fdrReplaceL fixture is missing the 2/3 note.")
        }
        require(note.fractionNumerator == 2 && note.fractionDenominator == 3,
                "000001 places 01 at 2/3")
        try offGrid.replaceFindLabels(events: [note], longNotes: [], label: "02")
        require(offGrid.chartSnapshot.events.contains {
            $0.channel == "11" && $0.token == "02"
                && $0.fractionNumerator == 2 && $0.fractionDenominator == 3
        }, "fdrReplaceL keeps the exact 2/3 cell")

        let hold = try DocumentSession(data: Data("#00051:01\n#00151:000001\n".utf8))
        guard let longNote = hold.longNoteSnapshot.notes.first else {
            throw TestFailure("fdrReplaceL long-note fixture is missing the 51 pair.")
        }
        try hold.replaceFindLabels(events: [], longNotes: [longNote], label: "03")
        require(hold.longNoteSnapshot.notes.contains {
            $0.channel == "51" && $0.start.token == "03" && $0.end.token == "03"
                && $0.end.measure == 1 && $0.end.fractionNumerator == 2 && $0.end.fractionDenominator == 3
        }, "NT long replace keeps the off-grid tail")

        let scroll = try DocumentSession(data: Data("#SCROLL01 1\n#000SC:01\n".utf8))
        guard let event = scroll.chartSnapshot.events.first(where: { $0.channel == "SC" }) else {
            throw TestFailure("fdrReplaceV fixture is missing SC")
        }
        try scroll.replaceFindValues(timing: [], events: [event], decimal: "0.5")
        let saved = String(decoding: try saveAndRead(scroll), as: UTF8.self)
        require(saved.contains("0.5"), "fdrReplaceV writes SCROLL 0.5")
        require(scroll.chartSnapshot.events.contains { $0.channel == "SC" && $0.fractionNumerator == 0 },
                "SCROLL stays on the same cell")

        let two = try DocumentSession(data: Data("#00011:01\n#00012:01\n".utf8))
        try two.replaceFindLabels(
            events: two.chartSnapshot.events.filter { $0.token == "01" },
            longNotes: [],
            label: "02"
        )
        require(try two.undo(), "fdrReplaceL AddUndo is one command")
        require(two.chartSnapshot.events.filter { $0.token == "01" }.count == 2,
                "one undo restores both labels")
        require(!two.canUndo, "label replace is not several undo steps")
    }

    @MainActor
    private static func testWavListBrowseRemoveAndMoveUp() throws {
        let session = try DocumentSession(data: Data("#WAV01 a.wav\n#00011:02\n".utf8))
        var names = try session.wavNames()
        let assigned = LegacyWavList.assign(paths: ["/tmp/b.wav"], selected: [1], names: names)
        try session.applyWavEdit(assigned, synchronizeLabels: false)
        var saved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(saved.contains("#WAV02 b.wav"), "Browse writes the selected empty slot")
        names = try session.wavNames()
        let moved = LegacyWavList.moveUp(names: names, selected: [1])
        try session.applyWavEdit(moved, synchronizeLabels: true)
        saved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(saved.contains("#WAV01 b.wav") && saved.contains("#WAV02 a.wav"), "Up swaps definitions")
        require(
            session.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
            "Synchronize Note Labels remaps 02 to 01"
        )
        require(session.canUndo, "BWAVUp AddUndo is one command")
        require(try session.undo(), "one undo after Up")
        let afterUpUndo = String(decoding: try session.currentBytes(), as: UTF8.self)
        require(
            afterUpUndo.contains("#WAV01 a.wav") && afterUpUndo.contains("#WAV02 b.wav"),
            "one undo restores both WAV slots"
        )
        require(session.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "02" },
                "one undo restores the remapped note label")
        require(session.canUndo, "Browse remains a separate undo after Up")
        try session.redo()
        names = try session.wavNames()
        let removed = LegacyWavList.remove(names: names, selected: [1])
        try session.applyWavEdit(removed, synchronizeLabels: false)
        saved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(saved.contains("#WAV02") == false, "Remove deletes the #WAV line")
    }

    @MainActor
    private static func testBmpListBrowseRemoveAndMoveUp() throws {
        let session = try DocumentSession(data: Data("#BMP01 a.bmp\n#00004:02\n".utf8))
        var names = try session.bmpNames()
        let assigned = LegacyWavList.assign(paths: ["/tmp/b.png"], selected: [1], names: names)
        try session.applyBmpEdit(assigned, synchronizeLabels: false)
        var saved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(saved.contains("#BMP02 b.png"), "Browse writes the selected empty BMP slot")
        names = try session.bmpNames()
        let moved = LegacyWavList.moveUp(names: names, selected: [1])
        try session.applyBmpEdit(moved, synchronizeLabels: true)
        saved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(saved.contains("#BMP01 b.png") && saved.contains("#BMP02 a.bmp"), "Up swaps BMP definitions")
        require(
            session.chartSnapshot.events.contains { $0.channel == "04" && $0.token == "01" },
            "Synchronize Note Labels remaps BGA 02 to 01"
        )
        require(session.canUndo, "BBMPUp AddUndo is one command")
        require(try session.undo(), "one undo after BMP Up")
        let afterBmpUpUndo = String(decoding: try session.currentBytes(), as: UTF8.self)
        require(
            afterBmpUpUndo.contains("#BMP01 a.bmp") && afterBmpUpUndo.contains("#BMP02 b.png"),
            "one undo restores both BMP slots"
        )
        require(session.chartSnapshot.events.contains { $0.channel == "04" && $0.token == "02" },
                "one undo restores the remapped BGA label")
        require(session.canUndo, "Browse remains a separate undo after BMP Up")
        try session.redo()
        names = try session.bmpNames()
        let removed = LegacyWavList.remove(names: names, selected: [1])
        try session.applyBmpEdit(removed, synchronizeLabels: false)
        saved = String(decoding: try saveAndRead(session), as: UTF8.self)
        require(saved.contains("#BMP02") == false, "Remove deletes the #BMP line")
    }

    @MainActor
    private static func testRewriteChartKeepsHeadersAndOneUndo() throws {
        let session = try DocumentSession(
            data: Data("#TITLE Song\n#WAV01 a.wav\n#00011:01\n#00052:02\n#00152:02\n".utf8)
        )
        try session.rewriteChart {
            try session.insertNote(
                measure: 1,
                channel: "11",
                gridSlot: 0,
                gridDivision: 16,
                token: "01"
            )
        }
        let rewritten = String(decoding: try session.currentBytes(), as: UTF8.self)
        require(rewritten.contains("#TITLE Song") && rewritten.contains("#WAV01 a.wav"),
                "TimeSelection/MyO2 rewrite keeps headers")
        require(
            session.chartSnapshot.events.contains { $0.channel == "11" && $0.measure == 1 && $0.token == "01" },
            "rewrite puts the short note at the new vpos"
        )
        require(session.longNoteSnapshot.notes.isEmpty, "rewrite drops previous long notes")
        require(try session.undo(), "RedoRemoveNoteAll + RedoAddNoteAll is one AddUndo")
        let restored = String(decoding: try session.currentBytes(), as: UTF8.self)
        require(restored.contains("#TITLE Song") && restored.contains("#WAV01 a.wav"),
                "one undo still keeps headers")
        require(
            session.chartSnapshot.events.contains { $0.channel == "11" && $0.measure == 0 && $0.token == "01" },
            "one undo restores the short note"
        )
        require(
            session.longNoteSnapshot.notes.contains { $0.channel == "52" && $0.start.token == "02" },
            "one undo restores the long note"
        )
        require(!session.canUndo, "rewrite is not several undo steps")
    }

    @MainActor
    private static func testRewriteChartUsesMeasureRatios() throws {
        let source = Data("#TITLE Song\n#WAV01 a.wav\n#00002:0.5\n#00111:01\n".utf8)
        let session = try DocumentSession(data: source)
        require(session.timingSnapshot.ratio(for: 0) == "0.5", "measure 0 keeps #00002")
        guard let event = session.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("source note #00111:01 is missing")
        }
        require(event.measure == 1, "source note is measure 1")
        require(abs(event.beat - 2) < 0.000_001, "measure 0 is 2 beats")
        let vpos = event.beat * 48
        require(abs(vpos - 96) < 0.000_001, "start of measure 1 is vpos 96")
        let lengths = session.timingSnapshot.measureLengths()
        require(abs((lengths[0] ?? 0) - 96) < 0.000_001, "MeasureLength 0 is 96")
        let same = LegacyMeasureGrid.grid(from: vpos, measureLengths: lengths)
        require(same.measure == 1 && same.slot == 0, "vpos 96 stays in measure 1")
        let half = LegacyMeasureGrid.grid(from: 48, measureLengths: lengths)
        require(half.measure == 0 && half.slot == 96, "halfway in a half measure is slot 96")
        let expanded = LegacyMeasureGrid.grid(from: 192, measureLengths: lengths)
        require(expanded.measure == 1 && expanded.slot == 96, "expanded vpos 192 is measure 1 slot 96")
        require(Int(floor(96.0 / 192.0)) == 0, "192-grid would put vpos 96 in measure 0")

        try session.rewriteChart {
            try session.insertNote(
                atVPosition: 96,
                channel: "11",
                token: "01",
                measureLengths: lengths
            )
        }
        let rewritten = String(decoding: try session.currentBytes(), as: UTF8.self)
        require(rewritten.contains("#00002"), "rewrite keeps #mmm02")
        require(rewritten.contains("#TITLE Song") && rewritten.contains("#WAV01 a.wav"),
                "headers stay")
        require(
            session.chartSnapshot.events.contains { $0.channel == "11" && $0.measure == 1 },
            "same vpos stays in measure 1"
        )
        require(
            !session.chartSnapshot.events.contains { $0.channel == "11" && $0.measure == 0 },
            "do not fold measure 1 into the short measure 0"
        )

        let stretched = try DocumentSession(data: source)
        let stretchedLengths = stretched.timingSnapshot.measureLengths()
        try stretched.rewriteChart {
            try stretched.insertNote(
                atVPosition: 192,
                channel: "11",
                token: "01",
                measureLengths: stretchedLengths
            )
        }
        require(
            stretched.chartSnapshot.events.contains {
                $0.channel == "11" && $0.measure == 1 && abs($0.beat - 4) < 0.000_001
            },
            "vpos 192 is halfway through measure 1"
        )
        require(
            !stretched.chartSnapshot.events.contains { $0.channel == "11" && $0.measure == 0 },
            "expanded vpos 192 is not measure 0"
        )

        let mid = try DocumentSession(data: source)
        let midLengths = mid.timingSnapshot.measureLengths()
        try mid.rewriteChart {
            try mid.insertNote(
                atVPosition: 48,
                channel: "11",
                token: "01",
                measureLengths: midLengths
            )
        }
        require(
            mid.chartSnapshot.events.contains {
                $0.channel == "11" && $0.measure == 0 && abs($0.beat - 1) < 0.000_001
            },
            "vpos 48 is halfway through the half measure"
        )
    }

    @MainActor
    private static func testTimingSnapshotUsesCoreExactValues() throws {
        let source = Data(
            "#BPM 120.125\n#BPM01 240.5\n#STOP01 48\n#00003:78\n#00108:01\n#00109:01\n#00202:1.5\n".utf8
        )
        let session = try DocumentSession(data: source)
        let timing = session.timingSnapshot
        require(timing.available && timing.initialBPMDecimal == "120.125",
                "The session did not expose the core's exact initial BPM.")
        require(timing.ratio(for: 2) == "1.5",
                "The session did not expose the exact measure ratio from the bridge.")
        require(timing.events.count == 3,
                "The session did not expose every parsed BPM and STOP event.")
        let directBPM = timing.events[0]
        require(directBPM.measure == 0
                    && directBPM.channel == "03"
                    && directBPM.fraction == TimingRational(numerator: 0, denominator: 1)
                    && directBPM.valueDecimal == "120",
                "The session changed the direct BPM coordinate or exact value.")
        let stop = timing.events[2]
        require(stop.kind == .stop
                    && stop.valueDecimal == "48"
                    && stop.secondsAfterStop > stop.secondsBeforeStop,
                "The session did not preserve the core timing-map STOP duration.")

        let editable = try DocumentSession(data: Data("#BPM 120\n".utf8))
        try editable.setInitialBPM("121.25")
        try editable.setMeasureRatio(measure: 1, decimal: "0.5")
        try editable.insertTimingEvent(
            measure: 1,
            channel: "08",
            fraction: TimingRational(numerator: 1, denominator: 2),
            decimal: "127.125"
        )
        guard let insertedBPM = editable.timingSnapshot.events.first(where: {
            $0.measure == 1 && $0.channel == "08" && $0.fraction == TimingRational(numerator: 1, denominator: 2)
        }) else {
            throw TestFailure("The session did not expose the inserted BPM event.")
        }
        try editable.replaceTimingEvent(insertedBPM, decimal: "128.5")
        try editable.insertTimingEvent(
            measure: 2,
            channel: "09",
            fraction: TimingRational(numerator: 0, denominator: 1),
            decimal: "48"
        )
        guard let insertedStop = editable.timingSnapshot.events.first(where: {
            $0.measure == 2 && $0.channel == "09"
        }) else {
            throw TestFailure("The session did not expose the inserted STOP event.")
        }
        try editable.eraseTimingEvent(insertedStop)
        require(editable.dirty && editable.canUndo
                    && editable.timingSnapshot.initialBPMDecimal == "121.25"
                    && editable.timingSnapshot.ratio(for: 1) == "0.5"
                    && editable.timingSnapshot.events.count == 1
                    && editable.timingSnapshot.events[0].valueDecimal == "128.5",
                "Session timing mutations did not refresh exact values and shared history.")
        require(try editable.undo() && editable.timingSnapshot.events.count == 2,
                "Shared undo did not restore the deleted STOP event.")
        require(try editable.redo() && editable.timingSnapshot.events.count == 1,
                "Shared redo did not restore the timing deletion.")
        let timingSaved = try saveAndRead(editable)
        let timingText = String(decoding: timingSaved, as: UTF8.self)
        require(timingText.contains("#BPM 121.25")
                    && timingText.contains("#00102:0.5")
                    && timingText.contains("128.5"),
                "Saving a session did not serialize its timing edits.")

        let invalidInitialBPM = try DocumentSession(data: Data("#BPM invalid\n".utf8))
        require(!invalidInitialBPM.timingSnapshot.available
                    && invalidInitialBPM.timingSnapshot.canEditInitialBPM,
                "An invalid initial BPM must remain repairable in the timing session.")
        try invalidInitialBPM.setInitialBPM("120.1")
        require(invalidInitialBPM.timingSnapshot.available
                    && invalidInitialBPM.timingSnapshot.initialBPMDecimal == "120.1",
                "Repairing an invalid initial BPM did not refresh the timing snapshot.")
    }

    @MainActor
    private static func testLongNoteSessionPipeline() throws {
        let source = Data("#00051:010100\n#00102:1.5\n".utf8)
        let session = try DocumentSession(data: source)
        guard let original = session.longNoteSnapshot.notes.first else {
            throw TestFailure("The session did not expose a long-channel pair.")
        }
        require(original.channel == "51"
                    && original.start.fractionNumerator == 0
                    && original.end.fractionNumerator == 1 && original.end.fractionDenominator == 3,
                "The session changed a long note's exact source endpoints.")

        try session.moveLongNote(original, toMeasure: 1, channel: "52", gridSlot: 4, gridDivision: 16)
        guard let moved = session.longNoteSnapshot.notes.first else {
            throw TestFailure("A moved long note disappeared from the session snapshot.")
        }
        require(session.dirty && session.canUndo && moved.channel == "52"
                    && moved.start.fractionNumerator == 1 && moved.start.fractionDenominator == 6
                    && moved.end.fractionNumerator == 7 && moved.end.fractionDenominator == 18,
                "The session quantized an off-grid long-note tail or lost a horizontal channel move.")

        require(try session.undo(), "Undo after a session long-note move failed.")
        require(session.longNoteSnapshot.notes.first?.channel == "51" && session.canRedo,
                "Undo did not restore the original long-note channel and source pair.")
        require(try session.redo(), "Redo after a session long-note move failed.")

        guard let restoredMove = session.longNoteSnapshot.notes.first else {
            throw TestFailure("Redo did not restore the moved long note.")
        }
        try session.resizeLongNote(restoredMove, endMeasure: 1, endSlot: 12, gridDivision: 16)
        guard let resized = session.longNoteSnapshot.notes.first else {
            throw TestFailure("The resized long note disappeared from the session snapshot.")
        }
        try session.eraseLongNote(resized)
        require(session.longNoteSnapshot.notes.isEmpty && session.dirty && session.canUndo,
                "Long-note deletion did not share session dirty state and history.")
        require(try session.undo() && session.longNoteSnapshot.notes.count == 1,
                "Undo did not restore a deleted session long note.")

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibmsnative-long-note-\(UUID().uuidString).bms")
        defer { try? FileManager.default.removeItem(at: output) }
        try session.save(to: output)
        let reopened = try DocumentSession(data: Data(contentsOf: output), fileURL: output)
        guard let reopenedNote = reopened.longNoteSnapshot.notes.first else {
            throw TestFailure("Saving and reopening lost the long note.")
        }
        require(!session.dirty && reopenedNote.channel == "52"
                    && reopenedNote.start.fractionNumerator == 1 && reopenedNote.start.fractionDenominator == 6
                    && reopenedNote.end.fractionNumerator == 1 && reopenedNote.end.fractionDenominator == 2,
                "Save and reopen did not preserve the edited long-note coordinates.")

        let ntShort = try DocumentSession(data: Data("#00051:010100\n".utf8))
        guard let ntPair = ntShort.longNoteSnapshot.notes.first else {
            throw TestFailure("NT POBShort fixture is missing the long-channel pair.")
        }
        try ntShort.convertLongNoteToShort(ntPair, keepEnd: false)
        require(ntShort.longNoteSnapshot.notes.isEmpty, "NT POBShort clears Length")
        require(ntShort.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" && $0.fractionNumerator == 0 },
                "NT POBShort keeps the start cell on the visible channel")
        require(!ntShort.chartSnapshot.events.contains { $0.channel == "11" && $0.fractionDenominator == 3 && $0.fractionNumerator == 1 },
                "NT POBShort must not keep the tail")
        let bmseShort = try DocumentSession(data: Data("#00051:010100\n".utf8))
        guard let bmsePair = bmseShort.longNoteSnapshot.notes.first else {
            throw TestFailure("BMSE POBShort fixture is missing the long-channel pair.")
        }
        try bmseShort.convertLongNoteToShort(bmsePair, keepEnd: true)
        require(bmseShort.longNoteSnapshot.notes.isEmpty, "BMSE POBShort clears the LongNote flag")
        require(bmseShort.chartSnapshot.events.filter { $0.channel == "11" && $0.token == "01" }.count == 2,
                "BMSE POBShort keeps both endpoints as short notes")

        let bmseLong = try DocumentSession(data: Data("#00011:010100\n".utf8))
        let shorts = bmseLong.chartSnapshot.events
            .filter { $0.channel == "11" }
            .sorted {
                ($0.measure, $0.fractionNumerator, $0.fractionDenominator)
                    < ($1.measure, $1.fractionNumerator, $1.fractionDenominator)
            }
        require(shorts.count == 2, "BMSE POBLong fixture needs two short notes")
        try bmseLong.convertShortNotesToLong(start: shorts[0], end: shorts[1])
        require(bmseLong.longNoteSnapshot.notes.count == 1 && bmseLong.longNoteSnapshot.notes[0].channel == "51",
                "BMSE POBLong pairs two 11s onto channel 51")
        require(bmseLong.chartSnapshot.events.filter { $0.channel == "11" && $0.token != "00" }.isEmpty,
                "BMSE POBLong removes the short-channel cells")
        require(bmseLong.chartSnapshot.editable, "a paired long note stays editable")

        let leftover = try DocumentSession(data: Data("#00011:01\n".utf8))
        guard let leftoverShort = leftover.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("BMSE leftover POBLong fixture is missing the short note.")
        }
        try leftover.convertShortNoteToLongEndpoint(leftoverShort)
        require(leftover.longNoteSnapshot.notes.isEmpty, "a single 51 is not a pair")
        require(leftover.chartSnapshot.editable, "a leftover 51 stays editable")
        require(leftover.chartSnapshot.events.contains { $0.channel == "51" && $0.token == "01" },
                "BMSE POBLong leftover writes channel 51")
        require(!leftover.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
                "BMSE POBLong leftover removes the short-channel cell")
        require(try leftover.undo(), "undo leftover 51")
        require(leftover.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
                "undo restores the leftover short note")

        let openedLeftover = try DocumentSession(data: Data("#00051:0100\n".utf8))
        require(openedLeftover.chartSnapshot.editable && openedLeftover.longNoteSnapshot.notes.isEmpty,
                "opening a leftover 51 stays editable")
        guard let leftover51 = openedLeftover.chartSnapshot.events.first(where: { $0.channel == "51" }) else {
            throw TestFailure("opened leftover 51 is missing from chart events")
        }
        try openedLeftover.convertLongEndpointToShort(leftover51)
        require(openedLeftover.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
                "POBShort writes an unpaired 51 back to 11")
        require(!openedLeftover.chartSnapshot.events.contains { $0.channel == "51" },
                "POBShort removes the leftover long-channel cell")

        let three = try DocumentSession(data: Data("#00011:010101\n".utf8))
        let threeShorts = three.chartSnapshot.events
            .filter { $0.channel == "11" }
            .sorted {
                ($0.measure, $0.fractionNumerator, $0.fractionDenominator)
                    < ($1.measure, $1.fractionNumerator, $1.fractionDenominator)
            }
        require(threeShorts.count == 3, "three-short POBLong fixture")
        try three.convertShortNotesToLong(start: threeShorts[0], end: threeShorts[1])
        try three.convertShortNoteToLongEndpoint(threeShorts[2])
        require(three.longNoteSnapshot.notes.count == 1 && three.chartSnapshot.editable,
                "two shorts pair; the leftover 51 stays editable")
        require(three.chartSnapshot.events.contains {
            $0.channel == "51" && $0.token == "01" && $0.fractionNumerator == 2 && $0.fractionDenominator == 3
        }, "leftover short becomes 51 at 2/3")

        let copied = try DocumentSession(data: Data("#00011:01\n".utf8))
        guard let original = copied.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("Ctrl-drag copy fixture is missing the short note.")
        }
        try copied.copyNote(original, toMeasure: 0, channel: "12", gridSlot: 0, gridDivision: 16)
        require(copied.chartSnapshot.events.contains { $0.channel == "11" && $0.token == "01" },
                "Ctrl-drag copy keeps the original note")
        require(copied.chartSnapshot.events.contains { $0.channel == "12" && $0.token == "01" },
                "Ctrl-drag copy inserts the duplicate on the drop target")
        try copied.copyNote(original, toChannel: "13", vPosition: 48)
        require(copied.chartSnapshot.events.contains {
            $0.channel == "13" && $0.token == "01" && $0.measure == 0 && $0.fractionNumerator == 1 && $0.fractionDenominator == 4
        }, "copy by vpos 48 lands on beat 1")

        let longCopied = try DocumentSession(data: Data("#00051:01\n#00151:01\n".utf8))
        guard let hold = longCopied.longNoteSnapshot.notes.first else {
            throw TestFailure("Ctrl-drag long-note fixture is missing the 51 pair.")
        }
        try longCopied.copyLongNote(hold, toChannel: "52", vPosition: 0, length: 192)
        require(longCopied.longNoteSnapshot.notes.contains { $0.channel == "51" && $0.start.beat == 0 && $0.end.beat == 4 },
                "Ctrl-drag copy keeps the original long note")
        require(longCopied.longNoteSnapshot.notes.contains { $0.channel == "52" && $0.start.beat == 0 && $0.end.beat == 4 },
                "Ctrl-drag copy inserts the long-note duplicate")
        require(longCopied.chartSnapshot.editable, "copied long notes stay editable")

        let bpmCopied = try DocumentSession(data: Data("#00003:8C\n".utf8))
        guard let bpm = bpmCopied.chartSnapshot.events.first(where: { $0.channel == "03" }) else {
            throw TestFailure("Ctrl-drag BPM fixture is missing channel 03")
        }
        try bpmCopied.copyNote(bpm, toChannel: "03", vPosition: 48)
        require(
            bpmCopied.timingSnapshot.events.contains {
                $0.channel == "03" && $0.valueDecimal == "140"
                    && abs((Double($0.beat.numerator) / Double(max(1, $0.beat.denominator))) - 1) < 0.000_001
            },
            "Ctrl-drag copies BPM 140 to beat 1"
        )
        require(bpmCopied.chartSnapshot.events.contains { $0.channel == "03" && $0.token == "8C" && $0.beat == 0 },
                "the original BPM stays")
        try bpmCopied.copyNote(bpm, toChannel: "12", vPosition: 0)
        require(bpmCopied.chartSnapshot.events.contains { $0.channel == "12" && $0.token == "3W" },
                "BPM 140 dropped on 12 writes label 3W")

        let keyToBpm = try DocumentSession(data: Data("#00011:01\n".utf8))
        guard let key = keyToBpm.chartSnapshot.events.first(where: { $0.channel == "11" }) else {
            throw TestFailure("playable-to-BPM fixture is missing channel 11")
        }
        try keyToBpm.copyNote(key, toChannel: "03", vPosition: 48)
        require(
            keyToBpm.timingSnapshot.events.contains {
                $0.channel == "03" && $0.valueDecimal == "1"
                    && abs((Double($0.beat.numerator) / Double(max(1, $0.beat.denominator))) - 1) < 0.000_001
            },
            "label 01 dropped on BPM writes 1"
        )

        let scrollCopied = try DocumentSession(data: Data("#SCROLL01 0.5\n#000SC:01\n".utf8))
        guard let scroll = scrollCopied.chartSnapshot.events.first(where: { $0.channel == "SC" }) else {
            throw TestFailure("Ctrl-drag SCROLL fixture is missing channel SC")
        }
        try scrollCopied.copyNote(scroll, toChannel: "SC", vPosition: 48)
        require(
            scrollCopied.chartSnapshot.events.contains { $0.channel == "SC" && abs($0.beat - 1) < 0.000_001 },
            "Ctrl-drag copies SCROLL to beat 1"
        )
        let scrollText = String(decoding: try scrollCopied.currentBytes(), as: UTF8.self)
        require(scrollText.contains("0.5"), "copied SCROLL keeps 0.5")
    }

    @MainActor
    private static func testSaveBmsReportOverlapAndGridLimit() throws {
        let overlap = try DocumentSession(data: Data("#00011:01\n#00011:02\n".utf8))
        let sameSlot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibmsnative-save-overlap-\(UUID().uuidString).bms")
        defer { try? FileManager.default.removeItem(at: sameSlot) }
        let overlapReport = try overlap.save(to: sameSlot)
        require(overlapReport.overlapping && overlapReport.bpmCount == 0,
                "two cells on the same GCD slot set hasOverlapping")
        require(String(decoding: try Data(contentsOf: sameSlot), as: UTF8.self).contains("#00011:02"),
                "the later cell remains after the overlap write")

        var payload = "0102"
        payload.append(String(repeating: "0", count: 380))
        let adjacent = try DocumentSession(data: Data("#00011:\(payload)\n".utf8))
        let fine = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibmsnative-save-fine-\(UUID().uuidString).bms")
        let coarse = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibmsnative-save-coarse-\(UUID().uuidString).bms")
        defer {
            try? FileManager.default.removeItem(at: fine)
            try? FileManager.default.removeItem(at: coarse)
        }
        let fineReport = try adjacent.save(to: fine, gridLimit: 1.0)
        require(!fineReport.overlapping, "BMSGridLimit 1 keeps vpos 0 and 1 apart")
        require(String(decoding: try Data(contentsOf: fine), as: UTF8.self).contains("#00011:0102"),
                "vpos 1 stays in the second cell")

        let adjacentAgain = try DocumentSession(data: Data("#00011:\(payload)\n".utf8))
        let coarseReport = try adjacentAgain.save(to: coarse, gridLimit: 24.0)
        require(coarseReport.overlapping, "BMSGridLimit 24 maps both notes onto one slot")
        require(String(decoding: try Data(contentsOf: coarse), as: UTF8.self).contains("#00011:02\r\n"),
                "the later slot value remains after the coarse GCD")
    }

    @MainActor
    private static func saveAndRead(_ session: DocumentSession) throws -> Data {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibmsnative-session-\(UUID().uuidString).bms")
        defer { try? FileManager.default.removeItem(at: output) }
        try session.save(to: output)
        return try Data(contentsOf: output)
    }

    private static func makeShiftJISSource(titleBytes: [UInt8]) -> Data {
        var source = Data("#TITLE ".utf8)
        source.append(contentsOf: titleBytes)
        source.append(contentsOf: Array("\r\n#WAV01 ".utf8))
        source.append(contentsOf: [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA])
        source.append(contentsOf: Array(".wav\r\n#00111:01\r\n".utf8))
        return source
    }

    private static func requireThrows(
        _ operation: () throws -> Void,
        matches: (Error) -> Bool,
        message: String
    ) {
        var caught: Error?
        do {
            try operation()
        } catch {
            caught = error
        }
        guard let caught else {
            require(false, message)
            return
        }
        require(matches(caught), message)
    }

    private static func require(_ condition: Bool, _ message: String) {
        if !condition {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
