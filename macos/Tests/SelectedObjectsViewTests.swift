import AppKit

@main
struct SelectedObjectsViewTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let view = BmsONESelectedObjectsView(frame: NSRect(x: 0, y: 0, width: 200, height: 180))
        var heightChanges = 0
        view.onHeightChange = { heightChanges += 1 }
        let empty = BmsonSelectedObjects.Display(message: "", lengthEnabled: false, lengthText: "", lengthPlaceholder: "", extraText: "")
        view.apply(empty)
        require(view.preferredHeight == 36, "empty view is compact")
        require(view.subviews.filter { $0 is NSButton || $0 is NSScrollView }.allSatisfy(\.isHidden), "empty edit controls are hidden")
        let selected = BmsonSelectedObjects.Display(message: "2 selected notes", lengthEnabled: true, lengthText: "", lengthPlaceholder: "multiple values", extraText: "(multiple values)")
        view.apply(selected)
        require(view.preferredHeight == 92 && heightChanges == 1, "selection expands and relayouts")
        require(view.subviews.filter { $0 is NSButton || $0 is NSScrollView }.contains { !$0.isHidden }, "selected edit controls are visible")
        view.apply(empty)
        require(view.preferredHeight == 36 && heightChanges == 2, "clearing selection compacts and relayouts")
        require(view.subviews.filter { $0 is NSButton || $0 is NSScrollView }.allSatisfy(\.isHidden), "cleared edit controls are hidden")
        print("SelectedObjectsViewTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
