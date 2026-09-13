# BMS I/O 合成夹具

本批次加入 6 个很小的 BMS 字节夹具。它们只使用合成标题、作者和音频文件名，不包含受版权保护的真实音乐内容。每个文件的字节长度和完整 `SHA-256` 都记录在 [`tests/fixtures/bms/manifest.json`](../../tests/fixtures/bms/manifest.json) 中。

这些文件用于固定输入字节、编码、换行、条件文本和异常通道行。`manifest.json` 把新核心期望和原始 VB 行为说明分开记录。它们是测试数据，不是原始程序兼容性通过证明。当前没有新增测试代码，也没有修改 `tests/CMakeLists.txt`。

## 源码锚点

本批次依据本地 µBMSC 提交 `f5b21d1de50ce28202d1b2e8d2f614fabde18092`。相关源码位置如下：

| 来源 | 已观察规则 | 夹具用途 |
| --- | --- | --- |
| `iBMSC/iBMSC/MainWindow.vb:58`、`:975-978` | 默认 `TextEncoding` 是 UTF-8；常见 BMS 文件通过该编码传给 `ReadAllText`，再进入 `OpenBMS`。 | UTF-8 BOM 与 Shift-JIS 样本必须分别记录编码条件，不能把默认 UTF-8 当成 Shift-JIS 证据。 |
| `iBMSC/iBMSC/ChartIO.vb:4-10` | `OpenBMS` 先把 `LF`、`CR` 和重复换行归一化为 `CRLF`，再按 `CRLF` 拆行。 | `01-mixed-endings-no-final-newline.bms` 固定原始换行和末尾状态，检查源码路径对字节边界的影响。 |
| `iBMSC/iBMSC/ChartIO.vb:13-21` | 读取开始时重建音符、通道和索引数组，并初始化新谱面和打开谱面状态。 | 每个样本都包含最小可识别的标题、BPM、WAV 或通道数据，便于区分初始化失败和解析差异。 |
| `iBMSC/iBMSC/ChartIO.vb:52-81` | `#WAV`、`#BMP`、索引 BPM、STOP、SCROLL 和元数据按 `StartsWith` 分支解析；`#TITLE` 分支也使用此前缀判断。 | `04-duplicate-headers-titleimage-boundary.bms` 保留重复 `TITLE` 和 `TITLEIMAGE` 边界，等待运行时确认实际字段结果。 |
| `iBMSC/iBMSC/ChartIO.vb:147-165`、`:226` | 未识别的 `#` 行会进入 `xExpansion`；`IF/ENDIF`、`SWITCH/ENDSW` 和 `SETSWITCH` 会改变 `xStack`；最后写入 `TExpansion.Text`。 | `05-nested-random-if-unknown-directives.bms` 检查分支内元数据、未知指令和 `RANDOM` 外层的实际处理。 |
| `iBMSC/iBMSC/ChartIO.vb:172-211` | 第二遍只处理形如通道行的内容；未映射通道会跳过；非 `00` 单元创建音符，并对 03、08、09、SC 使用专门的值来源。 | `06-malformed-channel-valid-records.bms` 把过短通道行和有效 WAV、BPM、STOP、03/08/09/11 记录放在一起。 |

## 夹具目录

| 文件 | 字节与编码重点 | 新核心期望 | 条件标记 |
| --- | --- | --- | --- |
| `01-mixed-endings-no-final-newline.bms` | ASCII；混合 `CRLF`、`LF`、`CR`；无末尾换行。 | `loadable=true`、`raw_round_trip=true`、`editable=true`。 | `false` |
| `02-utf8-bom-metadata.bms` | UTF-8 BOM；中文元数据；末尾有 `LF`。 | `loadable=true`、`raw_round_trip=true`、`editable=true`。 | `false` |
| `03-shiftjis-japanese-metadata.bms` | 真实 Shift-JIS 日文元数据字节；`CRLF`。 | `loadable=true`、`raw_round_trip=true`、`editable=true`；原始字节读取不依赖 UI 解码设置，显示文本依赖选定编码。 | `false` |
| `04-duplicate-headers-titleimage-boundary.bms` | 重复 `#TITLE`，并紧邻 `#TITLEIMAGE`。 | `loadable=true`、`raw_round_trip=true`、`editable=true`；精确指令匹配得到 `TITLE=Second`。 | `false` |
| `05-nested-random-if-unknown-directives.bms` | 嵌套 `RANDOM/IF`；分支内元数据；未知指令。 | `loadable=true`、`raw_round_trip=true`、`editable=false`；`expected_metadata_hex=null`。 | `true` |
| `06-malformed-channel-valid-records.bms` | 过短 `#00111:0` 与有效头字段、通道记录并存。 | `loadable=true`、`raw_round_trip=true`、`editable=true`。 | `false` |

## 原始字节边界

`manifest.json` 的 `raw_prefix_hex` 只展示每个文件的前 32 个字节；`byte_length` 和 `sha256` 钉住整个文件。`expected_header.display_source_text` 是用于人工查看的整文件解码文本，使用显式的 `\\r`、`\\n` 转义。`expected_metadata_hex` 才是新核心对最后一个精确匹配元数据指令的字节期望；条件夹具 05 使用 `null`，表示不评估分支元数据。

原始 VB 路径不会自动保留原始字节：`ChartIO.vb:8` 会先改写换行，`ChartIO.vb:164` 会把扩展文本按 `vbCrLf` 重新拼接。这些观察已经移到每个条目的 `original_behavior_notes`。新核心的 `raw_round_trip=true` 是本夹具清单的目标期望，不是对原始 VB 行为的结论。

## 交接状态

夹具已经写入 `tests/fixtures/bms/`，核心工作线程可以直接读取 `manifest.json`。下一步需要在实际读取路径中核对编码、条件文本、异常通道和保存结果；这批数据本身不替代运行时验证。
