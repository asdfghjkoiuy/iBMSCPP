#include "IBMSPreviewVideo.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

constexpr int64_t kFrameBudget = IBMS_PREVIEW_VIDEO_FRAME_BUDGET;
constexpr int kCatchupFrameCap = 360;
constexpr int kPacketCap = 128;
constexpr int kMaxInflight = 8;
constexpr double kForwardSeekGap = 0.45;
constexpr double kCaughtSlop = 0.08;

std::atomic<int> g_inflight{0};
std::atomic<int> g_worker_fault{0};

struct Command {
    double media_seconds = 0;
    double rate = 1;
    int playing = 0;
    uint64_t generation = 0;
    uint64_t revision = 0;
};

struct Stats {
    int64_t ints[IBMS_PV_INT_COUNT] = {};
    double doubles[IBMS_PV_DOUBLE_COUNT] = {};
    char codec[32] = {};
    char format[32] = {};
    char error[160] = {};
};

struct Control {
    std::mutex mu;
    std::condition_variable cv;
    std::atomic<bool> stop{false};
    std::atomic<uint64_t> accepted{0};
    std::atomic<uint64_t> revision{0};
    std::atomic<uint8_t> slot_filled{0};
    std::atomic<uint8_t> needs_redecode{0};
    std::atomic<int> busy{0};
    std::atomic<int64_t> decoded_live{0};
    bool dirty = false;
    Command command;
    Command applied;
    Stats stats;
    std::vector<uint8_t> frame;
    int frame_width = 0;
    int frame_height = 0;
    int frame_stride = 0;
    std::string path;
    std::thread thread;
};

struct Decoder {
    AVFormatContext *fmt = nullptr;
    AVCodecContext *codec = nullptr;
    AVFrame *frame = nullptr;
    AVPacket *packet = nullptr;
    SwsContext *sws = nullptr;
    int video_index = -1;
    AVRational time_base{1, 1000};
    double origin = 0;
    std::vector<uint8_t> scratch;
    ~Decoder() {
        sws_freeContext(sws);
        av_frame_free(&frame);
        av_packet_free(&packet);
        avcodec_free_context(&codec);
        avformat_close_input(&fmt);
    }
};

struct HeldFrame {
    AVFrame *frame = av_frame_alloc();
    ~HeldFrame() { av_frame_free(&frame); }
};

struct BusyFlag {
    Control *control;
    explicit BusyFlag(Control *control) : control(control) {
        control->busy.store(1, std::memory_order_release);
    }
    ~BusyFlag() { control->busy.store(0, std::memory_order_release); }
};

enum class Take { Frame, End, Error, Stale, Budget };

bool claim_inflight() {
    int live = g_inflight.load(std::memory_order_relaxed);
    while (live < kMaxInflight) {
        if (g_inflight.compare_exchange_weak(
                live, live + 1, std::memory_order_acq_rel, std::memory_order_relaxed)) {
            return true;
        }
    }
    return false;
}

bool same_command(const Command &left, const Command &right) {
    return left.media_seconds == right.media_seconds && left.rate == right.rate && left.playing == right.playing
        && left.generation == right.generation;
}

bool cancels_decode(const Command &current, const Command &next) {
    if (current.revision == 0 || next.generation != current.generation || next.rate != current.rate
        || next.playing != current.playing) {
        return true;
    }
    const double delta = next.media_seconds - current.media_seconds;
    return delta < -0.04 || delta > kForwardSeekGap;
}

bool superseded(Control *control, uint64_t generation, uint64_t revision) {
    if (control->stop.load(std::memory_order_acquire)) {
        return true;
    }
    if (control->accepted.load(std::memory_order_acquire) != generation) {
        return true;
    }
    return control->revision.load(std::memory_order_acquire) != revision;
}

bool pixels_fit(int width, int height) {
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
        return false;
    }
    const int64_t pixels = static_cast<int64_t>(width) * static_cast<int64_t>(height);
    return pixels <= kFrameBudget / 4;
}

void set_error(Stats &stats, int code, const char *fallback) {
    stats.ints[IBMS_PV_FAILED] = 1;
    if (code < 0) {
        av_strerror(code, stats.error, sizeof(stats.error));
    } else if (fallback) {
        std::snprintf(stats.error, sizeof(stats.error), "%s", fallback);
    }
}

void note_decoded(Control *control, Stats &stats) {
    stats.ints[IBMS_PV_DECODED_FRAMES] = control->decoded_live.load(std::memory_order_relaxed);
}

bool publish(
    Control *control,
    Stats &stats,
    std::vector<uint8_t> *pixels,
    int width,
    int height,
    int stride,
    uint64_t generation,
    uint64_t revision,
    bool command_bound) {
    std::lock_guard<std::mutex> lock(control->mu);
    const bool drop = control->stop.load(std::memory_order_acquire)
        || control->accepted.load(std::memory_order_acquire) != generation
        || (command_bound && control->revision.load(std::memory_order_acquire) != revision);
    if (drop) {
        control->stats.ints[IBMS_PV_DROPPED_STALE] += 1;
        stats.ints[IBMS_PV_DROPPED_STALE] = control->stats.ints[IBMS_PV_DROPPED_STALE];
        return false;
    }
    const int64_t copies = control->stats.ints[IBMS_PV_COPIES];
    const int64_t dropped = control->stats.ints[IBMS_PV_DROPPED_STALE];
    const double serial = control->stats.doubles[IBMS_PV_FRAME_SERIAL];
    const double peak = control->stats.doubles[IBMS_PV_PEAK];
    note_decoded(control, stats);
    control->stats = stats;
    control->stats.ints[IBMS_PV_COPIES] = copies;
    control->stats.ints[IBMS_PV_DROPPED_STALE] = dropped;
    control->stats.doubles[IBMS_PV_FRAME_SERIAL] = serial;
    const bool have_pixels = pixels && width > 0 && height > 0 && stride >= width * 4;
    if (have_pixels) {
        const int64_t bytes = static_cast<int64_t>(stride) * static_cast<int64_t>(height);
        if (bytes > kFrameBudget || static_cast<int64_t>(pixels->size()) < bytes || !pixels_fit(width, height)) {
            control->stats.ints[IBMS_PV_FAILED] = 1;
            control->stats.ints[IBMS_PV_VALID] = 0;
            std::snprintf(control->stats.error, sizeof(control->stats.error), "frame exceeds memory budget");
            control->slot_filled.store(0, std::memory_order_release);
        } else {
            control->frame.swap(*pixels);
            if (static_cast<int64_t>(control->frame.size()) > bytes) {
                control->frame.resize(static_cast<size_t>(bytes));
            }
            control->frame_width = width;
            control->frame_height = height;
            control->frame_stride = stride;
            control->stats.ints[IBMS_PV_VALID] = 1;
            control->stats.ints[IBMS_PV_WIDTH] = width;
            control->stats.ints[IBMS_PV_HEIGHT] = height;
            control->stats.ints[IBMS_PV_STRIDE] = stride;
            control->stats.doubles[IBMS_PV_FRAME_SERIAL] = serial + 1;
            control->slot_filled.store(1, std::memory_order_release);
        }
    } else if (control->frame.empty()) {
        control->stats.ints[IBMS_PV_VALID] = 0;
        control->slot_filled.store(0, std::memory_order_release);
    } else {
        control->stats.ints[IBMS_PV_VALID] = 1;
        control->stats.ints[IBMS_PV_WIDTH] = control->frame_width;
        control->stats.ints[IBMS_PV_HEIGHT] = control->frame_height;
        control->stats.ints[IBMS_PV_STRIDE] = control->frame_stride;
    }
    const double resident = static_cast<double>(control->frame.size());
    control->stats.doubles[IBMS_PV_RESIDENT] = resident;
    control->stats.doubles[IBMS_PV_PEAK] = std::max(peak, resident);
    stats = control->stats;
    return true;
}

int interrupt_cb(void *opaque) {
    auto *control = static_cast<Control *>(opaque);
    return control->stop.load(std::memory_order_acquire) ? 1 : 0;
}

double clamp_media(double media, double duration) {
    if (!std::isfinite(media) || media < 0) {
        return 0;
    }
    if (!(duration > 0.05) || !std::isfinite(duration) || media <= duration) {
        return media;
    }
    return duration;
}

bool open_decoder(Control *control, Decoder &decoder, Stats &stats) {
    AVFormatContext *fmt = avformat_alloc_context();
    if (!fmt) {
        set_error(stats, 0, "could not allocate format context");
        return false;
    }
    fmt->interrupt_callback.callback = interrupt_cb;
    fmt->interrupt_callback.opaque = control;
    const int opened = avformat_open_input(&fmt, control->path.c_str(), nullptr, nullptr);
    if (opened < 0) {
        decoder.fmt = nullptr;
        set_error(stats, opened, "open failed");
        return false;
    }
    decoder.fmt = fmt;
    const int info = avformat_find_stream_info(decoder.fmt, nullptr);
    if (info < 0) {
        set_error(stats, info, "stream info failed");
        return false;
    }
    const int video = av_find_best_stream(decoder.fmt, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (video < 0) {
        set_error(stats, video, "no video stream");
        return false;
    }
    decoder.video_index = video;
    for (unsigned index = 0; index < decoder.fmt->nb_streams; ++index) {
        AVStream *stream = decoder.fmt->streams[index];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            stats.ints[IBMS_PV_AUDIO_STREAMS] += 1;
            stream->discard = AVDISCARD_ALL;
        } else if (static_cast<int>(index) != video) {
            stream->discard = AVDISCARD_ALL;
        }
    }
    AVStream *stream = decoder.fmt->streams[video];
    decoder.time_base = stream->time_base;
    if (stream->start_time != AV_NOPTS_VALUE) {
        decoder.origin = static_cast<double>(stream->start_time) * av_q2d(stream->time_base);
        if (!std::isfinite(decoder.origin)) {
            decoder.origin = 0;
        }
    }
    const int coded_w = stream->codecpar->width;
    const int coded_h = stream->codecpar->height;
    if (!pixels_fit(coded_w, coded_h)) {
        set_error(stats, 0, "coded frame exceeds memory budget");
        return false;
    }
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        set_error(stats, 0, "no decoder");
        return false;
    }
    decoder.codec = avcodec_alloc_context3(codec);
    if (!decoder.codec) {
        set_error(stats, 0, "could not allocate codec");
        return false;
    }
    const int params = avcodec_parameters_to_context(decoder.codec, stream->codecpar);
    if (params < 0) {
        set_error(stats, params, "codec parameters failed");
        return false;
    }
    int limit_w = decoder.codec->width;
    int limit_h = decoder.codec->height;
    if (decoder.codec->coded_width > limit_w) {
        limit_w = decoder.codec->coded_width;
    }
    if (decoder.codec->coded_height > limit_h) {
        limit_h = decoder.codec->coded_height;
    }
    if (!pixels_fit(limit_w, limit_h)) {
        set_error(stats, 0, "coded frame exceeds memory budget");
        return false;
    }
    decoder.codec->pkt_timebase = stream->time_base;
    decoder.codec->thread_count = 1;
    decoder.codec->max_pixels = kFrameBudget / 4;
    const int codec_open = avcodec_open2(decoder.codec, codec, nullptr);
    if (codec_open < 0) {
        set_error(stats, codec_open, "codec open failed");
        return false;
    }
    decoder.frame = av_frame_alloc();
    decoder.packet = av_packet_alloc();
    if (!decoder.frame || !decoder.packet) {
        set_error(stats, 0, "could not allocate frame");
        return false;
    }
    stats.ints[IBMS_PV_ORIGINAL_W] = stream->codecpar->width;
    stats.ints[IBMS_PV_ORIGINAL_H] = stream->codecpar->height;
    if (decoder.fmt->duration > 0 && decoder.fmt->duration != AV_NOPTS_VALUE) {
        stats.doubles[IBMS_PV_DURATION] = static_cast<double>(decoder.fmt->duration) / AV_TIME_BASE;
    }
    std::snprintf(stats.codec, sizeof(stats.codec), "%s", avcodec_get_name(decoder.codec->codec_id));
    if (decoder.fmt->iformat && decoder.fmt->iformat->name) {
        std::snprintf(stats.format, sizeof(stats.format), "%s", decoder.fmt->iformat->name);
    }
    stats.ints[IBMS_PV_PROBED] = 1;
    stats.ints[IBMS_PV_AUDIO_DECODED] = 0;
    return true;
}

double frame_pts(const Decoder &decoder, const AVFrame *frame) {
    int64_t stamp = frame->best_effort_timestamp;
    if (stamp == AV_NOPTS_VALUE) {
        stamp = frame->pts;
    }
    if (stamp == AV_NOPTS_VALUE) {
        return -1;
    }
    const double raw = static_cast<double>(stamp) * av_q2d(decoder.time_base);
    const double normalized = raw - decoder.origin;
    return std::isfinite(normalized) ? normalized : -1;
}

bool convert_bgra(Decoder &decoder, AVFrame *frame, std::vector<uint8_t> &scratch, int &width, int &height, int &stride) {
    width = frame->width;
    height = frame->height;
    if (!pixels_fit(width, height)) {
        return false;
    }
    stride = width * 4;
    const size_t bytes = static_cast<size_t>(stride) * static_cast<size_t>(height);
    if (scratch.size() != bytes) {
        scratch.assign(bytes, 0);
    }
    decoder.sws = sws_getCachedContext(
        decoder.sws,
        width,
        height,
        static_cast<AVPixelFormat>(frame->format),
        width,
        height,
        AV_PIX_FMT_BGRA,
        SWS_BILINEAR,
        nullptr,
        nullptr,
        nullptr);
    if (!decoder.sws) {
        return false;
    }
    uint8_t *dest_slices[4] = {scratch.data(), nullptr, nullptr, nullptr};
    int dest_stride[4] = {stride, 0, 0, 0};
    const int scaled = sws_scale(decoder.sws, frame->data, frame->linesize, 0, height, dest_slices, dest_stride);
    return scaled == height;
}

bool seek_to(Decoder &decoder, double normalized) {
    double raw = normalized + decoder.origin;
    if (!std::isfinite(raw) || raw < 0) {
        raw = 0;
    }
    const int64_t stamp = av_rescale_q(
        static_cast<int64_t>(std::llround(raw * AV_TIME_BASE)),
        AV_TIME_BASE_Q,
        decoder.time_base);
    int result = av_seek_frame(decoder.fmt, decoder.video_index, stamp, AVSEEK_FLAG_BACKWARD);
    if (result < 0) {
        result = av_seek_frame(
            decoder.fmt,
            -1,
            static_cast<int64_t>(std::llround(raw * AV_TIME_BASE)),
            AVSEEK_FLAG_BACKWARD);
    }
    avcodec_flush_buffers(decoder.codec);
    av_packet_unref(decoder.packet);
    return result >= 0;
}

Take take_video_frame(Control *control, Decoder &decoder, Stats &stats, uint64_t generation, uint64_t revision) {
    bool flushing = false;
    bool packet_pending = false;
    int reads = 0;
    while (!superseded(control, generation, revision)) {
        const int received = avcodec_receive_frame(decoder.codec, decoder.frame);
        if (received == 0) {
            control->decoded_live.fetch_add(1, std::memory_order_relaxed);
            return Take::Frame;
        }
        if (received == AVERROR_EOF || (flushing && received == AVERROR(EAGAIN))) {
            return Take::End;
        }
        if (received != AVERROR(EAGAIN)) {
            set_error(stats, received, "decode failed");
            return Take::Error;
        }
        if (flushing) {
            return Take::End;
        }
        if (!packet_pending) {
            if (reads >= kPacketCap) {
                return Take::Budget;
            }
            const int read = av_read_frame(decoder.fmt, decoder.packet);
            reads += 1;
            if (read == AVERROR_EOF) {
                const int sent = avcodec_send_packet(decoder.codec, nullptr);
                if (sent < 0 && sent != AVERROR_EOF) {
                    set_error(stats, sent, "decode failed");
                    return Take::Error;
                }
                flushing = true;
                continue;
            }
            if (read < 0) {
                set_error(stats, read, "read failed");
                return Take::Error;
            }
            if (decoder.packet->stream_index != decoder.video_index) {
                if (decoder.packet->stream_index >= 0
                    && static_cast<unsigned>(decoder.packet->stream_index) < decoder.fmt->nb_streams
                    && decoder.fmt->streams[decoder.packet->stream_index]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
                    stats.ints[IBMS_PV_AUDIO_DISCARDED] += 1;
                }
                av_packet_unref(decoder.packet);
                continue;
            }
            packet_pending = true;
        }
        const int sent = avcodec_send_packet(decoder.codec, decoder.packet);
        if (sent == AVERROR(EAGAIN)) {
            continue;
        }
        av_packet_unref(decoder.packet);
        packet_pending = false;
        if (sent < 0) {
            set_error(stats, sent, "decode failed");
            return Take::Error;
        }
    }
    av_packet_unref(decoder.packet);
    return Take::Stale;
}

bool present_held(
    Control *control,
    Decoder &decoder,
    Stats &stats,
    HeldFrame &held,
    double chosen_pts,
    uint64_t generation,
    uint64_t revision,
    bool *force_seek) {
    if (chosen_pts >= 0) {
        stats.doubles[IBMS_PV_PTS] = chosen_pts;
    }
    if (superseded(control, generation, revision)) {
        *force_seek = true;
        return false;
    }
    if (!pixels_fit(held.frame->width, held.frame->height)) {
        set_error(stats, 0, "coded frame exceeds memory budget");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *force_seek = true;
        return false;
    }
    int width = 0;
    int height = 0;
    int stride = 0;
    if (!convert_bgra(decoder, held.frame, decoder.scratch, width, height, stride)) {
        set_error(stats, 0, "could not convert frame");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *force_seek = true;
        return false;
    }
    if (superseded(control, generation, revision)) {
        *force_seek = true;
        return false;
    }
    if (!publish(control, stats, &decoder.scratch, width, height, stride, generation, revision, true)) {
        *force_seek = true;
        return false;
    }
    return true;
}

bool latest_target(Control *control, const Command &baseline, double duration, double *target, bool *past_end) {
    Command latest = baseline;
    {
        std::lock_guard<std::mutex> lock(control->mu);
        if (control->stop.load(std::memory_order_acquire)) {
            return false;
        }
        if (control->command.generation != baseline.generation || control->command.revision != baseline.revision) {
            return false;
        }
        latest = control->command;
    }
    const bool end = duration > 0.05 && std::isfinite(duration) && latest.media_seconds >= duration;
    *past_end = end;
    *target = end ? std::max(0.0, duration - 0.001) : clamp_media(latest.media_seconds, duration);
    return true;
}

bool catch_up(Control *control, Decoder &decoder, Stats &stats, const Command &command, bool *holding_tail, bool *force_seek) {
    const uint64_t generation = command.generation;
    const uint64_t revision = command.revision;
    const double duration = stats.doubles[IBMS_PV_DURATION];
    bool past_end = false;
    double target = 0;
    if (!latest_target(control, command, duration, &target, &past_end)) {
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    note_decoded(control, stats);
    const bool slot = control->slot_filled.load(std::memory_order_acquire) != 0;
    const bool positioned = stats.ints[IBMS_PV_DECODED_FRAMES] > 0 && stats.doubles[IBMS_PV_PTS] >= 0;
    const double shown = stats.doubles[IBMS_PV_PTS];
    const bool need_frame = !slot || stats.ints[IBMS_PV_VALID] != 1;
    const bool backward = positioned && shown > target + 0.20;
    const bool far_forward = !positioned ? target > 0.50 : target > shown + kForwardSeekGap;
    const bool replay = need_frame && positioned && std::fabs(shown - target) <= kCaughtSlop + 0.02;
    bool seeked_this_call = false;
    if (*force_seek || backward || far_forward || replay) {
        if (!latest_target(control, command, duration, &target, &past_end)) {
            *holding_tail = false;
            *force_seek = true;
            return false;
        }
        if (seek_to(decoder, target)) {
            stats.ints[IBMS_PV_SEEK_COUNT] += 1;
            stats.ints[IBMS_PV_HAS_SEEK] = 1;
            stats.doubles[IBMS_PV_LAST_SEEK] = target;
        }
        *force_seek = false;
        seeked_this_call = true;
    }
    if (!seeked_this_call && positioned && !need_frame && shown + 0.001 >= target && shown <= target + 0.20) {
        *holding_tail = false;
        return true;
    }
    HeldFrame held;
    if (!held.frame) {
        set_error(stats, 0, "could not allocate frame");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    bool saw = false;
    bool drained = false;
    bool presented = false;
    double chosen_pts = -1;
    int frames = 0;
    while (frames < kCatchupFrameCap) {
        if (superseded(control, generation, revision)) {
            *holding_tail = false;
            *force_seek = true;
            return false;
        }
        const Take take = take_video_frame(control, decoder, stats, generation, revision);
        if (take == Take::Stale) {
            *holding_tail = false;
            *force_seek = true;
            return false;
        }
        if (take == Take::Error || take == Take::Budget) {
            if (take == Take::Budget) {
                set_error(stats, 0, "packet budget exhausted");
            }
            publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
            *holding_tail = false;
            *force_seek = true;
            return false;
        }
        if (take == Take::End) {
            drained = true;
            break;
        }
        const double pts = frame_pts(decoder, decoder.frame);
        if (pts >= 0) {
            chosen_pts = pts;
        }
        av_frame_unref(held.frame);
        av_frame_move_ref(held.frame, decoder.frame);
        saw = true;
        frames += 1;
        if (!latest_target(control, command, duration, &target, &past_end)) {
            *holding_tail = false;
            *force_seek = true;
            return false;
        }
        const bool near = !past_end && pts >= 0 && pts + kCaughtSlop >= target;
        const bool sequential = !past_end && !seeked_this_call && pts >= 0 && pts + kForwardSeekGap >= target;
        if (near || sequential) {
            if (!present_held(control, decoder, stats, held, chosen_pts, generation, revision, force_seek)) {
                *holding_tail = false;
                return false;
            }
            if (near) {
                *holding_tail = false;
                return true;
            }
            presented = true;
        }
    }
    if (!drained && !presented && frames >= kCatchupFrameCap) {
        set_error(stats, 0, "decode budget exhausted");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    if (presented) {
        *holding_tail = drained || past_end;
        return true;
    }
    if (!latest_target(control, command, duration, &target, &past_end)) {
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    if (seeked_this_call && !past_end && !drained && chosen_pts >= 0 && chosen_pts + kCaughtSlop < target) {
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    if (chosen_pts >= 0) {
        stats.doubles[IBMS_PV_PTS] = chosen_pts;
    }
    if (!saw) {
        if (past_end && slot) {
            *holding_tail = true;
            return publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        }
        set_error(stats, 0, "no frame");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    if (!pixels_fit(held.frame->width, held.frame->height)) {
        set_error(stats, 0, "coded frame exceeds memory budget");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    int width = 0;
    int height = 0;
    int stride = 0;
    const bool converted = convert_bgra(decoder, held.frame, decoder.scratch, width, height, stride);
    if (!converted) {
        set_error(stats, 0, "could not convert frame");
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, true);
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    if (superseded(control, generation, revision)) {
        *holding_tail = false;
        *force_seek = true;
        return false;
    }
    const bool published = publish(control, stats, &decoder.scratch, width, height, stride, generation, revision, true);
    *holding_tail = published && (drained || past_end);
    return published;
}

bool wait_command(Control *control, Command *command) {
    std::unique_lock<std::mutex> lock(control->mu);
    control->cv.wait(lock, [&] { return control->stop.load(std::memory_order_acquire) || control->dirty; });
    if (control->stop.load(std::memory_order_acquire)) {
        return false;
    }
    control->dirty = false;
    *command = control->command;
    return true;
}

bool adopt_soft_target(Control *control, Command *command) {
    std::lock_guard<std::mutex> lock(control->mu);
    if (control->stop.load(std::memory_order_acquire)) {
        return false;
    }
    if (control->command.generation != command->generation || control->command.revision != command->revision) {
        return false;
    }
    *command = control->command;
    control->dirty = false;
    return true;
}

void wait_until_stopped(Control *control) {
    std::unique_lock<std::mutex> lock(control->mu);
    control->cv.wait(lock, [&] { return control->stop.load(std::memory_order_acquire); });
}

void store_applied(Control *control, const Command &command) {
    std::lock_guard<std::mutex> lock(control->mu);
    control->applied = command;
}

bool applied_matches(Control *control, const Command &command) {
    std::lock_guard<std::mutex> lock(control->mu);
    return same_command(command, control->applied);
}

void note_drop(Control *control) {
    std::lock_guard<std::mutex> lock(control->mu);
    control->stats.ints[IBMS_PV_DROPPED_STALE] += 1;
}

void run_worker(Control *control) {
    av_log_set_level(AV_LOG_ERROR);
    Stats stats;
    const uint64_t opened_generation = control->accepted.load(std::memory_order_acquire);
    stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(opened_generation);
    Decoder decoder;
    if (!open_decoder(control, decoder, stats)) {
        const uint64_t generation = control->accepted.load(std::memory_order_acquire);
        const uint64_t revision = control->revision.load(std::memory_order_acquire);
        stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(generation);
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, false);
        wait_until_stopped(control);
        return;
    }
    const uint64_t generation = control->accepted.load(std::memory_order_acquire);
    const uint64_t revision = control->revision.load(std::memory_order_acquire);
    stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(generation);
    publish(control, stats, nullptr, 0, 0, 0, generation, revision, false);
    uint64_t local_generation = generation;
    bool holding_tail = false;
    bool force_seek = false;
    while (!control->stop.load(std::memory_order_acquire)) {
        Command command;
        if (!wait_command(control, &command)) {
            break;
        }
        if (!adopt_soft_target(control, &command) || superseded(control, command.generation, command.revision)) {
            holding_tail = false;
            force_seek = true;
            note_drop(control);
            continue;
        }
        if (command.generation != local_generation || control->slot_filled.load(std::memory_order_acquire) == 0) {
            if (command.generation != local_generation || control->slot_filled.load(std::memory_order_acquire) == 0) {
                stats.ints[IBMS_PV_VALID] = 0;
                holding_tail = false;
            }
            local_generation = command.generation;
        }
        stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(command.generation);
        stats.doubles[IBMS_PV_RATE] = command.playing ? command.rate : 0;
        const double duration = stats.doubles[IBMS_PV_DURATION];
        const bool past_end = duration > 0.05 && std::isfinite(duration) && command.media_seconds >= duration;
        if (!past_end) {
            holding_tail = false;
        }
        const double target = past_end ? std::max(0.0, duration - 0.001) : clamp_media(command.media_seconds, duration);
        const bool slot = control->slot_filled.load(std::memory_order_acquire) != 0;
        const bool have = stats.ints[IBMS_PV_VALID] == 1 && slot;
        if (past_end && holding_tail && have && !superseded(control, command.generation, command.revision)) {
            publish(control, stats, nullptr, 0, 0, 0, command.generation, command.revision, true);
            store_applied(control, command);
            continue;
        }
        const bool close_enough = have && !past_end && std::fabs(stats.doubles[IBMS_PV_PTS] - target) <= kCaughtSlop;
        if (close_enough && !command.playing) {
            publish(control, stats, nullptr, 0, 0, 0, command.generation, command.revision, true);
            store_applied(control, command);
            continue;
        }
        if (close_enough && command.playing && applied_matches(control, command)) {
            publish(control, stats, nullptr, 0, 0, 0, command.generation, command.revision, true);
            continue;
        }
        bool finished = false;
        {
            BusyFlag busy(control);
            finished = catch_up(control, decoder, stats, command, &holding_tail, &force_seek);
        }
        if (superseded(control, command.generation, command.revision)) {
            holding_tail = false;
            force_seek = true;
            note_drop(control);
            continue;
        }
        if (finished) {
            store_applied(control, command);
        }
    }
}

void retire_control(Control *control) {
    {
        std::lock_guard<std::mutex> lock(control->mu);
    }
    if (control->thread.joinable()) {
        control->thread.detach();
    }
    g_inflight.fetch_sub(1, std::memory_order_acq_rel);
    delete control;
}

void publish_worker_failure(Control *control) {
    try {
        Stats stats;
        set_error(stats, 0, "worker failed");
        const uint64_t generation = control->accepted.load(std::memory_order_acquire);
        const uint64_t revision = control->revision.load(std::memory_order_acquire);
        stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(generation);
        publish(control, stats, nullptr, 0, 0, 0, generation, revision, false);
    } catch (...) {
    }
}

void wait_for_owner_close(Control *control) {
    try {
        wait_until_stopped(control);
    } catch (...) {
        while (!control->stop.load(std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
    }
}

void worker_main(Control *control) {
    try {
        if (g_worker_fault.exchange(0, std::memory_order_acq_rel) != 0) {
            throw std::runtime_error("injected worker fault");
        }
        run_worker(control);
    } catch (...) {
        publish_worker_failure(control);
        wait_for_owner_close(control);
    }
    retire_control(control);
}

void copy_text(char *dest, int cap, const char *src) {
    if (!dest || cap <= 0) {
        return;
    }
    std::snprintf(dest, static_cast<size_t>(cap), "%s", src ? src : "");
}

void read_stats_locked(
    Control *control,
    int64_t *ints,
    double *doubles,
    char *codec_name,
    int codec_cap,
    char *format_name,
    int format_cap,
    char *error_text,
    int error_cap) {
    control->stats.ints[IBMS_PV_DECODED_FRAMES] = control->decoded_live.load(std::memory_order_relaxed);
    if (ints) {
        std::memcpy(ints, control->stats.ints, sizeof(control->stats.ints));
    }
    if (doubles) {
        std::memcpy(doubles, control->stats.doubles, sizeof(control->stats.doubles));
    }
    copy_text(codec_name, codec_cap, control->stats.codec);
    copy_text(format_name, format_cap, control->stats.format);
    copy_text(error_text, error_cap, control->stats.error);
}

}  // namespace

void ibms_preview_video_layout(int *int_count, int *double_count) {
    if (int_count) {
        *int_count = IBMS_PV_INT_COUNT;
    }
    if (double_count) {
        *double_count = IBMS_PV_DOUBLE_COUNT;
    }
}

int ibms_preview_video_inflight(void) {
    return g_inflight.load(std::memory_order_acquire);
}

int ibms_preview_video_inflight_limit(void) {
    return kMaxInflight;
}

void ibms_preview_video_decoder_inventory(char *names, int cap, int *video_count, int *audio_count) {
    std::vector<std::string> videos;
    std::vector<std::string> audios;
    void *opaque = nullptr;
    const AVCodec *codec = nullptr;
    while ((codec = av_codec_iterate(&opaque)) != nullptr) {
        if (!av_codec_is_decoder(codec) || !codec->name) {
            continue;
        }
        if (codec->type == AVMEDIA_TYPE_VIDEO) {
            videos.emplace_back(codec->name);
        } else if (codec->type == AVMEDIA_TYPE_AUDIO) {
            audios.emplace_back(codec->name);
        }
    }
    std::sort(videos.begin(), videos.end());
    std::sort(audios.begin(), audios.end());
    std::string text;
    for (const std::string &name : videos) {
        if (!text.empty()) {
            text.push_back(',');
        }
        text += name;
    }
    if (!audios.empty()) {
        text += ";audio=";
        for (size_t index = 0; index < audios.size(); ++index) {
            if (index > 0) {
                text.push_back(',');
            }
            text += audios[index];
        }
    }
    copy_text(names, cap, text.c_str());
    if (video_count) {
        *video_count = static_cast<int>(videos.size());
    }
    if (audio_count) {
        *audio_count = static_cast<int>(audios.size());
    }
}

IBMSPreviewVideo *ibms_preview_video_open(const char *path, uint64_t generation) {
    if (!path || path[0] == '\0') {
        return nullptr;
    }
    auto *control = new Control();
    if (!claim_inflight()) {
        delete control;
        return nullptr;
    }
    control->path = path;
    control->accepted.store(generation, std::memory_order_release);
    control->command.generation = generation;
    control->stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(generation);
    try {
        control->thread = std::thread(worker_main, control);
    } catch (...) {
        g_inflight.fetch_sub(1, std::memory_order_acq_rel);
        delete control;
        return nullptr;
    }
    return reinterpret_cast<IBMSPreviewVideo *>(control);
}

void ibms_preview_video_command(
    IBMSPreviewVideo *video,
    double media_seconds,
    double rate,
    int playing,
    uint64_t generation) {
    auto *control = reinterpret_cast<Control *>(video);
    if (!control) {
        return;
    }
    if (!std::isfinite(media_seconds) || media_seconds < 0) {
        media_seconds = 0;
    }
    if (!std::isfinite(rate) || rate < 0) {
        rate = 0;
    }
    std::lock_guard<std::mutex> lock(control->mu);
    if (control->stop.load(std::memory_order_acquire)) {
        return;
    }
    Command next;
    next.media_seconds = media_seconds;
    next.rate = rate;
    next.playing = playing ? 1 : 0;
    next.generation = generation;
    control->accepted.store(generation, std::memory_order_release);
    control->stats.doubles[IBMS_PV_RATE] = next.playing ? next.rate : 0;
    control->stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(generation);
    const bool same = same_command(next, control->command);
    const bool filled = control->slot_filled.load(std::memory_order_acquire) != 0;
    const bool busy = control->busy.load(std::memory_order_acquire) != 0;
    const bool redecode = control->needs_redecode.load(std::memory_order_acquire) != 0;
    if (same && !redecode && (filled || busy)) {
        return;
    }
    if (!redecode && !cancels_decode(control->command, next)) {
        next.revision = control->command.revision;
        control->command = next;
        control->dirty = true;
        control->cv.notify_one();
        return;
    }
    control->needs_redecode.store(0, std::memory_order_release);
    const uint64_t revision = control->revision.fetch_add(1, std::memory_order_acq_rel) + 1;
    next.revision = revision;
    control->command = next;
    control->dirty = true;
    control->cv.notify_one();
}

void ibms_preview_video_set_generation(IBMSPreviewVideo *video, uint64_t generation) {
    auto *control = reinterpret_cast<Control *>(video);
    if (!control) {
        return;
    }
    std::vector<uint8_t> dropped;
    {
        std::lock_guard<std::mutex> lock(control->mu);
        if (control->stop.load(std::memory_order_acquire)) {
            return;
        }
        const uint64_t revision = control->revision.fetch_add(1, std::memory_order_acq_rel) + 1;
        control->accepted.store(generation, std::memory_order_release);
        control->command.generation = generation;
        control->command.revision = revision;
        control->stats.doubles[IBMS_PV_GENERATION] = static_cast<double>(generation);
        control->stats.ints[IBMS_PV_VALID] = 0;
        control->stats.doubles[IBMS_PV_FRAME_SERIAL] += 1;
        control->frame_width = 0;
        control->frame_height = 0;
        control->frame_stride = 0;
        dropped.swap(control->frame);
        control->slot_filled.store(0, std::memory_order_release);
        control->needs_redecode.store(1, std::memory_order_release);
        control->dirty = false;
        control->cv.notify_one();
    }
}

void ibms_preview_video_read_stats(
    IBMSPreviewVideo *video,
    int64_t *ints,
    double *doubles,
    char *codec_name,
    int codec_cap,
    char *format_name,
    int format_cap,
    char *error_text,
    int error_cap) {
    auto *control = reinterpret_cast<Control *>(video);
    if (!control) {
        return;
    }
    std::lock_guard<std::mutex> lock(control->mu);
    read_stats_locked(control, ints, doubles, codec_name, codec_cap, format_name, format_cap, error_text, error_cap);
}

int ibms_preview_video_copy(
    IBMSPreviewVideo *video,
    uint64_t generation,
    uint8_t *dst,
    int dst_bytes,
    int64_t *ints,
    double *doubles,
    char *codec_name,
    int codec_cap,
    char *format_name,
    int format_cap,
    char *error_text,
    int error_cap) {
    auto *control = reinterpret_cast<Control *>(video);
    if (!control) {
        return -1;
    }
    std::lock_guard<std::mutex> lock(control->mu);
    if (control->stop.load(std::memory_order_acquire)) {
        read_stats_locked(control, ints, doubles, codec_name, codec_cap, format_name, format_cap, error_text, error_cap);
        return -1;
    }
    if (generation != control->accepted.load(std::memory_order_acquire) || control->stats.ints[IBMS_PV_VALID] != 1
        || control->frame.empty()) {
        if (generation != control->accepted.load(std::memory_order_acquire) || control->frame.empty()) {
            control->stats.ints[IBMS_PV_VALID] = control->frame.empty() ? 0 : control->stats.ints[IBMS_PV_VALID];
        }
        read_stats_locked(control, ints, doubles, codec_name, codec_cap, format_name, format_cap, error_text, error_cap);
        return 1;
    }
    const int need = control->frame_stride * control->frame_height;
    if (!dst || dst_bytes < need || static_cast<int64_t>(control->frame.size()) < need) {
        read_stats_locked(control, ints, doubles, codec_name, codec_cap, format_name, format_cap, error_text, error_cap);
        return 2;
    }
    std::memcpy(dst, control->frame.data(), static_cast<size_t>(need));
    control->stats.ints[IBMS_PV_COPIES] += 1;
    read_stats_locked(control, ints, doubles, codec_name, codec_cap, format_name, format_cap, error_text, error_cap);
    return 0;
}

void ibms_preview_video_debug_arm_worker_fault(void) {
    g_worker_fault.store(1, std::memory_order_release);
}

void ibms_preview_video_close(IBMSPreviewVideo *video) {
    auto *control = reinterpret_cast<Control *>(video);
    if (!control) {
        return;
    }
    std::lock_guard<std::mutex> lock(control->mu);
    control->stop.store(true, std::memory_order_release);
    control->revision.fetch_add(1, std::memory_order_acq_rel);
    control->dirty = true;
    control->cv.notify_one();
}
