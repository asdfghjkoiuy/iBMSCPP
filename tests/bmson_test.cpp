#include <ibms/bmson.hpp>

#include <cmath>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

int failures = 0;

void expect(bool condition, std::string_view expression)
{
    if (!condition) {
        std::cerr << "Expectation failed: " << expression << '\n';
        ++failures;
    }
}

void expect_near(double actual, double expected, std::string_view expression)
{
    expect(std::isfinite(actual) && std::abs(actual - expected) < 1e-9, expression);
}

template <typename Exception, typename Operation>
void expect_throws(Operation&& operation, std::string_view expression)
{
    try {
        operation();
        std::cerr << "Expected exception was not thrown: " << expression << '\n';
        ++failures;
    } catch (const Exception&) {
    } catch (const std::exception& exception) {
        std::cerr << "Unexpected exception for " << expression << ": " << exception.what() << '\n';
        ++failures;
    }
}

[[nodiscard]] std::string load_fixture(std::string_view filename)
{
    const std::filesystem::path path = std::filesystem::path{IBMS_BMSON_FIXTURE_DIR} / filename;
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("unable to open BMSON fixture: " + path.string());
    }
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}

[[nodiscard]] bool json_has_string(std::string_view json, std::string_view key, std::string_view value)
{
    const std::string needle = "\"" + std::string(key) + "\": \"" + std::string(value) + "\"";
    const std::string compact = "\"" + std::string(key) + "\":\"" + std::string(value) + "\"";
    return json.find(needle) != std::string_view::npos || json.find(compact) != std::string_view::npos;
}

[[nodiscard]] bool json_has_key(std::string_view json, std::string_view key)
{
    const std::string needle = "\"" + std::string(key) + "\"";
    return json.find(needle) != std::string_view::npos;
}

[[nodiscard]] bool json_has_number(std::string_view json, std::string_view key, std::string_view value)
{
    const std::string pretty = "\"" + std::string(key) + "\": " + std::string(value);
    const std::string compact = "\"" + std::string(key) + "\":" + std::string(value);
    return json.find(pretty) != std::string_view::npos || json.find(compact) != std::string_view::npos;
}

void empty_document_uses_bmsone_defaults()
{
    const auto document = ibms::BmsonDocument::empty();
    expect(document.version() == "1.0.0", "empty version is 1.0.0");
    expect(document.info().title.empty(), "empty title");
    expect(document.info().subtitle.empty(), "empty subtitle");
    expect(document.info().artist.empty(), "empty artist");
    expect(document.info().subartists.empty(), "empty subartists");
    expect(document.info().genre.empty(), "empty genre");
    expect(document.info().mode_hint == "beat-7k", "empty modeHint");
    expect(document.info().chart_name.empty(), "empty chartName");
    expect(document.info().level == 1, "empty level");
    expect_near(document.info().init_bpm, 120.0, "empty initBPM");
    expect_near(document.info().judge_rank, 100.0, "empty judgeRank");
    expect_near(document.info().total, 100.0, "empty total");
    expect(document.info().resolution == 240, "empty resolution is 240 pulses per beat");
    expect(document.lines().empty(), "empty lines");
    expect(document.bpm_notes().empty(), "empty bpmNotes");
    expect(document.stop_notes().empty(), "empty stopNotes");
    expect(document.sound_channels().empty(), "empty soundChannels");

    const std::string json = document.to_json();
    expect(json_has_key(json, "sound_channels"), "empty write uses sound_channels");
    expect(json_has_key(json, "init_bpm"), "empty write uses init_bpm");
    expect(json_has_number(json, "init_bpm", "120"), "empty write init_bpm is 120");
    expect(!json_has_key(json, "soundChannels"), "empty write has no soundChannels");
    expect(!json_has_key(json, "initBPM"), "empty write has no initBPM");
    expect(document.version() == "1.0.0", "empty version stays 1.0.0");

    const auto again = ibms::BmsonDocument::from_json(json);
    expect(again.info().mode_hint == "beat-7k", "empty JSON keeps modeHint");
    expect(again.info().resolution == 240, "empty JSON keeps resolution");
    expect_near(again.info().init_bpm, 120.0, "empty JSON keeps initBPM");
}

void minimal_json_roundtrip()
{
    const auto original = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    expect(original.info().title == "Demo", "minimal title");
    expect_near(original.info().init_bpm, 140.0, "minimal initBPM");
    expect(original.info().mode_hint == "beat-7k", "missing modeHint uses default");
    expect(original.info().resolution == 240, "missing resolution uses 240");
    expect(original.lines().size() == 1 && original.lines()[0].y == 240, "one line at pulse 240");
    expect(original.bpm_notes().size() == 1, "one bpmNote");
    expect(original.bpm_notes()[0].y == 0, "bpmNote pulse");
    expect_near(original.bpm_notes()[0].v, 140.0, "bpmNote value");
    expect(original.sound_channels().size() == 1, "one soundChannel");
    expect(original.sound_channels()[0].name == "kick.wav", "sound file name");
    expect(original.sound_channels()[0].notes.size() == 1, "one short note");
    expect(original.sound_channels()[0].notes[0].x == 1, "BMSON lane 1");
    expect(original.sound_channels()[0].notes[0].y == 0, "note pulse 0");
    expect(original.sound_channels()[0].notes[0].l == 0, "short note length");
    expect(!original.sound_channels()[0].notes[0].c, "short note is not continue");

    const std::string written = original.to_json();
    expect(json_has_key(written, "sound_channels"), "camelCase fixture rewrite uses sound_channels");
    expect(json_has_key(written, "init_bpm"), "camelCase fixture rewrite uses init_bpm");
    expect(json_has_key(written, "bpm_events"), "camelCase fixture rewrite uses bpm_events");
    expect(!json_has_key(written, "soundChannels"), "camelCase fixture rewrite drops soundChannels");
    expect(!json_has_key(written, "initBPM"), "camelCase fixture rewrite drops initBPM");
    expect(!json_has_key(written, "bpmNotes"), "camelCase fixture rewrite drops bpmNotes");

    const auto roundtrip = ibms::BmsonDocument::from_json(written);
    expect(roundtrip.info().title == "Demo", "roundtrip title");
    expect_near(roundtrip.info().init_bpm, 140.0, "roundtrip initBPM");
    expect(roundtrip.lines().size() == 1 && roundtrip.lines()[0].y == 240, "roundtrip line pulse");
    expect(roundtrip.bpm_notes().size() == 1 && roundtrip.bpm_notes()[0].y == 0, "roundtrip bpmNote");
    expect_near(roundtrip.bpm_notes()[0].v, 140.0, "roundtrip bpm value");
    expect(roundtrip.sound_channels().size() == 1, "roundtrip channel count");
    expect(roundtrip.sound_channels()[0].name == "kick.wav", "roundtrip wav name");
    expect(roundtrip.sound_channels()[0].notes[0].x == 1, "roundtrip lane");
    expect(roundtrip.sound_channels()[0].notes[0].l == 0, "roundtrip short note");
}

void erase_sound_note_by_pulse()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    expect(document.erase_sound_note(0, 0), "erase fixture pulse 0");
    expect(document.sound_channels()[0].notes.empty(), "channel has no notes");
    expect(!document.erase_sound_note(0, 0), "second erase misses");
    expect(!document.erase_sound_note(3, 0), "missing channel misses");

    const auto again = ibms::BmsonDocument::from_json(document.to_json());
    expect(again.sound_channels()[0].notes.empty(), "erased note stays gone");
}

void insert_long_note_and_same_pulse_update()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    document.insert_sound_note(0, ibms::BmsonNote{1, 0, 240, false});
    expect(document.sound_channels()[0].notes.size() == 1, "same pulse updates");
    expect(document.sound_channels()[0].notes[0].l == 240, "length becomes one beat");
    expect(document.sound_channels()[0].notes[0].x == 1, "lane stays 1");

    const auto again = ibms::BmsonDocument::from_json(document.to_json());
    expect(again.sound_channels()[0].notes[0].l == 240, "long note survives from_json");
}

void insert_overlapping_lane_is_refused()
{
    auto document = ibms::BmsonDocument::from_json(
        R"({"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[]}]})");
    expect(document.sound_channels().size() == 2, "two channels");
    expect_throws<ibms::BmsonParseError>(
        [&] { document.insert_sound_note(1, ibms::BmsonNote{1, 0, 0, false}); },
        "same lane same pulse on another channel is refused");
    expect_throws<ibms::BmsonParseError>(
        [&] { document.insert_sound_note(1, ibms::BmsonNote{1, 0, 240, false}); },
        "long note that covers another channel is refused");
    expect(document.sound_channels()[1].notes.empty(), "refused insert writes nothing");
}

void replace_sound_note_moves_pulse()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    document.replace_sound_note(0, 0, ibms::BmsonNote{2, 240, 240, false});
    expect(document.sound_channels()[0].notes.size() == 1, "replace keeps one note");
    expect(document.sound_channels()[0].notes[0].x == 2, "replace lane");
    expect(document.sound_channels()[0].notes[0].y == 240, "replace pulse");
    expect(document.sound_channels()[0].notes[0].l == 240, "replace length");
    expect_throws<ibms::BmsonParseError>(
        [&] { document.replace_sound_note(0, 0, ibms::BmsonNote{1, 0, 0, false}); },
        "missing old pulse is refused");
}

void note_extra_json_roundtrip_keeps_length()
{
    auto document = ibms::BmsonDocument::from_json(
        R"({"info":{"resolution":240},"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":240,"c":false,"comment":"first beat"}]}]})"
    );
    expect(
        json_has_string(document.note_extra_object_json(0, 0), "comment", "first beat"),
        "read note extra"
    );
    document.replace_sound_note(0, 0, ibms::BmsonNote{1, 0, 480, false});
    expect(document.sound_channels()[0].notes[0].l == 480, "length updated");
    expect(
        json_has_string(document.note_extra_object_json(0, 0), "comment", "first beat"),
        "replace_sound_note keeps extra"
    );
    document.replace_note_extra_object_json(0, 0, R"({"tag":2})");
    const std::string json = document.to_json();
    expect(json_has_key(json, "tag"), "wrote tag extra");
    expect(json.find("first beat") == std::string::npos, "replaced extra");
    expect(document.sound_channels()[0].notes[0].l == 480, "extra write keeps length");
    expect_throws<ibms::BmsonParseError>(
        [&] { (void)document.note_extra_object_json(0, 99); }, "missing pulse extra");
    expect_throws<ibms::BmsonParseError>(
        [&] { document.replace_note_extra_object_json(0, 0, "[]"); }, "extra must be object");
}

void replace_sound_note_refuses_other_channel()
{
    auto document = ibms::BmsonDocument::from_json(
        R"({"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]},{"name":"b.wav","notes":[{"x":2,"y":240,"l":0,"c":false}]}]})");
    expect_throws<ibms::BmsonParseError>(
        [&] { document.replace_sound_note(0, 0, ibms::BmsonNote{2, 240, 0, false}); },
        "move onto another channel's lane is refused");
    expect(document.sound_channels()[0].notes[0].x == 1 && document.sound_channels()[0].notes[0].y == 0,
           "failed replace keeps the original note");
}

void insert_sound_note_roundtrip()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    document.insert_sound_note(0, ibms::BmsonNote{2, 240, 0, false});
    expect(document.sound_channels().size() == 1, "insert keeps one channel");
    expect(document.sound_channels()[0].notes.size() == 2, "insert appends a short note");
    expect(document.sound_channels()[0].notes[1].x == 2, "inserted BMSON lane");
    expect(document.sound_channels()[0].notes[1].y == 240, "inserted pulse");
    expect(document.sound_channels()[0].notes[1].l == 0, "inserted short length");
    expect(!document.sound_channels()[0].notes[1].c, "inserted continue is false");

    const auto again = ibms::BmsonDocument::from_json(document.to_json());
    expect(again.info().title == "Demo", "insert roundtrip title");
    expect(again.sound_channels()[0].notes.size() == 2, "insert roundtrip note count");
    expect(again.sound_channels()[0].notes[0].x == 1, "original lane kept");
    expect(again.sound_channels()[0].notes[1].x == 2 && again.sound_channels()[0].notes[1].y == 240,
           "inserted note survives from_json");

    auto empty = ibms::BmsonDocument::empty();
    empty.insert_sound_note(3, ibms::BmsonNote{1, 0, 0, false});
    expect(empty.sound_channels().size() == 1, "empty insert creates first channel");
    expect(empty.sound_channels()[0].notes.size() == 1, "empty insert writes one note");
    expect(empty.sound_channels()[0].notes[0].x == 1, "empty insert lane");
    const auto empty_again = ibms::BmsonDocument::from_json(empty.to_json());
    expect(empty_again.sound_channels()[0].notes[0].x == 1, "empty insert JSON roundtrip");
}

void pulse_number_accepts_whole_float()
{
    const auto document = ibms::BmsonDocument::from_json(
        R"({"info":{"title":"FloatY"},"lines":[{"y":240.0}]})");
    expect(document.lines().size() == 1 && document.lines()[0].y == 240, "y=240.0 is pulse 240");
}

void long_note_length_and_continue()
{
    const auto original = ibms::BmsonDocument::from_json(load_fixture("long-note-continue.bmson"));
    expect(original.sound_channels().size() == 1, "LN channel");
    expect(original.sound_channels()[0].name == "synth.wav", "LN sample");
    expect(original.sound_channels()[0].notes.size() == 1, "one LN");
    const auto& note = original.sound_channels()[0].notes[0];
    expect(note.x == 2, "LN lane");
    expect(note.y == 480, "LN start pulse");
    expect(note.l == 240, "LN length in pulses");
    expect(note.c, "LN continue flag");

    const auto roundtrip = ibms::BmsonDocument::from_json(original.to_json());
    const auto& again = roundtrip.sound_channels()[0].notes[0];
    expect(again.l == 240, "roundtrip LN length");
    expect(again.c, "roundtrip continue");
    expect(again.x == 2 && again.y == 480, "roundtrip LN lane and pulse");
}

void missing_info_uses_defaults()
{
    const auto document = ibms::BmsonDocument::from_json("{}");
    expect(document.info().mode_hint == "beat-7k", "missing info modeHint");
    expect(document.info().resolution == 240, "missing info resolution");
    expect(document.info().level == 1, "missing info level");
    expect_near(document.info().init_bpm, 120.0, "missing info initBPM");
    expect_near(document.info().judge_rank, 100.0, "missing info judgeRank");
    expect_near(document.info().total, 100.0, "missing info total");
}

void unknown_fields_are_kept()
{
    const auto original = ibms::BmsonDocument::from_json(load_fixture("unknown-fields.bmson"));
    expect(original.info().title == "Extra", "unknown-fields title");
    expect(original.lines().size() == 1 && original.lines()[0].y == 240, "unknown-fields line");
    const std::string json = original.to_json();
    expect(json_has_string(json, "banner", "bn.png"), "info extra banner kept");
    expect(json_has_key(json, "bga"), "root extra bga kept");
    expect(json_has_string(json, "comment", "first beat"), "line extra comment kept");

    const auto again = ibms::BmsonDocument::from_json(json);
    expect(json_has_string(again.to_json(), "banner", "bn.png"), "banner survives second write");
    expect(json_has_key(again.to_json(), "bga"), "bga survives second write");
}

void replace_info_title_keeps_extras()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("unknown-fields.bmson"));
    auto info = document.info();
    info.title = "Renamed";
    document.replace_info(info);
    expect(document.info().title == "Renamed", "replaced title");
    expect(json_has_string(document.to_json(), "banner", "bn.png"), "info extra banner kept");
}

void replace_sound_channel_name_keeps_notes()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    auto channels = document.sound_channels();
    expect(channels.size() == 1, "fixture has one channel");
    expect(channels[0].name == "kick.wav", "fixture name");
    channels[0].name = "snare.wav";
    document.replace_sound_channels(channels);
    expect(document.sound_channels()[0].name == "snare.wav", "renamed channel");
    expect(document.sound_channels()[0].notes.size() == 1, "notes stay");
    expect(document.sound_channels()[0].notes[0].x == 1, "lane stays");
    expect(json_has_string(document.to_json(), "name", "snare.wav"), "JSON has new name");
}

void upsert_and_erase_timing_notes()
{
    auto document = ibms::BmsonDocument::empty();
    document.upsert_bpm_note(ibms::BmsonBpmNote{240, 140.0});
    expect(document.bpm_notes().size() == 1, "one bpmNote");
    expect(document.bpm_notes()[0].y == 240, "bpm pulse");
    expect_near(document.bpm_notes()[0].v, 140.0, "bpm value");
    document.upsert_bpm_note(ibms::BmsonBpmNote{240, 180.0});
    expect(document.bpm_notes().size() == 1, "same pulse replaces BPM");
    expect_near(document.bpm_notes()[0].v, 180.0, "replaced BPM");
    document.upsert_stop_note(ibms::BmsonStopNote{240, 240.0});
    expect(document.stop_notes().size() == 1, "one stopNote");
    expect_near(document.stop_notes()[0].v, 240.0, "stop pulses");
    expect(document.erase_bpm_note(240), "erase BPM");
    expect(document.bpm_notes().empty(), "BPM gone");
    expect(document.erase_stop_note(240), "erase stop");
    expect(document.stop_notes().empty(), "stop gone");
    expect(!document.erase_bpm_note(240), "missing BPM");
    expect_throws<ibms::BmsonParseError>(
        [&document] { document.upsert_bpm_note(ibms::BmsonBpmNote{0, 0.0}); }, "zero BPM");
    expect_throws<ibms::BmsonParseError>(
        [&document] { document.upsert_stop_note(ibms::BmsonStopNote{0, 0.0}); }, "zero stop");
}

void convert_resolution_doubles_pulses()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    expect(document.info().resolution == 240, "fixture resolution");
    expect(!document.resolution_conversion_loses_information(480), "240→480 keeps multiples of 240");
    document.convert_resolution(480);
    expect(document.info().resolution == 480, "resolution 480");
    expect(document.lines().size() == 1 && document.lines()[0].y == 480, "line y doubles");
    expect(document.bpm_notes().size() == 1 && document.bpm_notes()[0].y == 0, "bpm y=0 stays");
    expect_near(document.bpm_notes()[0].v, 140.0, "bpm tempo does not scale");
    expect(document.sound_channels()[0].notes[0].x == 1, "lane stays");
    expect(document.sound_channels()[0].notes[0].y == 0, "note y=0 stays");
    expect(document.sound_channels()[0].notes[0].l == 0, "short length stays");
    expect_near(document.info().init_bpm, 140.0, "initBPM stays");
    expect(json_has_string(document.to_json(), "title", "Demo"), "title stays");
}

void convert_resolution_scales_long_note_and_stop()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("long-note-continue.bmson"));
    document.upsert_stop_note(ibms::BmsonStopNote{240, 240.0});
    document.convert_resolution(480);
    expect(document.info().resolution == 480, "LN resolution");
    expect(document.sound_channels()[0].notes[0].y == 960, "LN start doubles");
    expect(document.sound_channels()[0].notes[0].l == 480, "LN length doubles");
    expect(document.sound_channels()[0].notes[0].c, "continue stays");
    expect(document.sound_channels()[0].notes[0].x == 2, "LN lane stays");
    expect(document.stop_notes().size() == 1 && document.stop_notes()[0].y == 480, "stop y doubles");
    expect_near(document.stop_notes()[0].v, 480.0, "stop duration doubles");
}

void convert_resolution_lossy_and_range()
{
    auto document = ibms::BmsonDocument::from_json(
        R"({"info":{"resolution":240},"soundChannels":[{"name":"a.wav","notes":[{"x":1,"y":1,"l":0,"c":false}]}]})");
    expect(document.acceptable_resolution_divider() == 1, "y=1 and 240 → divider 1");
    expect(document.resolution_conversion_loses_information(120), "120 is not a multiple of 240");
    expect(!document.resolution_conversion_loses_information(480), "480 is a multiple of 240");
    document.convert_resolution(120);
    expect(document.sound_channels()[0].notes[0].y == 0, "1 * 120 / 240 truncates to 0");
    expect(document.info().resolution == 120, "lossy resolution written");

    auto same = ibms::BmsonDocument::from_json(load_fixture("minimal-roundtrip.bmson"));
    same.convert_resolution(240);
    expect(same.lines()[0].y == 240, "same resolution is a no-op");
    expect_throws<ibms::BmsonParseError>(
        [&same] { same.convert_resolution(47); }, "below 48");
    expect_throws<ibms::BmsonParseError>(
        [&same] { same.convert_resolution(24001); }, "above 24000");
    expect(same.info().resolution == 240, "rejected range leaves resolution");
}

void convert_resolution_keeps_extras()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("unknown-fields.bmson"));
    document.convert_resolution(480);
    expect(document.lines()[0].y == 480, "unknown-fields line doubles");
    expect(json_has_string(document.to_json(), "banner", "bn.png"), "info extra banner kept");
    expect(json_has_key(document.to_json(), "bga"), "root extra bga kept");
    expect(json_has_string(document.to_json(), "comment", "first beat"), "line extra comment kept");
}

void info_extra_object_json_hides_official_keys()
{
    const auto unknown = ibms::BmsonDocument::from_json(load_fixture("unknown-fields.bmson"));
    expect(unknown.info_extra_object_json() == "{}", "banner is not an Extra field");

    const auto extras = ibms::BmsonDocument::from_json(load_fixture("info-extra-fields.bmson"));
    expect(
        extras.info_extra_object_json() == R"({"field_1":"14:00 2015/11/14","field_2":[0,240,480]})",
        "unknown extras sorted");
    expect(extras.info_extra_string("banner") == "bn.png", "banner stays first-class extra");
    expect(json_has_string(extras.to_json(), "banner", "bn.png"), "banner still in JSON");

    auto document = extras;
    document.replace_info_extra_object_json(R"({"field_1":"edited","banner":"hack.png","title":"hack"})");
    expect(document.info().title == "Extra", "title ignored in Extra fields");
    expect(document.info_extra_string("banner") == "bn.png", "banner ignored in Extra fields");
    expect(document.info_extra_object_json() == R"({"field_1":"edited"})", "only unknown extra written");
    expect(json_has_string(document.to_json(), "banner", "bn.png"), "banner kept after replace");
    expect(json_has_string(document.to_json(), "field_1", "edited"), "field_1 written");
    expect(!json_has_key(document.to_json(), "field_2"), "old unknown extra removed");

    document.replace_info_extra_object_json("{}");
    expect(document.info_extra_object_json() == "{}", "empty Extra fields");
    expect(document.info_extra_string("banner") == "bn.png", "empty Extra keeps banner");

    expect_throws<ibms::BmsonParseError>(
        [&document] { document.replace_info_extra_object_json("nope"); }, "plain extra text");
    expect_throws<ibms::BmsonParseError>(
        [&document] { document.replace_info_extra_object_json("{"); }, "truncated extra");
    expect_throws<ibms::BmsonParseError>(
        [&document] { document.replace_info_extra_object_json(R"("field_1")"); }, "extra not object");
}

void info_extra_string_reads_and_writes_banner()
{
    auto document = ibms::BmsonDocument::from_json(load_fixture("unknown-fields.bmson"));
    expect(document.info_extra_string("banner") == "bn.png", "read banner extra");
    expect(document.info_extra_string("backImage").empty(), "missing extra is empty");
    document.set_info_extra_string("backImage", "bg.png");
    document.set_info_extra_string("eyecatchImage", "eye.png");
    expect(document.info_extra_string("backImage") == "bg.png", "wrote backImage");
    expect(json_has_string(document.to_json(), "backImage", "bg.png"), "backImage in JSON");
    expect(json_has_string(document.to_json(), "eyecatchImage", "eye.png"), "eyecatchImage in JSON");
    document.set_info_extra_string("banner", "");
    expect(document.info_extra_string("banner").empty(), "empty value removes");
    expect(!json_has_key(document.to_json(), "banner"), "banner key gone");
    expect_throws<ibms::BmsonParseError>(
        [&document] { document.set_info_extra_string("title", "nope"); }, "title is first-class");
    expect_throws<ibms::BmsonParseError>(
        [&document] { document.set_info_extra_string("", "x"); }, "empty key");
    expect(document.info().title == "Extra", "title extra write refused");
}

void bga_roundtrip_and_upsert()
{
    const auto document = ibms::BmsonDocument::from_json(
        R"({"bga":{"bga_header":[{"id":1,"name":"bg.png"}],"bga_events":[{"y":240,"id":1}],)"
        R"("layer_events":[{"y":480,"id":2}],"poor_events":[{"y":0,"id":0}]}})");
    expect(document.bga_headers().size() == 1 && document.bga_headers()[0].name == "bg.png", "header");
    expect(document.bga_events().size() == 1 && document.bga_events()[0].y == 240, "bga y");
    expect(document.layer_events().size() == 1 && document.layer_events()[0].id == 2, "layer id");
    expect(document.poor_events().size() == 1 && document.poor_events()[0].id == 0, "poor id 0");
    const std::string json = document.to_json();
    expect(json_has_key(json, "bga_header"), "writes 1.0 header");
    expect(json_has_key(json, "bga_events"), "writes 1.0 events");
    expect(!json_has_key(json, "bgaNotes"), "does not write 0.21 event key");

    auto edited = document;
    edited.upsert_bga_event(ibms::BmsonBgaLane::bga, ibms::BmsonBgaEvent{240, 3});
    expect(edited.bga_events().size() == 1 && edited.bga_events()[0].id == 3, "same pulse replaces");
    edited.upsert_bga_event(ibms::BmsonBgaLane::layer, ibms::BmsonBgaEvent{0, 1});
    expect(edited.layer_events().size() == 2, "new layer pulse");
    expect(edited.erase_bga_event(ibms::BmsonBgaLane::poor, 0), "erase poor");
    expect(edited.poor_events().empty(), "poor gone");
    expect(!edited.erase_bga_event(ibms::BmsonBgaLane::poor, 0), "missing poor");
}

void bga_reads_021_keys_and_keeps_extras()
{
    const auto original = ibms::BmsonDocument::from_json(load_fixture("unknown-fields.bmson"));
    expect(original.bga_headers().empty() && original.bga_events().empty(), "unused bga has no events");
    expect(json_has_key(original.to_json(), "bga"), "root bga stays");
    expect(json_has_key(original.to_json(), "unused"), "bga extra unused stays");

    const auto v021 = ibms::BmsonDocument::from_json(
        R"({"bga":{"bgaHeader":[{"ID":4,"name":"old.png"}],"bgaNotes":[{"y":120,"ID":4}]}})");
    expect(v021.bga_headers().size() == 1 && v021.bga_headers()[0].id == 4, "0.21 header ID");
    expect(v021.bga_events().size() == 1 && v021.bga_events()[0].y == 120, "0.21 note");
    expect(json_has_key(v021.to_json(), "bga_header"), "0.21 rewritten as 1.0");
}

void convert_resolution_scales_bga()
{
    auto document = ibms::BmsonDocument::from_json(
        R"({"info":{"resolution":240},"bga":{"bga_events":[{"y":240,"id":1}]}})");
    document.convert_resolution(480);
    expect(document.bga_events().size() == 1 && document.bga_events()[0].y == 480, "bga y doubles");
    expect(document.bga_events()[0].id == 1, "bga id stays");
}

void illegal_json_does_not_crash()
{
    expect_throws<ibms::BmsonParseError>([] { (void)ibms::BmsonDocument::from_json(""); }, "empty text");
    expect_throws<ibms::BmsonParseError>([] { (void)ibms::BmsonDocument::from_json("not json"); }, "plain text");
    expect_throws<ibms::BmsonParseError>([] { (void)ibms::BmsonDocument::from_json("{"); }, "truncated object");
    expect_throws<ibms::BmsonParseError>(
        [] { (void)ibms::BmsonDocument::from_json(R"({"info":[]})"); }, "info array");
    expect_throws<ibms::BmsonParseError>(
        [] { (void)ibms::BmsonDocument::from_json(R"({"info":{"resolution":-1}})"); },
        "negative resolution");
    expect_throws<ibms::BmsonParseError>(
        [] { (void)ibms::BmsonDocument::from_json("[]"); }, "root array");
}

[[nodiscard]] std::size_t total_sound_notes(const ibms::BmsonDocument& document)
{
    std::size_t count = 0;
    for (const auto& channel : document.sound_channels()) {
        count += channel.notes.size();
    }
    return count;
}

void expect_bmsone10_write_without_camelcase_aliases(std::string_view json, std::string_view expression)
{
    expect(json_has_key(json, "sound_channels"), expression);
    expect(json_has_key(json, "init_bpm"), expression);
    expect(json_has_key(json, "mode_hint"), expression);
    expect(json_has_key(json, "chart_name"), expression);
    expect(json_has_key(json, "judge_rank"), expression);
    expect(json_has_key(json, "bpm_events"), expression);
    expect(json_has_key(json, "stop_events"), expression);
    expect(!json_has_key(json, "soundChannels"), expression);
    expect(!json_has_key(json, "initBPM"), expression);
    expect(!json_has_key(json, "modeHint"), expression);
    expect(!json_has_key(json, "chartName"), expression);
    expect(!json_has_key(json, "judgeRank"), expression);
    expect(!json_has_key(json, "bpmNotes"), expression);
    expect(!json_has_key(json, "stopNotes"), expression);
}

void expect_init_bpm_not_zero(std::string_view json, std::string_view expression)
{
    expect(json_has_key(json, "init_bpm"), expression);
    expect(!json_has_number(json, "init_bpm", "0"), expression);
}

void bmsone_snake_case_reads_channels_and_init_bpm()
{
    const auto document = ibms::BmsonDocument::from_json(load_fixture("bmsone-snake-case.bmson"));
    expect(document.sound_channels().size() == 1, "BmsONE snake_case has one channel");
    expect(total_sound_notes(document) == 2, "BmsONE snake_case has two notes");
    if (document.sound_channels().size() == 1 && document.sound_channels()[0].notes.size() == 2) {
        expect(document.sound_channels()[0].name == "kick.wav", "BmsONE snake_case wav");
        expect(document.sound_channels()[0].notes[0].x == 1 && document.sound_channels()[0].notes[0].l == 0,
               "first note is short");
        expect(document.sound_channels()[0].notes[1].x == 2 && document.sound_channels()[0].notes[1].l == 240,
               "second note is long");
    }
    expect_near(document.info().init_bpm, 140.0, "init_bpm is 140, not default 120");
    expect(document.info().chart_name == "Hyper", "chart_name");
    expect_near(document.info().judge_rank, 80.0, "judge_rank");
    expect(document.info().mode_hint == "beat-7k", "mode_hint");
    expect(document.info().level == 2, "level");
    expect(document.bpm_notes().size() == 1, "one bpm_event");
    if (document.bpm_notes().size() == 1) {
        expect(document.bpm_notes()[0].y == 240, "bpm_events pulse");
        expect_near(document.bpm_notes()[0].v, 160.0, "bpm_events uses bpm, not v");
    }
    expect(document.stop_notes().size() == 1, "one stop_event");
    if (document.stop_notes().size() == 1) {
        expect(document.stop_notes()[0].y == 480, "stop_events pulse");
        expect_near(document.stop_notes()[0].v, 120.0, "stop_events uses duration, not v");
    }

    const std::string json = document.to_json();
    expect_bmsone10_write_without_camelcase_aliases(json, "snake_case rewrite stays BmsONE 1.0");
    expect(json_has_key(json, "bpm_events"), "writes bpm_events");
    expect(json_has_key(json, "stop_events"), "writes stop_events");
    expect(json_has_key(json, "bpm"), "BPM field is bpm, not v");
    expect(json_has_key(json, "duration"), "stop field is duration, not v");
    expect(!json_has_key(json, "v"), "timing rewrite does not keep v");
    expect_init_bpm_not_zero(json, "snake_case rewrite init_bpm is not 0");
    expect(json_has_number(json, "init_bpm", "140"), "snake_case rewrite init_bpm is 140");

    const auto again = ibms::BmsonDocument::from_json(json);
    expect(again.sound_channels().size() == 1 && total_sound_notes(again) == 2, "roundtrip keeps notes");
    expect_near(again.info().init_bpm, 140.0, "roundtrip initBPM");
    expect(again.info().chart_name == "Hyper", "roundtrip chartName");
    expect_near(again.info().judge_rank, 80.0, "roundtrip judgeRank");
    expect(again.bpm_notes().size() == 1 && again.bpm_notes()[0].y == 240, "roundtrip bpmNotes");
    expect_near(again.bpm_notes()[0].v, 160.0, "roundtrip bpm value");
    expect(again.stop_notes().size() == 1 && again.stop_notes()[0].y == 480, "roundtrip stopNotes");
    expect_near(again.stop_notes()[0].v, 120.0, "roundtrip stop duration");
    expect_bmsone10_write_without_camelcase_aliases(again.to_json(), "second write stays BmsONE 1.0");
}

void empty_camelcase_channels_yield_to_populated_snake_case()
{
    const auto document = ibms::BmsonDocument::from_json(
        R"({"info":{"initBPM":120,"init_bpm":140},"soundChannels":[],"sound_channels":[)"
        R"({"name":"tone.wav","notes":[{"x":1,"y":0,"l":0,"c":false},{"x":2,"y":240,"l":240,"c":false}]}]})");
    expect(document.sound_channels().size() == 1, "empty soundChannels does not hide sound_channels");
    expect(total_sound_notes(document) == 2, "notes come from sound_channels");
    if (document.sound_channels().size() == 1 && document.sound_channels()[0].notes.size() == 2) {
        expect(document.sound_channels()[0].name == "tone.wav", "snake_case channel name");
        expect(document.sound_channels()[0].notes[1].l == 240, "long note from sound_channels");
    }
    expect_near(document.info().init_bpm, 120.0, "initBPM wins over init_bpm when both exist");
    const std::string json = document.to_json();
    expect_bmsone10_write_without_camelcase_aliases(json, "dual-key save writes BmsONE 1.0 keys");
    expect(json_has_key(json, "sound_channels"), "writes populated sound_channels");
    expect(!json_has_key(json, "soundChannels"), "does not keep empty soundChannels extra");
    expect_init_bpm_not_zero(json, "dual-key rewrite init_bpm is not 0");
    const auto again = ibms::BmsonDocument::from_json(json);
    expect(again.sound_channels().size() == 1 && total_sound_notes(again) == 2, "rewritten notes stay");
}

void conflicting_aliases_keep_camelcase_and_snake_only_notes()
{
    const auto document = ibms::BmsonDocument::from_json(
        R"({"soundChannels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}],)"
        R"("sound_channels":[{"name":"kick.wav","notes":[{"x":1,"y":0,"l":99,"c":true},)"
        R"({"x":2,"y":240,"l":240,"c":false}]},{"name":"snare.wav","notes":[{"x":3,"y":480,"l":0,"c":false}]}]})");
    expect(document.sound_channels().size() == 2, "snake-only channel is kept");
    if (document.sound_channels().size() >= 1) {
        expect(document.sound_channels()[0].name == "kick.wav", "first channel stays camelCase name");
        expect(document.sound_channels()[0].notes.size() == 2, "camelCase channel gains snake-only note");
        if (document.sound_channels()[0].notes.size() >= 1) {
            expect(document.sound_channels()[0].notes[0].l == 0 && !document.sound_channels()[0].notes[0].c,
                   "same pulse prefers camelCase");
        }
        if (document.sound_channels()[0].notes.size() >= 2) {
            expect(document.sound_channels()[0].notes[1].x == 2 && document.sound_channels()[0].notes[1].l == 240,
                   "snake-only note on same channel is kept");
        }
    }
    if (document.sound_channels().size() >= 2) {
        expect(document.sound_channels()[1].name == "snare.wav", "snake-only channel name");
        expect(document.sound_channels()[1].notes.size() == 1 && document.sound_channels()[1].notes[0].x == 3,
               "snake-only channel note");
    }
}

void snake_case_timing_merges_without_overwriting_camelcase()
{
    const auto document = ibms::BmsonDocument::from_json(
        R"({"bpmNotes":[{"y":0,"v":140}],"bpm_events":[{"y":0,"bpm":200},{"y":240,"bpm":160}],)"
        R"("stopNotes":[{"y":120,"v":60}],"stop_events":[{"y":120,"duration":999},{"y":480,"duration":90}]})");
    expect(document.bpm_notes().size() == 2, "bpm alias adds only the missing pulse");
    if (document.bpm_notes().size() >= 1) {
        expect(document.bpm_notes()[0].y == 0, "first BPM pulse");
        expect_near(document.bpm_notes()[0].v, 140.0, "same pulse prefers bpmNotes.v");
    }
    if (document.bpm_notes().size() >= 2) {
        expect(document.bpm_notes()[1].y == 240, "snake-only BPM pulse");
        expect_near(document.bpm_notes()[1].v, 160.0, "bpm_events.bpm");
    }
    expect(document.stop_notes().size() == 2, "stop alias adds only the missing pulse");
    if (document.stop_notes().size() >= 1) {
        expect_near(document.stop_notes()[0].v, 60.0, "same pulse prefers stopNotes.v");
    }
    if (document.stop_notes().size() >= 2) {
        expect(document.stop_notes()[1].y == 480, "snake-only stop pulse");
        expect_near(document.stop_notes()[1].v, 90.0, "stop_events.duration");
    }
    const std::string json = document.to_json();
    expect(json_has_key(json, "bpm_events"), "timing rewrite uses bpm_events");
    expect(json_has_key(json, "stop_events"), "timing rewrite uses stop_events");
    expect(json_has_key(json, "duration"), "timing rewrite uses duration");
    expect(!json_has_key(json, "bpmNotes"), "timing rewrite drops bpmNotes");
    expect(!json_has_key(json, "stopNotes"), "timing rewrite drops stopNotes");
    expect(!json_has_key(json, "v"), "timing rewrite does not keep v");
}

void writeback_uses_bmsone10_keys_from_either_alias()
{
    const auto camel = ibms::BmsonDocument::from_json(
        R"({"version":"1.0.0","info":{"title":"Camel","initBPM":140},"soundChannels":[)"
        R"({"name":"kick.wav","notes":[{"x":1,"y":0,"l":0,"c":false}]}]})");
    expect_near(camel.info().init_bpm, 140.0, "camelCase initBPM reads as 140");
    expect(camel.sound_channels().size() == 1 && total_sound_notes(camel) == 1, "camelCase channel");
    const std::string camel_json = camel.to_json();
    expect_bmsone10_write_without_camelcase_aliases(camel_json, "camelCase rewrite uses BmsONE 1.0");
    expect_init_bpm_not_zero(camel_json, "camelCase rewrite init_bpm is not 0");
    expect(json_has_number(camel_json, "init_bpm", "140"), "camelCase rewrite init_bpm is 140");
    expect(!json_has_key(camel_json, "soundChannels"), "camelCase rewrite has no soundChannels extra");

    const auto from_camel = ibms::BmsonDocument::from_json(camel_json);
    expect(from_camel.version() == "1.0.0", "camelCase rewrite keeps version 1.0.0");
    expect_near(from_camel.info().init_bpm, 140.0, "native rereads camelCase rewrite");
    expect(from_camel.sound_channels().size() == 1 && total_sound_notes(from_camel) == 1,
           "native rereads camelCase notes");

    const auto snake = ibms::BmsonDocument::from_json(load_fixture("bmsone-snake-case.bmson"));
    const std::string snake_json = snake.to_json();
    expect_bmsone10_write_without_camelcase_aliases(snake_json, "snake_case rewrite uses BmsONE 1.0");
    expect_init_bpm_not_zero(snake_json, "snake_case rewrite init_bpm is not 0");
    expect(json_has_number(snake_json, "init_bpm", "140"), "snake_case rewrite init_bpm is 140");
    expect(!json_has_key(snake_json, "soundChannels"), "snake_case rewrite has no soundChannels extra");

    const auto from_snake = ibms::BmsonDocument::from_json(snake_json);
    expect(from_snake.version() == "1.0.0", "snake_case rewrite keeps version 1.0.0");
    expect_near(from_snake.info().init_bpm, 140.0, "native rereads snake_case rewrite");
    expect(from_snake.sound_channels().size() == 1 && total_sound_notes(from_snake) == 2,
           "native rereads snake_case notes");
}

}  // namespace

int main()
{
    try {
        empty_document_uses_bmsone_defaults();
        minimal_json_roundtrip();
        erase_sound_note_by_pulse();
        insert_long_note_and_same_pulse_update();
        insert_overlapping_lane_is_refused();
        replace_sound_note_moves_pulse();
        note_extra_json_roundtrip_keeps_length();
        replace_sound_note_refuses_other_channel();
        insert_sound_note_roundtrip();
        pulse_number_accepts_whole_float();
        long_note_length_and_continue();
        missing_info_uses_defaults();
        unknown_fields_are_kept();
        replace_info_title_keeps_extras();
        replace_sound_channel_name_keeps_notes();
        upsert_and_erase_timing_notes();
        convert_resolution_doubles_pulses();
        convert_resolution_scales_long_note_and_stop();
        convert_resolution_lossy_and_range();
        convert_resolution_keeps_extras();
        info_extra_object_json_hides_official_keys();
        info_extra_string_reads_and_writes_banner();
        bga_roundtrip_and_upsert();
        bga_reads_021_keys_and_keeps_extras();
        convert_resolution_scales_bga();
        illegal_json_does_not_crash();
        bmsone_snake_case_reads_channels_and_init_bpm();
        empty_camelcase_channels_yield_to_populated_snake_case();
        conflicting_aliases_keep_camelcase_and_snake_only_notes();
        snake_case_timing_merges_without_overwriting_camelcase();
        writeback_uses_bmsone10_keys_from_either_alias();
    } catch (const std::exception& exception) {
        std::cerr << "Unhandled exception: " << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_bmson_tests passed\n";
    return 0;
}
