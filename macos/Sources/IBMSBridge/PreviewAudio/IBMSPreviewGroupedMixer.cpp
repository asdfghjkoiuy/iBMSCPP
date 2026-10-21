#include "PreviewAudio/IBMSPreviewGroupedMixer.h"

#include "PreviewAudio/IBMSPreviewMixBridge.h"

#include <AudioToolbox/AudioToolbox.h>
#include <mach/mach_time.h>
#include <samplerate.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <vector>

namespace {

constexpr double kGroupRate[IBMS_PREVIEW_GROUP_COUNT] = {44100.0, 48000.0, 96000.0, 192000.0};
constexpr float kOutputGain = 0.5f;

struct Voice {
    const float *samples = nullptr;
    int channels = 1;
    int64_t frames = 0;
    int64_t origin = 0;
    int64_t start = 0;
    int64_t end = 0;
    float gainL = 1;
    float gainR = 1;
};

struct Group {
    int fs = 48000;
    SRC_STATE *state = nullptr;
    double rate = 1;
    double ratio = 1;
    int64_t fed = 0;
    int voices = 0;
    int open = 0;
    Voice voice[IBMS_PREVIEW_GROUP_MAX_VOICES];
    std::vector<float> input;
    std::vector<float> output;
};

struct Mixer {
    Group group[IBMS_PREVIEW_GROUP_COUNT];
};

void mix_at(const Group &group, int64_t at, float *destination, long count) {
    std::memset(destination, 0, sizeof(float) * static_cast<size_t>(count) * 2);
    for (int index = 0; index < group.voices; ++index) {
        const Voice &voice = group.voice[index];
        if (voice.samples == nullptr) {
            continue;
        }
        const int64_t loNative = std::max(voice.start, voice.origin);
        const int64_t hiNative = std::min(voice.end, voice.origin + voice.frames);
        const int64_t iStart = std::max<int64_t>(0, loNative - at);
        const int64_t iEnd = std::min<int64_t>(static_cast<int64_t>(count), hiNative - at);
        if (iStart >= iEnd) {
            continue;
        }
        if (voice.channels <= 1) {
            for (long i = static_cast<long>(iStart); i < static_cast<long>(iEnd); ++i) {
                const float sample = voice.samples[(at + i) - voice.origin];
                destination[static_cast<size_t>(i) * 2] += sample * voice.gainL;
                destination[static_cast<size_t>(i) * 2 + 1] += sample * voice.gainR;
            }
        } else {
            for (long i = static_cast<long>(iStart); i < static_cast<long>(iEnd); ++i) {
                const int64_t frame = (at + i) - voice.origin;
                const size_t base = static_cast<size_t>(frame) * 2;
                destination[static_cast<size_t>(i) * 2] += voice.samples[base] * voice.gainL;
                destination[static_cast<size_t>(i) * 2 + 1] += voice.samples[base + 1] * voice.gainR;
            }
        }
    }
}

int open_group(Group &group, int fs, double rate) {
    if (group.state != nullptr) {
        src_delete(group.state);
        group.state = nullptr;
    }
    group.fs = fs;
    group.rate = rate;
    group.ratio = IBMS_PREVIEW_GROUP_OUTPUT_RATE / (static_cast<double>(fs) * rate);
    group.fed = 0;
    group.open = 0;
    int error = 0;
    group.state = src_new(SRC_SINC_MEDIUM_QUALITY, 2, &error);
    if (group.state == nullptr || error != 0) {
        group.state = nullptr;
        return IBMS_PREVIEW_GROUP_ERR_SRC;
    }
    if (src_set_ratio(group.state, group.ratio) != 0) {
        return IBMS_PREVIEW_GROUP_ERR_SRC;
    }
    group.open = 1;
    return IBMS_PREVIEW_GROUP_OK;
}

long pull_group(Group &group, float *destination, long want, long *used) {
    *used = 0;
    if (group.state == nullptr || want <= 0 || destination == nullptr) {
        return 0;
    }
    // 始终走 src_process，保住 preroll 灌进 Sinc 延迟线的相位。
    // 静音段也继续喂零，避免 src_reset 让 fed 相对输出时间向后漂。
    long filled = 0;
    int stall = 0;
    while (filled < want) {
        const long offer = 1024;
        if (static_cast<long>(group.input.size()) < offer * 2) {
            group.input.resize(static_cast<size_t>(offer) * 2);
        }
        mix_at(group, group.fed, group.input.data(), offer);
        SRC_DATA data{};
        data.data_in = group.input.data();
        data.input_frames = offer;
        data.data_out = destination + static_cast<size_t>(filled) * 2;
        data.output_frames = want - filled;
        data.end_of_input = 0;
        data.src_ratio = group.ratio;
        if (src_process(group.state, &data) != 0) {
            break;
        }
        group.fed += data.input_frames_used;
        *used += data.input_frames_used;
        filled += data.output_frames_gen;
        if (data.input_frames_used == 0 && data.output_frames_gen == 0) {
            if (++stall >= 8) {
                break;
            }
        } else {
            stall = 0;
        }
    }
    return filled;
}

int preroll(Group &group, double chartSeconds, double playbackRate) {
    if (group.state == nullptr) {
        return IBMS_PREVIEW_GROUP_ERR_SRC;
    }
    src_reset(group.state);
    group.rate = playbackRate;
    group.ratio = IBMS_PREVIEW_GROUP_OUTPUT_RATE / (static_cast<double>(group.fs) * playbackRate);
    if (src_set_ratio(group.state, group.ratio) != 0) {
        return IBMS_PREVIEW_GROUP_ERR_SRC;
    }
    const double native = chartSeconds * static_cast<double>(group.fs);
    double start = std::floor(native - static_cast<double>(IBMS_PREVIEW_GROUP_WARMUP));
    if (start < 0) {
        start = 0;
    }
    group.fed = static_cast<int64_t>(start);
    const double discardExact = (native - static_cast<double>(group.fed)) * group.ratio;
    long discard = static_cast<long>(std::floor(discardExact + 1e-12));
    if (discard < 0) {
        discard = 0;
    }
    if (discard == 0) {
        return IBMS_PREVIEW_GROUP_OK;
    }
    std::vector<float> trash(static_cast<size_t>(discard) * 2);
    long used = 0;
    pull_group(group, trash.data(), discard, &used);
    return IBMS_PREVIEW_GROUP_OK;
}

void reset_group(Group &group) {
    if (group.state != nullptr) {
        src_delete(group.state);
        group.state = nullptr;
    }
    group.fs = 48000;
    group.rate = 1;
    group.ratio = 1;
    group.fed = 0;
    group.voices = 0;
    group.open = 0;
    group.input.clear();
    group.input.shrink_to_fit();
    group.output.clear();
    group.output.shrink_to_fit();
    for (int index = 0; index < IBMS_PREVIEW_GROUP_MAX_VOICES; ++index) {
        group.voice[index] = Voice{};
    }
}

} // namespace

struct IBMSPreviewGroupedMixer {
    Mixer body;
};

struct IBMSPreviewRenderSlot {
    std::atomic<int> inflight;
    std::atomic<int> retired;
    std::atomic<int> tapFrames;
    std::atomic<int64_t> sourceSample;
    float *tap = nullptr;
    int tapCapacity = 0;
    int recording = 0;
    std::vector<float> scratch;
};

int ibms_preview_grouped_classify(double sampleRate, int *groupIndex, double *groupRate) {
    if (groupIndex == nullptr || groupRate == nullptr || !(sampleRate > 0) || !std::isfinite(sampleRate)) {
        return IBMS_PREVIEW_GROUP_ERR_ARGUMENT;
    }
    if (sampleRate > 192000.5) {
        return IBMS_PREVIEW_GROUP_ERR_UNSUPPORTED;
    }
    for (int index = 0; index < IBMS_PREVIEW_GROUP_COUNT; ++index) {
        if (std::fabs(sampleRate - kGroupRate[index]) < 1.0) {
            *groupIndex = index;
            *groupRate = kGroupRate[index];
            return IBMS_PREVIEW_GROUP_OK;
        }
    }
    for (int index = 0; index < IBMS_PREVIEW_GROUP_COUNT; ++index) {
        if (kGroupRate[index] + 0.5 >= sampleRate) {
            *groupIndex = index;
            *groupRate = kGroupRate[index];
            return IBMS_PREVIEW_GROUP_OK;
        }
    }
    return IBMS_PREVIEW_GROUP_ERR_UNSUPPORTED;
}

int ibms_preview_grouped_upsample(const float *interleavedStereo, int inputFrames, double ratio, float *destination,
                                  int destinationCapacity) {
    if (interleavedStereo == nullptr || destination == nullptr || inputFrames < 0 || destinationCapacity < 0 ||
        !(ratio >= 1.0) || !std::isfinite(ratio)) {
        return -1;
    }
    if (inputFrames == 0 || destinationCapacity == 0) {
        return 0;
    }
    int error = 0;
    SRC_STATE *state = src_new(SRC_SINC_MEDIUM_QUALITY, 2, &error);
    if (state == nullptr || error != 0) {
        return -1;
    }
    src_set_ratio(state, ratio);
    long filled = 0;
    long fed = 0;
    int stall = 0;
    int flushing = 0;
    while (filled < destinationCapacity) {
        long offer = 0;
        if (!flushing && fed < inputFrames) {
            offer = inputFrames - fed;
            if (offer > 2048) {
                offer = 2048;
            }
        } else {
            flushing = 1;
        }
        SRC_DATA data{};
        data.data_in = offer > 0 ? interleavedStereo + static_cast<size_t>(fed) * 2 : interleavedStereo;
        data.input_frames = offer;
        data.data_out = destination + static_cast<size_t>(filled) * 2;
        data.output_frames = destinationCapacity - filled;
        data.end_of_input = flushing ? 1 : 0;
        data.src_ratio = ratio;
        if (src_process(state, &data) != 0) {
            src_delete(state);
            return -1;
        }
        fed += data.input_frames_used;
        filled += data.output_frames_gen;
        if (data.input_frames_used == 0 && data.output_frames_gen == 0) {
            if (flushing || ++stall >= 8) {
                break;
            }
        } else {
            stall = 0;
        }
        if (fed >= inputFrames) {
            flushing = 1;
        }
    }
    src_delete(state);
    return static_cast<int>(filled);
}

IBMSPreviewGroupedMixer *ibms_preview_grouped_create(void) { return new (std::nothrow) IBMSPreviewGroupedMixer(); }

void ibms_preview_grouped_reset(IBMSPreviewGroupedMixer *mixer) {
    if (mixer == nullptr) {
        return;
    }
    for (int index = 0; index < IBMS_PREVIEW_GROUP_COUNT; ++index) {
        reset_group(mixer->body.group[index]);
    }
}

void ibms_preview_grouped_destroy(IBMSPreviewGroupedMixer *mixer) {
    if (mixer == nullptr) {
        return;
    }
    ibms_preview_grouped_reset(mixer);
    delete mixer;
}

int ibms_preview_grouped_set_voices(IBMSPreviewGroupedMixer *mixer, int groupIndex,
                                    const IBMSPreviewGroupedVoice *voices, int count, double chartSeconds,
                                    double playbackRate) {
    if (mixer == nullptr || groupIndex < 0 || groupIndex >= IBMS_PREVIEW_GROUP_COUNT || count < 0 ||
        count > IBMS_PREVIEW_GROUP_MAX_VOICES || (count > 0 && voices == nullptr) || !(playbackRate >= 0.25) ||
        !(playbackRate <= 4.0)) {
        return IBMS_PREVIEW_GROUP_ERR_ARGUMENT;
    }
    Group &group = mixer->body.group[groupIndex];
    const bool fresh = group.state == nullptr;
    if (fresh && count == 0) {
        group.voices = 0;
        return IBMS_PREVIEW_GROUP_OK;
    }
    if (fresh) {
        const int opened = open_group(group, static_cast<int>(kGroupRate[groupIndex]), playbackRate);
        if (opened != IBMS_PREVIEW_GROUP_OK) {
            return opened;
        }
    }
    group.voices = count;
    for (int index = 0; index < count; ++index) {
        Voice &slot = group.voice[index];
        slot.samples = voices[index].samples;
        slot.channels = voices[index].channels <= 1 ? 1 : 2;
        slot.frames = voices[index].frames;
        slot.origin = voices[index].origin;
        slot.start = voices[index].start;
        slot.end = voices[index].end;
        slot.gainL = voices[index].gainL;
        slot.gainR = voices[index].gainR;
    }
    if (fresh) {
        return preroll(group, chartSeconds, playbackRate);
    }
    return IBMS_PREVIEW_GROUP_OK;
}

int64_t ibms_preview_grouped_fed(const IBMSPreviewGroupedMixer *mixer, int groupIndex) {
    if (mixer == nullptr || groupIndex < 0 || groupIndex >= IBMS_PREVIEW_GROUP_COUNT) {
        return 0;
    }
    return mixer->body.group[groupIndex].fed;
}

int ibms_preview_grouped_rebase(IBMSPreviewGroupedMixer *mixer, double chartSeconds, double playbackRate) {
    if (mixer == nullptr || !(playbackRate >= 0.25) || !(playbackRate <= 4.0) || !std::isfinite(chartSeconds)) {
        return IBMS_PREVIEW_GROUP_ERR_ARGUMENT;
    }
    for (int index = 0; index < IBMS_PREVIEW_GROUP_COUNT; ++index) {
        Group &group = mixer->body.group[index];
        if (group.state == nullptr) {
            continue;
        }
        const int status = preroll(group, chartSeconds, playbackRate);
        if (status != IBMS_PREVIEW_GROUP_OK) {
            return status;
        }
    }
    return IBMS_PREVIEW_GROUP_OK;
}

int ibms_preview_grouped_pull(IBMSPreviewGroupedMixer *mixer, float *interleavedStereo, int frames, int *inputUsed,
                              float *peakBeforeLimit, int *overloadSamples) {
    if (mixer == nullptr || interleavedStereo == nullptr || frames <= 0) {
        return IBMS_PREVIEW_GROUP_ERR_ARGUMENT;
    }
    std::fill(interleavedStereo, interleavedStereo + static_cast<size_t>(frames) * 2, 0.f);
    long usedSum = 0;
    for (int index = 0; index < IBMS_PREVIEW_GROUP_COUNT; ++index) {
        Group &group = mixer->body.group[index];
        if (group.state == nullptr) {
            continue;
        }
        if (static_cast<long>(group.output.size()) < static_cast<long>(frames) * 2) {
            group.output.resize(static_cast<size_t>(frames) * 2);
        }
        long used = 0;
        const long got = pull_group(group, group.output.data(), frames, &used);
        usedSum += used;
        for (long i = 0; i < got; ++i) {
            interleavedStereo[static_cast<size_t>(i) * 2] += group.output[static_cast<size_t>(i) * 2];
            interleavedStereo[static_cast<size_t>(i) * 2 + 1] += group.output[static_cast<size_t>(i) * 2 + 1];
        }
    }
    float peak = 0;
    int overloads = 0;
    for (int i = 0; i < frames * 2; ++i) {
        const float scaled = interleavedStereo[i] * kOutputGain;
        const float absolute = std::fabs(scaled);
        if (absolute > peak) {
            peak = absolute;
        }
        if (absolute > 1.f) {
            overloads += 1;
            interleavedStereo[i] = std::copysign(1.f, scaled);
        } else {
            interleavedStereo[i] = scaled;
        }
    }
    if (inputUsed != nullptr) {
        *inputUsed = static_cast<int>(usedSum);
    }
    if (peakBeforeLimit != nullptr) {
        *peakBeforeLimit = peak;
    }
    if (overloadSamples != nullptr) {
        *overloadSamples = overloads;
    }
    return IBMS_PREVIEW_GROUP_OK;
}

IBMSPreviewRenderSlot *ibms_preview_render_slot_create(int tapCapacityFrames) {
    auto *slot = new (std::nothrow) IBMSPreviewRenderSlot();
    if (slot == nullptr) {
        return nullptr;
    }
    slot->inflight.store(0, std::memory_order_relaxed);
    slot->retired.store(0, std::memory_order_relaxed);
    slot->tapFrames.store(0, std::memory_order_relaxed);
    slot->sourceSample.store(0, std::memory_order_relaxed);
    slot->recording = 0;
    slot->tapCapacity = std::max(tapCapacityFrames, 0);
    if (slot->tapCapacity > 0) {
        slot->tap = new (std::nothrow) float[static_cast<size_t>(slot->tapCapacity) * 2];
        if (slot->tap == nullptr) {
            delete slot;
            return nullptr;
        }
        std::memset(slot->tap, 0, sizeof(float) * static_cast<size_t>(slot->tapCapacity) * 2);
    }
    slot->scratch.resize(static_cast<size_t>(IBMS_PREVIEW_MIX_MAX_CALLBACK_FRAMES) * 2);
    return slot;
}

void ibms_preview_render_slot_reset_tap(IBMSPreviewRenderSlot *slot, int recording) {
    if (slot == nullptr) {
        return;
    }
    slot->recording = recording ? 1 : 0;
    slot->tapFrames.store(0, std::memory_order_release);
}

void ibms_preview_render_slot_destroy(IBMSPreviewRenderSlot *slot) {
    if (slot == nullptr) {
        return;
    }
    delete[] slot->tap;
    delete slot;
}

void ibms_preview_render_slot_retire(IBMSPreviewRenderSlot *slot) {
    if (slot != nullptr) {
        slot->retired.store(1, std::memory_order_release);
    }
}

int ibms_preview_render_slot_inflight(IBMSPreviewRenderSlot *slot) {
    if (slot == nullptr) {
        return 0;
    }
    return slot->inflight.load(std::memory_order_acquire);
}

int ibms_preview_render_slot_tap_frames(IBMSPreviewRenderSlot *slot) {
    if (slot == nullptr) {
        return 0;
    }
    return slot->tapFrames.load(std::memory_order_acquire);
}

int ibms_preview_render_slot_copy_tap_left(IBMSPreviewRenderSlot *slot, float *destination, int capacity) {
    if (slot == nullptr || destination == nullptr || capacity <= 0 || slot->tap == nullptr) {
        return 0;
    }
    const int available = slot->tapFrames.load(std::memory_order_acquire);
    const int count = std::min(available, capacity);
    for (int index = 0; index < count; ++index) {
        destination[index] = slot->tap[static_cast<size_t>(index) * 2];
    }
    return count;
}

static void append_tap(IBMSPreviewRenderSlot *slot, const float *interleaved, unsigned int frames) {
    if (slot->recording == 0 || slot->tap == nullptr || interleaved == nullptr || frames == 0) {
        return;
    }
    int cursor = slot->tapFrames.load(std::memory_order_relaxed);
    if (cursor >= slot->tapCapacity) {
        return;
    }
    unsigned int room = static_cast<unsigned int>(slot->tapCapacity - cursor);
    if (frames < room) {
        room = frames;
    }
    std::memcpy(slot->tap + static_cast<size_t>(cursor) * 2, interleaved, sizeof(float) * room * 2);
    slot->tapFrames.store(cursor + static_cast<int>(room), std::memory_order_release);
}

static void interleave_output(const IBMSPreviewMixOutput &output, float *destination, unsigned int frames) {
    if (output.layout == IBMS_PREVIEW_MIX_LAYOUT_PLANAR && output.bufferCount >= 2 && output.buffers != nullptr &&
        output.buffers[0].data != nullptr && output.buffers[1].data != nullptr) {
        const float *left = output.buffers[0].data;
        const float *right = output.buffers[1].data;
        for (unsigned int index = 0; index < frames; ++index) {
            destination[index * 2] = left[index];
            destination[index * 2 + 1] = right[index];
        }
        return;
    }
    if (output.layout == IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED && output.bufferCount >= 1 && output.buffers != nullptr &&
        output.buffers[0].data != nullptr) {
        std::memcpy(destination, output.buffers[0].data, sizeof(float) * frames * 2);
    }
}

static int drive_output(IBMSPreviewRenderSlot *slot, IBMSPreviewMixRegistration *registration, uint64_t hostTicks,
                 unsigned int frames, IBMSPreviewMixOutput *output) {
    slot->inflight.fetch_add(1, std::memory_order_acq_rel);
    IBMSPreviewMixTime time{};
    time.sourceSample = slot->sourceSample.load(std::memory_order_relaxed);
    time.hostTicks = hostTicks;
    time.flags = IBMS_PREVIEW_MIX_TIME_SOURCE_SAMPLE_VALID | IBMS_PREVIEW_MIX_TIME_HOST_VALID;
    time.rateScalar = 1;
    const int status = ibms_preview_mix_render(registration, &time, output);
    if (status == IBMS_PREVIEW_MIX_OK && frames > 0 && frames <= IBMS_PREVIEW_MIX_MAX_CALLBACK_FRAMES) {
        const bool already =
            output->layout == IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED && output->buffers != nullptr &&
            output->buffers[0].data == slot->scratch.data();
        if (!already) {
            interleave_output(*output, slot->scratch.data(), frames);
        }
        append_tap(slot, slot->scratch.data(), frames);
        slot->sourceSample.fetch_add(static_cast<int64_t>(frames), std::memory_order_relaxed);
    }
    slot->inflight.fetch_sub(1, std::memory_order_acq_rel);
    return status;
}

static uint64_t host_after(uint64_t host, unsigned int frames) {
    static mach_timebase_info_data_t info = [] {
        mach_timebase_info_data_t value{};
        mach_timebase_info(&value);
        return value;
    }();
    if (info.numer == 0 || frames == 0) {
        return host;
    }
    const long double ticks = static_cast<long double>(frames) / 48000.0L * 1.0e9L *
                              static_cast<long double>(info.denom) / static_cast<long double>(info.numer);
    return host + static_cast<uint64_t>(ticks);
}

static int drive_quantized(IBMSPreviewRenderSlot *slot, IBMSPreviewMixRegistration *registration, uint64_t host,
                    unsigned int frames, IBMSPreviewMixOutput *output) {
    unsigned int done = 0;
    while (done < frames) {
        const unsigned int chunk = std::min(frames - done, static_cast<unsigned int>(IBMS_PREVIEW_MIX_MAX_CALLBACK_FRAMES));
        IBMSPreviewMixBuffer slice[2]{};
        IBMSPreviewMixOutput part = *output;
        part.frames = chunk;
        part.buffers = slice;
        for (uint32_t index = 0; index < output->bufferCount; ++index) {
            slice[index] = output->buffers[index];
            const uint32_t stride = slice[index].channels;
            slice[index].data += static_cast<size_t>(done) * stride;
            slice[index].capacityFrames = chunk;
        }
        const int status = drive_output(slot, registration, host_after(host, done), chunk, &part);
        if (status != IBMS_PREVIEW_MIX_OK) {
            return status;
        }
        done += chunk;
    }
    return IBMS_PREVIEW_MIX_OK;
}

int ibms_preview_render_drive(IBMSPreviewRenderSlot *slot, IBMSPreviewMixRegistration *registration,
                              const void *audioTimeStamp, unsigned int frames, void *audioBufferList) {
    if (slot == nullptr || registration == nullptr || audioBufferList == nullptr) {
        return -1;
    }
    const auto *stamp = static_cast<const AudioTimeStamp *>(audioTimeStamp);
    auto *list = static_cast<AudioBufferList *>(audioBufferList);
    uint64_t host = 0;
    if (stamp != nullptr && (stamp->mFlags & kAudioTimeStampHostTimeValid) != 0) {
        host = stamp->mHostTime;
    } else {
        host = ibms_preview_mix_host_ticks();
    }
    IBMSPreviewMixBuffer buffers[2]{};
    IBMSPreviewMixOutput output{};
    output.frames = frames;
    output.buffers = buffers;
    if (list->mNumberBuffers >= 2 && list->mBuffers[0].mNumberChannels == 1) {
        buffers[0].data = static_cast<float *>(list->mBuffers[0].mData);
        buffers[0].channels = 1;
        buffers[0].capacityFrames = frames;
        buffers[1].data = static_cast<float *>(list->mBuffers[1].mData);
        buffers[1].channels = 1;
        buffers[1].capacityFrames = frames;
        output.bufferCount = 2;
        output.layout = IBMS_PREVIEW_MIX_LAYOUT_PLANAR;
    } else if (list->mNumberBuffers >= 1 && list->mBuffers[0].mNumberChannels >= 2) {
        buffers[0].data = static_cast<float *>(list->mBuffers[0].mData);
        buffers[0].channels = 2;
        buffers[0].capacityFrames = frames;
        output.bufferCount = 1;
        output.layout = IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED;
    } else {
        return -1;
    }
    return drive_quantized(slot, registration, host, frames, &output);
}

int ibms_preview_render_drive_buffer(IBMSPreviewRenderSlot *slot, IBMSPreviewMixRegistration *registration,
                                     uint64_t hostTicks, unsigned int frames, float *interleavedStereo) {
    if (slot == nullptr || registration == nullptr || frames == 0) {
        return -1;
    }
    float *data = interleavedStereo != nullptr ? interleavedStereo : slot->scratch.data();
    IBMSPreviewMixBuffer buffer{};
    buffer.data = data;
    buffer.channels = 2;
    buffer.capacityFrames = frames;
    IBMSPreviewMixOutput output{};
    output.buffers = &buffer;
    output.bufferCount = 1;
    output.frames = frames;
    output.layout = IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED;
    if (interleavedStereo == nullptr && frames > IBMS_PREVIEW_MIX_MAX_CALLBACK_FRAMES) {
        return -1;
    }
    return drive_quantized(slot, registration, hostTicks, frames, &output);
}

struct IBMSPreviewRenderLease {
    std::atomic<int> holders;
    std::atomic<int> queries;
    std::atomic<int> entering;
    std::atomic<int> retireRequested;
    std::atomic<uint64_t> binding;
    std::atomic<int> lastStatus;
    IBMSPreviewRenderSlot *slot = nullptr;
    IBMSPreviewMixRegistration *registration = nullptr;
    IBMSPreviewMixContext *context = nullptr;
    IBMSPreviewMixReader *reader = nullptr;
    IBMSPreviewGroupedMixer *mixer = nullptr;
};

static void zero_audio_list(void *audioBufferList) {
    if (audioBufferList == nullptr) {
        return;
    }
    auto *list = static_cast<AudioBufferList *>(audioBufferList);
    for (UInt32 index = 0; index < list->mNumberBuffers; ++index) {
        if (list->mBuffers[index].mData != nullptr && list->mBuffers[index].mDataByteSize > 0) {
            std::memset(list->mBuffers[index].mData, 0, list->mBuffers[index].mDataByteSize);
        }
    }
}

IBMSPreviewRenderLease *ibms_preview_render_lease_create(IBMSPreviewRenderSlot *slot,
                                                        IBMSPreviewMixRegistration *registration, void *context,
                                                        void *reader, IBMSPreviewGroupedMixer *mixer) {
    if (slot == nullptr || registration == nullptr || context == nullptr || reader == nullptr || mixer == nullptr) {
        return nullptr;
    }
    auto *lease = new (std::nothrow) IBMSPreviewRenderLease();
    if (lease == nullptr) {
        return nullptr;
    }
    lease->holders.store(0, std::memory_order_relaxed);
    lease->queries.store(0, std::memory_order_relaxed);
    lease->entering.store(0, std::memory_order_relaxed);
    lease->retireRequested.store(0, std::memory_order_relaxed);
    lease->binding.store(1, std::memory_order_relaxed);
    lease->lastStatus.store(IBMS_PREVIEW_MIX_OK, std::memory_order_relaxed);
    lease->slot = slot;
    lease->registration = registration;
    lease->context = static_cast<IBMSPreviewMixContext *>(context);
    lease->reader = static_cast<IBMSPreviewMixReader *>(reader);
    lease->mixer = mixer;
    return lease;
}

void ibms_preview_render_lease_hold(IBMSPreviewRenderLease *lease) {
    if (lease != nullptr) {
        lease->holders.fetch_add(1, std::memory_order_acq_rel);
    }
}

void ibms_preview_render_lease_unhold(IBMSPreviewRenderLease *lease) {
    if (lease != nullptr) {
        lease->holders.fetch_sub(1, std::memory_order_acq_rel);
    }
}

uint64_t ibms_preview_render_lease_binding(const IBMSPreviewRenderLease *lease) {
    return lease == nullptr ? 0 : lease->binding.load(std::memory_order_acquire);
}

uint64_t ibms_preview_render_lease_rebind(IBMSPreviewRenderLease *lease) {
    if (lease == nullptr) {
        return 0;
    }
    return lease->binding.fetch_add(1, std::memory_order_acq_rel) + 1;
}

void ibms_preview_render_lease_request_retire(IBMSPreviewRenderLease *lease) {
    if (lease != nullptr) {
        lease->retireRequested.store(1, std::memory_order_release);
    }
}

int ibms_preview_render_lease_holders(const IBMSPreviewRenderLease *lease) {
    return lease == nullptr ? 0 : lease->holders.load(std::memory_order_acquire);
}

int ibms_preview_render_lease_query_begin(IBMSPreviewRenderLease *lease) {
    if (lease == nullptr) {
        return 0;
    }
    int current = lease->queries.load(std::memory_order_acquire);
    for (;;) {
        if (current < 0) {
            return 0;
        }
        if (lease->queries.compare_exchange_weak(current, current + 1, std::memory_order_acq_rel)) {
            return 1;
        }
    }
}

void ibms_preview_render_lease_query_end(IBMSPreviewRenderLease *lease) {
    if (lease != nullptr) {
        lease->queries.fetch_sub(1, std::memory_order_acq_rel);
    }
}

void *ibms_preview_render_lease_reader(IBMSPreviewRenderLease *lease) { return lease == nullptr ? nullptr : lease->reader; }

IBMSPreviewRenderSlot *ibms_preview_render_lease_slot(IBMSPreviewRenderLease *lease) {
    return lease == nullptr ? nullptr : lease->slot;
}

int ibms_preview_render_lease_last_status(const IBMSPreviewRenderLease *lease) {
    return lease == nullptr ? IBMS_PREVIEW_MIX_ERR_ARGUMENT : lease->lastStatus.load(std::memory_order_acquire);
}

static int claim_binding(IBMSPreviewRenderLease *lease, uint64_t binding) {
    if (lease->binding.load(std::memory_order_acquire) != binding) {
        return 0;
    }
    int idle = 0;
    if (!lease->entering.compare_exchange_strong(idle, 1, std::memory_order_acq_rel)) {
        return 0;
    }
    if (lease->binding.load(std::memory_order_acquire) != binding) {
        lease->entering.store(0, std::memory_order_release);
        return 0;
    }
    return 1;
}

int ibms_preview_render_lease_drive(IBMSPreviewRenderLease *lease, uint64_t binding, const void *audioTimeStamp,
                                    unsigned int frames, void *audioBufferList) {
    if (lease == nullptr || audioBufferList == nullptr) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (!claim_binding(lease, binding)) {
        zero_audio_list(audioBufferList);
        return IBMS_PREVIEW_MIX_OK;
    }
    const int status = ibms_preview_render_drive(lease->slot, lease->registration, audioTimeStamp, frames, audioBufferList);
    lease->lastStatus.store(status, std::memory_order_release);
    lease->entering.store(0, std::memory_order_release);
    return status;
}

int ibms_preview_render_lease_drive_buffer(IBMSPreviewRenderLease *lease, uint64_t binding, uint64_t hostTicks,
                                           unsigned int frames, float *interleavedStereo) {
    if (lease == nullptr || frames == 0) {
        return IBMS_PREVIEW_MIX_ERR_ARGUMENT;
    }
    if (!claim_binding(lease, binding)) {
        if (interleavedStereo != nullptr) {
            std::memset(interleavedStereo, 0, sizeof(float) * frames * 2);
        }
        return IBMS_PREVIEW_MIX_OK;
    }
    const int status =
        ibms_preview_render_drive_buffer(lease->slot, lease->registration, hostTicks, frames, interleavedStereo);
    lease->lastStatus.store(status, std::memory_order_release);
    lease->entering.store(0, std::memory_order_release);
    return status;
}

int ibms_preview_render_lease_try_release(IBMSPreviewRenderLease *lease) {
    if (lease == nullptr || lease->retireRequested.load(std::memory_order_acquire) == 0) {
        return 0;
    }
    if (lease->holders.load(std::memory_order_acquire) != 0) {
        return 0;
    }
    if (lease->slot != nullptr && lease->slot->inflight.load(std::memory_order_acquire) != 0) {
        return 0;
    }
    if (lease->entering.load(std::memory_order_acquire) != 0) {
        return 0;
    }
    int open = 0;
    if (!lease->queries.compare_exchange_strong(open, -1, std::memory_order_acq_rel)) {
        return 0;
    }
    if (lease->holders.load(std::memory_order_acquire) != 0 ||
        (lease->slot != nullptr && lease->slot->inflight.load(std::memory_order_acquire) != 0) ||
        lease->entering.load(std::memory_order_acquire) != 0) {
        lease->queries.store(0, std::memory_order_release);
        return 0;
    }
    if (lease->context != nullptr) {
        ibms_preview_mix_note_worker_exited(lease->context);
        ibms_preview_mix_close_queries(lease->context);
    }
    if (lease->reader != nullptr) {
        ibms_preview_mix_reader_release(lease->reader);
        lease->reader = nullptr;
    }
    if (lease->registration != nullptr) {
        ibms_preview_mix_registration_release(lease->registration);
        lease->registration = nullptr;
    }
    if (lease->context != nullptr) {
        ibms_preview_mix_context_release(lease->context);
        lease->context = nullptr;
    }
    if (lease->slot != nullptr) {
        ibms_preview_render_slot_destroy(lease->slot);
        lease->slot = nullptr;
    }
    /* mixer 的唯一销毁点。clear 只 reset，不会把 lease 里的指针换成另一只对象。 */
    if (lease->mixer != nullptr) {
        ibms_preview_grouped_destroy(lease->mixer);
        lease->mixer = nullptr;
    }
    delete lease;
    return 1;
}
