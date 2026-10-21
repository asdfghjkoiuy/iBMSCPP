# AT 有界调度（2026-10-21）

只改 `macos/Sources/IBMSNative/PreviewUnifiedAudioWorker.swift`。没有改 GroupedMixer、测试断言、CMake、MixBridge、窗口或第三方。没有做 asset 预索引。预算和采样率分档仍开着。

## 调度

每个输出块之前，已打开组用 `ibms_preview_grouped_fed` 当 native 游标。`end` 已经被这个游标读过的声部从池里去掉。不调用 `ibms_preview_grouped_reset`，SRC 里已经吃进去的历史留在滤波器里。

cue 只在自己那一组的输入预读窗口里进入声部池。窗口外的未来 cue 留在游标上，不占 32 声部。容量按声学区间：新 cue 的 `[chartStart, chartEnd)` 与池中声部重叠数达到 32 时，抢走最早的重叠声部。重叠不够 32 但池已满时不抢非重叠声部，这个 cue 留到下一块。

声部列表空了之后，只要组已经打开，每个输出块仍然 `ibms_preview_grouped_pull`。`set_voices` 把该组声部数写成 0，不重新预卷。静音块把 SRC 轴继续往前送。增益 0.5 和限幅仍在 pull 里。

## SHA-256

- `macos/Sources/IBMSNative/PreviewUnifiedAudioWorker.swift`：`6c691a4d4f6e9c7da532214e7e09b7c056a5a693ca1db537060b7b45885e9d98`
- `macos/Sources/IBMSBridge/PreviewAudio/IBMSPreviewGroupedMixer.h`：`c4a1d43f2f169b0a227a0068192eedf87dda3329dd0092e0fad9a624f0fbb426`（未改）
- `macos/Sources/IBMSBridge/PreviewAudio/IBMSPreviewGroupedMixer.cpp`：`c4a1cdb43abd56226118894a869e953fc383211104bef4519fd7d3c68300ec7d`（未改）
- `macos/Tests/LegacyPreviewAudioTests.swift`：`11b4e8a1e8d5b0ee6502772711d12868b28c8be8333cdf90ca003a0941bb7970`（未改）
- `/tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests`：`1674302aaf864f3ee484ef453f145004412bfb729487c0c7a674854cd1bede91`

## 命令

编译，退出码 0。链接有既有警告：`ld: warning: ignoring duplicate libraries: 'macos/libIBMSPreviewMixBridge.a'`。

```sh
cmake --build /tmp/ibms-ubm-b1-build --target IBMSNativePreviewAudioTests
```

完整音频，退出码 1。stdout `/tmp/at-audio-full2.log`，stderr `/tmp/at-audio-full2.err`。仓库副本 `audio-product-integration/probes/AT/full-audio-first-fail.log`。墙钟约 44.5 秒。

```sh
stdbuf -oL -eL /tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
```

先前的首失败 `140 unique stole` 没有再出现。工作集在 `UA4` 之前，这次日志里已经有 `UA4` 和 `UA6`。

stderr 第一行也是唯一一行：

```
overlap opens 1, main 0
```

这是 `testChordInflightIsSeparateFromResidentBudget` 后半段：同一 `overlap.wav`，拍 0 和拍 0.2，预算 1000。断言是 `calls >= 2 && mainCalls == 0`。实测 `calls=1`，`mainCalls=0`。同一句之前的 `diagnosticScheduledCues == 2` 和 `diagnosticDroppedVoices == 0` 已经通过，否则会先打印另一句。原断言没有改。

这次没有 UA8 的 PCM 行。套件在 dense 100/200 之前退出。

stdout：

```
UA2 chart-path: playChartReturn=2.828ms readyDelay=89.361ms deferredHit=0.015ms loads=2 voices=7
UA4 long-bgm: sourceBytes=42336044 peakDecoded=0 streamBlock=1179648
UA6 rate: ceiling=4.00 interval=0.250 stopWall=1.000 hereChart=0.408 hereWall=0.204
```

## 未修

- `overlap.wav` 两次音符只记到 1 次 `traceFileOpen`。`openFile` 仍是每个资源打开一次。没有为了这个计数去重开文件，也没有放宽 `calls >= 2`。
- 100/200 短音在 0.5/1/2/4 的逐格 PCM 这次没跑到。
- 预算、采样率分档、asset 预索引没有做。
- GroupedMixer 的增益和限幅没有改。
