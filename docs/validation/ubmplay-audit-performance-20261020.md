# uBMplay 预览独立性能审计（2026-10-20，早期快照）

审计范围：音频主线程路径、外部时钟生命周期、窗口呈现/节流、Metal 缓冲与 UP 性能统计。只读产品；仅在本报告及 `out/validation/ubmplay-parity-20261020/audit-performance/` 保存源副本、探针和结果。未操作用户窗口、未提交或重置工作区。

**本报告尚不是最终验收。** HEAD 为 `e1cb5f70b26ec58907e9584a452f5ab2a0a0207d`，工作区有大量未提交变更；UA2、US、UW 仍在写。下面行号对应早期文件，后续须按源内容及 hash 复核，不把半写状态的缺接口/编译失败当缺陷。

最初源 hash 见 `audit-performance/source-hashes-early.json`。音频探针副本只额外给 `startPlayer` 添加起止时刻记录，真实音频逻辑未改。窗口/BGA 完整副本保存于同目录，SHA-256 分别为 `d4e324111e87d416af37ef8a0447d954a5b06882fd51c17da5f9d0f174110b80`、`31d9cf1c01d4c8d58fc4668a4771c2820db470d6ccd4ea7267a717fad00528a0`。

## 已确认问题

### P1：音符触发仍在主线程读取/打开/准备声音，实测阻塞足以吞掉多帧

位置：`LegacyPreviewAudio.swift:563–576`、`665–699`（UA2 开始修改前的副本）。未来每个 hit 排入 `DispatchQueue.main.asyncAfter`，直接调用 `startPlayer`；当场执行路径查找、文件存在性检查、`AVAudioPlayer(contentsOf:)` / `prepareToPlay()` / `play()`，失败时同线程调用 `decodeToWav`。并发音符也逐个走此路径，没有已准备声音的复用。

触发：普通本地短 WAV、密集音符/和弦；真实 OGG fallback 还会在此线程解码，但本审计没有测 OGG。影响：AppKit、显示同步采样及音符触发共用主线程，帧率 Timer 换 CADisplayLink 并不能消除这个阻塞，晚来的和弦音符还会依次偏迟。

独立证据：`AudioAuditMain.swift` + UA 音频源副本，用 `swiftc -O -swift-version 6 -target arm64-apple-macosx14.0 -framework Foundation -framework AVFoundation` 编译并运行。一次 0.05 秒 PCM click WAV，16 个 100 ms 间隔启动后，在 1.7 秒触发 12 音和弦。`audio-main-thread.json`：冷启动 189.254 ms；后续单音 7.319–34.459 ms；同 RunLoop 120 Hz 心跳间隔 p95 17.086 ms、p99 43.037 ms、max 151.798 ms，15 段超过 12.5 ms。全部 `startPlayer` 记录为主线程。此处是音频局部探针/主线程心跳，**不是 presentedTime 或 FPS**；单轮、系统热状态和并行负载会影响绝对数值，不能泛化为每个 WAV 固定耗时。首次同步阻塞发生在首个心跳之前，另以 `syncStartupSeconds=189.919 ms` 记录。

旁证：UP 原基线 dense-audio 的真实 presentedTime p95/p99 为 50.000/100.001 ms，dense-silent 为 25.000/25.004 ms；二者有下述遮挡与编辑器负载限制。

最小修复范围：保持 UA 外部时钟 API、generation、停止、空谱与尾音合同；起播前在后台解析路径/解码并准备可复用 PCM，以同一未来音频 origin 调度，拍点热路径不读盘/解码。polyphony 必须用独立 voice 或支持重叠的音频节点，不能用每资源单个 `AVAudioPlayer` 重置 `currentTime` 截断重叠。停止/重播取消准备代，缓存需内存预算和释放，Swift6/委托隔离需明确。不要仅把现有 `startPlayer` 随手移到后台。主代理已将有界 UA2 修复交给 Grok，待复查。

### P2：最小化/不可见拆掉显示链后，没有可继续收尾的时钟

位置：`PreviewWindowController.swift:612–614`、`634–640`、`960–962`；对照 `LegacyPreviewAudio.swift:470–487`、`606–625`。

触发：显示链外部驱动播放期间，最小化或收到不可见遮挡通知。窗口只 `displaySync.detach()`，保留 `externalClockWanted=true` 和播放器外部模式；UA 的 Timer 已停，自然结束只能通过 `advancePresentationClock`/`tickElapsed` 检查。

影响：隐藏期间终点已经过了仍不触发自然结束，`display.isPlaying` 保持 true，直到恢复可见后才收尾。BGA 没收到 `isPlaying=false` 或独立 hold 请求，已有 AVPlayer 继续运行。后者由源码状态路径确认，尚未以真实视频资源计量其后台 CPU/GPU。

独立证据：`ExternalClockAuditMain.swift` 使用同一音频快照，无 UI。模拟窗口的“打开外部驱动、播放、无后续 display advance”序列：0.1 秒空音频视觉谱，泵 RunLoop 0.25 秒后 `finished=0` 且仅收到 elapsed=0；下一次 advance 才交出 0.1 秒并 `finished=1`。结果 `external-clock-detached.json`。这验证播放器没有隐藏期间的终点路径，不声称已测 OS 遮挡行为。

最小修复范围：由 UW 明确定义隐藏策略。隐藏时停止渲染和 BGA，并保留轻量终点/音频时间轴收尾；如改回 Timer fallback，隐藏回调必须避免它继续生成完整几何/BGA/UI。恢复可见用原 origin 采样，禁止重启歌曲。加入“隐藏跨终点只结束一次、恢复不重播、隐藏无 render tick”的测试。

### P2：BGA 统一 30 Hz 节流会跳过快速图片事件

位置：`PreviewWindowController.swift:901–902`、`1242–1250`，对照 `PreviewBGAView.swift:158–187`、`666–697`。

触发：显示同步路径中，所有 BGA 更新均 `throttle:true`，只要距离上次小于 1/30 秒就完全返回，未查询事件索引。若图片 BGA 60 Hz 交替，或两事件间隔不足 33 ms，中间事件可完全跳过；BGA 事件本应使用谱面同一时钟。

影响：图片切换变为最多 30 Hz，和原版逻辑兼容目标冲突。这是确定性分支行为，不是推测视频 seek 性能。举例：上次同步 0 秒；在 1/60 秒发生 B 图事件时节流返回；到 2/60 秒恰好已有 C 图事件，只会绑定 C，B 从未被消费。

最小修复范围：每显示 tick 查询便宜的当前 BGA 事件身份；相同图片事件已有 `boundKey` 早返。只给同一视频事件的 drift/seek 或低频 chrome 节流，事件变更立即同步。加入高频图片事件、同拍 base/layer 和 STOP 内 elapsed 的用例。尚未跑真实屏幕截图验证。

## UP 统计独立复核

直接解析 `perf/csv/*.csv` 并按 UP 的“提交 uptime 落在 play+0.5 秒至 stop 的稳态窗口、serial 对应正 presentedTime、相邻差、nearest rank”重算。七场景 p50/p95/p99 全部逐值匹配。结果 `up-csv-independent-check.json`。各场景有一个 presentedTime≤0 被正确剔除；未发现倒退呈现时间影响主结果；GPU 过滤 `<50 ms` 在这组数据未剔除任何 ≥50 ms 样本。

| 场景 | 间隔数 | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| normal-silent | 162 | 16.667 | 16.667 | 16.670 |
| dense-silent | 161 | 16.667 | 25.000 | 25.004 |
| normal-audio | 166 | 16.667 | 25.000 | 33.333 |
| dense-audio | 133 | 16.667 | 50.000 | 100.001 |
| bga-image | 161 | 16.667 | 25.004 | 33.334 |
| bga-video | 162 | 16.667 | 25.000 | 25.000 |
| bmson-normal | 162 | 16.667 | 16.671 | 16.672 |

这些是真实 `CAMetalDrawable.presentedTime` 回调，不是 geometry 耗时，也不是扫描输出。限制必须保留：

- 七场景 stop 时全部 `windowOccludedAtStop=true`；后五场开始前亦 true，前两份旧 summary 未记录开始前状态。没有逐帧可见状态，不能把整段认定为用户可见稳定窗口。
- 基线 drawable 为 999×1324（视图约 499×662），新原版比例默认 playfield 将约 1324×1024，面积相近但形状/可见拍数不同。正式性能对照需固定物理像素面积、滚速、同时间区间与相同事件，且另报默认布局体验，不能仅比较默认尺寸。
- 探针 onPlayheadBeat 是空闭包，没有主编辑器 `ChartRenderer.rebuildGeometry` 的负载。修掉 editor nil 回调的实际收益尚需完整应用对照。
- 稳态仅约 2.7 秒、每场单轮；p99 最多由少量尾部样本决定。应延长至有代表性的稳定区间并多轮、明确 startup 单列，采样低频 CPU/GPU/内存，禁止因窗口不可见而强行禁用产品守卫制造 FPS。
- display.json 的 NSScreen 上限、CV/CG 名义周期及 CADisplayLink 时间戳均约120 Hz；这支持刷新参考值，不能证明每帧扫描输出。

## 当前未确认/最终复查清单

- US 正在重写真实皮肤纹理。审计途中谱面文件连续变化，不对旧颜色 pipeline、未完成 `presentPlaybackFrame` 缺口或暂态编译失败报告 bug。稳定后核查 atlas 一次上传、nearest、每帧无磁盘/全历史扫描、真实 submit 与 presentedTime 区分。
- 早期 Metal live draw 先非阻塞获取三缓冲 semaphore，失败跳帧；提交完成后释放，失败路径 defer/signal；单 command queue 下未发现已证实的共享顶点 buffer 提前覆写。`currentRenderPassDescriptor/currentDrawable` 自身仍可能等待 drawable，尚无计量，列风险不列缺陷。
- 早期 BGA 事件索引二分、同事件不重复路径解析/时间积分、图片后台解码和有限 NSCache 是正向变更；不据此声称整个 BGA 热路径无开销。图片请求任务取消/短时间多图的资源上界尚未实测。
- 重新检查 UA2 音频准备、UW 隐藏/屏幕切换/无 editor 回调、US 最终纹理与实际 on-screen presentedTime。使用相同条件的 before/after 和完整应用有音频/视频负载。
- 本机没有 Windows uBMplay 同条件实测，不能承诺绝对性能超过原版。

## UA2 稳定音频快照独立复查：未通过（等待 UA3）

音频原件保存为 `audit-performance/LegacyPreviewAudio-UA2-original.swift`，SHA-256 `a9a21cb1a42975c2559ec64dd08e3e630d441808827f6d0b9e28259959bc4301`。以下行号均对应这个已固定快照。独立重编译并运行 UA2 产品测试成功：`ua2-product-tests.log` 显示测试全过，playChartReturn 1.241 ms、readyDelay 158.639 ms、deferredHit 0.058 ms。**这些测试没有覆盖下面已复现的声音丢失，不能作为兼容验收通过。**

审计脚本使用原件源副本；`LegacyPreviewAudio-UA2.swift` 仅添加一次 commit 时的 cue 总数/缺资源数；`LegacyPreviewAudio-UA2-tap.swift` 仅添加 mainMixer 输出 tap。实际运行结果分别为 `UA2-independent.json`、`UA2-rendered-audio-tap.json`、`UA2-spaced-audio-tap*.json`。未改产品或产品测试。

### P1：lookahead 提前占用声部，普通稀疏音符被取消

位置：`voicePlan` 1103–1150 按真实 `[start,start+duration]` 重叠分配声部；`scheduleDueCues` 1153–1158 提前 0.2 秒触发；`claim` 782–788 仅按 token 是否空闲；`trigger` 709–718 抢占时 `node.stop()`。

可复现负载：10 个同一 50 ms WAV，间隔 100 ms，根本没有声学重叠，正确只需一个可按顺序排程的节点。UA2 只建 1 voice，ready 时已经发生 2 次抢占，播放 600 ms 后 7 次。原因是未来 t=0.1、0.2 秒的音在 t≈0 便占用同一个 token，后音 `stop()` 取消前音和已排程的 buffer。

不只依赖自报计数：对相同负载添加 AVAudioEngine `mainMixerNode` 输出 tap，11 块输出中只有末尾一块有非静音 PCM（约 ready+0.971 秒，2392 个活跃 48kHz frame≈50 ms），9 次抢占，前 9 音被取消。tap 是引擎真实渲染输出，未做扬声器硬件回环。UA2 `soundingSampleCount` 根据预计 startedAt/token 推算，不能证明实际发声。

最小修复：区分已排队与正在发声生命周期；可在单节点按 sample time 队列顺序排非重叠 buffer，或按包括 lookahead 的占用区间预分配/预约 voice。只有真实同时重叠超过策略上限才允许有明确策略的抢占。完成释放应对应实际排程 token，禁止后音 stop 掉仍应播放的前音。验收必须捕获渲染 PCM 验证10次脉冲，不只看计数。

### P1：128 资源缓存会在 ready 前永久删掉有效谱面声音

位置：`completeLoad` 1051–1055；`store/evict` 638–650、814–823；`commitPreparedChart` 1070–1074。

独立探针准备 140 个不同路径、每个相同合法 50 ms 小 WAV，总 float PCM 约1.2 MB，远小于64 MB。结果后台成功读取 140 次；commit 时12个cue的资源已被 LRU 淘汰并直接改成 `key=nil/fired=true`。`ready=true` 且 `diagnosticDroppedVoices=0`，这些音永久静音；它们不会在之后重新预取。准备阶段所有资源 pins=0，因此淘汰选择受字典/异步完成顺序影响，不能认为只会牺牲曲尾。

最小修复：当前曲资源不得在建立 cue 后被不知情地淘汰。若有内存预算，按时间窗口流式准备/预取/消费/释放，当前需要的数据和未来事件必须保持可恢复；不能把缓存未命中转换成成功的静音。加入 >128 资源整曲每音输出、超预算逐段播放和清晰失败状态测试。

### P1：64 MB 单资源解析上限会静默丢掉长 BGM

位置：`PreviewPCMDecoder.parseWAV:526–527`，对转换后的 Float32 全长数据先作64 MB限制，随后失败处理沿用上一项静音分支。

探针输入合法4分钟、44.1kHz、双声道16-bit PCM WAV，原文件42,336,044字节，float预计84,672,000字节。结果 `.ready` 成功、missingCues=1、sounding=0、drops=0、engineFailure=none。原版可播放的常见整曲BGM因此整条消失；这不是仅极高同时发声数的取舍。

最小修复：长资源走分段解码/磁盘流或明确可播放的资源路径，在后台受预算地预取；不可因“缓存策略”吞掉有效BGM。无法准备应明确失败，不能报 ready 后无声。验证长BGM在缓存上限内连续输出和停止释放。

### P1：跨谱声部格式保留导致下一首正常单音全静音

位置：`prepareVoices:654–674` 只追加、达到32后不再添加；`stopAll:748–758` 不回收或重新配置旧格式；`claim:782–788` 只能选相同格式。

探针第一首32个同时44.1kHz单声道音，停止后第二首只有一个48kHz单声道音。第二首正常 `.ready`，nodesCreated=32，但 drops=1、soundingCount=0、engineFailure=none。因为32个闲置节点全部旧格式，新格式无法获得任何voice。即使单首从未超过32，长期切换多格式谱面亦会累积到同一状态。

最小修复：在 prepare 阶段重用/重接闲置节点或统一为 mixer 的固定采样格式；跨曲清理旧计划的无用格式。热路径不重接的要求应由准备阶段完成，不得换成后续格式永远静音。

### P2：ready 回调 stop 后仍收到旧代 elapsed=0

位置：`commitPreparedChart:1092–1094`，`.ready` 回调之后先无条件调用 `onElapsedSeconds(0)`，之后才检查 generation。

探针 `.ready` 回调立即调用 `stop()`，事件顺序明确为 `ready → stopped → elapsed:0.0`。若回调切换成下一首，还可能把旧代sample交给新回调。最小修复：每个可重入外部回调后先检查 generation/timeline，再进行下一个操作。加入 ready 回调中 stop/replay/close 的用例。

### P2：每100 ms 补队列仍遍历全曲所有 cue

位置：`scheduleDueCues:1156` 和 `armAudioPump:1202`。前者每次 `for cues.indices where ...` 全量检查 fired；后者 `cues.contains(where: ...)` 也重复扫描。随着前部 cue 已播放，仍需扫描全曲/整个前缀，没有下一未排程索引。此项由代码确定复杂度；尚未给出大谱CPU实测，不能据此宣称新presentedTime下降。

最小修复：cues已按seconds排序，维护下一待排索引，顺序推进至lookahead末尾；generation/stop清理索引。用十万/百万cue固定时间段统计访问量，避免只用40音测试。

### 排程时钟的渲染证据与限制

三个50 ms音，间隔500 ms、无voice抢占，mainMixer tap两轮的首个非零sample相对 ready 分别是42.781/514.365/1019.636 ms，以及42.727/516.748/1018.289 ms。首个间隔471.583/474.021 ms，与目标500 ms差约26–28 ms；第二个间隔505.271/501.542 ms。

源码 `sampleTime:769–779` 用最近一次 node/player render time 加当前 lead，fresh node 无有效render time时从sample0估计。它没有把 origin 映射到统一且可靠的未来引擎 epoch。上面tap证明当前首音/未来音间隔存在非固定偏移；**不是**扬声器输出延迟测量，不能声称所有系统恒定提前28ms，也不能把系统输出延迟与谱面偏移混为一谈。应先统一engine epoch，再验证相对脉冲间隔、首次ready、热缓存重播及多格式节点。单个提前0.25秒buffer的完成回调不足以证明全曲同步。

### 同负载 before/UA2 主线程比较（不能作为验收通过）

对16个100 ms间隔音加1.7秒的12音和弦、同一50 ms WAV负载，UA2第二轮：`playChart`返回0.621 ms，ready延迟299.297 ms（后台准备/启动独立列出），资源加载1次，主线程资源读取0次；ready+0.1秒后心跳p95 10.080 ms、p99 10.272 ms、max12.829 ms。此前旧路径心跳p95/p99/max为17.086/43.037/151.798 ms。启动从同步阻塞变为异步准备是有效方向，但本轮仍有1次错误抢占；因此不能通过“丢掉部分声音后心跳变好”宣称性能目标已完成。

UA2同负载另一轮调度最长11.582 ms，第二轮6.999 ms；产品小测试报告0.058 ms，两者都是单轮、负载/热状态不同，不能把0.058 ms推广为所有hit上限。独立tap与同负载对照分别运行；测试并发/系统负载影响绝对值。上述全部问题和证据已发给主代理，主代理已交UA3修复；待UA3稳定后再次独立复查。

## UA3 / UW2 稳定快照复查：部分关闭，长 BGM 与实时 I/O 仍未通过

快照清单为 `audit-performance/UA3-snapshot-hashes.json`；音频 SHA-256 `3986028b3883a4378dba21247887cce9a763fc1609df1fb3105f48fb7e83af48`，窗口 `098a6ee05dd371aa21ff95b252bdc71d0c6dd2f18d85e8d28c29567f0f09419f`，BGA `5675539b43c20298b40acf6eb0e10e484ff7a9e0ea1be55cd5e3c570a07ded10`。原件均保存在同目录 `UA3-*.swift`，审计结果不会受正在进行的 UA4/UW3 改动污染。以下行号指这一快照。

独立编译并完整运行产品音频测试通过，`ua3-product-tests.log`；另外重跑先前全部负载及新增 PCM tap/窗口探针，不以实现方报告替代验证。

### 已关闭的原问题

- **lookahead 丢普通音：已修复。** 原10个50 ms WAV、100 ms间隔负载，独立 mainMixer tap确有10段输出、无抢占，相邻onset分别100.000、100.000、100.000、100.000、100.000、100.037、100.005、100.005、99.966 ms。证据 `UA3-10note-audio-tap.json`。同节点顺序append避免未来音取消前音。
- **节点时钟相对间隔：已修复所测回归。** 3音500 ms间隔独立tap为500.000/500.0045 ms，证据 `UA3-spaced-audio-tap.json`。相对ready回调仍约提前11 ms，为engine render tap/host时戳与回调时刻关系，不当作扬声器画声误差结论；硬件回环仍未测。
- **128资源准备互相淘汰：已修复。** 原140个小资源探针全部加载140，commit missingCues=0、drops=0；新工作集不受闲置缓存128条限制。证据 `UA3-independent.json`。
- **跨谱格式池耗尽：已修复。** 原先32个44.1k声部后切单48k音，现在nodesCreated仍32、drops=0、sounding=1；prepare阶段可重接旧格式。相同证据。
- **ready回调stop旧elapsed：已修复。** 原序列现在为`ready → stopped`，没有旧sample。相同证据。
- **补队列全曲扫描：已修复源码路径。** `scheduleDueCues:1639–1663` 使用nextCueIndex顺推和有界时间窗口预取；`armAudioPump:1757`不再contains扫描。独立全量产品测试通过2万cue访问量断言；未把该断言换算为墙钟性能。

### P1 仍开：合法4分钟BGM仍被静默吞掉，UA3报告的shortfall承诺未覆盖这个路径

位置：`PreviewPCMDecoder.parseWAV:532`仍直接拒绝float PCM>64 MB并返回nil；`completeLoad:1483–1487`对nil不记录错误/拒绝；`openingFits:698–715`只检查已存在entry或rejectedKeys，没有cache entry的解码失败被认为可以起播。`pumpCue:1683`随后把这颗静默标为fired。

原4分钟44.1k双声道16bit WAV探针独立重跑：states=`preparing, ready`、ready=true、shortfall=0、sounding=0、commit missingCues=1、engineFailure=none。输入42,336,044字节、预计float84,672,000字节。证据 `UA3-independent.json`。因此这次没有变成显式shortfall，**仍是原P1静默丢BGM**。

窗口实际状态亦复现：新音频+UW2源副本构建小探针，资源注入同一合法长WAV，等待1.5秒后`playing=true, elapsed=1.483989, sounding=0, shortfall=0`，显示`0:01.48 · 2.97 · 120 BPM`，无资源错误。证据 `UW2-long-BGM-display.json`。这不是只阅读源码的推断，也不应把“窗口照常计时”当音频正常。

最小修复建议仍是后台分块转换/长音流式调度，保持正常长BGM输出。仅将此路径改成shortfall也不能满足原版逻辑兼容；同时必须区分缺失文件、无效格式、超预算与引擎错误，不能统称缺文件静音。主代理已将此项交给UA4继续实现。

### P2 新确认：溢出/回载路径在实时主线程同步写临时文件

位置：`@MainActor PreviewChartMixer.spill:1018–1032`，`data.write(to:options:.atomic)`在1024；`installSpill:773–806`在预算不足时调用795的`spill(victim)`；调用方`LegacyPreviewAudioPlayer.installPrefetch:1744–1748`在主actor。`planarData`和`makeBuffer`的逐sample复制也在同线程。

独立负载：4条8820字节PCM，测试预算10000字节，音符间隔1秒，成功schedule4、lateMisses=0、drops=0。插入起止时戳后，3次发生在ready之后的atomic写入均`Thread.isMainThread=true`，耗时0.827/2.279/1.784 ms。另3次准备阶段写入也是主线程。证据 `UA3-spill-mainthread.json`，源码副本`UA3-Audio-spill.swift`只增加计量。默认64 MB需更大曲目触发，不能把小预算耗时外推为默认长帧数；**实时同步I/O的存在已经实证**，故不能声称新音频hit周边全无I/O。

最小修复：后台生成/保留可反复使用的spill或转换文件，实时阶段只异步读取预取，预算淘汰仅释放驻留buffer，禁止为了回载另一资源同步再写被淘汰PCM；缓冲拷贝可在线程安全的准备层完成后传递。仍需测默认预算下真实密谱+BGM负载presentedTime，主线程心跳不能替代。

### UW2 原隐藏/图片BGA问题已关闭

固定快照审阅确认：`suspendPicture:1019–1027`拆display link并关闭外部驱动，播放器沿原origin恢复Timer，BGA hold一次；`writeClock`隐藏路径`.logic`不调用render/BGA；`content.syncBGA:1381`不再统一30 Hz限流。

独立重新编译/运行窗口生命周期、编辑器清理、快速BGA事件、异步准备测试，全部通过。审计源`UW2SelectedTests.swift`只选这四个相关测试并添加长BGM状态探针，固定fixture路径，未写实现方截图；日志`uw2-audit-tests.log`末行`PreviewWindowTests passed`，stderr为空。验证隐藏跨终点结束一次、呈现与playfield更新不增长、恢复不重新读取文档；真实本地视频隐藏后rate=0且未反复打开；20 ms图片BGA事件base依次AA/BB/CC、layer L1/L2/L2；准备阶段不挂显示链，迟到ready不恢复已停代。测试创建自己的窗口，未操作用户现有窗口。

这些测试是生命周期/事件逻辑证明，尚未测用户可见窗口presentedTime、遮挡状态变化全过程或后台GPU。因此关闭原两个确定性逻辑缺陷，不等于完整性能验收通过。

### UA3同负载性能数据

同原16个100 ms间隔音+12音和弦、同一50 ms WAV的独立运行：playChart返回0.590 ms，ready延迟347.716 ms，main资源读取0次，deferredHitMax 0.096 ms，steals/drops均0。ready+0.1秒后120Hz RunLoop心跳p95/p99/max为10.845/11.366/11.685 ms。旧路径对应17.086/43.037/151.798 ms。此次有声音正确性tap支持，改善方向成立；但不同轮系统负载、准备延迟和tap未一起运行，仍不作为最终FPS/画声同步结论。

**当前结论：UA3已修复普通keysound的主要回归，UW2已修复隐藏收尾和图片事件漏采样；合法长BGM仍无声、spill实时主线程写盘仍开。等待UA4、UW3与整体集成后的最终帧节奏复查。**

## UA4 稳定音频快照复查：长 BGM 真正出声，仍有三项 P2

原件 `audit-performance/UA4-LegacyPreviewAudio.swift` SHA-256 `3a8318d2b8713c7b16dcae090879a8b214ac64cd6f629ab5b1fe9b51c2cd6aaf`。下面行号指原件。独立重新编译并完整运行产品音频测试成功，`ua4-product-tests.log`，包含此前稀疏10音、140/500资源、跨格式、取消/重播代际、同host、长BGM、pause/startPaused与声音类别测试。未把“全部通过”当作没有下面问题。

### 原 P1 长 BGM 已关闭所测 PCM 路径

独立生成真实磁盘4分钟44.1k双声道16bit连续正弦WAV，文件42,336,044字节，前239秒440Hz、末秒880Hz。新路径不再把整段转Float32。`UA4-independent.json`：ready成功、drops=0、sourceBytes42,336,044、decodedPeak0、blockBytes352,800；录制3.2秒mainMixer PCM，440Hz相关能量0.07248，880Hz0.000069，峰值0.15256。采样跨越多个1秒scheduleSegment边界，未看到明显长静音；10ms窗统计有一个静音窗，属于开头采样边界，尚未做样本级连续性或硬件回环证明。

Here从beat478.5（239.25秒）开始，未重新加载、drops=0；880Hz相关能量0.06988，440Hz0.000108，确有尾段声音。**此项有真实PCM出声证据，可以关闭“>64MB长PCM一律无声”的原P1。** OGG/MP3仍由现有解码器返回整段Data后后台写临时WAV，峰值内存不能套用PCM路径的decodedPeak0；真实OGG+C++桥尚未测。

原UA3同步atomic写盘路径在当前准备方案中已移到worker。小预算资源亦能播放，后台临时写入有完整产品测试。但“实时无主线程I/O”仍不能关闭，见下一项。

### P2 仍开：文件音符每次触发在主 actor 打开 AVAudioFile，磁盘钩子漏计

位置：`PreviewChartMixer.triggerFile:1214–1245`，1243每个hit都`AVAudioFile(forReading:...)`；该mixer是`@MainActor`，由`fireCue`调用。文件头打开依然是同步文件操作，不能因为不读整段PCM就归为无I/O。

独立源副本在这个真实调用周围加起止时戳；同一50ms短WAV、budget1000，4个1秒间隔音，全走文件排程。4次均main=true，耗时0.689/1.362/0.912/1.161 ms，后三次发生ready之后。`traceDiskAccess`却只记录`read-background=2`，没有捕获这4次真实open。证据 `UA4-independent.json → smallBudgetIO`。本轮未测冷磁盘/网络卷，不外推最坏耗时；现有“磁盘钩子主线程0”的证据不完整。

最小修复：准备阶段/后台建立可复用且隔离正确的读取句柄/流式资源，hit只消费准备好的队列。明确AVAudioFile/AVAudioEngine线程要求并处理同资源多声部重叠，不能简单把共享可变file position跨线程乱用；跟踪所有真正文件打开/读写，不能只给自有Data路径打钩子。

### P2 新确认：silent / missing-resource 谱的 startPaused 被忽略

位置：`commitPreparedChart:2083–2112`。`audible=false`分支2108把pausedBeforeStart设false，未设置isChartPaused/pausedElapsed；emitOrigin随后启动Timer。

独立空音频谱、visualEndBeat8、`startPaused:true`，泵RunLoop350ms后isChartPaused=false，elapsed样本持续增长到0.354秒。证据 `UA4-pause-boundaries.json → startPausedSilentChart`。适用于纯BGA、缺音频和无声谱的暂停保持/重载，与有声谱语义不一致。

最小修复：暂停是时间轴状态，不应依赖是否创建声音节点；无声谱也保持elapsed0直到resume，且stop/自然结束回调约束相同。增加silent、missing以及所有类别被过滤时的startPaused测试。

### P2 新确认：驻留预算只约束单资源，当前全谱可以无界累计

位置：decoder 528–530按“每条<=budget且<=1MB”挑inline；`PreviewChartMixer.store:985–1015`不检查全谱累计；`evictIdle:1433–1442`只淘汰非workingSet的旧资源。当前工作集整体超过residentBudget时找不到victim，直接返回，仍ready。

独立4个不同合法50msWAV，每条Float32为8820字节，budget10000；commit时residentBytes35,280、resources4、ready=true，超过预算3.5倍。证据 `UA4-memory-budget.json`。同样逻辑在默认64MB下可让大量<1MB的keysound累计超过64MB；没有实测OOM，不将其描述为已发生崩溃。现有预算不再是总驻留上界，不能继续宣称“音频内存受64MB控制”。

最小修复：准备时给本谱所有inline资源分配总字节预算，超额资源走已有后台文件流；按可见时间窗口或使用频率选择驻留，而非让每条独立消耗全额预算。测试须累计总驻留bytes和实际进程峰值，不能仅观察单资源decodedPeak。

### 暂停/容量/时钟的独立核验与限制

- 再次给UA4源副本独立添加mainMixer tap，原10音确有10段、steal0，相邻间隔99.958–100.042 ms；3音500ms间隔为499.437/500.375 ms。证据 `UA4-10note-audio-tap.json` / `UA4-spaced-audio-tap.json`。不是仅复用UA3旧结果。
- 长BGM正常pause350ms：tap没有新增frame；resume新增13,230frame且峰值0.15256，elapsed从0.2027继续到0.5562，无stop/finish，无重新加载。startPaused长BGM准备后tap峰值0，resume后0.15256且elapsed继续。证据 `UA4-independent.json`。
- 1.5秒文件音、startPaused等待1.9秒（超过音长）再resume，tap活跃时长1.495秒，未看到截断。证据 `UA4-pause-boundaries.json`。未将代码猜测的release问题误报为缺陷。
- 32个3秒低音在0秒开始，1秒第33个880Hz短音，独立tap在1.0–1.3秒有880Hz输出，steal1/drop0；未看到抢占后node时钟错位。证据 `UA4-steal-timing.json`。实际超过32重叠仍会牺牲旧声部，与Windows原版容量是否一致尚无证据，仍是兼容限制，不能声称完全兼容。
- `setPlaybackRate`只有存储请求，未改变声音或时钟。此功能明确未完成，任何UI不得把请求值显示成已经生效的倍速。
- 原140资源、crossformat、取消代际仍由独立编译的完整产品测试覆盖；真实设备断连/切换、后台长时连续播放、超多格式和冷存储未实测。引擎tap也不等于扬声器硬件输出或窗口presentedTime。

以上三项P2和长BGM关闭证据已发主代理；UA4没有作为整体性能/原版兼容最终通过。窗口UW3与皮肤仍在并行实现，最终实际呈现节奏后测尚未进行。

## UA5 稳定音频复查：原三项P2修复，新增两项P1

冻结源 `UA5-LegacyPreviewAudio.swift` SHA-256 `c702ccd72055861494e75488df645217bdcd7662f9d3dbd6202cb576f189a9f7`；测试 `UA5-LegacyPreviewAudioTests.swift` 为 `2a49fa561ca85b130419b639d8dc986ec4fcf9da39f5adc6cf462935013636f2`。源hash在读取实现报告前固定。对冻结源和测试独立重编译、完整运行退出0，stderr为空；日志 `ua5-product-tests.log`。Cursor任务末尾非零状态不等于音频实现编译失败，本审计以自己的编译/运行结果为准。

已阅读最新现代化合同：原版是外观、交互含义和谱面语义参考，不默认要求复制旧DirectSound容量/频率限制或VB实现缺陷。现代实现仍必须避免真实漏音和错位。此节没有要求照搬原版单槽声音或阻塞路径。

### 已关闭原UA4三项P2

- **主线程AVAudioFile打开已修复。** 在真实构造处的`traceFileOpen`，小预算4个文件hit仅记录一次false（后台），后续3次触发没有再打开。独立源码搜索确认构造在worker的`openReadHandles:734–751`；handoff后主actor独占句柄，不靠把AVAudioFile声明Sendable隐藏隔离。证据 `UA5-independent.json → smallBudgetIO`。此项仅证明真实open不在主线程，不声称AVFoundation内部完全无I/O或整个系统无阻塞。
- **无声startPaused已修复。** 原探针现在paused=true、samples仅[0]；补测fresh无声/缺资源谱resume恢复计时。证据 `UA5-pause-boundaries.json`。有声长文件startPaused等待1.9秒再resume仍输出约1.491秒，未截断。
- **本谱PCM合计预算已修复所测场景。** 原4条各8820字节资源、预算10000，resident8820/resources1，其余文件路径不丢音。`diagnosticInflightScheduledBytes=8820`独立列出。证据 `UA5-memory-budget.json`。缓存预算不等于AVAudioEngine在途/转换或进程总内存；未将64MB宣传成进程总上界。

### P1 新确认：预开32句柄临时用尽，被误当缺资源永久丢音

位置：`readerCount:700–712`上限32；`isResident:1121–1124`把“当前没有闲置句柄”当作资源不在；`pumpCue:2658–2682`在非resident且非spill时直接fired=true；`trigger:1372`也以闲置files非空为条件。句柄虽然后台打开，但租借池和资源存在性被混为一谈。

独立真实磁盘短WAV：220个44.1k样本≈4.989 ms，音符间隔6 ms，共100音，声学没有重叠，只建1个voice；预算1字节迫使文件路径。worker预开32句柄且全false（非主线程）。第一次实际schedule95；第二次schedule96，**真实变速单元输出PCM包络也仅96段**，steals=0、drops=0。证据 `UA5-handle-exhaustion.json`，`UA5HandlesMain.swift`保存每段实际onset。

包络阈值0.02、连续无能量超过0.7 ms判下一段：440Hz正弦自身过零间隙短于阈值，音间静音约1 ms，正常完整输出应100段。第二轮actualPCMbursts恰好等于scheduled96，说明不仅是自报计数缺项，实际声音也少了4段。首轮95与次轮96差异取决于主线程补队列/释放时刻，不影响漏音结论。这是**提前排程占句柄**，不能解释为超过32真实polyphony的产品策略。

最小修复：资源存在性与闲置reader分开；临时池空保留cue并重试，不能直接fired。reader归还后及时继续队列，保证到拍点之前可用；可复用已读块/按真正排程区间管理所有权。增加100音真实PCM计数、跨速率/暂停后的相同负载以及正常预算大谱触发此路径的测试。主代理已交UA6。

### P1 新确认：照搬旧频率上限导致高采样率谱默认半速，旧缓存还污染下一首

位置：`PreviewAudioLimits.playbackRateCeiling:448–457`使用旧`5*Int(2000000/R)/100`和`100000/R`；`maximumSampleRate:1275–1278`把所有缓存与旧voice采样率混合；准备时2489自动refresh倍率。

独立合法192kHz单声道PCM，用户没有请求变速，默认1倍在ready后变成requested=0.5，elapsed0.182217对wall0.364491。随后同播放器显式`setPlaybackRate(1)`，改播44.1k文件，仍requested=0.5、elapsed0.183631对wall0.367379。证据 `UA5-high-samplerate.json`。因此不仅是“最大倍率稍保守”，连正常播放速度都错了，且跨曲污染。

没有证据表明现代AVAudioUnitVarispeed需要DirectSound的100000Hz上限。按用户最新现代化指令，应以现代组件实际支持的0.25…4范围及当前资源能力处理，清晰显示实际值；不得让旧历史缓存把新曲速度夹紧。主代理已记录统一现代范围决策并交UA6，需复测192k默认1倍、192k2倍、随后44.1k和UI实际倍率一致。

### 倍率、暂停与声音正确性的独立实测

- 另加自己的变速单元输出tap，稀疏10音确为10段、steal0，间隔100.000 ms附近（最大偏差0.010 ms）；3个500ms间隔为500.000/500.011 ms，证据 `UA5-10note-audio-tap.json` / `UA5-spaced-audio-tap.json`。不是复用UA4或实现方测试结果。
- 4分钟文件头部输出440Hz（相关能量0.07375），Here尾部880Hz（0.07019），drops0、decodedPeak0、block352800；录制3.2秒中没有10ms静音窗。证据 `UA5-independent.json`。
- 独立1→2动态倍率：变速前440Hz相关能量0.06841/880Hz0.000174；变速后880Hz0.07622/440Hz0.000048。chart从0.265774连续到0.864440，墙从0.265781到0.566404。pause中改0.5，chart与wall都冻结；resume约0.3005墙秒，chart仅增0.15026秒，符合0.5倍。证据 `UA5-rate-independent.json`。
- 同一独立探针的3个500ms谱间隔在2倍速下为250.000/261.202 ms；含1秒STOP的2谱秒间隔为1.01814墙秒。小测试实现报告250ms/1.020s也由独立产品测试重现。单轮主RunLoop/音频块回调有抖动，本审计保留实际数值，不把约11ms偏差说成全部事件严格sample准确，也没有足够证据将其归为确定性时钟bug。
- 正常pause350ms无新增PCM；resume新增13230frame且峰值0.15256，未发stop/finish。startPaused长音前峰值0，resume后0.15256。ready回调stop重入、旧代取消、140/500资源和跨格式由独立冻结全测试覆盖并通过。
- OGG/MP3仍由解码桥返回整段Data，未做真实OGG+C++桥的峰值/长帧测试。预开句柄数可按资源乘以重叠增长，不等于全进程只32个文件；当前没有测FD极限或整进程内存峰值。真实polyphony>32仍会抢占，是现代产品容量选择的未验收项，不默认复制原版意外限制。

**本轮结论：UA5有效修复主线程文件打开、silent暂停和PCM总预算，但短文件句柄压力仍真实漏音，高采样率默认速度被旧上限改错。UA6完成前音频不通过；窗口UW4与最终presentedTime后测另待集成稳定。**

## 固定W4谱面准备耗时独立复现与有界优化合同

只使用兼容审计保存的 `audit-compatibility/post-UW4-source/`，未读取正在US5修改的产品作为测量输入。谱面源SHA-256 `823355eca83eb2e68819a2a99975c3bbf8cbac218d81611cbfa2ba18beb666c7`；音频源为固定UA5。脚本 `audit-performance/TimingProbeFrozenW4.swift` 从父代理固定探针复制，独立以`swiftc -O -swift-version 6 -target arm64-apple-macosx14.0`和相应AppKit/AVFoundation/Metal框架重编译，运行退出0。

探针只有一个331×256视图，传`device:nil`，不创建真实GPU呈现；主actor计时`setChart`和`setTiming`。输入一条lane，每1/8拍一颗音，1000个交替120/180 BPM事件及1000个0.1秒STOP，变化事件按拍0…999排列，fromBeat0。结果 `w4-timing-results.txt`：

| 音符 | setChart ms | setTiming ms | 父代理setTiming ms |
| ---: | ---: | ---: | ---: |
| 1,000 | 0.234 | 9.212 | 9.878 |
| 10,000 | 1.531 | 93.980 | 94.585 |
| 50,000 | 7.038 | 470.276 | 492.221 |

独立结果与父代理口径一致。50k音单视图约0.47秒同步主线程准备，是可见起播/重载停顿风险，按P2准备开销记录；**不是稳态帧间隔、不是FPS，也未证明应用总开销必定是两倍。** `setTiming`还调用一次`rebuildGeometry`，计时没有单独扣除它；但源码明确每音符重复filter/sort/扫描BPM和STOP，具有直接优化依据。

位置：固定 `PreviewPlayfieldView.swift:1566–1594` 的`setTiming/rebuildHitSchedules`逐note调用`PreviewPlayfieldClock.arrivalSeconds:360`；`seconds:378–405`对同一timing反复过滤、排序并积分。N音、E事件，目前约O(N·E log E)，并多次创建数组。这里应采用现代不可变准备索引，不复制原版逐音符主循环。

下一有界实现合同建议：

1. **timing只预处理一次。** 对合法有限BPM/STOP按beat稳定排序，保留原输入sequence；同拍BPM维持当前“最后一项生效”规则，同拍STOP秒数累加。构建运动积分分段和STOP前缀，O(E log E)，不可变、可安全在后台准备。
2. **使用同一个到达函数。** 定义`F(b)`为到beat b第一次到达的累计秒：运动积分加所有`stopBeat < b`的STOP。计算`arrival(b,origin)=F(b)-F(origin)`；以二分查询O(log E)，或将note索引按beat排序后一次合并扫描O(N+E)。终点b上的STOP不包含，origin上的STOP包含在后续beat里，beat<origin返回负到达时间。不要用“所有<=b的STOP”造成判定时刻偏后。
3. **同拍顺序和异常值不能悄改。** beat b上的BPM用于离开b之后的运动，不能改变到达b本身；BPM与STOP同拍时先到达b、停顿、再按b后的BPM前进。保持当前非正/非有限事件过滤及无效header回退策略；相同beat的输入次序明确稳定。来自core的拍/STOP秒已经归一化，不另乘BMS STOP单位。
4. **每谱准备一次并复用。** 生成每lane按到达秒排序的hit schedule后供两谱面视图共享，时钟origin变化可用常量偏移或重新二分，不按每帧/每次只切side重复算全谱。新timing/notes版本才重建，generation取消防止旧后台结果覆盖新谱；一次短主actor提交，避免把全量排序/积分搬回UI。
5. **先保语义，再比准备数据。** 用冻结旧函数作差分oracle，覆盖同拍BPM/STOP、origin STOP、重复事件、未排序输入、负beat/负arrival、Here/反向seek、长STOP、非法值和空谱；普通有限数据逐note秒差在合理浮点容差内。独立Release复跑相同1k/10k/50k负载，报告准备墙钟、内存/访问量，确认播放热路径未新增工作；不得减少音符/事件或改变STOP语义换数字。可以以50k准备显著低于原470ms为目标，未经实现验证不保证某个绝对毫秒阈值。

该优化应在US5双时钟修复稳定后另一个有界批次进行，避免把效果墙钟修复、音频倍率和timing优化混成无法评审的大改。主代理已收到独立结果与合同；本审计未写产品实现。

## UA6 稳定音频复查：1/2倍句柄漏音修复，4倍音频排程仍有P1

固定音频SHA-256 `8b176e8157cb07a3f775e37a3e506d4c7ea2d8c9011fa1c52d61284bda44d3ed`，测试`b42309520ee4713cf1f25a1838e38ee8824fba9a1a6f781a54e574e2b4fc65e3`，Behavior `e00e4a2ae2b1f0864de63bfb2933dbde1fe02b3ef5aac9b4804bcd6d4dea5391`。原件及清单在`UA6-*.swift`/`UA6-source-hashes.json`。独立重编完整产品测试退出0，stderr空，`ua6-product-tests.log`含100/100的实现方新增病例；审计额外压力不在该完整测试覆盖内。

### 已确认修复/保持通过

- 100个约5ms WAV、6ms间隔、预算1字节迫使文件路径：1倍和2倍独立测试各为scheduled100、实际PCM包络100、drops/steals0、一个voice，32个文件构造全部在后台。原1倍池空误当缺文件的问题关闭所测范围。
- 合法192kHz默认速度恢复1倍，chart0.371777/wall0.371787；随后44.1k仍是1倍，chart0.373176/wall0.373242，缓存污染消失。`UA6-high-samplerate.json`。192k2倍及96k2倍的真实880Hz输出由独立编译的冻结全测试再次通过。
- 4分钟BGM头440Hz/尾880Hz继续有真实PCM，drops0、decodedPeak0、streamBlock352800；pause350ms无新增PCM、resume继续输出；startPaused前静音、resume后有声。`UA6-independent.json`。真实构造hook小预算4hit只一个false（后台），ready后无新open。
- 原合计驻留预算、无声/缺资源startPaused、ready回调stop重入、取消代际、140/500资源与跨格式均包含在独立冻结全测试中通过；附加原探针复跑结果会分别保存，不依赖继续变动的UA7源。

附加原探针也已全部对冻结UA6独立重跑：`UA6-memory-budget.json`为budget10000/resident8820/inflight8820；`UA6-pause-boundaries.json`中fresh无声及缺资源前samples[0]，resume后正常推进，有声1.5秒startPaused等待超过音长后仍约1.491秒输出。`UA6-high-samplerate.json`独立192k2倍tap的880Hz能量0.05099、440Hz0.000098，随后44.1k显式1倍保持1倍。`UA6-rate-independent.json`实际1→2变调440→880、暂停期间改0.5不推进，resume后约0.3044墙秒对应0.1522谱秒；2倍三音间隔为250.000/250.000ms，含STOP的2谱秒间隔1.00177墙秒。上述未依赖UA7产品源，均只使用固定UA6原件。

### P1：4倍在开场/补队列中将多个音夹到同一sample，真实输出出现25–29ms空洞

独立Release压力探针 `UA6PressureMain.swift` / `UA6PressureControlMain.swift`，同一合法220-sample（4.989ms）44.1k正弦WAV，每6ms一音，共100。4倍后预期每1.5ms一音、每段约1.247ms。全保留post-Varispeed原始PCM在`UA6-pressure.json`及`UA6-pressure-control.json`，没有用音符计数代替声音输出。

第一轮4倍文件scheduled100但简单包络仅80；**先未按80直接报告漏音**，因为4倍将音间静音压到约0.25ms，滤波/重采样可能连接包络。随后加同波形内存路径对照和逐格能量，结果确认不是仅仪器gap阈值问题：

- 控制轮4倍文件scheduled100，包络81，100个对齐能量格只有82格峰值>0.02；PCM在0.02204→0.04782之间没有能量，连续25.78ms空洞，约17个预期音符周期。
- 同轮4倍内存PCM路径scheduled100，包络77，只有79能量格命中；0.01927→0.04807连续28.80ms空洞。说明不仅是文件句柄池，内存路径亦受影响。
- 同条件1倍/2倍纯音各100包络、100能量格，最小格峰值约0.1078、RMS约0.076，未出现>3ms异常静音。4倍有多格精确为0；不能由0.25ms滤波尾巴解释25–29ms精确空洞。

统计脚本 `analyze_ua6_pressure.py` 与结果 `UA6-pressure-analysis.json`保存每格峰值/RMS。这里的“能量格”保留第一个实际onset作为统一相位，不为每个音单独调整位置；因此会把错时也识别为失败，符合节奏正确性要求。

**源副本trace进一步确定实际排程被改写。** `UA6-Audio-trace.swift`仅插计量，不改时钟/排程；`UA6TracePressureMain.swift`再次跑4倍文件路径，原始`UA6-pressure-trace.json`保存cueTrace/nodeTrace：

1. 初次补队列时谱面elapsed为**-0.159371秒**，尚未到origin；但`playerTime(forNodeTime:lastRenderTime)`已经为**+0.010975秒**，其host时间又比当前uptime超前约18ms。队列函数因此认为开头音符过期。
2. chart=0与chart=0.006两音都被改排到同一个sample时刻**0.020975秒**（playerTime+10ms）；这不是原本两个独立时刻。
3. 随后chart elapsed仅**0.008964秒**，节点render/player cursor却已是**0.150295秒**；本该在0.138、0.144、0.150秒的多音又都被夹到**0.160295秒**。

位置：`commitPreparedChart`先`mixer.anchor/AVAudioPlayerNode.play(at:)`再`scheduleDueCues`；`scheduleDueCues:2636`用`elapsed + 0.20`，origin前elapsed为负且乘4，削掉开场预排；`queueFileChunk:1561–1602`和`enqueue:1850–1894`又用带未来render时间的playerTime判断已迟到，将多个音都强推到player+10ms。0.1墙秒的补队列在4倍跨0.4谱秒，固定0.2谱秒提前量也不足。**scheduled100并不能证明声音/节奏完整。**

最小现代修复方向：在节点尚未启动时按同一个sample0排好充足的**正墙时间**提前量，再共同host启动；开场排程不得因origin前负elapsed而接近空窗口。统一音频输出时基和谱面时基，正确处理Varispeed拉取/渲染ahead，不能把未来render cursor直接当可听的当前时间；不得把多个不同due音都夹成同sample来伪装成功。句柄临时用尽必须在真实deadline前续排，固定0.1秒重试需按倍率/剩余时间有界调节。保持generation、pause/STOP/Here及资源预算合同。主代理已交UA7，产品未被本审计修改。

### 混资源饥饿验证尚未签过4倍

每倍率的100音之外，在池满附近0.19/0.196/0.202/0.208与0.39/0.396/0.402/0.408谱秒各加独立2200Hz、20ms标记音，合计108。三个倍率都scheduled108且drops0；聚合包络因标记与压力音重叠，**未把包络总数当108个声音证明**。

对post-Varispeed PCM按2200×rate频带、已知20ms包络进行八个独立正交模板联合拟合，允许一个全局录制偏移并消除440×rate干扰。1倍八个标记系数约0.160–0.163，全部明确出声；2倍八个标记系数均>0.02，但幅度变化较大；4倍在统一时序网格只有5/8标记系数>0.02，部分接近0。完整PCM、拟合偏移/残差/系数均保存。**4倍未通过，但此混音拟合不能独立区分“永久漏掉标记”和“标记被延迟到别处”**，不报一个未经证实的确切漏音数；纯音空洞与trace已经足够确认上面的P1。

没有进行屏幕帧率后测：父代理确认CGSession锁屏=1。不开守卫、不绕过不可见窗口；上述均为音频输出tap/时钟逻辑证据，不是用户可见presentedTime或扬声器硬件回环。

额外有界4倍长BGM跨块控制：同一4分钟连续正弦源录制3.2秒、141120个44.1k输出frame，约跨12个1秒谱面流块，阈值0.02的相邻活跃sample之间没有>0.5ms的内部空洞。原始PCM在`UA6-long4.json`。这说明4倍流式长音在该负载下连续；没有以此否定独立短音负载已经复现的开场/补队列P1。

## UG3 / UW6 冻结集成媒体钟审计

只链接父代理固定的`parent-UW6-UG3-frozen/`，未读取正在变化的A7/S8/G4产品源。主要SHA-256：窗口`6344ba5a4960f8d80c84d1771100c7f40c4ac018369a0860443c34db345498e7`，BGA `3726c3972ec7103a369ddb2bcfa68d18201f56af197b4aa75b099c56afcabdb2`，谱面`181e06889fd42cd8d4c7c4313814c9af4b7f9936b618a91640dee76bd8e85ca9`，音频仍固定UA6 `8b176e8…`，完整清单见父冻结目录`SHA256.txt`。

独立`VideoClockAudit.swift`使用真实窗口控制器、Behavior、BmsSource、音频与BGA模型。键3/4的NSEvent经`previewSendKeyDown/Up`进入host实际处理链，未直接伪造引擎或视频率。自己生成24秒64×48 H264、含AAC音轨的`audit-performance/ua4-media/rate24.mp4`。控制器只用Timer采样原时钟，未显示用户窗口、未请求屏幕截图/像素/FPS，不绕过锁屏或可见性守卫。`-O`独立编译和运行退出0、stderr为空。逐100ms原始时钟结果`UW6-UG3-media-clock.json`。

### 实际媒体钟结果（不是仅看rate字段）

| 请求/场景 | 墙秒 | 媒体增量 | 总比率 | 100ms分段比率范围 | 额外seek | 最大绝对media-expected漂移 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1倍 | 1.306 | 1.302 | 0.997 | 0.967…1.000 | 0 | 0.012秒 |
| 2倍 | 1.318 | 2.570 | **1.950** | 1.949…1.952 | 0 | 0.075秒 |
| 暂停后0.5倍恢复 | 1.333 | 0.666 | 0.500 | 0.500…0.500 | 0 | 0.089秒 |
| 4倍 | 1.351 | 5.405 | 4.000 | 3.999…4.001 | 0 | 0.096秒 |
| POOR重开1倍 | 0.535 | 0.535 | 1.000 | 0.999…1.000 | 0 | 0.017秒 |
| Here第4拍且前有1秒STOP，2倍 | 0.786 | 1.572 | 2.000 | 1.999…2.000 | 0 | 0.034秒 |

各稳态段没有新open，正常两通道、POOR一个通道均`videoMuted=true`、启用音轨合计0；源媒体确有音轨。暂停改率0.5，约0.455墙秒媒体增量精确0、播放器rate均0、seek不增，恢复后实际0.5倍。Off期间改倍率，open/seek/路径解析不增长、没有附着player；POOR重开沿当前媒体秒，没有从0重播。Here含STOP的首个实际媒体时间3.069秒，符合0→4拍共2秒运动+1秒STOP偏移。

上述4倍媒体钟结果只签视频AVPlayer这条路径，不能关闭UA6短音音频排程P1。视频与音频显示同一个requested字段，也不能自动推导声画输出已对齐；没有硬件回环或最终视频像素证据。

### P2：5%按键步长被视频传输容差吞掉，engine=2而视频持续1.95倍

位置：固定BGA `applyTransport:1817–1840`，`abs(player.rate - desired) < 0.05`分支会把`lastTransportCommand`改成desired后直接返回；此后`lastTransportCommand == desired`又阻止重新发起真实传输。host键3/4的步长正好0.05，浮点舍入使1.95→2.0落入这个容差。

独立证据：engine/request都为2，但两个player实际rate均`1.9500000477`，1.318秒墙钟内媒体比率1.950，逐段1.949…1.952，零seek/open。这不是单次抽样rate字段误差，真实媒体钟也慢了2.5%。`UW6-UG3-media-clock.json → two`。短测漂移已增到75ms；更长时段会需要漂移纠正，不应把纠正seek造成的平均比率当作准确变速。

最小修复：请求倍率变化时必须发对应的真实传输命令；相同请求去重已有`lastTransportCommand`足够。若保留实际rate近似比较，容差必须明显小于0.05用户步长（例如仅浮点误差级别），不能吞掉一个完整按键变化。测试单次1→1.05、1.95→2、反向降0.05、暂停中变率恢复，以及长时无校正seek的实际媒体比率。没有要求复制原版电影是否变速的未知旧行为；现代明确同步策略应实际生效。

单步长时复证已完成：`VideoRateStepAudit.swift`固定G3/W6，起播1倍后只按一次键4，engine/videoRequest为1.05但实际player始终1。约3.8秒采样中发生一次纠偏seek，总体媒体/墙比率1.031，不能当成接近1.05而通过；排除seek跳变的100ms分段比率中位数约1.000。原始`UW6-UG3-step-stop.json → singleStep105`。这同时证明“靠seek追帧”会掩盖真实播放倍率错误。

同一独立探针的STOP实时段已验证：2倍、beat1停1谱秒期间，画面beat连续五次为1，而视频从约0.492推进到1.363媒体秒，符合墙钟连续前进；全段实际media/wall约1.99998，零额外seek。另直接切到beat60新事件触发换资源/seek后立即Off，等待0.5秒仍无player、无新open/seek，过期回调没有复活旧播放。结果`UW6-UG3-step-stop.json → stopAtBeat1/staleEventThenOff`。两个probe构建和运行均退出0，stderr为空。

## 独立最小 AVAudioEngine 队列实验：未发现80段上限，不需要逐音符克隆同一不可变buffer

为核对A7早期“排100段会丢末两段、每声部不超过80且每段复制buffer”的解释，另写**完全不链接产品源**的`MinimalEngineQueueProbe.swift`。代码只含AVAudioEngine、AVAudioPlayerNode和AVAudioUnitVarispeed及输出tap；没有LegacyPreviewAudio、timer release、谱面终点、自动stop、late-frame修正或任何UI。主线程在node尚未播放时按固定sampleTime预排全部片段，然后`play(at:未来host+0.20秒)`。共享buffer创建后不再修改；克隆组在准备阶段生成所有副本。所有buffer都保留到理论声音结束后额外0.65秒，才stop。

机器同本轮arm64/macOS，`swiftc -parse-as-library -O -swift-version 6 -target arm64-apple-macosx14.0 -framework Foundation -framework AVFoundation`编译/运行退出0，stderr为空。最初单文件编译需要补`-parse-as-library`，这是探针编译修正，不是产品错误。

同一220-frame、44.1k、440Hz、不可变PCM短音，每6ms一段：

| 倍率 | 段数 | buffer策略 | 实际PCM包络 | 对齐能量格 | 最后两段峰值 |
| ---: | ---: | --- | ---: | ---: | --- |
| 4 | 100 | 同一个buffer重复排程 | 100 | 100 | 0.12730 / 0.12730 |
| 4 | 100 | 每段独立副本 | 100 | 100 | 0.12711 / 0.12711 |
| 4 | 200 | 同一个buffer重复排程 | 200 | 200 | 0.12730 / 0.12730 |
| 4 | 200 | 每段独立副本 | 200 | 200 | 0.12715 / 0.12715 |
| 1 | 200 | 同一个buffer重复排程 | 200 | 200 | 0.12727 / 0.12727 |

各组没有>3ms内部空洞，所有对齐能量格最小峰值均约0.127。原始PCM完整保存`minimal-engine-queue.json`，分析`minimal-engine-queue-analysis.json`。记录的queue调用总耗时不是每hit真实产品开销，也没有对不同组的系统调度噪声作性能优劣结论。

这组最小实验已否定“当前平台普遍只能排<=80段”或“重复排同一个不可变AVAudioPCMBuffer必然丢末两段”的解释，**不能用该解释给产品硬码80与每hit主线程大buffer复制背书**。更可能需要继续定位本播放器的anchor、Varispeed未来pull、wall release与终点/stop时序；本最小实验本身没有证明具体哪一个产品路径是根因。A7尚在修改，未读取混合快照，也不预先报告A7存在缺陷。A7稳定后应检查克隆成本、所有权必要性、在途总量和最后两段真实PCM，不能用“引擎限制”替代证据。

## UG4 稳定媒体钟复查：关闭0.05按键被吞P2

冻结`UG4-PreviewBGAView.swift` SHA-256 `360b345d9327a3db3272ba7d52daae81e1b972be7878cbe422fbba6bcece0723`、测试`bdf4380c5eaacded742fea294e501fd24397e64e7411293f4788d611a9257ca4`，与UG4报告一致。只替换前述W6固定模型组合中的BGA，其余仍用`parent-UW6-UG3-frozen`，没有取动态A7。自己的两个集成探针独立重编并运行退出0、stderr空。

`UG4VideoRateStepAudit.swift`经host真实键4将1变为1.05，长约3.8秒实测媒体/墙比率**1.050010**，100ms分段1.049551…1.050328，实际player为1.04999995，零纠正seek。原先固定1倍+seek补追的现象消失；结果`UW6-UG4-step-stop.json`。

`UG4VideoClockAudit.swift`继续按实际host键3/4、暂停与显示模式链复跑，结果`UW6-UG4-media-clock.json`：

| 场景 | 实际media/wall比率 | 100ms分段范围 | 额外seek/open/transport |
| --- | ---: | --- | --- |
| 1倍 | 0.99998 | 0.99968…1.00022 | 0 / 0 / 0 |
| host键升到2倍 | **2.00000** | 1.99944…2.00036 | 0 / 0 / 0 |
| 暂停改0.5后恢复 | 0.49998 | 0.49981…0.50016 | 0 / 0 / 0 |
| host键升到4倍 | 3.99997 | 3.99878…4.00111 | 0 / 0 / 0 |
| POOR重开1倍 | 0.99996 | 0.99895…1.00079 | 0 / 0 / 0 |
| Here含STOP偏移2倍 | 1.99967 | 1.99744…2.00036 | 0 / 0 / 0 |

同值`setPlaybackRate`加`setPlayback`连续500次，额外transport/open/seek全部0，两个player仍2倍；相同请求去重保留。暂停改率的媒体增量0、player均0，请求0.5保留；Off改率和旧异步回调均未新开视频。所有附着player的mute真、源audioTrackCount1、enabledAudioTrackCount0（正常base+layer两个player，POOR一个），未因变率恢复声音。

这足以关闭G3的0.05步长/伪变速P2。不能把它当作音频4倍排程P1通过，也没有视频最终像素、屏幕FPS或硬件声画同步证据。其余源裁切/视觉图集与A7验证各自继续。

## A8进行中文件租约诊断（非最终验收）

受主代理明确委托，只固定一次进行中音频快照作有界诊断：`UA8-diagnostic-LegacyPreviewAudio.swift` SHA-256 `1fdde171c1fabae6cb313c78a254bf6badc0c15e2666b29dc3d6ea6159c9ee41`，122835字节。该快照有debug输出、实现者仍修改，不能作为最终A8失败或通过结论。

直接缺口在`trigger:1404–1408`：首次claim把cache.files唯一句柄转进fileLeases；后续看到entry.files空，立即waiting，尚未进入本可复用非重叠租约的claimFile。固定快照初跑1倍scheduled100但只出第一个burst、live99均late；4倍scheduled94、drop6、同样只出第一burst。此结果仅帮助定位，不对未完成A8发正式缺陷。

在审计副本`UA8-audit-guardfix.swift`仅将该判断改为“entry.files空且fileLeases桶也空才waiting”，不修改live产品。独立原100音、预算1、同文件220-frame/6ms间隔，结果1倍100/100、4倍100/100，drops/steals0、一个voice、late0。1倍预排34其余66 live；4倍开场100全部预排。证据`UA8-guardfix-pressure.json`、`UA8-guardfix.err`。检查时live源已自行做同一guard修复，故不重复要求实现者改旧问题。

租约本身用每token的[start,end)区间判重叠，真实声学非重叠才共享句柄；`scheduleSegment`传显式startingFrame，源码无直接framePosition写入。另作不链接产品的`MinimalEngineFileQueueProbe.swift`：一份AVAudioFile、节点停止时预排100/200段后共同future host启动，4倍均100/100与200/200，1倍200/200。0.65秒尾部保留，没有观察到共享句柄顺序排程冲突。原始PCM`minimal-engine-file-queue.json`；SDK头亦明确旧completionHandler是dataConsumed，可能在渲染前回调，不能把它当实际声音播放完。

这支持“资源存在性、闲置句柄和可复用租约分开”，没有证据支持非重叠事件每颗新开文件。仍需A8稳定源验证真重叠独立句柄、同file跨node、pause/replay/generation与长流两块在途；本诊断未操作用户窗口、未改产品、未跑FPS。

## Varispeed多节点独立时基实验

详见 `audit-performance/two-node-origin/report.md`及完整三组PCM/host/sample JSON。不链接产品源。1倍同频脉冲single/dual间隔均190ms；4倍single约47.5ms，但dual三轮为58.912/55.669/55.669ms。同样440Hz波形排除了不同频率group delay。共同play(at:host)并不能建立相同source sample0。固定绝对host的lead扫描还显示：lead增加200ms，1倍输出推迟200ms、2倍约101ms、4倍约51ms；不是固定滤波延迟。未据此建议乘rate或magic offset。原始playerTime/nodeTime/host和pre/post tap均保存，不以第一声归零自证。单节点统一source sample轴的相对时间在这些control正确；多node需有可验证映射，或考虑统一格式单source混音后再Varispeed。仍未签A8最终通过。


## UA9P2稳定原型独立审计

完整报告：`audit-performance/ua9p2-review.md`，冻结源与自己的输出在`ua9p2-frozen/`。普通harness、原TSan与81项PCM probe独立重编复跑0，但新增命令组合确定性复现pause→rate丢暂停、seek2→rate继续chart10；新增并发clock-reader的TSan明确报告copy_clocks831与publish_span501的数据竞争。两个P1必须修复，原harness读clock在join后，未覆盖后者。自己的设备格式44100Hz/mainMixer输出tap控制仍测得1倍190/200ms、4倍47.506/50ms，支持单source方向，不等于产品通过。生命周期退休、Swift target未同步写、线性插值alias及worker全曲扫描均在独立报告列为集成门槛或原型边界。没有修改产品/原型，没有FPS证据。


## UA9P4 publication P2关闭

详见`audit-performance/ua9p4-review.md`。固定C `214d51b10c456e4ada600c04e4b7498dd7f17a255542c1917e432c1baa62f9cf`，desired/ack/slot所有sequence及payload访问均seq_cst，单写者且一次读取不发生sequence ABA时C11总序证明充分。自己的25命令pair全过；并发clock读者100000回调、91808日志覆盖，TSan一次退出0且stderr空。P3到P4仅内存序/注释差异，本轮未重复PCM。关闭原publication P2，不扩大到产品退休/重采样/67CTest或FPS；32位desired/ack sequence的2^31次发布ABA前提在报告中明确。
