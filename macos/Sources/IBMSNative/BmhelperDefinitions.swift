import Foundation

/// 对照 `common.h` 的 `ZZNumber`。
/// 两位 36 进制，高位在前，字母大写，范围 00–ZZ（0–1295）。
/// `increment_in_ff` 只在 00–FF 里走，F 是 15，不是 36 进制的 Z。
struct ZZNumber: Equatable {
    private(set) var low: UInt
    private(set) var high: UInt

    init(_ n: Int = 0) {
        let unsigned = UInt(max(n, 0))
        low = unsigned % 36
        high = (unsigned / 36) % 36
    }

    init(low: UInt, high: UInt) {
        self.low = low % 36
        self.high = high % 36
    }

    var integerValue: Int { Int(high * 36 + low) }

    func to_string() -> String {
        String([Self.digit(high), Self.digit(low)])
    }

    /// 对照 `ZZNumber::from_string`：两位 36 进制。
    mutating func from_string(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count >= 2 else { return false }
        let parsedHigh = Self.value(chars[0])
        let parsedLow = Self.value(chars[1])
        guard parsedHigh < 36, parsedLow < 36 else { return false }
        high = parsedHigh
        low = parsedLow
        return true
    }

    /// 对照 `operator++`：低位进到 36 再进高位；ZZ 之后回到 00。
    mutating func increment() {
        low += 1
        if low >= 36 {
            low = 0
            high += 1
            if high >= 36 {
                high = 0
            }
        }
    }

    /// 对照 `in_ff()`：`(low|high)<16`，也就是两位都在 0–15。
    func in_ff() -> Bool {
        (low | high) < 16
    }

    /// 对照 `increment_in_ff()`：低位进到 16 再进高位；FF（15,15）之后回到 00。
    mutating func increment_in_ff() {
        low += 1
        if low >= 16 {
            low = 0
            high += 1
            if high >= 16 {
                high = 0
            }
        }
    }

    /// 对照 `operator--`：低位从 0 借到 35；`00` 之后回到 `ZZ`。
    mutating func decrement() {
        if low == 0 {
            low = 35
            if high == 0 {
                high = 35
            } else {
                high -= 1
            }
        } else {
            low -= 1
        }
    }

    /// 对照 `decrement_in_ff()`：低位从 0 借到 15；`00` 之后回到 `FF`。
    mutating func decrement_in_ff() {
        if low == 0 {
            low = 15
            if high == 0 {
                high = 15
            } else {
                high -= 1
            }
        } else {
            low -= 1
        }
    }

    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static func digit(_ n: UInt) -> Character {
        digits[Int(n)]
    }

    private static func value(_ character: Character) -> UInt {
        if character >= "0" && character <= "9" {
            return UInt(character.asciiValue! - Character("0").asciiValue!)
        }
        if character >= "A" && character <= "Z" {
            return UInt(character.asciiValue! - Character("A").asciiValue!) + 10
        }
        if character >= "a" && character <= "z" {
            return UInt(character.asciiValue! - Character("a").asciiValue!) + 10
        }
        return 36
    }
}

/// 只拼 BMS `#WAV` 定义文本。这一轮不切片真实 WAV，也不做音符聚类。
enum BmhelperDefinitions {
    static func resolvedName(_ name: String) -> String {
        name.isEmpty ? BmhelperDefDialogLayout.defaultName : name
    }

    /// 对照 `divedit.cpp`：`#WAV%s %s_%03d.wav\r\n`，NNN 是 `div+offset`。
    static func formatWavLine(zz: String, name: String, div: Int, offset: Int) -> String {
        let index = String(format: "%03d", div + offset)
        return "#WAV\(zz) \(resolvedName(name))_\(index).wav\(BmhelperDefDialogLayout.wavLineTerminator)"
    }

    /// 从 `start` 连续分配 `count` 个 zz。
    /// `zzEnabled=true` 走 00–ZZ；`false` 走 00–FF。
    /// 对照 `division.cpp`：关掉 ZZ 且起点不在 FF 里时，先 `increment_in_ff` 再开始。
    static func assignDefinitions(start: Int, zzEnabled: Bool, count: Int) -> [String] {
        var zz = ZZNumber(start)
        if !zzEnabled, !zz.in_ff() {
            zz.increment_in_ff()
        }
        var result: [String] = []
        result.reserveCapacity(max(count, 0))
        for _ in 0..<max(count, 0) {
            result.append(zz.to_string())
            if zzEnabled {
                zz.increment()
            } else {
                zz.increment_in_ff()
            }
        }
        return result
    }

    /// 一对一：第 `i` 个音符对应 `div = i`。不是 `division.cpp` 的聚类。
    static func assignOneToOne(
        noteCount: Int,
        start: Int = BmhelperDefDialogLayout.defaultStartDefinition,
        zzEnabled: Bool = true
    ) -> (zzStrings: [String], divs: [Int]) {
        let count = max(noteCount, 0)
        return (
            assignDefinitions(start: start, zzEnabled: zzEnabled, count: count),
            Array(0..<count)
        )
    }

    /// 从 MIDI 音符个数拼定义文本。一对一，不是聚类。
    static func formatDefinitionBlock(
        fromNoteCount count: Int,
        name: String,
        offset: Int = 0,
        start: Int = BmhelperDefDialogLayout.defaultStartDefinition,
        zzEnabled: Bool = true
    ) -> String {
        let assigned = assignOneToOne(noteCount: count, start: start, zzEnabled: zzEnabled)
        return formatDefinitionBlock(
            name: name,
            offset: offset,
            zzStrings: assigned.zzStrings,
            divs: assigned.divs
        )
    }

    static func formatDefinitionBlock(
        name: String,
        offset: Int,
        zzStrings: [String],
        divs: [Int]
    ) -> String {
        let count = min(zzStrings.count, divs.count)
        var block = ""
        for index in 0..<count {
            block += formatWavLine(
                zz: zzStrings[index],
                name: name,
                div: divs[index],
                offset: offset
            )
        }
        return block
    }
}

/// 对照 `division.cpp` 的 `def_transpose_up` / `def_transpose_down` / `def_transpose_to`。
/// 只改定义 zz，不重新聚类。
enum BmhelperTranspose {
    enum Kind {
        case up
        case down
        case to(String)
    }

    /// `<`：ZZ 开则每个 `zz--`；关则每个 `decrement_in_ff()`。
    static func up(zzEnabled: Bool, zzStrings: [String]) -> [String] {
        zzStrings.map { text in
            var zz = ZZNumber()
            guard zz.from_string(text) else { return text }
            if zzEnabled {
                zz.decrement()
            } else {
                zz.decrement_in_ff()
            }
            return zz.to_string()
        }
    }

    /// `>`：ZZ 开则每个 `zz++`；关则每个 `increment_in_ff()`。
    static func down(zzEnabled: Bool, zzStrings: [String]) -> [String] {
        zzStrings.map { text in
            var zz = ZZNumber()
            guard zz.from_string(text) else { return text }
            if zzEnabled {
                zz.increment()
            } else {
                zz.increment_in_ff()
            }
            return zz.to_string()
        }
    }

    /// 定义为空则原样返回。
    /// ZZ 开：相对第一项的差，负则 `+1296`，`>=1296` 则 `-1296`。
    /// ZZ 关：从 nbegin 起逐个 `increment_in_ff` 赋回去。
    static func to(zzEnabled: Bool, zzStrings: [String], nbegin: String) -> [String] {
        guard !zzStrings.isEmpty else { return zzStrings }
        var begin = ZZNumber()
        guard begin.from_string(nbegin) else { return zzStrings }
        if zzEnabled {
            var first = ZZNumber()
            guard first.from_string(zzStrings[0]) else { return zzStrings }
            let diff = begin.integerValue - first.integerValue
            return zzStrings.map { text in
                var zz = ZZNumber()
                guard zz.from_string(text) else { return text }
                var tmp = zz.integerValue + diff
                if tmp < 0 { tmp += 1296 }
                if tmp >= 1296 { tmp -= 1296 }
                return ZZNumber(tmp).to_string()
            }
        }
        var zz = begin
        return zzStrings.map { _ in
            let text = zz.to_string()
            zz.increment_in_ff()
            return text
        }
    }

    /// 对照对话框：正好两位、`from_string` 成功；ZZ 关还要 `in_ff()`。
    static func accept(_ text: String, zzEnabled: Bool) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 2 else { return nil }
        var zz = ZZNumber()
        guard zz.from_string(trimmed) else { return nil }
        if !zzEnabled, !zz.in_ff() { return nil }
        return zz.to_string()
    }

    static func apply(zzEnabled: Bool, zzStrings: [String], kind: Kind) -> [String] {
        switch kind {
        case .up:
            return up(zzEnabled: zzEnabled, zzStrings: zzStrings)
        case .down:
            return down(zzEnabled: zzEnabled, zzStrings: zzStrings)
        case .to(let nbegin):
            return to(zzEnabled: zzEnabled, zzStrings: zzStrings, nbegin: nbegin)
        }
    }
}
