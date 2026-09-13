# BMS 谱面批次验证报告

本批次验证普通音符的事件模型、编辑、撤销/重做和保存。实现由 Terra 负责，独立回归由 Luna 负责。当前结果已经覆盖本批次的源代码规则和合成谱面；父任务的最终 Debug、Release、ASan 以及 GUI 验证已经有结果，具体证据见下文。

## 验证范围

本批次只覆盖普通音符模型和相关编辑操作。普通通道共 16 个：`11`–`16`、`18`、`19`、`21`–`26`、`28`、`29`。`17` 和 `27` 不属于普通 8 键映射，测试会把它们保留为未知事件，不能把它们当作额外轨道。

源映射来自 `iBMSC/iBMSC/EditorColumns.vb:147-175`。源解析行为来自 `iBMSC/iBMSC/ChartIO.vb:175-248`。对应的独立证据和 10 个无资源合成 fixture 记录在 [`docs/inventory/bms-note-cases.md`](../inventory/bms-note-cases.md) 和 [`tests/fixtures/bms-chart/manifest.json`](../../tests/fixtures/bms-chart/manifest.json) 中。

事件位置使用精确的 `measure_fraction` 和 `absolute_quarterbeats`。不同通道在同一个小节和槽位上的事件共享坐标，事件列表顺序不会推进时间。fixture `01` 覆盖 1P 和 2P 的 16 个普通通道；fixture `02` 覆盖三等分和 12 格；fixture `03` 覆盖比例 `0.5` 和 `1.5`；fixture `04` 覆盖重复 BGM 行和同一普通通道的不同位置；fixture `05` 覆盖 BOM、混合换行和无末尾换行；fixture `06`–`10` 覆盖 LNOBJ、长音符、条件分支、损坏行和 `G1` 进制边界。

## 源网格和方向

旧版 VB 编辑器的 `MainWindow.vb:293-297` 使用固定公式：

```vb
xRatio = 192.0R / gDivide
Return Math.Floor((xVPos - xOffset) / xRatio) * xRatio + xOffset
```

这条规则是在当前小节内向下取整，不是把每个小节按比例重新切成若干段。默认 `gDivide=16`，每格是 `192/16` 个 VB 单位，也就是 `4/16` 个四分音符。比例为 `0.5` 的小节有 8 个格，比例为 `1.5` 的小节有 24 个格。`MainWindow.vb:275-277` 的坐标换算表明，时间从面板底部向顶部增加。默认网格和吸附开关见 `MainWindow.designer.vb:1840-2083`。

普通音符的写入和选择行为取自 `PanelEvents.vb:515-625`、`PanelEvents.vb:1356-1496` 和 `PanelEvents.vb:1587-1674`。删除行为取自 `MainWindow.vb:4092-4105`。这些引用用于建立源行为基线，不代表本批次已经完成旧版全部编辑功能的复刻。

## 当前实现和独立测试

当前核心接口见 [`core/include/ibms/bms_document.hpp`](../../core/include/ibms/bms_document.hpp) 和 [`core/include/ibms/bms_chart.hpp`](../../core/include/ibms/bms_chart.hpp)。谱面解析、事件分类、条件分支只读条件、普通通道校验、精确小节拍点和只读诊断见 [`core/src/bms_document.cpp`](../../core/src/bms_document.cpp)。核心使用 `BeatPosition` 保存分数。事件的 `token` 使用规范化的大写形式；原始字节另行保留，用于无损序列化。

Luna 的独立测试源是 [`tests/bms_chart_fixture_test.cpp`](../../tests/bms_chart_fixture_test.cpp)。它通过命令行参数 `argv[1]` 接收 fixture 目录，不读取测试构建宏，也不修改 CMake。测试手工写出 10 个 fixture 的事件期望，并逐项比较小节、通道、token、分数位置、绝对拍点和事件类型。它还检查原始字节回读、条件谱面空事件、`17/27` 未伪装成普通轨道，以及 `#00003:G1` 按十六进制拒绝而 `#00011:G1` 按三十六进制保留。

独立测试还覆盖以下编辑约束：

- 无末尾换行的文件追加和移动后，新增行仍按正确通道和 token 解析，文件头不会被拼接破坏。
- 小写原始 token `#00011:g100` 经过删除、移动和撤销后，原始大小写完全恢复。
- 源位置不存在时，同位置移动会拒绝，且不改变字节、脏状态和历史。
- 目标位置已有普通音符时，移动会拒绝，并保留原有 redo 历史。
- 移动和元数据修改共享历史；保存点前后的 undo/redo 会正确改变脏状态。
- 超大 `#mmm02` 比例超过 `BeatPosition` 可表示范围时，谱面返回只读诊断，原始字节仍可序列化。

当前独立回归命令为：

```text
c++ -std=c++20 -Wall -Wextra -Icore/include \
  tests/bms_chart_fixture_test.cpp core/src/bms_document.cpp \
  -o /tmp/ibms-chart-independent
/tmp/ibms-chart-independent tests/fixtures/bms-chart
```

当前磁盘状态下，10 个 fixture 和上述独立编辑回归均已通过。测试源单独使用 `-Wall -Wextra -Wconversion -Werror` 编译也已通过。父任务最终回归结果如下：

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Debug CTest | 7/7 通过 | `out/build/debug` |
| Release CTest | 7/7 通过 | `out/build/release` |
| 严格编译、ASan 和 UBSan | 4/4 通过 | `/tmp/ibms-chart-parent-sanitize`，使用 `-Wall -Wextra -Wconversion -Werror`、ASan 和 UBSan；父任务已重新运行确认 |
| Luna 独立谱面回归 | 通过 | `/tmp/ibms-chart-independent tests/fixtures/bms-chart` |

## 旧版差异和只读条件

新模型遇到目标碰撞时会拒绝移动，并保持字节和历史不变。旧版 `PanelEvents.vb:1647-1664` 会先删除目标位置的旧音符，再写入新音符；这属于有意保留的行为差异，不能把新模型的拒绝误报成旧版覆盖兼容。

`#RANDOM`、`#IF` 等条件指令会让谱面只读，且不暴露未经选择分支的事件。无效或含歧义的 LNOBJ/长音配对、受支持通道的损坏行、受支持通道的非法 token 和超出拍点表示范围的比例会产生只读诊断；有效长音配对由独立的长音批次覆盖。fixture `06`–`10` 专门记录普通音符批次中的边界源输入，不把它们当成长音兼容性证明。

## GUI 验证和待确认项

父任务在最终 workspace Debug 应用中验证了写入、跨轨拖动、目标音符变为黄色选中状态后立即 Delete、Undo、Redo 和 Save。音符 token `01` 已完整显示；当前使用 7 pt fitted font，这项只说明文字可见，不代表像素一致性。

同一轮验证中，连续三次 Undo 可以回到新建文档的干净状态。重新打开 `out/ui-audit/chart-ratio-audit.bms` 后，6 个音符的位置正确，Undo 和 Redo 均保持禁用。滚轮滚动条位置按 `1 → 0.9960178101091183 → 1` 变化，Both 模式显示 16 条普通轨道。

此前同批次的 GUI 验证还覆盖了 Delete、Undo、Redo 和 Save。离网格 `1/3` 的简单点击不会生成历史。短小节使用网格 16 在槽位 7 写入通道 `13`，随后 Save As；独立字节比较确认输出保留源文件字节，并追加 `#00113:0000000000000001`，对应分数位置 `7/8`、绝对拍点 `23/4`。

当前原生界面只绘制普通音符轨道。其他对象会计数；发现问题时显示诊断，但本批次没有加载音频资源。标签在 7 pt fitted font 下已验证完整显示；这不代表像素一致性。

移动音符后的选中修复已完成并通过验证。实现使用移动前后的 `sourceLine` 身份定位记录，移除了浮点 epsilon 和 `Double` 无变化保护。接近已有音符的精确分数 `10000000001/20000000000` 回归已通过。

最终 GUI 验证中，写入、跨轨拖动后 Delete 可得到 0 个音符；Undo 后执行同位置的刻意拖动，Redo 仍可用且没有新增历史，随后 Delete 仍然有效。连续三次 Undo 可以回到新建文档的干净状态。

父任务已重新构建 Debug 和 Release，两个套件最终均为 7/7 通过，并完成 ASan、UBSan 和 GUI 验证。当前报告仍不覆盖 LN 播放、BMSON、音频、任何工具集成、完整格式兼容、全屏像素一致性或性能指标，也不对这些能力作实现声明。

构建过程中记录到重复 `-lc++` 链接警告，以及一次瞬时的 Debug PCH 缺失警告。这些警告没有阻断上述结果，单独记录为技术备注，不作为功能通过依据。
