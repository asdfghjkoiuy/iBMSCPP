# 源码来源锚点

这份来源表只固定本次初始清单使用的版本和材料。它不表示二进制等价，也不表示功能、视觉或运行时行为已经通过。

| 来源 | Git 提交 | 取得位置或说明 |
| --- | --- | --- |
| 本地 µBMSC，含继承的 iBMSC 代码 | `f5b21d1de50ce28202d1b2e8d2f614fabde18092` | 本地嵌套仓库 `iBMSC/`；`origin` 为 `https://github.com/zardoru/iBMSC.git`；`upstream` 为 `https://github.com/aqtq314/iBMSC.git`。 |
| bmhelper | `d6b674368b1e0c09baaa8dbb01d01c01f67f0791` | <https://github.com/zardoru/bmhelper>。窗口与客户区见 `docs/inventory/bmhelper-windows.md`。 |
| BmsONE | `bb3406eeb8f45d79350241f09bb897dd229ce3af` | <https://github.com/excln/BmsONE>。窗口与客户区见 `docs/inventory/bmsone-windows.md`。 |
| beatoraja | `bda2b72f8607daed9e9f651f1e92fc445d42f114` | 父审计通过 `git log` 核对；临时检出位于 `/tmp/ibms-design.sLhFrh/beatoraja`。 |
| woslicer II | 帮助未写版本号；zip SHA-256 `5079a6739295f02167d2a12796da3df1632d3d96123aabd4f72881f7bb8f4c65` | 官方归档：<https://cerebralmuddystream.nekokan.dyndns.info/soft/woslicerII.zip>。文件日期 2011-01-29。能力与哈希见 `docs/inventory/woslicer-windows.md`。 |
| woslicer III | 帮助未写版本号；zip SHA-256 `8319d792a792f9051a31cdf0ea3c9bdcbc2b1bbf18209560329970273592a22c` | 官方归档：<https://cerebralmuddystream.nekokan.dyndns.info/soft/woslicerIII.zip>。exe / `readme` 日期 2015-12-07。能力与哈希见 `docs/inventory/woslicer-windows.md`。 |

## 证据边界

本次清单以本地 µBMSC 提交为源码证据。临时目录只用于父审计已核对的来源，不是本仓库的持久依赖。woslicer II、III 的已检查归档没有源代码；不能由此推断其他位置不存在源代码。

`mubmsc-windows.md` 记录 Designer 声明、文字、默认值和几何线索。`mubmsc-interactions.csv` 记录指定行为文件中可直接定位的 25–50 个动作；CSV 的每行都使用 `observed-source/unverified-runtime`，表示源码已观察，运行时仍待验证。
