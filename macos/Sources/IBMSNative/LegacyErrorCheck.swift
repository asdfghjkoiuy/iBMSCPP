import CoreGraphics
import Foundation

struct ErrorCheckNote: Equatable {
    var vPosition: Double
    var columnIndex: Int
    var value: Int
    var length: Double
    var hidden: Bool
    var hasError: Bool = false
}

struct ErrorAnchor: Hashable {
    let channel: String
    let beat: Double

    func hash(into hasher: inout Hasher) {
        hasher.combine(channel)
        hasher.combine(beat.bitPattern)
    }

    static func == (lhs: ErrorAnchor, rhs: ErrorAnchor) -> Bool {
        lhs.channel == rhs.channel && lhs.beat.bitPattern == rhs.beat.bitPattern
    }
}

enum LegacyErrorCheck {
    static let iconSize: CGFloat = 24
    static let hoverErrorText = "Error"
    static let numericColumns: Set<Int> = [1, 2, 3]
    static let offIcon = "x16CheckErrorN"
    static let onIcon = "x16CheckError"
    static let imageName = "ImageError"

    static func markNT(_ notes: [ErrorCheckNote], lnObj: Int) -> [ErrorCheckNote] {
        var next = notes.enumerated().map { index, note -> ErrorCheckNote in
            var copy = note
            copy.hasError = false
            if index > 0 && copy.length < 0 { copy.length = 0 }
            return copy
        }
        guard next.count > 1 else { return next }
        let order = next.indices.dropFirst().sorted {
            if next[$0].vPosition != next[$1].vPosition { return next[$0].vPosition < next[$1].vPosition }
            return $0 < $1
        }

        for position in order.indices {
            let i = order[position]
            if next[i].length != 0 {
                let end = next[i].vPosition + next[i].length
                for later in (position + 1)..<order.count {
                    let j = order[later]
                    if next[j].vPosition > end { break }
                    if next[j].columnIndex == next[i].columnIndex {
                        next[j].hasError = true
                    }
                }
            } else {
                for later in (position + 1)..<order.count {
                    let j = order[later]
                    if next[j].vPosition > next[i].vPosition { break }
                    if next[j].columnIndex == next[i].columnIndex {
                        next[j].hasError = true
                    }
                }
                if token(next[i].value) == lnObj && lnObj != 0 && !numericColumns.contains(next[i].columnIndex) {
                    var found = false
                    if position > 0 {
                        for earlier in stride(from: position - 1, through: 0, by: -1) {
                            let j = order[earlier]
                            if next[j].columnIndex != next[i].columnIndex { continue }
                            if next[j].hidden { continue }
                            if next[j].length != 0 || token(next[j].value) == lnObj {
                                next[i].hasError = true
                            }
                            found = true
                            break
                        }
                    }
                    if !found {
                        next[i].hasError = true
                    }
                }
            }
        }
        return next
    }

    static func iconRect(
        laneLeft: CGFloat,
        laneWidth: CGFloat,
        anchorY: CGFloat,
        noteHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: laneLeft + laneWidth / 2 - iconSize / 2,
            y: anchorY - noteHeight / 2 - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
    }

    static func token(_ value: Int) -> Int {
        value / 10_000
    }
}
