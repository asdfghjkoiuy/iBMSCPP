#ifndef IBMS_PREVIEW_GROUPED_MIXER_H
#define IBMS_PREVIEW_GROUPED_MIXER_H

#include <stdint.h>

/* Worker 侧有界分组混音。不在音频回调里调用 pull / set_voices / rebase。
   回调只走 ibms_preview_render_drive，里面再进 ABI2 MixBridge。
   不修改 IBMSPreviewMixBridge。 */

#ifdef __cplusplus
extern "C" {
#endif

#define IBMS_PREVIEW_GROUP_COUNT 4
#define IBMS_PREVIEW_GROUP_WARMUP 720
#define IBMS_PREVIEW_GROUP_MAX_VOICES 32
#define IBMS_PREVIEW_GROUP_OUTPUT_RATE 48000.0

enum {
    IBMS_PREVIEW_GROUP_OK = 0,
    IBMS_PREVIEW_GROUP_ERR_ARGUMENT = 1,
    IBMS_PREVIEW_GROUP_ERR_UNSUPPORTED = 2,
    IBMS_PREVIEW_GROUP_ERR_SRC = 3
};

typedef struct IBMSPreviewGroupedMixer IBMSPreviewGroupedMixer;
typedef struct IBMSPreviewRenderSlot IBMSPreviewRenderSlot;
typedef struct IBMSPreviewMixRegistration IBMSPreviewMixRegistration;

typedef struct IBMSPreviewGroupedVoice {
    const float *samples;
    int channels;
    int64_t frames;
    int64_t origin;
    int64_t start;
    int64_t end;
    float gainL;
    float gainR;
} IBMSPreviewGroupedVoice;

/* 精确四档，或升到不小于 sampleRate 的那一档。高于 192 kHz 返回 UNSUPPORTED。 */
int ibms_preview_grouped_classify(double sampleRate, int *groupIndex, double *groupRate);

/* ratio = 输出采样率 / 输入采样率，必须 >= 1。交错立体声。返回写出的帧数，失败返回负值。 */
int ibms_preview_grouped_upsample(const float *interleavedStereo, int inputFrames, double ratio, float *destination,
                                  int destinationCapacity);

IBMSPreviewGroupedMixer *ibms_preview_grouped_create(void);
void ibms_preview_grouped_destroy(IBMSPreviewGroupedMixer *mixer);

/* 不释放对象。清掉各组 SRC、声部指针和暂存。调用时不能并发 pull。
   lease_create 成功之后，mixer 只由 try_release destroy 一次。
   bridge.mixer 是同一对象的非拥有别名。 */
void ibms_preview_grouped_reset(IBMSPreviewGroupedMixer *mixer);

/* 替换这一组的声部。指针保持到下一次 set 或 destroy。新组从 chartSeconds 做 720 帧预卷。 */
int ibms_preview_grouped_set_voices(IBMSPreviewGroupedMixer *mixer, int group, const IBMSPreviewGroupedVoice *voices,
                                    int count, double chartSeconds, double playbackRate);

/* 每个已经打开的组从同一 chart 重混。分数相位留在 SRC 里。 */
int ibms_preview_grouped_rebase(IBMSPreviewGroupedMixer *mixer, double chartSeconds, double playbackRate);

/* 这一组下一次要读的 native 帧。组还没打开时返回 0。Swift 用它放页窗口，不拿它当 chart。 */
int64_t ibms_preview_grouped_fed(const IBMSPreviewGroupedMixer *mixer, int group);

/* 各组为同一个输出区间各产 frames。inputUsed 是预读，不是 chart。
   累加后乘 0.5，超出 ±1 限幅。peak 是限幅前的绝对值峰值。 */
int ibms_preview_grouped_pull(IBMSPreviewGroupedMixer *mixer, float *interleavedStereo, int frames, int *inputUsed,
                              float *peakBeforeLimit, int *overloadSamples);

IBMSPreviewRenderSlot *ibms_preview_render_slot_create(int tapCapacityFrames);
void ibms_preview_render_slot_destroy(IBMSPreviewRenderSlot *slot);
void ibms_preview_render_slot_retire(IBMSPreviewRenderSlot *slot);
void ibms_preview_render_slot_reset_tap(IBMSPreviewRenderSlot *slot, int recording);
int ibms_preview_render_slot_inflight(IBMSPreviewRenderSlot *slot);
int ibms_preview_render_slot_tap_frames(IBMSPreviewRenderSlot *slot);
/* 把已发布的 tap 左声道拷出去。返回帧数。 */
int ibms_preview_render_slot_copy_tap_left(IBMSPreviewRenderSlot *slot, float *destination, int capacity);

/* 音频回调。不分配、不加锁、不释放 registration。 */
int ibms_preview_render_drive(IBMSPreviewRenderSlot *slot, IBMSPreviewMixRegistration *registration,
                              const void *audioTimeStamp, unsigned int frames, void *audioBufferList);

/* adapter 用。hostTicks 是 mach 时间。interleaved 可为 NULL，此时只写内部静音缓冲再发布。
   超过 2048 的请求在这里按不超过 2048 的量子分次提交，不让桥把整块判成 UNSUPPORTED 后假装成功。 */
int ibms_preview_render_drive_buffer(IBMSPreviewRenderSlot *slot, IBMSPreviewMixRegistration *registration,
                                     uint64_t hostTicks, unsigned int frames, float *interleavedStereo);

/* 一次图绑定的寿命。闭包持有 holder，析构只做原子减计数。
   非 RT 的 try_release 要等 request_retire、holder 归零、inflight 归零，并且没有 query。
   binding 不匹配的 drive 只清调用方缓冲，不进入 MixBridge，因此旧闭包不会写出新一代。 */
typedef struct IBMSPreviewRenderLease IBMSPreviewRenderLease;

/* 成功时接管 mixer。调用方之后不得 destroy。失败返回 NULL，不接管任何指针。 */
IBMSPreviewRenderLease *ibms_preview_render_lease_create(IBMSPreviewRenderSlot *slot,
                                                        IBMSPreviewMixRegistration *registration, void *context,
                                                        void *reader, IBMSPreviewGroupedMixer *mixer);
void ibms_preview_render_lease_hold(IBMSPreviewRenderLease *lease);
void ibms_preview_render_lease_unhold(IBMSPreviewRenderLease *lease);
uint64_t ibms_preview_render_lease_binding(const IBMSPreviewRenderLease *lease);
uint64_t ibms_preview_render_lease_rebind(IBMSPreviewRenderLease *lease);
void ibms_preview_render_lease_request_retire(IBMSPreviewRenderLease *lease);
int ibms_preview_render_lease_holders(const IBMSPreviewRenderLease *lease);
int ibms_preview_render_lease_query_begin(IBMSPreviewRenderLease *lease);
void ibms_preview_render_lease_query_end(IBMSPreviewRenderLease *lease);
void *ibms_preview_render_lease_reader(IBMSPreviewRenderLease *lease);
IBMSPreviewRenderSlot *ibms_preview_render_lease_slot(IBMSPreviewRenderLease *lease);
int ibms_preview_render_lease_last_status(const IBMSPreviewRenderLease *lease);
int ibms_preview_render_lease_drive(IBMSPreviewRenderLease *lease, uint64_t binding, const void *audioTimeStamp,
                                    unsigned int frames, void *audioBufferList);
int ibms_preview_render_lease_drive_buffer(IBMSPreviewRenderLease *lease, uint64_t binding, uint64_t hostTicks,
                                           unsigned int frames, float *interleavedStereo);
/* 非 RT。释放成功返回 1，调用后 lease 指针作废。条件不够返回 0。 */
int ibms_preview_render_lease_try_release(IBMSPreviewRenderLease *lease);

#ifdef __cplusplus
}
#endif

#endif
