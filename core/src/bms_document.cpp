#include <ibms/bms_document.hpp>

#include "bms_long_note_internal.hpp"
#include "bms_timing_internal.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace ibms
{
namespace
{
struct Line {
    std::size_t begin, end, number;
};

struct HeaderMatch {
    std::size_t key_end, separator_end, value_begin, value_end;
};

struct Row {
    int measure;
    std::string channel;
    std::size_t payload, slots, line;
};

struct Hit {
    std::size_t offset;
    std::string token;
};

constexpr std::size_t max_slots = 65536;

bool hspace(char c) noexcept
{
    return c == ' ' || c == '\t';
}

char upper(char c) noexcept
{
    return c >= 'a' && c <= 'z' ? char(c - 'a' + 'A') : c;
}

char lower(char c) noexcept
{
    return c >= 'A' && c <= 'Z' ? char(c - 'A' + 'a') : c;
}

bool equal(std::string_view a, std::string_view b) noexcept
{
    if (a.size() != b.size())
        return false;
    for (std::size_t i = 0; i < a.size(); ++i)
        if (lower(a[i]) != lower(b[i]))
            return false;
    return true;
}

bool bom(std::string_view b) noexcept
{
    return b.size() >= 3 && static_cast<unsigned char>(b[0]) == 0xef && static_cast<unsigned char>(b[1]) == 0xbb &&
           static_cast<unsigned char>(b[2]) == 0xbf;
}

std::vector<Line> lines(std::string_view b)
{
    std::vector<Line> out;
    for (std::size_t p = 0, n = 0; p < b.size(); ++n) {
        auto begin = p;
        while (p < b.size() && b[p] != '\r' && b[p] != '\n')
            ++p;
        out.push_back({begin, p, n});
        if (p < b.size() && b[p] == '\r' && p + 1 < b.size() && b[p + 1] == '\n')
            p += 2;
        else if (p < b.size())
            ++p;
    }
    return out;
}

std::pair<std::size_t, std::size_t> bounds(std::string_view b, Line l)
{
    auto x = l.begin, y = l.end;
    if (x == 0 && bom(b))
        x = 3;
    while (x < y && hspace(b[x]))
        ++x;
    while (y > x && hspace(b[y - 1]))
        --y;
    return {x, y};
}

std::string_view trim(std::string_view x)
{
    while (!x.empty() && hspace(x.front()))
        x.remove_prefix(1);
    while (!x.empty() && hspace(x.back()))
        x.remove_suffix(1);
    return x;
}

std::optional<HeaderMatch> header_match(std::string_view b, Line l, std::string_view key)
{
    auto [p, ignored] = bounds(b, l);
    auto e = l.end;
    if (p == e || b[p] != '#')
        return {};
    auto ke = p + 1 + key.size();
    if (ke > e || !equal(b.substr(p + 1, key.size()), key) || (ke < e && !hspace(b[ke])))
        return {};
    auto se = ke;
    while (se < e && hspace(b[se]))
        ++se;
    auto ve = e;
    while (ve > se && hspace(b[ve - 1]))
        --ve;
    return HeaderMatch{ke, se, se, ve};
}

bool conditional(std::string_view b)
{
    constexpr std::array<std::string_view, 13> n = {"RANDOM", "SETRANDOM", "IF",     "ELSEIF",    "ELSE",
                                                    "ENDIF",  "ENDRANDOM", "SWITCH", "SETSWITCH", "CASE",
                                                    "SKIP",   "DEF",       "ENDSW"};
    for (auto l : lines(b))
        for (auto x : n)
            if (header_match(b, l, x))
                return true;
    return false;
}

std::string eol(std::string_view b)
{
    for (std::size_t i = 0; i < b.size(); ++i)
        if (b[i] == '\r')
            return i + 1 < b.size() && b[i + 1] == '\n' ? "\r\n" : "\r";
        else if (b[i] == '\n')
            return "\n";
    return "\r\n";
}

bool end_eol(std::string_view b)
{
    return !b.empty() && (b.back() == '\r' || b.back() == '\n');
}

int d36(char c)
{
    c = upper(c);
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'A' && c <= 'Z')
        return c - 'A' + 10;
    return -1;
}

bool is_base36_token(std::string_view x)
{
    return x.size() == 2 && d36(x[0]) >= 0 && d36(x[1]) >= 0;
}

bool hex(std::string_view x)
{
    if (x.size() != 2)
        return false;
    auto f = [](char c) {
        c = upper(c);
        return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F');
    };
    return f(x[0]) && f(x[1]);
}

std::size_t base36_value(std::string_view x)
{
    return static_cast<std::size_t>(d36(x[0]) * 36 + d36(x[1]));
}

int d16(char c)
{
    c = upper(c);
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

std::size_t hex_index(std::string_view x)
{
    return static_cast<std::size_t>(d16(x[0]) * 16 + d16(x[1]));
}

bool is_indexed_token(std::string_view x, bool x1296)
{
    return x1296 ? is_base36_token(x) : hex(x);
}

std::size_t indexed_value(std::string_view x, bool x1296)
{
    return x1296 ? base36_value(x) : hex_index(x);
}

std::string uppercase_ascii(std::string_view x)
{
    std::string r(x);
    for (auto& c : r)
        c = upper(c);
    return r;
}

bool is_list_slot(std::string_view key, std::string_view kind)
{
    return key.size() == kind.size() + 2 && equal(key.substr(0, kind.size()), kind)
        && is_base36_token(uppercase_ascii(key.substr(kind.size(), 2)))
        && uppercase_ascii(key.substr(kind.size(), 2)) != "00";
}

bool in(std::string_view c, std::initializer_list<std::string_view> xs)
{
    return std::find(xs.begin(), xs.end(), c) != xs.end();
}

bool is_normal_channel(std::string_view c)
{
    return in(c, {"11", "12", "13", "14", "15", "16", "18", "19", "21", "22", "23", "24", "25", "26", "28", "29"});
}

bool is_hidden_channel(std::string_view c)
{
    return in(c, {"31", "32", "33", "34", "35", "36", "38", "39", "41", "42", "43", "44", "45", "46", "48", "49"});
}

bool is_mine_channel(std::string_view c)
{
    return in(c, {"D1", "D2", "D3", "D4", "D5", "D6", "D8", "D9", "E1", "E2", "E3", "E4", "E5", "E6", "E8", "E9"});
}

bool is_bga_channel(std::string_view c)
{
    return c == "04" || c == "06" || c == "07";
}

bool is_long_note_channel(std::string_view channel)
{
    return in(channel, {"51", "52", "53", "54", "55", "56", "58", "59",
                        "61", "62", "63", "64", "65", "66", "68", "69"});
}

bool is_object_edit_channel(std::string_view c)
{
    return is_normal_channel(c) || is_hidden_channel(c) || is_mine_channel(c) || is_bga_channel(c)
        || is_long_note_channel(c) || c == "01";
}

struct EditTarget {
    std::string channel;
    int bgm_lane = 0;
};

EditTarget parse_edit_target(std::string_view raw)
{
    const std::string upper = uppercase_ascii(raw);
    if (upper == "01")
        return {"01", 0};
    if (upper.size() >= 2 && upper.front() == 'B') {
        int lane_index = 0;
        for (std::size_t i = 1; i < upper.size(); ++i) {
            if (upper[i] < '0' || upper[i] > '9')
                throw std::invalid_argument("BGM column must be B1 through B999");
            if (lane_index > (999 - (upper[i] - '0')) / 10)
                throw std::invalid_argument("BGM column must be B1 through B999");
            lane_index = lane_index * 10 + (upper[i] - '0');
        }
        if (lane_index < 1)
            throw std::invalid_argument("BGM column must be B1 through B999");
        return {"01", lane_index - 1};
    }
    return {upper, 0};
}

BmsEventKind classify_event_kind(std::string_view c)
{
    if (is_normal_channel(c))
        return BmsEventKind::normal_note;
    if (is_hidden_channel(c))
        return BmsEventKind::hidden_note;
    if (is_long_note_channel(c))
        return BmsEventKind::long_note;
    if (is_mine_channel(c))
        return BmsEventKind::mine;
    if (c == "01")
        return BmsEventKind::bgm;
    if (c == "04" || c == "06" || c == "07")
        return BmsEventKind::bga;
    if (c == "03")
        return BmsEventKind::bpm;
    if (c == "08")
        return BmsEventKind::extended_bpm;
    if (c == "09")
        return BmsEventKind::stop;
    if (c == "SC")
        return BmsEventKind::scroll;
    return BmsEventKind::unknown;
}

std::optional<Row> parse_channel_row(std::string_view b, Line l, std::string* problem = nullptr)
{
    auto [p, e] = bounds(b, l);
    if (p == e || b[p] != '#' || e - p < 6 || !std::isdigit(static_cast<unsigned char>(b[p + 1])) ||
        !std::isdigit(static_cast<unsigned char>(b[p + 2])) || !std::isdigit(static_cast<unsigned char>(b[p + 3])))
        return {};
    auto c = uppercase_ascii(b.substr(p + 4, 2));
    if (e - p < 7 || b[p + 6] != ':') {
        if (problem && classify_event_kind(c) != BmsEventKind::unknown)
            *problem = "malformed supported channel row: missing ':' payload delimiter";
        return {};
    }
    auto payload = e - (p + 7);
    if (!payload || payload % 2) {
        if (problem && classify_event_kind(c) != BmsEventKind::unknown)
            *problem = "malformed supported channel row: payload must contain complete two-byte tokens";
        return {};
    }
    return Row{int((b[p + 1] - '0') * 100 + (b[p + 2] - '0') * 10 + b[p + 3] - '0'), c, p + 7, payload / 2, l.number};
}

std::optional<BeatPosition> ratio(std::string_view x, bool allow_zero = false, bool allow_negative = false)
{
    x = trim(x);
    if (x.empty())
        return {};
    bool negative = false;
    if (x.front() == '-') {
        if (!allow_negative)
            return {};
        negative = true;
        x.remove_prefix(1);
        x = trim(x);
        if (x.empty())
            return {};
    }
    std::int64_t n = 0, d = 1;
    bool dot = false, seen = false;
    for (char c : x) {
        if (c == '.' && !dot) {
            dot = true;
            continue;
        }
        if (c < '0' || c > '9')
            return {};
        seen = true;
        if (n > (std::numeric_limits<std::int64_t>::max() - (c - '0')) / 10)
            return {};
        n = n * 10 + c - '0';
        if (dot) {
            if (d > std::numeric_limits<std::int64_t>::max() / 10)
                return {};
            d *= 10;
        }
    }
    if (!seen || (!allow_zero && n == 0))
        return {};
    if (negative && n != 0)
        return BeatPosition(-n, d);
    return BeatPosition(n, d);
}

void readonly(BmsChart& c, std::string r)
{
    if (c.editable) {
        c.editable = false;
        c.editing_reason = std::move(r);
    }
}

BmsChart invalid_timeline(BmsChart chart, std::size_t source_line, std::string diagnostic, std::string reason)
{
    chart.measures.clear();
    chart.events.clear();
    chart.diagnostics.push_back({source_line, std::move(diagnostic)});
    readonly(chart, std::move(reason));
    return chart;
}

BmsChart make_chart(std::string_view b, bool conditions)
{
    BmsChart c;
    if (conditions) {
        c.editable = false;
        c.editing_reason = "chart editing is unavailable because conditional directives are not evaluated";
        c.diagnostics.push_back({0, c.editing_reason});
        return c;
    }

    std::array<std::optional<BeatPosition>, 1000> lens;
    std::array<bool, 1296> bpm{}, stop{}, scroll{};
    std::array<int, 1000> bgm_next{};
    std::vector<BmsEvent> raw;

    for (auto l : lines(b)) {
        auto [p, e] = bounds(b, l);
        auto text = b.substr(p, e - p);
        const bool bpm_x1296 = IndexedTimingRadix::bpm_x1296();
        const bool stop_x1296 = IndexedTimingRadix::stop_x1296();
        auto refs = [&](std::string_view key, auto& a, bool x1296) {
            if (text.size() >= key.size() + 3 && equal(text.substr(0, key.size()), key) &&
                is_indexed_token(text.substr(key.size(), 2), x1296) && hspace(text[key.size() + 2]))
                a[indexed_value(text.substr(key.size(), 2), x1296)] = true;
        };
        refs("#BPM", bpm, bpm_x1296);
        refs("#STOP", stop, stop_x1296);
        refs("#SCROLL", scroll, true);

        if (auto h = header_match(b, l, "BASE")) {
            if (trim(b.substr(h->value_begin, h->value_end - h->value_begin)) != "36")
                readonly(c, "chart editing supports only #BASE 36 token semantics");
        }

        if (auto h = header_match(b, l, "LNOBJ")) {
            auto v = trim(b.substr(h->value_begin, h->value_end - h->value_begin));
            if (!is_base36_token(v) || base36_value(v) == 0) {
                c.diagnostics.push_back({l.number, "invalid #LNOBJ token"});
                readonly(c, "chart editing is unavailable because #LNOBJ is malformed");
            }
        }

        if (auto h = header_match(b, l, "LNTYPE")) {
            static_cast<void>(h);
        }

        const bool measure_length_prefix =
            text.size() >= 6 && text[0] == '#' && std::isdigit(static_cast<unsigned char>(text[1])) &&
            std::isdigit(static_cast<unsigned char>(text[2])) && std::isdigit(static_cast<unsigned char>(text[3])) &&
            text.substr(4, 2) == "02";
        if (measure_length_prefix && (text.size() < 7 || text[6] != ':')) {
            c.diagnostics.push_back({l.number, "malformed measure-length row: missing ':' payload delimiter"});
            readonly(c, "chart editing is unavailable because a measure-length row is malformed");
            continue;
        }
        if (measure_length_prefix) {
            int m = (text[1] - '0') * 100 + (text[2] - '0') * 10 + text[3] - '0';
            auto q = ratio(text.substr(7));
            if (!q) {
                c.diagnostics.push_back({l.number, "invalid measure ratio in #mmm02 row"});
                readonly(c, "chart editing is unavailable because a measure ratio is invalid");
            } else {
                try {
                    lens[static_cast<std::size_t>(m)] = *q * BeatPosition{4};
                } catch (const std::overflow_error&) {
                    return invalid_timeline(std::move(c), l.number,
                                            "measure ratio exceeds the representable beat range",
                                            "chart editing is unavailable because a measure ratio overflows");
                }
            }
            continue;
        }

        std::string problem;
        auto r = parse_channel_row(b, l, &problem);
        if (!problem.empty()) {
            c.diagnostics.push_back({l.number, problem});
            readonly(c, "chart editing is unavailable because a supported channel row is malformed");
        }
        if (!r)
            continue;
        auto k = classify_event_kind(r->channel);
        const int bgm_lane = r->channel == "01" ? bgm_next[static_cast<std::size_t>(r->measure)]++ : 0;
        for (std::size_t i = 0; i < r->slots; ++i) {
            auto t = b.substr(r->payload + i * 2, 2);
            if (t == "00")
                continue;
            bool supported = k != BmsEventKind::unknown;
            bool valid = k == BmsEventKind::bpm ? hex(t)
                : k == BmsEventKind::extended_bpm ? is_indexed_token(t, bpm_x1296)
                : k == BmsEventKind::stop ? is_indexed_token(t, stop_x1296)
                : is_base36_token(t);
            if (supported && !valid) {
                c.diagnostics.push_back({r->line, "invalid token in channel " + r->channel});
                readonly(c, "chart editing is unavailable because a supported channel token is invalid");
                continue;
            }
            BmsEvent event;
            event.measure = r->measure;
            event.channel = r->channel;
            event.token = uppercase_ascii(t);
            event.fraction = BeatPosition(static_cast<BeatPosition::rep>(i), static_cast<BeatPosition::rep>(r->slots));
            event.kind = k;
            event.source_line = r->line;
            event.bgm_lane = bgm_lane;
            raw.push_back(std::move(event));
        }
    }

    try {
        for (int m = 0; m < 1000; ++m) {
            BmsMeasure z;
            z.measure = m;
            z.start = m ? c.measures.back().start + c.measures.back().length : BeatPosition{};
            z.length = lens[static_cast<std::size_t>(m)].value_or(BeatPosition{4});
            c.measures.push_back(z);
        }
    } catch (const std::overflow_error&) {
        return invalid_timeline(std::move(c), 0, "measure timeline exceeds the representable beat range",
                                "chart editing is unavailable because the measure timeline overflows");
    }
    for (auto& x : raw) {
        try {
            const std::size_t measure_index = static_cast<std::size_t>(x.measure);
            x.beat = c.measures[measure_index].start + c.measures[measure_index].length * x.fraction;
        } catch (const std::overflow_error&) {
            return invalid_timeline(std::move(c), x.source_line, "event beat exceeds the representable range",
                                    "chart editing is unavailable because an event beat overflows");
        }
        if (x.kind == BmsEventKind::extended_bpm && !bpm[indexed_value(x.token, IndexedTimingRadix::bpm_x1296())])
            c.diagnostics.push_back({x.source_line, "undefined #BPM reference " + x.token});
        if (x.kind == BmsEventKind::stop && !stop[indexed_value(x.token, IndexedTimingRadix::stop_x1296())])
            c.diagnostics.push_back({x.source_line, "undefined #STOP reference " + x.token});
        if (x.kind == BmsEventKind::scroll && !scroll[base36_value(x.token)])
            c.diagnostics.push_back({x.source_line, "undefined #SCROLL reference " + x.token});
        c.events.push_back(std::move(x));
    }
    return c;
}

std::vector<Hit> find_normal_note_hits(std::string_view b, int m, std::string_view ch, BeatPosition f)
{
    std::vector<Hit> out;
    for (auto l : lines(b)) {
        auto r = parse_channel_row(b, l);
        if (!r || r->measure != m || r->channel != ch)
            continue;
        for (std::size_t i = 0; i < r->slots; ++i)
            if (BeatPosition(static_cast<BeatPosition::rep>(i), static_cast<BeatPosition::rep>(r->slots)) == f) {
                auto t = b.substr(r->payload + i * 2, 2);
                if (t != "00")
                    out.push_back({r->payload + i * 2, std::string(t)});
            }
    }
    return out;
}

std::string measure_channel_prefix(int measure, std::string_view channel);

void validate_note_coordinate(int m, std::string_view ch, BeatPosition f)
{
    if (m < 0 || m > 999)
        throw std::invalid_argument("BMS measure must be in the range 0 through 999");
    const EditTarget target = parse_edit_target(ch);
    if (!is_object_edit_channel(target.channel))
        throw std::invalid_argument("only normal, hidden, mine, long-note, BGA, or BGM BMS channels may be edited");
    if (f < BeatPosition{} || f >= BeatPosition{1})
        throw std::invalid_argument("BMS note fraction must be in [0, 1)");
}

std::size_t gcd_slots(std::size_t a, std::size_t b)
{
    while (b != 0) {
        const std::size_t t = a % b;
        a = b;
        b = t;
    }
    return a == 0 ? 1 : a;
}

std::size_t lcm_slots(std::size_t a, std::size_t b)
{
    if (a == 0 || b == 0)
        return 0;
    const std::size_t g = gcd_slots(a, b);
    if (b != 0 && a / g > max_slots / b)
        throw std::length_error("note insertion would exceed the 65536-slot row limit");
    return (a / g) * b;
}

std::vector<Row> bgm_rows_in_measure(std::string_view b, int measure)
{
    std::vector<Row> rows;
    for (auto l : lines(b)) {
        auto r = parse_channel_row(b, l);
        if (r && r->measure == measure && r->channel == "01")
            rows.push_back(*r);
    }
    return rows;
}

std::optional<Hit> find_bgm_hit(std::string_view b, const Row& row, BeatPosition fraction)
{
    for (std::size_t i = 0; i < row.slots; ++i) {
        if (BeatPosition(static_cast<BeatPosition::rep>(i), static_cast<BeatPosition::rep>(row.slots)) == fraction) {
            auto t = b.substr(row.payload + i * 2, 2);
            if (t != "00")
                return Hit{row.payload + i * 2, std::string(t)};
        }
    }
    return {};
}

std::string expand_bgm_payload(std::string_view old_payload, std::size_t old_slots, std::size_t new_slots)
{
    std::string out(new_slots * 2, '0');
    const std::size_t scale = new_slots / old_slots;
    for (std::size_t i = 0; i < old_slots; ++i) {
        out[i * scale * 2] = old_payload[i * 2];
        out[i * scale * 2 + 1] = old_payload[i * 2 + 1];
    }
    return out;
}

struct RawByteChange {
    std::size_t offset;
    std::string before;
    std::string after;
};

RawByteChange make_bgm_insert_change(const std::string& bytes, int measure, int lane, BeatPosition fraction,
                            std::string_view token)
{
    const auto rows = bgm_rows_in_measure(bytes, measure);
    if (lane < static_cast<int>(rows.size())) {
        const Row& row = rows[static_cast<std::size_t>(lane)];
        if (find_bgm_hit(bytes, row, fraction))
            throw std::logic_error("a normal note already occupies the destination");
        const std::size_t old_slots = row.slots;
        const std::size_t want = static_cast<std::size_t>(fraction.denominator());
        const std::size_t new_slots = lcm_slots(old_slots, want);
        if (new_slots == 0 || new_slots > max_slots)
            throw std::length_error("note insertion would exceed the 65536-slot row limit");
        std::string old_payload(bytes.substr(row.payload, old_slots * 2));
        std::string new_payload = expand_bgm_payload(old_payload, old_slots, new_slots);
        const std::size_t slot = static_cast<std::size_t>(
            (static_cast<__int128>(fraction.numerator()) * static_cast<__int128>(new_slots)) /
            static_cast<__int128>(fraction.denominator()));
        if (new_payload.substr(slot * 2, 2) != "00")
            throw std::logic_error("a normal note already occupies the destination");
        new_payload[slot * 2] = token[0];
        new_payload[slot * 2 + 1] = token[1];
        return RawByteChange{row.payload, std::move(old_payload), std::move(new_payload)};
    }
    const std::size_t slot_count = static_cast<std::size_t>(fraction.denominator());
    if (slot_count == 0 || slot_count > max_slots)
        throw std::length_error("note insertion would exceed the 65536-slot row limit");
    std::string appended;
    auto append_row = [&](std::string_view payload) {
        if (appended.empty() && bytes.size() > (bom(bytes) ? 3U : 0U) && !end_eol(bytes))
            appended += eol(bytes);
        appended += measure_channel_prefix(measure, "01");
        appended += payload;
        appended += eol(bytes);
    };
    for (int i = static_cast<int>(rows.size()); i < lane; ++i)
        append_row("00");
    std::string payload(slot_count * 2, '0');
    const std::size_t slot = static_cast<std::size_t>(fraction.numerator());
    payload[slot * 2] = token[0];
    payload[slot * 2 + 1] = token[1];
    append_row(payload);
    return RawByteChange{bytes.size(), {}, std::move(appended)};
}

RawByteChange make_bgm_erase_change(const std::string& bytes, int measure, int lane, BeatPosition fraction)
{
    const auto rows = bgm_rows_in_measure(bytes, measure);
    if (lane < 0 || lane >= static_cast<int>(rows.size()))
        throw std::out_of_range("no normal note exists at the requested position");
    const auto hit = find_bgm_hit(bytes, rows[static_cast<std::size_t>(lane)], fraction);
    if (!hit)
        throw std::out_of_range("no normal note exists at the requested position");
    return RawByteChange{hit->offset, hit->token, "00"};
}

bool is_timing_channel(std::string_view channel)
{
    return channel == "03" || channel == "08" || channel == "09" || channel == "SC";
}

void validate_timing_coordinate(int measure, std::string_view channel, BeatPosition fraction)
{
    if (measure < 0 || measure > 999)
        throw std::invalid_argument("BMS measure must be in the range 0 through 999");
    if (!is_timing_channel(channel))
        throw std::invalid_argument("timing edits support only channels 03, 08, 09, and SC");
    if (fraction < BeatPosition{} || fraction >= BeatPosition{1})
        throw std::invalid_argument("BMS timing fraction must be in [0, 1)");
}

void validate_long_note_position(BmsLongNotePosition position)
{
    if (position.measure < 0 || position.measure > 999)
        throw std::invalid_argument("BMS measure must be in the range 0 through 999");
    if (position.fraction < BeatPosition{} || position.fraction >= BeatPosition{1})
        throw std::invalid_argument("BMS long-note fraction must be in [0, 1)");
}

BeatPosition position_beat(const BmsChart& chart, BmsLongNotePosition position)
{
    const BmsMeasure& measure = chart.measures[static_cast<std::size_t>(position.measure)];
    return measure.start + measure.length * position.fraction;
}

bool same_position(BmsLongNotePosition left, BmsLongNotePosition right)
{
    return left.measure == right.measure && left.fraction == right.fraction;
}

bool same_long_note_semantics(const BmsLongNote& left, const BmsLongNote& right)
{
    return left.channel == right.channel && left.encoding == right.encoding &&
           same_position(left.start.position, right.start.position) &&
           same_position(left.end.position, right.end.position) && left.start.beat == right.start.beat &&
           left.end.beat == right.end.beat && left.start.token == right.start.token && left.end.token == right.end.token;
}

bool long_note_less(const BmsLongNote& left, const BmsLongNote& right)
{
    if (left.channel != right.channel)
        return left.channel < right.channel;
    if (left.encoding != right.encoding)
        return left.encoding < right.encoding;
    if (left.start.position.measure != right.start.position.measure)
        return left.start.position.measure < right.start.position.measure;
    if (left.start.position.fraction != right.start.position.fraction)
        return left.start.position.fraction < right.start.position.fraction;
    if (left.end.position.measure != right.end.position.measure)
        return left.end.position.measure < right.end.position.measure;
    return left.end.position.fraction < right.end.position.fraction;
}

bool same_long_note_set(std::vector<BmsLongNote> left, std::vector<BmsLongNote> right)
{
    std::sort(left.begin(), left.end(), long_note_less);
    std::sort(right.begin(), right.end(), long_note_less);
    if (left.size() != right.size())
        return false;
    for (std::size_t index = 0; index < left.size(); ++index)
        if (!same_long_note_semantics(left[index], right[index]))
            return false;
    return true;
}

bool same_lnobj_pairs(const BmsLongNotes& left, const BmsLongNotes& right)
{
    std::vector<BmsLongNote> left_lnobj;
    std::vector<BmsLongNote> right_lnobj;
    for (const BmsLongNote& note : left.notes)
        if (note.encoding == BmsLongNoteEncoding::lnobj)
            left_lnobj.push_back(note);
    for (const BmsLongNote& note : right.notes)
        if (note.encoding == BmsLongNoteEncoding::lnobj)
            right_lnobj.push_back(note);
    return same_long_note_set(std::move(left_lnobj), std::move(right_lnobj));
}

bool preserves_long_channel_pairs(const BmsLongNotes& previous, const BmsLongNotes& candidate)
{
    std::vector<BmsLongNote> previous_channel;
    std::vector<BmsLongNote> candidate_channel;
    for (const BmsLongNote& note : previous.notes)
        if (note.encoding == BmsLongNoteEncoding::long_channel)
            previous_channel.push_back(note);
    for (const BmsLongNote& note : candidate.notes)
        if (note.encoding == BmsLongNoteEncoding::long_channel)
            candidate_channel.push_back(note);
    for (const BmsLongNote& note : previous_channel) {
        bool found = false;
        for (const BmsLongNote& other : candidate_channel) {
            if (same_long_note_semantics(note, other)) {
                found = true;
                break;
            }
        }
        if (!found)
            return false;
    }
    return true;
}

bool intervals_overlap_inclusively(
    const BeatPosition& left_start, const BeatPosition& left_end,
    const BeatPosition& right_start, const BeatPosition& right_end)
{
    return left_start <= right_end && right_start <= left_end;
}

void require_long_note_interval_clear(
    const BmsLongNotes& notes, std::string_view channel, BmsLongNoteEncoding encoding,
    const BeatPosition& start, const BeatPosition& end, const BmsLongNote* ignored)
{
    for (const BmsLongNote& existing : notes.notes) {
        if (&existing == ignored || existing.channel != channel || existing.encoding != encoding)
            continue;
        if (intervals_overlap_inclusively(start, end, existing.start.beat, existing.end.beat))
            throw std::logic_error("long-note interval collides with an existing paired long note");
    }
}

void require_lnobj_source_interval_clear(
    const BmsChart& chart, std::string_view channel, const BeatPosition& start, const BeatPosition& end,
    std::optional<BmsLongNotePosition> ignored_start = {}, std::optional<BmsLongNotePosition> ignored_end = {})
{
    for (const BmsEvent& event : chart.events) {
        if (event.kind != BmsEventKind::normal_note || event.channel != channel ||
            event.beat < start || event.beat > end)
            continue;
        const BmsLongNotePosition position{event.measure, event.fraction};
        if ((ignored_start.has_value() && same_position(position, *ignored_start)) ||
            (ignored_end.has_value() && same_position(position, *ignored_end)))
            continue;
        throw std::logic_error("LNOBJ interval would consume an existing normal-note source cell");
    }
}

const BmsLongNote* find_long_note(
    const BmsLongNotes& notes, std::string_view channel, BmsLongNotePosition start)
{
    const BmsLongNote* match = nullptr;
    for (const BmsLongNote& note : notes.notes) {
        if (note.channel != channel || !same_position(note.start.position, start))
            continue;
        if (match != nullptr)
            return nullptr;
        match = &note;
    }
    return match;
}

void validate_long_note_tokens(std::string_view start_token, std::string_view end_token)
{
    if (!is_base36_token(start_token) || start_token == "00" || !is_base36_token(end_token) || end_token == "00")
        throw std::invalid_argument("long-note endpoint tokens must be base36 in the range 01 through ZZ");
}

std::vector<Hit> find_timing_hits(
    std::string_view source, int measure, std::string_view channel, BeatPosition fraction)
{
    std::vector<Hit> hits;
    for (const Line line : lines(source)) {
        const std::optional<Row> row = parse_channel_row(source, line);
        if (!row.has_value() || row->measure != measure || row->channel != channel)
            continue;
        for (std::size_t slot = 0; slot < row->slots; ++slot) {
            const BeatPosition slot_fraction{
                static_cast<BeatPosition::rep>(slot), static_cast<BeatPosition::rep>(row->slots)};
            if (slot_fraction != fraction)
                continue;
            const std::string_view token = source.substr(row->payload + slot * 2, 2);
            if (token != "00")
                hits.push_back({row->payload + slot * 2, std::string(token)});
        }
    }
    return hits;
}

std::string measure_channel_prefix(int measure, std::string_view channel)
{
    return "#" + std::to_string(measure / 100) + std::to_string(measure / 10 % 10) +
           std::to_string(measure % 10) + std::string(channel) + ":";
}

std::string make_sparse_row(
    std::string_view source, int measure, std::string_view channel,
    BeatPosition fraction, std::string_view token)
{
    const std::size_t slot_count = static_cast<std::size_t>(fraction.denominator());
    if (slot_count > max_slots)
        throw std::length_error("note insertion would exceed the 65536-slot row limit");

    std::string row;
    if (source.size() > (bom(source) ? 3U : 0U) && !end_eol(source))
        row += eol(source);
    row += measure_channel_prefix(measure, channel);

    const std::size_t payload_offset = row.size();
    row.append(slot_count * 2, '0');
    const std::size_t slot = static_cast<std::size_t>(fraction.numerator());
    row[payload_offset + slot * 2] = token[0];
    row[payload_offset + slot * 2 + 1] = token[1];
    row += eol(source);
    return row;
}

std::string base36_token(std::size_t value)
{
    constexpr std::string_view digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return {digits[value / 36], digits[value % 36]};
}

std::string hex_token_encode(std::size_t value)
{
    constexpr std::string_view digits = "0123456789ABCDEF";
    return {digits[value / 16], digits[value % 16]};
}

std::string indexed_token(std::size_t value, bool x1296)
{
    return x1296 ? base36_token(value) : hex_token_encode(value);
}

std::size_t reserve_timing_resource(
    std::string_view source, std::string_view resource_name, std::string_view channel, bool x1296)
{
    const std::size_t limit = x1296 ? 1296 : 256;
    std::array<bool, 1296> used{};
    for (const Line line : lines(source)) {
        const auto [begin, end] = bounds(source, line);
        const std::string_view text = source.substr(begin, end - begin);
        if (text.size() >= resource_name.size() + 2 && equal(text.substr(0, resource_name.size()), resource_name) &&
            is_indexed_token(text.substr(resource_name.size(), 2), x1296)) {
            used[indexed_value(text.substr(resource_name.size(), 2), x1296)] = true;
        }
        const std::optional<Row> row = parse_channel_row(source, line);
        if (!row.has_value() || row->channel != channel)
            continue;
        for (std::size_t slot = 0; slot < row->slots; ++slot) {
            const std::string_view token = source.substr(row->payload + slot * 2, 2);
            if (is_indexed_token(token, x1296))
                used[indexed_value(token, x1296)] = true;
        }
    }
    for (std::size_t value = 1; value < limit; ++value)
        if (!used[value])
            return value;
    throw std::length_error("no unreserved BMS timing resource token remains");
}

std::string timing_resource_append(
    std::string_view source, std::string_view resource_name, std::size_t resource_id,
    std::string_view decimal, int measure, std::string_view channel, BeatPosition fraction, bool x1296)
{
    std::string appended;
    if (source.size() > (bom(source) ? 3U : 0U) && !end_eol(source))
        appended += eol(source);
    appended += std::string(resource_name) + indexed_token(resource_id, x1296) + " " + std::string(decimal) + eol(source);

    std::string source_after_definition(source);
    source_after_definition += appended;
    appended += make_sparse_row(source_after_definition, measure, channel, fraction, indexed_token(resource_id, x1296));
    return appended;
}

struct IndexedTimingWrite {
    std::string_view resource_name;
    bool x1296;
};

IndexedTimingWrite indexed_timing_write(std::string_view channel)
{
    if (channel == "08")
        return {"#BPM", IndexedTimingRadix::bpm_x1296()};
    if (channel == "09")
        return {"#STOP", IndexedTimingRadix::stop_x1296()};
    return {"#SCROLL", true};
}

const char* timing_decimal_error(std::string_view channel)
{
    if (channel == "09")
        return "STOP must be a nonnegative decimal";
    if (channel == "SC")
        return "SCROLL must be a decimal";
    return "BPM must be a positive decimal";
}

std::string timing_resource_definition_append(
    std::string_view source, std::string_view resource_name, std::size_t resource_id, std::string_view decimal,
    bool x1296)
{
    std::string appended;
    if (source.size() > (bom(source) ? 3U : 0U) && !end_eol(source))
        appended += eol(source);
    appended += std::string(resource_name) + indexed_token(resource_id, x1296) + " " + std::string(decimal) + eol(source);
    return appended;
}

std::size_t directive_content_begin(std::string_view source, const Line& line)
{
    std::size_t begin = line.begin;
    if (line.number == 0 && bom(source))
        begin = std::max(begin, static_cast<std::size_t>(3));
    while (begin < line.end && hspace(source[begin]))
        ++begin;
    return begin;
}

void rewrite_indexed_token(std::string& source, std::size_t offset, bool from_1296, bool to_1296)
{
    if (from_1296 == to_1296 || offset + 2 > source.size())
        return;
    const std::string_view token{source.data() + offset, 2};
    if (token[0] == '0' && token[1] == '0')
        return;
    if (!is_indexed_token(token, from_1296))
        return;
    const std::size_t value = indexed_value(token, from_1296);
    if (value == 0)
        return;
    if (!to_1296 && value > 255)
        return;
    const std::string next = indexed_token(value, to_1296);
    source[offset] = next[0];
    source[offset + 1] = next[1];
}

std::string rewrite_indexed_timing_labels(
    std::string source, bool bpm_from, bool stop_from, bool bpm_to, bool stop_to)
{
    if (bpm_from == bpm_to && stop_from == stop_to)
        return source;
    for (const Line line : lines(source)) {
        const std::size_t begin = directive_content_begin(source, line);
        if (begin >= line.end)
            continue;
        const std::string_view text{source.data() + begin, line.end - begin};
        if (bpm_from != bpm_to && text.size() >= 6 && equal(text.substr(0, 4), "#BPM")) {
            const std::string_view token = text.substr(4, 2);
            if (is_indexed_token(token, bpm_from) && (text.size() == 6 || hspace(text[6])))
                rewrite_indexed_token(source, begin + 4, bpm_from, bpm_to);
        }
        if (stop_from != stop_to && text.size() >= 7 && equal(text.substr(0, 5), "#STOP")) {
            const std::string_view token = text.substr(5, 2);
            if (is_indexed_token(token, stop_from) && (text.size() == 7 || hspace(text[7])))
                rewrite_indexed_token(source, begin + 5, stop_from, stop_to);
        }
        if (const auto row = parse_channel_row(source, line)) {
            if (row->channel == "08" && bpm_from != bpm_to) {
                for (std::size_t slot = 0; slot < row->slots; ++slot)
                    rewrite_indexed_token(source, row->payload + slot * 2, bpm_from, bpm_to);
            }
            if (row->channel == "09" && stop_from != stop_to) {
                for (std::size_t slot = 0; slot < row->slots; ++slot)
                    rewrite_indexed_token(source, row->payload + slot * 2, stop_from, stop_to);
            }
        }
    }
    return source;
}

bool relocatable_note_kind(BmsEventKind kind)
{
    return kind == BmsEventKind::normal_note || kind == BmsEventKind::hidden_note ||
           kind == BmsEventKind::mine || kind == BmsEventKind::bgm || kind == BmsEventKind::bga;
}

bool relocatable_timing_kind(BmsEventKind kind)
{
    return kind == BmsEventKind::bpm || kind == BmsEventKind::extended_bpm ||
           kind == BmsEventKind::stop || kind == BmsEventKind::scroll;
}

std::string note_write_channel(const BmsEvent& event)
{
    if (event.kind == BmsEventKind::bgm)
        return "B" + std::to_string(event.bgm_lane + 1);
    return event.channel;
}

std::optional<int> hex_byte_token(std::string_view token)
{
    if (token.size() != 2)
        return {};
    auto digit = [](char c) -> int {
        if (c >= '0' && c <= '9')
            return c - '0';
        if (c >= 'A' && c <= 'F')
            return c - 'A' + 10;
        if (c >= 'a' && c <= 'f')
            return c - 'a' + 10;
        return -1;
    };
    const int high = digit(token[0]);
    const int low = digit(token[1]);
    if (high < 0 || low < 0)
        return {};
    return high * 16 + low;
}

std::string unsigned_decimal_digits(unsigned __int128 value)
{
    if (value == 0)
        return "0";
    std::string digits;
    while (value != 0) {
        digits.push_back(static_cast<char>('0' + value % 10));
        value /= 10;
    }
    std::reverse(digits.begin(), digits.end());
    return digits;
}

std::optional<std::string> exact_decimal_string(const BeatPosition& value)
{
    const bool negative = value.numerator() < 0;
    unsigned __int128 numerator = negative
        ? static_cast<unsigned __int128>(-(value.numerator() + 1)) + 1
        : static_cast<unsigned __int128>(value.numerator());
    std::uint64_t denominator = static_cast<std::uint64_t>(value.denominator());
    unsigned int twos = 0;
    unsigned int fives = 0;
    while (denominator % 2 == 0) {
        denominator /= 2;
        ++twos;
    }
    while (denominator % 5 == 0) {
        denominator /= 5;
        ++fives;
    }
    if (denominator != 1)
        return {};
    constexpr unsigned __int128 maximum = ~static_cast<unsigned __int128>(0);
    const unsigned int fractional_digits = std::max(twos, fives);
    for (unsigned int count = twos; count < fractional_digits; ++count) {
        if (numerator > maximum / 2)
            return {};
        numerator *= 2;
    }
    for (unsigned int count = fives; count < fractional_digits; ++count) {
        if (numerator > maximum / 5)
            return {};
        numerator *= 5;
    }
    std::string text = unsigned_decimal_digits(numerator);
    if (fractional_digits != 0) {
        if (text.size() <= fractional_digits)
            text.insert(0, fractional_digits + 1 - text.size(), '0');
        text.insert(text.size() - fractional_digits, 1, '.');
    }
    if (negative)
        text.insert(text.begin(), '-');
    return text;
}

std::optional<std::string> indexed_resource_decimal(
    std::string_view bytes, std::string_view resource_name, std::string_view token, bool x1296, bool allow_zero,
    bool allow_negative)
{
    const std::string upper_token = uppercase_ascii(token);
    std::optional<std::string> found;
    for (const Line line : lines(bytes)) {
        const auto [begin, end] = bounds(bytes, line);
        const std::string_view text = bytes.substr(begin, end - begin);
        if (text.size() < resource_name.size() + 3 ||
            !equal(text.substr(0, resource_name.size()), resource_name))
            continue;
        const std::string_view label = text.substr(resource_name.size(), 2);
        if (!is_indexed_token(label, x1296) || uppercase_ascii(label) != upper_token)
            continue;
        if (text.size() > resource_name.size() + 2 && !hspace(text[resource_name.size() + 2]))
            continue;
        const std::string_view decimal = trim(text.substr(resource_name.size() + 2));
        if (!ratio(decimal, allow_zero, allow_negative).has_value())
            continue;
        found = std::string(decimal);
    }
    return found;
}

std::optional<std::string> timing_write_decimal(const BmsDocument& document, const BmsEvent& event)
{
    if (event.kind == BmsEventKind::bpm) {
        if (const auto value = hex_byte_token(event.token))
            return std::to_string(*value);
        return {};
    }
    if (event.kind == BmsEventKind::scroll)
        return indexed_resource_decimal(document.serialize(), "#SCROLL", event.token, true, true, true);
    if (!document.timing().available)
        return {};
    for (const auto& timing : document.timing().events) {
        if (timing.measure == event.measure && timing.channel == event.channel &&
            timing.fraction == event.fraction)
            return exact_decimal_string(timing.value);
    }
    return {};
}

std::pair<int, BeatPosition> bin_measure(const std::array<BeatPosition, 1000>& lengths, BeatPosition beat)
{
    BeatPosition start;
    for (int measure = 0; measure < 1000; ++measure) {
        const BeatPosition end = start + lengths[static_cast<std::size_t>(measure)];
        if (beat < end) {
            if (beat < start)
                throw std::overflow_error("beat is outside measures 0 through 999");
            return {measure, (beat - start) / lengths[static_cast<std::size_t>(measure)]};
        }
        start = end;
    }
    throw std::overflow_error("beat is outside measures 0 through 999");
}

struct BeatRelocate {
    BmsEvent event;
    bool erase = false;
    bool insert = false;
    int dest_measure = 0;
    BeatPosition dest_fraction;
    bool timing = false;
    std::string write_channel;
    std::string decimal;
};

struct LongBeatRelocate {
    BmsLongNote note;
    bool erase = false;
    bool insert = false;
    BmsLongNotePosition dest_start;
    BmsLongNotePosition dest_end;
};

bool is_long_endpoint(const BmsLongNotes& notes, const BmsEvent& event)
{
    for (const auto& note : notes.notes) {
        if (note.channel != event.channel)
            continue;
        if (same_position(note.start.position, {event.measure, event.fraction}) ||
            same_position(note.end.position, {event.measure, event.fraction}))
            return true;
    }
    return false;
}

void apply_beat_one(BmsDocument& working, int measure, std::string_view decimal, BmsBeatChangeMode mode)
{
    if (measure < 0 || measure > 999)
        throw std::invalid_argument("BMS measure must be in the range 0 through 999");
    const auto new_ratio = ratio(decimal);
    if (!new_ratio.has_value())
        throw std::invalid_argument("measure ratio must be a positive decimal");
    if (!working.chart().editable)
        throw std::logic_error(working.chart().editing_reason);

    const auto& measures = working.chart().measures;
    const BeatPosition old_length = measures[static_cast<std::size_t>(measure)].length;
    const BeatPosition start = measures[static_cast<std::size_t>(measure)].start;
    const BeatPosition old_end = start + old_length;
    const BeatPosition new_length = *new_ratio * BeatPosition{4};
    const BeatPosition new_end = start + new_length;
    const BeatPosition delta = new_length - old_length;

    std::array<BeatPosition, 1000> new_lengths;
    for (int index = 0; index < 1000; ++index)
        new_lengths[static_cast<std::size_t>(index)] = measures[static_cast<std::size_t>(index)].length;
    new_lengths[static_cast<std::size_t>(measure)] = new_length;

    const BmsLongNotes& holds = working.long_notes();
    const bool relocate_holds = mode != BmsBeatChangeMode::scale && holds.editable;
    std::vector<BeatRelocate> plans;
    for (const auto& event : working.chart().events) {
        const bool note = relocatable_note_kind(event.kind);
        const bool timing = relocatable_timing_kind(event.kind);
        if (!note && !timing)
            continue;
        if (relocate_holds && is_long_endpoint(holds, event))
            continue;
        BeatRelocate plan;
        plan.event = event;
        plan.timing = timing;
        plan.write_channel = note_write_channel(event);
        if (timing) {
            const auto value = timing_write_decimal(working, event);
            if (!value.has_value())
                continue;
            plan.decimal = *value;
        }
        const bool in_cut = mode == BmsBeatChangeMode::cut && delta < BeatPosition{} &&
                            event.beat >= new_end && event.beat < old_end;
        if (in_cut) {
            plan.erase = true;
            plans.push_back(std::move(plan));
            continue;
        }
        if (mode == BmsBeatChangeMode::scale)
            continue;
        BeatPosition target = event.beat;
        if ((mode == BmsBeatChangeMode::measure || mode == BmsBeatChangeMode::cut) && event.beat >= old_end)
            target = event.beat + delta;
        const auto [dest_measure, dest_fraction] = bin_measure(new_lengths, target);
        if (dest_measure == event.measure && dest_fraction == event.fraction)
            continue;
        plan.erase = true;
        plan.insert = true;
        plan.dest_measure = dest_measure;
        plan.dest_fraction = dest_fraction;
        plans.push_back(std::move(plan));
    }

    std::vector<LongBeatRelocate> hold_plans;
    if (relocate_holds) {
        const BeatPosition one_vpos{1, 48};
        for (const auto& note : holds.notes) {
            BeatPosition hold_start = note.start.beat;
            BeatPosition hold_end = note.end.beat;
            LongBeatRelocate plan;
            plan.note = note;
            if (mode == BmsBeatChangeMode::cut && delta < BeatPosition{}) {
                if (hold_start < new_end) {
                    if (hold_end >= new_end && hold_end < old_end)
                        hold_end = new_end - one_vpos;
                } else if (hold_start < old_end) {
                    if (hold_end < old_end) {
                        plan.erase = true;
                        hold_plans.push_back(std::move(plan));
                        continue;
                    }
                    hold_start = old_end;
                }
            }
            if (mode == BmsBeatChangeMode::measure || mode == BmsBeatChangeMode::cut) {
                if (hold_start >= old_end) {
                    hold_start = hold_start + delta;
                    hold_end = hold_end + delta;
                } else if (hold_end >= old_end) {
                    hold_end = hold_end + delta;
                }
            }
            if (hold_end <= hold_start) {
                plan.erase = true;
                hold_plans.push_back(std::move(plan));
                continue;
            }
            const auto [dest_start_measure, dest_start_fraction] = bin_measure(new_lengths, hold_start);
            const auto [dest_end_measure, dest_end_fraction] = bin_measure(new_lengths, hold_end);
            if (dest_start_measure == note.start.position.measure &&
                dest_start_fraction == note.start.position.fraction &&
                dest_end_measure == note.end.position.measure && dest_end_fraction == note.end.position.fraction)
                continue;
            plan.erase = true;
            plan.insert = true;
            plan.dest_start = {dest_start_measure, dest_start_fraction};
            plan.dest_end = {dest_end_measure, dest_end_fraction};
            hold_plans.push_back(std::move(plan));
        }
    }

    for (const auto& plan : hold_plans) {
        if (plan.erase)
            working.erase_long_note(plan.note.channel, plan.note.start.position);
    }
    for (const auto& plan : plans) {
        if (!plan.erase)
            continue;
        if (plan.timing)
            working.erase_timing_event(plan.event.measure, plan.event.channel, plan.event.fraction);
        else
            working.erase_note(plan.event.measure, plan.write_channel, plan.event.fraction);
    }
    working.set_measure_ratio(measure, decimal);
    for (const auto& plan : plans) {
        if (!plan.insert)
            continue;
        if (plan.timing)
            working.insert_timing_event(plan.dest_measure, plan.event.channel, plan.dest_fraction, plan.decimal);
        else
            working.insert_note(plan.dest_measure, plan.write_channel, plan.dest_fraction, plan.event.token);
    }
    for (const auto& plan : hold_plans) {
        if (!plan.insert)
            continue;
        working.insert_long_note(
            plan.note.channel, plan.dest_start, plan.dest_end, plan.note.start.token, plan.note.end.token);
    }
}

bool starts_directive(std::string_view trimmed, std::string_view keyword)
{
    return trimmed.size() >= keyword.size() + 1 && trimmed.front() == '#' &&
           equal(trimmed.substr(1, keyword.size()), keyword);
}

int expansion_stack_delta(std::string_view trimmed)
{
    if (starts_directive(trimmed, "IF") || starts_directive(trimmed, "SWITCH") ||
        starts_directive(trimmed, "SETSWITCH"))
        return 1;
    if (starts_directive(trimmed, "ENDIF") || starts_directive(trimmed, "ENDSW"))
        return -1;
    return 0;
}

bool is_measure_ratio_line(std::string_view trimmed)
{
    return trimmed.size() >= 7 && trimmed[0] == '#' &&
           std::isdigit(static_cast<unsigned char>(trimmed[1])) &&
           std::isdigit(static_cast<unsigned char>(trimmed[2])) &&
           std::isdigit(static_cast<unsigned char>(trimmed[3])) && trimmed[4] == '0' && trimmed[5] == '2' &&
           trimmed[6] == ':';
}

bool is_channel_row_shape(std::string_view trimmed)
{
    return trimmed.size() >= 7 && trimmed[0] == '#' &&
           std::isdigit(static_cast<unsigned char>(trimmed[1])) &&
           std::isdigit(static_cast<unsigned char>(trimmed[2])) &&
           std::isdigit(static_cast<unsigned char>(trimmed[3])) && trimmed[6] == ':';
}

bool is_known_play_channel(std::string_view identifier)
{
    const std::string upper = uppercase_ascii(identifier);
    return in(upper, {"01", "03", "04", "06", "07", "08", "09", "SC",
                      "11", "12", "13", "14", "15", "16", "18", "19",
                      "21", "22", "23", "24", "25", "26", "28", "29",
                      "31", "32", "33", "34", "35", "36", "38", "39",
                      "41", "42", "43", "44", "45", "46", "48", "49",
                      "51", "52", "53", "54", "55", "56", "58", "59",
                      "61", "62", "63", "64", "65", "66", "68", "69",
                      "71", "72", "73", "74", "75", "76", "78", "79",
                      "81", "82", "83", "84", "85", "86", "88", "89",
                      "D1", "D2", "D3", "D4", "D5", "D6", "D8", "D9",
                      "E1", "E2", "E3", "E4", "E5", "E6", "E8", "E9"});
}

bool is_consumed_openbms_header(std::string_view trimmed)
{
    constexpr std::array<std::string_view, 22> keys = {
        "WAV",      "BMP",        "BPM",      "STOP",      "SCROLL",    "TITLE",
        "ARTIST",   "GENRE",      "PLAYER",   "RANK",      "PLAYLEVEL", "SUBTITLE",
        "SUBARTIST", "STAGEFILE", "BANNER",   "BACKBMP",   "DIFFICULTY", "DEFEXRANK",
        "TOTAL",    "COMMENT",    "LNTYPE",   "LNOBJ"};
    for (const auto key : keys) {
        if (starts_directive(trimmed, key))
            return true;
    }
    return false;
}

bool is_openbms_expansion_line(std::string_view trimmed, int stack)
{
    if (trimmed.empty() || trimmed.front() != '#')
        return false;
    if (stack > 0)
        return true;
    if (is_measure_ratio_line(trimmed) || is_consumed_openbms_header(trimmed))
        return false;
    if (is_channel_row_shape(trimmed))
        return !is_known_play_channel(trimmed.substr(4, 2));
    return true;
}

std::size_t line_extent_end(std::string_view bytes, const Line& line)
{
    if (line.end >= bytes.size())
        return bytes.size();
    if (bytes[line.end] == '\r' && line.end + 1 < bytes.size() && bytes[line.end + 1] == '\n')
        return line.end + 2;
    if (bytes[line.end] == '\r' || bytes[line.end] == '\n')
        return line.end + 1;
    return line.end;
}

struct ExpansionSpan {
    std::size_t begin = 0;
    std::size_t end = 0;
};

std::vector<ExpansionSpan> expansion_spans(std::string_view bytes)
{
    std::vector<ExpansionSpan> spans;
    int stack = 0;
    for (const Line line : lines(bytes)) {
        const auto [begin, end] = bounds(bytes, line);
        const std::string_view trimmed = bytes.substr(begin, end - begin);
        const int delta = expansion_stack_delta(trimmed);
        if (is_openbms_expansion_line(trimmed, stack))
            spans.push_back({line.begin, line_extent_end(bytes, line)});
        stack += delta;
        if (stack < 0)
            stack = 0;
    }
    return spans;
}

std::string collect_expansion(std::string_view bytes)
{
    std::string text;
    for (const auto& span : expansion_spans(bytes))
        text.append(bytes.data() + span.begin, span.end - span.begin);
    return text;
}

std::vector<std::string_view> expansion_payload_lines(std::string_view text)
{
    std::vector<std::string_view> rows;
    std::size_t i = 0;
    while (i < text.size()) {
        std::size_t end = i;
        while (end < text.size() && text[end] != '\r' && text[end] != '\n')
            ++end;
        rows.push_back(text.substr(i, end - i));
        if (end < text.size() && text[end] == '\r' && end + 1 < text.size() && text[end + 1] == '\n')
            i = end + 2;
        else if (end < text.size())
            i = end + 1;
        else
            i = end;
    }
    if (!rows.empty() && rows.back().empty())
        rows.pop_back();
    return rows;
}

std::string rewrite_expansion(std::string_view bytes, std::string_view text)
{
    const auto spans = expansion_spans(bytes);
    const std::string ending = eol(bytes);
    std::string incoming;
    for (const auto line : expansion_payload_lines(text)) {
        incoming.append(line);
        incoming += ending;
    }
    std::string current;
    for (const auto& span : spans)
        current.append(bytes.data() + span.begin, span.end - span.begin);
    if (incoming == current)
        return std::string(bytes);

    std::string out;
    std::size_t cursor = 0;
    bool inserted = false;
    for (const auto& span : spans) {
        out.append(bytes.data() + cursor, span.begin - cursor);
        if (!inserted) {
            out += incoming;
            inserted = true;
        }
        cursor = span.end;
    }
    out.append(bytes.data() + cursor, bytes.size() - cursor);
    if (!inserted && !incoming.empty()) {
        if (!out.empty() && !end_eol(out))
            out += ending;
        out += incoming;
    }
    return out;
}

} // namespace
  // namespace

BmsDocument::BmsDocument(std::string b, bool c) noexcept
    : bytes_(std::move(b))
    , bpm_label_x1296_(IndexedTimingRadix::bpm_x1296())
    , stop_label_x1296_(IndexedTimingRadix::stop_x1296())
    , has_conditionals_(c)
{
}

BmsDocument BmsDocument::from_bytes(std::string b)
{
    const auto at = [&](std::size_t i) { return static_cast<unsigned char>(b[i]); };
    if ((b.size() >= 2 && ((at(0) == 0xff && at(1) == 0xfe) || (at(0) == 0xfe && at(1) == 0xff))) ||
        (b.size() >= 4 && ((at(0) == 0xff && at(1) == 0xfe && at(2) == 0 && at(3) == 0) ||
                           (at(0) == 0 && at(1) == 0 && at(2) == 0xfe && at(3) == 0xff))))
        throw std::invalid_argument("UTF-16 and UTF-32 BMS byte streams are unsupported");
    if (b.find('\0') != std::string::npos)
        throw std::invalid_argument("BMS byte streams containing NUL bytes are unsupported");
    bool c = conditional(b);
    return BmsDocument(std::move(b), c);
}

std::string BmsDocument::serialize() const
{
    if (has_conditionals_)
        return bytes_;
    const bool bpm = IndexedTimingRadix::bpm_x1296();
    const bool stop = IndexedTimingRadix::stop_x1296();
    if (bpm == bpm_label_x1296_ && stop == stop_label_x1296_)
        return bytes_;
    return rewrite_indexed_timing_labels(bytes_, bpm_label_x1296_, stop_label_x1296_, bpm, stop);
}

std::string BmsDocument::expansion() const
{
    return collect_expansion(bytes_);
}

void BmsDocument::set_expansion(std::string_view text)
{
    if (text.find('\0') != std::string_view::npos)
        throw std::invalid_argument("expansion text must not contain NUL bytes");
    const std::string next = rewrite_expansion(bytes_, text);
    if (next == bytes_)
        return;
    commit_patch(Patch{{BytePatch{0, bytes_, next}}, 0, 0});
}

void BmsDocument::align_indexed_timing_labels()
{
    const bool bpm = IndexedTimingRadix::bpm_x1296();
    const bool stop = IndexedTimingRadix::stop_x1296();
    if (has_conditionals_ || (bpm == bpm_label_x1296_ && stop == stop_label_x1296_))
        return;
    bytes_ = rewrite_indexed_timing_labels(bytes_, bpm_label_x1296_, stop_label_x1296_, bpm, stop);
    bpm_label_x1296_ = bpm;
    stop_label_x1296_ = stop;
    chart_revision_ = static_cast<std::size_t>(-1);
    timing_revision_ = static_cast<std::size_t>(-1);
}

std::optional<std::string> BmsDocument::header(std::string_view key) const
{
    if (has_conditionals_)
        return {};
    std::optional<std::string> out;
    for (auto l : lines(bytes_))
        if (auto h = header_match(bytes_, l, key))
            out = bytes_.substr(h->value_begin, h->value_end - h->value_begin);
    if (out && equal(key, "COMMENT")) {
        if (!out->empty() && out->front() == '"')
            out->erase(out->begin());
        if (!out->empty() && out->back() == '"')
            out->pop_back();
    }
    return out;
}

std::string BmsDocument::apply_patch_bytes(const std::string& s, const Patch& p, bool forward)
{
    std::string out;
    std::size_t cur = 0;
    std::ptrdiff_t shift = 0;
    for (auto& x : p.bytes) {
        auto& want = forward ? x.before : x.after;
        auto& put = forward ? x.after : x.before;
        auto at = forward ? x.offset : std::size_t(std::ptrdiff_t(x.offset) + shift);
        if (at < cur || at + want.size() > s.size() || s.compare(at, want.size(), want))
            throw std::logic_error("BMS history patch no longer matches document bytes");
        out.append(s, cur, at - cur);
        out += put;
        cur = at + want.size();
        if (!forward)
            shift += std::ptrdiff_t(x.after.size()) - std::ptrdiff_t(x.before.size());
    }
    out.append(s, cur, std::string::npos);
    return out;
}

std::string BmsDocument::make_sparse_note_row(std::string_view source, int measure, std::string_view channel,
                                              BeatPosition fraction, std::string_view token)
{
    return make_sparse_row(source, measure, channel, fraction, token);
}

void BmsDocument::commit_patch(Patch patch)
{
    if (compounding_) {
        bytes_ = apply_patch_bytes(bytes_, patch, true);
        has_conditionals_ = conditional(bytes_);
        chart_revision_ = static_cast<std::size_t>(-1);
        timing_revision_ = static_cast<std::size_t>(-1);
        long_note_revision_ = static_cast<std::size_t>(-1);
        return;
    }
    if (next_revision_ == std::numeric_limits<std::size_t>::max())
        throw std::overflow_error("BMS document history revision overflow");

    patch.before_revision = current_revision_;
    patch.after_revision = next_revision_;
    std::string updated = apply_patch_bytes(bytes_, patch, true);

    // Reserve and build the replacement before changing document bytes or history.
    undo_.reserve(undo_.size() + 1);
    undo_.push_back(std::move(patch));
    bytes_ = std::move(updated);
    has_conditionals_ = conditional(bytes_);
    redo_.clear();
    current_revision_ = undo_.back().after_revision;
    ++next_revision_;
}

void BmsDocument::commit_chart_edit_patch(Patch patch)
{
    const std::string candidate = apply_patch_bytes(bytes_, patch, true);
    const BmsChart candidate_chart = make_chart(candidate, has_conditionals_);
    if (!candidate_chart.editable || candidate_chart.measures.empty())
        throw std::overflow_error("chart edit would make derived positions unavailable");
    commit_patch(std::move(patch));
}

void BmsDocument::commit_long_note_patch(Patch patch, std::vector<BmsLongNote> expected_notes)
{
    const std::string candidate = apply_patch_bytes(bytes_, patch, true);
    const BmsChart candidate_chart = make_chart(candidate, has_conditionals_);
    const BmsLongNotes candidate_notes =
        detail::build_bms_long_notes(candidate, candidate_chart, has_conditionals_);
    if (!candidate_chart.editable || !candidate_notes.editable ||
        !same_long_note_set(candidate_notes.notes, expected_notes))
        throw std::logic_error("long-note edit would make pair semantics unavailable");
    commit_patch(std::move(patch));
}

void BmsDocument::commit_normal_note_patch(Patch patch)
{
    const BmsLongNotes previous_notes = long_notes();
    const std::string candidate = apply_patch_bytes(bytes_, patch, true);
    const BmsChart candidate_chart = make_chart(candidate, has_conditionals_);
    const BmsLongNotes candidate_notes =
        detail::build_bms_long_notes(candidate, candidate_chart, has_conditionals_);
    if (!candidate_chart.editable || !candidate_notes.editable || !same_lnobj_pairs(previous_notes, candidate_notes) ||
        !preserves_long_channel_pairs(previous_notes, candidate_notes))
        throw std::logic_error("normal-note edit would alter validated long-note pairing");
    commit_patch(std::move(patch));
}

void BmsDocument::set_header(std::string_view key, std::string_view value)
{
    constexpr std::array<std::string_view, 16> keys = {
        "TITLE",    "SUBTITLE", "ARTIST",     "SUBARTIST", "GENRE",
        "PLAYER",   "RANK",     "PLAYLEVEL",  "STAGEFILE", "BANNER",
        "BACKBMP",  "DIFFICULTY", "DEFEXRANK", "TOTAL",     "COMMENT",
        "LNOBJ",
    };
    auto it = std::find_if(keys.begin(), keys.end(), [&](auto k) { return equal(k, key); });
    std::string owned_list_key;
    std::string_view stored_key;
    const bool is_wav = is_list_slot(key, "WAV");
    const bool is_bmp = is_list_slot(key, "BMP");
    if (it == keys.end()) {
        if (!is_wav && !is_bmp)
            throw std::invalid_argument("unsupported BMS metadata key");
        owned_list_key = (is_wav ? "WAV" : "BMP") + uppercase_ascii(key.substr(3, 2));
        stored_key = owned_list_key;
    } else {
        stored_key = *it;
    }
    if (value.find_first_of("\r\n") != std::string_view::npos || value.find('\0') != std::string_view::npos)
        throw std::invalid_argument("BMS metadata values cannot contain CR, LF, or NUL bytes");
    if (has_conditionals_)
        throw std::logic_error("BMS metadata edits are unavailable while conditional directives are present");
    value = trim(value);
    const bool is_lnobj = equal(stored_key, "LNOBJ");
    const bool is_comment = equal(stored_key, "COMMENT");
    const bool omit_when_empty =
        equal(stored_key, "SUBTITLE") || equal(stored_key, "SUBARTIST") || equal(stored_key, "STAGEFILE") ||
        equal(stored_key, "BANNER") || equal(stored_key, "BACKBMP") || equal(stored_key, "DIFFICULTY") ||
        equal(stored_key, "DEFEXRANK") || equal(stored_key, "TOTAL") || is_comment;
    if (equal(stored_key, "DIFFICULTY") && value == "0")
        value = {};
    const bool remove_when_empty = is_lnobj || is_wav || is_bmp || omit_when_empty;
    std::string owned_lnobj;
    std::string owned_comment;
    if (is_comment && !value.empty()) {
        owned_comment.assign(1, '"');
        owned_comment.append(value);
        owned_comment.push_back('"');
        value = owned_comment;
    }
    if (is_lnobj && !value.empty()) {
        owned_lnobj.assign(value);
        for (char& c : owned_lnobj)
            c = upper(c);
        if (!is_base36_token(owned_lnobj) || owned_lnobj == "00")
            throw std::invalid_argument("LNOBJ must be empty or a base36 token 01 through ZZ");
        value = owned_lnobj;
    }
    std::optional<HeaderMatch> last;
    std::optional<Line> last_line;
    for (auto l : lines(bytes_))
        if (auto h = header_match(bytes_, l, stored_key)) {
            last = h;
            last_line = l;
        }
    BytePatch x;
    if (remove_when_empty && value.empty()) {
        if (!last || !last_line)
            return;
        std::size_t start = last_line->begin;
        if (start == 0 && bom(bytes_))
            start = 3;
        std::size_t end = last_line->end;
        if (end < bytes_.size()) {
            if (bytes_[end] == '\r' && end + 1 < bytes_.size() && bytes_[end + 1] == '\n')
                end += 2;
            else
                ++end;
        }
        x.offset = start;
        x.before = bytes_.substr(start, end - start);
        x.after = "";
    } else if (last) {
        x.offset = last->value_begin;
        x.before = bytes_.substr(last->value_begin, last->value_end - last->value_begin);
        x.after = value;
        if (last->separator_end == last->key_end && !value.empty()) {
            x.offset = last->key_end;
            x.before = "";
            x.after = " " + x.after;
        }

    } else {
        x.offset = bytes_.size();
        if (bytes_.size() > (bom(bytes_) ? 3 : 0) && !end_eol(bytes_))
            x.after += eol(bytes_);
        x.after += "#" + std::string(stored_key) + " " + std::string(value) + eol(bytes_);
    }
    if (x.before == x.after)
        return;
    commit_patch(Patch{{std::move(x)}, 0, 0});
}

const BmsChart& BmsDocument::chart() const
{
    const bool bpm_x1296 = IndexedTimingRadix::bpm_x1296();
    const bool stop_x1296 = IndexedTimingRadix::stop_x1296();
    if (chart_revision_ != current_revision_ || chart_cache_bpm_x1296_ != bpm_x1296 ||
        chart_cache_stop_x1296_ != stop_x1296) {
        auto x = make_chart(bytes_, has_conditionals_);
        auto long_notes = detail::build_bms_long_notes(bytes_, x, has_conditionals_);
        if (!long_notes.editable && x.editable)
            readonly(x, long_notes.editing_reason);
        chart_cache_ = std::move(x);
        long_note_cache_ = std::move(long_notes);
        chart_revision_ = current_revision_;
        long_note_revision_ = current_revision_;
        chart_cache_bpm_x1296_ = bpm_x1296;
        chart_cache_stop_x1296_ = stop_x1296;
    }
    return chart_cache_;
}

const BmsLongNotes& BmsDocument::long_notes() const
{
    static_cast<void>(chart());
    return long_note_cache_;
}

const BmsTiming& BmsDocument::timing() const
{
    const bool bpm_x1296 = IndexedTimingRadix::bpm_x1296();
    const bool stop_x1296 = IndexedTimingRadix::stop_x1296();
    if (timing_revision_ != current_revision_ || timing_cache_bpm_x1296_ != bpm_x1296 ||
        timing_cache_stop_x1296_ != stop_x1296) {
        timing_cache_ = detail::build_bms_timing(bytes_, has_conditionals_);
        timing_revision_ = current_revision_;
        timing_cache_bpm_x1296_ = bpm_x1296;
        timing_cache_stop_x1296_ = stop_x1296;
    }
    return timing_cache_;
}

void BmsDocument::insert_note(int measure, std::string_view channel, BeatPosition fraction, std::string_view token)
{
    const EditTarget target = parse_edit_target(channel);
    const std::string normalized_token = uppercase_ascii(token);
    validate_note_coordinate(measure, target.channel, fraction);
    if (!is_base36_token(normalized_token) || normalized_token == "00")
        throw std::invalid_argument("normal-note token must be base36 in the range 01 through ZZ");
    if (!chart().editable)
        throw std::logic_error(chart().editing_reason);
    if (target.channel == "01") {
        auto change = make_bgm_insert_change(bytes_, measure, target.bgm_lane, fraction, normalized_token);
        commit_normal_note_patch(Patch{{BytePatch{change.offset, std::move(change.before), std::move(change.after)}}, 0, 0});
        return;
    }
    if (!find_normal_note_hits(bytes_, measure, target.channel, fraction).empty())
        throw std::logic_error("a normal note already occupies the destination");
    std::string row = make_sparse_note_row(bytes_, measure, target.channel, fraction, normalized_token);
    commit_normal_note_patch(Patch{{BytePatch{bytes_.size(), {}, std::move(row)}}, 0, 0});
}

void BmsDocument::erase_note(int measure, std::string_view channel, BeatPosition fraction)
{
    const EditTarget target = parse_edit_target(channel);
    validate_note_coordinate(measure, target.channel, fraction);
    if (!chart().editable)
        throw std::logic_error(chart().editing_reason);
    if (target.channel == "01") {
        auto change = make_bgm_erase_change(bytes_, measure, target.bgm_lane, fraction);
        commit_normal_note_patch(Patch{{BytePatch{change.offset, std::move(change.before), std::move(change.after)}}, 0, 0});
        return;
    }
    const auto source_hits = find_normal_note_hits(bytes_, measure, target.channel, fraction);
    if (source_hits.empty())
        throw std::out_of_range("no normal note exists at the requested position");
    if (source_hits.size() != 1)
        throw std::logic_error("normal-note source position is ambiguous");
    commit_normal_note_patch(Patch{{BytePatch{source_hits.front().offset, source_hits.front().token, "00"}}, 0, 0});
}

void BmsDocument::move_note(int source_measure, std::string_view source_channel, BeatPosition source_fraction,
                            int destination_measure, std::string_view destination_channel,
                            BeatPosition destination_fraction)
{
    const EditTarget source = parse_edit_target(source_channel);
    const EditTarget destination = parse_edit_target(destination_channel);
    validate_note_coordinate(source_measure, source.channel, source_fraction);
    validate_note_coordinate(destination_measure, destination.channel, destination_fraction);
    if (!chart().editable)
        throw std::logic_error(chart().editing_reason);
    if (source_measure == destination_measure && source.channel == destination.channel &&
        source.bgm_lane == destination.bgm_lane && source_fraction == destination_fraction)
    {
        if (source.channel == "01") {
            (void)make_bgm_erase_change(bytes_, source_measure, source.bgm_lane, source_fraction);
        } else if (find_normal_note_hits(bytes_, source_measure, source.channel, source_fraction).empty()) {
            throw std::out_of_range("no normal note exists at the requested source position");
        }
        return;
    }
    if (source.channel == "01" || destination.channel == "01") {
        RawByteChange erase;
        std::string token;
        if (source.channel == "01") {
            erase = make_bgm_erase_change(bytes_, source_measure, source.bgm_lane, source_fraction);
            token = erase.before;
        } else {
            const auto source_hits = find_normal_note_hits(bytes_, source_measure, source.channel, source_fraction);
            if (source_hits.empty())
                throw std::out_of_range("no normal note exists at the requested source position");
            if (source_hits.size() != 1)
                throw std::logic_error("normal-note source position is ambiguous");
            erase = RawByteChange{source_hits.front().offset, source_hits.front().token, "00"};
            token = source_hits.front().token;
        }
        const std::string after_erase =
            apply_patch_bytes(bytes_, Patch{{BytePatch{erase.offset, erase.before, erase.after}}, 0, 0}, true);
        RawByteChange insert;
        if (destination.channel == "01") {
            insert = make_bgm_insert_change(after_erase, destination_measure, destination.bgm_lane, destination_fraction,
                                            token);
        } else {
            if (!find_normal_note_hits(after_erase, destination_measure, destination.channel, destination_fraction)
                     .empty())
                throw std::logic_error("a normal note already occupies the destination");
            insert = RawByteChange{after_erase.size(), {},
                                   make_sparse_note_row(after_erase, destination_measure, destination.channel,
                                                        destination_fraction, token)};
        }
        const std::string after_insert =
            apply_patch_bytes(after_erase, Patch{{BytePatch{insert.offset, insert.before, insert.after}}, 0, 0}, true);
        commit_normal_note_patch(Patch{{BytePatch{0, bytes_, after_insert}}, 0, 0});
        return;
    }
    const auto source_hits = find_normal_note_hits(bytes_, source_measure, source.channel, source_fraction);
    if (source_hits.empty())
        throw std::out_of_range("no normal note exists at the requested source position");
    if (source_hits.size() != 1)
        throw std::logic_error("normal-note source position is ambiguous");
    if (!find_normal_note_hits(bytes_, destination_measure, destination.channel, destination_fraction).empty())
        throw std::logic_error("a normal note already occupies the destination");
    std::string row = make_sparse_note_row(bytes_, destination_measure, destination.channel, destination_fraction,
                                           source_hits.front().token);
    commit_normal_note_patch(Patch{{BytePatch{source_hits.front().offset, source_hits.front().token, "00"},
                                    BytePatch{bytes_.size(), {}, std::move(row)}},
                                   0,
                                   0});
}

void BmsDocument::set_initial_bpm(std::string_view decimal)
{
    const auto parsed = ratio(decimal);
    if (!parsed.has_value())
        throw std::invalid_argument("initial BPM must be a positive decimal");
    if (has_conditionals_)
        throw std::logic_error("timing edits are unavailable while conditional directives are present");
    std::optional<HeaderMatch> last;
    for (const Line line : lines(bytes_))
        if (const auto match = header_match(bytes_, line, "BPM"); match.has_value())
            last = match;
    const std::string replacement(trim(decimal));
    if (last.has_value()) {
        BytePatch patch{
            last->value_begin,
            bytes_.substr(last->value_begin, last->value_end - last->value_begin),
            replacement};
        if (last->separator_end == last->key_end) {
            patch.offset = last->key_end;
            patch.before.clear();
            patch.after = " " + replacement;
        }
        if (patch.before != patch.after)
            commit_patch(Patch{{patch}, 0, 0});
        return;
    }
    std::string appended;
    if (bytes_.size() > (bom(bytes_) ? 3 : 0) && !end_eol(bytes_))
        appended += eol(bytes_);
    appended += "#BPM " + replacement + eol(bytes_);
    commit_patch(Patch{{BytePatch{bytes_.size(), {}, std::move(appended)}}, 0, 0});
}

void BmsDocument::set_measure_ratio(int measure, std::string_view decimal)
{
    if (measure < 0 || measure > 999)
        throw std::invalid_argument("BMS measure must be in the range 0 through 999");
    if (!ratio(decimal).has_value())
        throw std::invalid_argument("measure ratio must be a positive decimal");
    if (has_conditionals_ || !chart().editable)
        throw std::logic_error("Scale measure-ratio edits require an editable chart");
    const std::string replacement(trim(decimal));
    std::optional<std::pair<std::size_t, std::size_t>> last_numeric_range;
    for (const Line line : lines(bytes_)) {
        const auto [begin, end] = bounds(bytes_, line);
        const std::string_view text = std::string_view(bytes_).substr(begin, end - begin);
        const bool is_target =
            text.size() >= 7 && text[0] == '#' && std::isdigit(static_cast<unsigned char>(text[1])) &&
            std::isdigit(static_cast<unsigned char>(text[2])) && std::isdigit(static_cast<unsigned char>(text[3])) &&
            text.substr(4, 2) == "02" && text[6] == ':' &&
            (text[1] - '0') * 100 + (text[2] - '0') * 10 + text[3] - '0' == measure;
        if (!is_target)
            continue;

        std::size_t numeric_begin = begin + 7;
        std::size_t numeric_end = line.end;
        while (numeric_begin < numeric_end && hspace(bytes_[numeric_begin]))
            ++numeric_begin;
        while (numeric_end > numeric_begin && hspace(bytes_[numeric_end - 1]))
            --numeric_end;
        last_numeric_range = {numeric_begin, numeric_end};
    }
    Patch patch{{}, 0, 0};
    if (last_numeric_range.has_value()) {
        const std::size_t numeric_begin = last_numeric_range->first;
        const std::size_t numeric_end = last_numeric_range->second;
        patch.bytes.push_back(
            {numeric_begin, bytes_.substr(numeric_begin, numeric_end - numeric_begin), replacement});
    } else {
        std::string appended;
        if (bytes_.size() > (bom(bytes_) ? 3U : 0U) && !end_eol(bytes_))
            appended += eol(bytes_);
        appended += measure_channel_prefix(measure, "02") + replacement + eol(bytes_);
        patch.bytes.push_back({bytes_.size(), {}, std::move(appended)});
    }
    if (patch.bytes.front().before == patch.bytes.front().after)
        return;

    commit_chart_edit_patch(std::move(patch));
}

void BmsDocument::apply_beat(
    const std::vector<int>& measures, std::string_view decimal, BmsBeatChangeMode mode)
{
    if (measures.empty())
        return;
    if (!ratio(decimal).has_value())
        throw std::invalid_argument("measure ratio must be a positive decimal");
    if (has_conditionals_ || !chart().editable)
        throw std::logic_error(
            chart().editable ? "Beat Apply requires an editable chart"
                             : chart().editing_reason);

    BmsDocument working = from_bytes(bytes_);
    for (const int measure : measures)
        apply_beat_one(working, measure, decimal, mode);
    const std::string after = working.serialize();
    if (after == bytes_)
        return;
    commit_chart_edit_patch(Patch{{BytePatch{0, bytes_, after}}, 0, 0});
}

void BmsDocument::insert_timing_event(
    int measure, std::string_view channel, BeatPosition fraction, std::string_view decimal)
{
    align_indexed_timing_labels();
    const std::string normalized_channel = uppercase_ascii(channel);
    validate_timing_coordinate(measure, normalized_channel, fraction);
    const bool allow_zero = normalized_channel == "09" || normalized_channel == "SC";
    const bool allow_negative = normalized_channel == "SC";
    const std::optional<BeatPosition> value = ratio(decimal, allow_zero, allow_negative);
    if (!value.has_value())
        throw std::invalid_argument(timing_decimal_error(normalized_channel));
    if (!chart().editable)
        throw std::logic_error(chart().editing_reason);
    if (!find_timing_hits(bytes_, measure, normalized_channel, fraction).empty())
        throw std::logic_error("a timing event already occupies the destination");

    const std::string normalized_decimal(trim(decimal));
    if (normalized_channel == "03") {
        if (value->denominator() != 1 || value->numerator() > 255)
            throw std::invalid_argument("channel 03 BPM must be an integer in the range 1 through 255");
        const std::size_t bpm = static_cast<std::size_t>(value->numerator());
        constexpr std::string_view hex_digits = "0123456789ABCDEF";
        const std::string token{hex_digits[bpm / 16], hex_digits[bpm % 16]};
        std::string appended = make_sparse_note_row(bytes_, measure, normalized_channel, fraction, token);
        commit_chart_edit_patch(Patch{{BytePatch{bytes_.size(), {}, std::move(appended)}}, 0, 0});
        return;
    }

    const auto write = indexed_timing_write(normalized_channel);
    const std::size_t resource_id =
        reserve_timing_resource(bytes_, write.resource_name, normalized_channel, write.x1296);
    std::string appended = timing_resource_append(
        bytes_, write.resource_name, resource_id, normalized_decimal, measure, normalized_channel, fraction,
        write.x1296);
    commit_chart_edit_patch(Patch{{BytePatch{bytes_.size(), {}, std::move(appended)}}, 0, 0});
}

void BmsDocument::replace_timing_event(
    int measure, std::string_view channel, BeatPosition fraction, std::string_view decimal)
{
    align_indexed_timing_labels();
    const std::string normalized_channel = uppercase_ascii(channel);
    validate_timing_coordinate(measure, normalized_channel, fraction);
    const bool allow_zero = normalized_channel == "09" || normalized_channel == "SC";
    const bool allow_negative = normalized_channel == "SC";
    const std::optional<BeatPosition> value = ratio(decimal, allow_zero, allow_negative);
    if (!value.has_value())
        throw std::invalid_argument(timing_decimal_error(normalized_channel));
    if (!chart().editable)
        throw std::logic_error(chart().editing_reason);

    const std::vector<Hit> hits = find_timing_hits(bytes_, measure, normalized_channel, fraction);
    if (hits.empty()) {
        insert_timing_event(measure, normalized_channel, fraction, decimal);
        return;
    }
    if (hits.size() != 1)
        throw std::logic_error("timing event source position is ambiguous");

    if (normalized_channel == "03") {
        if (value->denominator() != 1 || value->numerator() > 255)
            throw std::invalid_argument("channel 03 BPM must be an integer in the range 1 through 255");
        const std::size_t bpm = static_cast<std::size_t>(value->numerator());
        constexpr std::string_view hex_digits = "0123456789ABCDEF";
        const std::string replacement{hex_digits[bpm / 16], hex_digits[bpm % 16]};
        if (uppercase_ascii(hits.front().token) == replacement)
            return;
        commit_chart_edit_patch(Patch{{BytePatch{hits.front().offset, hits.front().token, replacement}}, 0, 0});
        return;
    }

    const std::string normalized_decimal(trim(decimal));
    if (timing().available) {
        for (const BmsTimingEvent& event : timing().events) {
            if (event.measure == measure && event.channel == normalized_channel && event.fraction == fraction &&
                event.value == *value)
                return;
        }
    }

    const auto write = indexed_timing_write(normalized_channel);
    const std::size_t resource_id =
        reserve_timing_resource(bytes_, write.resource_name, normalized_channel, write.x1296);
    std::string appended =
        timing_resource_definition_append(bytes_, write.resource_name, resource_id, normalized_decimal, write.x1296);
    Patch patch{{BytePatch{hits.front().offset, hits.front().token, indexed_token(resource_id, write.x1296)},
                 BytePatch{bytes_.size(), {}, std::move(appended)}},
                0,
                0};
    commit_chart_edit_patch(std::move(patch));
}

void BmsDocument::erase_timing_event(int measure, std::string_view channel, BeatPosition fraction)
{
    align_indexed_timing_labels();
    const std::string normalized_channel = uppercase_ascii(channel);
    validate_timing_coordinate(measure, normalized_channel, fraction);
    if (!chart().editable)
        throw std::logic_error(chart().editing_reason);
    const std::vector<Hit> hits = find_timing_hits(bytes_, measure, normalized_channel, fraction);
    if (hits.empty())
        throw std::out_of_range("no timing event exists at the requested position");
    if (hits.size() != 1)
        throw std::logic_error("timing event source position is ambiguous");
    commit_patch(Patch{{BytePatch{hits.front().offset, hits.front().token, "00"}}, 0, 0});
}

void BmsDocument::insert_long_note(
    std::string_view channel, BmsLongNotePosition start, BmsLongNotePosition end,
    std::string_view start_token, std::string_view end_token)
{
    const std::string normalized_channel = uppercase_ascii(channel);
    validate_long_note_position(start);
    validate_long_note_position(end);
    const BmsLongNotes& notes = long_notes();
    if (!notes.editable)
        throw std::logic_error(notes.editing_reason);

    const bool long_channel = is_long_note_channel(normalized_channel);
    const bool lnobj_channel = is_normal_channel(normalized_channel);
    if (!long_channel && !lnobj_channel)
        throw std::invalid_argument("long-note edits require a supported long or normal playable channel");

    std::string normalized_start_token = uppercase_ascii(start_token);
    std::string normalized_end_token = uppercase_ascii(end_token);
    if (lnobj_channel) {
        if (notes.lnobj_token.empty())
            throw std::logic_error("LNOBJ editing requires a valid #LNOBJ declaration");
        if (!normalized_end_token.empty() && normalized_end_token != notes.lnobj_token)
            throw std::invalid_argument("LNOBJ long-note ends must use the declared #LNOBJ token");
        normalized_end_token = notes.lnobj_token;
        if (normalized_start_token == notes.lnobj_token)
            throw std::invalid_argument("LNOBJ long-note starts must use an ordinary note token");
    }
    validate_long_note_tokens(normalized_start_token, normalized_end_token);

    const BmsChart& current_chart = chart();
    const BeatPosition start_beat = position_beat(current_chart, start);
    const BeatPosition end_beat = position_beat(current_chart, end);
    if (end_beat <= start_beat)
        throw std::invalid_argument("long-note end must be after its start");
    if (!find_normal_note_hits(bytes_, start.measure, normalized_channel, start.fraction).empty() ||
        !find_normal_note_hits(bytes_, end.measure, normalized_channel, end.fraction).empty())
        throw std::logic_error("a long-note endpoint collides with an existing source cell");

    const BmsLongNoteEncoding encoding =
        long_channel ? BmsLongNoteEncoding::long_channel : BmsLongNoteEncoding::lnobj;
    require_long_note_interval_clear(notes, normalized_channel, encoding, start_beat, end_beat, nullptr);
    if (lnobj_channel)
        require_lnobj_source_interval_clear(current_chart, normalized_channel, start_beat, end_beat);

    std::string appended = make_sparse_note_row(
        bytes_, start.measure, normalized_channel, start.fraction, normalized_start_token);
    std::string source_after_start(bytes_);
    source_after_start += appended;
    appended += make_sparse_note_row(
        source_after_start, end.measure, normalized_channel, end.fraction, normalized_end_token);
    std::vector<BmsLongNote> expected_notes = notes.notes;
    expected_notes.push_back(
        {normalized_channel, {start, start_beat, normalized_start_token, 0},
         {end, end_beat, normalized_end_token, 0}, encoding});
    commit_long_note_patch(Patch{{BytePatch{bytes_.size(), {}, std::move(appended)}}, 0, 0}, std::move(expected_notes));
}

void BmsDocument::move_long_note(
    std::string_view source_channel, BmsLongNotePosition source_start,
    std::string_view destination_channel, BmsLongNotePosition destination_start,
    BmsLongNotePosition destination_end)
{
    const std::string normalized_source_channel = uppercase_ascii(source_channel);
    const std::string normalized_destination_channel = uppercase_ascii(destination_channel);
    validate_long_note_position(source_start);
    validate_long_note_position(destination_start);
    validate_long_note_position(destination_end);
    const BmsLongNotes& notes = long_notes();
    if (!notes.editable)
        throw std::logic_error(notes.editing_reason);
    const BmsLongNote* note = find_long_note(notes, normalized_source_channel, source_start);
    if (note == nullptr)
        throw std::out_of_range("no unambiguous long note begins at the requested position");

    const bool source_is_long_channel = note->encoding == BmsLongNoteEncoding::long_channel;
    if ((source_is_long_channel && !is_long_note_channel(normalized_destination_channel)) ||
        (!source_is_long_channel && !is_normal_channel(normalized_destination_channel)))
        throw std::invalid_argument("long-note moves must keep their long-channel or LNOBJ channel semantics");

    const BmsChart& current_chart = chart();
    const BeatPosition destination_start_beat = position_beat(current_chart, destination_start);
    const BeatPosition destination_end_beat = position_beat(current_chart, destination_end);
    if (destination_end_beat <= destination_start_beat)
        throw std::invalid_argument("long-note end must be after its start");

    const std::vector<Hit> start_hits =
        find_normal_note_hits(bytes_, source_start.measure, normalized_source_channel, source_start.fraction);
    const std::vector<Hit> end_hits =
        find_normal_note_hits(bytes_, note->end.position.measure, normalized_source_channel, note->end.position.fraction);
    if (start_hits.size() != 1 || end_hits.size() != 1)
        throw std::logic_error("long-note endpoint source cells are ambiguous");

    const bool start_unchanged = normalized_source_channel == normalized_destination_channel &&
                                 same_position(source_start, destination_start);
    const bool end_unchanged = normalized_source_channel == normalized_destination_channel &&
                               same_position(note->end.position, destination_end);
    if (start_unchanged && end_unchanged)
        return;

    require_long_note_interval_clear(
        notes, normalized_destination_channel, note->encoding,
        destination_start_beat, destination_end_beat, note);
    if (note->encoding == BmsLongNoteEncoding::lnobj) {
        require_lnobj_source_interval_clear(
            current_chart, normalized_destination_channel, destination_start_beat, destination_end_beat,
            source_start, note->end.position);
    }

    const auto require_free_destination = [&](BmsLongNotePosition position, bool unchanged) {
        const bool source_endpoint_is_vacated =
            normalized_destination_channel == normalized_source_channel &&
            (same_position(position, source_start) || same_position(position, note->end.position));
        if (!unchanged && !source_endpoint_is_vacated &&
            !find_normal_note_hits(bytes_, position.measure, normalized_destination_channel, position.fraction).empty())
            throw std::logic_error("a long-note destination endpoint collides with an existing source cell");
    };
    require_free_destination(destination_start, start_unchanged);
    require_free_destination(destination_end, end_unchanged);

    Patch patch{{}, 0, 0};
    if (!start_unchanged)
        patch.bytes.push_back({start_hits.front().offset, start_hits.front().token, "00"});
    if (!end_unchanged)
        patch.bytes.push_back({end_hits.front().offset, end_hits.front().token, "00"});

    std::string appended;
    if (!start_unchanged) {
        std::string source_after_patch(bytes_);
        source_after_patch += appended;
        appended += make_sparse_note_row(
            source_after_patch, destination_start.measure, normalized_destination_channel,
            destination_start.fraction, start_hits.front().token);
    }
    if (!end_unchanged) {
        std::string source_after_patch(bytes_);
        source_after_patch += appended;
        appended += make_sparse_note_row(
            source_after_patch, destination_end.measure, normalized_destination_channel,
            destination_end.fraction, end_hits.front().token);
    }
    if (!appended.empty())
        patch.bytes.push_back({bytes_.size(), {}, std::move(appended)});
    std::sort(patch.bytes.begin(), patch.bytes.end(),
              [](const BytePatch& left, const BytePatch& right) { return left.offset < right.offset; });
    std::vector<BmsLongNote> expected_notes = notes.notes;
    for (BmsLongNote& expected : expected_notes) {
        if (same_long_note_semantics(expected, *note)) {
            expected.channel = normalized_destination_channel;
            expected.start.position = destination_start;
            expected.start.beat = destination_start_beat;
            expected.start.token = uppercase_ascii(start_hits.front().token);
            expected.end.position = destination_end;
            expected.end.beat = destination_end_beat;
            expected.end.token = uppercase_ascii(end_hits.front().token);
            break;
        }
    }
    commit_long_note_patch(std::move(patch), std::move(expected_notes));
}

void BmsDocument::resize_long_note(
    std::string_view channel, BmsLongNotePosition start, BmsLongNotePosition end)
{
    const std::string normalized_channel = uppercase_ascii(channel);
    validate_long_note_position(start);
    validate_long_note_position(end);
    const BmsLongNotes& notes = long_notes();
    if (!notes.editable)
        throw std::logic_error(notes.editing_reason);
    const BmsLongNote* note = find_long_note(notes, normalized_channel, start);
    if (note == nullptr)
        throw std::out_of_range("no unambiguous long note begins at the requested position");
    if (same_position(note->end.position, end))
        return;
    const BmsChart& current_chart = chart();
    const BeatPosition end_beat = position_beat(current_chart, end);
    if (end_beat <= note->start.beat)
        throw std::invalid_argument("long-note end must be after its start");
    if (!find_normal_note_hits(bytes_, end.measure, normalized_channel, end.fraction).empty())
        throw std::logic_error("a long-note destination endpoint collides with an existing source cell");

    require_long_note_interval_clear(notes, normalized_channel, note->encoding, note->start.beat, end_beat, note);
    if (note->encoding == BmsLongNoteEncoding::lnobj) {
        require_lnobj_source_interval_clear(
            current_chart, normalized_channel, note->start.beat, end_beat, start, note->end.position);
    }

    const std::vector<Hit> old_end_hits =
        find_normal_note_hits(bytes_, note->end.position.measure, normalized_channel, note->end.position.fraction);
    if (old_end_hits.size() != 1)
        throw std::logic_error("long-note end source cell is ambiguous");
    std::string appended = make_sparse_note_row(
        bytes_, end.measure, normalized_channel, end.fraction, old_end_hits.front().token);
    std::vector<BmsLongNote> expected_notes = notes.notes;
    for (BmsLongNote& expected : expected_notes) {
        if (same_long_note_semantics(expected, *note)) {
            expected.end.position = end;
            expected.end.beat = end_beat;
            expected.end.token = uppercase_ascii(old_end_hits.front().token);
            break;
        }
    }
    commit_long_note_patch(Patch{{BytePatch{old_end_hits.front().offset, old_end_hits.front().token, "00"},
                                        BytePatch{bytes_.size(), {}, std::move(appended)}},
                                       0,
                                       0},
                           std::move(expected_notes));
}

void BmsDocument::erase_long_note(std::string_view channel, BmsLongNotePosition start)
{
    const std::string normalized_channel = uppercase_ascii(channel);
    validate_long_note_position(start);
    const BmsLongNotes& notes = long_notes();
    if (!notes.editable)
        throw std::logic_error(notes.editing_reason);
    const BmsLongNote* note = find_long_note(notes, normalized_channel, start);
    if (note == nullptr)
        throw std::out_of_range("no unambiguous long note begins at the requested position");
    const std::vector<Hit> start_hits =
        find_normal_note_hits(bytes_, start.measure, normalized_channel, start.fraction);
    const std::vector<Hit> end_hits =
        find_normal_note_hits(bytes_, note->end.position.measure, normalized_channel, note->end.position.fraction);
    if (start_hits.size() != 1 || end_hits.size() != 1)
        throw std::logic_error("long-note endpoint source cells are ambiguous");
    Patch patch{{BytePatch{start_hits.front().offset, start_hits.front().token, "00"},
                 BytePatch{end_hits.front().offset, end_hits.front().token, "00"}},
                0,
                0};
    std::sort(patch.bytes.begin(), patch.bytes.end(),
              [](const BytePatch& left, const BytePatch& right) { return left.offset < right.offset; });
    std::vector<BmsLongNote> expected_notes;
    for (const BmsLongNote& existing : notes.notes)
        if (!same_long_note_semantics(existing, *note))
            expected_notes.push_back(existing);
    commit_long_note_patch(std::move(patch), std::move(expected_notes));
}

void BmsDocument::begin_compound()
{
    if (compounding_)
        throw std::logic_error("a compound edit is already open");
    compounding_ = true;
    compound_before_ = bytes_;
}

void BmsDocument::end_compound()
{
    if (!compounding_)
        throw std::logic_error("no compound edit is open");
    compounding_ = false;
    std::string before = std::move(compound_before_);
    compound_before_.clear();
    if (before == bytes_)
        return;
    if (next_revision_ == std::numeric_limits<std::size_t>::max())
        throw std::overflow_error("BMS document history revision overflow");
    Patch patch;
    patch.bytes.push_back(BytePatch{0, std::move(before), bytes_});
    patch.before_revision = current_revision_;
    patch.after_revision = next_revision_;
    undo_.reserve(undo_.size() + 1);
    undo_.push_back(std::move(patch));
    redo_.clear();
    current_revision_ = undo_.back().after_revision;
    ++next_revision_;
    chart_revision_ = static_cast<std::size_t>(-1);
    timing_revision_ = static_cast<std::size_t>(-1);
    long_note_revision_ = static_cast<std::size_t>(-1);
}

void BmsDocument::abort_compound()
{
    if (!compounding_)
        return;
    bytes_ = std::move(compound_before_);
    compound_before_.clear();
    compounding_ = false;
    has_conditionals_ = conditional(bytes_);
    chart_revision_ = static_cast<std::size_t>(-1);
    timing_revision_ = static_cast<std::size_t>(-1);
    long_note_revision_ = static_cast<std::size_t>(-1);
}

bool BmsDocument::compounding() const noexcept
{
    return compounding_;
}

bool BmsDocument::undo()
{
    if (compounding_)
        throw std::logic_error("finish the compound edit before undo");
    if (undo_.empty())
        return false;
    auto u = apply_patch_bytes(bytes_, undo_.back(), false);
    redo_.reserve(redo_.size() + 1);
    redo_.push_back(std::move(undo_.back()));
    bytes_ = std::move(u);
    has_conditionals_ = conditional(bytes_);
    current_revision_ = redo_.back().before_revision;
    undo_.pop_back();
    chart_revision_ = static_cast<std::size_t>(-1);
    timing_revision_ = static_cast<std::size_t>(-1);
    long_note_revision_ = static_cast<std::size_t>(-1);
    return true;
}

bool BmsDocument::redo()
{
    if (compounding_)
        throw std::logic_error("finish the compound edit before redo");
    if (redo_.empty())
        return false;
    auto u = apply_patch_bytes(bytes_, redo_.back(), true);
    undo_.reserve(undo_.size() + 1);
    undo_.push_back(std::move(redo_.back()));
    bytes_ = std::move(u);
    has_conditionals_ = conditional(bytes_);
    current_revision_ = undo_.back().after_revision;
    redo_.pop_back();
    chart_revision_ = static_cast<std::size_t>(-1);
    timing_revision_ = static_cast<std::size_t>(-1);
    long_note_revision_ = static_cast<std::size_t>(-1);
    return true;
}

bool BmsDocument::can_undo() const noexcept
{
    return !undo_.empty();
}

bool BmsDocument::can_redo() const noexcept
{
    return !redo_.empty();
}

bool BmsDocument::dirty() const noexcept
{
    return current_revision_ != saved_revision_;
}

bool BmsDocument::has_conditionals() const noexcept
{
    return has_conditionals_;
}

void BmsDocument::mark_saved() noexcept
{
    saved_revision_ = current_revision_;
}

void BmsDocument::discard_history() noexcept
{
    abort_compound();
    undo_.clear();
    redo_.clear();
}

std::size_t BmsDocument::line_count() const noexcept
{
    if (bytes_.empty())
        return 0;

    std::size_t count = 0;

    for (std::size_t position = 0; position < bytes_.size();) {
        ++count;

        while (position < bytes_.size() && bytes_[position] != '\r' && bytes_[position] != '\n')
            ++position;

        if (position < bytes_.size() && bytes_[position] == '\r' && position + 1 < bytes_.size() &&
            bytes_[position + 1] == '\n')
            position += 2;

        else if (position < bytes_.size())
            ++position;
    }

    return count;
}

} // namespace ibms
  // namespace ibms
