# 编辑器 / PLAY 时钟 / 长音效果独立审计（2026-10-21）

## 范围与证据边界

只读产品与测试源码；唯一允许写入文件为本报告。未打开前台 UI，未运行长测试或与实现并发构建。源码定位不等于完整窗口验收，隔离 helper 测试通过不能证明鼠标跟随、AX 文本绘制或真实屏幕呈现通过。

基线 HEAD：`e1cb5f70b26ec58907e9584a452f5ab2a0a0207d`。工作区已有大量修改，不以 HEAD 全部 diff 归因本轮实现。基线读取时 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `macos/Sources/IBMSNative/ChartRenderer.swift` | `b93dc3042dbdd103d0e31b2f629be2a9189903d2f0c3422104d48c911a32a463` |
| `macos/Sources/IBMSNative/PreviewWindowController.swift` | `4cb3a4cf0322b9710d6a97105f089ea1d5a069f2ff2a27dbd65260c02e5bdd24` |
| `macos/Sources/IBMSNative/PreviewUbmInfoView.swift` | `88719359493004d70c252ede6aeeb5397537096806e031700ce59c7e682750c5` |

## 已确认的基线根因

1. **普通拖动没有实时移动预览。** `ChartRenderer.mouseDragged`（基线 2201）只有 pending Ctrl toggle 时调用 `updateCtrlCopyPreview`。普通源的 `selectMovePlan` 到 `mouseUp`（2330）才计算和提交。Metal 几何仅绘制 `ctrlCopyPreview`（3366），没有普通 move preview，因此 BMS/BMSON 都可出现按住鼠标时原音符不跟随、松手后才跳转。
2. **BMS 空白矩形框选被 BMSON 条件阻断。** `beginBmsonRubberBand`（1855）首个 guard 要求 `appliesBmsonSnap`，BMS 的默认值为 false；`updateBmsonCursor` 也在更新 rubber band 前先 guard 同一条件。选择工具的空白鼠标按下虽然调用此方法，但 BMS 无法建立 band。
3. **数字 2 移轨链路已存在，不能用键码 helper 排除问题。** `ChartRenderer.keyDown`→`MainWindowContentView.moveSelectedNotes`→`actions.moveSelectedToColumn`→`DocumentSession.moveNotes`。现有 LegacyMoveNotes 的映射为 digit 1→scratch 16、digit 2→11、digit 3→12；数字 2 是含 scratch 在内的视觉第二列，并非 BMS 通道 12。框选失败将直接导致这一链路没有集合可移动。需要在真实多选之后证明整个集合交给 action，且 snapshot 更新后仍保留所有被移动项。审计首次消息误称数字 2→12，已向父代理明确纠正。
4. **PLAY 百分秒被 250 ms 节流限制。** `writeClock(.display)`→`content.syncInfo(... throttle: true)`；`syncInfo`（2170）在距离上次更新不足 0.25 秒时直接丢弃文本。`formatClock` 提供两位小数，但可见文本最多约 4 Hz，无法满足实时百分秒要求。`PreviewUbmInfoView.setText` 仅在全文变化时重新生成点阵图；该层没有另一个固定文本闸门。
5. **旧测试固化低刷新预期。** `PreviewWindowTests.testDisplayStepPresentsWithoutRebuildingTheEditor`（约 487–500）在快速 30 次 display step 后要求 raster 增量最多 2。这些 step 没有推进输入 clock，不能证明动态时钟刷新；新实现需要以变化的统一 clock 检查文本，同时检查静态内容不重复布局或栅格。

目前没有源码证据证明“完全静止”的第二个根因：`performDisplayStep`→`player.advancePresentationClock`→`tickElapsed`→`onElapsedSeconds`→`updatePlayhead`→`writeClock` 可连通。是否出现实际输出时钟未推进、窗口显示回调未触发等情形，仍需真实播放测量，不能把移除 4 Hz 节流等同于解释所有停滞。

## 长音效果补充审计

用户所指是播放器判定线上的持续按住/发光，范围是 head→hold→tail。首次读取时 `PreviewPlayfieldView` 已有 long latch / tail birth 逻辑，可能包含并行 LNE 的未完成修改，不能将其算作原始基线。可观察的待审点：keycap 绘制约 2397 仍仅检查 `beamVisible(ageMilliseconds: hit.ageMilliseconds)`，没有把长音仍在 hold 当成可见条件；因此长条开始超过短 beam 窗口后可能抬起键帽，即使 bomb latch 仍存在。需在最终实现完成后重新定位、检查二者的效果开关。

## 必须满足的验收点

| 路径 | 应观察的行为 | 所需证据 |
| --- | --- | --- |
| BMS / BMSON 普通短音拖动 | 按住时每次鼠标 drag 立即更新预览，松手提交与最后预览相同；原始文档按提交契约修改 | 实际事件链测试 + 窗口录制或多帧证据 |
| 单个/多个短音、长音 body/端点 | 锚点、吸附、禁纵移、长度、相对轨道夹紧与提交一致；Ctrl copy 不回归 | 实际 ChartRenderer 事件路径 |
| BMS 空白矩形拖选 | 当前选择工具可见框，范围中的多个 kick 全选，不需要切时间选择工具 | 真实选择集合与屏幕高亮 |
| 框多个 kick 后按数字 2 | 所有选中 kick 到 2 轨，拍位置和 token 不变，未选中项不移动，单次撤销恢复 | 事件→selection→action→DocumentSession→snapshot 全链路 |
| PLAY 百分秒 | 变化 clock 输入在每帧/百分秒变化时反映到可见文本，无独立墙钟漂移 | 动态 clock 输入 + 实际 InfoView 呈现 |
| pause / seek / rate / replay | pause 停住，seek 即时采用新原点，倍速取统一 clock，重播清旧 epoch | 状态与可见文本同时检查 |
| 1/2 下落速度、3/4 播放倍速 | 有限明确档位，长按夹紧且不无界累增，显示当前值 | 最小/最大/长按/回放与显示证据 |
| 长音 head→hold→tail | head 到判定线后键帽与发光持续到 tail；tail 后按合同释放与短尾效果，不残留 | 长度显著超过短 beam 的真实长音、pause/seek/rate/遮挡恢复 |

## 最终 diff 审查

待父代理通知实现完成后补充。当前仅为基线与验收清单，未宣称任何 UI 项通过。

本轮实现以 `out/validation/editor-wmv-clock-20261021/parent-baseline/` 对比，其 hashes.json 与上列三文件基线一致。没有用 git HEAD 巨量既有 diff 归因本轮变更。

### CLK 首轮审查

- 移除了 250 ms 节流；相同文本仍提前返回，大小不变不触发舞台布局。新增 `syncInfo` 位于 `.logic`（隐藏/遮挡）分支；`.display` 在实现前快照中已有 syncInfo，不能误写成此次修复了 `.display` 遗漏。
- `infoOriginSeconds` 在 bindClock 用 fromBeat 积分一次；播放器 emitOrigin 回传 0、currentElapsed 返回 session 相对 chart，因此未发现重复加起点。STOP 采用终点 STOP 不计、起点 STOP 计入后续拍的既有到达时间定义。pause 不重 bind，seek/replay 重 bind，旧 epoch 仍有防护。
- `PreviewUbmStyle.textImage` 的 glyphMasks 首次加载 font.png 后缓存为 storedGlyphMasks，不会每帧读图；每个变化百分秒仍遍历全文并分配像素和 CGImage，最长 240 scalar，48 项 text cache 周期清空。是否有明显性能影响需要测量，源码不足以断言掉帧。
- 首版 layer.contents + draw/displayIfNeeded 双发布已经撤回；当前 InfoView 保留 wantsLayer=false，设置 needsDisplay、通知父视图脏区域并 displayIfNeeded。`previewInfoPresentedImage` 实际返回 cachedImage，命名不能作为物理呈现证据。离屏 bitmap 与缓存变化只证明绘制内容，不证明锁屏、遮挡或真实窗口 presented FPS。

### EDR 发现（已报父代理，待修）

**P2：提交失败后可能残留 ghost 几何。** 当前 mouseUp 的 defer 只 cancelDrag；cancelDrag 清 movePreview / endpointPreview 却不调用 rebuildGeometry。若最后一次拖动已经完成 Metal 呈现，然后 moveBatch 回调 false、snapshot 不可编辑、无效落点等路径提前返回，状态虽然清空，Metal 仍可能保留上一次隐藏原件的 ghost，直到下次几何重建。需要在真实 drag 呈现之后拒绝提交，并验证原音位置恢复、ghost 消失；同步调用 helper 重建后再断言会掩盖此缺陷。

另 endpointPreviewNote 未限制 start < end，而核心长音编辑明确拒绝 end <= start；跨过另一端可出现无法提交的预览。需明确失败后恢复，或让合法性与实际提交保持一致。

EDR 首轮 probe 报告 PASS metal=true，覆盖实际 ChartSurfaceView 合成事件、Metal 与 AppKit 回退呈现列表、框选描边位图、滚轮与多选、Ctrl copy、端点等。它没有打开真实 DocumentSession，数字 2 只记录 moveDigitRequested，并通过 LegacyMoveNotes 核对目标 11；撤销与实际文档完整移动没有实测。不能把 surface 回调绿写成文档移动/单次 undo 全链通过。父代理已安排 EDRF 修复失败提交清理并补 probe，最终状态待其完成。

**EDRF 最终复核：上述 ghost 与跨尾缺陷已关闭。** `ChartRenderer.swift` SHA-256 `f0c2344fdb7abbdbdb6a87c40a1129663a3a6f2c7ab29efd3beeeff3ddb684f4`。cancelDrag 按 dragPaintNeedsRestore 统一安排几何恢复；普通 move、Ctrl copy、endpoint 建立预览时设置标记；非法预览清理时自身安排重建。endpointBeats 共用预览和提交计算，end-start<=1e-6 时既不画倒置 ghost，也不提交。Probe 覆盖 callback=false、已呈现合法 ghost 后直接沟槽 mouseUp、Escape 后立即 mouseUp；松手后只排空主队列，没有调用 synchronizePresentation 帮产品补重建，因此可检验原缺口。父代理独立最新探针 PASS metal=true。

SessionTests 新增 `testDigitTwoColumnMoveIsOneUndo`，真实 DocumentSession/C++ bridge 及 undo/redo 均运行；父代理独立执行退出 0。边界是两颗 11 已在目标，只实际移动一颗 12→11，因此此项证明真实单个变更的 undo/redo，未直接证明多颗实际改变合并为单步。源码 moveNotes 的 withCompound 覆盖整批，控制器 3581 取 content.selectedChartItems 再调用 session.moveNotes 的连接存在，但 surface→MainWindowController→Session 尚没有同一测试贯通。不能据此宣称真实窗口框选→数字2→一笔撤销全链通过。

### LNE 首轮审查

`laneGlowVisible` 已让 long + tailAge=nil + age>=0 的持续 hold 保持可见，车道光束与 keycap 两条绘制链都接入该判定；短音仍用原 50 ms。新增测试包含 Metal readback 的 head、50 ms、500 ms hold、pause、双人轨道及 tail 等内容，因此比单纯 helper 绿更有力度；运行结果仍由实施代理提供并待父集成核实。真实窗口持续效果不因此宣称通过。

最终 LNE 只读审查未发现新增产品缺陷。已读测试包括 tail 0/100/120 ms、40 ms 短长音、效果位 0/2/4、pause/resume、1P/2P、seek 到 hold 中段及 seek 回头、换谱清理、0.5×/2× 墙钟年龄，实际从 Metal 读回图集纹素。实施代理报告两次 PreviewPlayfieldTests 退出 0；审计者未重复运行。对应 SHA-256：Playfield `ca1649b9c2d4030b7b8fb1e2ce212361d5c78519c99d14d942f435a12a7e0e8c`，Style `ec64d3a762475e40317d305f19761ae954fd5e51370e0d6b1e7dfdb83f73b283`，Tests `94c51313e495ddd45e09927bef45252c0b0e2e03b421f52d2f83055874edc942`。

证据归因纠正：用户确认了 hold/glow 问题，没有提供原版运行画面对照。LNE early/report 与 Style 注释中“按用户对照原版播放器的可观察行为”等措辞需要改成当前修复目标；静态反汇编未证明 hold 持续重写光束时钟。不能把本轮目标行为或测试实现当成已实测的原版事实。

速度合同追加：读取时 Window 的 `hiSpeedBasePixelsPerBeat = 48`，Window/Playfield 下限均为 16、上限 240；0.25 档算出 12 后实际夹为 16。Behavior 的 HiSpeed 没有上限，超过 5 后实际滚速都夹为 240，而选项仍可能显示任意更大的 HiSpeed。`effectiveOptionLines` 只比较已经夹紧的 `clampedScroll`，无法发现显示值与实际档位不一致。若最终采用 base 60 与 0.25…4.0，Window 与 Playfield floor 需统一为 15；若保留 base 48，floor 需相应统一或调整有限档位。1/2/3/4 单 keyDown 单档，hold 和系统 repeat 不继续变化，边界 clamp，当前值必须可见。

### SPD 最终审查及可交付结论

最终采用保留 base48 的方案：HiSpeed 19 档 `0.50…5.00`、每档 0.25，对应实际 `24…240px/beat`；Rate 16 档 `0.25x…4.00x`、每档 0.25x。两者均在现有实际上下限内，HS 不再显示被夹紧前的虚假档位。速度命令退出 usesHoldRepeat，apply(.keyDown) 的 alreadyHeld 防止重复按下；系统 repeat 与 pollHeldKeys 对速度不再步进，释放再按才变一档。现有定位键保留其重复行为。

像素 setter 量化到最近 HS 档，控制条/菜单/默认 Play 行分别显示当前应用的 HS 与引擎 requestedPlaybackRate。菜单预建、只更新标题与勾选，不在每帧重建。CLK 的起点一次积分、相对统一 elapsed、去 250 ms 节流、隐藏 .logic 更新、无层 InfoView 立即 draw 均保留，未发现回归。

已读取最终 BehaviorTests 与 WindowTests 日志，末行分别为 `PreviewUbmBehaviorTests passed` / `PreviewWindowTests passed`；父代理/实施代理执行，审计者没有并发重跑。WindowTests 包括实际合成按键/按钮/菜单、repeat、两端档位、16px setter→0.50/24px、pause 时变速与信息框布局。SPD 报告保留此前 2×、0.5× 到达采样窗口的两次间歇失败，之后完整一次通过；此证据不足以断言时间相关测试完全无波动。

最终产品 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| ChartRenderer.swift | `f0c2344fdb7abbdbdb6a87c40a1129663a3a6f2c7ab29efd3beeeff3ddb684f4` |
| PreviewUbmBehavior.swift | `263c1180a1f240825f6c8afa2016a8bfc2c85630fb225937e0c0f9a16fe0282c` |
| PreviewWindowController.swift | `daa6d5a48eef965eef6cde65417251e706416a7bb775190eb103074e1fcee7b4` |
| PreviewUbmInfoView.swift | `456472649ecb4c290a50288937f4a934fa9ad08e5f747b20f414fa4e9d8ded1a` |
| PreviewPlayfieldView.swift | `ca1649b9c2d4030b7b8fb1e2ce212361d5c78519c99d14d942f435a12a7e0e8c` |
| PreviewUbmStyle.swift | `ec64d3a762475e40317d305f19761ae954fd5e51370e0d6b1e7dfdb83f73b283` |

当前结论：已确认普通拖动预览/BMS 框选/PLAY 低刷新/长音 hold 光束与键帽/速度无界重复等源码缺口有对应实现，EDRF 的失败收尾与跨尾缺陷也已关闭。最终产品源码审查未发现新的阻塞缺陷。证据覆盖源码、合成事件、离屏绘制/Metal 像素与独立 Session 部分行为，**没有验证用户屏幕上的实时跟鼠标、真实可见 PLAY FPS、完整主窗口框选→数字2→实际多音移轨→单次撤销**。离屏/缓存图像不能证明锁屏时实际 presented FPS，也不能替代原版运行画面对照。EDS 正增强多颗实际变更 undo 测试，最终测试哈希/结果需父代理另补。

**后续父代理独立复测失败，以上“未发现新的阻塞缺陷”暂缓作为最终接受结论。** `/tmp/ibms-speed-detents-fix/macos/IBMSNativePreviewWindowTests` 退出 1：`UW7 occlusion=8194 suppressed=true / FAIL hidden logic pushed BGA`。当前 Content.layout 没有直接 syncBGA；bgaPlaybackUpdates 仅 syncBGA/holdBGA 递增。更直接的源码候选是 suspendPicture 不幂等：每次隐藏/遮挡通知都在 display.isPlaying 时再次 holdBGA，隐藏期间第二次通知即改变计数。syncInfo 的立即 display/layout 可能触发通知，但尚无调用轨迹证明因果，不能写成 layout 直接更新 BGA。父代理已安排 SPDF 定位并修复；必须保留失败事实，不以重跑偶然绿覆盖。隐藏 .logic 每 tick 更新 Info 还可能违反不绘制合同，需一并检查。

### SPDF / EDS 最终复核

上述隐藏失败已由 SPDF 按调用路径修复并补针对性测试。失败来源是重复遮挡通知再次 suspendPicture→holdBGA；最终 suspendPicture 已隐藏时幂等，隐藏 `.logic` 只 rememberText 缓存、不标脏、不 display、不 layout，准备完成且隐藏时不再 syncBGA，恢复后一次采样并呈现最新缓存。新增测试跨分钟及小时位数变化，检查隐藏 BGA、视频布局、几何与绘制计数不变，重复两次遮挡也不推 BGA；恢复后只加一次。最终日志仍出现 `UW7 occlusion=8194 suppressed=true`，但末行为 `PreviewWindowTests passed`、`EXIT:0`。源码复核未发现该修复新增阻塞缺陷。

SPDF 最终 SHA-256（替代上表 SPD 时点两项）：Window `350cf4df7bac6be4e202da4ead1b655439106e9c83c7b6f5488bbe58d36eb280`；Info `e9b63af4e450ee8ffe0a61dc05fb3de797c4c62377f6b4cef565d457d3053b3d`。SPDF 测试目录复用了已有 FFmpeg 静态库；当时新脚本的解码器检查失败。因此该结果证明该复用构建树的窗口测试，不证明全新依赖重建。touch 时间戳不构成内容一致性证据；父代理后续默认 Release 重配重编应另记整合结果。

EDS 现已增强真实 Session 测试：三颗源在 12/13 轨的音全部实际搬至目标 11，拍、分数与 token 不变，一次 undo 全回原轨，一次 redo 全回目标。SessionTests 退出 0，测试源码 SHA-256 `5ce99508da0707b8029e29e13a99204b7eabdd73546f3b2fd3af373e4bb16b13`。这关闭了首版只有一颗实际改变的覆盖不足；仍未把 surface 框选→MainWindowController→Session 接成同一个真实窗口测试。

最终审计结论：已报告的 ghost 失败清理、跨尾端点、隐藏重复 BGA 更新均有对应修复和针对性覆盖；产品源码复核未发现新的阻塞缺陷。保留真实用户屏幕呈现、完整主窗口事件贯通以及父默认 Release 全依赖重建的验证边界。先前失败事实保留，不由后续成功覆盖。
