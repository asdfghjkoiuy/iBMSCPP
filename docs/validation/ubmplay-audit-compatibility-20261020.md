# uBMplay 兼容性与像素证据独立审计（2026-10-20）

结论：所测W5真实双时钟、G2/G5静图裁切、S8有效长音恢复、S9叠层与排序，以及G5真实视频几何/媒体时钟均通过本报告对应独立用例。Here中段保持音频和长音体、无holding爆炸，单列策略边界。视频图层最终像素仍缺可见环境证据；最近邻缩放边界tie不冒充严格像素相等。各节保留冻结SHA，局部通过不等于全原版行为一致；用户要求以原版作参照并现代改进。

审计材料在 `out/validation/ubmplay-parity-20261020/audit-compatibility/`。源码仍在变化，初轮 SHA 在 `initial-source-sha256.json`；最终 GPU 复验和最终 SHA 尚待追加。

## 来源与证据分级

- **A：直接静态证据。** 官方 1.5.2 ZIP SHA-256 为 `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada`；exe MD5 为 `44e3d8aa24e2eb19d1e426fde4086d03`，imagebase `0x400000`，当前 IDA 识别 429 个函数。地址和反汇编只说明被读到的路径，不代表 429 个函数完整翻译。自己的只读 IDA 摘录附原指令字节，见 `ida-audit-snippets.json`。
- **B：反编译候选与推断。** `uq-loadbmsline.c`、`sprites-candidate.c` 明示 `bad sp value at call ... output may be wrong`；调用实参、VB Currency 单位、栈布局、虚表方法角色必须由汇编/字节复核。不能从文件名 `sprites-candidate` 推出函数真名。rank 到档名、效果时间/矩形等尚有未追链部分。
- **C：作者说明、官方截图、资源像素。** 原 readme 明确这是自动演奏 viewer，不能人工游玩；1.4.5 官方截图 593×281 含 Windows 装饰，不能当成 1.5.2 的逐帧运行 oracle。1.5.2 图集则可作为本机静态背景、切片的像素 oracle，原像素/尺寸/SHA 见 `asset-evidence.json`。
- **D：尚无证据。** 未运行原版同谱同显示环境的计时、未穷尽随机/长音/seek 状态机、未逐帧匹配全部动画；不得写“完整源码已恢复”“所有逻辑兼容”“性能绝对超过原版”。

官方来源：[页面](http://ucn.tokonats.net/software/ubmplay/)、[1.4.5 截图](http://ucn.tokonats.net/image/ubmplay_145.png)。皮肤由 AOiRO_Manbow 制作，程序作者 Hayana。原 readme 的再分发条款不是独立提取 PNG 的开放授权。本次仅从本机完整原版目录读取；未另行发布 PNG，未联系作者。

## 已复现问题与最小修复边界

| ID / 优先级 | 触发条件与实际影响 | 证据 | 最小修复范围 |
| --- | --- | --- | --- |
| V1 / P1 | `PreviewUbmStyle.loadAtlas` 读入任何原图。返回 RGBA 与 PNG 上下翻转；skin00 共 84,736 像素中 25,498 不同，与垂直翻转 oracle 0 差；font 9,030 像素中 4,312 不同，与垂直翻转 0 差。以顶部原点切图导致读到错误区域；实际 `BMS Info` 文本乱码/倒字 | 真实 Swift `StyleProbe.swift`，`style-results.txt`，`style-decode-comparison.json`，`font-audit-contact.png`。使用真实 Style 源码，`StyleTypes.swift` 仅提供值类型，未替换解码逻辑 | `PreviewUbmStyle.swift` 的 CGContext 朝向与所有使用者统一；CPU 数组采用 top-left，或完整变换全部切片与采样。字体与 GPU 都必须复验；不要只靠倒置背景 UV 掩盖字体 |
| L1 / P1 | 原生 BMS 文档含 `#RANDOM 1 / #IF 1`。`BmsDocument.chart()` 直接返回空事件；`MainWindowController.previewAudioContext()` 消费此快照，因此直接 BMS 预览不按原版分支播放。BMSON 导入有另一条展开路径，不能概括为整个程序无随机支持 | `parser-probe.cpp` / `parser-results.txt`: spaced_random `raw_events=0`、`raw_conditionals=1`；`make_chart(conditions)` 和主窗快照调用链 | 独立预览用随机已展开快照及资源定义，不能破坏无损编辑文档。需保留种子/重载与 Home 的差别；产品写入范围另行拆给实现者 |
| L2 / P1 | 经已有 `apply_bms_random` 导入 `#RANDOM2`、`#IF1`、`#IF2`。collect maxima 为 0，两个互斥分支都留下，`import_events=2`。原版 1.5.2 支持无空格 RANDOM/IF | 同上 `compact_two_branches`；readme 1.5.2；UQ 的 `LoadBMSLine 0x41C340` 前缀递归路径 | `bms_import_random.cpp` 命令 token 归一化与对应验证。保持原版只给 RANDOM/IF 无空格兼容，不能自动推广为所有命令 |
| L3 / P2 | `#RONDAM 1 / #IF 1` 本应留下音符，现有 import_maxima=0 / import_events=0；非匹配 IF 后用 `#END IF`，本应结束跳过并留下其后的音符，现为0 | `parser-results.txt` 的 rondam_alias / end_if_alias；readme 1.3.12、1.5.0；UQ 静态确认同分支/递归 | 同一 parser 命令兼容层；各增加最小行为 fixture |
| D1 / P2 文档 | 原分析写 `DrawText` 按 587−文字长度居中，遗漏像素宽度乘8；若按此实施会错位 | 0x414AEC LenBstr，0x414AF4 `imul ecx,8`，0x414AFD `mov eax,587`，0x414B02 sub，0x414B0F sar；`ida-audit-snippets.json` | 修正文档为 `(587 - 8*字符数)/2`。这不是要求对非 ASCII fallback 也强行8像素 |
| D2 / P2 文档 | rank3 阈值 40→80→50→60 不单调。描述成“从窄到宽”会诱发实现者排序阈值或伪造普通单调窗口，改变原版分支 | 0x419FCD/0x41A001/0x41A037/0x41A060 四次顺序 fcomp，每次超窗才继续。按报告系数 rank3，80内已被前档吸收，后50/60档不可达 | 保留汇编顺序；说明数值不单调与部分代码不可达。UQ 已确认 `#RANK` 写 0x42E48C，UR 的“未追到写入”现可用交叉证据升级；档名仍不等于已证明 |

字体切片补查：原 font 的三行是 y1..11、y12..22、y23..33（外框 y0/y34），当前 lowercase 取 y25 高9会截掉升部顶部两行。`font-audit-contact.png` 第一行是原图 nearest 放大，下三行是实际 `textImage` 输出。当前 `max(R,G,B)` 后 tint 会把青蓝渐变改成统一 cyan；字体颜色的原版着色链尚待验证，不能把这种换色直接算成逐像素相等。

## 静态像素基准与方向探针

真实运行 `skinDirectory()`，在未设环境变量时正确定位本仓库 `out/reference/ubmplay-1.5.2/ubmplay/image`。`#filePath` 向上四级是正确路径；该结论限于此次以实际路径编译的本机运行，不等于发布包拥有资源。

| 资源 | 原尺寸 | SHA-256 |
| --- | --- | --- |
| skin00 | 331×256 | bcb541fbac571005a79c6f09f7eadb39be3c00638a6bf62854f5d14a8a6cf3ad |
| skin01 | 137×221 | e09e374d05ade3afe1124e92dbf5a2c99f6a2670c5fd9652ac925eb3f30fe362 |
| skin02 | 160×244 | a17eabb3908a41745a80ef279b96a5802ece9c9292a1b0af080b6c3af4cf438b |
| skin03 | 578×228 | ea525c6232d368c70cdf624c865181d9dc2ed7a0a62970eaa014ec4120ed9cc5 |
| font | 258×35 | 6011eb5b8e9ea63c8888b2d6adfdc14e54759407e736d0053c4060bd97822d49 |

skin00 主车道色为 `(57,56,57)` 与黑；绿判定渐变在 y219..223，键盘在 y224..255。这一位置也得到原版 0x41115C 的 h5、0x411163 的 y219 与 0x411179 矩形调用支持。底部键盘 y224/h32 的指令在原 `focus-disasm.txt` 0x411378..0x4113B1。331 宽原生未覆盖像素应该 RGBA 严格相等，无颜色容差；其它大小则检查 nearest 对应与 letterbox，不拿线性混色当可接受差异。

sprites 不能把整幅分隔色画出。skin01/02 的纯绿、skin03/font 的粉色 `(199,80,127)` 实际不带 PNG alpha；需在切图/上传前按原版色键策略处理。skin00 的绿色判定线必须保留，不能全局把绿色透明。背景不需要 alpha 混合；sprite 半透明应明确采用预乘还是直通 alpha，并让 shader 与 blend 一致。CPU 解码正确本身还不能证明 GPU 采样、顶点坐标、高 DPI 都正确。

## 待覆盖行为矩阵

“已具备现代实现”只指代码可见，不表示原版兼容已验收。原程序只有自动演奏，判定动画不是人工判定系统。

| 功能 / 精确用例 | 原版 oracle 与强度 | 现代状态 / 下一项必需证据 |
| --- | --- | --- |
| parse 基本头、base36 WAV/BMP/BPM/STOP 01..ZZ | readme；UQ 0x41CDB0、0x421F30/0x422070 | 已有核心 parse/timing；需原版同 token 边界、重复定义、空行/空格、CP932、Val 宽容性对照，不能仅测试标准样本 |
| random 空格/无空格/别名/外层不活动的内层匹配/嵌套退出 | readme 1.5.0..1.5.2；UQ 0x41C340 栈+4/+6 | L2/L3 与 N1 外层不活动用例已修复；L1 集成在进行；需固定随机值的两条产品入口矩阵与重载重新掷骰 |
| format BMS/BME/BML/PMS、5/7/9/10/14/OCT-FP、PLAYER 1/2/3 | readme；扩展名静态字符串；format自动判定算法未完整 | BMS 默认7/14、BMSON mode 映射是另一套；PMS 9键在原皮肤八槽的显示待验证，不能把未放置列静默丢弃 |
| LNOBJ、5x/6x、LNTYPE1/2、跨小节、同时混用、seek跨长音 | readme明确LNTYPE1/2；UQ 0x41E6D0已见LNOBJ链接；exe没有LNTYPE字符串只说明没有文本标签 | 现代已有配对/视觉长音；原版通道状态机与完整sprite还未对应，必须证明显示/声音起点、尾端不重播 |
| BPM03/08、STOP09 同拍、重复BPM/STOP/mine不减Notes | readme1.5.1；UR CountPlay 时间式部分 | 有现代 timing 与播放映射；需原版同拍顺序、实际音频/视觉时钟对照；不要因现代数学自洽即宣称兼容 |
| seek Up/Down ±1、Pg ±4、Home0、End末小节、边界夹紧、按住加速 | UQ 0x4201E0夹Word范围、0x4173A0按键已确认 | 当前只有 Play Here 从当前指针起播，不能代替原版运行中seek；需重建跨起点长音/仍应响的声音/当前BGA |
| pause0、pause中seek不出声、resume同一位置/媒体 | readme1.5.0；UQ 0x418930 0x0A→0x0B，BGA虚表+0x38 | 现代 audio 暂未见 pause/resume API，Stop不是Pause；不能从BGA有player.pause推出完整暂停功能 |
| autoplay、GREAT/档名/combo/MAXCOMBO、mine | readme viewer；UR 0x419E10四窗五档、非单调例外 | 现代PreviewVisualNote只有lane/start/end，丢失mine类别/判定属性；统一GREAT是视觉近似。需动画/计数事件的真实规则 |
| effect6 四态0/1/3/7、judgment/bomb/beam位、寿命与sprite帧 | readme；UR 0x417928、0x415EC6 bit1 confirmed | 正在实现atlas；半拍寿命是现代选择，尚无原版同一寿命证据；需UR2源矩形与真实GPU各帧匹配 |
| BGA5 OFF/base/layer/normal/always-miss、OFF不读、BMP00/#BGA裁切/越界、threshold0..255、alpha不支持 | readme；UQ #BGA字串、UR 0..4计数；DLL阈值实现未读 | 现代base/layer/poor模型有基础，但没有完整BGA状态/裁切定义，默认PNG alpha行为与readme不一致；需行为probe，不能把poor正常隐藏当五态全覆盖 |
| 视频居中、长边256、STOP继续视频、pause冻结、seek媒体偏移 | readme；UR 0x416AF0 256常量 | 现代有AVPlayer时钟；需合成不同纵横比媒体与原版oracle，不要求复用DirectShow实现 |
| scratch8 L/R→R/R→L/L→R/L | readme；UR 0x42E55C两bit坐标重建、标签顺序未全钉死 | Style目前固定1P左/2P右，仅覆盖默认；需四种布局与音符、键盘、光束同变 |
| HiSpeed1/2，0.25下限/0.25步进，双按向1，repeat加速 | readme；UR 0x41770C..0x4177F6 | 当前pixelsPerBeat滑条16..240不能自动等同原版倍率；需定义1.00对应基准、原版步进和按住行为 |
| RealHS3/4，调用ChangeFrequency，动态上限 | readme与二进制有差异：UR整数步5、基准100、下限25，与说明0.25不要混合 | 现代未见对应音频频率/时间倍率；需先确认音频/视觉/判窗共同缩放语义 |
| keyboard5/6/7/8/9/0/F1/F2 + 小键盘 + wheel + Space0.5s | readme；UR/UQ仅部分逐指令落实 | 现代窗口未见这些事件处理。需置顶、四档信息、五档声音、AutoSeparate、reload、滚轮seek逐项落地 |
| PATH_WAV、VOLWAV、重复资源缓存、ForceReload/-FR | readme；UQ #PATH_WAV写0x42E468，VOLWAV*0.01 | 现代resolveAudioURL只拼谱面目录、playChart只读取WAV表；需带外部目录、缺文件、音量、同名替换的合成fixture；不能直接视为兼容 |
| CLI -N/-P/-S/-Q/-SP/-FR、编辑器调用、重放自动退出 | readme；UR/UQ命令分支未完整 | 当前内置预览UI并未提供兼容CLI；如“所有逻辑”含此项，需明确定义产品入口并验证 |

## 运行方法与验收边界

`parser-probe.cpp` 用当前核心源码独立编译，产生 `parser-results.txt`。`StyleProbe.swift` 用真实 `PreviewUbmStyle.swift` 加类型声明独立编译；它验证资源查找、CPU解码、实际字体栅格输出，**没有冒充GPU读回**。PNG 与 RGBA 用 Pillow 独立比较，全部差异与垂直翻转零差均已实测。

尚待稳定实现后复验：真实Metal native331×256背景未覆盖区逐像素、整数2x/3x nearest无混色、1P左/2P右及键盘/中央量条、五像素细note、GREAT/combo/bomb/beam、字体ASCII正确与中文可见、587×256客户区/高DPI、alpha与色键。性能由另一份真实presentedTime诊断报告负责，不能由本CPU解码probe推导性能或流畅度。


## UC / UB 独立复审

修复源码 SHA 在 `post-UC-UB-source-sha256.json`。没有覆盖初轮日志；复验产物单独使用 `post-UC`、`extended` 后缀。

| 项 | 独立运行结果 | 结论 |
| --- | --- | --- |
| L2 无空格两分支 | 原 `parser-probe.cpp` 重编译；`compact_two_branches` 的 maxima 数量由0到1，留下事件由2到1，只留 `#00011:01` | 所列用例已修复，证据 `parser-results-post-UC.txt` |
| L3 RONDAM / END IF | 前者正确留下 `#00011:01`，后者结束跳过并留下 `#00012:02`，均1事件 | 所列用例已修复 |
| L1 原生 BMS 条件快照 | 原探针所有含条件原文本仍 `raw_events=0`；这是 BmsDocument 的既定边界，不是 UC 宣称修复范围 | 等待预览独立展开集成，不能据 UC 结果宣称已通产品 |
| N1 外层不活动、内层匹配 | `parser-extended-probe.cpp` 的 `nested_parent_inactive` 固定值1：外层 `#IF 2`，内层 `#RANDOM 1 / #IF 1`；现代导入仍留下1事件。UQ R7 原版活动标记抄父帧应无事件 | P1，原版随机栈仍未兼容；这是已知未完成范围，非把 UC 有界归一化误判失败。最小修复边界：预览专用原版条件栈或明确原随机状态机；不要破坏已有 BmsONE 导入扩展语义 |
| UB 作者测试 | 默认 Swift 5 模式独立编译运行 `PreviewUbmBehaviorTests passed` | 只证明模型用例，非窗口/音频已集成 |
| UB Swift 6 编译 | 使用正式产品的 `-swift-version 6`，`PreviewUbmBehavior.swift:572` 的 `static let none` 报非 Sendable `PreviewUbmAction` 不满足并发安全；见 `behavior-compile.log` | P1 集成阻塞。最小修复：让适用的纯值 Action/Seek/Playback 等值类型明确 Sendable，或提供一致 actor 契约；不要关闭全项目并发检查 |

UB 只读核对：scratchRaw 的 0 L/R、1 R/R、2 L/L、3 R/L 与 UR2 已确认 SkinType 四态一致；旧 UB 报告“只来自 readme、未接上”的置信度已落后，可引用 UR2 升级，但模型字段尚未驱动布局。RealHS 单键步5、先看25/动态上限再变更，双键朝100，不按上限夹紧；源码与 UR/UB 所列指令规则一致，没有把它改成 readme 的0.25。`realHSCeiling=100` 仍只是占位，时钟/音频 frequency/判窗尚未接入。repeat 的50/1.3和最小1ms是模型推断/保护，未经原版辅助函数确认，不应标为完整原版时序。

US2 此时仍在修复皮肤、字体和 blend，尚未进行最终 GPU 验收。最终比较必须用原始 PNG 的独立 Pillow 解码作为 oracle，不能只拿 `PreviewUbmStyle.loadAtlas` 的输出与同源 GPU 纹理互相比较。


## UC2 / UB2 关闭项复验

下表是当前结论；前面的失败记录是修复前证据，不代表问题仍存在。冻结 SHA：`post-UC2-UB2-source-sha256.json`。

| 状态 | 项 | 独立证据与范围 |
| --- | --- | --- |
| 已关闭 | L2 紧凑随机命令两分支同时留下 | 重编并运行原 `parser-extended-probe.cpp`；`compact_two_branches` maxima数量1、events1，仅 `#00011`。`parser-results-post-UC2.txt` |
| 已关闭 | L3 RONDAM / END IF | 同一探针分别 events1，别名正确选择，END IF后正确恢复 |
| 已关闭 | N1 外层不活动的内层匹配漏音符 | 原 `nested_parent_inactive` 由 post-UC 的1事件变成 post-UC2 的0事件；没有改审计case迎合结果。不能由此推导全部原版随机栈语义已穷尽 |
| 已关闭 | UB Swift 6 编译阻塞 | 使用 `-swift-version 6 -warnings-as-errors -parse-as-library` 编译真实模型与产品测试，退出0；运行 `PreviewUbmBehaviorTests passed`。见 `behavior-post-UB2-compile.log` / `behavior-post-UB2-results.txt` |
| 仍待验证 | L1 产品原生BMS预览 | 原核心探针 raw_events仍0，这是保留的无损编辑边界。UM2 正在接预览快照，不能以核心raw_events0单独判新集成失败，也不能先宣布产品修复 |
| 仍待验证 | V1 皮肤方向、字体切片/颜色、alpha、最终GPU像素 | US2仍在实施；最终稳定后才独立复查。原PNG/Pillow仍是oracle |
| 仍待集成与验证 | UB动作模型接窗口、音频、BGA、布局、快捷键 | Sendable只解决编译；目前未把纯状态测试误报成产品已支持 |
| 仍未覆盖完整性 | 其余行为矩阵 / 性能超原版 | 原版完整随机栈、音频seek、RealHS ceiling、全部format与动画等仍须对应证据；没有相同环境原版性能对照 |


## US2 冻结版：独立 PNG → 实际 Metal 像素复验

这次使用冻结源码编译，不和 US2 编辑竞争。快照在 `audit-compatibility/post-US2-source/`，完整 SHA 在其中 `sha256.json`：Style `a266523541c5cdad146c2122df677410e430051f53bba354791e3d97e522929f`，renderer `2028159cd1ffd6b73d6718c312f9331e91df2b361b559b3ced20d2192fa6ad03`。快照不在原源码目录，因此运行时显式设置 `IBMS_UBM_SKIN_DIR` 指向原完整包 image 目录；没有修改产品资源查找函数。

`GPUProbe.swift` 和 `post-US2/SpriteProbe.swift` 调用真实 renderer `renderMetalReadback()`，各帧报告 `usedMetal=true`、status ready、failure nil，保存原始 BGRA（保留每行 stride）后由 Pillow 转 RGBA。oracle 则由 Pillow **直接解码官方原始 PNG**，不使用产品 `loadAtlas` 的结果作 GPU oracle。此证据是离屏真实 GPU 读回，不能代替窗口 presentedTime、截图、Retina窗口合成或整个587客户区验证。

| 已通过项目 | 独立检查范围与结果 |
| --- | --- |
| V1 五图CPU方向 | skin00/01/02/03/font 全部 RGBA 对原PNG零差，原上下翻转关闭。`post-US2/cpu-decode-comparison.json` |
| native背景 | 331×256，实际新增guide仅覆盖y27/y123两行，共662像素。其余84,074像素严格RGBA零差，含中央量条、绿判定线、底部键盘；没有任意扩大mask |
| nearest 2x | 662×512，按原图nearest得到独立oracle。排除实际guide覆盖2,648像素，其余336,296像素零差 |
| nearest 3x | 993×768，排除实际guide覆盖5,958像素，其余756,666像素零差。没有线性混色。以上见 `gpu-background-exact-coverage.json` |
| short notes | scratch32×5、white18×5、blue15×5各片分别160/90/75像素零差；目标x1/34/53、y118，源x104/69/88、y1。原skin01独立比对 |
| GREAT/combo | 稳定GREAT源(9,106,81,14)目标(27,161)，394个非色键ink零差；combo3 86 ink零差。没有把透明底色当成不该覆盖的像素 |
| 1P键帽光束 | scratch/white/blue 624/260/240 ink全部零差 |
| 2P前两键 | 21/22相应260/240 ink零差 |
| long-note爆炸 | 长音头第一帧skin03下排64方块，252 ink零差；没有据此声称短音第一档未确认的爆炸行也完成 |
| halfalpha | skin01源(36,11)=(60,0,0,255)，黑底50%实际GPU=(30,0,0,255)，避免平方暗到15；原alpha混用疑点关闭 |
| font小写 | 按font原PNG y23..33独立构造26个8×11字形，黑/粉色透明，输出26×8×12；全部2,496 RGBA像素零差，升部和渐变已恢复。中文真实输出有墨迹；视觉见 `post-US2/font-audit-contact.png` |

动态精灵结果见 `post-US2/sprite-comparison.json`，BGRA、PNG、probe和独立比较脚本均保留。背景两行guide是产品有意覆盖的现代辅助线，排除它们只支持“未覆盖区域相等”，不支持“原版整帧无差异”。

### 当前新增、尚未关闭的可证差异

| ID / 优先级 | 触发条件、影响、证据 | 最小修复范围 |
| --- | --- | --- |
| V2 / P2 | 默认双人SkinType0中，2P的23/24/25/28/29键帽光束沿用1P附加量，这是UR2已确认的原版特例。当前renderer用 `column.midX <165` 一律按2P右scratch选择白+2/蓝+1，比原版白+3/蓝+2向左1px。独立GPU原skin01比较：23/25/29各139 ink差，24/28各112 ink差；把oracle左移1px则这五键全部零差。21/22没有差异。见 `cap2-one-pixel-offset-confirmation.json` 与 `sprite-comparison.json` | renderer键帽capX判定需保留lane/channel或键序；不能仅凭该列在画面左右。沿用UR2特例，别移动整个2P车道或音符 |
| V3 / P2 | Style用 `originalFontColor` 的确保留源RGB，但真实 `PreviewUbmInfoView.swift:11/34` 仍传纯cyan(0,1,1,1)。用同一真实Style按实际调用色栅格26小写：2,496像素中984不同，首ink原(112,186,254,255)变(0,255,255,254)。因此Style原色单测通过不代表实际信息层逐像素 | InfoView颜色调用改成Style原色契约，并复查实际Info栅格。证据 `font-info-tint-comparison.json`、`info-tint/text-lower.png` |
| B2 / P2 | UR3现在有明确原版LoadConfig `0x40F74F` 给RealHS ceiling初值200；UB2仍默认100占位。这使默认键4从RealHS100直接被上限挡住，当前模型尚未集成到产品 | 模型初值改200，并验证默认加到105；动态上限仍需按UR3已确认的sound对象返回值计算。不要用音符数或采样率猜尚未命名的max |

D1/D2分析文档错误已由 UR3 追加更正关闭，旧失败文字保留作历史；rank3不可达档位、rank2第三档不可达和8像素居中都已明确。V1/字体切片/halfalpha在本冻结版关闭；V2/V3/B2、窗口组合及未覆盖逻辑矩阵仍开着。爆炸现用半拍age驱动，原版UR2是20/120时钟单位；没有原单位和动画生存状态对齐前，不能声称动画时序已经还原。


## US4 最终冻结版复验与当前关闭表

本节覆盖前面历史状态，不把早期失败当成仍存在。源码冻结于 `audit-compatibility/post-US4-source/sha256.json`；Style `120a54b8a35c7b02fa63ef36866674766dee764e9c46b27f31bca20f477ffbc8`，renderer `823355eca83eb2e68819a2a99975c3bbf8cbac218d81611cbfa2ba18beb666c7`。本轮GPU probe编译使用本轮冻结音频源，没有改渲染函数。所有probe/原始BGRA/PNG/独立Python比较均在 `post-US4/`。

### 本轮真实 GPU 与独立原图 oracle

- `AppearanceProbe.swift` 对4态分别生成无音符背景、16条全宽短音、16路同时命中、effect raw0..7和autoSeparate=false的packed帧。原PNG用Pillow直接解码，四态背景oracle由原图左块x0..157、右块x173..330按UR2目标表合成。实际两条guide覆盖y27/y123，精确排除662像素，**每态剩余84,074像素零差**，包括键盘和绿色判定线。2倍336,296、3倍756,666个未覆盖像素也继续零差。
- 四态每态16条note全片、16路顶部亮条取样片与所有键帽ink均零差；坐标oracle是UR2已确认的通道表。V2原来2P五键的一像素偏移关闭，旧SpriteProbe在US3也已全0通过。见 `appearance-comparison.json`。
- autoSeparate=false时的331子视图现在固定packed种子0/173；16条note（含2P）均按原skin01全片零差，原S3把2P移到429裁掉的问题关闭。**这只证明331 packed子视图**，不证明587宿主的separate布局已完成。
- effect bit0/1/2在实际GPU里分别改变判定字/长音爆炸/键帽。对每种其它bit组合逐对切换：判定区均373像素改变；爆炸区131；键帽区260，已有爆炸叠底时248。关闭对应bit后没有该层，车道亮条仍在。见 `effect-bit-toggle-comparison.json`；不能把“关闭键帽”误当关闭车道亮条。
- `ClockProbe.swift` 设真实timing BPM120、拍4 STOP两秒，以固定beat4、elapsed2.000/2.050/2.051/2.060/2.100/2.120/2.200/3.079/3.080/3.500读回。未来蓝音符的15×5切片全部等于**同一原skin01帧0**。同拍BPM60/120又都等于帧2，证明不再按每秒48替代。不是只比较helper返回值。
- 同一STOP case中，scratch亮条在50ms还是原skin01 `(60,0,0)`，51ms开始与背景黑一致；GREAT在1080ms前逐次匹配全局毫秒相位的原skin02切片，1080/1500ms回到背景。长音爆炸按20ms/6帧继续匹配原skin03，下排长音槽200/1500ms仍有属于**原版长音不在120ms清除的例外**，没有误断言所有爆炸都120ms消失。爆炸oracle只排除了另一条scratch键帽实际覆盖的区域。
- 暂停同beat/elapsed两次读回整幅RGBA零差，playing切换但相同时钟的整幅GPU像素也零差。这证明视图不会用独立wall-clock偷偷推进；播放器暂停是否把共享elapsed冻结仍需窗口/音频集成验证。
- `setBeamVertexAlpha(0.5)`的实际GPU `(1,10)`再得`(30,0,0,255)`，独立原skin01源是`(60,0,0,255)`，不是25%暗度。`half-alpha-comparison.json`。产品正常光束现在alpha1并在毫秒寿命边界关闭，不把这次诊断半透明当原版淡出规则。

时钟源补做了只读IDA小段复核，`post-US4/ida-clock-boundary.json` 留原字节：`0x415AB1` 取42E100减光束戳、`0x415ABE cmp 50`、`0x415AC1 jle`保留，超出才清字；`0x42C8DA call 0x404F00` 后减对象+34h基准。完整timeGetTime描述符与两只钟分工仍依据UT原报告，不扩展为已经恢复所有计时逻辑。

### 当前问题状态

| 状态 | 项 | 证据与保留边界 |
| --- | --- | --- |
| 已关闭 | V1 CPU上下翻转、font切片 | post-US2五图CPU对PNG全0差；本轮GPU背景继续0差 |
| 已关闭 | V2 2P键帽一像素偏移 | post-US3旧probe全0；本轮四态全通道实际GPU0差 |
| 已关闭 | V3 实际Info调用纯cyan | 冻结当前真实InfoView，实例化并调用`setText`，导出`sourceImage`；26小写2,496RGBA像素对原font独立拼字oracle零差。见 `info-comparison.json`。只验证实际栅格源，未冒充窗口合成图 |
| 已关闭 | B2 ceiling初值100 | UB3真实模型+测试用Swift6严格并发/warnings-as-errors独立运行通过；默认200、键4到105。动态上限的底层sound字段仍未命名，不等于变频完整 |
| 已关闭 | D1/D2分析错误 | UR3文档已追加乘8、原比较顺序和不可达档说明 |
| 已关闭 | L2/L3/N1所列随机case | 原审计探针post-UC2继续0/1事件正确；不泛化为全部原版随机运行库等价 |
| helper验证通过，集成仍待 | L1及PATH_WAV | 本轮按CMake列出的真实Swift源重新编译`PreviewBmsSourceTests`，链接现有原桥/core静态库，全部通过；命令与所有源码/库SHA在`source-test-command.json` / `source-test-sha256.json`。测试涵盖分支WAV/BPM/音符同源、缓存与reload、无损原字节、相对/绝对PATH_WAV和BGA不改道。但该测试不调用MainWindow，不能单靠它关闭整条previewAudioContext路径 |
| 仍待 | 完整587宿主、Retina、separate与F2 | 只读IDA已确认packed条件为`!autoSeparate || PLAYER==3`，见post-US3/ida-layout-f2.json。S4视图只消费packed，宿主必须安排15/429和中间BGA，不能因子视图通过声称完整原版布局通过 |
| 仍未完整 | 原动画与行为矩阵 | GREAT前90ms放大未做、短音判定第一档爆炸行未钉、地雷kind及判定属性模型缺口、RealHS变频/seek声音/BGA别名裁切/全部format/CLI等仍按矩阵逐项保留。STOP/暂停所列时钟用例通过不能替代全部行为兼容 |
| 仍未证明 | 性能绝对超过原版 | 本审计读回是离屏GPU，不能推出窗口presentedTime/原版同机性能 |

本轮没有新的像素失败。经过明确关闭后的状态，不能再把早期“所有皮肤翻转”或“Info始终实色”的句子当成当前产品事实；同样不能把已关闭项推广成所有原版逻辑、所有帧、所有窗口比例都一致。


## 用户原则更新与声音调用链定向复核

**当前实施原则覆盖此前“所有原版逻辑原样复刻”的表述。** 用户最新要求原版逻辑作原始参照，避免照搬过时设计，应现代改进。外观、预期谱面语义和操作行为仍需真实验证；内部线程、调度时钟、缓存和播放缓冲可以现代化。先前矩阵保留为差异清单，未覆盖项不自动等于缺陷。漏音、错误分支、缺失预期操作仍是实际问题；不单调判窗和单buffer重触发等legacy怪异不应默认强制复制。

声音新样本：sound.dll MD5 `4e7836e120be46e66b2e98c242802ba8`，imagebase `0x10000000`、IDA311函数，用户只读端点13338；exe仍原样本、端点13337。本次独立定向读取只在exe上取小段汇编，没有运行exe/dll，也没把DLL311函数当作完整源码恢复。

### 同WAV再次触发：已知、推断与待证

`audit-compatibility/sound-play-targeted.json`、`sound-stop-position.json` 附原指令字节，直接确认：

- `clsSoundBuffer.play 0x423FD0` 从`this+0x34`取**同一内部对象**；该路径没有分配/克隆第二内部对象。`0x4240F3`无参调用内部`+0x5C`，`0x424119`向内部`+0x48`传`this+0x6C`，`0x424132`向内部`+0x44`传0。
- 内部IID原字节是`9f76fb01-8e92-11d1-8808-00c04fc2c602`，外层clsSoundBuffer IID不同。不能沿用外层VB方法序号给内部虚表强行命名。
- 方法名已由exe自身表锚定的`stopForce 0x424300`，在`0x424363`也调用内部`+0x5C`。因此这个内部槽承担停止动作是强语义证据。
- 外层`setPosition 0x424550`把`输入Currency位置 * nAvgBytesPerSec * 0.001`变成整数，`0x4245D8`存进`this+0x6C`；外层`pause 0x424180`在`0x4242AA`也由已播放毫秒数算出字节位置并存入同一字段。

由此，比UD早期“最后传0可能是setPosition”更可靠的角色解释是：**内部+0x48接保存的字节位置；内部+0x44的0更可能是Play flags；内部+0x5C是停止。** 这是由实参流与已命名外层操作得出的强推断，尚缺该IID的正式方法表或运行oracle。最后的参数0不能单独证明`SetCurrentPosition(0)`，因为实际位置参数在前一调用。

同一WAV槽正常再次触发复用同一后端缓冲、停止/设置位置后重新播放的可能性很高；完整事件触发链是否先清保存位置、别名WAV槽是否共享内部对象、实际声卡波形是否截断旧尾音，本轮没有运行证明。应记为**待原版运行或内部接口类型表确认**，不把推断升级为硬性产品缺陷。

现代播放器独立voices可允许同keysound尾音重叠。这和单内部对象设计不同，但按用户新原则是有意改善候选；不能再把“旧引擎很可能restart”自动转成必须破坏现代重叠的修复任务。应保留同token密集重触发、不同token同文件、暂停/seek尾音、爆音/漏音等行为测试，并对最终选择记录理由。现有现代polyphony测试证明现代合同，不能声称它同时证明原版相同行为。

### RealHS：max采样率身份升级，旧上限不自动约束现代后端

UD把`Format`虚表`+0x54`正确对到`0x4249B0`，它从对象`+0x3C`拷24字节；装载链确认对象`+0x40`是WAVEFORMATEX的`nSamplesPerSec`。本次独立复核原字节：`0x424A19 add esi,0x3C`、拷贝24；`0x424680`乘0.01、`0x424686 fimul [this+0x40]`，随后夹100..100000，再调用内部`+0x58`。原UR3“max字段尚未命名”的状态由此升级为**源声音格式采样率Hz**。

原公式可作为legacy对照oracle：正max采样率时`5*floor(2000000/maxHz)`，max为0时200；例如44100Hz→225、48000Hz→205、96000Hz→100、192000Hz→50。多资源取最大有效源采样率，不能错用音符数量、毫秒长度或混音器统一输出rate。运行时解析/解码保留源rate metadata即可避免把重采样后的设备格式误当原公式输入。

原频率`roundLikeVB(RealHS*0.01*sourceHz)`夹到100..100000Hz是原后端限制。**现代AudioEngine应根据真实支持范围与所选速度语义设计，不盲目复制100000上限。** 同样，旧公式对不同采样率造成的倍率上限差异应作为可观察行为差异记录；不能只因内部上限实现不同判为不兼容。默认200的历史项B2已修复，不要求A5重新开放它。

sound.dll只解码的导入/API证据和完整Format字段链接来自UD原报告；本次定向核查没有重做全部DLL函数。ACM报告格式与实际转换格式是否总一致、`changeVolume`最终单位、内部接口正式方法名仍未覆盖。


## UM3：L1真实MainWindow入口集成复验

**L1在以下实际产品入口用例关闭。** 先前只验证helper的边界已由本节升级，不再把“没调用MainWindow”作为这些用例的未完成项。

审计冻结了全部IBMSNative Swift源（排除AppDelegate的`@main`启动器），用新的`AuditMain.swift`构造真实`MainWindowController`与`ApplicationState`，直接调用产品方法`previewAudioContext()`。为避免从文件打开修改recent列表，仅在**审计目录中的MainWindow源副本末尾**追加一个同文件extension，注入真实`DocumentSession`和`BmsONEDocument`；没有替换、mock或修改产品`previewAudioContext`、`previewReadOnlyChart`、`bmsPreviewContext`、`bmsonPreviewContext`。原产品源未写入。没有激活、关闭或强退用户已有窗口，没有调用playChart发声。

证据：`audit-compatibility/main-integration-source/`（原始源SHA为`snapshot-sha256.json`，含注入extension的最终文件和链接库SHA为上级`main-integration-final-sha256.json`），完整编译参数`main-integration-command.json`，编译日志与实际结果`main-integration-results.txt`。Swift6、arm64-macos14目标，全部真实Swift源与现有真实桥/core/audio静态库链接成功；编译中的既有取色器弃用/菜单NSApp警告不冒充本次缺陷。

实际运行结果：

```text
MainWindow.previewAudioContext integration passed
actual BMSON metadata PLAYER3/JUDGERANK100 passed; audio2 bgm1/key1; continue skipped
branchA audio=5 visual=3 bpm=120.0; branchB audio=5 visual=3 bpm=180.0
```

验证范围：

- 原生BMS用`#RANDOM2 / #IF1 / #IF2`，两个分支拥有不同TITLE/ARTIST/BPM/PATH_WAV/WAV/BMP与音符位置。choice1读A/120BPM，改注入choice2但不reload仍复用A；reload后才变B/180BPM。实际notes中的01由拍0变拍2。标题、音符、速度、音频WAV表与图像BMP都来自同一条已展开分支。
- 每支真实主窗context均给5条音频记录：1BGM、1mine（token为空，不误触发谱面WAV）、3key（普通、hidden、长音头）；长音尾没有二次发声。视觉3条（普通、mine、配对长音）；hidden/BGM没有画进键道。
- PATH_WAV含空格的分支目录与带空格文件名被改成正确绝对WAV路径；`chartDirectory`仍为谱面目录，BGA资源仍为该分支的image-a/image-b，不被拼到PATH_WAV。
- 原编辑文档的currentBytes前后完全相等、dirty仍false、hasConditionals仍true、chart.events仍空，证明没有把只读预览分支写回编辑文档。另一普通文档先经真实`replaceMetadata`产生未保存TITLE，主窗preview读取到新TITLE且dirty保持true。
- 从真实BMSON JSON读入beat14k、标题/曲师/曲风、level7、BPM150、judgeRank100，经实际主窗context得到`#PLAYER 3`、`#JUDGERANK 100`，没有虚构`#RANK 100`。x0→BGM、x1→key、continue音符不重触发，文档isModified保持false。
- 当前UM3 `PreviewBmsSourceTests`另独立重编运行通过，见`source-tests-UM3-results.txt`。它的更多编码/别名边界与上述MainWindow实际入口证据并列，不把helper结果替代实际入口。

尚未由此覆盖：mine stock engine音本身仍缺；音量VOLWAV只随context字节保留；RealHS调用链、播放后的声音过滤/暂停seek由音频与窗口专项验证；BMSON无法由八槽皮肤承载的模式仍应清楚表达部分显示。CLI兼容是产品范围差异，按用户现代化原则不擅自加入外部uBM exe调用。

接下来真正剩余的外观集成审查是UW4宿主587×256布局：packed与separate的P1/P2/BGA位置、高DPI与共同倍率，以及真实合成图。US4离屏子视图零差与本节MainWindow数据入口通过均不能替代此项。


## UW4：完整587舞台独立复验（冻结W4+A5，非最终A6二进制）

源稳定性：在UW4完成前后对11个输入文件重复检查mtime与SHA均相同，见`post-UW4-source/stability-check.json`；原样源码冻结在该目录，清单`sha256.json`。窗口SHA `db4539173833568313c7862ec3fabd30c0eed13367710ee69225554e08dfbd08`；音频为A5的`c702ccd72055861494e75488df645217bdcd7662f9d3dbd6202cb576f189a9f7`。随后A6/S5/W5/G2在实施，本节不冒充最终发布二进制的结论。

`post-UW4/StageProbe.swift`使用真实窗口控制器/真实content view、两张真实Metal视图、真实BGA图层与实际Info源，轻量ApplicationState只提供真实LegacyPreviewAudioPlayer对象。未替换布局、视图、皮肤或绘制。离屏实际Metal读回保存PNG，由Pillow按**实际clip frame、child offset**拼入587舞台；BGA取真实layer.render，Info取实际view.sourceImage。独立oracle用原skin00/skin01/font直接Pillow解码，BGA是审计自制四象限PNG（可识别上下/左右/采样），不使用产品CPU图集解码输出当oracle。

### 已通过：布局、可见像素与效果层位置

- **72 case**：PLAYER缺头/1/2/3 × AutoSeparate真/假 × Both/1P/2P × 原生/2倍/3倍。全部布局帧和倍数正确：`packed = !autoSeparate || PLAYER==3`；packed为P1/P2完整331左、BGA331..587；separate为P1 15..173、BGA173..429、P2 429..587。2P child offset=-173×scale，clip158×scale；没有把2P整个推到331子视图外。
- 按实际guide覆盖行准确mask，原图背景、键盘、判定线、note、BGA和**实际Info源的独立font逐字RGBA oracle**，合计**49,788,900比较像素零差**，几何0失败。`post-UW4/stage-comparison.json`列每case比较像素/差异，`stage-records.json`列实际frame、source size、文本和BGA ready；不是只比helper布局值。
- 另**12个命中stage case / 384检查**：PLAYER1/3 × AutoSeparate真/假 × 1/2/3倍，16通道所有键帽和顶部车道亮条共**350,448个放大ink像素零差**。使用宿主实际clip和offset合成，再对原skin01源纹素检验，2P键帽/beam没有裁掉、偏1px或误缩放。见`post-UW4/hits/hit-comparison.json`与实际composite。
- Info的BMS实际头LEVEL7/RANK2保留；BMSON JUDGERANK100不伪造BMS RANK；缺头时不补LEVEL/RANK。通过真实controller按9切换Info读取，见`metadata-results.json`。未把没有显示的旧prefix解析代码当显示bug。
- F2真实运行中只重排：同一次播放仍`isPlaying=true`，BGA chart绑定计数2→2，beat4.045886前后完全相同，wall正常前进，没有重播或重`setChart`，见`host-clock-results.json`。

最初BGA layer.render导出出现的2x/3x边界混色，经核查产品imageLayer明确nearest；问题是**审计用CGContext默认插值**。把探针context.interpolationQuality设为.none后72case全部零差。因此没有把该探针伪差异列成产品缺陷。

本节composite是“实际Metal+图层”验证，**不是屏幕截图、锁屏绕过或WindowServer/presentedTime验收**。没有操控系统屏幕。真实Retina窗口最终合成、非整数letterbox与呈现节奏仍由相应窗口/性能证据承担。15px外侧留白未作为原skin覆盖区验收，不以未比较区域充数。

### 仍未关闭：W4后续音符在RealHS下的效果时钟错位（P1）

精确触发：BPM120、音符拍4、RealHS/播放器速率2倍，原生与侧视图都用`setTiming`算到达谱面秒2。播放墙上秒约1时音符已到判线，但窗口传墙上秒给S4与谱面到达秒相减。

实际应用拥有的窗口/真实播放器运行（无声音文件、不是虚构elapsed回调）的独立结果：

| 时刻 | 墙上秒 | 谱面秒 | 播放拍 | 主/侧命中 |
| --- | --- | --- | --- | --- |
| 音符已经过线 | 1.029554 | 2.022943 | 4.045886 | 两边都空 |
| 错误延迟触发 | 2.027920 | 4.021665 | 8.043329 | 才出现11ms年龄 |

冻结代码位置：`post-UW4-source/PreviewWindowController.swift:984`取wall并写effectElapsed；`PreviewPlayfieldView.swift:537`用该elapsed二分**谱面到达秒**，`:539`直接相减。`HostClockProbe.swift`直接调用窗口playFromStart并轮询同一真实播放，GPU原始BGRA和PNG为`host-rate-note-at-line.*`，完整值在`host-clock-results.json` / `.txt`。命中层缺失和晚触发是用户可见错误，不属于允许现代化的内部差异，也不是“因为原版过时必须复制”的结论。

最小修复边界：S5明确分开chartElapsedSeconds与effectElapsedSeconds，按谱面钟判断事件到达，并记录该事件的墙上生存起点；W5向两侧正确传两只钟，不能简单把墙上秒减未缩放谱面秒。速率运行中改变、STOP、暂停/恢复、Here和seek要清理/保持正确的有限lane记录。当前S5/W5在修，**父代理Release67/67通过不关闭本P1**；待修复稳定后需用同一实际host probe复验。

### 尚待验证或范围差异

- 静态核对W4的BPM/STOP/fromBeat在起播/Here/seek/重绑定通过`setTiming`交给两视图；现有产品测试已覆盖这些基本时刻。独立S4的STOP/暂停GPU边界通过仍有效，但本轮不把67测试通过替代上述RealHS P1。
- BGA `#BGA`别名裁切、整stage透明外溢当前冻结G1尚未实现；G2在开发。不能写BGA所有逻辑或像素已经完整一致。
- GREAT前90ms放大、短音爆炸行、mine stock音、RealHS最终现代可用范围/音量、全部特殊format等按前述记录保留。CLI是产品范围差异，不擅自加入外部exe接口。
- A6按用户现代化要求将不再照搬100000Hz/sampleRate旧上限，并修资源句柄临时耗尽漏音；这轮冻结A5只用于可复现窗口审计，最终集成需重测，不能把旧ceiling200当现代新需求的验收常数。
- 准备阶段性能：S4 `rebuildHitSchedules`逐note调用arrivalSeconds，后者进入会排序/扫描BPM/STOP的seconds路径；两视图在setChart/setTiming还可能重复。**这是静态复杂度疑点，尚未量出耗时，不定为用户卡顿来源。** native像素零差不证明准备阶段性能达标。


## US5：独立双时钟与命中生命周期复审（S5冻结，不读取进行中的S6/W5）

S5源已原样冻结：renderer `6c78d2fa2437927059a3479aae96127e49041bcfe6dccf2e38f21f94abcdabde`，Style仍`120a54b8…`，测试`c880e829…`，SHA与源在`post-US5-source/`。编译使用真实、已冻结A5 `LegacyPreviewAudio.swift`的类型及实现，**没有使用PlayfieldVisualStub**；不将进行中的A6/W5版本混进本轮。`post-US5/DualClockProbe.swift`直接调真实双钟API和Metal读回，输出`dual-clock-results.json`及逐case PNG；源PNG独立像素比较见`compare-dual-clock.py`和`dual-clock-pixel-comparison.json`。

### 渲染层已通过的双时钟范围

- 非零拍4，BPM120：2倍时chart2/wall1，0.5倍时chart2/wall4，均在到达帧捕获age0；50ms还是beam原 `(60,0,0)`，51ms归背景黑，100ms长音bomb匹配原skin03第5帧（按wall/20，非chart/20）。两个倍率的每个未覆盖bomb ink与独立PNG零差，未来note保持全局beat帧零差。
- 动态倍率：先(chart1.5,wall1.5)，再(chart2.1,wall1.8)，跨到达chart2的birth插值为wall1.75，实际age50ms；暂停保持相同两钟，重复两帧整幅GPU零差。切side、改scratch/F2 appearance、滚速未把age50重置。
- STOP：beat4固定、chart秒和wall秒各增加，后续note不提前命中，已触发效果按wall增长。BPM4处改240，第6拍到达chart2.5/wall1.25获得age0，匹配两段到达秒。
- 新API第一帧chart2.02/wall1.01不补过去20ms命中；正好chart2/wall1则补age0。Here从拍8起，过去的拍4长音不复活，拍8精确命中保留，后续拍12再跨越得到age0。chart回退到0清旧latch，重新跨到达产生新age0。
- 每case连续`currentScene()`、再Metal readback、再`currentScene()`，**所有scene相等**；取场景/读像素不会推进命中出生时刻。
- 简单hidden gap（同一long索引）墙钟跳过1.08秒，expired命中能清除；但下表“跳过后一音符”分支仍有缺陷。
- 原图不回归：用前一轮独立`AppearanceProbe`重编到S5，四scratch背景/键盘/16路note/beam/cap、默认2x/3x和packed false继续全部原PNG零差，记录在`post-US5/atlas-regression/appearance-comparison.json`。上述渲染层通过**不关闭W4实际宿主P1**；W5仍须接双钟重载并复跑真实host。

### 新确认的两个生命周期缺陷（待S7）

| ID / 优先级 | 精确触发与实际影响 | 独立证据 | 最小修复边界 |
| --- | --- | --- | --- |
| C2 / P2 | lane11 startBeat4/endBeat8，2倍速以每0.02chart秒连续更新直到chart12/wall6/beat24。尾端本应在chart4/wall2结束，四秒后仍`isLong=true,age5000ms`，永久循环爆炸直至同lane下一note；这是结束状态缺失，不因“原版long不120ms清”豁免 | `long-after-tail-continuous.png`底部1,089 ink仍严格等于原skin03旧long第4帧、对背景改变1,089像素；scene记录同名case | 命中表保留长音尾到达/结束信息；尾后正确退出持有爆炸（是否另做尾击反馈按现代合同定义）。不能只用isLong永久跳过清除 |
| C3 / P2 | 同lane先long拍4..8，再short拍12。旧long在chart2/wall1已锁存；隐藏样本一步跳到chart10/wall5，新short已过期。S5检查新index时`age>=1.08`直接continue，却未清旧latch；恢复第一帧出现age4000ms的旧long，下一帧才消失 | `hidden-skipped-next-note.png`有763个旧long第2帧ink，对原背景改变763像素；`hidden-skipped-next-note-again`下一帧才空 | 新index覆盖旧命中之前先移除旧latch，随后再决定是否接纳这个过期的新命中；长间隔/隐藏恢复不可留下单帧幽灵 |

定位：S5 `latchSegment` 旧索引分支约`:1702`，新命中年龄过滤约`:1725`；生命周期只存index/birthWall/isLong，没有尾到达秒。使用上述冻结源行号，不将后续S6行数变化当同一版本。

这些是用户可见状态错误，按用户现代化原则应修复；无需机械复制可能存在的旧长音怪异。S6只做预处理性能，语义修复应独立续S7，避免并发写同文件。

### 普通短音爆炸缺口：原版图集行已补足证据

此前UR2/US5把“第一判档EBX未知”当不画任何短音爆炸的理由。独立最小只读追链已补齐，见`post-US5/ida-ordinary-bomb.json`和`ida-first-judge-ebx.json`（含原指令字节）：

1. 判定函数`0x419E10`序言`0x419E4A xor ebx,ebx`，至第一判档`0x419FDF push ebx`之间没有EBX重写；正常VB/native ABI调用保持callee-saved EBX。因此第一档传0，`0x419FE4`调用`0x419CE0`时另一个参数是`0x2000`。
2. `0x419CE0`在`0x419D6D`把arg4写爆炸槽+8；仅arg8等于`0x4000`会把long标志+0C置真，普通`0x2000`不会走long例外。
3. `DrawBomb`读取槽+0C，long非零走源top163/64方块。非long在`0x415F53`读+8；值0走`0x415F5A top66`且边长96；值1走`0x415FD6 top1`且边长64。源x均`1 + ((age/20)%6)*边长`。`0x416155 cmp 120`后非long清槽。

因此普通第一判档可画**skin03中排96×96、6帧/20ms**，第二档可画上排64×64；第一档逐词叫PERFECT还是GREAT仍不是本段指令证明的事，但**不再缺少图集行选择的依据**。原版序言EBX已确认，旧“未知”置信度应升级。现代自动演奏命中若选择精确首档反馈，可以明确使用中排96方块，不应把“短音无爆炸”写成完整视觉一致。

当前S5实际正常音只有车道亮条/键帽/GREAT，短音爆炸仍未画；GREAT前90ms放大也仍未实现。两项保留为外观差距，不因普通功能测试或本节时钟通过而关闭。没有运行原版程序，也没有据此次小段读取宣称全部判定状态机已还原。


## S5 判定图层补审：位置、数字与双侧计数（新增P2，待S7）

本节使用同一S5冻结版，不读取S6中途保存。父代理新增`ida/parent-effect-contract.md`给出90ms放大和数字摆动。独立小段原指令证据在`post-US5/ida-judge-position.json`与`ida-judge-rounding-wave.json`，包含调用/参数与原字节。

### 汇编核对

- 默认SkinType0..3时`0x416306 xor eax,eax`与`0x416308 var_38=1`，在`0x41631E`循环player记录0..1。每侧记录步长44字节；`0x416668`与`0x4166B8`取**该侧记录+0x24的combo**，不是整个谱面统一数字。`0x41691F`跳回下一侧，因此同时两侧命中应分别有字与数字。
- 有数字的GREAT x有**两次独立向零整数除2**：`0x416496..4A3`给`15*digits+88`除2，`0x4164AD..4B3`给source宽81除2。因此1位数是`seed+119−40−51=seed+28`；现代Style使用CGFloat的40.5/51.5得到27，向左1像素。没有数字时仍seed+35。
- `0x4165F7..61B`建立digitBase=`great.left+(sourceRight-sourceLeft)−7`。`0x41668D`令i=1；`0x41687F`和90ms后`0x4168D5`都是`15*i+digitBase`。首位应**great.right+8**；当前renderer首位great.right−7，额外少15像素，再叠GREAT本身1px合计少16px。
- 正弦helper：`0x410A30`读256/360、乘传入整数degree、`__vbaFpI4`、`0x4109E0`屏蔽uint8后读Float32表；`0x410A60`把age加90再调前者。表初值父代理证据为Float32(sin(i*pi/128))。**banker rounding依赖VB运行库合同**，不是此exe自实现算法，不把未调试运行库的半值行为伪称指令直接证明。
- GREAT age<90在`0x41654C`用age+90表值s；目标高单独`FpI4(14+7s)`，y单独`FpI4(161−3.5s)`，宽仍81。数字先`FpI4(161 + sinTable(globalMs+180*i)*(6-age/180)*0.5)`；age<90再给高`FpI4(14+14s)`、y`FpI4(先前已取整y−7s)`。两次y取整不可合成一次。90ms后digit仍有轻摆，不是固定y161。常数原字节已核14/7/3.5/180/6/0.5。

### 实际Metal与独立PNG复现

`post-US5/JudgeProbe.swift`分别渲染1P单独、2P单独、双侧同拍各1音符。取age160ms、global2160ms，已过90ms放大期，首digit相位2160+180=2340°落在sin0，避免把尚未实现的波形误算成x差。所有帧`usedMetal=true`，保存实际PNG。原skin02直接Pillow解码，比较脚本`compare-judge.py`。

| ID / 优先级 | 触发与影响 | 实测 | 最小修复范围 |
| --- | --- | --- | --- |
| V4 / P2 | 单digit的GREAT向左1px | 每侧原GREAT源前74列188ink：正确x(seed+28)差63；实际x(seed+27)差0 | `greatNativeX`用两次独立整数向零除法，不做Float半宽 |
| V5 / P2 | 首digit向左16px并压进字右侧 | 每侧数字1应在seed+117，24ink全部缺；实际seed+101与原digit1的24ink零差 | 首digit索引从1（right−7+15*i），并使用修正后的GREAT整数x |
| V6 / P2 | 双侧同拍命中只显示1P字，combo全局2 | `judge-1-2.png`右判定区排除实际guide y153后与原skin背景0差，完全没2P字；左digit2 42ink与原PNG零差，理应两侧分别digit1 | 命中记录、判定字年龄、combo按player分别取值/画字，保留全局总计仅用于另外明确的统计 |

早期报告的GREAT/combo“源片零差”仍证明原图纹素读对；但早期x27、first digit x101的定位oracle来自尚未核整数除法/1-based循环的UR2摘要，**不能继续作为原版绝对定位通过**。本节新增原汇编和GPU证据明确推翻那个定位结论，相关绝对位置项重新打开为V4/V5。不是通过修改对比范围隐藏偏差。

普通短音bomb（已补足首档中排96px证据）、GREAT前90ms放大/数字轻摆，以及本节V4/V5/V6均尚未实现；不能称判定动画完整一致。用户允许现代化内部实现，但这几项是明确的视觉缺失/错位/计数错误，属于应处理的外观行为。


## UW5/G2 冻结整链：裁切、整舞台与两只钟

本轮严格读取父代理`parent-UW5-UG2-frozen`，逐文件核对其SHA全部相符，见`post-UW5-UG2/verified-frozen-sha256.json`。W5=`fe808c6f…`、G2=`89736f6f…`、S6=`b1c3407e…`、A6=`8b176e81…`；没有混入动态S7/A7/G3。本轮只写审计目录。G2报告实际路径是`out/validation/ubmplay-parity-20261020/UG2-early/report.md`，其“窗口未接”的旧状态由W5与以下集成证据升级。

### W4效果错位P1：所测真实宿主用例关闭

复用原`HostClockProbe`的真实窗口/播放器时间线（没有伪造elapsed回调），通过真实键4二十次设置RealHS200、engine.requestedPlaybackRate=2，BPM120/拍4：墙上1.03146s、谱面2.02645s、beat4.05290时，**主视图和侧视图都已有lane11/21的命中**。旧W4同位置两边均空、墙上约2秒才出效果。真实GPU BGRA仍保留为`post-UW5-UG2/host-rate-note-at-line.*`；数值见`host-clock-results.json`。判定图绝对位置/短音bomb仍是S7另修范围，本项关闭不连带关闭它们。

`HostTransportProbe`进一步实际运行Here(origin4)、BPM4改240、拍4 STOP1秒、暂停/恢复、F2、Home与Down seek：

- Here的拍4在两侧都获得age0，STOP期间拍4保持、效果墙钟继续；暂停等待0.12s后播放器wall、场景effect、chart、命中年龄全部相同，RealHS200/requestedRate2保持；恢复后效果年龄增长，仍在STOP拍4。
- F2前后BGA bindings=3，sourceFetches=2；只重排、不重读分支、不重播；Home清到origin0、无旧命中；Down seek回拍4立即获得两侧age0。两次seek不增加BGA绑定或sourceFetches，倍率仍2。
- 低倍速与其它边界日志单列在`half-rate/`；UI倍率读回和engine一致的检查不只看菜单文字。

### G2 静图独立逐像素oracle

`BGACropProbe.swift`使用真实G2/A6，生成/读取审计自制4×4独立颜色图、512×300逐像素pattern与黑键layer。直接渲染真实BGA图层，Pillow oracle**用朴素源像素到目标坐标逐点映射**，不调用`PreviewBGAGeometry`、产品parser或切片helper。共**60case、42,076,160 RGBA像素零差**，每case都确认ready，见`bga-crop-comparison.json`。

覆盖名义列origin173/331 × 1/2/3倍，分别：原4×4不缩放居中；BGA05指向BMP00优先于BMP05；BGA00在alwaysPoor别名到BMP01；负源坐标保留目标偏移；负dx/dy舞台裁边；右/下舞台585/254只留下2×2；逆序源端点；512宽静图保持原宽向两侧外溢且只取顶256行；base00清屏不画BMP00；黑键layer叠合。列外/舞台内透明、名义256列不透明黑，超舞台像素裁掉；没有通过拉伸残图填回去掩盖负坐标。

每case额外300tick，scriptParse/imageDecode/pathResolve/eventIndex计数均不增加。独立`BGAAsyncProbe`：

- Off500tick：parse1/index1，**resolve0/decode0/videoOpen0**。解析内存文本不冒充图像IO。
- beforeDecode门闩阻塞旧base与layer两条异步请求，换成新chart再释放旧请求；最后真实图层与“新蓝base+新绿黑键layer”的独立150,272像素oracle零差，旧红图没有覆盖。generation2、parse2；准备完成再500tick计数不变。见`async-results.json`、`async-pixel-comparison.json`。

### 真实分支数据到完整587舞台

复用已冻结真实MainWindow集成源副本，在**原随机分支内**分别加入BMP00 pattern4/pattern512与BGA01→00定义，通过真实`previewAudioContext()`选支、缓存、reload、PATH_WAV重写后导出`selected-branch-A/B.bms`。实际MainWindow集成再次passed；原编辑字节不变、分支WAV和BGA定义同源。BGA脚本由主窗字节保留，BMP没有被拼入PATH_WAV。为了验证两种宿主布局，布局fixture在这些已展开字节末尾显式覆盖PLAYER1/3；未把此测试覆盖冒充修改用户谱面。

`HostBGACropProbe`用这些真实主窗输出交给冻结W5/G2，测试两分支×PLAYER1/3×F2开/关×1/2/3倍，**24case**。实际BGA view frame确是整587舞台，不只是名义256列；layer整体**16,830,464像素零差**。在BGA之后按真实clip/child offset叠上两块Metal谱面，再与原atlas独立oracle比**16,757,160像素零差**，2P不裁、packed/separate和统一倍率正确。见`host-bga/host-bga-comparison.json`。整体BGA透明外溢位于谱面后方，正确被不透明皮肤覆盖；这不是把每幅图强行限制在256列而得到的假通过。

本节仅静图裁切/组合。**视频仍是冻结G2的rate1、未实现完整源裁切**，已知G3修复进行中，不能写视频与2倍谱面同步。取整/安全范围按用户现代化原则使用有界整数，不要求复制原版int16溢出。普通第二档/手动判定/skinType4也没有因本节通过被当作实现完成。


## US7：有限长音、普通爆炸和两玩家判定的独立复验

S7已原样冻结为renderer `181e06889fd42cd8d4c7c4313814c9af4b7f9936b618a91640dee76bd8e85ca9`、Style `7aaa8f88b49f60e55e0533203ae24dd41106af1095258e68b7ac8b9a5c9fa012`、Tests `1286bee1…`；真实A6音频结构/实现采用父冻结`8b176e81…`，没有用stub。源与SHA在`post-US7-source/`，本轮所有独立probe和图片在`post-US7/`。

### 已关闭的旧缺陷与动画验证范围

- C2（尾后无限爆炸）原独立case：start4/end8，2倍连续走到beat24/wall6，现hit为空，原底部4096像素对skin00背景零差。连续跟踪跨尾的2倍case，tail age100ms仍有尾反馈，120ms消失；不加combo或重放head GREAT。C3（隐藏跨过新过期note的旧latch幽灵）原case及下一帧均hit空、底部背景4096像素零差。
- V4/V5/V6：97个实际Metal帧覆盖1P、2P、两侧各1combo、1P3combo/2P1combo，native/2x/3x及age0/30/60/89/90/120/1079/1080，再加global500ms/age0。按独立Python Float32正弦表、银行舍入和原整数除法计算目标矩形；GREAT单digit x28、数字首位right+8、每侧自己的combo与年龄均正确，右侧不再漏字。
- 90ms放大与数字轻摆**公式、目标位置和生存期**得到上述独立验证；1080ms清字，global500ms/age0的digit使用全局相位而非年龄。第一判档普通爆炸现在实际画出中排96×96的6帧，每20ms一帧；关闭键帽的效果3下，各帧未覆盖ink与原skin03全部零差，120ms恢复skin+note底图。第二判档上排64与手动判定、SkinType4仍未支持，自动预览固定首档，不能写成全手动判定系统。
- S6时刻索引保留：独立以真实A6类型、`-O`、device:nil重编原US6 TimingProbe三遍，50k notes +1000 BPM +1000 STOP的setChart6.68…8.53ms、setTiming7.80…9.08ms。这是准备阶段单子视图的有界数据，不是帧率或超过原版性能证据。日志`timing-results.txt`。

### 精确采样限制：不把nearest平局误报为位置错误

`compare-judge-animation.py`共266 ROI、1,009,244源ink/清除区域像素，严格按Pillow nearest计算时出现3,596像素差异。进一步逐点检查，**全部3,596处恰落在垂直source texel边界的nearest平局，非边界差0**；主要是14→21高度在1x/3x下的边界，2x没有这些差异。见`judge-sampler-tie-analysis.json`。

没有原版DirectDraw在同帧、同缩放条件下的平局选择oracle，因此不把这种有效nearest边界政策差异直接判成GREAT定位/zoom公式缺陷；也不宣称该97帧对Pillow整片严格RGBA零差。若需要跨GPU统一逐像素结果，应另定边界选择/数值策略，并做可复现采样契约，而不是扩大颜色容差。

### 新确认的有效长音恢复缺陷与绘制顺序差异

| ID / 优先级 | 精确触发与实际影响 | 证据与最小修复边界 |
| --- | --- | --- |
| C4 / P2 | **有效long中段**：start0/end32，先(chart0,wall0)锁存，再(chart2,wall1)正常持有；隐藏2秒后(chart6,wall3,beat12)，尾仍在chart16，S7却清掉同index持有状态，下一帧也不恢复。不能与已经修好的尾后过期混同 | `valid-long-after-hidden2s`/`…next`无hit；连续走到完全相同chart6/wall3/beat12仍有long，真实GPU两图差252像素。`validlong-visibility-comparison.json`。S7约1885行same-index wallGap>1.08直接清，是根因。S8需在有效持有期间恢复/保留持续反馈，并避免重放head GREAT；W隐藏logic-only推进可作为配套，但不能让状态正确性只依赖可见渲染 |
| V7 / P2（待产品选择/修复） | S7先画bomb后画cap，0/20/40ms键帽盖掉了白键普通爆炸的106/130/121个原ink，60ms帽灭后差0。原已确认DrawMain顺序为4158F0键帽、415B20、415E10 bomb、416280字，bomb应位于cap之后 | `ordinary-bomb-comparison.json`和PNG，差异只在x37..49,y233..249；效果3无cap时同源6帧均零差，排除源切片错误。若目标仍是原像素顺序，将cap放bomb前；若刻意改善可见键帽，应明确记录这是新的视觉选择，不宣称和原版覆盖关系相同 |

额外边界记录：一次大步从chart0/wall0跨到chart4.2/wall2.1，long start4/end8的head已经1.1秒、tail仅100ms，S7因head过期直接不存latch，未见尾反馈。是否恢复短尾反馈应由现代隐藏恢复合同决定，本轮没有把`advanceTails` fallback的静态可疑换算直接升级为单独已证公式错误；连续跨尾100/120ms对照正确。

本节旧C2/C3/V4/V5/V6关闭不代表所有长音状态通过；C4仍是明确的有效状态丢失。普通bomb/90ms已经实施，旧章节“未画/未做”仅保留历史，不应继续当成当前S7事实。最终窗口集成仍等所有范围稳定再冻结，未把动态A7/G3/W6混进S7本轮。


## 原版视频合同更正：实际+0x44裁切入口与另一条+0x48居中入口

本节独立小段只读证据为`audit-compatibility/movie-draw-entry-and-scale.json`和`movie-private-scale-and-convert.json`，均附原始指令字节。没有修改IDA函数边界、没有运行exe/movie.dll。父代理相邻raw证据为`ida/parent-movie-*.json`。这项更正覆盖UX/G2早期把整帧居中函数套到实际裁切调用链的推断；**不能继续只写“未知”却沿用已经对错入口的y公式**。

### 直接确认的方法映射和调用

| 虚表槽 | 表项与跳板 | 实际入口 / 业务证据 |
| --- | --- | --- |
| +0x58（public15） | 403F7C→4041E1 | 42AC60 getter在42ACA0读`self+40`，即当前对外宽 |
| +0x5C（public16） | 403F80→4041EE | 42ACE0 getter在42AD20读`self+44`，即当前对外高 |
| +0x44（public10） | 403F68→404193 | **42A580**，实际裁切绘制入口 |
| +0x48（public11） | 403F6C→4041A0 | **42A780**，另一条整帧绘制，含垂直居中 |
| +0x84（private） | 403F9C→4041FB | 42AD60，打开后归一化尺寸/保存缩放比 |
| +0x88（private） | 403FA0→404208 | 42AE80，四角源矩形坐标转回原视频坐标 |

width/height getter同时锚定public序号，不是只凭描述符偏移猜测方法名。父代理的打开链原字节已见429E2E/31写`self+40/+44`原始W/H后429E34立刻`call [vtable+84]`；独立重读私有函数确认其把原W/H另存`+4C/+50`，再改写对外`+40/+44`。

实际`DrawBGA`在416BC8/416C21读对外宽高，416C01..06算`128−trunc(W'/2)`；416CD7 **call+0x44**。该调用压的目标y是EBX=0（此路径没有加`(256−H')/2`）。42A580在42A649/657直接使用传入y构造目标矩形，矩形宽高是传入源rect的right-left、bottom-top；416F90裁边后42A6DF调用+0x88转源rect，随后42A715把目标rect与转换后的源rect交后端。

相反，42A780在42A825..853明确读对外W'/H'，计算`传入y + trunc((256−H')/2)`；它属于**+0x48**。早期UX/G2把这段额外垂直居中当成实际+0x44行为，调用链对错了。readme的“视频居中”可作为产品期望参照，现代产品也可有意选择居中，但不能称这种y与当前已证的原版+0x44调用相同。

### 尺寸归一化与矩形转换的证据分级

42AD60先用`rtcImmediateIf(W<H,H,W)`取得长边，常数VARIANT为Float32 256（`0x43800000`），调用`__vbaVarDiv`后把Float32结果存在`self+48`，随后两次明确的FPU `W / scale`、`H / scale`与`__vbaFpI4`改写对外宽高。按VB二元helper的操作数约定，这个scale是`max(W,H)/256`，因此对外长边256；它也与官方readme的长边256闭合。

**运行库边界：** 此exe只导入VarDiv，未读取/单步MSVBVM60实现；push顺序本身不能按普通直觉当成C的左除右。最强直接事实是“IIf长边和256进入VarDiv，结果Float32，W/H明确除结果”，`max/256`的最终命名还依赖VB helper约定及对外尺寸/readme交叉支持。没有把这一点伪称运行验证，也没有以“可能相反”继续沿用G2未缩放的整个原始640×480帧。

42AE80的坐标转换则是完全直接FPU证据：按输入Rect的left/right/top/bottom，**每个角分别乘Float32 self+48再FpI4**写输出四角；不是先取width/height乘比后加回left/top。VB半值银行舍入仍属运行库合同。以640×480为对照：scale2.5，对外256×192；虚拟源rect(0,0,128,96)对应原像素(0,0,320,240)。虚拟x端点1/2各自乘2.5→按银行舍入2/5，宽是3，不能先把width1乘2.5取2后拼成2..4。

### 给后续G4的可验证合同与保留项

- 静图仍保持G2已测的原始像素/裁切语义；视频单独使用归一化显示W'/H'和原始视频W/H，不能把静图512外溢规则直接套视频。
- 对实际+0x44参照，目标位置取caller x/y（含BGA dx/dy），不再额外加+0x48那条垂直居中；目标尺寸用虚拟源rect跨度，源四角经scale转回原像素并安全裁剪。
- 现代代码应检查零/负/非有限尺寸、用有界整型和安全裁边，不复制原版int16溢出或异常路径。可另选居中显示作为明确产品选择，但需标明与已证调用路径的差异。
- 后续独立用640×480、64×32、奇数尺寸和带象限/边缘标记的视频做实际帧验证；涵盖无BGA、正/负源rect、packed/separate origin、1/2/3倍、暂停/Here/seek，以及G3/G4实际AVPlayer倍率。当前本审计**尚未测试进行中的G3/G4**，不把新静态合同当作已完成产品验收。
- 后端movieDraw的最终颜色/采样、416F90在这个入口里各bounds参数角色、全部异常和运行库半值行为没有穷尽；应保留细节边界，不能将这次入口纠错写成movie.dll全部逻辑已恢复。


## US8：有效长音恢复与logic-only推进复验

本轮只读父冻结`parent-US8-frozen`，三份SHA逐一匹配：renderer `3543743170d046084accca086bb1d665124b5fd5ef6d7994eb5561f0cc731427`、Style `7aaa8f88…`、Tests `b6037c05…`，验证表`post-US8/verified-sha256.json`。独立probe仍链接真实父冻结A6 `8b176e81…`的音频数据结构与实现，不用stub，不读S9进行中源。

### C4所测用例关闭

同一原审计case：long start0/end32，先(chart0,wall0)，再(chart2,wall1)，隐藏两秒后(chart6,wall3,beat12)。现holding仍有原age3000ms，下一帧age3010ms；该侧判定数组为空，**没有重播head GREAT、没有新增combo**。与连续推进到同一chart6/wall3/beat12的Metal图，**全84,736 RGBA像素零差**；持有爆炸252个原skin03下排ink也零差。`post-US8/recovery-pixel-comparison.json`。原来这两图差252像素，现在该C4消失。

大步跨head与tail：long start4/end8，从(chart0,wall0)跨到(chart4.2,wall2.1)；head1100ms已过期，tail100ms仍保留，只显示有限尾反馈，不新判定。tail119ms仍是原skin03中排96第5帧，100/119各2,408个可见ink零差；120ms清到原底图6,840像素零差，sideJudges始终空。原S5/S7旧尾后无限及“跳过下一过期note留下旧latch”用例仍为空，没有回归。

### 2000次advancePlaybackClock：实际几何和GPU零增量

`post-US8/LogicOnlyProbe.swift`对两玩家long0..8，仅调用2000次`advancePlaybackClock`，从(chart0,wall0)到(chart4.2,wall2.1)：

| 计数 | 开始 | 2000次后 | 增量 |
| --- | ---: | ---: | ---: |
| geometryBuildCount | 3 | 3 | 0 |
| liveSubmitCount | 0 | 0 | 0 |
| pipelineCompileCount | 1 | 1 | 0 |
| vertexBufferAllocationCount | 0 | 0 | 0 |

此后重复`currentScene`相等；两侧head age2100、tail age100、无sideJudges。随后**一次**`renderMetalReadback`只增加一次geometry，usedMetal=true；实际两侧尾反馈对独立原skin03 ink分别2,408/2,488像素零差。日志`logic2000-results.json`、原BGRA与PNG、比较脚本均保留。约863ns/tick只是本机、此两轨道、Onone逻辑探针数据，不报成播放帧率，也不代表任意lane数下固定开销。

本轮不声明窗口隐藏时已经接此入口：W7宿主接线仍须其稳定版本的整体逻辑/时钟证据。S9只改覆盖顺序，不能把它的中途文件混进此处。V7图层顺序和nearest平局限制没有被本轮逻辑通过顺带关闭。

Here策略需单列：不重放原点前的head GREAT是合理的瞬时反馈策略；它并不自动证明长音中段的持续持有状态应该消失。当前审计将这两者分开，后续宿主观测若仅缺持有爆炸而长音体/音频carry仍在，应先记具体策略边界，不以未复刻旧怪异无限扩大阻塞范围。


## W7 Here中段长音策略与隐藏logic-only实测

使用父冻结`parent-UW7-UG4-frozen`，全部SHA核对相符（W7 `4cb3a4cf…`、S8 `35437431…`、A6 `8b176e81…`、G4 `360b345d…`），没有读取S9/后续音频/视频动态源。`post-UW7-here/HereHoldingProbe.swift`构造应用拥有的窗口与真实播放器，只读当前原始皮肤，音频是审计目录生成的20秒全零PCM，不会发出可闻内容。没有显示/操控系统窗口、没有调用屏幕截图或绕过锁屏/可见守卫。

实际case：visual LN start0/end32、音频采样在beat0，Here从beat4开始。约chart0.21271s、beat4.42542、effect0.21273s时：

| 观察 | 结果 |
| --- | --- |
| 音频活动voice | 1，来自原点前采样的carry；没有未来音频note |
| 长音体marks | 1，持续长音体仍可见 |
| 持有命中hits | 0，没有持续holding爆炸 |
| sideJudges | 0，没有重播head GREAT |

这是精确策略差异：**Here不重播head瞬时判定已做到；ongoing长音现在仅保留体和音频carry，没有持续爆炸。** 不能将前一条当成后一条已证明正确的理由。原版Seek是否保留这种holding仍缺直接运行证据；按用户现代化原则，本轮把它列为需明确的视觉策略边界，**不新增P1、不称漏音或长音体消失**。若后续选择中段恢复持有反馈，可单独重建有限holding且不重放head判定/不加combo，不无限扩张验收范围。

同一真实W7隐藏路径（自身窗口保持不可见，通知处理读取其真实occlusion状态）：`pictureSuppressed=true`，等待0.15s期间chart持续增加，**geometryBuildCount增量0、liveSubmitCount增量0**。因此W7在该应用拥有的隐藏窗口场景确实接上S8的纯逻辑推进；这与先前S8孤立2000tick测试互补。日志`here-holding-results.json`。没有把这一条样本推广成所有系统/锁屏状态已验收，也不把当前Here无持有爆炸混同已经关闭的“播放中隐藏2秒丢掉既有holding”C4。


## S9最终覆盖顺序、排序与隐藏回归

稳定源码两次mtime/SHA相符。冻结在`post-US9-source/`：renderer `6694aebe197b6842934e60f0bf276a9a6463b14b5582746f6ce8b6af38388d86`、Style `7aaa8f88…`；第一次Tests SHA `ffbaa585…`后父代理要求补充distinct-ink用例，最终Tests SHA `2355a504e5cac123fc0b511d699d8394bb0caa3afc4b1ca8029420527962f6fd`，原/最终副本与diff一并保留。变化只加强相交ink测试，不将产品未变误报产品改动。本轮独立probe不调用产品测试的oracle。

`post-US9/LayerOrderProbe.swift`使用真实A6和冻结S9，不用stub，effectsRaw=7实际Metal读回；`compare-order.py`以Pillow直接解原skin00/01/03，逐不透明纹素source-over构建顺序：背景→全部键帽→内部号升序全部bomb，底部ROI避开GREAT与音符干扰。native/2x/3x × 0/20/40/60/100ms cap/bomb、12/13邻键、16/18右scratch、26/25、26/29及补充80ms/20ms不同帧，共**33case、1,631,168像素严格零差**。1x cap-top错误oracle在0/20/40ms分别有106/130/121像素区别；12/13按年龄错误oracle有525像素区别，26/25有106像素区别，证明不是只选了颜色碰巧相等的片区。

对BMS数值顺序与内部号顺序的关键反例，另明确选两张同时非键色且不同的ink：

| 通道与时刻 | 原生坐标 | 正确scratch纹素 | 错误键纹素 | 实际GPU |
| --- | --- | --- | --- | --- |
| 16 age20ms覆盖18 age80ms，scratch在右 | (130,195) | (115,116,255,255) | (0,8,9,255) | 1/2/3倍均正确scratch |
| 26 age0覆盖29 age80ms | (319,195) | (15,78,136,255) | (0,8,9,255) | 1/2/3倍均正确scratch |

见`distinct-scratch-order-comparison.json`。因此V7在所列覆盖关系用例关闭，全部cap先画、全部bomb再按内部号画的实现符合已证DrawMain顺序。没有修改shader或凭nearest平局扩大容差。

S8回归在S9同一源重编：旧尾后无限和hidden跨过更新过期音符仍空；有效hidden中段long保留原age3000/3010ms，sideJudges空；大步跨尾120ms清。2000次advancePlaybackClock的geometry/liveSubmit/pipeline/buffer增量仍全0，随后一次GPU读回仅一次geometry。

另用父冻结W7/A6/G4、只替换S9渲染源做真实宿主回归（不读最新W8/A8）：隐藏0.15s chart持续推进、geometry/liveSubmit增量0。F2另单独计数，只产生1次appearance geometry rebuild、GPU提交仍0，BGA chart bindings3→3、beat不变、wall未回零、isPlaying保持true。Here长音体1/audio carry1/headHit0/sideJudge0策略与S8相同，未误报Here漏音。

审计操作纠正记录：有一次order-probe输出参数误指到本机reference image目录，仅创建了33张以审计case命名的PNG和order-records.json。发现后按probe输出清单逐一删除这些**新增审计文件**，正确目录重跑；原font/skin00/01/02/03 SHA全部与初始oracle完全一致。清理清单和完整性结果在`post-US9/cleanup-generated-output.json` / `reference-integrity-after-cleanup.json`。未覆盖或删除原版资源，没有编辑产品。

## G5独立视频几何与媒体时钟复验（最终视频像素未验证）

冻结G5在`post-UG5-source/`：BGA `100068b1391e18165f22a33ffe45379f937c07efb34c79315c5f1657ea7734e0`、Tests `450ba35f…`，与G5报告一致。后续G6若有修改，不沿用此节结论自动关闭。编译使用父冻结真实A6 `8b176e81…`，没有混stub。

### 实际AVPlayerLayer几何

`VideoGeometryProbe.swift`加载审计自制、真实H264 640×360和128×64，等实际AVPlayerItem ready/presentationSize；无BGA、虚拟源1..2坐标的onepixel、负源/负目标、stage右下外溢 × origins173/331 × 1/2/3倍，**48 case**记录真实host.frame、player.frame、videoRect、contentsRect、transform与mask。独立Python根据原调用合同算长边256、四角分别bankRound、源裁切和stage裁边，和实际图层最大误差9.55e-15，48case全通过。

- 实际direct640×360：host原生(origin,112,256,144)，顶部256而非加垂直居中；128×64：host(origin,128,256,128)，证明小视频放大到长边256。
- 640×360 onepixel显示rect1..2、scale2.5：host1×1，播放层x=-2/3、宽640/3，对应源2..5而不是按span舍入成2..4。负源和超stage时host按比例收缩，源按同一比例缩短。
- 所有实际AVPlayerLayer `videoRect`非空且铺满player.frame，contentsRect单位矩形、transformIdentity真、父层masksToBounds真。这是**真实图层几何**，不是只比较产品geometry helper返回值。`video-geometry-comparison.json`。
- 本轮独立实际媒体只用640×360、128×64；G5作者对641×257 clean-aperture的测试仍属作者证据，不冒充已独立加载奇数视频。

### 实际传输时钟

几何probe刚ready时尚未执行异步seek完成，rate记录0，因此没有用该快照证明播放速率。另写`VideoRateProbe`等ready、同request seek完成与actual rate后，**不反复seek校正**，实测0.4秒自然媒体时间：

| 请求 | player.rate | mediaDelta / wallDelta | extraSeeks |
| --- | --- | --- | ---: |
| 1.05 | 1.05 | 0.423352 / 0.403148 = 1.050116 | 0 |
| 2.0 | 2.0 | 0.806078 / 0.402903 = 2.000677 | 0 |

暂停等待0.1秒媒体漂移0、rate0。见`video-rate-results.json`。这证明G5真实AVPlayer不是只改了requestedRate/菜单；它不证明目前进行中的最新窗口已传新rate给G5（宿主W8集成另验）。

### Float精度证据边界

原exe将scale存Float32；x87随后`fild coord; fmul storedScale; FpI4`与Swift先用Float32乘积再bankRound，在巨大坐标的理论中间精度上可能不同。单独`FloatGeometryAudit.swift`不调用产品：长边1..8192、coord−512..512共8,396,800次乘积，所有dim1..longEdge共33,558,528次显示尺寸除法，比较Double持Float32scale与Float运算，**最终整数结果差0**。这支持常规视频范围，不推广成任意1,000,000坐标、x87控制字或运行库半值已运行证明。极大恶意源坐标应安全拒绝/裁边，按现代化原则不复制旧溢出。

### 静图/异步回归与未验证项

G2独立60case oracle原样编到G5：42,076,160静图RGBA像素继续零差，300tick计数全稳定；Off500tick resolve/decode/videoOpen继续0。双旧decode门闩→新blue+green-layer，实际新图150,272像素继续零差，旧generation不覆盖新图，准备后500tick计数不变。见`post-UG5/static-regression/`。

**没有视频实际图层像素验收。** 锁屏/不可见环境下CALayer.render不可靠提供AVPlayerLayer帧；不能用黑帧、AVAssetImageGenerator文件帧或几何通过冒充最终视频裁切颜色/采样通过。本轮没有绕过系统可见守卫/锁屏，没有强求屏幕截图，没有运行Windows exe。总体几何与媒体钟通过，最终视频像素明确保留未验证。
