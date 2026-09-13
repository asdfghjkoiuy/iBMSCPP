import AppKit

@main
struct NativeLocalizationTests {
    static func main() {
        let suite = "IBMSNativeLocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let languageKey = "IBMSNative.NativeLanguage"
        let originalStandardLanguage = UserDefaults.standard.object(forKey: languageKey) as? String
        NativeLocalization.setDefaultsForTesting(defaults)
        defer {
            NativeLocalization.setDefaultsForTesting(nil)
            UserDefaults.standard.removePersistentDomain(forName: suite)
            require(
                (UserDefaults.standard.object(forKey: languageKey) as? String) == originalStandardLanguage,
                "standard defaults remain unchanged"
            )
        }
        NativeLocalization.useChineseSimplified()
        require(NativeLocalization.text("File") == "文件", "English source lookup")
        require(NativeLocalization.text("app.quit", fallback: "Quit IBMSNative") == "退出 IBMSNative", "semantic lookup")
        require(NativeLocalization.text("#WAV") == "#WAV", "protocol token remains unchanged")
        require(NativeLocalization.text("Audio File") == "音频文件", "audio tool lookup")
        require(NativeLocalization.text("0 selected notes") == "已选中 0 个音符", "zero selected-note state")
        require(NativeLocalization.text("1 selected note") == "已选中 1 个音符", "singular selected-note state")
        require(NativeLocalization.text("12 selected notes") == "已选中 12 个音符", "plural selected-note state")
        require(NativeLocalization.text("version 12 selected notes") == "version 12 selected notes", "similar user string remains unchanged")
        require(NativeLocalization.text("multiple values") == "多个值", "selected-object placeholder")
        require(
            NativeLocalization.format("Project has unsaved changes: %@", "demo") == "demo（有未保存的改动）。",
            "format placeholder"
        )

        let editable = NSTextField(string: "Save")
        let readOnlyData = NSTextField(string: "File")
        let label = NSTextField(labelWithString: NativeLocalization.text("Save"))
        NativeLocalization.markFixed(label, key: "Save")
        let button = NSButton(title: NativeLocalization.text("Open..."), target: nil, action: nil)
        NativeLocalization.markFixed(button, key: "Open...")
        let box = NSBox()
        box.title = NativeLocalization.text("Arguments")
        NativeLocalization.markFixed(box, key: "Arguments")
        NativeLocalization.markTooltip(button, key: "Audio file path")
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["1 - Single Play", "File"])
        let combo = NSComboBox()
        combo.addItems(withObjectValues: ["Save"])
        let root = NSView()
        root.addSubview(editable)
        root.addSubview(readOnlyData)
        root.addSubview(label)
        root.addSubview(button)
        root.addSubview(box)
        root.addSubview(popup)
        root.addSubview(combo)
        NativeLocalization.localize(view: root)
        require(editable.stringValue == "Save", "editable field is skipped")
        require(readOnlyData.stringValue == "File", "read-only data field is skipped")
        require(label.stringValue == "保存", "label is localized")
        require(button.title == "打开…", "button is localized")
        require(box.title == "参数", "box is localized")
        require(button.toolTip == "音频文件路径", "fixed tooltip is localized")
        require(popup.itemTitles == ["1 - Single Play", "File"], "popup data is skipped")
        require(combo.objectValues as? [String] == ["Save"], "combo data is skipped")

        NativeLocalization.useEnglish()
        NativeLocalization.localize(view: root)
        require(NativeLocalization.text("File") == "File", "English selection")
        require(NativeLocalization.text("12 selected notes") == "12 selected notes", "English selected-note state")
        require(label.stringValue == "Save" && button.title == "Open..." && box.title == "Arguments", "English restores source text")
        require(button.toolTip == "Audio file path", "English restores fixed tooltip")
        NativeLocalization.useChineseSimplified()
        NativeLocalization.localize(view: root)
        require(label.stringValue == "保存" && button.title == "打开…", "Chinese restores source text")
        require(
            (UserDefaults.standard.object(forKey: languageKey) as? String) == originalStandardLanguage,
            "standard defaults untouched"
        )
        NativeLocalization.useEnglish()
        require(defaults.string(forKey: "IBMSNative.NativeLanguage") == "en", "test suite stores choice")
        print("NativeLocalizationTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
