# 2026-09-21 全链路测试记录

本轮验收未通过。主应用在当前工具链下无法构建；核心存在整数溢出；独立 BmsONE 的 GPU Player 停止播放会崩溃，播放时间更新方式也会造成明显跳帧。

测试没有修改产品源码。构建、日志、音频时钟复现程序和测试谱面均在 `out/validation/full-chain-20260921/`。该目录已由仓库忽略规则排除。BmsONE 配置阶段会生成 `ja.qm`，测试后已恢复为测试前的文件。

## 环境和范围

- 主仓库提交：`e1cb5f70b26ec58907e9584a452f5ab2a0a0207d`。
- 测试当前工作区，保留原有 `.gitignore` 修改及 BmsONE 子工程中的未提交内容。
- macOS 26.6.1，Apple silicon，Apple Swift 6.4，CMake 4.3.3，Ninja 1.13.0。
- 主工程使用独立的全新 Debug、Release 和 ASan/UBSan 构建目录。
- 独立 BmsONE 使用当前 Homebrew Qt 6，Debug 构建，部署目标为 macOS 14.0。
- 本轮是功能与运行验证，不包含原版界面的逐像素对比、完整格式兼容认证或所有硬件的性能验收。

## 结果

| 检查 | 结果 | 说明 |
| --- | --- | --- |
| 主工程 Debug 配置 | 通过 | CMake 配置成功 |
| 主工程 Debug 完整构建 | 失败 | ApplicationState.swift:5 主线程隔离错误 |
| 主工程 Release 完整构建 | 失败 | 同一错误 |
| Debug CTest | 62/62 通过 | 失败后继续构建其余独立目标，再执行测试；耗时 27.43 秒 |
| Release CTest | 62/62 通过 | 同上；耗时 26.68 秒 |
| 核心 ASan/UBSan | 15/17 通过 | 两个测试触发同一处有符号整数溢出 |
| 原生编辑器布局查询基准 | 已执行 | 中位数 0.041833 ms，P95 0.061291 ms；不能代表 GPU Player 帧率 |
| 独立 BmsONE Debug 构建 | 通过，有警告 | 部分 Qt 库最低系统版本为 15.0，与目标 14.0 不一致 |
| 独立 BmsONE CTest 清单 | 0 个 | 没有注册自动化测试 |
| BmsONE 打开、编辑、撤销、重做、保存、重开 | 通过 | 中文标题、BPM、普通音符和长音时长核对成功 |
| BmsONE 音频资源加载 | 通过 | 界面识别 44.1 kHz、单声道、16 bit、1 秒 WAV |
| GPU Player 打开及绘制 | 通过基本启动检查 | 能画出车道和长音；不代表播放流畅 |
| GPU Player 停止播放 | 失败 | 两次操作均出现应用退出并重新进入空文档；系统生成崩溃报告 |
| 主应用 GUI 端到端流程 | 阻断 | 没有用旧版本应用替代当前构建 |

62 个 CTest 项是测试程序数量，不是断言或独立业务场景数量。其覆盖包括 BMS/BMSON 读写、节拍与长音、桥接层、文档会话、撤销重做、保存失败、剪贴板、音频解码、预览数据、切片、导出、MIDI、布局与本地化。独立测试程序通过，不保证这些功能在完整应用中已正确接通。

## 问题一：GPU Player 的绘制次数掩盖了位置停顿

用户现场指出，同一测试画面肉眼约每秒只移动五六次。界面先后显示过 84、119、104 FPS，不能据此认定画面流畅。

代码路径：

1. `BmsONE/src/player/PlayMixer.cpp:15` 以 `QIODevice::ReadOnly` 打开，保留 QIODevice 读取缓冲。
2. `readData()` 每次按整批读取量增加 `samplesPlayed_`，这是已经生成的样本数。
3. `GpuPlayerWidget.cpp:556` 每帧把该值直接交给播放时钟。
4. `PlayClock.h:96` 直接将样本数换算成时间，未在两次读取之间插值。
5. `GpuPlayerWidget.cpp:568` 附近只统计 render 调用次数。重复绘制相同位置也会增加 FPS。

独立复现程序使用相同的读取模式、bytesAvailable、44.1 kHz 双声道 PCM16 格式和 256 帧音频缓冲。计时器约每 8 ms 观察一次样本位置。

| 读取方式 | 观察次数 | 位置变化次数 | 典型读取量 | 结果 |
| --- | --- | --- | --- | --- |
| 原有缓冲方式 | 635 | 28 | 16,384 bytes | 约 5.1 秒内只有 28 次位置变化；相邻读取约隔 186 ms |
| 仅在复现程序中使用 Unbuffered | 657 | 452 | 1,024 bytes | 约 5.4 秒内位置变化明显增多 |

这是对音频读取与时钟更新机制的独立复现，不是修改后产品的实测 FPS。它与用户看到的每秒五六次移动吻合，强烈支持缓冲读取计数驱动画面时间是主要原因。关闭读取缓冲也不能单独证明音画同步正确：生成样本数仍不等于声卡实际播放位置，后续需要验证设备时间、输出延迟、暂停、恢复和跳转。

此外，`buildFrame()` 每帧遍历全部时间线和音符；手动判定也扫描整个谱面。这是大谱面的扩展性风险，但尚未证明它是本次两音符场景的主要瓶颈。

证据：`audio-clock-probe.cpp`、`audio-clock-probe.log`、`audio-clock-unbuffered.log`、`gpu-player-sample.txt`。

## 问题二：停止 GPU 播放器时崩溃

复现：打开 `gui/input.bmson` → GPU Player from Beginning → 播放 → Stop。已执行两次，均出现异常退出。

首次报告为 `BmsONE-2026-09-21-165612.ips`，异常是 `EXC_BAD_ACCESS / SIGSEGV`，访问地址 `0x3c`。触发线程为主线程，栈顶为 QtMultimedia 的 `QPlatformAudioEndpointBase::updateStreamIdle`，后续为音频 pull 回调。

`PlayOutput::Stop()` 会停止并立即删除 QAudioSink；播放器还涉及主线程上的 QIODevice 与音频线程中的输出对象。需进一步检查停止期间的回调与对象生命周期。现有堆栈不足以把根因唯一归到某行代码。

崩溃原始报告已复制到测试输出目录。第二次崩溃也保留了独立报告。

## 问题三：原生应用无法完成构建

`macos/Sources/IBMSNative/ApplicationState.swift:5` 初始化 `LegacyPreviewAudioPlayer()` 时，编译器报：

```text
main actor-isolated default value in a nonisolated context
```

Debug 和 Release 均复现。还存在修改 `decodeToWav` 的隔离警告。应统一该状态对象、播放器及调用方的 actor 隔离，不能只忽略诊断。完整应用未产生可验收的构建，因此主应用打开、交互、保存和内置播放链路尚未完成 GUI 验证。

证据：`build-debug.log`、`build-debug-keepgoing.log`、`build-release.log`、`build-release-keepgoing.log`。

## 问题四：极大小节长度触发有符号整数溢出

位置：`core/src/bms_document.cpp:362`。

```cpp
n = n * 10 + c - '0';
```

表达式先把字符编码加到 `n * 10`，再减去 `'0'`。即使前一行按十进制数字做了边界检查，中间加法仍会越界。输入 `9223372036854775807` 时，UBSan 报告 `9223372036854775800 + 55` 溢出。

触发测试：`ibms_bms_chart_fixture_tests` 和 `ibms_bms_timing_fixture_tests`。常规 Debug/Release 均通过，但 UBSan 中止，因此不能把常规测试通过当成没有未定义行为。

证据：`test-sanitized.log`、`overflow-reproduction.log`，后者含源码堆栈。

## 复跑

在仓库根目录运行：

```sh
cmake -S . -B out/validation/full-chain-20260921/debug -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build out/validation/full-chain-20260921/debug -j 4 -- -k 0
ctest --test-dir out/validation/full-chain-20260921/debug --output-on-failure --timeout 90

cmake -S . -B out/validation/full-chain-20260921/sanitized -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON -DIBMS_BUILD_MACOS_APP=OFF '-DCMAKE_CXX_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer' '-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address,undefined'
cmake --build out/validation/full-chain-20260921/sanitized -j 3
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir out/validation/full-chain-20260921/sanitized --output-on-failure --timeout 90

out/validation/full-chain-20260921/audio-clock-probe
out/validation/full-chain-20260921/audio-clock-probe unbuffered
```

主应用编译、播放器时钟、停止崩溃和数值溢出修复后，需要重新执行相关测试，并补完主应用 GUI 流程。目前不能宣称完整全链路测试通过，也没有宣称上述问题已修复。
