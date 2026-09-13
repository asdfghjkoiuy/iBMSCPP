# BMS 时序批次清单

这是一批只覆盖时序解析和时序编辑的小型合成样本。样本不含音频、图片或真实曲目；每个文件的字节长度和 SHA-256 都记录在 [`tests/fixtures/bms-timing/manifest.json`](../../tests/fixtures/bms-timing/manifest.json) 中。`tests/bms_timing_fixture_test.cpp` 是独立测试入口，接收样本目录参数，不修改 CMake，也不把旧版播放函数直接当作预期结果。

## 已核对的源行为

原版 iBMSC 的默认初始 BPM 是 120：`ChartIO.vb:17-28` 重建 BPM 表并写入 `Notes(0).Value = 1200000`。`ChartIO.vb:45-50` 将 `#mmm02` 的小节倍率换算为 `ratio * 192`；`ChartIO.vb:58-64` 读取大小写不敏感的 `#BPMxx`、`#STOPxx` 定义并使用 `Val(...) * 10000`。通道解析在 `ChartIO.vb:199-205`：03 是十六进制 BPM，08 是索引 BPM，09 是索引 STOP。

原版 `MainWindow.vb:2281-2327` 的 `GetTimeFromVPosition` 把 STOP 原值先除以 10000，再除以 48 个四分音符单位，并在 BPM 段中累加秒数。该函数对同拍重复 STOP 使用求和，而且当查询点早于未来 BPM 时，按下一 BPM 行切段而没有把查询位置截断。本批按当前明确的时间线规则计算，专门用查询点 3（未来 BPM 在 4）捕捉后一个问题；不会把这两个旧函数特征冒充新核心契约。

本批另用固定提交的 jbms-parser 作为明确标注的播放参考：`Section.java:66-145` 对 03、08、09 在同一位置分别写入 BPM/STOP 映射，后出现的同类源行覆盖先出现者；`Section.java:292-310` 在同拍先处理 BPM，再处理 STOP；`BMSDecoder.java:313-325` 将 STOP 原值除以 192 得到以整小节表示的停顿，再折算为四分音符即原值 `/48`。它是参考播放 profile，不是 bundled jar 的二进制等价证明，也不代表新版 master parser 已完全相同。

固定源地址：

- [iBMSC `ChartIO.vb`（f5b21d1de50ce28202d1b2e8d2f614fabde18092）](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb)；[相关 `MainWindow.vb`](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb)。
- [jbms-parser `Section.java`（e19bcc21c8d4c85d7791ff8d31d73c1cb1ea5d27）](https://github.com/exch-bms2/jbms-parser/blob/e19bcc21c8d4c85d7791ff8d31d73c1cb1ea5d27/src/bms/model/Section.java)；[相关 `BMSDecoder.java`](https://github.com/exch-bms2/jbms-parser/blob/e19bcc21c8d4c85d7791ff8d31d73c1cb1ea5d27/src/bms/model/BMSDecoder.java)。
- [beatoraja 对照提交 bda2b72f8607daed9e9f651f1e92fc445d42f114](https://github.com/exch-bms2/beatoraja/commit/bda2b72f8607daed9e9f651f1e92fc445d42f114)；这里只保留提交锚点，未据此声称完整播放器兼容。

## 手工计算的预期结果

测试使用 `BeatPosition` 表示精确的有理数小节位置、绝对四分音符和事件值；只有 `seconds_at` 的最终秒数输出使用带容差的 `double` 比较。

- 初始 BPM 默认为 120；显式 BPM 改变其所在 beat 之后的行进速度。
- 同一 beat 的 BPM 先生效，再计算该 beat 的 STOP；精确查询点表示到达 STOP 前，查询后续位置才包含 STOP。
- 同一 BPM 或 STOP 位置上的最后一条源行胜出；03 与 08 没有固定频道优先级，重复 STOP 不求和。
- STOP 原值按 `/48` 转成四分音符，再按当前 BPM 转成秒。
- `#BASE 62`、损坏的支持时序行、未定义引用、无效数字和不可表示的拍位置都使时序结果不可用；不能跳过坏行后回退到默认 120。
- `#STOPxx 0` 是有效定义；极小的正 STOP 也应产生有限的正秒数。原始资源定义仍以字节为准。

## 样本分组

`01` 验证默认 BPM；`02` 验证 `0.5`/`1.5` 小节倍率、未来 BPM、扩展 BPM、STOP 以及查询点截断；`03` 验证精确 STOP 到达前后；`04` 是同拍 BPM+STOP、重复 STOP 与反转 03/08 源行顺序，手工计算的预期结果为：3 拍 `3/2` 秒，4 拍到达前 `2` 秒，4 拍包含 STOP 后 `12/5` 秒，5 拍 `13/5` 秒；`05` 验证无效数字和未定义引用；`06` 验证同一 BPM/STOP 定义被多个事件共享；`07` 只提供小种子，测试在内存中生成 1296 个 BPM/STOP 定义来覆盖资源数量压力，不生成巨大媒体资源。

`08` 是 UTF-8 BOM、BOM 后空格、大小写不敏感的 `#bpm 60` 与 `#stopa1 48`，并要求 BOM/CRLF 原始字节保持不变；`09` 含 `#00003`、`#00008:` 和坏的 `#00002`，测试入口还分别用三个独立内存样本确认每一种损坏行都返回不可用和非空诊断；`10` 验证零 STOP；`11` 验证 `#BASE 62` 不可用；`12` 验证超大倍率触发不可表示范围诊断且读取不抛异常；`13` 验证 `0.000000000000000001` 的 STOP 仍是有限正秒数；`14` 同时包含 `#BPM` 与 `#BPM   `，测试入口另分别覆盖两种空初始 BPM，要求报诊断且不静默使用 120。manifest 中的哈希和长度由写入后重新读回计算。

## 时序编辑回归

独立测试还固定了以下源字节和历史契约：

- 对孤立 `#BPM` 设置 `120` 必须形成 `#BPM 120`，不能写成 `#BPM120`；撤销恢复原字节。
- 对 BOM、缩进、`#00002:1  `、CRLF 的样本改倍率时，只替换数值，保留 BOM、缩进、尾随空格和换行；撤销恢复原字节。
- 替换共享资源中的一个时序事件时，事件总数不增加；同坐标再次替换仍更新原事件，擦除后再替换同坐标也只能恢复一个事件。另一个使用者和 `#BPM01`/`#STOP01` 定义字节保持不变。
- 时序事件插入或替换遇到行槽位、资源标识耗尽或 `#BASE 62` 时拒绝提交；失败前已有的重做记录必须仍可用，字节、未保存状态及撤销重做记录保持不变。
- 新倍率导致时间线超出 `BeatPosition` 可表示范围时必须原子拒绝，不能留下不可解析的已提交状态。

当前 `BmsDocument` 头文件和核心实现已公开 `timing()`、`set_initial_bpm`、`set_measure_ratio` 以及时序事件编辑接口。父任务最终 Debug、Release 均为 `9/9`，严格 ASan/UBSan 验证为 `6/6`；独立时序 fixture 和可用性状态变更均已通过。核心重复事件替换路径已修复，测试确认事件数量稳定、同坐标再次替换和擦除后再替换均可工作。

## 范围和未决项

本批只验证 BPM、STOP、倍率、时序查询、有限的时序源编辑和历史原子性。它没有证明音频播放、编辑器显示、BGA、SCROLL、BMSON、完整格式兼容、工具集成或性能行为；也不把旧版 VB 的重复 STOP 求和和未来 BPM 查询问题作为目标行为。`set_measure_ratio` 只覆盖 **Scale measure**（ApplyBeat Case 3）：保留小节内相对位置，并影响后续小节起点。四种模式的入口是 `apply_beat`。Case 0 / 1 / 2 会按绝对拍重归短音、BPM / STOP / `SC` 格子，以及 NT 长音（`5x` / `6x` 和 LNOBJ）。Case 2 缩短时，终点落在裁掉区间里的长音会收到 `xUpAfter - 1` vpos。
