#pragma once

#include <string_view>

#include <ibms/bms_chart.hpp>
#include <ibms/bms_long_note.hpp>

namespace ibms::detail {

[[nodiscard]] BmsLongNotes build_bms_long_notes(
    std::string_view source, const BmsChart& chart, bool has_conditionals);

}  // namespace ibms::detail
