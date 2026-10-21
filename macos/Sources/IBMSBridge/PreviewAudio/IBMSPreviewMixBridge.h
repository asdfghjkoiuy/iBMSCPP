#ifndef IBMS_PREVIEW_MIX_BRIDGE_H
#define IBMS_PREVIEW_MIX_BRIDGE_H

#include <stdint.h>

/* UB0：未来单 source 音频产品的 context-owned 实时 SPSC 桥。
   C++17 实现，对外是 C ABI。部署目标 macOS 14。本头尚未接入 Legacy、CMake 或 AVAudioEngine。

   这里没有 global 安装槽，也没有“当前 session”指针。每个函数都显式接收 context 或 registration。
   进程内 session 计数器只在 config.session == 0 时分配 id，回调不会去读它来找 context。

   桥只搬运已经生成的 48 kHz stereo Float32 PCM，并适配成交错或 planar 输出。
   不做采样率转换、解码、声部混音，也不持有 64 MB 资源缓存。
   rate 是 chart 斜率元数据。桥不按 rate 拉伸样本；拉伸或重混由 context 外的 worker 完成。

   sourceSample 是本次 source 回调时间线上的样本编号。hostTicks 是调用者给出的 mach host 时间戳。
   二者都不是设备 sample，也不是扬声器 presentation 时间。本桥不加 presentationLatency。
   chart 只在 validFrames 上按 rate/48000 前进。wall 只按有效消费帧/48000 前进，rate 不乘 wall。
   underrun 输出静音并冻结已有效的 chart 与 wall，不按缺口跳 cue。
   只有 validFrames>0 的 span 携带非零 rate。静音 span 的 rate 为 0，chartStart/wallStart 停在冻结点。
   命令里的 rate 看 ack，不靠静音 span 反推。
   epoch 变化的那个回调只记 flush，不把同一块再记入 pause 或 stop。
   其后的暂停回调记 pause，停止回调记 stop。尚无有效 PCM 的起播静音记 prime。
   已经有过有效消费之后再缺 PCM，记 real underrun。seek 把 wall 的局部原点归零，rate 不清 wall。

   —— 调用方要自己保证的屏障。C 不等待 CoreAudio，也不证明图已经安静 ——
   C 不 join、不轮询、不假装 AVAudioEngine / CoreAudio 的 stop 或图解绑已经排空回调。
   engine.stop 的返回、registration 计数变成 0、close_queries，都不是“音频线程不会再进旧闭包”的证明。
   Swift 后续接入时，每个 render 闭包必须强持有自己那份 registration（具体对象）。
   不要用 Unmanaged.passUnretained 裸指针当闭包所有权。
   图解绑之后，还要等已经进入系统队列的那次闭包返回，再由非实时 owner 调用 registration_release。
   音频线程上禁止 registration_release、reader_release、context_release，也禁止在那里做最后一次 Swift 释放。
   证明不了旧闭包已结束时，继续持有 context，不要提前 free。

   1. create 之后，非实时 owner 持有 context。
   2. 把 render 装进音频图之前，离线 registration_retain。这份 registration 一直持有 context。
   3. “retain 已经完成”先于“图可以调用 render”。这个同步由 Swift 保证。
   4. 任何 live / copy_clocks / clock_at_source_sample / span_map / ticks_to_seconds / read_ack / stats
      都必须带着事先 retain 的 reader。裸 context 不能再当这些查询的入口。
      reader_retain、reader_release、close_queries、context_release 只由同一条非实时 owner 线程串行调用。
      查询线程可以并发使用已经 retain 的 reader，但 owner 必须先 join 这些线程，再 reader_release。
   5. begin_retire 停止新的命令和新的 PCM 生产。它不释放 context，也不证明回调已结束。
   6. 入口已经观察到 retire 的 render（包括迟到回调）把整块输出写成静音，
      不消费 ring，不推进 chart/wall，不在回调里 release 或 free。
      同一次回调若在入口时还没 retire、提交前才看到 retire，也会整块改回静音并且不提交 read。
      已经提交的那一个量子无法撤回。
   7. 拆除回调节点是 Swift / 系统的屏障。屏障之后才离线 registration_release。
   8. owner join worker 之后调用 note_worker_exited。C 不观察线程。
   9. owner join 全部 query 线程后 close_queries。此后新的 reader_retain 失败。
      然后释放已经持有的 reader。context_release 还要求 begin_retire 已经发生。
      未 retire、query 入口未关、reader 或 registration 仍在、worker 未标记退出，都不释放。
      回调路径不会做最后一次 release。

   同一 context 同时只允许一个 render 线程、一个控制线程、一个 producer 线程。
   poll / write / fill_frames / 命令仍用 context，只属于 worker 或控制线程；
   owner 在 note_worker_exited 之前 join 它们，不能和 context_release 并发。

   多字快照（desired、ack、live、history）的唯一写者按下面的表。发布用 uint64 sequence：
   奇数 seq、全部 payload 的 seq_cst store、偶数 seq。读者 seq_cst 读 seq、payload、再读 seq，
   只接受两次相同的非零偶数。这依赖 C11 seq_cst 总序与同线程 sequenced-before；
   单次观察窗口内若发生 2^63 次发布才会回到同一偶数。本桥把该 ABA 前提写成运行约束。
   读者最多重试 8 次（回调里读 desired 为 2 次）。失败就放弃这次快照，不自旋，不等待锁。
   TSan 只能证明没有 data race，不能代替上面的总序论证。

   原子所有权：
   - desired.*            写：控制线程。读：render、producer poll。
   - ack.*                写：render。读：控制侧 read_ack、producer poll、owner。
   - write 下标、样本、meta 写：producer。读：render（下标 acquire 之后才读样本）。
   - read 下标            写：render。读：producer。
   - live / history / logWrite 写：render。读：时钟读者与 owner。
   - 回调计数、pause/prime/flush/stop/underrun 计数、timing 槽 写：render。读：owner 的 stats。
   - retired              写：owner begin_retire。读：render、命令、write、retain。
   - registrationCount    写：owner retain/release。读：owner context_release。回调不碰。
   - readerCount          写：owner reader_retain/release。读：owner context_release。查询线程不改它。
   - queriesClosed        写：owner close_queries。读：reader_retain、context_release。
   - workerExited         写：owner note_worker_exited。读：owner context_release。回调不碰。
   consumedChart、consumedWall、epoch、paused 等普通字段只由 render 线程写。
   stats 会读这些普通字段并分配排序缓冲，因此只能在 render 不再进入之后离线调用。
   暂停不算：暂停时 source callback 仍会进 render。播放中的 UI 用 live / span_map，不要调用 stats。
   命令普通字段只由控制线程写。
   prepare 与 debug_preset_cursor 要求尚无回调且无并发。 */

#ifdef __cplusplus
extern "C" {
#endif

#define IBMS_PREVIEW_MIX_ABI 2
#define IBMS_PREVIEW_MIX_SOURCE_RATE 48000.0
#define IBMS_PREVIEW_MIX_MAX_CALLBACK_FRAMES 2048

enum {
    IBMS_PREVIEW_MIX_STATE_PLAYING = 1,
    IBMS_PREVIEW_MIX_STATE_UNDERRUN = 2,
    IBMS_PREVIEW_MIX_STATE_PAUSED = 4,
    IBMS_PREVIEW_MIX_STATE_FLUSH = 8,
    IBMS_PREVIEW_MIX_STATE_INVALID = 16,
    IBMS_PREVIEW_MIX_STATE_PRIME = 32,
    IBMS_PREVIEW_MIX_STATE_STOPPED = 64,
    IBMS_PREVIEW_MIX_STATE_RETIRED = 128
};

enum {
    IBMS_PREVIEW_MIX_CMD_NONE = 0,
    IBMS_PREVIEW_MIX_CMD_RATE = 1,
    IBMS_PREVIEW_MIX_CMD_PAUSE = 2,
    IBMS_PREVIEW_MIX_CMD_RESUME = 3,
    IBMS_PREVIEW_MIX_CMD_SEEK = 4,
    IBMS_PREVIEW_MIX_CMD_STOP = 5
};

enum {
    IBMS_PREVIEW_MIX_LAYOUT_INTERLEAVED = 1,
    IBMS_PREVIEW_MIX_LAYOUT_PLANAR = 2
};

enum {
    IBMS_PREVIEW_MIX_OK = 0,
    IBMS_PREVIEW_MIX_ERR_ARGUMENT = 1,
    IBMS_PREVIEW_MIX_ERR_STATE = 2,
    IBMS_PREVIEW_MIX_ERR_FULL = 3,
    IBMS_PREVIEW_MIX_ERR_EPOCH = 4,
    IBMS_PREVIEW_MIX_ERR_RETIRED = 5,
    IBMS_PREVIEW_MIX_ERR_BUSY = 6,
    IBMS_PREVIEW_MIX_ERR_UNSUPPORTED = 7
};

enum {
    IBMS_PREVIEW_MIX_TIME_SOURCE_SAMPLE_VALID = 1,
    IBMS_PREVIEW_MIX_TIME_HOST_VALID = 2,
    IBMS_PREVIEW_MIX_TIME_RATE_SCALAR_VALID = 4
};

typedef struct IBMSPreviewMixContext IBMSPreviewMixContext;
typedef struct IBMSPreviewMixRegistration IBMSPreviewMixRegistration;
typedef struct IBMSPreviewMixReader IBMSPreviewMixReader;

typedef struct IBMSPreviewMixConfig {
    uint64_t session;
    double sourceRate;
    uint32_t capacityFrames;
    uint32_t blockFrames;
    uint32_t logCapacity;
} IBMSPreviewMixConfig;

typedef struct IBMSPreviewMixClock {
    uint64_t session;
    uint64_t epoch;
    uint64_t serial;
    int64_t sourceSample;
    uint64_t hostTicks;
    uint64_t logicalFrame;
    double chartStart;
    double rate;
    double wallStart;
    uint32_t frameCount;
    uint32_t validFrames;
    uint32_t hostFrameOffset;
    uint32_t state;
    uint32_t timeFlags;
    uint32_t reserved;
} IBMSPreviewMixClock;

typedef struct IBMSPreviewMixTime {
    int64_t sourceSample;
    uint64_t hostTicks;
    uint32_t flags;
    float rateScalar;
} IBMSPreviewMixTime;

typedef struct IBMSPreviewMixBuffer {
    float *data;
    uint32_t channels;
    uint32_t capacityFrames;
} IBMSPreviewMixBuffer;

typedef struct IBMSPreviewMixOutput {
    IBMSPreviewMixBuffer *buffers;
    uint32_t bufferCount;
    uint32_t frames;
    uint32_t layout;
} IBMSPreviewMixOutput;

typedef struct IBMSPreviewMixProduce {
    uint64_t appliedSerial;
    uint64_t epoch;
    double chart;
    double rate;
    double wall;
    int resetCursor;
    int paused;
    int stopped;
    int canWrite;
    uint64_t seenAdopt;
} IBMSPreviewMixProduce;

typedef struct IBMSPreviewMixAck {
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
} IBMSPreviewMixAck;

typedef struct IBMSPreviewMixStats {
    uint64_t realUnderrunFrames;
    uint64_t primeSilenceFrames;
    uint64_t discardFrames;
    uint64_t pauseFrames;
    uint64_t stopFrames;
    uint64_t flushSpans;
    uint64_t flushSilenceFrames;
    uint64_t retiredSilenceFrames;
    uint64_t logOverflow;
    uint64_t logWrite;
    uint64_t callbacks;
    uint64_t protocolFaults;
    uint64_t overrunWrites;
    uint64_t callbackNsMax;
    uint64_t callbackNsP95;
    uint64_t callbackNsP99;
    uint32_t timingSamples;
    uint32_t capacityFrames;
    uint32_t blockFrames;
    uint32_t logCapacity;
    uint32_t lockFree;
    uint64_t session;
    double sourceRate;
    double consumedChart;
    double consumedWall;
    uint32_t registrationCount;
    uint32_t retired;
    uint32_t workerExited;
} IBMSPreviewMixStats;

void ibms_preview_mix_config_init(IBMSPreviewMixConfig *config);

/* 失败返回 NULL。成功后 owner 持有 context，此时 registration 计数为 0。 */
IBMSPreviewMixContext *ibms_preview_mix_create(const IBMSPreviewMixConfig *config);

/* 离线调用。retire 之后的新 retain 失败并返回 NULL。返回的 registration 持有 context。 */
IBMSPreviewMixRegistration *ibms_preview_mix_registration_retain(IBMSPreviewMixContext *ctx);

/* 离线调用。不释放 context。同一 registration 只 release 一次。
   不在音频线程调用。图解绑不等于已经排队的旧闭包已经返回。 */
void ibms_preview_mix_registration_release(IBMSPreviewMixRegistration *reg);

/* 离线、owner 线程。retire 之后仍可 retain，用来读已经冻结的 clock。
   close_queries 之后失败。返回的 reader 持有 context，查询期间必须一直持有。 */
IBMSPreviewMixReader *ibms_preview_mix_reader_retain(IBMSPreviewMixContext *ctx);

/* 离线、owner 线程。不释放 context。先 join 使用这份 reader 的查询线程。 */
void ibms_preview_mix_reader_release(IBMSPreviewMixReader *reader);

/* 离线、owner 线程。关掉新的 reader_retain。不释放，不等待已经在跑的查询。 */
void ibms_preview_mix_close_queries(IBMSPreviewMixContext *ctx);

/* 停止后续命令与生产。不释放，不等待回调结束。 */
void ibms_preview_mix_begin_retire(IBMSPreviewMixContext *ctx);

/* owner 在 worker 已经退出之后调用。C 本身不观察线程。 */
void ibms_preview_mix_note_worker_exited(IBMSPreviewMixContext *ctx);

/* 非实时 owner 线程。返回 OK 才表示 context 已释放，指针失效。
   未 begin_retire 返回 ERR_STATE，指针仍有效。
   query 入口未关、reader 或 registration 仍在、或 worker 未标记退出，返回 ERR_BUSY，指针仍有效。
   C 不在这里等待 CoreAudio。调用方要先关掉控制/查询入口并等在途读者退出。
   不得在回调里调用。 */
int ibms_preview_mix_context_release(IBMSPreviewMixContext *ctx);

/* 仅在尚无 render 时设置初始 rate 与 chart。rate 必须在 [0.25, 4]。 */
int ibms_preview_mix_prepare(IBMSPreviewMixContext *ctx, double rate, double chart);

/* 控制线程独占。快照同时带上暂停、停止、rate、seek chart 与 seek 修订。
   rate / seek / stop 增加 epoch；pause / resume 不增加。rate 不清除暂停或 seek。 */
int ibms_preview_mix_command_rate(IBMSPreviewMixContext *ctx, double rate, uint64_t requestHost);
int ibms_preview_mix_command_pause(IBMSPreviewMixContext *ctx, uint64_t requestHost);
int ibms_preview_mix_command_resume(IBMSPreviewMixContext *ctx, uint64_t requestHost);
int ibms_preview_mix_command_seek(IBMSPreviewMixContext *ctx, double chart, uint64_t requestHost);
int ibms_preview_mix_command_stop(IBMSPreviewMixContext *ctx, uint64_t requestHost);

/* producer 线程。state 的 appliedSerial / seenAdopt / epoch / rate / chart / wall 由调用者保存。
   仅当 desired 与 ack 是同一张快照时更新。返回 OK、ERR_BUSY、ERR_RETIRED 或 ERR_ARGUMENT。 */
int ibms_preview_mix_poll(IBMSPreviewMixContext *ctx, IBMSPreviewMixProduce *state);

/* pcm 指向 frames*2 个交错 Float32（L,R）。frames 必须等于 blockFrames。
   chartStart/rate/epoch 写入该块元数据。epoch 必须等于已 ack 的 epoch。暂停、停止或 retire 时拒绝。 */
int ibms_preview_mix_write(IBMSPreviewMixContext *ctx, const float *interleavedStereo, uint32_t frames,
                           double chartStart, double rate, uint64_t epoch);

uint64_t ibms_preview_mix_fill_frames(IBMSPreviewMixContext *ctx);
int ibms_preview_mix_read_ack(IBMSPreviewMixReader *reader, IBMSPreviewMixAck *out);

/* 实时回调。registration 必须仍被 owner 持有。合法静音也返回 OK。
   不分配、不加锁、不释放 registration。
   固定立体声：INTERLEAVED 必须 bufferCount==1 且 channels==2；
   PLANAR 必须 bufferCount==2 且每个 channels==1。
   其它 layout 返回 ERR_ARGUMENT，不写调用方缓冲，不消费 ring。
   frames 超过 2048 或超过 ring capacity 时，不消费 ring，不发布 clock。
   若立体声形状本身合法，先把请求的整块清零，再返回 ERR_UNSUPPORTED。
   不会截成 2048 再返回 OK。 */
int ibms_preview_mix_render(IBMSPreviewMixRegistration *reg, const IBMSPreviewMixTime *time,
                            IBMSPreviewMixOutput *output);

int ibms_preview_mix_live(IBMSPreviewMixReader *reader, IBMSPreviewMixClock *out);
int ibms_preview_mix_clock_at_source_sample(IBMSPreviewMixReader *reader, int64_t sourceSample,
                                            IBMSPreviewMixClock *out);
uint32_t ibms_preview_mix_copy_clocks(IBMSPreviewMixReader *reader, IBMSPreviewMixClock *dst, uint32_t capacity);

/* hostSeconds 使用回调 host 时间戳加 source 帧偏移，不含扬声器延迟。
   chart 与 wall 都只走到 validFrames，越过 validFrames 就停在冻结点。index 超出 span 返回 0。 */
int ibms_preview_mix_span_map(IBMSPreviewMixReader *reader, const IBMSPreviewMixClock *span, uint32_t index,
                              double *hostSeconds, double *chart, double *wall, int *advanced);

double ibms_preview_mix_ticks_to_seconds(IBMSPreviewMixReader *reader, uint64_t ticks);
uint64_t ibms_preview_mix_host_ticks(void);

/* 离线诊断，会分配排序缓冲。调用期间必须持有 reader，且 render 已经不会再进入。
   暂停时 callback 仍在跑，不能在暂停中用 stats 当播放 UI。播放中用 live / span_map。 */
void ibms_preview_mix_stats(IBMSPreviewMixReader *reader, IBMSPreviewMixStats *out);

/* harness 用。尚无回调时把 SPSC 光标放到 logicalFrame（必须按 block 对齐）。产品回调不要调用。 */
int ibms_preview_mix_debug_preset_cursor(IBMSPreviewMixContext *ctx, uint64_t logicalFrame, double chart,
                                         double wall);

#ifdef __cplusplus
}
#endif

#endif
