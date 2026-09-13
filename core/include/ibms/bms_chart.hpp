#pragma once

#include <cstddef>
#include <string>
#include <vector>

#include <ibms/beat_position.hpp>

namespace ibms {

enum class BmsEventKind {
    normal_note,
    hidden_note,
    long_note,
    mine,
    bgm,
    bga,
    bpm,
    extended_bpm,
    stop,
    scroll,
    unknown,
};

struct BmsDiagnostic {
    std::size_t source_line = 0;
    std::string message;
};

struct BmsMeasure {
    int measure = 0;
    BeatPosition start;
    BeatPosition length = BeatPosition{4};
};

struct BmsEvent {
    int measure = 0;
    std::string channel;
    std::string token;
    BeatPosition fraction;
    BeatPosition beat;
    BmsEventKind kind = BmsEventKind::unknown;
    std::size_t source_line = 0;
    /// 0-based BGM column. Each `#mmm01` row in a measure is the next lane.
    int bgm_lane = 0;
};

class BmsChart final {
public:
    std::vector<BmsEvent> events;
    std::vector<BmsMeasure> measures;
    std::vector<BmsDiagnostic> diagnostics;
    bool editable = true;
    std::string editing_reason;
};

}  // namespace ibms
