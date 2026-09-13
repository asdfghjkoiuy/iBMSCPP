# BMS 时序批次验证

本批验证 `BmsDocument` 的 BPM、STOP、小节倍率、时序查询和有限时序编辑。样本是无资源的合成 BMS，不代表完整格式、播放器或界面兼容性。

验证输入和手工计算的预期结果位于 [`tests/fixtures/bms-timing/manifest.json`](../../tests/fixtures/bms-timing/manifest.json)，共 14 个文件；写入后重新读取的长度和 SHA-256 全部匹配。源证据和规则见 [`docs/inventory/bms-timing-cases.md`](../inventory/bms-timing-cases.md)，包括 iBMSC 提交 `f5b21d1de50ce28202d1b2e8d2f614fabde18092`、jbms-parser 提交 `e19bcc21c8d4c85d7791ff8d31d73c1cb1ea5d27` 和 beatoraja 对照提交 `bda2b72f8607daed9e9f651f1e92fc445d42f114`。

## 覆盖内容

- 默认 BPM 120、显式 BPM、03 十六进制 BPM、08 索引 BPM、09 索引 STOP。
- `0.5`、`1.5` 小节倍率和精确有理数 beat；查询点覆盖未来 BPM 之前、BPM/STOP 同拍到达前、包含 STOP 后和下一拍。
- 同拍 BPM 先于 STOP；03/08 按同类源行最后出现者生效；重复 STOP 取最后源行，不采用旧 VB 的求和结果。
- UTF-8 BOM、BOM 后空格、大小写不敏感 `#bpm 60`、`#stopa1 48`、零 STOP、极小正 STOP、空初始 BPM、损坏 03/08/02 行、未定义引用、`#BASE 62` 和超大倍率。
- 共享 BPM/STOP 定义的单事件替换；事件计数不增加，同坐标再次替换和擦除后再替换均可工作，其他事件和定义字节保持不变。
- 1296 个时序资源的内存压力样本；资源或行槽位耗尽、`#BASE 62` 插入失败时，字节、未保存状态及撤销重做记录保持不变。
- `#BPM` 设置格式、BOM/缩进/尾随空格/CRLF 的倍率编辑、撤销精确恢复，以及超大倍率提交的原子拒绝。

测试入口是 [`tests/bms_timing_fixture_test.cpp`](../../tests/bms_timing_fixture_test.cpp)，不改 CMake 和产品代码。测试使用 `BeatPosition` 做事件位置和值的精确比较，仅对最终 `double` 秒数使用容差；没有使用浮点位置来寻找或替换事件。

## 实际验证结果

- 父任务最终 Debug 全套 `9/9`、Release 全套 `9/9` 均通过。
- 父任务最终严格 ASan/UBSan 时序验证（包含可用性状态变更）`6/6` 通过。
- 独立 `ibms_bms_timing_fixture_tests` 在重建后的 Debug 和 Release 中均通过；严格警告选项为 `-Wall -Wextra -Wconversion -Werror`。
- 核心已修复重复事件替换路径：替换一个事件保持事件数量不变，同坐标再次替换和擦除后再替换均可工作；manifest 对不可用样本不提供查询结果，诊断只要求非空。

## 已提供的 UI 证据

New 默认 BPM 为 `120`；父任务随后设置为 `120.1`。在 measure 0、小节内相对位置 `1/2` 添加 BPM `180.5`，再添加同位置 STOP `48`，查询显示到达前 `0.999167`、包含 STOP 后 `1.331577`。替换为 `240.25` 后仍保持 2 个时序事件，包含 STOP 后为 `1.248907`。Scale measure 设为 `0.5` 后保存到 `out/ui-audit/timing-ui-audit.bms`，最终样本字节已独立核对；随后在缩放后的文档上执行删除、Cmd-Z、Cmd-Shift-Z，只保留 STOP `48`，时间为到达前 `0.499584`、包含 STOP 后 `0.999167`，再次 Cmd-Z 恢复 BPM `240.25`，包含 STOP 后为 `0.749324`。

父任务随后重开该文件，确认初始值 `120.1`、倍率 `0.5`，两个事件仍为小节内相对位置 `1/2` 的 BPM `240.25` 和 STOP `48`；到达前为 `0.499584`，包含 STOP 后为 `0.749324`。初始 BPM 设为 0 会显示行内错误，事件和时间保持不变。父任务独立核对全部 14 个 fixture 的 SHA-256 与字节长度；850 宽时弹窗完整可见，720×480 截图确认 Scale 说明完整显示为两行、弹窗完整且所有控件可见；水平滚动条拖动后可访问 Source 列。说明文字和水平滚动条的 native 修复已完成，最终 Debug/Release 重建成功。

## 范围边界

本批没有验证播放、音频资源、BGA、SCROLL、BMSON、工具集成、完整格式兼容、像素一致性或性能。UI 只记录上述时序编辑、保存、重开、错误保护、窗口宽度和 Source 列访问证据。`set_measure_ratio` 只覆盖当前 **Scale measure** 路径（ApplyBeat Case 3）；Case 0 preserve、Case 1 measure、Case 2 cut 属于后续范围。
