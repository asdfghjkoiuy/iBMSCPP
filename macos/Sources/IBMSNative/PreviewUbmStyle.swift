import AppKit
import CoreText
import ImageIO

/// uBMplay 1.5.2 默认皮肤的几何和切片。坐标来自本机 `skin_00/01/02/03` 与 `font.png` 的像素测量。
/// 常量不绑在主线程上。文本栅格化单独标成主线程，供预览窗按同一套字形出图。
enum PreviewUbmStyle {
    static let canvasSize = CGSize(width: 587, height: 256)
    static let playfieldSize = CGSize(width: 331, height: 256)
    static let bgaSize = CGSize(width: 256, height: 256)

    /// 判定线第一行。skin_00 的 y=219…223 是绿渐变，音符前沿落在 219。
    static let judgmentTop: CGFloat = 219
    /// 底部立体键从这一行开始，音符不盖住它。
    static let keyTop: CGFloat = 224
    static let noteHeight: CGFloat = 5

    static let missingSkinMessage = "没有找到 uBMplay 皮肤目录"
    static let incompleteSkinMessage = "uBMplay 皮肤图集无法按原尺寸读入"
    static let disabledSkinMessage = "已关闭原版皮肤，使用程序性外观"

    struct Placement: Equatable {
        var origin: CGPoint
        var scale: CGFloat
        var contentRect: CGRect

        func viewRect(_ native: CGRect) -> CGRect {
            CGRect(
                x: origin.x + native.minX * scale,
                y: origin.y + native.minY * scale,
                width: native.width * scale,
                height: native.height * scale
            )
        }
    }

    struct Column: Equatable {
        var kind: PreviewPlayfieldLaneKind
        var player: Int
        var channel: Int
        var rect: CGRect
    }

    struct BackgroundPanel: Equatable {
        var sourceX: CGFloat
        var destX: CGFloat
        var width: CGFloat
    }

    struct Sprite: Equatable {
        var rect: CGRect
        /// 0 背景，1 音符/光束，2 判定字，3 爆炸。
        var texture: Int
    }

    struct AtlasImage {
        var width: Int
        var height: Int
        var rgba: [UInt8]

        func components(x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double)? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let offset = (y * width + x) * 4
            guard offset + 3 < rgba.count else { return nil }
            return (
                Double(rgba[offset]) / 255,
                Double(rgba[offset + 1]) / 255,
                Double(rgba[offset + 2]) / 255,
                Double(rgba[offset + 3]) / 255
            )
        }
    }

    /// 整张 331×256 放进视图，多出来的边留白，不把背景拉变形。
    static func placement(in viewSize: CGSize) -> Placement {
        let native = playfieldSize
        guard viewSize.width > 1, viewSize.height > 1, native.width > 0, native.height > 0 else {
            return Placement(origin: .zero, scale: 1, contentRect: .zero)
        }
        let scale = min(viewSize.width / native.width, viewSize.height / native.height)
        let size = CGSize(width: native.width * scale, height: native.height * scale)
        let origin = CGPoint(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2)
        return Placement(origin: origin, scale: scale, contentRect: CGRect(origin: origin, size: size))
    }

    /// 完整图集目录。这里只返回路径，不读像素。
    /// 顺序是 `IBMS_UBM_SKIN_DIR`，然后 app bundle 的 `UbmplayReference/image`。
    /// 开发测试才编译本机参考包回退。正式 app 不带源码绝对路径。
    static func skinDirectory() -> URL? {
        if let override = ProcessInfo.processInfo.environment["IBMS_UBM_SKIN_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if skinLooksComplete(url) { return url }
        }
        if let bundled = bundledSkinDirectory(), skinLooksComplete(bundled) {
            return bundled
        }
        #if IBMS_PREVIEW_DEV_SKIN_FALLBACK
        if let reference = developmentReferenceSkinDirectory(), skinLooksComplete(reference) {
            return reference
        }
        #endif
        return nil
    }

    /// `Contents/Resources/UbmplayReference/image`。齐不齐由 `skinLooksComplete` 判断。
    private static func bundledSkinDirectory() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return resources
            .appendingPathComponent("UbmplayReference", isDirectory: true)
            .appendingPathComponent("image", isDirectory: true)
    }

    #if IBMS_PREVIEW_DEV_SKIN_FALLBACK
    /// 只有定义了 `IBMS_PREVIEW_DEV_SKIN_FALLBACK` 的测试目标会编译这段。
    private static func developmentReferenceSkinDirectory() -> URL? {
        let source = URL(fileURLWithPath: #filePath)
        let root = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root
            .appendingPathComponent("out", isDirectory: true)
            .appendingPathComponent("reference", isDirectory: true)
            .appendingPathComponent("ubmplay-1.5.2", isDirectory: true)
            .appendingPathComponent("ubmplay", isDirectory: true)
            .appendingPathComponent("image", isDirectory: true)
    }
    #endif

    static func loadAtlas(named name: String, in directory: URL, keying: AtlasKeying = .none) -> AtlasImage? {
        let url = directory.appendingPathComponent(name)
        guard var image = loadRGBA(url) else { return nil }
        image.apply(keying)
        return image
    }

    /// 0…3 是 L/R、R/R、L/L、R/L。再大或负数收进这四态，不另造 SkinType 4。
    static func clampedScratch(_ raw: Int) -> Int {
        min(max(raw, 0), 3)
    }

    /// 只保留 bit0 判定字、bit1 爆炸、bit2 键帽光束。更高的位丢掉，不当成新效果。
    static func clampedEffects(_ raw: Int) -> Int {
        max(raw, 0) & 7
    }

    static func showsJudgment(_ effectsRaw: Int) -> Bool { clampedEffects(effectsRaw) & 1 != 0 }
    static func showsBomb(_ effectsRaw: Int) -> Bool { clampedEffects(effectsRaw) & 2 != 0 }
    static func showsKeyCap(_ effectsRaw: Int) -> Bool { clampedEffects(effectsRaw) & 4 != 0 }

    /// `#PLAYER == 3` 或分侧关闭时都是并排。331 视图只画这一套。分离的 15/429 由 587 宿主排，不塞进这张图。
    static func panelSeed(player: Int, autoSeparate: Bool) -> CGFloat {
        _ = autoSeparate
        return player == 2 ? 173 : 0
    }

    /// bit0 清时 1P 搓盘在左。bit1 置位时 2P 搓盘在左，和 1P 的位方向相反。
    static func scratchOnLeft(player: Int, scratchRaw: Int) -> Bool {
        let state = clampedScratch(scratchRaw)
        if player == 2 { return state & 2 != 0 }
        return state & 1 == 0
    }

    /// 背景是 skin_00 上两块 158 宽。搓盘在左用 x=0，在右用 x=173。目标原点跟面板种子走。
    static func backgroundPanels(scratchRaw: Int, autoSeparate: Bool) -> [BackgroundPanel] {
        let state = clampedScratch(scratchRaw)
        let oneSource: CGFloat = state & 1 == 0 ? 0 : 173
        let twoSource: CGFloat = state & 2 == 0 ? 173 : 0
        return [
            BackgroundPanel(sourceX: oneSource, destX: panelSeed(player: 1, autoSeparate: autoSeparate), width: 158),
            BackgroundPanel(sourceX: twoSource, destX: panelSeed(player: 2, autoSeparate: autoSeparate), width: 158)
        ]
    }

    static func backgroundIsIdentity(scratchRaw: Int, autoSeparate: Bool) -> Bool {
        _ = autoSeparate
        return clampedScratch(scratchRaw) == 0
    }

    /// 槽位按 BMS 通道号。id 本身是通道号时用它，否则按该侧出现顺序套 11…19 / 21…29。
    static func nativeColumns(
        for lanes: [PreviewVisualLane],
        scratchRaw: Int = 0,
        autoSeparate: Bool = true
    ) -> [Column] {
        let state = clampedScratch(scratchRaw)
        var nextKey = [1: 0, 2: 0]
        return lanes.map { lane in
            let player = lane.player == 2 ? 2 : 1
            let order = channelOrder(player: player)
            let channel: Int
            if let parsed = Int(lane.id), knownChannels.contains(parsed), channelPlayer(parsed) == player {
                channel = parsed
            } else if lane.isScratch {
                channel = order.scratch
            } else {
                let index = nextKey[player] ?? 0
                guard index < order.keys.count else {
                    return Column(kind: .white, player: player, channel: 0, rect: .zero)
                }
                channel = order.keys[index]
                nextKey[player] = index + 1
            }
            let kind = kind(for: channel)
            let x = contentX(
                channel: channel,
                seed: panelSeed(player: player, autoSeparate: autoSeparate),
                scratchOnLeft: scratchOnLeft(player: player, scratchRaw: state)
            )
            return Column(
                kind: kind,
                player: player,
                channel: channel,
                rect: CGRect(x: x, y: 0, width: width(for: kind), height: playfieldSize.height)
            )
        }
    }

    /// 播放头 `qword_42E0E8` 是 48 tick/拍，不是每秒 48。普通帧对正数向下取整。
    static let ticksPerBeat = 48.0

    static func playheadTicks(playbackBeat: Double) -> Double {
        guard playbackBeat.isFinite else { return 0 }
        return playbackBeat * ticksPerBeat
    }

    static func shortFrame(playbackBeat: Double) -> Int {
        Int(floor(playheadTicks(playbackBeat: playbackBeat) / 4.8)) & 7
    }

    /// Currency 转整数用 VB 的银行家舍入，再有符号整除 24。
    static func vbI4Currency(_ value: Double) -> Int {
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
        let signed = negative ? -rounded : rounded
        return Int(signed)
    }

    static func longFrame(playbackBeat: Double) -> Int {
        (vbI4Currency(playheadTicks(playbackBeat: playbackBeat)) / 24) & 3
    }

    static func effectMilliseconds(_ elapsedSeconds: Double) -> Int {
        guard elapsedSeconds.isFinite else { return 0 }
        return Int((elapsedSeconds * 1000).rounded(.toNearestOrAwayFromZero))
    }

    /// 410A30 的 256 项 Float32 表。`rtcSin(i * pi / 128)`，pi 用反汇编里的 3.1415926535897。进程内只建一次。
    static let sineTable: [Float] = {
        let pi = 3.1415926535897
        return (0..<256).map { index in
            Float(sin(Double(index) * pi / 128))
        }
    }()

    /// `(degree * 256 / 360)` 银行家舍入后取低 8 位。
    static func sineDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var index = vbI4Currency(degrees * 256 / 360) % 256
        if index < 0 { index += 256 }
        return Double(sineTable[index])
    }

    /// 年龄不到 90 ms 时高 `bank(14+7*s)`、y `bank(161-3.5*s)`。之后高 14、y 161。宽保持 81。
    static func greatZoom(ageMilliseconds: Int) -> (y: Int, height: Int) {
        guard ageMilliseconds < 90 else { return (161, 14) }
        let scale = sineDegrees(Double(ageMilliseconds) + 90)
        return (vbI4Currency(161 - 3.5 * scale), vbI4Currency(14 + 7 * scale))
    }

    /// 轻摆用效果墙钟加 `180*i`，i 从 1。前 90 ms 再按 `bank(sway-7*s)` 和 `bank(14+14*s)` 拉伸。
    static func digitZoom(ageMilliseconds: Int, index: Int, wallMilliseconds: Int) -> (y: Int, height: Int) {
        let swing = sineDegrees(Double(wallMilliseconds) + Double(180 * index))
        let sway = vbI4Currency(161 + swing * (6 - Double(ageMilliseconds) / 180) * 0.5)
        guard ageMilliseconds < 90 else { return (sway, 14) }
        let scale = sineDegrees(Double(ageMilliseconds) + 90)
        return (vbI4Currency(Double(sway) - 7 * scale), vbI4Currency(14 + 14 * scale))
    }

    /// `(毫秒 / 50) mod 5`，全局相位，不是单次判定的年龄。
    static func greatFrame(elapsedSeconds: Double) -> Int {
        let milliseconds = effectMilliseconds(elapsedSeconds)
        let unit = milliseconds >= 0 ? milliseconds : 0
        return (unit / 50) % 5
    }

    static func bombFrame(ageMilliseconds: Int) -> Int {
        let age = max(ageMilliseconds, 0)
        return (age / PreviewUbmStyle.bombFrameMilliseconds) % bombFrameCount
    }

    static let beamLifetimeMilliseconds = 50
    static let bombFrameMilliseconds = 20
    static let bombClearMilliseconds = 120
    static let greatLifetimeMilliseconds = 1080

    static func beamVisible(ageMilliseconds: Int) -> Bool {
        ageMilliseconds >= 0 && ageMilliseconds <= beamLifetimeMilliseconds
    }

    /// 车道亮条和键帽共用 `word_42E1C0`。普通音符超过 50 ms 熄灭。
    /// 长音在尾龄还是 nil 时保持这两层。尾龄一记上就回到头龄的 50 ms，不再因持有续亮。
    /// 反汇编只证明计时差超过 50 ms 会清这只字，没有证明持有期间会重写 `dword_42E1E4`。
    /// 本轮按持续按住的显示目标保持；原版长音持有状态机尚未完全核对，短音仍走50ms。
    static func laneGlowVisible(ageMilliseconds: Int, isLong: Bool, tailAgeMilliseconds: Int?) -> Bool {
        if isLong, tailAgeMilliseconds == nil, ageMilliseconds >= 0 {
            return true
        }
        return beamVisible(ageMilliseconds: ageMilliseconds)
    }

    static func judgmentVisible(ageMilliseconds: Int) -> Bool {
        ageMilliseconds >= 0 && ageMilliseconds < greatLifetimeMilliseconds
    }

    /// 普通槽满 120 ms 清除。长音头那一档到 120 仍留着。
    static func bombVisible(ageMilliseconds: Int, isLong: Bool) -> Bool {
        guard ageMilliseconds >= 0 else { return false }
        if isLong { return true }
        return ageMilliseconds < bombClearMilliseconds
    }

    static func noteSprite(
        kind: PreviewPlayfieldLaneKind,
        part: PreviewPlayfieldNotePart,
        frame: Int = 0
    ) -> Sprite {
        let chip = noteChip(kind)
        let (top, mask) = noteTop(part: part, frame: frame)
        _ = mask
        return Sprite(rect: CGRect(x: chip.x, y: top, width: chip.width, height: noteHeight), texture: 1)
    }

    static func beamSprite(kind: PreviewPlayfieldLaneKind) -> Sprite {
        switch kind {
        case .blue:
            return Sprite(rect: CGRect(x: 1, y: 1, width: 15, height: 219), texture: 1)
        case .white:
            return Sprite(rect: CGRect(x: 17, y: 1, width: 18, height: 219), texture: 1)
        case .scratch:
            return Sprite(rect: CGRect(x: 36, y: 1, width: 32, height: 219), texture: 1)
        }
    }

    /// 键帽上的小光束，不是整条车道，也不是地雷那一排。
    static func keyCapSprite(kind: PreviewPlayfieldLaneKind) -> Sprite {
        switch kind {
        case .white:
            return Sprite(rect: CGRect(x: 69, y: 139, width: 13, height: 20), texture: 1)
        case .blue:
            return Sprite(rect: CGRect(x: 83, y: 139, width: 12, height: 20), texture: 1)
        case .scratch:
            return Sprite(rect: CGRect(x: 96, y: 139, width: 28, height: 28), texture: 1)
        }
    }

    static func keyCapNativeY(kind: PreviewPlayfieldLaneKind) -> CGFloat {
        switch kind {
        case .white: 233
        case .blue: 227
        case .scratch: 226
        }
    }

    /// 23/24/25/28/29 固定用 1P 附加量。21/22 才跟 2P 搓盘方向。搓盘自身 +2。
    static func keyCapXOffset(channel: Int, scratchRaw: Int) -> CGFloat {
        let state = clampedScratch(scratchRaw)
        let oneLeft = state & 1 == 0
        let twoLeft = state & 2 != 0
        let followsTwo = channel == 21 || channel == 22
        let scratchLeft = followsTwo ? twoLeft : oneLeft
        switch kind(for: channel) {
        case .scratch: return 2
        case .white: return scratchLeft ? 3 : 2
        case .blue: return scratchLeft ? 2 : 1
        }
    }

    static let bombFrameCount = 6

    /// 长音头。下行 y=163，边长 64。持有期间不按 120 ms 清除。
    static func longNoteBombSprite(frame: Int) -> Sprite {
        let index = min(max(frame, 0), bombFrameCount - 1)
        let side: CGFloat = 64
        return Sprite(
            rect: CGRect(x: 1 + CGFloat(index) * side, y: 163, width: side, height: side),
            texture: 3
        )
    }

    /// 第一判档和长音尾。中行 y=66，边长 96，x=1+frame*96。满 120 ms 清除。
    static func judgmentBombSprite(frame: Int) -> Sprite {
        let index = min(max(frame, 0), bombFrameCount - 1)
        let side: CGFloat = 96
        return Sprite(
            rect: CGRect(x: 1 + CGFloat(index) * side, y: 66, width: side, height: side),
            texture: 3
        )
    }

    static func greatSprite(frame: Int = 0) -> Sprite {
        let index = min(max(frame, 0), 4)
        return Sprite(rect: CGRect(x: 9, y: 106 + CGFloat(index) * 15, width: 81, height: 14), texture: 2)
    }

    static func digitSprite(_ digit: Int, frame: Int = 0) -> Sprite {
        let clamped = min(max(digit, 0), 9)
        let index = min(max(frame, 0), 4)
        return Sprite(
            rect: CGRect(x: 9 + CGFloat(clamped) * 15, y: 1 + CGFloat(index) * 15, width: 15, height: 14),
            texture: 2
        )
    }

    /// ASCII 判定字在 587 宽里的左边缘。汇编是 `(587 - 8 * 字符数) / 2`。非 ASCII 不要套这个 8。
    static func centeredAsciiOriginX(characterCount: Int, canvasWidth: CGFloat = canvasSize.width) -> CGFloat {
        (canvasWidth - CGFloat(max(characterCount, 0)) * 8) / 2
    }

    /// 4164A3/4164B3 是整数除法。一位数是 side+28，没有数字时是 side+35。
    static func greatNativeX(combo: Int, sideOrigin: CGFloat) -> CGFloat {
        let side = Int(sideOrigin)
        guard combo > 0 else { return CGFloat(side + 35) }
        let digits = String(min(combo, 999_999)).count
        let halfSpan = (digits * 15 + 88) / 2
        return CGFloat(side + 119 - 40 - halfSpan)
    }

    /// 41661B 的基线是 GREAT 右缘减 7。41687F 再加 `15*i`，i 从 1，首位在右缘加 8。
    static func digitNativeX(greatX: Int, index: Int) -> Int {
        greatX + 81 - 7 + 15 * index
    }

    static let greatNativeY: CGFloat = 161
    static let digitStep: CGFloat = 15

    /// 传这个颜色时保留 `font.png` 的青蓝渐变。其它颜色按像素亮度着色，不作为默认。
    static let originalFontColor = NSColor(srgbRed: 112.0 / 255.0, green: 186.0 / 255.0, blue: 254.0 / 255.0, alpha: 1)

    /// 原版点阵一次拆开后缓存。默认颜色保留图集 RGB。不能读的字符用等宽字体，中文不会被丢掉。
    @MainActor
    static func textImage(_ text: String, color: NSColor = originalFontColor) -> CGImage? {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return nil }
        let limited = scalars.count > 240 ? Array(scalars.prefix(240)) : scalars
        let rgba = (color.usingColorSpace(.sRGB) ?? color)
        let key = TextCacheKey(
            text: String(String.UnicodeScalarView(limited)),
            red: rgba.redComponent,
            green: rgba.greenComponent,
            blue: rgba.blueComponent,
            alpha: rgba.alphaComponent
        )
        if let cached = textCache[key] { return cached }
        let masks = glyphMasks()
        let red = Double(rgba.redComponent)
        let green = Double(rgba.greenComponent)
        let blue = Double(rgba.blueComponent)
        let tintAlpha = Double(rgba.alphaComponent)
        let keepFontRGB = preservesFontRGB(rgba)
        let lines = splitLines(limited)
        let lineHeight = 12
        var width = 1
        for line in lines {
            width = max(width, lineWidth(line, masks: masks, color: rgba))
        }
        let height = max(lineHeight * lines.count, 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var cursorY = 0
        for line in lines {
            var cursorX = 0
            for scalar in line {
                if let mask = masks[scalar.value] {
                    blit(
                        mask,
                        at: cursorX,
                        baseline: cursorY + lineHeight,
                        into: &pixels,
                        width: width,
                        height: height,
                        red: red,
                        green: green,
                        blue: blue,
                        alpha: tintAlpha,
                        keepSourceRGB: mask.keepsSourceRGB && keepFontRGB
                    )
                    cursorX += mask.advance
                } else {
                    let drawn = fallbackGlyph(scalar, color: rgba, lineHeight: lineHeight)
                    blit(
                        drawn,
                        at: cursorX,
                        baseline: cursorY + lineHeight,
                        into: &pixels,
                        width: width,
                        height: height,
                        red: red,
                        green: green,
                        blue: blue,
                        alpha: tintAlpha,
                        keepSourceRGB: true
                    )
                    cursorX += drawn.advance
                }
            }
            cursorY += lineHeight
        }
        guard let image = makeImage(pixels, width: width, height: height) else { return nil }
        if textCache.count > 48 {
            textCache.removeAll(keepingCapacity: true)
        }
        textCache[key] = image
        return image
    }

    struct AtlasKeying: OptionSet {
        var rawValue: Int
        static let green = AtlasKeying(rawValue: 1)
        static let black = AtlasKeying(rawValue: 2)
        static let pink = AtlasKeying(rawValue: 4)
        static let noteSheets: AtlasKeying = [.green, .black]
        static let bombSheet: AtlasKeying = [.pink, .black]
        static let none: AtlasKeying = []
    }

    private static let knownChannels: Set<Int> = [11, 12, 13, 14, 15, 16, 18, 19, 21, 22, 23, 24, 25, 26, 28, 29]

    private static func channelPlayer(_ channel: Int) -> Int {
        channel >= 21 ? 2 : 1
    }

    private static func channelOrder(player: Int) -> (scratch: Int, keys: [Int]) {
        if player == 2 { return (26, [21, 22, 23, 24, 25, 28, 29]) }
        return (16, [11, 12, 13, 14, 15, 18, 19])
    }

    private static func kind(for channel: Int) -> PreviewPlayfieldLaneKind {
        switch channel {
        case 16, 26: return .scratch
        case 12, 14, 18, 22, 24, 28: return .blue
        default: return .white
        }
    }

    private static func width(for kind: PreviewPlayfieldLaneKind) -> CGFloat {
        switch kind {
        case .scratch: 32
        case .white: 18
        case .blue: 15
        }
    }

    /// 相对面板种子。搓盘在左：+1 / +34 / +53，之后列距 35。在右：键从 +1、+20 起，搓盘在 +125。
    private static func contentX(channel: Int, seed: CGFloat, scratchOnLeft: Bool) -> CGFloat {
        let delta: CGFloat
        if scratchOnLeft {
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

    private struct Chip {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
    }

    /// skin_01 右侧第一帧。白 18、蓝 15、皿 32，高 5，和车道内容同宽。
    private static func noteChip(_ kind: PreviewPlayfieldLaneKind) -> Chip {
        switch kind {
        case .white:
            return Chip(x: 69, y: 1, width: 18)
        case .blue:
            return Chip(x: 88, y: 1, width: 15)
        case .scratch:
            return Chip(x: 104, y: 1, width: 32)
        }
    }

    private static func noteTop(part: PreviewPlayfieldNotePart, frame: Int) -> (CGFloat, Int) {
        switch part {
        case .short:
            return (1 + CGFloat(frame & 7) * 6, 8)
        case .head:
            return (97 + CGFloat(frame & 3) * 6, 4)
        case .body:
            return (73 + CGFloat(frame & 3) * 6, 4)
        case .tail:
            return (49 + CGFloat(frame & 3) * 6, 4)
        }
    }

    /// 必须是目录，且五张原图都是普通文件。缺一张就当这处没有皮肤。
    private static func skinLooksComplete(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let names = ["skin_00.png", "skin_01.png", "skin_02.png", "skin_03.png", "font.png"]
        return names.allSatisfy { name in
            let file = url.appendingPathComponent(name)
            var fileIsDirectory = ObjCBool(false)
            return manager.fileExists(atPath: file.path, isDirectory: &fileIsDirectory) && !fileIsDirectory.boolValue
        }
    }

    private static func loadRGBA(_ url: URL) -> AtlasImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
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
        return AtlasImage(width: width, height: height, rgba: rgba)
    }
}

private extension PreviewUbmStyle.AtlasImage {
    mutating func apply(_ keying: PreviewUbmStyle.AtlasKeying) {
        guard !keying.isEmpty else { return }
        var index = 0
        while index + 3 < rgba.count {
            let red = rgba[index]
            let green = rgba[index + 1]
            let blue = rgba[index + 2]
            let dropGreen = keying.contains(.green) && red == 0 && green == 255 && blue == 0
            let dropBlack = keying.contains(.black) && red == 0 && green == 0 && blue == 0
            let dropPink = keying.contains(.pink) && red == 199 && green == 80 && blue == 127
            if dropGreen || dropBlack || dropPink {
                rgba[index] = 0
                rgba[index + 1] = 0
                rgba[index + 2] = 0
                rgba[index + 3] = 0
            }
            index += 4
        }
    }
}

private struct PreviewUbmGlyphMask {
    var width: Int
    var height: Int
    var advance: Int
    var baseline: Int
    /// 直通 RGBA。字体图集保留原色；fallback 已经是请求的颜色。
    var rgba: [UInt8]
    var keepsSourceRGB: Bool
}

private struct TextCacheKey: Hashable {
    var text: String
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
}

private struct FallbackGlyphKey: Hashable {
    var value: UInt32
    var lineHeight: Int
    var red: UInt16
    var green: UInt16
    var blue: UInt16
    var alpha: UInt16
}

@MainActor
private var storedGlyphMasks: [UInt32: PreviewUbmGlyphMask]?

@MainActor
private var textCache: [TextCacheKey: CGImage] = [:]

@MainActor
private var fallbackGlyphCache: [FallbackGlyphKey: PreviewUbmGlyphMask] = [:]

@MainActor
private var fallbackGlyphOrder: [FallbackGlyphKey] = []

private let fallbackGlyphLimit = 2048

private func quantizedComponent(_ value: CGFloat) -> UInt16 {
    let unit = min(max(Double(value), 0), 1)
    return UInt16((unit * 65535).rounded())
}

@MainActor
private func glyphMasks() -> [UInt32: PreviewUbmGlyphMask] {
    if let storedGlyphMasks { return storedGlyphMasks }
    var masks: [UInt32: PreviewUbmGlyphMask] = [:]
    if let directory = PreviewUbmStyle.skinDirectory(),
       let font = PreviewUbmStyle.loadAtlas(named: "font.png", in: directory),
       font.width == 258, font.height == 35 {
        func store(start: UInt32, count: Int, y: Int, height: Int) {
            for index in 0..<count {
                let x = 1 + index * 8
                var rgba = [UInt8](repeating: 0, count: 8 * height * 4)
                var ink = 0
                for row in 0..<height {
                    for column in 0..<8 {
                        guard let pixel = font.components(x: x + column, y: y + row) else { continue }
                        let red = UInt8(min(max(pixel.r * 255, 0), 255).rounded())
                        let green = UInt8(min(max(pixel.g * 255, 0), 255).rounded())
                        let blue = UInt8(min(max(pixel.b * 255, 0), 255).rounded())
                        let pink = red == 199 && green == 80 && blue == 127
                        let empty = red == 0 && green == 0 && blue == 0
                        let offset = (row * 8 + column) * 4
                        if pink || empty {
                            continue
                        }
                        rgba[offset] = red
                        rgba[offset + 1] = green
                        rgba[offset + 2] = blue
                        rgba[offset + 3] = 255
                        ink += 1
                    }
                }
                guard ink > 0 else { continue }
                masks[start + UInt32(index)] = PreviewUbmGlyphMask(
                    width: 8,
                    height: height,
                    advance: 8,
                    baseline: 12,
                    rgba: rgba,
                    keepsSourceRGB: true
                )
            }
        }
        // 三行都是 11 像素：y1…11、y12…22、y23…33。外框在 y0 和 y34。
        store(start: 0x21, count: 32, y: 1, height: 11)
        store(start: 0x41, count: 32, y: 12, height: 11)
        store(start: 0x61, count: 32, y: 23, height: 11)
    }
    storedGlyphMasks = masks
    return masks
}

@MainActor
private func splitLines(_ scalars: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
    var lines: [[Unicode.Scalar]] = [[]]
    for scalar in scalars {
        if scalar == "\n" || scalar == "\r" {
            lines.append([])
        } else {
            lines[lines.count - 1].append(scalar)
        }
    }
    return lines
}

@MainActor
private func lineWidth(_ line: [Unicode.Scalar], masks: [UInt32: PreviewUbmGlyphMask], color: NSColor) -> Int {
    var width = 0
    for scalar in line {
        if scalar == " " {
            width += 8
        } else if scalar == "\t" {
            width += 16
        } else if let mask = masks[scalar.value] {
            width += mask.advance
        } else {
            width += fallbackGlyph(scalar, color: color, lineHeight: 12).advance
        }
    }
    return max(width, 1)
}

@MainActor
private func fallbackGlyph(_ scalar: Unicode.Scalar, color: NSColor, lineHeight: Int) -> PreviewUbmGlyphMask {
    if scalar == " " {
        return PreviewUbmGlyphMask(width: 8, height: lineHeight, advance: 8, baseline: lineHeight, rgba: [], keepsSourceRGB: false)
    }
    if scalar == "\t" {
        return PreviewUbmGlyphMask(width: 16, height: lineHeight, advance: 16, baseline: lineHeight, rgba: [], keepsSourceRGB: false)
    }
    let tint = color.usingColorSpace(.sRGB) ?? color
    let key = FallbackGlyphKey(
        value: scalar.value,
        lineHeight: lineHeight,
        red: quantizedComponent(tint.redComponent),
        green: quantizedComponent(tint.greenComponent),
        blue: quantizedComponent(tint.blueComponent),
        alpha: quantizedComponent(tint.alphaComponent)
    )
    if let cached = fallbackGlyphCache[key] {
        return cached
    }
    let drawn = renderFallbackGlyph(scalar, color: tint, lineHeight: lineHeight)
    if fallbackGlyphCache[key] == nil, fallbackGlyphOrder.count >= fallbackGlyphLimit, let oldest = fallbackGlyphOrder.first {
        fallbackGlyphOrder.removeFirst()
        fallbackGlyphCache.removeValue(forKey: oldest)
    }
    if fallbackGlyphCache[key] == nil {
        fallbackGlyphOrder.append(key)
    }
    fallbackGlyphCache[key] = drawn
    return drawn
}

@MainActor
private func renderFallbackGlyph(_ scalar: Unicode.Scalar, color: NSColor, lineHeight: Int) -> PreviewUbmGlyphMask {
    let text = String(scalar)
    let base = CTFontCreateUIFontForLanguage(.system, 11, nil) ?? CTFontCreateWithName("Menlo" as CFString, 11, nil)
    let font = CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: text.utf16.count))
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let measured = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let width = min(max(Int(ceil(measured)), 4), 32)
    let height = lineHeight
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
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
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 0, y: max(descent, 0))
        CTLineDraw(line, context)
        return true
    }
    if !drew || pixels.allSatisfy({ $0 == 0 }) {
        var rgba = [UInt8](repeating: 0, count: 8 * lineHeight * 4)
        for y in 1..<(lineHeight - 1) {
            for x in [1, 6] {
                let offset = (y * 8 + x) * 4
                rgba[offset] = 255
                rgba[offset + 1] = 255
                rgba[offset + 2] = 255
                rgba[offset + 3] = 255
            }
        }
        for x in 1..<7 {
            for y in [1, lineHeight - 2] {
                let offset = (y * 8 + x) * 4
                rgba[offset] = 255
                rgba[offset + 1] = 255
                rgba[offset + 2] = 255
                rgba[offset + 3] = 255
            }
        }
        return PreviewUbmGlyphMask(width: 8, height: lineHeight, advance: 8, baseline: lineHeight, rgba: rgba, keepsSourceRGB: false)
    }
    return PreviewUbmGlyphMask(width: width, height: height, advance: width, baseline: height, rgba: pixels, keepsSourceRGB: false)
}

@MainActor
private func preservesFontRGB(_ color: NSColor) -> Bool {
    let sample = color.usingColorSpace(.sRGB) ?? color
    let original = PreviewUbmStyle.originalFontColor.usingColorSpace(.sRGB) ?? PreviewUbmStyle.originalFontColor
    return abs(sample.redComponent - original.redComponent) < 0.004
        && abs(sample.greenComponent - original.greenComponent) < 0.004
        && abs(sample.blueComponent - original.blueComponent) < 0.004
        && abs(sample.alphaComponent - original.alphaComponent) < 0.004
}

@MainActor
private func blit(
    _ mask: PreviewUbmGlyphMask,
    at x: Int,
    baseline: Int,
    into pixels: inout [UInt8],
    width: Int,
    height: Int,
    red: Double,
    green: Double,
    blue: Double,
    alpha tintAlpha: Double,
    keepSourceRGB: Bool
) {
    let originY = baseline - mask.baseline
    guard !mask.rgba.isEmpty else { return }
    for row in 0..<mask.height {
        let destinationY = originY + row
        guard destinationY >= 0, destinationY < height else { continue }
        for column in 0..<mask.width {
            let destinationX = x + column
            guard destinationX >= 0, destinationX < width else { continue }
            let source = (row * mask.width + column) * 4
            guard source + 3 < mask.rgba.count else { continue }
            let alpha = Double(mask.rgba[source + 3]) / 255
            guard alpha > 0 else { continue }
            let destination = (destinationY * width + destinationX) * 4
            if keepSourceRGB {
                pixels[destination] = mask.rgba[source]
                pixels[destination + 1] = mask.rgba[source + 1]
                pixels[destination + 2] = mask.rgba[source + 2]
                pixels[destination + 3] = mask.rgba[source + 3]
            } else {
                let coverage = max(Double(mask.rgba[source]), Double(mask.rgba[source + 1]), Double(mask.rgba[source + 2])) / 255 * alpha * tintAlpha
                guard coverage > 0 else { continue }
                pixels[destination] = UInt8(min(red * coverage * 255, 255))
                pixels[destination + 1] = UInt8(min(green * coverage * 255, 255))
                pixels[destination + 2] = UInt8(min(blue * coverage * 255, 255))
                pixels[destination + 3] = UInt8(min(coverage * 255, 255))
            }
        }
    }
}

@MainActor
private func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
