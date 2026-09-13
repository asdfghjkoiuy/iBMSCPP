import Foundation

struct IBMSCNote: Equatable, Sendable {
    var vPosition: Double
    var columnIndex: Int
    var value: Int64
    var longNote: Bool
    var length: Double
    var hidden: Bool
    var landmine: Bool

    func matches(_ other: IBMSCNote, ntInput: Bool) -> Bool {
        if ntInput {
            return vPosition == other.vPosition
                && columnIndex == other.columnIndex
                && value == other.value
                && hidden == other.hidden
                && length == other.length
                && landmine == other.landmine
        }
        return vPosition == other.vPosition
            && columnIndex == other.columnIndex
            && value == other.value
            && longNote == other.longNote
            && hidden == other.hidden
            && landmine == other.landmine
    }
}

struct IBMSCHeader: Equatable, Sendable {
    var title: String
    var artist: String
    var genre: String
    var subtitle: String
    var subartist: String
    var bpmValue: Int64
    var playLevel: String
    var playerRank: UInt8 = 0
    var stageFile: String = ""
    var banner: String = ""
    var backBMP: String = ""
    var difficulty: UInt8 = 0
    var exRank: String = ""
    var total: String = ""
    var comment: String = ""
    var lnObjIndex: Int16 = 0
}

struct IBMSCDocument: Equatable, Sendable {
    var magicOK: Bool
    var major: UInt8
    var minor: UInt8
    var build: UInt8
    var ntInput: Bool
    var snap: Bool
    var disableVerticalMove: Bool
    var showFileName: Bool
    var showLeftSplitter: Bool
    var showRightSplitter: Bool
    var lockLeftScroll: Bool
    var lockMiddleScroll: Bool
    var lockRightScroll: Bool
    var errorCheck: Bool
    var previewOnClick: Bool
    var showToolbar: Bool
    var showOptionsPanel: Bool
    var showStatusBar: Bool
    var showGrid: Bool
    var showSubGrid: Bool
    var showBackground: Bool
    var showMeasureNumber: Bool
    var showMeasureBar: Bool
    var showVerticalLine: Bool
    var showColumnCaption: Bool
    var showBPMColumn: Bool
    var showStopColumn: Bool
    var showBGAColumns: Bool
    var showScrollColumn: Bool
    var divide: Int
    var sub: Int
    var slash: Int
    var height: Double
    var width: Double
    var bgmColumns: Int
    var header: IBMSCHeader
    var measureLengths: [Int: Double]
    var notes: [IBMSCNote]
    var expansion: String
    var wavs: [Int: String]
    var bmps: [Int: String]
    var wavOptions: UInt8
    var undo: IBMSCUndoHistory
}

enum IBMSCUndoOp: UInt8 {
    case void = 0
    case addNote = 1
    case removeNote = 2
    case changeNote = 3
    case moveNote = 4
    case longNoteModify = 5
    case hiddenNoteModify = 6
    case relabelNote = 7
    case removeAllNotes = 15
    case changeMeasureLength = 16
    case changeTimeSelection = 17
    case nt = 18
    case wavAutoinc = 20
    case noOperation = 255
}

enum IBMSCUndoCommand: Equatable {
    case void
    case addNote(IBMSCNote)
    case removeNote(IBMSCNote)
    case changeNote(from: IBMSCNote, to: IBMSCNote)
    case moveNote(note: IBMSCNote, column: Int, vPosition: Double)
    case longNoteModify(note: IBMSCNote, vPosition: Double, length: Double)
    case hiddenNoteModify(note: IBMSCNote, hidden: Bool)
    case relabelNote(note: IBMSCNote, value: Int64)
    case removeAllNotes
    case changeMeasureLength(value: Double, indices: [Int])
    case changeTimeSelection(start: Double, length: Double, half: Double, selected: Bool)
    case nt(becomeNT: Bool, autoConvert: Bool)
    case wavAutoinc(Bool)
    case noOperation
    case unknown(Data)

    var op: IBMSCUndoOp? {
        switch self {
        case .void: return .void
        case .addNote: return .addNote
        case .removeNote: return .removeNote
        case .changeNote: return .changeNote
        case .moveNote: return .moveNote
        case .longNoteModify: return .longNoteModify
        case .hiddenNoteModify: return .hiddenNoteModify
        case .relabelNote: return .relabelNote
        case .removeAllNotes: return .removeAllNotes
        case .changeMeasureLength: return .changeMeasureLength
        case .changeTimeSelection: return .changeTimeSelection
        case .nt: return .nt
        case .wavAutoinc: return .wavAutoinc
        case .noOperation: return .noOperation
        case .unknown: return nil
        }
    }

    static func fromBytes(_ data: Data) -> IBMSCUndoCommand? {
        guard let first = data.first else { return nil }
        var reader = LegacyBinaryReader(data: data)
        _ = reader.readUInt8()
        switch IBMSCUndoOp(rawValue: first) {
        case .void:
            return .void
        case .addNote:
            return reader.readNote().map { .addNote($0) }
        case .removeNote:
            return reader.readNote().map { .removeNote($0) }
        case .changeNote:
            guard let from = reader.readNote(), let to = reader.readNote() else { return nil }
            return .changeNote(from: from, to: to)
        case .moveNote:
            guard let note = reader.readNote(),
                  let column = reader.readInt32(),
                  let vPosition = reader.readDouble() else { return nil }
            return .moveNote(note: note, column: Int(column), vPosition: vPosition)
        case .longNoteModify:
            guard let note = reader.readNote(),
                  let length = reader.readDouble(),
                  let vPosition = reader.readDouble() else { return nil }
            return .longNoteModify(note: note, vPosition: vPosition, length: length)
        case .hiddenNoteModify:
            guard let note = reader.readNote(), let hidden = reader.readBool() else { return nil }
            return .hiddenNoteModify(note: note, hidden: hidden)
        case .relabelNote:
            guard let note = reader.readNote(), let value = reader.readInt64() else { return nil }
            return .relabelNote(note: note, value: value)
        case .removeAllNotes:
            return .removeAllNotes
        case .changeMeasureLength:
            guard let value = reader.readDouble(), let last = reader.readInt32() else { return nil }
            var indices: [Int] = []
            if last >= 0 {
                for _ in 0...Int(last) {
                    guard let index = reader.readInt32() else { return nil }
                    indices.append(Int(index))
                }
            }
            return .changeMeasureLength(value: value, indices: indices)
        case .changeTimeSelection:
            guard let start = reader.readDouble(),
                  let length = reader.readDouble(),
                  let half = reader.readDouble(),
                  let selected = reader.readBool() else { return nil }
            return .changeTimeSelection(start: start, length: length, half: half, selected: selected)
        case .nt:
            guard let becomeNT = reader.readBool(), let autoConvert = reader.readBool() else { return nil }
            return .nt(becomeNT: becomeNT, autoConvert: autoConvert)
        case .wavAutoinc:
            return reader.readBool().map { .wavAutoinc($0) }
        case .noOperation:
            return .noOperation
        case nil:
            return .unknown(data)
        }
    }

    func toBytes() -> Data {
        if case .unknown(let data) = self {
            return data
        }
        var writer = LegacyBinaryWriter()
        guard let op else { return Data() }
        writer.writeUInt8(op.rawValue)
        switch self {
        case .void, .noOperation, .removeAllNotes, .unknown:
            break
        case .addNote(let note), .removeNote(let note):
            writer.writeNote(note)
        case .changeNote(let from, let to):
            writer.writeNote(from)
            writer.writeNote(to)
        case .moveNote(let note, let column, let vPosition):
            writer.writeNote(note)
            writer.writeInt32(Int32(column))
            writer.writeDouble(vPosition)
        case .longNoteModify(let note, let vPosition, let length):
            writer.writeNote(note)
            writer.writeDouble(vPosition)
            writer.writeDouble(length)
        case .hiddenNoteModify(let note, let hidden):
            writer.writeNote(note)
            writer.writeBool(hidden)
        case .relabelNote(let note, let value):
            writer.writeNote(note)
            writer.writeInt64(value)
        case .changeMeasureLength(let value, let indices):
            writer.writeDouble(value)
            writer.writeInt32(Int32(indices.count - 1))
            for index in indices {
                writer.writeInt32(Int32(index))
            }
        case .changeTimeSelection(let start, let length, let half, let selected):
            writer.writeDouble(start)
            writer.writeDouble(length)
            writer.writeDouble(half)
            writer.writeBool(selected)
        case .nt(let becomeNT, let autoConvert):
            writer.writeBool(becomeNT)
            writer.writeBool(autoConvert)
        case .wavAutoinc(let checked):
            writer.writeBool(checked)
        }
        return writer.data
    }

    static func perform(_ commands: [IBMSCUndoCommand], on notes: inout [IBMSCNote], ntInput: Bool) {
        for command in commands {
            switch command {
            case .void, .noOperation, .unknown, .changeTimeSelection, .nt, .wavAutoinc:
                continue
            case .addNote(let note):
                notes.append(note)
            case .removeNote(let note):
                if let index = notes.firstIndex(where: { $0.matches(note, ntInput: ntInput) }) {
                    notes.remove(at: index)
                }
            case .changeNote(let from, _):
                if let index = notes.firstIndex(where: { $0.matches(from, ntInput: ntInput) }) {
                    notes[index] = from
                }
            case .moveNote(let note, let column, let vPosition):
                if let index = notes.firstIndex(where: { $0.matches(note, ntInput: ntInput) }) {
                    notes[index].columnIndex = column
                    notes[index].vPosition = vPosition
                }
            case .longNoteModify(let note, let vPosition, let length):
                if let index = notes.firstIndex(where: { $0.matches(note, ntInput: ntInput) }) {
                    if ntInput {
                        notes[index].vPosition = vPosition
                        notes[index].length = length
                    } else {
                        notes[index].longNote = length != 0
                    }
                }
            case .hiddenNoteModify(let note, let hidden):
                if let index = notes.firstIndex(where: { $0.matches(note, ntInput: ntInput) }) {
                    notes[index].hidden = hidden
                }
            case .relabelNote(let note, let value):
                if let index = notes.firstIndex(where: { $0.matches(note, ntInput: ntInput) }) {
                    notes[index].value = value
                }
            case .removeAllNotes:
                notes.removeAll()
            case .changeMeasureLength:
                continue
            }
        }
        notes.sort {
            if $0.vPosition != $1.vPosition { return $0.vPosition < $1.vPosition }
            return $0.columnIndex < $1.columnIndex
        }
    }
}

struct IBMSCUndoSlot: Equatable {
    var undo: [IBMSCUndoCommand]
    var redo: [IBMSCUndoCommand]
}

struct IBMSCUndoHistory: Equatable {
    static let slotCount = 100

    var pointer: Int
    var slots: [IBMSCUndoSlot]

    static var empty: IBMSCUndoHistory {
        IBMSCUndoHistory(
            pointer: 0,
            slots: Array(repeating: IBMSCUndoSlot(undo: [], redo: []), count: slotCount)
        )
    }

    /// `EditorUndoRedo.ClearUndo`: slots 0 and 1 are `NoOperation`.
    static var cleared: IBMSCUndoHistory {
        var history = empty
        history.slots[0] = IBMSCUndoSlot(undo: [.noOperation], redo: [.noOperation])
        history.slots[1] = IBMSCUndoSlot(undo: [.noOperation], redo: [.noOperation])
        return history
    }

    var nextPointer: Int { pointer > 98 ? 0 : pointer + 1 }
    var previousPointer: Int { pointer < 1 ? 99 : pointer - 1 }

    var canUndo: Bool {
        guard slots.indices.contains(pointer), let first = slots[pointer].undo.first else { return false }
        return first != .noOperation
    }

    var canRedo: Bool {
        let index = nextPointer
        guard slots.indices.contains(index), let first = slots[index].redo.first else { return false }
        return first != .noOperation
    }

    mutating func add(undo: [IBMSCUndoCommand], redo: [IBMSCUndoCommand], overwrite: Bool = false) {
        if !overwrite {
            pointer = nextPointer
        }
        guard slots.indices.contains(pointer) else { return }
        slots[pointer] = IBMSCUndoSlot(undo: undo, redo: redo)
        let next = nextPointer
        if slots.indices.contains(next) {
            slots[next] = IBMSCUndoSlot(undo: [.noOperation], redo: [.noOperation])
        }
    }

    mutating func undo(notes: inout [IBMSCNote], ntInput: Bool) -> Bool {
        guard canUndo else { return false }
        IBMSCUndoCommand.perform(slots[pointer].undo, on: &notes, ntInput: ntInput)
        pointer = previousPointer
        return true
    }

    mutating func redo(notes: inout [IBMSCNote], ntInput: Bool) -> Bool {
        guard canRedo else { return false }
        IBMSCUndoCommand.perform(slots[nextPointer].redo, on: &notes, ntInput: ntInput)
        pointer = nextPointer
        return true
    }
}

enum LegacyIBMSC {
    static let magic = Int32(bitPattern: 0x534D_4269)
    static let magicLetter: UInt8 = 0x43
    static let preferencesID = Int32(bitPattern: 0x6665_7250)
    static let headerID = Int32(bitPattern: 0x6461_6548)
    static let wavID = Int32(0x0056_4157)
    static let bmpID = Int32(0x0050_4D42)
    static let beatID = Int32(bitPattern: 0x7461_6542)
    static let expansionID = Int32(bitPattern: 0x6E70_7845)
    static let noteID = Int32(bitPattern: 0x6574_6F4E)
    static let undoID = Int32(bitPattern: 0x6F64_6E55)

    static let prefNTInput = 0x1
    static let prefSnap = 0x1_000_000
    static let prefDisableVertical = 0x2_000_000
    static let prefShowFileName = 0x8
    static let prefLeftSplitter = 0x1000
    static let prefRightSplitter = 0x2000
    static let prefLockLeft = 0x4_000_000
    static let prefLockMiddle = 0x8_000_000
    static let prefLockRight = 0x10_000_000
    static let prefErrorCheck = 0x2
    static let prefPreviewOnClick = 0x4
    static let prefToolbar = 0x200
    static let prefOptionsPanel = 0x400
    static let prefStatusBar = 0x800
    static let prefShowGrid = 0x4000
    static let prefShowSubGrid = 0x8000
    static let prefShowBackground = 0x1_0000
    static let prefShowMeasureNumber = 0x2_0000
    static let prefShowMeasureBar = 0x4_0000
    static let prefShowVerticalLine = 0x8_0000
    static let prefShowColumnCaption = 0x10_0000
    static let prefShowBGAColumns = 0x20_0000
    static let prefShowStopColumn = 0x40_0000
    static let prefShowBPMColumn = 0x80_0000
    static let prefShowScrollColumn = 0x2000_0000

    /// `ChartIO`：Pref 整数各位。
    static func packPreferences(
        ntInput: Bool,
        snap: Bool,
        disableVerticalMove: Bool,
        showFileName: Bool = false,
        showLeftSplitter: Bool = false,
        showRightSplitter: Bool = false,
        lockLeftScroll: Bool = false,
        lockMiddleScroll: Bool = false,
        lockRightScroll: Bool = false,
        errorCheck: Bool = false,
        previewOnClick: Bool = false,
        showToolbar: Bool = false,
        showOptionsPanel: Bool = false,
        showStatusBar: Bool = false,
        showGrid: Bool = false,
        showSubGrid: Bool = false,
        showBackground: Bool = false,
        showMeasureNumber: Bool = false,
        showMeasureBar: Bool = false,
        showVerticalLine: Bool = false,
        showColumnCaption: Bool = false,
        showBPMColumn: Bool = false,
        showStopColumn: Bool = false,
        showBGAColumns: Bool = false,
        showScrollColumn: Bool = false
    ) -> Int32 {
        var pref = 0
        if ntInput { pref |= prefNTInput }
        if errorCheck { pref |= prefErrorCheck }
        if previewOnClick { pref |= prefPreviewOnClick }
        if showFileName { pref |= prefShowFileName }
        if showToolbar { pref |= prefToolbar }
        if showOptionsPanel { pref |= prefOptionsPanel }
        if showStatusBar { pref |= prefStatusBar }
        if showLeftSplitter { pref |= prefLeftSplitter }
        if showRightSplitter { pref |= prefRightSplitter }
        if showGrid { pref |= prefShowGrid }
        if showSubGrid { pref |= prefShowSubGrid }
        if showBackground { pref |= prefShowBackground }
        if showMeasureNumber { pref |= prefShowMeasureNumber }
        if showMeasureBar { pref |= prefShowMeasureBar }
        if showVerticalLine { pref |= prefShowVerticalLine }
        if showColumnCaption { pref |= prefShowColumnCaption }
        if showBGAColumns { pref |= prefShowBGAColumns }
        if showStopColumn { pref |= prefShowStopColumn }
        if showBPMColumn { pref |= prefShowBPMColumn }
        if snap { pref |= prefSnap }
        if disableVerticalMove { pref |= prefDisableVertical }
        if lockLeftScroll { pref |= prefLockLeft }
        if lockMiddleScroll { pref |= prefLockMiddle }
        if lockRightScroll { pref |= prefLockRight }
        if showScrollColumn { pref |= prefShowScrollColumn }
        return Int32(pref)
    }

    /// `ChartIO`：`CHPlayer.SelectedIndex | (CHRank.SelectedIndex << 4)`。
    static func packPlayerRank(playerIndex: Int, rankIndex: Int) -> UInt8 {
        UInt8((max(0, min(15, playerIndex)) & 0xF) | ((max(0, min(15, rankIndex)) & 0xF) << 4))
    }

    static func playerIndex(from packed: UInt8) -> Int {
        Int(packed & 0xF)
    }

    static func rankIndex(from packed: UInt8) -> Int {
        Int(packed >> 4)
    }

    static func parse(_ data: Data) -> IBMSCDocument? {
        var reader = LegacyBinaryReader(data: data)
        guard let magic = reader.readInt32(), magic == self.magic,
              let letter = reader.readUInt8(), letter == magicLetter,
              let major = reader.readUInt8(),
              let minor = reader.readUInt8(),
              let build = reader.readUInt8() else { return nil }

        var document = IBMSCDocument(
            magicOK: true,
            major: major,
            minor: minor,
            build: build,
            ntInput: true,
            snap: true,
            disableVerticalMove: false,
            showFileName: false,
            showLeftSplitter: false,
            showRightSplitter: false,
            lockLeftScroll: false,
            lockMiddleScroll: false,
            lockRightScroll: false,
            errorCheck: false,
            previewOnClick: false,
            showToolbar: false,
            showOptionsPanel: false,
            showStatusBar: false,
            showGrid: false,
            showSubGrid: false,
            showBackground: false,
            showMeasureNumber: false,
            showMeasureBar: false,
            showVerticalLine: false,
            showColumnCaption: false,
            showBPMColumn: false,
            showStopColumn: false,
            showBGAColumns: false,
            showScrollColumn: false,
            divide: MainWindowChrome.defaultDivision,
            sub: MainWindowChrome.defaultSubDivision,
            slash: LegacyGridDivision.defaultSlash,
            height: Double(MainWindowChrome.defaultGridHeight),
            width: Double(MainWindowChrome.defaultGridWidth),
            bgmColumns: 0,
            header: IBMSCHeader(title: "", artist: "", genre: "", subtitle: "", subartist: "", bpmValue: 1_200_000, playLevel: ""),
            measureLengths: [:],
            notes: [],
            expansion: "",
            wavs: [:],
            bmps: [:],
            wavOptions: 3,
            undo: .empty
        )
        while reader.hasBytes {
            guard let block = reader.readInt32() else { break }
            switch block {
            case preferencesID:
                guard let pref = reader.readInt32(),
                      let divide = reader.readInt32(),
                      let sub = reader.readInt32(),
                      let slash = reader.readInt32(),
                      let height = reader.readFloat(),
                      let width = reader.readFloat(),
                      let columns = reader.readInt32() else { return document }
                document.divide = LegacyGridDivision.clamp(Int(divide))
                document.sub = LegacyGridDivision.clamp(Int(sub))
                document.height = ChartZoom.clampField(Double(height))
                document.width = ChartZoom.clampField(Double(width))
                document.bgmColumns = Int(columns)
                document.ntInput = pref & Int32(prefNTInput) != 0
                document.snap = pref & Int32(prefSnap) != 0
                document.disableVerticalMove = pref & Int32(prefDisableVertical) != 0
                document.showFileName = pref & Int32(prefShowFileName) != 0
                document.showLeftSplitter = pref & Int32(prefLeftSplitter) != 0
                document.showRightSplitter = pref & Int32(prefRightSplitter) != 0
                document.lockLeftScroll = pref & Int32(prefLockLeft) != 0
                document.lockMiddleScroll = pref & Int32(prefLockMiddle) != 0
                document.lockRightScroll = pref & Int32(prefLockRight) != 0
                document.errorCheck = pref & Int32(prefErrorCheck) != 0
                document.previewOnClick = pref & Int32(prefPreviewOnClick) != 0
                document.showToolbar = pref & Int32(prefToolbar) != 0
                document.showOptionsPanel = pref & Int32(prefOptionsPanel) != 0
                document.showStatusBar = pref & Int32(prefStatusBar) != 0
                document.showGrid = pref & Int32(prefShowGrid) != 0
                document.showSubGrid = pref & Int32(prefShowSubGrid) != 0
                document.showBackground = pref & Int32(prefShowBackground) != 0
                document.showMeasureNumber = pref & Int32(prefShowMeasureNumber) != 0
                document.showMeasureBar = pref & Int32(prefShowMeasureBar) != 0
                document.showVerticalLine = pref & Int32(prefShowVerticalLine) != 0
                document.showColumnCaption = pref & Int32(prefShowColumnCaption) != 0
                document.showBPMColumn = pref & Int32(prefShowBPMColumn) != 0
                document.showStopColumn = pref & Int32(prefShowStopColumn) != 0
                document.showBGAColumns = pref & Int32(prefShowBGAColumns) != 0
                document.showScrollColumn = pref & Int32(prefShowScrollColumn) != 0
                document.slash = LegacyGridDivision.clamp(Int(slash))
            case headerID:
                guard let title = reader.readDotNetString(),
                      let artist = reader.readDotNetString(),
                      let genre = reader.readDotNetString(),
                      let bpm = reader.readInt64(),
                      let playerRank = reader.readUInt8(),
                      let playLevel = reader.readDotNetString(),
                      let subtitle = reader.readDotNetString(),
                      let subartist = reader.readDotNetString(),
                      let stageFile = reader.readDotNetString(),
                      let banner = reader.readDotNetString(),
                      let backBMP = reader.readDotNetString(),
                      let difficulty = reader.readUInt8(),
                      let exRank = reader.readDotNetString(),
                      let total = reader.readDotNetString(),
                      let comment = reader.readDotNetString(),
                      let lnObjIndex = reader.readInt16() else { return document }
                document.header = IBMSCHeader(
                    title: title, artist: artist, genre: genre,
                    subtitle: subtitle, subartist: subartist,
                    bpmValue: bpm, playLevel: playLevel,
                    playerRank: playerRank,
                    stageFile: stageFile,
                    banner: banner,
                    backBMP: backBMP,
                    difficulty: difficulty,
                    exRank: exRank,
                    total: total,
                    comment: comment,
                    lnObjIndex: lnObjIndex
                )
            case wavID:
                guard let options = reader.readUInt8(), let count = reader.readInt32() else { return document }
                document.wavOptions = options
                for _ in 0..<max(0, count) {
                    guard let index = reader.readInt16(), let name = reader.readDotNetString() else { return document }
                    if index >= 1 && index <= 1295 {
                        document.wavs[Int(index)] = name
                    }
                }
            case bmpID:
                guard let count = reader.readInt32() else { return document }
                for _ in 0..<max(0, count) {
                    guard let index = reader.readInt16(), let name = reader.readDotNetString() else { return document }
                    if index >= 1 && index <= 1295 {
                        document.bmps[Int(index)] = name
                    }
                }
            case beatID:
                guard reader.readInt16() != nil, reader.readInt16() != nil, reader.readUInt8() != nil,
                      let count = reader.readInt32() else { return document }
                for _ in 0..<max(0, count) {
                    guard let index = reader.readInt16(), let length = reader.readDouble() else { return document }
                    document.measureLengths[Int(index)] = length
                }
            case expansionID:
                guard let expansion = reader.readDotNetString() else { return document }
                document.expansion = expansion
            case noteID:
                guard let upper = reader.readInt32() else { return document }
                var notes: [IBMSCNote] = []
                if upper >= 1 {
                    for _ in 1...upper {
                        guard let note = reader.readNote() else { return document }
                        notes.append(note)
                    }
                }
                document.notes = notes
            case undoID:
                guard let undo = parseUndo(&reader) else { return document }
                document.undo = undo
            default:
                return document
            }
        }
        return document
    }

    static func writeSubset(
        header: IBMSCHeader,
        notes: [IBMSCNote],
        ntInput: Bool,
        snap: Bool = true,
        disableVerticalMove: Bool = false,
        showFileName: Bool = false,
        showLeftSplitter: Bool = false,
        showRightSplitter: Bool = false,
        lockLeftScroll: Bool = false,
        lockMiddleScroll: Bool = false,
        lockRightScroll: Bool = false,
        errorCheck: Bool = false,
        previewOnClick: Bool = false,
        showToolbar: Bool = false,
        showOptionsPanel: Bool = false,
        showStatusBar: Bool = false,
        showGrid: Bool = false,
        showSubGrid: Bool = false,
        showBackground: Bool = false,
        showMeasureNumber: Bool = false,
        showMeasureBar: Bool = false,
        showVerticalLine: Bool = false,
        showColumnCaption: Bool = false,
        showBPMColumn: Bool = false,
        showStopColumn: Bool = false,
        showBGAColumns: Bool = false,
        showScrollColumn: Bool = false,
        divide: Int = MainWindowChrome.defaultDivision,
        sub: Int = MainWindowChrome.defaultSubDivision,
        slash: Int = LegacyGridDivision.defaultSlash,
        height: Double = Double(MainWindowChrome.defaultGridHeight),
        width: Double = Double(MainWindowChrome.defaultGridWidth),
        bgmColumns: Int = 0,
        measureLengths: [Int: Double],
        expansion: String = "",
        wavs: [Int: String] = [:],
        bmps: [Int: String] = [:],
        wavOptions: UInt8 = 3,
        undo: IBMSCUndoHistory = .cleared
    ) -> Data {
        var writer = LegacyBinaryWriter()
        writer.writeInt32(magic)
        writer.writeUInt8(magicLetter)
        writer.writeUInt8(0)
        writer.writeUInt8(0)
        writer.writeUInt8(0)
        writer.writeInt32(preferencesID)
        writer.writeInt32(packPreferences(
            ntInput: ntInput,
            snap: snap,
            disableVerticalMove: disableVerticalMove,
            showFileName: showFileName,
            showLeftSplitter: showLeftSplitter,
            showRightSplitter: showRightSplitter,
            lockLeftScroll: lockLeftScroll,
            lockMiddleScroll: lockMiddleScroll,
            lockRightScroll: lockRightScroll,
            errorCheck: errorCheck,
            previewOnClick: previewOnClick,
            showToolbar: showToolbar,
            showOptionsPanel: showOptionsPanel,
            showStatusBar: showStatusBar,
            showGrid: showGrid,
            showSubGrid: showSubGrid,
            showBackground: showBackground,
            showMeasureNumber: showMeasureNumber,
            showMeasureBar: showMeasureBar,
            showVerticalLine: showVerticalLine,
            showColumnCaption: showColumnCaption,
            showBPMColumn: showBPMColumn,
            showStopColumn: showStopColumn,
            showBGAColumns: showBGAColumns,
            showScrollColumn: showScrollColumn
        ))
        writer.writeInt32(Int32(LegacyGridDivision.clamp(divide)))
        writer.writeInt32(Int32(LegacyGridDivision.clamp(sub)))
        writer.writeInt32(Int32(LegacyGridDivision.clamp(slash)))
        writer.writeFloat(Float(ChartZoom.clampField(height)))
        writer.writeFloat(Float(ChartZoom.clampField(width)))
        writer.writeInt32(Int32(bgmColumns))
        writer.writeInt32(headerID)
        writer.writeDotNetString(header.title)
        writer.writeDotNetString(header.artist)
        writer.writeDotNetString(header.genre)
        writer.writeInt64(header.bpmValue)
        writer.writeUInt8(header.playerRank)
        writer.writeDotNetString(header.playLevel)
        writer.writeDotNetString(header.subtitle)
        writer.writeDotNetString(header.subartist)
        writer.writeDotNetString(header.stageFile)
        writer.writeDotNetString(header.banner)
        writer.writeDotNetString(header.backBMP)
        writer.writeUInt8(header.difficulty)
        writer.writeDotNetString(header.exRank)
        writer.writeDotNetString(header.total)
        writer.writeDotNetString(header.comment)
        writer.writeInt16(header.lnObjIndex)
        writer.writeInt32(wavID)
        writer.writeUInt8(wavOptions)
        let wavEntries = wavs.keys.sorted().compactMap { index -> (Int, String)? in
            guard index >= 1, index <= 1295, let name = wavs[index], !name.isEmpty else { return nil }
            return (index, name)
        }
        writer.writeInt32(Int32(wavEntries.count))
        for (index, name) in wavEntries {
            writer.writeInt16(Int16(index))
            writer.writeDotNetString(name)
        }
        writer.writeInt32(bmpID)
        let bmpEntries = bmps.keys.sorted().compactMap { index -> (Int, String)? in
            guard index >= 1, index <= 1295, let name = bmps[index], !name.isEmpty else { return nil }
            return (index, name)
        }
        writer.writeInt32(Int32(bmpEntries.count))
        for (index, name) in bmpEntries {
            writer.writeInt16(Int16(index))
            writer.writeDotNetString(name)
        }
        writer.writeInt32(beatID)
        writer.writeInt16(4)
        writer.writeInt16(4)
        writer.writeUInt8(0)
        writer.writeInt32(Int32(measureLengths.count))
        for key in measureLengths.keys.sorted() {
            writer.writeInt16(Int16(key))
            writer.writeDouble(measureLengths[key] ?? 192)
        }
        writer.writeInt32(expansionID)
        writer.writeDotNetString(expansion)
        writer.writeInt32(noteID)
        writer.writeInt32(Int32(notes.count))
        for note in notes {
            writer.writeNote(note)
        }
        writeUndo(&writer, undo)
        return writer.data
    }

    static func grid(from vPosition: Double, measureLengths: [Int: Double]) -> (measure: Int, slot: Int, division: Int) {
        LegacyMeasureGrid.grid(from: vPosition, measureLengths: measureLengths)
    }

    private static func parseUndo(_ reader: inout LegacyBinaryReader) -> IBMSCUndoHistory? {
        guard let count = reader.readInt32(), let pointer = reader.readInt32() else { return nil }
        var history = IBMSCUndoHistory.empty
        history.pointer = Int(pointer)
        let slots = min(IBMSCUndoHistory.slotCount, max(0, Int(count)))
        for index in 0..<slots {
            guard let undo = parseCommandList(&reader), let redo = parseCommandList(&reader) else { return nil }
            history.slots[index] = IBMSCUndoSlot(undo: undo, redo: redo)
        }
        return history
    }

    private static func parseCommandList(_ reader: inout LegacyBinaryReader) -> [IBMSCUndoCommand]? {
        guard let count = reader.readInt32() else { return nil }
        var commands: [IBMSCUndoCommand] = []
        for _ in 0..<max(0, Int(count)) {
            guard let length = reader.readInt32(), let bytes = reader.read(Int(length)),
                  let command = IBMSCUndoCommand.fromBytes(bytes) else { return nil }
            commands.append(command)
        }
        return commands
    }

    private static func writeUndo(_ writer: inout LegacyBinaryWriter, _ history: IBMSCUndoHistory) {
        writer.writeInt32(undoID)
        writer.writeInt32(Int32(IBMSCUndoHistory.slotCount))
        writer.writeInt32(Int32(history.pointer))
        for index in 0..<IBMSCUndoHistory.slotCount {
            let slot = history.slots.indices.contains(index)
                ? history.slots[index]
                : IBMSCUndoSlot(undo: [], redo: [])
            writeCommandList(&writer, slot.undo)
            writeCommandList(&writer, slot.redo)
        }
    }

    private static func writeCommandList(_ writer: inout LegacyBinaryWriter, _ commands: [IBMSCUndoCommand]) {
        writer.writeInt32(Int32(commands.count))
        for command in commands {
            let bytes = command.toBytes()
            writer.writeInt32(Int32(bytes.count))
            writer.writeBytes(bytes)
        }
    }
}

struct LegacyBinaryReader {
    let data: Data
    var offset = 0

    var hasBytes: Bool { offset < data.count }

    mutating func readUInt8() -> UInt8? { read(1).map { $0[0] } }
    mutating func readInt16() -> Int16? { read(2).map { $0.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) } } }
    mutating func readInt32() -> Int32? { read(4).map { $0.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) } } }
    mutating func readInt64() -> Int64? { read(8).map { $0.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) } } }
    mutating func readFloat() -> Float? { read(4).map { $0.withUnsafeBytes { $0.loadUnaligned(as: Float.self) } } }
    mutating func readDouble() -> Double? { read(8).map { $0.withUnsafeBytes { $0.loadUnaligned(as: Double.self) } } }

    mutating func readBool() -> Bool? { readUInt8().map { $0 != 0 } }

    mutating func readDotNetString() -> String? {
        guard let length = read7BitEncodedInt() else { return nil }
        guard length == 0 else {
            guard let bytes = read(length * 2) else { return nil }
            return String(data: bytes, encoding: .utf16LittleEndian) ?? ""
        }
        return ""
    }

    mutating func readNote() -> IBMSCNote? {
        guard let vPosition = readDouble(),
              let column = readInt32(),
              let value = readInt64(),
              let longNote = readBool(),
              let length = readDouble(),
              let hidden = readBool(),
              let landmine = readBool() else { return nil }
        return IBMSCNote(
            vPosition: vPosition, columnIndex: Int(column), value: value,
            longNote: longNote, length: length, hidden: hidden, landmine: landmine
        )
    }

    mutating func skip(_ count: Int) -> Bool {
        guard count >= 0, offset + count <= data.count else { return false }
        offset += count
        return true
    }

    mutating func read(_ count: Int) -> Data? {
        guard count >= 0, offset + count <= data.count else { return nil }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }

    private mutating func read7BitEncodedInt() -> Int? {
        var value = 0
        var shift = 0
        while true {
            guard let byte = readUInt8() else { return nil }
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift > 35 { return nil }
        }
    }
}

struct LegacyBinaryWriter {
    var data = Data()

    mutating func writeUInt8(_ value: UInt8) { data.append(value) }
    mutating func writeInt16(_ value: Int16) { append(value) }
    mutating func writeInt32(_ value: Int32) { append(value) }
    mutating func writeInt64(_ value: Int64) { append(value) }
    mutating func writeFloat(_ value: Float) { append(value) }
    mutating func writeDouble(_ value: Double) { append(value) }
    mutating func writeBool(_ value: Bool) { writeUInt8(value ? 1 : 0) }
    mutating func writeBytes(_ bytes: Data) { data.append(bytes) }

    mutating func writeDotNetString(_ text: String) {
        let units = Array(text.utf16)
        write7BitEncodedInt(units.count)
        for unit in units {
            append(unit)
        }
    }

    mutating func writeNote(_ note: IBMSCNote) {
        writeDouble(note.vPosition)
        writeInt32(Int32(note.columnIndex))
        writeInt64(note.value)
        writeBool(note.longNote)
        writeDouble(note.length)
        writeBool(note.hidden)
        writeBool(note.landmine)
    }

    private mutating func write7BitEncodedInt(_ value: Int) {
        var current = UInt(bitPattern: value)
        while current >= 0x80 {
            writeUInt8(UInt8(current & 0x7F) | 0x80)
            current >>= 7
        }
        writeUInt8(UInt8(current))
    }

    private mutating func append<T>(_ value: T) {
        var next = value
        withUnsafeBytes(of: &next) { data.append(contentsOf: $0) }
    }
}

private func bankersRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}
