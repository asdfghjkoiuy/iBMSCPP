# 默认预览资源分发修正（2026-10-21）

默认播放器继续使用已有的内置预览。这一轮只补上 uBMplay 1.5.2 原归档的随包分发，并让干净源码树在不依赖 `out/reference` 的情况下完成 configure。

未提交，未推远程。未启动 `IBMSNative` 窗口，未跑全量 CTest。

## 许可

`ubmplay/readme.txt` 的「再配布について」原文：

> UCN-Soft (http://ucn.tokonats.net/) で配布しているアーカイブに一切の変更を加えず (内容を変更しない再圧縮はこの限りではありません)、また配布形態が無償の場合に限り、無制限に再配布を許可します。事前の連絡や許可も必要ありません。ただし、それによって生じるコストは再配布を行う人が各自で請け負うこととします。また、著作権は放棄しませんのでご注意ください。

允许无偿再分发的是 UCN-Soft 发出的归档本身，内容保持原样。说明里的括号允许不改内容的再压缩；本轮没有再压缩，放进仓库和 app 的是同一份原始字节。图集查找仍读解压后的 `image/`。`readme.txt` 仍在 bundle 内。

## 归档来源与跟踪

来源是本机已有的 `out/reference/ubmplay-1.5.2/ubmplay_152.zip`。任务记录里的官方地址是 `http://ucn.tokonats.net/archives/ubmplay/ubmplay_152.zip`。本轮没有下载，configure 和构建也没有访问网络。

原字节复制到 `macos/Resources/UbmplayReference/ubmplay_152.zip`。源文件与仓库副本 `cmp` 相同，大小 868429 字节。SHA-256：

`d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada`

`git ls-files` 对这个路径没有输出。`git check-ignore` 未忽略它。`git status --short`：

```
?? macos/Resources/UbmplayReference/ubmplay_152.zip
 M macos/cmake/preview-audio.cmake
```

归档目前未跟踪。仓库根目录没有 `.gitattributes` 会在提交时改写 zip 字节。本轮不提交。`macos/Resources` 里原有主题和 chrome 资源都还在，这个新目录里只有这一份 zip。

## 干净默认输入

`IBMS_UBMPLAY_REFERENCE_INPUT` 仍是 `CACHE FILEPATH`。未传入覆盖时，默认值是源码树里的绝对路径：

`/Users/guanhao/VSCodeAlgorithmTrain/CPP/ibmsc/iBMSCPP/macos/Resources/UbmplayReference/ubmplay_152.zip`

也就是 `CMAKE_CURRENT_SOURCE_DIR`（`macos/`）下的 `Resources/UbmplayReference/ubmplay_152.zip`。开发者仍可用 `-D` 指向另一份官方 zip，或一个含 `ubmplay_152.zip` / 已解压运行树的目录。

成功 configure 的状态行：

`mode=zip files=14 archive=.../macos/Resources/UbmplayReference/ubmplay_152.zip input=.../macos/Resources/UbmplayReference/ubmplay_152.zip`

`/tmp/ibms-default-preview-redist-build/CMakeCache.txt` 里该变量类型是 `FILEPATH`，值就是上面的仓库归档。`build.ninja` 中没有 `out/reference`。

显式覆盖到不存在的 `/tmp/ibms-ubmplay-missing-does-not-exist` 时，configure 在 `macos/cmake/preview-audio.cmake:278` 失败，退出码 1。成功构建目录是另一个路径，没有被这次失败覆盖。

## 构建

目录 `/tmp/ibms-default-preview-redist-build`，Ninja，Release，`BUILD_TESTING=OFF`。只构建目标 `IBMSNative`。configure 退出码 0，构建退出码 0。链接行含 `Copy uBMplay 1.5.2 reference and original archive into the app bundle`。

`POST_BUILD` 先把既有 14 个运行文件拷进 `Contents/Resources/UbmplayReference`，再把原 zip 拷到 `Contents/Resources/UbmplayReference/ubmplay_152.zip`。Windows `uBMplay.exe` 和各个 DLL 的权限是 `0644`，构建没有执行它们。

bundle 内 zip 与仓库归档 `cmp` 相同，SHA-256 同为 `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada`。14 个解压文件与 zip 内对应条目哈希一致，没有多出的运行文件。

| 相对路径 | SHA-256 |
| --- | --- |
| `image/font.png` | `6011eb5b8e9ea63c8888b2d6adfdc14e54759407e736d0053c4060bd97822d49` |
| `image/skin_00.png` | `bcb541fbac571005a79c6f09f7eadb39be3c00638a6bf62854f5d14a8a6cf3ad` |
| `image/skin_01.png` | `e09e374d05ade3afe1124e92dbf5a2c99f6a2670c5fd9652ac925eb3f30fe362` |
| `image/skin_02.png` | `a17eabb3908a41745a80ef279b96a5802ece9c9292a1b0af080b6c3af4cf438b` |
| `image/skin_03.png` | `ea525c6232d368c70cdf624c865181d9dc2ed7a0a62970eaa014ec4120ed9cc5` |
| `image.dll` | `72c4f0825108bbc1c583f25b3af24671e312a529c8affe85a6b770e277e04f65` |
| `libogg.dll` | `119534763451260db6bc7503675b366cbb98e10476c3e9e8cf36c17e91a45f26` |
| `libvorbis.dll` | `1b52157629f508436d958834c934a09a2cb05fdd70fc3ad7090e9a1aacfe23ac` |
| `libvorbisfile.dll` | `e3625bc73f6e9f6f2d46eccbbcd379226b582c1882d4012e990127682aeeef3d` |
| `movie.dll` | `49e97a9a7c7912cde7437619ba5aaecc47b08d0ee4dba61ec3b17f0ab54ffe6b` |
| `readme.txt` | `e7e1d1300de05da3498a7d913455c6782ff81dde69a69aaef9b75d69317d29b3` |
| `sound/engine.ogg` | `8bbd7a40480cadc0c4039f214b3d1a3399eccf0bb217b7e4509d6e7c76a227e2` |
| `sound.dll` | `09a0bd1dcd3177feeb33c56020c756dc98f94123b69018332b58856fb4ea98ef` |
| `uBMplay.exe` | `7c916e531ee3fa2724bb2890e2e9614562b25a0f8deb2ebf646c72dca3808e90` |

## 挪走后的探针

app 复制到 `/tmp/ibms-default-preview-redist-moved/IBMSNative.app` 后，bundle zip 与仓库归档仍然 `cmp` 相同。辅助程序 `DefaultPreviewSkinProbe` 放在该 app 的 `Contents/MacOS/`，工作目录是 `/tmp`（进程内 `cwd=/private/tmp`）。环境里没有 `IBMS_UBM_SKIN_DIR`。没有启动 `IBMSNative`。

探针退出码 0。`skinDirectory()` 返回：

`/tmp/ibms-default-preview-redist-moved/IBMSNative.app/Contents/Resources/UbmplayReference/image`

`loadAtlas` 读出 `skin_00` 331×256、`skin_01` 137×221、`skin_02` 160×244、`skin_03` 578×228、`font` 258×35。探针打印的 zip SHA-256 与 readme SHA-256 与上表一致。

挪走后的 `IBMSNative` 可执行文件里没有 `out/reference`，没有 `ubmplay-1.5.2/ubmplay/image`，也没有 `/Users/guanhao`。这次构建的 `build.ninja` 没有 `IBMS_PREVIEW_DEV_SKIN_FALLBACK`。正式 app 的图集来自自己的 bundle。

## 退出码

| 步骤 | 退出码 |
| --- | --- |
| 默认 configure `/tmp/ibms-default-preview-redist-build` | 0 |
| 缺失覆盖 configure `/tmp/ibms-default-preview-redist-missing` | 1 |
| `cmake --build` 目标 `IBMSNative` | 0 |
| 探针编译 | 0 |
| 挪走后的 `DefaultPreviewSkinProbe` | 0 |
| bundle 与原 zip 的哈希对照 | 0 |

## 本轮源码

| 文件 | SHA-256 |
| --- | --- |
| `macos/cmake/preview-audio.cmake` | `592062eaae3f922d9e4add2ce7455e7f4e78aa3152c84f0914ab35e177689295` |
| `macos/Resources/UbmplayReference/ubmplay_152.zip` | `d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada` |
| `PreviewUbmStyle.swift` | `382b1aabd53d9c77906b753213e47c02152c434d673b7e1ce68d7b63e7c5f4d5` |
| `AppDelegate.swift` | `4af6a93ca16536ccb689b4eec734fb4e01e696db665f80d4876ba65c2850f3e2` |

`PreviewUbmStyle.swift` 与 `AppDelegate.swift` 的哈希和上一份整合报告结束时相同。`macos/CMakeLists.txt`、菜单、Legacy audio 和测试断言本轮没有改。

日志在 `out/validation/default-preview-redistribution-20261021/logs/`：`configure.log`、`configure-missing.log`、`build.log`、`probe.log`、`bundle-hashes.log`、`strings-fallback.log`。
