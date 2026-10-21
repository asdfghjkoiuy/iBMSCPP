# 内置 Metal 预览：2026-10-20

## 当前结果

原生预览已从声音和按钮窗口改为内置下落谱面窗口。BMS、BMSON 使用当前未保存内容，支持 1P / 2P / Both、短音、长音、BPM / STOP、从头/当前位置播放，以及 BGA 基础层、叠加层和本地视频。正常自动播放不显示 poor 层。窗口关闭会停止播放，自然结束保留末拍和最后视频帧。

所有产品实现由用户指定的 Cursor Grok 4.7 Fast 完成，父代理负责拆解、审查、提出修正及独立验证。早期 gpt-6-luna 请求全部 503，没有实现；Grok 中途也出现 unavailable，因此曾将未集成实现保存并恢复基线。用户要求继续后，连接检查成功，A3/B3/C3/D3/F3 恢复实现，C4/D4/F4 完成审查后的修正。旧中间代码仍在 `out/validation/visual-preview-20261020/unintegrated/`，不要再用它覆盖当前实现。

## 运行

Release 应用：

```sh
open /Users/guanhao/VSCodeAlgorithmTrain/CPP/ibmsc/iBMSCPP/out/build/metal-preview-release/macos/IBMSNative.app
```

在应用里打开 `out/validation/visual-preview-20261020/acceptance/double-play.bms` 或同目录 `double-play.bmson`，再用 Preview 菜单从头播放（通常是 F5；系统占用功能键时用菜单）。从当前位置通常是 F6，停止 F7。预览窗里可切 Both / 1P / 2P，并调节滚速。

样例目录包含 `pulse.wav`、背景红/蓝图、透明叠加图、poor 图和本地 H.264 视频。两份谱面都有双人音符、长音、BPM 变化与 STOP；正常播放时 poor 图不应盖住背景。不要覆盖用户自己的谱面。

重新构建：

```sh
cmake -S . -B out/build/metal-preview-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build out/build/metal-preview-release --target IBMSNative
```

## 验证结果

父代理独立执行：

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 干净 Debug 全部构建 | 通过 | `acceptance-configure.log` / `acceptance-build.log` |
| Debug CTest | 65/65 通过 | `acceptance-tests.log` |
| Release 应用及预览测试目标构建 | 通过 | `release-configure.log` / `release-build.log` |
| Release 预览相关 CTest | 5/5 通过 | `release-preview-tests.log` |
| Qt BmsONE 既有定位修复 | 独立 CTest 5/5 通过；探针 3/3 PASS | `independent-bmsone-tests.log` / `independent-seek-probe.log` |
| Computer Use 控制真实编辑器 | 阻塞 | 返回 `Computer Use was not approved to use IBMSNative` |

日志都在 `out/validation/visual-preview-20261020/`。构建仍有项目既有的弃用与重复链接等警告。

新增测试覆盖真实 Metal draw / 纹理读回、短音颜色、下落坐标、跨视口长音、双人筛选、缓冲重用、无 Metal 状态、BGA 图像与黑色透明叠加、资源回退、旧异步解码隔离、本地视频时间与静音、Here、STOP、停止/关闭/重播/自然结束，以及密集 BPM/STOP 的索引查询。窗口测试创建实际 NSWindow 并调用产品控制器，属于程序测试；没有通过电脑操作工具走人工编辑链路。

## 性能实现与测量范围

- 谱面使用 MTKView/Metal，着色器和 pipeline 每个预览会话编译一次，command queue 重用。三块顶点缓冲轮换；GPU 积压时实时路径跳过本帧，主线程不等信号量。离屏测试才等待 GPU 完成后读回。
- 音符在抓取快照时建立区间索引；小节线排序和各侧是否有音符也只预处理一次。每帧只提取可见范围。
- 10 万颗历史音符、40001 条小节线的测试中，可见音符 2、顶点 48；可见筛选平均约 17 微秒，顶点组装约 8 微秒，总计约 25 微秒（Debug 样本）。这不是整帧耗时或屏幕 FPS。
- 画面播放时间用主线程约 60Hz 的单调时钟，BPM/STOP 在起播时建立分段索引，实时二分查询，不再每帧重排或扫描整表。谱面和 BGA 共用同一次播放的拍和 elapsed。
- BGA 静态图异步解码并放入有上限的缓存，CALayer 合成；视频使用静音 AVPlayerLayer。事件不变时不重复查路径或解码，视频偏移只在绑定事件时积分一次，纠偏限频。400 次相同事件 tick 的路径解析和解码次数保持为 1；暂停不 seek、不重建播放器。

性能测量和细节见 `cursor-tasks/C4-report.md`、`D4-report.md`、`F4-report.md`。数字只是本机相应测试路径，不保证所有谱面、BGA 资源和音频密度下都相同。

## 图像与验收边界

`preview-window-content.png` 是测试创建的窗口内容合成图：真实控件截图，加上 Metal 纹理读回和静态 BGA 图层渲染。它不是屏幕录制，也不是通过电脑操作工具截取的最终显示画面。`playfield-*.png` 是真实 Metal 离屏纹理读回。

没有绕过 Computer Use 授权，也没有声称真实窗口手动流程、显示器呈现 FPS 或扬声器音画同步已经通过。视频测试检查 AVPlayer 时间、静音和暂停状态，未读取 AVPlayerLayer 的最终视频像素。

当前音频仍沿用 AVAudioPlayer 采样调度；本批没有将其替换成统一 PCM 混音设备时钟。大规模密集谱面、端到端音画延迟和真实视频呈现仍需实际运行验收。

GIF 目前显示首帧；不同视频容器的支持取决于系统解码器。超过 32MB 的叠加图跳过黑色透明处理。此版本提供类似 uBMplay 的基本内置预览能力，不是完整 uBMplay 兼容性验收。

## 实现和记录

任务契约在 `docs/tasks/20261020-visual-preview-delegation.md`。产品文件包括 `LegacyPreviewAudio.swift`、`LegacyBmsonPreview.swift`、`MainWindowController.swift`、`PreviewPlayfieldView.swift`、`PreviewBGAView.swift`、`PreviewWindowController.swift` 和 `macos/cmake/preview-audio.cmake`，以及对应测试。

Qt 非零定位修复单独在 `BmsONE/src/player/PlayMixer.cpp/.h` 及其 replay 测试，保留 generatedSamples 的相对计数合同。详细初始复现见 `docs/validation/gui-start-20261020.md`。

本地任务日志、原始备份、中间实现和样例都在被 Git 忽略的 `out/` 下；跨机器交接需要同时复制，不能只拷已跟踪文件。未提交或推送当前工作区。
