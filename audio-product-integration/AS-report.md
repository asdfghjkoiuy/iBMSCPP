# AS 极小 Session 修复（2026-10-21）

只改 `macos/Sources/IBMSNative/PreviewUnifiedAudioSession.swift`。探针在 `audio-product-integration/probes/AS/`。没有改 Worker、Legacy、tests、C++、CMake、第三方或窗口。

输入审查：`out/validation/ubmplay-parity-20261020/audit-performance/lease-short-review.md`。该审查记录的 Session 基线 SHA-256 是 `d08ce45cad9eef64ab701cb12f0fb6caa44fef57361b880b3e516f70fa360455`。本报告不把那次基线重新宣称为本次写入前的原子快照。

## 改了什么

1. 终止态。`shutdown` 第一次把 `terminated` 置上并拆掉 adapter、source、tap 和配置观察者，然后请求 worker 退出。再调用直接返回。`submit`、`update`、`attachPending`、`startEngine`、`startAdapter`、`installSourceNode`、`noteDeviceConfiguration`、`debugCaptureToken`、`debugHolderCount`、`debugReplaceBinding`、`consumeRenderFault` 在终止后不再进入租约。迟到的 `onBooted` 看到终止态后不 attach。

2. Token。`PreviewRenderToken` 只在 `pointers.lock` 内构造。`init` 的 `hold` 发生在同一把锁里，出锁前 holder 已经加上。不再把 publication 裸指针带出锁再 `hold`。`debugHolderCount`、`consumeRenderFault` 和设备配置里的 `rebind` 走既有 `withQuery`。`rebind` 发生在 debug 换绑路径时，用的是锁内已经 hold 的 token。闭包仍强捕获 token。`PreviewRenderToken.deinit` 仍只 `unhold`。C 对象的最后释放仍在退休队列，不在音频回调里。

3. 时钟。`mappedClock` 不再只读 live。1024 个 `IBMSPreviewMixClock` 在 `init` 分配并初始化一次，`deinit` 释放；查询使用 `ibms_preview_mix_copy_clocks` 写入这块缓冲。`now` 落在某段 `[start, end)` 内时，只对这一段调用一次 `ibms_preview_mix_span_map`。`now` 比缓冲里每一段都早时，保留上次确认的 chart/wall，不用未来段的 sample 0。已经走完的最后一段停在末端：`validFrames < frameCount` 时样本是 `validFrames`（`span_map` 的 used 取到有效帧终点）；`validFrames >= frameCount` 时样本是 `frameCount - 1`，因为 `span_map` 拒绝 `index >= frameCount`。超出末端不再乘 rate。rate、seek、underrun 的空隙停在前一段，不把两段的斜率接起来。这段 host 是 source callback 时间，不是设备 post-tap，也不含扬声器延迟。

## SHA-256

- `macos/Sources/IBMSNative/PreviewUnifiedAudioSession.swift`：`48dbde649c52bf141c573ad657f3217c7b4f6ed32782b0aa66e26a516ed8dde3`
- `audio-product-integration/probes/AS/span-clock-checks.swift`：`5ba7b4139a4e203f7869b653678478bf405c5e851315f247b6c7b5ba267c43c1`
- `audio-product-integration/probes/AS/run-span-clock-probe.sh`：`282bab1bec85baacba158feea0a5ad2079f7f2a2dde1f6dfe3a637ace8b8101e`
- 编译产物 `/tmp/ibms-ubm-b1-build/macos/IBMSNativePreviewAudioTests`：`b0395e492b5297e316b1057d89d82cc91926fa55e0831c61a821bb0d95d769b3`

## 命令

```sh
audio-product-integration/probes/AS/run-span-clock-probe.sh
```

输出：`as-span-clock-probe ok`。探针从 Session 的 `AS-SPAN-CLOCK-BEGIN/END` 抽出 `PreviewHostSpanClock`，注入 span，不创建 `AVAudioEngine`，不调用租约。chart/wall 断言使用与 `span_map` 相同的 used 公式，作用在被选中的那一段上。

```sh
cmake --build /tmp/ibms-ubm-b1-build --target IBMSNativePreviewAudioTests
```

退出码 0。链接阶段有既有警告：`ld: warning: ignoring duplicate libraries: 'macos/libIBMSPreviewMixBridge.a'`。这次输出里没有 Worker 编译错误。没有运行 `IBMSNativePreviewAudioTests`。

## 未验收

- 不是扬声器同步，也没有改设备 post-tap 或 downmix。
- `validFrames == frameCount` 时，冻结样本是 `frameCount - 1`，比有效帧的右端点少 1 个 source sample。`span_map` 不能对 `index == frameCount` 返回右端点。没有用下一段的 chart 去补这 1 帧。
- 没有用真实 AV 或租赁释放去复现 shutdown 后的 UAF。终止态和锁内 hold 是代码收口，不是崩溃回归证明。
- 正常播放路径仍按 lease-short-review：未把它签成已复现 UAF，也不据此宣布整条音频生命周期通过。
- 历史只覆盖桥里最近 1024 段。更早的 span 被覆盖后，这次查询看不到。
- Worker 的 clear / `withQuery` / 退休队列没有改。并发的 Worker 改动不在这次范围内。
- 探针没有链接 MixBridge，因此没有执行 C `span_map` 本体。
