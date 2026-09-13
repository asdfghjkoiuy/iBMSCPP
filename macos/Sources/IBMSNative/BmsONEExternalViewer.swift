import Foundation

/// BmsONE `ExternalViewerConfig` / `ExternalViewer` settings keys.
enum BmsONEExternalViewerKey {
    static let group = "ExternalViewer"
    static let count = "ExternalViewer/ViewerCount"
    static let current = "ExternalViewer/CurrentViewer"

    static func viewer(_ index: Int, _ field: String) -> String {
        "ExternalViewer/Viewer\(index)/\(field)"
    }

    static let name = "Name"
    static let path = "Path"
    static let icon = "Icon"
    static let playBegin = "ArgumentPlayBegin"
    static let playHere = "ArgumentPlayHere"
    static let stop = "ArgumentStop"
    static let workingDirectory = "WorkingDirectory"
}

/// One external viewer. Contrasts `ExternalViewerConfig`.
struct BmsONEExternalViewerConfig: Equatable {
    var displayName: String
    var programPath: String
    var iconPath: String
    var argumentFormatPlayBeg: String
    var argumentFormatPlayHere: String
    var argumentFormatStop: String
    var executionDirectory: String

    /// `ExternalViewer::CreateNewConfig`.
    static func createNew() -> BmsONEExternalViewerConfig {
        BmsONEExternalViewerConfig(
            displayName: BmsONEDialogLayout.externalViewerNewName,
            programPath: "",
            iconPath: "",
            argumentFormatPlayBeg: "",
            argumentFormatPlayHere: "",
            argumentFormatStop: "",
            executionDirectory: BmsONEDialogLayout.externalViewerDefaultDirectory
        )
    }
}

/// Saved viewer list. Contrasts `ExternalViewer` settings and `SetConfig`.
struct BmsONEExternalViewerStore: Equatable {
    var viewers: [BmsONEExternalViewerConfig]
    var currentIndex: Int

    static var empty: BmsONEExternalViewerStore {
        BmsONEExternalViewerStore(viewers: [], currentIndex: 0)
    }

    /// `ExternalViewer::IsPlayable`.
    var isPlayable: Bool {
        viewers.indices.contains(currentIndex)
    }

    mutating func setViewers(_ next: [BmsONEExternalViewerConfig], index: Int) {
        viewers = next
        currentIndex = index
        if !viewers.isEmpty && !isPlayable {
            currentIndex = 0
        }
    }

    mutating func setCurrentIndex(_ index: Int) {
        currentIndex = index
        if !viewers.isEmpty && !isPlayable {
            currentIndex = 0
        }
    }

    /// Insert at the current row, or 0 when the list is empty. Contrasts `Add`.
    @discardableResult
    mutating func add(at row: Int? = nil) -> Int {
        let inserted = row ?? (viewers.isEmpty ? 0 : max(currentIndex, 0))
        let index = min(max(inserted, 0), viewers.count)
        viewers.insert(.createNew(), at: index)
        currentIndex = index
        return index
    }

    mutating func remove(at row: Int) {
        guard viewers.indices.contains(row) else { return }
        viewers.remove(at: row)
        if viewers.isEmpty {
            currentIndex = 0
            return
        }
        currentIndex = min(row, viewers.count - 1)
    }

    mutating func moveUp(at row: Int) {
        guard row > 0, viewers.indices.contains(row) else { return }
        viewers.swapAt(row, row - 1)
        currentIndex = row - 1
    }

    mutating func moveDown(at row: Int) {
        guard viewers.indices.contains(row), row + 1 < viewers.count else { return }
        viewers.swapAt(row, row + 1)
        currentIndex = row + 1
    }

    static func load(from defaults: UserDefaults = .standard) -> BmsONEExternalViewerStore {
        let count = defaults.object(forKey: BmsONEExternalViewerKey.count) as? Int ?? 0
        var viewers: [BmsONEExternalViewerConfig] = []
        viewers.reserveCapacity(max(count, 0))
        if count > 0 {
            for index in 0..<count {
                viewers.append(
                    BmsONEExternalViewerConfig(
                        displayName: string(defaults, index, BmsONEExternalViewerKey.name),
                        programPath: string(defaults, index, BmsONEExternalViewerKey.path),
                        iconPath: string(defaults, index, BmsONEExternalViewerKey.icon),
                        argumentFormatPlayBeg: string(defaults, index, BmsONEExternalViewerKey.playBegin),
                        argumentFormatPlayHere: string(defaults, index, BmsONEExternalViewerKey.playHere),
                        argumentFormatStop: string(defaults, index, BmsONEExternalViewerKey.stop),
                        executionDirectory: string(defaults, index, BmsONEExternalViewerKey.workingDirectory)
                    )
                )
            }
        }
        var store = BmsONEExternalViewerStore(
            viewers: viewers,
            currentIndex: defaults.object(forKey: BmsONEExternalViewerKey.current) as? Int ?? 0
        )
        if !store.viewers.isEmpty && !store.isPlayable {
            store.currentIndex = 0
        }
        return store
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(viewers.count, forKey: BmsONEExternalViewerKey.count)
        defaults.set(currentIndex, forKey: BmsONEExternalViewerKey.current)
        for (index, viewer) in viewers.enumerated() {
            defaults.set(viewer.displayName, forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.name))
            defaults.set(viewer.programPath, forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.path))
            defaults.set(viewer.iconPath, forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.icon))
            defaults.set(
                viewer.argumentFormatPlayBeg,
                forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.playBegin)
            )
            defaults.set(
                viewer.argumentFormatPlayHere,
                forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.playHere)
            )
            defaults.set(viewer.argumentFormatStop, forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.stop))
            defaults.set(
                viewer.executionDirectory,
                forKey: BmsONEExternalViewerKey.viewer(index, BmsONEExternalViewerKey.workingDirectory)
            )
        }
    }

    private static func string(_ defaults: UserDefaults, _ index: Int, _ field: String) -> String {
        defaults.string(forKey: BmsONEExternalViewerKey.viewer(index, field)) ?? ""
    }
}

/// Argument substitution and temp names. Contrasts `ExternalViewer`.
enum BmsONEExternalViewer {
    /// `ExternalViewer::EvalArgument`. Unknown names become empty. `\$` is not special.
    static func evaluateArgument(_ format: String, environment: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\$\(([_a-zA-Z][_a-zA-Z0-9]*)\)"#) else {
            return format
        }
        let nsFormat = format as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: format, range: NSRange(location: 0, length: nsFormat.length)) {
            let range = match.range
            if range.location > cursor {
                result += nsFormat.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            let name = nsFormat.substring(with: match.range(at: 1))
            result += environment[name] ?? ""
            cursor = range.location + range.length
        }
        if cursor < nsFormat.length {
            result += nsFormat.substring(from: cursor)
        }
        return result
    }

    /// `ExternalViewer::GetBarNumber`.
    static func barNumber(pulse: Int, bars: [Int64]) -> Int {
        var bar = -1
        for location in bars.sorted() where location <= Int64(pulse) {
            bar += 1
        }
        return bar
    }

    /// `QString::number(double)` default `'g'` precision 6.
    static func qtNumber(_ value: Double) -> String {
        String(format: "%.6g", value)
    }

    /// `ExternalViewer::Environment`. `pulse == nil` is Play from Beginning / Stop.
    static func environment(
        directory: String,
        filename: String,
        programPath: String,
        pulse: Int? = nil,
        bars: [Int64] = [],
        initBpm: Double = BmsONEInfoDefaults.initialBpm,
        resolution: Int = BmsONEInfoDefaults.resolution,
        bpmNotes: [(y: Int64, v: Double)] = []
    ) -> [String: String] {
        var env = [
            "directory": directory,
            "filename": filename,
            "exedir": exeDirectory(programPath)
        ]
        if let pulse {
            env["ticks"] = "\(pulse)"
            env["time"] = qtNumber(
                BmsONEStatus.absoluteSeconds(
                    pulse: pulse,
                    initBpm: initBpm,
                    resolution: resolution,
                    bpmNotes: bpmNotes
                )
            )
            env["measure"] = "\(barNumber(pulse: pulse, bars: bars))"
        }
        return env
    }

    /// First unused `__bmsone_temp_%1.bmson` in `0...98`.
    static func tempFileName(directory: String, exists: (String) -> Bool) -> String? {
        for index in 0..<99 {
            let name = "__bmsone_temp_\(index).bmson"
            let path = (directory as NSString).appendingPathComponent(name)
            if !exists(path) {
                return path
            }
        }
        return nil
    }

    /// macOS `QProcess::start` command. Does not launch a process.
    static func macosCommand(program: String, argument: String) -> String {
        "\"\(program)\" \(argument)"
    }

    static func exeDirectory(_ programPath: String) -> String {
        if programPath.isEmpty {
            return FileManager.default.currentDirectoryPath
        }
        return URL(fileURLWithPath: programPath).deletingLastPathComponent().path
    }

    /// `GetProjectDirectory() == QDir::root()` 时 Play 直接返回。
    static func projectDirectory(filePath: String?) -> String? {
        guard let filePath, !filePath.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        if directory.isEmpty || directory == "/" {
            return nil
        }
        return directory
    }

    /// `SequenceView::GetCurrentLocation`：视口底边，再 `SnapToLowerFineGrid`。
    static func currentLocation(
        time: Double,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> Int {
        let clamped = time.isFinite ? max(0, time) : 0
        return BmsONESnap.snapToLowerFineGrid(
            time: clamped,
            bars: bars,
            resolution: resolution,
            fineGrid: fineGrid
        )
    }

    /// 源码：`tBegin = viewLength - (scrollY + height) / zoomY`。
    static func currentLocation(
        viewLength: Double,
        scrollY: Double,
        viewportHeight: Double,
        zoomY: Double,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> Int {
        guard zoomY != 0 else {
            return currentLocation(time: 0, bars: bars, resolution: resolution, fineGrid: fineGrid)
        }
        var tBegin = viewLength - (scrollY + viewportHeight) / zoomY
        if tBegin < 0 {
            tBegin = 0
        }
        return currentLocation(time: tBegin, bars: bars, resolution: resolution, fineGrid: fineGrid)
    }

    static func cleanTempFile(_ path: String?, fileManager: FileManager = .default) -> Bool {
        guard let path, fileManager.fileExists(atPath: path) else { return true }
        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// `PrepareTempFile`：写出当前 JSON。失败返回 `nil`。
    static func writeTempFile(
        directory: String,
        json: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard let path = tempFileName(directory: directory, exists: { fileManager.fileExists(atPath: $0) }) else {
            return nil
        }
        do {
            try json.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            return path
        } catch {
            return nil
        }
    }

    /// Spaces split tokens. Double quotes keep a token together.
    static func splitCommandArguments(_ argument: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in argument {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == " " && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Contrasts `ExternalViewer::PlayBeg` / `Play` / `Stop` before `QProcess`.
    static func plan(
        kind: BmsONEExternalViewerKind,
        store: BmsONEExternalViewerStore,
        filePath: String?,
        json: String,
        currentTempPath: String?,
        pulse: Int? = nil,
        bars: [Int64] = [],
        initBpm: Double = BmsONEInfoDefaults.initialBpm,
        resolution: Int = BmsONEInfoDefaults.resolution,
        bpmNotes: [(y: Int64, v: Double)] = [],
        fileManager: FileManager = .default
    ) -> (BmsONEExternalViewerAction, String?) {
        guard store.isPlayable, store.viewers.indices.contains(store.currentIndex) else {
            return (.ignored, currentTempPath)
        }
        guard let directory = projectDirectory(filePath: filePath) else {
            return (.ignored, currentTempPath)
        }
        let viewer = store.viewers[store.currentIndex]
        var tempPath = currentTempPath
        switch kind {
        case .beginning, .here:
            if !cleanTempFile(tempPath, fileManager: fileManager) {
                return (.failed, tempPath)
            }
            tempPath = nil
            guard let written = writeTempFile(directory: directory, json: json, fileManager: fileManager) else {
                return (.failed, nil)
            }
            tempPath = written
        case .stop:
            guard currentTempPath != nil else {
                return (.ignored, currentTempPath)
            }
        }
        guard let tempFilePath = tempPath else {
            return (.ignored, nil)
        }
        let format: String
        let playPulse: Int?
        switch kind {
        case .beginning:
            format = viewer.argumentFormatPlayBeg
            playPulse = nil
        case .here:
            format = viewer.argumentFormatPlayHere
            playPulse = pulse
        case .stop:
            format = viewer.argumentFormatStop
            playPulse = nil
        }
        let env = environment(
            directory: directory,
            filename: tempFilePath,
            programPath: viewer.programPath,
            pulse: playPulse,
            bars: bars,
            initBpm: initBpm,
            resolution: resolution,
            bpmNotes: bpmNotes
        )
        let argument = evaluateArgument(format, environment: env)
        let workingDirectory = evaluateArgument(viewer.executionDirectory, environment: env)
        let launch = BmsONEExternalViewerLaunch(
            program: viewer.programPath,
            argument: argument,
            workingDirectory: workingDirectory,
            command: macosCommand(program: viewer.programPath, argument: argument),
            tempFilePath: tempFilePath
        )
        return (.run(launch), tempFilePath)
    }

    /// Starts the viewer. Tests may pass `/usr/bin/true`.
    /// The process is kept so the player is not killed when this function returns.
    static func start(_ launch: BmsONEExternalViewerLaunch) -> Bool {
        guard !launch.program.isEmpty else { return false }
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: launch.workingDirectory, isDirectory: true)
        process.executableURL = URL(fileURLWithPath: launch.program)
        process.arguments = splitCommandArguments(launch.argument)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            BmsONEExternalViewerProcessBox.shared.keep(process)
            return true
        } catch {
            return false
        }
    }
}

/// 已启动的外置播放器进程要留着，函数返回后不能立刻释放。
final class BmsONEExternalViewerProcessBox: @unchecked Sendable {
    static let shared = BmsONEExternalViewerProcessBox()
    private var running: [Process] = []
    private let lock = NSLock()

    func keep(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        running.removeAll { !$0.isRunning }
        running.append(process)
    }
}

enum BmsONEExternalViewerKind: Equatable {
    case beginning
    case here
    case stop
}

struct BmsONEExternalViewerLaunch: Equatable {
    var program: String
    var argument: String
    var workingDirectory: String
    var command: String
    var tempFilePath: String
}

enum BmsONEExternalViewerAction: Equatable {
    case ignored
    case run(BmsONEExternalViewerLaunch)
    case failed
}
