import Foundation

@main
struct LegacyLoadProgressTests {
    static func main() {
        testLayout()
        testStatusAndProgress()
        testFilter()
        testCommandLine()
        testAutoSave()
        testMiddleButton()
        print("LegacyLoadProgressTests passed")
    }

    private static func testLayout() {
        require(LoadProgressLayout.clientSize == CGSize(width: 611, height: 120), "client size")
        require(LoadProgressLayout.label == CGRect(x: 12, y: 9, width: 587, height: 48), "Label1")
        require(LoadProgressLayout.progress == CGRect(x: 15, y: 60, width: 584, height: 15), "prog")
        require(LoadProgressLayout.cancel == CGRect(x: 245, y: 81, width: 120, height: 27), "Cancel")
        require(LoadProgressLayout.title == "Loading Files", "title")
        require(LoadProgressLayout.cancelTitle == "Cancel", "Cancel text")
        require(!LoadProgressLayout.controlBox && !LoadProgressLayout.showInTaskbar && LoadProgressLayout.topMost, "window chrome")
    }

    private static func testStatusAndProgress() {
        require(
            LegacyLoadProgress.statusText(index: 0, count: 2, path: "/tmp/a.bms")
                == "Currently loading ( 1 / 2 ): /tmp/a.bms",
            "status text"
        )
        require(LegacyLoadProgress.progressMaximum(fileCount: 3) == 3, "Maximum = UBound + 1")
        require(LegacyLoadProgress.progressValue(beforeLoading: 0) == 0, "first file is still 0")
        require(LegacyLoadProgress.destination(index: 0, isSaved: true) == .currentWindow, "first saved file stays here")
        require(LegacyLoadProgress.destination(index: 0, isSaved: false) == .newProcess, "unsaved first file starts a process")
        require(LegacyLoadProgress.destination(index: 1, isSaved: true) == .newProcess, "later files start a process")
        require(LegacyLoadProgress.kind(path: "song.BME") == .bms, "ReadFile lowercases the extension")
        require(LegacyLoadProgress.kind(path: "chart.sm") == .sm, "SM")
        require(LegacyLoadProgress.kind(path: "AutoSave_1.IBMSC") == .ibmsc, "IBMSC")
        require(LegacyLoadProgress.kind(path: "notes.wav") == nil, "unsupported")
        require(LegacyLoadProgress.extensionMatches("song.bms"), "lowercase match")
        require(!LegacyLoadProgress.extensionMatches("song.BMS"), "IndexOf is case-sensitive")
        require(LegacyLoadProgress.isAutosaveCommandLinePath("/tmp/AutoSave_1.ibmsc"), "autosave argv skip restore")
        require(!LegacyLoadProgress.isAutosaveCommandLinePath("/tmp/song.ibmsc"), "ordinary IBMSC still offers restore")
    }

    private static func testFilter() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ibms-load-filter-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let song = root.appendingPathComponent("song.bms")
        let upper = root.appendingPathComponent("SONG.BMS")
        let sm = root.appendingPathComponent("dance.sm")
        let wav = root.appendingPathComponent("kick.wav")
        let nestedSong = nested.appendingPathComponent("hidden.bms")
        try! FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try! Data().write(to: song)
        try! Data().write(to: upper)
        try! Data().write(to: sm)
        try! Data().write(to: wav)
        try! Data().write(to: nestedSong)
        defer { try? FileManager.default.removeItem(at: root) }

        let files = LegacyLoadProgress.filterExisting([song, wav, upper, root])
        require(files.contains(song), "existing .bms is kept")
        require(files.contains(sm), "directory children include .sm")
        require(!files.contains(wav), "wav is rejected")
        require(!files.contains(upper), ".BMS does not match .bms")
        require(!files.contains(nestedSong), "directories are not recursive")
        require(files.first == song, "matching files are collected before directory children")
    }

    private static func testCommandLine() {
        require(
            LegacyLoadProgress.commandLineCandidate(["/app/IBMSNative", "/tmp/a.bms"]) == "/tmp/a.bms",
            "exactly one file"
        )
        require(
            LegacyLoadProgress.commandLineCandidate(["/app/IBMSNative", "/tmp/a.bms", "/tmp/b.bms"]) == nil,
            "two files are ignored"
        )
        require(
            LegacyLoadProgress.commandLineCandidate([
                "/app/IBMSNative",
                "-NSDocumentRevisionsDebugMode",
                "YES",
                "/tmp/a.bms"
            ]) == "/tmp/a.bms",
            "debug flag is skipped"
        )
        require(LegacyLoadProgress.commandLineCandidate(["/app/IBMSNative"]) == nil, "no file")
    }

    private static func testAutoSave() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 5
        parts.day = 8
        parts.hour = 4
        parts.minute = 42
        parts.second = 3
        parts.nanosecond = 0
        let date = calendar.date(from: parts)!
        require(
            LegacyAutoSave.fileName(at: date, calendar: calendar) == "AutoSave_2026_5_8_4_42_3_0.IBMSC",
            "VB Date parts are not zero-padded"
        )
        require((45_000_000) / 1_000_000 == 45, "millisecond is nanosecond / 1_000_000")
        require(
            LegacyAutoSave.restoreMessage(count: 2)
                == "2 autosaved file(s) have been found. Do you want to recover these files?",
            "restore prompt"
        )
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ibms-autosave-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try! Data().write(to: folder.appendingPathComponent("AutoSave_1.IBMSC"))
        try! Data().write(to: folder.appendingPathComponent("autosave_2.ibmsc"))
        try! Data().write(to: folder.appendingPathComponent("song.ibmsc"))
        let found = LegacyAutoSave.listSnapshots(in: folder)
        require(found.count == 2, "AutoSave_*.IBMSC is case-insensitive on macOS")
        require(found.allSatisfy { $0.lastPathComponent.lowercased().hasPrefix("autosave_") }, "prefix")
    }

    private static func testMiddleButton() {
        require(LegacyMiddleButton.timerIntervalMilliseconds == 15, "TimerMiddle interval")
        require(LegacyMiddleButton.shouldReleaseAutoScroll(deltaX: 3, deltaY: 1, threshold: 10), "3*3+1*1 >= 10")
        require(!LegacyMiddleButton.shouldReleaseAutoScroll(deltaX: 2, deltaY: 2, threshold: 10), "click without moving stays")
        let auto = LegacyMiddleButton.autoScrollDelta(
            current: CGPoint(x: 10, y: 20),
            origin: CGPoint(x: 0, y: 0),
            gxHeight: 1,
            gxWidth: 1
        )
        require(abs(auto.x - 2) < 0.000_1 && abs(auto.y - 4) < 0.000_1, "(dx,dy)/5")
        let cocoa = LegacyMiddleButton.autoScrollDeltaFromCocoaScreen(
            current: CGPoint(x: 10, y: 80),
            origin: CGPoint(x: 0, y: 100),
            gxHeight: 1,
            gxWidth: 1
        )
        require(abs(cocoa.x - 2) < 0.000_1 && abs(cocoa.y - 4) < 0.000_1, "Cocoa Y is inverted")
        let dragged = LegacyMiddleButton.dragOffset(
            current: CGPoint(x: 8, y: 18),
            origin: CGPoint(x: 4, y: 10),
            startOffset: CGPoint(x: 40, y: 80),
            gxHeight: 2,
            gxWidth: 2
        )
        require(abs(dragged.x - 38) < 0.000_1 && abs(dragged.y - 76) < 0.000_1, "temp + (start-current)/gx")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
