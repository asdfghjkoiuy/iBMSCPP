#include "bms_timing_internal.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace ibms
{
namespace
{

struct Line {
    std::size_t begin;
    std::size_t end;
    std::size_t number;
};
struct Definition {
    BeatPosition value;
    std::size_t source_line;
};

char uppercase(char value) noexcept
{
    return value >= 'a' && value <= 'z' ? static_cast<char>(value - 'a' + 'A') : value;
}
bool space(char value) noexcept
{
    return value == ' ' || value == '\t';
}
bool base36_token(std::string_view value) noexcept
{
    const auto digit = [](char byte) {
        byte = uppercase(byte);
        return (byte >= '0' && byte <= '9') || (byte >= 'A' && byte <= 'Z');
    };
    return value.size() == 2 && digit(value[0]) && digit(value[1]);
}
std::size_t base36_value(std::string_view value) noexcept
{
    const auto digit = [](char byte) -> std::size_t {
        byte = uppercase(byte);
        return byte <= '9' ? static_cast<std::size_t>(byte - '0') : static_cast<std::size_t>(byte - 'A' + 10);
    };
    return digit(value[0]) * 36 + digit(value[1]);
}
bool hex_token(std::string_view value) noexcept
{
    const auto digit = [](char byte) {
        byte = uppercase(byte);
        return (byte >= '0' && byte <= '9') || (byte >= 'A' && byte <= 'F');
    };
    return value.size() == 2 && digit(value[0]) && digit(value[1]);
}
int hex_value(std::string_view value) noexcept
{
    const auto digit = [](char byte) {
        byte = uppercase(byte);
        return byte <= '9' ? byte - '0' : byte - 'A' + 10;
    };
    return digit(value[0]) * 16 + digit(value[1]);
}
bool indexed_token(std::string_view value, bool x1296) noexcept
{
    return x1296 ? base36_token(value) : hex_token(value);
}
std::size_t indexed_value(std::string_view value, bool x1296) noexcept
{
    return x1296 ? base36_value(value) : static_cast<std::size_t>(hex_value(value));
}
std::string upper(std::string_view value)
{
    std::string result(value);
    for (char& byte : result)
        byte = uppercase(byte);
    return result;
}
std::vector<Line> lines(std::string_view bytes)
{
    std::vector<Line> result;
    for (std::size_t position = 0, number = 0; position < bytes.size(); ++number) {
        const std::size_t begin = position;
        while (position < bytes.size() && bytes[position] != '\r' && bytes[position] != '\n')
            ++position;
        result.push_back({begin, position, number});
        if (position < bytes.size() && bytes[position] == '\r' && position + 1 < bytes.size() &&
            bytes[position + 1] == '\n')
            position += 2;
        else if (position < bytes.size())
            ++position;
    }
    return result;
}
std::string_view trim(std::string_view value)
{
    while (!value.empty() && space(value.front()))
        value.remove_prefix(1);
    while (!value.empty() && space(value.back()))
        value.remove_suffix(1);
    return value;
}
bool starts_with_ascii(std::string_view value, std::string_view prefix)
{
    if (value.size() < prefix.size())
        return false;
    for (std::size_t index = 0; index < prefix.size(); ++index)
        if (uppercase(value[index]) != uppercase(prefix[index]))
            return false;
    return true;
}
std::optional<BeatPosition> decimal(std::string_view value, bool allow_zero = false)
{
    value = trim(value);
    if (value.empty())
        return std::nullopt;
    std::int64_t numerator = 0, denominator = 1;
    bool fractional = false, digit_seen = false;
    for (char byte : value) {
        if (byte == '.' && !fractional) {
            fractional = true;
            continue;
        }
        if (byte < '0' || byte > '9')
            return std::nullopt;
        digit_seen = true;
        if (numerator > (std::numeric_limits<std::int64_t>::max() - (byte - '0')) / 10)
            return std::nullopt;
        numerator = numerator * 10 + (byte - '0');
        if (fractional) {
            if (denominator > std::numeric_limits<std::int64_t>::max() / 10)
                return std::nullopt;
            denominator *= 10;
        }
    }
    if (!digit_seen || (!allow_zero && numerator == 0))
        return std::nullopt;
    return BeatPosition{numerator, denominator};
}
double as_double(const BeatPosition& value)
{
    return static_cast<double>(value.numerator()) / static_cast<double>(value.denominator());
}
double seconds_for_beats(const BeatPosition& beats, const BeatPosition& bpm)
{
    return as_double(beats) * 60.0 / as_double(bpm);
}

double seconds_for_stop(const BeatPosition& stop_value, const BeatPosition& bpm)
{
    return as_double(stop_value) / 48.0 * 60.0 / as_double(bpm);
}
void unavailable(BmsTiming& timing, std::size_t line, std::string message)
{
    timing.diagnostics.push_back({line, std::move(message)});
    timing.events.clear();
    timing.points.clear();
    if (timing.available) {
        timing.available = false;
        timing.unavailable_reason = timing.diagnostics.back().message;
    }
}

} // namespace

bool IndexedTimingRadix::bpm_x1296_ = false;
bool IndexedTimingRadix::stop_x1296_ = false;

void IndexedTimingRadix::set(bool bpm_x1296, bool stop_x1296) noexcept
{
    bpm_x1296_ = bpm_x1296;
    stop_x1296_ = stop_x1296;
}

bool IndexedTimingRadix::bpm_x1296() noexcept
{
    return bpm_x1296_;
}

bool IndexedTimingRadix::stop_x1296() noexcept
{
    return stop_x1296_;
}

IndexedTimingRadixScope::IndexedTimingRadixScope(bool bpm_x1296, bool stop_x1296)
    : previous_bpm_(IndexedTimingRadix::bpm_x1296())
    , previous_stop_(IndexedTimingRadix::stop_x1296())
{
    IndexedTimingRadix::set(bpm_x1296, stop_x1296);
}

IndexedTimingRadixScope::~IndexedTimingRadixScope()
{
    IndexedTimingRadix::set(previous_bpm_, previous_stop_);
}

namespace detail
{
BmsTiming build_bms_timing(std::string_view bytes, bool has_conditionals)
{
    BmsTiming timing;
    if (has_conditionals) {
        unavailable(timing, 0, "timing is unavailable because conditional directives are not evaluated");
        return timing;
    }
    const bool bpm_x1296 = IndexedTimingRadix::bpm_x1296();
    const bool stop_x1296 = IndexedTimingRadix::stop_x1296();
    std::array<std::optional<BeatPosition>, 1000> lengths;
    std::array<std::optional<Definition>, 1296> bpm_definitions, stop_definitions;
    std::vector<BmsTimingEvent> raw_events;
    BeatPosition initial_bpm{120};
    for (const Line line : lines(bytes)) {
        std::string_view text = trim(bytes.substr(line.begin, line.end - line.begin));
        if (line.begin == 0 && text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
            static_cast<unsigned char>(text[1]) == 0xBB && static_cast<unsigned char>(text[2]) == 0xBF)
            text.remove_prefix(3);
        text = trim(text);
        // Indexed #BPM / #STOP and 08 / 09 follow IndexedTimingRadix.
        // serialize() rewrites those labels to the current radix.
        if (text.size() >= 4 && starts_with_ascii(text, "#BPM")) {
            const std::string_view suffix = text.substr(4);
            if (suffix.size() >= 3 && indexed_token(suffix.substr(0, 2), bpm_x1296) && space(suffix[2])) {
                if (const auto value = decimal(suffix.substr(3)); value.has_value())
                    bpm_definitions[indexed_value(suffix.substr(0, 2), bpm_x1296)] = Definition{*value, line.number};
                else
                    unavailable(timing, line.number, "invalid indexed BPM definition");
            } else if (!suffix.empty() && space(suffix.front())) {
                if (const auto value = decimal(suffix); value.has_value())
                    initial_bpm = *value;
                else
                    unavailable(timing, line.number, "invalid initial BPM");
            } else if (suffix.empty()) {
                unavailable(timing, line.number, "invalid initial BPM: no value");
            } else {
                unavailable(timing, line.number, "malformed BPM definition");
            }
        }
        if (text.size() >= 5 && starts_with_ascii(text, "#STOP")) {
            const std::string_view suffix = text.substr(5);
            if (suffix.size() >= 3 && indexed_token(suffix.substr(0, 2), stop_x1296) && space(suffix[2])) {
                if (const auto value = decimal(suffix.substr(3), true); value.has_value())
                    stop_definitions[indexed_value(suffix.substr(0, 2), stop_x1296)] = Definition{*value, line.number};
                else
                    unavailable(timing, line.number, "invalid indexed STOP definition");
            } else {
                unavailable(timing, line.number, "malformed STOP definition");
            }
        }
        if (text.size() >= 6 && starts_with_ascii(text, "#BASE") && space(text[5])) {
            if (trim(text.substr(5)) != "36")
                unavailable(timing, line.number, "timing supports only #BASE 36");
        }
        const bool channel_prefix =
            text.size() >= 6 && text[0] == '#' && std::isdigit(static_cast<unsigned char>(text[1])) &&
            std::isdigit(static_cast<unsigned char>(text[2])) && std::isdigit(static_cast<unsigned char>(text[3]));
        if (channel_prefix && text.substr(4, 2) == "02" && (text.size() < 7 || text[6] != ':')) {
            unavailable(timing, line.number, "malformed measure ratio row");
            continue;
        }
        if (channel_prefix && text.substr(4, 2) == "02" && text[6] == ':') {
            const int measure = (text[1] - '0') * 100 + (text[2] - '0') * 10 + (text[3] - '0');
            if (const auto value = decimal(text.substr(7)); value.has_value()) {
                try {
                    lengths[static_cast<std::size_t>(measure)] = *value * BeatPosition{4};
                } catch (const std::overflow_error&) {
                    unavailable(timing, line.number, "measure ratio exceeds the representable beat range");
                }
            } else
                unavailable(timing, line.number, "invalid measure ratio");
        }
    }
    timing.initial_bpm = initial_bpm;
    if (!timing.available)
        return timing;
    std::array<BeatPosition, 1000> starts;
    try {
        for (std::size_t measure = 1; measure < starts.size(); ++measure)
            starts[measure] = starts[measure - 1] + lengths[measure - 1].value_or(BeatPosition{4});
    } catch (const std::overflow_error&) {
        unavailable(timing, 0, "measure timeline exceeds the representable beat range");
        return timing;
    }
    for (const Line line : lines(bytes)) {
        std::string_view text = trim(bytes.substr(line.begin, line.end - line.begin));
        if (line.begin == 0 && text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
            static_cast<unsigned char>(text[1]) == 0xBB && static_cast<unsigned char>(text[2]) == 0xBF)
            text.remove_prefix(3);
        text = trim(text);
        if (text.size() < 6 || text[0] != '#' || !std::isdigit(static_cast<unsigned char>(text[1])) ||
            !std::isdigit(static_cast<unsigned char>(text[2])) || !std::isdigit(static_cast<unsigned char>(text[3])))
            continue;
        const std::string channel = upper(text.substr(4, 2));
        if (channel != "03" && channel != "08" && channel != "09")
            continue;
        if (text.size() < 8 || text[6] != ':') {
            unavailable(timing, line.number, "malformed timing channel row");
            continue;
        }
        const std::string_view payload = text.substr(7);
        if (payload.empty() || payload.size() % 2 != 0) {
            unavailable(timing, line.number, "malformed timing channel row");
            continue;
        }
        const int measure = (text[1] - '0') * 100 + (text[2] - '0') * 10 + (text[3] - '0');
        const std::size_t slots = payload.size() / 2;
        for (std::size_t slot = 0; slot < slots; ++slot) {
            const std::string_view token = payload.substr(slot * 2, 2);
            if (token == "00")
                continue;
            BmsTimingEvent event;
            event.measure = measure;
            event.fraction = BeatPosition{static_cast<BeatPosition::rep>(slot), static_cast<BeatPosition::rep>(slots)};
            try {
                event.beat = starts[static_cast<std::size_t>(measure)] +
                             lengths[static_cast<std::size_t>(measure)].value_or(BeatPosition{4}) * event.fraction;
            } catch (const std::overflow_error&) {
                unavailable(timing, line.number, "timing event beat exceeds the representable range");
                continue;
            }
            event.channel = channel;
            event.token = upper(token);
            event.source_line = line.number;
            if (channel == "03") {
                if (!hex_token(token) || hex_value(token) == 0) {
                    unavailable(timing, line.number, "invalid channel 03 BPM token");
                    continue;
                }
                event.kind = BmsTimingEventKind::bpm;
                event.value = BeatPosition{hex_value(token)};
            } else if (channel == "08") {
                if (!indexed_token(token, bpm_x1296) || !bpm_definitions[indexed_value(token, bpm_x1296)].has_value()) {
                    unavailable(timing, line.number, "undefined indexed BPM reference");
                    continue;
                }
                event.kind = BmsTimingEventKind::bpm;
                event.value = bpm_definitions[indexed_value(token, bpm_x1296)]->value;
            } else {
                if (!indexed_token(token, stop_x1296) || !stop_definitions[indexed_value(token, stop_x1296)].has_value()) {
                    unavailable(timing, line.number, "undefined STOP reference");
                    continue;
                }
                event.kind = BmsTimingEventKind::stop;
                event.value = stop_definitions[indexed_value(token, stop_x1296)]->value;
            }
            raw_events.push_back(std::move(event));
        }
    }
    if (!timing.available)
        return timing;
    std::stable_sort(raw_events.begin(), raw_events.end(),
                     [](const BmsTimingEvent& left, const BmsTimingEvent& right) { return left.beat < right.beat; });
    timing.events = raw_events;
    BeatPosition current_beat{};
    BeatPosition current_bpm = initial_bpm;
    double seconds = 0.0;
    for (std::size_t index = 0; index < timing.events.size();) {
        const BeatPosition event_beat = timing.events[index].beat;
        try {
            seconds += seconds_for_beats(event_beat - current_beat, current_bpm);
        } catch (const std::overflow_error&) {
            unavailable(timing, timing.events[index].source_line, "timing beat delta exceeds the representable range");
            return timing;
        }
        std::optional<BeatPosition> last_bpm;
        std::optional<BeatPosition> last_stop;
        std::size_t bpm_count = 0;
        std::size_t stop_count = 0;
        while (index < timing.events.size() && timing.events[index].beat == event_beat) {
            if (timing.events[index].kind == BmsTimingEventKind::bpm) {
                last_bpm = timing.events[index].value;
                ++bpm_count;
            } else {
                last_stop = timing.events[index].value;
                ++stop_count;
            }
            ++index;
        }
        if (bpm_count > 1)
            timing.diagnostics.push_back(
                {timing.events[index - 1].source_line, "multiple BPM events at one beat: last source event wins"});
        if (stop_count > 1)
            timing.diagnostics.push_back(
                {timing.events[index - 1].source_line, "multiple STOP events at one beat: last source event wins"});
        if (last_bpm.has_value())
            current_bpm = *last_bpm;
        const double before_stop = seconds;
        if (last_stop.has_value())
            seconds += seconds_for_stop(*last_stop, current_bpm);
        if (!std::isfinite(seconds)) {
            unavailable(timing, timing.events[index - 1].source_line, "timing seconds are not finite");
            return timing;
        }
        timing.points.push_back({event_beat, current_bpm, before_stop, seconds});
        current_beat = event_beat;
    }
    return timing;
}
} // namespace detail

std::optional<double> BmsTiming::seconds_at(BeatPosition beat, bool after_stop) const
{
    if (!available || beat < BeatPosition{})
        return std::nullopt;
    const auto upper =
        std::upper_bound(points.begin(), points.end(), beat,
                         [](const BeatPosition& value, const BmsTimingPoint& point) { return value < point.beat; });
    if (upper != points.begin()) {
        const BmsTimingPoint& point = *std::prev(upper);
        if (beat == point.beat)
            return after_stop ? point.seconds_after_stop : point.seconds_before_stop;
        try {
            return point.seconds_after_stop + seconds_for_beats(beat - point.beat, point.bpm_after);
        } catch (const std::overflow_error&) {
            return std::nullopt;
        }
    }
    try {
        return seconds_for_beats(beat, initial_bpm);
    } catch (const std::overflow_error&) {
        return std::nullopt;
    }
}

std::optional<double> BmsTiming::time_before_stop(BeatPosition beat) const
{
    return seconds_at(beat, false);
}

std::optional<double> BmsTiming::time_after_stop(BeatPosition beat) const
{
    return seconds_at(beat, true);
}

} // namespace ibms
