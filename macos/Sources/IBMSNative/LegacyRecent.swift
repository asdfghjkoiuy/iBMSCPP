import Foundation

/// 对照 `EditorRecent.vb` `NewRecent` / `SetRecent` / `OpenRecent`。
enum LegacyRecent {
    static let slotCount = 5
    static let noneWord = "None"
    static let emptyTitle = "<None>"
    static let cannotFind = "Cannot find file {}."
    static let defaultsKey = "IBMSNative.Recent"

    enum Kind: Equatable {
        case bms
        case ibmsc
        case bmson
        case unsupported
    }

    static func emptySlots() -> [String] {
        Array(repeating: "", count: slotCount)
    }

    /// `NewRecent`：已有路径提到最前；否则整表后移，丢掉第 5 个。
    static func insert(_ path: String, into recent: [String]) -> [String] {
        var slots = padded(recent)
        if let index = slots.firstIndex(of: path) {
            if index > 0 {
                for step in stride(from: index, through: 1, by: -1) {
                    slots[step] = slots[step - 1]
                }
            }
            slots[0] = path
            return slots
        }
        slots[4] = slots[3]
        slots[3] = slots[2]
        slots[2] = slots[1]
        slots[1] = slots[0]
        slots[0] = path
        return slots
    }

    /// `SetRecent`：先 `Trim`，空槽是 `"<" & Strings.None & ">"`。
    static func menuTitle(_ path: String, noneWord: String = noneWord) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "<\(noneWord)>" }
        return fileName(trimmed)
    }

    static func isEnabled(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `SetRecent` 的 `ToolTipText`：Trim 之后的路径。
    static func tooltip(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `GetFileName`：取最后一个 `/` 或 `\` 后面的部分。
    static func fileName(_ path: String) -> String {
        let slash = lastIndex(path, "/")
        let backslash = lastIndex(path, "\\")
        let start = max(slash, backslash)
        if start <= 0 { return path }
        return String(path.dropFirst(start))
    }

    static func missingFileMessage(_ path: String) -> String {
        cannotFind.replacingOccurrences(of: "{}", with: path)
    }

    /// `OpenRecent` 的 `UCase(Path.GetExtension)`。`.bmson` 走同一主窗。
    static func kind(path: String) -> Kind {
        let ext = URL(fileURLWithPath: path).pathExtension.uppercased()
        switch ext {
        case "BMS", "BME", "BML", "PMS", "TXT":
            return .bms
        case "IBMSC":
            return .ibmsc
        case "BMSON":
            return .bmson
        default:
            return .unsupported
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.stringArray(forKey: defaultsKey) ?? []
        return padded(stored)
    }

    static func save(_ slots: [String], to defaults: UserDefaults = .standard) {
        defaults.set(padded(slots), forKey: defaultsKey)
    }

    private static func padded(_ recent: [String]) -> [String] {
        var slots = recent
        if slots.count < slotCount {
            slots.append(contentsOf: Array(repeating: "", count: slotCount - slots.count))
        }
        return Array(slots.prefix(slotCount))
    }

    /// `InStrRev`：1 起算，找不到是 0。
    private static func lastIndex(_ path: String, _ mark: Character) -> Int {
        guard let index = path.lastIndex(of: mark) else { return 0 }
        return path.distance(from: path.startIndex, to: index) + 1
    }
}
