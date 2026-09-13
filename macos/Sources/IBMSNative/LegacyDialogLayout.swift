import CoreGraphics
import Foundation

enum AboutDialogLayout {
    /// Designer client size before `TBAbout_Click` resizes the window to the About0 bitmap.
    static let designerClientSize = CGSize(width: 1000, height: 600)
    /// Runtime size from `MainWindow.TBAbout_Click` and `About.png`.
    static let runtimeClientSize = CGSize(width: 1000, height: 500)
    static let clickToCopy = CGRect(x: 540, y: 355, width: 131, height: 23)
    static let hiddenCopyLabel = CGRect(x: 620, y: 288, width: 96, height: 21)
    static let clickToCopyTitle = "Click to copy"
    static let email = "higan314doaz9@qq.com"
    static let imageName = "About"
}

enum SplashDialogLayout {
    static let clientSize = CGSize(width: 722, height: 331)
    static let background = ThemeColor(argb: 0xFF69_6969)
    /// `SplashScreen1.OnPaintBackground` has `DrawImage(About0)` commented out.
    static let drawsImage = false
}

enum ColorPickerLayout {
    static let clientSize = CGSize(width: 453, height: 345)
    static let preview = CGRect(x: 315, y: 14, width: 125, height: 30)
    static let previewOrig = CGRect(x: 0, y: 0, width: 61, height: 28)
    static let previewDividerX = 61
    static let previewNew = CGRect(x: 62, y: 0, width: 61, height: 28)
    static let main = CGRect(x: 14, y: 14, width: 258, height: 258)
    static let mainInner = CGRect(x: 15, y: 15, width: 256, height: 256)
    static let slider = CGRect(x: 278, y: 14, width: 19, height: 258)
    static let sliderInner = CGRect(x: 279, y: 15, width: 17, height: 256)
    static let alpha = CGRect(x: 14, y: 278, width: 258, height: 19)
    static let alphaInner = CGRect(x: 15, y: 279, width: 256, height: 17)
    static let precisionLabel = CGRect(x: 16, y: 305, width: 58, height: 15)
    static let precision = CGRect(x: 73, y: 303, width: 199, height: 45)
    static let precisionRange = 1...10
    static let defaultPrecision = 2
    static let hashLabel = CGRect(x: 320, y: 248, width: 14, height: 15)
    static let hexField = CGRect(x: 340, y: 245, width: 89, height: 23)
    static let ok = CGRect(x: 315, y: 275, width: 126, height: 27)
    static let cancel = CGRect(x: 315, y: 306, width: 126, height: 27)
    static let defaultHex = "FF000000"
    static let defaultChannel = ColorPickerChannel.saturation
    static let transparentBackgroundName = "TransparentBG"

    static let channels: [(channel: ColorPickerChannel, title: String, button: CGRect, field: CGRect, range: ClosedRange<Int>)] = [
        (.hue, "H (0-359)", CGRect(x: 315, y: 55, width: 77, height: 23), CGRect(x: 396, y: 55, width: 45, height: 23), 0...360),
        (.saturation, "S (0-1000)", CGRect(x: 315, y: 80, width: 77, height: 23), CGRect(x: 396, y: 80, width: 45, height: 23), 0...1000),
        (.lightness, "L (0-1000)", CGRect(x: 315, y: 105, width: 77, height: 23), CGRect(x: 396, y: 105, width: 45, height: 23), 0...1000),
        (.red, "R (0-255)", CGRect(x: 315, y: 134, width: 77, height: 23), CGRect(x: 396, y: 134, width: 45, height: 23), 0...255),
        (.green, "G (0-255)", CGRect(x: 315, y: 159, width: 77, height: 23), CGRect(x: 396, y: 159, width: 45, height: 23), 0...255),
        (.blue, "B (0-255)", CGRect(x: 315, y: 184, width: 77, height: 23), CGRect(x: 396, y: 184, width: 45, height: 23), 0...255)
    ]

    static let alphaButton = CGRect(x: 315, y: 213, width: 77, height: 23)
    static let alphaField = CGRect(x: 396, y: 213, width: 45, height: 23)
    static let alphaEnabled = false
    static let defaultAlpha = 255
}
