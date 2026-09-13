import Foundation

/// 对照 `PanelDraw.vb` `DrawBackgroundColor` / `DrawColumnCaptions` / `DrawPanelLines`。
enum LegacyPanelGuides {
    static func measureCaption(_ measure: Int) -> String {
        "[\(String(format: "%03d", measure))]"
    }

    /// `Color.GetBrightness` 是 `(max + min) / 2`。亮度为 0 时不填列底色。
    static func shouldFillBackground(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        Int(max(red, max(green, blue))) + Int(min(red, min(green, blue))) != 0
    }
}
