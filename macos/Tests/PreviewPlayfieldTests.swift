import AppKit
import CryptoKit
import Foundation
import ImageIO

@main
struct PreviewPlayfieldTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        testSevenKeyNotesFallOntoTheJudgmentLine()
        testLongNoteHeadTailAndViewportSpan()
        testHistoricalNotesAreSkippedWithoutDroppingHeldNotes()
        testEmptyChartAndUnplayableNotes()
        testDoublePlayFitsAndScrollSpeedIsClamped()
        testIrregularMeasuresAndBeatLines()
        testMetalReadbackMatchesNoteColorsAndPlayback()
        testPlayerSideFiltersLanesAndPixels()
        testMetalResourcesStayCached()
        testAttachedMetalViewDrawsFromPlayback()
        testHundredThousandNotesBuildVisibleGeometryOnly()
        testMissingMetalStaysExplicit()
        testOriginalAtlasPixelsAndPlaybackFrame()
        testScratchStatesAndKeyCapChannels()
        testBeatClockAndStopLifetimes()
        testDualClockRates()
        testTimeIndexMatchesSlowIntegral()
        testFiniteTailAndPlayerJudges()
        testHiddenHoldTailRecoveryAndLogicClock()
        testBombCoversKeyCapAndInternalDrawOrder()
        testLongNoteGlowStaysThroughTheHold()
        print("PreviewPlayfieldTests passed")
    }

    /// 键帽附加按通道号。四态 scratch 连键盘底图一起换块，效果位只开关 GREAT、爆炸和键帽光束。
    @MainActor
    private static func testScratchStatesAndKeyCapChannels() {
        let capOffset: [Int: [CGFloat]] = [
            11: [3, 2, 3, 2],
            12: [2, 1, 2, 1],
            16: [2, 2, 2, 2],
            21: [2, 2, 3, 3],
            22: [1, 1, 2, 2],
            23: [3, 2, 3, 2],
            24: [2, 1, 2, 1],
            25: [3, 2, 3, 2],
            26: [2, 2, 2, 2],
            28: [2, 1, 2, 1],
            29: [3, 2, 3, 2]
        ]
        for (channel, row) in capOffset {
            for state in 0..<4 {
                require(
                    PreviewUbmStyle.keyCapXOffset(channel: channel, scratchRaw: state) == row[state],
                    "channel \(channel) scratch \(state) cap offset \(row[state])"
                )
            }
        }
        require(PreviewUbmStyle.clampedScratch(-4) == 0 && PreviewUbmStyle.clampedScratch(8) == 3, "scratch raw stays inside 0...3")
        require(PreviewUbmStyle.clampedEffects(-1) == 0 && PreviewUbmStyle.clampedEffects(8) == 0 && PreviewUbmStyle.clampedEffects(15) == 7, "unknown effect bits are dropped")

        let twoPlayer = (1...7).map { PreviewVisualLane(id: "p2k\($0)", title: "\($0)", player: 2) }
            + [PreviewVisualLane(id: "p2s", title: "S", isScratch: true, player: 2)]
        let placed = PreviewUbmStyle.nativeColumns(for: twoPlayer)
        let laneX: [Int: CGFloat] = [21: 174, 22: 193, 23: 209, 24: 228, 25: 244, 26: 298, 28: 263, 29: 279]
        for column in placed {
            require(column.rect.minX == laneX[column.channel], "2P channel \(column.channel) x is \(laneX[column.channel] ?? -1), got \(column.rect.minX)")
        }
        let scratchOnly = [PreviewVisualLane(id: "s", title: "S", isScratch: true)]
        let scratchX = [1, 125, 1, 125]
        for state in 0..<4 {
            let column = PreviewUbmStyle.nativeColumns(for: scratchOnly, scratchRaw: state)[0]
            require(column.rect.minX == CGFloat(scratchX[state]) && column.channel == 16, "1P scratch state \(state)")
            let panels = PreviewUbmStyle.backgroundPanels(scratchRaw: state, autoSeparate: true)
            require(panels[0].sourceX == (state & 1 == 0 ? 0 : 173) && panels[0].destX == 0, "1P panel \(state)")
            require(panels[1].sourceX == (state & 2 == 0 ? 173 : 0) && panels[1].destX == 173, "2P panel \(state)")
        }
        require(PreviewUbmStyle.nativeColumns(for: scratchOnly, autoSeparate: false)[0].rect.minX == 1, "331 stays packed when autoSeparate is off")
        let packedOff = PreviewUbmStyle.backgroundPanels(scratchRaw: 1, autoSeparate: false)
        require(packedOff[0].destX == 0 && packedOff[1].destX == 173, "autoSeparate off keeps both panels inside 331")

        guard let skin0 = calibratedPng(named: "skin_00.png"), let skin1 = calibratedPng(named: "skin_01.png") else {
            fail("missing atlas for the appearance oracle")
        }
        let view = makeView(width: 331, height: 256)
        requireMetal(view)
        for state in 0..<4 {
            view.setUbmAppearance(scratchRaw: state, effectsRaw: 7, autoSeparate: true)
            view.setChart(PreviewChartSnapshot(title: "Scratch", lanes: scratchOnly, notes: [], barBeats: [], endBeat: 8))
            view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
            let image = view.renderMetalReadback()
            requireMetalReadback(image)
            var diff = 0
            for y in [10, 100, 240, 250] {
                for x in 0..<331 {
                    guard let got = image.components(x: x, y: y), let want = appearancePixel(skin0, x: x, y: y, state: state) else {
                        fail("missing appearance pixel \(x),\(y)")
                    }
                    if !near(got, want, tolerance: 0) { diff += 1 }
                }
            }
            print("appearance-scratch-\(state)-diff=\(diff)")
            writePNG(image, name: "appearance-scratch-\(state).png")
            require(diff == 0, "scratch \(state) background differs by \(diff)")
            view.setChart(PreviewChartSnapshot(
                title: "Scratch Notes",
                lanes: scratchOnly + [PreviewVisualLane(id: "k", title: "1")],
                notes: [
                    PreviewVisualNote(laneID: "s", startBeat: 1, endBeat: 1),
                    PreviewVisualNote(laneID: "k", startBeat: 1, endBeat: 1)
                ],
                barBeats: [],
                endBeat: 8
            ))
            view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
            let notes = view.renderMetalReadback()
            requireMetalReadback(notes)
            writePNG(notes, name: "appearance-notes-\(state).png")
        }

        // effects 5 = bit0 判定 + bit2 键帽，没有 bit1 爆炸。隔离键帽，避免 96 爆炸盖住 skin_01 采样点。
        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 5, autoSeparate: true)
        view.setChart(PreviewChartSnapshot(
            title: "Caps",
            lanes: twoPlayer,
            notes: twoPlayer.map { PreviewVisualNote(laneID: $0.id, startBeat: 4, endBeat: 4) },
            barBeats: [],
            endBeat: 8
        ))
        view.setTiming(PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: []), fromBeat: 4)
        view.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        let caps = view.renderMetalReadback()
        requireMetalReadback(caps)
        for lane in view.currentScene().lanes {
            let offset = capOffset[lane.channel]?[0] ?? -1
            let localX: CGFloat
            let atlasX: Int
            switch lane.kind {
            case .white:
                localX = 0
                atlasX = 69
            case .blue:
                localX = 0
                atlasX = 83
            case .scratch:
                localX = 10
                atlasX = 106
            }
            let point = CGPoint(
                x: lane.rect.minX + offset + localX + 0.2,
                y: PreviewUbmStyle.keyCapNativeY(kind: lane.kind) + 0.2
            )
            let pixel = sample(caps, point, viewSize: view.bounds.size)
            guard let want = skin1.rgb(atlasX, 139) else { fail("missing cap texel") }
            require(near(pixel, want, tolerance: 0), "channel \(lane.channel) cap at \(point) is \(pixel), skin_01 \(want)")
        }
        writePNG(caps, name: "appearance-caps-2p.png")

        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 0, autoSeparate: true)
        let hidden = view.renderMetalReadback()
        requireMetalReadback(hidden)
        let capPoint = CGPoint(x: 174 + 2 + 0.2, y: 233.2)
        let hiddenCap = sample(hidden, capPoint, viewSize: view.bounds.size)
        guard let capInk = skin1.rgb(69, 139) else { fail("missing white cap ink") }
        require(!near(hiddenCap, capInk, tolerance: 0), "effects 0 still draws the key cap \(hiddenCap)")
        let hiddenGreat = sample(hidden, CGPoint(x: 37.2, y: 162.2), viewSize: view.bounds.size)
        require(!near(hiddenGreat, (1, 1, 0), tolerance: 0.04), "effects 0 still draws GREAT \(hiddenGreat)")
        writePNG(hidden, name: "appearance-effects-0.png")
        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 7, autoSeparate: false)
        view.setChart(PreviewChartSnapshot(title: "Single", lanes: scratchOnly, notes: [], barBeats: [], endBeat: 4))
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        let singleImage = view.renderMetalReadback()
        requireMetalReadback(singleImage)
        var packedDiff = 0
        for y in [10, 100, 240, 250] {
            for x in 0..<331 {
                guard let got = singleImage.components(x: x, y: y), let want = skin0.rgb(x, y) else {
                    fail("missing packed pixel \(x),\(y)")
                }
                if !near(got, want, tolerance: 0) { packedDiff += 1 }
            }
        }
        print("appearance-packed-off-diff=\(packedDiff)")
        require(packedDiff == 0, "autoSeparate off still moves the 331 background, diff \(packedDiff)")
        writePNG(singleImage, name: "appearance-single.png")
    }

    private static func appearancePixel(_ image: PngTopLeft, x: Int, y: Int, state: Int) -> (Double, Double, Double)? {
        var sourceX = x
        if x < 158, state & 1 != 0 { sourceX = 173 + x }
        if (173..<331).contains(x), state & 2 != 0 { sourceX = x - 173 }
        return image.rgb(sourceX, y)
    }

    /// 7 键：scratch / 白键 / 蓝键分开上色，短音前沿在当前拍落到判定线，BGM 车道不画。
    @MainActor
    private static func testSevenKeyNotesFallOntoTheJudgmentLine() {
        let view = makeView(width: 760, height: 680)
        view.pixelsPerBeat = 40
        view.setChart(sevenKeyChart())
        require(view.playerSide == .both, "playback starts on both sides")
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        let approaching = view.currentScene()
        let scratch = tryMark(approaching, lane: "scratch", part: .short)
        let white = tryMark(approaching, lane: "k1", part: .short)
        let blue = tryMark(approaching, lane: "k2", part: .short)
        require(approaching.marks.allSatisfy { $0.laneID != "bgm" }, "BGM lane must not become a playable note")
        require(scratch.kind == .scratch && white.kind == .white && blue.kind == .blue, "scratch, white and blue keys keep their own colors")
        require(scratch.rect.midX < white.rect.midX && white.rect.midX < blue.rect.midX, "7-key order is scratch, then white, then blue")
        require(scratch.rect.maxY < approaching.judgmentY - 90, "a later note starts above the judgment line")
        require(view.laneTitleFrames.isEmpty, "the skin already draws the keys, so lane names are not painted on top")
        let scale = PreviewUbmStyle.placement(in: view.bounds.size).scale
        let overlayRevision = view.textOverlayRevision

        view.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: true)
        let hitting = view.currentScene()
        let landed = tryMark(hitting, lane: "k1", part: .short)
        require(abs(landed.rect.maxY - hitting.judgmentY) < 0.6, "short-note front edge lands on the judgment line at its beat")
        require(landed.rect.maxY > white.rect.maxY, "the same note moves downward as playback advances")
        require(abs((landed.rect.maxY - white.rect.maxY) - CGFloat(4 * view.pixelsPerBeat) * scale) < 1.2, "downward travel follows native pixels per beat after uniform scaling")
        require(hitting.accessibilityTitle == "Falling Keys", "accessibility title uses the chart title")
        require(hitting.accessibilityStatus.contains("正在播放") && hitting.accessibilityStatus.contains("4.00"), "accessibility status reports playback and the current beat")
        require(view.accessibilityLabel() == hitting.accessibilityStatus, "view accessibility label matches the scene status")
        require(view.accessibilityValue() as? String == "4.00", "view accessibility value is the current beat")
        require(view.textOverlayRevision == overlayRevision, "playback does not redraw lane titles")
        require(view.rendersFromExternalPlayback, "Metal view stays paused and waits for setPlayback")

        view.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: false)
        let stopped = view.currentScene()
        require(stopped.marks == hitting.marks, "stopping does not move notes")
        require(stopped.accessibilityStatus.contains("已停止"), "stopped playback is announced")
    }

    /// 长音要有头、尾和主体。开始于屏幕外、结束于屏幕外的长音仍然穿过画面。
    @MainActor
    private static func testLongNoteHeadTailAndViewportSpan() {
        let view = makeView(width: 420, height: 640)
        view.pixelsPerBeat = 80
        var chart = PreviewChartSnapshot(title: "Hold", endBeat: 32)
        chart.lanes = [PreviewVisualLane(id: "k1", title: "1", isScratch: false)]
        chart.notes = [PreviewVisualNote(laneID: "k1", startBeat: 2, endBeat: 6)]
        chart.barBeats = [0, 4]
        view.setChart(chart)
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        let visible = view.currentScene()
        let body = tryMark(visible, lane: "k1", part: .body)
        let head = tryMark(visible, lane: "k1", part: .head)
        let tail = tryMark(visible, lane: "k1", part: .tail)
        require(head.rect.midY > tail.rect.midY, "the long-note head is below the tail while notes fall downward")
        require(body.rect.minY < head.rect.minY && body.rect.maxY > tail.rect.maxY, "the body connects the head and the tail")
        let scale = PreviewUbmStyle.placement(in: view.bounds.size).scale
        require(abs(body.rect.height - CGFloat(4 * view.pixelsPerBeat) * scale) < 1.5, "body length follows the held beats in native pixels")

        chart.notes = [PreviewVisualNote(laneID: "k1", startBeat: 0, endBeat: 40)]
        view.setChart(chart)
        view.setPlayback(beat: 10, elapsedSeconds: 5, isPlaying: true)
        let spanning = view.currentScene()
        let span = tryMark(spanning, lane: "k1", part: .body)
        require(span.rect.minY < 0 && span.rect.maxY > view.bounds.height, "a held note that starts and ends offscreen still crosses the viewport")
        require(span.rect.intersects(view.bounds), "the crossing hold is not dropped")
        require(!spanning.marks.contains { $0.part == .head && $0.rect.intersects(view.bounds) }, "the already-passed head stays below the viewport")
        require(!spanning.marks.contains { $0.part == .tail && $0.rect.intersects(view.bounds) }, "the future tail stays above the viewport")

        let readback = view.renderMetalReadback()
        requireMetalReadback(readback)
        let lane = spanning.lanes[0]
        let frame = PreviewUbmStyle.longFrame(playbackBeat: 10)
        let sprite = PreviewUbmStyle.noteSprite(kind: .white, part: .body, frame: frame)
        require(
            sprite.rect == CGRect(x: 69, y: 73 + CGFloat(frame & 3) * 6, width: 18, height: 5),
            "hold body follows skin_01 y=73, frame \(frame) rect \(sprite.rect)"
        )
        guard let directory = PreviewUbmStyle.skinDirectory(),
              let probe = rasterize(directory.appendingPathComponent("skin_00.png"), reverseRows: false) else {
            fail("missing skin_00 for the hold oracle")
        }
        let reverseRows = !(exactRGB(probe, 0, 0, 156, 158, 156) && exactRGB(probe, 40, 219, 0, 255, 0))
        guard let sheet = rasterize(directory.appendingPathComponent("skin_01.png"), reverseRows: reverseRows),
              let expected = sheet.rgb(Int(sprite.rect.minX) + 9, Int(sprite.rect.minY) + 2) else {
            fail("missing hold body source pixel")
        }
        let center = sample(readback, CGPoint(x: lane.rect.midX, y: view.bounds.midY), viewSize: view.bounds.size)
        let bodyMatches = countPixelsNear(
            readback,
            x: lane.rect.midX,
            rgb: expected,
            viewSize: view.bounds.size,
            tolerance: 0
        )
        writePNG(readback, name: "playfield-long-span.png")
        require(near(center, expected, tolerance: 0), "hold center matches skin_01 \(sprite.rect) \(center) expected \(expected)")
        require(bodyMatches > 20, "the stretched hold repeats that source row, matched \(bodyMatches)")
    }

    /// 几万个已经结束的短音不能被逐个扫到；仍覆盖当前画面的长音必须留下。
    @MainActor
    private static func testHistoricalNotesAreSkippedWithoutDroppingHeldNotes() {
        var notes: [PreviewVisualNote] = []
        notes.reserveCapacity(80_003)
        for beat in 0..<80_000 {
            notes.append(PreviewVisualNote(laneID: "old", startBeat: Double(beat), endBeat: Double(beat)))
        }
        notes.append(PreviewVisualNote(laneID: "hold", startBeat: 0, endBeat: 120_000))
        notes.append(PreviewVisualNote(laneID: "now", startBeat: 90_003, endBeat: 90_003))
        var index = PreviewPlayfieldNoteIndex(notes: notes.reversed())
        let started = Date()
        var visits = 0
        for _ in 0..<300 {
            let visible = index.visibleNotes(bottomBeat: 89_998.5, topBeat: 90_006, capBeats: 0.2)
            visits = index.lastNodeVisits
            require(visible.count == 2, "only the held note and the note inside the window are visible")
            require(visible.contains { $0.laneID == "hold" && $0.endBeat == 120_000 }, "a hold that began at beat 0 is still visible")
            require(visible.contains { $0.laneID == "now" }, "the note inside the window is visible")
            require(!visible.contains { $0.laneID == "old" }, "finished notes behind the window are not returned")
        }
        let elapsed = Date().timeIntervalSince(started)
        require(visits < 250, "visible lookup visited \(visits) tree nodes; historical notes were scanned")
        print(String(format: "historical-note queries: visits=%d elapsed=%.4fs", visits, elapsed))

        let view = makeView(width: 360, height: 240)
        view.pixelsPerBeat = 96
        view.setChart(PreviewChartSnapshot(
            title: "Seek",
            lanes: [
                PreviewVisualLane(id: "old", title: "O"),
                PreviewVisualLane(id: "hold", title: "H"),
                PreviewVisualLane(id: "now", title: "N")
            ],
            notes: [
                PreviewVisualNote(laneID: "old", startBeat: 1, endBeat: 1),
                PreviewVisualNote(laneID: "hold", startBeat: 0, endBeat: 800),
                PreviewVisualNote(laneID: "now", startBeat: 400, endBeat: 400)
            ],
            barBeats: [0],
            endBeat: 800
        ))
        view.setPlayback(beat: 400, elapsedSeconds: 200, isPlaying: true)
        let scene = view.currentScene()
        require(!scene.marks.contains { $0.laneID == "old" }, "a finished short note is not drawn after seeking ahead")
        require(scene.marks.contains { $0.laneID == "hold" && $0.part == .body }, "the held note is drawn after seeking into it")
        require(scene.emptyMessage == nil, "seeking into a chart that still has notes is not an empty chart")
        require(scene.accessibilityStatus.contains("正在播放"), "playback status remains while old notes are offscreen")
    }

    @MainActor
    private static func testEmptyChartAndUnplayableNotes() {
        let view = makeView(width: 760, height: 680)
        let blank = view.currentScene()
        require(blank.emptyMessage == "没有可预览的谱面", "a view with no chart explains that")
        require(blank.marks.isEmpty && blank.lanes.isEmpty, "an empty chart draws no lanes")
        require(view.accessibilityTitle() == "预览", "missing title falls back to a generic preview name")
        require(view.displayedOverlayMessage == "没有可预览的谱面", "the empty state is an overlay string")
        let emptyImage = view.renderMetalReadback()
        requireMetalReadback(emptyImage)
        let backdrop = sample(emptyImage, CGPoint(x: 20, y: 20), viewSize: view.bounds.size)
        require(matches(backdrop, PreviewPlayfieldPalette.background), "an empty chart clears through Metal \(backdrop)")
        writePNG(emptyImage, name: "playfield-empty.png")

        view.setChart(PreviewChartSnapshot(
            title: "Keys Only",
            lanes: [PreviewVisualLane(id: "k1", title: "1")],
            notes: [PreviewVisualNote(laneID: "bgm", startBeat: 2, endBeat: 2)],
            barBeats: [0, 4],
            endBeat: 8
        ))
        let unplayable = view.currentScene()
        require(unplayable.emptyMessage == "没有可玩音符", "lanes without a playable note say so")
        require(unplayable.marks.isEmpty, "a BGM-only note is not drawn on a key lane")
        require(!unplayable.lanes.isEmpty, "key lanes stay visible when no playable notes exist")
        require(view.accessibilityLabel() == "没有可玩音符", "accessibility repeats the empty-note state")
    }

    @MainActor
    private static func testDoublePlayFitsAndScrollSpeedIsClamped() {
        let lanes = doublePlayLanes()
        let narrow = PreviewPlayfieldLayout.laneFrames(
            for: lanes,
            in: CGRect(x: 0, y: 0, width: 320, height: 500)
        )
        require(narrow.count == 16, "double play keeps both sides")
        require(narrow.allSatisfy { $0.rect.width > 1 && $0.rect.minX >= -0.1 && $0.rect.maxX <= 320.6 }, "16 lanes stay inside a narrow window")
        require(
            narrow.prefix(8).contains { $0.kind == .scratch } && narrow.suffix(8).contains { $0.kind == .scratch },
            "each side has a scratch lane"
        )
        let wide = PreviewPlayfieldLayout.laneFrames(
            for: lanes,
            in: CGRect(x: 0, y: 0, width: 1600, height: 500)
        )
        require(wide.allSatisfy { $0.rect.maxX <= 1600.6 && $0.rect.minX >= -0.1 }, "lanes do not run past a wide window")
        require((wide.map(\.rect.maxX).max() ?? 0) - (wide.map(\.rect.minX).min() ?? 0) < 1500, "lanes stay a playfield width instead of stretching across the whole window")
        let scratchWidth = narrow.first { $0.kind == .scratch }?.rect.width ?? 0
        let keyWidth = narrow.first { $0.kind == .white }?.rect.width ?? 0
        require(scratchWidth > keyWidth, "scratch columns stay wider than white keys")

        let view = makeView(width: 760, height: 680)
        view.pixelsPerBeat = 10_000
        require(abs(view.pixelsPerBeat - PreviewPlayfieldMetrics.maximumPixelsPerBeat) < 0.001, "scroll speed caps at the maximum")
        view.pixelsPerBeat = -4
        require(abs(view.pixelsPerBeat - PreviewPlayfieldMetrics.minimumPixelsPerBeat) < 0.001, "non-positive scroll speed uses the minimum")
        view.pixelsPerBeat = .nan
        require(abs(view.pixelsPerBeat - PreviewPlayfieldMetrics.defaultPixelsPerBeat) < 0.001, "a non-finite scroll speed returns to the default")
        view.pixelsPerBeat = .infinity
        require(abs(view.pixelsPerBeat - PreviewPlayfieldMetrics.defaultPixelsPerBeat) < 0.001, "infinite scroll speed returns to the default")
    }

    /// 小节可以不是 4 拍。小节线和整拍线要跟着真实小节起点走。
    @MainActor
    private static func testIrregularMeasuresAndBeatLines() {
        let view = makeView(width: 480, height: 680)
        view.pixelsPerBeat = 16
        view.setChart(PreviewChartSnapshot(
            title: "Meters",
            lanes: [PreviewVisualLane(id: "k1", title: "1")],
            notes: [PreviewVisualNote(laneID: "k1", startBeat: 1, endBeat: 1)],
            barBeats: [0, 3, 7, 3],
            endBeat: 9
        ))
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        let scene = view.currentScene()
        let scale = PreviewUbmStyle.placement(in: view.bounds.size).scale
        guard let bar0 = scene.measureLineYs.min(by: { abs($0 - scene.judgmentY) < abs($1 - scene.judgmentY) }) else {
            fail("missing the opening bar line")
        }
        require(abs(bar0 - scene.judgmentY) < 1, "the opening bar sits on the judgment line when playback is at beat 0")
        func lineY(atBeat beat: Double) -> CGFloat {
            bar0 - CGFloat(beat * view.pixelsPerBeat) * scale
        }
        func hasMeasure(atBeat beat: Double) -> Bool {
            scene.measureLineYs.contains { abs($0 - lineY(atBeat: beat)) < 1.2 }
        }
        func hasBeat(atBeat beat: Double) -> Bool {
            scene.beatLineYs.contains { abs($0 - lineY(atBeat: beat)) < 1.2 }
        }
        require(hasMeasure(atBeat: 3) && hasMeasure(atBeat: 7), "bar lines follow the real 3-beat then 4-beat measures")
        require(hasMeasure(atBeat: 9), "the chart end is marked when it is not already a bar")
        require(hasBeat(atBeat: 1) && hasBeat(atBeat: 2), "whole beats inside a measure stay visible")
        require(!hasBeat(atBeat: 0) && !hasBeat(atBeat: 3), "a bar line is not also drawn as a beat line")
        require(!scene.measureLineYs.contains { abs($0 - lineY(atBeat: 1)) < 1.2 }, "beat 1 is not promoted to a bar")
    }

    /// 离屏路径必须读回 Metal 纹理。布局矩形不能代替这次像素检查。
    @MainActor
    private static func testMetalReadbackMatchesNoteColorsAndPlayback() {
        let view = makeView(width: 760, height: 680)
        requireMetal(view)
        view.pixelsPerBeat = 32
        view.setChart(sevenKeyChart())
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        let earlyScene = view.currentScene()
        let earlyNote = tryMark(earlyScene, lane: "k1", part: .short)
        let earlyImage = view.renderMetalReadback()
        requireMetalReadback(earlyImage)
        let earlyPoint = CGPoint(x: earlyNote.rect.midX, y: earlyNote.rect.minY + 0.5)
        let earlyPixel = sample(earlyImage, earlyPoint, viewSize: view.bounds.size)
        require(earlyPixel.r > 0.9 && earlyPixel.g > 0.9 && earlyPixel.b > 0.9, "the upcoming white chip's top row is in the Metal texture \(earlyPixel)")

        view.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: true)
        let scene = view.currentScene()
        let readback = view.renderMetalReadback()
        requireMetalReadback(readback)
        writePNG(readback, name: "playfield-7k-beat4.png")
        let scratch = tryMark(scene, lane: "scratch", part: .short)
        let blue = tryMark(scene, lane: "k2", part: .short)
        let landed = tryMark(scene, lane: "k1", part: .short)
        require(scratch.rect.maxY > scene.judgmentY - 2 && blue.rect.maxY > scene.judgmentY - 2, "scratch and blue notes reach the judgment line")
        require(landed.rect.midX > scratch.rect.midX && blue.rect.midX > landed.rect.midX, "landed notes keep scratch, white, blue order")
        let vacated = sample(readback, earlyPoint, viewSize: view.bounds.size)
        require(
            abs(vacated.r - earlyPixel.r) > 0.05 || abs(vacated.g - earlyPixel.g) > 0.05 || abs(vacated.b - earlyPixel.b) > 0.05,
            "the note's earlier position changed after it moved \(vacated)"
        )
        guard let scratchLane = scene.lanes.first(where: { $0.kind == .scratch }) else {
            fail("scratch lane is laid out")
        }
        let placement = scene.placement
        let judgmentPoint = CGPoint(x: scratchLane.rect.midX, y: scene.judgmentY + placement.scale * 0.5)
        let judgment = sample(earlyImage, judgmentPoint, viewSize: view.bounds.size)
        require(judgment.g > 0.9 && judgment.r < 0.08 && judgment.b < 0.08, "the judgment row is the skin's green, not a white stroke \(judgment)")
        let margin = sample(earlyImage, CGPoint(x: view.bounds.midX, y: 4), viewSize: view.bounds.size)
        require(matches(margin, PreviewPlayfieldPalette.background), "the letterbox keeps the clear color \(margin)")
        require(view.pipelineCompileCount == 1, "the shader pipeline is compiled once")
        require(view.rendersFromExternalPlayback, "color readback still leaves the view clock paused")
    }

    @MainActor
    private static func testPlayerSideFiltersLanesAndPixels() {
        let view = makeView(width: 331, height: 256)
        requireMetal(view)
        view.pixelsPerBeat = 48
        view.setChart(PreviewChartSnapshot(
            title: "Sides",
            lanes: doublePlayLanes(),
            notes: [
                PreviewVisualNote(laneID: "1p-k1", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "2p-sc", startBeat: 4, endBeat: 4)
            ],
            barBeats: [0, 4],
            endBeat: 8
        ))
        view.setPlayback(beat: 2, elapsedSeconds: 0, isPlaying: true)
        let both = view.currentScene()
        require(both.lanes.count == 16, "both keeps 1P and 2P")
        require(both.visibleNoteCount == 2, "both sides keep their notes")
        let bothImage = view.renderMetalReadback()
        requireMetalReadback(bothImage)
        writePNG(bothImage, name: "playfield-dp.png")
        let white = tryMark(both, lane: "1p-k1", part: .short)
        let scratch = tryMark(both, lane: "2p-sc", part: .short)
        require(white.rect.midX < 157 && scratch.rect.midX > 298, "1P white stays left of the gauge and 2P scratch stays on the right")
        let whitePoint = CGPoint(x: 43.2, y: 120.2)
        let scratchPoint = CGPoint(x: 314.2, y: 120.2)
        let sideFrame = PreviewUbmStyle.shortFrame(playbackBeat: 2)
        guard let sideSheet = calibratedPng(named: "skin_01.png") else { fail("missing skin_01 for the side-frame oracle") }
        let whiteSprite = PreviewUbmStyle.noteSprite(kind: .white, part: .short, frame: sideFrame)
        let scratchSprite = PreviewUbmStyle.noteSprite(kind: .scratch, part: .short, frame: sideFrame)
        guard let whiteColor = sideSheet.rgb(Int(whiteSprite.rect.minX) + 9, Int(whiteSprite.rect.minY) + 2),
              let scratchColor = sideSheet.rgb(Int(scratchSprite.rect.minX) + 16, Int(scratchSprite.rect.minY) + 2) else {
            fail("missing side-frame texels")
        }
        require(
            near(sample(bothImage, whitePoint, viewSize: view.bounds.size), whiteColor),
            "1P white note matches skin_01 frame \(sideFrame)"
        )
        require(
            near(sample(bothImage, scratchPoint, viewSize: view.bounds.size), scratchColor),
            "2P scratch note matches skin_01 frame \(sideFrame)"
        )

        view.setPlayerSide(.onePlayer)
        let one = view.currentScene()
        require(one.lanes.count == 8, "1P keeps eight lanes")
        require(one.lanes.allSatisfy { $0.id.hasPrefix("1p") }, "1P hides 2P lanes")
        require(!one.marks.contains { $0.laneID.hasPrefix("2p") }, "1P drops 2P notes")
        require(one.visibleNoteCount == 1, "only the 1P note remains visible")
        let oneImage = view.renderMetalReadback()
        requireMetalReadback(oneImage)
        writePNG(oneImage, name: "playfield-1p.png")
        let oneNote = tryMark(one, lane: "1p-k1", part: .short)
        require(oneNote.rect.midX < 80, "the 1P note stays on the left scratch side")
        require(
            near(sample(oneImage, whitePoint, viewSize: view.bounds.size), whiteColor),
            "the 1P note is still the white chip after the side switch"
        )
        require(
            near(sample(oneImage, scratchPoint, viewSize: view.bounds.size), skinPixel(314, 120)),
            "1P leaves the 2P scratch column as skin_00"
        )

        view.setPlayerSide(.twoPlayer)
        let two = view.currentScene()
        require(two.lanes.count == 8 && two.lanes.allSatisfy { $0.id.hasPrefix("2p") }, "2P keeps only its lanes")
        require(two.visibleNoteCount == 1, "only the 2P note remains visible")
        let twoImage = view.renderMetalReadback()
        requireMetalReadback(twoImage)
        writePNG(twoImage, name: "playfield-2p.png")
        let twoNote = tryMark(two, lane: "2p-sc", part: .short)
        require(twoNote.rect.minX > 290, "2P scratch is the right-hand disc")
        require(
            near(sample(twoImage, scratchPoint, viewSize: view.bounds.size), scratchColor),
            "the 2P scratch note is drawn on its own"
        )
        require(
            near(sample(twoImage, whitePoint, viewSize: view.bounds.size), skinPixel(43, 120)),
            "2P leaves the 1P white column as skin_00"
        )

        view.setPlayerSide(.both)
        require(view.currentScene().lanes.count == 16, "switching back to both restores every lane")

        let single = makeView(width: 760, height: 680)
        single.pixelsPerBeat = 96
        single.setChart(sevenKeyChart())
        single.setPlayback(beat: 4, elapsedSeconds: 1, isPlaying: false)
        single.setPlayerSide(.twoPlayer)
        let hidden = single.currentScene()
        require(hidden.lanes.isEmpty && hidden.emptyMessage == "没有可玩音符", "a 1P chart has nothing to show on 2P")
        let hiddenImage = single.renderMetalReadback()
        requireMetalReadback(hiddenImage)
        require(countPixels(hiddenImage, matching: PreviewPlayfieldPalette.whiteNote) == 0, "filtered-out notes are not rasterized")
        let cleared = sample(hiddenImage, CGPoint(x: 30, y: 30), viewSize: single.bounds.size)
        require(matches(cleared, PreviewPlayfieldPalette.background), "a side with no lanes clears to the background \(cleared)")
    }

    @MainActor
    private static func testMetalResourcesStayCached() {
        let view = makeView(width: 640, height: 480)
        requireMetal(view)
        view.pixelsPerBeat = 96
        view.setChart(sevenKeyChart())
        view.setPlayback(beat: 4, elapsedSeconds: 1, isPlaying: true)
        require(view.pipelineCompileCount == 1, "pipeline compile happens when the view is created")
        for _ in 0..<3 {
            requireMetalReadback(view.renderMetalReadback())
        }
        let allocated = view.vertexBufferAllocationCount
        require(allocated == 3, "three in-flight vertex buffers are allocated, got \(allocated)")
        for _ in 0..<3 {
            requireMetalReadback(view.renderMetalReadback())
        }
        require(view.vertexBufferAllocationCount == 3, "later frames reuse the vertex buffers")
        require(view.pipelineCompileCount == 1, "more frames do not compile the shader again")
        require(view.inFlightLimit >= 3, "at least three frames may be in flight")
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 620)
        view.layoutSubtreeIfNeeded()
        requireMetalReadback(view.renderMetalReadback())
        require(view.pipelineCompileCount == 1, "resize keeps the compiled pipeline")
        require(view.vertexBufferAllocationCount == 3, "resize reuses the vertex buffer cache, got \(view.vertexBufferAllocationCount)")
        require(view.rendersFromExternalPlayback, "resize does not start an internal Metal clock")

        let pipeline = view.pipelineCompileCount
        let buffers = view.vertexBufferAllocationCount
        view.holdInFlightSlotsForTesting()
        let skips = view.skippedLiveFrameCount
        let skipStarted = DispatchTime.now().uptimeNanoseconds
        view.submitLiveFrameNow()
        let skipElapsed = Double(DispatchTime.now().uptimeNanoseconds &- skipStarted) / 1_000_000_000
        require(view.skippedLiveFrameCount == skips + 1, "a full in-flight ring skips the live frame instead of waiting")
        require(skipElapsed < 0.05, String(format: "skipping a live frame blocked for %.4fs", skipElapsed))
        require(view.pipelineCompileCount == pipeline, "a skipped frame must not compile a pipeline")
        require(view.vertexBufferAllocationCount == buffers, "a skipped frame must not allocate a vertex buffer")
        view.releaseInFlightSlotsForTesting()
        requireMetalReadback(view.renderMetalReadback())
        require(view.pipelineCompileCount == pipeline, "offscreen readback reuses the pipeline")
        require(view.vertexBufferAllocationCount == buffers, "offscreen readback reuses the three vertex buffers")
    }

    /// 挂到窗口上的 MTKView 必须能拿到 drawable 并提交，而不是只靠离屏纹理。
    @MainActor
    private static func testAttachedMetalViewDrawsFromPlayback() {
        let view = makeView(width: 320, height: 240)
        requireMetal(view)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame = window.contentView?.bounds ?? view.frame
        view.layoutSubtreeIfNeeded()
        view.pixelsPerBeat = 96
        view.setChart(sevenKeyChart())
        view.setPlayback(beat: 4, elapsedSeconds: 1, isPlaying: true)
        window.displayIfNeeded()
        let presented = view.drawMetalViewNow()
        require(presented, "MTKView did not present a drawable after setPlayback")
        require(view.rendersFromExternalPlayback, "the attached view still has no internal clock")
        require(view.pipelineCompileCount == 1, "the window drawable reuses the same pipeline")
        window.orderOut(nil)
    }

    /// 10 万颗已经结束的 1P 音排在前面，当前看 2P，再加几万条小节线。测的是筛选和构几何，不是读回等待。
    @MainActor
    private static func testHundredThousandNotesBuildVisibleGeometryOnly() {
        let view = makeView(width: 360, height: 240)
        requireMetal(view)
        view.pixelsPerBeat = 96
        var notes: [PreviewVisualNote] = []
        notes.reserveCapacity(100_003)
        for beat in 0..<100_000 {
            notes.append(PreviewVisualNote(laneID: "1p", startBeat: Double(beat), endBeat: Double(beat)))
        }
        notes.append(PreviewVisualNote(laneID: "2p-hold", startBeat: 0, endBeat: 320_000))
        notes.append(PreviewVisualNote(laneID: "2p-now", startBeat: 200_000, endBeat: 200_000))
        var bars: [Double] = []
        bars.reserveCapacity(40_001)
        for index in 0..<40_000 {
            bars.append(Double(index) * 8)
        }
        bars.append(3)
        view.setChart(PreviewChartSnapshot(
            title: "Dense Sides",
            lanes: [
                PreviewVisualLane(id: "1p", title: "1", player: 1),
                PreviewVisualLane(id: "2p-hold", title: "H", player: 2),
                PreviewVisualLane(id: "2p-now", title: "N", player: 2)
            ],
            notes: notes,
            barBeats: bars,
            endBeat: 320_000
        ))
        view.setPlayerSide(.twoPlayer)
        let overlayRevision = view.textOverlayRevision
        let pipeline = view.pipelineCompileCount
        let buffers = view.vertexBufferAllocationCount
        var selectSamples: [Double] = []
        var vertexSamples: [Double] = []
        var totalSamples: [Double] = []
        selectSamples.reserveCapacity(20)
        for step in 0..<20 {
            view.setPlayback(beat: 200_000 + Double(step) * 0.01, elapsedSeconds: Double(step) * 0.01, isPlaying: true)
            selectSamples.append(view.lastVisibleSelectSeconds)
            vertexSamples.append(view.lastVertexAssemblySeconds)
            totalSamples.append(view.lastGeometryBuildSeconds)
        }
        func average(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(values.count)
        }
        let selectAverage = average(selectSamples)
        let vertexAverage = average(vertexSamples)
        let totalAverage = average(totalSamples)
        let scene = view.currentScene()
        require(scene.lanes.allSatisfy { $0.id.hasPrefix("2p") }, "the timed frames are the 2P side")
        require(scene.emptyMessage == nil, "2P still has playable notes behind the 1P history")
        require(scene.visibleNoteCount == 2, "only the 2P hold and the 2P note stay visible, got \(scene.visibleNoteCount)")
        require(!scene.marks.contains { $0.laneID == "1p" }, "historical 1P notes are not visible on 2P")
        require(!scene.measureLineYs.isEmpty, "a dense bar list still yields the visible measures")
        require(view.lastVertexCount > 0 && view.lastVertexCount < 2_000, "visible geometry stayed small, got \(view.lastVertexCount) vertices")
        require(selectAverage < 0.02, String(format: "visible select averaged %.6fs", selectAverage))
        require(vertexAverage < 0.02, String(format: "vertex assembly averaged %.6fs", vertexAverage))
        require(totalAverage < 0.02, String(format: "CPU filter plus geometry averaged %.6fs", totalAverage))
        require(view.pipelineCompileCount == pipeline, "playback frames did not compile another pipeline")
        require(view.vertexBufferAllocationCount == buffers, "playback frames did not allocate vertex buffers")
        require(view.textOverlayRevision == overlayRevision, "dense playback does not rebuild lane title layers")
        let readback = view.renderMetalReadback()
        requireMetalReadback(readback)
        let now = tryMark(scene, lane: "2p-now", part: .short)
        require(now.kind == .blue, "the second 2P key is the blue column")
        guard let hold = scene.lanes.first(where: { $0.id == "2p-hold" }) else {
            fail("missing 2P hold lane")
        }
        let frame = PreviewUbmStyle.longFrame(playbackBeat: scene.playbackBeat)
        let sprite = PreviewUbmStyle.noteSprite(kind: .white, part: .body, frame: frame)
        require(
            sprite.rect == CGRect(x: 69, y: 73 + CGFloat(frame & 3) * 6, width: 18, height: 5),
            "2P hold uses the y=73 body table"
        )
        guard let directory = PreviewUbmStyle.skinDirectory(),
              let probe = rasterize(directory.appendingPathComponent("skin_00.png"), reverseRows: false) else {
            fail("missing skin_00 for the 2P hold oracle")
        }
        let reverseRows = !(exactRGB(probe, 0, 0, 156, 158, 156) && exactRGB(probe, 40, 219, 0, 255, 0))
        guard let sheet = rasterize(directory.appendingPathComponent("skin_01.png"), reverseRows: reverseRows) else {
            fail("missing skin_01 for the 2P hold oracle")
        }
        let sourceX = Int(sprite.rect.minX) + 9
        let rows = (0..<5).compactMap { sheet.rgb(sourceX, Int(sprite.rect.minY) + $0) }
        require(rows.count == 5, "body sprite has five source rows")
        let center = sample(readback, CGPoint(x: hold.rect.midX, y: view.bounds.midY), viewSize: view.bounds.size)
        guard let matched = rows.first(where: { near(center, $0, tolerance: 0) }) else {
            fail("2P hold center \(center) is not a texel of skin_01 \(sprite.rect)")
        }
        let holdMatches = countPixelsNear(
            readback,
            x: hold.rect.midX,
            rgb: matched,
            viewSize: view.bounds.size,
            tolerance: 0
        )
        require(holdMatches > 8, "the 2P hold repeats its skin_01 body row, matched \(holdMatches)")
        require(view.pipelineCompileCount == pipeline, "readback did not compile another pipeline")
        print(String(
            format: "visible-select avg=%.6fs vertex-assembly avg=%.6fs cpu-total avg=%.6fs notes=%d vertices=%d bars=%d samples=%d",
            selectAverage,
            vertexAverage,
            totalAverage,
            view.lastVisibleNoteCount,
            view.lastVertexCount,
            bars.count,
            totalSamples.count
        ))
        print(String(
            format: "offscreen-gpu-wait=%.4fs (not a screen frame rate)",
            view.lastOffscreenWaitSeconds
        ))
    }

    /// 331×256 读回对照 skin_00，2× 最近邻不糊，击打帧可重复，文字和提交接口可用。
    @MainActor
    private static func testOriginalAtlasPixelsAndPlaybackFrame() {
        require(PreviewUbmStyle.canvasSize == CGSize(width: 587, height: 256), "canvas is 587×256")
        require(PreviewUbmStyle.playfieldSize == CGSize(width: 331, height: 256), "playfield is 331×256")
        require(PreviewUbmStyle.bgaSize == CGSize(width: 256, height: 256), "BGA slot is 256×256")
        guard let skinDirectory = PreviewUbmStyle.skinDirectory() else {
            fail("original skin directory is required for this acceptance")
        }
        setenv("IBMS_UBM_SKIN_DIR", "/tmp/ibms-missing-ubm-skin", 1)
        let fellThrough = PreviewUbmStyle.skinDirectory()?.standardizedFileURL.path
        unsetenv("IBMS_UBM_SKIN_DIR")
        require(fellThrough == skinDirectory.standardizedFileURL.path, "a missing override falls through to the reference atlas")
        setenv("IBMS_UBM_SKIN_DIR", skinDirectory.path, 1)
        let preferred = PreviewUbmStyle.skinDirectory()?.standardizedFileURL.path
        unsetenv("IBMS_UBM_SKIN_DIR")
        require(preferred == skinDirectory.standardizedFileURL.path, "IBMS_UBM_SKIN_DIR is preferred when the atlas is complete")

        let columns = PreviewUbmStyle.nativeColumns(for: doublePlayLanes())
        require(columns.count == 16, "double play has 16 native columns")
        require(columns[0].kind == .scratch && columns[0].rect.minX == 1 && columns[0].rect.width == 32, "1P scratch is the left 32px disc")
        require(columns[8].kind == .scratch && columns[8].rect.minX == 298 && columns[8].rect.width == 32, "2P scratch is the right 32px disc")
        require(columns[9].rect.minX == 174 && columns[9].rect.minX < columns[8].rect.minX, "2P keys sit left of the right scratch")

        guard let oracle = calibratedPng(named: "skin_00.png") else {
            fail("could not read skin_00.png as top-left")
        }
        require(exactRGB(oracle, 0, 0, 156, 158, 156), "PNG oracle (0,0) is the measured gray")
        require(exactRGB(oracle, 40, 219, 0, 255, 0), "PNG oracle keeps the green judgment line")
        guard let decoded = PreviewUbmStyle.loadAtlas(named: "skin_00.png", in: skinDirectory),
              decoded.width == 331, decoded.height == 256 else {
            fail("skin_00 did not load at 331×256")
        }
        var decodeDiff = 0
        for y in 0..<256 {
            for x in 0..<331 {
                guard let got = decoded.components(x: x, y: y), let want = oracle.rgb(x, y) else {
                    fail("missing decoded pixel \(x),\(y)")
                }
                if !near(got, want, tolerance: 0) { decodeDiff += 1 }
            }
        }
        print("loadAtlas-vs-png-diff=\(decodeDiff)")
        require(decodeDiff == 0, "loadAtlas must match the top-left PNG, differed by \(decodeDiff)")
        let body = PreviewUbmStyle.noteSprite(kind: .white, part: .body, frame: 0)
        require(body.rect == CGRect(x: 69, y: 73, width: 18, height: 5), "long-note body source is y=73")
        let short = PreviewUbmStyle.noteSprite(kind: .white, part: .short, frame: 0)
        require(short.rect == CGRect(x: 69, y: 1, width: 18, height: 5), "short note source is y=1")
        let greatSprite = PreviewUbmStyle.greatSprite(frame: 0)
        require(greatSprite.rect == CGRect(x: 9, y: 106, width: 81, height: 14), "GREAT source is 81×14 at y=106")
        require(PreviewUbmStyle.centeredAsciiOriginX(characterCount: 4) == 277.5, "ASCII centering is (587 - 8*count)/2")
        let skin = oracle

        let quiet = makeView(width: 331, height: 256)
        requireMetal(quiet)
        guard case .original = quiet.skinMode else {
            fail("acceptance must use the original atlas, got \(quiet.skinMode)")
        }
        quiet.pixelsPerBeat = 96
        quiet.setChart(PreviewChartSnapshot(
            title: "Skin",
            lanes: sevenKeyChart().lanes,
            notes: [PreviewVisualNote(laneID: "k1", startBeat: 80, endBeat: 80)],
            barBeats: [],
            endBeat: 200
        ))
        quiet.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        let quietScene = quiet.currentScene()
        let quietImage = quiet.renderMetalReadback()
        requireMetalReadback(quietImage)
        require(quietImage.width == 331 && quietImage.height == 256, "readback stays at the native playfield size")
        let guideRows = guideRows(in: quietScene, height: 256)
        var mismatches: [(x: Int, y: Int)] = []
        var mismatchCount = 0
        for y in 0..<256 where !guideRows.contains(y) {
            for x in 0..<331 {
                guard let got = quietImage.components(x: x, y: y), let want = skin.rgb(x, y) else {
                    fail("missing pixel \(x),\(y)")
                }
                if !near(got, want, tolerance: 0) {
                    mismatchCount += 1
                    if mismatches.count < 8 { mismatches.append((x, y)) }
                }
            }
        }
        print("skin00-readback-diff=\(mismatchCount) excluded-guide-rows=\(guideRows.count)")
        require(mismatchCount == 0, "skin_00 readback differs by \(mismatchCount) at \(mismatches)")
        let judged = sample(quietImage, CGPoint(x: 40.2, y: 219.2), viewSize: quiet.bounds.size)
        require(near(judged, (0, 1, 0), tolerance: 0), "readback judgment pixel is 0,255,0 \(judged)")
        writePNG(quietImage, name: "skin-readback-331.png")
        writeCanvas(playfield: quietImage, name: "playfield-canvas-587.png")

        let doubled = makeView(width: 662, height: 512)
        doubled.pixelsPerBeat = 96
        doubled.setChart(quiet.currentScene().lanes.isEmpty ? sevenKeyChart() : PreviewChartSnapshot(
            title: "Skin",
            lanes: sevenKeyChart().lanes,
            notes: [PreviewVisualNote(laneID: "k1", startBeat: 80, endBeat: 80)],
            barBeats: [],
            endBeat: 200
        ))
        doubled.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        let doubledImage = doubled.renderMetalReadback()
        requireMetalReadback(doubledImage)
        require(doubledImage.width == 662 && doubledImage.height == 512, "2× readback is 662×512")
        require(uniformBlock(doubledImage, x: 32, y: 200, rgb: skinPixel(16, 100)), "2× nearest keeps scratch black as a 2×2 block")
        require(uniformBlock(doubledImage, x: 80, y: 438, rgb: (0, 1, 0)), "2× nearest keeps the green judgment as a 2×2 block")
        require(uniformBlock(doubledImage, x: 0, y: 0, rgb: (156.0 / 255.0, 158.0 / 255.0, 156.0 / 255.0)), "2× nearest keeps the corner gray")
        writePNG(doubledImage, name: "skin-readback-2x.png")

        let notes = makeView(width: 331, height: 256)
        notes.pixelsPerBeat = 96
        notes.setChart(PreviewChartSnapshot(
            title: "Notes",
            lanes: sevenKeyChart().lanes,
            notes: [
                PreviewVisualNote(laneID: "scratch", startBeat: 1, endBeat: 1),
                PreviewVisualNote(laneID: "k1", startBeat: 1, endBeat: 1),
                PreviewVisualNote(laneID: "k2", startBeat: 1, endBeat: 1)
            ],
            barBeats: [],
            endBeat: 16
        ))
        notes.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        let noteImage = notes.renderMetalReadback()
        requireMetalReadback(noteImage)
        require(near(sample(noteImage, CGPoint(x: 17.2, y: 120.2), viewSize: notes.bounds.size), (250.0 / 255.0, 50.0 / 255.0, 50.0 / 255.0)), "scratch chip mid is skin_01 red")
        require(near(sample(noteImage, CGPoint(x: 43.2, y: 120.2), viewSize: notes.bounds.size), (106.0 / 255.0, 106.0 / 255.0, 106.0 / 255.0)), "white chip mid is skin_01 106 gray")
        require(near(sample(noteImage, CGPoint(x: 60.2, y: 120.2), viewSize: notes.bounds.size), (0, 31.0 / 255.0, 1)), "blue chip mid is skin_01 blue")
        writePNG(noteImage, name: "playfield-notes-331.png")

        let hitting = makeView(width: 331, height: 256)
        hitting.pixelsPerBeat = 96
        hitting.setChart(PreviewChartSnapshot(
            title: "Hit",
            lanes: sevenKeyChart().lanes,
            notes: [
                PreviewVisualNote(laneID: "scratch", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "k1", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "k2", startBeat: 4, endBeat: 4)
            ],
            barBeats: [0, 4],
            endBeat: 16
        ))
        hitting.setTiming(PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: []), fromBeat: 4)
        hitting.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        let hitScene = hitting.currentScene()
        require(hitScene.combo == 3, "autoplay combo counts the three notes that have started")
        require(hitScene.judgeAge == 0, "the hit age is zero at the timing origin")
        require(hitScene.hits.count == 3, "one beam per lane, not a random flash")
        let hitImage = hitting.renderMetalReadback()
        requireMetalReadback(hitImage)
        let again = hitting.renderMetalReadback()
        require(hitImage.bgra == again.bgra, "the same beat renders the same pixels")
        let greatX = IndependentEffect.greatX(combo: 3, side: 0)
        require(greatX == 28, "one digit uses integer x=28")
        require(PreviewUbmStyle.greatNativeX(combo: 3, sideOrigin: 0) == CGFloat(greatX), "product GREAT x matches the integer division")
        let greatPoint = IndependentEffect.greatPoint(combo: 3, side: 0, ageMs: 0, wallMs: 0, atlasX: 19, atlasY: 107)
        let great = sample(hitImage, greatPoint, viewSize: hitting.bounds.size)
        guard let greatSource = calibratedPng(named: "skin_02.png"),
              let yellow = greatSource.rgb(19, 107) else {
            fail("missing GREAT source pixel")
        }
        require(near((r: yellow.0, g: yellow.1, b: yellow.2, a: 1), (1, 1, 0), tolerance: 0), "skin_02 GREAT pixel is yellow")
        require(near(great, yellow, tolerance: 0), "GREAT readback matches skin_02 (19,107) \(great)")
        writePNG(hitImage, name: "playfield-hit-331.png")
        writeCanvas(playfield: hitImage, name: "playfield-hit-canvas-587.png")

        let plain = PreviewUbmStyle.textImage("A", color: PreviewUbmStyle.originalFontColor)
        let lower = PreviewUbmStyle.textImage("b", color: PreviewUbmStyle.originalFontColor)
        let title = PreviewUbmStyle.textImage("测试", color: PreviewUbmStyle.originalFontColor)
        require(plain?.width == 8 && lower?.width == 8, "bitmap font cells are 8px wide")
        require((title?.width ?? 0) > 8, "non-ASCII titles are drawn instead of dropped")
        require(inkCount(plain) > 0 && inkCount(title) > 0, "font images contain ink")
        let aPixel = textPixel(plain, x: 2, y: 0)
        let bTop = textPixel(lower, x: 1, y: 0)
        let bLower = textPixel(lower, x: 2, y: 2)
        require(near(aPixel, (112.0 / 255.0, 186.0 / 255.0, 254.0 / 255.0), tolerance: 0), "A keeps the font cyan \(aPixel)")
        require(near(bTop, (112.0 / 255.0, 186.0 / 255.0, 254.0 / 255.0), tolerance: 0), "b keeps the ascender at y=23 \(bTop)")
        require(near(bLower, (10.0 / 255.0, 234.0 / 255.0, 1), tolerance: 0), "b keeps the lower cyan gradient \(bLower)")
        if let plain, let lower, let title {
            writeCGImage(plain, name: "font-a.png")
            writeCGImage(lower, name: "font-b.png")
            writeCGImage(title, name: "font-title.png")
        }
        printPngHashes(in: skinDirectory)

        let fade = makeView(width: 331, height: 256)
        fade.pixelsPerBeat = 96
        fade.setChart(PreviewChartSnapshot(
            title: "Fade",
            lanes: [PreviewVisualLane(id: "scratch", title: "SC", isScratch: true)],
            notes: [PreviewVisualNote(laneID: "scratch", startBeat: 4, endBeat: 4)],
            barBeats: [],
            endBeat: 16
        ))
        fade.setTiming(PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: []), fromBeat: 4)
        fade.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        fade.setBeamVertexAlpha(0.5)
        let fadeImage = fade.renderMetalReadback()
        requireMetalReadback(fadeImage)
        let faded = sample(fadeImage, CGPoint(x: 1.2, y: 10.2), viewSize: fade.bounds.size)
        require(near(faded, (30.0 / 255.0, 0, 0), tolerance: 1.0 / 255.0), "half alpha blends once \(faded)")
        require(abs(faded.r - 15.0 / 255.0) > 8.0 / 255.0, "half alpha is not squared to 25 percent \(faded)")
        fade.setBeamVertexAlpha(1)
        fade.setPlayback(beat: 4, elapsedSeconds: 0.051, isPlaying: true)
        let expired = fade.renderMetalReadback()
        requireMetalReadback(expired)
        let gone = sample(expired, CGPoint(x: 1.2, y: 10.2), viewSize: fade.bounds.size)
        require(near(gone, (0, 0, 0), tolerance: 0), "beam past 50 ms is the black background \(gone)")
        writePNG(fadeImage, name: "playfield-half-alpha.png")

        let procedural = PreviewPlayfieldView(
            frame: NSRect(x: 0, y: 0, width: 331, height: 256),
            device: MTLCreateSystemDefaultDevice(),
            skinChoice: .disabled
        )
        procedural.layoutSubtreeIfNeeded()
        requireMetal(procedural)
        guard case .procedural = procedural.skinMode else {
            fail("disabled skin must stay procedural")
        }
        procedural.pixelsPerBeat = 96
        procedural.setChart(sevenKeyChart())
        procedural.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: false)
        let flat = procedural.renderMetalReadback()
        requireMetalReadback(flat)
        let scratchFill = sample(flat, CGPoint(x: 16.2, y: 100.2), viewSize: procedural.bounds.size)
        require(matches(scratchFill, PreviewPlayfieldPalette.scratchLane), "procedural scratch column keeps the flat palette \(scratchFill)")
        require(!near(scratchFill, (0, 0, 0), tolerance: 0.05), "procedural mode does not sample skin_00 black")

        let windowView = makeView(width: 320, height: 240)
        requireMetal(windowView)
        let window = NSWindow(contentRect: windowView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = windowView
        windowView.frame = window.contentView?.bounds ?? windowView.frame
        windowView.layoutSubtreeIfNeeded()
        windowView.pixelsPerBeat = 96
        windowView.setChart(sevenKeyChart())
        let beforeSubmit = windowView.liveSubmitCount
        windowView.setPlayback(beat: 1, elapsedSeconds: 0.5, isPlaying: true)
        require(windowView.liveSubmitCount == beforeSubmit, "setPlayback does not submit a drawable by itself")
        window.displayIfNeeded()
        windowView.presentPlaybackFrame(beat: 2, elapsedSeconds: 1, isPlaying: true)
        require(windowView.liveSubmitCount == beforeSubmit + 1, "presentPlaybackFrame submits one Metal drawable")
        require(windowView.currentScene().accessibilityBeat == "2.00", "the submitted frame uses the shared beat")
        require(windowView.rendersFromExternalPlayback, "presenting a frame does not start a view timer")
        let until = Date().addingTimeInterval(0.25)
        while windowView.recentPresentedSamples().isEmpty && Date() < until {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let samples = windowView.recentPresentedSamples()
        print("presented-samples=\(samples.count)")
        if let first = samples.first {
            print("presented-time=\(first.presentedTime)")
        }
        window.orderOut(nil)
    }

    @MainActor
    private static func testMissingMetalStaysExplicit() {
        let view = PreviewPlayfieldView(frame: NSRect(x: 0, y: 0, width: 760, height: 680), device: nil)
        view.setChart(sevenKeyChart())
        view.setPlayback(beat: 4, elapsedSeconds: 1, isPlaying: true)
        guard case .unavailable(let reason) = view.gpuStatus else {
            fail("a nil device must not report Metal as ready")
        }
        require(reason == PreviewPlayfieldLayout.missingMetalMessage, "missing Metal uses an explicit status")
        require(view.displayedOverlayMessage == reason, "the overlay shows the Metal status instead of a CPU chart")
        require(view.accessibilityLabel()?.contains(reason) == true, "accessibility includes the Metal status")
        require(view.currentScene().marks.contains { $0.laneID == "k1" }, "layout is still available when Metal is not")
        require(view.pipelineCompileCount == 0, "no pipeline is compiled without a device")
        require(!view.rendersFromExternalPlayback, "there is no paused Metal clock to pretend with")
        let readback = view.renderMetalReadback()
        require(readback.usedMetal == false, "readback must not invent a CPU image")
        require(readback.bgra.isEmpty, "missing Metal returns no pixels")
        require(readback.status == view.gpuStatus, "readback repeats the same unavailable status")
    }

    /// 同一拍的音符帧不跟 BPM 走。同一拍差在慢 BPM 上先超过 50 ms。STOP 冻住拍，毫秒继续走。
    @MainActor
    private static func testBeatClockAndStopLifetimes() {
        require(PreviewUbmStyle.vbI4Currency(0.5) == 0, "VB rounds 0.5 to even 0")
        require(PreviewUbmStyle.vbI4Currency(1.5) == 2, "VB rounds 1.5 to even 2")
        require(PreviewUbmStyle.vbI4Currency(2.5) == 2, "VB rounds 2.5 to even 2")
        require(PreviewUbmStyle.vbI4Currency(3.5) == 4, "VB rounds 3.5 to even 4")
        require(PreviewUbmStyle.shortFrame(playbackBeat: 0) == 0, "beat 0 is short frame 0")
        require(PreviewUbmStyle.shortFrame(playbackBeat: 1) == 2, "beat 1 is short frame 2")
        require(PreviewUbmStyle.longFrame(playbackBeat: 0.5) == 1, "half a beat is long frame 1")
        require(PreviewUbmStyle.longFrame(playbackBeat: 1) == 2, "beat 1 is long frame 2")
        require(PreviewUbmStyle.effectMilliseconds(0.05) == 50, "50 ms converts from seconds")
        require(PreviewUbmStyle.effectMilliseconds(0.051) == 51, "51 ms converts from seconds")
        require(PreviewUbmStyle.beamVisible(ageMilliseconds: 50) && !PreviewUbmStyle.beamVisible(ageMilliseconds: 51), "beam stays through 50 ms")
        require(PreviewUbmStyle.bombFrame(ageMilliseconds: 100) == 5, "bomb frame is age/20")
        require(!PreviewUbmStyle.bombVisible(ageMilliseconds: 120, isLong: false), "a normal slot clears at 120 ms")
        require(PreviewUbmStyle.bombVisible(ageMilliseconds: 500, isLong: true), "a long bomb has no 120 ms clear")
        require(PreviewUbmStyle.judgmentVisible(ageMilliseconds: 1079) && !PreviewUbmStyle.judgmentVisible(ageMilliseconds: 1080), "GREAT lasts until 1080 ms")
        require(PreviewUbmStyle.greatFrame(elapsedSeconds: 0.05) == 1, "GREAT frame follows global milliseconds")
        let ordered = [0.0, 0.5, 1.0, 2.0]
        require(PreviewPlayfieldLayout.lastAtMost(-0.1, in: ordered) == -1, "the window starts after the first hit")
        require(PreviewPlayfieldLayout.lastAtMost(0.7, in: ordered) == 1, "the window keeps the latest hit")
        require(PreviewPlayfieldLayout.lastAtMost(9, in: ordered) == 3, "the window stays on the last hit")

        let fast = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
        let slow = PreviewAudioTiming(headerBPM: 60, bpmEvents: [], stopEvents: [])
        let changed = PreviewAudioTiming(headerBPM: 120, bpmEvents: [(beat: 2, bpm: 60)], stopEvents: [])
        let stopped = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 2, durationSeconds: 1)])
        require(abs(PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: fast) - 2) < 1e-9, "BPM 120")
        require(abs(PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: slow) - 4) < 1e-9, "BPM 60")
        require(abs(PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: changed) - 3) < 1e-9, "a BPM change applies after its beat")
        require(abs(PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: stopped) - 3) < 1e-9, "STOP inside the span is added")
        require(abs(PreviewPlayfieldClock.arrivalSeconds(beat: 2, origin: 0, timing: stopped) - 1) < 1e-9, "STOP on the destination is excluded")
        require(abs(PreviewPlayfieldClock.arrivalSeconds(beat: 2, origin: 4, timing: fast) + 1) < 1e-9, "Play Here before the origin is negative")

        guard let skin0 = calibratedPng(named: "skin_00.png"),
              let skin1 = calibratedPng(named: "skin_01.png"),
              let skin2 = calibratedPng(named: "skin_02.png"),
              let skin3 = calibratedPng(named: "skin_03.png") else {
            fail("missing clock atlases")
        }
        let noteFrame = PreviewUbmStyle.shortFrame(playbackBeat: 1)
        let chip = PreviewUbmStyle.noteSprite(kind: .white, part: .short, frame: noteFrame)
        guard let chipColor = skin1.rgb(Int(chip.rect.minX) + 9, Int(chip.rect.minY) + 2) else {
            fail("missing beat-1 chip texel")
        }
        func clockView(_ timing: PreviewAudioTiming) -> PreviewPlayfieldView {
            let view = makeView(width: 331, height: 256)
            requireMetal(view)
            view.pixelsPerBeat = 96
            view.setChart(PreviewChartSnapshot(
                title: "Clock",
                lanes: [
                    PreviewVisualLane(id: "s", title: "S", isScratch: true),
                    PreviewVisualLane(id: "k", title: "1")
                ],
                notes: [
                    PreviewVisualNote(laneID: "s", startBeat: 1, endBeat: 1),
                    PreviewVisualNote(laneID: "k", startBeat: 2, endBeat: 2)
                ],
                barBeats: [],
                endBeat: 8
            ))
            view.setTiming(timing, fromBeat: 0)
            return view
        }
        let fastView = clockView(fast)
        let slowView = clockView(slow)
        fastView.setPlayback(beat: 1, elapsedSeconds: PreviewPlayfieldClock.arrivalSeconds(beat: 1.06, origin: 0, timing: fast), isPlaying: true)
        slowView.setPlayback(beat: 1, elapsedSeconds: PreviewPlayfieldClock.arrivalSeconds(beat: 1.06, origin: 0, timing: slow), isPlaying: true)
        let fastImage = fastView.renderMetalReadback()
        let slowImage = slowView.renderMetalReadback()
        requireMetalReadback(fastImage)
        requireMetalReadback(slowImage)
        let mark = tryMark(fastView.currentScene(), lane: "k", part: .short)
        let chipPoint = CGPoint(x: mark.rect.minX + 9.2, y: mark.rect.minY + 2.2)
        require(near(sample(fastImage, chipPoint, viewSize: fastView.bounds.size), chipColor, tolerance: 0), "BPM 120 uses the beat frame")
        require(near(sample(slowImage, chipPoint, viewSize: slowView.bounds.size), chipColor, tolerance: 0), "BPM 60 keeps that same frame")
        let beamPoint = CGPoint(x: 1.2, y: 10.2)
        require(near(sample(fastImage, beamPoint, viewSize: fastView.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "30 ms beam is on")
        require(near(sample(slowImage, beamPoint, viewSize: slowView.bounds.size), (0, 0, 0), tolerance: 0), "60 ms beam is off at the same beat delta")
        writePNG(fastImage, name: "clock-bpm120.png")
        writePNG(slowImage, name: "clock-bpm60.png")

        var bombLocal: (x: Int, y: Int)?
        for y in 0..<64 {
            for x in 20..<64 {
                guard let first = skin3.rgb(1 + x, 163 + y), let later = skin3.rgb(1 + 5 * 64 + x, 163 + y) else { continue }
                if first == later { continue }
                if isKeyed(first) || isKeyed(later) { continue }
                bombLocal = (x, y)
                break
            }
            if bombLocal != nil { break }
        }
        guard let bombLocal else { fail("skin_03 bomb frames 0 and 5 share every opaque texel") }
        guard let bomb0 = skin3.rgb(1 + bombLocal.x, 163 + bombLocal.y),
              let bomb5 = skin3.rgb(1 + 5 * 64 + bombLocal.x, 163 + bombLocal.y),
              let great0 = skin2.rgb(19, 107),
              let great1 = skin2.rgb(19, 122),
              great0 != great1 else {
            fail("missing STOP oracle texels")
        }
        let frozenFrame = PreviewUbmStyle.shortFrame(playbackBeat: 4)
        let frozenSprite = PreviewUbmStyle.noteSprite(kind: .white, part: .short, frame: frozenFrame)
        guard let frozenColor = skin1.rgb(Int(frozenSprite.rect.minX) + 9, Int(frozenSprite.rect.minY) + 2) else {
            fail("missing frozen chip texel")
        }
        let stopView = makeView(width: 331, height: 256)
        requireMetal(stopView)
        stopView.pixelsPerBeat = 96
        let stopTiming = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 4, durationSeconds: 2)])
        stopView.setChart(PreviewChartSnapshot(
            title: "Stop",
            lanes: [
                PreviewVisualLane(id: "s", title: "S", isScratch: true),
                PreviewVisualLane(id: "k", title: "1")
            ],
            notes: [
                PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8),
                PreviewVisualNote(laneID: "k", startBeat: 5, endBeat: 5)
            ],
            barBeats: [],
            endBeat: 12
        ))
        stopView.setTiming(stopTiming, fromBeat: 0)
        func stopFrame(_ elapsed: Double) -> PreviewPlayfieldMetalReadback {
            stopView.setPlayback(beat: 4, elapsedSeconds: elapsed, isPlaying: true)
            let image = stopView.renderMetalReadback()
            requireMetalReadback(image)
            return image
        }
        let arrival = PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: stopTiming)
        let atHit = stopFrame(arrival)
        let atFifty = stopFrame(arrival + 0.05)
        let atSixty = stopFrame(arrival + 0.06)
        let atBomb = stopFrame(arrival + 0.10)
        let atLate = stopFrame(arrival + 0.20)
        let atEnd = stopFrame(arrival + 1.08)
        let frozenMark = tryMark(stopView.currentScene(), lane: "k", part: .short)
        let frozenPoint = CGPoint(x: frozenMark.rect.minX + 9.2, y: frozenMark.rect.minY + 2.2)
        require(near(sample(atHit, frozenPoint, viewSize: stopView.bounds.size), frozenColor, tolerance: 0), "STOP hit frame")
        require(near(sample(atLate, frozenPoint, viewSize: stopView.bounds.size), frozenColor, tolerance: 0), "STOP keeps the note frame while elapsed grows")
        require(near(sample(atFifty, beamPoint, viewSize: stopView.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "STOP beam is still on at 50 ms")
        require(near(sample(atSixty, beamPoint, viewSize: stopView.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "STOP keeps the held beam at 60 ms")
        require(near(sample(atLate, beamPoint, viewSize: stopView.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "STOP keeps the held beam at 200 ms")
        require(near(sample(atEnd, beamPoint, viewSize: stopView.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "STOP keeps the held beam at 1080 ms")
        let greatAtHit = IndependentEffect.greatPoint(combo: 1, side: 0, ageMs: 0, wallMs: 2000, atlasX: 19, atlasY: 107)
        let greatAtFifty = IndependentEffect.greatPoint(combo: 1, side: 0, ageMs: 50, wallMs: 2050, atlasX: 19, atlasY: 122)
        require(near(sample(atHit, greatAtHit, viewSize: stopView.bounds.size), great0, tolerance: 0), "STOP GREAT starts on frame 0")
        require(near(sample(atFifty, greatAtFifty, viewSize: stopView.bounds.size), great1, tolerance: 0), "STOP GREAT advances with milliseconds")
        guard let back = skin0.rgb(Int(greatAtHit.x), Int(greatAtHit.y)) else { fail("missing GREAT background") }
        require(near(sample(atEnd, greatAtHit, viewSize: stopView.bounds.size), back, tolerance: 0), "GREAT is gone at 1080 ms")
        let bombPoint = bombPoint(in: stopView, lane: "s", local: bombLocal)
        require(near(sample(atHit, bombPoint, viewSize: stopView.bounds.size), bomb0, tolerance: 0), "long bomb frame 0 \(bombPoint)")
        require(near(sample(atBomb, bombPoint, viewSize: stopView.bounds.size), bomb5, tolerance: 0), "long bomb frame 5 at 100 ms")
        require(near(sample(atLate, bombPoint, viewSize: stopView.bounds.size), skin3.rgb(1 + 4 * 64 + bombLocal.x, 163 + bombLocal.y) ?? bomb5, tolerance: 0), "long bomb remains after 120 ms")
        writePNG(atHit, name: "clock-stop-hit.png")
        writePNG(atLate, name: "clock-stop-late.png")
        writePNG(atEnd, name: "clock-stop-great-end.png")

        let here = makeView(width: 331, height: 256)
        requireMetal(here)
        here.pixelsPerBeat = 96
        here.setChart(PreviewChartSnapshot(
            title: "Here",
            lanes: [PreviewVisualLane(id: "s", title: "S", isScratch: true)],
            notes: [PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)],
            barBeats: [],
            endBeat: 12
        ))
        here.setTiming(fast, fromBeat: 8)
        here.setPlayback(beat: 8, elapsedSeconds: 0, isPlaying: true)
        let recovered = here.currentScene()
        require(recovered.hits.isEmpty, "Play Here does not resurrect a note that arrived before the origin")
        let hereImage = here.renderMetalReadback()
        requireMetalReadback(hereImage)
        require(near(sample(hereImage, beamPoint, viewSize: here.bounds.size), (0, 0, 0), tolerance: 0), "an unobserved earlier beam stays off")
        writePNG(hereImage, name: "clock-play-here.png")
    }

    /// 2 倍和 0.5 倍都从非 0 拍跨过到达。年龄跟墙钟，不跟谱面秒。
    @MainActor
    private static func testDualClockRates() {
        require(PreviewUbmStyle.effectMilliseconds(0.06) == 60, "60 ms")
        require(PreviewUbmStyle.effectMilliseconds(0.12) == 120, "120 ms")
        require(PreviewUbmStyle.effectMilliseconds(1.08) == 1080, "1080 ms")
        guard let skin0 = calibratedPng(named: "skin_00.png"),
              let skin1 = calibratedPng(named: "skin_01.png"),
              let skin2 = calibratedPng(named: "skin_02.png"),
              let skin3 = calibratedPng(named: "skin_03.png"),
              let great0 = skin2.rgb(19, 107),
              let great1 = skin2.rgb(19, 122),
              let whiteBeamInk = skin1.rgb(17, 11),
              great0 != great1 else {
            fail("missing dual-clock GREAT texels")
        }
        var bombLocal: (x: Int, y: Int)?
        for y in 0..<64 {
            for x in 20..<64 {
                guard let first = skin3.rgb(1 + x, 163 + y), let later = skin3.rgb(1 + 5 * 64 + x, 163 + y) else { continue }
                if first == later || isKeyed(first) || isKeyed(later) { continue }
                bombLocal = (x, y)
                break
            }
            if bombLocal != nil { break }
        }
        guard let bombLocal,
              let bomb0 = skin3.rgb(1 + bombLocal.x, 163 + bombLocal.y),
              let bomb5 = skin3.rgb(1 + 5 * 64 + bombLocal.x, 163 + bombLocal.y) else {
            fail("missing dual-clock bomb texels")
        }
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
        let view = clockHost()
        view.setTiming(timing, fromBeat: 0)
        view.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        view.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5, isPlaying: true)
        let arrived = view.currentScene()
        let longHit = arrived.hits.first { $0.laneID == "s" }
        let shortHit = arrived.hits.first { $0.laneID == "k" }
        guard let longHit, let shortHit else { fail("2× arrival did not hit both lanes") }
        require(longHit.ageMilliseconds == 0 && shortHit.ageMilliseconds == 0, "2× age is 0 at chart 1 / wall 0.5, long \(longHit.ageMilliseconds)")
        let arrivedImage = view.renderMetalReadback()
        requireMetalReadback(arrivedImage)
        let beamPoint = CGPoint(x: 1.2, y: 10.2)
        let bomb = bombPoint(in: view, lane: "s", local: bombLocal)
        let greatAtArrival = IndependentEffect.greatPoint(combo: 2, side: 0, ageMs: 0, wallMs: 500, atlasX: 19, atlasY: 107)
        let greatAtWall = IndependentEffect.greatPoint(combo: 2, side: 0, ageMs: 50, wallMs: 550, atlasX: 19, atlasY: 122)
        require(near(sample(arrivedImage, beamPoint, viewSize: view.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "2× beam is on at the real arrival")
        require(near(sample(arrivedImage, bomb, viewSize: view.bounds.size), bomb0, tolerance: 0), "2× bomb frame 0 matches skin_03")
        require(near(sample(arrivedImage, greatAtArrival, viewSize: view.bounds.size), great0, tolerance: 0), "2× GREAT frame follows wall 0.5")
        view.setPlayback(beat: 2, chartElapsedSeconds: 1.10, effectElapsedSeconds: 0.5 + 0.05, isPlaying: true)
        let greatImage = view.renderMetalReadback()
        requireMetalReadback(greatImage)
        require(view.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 50, "birth stays put across the next 2× frame")
        require(near(sample(greatImage, greatAtWall, viewSize: view.bounds.size), great1, tolerance: 0), "GREAT frame follows the wall, not the chart second")
        view.setPlayback(beat: 2, chartElapsedSeconds: 1.12, effectElapsedSeconds: 0.5 + 0.06, isPlaying: true)
        let beamOff = view.renderMetalReadback()
        requireMetalReadback(beamOff)
        guard let whiteLane = view.currentScene().lanes.first(where: { $0.id == "k" }),
              let whiteBack = skin0.rgb(Int(whiteLane.rect.minX), 10) else {
            fail("missing the short-note beam column")
        }
        let whiteBeam = CGPoint(x: whiteLane.rect.minX + 0.2, y: 10.2)
        require(whiteBeamInk != whiteBack, "white beam ink matches the background")
        require(near(sample(arrivedImage, whiteBeam, viewSize: view.bounds.size), whiteBeamInk, tolerance: 0), "short beam is on at the real arrival")
        require(near(sample(beamOff, beamPoint, viewSize: view.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "held scratch beam stays on at wall +60 ms")
        require(near(sample(beamOff, whiteBeam, viewSize: view.bounds.size), whiteBack, tolerance: 0), "short beam is off at wall +60 ms")
        view.setPlayback(beat: 2, chartElapsedSeconds: 1.20, effectElapsedSeconds: 0.5 + 0.10, isPlaying: true)
        let bombImage = view.renderMetalReadback()
        requireMetalReadback(bombImage)
        require(view.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 100, "100 ms wall age, not the 200 ms chart delta")
        require(near(sample(bombImage, bomb, viewSize: view.bounds.size), bomb5, tolerance: 0), "bomb frame 5 is the wall age")
        view.setPlayback(beat: 2, chartElapsedSeconds: 1.24, effectElapsedSeconds: 0.5 + 0.12, isPlaying: true)
        let cleared = view.currentScene()
        guard let agedShort = cleared.hits.first(where: { $0.laneID == "k" }) else { fail("short hit dropped before 1080 ms") }
        require(agedShort.ageMilliseconds == 120, "short age is 120 ms")
        require(!PreviewUbmStyle.bombVisible(ageMilliseconds: agedShort.ageMilliseconds, isLong: false), "normal bomb clears at 120 ms")
        require(cleared.hits.contains { $0.laneID == "s" && $0.isLong }, "long bomb is still latched at 120 ms")
        view.setPlayback(beat: 2, chartElapsedSeconds: 1.24, effectElapsedSeconds: 0.5 + 1.08, isPlaying: true)
        require(view.currentScene().hits.contains { $0.laneID == "k" } == false, "judgment ends at 1080 ms")
        require(view.currentScene().hits.contains { $0.laneID == "s" && $0.isLong }, "a latched long bomb outlives GREAT")
        writePNG(arrivedImage, name: "clock-2x-hit.png")
        writePNG(bombImage, name: "clock-2x-bomb.png")

        let half = clockHost()
        half.setTiming(timing, fromBeat: 0)
        half.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        half.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 2, isPlaying: true)
        require(half.currentScene().hits.allSatisfy { $0.ageMilliseconds == 0 }, "0.5× arrival age is 0 at wall 2")
        let halfOn = half.renderMetalReadback()
        requireMetalReadback(halfOn)
        require(near(sample(halfOn, beamPoint, viewSize: half.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "0.5× beam is on despite chart age of 1 s")
        half.setPlayback(beat: 2, chartElapsedSeconds: 1.03, effectElapsedSeconds: 2 + 0.06, isPlaying: true)
        let halfOff = half.renderMetalReadback()
        requireMetalReadback(halfOff)
        require(half.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 60, "0.5× age follows the 60 ms wall step")
        guard let halfWhite = half.currentScene().lanes.first(where: { $0.id == "k" }),
              let halfBack = skin0.rgb(Int(halfWhite.rect.minX), 10) else {
            fail("missing the 0.5× short-note column")
        }
        let halfWhiteBeam = CGPoint(x: halfWhite.rect.minX + 0.2, y: 10.2)
        require(near(sample(halfOff, beamPoint, viewSize: half.bounds.size), (60.0 / 255.0, 0, 0), tolerance: 0), "0.5× held beam stays on at wall +60 ms")
        require(near(sample(halfOff, halfWhiteBeam, viewSize: half.bounds.size), halfBack, tolerance: 0), "0.5× short beam is off while the chart only moved 30 ms")
        writePNG(halfOn, name: "clock-half-hit.png")

        let bend = clockHost()
        bend.setTiming(timing, fromBeat: 0)
        bend.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        bend.setPlayback(beat: 1, chartElapsedSeconds: 0.5, effectElapsedSeconds: 0.5, isPlaying: true)
        require(bend.currentScene().hits.isEmpty, "the note at chart 1 has not arrived")
        bend.setPlayback(beat: 1, chartElapsedSeconds: 0.5, effectElapsedSeconds: 0.5, isPlaying: false)
        require(bend.currentScene().hits.isEmpty, "pause does not invent a hit")
        bend.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.75, isPlaying: true)
        require(bend.currentScene().hits.allSatisfy { $0.ageMilliseconds == 0 }, "rate change across the pause births the hit at the new wall")

        let changed = PreviewAudioTiming(headerBPM: 120, bpmEvents: [(beat: 2, bpm: 240)], stopEvents: [])
        let bpm = clockHost()
        bpm.setChart(PreviewChartSnapshot(
            title: "BPM",
            lanes: [PreviewVisualLane(id: "k", title: "1")],
            notes: [PreviewVisualNote(laneID: "k", startBeat: 4, endBeat: 4)],
            barBeats: [],
            endBeat: 8
        ))
        bpm.setTiming(changed, fromBeat: 0)
        bpm.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        let arrival = PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: changed)
        bpm.setPlayback(beat: 4, chartElapsedSeconds: arrival, effectElapsedSeconds: arrival, isPlaying: true)
        require(abs(arrival - 1.5) < 1e-9, "beat 4 arrives at chart 1.5 after the BPM change")
        require(bpm.currentScene().hits.allSatisfy { $0.ageMilliseconds == 0 }, "BPM change moves the chart arrival to 1.5 s")
        bpm.setPlayback(beat: 4, chartElapsedSeconds: 1.4, effectElapsedSeconds: 1.4, isPlaying: true)
        require(bpm.currentScene().hits.isEmpty, "seeking backward clears the hit")

        let stopped = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 2, durationSeconds: 1)])
        let stop = clockHost()
        stop.setTiming(stopped, fromBeat: 0)
        stop.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        stop.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 1, isPlaying: true)
        require(stop.currentScene().hits.allSatisfy { $0.ageMilliseconds == 0 }, "STOP does not delay the note on its own beat")
        stop.setPlayback(beat: 2, chartElapsedSeconds: 2, effectElapsedSeconds: 2, isPlaying: true)
        let duringStop = stop.currentScene()
        require(duringStop.playbackBeat == 2, "STOP keeps the beat")
        require(duringStop.hits.allSatisfy { $0.ageMilliseconds == 1000 }, "STOP ages the bomb on the wall without a new note")
        require(duringStop.hits.contains { $0.laneID == "s" && $0.isLong }, "the long bomb stays through STOP")

        let here = clockHost()
        here.setChart(PreviewChartSnapshot(
            title: "Here",
            lanes: [
                PreviewVisualLane(id: "s", title: "S", isScratch: true),
                PreviewVisualLane(id: "k", title: "1")
            ],
            notes: [
                PreviewVisualNote(laneID: "s", startBeat: 2, endBeat: 6),
                PreviewVisualNote(laneID: "k", startBeat: 4, endBeat: 4)
            ],
            barBeats: [],
            endBeat: 8
        ))
        here.setTiming(timing, fromBeat: 4)
        here.setPlayback(beat: 4, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        let hereScene = here.currentScene()
        require(hereScene.hits.count == 1 && hereScene.hits[0].laneID == "k", "Here only hits the note on the origin")
        require(hereScene.hits[0].ageMilliseconds == 0, "the origin note is age 0")

        let seek = clockHost()
        seek.setTiming(timing, fromBeat: 0)
        seek.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        seek.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5, isPlaying: true)
        require(seek.currentScene().hits.contains { $0.ageMilliseconds == 0 }, "seek setup hit")
        seek.setTiming(timing, fromBeat: 8)
        seek.setPlayback(beat: 8, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        require(seek.currentScene().hits.isEmpty, "seek clears the previous hit clock")

        let side = clockHost()
        side.setTiming(timing, fromBeat: 0)
        side.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        side.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5, isPlaying: true)
        side.setPlayerSide(.twoPlayer)
        side.setPlayback(beat: 2, chartElapsedSeconds: 1.02, effectElapsedSeconds: 0.5 + 0.01, isPlaying: true)
        side.setUbmAppearance(scratchRaw: 1, effectsRaw: 7, autoSeparate: true)
        side.pixelsPerBeat = 80
        side.layoutSubtreeIfNeeded()
        side.setPlayerSide(.both)
        guard let kept = side.currentScene().hits.first(where: { $0.laneID == "s" }) else {
            fail("side, F2 and resize dropped the hit")
        }
        require(kept.ageMilliseconds == 10, "the hidden interval keeps the original birth, got \(kept.ageMilliseconds)")

        let hidden = clockHost()
        hidden.setTiming(timing, fromBeat: 0)
        hidden.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        hidden.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5, isPlaying: true)
        hidden.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5 + 5, isPlaying: true)
        let jumped = hidden.currentScene()
        require(jumped.hits.contains { $0.laneID == "k" } == false, "a five-second wall jump drops the expired short hit")
        guard let keptHold = jumped.hits.first(where: { $0.laneID == "s" }) else {
            fail("a five-second wall jump must keep the hold while chart is still before the tail")
        }
        require(keptHold.isLong && keptHold.tailAgeMilliseconds == nil, "chart 1 is still inside the hold to chart 3")
        require(keptHold.ageMilliseconds == 5000, "the original birth ages to 5000 ms, got \(keptHold.ageMilliseconds)")
        require(jumped.sideJudges.isEmpty, "5000 ms is past GREAT")
    }

    /// 快路径必须和原来的逐段积分一致，包括同拍、边界和负拍。
    @MainActor
    private static func testTimeIndexMatchesSlowIntegral() {
        let sameBeat = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [(beat: 1, bpm: 100), (beat: 1, bpm: 200), (beat: 1, bpm: 80)],
            stopEvents: [
                (beat: 1, durationSeconds: 0.2),
                (beat: 1, durationSeconds: 0.3),
                (beat: 0, durationSeconds: 1)
            ]
        )
        expectArrival(sameBeat, beat: 1, origin: 0, expected: 1.5, label: "destination STOP and BPM stay out of the arrival")
        expectArrival(sameBeat, beat: 2, origin: 1, expected: 1.25, label: "origin STOP is included and the last same-beat BPM is 80")
        expectArrival(sameBeat, beat: 1, origin: 2, expected: -1.25, label: "reverse travel negates the same span")
        let reversedBPM = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [(beat: 1, bpm: 200), (beat: 1, bpm: 100)],
            stopEvents: []
        )
        expectArrival(reversedBPM, beat: 3, origin: 1, expected: 2 * 60 / 100, label: "stable order keeps the later BPM")
        let invalid = PreviewAudioTiming(
            headerBPM: 0,
            bpmEvents: [(beat: .nan, bpm: 180), (beat: 1, bpm: 0), (beat: 1, bpm: -4), (beat: 2, bpm: 240)],
            stopEvents: [
                (beat: 2, durationSeconds: 0),
                (beat: 2, durationSeconds: -1),
                (beat: .infinity, durationSeconds: 1),
                (beat: 2, durationSeconds: 0.4)
            ]
        )
        expectArrival(invalid, beat: 2, origin: 0, expected: 1, label: "invalid header falls back to 120 and the destination STOP is excluded")
        expectArrival(invalid, beat: 3, origin: 0, expected: 1.65, label: "the valid STOP is kept after leaving its beat")
        let unsorted = PreviewAudioTiming(
            headerBPM: 90,
            bpmEvents: [(beat: 4, bpm: 180), (beat: -3, bpm: 60), (beat: 4, bpm: 120), (beat: 1, bpm: 240)],
            stopEvents: [(beat: 5, durationSeconds: 0.25), (beat: -1, durationSeconds: 0.5), (beat: -1, durationSeconds: 0.5)]
        )
        for pair in [(-4.0, -3.0), (-3.0, 0.0), (-1.0, 1.0), (0.0, 4.0), (4.0, 6.0), (6.0, -2.0), (1.0, 1.0)] {
            expectArrival(unsorted, beat: pair.0, origin: pair.1, expected: nil, label: "unsorted \(pair.0) from \(pair.1)")
        }
        var seed: UInt64 = 0x1234_5678
        func unit() -> Double {
            seed = seed &* 6364136223846793005 &+ 1
            return Double(seed % 10_000) / 10_000
        }
        var bpmEvents: [(beat: Double, bpm: Double)] = []
        var stopEvents: [(beat: Double, durationSeconds: Double)] = []
        for _ in 0..<40 {
            bpmEvents.append((beat: unit() * 30 - 8, bpm: 40 + unit() * 200))
            stopEvents.append((beat: unit() * 30 - 8, durationSeconds: 0.05 + unit()))
        }
        bpmEvents.append((beat: 2, bpm: 100))
        bpmEvents.append((beat: 2, bpm: 0))
        bpmEvents.append((beat: 2, bpm: 150))
        stopEvents.append((beat: 2, durationSeconds: 0.2))
        stopEvents.append((beat: 2, durationSeconds: 0.2))
        let randomTiming = PreviewAudioTiming(headerBPM: -5, bpmEvents: bpmEvents, stopEvents: stopEvents)
        let fast = PreviewPlayfieldTimeIndex(timing: randomTiming)
        for _ in 0..<1000 {
            let beat = unit() * 40 - 12
            let origin = unit() * 40 - 12
            let slow = PreviewPlayfieldClock.arrivalSeconds(beat: beat, origin: origin, timing: randomTiming)
            let got = fast.arrival(beat: beat, origin: origin)
            require(abs(got - slow) <= 1e-8, "random arrival \(got) vs \(slow)")
        }
        let view = makeView(width: 331, height: 256)
        view.setChart(PreviewChartSnapshot(
            title: "Index",
            lanes: [PreviewVisualLane(id: "k", title: "1")],
            notes: [PreviewVisualNote(laneID: "k", startBeat: 0, endBeat: 0)],
            barBeats: [],
            endBeat: 4
        ))
        view.setTiming(sameBeat, fromBeat: -2)
        let arrival = PreviewPlayfieldClock.arrivalSeconds(beat: 0, origin: -2, timing: sameBeat)
        view.setPlayback(beat: 0, elapsedSeconds: arrival, isPlaying: true)
        require(view.currentScene().hits.first?.ageMilliseconds == 0, "the view schedule uses F(note)-F(origin), age \(view.currentScene().hits.first?.ageMilliseconds ?? -1)")
    }

    private static func expectArrival(
        _ timing: PreviewAudioTiming,
        beat: Double,
        origin: Double,
        expected: Double?,
        label: String
    ) {
        let slow = PreviewPlayfieldClock.arrivalSeconds(beat: beat, origin: origin, timing: timing)
        let fast = PreviewPlayfieldTimeIndex(timing: timing).arrival(beat: beat, origin: origin)
        if let expected {
            require(abs(slow - expected) <= 1e-9, "\(label) slow \(slow)")
        }
        require(abs(fast - slow) <= 1e-8, "\(label) fast \(fast) slow \(slow)")
    }

    /// 416280 的正弦表和银行家舍入。不调用产品的坐标函数。
    private enum IndependentEffect {
        static let table: [Double] = {
            let pi = 3.1415926535897
            return (0..<256).map { sin(Double($0) * pi / 128) }
        }()

        static func bank(_ value: Double) -> Int {
            guard value.isFinite else { return 0 }
            let negative = value < 0
            let magnitude = abs(value)
            let whole = floor(magnitude)
            let fraction = magnitude - whole
            let rounded: Double
            if fraction < 0.5 {
                rounded = whole
            } else if fraction > 0.5 {
                rounded = whole + 1
            } else if Int(whole) % 2 == 0 {
                rounded = whole
            } else {
                rounded = whole + 1
            }
            return Int(negative ? -rounded : rounded)
        }

        static func sine(_ degrees: Double) -> Double {
            var index = bank(degrees * 256 / 360) % 256
            if index < 0 { index += 256 }
            return table[index]
        }

        static func greatX(combo: Int, side: Int) -> Int {
            guard combo > 0 else { return side + 35 }
            let digits = String(min(combo, 999_999)).count
            return side + 119 - 40 - (digits * 15 + 88) / 2
        }

        static func digitX(greatX: Int, index: Int) -> Int {
            greatX + 81 - 7 + 15 * index
        }

        static func greatLayout(_ age: Int) -> (y: Int, height: Int) {
            guard age < 90 else { return (161, 14) }
            let scale = sine(Double(age) + 90)
            return (bank(161 - 3.5 * scale), bank(14 + 7 * scale))
        }

        static func digitLayout(age: Int, index: Int, wall: Int) -> (y: Int, height: Int) {
            let swing = sine(Double(wall) + Double(180 * index))
            let sway = bank(161 + swing * (6 - Double(age) / 180) * 0.5)
            guard age < 90 else { return (sway, 14) }
            let scale = sine(Double(age) + 90)
            return (bank(Double(sway) - 7 * scale), bank(14 + 14 * scale))
        }

        static func frame(_ wallMs: Int) -> Int {
            (max(wallMs, 0) / 50) % 5
        }

        static func stretched(
            destX: Int,
            destY: Int,
            destHeight: Int,
            sourceX: Int,
            sourceY: Int,
            sourceMinX: Int,
            sourceMinY: Int,
            sourceHeight: Int
        ) -> CGPoint {
            let pixelX = destX + (sourceX - sourceMinX)
            let height = max(destHeight, 1)
            let continuous = Double(destY) + (Double(sourceY) + 0.5 - Double(sourceMinY)) * Double(height) / Double(sourceHeight) - 0.5
            let pixelY = Int(continuous.rounded())
            return CGPoint(x: CGFloat(pixelX) + 0.2, y: CGFloat(pixelY) + 0.2)
        }

        static func greatPoint(combo: Int, side: Int, ageMs: Int, wallMs: Int, atlasX: Int, atlasY: Int) -> CGPoint {
            let layout = greatLayout(ageMs)
            return stretched(
                destX: greatX(combo: combo, side: side),
                destY: layout.y,
                destHeight: layout.height,
                sourceX: atlasX,
                sourceY: atlasY,
                sourceMinX: 9,
                sourceMinY: 106 + frame(wallMs) * 15,
                sourceHeight: 14
            )
        }

        static func digitPoint(
            combo: Int,
            side: Int,
            ageMs: Int,
            wallMs: Int,
            digit: Int,
            index: Int,
            localX: Int,
            localY: Int
        ) -> CGPoint {
            let layout = digitLayout(age: ageMs, index: index, wall: wallMs)
            let sourceMinX = 9 + digit * 15
            let sourceMinY = 1 + frame(wallMs) * 15
            return stretched(
                destX: digitX(greatX: greatX(combo: combo, side: side), index: index),
                destY: layout.y,
                destHeight: layout.height,
                sourceX: sourceMinX + localX,
                sourceY: sourceMinY + localY,
                sourceMinX: sourceMinX,
                sourceMinY: sourceMinY,
                sourceHeight: 14
            )
        }
    }

    /// 尾音、短音爆炸、整数 GREAT/数字和每玩家判定。坐标来自独立正弦表，不读产品的坐标函数。
    @MainActor
    private static func testFiniteTailAndPlayerJudges() {
        require(IndependentEffect.greatX(combo: 0, side: 0) == 35, "no combo stays at 35")
        require(IndependentEffect.greatX(combo: 3, side: 0) == 28, "1 digit is 28")
        require(IndependentEffect.greatX(combo: 12, side: 0) == 20, "2 digits are 20")
        require(IndependentEffect.greatX(combo: 100, side: 0) == 13, "3 digits are 13")
        require(IndependentEffect.digitX(greatX: 28, index: 1) == 117, "the first digit is great.right+8")
        require(IndependentEffect.digitX(greatX: 20, index: 1) == 109, "2-digit first cell")
        require(IndependentEffect.digitX(greatX: 13, index: 1) == 102, "3-digit first cell")
        require(IndependentEffect.digitX(greatX: 28, index: 2) == 132, "the second digit steps 15")
        let zoomCases = [
            (0, 158, 21, 154, 28),
            (30, 158, 20, 154, 26),
            (60, 159, 17, 156, 21),
            (89, 161, 14, 158, 14),
            (90, 161, 14, 158, 14),
            (120, 161, 14, 159, 14),
            (1079, 161, 14, 161, 14),
            (1080, 161, 14, 161, 14)
        ]
        for item in zoomCases {
            let great = IndependentEffect.greatLayout(item.0)
            let digit = IndependentEffect.digitLayout(age: item.0, index: 1, wall: item.0)
            require(great.y == item.1 && great.height == item.2, "GREAT zoom at \(item.0) ms is \(great)")
            require(digit.y == item.3 && digit.height == item.4, "digit sway at \(item.0) ms is \(digit)")
        }
        require(IndependentEffect.greatLayout(60).height != 14, "60 ms is still inside the 90 ms zoom")
        let away = IndependentEffect.digitLayout(age: 0, index: 1, wall: 500)
        require(away.y == 152 && away.height == 28, "sway uses the effect wall, not the hit age")

        guard let skin2 = calibratedPng(named: "skin_02.png"),
              let skin3 = calibratedPng(named: "skin_03.png") else {
            fail("missing judgment atlases")
        }
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
        let lanes = [
            PreviewVisualLane(id: "s", title: "S", isScratch: true),
            PreviewVisualLane(id: "k", title: "1")
        ]
        func host(_ notes: [PreviewVisualNote]) -> PreviewPlayfieldView {
            let view = makeView(width: 331, height: 256)
            requireMetal(view)
            view.pixelsPerBeat = 96
            view.setChart(PreviewChartSnapshot(title: "US7", lanes: lanes, notes: notes, barBeats: [], endBeat: 16))
            view.setTiming(timing, fromBeat: 0)
            return view
        }
        var shortLocal: (x: Int, y: Int)?
        for y in 24..<56 {
            for x in 36..<80 {
                guard let first = skin3.rgb(1 + x, 66 + y), let later = skin3.rgb(1 + 5 * 96 + x, 66 + y) else { continue }
                if first == later || isKeyed(first) || isKeyed(later) { continue }
                shortLocal = (x, y)
                break
            }
            if shortLocal != nil { break }
        }
        guard let shortLocal else { fail("skin_03 middle row has no frame-0/5 difference") }
        let shortView = host([PreviewVisualNote(laneID: "k", startBeat: 4, endBeat: 4)])
        shortView.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        let beforeBomb = shortView.renderMetalReadback()
        requireMetalReadback(beforeBomb)
        func shortBombPoint() -> CGPoint {
            let scene = shortView.currentScene()
            guard let column = scene.lanes.first(where: { $0.id == "k" }) else { fail("missing short lane") }
            let centerX = column.rect.minX + 8 * scene.placement.scale
            let left = centerX - 48 * scene.placement.scale
            let top = scene.placement.origin.y + 224 * scene.placement.scale - 48 * scene.placement.scale
            return CGPoint(x: left + CGFloat(shortLocal.x) + 0.2, y: top + CGFloat(shortLocal.y) + 0.2)
        }
        for frame in 0..<6 {
            let age = Double(frame) * 0.02
            shortView.setPlayback(beat: 4, elapsedSeconds: 2 + age, isPlaying: true)
            let image = shortView.renderMetalReadback()
            requireMetalReadback(image)
            guard let want = skin3.rgb(1 + frame * 96 + shortLocal.x, 66 + shortLocal.y) else {
                fail("missing short bomb texel \(frame)")
            }
            let point = shortBombPoint()
            require(near(sample(image, point, viewSize: shortView.bounds.size), want, tolerance: 0), "short bomb frame \(frame) at \(Int(age * 1000)) ms")
            require(shortView.currentScene().hits.contains { $0.laneID == "k" && !$0.isLong }, "a short bomb is not dropped as a long note")
        }
        shortView.setPlayback(beat: 4, elapsedSeconds: 2.12, isPlaying: true)
        let clearedBomb = shortView.renderMetalReadback()
        requireMetalReadback(clearedBomb)
        let bombPoint = shortBombPoint()
        let restored = sample(beforeBomb, bombPoint, viewSize: shortView.bounds.size)
        require(
            near(sample(clearedBomb, bombPoint, viewSize: shortView.bounds.size), (restored.r, restored.g, restored.b), tolerance: 0),
            "short bomb is gone at 120 ms"
        )

        let tail = host([
            PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8),
            PreviewVisualNote(laneID: "k", startBeat: 40, endBeat: 40)
        ])
        tail.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        tail.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        let held = tail.currentScene()
        guard let heldHit = held.hits.first(where: { $0.laneID == "s" }) else { fail("2× did not latch the long note") }
        require(heldHit.isLong && heldHit.tailAgeMilliseconds == nil && heldHit.ageMilliseconds == 0, "the hold has not reached the tail")
        require(held.combo == 1 && held.sideJudges.count == 1 && held.sideJudges[0].combo == 1, "the tail does not add a combo")
        tail.setPlayback(beat: 6, chartElapsedSeconds: 3, effectElapsedSeconds: 1.5, isPlaying: true)
        require(tail.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == nil, "chart 3 is still inside the hold")
        tail.setPlayback(beat: 8, chartElapsedSeconds: 4, effectElapsedSeconds: 2, isPlaying: false)
        let tailStart = tail.currentScene()
        require(tailStart.hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 0, "pause keeps the tail birth")
        require(tailStart.combo == 1 && tailStart.sideJudges.first?.combo == 1, "ending the hold does not add a combo")
        tail.setPlayback(beat: 8, chartElapsedSeconds: 4, effectElapsedSeconds: 2, isPlaying: false)
        require(tail.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 0, "a paused wall does not age the tail")
        let tailImage = tail.renderMetalReadback()
        requireMetalReadback(tailImage)
        guard let tailTexel = skin3.rgb(1 + shortLocal.x, 66 + shortLocal.y) else { fail("missing tail texel") }
        let scratchTail = judgmentPoint(tail, lane: "s", local: shortLocal, side: 96)
        require(near(sample(tailImage, scratchTail, viewSize: tail.bounds.size), tailTexel, tolerance: 0), "the tail uses the 96 middle row")
        tail.setPlayback(beat: 8, chartElapsedSeconds: 4.2, effectElapsedSeconds: 2.1, isPlaying: true)
        require(tail.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 100, "0.5× of the remaining chart is not the tail clock")
        tail.setPlayback(beat: 12, chartElapsedSeconds: 12, effectElapsedSeconds: 6, isPlaying: true)
        let after = tail.currentScene()
        require(after.hits.contains { $0.laneID == "s" } == false, "chart 12 does not keep a 5000 ms long bomb")
        require(after.sideJudges.isEmpty, "the finished tail does not keep GREAT")
        require(after.combo == 1, "scene.combo stays the started-note total")
        let afterImage = tail.renderMetalReadback()
        requireMetalReadback(afterImage)
        require(!near(sample(afterImage, scratchTail, viewSize: tail.bounds.size), tailTexel, tolerance: 0), "the tail bomb is gone without another lane")

        let half = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        half.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        half.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 4, isPlaying: true)
        var halfChart = 2.0
        var halfWall = 4.0
        while halfChart < 4 {
            let nextChart = min(halfChart + 0.4, 4)
            let nextWall = halfWall + (nextChart - halfChart) * 2
            half.setPlayback(beat: nextChart * 2, chartElapsedSeconds: nextChart, effectElapsedSeconds: nextWall, isPlaying: true)
            halfChart = nextChart
            halfWall = nextWall
        }
        require(abs(halfWall - 8) < 1e-9, "0.5× reaches the tail at wall 8")
        require(half.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 0, "0.5× tail birth is wall 8")
        half.setPlayback(beat: 8, chartElapsedSeconds: 4.05, effectElapsedSeconds: 8.1, isPlaying: true)
        require(half.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 100, "0.5× tail age follows the wall")
        half.setPlayback(beat: 8, chartElapsedSeconds: 4.1, effectElapsedSeconds: 8.12, isPlaying: true)
        require(half.currentScene().hits.contains { $0.laneID == "s" && ($0.tailAgeMilliseconds ?? 0) < 120 } == false, "0.5× tail ends at 120 ms")

        let stopped = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 8, durationSeconds: 2)])
        let stop = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        stop.setTiming(stopped, fromBeat: 0)
        stop.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        stop.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 2, isPlaying: true)
        stop.setPlayback(beat: 6, chartElapsedSeconds: 3, effectElapsedSeconds: 3, isPlaying: true)
        stop.setPlayback(beat: 8, chartElapsedSeconds: 4, effectElapsedSeconds: 4, isPlaying: true)
        require(stop.currentScene().playbackBeat == 8, "STOP keeps beat 8")
        require(stop.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 0, "the tail starts when the end arrival is reached")
        stop.setPlayback(beat: 8, chartElapsedSeconds: 5, effectElapsedSeconds: 5, isPlaying: true)
        require(stop.currentScene().playbackBeat == 8, "STOP still holds the beat")
        require(stop.currentScene().hits.contains { $0.laneID == "s" } == false, "STOP does not extend the tail past 120 ms")

        let hidden = host([
            PreviewVisualNote(laneID: "s", startBeat: 2, endBeat: 6),
            PreviewVisualNote(laneID: "s", startBeat: 2.02, endBeat: 2.02)
        ])
        hidden.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        hidden.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5, isPlaying: true)
        guard hidden.currentScene().hits.contains(where: { $0.laneID == "s" && $0.isLong && $0.tailAgeMilliseconds == nil }) else {
            fail("the long note was not held before the hidden jump")
        }
        hidden.setPlayback(beat: 10, chartElapsedSeconds: 5, effectElapsedSeconds: 2.5, isPlaying: true)
        require(hidden.currentScene().hits.contains { $0.laneID == "s" } == false, "an expired new note clears the old long latch on that frame")

        let players = makeView(width: 331, height: 256)
        requireMetal(players)
        players.pixelsPerBeat = 96
        players.setChart(PreviewChartSnapshot(
            title: "Players",
            lanes: [
                PreviewVisualLane(id: "a", title: "1", player: 1),
                PreviewVisualLane(id: "b", title: "2", player: 1),
                PreviewVisualLane(id: "c", title: "3", player: 1),
                PreviewVisualLane(id: "d", title: "1", player: 2)
            ],
            notes: [
                PreviewVisualNote(laneID: "a", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "b", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "c", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "d", startBeat: 4, endBeat: 4)
            ],
            barBeats: [],
            endBeat: 8
        ))
        players.setTiming(timing, fromBeat: 4)
        players.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        let both = players.currentScene()
        require(both.combo == 4, "scene.combo keeps the combined total")
        require(both.sideJudges.count == 2, "both players keep a judgment")
        require(both.sideJudges.contains { $0.player == 1 && $0.combo == 3 && $0.ageMilliseconds == 0 && $0.originX == 0 }, "1P combo is 3")
        require(both.sideJudges.contains { $0.player == 2 && $0.combo == 1 && $0.ageMilliseconds == 0 && $0.originX == 173 }, "2P combo is 1")
        let bothImage = players.renderMetalReadback()
        requireMetalReadback(bothImage)
        guard let yellow = skin2.rgb(19, 107) else { fail("missing GREAT yellow") }
        let onePoint = IndependentEffect.greatPoint(combo: 3, side: 0, ageMs: 0, wallMs: 0, atlasX: 19, atlasY: 107)
        let twoPoint = IndependentEffect.greatPoint(combo: 1, side: 173, ageMs: 0, wallMs: 0, atlasX: 19, atlasY: 107)
        require(near(sample(bothImage, onePoint, viewSize: players.bounds.size), yellow, tolerance: 0), "1P GREAT is at integer x=28")
        require(near(sample(bothImage, twoPoint, viewSize: players.bounds.size), yellow, tolerance: 0), "2P GREAT is at 173+28")

        let split = makeView(width: 331, height: 256)
        requireMetal(split)
        split.pixelsPerBeat = 96
        split.setChart(PreviewChartSnapshot(
            title: "Split",
            lanes: [
                PreviewVisualLane(id: "a", title: "1", player: 1),
                PreviewVisualLane(id: "d", title: "1", player: 2)
            ],
            notes: [
                PreviewVisualNote(laneID: "a", startBeat: 2, endBeat: 2),
                PreviewVisualNote(laneID: "d", startBeat: 4, endBeat: 4)
            ],
            barBeats: [],
            endBeat: 8
        ))
        split.setTiming(timing, fromBeat: 0)
        split.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        split.setPlayback(beat: 2, elapsedSeconds: 1, isPlaying: true)
        split.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: true)
        let together = split.currentScene()
        require(together.sideJudges.contains { $0.player == 1 && $0.ageMilliseconds == 1000 }, "1P keeps its own age")
        require(together.sideJudges.contains { $0.player == 2 && $0.ageMilliseconds == 0 }, "2P starts later")
        split.setPlayback(beat: 4.2, elapsedSeconds: 2.1, isPlaying: true)
        let expired = split.currentScene()
        require(expired.sideJudges.count == 1 && expired.sideJudges[0].player == 2, "1P expiry does not remove 2P")
        require(expired.sideJudges[0].ageMilliseconds == 100, "2P age is independent")
        require(expired.combo == 2, "the combined combo remains")

        guard let digitInk = firstDigitInk(skin2, digit: 3, frame: 0) else { fail("missing digit 3 ink") }
        let digitLocalX = digitInk.x - (9 + 3 * 15)
        let digitLocalY = digitInk.y - 1
        let digits = host([
            PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 4),
            PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 4),
            PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 4)
        ])
        for age in [0, 30, 60, 89, 90, 120, 1079] {
            let wall = 2000 + age
            digits.setPlayback(beat: 4, elapsedSeconds: 2 + Double(age) / 1000, isPlaying: true)
            let image = digits.renderMetalReadback()
            requireMetalReadback(image)
            let point = IndependentEffect.digitPoint(
                combo: 3, side: 0, ageMs: age, wallMs: wall, digit: 3, index: 1, localX: digitLocalX, localY: digitLocalY
            )
            let sourceY = 1 + IndependentEffect.frame(wall) * 15 + digitLocalY
            guard let want = skin2.rgb(digitInk.x, sourceY) else { fail("missing digit frame \(age)") }
            require(near(sample(image, point, viewSize: digits.bounds.size), want, tolerance: 0), "digit ROI at \(age) ms \(point)")
        }
        digits.setPlayback(beat: 4, elapsedSeconds: 2 + 1.08, isPlaying: true)
        let ended = digits.renderMetalReadback()
        requireMetalReadback(ended)
        require(digits.currentScene().sideJudges.isEmpty, "1080 ms removes the judgment")
        let stale = IndependentEffect.digitPoint(
            combo: 3, side: 0, ageMs: 1079, wallMs: 3079, digit: 3, index: 1, localX: digitLocalX, localY: digitLocalY
        )
        guard let staleInk = skin2.rgb(digitInk.x, 1 + IndependentEffect.frame(3079) * 15 + digitLocalY) else {
            fail("missing stale digit")
        }
        require(!near(sample(ended, stale, viewSize: digits.bounds.size), staleInk, tolerance: 0), "1080 ms no longer draws the digit")

        let wide = host((0..<9).map { _ in PreviewVisualNote(laneID: "s", startBeat: 0, endBeat: 0) } + [PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 4)])
        wide.setTiming(timing, fromBeat: 4)
        wide.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        require(wide.currentScene().sideJudges.first?.combo == 10, "two-digit combo")
        let wideImage = wide.renderMetalReadback()
        requireMetalReadback(wideImage)
        guard let oneInk = firstDigitInk(skin2, digit: 1, frame: 0) else { fail("missing digit 1") }
        let oneLocalX = oneInk.x - (9 + 15)
        let oneLocalY = oneInk.y - 1
        let twoDigit = IndependentEffect.digitPoint(
            combo: 10, side: 0, ageMs: 0, wallMs: 0, digit: 1, index: 1, localX: oneLocalX, localY: oneLocalY
        )
        guard let oneColor = skin2.rgb(oneInk.x, oneInk.y) else { fail("missing digit 1 color") }
        require(near(sample(wideImage, twoDigit, viewSize: wide.bounds.size), oneColor, tolerance: 0), "2-digit cell is at x=109")
        let oldFirst = CGPoint(x: CGFloat(IndependentEffect.greatX(combo: 10, side: 0) + 81 - 7) + 0.2, y: twoDigit.y)
        require(!near(sample(wideImage, oldFirst, viewSize: wide.bounds.size), oneColor, tolerance: 0), "the first digit is not great.right-7")

        var hundred: [PreviewVisualNote] = (0..<99).map { _ in PreviewVisualNote(laneID: "s", startBeat: 0, endBeat: 0) }
        hundred.append(PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 4))
        let triple = host(hundred)
        triple.setTiming(timing, fromBeat: 4)
        triple.setPlayback(beat: 4, elapsedSeconds: 0, isPlaying: true)
        require(triple.currentScene().sideJudges.first?.combo == 100, "three-digit combo")
        let tripleImage = triple.renderMetalReadback()
        requireMetalReadback(tripleImage)
        let threeDigit = IndependentEffect.digitPoint(
            combo: 100, side: 0, ageMs: 0, wallMs: 0, digit: 1, index: 1, localX: oneLocalX, localY: oneLocalY
        )
        require(near(sample(tripleImage, threeDigit, viewSize: triple.bounds.size), oneColor, tolerance: 0), "3-digit cell is at x=102")
    }

    /// 隐藏间隙里的持有和尾音各自恢复，不重播 GREAT。逻辑时钟不碰几何。
    @MainActor
    private static func testHiddenHoldTailRecoveryAndLogicClock() {
        guard let skin2 = calibratedPng(named: "skin_02.png"),
              let skin3 = calibratedPng(named: "skin_03.png"),
              let yellow = skin2.rgb(19, 107) else {
            fail("missing US8 atlases")
        }
        var holdLocal: (x: Int, y: Int)?
        for y in 0..<64 {
            for x in 20..<64 {
                guard let first = skin3.rgb(1 + x, 163 + y), let later = skin3.rgb(1 + 5 * 64 + x, 163 + y) else { continue }
                if first == later || isKeyed(first) || isKeyed(later) { continue }
                holdLocal = (x, y)
                break
            }
            if holdLocal != nil { break }
        }
        var tailLocal: (x: Int, y: Int)?
        for y in 24..<56 {
            for x in 36..<80 {
                guard let first = skin3.rgb(1 + x, 66 + y), let later = skin3.rgb(1 + 5 * 96 + x, 66 + y) else { continue }
                if first == later || isKeyed(first) || isKeyed(later) { continue }
                tailLocal = (x, y)
                break
            }
            if tailLocal != nil { break }
        }
        guard let holdLocal, let tailLocal else { fail("skin_03 has no independent hold/tail texels") }
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
        func host(_ notes: [PreviewVisualNote]) -> PreviewPlayfieldView {
            let view = makeView(width: 331, height: 256)
            requireMetal(view)
            view.pixelsPerBeat = 96
            view.setChart(PreviewChartSnapshot(
                title: "US8",
                lanes: [
                    PreviewVisualLane(id: "s", title: "S", isScratch: true),
                    PreviewVisualLane(id: "k", title: "1")
                ],
                notes: notes,
                barBeats: [],
                endBeat: 64
            ))
            view.setTiming(timing, fromBeat: 0)
            return view
        }

        let p1 = host([PreviewVisualNote(laneID: "s", startBeat: 0, endBeat: 32)])
        p1.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        p1.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        let held = p1.currentScene()
        guard let heldHit = held.hits.first(where: { $0.laneID == "s" }) else { fail("P1 did not latch the hold") }
        require(heldHit.ageMilliseconds == 1000 && heldHit.tailAgeMilliseconds == nil, "P1 age is 1000 ms before the hidden jump")
        require(held.combo == 1 && held.sideJudges.count == 1, "P1 combo is 1 while GREAT is still visible")
        p1.setPlayback(beat: 12, chartElapsedSeconds: 6, effectElapsedSeconds: 3, isPlaying: true)
        let hiddenHold = p1.currentScene()
        guard let hiddenHit = hiddenHold.hits.first(where: { $0.laneID == "s" }) else { fail("P1 dropped the hold across the hidden gap") }
        require(hiddenHit.ageMilliseconds == 3000 && hiddenHit.tailAgeMilliseconds == nil, "P1 keeps birthWall 0, age 3000 ms")
        require(hiddenHold.combo == 1 && hiddenHold.sideJudges.isEmpty, "P1 does not replay GREAT or add combo")
        let holdImage = p1.renderMetalReadback()
        requireMetalReadback(holdImage)
        guard let holdTexel = skin3.rgb(1 + holdLocal.x, 163 + holdLocal.y) else { fail("missing hold texel") }
        let holdPoint = bombPoint(in: p1, lane: "s", local: holdLocal)
        require(near(sample(holdImage, holdPoint, viewSize: p1.bounds.size), holdTexel, tolerance: 0), "P1 hold matches skin_03 y=163 64")
        let newGreat = IndependentEffect.greatPoint(combo: 1, side: 0, ageMs: 0, wallMs: 3000, atlasX: 19, atlasY: 107)
        require(!near(sample(holdImage, newGreat, viewSize: p1.bounds.size), yellow, tolerance: 0), "P1 GREAT is not a fresh yellow judgment")
        p1.setPlayback(beat: 12.04, chartElapsedSeconds: 6.02, effectElapsedSeconds: 3.01, isPlaying: true)
        let nextHold = p1.currentScene()
        require(nextHold.hits.first { $0.laneID == "s" }?.ageMilliseconds == 3010, "the next frame is still the same birth")
        require(nextHold.hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == nil, "P1 is still holding")
        require(nextHold.combo == 1 && nextHold.sideJudges.isEmpty, "combo stays 1 after the next frame")

        let p2 = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        p2.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        p2.setPlayback(beat: 8.4, chartElapsedSeconds: 4.2, effectElapsedSeconds: 2.1, isPlaying: true)
        let recovered = p2.currentScene()
        guard let recoveredHit = recovered.hits.first(where: { $0.laneID == "s" }) else { fail("P2 did not recover the tail") }
        require(recoveredHit.ageMilliseconds == 1100 && recoveredHit.tailAgeMilliseconds == 100, "P2 head 1100 ms / tail 100 ms, not age 0")
        require(recovered.sideJudges.isEmpty && recovered.combo == 1, "P2 does not replay GREAT or add combo")
        let tailImage = p2.renderMetalReadback()
        requireMetalReadback(tailImage)
        guard let tailTexel = skin3.rgb(1 + 5 * 96 + tailLocal.x, 66 + tailLocal.y) else { fail("missing tail texel") }
        let tailPoint = judgmentPoint(p2, lane: "s", local: tailLocal, side: 96)
        require(near(sample(tailImage, tailPoint, viewSize: p2.bounds.size), tailTexel, tolerance: 0), "P2 tail matches skin_03 y=66 96")
        p2.setPlayback(beat: 8.4, chartElapsedSeconds: 4.2, effectElapsedSeconds: 2.119, isPlaying: true)
        let almost = p2.currentScene()
        require(almost.hits.first { $0.laneID == "s" }?.ageMilliseconds == 1119, "119 ms tail still has head age 1119")
        require(almost.hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 119, "tail stays at 119 ms")
        require(almost.sideJudges.isEmpty, "119 ms tail does not revive GREAT")
        p2.setPlayback(beat: 8.4, chartElapsedSeconds: 4.2, effectElapsedSeconds: 2.120, isPlaying: true)
        let gone = p2.currentScene()
        require(gone.hits.contains { $0.laneID == "s" } == false, "120 ms clears the tail")
        require(gone.sideJudges.isEmpty, "120 ms does not create a new GREAT")

        let ghost = host([
            PreviewVisualNote(laneID: "s", startBeat: 2, endBeat: 6),
            PreviewVisualNote(laneID: "s", startBeat: 2.02, endBeat: 2.02)
        ])
        ghost.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        ghost.setPlayback(beat: 2, chartElapsedSeconds: 1, effectElapsedSeconds: 0.5, isPlaying: true)
        ghost.setPlayback(beat: 10, chartElapsedSeconds: 5, effectElapsedSeconds: 2.5, isPlaying: true)
        require(ghost.currentScene().hits.contains { $0.laneID == "s" } == false, "an expired short on the same lane still drops the old long")

        let late = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        late.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        late.setPlayback(beat: 40, chartElapsedSeconds: 20, effectElapsedSeconds: 10, isPlaying: true)
        require(late.currentScene().hits.contains { $0.laneID == "s" } == false, "a jump far past the tail does not keep a bomb")
        late.setPlayback(beat: 40.02, chartElapsedSeconds: 20.01, effectElapsedSeconds: 10.01, isPlaying: true)
        require(late.currentScene().hits.contains { $0.laneID == "s" } == false, "the next frame does not invent an infinite bomb")

        func rateHost() -> PreviewPlayfieldView {
            host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 32)])
        }
        func assertKeptBirth(_ view: PreviewPlayfieldView, wall: Double, age: Int, label: String) {
            guard let hit = view.currentScene().hits.first(where: { $0.laneID == "s" }) else {
                fail("\(label) dropped the hold")
            }
            require(hit.tailAgeMilliseconds == nil && hit.ageMilliseconds == age, "\(label) birth stays, age \(hit.ageMilliseconds)")
            require(abs((wall - Double(age) / 1000) - (wall - hit.ageBeats)) < 1e-6, "\(label) uses the original birth")
        }
        let half = rateHost()
        half.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        half.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 4, isPlaying: true)
        half.setPlayback(beat: 12, chartElapsedSeconds: 6, effectElapsedSeconds: 12, isPlaying: true)
        assertKeptBirth(half, wall: 12, age: 8000, label: "0.5×")
        let double = rateHost()
        double.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        double.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        double.setPlayback(beat: 12, chartElapsedSeconds: 6, effectElapsedSeconds: 3, isPlaying: true)
        assertKeptBirth(double, wall: 3, age: 2000, label: "2×")
        let quad = rateHost()
        quad.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        quad.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 0.5, isPlaying: true)
        quad.setPlayback(beat: 20, chartElapsedSeconds: 10, effectElapsedSeconds: 2.5, isPlaying: true)
        assertKeptBirth(quad, wall: 2.5, age: 2000, label: "4×")

        let stopped = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [(beat: 8, durationSeconds: 2)])
        let stop = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        stop.setTiming(stopped, fromBeat: 0)
        stop.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        stop.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 2, isPlaying: true)
        stop.setPlayback(beat: 6, chartElapsedSeconds: 3, effectElapsedSeconds: 3, isPlaying: true)
        require(stop.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == nil, "STOP still holds before the end")
        stop.setPlayback(beat: 8, chartElapsedSeconds: 4, effectElapsedSeconds: 4, isPlaying: true)
        require(stop.currentScene().playbackBeat == 8, "STOP freezes the beat")
        require(stop.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 0, "the tail starts at the end arrival")
        stop.setPlayback(beat: 8, chartElapsedSeconds: 4.05, effectElapsedSeconds: 4.05, isPlaying: true)
        require(stop.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 50, "STOP tail follows the wall")
        stop.setPlayback(beat: 8, chartElapsedSeconds: 5, effectElapsedSeconds: 5, isPlaying: true)
        require(stop.currentScene().hits.contains { $0.laneID == "s" } == false, "STOP tail ends at 120 ms wall")

        let changed = PreviewAudioTiming(headerBPM: 120, bpmEvents: [(beat: 2, bpm: 240)], stopEvents: [])
        let bpm = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        bpm.setTiming(changed, fromBeat: 0)
        let startArrival = PreviewPlayfieldClock.arrivalSeconds(beat: 4, origin: 0, timing: changed)
        let endArrival = PreviewPlayfieldClock.arrivalSeconds(beat: 8, origin: 0, timing: changed)
        require(abs(startArrival - 1.5) < 1e-9 && abs(endArrival - 2.5) < 1e-9, "BPM arrivals follow the index")
        bpm.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        bpm.setPlayback(beat: 4, chartElapsedSeconds: startArrival, effectElapsedSeconds: startArrival, isPlaying: true)
        require(bpm.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 0, "BPM start is age 0")
        bpm.setPlayback(beat: 6, chartElapsedSeconds: 2.0, effectElapsedSeconds: 2.0, isPlaying: true)
        require(bpm.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == nil, "chart 2.0 is still before end 2.5")
        require(bpm.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 500, "BPM hidden gap keeps the original birth")

        let here = host([
            PreviewVisualNote(laneID: "s", startBeat: 0, endBeat: 32),
            PreviewVisualNote(laneID: "k", startBeat: 4, endBeat: 4)
        ])
        here.setTiming(timing, fromBeat: 4)
        here.setPlayback(beat: 4, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        let hereScene = here.currentScene()
        require(hereScene.hits.count == 1 && hereScene.hits[0].laneID == "k", "Here does not resurrect the note before the origin")
        require(hereScene.hits[0].ageMilliseconds == 0, "the origin short is age 0")

        let rewind = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 32)])
        rewind.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        rewind.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        require(rewind.currentScene().hits.contains { $0.laneID == "s" && $0.ageMilliseconds == 0 }, "rewind setup hit")
        rewind.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        require(rewind.currentScene().hits.contains { $0.laneID == "s" } == false, "rewind clears the latch")
        rewind.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        require(rewind.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 0, "crossing again after rewind can re-birth")

        let pause = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 32)])
        pause.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        pause.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        pause.setPlayback(beat: 4.2, chartElapsedSeconds: 2.1, effectElapsedSeconds: 1.1, isPlaying: true)
        require(pause.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 100, "pause setup age")
        pause.setPlayback(beat: 4.2, chartElapsedSeconds: 2.1, effectElapsedSeconds: 1.1, isPlaying: false)
        require(pause.currentScene().hits.first { $0.laneID == "s" }?.ageMilliseconds == 100, "the same timestamp does not age")
        let firstScene = pause.currentScene()
        let secondScene = pause.currentScene()
        require(firstScene.hits == secondScene.hits, "two currentScene calls keep the same hits")

        let logic = host([PreviewVisualNote(laneID: "s", startBeat: 4, endBeat: 8)])
        logic.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        let geo0 = logic.geometryBuildCount
        let live0 = logic.liveSubmitCount
        let pipe0 = logic.pipelineCompileCount
        let tickStarted = ProcessInfo.processInfo.systemUptime
        for step in 1...2000 {
            let t = Double(step) / 2000
            let chart = 2.1 + 2.0 * t
            logic.advancePlaybackClock(
                beat: chart * 2,
                chartElapsedSeconds: chart,
                effectElapsedSeconds: chart,
                isPlaying: true
            )
        }
        let tickSeconds = ProcessInfo.processInfo.systemUptime - tickStarted
        let nsPerTick = tickSeconds * 1_000_000_000 / 2000
        print("US8-logic-only-ns-per-tick=\(nsPerTick)")
        require(logic.geometryBuildCount == geo0, "advancePlaybackClock does not rebuild geometry")
        require(logic.liveSubmitCount == live0, "advancePlaybackClock does not submit a drawable")
        require(logic.pipelineCompileCount == pipe0, "advancePlaybackClock does not compile a pipeline")
        let walking = logic.currentScene()
        require(walking.hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 100, "currentScene sees the tail age after 2000 ticks")
        require(walking.hits.first { $0.laneID == "s" }?.ageMilliseconds == 2100, "head age follows the original interpolated birth")
        let geo1 = logic.geometryBuildCount
        let drawn = logic.renderMetalReadback()
        requireMetalReadback(drawn)
        require(logic.geometryBuildCount == geo1 + 1, "one draw rebuilds geometry once")
        require(logic.liveSubmitCount == live0 && logic.pipelineCompileCount == pipe0, "the offscreen draw does not compile or present live")
        require(logic.currentScene().hits.first { $0.laneID == "s" }?.tailAgeMilliseconds == 100, "the drawn frame matches the logic clock")
    }

    /// 独立 PNG source-over。切片来自 UR2 / DrawBomb，不调产品 bomb/cap sprite 函数。
    private enum IndependentStack {
        struct RGB: Equatable {
            var r: Double
            var g: Double
            var b: Double

            var tuple: (Double, Double, Double) { (r, g, b) }
        }

        struct Rect: Equatable {
            var x: Int
            var y: Int
            var w: Int
            var h: Int

            var maxX: Int { x + w }
            var maxY: Int { y + h }

            func contains(_ px: Int, _ py: Int) -> Bool {
                px >= x && px < maxX && py >= y && py < maxY
            }

            func intersection(_ other: Rect) -> Rect? {
                let left = max(x, other.x)
                let top = max(y, other.y)
                let right = min(maxX, other.maxX)
                let bottom = min(maxY, other.maxY)
                guard right > left, bottom > top else { return nil }
                return Rect(x: left, y: top, w: right - left, h: bottom - top)
            }

            func clipped(to width: Int, height: Int) -> Rect? {
                intersection(Rect(x: 0, y: 0, w: width, h: height))
            }
        }

        struct Layer {
            var dest: Rect
            var sourceX: Int
            var sourceY: Int
            var atlas: PngTopLeft
            var isKey: (RGB) -> Bool
        }

        static func rgb(_ atlas: PngTopLeft, _ x: Int, _ y: Int) -> RGB? {
            guard let pixel = atlas.rgb(x, y) else { return nil }
            return RGB(r: pixel.0, g: pixel.1, b: pixel.2)
        }

        static func backgroundPixel(_ atlas: PngTopLeft, x: Int, y: Int, scratchRaw: Int) -> RGB? {
            var sourceX = x
            if x < 158, scratchRaw & 1 != 0 { sourceX = 173 + x }
            if (173..<331).contains(x), scratchRaw & 2 != 0 { sourceX = x - 173 }
            return rgb(atlas, sourceX, y)
        }

        static func isSkin01Key(_ color: RGB) -> Bool {
            (color.r == 0 && color.g == 1 && color.b == 0) || (color.r == 0 && color.g == 0 && color.b == 0)
        }

        static func isSkin03Key(_ color: RGB) -> Bool {
            let pink = color.r == 199.0 / 255.0 && color.g == 80.0 / 255.0 && color.b == 127.0 / 255.0
            return pink || (color.r == 0 && color.g == 0 && color.b == 0)
        }

        static func sourceOver(_ dest: RGB, _ source: RGB, isKey: (RGB) -> Bool) -> RGB {
            isKey(source) ? dest : source
        }

        static func bombFrame(_ ageMilliseconds: Int) -> Int {
            (max(ageMilliseconds, 0) / 20) % 6
        }

        static func columnX(channel: Int, scratchRaw: Int) -> Int {
            let seed = channel >= 21 ? 173 : 0
            let scratchLeft = channel >= 21 ? (scratchRaw & 2 != 0) : (scratchRaw & 1 == 0)
            let delta: Int
            if scratchLeft {
                switch channel {
                case 16, 26: delta = 1
                case 11, 21: delta = 34
                case 12, 22: delta = 53
                case 13, 23: delta = 69
                case 14, 24: delta = 88
                case 15, 25: delta = 104
                case 18, 28: delta = 123
                default: delta = 139
                }
            } else {
                switch channel {
                case 16, 26: delta = 125
                case 11, 21: delta = 1
                case 12, 22: delta = 20
                case 13, 23: delta = 36
                case 14, 24: delta = 55
                case 15, 25: delta = 71
                case 18, 28: delta = 90
                default: delta = 106
                }
            }
            return seed + delta
        }

        static func isScratch(_ channel: Int) -> Bool {
            channel == 16 || channel == 26
        }

        static func isBlue(_ channel: Int) -> Bool {
            [12, 14, 18, 22, 24, 28].contains(channel)
        }

        static func bombDest(channel: Int, scratchRaw: Int) -> Rect {
            let centerX = columnX(channel: channel, scratchRaw: scratchRaw) + (isScratch(channel) ? 16 : 8)
            return Rect(x: centerX - 48, y: 176, w: 96, h: 96)
        }

        static func bombLayer(channel: Int, ageMilliseconds: Int, scratchRaw: Int, skin3: PngTopLeft) -> Layer {
            let frame = bombFrame(ageMilliseconds)
            return Layer(
                dest: bombDest(channel: channel, scratchRaw: scratchRaw),
                sourceX: 1 + frame * 96,
                sourceY: 66,
                atlas: skin3,
                isKey: isSkin03Key
            )
        }

        static func capOffset(channel: Int, scratchRaw: Int) -> Int {
            if isScratch(channel) { return 2 }
            let oneLeft = scratchRaw & 1 == 0
            let twoLeft = scratchRaw & 2 != 0
            let scratchLeft = (channel == 21 || channel == 22) ? twoLeft : oneLeft
            if isBlue(channel) { return scratchLeft ? 2 : 1 }
            return scratchLeft ? 3 : 2
        }

        static func capDest(channel: Int, scratchRaw: Int) -> Rect {
            let x = columnX(channel: channel, scratchRaw: scratchRaw) + capOffset(channel: channel, scratchRaw: scratchRaw)
            if isScratch(channel) { return Rect(x: x, y: 226, w: 28, h: 28) }
            if isBlue(channel) { return Rect(x: x, y: 227, w: 12, h: 20) }
            return Rect(x: x, y: 233, w: 13, h: 20)
        }

        static func capLayer(channel: Int, scratchRaw: Int, skin1: PngTopLeft) -> Layer {
            let sourceX: Int
            let sourceY = 139
            if isScratch(channel) {
                sourceX = 96
            } else if isBlue(channel) {
                sourceX = 83
            } else {
                sourceX = 69
            }
            return Layer(
                dest: capDest(channel: channel, scratchRaw: scratchRaw),
                sourceX: sourceX,
                sourceY: sourceY,
                atlas: skin1,
                isKey: isSkin01Key
            )
        }

        static func sample(_ layer: Layer, x: Int, y: Int) -> RGB? {
            guard layer.dest.contains(x, y) else { return nil }
            return rgb(layer.atlas, layer.sourceX + (x - layer.dest.x), layer.sourceY + (y - layer.dest.y))
        }

        static func composite(background: RGB, layers: [Layer], x: Int, y: Int) -> RGB {
            var color = background
            for layer in layers {
                guard let source = sample(layer, x: x, y: y) else { continue }
                color = sourceOver(color, source, isKey: layer.isKey)
            }
            return color
        }
    }

    /// 键帽全部先画，爆炸按内部号盖住重叠。期望色来自独立 PNG source-over。
    @MainActor
    private static func testBombCoversKeyCapAndInternalDrawOrder() {
        guard let skin0 = calibratedPng(named: "skin_00.png"),
              let skin1 = calibratedPng(named: "skin_01.png"),
              let skin3 = calibratedPng(named: "skin_03.png") else {
            fail("missing atlases for the US9 source-over oracle")
        }
        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
        let ages = [0, 20, 40, 60, 100]
        let scales: [(Int, CGFloat, CGFloat)] = [
            (1, 331, 256),
            (2, 662, 512),
            (3, 993, 768)
        ]
        for (factor, width, height) in scales {
            let view = makeView(width: width, height: height)
            requireMetal(view)
            view.pixelsPerBeat = 96
            view.setUbmAppearance(scratchRaw: 0, effectsRaw: 7, autoSeparate: true)
            view.setChart(PreviewChartSnapshot(
                title: "US9 cap-bomb",
                lanes: [PreviewVisualLane(id: "11", title: "1")],
                notes: [PreviewVisualNote(laneID: "11", startBeat: 4, endBeat: 4)],
                barBeats: [],
                endBeat: 8
            ))
            view.setTiming(timing, fromBeat: 0)
            let cap = IndependentStack.capDest(channel: 11, scratchRaw: 0)
            let bomb = IndependentStack.bombDest(channel: 11, scratchRaw: 0)
            guard let overlap = cap.intersection(bomb)?.clipped(to: 331, height: 256) else {
                fail("white key cap does not overlap the 96 bomb")
            }
            require(overlap.x <= 37 && overlap.maxX >= 50 && overlap.y <= 233 && overlap.maxY >= 250, "audit ROI x37..49 y233..249 is inside the overlap")
            for age in ages {
                view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
                view.setPlayback(beat: 4, elapsedSeconds: 2 + Double(age) / 1000, isPlaying: true)
                let scene = view.currentScene()
                require(scene.hits.contains { $0.laneID == "11" && $0.ageMilliseconds == age && !$0.isLong }, "white key age \(age) ms")
                let image = view.renderMetalReadback()
                requireMetalReadback(image)
                let capVisible = age <= 50
                var layers: [IndependentStack.Layer] = []
                if capVisible {
                    layers.append(IndependentStack.capLayer(channel: 11, scratchRaw: 0, skin1: skin1))
                }
                layers.append(IndependentStack.bombLayer(channel: 11, ageMilliseconds: age, scratchRaw: 0, skin3: skin3))
                var diff = 0
                var sawBombInk = false
                let bombLayer = layers[layers.count - 1]
                let capLayer = capVisible ? layers.first : nil
                for y in overlap.y..<overlap.maxY {
                    for x in overlap.x..<overlap.maxX {
                        guard let background = IndependentStack.rgb(skin0, x, y) else {
                            fail("missing skin_00 \(x),\(y)")
                        }
                        let want = IndependentStack.composite(background: background, layers: layers, x: x, y: y)
                        let got = sampleNative(image, x: x, y: y, in: scene, viewSize: view.bounds.size)
                        if !near(got, want.tuple, tolerance: 0) { diff += 1 }
                        if let bombInk = IndependentStack.sample(bombLayer, x: x, y: y),
                           !IndependentStack.isSkin03Key(bombInk) {
                            let capInk = capLayer.flatMap { IndependentStack.sample($0, x: x, y: y) }
                            let distinctFromCap = capInk.map { IndependentStack.isSkin01Key($0) || $0 != bombInk } ?? true
                            if distinctFromCap {
                                require(near(got, bombInk.tuple, tolerance: 0), "\(factor)× overlap \(x),\(y) at \(age) ms is cap, not bomb")
                                sawBombInk = true
                            }
                        }
                    }
                }
                print("us9-cap-bomb-\(factor)x-\(age)ms-overlap-diff=\(diff)")
                require(diff == 0, "\(factor)× white key overlap at \(age) ms differs by \(diff)")
                require(sawBombInk, "\(factor)× overlap at \(age) ms has no non-key bomb texel different from the cap")
            }
        }

        let over25 = stackedHits(
            title: "US9 2P scratch 25",
            scratchRaw: 0,
            lanes: [
                PreviewVisualLane(id: "25", title: "5", player: 2),
                PreviewVisualLane(id: "26", title: "S", isScratch: true, player: 2)
            ],
            older: "25",
            younger: "26"
        )
        let over25Layers: [IndependentStack.Layer] = [
            IndependentStack.capLayer(channel: 26, scratchRaw: 0, skin1: skin1),
            IndependentStack.bombLayer(channel: 25, ageMilliseconds: 60, scratchRaw: 0, skin3: skin3),
            IndependentStack.bombLayer(channel: 26, ageMilliseconds: 20, scratchRaw: 0, skin3: skin3)
        ]
        let twoDiff = assertBombOverlap(
            image: over25.image,
            scene: over25.scene,
            viewSize: over25.view.bounds.size,
            background: skin0,
            scratchRaw: 0,
            layers: over25Layers,
            earlier: over25Layers[1],
            later: over25Layers[2],
            requireDistinctInk: true,
            label: "2P scratch 26 over 25"
        )
        print("us9-p2-scratch-over-25-diff=\(twoDiff)")

        // 26 帧 0、29 帧 4。唯一两张都非键色且不同的像素在 (319, 195)。
        let over29 = stackedHits(
            title: "US9 2P scratch 29",
            scratchRaw: 0,
            lanes: [
                PreviewVisualLane(id: "29", title: "7", player: 2),
                PreviewVisualLane(id: "26", title: "S", isScratch: true, player: 2)
            ],
            older: "29",
            younger: "26",
            olderAgeMilliseconds: 80,
            youngerAgeMilliseconds: 0
        )
        let over29Layers: [IndependentStack.Layer] = [
            IndependentStack.capLayer(channel: 26, scratchRaw: 0, skin1: skin1),
            IndependentStack.bombLayer(channel: 29, ageMilliseconds: 80, scratchRaw: 0, skin3: skin3),
            IndependentStack.bombLayer(channel: 26, ageMilliseconds: 0, scratchRaw: 0, skin3: skin3)
        ]
        let twoScratchOver29 = assertBombOverlap(
            image: over29.image,
            scene: over29.scene,
            viewSize: over29.view.bounds.size,
            background: skin0,
            scratchRaw: 0,
            layers: over29Layers,
            earlier: over29Layers[1],
            later: over29Layers[2],
            requireDistinctInk: true,
            label: "2P scratch 26 over 29"
        )
        let pixel319 = sampleNative(over29.image, x: 319, y: 195, in: over29.scene, viewSize: over29.view.bounds.size)
        print("us9-pixel-26-over-29-319-195=\(pixel319.r),\(pixel319.g),\(pixel319.b)")
        require(
            near(pixel319, (15.0 / 255.0, 78.0 / 255.0, 136.0 / 255.0), tolerance: 0),
            "319,195 must be scratch frame 0 (15,78,136), got \(pixel319)"
        )
        print("us9-p2-scratch-over-29-diff=\(twoScratchOver29)")

        // 11/12 dest 差 19 为奇数。12/13 dest 差 16 为偶数，爆炸矩形和 ink 都重叠。
        let adjacent = stackedHits(
            title: "US9 adjacent",
            scratchRaw: 0,
            lanes: [
                PreviewVisualLane(id: "12", title: "2"),
                PreviewVisualLane(id: "13", title: "3")
            ],
            older: "12",
            younger: "13"
        )
        let adjLayers: [IndependentStack.Layer] = [
            IndependentStack.capLayer(channel: 13, scratchRaw: 0, skin1: skin1),
            IndependentStack.bombLayer(channel: 12, ageMilliseconds: 60, scratchRaw: 0, skin3: skin3),
            IndependentStack.bombLayer(channel: 13, ageMilliseconds: 20, scratchRaw: 0, skin3: skin3)
        ]
        let adjDiff = assertBombOverlap(
            image: adjacent.image,
            scene: adjacent.scene,
            viewSize: adjacent.view.bounds.size,
            background: skin0,
            scratchRaw: 0,
            layers: adjLayers,
            earlier: adjLayers[1],
            later: adjLayers[2],
            requireDistinctInk: true,
            label: "channel 13 over 12"
        )
        print("us9-adjacent-13-over-12-diff=\(adjDiff)")

        // scratchRaw 1 把 16 放到右边。16 帧 1、18 帧 4。唯一竞争像素在 (130, 195)。
        // 内部号 17 晚于 14；BMS 整数 16<18 和年龄序都会把 18 画在上面。
        let integerOrder = stackedHits(
            title: "US9 scratch integer",
            scratchRaw: 1,
            lanes: [
                PreviewVisualLane(id: "16", title: "S", isScratch: true),
                PreviewVisualLane(id: "18", title: "6")
            ],
            older: "18",
            younger: "16",
            olderAgeMilliseconds: 80,
            youngerAgeMilliseconds: 20
        )
        require(integerOrder.scene.scratchRaw == 1, "1P scratch sits on the right")
        let intLayers: [IndependentStack.Layer] = [
            IndependentStack.capLayer(channel: 16, scratchRaw: 1, skin1: skin1),
            IndependentStack.bombLayer(channel: 18, ageMilliseconds: 80, scratchRaw: 1, skin3: skin3),
            IndependentStack.bombLayer(channel: 16, ageMilliseconds: 20, scratchRaw: 1, skin3: skin3)
        ]
        let intDiff = assertBombOverlap(
            image: integerOrder.image,
            scene: integerOrder.scene,
            viewSize: integerOrder.view.bounds.size,
            background: skin0,
            scratchRaw: 1,
            layers: intLayers,
            earlier: intLayers[1],
            later: intLayers[2],
            requireDistinctInk: true,
            label: "scratch 16 over 18"
        )
        let pixel130 = sampleNative(integerOrder.image, x: 130, y: 195, in: integerOrder.scene, viewSize: integerOrder.view.bounds.size)
        print("us9-pixel-16-over-18-130-195=\(pixel130.r),\(pixel130.g),\(pixel130.b)")
        require(
            near(pixel130, (115.0 / 255.0, 116.0 / 255.0, 1.0), tolerance: 0),
            "130,195 must be scratch frame 1 (115,116,255), got \(pixel130)"
        )
        print("us9-scratch-16-over-18-diff=\(intDiff)")
    }

    @MainActor
    private static func stackedHits(
        title: String,
        scratchRaw: Int,
        lanes: [PreviewVisualLane],
        older: String,
        younger: String,
        olderAgeMilliseconds: Int = 60,
        youngerAgeMilliseconds: Int = 20
    ) -> (view: PreviewPlayfieldView, scene: PreviewPlayfieldScene, image: PreviewPlayfieldMetalReadback) {
        let view = makeView(width: 331, height: 256)
        requireMetal(view)
        view.pixelsPerBeat = 96
        view.setUbmAppearance(scratchRaw: scratchRaw, effectsRaw: 7, autoSeparate: true)
        let olderChart = 2.0
        let playChart = olderChart + Double(olderAgeMilliseconds) / 1000
        let youngerChart = playChart - Double(youngerAgeMilliseconds) / 1000
        view.setChart(PreviewChartSnapshot(
            title: title,
            lanes: lanes,
            notes: [
                PreviewVisualNote(laneID: older, startBeat: olderChart * 2, endBeat: olderChart * 2),
                PreviewVisualNote(laneID: younger, startBeat: youngerChart * 2, endBeat: youngerChart * 2)
            ],
            barBeats: [],
            endBeat: 8
        ))
        view.setTiming(PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: []), fromBeat: 0)
        view.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        view.setPlayback(beat: playChart * 2, elapsedSeconds: playChart, isPlaying: true)
        let scene = view.currentScene()
        require(
            scene.hits.contains { $0.laneID == older && $0.ageMilliseconds == olderAgeMilliseconds },
            "\(older) is \(olderAgeMilliseconds) ms so age-sort would paint it last"
        )
        require(
            scene.hits.contains { $0.laneID == younger && $0.ageMilliseconds == youngerAgeMilliseconds },
            "\(younger) is \(youngerAgeMilliseconds) ms"
        )
        let image = view.renderMetalReadback()
        requireMetalReadback(image)
        return (view, scene, image)
    }

    @MainActor
    private static func assertBombOverlap(
        image: PreviewPlayfieldMetalReadback,
        scene: PreviewPlayfieldScene,
        viewSize: CGSize,
        background: PngTopLeft,
        scratchRaw: Int,
        layers: [IndependentStack.Layer],
        earlier: IndependentStack.Layer,
        later: IndependentStack.Layer,
        requireDistinctInk: Bool,
        label: String
    ) -> Int {
        guard let overlap = earlier.dest.intersection(later.dest)?.clipped(to: 331, height: 256) else {
            fail("\(label) bombs do not overlap")
        }
        require(overlap.contains(130, 195) || overlap.contains(319, 195) || overlap.y <= 195,
                "\(label) overlap must include y195 when the competing texel is there")
        var diff = 0
        var sawDistinct = false
        for y in overlap.y..<overlap.maxY {
            for x in overlap.x..<overlap.maxX {
                guard let laterInk = IndependentStack.sample(later, x: x, y: y),
                      let earlierInk = IndependentStack.sample(earlier, x: x, y: y),
                      !IndependentStack.isSkin03Key(laterInk),
                      !IndependentStack.isSkin03Key(earlierInk),
                      laterInk != earlierInk else { continue }
                let got = sampleNative(image, x: x, y: y, in: scene, viewSize: viewSize)
                if !near(got, laterInk.tuple, tolerance: 0) { diff += 1 }
                require(near(got, laterInk.tuple, tolerance: 0), "\(label) overlap \(x),\(y) is not the later bomb \(laterInk.tuple), got \(got)")
                sawDistinct = true
            }
        }
        _ = (background, scratchRaw, layers, viewSize)
        require(diff == 0, "\(label) distinct-ink differs by \(diff)")
        if requireDistinctInk {
            require(sawDistinct, "\(label) has no overlapping opaque texels that differ")
        }
        return diff
    }

    private static func sampleNative(
        _ image: PreviewPlayfieldMetalReadback,
        x: Int,
        y: Int,
        in scene: PreviewPlayfieldScene,
        viewSize: CGSize
    ) -> (r: Double, g: Double, b: Double, a: Double) {
        let scale = scene.placement.scale > 0 ? scene.placement.scale : 1
        let point = CGPoint(
            x: scene.placement.origin.x + CGFloat(x) * scale + 0.2,
            y: scene.placement.origin.y + CGFloat(y) * scale + 0.2
        )
        return sample(image, point, viewSize: viewSize)
    }

    @MainActor
    private static func judgmentPoint(_ view: PreviewPlayfieldView, lane: String, local: (x: Int, y: Int), side: CGFloat) -> CGPoint {
        let scene = view.currentScene()
        guard let column = scene.lanes.first(where: { $0.id == lane }) else { fail("missing \(lane)") }
        let centerX = column.rect.minX + (column.kind == .scratch ? 16 : 8) * scene.placement.scale
        let left = centerX - side / 2 * scene.placement.scale
        let top = scene.placement.origin.y + 224 * scene.placement.scale - side / 2 * scene.placement.scale
        return CGPoint(x: left + CGFloat(local.x) + 0.2, y: top + CGFloat(local.y) + 0.2)
    }

    private static func firstDigitInk(_ image: PngTopLeft, digit: Int, frame: Int) -> (x: Int, y: Int)? {
        let originX = 9 + digit * 15
        let originY = 1 + frame * 15
        for y in 0..<14 {
            for x in 0..<15 {
                guard let color = image.rgb(originX + x, originY + y) else { continue }
                if isKeyed(color) { continue }
                if color.0 == 0, color.1 == 1, color.2 == 0 { continue }
                return (originX + x, originY + y)
            }
        }
        return nil
    }

    /// 长音持有期间亮条、键帽和 64 像素爆炸留着。尾释放后改 96 像素爆炸，120 ms 结束。短音仍是 50 ms。
    @MainActor
    private static func testLongNoteGlowStaysThroughTheHold() {
        require(PreviewUbmStyle.laneGlowVisible(ageMilliseconds: 50, isLong: false, tailAgeMilliseconds: nil), "short glow lasts 50 ms")
        require(!PreviewUbmStyle.laneGlowVisible(ageMilliseconds: 51, isLong: false, tailAgeMilliseconds: nil), "short glow ends at 51 ms")
        require(!PreviewUbmStyle.laneGlowVisible(ageMilliseconds: 500, isLong: false, tailAgeMilliseconds: nil), "a short note does not stay lit")
        require(PreviewUbmStyle.laneGlowVisible(ageMilliseconds: 500, isLong: true, tailAgeMilliseconds: nil), "a hold stays lit at 500 ms")
        require(PreviewUbmStyle.laneGlowVisible(ageMilliseconds: 40, isLong: true, tailAgeMilliseconds: 0), "a tail inside the head window still uses 50 ms")
        require(!PreviewUbmStyle.laneGlowVisible(ageMilliseconds: 500, isLong: true, tailAgeMilliseconds: 0), "releasing the tail does not keep the glow")
        require(!PreviewUbmStyle.laneGlowVisible(ageMilliseconds: -1, isLong: true, tailAgeMilliseconds: nil), "a future long note is dark")

        guard let skin0 = calibratedPng(named: "skin_00.png"),
              let skin1 = calibratedPng(named: "skin_01.png"),
              let skin3 = calibratedPng(named: "skin_03.png"),
              let beamInk = skin1.rgb(17, 11),
              let capInk = skin1.rgb(75, 149) else {
            fail("missing long-note glow atlases")
        }
        var longLocal: (x: Int, y: Int)?
        for y in 8..<56 {
            for x in 8..<56 {
                let frames = (0..<6).compactMap { skin3.rgb(1 + $0 * 64 + x, 163 + y) }
                guard frames.count == 6, !frames.contains(where: isKeyed) else { continue }
                guard frames[0] != frames[1], frames[1] != frames[2], frames[0] != frames[2], frames[2] != frames[4] else { continue }
                guard let overlapped = skin3.rgb(1 + x + 16, 66 + y + 16), overlapped != frames[0], !isKeyed(overlapped) else { continue }
                longLocal = (x, y)
                break
            }
            if longLocal != nil { break }
        }
        guard let longLocal else { fail("skin_03 long-note row has no distinct hold frames") }
        func longColor(_ frame: Int) -> (Double, Double, Double) {
            guard let color = skin3.rgb(1 + frame * 64 + longLocal.x, 163 + longLocal.y) else {
                fail("missing long bomb frame \(frame)")
            }
            return color
        }

        let timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
        let lanes = [
            PreviewVisualLane(id: "13", title: "3", player: 1),
            PreviewVisualLane(id: "12", title: "2", player: 1),
            PreviewVisualLane(id: "23", title: "3", player: 2)
        ]
        let view = makeView(width: 331, height: 256)
        requireMetal(view)
        let atlasLoads = view.atlasLoadCount
        view.pixelsPerBeat = 24
        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 7, autoSeparate: true)
        view.setChart(PreviewChartSnapshot(
            title: "LN glow",
            lanes: lanes,
            notes: [
                PreviewVisualNote(laneID: "13", startBeat: 0, endBeat: 4),
                PreviewVisualNote(laneID: "23", startBeat: 0, endBeat: 4),
                PreviewVisualNote(laneID: "12", startBeat: 0, endBeat: 0)
            ],
            barBeats: [],
            endBeat: 8
        ))
        view.setTiming(timing, fromBeat: 0)
        require(abs(view.currentScene().placement.scale - 1) < 0.001, "the glow oracle is at native scale")

        func play(_ elapsed: Double, playing: Bool = true) {
            view.setPlayback(beat: elapsed * 2, elapsedSeconds: elapsed, isPlaying: playing)
        }
        func hit(_ lane: String) -> PreviewPlayfieldHit {
            guard let found = view.currentScene().hits.first(where: { $0.laneID == lane }) else {
                fail("missing hit \(lane)")
            }
            return found
        }
        func column(_ lane: String) -> PreviewPlayfieldLaneFrame {
            guard let found = view.currentScene().lanes.first(where: { $0.id == lane }) else {
                fail("missing lane \(lane)")
            }
            return found
        }
        let p1Column = column("13")
        let p2Column = column("23")
        let shortColumn = column("12")
        let p1Beam = CGPoint(x: p1Column.rect.minX + 0.2, y: 10.2)
        let p2Beam = CGPoint(x: p2Column.rect.minX + 0.2, y: 10.2)
        let shortBeam = CGPoint(x: shortColumn.rect.minX + 0.2, y: 10.2)
        guard let p1Back = skin0.rgb(Int(p1Beam.x), 10),
              let p2Back = skin0.rgb(Int(p2Beam.x), 10),
              let shortBack = skin0.rgb(Int(shortBeam.x), 10),
              p1Back != beamInk, shortBack != beamInk else {
            fail("beam sample sits on ink-colored background")
        }
        let centerX = p1Column.rect.minX + 8
        var judgeLocal: (x: Int, y: Int)?
        let judgeLeft = centerX - 48
        for y in 24..<56 {
            for x in 36..<80 {
                guard let first = skin3.rgb(1 + x, 66 + y), let later = skin3.rgb(1 + 5 * 96 + x, 66 + y) else { continue }
                if first == later || isKeyed(first) || isKeyed(later) { continue }
                let sx = Int(judgeLeft) + x
                let sy = 176 + y
                guard (0..<331).contains(sx), (0..<256).contains(sy) else { continue }
                guard let back = skin0.rgb(sx, sy), back != first else { continue }
                judgeLocal = (x, y)
                break
            }
            if judgeLocal != nil { break }
        }
        guard let judgeLocal else { fail("skin_03 middle row has no on-screen tail texel") }
        func judgeColor(_ frame: Int) -> (Double, Double, Double) {
            guard let color = skin3.rgb(1 + frame * 96 + judgeLocal.x, 66 + judgeLocal.y) else {
                fail("missing tail bomb frame \(frame)")
            }
            return color
        }
        func shot() -> PreviewPlayfieldMetalReadback {
            let image = view.renderMetalReadback()
            requireMetalReadback(image)
            return image
        }
        let longPoint = bombPoint(in: view, lane: "13", local: longLocal)
        let tailPoint = judgmentPoint(view, lane: "13", local: judgeLocal, side: 96)
        let capOffset = PreviewUbmStyle.keyCapXOffset(channel: p1Column.channel, scratchRaw: 0)
        let capPoint = CGPoint(
            x: p1Column.rect.minX + capOffset + 6.2,
            y: PreviewUbmStyle.keyCapNativeY(kind: p1Column.kind) + 10.2
        )

        play(0)
        let atHead = shot()
        require(hit("13").isLong && hit("13").tailAgeMilliseconds == nil && hit("13").ageMilliseconds == 0, "both players start the hold at age 0")
        require(hit("23").ageMilliseconds == 0 && hit("23").tailAgeMilliseconds == nil, "2P hold starts with 1P")
        require(near(sample(atHead, p1Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "1P beam is on at the head")
        require(near(sample(atHead, p2Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "2P beam is on at the head")
        require(near(sample(atHead, longPoint, viewSize: view.bounds.size), longColor(0), tolerance: 0), "hold bomb frame 0 is the 64 px row")

        play(0.05)
        let atFifty = shot()
        require(hit("13").ageMilliseconds == 50 && hit("13").tailAgeMilliseconds == nil, "head +50 ms is still the hold")
        require(near(sample(atFifty, p1Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "1P beam is on at head +50 ms")
        require(near(sample(atFifty, p2Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "2P beam is on at head +50 ms")
        require(near(sample(atFifty, longPoint, viewSize: view.bounds.size), longColor(2), tolerance: 0), "hold bomb frame 2 at 50 ms")

        play(0.5)
        let atHold = shot()
        require(hit("13").ageMilliseconds == 500 && hit("13").tailAgeMilliseconds == nil, "head +500 ms has not reached the tail")
        require(hit("23").ageMilliseconds == 500 && hit("23").tailAgeMilliseconds == nil, "2P is on the same hold clock")
        require(hit("12").ageMilliseconds == 500 && !hit("12").isLong, "the short note is still only a judgment")
        require(near(sample(atHold, p1Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "1P beam stays on at head +500 ms")
        require(near(sample(atHold, p2Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "2P beam stays on at head +500 ms")
        require(near(sample(atHold, shortBeam, viewSize: view.bounds.size), shortBack, tolerance: 0), "the short beam is off at 500 ms")
        require(near(sample(atHold, longPoint, viewSize: view.bounds.size), longColor(1), tolerance: 0), "hold bomb frame follows the 500 ms head age")
        require(!near(sample(atHold, longPoint, viewSize: view.bounds.size), longColor(0), tolerance: 0), "500 ms is not stuck on frame 0")
        require(!near(sample(atHold, tailPoint, viewSize: view.bounds.size), judgeColor(0), tolerance: 0), "the 96 px bomb stays off during the hold")
        play(0.5, playing: false)
        let paused = shot()
        require(hit("13").ageMilliseconds == 500 && hit("13").tailAgeMilliseconds == nil, "pause keeps the hold age")
        require(near(sample(paused, p1Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "pause keeps the beam")
        require(near(sample(paused, longPoint, viewSize: view.bounds.size), longColor(1), tolerance: 0), "pause keeps the bomb frame")
        play(0.52)
        require(hit("13").ageMilliseconds == 520, "resume ages the wall")
        require(near(sample(shot(), longPoint, viewSize: view.bounds.size), longColor(2), tolerance: 0), "the bomb frame advances after resume")

        play(0.5)
        view.setPlayerSide(.twoPlayer)
        let onlyTwo = shot()
        require(view.currentScene().hits.allSatisfy { $0.player == 2 }, "the 2P side does not keep 1P hits")
        require(near(sample(onlyTwo, p1Beam, viewSize: view.bounds.size), p1Back, tolerance: 0), "hiding 1P turns that beam off")
        require(near(sample(onlyTwo, p2Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "2P beam stays while 1P is hidden")
        view.setPlayerSide(.both)
        require(hit("13").ageMilliseconds == 500, "showing 1P again keeps the original birth")

        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 0, autoSeparate: true)
        let effectsOff = shot()
        require(near(sample(effectsOff, p1Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "effects 0 still draws the lane beam")
        require(!near(sample(effectsOff, capPoint, viewSize: view.bounds.size), capInk, tolerance: 0), "effects 0 hides the key cap")
        require(!near(sample(effectsOff, longPoint, viewSize: view.bounds.size), longColor(1), tolerance: 0), "effects 0 hides the bomb")
        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 4, autoSeparate: true)
        let capsOnly = shot()
        require(near(sample(capsOnly, capPoint, viewSize: view.bounds.size), capInk, tolerance: 0), "effects 4 keeps the key cap through the hold")
        require(!near(sample(capsOnly, longPoint, viewSize: view.bounds.size), longColor(1), tolerance: 0), "effects 4 hides the bomb")
        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 2, autoSeparate: true)
        let bombsOnly = shot()
        require(near(sample(bombsOnly, longPoint, viewSize: view.bounds.size), longColor(1), tolerance: 0), "effects 2 keeps the hold bomb")
        require(!near(sample(bombsOnly, capPoint, viewSize: view.bounds.size), capInk, tolerance: 0), "effects 2 hides the key cap")
        view.setUbmAppearance(scratchRaw: 0, effectsRaw: 7, autoSeparate: true)

        play(1.99)
        require(hit("13").tailAgeMilliseconds == nil && hit("13").ageMilliseconds == 1990, "chart 1.99 is still before the tail")
        require(near(sample(shot(), p1Beam, viewSize: view.bounds.size), beamInk, tolerance: 0), "the beam is on just before the tail")
        play(2)
        let atTail = shot()
        require(hit("13").tailAgeMilliseconds == 0 && hit("13").ageMilliseconds == 2000, "the tail starts at chart 2")
        require(near(sample(atTail, p1Beam, viewSize: view.bounds.size), p1Back, tolerance: 0), "the beam ends when the tail starts")
        require(near(sample(atTail, p2Beam, viewSize: view.bounds.size), p2Back, tolerance: 0), "2P beam ends on its own tail")
        require(near(sample(atTail, tailPoint, viewSize: view.bounds.size), judgeColor(0), tolerance: 0), "the tail uses the 96 px row")
        guard let releasedOverlap = skin3.rgb(1 + longLocal.x + 16, 66 + longLocal.y + 16) else {
            fail("missing the tail overlap texel")
        }
        require(near(sample(atTail, longPoint, viewSize: view.bounds.size), releasedOverlap, tolerance: 0), "the old 64 px point shows the 96 px frame")
        play(2.1)
        let tailLate = shot()
        require(hit("13").tailAgeMilliseconds == 100, "tail +100 ms")
        require(near(sample(tailLate, p1Beam, viewSize: view.bounds.size), p1Back, tolerance: 0), "the beam stays off during the tail bomb")
        require(near(sample(tailLate, tailPoint, viewSize: view.bounds.size), judgeColor(5), tolerance: 0), "tail bomb frame 5 at 100 ms")
        play(2.12)
        require(view.currentScene().hits.contains { $0.laneID == "13" } == false, "the tail bomb ends at 120 ms")
        require(!near(sample(shot(), tailPoint, viewSize: view.bounds.size), judgeColor(0), tolerance: 0), "the tail pixel is gone at 120 ms")
        require(view.atlasLoadCount == atlasLoads, "playfield frames reloaded the atlas, \(view.atlasLoadCount) loads")

        let brief = makeView(width: 331, height: 256)
        requireMetal(brief)
        brief.pixelsPerBeat = 24
        brief.setChart(PreviewChartSnapshot(
            title: "Brief LN",
            lanes: [PreviewVisualLane(id: "13", title: "3")],
            notes: [PreviewVisualNote(laneID: "13", startBeat: 4, endBeat: 4.08)],
            barBeats: [],
            endBeat: 8
        ))
        brief.setTiming(timing, fromBeat: 0)
        brief.setPlayback(beat: 0, elapsedSeconds: 0, isPlaying: true)
        brief.setPlayback(beat: 4, elapsedSeconds: 2, isPlaying: true)
        require(brief.currentScene().hits.first?.tailAgeMilliseconds == nil, "40 ms hold has not reached the tail")
        brief.setPlayback(beat: 4.08, elapsedSeconds: 2.04, isPlaying: true)
        let briefColumn = brief.currentScene().lanes[0]
        let briefBeam = CGPoint(x: briefColumn.rect.minX + 0.2, y: 10.2)
        let briefTail = judgmentPoint(brief, lane: "13", local: judgeLocal, side: 96)
        let opened = brief.renderMetalReadback()
        requireMetalReadback(opened)
        require(brief.currentScene().hits.first?.tailAgeMilliseconds == 0, "the 40 ms note releases at 2.04 s")
        require(brief.currentScene().hits.first?.ageMilliseconds == 40, "head age is 40 ms at release")
        require(near(sample(opened, briefBeam, viewSize: brief.bounds.size), beamInk, tolerance: 0), "glow remains while the head window is open")
        require(near(sample(opened, briefTail, viewSize: brief.bounds.size), judgeColor(0), tolerance: 0), "release draws the 96 px bomb immediately")
        brief.setPlayback(beat: 4.102, elapsedSeconds: 2.051, isPlaying: true)
        let briefOff = brief.renderMetalReadback()
        requireMetalReadback(briefOff)
        require(brief.currentScene().hits.first?.ageMilliseconds == 51, "head age is 51 ms")
        require(brief.currentScene().hits.first?.tailAgeMilliseconds == 11, "tail age is 11 ms")
        require(near(sample(briefOff, briefBeam, viewSize: brief.bounds.size), p1Back, tolerance: 0), "glow ends at 51 ms while the tail bomb continues")
        require(near(sample(briefOff, briefTail, viewSize: brief.bounds.size), judgeColor(0), tolerance: 0), "the tail bomb is still frame 0 at 11 ms")
        brief.setPlayback(beat: 4.32, elapsedSeconds: 2.16, isPlaying: true)
        require(brief.currentScene().hits.isEmpty, "the short hold's tail bomb ends at 120 ms")

        let jumped = makeView(width: 331, height: 256)
        requireMetal(jumped)
        jumped.pixelsPerBeat = 24
        jumped.setChart(PreviewChartSnapshot(
            title: "Seek LN",
            lanes: [PreviewVisualLane(id: "13", title: "3")],
            notes: [PreviewVisualNote(laneID: "13", startBeat: 4, endBeat: 8)],
            barBeats: [],
            endBeat: 12
        ))
        jumped.setTiming(timing, fromBeat: 0)
        jumped.setPlayback(beat: 6, elapsedSeconds: 3, isPlaying: true)
        let jumpedHit = jumped.currentScene().hits.first
        require(jumpedHit?.isLong == true && jumpedHit?.tailAgeMilliseconds == nil && jumpedHit?.ageMilliseconds == 1000, "seeking into the hold ages from the head")
        let jumpedImage = jumped.renderMetalReadback()
        requireMetalReadback(jumpedImage)
        let jumpedBeam = CGPoint(x: jumped.currentScene().lanes[0].rect.minX + 0.2, y: 10.2)
        let jumpedBomb = bombPoint(in: jumped, lane: "13", local: longLocal)
        require(near(sample(jumpedImage, jumpedBeam, viewSize: jumped.bounds.size), beamInk, tolerance: 0), "seeking into the hold lights the beam")
        require(near(sample(jumpedImage, jumpedBomb, viewSize: jumped.bounds.size), longColor(2), tolerance: 0), "seeking into the hold uses the 1000 ms bomb frame")
        jumped.setPlayback(beat: 6, elapsedSeconds: 3, isPlaying: false)
        let jumpedPause = jumped.renderMetalReadback()
        requireMetalReadback(jumpedPause)
        require(near(sample(jumpedPause, jumpedBomb, viewSize: jumped.bounds.size), longColor(2), tolerance: 0), "a paused seek keeps the bomb frame")
        jumped.setChart(PreviewChartSnapshot(
            title: "Next",
            lanes: [PreviewVisualLane(id: "13", title: "3")],
            notes: [PreviewVisualNote(laneID: "13", startBeat: 8, endBeat: 8)],
            barBeats: [],
            endBeat: 12
        ))
        jumped.setTiming(timing, fromBeat: 0)
        let clearedChart = jumped.renderMetalReadback()
        requireMetalReadback(clearedChart)
        require(jumped.currentScene().hits.isEmpty, "a new chart drops the previous hold")
        require(near(sample(clearedChart, jumpedBeam, viewSize: jumped.bounds.size), p1Back, tolerance: 0), "the previous beam does not remain on the new chart")
        jumped.setPlayback(beat: 6, elapsedSeconds: 3, isPlaying: true)
        require(jumped.currentScene().hits.isEmpty, "the new note has not arrived, so the old hold stays gone")

        let backward = makeView(width: 331, height: 256)
        requireMetal(backward)
        backward.pixelsPerBeat = 24
        backward.setChart(PreviewChartSnapshot(
            title: "Back",
            lanes: [PreviewVisualLane(id: "13", title: "3")],
            notes: [PreviewVisualNote(laneID: "13", startBeat: 4, endBeat: 8)],
            barBeats: [],
            endBeat: 12
        ))
        backward.setTiming(timing, fromBeat: 0)
        backward.setPlayback(beat: 6, elapsedSeconds: 3, isPlaying: true)
        backward.setPlayback(beat: 2, elapsedSeconds: 1, isPlaying: true)
        require(backward.currentScene().hits.isEmpty, "seeking before the hold clears it")
        let backwardImage = backward.renderMetalReadback()
        requireMetalReadback(backwardImage)
        require(near(sample(backwardImage, jumpedBeam, viewSize: backward.bounds.size), p1Back, tolerance: 0), "the cleared hold does not leave a beam")

        let rateChart = PreviewChartSnapshot(
            title: "Rate",
            lanes: [
                PreviewVisualLane(id: "13", title: "3"),
                PreviewVisualLane(id: "12", title: "2")
            ],
            notes: [
                PreviewVisualNote(laneID: "13", startBeat: 0, endBeat: 8),
                PreviewVisualNote(laneID: "12", startBeat: 0, endBeat: 0)
            ],
            barBeats: [],
            endBeat: 12
        )
        let rate = makeView(width: 331, height: 256)
        requireMetal(rate)
        rate.pixelsPerBeat = 24
        rate.setChart(rateChart)
        rate.setTiming(timing, fromBeat: 0)
        rate.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        rate.setPlayback(beat: 4, chartElapsedSeconds: 2, effectElapsedSeconds: 1, isPlaying: true)
        require(rate.currentScene().hits.first { $0.laneID == "13" }?.ageMilliseconds == 1000, "2× wall age is 1000 ms")
        require(rate.currentScene().hits.first { $0.laneID == "13" }?.tailAgeMilliseconds == nil, "2× is still inside the hold")
        let fast = rate.renderMetalReadback()
        requireMetalReadback(fast)
        let rateBeam = CGPoint(x: rate.currentScene().lanes[0].rect.minX + 0.2, y: 10.2)
        let rateBomb = bombPoint(in: rate, lane: "13", local: longLocal)
        require(near(sample(fast, rateBeam, viewSize: rate.bounds.size), beamInk, tolerance: 0), "2× beam stays on at wall 1000 ms")
        require(near(sample(fast, rateBomb, viewSize: rate.bounds.size), longColor(2), tolerance: 0), "2× bomb frame follows the wall, not the 2 s chart")
        let slow = makeView(width: 331, height: 256)
        requireMetal(slow)
        slow.pixelsPerBeat = 24
        slow.setChart(rateChart)
        slow.setTiming(timing, fromBeat: 0)
        slow.setPlayback(beat: 0, chartElapsedSeconds: 0, effectElapsedSeconds: 0, isPlaying: true)
        slow.setPlayback(beat: 1, chartElapsedSeconds: 0.5, effectElapsedSeconds: 1, isPlaying: true)
        require(slow.currentScene().hits.first { $0.laneID == "13" }?.ageMilliseconds == 1000, "0.5× wall age is 1000 ms")
        require(slow.currentScene().hits.first { $0.laneID == "12" }?.ageMilliseconds == 1000, "0.5× short age follows the wall")
        let slowImage = slow.renderMetalReadback()
        requireMetalReadback(slowImage)
        guard let slowShort = slow.currentScene().lanes.first(where: { $0.id == "12" }),
              let slowShortBack = skin0.rgb(Int(slowShort.rect.minX), 10) else {
            fail("missing the 0.5× short column")
        }
        require(near(sample(slowImage, rateBeam, viewSize: slow.bounds.size), beamInk, tolerance: 0), "0.5× held beam is on")
        require(near(sample(slowImage, rateBomb, viewSize: slow.bounds.size), longColor(2), tolerance: 0), "0.5× bomb frame is the wall age")
        require(
            near(sample(slowImage, CGPoint(x: slowShort.rect.minX + 0.2, y: 10.2), viewSize: slow.bounds.size), slowShortBack, tolerance: 0),
            "0.5× short beam is off at wall 1000 ms"
        )
    }

    @MainActor
    private static func clockHost() -> PreviewPlayfieldView {
        let view = makeView(width: 331, height: 256)
        requireMetal(view)
        view.pixelsPerBeat = 96
        view.setChart(PreviewChartSnapshot(
            title: "Dual",
            lanes: [
                PreviewVisualLane(id: "s", title: "S", isScratch: true),
                PreviewVisualLane(id: "k", title: "1")
            ],
            notes: [
                PreviewVisualNote(laneID: "s", startBeat: 2, endBeat: 6),
                PreviewVisualNote(laneID: "k", startBeat: 2, endBeat: 2)
            ],
            barBeats: [],
            endBeat: 8
        ))
        return view
    }

    private static func isKeyed(_ color: (Double, Double, Double)) -> Bool {
        let pink = abs(color.0 - 199.0 / 255.0) < 0.01 && abs(color.1 - 80.0 / 255.0) < 0.01 && abs(color.2 - 127.0 / 255.0) < 0.01
        let black = color.0 == 0 && color.1 == 0 && color.2 == 0
        return pink || black
    }

    @MainActor
    private static func bombPoint(in view: PreviewPlayfieldView, lane: String, local: (x: Int, y: Int)) -> CGPoint {
        let scene = view.currentScene()
        guard let column = scene.lanes.first(where: { $0.id == lane }) else { fail("missing bomb lane") }
        let scale = scene.placement.scale
        let centerX = column.rect.minX + (column.kind == .scratch ? 16 : 8) * scale
        let left = centerX - 32 * scale
        let top = scene.placement.origin.y + 224 * scale - 32 * scale
        return CGPoint(x: left + CGFloat(local.x) + 0.2, y: top + CGFloat(local.y) + 0.2)
    }

    private static func sevenKeyChart() -> PreviewChartSnapshot {
        let specs: [(String, String, Bool)] = [
            ("scratch", "SC", true),
            ("k1", "1", false),
            ("k2", "2", false),
            ("k3", "3", false),
            ("k4", "4", false),
            ("k5", "5", false),
            ("k6", "6", false),
            ("k7", "7", false)
        ]
        return PreviewChartSnapshot(
            title: "Falling Keys",
            lanes: specs.map { PreviewVisualLane(id: $0.0, title: $0.1, isScratch: $0.2) },
            notes: [
                PreviewVisualNote(laneID: "scratch", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "k1", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "k2", startBeat: 4, endBeat: 4),
                PreviewVisualNote(laneID: "bgm", startBeat: 4, endBeat: 4)
            ],
            barBeats: [0, 4, 8],
            endBeat: 16
        )
    }

    private static func doublePlayLanes() -> [PreviewVisualLane] {
        var lanes: [PreviewVisualLane] = []
        func appendSide(player: Int, prefix: String) {
            lanes.append(PreviewVisualLane(id: "\(prefix)-sc", title: "SC", isScratch: true, player: player))
            for key in 1...7 {
                lanes.append(PreviewVisualLane(id: "\(prefix)-k\(key)", title: "\(key)", isScratch: false, player: player))
            }
        }
        appendSide(player: 1, prefix: "1p")
        appendSide(player: 2, prefix: "2p")
        return lanes
    }

    @MainActor
    private static func makeView(width: CGFloat, height: CGFloat) -> PreviewPlayfieldView {
        let view = PreviewPlayfieldView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.layoutSubtreeIfNeeded()
        return view
    }

    @MainActor
    private static func requireMetal(_ view: PreviewPlayfieldView) {
        guard view.gpuStatus == .ready else {
            fail("Metal unavailable: \(String(describing: view.gpuStatus))")
        }
    }

    @MainActor
    private static func requireMetalReadback(_ readback: PreviewPlayfieldMetalReadback) {
        require(readback.usedMetal, "offscreen draw did not complete on Metal \(readback.failure ?? "")")
        require(readback.width > 0 && readback.height > 0 && !readback.bgra.isEmpty, "Metal readback returned no pixels")
        require(readback.status == .ready, "a completed readback should stay ready")
    }

    @MainActor
    private static func tryMark(
        _ scene: PreviewPlayfieldScene,
        lane: String,
        part: PreviewPlayfieldNotePart
    ) -> PreviewPlayfieldNoteMark {
        guard let mark = scene.marks.first(where: { $0.laneID == lane && $0.part == part }) else {
            fail("missing \(part) mark on \(lane)")
        }
        return mark
    }

    private static func sample(
        _ readback: PreviewPlayfieldMetalReadback,
        _ point: CGPoint,
        viewSize: CGSize
    ) -> (r: Double, g: Double, b: Double, a: Double) {
        guard viewSize.width > 0, viewSize.height > 0, readback.width > 0, readback.height > 0 else {
            fail("cannot sample an empty readback")
        }
        let x = min(max(Int((point.x / viewSize.width * CGFloat(readback.width)).rounded()), 0), readback.width - 1)
        let y = min(max(Int((point.y / viewSize.height * CGFloat(readback.height)).rounded()), 0), readback.height - 1)
        guard let pixel = readback.components(x: x, y: y) else {
            fail("missing pixel at \(x),\(y)")
        }
        return pixel
    }

    private static func matches(
        _ pixel: (r: Double, g: Double, b: Double, a: Double),
        _ color: NSColor,
        tolerance: Double = 0.02
    ) -> Bool {
        guard let want = color.usingColorSpace(.sRGB) else { return false }
        return abs(pixel.r - want.redComponent) <= tolerance
            && abs(pixel.g - want.greenComponent) <= tolerance
            && abs(pixel.b - want.blueComponent) <= tolerance
    }

    private static func countPixels(
        _ readback: PreviewPlayfieldMetalReadback,
        matching color: NSColor,
        tolerance: Double = 0.02
    ) -> Int {
        var count = 0
        guard readback.width > 0, readback.height > 0 else { return 0 }
        for y in 0..<readback.height {
            for x in 0..<readback.width {
                guard let pixel = readback.components(x: x, y: y) else { continue }
                if matches(pixel, color, tolerance: tolerance) {
                    count += 1
                }
            }
        }
        return count
    }

    private static func judgmentRowIsBright(
        _ readback: PreviewPlayfieldMetalReadback,
        viewY: CGFloat,
        viewX: CGFloat,
        viewSize: CGSize
    ) -> Bool {
        guard viewSize.width > 0, viewSize.height > 0 else { return false }
        let x = min(max(Int((viewX / viewSize.width * CGFloat(readback.width)).rounded()), 0), max(readback.width - 1, 0))
        let center = Int((viewY / viewSize.height * CGFloat(readback.height)).rounded())
        for y in (center - 3)...(center + 3) {
            guard let color = readback.components(x: x, y: y) else { continue }
            if color.r > 0.93, color.g > 0.93, color.b > 0.93 {
                return true
            }
        }
        return false
    }

    private static func writePNG(_ readback: PreviewPlayfieldMetalReadback, name: String) {
        guard readback.usedMetal, readback.width > 0, readback.height > 0 else {
            fail("could not encode \(name)")
        }
        let data = readback.bgra as CFData
        guard let provider = CGDataProvider(data: data) else {
            fail("could not wrap \(name)")
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let image = CGImage(
            width: readback.width,
            height: readback.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: readback.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            fail("could not build \(name)")
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("out/validation/ubmplay-parity-20261020", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                fail("could not open \(name)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                fail("could not write \(name)")
            }
        } catch {
            fail("could not write \(name): \(error)")
        }
    }

    private static func guideRows(in scene: PreviewPlayfieldScene, height: Int) -> Set<Int> {
        let scale = scene.placement.scale > 0 ? scene.placement.scale : 1
        var rows = Set<Int>()
        for y in scene.beatLineYs + scene.measureLineYs {
            let top = Int((y / scale).rounded(.down))
            let band = max(Int(scale.rounded(.up)), 1)
            for row in (top - 1)..<(top + band + 1) where row >= 0 && row < height && row < Int(PreviewUbmStyle.judgmentTop) {
                rows.insert(row)
            }
        }
        return rows
    }

    private struct PngTopLeft {
        var width: Int
        var height: Int
        var rgba: [UInt8]

        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double)? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let offset = (y * width + x) * 4
            guard offset + 2 < rgba.count else { return nil }
            return (Double(rgba[offset]) / 255, Double(rgba[offset + 1]) / 255, Double(rgba[offset + 2]) / 255)
        }
    }

    @MainActor private static var pngReverseRows = false
    @MainActor private static var pngCalibrated = false
    @MainActor private static var pngCache: [String: PngTopLeft] = [:]

    @MainActor
    private static func calibratedPng(named name: String) -> PngTopLeft? {
        if let cached = pngCache[name] { return cached }
        guard let directory = PreviewUbmStyle.skinDirectory() else { return nil }
        if !pngCalibrated {
            guard let probe = rasterize(directory.appendingPathComponent("skin_00.png"), reverseRows: false) else { return nil }
            let upright = exactRGB(probe, 0, 0, 156, 158, 156) && exactRGB(probe, 40, 219, 0, 255, 0)
            pngReverseRows = !upright
            pngCalibrated = true
        }
        guard let image = rasterize(directory.appendingPathComponent(name), reverseRows: pngReverseRows) else { return nil }
        pngCache[name] = image
        return image
    }

    private static func exactRGB(_ image: PngTopLeft, _ x: Int, _ y: Int, _ r: Int, _ g: Int, _ b: Int) -> Bool {
        guard let pixel = image.rgb(x, y) else { return false }
        return pixel.0 == Double(r) / 255 && pixel.1 == Double(g) / 255 && pixel.2 == Double(b) / 255
    }

    private static func rasterize(_ url: URL, reverseRows: Bool) -> PngTopLeft? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return rasterize(image, reverseRows: reverseRows)
    }

    private static func rasterize(_ image: CGImage, reverseRows: Bool) -> PngTopLeft? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        if reverseRows {
            let rowBytes = width * 4
            var flipped = [UInt8](repeating: 0, count: rgba.count)
            for y in 0..<height {
                let source = (height - 1 - y) * rowBytes
                let destination = y * rowBytes
                flipped.replaceSubrange(destination..<(destination + rowBytes), with: rgba[source..<(source + rowBytes)])
            }
            rgba = flipped
        }
        return PngTopLeft(width: width, height: height, rgba: rgba)
    }

    @MainActor
    private static func textPixel(_ image: CGImage?, x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let image, let raster = rasterize(image, reverseRows: pngReverseRows), let pixel = raster.rgb(x, y) else {
            fail("missing text pixel \(x),\(y)")
        }
        return (pixel.0, pixel.1, pixel.2, 1)
    }

    private static func printPngHashes(in directory: URL) {
        for name in ["skin_00.png", "skin_01.png", "skin_02.png", "skin_03.png", "font.png"] {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                print("sha256 \(name) missing")
                continue
            }
            let digest = SHA256.hash(data: data)
            print("sha256 \(name) \(digest.map { String(format: "%02x", $0) }.joined())")
        }
    }

    @MainActor
    private static func skinPixel(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        guard let image = calibratedPng(named: "skin_00.png"), let pixel = image.rgb(x, y) else {
            fail("missing skin_00 pixel \(x),\(y)")
        }
        return pixel
    }

    private static func near(
        _ pixel: (r: Double, g: Double, b: Double, a: Double),
        _ rgb: (Double, Double, Double),
        tolerance: Double = 2.0 / 255.0
    ) -> Bool {
        abs(pixel.r - rgb.0) <= tolerance && abs(pixel.g - rgb.1) <= tolerance && abs(pixel.b - rgb.2) <= tolerance
    }

    private static func uniformBlock(
        _ readback: PreviewPlayfieldMetalReadback,
        x: Int,
        y: Int,
        rgb: (Double, Double, Double)
    ) -> Bool {
        for dy in 0...1 {
            for dx in 0...1 {
                guard let pixel = readback.components(x: x + dx, y: y + dy), near(pixel, rgb, tolerance: 0) else {
                    return false
                }
            }
        }
        return true
    }

    private static func countPixelsNear(
        _ readback: PreviewPlayfieldMetalReadback,
        x viewX: CGFloat,
        rgb: (Double, Double, Double),
        viewSize: CGSize,
        tolerance: Double = 0.02
    ) -> Int {
        guard viewSize.width > 0, readback.width > 0 else { return 0 }
        let x = min(max(Int((viewX / viewSize.width * CGFloat(readback.width)).rounded()), 0), readback.width - 1)
        var count = 0
        for y in 0..<readback.height {
            guard let pixel = readback.components(x: x, y: y) else { continue }
            if near(pixel, rgb, tolerance: tolerance) {
                count += 1
            }
        }
        return count
    }

    private static func inkCount(_ image: CGImage?) -> Int {
        guard let image, image.width > 0, image.height > 0 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drew else { return 0 }
        var ink = 0
        var index = 0
        while index + 3 < pixels.count {
            if pixels[index] > 16 || pixels[index + 1] > 16 || pixels[index + 2] > 16 {
                ink += 1
            }
            index += 4
        }
        return ink
    }

    private static func writeCGImage(_ image: CGImage, name: String) {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("out/validation/ubmplay-parity-20261020", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                fail("could not open \(name)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                fail("could not write \(name)")
            }
        } catch {
            fail("could not write \(name): \(error)")
        }
    }

    private static func writeCanvas(playfield: PreviewPlayfieldMetalReadback, name: String) {
        require(playfield.width == 331 && playfield.height == 256, "canvas composite expects a 331×256 playfield")
        let width = 587
        let height = 256
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<331 {
                guard let pixel = playfield.components(x: x, y: y) else { continue }
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(min(max(pixel.b * 255, 0), 255).rounded())
                bytes[offset + 1] = UInt8(min(max(pixel.g * 255, 0), 255).rounded())
                bytes[offset + 2] = UInt8(min(max(pixel.r * 255, 0), 255).rounded())
                bytes[offset + 3] = 255
            }
            for x in 331..<width {
                let offset = (y * width + x) * 4
                bytes[offset + 3] = 255
            }
        }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress,
                  let provider = CGDataProvider(data: Data(bytes: base, count: bytes.count) as CFData) else {
                fail("could not wrap \(name)")
            }
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            )
            guard let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) else {
                fail("could not build \(name)")
            }
            writeCGImage(image, name: name)
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("PreviewPlayfieldTests failed: \(message)\n", stderr)
        exit(1)
    }
}
