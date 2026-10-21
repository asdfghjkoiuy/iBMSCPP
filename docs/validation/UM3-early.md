# UM3 预览分类与曲信息公共接口

BMS 和 BMSON 仍是两套模型。曲师、曲风、等级、段位、人数和音量原文留在预览文本和 `PreviewBmsMetadata`，不写进 `PreviewChartSnapshot`。下面这些函数只生成预览用的副本，不写回编辑器字节。

## 声音类别

`PreviewAudioKind` 仍由播放器定义：`bgm`、`key`、`mine`。映射在预览侧完成。

`LegacyBmsonPreview.audibleBmsNotes(events:longNotes:)`

- `bgm` → `.bgm`，保留谱面 `#WAV` 键
- `mine` → `.mine`，`wavToken` 为空。不把地雷的谱面 WAV 键交给播放器
- `hiddenNote`、`normalNote`、`longNote` → `.key`
- hidden 走可听通道时会发声，画面仍不画
- 已配对长音只在起点发一次，种类是 `.key`

原版地雷音是 `sound/engine.ogg`。这个文件还没接进预览，所以地雷现在不会出声。种类仍然是 `.mine`。

`LegacyBmsonPreview.notes(channels:resolution:)`

- `SoundNote.x > 0` → `.key`
- `SoundNote.x <= 0` → `.bgm`
- `continueFlag == true` 两种都不重触发

`setAudibleKinds` 仍属于播放器。默认听得见的是 `.bgm` 和 `.key`。

## 曲信息

`PreviewBmsSource.metadata(from:noteCount:)` 按整条命令名读取，最后一条同名头生效。

| 命令 | 字段 |
| --- | --- |
| `TITLE` / `ARTIST` / `GENRE`（含 `GENLE`）/ `PLAYLEVEL` | 原有字段 |
| `RANK` | `rank`。`RANKING` 不算 |
| `PLAYER` | `player`，原文 |
| `VOLWAV` | `volwav`，原文。播放音量还没乘上 |
| `JUDGERANK` | `judgeRank`。不会写入 `rank` |

`parsedPlayerHeader(_:)` 把 `#PLAYER` 原文收成正整数。缺、空或不是整数时是 `nil`。

`playerLayout(modeHint:)` 只解释 BMSON 的 `modeHint`，不改 BMS 谱里已经写好的 `#PLAYER`。

| hint | 皮肤 | `#PLAYER` |
| --- | --- | --- |
| 空串、`beat-7k`、`beat-5k` | 能放 | 1 |
| `beat-5k-battle`、`beat-7k-battle` | 能放 | 2 |
| `beat-10k`、`beat-14k` | 能放 | 3 |
| popn、键盘、generic、circular、未知 | 不能放 | 不写 |

`previewPacked(autoSeparate:playerHeader:)` 就是 `!autoSeparate || playerHeader == 3`。

`LegacyBmsonPreview.previewPlayerHeader(modeHint:)` 与上表同一个数。`previewDocumentData(wavTable:title:artist:genre:playLevel:judgeRank:modeHint:volwav:)` 把这些头和 `#WAV` 合成一份预览文本。`judgeRank` 写成 `#JUDGERANK`，不写成 `#RANK`。没有传入的字段不补。不写 `#PATH_WAV`，也不写 BGA。

`context(...)` 新增可选参数 `artist`、`genre`、`playLevel`、`judgeRank`、`volwav`。主窗把 BMSON 文档上的曲师、曲风、`level`、`judgeRank` 传进去。`audioMetadataDocumentData(wavTable:)` 仍然只有 `#WAV`。

BMS 预览继续用 `PreviewBmsSource.previewDocumentData(data:chartDirectory:)`。它只在需要时改 `#WAV` 行，`#TITLE`、`#ARTIST`、`#GENRE`、`#PLAYLEVEL`、`#RANK`、`#PLAYER`、`#VOLWAV` 和 `#BMP` 留在原字节里。`#PATH_WAV` 不改变 `bgaDirectory`。

## 条件分支

`reloadPreviewRandomization()`、`setPreviewRandomChoices(_:)`、`previewRandomValues` 和同一份原字节的展开缓存保持 UM2 的行为。这次没有改选择或写回。
