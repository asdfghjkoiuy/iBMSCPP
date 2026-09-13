# 长音来源与编辑用例清单

本批次只覆盖长音位置、端点配对、普通音符冲突、原始字节保存以及撤销重做。fixture 全部是手工构造的无资源 BMS；`#WAV01 sample.wav` 只是检验 `#LNOBJ` 尾标记不等于 WAV 定义，目录中没有音频文件。每个 `.bms` 的字节长度和 SHA-256 都记录在同目录的 [`manifest.json`](../../tests/fixtures/bms-long-notes/manifest.json) 中，并由独立测试按原始字节读取。

当前测试使用 Terra 线程 `01a076c8-bce7-7e81-9057-1e583e4fef8d` 发布的 `BmsDocument::chart()`、`long_notes()`、`insert_long_note`、`move_long_note`、`resize_long_note`、`erase_long_note`、普通音符编辑和撤销重做接口。测试把 `chart.events` 当作原始行事件视图，把 `BmsLongNotes` 当作经过校验的长音配对视图；长音配对未通过校验时，仍检查原始端点和诊断，而不会把部分结果当成完整兼容。

有效的 51/61 配对和有效的 LNOBJ 配对保持 `chart` 与 `long_notes` 可编辑；长音端点不会把整个谱面自动设为只读。普通音符编辑仍须重新验证配对，只有会占用长音区间、改变 LNOBJ 头尾或引入歧义的操作才拒绝。

## fixture 覆盖

| 文件 | 具体覆盖 | 手工预期与边界 |
|---|---|---|
| `01-lntype-cross-ratio.bms` | `#LNTYPE 1`、51 通道、跨小节倍率 `0.5`/`1.5`、首尾 token `01`/`ZZ`、混合换行、无末尾换行 | 头端在 `(小节0,0)`，尾端在 `(小节1,1/2)`，绝对拍位置为 `0` 和 `5`；端点 token 不要求相同。 |
| `02-duplicate-unmatched.bms` | 同位置重复端点、51 通道未成对、61 通道孤立端点 | 保留四个源事件。同拍重复仍让配对视图为空、只读。单独不成对的端点只记诊断，不把谱标成只读。 |
| `03-overlap-crossing-lanes.bms` | 51/61 两条交叠长音，11/21 普通音符位于对应长音区间内 | 保留七个源事件和两条候选配对；普通音符重叠使配对视图只读。不同列的区间交叠不合并。 |
| `04-lnobj-marker-not-wav.bms` | `#LNOBJ ZZ`，11 通道普通头和 `ZZ` 尾，区间外普通音符，独立 `#WAV01` 声明 | `01`→`ZZ` 形成 LNOBJ 配对；WAV 声明不生成谱面事件。区间外普通音符可编辑，区间内插入和新建 `ZZ` 标记应拒绝。 |
| `05-lntype-mixed-bom-edit-undo.bms` | UTF-8 BOM、CRLF/LF/CR 混合换行、无末尾换行、只有 `#LNTYPE 1` 的普通音符 | 插入长音后撤销必须恢复全部原始字节；重做再次得到一条有效配对。没有端点时不虚构长音。 |
| `06-lnobj-duplicate-marker.bms` | 有效 LNOBJ 配对后再次出现无新头的 `ZZ` 标记 | 保留三个普通源事件和首个部分配对；重复标记导致只读与诊断。 |
| `07-placement-guards.bms` | 两个 51 配对 `0→4`、`6→8`，嵌套插入 `1→2`，以及越过邻接配对的改尾 | 插入不得把原来的配对静默重分成 `0→1`、`2→4`；越界改尾必须原子拒绝。 |
| `08-single-pair-move.bms` | 一个首尾 token 不同的 51 配对 `0→4` | 整体移动到 `4→8`，旧位置腾空，首尾 token 保持不变。 |

`fraction` 是小节内相对位置，`beat` 是按 `#mmm02` 倍率展开后的绝对拍位置。事件 token 在模型中按大写规范化；原始大小写仍由 `serialize()` 保存。`source_line` 使用零基物理行号，BOM 不额外占一行。

## 原版 VB 证据

原版固定提交为 [`f5b21d1de50ce28202d1b2e8d2f614fabde18092`](https://github.com/zardoru/iBMSC/tree/f5b21d1de50ce28202d1b2e8d2f614fabde18092)，以下链接均固定到该提交：

- [`BMS.vb:4-7`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/BMS.vb#L4-L7) 将数值在 50 到 89 的通道标为长音候选；具体键位映射仍受通道表限制。
- [`ChartIO.vb:132-140`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L132-L140) 读取 `#LNTYPE` 和 `#LNOBJ`，`#LNOBJ` 用 base36 转换，并保留了待验证注释。
- [`ChartIO.vb:172-205`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L172-L205) 按小节、通道和槽位生成音符；是否为长音来自通道，`#LNOBJ` 尾标记来自普通音符 token，不能从 WAV 声明推导。
- [`ChartIO.vb:251-282`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L251-L282) 写回时先计算配对，再按小节输出，并为非 192 基准小节写出 `#mmm02`。
- [`ChartIO.vb:352-374`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L352-L374) 写回 `#LNOBJ <base36>` 或 `#LNTYPE 1`；这说明两种编码是写回选择，不是同一种源格式。
- [`MainWindow.vb:1194-1255`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L1194-L1255) 的 `UpdatePairing` 按同一编辑列寻找端点，检查同位置重复、无匹配、普通音符重叠和 LNOBJ 标记；本批次的重复、未匹配、交叠 fixture 直接对应这些分支。
- [`MainWindow.vb:2759-2839`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L2759-L2839) 展示 BMS 端点与内部长音长度之间的读写转换：长音端点可合成为长度，保存时又拆回首尾端点。

原版源码只证明上述读取、配对和写回路径；它不证明当前核心、新原生界面或 IIDX 风格皮肤已经达到二进制等价、交互等价或视觉等价。

## 独立测试边界

[`tests/bms_long_note_fixture_test.cpp`](../../tests/bms_long_note_fixture_test.cpp) 独立检查：

- 八个 fixture 的原始事件、规范化 token、精确小节分数、绝对拍位置、源行号和长音编码；
- 51/61 长音的跨小节移动、改尾、删除，以及撤销后完整字节恢复；
- UTF-8 BOM、混合换行、无末尾换行在长音编辑撤销/重做中的保留；
- LNOBJ 区间外普通音符可编辑，区间内普通音符、移动头端、删除尾端和新建保护标记会被拒绝；LNOBJ 的移动和删除只能走长音接口；
- 发生重复、孤立、普通音符重叠或重复 LNOBJ 标记时，原始事件仍可见，同时配对视图给出诊断并保持只读。
- 两个已有配对之间插入新 51 配对时，测试检查不会静默改写端点归属；改尾越过相邻配对会原子失败；整条配对移动会同时移动头尾并保留 token。
- LNOBJ 头尾附近插入普通音符或保护标记会拒绝，避免把已有普通头错误地重新配对；头尾的移动和删除只通过长音接口进行。

测试文件接受一个 fixture 目录参数，暂不修改 CMake；核心工作者负责注册并在其发布的实现上运行。这里没有声称 BMSON、播放、音频资源、完整皮肤、像素一致性或所有 BMS 扩展已经兼容；这些内容留在后续批次。

本次在当前工作树上直接编译运行通过：8 个 fixture 全部通过，严格 `-Wall -Wextra -Wconversion -Werror` 编译通过，独立 ASan/UBSan 运行通过。CMake 注册仍由核心工作者处理。
