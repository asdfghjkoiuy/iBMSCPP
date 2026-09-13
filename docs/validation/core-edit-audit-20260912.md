# 编辑边界审计记录

审计日期：2026 年 9 月 12 日

审计范围：`core/src/bms_document.cpp`、`macos/Sources/IBMSBridge/IBMSDocumentBridge.mm`、`DocumentSession.swift`、`BmsONEDocument.swift`。

## 已确认并已修复的问题

| 位置 | 触发样本 | 结果 | 严重程度 | 覆盖情况 |
| --- | --- | --- | --- | --- |
| `core/src/bms_document.cpp:1897-1908` | `move_note` 的 source 与 destination 完全相同，source 位置没有音符 | 旧代码提前返回，错误地把不存在的 source 当成成功；现在先检查 BGM 或普通音符 source | 中 | `ibms_bms_document_tests` 已通过；普通音符路径有测试，BGM 与扩展通道仍依赖现有核心测试覆盖 |
| `macos/Sources/IBMSNative/BmsONEDocument.swift:2042-2059` | `moveBpmNote(from: 999, to: 120, bpm: 150)` | 先写入新 BPM，再删除不存在的旧 BPM；旧代码会留下新 BPM。现在失败时恢复编辑前 JSON | 高 | `BmsONEDocumentTests` 已新增回归测试；目标受 `BmsonChannel.swift` 既有编译错误阻塞 |
| `macos/Sources/IBMSNative/DocumentSession.swift:93-109` | compound 内先成功插入，再由调用方抛错 | bridge bytes 已回滚，但 Swift 的三套快照可能停留在中间状态；现在恢复编辑前 chart、long note、timing 快照 | 高 | `DocumentSessionTests` 已新增回归测试并通过 |

## 边界检查结果

`bms_document.cpp` 的通道行解析在 `parse_channel_row`（约 314 行）限制单行槽数，避免按恶意槽数直接分配无限长度。`make_sparse_note_row`（约 867 行）按已有行和目标分数生成内容，目标坐标在公开编辑入口先经过 `validate_note_coordinate`。当前审计没有复现整数溢出或无界单行分配。

核心保存和撤销路径使用 `Patch` 保存修改前后的字节。`commit_normal_note_patch` 及 timing、长音相关提交会把修改写入 history；独立核心文档测试已覆盖普通音符写入、撤销和保存报告。没有发现静默丢失用户字节的可复现样本。

`IBMSDocumentBridge.mm` 将 C++ 异常转换为 `NSError`，编辑调用点均检查返回值。当前没有发现 bridge 成功返回但 Swift 忽略错误码的新增路径。资源列表和 metadata 失败路径由 `DocumentSession` 在写入后刷新快照；本次未修改这些行为。

`BmsONEDocument` 的 `commitEdit` 在成功时才追加 undo、清空 redo 和设置 modified。失败时保留 file path、clean JSON 与 history，并恢复 bridge。`commitEditRestoring` 已改为调用统一实现，避免二次恢复。

## 测试边界

- 独立目录 `out/build/sidebar-audit2` 中，`IBMSNativeSessionTests` 和 `ibms_bms_document_tests` 构建、运行通过。
- `IBMSNativeBmsONEDocumentTests` 已构建并运行通过，包含缺失旧 BPM 的事务回滚测试。
- 尚未对超大文件（超过数百 MB）、极端 measure 编号和极端 JSON 深度进行压力测试；本记录不把这些未测试场景推断为缺陷。
- `BmsonChannel.swift:407-430` 的 long interval cache 索引使用 `upperBound`，并以 `Int.max` sentinel 处理末尾；边界检查未发现越界。`mixed`（约 826-858 行）明确只取起始 packet，跨 packet 区间按原版语义只处理起始包，当前没有可复现的索引错误。

## 审计结论

除表中三个已确认问题外，本次范围内没有发现新的、可复现的边界或保存缺陷。BMSON 回归目标和长音布局目标均已在独立目录中通过。

## Bmhelper 子窗口中文与尺寸复核

本次只读检查了三个窗口控制器，没有修改产品代码。

| 文件与位置 | 英文残留 | 尺寸风险 |
| --- | --- | --- |
| `BmhelperMidiWindowController.swift:18-37, 51-80` | 标题、`Tracks (&T):`、`Channels (&C):`、`OK` 来自 `BmhelperMidiImportLayout`；通道编号是协议显示值，不应翻译 | `BmhelperMidiImportLayout.clientSize` 为 290 × 130，`tracksChoice` 宽 185，中文化后的标题若直接替换可能超出 85 px 标签区；窗口设置了固定最小和最大尺寸 |
| `BmhelperDivisionWindowController.swift:76-123` | 窗口标题、Name、MIDI settings、Leading silence、Sorting method、Definition settings、OK/Cancel 等全部来自 `BmhelperDivisionSettingLayout`，控制器没有调用 `NativeLocalization` | 客户区固定 330 × 455；160 px 标签区和 146 px 输入区对较长中文标签有裁剪风险，按钮区仅 76 px |
| `BmhelperAudioSplitterWindowController.swift:61-85, 118-187` | Audio File、拖放提示、Browse、Output Directory、Slice Parameters、Split、Close，以及两个选择面板提示和错误标题均来自 `BmhelperAudioSplitterLayout`，控制器未调用 `NativeLocalization` | 客户区固定 800 × 360；按钮宽 80/90 px，中文按钮一般可容纳，780 px 拖放提示标签可用；错误标题和动态 division name 仍可能超过窗口标题栏，但不影响客户区 |

上述英文 key 应交给 `audio_tools` 接入本地化。`BmhelperMidiImportText.trackChoice` 产生的轨道名和 `channelTitle` 的十六进制通道号属于输入数据或协议值，审计建议继续保留原文。

## 长音区间索引复核

`ChartLayout.swift:1399-1486` 的 `LongNoteIntervalIndex` 以长音起止拍的最小值和最大值建立区间树。叶节点保存原数组下标，查询结果最后排序，因此绘制顺序与旧数组一致；hit test 再反向遍历，保留后画优先命中规则。

`ChartLayout.swift:1404-1411` 使用闭区间重叠判断，长音恰好落在视口端点时会被查询。空数组的根节点为 `nil`，查询返回空数组。跨视口长音按起止拍范围命中，再由 `visibleLongNoteRects` 检查 body、outline、startCap、endCap 是否与视口相交。`hitTestLongNote` 使用同一拍容差查询，并分别检查起点、终点和主体。

现有 `ChartLayoutTests.swift:960-1009` 已覆盖跨视口长音、原数组逆序命中和长音端点 hit test。独立目录 `out/build/sidebar-audit2` 中 `IBMSNativeChartLayoutTests` 已构建并运行通过。此次只读复核没有发现空集合、端点或索引越界问题。

## 全应用固定文案覆盖审计（2026-09-12）

按实际控件构造检查 `macos/Sources/IBMSNative`。以下只列未登记或未调用本地化的固定界面文案，文件名、路径、命令、谱面值和协议字段不算遗漏。

- **BMS 导入窗口**：`BmsONEImportWindowController.swift:20, 56, 59-65, 70, 130, 205-208, 299, 348, 392` 直接设置 `BMS Import`、`Loading BMS...`、`Skip Questions`、`Next`、`Cancel`、`Random`，控制器没有调用 `NativeLocalization.localize(window:)`。建议补这些键；`O` 是游戏模式标记，应保留。
- **外部查看器**：`BmsONEExternalViewerDialog.swift:69, 92-95, 101-127, 136-142, 301-338` 虽登记窗口并递归扫描，但 `Name:`、`Program Path:`、`Working Directory:`、`Arguments`、播放标签、`Defined variables`、变量说明和 `Up/Down/Remove/Add` 工具提示没有完整词典键。`$(filename)` 等变量占位符必须保持原样。
- **woslicer 独立窗口**：`WoslicerWindowController.swift:13, 49-58` 构造标题和三段说明，没有本地化调用；说明已经是中文，`woslicer II / III` 是工具名，是否翻译需产品明确。
- **BMSON 主窗口菜单**：`BmsONEWindowController.swift:189-247` 自建菜单没有在构造末尾调用 `NativeLocalization.localize(menu:)`。`New`、`Open...`、`Save`、`Save As...`、`Export WAV...`、`Grid Setting` 等固定项需要登记；文件名、文档标题、BMS/BMSON 字段和通道名保持原值。
- **MyO2 工具箱**：`MyO2WindowController.swift:20, 89-94` 的标题、标签和按钮已经是中文，但没有登记，因此切到英文时不会还原。若要全窗口支持切换，应显式绑定这些中文源键；表格谱面值保持不变。

已确认接入窗口包括 Find、General Options、Player Options、ColorPicker、Timing、BMS ONE Extra Dialogs、SM 导入和加载进度窗口；状态条、时间选择条和时序通道中的数值及协议标识不翻译。
