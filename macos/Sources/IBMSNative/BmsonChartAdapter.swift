import Foundation

/// 把 `BmsONEDocument` 转成主编辑器能画的 snapshot。不改 BMS 模型。
enum BmsonChartAdapter {
    static func display(
        from document: BmsONEDocument,
        shownChannels: [Bool]? = nil,
        viewMode: BmsONEViewMode? = nil
    ) -> MainEditorChartSource {
        let mapping = input(from: document)
        let mode = viewMode ?? BmsONEViewMode.resolve(mapping.modeHint)
        let channels = BmsonChannel.visibleChannels(mapping.channels, shown: shownChannels)
        let soundLast = mapping.channels.flatMap(\.notes).map { $0.y + max(0, $0.l) }.max() ?? 0
        let timingLast = (document.bpmNotes.map(\.y) + document.stopNotes.map(\.y)).max() ?? 0
        let bgaLast = (document.bgaEvents.map(\.y) + document.layerEvents.map(\.y) + document.poorEvents.map(\.y))
            .max() ?? 0
        let lastPulse = max(soundLast, max(timingLast, bgaLast))
        let measures = BmsonChartMapping.measures(
            lines: mapping.lines,
            lastPulse: lastPulse,
            resolution: mapping.resolution
        )
        let visible = BmsonChartMapping.visibleNotes(
            channels: channels,
            measures: measures,
            resolution: mapping.resolution,
            mode: mode
        )
        let laneNotes = BmsonChartMapping.soundLaneNotes(
            channels: channels,
            measures: measures,
            resolution: mapping.resolution,
            shown: shownChannels
        )
        let timing = BmsonChartMapping.visibleTiming(
            bpmNotes: document.bpmNotes.map { ($0.y, $0.v) },
            stopNotes: document.stopNotes.map { ($0.y, $0.v) },
            measures: measures,
            resolution: mapping.resolution
        )
        let bga = BmsonChartMapping.visibleBga(
            bgaEvents: document.bgaEvents.map { ($0.y, Int($0.identifier)) },
            layerEvents: document.layerEvents.map { ($0.y, Int($0.identifier)) },
            poorEvents: document.poorEvents.map { ($0.y, Int($0.identifier)) },
            measures: measures,
            resolution: mapping.resolution
        )
        let chart = ChartSnapshot(
            events: (visible + timing + bga + laneNotes).map { note in
                ChartEventSnapshot(
                    measure: note.measure,
                    channel: note.channel,
                    token: note.token,
                    fractionNumerator: pulseFraction(beat: note.beat, measures: measures, resolution: mapping.resolution).num,
                    fractionDenominator: pulseFraction(beat: note.beat, measures: measures, resolution: mapping.resolution).den,
                    beat: note.beat,
                    kind: note.kind,
                    sourceLine: note.identity
                )
            },
            measures: measures.map {
                ChartMeasureSnapshot(measure: $0.index, start: $0.start, length: $0.length)
            },
            diagnostics: [],
            editable: true,
            editingReason: ""
        )
        let longNotes = LongNoteSnapshotSet(
            notes: visible.filter { $0.kind == "longNote" }.map { note in
                LongNoteSnapshot(
                    channel: note.channel,
                    start: LongNoteEndpointSnapshot(
                        measure: note.measure,
                        fractionNumerator: pulseFraction(beat: note.beat, measures: measures, resolution: mapping.resolution).num,
                        fractionDenominator: pulseFraction(beat: note.beat, measures: measures, resolution: mapping.resolution).den,
                        beat: note.beat,
                        token: note.token,
                        sourceLine: note.identity
                    ),
                    end: LongNoteEndpointSnapshot(
                        measure: BmsonChartMapping.measureIndex(
                            beat: note.beat + note.lengthBeats,
                            in: measures
                        ),
                        fractionNumerator: pulseFraction(
                            beat: note.beat + note.lengthBeats,
                            measures: measures,
                            resolution: mapping.resolution
                        ).num,
                        fractionDenominator: pulseFraction(
                            beat: note.beat + note.lengthBeats,
                            measures: measures,
                            resolution: mapping.resolution
                        ).den,
                        beat: note.beat + note.lengthBeats,
                        token: note.token,
                        sourceLine: note.identity
                    ),
                    encoding: "bmson"
                )
            },
            diagnostics: [],
            editable: true,
            editingReason: "",
            lnobjToken: ""
        )
        var wavTable: [String: String] = [:]
        for (index, channel) in document.soundChannels.enumerated() {
            wavTable[BmsonChartMapping.wavToken(channelIndex: index)] = channel.name
        }
        var bmpTable: [String: String] = [:]
        for header in document.bgaHeaders {
            bmpTable[BmsonChartMapping.bmpToken(id: Int(header.identifier))] = header.name
        }
        let shownTitle = document.title.isEmpty ? "untitled.bmson" : document.title
        return MainEditorChartSource(
            chart: chart,
            longNotes: longNotes,
            wavTable: wavTable,
            bmpTable: bmpTable,
            headerBPM: document.initialBpm,
            headerFields: document.headerFields(),
            editableHeaderKeys: Set(BmsonHeaderMapping.editableKeys),
            canEditHeaderBPM: true,
            canWrite: true,
            canSave: true,
            canUndo: document.canUndo,
            canRedo: document.canRedo,
            statusLength: "BMSON \(document.soundChannels.count) ch",
            titleBPM: String(Int(document.initialBpm.rounded())),
            windowTitle: document.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? shownTitle,
            soundChannelNames: document.soundChannels.map(\.name),
            shownSoundChannels: shownChannels
        )
    }

    /// `Document::GetBarLines`：实线加后面铺开的 4 拍虚线。
    static func barPulses(from document: BmsONEDocument) -> [Int64] {
        let soundLast = document.soundChannels.flatMap(\.notes).map { $0.y + max(0, $0.l) }.max() ?? 0
        let timingLast = (document.bpmNotes.map(\.y) + document.stopNotes.map(\.y)).max() ?? 0
        let bgaLast = (document.bgaEvents.map(\.y) + document.layerEvents.map(\.y) + document.poorEvents.map(\.y))
            .max() ?? 0
        return Array(
            BmsonBarLine.displayed(
                lines: document.lines.map(\.y),
                lastPulse: max(soundLast, max(timingLast, bgaLast)),
                resolution: document.resolution
            ).all
        ).sorted()
    }

    static func insertPulse(
        measure: Int,
        slot: Int,
        division: Int,
        document: BmsONEDocument
    ) -> Int64 {
        let source = display(from: document)
        let start = source.chart.measures.first { $0.measure == measure }?.start ?? 0
        return BmsonChartMapping.pulse(
            measureStart: start,
            slot: slot,
            division: division,
            resolution: document.resolution
        )
    }

    private static func input(from document: BmsONEDocument) -> (
        resolution: Int,
        modeHint: String,
        lines: [Int64],
        channels: [BmsonChartMapping.ChannelInput]
    ) {
        (
            document.resolution,
            document.modeHint,
            document.lines.map(\.y),
            document.soundChannels.map { channel in
                BmsonChartMapping.ChannelInput(
                    name: channel.name,
                    notes: channel.notes.map {
                        BmsonChartMapping.NoteInput(x: $0.x, y: $0.y, l: $0.l, c: $0.c)
                    }
                )
            }
        )
    }

    private static func pulseFraction(
        beat: Double,
        measures: [BmsonChartMapping.MeasureBeat],
        resolution: Int
    ) -> (num: Int64, den: Int64) {
        let measure = measures.first {
            beat >= $0.start && beat < $0.start + $0.length
        }
        let startPulse = BmsonChartMapping.pulse(beat: measure?.start ?? 0, resolution: resolution)
        let pulse = BmsonChartMapping.pulse(beat: beat, resolution: resolution)
        return (max(0, pulse - startPulse), Int64(max(1, resolution)))
    }
}

struct MainEditorChartSource {
    var chart: ChartSnapshot
    var longNotes: LongNoteSnapshotSet
    var wavTable: [String: String]
    var bmpTable: [String: String] = [:]
    var headerBPM: Double
    var headerFields: [String: String] = [:]
    var editableHeaderKeys: Set<String> = []
    var canEditHeaderBPM: Bool = false
    var canWrite: Bool
    var canSave: Bool
    var canUndo: Bool
    var canRedo: Bool
    var statusLength: String
    var titleBPM: String
    var windowTitle: String
    var soundChannelNames: [String] = []
    var shownSoundChannels: [Bool]?
}
