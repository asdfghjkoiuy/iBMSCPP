#ifndef IBMS_PREVIEW_VIDEO_H
#define IBMS_PREVIEW_VIDEO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Applied BGRA slot budget. Larger coded frames are rejected before decode. */
#define IBMS_PREVIEW_VIDEO_FRAME_BUDGET 16777216

/*
 * RESIDENT and PEAK count only the applied BGRA frame.
 * They are not process RSS and do not include decoder references, packets,
 * swscale scratch, or Swift copies.
 * PTS and seek targets are normalized by the video stream start_time.
 * Media time past the end holds the last frame.
 * close returns without joining; inflight decoders stay capped.
 */

typedef struct IBMSPreviewVideo IBMSPreviewVideo;

enum {
    IBMS_PV_PROBED = 0,
    IBMS_PV_FAILED = 1,
    IBMS_PV_WIDTH = 2,
    IBMS_PV_HEIGHT = 3,
    IBMS_PV_STRIDE = 4,
    IBMS_PV_ORIGINAL_W = 5,
    IBMS_PV_ORIGINAL_H = 6,
    IBMS_PV_AUDIO_STREAMS = 7,
    IBMS_PV_AUDIO_DECODED = 8,
    IBMS_PV_AUDIO_DISCARDED = 9,
    IBMS_PV_SEEK_COUNT = 10,
    IBMS_PV_DECODED_FRAMES = 11,
    IBMS_PV_DROPPED_STALE = 12,
    IBMS_PV_VALID = 13,
    IBMS_PV_HAS_SEEK = 14,
    IBMS_PV_COPIES = 15,
    IBMS_PV_INT_COUNT = 16
};

enum {
    IBMS_PV_PTS = 0,
    IBMS_PV_DURATION = 1,
    IBMS_PV_LAST_SEEK = 2,
    IBMS_PV_RATE = 3,
    IBMS_PV_RESIDENT = 4,
    IBMS_PV_PEAK = 5,
    IBMS_PV_GENERATION = 6,
    IBMS_PV_FRAME_SERIAL = 7,
    IBMS_PV_DOUBLE_COUNT = 8
};

void ibms_preview_video_layout(int *int_count, int *double_count);
int ibms_preview_video_inflight(void);
int ibms_preview_video_inflight_limit(void);
void ibms_preview_video_decoder_inventory(char *names, int cap, int *video_count, int *audio_count);

IBMSPreviewVideo *ibms_preview_video_open(const char *path, uint64_t generation);
void ibms_preview_video_command(
    IBMSPreviewVideo *video,
    double media_seconds,
    double rate,
    int playing,
    uint64_t generation);
void ibms_preview_video_set_generation(IBMSPreviewVideo *video, uint64_t generation);
void ibms_preview_video_read_stats(
    IBMSPreviewVideo *video,
    int64_t *ints,
    double *doubles,
    char *codec_name,
    int codec_cap,
    char *format_name,
    int format_cap,
    char *error_text,
    int error_cap);
/* 0 copied, 1 no frame, 2 dst too small, -1 closed. */
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
    int error_cap);
void ibms_preview_video_close(IBMSPreviewVideo *video);

/* Next worker throws before decode. The handle stays readable until close. */
void ibms_preview_video_debug_arm_worker_fault(void);

#ifdef __cplusplus
}
#endif

#endif
