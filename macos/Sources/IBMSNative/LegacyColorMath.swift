import Foundation

enum ColorPickerChannel: Int, CaseIterable, Sendable {
    case hue = 0
    case saturation = 1
    case lightness = 2
    case red = 3
    case green = 4
    case blue = 5
}

struct ColorPickerHSLA: Equatable, Sendable {
    var hue: Int
    var saturation: Int
    var lightness: Int
    var alpha: Int

    func clamped() -> ColorPickerHSLA {
        ColorPickerHSLA(
            hue: hue == 360 ? 0 : min(360, max(0, hue)),
            saturation: min(1000, max(0, saturation)),
            lightness: min(1000, max(0, lightness)),
            alpha: min(255, max(0, alpha))
        )
    }
}

struct ColorPickerRGBA: Equatable, Sendable {
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Int

    var themeColor: ThemeColor {
        ThemeColor(argb:
            (UInt32(clamping(alpha)) << 24)
            | (UInt32(clamping(red)) << 16)
            | (UInt32(clamping(green)) << 8)
            | UInt32(clamping(blue))
        )
    }

    private func clamping(_ value: Int) -> UInt8 {
        UInt8(clamping: min(255, max(0, value)))
    }
}

enum LegacyColorMath {
    /// `ColorPicker.HSL2RGB`. Hue 0...360, saturation/lightness 0...1000, alpha 0...255.
    static func hsl2rgb(_ hsl: ColorPickerHSLA) -> ThemeColor {
        let hue = hsl.hue
        let saturation = hsl.saturation
        let lightness = hsl.lightness
        let alpha = hsl.alpha
        if hue > 360 || saturation > 1000 || lightness > 1000 || alpha > 255 {
            return ThemeColor(argb: 0xFF00_0000)
        }

        let xxS = Double(saturation) / 1000
        let xxB = Double(lightness - 500) / 500
        var red: Double
        var green: Double
        var blue: Double
        if hue < 60 {
            blue = -1
            red = 1
            green = Double(hue - 30) / 30
        } else if hue < 120 {
            blue = -1
            green = 1
            red = Double(90 - hue) / 30
        } else if hue < 180 {
            red = -1
            green = 1
            blue = Double(hue - 150) / 30
        } else if hue < 240 {
            red = -1
            blue = 1
            green = Double(210 - hue) / 30
        } else if hue < 300 {
            green = -1
            blue = 1
            red = Double(hue - 270) / 30
        } else {
            green = -1
            red = 1
            blue = Double(330 - hue) / 30
        }

        let mix = 1 - abs(xxB)
        red = (red * xxS * mix + xxB + 1) * 255 / 2
        green = (green * xxS * mix + xxB + 1) * 255 / 2
        blue = (blue * xxS * mix + xxB + 1) * 255 / 2
        return ColorPickerRGBA(
            red: bankersRound(red),
            green: bankersRound(green),
            blue: bankersRound(blue),
            alpha: alpha
        ).themeColor
    }

    /// `System.Drawing.Color.GetHue` / `GetSaturation` / `GetBrightness`.
    static func netHSL(from color: ThemeColor) -> ColorPickerHSLA {
        let red = Double(color.red) / 255
        let green = Double(color.green) / 255
        let blue = Double(color.blue) / 255
        let maxChannel = max(red, max(green, blue))
        let minChannel = min(red, min(green, blue))
        let delta = maxChannel - minChannel
        let lightness = (maxChannel + minChannel) / 2
        var hue = 0.0
        var saturation = 0.0
        if delta != 0 {
            saturation = lightness <= 0.5
                ? delta / (maxChannel + minChannel)
                : delta / (2 - maxChannel - minChannel)
            if red == maxChannel {
                hue = (green - blue) / delta
            } else if green == maxChannel {
                hue = 2 + (blue - red) / delta
            } else {
                hue = 4 + (red - green) / delta
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        return ColorPickerHSLA(
            hue: wrapHue(bankersRound(hue)),
            saturation: min(1000, max(0, bankersRound(saturation * 1000))),
            lightness: min(1000, max(0, bankersRound(lightness * 1000))),
            alpha: Int(color.alpha)
        )
    }

    static func rgba(from color: ThemeColor) -> ColorPickerRGBA {
        ColorPickerRGBA(red: Int(color.red), green: Int(color.green), blue: Int(color.blue), alpha: Int(color.alpha))
    }

    static func hexARGB(_ color: ThemeColor) -> String {
        String(format: "%08X", color.argb)
    }

    static func parseHex(_ text: String) -> ThemeColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 8,
              trimmed.unicodeScalars.allSatisfy(hexDigits.contains),
              let parsed = UInt32(trimmed, radix: 16) else { return nil }
        return ThemeColor(argb: parsed)
    }

    static func wrapHue(_ hue: Int) -> Int {
        let wrapped = ((hue % 360) + 360) % 360
        return wrapped
    }

    static func cursor(
        channel: ColorPickerChannel,
        hue: Int,
        saturation: Int,
        lightness: Int,
        red: Int,
        green: Int,
        blue: Int,
        alpha: Int
    ) -> (main: (x: Int, y: Int), slider: Int, alpha: Int) {
        let main: (Int, Int)
        let slider: Int
        switch channel {
        case .hue:
            main = (scale(saturation, 1000, 255), scale(1000 - lightness, 1000, 255))
            slider = scale(360 - hue, 360, 255)
        case .saturation:
            main = (scale(hue, 360, 255), scale(1000 - lightness, 1000, 255))
            slider = scale(1000 - saturation, 1000, 255)
        case .lightness:
            main = (scale(hue, 360, 255), scale(1000 - saturation, 1000, 255))
            slider = scale(1000 - lightness, 1000, 255)
        case .red:
            main = (blue, 255 - green)
            slider = 255 - red
        case .green:
            main = (blue, 255 - red)
            slider = 255 - green
        case .blue:
            main = (green, 255 - red)
            slider = 255 - blue
        }
        return (main, slider, min(255, max(0, alpha)))
    }

    static func applyMainCursor(
        channel: ColorPickerChannel,
        x: Int,
        y: Int,
        hue: Int,
        saturation: Int,
        lightness: Int,
        red: Int,
        green: Int,
        blue: Int
    ) -> (hue: Int, saturation: Int, lightness: Int, red: Int, green: Int, blue: Int) {
        let x = min(255, max(0, x))
        let y = min(255, max(0, y))
        var nextHue = hue
        var nextSaturation = saturation
        var nextLightness = lightness
        var nextRed = red
        var nextGreen = green
        var nextBlue = blue
        switch channel {
        case .hue:
            nextLightness = scale(255 - y, 255, 1000)
            nextSaturation = scale(x, 255, 1000)
        case .saturation:
            nextLightness = scale(255 - y, 255, 1000)
            nextHue = wrapHue(scale(x, 255, 360))
        case .lightness:
            nextSaturation = scale(255 - y, 255, 1000)
            nextHue = wrapHue(scale(x, 255, 360))
        case .red:
            nextGreen = 255 - y
            nextBlue = x
        case .green:
            nextRed = 255 - y
            nextBlue = x
        case .blue:
            nextRed = 255 - y
            nextGreen = x
        }
        return (nextHue, nextSaturation, nextLightness, nextRed, nextGreen, nextBlue)
    }

    static func applySliderCursor(channel: ColorPickerChannel, y: Int, hue: Int, saturation: Int, lightness: Int, red: Int, green: Int, blue: Int)
        -> (hue: Int, saturation: Int, lightness: Int, red: Int, green: Int, blue: Int) {
        let y = min(255, max(0, y))
        var nextHue = hue
        var nextSaturation = saturation
        var nextLightness = lightness
        var nextRed = red
        var nextGreen = green
        var nextBlue = blue
        switch channel {
        case .hue:
            nextHue = wrapHue(scale(255 - y, 255, 360))
        case .saturation:
            nextSaturation = scale(255 - y, 255, 1000)
        case .lightness:
            nextLightness = scale(255 - y, 255, 1000)
        case .red:
            nextRed = 255 - y
        case .green:
            nextGreen = 255 - y
        case .blue:
            nextBlue = 255 - y
        }
        return (nextHue, nextSaturation, nextLightness, nextRed, nextGreen, nextBlue)
    }

    static func previewCaptionIsDark(lightness: Int, alpha: Int) -> Bool {
        Double(lightness) / 1000 + Double(255 - alpha) / 255 > 0.5
    }

    static func sliderCaptionIsDark(lightness: Int) -> Bool {
        lightness > 500
    }

    static func alphaCaptionIsDark(lightness: Int, alpha: Int) -> Bool {
        lightness + (255 - alpha) * 1000 / 255 > 500
    }

    private static func scale(_ value: Int, _ from: Int, _ to: Int) -> Int {
        bankersRound(Double(value) / Double(from) * Double(to))
    }

    private static let hexDigits = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
}

private func bankersRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}
