import AppKit
import Metal
import MetalKit
import QuartzCore

/// 预览画面的滚速和音符尺寸。播放时刻只来自外部传入的拍，这里不建时钟。
@MainActor
enum PreviewPlayfieldMetrics {
    static let defaultPixelsPerBeat = 96.0
    static let minimumPixelsPerBeat = 16.0
    static let maximumPixelsPerBeat = 240.0
    static let shortNoteHeight: CGFloat = 14
    static let longCapHeight: CGFloat = 11
    static let judgmentRatio = 0.82

    static func clampedPixelsPerBeat(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPixelsPerBeat }
        return min(max(value, minimumPixelsPerBeat), maximumPixelsPerBeat)
    }

    static func capBeats(pixelsPerBeat: Double) -> Double {
        let pixels = clampedPixelsPerBeat(pixelsPerBeat)
        return Double(max(shortNoteHeight, longCapHeight) / CGFloat(pixels))
    }

    static func judgmentY(in height: CGFloat) -> CGFloat {
        guard height.isFinite, height > 0 else { return 0 }
        return min(max(height * judgmentRatio, 0), height)
    }

    /// 屏幕上能看见的拍区间。较小的拍在判定线下方，较大的拍在判定线上方。
    static func visibleBeatRange(
        playbackBeat: Double,
        height: CGFloat,
        pixelsPerBeat: Double
    ) -> (bottom: Double, top: Double) {
        let beat = playbackBeat.isFinite ? playbackBeat : 0
        let pixels = clampedPixelsPerBeat(pixelsPerBeat)
        let judgment = judgmentY(in: height)
        let above = Double(judgment / CGFloat(pixels))
        let below = Double(max(height - judgment, 0) / CGFloat(pixels))
        let cap = capBeats(pixelsPerBeat: pixels)
        return (beat - below - cap, beat + above + cap)
    }
}

@MainActor
enum PreviewPlayfieldPalette {
    static let background = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)
    static let scratchLane = NSColor(srgbRed: 0.24, green: 0.10, blue: 0.13, alpha: 1)
    static let whiteLane = NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1)
    static let blueLane = NSColor(srgbRed: 0.09, green: 0.12, blue: 0.24, alpha: 1)
    static let scratchNote = NSColor(srgbRed: 0.94, green: 0.47, blue: 0.56, alpha: 1)
    static let whiteNote = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.94, alpha: 1)
    static let blueNote = NSColor(srgbRed: 0.45, green: 0.70, blue: 0.96, alpha: 1)
    static let judgment = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)
    static let measureLine = NSColor(srgbRed: 0.62, green: 0.67, blue: 0.76, alpha: 1)
    static let beatLine = NSColor(srgbRed: 0.30, green: 0.34, blue: 0.42, alpha: 1)
    static let label = NSColor(srgbRed: 0.78, green: 0.81, blue: 0.86, alpha: 1)
    static let emptyText = NSColor(srgbRed: 0.86, green: 0.88, blue: 0.92, alpha: 1)

    static func laneColor(_ kind: PreviewPlayfieldLaneKind) -> NSColor {
        switch kind {
        case .scratch: scratchLane
        case .white: whiteLane
        case .blue: blueLane
        }
    }

    static func noteColor(_ kind: PreviewPlayfieldLaneKind) -> NSColor {
        switch kind {
        case .scratch: scratchNote
        case .white: whiteNote
        case .blue: blueNote
        }
    }

    static func metalClearColor() -> MTLClearColor {
        let rgba = background.usingColorSpace(.sRGB) ?? background
        return MTLClearColor(
            red: Double(rgba.redComponent),
            green: Double(rgba.greenComponent),
            blue: Double(rgba.blueComponent),
            alpha: 1
        )
    }
}

enum PreviewPlayfieldLaneKind: Equatable {
    case scratch
    case white
    case blue
}

enum PreviewPlayfieldNotePart: Equatable {
    case short
    case head
    case tail
    case body
}

enum PreviewPlayfieldGPUStatus: Equatable {
    case ready
    case unavailable(String)

    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

struct PreviewPlayfieldLaneFrame: Equatable {
    var id: String
    var title: String
    var kind: PreviewPlayfieldLaneKind
    var rect: CGRect
    var channel: Int = 0
    var player: Int = 1
}

struct PreviewPlayfieldNoteMark: Equatable {
    var laneID: String
    var part: PreviewPlayfieldNotePart
    var kind: PreviewPlayfieldLaneKind
    var rect: CGRect
}

struct PreviewPlayfieldHit: Equatable {
    var laneID: String
    var kind: PreviewPlayfieldLaneKind
    var column: CGRect
    var ageBeats: Double
    var isLong = false
    var channel: Int = 0
    var player: Int = 1
    var ageMilliseconds: Int = 0
    /// 长音跨过结尾后的墙钟年龄。还在持有时是 nil。
    var tailAgeMilliseconds: Int? = nil
}

struct PreviewPlayfieldSideJudge: Equatable {
    var player: Int
    var combo: Int
    var ageMilliseconds: Int
    var originX: CGFloat
}

enum PreviewPlayfieldSkinChoice: Equatable {
    case automatic
    case disabled
}

enum PreviewPlayfieldSkinMode: Equatable {
    case original(URL)
    case procedural(String)
}

struct PreviewPlayfieldPresentedSample: Equatable {
    var submitTime: CFTimeInterval
    var presentedTime: CFTimeInterval
}

struct PreviewPlayfieldScene: Equatable {
    var lanes: [PreviewPlayfieldLaneFrame] = []
    var marks: [PreviewPlayfieldNoteMark] = []
    var hits: [PreviewPlayfieldHit] = []
    var measureLineYs: [CGFloat] = []
    var beatLineYs: [CGFloat] = []
    var judgmentY: CGFloat = 0
    var emptyMessage: String?
    var visibleNoteCount = 0
    var combo = 0
    /// 每个可见玩家自己的最近命中。空数组表示这一帧没有还活着的判定。
    var sideJudges: [PreviewPlayfieldSideJudge] = []
    var judgeAge: Double?
    var placement = PreviewUbmStyle.Placement(origin: .zero, scale: 1, contentRect: .zero)
    var usesSkin = false
    var elapsedSeconds = 0.0
    var playbackBeat = 0.0
    var scratchRaw = 0
    var effectsRaw = 7
    var autoSeparate = true
    /// 产品光束不透明。测试把它设成 0.5，确认着色器只把顶点 alpha 乘一次。
    var beamVertexAlpha: CGFloat = 1
    var accessibilityTitle: String = "预览"
    var accessibilityStatus: String = "没有可预览的谱面"
    var accessibilityBeat: String = "0.00"
}

struct PreviewPlayfieldMetalReadback {
    var width: Int
    var height: Int
    var bytesPerRow: Int
    var bgra: Data
    var status: PreviewPlayfieldGPUStatus
    var usedMetal: Bool
    var offscreenWaitSeconds: Double
    var failure: String?

    func components(x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = y * bytesPerRow + x * 4
        guard bytesPerRow >= 4, offset >= 0, offset + 3 < bgra.count else { return nil }
        return (
            Double(bgra[offset + 2]) / 255,
            Double(bgra[offset + 1]) / 255,
            Double(bgra[offset]) / 255,
            Double(bgra[offset + 3]) / 255
        )
    }
}

/// 按开始拍排序。查询时用线段树剪掉已经结束的历史音符，避免每帧扫完整首曲子。
struct PreviewPlayfieldNoteIndex {
    private(set) var lastNodeVisits = 0
    private let notes: [PreviewVisualNote]
    private let tree: [Double]
    private let count: Int

    init(notes: [PreviewVisualNote]) {
        let sorted = notes.compactMap { note -> PreviewVisualNote? in
            guard note.startBeat.isFinite, note.endBeat.isFinite else { return nil }
            var normalized = note
            if normalized.endBeat < normalized.startBeat {
                normalized.endBeat = normalized.startBeat
            }
            return normalized
        }.sorted { lhs, rhs in
            if lhs.startBeat != rhs.startBeat { return lhs.startBeat < rhs.startBeat }
            if lhs.endBeat != rhs.endBeat { return lhs.endBeat < rhs.endBeat }
            return lhs.laneID < rhs.laneID
        }
        self.notes = sorted
        count = sorted.count
        tree = Self.buildTree(ends: sorted.map(\.endBeat))
    }

    /// `bottomBeat` 是屏幕下沿，`topBeat` 是屏幕上沿。返回的音符按开始拍升序。
    mutating func visibleNotes(bottomBeat: Double, topBeat: Double, capBeats: Double) -> [PreviewVisualNote] {
        lastNodeVisits = 0
        guard count > 0, bottomBeat.isFinite, topBeat.isFinite, capBeats.isFinite else { return [] }
        let lastIndex = upperBound(startBeat: topBeat) - 1
        guard lastIndex >= 0 else { return [] }
        var indices: [Int] = []
        collect(
            node: 1,
            rangeLo: 0,
            rangeHi: count - 1,
            queryLo: 0,
            queryHi: lastIndex,
            minEnd: bottomBeat - capBeats,
            into: &indices
        )
        return indices.map { notes[$0] }
    }

    private static func buildTree(ends: [Double]) -> [Double] {
        let count = ends.count
        guard count > 0 else { return [] }
        var tree = [Double](repeating: -.infinity, count: count * 4 + 8)
        func build(_ node: Int, _ lo: Int, _ hi: Int) {
            if lo == hi {
                tree[node] = ends[lo]
                return
            }
            let mid = (lo + hi) / 2
            build(node * 2, lo, mid)
            build(node * 2 + 1, mid + 1, hi)
            tree[node] = max(tree[node * 2], tree[node * 2 + 1])
        }
        build(1, 0, count - 1)
        return tree
    }

    private func upperBound(startBeat: Double) -> Int {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startBeat <= startBeat {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    private mutating func collect(
        node: Int,
        rangeLo: Int,
        rangeHi: Int,
        queryLo: Int,
        queryHi: Int,
        minEnd: Double,
        into indices: inout [Int]
    ) {
        lastNodeVisits += 1
        guard node < tree.count else { return }
        if queryHi < rangeLo || queryLo > rangeHi || tree[node] < minEnd { return }
        if rangeLo == rangeHi {
            indices.append(rangeLo)
            return
        }
        let mid = (rangeLo + rangeHi) / 2
        collect(
            node: node * 2,
            rangeLo: rangeLo,
            rangeHi: mid,
            queryLo: queryLo,
            queryHi: queryHi,
            minEnd: minEnd,
            into: &indices
        )
        collect(
            node: node * 2 + 1,
            rangeLo: mid + 1,
            rangeHi: rangeHi,
            queryLo: queryLo,
            queryHi: queryHi,
            minEnd: minEnd,
            into: &indices
        )
    }
}

/// 切谱时算一次。播放帧只二分可见小节，并直接查这一侧有没有可玩音。
struct PreviewPlayfieldChartPrep: Equatable {
    var playableBoth = false
    var playableOne = false
    var playableTwo = false
    var sortedBars: [Double] = []
    var endBeat = 0.0
    var playableStartsBoth: [Double] = []
    var playableStartsOne: [Double] = []
    var playableStartsTwo: [Double] = []

    func hasPlayable(_ side: PreviewPlayerSide) -> Bool {
        switch side {
        case .both: playableBoth
        case .onePlayer: playableOne
        case .twoPlayer: playableTwo
        }
    }

    /// 已经开始的可玩音。按起始拍二分，不把整首曲子再扫一遍。
    func comboCount(at beat: Double, side: PreviewPlayerSide) -> Int {
        let starts: [Double]
        switch side {
        case .both: starts = playableStartsBoth
        case .onePlayer: starts = playableStartsOne
        case .twoPlayer: starts = playableStartsTwo
        }
        guard beat.isFinite, !starts.isEmpty else { return 0 }
        var lo = 0
        var hi = starts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= beat {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}

enum PreviewPlayfieldClock {
    /// 从 `origin` 第一次走到 `beat` 的秒数。停在终点上的 STOP 不算进到达时刻；起点上的 STOP 会计入后面的拍。
    static func arrivalSeconds(beat: Double, origin: Double, timing: PreviewAudioTiming) -> Double {
        guard beat.isFinite, origin.isFinite else { return 0 }
        if beat >= origin {
            return seconds(fromBeat: origin, toBeat: beat, timing: timing)
        }
        return -seconds(fromBeat: beat, toBeat: origin, timing: timing)
    }

    static func ageSeconds(
        noteBeat: Double,
        origin: Double,
        elapsedSeconds: Double,
        timing: PreviewAudioTiming
    ) -> Double {
        let elapsed = elapsedSeconds.isFinite ? elapsedSeconds : 0
        return elapsed - arrivalSeconds(beat: noteBeat, origin: origin, timing: timing)
    }

    static func seconds(fromBeat: Double, toBeat: Double, timing: PreviewAudioTiming) -> Double {
        guard fromBeat.isFinite, toBeat.isFinite, toBeat >= fromBeat else { return 0 }
        let changes = timing.bpmEvents
            .filter { $0.bpm > 0 && $0.bpm.isFinite && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        let stops = timing.stopEvents
            .filter { $0.durationSeconds > 0 && $0.durationSeconds.isFinite && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        var bpm = usableBPM(timing.headerBPM)
        for event in changes where event.beat <= fromBeat {
            bpm = usableBPM(event.bpm)
        }
        var time = 0.0
        var cursor = fromBeat
        for event in changes where event.beat > fromBeat && event.beat < toBeat {
            time += (event.beat - cursor) * 60 / bpm
            cursor = event.beat
            bpm = usableBPM(event.bpm)
        }
        time += (toBeat - cursor) * 60 / bpm
        for stop in stops where fromBeat <= stop.beat && stop.beat < toBeat {
            time += stop.durationSeconds
        }
        return time
    }

    static func usableBPM(_ bpm: Double) -> Double {
        bpm > 0 && bpm.isFinite ? bpm : 120
    }
}

/// 一次建好的到达函数。`F(b)` 含运动积分和 `stopBeat < b` 的 STOP。
struct PreviewPlayfieldTimeIndex {
    private var knots: [Double]
    private var bpmAfter: [Double]
    private var tempoPrefix: [Double]
    private var header: Double
    private var stopBeats: [Double]
    private var stopPrefix: [Double]

    init(timing: PreviewAudioTiming) {
        header = PreviewPlayfieldClock.usableBPM(timing.headerBPM)
        let changes = timing.bpmEvents
            .filter { $0.bpm > 0 && $0.bpm.isFinite && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        var knotBeats: [Double] = []
        var knotBPM: [Double] = []
        knotBeats.reserveCapacity(changes.count)
        knotBPM.reserveCapacity(changes.count)
        for event in changes {
            if knotBeats.last == event.beat {
                knotBPM[knotBPM.count - 1] = event.bpm
            } else {
                knotBeats.append(event.beat)
                knotBPM.append(event.bpm)
            }
        }
        knots = knotBeats
        bpmAfter = knotBPM
        tempoPrefix = PreviewPlayfieldTimeIndex.tempoPrefixes(knots: knotBeats, bpmAfter: knotBPM, header: header)
        let stops = timing.stopEvents
            .filter { $0.durationSeconds > 0 && $0.durationSeconds.isFinite && $0.beat.isFinite }
            .sorted { $0.beat < $1.beat }
        stopBeats = stops.map(\.beat)
        var prefix = [0.0]
        prefix.reserveCapacity(stops.count + 1)
        for stop in stops {
            prefix.append(prefix[prefix.count - 1] + stop.durationSeconds)
        }
        stopPrefix = prefix
    }

    func arrival(beat: Double, origin: Double) -> Double {
        guard beat.isFinite, origin.isFinite else { return 0 }
        return time(at: beat) - time(at: origin)
    }

    func time(at beat: Double) -> Double {
        guard beat.isFinite else { return 0 }
        return tempo(at: beat) + stops(before: beat)
    }

    private func tempo(at beat: Double) -> Double {
        guard let first = knots.first, let firstPrefix = tempoPrefix.first else {
            return beat * 60 / header
        }
        if beat < first {
            return firstPrefix + (beat - first) * 60 / header
        }
        let index = PreviewPlayfieldTimeIndex.lastNotAfter(beat, in: knots)
        if knots[index] == beat {
            return tempoPrefix[index]
        }
        return tempoPrefix[index] + (beat - knots[index]) * 60 / bpmAfter[index]
    }

    private func stops(before beat: Double) -> Double {
        stopPrefix[PreviewPlayfieldTimeIndex.firstNotBefore(beat, in: stopBeats)]
    }

    private static func tempoPrefixes(knots: [Double], bpmAfter: [Double], header: Double) -> [Double] {
        guard !knots.isEmpty else { return [] }
        var relative = [Double](repeating: 0, count: knots.count)
        for index in 1..<knots.count {
            relative[index] = relative[index - 1] + (knots[index] - knots[index - 1]) * 60 / bpmAfter[index - 1]
        }
        let fromFirstToZero: Double
        if knots[0] >= 0 {
            fromFirstToZero = (0 - knots[0]) * 60 / header
        } else if knots[knots.count - 1] <= 0 {
            let last = knots.count - 1
            fromFirstToZero = relative[last] + (0 - knots[last]) * 60 / bpmAfter[last]
        } else {
            var index = 0
            while index + 1 < knots.count, knots[index + 1] <= 0 {
                index += 1
            }
            if knots[index] == 0 {
                fromFirstToZero = relative[index]
            } else {
                fromFirstToZero = relative[index] + (0 - knots[index]) * 60 / bpmAfter[index]
            }
        }
        return relative.map { $0 - fromFirstToZero }
    }

    private static func firstNotBefore(_ beat: Double, in beats: [Double]) -> Int {
        var low = 0
        var high = beats.count
        while low < high {
            let mid = (low + high) / 2
            if beats[mid] < beat {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func lastNotAfter(_ beat: Double, in beats: [Double]) -> Int {
        var low = 0
        var high = beats.count
        while low < high {
            let mid = (low + high) / 2
            if beats[mid] <= beat {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low - 1
    }
}

struct PreviewPlayfieldLaneSchedule: Equatable {
    var seconds: [Double]
    var endSeconds: [Double]
    var isLong: [Bool]
    var player: Int
}

struct PreviewPlayfieldLatchedHit: Equatable {
    var index: Int
    var birthWall: Double
    var isLong: Bool
    var endChart: Double
    var tailBirthWall: Double?
}

struct PreviewPlayfieldClockSample: Equatable {
    var chart: Double
    var wall: Double
}

@MainActor
enum PreviewPlayfieldLayout {
    static let emptyChartMessage = "没有可预览的谱面"
    static let emptyNotesMessage = "没有可玩音符"
    static let missingMetalMessage = "这台机器没有可用的 Metal 设备"
    static let missingQueueMessage = "Metal 命令队列未能建立"
    static let missingPipelineMessage = "Metal 着色器或渲染管线未能建立"

    static func lanes(_ lanes: [PreviewVisualLane], side: PreviewPlayerSide) -> [PreviewVisualLane] {
        switch side {
        case .both:
            return lanes
        case .onePlayer:
            return lanes.filter { $0.player == 1 }
        case .twoPlayer:
            return lanes.filter { $0.player == 2 }
        }
    }

    static func contentPlacement(in bounds: CGRect) -> PreviewUbmStyle.Placement {
        let fitted = PreviewUbmStyle.placement(in: bounds.size)
        return PreviewUbmStyle.Placement(
            origin: CGPoint(x: bounds.minX + fitted.origin.x, y: bounds.minY + fitted.origin.y),
            scale: fitted.scale,
            contentRect: CGRect(
                x: bounds.minX + fitted.contentRect.minX,
                y: bounds.minY + fitted.contentRect.minY,
                width: fitted.contentRect.width,
                height: fitted.contentRect.height
            )
        )
    }

    static func lastAtMost(_ value: Double, in ordered: [Double]) -> Int {
        var low = 0
        var high = ordered.count
        while low < high {
            let mid = (low + high) / 2
            if ordered[mid] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low - 1
    }

    static func laneFrames(
        for lanes: [PreviewVisualLane],
        in bounds: CGRect,
        scratchRaw: Int = 0,
        autoSeparate: Bool = true
    ) -> [PreviewPlayfieldLaneFrame] {
        let placement = contentPlacement(in: bounds)
        return zip(lanes, PreviewUbmStyle.nativeColumns(for: lanes, scratchRaw: scratchRaw, autoSeparate: autoSeparate)).compactMap { lane, column in
            guard column.rect.width > 0, column.rect.height > 0 else { return nil }
            return PreviewPlayfieldLaneFrame(
                id: lane.id,
                title: lane.title,
                kind: column.kind,
                rect: placement.viewRect(column.rect),
                channel: column.channel,
                player: column.player
            )
        }
    }

    static func scene(
        chart: PreviewChartSnapshot,
        side: PreviewPlayerSide,
        index: inout PreviewPlayfieldNoteIndex,
        bounds: CGRect,
        pixelsPerBeat: Double,
        playbackBeat: Double,
        elapsedSeconds: Double,
        isPlaying: Bool,
        metalUnavailable: String?,
        prep cached: PreviewPlayfieldChartPrep? = nil,
        usesSkin: Bool = false,
        skinNotice: String? = nil,
        scratchRaw: Int = 0,
        effectsRaw: Int = 7,
        autoSeparate: Bool = true,
        latches: [String: PreviewPlayfieldLatchedHit] = [:],
        playerBirths: [Int: Double] = [:],
        beamVertexAlpha: CGFloat = 1
    ) -> PreviewPlayfieldScene {
        let prepared = cached ?? PreviewPlayfieldLayout.prep(for: chart)
        let pixels = PreviewPlayfieldMetrics.clampedPixelsPerBeat(pixelsPerBeat)
        let placement = contentPlacement(in: bounds)
        let scale = placement.scale > 0 ? placement.scale : 1
        let viewPixels = pixels * Double(scale)
        let beat = playbackBeat.isFinite ? playbackBeat : 0
        let elapsed = elapsedSeconds.isFinite ? elapsedSeconds : 0
        let judgment = placement.origin.y + PreviewUbmStyle.judgmentTop * scale
        let noteHeight = PreviewUbmStyle.noteHeight * scale
        let visibleLanes = lanes(chart.lanes, side: side)
        let laneFrames = laneFrames(for: visibleLanes, in: bounds, scratchRaw: scratchRaw, autoSeparate: autoSeparate)
        var laneByID: [String: PreviewPlayfieldLaneFrame] = [:]
        for lane in laneFrames where laneByID[lane.id] == nil {
            laneByID[lane.id] = lane
        }
        let above = Double(PreviewUbmStyle.judgmentTop / CGFloat(pixels))
        let below = Double((PreviewUbmStyle.playfieldSize.height - PreviewUbmStyle.judgmentTop) / CGFloat(pixels))
        let cap = Double(PreviewUbmStyle.noteHeight / CGFloat(pixels))
        let range = (bottom: beat - below - cap, top: beat + above + cap)
        let visible = index.visibleNotes(bottomBeat: range.bottom, topBeat: range.top, capBeats: cap)
        var marks: [PreviewPlayfieldNoteMark] = []
        var visibleNoteCount = 0
        for note in visible {
            guard let lane = laneByID[note.laneID] else { continue }
            visibleNoteCount += 1
            marks.append(contentsOf: marksFor(
                note: note,
                lane: lane,
                playbackBeat: beat,
                judgmentY: judgment,
                pixelsPerBeat: viewPixels,
                noteHeight: noteHeight
            ))
        }
        var hitByLane: [String: PreviewPlayfieldHit] = [:]
        for lane in laneFrames {
            guard let latch = latches[lane.id] else { continue }
            var age = elapsed - latch.birthWall
            if age < 0, age > -0.002 { age = 0 }
            let ageMilliseconds = PreviewUbmStyle.effectMilliseconds(age)
            let beam = PreviewUbmStyle.beamVisible(ageMilliseconds: ageMilliseconds)
            var tailAgeMilliseconds: Int?
            if latch.isLong, let tailBirth = latch.tailBirthWall {
                var tailAge = elapsed - tailBirth
                if tailAge < 0, tailAge > -0.002 { tailAge = 0 }
                tailAgeMilliseconds = PreviewUbmStyle.effectMilliseconds(tailAge)
            }
            // 持有只把命中留在这一帧。光束和键帽不在这里用头龄 50 ms 裁掉。
            let holding = latch.isLong && latch.tailBirthWall == nil && ageMilliseconds >= 0
            let tailBomb = tailAgeMilliseconds.map { $0 >= 0 && $0 < PreviewUbmStyle.bombClearMilliseconds } ?? false
            let shortBomb = !latch.isLong && PreviewUbmStyle.bombVisible(ageMilliseconds: ageMilliseconds, isLong: false)
            let judgmentShown = PreviewUbmStyle.judgmentVisible(ageMilliseconds: ageMilliseconds)
            guard beam || holding || tailBomb || shortBomb || judgmentShown else { continue }
            hitByLane[lane.id] = PreviewPlayfieldHit(
                laneID: lane.id,
                kind: lane.kind,
                column: lane.rect,
                ageBeats: age,
                isLong: latch.isLong,
                channel: lane.channel,
                player: lane.player,
                ageMilliseconds: ageMilliseconds,
                tailAgeMilliseconds: tailAgeMilliseconds
            )
        }
        let hits = hitByLane.values.sorted { lhs, rhs in
            if lhs.ageBeats != rhs.ageBeats { return lhs.ageBeats < rhs.ageBeats }
            return lhs.laneID < rhs.laneID
        }
        let lines = laneFrames.isEmpty
            ? (measures: [CGFloat](), beats: [CGFloat]())
            : guideLines(
                sortedBars: prepared.sortedBars,
                endBeat: prepared.endBeat,
                bottomBeat: range.bottom,
                topBeat: range.top,
                playbackBeat: beat,
                judgmentY: judgment,
                pixelsPerBeat: viewPixels,
                height: bounds.height
            )
        let empty = emptyMessage(
            chartHasLanes: !chart.lanes.isEmpty,
            sideHasLanes: !visibleLanes.isEmpty,
            sideHasPlayableNotes: prepared.hasPlayable(side)
        )
        let notice = metalUnavailable == nil ? skinNotice : nil
        let judgePlayers: [Int]
        switch side {
        case .onePlayer: judgePlayers = [1]
        case .twoPlayer: judgePlayers = [2]
        case .both: judgePlayers = [1, 2]
        }
        var sideJudges: [PreviewPlayfieldSideJudge] = []
        for player in judgePlayers {
            guard let birth = playerBirths[player] else { continue }
            var judgeAgeSeconds = elapsed - birth
            if judgeAgeSeconds < 0, judgeAgeSeconds > -0.002 { judgeAgeSeconds = 0 }
            let ageMilliseconds = PreviewUbmStyle.effectMilliseconds(judgeAgeSeconds)
            guard PreviewUbmStyle.judgmentVisible(ageMilliseconds: ageMilliseconds) else { continue }
            let judgeSide: PreviewPlayerSide = player == 2 ? .twoPlayer : .onePlayer
            sideJudges.append(PreviewPlayfieldSideJudge(
                player: player,
                combo: prepared.comboCount(at: beat, side: judgeSide),
                ageMilliseconds: ageMilliseconds,
                originX: PreviewUbmStyle.panelSeed(player: player, autoSeparate: autoSeparate)
            ))
        }
        return PreviewPlayfieldScene(
            lanes: laneFrames,
            marks: marks,
            hits: Array(hits.prefix(32)),
            measureLineYs: lines.measures,
            beatLineYs: lines.beats,
            judgmentY: judgment,
            emptyMessage: empty,
            visibleNoteCount: visibleNoteCount,
            combo: prepared.comboCount(at: beat, side: side),
            sideJudges: sideJudges,
            judgeAge: hits.map(\.ageBeats).min(),
            placement: placement,
            usesSkin: usesSkin,
            elapsedSeconds: elapsed,
            playbackBeat: beat,
            scratchRaw: PreviewUbmStyle.clampedScratch(scratchRaw),
            effectsRaw: PreviewUbmStyle.clampedEffects(effectsRaw),
            autoSeparate: autoSeparate,
            beamVertexAlpha: beamVertexAlpha,
            accessibilityTitle: accessibilityTitle(chart.title),
            accessibilityStatus: accessibilityStatus(
                emptyMessage: empty,
                isPlaying: isPlaying,
                beat: beat,
                elapsedSeconds: elapsed,
                metalUnavailable: metalUnavailable,
                skinNotice: notice
            ),
            accessibilityBeat: String(format: "%.2f", beat)
        )
    }

    static func beatY(beat: Double, playbackBeat: Double, judgmentY: CGFloat, pixelsPerBeat: Double) -> CGFloat {
        judgmentY - CGFloat((beat - playbackBeat) * pixelsPerBeat)
    }

    static func prep(for chart: PreviewChartSnapshot) -> PreviewPlayfieldChartPrep {
        var owner: [String: Int] = [:]
        owner.reserveCapacity(chart.lanes.count)
        for lane in chart.lanes where owner[lane.id] == nil {
            owner[lane.id] = lane.player
        }
        var playableBoth = false
        var playableOne = false
        var playableTwo = false
        var startsBoth: [Double] = []
        var startsOne: [Double] = []
        var startsTwo: [Double] = []
        if !owner.isEmpty {
            startsBoth.reserveCapacity(chart.notes.count)
            for note in chart.notes {
                guard note.startBeat.isFinite, note.endBeat.isFinite else { continue }
                guard let player = owner[note.laneID] else { continue }
                playableBoth = true
                startsBoth.append(note.startBeat)
                if player == 1 {
                    playableOne = true
                    startsOne.append(note.startBeat)
                } else if player == 2 {
                    playableTwo = true
                    startsTwo.append(note.startBeat)
                }
            }
        }
        startsBoth.sort()
        startsOne.sort()
        startsTwo.sort()
        return PreviewPlayfieldChartPrep(
            playableBoth: playableBoth,
            playableOne: playableOne,
            playableTwo: playableTwo,
            sortedBars: uniqueSorted(chart.barBeats),
            endBeat: chart.endBeat,
            playableStartsBoth: startsBoth,
            playableStartsOne: startsOne,
            playableStartsTwo: startsTwo
        )
    }

    private static func emptyMessage(
        chartHasLanes: Bool,
        sideHasLanes: Bool,
        sideHasPlayableNotes: Bool
    ) -> String? {
        if !chartHasLanes { return emptyChartMessage }
        if !sideHasLanes || !sideHasPlayableNotes { return emptyNotesMessage }
        return nil
    }

    private static func accessibilityTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "预览" : trimmed
    }

    private static func accessibilityStatus(
        emptyMessage: String?,
        isPlaying: Bool,
        beat: Double,
        elapsedSeconds: Double,
        metalUnavailable: String?,
        skinNotice: String?
    ) -> String {
        let base: String
        if let emptyMessage {
            base = emptyMessage
        } else {
            let motion = isPlaying ? "正在播放" : "已停止"
            base = "\(motion)，第 \(String(format: "%.2f", beat)) 拍，已播放 \(String(format: "%.2f", elapsedSeconds)) 秒"
        }
        if let metalUnavailable, !metalUnavailable.isEmpty {
            return "\(metalUnavailable)。\(base)"
        }
        guard let skinNotice, !skinNotice.isEmpty else { return base }
        return "\(skinNotice)。\(base)"
    }

    private static func marksFor(
        note: PreviewVisualNote,
        lane: PreviewPlayfieldLaneFrame,
        playbackBeat: Double,
        judgmentY: CGFloat,
        pixelsPerBeat: Double,
        noteHeight: CGFloat
    ) -> [PreviewPlayfieldNoteMark] {
        let startY = beatY(
            beat: note.startBeat,
            playbackBeat: playbackBeat,
            judgmentY: judgmentY,
            pixelsPerBeat: pixelsPerBeat
        )
        let length = note.endBeat - note.startBeat
        if length <= 0.000_001 {
            return [PreviewPlayfieldNoteMark(
                laneID: lane.id,
                part: .short,
                kind: lane.kind,
                rect: capRect(bottomY: startY, height: noteHeight, lane: lane.rect, insetFraction: 0)
            )]
        }
        let endY = beatY(
            beat: note.endBeat,
            playbackBeat: playbackBeat,
            judgmentY: judgmentY,
            pixelsPerBeat: pixelsPerBeat
        )
        let bodyTop = min(startY, endY)
        let bodyBottom = max(startY, endY)
        let body = CGRect(x: lane.rect.minX, y: bodyTop, width: lane.rect.width, height: max(bodyBottom - bodyTop, 1))
        return [
            PreviewPlayfieldNoteMark(laneID: lane.id, part: .body, kind: lane.kind, rect: body),
            PreviewPlayfieldNoteMark(
                laneID: lane.id,
                part: .head,
                kind: lane.kind,
                rect: capRect(bottomY: startY, height: noteHeight, lane: lane.rect, insetFraction: 0)
            ),
            PreviewPlayfieldNoteMark(
                laneID: lane.id,
                part: .tail,
                kind: lane.kind,
                rect: capRect(bottomY: endY, height: noteHeight, lane: lane.rect, insetFraction: 0)
            )
        ]
    }

    private static func capRect(bottomY: CGFloat, height: CGFloat, lane: CGRect, insetFraction: CGFloat) -> CGRect {
        let column = insetX(lane, fraction: insetFraction)
        return CGRect(x: column.x, y: bottomY - height, width: column.width, height: height)
    }

    private static func insetX(_ lane: CGRect, fraction: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let inset = min(max(lane.width * fraction, 0), lane.width * 0.4)
        let width = max(lane.width - inset * 2, 1)
        return (lane.midX - width / 2, width)
    }

    private static func guideLines(
        sortedBars: [Double],
        endBeat: Double,
        bottomBeat: Double,
        topBeat: Double,
        playbackBeat: Double,
        judgmentY: CGFloat,
        pixelsPerBeat: Double,
        height: CGFloat
    ) -> (measures: [CGFloat], beats: [CGFloat]) {
        guard height > 1, pixelsPerBeat > 0 else { return ([], []) }
        let lower = bottomBeat - 0.001
        let upper = topBeat + 0.001
        let start = lowerBound(sortedBars, firstAtLeast: lower)
        let end = upperBound(sortedBars, firstGreaterThan: upper)
        var measureBeats: [Double] = []
        if start < end {
            measureBeats.reserveCapacity(end - start + 1)
            measureBeats.append(contentsOf: sortedBars[start..<end])
        }
        if endBeat.isFinite, endBeat >= lower, endBeat <= upper,
           measureBeats.allSatisfy({ abs($0 - endBeat) > 0.000_001 }) {
            measureBeats.append(endBeat)
            measureBeats.sort()
        }
        let measureYs = measureBeats.map {
            beatY(beat: $0, playbackBeat: playbackBeat, judgmentY: judgmentY, pixelsPerBeat: pixelsPerBeat)
        }
        let first = Int(floor(bottomBeat))
        let last = Int(ceil(topBeat))
        var beatYs: [CGFloat] = []
        if last >= first, last - first < 20_000 {
            for beat in first...last {
                let value = Double(beat)
                if measureBeats.contains(where: { abs($0 - value) < 0.000_001 }) { continue }
                let y = beatY(beat: value, playbackBeat: playbackBeat, judgmentY: judgmentY, pixelsPerBeat: pixelsPerBeat)
                if y >= -2, y <= height + 2 {
                    beatYs.append(y)
                }
            }
        }
        return (measureYs, beatYs)
    }

    private static func lowerBound(_ sorted: [Double], firstAtLeast value: Double) -> Int {
        var lo = 0
        var hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    private static func upperBound(_ sorted: [Double], firstGreaterThan value: Double) -> Int {
        var lo = 0
        var hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] <= value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    private static func uniqueSorted(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values.filter(\.isFinite).sorted() {
            if let last = result.last, abs(last - value) < 0.000_001 { continue }
            result.append(value)
        }
        return result
    }
}

private struct PreviewPlayfieldVertex {
    var x: Float
    var y: Float
    var u: Float
    var v: Float
    var r: Float
    var g: Float
    var b: Float
    var a: Float
    var slot: Float
}

private struct PreviewPlayfieldTextureSizes {
    var s0: SIMD2<Float>
    var s1: SIMD2<Float>
    var s2: SIMD2<Float>
    var s3: SIMD2<Float>
    var s4: SIMD2<Float>
}

private final class PreviewPlayfieldPresentationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var submits: [CFTimeInterval] = []
    private var presented: [PreviewPlayfieldPresentedSample] = []
    private let limit = 32

    func recordPresented(_ presentedTime: CFTimeInterval, submit: CFTimeInterval) {
        lock.lock()
        presented.append(PreviewPlayfieldPresentedSample(submitTime: submit, presentedTime: presentedTime))
        if presented.count > limit {
            presented.removeFirst(presented.count - limit)
        }
        lock.unlock()
    }

    func samples() -> [PreviewPlayfieldPresentedSample] {
        lock.lock()
        let copy = presented
        lock.unlock()
        return copy
    }
}

private final class PreviewPlayfieldInFlightGate: @unchecked Sendable {
    private let semaphore: DispatchSemaphore

    init(limit: Int) {
        semaphore = DispatchSemaphore(value: limit)
    }

    func wait() {
        semaphore.wait()
    }

    /// 实时帧用不阻塞的尝试。没有空位就立刻失败，调用方跳过这一帧。
    func tryAcquire() -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }

    func signal() {
        semaphore.signal()
    }
}

private final class PreviewPlayfieldSurface: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class PreviewPlayfieldTextOverlay: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 着色器只编译一次。三块顶点缓冲轮换，避免 CPU 写入 GPU 仍在读的那一块。
@MainActor
private final class PreviewPlayfieldMetalSession: NSObject, MTKViewDelegate {
    static let inFlightLimit = 3
    private static let bufferCapacityFloor = 65_536

    let device: MTLDevice
    let status: PreviewPlayfieldGPUStatus
    let skinMode: PreviewPlayfieldSkinMode
    private(set) var pipelineCompileCount = 0
    /// 进入读图集的 `loadSkin` 次数。一次会话一次，播放帧不再增加。
    private(set) static var atlasLoadCount = 0
    private(set) var vertexBufferAllocationCount = 0
    private(set) var drawablePresentationCount = 0
    private(set) var skippedLiveFrameCount = 0
    var cpuVertices: [PreviewPlayfieldVertex] = []
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private let gate = PreviewPlayfieldInFlightGate(limit: PreviewPlayfieldMetalSession.inFlightLimit)
    private let presentationLog = PreviewPlayfieldPresentationLog()
    private let textures: [MTLTexture?]
    private let textureSizes: PreviewPlayfieldTextureSizes
    private var buffers: [MTLBuffer?]
    private var ringIndex = 0
    private var offscreenTexture: MTLTexture?
    private var offscreenBuffer: MTLBuffer?
    private var offscreenWidth = 0
    private var offscreenHeight = 0
    private var offscreenBytesPerRow = 0

    init(device: MTLDevice, skinChoice: PreviewPlayfieldSkinChoice) {
        self.device = device
        buffers = Array(repeating: nil, count: Self.inFlightLimit)
        let loaded = Self.loadSkin(device: device, choice: skinChoice)
        skinMode = loaded.mode
        textures = loaded.textures
        textureSizes = loaded.sizes
        let queue = device.makeCommandQueue()
        commandQueue = queue
        if queue == nil {
            pipeline = nil
            status = .unavailable(PreviewPlayfieldLayout.missingQueueMessage)
            super.init()
            return
        }
        if let compiled = Self.makePipeline(device: device) {
            pipeline = compiled
            pipelineCompileCount = 1
            status = .ready
        } else {
            pipeline = nil
            status = .unavailable(PreviewPlayfieldLayout.missingPipelineMessage)
        }
        super.init()
    }

    func recentPresentedSamples() -> [PreviewPlayfieldPresentedSample] {
        presentationLog.samples()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard status == .ready else { return }
        guard gate.tryAcquire() else {
            skippedLiveFrameCount += 1
            return
        }
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            gate.signal()
            return
        }
        let submitTime = CACurrentMediaTime()
        drawable.addPresentedHandler { [presentationLog] drawable in
            presentationLog.recordPresented(drawable.presentedTime, submit: submitTime)
        }
        guard encodeAssumingHeld(pass: pass, prepare: { commandBuffer in
            commandBuffer.present(drawable)
        }) != nil else { return }
        drawablePresentationCount += 1
    }

    func holdAllSlotsForTesting() {
        for _ in 0..<Self.inFlightLimit {
            gate.wait()
        }
    }

    func releaseHeldSlotsForTesting() {
        for _ in 0..<Self.inFlightLimit {
            gate.signal()
        }
    }

    func renderOffscreen(width: Int, height: Int, clear: MTLClearColor) -> PreviewPlayfieldMetalReadback {
        guard status == .ready, width > 0, height > 0 else {
            return PreviewPlayfieldMetalReadback(
                width: 0,
                height: 0,
                bytesPerRow: 0,
                bgra: Data(),
                status: status,
                usedMetal: false,
                offscreenWaitSeconds: 0,
                failure: status.unavailableReason
            )
        }
        guard let target = cachedOffscreenTarget(width: width, height: height) else {
            return PreviewPlayfieldMetalReadback(
                width: width,
                height: height,
                bytesPerRow: 0,
                bgra: Data(),
                status: status,
                usedMetal: false,
                offscreenWaitSeconds: 0,
                failure: "无法建立离屏渲染目标"
            )
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clear
        let started = DispatchTime.now().uptimeNanoseconds
        gate.wait()
        var didBlit = false
        guard let commandBuffer = encodeAssumingHeld(pass: pass, prepare: { commandBuffer in
            guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
            blit.copy(
                from: target.texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: target.buffer,
                destinationOffset: 0,
                destinationBytesPerRow: target.bytesPerRow,
                destinationBytesPerImage: target.bytesPerRow * height
            )
            blit.endEncoding()
            didBlit = true
        }), didBlit else {
            return PreviewPlayfieldMetalReadback(
                width: width,
                height: height,
                bytesPerRow: target.bytesPerRow,
                bgra: Data(),
                status: status,
                usedMetal: false,
                offscreenWaitSeconds: 0,
                failure: "无法提交 Metal 命令"
            )
        }
        commandBuffer.waitUntilCompleted()
        let waited = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000_000
        guard commandBuffer.status == .completed else {
            let detail = commandBuffer.error?.localizedDescription ?? "Metal 离屏绘制没有完成"
            return PreviewPlayfieldMetalReadback(
                width: width,
                height: height,
                bytesPerRow: target.bytesPerRow,
                bgra: Data(),
                status: status,
                usedMetal: false,
                offscreenWaitSeconds: waited,
                failure: detail
            )
        }
        let byteCount = target.bytesPerRow * height
        let bytes = Data(bytes: target.buffer.contents(), count: byteCount)
        return PreviewPlayfieldMetalReadback(
            width: width,
            height: height,
            bytesPerRow: target.bytesPerRow,
            bgra: bytes,
            status: status,
            usedMetal: true,
            offscreenWaitSeconds: waited,
            failure: nil
        )
    }

    private func cachedOffscreenTarget(width: Int, height: Int) -> (texture: MTLTexture, buffer: MTLBuffer, bytesPerRow: Int)? {
        let alignment = max(device.minimumLinearTextureAlignment(for: .bgra8Unorm), 256)
        let row = max(width * 4, alignment)
        let bytesPerRow = ((row + alignment - 1) / alignment) * alignment
        if let texture = offscreenTexture, let buffer = offscreenBuffer,
           offscreenWidth == width, offscreenHeight == height, offscreenBytesPerRow == bytesPerRow {
            return (texture, buffer, bytesPerRow)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor),
              let buffer = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared) else {
            return nil
        }
        offscreenTexture = texture
        offscreenBuffer = buffer
        offscreenWidth = width
        offscreenHeight = height
        offscreenBytesPerRow = bytesPerRow
        return (texture, buffer, bytesPerRow)
    }

    @discardableResult
    private func encodeAssumingHeld(
        pass: MTLRenderPassDescriptor,
        prepare: (MTLCommandBuffer) -> Void
    ) -> MTLCommandBuffer? {
        var handedOff = false
        defer {
            if !handedOff { gate.signal() }
        }
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }
        if let pipeline, !cpuVertices.isEmpty, let buffer = uploadCurrentSlot() {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            var sizes = textureSizes
            encoder.setFragmentBytes(&sizes, length: MemoryLayout<PreviewPlayfieldTextureSizes>.stride, index: 0)
            for index in 0..<min(textures.count, 5) {
                encoder.setFragmentTexture(textures[index], index: index)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cpuVertices.count)
        }
        encoder.endEncoding()
        prepare(commandBuffer)
        commandBuffer.addCompletedHandler { [gate] _ in
            gate.signal()
        }
        handedOff = true
        commandBuffer.commit()
        return commandBuffer
    }

    private func uploadCurrentSlot() -> MTLBuffer? {
        let bytes = cpuVertices.count * MemoryLayout<PreviewPlayfieldVertex>.stride
        guard bytes > 0 else { return nil }
        let slot = ringIndex
        ringIndex = (ringIndex + 1) % Self.inFlightLimit
        if let existing = buffers[slot], existing.length >= bytes {
            cpuVertices.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                existing.contents().copyMemory(from: base, byteCount: min(raw.count, bytes))
            }
            return existing
        }
        let capacity: Int
        if buffers[slot] == nil {
            capacity = max(bytes, Self.bufferCapacityFloor)
        } else {
            capacity = max(bytes, (buffers[slot]?.length ?? Self.bufferCapacityFloor) * 2)
        }
        guard let made = device.makeBuffer(length: capacity, options: .storageModeShared) else { return nil }
        buffers[slot] = made
        vertexBufferAllocationCount += 1
        cpuVertices.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            made.contents().copyMemory(from: base, byteCount: min(raw.count, bytes))
        }
        return made
    }

    private static func loadSkin(
        device: MTLDevice,
        choice: PreviewPlayfieldSkinChoice
    ) -> (mode: PreviewPlayfieldSkinMode, textures: [MTLTexture?], sizes: PreviewPlayfieldTextureSizes) {
        let white = solidTexture(device: device, red: 255, green: 255, blue: 255, alpha: 255)
        var textures: [MTLTexture?] = [white, white, white, white, white]
        var sizes = PreviewPlayfieldTextureSizes(
            s0: SIMD2(1, 1),
            s1: SIMD2(1, 1),
            s2: SIMD2(1, 1),
            s3: SIMD2(1, 1),
            s4: SIMD2(1, 1)
        )
        guard choice == .automatic else {
            return (.procedural(PreviewUbmStyle.disabledSkinMessage), textures, sizes)
        }
        guard let directory = PreviewUbmStyle.skinDirectory() else {
            return (.procedural(PreviewUbmStyle.missingSkinMessage), textures, sizes)
        }
        atlasLoadCount += 1
        guard let skin0 = PreviewUbmStyle.loadAtlas(named: "skin_00.png", in: directory),
              skin0.width == 331, skin0.height == 256,
              let skin1 = PreviewUbmStyle.loadAtlas(named: "skin_01.png", in: directory, keying: .noteSheets),
              skin1.width == 137, skin1.height == 221,
              let skin2 = PreviewUbmStyle.loadAtlas(named: "skin_02.png", in: directory, keying: .noteSheets),
              skin2.width == 160, skin2.height == 244,
              let skin3 = PreviewUbmStyle.loadAtlas(named: "skin_03.png", in: directory, keying: .bombSheet),
              skin3.width == 578, skin3.height == 228,
              let texture0 = upload(device: device, image: skin0),
              let texture1 = upload(device: device, image: skin1),
              let texture2 = upload(device: device, image: skin2),
              let texture3 = upload(device: device, image: skin3) else {
            return (.procedural(PreviewUbmStyle.incompleteSkinMessage), textures, sizes)
        }
        textures = [texture0, texture1, texture2, texture3, white]
        sizes = PreviewPlayfieldTextureSizes(
            s0: SIMD2(Float(skin0.width), Float(skin0.height)),
            s1: SIMD2(Float(skin1.width), Float(skin1.height)),
            s2: SIMD2(Float(skin2.width), Float(skin2.height)),
            s3: SIMD2(Float(skin3.width), Float(skin3.height)),
            s4: SIMD2(1, 1)
        )
        return (.original(directory), textures, sizes)
    }

    private static func upload(device: MTLDevice, image: PreviewUbmStyle.AtlasImage) -> MTLTexture? {
        var bgra = [UInt8](repeating: 0, count: image.rgba.count)
        var index = 0
        while index + 3 < image.rgba.count {
            bgra[index] = image.rgba[index + 2]
            bgra[index + 1] = image.rgba[index + 1]
            bgra[index + 2] = image.rgba[index]
            bgra[index + 3] = image.rgba[index + 3]
            index += 4
        }
        return texture(device: device, width: image.width, height: image.height, bgra: bgra)
    }

    private static func solidTexture(device: MTLDevice, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> MTLTexture? {
        texture(device: device, width: 1, height: 1, bgra: [blue, green, red, alpha])
    }

    private static func texture(device: MTLDevice, width: Int, height: Int, bgra: [UInt8]) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let alignment = max(device.minimumLinearTextureAlignment(for: .bgra8Unorm), 64)
        let bytesPerRow = ((width * 4 + alignment - 1) / alignment) * alignment
        var padded = [UInt8](repeating: 0, count: bytesPerRow * height)
        let sourceRow = width * 4
        for row in 0..<height {
            let source = row * sourceRow
            let destination = row * bytesPerRow
            padded.replaceSubrange(destination..<(destination + sourceRow), with: bgra[source..<(source + sourceRow)])
        }
        padded.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vertex {
            packed_float2 position;
            packed_float2 uv;
            packed_float4 color;
            float slot;
        };
        struct Output {
            float4 position [[position]];
            float2 uv;
            float4 color;
            float slot;
        };
        struct Sizes {
            float2 s0;
            float2 s1;
            float2 s2;
            float2 s3;
            float2 s4;
        };

        vertex Output previewPlayfieldVertex(uint vid [[vertex_id]], constant Vertex *vertices [[buffer(0)]]) {
            Vertex value = vertices[vid];
            Output output;
            output.position = float4(float2(value.position), 0.0, 1.0);
            output.uv = float2(value.uv);
            output.color = float4(value.color);
            output.slot = value.slot;
            return output;
        }

        float2 snapUV(float2 uv, float2 size) {
            float2 safe = max(size, float2(1.0));
            float2 texel = clamp(floor(uv * safe), float2(0.0), safe - 1.0);
            return (texel + 0.5) / safe;
        }

        fragment float4 previewPlayfieldFragment(
            Output input [[stage_in]],
            constant Sizes &sizes [[buffer(0)]],
            texture2d<float> skin0 [[texture(0)]],
            texture2d<float> skin1 [[texture(1)]],
            texture2d<float> skin2 [[texture(2)]],
            texture2d<float> skin3 [[texture(3)]],
            texture2d<float> solid [[texture(4)]]
        ) {
            constexpr sampler nearestSampler(mag_filter::nearest, min_filter::nearest, address::clamp_to_edge);
            int slot = int(input.slot + 0.5);
            float4 tex;
            if (slot <= 0) {
                tex = skin0.sample(nearestSampler, snapUV(input.uv, sizes.s0));
            } else if (slot == 1) {
                tex = skin1.sample(nearestSampler, snapUV(input.uv, sizes.s1));
            } else if (slot == 2) {
                tex = skin2.sample(nearestSampler, snapUV(input.uv, sizes.s2));
            } else if (slot == 3) {
                tex = skin3.sample(nearestSampler, snapUV(input.uv, sizes.s3));
            } else {
                tex = solid.sample(nearestSampler, snapUV(input.uv, sizes.s4));
            }
            float4 sampled = tex * float4(input.color.rgb, 1.0);
            return float4(sampled.rgb, sampled.a * input.color.a);
        }
        """
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let vertex = library.makeFunction(name: "previewPlayfieldVertex"),
                  let fragment = library.makeFunction(name: "previewPlayfieldFragment") else {
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
    }
}

/// 下落式预览。判定线固定，音符位置只由 `setPlayback` 的拍决定。几何由 Metal 绘制。
@MainActor
final class PreviewPlayfieldView: NSView {
    private let session: PreviewPlayfieldMetalSession?
    let gpuStatus: PreviewPlayfieldGPUStatus
    private var chart = PreviewChartSnapshot()
    private var chartPrep = PreviewPlayfieldLayout.prep(for: PreviewChartSnapshot())
    private var noteIndex = PreviewPlayfieldNoteIndex(notes: [])
    private var playbackBeat = 0.0
    private var chartElapsedSeconds = 0.0
    private var elapsedSeconds = 0.0
    private var isPlaying = false
    private var clockSample: PreviewPlayfieldClockSample?
    private var latchedHits: [String: PreviewPlayfieldLatchedHit] = [:]
    /// 玩家 1 和 2 最近一次命中的墙钟。过期后仍留着，避免退回更早的 GREAT。
    private var playerBirthWall: [Int: Double] = [:]
    private var storedPixelsPerBeat = PreviewPlayfieldMetrics.defaultPixelsPerBeat
    private var scratchRaw = 0
    private var effectsRaw = 7
    private var autoSeparate = true
    private var timing = PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
    private var timingOrigin = 0.0
    private var hitSchedules: [String: PreviewPlayfieldLaneSchedule] = [:]
    private var timeIndex = PreviewPlayfieldTimeIndex(
        timing: PreviewAudioTiming(headerBPM: 120, bpmEvents: [], stopEvents: [])
    )
    private var beamVertexAlpha: CGFloat = 1
    private(set) var playerSide: PreviewPlayerSide = .both
    private var metalView: PreviewPlayfieldSurface!
    private var overlay: PreviewPlayfieldTextOverlay!
    private var titleLayers: [CATextLayer] = []
    private let messageLayer = CATextLayer()
    private var didInstall = false
    private(set) var textOverlayRevision = 0
    private(set) var displayedOverlayMessage: String?
    private(set) var lastVisibleNoteCount = 0
    private(set) var lastVisibleSelectSeconds = 0.0
    private(set) var lastVertexAssemblySeconds = 0.0
    private(set) var lastGeometryBuildSeconds = 0.0
    private(set) var lastOffscreenWaitSeconds = 0.0
    private(set) var laneTitleFrames: [CGRect] = []

    private(set) var geometryBuildCount = 0
    var pipelineCompileCount: Int { session?.pipelineCompileCount ?? 0 }
    var atlasLoadCount: Int { PreviewPlayfieldMetalSession.atlasLoadCount }
    var vertexBufferAllocationCount: Int { session?.vertexBufferAllocationCount ?? 0 }
    var lastVertexCount: Int { session?.cpuVertices.count ?? 0 }
    var inFlightLimit: Int { PreviewPlayfieldMetalSession.inFlightLimit }
    var drawablePresentationCount: Int { session?.drawablePresentationCount ?? 0 }
    var liveSubmitCount: Int { drawablePresentationCount }
    var skippedLiveFrameCount: Int { session?.skippedLiveFrameCount ?? 0 }
    var skinMode: PreviewPlayfieldSkinMode {
        session?.skinMode ?? .procedural(PreviewPlayfieldLayout.missingMetalMessage)
    }

    func recentPresentedSamples() -> [PreviewPlayfieldPresentedSample] {
        session?.recentPresentedSamples() ?? []
    }

    func holdInFlightSlotsForTesting() {
        session?.holdAllSlotsForTesting()
    }

    func releaseInFlightSlotsForTesting() {
        session?.releaseHeldSlotsForTesting()
    }

    /// 直接走实时 `draw(in:)`。没空闲缓冲时立刻返回，不等 GPU。
    func submitLiveFrameNow() {
        session?.draw(in: metalView)
    }

    /// 窗口里的 MTKView 立刻走外部触发的 `draw(in:)`。没有 drawable 时返回 false，不改用 CPU 填色。
    func drawMetalViewNow() -> Bool {
        guard gpuStatus == .ready, didInstall else { return false }
        let before = drawablePresentationCount
        metalView.draw()
        return drawablePresentationCount > before
    }

    var rendersFromExternalPlayback: Bool {
        guard gpuStatus == .ready, didInstall else { return false }
        return metalView.isPaused && metalView.enableSetNeedsDisplay
    }

    var pixelsPerBeat: Double {
        get { storedPixelsPerBeat }
        set {
            let clamped = PreviewPlayfieldMetrics.clampedPixelsPerBeat(newValue)
            guard clamped != storedPixelsPerBeat else { return }
            storedPixelsPerBeat = clamped
            rebuildGeometry()
        }
    }

    override var isFlipped: Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityTitle() -> String? {
        currentScene().accessibilityTitle
    }

    override func accessibilityLabel() -> String? {
        currentScene().accessibilityStatus
    }

    override func accessibilityValue() -> Any? {
        currentScene().accessibilityBeat
    }

    convenience override init(frame frameRect: NSRect) {
        self.init(frame: frameRect, device: MTLCreateSystemDefaultDevice(), skinChoice: .automatic)
    }

    convenience init(frame frameRect: NSRect, device: MTLDevice?) {
        self.init(frame: frameRect, device: device, skinChoice: .automatic)
    }

    init(frame frameRect: NSRect, device: MTLDevice?, skinChoice: PreviewPlayfieldSkinChoice) {
        let session = device.map { PreviewPlayfieldMetalSession(device: $0, skinChoice: skinChoice) }
        self.session = session
        gpuStatus = session?.status ?? .unavailable(PreviewPlayfieldLayout.missingMetalMessage)
        super.init(frame: frameRect)
        install()
    }

    required init?(coder: NSCoder) {
        let session = MTLCreateSystemDefaultDevice().map { PreviewPlayfieldMetalSession(device: $0, skinChoice: .automatic) }
        self.session = session
        gpuStatus = session?.status ?? .unavailable(PreviewPlayfieldLayout.missingMetalMessage)
        super.init(coder: coder)
        install()
    }

    func setChart(_ chart: PreviewChartSnapshot) {
        guard chart != self.chart else { return }
        self.chart = chart
        chartPrep = PreviewPlayfieldLayout.prep(for: chart)
        noteIndex = PreviewPlayfieldNoteIndex(notes: chart.notes)
        clearHitClocks()
        rebuildHitSchedules()
        let scene = rebuildGeometry()
        updateText(scene: scene)
    }

    func setPlayerSide(_ side: PreviewPlayerSide) {
        guard side != playerSide else { return }
        playerSide = side
        let scene = rebuildGeometry()
        updateText(scene: scene)
    }

    func setPlayback(beat: Double, elapsedSeconds: Double, isPlaying: Bool) {
        commitSetPlayback(
            beat: beat,
            chartElapsedSeconds: elapsedSeconds,
            effectElapsedSeconds: elapsedSeconds,
            isPlaying: isPlaying,
            clocksLocked: true
        )
    }

    /// 谱面秒选择到达的音符，墙钟计算爆炸年龄。暂停时两边都由调用方冻住。
    func setPlayback(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool
    ) {
        commitSetPlayback(
            beat: beat,
            chartElapsedSeconds: chartElapsedSeconds,
            effectElapsedSeconds: effectElapsedSeconds,
            isPlaying: isPlaying,
            clocksLocked: false
        )
    }

    private func commitSetPlayback(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool,
        clocksLocked: Bool
    ) {
        let nextBeat = beat.isFinite ? beat : 0
        let nextChart = chartElapsedSeconds.isFinite ? chartElapsedSeconds : 0
        let nextEffect = effectElapsedSeconds.isFinite ? effectElapsedSeconds : 0
        let unchanged = nextBeat == playbackBeat
            && nextChart == self.chartElapsedSeconds
            && nextEffect == self.elapsedSeconds
            && isPlaying == self.isPlaying
        guard !unchanged || clockSample == nil else { return }
        advancePlaybackClock(
            beat: nextBeat,
            chartElapsedSeconds: nextChart,
            effectElapsedSeconds: nextEffect,
            isPlaying: isPlaying,
            clocksLocked: clocksLocked
        )
        rebuildGeometry()
    }

    /// 只推进有限逻辑时钟和命中锁存。不重建几何，不提交画面，不分配时间轴。
    func advancePlaybackClock(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool
    ) {
        advancePlaybackClock(
            beat: beat,
            chartElapsedSeconds: chartElapsedSeconds,
            effectElapsedSeconds: effectElapsedSeconds,
            isPlaying: isPlaying,
            clocksLocked: false
        )
    }

    private func advancePlaybackClock(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool,
        clocksLocked: Bool
    ) {
        playbackBeat = beat.isFinite ? beat : 0
        self.chartElapsedSeconds = chartElapsedSeconds.isFinite ? chartElapsedSeconds : 0
        self.elapsedSeconds = effectElapsedSeconds.isFinite ? effectElapsedSeconds : 0
        self.isPlaying = isPlaying
        noteHitClock(chart: self.chartElapsedSeconds, wall: self.elapsedSeconds, locked: clocksLocked)
    }

    /// 按共享播放时间更新，并立刻提交一次 MTKView。不另起 Timer，也不只标 needsDisplay。
    func presentPlaybackFrame(beat: Double, elapsedSeconds: Double, isPlaying: Bool) {
        commitPresentPlaybackFrame(
            beat: beat,
            chartElapsedSeconds: elapsedSeconds,
            effectElapsedSeconds: elapsedSeconds,
            isPlaying: isPlaying,
            clocksLocked: true
        )
    }

    func presentPlaybackFrame(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool
    ) {
        commitPresentPlaybackFrame(
            beat: beat,
            chartElapsedSeconds: chartElapsedSeconds,
            effectElapsedSeconds: effectElapsedSeconds,
            isPlaying: isPlaying,
            clocksLocked: false
        )
    }

    private func commitPresentPlaybackFrame(
        beat: Double,
        chartElapsedSeconds: Double,
        effectElapsedSeconds: Double,
        isPlaying: Bool,
        clocksLocked: Bool
    ) {
        advancePlaybackClock(
            beat: beat,
            chartElapsedSeconds: chartElapsedSeconds,
            effectElapsedSeconds: effectElapsedSeconds,
            isPlaying: isPlaying,
            clocksLocked: clocksLocked
        )
        rebuildGeometry(displays: false)
        _ = drawMetalViewNow()
    }

    func currentScene() -> PreviewPlayfieldScene {
        let usesSkin: Bool
        let skinNotice: String?
        switch skinMode {
        case .original:
            usesSkin = true
            skinNotice = nil
        case .procedural(let reason):
            usesSkin = false
            skinNotice = reason
        }
        return PreviewPlayfieldLayout.scene(
            chart: chart,
            side: playerSide,
            index: &noteIndex,
            bounds: bounds,
            pixelsPerBeat: storedPixelsPerBeat,
            playbackBeat: playbackBeat,
            elapsedSeconds: elapsedSeconds,
            isPlaying: isPlaying,
            metalUnavailable: gpuStatus.unavailableReason,
            prep: chartPrep,
            usesSkin: usesSkin,
            skinNotice: skinNotice,
            scratchRaw: scratchRaw,
            effectsRaw: effectsRaw,
            autoSeparate: autoSeparate,
            latches: latchedHits,
            playerBirths: playerBirthWall,
            beamVertexAlpha: beamVertexAlpha
        )
    }

    func setBeamVertexAlpha(_ alpha: CGFloat) {
        let next = alpha.isFinite ? min(max(alpha, 0), 1) : 1
        guard next != beamVertexAlpha else { return }
        beamVertexAlpha = next
        rebuildGeometry()
    }

    /// 预建每条轨道的到达秒。STOP 和 BPM 都算进去。播放头从 `fromBeat` 起算，之前的音符年龄为负。
    func setTiming(_ timing: PreviewAudioTiming, fromBeat: Double) {
        self.timing = timing
        timingOrigin = fromBeat.isFinite ? fromBeat : 0
        clearHitClocks()
        timeIndex = PreviewPlayfieldTimeIndex(timing: self.timing)
        rebuildHitSchedules()
        rebuildGeometry()
    }

    private func clearHitClocks() {
        clockSample = nil
        latchedHits.removeAll()
        playerBirthWall.removeAll()
    }

    /// 用相邻两帧的谱面秒和墙钟插值出生时刻。已经记下的命中不重写。
    private func noteHitClock(chart: Double, wall: Double, locked: Bool) {
        var previous = clockSample
        if let sample = previous, chart + 1e-9 < sample.chart {
            clockSample = nil
            latchedHits.removeAll()
            playerBirthWall.removeAll()
            previous = nil
        }
        if clockSample == nil {
            latchOpening(chart: chart, wall: wall, locked: locked)
        } else if let sample = clockSample {
            latchSegment(from: sample, toChart: chart, toWall: wall)
        }
        advanceTails(previous: previous, chart: chart, wall: wall)
        expireFinishedTails(wall: wall)
        clockSample = PreviewPlayfieldClockSample(chart: chart, wall: wall)
    }

    private func latchOpening(chart: Double, wall: Double, locked: Bool) {
        for (laneID, schedule) in hitSchedules {
            let index = PreviewPlayfieldLayout.lastAtMost(chart, in: schedule.seconds)
            guard index >= 0, schedule.seconds.indices.contains(index) else { continue }
            let noteChart = schedule.seconds[index]
            if noteChart < -1e-6 { continue }
            let chartAge = chart - noteChart
            if !locked, chartAge > 1e-4 { continue }
            let birth = wall - chartAge
            storeLatch(laneID: laneID, index: index, birthWall: birth, schedule: schedule)
        }
    }

    private func latchSegment(from previous: PreviewPlayfieldClockSample, toChart: Double, toWall: Double) {
        let span = toChart - previous.chart
        let wallGap = toWall - previous.wall
        for (laneID, schedule) in hitSchedules {
            let index = PreviewPlayfieldLayout.lastAtMost(toChart, in: schedule.seconds)
            guard index >= 0, schedule.seconds.indices.contains(index) else {
                latchedHits[laneID] = nil
                continue
            }
            if let existing = latchedHits[laneID], existing.index == index {
                if existing.isLong {
                    continue
                }
                let age = toWall - existing.birthWall
                if wallGap > 1.08, age >= 1.08 {
                    latchedHits[laneID] = nil
                }
                continue
            }
            let noteChart = schedule.seconds[index]
            guard noteChart > previous.chart, noteChart <= toChart + 1e-9 else {
                if (latchedHits[laneID]?.index ?? -1) < index {
                    latchedHits[laneID] = nil
                }
                continue
            }
            let birth: Double
            if span > 1e-12 {
                let t = min(max((noteChart - previous.chart) / span, 0), 1)
                birth = previous.wall + t * wallGap
            } else {
                birth = toWall
            }
            let age = toWall - birth
            if age < -0.002 { continue }
            let isLong = schedule.isLong.indices.contains(index) && schedule.isLong[index]
            if !isLong {
                if age >= 1.08 {
                    latchedHits[laneID] = nil
                    notePlayerArrival(schedule.player, birthWall: birth)
                    continue
                }
                storeLatch(laneID: laneID, index: index, birthWall: birth, schedule: schedule)
                continue
            }
            let endChart = schedule.endSeconds.indices.contains(index)
                ? schedule.endSeconds[index]
                : schedule.seconds[index]
            let stillHolding = toChart < endChart
            let tailAge: Double?
            if toChart + 1e-9 >= endChart {
                tailAge = toWall - interpolatedBirth(
                    noteChart: endChart,
                    previous: previous,
                    toChart: toChart,
                    toWall: toWall
                )
            } else {
                tailAge = nil
            }
            let tailFresh = tailAge.map {
                PreviewUbmStyle.effectMilliseconds($0) < PreviewUbmStyle.bombClearMilliseconds
            } ?? false
            if stillHolding || tailFresh {
                storeLatch(laneID: laneID, index: index, birthWall: birth, schedule: schedule)
            } else {
                latchedHits[laneID] = nil
                notePlayerArrival(schedule.player, birthWall: birth)
            }
        }
    }

    private func storeLatch(laneID: String, index: Int, birthWall: Double, schedule: PreviewPlayfieldLaneSchedule) {
        let endChart = schedule.endSeconds.indices.contains(index) ? schedule.endSeconds[index] : schedule.seconds[index]
        latchedHits[laneID] = PreviewPlayfieldLatchedHit(
            index: index,
            birthWall: birthWall,
            isLong: schedule.isLong[index],
            endChart: endChart,
            tailBirthWall: nil
        )
        notePlayerArrival(schedule.player, birthWall: birthWall)
    }

    /// 谱面秒跨过长音结尾时记一次尾音墙钟。已经记下的不再改。
    private func advanceTails(previous: PreviewPlayfieldClockSample?, chart: Double, wall: Double) {
        for (laneID, var latch) in latchedHits where latch.isLong && latch.tailBirthWall == nil {
            guard chart + 1e-9 >= latch.endChart else { continue }
            let birth: Double
            if let previous {
                birth = interpolatedBirth(
                    noteChart: latch.endChart,
                    previous: previous,
                    toChart: chart,
                    toWall: wall
                )
            } else {
                birth = wall - (chart - latch.endChart)
            }
            latch.tailBirthWall = birth
            latchedHits[laneID] = latch
        }
    }

    /// 过尾且尾龄满 120 ms 就清该轨道。不等别的轨道。
    private func expireFinishedTails(wall: Double) {
        for (laneID, latch) in latchedHits {
            guard latch.isLong, let tailBirth = latch.tailBirthWall else { continue }
            if PreviewUbmStyle.effectMilliseconds(wall - tailBirth) >= PreviewUbmStyle.bombClearMilliseconds {
                latchedHits[laneID] = nil
            }
        }
    }

    private func interpolatedBirth(
        noteChart: Double,
        previous: PreviewPlayfieldClockSample,
        toChart: Double,
        toWall: Double
    ) -> Double {
        let span = toChart - previous.chart
        let wallGap = toWall - previous.wall
        if noteChart > previous.chart + 1e-12, span > 1e-12 {
            let t = min(max((noteChart - previous.chart) / span, 0), 1)
            return previous.wall + t * wallGap
        }
        return previous.wall - (previous.chart - noteChart)
    }

    private func notePlayerArrival(_ player: Int, birthWall: Double) {
        guard player == 1 || player == 2 else { return }
        if let existing = playerBirthWall[player], existing > birthWall + 1e-9 { return }
        playerBirthWall[player] = birthWall
    }

    private func rebuildHitSchedules() {
        let originTime = timingOrigin.isFinite ? timeIndex.time(at: timingOrigin) : 0
        var playerByLane: [String: Int] = [:]
        playerByLane.reserveCapacity(chart.lanes.count)
        for lane in chart.lanes where playerByLane[lane.id] == nil {
            playerByLane[lane.id] = lane.player
        }
        var grouped: [String: [(seconds: Double, endSeconds: Double, isLong: Bool)]] = [:]
        for note in chart.notes {
            let seconds: Double
            let endSeconds: Double
            if note.startBeat.isFinite, timingOrigin.isFinite {
                seconds = timeIndex.time(at: note.startBeat) - originTime
                let endBeat = note.endBeat.isFinite ? note.endBeat : note.startBeat
                endSeconds = timeIndex.time(at: endBeat) - originTime
            } else {
                seconds = 0
                endSeconds = 0
            }
            let isLong = note.endBeat - note.startBeat > 0.000_001
            grouped[note.laneID, default: []].append((seconds, endSeconds, isLong))
        }
        var schedules: [String: PreviewPlayfieldLaneSchedule] = [:]
        for (laneID, hits) in grouped {
            let ordered = hits.sorted { $0.seconds < $1.seconds }
            schedules[laneID] = PreviewPlayfieldLaneSchedule(
                seconds: ordered.map(\.seconds),
                endSeconds: ordered.map(\.endSeconds),
                isLong: ordered.map(\.isLong),
                player: playerByLane[laneID] ?? 0
            )
        }
        hitSchedules = schedules
    }

    /// 原版 SkinType / 效果位。331 视图始终并排；`autoSeparate` 只留给 587 宿主，不把列推到 15/429。
    func setUbmAppearance(scratchRaw: Int, effectsRaw: Int, autoSeparate: Bool) {
        self.scratchRaw = PreviewUbmStyle.clampedScratch(scratchRaw)
        self.effectsRaw = PreviewUbmStyle.clampedEffects(effectsRaw)
        self.autoSeparate = autoSeparate
        rebuildGeometry()
    }

    func renderMetalReadback() -> PreviewPlayfieldMetalReadback {
        _ = rebuildGeometry()
        guard let session, gpuStatus == .ready else {
            lastOffscreenWaitSeconds = 0
            return PreviewPlayfieldMetalReadback(
                width: 0,
                height: 0,
                bytesPerRow: 0,
                bgra: Data(),
                status: gpuStatus,
                usedMetal: false,
                offscreenWaitSeconds: 0,
                failure: gpuStatus.unavailableReason
            )
        }
        let width = max(Int(bounds.width.rounded()), 1)
        let height = max(Int(bounds.height.rounded()), 1)
        let readback = session.renderOffscreen(
            width: width,
            height: height,
            clear: PreviewPlayfieldPalette.metalClearColor()
        )
        lastOffscreenWaitSeconds = readback.offscreenWaitSeconds
        return readback
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        guard didInstall, changed else { return }
        metalView.frame = bounds
        overlay.frame = bounds
        let scene = rebuildGeometry()
        updateText(scene: scene)
    }

    override func layout() {
        super.layout()
        guard didInstall else { return }
        let sizeChanged = overlay.frame.size != bounds.size
        metalView.frame = bounds
        overlay.frame = bounds
        guard sizeChanged else { return }
        let scene = rebuildGeometry()
        updateText(scene: scene)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard didInstall else { return }
        holdExternalClock()
        let scale = window?.backingScaleFactor ?? overlay.layer?.contentsScale ?? 2
        overlay.layer?.contentsScale = scale
        messageLayer.contentsScale = scale
        for title in titleLayers {
            title.contentsScale = scale
        }
    }

    @discardableResult
    private func rebuildGeometry(displays: Bool = true) -> PreviewPlayfieldScene {
        geometryBuildCount += 1
        let started = DispatchTime.now().uptimeNanoseconds
        let scene = currentScene()
        let selected = DispatchTime.now().uptimeNanoseconds
        session?.cpuVertices = Self.metalVertices(for: scene, in: bounds)
        let finished = DispatchTime.now().uptimeNanoseconds
        lastVisibleSelectSeconds = Double(selected &- started) / 1_000_000_000
        lastVertexAssemblySeconds = Double(finished &- selected) / 1_000_000_000
        lastGeometryBuildSeconds = Double(finished &- started) / 1_000_000_000
        lastVisibleNoteCount = scene.visibleNoteCount
        if displays, gpuStatus == .ready {
            metalView?.needsDisplay = true
        }
        return scene
    }

    private func install() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        metalView = PreviewPlayfieldSurface(frame: bounds, device: gpuStatus == .ready ? session?.device : nil)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = PreviewPlayfieldPalette.metalClearColor()
        metalView.framebufferOnly = true
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.delegate = session
        metalView.setAccessibilityElement(false)
        metalView.isHidden = gpuStatus != .ready
        overlay = PreviewPlayfieldTextOverlay(frame: bounds)
        overlay.wantsLayer = true
        overlay.layerContentsRedrawPolicy = .never
        overlay.layer?.backgroundColor = gpuStatus == .ready
            ? NSColor.clear.cgColor
            : PreviewPlayfieldPalette.background.cgColor
        overlay.layer?.isOpaque = gpuStatus != .ready
        overlay.setAccessibilityElement(false)
        messageLayer.alignmentMode = .center
        messageLayer.font = NSFont.systemFont(ofSize: 16)
        messageLayer.fontSize = 16
        messageLayer.foregroundColor = PreviewPlayfieldPalette.emptyText.cgColor
        messageLayer.contentsScale = 2
        messageLayer.isWrapped = true
        overlay.layer?.addSublayer(messageLayer)
        didInstall = true
        holdExternalClock()
        addSubview(metalView)
        addSubview(overlay)
        let scene = rebuildGeometry()
        updateText(scene: scene)
    }

    private func holdExternalClock() {
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
    }

    private func updateText(scene: PreviewPlayfieldScene) {
        guard didInstall, let host = overlay.layer else { return }
        let scale = window?.backingScaleFactor ?? host.contentsScale
        host.contentsScale = scale
        let titles: [PreviewPlayfieldLaneFrame] = []
        while titleLayers.count < titles.count {
            let text = CATextLayer()
            text.alignmentMode = .center
            text.truncationMode = .end
            text.isWrapped = false
            text.font = NSFont.systemFont(ofSize: 9)
            text.fontSize = 9
            text.foregroundColor = PreviewPlayfieldPalette.label.cgColor
            text.contentsScale = scale
            host.addSublayer(text)
            titleLayers.append(text)
        }
        for (index, lane) in titles.enumerated() {
            let text = titleLayers[index]
            text.string = lane.title
            text.frame = CGRect(x: lane.rect.minX, y: bounds.height - 16, width: lane.rect.width, height: 12)
            text.contentsScale = scale
            text.isHidden = false
        }
        if titleLayers.count > titles.count {
            for text in titleLayers[titles.count...] {
                text.isHidden = true
            }
        }
        laneTitleFrames = titles.map { lane in
            CGRect(x: lane.rect.minX, y: bounds.height - 16, width: lane.rect.width, height: 12)
        }
        let message = gpuStatus.unavailableReason ?? scene.emptyMessage
        displayedOverlayMessage = message
        messageLayer.string = message
        messageLayer.isHidden = message == nil
        messageLayer.contentsScale = scale
        messageLayer.frame = CGRect(x: 12, y: bounds.midY - 18, width: max(bounds.width - 24, 1), height: 36)
        textOverlayRevision += 1
    }

    /// DrawBomb 循环下标。51–59 / 61–69 与 11–19 / 21–29 同内部号。未知通道不进 9..26。
    private static func bombInternalIndex(_ channel: Int) -> Int {
        let aligned: Int
        switch channel {
        case 51...59, 61...69:
            aligned = channel - 40
        default:
            aligned = channel
        }
        switch aligned {
        case 11...15:
            return 9 + (aligned - 11)
        case 18, 19:
            return 14 + (aligned - 18)
        case 16:
            return 17
        case 21...25:
            return 18 + (aligned - 21)
        case 28, 29:
            return 23 + (aligned - 28)
        case 26:
            return 26
        default:
            return 1000 + min(max(channel, 0), 999)
        }
    }

    private static func visibleBombSprite(for hit: PreviewPlayfieldHit) -> PreviewUbmStyle.Sprite? {
        if hit.isLong, hit.tailAgeMilliseconds == nil {
            return PreviewUbmStyle.longNoteBombSprite(frame: PreviewUbmStyle.bombFrame(ageMilliseconds: hit.ageMilliseconds))
        }
        if let tailAge = hit.tailAgeMilliseconds,
           tailAge >= 0,
           tailAge < PreviewUbmStyle.bombClearMilliseconds {
            return PreviewUbmStyle.judgmentBombSprite(frame: PreviewUbmStyle.bombFrame(ageMilliseconds: tailAge))
        }
        if !hit.isLong, PreviewUbmStyle.bombVisible(ageMilliseconds: hit.ageMilliseconds, isLong: false) {
            return PreviewUbmStyle.judgmentBombSprite(frame: PreviewUbmStyle.bombFrame(ageMilliseconds: hit.ageMilliseconds))
        }
        return nil
    }

    private static func metalVertices(for scene: PreviewPlayfieldScene, in viewport: CGRect) -> [PreviewPlayfieldVertex] {
        guard viewport.width > 1, viewport.height > 1 else { return [] }
        var vertices: [PreviewPlayfieldVertex] = []
        let reserve = (scene.lanes.count + scene.marks.count + scene.hits.count + scene.measureLineYs.count + scene.beatLineYs.count + 8) * 6
        vertices.reserveCapacity(reserve)
        let placement = scene.placement
        let scale = placement.scale > 0 ? placement.scale : 1
        let noteField = CGRect(
            x: placement.contentRect.minX,
            y: placement.contentRect.minY,
            width: placement.contentRect.width,
            height: max(scene.judgmentY - placement.contentRect.minY, 0)
        )
        func addSolid(_ rect: CGRect, _ color: NSColor, alpha: CGFloat = 1) {
            guard let clipped = clip(rect, to: viewport) else { return }
            vertices.append(contentsOf: quad(
                clipped,
                color: color,
                alpha: alpha,
                viewport: viewport,
                uv: CGRect(x: 0, y: 0, width: 1, height: 1),
                slot: 4
            ))
        }
        func addSprite(_ rect: CGRect, _ sprite: PreviewUbmStyle.Sprite, alpha: CGFloat, limit: CGRect?) {
            let limited = limit.map { rect.intersection($0) } ?? rect
            guard let clipped = clip(limited, to: viewport) else { return }
            let uv = spriteUV(sprite, full: rect, visible: clipped)
            vertices.append(contentsOf: quad(
                clipped,
                color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                alpha: alpha,
                viewport: viewport,
                uv: uv,
                slot: Float(sprite.texture)
            ))
        }
        if scene.usesSkin, !scene.lanes.isEmpty, placement.contentRect.width > 1, placement.contentRect.height > 1 {
            addSprite(
                placement.contentRect,
                PreviewUbmStyle.Sprite(rect: CGRect(origin: .zero, size: PreviewUbmStyle.playfieldSize), texture: 0),
                alpha: 1,
                limit: nil
            )
            if !PreviewUbmStyle.backgroundIsIdentity(scratchRaw: scene.scratchRaw, autoSeparate: scene.autoSeparate) {
                for panel in PreviewUbmStyle.backgroundPanels(scratchRaw: scene.scratchRaw, autoSeparate: scene.autoSeparate) {
                    let native = CGRect(x: panel.destX, y: 0, width: panel.width, height: PreviewUbmStyle.playfieldSize.height)
                    addSprite(
                        placement.viewRect(native),
                        PreviewUbmStyle.Sprite(
                            rect: CGRect(x: panel.sourceX, y: 0, width: panel.width, height: PreviewUbmStyle.playfieldSize.height),
                            texture: 0
                        ),
                        alpha: 1,
                        limit: placement.contentRect
                    )
                }
            }
        } else {
            for lane in scene.lanes {
                addSolid(lane.rect, PreviewPlayfieldPalette.laneColor(lane.kind))
            }
        }
        if placement.contentRect.width > 1 {
            let thickness = max(scale, 1)
            func guide(_ y: CGFloat, _ color: NSColor) {
                let top = (y / scale).rounded(.down) * scale
                let rect = CGRect(x: placement.contentRect.minX, y: top, width: placement.contentRect.width, height: thickness)
                let limited = scene.usesSkin ? rect.intersection(noteField) : rect
                addSolid(limited, color)
            }
            for y in scene.beatLineYs {
                guide(y, NSColor(srgbRed: 0.35, green: 0.35, blue: 0.38, alpha: 1))
            }
            for y in scene.measureLineYs {
                guide(y, NSColor(srgbRed: 0.82, green: 0.84, blue: 0.88, alpha: 1))
            }
        }
        if scene.usesSkin {
            for hit in scene.hits where PreviewUbmStyle.laneGlowVisible(
                ageMilliseconds: hit.ageMilliseconds,
                isLong: hit.isLong,
                tailAgeMilliseconds: hit.tailAgeMilliseconds
            ) {
                let beam = CGRect(
                    x: hit.column.minX,
                    y: placement.contentRect.minY,
                    width: hit.column.width,
                    height: max(scene.judgmentY - placement.contentRect.minY, 0)
                )
                addSprite(beam, PreviewUbmStyle.beamSprite(kind: hit.kind), alpha: scene.beamVertexAlpha, limit: noteField)
            }
        }
        let shortFrame = PreviewUbmStyle.shortFrame(playbackBeat: scene.playbackBeat)
        let longFrame = PreviewUbmStyle.longFrame(playbackBeat: scene.playbackBeat)
        let markLimit = scene.usesSkin ? noteField : nil
        for mark in scene.marks where mark.part == .body {
            if scene.usesSkin {
                addSprite(mark.rect, PreviewUbmStyle.noteSprite(kind: mark.kind, part: .body, frame: longFrame), alpha: 1, limit: markLimit)
            } else {
                addSolid(mark.rect, PreviewPlayfieldPalette.noteColor(mark.kind), alpha: 0.72)
            }
        }
        for mark in scene.marks where mark.part != .body {
            let frame = mark.part == .short ? shortFrame : longFrame
            if scene.usesSkin {
                addSprite(mark.rect, PreviewUbmStyle.noteSprite(kind: mark.kind, part: mark.part, frame: frame), alpha: 1, limit: markLimit)
            } else {
                addSolid(mark.rect, PreviewPlayfieldPalette.noteColor(mark.kind))
            }
        }
        if scene.usesSkin {
            if PreviewUbmStyle.showsKeyCap(scene.effectsRaw) {
                for hit in scene.hits {
                    guard PreviewUbmStyle.laneGlowVisible(
                        ageMilliseconds: hit.ageMilliseconds,
                        isLong: hit.isLong,
                        tailAgeMilliseconds: hit.tailAgeMilliseconds
                    ) else { continue }
                    let cap = PreviewUbmStyle.keyCapSprite(kind: hit.kind)
                    let capX = hit.column.minX + PreviewUbmStyle.keyCapXOffset(channel: hit.channel, scratchRaw: scene.scratchRaw) * scale
                    let capRect = CGRect(
                        x: capX,
                        y: placement.origin.y + PreviewUbmStyle.keyCapNativeY(kind: hit.kind) * scale,
                        width: cap.rect.width * scale,
                        height: cap.rect.height * scale
                    )
                    addSprite(capRect, cap, alpha: 1, limit: placement.contentRect)
                }
            }
            if PreviewUbmStyle.showsBomb(scene.effectsRaw) {
                var pending: [(hit: PreviewPlayfieldHit, sprite: PreviewUbmStyle.Sprite)] = []
                pending.reserveCapacity(min(scene.hits.count, 32))
                for hit in scene.hits {
                    guard pending.count < 32, let sprite = visibleBombSprite(for: hit) else { continue }
                    pending.append((hit, sprite))
                }
                let ranked = pending.enumerated().sorted { lhs, rhs in
                    let left = bombInternalIndex(lhs.element.hit.channel)
                    let right = bombInternalIndex(rhs.element.hit.channel)
                    if left != right { return left < right }
                    if lhs.element.hit.laneID != rhs.element.hit.laneID {
                        return lhs.element.hit.laneID < rhs.element.hit.laneID
                    }
                    return lhs.offset < rhs.offset
                }
                for item in ranked {
                    let hit = item.element.hit
                    let bomb = item.element.sprite
                    let bombSide = bomb.rect.width * scale
                    let centerX = hit.column.minX + (hit.kind == .scratch ? 16 : 8) * scale
                    let burst = CGRect(
                        x: centerX - bombSide / 2,
                        y: placement.origin.y + 224 * scale - bombSide / 2,
                        width: bombSide,
                        height: bombSide
                    )
                    addSprite(burst, bomb, alpha: 1, limit: placement.contentRect)
                }
            }
            if PreviewUbmStyle.showsJudgment(scene.effectsRaw) {
                let wallMilliseconds = PreviewUbmStyle.effectMilliseconds(scene.elapsedSeconds)
                let digitFrame = PreviewUbmStyle.greatFrame(elapsedSeconds: scene.elapsedSeconds)
                for judge in scene.sideJudges where PreviewUbmStyle.judgmentVisible(ageMilliseconds: judge.ageMilliseconds) {
                    let zoom = PreviewUbmStyle.greatZoom(ageMilliseconds: judge.ageMilliseconds)
                    let great = PreviewUbmStyle.greatSprite(frame: digitFrame)
                    let greatX = PreviewUbmStyle.greatNativeX(combo: judge.combo, sideOrigin: judge.originX)
                    let greatRect = CGRect(
                        x: placement.origin.x + greatX * scale,
                        y: placement.origin.y + CGFloat(zoom.y) * scale,
                        width: great.rect.width * scale,
                        height: CGFloat(zoom.height) * scale
                    )
                    addSprite(greatRect, great, alpha: 1, limit: placement.contentRect)
                    guard judge.combo > 0 else { continue }
                    let digits = Array(String(min(judge.combo, 999_999)))
                    let greatPixelX = Int(greatX)
                    for (offset, character) in digits.enumerated() {
                        let index = offset + 1
                        let value = Int(String(character)) ?? 0
                        let digitZoom = PreviewUbmStyle.digitZoom(
                            ageMilliseconds: judge.ageMilliseconds,
                            index: index,
                            wallMilliseconds: wallMilliseconds
                        )
                        let sprite = PreviewUbmStyle.digitSprite(value, frame: digitFrame)
                        let rect = CGRect(
                            x: placement.origin.x + CGFloat(PreviewUbmStyle.digitNativeX(greatX: greatPixelX, index: index)) * scale,
                            y: placement.origin.y + CGFloat(digitZoom.y) * scale,
                            width: 15 * scale,
                            height: CGFloat(digitZoom.height) * scale
                        )
                        addSprite(rect, sprite, alpha: 1, limit: placement.contentRect)
                    }
                }
            }
        } else if let span = playfieldSpan(scene.lanes) {
            addSolid(
                CGRect(x: span.minX, y: scene.judgmentY - 1, width: span.width, height: 2),
                PreviewPlayfieldPalette.judgment
            )
        }
        return vertices
    }

    private static func textureSize(for slot: Int) -> CGSize {
        switch slot {
        case 0: PreviewUbmStyle.playfieldSize
        case 1: CGSize(width: 137, height: 221)
        case 2: CGSize(width: 160, height: 244)
        case 3: CGSize(width: 578, height: 228)
        default: CGSize(width: 1, height: 1)
        }
    }

    private static func spriteUV(_ sprite: PreviewUbmStyle.Sprite, full: CGRect, visible: CGRect) -> CGRect {
        let texture = textureSize(for: sprite.texture)
        let u0 = sprite.rect.minX / texture.width
        let v0 = sprite.rect.minY / texture.height
        let uSpan = sprite.rect.width / max(texture.width, 1)
        let vSpan = sprite.rect.height / max(texture.height, 1)
        guard full.width > 0.001, full.height > 0.001 else {
            return CGRect(x: u0, y: v0, width: uSpan, height: vSpan)
        }
        let left = (visible.minX - full.minX) / full.width
        let top = (visible.minY - full.minY) / full.height
        let width = visible.width / full.width
        let height = visible.height / full.height
        return CGRect(x: u0 + left * uSpan, y: v0 + top * vSpan, width: width * uSpan, height: height * vSpan)
    }

    private static func playfieldSpan(_ lanes: [PreviewPlayfieldLaneFrame]) -> CGRect? {
        guard let minX = lanes.map(\.rect.minX).min(),
              let maxX = lanes.map(\.rect.maxX).max(),
              maxX - minX >= 1 else { return nil }
        return CGRect(x: minX, y: 0, width: maxX - minX, height: 0)
    }

    private static func clip(_ rect: CGRect, to viewport: CGRect) -> CGRect? {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite else { return nil }
        let clipped = rect.intersection(viewport.insetBy(dx: -1, dy: -1))
        guard !clipped.isNull, !clipped.isInfinite, clipped.width >= 0.5, clipped.height >= 0.5 else { return nil }
        return clipped
    }

    private static func quad(
        _ rect: CGRect,
        color: NSColor,
        alpha: CGFloat,
        viewport: CGRect,
        uv: CGRect,
        slot: Float
    ) -> [PreviewPlayfieldVertex] {
        let rgba = color.usingColorSpace(.sRGB) ?? color
        let red = Float(rgba.redComponent)
        let green = Float(rgba.greenComponent)
        let blue = Float(rgba.blueComponent)
        let opacity = Float(min(max(rgba.alphaComponent * alpha, 0), 1))
        let left = Float((rect.minX - viewport.minX) / viewport.width * 2 - 1)
        let right = Float((rect.maxX - viewport.minX) / viewport.width * 2 - 1)
        let top = Float(1 - (rect.minY - viewport.minY) / viewport.height * 2)
        let bottom = Float(1 - (rect.maxY - viewport.minY) / viewport.height * 2)
        let leftU = Float(uv.minX)
        let rightU = Float(uv.maxX)
        let topV = Float(uv.minY)
        let bottomV = Float(uv.maxY)
        func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) -> PreviewPlayfieldVertex {
            PreviewPlayfieldVertex(x: x, y: y, u: u, v: v, r: red, g: green, b: blue, a: opacity, slot: slot)
        }
        return [
            vertex(left, top, leftU, topV),
            vertex(right, top, rightU, topV),
            vertex(right, bottom, rightU, bottomV),
            vertex(left, top, leftU, topV),
            vertex(right, bottom, rightU, bottomV),
            vertex(left, bottom, leftU, bottomV)
        ]
    }
}
