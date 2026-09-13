import CoreGraphics
import Foundation

enum LoadProgressLayout {
    static let clientSize = CGSize(width: 611, height: 120)
    static let label = CGRect(x: 12, y: 9, width: 587, height: 48)
    static let progress = CGRect(x: 15, y: 60, width: 584, height: 15)
    static let cancel = CGRect(x: 245, y: 81, width: 120, height: 27)
    static let title = "Loading Files"
    static let cancelTitle = "Cancel"
    static let controlBox = false
    static let showInTaskbar = false
    static let topMost = true
}

enum LoadFileKind: Equatable {
    case bms
    case sm
    case ibmsc
    case bmson
}

enum LoadFileDestination: Equatable {
    case currentWindow
    case newProcess
}

enum LegacyLoadProgress {
    static let supportedExtensions = [".bms", ".bme", ".bml", ".pms", ".txt", ".sm", ".ibmsc", ".bmson"]

    static func statusText(index: Int, count: Int, path: String) -> String {
        "Currently loading ( \(index + 1) / \(count) ): \(path)"
    }

    static func progressMaximum(fileCount: Int) -> Int {
        fileCount
    }

    static func progressValue(beforeLoading index: Int) -> Int {
        index
    }

    static func destination(index: Int, isSaved: Bool) -> LoadFileDestination {
        index == 0 && isSaved ? .currentWindow : .newProcess
    }

    static func kind(path: String) -> LoadFileKind? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "bms", "bme", "bml", "pms", "txt":
            return .bms
        case "sm":
            return .sm
        case "ibmsc":
            return .ibmsc
        case "bmson":
            return .bmson
        default:
            return nil
        }
    }

    /// `Path.GetExtension` plus `Array.IndexOf`: the extension is case-sensitive.
    static func extensionMatches(_ path: String) -> Bool {
        supportedExtensions.contains(fileExtension(path))
    }

    static func fileExtension(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[dot...])
    }

    /// `FilterFileBySupported`: matching files, then non-recursive directory children.
    static func filter(
        _ paths: [String],
        fileExists: (String) -> Bool,
        isDirectory: (String) -> Bool,
        directoryFiles: (String) -> [String]
    ) -> [String] {
        var result: [String] = []
        for path in paths {
            if fileExists(path), extensionMatches(path) {
                result.append(path)
            }
            if isDirectory(path) {
                for child in directoryFiles(path) where extensionMatches(child) {
                    result.append(child)
                }
            }
        }
        return result
    }

    static func filterExisting(_ urls: [URL], fileManager: FileManager = .default) -> [URL] {
        let paths = filter(
            urls.map(\.path),
            fileExists: { fileManager.fileExists(atPath: $0) && !directoryExists($0, fileManager) },
            isDirectory: { directoryExists($0, fileManager) },
            directoryFiles: { directory in
                let root = URL(fileURLWithPath: directory)
                return (try? fileManager.contentsOfDirectory(atPath: directory))?.compactMap { name in
                    let child = root.appendingPathComponent(name)
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                          !isDirectory.boolValue else { return nil }
                    return child.path
                } ?? []
            }
        )
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// `GetCommandLineArgs.Length = 2` only. Flags such as `-NSDocumentRevisionsDebugMode` are skipped.
    static func commandLineCandidate(_ arguments: [String]) -> String? {
        var leftover: [String] = []
        var skipNext = false
        for (index, argument) in arguments.enumerated() {
            if index == 0 { continue }
            if skipNext {
                skipNext = false
                continue
            }
            if argument == "-NSDocumentRevisionsDebugMode" {
                skipNext = true
                continue
            }
            if argument.hasPrefix("-") { continue }
            leftover.append(argument)
        }
        return leftover.count == 1 ? leftover[0] : nil
    }

    static func isAutosaveCommandLinePath(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return pathExtensionLowercased(path) == ".ibmsc" && name.lowercased().hasPrefix("autosave_")
    }

    private static func pathExtensionLowercased(_ path: String) -> String {
        fileExtension(path).lowercased()
    }

    private static func directoryExists(_ path: String, _ fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

enum LegacyAutoSave {
    static let filePrefix = "AutoSave_"
    static let fileExtension = "IBMSC"

    static func fileName(at date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let millisecond = (parts.nanosecond ?? 0) / 1_000_000
        return "\(filePrefix)\(parts.year ?? 0)_\(parts.month ?? 0)_\(parts.day ?? 0)_\(parts.hour ?? 0)_\(parts.minute ?? 0)_\(parts.second ?? 0)_\(millisecond).\(fileExtension)"
    }

    static func directory(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("IBMSNative", isDirectory: true)
    }

    static func restoreMessage(count: Int) -> String {
        "\(count) autosaved file(s) have been found. Do you want to recover these files?"
    }

    static func listSnapshots(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            let lower = name.lowercased()
            guard lower.hasPrefix("autosave_"), lower.hasSuffix(".ibmsc") else { return nil }
            return directory.appendingPathComponent(name)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

enum LegacyMiddleButton {
    static let timerIntervalMilliseconds = 15
    static let autoScrollDivisor: CGFloat = 5

    static func shouldReleaseAutoScroll(deltaX: CGFloat, deltaY: CGFloat, threshold: Int) -> Bool {
        deltaX * deltaX + deltaY * deltaY >= CGFloat(threshold)
    }

    /// Windows / flipped-view coordinates: Y grows downward. Each tick adds this delta to the current offset.
    static func autoScrollDelta(
        current: CGPoint,
        origin: CGPoint,
        gxHeight: CGFloat,
        gxWidth: CGFloat
    ) -> CGPoint {
        let height = max(gxHeight, 0.000_1)
        let width = max(gxWidth, 0.000_1)
        return CGPoint(
            x: (current.x - origin.x) / autoScrollDivisor / width,
            y: (current.y - origin.y) / autoScrollDivisor / height
        )
    }

    /// Cocoa screen coordinates: Y grows upward. Convert to the Windows delta used by `TimerMiddle`.
    static func autoScrollDeltaFromCocoaScreen(
        current: CGPoint,
        origin: CGPoint,
        gxHeight: CGFloat,
        gxWidth: CGFloat
    ) -> CGPoint {
        autoScrollDelta(
            current: CGPoint(x: current.x, y: -current.y),
            origin: CGPoint(x: origin.x, y: -origin.y),
            gxHeight: gxHeight,
            gxWidth: gxWidth
        )
    }

    static func dragOffset(
        current: CGPoint,
        origin: CGPoint,
        startOffset: CGPoint,
        gxHeight: CGFloat,
        gxWidth: CGFloat
    ) -> CGPoint {
        let height = max(gxHeight, 0.000_1)
        let width = max(gxWidth, 0.000_1)
        return CGPoint(
            x: startOffset.x + (origin.x - current.x) / width,
            y: startOffset.y + (origin.y - current.y) / height
        )
    }
}
