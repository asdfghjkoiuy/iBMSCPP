#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace ibms {

/// 对照 `BmsReader::HandleRANDOM`。按源码顺序收集每个 `#RANDOM` 的上限。
/// 控制命令在跳过的 `#IF` 里也会执行，所以这里按全文扫描，不看分支。
[[nodiscard]] std::vector<int> collect_bms_random_maxima(std::string_view bytes);

/// 对照 `HandleRANDOM` / `HandleIF` / `HandleELSEIF` / `HandleELSE`。
///
/// 控制行会从结果里去掉。这样 `BmsDocument` 才不会因为条件指令而丢掉全部物件。
/// `values[i]` 对应第 i 个 `#RANDOM`。缺的按 1。0 或越界则在 `1..max` 里取随机数。
/// `skip_between_random_and_if` 默认 false，对照偏好设置默认值。
///
/// `#ELSEIF` / `#ELSE` 按 BMS 意图：匹配的分支留下。
/// 源码写成 `skipping = !contains && top == cond`，按字面会在匹配时仍跳过。
[[nodiscard]] std::string apply_bms_random(
    std::string_view bytes,
    const std::vector<int>& values,
    bool skip_between_random_and_if = false);

}  // namespace ibms
