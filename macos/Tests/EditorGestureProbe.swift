import AppKit
import Foundation

/// 探测不链接预览混音的 C 符号，所以没有编进 `LegacyPreviewAudio.swift`。
/// 谱面表面的调用点不变；这两个查找与该文件里的同名函数一致。
enum LegacyPreviewAudio {
    static func fileName(forToken token: String, in table: [String: String]) -> String? {
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isWavKey(key) else { return nil }
        let name = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static func isAudibleChannel(_ channel: String) -> Bool {
        switch channel.uppercased() {
        case "02", "03", "04", "06", "07", "08", "09", "SC":
            return false
        default:
            return !channel.isEmpty
        }
    }

    private static func isWavKey(_ key: String) -> Bool {
        guard key.count == 2 else { return false }
        let chars = Array(key.uppercased())
        guard let high = base36(chars[0]), let low = base36(chars[1]) else { return false }
        let index = high * 36 + low
        return index >= 1 && index <= 1295
    }

    private static func base36(_ character: Character) -> Int? {
        switch character {
        case "0"..."9":
            return Int(character.asciiValue! - UInt8(ascii: "0"))
        case "A"..."Z":
            return Int(character.asciiValue! - UInt8(ascii: "A")) + 10
        default:
            return nil
        }
    }
}

@main
@MainActor
struct EditorGestureProbe {
    static func main() {
        var failures = 0
        func require(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                print("FAIL \(message)")
            }
        }
        let probe = GestureHarness()
        probe.testCoordinateRoundtrip(require)
        probe.testBmsDragFollowsGridWithoutWriting(require)
        probe.testVerticalLockAndEscapeAndInvalid(require)
        probe.testMultiSelectAndLongNotesAndCtrl(require)
        probe.testBmsMarqueeThenDigitTwo(require)
        probe.testBmsonRubberBandKeepsKind(require)
        probe.testScrollRetargetsDragPreview(require)
        probe.testReleaseRestoresDocumentGeometry(require)
        failures += probe.paintFailures
        if failures == 0 {
            print("PASS metal=\(probe.sawMetal)")
        } else {
            print("FAIL count=\(failures) metal=\(probe.sawMetal)")
            exit(1)
        }
    }
}

@MainActor
private final class GestureHarness {
    var sawMetal = false
    var paintFailures = 0
    private var moveBatches = 0
    private var singleMoves = 0
    private var copies = 0
    private var resizes = 0
    private var startMoves = 0
    private var digitEvents: [(digit: Int, shift: Bool)] = []
    private var lastShorts: [ChartDuplicate.ShortCopy] = []
    private var lastLongs: [ChartDuplicate.LongCopy] = []
    private var acceptMoves = true
    private var acceptResizes = true

    func testCoordinateRoundtrip(_ require: (Bool, String) -> Void) {
        let harness = make(length: 8)
        let point = CGPoint(x: 80, y: harness.surface.chartLayout.y(forBeat: 1))
        guard let event = mouse(.mouseMoved, content: point, on: harness) else {
            require(false, "mouse event synthesis failed")
            return
        }
        let local = harness.surface.convert(event.locationInWindow, from: nil)
        let chart = CGPoint(
            x: local.x + harness.surface.scrollOffset.x,
            y: local.y + harness.surface.scrollOffset.y
        )
        require(
            abs(chart.x - point.x) < 0.6 && abs(chart.y - point.y) < 0.6,
            "content point roundtrip \(chart) vs \(point) offset \(harness.surface.scrollOffset)"
        )
        harness.window.close()
    }

    func testBmsDragFollowsGridWithoutWriting(_ require: (Bool, String) -> Void) {
        let note = event(channel: "12", beat: 1, token: "A1", line: 1)
        let harness = make(length: 8, events: [note])
        guard let hit = harness.surface.chartLayout.eventRect(note) else {
            require(false, "missing note rect")
            return
        }
        let down = CGPoint(x: hit.hit.midX, y: hit.hit.midY)
        let anchorOffset = hit.rect.maxY - down.y
        let destination = lanePoint("13", beat: 2.4, on: harness)
        let anchor = CGPoint(x: destination.x, y: destination.y + anchorOffset)
        guard let snapped = harness.surface.chartLayout.snapTarget(at: anchor) else {
            require(false, "snap target missing at \(anchor)")
            return
        }
        let snappedBeat = snapped.measure.start + Double(snapped.slot) * 4.0 / 16.0
        let rawBeat = harness.surface.chartLayout.beat(atY: anchor.y)
        require(abs(snappedBeat - rawBeat) > 0.02, "fixture must leave the grid line raw=\(rawBeat) snap=\(snappedBeat)")
        send(.leftMouseDown, content: down, on: harness)
        for step in 1...4 {
            let point = CGPoint(
                x: down.x + (destination.x - down.x) * CGFloat(step) / 4,
                y: down.y + (destination.y - down.y) * CGFloat(step) / 4
            )
            send(.leftMouseDragged, content: point, on: harness)
            require(moveBatches == 0 && singleMoves == 0, "drag step \(step) wrote the document")
        }
        settle(harness)
        let passes = harness.surface.presentedPaintPasses
        require(passes >= 2, "drag paint passes \(passes) metal=\(harness.surface.hasMetalRenderer)")
        let ghosts = notes(token: "A1", ghost: true, on: harness)
        let bodies = notes(token: "A1", ghost: false, on: harness)
        require(ghosts.count == 1, "expected one drag ghost, got \(ghosts)")
        require(bodies.isEmpty, "original A1 still drawn \(bodies)")
        if let ghost = ghosts.first {
            require(abs(ghost.beat - snappedBeat) < 0.001, "ghost beat \(ghost.beat) snap \(snappedBeat) raw \(rawBeat)")
            require(ghost.channel == "13", "ghost channel \(ghost.channel)")
            let frame = harness.surface.chartLayout.laneFrames["13"]
            require(frame?.contains(CGPoint(x: ghost.contentRect.midX, y: 0)) == true, "ghost not on lane 13")
        }
        let beforeUp = moveBatches
        send(.leftMouseUp, content: destination, on: harness)
        require(moveBatches == beforeUp + 1, "mouse up batches \(moveBatches)")
        require(singleMoves == 0, "single-note move ran beside the batch")
        require(lastShorts.count == 1, "batch shorts \(lastShorts.count)")
        if let copy = lastShorts.first {
            require(copy.channel == "13", "committed channel \(copy.channel)")
            require(copy.event.token == "A1", "committed token changed")
            require(abs(ChartDuplicate.beat(vPosition: copy.vPosition) - snappedBeat) < 0.001, "committed beat drifted")
        }
        flushPaint(harness)
        require(moveBatches == beforeUp + 1, "successful release wrote again")
        require(notes(token: "A1", ghost: true, on: harness).isEmpty, "successful release left a ghost")
        let restored = notes(token: "A1", ghost: false, on: harness)
        require(restored.count == 1 && restored.first?.channel == "12", "successful release hid the document note \(restored)")
        if let body = restored.first {
            require(abs(body.beat - 1) < 0.001, "successful release moved the document note to \(body.beat)")
        }
        harness.window.close()
    }

    func testVerticalLockAndEscapeAndInvalid(_ require: (Bool, String) -> Void) {
        let note = event(channel: "12", beat: 2, token: "LK", line: 2)
        let harness = make(length: 8, events: [note])
        harness.surface.disableVerticalMove = true
        guard let hit = harness.surface.chartLayout.eventRect(note) else {
            require(false, "lock note missing")
            return
        }
        let down = CGPoint(x: hit.hit.midX, y: hit.hit.midY)
        let destination = lanePoint("14", beat: 5, on: harness)
        send(.leftMouseDown, content: down, on: harness)
        send(.leftMouseDragged, content: destination, on: harness)
        settle(harness)
        require(moveBatches == 0, "vertical lock wrote during drag")
        let ghosts = notes(token: "LK", ghost: true, on: harness)
        require(ghosts.count == 1, "lock ghost \(ghosts)")
        if let ghost = ghosts.first {
            require(abs(ghost.beat - 2) < 0.001, "vertical lock beat moved to \(ghost.beat)")
            require(ghost.channel == "14", "lock channel \(ghost.channel)")
        }
        require(notes(token: "LK", ghost: false, on: harness).isEmpty, "locked original still drawn")
        send(.leftMouseUp, content: destination, on: harness)
        require(moveBatches == 1, "lock release batches \(moveBatches)")
        if let copy = lastShorts.first {
            require(abs(ChartDuplicate.beat(vPosition: copy.vPosition) - 2) < 0.001, "lock commit changed time")
            require(copy.channel == "14" && copy.event.token == "LK", "lock commit payload \(copy.channel) \(copy.event.token)")
        }

        let again = event(channel: "12", beat: 2, token: "ES", line: 3)
        let escape = make(length: 8, events: [again])
        guard let escapeHit = escape.surface.chartLayout.eventRect(again) else {
            require(false, "escape note missing")
            return
        }
        let escapeDown = CGPoint(x: escapeHit.hit.midX, y: escapeHit.hit.midY)
        send(.leftMouseDown, content: escapeDown, on: escape)
        send(.leftMouseDragged, content: lanePoint("13", beat: 4, on: escape), on: escape)
        settle(escape)
        require(!notes(token: "ES", ghost: true, on: escape).isEmpty, "escape drag produced no ghost")
        guard let cancel = key(53, characters: "\u{1b}", on: escape) else {
            require(false, "escape event missing")
            return
        }
        escape.surface.keyDown(with: cancel)
        settle(escape)
        send(.leftMouseUp, content: lanePoint("13", beat: 4, on: escape), on: escape)
        require(moveBatches == 0, "escape committed a move \(moveBatches)")
        require(notes(token: "ES", ghost: true, on: escape).isEmpty, "escape left a ghost")
        require(notes(token: "ES", ghost: false, on: escape).count == 1, "escape hid the original")

        let bad = event(channel: "11", beat: 1, token: "IV", line: 4)
        let invalid = make(length: 8, events: [bad])
        guard let badHit = invalid.surface.chartLayout.eventRect(bad) else {
            require(false, "invalid note missing")
            return
        }
        let badDown = CGPoint(x: badHit.hit.midX, y: badHit.hit.midY)
        let gutter = CGPoint(x: 8, y: invalid.surface.chartLayout.y(forBeat: 3))
        let before = moveBatches
        send(.leftMouseDown, content: badDown, on: invalid)
        send(.leftMouseDragged, content: gutter, on: invalid)
        settle(invalid)
        require(notes(token: "IV", ghost: true, on: invalid).isEmpty, "invalid lane drew a ghost")
        require(notes(token: "IV", ghost: false, on: invalid).count == 1, "invalid lane hid the original")
        send(.leftMouseUp, content: gutter, on: invalid)
        require(moveBatches == before, "invalid target wrote \(moveBatches - before) batches")
        harness.window.close()
        escape.window.close()
        invalid.window.close()
    }

    func testMultiSelectAndLongNotesAndCtrl(_ require: (Bool, String) -> Void) {
        let first = event(channel: "12", beat: 1, token: "M1", line: 10)
        let second = event(channel: "13", beat: 2, token: "M2", line: 11)
        let harness = make(length: 8, events: [first, second])
        harness.surface.applySelection(events: [first, second], longNotes: [])
        guard let hit = harness.surface.chartLayout.eventRect(first) else {
            require(false, "multi hit missing")
            return
        }
        let down = CGPoint(x: hit.hit.midX, y: hit.hit.midY)
        let destination = lanePoint("15", beat: 3.3, on: harness)
        let before = moveBatches
        send(.leftMouseDown, content: down, on: harness)
        send(.leftMouseDragged, content: destination, on: harness)
        settle(harness)
        require(moveBatches == before, "multi drag wrote")
        require(notes(token: "M1", ghost: true, on: harness).count == 1, "M1 ghost missing")
        require(notes(token: "M2", ghost: true, on: harness).count == 1, "M2 ghost missing")
        require(notes(token: "M1", ghost: false, on: harness).isEmpty && notes(token: "M2", ghost: false, on: harness).isEmpty,
                "multi drag still drew originals")
        send(.leftMouseUp, content: destination, on: harness)
        require(moveBatches == before + 1, "multi release batches \(moveBatches)")
        require(lastShorts.count == 2 && lastLongs.isEmpty, "multi payload \(lastShorts.count) \(lastLongs.count)")
        let tokens = Set(lastShorts.map(\.event.token))
        require(tokens == ["M1", "M2"], "multi tokens \(tokens)")
        flushPaint(harness)
        require(moveBatches == before + 1, "multi release wrote again")
        require(notes(token: "M1", ghost: true, on: harness).isEmpty && notes(token: "M2", ghost: true, on: harness).isEmpty,
                "multi release left ghosts")
        require(notes(token: "M1", ghost: false, on: harness).count == 1
                    && notes(token: "M2", ghost: false, on: harness).count == 1,
                "multi release hid the document notes")

        let long = longNote(channel: "12", start: 1, end: 4, token: "LN", line: 20)
        let longs = make(length: 8, events: [], longs: [long])
        guard let painted = longs.surface.chartLayout.longNoteRect(long) else {
            require(false, "long rect missing")
            return
        }
        let body = CGPoint(x: painted.fill.midX, y: (painted.startCap.midY + painted.endCap.midY) / 2)
        let bodyDestination = lanePoint("11", beat: 2.2, on: longs)
        send(.leftMouseDown, content: body, on: longs)
        send(.leftMouseDragged, content: bodyDestination, on: longs)
        settle(longs)
        require(moveBatches == 0 && resizes == 0, "long body wrote early")
        let longGhosts = notes(token: "LN", ghost: true, on: longs)
        require(longGhosts.count == 1, "long ghost \(longGhosts)")
        if let ghost = longGhosts.first {
            require(ghost.longNote, "long ghost became a short")
            require(abs((ghost.endBeat - ghost.beat) - 3) < 0.001, "long length \(ghost.endBeat - ghost.beat)")
            require(ghost.channel == "11", "long channel \(ghost.channel)")
        }
        require(notes(token: "LN", ghost: false, on: longs).isEmpty, "long original still drawn")
        send(.leftMouseUp, content: bodyDestination, on: longs)
        require(moveBatches == 1 && lastLongs.count == 1, "long release \(moveBatches) \(lastLongs.count)")
        require(resizes == 0 && startMoves == 0, "body drag resized an endpoint")
        flushPaint(longs)
        require(moveBatches == 1 && resizes == 0, "long release wrote again")
        require(notes(token: "LN", ghost: true, on: longs).isEmpty, "long release left a ghost")
        let longBodies = notes(token: "LN", ghost: false, on: longs)
        require(longBodies.count == 1 && longBodies.first?.channel == "12", "long release hid the document note \(longBodies)")
        if let body = longBodies.first {
            require(abs((body.endBeat - body.beat) - 3) < 0.001, "long release changed length \(body.endBeat - body.beat)")
        }

        let end = longNote(channel: "13", start: 1, end: 3, token: "EP", line: 30)
        let ends = make(length: 8, events: [], longs: [end])
        guard let endPaint = ends.surface.chartLayout.longNoteRect(end) else {
            require(false, "end cap rect missing")
            return
        }
        let cap = CGPoint(x: endPaint.endHit.midX, y: endPaint.endHit.midY)
        let capDestination = CGPoint(x: cap.x, y: ends.surface.chartLayout.y(forBeat: 5.2))
        let resizeBefore = resizes
        send(.leftMouseDown, content: cap, on: ends)
        send(.leftMouseDragged, content: capDestination, on: ends)
        settle(ends)
        require(resizes == resizeBefore && moveBatches == 0, "endpoint wrote during drag")
        let endGhosts = notes(token: "EP", ghost: true, on: ends)
        require(endGhosts.count == 1, "endpoint ghost \(endGhosts)")
        if let ghost = endGhosts.first {
            require(abs(ghost.beat - 1) < 0.001, "endpoint start moved \(ghost.beat)")
            require(abs(ghost.endBeat - 3) > 0.2, "endpoint end stayed \(ghost.endBeat)")
        }
        require(notes(token: "EP", ghost: false, on: ends).isEmpty, "endpoint original still drawn")
        send(.leftMouseUp, content: capDestination, on: ends)
        require(resizes == resizeBefore + 1, "endpoint release resizes \(resizes)")
        require(moveBatches == 0, "endpoint release used a move batch")
        flushPaint(ends)
        require(resizes == resizeBefore + 1 && moveBatches == 0, "endpoint release wrote again")
        require(notes(token: "EP", ghost: true, on: ends).isEmpty, "endpoint release left a ghost")
        let endBodies = notes(token: "EP", ghost: false, on: ends)
        require(endBodies.count == 1, "endpoint release hid the document note \(endBodies)")
        if let body = endBodies.first {
            require(abs(body.beat - 1) < 0.001 && abs(body.endBeat - 3) < 0.001,
                    "endpoint release changed the document length \(body.beat) \(body.endBeat)")
        }

        let source = event(channel: "12", beat: 1, token: "CP", line: 40)
        let copy = make(length: 8, events: [source])
        guard let copyHit = copy.surface.chartLayout.eventRect(source) else {
            require(false, "copy hit missing")
            return
        }
        let copyDown = CGPoint(x: copyHit.hit.midX, y: copyHit.hit.midY)
        let copyDestination = lanePoint("15", beat: 3, on: copy)
        send(.leftMouseDown, content: copyDown, flags: .control, on: copy)
        send(.leftMouseDragged, content: copyDestination, flags: .control, on: copy)
        settle(copy)
        require(copies == 0 && moveBatches == 0, "ctrl drag wrote early copies=\(copies)")
        require(notes(token: "CP", ghost: false, on: copy).count == 1, "ctrl copy hid the original")
        require(notes(token: "CP", ghost: true, on: copy).count == 1, "ctrl copy ghost missing")
        send(.leftMouseUp, content: copyDestination, flags: .control, on: copy)
        require(copies == 1 && moveBatches == 0, "ctrl release copies=\(copies) moves=\(moveBatches)")
        flushPaint(copy)
        require(copies == 1 && moveBatches == 0, "ctrl release wrote again")
        require(notes(token: "CP", ghost: true, on: copy).isEmpty, "ctrl release left a ghost")
        require(notes(token: "CP", ghost: false, on: copy).count == 1, "ctrl release hid the original")

        let labelA = event(channel: "11", beat: 1, token: "AA", line: 50)
        let labelB = event(channel: "14", beat: 2, token: "AA", line: 51)
        let labels = make(length: 8, events: [labelA, labelB])
        guard let labelHit = labels.surface.chartLayout.eventRect(labelA)?.hit else {
            require(false, "label hit missing")
            return
        }
        let labelPoint = CGPoint(x: labelHit.midX, y: labelHit.midY)
        send(.leftMouseDown, content: labelPoint, flags: [.control, .shift], on: labels)
        send(.leftMouseUp, content: labelPoint, flags: [.control, .shift], on: labels)
        let selected = labels.surface.selectedChartItems().events.map(\.sourceLine).sorted()
        require(selected == [50, 51], "shift label select \(selected)")
        require(copies == 0 && moveBatches == 0, "shift select wrote")
        harness.window.close()
        longs.window.close()
        ends.window.close()
        copy.window.close()
        labels.window.close()
    }

    func testBmsMarqueeThenDigitTwo(_ require: (Bool, String) -> Void) {
        let kicks = [
            event(channel: "11", beat: 1, token: "K1", line: 1),
            event(channel: "11", beat: 2, token: "K2", line: 2),
            event(channel: "11", beat: 3, token: "K3", line: 3),
            event(channel: "12", beat: 2, token: "IN", line: 4),
            event(channel: "14", beat: 2, token: "ZZ", line: 5),
            event(channel: "11", beat: 7, token: "FAR", line: 6)
        ]
        let harness = make(length: 16, events: kicks)
        let start = lanePoint("16", beat: 0.2, on: harness)
        let end = lanePoint("12", beat: 3.5, on: harness)
        send(.leftMouseDown, content: start, on: harness)
        send(.leftMouseDragged, content: end, on: harness)
        settle(harness)
        let beforePasses = harness.surface.presentedPaintPasses
        let stroked = harness.surface.rubberBandWasStroked
        let hits = harness.surface.rubberBandBitmapHitCount()
        require(harness.surface.presentedPaintPasses >= beforePasses, "bitmap paint went backwards")
        require(stroked, "BMS marquee was not stroked by the overlay")
        require(hits > 0, "BMS marquee bitmap hits \(hits) band \(String(describing: harness.surface.bmsonRubberBandFrame()))")
        require(moveBatches == 0 && digitEvents.isEmpty, "marquee drag wrote or sent a digit")
        send(.leftMouseUp, content: end, on: harness)
        let selected = harness.surface.selectedChartItems().events
        let tokens = Set(selected.map(\.token))
        require(tokens == ["K1", "K2", "K3", "IN"], "marquee tokens \(tokens)")
        require(selected.allSatisfy { event in
            kicks.first { $0.token == event.token }?.beat == event.beat
        }, "marquee changed timing")
        guard let digit = key(19, characters: "2", on: harness) else {
            require(false, "digit 2 event missing")
            return
        }
        let passesBeforeKey = harness.surface.presentedPaintPasses
        harness.surface.keyDown(with: digit)
        require(digitEvents.count == 1 && digitEvents[0].digit == 2 && digitEvents[0].shift == false,
                "digit events \(digitEvents)")
        require(harness.surface.presentedPaintPasses == passesBeforeKey, "digit key repainted the chart")
        let after = harness.surface.selectedChartItems().events
        require(Set(after.map(\.token)) == tokens, "digit 2 cleared selection")
        require(after.allSatisfy { event in
            kicks.first { $0.sourceLine == event.sourceLine }?.beat == event.beat
                && kicks.first { $0.sourceLine == event.sourceLine }?.token == event.token
        }, "digit 2 changed notes before the callback returned")
        let display = LegacyMoveNotes.playableDisplay(forDigit: 2)
        require(display == "11", "digit 2 display \(String(describing: display))")
        var moved = 0
        for event in after {
            guard let destination = LegacyMoveNotes.destination(source: event.channel, display: "11") else {
                require(false, "no destination for \(event.channel)")
                continue
            }
            if destination != event.channel {
                moved += 1
                require(destination == "11", "destination \(destination)")
            }
        }
        require(moved >= 1, "nothing needed to move onto key 2")
        guard let letterD = key(2, characters: "d", on: harness) else {
            require(false, "letter d event missing")
            return
        }
        harness.surface.keyDown(with: letterD)
        require(digitEvents.count == 1, "letter d was treated as digit 2")
        harness.window.close()
    }

    func testBmsonRubberBandKeepsKind(_ require: (Bool, String) -> Void) {
        let notes = [
            event(channel: "11", beat: 1, token: "K1", line: 1),
            event(channel: "12", beat: 2, token: "K2", line: 2),
            event(channel: "13", beat: 1.5, token: "OUT", line: 3),
            event(channel: "03", beat: 1, token: "90", line: 4),
            event(channel: "B1", beat: 1, token: "BG", line: 5),
            event(channel: "18", beat: 1, token: "KEEP", line: 6)
        ]
        let harness = make(length: 8, events: notes, bpm: true, bgm: 1)
        harness.surface.applyBmsonSnap(
            applies: true,
            resolution: 240,
            fineGrid: BmsONESnap.defaultFineGrid,
            bars: [],
            viewMode: BmsONEViewMode(kind: .beat7k)
        )
        if let keep = notes.first(where: { $0.token == "KEEP" }) {
            harness.surface.applySelection(events: [keep], longNotes: [])
        }
        let start = lanePoint("11", beat: 0.2, on: harness)
        let end = lanePoint("12", beat: 3.2, on: harness)
        send(.leftMouseDown, content: start, flags: .control, on: harness)
        send(.leftMouseDragged, content: end, flags: .control, on: harness)
        settle(harness)
        guard let band = harness.surface.bmsonRubberBandFrame(),
              let left = harness.surface.chartLayout.laneFrames["11"],
              let right = harness.surface.chartLayout.laneFrames["12"] else {
            require(false, "BMSON band missing")
            return
        }
        require(abs(band.minX - min(left.minX, right.minX)) < 1, "BMSON band left \(band) lanes \(left) \(right)")
        require(abs(band.maxX - max(left.maxX, right.maxX)) < 1, "BMSON band right \(band)")
        require(harness.surface.rubberBandWasStroked, "BMSON band was not stroked")
        let hits = harness.surface.rubberBandBitmapHitCount()
        require(hits > 0, "BMSON bitmap hits \(hits)")
        send(.leftMouseUp, content: end, flags: .control, on: harness)
        let tokens = Set(harness.surface.selectedChartItems().events.map(\.token))
        require(tokens == ["K1", "K2", "KEEP"], "BMSON tokens \(tokens)")
        require(moveBatches == 0, "BMSON marquee wrote notes")
        harness.window.close()
    }

    func testScrollRetargetsDragPreview(_ require: (Bool, String) -> Void) {
        let note = event(channel: "12", beat: 30, token: "SC", line: 1)
        let harness = make(length: 40, events: [note], viewHeight: 640)
        harness.surface.setOffset(CGPoint(x: 0, y: 200))
        settle(harness)
        guard let hit = harness.surface.chartLayout.eventRect(note) else {
            require(false, "scroll note missing")
            return
        }
        let down = CGPoint(x: hit.hit.midX, y: hit.hit.midY)
        let dragged = CGPoint(x: down.x + 70, y: down.y + 36)
        send(.leftMouseDown, content: down, on: harness)
        send(.leftMouseDragged, content: dragged, on: harness)
        settle(harness)
        guard let before = notes(token: "SC", ghost: true, on: harness).first else {
            require(false, "scroll drag ghost missing notes=\(harness.surface.presentedNotes)")
            return
        }
        guard let scroll = scrollEvent(wheel: -160) else {
            require(false, "scroll event synthesis failed")
            return
        }
        let offsetBefore = harness.surface.scrollOffset
        let batches = moveBatches
        harness.surface.scrollWheel(with: scroll)
        settle(harness)
        require(harness.surface.scrollOffset != offsetBefore, "scroll did not move offset \(offsetBefore) eventY \(scroll.scrollingDeltaY) precise \(scroll.hasPreciseScrollingDeltas)")
        require(moveBatches == batches, "scroll wrote the document")
        guard let after = notes(token: "SC", ghost: true, on: harness).first else {
            require(false, "scroll lost the ghost")
            return
        }
        require(abs(after.beat - before.beat) > 0.2, "scroll left the ghost at \(after.beat) from \(before.beat)")
        require(notes(token: "SC", ghost: false, on: harness).isEmpty, "scroll restored the original under the ghost")
        send(.leftMouseUp, content: dragged, on: harness)
        require(moveBatches == batches + 1, "scroll release did not commit once")
        harness.window.close()
    }

    /// 松手后的几何来自手势自己排上的刷新，不再调用 `synchronizePresentation` 把没排上的重建补出来。
    func testReleaseRestoresDocumentGeometry(_ require: (Bool, String) -> Void) {
        let refused = event(channel: "12", beat: 1, token: "RF", line: 1)
        let refusedLive = make(length: 8, events: [refused])
        acceptMoves = false
        guard let refusedHit = refusedLive.surface.chartLayout.eventRect(refused) else {
            require(false, "refused note missing")
            return
        }
        let refusedDown = CGPoint(x: refusedHit.hit.midX, y: refusedHit.hit.midY)
        let refusedDestination = lanePoint("13", beat: 3, on: refusedLive)
        send(.leftMouseDown, content: refusedDown, on: refusedLive)
        send(.leftMouseDragged, content: refusedDestination, on: refusedLive)
        settle(refusedLive)
        require(notes(token: "RF", ghost: true, on: refusedLive).count == 1, "refused drag drew no ghost")
        require(notes(token: "RF", ghost: false, on: refusedLive).isEmpty, "refused drag kept the original")
        send(.leftMouseUp, content: refusedDestination, on: refusedLive)
        require(moveBatches == 1 && singleMoves == 0, "refused release calls \(moveBatches) singles \(singleMoves)")
        requireReleased(refused, token: "RF", on: refusedLive, require)
        require(moveBatches == 1, "refused release wrote again after paint")

        let bad = event(channel: "11", beat: 1, token: "IV", line: 2)
        let invalid = make(length: 8, events: [bad])
        guard let badHit = invalid.surface.chartLayout.eventRect(bad) else {
            require(false, "illegal note missing")
            return
        }
        let badDown = CGPoint(x: badHit.hit.midX, y: badHit.hit.midY)
        let valid = lanePoint("13", beat: 3, on: invalid)
        let gutter = CGPoint(x: 8, y: invalid.surface.chartLayout.y(forBeat: 3))
        send(.leftMouseDown, content: badDown, on: invalid)
        send(.leftMouseDragged, content: valid, on: invalid)
        settle(invalid)
        require(!notes(token: "IV", ghost: true, on: invalid).isEmpty, "illegal setup lost the ghost")
        let batches = moveBatches
        send(.leftMouseUp, content: gutter, on: invalid)
        require(moveBatches == batches && singleMoves == 0, "illegal release wrote \(moveBatches - batches)")
        requireReleased(bad, token: "IV", on: invalid, require)

        let again = event(channel: "12", beat: 2, token: "ES", line: 3)
        let escape = make(length: 8, events: [again])
        guard let escapeHit = escape.surface.chartLayout.eventRect(again) else {
            require(false, "escape release note missing")
            return
        }
        let escapeDown = CGPoint(x: escapeHit.hit.midX, y: escapeHit.hit.midY)
        let escapeDestination = lanePoint("13", beat: 4, on: escape)
        send(.leftMouseDown, content: escapeDown, on: escape)
        send(.leftMouseDragged, content: escapeDestination, on: escape)
        settle(escape)
        require(!notes(token: "ES", ghost: true, on: escape).isEmpty, "escape setup lost the ghost")
        guard let cancel = key(53, characters: "\u{1b}", on: escape) else {
            require(false, "escape release event missing")
            return
        }
        escape.surface.keyDown(with: cancel)
        send(.leftMouseUp, content: escapeDestination, on: escape)
        require(moveBatches == 0 && singleMoves == 0, "escape then mouse up wrote \(moveBatches)")
        requireReleased(again, token: "ES", on: escape, require)

        let crossed = longNote(channel: "13", start: 1, end: 3, token: "CX", line: 4)
        let ends = make(length: 8, events: [], longs: [crossed])
        guard let endPaint = ends.surface.chartLayout.longNoteRect(crossed) else {
            require(false, "crossed long rect missing")
            return
        }
        let cap = CGPoint(x: endPaint.endHit.midX, y: endPaint.endHit.midY)
        let beforeTail = CGPoint(x: cap.x, y: ends.surface.chartLayout.y(forBeat: 0))
        let resizeBefore = resizes
        send(.leftMouseDown, content: cap, on: ends)
        send(.leftMouseDragged, content: beforeTail, on: ends)
        settle(ends)
        require(resizes == resizeBefore && moveBatches == 0, "crossed endpoint wrote during drag")
        require(notes(token: "CX", ghost: true, on: ends).isEmpty, "crossed endpoint drew an illegal ghost")
        require(notes(token: "CX", ghost: false, on: ends).count == 1, "crossed endpoint hid the original during drag")
        send(.leftMouseUp, content: beforeTail, on: ends)
        require(resizes == resizeBefore && startMoves == 0 && moveBatches == 0,
                "crossed endpoint committed resizes=\(resizes) starts=\(startMoves)")
        flushPaint(ends)
        let crossedPaint = ends.surface.presentedNotes
        let crossedBodies = notes(token: "CX", ghost: false, on: ends)
        require(notes(token: "CX", ghost: true, on: ends).isEmpty, "crossed endpoint left a ghost")
        require(crossedBodies.count == 1, "crossed endpoint hid the document note")
        if let body = crossedBodies.first {
            require(body.endBeat - body.beat > 0.000_001, "crossed endpoint painted an inverted long note")
            require(abs(body.beat - 1) < 0.001 && abs(body.endBeat - 3) < 0.001,
                    "crossed endpoint changed the document note \(body.beat) \(body.endBeat)")
        }
        ends.surface.exerciseFallbackPaint()
        require(ends.surface.presentedNotes == crossedPaint, "crossed endpoint fallback diverged")

        refusedLive.window.close()
        invalid.window.close()
        escape.window.close()
        ends.window.close()
    }

    private struct Live {
        let surface: ChartSurfaceView
        let window: NSWindow
    }

    private func make(
        length: Double,
        events: [ChartEventSnapshot] = [],
        longs: [LongNoteSnapshot] = [],
        bpm: Bool = false,
        bgm: Int = 0,
        viewHeight: CGFloat = 720
    ) -> Live {
        moveBatches = 0
        singleMoves = 0
        copies = 0
        resizes = 0
        startMoves = 0
        digitEvents = []
        lastShorts = []
        lastLongs = []
        acceptMoves = true
        acceptResizes = true
        let surface = ChartSurfaceView(frame: NSRect(x: 0, y: 0, width: 960, height: viewHeight))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: viewHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = surface
        surface.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        surface.tool = .select
        surface.previewOnClick = false
        surface.stopPreviewOnClick = false
        surface.disableFirstClick = false
        surface.snapEnabled = true
        surface.disableVerticalMove = false
        surface.moveBatchAtVPositionRequested = { [weak self] shorts, longs in
            self?.moveBatches += 1
            self?.lastShorts = shorts
            self?.lastLongs = longs
            return self?.acceptMoves ?? false
        }
        surface.moveRequested = { [weak self] _, _, _, _ in
            self?.singleMoves += 1
            return true
        }
        surface.moveAtPulseRequested = { [weak self] _, _, _ in
            self?.singleMoves += 1
            return true
        }
        surface.copyBatchAtVPositionRequested = { [weak self] _, _ in
            self?.copies += 1
            return true
        }
        surface.resizeLongNoteRequested = { [weak self] _, _, _ in
            self?.resizes += 1
            return self?.acceptResizes ?? false
        }
        surface.resizeLongAtPulseRequested = { [weak self] _, _ in
            self?.resizes += 1
            return self?.acceptResizes ?? false
        }
        surface.moveLongNoteStartRequested = { [weak self] _, _, _ in
            self?.startMoves += 1
            return true
        }
        surface.moveLongStartAtPulseRequested = { [weak self] _, _ in
            self?.startMoves += 1
            return true
        }
        surface.moveDigitRequested = { [weak self] digit, shift in
            self?.digitEvents.append((digit, shift))
        }
        let snapshot = ChartSnapshot(
            events: events,
            measures: [ChartMeasureSnapshot(measure: 0, start: 0, length: length)],
            diagnostics: [],
            editable: true,
            editingReason: ""
        )
        let longSet = LongNoteSnapshotSet(
            notes: longs,
            diagnostics: [],
            editable: true,
            editingReason: "",
            lnobjToken: ""
        )
        surface.update(
            snapshot: snapshot,
            longNotes: longSet,
            theme: .defaultTheme,
            side: .onePlayer,
            pixelsPerQuarterBeat: 48,
            division: 16,
            showsTwoPlayerColumns: false,
            bgmColumnCount: bgm,
            showsBPMColumn: bpm
        )
        sawMetal = sawMetal || surface.hasMetalRenderer
        settle(Live(surface: surface, window: window))
        return Live(surface: surface, window: window)
    }

    /// 只排空主队列。不主动 `synchronizePresentation`，否则松手没排队的重建也会被探测补上。
    private func flushPaint(_ live: Live) {
        var spun = false
        DispatchQueue.main.async { spun = true }
        let deadline = Date().addingTimeInterval(1)
        while !spun && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        _ = live.window.windowNumber
    }

    private func requireReleased(
        _ event: ChartEventSnapshot,
        token: String,
        on live: Live,
        _ require: (Bool, String) -> Void
    ) {
        flushPaint(live)
        let ghosts = notes(token: token, ghost: true, on: live)
        let bodies = notes(token: token, ghost: false, on: live)
        require(ghosts.isEmpty, "\(token) release left ghosts \(ghosts)")
        require(bodies.count == 1, "\(token) release bodies \(bodies)")
        if let body = bodies.first, let rect = live.surface.chartLayout.eventRect(event)?.rect {
            require(body.channel == event.channel && abs(body.beat - event.beat) < 0.001,
                    "\(token) release geometry \(body.channel) \(body.beat)")
            require(abs(body.contentRect.midX - rect.midX) < 0.5
                        && abs(body.contentRect.midY - rect.midY) < 0.5,
                    "\(token) release rect \(body.contentRect) document \(rect)")
        }
        let painted = live.surface.presentedNotes
        live.surface.exerciseFallbackPaint()
        require(live.surface.presentedNotes == painted, "\(token) fallback diverged from metal notes")
    }

    private func settle(_ live: Live) {
        live.surface.synchronizePresentation()
        var spun = false
        DispatchQueue.main.async { spun = true }
        let deadline = Date().addingTimeInterval(1)
        while !spun && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        live.surface.synchronizePresentation()
        let synced = live.surface.presentedNotes
        let passes = live.surface.presentedPaintPasses
        live.surface.exerciseFallbackPaint()
        if live.surface.presentedNotes != synced {
            paintFailures += 1
            print("FAIL fallback paint diverged from displayed notes")
        }
        if live.surface.presentedPaintPasses <= passes {
            paintFailures += 1
            print("FAIL fallback paint path did not run")
        }
    }

    private func notes(token: String, ghost: Bool, on live: Live) -> [ChartPresentedNote] {
        live.surface.presentedNotes.filter { $0.token == token && $0.ghost == ghost }
    }

    private func lanePoint(_ channel: String, beat: Double, on live: Live) -> CGPoint {
        let frame = live.surface.chartLayout.laneFrames[channel] ?? .zero
        return CGPoint(x: frame.midX, y: live.surface.chartLayout.y(forBeat: beat))
    }

    private func send(
        _ type: NSEvent.EventType,
        content: CGPoint,
        flags: NSEvent.ModifierFlags = [],
        on live: Live
    ) {
        guard let event = mouse(type, content: content, flags: flags, on: live) else { return }
        switch type {
        case .leftMouseDown:
            live.surface.mouseDown(with: event)
        case .leftMouseDragged:
            live.surface.mouseDragged(with: event)
        case .leftMouseUp:
            live.surface.mouseUp(with: event)
        default:
            break
        }
    }

    private func mouse(
        _ type: NSEvent.EventType,
        content: CGPoint,
        flags: NSEvent.ModifierFlags = [],
        on live: Live
    ) -> NSEvent? {
        let view = CGPoint(
            x: content.x - live.surface.scrollOffset.x,
            y: content.y - live.surface.scrollOffset.y
        )
        let windowPoint = live.surface.convert(view, to: nil)
        return NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: live.window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }

    private func key(_ keyCode: UInt16, characters: String, on live: Live) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: live.window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func scrollEvent(wheel: Int32) -> NSEvent? {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: wheel,
            wheel2: 0,
            wheel3: 0
        ) else { return nil }
        return NSEvent(cgEvent: cgEvent)
    }

    private func event(channel: String, beat: Double, token: String, line: Int) -> ChartEventSnapshot {
        ChartEventSnapshot(
            measure: 0,
            channel: channel,
            token: token,
            fractionNumerator: 0,
            fractionDenominator: 1,
            beat: beat,
            kind: "normalNote",
            sourceLine: line
        )
    }

    private func longNote(channel: String, start: Double, end: Double, token: String, line: Int) -> LongNoteSnapshot {
        LongNoteSnapshot(
            channel: channel,
            start: LongNoteEndpointSnapshot(
                measure: 0,
                fractionNumerator: 0,
                fractionDenominator: 1,
                beat: start,
                token: token,
                sourceLine: line
            ),
            end: LongNoteEndpointSnapshot(
                measure: 0,
                fractionNumerator: 0,
                fractionDenominator: 1,
                beat: end,
                token: token,
                sourceLine: line + 1
            ),
            encoding: "ln"
        )
    }
}
