# BmsONE 窗口与布局初始清单

这份清单只记录提交 `bb3406eeb8f45d79350241f09bb897dd229ce3af`（<https://github.com/excln/BmsONE>）里能直接读到的窗口、停靠区和对话框。源码曾在临时目录核对，没有把 Qt 工程提交进本仓库。下表路径相对于该提交的仓库根，例如 `src/MainWindow.cpp`。用户说明见 <https://excln.github.io/bmsone.html>。仓库没有 `.ui` 文件，几何都写在 C++ 里。

BmsONE 编辑的是 BMSON。它另外提供 BMS 导入，那是转换入口，不是把 BMS 谱面结构套进编辑器。BMS 与 BMSON 必须分开建模。

这份清单只记录原版 BmsONE 有哪些窗和数字，方便对照能力。产品里这些能力挂进同一软件，不另做一扇 BmsONE 主程序。

未截图。图标、字体栅格、DPI、停靠区实际高度和系统窗口装饰都不算已经通过，表中一律标「运行时待核对」。

## 窗口

| 窗口 | 来源 | 标题、尺寸和默认值 | 已观察的布局 | 运行时待核对 |
| --- | --- | --- | --- | --- |
| `MainWindow` | `src/MainWindow.cpp:43`；标题 `src/MainWindow.cpp:749-757`；应用名 `src/AppInfo.h:6-7` | `resize(960, 640)` 是窗体客户区，不含系统边框。未保存文档标题为 `untitled [*] - BmsONE`。版本字符串是 `beta 0.2.1`。默认显示模式是 Beat 7-key（`MainWindow.cpp:37`）。 | 左侧三个停靠区：`Info`、`Channel`、`Selected Objects`（`:408-427`）。`Channel` 另有 `resize(334, height)`。中央是序列视图。底栏是名为 `Status Bar` 的工具栏。顶栏有 File、Edit、Sequence Tools、Sound Output、Preview、Find Channels。工具栏图标 `18 × 18`（`:29`、`:363`）。菜单是 File / Edit / View / Channel / Preview / Help，不接到 iBMSC。 | 菜单栏和工具栏实际高度、停靠区叠放后的高度、保存过的 `Geometry` / `WindowState`、图标绘制。 |
| `Preferences` | `src/Preferences.cpp:12-13` | 标题 `Preferences`。源码没有 `resize`。左侧列表最小 `80 × 80`、最大宽 `180`、图标 `32 × 32`（`:20-25`）。页：General、Edit、Preview、BMS Import。关闭按钮默认。产品里挂在主编辑器 Edit → Preferences...，快捷键 `Command+,`。 | 左右分栏加底部按钮，尺寸由布局算出。工作客户区 `640 × 420`。 | 打开后的实际客户区、各页控件框、图标。 |
| `BmsImportDialog` | `src/bms/BmsImportDialog.cpp:10`、`:45` | 标题 `BMS Import`。客户区 `640 × 480`。模态。按钮 `Next`、`Cancel`；复选框 `Skip Questions`；进度条最大 100。 | 交互区、进度条、只读日志、底栏按钮。这是 BMS → BMSON 的导入窗，不是 BMS 编辑器。 | 向导各步的控件框和进度更新。 |
| `GridSettingDialog` | `src/SequenceTools.cpp:643`、`:677` | 标题 `Grid Setting`。客户区 `600 × 400`。按钮 `OK`、`Cancel`、`Restore Default`，以及加减按钮。 | 表格加底栏。 | 表格列宽和行高。 |
| `MasterOutDialog` | `src/MasterOutDialog.cpp:17`、`:91` | 标题 `Export WAV`。客户区 `480 × 320`。按钮 `Export`、`Close`。默认勾选 `Refresh Master Cache`。音量滑条范围 `0–200`，默认一半。裁剪项：Soft Clip、Hard Clip、Normalize。未命名工程默认文件名 `NewProject.wav`。 | 表单加日志。 | 导出过程中的禁用状态和日志高度。 |
| `ExternalViewerConfigDialog` | `src/ExternalViewerTools.cpp:154` | 标题 `External Viewer Configuration`。源码没有 `resize`。列表最小 `80 × 80`、最大宽 `200`、图标 `32 × 32`。上下加减按钮图标 `20 × 20`。产品里挂在主编辑器 Preferences 和 Preview → Configure External Viewers...。Preview 另有 Play from Beginning / Here / Stop (External Viewer)。打开 BMS 时这三项走 iBMSC 播放器，写出 `___TempBMS.bms`，不写 `__bmsone_temp_*.bmson`。工作客户区 `720 × 440`。 | 左侧列表、右侧表单、变量说明。 | 打开后的实际客户区。 |
| `Convert Resolution` | `src/InfoView.cpp:494-513` | 标题 `Convert Resolution`。源码没有 `resize`。新分辨率合法范围 `48–24000`。产品里挂在主编辑器 File → Convert Resolution...，只对打开的 BMSON 有效。 | 当前值标签、新值输入、`OK` / `Cancel`。 | 对话框实际尺寸。 |
| `About BmsONE` | `src/MainWindow.cpp:733-745` | 标题 `About BmsONE`。系统 `QMessageBox::about`，没有手写客户区。产品里挂在主编辑器 Help → About BmsONE。版本 `beta 0.2.1`、平台 `macOS`。不写本程序编译日期。不写 Qt 版本号。 | HTML 简介，含版本、exclusion、Qt / libogg / libvorbis。 | 系统关于框的尺寸和图标。 |

## 主窗内部、可测几何

这些数字来自主窗和序列视图源码。它们是控件框的源码声明，不是截图像素验收。

| 部位 | 来源 | 源码数字 | 运行时待核对 |
| --- | --- | --- | --- |
| 序列时间线 | `src/sequence_view/SequenceView.cpp:68-73`、`:1285` | 小节列宽 `20`，BPM 列宽 `34`，合计 `54`。`headerHeight = 0`。框为 `(0, 0, 54, 视口高)`。 | 视口高随停靠区和滚动条变化。 |
| 主控车道 | 同上 `:73`、`:1288` | 宽 `64`。默认显示（`EditConfig.cpp:35-40`、`:95-97` 默认均为 true）。框为 `(54, 0, 64, 视口高)`。 | 用户关掉主控车道后的布局。 |
| 演奏区画 | `src/sequence_view/Skin.h:204-208`；`Skin.cpp:64`；`SequenceView.cpp:1290` | Beat 7-key、刮盘在左：`5×2 + 32 + 24×4 + 24×3 = 210`。框为 `(118, 0, 210, 视口高)`。共用编辑器按 `BO-SKIN` 改刮盘左右，按 `BO-CIRC` 改 Circular 列顺序，按 `BO-PLAIN` 改 Plain 列数，按 `BO-SCHEME` 改 Generic 配色数字，按 `BO-WHEEL` 改 Keyboard 搬到键盘的空列（轮盘不画进前 16 列）；独立 BmsONE 窗仍写死刮盘在左。 | 键图资源没有；未截图。 |
| 底栏 | `SequenceView.cpp:26-27`、`:173`、`:1286-1291` | 把手高 `6`。默认底栏高 `48 + 6×2 = 60`，范围 `60–180`。贴在视口下方。普通车道宽 `64`，紧凑 / 简单车道宽 `32`。产品里挂在主编辑器共用谱面底下，见 `BO-FOOTER`。 | 用户拖过把手之后的高度。 |
| 迷你地图 | `src/MasterView.cpp:24`、`:69-73`；`MasterView.h:43` | 宽 `50`。缓冲 `88 × 1024`。 | 悬停滑入和固定位置。 |
| 状态分区 | `src/StatusBar.cpp:9-22`、`:31` | 高 `18`。宽：Absolute Location `120`、Location `180`、Real Time `160`、Lane `100`、对象区 `320`（可拉伸）。 | 底栏工具栏的实际总宽和拉伸后的对象区。 |
| Info 表单默认值 | `src/document/DocumentInfo.cpp:39-58`；分辨率 `src/document/Document.h:30` | `modeHint = beat-7k`，分辨率 `240`，`judgeRank = 100`，`total = 100`，`initBpm = 120`，`level = 1`。子艺术家提示框 `200 × 60`，扩展字段 `200 × 180`（`InfoView.cpp:50`、`:60`）。产品里 TITLE 等对得上的字段走共用 Header；Chart Name / Judge Rank / Mode Hint / Title Image / Preview Music 在右侧 Info 栏。STAGEFILE / BANNER / BACKBMP 写 `eyecatchImage` / `banner` / `backImage`。Extra fields 折叠默认关，键是 `DocumentInfoView/ShowExtraFields`。`banner` 等官方图键不进折叠。 | 表单标签和输入框的运行时坐标。 |
| Selected Objects | `src/NoteEditTool.cpp`（类名 `NoteEditView`） | 标题 `Selected Objects`。尺寸提示 `200 × 180`。只编 Length 和 Extra fields，没有 Continue 控件。空选 Length 禁用。1 颗 `1 selected note`，多颗 `%1 selected notes`。Length 不一致用 placeholder `multiple values`；Extra 不一致写成 `(multiple values)`。Extra 折叠键 `NoteEditView/ShowExtraFields`，默认关。产品里挂在主编辑器右侧，打开 BMSON 时出现。 | 停靠区实际高度、字体和折叠后的高度。 |

## 解读限制

`QWidget::resize` 设置的是窗体客户区，不包括系统标题栏和边框。本仓库的原生窗也只约束客户区，装饰交给系统。

主窗 `960 × 640` 包含菜单（macOS 上多半在系统菜单栏）、工具栏、左侧停靠区和底栏。工具栏高度、停靠区叠放高度没有写死在源码里，不能当成已量过的像素。

BMS 导入窗只负责读 BMS 再转成 BMSON。不要把 BMS 小节、通道或条件分支写进 BmsONE 的文档模型。BMSON 领域模型在 `ibms::BmsonDocument`（`core/include/ibms/bmson.hpp`）：分辨率、声音通道、续播和切片字段已经能读写 JSON。打开、保存和放短音走同一套 C++ 模型，不走 BMS `insert_note`。主程序 Window 菜单可以打开这扇窗。窗成为 key 时，系统菜单栏换成 BmsONE 的 File 菜单。车道按 `Skin.cpp`：7k 默认刮盘在左（`x=8` 再 `1`–`7`），5k 默认在右，10k 默认 `rr`，14k 默认 `lr`。View → Scratch 只改刮盘左右，不写 `info`。View → Lane Order 对照 Circular `lane-order`，single 默认左，double 默认 `lr`，Space 在中间，不拆 1P / 2P。不要把刮盘写成永远是 `x=1`。File → Open 选 BMS 时走导入窗。没勾 Skip Questions 会先问编码，再问 RANDOM，最后问游戏模式；勾了就用编码空串、RANDOM `1` 和 `GetMode`。View → Grid Setting... 打开 `600 × 400` 网格设置窗，挂在主编辑器，不另开主程序窗。默认格子来自 `DefaultGrids`。确定后细格接到 `CGDivide`，辅助格接到 `CGSub`。View → View Mode 对照 `GetAllViewModes` / `GetViewMode`，只改显示和点选，不写 `info.modeHint`。共用现有 8+8 列；Keyboard 24k 只接到前 16 个 `x`。View → Zoom 对照 `ZoomIn` / `ZoomOut` / `ZoomReset`，打开 BMSON 时按 `zoomY` 改每拍像素，不套 iBMSC 的 `0.25` 步进。打开 BMSON 时，共用状态条对照 `SequenceViewCursor` 写 Absolute / Composite / Real Time / Lane，对象段接到 `FST`，不另做一条 BmsONE 底栏。View → Snap to Grid（`Command+T`）对照 `SnapToLowerFineGrid`，打开 BMSON 时按细格 `n/d` 对齐脉冲，不套 iBMSC 的 `4 / gDivide`。File → Export WAV... 打开 `480 × 320` 导出窗，默认刷新缓存、音量一半、`Soft Clip`。Export 已能按主控混音写出 44100 Hz 立体声 PCM16。File → Convert Resolution... 对照 `InfoView::ResolutionClicked`，范围 `48…24000`。主编辑器同一套 Beat 侧栏打开 `.bmson` 时写 `lines[]`，不写 `#mmm02`。BmsONE 源码只有插线 / 删线，四种 Apply 按 iBMSC `ApplyBeat` 改脉冲，这是工作规则。主编辑器同一套 BGA / Layer / Poor 列打开 `.bmson` 时写 `bga`，不写 `#BMP` / `#mmm04`。BmsONE 源码里编辑和换算仍是 `TODO`，这里按文档模型和导入公式补完。Edit → Move to Key Lanes / Move to BGM Lanes 对照 `TransferSelectedNotesToKey` / `ToBgm`，只改 `x`。Edit → Separate Layered Notes 对照 `SeparateLayeredNotes`，只拆同一脉冲的叠层。写入模式 + Command 点小节号列对照 `InsertBarLine` / `RemoveBarLine`，只改 `lines[]`。Channel 菜单对照 `InsertNewSoundChannels` / `DestroySoundChannel` / `MoveSoundChannel`，挂在主编辑器。Find → Active Channels Only 对照 `FiltersActive` / `IsActiveInRegion` / `GetVisibleRangeExtended`。Show Hit Channels Only 还没做。打开 BMSON 时共用主编辑器的 Find / Statistics，不另开 BmsONE Find 窗。Edit → Preferences... 对照 `Preferences`，四页挂在同一软件，不另开主程序窗。BMS Import 页的 Ask 旗和 `GetMode` 三旗接到导入。Preview 页的延迟接到 BMSON 播放头，时值接到点音符预听。主控道和迷你地图已接到主编辑器同一套谱面，不另开窗。关掉 Enable Master Channel 后两个都藏。未截图。打开 BMSON 时，右侧出现 Selected Objects，对照 `NoteEditView`，只改已选音符的 Length 和 Extra fields。写入模式点写对照 `SequenceViewWriteMode.cpp`：不按 Shift 写 `c=true`，按 Shift 写 `c=false`。Edit → Edit Mode / Write Mode 接到同一套 Select / Write。未截图，不能写成像素已通过。
