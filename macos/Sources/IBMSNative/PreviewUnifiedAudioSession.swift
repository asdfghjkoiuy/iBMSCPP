import AVFoundation
import Foundation
import os

/// 闭包强持的绑定。deinit 只原子减少 holder，不释放 C 对象。
final class PreviewRenderToken: @unchecked Sendable {
    let lease: OpaquePointer
    let binding: UInt64
    init(lease: OpaquePointer, binding: UInt64) {
        self.lease = lease
        self.binding = binding
        ibms_preview_render_lease_hold(lease)
    }

    deinit { ibms_preview_render_lease_unhold(lease) }

    func drive(_ host: UInt64, frames: Int, interleaved: UnsafeMutablePointer<Float>?) -> Int32 {
        ibms_preview_render_lease_drive_buffer(lease, binding, host, UInt32(frames), interleaved)
    }

    func driveList(_ stamp: UnsafeRawPointer?, frames: UInt32, list: UnsafeMutableRawPointer) -> Int32 {
        ibms_preview_render_lease_drive(lease, binding, stamp, frames, list)
    }
}

// AS-SPAN-CLOCK-BEGIN
/// 在已发布的 source host span 里选一个样本。不跨 span 插值，也不按超出末端的 host 继续乘 rate。
enum PreviewHostSpanClock {
    static let sourceRate = 48_000.0
    static let historyCapacity = 1024

    enum Decision: Equatable {
        case keepOrigin
        case span(index: Int, sample: UInt32)
    }

    static func decide(
        count: Int,
        now: Double,
        serial: (Int) -> UInt64,
        frameCount: (Int) -> UInt32,
        validFrames: (Int) -> UInt32,
        hostStart: (Int) -> Double
    ) -> Decision {
        if count <= 0 || !now.isFinite {
            return .keepOrigin
        }
        var contained = -1
        var containedStart = 0.0
        var containedFrames: UInt32 = 0
        var completed = -1
        var completedEnd = -Double.greatestFiniteMagnitude
        var completedFrames: UInt32 = 0
        var completedValid: UInt32 = 0
        for index in 0..<count {
            let frames = frameCount(index)
            if serial(index) == 0 || frames == 0 {
                continue
            }
            let start = hostStart(index)
            if !start.isFinite {
                continue
            }
            let end = start + Double(frames) / sourceRate
            if now >= start && now < end {
                contained = index
                containedStart = start
                containedFrames = frames
            } else if now >= end && (end > completedEnd || (end == completedEnd && index > completed)) {
                completed = index
                completedEnd = end
                completedFrames = frames
                completedValid = validFrames(index)
            }
        }
        if contained >= 0 {
            return .span(
                index: contained,
                sample: interiorSample(now: now, start: containedStart, frames: containedFrames)
            )
        }
        if completed >= 0 {
            return .span(index: completed, sample: endSample(frames: completedFrames, valid: completedValid))
        }
        return .keepOrigin
    }

    /// `now` 在 [start, end) 内。样本只属于这一段。
    static func interiorSample(now: Double, start: Double, frames: UInt32) -> UInt32 {
        if frames == 0 || !(now > start) {
            return 0
        }
        let raw = (now - start) * sourceRate
        if !raw.isFinite || raw <= 0 {
            return 0
        }
        if raw >= Double(frames) {
            return frames - 1
        }
        return UInt32(raw)
    }

    /// 已走完的 span 停在末端，不按剩余 host 外推。
    /// valid < frames：末端样本是 valid。span_map 在 index >= valid 时 used = valid，chart/wall 停在有效帧终点。
    /// validFrames-1 仍是会前进的最后一帧，不能把它当成这段的终点。
    /// valid >= frames：span_map 拒绝 index >= frames，最后合法样本是 frames-1（也就是 valid-1）。
    static func endSample(frames: UInt32, valid: UInt32) -> UInt32 {
        if frames == 0 {
            return 0
        }
        let frozen = valid < frames ? valid : frames
        if frozen == 0 || frozen < frames {
            return frozen
        }
        return frames - 1
    }
}
// AS-SPAN-CLOCK-END

/// 文件级、非 actor。闭包在这里生成，不继承 MainActor。只捕获 token，块体只进 C。
private func previewSourceRenderBlock(token: PreviewRenderToken) -> AVAudioSourceNodeRenderBlock {
    let block: @Sendable (UnsafeMutablePointer<ObjCBool>, UnsafePointer<AudioTimeStamp>, AVAudioFrameCount, UnsafeMutablePointer<AudioBufferList>) -> OSStatus = { _, timestamp, frameCount, abl in
        ibms_preview_render_lease_drive(
            token.lease,
            token.binding,
            UnsafeRawPointer(timestamp),
            frameCount,
            UnsafeMutableRawPointer(abl)
        )
    }
    return block
}

/// 文件级、非 actor。tap 不捕获 Session。锁对象在返回闭包前已经存在。
private func previewDeviceTapBlock() -> AVAudioNodeTapBlock {
    _ = PreviewDeviceTapRate.shared.load()
    let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
        let rate = buffer.format.sampleRate
        if rate > 0 {
            PreviewDeviceTapRate.shared.store(rate)
        }
    }
    return block
}

/// 单 AVAudioSourceNode 或显式静音 adapter。MainActor 外壳只采样已经提交的 host span。
@MainActor
final class PreviewUnifiedAudioSession {
    let worker = PreviewUnifiedAudioWorker()
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var adapter: PreviewSilentAdapter?
    private var liveToken: PreviewRenderToken?
    private var configObserver: NSObjectProtocol?
    private var usingEngine = false
    private var pendingAttach = false
    private var terminated = false
    private var boundDeviceRate = 0.0
    private var boundDeviceChannels = 0
    private var deviceTapRate = 0.0
    private var rememberedChart = 0.0
    private var rememberedWall = 0.0
    private var rememberedGeneration: UInt = 0
    /// 历史 span 只分配这一次。查询在 MainActor，释放在 deinit，都不在音频回调里。
    nonisolated(unsafe) private let clockSlots: UnsafeMutablePointer<IBMSPreviewMixClock>
    var onReady: ((UInt) -> Void)?
    var onFailed: ((UInt, String) -> Void)?
    var deviceOutputRate: Double {
        let tapped = PreviewDeviceTapRate.shared.load()
        return tapped > 0 ? tapped : deviceTapRate
    }
    var outputNodeRate: Double { boundDeviceRate }
    func storedDeviceTapRate() -> Double { PreviewDeviceTapRate.shared.load() }

    init() {
        let slots = UnsafeMutablePointer<IBMSPreviewMixClock>.allocate(capacity: PreviewHostSpanClock.historyCapacity)
        slots.initialize(repeating: IBMSPreviewMixClock(), count: PreviewHostSpanClock.historyCapacity)
        clockSlots = slots
        worker.mailbox.onReady = { [weak self] generation in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onReady?(generation) }
            }
        }
        worker.mailbox.onFailed = { [weak self] generation, reason in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onFailed?(generation, reason) }
            }
        }
        worker.mailbox.onBooted = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.terminated else { return }
                    self.attachPending()
                }
            }
        }
        worker.ensureStarted()
    }

    deinit {
        clockSlots.deinitialize(count: PreviewHostSpanClock.historyCapacity)
        clockSlots.deallocate()
    }

    func currentJob() -> PreviewUnifiedJob { worker.mailbox.snapshot() }

    func submit(_ job: PreviewUnifiedJob) {
        guard !terminated else { return }
        worker.ensureStarted()
        worker.mailbox.lock.lock()
        let previous = worker.mailbox.clockGeneration
        worker.mailbox.job = job
        worker.mailbox.failure = nil
        let newGeneration = job.generation != previous
        if newGeneration {
            worker.mailbox.beginClockGenerationLocked(job.generation)
        }
        worker.mailbox.lock.unlock()
        if newGeneration {
            rememberedChart = 0
            rememberedWall = 0
            rememberedGeneration = job.generation
        }
        worker.mailbox.wake()
        pendingAttach = true
        attachPending()
    }

    func update(_ job: PreviewUnifiedJob) {
        guard !terminated else { return }
        worker.mailbox.lock.lock()
        let previousGeneration = worker.mailbox.job.generation
        let previousSeek = worker.mailbox.job.seekSerial
        worker.mailbox.job = job
        let generationChanged = job.generation != previousGeneration
        let seekChanged = job.seekSerial != previousSeek
        if generationChanged {
            worker.mailbox.beginClockGenerationLocked(job.generation)
        } else if seekChanged {
            worker.mailbox.invalidateClockOriginLocked()
        }
        worker.mailbox.lock.unlock()
        if generationChanged {
            rememberedChart = 0
            rememberedWall = 0
            rememberedGeneration = job.generation
        } else if seekChanged {
            rememberedChart = job.seekChart
            rememberedWall = 0
            rememberedGeneration = job.generation
        }
        worker.mailbox.wake()
    }

    func stats() -> PreviewUnifiedStats { worker.mailbox.statsCopy() }

    func failure() -> String? {
        worker.mailbox.lock.lock()
        let value = worker.mailbox.failure
        worker.mailbox.lock.unlock()
        return value
    }

    func consumeRenderFault() -> Int32 {
        guard !terminated else { return 0 }
        return worker.pointers.withQuery { lease in
            let status = ibms_preview_render_lease_last_status(lease)
            return status == IBMS_PREVIEW_MIX_OK ? 0 : status
        } ?? 0
    }

    func tapLeft() -> [Float] {
        guard let copied = worker.pointers.withQuery({ lease -> [Float] in
            guard let slot = ibms_preview_render_lease_slot(lease) else { return [] }
            let count = Int(ibms_preview_render_slot_tap_frames(slot))
            guard count > 0 else { return [] }
            var output = [Float](repeating: 0, count: count)
            let copied = output.withUnsafeMutableBufferPointer { buffer in
                ibms_preview_render_slot_copy_tap_left(slot, buffer.baseAddress, Int32(count))
            }
            if copied < count { output.removeLast(count - Int(copied)) }
            return output
        }) else { return [] }
        return copied
    }

    /// source callback 的 host span。不含设备 post-tap，也不加扬声器延迟。
    /// 历史缓冲在 init 分配一次。只接受这一代已 ack 的 epoch；ack 前保持 origin。
    func mappedClock(generation: UInt) -> (chart: Double, wall: Double) {
        if generation != rememberedGeneration {
            rememberedGeneration = generation
            rememberedChart = 0
            rememberedWall = 0
        }
        let proof = worker.mailbox.clockProof()
        let origin = proof.originEpoch
        let accepted = proof.acceptedEpoch
        guard proof.acked, proof.generation == generation, origin != 0 else {
            return (rememberedChart, rememberedWall)
        }
        let slots = clockSlots
        let mapped = worker.pointers.withQuery { lease -> (Double, Double)? in
            guard let reader = ibms_preview_render_lease_reader(lease).map({ OpaquePointer($0) }) else { return nil }
            let copied = Int(ibms_preview_mix_copy_clocks(reader, slots, UInt32(PreviewHostSpanClock.historyCapacity)))
            let now = ibms_preview_mix_ticks_to_seconds(reader, ibms_preview_mix_host_ticks())
            let decision = PreviewHostSpanClock.decide(
                count: copied,
                now: now,
                serial: { index in
                    let span = slots[index]
                    if span.epoch < origin || span.epoch > accepted { return 0 }
                    return span.serial
                },
                frameCount: { slots[$0].frameCount },
                validFrames: { slots[$0].validFrames },
                hostStart: { index in
                    let span = slots[index]
                    return ibms_preview_mix_ticks_to_seconds(reader, span.hostTicks)
                        + Double(span.hostFrameOffset) / PreviewHostSpanClock.sourceRate
                }
            )
            guard case .span(let index, let sample) = decision else { return nil }
            var span = slots[index]
            if span.epoch < origin || span.epoch > accepted { return nil }
            var host = 0.0
            var chart = 0.0
            var wall = 0.0
            var advanced: Int32 = 0
            guard ibms_preview_mix_span_map(reader, &span, sample, &host, &chart, &wall, &advanced) != 0 else {
                return nil
            }
            return (chart, wall)
        }
        if let mapped {
            rememberedChart = mapped.0
            rememberedWall = mapped.1
            return (mapped.0, mapped.1)
        }
        return (rememberedChart, rememberedWall)
    }

    func debugCaptureToken() -> PreviewRenderToken? {
        makeRenderToken()
    }

    func debugHolderCount() -> Int {
        guard !terminated else { return 0 }
        return worker.pointers.withQuery { lease -> Int? in
            Int(ibms_preview_render_lease_holders(lease))
        } ?? 0
    }

    /// 换 binding 并换上新节点。返回的 token 仍是换之前的 binding。
    func debugReplaceBinding() -> PreviewRenderToken? {
        guard let stale = makeRenderToken() else { return nil }
        _ = ibms_preview_render_lease_rebind(stale.lease)
        if usingEngine {
            installSourceNode()
        } else if adapter != nil {
            adapter?.stop()
            adapter = nil
            startAdapter()
        }
        return stale
    }

    func shutdown() {
        guard !terminated else { return }
        terminated = true
        pendingAttach = false
        adapter?.stop()
        adapter = nil
        engine.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        if let source {
            engine.disconnectNodeOutput(source)
            engine.detach(source)
        }
        source = nil
        liveToken = nil
        usingEngine = false
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        worker.shutdown()
    }

    /// 锁还在时构造 token，init 里的 hold 发生在 clear 能摘掉 publication 之前。
    private func makeRenderToken() -> PreviewRenderToken? {
        guard !terminated else { return nil }
        let pointers = worker.pointers
        pointers.lock.lock()
        defer { pointers.lock.unlock() }
        guard let lease = pointers.lease else { return nil }
        return PreviewRenderToken(lease: lease, binding: ibms_preview_render_lease_binding(lease))
    }

    private func leasePublished() -> Bool {
        let pointers = worker.pointers
        pointers.lock.lock()
        let present = pointers.lease != nil
        pointers.lock.unlock()
        return present
    }

    private func attachPending() {
        guard !terminated, pendingAttach else { return }
        guard leasePublished() else { return }
        let job = currentJob()
        if job.silent {
            startAdapter()
        } else if !startEngine() {
            pendingAttach = false
            onFailed?(job.generation, "engine")
            return
        }
        worker.mailbox.setArmed(true)
        pendingAttach = false
    }

    private func startAdapter() {
        guard !terminated, adapter == nil, !usingEngine, let token = makeRenderToken() else { return }
        let started = PreviewSilentAdapter(token: token)
        started.start()
        adapter = started
        liveToken = token
        worker.mailbox.updateStats { $0.clockSource = "adapter" }
    }

    private func startEngine() -> Bool {
        if terminated { return false }
        if usingEngine { return engine.isRunning }
        guard leasePublished(),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)
        else { return false }
        adapter?.stop()
        adapter = nil
        installSourceNode()
        guard let source else { return false }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.detach(source)
            self.source = nil
            liveToken = nil
            return false
        }
        usingEngine = true
        let output = engine.outputNode.outputFormat(forBus: 0)
        boundDeviceRate = output.sampleRate
        boundDeviceChannels = Int(output.channelCount)
        installDeviceTap()
        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteDeviceConfiguration() }
            }
        }
        worker.mailbox.updateStats { $0.clockSource = "engine" }
        return true
    }

    private func installSourceNode() {
        guard let token = makeRenderToken() else { return }
        if let source {
            engine.disconnectNodeOutput(source)
            engine.detach(source)
        }
        liveToken = token
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false) else {
            return
        }
        let node = AVAudioSourceNode(format: format, renderBlock: previewSourceRenderBlock(token: token))
        source = node
        if usingEngine {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    private func installDeviceTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil, block: previewDeviceTapBlock())
        deviceTapRate = PreviewDeviceTapRate.shared.load()
        if deviceTapRate == 0 {
            deviceTapRate = boundDeviceRate
        }
    }

    private func noteDeviceConfiguration() {
        guard !terminated else { return }
        let output = engine.outputNode.outputFormat(forBus: 0)
        let rate = output.sampleRate
        let channels = Int(output.channelCount)
        if boundDeviceRate == 0 {
            boundDeviceRate = rate
            boundDeviceChannels = channels
            return
        }
        if abs(rate - boundDeviceRate) < 1, channels == boundDeviceChannels {
            return
        }
        let paused = currentJob().paused
        boundDeviceRate = rate
        boundDeviceChannels = channels
        _ = worker.pointers.withQuery { lease -> UInt64? in
            ibms_preview_render_lease_rebind(lease)
        }
        installSourceNode()
        var job = currentJob()
        job.paused = paused
        update(job)
        installDeviceTap()
        deviceTapRate = PreviewDeviceTapRate.shared.load()
    }
}

private final class PreviewDeviceTapRate: @unchecked Sendable {
    static let shared = PreviewDeviceTapRate()
    private let lock = OSAllocatedUnfairLock(initialState: 0.0)
    func store(_ value: Double) { lock.withLock { $0 = value } }
    func load() -> Double { lock.withLock { $0 } }
}

private final class PreviewSilentAdapter: @unchecked Sendable {
    let token: PreviewRenderToken
    private let stopFlag = OSAllocatedUnfairLock(initialState: false)

    init(token: PreviewRenderToken) {
        self.token = token
    }

    func start() {
        let token = self.token
        let stopFlag = self.stopFlag
        Thread.detachNewThread {
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            let blockSeconds = 256.0 / 48_000.0
            let numer = info.numer > 0 ? info.numer : 1
            let nanos = blockSeconds * 1e9
            let scaled = nanos * Double(info.denom)
            let ticks = scaled / Double(numer)
            let blockTicks = UInt64(ticks)
            var next = mach_absolute_time()
            while !stopFlag.withLock({ $0 }) {
                let now = mach_absolute_time()
                if blockTicks > 0, now > next, now &- next > blockTicks &* 64 {
                    next = now
                }
                while next &+ blockTicks < now {
                    _ = token.drive(next, frames: 256, interleaved: nil)
                    next &+= blockTicks
                }
                _ = token.drive(next, frames: 256, interleaved: nil)
                next &+= blockTicks
                mach_wait_until(next)
            }
        }
    }

    func stop() {
        stopFlag.withLock { $0 = true }
    }
}
