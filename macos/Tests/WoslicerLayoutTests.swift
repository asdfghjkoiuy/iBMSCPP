import Foundation

@main
struct WoslicerLayoutTests {
    static func main() {
        testTitles()
        testHelpCopy()
        testCommands()
        testGeometryPending()
        testWosFormatUnknown()
        testShellDoesNotClaimSlicing()
        print("WoslicerLayoutTests passed")
    }

    private static func testTitles() {
        require(WoslicerLayout.windowTitle == "woslicer II / III", "shell title")
        require(WoslicerLayout.iiProductName == "woslicerII", "II product name")
        require(WoslicerLayout.iiiProductName == "woslicerIII", "III product name")
        require(WoslicerLayout.author == "wosderge", "author")
    }

    private static func testHelpCopy() {
        require(WoslicerLayout.iiOverview.contains("wavスライサー"), "II overview")
        require(WoslicerLayout.iiLoadOGG.contains("ogg"), "OGG")
        require(WoslicerLayout.iiTrimTrailingSilence.contains("無音"), "trailing silence")
        require(WoslicerLayout.iiExportSlicedWAV.contains("_xxx.wav"), "batch WAV name")
        require(WoslicerLayout.wosFileNameRule.contains(".wos"), ".wos name rule")
        require(WoslicerLayout.iiiShowWaveform.contains("波形"), "waveform")
        require(WoslicerLayout.iiiDetectEdges.contains("エッジ"), "edge detection")
        require(WoslicerLayout.iiiPreviewCurrent.contains("現在"), "current preview")
        require(WoslicerLayout.iiiPreviewPrevious.contains("１つ前"), "previous preview")
        require(WoslicerLayout.iiiImportClip.contains("クリップ"), "clip import")
    }

    private static func testCommands() {
        require(WoslicerCommand.allCases.count == 24, "command enum count")
        require(WoslicerLayout.observedCapabilityCount == 24, "observed capability count")
        require(WoslicerLayout.commands.count == WoslicerCommand.allCases.count, "list matches enum")
        require(WoslicerLayout.commands.filter { $0.edition == .ii }.count == 16, "II count")
        require(WoslicerLayout.commands.filter { $0.edition == .iii }.count == 8, "III count")
        let ids = WoslicerLayout.commands.map(\.id)
        require(ids == WoslicerCommand.allCases.map(\.rawValue), "stable command ids")
        require(WoslicerLayout.commandListing.contains("[1][2][3][4]"), "BPM keys")
        require(WoslicerLayout.commandListing.contains("[Q][W]"), "grid keys")
        require(WoslicerLayout.commandListing.contains("[M]"), "export WAV")
        require(WoslicerLayout.commandListing.contains("[V]"), "BMSE clipboard")
        require(WoslicerLayout.commandListing.contains("[T][Y]"), ".wos keys")
        require(WoslicerLayout.commandListing.contains("[8][7]"), "global offset")
        require(WoslicerLayout.commandListing.contains("[O]"), "III previous preview")
    }

    private static func testGeometryPending() {
        require(WoslicerLayout.originalClientSize == nil, "client size is unmeasured")
        require(
            WoslicerLayout.originalClientSizeNote == "待运行时从 Windows 原版量",
            "geometry note"
        )
    }

    private static func testWosFormatUnknown() {
        require(!WoslicerLayout.wosFormatKnown, ".wos body is unknown")
        require(WoslicerLayout.wosFileNameRule.contains(".wav"), "filename replaces wav")
    }

    private static func testShellDoesNotClaimSlicing() {
        require(WoslicerLayout.slicingImplemented, "mark split is implemented")
        require(WoslicerLayout.clipboardImplemented, "BMSE clipboard is implemented")
        require(WoslicerLayout.previewImplemented, "preview is implemented")
        require(WoslicerLayout.waveformImplemented, "waveform is implemented")
        require(WoslicerLayout.trimImplemented, "trim is implemented")
        require(WoslicerLayout.shellStatus.contains("Audio Slicer"), "shared slicer")
        require(WoslicerLayout.shellStatus.contains("BMSE"), "shared clipboard")
        require(WoslicerLayout.shellStatus.contains("预览"), "shared preview")
        require(WoslicerLayout.shellStatus.contains("波形"), "shared waveform")
        require(WoslicerLayout.shellStatus.contains("末端"), "trailing silence")
        require(WoslicerLayout.shellStatus.contains("待运行时从 Windows 原版量"), "shell geometry")
        require(WoslicerLayout.shellStatus.contains(".wos"), "no .wos")
        require(WoslicerLayout.shellStatus.contains("边缘检测"), "no edge")
        require(WoslicerLayout.originalClientSize == nil, "client size still unmeasured")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
