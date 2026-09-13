import AppKit
import Foundation

@main
struct ChartLayoutTests {
    static func main() {
        let measures = [
            ChartMeasureSnapshot(measure: 0, start: 0, length: 4),
            ChartMeasureSnapshot(measure: 1, start: 4, length: 2),
            ChartMeasureSnapshot(measure: 2, start: 6, length: 6)
        ]
        let event = ChartEventSnapshot(measure: 1, channel: "16", token: "01", fractionNumerator: 1,
                                       fractionDenominator: 2, beat: 5, kind: "normalNote", sourceLine: 2)
        let layout = ChartLayout(snapshot: ChartSnapshot(events: [event], measures: measures, diagnostics: [], editable: true, editingReason: ""),
                                 side: .onePlayer, pixelsPerQuarterBeat: 48, division: 16)
        require(layout.lanes.map(\.channel) == ["16", "11", "12", "13", "14", "15", "18", "19"], "1P source lane order changed")
        require(layout.lanes.map(\.width) == [42, 30, 42, 45, 42, 30, 42, 40], "source lane widths changed")
        let twoPlayer = ChartLayout(snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
                                    side: .twoPlayer, pixelsPerQuarterBeat: 48, division: 16)
        require(twoPlayer.lanes.map(\.channel) == ["21", "22", "23", "24", "25", "28", "29", "26"],
                "Selecting 2P must show its source lane bank even when a theme saves it hidden.")
        require(ChartPlayerColumns.showsTwoPlayer("2") && ChartPlayerColumns.showsTwoPlayer("3"),
                "iBMSC iPlayer<>0 shows 2P columns")
        require(!ChartPlayerColumns.showsTwoPlayer("1") && !ChartPlayerColumns.showsTwoPlayer(""),
                "PLAYER 1 / missing hides 2P")
        let singleBoth = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .both,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showsTwoPlayerColumns: false
        )
        require(singleBoth.lanes.map(\.channel) == ["16", "11", "12", "13", "14", "15", "18", "19"],
                "PLAYER 1 hides 2P even when the side control is Both")
        require(layout.eventRect(event)?.rect.maxY == layout.y(forBeat: 5), "note must extend upward from its anchor")
        require(layout.hitTest(CGPoint(x: 52, y: layout.y(forBeat: 5) - 4)) == event, "note hit test does not match draw rect")
        require(layout.snapTarget(at: CGPoint(x: 55, y: layout.y(forBeat: 4.99)))?.slot == 3, "snap must floor from measure start")
        require(layout.snapTarget(at: CGPoint(x: 55, y: layout.y(forBeat: 5.99)))?.slot == 7, "0.5 measure at division 16 must have eight slots")
        require(layout.snapTarget(at: CGPoint(x: 55, y: layout.y(forBeat: 11.99)))?.slot == 23, "1.5 measure at division 16 must have twenty-four slots")
        let longMeasure = ChartMeasureSnapshot(measure: 99, start: 12, length: 10_000)
        let longLayout = ChartLayout(snapshot: ChartSnapshot(events: [], measures: [longMeasure], diagnostics: [], editable: true, editingReason: ""), side: .onePlayer, pixelsPerQuarterBeat: 48, division: 64)
        let viewport = CGRect(x: 0, y: longLayout.y(forBeat: 100) - 96, width: 400, height: 96)
        require(longLayout.gridLines(in: viewport).count < 40, "grid generation must be bounded by the viewport, not the full measure")
        let partial = ChartMeasureSnapshot(measure: 3, start: 0, length: 0.3)
        let partialLayout = ChartLayout(snapshot: ChartSnapshot(events: [], measures: [partial], diagnostics: [], editable: true, editingReason: ""), side: .onePlayer, pixelsPerQuarterBeat: 48, division: 4)
        require(partialLayout.gridLines(in: CGRect(origin: .zero, size: partialLayout.contentSize)).map(\.y).contains(partialLayout.y(forBeat: 0.3)), "partial measure needs an exact final boundary")
        let oddDivision = ChartLayout(snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""), side: .onePlayer, pixelsPerQuarterBeat: 48, division: 7, subDivision: 4)
        require(oddDivision.division == 7, "gDivide allows any value from 1 through 1920")
        require(LegacyGridDivision.defaultSlash == 192, "gSlash starts at 192")
        require(LegacyGridDivision.doubled(16) == 32 && LegacyGridDivision.doubled(960) == 1920,
                "Oemcomma doubles CGDivide while it stays at or below 1920")
        require(LegacyGridDivision.doubled(961) == nil, "Oemcomma does nothing once 2x would exceed 1920")
        require(LegacyGridDivision.halved(16) == 8 && LegacyGridDivision.halved(3) == 1,
                "OemPeriod uses integer divide-by-two")
        require(LegacyGridDivision.halved(1) == nil, "OemPeriod does nothing at CGDivide.Minimum")
        require(LegacyGridDivision.parseSlash("") == nil && LegacyGridDivision.parseSlash("0") == nil
                    && LegacyGridDivision.parseSlash("abc") == nil,
                "Val 0 cancels BGSlash like the original InputBox")
        require(LegacyGridDivision.parseSlash("192") == 192 && LegacyGridDivision.parseSlash("16abc") == 16,
                "BGSlash keeps the leading Val number")
        require(LegacyGridDivision.parseSlash("1921") == 1920 && LegacyGridDivision.parseSlash("-5") == 1,
                "BGSlash clamps to CGDivide 1...1920")
        require(LegacyMoveNotes.playableDisplay(forDigit: 1) == "16"
                    && LegacyMoveNotes.playableDisplay(forDigit: 2) == "11"
                    && LegacyMoveNotes.playableDisplay(forDigit: 7) == "18"
                    && LegacyMoveNotes.playableDisplay(forDigit: 8) == "19"
                    && LegacyMoveNotes.playableDisplay(forDigit: 0) == nil,
                "Keys.D1–D8 map to niA1–niA8")
        require(LegacyMoveNotes.destination(source: "11", display: "12") == "12"
                    && LegacyMoveNotes.destination(source: "31", display: "13") == "33"
                    && LegacyMoveNotes.destination(source: "51", display: "16") == "56"
                    && LegacyMoveNotes.destination(source: "D6", display: "11") == "D1",
                "MoveToColumn keeps Hidden / Long / Mine on the target column")
        require(LegacyMoveNotes.notesToMove(sorted: ["11@0", "12@48"], shiftFirstOnly: true) == ["11@0"],
                "Shift+digit moves only the first selected note")
        require(LegacyMoveNotes.notesToMove(sorted: ["11@0", "12@48"], shiftFirstOnly: false) == ["11@0", "12@48"],
                "digit without Shift moves every selected note")
        let bgmAlone = LegacyMoveNotes.Occupant(channel: "11", vPosition: 0, length: 0)
        require(LegacyMoveNotes.bgmDestination(moving: bgmAlone, occupants: [bgmAlone], ntInput: true) == "B1",
                "MoveToBGM starts at niB")
        let onB1 = LegacyMoveNotes.Occupant(channel: "B1", vPosition: 0, length: 0)
        require(LegacyMoveNotes.bgmDestination(moving: onB1, occupants: [onB1], ntInput: false) == "B2",
                "a note already on B1 occupies that column and moves to the next free B")
        let longOnKey = LegacyMoveNotes.Occupant(channel: "11", vPosition: 0, length: 96)
        let bgmCover = LegacyMoveNotes.Occupant(channel: "B1", vPosition: 48, length: 0)
        require(LegacyMoveNotes.bgmDestination(moving: longOnKey, occupants: [longOnKey, bgmCover], ntInput: true) == "B2",
                "NT MoveToBGM treats interval overlap as occupied")
        require(LegacyMoveNotes.digit(fromKeyCode: 18) == 1 && LegacyMoveNotes.digit(fromKeyCode: 29) == 0
                    && LegacyMoveNotes.digit(fromKeyCode: 83) == 1 && LegacyMoveNotes.digit(fromKeyCode: 82) == 0,
                "main-row and keypad 0–8 map to the same digits")
        let arrowEnabled = [false, true, true, true]
        require(LegacyArrowMove.step(divide: 16, control: false, up: true) == 12,
                "Up without Control is 192 / gDivide")
        require(LegacyArrowMove.step(divide: 16, control: true, up: true) == 1,
                "Control+Up is 1")
        require(LegacyArrowMove.step(divide: 16, control: false, up: false) == -12,
                "Down without Control is -192 / gDivide")
        require(LegacyArrowMove.step(divide: 16, control: true, up: false) == -1,
                "Control+Down is -1")
        require(LegacyArrowMove.enabledIndex(real: 1, enabled: arrowEnabled) == 0,
                "real 1 is the first enabled column")
        require(LegacyArrowMove.enabledIndex(real: 3, enabled: arrowEnabled) == 2,
                "real 3 is the last enabled column")
        require(LegacyArrowMove.realIndex(enabled: 0, enabled: arrowEnabled) == 1,
                "enabled 0 maps back to real 1")
        require(LegacyArrowMove.realIndex(enabled: 2, enabled: arrowEnabled) == 3,
                "enabled 2 maps back to real 3")
        func arrowNote(real: Int, vpos: Double, length: Double = 0, channel: String = "11") -> LegacyArrowMove.Note {
            LegacyArrowMove.Note(realColumn: real, vPosition: vpos, length: length, channel: channel)
        }
        let upFromZero = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0)],
            direction: .up,
            enabled: arrowEnabled,
            divide: 16,
            ntInput: false
        )
        require(upFromZero.destinations.first?.vPosition == 12 && upFromZero.recordUndo,
                "Up from vpos 0 by 12 records undo")
        let upNearTop = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 191_990)],
            direction: .up,
            enabled: arrowEnabled,
            step: 12,
            ntInput: false
        )
        require(upNearTop.destinations.first?.vPosition == 191_999 && upNearTop.recordUndo,
                "Up near the top clamps to 191999 after subtracting 191999")
        let upAtTop = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 191_999)],
            direction: .up,
            enabled: arrowEnabled,
            step: 12
        )
        require(upAtTop.destinations.first?.vPosition == 191_999 && !upAtTop.recordUndo,
                "Up at 191999 does not move and does not record undo")
        let upNT = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 191_900, length: 100)],
            direction: .up,
            enabled: arrowEnabled,
            step: 12,
            ntInput: true
        )
        require(upNT.destinations.first?.vPosition == 191_899 && upNT.recordUndo,
                "NT Up counts Length then subtracts literal 191999")
        let upNTOff = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 191_900, length: 100)],
            direction: .up,
            enabled: arrowEnabled,
            step: 12,
            ntInput: false
        )
        require(upNTOff.destinations.first?.vPosition == 191_912,
                "BMSE Up ignores Length")
        let downZero = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0)],
            direction: .down,
            enabled: arrowEnabled,
            step: -12,
        )
        require(downZero.destinations.first?.vPosition == 0 && !downZero.recordUndo,
                "Down at vpos 0 stays and does not record undo")
        let downStep = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 24)],
            direction: .down,
            enabled: arrowEnabled,
            step: -12,
        )
        require(downStep.destinations.first?.vPosition == 12 && downStep.recordUndo,
                "Down from 24 by 12 records undo")
        let downPinned = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0), arrowNote(real: 2, vpos: 24)],
            direction: .down,
            enabled: arrowEnabled,
            step: -12,
        )
        require(
            downPinned.destinations.map(\.vPosition) == [0, 24] && !downPinned.recordUndo,
            "Down with one note at 0 pins the group so nothing moves"
        )
        let downPair = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 24), arrowNote(real: 2, vpos: 36)],
            direction: .down,
            enabled: arrowEnabled,
            step: -12,
        )
        require(
            downPair.destinations.map(\.vPosition) == [12, 24] && downPair.recordUndo,
            "Down from 24 and 36 moves both"
        )
        let leftFromTwo = LegacyArrowMove.move(
            notes: [arrowNote(real: 2, vpos: 0)],
            direction: .left,
            enabled: arrowEnabled
        )
        require(leftFromTwo.destinations.first?.realColumn == 1 && leftFromTwo.recordUndo,
                "Left from real 2 lands on real 1")
        let leftFromFirst = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0)],
            direction: .left,
            enabled: arrowEnabled
        )
        require(leftFromFirst.destinations.first?.realColumn == 1 && !leftFromFirst.recordUndo,
                "Left from the first enabled column stays")
        let leftPair = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0), arrowNote(real: 3, vpos: 0)],
            direction: .left,
            enabled: arrowEnabled
        )
        require(
            leftPair.destinations.map(\.realColumn) == [1, 3] && !leftPair.recordUndo,
            "Left with a note on the first enabled column pins the group"
        )
        let rightFromOne = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0)],
            direction: .right,
            enabled: arrowEnabled
        )
        require(rightFromOne.destinations.first?.realColumn == 2 && rightFromOne.recordUndo,
                "Right from real 1 lands on real 2")
        let rightLast = LegacyArrowMove.move(
            notes: [arrowNote(real: 3, vpos: 0)],
            direction: .right,
            enabled: arrowEnabled
        )
        require(rightLast.destinations.first?.realColumn == 3 && !rightLast.recordUndo,
                "Right past the last enabled column stays and does not record undo")
        let arrowDisplays = ["", "11", "12", "13"]
        let rightHidden = LegacyArrowMove.move(
            notes: [arrowNote(real: 1, vpos: 0, channel: "31")],
            direction: .right,
            enabled: arrowEnabled,
            displays: arrowDisplays
        )
        require(
            rightHidden.destinations.first?.channel == "32"
                && ChartDuplicate.writeChannel(source: "31", display: "12") == "32"
                && rightHidden.recordUndo,
            "Right keeps Hidden on the next enabled visible column via writeChannel"
        )
        let emptyArrow = LegacyArrowMove.move(notes: [], direction: .up, enabled: arrowEnabled)
        require(!emptyArrow.moved && !emptyArrow.recordUndo,
                "empty selection does not write and does not record undo")
        require(
            LegacyArrowMove.direction(fromKeyCode: 126) == .up
                && LegacyArrowMove.direction(fromKeyCode: 125) == .down
                && LegacyArrowMove.direction(fromKeyCode: 123) == .left
                && LegacyArrowMove.direction(fromKeyCode: 124) == .right,
            "macOS arrow keyCodes are 126/125/123/124"
        )
        let fullGrid = layout.gridLines(in: CGRect(origin: .zero, size: layout.contentSize))
        require(fullGrid.contains { $0.kind == .sub && $0.y == layout.y(forBeat: 1) }, "gSub=4 emits a subdivision on each quarter beat")
        require(fullGrid.contains { $0.kind == .grid && $0.y == layout.y(forBeat: 0.25) }, "gDivide=16 emits a grid line every 0.25 beat")
        require(fullGrid.contains { $0.kind == .measure && $0.y == layout.y(forBeat: 0) }, "measure bars sit on MeasureBottom")
        require(!ChartInput.isDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 102)), "a click must not become a quantizing drag")
        require(ChartInput.isDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 103, y: 100)), "drag threshold must accept deliberate movement")
        require(ChartInput.pointForAnchor(from: CGPoint(x: 50, y: 80), anchorOffsetY: 6).y == 86, "dragging must retain the note-anchor grab offset")
        let unrenderable = ChartMeasureSnapshot(measure: 4, start: .infinity, length: 4)
        let guardedLayout = ChartLayout(snapshot: ChartSnapshot(events: [], measures: [unrenderable], diagnostics: [], editable: true, editingReason: ""), side: .onePlayer, pixelsPerQuarterBeat: 48, division: 16)
        require(guardedLayout.snapshot.measures.isEmpty && guardedLayout.contentSize.height.isFinite,
                "invalid core display coordinates must not enter canvas arithmetic")
        require(!guardedLayout.snapshot.editable && !guardedLayout.snapshot.editingReason.isEmpty,
                "a partially hidden chart must become read-only with a reason")
        require(!guardedLayout.snapshot.diagnostics.isEmpty,
                "a range-gated chart must expose an honest diagnostic")
        require(guardedLayout.snapshot.diagnostics[0].message.contains("1 measures"),
                "a range-gated chart must report its omitted measure count")

        let nearlyEqualExisting = ChartEventSnapshot(
            measure: 1,
            channel: "11",
            token: "01",
            fractionNumerator: 10_000_000_001,
            fractionDenominator: 20_000_000_000,
            beat: 5.000_000_000_1,
            kind: "normalNote",
            sourceLine: 7
        )
        let moved = ChartEventSnapshot(measure: 1, channel: "11", token: "01", fractionNumerator: 1,
                                       fractionDenominator: 2, beat: 5, kind: "normalNote", sourceLine: 99)
        let movedSnapshot = ChartSnapshot(events: [nearlyEqualExisting, moved], measures: measures, diagnostics: [], editable: true, editingReason: "")
        require(ChartSelection.movedEvent(from: event, toMeasure: measures[1], channel: "11", excludingSourceLines: [2, 7], in: movedSnapshot) == moved,
                "a successful drag must select the newly appended core event, not a nearby existing note")
        let noOpSnapshot = ChartSnapshot(events: [event], measures: measures, diagnostics: [], editable: true, editingReason: "")
        require(ChartSelection.movedEvent(from: event, toMeasure: measures[1], channel: "16", excludingSourceLines: [2], in: noOpSnapshot) == nil,
                "an exact core no-op must leave the refreshed source selection in place")

        let lnobjHead = ChartEventSnapshot(measure: 0, channel: "11", token: "01", fractionNumerator: 0,
                                           fractionDenominator: 1, beat: 0, kind: "normalNote", sourceLine: 12)
        let lnobjTail = ChartEventSnapshot(measure: 0, channel: "11", token: "ZZ", fractionNumerator: 1,
                                           fractionDenominator: 3, beat: 4.0 / 3.0, kind: "normalNote", sourceLine: 12)
        let ordinarySameRow = ChartEventSnapshot(measure: 0, channel: "11", token: "02", fractionNumerator: 2,
                                                 fractionDenominator: 3, beat: 8.0 / 3.0, kind: "normalNote", sourceLine: 12)
        let lnobj = LongNoteSnapshot(
            channel: "11",
            start: LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 0, fractionDenominator: 1,
                                            beat: 0, token: "01", sourceLine: 12),
            end: LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 1, fractionDenominator: 3,
                                          beat: 4.0 / 3.0, token: "ZZ", sourceLine: 12),
            encoding: "lnobj"
        )
        let lnobjLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [lnobjHead, lnobjTail, ordinarySameRow], measures: [measures[0]], diagnostics: [], editable: true, editingReason: ""),
            longNotes: LongNoteSnapshotSet(notes: [lnobj], diagnostics: [], editable: true, editingReason: "", lnobjToken: "ZZ"),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16
        )
        func midpoint(_ rect: CGRect) -> CGPoint {
            CGPoint(x: rect.midX, y: rect.midY)
        }
        let fullViewport = CGRect(origin: .zero, size: lnobjLayout.contentSize)
        require(lnobjLayout.visibleNoteRects(in: fullViewport).map(\.event) == [ordinarySameRow],
                "LNOBJ endpoint suppression must not hide another ordinary note on the same source row.")
        guard let ordinaryRect = lnobjLayout.eventRect(ordinarySameRow)?.rect,
              let longRect = lnobjLayout.longNoteRect(lnobj) else {
            require(false, "LNOBJ layout did not create ordinary and long-note rectangles.")
            return
        }
        require(lnobjLayout.hitTest(midpoint(ordinaryRect)) == ordinarySameRow,
                "An ordinary same-row LNOBJ note must remain hittable.")
        require(lnobjLayout.hitTestLongNote(midpoint(longRect.startCap))?.part == .startCap
                    && lnobjLayout.hitTestLongNote(midpoint(longRect.endCap))?.part == .endCap
                    && lnobjLayout.hitTestLongNote(midpoint(longRect.body))?.part == .body,
                "LNOBJ caps and body must hit-test independently.")

        let longChannel = LongNoteSnapshot(
            channel: "51",
            start: LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 0, fractionDenominator: 1,
                                            beat: 0, token: "01", sourceLine: 20),
            end: LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 1, fractionDenominator: 2,
                                          beat: 2, token: "01", sourceLine: 21),
            encoding: "longChannel"
        )
        let mappedLongLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: [measures[0]], diagnostics: [], editable: true, editingReason: ""),
            longNotes: LongNoteSnapshotSet(notes: [longChannel], diagnostics: [], editable: true, editingReason: "", lnobjToken: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16
        )
        require(mappedLongLayout.longNoteRect(longChannel)?.body.minX == (mappedLongLayout.laneFrames["11"]?.minX ?? -1) + 1,
                "Long channel 51 must render in display lane 11 while retaining its raw source channel.")
        require(ChartLayout.displayChannel("31") == "11" && ChartLayout.displayChannel("D1") == "11",
                "hidden 31 and mine D1 share the 11 lane")
        require(ChartLayout.displayChannel("41") == "21" && ChartLayout.displayChannel("E1") == "21",
                "hidden 41 and mine E1 share the 21 lane")
        require(ChartWriteChannel.source(display: "11", hidden: true, mine: false) == "31",
                "Ctrl writes hidden channel 31")
        require(ChartWriteChannel.source(display: "11", hidden: false, mine: true) == "D1",
                "Ctrl+Shift writes mine channel D1")
        require(ChartWriteChannel.source(display: "21", hidden: true, mine: false) == "41",
                "2P hidden is 41")
        require(ChartWriteChannel.source(display: "21", hidden: false, mine: true) == "E1",
                "2P mine is E1")
        require(ChartBGM.displayChannel(lane: 0) == "B1" && ChartBGM.displayChannel(lane: 1) == "B2",
                "BGM lanes are B1, B2, ...")
        require(ChartBGM.lane(display: "B2") == 1 && ChartBGM.lane(display: "01") == 0,
                "B2 and #01 map back to lanes")
        require(ChartConvert.destinationChannel(for: "11", action: .hide) == "31",
                "→ Hidden writes channel 31")
        require(ChartConvert.destinationChannel(for: "31", action: .show) == "11",
                "→ Visible writes channel 11")
        require(ChartConvert.destinationChannel(for: "11", action: .toggle) == "31" &&
                    ChartConvert.destinationChannel(for: "31", action: .toggle) == "11",
                "Hidden / Visible toggles the hidden bit")
        require(ChartConvert.destinationChannel(for: "D1", action: .hide) == "31" &&
                    ChartConvert.destinationChannel(for: "D1", action: .show) == nil,
                "Hidden takes priority over landmine; Visible does not clear landmine")
        require(ChartConvert.destinationChannel(for: "51", action: .hide) == nil,
                "long-note channels stay out of this convert")
        require(ChartConvert.shortChannel(for: "51") == "11" && ChartConvert.shortChannel(for: "11") == "11",
                "POBShort writes the visible playable channel")
        require(!ChartConvert.longNoteMenuEnabled(ntInput: true) && ChartConvert.longNoteMenuEnabled(ntInput: false),
                "NT disables → Long and Long ↔ Short")
        require(ChartConvert.convertShortcut(fromKeyCode: 37) == .long &&
                    ChartConvert.convertShortcut(fromKeyCode: 1) == .short,
                "Keys.L / Keys.S without Ctrl call POBLong / POBShort")
        require(ChartConvert.convertShortcut(fromKeyCode: 5) == nil,
                "G is snap, not convert")
        require(ChartConvert.longChannel(for: "11") == "51" && ChartConvert.longChannel(for: "21") == "61",
                "GetBMSChannelBy LongNote writes 5x / 6x")
        require(ChartConvert.longChannel(for: "31") == "51" && ChartConvert.longChannel(for: "D1") == "51",
                "Long takes priority over hidden and landmine")
        require(ChartConvert.longChannel(for: "51") == "51" && ChartConvert.longChannel(for: "01") == nil,
                "already-long stays 51; BGM has no long channel")
        require(ChartConvert.isLongChannel("51") && ChartConvert.isLongChannel("61") && !ChartConvert.isLongChannel("11"),
                "5x / 6x are long-note channels")
        let pairStart = ChartEventSnapshot(measure: 0, channel: "11", token: "01", fractionNumerator: 0,
                                           fractionDenominator: 1, beat: 0, kind: "normalNote", sourceLine: 1)
        let pairEnd = ChartEventSnapshot(measure: 0, channel: "11", token: "01", fractionNumerator: 1,
                                           fractionDenominator: 3, beat: 4.0 / 3.0, kind: "normalNote", sourceLine: 1)
        let otherLane = ChartEventSnapshot(measure: 0, channel: "12", token: "02", fractionNumerator: 0,
                                           fractionDenominator: 1, beat: 0, kind: "normalNote", sourceLine: 2)
        let leftoverShort = ChartEventSnapshot(measure: 0, channel: "11", token: "03", fractionNumerator: 2,
                                               fractionDenominator: 3, beat: 8.0 / 3.0, kind: "normalNote", sourceLine: 3)
        let pairs = ChartConvert.longNotePairs(from: [pairEnd, pairStart, otherLane, leftoverShort])
        require(pairs.count == 1 && pairs[0].0.fractionNumerator == 0 && pairs[0].1.fractionNumerator == 1,
                "POBLong pairs two shorts on the same visible column in time order")
        let leftovers = ChartConvert.unpairedLongNotes(from: [pairEnd, pairStart, otherLane, leftoverShort])
        require(leftovers.count == 2 && leftovers[0].channel == "11" && leftovers[0].token == "03"
                    && leftovers[1].channel == "12",
                "POBLong leftover is the last short on each visible column")
        let unpaired51 = ChartEventSnapshot(measure: 0, channel: "51", token: "01", fractionNumerator: 0,
                                            fractionDenominator: 1, beat: 0, kind: "longNote", sourceLine: 8)
        require(ChartConvert.unpairedLongEndpoints(from: [unpaired51], longs: []).map(\.channel) == ["51"],
                "an unpaired 51 is a leftover long endpoint")
        let unpairedLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [unpaired51], measures: [measures[0]], diagnostics: [], editable: true,
                                    editingReason: ""),
            longNotes: LongNoteSnapshotSet(notes: [], diagnostics: [], editable: true, editingReason: "", lnobjToken: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16
        )
        let unpairedViewport = CGRect(origin: .zero, size: unpairedLayout.contentSize)
        require(unpairedLayout.visibleNoteRects(in: unpairedViewport).map(\.event) == [unpaired51],
                "unpaired 51 draws on the visible 11 column")
        require(unpairedLayout.hitTest(CGPoint(x: unpairedLayout.laneFrames["11"]?.midX ?? 0,
                                               y: unpairedLayout.y(forBeat: 0) - 4)) == unpaired51,
                "unpaired 51 is selectable")
        require(ChartConvert.mirrorChannel("11") == "15" && ChartConvert.mirrorChannel("16") == "18",
                "POBMirror swaps A2↔A6 and A1↔A7")
        require(ChartConvert.mirrorChannel("13") == "13" && ChartConvert.mirrorChannel("19") == nil,
                "A4 stays; A8 is not mirrored")
        require(ChartConvert.mirrorChannel("31") == "35" && ChartConvert.mirrorChannel("D6") == "D8",
                "Mirror keeps Hidden / Landmine and maps the playable column")
        require(ChartConvert.mirrorChannel("21") == nil && ChartConvert.mirrorChannel("01") == nil,
                "2P and BGM are not mirrored")
        require(ChartConvert.modifyLabel("a") == "0A" && ChartConvert.modifyLabel("01") == "01",
                "Modify Labels uppercases and pads to two characters")
        require(ChartConvert.modifyLabel("00") == nil && ChartConvert.modifyLabel("0") == nil
                    && ChartConvert.modifyLabel("") == nil && ChartConvert.modifyLabel("@@@") == nil,
                "00 / 0 / empty / junk are invalid labels")
        require(ChartConvert.modifyNumeric("140") == "140" && ChartConvert.modifyNumeric("-1") == "0.0001",
                "numeric InputBox: 140 stays; <=0 becomes Value 1")
        require(ChartConvert.modifyNumeric("0") == nil && ChartConvert.modifyNumeric("") == nil,
                "Val 0 skips the numeric rewrite")
        require(ChartConvert.doubleClickPrompt(channel: "03") == "Please enter a BPM value."
                    && ChartConvert.doubleClickPrompt(channel: "08") == "Please enter a BPM value.",
                "BPM columns use PromptEnterBPM")
        require(ChartConvert.doubleClickPrompt(channel: "09") == "Please enter a STOP value.",
                "STOP uses PromptEnterSTOP")
        require(ChartConvert.doubleClickPrompt(channel: "SC") == "Please enter a SCROLL value.",
                "SCROLL uses PromptEnterSCROLL")
        require(ChartConvert.doubleClickPrompt(channel: "11") == "Please enter a label."
                    && ChartConvert.doubleClickPrompt(channel: "04") == "Please enter a label.",
                "label columns use PromptEnter")
        require(ChartConvert.doubleClickNumeric(text: "140", channel: "03") == 140,
                "Val 140 stays 140")
        require(ChartConvert.doubleClickNumeric(text: "140abc", channel: "03") == 140,
                "Val stops at the first illegal character")
        require(ChartConvert.doubleClickNumeric(text: "0", channel: "03") == nil
                    && ChartConvert.doubleClickNumeric(text: "", channel: "03") == nil
                    && ChartConvert.doubleClickNumeric(text: "abc", channel: "03") == nil,
                "BPM 0 / empty / junk cancel")
        require(ChartConvert.doubleClickNumeric(text: "-1", channel: "03") == -1,
                "double-click -1 stays -1, not 0.0001")
        require(ChartConvert.doubleClickNumeric(text: "0", channel: "SC") == 0,
                "SCROLL valstr exactly 0 writes 0")
        require(ChartConvert.doubleClickNumeric(text: "0.0", channel: "SC") == nil
                    && ChartConvert.doubleClickNumeric(text: " 0", channel: "SC") == nil,
                "SCROLL 0.0 and leading-space 0 are not exact 0")
        require(ChartZoom.wheelNotches(scrollingDeltaY: 1, precise: false) == 1 &&
                    ChartZoom.wheelNotches(scrollingDeltaY: -1, precise: false) == -1,
                "PMain_Scroll treats one mouse-wheel notch as Delta/120")
        require(ChartZoom.nextTrackValue(current: 4, wheelNotches: 1) == 5 &&
                    ChartZoom.gridHeight(trackValue: 5) == 1.25,
                "Ctrl+wheel steps CGHeight2 by 1, then CGHeight = CGHeight2/4")
        require(ChartZoom.nextTrackValue(current: 20, wheelNotches: 1) == 20 &&
                    ChartZoom.nextTrackValue(current: 1, wheelNotches: -1) == 1,
                "CGHeight2 stays in Designer 1...20")
        require(ChartZoom.trackValue(gridHeight: 1) == 4,
                "default CGHeight 1.00 is track value 4")
        require(ChartZoom.gridHeight(trackValue: 5) == 1.25 &&
                    ChartZoom.trackValueFromField(1.25) == 5,
                "CGWidth2 += 1 then CGWidth = CGWidth2/4; slider 5 is 1.25")
        require(ChartZoom.clampField(0.1) == 0.25 && ChartZoom.clampField(100) == 99,
                "CGWidth NumericUpDown stays in Designer 0.25...99")
        require(ChartZoom.nudgeField(1, up: true) == 1.25 && ChartZoom.nudgeField(1.25, up: false) == 1,
                "OemPlus / OemMinus step CGHeight by Increment 0.25")
        require(ChartZoom.nudgeField(99, up: true) == 99 && ChartZoom.nudgeField(0.25, up: false) == 0.25,
                "CGHeight stops at Designer 0.25...99")
        require(ChartZoom.nudgeField(98.8, up: true) == 99 && ChartZoom.nudgeField(0.4, up: false) == 0.25,
                "near the ends OemPlus/OemMinus clamp to Maximum/Minimum")
        require(ChartZoom.trackValueFromField(10) == 20 && ChartZoom.clampField(10) == 10,
                "field 10 keeps gxWidth 10; slider stays at 20")
        require(layout.laneFrames["16"]?.minX == 50 && layout.laneFrames["16"]?.width == 42,
                "default gxWidth 1 keeps Measure gutter 50 and A1 width 42")
        require(layout.isMeasureArea(CGPoint(x: 25, y: 10)) && !layout.isMeasureArea(CGPoint(x: 50, y: 10)),
                "measure gutter is x < 50")
        require(!layout.isMasterLane(CGPoint(x: 80, y: 10)), "master off by default")
        let masterLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [event], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showMasterLane: true
        )
        require(masterLayout.laneFrames["16"]?.minX == 114, "master 64 sits after gutter 50")
        require(masterLayout.isMeasureArea(CGPoint(x: 25, y: 10)), "gutter still measure")
        require(!masterLayout.isMeasureArea(CGPoint(x: 80, y: 10)), "master is not measure")
        require(masterLayout.isMasterLane(CGPoint(x: 80, y: 10)), "x in 50..<114 is master")
        let fiveKeyLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            hiddenPlayChannels: ["18", "19"]
        )
        require(
            fiveKeyLayout.lanes.map(\.channel) == ["16", "11", "12", "13", "14", "15"],
            "Beat 5-key hides 18/19"
        )
        require(
            ChartLanes.pairs(for: ["11", "16"]).map(\.0) == ["11", "16"],
            "pairs keeps given channel order"
        )
        let rightScratch = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            onePlayerOrder: ChartLanes.pairs(for: ["11", "12", "13", "14", "15", "18", "19", "16"])
        )
        require(
            rightScratch.lanes.map(\.channel) == ["11", "12", "13", "14", "15", "18", "19", "16"],
            "7k scratch right puts 16 after keys"
        )
        require(
            (rightScratch.laneFrames["16"]?.minX ?? 0) > (rightScratch.laneFrames["19"]?.minX ?? 0),
            "7k scratch right draws 16 after 19"
        )
        let tenRight = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .both,
            pixelsPerQuarterBeat: 48,
            division: 16,
            onePlayerOrder: ChartLanes.pairs(for: ["11", "12", "13", "14", "15", "16"]),
            twoPlayerOrder: ChartLanes.pairs(for: ["21", "22", "23", "24", "25", "26"])
        )
        require(
            (tenRight.laneFrames["16"]?.minX ?? 0) > (tenRight.laneFrames["11"]?.minX ?? 0),
            "10k P1 scratch right draws 16 after 11"
        )
        require(
            (tenRight.laneFrames["26"]?.minX ?? 0) > (tenRight.laneFrames["21"]?.minX ?? 0),
            "10k P2 scratch right draws 26 after 21"
        )
        let circularLeft = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            hiddenPlayChannels: ["16", "18", "19", "21", "22", "23", "24", "25", "26", "28", "29"],
            onePlayerOrder: ChartLanes.pairs(for: ["14", "13", "12", "11", "15"])
        )
        require(
            circularLeft.lanes.map(\.channel) == ["14", "13", "12", "11", "15"],
            "circular left puts blue before red then space"
        )
        require(
            (circularLeft.laneFrames["14"]?.minX ?? 0) < (circularLeft.laneFrames["11"]?.minX ?? 0),
            "circular left draws 14 before 11"
        )
        require(
            (circularLeft.laneFrames["15"]?.minX ?? 0) > (circularLeft.laneFrames["11"]?.minX ?? 0),
            "circular left draws space after red"
        )
        let circularDouble = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showsTwoPlayerColumns: false,
            hiddenPlayChannels: ["22", "23", "24", "25", "26", "28", "29"],
            onePlayerOrder: ChartLanes.pairs(for: ["14", "13", "12", "11", "21", "15", "18", "19", "16"])
        )
        require(
            circularDouble.lanes.map(\.channel)
                == ["14", "13", "12", "11", "21", "15", "18", "19", "16"],
            "circular double lr is one row"
        )
        require(
            (circularDouble.laneFrames["21"]?.minX ?? 0) > (circularDouble.laneFrames["11"]?.minX ?? 0)
                && (circularDouble.laneFrames["21"]?.minX ?? 0) < (circularDouble.laneFrames["15"]?.minX ?? 0),
            "circular double space sits between left red and right red"
        )
        let popNineLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .both,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showsTwoPlayerColumns: true,
            hiddenPlayChannels: ["22", "23", "24", "25", "26", "28", "29"]
        )
        require(
            popNineLayout.lanes.map(\.channel).contains("21")
                && !popNineLayout.lanes.map(\.channel).contains("22"),
            "Pop 9-key keeps column 21 and hides the rest of 2P"
        )
        let plainFour = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            hiddenPlayChannels: Set([
                "14", "15", "18", "19", "21", "22", "23", "24", "25", "28", "29", "26"
            ]),
            onePlayerOrder: ChartLanes.pairs(for: ["16", "11", "12", "13"])
        )
        require(
            plainFour.lanes.map(\.channel) == ["16", "11", "12", "13"],
            "plain 4 shows first shared columns"
        )
        let plainTen = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showsTwoPlayerColumns: false,
            hiddenPlayChannels: Set(["23", "24", "25", "28", "29", "26"]),
            onePlayerOrder: ChartLanes.pairs(for: [
                "16", "11", "12", "13", "14", "15", "18", "19", "21", "22"
            ])
        )
        require(
            plainTen.lanes.map(\.channel)
                == ["16", "11", "12", "13", "14", "15", "18", "19", "21", "22"],
            "plain 10 is one row including 21"
        )
        let genericNote = ThemeColor(red: 180, green: 137, blue: 225)
        let genericBackground = ThemeColor(red: 51, green: 26, blue: 68)
        let genericPaint = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            hiddenPlayChannels: ["16", "19"],
            playSkinColors: [
                "11": ChartPlaySkinColor(note: genericNote, background: genericBackground)
            ]
        )
        let painted = genericPaint.lanes.first(where: { $0.channel == "11" })
        require(painted?.backgroundThemeColor == genericBackground, "generic overlay bg")
        let expectedColumn = ThemeColumn(
            legacyIndex: 0,
            width: 1,
            title: "",
            isVisible: true,
            noteColor: genericNote,
            textColor: ThemeColor(red: 255, green: 255, blue: 255),
            longNoteColor: genericNote,
            longTextColor: ThemeColor(red: 255, green: 255, blue: 255),
            backgroundColor: genericBackground
        )
        require(
            painted?.normalColors == expectedColumn.derivedColors(
                longNote: false,
                hidden: false,
                hiddenOpacity: genericPaint.theme.visual.hiddenNoteOpacity
            ),
            "generic overlay uses theme brightness"
        )
        let wideLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [event], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            gxWidth: 1.25
        )
        require(wideLayout.laneFrames["16"]?.minX == 62.5 && wideLayout.laneFrames["16"]?.width == 52.5,
                "gxWidth 1.25 scales nLeft and GetColumnWidth")
        require(wideLayout.lanes.map(\.width) == [42, 30, 42, 45, 42, 30, 42, 40],
                "theme column widths stay in unscaled units")
        require(wideLayout.hitTest(CGPoint(x: 65, y: wideLayout.y(forBeat: 5) - 4)) == event,
                "scaled column still hits the note")
        require(wideLayout.hitTest(CGPoint(x: 52, y: wideLayout.y(forBeat: 5) - 4)) == nil,
                "unscaled hit point misses after gxWidth 1.25")
        let lanes = ["16", "11", "12", "13", "14"]
        require(ChartDuplicate.shiftedChannel(source: "11", origin: "11", target: "13", lanes: lanes) == "13",
                "Ctrl-drag copy keeps the dragged note on the drop lane")
        require(ChartDuplicate.shiftedChannel(source: "12", origin: "11", target: "13", lanes: lanes) == "14",
                "Ctrl-drag copy shifts the other selected notes by the same lane delta")
        require(ChartDuplicate.shiftedChannel(source: "16", origin: "12", target: "11", lanes: lanes) == nil,
                "a shift past the left of the lane bank is rejected")
        require(ChartDuplicate.writeChannel(source: "31", origin: "11", target: "13", lanes: lanes) == "33",
                "copy keeps the Hidden flag on the destination column")
        require(ChartDuplicate.writeChannel(source: "D1", origin: "11", target: "13", lanes: lanes) == "D3",
                "copy keeps the landmine flag on the destination column")
        require(ChartDuplicate.shiftedGrid(
                    source: ChartDuplicate.GridPoint(measure: 0, slot: 0),
                    origin: ChartDuplicate.GridPoint(measure: 0, slot: 0),
                    target: ChartDuplicate.GridPoint(measure: 0, slot: 8),
                    slotsPerMeasure: 16
                ) == ChartDuplicate.GridPoint(measure: 0, slot: 8),
                "the dragged note lands on the drop grid")
        require(ChartDuplicate.shiftedGrid(
                    source: ChartDuplicate.GridPoint(measure: 0, slot: 8),
                    origin: ChartDuplicate.GridPoint(measure: 0, slot: 0),
                    target: ChartDuplicate.GridPoint(measure: 1, slot: 0),
                    slotsPerMeasure: 16
                ) == ChartDuplicate.GridPoint(measure: 1, slot: 8),
                "other selected notes keep their grid offset across measures")
        require(ChartDuplicate.notesToCopy(selected: ["12@0"], origin: "11@0").sorted() == ["11@0", "12@0"],
                "DuplicateSelectedNotes also copies the note under the mouse")
        let origin = ChartDuplicate.NoteRef(columnIndex: 1, vPosition: 0, length: 0)
        require(ChartDuplicate.shift(
                    notes: [origin],
                    origin: origin,
                    mouseColumn: 2,
                    mouseVPosition: 48,
                    ntInput: true
                ) == ChartDuplicate.Shift(columnDelta: 1, vPositionDelta: 48),
                "OnDuplicateSelectedNotes keeps the dragged note on the mouse column and vpos")
        require(ChartDuplicate.shift(
                    notes: [origin],
                    origin: origin,
                    mouseColumn: 2,
                    mouseVPosition: 48,
                    ntInput: true,
                    disableVerticalMove: true
                ) == ChartDuplicate.Shift(columnDelta: 1, vPositionDelta: 0),
                "DisableVerticalMove keeps vpos and still allows a column change")
        require(ChartDuplicate.shift(
                    notes: [origin],
                    origin: origin,
                    mouseColumn: 1,
                    mouseVPosition: 0,
                    ntInput: true
                ).isZero,
                "no copy until the mouse leaves the origin cell")
        let leftEdge = ChartDuplicate.NoteRef(columnIndex: 0, vPosition: 0, length: 0)
        require(ChartDuplicate.shift(
                    notes: [leftEdge],
                    origin: leftEdge,
                    mouseColumn: -1,
                    mouseVPosition: -24,
                    ntInput: true
                ) == ChartDuplicate.Shift(columnDelta: 0, vPositionDelta: 0),
                "dstColumn / mVPosition clamp copies back to column 0 and vpos 0")
        let nearTop = ChartDuplicate.NoteRef(columnIndex: 1, vPosition: 191_000, length: 2_000)
        require(ChartDuplicate.shift(
                    notes: [nearTop],
                    origin: nearTop,
                    mouseColumn: 1,
                    mouseVPosition: 191_100,
                    ntInput: true
                ) == ChartDuplicate.Shift(columnDelta: 0, vPositionDelta: -1_001),
                "NT length counts toward the 191999 ceiling")
        require(ChartDuplicate.shift(
                    notes: [nearTop],
                    origin: nearTop,
                    mouseColumn: 1,
                    mouseVPosition: 191_100,
                    ntInput: false
                ) == ChartDuplicate.Shift(columnDelta: 0, vPositionDelta: 100),
                "BMSE clamp ignores Length")
        require(ChartDuplicate.writeChannel(source: "51", display: "13") == "53",
                "copied NT longs keep the 5x family")
        let longStart = LongNoteEndpointSnapshot(
            measure: 0, fractionNumerator: 0, fractionDenominator: 1, beat: 0, token: "01", sourceLine: 1)
        let longEnd = LongNoteEndpointSnapshot(
            measure: 1, fractionNumerator: 0, fractionDenominator: 1, beat: 4, token: "01", sourceLine: 2)
        let longNote = LongNoteSnapshot(channel: "51", start: longStart, end: longEnd, encoding: "nt")
        let planned = ChartDuplicate.plan(
            shorts: [],
            longs: [longNote],
            originChannel: "51",
            originVPosition: 0,
            originLength: 192,
            mouseChannel: "12",
            mouseVPosition: 48,
            lanes: ["16", "11", "12", "13"],
            ntInput: true
        )
        require(planned?.longs.count == 1 && planned?.longs.first?.channel == "52"
                    && planned?.longs.first?.vPosition == 48 && planned?.longs.first?.length == 192,
                "Ctrl-drag copies a long note with the same length")
        let lockedLong = ChartDuplicate.plan(
            shorts: [],
            longs: [longNote],
            originChannel: "51",
            originVPosition: 0,
            originLength: 192,
            mouseChannel: "12",
            mouseVPosition: 48,
            lanes: ["16", "11", "12", "13"],
            ntInput: true,
            disableVerticalMove: true
        )
        require(lockedLong?.longs.count == 1 && lockedLong?.longs.first?.channel == "52"
                    && lockedLong?.longs.first?.vPosition == 0 && lockedLong?.longs.first?.length == 192,
                "DisableVerticalMove copies a long note across columns without changing vpos")
        require(ChartDuplicate.writeChannel(source: "03", display: "03") == "03",
                "a BPM copy that stays in the BPM column keeps 03")
        require(ChartDuplicate.writeChannel(source: "03", display: "11") == "11",
                "DuplicateSelectedNotes can move a BPM note onto a playable column")
        require(ChartDuplicate.writeChannel(source: "11", display: "03") == "03",
                "a playable note dragged onto the BPM column becomes 03")
        require(ChartDuplicate.writeChannel(source: "SC", display: "09") == "09",
                "SCROLL dragged onto STOP becomes 09")
        let bpmEvent = ChartEventSnapshot(
            measure: 0, channel: "03", token: "8C", fractionNumerator: 0,
            fractionDenominator: 1, beat: 0, kind: "bpm", sourceLine: 6
        )
        let timingLanes = ["SC", "03", "09", "16", "11", "12"]
        let bpmShift = ChartDuplicate.plan(
            shorts: [bpmEvent],
            longs: [],
            originChannel: "03",
            originVPosition: 0,
            originLength: 0,
            mouseChannel: "03",
            mouseVPosition: 48,
            lanes: timingLanes,
            ntInput: true
        )
        require(bpmShift?.shorts.count == 1 && bpmShift?.shorts.first?.channel == "03"
                    && bpmShift?.shorts.first?.vPosition == 48,
                "Ctrl-drag copies a BPM event down the same column")
        let bpmToKey = ChartDuplicate.plan(
            shorts: [bpmEvent],
            longs: [],
            originChannel: "03",
            originVPosition: 0,
            originLength: 0,
            mouseChannel: "11",
            mouseVPosition: 0,
            lanes: timingLanes,
            ntInput: true
        )
        require(bpmToKey?.shorts.count == 1 && bpmToKey?.shorts.first?.channel == "11"
                    && bpmToKey?.shorts.first?.vPosition == 0,
                "Ctrl-drag can drop a BPM event onto channel 11")
        let bgmEvent = ChartEventSnapshot(measure: 0, channel: "B2", token: "02", fractionNumerator: 0,
                                          fractionDenominator: 1, beat: 0, kind: "bgm", sourceLine: 3)
        let bgmLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [bgmEvent], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            bgmColumnCount: 2
        )
        require(bgmLayout.lanes.map(\.channel).suffix(2) == ["B1", "B2"],
                "CGB=2 appends B1 and B2 after the playable lanes")
        require(bgmLayout.eventRect(bgmEvent)?.rect.minX == (bgmLayout.laneFrames["B2"]?.minX ?? -1) + 1,
                "the second #01 row paints in B2")
        require(ChartLayout.displayChannel("08") == "03" && ChartLayout.displayChannel("SC") == "SC",
                "extended BPM shares the BPM column; SCROLL stays SC")
        require(ChartTiming.bpmWriteChannel("140") == "03" && ChartTiming.bpmWriteChannel("255") == "03",
                "integer BPM 1–255 writes channel 03")
        require(ChartTiming.bpmWriteChannel("256") == "08" && ChartTiming.bpmWriteChannel("140.5") == "08",
                "GetBMSChannelBy sends fractions and BPM >= 256 to channel 08")
        require(ChartTiming.bpmWriteChannel("0") == nil && ChartTiming.bpmWriteChannel("") == nil,
                "empty or zero BPM is skipped like InputBox value=0")
        require(ChartTiming.bpmWriteChannel("-1") == "03",
                "non-SCROLL value <= 0 is clamped to 1 and stored as channel 03")
        let extendedBpmEvent = ChartEventSnapshot(measure: 0, channel: "08", token: "01", fractionNumerator: 0,
                                          fractionDenominator: 1, beat: 0, kind: "extendedBpm", sourceLine: 4)
        let bgaEvent = ChartEventSnapshot(measure: 0, channel: "04", token: "01", fractionNumerator: 0,
                                          fractionDenominator: 1, beat: 0, kind: "bga", sourceLine: 5)
        let extraLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [extendedBpmEvent, bgaEvent], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showsScrollColumn: true,
            showsBPMColumn: true,
            showsStopColumn: true,
            showsBGAColumns: true
        )
        require(extraLayout.lanes.map(\.channel).prefix(3) == ["SC", "03", "09"],
                "CGBPM/CGSTOP/CGSCROLL append SCROLL, BPM, STOP before the playable lanes")
        require(extraLayout.lanes.map(\.channel).suffix(3) == ["04", "07", "06"],
                "CGBLP appends BGA, LAYER, POOR after the playable lanes")
        require(extraLayout.eventRect(extendedBpmEvent)?.rect.minX == (extraLayout.laneFrames["03"]?.minX ?? -1) + 1,
                "channel 08 paints in the BPM column")
        require(extraLayout.eventRect(bgaEvent)?.rect.minX == (extraLayout.laneFrames["04"]?.minX ?? -1) + 1,
                "channel 04 paints in the BGA column")
        let hiddenEvent = ChartEventSnapshot(measure: 1, channel: "31", token: "02", fractionNumerator: 1,
                                             fractionDenominator: 2, beat: 5, kind: "hiddenNote", sourceLine: 8)
        let hiddenLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [hiddenEvent], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16
        )
        require(hiddenLayout.eventRect(hiddenEvent)?.rect.minX == (hiddenLayout.laneFrames["11"]?.minX ?? -1) + 1,
                "hidden notes must paint in the visible playable lane")
        let kickLane = ChartLanes.fixedWidthLane(
            channel: "CH0",
            title: "kick.wav",
            width: 64,
            theme: .defaultTheme
        )
        let hatLane = ChartLanes.fixedWidthLane(
            channel: "CH1",
            title: "hat.wav",
            width: 32,
            theme: .defaultTheme
        )
        require(kickLane?.width == 64 && hatLane?.width == 32, "sound lane widths")
        let laneEvent = ChartEventSnapshot(
            measure: 0,
            channel: "CH0",
            token: "kick.wav",
            fractionNumerator: 0,
            fractionDenominator: 1,
            beat: 0,
            kind: "normal",
            sourceLine: 1
        )
        let soundLayout = ChartLayout(
            snapshot: ChartSnapshot(
                events: [laneEvent],
                measures: measures,
                diagnostics: [],
                editable: true,
                editingReason: ""
            ),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            bgmColumnCount: 1,
            gxWidth: 1.25,
            soundChannelLanes: [kickLane, hatLane].compactMap { $0 }
        )
        require(soundLayout.lanes.map(\.channel).suffix(2) == ["CH0", "CH1"], "sound lanes after BGM")
        require(soundLayout.laneFrames["CH0"]?.width == 64, "normal 64 ignores gxWidth")
        require(soundLayout.laneFrames["CH1"]?.width == 32, "compact 32 ignores gxWidth")
        require(
            soundLayout.laneFrames["CH1"]?.minX == soundLayout.laneFrames["CH0"]?.maxX,
            "second sound lane sits after the first"
        )
        require(
            soundLayout.eventRect(laneEvent)?.rect.minX == (soundLayout.laneFrames["CH0"]?.minX ?? -1) + 1,
            "channel notes paint in CH0"
        )

        guard let painted = layout.eventRect(event) else {
            require(false, "ordinary note paint geometry is missing")
            return
        }
        let lane = layout.laneFrames["16"]!
        let anchor = layout.y(forBeat: 5)
        require(painted.rect == CGRect(x: lane.minX + 1, y: anchor - 10, width: 40, height: 10),
                "ordinary outline must match PanelDraw.DrawNote")
        require(painted.fill == CGRect(x: lane.minX + 2, y: anchor - 9, width: 39, height: 9),
                "ordinary fill must use the +2/+1, width-3, height-1 insets")
        require(painted.selection == CGRect(x: lane.minX, y: anchor - 11, width: 42, height: 12),
                "selected-note rectangle must grow one pixel on each side")
        require(painted.hit.contains(CGPoint(x: lane.minX + 1, y: anchor)),
                "MouseInNote includes the time-anchor scanline")
        require(layout.y(forBeat: 5) == layout.contentSize.height - 240 - 1,
                "NoteRowToPanelHeight truncates toward zero and subtracts one pixel")
        require(LegacyChartPaint.gradientWeight(at: painted.gradientStart, from: painted.gradientStart, to: painted.gradientEnd) == 0
                    && LegacyChartPaint.gradientWeight(at: painted.gradientEnd, from: painted.gradientStart, to: painted.gradientEnd) == 1,
                "GDI+ LinearGradientBrush weights must be 0 at p1 and 1 at p2")
        guard let paintedLong = mappedLongLayout.longNoteRect(longChannel),
              let displayLane = mappedLongLayout.laneFrames["11"] else {
            require(false, "NT long-note paint geometry is missing")
            return
        }
        let startAnchor = mappedLongLayout.y(forBeat: 0)
        let endAnchor = mappedLongLayout.y(forBeat: 2)
        let lengthPixels = startAnchor - endAnchor
        require(paintedLong.fill.origin == CGPoint(x: displayLane.minX + 1, y: endAnchor - 9),
                "NT long-note fill starts at left+1, endTop+1")
        require(paintedLong.fill.size == CGSize(width: displayLane.width - 1, height: lengthPixels + 9),
                "NT long-note fill uses width-1 and length+kHeight-1")
        require(paintedLong.outline.size.width == displayLane.width - 3,
                "NT long-note outline uses width-3")
        require(
            layout.showBackground && layout.showMeasureNumber && layout.showVerticalLine && layout.showColumnCaption,
            "CGShowBG / CGShowM / CGShowV / CGShowC start checked"
        )
        require(layout.measureCaption(for: measures[0]) == "[000]", "measure label uses Add3Zeros brackets")
        require(layout.fillsColumnBackground(layout.lanes[1]), "A2 tint is drawn when BackGround is on")
        let hiddenGuides = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: measures, diagnostics: [], editable: true, editingReason: ""),
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showBackground: false,
            showMeasureNumber: false,
            showVerticalLine: false,
            showColumnCaption: false
        )
        require(
            !hiddenGuides.showBackground && !hiddenGuides.fillsColumnBackground(hiddenGuides.lanes[1]),
            "BackGround off skips column fill"
        )

        func endpoint(_ beat: Double, _ line: Int) -> LongNoteEndpointSnapshot {
            LongNoteEndpointSnapshot(measure: 0, fractionNumerator: 0, fractionDenominator: 1, beat: beat, token: "01", sourceLine: line)
        }
        let spanning = LongNoteSnapshot(channel: "51", start: endpoint(0, 100), end: endpoint(20, 101), encoding: "NT")
        let overlapFirst = LongNoteSnapshot(channel: "51", start: endpoint(9, 102), end: endpoint(11, 103), encoding: "NT")
        let overlapLast = LongNoteSnapshot(channel: "51", start: endpoint(9, 104), end: endpoint(11, 105), encoding: "NT")
        let longIndexLayout = ChartLayout(
            snapshot: ChartSnapshot(events: [], measures: [ChartMeasureSnapshot(measure: 0, start: 0, length: 24)], diagnostics: [], editable: true, editingReason: ""),
            longNotes: LongNoteSnapshotSet(notes: [spanning, overlapFirst, overlapLast], diagnostics: [], editable: true, editingReason: "", lnobjToken: ""),
            side: .onePlayer, pixelsPerQuarterBeat: 48, division: 16
        )
        let middleView = CGRect(x: 0, y: longIndexLayout.y(forBeat: 10) - 24, width: 400, height: 48)
        require(longIndexLayout.visibleLongNoteRects(in: middleView).count == 3, "long interval index keeps notes spanning the viewport")
        let hitPoint = CGPoint(x: longIndexLayout.laneFrames["11"]!.midX, y: longIndexLayout.y(forBeat: 10) - 4)
        require(longIndexLayout.hitTestLongNote(hitPoint)?.note.start.sourceLine == 104, "long interval hit keeps original reverse draw priority")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("\(message)\n", stderr); exit(EXIT_FAILURE) }
    }
}
