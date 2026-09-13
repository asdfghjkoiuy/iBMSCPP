import Foundation

@main
struct LegacyWaveformTests {
    static func main() {
        testDeinterleaveStereo()
        testSampleIndexAtOneBeat()
        testSampleIndexAcrossBPMChange()
        testLockUsesFirstBGM()
        testPointXUsesWidthAndLeft()
        testDesignerDisplayDefaultsAndClamps()
        testPrecisionSampleCount()
        testTransparencyKeepsRGB()
        testSaturationUsesNetHSLAndHSL2RGB()
        testPositionClampAndDrawing()
        print("LegacyWaveformTests passed")
    }

    /// `Waveform.vb`：交错立体声拆成左右。
    private static func testDeinterleaveStereo() {
        let split = LegacyWaveform.deinterleaveStereo([0.25, -0.5, 0.75, 1.0])
        require(split.left == [0.25, 0.75], "left channel")
        require(split.right == [-0.5, 1.0], "right channel")
    }

    /// `(vpos) * 1.25 * sampleRate / BPM`。一拍 48 vpos，120 BPM，44100 Hz → 22050。
    private static func testSampleIndexAtOneBeat() {
        let segments = LegacyWaveform.segments(headBPM: 120, bpmEvents: [], lockPosition: 0)
        let index = LegacyWaveform.sampleIndex(vPosition: 48, segments: segments, sampleRate: 44100)
        require(index == 22050, "one beat at 120 BPM is 0.5 s")
    }

    /// 先 120 走 48 vpos，再 240 走 48 vpos。
    private static func testSampleIndexAcrossBPMChange() {
        let segments = LegacyWaveform.segments(
            headBPM: 120,
            bpmEvents: [(vPosition: 48, bpm: 240)],
            lockPosition: 0
        )
        let index = LegacyWaveform.sampleIndex(vPosition: 96, segments: segments, sampleRate: 44100)
        require(index == 33075, "48 vpos at 120 plus 48 vpos at 240")
    }

    /// `wLock`：第一颗 B 列音的 VPosition 当成波形起点。
    private static func testLockUsesFirstBGM() {
        require(LegacyWaveform.lockPosition(firstBGMVPosition: 192) == 192, "lock to first BGM")
        require(LegacyWaveform.lockPosition(firstBGMVPosition: nil) == 0, "no BGM keeps 0")
    }

    /// `DrawWaveform`：`sample * wWidth + wLeft`。
    private static func testPointXUsesWidthAndLeft() {
        require(LegacyWaveform.pointX(sample: 0.5, width: 200, left: 50) == 150, "Designer width 200")
        require(LegacyWaveform.pointX(sample: 1, width: 100, left: 50) == 150, "Waveform.vb Dim width 100")
        require(LegacyWaveform.pointX(sample: -0.25, width: 200, left: 50) == 0, "negative sample stays left of center")
    }

    /// Designer：`TWLeft=50`，`TWWidth=200`，`TWPrecision=5`。范围按 NumericUpDown。
    private static func testDesignerDisplayDefaultsAndClamps() {
        require(LegacyWaveform.defaultLeft == 50, "TWLeft default")
        require(LegacyWaveform.defaultWidth == 200, "TWWidth default")
        require(LegacyWaveform.defaultPrecision == 5, "TWPrecision default")
        require(LegacyWaveform.clampLeft(-1) == 0 && LegacyWaveform.clampLeft(801) == 800, "TWLeft 0...800")
        require(LegacyWaveform.clampWidth(-1) == 0 && LegacyWaveform.clampWidth(1001) == 1000, "TWWidth 0...1000")
        require(LegacyWaveform.clampPrecision(-1) == 0 && LegacyWaveform.clampPrecision(51) == 50, "TWPrecision 0...50")
    }

    /// `xPts(xTHeight * wPrecision)`，Y 是 `index / wPrecision`。精度 0 不画。
    private static func testPrecisionSampleCount() {
        require(LegacyWaveform.sampleCount(height: 2, precision: 5) == 11, "2 * 5 + 1 points")
        require(LegacyWaveform.pointY(index: 5, precision: 5) == 1, "index 5 at precision 5 is y=1")
        require(LegacyWaveform.sampleCount(height: 2, precision: 0) == 0, "precision 0 draws nothing")
        require(LegacyWaveform.sampleCount(height: 2, precision: 1) == 3, "precision 1 is one point per row including 0")
    }

    /// `FromArgb(80, Color.FromArgb(851493056))` 只改 Alpha。
    private static func testTransparencyKeepsRGB() {
        require(LegacyWaveform.defaultTransparency == 80, "TWTransparency default")
        require(LegacyWaveform.clampTransparency(-1) == 0 && LegacyWaveform.clampTransparency(256) == 255, "0...255")
        let source = ThemeColor(signedARGB: 851493056)
        let painted = LegacyWaveform.applyTransparency(source, alpha: 80)
        require(painted.alpha == 80 && painted.red == source.red && painted.green == source.green && painted.blue == source.blue,
                "alpha 80 keeps C0C0C0")
        require(painted.argb == 0x50C0_C0C0, "0x32C0C0C0 plus A=80 is 0x50C0C0C0")
    }

    /// `HSL2RGB(0, 500, 500, 80)`：红半饱和。
    private static func testSaturationUsesNetHSLAndHSL2RGB() {
        require(LegacyWaveform.defaultSaturation == 0, "TWSaturation default")
        require(LegacyWaveform.clampSaturation(-1) == 0 && LegacyWaveform.clampSaturation(1001) == 1000, "0...1000")
        let red = ThemeColor(argb: 0x50FF_0000)
        require(LegacyWaveform.saturationSlider(from: red) == 1000, "red saturation is 1000")
        let painted = LegacyWaveform.applySaturation(red, saturation: 500)
        require(painted.argb == 0x50BF_4040, "H=0 S=500 L=500 A=80")
        let gray = ThemeColor(argb: 0x50C0_C0C0)
        require(LegacyWaveform.saturationSlider(from: gray) == 0, "gray saturation is 0")
    }

    /// `TWPosition` / `TWPosition2`：锁开走第一颗 B，锁关走数字框。不写回字段。
    private static func testPositionClampAndDrawing() {
        require(LegacyWaveform.defaultPosition == 0, "TWPosition default 0")
        require(LegacyWaveform.clampPosition(-1) == 0, "TWPosition min 0")
        require(LegacyWaveform.clampPosition(192001) == 192000, "TWPosition max 192000")
        require(LegacyWaveform.clampPosition(48) == 48, "TWPosition keeps 48")
        require(LegacyWaveform.sliderValue(0) == 0, "slider 0")
        require(LegacyWaveform.sliderValue(480) == 480, "slider 480")
        require(LegacyWaveform.sliderValue(960) == 960, "slider 960")
        require(LegacyWaveform.sliderValue(961) == 960, "slider caps 961")
        require(LegacyWaveform.sliderValue(192000) == 960, "slider caps 192000")
        require(
            LegacyWaveform.drawingPosition(locked: true, fieldPosition: 0, firstBGMVPosition: 192) == 192,
            "locked uses first BGM 192"
        )
        require(
            LegacyWaveform.drawingPosition(locked: true, fieldPosition: 48, firstBGMVPosition: nil) == 0,
            "locked without BGM is 0"
        )
        require(
            LegacyWaveform.drawingPosition(locked: false, fieldPosition: 48, firstBGMVPosition: 192) == 48,
            "unlocked uses field 48"
        )
        require(
            LegacyWaveform.drawingPosition(locked: false, fieldPosition: 0, firstBGMVPosition: 192) == 0,
            "unlocked uses field 0"
        )
        let unlockedOrigin = LegacyWaveform.drawingPosition(
            locked: false,
            fieldPosition: 48,
            firstBGMVPosition: 192
        )
        let unlockedSegments = LegacyWaveform.segments(
            headBPM: 120,
            bpmEvents: [],
            lockPosition: unlockedOrigin
        )
        let unlockedIndex = LegacyWaveform.sampleIndex(
            vPosition: 96,
            segments: unlockedSegments,
            sampleRate: 44100
        )
        require(unlockedIndex == 22050, "unlocked origin 48 then 48 vpos is one beat")
        let fieldStillZero: Double = 0
        require(
            LegacyWaveform.drawingPosition(
                locked: true,
                fieldPosition: fieldStillZero,
                firstBGMVPosition: 192
            ) == 192,
            "locked drawing 192 does not change field"
        )
        require(fieldStillZero == 0, "field stays 0 when lock draws 192")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
