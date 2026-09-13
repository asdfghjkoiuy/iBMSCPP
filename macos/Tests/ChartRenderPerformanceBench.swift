import AppKit
import Foundation

@main
struct ChartRenderPerformanceBench {
    static func main() {
        let measures = (0..<1_000).map { ChartMeasureSnapshot(measure: $0, start: Double($0 * 4), length: 4) }
        let events = (0..<100_000).map { index in
            ChartEventSnapshot(measure: index / 100, channel: index % 2 == 0 ? "11" : "12", token: "01", fractionNumerator: 0, fractionDenominator: 1, beat: Double(index) * 0.04, kind: "normalNote", sourceLine: index)
        }
        func endpoint(_ beat: Double, _ line: Int) -> LongNoteEndpointSnapshot {
            LongNoteEndpointSnapshot(measure: Int(beat / 4), fractionNumerator: 0, fractionDenominator: 1, beat: beat, token: "01", sourceLine: line)
        }
        let longs = (0..<20_000).map { index in
            let start = Double(index) * 0.18
            return LongNoteSnapshot(channel: "51", start: endpoint(start, index * 2), end: endpoint(start + 8, index * 2 + 1), encoding: "NT")
        }
        let layout = ChartLayout(snapshot: ChartSnapshot(events: events, measures: measures, diagnostics: [], editable: true, editingReason: ""), longNotes: LongNoteSnapshotSet(notes: longs, diagnostics: [], editable: true, editingReason: "", lnobjToken: ""), side: .onePlayer, pixelsPerQuarterBeat: 48, division: 16)
        let views = (0..<120).map { CGRect(x: 0, y: CGFloat($0 * 480), width: 600, height: 720) }
        for view in views { _ = layout.visibleLongNoteRects(in: view); _ = layout.hitTestLongNote(CGPoint(x: 70, y: view.midY)) }
        let samples = views.map { view -> Double in
            let start = DispatchTime.now().uptimeNanoseconds
            _ = layout.visibleLongNoteRects(in: view)
            _ = layout.hitTestLongNote(CGPoint(x: 70, y: view.midY))
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }.sorted()
        let median = samples[samples.count / 2]
        let p95 = samples[min(samples.count - 1, Int(Double(samples.count - 1) * 0.95))]
        print("ChartRenderPerformanceBench operations=120 events=100000 longs=20000 median_ms=\(median) p95_ms=\(p95)")
    }
}
