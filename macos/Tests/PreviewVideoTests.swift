import AppKit
import CoreGraphics
import Foundation
import ImageIO

@main
struct PreviewVideoTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        do {
            try testPunchTurnsBlackTransparent()
            try testProbeFilesAreASF()
            try testWMV2PixelsSeekPauseRateEOFHoldCancelAndMemory()
            try testWMV1Frame()
            try testParentWMVFixtures()
            try testNonZeroStartTime()
            try testLinkedDecodersAndDecoderLifetime()
            try testViewClockLayersCropBlackKeyAndChartChange()
            try testContinuousForwardAtSixtyHertz()
            try testWorkerFaultStaysReadableUntilClose()
            try testInflightFullRetriesWithoutExtraThreads()
        } catch {
            fail("\(error)")
        }
        print("PreviewVideoTests passed")
    }

    @MainActor
    private static func testPunchTurnsBlackTransparent() throws {
        var bytes: [UInt8] = [0, 0, 0, 255, 0, 0, 254, 255]
        PreviewVideoPunch.apply(&bytes, threshold: 0)
        require(bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0, "threshold 0 clears exact black")
        require(bytes[4] == 0 && bytes[5] == 0 && bytes[6] == 254 && bytes[7] == 255, "threshold 0 keeps red")
        PreviewVideoPunch.apply(&bytes, threshold: 255)
        require(bytes[7] == 0, "threshold 255 clears the remaining pixel")
    }

    @MainActor
    private static func testProbeFilesAreASF() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let color = try encodeColor(root.appendingPathComponent("color.wmv"), secondsEach: 2, size: "80x60")
        let wmv1 = try encodeSolid(root.appendingPathComponent("red1.wmv"), codec: "wmv1", color: "0xFF0000", size: "64x48", seconds: 0.6)
        let probe2 = try ffprobe(color)
        let probe1 = try ffprobe(wmv1)
        require(probe2.contains("codec_name=wmv2"), "ffprobe wmv2 missing: \(probe2)")
        require(probe2.contains("codec_name=wmav2"), "ffprobe wmav2 missing: \(probe2)")
        require(probe2.contains("format_name=asf"), "ffprobe asf missing: \(probe2)")
        require(probe1.contains("codec_name=wmv1"), "ffprobe wmv1 missing: \(probe1)")
        require(probe1.contains("format_name=asf"), "wmv1 container is not asf: \(probe1)")
        require(PreviewVideoClock.usesNativeFile(color), "wmv extension uses the native clock")
        require(!PreviewVideoClock.usesNativeFile(root.appendingPathComponent("clip.m4v")), "m4v stays on AVPlayer")
        require(!PreviewVideoClock.usesNativeFile(root.appendingPathComponent("clip.mp4")), "mp4 stays on AVPlayer")
        let renamed = root.appendingPathComponent("clip.bin")
        try FileManager.default.copyItem(at: color, to: renamed)
        require(PreviewVideoClock.usesNativeFile(renamed), "ASF magic is decoded without a wmv extension")
    }

    @MainActor
    private static func testWMV2PixelsSeekPauseRateEOFHoldCancelAndMemory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let color = try encodeColor(root.appendingPathComponent("color.wmv"), secondsEach: 2, size: "80x60")
        let long = try encodeSolid(
            root.appendingPathComponent("long.wmv"),
            codec: "wmv2",
            color: "0x808080",
            size: "160x120",
            seconds: 8,
            gop: 10
        )
        let clock = PreviewVideoClock()
        clock.open(url: color, generation: 1)
        require(clock.attached, "decoder session opened")
        clock.command(mediaSeconds: 0.25, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { $0.probed && $0.codec == "wmv2" && $0.format.contains("asf") && $0.audioStreams >= 1 }
        let opened = clock.stats
        require(opened.audioDecodedPackets == 0, "audio decoder packets \(opened.audioDecodedPackets)")
        wait(clock, timeout: 4) { imageReady($0, near: 0.25) }
        let early = sample(needImage(clock))
        require(isRed(early), "t=0.25 is not red \(early) pts=\(clock.stats.pts ?? -1)")
        let earlyCopies = clock.stats.copyCount
        require(earlyCopies > 0, "first frame was not copied")
        for _ in 0..<6 { clock.poll(blackKey: false, threshold: 0) }
        require(clock.stats.copyCount == earlyCopies, "unchanged polls copied \(clock.stats.copyCount - earlyCopies) extra frames")
        let seeksAtStart = clock.stats.seekCount
        clock.command(mediaSeconds: 0.45, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 3) { imageReady($0, near: 0.45) }
        require(clock.stats.seekCount == seeksAtStart, "a short forward step seeked \(clock.stats.seekCount - seeksAtStart)")
        require(isRed(sample(needImage(clock))), "t=0.45 left red")
        clock.command(mediaSeconds: 2.45, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { imageReady($0, near: 2.45) }
        require(clock.stats.seekCount == seeksAtStart + 1, "jump to 2.45 seeks once, seeks=\(clock.stats.seekCount)")
        let blue = sample(needImage(clock))
        require(isBlue(blue), "t=2.45 is not blue \(blue) pts=\(clock.stats.pts ?? -1)")
        require(clock.stats.audioDecodedPackets == 0, "audio was decoded")
        require(clock.stats.audioDiscardedPackets > 0, "audio packets were not discarded")
        let heldSerial = clock.stats.frameSerial
        let heldPTS = clock.stats.pts ?? -1
        let heldCopies = clock.stats.copyCount
        clock.command(mediaSeconds: 2.45, rate: 2, playing: false, generation: 1)
        clock.poll(blackKey: false, threshold: 0)
        require(abs(clock.outputRate) < 0.001, "pause rate is \(clock.outputRate)")
        Thread.sleep(forTimeInterval: 0.2)
        for _ in 0..<8 { clock.poll(blackKey: false, threshold: 0) }
        require(clock.stats.frameSerial == heldSerial, "pause published a new frame")
        require(clock.stats.copyCount == heldCopies, "pause ticks copied \(clock.stats.copyCount - heldCopies) frames")
        require(abs((clock.stats.pts ?? -1) - heldPTS) < 0.001, "pause moved pts")
        require(isBlue(sample(needImage(clock))), "pause replaced the blue frame")
        clock.command(mediaSeconds: 2.45, rate: 2, playing: true, generation: 1)
        clock.poll(blackKey: false, threshold: 0)
        require(abs(Double(clock.outputRate) - 2) < 0.01, "resume rate is \(clock.outputRate)")
        let duration = clock.stats.duration
        require(duration > 3.5 && duration < 5, "color clip duration \(duration)")
        let pastEnd = duration + 0.35
        clock.command(mediaSeconds: pastEnd, rate: 2, playing: true, generation: 1)
        wait(clock, timeout: 4) { stats in
            guard stats.valid, let pts = stats.pts else { return false }
            return pts > 3.0
        }
        let tailPTS = clock.stats.pts ?? -1
        require(tailPTS > 3.0 && tailPTS + 0.35 >= duration, "past EOF pts \(tailPTS) duration \(duration)")
        require(isBlue(sample(needImage(clock))), "past EOF \(pastEnd) is not the last blue frame, pts=\(tailPTS)")
        let tailSerial = clock.stats.frameSerial
        let tailCopies = clock.stats.copyCount
        clock.command(mediaSeconds: pastEnd, rate: 1, playing: false, generation: 1)
        Thread.sleep(forTimeInterval: 0.2)
        for _ in 0..<6 { clock.poll(blackKey: false, threshold: 0) }
        require(abs(clock.outputRate) < 0.001, "EOF pause rate \(clock.outputRate)")
        require(clock.stats.frameSerial == tailSerial, "EOF pause published a frame")
        require(clock.stats.copyCount == tailCopies, "EOF pause copied")
        require(abs((clock.stats.pts ?? -1) - tailPTS) < 0.001, "EOF pause moved pts")
        require(isBlue(sample(needImage(clock))), "EOF pause left the last blue frame")
        clock.command(mediaSeconds: 0.25, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { imageReady($0, near: 0.25) }
        require(isRed(sample(needImage(clock))), "seek after EOF did not return to red, pts=\(clock.stats.pts ?? -1)")
        clock.command(mediaSeconds: 2.45, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { imageReady($0, near: 2.45) }
        require(isBlue(sample(needImage(clock))), "play after EOF seek is not blue, pts=\(clock.stats.pts ?? -1)")
        clock.command(mediaSeconds: 2.45, rate: 1, playing: true, generation: 1)
        clock.retire(generation: 2)
        clock.poll(blackKey: false, threshold: 0)
        require(clock.image == nil, "retired generation kept a frame")
        Thread.sleep(forTimeInterval: 0.08)
        clock.poll(blackKey: false, threshold: 0)
        if let image = clock.image {
            require(isRed(sample(image)), "stale blue frame survived generation 2")
        }
        clock.command(mediaSeconds: 0.25, rate: 1, playing: true, generation: 2)
        wait(clock, timeout: 4) { $0.generation == 2 && imageReady($0, near: 0.25) }
        require(isRed(sample(needImage(clock))), "generation 2 did not show the restarted red frame")
        clock.command(mediaSeconds: 2.45, rate: 1, playing: true, generation: 2)
        wait(clock, timeout: 4) { $0.generation == 2 && imageReady($0, near: 2.45) }
        require(isBlue(sample(needImage(clock))), "generation 2 blue frame missing")
        clock.retire(generation: 3)
        clock.poll(blackKey: false, threshold: 0)
        require(clock.image == nil, "same-target retire kept a frame")
        require(!clock.stats.valid, "empty slot stayed valid")
        clock.command(mediaSeconds: 2.45, rate: 1, playing: true, generation: 3)
        wait(clock, timeout: 4) { $0.generation == 3 && imageReady($0, near: 2.45) }
        require(isBlue(sample(needImage(clock))), "same target after retire did not decode a frame, pts=\(clock.stats.pts ?? -1)")
        let closeStarted = Date()
        clock.close()
        require(Date().timeIntervalSince(closeStarted) < 0.5, "close joined for \(Date().timeIntervalSince(closeStarted))s")

        let memory = PreviewVideoClock()
        memory.open(url: long, generation: 3)
        memory.command(mediaSeconds: 0, rate: 1, playing: true, generation: 3)
        wait(memory, timeout: 4) { imageReady($0, near: 0) || ($0.valid && ($0.pts ?? 1) < 0.2) }
        let afterOpenFrames = memory.stats.decodedFrames
        memory.command(mediaSeconds: 7, rate: 1, playing: true, generation: 3)
        wait(memory, timeout: 4) { imageReady($0, near: 7) }
        let delta = memory.stats.decodedFrames - afterOpenFrames
        require(delta < 40, "seek to 7s decoded \(delta) frames from \(afterOpenFrames)")
        let peak = memory.stats.peakResidentBytes
        let fullMovie = 80 * 160 * 120 * 4
        require(peak > 0 && peak < 2_000_000 && peak < fullMovie, "applied frame peak \(peak) is outside the frame budget or covers a full \(fullMovie)-byte movie")
        require(memory.stats.audioDecodedPackets == 0, "long clip decoded audio")
        memory.close()

        let sparse = try encodeSolid(
            root.appendingPathComponent("sparse.wmv"),
            codec: "wmv2",
            color: "0x808080",
            size: "960x540",
            seconds: 8,
            gop: 500
        )
        let hold = PreviewVideoClock()
        hold.open(url: sparse, generation: 9)
        hold.command(mediaSeconds: 0.1, rate: 1, playing: true, generation: 9)
        wait(hold, timeout: 4) { imageReady($0, near: 0.1) || ($0.valid && ($0.pts ?? 1) < 0.3) }
        let baseFrames = hold.stats.decodedFrames
        hold.command(mediaSeconds: 6.5, rate: 1, playing: true, generation: 9)
        let spinEnd = Date().addingTimeInterval(2)
        var started = false
        while Date() < spinEnd {
            hold.poll(blackKey: false, threshold: 0)
            let pts = hold.stats.pts ?? 0
            if hold.stats.decodedFrames >= baseFrames + 2 && pts < 1.0 {
                started = true
                break
            }
            if pts > 2 { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        require(started, "catch-up finished before cancel, pts=\(hold.stats.pts ?? -1) frames=\(hold.stats.decodedFrames)")
        let midFrames = hold.stats.decodedFrames
        hold.command(mediaSeconds: 0.15, rate: 1, playing: false, generation: 9)
        let holdEnd = Date().addingTimeInterval(4)
        var settled = false
        while Date() < holdEnd {
            hold.poll(blackKey: false, threshold: 0)
            if let pts = hold.stats.pts, pts > 1.5 {
                fail("stale catch-up published \(pts) after hold")
            }
            if hold.stats.valid, let pts = hold.stats.pts, abs(pts - 0.15) < 0.25, abs(hold.outputRate) < 0.001 {
                settled = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        require(settled, "hold did not settle near 0.15 pts=\(hold.stats.pts ?? -1) rate=\(hold.outputRate) err=\(hold.stats.error)")
        require(hold.stats.decodedFrames - midFrames < 35, "hold let catch-up continue for \(hold.stats.decodedFrames - midFrames) frames")
        let frozenSerial = hold.stats.frameSerial
        let frozenCopies = hold.stats.copyCount
        let frozenPTS = hold.stats.pts ?? -1
        Thread.sleep(forTimeInterval: 0.25)
        for _ in 0..<8 { hold.poll(blackKey: false, threshold: 0) }
        require(hold.stats.frameSerial == frozenSerial, "late frame published after hold")
        require(hold.stats.copyCount == frozenCopies, "hold polls copied")
        require(abs((hold.stats.pts ?? -1) - frozenPTS) < 0.001, "hold moved pts to \(hold.stats.pts ?? -1)")
        let holdClose = Date()
        hold.close()
        require(Date().timeIntervalSince(holdClose) < 0.5, "hold close joined for \(Date().timeIntervalSince(holdClose))s")
        _ = sparse
    }

    @MainActor
    private static func testWMV1Frame() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try encodeSolid(root.appendingPathComponent("red1.wmv"), codec: "wmv1", color: "0xFF0000", size: "64x48", seconds: 0.6)
        let clock = PreviewVideoClock()
        clock.open(url: url, generation: 1)
        clock.command(mediaSeconds: 0.1, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { $0.codec == "wmv1" && $0.format.contains("asf") && imageReady($0, near: 0.1) }
        let pixel = sample(needImage(clock))
        require(isRed(pixel), "wmv1 frame is not red \(pixel)")
        require(clock.stats.originalWidth == 64 && clock.stats.originalHeight == 48, "wmv1 size \(clock.stats.originalWidth)x\(clock.stats.originalHeight)")
        require(clock.stats.audioDecodedPackets == 0, "wmv1 decoded audio")
        clock.close()
    }

    @MainActor
    private static func testViewClockLayersCropBlackKeyAndChartChange() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let color = try encodeColor(root.appendingPathComponent("color.wmv"), secondsEach: 2, size: "80x60")
        let black = try encodeSolid(root.appendingPathComponent("black.wmv"), codec: "wmv2", color: "0x000000", size: "80x60", seconds: 0.5)
        let blue = try encodeSolid(root.appendingPathComponent("blue.wmv"), codec: "wmv2", color: "0x0000FF", size: "80x60", seconds: 0.8)
        let timing = PreviewAudioTiming(
            headerBPM: 120,
            bpmEvents: [],
            stopEvents: [(beat: 2, durationSeconds: 1.5)]
        )
        let view = PreviewBGAView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        let window = host(view)
        view.setStageLayout(bgaOriginX: 0, nativeCanvasSize: CGSize(width: 256, height: 256))
        view.setTransparencyThreshold(0)
        var chart = PreviewChartSnapshot()
        chart.bgaAssets = [
            PreviewBGAAsset(id: "01", fileName: "color.wmv"),
            PreviewBGAAsset(id: "02", fileName: "black.wmv")
        ]
        chart.bgaEvents = [
            PreviewBGAEvent(beat: 0, assetID: "01", layer: .base),
            PreviewBGAEvent(beat: 0, assetID: "02", layer: .layer),
            PreviewBGAEvent(beat: 0, assetID: "01", layer: .poor)
        ]
        view.setChart(chart, chartDirectory: root, timing: timing, fromBeat: 4, documentData: Data("#BMP01 color.wmv\n#BMP02 black.wmv\n".utf8))
        let idle = view.inspection()
        require(idle.status == "视频未播放" && !idle.videoAttached && idle.videoOpenCount == 0, "video stays closed until playback")
        pump(view, beat: 4, elapsedSeconds: 0, playing: true, timeout: 5) { shot in
            guard let base = shot.presentedNativeVideo(.base) else { return false }
            return isBlue(sample(base.image))
        }
        let here = view.inspection()
        require(abs((here.expectedVideoSeconds ?? -1) - 3.5) < 0.000001, "Here media time \(here.expectedVideoSeconds ?? -1)")
        require(abs((here.nativePresentedPTS ?? -1) - 3.5) < 0.25, "presented pts \(here.nativePresentedPTS ?? -1)")
        require(here.videoOpenCount == 2, "normal opened poor too, open=\(here.videoOpenCount)")
        require(here.videoMuted && here.videoAudioDisabled && here.enabledAudioTrackCount == 0, "native video is not silenced")
        require(here.nativeAudioDecodedPackets == 0, "audio decode \(here.nativeAudioDecodedPackets)")
        require(here.videoAudioTrackCount > 0, "audio stream was not reported")
        require(here.nativeCodecName == "wmv2" && here.nativeFormatName.contains("asf"), "view codec \(here.nativeCodecName) \(here.nativeFormatName)")
        let base = needPicture(view, .base)
        require(base.originalWidth == 80 && base.originalHeight == 60, "original size \(base.originalWidth)x\(base.originalHeight)")
        require(abs(base.hostFrame.minX) < 0.6 && abs(base.hostFrame.minY - 64) < 0.6, "host origin \(base.hostFrame)")
        require(abs(base.hostFrame.width - 256) < 0.6 && abs(base.hostFrame.height - 192) < 0.6, "uncropped host \(base.hostFrame)")
        let seeks = here.videoSeekCount
        view.setPlayback(beat: 4, elapsedSeconds: 0.05, isPlaying: true)
        require(view.inspection().videoSeekCount == seeks, "5cs step seeked")
        view.setPlayback(beat: 4, elapsedSeconds: 0.05, isPlaying: false)
        let paused = view.inspection()
        require(paused.videoRate == 0 && paused.videoItemKept && paused.videoMuted, "pause rate \(paused.videoRate ?? -1) kept \(paused.videoItemKept)")
        require(abs((paused.nativePresentedPTS ?? -1) - (here.nativePresentedPTS ?? -2)) < 0.2, "pause moved pts to \(paused.nativePresentedPTS ?? -1)")
        view.setPlaybackRate(2)
        view.setPlayback(beat: 4, elapsedSeconds: 0.05, isPlaying: true)
        let resumed = view.inspection()
        require(abs(Double(resumed.videoRate ?? -1) - 2) < 0.01, "resume rate \(resumed.videoRate ?? -1)")
        view.setPlaybackRate(1)
        view.setChart(chart, chartDirectory: root, timing: timing, fromBeat: 0, documentData: Data("#BMP01 color.wmv\n#BMP02 black.wmv\n".utf8))
        pump(view, beat: 0, elapsedSeconds: 0.12, playing: true, timeout: 4) { shot in
            guard let base = shot.presentedNativeVideo(.base), let layer = shot.presentedNativeVideo(.layer) else { return false }
            let pixel = sample(layer.image)
            return isRed(sample(base.image)) && pixel.0 == 0 && pixel.1 == 0 && pixel.2 == 0 && pixel.3 == 0
        }
        pump(view, beat: 0, elapsedSeconds: 2.5, playing: true, timeout: 4) { shot in
            guard let picture = shot.presentedNativeVideo(.base) else { return false }
            return isBlue(sample(picture.image)) && abs((shot.inspection().expectedVideoSeconds ?? -1) - 2.5) < 0.000001
        }
        pump(view, beat: 0, elapsedSeconds: 4.6, playing: true, timeout: 4) { shot in
            guard let picture = shot.presentedNativeVideo(.base) else { return false }
            let expected = shot.inspection().expectedVideoSeconds ?? -1
            return abs(expected - 4.6) < 0.000001 && isBlue(sample(picture.image)) && picture.pts > 3.0
        }
        view.setPlayback(beat: 0, elapsedSeconds: 4.6, isPlaying: false)
        let heldTail = view.inspection()
        require(heldTail.videoRate == 0, "EOF pause rate \(heldTail.videoRate ?? -1)")
        require(isBlue(sample(needPicture(view, .base).image)), "EOF pause left the last blue frame")
        pump(view, beat: 0, elapsedSeconds: 0.2, playing: true, timeout: 4) { shot in
            guard let picture = shot.presentedNativeVideo(.base) else { return false }
            return isRed(sample(picture.image))
        }

        view.setDisplayMode(0)
        let off = view.inspection()
        require(!off.videoAttached && view.presentedNativeVideo(.base) == nil, "off kept the decoder attached")
        let opened = off.videoOpenCount
        view.setPlayback(beat: 0, elapsedSeconds: 0.2, isPlaying: true)
        require(view.inspection().videoOpenCount == opened && !view.inspection().videoAttached, "off reopened the video")

        view.setDisplayMode(4)
        pump(view, beat: 0, elapsedSeconds: 0.2, playing: true, timeout: 4) { shot in
            guard let picture = shot.presentedNativeVideo(.poor) else { return false }
            return isRed(sample(picture.image)) && shot.presentedNativeVideo(.base) == nil
        }

        var cropped = PreviewChartSnapshot()
        cropped.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "color.wmv")]
        cropped.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        view.setDisplayMode(3)
        view.setChart(
            cropped,
            chartDirectory: root,
            timing: timing,
            fromBeat: 0,
            documentData: Data("#BMP01 color.wmv\n#BGA01 01 0 0 40 30 0 0\n".utf8)
        )
        pump(view, beat: 0, elapsedSeconds: 0.2, playing: true, timeout: 4) { $0.presentedNativeVideo(.base) != nil }
        let picture = needPicture(view, .base)
        let placement = PreviewBGAGeometry.video(
            originX: 0,
            pixelWidth: 80,
            pixelHeight: 60,
            crop: PreviewBGACropBox(x1: 0, y1: 0, x2: 40, y2: 30, dx: 0, dy: 0),
            stageWidth: 256,
            stageHeight: 256
        )
        require(placement != nil, "crop placement missing")
        let host = PreviewBGAGeometry.videoHostFrame(placement!, scale: 1, stageHeight: 256)
        let fitted = PreviewBGAGeometry.videoPlayerFrame(hostSize: host.size, placement: placement!)
        near(picture.hostFrame, host, "crop host")
        near(picture.imageFrame, fitted, "crop image")
        require(abs(host.width - 40) < 0.6 && abs(host.height - 30) < 0.6, "crop host is not 40x30 \(host)")
        require(isRed(sample(picture.image)), "cropped source frame is not the red half")

        let generation = view.inspection().generation
        var next = PreviewChartSnapshot()
        next.bgaAssets = [PreviewBGAAsset(id: "01", fileName: "blue.wmv")]
        next.bgaEvents = [PreviewBGAEvent(beat: 0, assetID: "01", layer: .base)]
        view.setChart(next, chartDirectory: root, timing: timing, fromBeat: 0, documentData: Data("#BMP01 blue.wmv\n".utf8))
        require(view.inspection().generation > generation, "setChart did not bump generation")
        pump(view, beat: 0, elapsedSeconds: 0.15, playing: true, timeout: 4) { shot in
            guard let picture = shot.presentedNativeVideo(.base) else { return false }
            return isBlue(sample(picture.image))
        }
        require(view.inspection().nativeAudioDecodedPackets == 0, "replacement clip decoded audio")
        _ = window
        _ = color
        _ = black
        _ = blue
    }

    @MainActor
    private static func testParentWMVFixtures() throws {
        let root = parentFixtures()
        let wmv1 = root.appendingPathComponent("wmv1.wmv")
        let wmv2 = root.appendingPathComponent("wmv2.wmv")
        let probe1 = try ffprobe(wmv1)
        let probe2 = try ffprobe(wmv2)
        require(probe1.contains("codec_name=wmv1") && probe1.contains("format_name=asf"), "parent wmv1 probe \(probe1)")
        require(probe2.contains("codec_name=wmv2") && probe2.contains("format_name=asf"), "parent wmv2 probe \(probe2)")
        try expectFixtureFrame(wmv1, codec: "wmv1")
        try expectFixtureFrame(wmv2, codec: "wmv2")
    }

    @MainActor
    private static func expectFixtureFrame(_ url: URL, codec: String) throws {
        let clock = PreviewVideoClock()
        clock.open(url: url, generation: 1)
        require(clock.attached, "\(codec) fixture did not open")
        clock.command(mediaSeconds: 0.4, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { $0.codec == codec && $0.format.contains("asf") && $0.valid && $0.originalWidth == 128 && $0.originalHeight == 96 }
        require(clock.stats.audioDecodedPackets == 0, "\(codec) fixture decoded audio")
        require(!clock.stats.failed, "\(codec) fixture failed \(clock.stats.error)")
        _ = needImage(clock)
        clock.close()
    }

    @MainActor
    private static func testNonZeroStartTime() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try encodeOffset(root.appendingPathComponent("offset.wmv"))
        let probe = try ffprobe(url)
        require(probe.contains("codec_name=wmv2"), "offset probe codec \(probe)")
        require(probe.contains("start_time=1.250000") || probe.contains("start_pts=1250"), "offset start missing \(probe)")
        let clock = PreviewVideoClock()
        clock.open(url: url, generation: 1)
        clock.command(mediaSeconds: 0.20, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { imageReady($0, near: 0.20) }
        require(isRed(sample(needImage(clock))), "normalized 0.20 is not red, pts=\(clock.stats.pts ?? -1)")
        require(abs((clock.stats.pts ?? -1) - 0.20) < 0.2, "start_time was not removed, pts=\(clock.stats.pts ?? -1)")
        clock.command(mediaSeconds: 1.20, rate: 1, playing: true, generation: 1)
        wait(clock, timeout: 4) { imageReady($0, near: 1.20) }
        require(isBlue(sample(needImage(clock))), "normalized 1.20 is not blue, pts=\(clock.stats.pts ?? -1)")
        require(abs(clock.stats.lastSeekSeconds - 1.20) < 0.05, "seek origin leaked into \(clock.stats.lastSeekSeconds)")
        clock.close()
    }

    @MainActor
    private static func testLinkedDecodersAndDecoderLifetime() throws {
        let linked = PreviewVideoClock.linkedDecoders()
        require(linked.audio == 0, "audio decoders are linked: \(linked.names)")
        require(linked.video == 5, "video decoder count \(linked.video) \(linked.names)")
        require(linked.names == "h263,vc1,wmv1,wmv2,wmv3", "decoder inventory \(linked.names)")
        let limit = PreviewVideoClock.inflightLimit
        require(limit >= 3 && limit <= 8, "inflight limit \(limit)")
        let url = parentFixtures().appendingPathComponent("wmv1.wmv")
        var peak = 0
        for _ in 0..<20 {
            let clock = PreviewVideoClock()
            clock.open(url: url, generation: 1)
            clock.close()
            peak = max(peak, PreviewVideoClock.inflight)
            require(PreviewVideoClock.inflight <= limit, "inflight \(PreviewVideoClock.inflight) exceeded \(limit)")
        }
        let drained = Date().addingTimeInterval(3)
        while Date() < drained && PreviewVideoClock.inflight > 0 {
            Thread.sleep(forTimeInterval: 0.02)
        }
        require(PreviewVideoClock.inflight == 0, "retired decoders still inflight \(PreviewVideoClock.inflight) peak \(peak)")
        let again = PreviewVideoClock()
        again.open(url: url, generation: 4)
        require(again.attached, "open failed after retirement")
        again.command(mediaSeconds: 0.2, rate: 1, playing: true, generation: 4)
        wait(again, timeout: 4) { $0.codec == "wmv1" && $0.valid }
        again.close()
        let end = Date().addingTimeInterval(3)
        while Date() < end && PreviewVideoClock.inflight > 0 {
            Thread.sleep(forTimeInterval: 0.02)
        }
        require(PreviewVideoClock.inflight == 0, "final decoder leaked")
    }

    @MainActor
    private static func testContinuousForwardAtSixtyHertz() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = try encodeColor(root.appendingPathComponent("hd.wmv"), secondsEach: 2, size: "960x540")
        let clock = PreviewVideoClock()
        clock.open(url: clip, generation: 1)
        require(clock.attached, "960x540 session did not open")
        let started = Date()
        var media = 0.05
        clock.command(mediaSeconds: media, rate: 1, playing: true, generation: 1)
        var serials = Set<UInt64>()
        var firstPTS: Double?
        var lastPTS: Double?
        var firstFrameAt: TimeInterval?
        var sawRed = false
        let runUntil = Date().addingTimeInterval(2.0)
        while Date() < runUntil {
            media += 1.0 / 60.0
            clock.command(mediaSeconds: media, rate: 1, playing: true, generation: 1)
            clock.poll(blackKey: false, threshold: 0)
            if clock.stats.valid, let pts = clock.stats.pts, pts < 1.7 {
                if firstFrameAt == nil {
                    firstFrameAt = Date().timeIntervalSince(started)
                }
                serials.insert(clock.stats.frameSerial)
                if firstPTS == nil { firstPTS = pts }
                lastPTS = pts
                if isRed(sample(needImage(clock))) { sawRed = true }
            }
            Thread.sleep(forTimeInterval: 1.0 / 60.0)
        }
        require(firstFrameAt != nil, "continuous forward published no frame \(clock.stats)")
        require((firstFrameAt ?? 9) < 1.5, "first frame missed the deadline at \(firstFrameAt ?? -1)s \(clock.stats)")
        require(serials.count >= 3, "continuous forward serials \(serials.count) seeks \(clock.stats.seekCount) pts \(clock.stats.pts ?? -1)")
        require((lastPTS ?? 0) > (firstPTS ?? 0) + 0.05, "pts did not move \(firstPTS ?? -1) -> \(lastPTS ?? -1)")
        require(clock.stats.seekCount <= 2, "continuous forward seeked \(clock.stats.seekCount) times")
        require(sawRed, "forward frames left red pts=\(clock.stats.pts ?? -1)")

        let pausedSerial = clock.stats.frameSerial
        let pausedPTS = clock.stats.pts ?? -1
        let pauseAt = pausedPTS >= 0 ? pausedPTS : media
        clock.command(mediaSeconds: pauseAt, rate: 1, playing: false, generation: 1)
        Thread.sleep(forTimeInterval: 0.2)
        for _ in 0..<8 {
            clock.poll(blackKey: false, threshold: 0)
        }
        require(clock.stats.frameSerial == pausedSerial, "pause published a new frame")
        require(abs((clock.stats.pts ?? -1) - pausedPTS) < 0.001, "pause moved pts to \(clock.stats.pts ?? -1)")

        let holdsBefore = clock.stats.seekCount
        for step in 0..<24 {
            clock.command(mediaSeconds: pauseAt + Double(step) * 0.012, rate: 1, playing: false, generation: 1)
        }
        Thread.sleep(forTimeInterval: 0.25)
        for _ in 0..<6 { clock.poll(blackKey: false, threshold: 0) }
        require(clock.stats.seekCount - holdsBefore <= 2, "rapid hold seeked \(clock.stats.seekCount - holdsBefore) times")
        require(abs(clock.outputRate) < 0.001, "rapid hold resumed")
        if let pts = clock.stats.pts {
            require(pts + 0.35 >= pauseAt && pts < pauseAt + 0.6, "rapid hold landed on \(pts) from \(pauseAt)")
        }

        let jumpFrom = clock.stats.pts ?? pausedPTS
        let seeksBeforeJump = clock.stats.seekCount
        let jumps = [1.2, 3.4, 0.3, 2.72]
        for target in jumps {
            clock.command(mediaSeconds: target, rate: 1, playing: true, generation: 1)
        }
        wait(clock, timeout: 4) { stats in
            guard stats.valid, let pts = stats.pts else { return false }
            return abs(pts - 2.72) < 0.25
        }
        require(clock.stats.seekCount - seeksBeforeJump <= 4, "rapid seek issued \(clock.stats.seekCount - seeksBeforeJump) seeks for \(jumps.count) targets")
        require(abs((clock.stats.pts ?? -1) - jumpFrom) > 0.5, "rapid seek replayed pts \(clock.stats.pts ?? -1)")
        require(isBlue(sample(needImage(clock))), "rapid seek did not reach blue pts=\(clock.stats.pts ?? -1)")
        clock.close()
    }

    @MainActor
    private static func testWorkerFaultStaysReadableUntilClose() throws {
        let url = parentFixtures().appendingPathComponent("wmv1.wmv")
        drainInflight(timeout: 0.5)
        let baseline = PreviewVideoClock.inflight
        PreviewVideoClock.debugArmWorkerFault()
        let broken = PreviewVideoClock()
        broken.open(url: url, generation: 7)
        require(broken.attached, "faulted open did not return a handle")
        let end = Date().addingTimeInterval(2)
        var sawFailure = false
        while Date() < end {
            broken.command(mediaSeconds: 0.2, rate: 1, playing: true, generation: 7)
            broken.poll(blackKey: false, threshold: 0)
            if broken.stats.failed {
                sawFailure = true
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        require(sawFailure, "owner could not read the worker failure \(broken.stats)")
        broken.command(mediaSeconds: 0.4, rate: 1, playing: false, generation: 7)
        broken.poll(blackKey: false, threshold: 0)
        require(broken.stats.failed, "failure was cleared before close")
        broken.close()
        drainInflight(timeout: 3, floor: baseline)
        require(PreviewVideoClock.inflight == baseline, "faulted worker leaked inflight \(PreviewVideoClock.inflight) baseline \(baseline)")
        let again = PreviewVideoClock()
        again.open(url: url, generation: 8)
        require(again.attached, "open after fault did not recover")
        again.command(mediaSeconds: 0.2, rate: 1, playing: true, generation: 8)
        wait(again, timeout: 4) { $0.codec == "wmv1" && $0.valid }
        again.close()
        drainInflight(timeout: 3, floor: baseline)
        require(PreviewVideoClock.inflight == baseline, "recovery decoder leaked inflight \(PreviewVideoClock.inflight)")
    }

    @MainActor
    private static func testInflightFullRetriesWithoutExtraThreads() throws {
        let url = parentFixtures().appendingPathComponent("wmv1.wmv")
        drainInflight(timeout: 0.5)
        let baseline = PreviewVideoClock.inflight
        let limit = PreviewVideoClock.inflightLimit
        require(baseline < limit, "no free decoder slot before the cap test \(baseline)")
        let slots = limit - baseline
        var held: [PreviewVideoClock] = []
        for index in 0..<slots {
            let clock = PreviewVideoClock()
            clock.open(url: url, generation: UInt64(index + 1))
            require(clock.attached, "slot \(index) did not open")
            held.append(clock)
        }
        require(PreviewVideoClock.inflight == limit, "cap was not filled \(PreviewVideoClock.inflight)")
        let extra = PreviewVideoClock()
        extra.open(url: url, generation: 90)
        require(extra.attached, "a full cap dropped the caller")
        require(PreviewVideoClock.inflight <= limit, "pending open started decoder \(PreviewVideoClock.inflight)")
        let cancelled = PreviewVideoClock()
        cancelled.open(url: url, generation: 91)
        require(cancelled.attached, "second delayed open was refused")
        cancelled.close()
        require(PreviewVideoClock.inflight <= limit, "cancelling a delayed open leaked a decoder")
        extra.command(mediaSeconds: 0.2, rate: 1, playing: true, generation: 90)
        extra.poll(blackKey: false, threshold: 0)
        require(!extra.stats.probed && !extra.stats.valid, "full cap decoded before a slot freed \(extra.stats)")
        held[0].close()
        held.removeFirst()
        let admitEnd = Date().addingTimeInterval(4)
        var admitted = false
        while Date() < admitEnd {
            extra.command(mediaSeconds: 0.2, rate: 1, playing: true, generation: 90)
            extra.poll(blackKey: false, threshold: 0)
            require(PreviewVideoClock.inflight <= limit, "retry exceeded the cap \(PreviewVideoClock.inflight)")
            if extra.stats.probed || extra.stats.codec == "wmv1" || extra.stats.valid {
                admitted = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        require(admitted, "delayed open stayed unplayable \(extra.stats) inflight \(PreviewVideoClock.inflight)")
        extra.close()
        for clock in held { clock.close() }
        drainInflight(timeout: 3, floor: baseline)
        require(PreviewVideoClock.inflight == baseline, "cap test leaked \(PreviewVideoClock.inflight) baseline \(baseline)")
    }

    @MainActor
    private static func drainInflight(timeout: TimeInterval, floor: Int = 0) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end && PreviewVideoClock.inflight > floor {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private static func parentFixtures() -> URL {
        let relative = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("out/validation/editor-wmv-clock-20261021/parent-fixtures")
        if FileManager.default.fileExists(atPath: relative.appendingPathComponent("wmv1.wmv").path) {
            return relative
        }
        return URL(fileURLWithPath: "/Users/guanhao/VSCodeAlgorithmTrain/CPP/ibmsc/iBMSCPP/out/validation/editor-wmv-clock-20261021/parent-fixtures", isDirectory: true)
    }

    private static func imageReady(_ stats: PreviewVideoStats, near target: Double) -> Bool {
        guard stats.valid, let pts = stats.pts else { return false }
        return abs(pts - target) < 0.2
    }

    @MainActor
    private static func needImage(_ clock: PreviewVideoClock) -> CGImage {
        clock.poll(blackKey: false, threshold: 0)
        guard let image = clock.image else { fail("missing decoded image \(clock.stats)") }
        return image
    }

    @MainActor
    private static func needPicture(_ view: PreviewBGAView, _ layer: PreviewBGALayer) -> PreviewNativeVideoPicture {
        guard let picture = view.presentedNativeVideo(layer) else { fail("missing \(layer) picture \(view.inspection())") }
        return picture
    }

    private static func isRed(_ pixel: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        pixel.0 > 200 && pixel.1 < 40 && pixel.2 < 40 && pixel.3 > 200
    }

    private static func isBlue(_ pixel: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        pixel.2 > 200 && pixel.0 < 40 && pixel.1 < 40 && pixel.3 > 200
    }

    private static func sample(_ image: CGImage) -> (UInt8, UInt8, UInt8, UInt8) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return (0, 0, 0, 0) }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let x = width / 2
        let y = height / 2
        let index = ((height - 1 - y) * width + x) * 4
        guard index + 3 < bytes.count else { return (0, 0, 0, 0) }
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    @MainActor
    private static func wait(_ clock: PreviewVideoClock, timeout: TimeInterval, _ ready: (PreviewVideoStats) -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            clock.poll(blackKey: false, threshold: 0)
            if ready(clock.stats) { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        fail("timed out \(clock.stats)")
    }

    @MainActor
    private static func pump(
        _ view: PreviewBGAView,
        beat: Double,
        elapsedSeconds: Double,
        playing: Bool,
        timeout: TimeInterval,
        _ ready: (PreviewBGAView) -> Bool
    ) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            view.setPlayback(beat: beat, elapsedSeconds: elapsedSeconds, isPlaying: playing)
            view.layoutSubtreeIfNeeded()
            if ready(view) { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        fail("timed out \(view.inspection())")
    }

    @MainActor
    private static func host(_ view: PreviewBGAView) -> NSWindow {
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame = window.contentView?.bounds ?? view.frame
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        return window
    }

    private static func near(_ actual: CGRect, _ expected: CGRect, _ label: String) {
        require(abs(actual.minX - expected.minX) < 0.6, "\(label) x \(actual) vs \(expected)")
        require(abs(actual.minY - expected.minY) < 0.6, "\(label) y \(actual) vs \(expected)")
        require(abs(actual.width - expected.width) < 0.6, "\(label) w \(actual) vs \(expected)")
        require(abs(actual.height - expected.height) < 0.6, "\(label) h \(actual) vs \(expected)")
    }

    private static func encodeColor(_ url: URL, secondsEach: Int, size: String) throws -> URL {
        let seconds = String(secondsEach)
        let result = run(
            "/opt/homebrew/bin/ffmpeg",
            [
                "-y", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-i", "color=c=0xFF0000:s=\(size):r=10:d=\(seconds)",
                "-f", "lavfi", "-i", "color=c=0x0000FF:s=\(size):r=10:d=\(seconds)",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100:duration=\(secondsEach * 2)",
                "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[v]",
                "-map", "[v]", "-map", "2:a",
                "-c:v", "wmv2", "-b:v", "2M", "-g", "10", "-bf", "0",
                "-c:a", "wmav2", "-b:a", "64k",
                "-f", "asf", url.path
            ]
        )
        require(result.0 == 0, "ffmpeg color failed \(result.0) \(result.1)")
        return url
    }

    private static func encodeOffset(_ url: URL) throws -> URL {
        let result = run(
            "/opt/homebrew/bin/ffmpeg",
            [
                "-y", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-i", "color=c=0xFF0000:s=64x48:r=10:d=1",
                "-f", "lavfi", "-i", "color=c=0x0000FF:s=64x48:r=10:d=1",
                "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[v]",
                "-map", "[v]",
                "-c:v", "wmv2", "-b:v", "1M", "-g", "5", "-bf", "0",
                "-output_ts_offset", "1.25",
                "-f", "asf", url.path
            ]
        )
        require(result.0 == 0, "ffmpeg offset failed \(result.0) \(result.1)")
        return url
    }

    private static func encodeSolid(
        _ url: URL,
        codec: String,
        color: String,
        size: String,
        seconds: Double,
        gop: Int = 5
    ) throws -> URL {
        let result = run(
            "/opt/homebrew/bin/ffmpeg",
            [
                "-y", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-i", "color=c=\(color):s=\(size):r=10:d=\(seconds)",
                "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=44100:duration=\(seconds)",
                "-c:v", codec, "-b:v", "2M", "-g", "\(gop)", "-bf", "0",
                "-c:a", "wmav2", "-b:a", "64k",
                "-shortest",
                "-f", "asf", url.path
            ]
        )
        require(result.0 == 0, "ffmpeg \(codec) failed \(result.0) \(result.1)")
        return url
    }

    private static func ffprobe(_ url: URL) throws -> String {
        let result = run(
            "/opt/homebrew/bin/ffprobe",
            [
                "-hide_banner", "-show_streams", "-show_format",
                "-of", "compact", url.path
            ]
        )
        require(result.0 == 0, "ffprobe failed \(result.0) \(result.1)")
        return result.1
    }

    private static func run(_ launch: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (1, "\(error)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ibms-wmv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("PreviewVideoTests failed: \(message)\n", stderr)
        exit(1)
    }
}
