import Foundation

struct InjectedSpan {
    var serial: UInt64 = 1
    var frames: UInt32
    var valid: UInt32
    var start: Double
    var chart: Double = 0
    var wall: Double = 0
    var rate: Double = 1
}

func decide(_ spans: [InjectedSpan], now: Double) -> PreviewHostSpanClock.Decision {
    PreviewHostSpanClock.decide(
        count: spans.count,
        now: now,
        serial: { spans[$0].serial },
        frameCount: { spans[$0].frames },
        validFrames: { spans[$0].valid },
        hostStart: { spans[$0].start }
    )
}

func project(_ span: InjectedSpan, _ sample: UInt32) -> (chart: Double, wall: Double) {
    let used = sample < span.valid ? sample : span.valid
    let chart = span.chart + Double(used) * span.rate / PreviewHostSpanClock.sourceRate
    let wall = span.wall + Double(used) / PreviewHostSpanClock.sourceRate
    return (chart, wall)
}

@main
struct ASSpanClockProbe {
    static func main() {
        var failed = 0
        func check(_ ok: Bool, _ name: String) {
            if !ok {
                failed += 1
                FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
            }
        }

        let rate = PreviewHostSpanClock.sourceRate
        check(PreviewHostSpanClock.historyCapacity == 1024, "capacity")
        check(decide([], now: 0) == .keepOrigin, "empty")
        check(PreviewHostSpanClock.endSample(frames: 256, valid: 100) == 100, "partial end is valid")
        check(PreviewHostSpanClock.endSample(frames: 256, valid: 99) == 99, "partial end is not valid-1")
        check(PreviewHostSpanClock.endSample(frames: 256, valid: 256) == 255, "full end is last legal sample")
        check(PreviewHostSpanClock.endSample(frames: 256, valid: 400) == 255, "valid above frames stays in span")
        check(PreviewHostSpanClock.endSample(frames: 256, valid: 0) == 0, "silence end")
        check(PreviewHostSpanClock.endSample(frames: 1, valid: 1) == 0, "one-frame full span")
        check(PreviewHostSpanClock.endSample(frames: 0, valid: 0) == 0, "zero frames")

        let future = InjectedSpan(frames: 256, valid: 256, start: 1, chart: 50, rate: 1)
        check(decide([future], now: 0.5) == .keepOrigin, "future span keeps origin")
        check(decide([future], now: 1) == .span(index: 0, sample: 0), "now at start is sample 0")

        let inside = InjectedSpan(frames: 256, valid: 256, start: 0, chart: 10, wall: 4, rate: 2)
        let insideNow = 10.0 / rate
        let insideDecision = decide([inside], now: insideNow)
        check(insideDecision == .span(index: 0, sample: 10), "interior sample")
        if case .span(_, let sample) = insideDecision {
            let point = project(inside, sample)
            check(point.chart == 10 + 10 * 2 / rate, "interior chart from this span")
            check(point.wall == 4 + Double(10) / rate, "interior wall from this span")
        }

        let played = InjectedSpan(frames: 256, valid: 256, start: 0, chart: 1, wall: 2, rate: 1)
        let ahead = InjectedSpan(frames: 256, valid: 256, start: 5, chart: 99, wall: 7, rate: 4)
        let held = decide([played, ahead], now: 1)
        check(held == .span(index: 0, sample: 255), "future live does not replace completed span")
        if case .span(let index, let sample) = held {
            let point = project(played, sample)
            check(index == 0 && point.chart != 99 && point.wall != 7, "does not borrow future chart")
            check(point.chart == 1 + 255 / rate, "full span freezes on last legal sample")
        }

        let partial = InjectedSpan(frames: 256, valid: 100, start: 0, chart: 3, wall: 8, rate: 1)
        let partialDecision = decide([partial], now: 1)
        check(partialDecision == .span(index: 0, sample: 100), "partial freeze uses valid, not valid-1")
        if case .span(_, let sample) = partialDecision {
            let point = project(partial, sample)
            check(point.chart == 3 + 100 / rate, "partial chart is the valid end")
            check(point.wall == 8 + 100 / rate, "partial wall is the valid end")
            check(point.chart != 3 + 99 / rate, "partial chart is not the previous sample")
        }

        let underrunStart = 128.0 / rate
        let head = InjectedSpan(frames: 128, valid: 128, start: 0, chart: 8, wall: 1, rate: 1)
        let underrun = InjectedSpan(
            frames: 128, valid: 0, start: underrunStart, chart: 8 + 128 / rate, wall: 1 + 128 / rate, rate: 0
        )
        let underrunNow = underrunStart + 10 / rate
        let underrunDecision = decide([head, underrun], now: underrunNow)
        check(underrunDecision == .span(index: 1, sample: 10), "underrun stays on its own span")
        if case .span(let index, let sample) = underrunDecision {
            let point = project(underrun, sample)
            check(index == 1 && point.chart == underrun.chart && point.wall == underrun.wall, "underrun does not keep the old rate")
        }

        let beforeSeek = InjectedSpan(frames: 256, valid: 256, start: 0, chart: 4, wall: 9, rate: 1)
        let seek = InjectedSpan(frames: 256, valid: 256, start: 1, chart: 0, wall: 0, rate: 2)
        let gap = decide([beforeSeek, seek], now: 0.5)
        check(gap == .span(index: 0, sample: 255), "seek gap freezes the previous epoch")
        if case .span(_, let sample) = gap {
            let point = project(beforeSeek, sample)
            check(point.chart != 0 && point.wall != 0, "seek chart is not sampled early")
        }

        let nextStart = 256.0 / rate
        let first = InjectedSpan(frames: 256, valid: 256, start: 0, chart: 0, wall: 0, rate: 1)
        let second = InjectedSpan(frames: 256, valid: 256, start: nextStart, chart: 100, wall: 3, rate: 4)
        let crossed = decide([first, second], now: nextStart + 20 / rate)
        check(crossed == .span(index: 1, sample: 20), "new epoch uses its own sample")
        if case .span(_, let sample) = crossed {
            let point = project(second, sample)
            check(point.chart == 100 + 20 * 4 / rate, "rate boundary does not extend the old slope")
            check(point.wall == 3 + 20 / rate, "wall comes from the same span")
        }
        check(decide([first, second], now: nextStart) == .span(index: 1, sample: 0), "exact boundary enters the next span")

        let long = InjectedSpan(frames: 48_000, valid: 48_000, start: 0, chart: 0, rate: 1)
        let newer = InjectedSpan(frames: 256, valid: 256, start: 0.5, chart: 20, wall: 6, rate: 1)
        check(decide([long, newer], now: 0.5) == .span(index: 1, sample: 0), "newer containing span wins")

        let hidden = InjectedSpan(serial: 0, frames: 256, valid: 256, start: 0, chart: 1, rate: 1)
        check(decide([hidden, future], now: 0.5) == .keepOrigin, "unpublished serial does not count")

        let wayPast = decide([played], now: 100)
        check(wayPast == .span(index: 0, sample: 255), "past the end does not extrapolate")

        if failed != 0 {
            FileHandle.standardError.write(Data("\(failed) failed\n".utf8))
            exit(1)
        }
        print("as-span-clock-probe ok")
    }
}
