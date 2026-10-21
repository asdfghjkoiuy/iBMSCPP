import Foundation

@main
struct PreviewUbmBehaviorTests {
    static func main() {
        testDefaults()
        testStateCycles()
        testHiSpeedStepsAndDualKey()
        testRealHSRangeAndCeiling()
        testRuntimeCeilingReaches400()
        testScratchPlayers()
        testInfoBits()
        testSoundPredicateAndEffects()
        testPauseSeekDoesNotEmitSound()
        testVariableMeterSeek()
        testSpaceReloadLatch()
        testHoldRepeatSchedule()
        testCommandCharactersDriveState()
        testSendableCopiesDoNotShareMutation()
        print("PreviewUbmBehaviorTests passed")
    }
}

private func testDefaults() {
    let model = PreviewUbmBehavior()
    require(model.hiSpeed == 1, "default HiSpeed")
    require(model.realHS == 100, "default RealHS")
    require(model.realHSCeiling == 400, "runtime ceiling is 400")
    require(model.realHSCeiling == PreviewUbmBehavior.realHSRuntimeCeiling, "runtime ceiling constant")
    require(PreviewUbmBehavior.realHSLoadConfigCeiling == 200, "LoadConfig immediate stays 200")
    require(model.bgaRaw == 3 && model.bgaMode == .normal, "default BGA normal")
    require(model.effectsRaw == 7, "default effects")
    require(model.showsJudgment && model.showsBomb && model.showsBeam, "default effects all on")
    require(model.scratchRaw == 0, "default scratch")
    require(model.scratchPlayers == PreviewUbmScratchPlayers(player1: .left, player2: .right), "default L/R")
    require(model.infoRaw == 1 && model.showsPlayInfo && !model.showsSongInfo && !model.showsOptionInfo, "default info")
    require(!model.alwaysOnTop && !model.paused, "default top and pause")
    require(model.sound == .keyAndBGM && model.autoSeparate, "default sound and separate")
    require(model.lanePacking == .followPlayer, "auto separate packing")
    require(!model.hasReloadPath && !model.canSeek, "closed chart does not seek or reload")
}

private func testStateCycles() {
    var model = PreviewUbmBehavior()
    var bga: [Int] = [model.bgaRaw]
    for _ in 0..<5 {
        let action = model.apply(.cycleBGA, phase: .keyDown)
        require(action.bgaChanged && action.seek == nil, "BGA action")
        bga.append(model.bgaRaw)
        require(model.apply(.cycleBGA, phase: .keyUp).isEmpty, "BGA release")
    }
    require(bga == [3, 4, 0, 1, 2, 3], "BGA cycle \(bga)")
    require(model.bgaLoadsGraphics, "normal still loads")
    model.bgaRaw = 0
    require(!model.bgaLoadsGraphics, "off does not load")
    model.bgaRaw = 6
    _ = model.apply(.cycleBGA, phase: .keyDown)
    _ = model.apply(.cycleBGA, phase: .keyUp)
    require(model.bgaRaw == 0, "BGA above 4 collapses to 0, not modulo")

    model = PreviewUbmBehavior()
    var effects: [Int] = [model.effectsRaw]
    for _ in 0..<4 {
        _ = model.apply(.cycleEffects, phase: .keyDown)
        effects.append(model.effectsRaw)
        _ = model.apply(.cycleEffects, phase: .keyUp)
    }
    require(effects == [7, 0, 1, 3, 7], "effects cycle \(effects)")
    model.effectsRaw = 2
    _ = model.apply(.cycleEffects, phase: .keyDown)
    require(model.effectsRaw == 5, "effects formula keeps 2*2+1")

    model = PreviewUbmBehavior()
    var info: [Int] = [model.infoRaw]
    for _ in 0..<4 {
        _ = model.apply(.cycleInfo, phase: .keyDown)
        info.append(model.infoRaw)
        _ = model.apply(.cycleInfo, phase: .keyUp)
    }
    require(info == [1, 6, 7, 0, 1], "info cycle \(info)")
    model.infoRaw = 3
    _ = model.apply(.cycleInfo, phase: .keyDown)
    require(model.infoRaw == 0, "info default case clears unknown raw")

    model = PreviewUbmBehavior()
    var sounds: [PreviewUbmSoundMode] = [model.sound]
    for _ in 0..<5 {
        let action = model.apply(.cycleSound, phase: .keyDown)
        require(action.soundChanged && action.playback == nil, "sound action")
        sounds.append(model.sound)
        _ = model.apply(.cycleSound, phase: .keyUp)
    }
    require(
        sounds == [.keyAndBGM, .mine, .keyBGMAndMine, .bgm, .key, .keyAndBGM],
        "sound cycle follows readme, not the draw-string list \(sounds)"
    )

    model = PreviewUbmBehavior()
    let pause = model.apply(.togglePause, phase: .keyDown)
    require(model.paused && pause.playback == .pause, "pause")
    _ = model.apply(.togglePause, phase: .keyUp)
    let resume = model.apply(.togglePause, phase: .keyDown)
    require(!model.paused && resume.playback == .resume, "resume")
    model.pauseEnabled = false
    model.paused = false
    require(model.apply(.togglePause, phase: .keyDown).isEmpty && !model.paused, "pause ignored when disabled")

    model = PreviewUbmBehavior()
    require(!model.alwaysOnTop, "top starts off")
    _ = model.apply(.toggleAlwaysOnTop, phase: .keyDown)
    require(model.alwaysOnTop, "top turns on")
    _ = model.apply(.toggleAlwaysOnTop, phase: .keyUp)
    _ = model.apply(.toggleAlwaysOnTop, phase: .keyDown)
    require(!model.alwaysOnTop, "top returns")

    model = PreviewUbmBehavior()
    _ = model.apply(.toggleAutoSeparate, phase: .keyDown)
    require(!model.autoSeparate && model.lanePacking == .packedDouble, "separate off packs double")
    _ = model.apply(.toggleAutoSeparate, phase: .keyUp)
    _ = model.apply(.toggleAutoSeparate, phase: .keyDown)
    require(model.autoSeparate, "separate returns")
    _ = model.apply(.toggleAutoSeparate, phase: .keyUp)

    _ = model.apply(.cycleBGA, phase: .keyDown)
    let heldBGA = model.bgaRaw
    require(model.apply(.cycleBGA, phase: .keyRepeat, elapsedMilliseconds: 5_000).isEmpty, "toggle ignores repeat")
    require(model.bgaRaw == heldBGA, "held BGA does not spin")
}

private func testHiSpeedStepsAndDualKey() {
    require(PreviewUbmBehavior.hiSpeedDetents.count == 19, "HiSpeed has 19 detents")
    require(PreviewUbmBehavior.hiSpeedDetents.first == 0.5 && PreviewUbmBehavior.hiSpeedDetents.last == 5, "HiSpeed ends")
    var model = PreviewUbmBehavior()
    var seen = [model.hiSpeed]
    for _ in 0..<4 {
        _ = model.apply(.hiSpeedUp, phase: .keyDown)
        seen.append(model.hiSpeed)
        _ = model.apply(.hiSpeedUp, phase: .keyUp)
    }
    require(seen == [1, 1.25, 1.5, 1.75, 2], "up steps \(seen)")

    model = PreviewUbmBehavior()
    seen = [model.hiSpeed]
    for _ in 0..<3 {
        _ = model.apply(.hiSpeedDown, phase: .keyDown)
        seen.append(model.hiSpeed)
        _ = model.apply(.hiSpeedDown, phase: .keyUp)
    }
    require(seen == [1, 0.75, 0.5, 0.5], "down stops at 0.50 \(seen)")

    model.hiSpeed = 5
    for _ in 0..<8 {
        let held = model.apply(.hiSpeedUp, phase: .keyDown)
        require(!held.hiSpeedChanged && model.hiSpeed == 5, "top stays")
        _ = model.apply(.hiSpeedUp, phase: .keyUp)
    }

    model.hiSpeed = 2
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    model.hiSpeed = 2
    let towardDown = model.apply(.hiSpeedDown, phase: .keyDown)
    require(towardDown.hiSpeedChanged && model.hiSpeed == 1.75, "both keys from above \(model.hiSpeed)")
    _ = model.apply(.hiSpeedDown, phase: .keyUp)
    _ = model.apply(.hiSpeedUp, phase: .keyUp)

    model = PreviewUbmBehavior()
    model.hiSpeed = 0.5
    _ = model.apply(.hiSpeedDown, phase: .keyDown)
    model.hiSpeed = 0.5
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 0.75, "both keys from below \(model.hiSpeed)")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    _ = model.apply(.hiSpeedDown, phase: .keyUp)

    model = PreviewUbmBehavior()
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    model.hiSpeed = 1
    let stayed = model.apply(.hiSpeedDown, phase: .keyDown)
    require(!stayed.hiSpeedChanged && model.hiSpeed == 1, "both keys already at 1")

    model = PreviewUbmBehavior()
    model.hiSpeed = 0.25
    _ = model.apply(.hiSpeedDown, phase: .keyDown)
    require(model.hiSpeed == 0.5, "0.25 regularizes onto 0.50 instead of 16px")
    _ = model.apply(.hiSpeedDown, phase: .keyUp)

    model.hiSpeed = 0.375
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 0.5, "0.375 steps up onto the table \(model.hiSpeed)")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    model.hiSpeed = 0.375
    _ = model.apply(.hiSpeedDown, phase: .keyDown)
    model.hiSpeed = 0.375
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 0.5, "dual key from 0.375 stays on the table \(model.hiSpeed)")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    _ = model.apply(.hiSpeedDown, phase: .keyUp)

    model.hiSpeed = 1.1
    _ = model.apply(.hiSpeedDown, phase: .keyDown)
    require(model.hiSpeed == 1, "1.1 down lands on 1.00")
    _ = model.apply(.hiSpeedDown, phase: .keyUp)
    model.hiSpeed = 1.1
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 1.25, "1.1 up lands on 1.25")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    model.hiSpeed = 9
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 5, "above the table clamps to 5.00")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    model.hiSpeed = .nan
    _ = model.apply(.hiSpeedDown, phase: .keyDown)
    require(model.hiSpeed == 0.75, "non-finite starts at 1.00 then steps down")
}

private func testRealHSRangeAndCeiling() {
    require(PreviewUbmBehavior.realHSDetents.count == 16, "RealHS has 16 detents")
    require(PreviewUbmBehavior.realHSDetents.first == 25 && PreviewUbmBehavior.realHSDetents.last == 400, "RealHS ends")
    var fresh = PreviewUbmBehavior()
    let hiSpeedBefore = fresh.hiSpeed
    let climbed = fresh.apply(.realHSUp, phase: .keyDown)
    require(fresh.realHS == 125 && climbed.realHSChanged && !climbed.realHSExceedsCeiling, "one press leaves 100 for 125")
    require(!fresh.clampRealHSToCeiling() && fresh.realHS == 125, "125 is inside 400")
    require(fresh.hiSpeed == hiSpeedBefore, "RealHS default does not move HiSpeed")
    _ = fresh.apply(.realHSUp, phase: .keyUp)
    fresh.paused = true
    let pausedStep = fresh.apply(.realHSUp, phase: .keyDown)
    require(fresh.paused && fresh.realHS == 150 && pausedStep.realHSChanged, "pause does not block a RealHS step")
    _ = fresh.apply(.realHSUp, phase: .keyUp)

    var model = PreviewUbmBehavior()
    model.realHSCeiling = 110
    let blocked = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 100 && !blocked.realHSChanged && !blocked.realHSExceedsCeiling, "110 ceiling has no detent above 100")
    _ = model.apply(.realHSUp, phase: .keyUp)
    model.realHS = 105
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 100, "105 under a 110 ceiling regularizes down to 100")
    _ = model.apply(.realHSUp, phase: .keyUp)

    model.realHSCeiling = 400
    model.realHS = 30
    var down: [Int] = [model.realHS]
    for _ in 0..<3 {
        _ = model.apply(.realHSDown, phase: .keyDown)
        down.append(model.realHS)
        _ = model.apply(.realHSDown, phase: .keyUp)
    }
    require(down == [30, 25, 25, 25], "floor 25 \(down)")

    model.realHS = 26
    _ = model.apply(.realHSDown, phase: .keyDown)
    require(model.realHS == 25, "off-grid 26 lands on 25")
    _ = model.apply(.realHSDown, phase: .keyUp)
    model.realHS = 105
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 125, "105 up lands on 125")
    _ = model.apply(.realHSUp, phase: .keyUp)
    model.realHS = 105
    _ = model.apply(.realHSDown, phase: .keyDown)
    require(model.realHS == 100, "105 down lands on 100")
    _ = model.apply(.realHSDown, phase: .keyUp)

    model.realHSCeiling = 90
    model.realHS = 75
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 75 && !model.apply(.realHSUp, phase: .keyRepeat, elapsedMilliseconds: 5_000).realHSChanged, "ceiling 90 stops at 75")
    _ = model.apply(.realHSUp, phase: .keyUp)
    _ = model.apply(.realHSDown, phase: .keyDown)
    model.realHS = 75
    let toward = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 75 && !toward.realHSExceedsCeiling, "dual key does not walk through 100 past the ceiling")
    _ = model.apply(.realHSDown, phase: .keyUp)
    _ = model.apply(.realHSUp, phase: .keyUp)

    model.realHSCeiling = 200
    model.realHS = 198
    let onto = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 200 && onto.realHSChanged && !onto.realHSExceedsCeiling, "198 up lands on 200")
    require(model.hiSpeed == 1, "RealHS does not touch HiSpeed")
    _ = model.apply(.realHSUp, phase: .keyUp)
    require(!model.clampRealHSToCeiling() && model.realHS == 200, "200 is not above the ceiling")

    model.realHS = 100
    model.realHSCeiling = 80
    require(model.realHS == 100, "writing the ceiling does not clamp")
    require(model.clampRealHSToCeiling() && model.realHS == 75, "80 ceiling snaps down to the 75 detent")
    model.realHSCeiling = 10
    model.realHS = 30
    require(model.clampRealHSToCeiling() && model.realHS == 10, "a ceiling below 25 is written as itself")

    model.realHSCeiling = 200
    model.realHS = 175
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 200, "175 climbs to 200")
    _ = model.apply(.realHSUp, phase: .keyUp)
    require(model.realHS == 200 && !model.apply(.realHSUp, phase: .keyDown).realHSChanged, "200 is the last detent under this ceiling")
    _ = model.apply(.realHSUp, phase: .keyUp)
    model.realHS = 125
    _ = model.apply(.realHSDown, phase: .keyDown)
    model.realHS = 125
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 100, "both keys above 100 step back to the center")
}

private func testRuntimeCeilingReaches400() {
    var model = PreviewUbmBehavior()
    require(model.realHSCeiling == 400, "fresh ceiling")
    for step in 1...12 {
        let action = model.apply(.realHSUp, phase: .keyDown)
        require(model.realHS == 100 + step * 25 && action.realHSChanged, "step \(step) landed on \(model.realHS)")
        _ = model.apply(.realHSUp, phase: .keyUp)
    }
    require(model.realHS == 400, "key 4 stopped at \(model.realHS)")
    let held = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 400 && !held.realHSChanged && !held.realHSExceedsCeiling, "another press left \(model.realHS)")
    _ = model.apply(.realHSUp, phase: .keyUp)
}

private func testScratchPlayers() {
    var model = PreviewUbmBehavior()
    let expected: [PreviewUbmScratchPlayers] = [
        PreviewUbmScratchPlayers(player1: .left, player2: .right),
        PreviewUbmScratchPlayers(player1: .right, player2: .right),
        PreviewUbmScratchPlayers(player1: .left, player2: .left),
        PreviewUbmScratchPlayers(player1: .right, player2: .left),
    ]
    for (index, players) in expected.enumerated() {
        require(model.scratchRaw == index, "scratch raw \(model.scratchRaw)")
        require(model.scratchPlayers == players, "scratch players \(index)")
        require(model.scratchBit0 == (index & 1 != 0) && model.scratchBit1 == (index & 2 != 0), "scratch bits")
        let action = model.apply(.cycleScratch, phase: .keyDown)
        require(action.layoutChanged && action.soundChanged == false, "scratch only changes layout")
        _ = model.apply(.cycleScratch, phase: .keyUp)
    }
    require(model.scratchRaw == 0, "scratch wraps")
    model.scratchRaw = 9
    require(model.scratchPlayers == nil, "unmapped scratch raw")
}

private func testInfoBits() {
    var model = PreviewUbmBehavior()
    func mask(_ model: PreviewUbmBehavior) -> (Bool, Bool, Bool) {
        (model.showsPlayInfo, model.showsSongInfo, model.showsOptionInfo)
    }
    require(mask(model) == (true, false, false), "raw 1 is play only")
    _ = model.apply(.cycleInfo, phase: .keyDown)
    _ = model.apply(.cycleInfo, phase: .keyUp)
    require(model.infoRaw == 6 && mask(model) == (false, true, true), "raw 6 is song+option")
    _ = model.apply(.cycleInfo, phase: .keyDown)
    require(model.infoRaw == 7 && mask(model) == (true, true, true), "raw 7 is all")
    _ = model.apply(.cycleInfo, phase: .keyUp)
    _ = model.apply(.cycleInfo, phase: .keyDown)
    require(model.infoRaw == 0 && mask(model) == (false, false, false), "raw 0 is none")
}

private func testSoundPredicateAndEffects() {
    var model = PreviewUbmBehavior()
    func allowed(_ model: PreviewUbmBehavior) -> [PreviewUbmAudibleKind] {
        [PreviewUbmAudibleKind.bgm, .key, .mine].filter { model.allows($0) }
    }
    require(allowed(model) == [.bgm, .key], "default key+bgm")
    model.sound = .bgm
    require(allowed(model) == [.bgm], "bgm only")
    model.sound = .key
    require(allowed(model) == [.key], "key only")
    model.sound = .mine
    require(allowed(model) == [.mine], "mine only")
    model.sound = .keyBGMAndMine
    require(allowed(model) == [.bgm, .key, .mine], "all layers")

    model.effectsRaw = 0
    require(!model.showsJudgment && !model.showsBomb && !model.showsBeam, "effects 0")
    model.effectsRaw = 1
    require(model.showsJudgment && !model.showsBomb && !model.showsBeam, "effects 1")
    model.effectsRaw = 3
    require(model.showsJudgment && model.showsBomb && !model.showsBeam, "effects 3")
    model.effectsRaw = 7
    require(model.showsJudgment && model.showsBomb && model.showsBeam, "effects 7")
}

private func testPauseSeekDoesNotEmitSound() {
    let measures = PreviewUbmMeasures(starts: [0, 4, 7, 12])
    var playing = PreviewUbmBehavior()
    playing.canSeek = true
    let heard = playing.apply(.seekDown, phase: .keyDown, currentBeat: 5, measures: measures)
    require(heard.seek?.measure == 2 && heard.seek?.beat == 7, "playing seek \(String(describing: heard.seek))")
    require(heard.seek?.emitsSound == true && heard.playback == nil && !playing.paused, "playing seek may sound")

    var paused = PreviewUbmBehavior()
    paused.canSeek = true
    _ = paused.apply(.togglePause, phase: .keyDown)
    let silent = paused.apply(.seekDown, phase: .keyDown, currentBeat: 5, measures: measures)
    require(paused.paused, "stays paused")
    require(silent.playback == nil, "seek does not resume")
    require(silent.seek?.measure == 2 && silent.seek?.beat == 7, "paused still moves")
    require(silent.seek?.emitsSound == false, "paused seek does not emit sound")

    var closed = PreviewUbmBehavior()
    let blocked = closed.apply(.seekHome, phase: .keyDown, currentBeat: 5, measures: measures)
    require(blocked.isEmpty, "seek without a chart")
}

private func testVariableMeterSeek() {
    // 小节长 4、3、5、0.5。均匀 4 拍会把 7.2 当成第 1 小节，向下会落到 8。
    let measures = PreviewUbmMeasures(starts: [0, 4, 7, 12, 12.5])
    var model = PreviewUbmBehavior()
    model.canSeek = true
    let beat = 7.2
    require(measures.measureIndex(at: beat) == 2, "7.2 sits in the 5-beat bar")

    let down = model.apply(.seekDown, phase: .keyDown, currentBeat: beat, measures: measures)
    require(down.seek?.measure == 3 && down.seek?.beat == 12, "down one content bar \(String(describing: down.seek))")
    _ = model.apply(.seekDown, phase: .keyUp)

    let up = model.apply(.seekUp, phase: .keyDown, currentBeat: beat, measures: measures)
    require(up.seek?.measure == 1 && up.seek?.beat == 4, "up one content bar")
    _ = model.apply(.seekUp, phase: .keyUp)

    let pageDown = model.apply(.seekPageDown, phase: .keyDown, currentBeat: beat, measures: measures)
    require(pageDown.seek?.measure == 4 && pageDown.seek?.beat == 12.5, "page down clamps to the last bar")
    _ = model.apply(.seekPageDown, phase: .keyUp)

    let pageUp = model.apply(.seekPageUp, phase: .keyDown, currentBeat: beat, measures: measures)
    require(pageUp.seek?.measure == 0 && pageUp.seek?.beat == 0, "page up clamps to 0")
    _ = model.apply(.seekPageUp, phase: .keyUp)

    let home = model.apply(.seekHome, phase: .keyDown, currentBeat: 12.4, measures: measures)
    require(home.seek?.measure == 0 && home.seek?.beat == 0, "home")
    _ = model.apply(.seekHome, phase: .keyUp)
    let end = model.apply(.seekEnd, phase: .keyDown, currentBeat: 0.2, measures: measures)
    require(end.seek?.measure == 4 && end.seek?.beat == 12.5, "end is the last content bar, not beat+16")

    let before = model.apply(.seekUp, phase: .keyDown, currentBeat: 0, measures: measures)
    require(before.seek?.measure == 0 && before.seek?.beat == 0, "up at the start stays")
    let after = model.apply(.seekDown, phase: .keyDown, currentBeat: 20, measures: measures)
    require(after.seek?.measure == 4, "down past the end stays on the last bar")

    let wheel = model.seekByMeasures(-1, currentBeat: beat, measures: measures)
    require(wheel.seek?.measure == 1 && wheel.seek?.beat == 4, "wheel uses the same bar map")

    let empty = model.apply(.seekEnd, phase: .keyDown, currentBeat: 3, measures: PreviewUbmMeasures())
    require(empty.isEmpty, "empty bar list")
}

private func testSpaceReloadLatch() {
    var model = PreviewUbmBehavior()
    model.hasReloadPath = true
    require(model.apply(.spaceReload, phase: .keyDown).isEmpty, "press does not reload")
    require(model.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 499).isEmpty, "499 ms holds")
    let once = model.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 500)
    require(once.reloadChart && once.seek == nil && once.playback == nil, "500 ms reloads once")
    require(model.paused == false, "reload does not invent a transport change")
    require(
        model.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 2_000).isEmpty,
        "holding longer does not reload again"
    )
    _ = model.apply(.spaceReload, phase: .keyUp)
    require(model.apply(.spaceReload, phase: .keyDown).isEmpty, "second press waits again")
    let again = model.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 500)
    require(again.reloadChart, "release arms another reload")

    var missing = PreviewUbmBehavior()
    _ = missing.apply(.spaceReload, phase: .keyDown)
    require(missing.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 500).isEmpty, "empty path does not reload")
    missing.hasReloadPath = true
    require(
        missing.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 800).isEmpty,
        "the latch is already consumed for this hold"
    )
    _ = missing.apply(.spaceReload, phase: .keyUp)
    _ = missing.apply(.spaceReload, phase: .keyDown)
    require(missing.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 500).reloadChart, "next hold can reload")

    var early = PreviewUbmBehavior()
    early.hasReloadPath = true
    _ = early.apply(.spaceReload, phase: .keyDown)
    _ = early.apply(.spaceReload, phase: .keyUp)
    require(early.apply(.spaceReload, phase: .keyRepeat, elapsedMilliseconds: 500).isEmpty, "repeat without a hold")
}

private func testHoldRepeatSchedule() {
    var model = PreviewUbmBehavior()
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 1.25, "first down counts")
    for _ in 0..<40 {
        require(
            model.apply(.hiSpeedUp, phase: .keyRepeat, elapsedMilliseconds: 10_000).isEmpty,
            "HiSpeed repeat does not step"
        )
    }
    require(model.hiSpeed == 1.25, "held HiSpeed stays on the first detent")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    _ = model.apply(.hiSpeedUp, phase: .keyDown)
    require(model.hiSpeed == 1.5, "release then press moves one more detent")
    _ = model.apply(.hiSpeedUp, phase: .keyUp)
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 125, "first RealHS press")
    for _ in 0..<40 {
        require(model.apply(.realHSUp, phase: .keyRepeat, elapsedMilliseconds: 50_000).isEmpty, "RealHS repeat does not step")
    }
    require(model.realHS == 125, "held RealHS stays")
    _ = model.apply(.realHSUp, phase: .keyUp)
    _ = model.apply(.realHSUp, phase: .keyDown)
    require(model.realHS == 150, "release then press moves RealHS")

    let second = PreviewUbmBehavior.repeatDeadline(index: 1)
    require(abs(second - (50 + 50 / 1.3)) < 0.000_001, "seek repeat still accelerates \(second)")

    var home = PreviewUbmBehavior()
    home.canSeek = true
    let measures = PreviewUbmMeasures(starts: [0, 4, 8])
    _ = home.apply(.seekHome, phase: .keyDown, currentBeat: 5, measures: measures)
    let repeated = home.apply(.seekHome, phase: .keyRepeat, elapsedMilliseconds: 50, currentBeat: 5, measures: measures)
    require(repeated.isEmpty, "Home is not on the 50 ms repeater")

    var seek = PreviewUbmBehavior()
    seek.canSeek = true
    let firstSeek = seek.apply(.seekDown, phase: .keyDown, currentBeat: 1, measures: measures)
    require(firstSeek.seek?.measure == 1 && firstSeek.seek?.beat == 4, "first Down leaves bar 0")
    let seekRepeat = seek.apply(
        .seekDown,
        phase: .keyRepeat,
        elapsedMilliseconds: 50,
        currentBeat: 4,
        measures: measures
    )
    require(seekRepeat.seek?.measure == 2 && seekRepeat.seek?.beat == 8, "Down repeats on the 50 ms schedule")
}

private func testCommandCharactersDriveState() {
    var model = PreviewUbmBehavior()
    model.canSeek = true
    model.hasReloadPath = true
    model.realHSCeiling = 150
    let measures = PreviewUbmMeasures(starts: [0, 4, 7, 12])

    func mapped(_ characters: String, keyCode: UInt16 = 0, keypad: Bool = false, command: Bool = false) -> PreviewUbmCommand? {
        PreviewUbmBehavior.command(for: characters, keyCode: keyCode, isKeypad: keypad, commandModifier: command)
    }

    let digit1 = mapped("1", keyCode: 18)
    require(digit1 == .hiSpeedDown, "digit 1")
    _ = model.apply(digit1!, phase: .keyDown)
    require(model.hiSpeed == 0.75, "mapped 1 changes HiSpeed")
    _ = model.apply(digit1!, phase: .keyUp)

    require(mapped("1", keyCode: 83, keypad: true) == .hiSpeedDown, "keypad 1 uses the same character")
    require(mapped("", keyCode: 126, keypad: true) == nil, "keypad without characters is not guessed")
    require(mapped("", keyCode: 126) == nil, "up-arrow keyCode alone is not guessed")
    require(mapped("!", keyCode: 18) == nil, "shifted character is not a digit")
    require(mapped("F1") == nil && mapped("10") == nil, "literal names are not keys")
    require(mapped("5", command: true) == nil, "command modifier yields no command")
    let bgaBefore = model.bgaRaw
    require(bgaBefore == 3, "bga untouched")

    let five = mapped("5", keyCode: 0)
    _ = model.apply(five!, phase: .keyDown)
    require(model.bgaRaw == 4, "mapped 5 cycles BGA")
    _ = model.apply(five!, phase: .keyUp)

    let f1 = mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.f1), keyCode: 122)
    _ = model.apply(f1!, phase: .keyDown)
    require(model.sound == .mine, "F1 scalar cycles sound")
    _ = model.apply(f1!, phase: .keyUp)

    let up = mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.up), keyCode: 9_999)
    let moved = model.apply(up!, phase: .keyDown, currentBeat: 8, measures: measures)
    require(moved.seek?.measure == 1 && moved.seek?.beat == 4, "up scalar seeks one bar")
    _ = model.apply(up!, phase: .keyUp)

    let page = mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.pageDown), keyCode: 121)
    let paged = model.apply(page!, phase: .keyDown, currentBeat: 1, measures: measures)
    require(paged.seek?.measure == 3 && paged.seek?.beat == 12, "page down scalar clamps a +4 bar jump")
    _ = model.apply(page!, phase: .keyUp)

    let four = mapped("4", keyCode: 21)
    let raised = model.apply(four!, phase: .keyDown)
    require(model.realHS == 125 && raised.realHSChanged, "mapped 4 moves one 0.25x detent")
    _ = model.apply(four!, phase: .keyUp)

    let zero = mapped("0")
    let paused = model.apply(zero!, phase: .keyDown)
    require(model.paused && paused.playback == .pause && paused.seek == nil, "mapped 0 pauses")
    _ = model.apply(zero!, phase: .keyUp)

    let space = mapped(" ")
    _ = model.apply(space!, phase: .keyDown)
    require(model.apply(space!, phase: .keyRepeat, elapsedMilliseconds: 500).reloadChart, "mapped space reloads at 500 ms")

    require(mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.down)) == .seekDown, "down")
    require(mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.pageUp)) == .seekPageUp, "page up")
    require(mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.pageDown)) == .seekPageDown, "page down")
    require(mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.home)) == .seekHome, "home")
    require(mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.end)) == .seekEnd, "end")
    require(mapped(PreviewUbmFunctionScalar.character(PreviewUbmFunctionScalar.f2)) == .toggleAutoSeparate, "f2")
    require(mapped(" ") == .spaceReload, "space")
    require(mapped("0") == .togglePause && mapped("9") == .cycleInfo, "0 and 9")
    require(mapped("8") == .cycleScratch && mapped("6") == .cycleEffects && mapped("7") == .toggleAlwaysOnTop, "6 7 8")
    require(mapped("2") == .hiSpeedUp && mapped("3") == .realHSDown && mapped("4") == .realHSUp, "2 3 4")
}

private func testSendableCopiesDoNotShareMutation() {
    let empty = send(PreviewUbmAction.none)
    require(empty.isEmpty && empty.seek == nil && empty.playback == nil, "shared none is an empty value")

    var model = send(PreviewUbmBehavior())
    model.realHSCeiling = 140
    model.canSeek = true
    let copy = send(model)
    model.realHSCeiling = 100
    model.canSeek = false
    require(copy.realHSCeiling == 140 && copy.canSeek, "a sent behavior is a separate copy")
    require(model.realHSCeiling == 100 && !model.canSeek, "the original binding stays put")

    let measures = send(PreviewUbmMeasures(starts: [0, 4, 7]))
    require(measures.measureIndex(at: 5) == 1, "a sent measure list still locates the bar")
    let seek = send(PreviewUbmSeek(measure: 1, beat: 4, emitsSound: false))
    require(seek.measure == 1 && seek.beat == 4 && !seek.emitsSound, "a sent seek keeps its fields")
    let players = send(copy.scratchPlayers)
    require(
        players == PreviewUbmScratchPlayers(player1: .left, player2: .right),
        "default scratch still copies as L/R"
    )
    require(send(PreviewUbmCommand.cycleScratch) == .cycleScratch, "commands cross as values")
}

private func send<T: Sendable>(_ value: T) -> T {
    value
}

private func require(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}
