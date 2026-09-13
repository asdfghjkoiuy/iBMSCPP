import Foundation

/// 主编辑器同一套 BMP 侧栏 ↔ BMSON `bga.bga_header`。
/// 不套 `#BMPxx`。侧栏 `01` 是 id `1`。id `0`（`#BMP00`）不进侧栏。
enum BmsonBmpList {
    struct Header: Equatable {
        var id: Int
        var name: String
    }

    struct State: Equatable {
        var headers: [Header]
        var bgaEvents: [BmsonBeat.BgaEvent]
        var layerEvents: [BmsonBeat.BgaEvent]
        var poorEvents: [BmsonBeat.BgaEvent]
    }

    static func table(from headers: [Header]) -> [String: String] {
        var table: [String: String] = [:]
        for header in headers {
            table[BmsonChartMapping.bmpToken(id: header.id)] = header.name
        }
        return table
    }

    static func apply(
        _ edit: WavListEdit,
        headers: [Header],
        bgaEvents: [BmsonBeat.BgaEvent],
        layerEvents: [BmsonBeat.BgaEvent],
        poorEvents: [BmsonBeat.BgaEvent],
        synchronizeLabels: Bool
    ) -> State? {
        let names = padded(edit.names)
        if names.contains(where: hasNewline) {
            return nil
        }
        var nextBga = bgaEvents
        var nextLayer = layerEvents
        var nextPoor = poorEvents
        if synchronizeLabels && !edit.labelSwaps.isEmpty {
            for pair in edit.labelSwaps {
                guard let first = BmsonChartMapping.bmpId(token: pair.0),
                      let second = BmsonChartMapping.bmpId(token: pair.1),
                      first > 0, second > 0
                else {
                    return nil
                }
                remap(&nextBga, first: first, second: second)
                remap(&nextLayer, first: first, second: second)
                remap(&nextPoor, first: first, second: second)
            }
        }
        var byId: [Int: String] = [:]
        for header in headers where header.id == 0 {
            byId[0] = header.name
        }
        for index in names.indices {
            let id = index + 1
            let name = names[index]
            if !name.isEmpty {
                byId[id] = name
            }
        }
        let used = Set((nextBga + nextLayer + nextPoor).map(\.id))
        for id in used where byId[id] == nil {
            byId[id] = headers.first(where: { $0.id == id })?.name ?? ""
        }
        let nextHeaders = byId.keys.sorted().map { Header(id: $0, name: byId[$0] ?? "") }
        return State(
            headers: nextHeaders,
            bgaEvents: nextBga,
            layerEvents: nextLayer,
            poorEvents: nextPoor
        )
    }

    private static func remap(_ events: inout [BmsonBeat.BgaEvent], first: Int, second: Int) {
        for index in events.indices {
            if events[index].id == first {
                events[index].id = second
            } else if events[index].id == second {
                events[index].id = first
            }
        }
    }

    private static func padded(_ names: [String]) -> [String] {
        if names.count >= LegacyWavList.slotCount {
            return Array(names.prefix(LegacyWavList.slotCount))
        }
        return names + Array(repeating: "", count: LegacyWavList.slotCount - names.count)
    }

    private static func hasNewline(_ name: String) -> Bool {
        name.contains(where: { $0 == "\n" || $0 == "\r" })
    }
}
