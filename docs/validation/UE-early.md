# UE 预览 Space 重载接线

只准备改 `macos/Sources/IBMSNative/AppDelegate.swift`。这次读取时预览窗还没有可接的 reload 回调，所以先不改产品代码。

## 已经能用的主窗

`MainWindowController.reloadPreviewRandomization()` 已在。它清掉预览随机缓存和展开结果。不改编辑文档，自己不接空格键。下一次预览才按当前注入值或 `1...max` 再选一次。

## 预览窗当前签名

`PreviewWindowController` 的初始化只有：

- `state: ApplicationState`
- `documentSource: @escaping () -> PreviewAudioDocumentContext?`
- `onPlayheadBeat: ((Double?) -> Void)?`

文件里没有 `onReloadPreview`，也没有 `setReloadHandler`。`playFromStart()` 和 `playFromPointer()` 只进入 `play(explicitBeat:)`。Home 对应的 seek 动作不带 `reloadChart`。只有空格按住约 500 ms 的 `PreviewUbmAction.reloadChart` 表示重载；这个动作还没有从预览窗调到主窗。

`AppDelegate` 里现有的 `documentSource` 和 `onPlayheadBeat` 都是 `[weak self]`，用户已有修改保持不动。

## 接口出现后的接法

以当时的 `PreviewWindowController.swift` 为准，不另造参数名。

1. 初始化如果有 `onReloadPreview`，只在 `previewWindowController` 的 lazy 初始化里加上：

```swift
onReloadPreview: { [weak self] in
    self?.mainWindowController.reloadPreviewRandomization()
}
```

闭包体不在初始化时执行。`[weak self]` 与现有两个回调相同，避免预览窗强持有 `AppDelegate`。

2. 初始化没有这个 label、但有 `setReloadHandler` 时，在 `applicationDidFinishLaunching` 里于该控制器初始化之后调用。闭包同样弱捕获。不在 `playPreview`、`playFromStart`、`playFromPointer` 或 `hidePreview` 里清随机。

普通播放和 fromHere 继续只显示并播放。只有预览窗在 Space 重载时调用上述闭包，才会重新随机。Home 不走这条回调。

## 复核

`PreviewWindowController.swift` 在 20:25 之后没有再改。初始化仍然只有上面三个参数。全库没有 `onReloadPreview` 或 `setReloadHandler`。因此没有改 `AppDelegate.swift`，也没有为了接回调去改预览窗。
