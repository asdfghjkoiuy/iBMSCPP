#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <ibms/bmson.hpp>

namespace ibms {

class BmsDocument;

/// 对照 `Bms::Mode`。顺序与 `Bms.h` 一致，给导入问询当默认值。
enum class BmsonBmsMode {
    mode_5k = 0,
    mode_7k = 1,
    mode_10k = 2,
    mode_14k = 3,
    mode_pms_9k = 4,
    mode_pms_5k = 5
};

/// Import options. Encoding and `#RANDOM` 由导入前的解码和 `apply_bms_random` 处理。
/// `mode` 为空时对照 `BmsUtil::GetMode`：默认不信 `#PLAYER`、不忽略扩展名、不偏好扩展模式。
struct BmsonFromBmsOptions {
    int resolution = 240;
    std::optional<BmsonBmsMode> mode;
    std::string path;
    bool trust_player_command = false;
    bool ignore_extension = false;
    bool prefer_ex_modes = false;
};

/// 对照 `BmsUtil::GetMode`。`.pms` 走 PMS；否则按 1P/2P 和是否用了 6/7 键。
[[nodiscard]] BmsonBmsMode detect_bmson_bms_mode(
    const BmsDocument& bms, const BmsonFromBmsOptions& options = {});

/// 对照 `DocumentInfo` 的 `modeHint`。
[[nodiscard]] std::string_view bmson_mode_hint(BmsonBmsMode mode);

/// 对照 `BmsUtil::LongNameOfMode`。
[[nodiscard]] std::string_view bmson_mode_long_name(BmsonBmsMode mode);

/// Skin / `GetLaneMapToBmson` lane for a BMS channel such as `11` or `16`.
/// Unknown channels return 0 (BGM).
[[nodiscard]] std::int64_t bmson_lane_x(std::string_view channel, BmsonBmsMode mode);

/// 7K 包装，给旧测试用。
[[nodiscard]] std::int64_t bmson_lane_x_mode_7k(std::string_view channel);

/// 对照 `GetMode` 的 `errorChannels`：该模式不允许、但谱里用了的 offset。
[[nodiscard]] std::vector<int> bmson_mode_error_offsets(
    const BmsDocument& bms, BmsonBmsMode mode);

/// Convert a BMS document into a separate BMSON document.
/// This is not a BMS editor path: the result has pulses and Skin `x`, not `#xxx11`.
[[nodiscard]] BmsonDocument bmson_from_bms(
    const BmsDocument& bms, const BmsonFromBmsOptions& options = {});

}  // namespace ibms
