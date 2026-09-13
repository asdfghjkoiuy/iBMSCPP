import Foundation

struct WavListEdit: Equatable {
    var names: [String]
    var selected: [Int]
    var labelSwaps: [(String, String)] = []

    static func == (lhs: WavListEdit, rhs: WavListEdit) -> Bool {
        lhs.names == rhs.names
            && lhs.selected == rhs.selected
            && lhs.labelSwaps.elementsEqual(rhs.labelSwaps, by: ==)
    }
}

/// 对照 `MainWindow.vb` `AddToPOWAV` / `BWAVUp` / `BWAVDown` / `BWAVRemove`。
enum LegacyWavList {
    static let slotCount = 1295
    static let audioExtensions = [".wav", ".mp3", ".ogg"]
    static let imageExtensions = [
        ".bmp", ".png", ".jpg", ".jpeg", ".gif", ".mpg", ".mpeg", ".avi",
        ".m1v", ".m2v", ".m4v", ".mp4", ".webm", ".wmv"
    ]
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func emptyNames() -> [String] {
        Array(repeating: "", count: slotCount)
    }

    enum RightClickNoteAction: Equatable {
        case remove
        case selectWav
        case ignore
    }

    /// `C10to36` 把 `< 1` 夹成 `1`，`> 1295` 夹成 `1295`，再 `C36to10 - 1`。
    /// 槽位就是 `clamp(n, 1, 1295) - 1`。
    static func rightClickWavSlot(valueDiv10000 n: Int) -> Int {
        min(slotCount, max(1, n)) - 1
    }

    /// 对照 `DeselectOrRemove`。带 Control 或没点中音：不删、不改 WAV。
    static func rightClickNoteAction(shift: Bool, control: Bool, hitNote: Bool) -> RightClickNoteAction {
        guard hitNote, !control else { return .ignore }
        return shift ? .selectWav : .remove
    }

    /// 对照 `Notes.Value \ 10000`。两位标签用已有 `slotIndex` 再加 1。
    /// 通道 `03`：BMS 两位十六进制（`8C` → 140）；更长的串按十进制（BMSON `140`）。
    static func rightClickValueDiv10000(channel: String, token: String) -> Int {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if channel.uppercased() == "03" {
            if trimmed.count > 2, let decimal = Int(trimmed) {
                return decimal
            }
            if let hex = Int(trimmed, radix: 16) {
                return hex
            }
        }
        return slotIndex(trimmed) + 1
    }

    /// `IncreaseCurrentWav` / `DecreaseCurrentWav`：`SelectedIndex = -1` 先落到 0。
    static func stepIndex(selected: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        if selected < 0 {
            return 0
        }
        return min(count - 1, max(0, selected + delta))
    }

    /// 原版非数值列都用 `LWAV`。这里时值和 BGA 已分列，不推进 WAV。
    static func usesWavLabel(_ channel: String) -> Bool {
        switch channel.uppercased() {
        case "03", "08", "09", "SC", "04", "06", "07":
            return false
        default:
            return true
        }
    }

    /// `RemoveNote`：`Notes(I).Value = LWAV.SelectedIndex * 10000`。写下 `01` 并加一格后，选中是 1。
    static func shouldDecreaseAfterErase(enabled: Bool, selected: Int, token: String) -> Bool {
        guard enabled else { return false }
        return selected == slotIndex(token) + 1
    }

    static func token(at slot: Int) -> String {
        let value = min(slotCount, max(1, slot + 1))
        return String([digits[value / 36], digits[value % 36]])
    }

    static func names(from table: [String: String]) -> [String] {
        var names = emptyNames()
        for (token, name) in table {
            let slot = slotIndex(token)
            if slot >= 0 && slot < slotCount {
                names[slot] = name
            }
        }
        return names
    }

    static func table(from names: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for slot in 0..<min(names.count, slotCount) where !names[slot].isEmpty {
            table[token(at: slot)] = names[slot]
        }
        return table
    }

    /// `GetFileName`：最后一段 `/` 或 `\` 后面的名字。
    static func fileName(fromPath path: String) -> String {
        let slash = path.lastIndex(of: "/")
        let backslash = path.lastIndex(of: "\\")
        guard let cut = laterIndex(slash, backslash) else { return path }
        return String(path[path.index(after: cut)...])
    }

    static func displayLine(token: String, name: String) -> String {
        "\(token): \(name)"
    }

    static func headerKey(for token: String) -> String {
        headerKey(directive: "WAV", token: token)
    }

    static func headerKey(directive: String, token: String) -> String {
        directive.uppercased() + token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// `#WAVxx` 定义。后写覆盖先写。不展开 RANDOM。
    static func parseTable(from text: String) -> [String: String] {
        parseTable(from: text, directive: "WAV")
    }

    /// `#WAVxx` / `#BMPxx`。后写覆盖先写。不展开 RANDOM。
    static func parseTable(from text: String, directive: String) -> [String: String] {
        let tag = "#" + directive.uppercased()
        var table: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count >= tag.count + 2, line.uppercased().hasPrefix(tag) else { continue }
            let body = String(line.dropFirst(tag.count))
            guard body.count >= 2 else { continue }
            let token = String(body.prefix(2)).uppercased()
            let slot = slotIndex(token)
            guard slot >= 0, slot < slotCount else { continue }
            let name = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { table[token] = name }
        }
        return table
    }

    static func moveUp(names: [String], selected: [Int]) -> WavListEdit {
        var names = padded(names)
        var indices = selected.filter { $0 >= 0 && $0 < slotCount }
        var start = 0
        while start < slotCount && indices.contains(start) {
            start += 1
        }
        var swaps: [(String, String)] = []
        guard start < slotCount else {
            return WavListEdit(names: names, selected: indices)
        }
        for slot in start..<slotCount {
            guard let position = indices.firstIndex(of: slot) else { continue }
            names.swapAt(slot, slot - 1)
            swaps.append((token(at: slot - 1), token(at: slot)))
            indices[position] = slot - 1
        }
        return WavListEdit(names: names, selected: indices, labelSwaps: swaps)
    }

    static func moveDown(names: [String], selected: [Int]) -> WavListEdit {
        var names = padded(names)
        var indices = selected.filter { $0 >= 0 && $0 < slotCount }
        var start = slotCount - 1
        while start >= 0 && indices.contains(start) {
            start -= 1
        }
        var swaps: [(String, String)] = []
        guard start >= 0 else {
            return WavListEdit(names: names, selected: indices)
        }
        for slot in stride(from: start, through: 0, by: -1) {
            guard let position = indices.firstIndex(of: slot), slot + 1 < slotCount else { continue }
            names.swapAt(slot, slot + 1)
            swaps.append((token(at: slot + 1), token(at: slot)))
            indices[position] = slot + 1
        }
        return WavListEdit(names: names, selected: indices, labelSwaps: swaps)
    }

    static func assign(paths: [String], selected: [Int], names: [String]) -> WavListEdit {
        var names = padded(names)
        var indices = selected.filter { $0 >= 0 && $0 < slotCount }
        guard !indices.isEmpty, !paths.isEmpty else {
            return WavListEdit(names: names, selected: indices)
        }
        if indices.count < paths.count {
            var current = indices[indices.count - 1] + 1
            while indices.count < paths.count && current < slotCount {
                while current < slotCount && !names[current].isEmpty {
                    current += 1
                }
                if current >= slotCount { break }
                indices.append(current)
                current += 1
            }
        }
        let count = min(indices.count, paths.count)
        for index in 0..<count {
            names[indices[index]] = fileName(fromPath: paths[index])
        }
        return WavListEdit(names: names, selected: Array(indices.prefix(count)))
    }

    /// `Color.FromArgb(&HC0FFFFFF)`：画在编辑区正中的拖入预览。
    static let dragPreviewARGB: UInt32 = 0xC0FF_FFFF

    /// `Join(DDFileName, vbCrLf)`。
    static func dragPreviewText(_ paths: [String]) -> String {
        paths.joined(separator: "\r\n")
    }

    /// `FilterFileBySupported`。目录只看一层，不往下走。DragEnter 用这个，不排序。
    static func filterDropped(
        paths: [String],
        extensions: [String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isDirectory: (String) -> Bool = {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &directory) && directory.boolValue
        },
        filesInDirectory: (String) -> [String] = { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory))?.map { directory + "/" + $0 } ?? []
        }
    ) -> [String] {
        var kept: [String] = []
        for path in paths {
            if fileExists(path), !isDirectory(path), extensions.contains(fileExtension(path)) {
                kept.append(path)
            }
            if isDirectory(path) {
                for file in filesInDirectory(path) where extensions.contains(fileExtension(file)) {
                    kept.append(file)
                }
            }
        }
        return kept
    }

    /// `FilterFileBySupported` 再 `Array.Sort`。目录只看一层，不往下走。
    static func prepareDropped(
        paths: [String],
        extensions: [String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isDirectory: (String) -> Bool = {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &directory) && directory.boolValue
        },
        filesInDirectory: (String) -> [String] = { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory))?.map { directory + "/" + $0 } ?? []
        }
    ) -> [String] {
        filterDropped(
            paths: paths,
            extensions: extensions,
            fileExists: fileExists,
            isDirectory: isDirectory,
            filesInDirectory: filesInDirectory
        ).sorted()
    }

    static func fileExtension(_ path: String) -> String {
        let name = fileName(fromPath: path)
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[dot...])
    }

    static func remove(names: [String], selected: [Int]) -> WavListEdit {
        var names = padded(names)
        let indices = selected.filter { $0 >= 0 && $0 < slotCount }
        for slot in indices {
            names[slot] = ""
        }
        return WavListEdit(names: names, selected: indices)
    }

    private static func padded(_ names: [String]) -> [String] {
        if names.count >= slotCount { return Array(names.prefix(slotCount)) }
        return names + Array(repeating: "", count: slotCount - names.count)
    }

    private static func slotIndex(_ token: String) -> Int {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let padded = String(("00" + trimmed).suffix(2))
        let characters = Array(padded)
        let value = digit(characters[0]) * 36 + digit(characters[1])
        return value - 1
    }

    private static func digit(_ character: Character) -> Int {
        guard let value = character.asciiValue else { return 0 }
        if value >= 48 && value <= 57 { return Int(value - 48) }
        if value >= 65 && value <= 90 { return Int(value - 65 + 10) }
        return 0
    }

    private static func laterIndex(_ lhs: String.Index?, _ rhs: String.Index?) -> String.Index? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left > right ? left : right
        case (let left?, nil):
            return left
        case (nil, let right?):
            return right
        case (nil, nil):
            return nil
        }
    }
}
