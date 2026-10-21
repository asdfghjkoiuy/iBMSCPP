import Foundation

/// 预览读到的曲信息。缺的字段保持空，不补标题、曲师、曲风、等级、段位或音符数。
struct PreviewBmsMetadata: Equatable {
    var title: String?
    var artist: String?
    var genre: String?
    var playLevel: String?
    var rank: String?
    /// `#PLAYER` 原文。没有这条头就是 `nil`。
    var player: String?
    /// `#VOLWAV` 原文。只保留数字，播放音量还没接。
    var volwav: String?
    /// `#JUDGERANK` 原文。这是 BMSON 判定等级，不写进 `rank`。
    var judgeRank: String?
    /// 调用方从同一份展开字节数出来的音符。没数过就是 `nil`。
    var notes: Int?
}

/// 原版皮肤能不能放下这个 BMSON 模式，以及预览文本里该写的 `#PLAYER`。
/// `playerHeader` 为 `nil` 时不要另造 5/7/10/14 以外的列。
struct PreviewBmsPlayerLayout: Equatable {
    var supportedByUbmSkin: Bool
    var playerHeader: Int?
}

/// `#PATH_WAV` 只影响 WAV。BGA 目录始终是谱面目录。
struct PreviewBmsResources: Equatable {
    /// 最后一条 `#PATH_WAV` 的原文。没有这条头就是 `nil`。
    var pathWav: String?
    /// 相对 WAV 要拼上去的目录。没有 `#PATH_WAV` 时等于谱面目录。
    var wavDirectory: URL?
    /// 谱面所在目录。不因 `#PATH_WAV` 改道。
    var bgaDirectory: URL?
    /// `#WAVxx` 原文文件名。
    var wavNames: [String: String]
    /// 播放器应打开的路径。有目录时是拼好的路径。
    var wavFiles: [String: String]
    /// `#BMPxx` 原文。不拼 `#PATH_WAV`。
    var bmpFiles: [String: String]
}

struct PreviewBmsRandomBranch: Equatable {
    var values: [Int]
    var expanded: Data
}

struct PreviewBmsRandomResolution: Equatable {
    var branch: PreviewBmsRandomBranch
    var reused: Bool
}

/// 同一份原字节只展开一次。`reload()` 之后下一次才重新选支。
struct PreviewBmsRandomCache {
    private var raw: Data?
    private var stored: PreviewBmsRandomBranch?

    var storedValues: [Int] { stored?.values ?? [] }
    var storedRaw: Data? { raw }

    mutating func reload() {
        raw = nil
        stored = nil
    }

    /// `injected` 只在缓存未命中时读取。越界或没给的槽才在 `1...max` 里取一次。
    mutating func resolve(
        raw: Data,
        maxima: [Int],
        injected: [Int]?,
        expand: (Data, [Int]) throws -> Data
    ) rethrows -> PreviewBmsRandomResolution {
        if self.raw == raw, let stored {
            return PreviewBmsRandomResolution(branch: stored, reused: true)
        }
        let values = Self.choose(maxima: maxima, injected: injected)
        let expanded = try expand(raw, values)
        let branch = PreviewBmsRandomBranch(values: values, expanded: expanded)
        self.raw = raw
        self.stored = branch
        return PreviewBmsRandomResolution(branch: branch, reused: false)
    }

    static func choose(maxima: [Int], injected: [Int]?) -> [Int] {
        maxima.enumerated().map { index, maximum in
            let upper = maximum > 0 ? maximum : 1
            if let injected, injected.indices.contains(index) {
                let requested = injected[index]
                if requested >= 1 && requested <= upper {
                    return requested
                }
            }
            return Int.random(in: 1...upper)
        }
    }
}

/// 原生 BMS 预览的纯数据策略。不写文件，不把 BMS 换成 BMSON。
enum PreviewBmsSource {
    /// 有 `#RANDOM` 上限，或文档仍被核心标成条件谱，就要先展开再预览。
    static func shouldExpand(maxima: [Int], hasConditionals: Bool) -> Bool {
        hasConditionals || !maxima.isEmpty
    }

    /// BMSON `modeHint` 到预览 `#PLAYER`。空串是 Beat 7-key，单人 `1`。
    /// `beat-5k-battle` / `beat-7k-battle` 是明确的 battle，写 `2`。
    /// `beat-10k` / `beat-14k` 是双人，写 `3`。
    /// popn、键盘、generic、circular 以及未知 hint 皮肤放不下，`playerHeader` 留空。
    /// BMS 谱自己的 `#PLAYER` 用 `metadata.player`，不要拿这个函数改掉。
    static func playerLayout(modeHint: String) -> PreviewBmsPlayerLayout {
        let header: Int?
        switch modeHint {
        case "", "beat-7k", "beat-5k":
            header = 1
        case "beat-7k-battle", "beat-5k-battle":
            header = 2
        case "beat-14k", "beat-10k":
            header = 3
        default:
            header = nil
        }
        return PreviewBmsPlayerLayout(supportedByUbmSkin: header != nil, playerHeader: header)
    }

    /// `#PLAYER` 原文变成整数。缺、空、不是整数时是 `nil`。
    static func parsedPlayerHeader(_ stored: String?) -> Int? {
        guard let stored else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    /// 窗口并排：`packed = !autoSeparate || playerHeader == 3`。
    static func previewPacked(autoSeparate: Bool, playerHeader: Int) -> Bool {
        !autoSeparate || playerHeader == 3
    }

    /// 只为读曲信息解码。解码失败时各字段保持空。
    static func metadata(from data: Data, noteCount: Int? = nil) -> PreviewBmsMetadata {
        guard let text = decodePreviewText(data) else {
            return PreviewBmsMetadata(notes: noteCount)
        }
        var song = PreviewBmsMetadata()
        for line in lines(in: text) {
            guard let command = command(from: line), !command.isChannel else { continue }
            switch command.name {
            case "TITLE":
                song.title = command.value
            case "ARTIST":
                song.artist = command.value
            case "GENRE", "GENLE":
                song.genre = command.value
            case "PLAYLEVEL":
                song.playLevel = command.value
            case "RANK":
                song.rank = command.value
            case "PLAYER":
                song.player = command.value
            case "VOLWAV":
                song.volwav = command.value
            case "JUDGERANK":
                song.judgeRank = command.value
            default:
                break
            }
        }
        song.notes = noteCount
        return song
    }

    static func resources(from data: Data, chartDirectory: URL?) -> PreviewBmsResources {
        var pathWav: String?
        var wavNames: [String: String] = [:]
        var bmpFiles: [String: String] = [:]
        if let text = decodePreviewText(data) {
            for line in lines(in: text) {
                guard let command = command(from: line), !command.isChannel else { continue }
                if command.name == "PATH_WAV" {
                    pathWav = command.value
                    continue
                }
                if command.name.count == 5, command.name.hasPrefix("WAV"), isWavKey(String(command.name.suffix(2))) {
                    let key = String(command.name.suffix(2))
                    if !command.value.isEmpty {
                        wavNames[key] = command.value
                    }
                    continue
                }
                if command.name.count == 5, command.name.hasPrefix("BMP"), isWavKey(String(command.name.suffix(2))) {
                    let key = String(command.name.suffix(2))
                    if !command.value.isEmpty {
                        bmpFiles[key] = command.value
                    }
                }
            }
        }
        let directory = wavDirectory(pathWav: pathWav, chartDirectory: chartDirectory)
        var wavFiles: [String: String] = [:]
        for (key, name) in wavNames {
            wavFiles[key] = openPath(fileName: name, pathWav: pathWav, chartDirectory: chartDirectory)
        }
        return PreviewBmsResources(
            pathWav: pathWav.flatMap { $0.isEmpty ? nil : $0 },
            wavDirectory: directory,
            bgaDirectory: chartDirectory,
            wavNames: wavNames,
            wavFiles: wavFiles,
            bmpFiles: bmpFiles
        )
    }

    /// 播放器仍用谱面目录找 BGA。只有现有拼接得不到 WAV 时，才把 `#WAV` 改成绝对路径。
    /// 返回的是副本。入参字节不动，也不能拿去保存。
    static func previewDocumentData(data: Data, chartDirectory: URL?) -> Data {
        let resolved = resources(from: data, chartDirectory: chartDirectory)
        var replacements: [String: String] = [:]
        for (key, open) in resolved.wavFiles {
            guard let original = resolved.wavNames[key] else { continue }
            if open != stockOpenPath(fileName: original, chartDirectory: chartDirectory) {
                replacements[key] = open
            }
        }
        guard !replacements.isEmpty else { return data }
        return rewriteWavLines(data, replacements: replacements)
    }

    /// 去掉 UTF-8 BOM 后再试 UTF-8、Shift-JIS。失败就返回 `nil`，不造一份有损文本。
    static func decodePreviewText(_ data: Data) -> String? {
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        if let text = String(data: payload, encoding: .shiftJIS) {
            return text
        }
        return nil
    }

    static func openPath(fileName: String, pathWav: String?, chartDirectory: URL?) -> String {
        let file = normalizeSlashes(fileName.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !file.isEmpty else { return file }
        if isAbsolute(file) {
            return absolutePath(file)
        }
        let root = pathWav.map { normalizeSlashes($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let root, !root.isEmpty {
            if isAbsolute(root) {
                return joinAbsolute(root, file)
            }
            if let chartDirectory {
                return appendRelative(appendRelative(chartDirectory, root), file).path
            }
            return joinRelative(root, file)
        }
        return stockOpenPath(fileName: file, chartDirectory: chartDirectory)
    }

    /// 现有播放器的拼接：只认以 `/` 开头的绝对路径，反斜杠不当分隔符。
    static func stockOpenPath(fileName: String, chartDirectory: URL?) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).path
        }
        if let chartDirectory {
            return chartDirectory.appendingPathComponent(trimmed).path
        }
        return URL(fileURLWithPath: trimmed).path
    }

    private static func wavDirectory(pathWav: String?, chartDirectory: URL?) -> URL? {
        guard let pathWav else { return chartDirectory }
        let normalized = normalizeSlashes(pathWav.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else { return chartDirectory }
        if isAbsolute(normalized) {
            guard normalized.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: normalized, isDirectory: true)
        }
        guard let chartDirectory else { return nil }
        return appendRelative(chartDirectory, normalized)
    }

    private static func absolutePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).path
        }
        return path
    }

    private static func joinAbsolute(_ root: String, _ file: String) -> String {
        if root.hasPrefix("/") {
            return appendRelative(URL(fileURLWithPath: root, isDirectory: true), file).path
        }
        return joinRelative(root, file)
    }

    private static func joinRelative(_ root: String, _ file: String) -> String {
        let base = root.split(separator: "/").filter { !$0.isEmpty && $0 != "." }
        let rest = file.split(separator: "/").filter { !$0.isEmpty && $0 != "." }
        return (base + rest).joined(separator: "/")
    }

    private static func appendRelative(_ base: URL, _ relative: String) -> URL {
        var url = base
        let parts = normalizeSlashes(relative).split(separator: "/", omittingEmptySubsequences: true)
        for part in parts {
            if part == "." { continue }
            if part == ".." {
                url.deleteLastPathComponent()
                continue
            }
            url.appendPathComponent(String(part))
        }
        return url
    }

    private static func normalizeSlashes(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "/")
    }

    private static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        guard path.count >= 2, let first = path.first, first.isASCII, first.isLetter else { return false }
        return path[path.index(after: path.startIndex)] == ":"
    }

    private struct LineCommand {
        var name: String
        var value: String
        var isChannel: Bool
    }

    private static func lines(in text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    private static func command(from line: String) -> LineCommand? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "#" else { return nil }
        let body = trimmed.dropFirst()
        var delimiter: String.Index?
        for index in body.indices {
            let character = body[index]
            if character == ":" || character == " " || character == "\t" {
                delimiter = index
                break
            }
        }
        if let delimiter, body[delimiter] == ":" {
            let name = String(body[..<delimiter]).uppercased()
            let value = String(body[body.index(after: delimiter)...]).trimmingCharacters(in: .whitespaces)
            return LineCommand(name: name, value: value, isChannel: true)
        }
        let name: String
        let value: String
        if let delimiter {
            name = String(body[..<delimiter]).uppercased()
            value = String(body[body.index(after: delimiter)...]).trimmingCharacters(in: .whitespaces)
        } else {
            name = String(body).uppercased()
            value = ""
        }
        return LineCommand(name: name, value: value, isChannel: false)
    }

    private static func isWavKey(_ key: String) -> Bool {
        guard key.count == 2 else { return false }
        let chars = Array(key.uppercased())
        guard let high = base36(chars[0]), let low = base36(chars[1]) else { return false }
        let index = high * 36 + low
        return index >= 1 && index <= 1295
    }

    private static func base36(_ character: Character) -> Int? {
        switch character {
        case "0"..."9":
            guard let ascii = character.asciiValue else { return nil }
            return Int(ascii - UInt8(ascii: "0"))
        case "A"..."Z":
            guard let ascii = character.asciiValue else { return nil }
            return Int(ascii - UInt8(ascii: "A")) + 10
        default:
            return nil
        }
    }

    private static func rewriteWavLines(_ data: Data, replacements: [String: String]) -> Data {
        var output = Data()
        var index = data.startIndex
        while index < data.endIndex {
            var end = index
            while end < data.endIndex, data[end] != 0x0A, data[end] != 0x0D {
                end += 1
            }
            var newlineEnd = end
            if newlineEnd < data.endIndex, data[newlineEnd] == 0x0D {
                newlineEnd += 1
                if newlineEnd < data.endIndex, data[newlineEnd] == 0x0A {
                    newlineEnd += 1
                }
            } else if newlineEnd < data.endIndex, data[newlineEnd] == 0x0A {
                newlineEnd += 1
            }
            let line = Data(data[index..<end])
            if let replaced = replacedWavLine(line, replacements: replacements) {
                output.append(replaced)
            } else {
                output.append(line)
            }
            if newlineEnd > end {
                output.append(data[end..<newlineEnd])
            }
            index = newlineEnd
        }
        return output
    }

    private static func replacedWavLine(_ line: Data, replacements: [String: String]) -> Data? {
        var start = line.startIndex
        while start < line.endIndex, line[start] == 0x20 || line[start] == 0x09 {
            start += 1
        }
        let content = Data(line[start...])
        guard content.count >= 6, content[content.startIndex] == 0x23 else { return nil }
        let tagStart = content.index(content.startIndex, offsetBy: 1)
        let keyStart = content.index(tagStart, offsetBy: 3)
        let keyEnd = content.index(keyStart, offsetBy: 2)
        guard let tag = String(data: content[tagStart..<keyStart], encoding: .ascii)?.uppercased(), tag == "WAV" else {
            return nil
        }
        guard let key = String(data: content[keyStart..<keyEnd], encoding: .ascii), isWavKey(key) else {
            return nil
        }
        let upper = key.uppercased()
        guard let path = replacements[upper] else { return nil }
        return Data("#WAV\(upper) \(path)".utf8)
    }
}
