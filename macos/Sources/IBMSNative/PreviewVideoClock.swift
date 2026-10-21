import CoreGraphics
import Foundation

/// WMV/ASF 时钟。位置只跟调用方给出的媒体秒，后台线程解码，不建定时器，不碰 MainActor。
@MainActor
final class PreviewVideoClock {
    private let box = PreviewVideoHandle()
    private(set) var stats = PreviewVideoStats.empty
    private(set) var image: CGImage?
    private var imageKey = ""

    static func usesNativeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "wmv" || ext == "asf" {
            return true
        }
        if ext == "mp4" || ext == "m4v" || ext == "mov" {
            return false
        }
        return fileStartsWithASF(url)
    }

    var attached: Bool { box.isOpen }
    var presentedPTS: Double? { stats.pts }
    var outputRate: Float { Float(stats.outputRate) }
    var silenced: Bool { attached }

    func open(url: URL, generation: UInt64) {
        close()
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return }
            box.open(pointer, generation: generation)
        }
        stats = .empty
        stats.generation = generation
        image = nil
        imageKey = ""
    }

    func command(mediaSeconds: Double, rate: Double, playing: Bool, generation: UInt64) {
        guard box.isOpen else { return }
        let media = mediaSeconds.isFinite ? max(0, mediaSeconds) : 0
        let playback = rate.isFinite ? max(0, rate) : 0
        box.command(media: media, rate: playback, playing: playing, generation: generation)
        stats.outputRate = playing ? playback : 0
        stats.generation = generation
    }

    /// 播放或暂停命令只在目标速率变化时记一次。
    func noteTransport(playing: Bool, rate: Double) -> Bool {
        let desired = Float(playing ? rate : 0)
        if box.lastTransport == desired {
            return false
        }
        box.lastTransport = desired
        return true
    }

    func retire(generation: UInt64) {
        guard box.isOpen else { return }
        box.retire(generation)
        image = nil
        imageKey = ""
        stats.generation = generation
        stats.frameSerial &+= 1
    }

    func poll(blackKey: Bool, threshold: UInt8) {
        guard box.isOpen else { return }
        let snapshot = box.readStats()
        stats = snapshot
        guard snapshot.valid, snapshot.width > 0, snapshot.height > 0, snapshot.stride >= snapshot.width * 4 else { return }
        let key = "\(snapshot.generation)|\(snapshot.frameSerial)|\(blackKey ? 1 : 0)|\(threshold)"
        guard key != imageKey else { return }
        let byteCount = snapshot.stride * snapshot.height
        guard byteCount > 0, byteCount <= 16 * 1024 * 1024 else {
            stats.failed = true
            stats.error = "frame exceeds memory budget"
            return
        }
        let copied = box.copyFrame(generation: snapshot.generation, byteCount: byteCount)
        stats = copied.stats
        guard copied.code == 0, var pixels = copied.pixels else {
            if !stats.valid {
                image = nil
                imageKey = ""
            }
            return
        }
        if blackKey {
            PreviewVideoPunch.apply(&pixels, threshold: threshold)
        }
        guard let image = PreviewVideoImage.makeBGRA(pixels, width: stats.width, height: stats.height, stride: stats.stride) else {
            return
        }
        self.image = image
        imageKey = "\(stats.generation)|\(stats.frameSerial)|\(blackKey ? 1 : 0)|\(threshold)"
    }

    func close() {
        box.close()
        image = nil
        imageKey = ""
    }

    static var inflight: Int { Int(ibms_preview_video_inflight()) }

    static var inflightLimit: Int { Int(ibms_preview_video_inflight_limit()) }

    static func debugArmWorkerFault() {
        ibms_preview_video_debug_arm_worker_fault()
    }

    static func linkedDecoders() -> (video: Int, audio: Int, names: String) {
        var video: Int32 = 0
        var audio: Int32 = 0
        var names = [CChar](repeating: 0, count: 256)
        names.withUnsafeMutableBufferPointer { buffer in
            ibms_preview_video_decoder_inventory(buffer.baseAddress, 256, &video, &audio)
        }
        let text = names.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
        return (Int(video), Int(audio), text)
    }

    private static func fileStartsWithASF(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16), data.count == 16 else { return false }
        let magic: [UInt8] = [
            0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11,
            0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C
        ]
        return Array(data) == magic
    }
}

struct PreviewVideoStats: Equatable {
    var probed = false
    var failed = false
    var valid = false
    var width = 0
    var height = 0
    var stride = 0
    var originalWidth = 0
    var originalHeight = 0
    var audioStreams = 0
    var audioDecodedPackets = 0
    var audioDiscardedPackets = 0
    var seekCount = 0
    var decodedFrames = 0
    var droppedStale = 0
    var hasLastSeek = false
    var pts: Double?
    var duration = 0.0
    var lastSeekSeconds = 0.0
    var outputRate = 0.0
    /// 已发布的那张 BGRA。不是进程 RSS，也不含解码参考帧、包、swscale 或 Swift 副本。
    var residentBytes = 0
    var peakResidentBytes = 0
    var copyCount = 0
    var generation: UInt64 = 0
    var frameSerial: UInt64 = 0
    var codec = ""
    var format = ""
    var error = ""

    static let empty = PreviewVideoStats()
}

enum PreviewVideoPunch {
    static func apply(_ bytes: inout [UInt8], threshold: UInt8) {
        bytes.withUnsafeMutableBytes { raw in
            guard let start = raw.baseAddress else { return }
            let count = raw.count & ~3
            guard count >= 4 else { return }
            if Int(bitPattern: start) & 3 == 0 {
                var offset = 0
                while offset < count {
                    let pixel = start.load(fromByteOffset: offset, as: UInt32.self)
                    let blue = UInt8(truncatingIfNeeded: pixel)
                    let green = UInt8(truncatingIfNeeded: pixel >> 8)
                    let red = UInt8(truncatingIfNeeded: pixel >> 16)
                    if red <= threshold, green <= threshold, blue <= threshold {
                        start.storeBytes(of: UInt32(0), toByteOffset: offset, as: UInt32.self)
                    }
                    offset += 4
                }
                return
            }
            let pixels = start.assumingMemoryBound(to: UInt8.self)
            var index = 0
            while index < count {
                let blue = pixels[index]
                let green = pixels[index + 1]
                let red = pixels[index + 2]
                if red <= threshold, green <= threshold, blue <= threshold {
                    pixels[index] = 0
                    pixels[index + 1] = 0
                    pixels[index + 2] = 0
                    pixels[index + 3] = 0
                }
                index += 4
            }
        }
    }
}

enum PreviewVideoImage {
    static func makeBGRA(_ bytes: [UInt8], width: Int, height: Int, stride: Int) -> CGImage? {
        guard width > 0, height > 0, stride >= width * 4, bytes.count >= stride * height else { return nil }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

struct PreviewNativeVideoPicture {
    var image: CGImage
    var pts: Double
    var hostFrame: CGRect
    var imageFrame: CGRect
    var originalWidth: Int
    var originalHeight: Int
}

private struct PreviewVideoCopy {
    var code: Int32
    var stats: PreviewVideoStats
    var pixels: [UInt8]?
}

private final class PreviewVideoHandle: @unchecked Sendable {
    fileprivate static let intCount = 16
    fileprivate static let doubleCount = 8
    private var raw: OpaquePointer?
    private var pendingPath: String?
    private var pendingGeneration: UInt64 = 0
    private var pendingCommand: (media: Double, rate: Double, playing: Bool, generation: UInt64)?
    var lastTransport: Float = -1

    var isOpen: Bool { raw != nil || pendingPath != nil }

    func open(_ path: UnsafePointer<CChar>, generation: UInt64) {
        close()
        lastTransport = -1
        if let opened = ibms_preview_video_open(path, generation) {
            raw = opened
            return
        }
        pendingPath = String(cString: path)
        pendingGeneration = generation
        pendingCommand = nil
    }

    func command(media: Double, rate: Double, playing: Bool, generation: UInt64) {
        if raw == nil, pendingPath != nil {
            pendingCommand = (media, rate, playing, generation)
            servicePending()
            return
        }
        guard let raw else { return }
        ibms_preview_video_command(raw, media, rate, playing ? 1 : 0, generation)
    }

    func retire(_ generation: UInt64) {
        guard let raw else { return }
        ibms_preview_video_set_generation(raw, generation)
    }

    func readStats() -> PreviewVideoStats {
        servicePending()
        guard let raw else { return .empty }
        var intCount: Int32 = 0
        var doubleCount: Int32 = 0
        ibms_preview_video_layout(&intCount, &doubleCount)
        guard intCount == Int32(Self.intCount), doubleCount == Int32(Self.doubleCount) else {
            var stats = PreviewVideoStats.empty
            stats.failed = true
            stats.error = "stat layout mismatch"
            return stats
        }
        var ints = [Int64](repeating: 0, count: Self.intCount)
        var doubles = [Double](repeating: 0, count: Self.doubleCount)
        var codec = [CChar](repeating: 0, count: 32)
        var format = [CChar](repeating: 0, count: 32)
        var error = [CChar](repeating: 0, count: 160)
        Self.read(raw, ints: &ints, doubles: &doubles, codec: &codec, format: &format, error: &error)
        return Self.stats(ints: ints, doubles: doubles, codec: codec, format: format, error: error)
    }

    func copyFrame(generation: UInt64, byteCount: Int) -> PreviewVideoCopy {
        servicePending()
        guard let raw else { return PreviewVideoCopy(code: -1, stats: .empty, pixels: nil) }
        var pixels = [UInt8](repeating: 0, count: byteCount)
        var ints = [Int64](repeating: 0, count: Self.intCount)
        var doubles = [Double](repeating: 0, count: Self.doubleCount)
        var codec = [CChar](repeating: 0, count: 32)
        var format = [CChar](repeating: 0, count: 32)
        var error = [CChar](repeating: 0, count: 160)
        let copied = pixels.withUnsafeMutableBufferPointer { pixelPointer in
            ints.withUnsafeMutableBufferPointer { intPointer in
                doubles.withUnsafeMutableBufferPointer { doublePointer in
                    codec.withUnsafeMutableBufferPointer { codecPointer in
                        format.withUnsafeMutableBufferPointer { formatPointer in
                            error.withUnsafeMutableBufferPointer { errorPointer in
                                ibms_preview_video_copy(
                                    raw,
                                    generation,
                                    pixelPointer.baseAddress,
                                    Int32(byteCount),
                                    intPointer.baseAddress,
                                    doublePointer.baseAddress,
                                    codecPointer.baseAddress,
                                    32,
                                    formatPointer.baseAddress,
                                    32,
                                    errorPointer.baseAddress,
                                    160
                                )
                            }
                        }
                    }
                }
            }
        }
        var stats = Self.stats(ints: ints, doubles: doubles, codec: codec, format: format, error: error)
        if copied == 2 {
            stats.failed = true
            stats.error = "frame copy was short"
            return PreviewVideoCopy(code: copied, stats: stats, pixels: nil)
        }
        if copied != 0 {
            stats.valid = false
            return PreviewVideoCopy(code: copied, stats: stats, pixels: nil)
        }
        return PreviewVideoCopy(code: 0, stats: stats, pixels: pixels)
    }

    func close() {
        pendingPath = nil
        pendingCommand = nil
        guard let raw else { return }
        self.raw = nil
        lastTransport = -1
        ibms_preview_video_close(raw)
    }

    private func servicePending() {
        guard raw == nil, let path = pendingPath else { return }
        path.withCString { pointer in
            guard let opened = ibms_preview_video_open(pointer, pendingGeneration) else { return }
            raw = opened
            pendingPath = nil
            if let pending = pendingCommand {
                pendingCommand = nil
                ibms_preview_video_command(opened, pending.media, pending.rate, pending.playing ? 1 : 0, pending.generation)
            }
        }
    }

    deinit { close() }

    private static func stats(
        ints: [Int64],
        doubles: [Double],
        codec: [CChar],
        format: [CChar],
        error: [CChar]
    ) -> PreviewVideoStats {
        var stats = PreviewVideoStats.empty
        stats.probed = ints[0] != 0
        stats.failed = ints[1] != 0
        stats.width = Int(ints[2])
        stats.height = Int(ints[3])
        stats.stride = Int(ints[4])
        stats.originalWidth = Int(ints[5])
        stats.originalHeight = Int(ints[6])
        stats.audioStreams = Int(ints[7])
        stats.audioDecodedPackets = Int(ints[8])
        stats.audioDiscardedPackets = Int(ints[9])
        stats.seekCount = Int(ints[10])
        stats.decodedFrames = Int(ints[11])
        stats.droppedStale = Int(ints[12])
        stats.valid = ints[13] != 0
        stats.hasLastSeek = ints[14] != 0
        stats.pts = ints[13] != 0 ? doubles[0] : nil
        stats.duration = doubles[1]
        stats.lastSeekSeconds = doubles[2]
        stats.outputRate = doubles[3]
        stats.residentBytes = Int(doubles[4])
        stats.peakResidentBytes = Int(doubles[5])
        stats.copyCount = ints.count > 15 ? Int(ints[15]) : 0
        stats.generation = UInt64(max(0, doubles[6]))
        stats.frameSerial = UInt64(max(0, doubles[7]))
        stats.codec = Self.text(codec)
        stats.format = Self.text(format)
        stats.error = Self.text(error)
        return stats
    }

    private static func read(
        _ raw: OpaquePointer,
        ints: inout [Int64],
        doubles: inout [Double],
        codec: inout [CChar],
        format: inout [CChar],
        error: inout [CChar]
    ) {
        ints.withUnsafeMutableBufferPointer { intPointer in
            doubles.withUnsafeMutableBufferPointer { doublePointer in
                codec.withUnsafeMutableBufferPointer { codecPointer in
                    format.withUnsafeMutableBufferPointer { formatPointer in
                        error.withUnsafeMutableBufferPointer { errorPointer in
                            ibms_preview_video_read_stats(
                                raw,
                                intPointer.baseAddress,
                                doublePointer.baseAddress,
                                codecPointer.baseAddress,
                                32,
                                formatPointer.baseAddress,
                                32,
                                errorPointer.baseAddress,
                                160
                            )
                        }
                    }
                }
            }
        }
    }

    private static func text(_ bytes: [CChar]) -> String {
        bytes.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
    }
}

@_silgen_name("ibms_preview_video_layout")
private func ibms_preview_video_layout(_ intCount: UnsafeMutablePointer<Int32>?, _ doubleCount: UnsafeMutablePointer<Int32>?)

@_silgen_name("ibms_preview_video_inflight")
private func ibms_preview_video_inflight() -> Int32

@_silgen_name("ibms_preview_video_inflight_limit")
private func ibms_preview_video_inflight_limit() -> Int32

@_silgen_name("ibms_preview_video_decoder_inventory")
private func ibms_preview_video_decoder_inventory(
    _ names: UnsafeMutablePointer<CChar>?,
    _ cap: Int32,
    _ videoCount: UnsafeMutablePointer<Int32>?,
    _ audioCount: UnsafeMutablePointer<Int32>?
)

@_silgen_name("ibms_preview_video_open")
private func ibms_preview_video_open(_ path: UnsafePointer<CChar>, _ generation: UInt64) -> OpaquePointer?

@_silgen_name("ibms_preview_video_command")
private func ibms_preview_video_command(
    _ video: OpaquePointer?,
    _ media: Double,
    _ rate: Double,
    _ playing: Int32,
    _ generation: UInt64
)

@_silgen_name("ibms_preview_video_set_generation")
private func ibms_preview_video_set_generation(_ video: OpaquePointer?, _ generation: UInt64)

@_silgen_name("ibms_preview_video_read_stats")
private func ibms_preview_video_read_stats(
    _ video: OpaquePointer?,
    _ ints: UnsafeMutablePointer<Int64>?,
    _ doubles: UnsafeMutablePointer<Double>?,
    _ codec: UnsafeMutablePointer<CChar>?,
    _ codecCap: Int32,
    _ format: UnsafeMutablePointer<CChar>?,
    _ formatCap: Int32,
    _ error: UnsafeMutablePointer<CChar>?,
    _ errorCap: Int32
)

@_silgen_name("ibms_preview_video_copy")
private func ibms_preview_video_copy(
    _ video: OpaquePointer?,
    _ generation: UInt64,
    _ dst: UnsafeMutablePointer<UInt8>?,
    _ dstBytes: Int32,
    _ ints: UnsafeMutablePointer<Int64>?,
    _ doubles: UnsafeMutablePointer<Double>?,
    _ codec: UnsafeMutablePointer<CChar>?,
    _ codecCap: Int32,
    _ format: UnsafeMutablePointer<CChar>?,
    _ formatCap: Int32,
    _ error: UnsafeMutablePointer<CChar>?,
    _ errorCap: Int32
) -> Int32

@_silgen_name("ibms_preview_video_debug_arm_worker_fault")
private func ibms_preview_video_debug_arm_worker_fault()

@_silgen_name("ibms_preview_video_close")
private func ibms_preview_video_close(_ video: OpaquePointer?)
