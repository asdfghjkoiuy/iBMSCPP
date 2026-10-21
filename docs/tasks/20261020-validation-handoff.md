# 小模型任务包：2026-10-20 混音定位修复与验证

## 调度人先读

本批只有一个已确认的产品 bug：BmsONE 混音器非零定位后，未来音符延后一个定位起点。完整证据和手动验收步骤在 `docs/validation/gui-start-20261020.md`。主工程 62 项、BmsONE 5 项旧测试均通过，说明本批要补测试覆盖，不能以旧测试全绿认定无需修复。

用户自行将下方任务发给小模型。本轮主代理未启动子代理，未编写产品修复。`docs/development-workflow.md` 要求父代理负责拆解、审查、验收，实现由子代理负责。该文档建议有界任务用 `gpt-5.6-luna`，音频/并发/集成用 `gpt-5.6-terra`；调度人可按实际可用模型选择。

各任务只允许写自己列出的文件，不得顺便重构或格式化其他文件。当前工作区本来有未提交修改，禁止 reset、clean、批量覆盖或把原有改动算作自己的成果。不要自行提交、推送或安装依赖。遇到范围外问题，报告具体位置和理由，交给调度人。

顺序：A（补失败测试）→ B（修复）→ D（窗口验收）；C（调用链审查）可以与 A 同时进行，结果交给 B。A 和 B 的产品写入范围互不重叠。若 C 要求修改调用方，先由调度人新增单独任务，不在 C 中偷偷实现。

## 任务 A：把非零定位缺陷写成正式回归测试

**建议模型：luna；目标：只补测试，允许提交时仍红，不写实现。**

任务契约：直接调用实际 `PlayMixer`，固定 44100 Hz，用 `installTestTone` 安装可精确检测起音的 PCM。先看 `out/validation/gui-20261020/seek-probe/probe.cpp` 的已确认复现，再阅读已有 replay 测试。不要依赖扬声器、等待墙钟或打开 GUI。

允许修改：仅 `BmsONE/tests/play_mixer_replay_test.cpp`。预计只变这一份文件。现有测试目标已经编译实际 `PlayMixer.cpp`，无需改 CMake。

步骤：

1. 保留所有已有从零重播断言。增加帮助函数检测立体声 PCM 第一个非零帧，避免把“返回了字节”当成“触发了正确音符”。
2. 分别建立起点 0、1、3 秒的场景；每场景只放一颗位于起点后 0.1 秒的音。定位后生成 0.2 秒 PCM，首个非零帧应为 4410（可容许最多 1 帧舍入差）。起点 1、3 秒在旧实现应失败，起点 0 应通过。
3. 增加起点之前已有音、起点恰好有音、相邻两次不同起点定位的覆盖。为每个场景写明确的期望帧位置。短 PCM 避免旧声音跨越起点混淆断言。
4. 增加“开始后暂停，再定位继续”的有界测试：从零先输出一段，setPaused(true) 后请求 PCM 应静音且不增加 generated 样本；再 seekAndArm(非零位置) 后，未来事件仍只等相对差值。确认实际 API 合同后再落断言，不编造 UI 接口。
5. 对跨起点仍在响的声音写独立断言：早于起点触发、长度超过起点的 PCM 在定位后应从正确偏移继续；新的未来事件仍按相对时间触发。
6. 检查 samplesPlayed/clockTransport.generatedSamples 的计数从新定位开始，输出 N 帧后应为 N，不能等于绝对谱面帧号。

命令（从 BmsONE 目录）：

```sh
cmake --build out/build/macos-arm64-debug --target bmsone_play_mixer_replay_tests
ctest --test-dir out/build/macos-arm64-debug -R '^bmsone_play_mixer_replay_tests$' --output-on-failure
```

提交给调度人的内容：实际改动文件、新增场景、旧代码失败的断言、命令/退出码/日志。不要为了全绿改期望为错误的实际值，也不要删除失败测试。

## 任务 B：修复混音器的绝对与相对时间混用

**建议模型：terra；等待 A 完成；目标：只修混音定位，不做播放时钟重构。**

允许修改：仅 `BmsONE/src/player/PlayMixer.cpp`、`BmsONE/src/player/PlayMixer.h`。预计这两份以内。禁止修改 `PlayClock.h`、`PlayOutput.cpp`、`GpuPlayerWindow.cpp`、`PlayChart`、测试和 CMake。

输入：A 的失败测试；独立探针；`docs/validation/gui-start-20261020.md` 的测量。输出：新定位后事件在正确相对时间混入 PCM，同时公开 generatedSamples 仍是从本次定位起累计的输出帧数。

步骤：

1. 读 `prepare`、`seekAndArm`、`fillAudio`、`mixBlock`、`stopVoices`，写下每个变量的单位及原点：微秒、样本帧、绝对谱面时间、本次播放相对时间。先把问题讲明白再改。
2. 已确认的错误：事件的 sample 是谱面绝对位置，而 seek 把 samplesPlayed 清零，fillAudio 又直接拿 samplesPlayed 对事件。不能仅将 samplesPlayed 改为 startSample，这会改变提供给显示时钟的相对计数合同。
3. 可采用明确保存定位原点的方案：绝对混音游标由“定位原点 + 本次已生成帧”得到，generatedSamples 保持相对。最终方案需给出理由，不要求照抄某个变量名。
4. 新状态与现有混音状态一起受 mutex 保护；核对 prepare、seek、stop 的初始化/重置。不要新增无锁读写或扩大临界区到解码/I/O。
5. 保持起点之前事件的跳过规则、跨起点声音恢复、起点事件触发一次、同帧多事件、手动触发、自动播放开关、停止后缓存保留。
6. 不把显示延迟或音频缓冲当成补偿量。禁止 sleep、硬编码 1 秒/3 秒、削弱测试、改变事件绝对位置来掩盖错误。

验收：A 测试通过；独立 seek_probe 三项通过且退出码 0；BmsONE 全部 CTest 通过。构建独立探针时会重新编译产品 PlayMixer，不能只运行修复前二进制。

```sh
cmake --build BmsONE/out/build/macos-arm64-debug
ctest --test-dir BmsONE/out/build/macos-arm64-debug --output-on-failure
cmake --build out/validation/gui-20261020/seek-probe/build
out/validation/gui-20261020/seek-probe/build/seek_probe
```

报告必须包含完整变更文件、为什么计数合同没有改变、锁的说明、每条验收命令及结果、尚未验证的窗口行为。若确实需要范围外修改，先停在具体问题并向调度人报告。

## 任务 C：独立审查 Here / Pause / Resume 的调用合同

**建议模型：terra；可与 A 同时；只读产品代码。**

允许新增：仅 `docs/validation/20261020-player-call-contract-review.md`。不得改产品或测试。预计只新增这份报告。

阅读：`BmsONE/src/player/GpuPlayerWindow.cpp`、`PlayClock.h`、`PlayOutput.cpp`、`PlayMixer.cpp/.h`、`GpuPlayerWidget.cpp`，以及现有 clock/replay tests。

步骤：

1. 为从头、从 Here、暂停继续、停止重播、播放中改 BUF、自然结束这六条路径列出关键调用顺序，标出传给 seekAndArm 的参数来源。
2. 明确 beginPlay、resume、restartDeviceEpoch 和 clockTransport 中时间的原点。解释 B 的修复为什么必须保持 generatedSamples 为相对输出计数。
3. 检查定时 READY 失效机制、异步解码完成、音频线程停止与 seek 的先后顺序，只报告有具体代码依据的风险。不要凭猜测列 bug。
4. 说明现有 GPU replay test 仅测辅助判定函数，未覆盖完整窗口。给 D 一份可操作的回归清单。
5. 报告按“已确认”“需要测量”“目前没有证据”区分。每个发现给文件、函数、触发条件、影响和建议验证方法。

验收：报告中的调用都能在当前源码找到；不宣称 GUI 或人耳音频通过；不修改 B 的文件。把范围外发现交给调度人决定是否另开实现任务。

## 任务 D：修复后的真实窗口回归与证据

**建议模型：有 computer use 能力的小模型；等待 B 完成并由主代理审查。**

允许新增：仅 `docs/validation/20261020-player-gui-after-fix.md` 和 `out/validation/gui-20261020/after-fix/` 下的截图、临时谱面、日志。不得改源码、测试和其他报告。

前提：Computer Use 已获准控制 IBMSNative/BmsONE。若仍返回未授权，原样记录错误和阻塞项，不改用其他 UI 自动化绕过，不把启动尝试当作测试成功。用户可按前一份报告的步骤手动完成。

步骤：

1. 构建并记录真实启动路径，不能误用旧 .app。保存输入副本和日志，不覆盖用户谱面。
2. 按 `docs/validation/gui-start-20261020.md` 的窗口流程跑：原生 BMS 编辑保存、原生/Qt BMSON 往返、播放器停止重播三轮、非零 Here、暂停继续、切 BUF、自然结束。
3. Here 和暂停继续重点用 `seek-repro.bmson` / `pulse.wav`；记录起点、相邻音符时间和暂停前后时刻。本样本每秒只有一颗 0.1 秒的音，避免长音残留掩盖延迟。
4. 对复现出的新问题，保存最小输入和逐步复现；不自行修复，交给主代理另拆任务。
5. 只有截图/AX 时不能证明真实出声或显示刷新率。音频需人工听测注明主观观察，或另外使用明确授权的系统音频采集并分析；没有这些能力时标为未验证。

验收报告：每项通过/失败/阻塞，附期望、实际、重复次数和证据。结束时停止播放、关闭测试窗口；若出现未保存提示，只丢弃本任务创建且可再生的临时修改，不处理其他用户窗口。

## 主代理最终集成检查

1. 审查 A/B 完整 diff，确认范围没有越界，未掩盖失败。
2. 重新运行 BmsONE 全部测试及独立探针；检查样本位置而不只是返回字节数。
3. 判断 C 的发现是否需要新增任务。调用方没有问题时不要扩展修复范围。
4. 检查 D 的真实窗口证据；缺授权/缺音频采集时保留未验证项，不声称全链路通过。
5. 用户接受结果前不合并或推送。只有对应证据充分时更新状态文档；不能把旧历史报告改写成当时通过。
