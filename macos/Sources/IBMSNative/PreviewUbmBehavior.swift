import Foundation

/// uBMplay 1.5.2 的选项、按键和定位状态。
///
/// 只保存调用方下一步要做什么，不读谱、不建播放器、不起计时器。
/// 地址能确定的行为按 `uBMplay.exe`（MD5 `44e3d8aa24e2eb19d1e426fde4086d03`）走。
/// 反汇编没钉死的循环顺序用官方 readme，并在 `UB-report.md` 里和地址证据分开。
/// 这不是整份预览的复刻；窗口、声音和 BGA 仍由后续集成去接这些动作。
public struct PreviewUbmBehavior: Equatable, Sendable {
    /// 下落速度倍率。固定 19 档：0.50…5.00，每档 0.25。1 减小，2 增大，同时按下向 1.00 靠一档。
    /// 48px/beat 下这些档对应 24…240，都落在播放区 16…240 里面。
    public var hiSpeed: Double = 1
    /// 播放倍速的百分数。100 表示 1.00x。固定 16 档：25…400，每档 25，也就是 0.25x…4.00x。
    /// 3 减小，4 增大，同时按下向 100 靠一档。可用档还要小于等于 `realHSCeiling`。
    public var realHS: Int = 100
    /// 运行中的 RealHS 整数上限。100 表示 1 倍，400 表示 `AVAudioUnitVarispeed` 的 4 倍。
    /// 原版 `LoadConfig` 的 200，以及 `5 * Int(2000000 / 采样率)`，只作历史参照，不参与夹紧。
    public var realHSCeiling: Int = Self.realHSRuntimeCeiling
    /// `dword_42E554`，0...4。默认 3 来自说明书括号里的「通常表示」，整数和四句叠字的对应没有从 switch 接上。
    public var bgaRaw: Int = PreviewUbmBGAMode.normal.rawValue
    /// `dword_42E558`。循环是 `x = 2x+1`，大于 7 写成 0。默认 7 来自说明书括号里的全开。
    public var effectsRaw: Int = 7
    /// `dword_42E55C`。默认 0 对应说明书的「左・右」。超过 3 回到 0；栈上的模数不是立即数，4 态来自说明书。
    public var scratchRaw: Int = 0
    /// `dword_42E564`。0→1→6→7→0。默认 1 是说明书的「再生情报」。
    public var infoRaw: Int = 1
    /// `dword_42E560` 取反。默认 false 来自说明书括号里的 OFF，初值指令没有单独摘出。
    public var alwaysOnTop: Bool = false
    /// 播放状态 `dword_42E5B4` 的 0x0B。默认不在暂停。
    public var paused: Bool = false
    /// 说明书的五态，默认 KEY&BGM。F1 的状态变量这次没有在反汇编里钉死。
    public var sound: PreviewUbmSoundMode = .keyAndBGM
    /// 说明书默认 ON。OFF 时调用方应把车道收成双人贴拢；`#PLAYER == 3` 的坐标种子是另一条已看到的分支。
    public var autoSeparate: Bool = true
    /// 路径字符串 `0x42E460` 非空时，空格长按才真正重读。
    public var hasReloadPath: Bool = false
    /// 有标题、或已经在播时 SeekBMS 才继续。空标题且状态为 0 会整段退出。
    public var canSeek: Bool = false
    /// 原版只在状态 0x0A 与 0x0B 之间切换暂停。还没开始播放时把这里关掉。
    public var pauseEnabled: Bool = true

    private var held: Set<PreviewUbmCommand> = []
    private var repeatClocks: [PreviewUbmCommand: PreviewUbmRepeatClock] = [:]
    private var spaceArmed = false
    private var spaceConsumed = false

    public static let hiSpeedStep = 0.25
    /// 0.25 倍会变成 12px，被播放区抬到 16px。最低档从 0.50（24px）起。
    public static let hiSpeedFloor = 0.50
    public static let hiSpeedCeiling = 5.0
    public static let hiSpeedCenter = 1.0
    /// 2…20 乘 0.25：0.50、0.75、…、5.00，共 19 档。
    public static let hiSpeedDetents: [Double] = (2...20).map { Double($0) / 4.0 }
    /// 一档是 0.25x，存成百分数就是 25。
    public static let realHSStep = 25
    public static let realHSFloor = 25
    public static let realHSCenter = 100
    /// 25、50、…、400，共 16 档。
    public static let realHSDetents: [Int] = Array(stride(from: 25, through: 400, by: 25))
    /// 和引擎 4 倍同一上限。100 是 1 倍。
    public static let realHSRuntimeCeiling = 400
    /// `0x40f74f` 的立即数 `0xC8`。历史参照，不是当前运行上限。
    public static let realHSLoadConfigCeiling = 200
    /// `0x417ef0` 的整数参数。函数体没打开，和空格的 500 放在同一套按键计时里，按毫秒使用。
    public static let holdRepeatInitialMilliseconds = 50.0
    /// `0x417ef0` 的浮点立即数 `0x3FA66666`。readme 写按住加速，所以间隔除以它。
    public static let holdRepeatRate = 1.3
    /// 空格比较的是 `0x1F4`。readme 写 0.5 秒，单位按毫秒推断。
    public static let reloadHoldMilliseconds = 500.0
    /// `0x417ef0` 没还原出最小间隔。防止除到 0 之后截止时间不再前进。
    public static let minimumRepeatMilliseconds = 1.0
    /// 说明书四态。反汇编只看到加 1 后和栈上的上限比较。
    public static let scratchStateCount = 4

    public init() {}

    public var bgaMode: PreviewUbmBGAMode? {
        PreviewUbmBGAMode(rawValue: bgaRaw)
    }

    /// readme：OFF 不读图。只在 raw 0 上成立，其余值都交给调用方读图。
    public var bgaLoadsGraphics: Bool {
        bgaRaw != 0
    }

    /// bit0 判定。位意义对照说明书的三层叠加，`test` 摘录只覆盖爆炸位。
    public var showsJudgment: Bool { effectsRaw & 1 != 0 }
    /// bit1。`DrawBomb` `0x415ec6` 测试这个位。
    public var showsBomb: Bool { effectsRaw & 2 != 0 }
    /// bit2 光束。没有单独的 `test` 摘录。
    public var showsBeam: Bool { effectsRaw & 4 != 0 }

    /// bit0 播放，bit1 曲，bit2 选项。6 = 曲+选项，7 = 全部，和说明书四档对齐；其余组合键不会停。
    public var showsPlayInfo: Bool { infoRaw & 1 != 0 }
    public var showsSongInfo: Bool { infoRaw & 2 != 0 }
    public var showsOptionInfo: Bool { infoRaw & 4 != 0 }

    /// readme 顺序下的 1P / 2P 搓盘。raw 不在 0...3 时没有对应布局。
    public var scratchPlayers: PreviewUbmScratchPlayers? {
        switch scratchRaw {
        case 0:
            return PreviewUbmScratchPlayers(player1: .left, player2: .right)
        case 1:
            return PreviewUbmScratchPlayers(player1: .right, player2: .right)
        case 2:
            return PreviewUbmScratchPlayers(player1: .left, player2: .left)
        case 3:
            return PreviewUbmScratchPlayers(player1: .right, player2: .left)
        default:
            return nil
        }
    }

    public var scratchBit0: Bool { scratchRaw & 1 != 0 }
    public var scratchBit1: Bool { scratchRaw & 2 != 0 }

    public var lanePacking: PreviewUbmLanePacking {
        autoSeparate ? .followPlayer : .packedDouble
    }

    public func allows(_ kind: PreviewUbmAudibleKind) -> Bool {
        switch sound {
        case .bgm:
            return kind == .bgm
        case .key:
            return kind == .key
        case .keyAndBGM:
            return kind == .bgm || kind == .key
        case .mine:
            return kind == .mine
        case .keyBGMAndMine:
            return true
        }
    }

    /// 第 `index` 次按住重复的截止时间，从按下瞬间算起。0 是第一次重复，不是按下的那一下。
    public static func repeatDeadline(index: Int) -> Double {
        var deadline = holdRepeatInitialMilliseconds
        var interval = holdRepeatInitialMilliseconds
        guard index > 0 else { return deadline }
        for _ in 1...index {
            let advanced = nextRepeatDeadline(previousDeadline: deadline, interval: interval)
            deadline = advanced.deadline
            interval = advanced.interval
        }
        return deadline
    }

    public static func nextRepeatDeadline(
        previousDeadline: Double,
        interval: Double
    ) -> (deadline: Double, interval: Double) {
        let nextInterval = max(minimumRepeatMilliseconds, interval / holdRepeatRate)
        return (previousDeadline + nextInterval, nextInterval)
    }

    /// `characters` 用 AppKit `charactersIgnoringModifiers` 的功能键标量。
    /// `keyCode` 不参与判断：原版表是 Windows 虚拟键，macOS 硬件码没有对应证据。
    /// `commandModifier` 为真时返回 nil，避免吃掉 Command 组合键。
    public static func command(
        for characters: String,
        keyCode: UInt16,
        isKeypad: Bool,
        commandModifier: Bool = false
    ) -> PreviewUbmCommand? {
        if commandModifier {
            return nil
        }
        // 空串、小键盘只有键码、或硬件码本身，都不猜。
        if characters.unicodeScalars.count != 1 {
            return nil
        }
        _ = (keyCode, isKeypad)
        switch characters.unicodeScalars[characters.unicodeScalars.startIndex].value {
        case 0x31: return .hiSpeedDown
        case 0x32: return .hiSpeedUp
        case 0x33: return .realHSDown
        case 0x34: return .realHSUp
        case 0x35: return .cycleBGA
        case 0x36: return .cycleEffects
        case 0x37: return .toggleAlwaysOnTop
        case 0x38: return .cycleScratch
        case 0x39: return .cycleInfo
        case 0x30: return .togglePause
        case 0x20: return .spaceReload
        case PreviewUbmFunctionScalar.up: return .seekUp
        case PreviewUbmFunctionScalar.down: return .seekDown
        case PreviewUbmFunctionScalar.pageUp: return .seekPageUp
        case PreviewUbmFunctionScalar.pageDown: return .seekPageDown
        case PreviewUbmFunctionScalar.home: return .seekHome
        case PreviewUbmFunctionScalar.end: return .seekEnd
        case PreviewUbmFunctionScalar.f1: return .cycleSound
        case PreviewUbmFunctionScalar.f2: return .toggleAutoSeparate
        default: return nil
        }
    }

    /// 鼠标滚轮和 Up/Down 一样按小节走。readme 有滚轮，反汇编这次没有单独摘滚轮槽。
    public mutating func seekByMeasures(
        _ delta: Int,
        currentBeat: Double,
        measures: PreviewUbmMeasures
    ) -> PreviewUbmAction {
        guard let seek = makeSeek(target: nil, delta: delta, currentBeat: currentBeat, measures: measures) else {
            return .none
        }
        return PreviewUbmAction(seek: seek)
    }

    public mutating func apply(
        _ command: PreviewUbmCommand,
        phase: PreviewUbmInputPhase = .keyDown,
        elapsedMilliseconds: Double = 0,
        currentBeat: Double = 0,
        measures: PreviewUbmMeasures = PreviewUbmMeasures()
    ) -> PreviewUbmAction {
        switch phase {
        case .keyUp:
            held.remove(command)
            repeatClocks[command] = nil
            if command == .spaceReload {
                spaceArmed = false
                spaceConsumed = false
            }
            return .none
        case .keyDown:
            let alreadyHeld = held.contains(command)
            held.insert(command)
            if command == .spaceReload {
                if !alreadyHeld {
                    spaceArmed = true
                    spaceConsumed = false
                }
                return .none
            }
            if alreadyHeld {
                return .none
            }
            if command.usesHoldRepeat {
                repeatClocks[command] = PreviewUbmRepeatClock(
                    nextMilliseconds: Self.holdRepeatInitialMilliseconds,
                    intervalMilliseconds: Self.holdRepeatInitialMilliseconds
                )
            }
            return perform(
                command,
                currentBeat: currentBeat,
                measures: measures
            )
        case .keyRepeat:
            guard held.contains(command) else { return .none }
            if command == .spaceReload {
                return performSpaceReload(elapsedMilliseconds: elapsedMilliseconds)
            }
            guard command.usesHoldRepeat, var clock = repeatClocks[command] else {
                return .none
            }
            guard elapsedMilliseconds.isFinite, elapsedMilliseconds >= clock.nextMilliseconds else {
                return .none
            }
            repeat {
                let advanced = Self.nextRepeatDeadline(
                    previousDeadline: clock.nextMilliseconds,
                    interval: clock.intervalMilliseconds
                )
                clock.nextMilliseconds = advanced.deadline
                clock.intervalMilliseconds = advanced.interval
            } while clock.nextMilliseconds <= elapsedMilliseconds && clock.intervalMilliseconds > Self.minimumRepeatMilliseconds
            if clock.nextMilliseconds <= elapsedMilliseconds {
                let remaining = elapsedMilliseconds - clock.nextMilliseconds
                let steps = remaining.rounded(.down) + 1
                clock.nextMilliseconds += steps * Self.minimumRepeatMilliseconds
            }
            repeatClocks[command] = clock
            return perform(
                command,
                currentBeat: currentBeat,
                measures: measures
            )
        }
    }

    private mutating func performSpaceReload(elapsedMilliseconds: Double) -> PreviewUbmAction {
        guard spaceArmed, !spaceConsumed else { return .none }
        guard elapsedMilliseconds.isFinite, elapsedMilliseconds >= Self.reloadHoldMilliseconds else {
            return .none
        }
        // 原版即使路径为空也会落下闩，同一次按住不会再试。
        spaceConsumed = true
        guard hasReloadPath else { return .none }
        return PreviewUbmAction(reloadChart: true)
    }

    private mutating func perform(
        _ command: PreviewUbmCommand,
        currentBeat: Double,
        measures: PreviewUbmMeasures
    ) -> PreviewUbmAction {
        switch command {
        case .hiSpeedDown, .hiSpeedUp:
            return adjustHiSpeed()
        case .realHSDown, .realHSUp:
            return adjustRealHS()
        case .cycleBGA:
            let next = bgaRaw + 1
            bgaRaw = next > 4 ? 0 : next
            return PreviewUbmAction(bgaChanged: true)
        case .cycleEffects:
            let next = effectsRaw * 2 + 1
            effectsRaw = next > 7 ? 0 : next
            return PreviewUbmAction(effectsChanged: true)
        case .toggleAlwaysOnTop:
            alwaysOnTop.toggle()
            return PreviewUbmAction(alwaysOnTopChanged: true)
        case .cycleScratch:
            let next = scratchRaw + 1
            scratchRaw = next > Self.scratchStateCount - 1 ? 0 : next
            return PreviewUbmAction(layoutChanged: true)
        case .cycleInfo:
            switch infoRaw {
            case 0: infoRaw = 1
            case 1: infoRaw = 6
            case 6: infoRaw = 7
            default: infoRaw = 0
            }
            return PreviewUbmAction(infoChanged: true)
        case .togglePause:
            guard pauseEnabled else { return .none }
            paused.toggle()
            return PreviewUbmAction(playback: paused ? .pause : .resume)
        case .cycleSound:
            sound = sound.next
            return PreviewUbmAction(soundChanged: true)
        case .toggleAutoSeparate:
            autoSeparate.toggle()
            return PreviewUbmAction(layoutChanged: true)
        case .seekUp:
            return seekAction(delta: -1, currentBeat: currentBeat, measures: measures)
        case .seekDown:
            return seekAction(delta: 1, currentBeat: currentBeat, measures: measures)
        case .seekPageUp:
            return seekAction(delta: -4, currentBeat: currentBeat, measures: measures)
        case .seekPageDown:
            return seekAction(delta: 4, currentBeat: currentBeat, measures: measures)
        case .seekHome:
            return seekAction(home: true, currentBeat: currentBeat, measures: measures)
        case .seekEnd:
            return seekAction(end: true, currentBeat: currentBeat, measures: measures)
        case .spaceReload:
            return .none
        }
    }

    private mutating func adjustHiSpeed() -> PreviewUbmAction {
        let down = held.contains(.hiSpeedDown)
        let up = held.contains(.hiSpeedUp)
        let previous = hiSpeed
        if !hiSpeed.isFinite {
            hiSpeed = Self.hiSpeedCenter
        }
        if down && up {
            if hiSpeed > Self.hiSpeedCenter {
                let next = Self.steppedHiSpeed(hiSpeed, direction: -1)
                hiSpeed = next < Self.hiSpeedCenter ? Self.hiSpeedCenter : next
            } else if hiSpeed < Self.hiSpeedCenter {
                let next = Self.steppedHiSpeed(hiSpeed, direction: 1)
                hiSpeed = next > Self.hiSpeedCenter ? Self.hiSpeedCenter : next
            }
        } else if up {
            hiSpeed = Self.steppedHiSpeed(hiSpeed, direction: 1)
        } else if down {
            hiSpeed = Self.steppedHiSpeed(hiSpeed, direction: -1)
        }
        return PreviewUbmAction(hiSpeedChanged: hiSpeed != previous)
    }

    private mutating func adjustRealHS() -> PreviewUbmAction {
        let down = held.contains(.realHSDown)
        let up = held.contains(.realHSUp)
        let previous = realHS
        let ceiling = realHSCeiling
        if down && up {
            if realHS > Self.realHSCenter {
                let next = Self.steppedRealHS(realHS, direction: -1, ceiling: ceiling)
                if Self.legalRealHSDetents(ceiling: ceiling).contains(Self.realHSCenter) {
                    realHS = next < Self.realHSCenter ? Self.realHSCenter : next
                } else {
                    realHS = next
                }
            } else if realHS < Self.realHSCenter {
                let next = Self.steppedRealHS(realHS, direction: 1, ceiling: ceiling)
                if Self.legalRealHSDetents(ceiling: ceiling).contains(Self.realHSCenter) {
                    realHS = next > Self.realHSCenter ? Self.realHSCenter : next
                } else {
                    realHS = next
                }
            }
        } else if up {
            realHS = Self.steppedRealHS(realHS, direction: 1, ceiling: ceiling)
        } else if down {
            realHS = Self.steppedRealHS(realHS, direction: -1, ceiling: ceiling)
        }
        return PreviewUbmAction(realHSChanged: realHS != previous)
    }

    /// 只在当前值高于 ceiling 时改写。结果是不超过 ceiling 的最高档；ceiling 低于 25 时写成 ceiling 本身。
    /// 赋值 `realHSCeiling` 本身不夹紧。
    @discardableResult
    public mutating func clampRealHSToCeiling() -> Bool {
        guard realHS > realHSCeiling else { return false }
        realHS = Self.legalRealHSDetents(ceiling: realHSCeiling).last ?? realHSCeiling
        return true
    }

    /// 距离相等时留下较低的那一档。非有限值看成 1.00。
    public static func nearestHiSpeedDetent(_ value: Double) -> Double {
        let current = value.isFinite ? value : hiSpeedCenter
        var best = hiSpeedDetents[0]
        var bestDistance = abs(current - best)
        for detent in hiSpeedDetents.dropFirst() {
            let distance = abs(current - detent)
            if distance < bestDistance {
                best = detent
                bestDistance = distance
            }
        }
        return best
    }

    /// 正方向取严格更高的下一档，负方向取严格更低的下一档。到头就停在端点。
    public static func steppedHiSpeed(_ value: Double, direction: Int) -> Double {
        let current = value.isFinite ? value : hiSpeedCenter
        if direction > 0 {
            return hiSpeedDetents.first { $0 > current + 0.000_001 } ?? hiSpeedDetents[hiSpeedDetents.count - 1]
        }
        if direction < 0 {
            return hiSpeedDetents.last { $0 < current - 0.000_001 } ?? hiSpeedDetents[0]
        }
        return nearestHiSpeedDetent(current)
    }

    /// ceiling 低于第一档时，表里只放 ceiling 自己，避免键再往上跳。
    public static func legalRealHSDetents(ceiling: Int) -> [Int] {
        let allowed = realHSDetents.filter { $0 <= ceiling }
        if allowed.isEmpty {
            return [min(realHSFloor, ceiling)]
        }
        return allowed
    }

    /// 距离相等时留下较低的百分数。
    public static func nearestRealHSDetent(_ value: Int, ceiling: Int) -> Int {
        let table = legalRealHSDetents(ceiling: ceiling)
        var best = table[0]
        var bestDistance = abs(value - best)
        for detent in table.dropFirst() {
            let distance = abs(value - detent)
            if distance < bestDistance {
                best = detent
                bestDistance = distance
            }
        }
        return best
    }

    /// 正方向取严格更高且不超过 ceiling 的下一档。到头就停。
    public static func steppedRealHS(_ value: Int, direction: Int, ceiling: Int) -> Int {
        let table = legalRealHSDetents(ceiling: ceiling)
        if direction > 0 {
            return table.first { $0 > value } ?? table[table.count - 1]
        }
        if direction < 0 {
            return table.last { $0 < value } ?? table[0]
        }
        return nearestRealHSDetent(value, ceiling: ceiling)
    }

    private func seekAction(
        delta: Int = 0,
        home: Bool = false,
        end: Bool = false,
        currentBeat: Double,
        measures: PreviewUbmMeasures
    ) -> PreviewUbmAction {
        let target: Int?
        if home {
            target = 0
        } else if end {
            target = measures.lastContentMeasure
        } else {
            target = nil
        }
        guard let seek = makeSeek(target: target, delta: delta, currentBeat: currentBeat, measures: measures) else {
            return .none
        }
        return PreviewUbmAction(seek: seek)
    }

    private func makeSeek(
        target: Int?,
        delta: Int,
        currentBeat: Double,
        measures: PreviewUbmMeasures
    ) -> PreviewUbmSeek? {
        guard canSeek, let resolved = measures.seekIndex(target: target, delta: delta, beat: currentBeat) else {
            return nil
        }
        guard let beat = measures.beat(ofMeasure: resolved) else { return nil }
        return PreviewUbmSeek(measure: resolved, beat: beat, emitsSound: !paused)
    }

}

public enum PreviewUbmCommand: Hashable, Sendable {
    case hiSpeedDown
    case hiSpeedUp
    case realHSDown
    case realHSUp
    case cycleBGA
    case cycleEffects
    case toggleAlwaysOnTop
    case cycleScratch
    case cycleInfo
    case togglePause
    case cycleSound
    case toggleAutoSeparate
    case seekUp
    case seekDown
    case seekPageUp
    case seekPageDown
    case seekHome
    case seekEnd
    case spaceReload

    var usesHoldRepeat: Bool {
        switch self {
        case .seekUp, .seekDown, .seekPageUp, .seekPageDown:
            return true
        case .hiSpeedDown, .hiSpeedUp, .realHSDown, .realHSUp,
             .cycleBGA, .cycleEffects, .toggleAlwaysOnTop, .cycleScratch, .cycleInfo,
             .togglePause, .cycleSound, .toggleAutoSeparate, .seekHome, .seekEnd, .spaceReload:
            return false
        }
    }
}

public enum PreviewUbmInputPhase: Equatable, Sendable {
    case keyDown
    case keyRepeat
    case keyUp
}

public enum PreviewUbmBGAMode: Int, Equatable, Sendable {
    case off = 0
    case base = 1
    case layer = 2
    case normal = 3
    case alwaysPoor = 4
}

public enum PreviewUbmSoundMode: Equatable, CaseIterable, Sendable {
    case bgm
    case key
    case keyAndBGM
    case mine
    case keyBGMAndMine

    var next: PreviewUbmSoundMode {
        let order = Self.allCases
        let index = order.firstIndex(of: self) ?? 0
        return order[(index + 1) % order.count]
    }
}

public enum PreviewUbmAudibleKind: Equatable, Sendable {
    case bgm
    case key
    case mine
}

public enum PreviewUbmScratchSide: Equatable, Sendable {
    case left
    case right
}

public struct PreviewUbmScratchPlayers: Equatable, Sendable {
    public var player1: PreviewUbmScratchSide
    public var player2: PreviewUbmScratchSide

    public init(player1: PreviewUbmScratchSide, player2: PreviewUbmScratchSide) {
        self.player1 = player1
        self.player2 = player2
    }
}

public enum PreviewUbmLanePacking: Equatable, Sendable {
    /// F2 开。`#PLAYER == 3` 时原版写 331 宽种子；其他玩家数怎么分栏还没追完。
    case followPlayer
    /// F2 关。readme：总是收成 DP。几何分支未追完。
    case packedDouble
}

public enum PreviewUbmPlayback: Equatable, Sendable {
    case pause
    case resume
}

public struct PreviewUbmSeek: Equatable, Sendable {
    public var measure: Int
    public var beat: Double
    /// 暂停中为 false。调用方只改位置，不要为这次 seek 开新的声音。
    public var emitsSound: Bool

    public init(measure: Int, beat: Double, emitsSound: Bool) {
        self.measure = measure
        self.beat = beat
        self.emitsSound = emitsSound
    }
}

public struct PreviewUbmAction: Equatable, Sendable {
    public var seek: PreviewUbmSeek?
    public var reloadChart: Bool
    public var playback: PreviewUbmPlayback?
    public var layoutChanged: Bool
    public var soundChanged: Bool
    public var hiSpeedChanged: Bool
    /// 键路径已经写入新的 RealHS。调用方接着把百分数交给播放速率。
    public var realHSChanged: Bool
    /// 键路径现在停在档位表内，不再写出高于 ceiling 的值。字段保留给旧的动作结构。
    public var realHSExceedsCeiling: Bool
    public var bgaChanged: Bool
    public var effectsChanged: Bool
    public var infoChanged: Bool
    public var alwaysOnTopChanged: Bool

    public init(
        seek: PreviewUbmSeek? = nil,
        reloadChart: Bool = false,
        playback: PreviewUbmPlayback? = nil,
        layoutChanged: Bool = false,
        soundChanged: Bool = false,
        hiSpeedChanged: Bool = false,
        realHSChanged: Bool = false,
        realHSExceedsCeiling: Bool = false,
        bgaChanged: Bool = false,
        effectsChanged: Bool = false,
        infoChanged: Bool = false,
        alwaysOnTopChanged: Bool = false
    ) {
        self.seek = seek
        self.reloadChart = reloadChart
        self.playback = playback
        self.layoutChanged = layoutChanged
        self.soundChanged = soundChanged
        self.hiSpeedChanged = hiSpeedChanged
        self.realHSChanged = realHSChanged
        self.realHSExceedsCeiling = realHSExceedsCeiling
        self.bgaChanged = bgaChanged
        self.effectsChanged = effectsChanged
        self.infoChanged = infoChanged
        self.alwaysOnTopChanged = alwaysOnTopChanged
    }

    /// 不可变的空动作。类型是 `Sendable`，这个 `let` 可以跨任务共享。
    public static let none = PreviewUbmAction()

    public var isEmpty: Bool {
        self == .none
    }
}

/// 每个元素是该内容小节的起始拍。不要在末尾再塞一个“小节结束”哨兵，End 会把它当成最后一小节。
public struct PreviewUbmMeasures: Equatable, Sendable {
    public var starts: [Double]

    public init(starts: [Double] = []) {
        self.starts = starts
    }

    public var lastContentMeasure: Int? {
        starts.indices.filter { starts[$0].isFinite }.max()
    }

    public func measureIndex(at beat: Double) -> Int? {
        guard beat.isFinite else { return nil }
        var best: Int?
        var bestStart = -Double.greatestFiniteMagnitude
        for (index, start) in starts.enumerated() where start.isFinite {
            if start <= beat && start >= bestStart {
                best = index
                bestStart = start
            }
        }
        if let best {
            return best
        }
        return starts.firstIndex(where: \.isFinite)
    }

    public func beat(ofMeasure measure: Int) -> Double? {
        guard starts.indices.contains(measure), starts[measure].isFinite else { return nil }
        return starts[measure]
    }

    func seekIndex(target: Int?, delta: Int, beat: Double) -> Int? {
        guard let last = lastContentMeasure else { return nil }
        let raw: Int
        if let target {
            raw = target
        } else {
            guard let current = measureIndex(at: beat) else { return nil }
            raw = current + delta
        }
        if raw < 0 { return 0 }
        if raw > last { return last }
        return raw
    }
}

public enum PreviewUbmFunctionScalar: Sendable {
    public static let up: UInt32 = 0xF700
    public static let down: UInt32 = 0xF701
    public static let f1: UInt32 = 0xF704
    public static let f2: UInt32 = 0xF705
    public static let home: UInt32 = 0xF729
    public static let end: UInt32 = 0xF72B
    public static let pageUp: UInt32 = 0xF72C
    public static let pageDown: UInt32 = 0xF72D

    public static func character(_ scalar: UInt32) -> String {
        String(UnicodeScalar(scalar)!)
    }
}

private struct PreviewUbmRepeatClock: Equatable, Sendable {
    var nextMilliseconds: Double
    var intervalMilliseconds: Double
}
