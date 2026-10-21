# 当前预览修复任务与验收边界

## 最新状态（覆盖下文较早批次）

- UA7被父代理中断（130），不是通过：独立最小引擎证明同一immutable buffer排100/200完整，没有80段平台限制。UA8据此去除无依据上限/逐音复制，并完成4x准时排程，待审计。
- US8有效长音隐藏恢复、跨尾100/119/120ms及logic-only零geometry/GPU已由独立真实模型和Metal验证。W7隐藏实际路径也前进逻辑而不渲染。
- US9已完成cap/bomb覆盖顺序与内部通道顺序；独立27种实际effects7叠层case的底部1,334,592像素diff0，最终补搓盘测试后SHA已更新，审计收尾中。
- UG4视频1.05/2.0真实键盘倍率、去重/暂停/STOP/Off已独立通过。UG5已完成按原+44入口的视频最长边256和源矩形换算；真实AVPlayerLayer裁切几何自测通过，独立审计中，最终视频像素受锁屏限制。
- UW7已完成接线并自测通过，最终全源仍待UA8/US9/UG5稳定后的父代理Release/CTest。
- Here长音中段当前是声音carry+长音体可见、不重播head判定/holding bomb；单列策略边界，不当漏音P1。

产品实现全部使用Cursor Grok 4.7 High Fast；两位gpt-6.1-sol high独立审计，父代理拆解、读证据、运行验收，不写产品修复。原版提供外观与行为参照，过时后端限制不自动继承。

## A：真实音频排程（UA7）

独占：LegacyPreviewAudio.swift、LegacyPreviewAudioTests.swift。禁止改行为模型、窗口、其他渲染文件和审计探针。

1. 读UA6-pressure-control/trace及音频审计末节，复现4x下scheduled100但实际25–29ms静音缺口。
2. 对齐开场预排、共同host起点、Varispeed上游render cursor；不能把多个音挤到一个sample来避免“迟到”。
3. 正墙钟提前量换算到谱面秒，origin前的负elapsed不能削掉开场队列；rate变化与句柄临时耗尽仍须准时重试。
4. 保留后台IO、合计PCM预算、长BGM分块和有限容量；不降成2x掩盖缺陷。
5. 真实PCM验证file/inline 1x/2x/4x、混频标记、动态rate/暂停/192k/长BGM。计数器仅辅助，审计以固定源输出签审。

UA6已关闭：1x/2x短音漏音、192k默认半速与缓存污染、主线程fileopen、无声startPaused、合计内存预算。4x短音仍开P1，UA7进行中。

## S：命中与判定像素（US7）

独占：PreviewPlayfieldView.swift、PreviewUbmStyle.swift、PreviewPlayfieldTests.swift。

1. 保留US6时间索引（50k音符setTiming已由父代理实测约7ms，旧约492ms）。
2. LN尾结束持有状态；隐藏跨过新过期音符先清旧命中，不能恢复时闪一帧旧爆炸。
3. 普通自动命中使用已证skin03中排96×96，20ms一帧，120ms结束。
4. GREAT/数字按原整数除法定位；数字从i=1开始；双玩家分别判定/连击。
5. 原Float32正弦表驱动前90ms缩放与数字轻摆。只改视觉合同，不复制VB慢对象。
6. 对1x/2x/3x、各时间边界和两玩家做真实Metal读回及独立PNG oracle，再由审计复测。

US5已通过渲染双时钟所列用例；C2/C3/V4/V5/V6、普通爆炸与90ms动画由US7处理，不能说像素全通过。

## G：BGA媒体速率（UG3）

独占：PreviewBGAView.swift、PreviewBGATests.swift。

1. 保留UG2静态图裁切/负offset/BMP00/整stage/nearest与Off零IO。
2. 新增setPlaybackRate(Double)，存真实请求倍率，事件/模式切换和暂停恢复保留。
3. 所有AVPlayer按请求速率播放；异步seek/准备回调服从最新generation、暂停和rate，旧回调不得开声或复活旧视频。
4. 用实际currentTime与墙钟测1x/2x/0.5x/可用4x，不靠rate字段或反复seek模拟速率；视频音轨始终禁用。
5. 视频源矩形和旧movie.dll缩放尚未证实，明确列缺口，不凭猜测冒充复刻。

UG2实现和自己的测试通过，独立整stage审计进行中。报告实际在out/validation/ubmplay-parity-20261020/UG2-early/report.md。

## W：窗口媒体接线（UW6）

独占：PreviewWindowController.swift、PreviewWindowTests.swift。

1. 将engine真实requestedPlaybackRate在变速/首次绑定/ready转发给BGA，不每帧重复setter或setChart。
2. 保持谱面秒和暂停冻结墙钟分别送给S，BGA使用谱面秒。
3. 用实际host测试非0拍到线效果、暂停/Here/F2以及视频媒体进度。
4. 等各依赖稳定才编译，记录准确源SHA；父代理另做最终独立Release/CTest。

UW5固定源Release67/67通过，587舞台布局与BGA接线已完成；旧W4谱面/特效时钟问题待独立UW5真实host复验。视频1x不同步由UG3/UW6处理。

## 独立验收

性能审计：实际PCM、错时/漏音、IO线程、预算、长BGM、倍率；兼容审计：原PNG独立像素oracle、完整587布局、真实入口同分支Data、效果/媒体时间。

父代理已保存US6与UW5/G2源快照，避免在实现者改文件时混测。最终冻结A/S/G/W依赖后重新构建全部Release并运行CTest；67项自动测试通过不替代针对缺陷的独立探针。

当前CGSession明确锁屏。不得解锁或伪造窗口可见性。屏幕恢复可见后用CAMetalDrawable.presentedTime测p50/p95/p99、丢帧与CPU/GPU，同负载比较；无同条件Windows原版数据时不宣称绝对更快。


## 本轮有效测量

父代理固定源码Release重测单视图50k音符/1000BPM/1000STOP的setTiming：W4约492ms，US6约7.04ms；S7/S8新增尾时刻后实现者与独立审计约7.8–9.1ms。不是稳态帧率。

独立G4真实键盘媒体钟：1.05x长段1.050010、2x约2.00000、4x约3.99997、0.5x约0.49998；500次重复setter/tick无额外transport/open/seek。原G3吞0.05步长问题已关闭。

独立最小引擎（不链接产品）：同一不可变PCM预排100/200段再共同host启动，4x全部完整输出。此实验推翻A7的80段平台假设，当前A8已移除该限制及逐hit整buffer克隆，仍待独立真实播放器验收。


## 2026-10-21 独立完整构建

父代理在/tmp/ibms-ubm-parent-acceptance独立Release构建通过；固定音频5db2bd00、S9/G5/W7全套CTest **66/67**，音频暂停变速断言失败，不能沿用旧67/67作为当前源验收。日志parent-final-configure.log、parent-final-build.log、parent-final-ctest.log。S9/G5最新独立审计：33组1,631,168像素、静图42,076,160像素零差；48个AVPlayerLayer几何通过，最终视频合成像素仍未采到。

A8被父停止130，原因是架构证据：4x同频单node间隔47.5ms、双node55.7–58.9ms，共同play(at:host)不能建立同sample0，hostLead亦随Varispeed改变。拒绝继续用固定bias/host乘rate作为未经证明的同步方案。产品保留当前可编译但未验收状态，不回滚用户其他工作。

UA9P由Grok只在unified-audio-prototype目录实现单一输出采样轴proof，选择后台worker混音+固定SPSC ring+单AVAudioSourceNode，render callback由C/C++ thunk完成无IO/无锁等待/无分配复制，用实际callback sample/host推chartclock。先独立证明三轮多资源/多采样率1/2/4倍间隔、100/200短音、暂停/seek/rate切换与有界内存，再决定产品集成；原型通过不自动等于产品通过。


## 2026-10-21 01:20 验收更正与当前执行

暂停失败已由独立一轮probe证实为stale callback基线假阳性，产品pause返回后chart/wall均冻结。UAT只改testDynamicRateKeepsTheTone取样顺序，未改产品，保严格容差与暂停后两段等待；完整音频测试两轮0。父代理再次Release build与全CTest **67/67**，136.49秒，证据parent-uat-build.log/parent-uat-ctest.log。测试绿不关闭独立多nodeVarispeed时基偏移。

UA9P2单Source原型真实多格式/同频0.5/1/2/4三轮间隔最大误差0.025ms，自检81通过，独立device-format输出tap控制亦支持单源时序。独立扩展审计却确认两项P1：callback前异类命令覆盖丢pause/seek，以及循环MixClock日志plainpayload竞争（真实TSan）。UA9P3旧会话停滞后130，精简新会话UA9P3F继续，只写原型目录；完整desired-state与atomic live/history正在修。

UAR另只写resampler-proof目录，验证现有libsamplerate0.2.2/soxr0.1.3候选的带限变速、立体声、delay与32voice后台耗时。当前未集成产品，不把原型线性插值当生产音质。产品集成前还需callback读者退休、worker活动voice索引和多offset页缓存，见audit-performance/unified-product-integration-contract.md。


## 2026-10-21 现代音频方案审计结论

UA9P4完整desired-state与live/history原子发布经独立审计关闭前述P1及后续内存序P2；25组命令对和10万callback并发读者TSan控制通过。它仍为隔离原型：线性重采样、mono、全谱扫描与callback生命周期不满足产品合同，不能整体复制进产品。

UAR libsamplerate0.2.2 medium sinc通过所测通带/抗混叠、stereo、跨块、EOF控制；独立脉冲证明input_frames_used包含预读，绝不能作为已听到的chart位置。32路192k/4x、256输出帧独立p50约10.108ms、60样本p99/max约13.117ms，超过5.333ms预算。逐voice SRC方案不批准集成。

UAR2由Grok独占resampler-bus-proof目录验证一次后台native->48k stereo归一化、活动cue索引混音、单总线SRC。必须同时验证输出帧映射、动态rate/seek无漏音重播、多offset页缓存、64MB内存约束及steady p99；未通过不能以减少声部/线性插值/无界缓存替代。其结果和产品后端接入分开记录。产品集成仍依赖unified-product-integration-contract.md的生命周期、时钟、接口和完整回归门槛。


## 2026-10-21 新后端产品接入中（未通过）

UAR2F完成native分组proof，父冻结88975e24独立Release运行0，所测mono同asset32voice192k4x/256 p99约.349ms；独立四组合流与direct参考最大差0。UB0F ABI2完成reader ownership/strict stereo/oversize错误修复，父plainASanTSan均0，sol独立ASan定向控制通过。B1固定官方libsamplerate0.2.2源码静态构建，来源/许可证保留，父11hash复核。

A1产品适配已落盘但B2 Swift编译失败（Int32/模块导入等），且独立审计确认裸callback/query+inflight0回收、MainActor wait、mailbox无锁读、设备无条件unpause等P1门槛。父已反馈A1F，未运行不安全播放路径，当前新源码不算旧67/67。分页同资源多offset单window裸pointer、预算guard恒真与file稀有率归一化还需定向审查/修复。后续必须新冻结Release全套与实际PCM，不跳过失败、不以proof代替产品。


## A2构建修复与A3资源批次

A2由Grok完成Session/Worker类型修正，主程序与音频测试目标Release构建退出0，未改旧声音断言，未运行已知资源UAF的播放路径。证据audio-product-integration/A2-report.md。新后端仍未通过整体验收，不能沿用旧67/67。

A3已分配同文件多offset不可变页租约、绝对group轴到asset相对帧转换、非标准file采样率实际转换、真实预算与IO错误处理；资源修复未通过前不跑产品音频。W7接口审计另确认paused起播提前ready与运行期failed未完成stopped交接，见audit-performance/window-audio-integration-review.md，后续由音频owner修复，不改冻结W7。


## 最新父复跑

parent-ac-tests.log：100 次 offline reset 与真实 source/tap44100 正常退出 0；parent-ag-external-gen.log：重播代际回归 0；parent-at-build.log 构建 0。parent-at-full-audio.log 完整音频退出 1，首失败 overlap opens1/main0，已越过 140unique stole。未改该断言，需先确认共享页下测试合同，并用真实双 offset PCM 验收。新后端不算 67/67 通过。预算/rareFs/IO 失败交接与最终设备/可见性能仍开。
