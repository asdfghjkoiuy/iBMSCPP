# AG 代际时钟（2026-10-21）

只改 `PreviewUnifiedAudioSession.swift`、`PreviewUnifiedAudioWorker.swift` 的 mailbox epoch 发布、`LegacyPreviewAudio.swift` 的 generation 读数，以及 `LegacyPreviewAudioTests.swift` 里去掉 `AW_ONLY` 的 `_exit` / `awHold`。没有改 CMake、C 桥、窗口、第三方，也没有清 C 时钟日志。

## 时钟

`submit` 见到新 generation 时，在 mailbox 锁内把该代标成尚未 ack，并把 `rememberedChart` / `rememberedWall` 置 0。ack 之前 `mappedClock` 只返回这个 origin，不读上一代 span。

Worker 在 `ibms_preview_mix_poll` 返回 OK（desired 与 ack 一致）之后，于 mailbox 锁内写下 `(generation, epoch)`。install / seek 要等到 epoch 离开命令前的值，才把这次发布当成新局部 origin。同代的 rate 只把已接受 epoch 的上界抬高，不把 chart/wall 清回 0。seek 与新 generation 重播收紧下界。

`mappedClock` 仍用 AS 的 host 选择。拷贝出来的 span 里，epoch 不在这一代 `[origin, accepted]` 内的，序列号按未发布处理。不按 host 回绕过滤，也不用 `installedGeneration` 代替 ack。

Legacy 读 chart/wall 时带上 `playbackGeneration`。

`AW_ONLY` 成功路径改为 `return`。播放器不再留在 `awHold` 里跳过析构。

## SHA-256

- `macos/Sources/IBMSNative/PreviewUnifiedAudioSession.swift`：`86f02b4a1c3aa4959b22e5a8cffbdce1d7c6ec588fd22a8e7a3550fe97f01765`
- `macos/Sources/IBMSNative/PreviewUnifiedAudioWorker.swift`：`abd4333724d67bd3c16dcea34d3ee1a7ad255fac80eda63336546e0cd7220997`
- `macos/Sources/IBMSNative/LegacyPreviewAudio.swift`：`99b51f1d69999ea75e2beb647a2774390b7434d8e1072ea7cdf2001d80ac92d2`
- `macos/Tests/LegacyPreviewAudioTests.swift`：`11b4e8a1e8d5b0ee6502772711d12868b28c8be8333cdf90ca003a0941bb7970`
- `/tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests`：`c0fc9019ce319009b5e271d5bf0617091a12b654325053aca09a4ad6291c8382`

## 命令

编译，退出码 0。链接有既有警告：`ld: warning: ignoring duplicate libraries: 'macos/libIBMSPreviewMixBridge.a'`。

```sh
cmake --build /tmp/ibms-ubm-b1-build --target IBMSNativePreviewAudioTests
```

定向测试都打印对应的 `AW … ok` 后从 `main` 返回。退出码都是 0。原有 0.02 等门限没有改。

```sh
AW_ONLY=external-gen /tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
AW_ONLY=external-final /tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
AW_ONLY=external-empty /tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
AW_ONLY=empty-old /tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
AW_ONLY=empty-sync /tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
```

完整音频跑到第一处失败。日志 `/tmp/ag-audio-full.log`。进程退出码 1。stderr 断言是 `140 unique stole`（`playUniqueChart(count: 140)`，`diagnosticStolenVoices != 0`）。同一次输出里还有更早刷出的 `UA2 chart-path: playChartReturn=4.232ms readyDelay=87.191ms deferredHit=0.019ms loads=2 voices=7`。没有改资源、预算或调度。

```sh
/tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests
```
