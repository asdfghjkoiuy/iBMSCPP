import AppKit
import Foundation

@main
struct LegacyTimeSelectionTests {
    static func main() {
        testLayout()
        testValidate()
        testHitAndDrag()
        testPaint()
        testConvertAndBPM()
        testGridPositions()
        testExpandByRatio()
        testStretchByHalfDelta()
        testRelocateByValue()
        testConvertAreaToStop()
        test1296Write()
        testErrorCheck()
        testFieldInput()
        testSelectAll()
        print("LegacyTimeSelectionTests passed")
    }

    private static func testSelectAll() {
        let bottoms = LegacyTimeSelection.defaultSelectAllBottoms

        let emptyNTOn = LegacyTimeSelection.greatestVPosition(notes: [], ntInput: true)
        let emptyNTOff = LegacyTimeSelection.greatestVPosition(notes: [], ntInput: false)
        require(emptyNTOn == 0 && emptyNTOff == 0, "empty Greatest is 0")
        let emptySelection = LegacyTimeSelection.selectAllTimeSelection(
            greatestVPosition: emptyNTOn,
            currentHalf: 48,
            bottoms: bottoms
        )
        require(
            emptySelection.start == 0 && emptySelection.length == 192 && emptySelection.half == 48,
            "empty chart: start 0, length 192, half stays 48"
        )

        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: 191, bottoms: bottoms) == 192,
            "non-NT vpos 191 → measure 0 upper 192"
        )
        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: 192, bottoms: bottoms) == 384,
            "non-NT vpos 192 → measure 1 upper 384"
        )

        let twoNotes = LegacyTimeSelection.greatestVPosition(
            notes: [(0, 0), (192, 0)],
            ntInput: false
        )
        require(twoNotes == 192, "non-NT notes at 0 and 192 → Greatest 192")
        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: twoNotes, bottoms: bottoms) == 384,
            "non-NT 0 and 192 → length 384"
        )

        let ntLong = LegacyTimeSelection.greatestVPosition(notes: [(0, 192)], ntInput: true)
        require(ntLong == 192, "NT long 0+192 → Greatest 192")
        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: ntLong, bottoms: bottoms) == 384,
            "NT long → length 384"
        )

        let ntOffLong = LegacyTimeSelection.greatestVPosition(notes: [(0, 192)], ntInput: false)
        require(ntOffLong == 0, "non-NT ignores Length, Greatest is 0")
        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: ntOffLong, bottoms: bottoms) == 192,
            "non-NT same note → length 192"
        )

        let measure0Length96: [Double] = [0, 96, 288]
        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: 50, bottoms: measure0Length96) == 96,
            "#00002:0.5 Greatest 50 → length 96"
        )
        require(
            LegacyTimeSelection.selectAllTimeLength(greatestVPosition: 96, bottoms: measure0Length96) == 288,
            "#00002:0.5 Greatest 96 → measure 1 → length 288"
        )

        let keepHalf = LegacyTimeSelection.selectAllTimeSelection(
            greatestVPosition: 0,
            currentHalf: 200,
            bottoms: bottoms
        )
        require(keepHalf.length == 192 && keepHalf.half == 200, "half stays 200 without validate")

        require(LegacyTimeSelection.selectAllIncludesNote(columnEnabled: true), "enabled note is selected")
        require(!LegacyTimeSelection.selectAllIncludesNote(columnEnabled: false), "disabled note is not selected")
    }

    private static func testLayout() {
        require(TimeSelectionLayout.stripHeight == 22, "FStatus2 height")
        require(TimeSelectionLayout.start == CGRect(x: 0, y: 1, width: 23, height: 20), "FSSS")
        require(TimeSelectionLayout.startTooltip == "Selection Start Position", "FSSS tooltip")
        require(TimeSelectionLayout.lengthTooltip == "Selection Length", "FSSL tooltip")
        require(TimeSelectionLayout.halfTooltip == "Selection Split Position", "FSSH tooltip")
        require(TimeSelectionLayout.reverse == CGRect(x: 69, y: 1, width: 102, height: 20), "Reverse")
        require(TimeSelectionLayout.apply == CGRect(x: 321, y: 1, width: 95, height: 20), "Expand")
        require(TimeSelectionLayout.convertStop == CGRect(x: 600, y: 1, width: 117, height: 20), "Stop")
        require(TimeSelection.legacyDefault.start == 192 && TimeSelection.legacyDefault.length == 0, "default vSelStart")
        require(TimeSelection.vPosition(beat: 4) == 192, "4 quarter beats = 192 vpos")
    }

    private static func testValidate() {
        let clipped = LegacyTimeSelection.validate(
            TimeSelection(start: -10, length: 20, half: 5),
            maxVPosition: 192
        )
        require(clipped.start == 0 && clipped.length == 10 && clipped.half == 0, "negative start, half sign")
        let upper = LegacyTimeSelection.validate(
            TimeSelection(start: 180, length: 40, half: 10),
            maxVPosition: 192
        )
        require(upper.start == 180 && abs(upper.length - 11) < 0.000_001, "end clamps to max-1")
        let reversed = LegacyTimeSelection.reverse(TimeSelection(start: 48, length: 96, half: 32))
        require(reversed.start == 144 && reversed.length == -96 && reversed.half == -64, "Reverse Selection")
        require(LegacyTimeSelection.formatField(192) == "192", "integer field")
        require(LegacyTimeSelection.maxVPosition(chartEndBeat: 4) == 192_000, "default 1000 measures of 192")
        require(LegacyTimeSelection.maxVPosition(chartEndBeat: 5000) == 240_000, "longer charts raise the limit")
    }

    private static func testHitAndDrag() {
        require(
            LegacyTimeSelection.hitLine(pointerY: 50, startY: 10, halfY: 30, endY: 50, threshold: 5) == .end,
            "end is checked first"
        )
        require(
            LegacyTimeSelection.hitLine(pointerY: 12, startY: 10, halfY: 30, endY: 50, threshold: 5) == .start,
            "start hit"
        )
        let started = LegacyTimeSelection.begin(
            at: 200,
            snapped: 192,
            current: TimeSelection.legacyDefault,
            line: .none
        )
        require(started.start == 192 && started.length == 0, "empty click snaps")
        let dragged = LegacyTimeSelection.drag(
            to: 300,
            snapped: 288,
            current: started,
            line: .none,
            noteVPosition: nil
        )
        require(dragged.start == 192 && dragged.length == 96 && dragged.half == 48, "drag sets half to mid")
        let moveStart = LegacyTimeSelection.begin(
            at: 100,
            snapped: 96,
            current: TimeSelection(start: 192, length: 96, half: 48),
            line: .start
        )
        require(moveStart.start == 96 && moveStart.length == 192 && moveStart.half == 144, "moving start keeps end")
    }

    private static func testPaint() {
        let height: CGFloat = 1000
        let startY = LegacyTimeSelection.lineY(vPosition: 192, contentHeight: height, pixelsPerQuarterBeat: 48)
        let endY = LegacyTimeSelection.lineY(vPosition: 384, contentHeight: height, pixelsPerQuarterBeat: 48)
        require(startY > endY, "later vpos is higher on the panel")
        let fill = LegacyTimeSelection.fillRect(
            start: 192,
            length: 192,
            contentHeight: height,
            pixelsPerQuarterBeat: 48,
            width: 200
        )
        require(abs(fill.height - 192) < 0.000_1, "abs(vSelLength) * gxHeight")
        require(abs(fill.minY - (endY + 1)) < 0.000_1, "fill starts at the later cursor plus 1")
        let outline = LegacyTimeSelection.hoverOutline(CGRect(x: 10, y: 20, width: 40, height: 10))
        require(outline == CGRect(x: 10, y: 20, width: 39, height: 9), "DrawRectangle uses width-1 height-1")
        let highlighted = LegacyTimeSelection.highlightColumn(ThemeColor(argb: 0xFF10_2030))
        require(highlighted.red == 32 && highlighted.green == 64 && highlighted.blue == 96, "column highlight * 2")
        let hover = LegacyTimeSelection.noteHoverOutline(laneLeft: 50, laneWidth: 42, anchorY: 200, noteHeight: 10)
        require(hover == CGRect(x: 50, y: 189, width: 42, height: 12), "GetNoteRectangle then Width-1 Height-1")
        let timeHover = LegacyTimeSelection.timeHoverRect(lineY: 40, width: 200)
        require(timeHover == CGRect(x: 0, y: 39, width: 199, height: 2), "PEMouseOver box")
    }

    private static func testConvertAndBPM() {
        require(
            LegacyTimeSelection.convertAreaToStopAllowed(start: 0, length: 192, noteVPositions: [0, 193]),
            "notes on the start edge and after the end are allowed"
        )
        require(
            !LegacyTimeSelection.convertAreaToStopAllowed(start: 0, length: 192, noteVPositions: [1]),
            "(lower, upper] rejects interior notes"
        )
        require(LegacyTimeSelection.stopValue(length: 192) == 1_920_000, "STOP.Value = vSelLength * 10000")
        let bpm = LegacyTimeSelection.bpmAt(
            vPosition: 200,
            header: 120,
            events: [(0, 120), (192, 180), (384, 90)]
        )
        require(bpm == 180, "last BPM at or before the cursor")
        let range = TimeSelection(start: 0, length: 192, half: 96)
        require(LegacyTimeSelection.contains(vPosition: 0, selection: range, ntInput: false), "start is inside a non-NT range")
        require(!LegacyTimeSelection.contains(vPosition: 192, selection: range, ntInput: false), "end is exclusive")
        require(LegacyTimeSelection.contains(vPosition: 180, length: 20, selection: range, ntInput: true), "NT length may cross the end")
        require(LegacyTimeSelection.write1296Notice(bpm1296: true, stop1296: false) == LegacyTimeSelection.write1296Notice, "1296 notice")
        require(LegacyTimeSelection.write1296Notice(bpm1296: false, stop1296: false) == nil, "no notice when both switches are off")
    }

    private static func testGridPositions() {
        let main = LegacyChartGrid.positions(measureStart: 0, measureLength: 4, divisions: 16)
        require(main.count == 16 && main[1] == 0.25, "192/16 vpos = 0.25 beat")
        require(main.last == 3.75, "grid stops before MeasureUpper")
        let sub = LegacyChartGrid.positions(measureStart: 0, measureLength: 4, divisions: 4)
        require(sub == [0, 1, 2, 3], "gSub=4")
        let partial = LegacyChartGrid.positions(measureStart: 0, measureLength: 0.3, divisions: 4)
        require(partial == [0], "partial measure does not emit the exclusive upper bound")
    }

    private static func testExpandByRatio() {
        let header = TimeSelectionNote(vPosition: -1, columnIndex: 2, value: 1_200_000, length: 0, hidden: false)
        let note = TimeSelectionNote(vPosition: 96, columnIndex: 5, value: 10_000, length: 0, hidden: false)
        let after = TimeSelectionNote(vPosition: 200, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let selection = TimeSelection(start: 0, length: 192, half: 96)
        let result = LegacyTimeSelectionOps.expandByRatio(
            notes: [header, note, after],
            selection: selection,
            ratio: 2,
            maxVPosition: 192_000
        )
        guard case .applied(let notes, let next) = result else {
            require(false, "expand applies")
            return
        }
        require(notes.contains { $0.columnIndex == 5 && $0.value == 10_000 && abs($0.vPosition - 192) < 0.000_001 }, "interior note scales from 96 to 192")
        require(notes.contains { $0.columnIndex == 5 && $0.value == 20_000 && abs($0.vPosition - 392) < 0.000_001 }, "note after upper shifts by 192")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 0 && $0.value == 2_400_000 }, "BPM at lower is header * ratio")
        require(notes.contains { $0.columnIndex == 2 && abs($0.vPosition - 384) < 0.000_001 && $0.value == 1_200_000 }, "BPM at new upper restores the prior BPM")
        require(next.start == 0 && next.length == 384 && next.half == 192, "selection length and half scale")
        require(
            LegacyTimeSelectionOps.expandByRatio(notes: [header], selection: selection, ratio: 1, maxVPosition: 192_000) == .skipped,
            "ratio 1 is a no-op"
        )
        require(
            LegacyTimeSelectionOps.expandByRatio(notes: [header], selection: TimeSelection.legacyDefault, ratio: 2, maxVPosition: 192_000) == .skipped,
            "empty length is a no-op"
        )
        require(
            LegacyTimeSelectionOps.expandByRatio(notes: [header], selection: selection, ratio: 0, maxVPosition: 192_000) == .blocked(LegacyTimeSelectionOps.factorMustBePositive),
            "non-positive ratio uses the original English"
        )
        let atLower = TimeSelectionNote(vPosition: 0, columnIndex: 2, value: 1_500_000, length: 0, hidden: false)
        guard case .applied(let scaled, _) = LegacyTimeSelectionOps.expandByRatio(
            notes: [header, atLower],
            selection: selection,
            ratio: 2,
            maxVPosition: 192_000
        ) else {
            require(false, "expand existing lower BPM")
            return
        }
        require(scaled.filter { $0.columnIndex == 2 && $0.vPosition == 0 }.count == 1, "do not add a second BPM on the lower edge")
        require(scaled.contains { $0.columnIndex == 2 && $0.vPosition == 0 && $0.value == 3_000_000 }, "existing lower BPM is multiplied")
    }

    private static func testStretchByHalfDelta() {
        // header 120、选区 0–192、中线 96、delta +48
        // xRatio1 = (96 + 48) / 96 = 1.5
        // xRatio2 = (192 - 96 - 48) / 96 = 0.5
        let header = TimeSelectionNote(vPosition: -1, columnIndex: 2, value: 1_200_000, length: 0, hidden: false)
        let inside = TimeSelectionNote(vPosition: 48, columnIndex: 5, value: 10_000, length: 0, hidden: false)
        let after = TimeSelectionNote(vPosition: 200, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let selection = TimeSelection(start: 0, length: 192, half: 96)
        let result = LegacyTimeSelectionOps.stretchByHalfDelta(
            notes: [header, inside, after],
            selection: selection,
            delta: 48,
            maxVPosition: 192_000
        )
        guard case .applied(let notes, let next) = result else {
            require(false, "stretchHalf applies")
            return
        }
        require(next.start == 0 && next.length == 192 && next.half == 144, "vSelHalf += 48, then validate")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 0 && $0.value == 1_800_000 }, "lower BPM is header * 1.5")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 144 && $0.value == 600_000 }, "half BPM is header * 0.5")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 192 && $0.value == 1_200_000 }, "upper BPM restores the prior value")
        require(notes.contains { $0.columnIndex == 5 && $0.value == 10_000 && abs($0.vPosition - 72) < 0.000_001 }, "note in the first half: (48-0)*1.5")
        require(notes.contains { $0.columnIndex == 5 && $0.value == 20_000 && abs($0.vPosition - 200) < 0.000_001 }, "NT does not shift notes after upper")
        require(
            LegacyTimeSelectionOps.stretchByHalfDelta(notes: [header], selection: selection, delta: 0, maxVPosition: 192_000) == .skipped,
            "delta 0 is a no-op"
        )
        require(
            LegacyTimeSelectionOps.stretchByHalfDelta(notes: [header], selection: TimeSelection.legacyDefault, delta: 48, maxVPosition: 192_000) == .skipped,
            "empty length is a no-op"
        )
        require(
            LegacyTimeSelectionOps.stretchByHalfDelta(notes: [header], selection: selection, delta: 96, maxVPosition: 192_000) == .skipped,
            "new half on upper is outside (lower, upper)"
        )
        require(
            LegacyTimeSelectionOps.stretchByHalfDelta(notes: [header], selection: selection, delta: -96, maxVPosition: 192_000) == .skipped,
            "new half on lower is outside (lower, upper)"
        )
        let atLower = TimeSelectionNote(vPosition: 0, columnIndex: 2, value: 1_500_000, length: 0, hidden: false)
        let atHalf = TimeSelectionNote(vPosition: 96, columnIndex: 2, value: 1_000_000, length: 0, hidden: false)
        guard case .applied(let scaled, _) = LegacyTimeSelectionOps.stretchByHalfDelta(
            notes: [header, atLower, atHalf],
            selection: selection,
            delta: 48,
            maxVPosition: 192_000
        ) else {
            require(false, "stretch existing BPM at lower and half")
            return
        }
        require(scaled.filter { $0.columnIndex == 2 && $0.vPosition == 0 }.count == 1, "do not add a second BPM on the lower edge")
        require(scaled.contains { $0.columnIndex == 2 && $0.vPosition == 0 && $0.value == 2_250_000 }, "existing lower BPM is multiplied by ratio1")
        require(scaled.filter { $0.columnIndex == 2 && abs($0.vPosition - 144) < 0.000_001 }.count == 1, "do not add a second BPM on the moved half")
        require(scaled.contains { $0.columnIndex == 2 && abs($0.vPosition - 144) < 0.000_001 && $0.value == 500_000 }, "existing half BPM is multiplied by ratio2 and moved")
    }

    private static func testRelocateByValue() {
        let header = TimeSelectionNote(vPosition: -1, columnIndex: 2, value: 1_200_000, length: 0, hidden: false)
        let note = TimeSelectionNote(vPosition: 48, columnIndex: 5, value: 10_000, length: 0, hidden: false)
        let selection = TimeSelection(start: 0, length: 192, half: 96)
        let result = LegacyTimeSelectionOps.relocateByValue(
            notes: [header, note],
            selection: selection,
            value: 2_400_000,
            maxVPosition: 192_000
        )
        guard case .applied(let notes, let next) = result else {
            require(false, "relocate applies")
            return
        }
        require(notes.contains { $0.columnIndex == 5 && abs($0.vPosition - 96) < 0.000_001 }, "quarter of the first half lands on the split")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 0 && $0.value == 2_400_000 }, "target BPM at lower")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 96 && $0.value == 800_000 }, "second-half BPM is 80")
        require(notes.contains { $0.columnIndex == 2 && $0.vPosition == 192 && $0.value == 1_200_000 }, "upper BPM restores the prior value")
        require(next == selection, "Relocate does not scale the selection")
        guard case .blocked(let message) = LegacyTimeSelectionOps.relocateByValue(
            notes: [header],
            selection: selection,
            value: 400_000,
            maxVPosition: 192_000
        ) else {
            require(false, "too-small target is blocked")
            return
        }
        require(message == LegacyTimeSelectionOps.relocateLimitMessage(60), "original greater-than limit")
    }

    private static func testConvertAreaToStop() {
        let header = TimeSelectionNote(vPosition: -1, columnIndex: 2, value: 1_200_000, length: 0, hidden: false)
        let start = TimeSelectionNote(vPosition: 0, columnIndex: 5, value: 10_000, length: 0, hidden: false)
        let after = TimeSelectionNote(vPosition: 200, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let selection = TimeSelection(start: 0, length: 192, half: 96)
        guard case .applied(let notes, let next) = LegacyTimeSelectionOps.convertAreaToStop(
            notes: [header, start, after],
            selection: selection
        ) else {
            require(false, "convert applies")
            return
        }
        require(notes.contains { $0.columnIndex == 5 && $0.value == 20_000 && abs($0.vPosition - 8) < 0.000_001 }, "notes after upper move by -length")
        require(notes.contains { $0.columnIndex == 3 && $0.vPosition == 0 && $0.value == 1_920_000 }, "STOP at lower is vSelLength * 10000")
        require(next == selection, "convert keeps the selection")
        let blocked = LegacyTimeSelectionOps.convertAreaToStop(
            notes: [header, TimeSelectionNote(vPosition: 192, columnIndex: 5, value: 10_000, length: 0, hidden: false)],
            selection: selection
        )
        require(blocked == .blocked(LegacyTimeSelection.convertBlockedMessage), "notes on (lower, upper] block convert")
    }

    private static func test1296Write() {
        require(Legacy1296Write.limit(enabled: false) == 255, "closed switch cap")
        require(Legacy1296Write.limit(enabled: true) == 1295, "open switch cap")
        require(Legacy1296Write.isChannel03BPM(1_200_000), "integer 1-255 stays on 03")
        require(!Legacy1296Write.isChannel03BPM(2_560_000), "256 needs a #BPM definition")
        require(Legacy1296Write.uniqueExtendedBPMCount([1_200_000, 1_800_000, 1_800_000]) == 0, "03 values are not counted")
        require(Legacy1296Write.uniqueExtendedBPMCount([2_560_000, 2_560_000, 1_205_000]) == 2, "unique extended BPM values")
        require(Legacy1296Write.overflowMessage(kind: .bpm, count: 255, enabled: false) == nil, "255 is allowed when the switch is off")
        require(
            Legacy1296Write.overflowMessage(kind: .bpm, count: 256, enabled: false)
                == "Warning: \nNumbers of multi-byte BPMs has exceeded supported maximum: 256 > 255\nThe saved file will contain errors.",
            "BPM overflow text"
        )
        require(
            Legacy1296Write.overflowMessage(kind: .stop, count: 1296, enabled: true)
                == "Warning: \nNumbers of STOPs has exceeded supported maximum: 1296 > 1295\nThe saved file will contain errors.",
            "STOP overflow text"
        )
        require(Legacy1296Write.messages(bpmValues: [1_200_000], stopValues: [], bpm1296: false, stop1296: false).isEmpty, "no warning under the cap")
        require(
            Legacy1296Write.overlapMessage()
                == "Warning: \nNote operlapping detected. Increasing Maximum Grid Partition will resolve this.\nThe saved file will contain errors.",
            "SaveBMS overlap text keeps the source typo"
        )
        require(Legacy1296Write.scrollOverflowMessage(count: 1295) == nil, "1295 SCROLL labels are allowed")
        require(
            Legacy1296Write.scrollOverflowMessage(count: 1296)
                == "Warning: \nNumbers of multi-byte SCROLLs has exceeded supported maximum: 1296 > 1295\nThe saved file will contain errors.",
            "SCROLL overflow text"
        )
        require(
            Legacy1296Write.saveMessages(
                overlapping: true,
                bpmCount: 256,
                stopCount: 0,
                scrollCount: 0,
                bpm1296: false,
                stop1296: false
            ) == [
                Legacy1296Write.overlapMessage(),
                Legacy1296Write.overflowMessage(kind: .bpm, count: 256, enabled: false)!,
            ],
            "SaveBMS warns overlap then UBound(hBPM)"
        )
    }

    private static func testErrorCheck() {
        let header = ErrorCheckNote(vPosition: -1, columnIndex: 2, value: 1_200_000, length: 0, hidden: false)
        let first = ErrorCheckNote(vPosition: 96, columnIndex: 5, value: 10_000, length: 0, hidden: false)
        let overlap = ErrorCheckNote(vPosition: 96, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let marked = LegacyErrorCheck.markNT([header, first, overlap], lnObj: 0)
        require(!marked[1].hasError && marked[2].hasError, "later same-cell short is the error")
        let body = ErrorCheckNote(vPosition: 0, columnIndex: 5, value: 10_000, length: 192, hidden: false)
        let inside = ErrorCheckNote(vPosition: 96, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let covered = LegacyErrorCheck.markNT([header, body, inside], lnObj: 0)
        require(covered[2].hasError, "a short inside an NT long is an error")
        let orphan = ErrorCheckNote(vPosition: 48, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let unpaired = LegacyErrorCheck.markNT([header, orphan], lnObj: 2)
        require(unpaired[1].hasError, "LnObj with nothing before it is an error")
        let head = ErrorCheckNote(vPosition: 0, columnIndex: 5, value: 10_000, length: 0, hidden: false)
        let tail = ErrorCheckNote(vPosition: 48, columnIndex: 5, value: 20_000, length: 0, hidden: false)
        let paired = LegacyErrorCheck.markNT([header, head, tail], lnObj: 2)
        require(!paired[1].hasError && !paired[2].hasError, "LnObj pairs with the previous visible short")
        let hiddenHead = ErrorCheckNote(vPosition: 0, columnIndex: 5, value: 10_000, length: 0, hidden: true)
        let skipped = LegacyErrorCheck.markNT([header, hiddenHead, tail], lnObj: 2)
        require(skipped[2].hasError, "hidden notes are skipped when looking for an LnObj pair")
        let icon = LegacyErrorCheck.iconRect(laneLeft: 50, laneWidth: 40, anchorY: 200, noteHeight: 10)
        require(icon == CGRect(x: 58, y: 183, width: 24, height: 24), "24x24 centered on the note")
        require(LegacyErrorCheck.hoverErrorText == "Error", "FSE uses Strings.StatusBar.Err")
    }

    private static func testFieldInput() {
        let maxV = 192_000.0
        let def = TimeSelection.legacyDefault
        require(LegacyTimeSelection.fieldTitle == "", "InputBox title is empty")

        let startRange = LegacyTimeSelection.bounds(.start, selection: def, maxVPosition: maxV)
        require(startRange.min == 0 && startRange.max == 192_000, "default Start bounds")
        require(
            LegacyTimeSelection.fieldPrompt(min: startRange.min, max: startRange.max)
                == "Please enter a number between 0 and 192000.",
            "default Start prompt"
        )

        let lengthRange = LegacyTimeSelection.bounds(.length, selection: def, maxVPosition: maxV)
        require(lengthRange.min == -192 && lengthRange.max == 191_808, "default Length bounds")
        require(
            LegacyTimeSelection.fieldPrompt(min: lengthRange.min, max: lengthRange.max)
                == "Please enter a number between -192 and 191808.",
            "default Length prompt"
        )

        let halfRange = LegacyTimeSelection.bounds(.half, selection: def, maxVPosition: maxV)
        require(halfRange.min == 0 && halfRange.max == 0, "default Half bounds")
        require(
            LegacyTimeSelection.fieldPrompt(min: halfRange.min, max: halfRange.max)
                == "Please enter a number between 0 and 0.",
            "default Half prompt"
        )

        let positive = TimeSelection(start: 192, length: 96, half: 0)
        let posStart = LegacyTimeSelection.bounds(.start, selection: positive, maxVPosition: maxV)
        require(posStart.min == 0 && posStart.max == 191_904, "Start when length is 96")
        let posHalf = LegacyTimeSelection.bounds(.half, selection: positive, maxVPosition: maxV)
        require(posHalf.min == 0 && posHalf.max == 96, "Half when length is 96")

        let negative = TimeSelection(start: 192, length: -96, half: 0)
        let negStart = LegacyTimeSelection.bounds(.start, selection: negative, maxVPosition: maxV)
        require(negStart.min == 96 && negStart.max == 192_000, "Start when length is -96")
        let negHalf = LegacyTimeSelection.bounds(.half, selection: negative, maxVPosition: maxV)
        require(negHalf.min == 96 && negHalf.max == 0, "Half keeps min > max")

        require(LegacyTimeSelection.val("16abc") == 16, "Val(16abc)")
        require(LegacyTimeSelection.val("abc") == 0, "Val(abc)")
        require(LegacyTimeSelection.val("   ") == 0, "Val(spaces)")
        require(LegacyTimeSelection.parseFieldInput("", min: 0, max: 192_000) == nil, "empty string cancels")

        require(
            LegacyTimeSelection.parseFieldInput("200000", min: startRange.min, max: startRange.max) == 192_000,
            "Start 200000 first clamps to 192000"
        )
        let limit = maxV - 1
        let overflowLength = 0 + (192_000 - limit)
        let overflowHalf = 0 + (192_000 - limit)
        require(limit == 191_999 && overflowLength == 1 && overflowHalf == 1, "Start overflow branch: start=191999, length=1, half=1")
        let startOver = applyFieldInput(.start, "200000", to: def, maxV: maxV)
        require(startOver != nil, "Start 200000 parses")
        require(
            startOver?.start == 191_999 && startOver?.length == 0 && startOver?.half == 0,
            "full ValidateSelection then end clamp and opposite-sign half → 0"
        )

        let lengthOver = applyFieldInput(.length, "200000", to: def, maxV: maxV)
        require(lengthOver?.start == 192 && lengthOver?.length == 191_807, "Length 200000 → 191807")

        let startLow = applyFieldInput(.start, "-10", to: def, maxV: maxV)
        require(startLow?.start == 0 && startLow?.length == 0 && startLow?.half == 0, "Start -10 → 0")

        let lengthLow = applyFieldInput(.length, "-200", to: def, maxV: maxV)
        require(lengthLow?.start == 192 && lengthLow?.length == -192, "Length -200 → -192")
        require((lengthLow?.start ?? 0) + (lengthLow?.length ?? 0) == 0, "start+length is 0")

        let halfDefault = applyFieldInput(.half, "50", to: def, maxV: maxV)
        require(halfDefault?.half == 0, "Half 50 clamps to 0")

        require(applyFieldInput(.start, "", to: def, maxV: maxV) == nil, "empty does not change")

        let startVal = applyFieldInput(.start, "16abc", to: def, maxV: maxV)
        require(startVal?.start == 16 && startVal?.length == 0 && startVal?.half == 0, "Val(16abc) as Start")

        require(LegacyTimeSelection.parseFieldInput("abc", min: 0, max: 192_000) == 0, "Val(abc) is 0")

        let startSpaces = applyFieldInput(.start, "   ", to: def, maxV: maxV)
        require(startSpaces?.start == 0, "spaces are not empty; Val → 0")

        let halfNeg = applyFieldInput(.half, "50", to: negative, maxV: maxV)
        require(halfNeg?.half == 0 && halfNeg?.length == -96 && halfNeg?.start == 192, "Half any → 96 then validate 0")
        require(
            LegacyTimeSelection.parseFieldInput("50", min: negHalf.min, max: negHalf.max) == 96,
            "Half inverted range clamps any input to 96"
        )

        let halfOver = applyFieldInput(.half, "200", to: positive, maxV: maxV)
        require(halfOver?.start == 192 && halfOver?.length == 96 && halfOver?.half == 96, "Half 200 → 96")

        let startMid = applyFieldInput(.start, "50", to: positive, maxV: maxV)
        require(startMid?.start == 50 && startMid?.length == 96, "only Start changes; length stays 96")
    }

    private static func applyFieldInput(
        _ field: TimeSelectionField,
        _ text: String,
        to selection: TimeSelection,
        maxV: Double
    ) -> TimeSelection? {
        let range = LegacyTimeSelection.bounds(field, selection: selection, maxVPosition: maxV)
        guard let value = LegacyTimeSelection.parseFieldInput(text, min: range.min, max: range.max) else {
            return nil
        }
        return LegacyTimeSelection.applyField(field, value: value, to: selection, maxVPosition: maxV)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
