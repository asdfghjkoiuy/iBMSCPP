#include <ibms/bms_document.hpp>
#include <ibms/bms_timing.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <iomanip>
#include <locale>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ibms {
namespace {

constexpr std::string_view kKeyChannels[] = {
    "03", "04", "06", "07", "08", "09", "11", "12", "13", "14", "15", "16", "18", "19",
    "21", "22", "23", "24", "25", "26", "28", "29", "31", "32", "33", "34", "35", "36",
    "38", "39", "41", "42", "43", "44", "45", "46", "48", "49", "51", "52", "53", "54",
    "55", "56", "58", "59", "61", "62", "63", "64", "65", "66", "68", "69", "D1", "D2",
    "D3", "D4", "D5", "D6", "D8", "D9", "E1", "E2", "E3", "E4", "E5", "E6", "E8", "E9",
    "SC",
};

struct Cell {
    double vpos = 0;
    std::string channel;
    std::string text;
    std::int64_t scaled = 0;
    int bgm_lane = -1;
    bool allocate = false;
};

std::string crlf()
{
    return "\r\n";
}

char upper_ascii(char c)
{
    return c >= 'a' && c <= 'z' ? static_cast<char>(c - 'a' + 'A') : c;
}

std::string upper_ascii(std::string_view text)
{
    std::string out(text);
    for (char& c : out)
        c = upper_ascii(c);
    return out;
}

std::string add3(int measure)
{
    std::string text = "000" + std::to_string(measure);
    return text.substr(text.size() - 3);
}

std::string c10to36(int value)
{
    if (value < 1)
        value = 1;
    if (value > 1295)
        value = 1295;
    constexpr char digits[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return {digits[value / 36], digits[value % 36]};
}

std::string hex2(int value)
{
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%X", value);
    const std::string hex = buffer;
    return ("0" + hex).substr(hex.size() - 1);
}

std::string index_label(int value, bool x1296)
{
    return x1296 ? c10to36(value) : hex2(value);
}

int parse_int(std::string_view text, int fallback)
{
    std::size_t i = 0;
    while (i < text.size() && (text[i] == ' ' || text[i] == '\t'))
        ++i;
    if (i >= text.size())
        return fallback;
    bool negative = false;
    if (text[i] == '-') {
        negative = true;
        ++i;
    }
    if (i >= text.size() || text[i] < '0' || text[i] > '9')
        return fallback;
    int value = 0;
    for (; i < text.size() && text[i] >= '0' && text[i] <= '9'; ++i)
        value = value * 10 + (text[i] - '0');
    return negative ? -value : value;
}

int parse_hex(std::string_view text)
{
    int value = 0;
    for (char c : text) {
        value *= 16;
        if (c >= '0' && c <= '9')
            value += c - '0';
        else if (c >= 'A' && c <= 'F')
            value += c - 'A' + 10;
        else if (c >= 'a' && c <= 'f')
            value += c - 'a' + 10;
    }
    return value;
}

std::string decimal_dot(double value)
{
    std::ostringstream out;
    out.imbue(std::locale::classic());
    out << std::defaultfloat << std::setprecision(15) << value;
    return out.str();
}

std::string decimal_dot(const BeatPosition& value)
{
    if (value.denominator() == 1)
        return std::to_string(value.numerator());
    return decimal_dot(
        static_cast<double>(value.numerator()) / static_cast<double>(value.denominator()));
}

double beat_to_vpos(const BeatPosition& beat)
{
    return 48.0 * static_cast<double>(beat.numerator()) / static_cast<double>(beat.denominator());
}

std::int64_t scaled_value(const BeatPosition& value)
{
    const double decimal =
        static_cast<double>(value.numerator()) / static_cast<double>(value.denominator());
    return static_cast<std::int64_t>(std::llround(decimal * 10000.0));
}

std::optional<BeatPosition> parse_decimal(std::string_view raw)
{
    std::size_t begin = 0;
    std::size_t end = raw.size();
    while (begin < end && (raw[begin] == ' ' || raw[begin] == '\t'))
        ++begin;
    while (end > begin && (raw[end - 1] == ' ' || raw[end - 1] == '\t'))
        --end;
    if (begin >= end)
        return {};
    bool negative = false;
    if (raw[begin] == '-') {
        negative = true;
        ++begin;
    } else if (raw[begin] == '+') {
        ++begin;
    }
    const auto dot = raw.find('.', begin);
    try {
        if (dot == std::string_view::npos || dot >= end) {
            BeatPosition::rep numerator = std::stoll(std::string(raw.substr(begin, end - begin)));
            if (negative)
                numerator = -numerator;
            return BeatPosition{numerator};
        }
        const std::string whole = std::string(raw.substr(begin, dot - begin));
        const std::string frac = std::string(raw.substr(dot + 1, end - (dot + 1)));
        BeatPosition::rep denominator = 1;
        for (std::size_t i = 0; i < frac.size(); ++i)
            denominator *= 10;
        BeatPosition::rep numerator = (whole.empty() ? 0 : std::stoll(whole)) * denominator
            + (frac.empty() ? 0 : std::stoll(frac));
        if (negative)
            numerator = -numerator;
        return BeatPosition{numerator, denominator};
    } catch (...) {
        return {};
    }
}

double gcd_legacy(double first, double second, double limit)
{
    double maximum = first;
    double minimum = second;
    if (first < second) {
        maximum = second;
        minimum = first;
    }
    while (minimum >= limit) {
        const double remainder = maximum - std::floor(maximum / minimum) * minimum;
        maximum = minimum;
        minimum = remainder;
    }
    return maximum;
}

int cint(double value)
{
    return static_cast<int>(std::nearbyint(value));
}

std::string to_long_channel(std::string_view channel)
{
    if (channel.size() != 2)
        return std::string(channel);
    if (channel[0] == '5' || channel[0] == '6')
        return std::string(channel);
    if (channel[0] == '1')
        return std::string{'5', channel[1]};
    if (channel[0] == '2')
        return std::string{'6', channel[1]};
    return std::string(channel);
}

int measure_at(double vpos, const std::vector<BmsMeasure>& measures)
{
    for (int index = 1; index <= 999; ++index) {
        if (vpos < beat_to_vpos(measures[static_cast<std::size_t>(index)].start))
            return index - 1;
    }
    return 999;
}

bool same_endpoint(const BmsEvent& event, const BmsLongNoteEndpoint& end, std::string_view channel)
{
    return event.measure == end.position.measure && event.channel == channel
        && event.fraction == end.position.fraction;
}

bool is_long_endpoint(const BmsEvent& event, const BmsLongNotes& notes)
{
    for (const auto& note : notes.notes) {
        if (same_endpoint(event, note.start, note.channel)
            || same_endpoint(event, note.end, note.channel))
            return true;
    }
    return false;
}

std::optional<BeatPosition> header_decimal(const BmsDocument& document, std::string_view prefix, std::string_view token)
{
    const auto value = document.header(std::string(prefix) + upper_ascii(token));
    if (!value)
        return {};
    return parse_decimal(*value);
}

int intern(std::vector<std::int64_t>& table, std::int64_t value)
{
    for (std::size_t index = 1; index < table.size(); ++index) {
        if (table[index] == value)
            return static_cast<int>(index);
    }
    table.push_back(value);
    return static_cast<int>(table.size() - 1);
}

void append_cell(std::vector<Cell>& cells, double vpos, std::string channel, std::string text)
{
    Cell cell;
    cell.vpos = vpos;
    cell.channel = std::move(channel);
    cell.text = std::move(text);
    cells.push_back(std::move(cell));
}

void collect_long_notes(const BmsDocument& document, bool nt_input, std::vector<Cell>& cells)
{
    for (const auto& note : document.long_notes().notes) {
        const double start = beat_to_vpos(note.start.beat);
        const double end = beat_to_vpos(note.end.beat);
        if (nt_input) {
            const std::string channel = to_long_channel(note.channel);
            const std::string text = upper_ascii(note.start.token);
            append_cell(cells, start, channel, text);
            append_cell(cells, end, channel, text);
            continue;
        }
        if (note.encoding == BmsLongNoteEncoding::lnobj) {
            append_cell(cells, start, note.channel, upper_ascii(note.start.token));
            append_cell(cells, end, note.channel, upper_ascii(note.end.token));
            continue;
        }
        append_cell(cells, start, note.channel, upper_ascii(note.start.token));
        append_cell(cells, end, note.channel, upper_ascii(note.end.token));
    }
}

void collect_events(const BmsDocument& document, std::vector<Cell>& cells)
{
    const auto& notes = document.long_notes();
    for (const auto& event : document.chart().events) {
        if (is_long_endpoint(event, notes))
            continue;
        Cell cell;
        cell.vpos = beat_to_vpos(event.beat);
        cell.channel = event.channel;
        if (event.kind == BmsEventKind::bgm)
            cell.bgm_lane = event.bgm_lane;
        switch (event.kind) {
        case BmsEventKind::bpm:
            cell.text = hex2(parse_hex(event.token));
            break;
        case BmsEventKind::extended_bpm:
            if (const auto value = header_decimal(document, "BPM", event.token)) {
                cell.allocate = true;
                cell.scaled = scaled_value(*value);
            } else {
                cell.text = upper_ascii(event.token);
            }
            break;
        case BmsEventKind::stop:
            if (const auto value = header_decimal(document, "STOP", event.token)) {
                cell.allocate = true;
                cell.scaled = scaled_value(*value);
            } else {
                cell.text = upper_ascii(event.token);
            }
            break;
        case BmsEventKind::scroll:
            if (const auto value = header_decimal(document, "SCROLL", event.token)) {
                cell.allocate = true;
                cell.scaled = scaled_value(*value);
            } else {
                cell.text = upper_ascii(event.token);
            }
            break;
        default:
            cell.text = upper_ascii(event.token);
            break;
        }
        cells.push_back(std::move(cell));
    }
}

void assign_resource(
    Cell& cell, std::vector<std::int64_t>& table, bool x1296, bool always_base36)
{
    if (!cell.allocate || !cell.text.empty())
        return;
    const int index = intern(table, cell.scaled);
    cell.text = always_base36 ? c10to36(index) : index_label(index, x1296);
    cell.allocate = false;
}

std::string encode_column(
    int measure, std::string_view channel, double length, const std::vector<Cell>& items,
    std::vector<Cell>& overflow, double grid_limit,
    const std::vector<BmsMeasure>& measures, bool& overlapping)
{
    if (items.empty() && channel != "01")
        return {};
    double gcd = length;
    std::vector<double> relative;
    relative.reserve(items.size());
    for (const auto& item : items) {
        double offset = item.vpos - beat_to_vpos(measures[static_cast<std::size_t>(measure_at(item.vpos, measures))].start);
        if (offset < 0)
            offset = 0;
        relative.push_back(offset);
        if (offset > 0)
            gcd = gcd_legacy(gcd, offset, grid_limit);
    }
    const int last = cint(length / gcd) - 1;
    std::vector<std::string> keys(static_cast<std::size_t>(last + 1), "00");
    for (std::size_t index = 0; index < items.size(); ++index) {
        const int slot = cint(relative[index] / gcd);
        if (slot > last) {
            Cell next = items[index];
            next.vpos = beat_to_vpos(measures[static_cast<std::size_t>(measure)].start);
            overflow.push_back(std::move(next));
            continue;
        }
        if (keys[static_cast<std::size_t>(slot)] != "00")
            overlapping = true;
        keys[static_cast<std::size_t>(slot)] = items[index].text;
    }
    std::string row = "#" + add3(measure) + std::string(channel) + ":";
    for (const auto& key : keys)
        row += key;
    row += crlf();
    return row;
}

std::string generate_header_meta(const BmsDocument& document)
{
    const std::string player = document.header("PLAYER").value_or("1");
    const std::string genre = document.header("GENRE").value_or("");
    const std::string title = document.header("TITLE").value_or("");
    const std::string artist = document.header("ARTIST").value_or("");
    BeatPosition bpm{120};
    if (document.timing().available)
        bpm = document.timing().initial_bpm;
    else if (const auto header = document.header("BPM")) {
        if (const auto parsed = parse_decimal(*header))
            bpm = *parsed;
    }
    const std::string play_level = document.header("PLAYLEVEL").value_or("");
    const int rank = document.header("RANK") ? parse_int(*document.header("RANK"), 3) : 3;
    std::string out = crlf() + "*---------------------- HEADER FIELD" + crlf() + crlf();
    out += "#PLAYER " + std::string(player.empty() ? "1" : player) + crlf();
    out += "#GENRE " + genre + crlf();
    out += "#TITLE " + title + crlf();
    out += "#ARTIST " + artist + crlf();
    out += "#BPM " + decimal_dot(bpm) + crlf();
    out += "#PLAYLEVEL " + play_level + crlf();
    out += "#RANK " + std::to_string(rank) + crlf();
    out += crlf();
    const auto append_optional = [&](std::string_view key, std::string_view directive) {
        if (const auto value = document.header(key); value && !value->empty())
            out += "#" + std::string(directive) + " " + *value + crlf();
    };
    append_optional("SUBTITLE", "SUBTITLE");
    append_optional("SUBARTIST", "SUBARTIST");
    append_optional("STAGEFILE", "STAGEFILE");
    append_optional("BANNER", "BANNER");
    append_optional("BACKBMP", "BACKBMP");
    out += crlf();
    if (const auto difficulty = document.header("DIFFICULTY")) {
        const int index = parse_int(*difficulty, 0);
        if (index != 0)
            out += "#DIFFICULTY " + std::to_string(index) + crlf();
    }
    append_optional("DEFEXRANK", "DEFEXRANK");
    append_optional("TOTAL", "TOTAL");
    if (const auto comment = document.header("COMMENT"); comment && !comment->empty())
        out += "#COMMENT \"" + *comment + "\"" + crlf();
    if (const auto lnobj = document.header("LNOBJ"); lnobj && !lnobj->empty())
        out += "#LNOBJ " + *lnobj + crlf();
    else
        out += "#LNTYPE 1" + crlf();
    out += crlf();
    return out;
}

std::string generate_header_indexed(
    const BmsDocument& document, const std::vector<std::int64_t>& bpm, const std::vector<std::int64_t>& stop,
    const std::vector<std::int64_t>& scroll)
{
    std::string out;
    for (int index = 1; index <= 1295; ++index) {
        if (const auto name = document.header(std::string("WAV") + c10to36(index)); name && !name->empty())
            out += "#WAV" + c10to36(index) + " " + *name + crlf();
    }
    for (int index = 1; index <= 1295; ++index) {
        if (const auto name = document.header(std::string("BMP") + c10to36(index)); name && !name->empty())
            out += "#BMP" + c10to36(index) + " " + *name + crlf();
    }
    const bool bpm1296 = IndexedTimingRadix::bpm_x1296();
    const bool stop1296 = IndexedTimingRadix::stop_x1296();
    for (std::size_t index = 1; index < bpm.size(); ++index)
        out += "#BPM" + index_label(static_cast<int>(index), bpm1296) + " "
            + decimal_dot(static_cast<double>(bpm[index]) / 10000.0) + crlf();
    for (std::size_t index = 1; index < stop.size(); ++index)
        out += "#STOP" + index_label(static_cast<int>(index), stop1296) + " "
            + decimal_dot(static_cast<double>(stop[index]) / 10000.0) + crlf();
    for (std::size_t index = 1; index < scroll.size(); ++index)
        out += "#SCROLL" + c10to36(static_cast<int>(index)) + " "
            + decimal_dot(static_cast<double>(scroll[index]) / 10000.0) + crlf();
    return out;
}

}  // namespace

std::string BmsDocument::save_bms(bool nt_input, double grid_limit) const
{
    return save_bms_report(nt_input, grid_limit).text;
}

BmsSaveReport BmsDocument::save_bms_report(bool nt_input, double grid_limit) const
{
    if (has_conditionals_)
        return {serialize(), false, 0, 0, 0};

    std::vector<Cell> cells;
    collect_long_notes(*this, nt_input, cells);
    collect_events(*this, cells);
    std::stable_sort(cells.begin(), cells.end(), [](const Cell& left, const Cell& right) {
        return left.vpos < right.vpos;
    });

    double greatest = 0;
    for (const auto& cell : cells)
        greatest = std::max(greatest, cell.vpos);

    const auto& measures = chart().measures;
    const int last = measure_at(greatest, measures) + 1;
    std::vector<std::string> measure_text(static_cast<std::size_t>(last + 1));
    std::vector<Cell> overflow;
    std::vector<std::int64_t> bpm_table(1, 0);
    std::vector<std::int64_t> stop_table(1, 0);
    std::vector<std::int64_t> scroll_table(1, 0);
    const bool bpm1296 = IndexedTimingRadix::bpm_x1296();
    const bool stop1296 = IndexedTimingRadix::stop_x1296();
    bool overlapping = false;

    for (int measure = 0; measure <= last; ++measure) {
        std::string block = crlf();
        const auto& info = measures[static_cast<std::size_t>(measure)];
        if (info.length != BeatPosition{4})
            block += "#" + add3(measure) + "02:" + decimal_dot(info.length / BeatPosition{4}) + crlf();

        std::vector<Cell> in_measure;
        for (const auto& cell : cells) {
            if (measure_at(cell.vpos, measures) == measure)
                in_measure.push_back(cell);
        }
        if (in_measure.empty()) {
            measure_text[static_cast<std::size_t>(measure)] = std::move(block);
            continue;
        }
        in_measure.insert(in_measure.begin(), overflow.begin(), overflow.end());
        overflow.clear();

        int greatest_lane = -1;
        for (const auto& cell : in_measure)
            greatest_lane = std::max(greatest_lane, cell.bgm_lane);
        const double length = beat_to_vpos(info.length);
        for (int lane = 0; lane <= greatest_lane; ++lane) {
            std::vector<Cell> column;
            for (auto& cell : in_measure) {
                if (cell.bgm_lane == lane)
                    column.push_back(cell);
            }
            block += encode_column(measure, "01", length, column, overflow, grid_limit, measures, overlapping);
        }
        for (const auto channel : kKeyChannels) {
            std::vector<Cell> column;
            for (auto& cell : in_measure) {
                if (cell.bgm_lane >= 0 || cell.channel != channel)
                    continue;
                if (channel == "08")
                    assign_resource(cell, bpm_table, bpm1296, false);
                else if (channel == "09")
                    assign_resource(cell, stop_table, stop1296, false);
                else if (channel == "SC")
                    assign_resource(cell, scroll_table, true, true);
                column.push_back(cell);
            }
            if (column.empty())
                continue;
            block += encode_column(measure, channel, length, column, overflow, grid_limit, measures, overlapping);
        }
        measure_text[static_cast<std::size_t>(measure)] = std::move(block);
    }

    std::string expansion;
    const std::string expansion_text = this->expansion();
    if (!expansion_text.empty())
        expansion = crlf() + "*---------------------- EXPANSION FIELD" + crlf() + expansion_text + crlf() + crlf();

    std::string main = "*---------------------- MAIN DATA FIELD" + crlf() + crlf();
    for (const auto& block : measure_text)
        main += block;
    main += crlf();

    BmsSaveReport report;
    report.text = generate_header_meta(*this) + generate_header_indexed(*this, bpm_table, stop_table, scroll_table)
        + crlf() + expansion + crlf() + main;
    report.overlapping = overlapping;
    report.bpm_count = bpm_table.size() - 1;
    report.stop_count = stop_table.size() - 1;
    report.scroll_count = scroll_table.size() - 1;
    return report;
}

}  // namespace ibms
