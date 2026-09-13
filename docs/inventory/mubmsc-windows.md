# µBMSC 窗口与布局初始清单

这是一份有边界的源码清单。它覆盖本地 µBMSC 提交 `f5b21d1de50ce28202d1b2e8d2f614fabde18092` 中的主窗体、`Dialogs/*.Designer.vb` 和 `Option Windows/*.Designer.vb`。我检查了窗体声明、控件声明、文字、默认值、字体、停靠和锚点；没有把这些观察写成完整行为审查，也没有声称截图或运行时已通过。

源码路径均相对于工作区根目录 `/Users/guanhao/VSCodeAlgorithmTrain/CPP/ibmsc/iBMSCPP`。嵌套仓库根目录是 `iBMSC/`，因此完整 VB 源文件路径带有 `iBMSC/iBMSC/` 前缀。为控制表格宽度，表中 `Dialogs/...` 和 `Option Windows/...` 是相对于 `iBMSC/iBMSC/` 的明确缩写；主窗体行直接使用完整路径。

## 主窗体和窗口元数据

| 窗口 | Designer 来源与声明 | 标题、尺寸和缩放 | 已观察的声明、默认值或布局 | 运行时待核对 |
| --- | --- | --- | --- | --- |
| `MainWindow` | `iBMSC/iBMSC/MainWindow.designer.vb:4163-4177`；控件声明 `:4297-4641` | `AutoScaleMode.None`；客户区 `1082 × 730`；`Segoe UI` 9 pt；`KeyPreview=True`。 | `AllowDrop=True`、`DoubleBuffered=True`、主菜单为 `mnMain`。选项滚动区 `POptionsScroll` 在右侧，`200 × 730`（`:554-558`）；状态区停靠底部，`876 × 22`（`:3699-3706`）；主编辑区填充 `866 × 660`，主编辑面板使用 `Verdana` 9 pt 粗体（`:3970-3988`）。三个编辑区滚动条的初始 `LargeChange=592`、`SmallChange=12`，水平条停靠底部（`:3995-4015`、`:4075-4093`、`:4127-4145`）。 | 右侧选项区的实际展开状态、面板宽度变化、DPI 和字体栅格化待运行时记录。窗口装饰不属于客户区基线。 |
| `AboutBox1` | `Dialogs/AboutBox1.Designer.vb:72-73` | `About`；`1000 × 600`；无缩放；无边框；屏幕居中（`:56-68`）。 | `ClickToCopy` 与 `Label1` 的文字都是 `Click to copy`，并且在 Designer 中 `Visible=False`（`:33-50`）。 | 文本来源、点击行为、实际可见性待运行时核对。 |
| `ColorPicker` | `Dialogs/ColorPicker.Designer.vb:333-356` | `ColorPicker`；`453 × 345`；无缩放；固定对话框；父窗口居中（`:286-320`）。 | `OK`、`Cancel`；`rbS.Checked=True`；`tbPrecision.Value=2`、最小值 `1`；`tStr.Text=FF000000`；`inA.Value=255`；`rbA.Enabled=False`（`:61-76`、`:89-94`、`:126-133`、`:239-243`、`:256-272`）。 | 颜色转换、精度含义、控件实际布局待运行时核对。 |
| `SplashScreen1` | `Dialogs/SplashScreen1.Designer.vb:24-42`；无 `Friend WithEvents` 控件声明 | 无 Designer 标题赋值；`722 × 331`；`AutoScaleMode.Font`，缩放尺寸 `6 × 13`；深色系统背景；无边框；屏幕居中（`:29-39`）。 | Designer 只建立窗体属性，没有列出控件声明。 | 启动画面内容、资源和持续时间待运行时核对。 |
| `dgImportSM` | `Dialogs/dgImportSM.Designer.vb:117-122` | `Import *.SM file`；`210 × 203`；无缩放；固定对话框；父窗口居中（`:97-111`）。 | `OK`、`Cancel`、难度列表 `LDiff`。提示文字明确写着「bg musics and STOP values will not be imported」（`:70-92`）。按钮表格停靠右下（`:36-66`）。 | 导入后的字段和提示显示方式待运行时核对。 |
| `dgMyO2` | `Dialogs/dgMyO2.Designer.vb:210-225` | Designer 未设置 `Text` 和 `ClientSize`；无缩放；固定单边框；`TopMost=True`（`:189-206`）。 | `vBPM` 默认 `120`，范围为 `0.0001` 到 `65535.9999` 的 Decimal 表达；三个应用按钮；结果表列为 `Index`、`Measure`、`ColumnName`、`Grid`、`LongNote`、`Hidden`、`AdjTo64`、`D64`、`D48`（`:57-191`、`:210-225`）。 | 资源文件提供的实际尺寸、标题和按钮行为待运行时核对。 |
| `dgStatistics` | `Dialogs/dgStatistics.Designer.vb:291-306` | `Statistics`；`482 × 254`；无缩放；固定单边框；父窗口居中（`:271-285`）。 | `OK`、图标、表格；行文字包括 `BPM`、`STOP`、`SCROLL`、`A1-A8`、`D1-D8`、`BGM`，列头包括 `Short`、`Errors`、`Total`（`:104-240`）。`OK` 锚定右下（`:47-54`）。 | 统计值的计算口径和错误计数待运行时核对。 |
| `diagFind` | `Dialogs/diagFind.Designer.vb:878-935` | `Find / Delete / Replace`；`474 × 422`；无缩放；固定单边框；父窗口居中（`:817-863`）。 | 两个 measure 数值框、两个 label 文本框、数值范围框、多个通道和范围复选框；`BSAll`、`BSInv`、`BSNone`、`TBSelect`、`TBClose`、`TBDelete`、`TBrl`、`TBrv`、`TBUnselect` 等声明均在 `:878-935`。 | 查找匹配、删除、替换和选择范围规则待运行时核对。 |
| `fLoadFileProgress` | `Dialogs/fLoadFileProgress.Designer.vb:77-79` | `Loading Files`；`611 × 120`；无缩放；固定对话框；无边框控制；屏幕居中（`:58-72`）。 | `Cancel_Button`、`prog` 进度条、`Label1`。 | 取消是否中止批量读取、进度更新时机待运行时核对。 |
| `OpGeneral` | `Option Windows/OpGeneral.Designer.vb:429-459` | `General Settings`；`413 × 510`；无缩放；固定对话框；父窗口居中（`:381-418`）。 | `cBeep.Checked=True`、`cAutoSave.Checked=True`、`cMStopPreview.Checked=True`；`NAutoSave.Value=2`，范围 `1–60`；`nGridPartition.Value=192`，范围 `8–10000`；中键默认 `rMiddleAuto.Checked=True`；编码、滚轮、自动保存、文件关联和焦点选项均有对应控件声明（`:102-375`）。 | 设置写入时机、选项对编辑器的影响和组合关系待运行时核对。 |
| `OpPlayer` | `Option Windows/OpPlayer.Designer.vb:259-277` | `Player Options`；`382 × 351`；无缩放；固定对话框；父窗口居中（`:224-253`）。 | 播放器列表 `LPlayer`；路径框 `TPath`；`Add`、`Remove`、`Restore default`、浏览按钮；播放、从当前小节播放和停止的参数框；引用文字解释 `<apppath>`、`<measure>`、`<filename>`（`:59-219`）。打开 BMS 时，Preview 外置三项会写 `___TempBMS.bms` 并启动这里的程序；F5 / F6 / F7 仍是内置。 | 播放器命令实际展开、保存和调用时机待运行时核对。未截图。 |
| `OpVisual` | `Option Windows/OpVisual.Designer.vb:836-901` | `Visual Options`；`1026 × 713`；无缩放；固定对话框；父窗口居中（`:755-822`）。 | 颜色按钮默认多为 `FF000000`；字体默认为 `Verdana`，列标题字体为 `Tahoma`；`iTSSensitivity.Value=1`、最大值 `20`；`iMiddleSensitivity.Value=1`、最大值 `1000000`；视觉项包括音符高度、标签横纵位移、隐藏音符透明度、时间选择颜色和敏感度（`:227-741`）。 | 数值下限、颜色解析、实际绘制效果和布局滚动状态待运行时核对。 |

## 布局证据和解读限制

Designer 中的 `Dock`、`Anchor`、`Location` 和 `Size` 只说明初始化布局。例如 `POptionsScroll.Dock=Right`，主编辑区 `PMain.Dock=Fill`，左、右编辑区分别停靠 `Left`、`Right`（`MainWindow.designer.vb:555-558`、`:3971-3976`、`:4051-4056`、`:4102-4108`）。这不能替代窗口创建后的实测客户区几何。

主窗体基线是源码中的 `1082 × 730` 客户区和 `Segoe UI` 9 pt；编辑面板另有 `Verdana` 9 pt 粗体。选项窗体和多数对话框使用 `Segoe UI` 9 pt，但 `SplashScreen1` 使用字体自动缩放，`dgMyO2` 的尺寸和标题来自资源。未记录操作系统、DPI、显示器、主题或截图步骤，因此这里没有截图结论，也没有假设窗口装饰可复用。

## 本次行为覆盖

`mubmsc-interactions.csv` 的 48 行只覆盖 `PanelEvents.vb`、`PanelKeyStates.vb`、`MainWindow.vb`、`TimeSelectionOps.vb`、`ChartIO.vb` 和 `EditorUndoRedo.vb` 中的代表性可操作行为。尤其保留了以下源码规则：`Shift` 单独用于长音符，`Ctrl` 单独用于隐藏，`Shift+Ctrl` 同时满足地雷和多选判断；最终含义取决于写入模式、时间选择模式或选择模式。`ConvertAreaToStop` 使用 `(lower, upper]` 检查范围，遇到起点以外的音符就提示并返回；通过后按有符号的 `vSelLength` 平移，并把 `STOP.Value` 设为 `vSelLength * 10000`。反向选择是否具有独立运行时表现仍待验证，清单不把它规范化，也不声称已修复。
