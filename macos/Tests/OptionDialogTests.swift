import Foundation

@main
struct OptionDialogTests {
    static func main() {
        testLayouts()
        testMappings()
        testPlayerEdits()
        testSettingsPersistence()
        testColorCaption()
        testExternalPlayer()
        print("OptionDialogTests passed")
    }

    private static func testLayouts() {
        require(VisualOptionsLayout.clientSize == CGSize(width: 1026, height: 713), "OpVisual client size")
        require(VisualOptionsLayout.columnPanel == CGRect(x: 10, y: 263, width: 1004, height: 402), "OpVisual Panel1")
        require(VisualOptionsLayout.ok == CGRect(x: 871, y: 675, width: 67, height: 23), "OpVisual OK")
        require(VisualOptionsLayout.cancel == CGRect(x: 944, y: 675, width: 67, height: 23), "OpVisual Cancel")
        require(VisualOptionsLayout.columnLefts.count == 28 && VisualOptionsLayout.columnLefts[0] == 78
                    && VisualOptionsLayout.columnLefts[27] == 950,
                "OpVisual lLeft has 28 columns")
        require(VisualOptionsLayout.columnFrame(index: 0, row: .width) == CGRect(x: 78, y: 12, width: 33, height: 23),
                "first column width editor")
        require(VisualOptionsLayout.columnFrame(index: 27, row: .background) == CGRect(x: 950, y: 323, width: 33, height: 66),
                "BGM column background swatch")
        require(VisualOptionsLayout.globalRows.count == 27, "visual global rows")
        require(VisualOptionsLayout.globalRows.first?.title == "Column Caption", "first visual label")
        require(VisualOptionsLayout.globalRows.last?.control == CGRect(x: 870, y: 199, width: 80, height: 23),
                "middle sensitivity control")

        require(GeneralOptionsLayout.clientSize == CGSize(width: 413, height: 510), "OpGeneral client size")
        require(GeneralOptionsLayout.ok == CGRect(x: 232, y: 466, width: 78, height: 27), "OpGeneral OK")
        require(GeneralOptionsLayout.encoding.origin.x == 137 && GeneralOptionsLayout.associateBMS.width == 122,
                "OpGeneral encoding and *.bms")
        require(GeneralOptionsLayout.encodingTitles.count == 9 && GeneralOptionsLayout.wheelTitles.count == 4
                    && GeneralOptionsLayout.pageTitles.count == 7,
                "OpGeneral combo item counts")

        require(PlayerOptionsLayout.clientSize == CGSize(width: 382, height: 351), "OpPlayer client size")
        require(PlayerOptionsLayout.playerList == CGRect(x: 12, y: 27, width: 225, height: 55), "OpPlayer list")
        require(PlayerOptionsLayout.restoreDefault == CGRect(x: 240, y: 316, width: 130, height: 23), "OpPlayer restore")
    }

    private static func testMappings() {
        require(GeneralOptionsLayout.wheelIndex(for: 96) == 1 && GeneralOptionsLayout.wheelValue(at: 1) == 96,
                "default wheel is 1/2 = 96")
        require(GeneralOptionsLayout.pageIndex(for: 384) == 4 && GeneralOptionsLayout.pageValue(at: 4) == 384,
                "default PageUp/Down is 2 measures = 384")
        require(GeneralOptionsLayout.wheelIndex(for: 7) == 1, "unknown wheel falls back to 96")
        require(GeneralOptionsLayout.autoSaveMilliseconds(enabled: true, minutes: 2) == 120_000, "2 minute autosave")
        require(GeneralOptionsLayout.autoSaveMilliseconds(enabled: false, minutes: 2) == 0, "unchecked autosave is 0")
        require(GeneralOptionsLayout.autoSaveDisplay(milliseconds: 120_000) == (true, 2.0), "2 minutes stays checked")
        require(GeneralOptionsLayout.autoSaveDisplay(milliseconds: 0) == (false, 2.0), "0 ms unchecks and keeps 2")
        require(GeneralOptionsLayout.autoSaveDisplay(milliseconds: 3_600_000) == (true, 60.0), "60 minutes is still valid")
        require(GeneralOptionsLayout.autoSaveDisplay(milliseconds: 3_660_000) == (false, 2.0), "over 60 minutes unchecks")
        require(EditorSettings.legacyDefault.wheelStep == 96 && EditorSettings.legacyDefault.pageStep == 384,
                "MainWindow startup defaults")
        require(EditorSettings.legacyDefault.autoSaveMilliseconds == 120_000
                    && EditorSettings.legacyDefault.beepWhileSaved
                    && EditorSettings.legacyDefault.stopPreviewOnClick,
                "MainWindow checkbox defaults")
        require(EditorSettings.legacyDefault.players == PlayerArguments.legacyDefaults
                    && EditorSettings.legacyDefault.currentPlayer == 0,
                "two default players")
        require(PlayerArguments.legacyDefaults[0].path == "<apppath>\\uBMplay.exe", "uBMplay default path")
    }

    private static func testPlayerEdits() {
        require(PlayerOptionsLayout.fileName(from: "<apppath>\\uBMplay.exe") == "uBMplay.exe", "backslash file name")
        require(PlayerOptionsLayout.fileName(from: "/Applications/o2play") == "o2play", "slash file name")
        require(PlayerOptionsLayout.fileName(from: "bare") == "bare", "no separator")
        require(!PlayerOptionsLayout.hasInvalidPathCharacters("-P -N0 \"<filename>\""), "tokens and quotes are allowed")
        require(PlayerOptionsLayout.hasInvalidPathCharacters("a<b"), "stray < is invalid")
        require(PlayerOptionsLayout.hasInvalidPathCharacters("a|b"), "pipe is invalid")

        let defaults = PlayerArguments.legacyDefaults
        let added = PlayerOptionsLayout.insertingCopy(players: defaults, currentIndex: 0)
        require(added?.players.count == 3 && added?.currentIndex == 1, "Add inserts after the current row")
        require(added?.players[0].path == added?.players[1].path, "Add copies the current player")
        require(added?.players[2].path == defaults[1].path, "Add keeps the later rows")
        require(PlayerOptionsLayout.insertingCopy(players: defaults, currentIndex: 9) == nil, "Add rejects a bad index")

        let removed = PlayerOptionsLayout.removing(players: defaults, currentIndex: 0)
        require(removed?.players.count == 1 && removed?.players[0].path == defaults[1].path, "Remove drops the current row")
        require(PlayerOptionsLayout.removing(players: [defaults[0]], currentIndex: 0) == nil, "the last player stays")
    }

    private static func testSettingsPersistence() {
        let suite = "org.ibmsc.option-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let empty = EditorSettings.load(from: defaults)
        require(empty == .legacyDefault, "missing keys load MainWindow defaults")

        var edited = EditorSettings.legacyDefault
        edited.wheelStep = 192
        edited.pageStep = 768
        edited.middleButtonMoveMethod = 1
        edited.autoSaveMilliseconds = 0
        edited.beepWhileSaved = false
        edited.bpm1296 = true
        edited.gridPartition = 384
        edited.textEncodingIndex = 6
        edited.currentPlayer = 1
        edited.players[1].path = "/tmp/player"
        let store = EditorSettingsStore(defaults: defaults)
        store.replace(edited)
        require(store.settings.wheelStep == 192 && store.settings.textEncodingIndex == 6, "store keeps OK values")

        let restored = EditorSettings.load(from: defaults)
        require(restored == store.settings, "settings round-trip through UserDefaults")

        var broken = EditorSettings.legacyDefault
        broken.wheelStep = 7
        broken.players = []
        broken.currentPlayer = 99
        broken.gridPartition = 2
        let normalized = broken.normalized()
        require(normalized.wheelStep == 96 && normalized.players.count == 2 && normalized.currentPlayer == 0,
                "invalid wheel and empty players snap back")
        require(normalized.gridPartition == 8, "grid partition minimum is 8")
        require(EditorSettings.legacyDefault.bmsGridLimit == 1.0, "default 192 partition is BMSGridLimit 1")
        var coarse = EditorSettings.legacyDefault
        coarse.gridPartition = 8
        require(coarse.bmsGridLimit == 24.0, "partition 8 is BMSGridLimit 24")
    }

    private static func testExternalPlayer() {
        let first = PlayerArguments.legacyDefaults[0]
        require(first.path == "<apppath>\\uBMplay.exe", "default first path is uBMplay")
        require(first.playFromBeginning == "-P -N0 \"<filename>\"", "default aBegin")
        require(first.playFromMeasure == "-P -N<measure> \"<filename>\"", "default aHere")
        require(first.stop == "-S", "default aStop")

        require(
            LegacyExternalPlayer.tempBMSPath(fileName: "/song/a.bms", initPath: "/ignored", appPath: "/app")
                == "/song/___TempBMS.bms",
            "named chart temp path"
        )
        require(
            LegacyExternalPlayer.tempBMSPath(fileName: nil, initPath: "/charts", appPath: "/app")
                == "/charts/___TempBMS.bms",
            "initPath temp path"
        )
        require(
            LegacyExternalPlayer.tempBMSPath(fileName: nil, initPath: nil, appPath: "/app")
                == "/app/___TempBMS.bms",
            "unnamed temp path uses appPath"
        )
        require(
            LegacyExternalPlayer.tempBMSPath(fileName: "", initPath: nil, appPath: "/app")
                == "/app/___TempBMS.bms",
            "empty fileName is not a valid path"
        )
        require(
            LegacyExternalPlayer.programPath("<apppath>\\uBMplay.exe", appPath: "/app") == "/app/uBMplay.exe",
            "programPath turns backslashes into slashes"
        )
        require(
            LegacyExternalPlayer.substitute(
                "-P -N<measure> \"<filename>\"",
                appPath: "/app",
                measure: 2,
                fileName: "/song/___TempBMS.bms"
            ) == "-P -N2 \"/song/___TempBMS.bms\"",
            "aHere substitution"
        )
        require(
            LegacyExternalPlayer.substitute(
                "-P -N0 \"<filename>\"",
                appPath: "/app",
                measure: 2,
                fileName: "/song/___TempBMS.bms"
            ) == "-P -N0 \"/song/___TempBMS.bms\"",
            "aBegin substitution"
        )
        require(
            LegacyExternalPlayer.substitute("-S", appPath: "/app", measure: 2, fileName: "/song/___TempBMS.bms")
                == "-S",
            "aStop stays -S"
        )
        require(LegacyExternalPlayer.measureFromScroll(0) == 0, "scroll 0 is measure 0")
        require(LegacyExternalPlayer.measureFromScroll(-192) == 1, "abs(-192) is measure 1")
        require(LegacyExternalPlayer.writesTempFile(.begin), "begin writes temp")
        require(LegacyExternalPlayer.writesTempFile(.here), "here writes temp")
        require(!LegacyExternalPlayer.writesTempFile(.stop), "stop does not write temp")
        require(LegacyExternalPlayer.missingTitle == "Player not found", "missing title")
        require(
            LegacyExternalPlayer.missingMessage("/opt/uBMplay.exe")
                == "Cannot find file /opt/uBMplay.exe.\r\nPlease respecify path.",
            "missing message is the three original sentences"
        )
        let storedUnderApp = LegacyExternalPlayer.storePickedPath(picked: "/app/bin/player", appPath: "/app")
        require(storedUnderApp.hasPrefix("<apppath>"), "picked under appPath stores <apppath> prefix")
        require(
            LegacyExternalPlayer.storePickedPath(picked: "/opt/player", appPath: "/app") == "/opt/player",
            "picked outside appPath stays absolute"
        )
    }

    private static func testColorCaption() {
        let black = ThemeColor(argb: 0xFF00_0000)
        require(OptionDialogColor.hexARGB(black) == "FF000000", "ToArgb hex")
        require(OptionDialogColor.contrastingText(black).argb == 0xFFFF_FFFF, "dark fill uses a light caption")
        let white = ThemeColor(argb: 0xFFFF_FFFF)
        require(OptionDialogColor.contrastingText(white).argb == 0xFF00_0000, "light fill uses a dark caption")
        let lime = ThemeColor(signedARGB: -16_711_936)
        require(OptionDialogColor.hexARGB(lime) == "FF00FF00", "signed ARGB lime")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
