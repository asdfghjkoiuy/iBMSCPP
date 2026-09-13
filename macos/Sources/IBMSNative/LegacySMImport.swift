import Foundation

struct SMImportedNote: Equatable, Sendable {
    var columnIndex: Int
    var vPosition: Double
    var length: Double
    var longNote: Bool
    var value: Int
}

struct SMImportResult: Equatable, Sendable {
    var title: String
    var artist: String
    var genre: String
    var playLevel: String
    var initialBPM: Int
    var bpmEvents: [(vPosition: Double, value: Int)]
    var notes: [SMImportedNote]
    var difficulties: [String]

    static func == (lhs: SMImportResult, rhs: SMImportResult) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.genre == rhs.genre
            && lhs.playLevel == rhs.playLevel
            && lhs.initialBPM == rhs.initialBPM
            && lhs.difficulties == rhs.difficulties
            && lhs.notes == rhs.notes
            && lhs.bpmEvents.elementsEqual(rhs.bpmEvents) { $0.vPosition == $1.vPosition && $0.value == $1.value }
    }
}

enum LegacySMImport {
    static let playableColumns = [EditorColumn.a1, EditorColumn.a2, EditorColumn.a3, EditorColumn.a4]
    static let defaultBPMValue = 1_200_000

    static func difficulties(in text: String) -> [String] {
        let joined = stripComments(text)
        let parts = splitKeepingEmpty(joined, separator: "#NOTES:")
        guard parts.count > 2 else { return [] }
        return parts.dropFirst().compactMap(difficultyLabel)
    }

    static func parse(_ text: String, difficulty: Int, convertToNT: Bool, lnobj: Int = 0) -> SMImportResult {
        let joined = stripComments(text)
        let labels = difficulties(in: text)
        var result = SMImportResult(
            title: "",
            artist: "",
            genre: "",
            playLevel: "",
            initialBPM: defaultBPMValue,
            bpmEvents: [],
            notes: [],
            difficulties: labels
        )
        let selected = labels.isEmpty ? 0 : min(max(0, difficulty), labels.count - 1)
        var current = 0
        for statement in splitKeepingEmpty(joined, separator: ";") {
            let line = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = line.uppercased()
            if upper.hasPrefix("#TITLE:") {
                result.title = String(line.dropFirst("#TITLE:".count))
            } else if upper.hasPrefix("#SUBTITLE:") {
                let subtitle = String(line.dropFirst("#SUBTITLE:".count))
                if !upper.hasSuffix("#SUBTITLE:") {
                    result.title += " " + subtitle
                }
            } else if upper.hasPrefix("#ARTIST:") {
                result.artist = String(line.dropFirst("#ARTIST:".count))
            } else if upper.hasPrefix("#GENRE:") {
                result.genre = String(line.dropFirst("#GENRE:".count))
            } else if upper.hasPrefix("#BPMS:") {
                parseBPMs(String(line.dropFirst("#BPMS:".count)), into: &result)
            } else if upper.hasPrefix("#NOTES:") {
                if current != selected {
                    current += 1
                    continue
                }
                current += 1
                parseNotes(String(line.dropFirst("#NOTES:".count)), into: &result)
            }
        }
        if convertToNT {
            result.notes = convertBMSE2NT(result.notes, lnobj: lnobj)
        }
        return result
    }

    static func grid(from vPosition: Double) -> (measure: Int, slot: Int, division: Int) {
        let measure = max(0, Int(floor(vPosition / 192)))
        let slot = bankersRound(vPosition - Double(measure) * 192)
        return (measure, min(191, max(0, slot)), 192)
    }

    static func visibleChannel(for column: Int) -> String {
        LegacyMyO2.shortChannel(for: column)
    }

    static func token(for value: Int) -> String {
        BMS36Token.encode(max(1, value / 10_000))
    }

    private static func stripComments(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let raw = String(line)
                if let range = raw.range(of: "//") {
                    return String(raw[..<range.lowerBound])
                }
                return raw
            }
            .joined()
    }

    private static func difficultyLabel(_ block: String) -> String? {
        guard let first = afterFirstColon(block),
              let second = afterFirstColon(first) else { return nil }
        let trimmed = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let nameEnd = trimmed.firstIndex(of: ":") else { return nil }
        let name = String(trimmed[..<nameEnd])
        let rest = trimmed[trimmed.index(after: nameEnd)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let meterEnd = rest.firstIndex(of: ":") else { return nil }
        return name + " : " + String(rest[..<meterEnd])
    }

    private static func parseBPMs(_ body: String, into result: inout SMImportResult) {
        for item in body.split(separator: ",") {
            let piece = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let split = piece.firstIndex(of: "=") else { continue }
            let beat = vbVal(String(piece[..<split]))
            let bpm = vbVal(String(piece[piece.index(after: split)...]))
            let value = bankersRound(bpm * 10_000)
            if beat != 0 {
                result.bpmEvents.append((beat * 48, value))
            } else {
                result.initialBPM = value
            }
        }
    }

    private static func parseNotes(_ body: String, into result: inout SMImportResult) {
        let items = body.split(separator: ":", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard items.count == 6 else { return }
        result.playLevel = items[3]
        let measures = items[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for (measureIndex, measure) in measures.enumerated() {
            let characters = Array(measure)
            guard characters.count >= 4 else { continue }
            let rows = characters.count / 4
            guard rows > 0 else { continue }
            let step = 192 / rows
            var index = 0
            while index + 3 < characters.count {
                let row = index / 4
                let vPosition = Double(step * row + measureIndex * 192)
                for lane in 0..<4 where characters[index + lane] != "0" {
                    let mark = characters[index + lane]
                    result.notes.append(SMImportedNote(
                        columnIndex: playableColumns[lane],
                        vPosition: vPosition,
                        length: 0,
                        longNote: mark == "2" || mark == "3",
                        value: 10_000
                    ))
                }
                index += 4
            }
        }
    }

    static func convertBMSE2NT(_ notes: [SMImportedNote], lnobj: Int) -> [SMImportedNote] {
        var next = notes.sorted { $0.vPosition < $1.vPosition }
        for index in next.indices { next[index].length = 0 }
        var index = 0
        while index < next.count {
            if !next[index].longNote {
                index += 1
                continue
            }
            var partner = index + 1
            while partner < next.count {
                if next[partner].columnIndex != next[index].columnIndex {
                    partner += 1
                    continue
                }
                if next[partner].longNote {
                    next[index].length = next[partner].vPosition - next[index].vPosition
                    next.remove(at: partner)
                }
                break
            }
            index += 1
        }
        _ = lnobj
        for index in next.indices { next[index].longNote = false }
        return next
    }

    private static func afterFirstColon(_ text: String) -> String? {
        guard let index = text.firstIndex(of: ":") else { return nil }
        return String(text[text.index(after: index)...])
    }

    private static func splitKeepingEmpty(_ text: String, separator: String) -> [String] {
        text.components(separatedBy: separator)
    }

    private static func vbVal(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = ""
        var sawDot = false
        var sawDigit = false
        for character in trimmed {
            if character == "+" || character == "-" {
                if value.isEmpty { value.append(character) } else { break }
            } else if character == ".", !sawDot {
                value.append(character)
                sawDot = true
            } else if character.isNumber {
                value.append(character)
                sawDigit = true
            } else if character == " " && !sawDigit {
                continue
            } else {
                break
            }
        }
        return Double(value) ?? 0
    }
}

private func bankersRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}
