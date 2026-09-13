import AppKit

@main
struct BmhelperWindowLayoutTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let controller = BmhelperWindowController()
        let window = controller.window!
        verify(controller, window: window, size: BmhelperMainLayout.clientSize)
        verify(controller, window: window, size: BmhelperMainLayout.minimumWindowSize)
        require(controller.definitionsCloseButtonWorksForTesting(), "WAV definitions close button closes its window")

        let slicer = AudioSlicerWindowController()
        require(!slicer.previousPreviewEnabledForTesting(), "previous preview is disabled without audio")
        print("BmhelperWindowLayoutTests passed")
    }

    @MainActor
    private static func verify(_ controller: BmhelperWindowController, window: NSWindow, size: CGSize) {
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        guard let snapshot = controller.layoutSnapshotForTesting() else {
            fatalError("main workspace snapshot")
        }
        require(snapshot.sourceFrame.height >= 220, "source MIDI remains visible")
        require(snapshot.divisionFrame.height > 0, "division workspace remains visible")
        require(snapshot.inspectorFrame.width >= 200, "action inspector remains visible")
        require(snapshot.actionFrames.count == 5, "five actions")
        for pair in zip(snapshot.actionFrames, snapshot.actionFrames.dropFirst()) {
            require(pair.0.height == 32 && pair.1.height == 32, "fixed action height")
            require(abs(pair.1.minY - pair.0.maxY - 8) < 0.01, "fixed action spacing")
        }
        require(snapshot.divisionFrame.maxY <= window.contentView!.bounds.maxY, "division workspace fits window")
        require(snapshot.definitionFrame.width > 0 && snapshot.definitionFrame.maxY <= window.contentView!.bounds.maxY, "definition bar fits window")
        require(snapshot.divisionListFrame.width > 0 && snapshot.divisionListFrame.maxY <= window.contentView!.bounds.maxY, "division list fits window")
        require(snapshot.transposeFrames.allSatisfy { $0.width > 0 && $0.maxY <= window.contentView!.bounds.maxY }, "transpose controls fit window")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
