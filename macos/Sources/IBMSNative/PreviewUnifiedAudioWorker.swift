import AVFoundation
import Foundation

struct PreviewUnifiedAsset: Sendable {
    var key: String
    var sampleRate: Double
    var channels: Int
    var frameCount: Int
    var planar: Data?
    var fileURL: URL?
    var temporary: Bool
    var sourceBytes: Int
}

struct PreviewUnifiedCue: Sendable {
    var seconds: Double
    var key: String?
    var kind: PreviewAudioKind
    var fileOffset: Double
    var duration: Double
}

struct PreviewUnifiedStats: Sendable {
    var scheduled = 0
    var stolen = 0
    var dropped = 0
    var voiceSlots = 0
    var residentBytes = 0
    var residentResources = 0
    var fileBacked = 0
    var inflightBytes = 0
    var streamBlockBytes = 0
    var pcmCopies = 0
    var late = 0
    var cueTouchesLast = 0
    var cueTouchesMax = 0
    var cueTouchesTotal = 0
    var scheduleStops = 0
    var activeVoices = 0
    var voiceStarts: [Double] = []
    var overloadSamples = 0
    var inputUsed = 0
    var maxScheduleSeconds = 0.0
    var clockSource = "adapter"
    var ioFailed = false
}

struct PreviewUnifiedJob: Sendable {
    var generation: UInt = 0
    var assets: [PreviewUnifiedAsset] = []
    var cues: [PreviewUnifiedCue] = []
    var rate: Double = 1
    var paused = false
    var stopped = false
    var seekSerial: UInt = 0
    var seekChart = 0.0
    var audible: Set<PreviewAudioKind> = [.bgm, .key]
    var voiceSlots = 1
    var budget = PreviewAudioLimits.maxCachedBytes
    var record = false
    var silent = false
    var quit = false
    var traceOpen: (@Sendable (Bool) -> Void)?
    var traceDisk: (@Sendable (Bool) -> Void)?
}

/// 后台串行混音。cue 索引、页缓存和 libsamplerate 都在这条队列上。
final class PreviewUnifiedAudioWorker: @unchecked Sendable {
    let mailbox = PreviewAudioMailbox()
    let pointers = PreviewAudioPointers()
    let queue = DispatchQueue(label: "ibms.preview.unified.worker")
    private var started = false
    private let startedLock = NSLock()

    func ensureStarted() {
        startedLock.lock()
        let needs = !started
        started = true
        startedLock.unlock()
        if needs {
            queue.async { [self] in
                self.loop()
            }
        }
    }

    func shutdown() {
        mailbox.lock.lock()
        mailbox.job.quit = true
        mailbox.lock.unlock()
        mailbox.wake()
    }

    private func loop() {
        let bridge = PreviewAudioBridge()
        guard bridge.open() else {
            mailbox.fail(generation: 0, reason: "bridge")
            return
        }
        pointers.publish(bridge)
        mailbox.markBooted()
        var state = PreviewWorkerState(bridge: bridge)
        while !state.quit {
            let job = mailbox.snapshot()
            if job.quit {
                state.quit = true
                break
            }
            if job.generation != state.generation {
                state.install(job, mailbox: mailbox)
            }
            state.apply(job, mailbox: mailbox)
            if !state.produce(job, mailbox: mailbox) {
                // 播放中不用信号量，避免历史 signal 被 0ms 吃掉后打满 CPU。
                // 排空后再读一次任务：排空期间到来的 wake 不能被 50ms 等待吞掉。
                let idle = job.generation == state.generation
                    && (job.generation == 0
                        || job.stopped
                        || (!state.awaitingOrigin && state.readySent && (!mailbox.isArmed() || job.paused)))
                if idle {
                    while mailbox.semaphore.wait(timeout: .now()) == .success {}
                    let latest = mailbox.snapshot()
                    let stillIdle = !latest.quit
                        && latest.generation == job.generation
                        && latest.stopped == job.stopped
                        && latest.paused == job.paused
                        && latest.seekSerial == job.seekSerial
                        && (latest.generation == 0 || latest.stopped || !mailbox.isArmed() || latest.paused)
                    if stillIdle {
                        _ = mailbox.semaphore.wait(timeout: .now() + .milliseconds(50))
                    }
                } else {
                    usleep(2_000)
                }
            }
        }
        bridge.beginRetire()
        if let lease = bridge.lease {
            ibms_preview_render_lease_request_retire(lease)
        }
        // 卸下别名。对象留在 lease 里，由非 RT 的 try_release 销毁一次。
        bridge.mixer = nil
        pointers.clear()
        if let lease = bridge.lease {
            PreviewAudioRetirementOwner.shared.take(lease)
            bridge.lease = nil
        }
        mailbox.markExited()
    }
}

final class PreviewAudioMailbox: @unchecked Sendable {
    let lock = NSLock()
    var job = PreviewUnifiedJob()
    var stats = PreviewUnifiedStats()
    var failure: String?
    var readyGeneration: UInt = .max
    var failedGeneration: UInt = .max
    var installedGeneration: UInt = .max
    var booted = false
    var exited = false
    var armed = false
    var onReady: (@Sendable (UInt) -> Void)?
    var onFailed: (@Sendable (UInt, String) -> Void)?
    var onBooted: (@Sendable () -> Void)?
    /// poll 见到 desired 与 ack 一致后才写下。ack 前 acked 为 false，Session 只能报 0。
    var clockGeneration: UInt = 0
    var originEpoch: UInt64 = 0
    var acceptedEpoch: UInt64 = 0
    var clockAcked = false
    let semaphore = DispatchSemaphore(value: 0)

    func wake() { semaphore.signal() }

    func snapshot() -> PreviewUnifiedJob {
        lock.lock()
        let copy = job
        lock.unlock()
        return copy
    }

    func updateStats(_ body: (inout PreviewUnifiedStats) -> Void) {
        lock.lock()
        body(&stats)
        lock.unlock()
    }

    func statsCopy() -> PreviewUnifiedStats {
        lock.lock()
        let copy = stats
        lock.unlock()
        return copy
    }

    func fail(generation: UInt, reason: String) {
        lock.lock()
        failure = reason
        failedGeneration = generation
        let handler = onFailed
        lock.unlock()
        wake()
        handler?(generation, reason)
    }

    func readFailedGeneration() -> UInt {
        lock.lock()
        let value = failedGeneration
        lock.unlock()
        return value
    }

    func noteInstalled(_ generation: UInt) {
        lock.lock()
        installedGeneration = generation
        lock.unlock()
    }

    func installedGenerationCopy() -> UInt {
        lock.lock()
        let value = installedGeneration
        lock.unlock()
        return value
    }

    func markReady(_ generation: UInt) {
        lock.lock()
        readyGeneration = generation
        let handler = onReady
        lock.unlock()
        wake()
        handler?(generation)
    }

    func setArmed(_ value: Bool) {
        lock.lock()
        armed = value
        lock.unlock()
        wake()
    }

    func isArmed() -> Bool {
        lock.lock()
        let value = armed
        lock.unlock()
        return value
    }

    func markBooted() {
        lock.lock()
        booted = true
        let handler = onBooted
        lock.unlock()
        wake()
        handler?()
    }

    func markExited() {
        lock.lock()
        exited = true
        lock.unlock()
        wake()
    }

    /// 调用方已持有 lock。新 generation 立刻进入等待，旧 epoch 不再有效。
    func beginClockGenerationLocked(_ generation: UInt) {
        clockGeneration = generation
        originEpoch = 0
        acceptedEpoch = 0
        clockAcked = false
    }

    /// 调用方已持有 lock。同代 seek 丢掉当前 origin，下一次新 epoch 才重新有效。
    func invalidateClockOriginLocked() {
        originEpoch = 0
        acceptedEpoch = 0
        clockAcked = false
    }

    /// desired/ack 已经一致。新 origin 收紧下界；同代后续 epoch（rate）只抬高上界。
    func noteClock(generation: UInt, epoch: UInt64, newOrigin: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == clockGeneration, generation != 0, epoch != 0 else { return }
        if !clockAcked {
            guard newOrigin else { return }
            originEpoch = epoch
            acceptedEpoch = epoch
            clockAcked = true
            return
        }
        if newOrigin {
            originEpoch = epoch
            acceptedEpoch = epoch
            return
        }
        if epoch > acceptedEpoch {
            acceptedEpoch = epoch
        }
    }

    func clockProof() -> (generation: UInt, originEpoch: UInt64, acceptedEpoch: UInt64, acked: Bool) {
        lock.lock()
        let proof = (clockGeneration, originEpoch, acceptedEpoch, clockAcked)
        lock.unlock()
        return proof
    }

    func waitUntil(_ predicate: () -> Bool, timeout: Double) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= end { return predicate() }
            _ = semaphore.wait(timeout: .now() + 0.01)
        }
        return true
    }
}

final class PreviewAudioPointers: @unchecked Sendable {
    let lock = NSLock()
    var lease: OpaquePointer?

    func publish(_ bridge: PreviewAudioBridge) {
        lock.lock()
        lease = bridge.lease
        lock.unlock()
    }

    func clear() {
        lock.lock()
        lease = nil
        lock.unlock()
    }

    /// query 计数覆盖整个读取。退休线程看到计数非 0 就不能 release。
    /// 闭包结果本身可以是可选值；没有 lease 和闭包返回 nil 都是同一层 T?。
    func withQuery<T>(_ body: (OpaquePointer) -> T?) -> T? {
        lock.lock()
        guard let lease, ibms_preview_render_lease_query_begin(lease) != 0 else {
            lock.unlock()
            return nil
        }
        let held = lease
        lock.unlock()
        defer { ibms_preview_render_lease_query_end(held) }
        return body(held)
    }
}

final class PreviewAudioBridge: @unchecked Sendable {
    var context: OpaquePointer?
    var registration: OpaquePointer?
    var reader: OpaquePointer?
    var slot: OpaquePointer?
    var mixer: OpaquePointer?
    var lease: OpaquePointer?
    let blockFrames = 256

    func open() -> Bool {
        var config = IBMSPreviewMixConfig()
        ibms_preview_mix_config_init(&config)
        config.capacityFrames = 2048
        config.blockFrames = UInt32(blockFrames)
        guard let context = ibms_preview_mix_create(&config) else { return false }
        guard ibms_preview_mix_prepare(context, 1, 0) == IBMS_PREVIEW_MIX_OK else {
            ibms_preview_mix_begin_retire(context)
            ibms_preview_mix_note_worker_exited(context)
            ibms_preview_mix_close_queries(context)
            _ = ibms_preview_mix_context_release(context)
            return false
        }
        guard let registration = ibms_preview_mix_registration_retain(context) else {
            releaseFresh(context: context, registration: nil, reader: nil, slot: nil, mixer: nil)
            return false
        }
        guard let reader = ibms_preview_mix_reader_retain(context) else {
            releaseFresh(context: context, registration: registration, reader: nil, slot: nil, mixer: nil)
            return false
        }
        guard let slot = ibms_preview_render_slot_create(48_000 * 20) else {
            releaseFresh(context: context, registration: registration, reader: reader, slot: nil, mixer: nil)
            return false
        }
        guard let mixer = ibms_preview_grouped_create() else {
            releaseFresh(context: context, registration: registration, reader: reader, slot: slot, mixer: nil)
            return false
        }
        guard let lease = ibms_preview_render_lease_create(
            slot,
            registration,
            UnsafeMutableRawPointer(context),
            UnsafeMutableRawPointer(reader),
            mixer
        ) else {
            releaseFresh(context: context, registration: registration, reader: reader, slot: slot, mixer: mixer)
            return false
        }
        // lease 从这里起拥有 mixer。self.mixer 只是同一只对象的别名。
        self.context = context
        self.registration = registration
        self.reader = reader
        self.slot = slot
        self.mixer = mixer
        self.lease = lease
        return true
    }

    private func releaseFresh(
        context: OpaquePointer,
        registration: OpaquePointer?,
        reader: OpaquePointer?,
        slot: OpaquePointer?,
        mixer: OpaquePointer?
    ) {
        ibms_preview_mix_begin_retire(context)
        ibms_preview_mix_note_worker_exited(context)
        ibms_preview_mix_close_queries(context)
        if let reader { ibms_preview_mix_reader_release(reader) }
        if let registration { ibms_preview_mix_registration_release(registration) }
        _ = ibms_preview_mix_context_release(context)
        if let slot { ibms_preview_render_slot_destroy(slot) }
        // lease 还没接走所有权。这里是移交前的唯一销毁点。
        if let mixer { ibms_preview_grouped_destroy(mixer) }
    }

    func beginRetire() {
        if let context { ibms_preview_mix_begin_retire(context) }
        if let slot { ibms_preview_render_slot_retire(slot) }
    }
}

final class PreviewAudioRetirementOwner: @unchecked Sendable {
    static let shared = PreviewAudioRetirementOwner()
    private let queue = DispatchQueue(label: "ibms.preview.unified.retire")
    private let ingressLock = NSLock()
    private var ingress: [OpaquePointer] = []
    private var held: [OpaquePointer] = []
    private var pumping = false
    private var accepted = 0
    private var releasedCount = 0

    /// 调用线程先把指针交进这个 owner。队列闭包只捕获 owner，不捕获裸 OpaquePointer。
    func take(_ lease: OpaquePointer) {
        ingressLock.lock()
        ingress.append(lease)
        accepted += 1
        ingressLock.unlock()
        queue.async {
            self.drainIngress()
            self.pump()
        }
    }

    func acceptedCount() -> Int {
        ingressLock.lock()
        let value = accepted
        ingressLock.unlock()
        return value
    }

    /// accepted 已经达到 count，并且这些 lease 都已 try_release。给关闭回归等析构，不在音频回调里等。
    func waitUntilReleased(atLeast count: Int, timeout: Double) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while true {
            if released(atLeast: count) { return true }
            if Date() >= end { return released(atLeast: count) }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func released(atLeast count: Int) -> Bool {
        ingressLock.lock()
        let ready = accepted >= count && releasedCount >= count && ingress.isEmpty
        ingressLock.unlock()
        if !ready { return false }
        return queue.sync { held.isEmpty }
    }

    private func drainIngress() {
        ingressLock.lock()
        let batch = ingress
        ingress.removeAll(keepingCapacity: true)
        ingressLock.unlock()
        held.append(contentsOf: batch)
    }

    /// 只在 holder 已标记销毁、query 和 inflight 都结束后释放。不在主线程上等。
    private func pump() {
        var freed = 0
        held.removeAll { lease in
            if ibms_preview_render_lease_try_release(lease) != 0 {
                freed += 1
                return true
            }
            return false
        }
        if freed > 0 {
            ingressLock.lock()
            releasedCount += freed
            ingressLock.unlock()
        }
        guard !held.isEmpty else {
            pumping = false
            return
        }
        if pumping { return }
        pumping = true
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) {
            self.pumping = false
            self.pump()
        }
    }
}

private struct PreviewStoredPCM {
    var samples: UnsafeMutablePointer<Float>
    var frames: Int
    var channels: Int
    var bytes: Int
}

private final class PreviewNativeAsset {
    var group = 0
    var groupRate = 48_000.0
    var channels = 1
    var frames: Int64 = 0
    var inline: PreviewStoredPCM?
    var file: PreviewFilePage?
    var residentBytes = 0
    var failed = false
    let source: PreviewUnifiedAsset

    init(source: PreviewUnifiedAsset) { self.source = source }

    func releaseStorage() {
        if let inline {
            inline.samples.deallocate()
            self.inline = nil
        }
        file?.close()
        file = nil
    }
}

private let previewPageFrames = 147_456
private let previewPageCacheBytes = 8 * 1_179_648

private struct PreviewPageKey: Hashable {
    var pageStart: Int64
    var format: Int
}

private final class PreviewImmutablePage {
    let samples: UnsafeMutablePointer<Float>
    let frames: Int
    let channels: Int
    let bytes: Int
    let pageStart: Int64
    let format: Int
    var pins = 0

    init(samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int, pageStart: Int64, format: Int) {
        self.samples = samples
        self.frames = frames
        self.channels = channels
        self.bytes = frames * channels * MemoryLayout<Float>.size
        self.pageStart = pageStart
        self.format = format
    }
}

private struct PreviewPinnedView {
    var samples: UnsafePointer<Float>
    var frames: Int
    var channels: Int
    var pages: [PreviewImmutablePage]
    var stitch: UnsafeMutablePointer<Float>?
}

private enum PreviewPageFetch {
    case page(PreviewImmutablePage)
    case eof
    case failed
}

private enum PreviewPinResult {
    case ready(PreviewPinnedView)
    case empty
    case failed
}

private final class PreviewFilePage {
    let handle: FileHandle
    var dataOffset: UInt64 = 0
    var bits = 16
    var channels = 1
    var frameCount: Int64 = 0
    private var cache: [PreviewPageKey: PreviewImmutablePage] = [:]
    private var order: [PreviewPageKey] = []
    private(set) var cachedBytes = 0

    init(handle: FileHandle) { self.handle = handle }

    var formatTag: Int { bits | (min(max(channels, 1), 2) << 16) }

    func pageStarts() -> [Int64] {
        cache.values.map(\.pageStart).sorted()
    }

    func close() {
        for page in cache.values {
            page.samples.deallocate()
        }
        cache.removeAll()
        order.removeAll()
        cachedBytes = 0
        try? handle.close()
    }

    func evictToBudget() {
        while cachedBytes > previewPageCacheBytes {
            guard let index = order.firstIndex(where: { cache[$0]?.pins == 0 }) else { return }
            let key = order.remove(at: index)
            guard let page = cache.removeValue(forKey: key) else { continue }
            cachedBytes -= page.bytes
            page.samples.deallocate()
        }
    }
}

private struct PreviewLiveVoice {
    var asset: Int
    var cue: Int
    var chartStart: Double
    var chartEnd: Double
    var origin: Int64 = 0
    var start: Int64 = 0
    var end: Int64 = 0
    var samples: UnsafePointer<Float>?
    var channels = 1
    var frames: Int64 = 0
    var contributed = false
}

private struct PreviewWorkerState {
    var bridge: PreviewAudioBridge
    var quit = false
    var generation: UInt = .max
    var assets: [PreviewNativeAsset] = []
    var cues: [PreviewUnifiedCue] = []
    var nextCue = 0
    var voices: [PreviewLiveVoice] = []
    var rate = 1.0
    var writeChart = 0.0
    var paused = false
    var stopped = false
    var seekSerial: UInt = 0
    var audible: Set<PreviewAudioKind> = [.bgm, .key]
    var produce = IBMSPreviewMixProduce()
    /// install/seek 之后，poll 必须见到比这更大的 epoch 才算这一代的 origin。
    var awaitingOrigin = false
    var epochBeforeOrigin: UInt64 = 0
    var primed = false
    var readySent = false
    var voicePool = 0
    var scheduled = 0
    var stolen = 0
    var dropped = 0
    var late = 0
    var overload = 0
    var inputUsed = 0
    var touchesLast = 0
    var touchesMax = 0
    var touchesTotal = 0
    var maxSchedule = 0.0
    var starts: [Double] = []
    var silent = false
    var record = false
    var budget = PreviewAudioLimits.maxCachedBytes
    var renderArmed = false
    var traceOpen: (@Sendable (Bool) -> Void)?
    var traceDisk: (@Sendable (Bool) -> Void)?
    var openedGroups = Set<Int>()
    var heldPages: [PreviewImmutablePage] = []
    var heldStitches: [UnsafeMutablePointer<Float>] = []
    /// 混音块在这条队列上反复使用，不再每 256 帧分配一次。
    var mixScratch: [Float] = []

    mutating func install(_ job: PreviewUnifiedJob, mailbox: PreviewAudioMailbox) {
        clearChart()
        generation = job.generation
        rate = job.rate
        paused = job.paused
        stopped = false
        seekSerial = job.seekSerial
        audible = job.audible
        silent = job.silent
        record = job.record
        budget = job.budget
        traceOpen = job.traceOpen
        traceDisk = job.traceDisk
        voicePool = max(voicePool, min(PreviewAudioLimits.maxVoices, max(0, job.voiceSlots)))
        cues = job.cues.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
            return (lhs.key ?? "") < (rhs.key ?? "")
        }
        var resident = 0
        var resources = 0
        var backed = 0
        for source in job.assets {
            let asset = PreviewNativeAsset(source: source)
            if let planar = source.planar {
                if !storeInline(asset, planar: planar, budgetLeft: budget - resident) {
                    asset.failed = true
                } else {
                    resident += asset.residentBytes
                    resources += 1
                }
            } else if source.fileURL != nil {
                if !openFile(asset) {
                    asset.failed = true
                    mailbox.fail(generation: job.generation, reason: "io")
                } else {
                    backed += 1
                }
            }
            assets.append(asset)
        }
        if assets.contains(where: \.failed), assets.allSatisfy(\.failed), !assets.isEmpty {
            mailbox.fail(generation: job.generation, reason: mailbox.failure ?? "unsupported")
        }
        epochBeforeOrigin = produce.epoch
        awaitingOrigin = true
        produce = IBMSPreviewMixProduce()
        writeChart = 0
        primed = false
        readySent = false
        if let slot = bridge.slot {
            ibms_preview_render_slot_reset_tap(slot, record ? 1 : 0)
        }
        if let context = bridge.context {
            let host = ibms_preview_mix_host_ticks()
            _ = ibms_preview_mix_command_seek(context, 0, host)
            _ = ibms_preview_mix_command_rate(context, rate, host)
            if paused {
                _ = ibms_preview_mix_command_pause(context, host)
            } else {
                _ = ibms_preview_mix_command_resume(context, host)
            }
        }
        mailbox.updateStats { stats in
            stats = PreviewUnifiedStats()
            stats.voiceSlots = self.voicePool
            stats.residentBytes = resident
            stats.residentResources = resources
            stats.fileBacked = backed
            stats.streamBlockBytes = backed > 0 ? 1_179_648 : 0
            stats.clockSource = silent ? "adapter" : "engine"
        }
        publish(mailbox)
        mailbox.noteInstalled(job.generation)
    }

    mutating func clearChart() {
        if let mixer = bridge.mixer {
            ibms_preview_grouped_reset(mixer)
        }
        openedGroups.removeAll()
        releaseHeldPages()
        for asset in assets { asset.releaseStorage() }
        assets.removeAll()
        cues.removeAll()
        voices.removeAll()
        nextCue = 0
        scheduled = 0
        stolen = 0
        dropped = 0
        late = 0
        starts.removeAll()
    }

    mutating func apply(_ job: PreviewUnifiedJob, mailbox: PreviewAudioMailbox) {
        audible = job.audible
        guard let context = bridge.context else { return }
        if job.stopped, !stopped {
            _ = ibms_preview_mix_command_stop(context, ibms_preview_mix_host_ticks())
            stopped = true
            voices.removeAll()
        }
        if job.paused != paused, !stopped {
            if job.paused {
                _ = ibms_preview_mix_command_pause(context, ibms_preview_mix_host_ticks())
            } else {
                _ = ibms_preview_mix_command_resume(context, ibms_preview_mix_host_ticks())
            }
            paused = job.paused
        }
        if abs(job.rate - rate) > 0.000_001, !stopped {
            _ = ibms_preview_mix_command_rate(context, job.rate, ibms_preview_mix_host_ticks())
            rate = job.rate
        }
        if job.seekSerial != seekSerial, !stopped {
            epochBeforeOrigin = produce.epoch
            awaitingOrigin = true
            _ = ibms_preview_mix_command_seek(context, job.seekChart, ibms_preview_mix_host_ticks())
            seekSerial = job.seekSerial
        }
        var polled = produce
        let status = ibms_preview_mix_poll(context, &polled)
        produce = polled
        if status == IBMS_PREVIEW_MIX_OK, polled.epoch != 0, generation != 0, generation != .max {
            if awaitingOrigin {
                if polled.epoch != epochBeforeOrigin {
                    mailbox.noteClock(generation: generation, epoch: polled.epoch, newOrigin: true)
                    awaitingOrigin = false
                }
            } else {
                mailbox.noteClock(generation: generation, epoch: polled.epoch, newOrigin: false)
            }
        }
        if status == IBMS_PREVIEW_MIX_OK, polled.resetCursor != 0 {
            writeChart = polled.chart
            if polled.rate > 0 { rate = polled.rate }
            rebase()
            retargetVoices()
        }
        _ = mailbox
    }

    mutating func prepareMixScratch() {
        let sampleCount = bridge.blockFrames * 2
        if mixScratch.count != sampleCount {
            mixScratch = [Float](repeating: 0, count: sampleCount)
            return
        }
        mixScratch.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            base.update(repeating: 0, count: buffer.count)
        }
    }

    mutating func produce(_ job: PreviewUnifiedJob, mailbox: PreviewAudioMailbox) -> Bool {
        guard let context = bridge.context else { return false }
        if job.generation == 0 || generation == .max { return false }
        if mailbox.readFailedGeneration() == generation { return false }
        if !mailbox.isArmed() { return false }
        if paused, !readySent {
            readySent = true
            publish(mailbox)
            mailbox.markReady(generation)
            return false
        }
        // Callback 0 必须已经 ack 了这一代的 epoch，才能开始对齐下降沿。
        if paused || stopped || produce.canWrite == 0 || awaitingOrigin { return false }
        if !primed, !paused, !silent {
            if let reader = bridge.reader {
                // 200µs 轮询。serial 刚变化说明回调在 0.2ms 内结束，距下一次还有完整一拍。
                let deadline = CFAbsoluteTimeGetCurrent() + 0.045
                var clock = IBMSPreviewMixClock()
                var baseSample: Int64 = 0
                var prevSerial: UInt64 = 0
                var haveBase = false
                while CFAbsoluteTimeGetCurrent() < deadline {
                    if ibms_preview_mix_live(reader, &clock) != 0, clock.epoch == produce.epoch {
                        if !haveBase {
                            baseSample = clock.sourceSample
                            prevSerial = clock.serial
                            haveBase = true
                        } else if clock.serial != prevSerial {
                            prevSerial = clock.serial
                            let endSample = clock.sourceSample + Int64(clock.frameCount)
                            let tapFrames = bridge.slot.map { Int(ibms_preview_render_slot_tap_frames($0)) } ?? 0
                            if endSample - baseSample >= 1024 || tapFrames >= 1024 {
                                if let slot = bridge.slot {
                                    while ibms_preview_render_slot_inflight(slot) != 0 {
                                        usleep(50)
                                    }
                                }
                                break
                            }
                        }
                    }
                    usleep(200)
                }
            } else {
                usleep(25_000)
            }
            primed = true
            apply(job, mailbox: mailbox)
            if paused || stopped || produce.canWrite == 0 || awaitingOrigin { return false }
        }
        let fill = ibms_preview_mix_fill_frames(context)
        if fill + UInt64(bridge.blockFrames) > 2048 { return false }
        reclaimConsumedVoices()
        armCues()
        placeWindows()
        pushVoices()
        prepareMixScratch()
        var used: Int32 = 0
        var peak: Float = 0
        var over: Int32 = 0
        if let mixer = bridge.mixer, !openedGroups.isEmpty {
            let status = mixScratch.withUnsafeMutableBufferPointer { buffer in
                ibms_preview_grouped_pull(mixer, buffer.baseAddress, Int32(bridge.blockFrames), &used, &peak, &over)
            }
            if status != IBMS_PREVIEW_GROUP_OK {
                mailbox.fail(generation: generation, reason: "src")
                return false
            }
            inputUsed += Int(used)
            overload += Int(over)
        }
        let chart = writeChart
        let wrote = mixScratch.withUnsafeBufferPointer { buffer in
            ibms_preview_mix_write(context, buffer.baseAddress, UInt32(bridge.blockFrames), chart, rate, produce.epoch)
        }
        if wrote != IBMS_PREVIEW_MIX_OK { return false }
        writeChart += Double(bridge.blockFrames) * rate / 48_000
        noteContributions()
        publish(mailbox)
        if !readySent {
            readySent = true
            mailbox.markReady(generation)
        }
        return true
    }

    /// fed 已经读过的声部从池里拿掉。样本已进入 SRC，不 reset，尾留在滤波器里。
    mutating func reclaimConsumedVoices() {
        guard let mixer = bridge.mixer, !openedGroups.isEmpty else { return }
        voices.removeAll { voice in
            guard voice.end > 0 else { return false }
            let group = assets[voice.asset].group
            guard openedGroups.contains(group) else { return false }
            return ibms_preview_grouped_fed(mixer, Int32(group)) >= voice.end
        }
    }

    mutating func armCues() {
        let started = Date()
        var touches = 0
        while nextCue < cues.count {
            let cue = cues[nextCue]
            guard audible.contains(cue.kind), let key = cue.key else {
                if cue.seconds > writeChart { break }
                touches += 1
                nextCue += 1
                continue
            }
            guard let assetIndex = assets.firstIndex(where: { $0.source.key == key }), !assets[assetIndex].failed else {
                if cue.seconds > writeChart { break }
                dropped += 1
                touches += 1
                nextCue += 1
                continue
            }
            let asset = assets[assetIndex]
            let offsetFrames = Int64((cue.fileOffset * asset.groupRate).rounded(.down))
            if asset.frames <= 0 || offsetFrames >= asset.frames {
                if cue.seconds > writeChart { break }
                touches += 1
                nextCue += 1
                continue
            }
            let startNative = Int64((cue.seconds * asset.groupRate).rounded(.down))
            let endNative = startNative + max(0, asset.frames - offsetFrames)
            let bounds = groupReadBounds(group: asset.group, groupRate: asset.groupRate)
            if startNative >= bounds.hi { break }
            if endNative <= bounds.lo {
                touches += 1
                nextCue += 1
                let fed = bridge.mixer.map { ibms_preview_grouped_fed($0, Int32(asset.group)) } ?? 0
                if fed > startNative + 64 { late += 1 }
                continue
            }
            let cueEnd = cue.seconds + max(0, cue.duration)
            while voices.count >= PreviewAudioLimits.maxVoices {
                let overlapping = voices.indices.filter {
                    voices[$0].chartStart < cueEnd && cue.seconds < voices[$0].chartEnd
                }
                guard overlapping.count >= PreviewAudioLimits.maxVoices,
                      let oldest = overlapping.min(by: { voices[$0].chartStart < voices[$1].chartStart })
                else { break }
                voices.remove(at: oldest)
                stolen += 1
            }
            if voices.count >= PreviewAudioLimits.maxVoices { break }
            touches += 1
            let index = nextCue
            nextCue += 1
            voices.append(PreviewLiveVoice(
                asset: assetIndex,
                cue: index,
                chartStart: cue.seconds,
                chartEnd: cueEnd
            ))
            scheduled += 1
            starts.append(cue.seconds)
            let fed = bridge.mixer.map { ibms_preview_grouped_fed($0, Int32(asset.group)) } ?? 0
            if fed > startNative + 64 { late += 1 }
        }
        touchesLast = touches
        touchesMax = max(touchesMax, touches)
        touchesTotal += touches
        maxSchedule = max(maxSchedule, Date().timeIntervalSince(started))
    }

    mutating func releaseHeldPages() {
        for page in heldPages where page.pins > 0 {
            page.pins -= 1
        }
        heldPages.removeAll()
        for stitch in heldStitches {
            stitch.deallocate()
        }
        heldStitches.removeAll()
        for asset in assets {
            asset.file?.evictToBudget()
        }
        for index in voices.indices {
            voices[index].samples = nil
        }
    }

    /// 组已打开时用当前 fed。第一次 set_voices 会按同一公式预卷，页必须盖住那次读取。
    func groupReadBounds(group: Int, groupRate: Double) -> (lo: Int64, hi: Int64) {
        let blockNative = Int64((Double(bridge.blockFrames) * groupRate * rate / 48_000).rounded(.up))
        let span = blockNative + 1024 + 64
        if openedGroups.contains(group), let mixer = bridge.mixer {
            let fed = ibms_preview_grouped_fed(mixer, Int32(group))
            return (fed, fed + span)
        }
        let chartNative = writeChart * groupRate
        let preroll = max(0, floor(chartNative - Double(IBMS_PREVIEW_GROUP_WARMUP)))
        let hi = Int64(ceil(chartNative)) + span
        return (Int64(preroll), max(hi, Int64(preroll) + span))
    }

    mutating func placeWindows() {
        releaseHeldPages()
        for index in voices.indices {
            let asset = assets[voices[index].asset]
            let offset = Int64((cues[voices[index].cue].fileOffset * asset.groupRate).rounded(.down))
            let voiceStart = Int64((voices[index].chartStart * asset.groupRate).rounded(.down))
            voices[index].start = voiceStart
            voices[index].end = voiceStart + max(0, asset.frames - offset)
            voices[index].samples = nil
            let bounds = groupReadBounds(group: asset.group, groupRate: asset.groupRate)
            let lo = max(bounds.lo, voices[index].start)
            let hi = min(bounds.hi, voices[index].end)
            guard hi > lo else { continue }
            if let inline = asset.inline {
                voices[index].samples = UnsafePointer(inline.samples)
                voices[index].channels = inline.channels
                voices[index].frames = Int64(inline.frames)
                voices[index].origin = voiceStart - offset
                continue
            }
            guard let file = asset.file else { continue }
            let assetLo = lo - voiceStart + offset
            let assetHi = hi - voiceStart + offset
            switch file.pinSpan(from: assetLo, to: assetHi, trace: traceDisk) {
            case .failed:
                assets[voices[index].asset].failed = true
            case .empty:
                break
            case .ready(let view):
                voices[index].samples = view.samples
                voices[index].channels = view.channels
                voices[index].frames = Int64(view.frames)
                voices[index].origin = lo
                heldPages.append(contentsOf: view.pages)
                if let stitch = view.stitch {
                    heldStitches.append(stitch)
                }
            }
        }
    }

    mutating func pushVoices() {
        guard let mixer = bridge.mixer else { return }
        var byGroup: [Int: [IBMSPreviewGroupedVoice]] = [:]
        for voice in voices {
            guard let samples = voice.samples else { continue }
            let asset = assets[voice.asset]
            var item = IBMSPreviewGroupedVoice()
            item.samples = samples
            item.channels = Int32(voice.channels)
            item.frames = voice.frames
            item.origin = voice.origin
            item.start = voice.start
            item.end = voice.end
            item.gainL = 1
            item.gainR = 1
            byGroup[asset.group, default: []].append(item)
        }
        for group in 0..<4 {
            let list = byGroup[group] ?? []
            let count = list.count
            let status = list.withUnsafeBufferPointer { buffer in
                ibms_preview_grouped_set_voices(
                    mixer,
                    Int32(group),
                    buffer.baseAddress,
                    Int32(buffer.count),
                    writeChart,
                    rate
                )
            }
            if status == IBMS_PREVIEW_GROUP_OK, count > 0 {
                openedGroups.insert(group)
            }
        }
    }

    mutating func rebase() {
        guard let mixer = bridge.mixer else { return }
        _ = ibms_preview_grouped_rebase(mixer, writeChart, rate)
    }

    mutating func retargetVoices() {
        voices.removeAll { $0.chartEnd <= writeChart }
        nextCue = cues.firstIndex { $0.seconds >= writeChart - 0.001 } ?? cues.count
    }

    mutating func noteContributions() {
        for index in voices.indices where !voices[index].contributed && writeChart >= voices[index].chartStart {
            voices[index].contributed = true
        }
    }

    mutating func publish(_ mailbox: PreviewAudioMailbox) {
        let active = transportActive()
        var inflight = 0
        for asset in assets { inflight += asset.file?.cachedBytes ?? 0 }
        mailbox.updateStats { stats in
            stats.scheduled = self.scheduled
            stats.stolen = self.stolen
            stats.dropped = self.dropped
            stats.voiceSlots = self.voicePool
            stats.late = self.late
            stats.cueTouchesLast = self.touchesLast
            stats.cueTouchesMax = self.touchesMax
            stats.cueTouchesTotal = self.touchesTotal
            stats.activeVoices = active
            stats.voiceStarts = self.starts
            stats.overloadSamples = self.overload
            stats.inputUsed = self.inputUsed
            stats.maxScheduleSeconds = self.maxSchedule
            stats.inflightBytes = inflight
            stats.pcmCopies = 0
            stats.scheduleStops = 0
            stats.ioFailed = self.assets.contains(where: \.failed)
        }
    }

    func transportActive() -> Int {
        voices.reduce(0) { count, voice in
            count + (writeChart >= voice.chartStart && writeChart < voice.chartEnd ? 1 : 0)
        }
    }

    mutating func storeInline(_ asset: PreviewNativeAsset, planar: Data, budgetLeft: Int) -> Bool {
        guard asset.source.channels > 0, asset.source.channels <= 2 else { return false }
        guard planar.count <= max(budgetLeft, planar.count) else { return false }
        var group: Int32 = 0
        var groupRate = 0.0
        let classified = ibms_preview_grouped_classify(asset.source.sampleRate, &group, &groupRate)
        if classified == IBMS_PREVIEW_GROUP_ERR_UNSUPPORTED {
            return false
        }
        if classified != IBMS_PREVIEW_GROUP_OK { return false }
        let channels = min(max(asset.source.channels, 1), 2)
        let frames = asset.source.frameCount
        guard frames > 0 else { return false }
        var interleaved = stereoInterleaved(planar: planar, frames: frames, channels: asset.source.channels)
        if abs(groupRate - asset.source.sampleRate) >= 1 {
            let ratio = groupRate / asset.source.sampleRate
            let capacity = Int((Double(frames) * ratio).rounded(.up)) + 64
            var output = [Float](repeating: 0, count: capacity * 2)
            let got = interleaved.withUnsafeBufferPointer { input in
                output.withUnsafeMutableBufferPointer { destination in
                    ibms_preview_grouped_upsample(input.baseAddress, Int32(frames), ratio, destination.baseAddress, Int32(capacity))
                }
            }
            guard got > 0 else { return false }
            interleaved = Array(output.prefix(Int(got) * 2))
            asset.frames = Int64(got)
            asset.channels = 2
        } else {
            asset.frames = Int64(frames)
            asset.channels = channels
            if channels == 1 {
                interleaved = monoFromStereoPairs(interleaved)
            }
        }
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: interleaved.count)
        pointer.initialize(from: interleaved, count: interleaved.count)
        let storedChannels = asset.channels
        asset.inline = PreviewStoredPCM(
            samples: pointer,
            frames: Int(asset.frames),
            channels: storedChannels,
            bytes: interleaved.count * MemoryLayout<Float>.size
        )
        asset.group = Int(group)
        asset.groupRate = groupRate
        asset.residentBytes = interleaved.count * MemoryLayout<Float>.size
        return true
    }

    mutating func openFile(_ asset: PreviewNativeAsset) -> Bool {
        guard let url = asset.source.fileURL else { return false }
        var group: Int32 = 0
        var groupRate = 0.0
        if asset.source.channels > 2 {
            return false
        }
        if ibms_preview_grouped_classify(asset.source.sampleRate, &group, &groupRate) != IBMS_PREVIEW_GROUP_OK {
            return false
        }
        traceOpen?(Thread.isMainThread)
        traceDisk?(false)
        guard let handle = try? FileHandle(forReadingFrom: url),
              let layout = PreviewWavScan.scan(handle)
        else { return false }
        let page = PreviewFilePage(handle: handle)
        page.dataOffset = layout.dataOffset
        page.bits = layout.bits
        page.channels = layout.channels
        page.frameCount = layout.frames
        asset.file = page
        asset.group = Int(group)
        asset.groupRate = groupRate
        asset.channels = min(layout.channels, 2)
        asset.frames = layout.frames
        return true
    }
}

private extension PreviewFilePage {
    func pinSpan(from: Int64, to: Int64, trace: (@Sendable (Bool) -> Void)?) -> PreviewPinResult {
        let assetLo = max(0, from)
        let assetHi = min(frameCount, to)
        if assetLo >= frameCount || assetHi <= assetLo {
            return .empty
        }
        var local: [PreviewImmutablePage] = []
        var cursor = assetLo
        while cursor < assetHi {
            let start = (cursor / Int64(previewPageFrames)) * Int64(previewPageFrames)
            switch fetch(start: start, count: previewPageFrames, trace: trace) {
            case .page(let page):
                local.append(page)
                let next = page.pageStart + Int64(page.frames)
                if next <= cursor {
                    unpin(local)
                    return .failed
                }
                cursor = next
            case .eof:
                unpin(local)
                return local.isEmpty ? .empty : .failed
            case .failed:
                unpin(local)
                return .failed
            }
        }
        let storedChannels = local[0].channels
        let frames = Int(assetHi - assetLo)
        if local.count == 1, assetHi <= local[0].pageStart + Int64(local[0].frames) {
            let into = Int(assetLo - local[0].pageStart) * storedChannels
            return .ready(PreviewPinnedView(
                samples: UnsafePointer(local[0].samples.advanced(by: into)),
                frames: frames,
                channels: storedChannels,
                pages: local,
                stitch: nil
            ))
        }
        let stitch = UnsafeMutablePointer<Float>.allocate(capacity: frames * storedChannels)
        stitch.initialize(repeating: 0, count: frames * storedChannels)
        for frame in 0..<frames {
            let assetFrame = assetLo + Int64(frame)
            guard let page = local.first(where: {
                assetFrame >= $0.pageStart && assetFrame < $0.pageStart + Int64($0.frames)
            }) else {
                stitch.deallocate()
                unpin(local)
                return .failed
            }
            let source = Int(assetFrame - page.pageStart) * storedChannels
            let destination = frame * storedChannels
            for channel in 0..<storedChannels {
                stitch[destination + channel] = page.samples[source + channel]
            }
        }
        return .ready(PreviewPinnedView(
            samples: UnsafePointer(stitch),
            frames: frames,
            channels: storedChannels,
            pages: local,
            stitch: stitch
        ))
    }

    func fetch(start: Int64, count: Int, trace: (@Sendable (Bool) -> Void)?) -> PreviewPageFetch {
        let key = PreviewPageKey(pageStart: start, format: formatTag)
        if let existing = cache[key] {
            existing.pins += 1
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
            }
            order.append(key)
            return .page(existing)
        }
        if start < 0 {
            return .failed
        }
        if start >= frameCount {
            return .eof
        }
        let channels = max(self.channels, 1)
        let frames = Int(min(Int64(count), frameCount - start))
        guard frames > 0 else { return .eof }
        let bytesPerFrame = channels * max(bits, 8) / 8
        guard bytesPerFrame > 0 else { return .failed }
        let offset = dataOffset + UInt64(start) * UInt64(bytesPerFrame)
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return .failed
        }
        let data: Data
        do {
            guard let read = try handle.read(upToCount: frames * bytesPerFrame) else { return .failed }
            data = read
        } catch {
            return .failed
        }
        trace?(false)
        let got = data.count / bytesPerFrame
        if got <= 0 {
            return .failed
        }
        let atEOF = start + Int64(got) >= frameCount
        if got < frames, !atEOF {
            return .failed
        }
        let storedChannels = min(channels, 2)
        let total = got * storedChannels
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: total)
        let copied: Bool = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            for frame in 0..<got {
                if storedChannels == 1 {
                    pointer[frame] = PreviewWavScan.sample(base, frame: frame, channel: 0, channels: channels, bits: bits)
                } else {
                    pointer[frame * 2] = PreviewWavScan.sample(base, frame: frame, channel: 0, channels: channels, bits: bits)
                    let right = channels > 1 ? 1 : 0
                    pointer[frame * 2 + 1] = PreviewWavScan.sample(base, frame: frame, channel: right, channels: channels, bits: bits)
                }
            }
            return true
        }
        if !copied {
            pointer.deallocate()
            return .failed
        }
        let page = PreviewImmutablePage(
            samples: pointer,
            frames: got,
            channels: storedChannels,
            pageStart: start,
            format: formatTag
        )
        page.pins = 1
        cache[key] = page
        order.append(key)
        cachedBytes += page.bytes
        evictToBudget()
        return .page(page)
    }

    private func unpin(_ pages: [PreviewImmutablePage]) {
        for page in pages where page.pins > 0 {
            page.pins -= 1
        }
        evictToBudget()
    }
}

private enum PreviewWavScan {
    struct Layout {
        var dataOffset: UInt64
        var channels: Int
        var bits: Int
        var frames: Int64
    }

    static func scan(_ handle: FileHandle) -> Layout? {
        try? handle.seek(toOffset: 0)
        guard let header = try? handle.read(upToCount: 12), header.count == 12,
              header.prefix(4) == Data("RIFF".utf8) else { return nil }
        var cursor: UInt64 = 12
        var channels = 0
        var bits = 0
        var dataOffset: UInt64 = 0
        var dataBytes = 0
        while true {
            try? handle.seek(toOffset: cursor)
            guard let chunk = try? handle.read(upToCount: 8), chunk.count == 8 else { break }
            let size = Int(u32(chunk, 4))
            let payload = cursor + 8
            if chunk.prefix(4) == Data("fmt ".utf8), size >= 16,
               let fmt = try? handle.read(upToCount: 16), fmt.count >= 16 {
                channels = Int(u16(fmt, 2))
                bits = Int(u16(fmt, 14))
            } else if chunk.prefix(4) == Data("data".utf8) {
                dataOffset = payload
                dataBytes = size
                break
            }
            cursor = payload + UInt64(size + (size & 1))
        }
        guard channels > 0, bits > 0, dataBytes > 0 else { return nil }
        let bytesPerFrame = channels * bits / 8
        guard bytesPerFrame > 0 else { return nil }
        return Layout(dataOffset: dataOffset, channels: channels, bits: bits, frames: Int64(dataBytes / bytesPerFrame))
    }

    static func sample(_ base: UnsafeRawPointer, frame: Int, channel: Int, channels: Int, bits: Int) -> Float {
        let index = frame * channels + channel
        if bits == 8 {
            let byte = base.load(fromByteOffset: index, as: UInt8.self)
            return (Float(byte) - 128) / 128
        }
        let low = UInt16(base.load(fromByteOffset: index * 2, as: UInt8.self))
        let high = UInt16(base.load(fromByteOffset: index * 2 + 1, as: UInt8.self))
        return Float(Int16(bitPattern: low | (high << 8))) / 32768
    }

    static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}

private func stereoInterleaved(planar: Data, frames: Int, channels: Int) -> [Float] {
    let count = frames * 2
    var output = [Float](repeating: 0, count: count)
    planar.withUnsafeBytes { raw in
        let source = raw.bindMemory(to: Float.self)
        let channelCount = max(channels, 1)
        for frame in 0..<frames {
            let left = frame < source.count ? source[frame] : 0
            let rightIndex = channelCount > 1 ? frames + frame : frame
            let right = rightIndex < source.count ? source[rightIndex] : left
            output[frame * 2] = left
            output[frame * 2 + 1] = right
        }
    }
    return output
}

private func monoFromStereoPairs(_ stereo: [Float]) -> [Float] {
    var mono = [Float]()
    mono.reserveCapacity(stereo.count / 2)
    var index = 0
    while index < stereo.count {
        mono.append(stereo[index])
        index += 2
    }
    return mono
}

struct PreviewFilePageProbeResult: Sendable {
    var json: String
    var pass: Bool
}

/// 离线页探针。只开 MixBridge / GroupedMixer，不启动 AVAudioEngine。
enum PreviewFilePageProbe {
    static func run() -> PreviewFilePageProbeResult {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibms-a3p-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return finish(pass: false, fields: ["error": "mkdir"])
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let farURL = folder.appendingPathComponent("far.wav")
        let shortURL = folder.appendingPathComponent("short.wav")
        let crossURL = folder.appendingPathComponent("cross.wav")
        let ioURL = folder.appendingPathComponent("io.wav")
        let farPage = Int64((8_000_000 / previewPageFrames) * previewPageFrames)
        writeWAV(farURL, frames: Int(farPage) + previewPageFrames, markers: [
            (0, 16384, 8192),
            (Int(farPage), 8192, previewPageFrames)
        ])
        writeWAV(shortURL, frames: 4_800, markers: [(0, 26214, 4_800)])
        writeWAV(crossURL, frames: previewPageFrames + 8_192, markers: [
            (previewPageFrames - 4_096, 26214, 4_096 + 8_192)
        ])
        writeWAV(ioURL, frames: 1_000, markers: [(0, 16384, 1_000)])
        let far = renderPair(url: farURL, offsets: [0, 8_000_000], chart: 0)
        let chart = renderPair(url: shortURL, offsets: [0], chart: 10)
        let cross = renderPair(url: crossURL, offsets: [previewPageFrames - 64], chart: 0)
        let io = ioChecks(url: ioURL)
        let farPass = far.ok && abs(far.mean - 0.375) < 0.08 && far.pages.count >= 2 && far.pages.contains(0) && far.pages.contains(farPage)
        let chartPass = chart.ok && chart.mean > 0.25 && chart.mean < 0.55 && chart.pages == [0]
        let crossPass = cross.ok && cross.mean > 0.25 && cross.pages.contains(0) && cross.pages.contains(Int64(previewPageFrames))
        let pass = farPass && chartPass && crossPass && io.eofPass && io.seekPass
        return finish(pass: pass, fields: [
            "playback": "offline",
            "far_mean": String(format: "%.5f", far.mean),
            "far_pages": far.pages.map(String.init).joined(separator: ","),
            "far_error": far.error,
            "far_pass": farPass ? "true" : "false",
            "chart10_mean": String(format: "%.5f", chart.mean),
            "chart10_pages": chart.pages.map(String.init).joined(separator: ","),
            "chart10_error": chart.error,
            "chart10_pass": chartPass ? "true" : "false",
            "cross_mean": String(format: "%.5f", cross.mean),
            "cross_pages": cross.pages.map(String.init).joined(separator: ","),
            "cross_error": cross.error,
            "cross_pass": crossPass ? "true" : "false",
            "eof": io.eof,
            "eof_reused_old": io.eofReused ? "true" : "false",
            "seek": io.seek,
            "seek_reused_old": io.seekReused ? "true" : "false",
            "io_pass": (io.eofPass && io.seekPass) ? "true" : "false",
            "pass": pass ? "true" : "false",
            "not_in_batch": "rare-fs,budget,schedule"
        ])
    }

    private struct Render {
        var mean = 0.0
        var pages: [Int64] = []
        var ok = false
        var error = ""
    }

    private struct IOResult {
        var eof = ""
        var eofReused = true
        var eofPass = false
        var seek = ""
        var seekReused = true
        var seekPass = false
    }

    private static func renderPair(url: URL, offsets: [Int], chart: Double) -> Render {
        let bridge = PreviewAudioBridge()
        guard bridge.open() else { return Render(error: "bridge") }
        var state = PreviewWorkerState(bridge: bridge)
        state.rate = 1
        state.writeChart = chart
        let asset = PreviewNativeAsset(source: PreviewUnifiedAsset(
            key: "wav",
            sampleRate: 48_000,
            channels: 1,
            frameCount: 1,
            planar: nil,
            fileURL: url,
            temporary: false,
            sourceBytes: 0
        ))
        guard state.openFile(asset) else {
            state.clearChart()
            return Render(error: "open")
        }
        state.assets = [asset]
        state.cues = offsets.enumerated().map { index, frame in
            PreviewUnifiedCue(
                seconds: chart,
                key: "wav",
                kind: .key,
                fileOffset: Double(frame) / asset.groupRate,
                duration: 1
            )
        }
        state.voices = offsets.enumerated().map { index, _ in
            PreviewLiveVoice(asset: 0, cue: index, chartStart: chart, chartEnd: chart + 1)
        }
        var blocks: [[Float]] = []
        for _ in 0..<12 {
            state.placeWindows()
            state.pushVoices()
            guard let mixer = state.bridge.mixer else {
                state.clearChart()
                return Render(error: "mixer")
            }
            var block = [Float](repeating: 0, count: state.bridge.blockFrames * 2)
            var used: Int32 = 0
            var peak: Float = 0
            var over: Int32 = 0
            let status = block.withUnsafeMutableBufferPointer { buffer in
                ibms_preview_grouped_pull(mixer, buffer.baseAddress, Int32(state.bridge.blockFrames), &used, &peak, &over)
            }
            if status != IBMS_PREVIEW_GROUP_OK {
                state.clearChart()
                return Render(error: "pull")
            }
            blocks.append(block)
            state.writeChart += Double(state.bridge.blockFrames) * state.rate / 48_000
        }
        let pages = asset.file?.pageStarts() ?? []
        let settled = blocks.suffix(4)
        var sum = 0.0
        var count = 0
        for block in settled {
            var frame = 0
            while frame < block.count {
                sum += Double(block[frame])
                count += 1
                frame += 2
            }
        }
        state.clearChart()
        return Render(mean: count > 0 ? sum / Double(count) : 0, pages: pages, ok: true, error: "")
    }

    private static func ioChecks(url: URL) -> IOResult {
        var result = IOResult()
        guard let handle = try? FileHandle(forReadingFrom: url), let layout = PreviewWavScan.scan(handle) else {
            result.eof = "open"
            result.seek = "open"
            return result
        }
        let file = PreviewFilePage(handle: handle)
        file.dataOffset = layout.dataOffset
        file.bits = layout.bits
        file.channels = layout.channels
        file.frameCount = layout.frames
        guard case .page(let first) = file.fetch(start: 0, count: previewPageFrames, trace: nil) else {
            result.eof = "first"
            result.seek = "first"
            file.close()
            return result
        }
        let old = first.samples
        let eofStart = file.frameCount
        let eof = file.fetch(start: eofStart, count: previewPageFrames, trace: nil)
        if case .eof = eof {
            result.eof = "eof"
            result.eofReused = false
        } else if case .page(let page) = eof {
            result.eof = "page"
            result.eofReused = page.samples == old
        } else {
            result.eof = "failed"
            result.eofReused = false
        }
        result.eofPass = result.eof == "eof" && !result.eofReused && !file.pageStarts().contains(eofStart)
        file.frameCount = 500_000
        try? handle.close()
        let seek = file.fetch(start: Int64(previewPageFrames), count: previewPageFrames, trace: nil)
        if case .failed = seek {
            result.seek = "failed"
            result.seekReused = false
        } else if case .page(let page) = seek {
            result.seek = "page"
            result.seekReused = page.samples == old || page.pageStart != Int64(previewPageFrames)
        } else {
            result.seek = "eof"
            result.seekReused = false
        }
        result.seekPass = result.seek == "failed" && !result.seekReused && !file.pageStarts().contains(Int64(previewPageFrames))
        file.close()
        return result
    }

    private static func writeWAV(_ url: URL, frames: Int, markers: [(Int, Int16, Int)]) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        var header = [UInt8]()
        func ascii(_ text: String) { header.append(contentsOf: text.utf8) }
        func u32(_ value: UInt32) {
            header.append(UInt8(value & 0xff))
            header.append(UInt8((value >> 8) & 0xff))
            header.append(UInt8((value >> 16) & 0xff))
            header.append(UInt8((value >> 24) & 0xff))
        }
        func u16(_ value: UInt16) {
            header.append(UInt8(value & 0xff))
            header.append(UInt8((value >> 8) & 0xff))
        }
        let dataBytes = frames * 2
        ascii("RIFF")
        u32(UInt32(36 + dataBytes))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(48_000)
        u32(96_000)
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(dataBytes))
        try? handle.write(contentsOf: header)
        try? handle.truncate(atOffset: UInt64(header.count + dataBytes))
        for marker in markers {
            var bytes = [UInt8]()
            bytes.reserveCapacity(marker.2 * 2)
            let bits = UInt16(bitPattern: marker.1)
            for _ in 0..<marker.2 {
                bytes.append(UInt8(bits & 0xff))
                bytes.append(UInt8((bits >> 8) & 0xff))
            }
            try? handle.seek(toOffset: UInt64(header.count + marker.0 * 2))
            try? handle.write(contentsOf: bytes)
        }
    }

    private static func finish(pass: Bool, fields: [String: String]) -> PreviewFilePageProbeResult {
        let body = fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            if value == "true" || value == "false" {
                return "\"\(key)\":\(value)"
            }
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(key)\":\"\(escaped)\""
        }.joined(separator: ",")
        return PreviewFilePageProbeResult(json: "{\(body)}\n", pass: pass)
    }
}

enum PreviewMixerOwnershipProbe {
    static func resetRetire(cycles: Int) -> String {
        let tone = [Float](repeating: 0.5, count: 4096)
        return tone.withUnsafeBufferPointer { buffer -> String in
            for cycle in 0..<cycles {
                let bridge = PreviewAudioBridge()
                guard bridge.open(), let mixer = bridge.mixer, bridge.lease != nil else { return "open \(cycle)" }
                var state = PreviewWorkerState(bridge: bridge)
                state.clearChart()
                if state.bridge.mixer != mixer { return "alias \(cycle)" }
                var voice = IBMSPreviewGroupedVoice()
                voice.samples = buffer.baseAddress
                voice.channels = 1
                voice.frames = Int64(buffer.count)
                voice.origin = 0
                voice.start = 0
                voice.end = Int64(buffer.count)
                voice.gainL = 1
                voice.gainR = 1
                if ibms_preview_grouped_set_voices(mixer, 1, &voice, 1, 0, 1) != IBMS_PREVIEW_GROUP_OK {
                    _ = release(bridge)
                    return "set \(cycle)"
                }
                var peak = pullPeak(bridge, mixer)
                if peak < 0.05 {
                    _ = release(bridge)
                    return "pull \(cycle) \(peak)"
                }
                state.clearChart()
                if state.bridge.mixer != mixer {
                    _ = release(bridge)
                    return "replay \(cycle)"
                }
                peak = pullPeak(bridge, mixer)
                if peak != 0 {
                    _ = release(bridge)
                    return "silent \(cycle) \(peak)"
                }
                if ibms_preview_grouped_set_voices(mixer, 1, &voice, 1, 0, 1) != IBMS_PREVIEW_GROUP_OK {
                    _ = release(bridge)
                    return "reset-set \(cycle)"
                }
                peak = pullPeak(bridge, mixer)
                if peak < 0.05 {
                    _ = release(bridge)
                    return "reset-pull \(cycle) \(peak)"
                }
                if !release(bridge) { return "release \(cycle)" }
            }
            return "ok"
        }
    }

    private static func pullPeak(_ bridge: PreviewAudioBridge, _ mixer: OpaquePointer) -> Float {
        var block = [Float](repeating: 0, count: bridge.blockFrames * 2)
        var used: Int32 = 0
        var over: Int32 = 0
        var best: Float = 0
        for _ in 0..<16 {
            var local: Float = 0
            let status = block.withUnsafeMutableBufferPointer { buf in
                ibms_preview_grouped_pull(mixer, buf.baseAddress, Int32(bridge.blockFrames), &used, &local, &over)
            }
            if status != IBMS_PREVIEW_GROUP_OK { return -1 }
            if local > best { best = local }
        }
        return best
    }

    private static func release(_ bridge: PreviewAudioBridge) -> Bool {
        guard let lease = bridge.lease else { return false }
        bridge.beginRetire()
        ibms_preview_render_lease_request_retire(lease)
        bridge.mixer = nil
        bridge.lease = nil
        return ibms_preview_render_lease_try_release(lease) != 0
    }
}
