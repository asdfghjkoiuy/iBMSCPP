import Foundation

@main
struct LegacyDialogTests {
    static func main() {
        testLayouts()
        testHSL()
        testHex()
        testCursor()
        testCaptions()
        print("LegacyDialogTests passed")
    }

    private static func testLayouts() {
        require(AboutDialogLayout.designerClientSize == CGSize(width: 1000, height: 600), "About Designer size")
        require(AboutDialogLayout.runtimeClientSize == CGSize(width: 1000, height: 500), "About runtime size")
        require(AboutDialogLayout.clickToCopy == CGRect(x: 540, y: 355, width: 131, height: 23), "Click to copy")
        require(AboutDialogLayout.email == "higan314doaz9@qq.com", "About email")
        require(SplashDialogLayout.clientSize == CGSize(width: 722, height: 331), "Splash client size")
        require(SplashDialogLayout.background.argb == 0xFF69_6969, "ControlDarkDark")
        require(!SplashDialogLayout.drawsImage, "current SplashScreen1 does not draw About0")
        require(ColorPickerLayout.clientSize == CGSize(width: 453, height: 345), "ColorPicker client size")
        require(ColorPickerLayout.main == CGRect(x: 14, y: 14, width: 258, height: 258), "PCMain")
        require(ColorPickerLayout.slider == CGRect(x: 278, y: 14, width: 19, height: 258), "PC1")
        require(ColorPickerLayout.ok == CGRect(x: 315, y: 275, width: 126, height: 27), "ColorPicker OK")
        require(ColorPickerLayout.defaultChannel == .saturation && ColorPickerLayout.defaultPrecision == 2, "S mode and precision 2")
        require(ColorPickerLayout.channels.count == 6 && !ColorPickerLayout.alphaEnabled, "six channels, A button disabled")
    }

    private static func testHSL() {
        let black = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: 0, saturation: 0, lightness: 0, alpha: 255))
        require(black.argb == 0xFF00_0000, "L=0 is black")
        let white = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: 0, saturation: 0, lightness: 1000, alpha: 255))
        require(white.argb == 0xFFFF_FFFF, "L=1000 is white")
        let gray = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: 0, saturation: 0, lightness: 500, alpha: 255))
        require(gray.red == 128 && gray.green == 128 && gray.blue == 128, "L=500 S=0 is 127.5 banker-rounded to 128")
        let red = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: 0, saturation: 1000, lightness: 500, alpha: 255))
        require(red.argb == 0xFFFF_0000, "H=0 S=1000 L=500 is red")
        let green = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: 120, saturation: 1000, lightness: 500, alpha: 255))
        require(green.argb == 0xFF00_FF00, "H=120 S=1000 L=500 is green")
        let outOfRange = LegacyColorMath.hsl2rgb(ColorPickerHSLA(hue: 361, saturation: 0, lightness: 0, alpha: 255))
        require(outOfRange.argb == 0xFF00_0000, "H>360 returns black")

        let netRed = LegacyColorMath.netHSL(from: ThemeColor(argb: 0xFFFF_0000))
        require(netRed.hue == 0 && netRed.saturation == 1000 && netRed.lightness == 500, ".NET HSL of red")
        let netWhite = LegacyColorMath.netHSL(from: ThemeColor(argb: 0xFFFF_FFFF))
        require(netWhite.hue == 0 && netWhite.saturation == 0 && netWhite.lightness == 1000, ".NET HSL of white")
        let netGray = LegacyColorMath.netHSL(from: ThemeColor(argb: 0xFF80_8080))
        require(netGray.hue == 0 && netGray.saturation == 0 && netGray.lightness == 502, "128/255 brightness bankers to 502")
    }

    private static func testHex() {
        require(LegacyColorMath.hexARGB(ThemeColor(argb: 0xFF00_0000)) == "FF000000", "8-digit hex")
        require(LegacyColorMath.parseHex("FF00FF00")?.argb == 0xFF00_FF00, "parse full hex")
        require(LegacyColorMath.parseHex("FF0000")?.argb == 0x00FF_0000, "short hex keeps the integer value")
        require(LegacyColorMath.parseHex("GG") == nil, "invalid hex")
        require(LegacyColorMath.parseHex("") == nil, "empty hex")
    }

    private static func testCursor() {
        let saturation = LegacyColorMath.cursor(
            channel: .saturation, hue: 0, saturation: 1000, lightness: 500,
            red: 255, green: 0, blue: 0, alpha: 255
        )
        require(saturation.main.x == 0 && saturation.slider == 0, "red in S mode sits on the left and top of the slider")
        require(saturation.main.y == 128, "(1000-500)/1000*255 is 127.5 → 128")

        let dragged = LegacyColorMath.applyMainCursor(
            channel: .saturation, x: 0, y: 0,
            hue: 0, saturation: 1000, lightness: 500,
            red: 255, green: 0, blue: 0
        )
        require(dragged.lightness == 1000 && dragged.hue == 0, "top of the S square is L=1000")
    }

    private static func testCaptions() {
        require(LegacyColorMath.sliderCaptionIsDark(lightness: 501), "light square uses a dark cursor")
        require(!LegacyColorMath.sliderCaptionIsDark(lightness: 500), "L=500 uses a light cursor")
        require(LegacyColorMath.previewCaptionIsDark(lightness: 1000, alpha: 255), "white Orig/New caption is dark")
        require(!LegacyColorMath.previewCaptionIsDark(lightness: 0, alpha: 255), "black Orig/New caption is light")
        require(LegacyColorMath.alphaCaptionIsDark(lightness: 0, alpha: 0), "transparent black still uses a dark triangle")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
