#include "IBMSPreviewMixBridge.h"

#if !defined(__APPLE__)
#error IBMSPreviewMixBridge requires macOS
#endif

#include <mach/mach_time.h>

#include <atomic>
#include <cstddef>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>

/* 多字发布的读者只接受“两次相同的非零偶数 seq”。
   写端在 seq_cst 总序里是：奇数、每个 payload、偶数。读端是：seq、每个 payload、seq。
   总序尊重同一线程的 sequenced-before。因此被接受的 payload 来自同一次发布。
   奇数若只用 release、payload 若用 relaxed，跨字段次序不成立；这里每个字都是 seq_cst。
   末尾的 acquire fence 是冗余的，证明不依赖它。有界重试失败就放弃，不自旋。
   seq 为 0 表示还没有成功发布。稳定偶数若绕回 0，写端改记 2，避免和“未发布”混淆。 */

namespace {

constexpr uint32_t kTimingCap = 4096;
constexpr int kClockPayloadWords = 12;
constexpr int kClockWords = 13;
constexpr int kReaderTries = 8;
constexpr int kCallbackTries = 2;
constexpr int kMaxPending = 64;
constexpr uint32_t kRegMagic = 0x504D5247u;
constexpr uint32_t kReaderMagic = 0x504D5244u;

std::atomic<uint64_t> g_next_session{1};

uint64_t bits_of(double v) {
    uint64_t bits = 0;
    std::memcpy(&bits, &v, sizeof(bits));
    return bits;
}

double double_of(uint64_t bits) {
    double v = 0;
    std::memcpy(&v, &bits, sizeof(v));
    return v;
}

bool rate_ok(double rate) { return rate >= 0.25 && rate <= 4.0; }

bool power_of_two(uint32_t v) { return v != 0 && (v & (v - 1u)) == 0; }

uint64_t stable_even(uint64_t seq) {
    uint64_t even = seq + 2;
    if (even == 0) {
        even = 2;
    }
    return even;
}

struct Meta {
    uint64_t beginFrame;
    uint64_t epoch;
    uint64_t session;
    double chartStart;
    double rate;
    uint32_t frames;
};

struct Desired {
    std::atomic<uint64_t> seq{0};
    std::atomic<uint64_t> serial{0};
    std::atomic<uint64_t> epoch{0};
    std::atomic<uint64_t> session{0};
    std::atomic<uint64_t> requestHost{0};
    std::atomic<uint64_t> seekRevision{0};
    std::atomic<uint64_t> rateBits{0};
    std::atomic<uint64_t> chartBits{0};
    std::atomic<uint32_t> kind{0};
    std::atomic<uint32_t> paused{0};
    std::atomic<uint32_t> stopped{0};
};

struct AckStore {
    std::atomic<uint64_t> seq{0};
    std::atomic<uint64_t> serial{0};
    std::atomic<uint64_t> epoch{0};
    std::atomic<uint64_t> session{0};
    std::atomic<uint64_t> logicalFrame{0};
    std::atomic<uint64_t> sourceSampleBits{0};
    std::atomic<uint64_t> hostTicks{0};
    std::atomic<uint64_t> requestHost{0};
    std::atomic<uint64_t> seekRevision{0};
    std::atomic<uint64_t> chartBits{0};
    std::atomic<uint64_t> rateBits{0};
    std::atomic<uint64_t> wallBits{0};
    std::atomic<uint32_t> kind{0};
    std::atomic<uint32_t> state{0};
    std::atomic<uint64_t> adopt{0};
    std::atomic<uint32_t> paused{0};
    std::atomic<uint32_t> stopped{0};
};

struct DesiredView {
    uint64_t serial;
    uint64_t epoch;
    uint64_t session;
    uint64_t requestHost;
    uint64_t seekRevision;
    double rate;
    double seekChart;
    uint32_t kind;
    uint32_t paused;
    uint32_t stopped;
};

struct AckView {
    uint64_t serial;
    uint64_t epoch;
    uint64_t session;
    uint64_t logicalFrame;
    int64_t sourceSample;
    uint64_t hostTicks;
    uint64_t requestHost;
    uint64_t seekRevision;
    double chart;
    double rate;
    double wall;
    uint32_t kind;
    uint32_t state;
    uint64_t adopt;
    uint32_t paused;
    uint32_t stopped;
};

struct ClockSlot {
    std::atomic<uint64_t> seq;
    std::atomic<uint64_t> word[kClockWords];
    ClockSlot() : seq(0) {
        for (int i = 0; i < kClockWords; ++i) {
            word[i].store(0, std::memory_order_relaxed);
        }
    }
};

struct Context {
    float *samples = nullptr;
    Meta *meta = nullptr;
    ClockSlot *log = nullptr;
    uint32_t *timing = nullptr;
    ClockSlot live;
    Desired desired;
    AckStore ack;

    uint32_t capacity = 0;
    uint32_t mask = 0;
    uint32_t blockFrames = 0;
    uint32_t slotMask = 0;
    uint32_t slotCount = 0;
    uint32_t logCapacity = 0;
    uint32_t logMask = 0;
    uint32_t lockFree = 0;
    uint64_t session = 0;
    double sourceRate = IBMS_PREVIEW_MIX_SOURCE_RATE;
    mach_timebase_info_data_t timebase{};

    std::atomic<uint64_t> write{0};
    std::atomic<uint64_t> read{0};
    std::atomic<uint64_t> logWrite{0};
    std::atomic<uint64_t> realUnderrunFrames{0};
    std::atomic<uint64_t> primeSilenceFrames{0};
    std::atomic<uint64_t> discardFrames{0};
    std::atomic<uint64_t> pauseFrames{0};
    std::atomic<uint64_t> stopFrames{0};
    std::atomic<uint64_t> flushSpans{0};
    std::atomic<uint64_t> flushSilenceFrames{0};
    std::atomic<uint64_t> retiredSilenceFrames{0};
    std::atomic<uint64_t> protocolFaults{0};
    std::atomic<uint64_t> overrunWrites{0};
    std::atomic<uint64_t> callbacks{0};
    std::atomic<uint64_t> nsMax{0};
    std::atomic<uint64_t> timingWrite{0};
    std::atomic<uint32_t> retired{0};
    std::atomic<uint32_t> registrationCount{0};
    std::atomic<uint32_t> readerCount{0};
    std::atomic<uint32_t> queriesClosed{0};
    std::atomic<uint32_t> workerExited{0};

    uint64_t cmdSerial = 0;
    uint64_t cmdEpoch = 1;
    uint64_t seekRevision = 0;
    uint64_t cmdHost = 0;
    double cmdRate = 1;
    double seekChart = 0;
    uint32_t cmdKind = IBMS_PREVIEW_MIX_CMD_NONE;
    int cmdPaused = 0;
    int cmdStopped = 0;

    uint64_t ackedSerial = 0;
    uint64_t ackedSeekRevision = 0;
    uint64_t currentEpoch = 1;
    uint64_t adoptGen = 0;
    uint64_t spanSerial = 0;
    double consumedChart = 0;
    double consumedWall = 0;
    double currentRate = 1;
    int paused = 0;
    int stopped = 0;
    int everValid = 0;
    int64_t lastSourceEnd = INT64_MIN;

    ~Context() {
        delete[] samples;
        delete[] meta;
        delete[] log;
        delete[] timing;
    }

    Context(const Context &) = delete;
    Context &operator=(const Context &) = delete;
    Context() = default;
};

struct Registration {
    Context *context;
    uint32_t magic;
};

struct Reader {
    Context *context;
    uint32_t magic;
};

static_assert(sizeof(IBMSPreviewMixClock) == 96, "clock payload must be 12 atomic words");
static_assert(kClockWords == kClockPayloadWords + 1, "history slot keeps one index word");
static_assert(offsetof(IBMSPreviewMixClock, reserved) == 92, "clock must not contain padding");

Context *from_api(IBMSPreviewMixContext *ctx) { return reinterpret_cast<Context *>(ctx); }

Context *from_reader(IBMSPreviewMixReader *api) {
    Reader *reader = reinterpret_cast<Reader *>(api);
    if (reader == nullptr || reader->magic != kReaderMagic || reader->context == nullptr) {
        return nullptr;
    }
    return reader->context;
}

IBMSPreviewMixContext *to_api(Context *ctx) { return reinterpret_cast<IBMSPreviewMixContext *>(ctx); }

void touch_pages(void *p, size_t bytes) {
    if (!p || bytes == 0) {
        return;
    }
    volatile unsigned char *b = static_cast<volatile unsigned char *>(p);
    for (size_t i = 0; i < bytes; i += 4096) {
        b[i] = 0;
    }
    b[bytes - 1] = 0;
}

bool load_desired(Context *ctx, DesiredView *out, int tries) {
    for (int i = 0; i < tries; ++i) {
        uint64_t a = ctx->desired.seq.load(std::memory_order_seq_cst);
        if ((a & 1ull) != 0 || a == 0) {
            continue;
        }
        DesiredView v;
        v.serial = ctx->desired.serial.load(std::memory_order_seq_cst);
        v.epoch = ctx->desired.epoch.load(std::memory_order_seq_cst);
        v.session = ctx->desired.session.load(std::memory_order_seq_cst);
        v.requestHost = ctx->desired.requestHost.load(std::memory_order_seq_cst);
        v.seekRevision = ctx->desired.seekRevision.load(std::memory_order_seq_cst);
        v.rate = double_of(ctx->desired.rateBits.load(std::memory_order_seq_cst));
        v.seekChart = double_of(ctx->desired.chartBits.load(std::memory_order_seq_cst));
        v.kind = ctx->desired.kind.load(std::memory_order_seq_cst);
        v.paused = ctx->desired.paused.load(std::memory_order_seq_cst);
        v.stopped = ctx->desired.stopped.load(std::memory_order_seq_cst);
        std::atomic_thread_fence(std::memory_order_acquire);
        uint64_t b = ctx->desired.seq.load(std::memory_order_seq_cst);
        if (a == b && v.session == ctx->session) {
            *out = v;
            return true;
        }
    }
    return false;
}

bool load_ack(Context *ctx, AckView *out, int tries) {
    for (int i = 0; i < tries; ++i) {
        uint64_t a = ctx->ack.seq.load(std::memory_order_seq_cst);
        if ((a & 1ull) != 0 || a == 0) {
            continue;
        }
        AckView v;
        v.serial = ctx->ack.serial.load(std::memory_order_seq_cst);
        v.epoch = ctx->ack.epoch.load(std::memory_order_seq_cst);
        v.session = ctx->ack.session.load(std::memory_order_seq_cst);
        v.logicalFrame = ctx->ack.logicalFrame.load(std::memory_order_seq_cst);
        v.sourceSample = static_cast<int64_t>(ctx->ack.sourceSampleBits.load(std::memory_order_seq_cst));
        v.hostTicks = ctx->ack.hostTicks.load(std::memory_order_seq_cst);
        v.requestHost = ctx->ack.requestHost.load(std::memory_order_seq_cst);
        v.seekRevision = ctx->ack.seekRevision.load(std::memory_order_seq_cst);
        v.chart = double_of(ctx->ack.chartBits.load(std::memory_order_seq_cst));
        v.rate = double_of(ctx->ack.rateBits.load(std::memory_order_seq_cst));
        v.wall = double_of(ctx->ack.wallBits.load(std::memory_order_seq_cst));
        v.kind = ctx->ack.kind.load(std::memory_order_seq_cst);
        v.state = ctx->ack.state.load(std::memory_order_seq_cst);
        v.adopt = ctx->ack.adopt.load(std::memory_order_seq_cst);
        v.paused = ctx->ack.paused.load(std::memory_order_seq_cst);
        v.stopped = ctx->ack.stopped.load(std::memory_order_seq_cst);
        std::atomic_thread_fence(std::memory_order_acquire);
        uint64_t b = ctx->ack.seq.load(std::memory_order_seq_cst);
        if (a == b && v.session == ctx->session) {
            *out = v;
            return true;
        }
    }
    return false;
}

bool coherent(const DesiredView &desired, const AckView &ack) {
    return desired.serial == ack.serial && desired.epoch == ack.epoch && desired.session == ack.session &&
           desired.seekRevision == ack.seekRevision && desired.paused == ack.paused && desired.stopped == ack.stopped &&
           desired.requestHost == ack.requestHost && bits_of(desired.rate) == bits_of(ack.rate);
}

void publish_desired(Context *ctx) {
    uint64_t s = ctx->desired.seq.load(std::memory_order_seq_cst);
    ctx->desired.seq.store(s + 1, std::memory_order_seq_cst);
    ctx->desired.serial.store(ctx->cmdSerial, std::memory_order_seq_cst);
    ctx->desired.epoch.store(ctx->cmdEpoch, std::memory_order_seq_cst);
    ctx->desired.session.store(ctx->session, std::memory_order_seq_cst);
    ctx->desired.requestHost.store(ctx->cmdHost, std::memory_order_seq_cst);
    ctx->desired.seekRevision.store(ctx->seekRevision, std::memory_order_seq_cst);
    ctx->desired.rateBits.store(bits_of(ctx->cmdRate), std::memory_order_seq_cst);
    ctx->desired.chartBits.store(bits_of(ctx->seekChart), std::memory_order_seq_cst);
    ctx->desired.kind.store(ctx->cmdKind, std::memory_order_seq_cst);
    ctx->desired.paused.store(ctx->cmdPaused ? 1u : 0u, std::memory_order_seq_cst);
    ctx->desired.stopped.store(ctx->cmdStopped ? 1u : 0u, std::memory_order_seq_cst);
    ctx->desired.seq.store(stable_even(s), std::memory_order_seq_cst);
}

void publish_ack(Context *ctx, const AckView &ack) {
    uint64_t s = ctx->ack.seq.load(std::memory_order_seq_cst);
    ctx->ack.seq.store(s + 1, std::memory_order_seq_cst);
    ctx->ack.serial.store(ack.serial, std::memory_order_seq_cst);
    ctx->ack.epoch.store(ack.epoch, std::memory_order_seq_cst);
    ctx->ack.session.store(ack.session, std::memory_order_seq_cst);
    ctx->ack.logicalFrame.store(ack.logicalFrame, std::memory_order_seq_cst);
    ctx->ack.sourceSampleBits.store(static_cast<uint64_t>(ack.sourceSample), std::memory_order_seq_cst);
    ctx->ack.hostTicks.store(ack.hostTicks, std::memory_order_seq_cst);
    ctx->ack.requestHost.store(ack.requestHost, std::memory_order_seq_cst);
    ctx->ack.seekRevision.store(ack.seekRevision, std::memory_order_seq_cst);
    ctx->ack.chartBits.store(bits_of(ack.chart), std::memory_order_seq_cst);
    ctx->ack.rateBits.store(bits_of(ack.rate), std::memory_order_seq_cst);
    ctx->ack.wallBits.store(bits_of(ack.wall), std::memory_order_seq_cst);
    ctx->ack.kind.store(ack.kind, std::memory_order_seq_cst);
    ctx->ack.state.store(ack.state, std::memory_order_seq_cst);
    ctx->ack.adopt.store(ack.adopt, std::memory_order_seq_cst);
    ctx->ack.paused.store(ack.paused, std::memory_order_seq_cst);
    ctx->ack.stopped.store(ack.stopped, std::memory_order_seq_cst);
    ctx->ack.seq.store(stable_even(s), std::memory_order_seq_cst);
}

void publish_initial(Context *ctx, double rate, double chart) {
    ctx->cmdSerial = 0;
    ctx->cmdEpoch = 1;
    ctx->seekRevision = 0;
    ctx->cmdHost = 0;
    ctx->cmdRate = rate;
    ctx->seekChart = chart;
    ctx->cmdKind = IBMS_PREVIEW_MIX_CMD_NONE;
    ctx->cmdPaused = 0;
    ctx->cmdStopped = 0;
    ctx->ackedSerial = 0;
    ctx->ackedSeekRevision = 0;
    ctx->currentEpoch = 1;
    ctx->adoptGen = 0;
    ctx->spanSerial = 0;
    ctx->consumedChart = chart;
    ctx->consumedWall = 0;
    ctx->currentRate = rate;
    ctx->paused = 0;
    ctx->stopped = 0;
    ctx->everValid = 0;
    ctx->lastSourceEnd = INT64_MIN;
    ctx->read.store(0, std::memory_order_relaxed);
    ctx->write.store(0, std::memory_order_relaxed);
    if (ctx->meta != nullptr) {
        for (uint32_t i = 0; i < ctx->slotCount; ++i) {
            ctx->meta[i].frames = 0;
        }
    }
    publish_desired(ctx);
    AckView ack{};
    ack.serial = 0;
    ack.epoch = 1;
    ack.session = ctx->session;
    ack.chart = chart;
    ack.rate = rate;
    ack.wall = 0;
    ack.kind = IBMS_PREVIEW_MIX_CMD_NONE;
    ack.state = IBMS_PREVIEW_MIX_STATE_PLAYING;
    publish_ack(ctx, ack);
}

void note_command(Context *ctx, uint32_t kind, uint64_t host, bool bumpEpoch) {
    if (bumpEpoch) {
        ctx->cmdEpoch += 1;
    }
    ctx->cmdSerial += 1;
    ctx->cmdKind = kind;
    ctx->cmdHost = host;
    publish_desired(ctx);
}

bool meta_at(const Context *ctx, uint64_t frame, Meta *out) {
    uint32_t slot = static_cast<uint32_t>((frame / ctx->blockFrames) & ctx->slotMask);
    Meta meta = ctx->meta[slot];
    if (meta.frames == 0 || meta.session != ctx->session) {
        return false;
    }
    uint64_t into = frame - meta.beginFrame;
    if (into >= meta.frames) {
        return false;
    }
    *out = meta;
    return true;
}

void publish_slot(ClockSlot *slot, const IBMSPreviewMixClock &clock, uint64_t logIndex) {
    uint64_t words[kClockWords];
    std::memset(words, 0, sizeof(words));
    std::memcpy(words, &clock, sizeof(clock));
    words[kClockWords - 1] = logIndex;
    uint64_t s = slot->seq.load(std::memory_order_seq_cst);
    slot->seq.store(s + 1, std::memory_order_seq_cst);
    for (int i = 0; i < kClockWords; ++i) {
        slot->word[i].store(words[i], std::memory_order_seq_cst);
    }
    slot->seq.store(stable_even(s), std::memory_order_seq_cst);
}

bool load_slot(const ClockSlot *slot, IBMSPreviewMixClock *out, uint64_t expectIndex, bool checkIndex, int tries) {
    for (int t = 0; t < tries; ++t) {
        uint64_t a = slot->seq.load(std::memory_order_seq_cst);
        if ((a & 1ull) != 0 || a == 0) {
            continue;
        }
        uint64_t words[kClockWords];
        for (int i = 0; i < kClockWords; ++i) {
            words[i] = slot->word[i].load(std::memory_order_seq_cst);
        }
        std::atomic_thread_fence(std::memory_order_acquire);
        uint64_t b = slot->seq.load(std::memory_order_seq_cst);
        if (a != b) {
            continue;
        }
        if (checkIndex && words[kClockWords - 1] != expectIndex) {
            return false;
        }
        IBMSPreviewMixClock clock{};
        std::memcpy(&clock, words, sizeof(clock));
        if (clock.serial == 0) {
            return false;
        }
        *out = clock;
        return true;
    }
    return false;
}

void publish_span(Context *ctx, const IBMSPreviewMixClock &clock) {
    uint64_t index = ctx->logWrite.load(std::memory_order_relaxed);
    publish_slot(&ctx->log[index & ctx->logMask], clock, index);
    ctx->logWrite.store(index + 1, std::memory_order_release);
    publish_slot(&ctx->live, clock, index);
}

uint64_t discard_unread(Context *ctx) {
    uint64_t write = ctx->write.load(std::memory_order_acquire);
    uint64_t read = ctx->read.load(std::memory_order_relaxed);
    uint64_t n = write - read;
    if (n > ctx->capacity) {
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
        n = ctx->capacity;
        write = read + n;
    }
    ctx->read.store(write, std::memory_order_release);
    if (n != 0) {
        ctx->discardFrames.fetch_add(n, std::memory_order_relaxed);
    }
    return n;
}

void note_cost(Context *ctx, uint64_t started) {
    uint64_t ns = 0;
    if (ctx->timebase.denom != 0) {
        uint64_t dt = mach_absolute_time() - started;
        ns = static_cast<uint64_t>((static_cast<long double>(dt) * static_cast<long double>(ctx->timebase.numer)) /
                                   static_cast<long double>(ctx->timebase.denom));
    }
    uint64_t slot = ctx->timingWrite.fetch_add(1, std::memory_order_relaxed);
    ctx->timing[slot & (kTimingCap - 1u)] = ns > 0xffffffffull ? 0xffffffffu : static_cast<uint32_t>(ns);
    uint64_t prev = ctx->nsMax.load(std::memory_order_relaxed);
    if (ns > prev) {
        ctx->nsMax.store(ns, std::memory_order_relaxed);
    }
}

bool storage_ok(const IBMSPreviewMixOutput *output) {
    if (output == nullptr || output->buffers == nullptr || output->frames == 0) {
        return false;
    }
    if (output->layout == IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED) {
        if (output->bufferCount != 1) {
            return false;
        }
        const IBMSPreviewMixBuffer &b = output->buffers[0];
        return b.data != nullptr && b.channels == 2 && b.capacityFrames >= output->frames;
    }
    if (output->layout == IBMS_PREVIEW_MIX_LAYOUT_PLANAR) {
        if (output->bufferCount != 2) {
            return false;
        }
        for (uint32_t i = 0; i < 2; ++i) {
            const IBMSPreviewMixBuffer &b = output->buffers[i];
            if (b.data == nullptr || b.channels != 1 || b.capacityFrames < output->frames) {
                return false;
            }
        }
        return true;
    }
    return false;
}

void zero_output(IBMSPreviewMixOutput *output) {
    if (output->layout == IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED) {
        IBMSPreviewMixBuffer &b = output->buffers[0];
        std::memset(b.data, 0, sizeof(float) * b.channels * output->frames);
        return;
    }
    if (output->layout == IBMS_PREVIEW_MIX_LAYOUT_PLANAR) {
        for (uint32_t i = 0; i < 2; ++i) {
            IBMSPreviewMixBuffer &b = output->buffers[i];
            std::memset(b.data, 0, sizeof(float) * b.channels * output->frames);
        }
    }
}

void write_frame(IBMSPreviewMixOutput *output, uint32_t frame, float left, float right) {
    if (output->layout == IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED) {
        IBMSPreviewMixBuffer &b = output->buffers[0];
        b.data[frame * b.channels] = left;
        b.data[frame * b.channels + 1] = right;
        return;
    }
    IBMSPreviewMixBuffer &l = output->buffers[0];
    IBMSPreviewMixBuffer &r = output->buffers[1];
    l.data[frame * l.channels] = left;
    r.data[frame * r.channels] = right;
}

void load_frame(const Context *ctx, uint64_t frame, float *left, float *right) {
    const float *s = ctx->samples + ((frame & ctx->mask) * 2u);
    *left = s[0];
    *right = s[1];
}

IBMSPreviewMixClock blank_clock(Context *ctx, const IBMSPreviewMixTime *time, uint32_t offset, uint32_t frames,
                                uint32_t state) {
    IBMSPreviewMixClock clock{};
    ctx->spanSerial += 1;
    clock.serial = ctx->spanSerial;
    clock.session = ctx->session;
    clock.epoch = ctx->currentEpoch;
    clock.sourceSample = time->sourceSample + static_cast<int64_t>(offset);
    clock.hostTicks = time->hostTicks;
    clock.logicalFrame = ctx->read.load(std::memory_order_relaxed);
    clock.chartStart = ctx->consumedChart;
    clock.rate = 0;
    clock.wallStart = ctx->consumedWall;
    clock.frameCount = frames;
    clock.validFrames = 0;
    clock.hostFrameOffset = offset;
    clock.state = state;
    clock.timeFlags = time->flags;
    return clock;
}

void note_source_end(Context *ctx, const IBMSPreviewMixTime *time, uint32_t frames) {
    if (time == nullptr || (time->flags & IBMS_PREVIEW_MIX_TIME_SOURCE_SAMPLE_VALID) == 0) {
        return;
    }
    if (ctx->lastSourceEnd != INT64_MIN && time->sourceSample < ctx->lastSourceEnd) {
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
    }
    ctx->lastSourceEnd = time->sourceSample + static_cast<int64_t>(frames);
}

bool retired_now(const Context *ctx) { return ctx->retired.load(std::memory_order_seq_cst) != 0; }

struct Pending {
    double chartStart;
    double rate;
    double wallStart;
    uint64_t logicalFrame;
    int64_t sourceSample;
    uint32_t hostFrameOffset;
    uint32_t frameCount;
    uint32_t validFrames;
};

int render_retired(Context *ctx, const IBMSPreviewMixTime *time, IBMSPreviewMixOutput *output) {
    zero_output(output);
    publish_span(ctx, blank_clock(ctx, time, 0, output->frames, IBMS_PREVIEW_MIX_STATE_RETIRED));
    ctx->retiredSilenceFrames.fetch_add(output->frames, std::memory_order_relaxed);
    return IBMS_PREVIEW_MIX_OK;
}

int command_common(Context *ctx) {
    if (ctx == nullptr) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (retired_now(ctx)) {
        return IBMS_PREVIEW_MIX_ERR_RETIRED;
    }
    return IBMS_PREVIEW_MIX_OK;
}

} // namespace

void ibms_preview_mix_config_init(IBMSPreviewMixConfig *config) {
    if (config == nullptr) {
        return;
    }
    config->session = 0;
    config->sourceRate = IBMS_PREVIEW_MIX_SOURCE_RATE;
    config->capacityFrames = 4096;
    config->blockFrames = 256;
    config->logCapacity = 1024;
}

IBMSPreviewMixContext *ibms_preview_mix_create(const IBMSPreviewMixConfig *config) {
    if (config == nullptr || config->sourceRate != IBMS_PREVIEW_MIX_SOURCE_RATE) {
        return nullptr;
    }
    uint32_t logCapacity = config->logCapacity == 0 ? 1024u : config->logCapacity;
    if (!power_of_two(config->capacityFrames) || config->capacityFrames < 256 || config->capacityFrames > 65536 ||
        !power_of_two(config->blockFrames) || config->blockFrames < 32 ||
        config->capacityFrames % config->blockFrames != 0 || !power_of_two(logCapacity) || logCapacity < 2 ||
        logCapacity > 8192) {
        return nullptr;
    }
    std::atomic<uint64_t> probe{0};
    if (!probe.is_lock_free()) {
        return nullptr;
    }
    Context *ctx = new (std::nothrow) Context();
    if (ctx == nullptr) {
        return nullptr;
    }
    ctx->capacity = config->capacityFrames;
    ctx->mask = config->capacityFrames - 1u;
    ctx->blockFrames = config->blockFrames;
    ctx->slotCount = config->capacityFrames / config->blockFrames;
    ctx->slotMask = ctx->slotCount - 1u;
    ctx->logCapacity = logCapacity;
    ctx->logMask = logCapacity - 1u;
    ctx->sourceRate = IBMS_PREVIEW_MIX_SOURCE_RATE;
    ctx->lockFree = 1;
    ctx->session = config->session != 0 ? config->session : g_next_session.fetch_add(1, std::memory_order_relaxed);
    mach_timebase_info(&ctx->timebase);
    ctx->samples = new (std::nothrow) float[static_cast<size_t>(ctx->capacity) * 2u]();
    ctx->meta = new (std::nothrow) Meta[ctx->slotCount]();
    ctx->log = new (std::nothrow) ClockSlot[ctx->logCapacity];
    ctx->timing = new (std::nothrow) uint32_t[kTimingCap]();
    if (ctx->samples == nullptr || ctx->meta == nullptr || ctx->log == nullptr || ctx->timing == nullptr) {
        delete ctx;
        return nullptr;
    }
    touch_pages(ctx->samples, sizeof(float) * static_cast<size_t>(ctx->capacity) * 2u);
    touch_pages(ctx->meta, sizeof(Meta) * ctx->slotCount);
    touch_pages(ctx->timing, sizeof(uint32_t) * kTimingCap);
    publish_initial(ctx, 1.0, 0.0);
    return to_api(ctx);
}

IBMSPreviewMixRegistration *ibms_preview_mix_registration_retain(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr || retired_now(ctx)) {
        return nullptr;
    }
    Registration *reg = new (std::nothrow) Registration();
    if (reg == nullptr) {
        return nullptr;
    }
    reg->context = ctx;
    reg->magic = kRegMagic;
    ctx->registrationCount.fetch_add(1, std::memory_order_release);
    if (retired_now(ctx)) {
        ctx->registrationCount.fetch_sub(1, std::memory_order_release);
        reg->magic = 0;
        reg->context = nullptr;
        delete reg;
        return nullptr;
    }
    return reinterpret_cast<IBMSPreviewMixRegistration *>(reg);
}

IBMSPreviewMixReader *ibms_preview_mix_reader_retain(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr || ctx->queriesClosed.load(std::memory_order_seq_cst) != 0) {
        return nullptr;
    }
    Reader *reader = new (std::nothrow) Reader();
    if (reader == nullptr) {
        return nullptr;
    }
    reader->context = ctx;
    reader->magic = kReaderMagic;
    ctx->readerCount.fetch_add(1, std::memory_order_release);
    if (ctx->queriesClosed.load(std::memory_order_seq_cst) != 0) {
        ctx->readerCount.fetch_sub(1, std::memory_order_release);
        reader->magic = 0;
        reader->context = nullptr;
        delete reader;
        return nullptr;
    }
    return reinterpret_cast<IBMSPreviewMixReader *>(reader);
}

void ibms_preview_mix_reader_release(IBMSPreviewMixReader *api) {
    Reader *reader = reinterpret_cast<Reader *>(api);
    if (reader == nullptr || reader->magic != kReaderMagic || reader->context == nullptr) {
        return;
    }
    Context *ctx = reader->context;
    reader->magic = 0;
    reader->context = nullptr;
    ctx->readerCount.fetch_sub(1, std::memory_order_release);
    delete reader;
}

void ibms_preview_mix_close_queries(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr) {
        return;
    }
    ctx->queriesClosed.store(1, std::memory_order_seq_cst);
}

void ibms_preview_mix_registration_release(IBMSPreviewMixRegistration *api) {
    Registration *reg = reinterpret_cast<Registration *>(api);
    if (reg == nullptr || reg->magic != kRegMagic || reg->context == nullptr) {
        return;
    }
    Context *ctx = reg->context;
    reg->magic = 0;
    reg->context = nullptr;
    ctx->registrationCount.fetch_sub(1, std::memory_order_release);
    delete reg;
}

void ibms_preview_mix_begin_retire(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr) {
        return;
    }
    ctx->retired.store(1, std::memory_order_seq_cst);
}

void ibms_preview_mix_note_worker_exited(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr) {
        return;
    }
    ctx->workerExited.store(1, std::memory_order_release);
}

int ibms_preview_mix_context_release(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (ctx->retired.load(std::memory_order_seq_cst) == 0) {
        return IBMS_PREVIEW_MIX_ERR_STATE;
    }
    if (ctx->queriesClosed.load(std::memory_order_seq_cst) == 0 ||
        ctx->readerCount.load(std::memory_order_acquire) != 0 ||
        ctx->registrationCount.load(std::memory_order_acquire) != 0 ||
        ctx->workerExited.load(std::memory_order_acquire) == 0) {
        return IBMS_PREVIEW_MIX_ERR_BUSY;
    }
    delete ctx;
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_prepare(IBMSPreviewMixContext *api, double rate, double chart) {
    Context *ctx = from_api(api);
    int gate = command_common(ctx);
    if (gate != IBMS_PREVIEW_MIX_OK) {
        return gate;
    }
    if (!rate_ok(rate) || !std::isfinite(chart)) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (ctx->callbacks.load(std::memory_order_acquire) != 0) {
        return IBMS_PREVIEW_MIX_ERR_STATE;
    }
    publish_initial(ctx, rate, chart);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_command_rate(IBMSPreviewMixContext *api, double rate, uint64_t requestHost) {
    Context *ctx = from_api(api);
    int gate = command_common(ctx);
    if (gate != IBMS_PREVIEW_MIX_OK) {
        return gate;
    }
    if (!rate_ok(rate)) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    ctx->cmdRate = rate;
    note_command(ctx, IBMS_PREVIEW_MIX_CMD_RATE, requestHost, true);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_command_pause(IBMSPreviewMixContext *api, uint64_t requestHost) {
    Context *ctx = from_api(api);
    int gate = command_common(ctx);
    if (gate != IBMS_PREVIEW_MIX_OK) {
        return gate;
    }
    ctx->cmdPaused = 1;
    note_command(ctx, IBMS_PREVIEW_MIX_CMD_PAUSE, requestHost, false);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_command_resume(IBMSPreviewMixContext *api, uint64_t requestHost) {
    Context *ctx = from_api(api);
    int gate = command_common(ctx);
    if (gate != IBMS_PREVIEW_MIX_OK) {
        return gate;
    }
    ctx->cmdPaused = 0;
    ctx->cmdStopped = 0;
    note_command(ctx, IBMS_PREVIEW_MIX_CMD_RESUME, requestHost, false);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_command_seek(IBMSPreviewMixContext *api, double chart, uint64_t requestHost) {
    Context *ctx = from_api(api);
    int gate = command_common(ctx);
    if (gate != IBMS_PREVIEW_MIX_OK) {
        return gate;
    }
    if (!std::isfinite(chart)) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    ctx->seekRevision += 1;
    ctx->seekChart = chart;
    note_command(ctx, IBMS_PREVIEW_MIX_CMD_SEEK, requestHost, true);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_command_stop(IBMSPreviewMixContext *api, uint64_t requestHost) {
    Context *ctx = from_api(api);
    int gate = command_common(ctx);
    if (gate != IBMS_PREVIEW_MIX_OK) {
        return gate;
    }
    ctx->cmdPaused = 1;
    ctx->cmdStopped = 1;
    note_command(ctx, IBMS_PREVIEW_MIX_CMD_STOP, requestHost, true);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_poll(IBMSPreviewMixContext *api, IBMSPreviewMixProduce *state) {
    Context *ctx = from_api(api);
    if (ctx == nullptr || state == nullptr) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    state->resetCursor = 0;
    state->canWrite = 0;
    if (retired_now(ctx)) {
        state->paused = 1;
        return IBMS_PREVIEW_MIX_ERR_RETIRED;
    }
    DesiredView desired;
    AckView ack;
    if (!load_desired(ctx, &desired, kReaderTries) || !load_ack(ctx, &ack, kReaderTries) || !coherent(desired, ack)) {
        return IBMS_PREVIEW_MIX_ERR_BUSY;
    }
    if (desired.serial != state->appliedSerial) {
        state->appliedSerial = ack.serial;
        state->epoch = ack.epoch;
        if (ack.rate > 0) {
            state->rate = ack.rate;
        }
        state->paused = ack.paused ? 1 : 0;
        state->stopped = ack.stopped ? 1 : 0;
        if (ack.adopt != state->seenAdopt) {
            state->chart = ack.chart;
            state->wall = ack.wall;
            state->resetCursor = 1;
            state->seenAdopt = ack.adopt;
        }
    } else if (state->epoch == 0) {
        state->appliedSerial = ack.serial;
        state->epoch = ack.epoch;
        state->chart = ack.chart;
        state->wall = ack.wall;
        state->rate = ack.rate;
        state->paused = ack.paused ? 1 : 0;
        state->stopped = ack.stopped ? 1 : 0;
        state->seenAdopt = ack.adopt;
        state->resetCursor = 1;
    } else {
        state->paused = ack.paused ? 1 : 0;
        state->stopped = ack.stopped ? 1 : 0;
        if (state->rate <= 0 && ack.rate > 0) {
            state->rate = ack.rate;
        }
    }
    state->canWrite = (state->paused || state->stopped) ? 0 : 1;
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_write(IBMSPreviewMixContext *api, const float *interleavedStereo, uint32_t frames, double chartStart,
                           double rate, uint64_t epoch) {
    Context *ctx = from_api(api);
    if (ctx == nullptr || interleavedStereo == nullptr || frames != ctx->blockFrames || !rate_ok(rate) ||
        !std::isfinite(chartStart)) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (retired_now(ctx)) {
        return IBMS_PREVIEW_MIX_ERR_RETIRED;
    }
    DesiredView desired;
    AckView ack;
    if (!load_desired(ctx, &desired, kCallbackTries) || !load_ack(ctx, &ack, kCallbackTries) || !coherent(desired, ack)) {
        return IBMS_PREVIEW_MIX_ERR_BUSY;
    }
    if (ack.paused || ack.stopped) {
        return IBMS_PREVIEW_MIX_ERR_STATE;
    }
    if (epoch != ack.epoch) {
        return IBMS_PREVIEW_MIX_ERR_EPOCH;
    }
    uint64_t write = ctx->write.load(std::memory_order_relaxed);
    uint64_t read = ctx->read.load(std::memory_order_acquire);
    if ((write & (ctx->blockFrames - 1u)) != 0) {
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
        return IBMS_PREVIEW_MIX_ERR_STATE;
    }
    uint64_t fill = write - read;
    if (fill > ctx->capacity || fill + frames > ctx->capacity) {
        ctx->overrunWrites.fetch_add(1, std::memory_order_relaxed);
        return IBMS_PREVIEW_MIX_ERR_FULL;
    }
    Meta meta;
    meta.beginFrame = write;
    meta.epoch = epoch;
    meta.session = ctx->session;
    meta.chartStart = chartStart;
    meta.rate = rate;
    meta.frames = frames;
    uint32_t slot = static_cast<uint32_t>((write / ctx->blockFrames) & ctx->slotMask);
    for (uint32_t i = 0; i < frames; ++i) {
        float *dst = ctx->samples + (((write + i) & ctx->mask) * 2u);
        dst[0] = interleavedStereo[i * 2u];
        dst[1] = interleavedStereo[i * 2u + 1];
    }
    ctx->meta[slot] = meta;
    if (retired_now(ctx)) {
        return IBMS_PREVIEW_MIX_ERR_RETIRED;
    }
    if (!load_desired(ctx, &desired, kCallbackTries) || !load_ack(ctx, &ack, kCallbackTries) || !coherent(desired, ack) ||
        epoch != ack.epoch) {
        return IBMS_PREVIEW_MIX_ERR_EPOCH;
    }
    if (ack.paused || ack.stopped) {
        return IBMS_PREVIEW_MIX_ERR_STATE;
    }
    ctx->write.store(write + frames, std::memory_order_release);
    return IBMS_PREVIEW_MIX_OK;
}

uint64_t ibms_preview_mix_fill_frames(IBMSPreviewMixContext *api) {
    Context *ctx = from_api(api);
    if (ctx == nullptr) {
        return 0;
    }
    uint64_t fill = ctx->write.load(std::memory_order_acquire) - ctx->read.load(std::memory_order_acquire);
    return fill > ctx->capacity ? ctx->capacity : fill;
}

int ibms_preview_mix_read_ack(IBMSPreviewMixReader *api, IBMSPreviewMixAck *out) {
    Context *ctx = from_reader(api);
    if (ctx == nullptr || out == nullptr) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    AckView ack;
    if (!load_ack(ctx, &ack, kReaderTries)) {
        return IBMS_PREVIEW_MIX_ERR_BUSY;
    }
    out->serial = ack.serial;
    out->epoch = ack.epoch;
    out->session = ack.session;
    out->logicalFrame = ack.logicalFrame;
    out->sourceSample = ack.sourceSample;
    out->hostTicks = ack.hostTicks;
    out->requestHost = ack.requestHost;
    out->seekRevision = ack.seekRevision;
    out->chart = ack.chart;
    out->rate = ack.rate;
    out->wall = ack.wall;
    out->kind = ack.kind;
    out->state = ack.state;
    out->adopt = ack.adopt;
    out->paused = ack.paused;
    out->stopped = ack.stopped;
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_render(IBMSPreviewMixRegistration *apiReg, const IBMSPreviewMixTime *time, IBMSPreviewMixOutput *output) {
    Registration *reg = reinterpret_cast<Registration *>(apiReg);
    if (reg == nullptr || reg->magic != kRegMagic || reg->context == nullptr) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    Context *ctx = reg->context;
    uint64_t started = mach_absolute_time();
    ctx->callbacks.fetch_add(1, std::memory_order_relaxed);
    if (!storage_ok(output)) {
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
        note_cost(ctx, started);
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    const bool timeOk = time != nullptr &&
                        (time->flags & (IBMS_PREVIEW_MIX_TIME_SOURCE_SAMPLE_VALID | IBMS_PREVIEW_MIX_TIME_HOST_VALID)) ==
                            (IBMS_PREVIEW_MIX_TIME_SOURCE_SAMPLE_VALID | IBMS_PREVIEW_MIX_TIME_HOST_VALID);
    if (output->frames > ctx->capacity || output->frames > IBMS_PREVIEW_MIX_MAX_CALLBACK_FRAMES) {
        zero_output(output);
        note_cost(ctx, started);
        return IBMS_PREVIEW_MIX_ERR_UNSUPPORTED;
    }
    if (!timeOk) {
        zero_output(output);
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
        note_cost(ctx, started);
        return IBMS_PREVIEW_MIX_OK;
    }
    note_source_end(ctx, time, output->frames);
    if ((time->flags & IBMS_PREVIEW_MIX_TIME_RATE_SCALAR_VALID) != 0 &&
        (time->rateScalar < 0.99f || time->rateScalar > 1.01f)) {
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
    }
    zero_output(output);
    if (retired_now(ctx)) {
        int rc = render_retired(ctx, time, output);
        note_cost(ctx, started);
        return rc;
    }

    DesiredView desired;
    bool have = load_desired(ctx, &desired, kCallbackTries);
    bool flush = false;
    bool hasAck = false;
    double chart = ctx->consumedChart;
    double wall = ctx->consumedWall;
    double rate = ctx->currentRate;
    uint64_t epoch = ctx->currentEpoch;
    uint64_t adopt = ctx->adoptGen;
    int paused = ctx->paused;
    int stopped = ctx->stopped;
    if (have && desired.serial != ctx->ackedSerial) {
        if (desired.seekRevision != ctx->ackedSeekRevision) {
            chart = desired.seekChart;
            wall = 0;
        }
        if (desired.rate > 0) {
            rate = desired.rate;
        }
        paused = desired.paused ? 1 : 0;
        stopped = desired.stopped ? 1 : 0;
        if (desired.epoch != epoch) {
            flush = true;
            epoch = desired.epoch;
            adopt += 1;
        }
        hasAck = true;
    }
    if (retired_now(ctx)) {
        int rc = render_retired(ctx, time, output);
        note_cost(ctx, started);
        return rc;
    }

    if (flush) {
        discard_unread(ctx);
        ctx->currentEpoch = epoch;
        ctx->adoptGen = adopt;
    }
    ctx->currentRate = rate;
    ctx->paused = paused;
    ctx->stopped = stopped;
    ctx->consumedChart = chart;
    ctx->consumedWall = wall;
    uint32_t ackState = flush ? IBMS_PREVIEW_MIX_STATE_FLUSH : IBMS_PREVIEW_MIX_STATE_PLAYING;
    if (paused) {
        ackState |= IBMS_PREVIEW_MIX_STATE_PAUSED;
    }
    if (stopped) {
        ackState |= IBMS_PREVIEW_MIX_STATE_STOPPED;
    }
    if (hasAck) {
        AckView ack{};
        ack.serial = desired.serial;
        ack.epoch = desired.epoch;
        ack.session = ctx->session;
        ack.logicalFrame = ctx->read.load(std::memory_order_relaxed);
        ack.sourceSample = time->sourceSample;
        ack.hostTicks = time->hostTicks;
        ack.requestHost = desired.requestHost;
        ack.seekRevision = desired.seekRevision;
        ack.chart = ctx->consumedChart;
        ack.rate = desired.rate;
        ack.wall = ctx->consumedWall;
        ack.kind = desired.kind;
        ack.adopt = ctx->adoptGen;
        ack.paused = desired.paused;
        ack.stopped = desired.stopped;
        ack.state = ackState;
        publish_ack(ctx, ack);
        ctx->ackedSerial = desired.serial;
        ctx->ackedSeekRevision = desired.seekRevision;
    }
    if (flush) {
        publish_span(ctx, blank_clock(ctx, time, 0, output->frames, ackState));
        ctx->flushSpans.fetch_add(1, std::memory_order_relaxed);
        ctx->flushSilenceFrames.fetch_add(output->frames, std::memory_order_relaxed);
        note_cost(ctx, started);
        return IBMS_PREVIEW_MIX_OK;
    }
    if (ctx->stopped) {
        publish_span(ctx, blank_clock(ctx, time, 0, output->frames,
                                      IBMS_PREVIEW_MIX_STATE_STOPPED | IBMS_PREVIEW_MIX_STATE_PAUSED));
        ctx->stopFrames.fetch_add(output->frames, std::memory_order_relaxed);
        note_cost(ctx, started);
        return IBMS_PREVIEW_MIX_OK;
    }
    if (ctx->paused) {
        publish_span(ctx, blank_clock(ctx, time, 0, output->frames, IBMS_PREVIEW_MIX_STATE_PAUSED));
        ctx->pauseFrames.fetch_add(output->frames, std::memory_order_relaxed);
        note_cost(ctx, started);
        return IBMS_PREVIEW_MIX_OK;
    }

    uint64_t read = ctx->read.load(std::memory_order_relaxed);
    uint64_t write = ctx->write.load(std::memory_order_acquire);
    uint64_t available = write - read;
    if (available > ctx->capacity) {
        ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
        available = 0;
    }
    uint64_t skipped = 0;
    while (skipped < available && skipped < ctx->capacity) {
        Meta meta;
        uint64_t frame = read + skipped;
        if (meta_at(ctx, frame, &meta) && meta.epoch == ctx->currentEpoch) {
            break;
        }
        uint32_t step = 1;
        if (meta_at(ctx, frame, &meta)) {
            uint64_t left = meta.frames - (frame - meta.beginFrame);
            if (left > 0) {
                step = static_cast<uint32_t>(left > 0xffffffffull ? 0xffffffffull : left);
            }
        } else {
            uint32_t into = static_cast<uint32_t>(frame & (ctx->blockFrames - 1u));
            step = ctx->blockFrames - into;
        }
        if (step == 0) {
            step = 1;
        }
        if (static_cast<uint64_t>(step) > available - skipped) {
            step = static_cast<uint32_t>(available - skipped);
        }
        skipped += step;
    }
    const uint64_t playable = available - skipped;
    Pending pending[kMaxPending];
    uint32_t npending = 0;
    uint32_t produced = 0;
    while (produced < output->frames && static_cast<uint64_t>(produced) < playable) {
        if (npending >= kMaxPending) {
            ctx->protocolFaults.fetch_add(1, std::memory_order_relaxed);
            break;
        }
        uint64_t frame = read + skipped + produced;
        Meta meta;
        if (!meta_at(ctx, frame, &meta) || meta.epoch != ctx->currentEpoch) {
            break;
        }
        double origin = meta.chartStart + static_cast<double>(frame - meta.beginFrame) * meta.rate / ctx->sourceRate;
        uint32_t run = 0;
        while (produced + run < output->frames && static_cast<uint64_t>(produced + run) < playable) {
            uint64_t f = read + skipped + produced + run;
            if ((f - meta.beginFrame) >= meta.frames) {
                Meta next;
                if (!meta_at(ctx, f, &next) || next.epoch != ctx->currentEpoch) {
                    break;
                }
                double expect = origin + static_cast<double>(run) * meta.rate / ctx->sourceRate;
                if (next.rate != meta.rate || std::fabs(next.chartStart - expect) > 1e-9) {
                    break;
                }
                meta = next;
            }
            float left = 0;
            float right = 0;
            load_frame(ctx, f, &left, &right);
            write_frame(output, produced + run, left, right);
            run += 1;
        }
        if (run == 0) {
            break;
        }
        Pending &span = pending[npending++];
        span.chartStart = origin;
        span.rate = meta.rate;
        span.wallStart = ctx->consumedWall + static_cast<double>(produced) / ctx->sourceRate;
        span.logicalFrame = frame;
        span.sourceSample = time->sourceSample + static_cast<int64_t>(produced);
        span.hostFrameOffset = produced;
        span.frameCount = run;
        span.validFrames = run;
        produced += run;
    }
    if (retired_now(ctx)) {
        int rc = render_retired(ctx, time, output);
        note_cost(ctx, started);
        return rc;
    }

    ctx->read.store(read + skipped + produced, std::memory_order_release);
    if (skipped != 0) {
        ctx->discardFrames.fetch_add(skipped, std::memory_order_relaxed);
    }
    double endChart = ctx->consumedChart;
    double endWall = ctx->consumedWall;
    for (uint32_t i = 0; i < npending; ++i) {
        IBMSPreviewMixClock clock{};
        ctx->spanSerial += 1;
        clock.serial = ctx->spanSerial;
        clock.session = ctx->session;
        clock.epoch = ctx->currentEpoch;
        clock.sourceSample = pending[i].sourceSample;
        clock.hostTicks = time->hostTicks;
        clock.logicalFrame = pending[i].logicalFrame;
        clock.chartStart = pending[i].chartStart;
        clock.rate = pending[i].rate;
        clock.wallStart = pending[i].wallStart;
        clock.frameCount = pending[i].frameCount;
        clock.validFrames = pending[i].validFrames;
        clock.hostFrameOffset = pending[i].hostFrameOffset;
        clock.state = IBMS_PREVIEW_MIX_STATE_PLAYING;
        clock.timeFlags = time->flags;
        publish_span(ctx, clock);
        endChart = clock.chartStart + static_cast<double>(clock.validFrames) * clock.rate / ctx->sourceRate;
        endWall = clock.wallStart + static_cast<double>(clock.validFrames) / ctx->sourceRate;
        ctx->currentRate = clock.rate;
        ctx->everValid = 1;
    }
    if (npending != 0) {
        ctx->consumedChart = endChart;
        ctx->consumedWall = endWall;
    }
    uint32_t missing = output->frames - produced;
    if (missing != 0) {
        IBMSPreviewMixClock clock = blank_clock(ctx, time, produced, missing,
                                                 ctx->everValid ? IBMS_PREVIEW_MIX_STATE_UNDERRUN : IBMS_PREVIEW_MIX_STATE_PRIME);
        clock.logicalFrame = read + skipped + produced;
        publish_span(ctx, clock);
        if (ctx->everValid) {
            ctx->realUnderrunFrames.fetch_add(missing, std::memory_order_relaxed);
        } else {
            ctx->primeSilenceFrames.fetch_add(missing, std::memory_order_relaxed);
        }
    }
    note_cost(ctx, started);
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_mix_live(IBMSPreviewMixReader *api, IBMSPreviewMixClock *out) {
    Context *ctx = from_reader(api);
    if (ctx == nullptr || out == nullptr) {
        return 0;
    }
    IBMSPreviewMixClock clock;
    if (!load_slot(&ctx->live, &clock, 0, false, kReaderTries) || clock.session != ctx->session) {
        return 0;
    }
    *out = clock;
    return 1;
}

int ibms_preview_mix_clock_at_source_sample(IBMSPreviewMixReader *api, int64_t sourceSample, IBMSPreviewMixClock *out) {
    Context *ctx = from_reader(api);
    if (ctx == nullptr || out == nullptr) {
        return 0;
    }
    uint64_t count = ctx->logWrite.load(std::memory_order_acquire);
    uint64_t start = count > ctx->logCapacity ? count - ctx->logCapacity : 0;
    for (uint64_t i = count; i > start; --i) {
        IBMSPreviewMixClock clock;
        if (!load_slot(&ctx->log[(i - 1) & ctx->logMask], &clock, i - 1, true, kReaderTries)) {
            continue;
        }
        if (clock.session != ctx->session || clock.frameCount == 0) {
            continue;
        }
        int64_t end = clock.sourceSample + static_cast<int64_t>(clock.frameCount);
        if (sourceSample >= clock.sourceSample && sourceSample < end) {
            *out = clock;
            return 1;
        }
    }
    return 0;
}

uint32_t ibms_preview_mix_copy_clocks(IBMSPreviewMixReader *api, IBMSPreviewMixClock *dst, uint32_t capacity) {
    Context *ctx = from_reader(api);
    if (ctx == nullptr || dst == nullptr || capacity == 0) {
        return 0;
    }
    uint64_t count = ctx->logWrite.load(std::memory_order_acquire);
    uint64_t start = count > ctx->logCapacity ? count - ctx->logCapacity : 0;
    uint32_t n = 0;
    for (uint64_t i = start; i < count && n < capacity; ++i) {
        IBMSPreviewMixClock clock;
        if (!load_slot(&ctx->log[i & ctx->logMask], &clock, i, true, kReaderTries)) {
            continue;
        }
        if (clock.serial == 0 || clock.session != ctx->session) {
            continue;
        }
        dst[n++] = clock;
    }
    return n;
}

int ibms_preview_mix_span_map(IBMSPreviewMixReader *api, const IBMSPreviewMixClock *span, uint32_t index, double *hostSeconds,
                              double *chart, double *wall, int *advanced) {
    Context *ctx = from_reader(api);
    if (ctx == nullptr || span == nullptr || span->serial == 0 || index >= span->frameCount || ctx->sourceRate <= 0) {
        return 0;
    }
    if (hostSeconds != nullptr) {
        *hostSeconds = ibms_preview_mix_ticks_to_seconds(api, span->hostTicks) +
                       static_cast<double>(span->hostFrameOffset + index) / ctx->sourceRate;
    }
    uint32_t used = index < span->validFrames ? index : span->validFrames;
    if (chart != nullptr) {
        *chart = span->chartStart + static_cast<double>(used) * span->rate / ctx->sourceRate;
    }
    if (wall != nullptr) {
        *wall = span->wallStart + static_cast<double>(used) / ctx->sourceRate;
    }
    if (advanced != nullptr) {
        *advanced = index < span->validFrames ? 1 : 0;
    }
    return 1;
}

double ibms_preview_mix_ticks_to_seconds(IBMSPreviewMixReader *api, uint64_t ticks) {
    Context *ctx = from_reader(api);
    if (ctx == nullptr || ctx->timebase.denom == 0) {
        return 0;
    }
    long double nanos = static_cast<long double>(ticks) * static_cast<long double>(ctx->timebase.numer) /
                        static_cast<long double>(ctx->timebase.denom);
    return static_cast<double>(nanos / 1e9L);
}

uint64_t ibms_preview_mix_host_ticks(void) { return mach_absolute_time(); }

void ibms_preview_mix_stats(IBMSPreviewMixReader *api, IBMSPreviewMixStats *out) {
    if (out == nullptr) {
        return;
    }
    std::memset(out, 0, sizeof(*out));
    Context *ctx = from_reader(api);
    if (ctx == nullptr) {
        return;
    }
    out->realUnderrunFrames = ctx->realUnderrunFrames.load(std::memory_order_relaxed);
    out->primeSilenceFrames = ctx->primeSilenceFrames.load(std::memory_order_relaxed);
    out->discardFrames = ctx->discardFrames.load(std::memory_order_relaxed);
    out->pauseFrames = ctx->pauseFrames.load(std::memory_order_relaxed);
    out->stopFrames = ctx->stopFrames.load(std::memory_order_relaxed);
    out->flushSpans = ctx->flushSpans.load(std::memory_order_relaxed);
    out->flushSilenceFrames = ctx->flushSilenceFrames.load(std::memory_order_relaxed);
    out->retiredSilenceFrames = ctx->retiredSilenceFrames.load(std::memory_order_relaxed);
    out->protocolFaults = ctx->protocolFaults.load(std::memory_order_relaxed);
    out->overrunWrites = ctx->overrunWrites.load(std::memory_order_relaxed);
    out->callbacks = ctx->callbacks.load(std::memory_order_relaxed);
    out->callbackNsMax = ctx->nsMax.load(std::memory_order_relaxed);
    uint64_t logWrite = ctx->logWrite.load(std::memory_order_acquire);
    out->logWrite = logWrite;
    out->logOverflow = logWrite > ctx->logCapacity ? logWrite - ctx->logCapacity : 0;
    out->capacityFrames = ctx->capacity;
    out->blockFrames = ctx->blockFrames;
    out->logCapacity = ctx->logCapacity;
    out->lockFree = ctx->lockFree;
    out->session = ctx->session;
    out->sourceRate = ctx->sourceRate;
    out->consumedChart = ctx->consumedChart;
    out->consumedWall = ctx->consumedWall;
    out->registrationCount = ctx->registrationCount.load(std::memory_order_relaxed);
    out->retired = ctx->retired.load(std::memory_order_relaxed);
    out->workerExited = ctx->workerExited.load(std::memory_order_relaxed);
    uint64_t timingN = ctx->timingWrite.load(std::memory_order_relaxed);
    uint32_t n = timingN > kTimingCap ? kTimingCap : static_cast<uint32_t>(timingN);
    out->timingSamples = n;
    if (n == 0) {
        return;
    }
    uint32_t *tmp = new (std::nothrow) uint32_t[n];
    if (tmp == nullptr) {
        return;
    }
    std::memcpy(tmp, ctx->timing, sizeof(uint32_t) * n);
    for (uint32_t i = 1; i < n; ++i) {
        uint32_t key = tmp[i];
        uint32_t j = i;
        while (j > 0 && tmp[j - 1] > key) {
            tmp[j] = tmp[j - 1];
            j -= 1;
        }
        tmp[j] = key;
    }
    out->callbackNsP95 = tmp[(n - 1u) * 95u / 100u];
    out->callbackNsP99 = tmp[(n - 1u) * 99u / 100u];
    delete[] tmp;
}

int ibms_preview_mix_debug_preset_cursor(IBMSPreviewMixContext *api, uint64_t logicalFrame, double chart, double wall) {
    Context *ctx = from_api(api);
    if (ctx == nullptr || !std::isfinite(chart) || !std::isfinite(wall) || (logicalFrame % ctx->blockFrames) != 0) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (ctx->callbacks.load(std::memory_order_acquire) != 0 || retired_now(ctx)) {
        return IBMS_PREVIEW_MIX_ERR_STATE;
    }
    ctx->read.store(logicalFrame, std::memory_order_relaxed);
    ctx->write.store(logicalFrame, std::memory_order_relaxed);
    ctx->consumedChart = chart;
    ctx->consumedWall = wall;
    AckView ack;
    if (!load_ack(ctx, &ack, kReaderTries)) {
        ack = AckView{};
        ack.serial = ctx->ackedSerial;
        ack.epoch = ctx->currentEpoch;
        ack.session = ctx->session;
        ack.rate = ctx->currentRate;
    }
    ack.chart = chart;
    ack.wall = wall;
    ack.logicalFrame = logicalFrame;
    publish_ack(ctx, ack);
    return IBMS_PREVIEW_MIX_OK;
}
