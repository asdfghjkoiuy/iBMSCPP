import CoreGraphics
import Foundation

/// 读 SMF 失败时返回，不抛到进程外、不崩溃。
enum BmhelperMidiError: Error, Equatable {
    case emptyFile
    case invalidHeader
    case unsupportedFormat
    case truncated
}

/// 对照 `midi_events.h` 的 `MidiNoteEvent(position, gate, nn, v)`。
/// 这一轮只收到音符列表，不写成 BMS `#xxx11` 行。
struct MidiNoteEvent: Equatable {
    var position: Int
    var gate: Int
    var noteNum: Int
    var velocity: Int
}

/// 一条已配对的音符。`gate` 是 note off 时刻减去 note on 时刻。
struct BmhelperMidiNote: Equatable {
    var tick: Int
    var gate: Int
    var note: Int
    var velocity: Int
    var channel: Int
}

/// 一条 SMF 轨道。`channelsUsed` 固定 16 项，对应通道 0–15。
struct BmhelperMidiTrack: Equatable {
    var index: Int
    var name: String
    var channelsUsed: [Bool]
    var notes: [BmhelperMidiNote]
}

struct BmhelperMidiFile: Equatable {
    var ticksPerQuarter: Int
    var format: Int
    var tracks: [BmhelperMidiTrack]

    /// 对照 `LoadSmfDialog`：默认选第一个「有音符通道」的轨道。
    /// 都没有音符时保持 0，和源码 `def = 0` 一致。
    var defaultSelectedTrackIndex: Int {
        tracks.firstIndex { $0.channelsUsed.contains(true) } ?? 0
    }
}

/// 导入设置。标题和尺寸对照 `LoadSmfDialog` 构造参数。
struct BmhelperMidiImportSettings: Equatable {
    var selectedTrackIndex: Int
    /// 16 个通道复选框。源码默认全部勾选。
    var channelMask: [Bool]

    static let title = BmhelperMidiImportLayout.title
    static let sourceSize = BmhelperMidiImportLayout.clientSize
    static let hasCloseBox = BmhelperMidiImportLayout.hasCloseBox
    static let tracksLabel = BmhelperMidiImportLayout.tracksLabel
    static let tracksTitle = BmhelperMidiImportLayout.tracksTitle

    static func makeDefault(for file: BmhelperMidiFile) -> BmhelperMidiImportSettings {
        BmhelperMidiImportSettings(
            selectedTrackIndex: file.defaultSelectedTrackIndex,
            channelMask: Array(repeating: true, count: 16)
        )
    }
}

enum BmhelperMidiImportText {
    /// `midi_smfin.cpp`：`%04X: %s`
    static func trackChoice(index: Int, name: String) -> String {
        String(format: "%04X: %@", index, name)
    }

    /// `midi_smfin.cpp`：`%02X`
    static func channelTitle(_ channel: Int) -> String {
        String(format: "%02X", channel)
    }
}

enum BmhelperMidi {
    /// 对照 `project.cpp`：`mid` / `midi` / `smf`。
    static let fileExtensions = ["mid", "midi", "smf"]

    static func parse(_ data: Data) -> Result<BmhelperMidiFile, BmhelperMidiError> {
        do {
            return .success(try parseThrowing(data))
        } catch let error as BmhelperMidiError {
            return .failure(error)
        } catch {
            return .failure(.truncated)
        }
    }

    /// 对照 `MidiData_SmfReader`：只收勾选通道上的音符，再按 position 排序。
    static func collectNoteEvents(
        from file: BmhelperMidiFile,
        settings: BmhelperMidiImportSettings
    ) -> [MidiNoteEvent] {
        guard file.tracks.indices.contains(settings.selectedTrackIndex) else {
            return []
        }
        let mask = settings.channelMask
        let notes = file.tracks[settings.selectedTrackIndex].notes.compactMap { note -> MidiNoteEvent? in
            guard note.channel >= 0, note.channel < mask.count, mask[note.channel] else {
                return nil
            }
            return MidiNoteEvent(
                position: note.tick,
                gate: note.gate,
                noteNum: note.note,
                velocity: note.velocity
            )
        }
        return notes.sorted { $0.position < $1.position }
    }

    /// 对照 `midi_smfout.cpp` 的 `MidiData::save_smf`。
    /// Type 1、两轨。轨 0 只有 EOT。轨 1 是时间线音符的 NoteOn / NoteOff + EOT。
    /// 这一轮不写 pitch / CC。合法音符不会失败。
    static func encode(quantize: Int, notes: [MidiNoteEvent]) -> Data {
        var timed: [TimedWriteEvent] = []
        timed.reserveCapacity(notes.count * 2)
        for note in notes {
            timed.append(
                TimedWriteEvent(
                    time: note.position,
                    event: .noteOn(channel: 0, nn: note.noteNum, velocity: note.velocity)
                )
            )
            timed.append(
                TimedWriteEvent(
                    time: note.position + note.gate,
                    event: .noteOff(channel: 0, nn: note.noteNum)
                )
            )
        }
        let track0 = encodeTrack([])
        let track1 = encodeTrack(timed)
        return wrapSmf(format: 1, ticks: quantize, tracks: [track0, track1])
    }

    private enum WriteEvent {
        case noteOn(channel: Int, nn: Int, velocity: Int)
        case noteOff(channel: Int, nn: Int)
        case endOfTrack
    }

    private struct TimedWriteEvent {
        var time: Int
        var event: WriteEvent
    }

    /// `EndOfTrack(-1)`：空轨写在时刻 0；非空写在最后一条事件的时刻。
    /// 先按时刻排音符，再把 EOT 接到该时刻后面，避免同刻排到 NoteOff 前面。
    private static func encodeTrack(_ events: [TimedWriteEvent]) -> [UInt8] {
        let ordered = events.enumerated().sorted { lhs, rhs in
            if lhs.element.time != rhs.element.time {
                return lhs.element.time < rhs.element.time
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let endTime = ordered.last?.time ?? 0
        let timed = ordered + [TimedWriteEvent(time: endTime, event: .endOfTrack)]
        var bytes: [UInt8] = []
        var lastTime = 0
        var status: UInt8 = 0
        for item in timed {
            appendVarInt(&bytes, item.time - lastTime)
            lastTime = item.time
            switch item.event {
            case .noteOn(let channel, let nn, let velocity):
                let next = UInt8(0x90 | (channel & 0x0F))
                if next != status {
                    bytes.append(next)
                    status = next
                }
                bytes.append(UInt8(nn & 0x7F))
                bytes.append(UInt8(velocity & 0x7F))
            case .noteOff(let channel, let nn):
                let next = UInt8(0x80 | (channel & 0x0F))
                if next != status {
                    bytes.append(next)
                    status = next
                }
                bytes.append(UInt8(nn & 0x7F))
                bytes.append(0)
            case .endOfTrack:
                bytes += [0xFF, 0x2F]
                appendVarInt(&bytes, 0)
                status = 0
            }
        }
        return bytes
    }

    private static func wrapSmf(format: Int, ticks: Int, tracks: [[UInt8]]) -> Data {
        var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64]
        appendU32(&bytes, 6)
        appendU16(&bytes, format)
        appendU16(&bytes, tracks.count)
        appendU16(&bytes, ticks)
        for track in tracks {
            bytes += [0x4D, 0x54, 0x72, 0x6B]
            appendU32(&bytes, track.count)
            bytes += track
        }
        return Data(bytes)
    }

    /// 对照 `SmfWriteVarInt`：低 7 位先拆，再倒序写出，最高位续行。
    private static func appendVarInt(_ dest: inout [UInt8], _ value: Int) {
        var chunks: [UInt8] = []
        var remaining = value & 0x0FFF_FFFF
        chunks.append(UInt8(remaining & 0x7F))
        remaining >>= 7
        while remaining != 0 {
            chunks.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        dest += chunks.reversed()
    }

    private static func appendU16(_ dest: inout [UInt8], _ value: Int) {
        dest.append(UInt8((value >> 8) & 0xFF))
        dest.append(UInt8(value & 0xFF))
    }

    private static func appendU32(_ dest: inout [UInt8], _ value: Int) {
        dest.append(UInt8((value >> 24) & 0xFF))
        dest.append(UInt8((value >> 16) & 0xFF))
        dest.append(UInt8((value >> 8) & 0xFF))
        dest.append(UInt8(value & 0xFF))
    }

    private static func parseThrowing(_ data: Data) throws -> BmhelperMidiFile {
        if data.isEmpty {
            throw BmhelperMidiError.emptyFile
        }
        var cursor = ByteCursor(bytes: Array(data))
        let magic = try cursor.ascii(4)
        guard magic == "MThd" else {
            throw BmhelperMidiError.invalidHeader
        }
        let headerSize = try cursor.u32be()
        guard headerSize == 6 else {
            throw BmhelperMidiError.invalidHeader
        }
        let format = try cursor.u16be()
        guard format == 0 || format == 1 else {
            throw BmhelperMidiError.unsupportedFormat
        }
        let trackCount = try cursor.u16be()
        let ticksPerQuarter = try cursor.u16be()
        var tracks: [BmhelperMidiTrack] = []
        tracks.reserveCapacity(trackCount)
        for index in 0..<trackCount {
            tracks.append(try readTrack(index: index, cursor: &cursor))
        }
        return BmhelperMidiFile(
            ticksPerQuarter: ticksPerQuarter,
            format: format,
            tracks: tracks
        )
    }

    private static func readTrack(index: Int, cursor: inout ByteCursor) throws -> BmhelperMidiTrack {
        let magic = try cursor.ascii(4)
        guard magic == "MTrk" else {
            throw BmhelperMidiError.invalidHeader
        }
        let size = try cursor.u32be()
        let end = cursor.offset + size
        guard end <= cursor.bytes.count else {
            throw BmhelperMidiError.truncated
        }

        var time = 0
        var status: UInt8 = 0
        var name = ""
        var channelsUsed = [Bool](repeating: false, count: 16)
        var notes: [BmhelperMidiNote] = []
        // 对照 `GetAllEvents`：按音符号配对，不按通道。后一次同音 note on 不覆盖。
        var keyboard: [Int: (position: Int, velocity: Int)] = [:]
        let previousLimit = cursor.limit
        cursor.limit = end

        while cursor.offset < end {
            time += try cursor.varint()
            let event = try readEvent(cursor: &cursor, status: &status)
            switch event {
            case .noteOn(_, let nn, let velocity):
                if keyboard[nn] == nil {
                    keyboard[nn] = (time, velocity)
                }
            case .noteOff(let channel, let nn):
                if let on = keyboard[nn] {
                    notes.append(
                        BmhelperMidiNote(
                            tick: on.position,
                            gate: time - on.position,
                            note: nn,
                            velocity: on.velocity,
                            channel: channel
                        )
                    )
                    if channel >= 0 && channel < 16 {
                        channelsUsed[channel] = true
                    }
                    keyboard.removeValue(forKey: nn)
                }
            case .trackName(let bytes):
                // 对照 PreLoader：每次 meta 0x03 插到现有名字前面。
                let piece = String(bytes: bytes, encoding: .isoLatin1) ?? ""
                name = piece + name
            case .skip:
                break
            }
        }
        cursor.limit = previousLimit
        cursor.offset = end
        return BmhelperMidiTrack(
            index: index,
            name: name,
            channelsUsed: channelsUsed,
            notes: notes
        )
    }

    private enum ParsedEvent {
        case noteOn(channel: Int, nn: Int, velocity: Int)
        case noteOff(channel: Int, nn: Int)
        case trackName([UInt8])
        case skip
    }

    private static func readEvent(
        cursor: inout ByteCursor,
        status: inout UInt8
    ) throws -> ParsedEvent {
        try cursor.require(1)
        let first = cursor.bytes[cursor.offset]
        if first & 0x80 != 0 {
            status = first
            cursor.offset += 1
        } else if status == 0 {
            throw BmhelperMidiError.truncated
        }
        let channel = Int(status & 0x0F)
        switch status & 0xF0 {
        case 0x80:
            let nn = Int(try cursor.u8())
            _ = try cursor.u8()
            return .noteOff(channel: channel, nn: nn)
        case 0x90:
            let nn = Int(try cursor.u8())
            let velocity = Int(try cursor.u8())
            if velocity == 0 {
                return .noteOff(channel: channel, nn: nn)
            }
            return .noteOn(channel: channel, nn: nn, velocity: velocity)
        case 0xA0, 0xB0, 0xE0:
            _ = try cursor.u8()
            _ = try cursor.u8()
            return .skip
        case 0xC0, 0xD0:
            _ = try cursor.u8()
            return .skip
        case 0xF0:
            switch channel {
            case 0x00, 0x07:
                // 系统独占：读完长度后丢掉。
                let size = try cursor.varint()
                _ = try cursor.take(size)
                status = 0
                return .skip
            case 0x0F:
                let type = try cursor.u8()
                let size = try cursor.varint()
                let payload = try cursor.take(size)
                status = 0
                if type == 0x03 {
                    return .trackName(payload)
                }
                return .skip
            default:
                throw BmhelperMidiError.truncated
            }
        default:
            throw BmhelperMidiError.truncated
        }
    }
}

/// 对照 `mdview.h` / `mdview.cpp` 的 `MidiView`。
/// 整数除法向零。算法客户区工作值是 `800 × 300`（主窗一半高，不是截图量出来的）。
enum BmhelperMidiView {
    static let zoomBase = 65536
    static let workingClientSize = CGSize(width: 800, height: 300)

    struct Size: Equatable {
        var width: Int
        var height: Int
    }

    struct Point: Equatable {
        var x: Int
        var y: Int
    }

    struct Rect: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int

        /// 对照 `wxRect::Contains`：左、上含，右、下不含。
        func contains(_ point: Point) -> Bool {
            point.x >= x
                && point.y >= y
                && (point.x - x) < width
                && (point.y - y) < height
        }
    }

    struct Metrics: Equatable {
        var maxTime: Int
        var minNn: Int
        var maxNn: Int
        var zoomRateX: Int
        var zoomRateY: Int
        var virtualWidth: Int
        var virtualHeight: Int
        var ypos: Int
        var hasData: Bool
        var notes: [MidiNoteEvent]
        var quantize: Int
    }

    private static let keyNames = [
        "C ", "C#", "D ", "D#", "E ", "F ", "F#", "G ", "G#", "A ", "A#", "B "
    ]

    /// `notes == nil` 对照 `SetMidiData(0)`。空数组对照有工程但没有音符。
    static func metrics(
        notes: [MidiNoteEvent]?,
        quantize: Int,
        client: Size = Size(
            width: Int(workingClientSize.width),
            height: Int(workingClientSize.height)
        )
    ) -> Metrics {
        let hasData = notes != nil
        let list = notes ?? []
        var maxTime = 0
        var rminNn = 127
        var rmaxNn = 0
        for note in list {
            let end = note.position + note.gate
            if end > maxTime {
                maxTime = end
            }
            if note.noteNum < rminNn {
                rminNn = note.noteNum
            }
            if note.noteNum > rmaxNn {
                rmaxNn = note.noteNum
            }
        }
        if rminNn > rmaxNn {
            rminNn = rmaxNn
        }
        if maxTime == 0 {
            maxTime = 1
        }
        let minNn = 0
        let maxNn = 127
        var zoomRateX = client.width * zoomBase / maxTime
        let zoomMin = zoomBase / 4
        let zoomMax = zoomBase * 2
        if zoomRateX > zoomMax {
            zoomRateX = zoomMax
        }
        if zoomRateX < zoomMin {
            zoomRateX = zoomMin
        }
        let zoomRateY = zoomBase * 8
        let virtualWidth = zoomRateX * maxTime / zoomBase
        let virtualHeight = zoomRateY * (maxNn - minNn + 1) / zoomBase
        let ypos = (maxNn - rmaxNn) * zoomRateY / zoomBase
            + ((rmaxNn - rminNn + 1) * zoomRateY / zoomBase - client.height) / 2
        return Metrics(
            maxTime: maxTime,
            minNn: minNn,
            maxNn: maxNn,
            zoomRateX: zoomRateX,
            zoomRateY: zoomRateY,
            virtualWidth: virtualWidth,
            virtualHeight: virtualHeight,
            ypos: ypos,
            hasData: hasData,
            notes: list,
            quantize: max(quantize, 1)
        )
    }

    static func noteRect(note: MidiNoteEvent, metrics: Metrics, scroll: Point) -> Rect {
        var rect = Rect(
            x: metrics.zoomRateX * note.position / zoomBase,
            y: metrics.zoomRateY * (metrics.maxNn - note.noteNum) / zoomBase,
            width: 0,
            height: 0
        )
        rect.width = metrics.zoomRateX * (note.position + note.gate) / zoomBase - rect.x
        rect.height = metrics.zoomRateY * (metrics.maxNn - note.noteNum + 1) / zoomBase - rect.y
        rect.x -= scroll.x
        rect.y -= scroll.y
        return rect
    }

    /// 对照 `get_note_num_string`。MIDI 60 是 `C  5`，不要改成 C4。
    static func noteName(_ noteNum: Int) -> String {
        let octv = noteNum / 12
        var key = noteNum % 12
        if key < 0 {
            key += 12
        }
        return String(format: "%@ %d", keyNames[key], octv)
    }

    /// 对照 `NoteFromPoint`。按数组顺序，第一个包含该点的矩形。没有则 `nil`。
    static func noteIndex(at point: Point, metrics: Metrics, scroll: Point) -> Int? {
        guard metrics.hasData else { return nil }
        for (index, note) in metrics.notes.enumerated() {
            if noteRect(note: note, metrics: metrics, scroll: scroll).contains(point) {
                return index
            }
        }
        return nil
    }

    /// 对照 `OnMouseMotion`。没点中或没有 data 则空串。
    static func hoverText(at point: Point, metrics: Metrics, scroll: Point) -> String {
        guard let index = noteIndex(at: point, metrics: metrics, scroll: scroll) else {
            return ""
        }
        let note = metrics.notes[index]
        return String(
            format: "Note#%d ( %@ ) gate:%d/%d vel:%d",
            index,
            noteName(note.noteNum),
            note.gate,
            metrics.quantize,
            note.velocity
        )
    }

    /// 对照 `divedit.cpp` 的 `SetDivision`：有选中则 `SetMidiData(division)`，没有则 `nullptr`。
    /// 画的是 Division 时间线，不是源 MIDI。`source` 只作对照，不进第二份钢琴卷。
    static func notesToShow(
        source _: [MidiNoteEvent],
        timeline: [MidiNoteEvent],
        hasSelection: Bool
    ) -> [MidiNoteEvent]? {
        hasSelection ? timeline : nil
    }

    /// 对照 `OnMouseWheel`：横缩放 `zoom_rate.x`。整数除法向零。
    static func zoomHorizontal(rate: Int, up: Bool) -> Int {
        var x = rate
        if up {
            x = x * 4 / 3
            if x > zoomBase * 2 {
                x = zoomBase * 2
            }
        } else {
            x = x * 3 / 4
            if x < zoomBase / 4 {
                x = zoomBase / 4
            }
        }
        return x
    }

    /// 对照 `OnMouseWheel`：竖缩放 `zoom_rate.y`。整数除法向零。
    static func zoomVertical(rate: Int, up: Bool) -> Int {
        var y = rate
        if up {
            y = y * 4 / 3
            if y > zoomBase * 32 {
                y = zoomBase * 32
            }
        } else {
            y = y * 3 / 4
            if y < zoomBase {
                y = zoomBase
            }
        }
        return y
    }

    /// 对照 `OnMouseWheel` 滚动步长。向上为负。整数除法向零。
    static func scrollStep(horizontal: Bool, zoomRate: Int, quantize: Int, up: Bool) -> Int {
        let amount = horizontal
            ? zoomRate * quantize / zoomBase
            : zoomRate / zoomBase
        return up ? -amount : amount
    }

    /// 对照 `mdview.cpp` `OnMouseWheel`。`command` 对照 `ControlDown`，`shift` 对照 `ShiftDown`。
    /// `up` 对照 `GetWheelRotation()>0`。没有 data 不改缩放、不改滚动。
    static func applyWheel(
        metrics: Metrics,
        scroll: Point,
        client: Size,
        command: Bool,
        shift: Bool,
        up: Bool
    ) -> (metrics: Metrics, scroll: Point) {
        guard metrics.hasData else {
            return (metrics, scroll)
        }
        var next = metrics
        var px = scroll.x
        var py = scroll.y
        if command {
            if shift {
                let oldX = next.zoomRateX
                next.zoomRateX = zoomHorizontal(rate: oldX, up: up)
                px = recenter(px, oldRate: oldX, newRate: next.zoomRateX, client: client.width)
            } else {
                let oldY = next.zoomRateY
                next.zoomRateY = zoomVertical(rate: oldY, up: up)
                py = recenter(py, oldRate: oldY, newRate: next.zoomRateY, client: client.height)
            }
            next.virtualWidth = next.zoomRateX * next.maxTime / zoomBase
            next.virtualHeight = next.zoomRateY * (next.maxNn - next.minNn + 1) / zoomBase
        } else if shift {
            if client.width < next.virtualWidth {
                px += scrollStep(
                    horizontal: true,
                    zoomRate: next.zoomRateX,
                    quantize: next.quantize,
                    up: up
                )
            }
        } else if client.height < next.virtualHeight {
            py += scrollStep(
                horizontal: false,
                zoomRate: next.zoomRateY,
                quantize: next.quantize,
                up: up
            )
        }
        return (
            next,
            Point(
                x: clampScroll(px, virtual: next.virtualWidth, client: client.width),
                y: clampScroll(py, virtual: next.virtualHeight, client: client.height)
            )
        )
    }

    /// 对照原文 `(int)((px + cls/2.0) * new / old) - cls/2`。先用 double，再转 int。
    private static func recenter(_ position: Int, oldRate: Int, newRate: Int, client: Int) -> Int {
        Int((Double(position) + Double(client) / 2.0) * Double(newRate) / Double(oldRate))
            - client / 2
    }

    /// 按 macOS 工作规则夹到 `[0, max(vs-cls, 0)]`。
    private static func clampScroll(_ value: Int, virtual: Int, client: Int) -> Int {
        let maxPos = max(virtual - client, 0)
        return min(max(value, 0), maxPos)
    }
}

private struct ByteCursor {
    let bytes: [UInt8]
    var offset: Int = 0
    var limit: Int

    init(bytes: [UInt8]) {
        self.bytes = bytes
        self.limit = bytes.count
    }

    var remaining: Int { limit - offset }

    mutating func require(_ count: Int) throws {
        if count < 0 || offset < 0 || remaining < count || offset + count > bytes.count {
            throw BmhelperMidiError.truncated
        }
    }

    mutating func u8() throws -> UInt8 {
        try require(1)
        let value = bytes[offset]
        offset += 1
        return value
    }

    mutating func u16be() throws -> Int {
        let high = Int(try u8())
        let low = Int(try u8())
        return (high << 8) | low
    }

    mutating func u32be() throws -> Int {
        let b0 = Int(try u8())
        let b1 = Int(try u8())
        let b2 = Int(try u8())
        let b3 = Int(try u8())
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    mutating func ascii(_ count: Int) throws -> String {
        let slice = try take(count)
        return String(bytes: slice, encoding: .ascii) ?? ""
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        try require(count)
        let slice = Array(bytes[offset..<(offset + count)])
        offset += count
        return slice
    }

    /// 对照 `SmfReadVarInt`：最多收到约 28 位。
    mutating func varint() throws -> Int {
        var value = 0
        var byte: UInt8
        repeat {
            byte = try u8()
            value = (value << 7) | Int(byte & 0x7F)
        } while (byte & 0x80) != 0 && (value & 0x0FE0_0000) == 0
        return value
    }
}
