# Preview 无需解锁的未闭合项核查（2026-10-21）

只读当前 `macos/Sources/IBMSNative/PreviewUnifiedAudioWorker.swift` 一次，SHA-256 `6c691a4d4f6e9c7da532214e7e09b7c056a5a693ca1db537060b7b45885e9d98`。本轮未执行播放、UI、像素基准、ASan/TSan或测试，未改产品；以下“源码确认”不等于本轮运行复现。源码后续改变须重新绑定hash。

| 项目 | 本次实际证据与判断 | 最小后续验证（均不需解锁/UI） |
| --- | --- | --- |
| inline预算guard | **仍在，源码确认。** 1089 `planar.count <= max(budgetLeft, planar.count)` 对任何budgetLeft均真；1087起仍可进入格式转换与存储，不能凭此guard保证剩余预算。 | 对storeInline直接给budgetLeft=0/负值和可解资源，记录返回值、实际分配后resident及转换峰值；再核多个asset累计。必须以实际字节验收，不能只scheduled或调低声音。 |
| page/stitch总量 | **仍非硬界，源码确认。** 518是每file字节目标 `8 * 1_179_648`；592–598全页pinned时直接return。656–657分开持有pages/stitches，997–998每voice追加stitch，不能把缓存目标说成整个在途内存界。9个不同远offset的stereo页可以同时pin而越目标；147456-frame mono页按Float32仅589824字节，该字节目标本身可容纳16页。 | 离线同file至少9个远offset和多个跨页voice，统计峰值cachedBytes、全部stitch字节、其他在途PCM并分别报告；比较pull完成后释放和缓存回落。若承诺硬界，超额需明确有界策略。 |
| 非标准Fs file | **本次未取得关闭证据，仍列待验。** 1136–1144的file入口仍以source.sampleRate调用group classify；与inline1092同样归组并不能独立证明file页已做带限转换。此前A3P已明确该项未修；本轮限定的Worker节选未完整展开归组之后的转换/页读取，故不将旧版“必然倍速”的推导冒充当前hash的完整独立证明。 | 强制同一22050/32000/88200资源分别走inline与file，离线比较频率、时长、Here offset和尾音；同时检查页实际采样率/帧数。若未实现转换，明确失败优于改标签后静音/错误速度ready。 |
| IO失败交接 | **仍在，源码确认。** pinSpan1188–1190返回failed；placeWindows987–988只置asset.failed，samples已于971清空。1077只将失败暴露为stats.ioFailed；此分支无mailbox.fail。不能把“页层不回旧pointer”当成session已收到失败。 | 离线注入已打开file的seek/read失败，沿place→produce→回调核失败是否明确交接、是否仍ready/继续无声生产。分别验证准备期及ready后的错误，不能只直接测fetch返回值。 |
| mailbox同步 | **无锁访问点仍在，但本轮不泛称所有点均已证race。** fail175–180在锁内写failure/failedGeneration；produce803直接读failedGeneration，install700直接读failure；waitUntil281–285在未持锁状态调用外部predicate。job snapshot155–159已加锁，不能把整个mailbox一概判为无保护。仅凭本Worker，尚未证明这些字段当前有不同线程并发写入；旧版Session调用关系不能自动套用当前版本。 | 对当前Session全部mailbox读写列出线程/锁，再用锁内状态快照替代跨线程普通读；离线TSan覆盖并发submit/failure/ready/cancel与predicate。只有可定位的并发读写才列race，不以@unchecked Sendable或信号量唤醒替代同步证据。 |

优先可直接执行的无设备验证为预算零额度、九页/跨页总量、非标准Fs双路径离线PCM、IO错误全链和mailbox TSan。上述均是最小建议，本轮未执行；没有据此宣称任一测试通过或真实设备声音正确。
