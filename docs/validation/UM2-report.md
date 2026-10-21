# UM2 条件预览与 PATH_WAV

原生 BMS 含 `#RANDOM` / `#IF` 时，核心 `chart()` 是空谱。预览现在用未保存原字节展开一次，音符、画面、速度和 WAV 都读这同一份结果。编辑文档仍是条件谱，不写回、不进撤销、不改脏标记。

这不是 uBMplay 全部解析器的复刻。`#SWITCH`、seek、暂停、VOLWAV 和原版随机运行库都不在这次范围内。

## 改了哪些文件

- `macos/Sources/IBMSNative/MainWindowController.swift`
- `macos/Sources/IBMSNative/LegacyBmsonPreview.swift`
- `macos/Tests/LegacyBmsonPreviewTests.swift`
- 新增 `macos/Sources/IBMSNative/PreviewBmsSource.swift`
- 新增 `macos/Tests/PreviewBmsSourceTests.swift`

没有改 `LegacyPreviewAudio`、预览窗、Style、BGA、core，也没有提交。

## 行为

`previewAudioContext()` 先读 `currentBytes()`。`randomMaxima` 非空，或 `hasConditionals` 为真，才调用 `applyRandom`。`skipBetweenRandomAndIf` 为 `false`。选择缓存在 `PreviewBmsRandomCache`。同一字节再次进入预览直接复用已展开的只读 `DocumentSession`。字节变了，或调用 `reloadPreviewRandomization()`，下一次才重选。

默认每个上限在 `1...max` 取一次，并把这个整数传给桥。不把 `0` 交给核心里的 `rand`，所以缓存里的 `previewRandomValues` 就是实际分支。测试用 `setPreviewRandomChoices` 注入；注入不清缓存。

`#PATH_WAV` 只拼 WAV。相对目录、反斜杠、缺末尾分隔符、带空格的目录和文件名会拼到谱面目录下。以 `/` 或盘符开头的目录不再加谱面目录。WAV 文件名本身已是绝对路径时，不再加 `#PATH_WAV`。没有 `#PATH_WAV` 时，WAV 仍用谱面目录。`#BMP` 原文和 `bgaDirectory` 不动。

UQ 只确认 `#PATH_WAV` 的参数与 `"\"` 被 `StrCat` 后写入 `0x42E468`，左右顺序没有钉死。这里按“目录在前、文件在后”实现，否则路径不可用。没有证据表明这个槽也用于 BGA；`#BMP` / `#BGA` 是另一组命令。

现有 `resolveWavURL` 只把以 `/` 开头的字符串当绝对路径。因此 POSIX 绝对 WAV 会写进预览用的文档副本。盘符路径 `C:/wavs/hit.wav` 由 helper 算出，但播放器仍可能把它再拼到谱面目录。这次没有改播放器。

CP932 与 UTF-8 BOM 留在原字节上。解码只用于 `PreviewBmsMetadata`。不需要改 `#WAV` 时，预览字节与展开结果相同。

## 测试

`PreviewBmsSource.swift` 可单独 `swiftc -typecheck`。

`PreviewBmsSourceTests` 已通过。纯数据部分不链接核心。桥部分使用今天的 `out/build/core-random/core/libibms_core.a`，并重新编译了 `IBMSBmsonBridge.mm` 与 `IBMSDocumentBridge.mm`。覆盖：

- 互斥两支的 WAV、标题、BPM、音符，注入 `[1]` 与 `[2]`
- 同一字节再解析不第二次展开
- `reload()` 后注入另一支；编辑字节和 `dirty` 不变；编辑谱仍是空的条件谱
- 内存中的 `currentBytes`（含未落盘的 `#COMMENT`）进入展开
- 普通谱改标题后，预览读到新标题，`dirty` 仍在
- `#RANDOM2` / `#IF1`、外层不中的内层、`#RONDAM`、`#END IF`
- `#RANDOM` 与 `#IF` 之间的标题在 `skipBetweenRandomAndIf == false` 时留下
- BOM 与 CP932 标题字节保留，曲名解码为「あ」，不另造标题
- `#PATH_WAV` 相对、绝对、反斜杠、空格、缺分隔符；BMP 不进 WAV 目录；无 PATH 时退回谱面目录；分支内的 PATH 与标题来自同一支

`LegacyBmsonPreviewTests` 已通过，包含只含 `#WAV` 的 `audioMetadataDocumentData`。

全部 `macos/Sources/IBMSNative/*.swift` 一起 `-typecheck` 通过。完整 App 链接还不行：新文件不在 CMake 里。

## 请 UW 补进构建

在 `macos/CMakeLists.txt` 的 `IBMSNative` 源列表里，`MainWindowController.swift` 旁增加：

`Sources/IBMSNative/PreviewBmsSource.swift`

不要把 `PreviewBmsSourceTests.swift` 放进 App。若要进 `ctest`，另做测试目标并链接 `IBMSNativeBridge` 与 `IBMSNativeBmsonBridge`。这次按约定没有改 CMake。

空格重载只应调用 `reloadPreviewRandomization()`。产品路径不要留下 `setPreviewRandomChoices`。

## 局限

- 不能声称原版解析、seek、暂停、音量或资源缓存已经兼容。
- `#SWITCH` / `#CASE` / `#ENDSW` 仍会让核心把谱面当成条件谱。`apply_bms_random` 不处理它们，预览展开后仍可能是空谱。
- `#PLAYLEVEL` 这里保留原文。原版会 `Val` 后再转回字符串，`07` 不会变成去掉前导零的形式。
- `#LNTYPE`、对象时值、BGA 五态都不在这次。
- 曲师、曲风、等级、段位、音符数在 `PreviewBmsMetadata`。`PreviewChartSnapshot` 没有这些字段，预览窗还读不到。
- 速度条在 BPM 文本无法解析时仍用原来的 120。那是播放时钟的旧后备，不是曲信息默认值。
- 编辑器里的条件谱继续显示空谱。只有预览快照展开。
- 盘符 WAV 路径还要等播放器认识非 `/` 绝对路径。
