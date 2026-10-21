# iBMSCPP

**iBMSCPP**（应用名 **μBMSC Editor** / `IBMSNative`）是一款面向 macOS 的原生 BMS / BMSON 音游制谱软件。底层采用跨平台 C++20 核心库处理精确拍号分数、时序计算、谱面读写与音频解码；前端基于 AppKit、Metal 与 Core Audio 构建，提供高帧率谱面编辑与低延迟音画预览。

传统 BMS 制谱往往需要在多个年代久远的工具之间来回切换。本项目将四款经典制谱工具完整整合进**同一个软件**中：

- **iBMSC / µBMSC**：主谱面编辑器、NT 长音模式、时间选择变速、MyO2 工具箱與主题系统
- **BmsONE**：原生 `.bmson` 编辑、声道分轨视图、主控混音预览与整曲 WAV 导出
- **Be-Music Helper（bmhelper）**：MIDI 导入自动聚类、`#WAV` 定义生成与 Division 时间线管理
- **woslicer II / III**：波形裁断线切音、片段试听与 BMSE 剪贴板序列生成
- **uBMplay 风格内置预览器**：无需配置外部播放器，直接按 `F5` / `F6` 呼出独立窗口，同步预览下落式谱面、BGA 图层/视频（含 WMV / MP4）与 48 kHz 高精度混音

---

## 目录

- [功能特性](#功能特性)
- [环境要求](#环境要求)
- [构建与运行](#构建与运行)
- [使用指南](#使用指南)
  - [1. 打开、新建与格式转换](#1-打开新建与格式转换)
  - [2. 主编辑器常用操作](#2-主编辑器常用操作)
  - [3. 内置预览器（uBMplay 风格）](#3-内置预览器ubmplay-风格)
  - [4. 音频切片器（woslicer / bmhelper 二合一）](#4-音频切片器woslicer--bmhelper-二合一)
  - [5. MIDI 制谱助手（Be-Music Helper）](#5-midi-制谱助手be-music-helper)
  - [6. BMSON 专属工作流](#6-bmson-专属工作流)
  - [7. MyO2 工具箱与批量变速](#7-myo2-工具箱与批量变速)
- [目录结构](#目录结构)

---

## 功能特性

- **一套主界面同时编辑 BMS 与 BMSON**：底层严格区分 BMS 与 BMSON 数据模型，不互相硬套；上层共用同一套 Metal 谱面视图、点选、写入、框选、缩放、查找替换与撤销栈。
- **支持主流谱面与工程格式**：
  - 原生读写：`.bms`、`.bme`、`.bml`、`.pms`、`.bmson`
  - 工程导入与导出：`.ibmsc`（支持保留 Undo 历史、扩展区与界面偏好）
  - 外部谱面导入：`.sm`（StepMania 谱面导入）、BMS 转 BMSON 向导（支持编码选择、`#RANDOM` 分支展开与 5K/7K/10K/14K/PMS 键位映射）
- **开箱即用的内置音画预览**：
  - 按 `F5`（从头播放）或 `F6`（从当前位置播放）即刻试玩，支持 `0.50`–`5.00` 共 19 档 HiSpeed 与 `0.25x`–`4.00x` 共 16 档倍速播放（自动带限重采样变调）。
  - 原生支持 BMP / PNG / JPG / GIF 静态与序列图层，以及 WMV / ASF / MP4 等 BGA 视频同步解码与色键抠像。
- **内置完整切音与 MIDI 辅助链**：从 MIDI 分轨聚类、音频切片导出到谱面排布，全程在一个应用内闭环完成。

---

## 环境要求

1. **完整 macOS 桌面应用（`IBMSNative.app`）**
   - **系统版本**：macOS 14.0（Sonoma）或更高版本
   - **开发工具**：Xcode 15+ 或 Xcode Command Line Tools（需包含 Swift 编译器、Apple Clang 与 Metal 工具链）
   - **构建工具**：CMake `3.26` 及以上、Ninja
2. **仅编译跨平台 C++ 核心库（`ibms_core`）**
   - 任何支持 C++20 及 `__int128` 的 Clang 或 GCC 环境（macOS / Linux）
3. **第三方依赖**
   - 仓库已内置所需音频与重采样源码（`minimp3`、`stb_vorbis`、`libsamplerate` 0.2.2）以及 uBMplay 1.5.2 皮肤资源，无需通过 Homebrew 额外安装运行时动态库。
   - 用于 WMV / ASF 视频解码的最小化 LGPL FFmpeg 静态库会在首次构建时由 `third_party/ffmpeg-lgpl/build-static.sh` 自动拉取并静态编译。

---

## 构建与运行

在仓库根目录下打开终端，执行以下命令即可完成编译。

### 方式一：使用 CMake Presets（推荐）

编译 **Release** 版本并运行测试：

```bash
cmake --preset release
cmake --build --preset release
ctest --preset release
```

编译完成后，直接启动 macOS 应用：

```bash
open out/build/release/macos/IBMSNative.app
```

如果需要调试符号，可使用 `debug` 预设（产物位于 `out/build/debug/macos/IBMSNative.app`）：

```bash
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

### 方式二：自定义构建目录

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
ctest --test-dir build --output-on-failure -j4
```

使用该方式时，生成的应用位于 `build/macos/IBMSNative.app`：

```bash
open build/macos/IBMSNative.app
```

### 方式三：仅编译跨平台 C++ 核心与单元测试

在非 macOS 环境，或只需验证底层 C++20 核心库（`ibms_core`）时，可使用 `core-release` 或 `core-debug` 预设：

```bash
cmake --preset core-release
cmake --build --preset core-release
ctest --preset core-release
```

---

## 使用指南

> **提示**：应用首次启动默认为简体中文界面（可在顶栏或工具栏 `Language` 菜单中切换语言，在 `Options → Theme` 中切换编辑器配色主题）。若 macOS 系统将顶排按键默认设为媒体功能键，按 `F1`–`F7` 时请配合 `Fn` 键使用。

### 1. 打开、新建与格式转换

- **新建 / 打开谱面**：通过菜单 **文件 → 新建**（`Cmd + N`）或 **文件 → 打开…**（`Cmd + O`），也可直接将 `.bms`、`.bme`、`.bml`、`.pms`、`.bmson`、`.ibmsc`、`.sm` 文件拖入主窗口。
- **新建空白 BMSON**：点击菜单 **窗口 → BmsONE**，主编辑器将直接切换为新建的空白 `.bmson` 工程。
- **将 BMS 转为 BMSON**：点击 **文件 → 将 BMS 导入为 BMSON…**，按向导选择文本编码、`#RANDOM` 分支值和键位模式即可完成转换。
- **导入 / 导出工程**：在 **文件** 菜单下可执行 `.sm` 导入，以及 `.ibmsc` 工程文件的导入与导出。

### 2. 主编辑器常用操作

#### 工具模式切换

可通过顶部工具栏或快捷键随时切换三种编辑工具：

| 快捷键 | 工具名称 | 用途 |
| --- | --- | --- |
| `F1` | **时间选择工具**（Time Selection） | 划定时间区间，用于整体变速、拉伸或转为 STOP |
| `F2` | **选择工具**（Select） | 点选、框选、拖动、复制或修改已有音符 |
| `F3` | **写入工具**（Write） | 在轨道上点击写入新音符、长条或 BPM / STOP / BGA 事件 |

#### 音符编辑与快捷键

- **写入音符（`F3` 写入模式）**：
  - **左键单击 / 拖拽**：写入当前右侧列表选中的 `#WAV` / `#BMP` 编号（开启 NT 模式时纵向拖拽直接拉出长条）。
  - **按住 `Ctrl` + 左键**：写入隐藏音符（Hidden Note）。
  - **按住 `Ctrl + Shift` + 左键**：写入地雷音符（Landmine）。
- **选择与修改（`F2` 选择模式）**：
  - **左键点选 / 空白处框选**：选中单颗或多颗音符；直接拖拽可移动选中音符。
  - **按住 `Ctrl` + 拖拽**：复制选中的音符（包含短音、长音与 BPM / STOP / SCROLL 事件）到目标位置。
  - **按住 `Ctrl + Shift` + 左键点击音符**：将全谱面相同标签的音符一并加入选中（或在悬停音符时按 `Ctrl + Shift + A`）。
  - **双击音符**：弹出输入框，直接修改该音符的标签编号或 BPM / STOP / SCROLL 数值。
- **删除与吸取（任意模式通用）**：
  - **右键单击音符**：删除该音符（点击小节线可删除多余小节线）。
  - **`Shift` + 右键单击音符**：吸取该音符对应的编号，自动在右侧 `#WAV` 列表中定位选中。
- **快速换轨与长短音转换**：
  - **数字键 `1`–`8`**：将已选音符移至对应键列（A1–A8）；按住 `Shift` 时仅移动时间最早的一颗。
  - **数字键 `0`**：将已选音符移至第一列空闲的 BGM 列。
  - **`L` / `S`**：将已选音符转为长音（Long Note）或短音（Short Note）。
- **网格、缩放与导航**：
  - **`,` / `.`**：将当前网格细分（Grid Division）乘 2 或除以 2；按 `/` 切换至预设细分值。
  - **`G`**：开关网格对齐吸附（Snap to Grid）。
  - **`D`**：锁定纵向移动（仅允许左右换列，防止误改节拍位置）。
  - **`=` / `-` 或 `Ctrl` + 滚轮**：放大或缩小谱面纵向高度。
  - **小键盘 `+` / `-`**：在右侧 `#WAV` 列表中上下切换当前选中的编号。
  - **`Cmd + G`**：跳转到指定小节（Go To Measure）。
  - **分屏对照**：在 **视图（View）** 菜单中勾选 `Left Splitter` / `Right Splitter`，可在同一窗口拉开左、中、右三栏谱面视口，配合右侧面板的滚动锁按钮进行多段对照编辑。

### 3. 内置预览器（uBMplay 风格）

无需在外部配置播放器路径，在主编辑器中即可随时试听与审谱：

- **`F5`**：从头开始播放（Play from Beginning）
- **`F6`**：从当前位置播放（Play from Here）
- **`F7`**：停止播放（Stop）

当**预览窗口处于激活（拥有键盘焦点）**状态时，可使用以下快捷键实时控制预览（速度档位为逐次点按切换，按住不连跳）：

| 快捷键 | 功能说明 |
| --- | --- |
| `0` | 暂停 / 继续播放 |
| `1` / `2` | 降低 / 提高下落速度 **HiSpeed**（`0.50`–`5.00`，步长 `0.25`，仅改变视觉流速） |
| 同时按 `1 + 2` | 将 HiSpeed 向 `1.00` 回退一档 |
| `3` / `4` | 降低 / 提高播放倍速 **Rate**（`0.25x`–`4.00x`，步长 `0.25`，改变音频与时间流速） |
| 同时按 `3 + 4` | 将播放倍速 Rate 向 `1.00x` 回退一档 |
| `↑` / `↓` | 向前 / 向后跳转 1 小节（支持长按连跳） |
| `Page Up` / `Page Down` | 向前 / 向后跳转 4 小节（支持长按连跳） |
| `Home` / `End` | 跳至开头 / 最后有内容的小节 |
| 鼠标滚轮 | 按小节前后滚动定位 |
| 长按 `Space`（约 0.5 秒） | 从主编辑器当前最新内容热重载谱面 |
| `5` | 循环切换 BGA 显示模式（关闭 / 基础层 / 叠加层 / 正常 / 始终 MISS） |
| `6` | 循环切换判定文字、打击爆炸与按键光束显示组合 |
| `7` | 切换预览窗口置顶 |
| `8` | 循环切换 1P / 2P 皿位（Scratch）左右布局 |
| `9` | 循环切换顶部 HUD 信息（关闭 / 播放信息 / 曲目与选项 / 全部） |
| `F1` | 循环切换发声通道（BGM / KEY / KEY+BGM / MINE / 全部） |
| `F2` | 切换双侧谱面布局自动分离 |

### 4. 音频切片器（woslicer / bmhelper 二合一）

通过菜单 **文件 → Audio Slicer…** 或 **窗口 → woslicer II / III** 打开「音频切片器」。左上角的 **Cut points** 下拉框可在两种切音模式间切换：

- **`woslicer` 模式（按裁断线切音）**：
  - 载入 `.wav` / `.ogg` / `.mp3` 音频后显示波形包络，直接用鼠标在波形上定位。
  - 无修饰键时的单键操作：
    - `Z`：在当前光标位置添加或移除裁断线
    - `C`：清空所有裁断线
    - `P` 或 `Enter`：试听当前切片区间
    - `O`：试听上一段切片区间
    - `M`：按裁断线批量切分并导出 16-bit PCM `.wav` 文件
    - `V`：根据当前 BPM 与切点生成 BMSE 剪贴板序列，可直接回到主编辑器粘贴上音
- **`bmhelper` 模式（按 Division 时间线切音）**：
  - 配合 Be-Music Helper 中的 Division 切点公式自动计算切片区间，支持一键试听与批量导出。

### 5. MIDI 制谱助手（Be-Music Helper）

通过菜单 **窗口 → Be-Music Helper** 打开：

1. 点击 **File → New...** 选择一份 `.mid` 文件（或将 `.mid` / `.bmh` 拖入窗口），在弹出的导入设置中选择目标轨道与 MIDI 通道。
2. 软件会自动按音高、时值（Gate）与力度（Velocity）对音符进行聚类，生成对应的 `#WAV` 定义列表与 Division 时间线。
3. 在下半窗格的钢琴卷中查看聚类后的时间线，点击右侧按钮或 **Divisions** 菜单即可：
   - 一键复制 `#WAV` 定义文本或 BMSE 剪贴板音符序列；
   - 打开内置音频切片器（自动切至 `bmhelper` 模式）将分轨干音切分为独立 Keysounds；
   - 调整定义编号偏移（Transpose）、重新聚类（Regenerate）或导出修改后的 MIDI 文件。

### 6. BMSON 专属工作流

当打开或新建 `.bmson` 文件时，主编辑器会自动解锁 BmsONE 的专属视图与功能：

- **声道分轨视图**：在 **视图 → Sound Channel Lanes Display** 中开启分轨列（Normal / Compact / Simple），可在主谱面右侧并排查看每条 Sound Channel 的音符分布、列内 RMS 波形或活动条。
- **底部声道栏与主控道**：底部声道栏直接显示各声道文件名（单击切换当前声道、双击试听）；左侧主控道（Master Channel）与右侧迷你地图（Minimap）支持全局概览与点击定位预览。
- **续播与重触发写入**：在写入模式下点击写入默认为续播音符（`c = true`），按住 `Shift` 点击写入为重新触发（`c = false`）。
- **整曲混音导出**：点击 **文件 → 导出 WAV…**（Export WAV…），可按 Master 混音设置（含音量、硬裁剪 / 软裁剪 / 归一化）直接将整首 BMSON 渲染导出为立体声 WAV。

### 7. MyO2 工具箱与批量变速

- **MyO2 工具箱**：点击 **编辑 → MyO2 工具箱**（或工具栏对应图标），可执行谱面恒速化、64 分音符对齐检查与一键自动对齐（同时支持 BMS 与 BMSON，修改均记录为单步撤销）。
- **时间选择变速（`F1`）**：切换到时间选择工具后，在谱面上划定起点、中线与终点，即可在底部工具条执行按比例缩放 BPM（Expand By Ratio）、按拍数重定位（Relocate By Value）、将选区转换为 STOP（Transform Into Stop），或按住 `Shift` 直接拖动时间选择线进行实时变速配拍。

---

## 目录结构

| 目录 / 文件 | 说明 |
| --- | --- |
| `core/` | 跨平台 C++20 核心库 `ibms_core`（`BeatPosition` 精确拍号分数、BMS / BMSON 解析与序列化、长音配对、时序推导、WAV / OGG / MP3 解码） |
| `macos/Sources/IBMSBridge/` | Objective-C++ 与 C++ 桥接层（文档桥、分组带限重采样混音桥 `PreviewAudio/`、FFmpeg 视频解码桥 `PreviewVideo/`） |
| `macos/Sources/IBMSNative/` | macOS 原生应用源码（主编辑器、Metal 谱面渲染器、内置 uBMplay 预览器、BmsONE / bmhelper / woslicer 集成模块） |
| `tests/`、`macos/Tests/` | C++ 核心测试与 Swift 原生模块测试套件（共 68 个 CTest 测试目标） |
| `third_party/` | 内置静态依赖源码（`minimp3`、`stb_vorbis`、`libsamplerate`、`ffmpeg-lgpl` 构建脚本与重链接说明） |
| `docs/` | 架构说明、[内置预览器键位细则](docs/preview-controls.md)及验证记录 |
