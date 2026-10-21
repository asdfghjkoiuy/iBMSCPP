# UE2 Space 重载回调

只改了 `macos/Sources/IBMSNative/AppDelegate.swift`。预览窗、主窗、测试和 CMake 都没动。没有提交。

## 接线

`PreviewWindowController` 的初始化末尾已有 `onReloadPreview: (() -> Void)? = nil`。`AppDelegate` 的 lazy 初始化现在传入：

```swift
onReloadPreview: { [weak self] in
    self?.mainWindowController.reloadPreviewRandomization()
}
```

闭包用 `[weak self]`，初始化时不执行，也不强持有 `AppDelegate`。原有的 `state` 显式存储和 `override init()` 保留。`playPreview`、`playFromStart`、`playFromPointer`、`hidePreview` 没有加清随机。

预览窗只在 `PreviewUbmAction.reloadChart` 时调用这个闭包，入口是 `reloadFromCurrentDocument()`。Home 走 seek，不进这条路径。

## 构建

```sh
cmake --build out/build/ubm-preview-release --target IBMSNative
```

退出码 0。产物 `out/build/ubm-preview-release/macos/IBMSNative.app/Contents/MacOS/IBMSNative` 新于这次源文件修改。

同一次编译里的警告不在 `AppDelegate`：

- `ColorPickerWindowController.swift`：`NSColor.windowFrameColor` 弃用
- `BmsONEWindowController.swift`：`BmsONEMenuBar.make()` 在非隔离上下文引用 `NSApp`

这两处归属原文件，这次没有改。
