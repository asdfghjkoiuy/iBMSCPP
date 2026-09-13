import Foundation

/// One external player row from `MainWindow.PlayerArguments`.
struct PlayerArguments: Equatable, Sendable, Codable {
    var path: String
    var playFromBeginning: String
    var playFromMeasure: String
    var stop: String

    static let legacyDefaults: [PlayerArguments] = [
        PlayerArguments(
            path: "<apppath>\\uBMplay.exe",
            playFromBeginning: "-P -N0 \"<filename>\"",
            playFromMeasure: "-P -N<measure> \"<filename>\"",
            stop: "-S"
        ),
        PlayerArguments(
            path: "<apppath>\\o2play.exe",
            playFromBeginning: "-P -N0 \"<filename>\"",
            playFromMeasure: "-P -N<measure> \"<filename>\"",
            stop: "-S"
        )
    ]
}

/// General and player options stored outside any BMS document.
struct EditorSettings: Equatable, Sendable {
    var wheelStep: Int
    var pageStep: Int
    /// `0` = click and auto scroll, `1` = click and drag.
    var middleButtonMoveMethod: Int
    var autoSaveMilliseconds: Int
    var beepWhileSaved: Bool
    var bpm1296: Bool
    var stop1296: Bool
    var mouseEnterFocus: Bool
    var firstClickDisabled: Bool
    var stopPreviewOnClick: Bool
    var gridPartition: Int
    var textEncodingIndex: Int
    var players: [PlayerArguments]
    var currentPlayer: Int

    static let legacyDefault = EditorSettings(
        wheelStep: 96,
        pageStep: 384,
        middleButtonMoveMethod: 0,
        autoSaveMilliseconds: 120_000,
        beepWhileSaved: true,
        bpm1296: false,
        stop1296: false,
        mouseEnterFocus: false,
        firstClickDisabled: false,
        stopPreviewOnClick: true,
        gridPartition: 192,
        textEncodingIndex: 0,
        players: PlayerArguments.legacyDefaults,
        currentPlayer: 0
    )

    var currentPlayerArguments: PlayerArguments? {
        players.indices.contains(currentPlayer) ? players[currentPlayer] : players.first
    }

    /// `MainWindow.vb` `BMSGridLimit = 192 / zGridPartition`.
    var bmsGridLimit: Double {
        192.0 / Double(max(1, gridPartition))
    }
}

enum EditorSettingsKeys {
    static let wheelStep = "org.ibmsc.native.general.wheel"
    static let pageStep = "org.ibmsc.native.general.pageUpDown"
    static let middleButton = "org.ibmsc.native.general.middleButton"
    static let autoSave = "org.ibmsc.native.general.autoSaveMilliseconds"
    static let beep = "org.ibmsc.native.general.beepWhileSaved"
    static let bpm1296 = "org.ibmsc.native.general.bpm1296"
    static let stop1296 = "org.ibmsc.native.general.stop1296"
    static let mouseEnterFocus = "org.ibmsc.native.general.mouseEnterFocus"
    static let firstClickDisabled = "org.ibmsc.native.general.firstClickDisabled"
    static let stopPreview = "org.ibmsc.native.general.stopPreviewOnClick"
    static let gridPartition = "org.ibmsc.native.general.gridPartition"
    static let encoding = "org.ibmsc.native.general.textEncodingIndex"
    static let players = "org.ibmsc.native.player.argumentsJSON"
    static let currentPlayer = "org.ibmsc.native.player.currentIndex"
}

extension EditorSettings {
    static func load(from defaults: UserDefaults) -> EditorSettings {
        var settings = EditorSettings.legacyDefault
        if defaults.object(forKey: EditorSettingsKeys.wheelStep) != nil {
            settings.wheelStep = defaults.integer(forKey: EditorSettingsKeys.wheelStep)
        }
        if defaults.object(forKey: EditorSettingsKeys.pageStep) != nil {
            settings.pageStep = defaults.integer(forKey: EditorSettingsKeys.pageStep)
        }
        if defaults.object(forKey: EditorSettingsKeys.middleButton) != nil {
            settings.middleButtonMoveMethod = defaults.integer(forKey: EditorSettingsKeys.middleButton)
        }
        if defaults.object(forKey: EditorSettingsKeys.autoSave) != nil {
            settings.autoSaveMilliseconds = defaults.integer(forKey: EditorSettingsKeys.autoSave)
        }
        if defaults.object(forKey: EditorSettingsKeys.beep) != nil {
            settings.beepWhileSaved = defaults.bool(forKey: EditorSettingsKeys.beep)
        }
        if defaults.object(forKey: EditorSettingsKeys.bpm1296) != nil {
            settings.bpm1296 = defaults.bool(forKey: EditorSettingsKeys.bpm1296)
        }
        if defaults.object(forKey: EditorSettingsKeys.stop1296) != nil {
            settings.stop1296 = defaults.bool(forKey: EditorSettingsKeys.stop1296)
        }
        if defaults.object(forKey: EditorSettingsKeys.mouseEnterFocus) != nil {
            settings.mouseEnterFocus = defaults.bool(forKey: EditorSettingsKeys.mouseEnterFocus)
        }
        if defaults.object(forKey: EditorSettingsKeys.firstClickDisabled) != nil {
            settings.firstClickDisabled = defaults.bool(forKey: EditorSettingsKeys.firstClickDisabled)
        }
        if defaults.object(forKey: EditorSettingsKeys.stopPreview) != nil {
            settings.stopPreviewOnClick = defaults.bool(forKey: EditorSettingsKeys.stopPreview)
        }
        if defaults.object(forKey: EditorSettingsKeys.gridPartition) != nil {
            settings.gridPartition = defaults.integer(forKey: EditorSettingsKeys.gridPartition)
        }
        if defaults.object(forKey: EditorSettingsKeys.encoding) != nil {
            settings.textEncodingIndex = defaults.integer(forKey: EditorSettingsKeys.encoding)
        }
        if let data = defaults.data(forKey: EditorSettingsKeys.players),
           let decoded = try? JSONDecoder().decode([PlayerArguments].self, from: data),
           !decoded.isEmpty {
            settings.players = decoded
        }
        if defaults.object(forKey: EditorSettingsKeys.currentPlayer) != nil {
            settings.currentPlayer = defaults.integer(forKey: EditorSettingsKeys.currentPlayer)
        }
        return settings.normalized()
    }

    func save(to defaults: UserDefaults) {
        let settings = normalized()
        defaults.set(settings.wheelStep, forKey: EditorSettingsKeys.wheelStep)
        defaults.set(settings.pageStep, forKey: EditorSettingsKeys.pageStep)
        defaults.set(settings.middleButtonMoveMethod, forKey: EditorSettingsKeys.middleButton)
        defaults.set(settings.autoSaveMilliseconds, forKey: EditorSettingsKeys.autoSave)
        defaults.set(settings.beepWhileSaved, forKey: EditorSettingsKeys.beep)
        defaults.set(settings.bpm1296, forKey: EditorSettingsKeys.bpm1296)
        defaults.set(settings.stop1296, forKey: EditorSettingsKeys.stop1296)
        defaults.set(settings.mouseEnterFocus, forKey: EditorSettingsKeys.mouseEnterFocus)
        defaults.set(settings.firstClickDisabled, forKey: EditorSettingsKeys.firstClickDisabled)
        defaults.set(settings.stopPreviewOnClick, forKey: EditorSettingsKeys.stopPreview)
        defaults.set(settings.gridPartition, forKey: EditorSettingsKeys.gridPartition)
        defaults.set(settings.textEncodingIndex, forKey: EditorSettingsKeys.encoding)
        defaults.set(settings.currentPlayer, forKey: EditorSettingsKeys.currentPlayer)
        if let data = try? JSONEncoder().encode(settings.players) {
            defaults.set(data, forKey: EditorSettingsKeys.players)
        }
    }

    func normalized() -> EditorSettings {
        var next = self
        if GeneralOptionsLayout.wheelValues.contains(next.wheelStep) == false {
            next.wheelStep = EditorSettings.legacyDefault.wheelStep
        }
        if GeneralOptionsLayout.pageValues.contains(next.pageStep) == false {
            next.pageStep = EditorSettings.legacyDefault.pageStep
        }
        next.middleButtonMoveMethod = next.middleButtonMoveMethod == 1 ? 1 : 0
        next.gridPartition = min(
            GeneralOptionsLayout.gridPartitionRange.upperBound,
            max(GeneralOptionsLayout.gridPartitionRange.lowerBound, next.gridPartition)
        )
        next.textEncodingIndex = min(GeneralOptionsLayout.encodingTitles.count - 1, max(0, next.textEncodingIndex))
        if next.players.isEmpty {
            next.players = PlayerArguments.legacyDefaults
            next.currentPlayer = 0
        } else {
            next.currentPlayer = min(next.players.count - 1, max(0, next.currentPlayer))
        }
        if next.autoSaveMilliseconds < 0 {
            next.autoSaveMilliseconds = 0
        }
        return next
    }
}

final class EditorSettingsStore {
    private let defaults: UserDefaults
    private(set) var settings: EditorSettings
    var onChange: ((EditorSettings) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = EditorSettings.load(from: defaults)
    }

    func replace(_ settings: EditorSettings) {
        let next = settings.normalized()
        self.settings = next
        next.save(to: defaults)
        onChange?(next)
    }

    func updateCurrentPlayerPath(_ path: String) {
        var next = settings
        guard next.players.indices.contains(next.currentPlayer) else { return }
        next.players[next.currentPlayer].path = path
        replace(next)
    }
}

enum LegacyExternalPlayerKind: Equatable {
    case begin
    case here
    case stop
}

/// iBMSC `PrevCodeToReal` / `TBPlayB` / `TBPlay` / `TBStop` / `PlayerMissingPrompt`.
enum LegacyExternalPlayer {
    static let missingTitle = "Player not found"
    static let tempFileName = "___TempBMS.bms"

    /// Original `PathIsValid` is `File.Exists Or Directory.Exists`.
    static func pathIsValid(_ path: String?, fileManager: FileManager = .default) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return fileManager.fileExists(atPath: path)
    }

    static func tempBMSPath(fileName: String?, initPath: String?, appPath: String) -> String {
        let directory: String
        if let fileName, !fileName.isEmpty {
            directory = excludeFileName(fileName)
        } else if let initPath, !initPath.isEmpty {
            directory = initPath
        } else {
            directory = appPath
        }
        return join(directory, tempFileName)
    }

    /// Replace order matches three `Replace` calls: `<apppath>` then `<measure>` then `<filename>`.
    static func substitute(_ template: String, appPath: String, measure: Int, fileName: String) -> String {
        var text = template.replacingOccurrences(of: "<apppath>", with: appPath)
        text = text.replacingOccurrences(of: "<measure>", with: String(measure))
        text = text.replacingOccurrences(of: "<filename>", with: fileName)
        return text
    }

    static func programPath(_ template: String, appPath: String) -> String {
        template.replacingOccurrences(of: "<apppath>", with: appPath)
            .replacingOccurrences(of: "\\", with: "/")
    }

    static func missingMessage(_ path: String) -> String {
        "Cannot find file \(path).\r\nPlease respecify path."
    }

    static func writesTempFile(_ kind: LegacyExternalPlayerKind) -> Bool {
        kind != .stop
    }

    /// `Replace(picked, DirectoryPath, "<apppath>")` when `picked` is under `appPath`.
    static func storePickedPath(picked: String, appPath: String) -> String {
        let root = appPath.hasSuffix("/") || appPath.hasSuffix("\\")
            ? String(appPath.dropLast())
            : appPath
        if picked == root {
            return "<apppath>"
        }
        if picked.hasPrefix(root + "/") || picked.hasPrefix(root + "\\") {
            return "<apppath>" + String(picked.dropFirst(root.count))
        }
        return picked
    }

    /// `MeasureAtDisplacement(Abs(PanelVScroll))` with the default 192-grid bottoms.
    static func measureFromScroll(_ scrollVS: Double, measureLength: Double = 192) -> Int {
        max(0, Int(floor(abs(scrollVS) / measureLength)))
    }

    static func argumentTemplate(_ player: PlayerArguments, kind: LegacyExternalPlayerKind) -> String {
        switch kind {
        case .begin:
            return player.playFromBeginning
        case .here:
            return player.playFromMeasure
        case .stop:
            return player.stop
        }
    }

    static func encodedSaveData(_ utf8Data: Data, encoding: String.Encoding) -> Data {
        guard encoding != .utf8,
              let text = String(data: utf8Data, encoding: .utf8),
              let encoded = text.data(using: encoding, allowLossyConversion: false) else {
            return utf8Data
        }
        return encoded
    }

    private static func excludeFileName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func join(_ directory: String, _ name: String) -> String {
        URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
    }
}
