import AppKit
import Foundation
import UniformTypeIdentifiers

/// AppKit-facing, appearance-only owner for original iBMSC theme XML.
///
/// The controller intentionally has no access to `DocumentSession` or chart mutation APIs. Its
/// `apply` callback is the sole integration point and must redraw appearance without marking a
/// BMS document dirty. The host owns menu insertion and the application's sheet/editing policy.
///
/// Menu order matches `cmnTheme` in `MainWindow.designer.vb`: (Default), Save Theme, Refresh,
/// Load Theme File from iBMSC 2.x, separator, then `*.Theme.xml` names from Refresh.
@MainActor
final class EditorThemeController: NSObject {
    typealias Apply = (ChartTheme) -> Void
    typealias SheetParent = () -> NSWindow?
    /// Return false while another host-owned sheet blocks presentation; each true must be paired
    /// with one `endSheet` call after the presented sheet finishes.
    typealias BeginSheet = () -> Bool
    typealias EndSheet = () -> Void

    private enum Persistence {
        static let xmlData = "org.ibmsc.native.editorTheme.xmlData"
        static let name = "org.ibmsc.native.editorTheme.name"
    }

    private struct BuiltinTheme: Sendable {
        let name: String
        let title: String

        static let all: [BuiltinTheme] = [
            BuiltinTheme(name: "IIDX", title: "IIDX"),
            BuiltinTheme(name: "O2Mania", title: "O2Mania"),
            BuiltinTheme(name: "BMSE", title: "BMSE"),
            BuiltinTheme(name: "BMSEmdk", title: "BMSE mdk"),
            BuiltinTheme(name: "BMSEmdkp", title: "BMSE mdkp"),
            BuiltinTheme(name: "Forme", title: "Forme"),
            BuiltinTheme(name: "MyO2_4K", title: "MyO2 4K"),
            BuiltinTheme(name: "Pomu", title: "Pomu")
        ]
    }

    let menu: NSMenu
    let dataDirectory: URL
    private(set) var currentTheme: ChartTheme
    /// Human-readable non-fatal codec notes, retained for an editor status area if the host has one.
    private(set) var lastDiagnostics: [String] = []
    private(set) var currentThemeName: String

    private let apply: Apply
    private let sheetParent: SheetParent
    private let beginSheet: BeginSheet
    private let endSheet: EndSheet
    private let defaults: UserDefaults
    private let resourceBundle: Bundle
    private let beepWhileSaved: () -> Bool

    static func defaultDataDirectory(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root
            .appendingPathComponent("IBMSNative", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    init(
        apply: @escaping Apply,
        sheetParent: @escaping SheetParent,
        beginSheet: @escaping BeginSheet,
        endSheet: @escaping EndSheet,
        defaults: UserDefaults = .standard,
        resourceBundle: Bundle = .main,
        dataDirectory: URL? = nil,
        beepWhileSaved: @escaping () -> Bool = { true }
    ) {
        self.apply = apply
        self.sheetParent = sheetParent
        self.beginSheet = beginSheet
        self.endSheet = endSheet
        self.defaults = defaults
        self.resourceBundle = resourceBundle
        self.dataDirectory = dataDirectory ?? EditorThemeController.defaultDataDirectory()
        self.beepWhileSaved = beepWhileSaved
        self.currentTheme = .defaultTheme
        self.currentThemeName = "Default"
        self.menu = NSMenu(title: "Theme")
        super.init()
        buildMenu()
        refreshThemeFiles()
        loadInitialTheme()
    }

    /// Restores a successfully exported theme, or applies the original IIDX resource. Invalid
    /// persisted XML is discarded and reported through `lastDiagnostics`; it never reaches render code.
    /// Startup matches `Form_Load`: Refresh only, never `(Default)`.
    func loadInitialTheme() {
        lastDiagnostics = []
        var startupDiagnostics = [String]()
        if let data = defaults.data(forKey: Persistence.xmlData) {
            do {
                let result = try ChartThemeCodec.importTheme(data: data, base: .defaultTheme)
                let name = defaults.string(forKey: Persistence.name) ?? "Restored theme"
                try stageAndApply(result.theme, name: name, diagnostics: result.diagnostics.map(\.description))
                return
            } catch {
                defaults.removeObject(forKey: Persistence.xmlData)
                defaults.removeObject(forKey: Persistence.name)
                startupDiagnostics.append("Saved theme was ignored: \(editorMessage(for: error))")
            }
        }

        do {
            let result = try ChartThemeCodec.importTheme(data: bundledData(named: "IIDX"), base: .defaultTheme)
            try stageAndApply(result.theme, name: "IIDX", diagnostics: result.diagnostics.map(\.description))
            lastDiagnostics = startupDiagnostics + lastDiagnostics
        } catch {
            // Do not claim this is IIDX when resource bundling has not been configured yet.
            currentTheme = .defaultTheme
            currentThemeName = "Default"
            apply(currentTheme)
            lastDiagnostics = startupDiagnostics + ["Bundled IIDX theme is unavailable: \(editorMessage(for: error))"]
        }
    }

    /// Writes a theme edited in Visual Options. Appearance only; the open BMS stays clean.
    func applyEditedTheme(_ theme: ChartTheme, name: String) throws {
        try stageAndApply(theme, name: name, diagnostics: [])
    }

    /// Applies any of the eight bundled, byte-for-byte original resources without touching BMS state.
    func selectBuiltin(named name: String) {
        guard BuiltinTheme.all.contains(where: { $0.name == name }) else {
            presentAlert(title: "Theme Unavailable", message: "Unknown bundled theme '\(name)'.", style: .warning)
            return
        }
        do {
            let result = try ChartThemeCodec.importTheme(data: bundledData(named: name), base: .defaultTheme)
            try stageAndApply(result.theme, name: name, diagnostics: result.diagnostics.map(\.description))
            if !lastDiagnostics.isEmpty { presentDiagnostics(lastDiagnostics) }
        } catch {
            presentAlert(title: "Theme Unavailable", message: editorMessage(for: error), style: .warning)
        }
    }

    /// `(Default)` / `TBThemeDef`: load bundled O2Mania. Does not mark the chart modified.
    @objc func applyDefaultTheme(_ sender: Any? = nil) {
        selectBuiltin(named: "O2Mania")
    }

    /// `Save Theme` / `TBThemeSave`. Cancel writes nothing. Initial folder is the injected Data directory.
    @objc func saveTheme(_ sender: Any? = nil) {
        guard let parent = sheetParent(), beginSheet() else { return }
        let panel = NSSavePanel()
        panel.title = "Save Theme"
        panel.message = "iBMSC Theme File (*.Theme.xml)"
        panel.nameFieldStringValue = sanitizedFilename(currentThemeName) + ".Theme.xml"
        panel.directoryURL = dataDirectory
        panel.allowedContentTypes = [.xml]
        panel.canCreateDirectories = true
        let finishSheet = endSheet
        panel.beginSheetModal(for: parent) { [weak self] response in
            guard let self else { finishSheet(); return }
            var message: String?
            var didWrite = false
            if response == .OK, let url = panel.url {
                do {
                    try self.writeTheme(to: url)
                    didWrite = true
                } catch {
                    message = self.editorMessage(for: error)
                }
            }
            self.endSheet()
            if let message {
                self.presentAlert(title: "Error", message: message, style: .warning)
            } else if didWrite {
                if self.beepWhileSaved() { NSSound.beep() }
                self.refreshThemeFiles()
            }
        }
    }

    /// `Refresh` / `TBThemeRefresh`: create Data if needed, then merge bundled and user `*.Theme.xml`.
    @objc func refreshThemeFiles(_ sender: Any? = nil) {
        while menu.items.count > 5 {
            menu.removeItem(at: menu.items.count - 1)
        }

        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        } catch {
            presentAlert(title: "Error", message: editorMessage(for: error), style: .warning)
        }

        for name in scannedThemeFileNames() {
            let item = NSMenuItem(title: name, action: #selector(loadScannedTheme(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    /// `Load Theme File from iBMSC 2.x`. Filter text matches `Strings.FileType.TH`; cancel loads nothing.
    @objc func loadThemeCompatibility(_ sender: Any? = nil) {
        guard let parent = sheetParent(), beginSheet() else { return }
        let panel = NSOpenPanel()
        panel.title = "Load Theme File from iBMSC 2.x"
        panel.message = "iBMSC 2.x Theme File (*.Theme.xml)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.item, .data]
        if let th = UTType(filenameExtension: "th") {
            types.insert(th, at: 0)
        }
        panel.allowedContentTypes = types
        panel.directoryURL = compatibilityInitialDirectory()
        let finishSheet = endSheet
        panel.beginSheetModal(for: parent) { [weak self] response in
            guard let self else { finishSheet(); return }
            var message: String?
            if response == .OK, let url = panel.url {
                do {
                    try self.applyCompatibilityFile(url)
                } catch {
                    message = self.editorMessage(for: error)
                }
            }
            self.endSheet()
            if let message { self.presentAlert(title: "Error", message: message, style: .warning) }
        }
    }

    private func buildMenu() {
        addMenuItem(title: "(Default)", action: #selector(applyDefaultTheme(_:)))
        addMenuItem(title: "Save Theme", action: #selector(saveTheme(_:)))
        addMenuItem(title: "Refresh", action: #selector(refreshThemeFiles(_:)))
        addMenuItem(title: "Load Theme File from iBMSC 2.x", action: #selector(loadThemeCompatibility(_:)))
        menu.addItem(.separator())
    }

    private func addMenuItem(title: String, action: Selector) {
        let item = NSMenuItem(title: NativeLocalization.text(title), action: action, keyEquivalent: "")
        NativeLocalization.markFixed(item, key: title)
        item.target = self
        menu.addItem(item)
    }

    @objc private func loadScannedTheme(_ sender: NSMenuItem) {
        let filename = sender.title
        do {
            let data = try themeFileData(named: filename)
            let result = try ChartThemeCodec.importTheme(data: data, base: .defaultTheme)
            try stageAndApply(result.theme, name: filename, diagnostics: result.diagnostics.map(\.description))
            if !lastDiagnostics.isEmpty { presentDiagnostics(lastDiagnostics) }
        } catch {
            presentAlert(title: "Error", message: editorMessage(for: error), style: .warning)
        }
    }

    /// Export first so a valid persistence payload exists before the host redraws the new appearance.
    private func stageAndApply(_ theme: ChartTheme, name: String, diagnostics: [String]) throws {
        let data = try ChartThemeCodec.exportTheme(theme)
        defaults.set(data, forKey: Persistence.xmlData)
        defaults.set(name, forKey: Persistence.name)
        currentTheme = theme
        currentThemeName = name
        lastDiagnostics = diagnostics
        apply(theme)
    }

    private func writeTheme(to url: URL) throws {
        let data = try ChartThemeCodec.exportTheme(currentTheme)
        try data.write(to: url, options: .atomic)
    }

    private func applyCompatibilityFile(_ url: URL) throws {
        let text = try readThemeText(url)
        guard let theme = LegacyThemeCompatibility.parse(text, base: currentTheme) else { return }
        try stageAndApply(theme, name: url.lastPathComponent, diagnostics: [])
    }

    private func readThemeText(_ url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .utf16) {
            return text
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func scannedThemeFileNames() -> [String] {
        var names = Set<String>()
        if let urls = resourceBundle.urls(forResourcesWithExtension: "xml", subdirectory: "Themes") {
            for url in urls where url.lastPathComponent.hasSuffix(".Theme.xml") {
                names.insert(url.lastPathComponent)
            }
        }
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: dataDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in urls where url.lastPathComponent.hasSuffix(".Theme.xml") {
                names.insert(url.lastPathComponent)
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func themeFileData(named filename: String) throws -> Data {
        let userURL = dataDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: userURL.path) {
            return try Data(contentsOf: userURL, options: [.mappedIfSafe])
        }
        return try bundledData(named: themeResourceName(filename))
    }

    private func themeResourceName(_ filename: String) -> String {
        let suffix = ".Theme.xml"
        if filename.count > suffix.count, filename.hasSuffix(suffix) {
            return String(filename.dropLast(suffix.count))
        }
        return (filename as NSString).deletingPathExtension
    }

    private func bundledData(named name: String) throws -> Data {
        guard let url = resourceBundle.url(forResource: name, withExtension: "Theme.xml", subdirectory: "Themes") else {
            throw ThemeCodecError.resourceNotFound(name)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func compatibilityInitialDirectory() -> URL {
        var directory = resourceBundle.bundleURL
        if directory.pathExtension == "app" {
            directory = directory.deletingLastPathComponent()
        }
        let themeDirectory = directory.appendingPathComponent("Theme", isDirectory: true)
        if FileManager.default.fileExists(atPath: themeDirectory.path) {
            return themeDirectory
        }
        return directory
    }

    private func presentDiagnostics(_ diagnostics: [String]) {
        presentAlert(title: "Theme Imported with Notes", message: diagnostics.joined(separator: "\n"), style: .informational)
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        guard let parent = sheetParent(), beginSheet() else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.beginSheetModal(for: parent) { [endSheet] _ in endSheet() }
    }

    private func editorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let result = name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "iBMSC-Theme" : result
    }
}
