# iBMSCPP

**iBMSCPP**（μBMSC Editor / IBMSNative）是一体化的 BMS / BMSON 谱面编辑器。谱面模型、拍号运算、时序和音频解码放在 C++20 核心库里；macOS 上的完整应用用 AppKit 组织窗口，用 Metal 绘制谱面，用 Core Audio 播放预览。

它把四款经典工具里可以观察到的能力收进同一个原生软件：

- **iBMSC / µBMSC**
- **BmsONE**
- **Be-Music Helper（bmhelper）**
- **woslicer II / III**

首次启动时界面为简体中文。下文先写中文菜单名，括号里是英文原文，便于对照英文界面和源码。

## 目录

- [项目简介](#项目简介)
- [设计理念](#设计理念)
- [环境要求](#环境要求)
- [构建与测试](#构建与测试)
- [使用指南](#使用指南)
- [仓库目录](#仓库目录)

## 项目简介

主程序是一扇编辑器窗口，同时原生支持 BMS 与 BMSON 两套模型。可以打开、新建和保存的谱面包括：

| 格式 | 扩展名 | 在本程序中的位置 |
| --- | --- | --- |
| BMS | `.bms`、`.bme`、`.bml`、`.pms` | 原生读写 |
| BMSON | `.bmson` | 原生读写 |
| iBMSC 工程 | `.ibmsc` | 导入与导出 |
| StepMania | `.sm` | 导入 |

预览也在这个软件里完成。内置预览器按 uBMplay 的非模态窗口来做：Metal 谱面、BGA 图层，以及 WMV / MP4 视频，配上 48 kHz 分组带限重采样混音。打开预览就能同时看谱、看 BGA、听声音。

## 设计理念

原则是「一个软件，不是四套窗」。BmsONE、bmhelper、woslicer 都挂在同一套主界面上，各自保留原来的算法和独有对话框，不再各开一扇主程序窗。

### 同一套主编辑器

时间线、Metal 谱面、点选、写入、缩放、滚动和内置预览共用一套前端。底层按文件类型走 BMS 或 BMSON 模型，显示和操作保持同一套。

### 同类功能共用前端

同一种工作共用一个窗口，算法按模式切换。音频切片器就是这样：一个 Audio Slicer 窗口，左上角 **Cut points** 在 `woslicer` 与 `bmhelper` 之间切换。`woslicer` 用裁断线；`bmhelper` 用 Division 时间线切分。写出的都是同一路 16-bit PCM。

### 内置 uBMplay 风格预览

预览窗口独立于主编辑器，非模态。谱面用 Metal 绘制，BGA 走图层以及 WMV / MP4，声音由分组带限重采样混音引擎以 48 kHz 输出。皮肤图集使用仓库内置的 uBMplay 1.5.2 资源（`macos/Resources/UbmplayReference/ubmplay_152.zip`）。

## 环境要求

- **macOS 14.0 及以上。** 完整应用 `IBMSNative.app` 需要 Xcode 或 Command Line Tools，以及 Swift 与 Metal。部署目标在根目录 `CMakeLists.txt` 里定为 14.0。
- **CMake 3.26 及以上**，以及 **Ninja**。
- **支持 `__int128` 的 C++20 编译器**，例如 Apple Clang 或 GCC。配置阶段会编译一段探测程序；编译器没有 `__int128` 时，配置直接失败。只构建跨平台核心 `ibms_core` 时，可以在非 macOS 环境使用 `core-debug` 或 `core-release` 预设。
- **第三方依赖随仓库提供，或在构建时静态编译**，不需要再安装这些动态库：
  - `stb_vorbis`（`third_party/stb/stb_vorbis.c`）
  - `minimp3`（`third_party/minimp3`）
  - `libsamplerate` 0.2.2（`third_party/libsamplerate`，2-clause BSD，见该目录 `COPYING`）
  - 用于 WMV / ASF 的 LGPL 静态 FFmpeg 7.1.1。构建脚本、许可证和重新链接步骤在 `third_party/ffmpeg-lgpl/`（`build-static.sh`、`COPYING.LGPLv2.1`、`RELINK.txt`）
  - uBMplay 1.5.2 皮肤图集，随 macOS 资源一起打包

## 构建与测试

以下命令都在仓库根目录执行。CMake Presets 使用 Ninja，并打开测试。

### 使用 CMake Presets

Release：

```bash
cmake --preset release
cmake --build --preset release
ctest --preset release
```

Debug：

```bash
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

应用包：

- Release：`out/build/release/macos/IBMSNative.app`
- Debug：`out/build/debug/macos/IBMSNative.app`

启动 Release 包：

```bash
open out/build/release/macos/IBMSNative.app
```

`release` 与 `debug` 的测试预设已打开「失败时打印输出」。Ninja 会按本机核心数并行编译。

### 只构建 C++ 核心

这个预设设置 `IBMS_BUILD_MACOS_APP=OFF`，只编译 `ibms_core` 和核心测试，不生成 macOS 界面。非 macOS 环境用这一组。

```bash
cmake --preset core-release
cmake --build --preset core-release
ctest --preset core-release
```

调试构建把预设名换成 `core-debug`，目录为 `out/build/core-debug`。Release 核心的目录是 `out/build/core-release`。

### 自定义构建目录

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
ctest --test-dir build --output-on-failure -j4
```

在 macOS 上，此方式的应用包位于 `build/macos/IBMSNative.app`。

## 使用指南

功能键若被系统占用，`F1`–`F7` 需要同时按 `Fn`。紧凑键盘上的 Page Up、Page Down、Home、End 也按系统的 `Fn` 组合键。

### 打开与新建谱面

- **文件 → 新建**（File → New），**文件 → 打开…**（File → Open…）：新建或打开 `.bms`、`.bme`、`.bml`、`.pms`、`.bmson`、`.ibmsc`、`.sm`。也可以把文件拖进主窗口。
- **窗口 → BmsONE**（Window → BmsONE）：在当前主编辑器里新建一张空白 `.bmson`。
- **文件 → 将 BMS 导入为 BMSON…**（File → Import BMS as BMSON…）：按 BmsONE 的规则导入，包括文本编码、`RANDOM` 分支，以及 5K / 7K / 10K / 14K / PMS 键位模式。
- 另有 **从 .SM 文件导入**、**从 .IBMSC 文件导入**，以及 **导出 .IBMSC 文件**。

### 主编辑器

编辑模式在 **编辑** 菜单里，也有对应的工具栏按钮：

| 按键 | 菜单 | 作用 |
| --- | --- | --- |
| `F1` | 时间选择工具（Time Selection Tool） | 时间选择 |
| `F2` | 选择工具（Select Tool） | 选择 |
| `F3` | 写入工具（Write Tool） | 写入 |

选择与编辑：

- 左键点选或框选音符，拖动可移动已选音符。按住 `Ctrl` 拖动则复制已选音符。
- 写入模式下，左键写入当前选中的 `#WAV` / `#BMP` 槽位。按住 `Ctrl` 写隐藏音符（Hidden）。按住 `Ctrl` + `Shift` 写地雷音符（Mine）。
- 右键单击音符，删除该音符。`Shift` + 右键吸取该音符对应的侧栏 WAV 槽位。双击音符，修改标签，或 BPM / STOP / SCROLL 数值。
- 数字键 `1`–`8` 把已选音符移到键列 A1–A8。`0` 移到第一列空着的 BGM 列。预览窗口的内容区拥有键盘焦点时，这些数字键改去控制预览；焦点回到谱面后，仍按这里的规则移动音符。
- `L` 把已选音符转为长音（Long Note），`S` 转为短音（Short Note）。
- `,` / `.` 把网格细分倍增或折半。`/` 切到预设细分。`G` 切换网格对齐（Snap to Grid）。`D` 锁定纵向移动（Disable vertical moves）。`=` / `-`，或 `Ctrl` + 滚轮，调整纵向缩放。
- 小键盘 `+` / `-` 递增或递减当前选中的侧栏 WAV 槽位。
- `Command` + `G` 打开 **编辑 → 跳转到小节…**（Edit → Go To Measure...）。

### 内置预览器

在主编辑器里：

| 按键 | 菜单与工具栏 | 作用 |
| --- | --- | --- |
| `F5` | 预览 → 从开头播放（Play from beginning） | 从头播放 |
| `F6` | 预览 → 从当前位置播放（Play from here） | 从编辑区指针所在拍播放 |
| `F7` | 预览 → 停止（Stop） | 停止 |

下面的键在预览窗口获得键盘焦点时生效。HiSpeed 和播放倍速是固定档：一次物理按下只动一档，按住不连跳；已经在端点就停住。松开后再按，才进入下一档。

| 按键 | 作用 |
| --- | --- |
| `1` / `2` | 降低 / 提高下落速度 HiSpeed。范围 `0.50`–`5.00`，步长 `0.25`，共 19 档。只改变谱面移动速度 |
| 同时按住 `1` 和 `2` | HiSpeed 朝 `1.00` 回退一档；已经是 `1.00` 则不动 |
| `3` / `4` | 降低 / 提高播放倍速 Rate。范围 `0.25x`–`4.00x`，步长 `0.25`，共 16 档。改变声音和谱面时间，不改变 HiSpeed 的像素 |
| 同时按住 `3` 和 `4` | Rate 朝 `1.00x` 回退一档 |
| `0` | 暂停 / 继续 |
| `↑` / `↓` | 前移 / 后移 1 小节。按住会重复 |
| `Page Up` / `Page Down` | 前移 / 后移 4 小节。按住会重复 |
| `Home` / `End` | 跳到开头 / 最后有内容的小节。按住不重复 |
| 鼠标滚轮 | 按小节定位 |
| 长按 `Space` 约 0.5 秒 | 从当前编辑器内容热重载谱面 |
| `5` | 循环 BGA 显示：关闭、基础层、叠加层、正常、始终 MISS |
| `6` | 循环判定文字、爆炸、光束的组合开关 |
| `7` | 切换窗口置顶 |
| `8` | 循环 1P / 2P 搓盘左右位置 |
| `9` | 循环 HUD：关闭、播放信息、曲目与选项、全部 |
| `F1` | 循环发声通道：BGM、KEY、KEY 与 BGM、MINE、KEY 与 BGM 与 MINE |
| `F2` | 切换双侧布局的自动分开 |

各档数值、焦点规则和控制条位置见 [docs/preview-controls.md](docs/preview-controls.md)。

### 内置辅助工具

#### 音频切片器（Audio Slicer）

**文件 → Audio Slicer…**，或 **窗口 → woslicer II / III**。窗口标题在中文界面下为「音频切片器」。**Cut points** 选择 `woslicer`（裁断线）或 `bmhelper`（Division 切分）。

下列单键在 `woslicer` 模式、且没有按下修饰键时生效：

| 按键 | 作用 |
| --- | --- |
| `Z` | 在当前位置添加或移除裁断线 |
| `C` | 清空裁断线 |
| `P` 或 `Enter` | 试听当前段 |
| `O` | 试听前一段 |
| `M` | 按裁断线切分并导出 WAV |
| `V` | 生成 BMSE 剪贴板序列 |

#### Be-Music Helper（bmhelper）

**窗口 → Be-Music Helper**。可以导入 MIDI（`.mid`），自动聚类并生成 `#WAV` 定义，管理 Division 时间线，调用同一套音频切分，并导出修改后的 MIDI。

#### MyO2 工具箱

**编辑 → MyO2 工具箱**（Edit → MyO2 ToolBox (Chinese Only)）。工具栏上有同一按钮。窗口标题是「MyO2 工具箱」。这里做恒速化、64 分音符对齐检查，以及按检查结果自动对齐。

#### BMSON 整曲混音

打开 `.bmson` 后，用 **文件 → 导出 WAV…**（File → Export WAV…）导出整曲混音 WAV。

## 仓库目录

| 路径 | 内容 |
| --- | --- |
| `core/` | 跨平台 C++20 核心库 `ibms_core`。精确拍号分数（`BeatPosition`）、BMS / BMSON 解析与保存、长音配对、时序计算、音频解码 |
| `macos/` | 原生应用 `IBMSNative`，以及 Objective-C++ / C++ 桥 `IBMSBridge`。桥里包括 Metal 谱面、分组重采样混音，以及 FFmpeg 视频解码时钟 |
| `tests/`、`macos/Tests/` | C++ 核心测试，以及 macOS 原生模块、界面和音视频回归。CTest 共 68 个测试目标 |
| `third_party/` | 静态依赖：`minimp3/`、`stb/stb_vorbis.c`、`libsamplerate/`、`ffmpeg-lgpl/`（构建脚本与重新链接说明） |
| `docs/` | 设计说明、[预览控制](docs/preview-controls.md)，以及阶段性验证记录 |

更细的预览键位以 [docs/preview-controls.md](docs/preview-controls.md) 为准。FFmpeg 的重新链接步骤以 [third_party/ffmpeg-lgpl/RELINK.txt](third_party/ffmpeg-lgpl/RELINK.txt) 为准。
