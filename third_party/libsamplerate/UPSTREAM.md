# libsamplerate 0.2.2

静态库源码来自官方发布资产，不是 Homebrew bottle，也不是 GitHub 自动生成的 tag 压缩包。

- 版本：0.2.2
- URL：https://github.com/libsndfile/libsamplerate/releases/download/0.2.2/libsamplerate-0.2.2.tar.xz
- 字节数：3319468
- SHA-256：`3258da280511d24b49d6b08615bbe824d0cacc9842b0e4caf11c52cf2b043893`
- 签名：同目录发布的 `libsamplerate-0.2.2.tar.xz.sig`
- 签名密钥：RSA `B8D5315DA00072C0A860889FCE36E117202E3842`，David Seifert `<soap@gentoo.org>`
- 主钥指纹：`31D95CAB6D80D262244A1750A47620E801E47E95`（过期日 2022-01-07）
- 许可证：本目录 `COPYING`，2-clause BSD
- 作者：本目录 `AUTHORS`

`COPYING`、`AUTHORS`、`include/samplerate.h` 和 `src/` 下的库源码与该压缩包内同路径文件字节相同。校验表在 `SHA256SUMS`。压缩包本身不放进仓库。

`config.h.in`、`UPSTREAM.md`、`SHA256SUMS` 是本地构建记录，不是上游文件。`config.h` 在配置期生成到构建目录。

未纳入 tests、examples、docs、Octave、Win32 和 autotools。soxr 不在本目录。
