#include <ibms/bmson_from_bms.hpp>

#include <ibms/bms_document.hpp>

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ibms {
namespace {

constexpr int k_wav_slots = 36 * 36;
constexpr int k_default_rank = 2;

int zz_digit(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'A' && c <= 'Z') {
        return c - 'A' + 10;
    }
    if (c >= 'a' && c <= 'z') {
        return c - 'a' + 10;
    }
    return -1;
}

int zz_to_int(std::string_view text)
{
    if (text.size() < 2) {
        return -1;
    }
    const int high = zz_digit(text[0]);
    const int low = zz_digit(text[1]);
    if (high < 0 || low < 0) {
        return -1;
    }
    return high * 36 + low;
}

std::string_view trim(std::string_view text)
{
    while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) {
        text.remove_prefix(1);
    }
    while (!text.empty() && (text.back() == ' ' || text.back() == '\t' || text.back() == '\r')) {
        text.remove_suffix(1);
    }
    return text;
}

std::string ascii_upper(std::string_view text)
{
    std::string out(text);
    for (char& c : out) {
        if (c >= 'a' && c <= 'z') {
            c = static_cast<char>(c - 'a' + 'A');
        }
    }
    return out;
}

std::int64_t pulse_from_beat(const BeatPosition& beat, int resolution)
{
    const double value = (static_cast<double>(beat.numerator()) / static_cast<double>(beat.denominator()))
        * static_cast<double>(resolution);
    return static_cast<std::int64_t>(std::llround(value));
}

std::int64_t lane_for_offset(int offset, BmsonBmsMode mode)
{
    switch (mode) {
    case BmsonBmsMode::mode_5k:
        if (offset >= 1 && offset <= 5) {
            return offset;
        }
        if (offset == 6) {
            return 8;
        }
        return 0;
    case BmsonBmsMode::mode_7k:
        if (offset >= 1 && offset <= 5) {
            return offset;
        }
        if (offset == 6) {
            return 8;
        }
        if (offset == 8) {
            return 6;
        }
        if (offset == 9) {
            return 7;
        }
        return 0;
    case BmsonBmsMode::mode_10k:
        if (offset >= 1 && offset <= 5) {
            return offset;
        }
        if (offset >= 37 && offset <= 41) {
            return 8 + (offset - 36);
        }
        if (offset == 6) {
            return 8;
        }
        if (offset == 42) {
            return 16;
        }
        return 0;
    case BmsonBmsMode::mode_14k:
        if (offset >= 1 && offset <= 5) {
            return offset;
        }
        if (offset >= 37 && offset <= 41) {
            return 8 + (offset - 36);
        }
        if (offset == 6) {
            return 8;
        }
        if (offset == 8) {
            return 6;
        }
        if (offset == 9) {
            return 7;
        }
        if (offset == 42) {
            return 16;
        }
        if (offset == 44) {
            return 14;
        }
        if (offset == 45) {
            return 15;
        }
        return 0;
    case BmsonBmsMode::mode_pms_9k:
        if (offset >= 1 && offset <= 5) {
            return offset;
        }
        if (offset == 38) {
            return 6;
        }
        if (offset == 39) {
            return 7;
        }
        if (offset == 40) {
            return 8;
        }
        if (offset == 41) {
            return 9;
        }
        return 0;
    case BmsonBmsMode::mode_pms_5k:
        if (offset == 3) {
            return 1;
        }
        if (offset == 4) {
            return 2;
        }
        if (offset == 5) {
            return 3;
        }
        if (offset == 38) {
            return 4;
        }
        if (offset == 39) {
            return 5;
        }
        return 0;
    }
    return 0;
}

int play_offset_for_channel(int zz)
{
    const int from_10 = zz - zz_to_int("10");
    const int from_30 = zz - zz_to_int("30");
    const int from_50 = zz - zz_to_int("50");
    const int from_d0 = zz - zz_to_int("D0");
    if (zz >= zz_to_int("11") && zz <= zz_to_int("2Z")) {
        return from_10;
    }
    if (zz >= zz_to_int("31") && zz <= zz_to_int("4Z")) {
        return from_30;
    }
    if (zz >= zz_to_int("51") && zz <= zz_to_int("6Z")) {
        return from_50;
    }
    if (zz >= zz_to_int("D1") && zz <= zz_to_int("EZ")) {
        return from_d0;
    }
    return -1;
}

bool channel_line_has_object(std::string_view data)
{
    for (std::size_t index = 0; index + 1 < data.size(); index += 2) {
        const std::string_view token = data.substr(index, 2);
        if (token != "00" && token != "\r" && token != "\n") {
            return true;
        }
    }
    return false;
}

std::array<bool, 72> collect_play_channels(std::string_view bytes)
{
    std::array<bool, 72> used{};
    std::size_t cursor = 0;
    while (cursor < bytes.size()) {
        std::size_t end = bytes.find_first_of("\r\n", cursor);
        if (end == std::string_view::npos) {
            end = bytes.size();
        }
        const std::string_view line = trim(bytes.substr(cursor, end - cursor));
        if (end < bytes.size() && bytes[end] == '\r' && end + 1 < bytes.size() && bytes[end + 1] == '\n') {
            cursor = end + 2;
        } else {
            cursor = end + (end < bytes.size() ? 1 : 0);
        }
        if (line.size() < 8 || line.front() != '#') {
            continue;
        }
        if (!std::isdigit(static_cast<unsigned char>(line[1]))
            || !std::isdigit(static_cast<unsigned char>(line[2]))
            || !std::isdigit(static_cast<unsigned char>(line[3]))
            || line[6] != ':') {
            continue;
        }
        const int zz = zz_to_int(line.substr(4, 2));
        const int offset = play_offset_for_channel(zz);
        if (offset < 0 || offset >= 72 || !channel_line_has_object(line.substr(7))) {
            continue;
        }
        used[static_cast<std::size_t>(offset)] = true;
    }
    return used;
}

std::set<int> allowed_offsets(BmsonBmsMode mode)
{
    switch (mode) {
    case BmsonBmsMode::mode_5k:
        return {1, 2, 3, 4, 5, 6, 7};
    case BmsonBmsMode::mode_7k:
        return {1, 2, 3, 4, 5, 6, 7, 8, 9};
    case BmsonBmsMode::mode_10k:
        return {1, 2, 3, 4, 5, 6, 7, 37, 38, 39, 40, 41, 42, 43};
    case BmsonBmsMode::mode_14k:
        return {1, 2, 3, 4, 5, 6, 7, 8, 9, 37, 38, 39, 40, 41, 42, 43, 44, 45};
    case BmsonBmsMode::mode_pms_9k:
        return {1, 2, 3, 4, 5, 38, 39, 40, 41};
    case BmsonBmsMode::mode_pms_5k:
        return {3, 4, 5, 38, 39};
    }
    return {};
}

bool unused(const std::array<bool, 72>& used, std::initializer_list<int> offsets)
{
    for (int offset : offsets) {
        if (offset >= 0 && offset < 72 && used[static_cast<std::size_t>(offset)]) {
            return false;
        }
    }
    return true;
}

std::string path_suffix(std::string_view path)
{
    const std::size_t slash = path.find_last_of("/\\");
    const std::string_view name = slash == std::string_view::npos ? path : path.substr(slash + 1);
    const std::size_t dot = name.find_last_of('.');
    if (dot == std::string_view::npos) {
        return {};
    }
    return ascii_upper(name.substr(dot + 1));
}

BmsonBmsMode detect_mode(
    const std::array<bool, 72>& used, int player, const BmsonFromBmsOptions& options)
{
    if (!options.ignore_extension && path_suffix(options.path) == "PMS") {
        if (!options.prefer_ex_modes && unused(used, {1, 2, 40, 41})) {
            return BmsonBmsMode::mode_pms_5k;
        }
        return BmsonBmsMode::mode_pms_9k;
    }
    bool player1 = player == 1;
    if (!options.trust_player_command && player1) {
        for (int index = 36; index < 72; ++index) {
            if (used[static_cast<std::size_t>(index)]) {
                player1 = false;
                break;
            }
        }
    }
    if (player1) {
        if (!options.prefer_ex_modes && unused(used, {8, 9})) {
            return BmsonBmsMode::mode_5k;
        }
        return BmsonBmsMode::mode_7k;
    }
    if (!options.prefer_ex_modes && unused(used, {8, 9, 44, 45})) {
        return BmsonBmsMode::mode_10k;
    }
    return BmsonBmsMode::mode_14k;
}

int64_t lane_from_channel(std::string_view channel, BmsonBmsMode mode)
{
    const std::string key = ascii_upper(channel);
    const int zz = zz_to_int(key);
    if (zz < 0) {
        return 0;
    }
    const int as_normal = zz - zz_to_int("10");
    const int as_long = zz - zz_to_int("50");
    if (key.size() >= 2 && (key[0] == '1' || key[0] == '2')) {
        return lane_for_offset(as_normal, mode);
    }
    if (key.size() >= 2 && (key[0] == '5' || key[0] == '6')) {
        return lane_for_offset(as_long, mode);
    }
    return 0;
}

double judge_rank_from_bms(int rank)
{
    switch (rank) {
    case 0:
        return 40.0;
    case 1:
        return 60.0;
    case 2:
        return 80.0;
    case 3:
        return 100.0;
    case 4:
        return 120.0;
    default:
        return 80.0;
    }
}

int parse_int(std::string_view text, int fallback)
{
    if (text.empty()) {
        return fallback;
    }
    const std::string owned(text);
    char* end = nullptr;
    const long value = std::strtol(owned.c_str(), &end, 10);
    if (end == owned.c_str()) {
        return fallback;
    }
    return static_cast<int>(value);
}

double parse_real(std::string_view text, double fallback)
{
    if (text.empty()) {
        return fallback;
    }
    const std::string owned(text);
    char* end = nullptr;
    const double value = std::strtod(owned.c_str(), &end);
    if (end == owned.c_str()) {
        return fallback;
    }
    return value;
}

struct HeaderDefs {
    std::array<std::string, k_wav_slots> wav{};
    std::array<std::string, k_wav_slots> bmp{};
    std::array<double, k_wav_slots> bpm{};
    std::array<double, k_wav_slots> stop{};
    std::array<bool, k_wav_slots> has_bpm{};
    std::array<bool, k_wav_slots> has_stop{};
    int lnobj = -1;
    int player = 1;
    std::string title;
    std::string subtitle;
    std::string artist;
    std::string subartist;
    std::string genre;
    double init_bpm = 120.0;
    int rank = k_default_rank;
    int level = 0;
};

void apply_header_line(HeaderDefs& defs, std::string_view line)
{
    line = trim(line);
    if (line.empty() || line.front() != '#') {
        return;
    }
    if (line.size() >= 7 && line[6] == ':') {
        return;
    }
    const std::size_t split = line.find_first_of(" \t");
    const std::string_view raw_key = split == std::string_view::npos ? line.substr(1) : line.substr(1, split - 1);
    const std::string_view value = split == std::string_view::npos ? std::string_view{} : trim(line.substr(split + 1));
    const std::string key = ascii_upper(trim(raw_key));
    if (key == "TITLE") {
        defs.title = std::string(value);
    } else if (key == "SUBTITLE") {
        defs.subtitle = std::string(value);
    } else if (key == "ARTIST") {
        defs.artist = std::string(value);
    } else if (key == "SUBARTIST") {
        defs.subartist = std::string(value);
    } else if (key == "GENRE") {
        defs.genre = std::string(value);
    } else if (key == "BPM") {
        defs.init_bpm = parse_real(value, defs.init_bpm);
    } else if (key == "RANK") {
        defs.rank = parse_int(value, defs.rank);
    } else if (key == "PLAYER") {
        defs.player = parse_int(value, defs.player);
    } else if (key == "PLAYLEVEL") {
        defs.level = parse_int(value, defs.level);
    } else if (key == "LNOBJ") {
        const int token = zz_to_int(value);
        if (token >= 0) {
            defs.lnobj = token;
        }
    } else if (key.size() >= 5 && key.substr(0, 3) == "WAV") {
        const int index = zz_to_int(key.substr(key.size() - 2, 2));
        if (index >= 0 && index < k_wav_slots) {
            defs.wav[static_cast<std::size_t>(index)] = std::string(value);
        }
    } else if (key.size() >= 5 && key.substr(0, 3) == "BMP") {
        const int index = zz_to_int(key.substr(key.size() - 2, 2));
        if (index >= 0 && index < k_wav_slots) {
            defs.bmp[static_cast<std::size_t>(index)] = std::string(value);
        }
    } else if (key.size() >= 5 && key.substr(0, 3) == "BPM") {
        const int index = zz_to_int(key.substr(key.size() - 2, 2));
        if (index >= 0 && index < k_wav_slots) {
            defs.bpm[static_cast<std::size_t>(index)] = parse_real(value, 120.0);
            defs.has_bpm[static_cast<std::size_t>(index)] = true;
        }
    } else if (key.size() >= 6 && key.substr(0, 4) == "STOP") {
        const int index = zz_to_int(key.substr(key.size() - 2, 2));
        if (index >= 0 && index < k_wav_slots) {
            defs.stop[static_cast<std::size_t>(index)] = parse_real(value, 0.0);
            defs.has_stop[static_cast<std::size_t>(index)] = true;
        }
    }
}

HeaderDefs parse_header_defs(std::string_view bytes)
{
    HeaderDefs defs;
    std::size_t cursor = 0;
    while (cursor < bytes.size()) {
        std::size_t end = bytes.find_first_of("\r\n", cursor);
        if (end == std::string_view::npos) {
            end = bytes.size();
        }
        apply_header_line(defs, bytes.substr(cursor, end - cursor));
        if (end < bytes.size() && bytes[end] == '\r' && end + 1 < bytes.size() && bytes[end + 1] == '\n') {
            cursor = end + 2;
        } else {
            cursor = end + (end < bytes.size() ? 1 : 0);
        }
    }
    return defs;
}

int zz_num_to_ff_num(int zz)
{
    const int high = zz / 36;
    const int low = zz % 36;
    if (high >= 16 || low >= 16) {
        return -1;
    }
    return high * 16 + low;
}

struct LanePlayingState {
    std::int64_t y = 0;
    int wav = 0;
};

int wav_index(std::string_view token)
{
    return zz_to_int(token);
}

void put_note(std::array<std::map<std::int64_t, BmsonNote>, k_wav_slots>& notes, int wav, BmsonNote note)
{
    if (wav < 0 || wav >= k_wav_slots) {
        return;
    }
    notes[static_cast<std::size_t>(wav)][note.y] = note;
}

std::optional<BmsonNote> take_note(
    std::array<std::map<std::int64_t, BmsonNote>, k_wav_slots>& notes, int wav, std::int64_t y)
{
    if (wav < 0 || wav >= k_wav_slots) {
        return std::nullopt;
    }
    auto& slot = notes[static_cast<std::size_t>(wav)];
    const auto found = slot.find(y);
    if (found == slot.end()) {
        return std::nullopt;
    }
    BmsonNote note = found->second;
    return note;
}

int event_rank(const BmsEvent& event)
{
    switch (event.kind) {
    case BmsEventKind::bgm:
        return 0;
    case BmsEventKind::normal_note:
        return 1;
    case BmsEventKind::long_note:
        return 2;
    default:
        return 9;
    }
}

}  // namespace

BmsonBmsMode detect_bmson_bms_mode(const BmsDocument& bms, const BmsonFromBmsOptions& options)
{
    const HeaderDefs defs = parse_header_defs(bms.serialize());
    return detect_mode(collect_play_channels(bms.serialize()), defs.player, options);
}

std::string_view bmson_mode_hint(BmsonBmsMode mode)
{
    switch (mode) {
    case BmsonBmsMode::mode_5k:
        return "beat-5k";
    case BmsonBmsMode::mode_7k:
        return "beat-7k";
    case BmsonBmsMode::mode_10k:
        return "beat-10k";
    case BmsonBmsMode::mode_14k:
        return "beat-14k";
    case BmsonBmsMode::mode_pms_9k:
        return "popn-9k";
    case BmsonBmsMode::mode_pms_5k:
        return "popn-5k";
    }
    return "beat-7k";
}

std::string_view bmson_mode_long_name(BmsonBmsMode mode)
{
    switch (mode) {
    case BmsonBmsMode::mode_5k:
        return "5key (BMS)";
    case BmsonBmsMode::mode_7k:
        return "7key (BMS)";
    case BmsonBmsMode::mode_10k:
        return "10key (BMS)";
    case BmsonBmsMode::mode_14k:
        return "14key (BMS)";
    case BmsonBmsMode::mode_pms_9k:
        return "9key (PMS)";
    case BmsonBmsMode::mode_pms_5k:
        return "5key (PMS)";
    }
    return "";
}

std::int64_t bmson_lane_x(std::string_view channel, BmsonBmsMode mode)
{
    return lane_from_channel(channel, mode);
}

std::int64_t bmson_lane_x_mode_7k(std::string_view channel)
{
    return lane_from_channel(channel, BmsonBmsMode::mode_7k);
}

std::vector<int> bmson_mode_error_offsets(const BmsDocument& bms, BmsonBmsMode mode)
{
    const auto used = collect_play_channels(bms.serialize());
    const auto allowed = allowed_offsets(mode);
    std::vector<int> errors;
    for (int index = 0; index < 72; ++index) {
        if (used[static_cast<std::size_t>(index)] && allowed.count(index) == 0) {
            errors.push_back(index);
        }
    }
    return errors;
}

BmsonDocument bmson_from_bms(const BmsDocument& bms, const BmsonFromBmsOptions& options)
{
    const int resolution = options.resolution > 0 ? options.resolution : 240;
    const HeaderDefs defs = parse_header_defs(bms.serialize());
    const BmsChart& chart = bms.chart();
    const BmsonBmsMode mode = options.mode.value_or(
        detect_mode(collect_play_channels(bms.serialize()), defs.player, options));

    BmsonDocument document = BmsonDocument::empty();
    BmsonInfo info = document.info();
    info.title = defs.title;
    info.subtitle = defs.subtitle;
    info.artist = defs.artist;
    info.genre = defs.genre;
    info.subartists.clear();
    if (!defs.subartist.empty()) {
        info.subartists.push_back(defs.subartist);
    }
    info.mode_hint = std::string(bmson_mode_hint(mode));
    info.init_bpm = defs.init_bpm;
    info.judge_rank = judge_rank_from_bms(defs.rank);
    info.level = defs.level;
    info.resolution = resolution;
    document.replace_info(std::move(info));

    std::vector<const BmsEvent*> ordered;
    ordered.reserve(chart.events.size());
    for (const BmsEvent& event : chart.events) {
        if (event.kind == BmsEventKind::bgm || event.kind == BmsEventKind::normal_note
            || event.kind == BmsEventKind::long_note) {
            ordered.push_back(&event);
        }
    }
    std::stable_sort(ordered.begin(), ordered.end(), [](const BmsEvent* left, const BmsEvent* right) {
        if (left->measure != right->measure) {
            return left->measure < right->measure;
        }
        const int left_rank = event_rank(*left);
        const int right_rank = event_rank(*right);
        if (left_rank != right_rank) {
            return left_rank < right_rank;
        }
        const int left_zz = zz_to_int(left->channel);
        const int right_zz = zz_to_int(right->channel);
        if (left_zz != right_zz) {
            return left_zz < right_zz;
        }
        if (left->fraction != right->fraction) {
            return left->fraction < right->fraction;
        }
        return left->source_line < right->source_line;
    });

    std::array<std::map<std::int64_t, BmsonNote>, k_wav_slots> notes_by_wav;
    std::map<std::int64_t, LanePlayingState> lane_normal;
    std::map<std::int64_t, LanePlayingState> lane_long;
    int last_used_measure = -1;

    for (const BmsEvent* event : ordered) {
        const int wav = wav_index(event->token);
        if (wav < 0) {
            continue;
        }
        const std::int64_t y = pulse_from_beat(event->beat, resolution);
        last_used_measure = std::max(last_used_measure, event->measure);

        if (event->kind == BmsEventKind::bgm) {
            put_note(notes_by_wav, wav, BmsonNote{0, y, 0, false});
            continue;
        }

        const std::int64_t lane = lane_from_channel(event->channel, mode);
        if (event->kind == BmsEventKind::normal_note) {
            if (defs.lnobj >= 0 && wav == defs.lnobj) {
                if (lane != 0) {
                    const auto found = lane_normal.find(lane);
                    if (found != lane_normal.end()) {
                        if (auto note = take_note(notes_by_wav, found->second.wav, found->second.y)) {
                            note->l = y - note->y;
                            put_note(notes_by_wav, found->second.wav, *note);
                        }
                        lane_normal.erase(found);
                    }
                }
                continue;
            }
            put_note(notes_by_wav, wav, BmsonNote{lane, y, 0, false});
            if (lane != 0) {
                lane_normal[lane] = LanePlayingState{y, wav};
            }
            continue;
        }

        if (lane != 0) {
            const auto found = lane_long.find(lane);
            if (found != lane_long.end()) {
                if (auto note = take_note(notes_by_wav, found->second.wav, found->second.y)) {
                    note->l = y - note->y;
                    put_note(notes_by_wav, found->second.wav, *note);
                }
                lane_long.erase(found);
            } else {
                put_note(notes_by_wav, wav, BmsonNote{lane, y, 0, false});
                lane_long[lane] = LanePlayingState{y, wav};
            }
        } else {
            put_note(notes_by_wav, wav, BmsonNote{0, y, 0, false});
        }
    }

    std::vector<BmsonBpmNote> bpm_notes;
    std::vector<BmsonStopNote> stop_notes;
    for (const BmsEvent& event : chart.events) {
        const std::int64_t y = pulse_from_beat(event.beat, resolution);
        if (event.kind == BmsEventKind::bpm) {
            const int ff = zz_num_to_ff_num(zz_to_int(event.token));
            if (ff > 0) {
                bpm_notes.push_back(BmsonBpmNote{y, static_cast<double>(ff)});
            }
        } else if (event.kind == BmsEventKind::extended_bpm) {
            const int index = zz_to_int(event.token);
            if (index >= 0 && index < k_wav_slots && defs.has_bpm[static_cast<std::size_t>(index)]
                && defs.bpm[static_cast<std::size_t>(index)] > 0.0) {
                bpm_notes.push_back(BmsonBpmNote{y, defs.bpm[static_cast<std::size_t>(index)]});
            }
        } else if (event.kind == BmsEventKind::stop) {
            const int index = zz_to_int(event.token);
            if (index >= 0 && index < k_wav_slots && defs.has_stop[static_cast<std::size_t>(index)]
                && defs.stop[static_cast<std::size_t>(index)] > 0.0) {
                const double pulses = std::llround(
                    static_cast<double>(resolution) * defs.stop[static_cast<std::size_t>(index)] / 48.0);
                stop_notes.push_back(BmsonStopNote{y, pulses});
            }
        }
    }
    document.replace_bpm_notes(std::move(bpm_notes));
    document.replace_stop_notes(std::move(stop_notes));

    std::map<std::int64_t, BmsonBgaEvent> imported_bga;
    std::map<std::int64_t, BmsonBgaEvent> imported_layer;
    std::map<std::int64_t, BmsonBgaEvent> imported_poor;
    for (const BmsEvent& event : chart.events) {
        if (event.kind != BmsEventKind::bga) {
            continue;
        }
        const int id = zz_to_int(event.token);
        if (id <= 0) {
            continue;
        }
        const std::int64_t y = pulse_from_beat(event.beat, resolution);
        const BmsonBgaEvent written{y, id};
        if (event.channel == "07") {
            imported_layer[y] = written;
        } else if (event.channel == "06") {
            imported_poor[y] = written;
        } else if (event.channel == "04") {
            imported_bga[y] = written;
        }
    }
    if (imported_poor.find(0) == imported_poor.end() && !defs.bmp[0].empty()) {
        imported_poor[0] = BmsonBgaEvent{0, 0};
    }
    std::array<bool, k_wav_slots> bmp_used{};
    auto mark_used = [&](const std::map<std::int64_t, BmsonBgaEvent>& events) {
        for (const auto& [_, event] : events) {
            if (event.id >= 0 && event.id < k_wav_slots) {
                bmp_used[static_cast<std::size_t>(event.id)] = true;
            }
        }
    };
    mark_used(imported_bga);
    mark_used(imported_layer);
    mark_used(imported_poor);
    std::vector<BmsonBgaHeader> headers;
    for (int index = 0; index < k_wav_slots; ++index) {
        const std::string& name = defs.bmp[static_cast<std::size_t>(index)];
        if (bmp_used[static_cast<std::size_t>(index)] || !name.empty()) {
            headers.push_back(BmsonBgaHeader{index, name});
        }
    }
    std::vector<BmsonBgaEvent> bga_events;
    std::vector<BmsonBgaEvent> layer_events;
    std::vector<BmsonBgaEvent> poor_events;
    for (const auto& [_, event] : imported_bga) {
        bga_events.push_back(event);
    }
    for (const auto& [_, event] : imported_layer) {
        layer_events.push_back(event);
    }
    for (const auto& [_, event] : imported_poor) {
        poor_events.push_back(event);
    }
    if (!headers.empty() || !bga_events.empty() || !layer_events.empty() || !poor_events.empty()) {
        document.replace_bga(
            std::move(headers), std::move(bga_events), std::move(layer_events), std::move(poor_events));
    }

    std::int64_t last_object_pulse = 0;
    if (last_used_measure >= 0 && last_used_measure < static_cast<int>(chart.measures.size())) {
        const BmsMeasure& measure = chart.measures[static_cast<std::size_t>(last_used_measure)];
        last_object_pulse = pulse_from_beat(measure.start + measure.length, resolution);
    }
    std::vector<BmsonBarLine> lines;
    lines.push_back(BmsonBarLine{0});
    std::int64_t pos = 0;
    for (std::size_t index = 0; index < chart.measures.size() && pos <= last_object_pulse; ++index) {
        pos = pulse_from_beat(chart.measures[index].start + chart.measures[index].length, resolution);
        lines.push_back(BmsonBarLine{pos});
    }
    document.replace_lines(std::move(lines));

    std::vector<BmsonSoundChannel> channels;
    for (int index = 0; index < k_wav_slots; ++index) {
        const std::string& name = defs.wav[static_cast<std::size_t>(index)];
        const auto& notes = notes_by_wav[static_cast<std::size_t>(index)];
        if (name.empty() && notes.empty()) {
            continue;
        }
        BmsonSoundChannel channel;
        channel.name = name;
        channel.notes.reserve(notes.size());
        for (const auto& [_, note] : notes) {
            channel.notes.push_back(note);
        }
        channels.push_back(std::move(channel));
    }
    document.replace_sound_channels(std::move(channels));
    return document;
}

}  // namespace ibms
