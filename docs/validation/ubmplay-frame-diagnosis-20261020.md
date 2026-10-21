# 旧预览帧节奏诊断（2026-10-20）

基线是 `out/validation/ubmplay-parity-20261020/before/` 里的 Metal 谱面和 BGA，不是更早的未整合原型。探针编译这份副本，不改产品源文件。优化 `-O`，目标 `arm64-apple-macosx14.0`。窗口是探针自己的 `NSWindow` / `MTKView`，标题 `UP-frame-probe`。没有采集其他应用，也没有用已经退出的旧进程。

帧间隔只统计 `CAMetalDrawable.addPresentedHandler` 回调里的 `presentedTime`。`draw(in:)` 次数和 `drawablePresentationCount` 只算提交，不算呈现。`presentedTime` 与回调里的 `CACurrentMediaTime()` 同一时间基，回调大约晚 0.3–0.4ms。这不是显示器扫描输出。

## 主屏

Built-in Retina Display，四项描述都是 120Hz，没有低于 `maximumFramesPerSecond` 的当前模式：

| 来源 | 结果 |
| --- | --- |
| `NSScreen.maximumFramesPerSecond` | 120 |
| `CGDisplayMode.refreshRate` | 120 |
| `CVDisplayLink` 名义周期 | 120Hz |
| `CADisplayLink.timestamp` 相邻差，1 秒，n=120 | p50 = p99 = 8.333ms |

`preferredFrameRateRange` 的 minimum、maximum、preferred 读数都是 0，没有拿它当刷新率。

## 怎么跑

客户区沿用旧预览默认 1000×720。谱面视口约 499×662 点，drawable 999×1324。BPM 120，画面终点第 64 拍，滚速 96。起播后丢掉 0.5 秒，再量约 2.7 秒，停止后再排空 0.5 秒回调。`MTKView` 保持 `isPaused = true`、`enableSetNeedsDisplay = true`。每次提交都配上了正的 `presentedTime`，时间没有倒退。每个场景另有 1 次 `presentedTime <= 0` 的回调，未进入间隔。

静音两场在普通窗口层级。音频、BGA、BMSON 五场把探针窗设为 `.floating` 并 `orderFrontRegardless()`。这五场在起播前和停止时 `occlusionState` 都不含 `.visible`；静音两场只在停止时采样，当时也不含 `.visible`。呈现时间仍然落在 120Hz 网格上。遮挡标志和扫描输出都没有被写成“已经看见画面”。

## 呈现间隔

下表的 p50 / p95 / p99 来自稳态 `presentedTime` 相邻差。相对 120Hz 的阈值是 12.5ms，相对 60Hz 定时器的阈值是 25ms。稳定的 16.7ms 已经大于 12.5ms，所以前一列高占比表示的是“呈现停在大约 60Hz”，不是帧间隔在乱跳。后一列才是超出定时器目标的长间隔。

| 场景 | 提交 / 呈现 | p50 | p95 | p99 | 最大 | >12.5ms | >25ms | 由中位间隔换算 | 首尾平均 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 普通静音 | 163 / 163 | 16.667 | 16.667 | 16.670 | 25.000 | 99.4% | 0.6% | 60.0Hz | 60.0Hz |
| 密谱静音 | 162 / 162 | 16.667 | 25.000 | 25.004 | 25.004 | 86.3% | 7.5% | 60.0Hz | 60.0Hz |
| 普通加音频 | 167 / 167 | 16.667 | 25.000 | 33.333 | 41.671 | 92.8% | 8.4% | 60.0Hz | 58.9Hz |
| 密谱加音频 | 134 / 134 | 16.667 | 50.000 | 100.001 | 116.667 | 78.9% | 24.1% | 60.0Hz | 48.7Hz |
| 图片 BGA | 162 / 162 | 16.667 | 25.004 | 33.334 | 33.334 | 81.4% | 15.5% | 60.0Hz | 59.8Hz |
| 视频 BGA | 163 / 163 | 16.667 | 25.000 | 25.000 | 33.334 | 78.4% | 7.4% | 60.0Hz | 60.2Hz |
| BMSON 普通静音 | 163 / 163 | 16.667 | 16.671 | 16.672 | 16.673 | 100% | 0% | 60.0Hz | 60.0Hz |

间隔落在 120Hz 网格上的个数（含预热，单位是 1/120 秒）：

| 场景 | 1 格 | 2 格 | 3 格 | 4 格及以上 |
| --- | --- | --- | --- | --- |
| 普通静音 | 2 | 190 | 1 | 0 |
| 密谱静音 | 27 | 139 | 27 | 0 |
| 普通加音频 | 13 | 161 | 11 | 4（最长达 5 格） |
| 密谱加音频 | 33 | 87 | 20 | 19（最长达 14 格，116.7ms） |
| 图片 BGA | 33 | 131 | 26 | 3 |
| 视频 BGA | 39 | 117 | 36 | 1 |
| BMSON 普通静音 | 1 | 192 | 0 | 0 |

普通静音的 `draw(in:)`、`needsDisplay` 和 tick 都是 163。密谱静音是 163 次 tick、163 次 `needsDisplay`、162 次 draw。没有出现“大量绘制被合成掉，所以只有提交没有呈现”。GPU 时长 p50 在 61–155µs，p99 最高约 1.0ms，不是这些间隔的来源。

## 根因

画面时钟是 `before` 副本 `LegacyPreviewAudio.swift` 第 384 行的 `Timer(timeInterval: 1/60, tolerance: 0.001)`。它加在主线程 RunLoop 上，不跟 `CADisplayLink` 对齐。tick 间隔 p95 约 16.7–17.6ms。`presentedTime` 再被吸到 120Hz 网格，普通静音就稳定地每两个显示周期呈现一帧。主屏四项描述都是 120Hz 时，这条路径的呈现上限大约是 60Hz。几何 p95 只有 84µs，解释不了 16.7ms 的间隔。

每个 tick 在主线程同步走完 `onElapsedSeconds` → `updatePlayhead` → 谱面 `setPlayback` / `rebuildGeometry` → `needsDisplay`，以及 BGA `apply`。普通静音整拍 p95 是 428µs。密谱可见音符约 1872–1888、顶点约 1.1 万，几何 p95 1.95ms（选择约 0.89ms，顶点装配约 1.10ms），整拍 p95 2.34ms。这仍小于 8.3ms，但会把 `needsDisplay` 推过垂直同步沿，于是 8.3ms 和 25ms 成对出现。密谱静音相对 60Hz 目标有 7.5% 的间隔超过 25ms。

BMS 每个 tick 都调用 `onPlayheadBeat(nil)`。稳态计数与 tick 相同。BMSON 场景则每个 tick 都交出实际拍，`playheadNil` 为 0、`playheadValue` 为 163，预览侧并没有因此变慢。完整应用里这个闭包接到 `ChartRenderer.setPreviewPlayheadBeat`（`before` 副本第 677 行）：传入 `nil` 也会 `rebuildGeometry()`。那次重建用 `DispatchQueue.main.async` 合并已经排上、尚未执行的请求。探针挂的是空闭包，编辑器毫秒数没有测到。定时器间隔约 16.7ms，预览本拍工作远小于这个间隔；只要编辑器重建同样短于间隔，上一次 async 会在下一次 tick 前跑完，合并不会跨拍生效。

音频打开在主线程。`AVAudioPlayer(contentsOf:)` 包在 `startPlayer` 里，由主线程上的定时器和 `asyncAfter` 调用。普通谱 7 个 WAV 命中：起播时第一次打开约 134ms，被 0.5 秒预热排除；之后 6 次的 p50 / p95 是 17.4 / 22.0ms。一次打开就长过一帧，tick 间隔 p99 升到 36ms，呈现 p99 33ms、最大 42ms。密谱 48 次打开（4 条车道、每八分音符同时开 4 个，共 6 拍）：稳态 40 次的 p50 / p95 / p99 是 11.0 / 21.7 / 53.3ms。tick 间隔 p95 / p99 / 最大是 54 / 106 / 115ms，呈现 p95 / p99 / 最大是 50 / 100 / 117ms。几何 p95 仍是 1.85ms，和密谱静音同一量级。密音频的长间隔来自同一拍上连续打开多个播放器，不是来自顶点。

图片 BGA 只调度了 2 次解码，解码在 `Task.detached`。主线程 `apply` p99 是 127µs、最大 310µs，tick 间隔 p99 仍约 17.6ms。呈现却有 33 个 8.3ms 和 26 个 25ms。视频只 seek 了 1 次（起播强制对齐；阈值 0.12 秒、最小间隔 0.35 秒），稳态 seek 计数是 0。每拍轮询播放器使整拍 p95 到 839µs，呈现 p95 25ms。这两场的主线程采样解释不了全部呈现抖动；解码完成回到主线程改 `CALayer`，以及窗口遮挡标志一直为真，都可能插在 tick 之间。没有把它们写成已经定量的主线程耗时。视频层是 `AVPlayerLayer`，不在这次 Metal `presentedTime` 里。

## 未验证

- 没有测量显示器扫描输出。
- 没有测量主编辑器 `ChartRenderer` 在真实主窗口里的重建耗时。
- 遮挡标志为真时，不能说明像素是否出现在面板上。
- 没有运行 uBMplay Windows 原版，不能比较绝对性能。
- 这是修复前的旧副本。S/W 改过渲染器之后需要重跑同一探针。

## 后测试点（2026-10-20，还不是对照）

后测探针在 `out/validation/ubmplay-parity-20261020/perf-after/`。`before/` 和 `perf/csv` 没有改。正式 after 表没有写进 `perf-after/summary`，因为还没有正的 `presentedTime`。细节在 `perf-after/UP2-early.md` 和 `perf-after/UP2-report.md`。

试点源冻结在 UA5 `returncode` 1、UW4 尚未返回之前。两边都不是 0，所以没有把试点二进制当成最终后测。二进制 SHA-256 `ac6dec31a903eb84fe5ea0711ef33ac7da02a649845b6ba0b57cdc61c2ebe260`。

产品窗客户区 1174×512，谱面 drawable 1324×1024，着色同样 1324×1024，像素 1,355,776。before 是 999×1324，像素 1,322,676。原版皮肤已挂上。窗口 `isVisible` 为真，遮挡不含 `.visible`。产品守卫因此停止提交：稳态提交 0，正 `presentedTime` 0。没有改遮挡标志去换帧率。

另一次孤立 `CVDisplayLink` 在 1.2 秒里提交 144 次，回调里的 `presentedTime` 仍全部 ≤0。这 144 次只是提交计数。同一次几何 p95 约 1.26 ms，GPU p95 约 0.147 ms，可见音符 720。drawable 可对到 999×1324，着色内容是 999×773。不能拿这组 GPU 时间和 before 的呈现 p50 16.667 ms 比快慢，也不能说超过 Windows 原版。

`onPlayheadBeat` 在这次产品冒烟里是 2 次。主编辑器重建仍未测。有声 tap、长 BGM、视频和 6 秒多轮还没跑。
