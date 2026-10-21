import Foundation

struct MyO2Note: Equatable, Sendable {
    var vPosition: Double
    var columnIndex: Int
    var value: Int
    var longNote: Bool
    var length: Double
    var hidden: Bool
}

struct MyO2Adjustment: Equatable, Sendable {
    var measure: Int
    var columnIndex: Int
    var columnName: String
    var grid: String
    var longNote: Bool
    var hidden: Bool
    var adjTo64: Bool
    var d64: Int
    var d48: Int

    var serialized: String {
        "\(measure)_\(columnIndex)_\(columnName)_\(grid)_\(vbBool(longNote))_\(vbBool(hidden))_\(vbBool(adjTo64))_\(d64)_\(d48)"
    }
}

enum LegacyMyO2 {
    static let identifiers = [
        "01", "03", "04", "06", "07", "08", "09",
        "16", "11", "12", "13", "14", "15", "18", "19",
        "26", "21", "22", "23", "24", "25", "28", "29",
        "36", "31", "32", "33", "34", "35", "38", "39",
        "46", "41", "42", "43", "44", "45", "48", "49",
        "56", "51", "52", "53", "54", "55", "58", "59",
        "66", "61", "62", "63", "64", "65", "68", "69",
        "76", "71", "72", "73", "74", "75", "78", "79",
        "86", "81", "82", "83", "84", "85", "88", "89"
    ]

    static let titles: [Int: String] = [
        0: "Measure", 1: "SCROLL", 2: "BPM", 3: "STOP",
        5: "A1", 6: "A2", 7: "A3", 8: "A4", 9: "A5", 10: "A6", 11: "A7", 12: "A8",
        14: "D1", 15: "D2", 16: "D3", 17: "D4", 18: "D5", 19: "D6", 20: "D7", 21: "D8",
        23: "BGA", 24: "LAYER", 25: "POOR", 27: "B"
    ]

    static let identifiersByColumn: [Int: Int] = [
        1: 99, 2: 3, 3: 9,
        5: 16, 6: 11, 7: 12, 8: 13, 9: 14, 10: 15, 11: 18, 12: 19,
        14: 21, 15: 22, 16: 23, 17: 24, 18: 25, 19: 28, 20: 29, 21: 26,
        23: 4, 24: 7, 25: 6, 27: 1
    ]

    static func shortChannel(for column: Int) -> String {
        if column == EditorColumn.scroll { return "SC" }
        let identifier = identifiersByColumn[column] ?? 0
        return add2Zeros(identifier)
    }

    static func channel(for note: MyO2Note) -> String {
        if note.columnIndex == EditorColumn.scroll { return "SC" }
        var base = identifiersByColumn[note.columnIndex] ?? 0
        if note.columnIndex == EditorColumn.bpm {
            let bpm = note.value
            if Double(bpm) / 10_000 != Double(bpm / 10_000) || bpm >= 2_560_000 || bpm < 0 {
                base += 5
            }
        }
        if (EditorColumn.a1...EditorColumn.a8).contains(note.columnIndex) {
            if note.longNote { return String((base + 0x50 - 10), radix: 16).uppercased() }
            if note.hidden { return String((base + 0x30 - 10), radix: 16).uppercased() }
        }
        if (EditorColumn.d1...EditorColumn.d8).contains(note.columnIndex) {
            if note.longNote { return String((base + 0x60 - 20), radix: 16).uppercased() }
            if note.hidden { return String((base + 0x40 - 20), radix: 16).uppercased() }
        }
        return add2Zeros(base)
    }

    static func isChannelLongNote(_ channel: String) -> Bool {
        let value = Int(Double(channel) ?? 0)
        return value >= 50 && value < 90
    }

    static func isChannelHidden(_ channel: String) -> Bool {
        let value = Int(Double(channel) ?? 0)
        return (value >= 30 && value < 50) || (value >= 70 && value < 90)
    }

    static func gcd(_ first: Double, _ second: Double, limit: Double) -> Double {
        var maxValue = max(first, second)
        var minValue = min(first, second)
        while minValue >= limit {
            let remainder = maxValue - floor(maxValue / minValue) * minValue
            maxValue = minValue
            minValue = remainder
        }
        return maxValue
    }

    static func measureAtDisplacement(_ vPosition: Double, measureLength: Double = 192) -> Int {
        max(0, Int(floor(vPosition / measureLength)))
    }

    static func constBPM(_ notes: [MyO2Note], target: Int, ntInput: Bool) -> [MyO2Note] {
        var next = notes
        guard !next.isEmpty else { return next }
        var time = 0.0
        var cursor = 0.0
        var bpm = next[0].value
        if !ntInput {
            for index in 1..<next.count {
                if next[index].columnIndex == EditorColumn.bpm {
                    if let step = finiteQuotient(next[index].vPosition - cursor, bpm: bpm) {
                        time += step
                    }
                    cursor = next[index].vPosition
                    if next[index].value > 0 {
                        bpm = next[index].value
                    }
                } else if let step = finiteQuotient(next[index].vPosition - cursor, bpm: bpm) {
                    let mapped = Double(target) * (time + step)
                    if mapped.isFinite {
                        next[index].vPosition = mapped
                    }
                }
            }
        } else {
            for index in 1..<next.count {
                if next[index].columnIndex == EditorColumn.bpm {
                    if let step = finiteQuotient(next[index].vPosition - cursor, bpm: bpm) {
                        time += step
                    }
                    cursor = next[index].vPosition
                    if next[index].value > 0 {
                        bpm = next[index].value
                    }
                } else if next[index].length == 0 {
                    if let step = finiteQuotient(next[index].vPosition - cursor, bpm: bpm) {
                        let mapped = Double(target) * (time + step)
                        if mapped.isFinite {
                            next[index].vPosition = mapped
                        }
                    }
                } else if let startStep = finiteQuotient(next[index].vPosition - cursor, bpm: bpm) {
                    let startTime = time + startStep
                    var time2 = time
                    var cursor2 = cursor
                    var bpm2 = bpm
                    var partner = index + 1
                    while partner < next.count, next[partner].vPosition < next[index].vPosition + next[index].length {
                        if next[partner].columnIndex == EditorColumn.bpm {
                            if let step = finiteQuotient(next[partner].vPosition - cursor2, bpm: bpm2) {
                                time2 += step
                            }
                            cursor2 = next[partner].vPosition
                            if next[partner].value > 0 {
                                bpm2 = next[partner].value
                            }
                        }
                        partner += 1
                    }
                    if let endStep = finiteQuotient(
                        next[index].vPosition + next[index].length - cursor2,
                        bpm: bpm2
                    ), startTime.isFinite {
                        let endTime = time2 + endStep
                        let mapped = Double(target) * startTime
                        let length = Double(target) * endTime - mapped
                        if mapped.isFinite, length.isFinite {
                            next[index].vPosition = mapped
                            next[index].length = length
                        }
                    }
                }
            }
        }
        next = next.filter { $0.vPosition < 0 || $0.columnIndex != EditorColumn.bpm }
        if !next.isEmpty {
            next[0].value = target
        }
        return next
    }

    /// `bpm <= 0` 或结果非有限时不除，避免后面 `Int` 转换崩溃。
    private static func finiteQuotient(_ numerator: Double, bpm: Int) -> Double? {
        guard bpm > 0, numerator.isFinite else { return nil }
        let value = numerator / Double(bpm)
        return value.isFinite ? value : nil
    }

    static func gridCheck(_ notes: [MyO2Note], ntInput: Bool, gridLimit: Double) -> [MyO2Adjustment] {
        let greatest = notes.dropFirst().map(\.vPosition).max() ?? 0
        let lastMeasure = measureAtDisplacement(greatest)
        var result: [MyO2Adjustment] = []
        if !ntInput {
            var lower = 1
            for measure in 0...lastMeasure {
                var upper = lower
                while upper < notes.count, measureAtDisplacement(notes[upper].vPosition) <= measure {
                    upper += 1
                }
                for identifier in identifiers {
                    var positions: [Double] = []
                    if lower < upper {
                        for index in lower..<upper {
                            let note = notes[index]
                            if channel(for: note) == identifier,
                               abs(note.vPosition - Double(measureAtDisplacement(note.vPosition)) * 192) > 0 {
                                positions.append(max(0, note.vPosition - Double(measure) * 192))
                            }
                        }
                    }
                    appendCheck(measure: measure, identifier: identifier, positions: positions, gridLimit: gridLimit, into: &result)
                }
                lower = upper
            }
        } else {
            for measure in 0...lastMeasure {
                for identifier in identifiers {
                    var positions: [Double] = []
                    for index in 1..<notes.count {
                        let note = notes[index]
                        if measureAtDisplacement(note.vPosition) > measure { break }
                        if channel(for: note) != identifier { continue }
                        if isChannelLongNote(identifier) != (note.length != 0) { continue }
                        if measureAtDisplacement(note.vPosition) == measure,
                           abs(note.vPosition - Double(measureAtDisplacement(note.vPosition)) * 192) > 0 {
                            positions.append(max(0, note.vPosition - Double(measure) * 192))
                        }
                        if note.length == 0 { continue }
                        let end = note.vPosition + note.length
                        if measureAtDisplacement(end) == measure, end - Double(measure) * 192 != 0 {
                            positions.append(max(0, end - Double(measure) * 192))
                        }
                    }
                    appendCheck(measure: measure, identifier: identifier, positions: positions, gridLimit: gridLimit, into: &result)
                }
            }
        }
        return result
    }

    static func gridAdjust(_ notes: [MyO2Note], adjustments: [MyO2Adjustment], ntInput: Bool) -> [MyO2Note] {
        var next = notes
        if !ntInput {
            for adjustment in adjustments {
                let step = adjustment.adjTo64 ? 3.0 : 4.0
                for index in 1..<next.count {
                    let note = next[index]
                    if measureAtDisplacement(note.vPosition) == adjustment.measure,
                       note.columnIndex == adjustment.columnIndex,
                       note.longNote == adjustment.longNote,
                       note.hidden == adjustment.hidden {
                        next[index].vPosition = Double(bankersRound(note.vPosition / step)) * step
                    }
                }
            }
        } else {
            for adjustment in adjustments {
                let step = adjustment.adjTo64 ? 3.0 : 4.0
                for index in 1..<next.count {
                    if (next[index].length != 0) != adjustment.longNote { continue }
                    var start = next[index].vPosition
                    var end = next[index].vPosition + next[index].length
                    if measureAtDisplacement(next[index].vPosition) == adjustment.measure,
                       next[index].columnIndex == adjustment.columnIndex,
                       next[index].hidden == adjustment.hidden {
                        start = Double(bankersRound(next[index].vPosition / step)) * step
                    }
                    if next[index].length > 0,
                       measureAtDisplacement(next[index].vPosition + next[index].length) == adjustment.measure,
                       next[index].columnIndex == adjustment.columnIndex,
                       next[index].hidden == adjustment.hidden {
                        end = Double(bankersRound((next[index].vPosition + next[index].length) / step)) * step
                    }
                    next[index].vPosition = start
                    if next[index].length > 0 {
                        next[index].length = end - next[index].vPosition
                    }
                }
            }
        }
        return next
    }

    static func parseAdjustments(_ lines: [String]) -> [MyO2Adjustment] {
        lines.compactMap { line in
            let parts = line.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 9 else { return nil }
            return MyO2Adjustment(
                measure: Int(Double(parts[0]) ?? 0),
                columnIndex: Int(Double(parts[1]) ?? 0),
                columnName: parts[2],
                grid: parts[3],
                longNote: (Double(parts[4]) ?? 0) != 0,
                hidden: (Double(parts[5]) ?? 0) != 0,
                adjTo64: (Double(parts[6]) ?? 0) != 0,
                d64: Int(Double(parts[7]) ?? 0),
                d48: Int(Double(parts[8]) ?? 0)
            )
        }
    }

    private static func appendCheck(
        measure: Int,
        identifier: String,
        positions: [Double],
        gridLimit: Double,
        into result: inout [MyO2Adjustment]
    ) {
        var divisor = 192.0
        for position in positions {
            divisor = gcd(divisor, position, limit: gridLimit)
        }
        guard divisor.isFinite, divisor > 0, divisor < 3 else { return }
        let gridCells = 192 / divisor
        guard gridCells.isFinite else { return }
        var d48 = 0
        var d64 = 0
        for position in positions {
            guard position.isFinite else { continue }
            d48 += bankersRound(abs(position - Double(bankersRound(position / 4)) * 4))
            d64 += bankersRound(abs(position - Double(bankersRound(position / 3)) * 3))
        }
        let column = EditorColumn.index(forChannel: identifier)
        result.append(MyO2Adjustment(
            measure: measure,
            columnIndex: column,
            columnName: titles[column] ?? "B\(max(1, column - EditorColumn.bgm + 1))",
            grid: String(bankersRound(gridCells)),
            longNote: isChannelLongNote(identifier),
            hidden: isChannelHidden(identifier),
            adjTo64: d48 > d64,
            d64: d64,
            d48: d48
        ))
    }

    private static func add2Zeros(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

private func vbBool(_ value: Bool) -> Int {
    value ? -1 : 0
}

private func bankersRound(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int(exactly: value.rounded(.toNearestOrEven)) ?? 0
}
