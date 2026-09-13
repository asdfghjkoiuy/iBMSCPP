#include "bms_long_note_internal.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

namespace ibms {
namespace {

struct SourceLine {
    std::size_t begin;
    std::size_t end;
    std::size_t number;
};

char uppercase(char value) noexcept
{
    return value >= 'a' && value <= 'z' ? static_cast<char>(value - 'a' + 'A') : value;
}

bool horizontal_space(char value) noexcept
{
    return value == ' ' || value == '\t';
}

std::string_view trim(std::string_view value)
{
    while (!value.empty() && horizontal_space(value.front()))
        value.remove_prefix(1);
    while (!value.empty() && horizontal_space(value.back()))
        value.remove_suffix(1);
    return value;
}

bool equal_ascii(std::string_view left, std::string_view right) noexcept
{
    if (left.size() != right.size())
        return false;
    for (std::size_t index = 0; index < left.size(); ++index)
        if (uppercase(left[index]) != uppercase(right[index]))
            return false;
    return true;
}

bool base36_token(std::string_view value) noexcept
{
    const auto digit = [](char character) {
        character = uppercase(character);
        return (character >= '0' && character <= '9') || (character >= 'A' && character <= 'Z');
    };
    return value.size() == 2 && digit(value[0]) && digit(value[1]);
}

std::string uppercase_ascii(std::string_view value)
{
    std::string result(value);
    for (char& character : result)
        character = uppercase(character);
    return result;
}

std::vector<SourceLine> source_lines(std::string_view source)
{
    std::vector<SourceLine> result;
    for (std::size_t position = 0, number = 0; position < source.size(); ++number) {
        const std::size_t begin = position;
        while (position < source.size() && source[position] != '\r' && source[position] != '\n')
            ++position;
        result.push_back({begin, position, number});
        if (position + 1 < source.size() && source[position] == '\r' && source[position + 1] == '\n')
            position += 2;
        else if (position < source.size())
            ++position;
    }
    return result;
}

std::string_view line_text(std::string_view source, SourceLine line)
{
    std::string_view text = source.substr(line.begin, line.end - line.begin);
    if (line.begin == 0 && text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
        static_cast<unsigned char>(text[1]) == 0xBB && static_cast<unsigned char>(text[2]) == 0xBF)
        text.remove_prefix(3);
    return trim(text);
}

std::optional<std::string_view> header_value(std::string_view text, std::string_view key)
{
    if (text.size() < key.size() + 1 || text.front() != '#' || !equal_ascii(text.substr(1, key.size()), key))
        return std::nullopt;
    if (text.size() == key.size() + 1)
        return std::string_view{};
    if (!horizontal_space(text[key.size() + 1]))
        return std::nullopt;
    return trim(text.substr(key.size() + 1));
}

bool is_long_channel(std::string_view channel)
{
    return channel == "51" || channel == "52" || channel == "53" || channel == "54" || channel == "55" ||
           channel == "56" || channel == "58" || channel == "59" || channel == "61" || channel == "62" ||
           channel == "63" || channel == "64" || channel == "65" || channel == "66" || channel == "68" ||
           channel == "69";
}

std::optional<std::size_t> lane_index(std::string_view channel)
{
    if (channel.size() != 2)
        return std::nullopt;
    const auto key_offset = [](char key) -> std::optional<std::size_t> {
        switch (key) {
        case '1': return 0;
        case '2': return 1;
        case '3': return 2;
        case '4': return 3;
        case '5': return 4;
        case '6': return 5;
        case '8': return 6;
        case '9': return 7;
        default: return std::nullopt;
        }
    };
    const std::optional<std::size_t> offset = key_offset(channel[1]);
    if (!offset.has_value())
        return std::nullopt;
    if (channel[0] == '1' || channel[0] == '5')
        return *offset;
    if (channel[0] == '2' || channel[0] == '6')
        return *offset + 8;
    return std::nullopt;
}

void disable(BmsLongNotes& notes, std::size_t source_line, std::string message)
{
    notes.diagnostics.push_back({source_line, std::move(message)});
    if (notes.editable) {
        notes.editable = false;
        notes.editing_reason = notes.diagnostics.back().message;
    }
}

void warn(BmsLongNotes& notes, std::size_t source_line, std::string message)
{
    notes.diagnostics.push_back({source_line, std::move(message)});
}

BmsLongNoteEndpoint endpoint(const BmsEvent& event)
{
    return {{event.measure, event.fraction}, event.beat, event.token, event.source_line};
}

bool source_order(const BmsEvent* left, const BmsEvent* right)
{
    if (left->beat != right->beat)
        return left->beat < right->beat;
    return left->source_line < right->source_line;
}

}  // namespace

namespace detail {

BmsLongNotes build_bms_long_notes(std::string_view source, const BmsChart& chart, bool has_conditionals)
{
    BmsLongNotes result;
    if (has_conditionals || !chart.editable || chart.measures.empty()) {
        disable(result, 0, "long-note pairing is unavailable because the chart timeline is unavailable");
        return result;
    }

    std::optional<std::string> lnobj;
    for (const SourceLine line : source_lines(source)) {
        const std::string_view text = line_text(source, line);
        if (const auto value = header_value(text, "LNTYPE")) {
            if (*value != "1")
                disable(result, line.number, "#LNTYPE values other than 1 are not editable");
        }
        if (const auto value = header_value(text, "LNOBJ")) {
            if (!base36_token(*value) || *value == "00")
                disable(result, line.number, "invalid #LNOBJ token");
            else {
                lnobj = uppercase_ascii(*value);
                result.lnobj_token = *lnobj;
            }
        }
    }

    std::array<std::vector<const BmsEvent*>, 16> long_events;
    std::array<std::vector<const BmsEvent*>, 16> normal_events;
    for (const BmsEvent& event : chart.events) {
        const std::optional<std::size_t> index = lane_index(event.channel);
        if (!index.has_value())
            continue;
        if (event.kind == BmsEventKind::long_note && is_long_channel(event.channel))
            long_events[*index].push_back(&event);
        if (event.kind == BmsEventKind::normal_note && (event.channel[0] == '1' || event.channel[0] == '2'))
            normal_events[*index].push_back(&event);
    }

    for (auto& events : normal_events)
        std::stable_sort(events.begin(), events.end(), source_order);

    for (auto& events : long_events) {
        if (events.empty())
            continue;
        std::stable_sort(events.begin(), events.end(), source_order);
        if (events.size() % 2 != 0)
            warn(result, events.back()->source_line, "long-channel endpoint has no matching end");
        for (std::size_t index = 0; index + 1 < events.size(); index += 2) {
            const BmsEvent& start = *events[index];
            const BmsEvent& end = *events[index + 1];
            if (end.beat <= start.beat) {
                disable(result, end.source_line, "long-channel endpoints must have strictly increasing beats");
                continue;
            }
            result.notes.push_back({start.channel, endpoint(start), endpoint(end), BmsLongNoteEncoding::long_channel});
        }
    }

    for (const BmsLongNote& note : result.notes) {
        const std::optional<std::size_t> index = lane_index(note.channel);
        if (!index.has_value())
            continue;
        const auto& events = normal_events[*index];
        const auto first_at_or_after_start = std::lower_bound(
            events.begin(), events.end(), note.start.beat,
            [](const BmsEvent* event, const BeatPosition& beat) { return event->beat < beat; });
        if (first_at_or_after_start != events.end() && (*first_at_or_after_start)->beat <= note.end.beat)
            disable(result, (*first_at_or_after_start)->source_line, "normal note overlaps a long-channel endpoint or interval");
    }

    if (!lnobj.has_value())
        return result;

    if (std::any_of(long_events.begin(), long_events.end(), [](const auto& events) { return !events.empty(); })) {
        disable(result, 0, "mixed long-channel and #LNOBJ semantics are not editable");
        return result;
    }

    for (auto& events : normal_events) {
        for (std::size_t index = 0; index < events.size(); ++index) {
            const BmsEvent& end = *events[index];
            if (end.token != *lnobj)
                continue;
            if (index == 0 || events[index - 1]->token == *lnobj || events[index - 1]->beat >= end.beat) {
                disable(result, end.source_line, "#LNOBJ endpoint has no unambiguous preceding note");
                continue;
            }
            const BmsEvent& start = *events[index - 1];
            if (index >= 2 && events[index - 2]->beat == start.beat) {
                disable(result, end.source_line, "#LNOBJ endpoint follows ambiguous same-beat notes");
                continue;
            }
            result.notes.push_back({start.channel, endpoint(start), endpoint(end), BmsLongNoteEncoding::lnobj});
        }
    }
    return result;
}

}  // namespace detail
}  // namespace ibms
