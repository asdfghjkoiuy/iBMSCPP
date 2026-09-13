import Foundation

/// 对照 `serialize.h` 的 RIFF 式树。名字 4 字节小端，第一字节是 A–Z 的是列表。
struct BmhelperTreeNode: Equatable {
    var name: String
    var children: [BmhelperTreeNode]
    var data: Data

    var isList: Bool {
        guard let first = name.utf8.first else { return false }
        return first >= 65 && first <= 90
    }

    static func list(_ name: String, _ children: [BmhelperTreeNode] = []) -> BmhelperTreeNode {
        BmhelperTreeNode(name: name, children: children, data: Data())
    }

    static func leaf(_ name: String, _ data: Data) -> BmhelperTreeNode {
        BmhelperTreeNode(name: name, children: [], data: data)
    }
}

enum BmhelperTreeError: Error, Equatable {
    case truncated
    case badRoot
}

enum BmhelperTree {
    static let projectRoot = "BMHP"
    static let sourceList = "Src "
    static let divisionList = "Div "
    static let midiList = "Midi"
    static let sourceDataList = "Srcd"
    static let quantizeLeaf = "qntz"
    static let noteLeaf = "note"
    static let nameLeaf = "name"
    static let src2defLeaf = "s2df"
    static let definitionLeaf = "dfnt"
    static let zzEnabledLeaf = "zzen"

    static func write(_ root: BmhelperTreeNode) -> Data {
        var data = Data()
        writeNode(root, into: &data)
        return data
    }

    static func read(_ data: Data) throws -> BmhelperTreeNode {
        var offset = 0
        return try readNode(from: data, offset: &offset)
    }

    private static func writeNode(_ node: BmhelperTreeNode, into data: inout Data) {
        appendName(node.name, into: &data)
        if node.isList {
            let sizeOffset = data.count
            appendUInt32(&data, 0)
            let innerStart = data.count
            for child in node.children {
                writeNode(child, into: &data)
            }
            let size = UInt32(data.count - innerStart)
            replaceUInt32(&data, at: sizeOffset, size)
        } else {
            appendUInt32(&data, UInt32(node.data.count))
            data.append(node.data)
        }
    }

    private static func readNode(from data: Data, offset: inout Int) throws -> BmhelperTreeNode {
        let name = try readName(from: data, offset: &offset)
        let size = Int(try readUInt32(from: data, offset: &offset))
        if isListName(name) {
            let end = offset + size
            guard end <= data.count else { throw BmhelperTreeError.truncated }
            var children: [BmhelperTreeNode] = []
            while offset < end {
                children.append(try readNode(from: data, offset: &offset))
            }
            offset = end
            return .list(name, children)
        }
        guard offset + size <= data.count else { throw BmhelperTreeError.truncated }
        let payload = data.subdata(in: offset..<(offset + size))
        offset += size
        return .leaf(name, payload)
    }

    private static func isListName(_ name: String) -> Bool {
        guard let first = name.utf8.first else { return false }
        return first >= 65 && first <= 90
    }

    private static func appendName(_ name: String, into data: inout Data) {
        var bytes = Array(name.utf8.prefix(4))
        while bytes.count < 4 {
            bytes.append(0x20)
        }
        data.append(contentsOf: bytes)
    }

    private static func readName(from data: Data, offset: inout Int) throws -> String {
        guard offset + 4 <= data.count else { throw BmhelperTreeError.truncated }
        let bytes = Array(data[offset..<(offset + 4)])
        offset += 4
        return String(bytes: bytes, encoding: .ascii) ?? "    "
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func replaceUInt32(_ data: inout Data, at offset: Int, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { raw in
            data.replaceSubrange(offset..<(offset + 4), with: raw)
        }
    }

    private static func readUInt32(from data: Data, offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw BmhelperTreeError.truncated }
        let value = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        offset += 4
        return value
    }
}

struct BmhelperMidiBlob: Equatable {
    var quantize: Int
    var notes: [MidiNoteEvent]
}

struct BmhelperSavedDivision: Equatable {
    var name: String
    var midi: BmhelperMidiBlob
    var src2def: [Int]
    var definitions: [BmhelperDivisionDefinition]
    var zzEnabled: Bool
    var source: BmhelperMidiBlob
}

struct BmhelperProject: Equatable {
    var source: BmhelperMidiBlob
    var divisions: [BmhelperSavedDivision]

    var divisionNames: [String] {
        BmhelperDivisionList.names(divisions.map(\.name))
    }

    /// 只改第一个 division 的名字。取消返回 `nil`。不改音符 / zz / div。
    func renamingFirstDivision(_ entered: String?) -> BmhelperProject? {
        renamingDivision(at: 0, entered)
    }

    /// 只改选中下标的名字。取消返回 `nil`。不改音符 / zz / div。
    func renamingDivision(at index: Int, _ entered: String?) -> BmhelperProject? {
        guard let name = BmhelperRename.commit(entered) else { return nil }
        var updated = self
        if updated.divisions.indices.contains(index) {
            updated.divisions[index].name = name
        }
        return updated
    }

    /// 只去掉选中下标的 division。取消返回 `nil`。不重新聚类，不改源 MIDI。
    func deletingDivision(at index: Int, _ confirmed: Bool?) -> BmhelperProject? {
        guard BmhelperDelete.commit(confirmed) else { return nil }
        guard divisions.indices.contains(index) else { return nil }
        var updated = self
        updated.divisions.remove(at: index)
        return updated
    }

    /// 就地重聚选中下标。取消返回 `nil`。条数不变。其余 division 原样。
    /// 用该 division 的 `source.notes`；若空则退回工程源音符。
    /// `setting == nil` 或 `confirmed` 为 `nil` / `false` 都算取消。
    func regeneratingDivision(
        at index: Int,
        _ setting: BmhelperDivisionSetting?,
        confirmed: Bool? = true
    ) -> BmhelperProject? {
        guard BmhelperRegenerate.commit(confirmed) else { return nil }
        guard let setting else { return nil }
        guard divisions.indices.contains(index) else { return nil }
        var updated = self
        let existing = updated.divisions[index]
        let notes = existing.source.notes.isEmpty ? source.notes : existing.source.notes
        let quantize = max(existing.source.quantize > 0 ? existing.source.quantize : source.quantize, 1)
        let result = BmhelperDivision.divide(notes: notes, setting: setting, quantize: quantize)
        updated.divisions[index] = BmhelperSavedDivision(
            name: setting.name.isEmpty ? BmhelperDefDialogLayout.defaultName : setting.name,
            midi: BmhelperMidiBlob(quantize: result.quantize, notes: result.notes),
            src2def: result.src2def,
            definitions: result.definitions,
            zzEnabled: setting.zzDefinition,
            source: existing.source
        )
        return updated
    }

    /// 只改选中下标的 `definitions[].zz`。不重新聚类。
    /// 不改 `div` / 音符 / `src2def` / 源 MIDI。其余 division 原样。
    func transposingDefinitions(at index: Int, _ kind: BmhelperTranspose.Kind?) -> BmhelperProject? {
        guard let kind else { return nil }
        guard divisions.indices.contains(index) else { return nil }
        var updated = self
        let existing = updated.divisions[index]
        let next = BmhelperTranspose.apply(
            zzEnabled: existing.zzEnabled,
            zzStrings: existing.definitions.map(\.zz),
            kind: kind
        )
        for i in updated.divisions[index].definitions.indices {
            guard next.indices.contains(i) else { continue }
            updated.divisions[index].definitions[i].zz = next[i]
        }
        return updated
    }

    /// 对照 `SetNewSource`：只换工程源。不重建、不删除 division。
    func replacingSource(_ source: BmhelperMidiBlob) -> BmhelperProject {
        var updated = self
        updated.source = source
        return updated
    }

    /// 空文件列表不改工程。有文件则只换源，脏标记原样返回。
    func applyingDroppedFiles(
        _ files: [String],
        source: BmhelperMidiBlob,
        changed: Bool
    ) -> (project: BmhelperProject, changed: Bool) {
        if files.isEmpty {
            return (self, changed)
        }
        return (replacingSource(source), BmhelperDrop.changeFlagAfterReplace(wasChanged: changed))
    }
}

enum BmhelperProjectFile {
    static let fileExtension = "bmh"
    static let filterTitle = "BMHelper project(*.bmh)|*.bmh"

    static func encode(_ project: BmhelperProject) -> Data {
        var root = BmhelperTreeNode.list(BmhelperTree.projectRoot)
        root.children.append(encodeMidiList(BmhelperTree.sourceList, project.source))
        for division in project.divisions {
            root.children.append(encodeDivision(division))
        }
        return BmhelperTree.write(root)
    }

    static func decode(_ data: Data) throws -> BmhelperProject {
        let root = try BmhelperTree.read(data)
        guard root.name == BmhelperTree.projectRoot, root.isList else {
            throw BmhelperTreeError.badRoot
        }
        var source = BmhelperMidiBlob(quantize: 480, notes: [])
        var divisions: [BmhelperSavedDivision] = []
        for child in root.children {
            if child.name == BmhelperTree.sourceList {
                source = decodeMidi(child)
            } else if child.name == BmhelperTree.divisionList {
                divisions.append(decodeDivision(child))
            }
        }
        return BmhelperProject(source: source, divisions: divisions)
    }

    static func make(
        sourceNotes: [MidiNoteEvent],
        quantize: Int,
        setting: BmhelperDivisionSetting
    ) -> BmhelperProject {
        let result = BmhelperDivision.divide(notes: sourceNotes, setting: setting, quantize: quantize)
        let source = BmhelperMidiBlob(quantize: quantize, notes: sourceNotes)
        let division = BmhelperSavedDivision(
            name: setting.name.isEmpty ? BmhelperDefDialogLayout.defaultName : setting.name,
            midi: BmhelperMidiBlob(quantize: result.quantize, notes: result.notes),
            src2def: result.src2def,
            definitions: result.definitions,
            zzEnabled: setting.zzDefinition,
            source: source
        )
        return BmhelperProject(source: source, divisions: [division])
    }

    private static func encodeMidiList(_ name: String, _ midi: BmhelperMidiBlob) -> BmhelperTreeNode {
        var node = BmhelperTreeNode.list(name)
        node.children.append(.leaf(BmhelperTree.quantizeLeaf, int32Data(midi.quantize)))
        for note in midi.notes {
            node.children.append(.leaf(BmhelperTree.noteLeaf, noteData(note)))
        }
        return node
    }

    private static func encodeDivision(_ division: BmhelperSavedDivision) -> BmhelperTreeNode {
        var node = BmhelperTreeNode.list(BmhelperTree.divisionList)
        node.children.append(encodeMidiList(BmhelperTree.midiList, division.midi))
        node.children.append(.leaf(BmhelperTree.nameLeaf, Data(division.name.utf8)))
        node.children.append(.leaf(BmhelperTree.src2defLeaf, int32ArrayData(division.src2def)))
        for definition in division.definitions {
            node.children.append(.leaf(BmhelperTree.definitionLeaf, definitionData(definition)))
        }
        node.children.append(.leaf(BmhelperTree.zzEnabledLeaf, Data([division.zzEnabled ? 1 : 0])))
        node.children.append(encodeMidiList(BmhelperTree.sourceDataList, division.source))
        return node
    }

    private static func decodeMidi(_ node: BmhelperTreeNode) -> BmhelperMidiBlob {
        var quantize = 480
        var notes: [MidiNoteEvent] = []
        for child in node.children {
            if child.name == BmhelperTree.quantizeLeaf, let value = int32(from: child.data) {
                quantize = value
            } else if child.name == BmhelperTree.noteLeaf, let note = note(from: child.data) {
                notes.append(note)
            }
        }
        return BmhelperMidiBlob(quantize: quantize, notes: notes)
    }

    private static func decodeDivision(_ node: BmhelperTreeNode) -> BmhelperSavedDivision {
        var midi = BmhelperMidiBlob(quantize: 480, notes: [])
        var source = BmhelperMidiBlob(quantize: 480, notes: [])
        var name = BmhelperDefDialogLayout.defaultName
        var src2def: [Int] = []
        var definitions: [BmhelperDivisionDefinition] = []
        var zzEnabled = true
        for child in node.children {
            if child.name == BmhelperTree.midiList {
                midi = decodeMidi(child)
            } else if child.name == BmhelperTree.nameLeaf {
                name = String(data: child.data, encoding: .utf8) ?? name
            } else if child.name == BmhelperTree.src2defLeaf {
                src2def = int32Array(from: child.data)
            } else if child.name == BmhelperTree.definitionLeaf, let definition = definition(from: child.data) {
                definitions.append(definition)
            } else if child.name == BmhelperTree.zzEnabledLeaf, let flag = child.data.first {
                zzEnabled = flag != 0
            } else if child.name == BmhelperTree.sourceDataList {
                source = decodeMidi(child)
            }
        }
        if name.isEmpty {
            name = BmhelperDefDialogLayout.defaultName
        }
        return BmhelperSavedDivision(
            name: name,
            midi: midi,
            src2def: src2def,
            definitions: definitions,
            zzEnabled: zzEnabled,
            source: source
        )
    }

    private static func noteData(_ note: MidiNoteEvent) -> Data {
        var data = Data()
        appendInt32(&data, note.position)
        appendInt32(&data, note.gate)
        appendInt32(&data, note.noteNum)
        appendInt32(&data, note.velocity)
        return data
    }

    private static func note(from data: Data) -> MidiNoteEvent? {
        guard data.count >= 16 else { return nil }
        return MidiNoteEvent(
            position: int32(from: data, at: 0) ?? 0,
            gate: int32(from: data, at: 4) ?? 0,
            noteNum: int32(from: data, at: 8) ?? 0,
            velocity: int32(from: data, at: 12) ?? 0
        )
    }

    private static func definitionData(_ definition: BmhelperDivisionDefinition) -> Data {
        var zz = ZZNumber()
        _ = zz.from_string(definition.zz)
        var data = Data()
        appendUInt32(&data, UInt32(zz.low))
        appendUInt32(&data, UInt32(zz.high))
        appendInt32(&data, definition.div)
        return data
    }

    private static func definition(from data: Data) -> BmhelperDivisionDefinition? {
        guard data.count >= 12 else { return nil }
        let low = int32(from: data, at: 0).map { UInt(max($0, 0)) } ?? 0
        let high = int32(from: data, at: 4).map { UInt(max($0, 0)) } ?? 0
        let div = int32(from: data, at: 8) ?? 0
        return BmhelperDivisionDefinition(zz: ZZNumber(low: low, high: high).to_string(), div: div)
    }

    private static func int32ArrayData(_ values: [Int]) -> Data {
        var data = Data()
        for value in values {
            appendInt32(&data, value)
        }
        return data
    }

    private static func int32Array(from data: Data) -> [Int] {
        stride(from: 0, to: data.count - data.count % 4, by: 4).compactMap { int32(from: data, at: $0) }
    }

    private static func int32Data(_ value: Int) -> Data {
        var data = Data()
        appendInt32(&data, value)
        return data
    }

    private static func int32(from data: Data) -> Int? {
        int32(from: data, at: 0)
    }

    private static func int32(from data: Data, at offset: Int) -> Int? {
        guard offset + 4 <= data.count else { return nil }
        let value = Int32(bitPattern:
            UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        )
        return Int(value)
    }

    private static func appendInt32(_ data: inout Data, _ value: Int) {
        var little = Int32(truncatingIfNeeded: value).littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
