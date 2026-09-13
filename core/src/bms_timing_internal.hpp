#pragma once

#include <string_view>

#include <ibms/bms_timing.hpp>

namespace ibms::detail {

[[nodiscard]] BmsTiming build_bms_timing(std::string_view bytes, bool has_conditionals);

}  // namespace ibms::detail
