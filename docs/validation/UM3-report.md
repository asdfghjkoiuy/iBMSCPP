# UM3 预览分类与曲信息

BGM 和地雷以前都带着默认的 `.key` 进播放器，所以 `setAudibleKinds` 滤不掉它们。BMSON 预览文本以前只有 `#WAV`，右面的曲信息是空的。这次把种类和真实谱头接到同一条预览数据上。

这不是 uBMplay 解析器的完整复刻。音量没有乘上，地雷的 `sound/engine.ogg` 也还没接。

## 改了哪些文件

- `macos/Sources/IBMSNative/MainWindowController.swift`
- `macos/Sources/IBMSNative/LegacyBmsonPreview.swift`
- `macos/Sources/IBMSNative/PreviewBmsSource.swift`
- `macos/Tests/LegacyBmsonPreviewTests.swift`
- `macos/Tests/PreviewBmsSourceTests.swift`

没有改 Style、预览窗、BGA、core、CMake，也没有提交。条件分支缓存还是同一份原字节复用一次展开结果。

## 声音

BMS 按物件种类映射：`bgm`、`mine`、`hiddenNote`、`normalNote`、`longNote`。hidden 在可听通道上是键音，画面仍不画。普通音和长音起点是键音。已配对长音的终点不第二次发声。

地雷的种类是 `.mine`，但不带谱面 WAV 键。播放器的 `scheduleHits` 会丢掉这个空键，所以即使 `setAudibleKinds` 打开地雷，也不会把 `#WAVxx` 当地雷音播出来。原版地雷音来自 `sound/engine.ogg`，预览还没有这个资源。

BMSON 里 `x <= 0` 是 BGM，`x > 0` 是键音。`c == true` 继续不重触发。

## 曲信息

BMS 的 `previewDocumentData` 本来就只改 `#WAV` 行，所以 `#TITLE`、`#ARTIST`、`#GENRE`、`#PLAYLEVEL`、`#RANK`、`#PLAYER`、`#VOLWAV` 会留在预览字节里。`#PATH_WAV` 只拼 WAV。`#BMP` 和 `bgaDirectory` 仍是谱面目录。

BMSON 的 `context` 现在把主窗传来的曲名、曲师、曲风、`level`、`judgeRank` 和模式写进预览文本，再接上 `#WAV`。双人 `beat-10k` / `beat-14k` 写预览专用的 `#PLAYER 3`。明确的 battle 写 `2`。空 hint、`beat-7k`、`beat-5k` 写 `1`。这份文本不写回 BMSON。

`judge_rank` 100 写成 `#JUDGERANK 100`，不写成 `#RANK 100`。`PreviewBmsSource.metadata` 用整条命令名区分两者。

popn、键盘、generic、circular 和未知模式不在 5/7/10/14 皮肤容量里。预览文本不写 `#PLAYER`，也不另造一套能玩的列。现有 `PreviewUbmStyle.nativeColumns` 对放不下的键仍是通道 0、矩形为空。这次没有改 Style。

`#VOLWAV` 只保留原文。播放器还没有按它调音量。BMSON 没有这个字段时不补一个数。

## 测试

Swift 6、`arm64-apple-macosx14.0`。

`LegacyBmsonPreviewTests` 已通过。分类测试用 `audibleBmsNotes` 和 BMSON `context` 的真实音符调用 `playChart` 与 `setAudibleKinds`：

- 只开键音时，起点键和稍后的 hidden 会排上，BGM 不会
- 键音加 BGM 时，BGM 也会排上
- 只开地雷时，调度数是 0，谱面 WAV 不会被当成地雷
- `x <= 0` 的 BMSON 音被键音过滤挡住，续播不进发声表
- `#JUDGERANK 100` 在文本里，没有 `#RANK`
- battle 是 `#PLAYER 2`，popn-9k 和 keyboard-36k 没有 `#PLAYER`

`PreviewBmsSourceTests` 已通过，包含原先的条件分支缓存。新增：`#JUDGERANK` 不进入 `rank`，`#VOLWAV` 和 `#PLAYER` 按原文留下，改写 WAV 时曲头和 `#BMP` 不动，`previewPacked` 符合 `!autoSeparate || playerHeader == 3`。

全部 `macos/Sources/IBMSNative/*.swift` 在一份快照上 `-typecheck` 通过。当时预览窗和播放器文件仍在被别的改动保存，直接对工作区编会报文件中途变化。快照本身没有新的类型错误。已有警告是取色器的 `windowFrameColor` 和 BmsONE 菜单里的 `NSApp`。

`PreviewBmsSource.swift` 已经在 `macos/cmake/preview-audio.cmake` 的 `IBMSNative` 源列表里。这次没有改 CMake，也没有做完整 App 链接。

## 局限

- 不能声称原版解析、seek、暂停或音量已经兼容。`#VOLWAV` 只是数据。
- 地雷没有 `sound/engine.ogg`。种类正确，声音没有。
- 预览窗现有的 `PreviewUbmChartFacts` 用 `#RANK` 前缀，并且只排除 `#RANKING`。`#JUDGERANK 100` 会被它读成 `ERANK 100`。当前信息条走的是 `PreviewBmsSource.metadata` 的整词 `RANK`，所以不会把判定等级显示成 BMS 段位。窗口若改用前缀解析，要避开这个头。
- `PreviewChartSnapshot` 仍没有曲师、曲风、等级、段位。这些在 `PreviewBmsMetadata` 和 `documentData` 里，等窗口自己读。
- 5/7/10/14 以外的模式没有可玩列。不要把 `playerHeader == nil` 当成单人再铺一套键。
- `#SWITCH` 和盘符 WAV 的旧限制还在。编辑器里的条件谱仍然是空谱，只有预览快照展开。
