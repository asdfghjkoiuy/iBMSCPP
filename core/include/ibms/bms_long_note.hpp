#pragma once

#include <cstddef>
#include <string>
#include <vector>

#include <ibms/beat_position.hpp>

namespace ibms {

enum class BmsLongNoteEncoding {
    long_channel,
    lnobj,
};

struct BmsLongNotePosition {
    int measure = 0;
    BeatPosition fraction;
};

struct BmsLongNoteEndpoint {
    BmsLongNotePosition position;
    BeatPosition beat;
    std::string token;
    std::size_t source_line = 0;
};

struct BmsLongNote {
    std::string channel;
    BmsLongNoteEndpoint start;
    BmsLongNoteEndpoint end;
    BmsLongNoteEncoding encoding = BmsLongNoteEncoding::long_channel;
};

struct BmsLongNoteDiagnostic {
    std::size_t source_line = 0;
    std::string message;
};

class BmsLongNotes final {
public:
    std::vector<BmsLongNote> notes;
    std::vector<BmsLongNoteDiagnostic> diagnostics;
    std::string lnobj_token;
    bool editable = true;
    std::string editing_reason;
};

}  // namespace ibms
