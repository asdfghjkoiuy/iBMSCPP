# 2026-09-21 第二轮全链路复测

本轮仍未通过完整验收。上轮的原生应用编译失败和整数溢出已通过复测，GPU Player 停止播放也未再崩溃。但播放器时间仍可能倒退，并发现主应用不能正确读取 BmsONE 输出的 BMSON 音符。

本轮只新增测试报告及输出目录中的诊断程序，没有修改产品实现。用户这一轮的修改保持原样。BmsONE 构建时生成的 `ja.qm` 已恢复为本轮开始前的内容。

## 测试范围与结果

环境沿用第一轮：macOS 26.6.1、Apple silicon、Swift 6.4、CMake 4.3.3、Homebrew Qt 6。测试当前未提交的工作区内容。复用第一轮构建目录，重新编译所有受修改影响的目标，没有用旧可执行文件代替本轮构建。

| 项目 | 第二轮结果 |
| --- | --- |
| 原生主应用 Debug 完整构建 | 通过，仍有弃用和重复链接等警告 |
| 原生主应用 Release 完整构建 | 通过 |
| Debug CTest | 62/62，通过，13.69 秒 |
| Release CTest | 62/62，通过，10.98 秒 |
| 核心 ASan/UBSan | 17/17，通过，10.70 秒；启用 halt_on_error |
| BmsONE Debug 构建 | 通过；仍有 macOS 14 目标链接 macOS 15 Qt 库的警告 |
| BmsONE 新增 CTest | 2/2，通过；没有输出无音频设备的 SKIP |
| 音频输出停止测试重复执行 | 连续 10 次通过；每次含 3 轮启动/停止，共 30 轮 |
| GPU Player 实际窗口停止 | 两轮播放后停止均保持 IDLE，编辑器未退出 |
| GPU Player 暂停/恢复 | 本次从 14.798 秒暂停后恢复到 15.281 秒，没有重回开头 |
| GPU Player 播放中切换缓冲 | 失败，时间倒退，见问题一 |
| GPU Player 连续时钟采样 | 失败，正常运行阶段仍出现向后修正，见问题二 |
| 原生 BMS 打开、中文标题、撤销、重做、保存、重开 | 通过；重新打开显示「第二轮 BMS 保存」 |
| 原生 BMS 保存后的音符语义 | 通过；首行从 0100 约简为 01，音符仍在小节开头；另一音符位置不变 |
| 原生 BMS 内置预览启动/停止入口 | 未崩溃；未采集声卡输出，不宣称音频内容或延迟已验收 |
| 原生主应用打开 BmsONE 输出的 BMSON | 失败，模型中的声道及音符数为零，见问题三 |

62/62 是测试程序数量，不是完整业务场景或断言数量。BmsONE 的两组现有测试没有覆盖此次发现的全部设备重建和时间倒退情况。

## 问题一：播放时切换缓冲会退回开头

复现步骤：

1. 用新构建的 BmsONE 打开第一轮 `gui/input.bmson`。
2. 点击 GPU Player from Beginning。
3. 播放中把 BUF 从 256 改为 512。

界面证据：切换前显示 `00:10.859 / COMBO 2 / AUDIO 256f`，切换后显示 `00:00.551 / COMBO 2 / AUDIO 512f`。时间重回开头，但判定状态没有重置。

`GpuPlayerWindow.cpp:259` 的 `ChangeBuffer` 重建音频输出；设备时间从零开始，播放时钟却没有重新建立偏移。`PlayClock.h:78` 只在设备时间低于 20 ms 时防止回退，达到 20 ms 后仍会直接跳回新设备时间。

独立程序直接调用当前 `PlayClock.h`，复现结果：

```text
设备时间  5 ms：播放时间 5.005 s
设备时间 10 ms：播放时间 5.010 s
设备时间 15 ms：播放时间 5.015 s
设备时间 20 ms：播放时间 0.020 s，倒退 4.995 s
```

## 问题二：正常播放时钟仍不单调

增加了真实音频设备测试。它直接链接本轮构建的 `PlayOutput.cpp`，使用仓库测试中的静音 PlayMixer 替身，再通过实际 `clockTransport()` 驱动当前 PlayClock。约每 8 ms 记录一次时间，忽略最初 500 ms 后分析相邻位置。没有修改播放器源码，也没有用界面 FPS 代替时间位置采样。

| 采样 | 第一遍 | 第二遍 |
| --- | --- | --- |
| 总观察次数 | 735 | 739 |
| 运行时长 | 5.882 秒 | 5.914 秒 |
| 稳定阶段相邻位置数 | 672 | 676 |
| 相同位置次数 | 0 | 0 |
| 倒退次数 | 198 | 199 |
| 最大单次倒退 | 8.607 ms | 6.957 ms |
| 最终显示时间 | 2.932 秒 | 2.952 秒 |
| 最终设备处理时间 | 2.937 秒 | 2.955 秒 |

因此上轮每秒五六次的大幅停顿机制已改变，但仍有重复的反向修正，不能认定播放平滑性已通过。设备处理时间在本机探针中也明显落后于墙上时钟，需要继续区分音频供给、Qt 设备计时和显示时钟的问题；本轮不把该差异单独归因为 GPU 渲染速度。

`PlayClock.h:83` 在误差较小时直接采用设备目标时间；该目标可能落后于上一帧插值位置，从而倒退。较大误差分支也没有保持单调的约束。

限制：这是实际音频输出加静音混音替身的集成采样，不是完整播放器每帧日志，更不是显示器呈现帧率。完整窗口中观察到约 114～121 FPS，仍不足以证明流畅性。大谱面、全屏和真实音画同步未通过独立性能验收。

## 问题三：BmsONE 输出的音符未进入原生 BMSON 模型

输入为第一轮通过 BmsONE 界面保存的 `input.bmson`：1 个音频通道、2 个音符，其中一个长音。

- BmsONE 的 `Bmson100.cpp` 写入 `sound_channels` 和 `init_bpm`。
- 原生核心 `core/src/bmson.cpp:880` 只查询 `soundChannels`；BPM 在第 798 行只查询 `initBPM`。
- `sound_channels` 被当作额外字段保留，没有进入可编辑和可播放的声道模型。

独立调用当前 C++ 解析器的结果：

```text
BmsONE 实际输出：channels=0 notes=0 bpm=120
仓库 minimal-roundtrip 夹具：channels=1 notes=1 bpm=140
```

主应用窗口可以显示标题，但音频列表为空。修改标题再保存后，文件同时出现空的 `soundChannels` 和保留原始音符的 `sound_channels`。这不等于物理删除原始 JSON 中的音符，但主应用无法正确显示、编辑和预览这些音符。现有夹具采用的字段形式与 BmsONE 实际输出不同，因此常规测试没有发现互通问题。

本次输入 BPM 本来就是 120，不能靠界面显示 120 来证明 `init_bpm` 已被识别；此字段的遗漏依据为解析代码。

## 问题四：自然结束后时钟返回旧暂停位置

独立调用当前 PlayClock：从 2 秒开始，推进到 3 秒后调用 `finish()`，读取时间返回 2 秒。

`PlayClock.h:184` 只改变状态，没有保存结束时的当前位置，而 Finished 分支返回 `pausedMicros_`。该值仍是开始位置或上次暂停位置。

这项已在当前代码的独立程序中复现，尚未等待完整 GUI 谱面自然结束。不能把它写成已完成界面复现。

## 证据与复跑

第二轮输出位于 `out/validation/full-chain-round2-20260921/`：

- `build-debug.log`、`build-release.log`、`test-debug.log`、`test-release.log`。
- `build-bmsone.log`、`test-bmsone.log`、`stop-repeat.log`。
- `clock-edge-probe.cpp`、`clock-edge-probe.log`：缓冲重建和自然结束。
- `live-clock-probe.cpp`、两份 `live-clock*.csv` 与汇总 JSON：真实设备时钟采样。
- `bmson-interop-probe.cpp`、`bmson-interop.log`：跨工程格式读取。
- `gui/input.bms`、`gui/input.bmson`、`gui/tone.wav`：原生界面测试输出。

核心检查日志位于 `out/validation/full-chain-round2-sanitized-build.log` 和 `out/validation/full-chain-round2-sanitized-test.log`。

```sh
ctest --test-dir out/validation/full-chain-20260921/debug --output-on-failure --timeout 90
ctest --test-dir out/validation/full-chain-20260921/release --output-on-failure --timeout 90
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir out/validation/full-chain-20260921/sanitized --output-on-failure --timeout 90
ctest --test-dir out/validation/full-chain-20260921/bmsone-debug --output-on-failure --timeout 90
ctest --test-dir out/validation/full-chain-20260921/bmsone-debug -R bmsone_play_output_stop_tests --repeat until-fail:10 --output-on-failure
out/validation/full-chain-round2-20260921/clock-edge-probe
out/validation/full-chain-round2-20260921/live-clock-probe
out/validation/full-chain-round2-20260921/bmson-interop-probe out/validation/full-chain-20260921/gui/input.bmson tests/fixtures/bmson/minimal-roundtrip.bmson
```

本轮没有新增应用崩溃报告，退出后也没有遗留测试启动的 BmsONE 或 IBMSNative 进程。以上未通过项仍需修复和复测，本报告不宣称全工程已经验收通过。
