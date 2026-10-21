# 默认 uBMplay 预览整合（2026-10-21）

默认 F5 / F6 / F7 本来就已经进同一个内置非模态预览窗。这一轮没有重做播放器，也没有加选择器。补上的是：app 搬家后仍能从自己的 `Resources/UbmplayReference` 读到官方 1.5.2 图集。

## 接线（未改）

`AppDelegate.swift` 本轮字节未动，SHA-256 仍是 `4af6a93ca16536ccb689b4eec734fb4e01e696db665f80d4876ba65c2850f3e2`。

| 入口 | 去向 |
| --- | --- |
| 菜单 `TBPlayB` / `TBPlay` / `TBStop`，快捷键 F5 / F6 / F7 | `MainWindowController.performChromeCommand` |
| 工具栏同名命令 | `MainWindowContentView` 调同一组闭包 |
| `AppDelegate.playPreview` | `showWindow`，再 `playFromStart`（拍 0）或 `playFromPointer` |
| 停止 | `PreviewWindowController.stopPlayback` |
| 播放器 | `ApplicationState.previewPlayer`，预览窗 `init` 里直接持有 |
| 谱面 | `previewAudioContext()`：未保存 BMS 字节、`#RANDOM` 缓存、BMSON 快照、1P/2P 车道和 BGA |

预览窗 `styleMask` 是普通窗口，走 `showWindow`，没有模态会话。外置 viewer 仍是预览菜单里另外三项，没有功能键。用户偏好和旧外置配置没改。

`PreviewPlayfieldMetalSession.init` 里 `loadSkin` 只调用一次。`draw(in:)` 不重新读图。`skinDirectory()` 只返回目录。

## 皮肤查找

`PreviewUbmStyle.skinDirectory()` 顺序：

1. `IBMS_UBM_SKIN_DIR`，目录里五张原图都是普通文件才用。
2. `Bundle.main` 的 `Contents/Resources/UbmplayReference/image`，同样要五张齐全。
3. 仅当编译了 `IBMS_PREVIEW_DEV_SKIN_FALLBACK` 时，才用源码树 `out/reference/ubmplay-1.5.2/ubmplay/image`。

正式 app 不编译第 3 步。`/tmp/ibms-default-preview-build/macos/IBMSNative.app/Contents/MacOS/IBMSNative` 里没有 `/Users/guanhao`，也没有 `out/reference/ubmplay`。谱面和图集测试目标才带这个回退，所以现有测试仍能找到本机参考包。

五张图：`skin_00.png`、`skin_01.png`、`skin_02.png`、`skin_03.png`、`font.png`。

## 官方 archive

`ubmplay/readme.txt` 是 CP932。其中「再配布について」写明：UCN-Soft（http://ucn.tokonats.net/）分发的 archive 不得做任何改动（不改变内容的再压缩不在此限），并且只在无偿分发时才允许再分发；版权不放弃。运行时仍读解压后的 `image/`。bundle 里另外放一份未改的原始 zip，用来满足这个分发形式。

原始 zip 从 `out/reference/ubmplay-1.5.2/ubmplay_152.zip` 逐字节复制到 `macos/Resources/UbmplayReference/ubmplay_152.zip`。SHA-256 是 `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada`，868429 字节。`git check-ignore` 没有忽略它。`git status` 里它是未跟踪文件 `?? macos/Resources/UbmplayReference/ubmplay_152.zip`。本轮没有 commit。

CMake 默认 `IBMS_UBMPLAY_REFERENCE_INPUT` 是这个 vendored zip，类型仍是 `CACHE FILEPATH`，已有缓存可以覆盖。不再默认 `out/reference`。空缓存的 `/tmp/ibms-dp-vendored-default` 配置日志写的输入就是 `macos/Resources/UbmplayReference/ubmplay_152.zip`。显式 `-DIBMS_UBMPLAY_REFERENCE_INPUT=/tmp/ibms-no-such-ubmplay-152.zip` 的 `/tmp/ibms-dp-missing-override` 退出码 1。

stage 脚本在解压之后用 `file(COPY_FILE ...)` 把输入 zip 写成 `stage/ubmplay_152.zip`。该文件是 `target_sources` 的 generated resource，`POST_BUILD` 再把整个 stage 拷进 bundle。

## 构建复制

成功构建时 Ninja 先按 zip 解出 stage，并把原始 zip 放进同一 stage。`LINK_DEPENDS` 这些文件是 app 的链接输入。链接后的 `POST_BUILD` 把 stage 拷进 `IBMSNative.app/Contents/Resources/UbmplayReference`。图集字节变化会让链接和拷贝重跑。代价是图集一变，Swift 可执行文件会重新链接。

Windows `uBMplay.exe` 和 DLL 按数据拷贝，权限 `0644`，构建脚本不执行它们。排除隐藏文件和 IDA 后缀。`readme.txt` 与 zip 内原文相同，SHA-256 `e7e1d1300de05da3498a7d913455c6782ff81dde69a69aaef9b75d69317d29b3`。

bundle 路径：`/tmp/ibms-default-preview-build/macos/IBMSNative.app/Contents/Resources/UbmplayReference/ubmplay_152.zip`。`out/reference` 里的原 zip、vendored 源码 zip、stage、这个 bundle、以及 `/tmp/ibms-default-preview-moved/IBMSNative.app` 里的同一路径，五份逐字节相同，哈希都是上面的 `d10c38ae…16ada`。解压出的 14 个运行文件仍在旁边。对照日志是 `logs/zip-byte-identity.log`。

## 构建和测试

目录 `/tmp/ibms-default-preview-build`，Ninja，Release。目标：`IBMSNative`、`IBMSNativePreviewPlayfieldTests`、`IBMSNativePreviewWindowTests`、`IBMSNativePreviewAudioTests`。三次测试退出码都是 0，日志末行分别是 `PreviewPlayfieldTests passed`、`PreviewWindowTests passed`、`LegacyPreviewAudioTests passed`。没有放宽断言。

图集增量：只改 stage 里 `skin_00.png` 的最后一个字节，没有改 Swift。下一次 `IBMSNative` 是 `[1/1] Linking ... Copy uBMplay 1.5.2 reference`，bundle 里该文件变成被改过的哈希 `7090db227e1fc212fb6877ab2ee187378d392ab6bff4d32cc286561fab8a2938`。从 zip 写回原字节后再构建，bundle 回到 `bcb541fbac571005a79c6f09f7eadb39be3c00638a6bf62854f5d14a8a6cf3ad`。用户的 `out/reference/ubmplay-1.5.2/ubmplay/image` 仍在，目录时间是 10 月 20 日 23:46。

无界面探针把辅助可执行文件放进挪走的 app：`/tmp/ibms-default-preview-moved/IBMSNative.app/Contents/MacOS/DefaultPreviewSkinProbe`。工作目录 `/private/tmp`，环境里没有 `IBMS_UBM_SKIN_DIR`。没有启动 `IBMSNative` 本体。装入原始 zip 之后又跑了一次，`logs/probe-vendored-zip.log` 仍是 `result ok`：`skinDirectory()` 返回该 bundle 的 `UbmplayReference/image`，`skin_00` 解出 331×256，哈希与官方图一致。

Playfield / Window / Audio 三次测试是装入原始 zip 之前的退出码 0。这轮没有改它们的源码，也没有重跑。

## 父代理最终复核（默认 Release）

父代理执行 `cmake --preset release`、`cmake --build --preset release --target IBMSNative`，均退出 0。交付应用为 `out/build/release/macos/IBMSNative.app`。另以空构建目录 `/tmp/ibms-default-preview-clean` 完成配置及构建，默认解析源码树内官方 ZIP。默认 Release bundle ZIP 与源码 ZIP 的 SHA-256 均为 `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada`。

默认 Release 的四项预览 CTest 最终为 3/4：Playfield 1.28s、BGA 35.65s、Window 33.11s 通过；Audio 66.96s 失败，总时长 137.00s。失败断言是 `4x file onset 0.0106875`，现有测试要求 `0.02 < onset < 0.15`。同批 100 个短音的 hits/bands 均为 100，零 steals/drops，但测试提前退出，不能宣称完整音频回归通过。没有放宽断言或重复运行换绿；本轮不把隔离构建的先前成功覆盖到默认 Release。

日志位于 `out/validation/default-preview-integration-20261021/`：`default-release-configure.log`、`default-release-build.log`、`default-release-tests-build.log`、`default-release-preview-ctest.log`、`clean-configure.log`、`clean-build.log`。用户暂不方便提供解锁/前台显示会话，因此未启动主程序做 UI 或实际屏幕帧率验收。

## 本轮源码 SHA-256

| 文件 | 开始 | 结束 |
| --- | --- | --- |
| `PreviewUbmStyle.swift` | `7aaa8f88b49f60e55e0533203ae24dd41106af1095258e68b7ac8b9a5c9fa012` | `382b1aabd53d9c77906b753213e47c02152c434d673b7e1ce68d7b63e7c5f4d5` |
| `preview-audio.cmake` | `df342d30ab8a9427515d40988b9ae180434593d9dffe8040b6f4e71ffb478649` | `d52a64422bb1e40ae7067cf6a130ffc9db97a05b37162b14bb31a15f5bd76ba9` |
| `macos/Resources/UbmplayReference/ubmplay_152.zip` | 无 | `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada` |
| `ApplicationState.swift` | `4fe2b62ba74d1d7e042bb9483f43e7797017b0ba51cc12934b80cb09dd740605` | `133fd0e2715c3b516bf40df0cf510b2a051bf7837635e07308ab06d9a6d80c22` |
| `AppDelegate.swift` | `4af6a93ca16536ccb689b4eec734fb4e01e696db665f80d4876ba65c2850f3e2` | 相同 |

`ApplicationState.swift` 只改了 `previewPlayer` 的注释。没有提交，没有推远程。没有跑前台窗口。

## 最终独立资源审计

gpt-6.1-sol high 只读审计未发现当前默认 Release 资源交付阻塞。正式 app 未编译开发源码 fallback，ZIP 固定 hash、14 个 payload 和原始 ZIP 的副本一致性通过。该审计不覆盖音频正确性，不关闭上述 Audio 失败。

发现 P2 增量构建边缘问题：最终 bundle 资源仅由链接后 POST_BUILD 写入，Ninja 没有最终 bundle 资源输出边。若手工删除 bundle 内某张皮肤，同时 executable/stage 未变，普通增量构建未必重链接和补回；需要重新链接或干净构建。当前交付 bundle 资源齐全，源图集正常更新的依赖链仍有效。此项来自源码/生成图审计，未破坏用户构建做删除复现。
