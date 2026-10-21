import Foundation

struct TimeSelectionNote: Equatable {
    var vPosition: Double
    var columnIndex: Int
    var value: Int
    var length: Double
    var hidden: Bool

    static let bpmColumn = 2
    static let stopColumn = 3
}

enum TimeSelectionWriteResult: Equatable {
    case applied(notes: [TimeSelectionNote], selection: TimeSelection)
    case skipped
    case blocked(String)
}

enum TimeSelectionCommand: Equatable {
    case expand(ratio: Double)
    case stretchHalf(delta: Double)
    case relocate(value: Double)
    case convertStop
}

enum LegacyTimeSelectionOps {
    static let bpmCap = 655_359_999
    static let factorMustBePositive = "Factor must be greater than zero."
    static let convertBlockedMessage = LegacyTimeSelection.convertBlockedMessage

    static func expandByRatio(
        notes: [TimeSelectionNote],
        selection: TimeSelection,
        ratio: Double,
        maxVPosition: Double
    ) -> TimeSelectionWriteResult {
        if selection.length == 0 || ratio == 1 { return .skipped }
        if ratio <= 0 { return .blocked(factorMustBePositive) }

        var lower = selection.lower
        var upper = selection.upper
        if lower < 0 { lower = 0 }
        let limit = max(0, maxVPosition - 1)
        if upper >= maxVPosition { upper = limit }

        var next = notes
        let headerBPM = next.first?.value ?? 1_200_000
        var valueL = headerBPM
        var valueU = headerBPM
        var addLower = true
        var addUpper = true

        if next.count > 1 {
            for index in 1..<next.count {
                if next[index].vPosition <= lower {
                    if next[index].columnIndex == TimeSelectionNote.bpmColumn {
                        valueL = next[index].value
                        valueU = next[index].value
                        if next[index].vPosition == lower {
                            addLower = false
                            next[index].value = scaledBPM(next[index].value, ratio: ratio, cap: true)
                        }
                    }
                    if next[index].vPosition + next[index].length > lower {
                        let overlapEnd = min(upper, next[index].vPosition + next[index].length)
                        next[index].length += (overlapEnd - lower) * (ratio - 1)
                    }
                } else if next[index].vPosition <= upper {
                    if next[index].columnIndex == TimeSelectionNote.bpmColumn {
                        valueU = next[index].value
                        if next[index].vPosition == upper {
                            addUpper = false
                        } else {
                            next[index].value = scaledBPM(next[index].value, ratio: ratio, cap: true)
                        }
                    }
                    let overlapEnd = min(upper, next[index].length + next[index].vPosition)
                    next[index].length += (overlapEnd - next[index].vPosition) * (ratio - 1)
                    next[index].vPosition = (next[index].vPosition - lower) * ratio + lower
                } else {
                    next[index].vPosition += (upper - lower) * (ratio - 1)
                }
            }
        }

        if addLower {
            next.append(TimeSelectionNote(
                vPosition: lower,
                columnIndex: TimeSelectionNote.bpmColumn,
                value: scaledBPM(valueL, ratio: ratio, cap: false),
                length: 0,
                hidden: false
            ))
        }
        if addUpper {
            next.append(TimeSelectionNote(
                vPosition: (upper - lower) * ratio + lower,
                columnIndex: TimeSelectionNote.bpmColumn,
                value: valueU,
                length: 0,
                hidden: false
            ))
        }

        for index in next.indices.dropFirst() where next[index].columnIndex == TimeSelectionNote.bpmColumn && next[index].value < 1 {
            next[index].value = 1
        }

        var updated = selection
        if updated.length < 0 {
            updated.start += (ratio - 1) * (upper - lower)
        }
        updated.length *= ratio
        updated.half *= ratio
        return .applied(notes: sortedPreservingHeader(next), selection: LegacyTimeSelection.validate(updated, maxVPosition: maxVPosition))
    }

    static func stretchByHalfDelta(
        notes: [TimeSelectionNote],
        selection: TimeSelection,
        delta: Double,
        maxVPosition: Double
    ) -> TimeSelectionWriteResult {
        if selection.length == 0 || delta == 0 { return .skipped }

        var lower = selection.lower
        var half = selection.halfPosition
        var upper = selection.upper
        if delta + half <= lower || delta + half >= upper { return .skipped }

        if lower < 0 { lower = 0 }
        let limit = max(0, maxVPosition - 1)
        if upper >= maxVPosition { upper = limit }
        if half > upper { half = upper }
        if half < lower { half = lower }
        if half == lower || half == upper { return .skipped }

        let ratio1 = (half - lower + delta) / (half - lower)
        let ratio2 = (upper - half - delta) / (upper - half)

        var next = notes
        let headerBPM = next.first?.value ?? 1_200_000
        var valueL = headerBPM
        var valueM = headerBPM
        var valueU = headerBPM
        var addLower = true
        var addMiddle = true
        var addUpper = true

        if next.count > 1 {
            for index in 1..<next.count {
                if next[index].vPosition <= lower {
                    if next[index].columnIndex == TimeSelectionNote.bpmColumn {
                        valueL = next[index].value
                        valueM = next[index].value
                        valueU = next[index].value
                        if next[index].vPosition == lower {
                            addLower = false
                            next[index].value = integerValue(Double(next[index].value) * ratio1)
                        }
                    }
                    let end = next[index].vPosition + next[index].length
                    if end > upper {
                    } else if end > half {
                        next[index].length = (end - half) * ratio2 + half + delta - next[index].vPosition
                    } else if end > lower {
                        next[index].length = (end - lower) * ratio1 + lower - next[index].vPosition
                    }
                } else if next[index].vPosition <= half {
                    if next[index].columnIndex == TimeSelectionNote.bpmColumn {
                        valueM = next[index].value
                        valueU = next[index].value
                        if next[index].vPosition == half {
                            addMiddle = false
                            next[index].value = integerValue(Double(next[index].value) * ratio2)
                        } else {
                            next[index].value = integerValue(Double(next[index].value) * ratio1)
                        }
                    }
                    let end = next[index].vPosition + next[index].length
                    if end > upper {
                        next[index].length = end - lower - (next[index].vPosition - lower) * ratio1
                    } else if end > half {
                        next[index].length = (half - next[index].vPosition) * ratio1 + (end - half) * ratio2
                    } else {
                        next[index].length *= ratio1
                    }
                    next[index].vPosition = (next[index].vPosition - lower) * ratio1 + lower
                } else if next[index].vPosition <= upper {
                    if next[index].columnIndex == TimeSelectionNote.bpmColumn {
                        valueU = next[index].value
                        if next[index].vPosition == upper {
                            addUpper = false
                        } else {
                            next[index].value = scaledBPM(next[index].value, ratio: ratio2, cap: true)
                        }
                    }
                    let end = next[index].vPosition + next[index].length
                    if end > upper {
                        next[index].length = (upper - next[index].vPosition) * ratio2 + end - upper
                    } else {
                        next[index].length *= ratio2
                    }
                    next[index].vPosition = (next[index].vPosition - half) * ratio2 + half + delta
                }
            }
        }

        if addLower {
            next.append(TimeSelectionNote(
                vPosition: lower,
                columnIndex: TimeSelectionNote.bpmColumn,
                value: integerValue(Double(valueL) * ratio1),
                length: 0,
                hidden: false
            ))
        }
        if addMiddle {
            next.append(TimeSelectionNote(
                vPosition: half + delta,
                columnIndex: TimeSelectionNote.bpmColumn,
                value: integerValue(Double(valueM) * ratio2),
                length: 0,
                hidden: false
            ))
        }
        if addUpper {
            next.append(TimeSelectionNote(
                vPosition: upper,
                columnIndex: TimeSelectionNote.bpmColumn,
                value: valueU,
                length: 0,
                hidden: false
            ))
        }

        var updated = selection
        updated.half += delta
        return .applied(notes: sortedPreservingHeader(next), selection: LegacyTimeSelection.validate(updated, maxVPosition: maxVPosition))
    }

    static func relocateByValue(
        notes: [TimeSelectionNote],
        selection: TimeSelection,
        value: Double,
        maxVPosition: Double
    ) -> TimeSelectionWriteResult {
        if selection.length == 0 { return .skipped }
        let target = integerValue(value)
        if target == 0 { return .skipped }

        var lower = selection.lower
        var half = selection.halfPosition
        var upper = selection.upper
        if half == upper { half = lower }
        if lower < 0 { lower = 0 }
        let limit = max(0, maxVPosition - 1)
        if upper >= maxVPosition { upper = limit }
        if half > upper { half = upper }
        if half < lower { half = lower }

        var bpm = notes.first?.value ?? 1_200_000
        if notes.count > 1 {
            for index in 1..<notes.count {
                if notes[index].vPosition > lower { break }
                if notes[index].columnIndex == TimeSelectionNote.bpmColumn {
                    bpm = notes[index].value
                }
            }
        }

        var positions = [lower]
        var values = [bpm]
        if notes.count > 1 {
            for index in 1..<notes.count {
                if notes[index].vPosition > upper { break }
                if notes[index].vPosition > lower && notes[index].columnIndex == TimeSelectionNote.bpmColumn {
                    positions.append(notes[index].vPosition)
                    values.append(notes[index].value)
                }
            }
        }
        positions.append(upper)

        var spanTime = 0.0
        for index in 0..<values.count {
            let divisor = Double(values[index])
            if divisor == 0 { return .skipped }
            spanTime += (positions[index + 1] - positions[index]) / divisor
        }
        if spanTime == 0 { return .skipped }
        let constBPM = (upper - lower) / spanTime

        if (upper - lower) / constBPM <= (half - lower) / Double(target) {
            let limitBPM = (half - lower) * constBPM / (upper - lower) / 10_000
            return .blocked(relocateLimitMessage(limitBPM))
        }

        let divider = constBPM * (half - lower) - Double(target) * (upper - lower)
        if divider == 0 { return .skipped }
        let result = (half - upper) * Double(target) / divider * constBPM

        var next = notes
        if next.count > 1 {
            for index in 1..<next.count {
                var end = next[index].length == 0 ? next[index].vPosition : next[index].vPosition + next[index].length
                if next[index].vPosition > lower && next[index].vPosition < upper {
                    next[index].vPosition = remap(
                        next[index].vPosition,
                        positions: positions,
                        values: values,
                        lower: lower,
                        half: half,
                        target: target,
                        result: result
                    )
                }
                if next[index].length != 0 {
                    if end > lower && end < upper {
                        end = remap(
                            end,
                            positions: positions,
                            values: values,
                            lower: lower,
                            half: half,
                            target: target,
                            result: result
                        )
                        next[index].length = end - next[index].vPosition
                    } else {
                        next[index].length = end - next[index].vPosition
                    }
                }
            }
        }

        next = next.enumerated().compactMap { index, note in
            if index == 0 { return note }
            if note.columnIndex == TimeSelectionNote.bpmColumn && note.vPosition >= lower && note.vPosition <= upper {
                return nil
            }
            return note
        }

        next.append(TimeSelectionNote(
            vPosition: half,
            columnIndex: TimeSelectionNote.bpmColumn,
            value: integerValue(result),
            length: 0,
            hidden: false
        ))
        next.append(TimeSelectionNote(
            vPosition: upper,
            columnIndex: TimeSelectionNote.bpmColumn,
            value: values[values.count - 1],
            length: 0,
            hidden: false
        ))
        if lower != half {
            next.append(TimeSelectionNote(
                vPosition: lower,
                columnIndex: TimeSelectionNote.bpmColumn,
                value: target,
                length: 0,
                hidden: false
            ))
        }

        return .applied(notes: sortedPreservingHeader(next), selection: selection)
    }

    static func convertAreaToStop(
        notes: [TimeSelectionNote],
        selection: TimeSelection
    ) -> TimeSelectionWriteResult {
        if selection.length == 0 { return .skipped }
        let lower = selection.lower
        let upper = selection.upper
        let blocked = notes.dropFirst().contains { $0.vPosition > lower && $0.vPosition <= upper }
        if blocked { return .blocked(convertBlockedMessage) }

        var next = notes
        if next.count > 1 {
            for index in 1..<next.count where next[index].vPosition > upper {
                next[index].vPosition -= selection.length
            }
        }
        next.append(TimeSelectionNote(
            vPosition: lower,
            columnIndex: TimeSelectionNote.stopColumn,
            value: integerValue(selection.length * 10_000),
            length: 0,
            hidden: false
        ))
        return .applied(notes: sortedPreservingHeader(next), selection: selection)
    }

    static func relocateLimitMessage(_ limit: Double) -> String {
        "Please enter a value that is greater than \(LegacyTimeSelection.formatField(limit))."
    }

    private static func remap(
        _ vPosition: Double,
        positions: [Double],
        values: [Int],
        lower: Double,
        half: Double,
        target: Int,
        result: Double
    ) -> Double {
        guard target > 0, result.isFinite, vPosition.isFinite, !values.isEmpty else { return vPosition }
        var time = 0.0
        var index = 0
        while index < values.count {
            guard index + 1 < positions.count, values[index] > 0 else { return vPosition }
            if vPosition < positions[index + 1] { break }
            let span = (positions[index + 1] - positions[index]) / Double(values[index])
            guard span.isFinite else { return vPosition }
            time += span
            index += 1
        }
        guard index < values.count, index < positions.count, values[index] > 0 else { return vPosition }
        let tail = (vPosition - positions[index]) / Double(values[index])
        guard tail.isFinite else { return vPosition }
        time += tail
        guard time.isFinite else { return vPosition }
        let boundary = (half - lower) / Double(target)
        guard boundary.isFinite else { return vPosition }
        if time - boundary > 0 {
            let mapped = (time - boundary) * result + half
            return mapped.isFinite ? mapped : vPosition
        }
        let mapped = time * Double(target) + lower
        return mapped.isFinite ? mapped : vPosition
    }

    private static func scaledBPM(_ value: Int, ratio: Double, cap: Bool) -> Int {
        let scaled = integerValue(Double(value) * ratio)
        return cap ? min(scaled, bpmCap) : scaled
    }

    private static func integerValue(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(exactly: value.rounded()) ?? 0
    }

    private static func sortedPreservingHeader(_ notes: [TimeSelectionNote]) -> [TimeSelectionNote] {
        guard notes.count > 1 else { return notes }
        return [notes[0]] + notes.dropFirst().sorted { lhs, rhs in
            if lhs.vPosition != rhs.vPosition { return lhs.vPosition < rhs.vPosition }
            return lhs.columnIndex < rhs.columnIndex
        }
    }
}
