import AppKit
import Foundation

/// Pixel geometry taken from µBMSC `PanelDraw.DrawNote` / `DrawNoteNT` and
/// `PanelEvents.MouseInNote`. Coordinates use the same downward-Y space as the
/// flipped native canvas. Default `gxWidth` / `gxHeight` are 1, matching the
/// current layout's 1 CSS-pixel column units.
enum LegacyChartPaint {
    struct Note {
        /// `DrawRectangle` outline: `left+1, anchor-kHeight, width-2, kHeight`.
        let outline: CGRect
        /// `FillRectangle` fill: `left+2, anchor-kHeight+1, width-3, kHeight-1`.
        let fill: CGRect
        /// Selected-note rectangle: `left, anchor-kHeight-1, width, kHeight+2`.
        let selection: CGRect
        /// Inclusive `MouseInNote` box: X in `[left+1, left+width-1]`, Y in `[top, anchor]`.
        let hit: CGRect
        /// GDI+ `LinearGradientBrush` start (`p1`).
        let gradientStart: CGPoint
        /// GDI+ `LinearGradientBrush` end (`p2`).
        let gradientEnd: CGPoint
        let labelOrigin: CGPoint
    }

    struct LongNote {
        let fill: CGRect
        let outline: CGRect
        let selection: CGRect
        let startCap: Note
        let endCap: Note
        let gradientStart: CGPoint
        let gradientEnd: CGPoint
        let labelOrigin: CGPoint
    }

    /// `NoteRowToPanelHeight` with `gxHeight` equal to `pixelsPerQuarterBeat`.
    static func panelY(contentHeight: CGFloat, beat: Double, pixelsPerQuarterBeat: CGFloat) -> CGFloat {
        contentHeight - CGFloat((beat * Double(pixelsPerQuarterBeat)).rounded(.towardZero)) - 1
    }

    static func beat(contentHeight: CGFloat, y: CGFloat, pixelsPerQuarterBeat: CGFloat) -> Double {
        Double(contentHeight - 1 - y) / Double(pixelsPerQuarterBeat)
    }

    /// Short note / NT zero-length note. Matches `DrawNote` and `DrawNoteNT` when `Length = 0`.
    static func shortNote(laneLeft: CGFloat, laneWidth: CGFloat, anchorY: CGFloat, noteHeight: CGFloat, labelShift: CGPoint) -> Note {
        let height = max(1, noteHeight)
        let width = max(1, laneWidth)
        let top = anchorY - height
        return Note(
            outline: CGRect(x: laneLeft + 1, y: top, width: max(1, width - 2), height: height),
            fill: CGRect(x: laneLeft + 2, y: top + 1, width: max(1, width - 3), height: max(1, height - 1)),
            selection: CGRect(x: laneLeft, y: top - 1, width: width, height: height + 2),
            hit: CGRect(x: laneLeft + 1, y: top, width: max(1, width - 2), height: height + 1),
            gradientStart: CGPoint(x: laneLeft, y: top - 10),
            gradientEnd: CGPoint(x: laneLeft + width, y: anchorY + 10),
            labelOrigin: CGPoint(x: laneLeft + labelShift.x, y: top + labelShift.y)
        )
    }

    /// NT-mode long note. Matches `DrawNoteNT` when `Length > 0`.
    static func longNote(
        laneLeft: CGFloat,
        laneWidth: CGFloat,
        startAnchorY: CGFloat,
        endAnchorY: CGFloat,
        noteHeight: CGFloat,
        labelShift: CGPoint
    ) -> LongNote {
        let height = max(1, noteHeight)
        let width = max(1, laneWidth)
        let lower = max(startAnchorY, endAnchorY)
        let upper = min(startAnchorY, endAnchorY)
        let lengthPixels = max(0, lower - upper)
        let top = upper - height
        let start = shortNote(
            laneLeft: laneLeft,
            laneWidth: laneWidth,
            anchorY: startAnchorY,
            noteHeight: height,
            labelShift: labelShift
        )
        let end = shortNote(
            laneLeft: laneLeft,
            laneWidth: laneWidth,
            anchorY: endAnchorY,
            noteHeight: height,
            labelShift: labelShift
        )
        return LongNote(
            fill: CGRect(x: laneLeft + 1, y: top + 1, width: max(1, width - 1), height: max(1, lengthPixels + height - 1)),
            outline: CGRect(x: laneLeft + 1, y: top, width: max(1, width - 3), height: lengthPixels + height),
            selection: CGRect(x: laneLeft, y: top - 1, width: width, height: lengthPixels + height + 2),
            startCap: start,
            endCap: end,
            gradientStart: CGPoint(x: laneLeft - 0.5 * width, y: top),
            gradientEnd: CGPoint(x: laneLeft + 1.5 * width, y: lower),
            labelOrigin: CGPoint(x: laneLeft + labelShift.x - 2, y: startAnchorY - height + labelShift.y)
        )
    }

    /// GDI+ `LinearGradientBrush(p1, p2)` interpolation weight, clamped to 0…1.
    static func gradientWeight(at point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }
        let weight = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        return min(1, max(0, weight))
    }

    static func interpolate(_ colors: ThemeGradientColors, weight: CGFloat) -> NSColor {
        let t = min(1, max(0, weight))
        func mix(_ a: UInt8, _ b: UInt8) -> CGFloat {
            (CGFloat(a) + (CGFloat(b) - CGFloat(a)) * t) / 255
        }
        return NSColor(
            calibratedRed: mix(colors.bright.red, colors.dark.red),
            green: mix(colors.bright.green, colors.dark.green),
            blue: mix(colors.bright.blue, colors.dark.blue),
            alpha: mix(colors.bright.alpha, colors.dark.alpha)
        )
    }

    static func columnBackground(laneLeft: CGFloat, laneWidth: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: laneLeft + 1, y: 0, width: max(0, laneWidth), height: height)
    }

    static func columnVerticalLineX(laneLeft: CGFloat) -> CGFloat { laneLeft }

    static func columnTitleOrigin(laneLeft: CGFloat) -> CGPoint {
        CGPoint(x: laneLeft, y: 0)
    }
}
