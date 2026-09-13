import Foundation

@main
struct BmhelperMidiTests {
    static func main() {
        testLayoutNumbers()
        testImportControlText()
        testMinimalType1Fixture()
        testDefaultTrackSkipsEmpty()
        testCollectNoteEventsRespectsChannelMask()
        testEmptyAndBadBytes()
        testExtensions()
        testSmfOutMenuCopy()
        testSmfOutOneC4Bytes()
        testSmfOutEmptyTwoTracks()
        testSmfOutOneC4Roundtrip()
        testSmfOutDefaultClusterTimeline()
        testMidiViewGeometry()
        testDivisionTimelineBinding()
        testMidiViewWheel()
        testDropFirstSuccess()
        print("BmhelperMidiTests passed")
    }

    /// 对照 `mdview.cpp` `SetMidiData` / `GetNoteRect` / `OnMouseMotion`。
    /// 工作客户区 `800 × 300`，quantize `480`，一条 C4，滚动 `(0,0)`。
    /// `109226 * 480 / 65536` 向零是 799，不是客户区 800。
    private static func testMidiViewGeometry() {
        require(BmhelperMidiView.zoomBase == 65536, "zoom_base")
        require(
            BmhelperMidiView.workingClientSize == CGSize(width: 800, height: 300),
            "working client 800x300"
        )

        let client = BmhelperMidiView.Size(width: 800, height: 300)
        let scroll = BmhelperMidiView.Point(x: 0, y: 0)
        let note = MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        let metrics = BmhelperMidiView.metrics(notes: [note], quantize: 480, client: client)

        require(metrics.maxTime == 480, "max_time")
        require(metrics.minNn == 0, "min_nn")
        require(metrics.maxNn == 127, "max_nn")
        require(metrics.zoomRateX == 109226, "zoom_rate.x 800*65536/480")
        require(metrics.zoomRateY == 524288, "zoom_rate.y 65536*8")
        require(metrics.virtualWidth == 799, "virtual width toward zero")
        require(metrics.virtualHeight == 1024, "virtual height")
        require(metrics.ypos == 390, "initial ypos")
        require(metrics.hasData, "has data")

        let rect = BmhelperMidiView.noteRect(note: note, metrics: metrics, scroll: scroll)
        require(
            rect == BmhelperMidiView.Rect(x: 0, y: 536, width: 799, height: 8),
            "C4 rect integer GetNoteRect"
        )

        require(BmhelperMidiView.noteName(60) == "C  5", "C4 is C  5")
        require(BmhelperMidiView.noteName(63) == "D# 5", "D# 5")

        let center = BmhelperMidiView.Point(x: 399, y: 540)
        require(
            BmhelperMidiView.hoverText(at: center, metrics: metrics, scroll: scroll)
                == "Note#0 ( C  5 ) gate:480/480 vel:100",
            "hover center"
        )
        require(
            BmhelperMidiView.noteIndex(at: center, metrics: metrics, scroll: scroll) == 0,
            "noteIndex center"
        )

        let outside = BmhelperMidiView.Point(x: 400, y: 0)
        require(
            BmhelperMidiView.hoverText(at: outside, metrics: metrics, scroll: scroll) == "",
            "hover outside empty"
        )
        require(
            BmhelperMidiView.noteIndex(at: outside, metrics: metrics, scroll: scroll) == nil,
            "noteIndex outside nil"
        )

        let empty = BmhelperMidiView.metrics(notes: [], quantize: 480, client: client)
        require(empty.maxTime == 1, "empty max_time")
        require(empty.zoomRateX == 131072, "empty zoom_rate.x clamped")
        require(empty.virtualWidth == 2, "empty virtual width")
        require(empty.hasData, "empty list still has data")

        let none = BmhelperMidiView.metrics(notes: nil, quantize: 480, client: client)
        require(!none.hasData, "nil is no data")
        require(
            BmhelperMidiView.hoverText(at: center, metrics: none, scroll: scroll) == "",
            "no data hover empty"
        )
        require(
            BmhelperMidiView.noteIndex(at: center, metrics: none, scroll: scroll) == nil,
            "no data noteIndex nil"
        )
        require(
            BmhelperStatus.fields(
                hasProject: true,
                selectedName: "melody",
                notes: 1,
                definitions: 1,
                sourceNotes: 1,
                hover: "Note#0 ( C  5 ) gate:480/480 vel:100"
            ) == ["Note#0 ( C  5 ) gate:480/480 vel:100", "melody: 1n/1d", "source: 1n"],
            "hover left column"
        )
    }

    /// 对照 `divedit.cpp` `SetDivision`：第二份钢琴卷绑时间线，不是源 MIDI。
    /// 几何仍走 BH-MIDIVIEW 那套 799 宽。
    private static func testDivisionTimelineBinding() {
        let sourceTwo = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 1000, gate: 480, noteNum: 60, velocity: 100)
        ]
        let clusteredOne = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        require(
            BmhelperMidiView.notesToShow(
                source: sourceTwo,
                timeline: clusteredOne,
                hasSelection: false
            ) == nil,
            "no selection is no data"
        )

        let differentCount = BmhelperMidiView.notesToShow(
            source: sourceTwo,
            timeline: clusteredOne,
            hasSelection: true
        )
        require(differentCount == clusteredOne, "selection uses timeline not source")
        require(differentCount?.count == 1, "bind count 1 not 2")
        require(differentCount?[0].position == 0, "default cluster at 0")

        let velSource = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 20),
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        ]
        let velTimeline = [
            MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100),
            MidiNoteEvent(position: 960, gate: 480, noteNum: 60, velocity: 20)
        ]
        let split = BmhelperMidiView.notesToShow(
            source: velSource,
            timeline: velTimeline,
            hasSelection: true
        )
        require(split?.count == 2, "vel split two timeline notes")
        require(split?[0].position == 0 && split?[1].position == 960, "timeline 0 and 960")
        require(split?[0].position != velSource[1].position || velSource[1].position == 0, "not source positions")

        let client = BmhelperMidiView.Size(width: 800, height: 300)
        let scroll = BmhelperMidiView.Point(x: 0, y: 0)
        let oneC4 = MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        let shown = BmhelperMidiView.notesToShow(
            source: [oneC4],
            timeline: [oneC4],
            hasSelection: true
        )
        let metrics = BmhelperMidiView.metrics(notes: shown, quantize: 480, client: client)
        let rect = BmhelperMidiView.noteRect(note: oneC4, metrics: metrics, scroll: scroll)
        require(
            rect == BmhelperMidiView.Rect(x: 0, y: 536, width: 799, height: 8),
            "timeline C4 still 799-wide"
        )
        require(BmhelperMidiView.noteName(60) == "C  5", "timeline name still C  5")

        let none = BmhelperMidiView.notesToShow(
            source: sourceTwo,
            timeline: clusteredOne,
            hasSelection: false
        )
        let emptyMetrics = BmhelperMidiView.metrics(notes: none, quantize: 480, client: client)
        require(!emptyMetrics.hasData, "no data metrics")
        require(
            BmhelperMidiView.hoverText(
                at: BmhelperMidiView.Point(x: 399, y: 540),
                metrics: emptyMetrics,
                scroll: scroll
            ) == "",
            "no data hover empty"
        )
    }

    /// 对照 `mdview.cpp` `OnMouseWheel`。客户区 `800 × 300`，一条 C4，quantize 480。
    /// 起始 `zoom_rate.x == 109226`，`y == 524288`，滚动 `(0, 390)`。
    /// 滚轮向上对照 `GetWheelRotation()>0`。Command 对照 ControlDown。
    /// 滚动夹到 `[0, max(vs-cls, 0)]`。第 11 条夹完后 `px == 0`。
    private static func testMidiViewWheel() {
        let client = BmhelperMidiView.Size(width: 800, height: 300)
        let note = MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)
        let start = BmhelperMidiView.metrics(notes: [note], quantize: 480, client: client)
        let startScroll = BmhelperMidiView.Point(x: 0, y: 390)
        require(start.zoomRateX == 109226, "wheel start x")
        require(start.zoomRateY == 524288, "wheel start y")
        require(start.ypos == 390, "wheel start ypos")
        require(start.virtualWidth == 799, "wheel start vs.x")
        require(start.virtualHeight == 1024, "wheel start vs.y")
        require(
            BmhelperMidiView.noteRect(
                note: note,
                metrics: start,
                scroll: BmhelperMidiView.Point(x: 0, y: 0)
            ) == BmhelperMidiView.Rect(x: 0, y: 536, width: 799, height: 8),
            "old MIDIVIEW rect (0, 536, 799, 8)"
        )

        let none = BmhelperMidiView.metrics(notes: nil, quantize: 480, client: client)
        let noneScroll = BmhelperMidiView.Point(x: 12, y: 34)
        let noneWheel = BmhelperMidiView.applyWheel(
            metrics: none,
            scroll: noneScroll,
            client: client,
            command: true,
            shift: true,
            up: true
        )
        require(noneWheel.metrics == none, "no data metrics unchanged")
        require(noneWheel.scroll == noneScroll, "no data scroll unchanged")

        let zoomXUp = BmhelperMidiView.applyWheel(
            metrics: start,
            scroll: startScroll,
            client: client,
            command: true,
            shift: true,
            up: true
        )
        require(zoomXUp.metrics.zoomRateX == 131072, "109226*4/3=145634 clamp to 131072")
        require(zoomXUp.scroll.x == 80, "px=(int)(400.0*131072/109226)-400")
        require(zoomXUp.metrics.virtualWidth == 960, "131072*480/65536")

        let zoomXDown = BmhelperMidiView.applyWheel(
            metrics: start,
            scroll: startScroll,
            client: client,
            command: true,
            shift: true,
            up: false
        )
        require(zoomXDown.metrics.zoomRateX == 81919, "109226*3/4")

        let zoomYUp = BmhelperMidiView.applyWheel(
            metrics: start,
            scroll: startScroll,
            client: client,
            command: true,
            shift: false,
            up: true
        )
        require(zoomYUp.metrics.zoomRateY == 699050, "524288*4/3")

        let zoomYDown = BmhelperMidiView.applyWheel(
            metrics: start,
            scroll: startScroll,
            client: client,
            command: true,
            shift: false,
            up: false
        )
        require(zoomYDown.metrics.zoomRateY == 393216, "524288*3/4")

        var floorY = start
        floorY.zoomRateY = 65536
        floorY.virtualHeight = 65536 * 128 / 65536
        let zoomYFloor = BmhelperMidiView.applyWheel(
            metrics: floorY,
            scroll: startScroll,
            client: client,
            command: true,
            shift: false,
            up: false
        )
        require(zoomYFloor.metrics.zoomRateY == 65536, "vertical min stays 65536")

        var floorX = start
        floorX.zoomRateX = 16384
        floorX.virtualWidth = 16384 * 480 / 65536
        let zoomXFloor = BmhelperMidiView.applyWheel(
            metrics: floorX,
            scroll: startScroll,
            client: client,
            command: true,
            shift: true,
            up: false
        )
        require(zoomXFloor.metrics.zoomRateX == 16384, "horizontal min stays 16384")

        let scrollY = BmhelperMidiView.applyWheel(
            metrics: start,
            scroll: startScroll,
            client: client,
            command: false,
            shift: false,
            up: true
        )
        require(
            BmhelperMidiView.scrollStep(
                horizontal: false,
                zoomRate: 524288,
                quantize: 480,
                up: true
            ) == -8,
            "vertical step 8"
        )
        require(scrollY.scroll.y == 382, "390-8")

        let scrollXBlocked = BmhelperMidiView.applyWheel(
            metrics: start,
            scroll: startScroll,
            client: client,
            command: false,
            shift: true,
            up: true
        )
        require(
            BmhelperMidiView.scrollStep(
                horizontal: true,
                zoomRate: 109226,
                quantize: 480,
                up: true
            ) == -799,
            "horizontal step 799"
        )
        require(scrollXBlocked.scroll.x == 0, "cls.x < vs.x is false, no scroll")
        require(scrollXBlocked.metrics == start, "blocked scroll keeps metrics")

        let afterZoomX = zoomXUp
        let scrollXAfterZoom = BmhelperMidiView.applyWheel(
            metrics: afterZoomX.metrics,
            scroll: afterZoomX.scroll,
            client: client,
            command: false,
            shift: true,
            up: true
        )
        require(afterZoomX.metrics.virtualWidth == 960, "zoomed vs.x 960")
        require(scrollXAfterZoom.scroll.x == 0, "80-799 clamped to 0")
    }

    /// 对照 `OnDropFiles`：前面失败继续，第一个成功用下标 1。
    private static func testDropFirstSuccess() {
        let index = BmhelperDrop.firstSuccess(["bad.mid", "ok.mid"]) { file in
            file == "ok.mid"
        }
        require(index == 1, "first success is ok.mid")
        require(
            BmhelperDrop.firstSuccess(["bad.mid", "also-bad.mid"]) { $0 == "ok.mid" } == nil,
            "all fail"
        )
        require(
            BmhelperDrop.dropFailedMessage("/tmp/a.mid") == "Couldn't open file:\r\n/tmp/a.mid",
            "drop failed has path"
        )
    }

    /// Type 1、一轨、480 tick、C4（nn=60）vel=100，gate=480。
    /// 构造步骤见 `makeType1OneNoteC4()`。
    private static func testMinimalType1Fixture() {
        let data = makeType1OneNoteC4()
        let file: BmhelperMidiFile
        switch BmhelperMidi.parse(data) {
        case .success(let parsed):
            file = parsed
        case .failure(let error):
            fail("parse fixture: \(error)")
        }

        require(file.format == 1, "SMF type 1")
        require(file.ticksPerQuarter == 480, "ticks per quarter")
        require(file.tracks.count == 1, "one track")
        require(file.tracks[0].name == "melody", "track name meta 0x03")
        require(file.tracks[0].index == 0, "track index")
        require(file.defaultSelectedTrackIndex == 0, "default first used track")
        require(file.tracks[0].channelsUsed[0], "channel 0 used")
        require(file.tracks[0].channelsUsed.dropFirst().allSatisfy { !$0 }, "other channels unused")
        require(file.tracks[0].notes.count == 1, "one paired note")

        let note = file.tracks[0].notes[0]
        require(note.tick == 0, "note tick")
        require(note.gate == 480, "note gate")
        require(note.note == 60, "C4 nn")
        require(note.velocity == 100, "velocity")
        require(note.channel == 0, "channel")

        let settings = BmhelperMidiImportSettings.makeDefault(for: file)
        require(settings.selectedTrackIndex == 0, "settings default track")
        require(settings.channelMask == Array(repeating: true, count: 16), "all channels on")
        let events = BmhelperMidi.collectNoteEvents(from: file, settings: settings)
        require(events.count == 1, "one MidiNoteEvent")
        require(events[0] == MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100), "SmfReader note")
    }

    private static func testDefaultTrackSkipsEmpty() {
        let data = makeType1ConductorThenNote()
        switch BmhelperMidi.parse(data) {
        case .success(let file):
            require(file.tracks.count == 2, "two tracks")
            require(file.tracks[0].name == "tempo", "conductor name")
            require(!file.tracks[0].channelsUsed.contains(true), "conductor has no notes")
            require(file.defaultSelectedTrackIndex == 1, "first track with notes")
        case .failure(let error):
            fail("parse two-track: \(error)")
        }
    }

    private static func testCollectNoteEventsRespectsChannelMask() {
        switch BmhelperMidi.parse(makeType1OneNoteC4()) {
        case .success(let file):
            var settings = BmhelperMidiImportSettings.makeDefault(for: file)
            settings.channelMask[0] = false
            require(BmhelperMidi.collectNoteEvents(from: file, settings: settings).isEmpty, "masked channel")
        case .failure(let error):
            fail("parse for mask: \(error)")
        }
    }

    private static func testLayoutNumbers() {
        require(
            BmhelperMidiImportSettings.title == "MIDI file import settings",
            "import title"
        )
        require(
            BmhelperMidiImportSettings.sourceSize == CGSize(width: 290, height: 130),
            "import 290x130"
        )
        require(BmhelperMidiImportSettings.hasCloseBox == false, "no close box")
        require(
            BmhelperMidiImportSettings.tracksLabel == CGRect(x: 5, y: 8, width: 85, height: 15),
            "Tracks label"
        )
        require(BmhelperMidiImportSettings.tracksTitle == "Tracks (&T):", "Tracks text")
        require(BmhelperMidiImportLayout.clientSize == CGSize(width: 290, height: 130), "layout client")
        require(BmhelperMidiImportLayout.title == "MIDI file import settings", "layout title")
        require(BmhelperMidiImportLayout.tracksChoice == CGRect(x: 95, y: 5, width: 185, height: 22), "Tracks choice")
        require(BmhelperMidiImportLayout.channelsTitle == "Channels (&C):", "Channels text")
        require(BmhelperMidiImportLayout.okTitle == "OK", "OK text")
        require(BmhelperMidiImportLayout.ok == CGRect(x: 200, y: 105, width: 80, height: 20), "OK frame")
        require(
            BmhelperMidiImportLayout.channelFrame(0) == CGRect(x: 95, y: 34, width: 42, height: 16),
            "channel 00 frame"
        )
        require(
            BmhelperMidiImportLayout.channelFrame(15)
                == CGRect(x: 95 + 3 * 44, y: 34 + 3 * 18, width: 42, height: 16),
            "channel 0F frame"
        )
        require(BmhelperMainLayout.clientSize == CGSize(width: 1000, height: 700), "main redesigned size")
        require(BmhelperDefTransposeLayout.clientSize == CGSize(width: 200, height: 120), "transpose unchanged")
        require(BmhelperDefDialogLayout.clientSize == CGSize(width: 400, height: 300), "def unchanged")
    }

    /// 对照 `midi_smfin.cpp`：轨名 `%04X: %s`，通道 `%02X`。
    private static func testImportControlText() {
        require(BmhelperMidiImportText.trackChoice(index: 0, name: "melody") == "0000: melody", "first track")
        require(BmhelperMidiImportText.trackChoice(index: 1, name: "tempo") == "0001: tempo", "second track")
        require(BmhelperMidiImportText.channelTitle(0) == "00", "channel 00")
        require(BmhelperMidiImportText.channelTitle(15) == "0F", "channel 0F")
    }

    private static func testEmptyAndBadBytes() {
        switch BmhelperMidi.parse(Data()) {
        case .success:
            fail("empty file should fail")
        case .failure(let error):
            require(error == .emptyFile, "empty file error")
        }

        switch BmhelperMidi.parse(Data([0x00, 0x01, 0x02])) {
        case .success:
            fail("bad bytes should fail")
        case .failure(let error):
            require(error == .invalidHeader || error == .truncated, "bad bytes error")
        }

        switch BmhelperMidi.parse(Data("MThd".utf8)) {
        case .success:
            fail("truncated header should fail")
        case .failure(let error):
            require(error == .truncated || error == .invalidHeader, "truncated header")
        }
    }

    private static func testExtensions() {
        require(BmhelperMidi.fileExtensions == ["mid", "midi", "smf"], "project.cpp extensions")
    }

    /// 对照 `frame.cpp` / `divedit.cpp` `_SmfOut` 文案。
    private static func testSmfOutMenuCopy() {
        require(
            BmhelperSmfOut.menuTitle == "Write modified MIDI File (&M)...",
            "smf out menu"
        )
        require(
            BmhelperSmfOut.failedMessage == "Failed to export MIDI file.",
            "smf out failed"
        )
        require(BmhelperSmfOut.saveTitle == "MIDI files", "save title")
        require(BmhelperSmfOut.defaultExtension == "mid", "default mid")
        require(
            BmhelperSmfOut.shouldExport(hasProject: false, hasSelection: true) == false,
            "no project no export"
        )
        require(
            BmhelperSmfOut.shouldExport(hasProject: true, hasSelection: false) == false,
            "no selection no export"
        )
    }

    /// 对照 `midi_smfout.cpp`：Type 1、两轨、480 tick、一条 C4。
    /// 轨 0 只有 EOT；轨 1 是 NoteOn + delta 480=`83 60` + NoteOff + EOT。
    private static func testSmfOutOneC4Bytes() {
        let data = BmhelperMidi.encode(
            quantize: 480,
            notes: [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        )
        require(hex(data) == oneC4SmfHex, "one C4 smf bytes")
    }

    /// 空音符仍写 Type 1、两轨、480；两轨都是 `00 FF 2F 00`。
    private static func testSmfOutEmptyTwoTracks() {
        let data = BmhelperMidi.encode(quantize: 480, notes: [])
        require(hex(data) == emptySmfHex, "empty two-track smf")
    }

    /// 夹具 3 的 Data 交给已有 `parse`：format=1，ticks=480，2 轨，第 1 轨一条 C4。
    private static func testSmfOutOneC4Roundtrip() {
        let data = BmhelperMidi.encode(
            quantize: 480,
            notes: [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        )
        switch BmhelperMidi.parse(data) {
        case .success(let file):
            require(file.format == 1, "roundtrip format")
            require(file.ticksPerQuarter == 480, "roundtrip ticks")
            require(file.tracks.count == 2, "roundtrip two tracks")
            require(file.tracks[0].notes.isEmpty, "conductor has no notes")
            require(file.tracks[1].notes.count == 1, "note track one note")
            let note = file.tracks[1].notes[0]
            require(note.tick == 0, "roundtrip tick")
            require(note.gate == 480, "roundtrip gate")
            require(note.note == 60, "roundtrip nn")
            require(note.velocity == 100, "roundtrip vel")
            require(note.channel == 0, "roundtrip ch")
        case .failure(let error):
            fail("parse encoded C4: \(error)")
        }
    }

    /// 默认聚类一条 C4 的时间线就是这条 C4；encode 必须和夹具 3 相同。
    private static func testSmfOutDefaultClusterTimeline() {
        let timeline = [MidiNoteEvent(position: 0, gate: 480, noteNum: 60, velocity: 100)]
        let data = BmhelperMidi.encode(quantize: 480, notes: timeline)
        require(hex(data) == oneC4SmfHex, "timeline C4 matches fixture")
    }

    /// Type 1、2 轨、480；轨 0 空 EOT；轨 1 一条 C4。
    private static let oneC4SmfHex =
        "4D546864000000060001000201E04D54726B0000000400FF2F004D54726B0000000D00903C648360803C0000FF2F00"

    /// Type 1、2 轨、480；两轨都只有 EOT。
    private static let emptySmfHex =
        "4D546864000000060001000201E04D54726B0000000400FF2F004D54726B0000000400FF2F00"

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    /// 最小合法 Type 1：
    /// 1. `MThd`，长度 6，格式 1，1 轨，division=480。
    /// 2. `MTrk`：delta 0 + meta 0x03 `melody`；
    ///    delta 0 + note on 通道 0、C4=60、vel=100；
    ///    delta 480 + note off；delta 0 + End of Track。
    private static func makeType1OneNoteC4() -> Data {
        var track = [UInt8]()
        appendMeta(&track, delta: 0, type: 0x03, payload: Array("melody".utf8))
        appendDelta(&track, 0)
        track += [0x90, 60, 100]
        appendDelta(&track, 480)
        track += [0x80, 60, 0]
        appendMeta(&track, delta: 0, type: 0x2F, payload: [])
        return wrapSmf(format: 1, ticks: 480, tracks: [track])
    }

    /// 第一轨只有名字，没有音符；第二轨有 C4。
    private static func makeType1ConductorThenNote() -> Data {
        var conductor = [UInt8]()
        appendMeta(&conductor, delta: 0, type: 0x03, payload: Array("tempo".utf8))
        appendMeta(&conductor, delta: 0, type: 0x2F, payload: [])

        var notes = [UInt8]()
        appendDelta(&notes, 0)
        notes += [0x90, 60, 100]
        appendDelta(&notes, 480)
        notes += [0x80, 60, 0]
        appendMeta(&notes, delta: 0, type: 0x2F, payload: [])
        return wrapSmf(format: 1, ticks: 480, tracks: [conductor, notes])
    }

    private static func wrapSmf(format: Int, ticks: Int, tracks: [[UInt8]]) -> Data {
        var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06]
        appendU16(&bytes, format)
        appendU16(&bytes, tracks.count)
        appendU16(&bytes, ticks)
        for track in tracks {
            bytes += [0x4D, 0x54, 0x72, 0x6B]
            appendU32(&bytes, track.count)
            bytes += track
        }
        return Data(bytes)
    }

    private static func appendMeta(_ dest: inout [UInt8], delta: Int, type: UInt8, payload: [UInt8]) {
        appendDelta(&dest, delta)
        dest += [0xFF, type]
        appendDelta(&dest, payload.count)
        dest += payload
    }

    private static func appendDelta(_ dest: inout [UInt8], _ value: Int) {
        var chunks: [UInt8] = []
        var remaining = value & 0x0FFF_FFFF
        chunks.append(UInt8(remaining & 0x7F))
        remaining >>= 7
        while remaining != 0 {
            chunks.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        dest += chunks.reversed()
    }

    private static func appendU16(_ dest: inout [UInt8], _ value: Int) {
        dest.append(UInt8((value >> 8) & 0xFF))
        dest.append(UInt8(value & 0xFF))
    }

    private static func appendU32(_ dest: inout [UInt8], _ value: Int) {
        dest.append(UInt8((value >> 24) & 0xFF))
        dest.append(UInt8((value >> 16) & 0xFF))
        dest.append(UInt8((value >> 8) & 0xFF))
        dest.append(UInt8(value & 0xFF))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
