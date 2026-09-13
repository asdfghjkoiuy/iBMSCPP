import AppKit

@main
struct GeneralOptionsLocalizationTests {
    @MainActor
    static func main() {
        let suite = "IBMSNative.GeneralOptionsLocalization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        NativeLocalization.setDefaultsForTesting(defaults)
        defer {
            NativeLocalization.setDefaultsForTesting(nil)
            defaults.removePersistentDomain(forName: suite)
        }

        NativeLocalization.useChineseSimplified()
        _ = NSApplication.shared
        let controller = GeneralOptionsWindowController()
        let window = controller.window!
        require(window.title == "常规选项", "constructed window title is localized")
        let controls = allViews(window.contentView!).compactMap { view -> String? in
            if let button = view as? NSButton { return button.title }
            if let field = view as? NSTextField, !field.isEditable { return field.stringValue }
            return nil
        }
        require(controls.contains("自动保存"), "constructed checkbox is localized")
        require(controls.contains("保存时发出提示音"), "constructed checkbox text is localized")
        let editable = allViews(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable }
        editable?.stringValue = "File"

        NativeLocalization.useEnglish()
        NativeLocalization.localize(window: window)
        require(window.title == "General Options", "window restores English")
        require(allViews(window.contentView!).compactMap { ($0 as? NSButton)?.title }.contains("AutoSave"),
                "control restores English")
        require(editable?.stringValue == "File", "editable user value is preserved")
        NativeLocalization.useChineseSimplified()
        NativeLocalization.localize(window: window)
        require(editable?.stringValue == "File", "editable value survives language round trip")
        require(EditorSettings.legacyDefault.players[0].path == "<apppath>\\uBMplay.exe",
                "user and protocol values are not changed")
        print("GeneralOptionsLocalizationTests passed")
    }

    @MainActor
    private static func allViews(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(allViews)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
