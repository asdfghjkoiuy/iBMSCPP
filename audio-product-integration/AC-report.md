# AC 有界崩溃（2026-10-21）

只修 mixer 双销毁，以及 source/tap 闭包的 MainActor 隔离。没有改资源预算、采样率分档、调度、CMake、MixBridge、第三方或窗口。

## 所有权

`ibms_preview_render_lease_create` 成功之后，mixer 只由 `ibms_preview_render_lease_try_release` 调用 `ibms_preview_grouped_destroy` 一次。`PreviewAudioBridge.mixer` 是同一只对象的非拥有别名。`clearChart` 调用 `ibms_preview_grouped_reset`，清掉各组 SRC、声部指针和暂存，不销毁对象，也不换成新指针。`releaseFresh` 只在 lease 还没接走所有权时销毁。worker 退出时把别名置空，再把 lease 交给退休队列。

## 回调

`previewSourceRenderBlock` 和 `previewDeviceTapBlock` 是文件级函数，不在 `@MainActor` 的 Session 方法里写字面闭包。两者返回 `@Sendable` 闭包。source 只捕获 `PreviewRenderToken`，块体只调用 `ibms_preview_render_lease_drive`。tap 不捕获 Session；返回闭包之前先碰已经存在的 `PreviewDeviceTapRate` 锁。这两条路径没有 `MainActor.assumeIsolated`，没有关掉检查，也没有降 Swift 版本。

## SHA-256

- `macos/Sources/IBMSNative/PreviewUnifiedAudioSession.swift`：`9d92e40a5e3dc38a3fd4a0985f2ee4361132d340ca5e230b2892edd9bb24e122`
- `macos/Sources/IBMSNative/PreviewUnifiedAudioWorker.swift`：`95d9a1ba38408623d238ba369b7e5a5d02741e2b7f1df7b62427753cad305b1f`
- `macos/Sources/IBMSNative/LegacyPreviewAudio.swift`：`5f011e00031acdede9551595d14cdb729bab697ea4d5c2e337173283c5886076`
- `macos/Tests/LegacyPreviewAudioTests.swift`：`568a504596ecf6e049fc1bd1f0cab23284b6d9ccc87b2e3ff5ea5bce880dba63`
- `macos/Sources/IBMSBridge/PreviewAudio/IBMSPreviewGroupedMixer.h`：`c4a1d43f2f169b0a227a0068192eedf87dda3329dd0092e0fad9a624f0fbb426`
- `macos/Sources/IBMSBridge/PreviewAudio/IBMSPreviewGroupedMixer.cpp`：`c4a1cdb43abd56226118894a869e953fc383211104bef4519fd7d3c68300ec7d`
- `/tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests`：`433ce46c66b792e5a3f637f029cb44eef8a7a7caf1db7c98fd6b6b8fc722f663`
- `/tmp/ibms-ubm-b1-build/macos/IBMSNative.app/Contents/MacOS/IBMSNative`：`74df0149459aca49a8651f1b0e7dc1a01c9112750ab826c2131221bcef95fe31`
- `/tmp/ibms-ac-asan/IBMSNativePreviewAudioTests`：`5e39577bb2c8cdae0f918f3d822097541a754a814b26d8d92730dc6ca4efa76a`

## 命令

Release 编译，退出码 0。链接有既有警告：`ld: warning: ignoring duplicate libraries`，以及 IBMSNative 里既有的 `windowFrameColor` 弃用和 `NSApp` MainActor 警告。

```sh
cmake --build /tmp/ibms-ubm-b1-build --target IBMSNativePreviewAudioTests IBMSNative
```

ASan 二进制由 clang/clang++ `-fsanitize=address` 与 `swiftc -sanitize=address -swift-version 6` 编出，退出码 0。产物是 `/tmp/ibms-ac-asan/IBMSNativePreviewAudioTests`。

同一进程、`main` 正常 `return`，没有 `_exit`：

```sh
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0:print_stacktrace=1 \
  AC_ONLY=all /tmp/ibms-ac-asan/IBMSNativePreviewAudioTests
```

退出码 0。输出：

```
AC offline 100 ok
AC audible frames=5016 peak=0.0915502 tapRate=44100.0 engine=ok
AC all ok
```

offline 是 100 次同一只 mixer 上的 clear/reset、再拉响、再退休 `try_release`。audible 是一轮真实 AVAudioEngine source：tap 帧峰值约 0.0916，设备 tap 采样率 44100。进程没有 `dispatch_assert_queue_fail`。

另一次 `ASAN_OPTIONS=halt_on_error=1:abort_on_error=1:detect_leaks=1` 的 offline 在测试打印之前退出码 134。ASan 只打出 `detect_leaks is not supported on this platform`。这不是 mixer 报告。本机 ASan 不能做 leak sanitizer。`halt_on_error=1` 的通过跑仍然会在 double-free 或 UAF 上中止。

## 未修

- rareFs、预算、调度没有动，也没有跑全套音频测试。
- `AW_ONLY` 仍用 `_exit` 跳过析构。这次 AC 选择器不走那条路径。
- 本机不能开 `detect_leaks`，所以没有泄漏消毒器的退出证据。
- `PreviewFilePageProbe` 自己开的 bridge 仍不退休。这次没有跑它。
