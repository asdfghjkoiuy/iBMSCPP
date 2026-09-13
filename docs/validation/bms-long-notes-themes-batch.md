# 长音与 IIDX 主题批次报告

本批次验证 BMS 长音的读取、配对、位置编辑、冲突拒绝和撤销重做，并记录 IIDX 风格主题资料与当前原生实现边界。长音部分由 Luna 建立独立 fixture 和测试；核心接口由 Terra 提供。主题界面仍由父任务验证，本报告不提前给出 GUI 结论。

## 已完成的长音范围

[`tests/fixtures/bms-long-notes/manifest.json`](../../tests/fixtures/bms-long-notes/manifest.json) 包含 8 个无音频、无图片资源的手工 BMS 文件。每个文件都记录字节长度和 SHA-256，当前回读校验全部通过。覆盖内容包括：

- `#LNTYPE 1` 的 51/61 通道长音、首尾 token 不同、跨小节倍率 `0.5` 和 `1.5`；
- 同位置重复端点、孤立端点、相邻配对、普通音符重叠和不同列的区间交叠；
- `#LNOBJ ZZ` 的普通音符头、保护标记尾、独立 `#WAV01` 声明、重复标记和区间外普通音符；
- BOM、混合 CRLF/LF/CR、无末尾换行，以及插入长音后的撤销和重做字节恢复；
- 已有 `0→4`、`6→8` 配对上的嵌套插入和越界改尾拒绝；完整 `0→4` 配对移动到 `4→8` 并保留首尾 token。

有效配对的 `chart` 和 `long_notes` 保持可编辑。普通音符编辑会重新验证配对：区间外普通音符可以写入，区间内插入、占用 LNOBJ 头尾、使用保护标记造成重新配对的操作会拒绝。重复、孤立、重叠或歧义配对保留源事件，同时给出诊断并保持只读。这里没有把只读结果写成完整兼容。

独立程序为 [`tests/bms_long_note_fixture_test.cpp`](../../tests/bms_long_note_fixture_test.cpp)，接受 fixture 目录参数，直接比较原始事件、规范化 token、精确小节分数、绝对拍位置、源行号、配对编码和字节历史。父任务已报告核心长音套件 `8/8` 通过；本地独立测试也已在严格 `-Wall -Wextra -Wconversion -Werror` 编译下运行通过，并完成 ASan/UBSan 运行。

## 原版来源

原版 μBMSC/iBMSC 固定提交为 [`f5b21d1de50ce28202d1b2e8d2f614fabde18092`](https://github.com/zardoru/iBMSC/tree/f5b21d1de50ce28202d1b2e8d2f614fabde18092)：

- [`ChartIO.vb:132-140`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L132-L140) 读取 `#LNTYPE` 和 `#LNOBJ`；
- [`ChartIO.vb:172-205`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L172-L205) 按源行槽位建立音符，长音来自通道，LNOBJ 尾端来自普通音符 token；
- [`ChartIO.vb:251-282`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L251-L282) 和 [`ChartIO.vb:352-374`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L352-L374) 记录长音配对、非标准小节倍率和两种写回头部；
- [`MainWindow.vb:1194-1255`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L1194-L1255) 检查同列重复、未匹配、普通音符重叠和 LNOBJ 标记；
- [`MainWindow.vb:2759-2839`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L2759-L2839) 展示长音端点与内部长度之间的转换。

这些源码是行为基线，不是当前核心或原生界面的二进制等价证明。

## IIDX 风格主题资料与界面状态

主题资料以 [`docs/inventory/mubmsc-themes.md`](../inventory/mubmsc-themes.md) 为准，并对照固定提交中的 `iBMSC/misc/Data/IIDX.Theme.xml`。该资料覆盖列宽、列标题、普通音符和长音颜色、字体、音符高度、网格及选择颜色等外观字段；`ChartTheme` 的范围校验和原始主题资源路径也已记录。主题模型只处理外观数据，不改变 BMS 通道、长音配对、撤销记录或播放语义。

父任务最终验证结果为：Debug `13/13`（1.73 秒）通过，Release `13/13`（6.08 秒）通过；独立 `/tmp/ibms-ln-parent` 在 `-Wall -Wextra -Wconversion -Werror`、ASan/UBSan 下长音套件 `8/8`（5.00 秒）通过。结果包含最新原生修复和测试。

回归覆盖了长度为 `4/3` 拍的长音移动到 1.5 倍率小节（使用 16 分网格）：尾端保持 `7/18`，通道保持 `52`；也覆盖会话移动、改尾、删除、撤销、保存后重新打开，以及同一行 LNOBJ 普通音符仍可见并可命中。原生修复已由父任务审阅：显示时按源端点的准确位置识别长音，选中边框在音符渐变之后绘制，选中长音颜色在 Metal 和回退绘制路径中保持一致。

本批次没有取得实际 GUI 观察结果。第三次 CUA 尝试仍遇到 macOS 锁定，因此不能把主题选择、列宽显示、长音绘制、交互布局或像素结果写成 GUI 已验证，也不作像素一致性声明。

已记录的主题实现边界包括：编辑器可切换 1P、2P 和 Both，列宽为 `0` 时隐藏列；侧边选择状态会覆盖保存的 `Display` 值。ThemeController 的新实例恢复和无效保存值回退已经测试。父任务已在实际 app bundle 中核对 8 个内置主题资源，并与固定原始资源逐字节一致；这项资源校验不等于 GUI 渲染等价。

当前已知外观差异包括主题渐变仍使用连续垂直渐变，而原版使用对角线采样点。字体、全部列、完整绘制功能和其他视觉细节没有作完整像素审计，不能据此宣称像素完美或只剩这一项差异。`#LNTYPE 2` 和混合长音编码仍保持只读。

当前界面的操作路径记录如下：选择 Long Note 工具，或在 Write 模式按住 Shift 拖动建立长音；在 Select 模式拖动长音主体移动，拖动首尾端点调整长度，按 Delete 删除；通过 Theme 菜单选择内置主题、导入或导出 `Theme.xml`，启动时恢复上次主题。由于本批次没有解锁后的 GUI 观察，这些是当前实现的操作说明，不是本批次的现场 GUI 通过记录。

BMSON、音频播放、完整编辑器行为、插件和其他工具集成也不在本批次结论内。
