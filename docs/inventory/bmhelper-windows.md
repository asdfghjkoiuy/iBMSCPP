# bmhelper 窗口与布局清单

这份清单记录 bmhelper 提交 `d6b674368b1e0c09baaa8dbb01d01c01f67f0791` 里能直接读到的窗口尺寸和控件几何。仓库在 GitHub：<https://github.com/zardoru/bmhelper>。上游说明：<https://excln.github.io/bmhelper.html>。路径相对于该提交的 `src/`。

我没有运行程序，也没有截图，因此没有像素已通过的结论。

wxWidgets 文档里，`wxFrame` / `wxDialog` 构造函数的 `wxSize` 是窗口尺寸，不一定等于客户区。这一轮按任务要求，把源码数字当作原生窗口的客户区。菜单栏和状态栏在 wx 里通常不计入 `GetClientSize()`。最终客户区以运行时为准。

调用 `SetSizerAndFit` 的窗口只有构造时的提示尺寸。最终客户区不能从源码定死。

## 窗口一览

| 窗口 | 来源 | 标题、尺寸 | 已观察的控件、默认值或布局 | 运行时待核对 |
| --- | --- | --- | --- | --- |
| `FrameWindow`（主窗） | `app.cpp:48`；`frame.cpp:45-46`、`:337-339` | 标题已按 `ProjectChangeFlagChanged` 刷新。无工程是 `Be-Music Helper`（`app.cpp:3`）。未命名永远是 `New project* - Be-Music Helper`。已命名且脏是 `{title}* - …`，干净是 `{title} - …`。构造 `wxSize(800, 600)`。 | 水平分割条铺满客户区 `(0, 0, 宽, 高)`；`SetSashGravity(0.5)`；最小窗格 `80`（`frame.cpp:115-120`）。状态栏三列，宽度 `-1`、`180`、`120`（`:111-113`）。有 File / Divisions / Help 菜单（`:85-107`）。下半窗格已接 division 名单：上边按钮 `New division...`，中间是时间线钢琴卷，再下面定义条和 `<` / `>` / `Transpose to...` 同一行，底边名字列表。编辑器 MidiView 已接时间线：有选中则画 `division.midi.notes`，没有选中或没有工程当没有 data。未截图。DefinitionView 条已接，未截图。没有选中则三个平移按钮禁用。Divisions 菜单已接 Delete，仍是系统提示框。Divisions 菜单已接 Regenerate division (&E)...，复用 Division settings 窗，就地重聚选中项。上半窗格已接 SourceView / MidiView：有工程时按原文整数公式画源 MIDI，不是 Division 时间线。算法客户区按工作值 `800 × 300`。悬停文案写到状态栏左列。未截图。状态栏文案已接，高度未量。窗标题在 New / Open / Save / 改名单之后刷新。File 菜单已接 Close project，仍是系统提示框。Divisions 菜单已接 Copy division (&W) 和 Copy BMS sequence to clipboard (&S)，都只写系统剪贴板，不写进主编辑器。Copy division 用时间线位置。Divisions 菜单已接 Write modified MIDI File (&M)...，写出选中 division 的时间线 MIDI。下半窗格已左右分栏：右栏提示宽 200，最小 125，重力在左。右侧五个按钮已接，接到已有菜单同一套动作。没有选中或没有工程则禁用。未截图。DefinitionView 条已接，未截图。编辑器 MidiView 已接时间线，未截图。两份钢琴卷已接滚轮：Command 缩放，Shift 改轴。未截图。主窗已接拖放：没有工程当 New / Open，有工程只换源，不重建 division，不设脏。失败带路径。第一个成功就停。不先问保存。未截图。 | 构造尺寸是外框还是客户区、菜单和状态栏实际占高、分割条初始位置。未截图。 |
| `LoadSmfDialog` | `midi_smfin.cpp:52-104` | 标题 `MIDI file import settings`。构造 `wxSize(290, 130)`，随即 `SetSizerAndFit`。 | 音轨标签曾写 `wxPoint(5, 8)`、`wxSize(85, 15)`（`:74`），随后被 sizer 接管。16 个通道复选框默认勾选（`:92-95`）。`OK` 为默认按钮。无关闭框（`:54`）。 | `SetSizerAndFit` 后的客户区。未截图。 |
| `DivisionSettingDialog` | `divsettingdialog.h:55`；`divview.cpp:153-253` | 标题 `Division settings`。构造宽 `_lm*2+_fc+_sc+_bw*2+10` = `330`，高 `_tm*2+_lw*15+_lb+_bw+_cw+10` = `455`，随即 `SetSizerAndFit`。 | 默认值在 `division.cpp:470-482`：`src_copy=false`，`head_margin=0`，`min_interval=quantize`，排序 `nn/gate/vel`，`gate_threshold=quantize/8`，`velocity_threshold=5`，`zz_definition=true`，`ml_definition=true`，起始定义 `1`，`ml_threshold=quantize/2`。按钮 `OK`、`Cancel`。 | sizer 收紧后的客户区和各控件矩形。未截图。 |
| `DefTransposeDialog` | `divedit.cpp:224-234` | 标题 `WAV definitions`。构造 `wxSize(200, 120)`。 | 按客户区 `w×h`：编辑框 `(5, 5, w-10, h-40)`，`OK` `(5, h-30, w-10, 25)`。若客户区按 `200 × 120`：编辑框 `(5, 5, 190, 80)`，`OK` `(5, 90, 190, 25)`。默认文字为当前起始定义的两位字串。`Transpose to` 已接到下半窗格按钮。确定后走 `to`。Cancel / 非法两位不改。 | 构造 `200 × 120` 是否等于客户区。未截图。 |
| `DefDialog` | `divedit.cpp:321-334`、`:296-302` | 标题 `BMS WAV definitions`。构造 `wxSize(400, 300)`，可改大小。 | 标签 `Filename (&F):` 在 `(5, 8, 80, 15)`。按客户区 `w×h`：文件名框 `(85, 5, w-90, 18)`，正文 `(5, 30, w-10, h-65)`，`Copy to clipboard (&C)` `(5, h-30, (w-10)/2, 25)`，`Close (&W)` `((w-10)/2+5, h-30, (w-10)/2, 25)`。若客户区按 `400 × 300`：文件名框 `(85, 5, 310, 18)`，正文 `(5, 30, 390, 235)`，复制 `(5, 270, 195, 25)`，关闭 `(200, 270, 195, 25)`。文件名为空时默认 `untitled`（`:333`）。 | 构造 `400 × 300` 是否等于客户区。未截图。 |
| `AudioSplitter` | `AudioSplitter.cpp:24-120`；`divedit.cpp:387` | 标题 `Audio splitter (division: "…")`。构造宽 `800`、高 `-1`，随即 `SetSizerAndFit`。不可最大化、不可改大小（`:27`）。 | BPM 范围 `1–5000`，两位小数，默认 `120`（`:88-91`）。偏移范围 `-10000–10000`，默认 `0`（`:97-99`）。前缀默认是 division 名（`:74`）。按钮 `Split`、`Close`。 | sizer 收紧后的客户区。未截图。 |
| 语言选择 | `app.cpp:20-25` | 标题 `Language`。文案 `Please choose language:`。 | `wxGetSingleChoiceIndex` 系统列表。选项：`System`、`English`、`Español`、`Norsk (Bokmål)`、`日本語`（`Configuration.cpp:12-18`）。已接到第一次 `present()`：还没存过有效选项时先弹，再 `showWindow`。仍是系统列表，没有手写客户区。 | 系统对话框的实际尺寸。未截图。 |
| 关于 | `frame.cpp:269-271` | 标题与程序名相同。 | `wxMessageBox`：`Be-Music Helper (beta 6 (wyrmin))\n by exclusion\n forked by zardoru`。已接到 Be-Music Helper 的 Help → About。仍是系统提示框，没有手写客户区。 | 系统提示框的实际尺寸。未截图。 |
| 重命名 division | `divedit.cpp:368-373` | 标题 `Rename division`。 | `wxTextEntryDialog`，提示 `Rename '%s' to`，默认值为当前名。已接到 Be-Music Helper 的 Divisions → Rename division。仍是系统输入框，没有手写客户区。 | 系统输入框的实际尺寸。未截图。 |
| 删除 division | `divview.cpp` `OnDeleteDivision`；`frame.cpp` 菜单 `Delete division (&D)` | 标题与程序名相同。 | `wxMessageBox`，提示 `Are you sure you want to delete %s?`，按钮 Yes / No。已接到 Be-Music Helper 的 Divisions → Delete division (&D)。仍是系统提示框，没有手写客户区。 | 系统提示框的实际尺寸。未截图。 |
| 重聚 division | `divedit.cpp` `OnDivRegenerate`；`division.cpp` `change_division_settings` | 复用 `Division settings`。 | 已接到 Be-Music Helper 的 Divisions → Regenerate division (&E)...。设置窗用默认值加上当前名字。就地重聚选中项，不是追加。 | 复用已有设置窗。未截图。 |

## 这一轮做成的原生窗口

已经做成的原生窗口：`FrameWindow`、`DefTransposeDialog`、`DefDialog`、MIDI 导入设置窗、`Division settings`，以及 `Audio splitter`。MIDI 窗按源码写成客户区 `290 × 130`、Tracks 标签 `(5, 8, 85, 15)`、无关闭盒；已有轨道下拉、16 个通道复选框和 `OK`。`SetSizerAndFit` 之后的真实客户区还没量过。`Audio splitter` 工作尺寸 `800 × 360`，高度不是原版客户区。主窗下半窗格已接 division 名单和 `New division...` 按钮；按钮和定义条之间是时间线钢琴卷。定义条右边是 `<` / `>` / `Transpose to...`。编辑器 MidiView 已接时间线，未截图。DefinitionView 条已接，未截图。`WAV definitions` 的 `Transpose to` 已接到这三个按钮。Divisions 菜单已接 Delete，仍是系统提示框。Divisions 菜单已接 Regenerate division (&E)...，复用 Division settings 窗，就地重聚选中项。Divisions 菜单已接 Copy division 和 Copy BMS sequence，都只写系统剪贴板。Copy division 用时间线位置。Divisions 菜单已接 Write modified MIDI。右侧五个按钮已接，接到已有菜单同一套动作。未截图。底边状态栏文案已接，高度未量。窗标题已按 `ProjectChangeFlagChanged` 刷新。上半窗格已接 SourceView / MidiView，有工程时画源 MIDI。未截图。左栏编辑器 MidiView 已接时间线。未截图。两份钢琴卷已接滚轮：Command 缩放，Shift 改轴。未截图。主窗已接拖放：没有工程当 New / Open，有工程只换源。未截图。DefinitionView 条已接，未截图。

`DefDialog` 已能按 `divedit.cpp:311` 拼 `#WAVxx name_NNN.wav\r\n`。默认从 `01` 起。Copy 按钮会把文本拷到剪贴板。MIDI 导入后按 `division.cpp` 聚类再写定义，不再默认一对一。`Division settings` 窗按构造 `330 × 455`。`Audio splitter` 已能按 `wavsplit.cpp` 切 PCM 16-bit WAV；工作尺寸 `800 × 360`，高度不是原版客户区。`.bmh` 已按 `serialize.h` 读写：根 `BMHP`，源 `Src `，division `Div `。名字按 UTF-8 写。未截图，不写像素已通过。

主窗用系统标题栏和关闭、最小化、缩放按钮，不仿 Windows 边框。客户区按 `800 × 600`。分割条铺满客户区。菜单不接到 IBMS 主菜单或主工具条；这一轮也不在客户区里画一份 Windows 菜单栏。

## 布局数字（按客户区等于构造尺寸）

| 窗口 | 客户区 | 关键矩形 |
| --- | --- | --- |
| 主窗 | `800 × 600` | 分割条 `(0, 0, 800, 600)` |
| `WAV definitions` | `200 × 120` | 编辑框 `(5, 5, 190, 80)`；`OK` `(5, 90, 190, 25)` |
| `BMS WAV definitions` | `400 × 300` | 标签 `(5, 8, 80, 15)`；文件名 `(85, 5, 310, 18)`；正文 `(5, 30, 390, 235)`；复制 `(5, 270, 195, 25)`；关闭 `(200, 270, 195, 25)` |

夹具在 `macos/Tests/BmhelperLayoutTests.swift`。测试只核对源码数字有没有写进布局常量，不表示截图或运行时已经通过。
