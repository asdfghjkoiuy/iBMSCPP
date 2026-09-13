import AppKit
import Foundation

@main
struct EditorThemeControllerTests {
    @MainActor
    static func main() throws {
        let localeSuite = "IBMSNative.EditorThemeControllerTests.\(UUID().uuidString)"
        let localeDefaults = UserDefaults(suiteName: localeSuite)!
        NativeLocalization.setDefaultsForTesting(localeDefaults)
        NativeLocalization.useEnglish()
        defer {
            NativeLocalization.setDefaultsForTesting(nil)
            localeDefaults.removePersistentDomain(forName: localeSuite)
        }
        try withFixtureBundle { bundle in
            try restoresIIDXAndSwitchesToPersistedO2Mania(bundle: bundle)
            try ignoresInvalidSavedThemeAndFallsBackToIIDX(bundle: bundle)
            try themeMenuMatchesDesignerAndDefaultLoadsO2Mania(bundle: bundle)
            try refreshListsUserAndBundledThemeFiles(bundle: bundle)
        }
        print("EditorThemeControllerTests passed")
    }

    @MainActor
    private static func restoresIIDXAndSwitchesToPersistedO2Mania(bundle: Bundle) throws {
        let (defaults, suite) = temporaryDefaults()
        let dataDirectory = temporaryDataDirectory()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dataDirectory)
        }
        var applied = [ChartTheme]()
        let controller = EditorThemeController(
            apply: { applied.append($0) },
            sheetParent: { nil },
            beginSheet: { false },
            endSheet: {},
            defaults: defaults,
            resourceBundle: bundle,
            dataDirectory: dataDirectory
        )

        let expectedIIDX = try fixtureTheme(named: "IIDX", bundle: bundle)
        require(controller.currentTheme == expectedIIDX && controller.currentThemeName == "IIDX",
                "fresh controller must stage bundled IIDX")
        require(applied == [expectedIIDX], "IIDX startup must apply exactly once")
        try requireDesignerMenu(controller.menu)

        controller.selectBuiltin(named: "O2Mania")
        let expectedO2 = try fixtureTheme(named: "O2Mania", bundle: bundle)
        require(controller.currentTheme == expectedO2 && applied.last == expectedO2,
                "built-in selection must apply O2Mania")
        require(defaults.string(forKey: "org.ibmsc.native.editorTheme.name") == "O2Mania",
                "built-in selection must persist its name")
        let persisted = try ChartThemeCodec.importTheme(data: try required(defaults.data(forKey: "org.ibmsc.native.editorTheme.xmlData"))).theme
        require(persisted == expectedO2, "built-in selection must persist exported XML")

        var restoredApplications = [ChartTheme]()
        let restoredController = EditorThemeController(
            apply: { restoredApplications.append($0) },
            sheetParent: { nil },
            beginSheet: { false },
            endSheet: {},
            defaults: defaults,
            resourceBundle: bundle,
            dataDirectory: dataDirectory
        )
        require(restoredController.currentTheme == expectedO2 && restoredController.currentThemeName == "O2Mania",
                "a second controller must restore persisted O2Mania XML")
        require(restoredApplications == [expectedO2], "restored theme must apply exactly once")

        var edited = expectedO2
        edited.visual.noteHeight = 12
        try restoredController.applyEditedTheme(edited, name: "O2Mania")
        require(restoredController.currentTheme.visual.noteHeight == 12, "Visual Options must write the edited theme")
        require(restoredController.currentThemeName == "O2Mania", "edited theme keeps its name")
        try requireDesignerMenu(restoredController.menu)
    }

    @MainActor
    private static func ignoresInvalidSavedThemeAndFallsBackToIIDX(bundle: Bundle) throws {
        let (defaults, suite) = temporaryDefaults()
        let dataDirectory = temporaryDataDirectory()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dataDirectory)
        }
        defaults.set(Data("<iBMSC>".utf8), forKey: "org.ibmsc.native.editorTheme.xmlData")
        defaults.set("Broken", forKey: "org.ibmsc.native.editorTheme.name")
        var callbackCount = 0
        let controller = EditorThemeController(
            apply: { _ in callbackCount += 1 },
            sheetParent: { nil },
            beginSheet: { false },
            endSheet: {},
            defaults: defaults,
            resourceBundle: bundle,
            dataDirectory: dataDirectory
        )
        let expectedIIDX = try fixtureTheme(named: "IIDX", bundle: bundle)
        require(controller.currentTheme == expectedIIDX,
                "invalid persisted XML must fall back to bundled IIDX")
        require(controller.lastDiagnostics.contains { $0.contains("Saved theme was ignored") },
                "invalid persisted XML must leave an editor-friendly diagnostic")
        require(callbackCount == 1, "invalid saved XML must never be applied")
        try requireDesignerMenu(controller.menu)
    }

    @MainActor
    private static func themeMenuMatchesDesignerAndDefaultLoadsO2Mania(bundle: Bundle) throws {
        let (defaults, suite) = temporaryDefaults()
        let dataDirectory = temporaryDataDirectory()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dataDirectory)
        }
        let controller = EditorThemeController(
            apply: { _ in },
            sheetParent: { nil },
            beginSheet: { false },
            endSheet: {},
            defaults: defaults,
            resourceBundle: bundle,
            dataDirectory: dataDirectory
        )
        try requireDesignerMenu(controller.menu)
        require(controller.menu.item(at: 0)?.submenu == nil, "Theme menu must not start with a Built-in Themes submenu")

        let expectedIIDX = try fixtureTheme(named: "IIDX", bundle: bundle)
        require(controller.currentTheme == expectedIIDX, "startup must still restore IIDX, not click Default")

        invoke(controller.menu, at: 0)
        let expectedO2 = try fixtureTheme(named: "O2Mania", bundle: bundle)
        require(controller.currentTheme == expectedO2, "Default must load bundled O2Mania")
    }

    @MainActor
    private static func refreshListsUserAndBundledThemeFiles(bundle: Bundle) throws {
        let (defaults, suite) = temporaryDefaults()
        let dataDirectory = temporaryDataDirectory()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dataDirectory)
        }
        let controller = EditorThemeController(
            apply: { _ in },
            sheetParent: { nil },
            beginSheet: { false },
            endSheet: {},
            defaults: defaults,
            resourceBundle: bundle,
            dataDirectory: dataDirectory
        )

        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let userURL = dataDirectory.appendingPathComponent("User.Theme.xml")
        try ChartThemeCodec.exportTheme(controller.currentTheme).write(to: userURL)
        invoke(controller.menu, at: 2)

        try requireDesignerMenu(controller.menu)
        let scanned = controller.menu.items.dropFirst(5).map(\.title)
        require(scanned.contains("User.Theme.xml"), "Refresh must list the user Data file by filename")
        require(scanned.contains("IIDX.Theme.xml"), "Refresh must list bundled IIDX.Theme.xml")
        require(scanned.contains("O2Mania.Theme.xml"), "Refresh must list bundled O2Mania.Theme.xml")
    }

    private static func invoke(_ menu: NSMenu, at index: Int) {
        guard let item = menu.item(at: index), let action = item.action else {
            fatalError("menu item \(index) has no action")
        }
        let target = (item.target as AnyObject?) ?? menu
        _ = target.perform(action, with: item)
    }

    private static func requireDesignerMenu(_ menu: NSMenu) throws {
        require(menu.item(at: 0)?.title == "(Default)", "item 0 must be (Default)")
        require(menu.item(at: 1)?.title == "Save Theme", "item 1 must be Save Theme")
        require(menu.item(at: 2)?.title == "Refresh", "item 2 must be Refresh")
        require(menu.item(at: 3)?.title == "Load Theme File from iBMSC 2.x",
                "item 3 must be Load Theme File from iBMSC 2.x")
        require(menu.item(at: 4)?.isSeparatorItem == true, "item 4 must be the separator")
    }

    private static func withFixtureBundle(_ body: (Bundle) throws -> Void) throws {
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EditorThemeControllerTests-\(UUID().uuidString).bundle", isDirectory: true)
        let resources = fixture.appendingPathComponent("Contents/Resources/Themes", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.ibmsc.theme-test</string></dict></plist>"
        try Data(plist.utf8).write(to: fixture.appendingPathComponent("Contents/Info.plist"))
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for name in ["IIDX", "O2Mania"] {
            try FileManager.default.copyItem(
                at: project.appendingPathComponent("macos/Resources/Themes/\(name).Theme.xml"),
                to: resources.appendingPathComponent("\(name).Theme.xml")
            )
        }
        defer { try? FileManager.default.removeItem(at: fixture) }
        guard let bundle = Bundle(path: fixture.path) else { throw TestError("fixture bundle could not load") }
        try body(bundle)
    }

    private static func fixtureTheme(named name: String, bundle: Bundle) throws -> ChartTheme {
        let url = try required(bundle.url(forResource: name, withExtension: "Theme.xml", subdirectory: "Themes"))
        return try ChartThemeCodec.importTheme(data: Data(contentsOf: url)).theme
    }

    private static func temporaryDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "org.ibmsc.theme-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private static func temporaryDataDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EditorThemeData-\(UUID().uuidString)", isDirectory: true)
    }

    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw TestError("required test fixture value is missing") }
        return value
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    private struct TestError: Error, LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
