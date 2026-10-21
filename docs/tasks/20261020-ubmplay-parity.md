# uBMplay 外观对照与真实播放帧节奏

用户反馈当前帧率低、卡顿，外观与 uBMplay 不像。用户最新明确：不要求照搬 uBMplay 的性能实现，要求看上去与原版差不多。先前约 25 微秒只量了局部几何生成，不能作为实际流畅证据。

最新追加：**用户要求直接使用压缩包里的皮肤图集，做到像素级还原，并要求性能超过原版。** 因此皮肤必须实际用于纹理，不再接受自行重画的近似样式。本机原生331×256背景的未覆盖区域必须与skin_00逐像素相等，nearest缩放无混色；音符/键盘/效果按原图集切片。原版Windows装饰不仿制。性能目标用实际presentedTime、p95/p99和丢帧占比验证，不能在没运行原版相同条件对照时声称“绝对超过原版”。

### 最新实现原则：原版作为参照，内部不照搬

用户随后明确：原逻辑在2026年已经过时，应寻找改进方法，切忌照搬。因此外观皮肤、布局、操作含义和谱面语义仍以原版为依据；线程、计时、缓存、音频调度、解码、资源管理和数据结构采用现代实现。原版阻塞/溢出/精度缺陷及偶然 bug 不默认列为必须复刻的合同。若改进影响可观察行为，记录原版证据、现代行为、理由和回归验证，让审计复核；不能用“改进”掩盖漏音、错误分支、错位或尚未实现。

例如音频可采用统一音频时间基、后台准备与长资源分块，不照抄VB主循环或逐音符同步读盘；渲染采用显示同步与Metal，不复制原版Sleep/VSYNC忙等。对原版不单调判定窗、同声音复用等可疑行为先作为研究记录，不在未明确影响前主动复制缺陷。性能声明仍必须来自现代实现实测与可比对照。

继续使用用户指定的 Cursor Grok 4.7 Fast。父代理研究来源、制定合同、审查并测试；产品实现交子代理。当前用户运行的旧 app 不可强退，不覆盖用户谱面，不提交/推送，不 reset 工作区已有修改。

## 已找到的原版依据

- 官方页：http://ucn.tokonats.net/software/ubmplay/
- 官方截图：http://ucn.tokonats.net/image/ubmplay_145.png （官方注明为 1.4.5，593×281，包括 Windows 装饰）
- 官方 1.5.2 压缩包：http://ucn.tokonats.net/archives/ubmplay/ubmplay_152.zip
- 本地完整原始包：`out/reference/ubmplay-1.5.2/ubmplay_152.zip`，SHA-256 `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada`。
- 已解压资源：`out/reference/ubmplay-1.5.2/ubmplay/image/`。
- 原始说明的 CP932→UTF-8 文本：`out/reference/ubmplay-1.5.2/readme-utf8.txt`。

皮肤由 AOiRO_Manbow 制作。原 readme 仅声明原封不动免费再分发整个包的条件，不是可任意提取素材另行发布的开放许可证。本次本机验证可从完整原版目录读取皮肤，**不要将 PNG 单独提交为本项目自有美术资源**，不要声称已取得重新授权。程序应支持读取本地完整皮肤目录；打包发布另行处理。本轮不发送联系作者的消息。

实际外观：`skin_00.png` 是 331×256 的完整双人背景，右侧 BGA 是 256×256，客户区约 587×256。1P 范围 x=0…156，中间量条 x=157…173，2P 范围 x=174…330。1P scratch 在左、2P scratch 在右。车道是纯黑/暖灰 (#393839)，不是蓝灰大格；判定线 y=219…223 为绿色渐变；底部立体按键/唱盘在 y≈224…255。背景全高都不可被随机宽高拉伸，应统一缩放或 letterbox。

原版 1P 车道边界 x: 0/33/52/68/87/103/122/138/157；2P 是对称反向，白键宽约18，黑键宽约15，scratch 宽约32。细灰边线。音符约4～5像素高的银/蓝/红细条，非当前14像素厚块。skin_01 是音符、按压和光束图集（137×221）；skin_02 是判定/数字字形（160×244）；skin_03 是爆炸动画（578×228）；font.png 是青色小点阵字体（258×35）。绿色/品红是图集分隔/色键，不能整张直接画到屏幕。

官方截图左侧顶部是小节/时间和标题叠字；右侧 BGA 上叠青色 `BMS Info` / BPM / Level / Rank / Notes 与 Option 文本；黄色 `GREAT` / 连击、键盘发光、击打爆炸是明显视觉特征。不要再默认两行现代按钮+巨高车道+任意大 BGA 各占一半。macOS 系统窗口装饰保持原生；播放客户区按上述原版比例对照。

## 并行边界与接口

### P：真实帧节奏诊断（只读产品）

只新增 `out/validation/ubmplay-parity-20261020/perf/` 下探针、源副本、CSV、报告，以及 `docs/validation/ubmplay-frame-diagnosis-20261020.md`。完整旧源备份在 `out/validation/ubmplay-parity-20261020/before/`，用它固定基线，避免并行改动影响对照。

使用真实 NSWindow / MTKView drawable。通过 **源副本** 给 CAMetalDrawable.addPresentedHandler 记录 presentedTime，并同时记录 tick/submit/CPU/GPU/长帧等。明确哪些是实际呈现回调，哪些只是 render 调用。不要用局部顶点耗时或自报 FPS 代替。普通谱、密谱、含音频/视频分别做有界对照；若无可呈现 drawable 明确报告，不制造静音离屏帧率。测试可编程创建窗口，但不能用其他 UI 自动化绕过 Computer Use 拒绝。不要操作/强退用户现有窗口。

检查明显路径：BMS 每 tick `onPlayheadBeat?(nil)` 也会走 ChartRenderer.setPreviewPlayheadBeat(nil)→rebuildGeometry；BMSON 每 tick 同样会重建主编辑区。60Hz Timer→needsDisplay 与 display refresh 不对齐、主线程音符解码都可能抖动，需要数据区分。

### A：音频时钟外部采样接口

只改 `LegacyPreviewAudio.swift`、`LegacyPreviewAudioTests.swift`。

给播放器添加 `func setPresentationClockExternallyDriven(_ enabled: Bool)` 和 `func advancePresentationClock()`。外部驱动启用后不再保留 60Hz Timer；由窗口显示器同步回调调用 advance，仍使用本次音频调度的同一单调 origin、end、generation，照常交出 onElapsedSeconds/自然结束。显式 stop/close/replay、空谱、尾音合同不变；外部驱动关闭且还在播放时恢复旧 Timer fallback。不要引入第二个独立播放时间轴。测试证明外部模式不重复 tick、停止和结束各一次、释放无泄漏。

可检查并报告采样触发时主线程文件/解码开销。不要在这轮擅自重写整个混音器或改公开时间单位。

### S：uBMplay 风格 Metal 谱面与皮肤

只改 `PreviewPlayfieldView.swift`、`PreviewPlayfieldTests.swift`，新增 `PreviewUbmStyle.swift`。不改公共模型、音频、窗口、CMake、BGA view。

`PreviewUbmStyle` 提供非隔离几何常量 `canvasSize = CGSize(width:587,height:256)`、`playfieldSize = CGSize(width:331,height:256)`、`bgaSize = CGSize(width:256,height:256)`，以及 `static func skinDirectory() -> URL?`：优先 `IBMS_UBM_SKIN_DIR` 指定的 image 目录，其次从本机完整原版目录读取（本轮仓库 out/reference 路径可通过编译时#filePath计算，避免把用户名硬编码）。默认不把原版图集单独放进 tracked 目录。缺原版图集时保留程序性外观降级并明确状态；本机验收必须使用找到的原版资源。

另提供 `@MainActor static func textImage(_ text: String, color: NSColor) -> CGImage?` 给 W 的右侧低频信息覆盖层。可将原版点阵字体一次解析后缓存 glyph，输出原生像素大小的文本图像；W 用 nearest 放大，不每帧重新栅格化相同文字。不能正确读出的字符用清晰的等宽 fallback，不把非 ASCII 标题悄悄吞掉。

用原版 skin_00 作背景纹理，skin_01/02/03/font 按实际图集识别小片上传一次，Metal 画音符/长音/键盘光束/击打爆炸/GREAT与combo（自动演奏视觉效果，不做虚假的人工判定）。用最近事件的拍/秒差驱动有限动画；不要每帧读磁盘/解码或扫描历史全谱。严格对齐331×256几何、绿色判定线、底部键盘和中量条，1P左scratch/2P右scratch。画面统一缩放、nearest 保留像素边缘。保留三重缓冲、可见索引、无Metal明确状态。现有几何/颜色测试必须按原版依据更新，不能仅改断言迎合错误。

保留原 setChart/setPlayback/setPlayerSide/pixelsPerBeat/readback API，额外提供 `func presentPlaybackFrame(beat:Double, elapsedSeconds:Double, isPlaying:Bool)`：按共享时间更新并直接提交一次 MTKView draw，避免只标 needsDisplay 被 AppKit 合帧。不能再起独立 Timer。W 将在显示同步回调使用它。普通 setPlayback 可保留非立即绘制供测试/空闲更新。提供 presentedTime/submit 的有界诊断计数接口或 P 可读副本，不把自报 FPS当最终验收。

### W：窗口布局和显示同步集成

只改 `PreviewWindowController.swift`、`PreviewWindowTests.swift`、`macos/cmake/preview-audio.cmake`，可新增 `PreviewUbmInfoView.swift`（右侧信息覆盖层）。

窗口播放主体固定 587:256 原版比例，默认2倍或其他整数倍放大，不默认1000×720任意拉伸；谱面331:256与BGA256:256并排，控件收成紧凑可显隐条或独立菜单，保留开始/Here/Stop、1P/2P/Both、滚速入口。右侧 BGA 上按原版青色像素风叠标题/时间/BPM/Notes/基本选项，不能遮整个BGA。不要展示不存在的功能状态。

用 macOS 14+ `NSView` / `NSScreen` 的 CADisplayLink 与显示器同步，帧率参考所在screen maximumFramesPerSecond；显示回调驱动 A.advancePresentationClock()，再通过 S.presentPlaybackFrame 真正提交。状态文字最多低频更新，BGA视频无需每屏幕帧做重复事务。停止、关窗、最小化/不可见时不空转，移屏重新选合适显示节奏。Swift6 actor正确；不能把后台display callback直接调用AppKit，不用sleep补帧。A未完成接口前可先实现自己的代码，最终等依赖就绪再编译。

修掉主编辑区更新：BMS播放不再每帧发重复nil导致整个编辑器重建；BMSON的编辑器游标不应牵制独立预览帧。可起播/停止清一次编辑器游标，播放中不转发整谱重建。保留原preview的正确关闭清理行为。

CMake注册新Style/Info文件，并加QuartzCore/MetalKit所需依赖；测试完整编译，不用存在性判断静默跳测试。不得把下载的官方exe运行起来，不要复制未获授权的原版PNG进tracked资源发布。完整原版目录在本机已存在，可直接读入。

## 验收

所有实现者实际运行测试，报告真实改动、来源、参数、未验证项；主代理独立diff/编译/测试。客户区截图对照官方1.4.5截图和1.5.2图集，说明版本差异；没有屏幕证据就不写像素级一致。P诊断与修复后至少对照p50/p95/p99帧间隔、>1.5×刷新周期比例、CPU与GPU时间、声音/主编辑器负载，不只报平均FPS。旧app不强退，输出新 `out/build/ubm-preview-release` 给用户试。
