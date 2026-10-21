# 内置可视化预览：并行任务契约

用户目标：预览不能只有声音和按钮。原生应用应内置类似 uBMplay 的车道与下落音符显示，声音和画面使用同一播放时间，支持当前未保存的 BMS、BMSON，从头和从当前位置播放。

用户授权由子代理实现。最初指定 gpt-6-luna，五个任务均遇到 HTTP 503，重试仍失败，没有开始实现。随后用户指定改用 Cursor 的 Grok 4.7，允许 Fast 及按任务选择思考强度；实际模型名和参数必须以 Cursor 提供的列表为准，不得声称未验证的模式已生效。

父代理只负责契约、审查和集成验收，不直接编写产品实现。工作区原本有未提交改动，不得 reset/clean/覆盖。每个实现者只修改分配文件；遇到范围外依赖交给父代理，不跨范围修复。不要提交、推送或改模型/账号/网络设置。

## 统一接口（先实现，后续任务严格遵循）

### 用户追加要求（优先于下文原 AppKit 绘制方案）

必须用 Metal GPU 绘制谱面，支持 1P / 2P / Both 切换与 BGA。AppKit 只负责窗口和控件。任务 C 改为 MTKView + Metal 绘制；不允许静默回退成 CPU 绘制并宣称满足要求。BGA 由新增任务 F 负责，图片用 Core Animation GPU 合成，视频用 AVPlayerLayer，使用同一播放时间与缓存。

统一模型追加：`PreviewVisualLane` 最后添加 `var player: Int = 1`；新增 `enum PreviewPlayerSide: String, CaseIterable { case both, onePlayer, twoPlayer }`。任务 C 视图增加 `func setPlayerSide(_ side: PreviewPlayerSide)`，默认 both。

新增 `enum PreviewBGALayer: String, Equatable { case base, layer, poor }`、`struct PreviewBGAAsset: Equatable { var id: String; var fileName: String }`、`struct PreviewBGAEvent: Equatable { var beat: Double; var assetID: String; var layer: PreviewBGALayer }`。`PreviewChartSnapshot` 最后追加 `var bgaAssets: [PreviewBGAAsset] = []`、`var bgaEvents: [PreviewBGAEvent] = []`。A 负责写公共模型；B 负责从当前 BMS #BMP/04/07/06 与 BMSON headers/events 映射，poor 不在正常自动播放中盖住基础层。

F 提供 `@MainActor final class PreviewBGAView: NSView`，接口 `setChart(_ chart: PreviewChartSnapshot, chartDirectory: URL?, timing: PreviewAudioTiming, fromBeat: Double)`、`setPlayback(beat: Double, elapsedSeconds: Double, isPlaying: Bool)`。D 负责与 playfield 并排显示、同一时钟驱动、停止/关闭停止视频；F 不建立新的谱面时钟。

A 的自然结束需可通知控制器。提供 `var onTimelineFinished: (() -> Void)?`，时间轴终点发最终 elapsed 后调用一次，不砍音频尾音；D 将显示转为已结束、保留末拍（不能一直显示正在播放）。显式 stop 仍走 onPlaybackStopped。未完成旧计时回调和新一轮播放必须 generation 隔离。

各代理继续保持原文件范围。F 只新增 `macos/Sources/IBMSNative/PreviewBGAView.swift` 与可选测试文件，D 注册新源文件并链接 Metal、MetalKit、QuartzCore、AVFoundation。共享模型只能由 A 修改。BGA 资源解码/视频加载不得每帧发生；Metal 重用 pipeline、几何缓冲和 command queue，仅对可见音符生成顶点。验证需给出实际 Metal draw/离屏 GPU readback，不能只测布局计算后声称 GPU 渲染通过。

公共类型放在 `macos/Sources/IBMSNative/LegacyPreviewAudio.swift`，保持 Foundation-only，便于现有测试目标引用：

```swift
struct PreviewVisualLane: Equatable {
    var id: String
    var title: String
    var isScratch: Bool = false
}
struct PreviewVisualNote: Equatable {
    var laneID: String
    var startBeat: Double
    var endBeat: Double
}
struct PreviewChartSnapshot: Equatable {
    var title: String = ""
    var lanes: [PreviewVisualLane] = []
    var notes: [PreviewVisualNote] = []
    var barBeats: [Double] = []
    var endBeat: Double = 0
}
```

`PreviewAudioDocumentContext` 最后新增 `var visualChart: PreviewChartSnapshot = PreviewChartSnapshot()`。`playChart` 末尾增加默认参数 `visualEndBeat: Double? = nil`，保留旧调用兼容。

绘制接口：`@MainActor final class PreviewPlayfieldView: NSView`，提供 `setChart(_ chart: PreviewChartSnapshot)`、`setPlayback(beat: Double, elapsedSeconds: Double, isPlaying: Bool)`、`pixelsPerBeat: Double`。View 不自建播放时钟。

## A：公共模型与音频时间生命周期

建议较高思考强度。允许修改：`LegacyPreviewAudio.swift`、`macos/Tests/LegacyPreviewAudioTests.swift`。

1. 先添加公共类型和默认参数，通知父代理契约就绪。
2. 检查播放、stop、重复 play 和自然结束；用单调时间替换 Date 差值，elapsed 约 60Hz。
3. 画面和音符调度共用本次播放的时间起点。缺文件/空音轨也能按 visualEndBeat 推进画面。
4. 自然结束清理定时器，等待已经发声的采样尾音，不砍掉尾音。避免定时器强引用导致永久存活、旧回调在重播后污染新状态。
5. 保持单音预听、OGG/MP3 解码回退、BPM/STOP 时间行为。不要重写整个音频架构。
6. 新增有意义的时间/生命周期测试，报告命令及结果。不能只验证字节数或是否调用了同名函数。

## B：当前文档映射

建议较高思考强度。允许修改：`MainWindowController.swift`、`LegacyBmsonPreview.swift`、`macos/Tests/LegacyBmsonPreviewTests.swift`。

1. 在 previewAudioContext/bmsonPreviewContext 提供 visualChart，使用当前未保存内容，不通过保存临时文件驱动预览。
2. BMS 用 chart/long-note/measure 快照，正确去掉已配对长音端点的重复；只将可玩车道作为视觉音符，不把 BGM、BGA、BPM/STOP、hidden 当作可玩道。
3. 提供完整键道和 scratch 顺序，包括 1P/2P，查阅现有 ChartLayout 映射，禁止凭通道数字猜测。
4. BMSON 按 modeHint、x、y/l/resolution 和现有映射处理；x=0 不画键道，c=true 可以有视觉音符但不重触发音频。保留 BMS/BMSON 两套模型。
5. 提供标题、真实小节起点、endBeat。模式无法完整显示时明确报告范围，不静默丢掉音符并称全支持。
6. 可给 LegacyBmsonPreview.SoundNote 增 x/l 默认字段，context 增标题/模式/小节默认参数，旧调用保持兼容。
7. 测试短音、长音、续播、BGM、分辨率和模式映射，不改文档脏状态或核心桥接口。

## C：预览画面

建议中等思考强度。允许新建：`macos/Sources/IBMSNative/PreviewPlayfieldView.swift`，可选 `macos/Tests/PreviewPlayfieldTests.swift`。不改 CMake 和其他文件。

1. 使用统一接口实现 AppKit 绘制，深色车道、scratch/白键/蓝键颜色、固定判定线、音符向下移动、长音头尾和主体、小节线与节拍线。
2. View 只按传入 beat 绘制，不再建立独立定时器；不实现编辑或自造游玩判定系统。
3. 大谱面按 startBeat 排序并查找可见范围，跨视口长音要正确显示，避免每帧遍历所有历史音符。
4. 窗口缩放和双人模式不溢出；无谱面/无可玩音符有清晰空状态；滚速限制在合理范围。
5. 提供可访问性标题/状态/当前拍，便于真实窗口验证。不要把调试和实现说明放进用户界面。
6. 如做离屏绘制验证，产物放 `out/validation/visual-preview-20261020/`。离屏截图不等于真实窗口播放验收。

## D：窗口与构建集成

建议中等思考强度。允许修改：`PreviewWindowController.swift`、`macos/cmake/preview-audio.cmake`。

1. 将旧按钮说明窗替换成主区域 playfield + 工具栏，合理默认尺寸如 760×680、最小尺寸、From Start/Here/Stop、滚速和时间/BPM状态。
2. 现有外部方法与菜单 F5/F6/F7 保持可用。打开窗口就显示当前快照，播放时再次抓取未保存内容。
3. elapsed 通过 LegacyPreviewAudio.beat 统一转换，BMS/BMSON 都绘制。原有 BMSON delay ratio 只按既有含义应用，检查非有限值。
4. stop 和关闭窗口都停止声音并清理画面播放状态，关闭不能只 orderOut 后继续播放。没有文档时清空旧谱面。
5. CMake 注册 C 的新文件，必要测试只在对应文件准备好后加入。不得改 macos/CMakeLists.txt 或其他代理文件。
6. 等 A/B/C 就绪后在 `/tmp/ibms-visual-preview-20261020` 干净构建；错误交回负责代理，不跨范围改动。

## E：独立 Qt 播放器非零定位修复

建议较高思考强度。允许修改：`BmsONE/src/player/PlayMixer.cpp`、`PlayMixer.h`、`BmsONE/tests/play_mixer_replay_test.cpp`。

按 `docs/tasks/20261020-validation-handoff.md` 中 A/B 的约束处理已确认 BUG-01：事件绝对样本与定位后相对计数混用。先补非零定位测试再修复。generatedSamples 必须仍为本次定位后的输出帧数，不能简单改成绝对样本位置。保持互斥、跨起点声音、同帧事件、停止后缓存和自动播放语义。运行 BmsONE 全部 CTest，重编并运行独立 seek-probe，三个场景均应 PASS/退出 0。

## 顺序与最终验收

A 先发布类型契约；B/C/E 可并行；D 依据固定契约实现，最后等 A/B/C 完成再构建。每个代理交付实际文件列表、行为变化、测试命令/结果、未验证项。主代理独立审查完整差异，所有修复仍交原代理。

最终：主工程构建和 CTest；BmsONE CTest；独立定位探针；真实窗口检查 BMS/BMSON 短音长音、BPM变化/STOP、Here、停止重播、关闭停止、缺音频仍有画面。工具未获准控制应用时原样报告，给手动启动步骤，不绕过 UI 授权。截图只能证明画面，不能证明扬声器时刻或显示器真实帧率。
