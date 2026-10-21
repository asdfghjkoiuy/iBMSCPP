# UM 预览条件分支公共接口

原生 BMS 预览在读到 `#RANDOM` / 条件时，用未保存原字节展开一份只读快照。编辑文档、撤销历史和脏标记保持不动。这不是 uBMplay 解析器的完整复刻，也不是把 BMS 转成 BMSON 再预览。

## 主窗

`MainWindowController`

- `previewAudioContext() -> PreviewAudioDocumentContext?`  
  先取编辑文档的 `currentBytes()`。没有随机或条件时，音符、画面、速度和 WAV 都来自这份字节。有随机或 `hasConditionals` 时，展开一次并缓存只读 `DocumentSession`。之后同一字节再播，无论从头、Home 还是 Here，都复用该分支。`playHereBeat` 每次读当前指针，不在缓存里。
- `reloadPreviewRandomization()`  
  清掉缓存的选择和展开结果。下一次预览才重新选择。不写文档，不接空格键。空格重载由窗口或主 App 以后调用这个函数。
- `setPreviewRandomChoices(_ values: [Int]?)`  
  测试注入。`nil` 表示每个 `#RANDOM` 在 `1...max` 里取一次。注入本身不清缓存；同一字节要换支，先 `reloadPreviewRandomization()`。
- `previewRandomValues: [Int]`  
  当前缓存的选择。还没展开时是空数组。

展开调用 `IBMSBmsonBridge.randomMaxima(fromBmsData:)` 和 `applyRandom(to:values:skipBetweenRandomAndIf:)`。`skipBetweenRandomAndIf` 固定为 `false`。缺的或越界的槽不传 `0` 进核心，避免核心每次 `rand`。

## 纯数据

`PreviewBmsRandomCache`

- `resolve(raw:maxima:injected:expand:) -> PreviewBmsRandomResolution`
- `reload()`
- `storedValues`、`storedRaw`
- `choose(maxima:injected:) -> [Int]`

`PreviewBmsRandomResolution` 含 `branch`（`values` 与 `expanded`）和 `reused`。

`PreviewBmsSource`

- `shouldExpand(maxima:hasConditionals:) -> Bool`
- `metadata(from:noteCount:) -> PreviewBmsMetadata`
- `decodePreviewText(_:) -> String?`
- `resources(from:chartDirectory:) -> PreviewBmsResources`
- `previewDocumentData(data:chartDirectory:) -> Data`
- `openPath(fileName:pathWav:chartDirectory:) -> String`
- `stockOpenPath(fileName:chartDirectory:) -> String`

`PreviewBmsMetadata` 的 `title`、`artist`、`genre`、`playLevel`、`rank`、`notes` 都是可选。没有对应头就保持 `nil`。`notes` 只保存调用方从同一份字节数出的数量。

`PreviewBmsResources` 把 WAV 和 BGA 分开：`pathWav`、`wavDirectory`、`wavNames`、`wavFiles` 管声音；`bgaDirectory` 始终是谱面目录；`bmpFiles` 保持 `#BMP` 原文。

`previewDocumentData` 在现有播放器拼不出目标 WAV 时，才把 `#WAV` 行改成打开路径。其它行按原字节复制。返回值只给预览，不能保存。没有 `#PATH_WAV`、普通相对名时，返回入参本身。

`LegacyBmsonPreview.audioMetadataDocumentData(wavTable:)` 就是 `encodeWavTable`。只有 `#WAV` 行，没有标题或 BGA，也不能当谱面存档。预览上下文仍传带谱头的 `previewDocumentData`，这样现有 `PreviewUbmChartFacts` 还能从同一份字节读到等级和段位。

## 曲信息还没进画面模型

`PreviewChartSnapshot` 仍只有 `title`。预览标题用 `metadata.title`，没有标题时传空字符串，不写 “Untitled”。`artist`、`genre`、`playLevel`、`rank`、`notes` 先留在 `PreviewBmsMetadata`。要显示它们，需要以后给快照或预览上下文加字段；这次不加。
