#include <ibms/bms_document.hpp>
#include <ibms/bms_import_random.hpp>
#include <ibms/bmson_from_bms.hpp>

#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

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

[[nodiscard]] std::string load_fixture(std::string_view filename)
{
    const std::filesystem::path path = std::filesystem::path{IBMS_BMS_IMPORT_FIXTURE_DIR} / filename;
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("unable to open BMS import fixture: " + path.string());
    }
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}

[[nodiscard]] ibms::BmsonFromBmsOptions options_for(std::string_view filename)
{
    ibms::BmsonFromBmsOptions options;
    options.path = (std::filesystem::path{IBMS_BMS_IMPORT_FIXTURE_DIR} / filename).string();
    return options;
}

[[nodiscard]] ibms::BmsonDocument import_fixture(std::string_view filename)
{
    return ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(load_fixture(filename)), options_for(filename));
}

[[nodiscard]] ibms::BmsonBmsMode detect_fixture(std::string_view filename)
{
    return ibms::detect_bmson_bms_mode(
        ibms::BmsDocument::from_bytes(load_fixture(filename)), options_for(filename));
}

void lane_map_mode_7k()
{
    expect(ibms::bmson_lane_x_mode_7k("11") == 1, "11 -> x=1");
    expect(ibms::bmson_lane_x_mode_7k("12") == 2, "12 -> x=2");
    expect(ibms::bmson_lane_x_mode_7k("15") == 5, "15 -> x=5");
    expect(ibms::bmson_lane_x_mode_7k("16") == 8, "16 -> scratch x=8");
    expect(ibms::bmson_lane_x_mode_7k("18") == 6, "18 -> x=6");
    expect(ibms::bmson_lane_x_mode_7k("19") == 7, "19 -> x=7");
    expect(ibms::bmson_lane_x_mode_7k("21") == 0, "21 is BGM in 7k");
    expect(ibms::bmson_lane_x_mode_7k("01") == 0, "01 is BGM");
    expect(ibms::bmson_lane_x_mode_7k("51") == 1, "51 long uses the same 7k map");
    expect(ibms::bmson_lane_x_mode_7k("56") == 8, "56 long scratch");
    expect(ibms::bmson_lane_x("16", ibms::BmsonBmsMode::mode_5k) == 8, "5k scratch");
    expect(ibms::bmson_lane_x("18", ibms::BmsonBmsMode::mode_5k) == 0, "18 is BGM in 5k");
    expect(ibms::bmson_lane_x("21", ibms::BmsonBmsMode::mode_10k) == 9, "21 -> x=9 in 10k");
    expect(ibms::bmson_lane_x("26", ibms::BmsonBmsMode::mode_10k) == 16, "26 -> x=16");
    expect(ibms::bmson_lane_x("18", ibms::BmsonBmsMode::mode_14k) == 6, "18 -> x=6 in 14k");
    expect(ibms::bmson_lane_x("28", ibms::BmsonBmsMode::mode_14k) == 14, "28 -> x=14");
    expect(ibms::bmson_lane_x("29", ibms::BmsonBmsMode::mode_14k) == 15, "29 -> x=15");
    expect(ibms::bmson_lane_x("13", ibms::BmsonBmsMode::mode_pms_5k) == 1, "13 -> x=1 in PMS 5k");
    expect(ibms::bmson_lane_x("22", ibms::BmsonBmsMode::mode_pms_5k) == 4, "22 -> x=4");
    expect(ibms::bmson_lane_x("11", ibms::BmsonBmsMode::mode_pms_9k) == 1, "11 -> x=1 in PMS 9k");
    expect(ibms::bmson_lane_x("22", ibms::BmsonBmsMode::mode_pms_9k) == 6, "22 -> x=6");
    expect(ibms::bmson_mode_hint(ibms::BmsonBmsMode::mode_5k) == "beat-5k", "5k hint");
    expect(ibms::bmson_mode_long_name(ibms::BmsonBmsMode::mode_7k) == "7key (BMS)", "7k long name");
}

void minimal_7k_fixture()
{
    const auto document = import_fixture("minimal-7k.bms");
    expect(document.info().title == "ImportDemo", "title");
    expect_near(document.info().init_bpm, 130.0, "initBPM from #BPM");
    expect(document.info().mode_hint == "beat-5k", "only 11 -> GetMode 5K");
    expect(document.info().resolution == 240, "default resolution");
    expect_near(document.info().judge_rank, 80.0, "missing RANK is Bms default 2 -> 80");
    expect(document.info().level == 0, "missing PLAYLEVEL is 0");
    expect_near(document.info().total, 100.0, "BmsONE does not import TOTAL");
    expect(document.sound_channels().size() == 1, "one WAV");
    expect(document.sound_channels()[0].name == "kick.wav", "WAV01 name");
    expect(document.sound_channels()[0].notes.size() == 1, "one note");
    expect(document.sound_channels()[0].notes[0].x == 1, "#00011 -> x=1");
    expect(document.sound_channels()[0].notes[0].y == 0, "measure 0 start");
    expect(document.sound_channels()[0].notes[0].l == 0, "short");
    expect(document.bpm_notes().empty(), "header BPM is not a bpmNote");
    expect(document.lines().size() == 3, "bar 0, end of last used, plus one more");
    expect(document.lines()[0].y == 0, "first bar");
    expect(document.lines()[1].y == 960, "4/4 measure in 240 pulses");
    expect(document.lines()[2].y == 1920, "one extra measure after last object");
}

void scratch_and_key_lanes()
{
    const auto document = import_fixture("scratch-and-keys.bms");
    expect(document.info().title == "ScratchKeys", "title");
    expect_near(document.info().judge_rank, 100.0, "RANK 3 -> 100");
    expect(document.info().mode_hint == "beat-7k", "18/19 -> GetMode 7K");
    expect(document.info().level == 12, "PLAYLEVEL 12");
    expect(document.sound_channels().size() == 4, "four WAV definitions");
    expect(document.sound_channels()[0].name == "key1.wav" && document.sound_channels()[0].notes[0].x == 1,
           "11 -> x=1");
    expect(document.sound_channels()[1].name == "scratch.wav" && document.sound_channels()[1].notes[0].x == 8,
           "16 -> x=8");
    expect(document.sound_channels()[2].name == "key6.wav" && document.sound_channels()[2].notes[0].x == 6,
           "18 -> x=6");
    expect(document.sound_channels()[3].name == "key7.wav" && document.sound_channels()[3].notes[0].x == 7,
           "19 -> x=7");
}

void measure_one_and_long_note()
{
    const auto document = import_fixture("measure-1-and-ln.bms");
    expect(document.sound_channels().size() == 1, "one channel");
    expect(document.sound_channels()[0].notes.size() == 2, "LN start plus measure-1 short");
    bool saw_ln = false;
    bool saw_later = false;
    for (const auto& note : document.sound_channels()[0].notes) {
        if (note.y == 0 && note.x == 1 && note.l == 480) {
            saw_ln = true;
        }
        if (note.y == 960 && note.x == 1 && note.l == 0) {
            saw_later = true;
        }
    }
    expect(saw_ln, "#00051:0101 is one beat LN on x=1");
    expect(saw_later, "#00111:01 is pulse 960");
}

void detect_and_import_other_modes()
{
    expect(detect_fixture("minimal-7k.bms") == ibms::BmsonBmsMode::mode_5k, "only 11 is 5K");
    expect(detect_fixture("scratch-and-keys.bms") == ibms::BmsonBmsMode::mode_7k, "18/19 is 7K");
    expect(detect_fixture("two-player-10k.bms") == ibms::BmsonBmsMode::mode_10k, "21 without 18 is 10K");
    expect(detect_fixture("two-player-14k.bms") == ibms::BmsonBmsMode::mode_14k, "21 plus 18 is 14K");
    expect(detect_fixture("pms-5k.pms") == ibms::BmsonBmsMode::mode_pms_5k, "pms unused 11/12 is 5key PMS");
    expect(detect_fixture("pms-9k.pms") == ibms::BmsonBmsMode::mode_pms_9k, "pms with 11 is 9key PMS");

    const auto ten = import_fixture("two-player-10k.bms");
    expect(ten.info().mode_hint == "beat-10k", "10k hint");
    expect(ten.sound_channels()[0].notes[0].x == 1, "11 -> x=1");
    expect(ten.sound_channels()[1].notes[0].x == 9, "21 -> x=9");

    const auto fourteen = import_fixture("two-player-14k.bms");
    expect(fourteen.info().mode_hint == "beat-14k", "14k hint");
    expect(fourteen.sound_channels()[0].notes[0].x == 1, "11 -> x=1");
    expect(fourteen.sound_channels()[1].notes[0].x == 6, "18 -> x=6");
    expect(fourteen.sound_channels()[2].notes[0].x == 9, "21 -> x=9");

    const auto pms5 = import_fixture("pms-5k.pms");
    expect(pms5.info().mode_hint == "popn-5k", "pms 5k hint");
    expect(pms5.sound_channels()[0].notes[0].x == 1, "13 -> x=1");

    const auto pms9 = import_fixture("pms-9k.pms");
    expect(pms9.info().mode_hint == "popn-9k", "pms 9k hint");
    expect(pms9.sound_channels()[0].notes[0].x == 1, "11 -> x=1 in 9k");

    ibms::BmsonFromBmsOptions forced = options_for("minimal-7k.bms");
    forced.mode = ibms::BmsonBmsMode::mode_7k;
    const auto forced_doc = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(load_fixture("minimal-7k.bms")), forced);
    expect(forced_doc.info().mode_hint == "beat-7k", "forced MODE_7K");

    const auto scratch = ibms::BmsDocument::from_bytes(load_fixture("scratch-and-keys.bms"));
    const auto fiveErrors = ibms::bmson_mode_error_offsets(scratch, ibms::BmsonBmsMode::mode_5k);
    expect(fiveErrors.size() == 2, "5K rejects 18 and 19");
    expect(fiveErrors[0] == 8 && fiveErrors[1] == 9, "error offsets 8, 9");
    expect(ibms::bmson_mode_error_offsets(scratch, ibms::BmsonBmsMode::mode_7k).empty(), "7K accepts 18/19");
}

void random_if_selects_branch()
{
    const std::string source = load_fixture("random-if.bms");
    const auto maxima = ibms::collect_bms_random_maxima(source);
    expect(maxima.size() == 1 && maxima[0] == 2, "one RANDOM 2");

    const auto raw = ibms::BmsDocument::from_bytes(source);
    expect(raw.chart().events.empty(), "unfiltered conditionals expose no events");

    const auto first = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(source, {1})),
        options_for("random-if.bms"));
    expect(first.info().title == "RandomDemo", "title kept");
    expect(first.sound_channels().size() == 2, "both WAV defs stay");
    expect(first.sound_channels()[0].name == "kick.wav", "wav 01");
    expect(first.sound_channels()[0].notes.size() == 1, "IF 1 keeps kick note");
    expect(first.sound_channels()[0].notes[0].x == 1, "11 -> x=1");
    expect(first.sound_channels()[1].notes.empty(), "IF 1 drops 12");

    const auto second = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(source, {2})),
        options_for("random-if.bms"));
    expect(second.sound_channels().size() == 2, "both WAV defs stay");
    expect(second.sound_channels()[1].name == "snare.wav", "wav 02");
    expect(second.sound_channels()[0].notes.empty(), "ELSEIF 2 drops 11");
    expect(second.sound_channels()[1].notes.size() == 1, "ELSEIF 2 keeps snare");
    expect(second.sound_channels()[1].notes[0].x == 2, "12 -> x=2");
}

[[nodiscard]] ibms::BmsonDocument import_applied(
    std::string_view filename, const std::vector<int>& values)
{
    const std::string source = load_fixture(filename);
    return ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(source, values)),
        options_for(filename));
}

[[nodiscard]] const ibms::BmsonSoundChannel* wav_named(
    const ibms::BmsonDocument& document, std::string_view name)
{
    for (const auto& channel : document.sound_channels()) {
        if (channel.name == name) {
            return &channel;
        }
    }
    return nullptr;
}

void expect_exclusive_branch(
    std::string_view filename,
    const std::vector<int>& values,
    std::string_view kept_name,
    int kept_count,
    int kept_x,
    std::string_view dropped_name,
    std::string_view label)
{
    const auto document = import_applied(filename, values);
    const auto* kept = wav_named(document, kept_name);
    const auto* dropped = wav_named(document, dropped_name);
    expect(kept != nullptr && static_cast<int>(kept->notes.size()) == kept_count, label);
    expect(dropped != nullptr && dropped->notes.empty(), label);
    if (kept != nullptr) {
        for (const auto& note : kept->notes) {
            expect(note.x == kept_x, label);
        }
    }
}

void ubmplay_compact_random_selects_one_branch()
{
    const std::string source = load_fixture("ubmplay-random-compact.bms");
    const auto maxima = ibms::collect_bms_random_maxima(source);
    expect(maxima.size() == 1 && maxima[0] == 2, "compact RANDOM2 is one maximum of 2");

    expect_exclusive_branch(
        "ubmplay-random-compact.bms", {1}, "kick.wav", 1, 1, "snare.wav", "RANDOM2 value 1 keeps IF1");
    expect_exclusive_branch(
        "ubmplay-random-compact.bms", {2}, "snare.wav", 1, 2, "kick.wav", "RANDOM2 value 2 keeps IF2");
}

void ubmplay_nested_outer_skips_inner()
{
    expect_exclusive_branch(
        "ubmplay-random-nested.bms", {1}, "kick.wav", 1, 1, "snare.wav",
        "outer value 1 drops the nested snare");
    expect_exclusive_branch(
        "ubmplay-random-nested.bms", {2}, "snare.wav", 2, 2, "kick.wav",
        "outer value 2 keeps the nested snare");
}

[[nodiscard]] ibms::BmsonDocument import_chart(
    const std::string& source, const std::vector<int>& values)
{
    ibms::BmsonFromBmsOptions options;
    options.path = "nested-inactive.bms";
    return ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(source, values)), options);
}

void ubmplay_nested_inactive_inherits()
{
    const std::string source = load_fixture("ubmplay-random-nested-inactive.bms");
    const auto maxima = ibms::collect_bms_random_maxima(source);
    expect(maxima.size() == 2 && maxima[0] == 2 && maxima[1] == 1, "outer max 2 and inner max 1");

    const std::string inactive = ibms::apply_bms_random(source, {1, 1});
    expect(inactive.find("#00011:01") == std::string::npos, "inactive parent hides a matching inner IF");
    expect(inactive.find("#00012:02") == std::string::npos, "inner ENDIF does not resume the parent body");
    expect(inactive.find("#00111:01\n") != std::string::npos, "outer ENDIF resumes the following note");
    const auto inactive_doc = import_applied("ubmplay-random-nested-inactive.bms", {1, 1});
    const auto* inactive_a = wav_named(inactive_doc, "a.wav");
    const auto* inactive_b = wav_named(inactive_doc, "b.wav");
    expect(inactive_a != nullptr && inactive_a->notes.size() == 1 && inactive_a->notes[0].y == 960,
           "inactive parent imports only the note after ENDIF");
    expect(inactive_b != nullptr && inactive_b->notes.empty(), "inactive parent imports no inner snare");

    const auto active = import_applied("ubmplay-random-nested-inactive.bms", {2, 1});
    const auto* active_a = wav_named(active, "a.wav");
    const auto* active_b = wav_named(active, "b.wav");
    expect(active_a != nullptr && active_a->notes.size() == 2, "active parent keeps the matching child and the coda");
    expect(active_b != nullptr && active_b->notes.size() == 1 && active_b->notes[0].x == 2,
           "active parent keeps the note after the inner ENDIF");

    const std::string mismatch =
        "#WAV01 a.wav\n#WAV02 b.wav\n#RANDOM 2\n#IF 2\n#RANDOM 1\n#IF 2\n#00011:01\n"
        "#ENDIF\n#00012:02\n#ENDIF\n#00111:01\n";
    const auto mismatch_doc = import_chart(mismatch, {1, 1});
    const auto* mismatch_a = wav_named(mismatch_doc, "a.wav");
    const auto* mismatch_b = wav_named(mismatch_doc, "b.wav");
    expect(mismatch_a != nullptr && mismatch_a->notes.size() == 1 && mismatch_a->notes[0].y == 960,
           "inactive parent also hides a mismatched child");
    expect(mismatch_b != nullptr && mismatch_b->notes.empty(), "mismatched child does not resume the parent body");

    const std::string end_random =
        "#WAV01 a.wav\n#WAV02 b.wav\n#RANDOM 2\n#IF 2\n#RANDOM 1\n#IF 1\n#00011:01\n"
        "#ENDRANDOM\n#00012:02\n#ENDIF\n#ENDRANDOM\n#00111:01\n";
    const std::string ended = ibms::apply_bms_random(end_random, {1, 1});
    expect(ended.find("#00011:01") == std::string::npos, "ENDRANDOM leaves the matching child hidden");
    expect(ended.find("#00012:02") == std::string::npos, "ENDRANDOM restores the parent skip");
    expect(ended.find("#00111:01\n") != std::string::npos, "outer ENDRANDOM restores the following note");

    const std::string siblings =
        "#WAV01 a.wav\n#WAV02 b.wav\n#RANDOM 2\n#IF 1\n#00011:01\n#ENDIF\n#IF 2\n#00012:02\n"
        "#ENDIF\n#00111:01\n";
    const auto sibling_one = import_chart(siblings, {1});
    const auto* sib_a = wav_named(sibling_one, "a.wav");
    const auto* sib_b = wav_named(sibling_one, "b.wav");
    expect(sib_a != nullptr && sib_a->notes.size() == 2, "sibling value 1 keeps IF 1 and the coda");
    expect(sib_b != nullptr && sib_b->notes.empty(), "sibling value 1 drops IF 2");
    const auto sibling_two = import_chart(siblings, {2});
    sib_a = wav_named(sibling_two, "a.wav");
    sib_b = wav_named(sibling_two, "b.wav");
    expect(sib_b != nullptr && sib_b->notes.size() == 1 && sib_b->notes[0].x == 2, "sibling value 2 keeps IF 2");
    expect(sib_a != nullptr && sib_a->notes.size() == 1 && sib_a->notes[0].y == 960,
           "sibling value 2 keeps only the coda on wav 01");

    const std::string inner_siblings =
        "#WAV01 a.wav\n#WAV02 b.wav\n#RANDOM 2\n#IF 2\n#RANDOM 1\n#IF 1\n#00011:01\n#ENDIF\n"
        "#IF 1\n#00012:02\n#ENDIF\n#ENDIF\n#00111:01\n";
    const auto inner = import_chart(inner_siblings, {1, 1});
    const auto* inner_a = wav_named(inner, "a.wav");
    const auto* inner_b = wav_named(inner, "b.wav");
    expect(inner_a != nullptr && inner_a->notes.size() == 1 && inner_a->notes[0].y == 960,
           "sibling IFs inside an inactive parent stay hidden");
    expect(inner_b != nullptr && inner_b->notes.empty(), "second inner sibling stays hidden");

    const std::string set_inside =
        "#WAV01 a.wav\n#RANDOM 2\n#IF 2\n#SETRANDOM 1\n#IF 1\n#00011:01\n#ENDIF\n#ENDIF\n#00111:01\n";
    const auto set_doc = import_chart(set_inside, {1});
    const auto* set_a = wav_named(set_doc, "a.wav");
    expect(set_a != nullptr && set_a->notes.size() == 1 && set_a->notes[0].y == 960,
           "SETRANDOM inside an inactive IF does not activate IF 1");
}

void ubmplay_rondam_and_end_if_resume()
{
    const std::string source = load_fixture("ubmplay-random-end-if.bms");
    const auto maxima = ibms::collect_bms_random_maxima(source);
    expect(maxima.size() == 1 && maxima[0] == 2, "spaced rondam is a RANDOM maximum");

    const auto first = import_applied("ubmplay-random-end-if.bms", {1});
    const auto* kick = wav_named(first, "kick.wav");
    const auto* snare = wav_named(first, "snare.wav");
    expect(kick != nullptr && kick->notes.size() == 2, "rondam 1 keeps the IF 1 note and the note after END IF");
    expect(snare != nullptr && snare->notes.empty(), "rondam 1 drops IF 2");
    if (kick != nullptr && kick->notes.size() == 2) {
        expect(kick->notes[0].y == 0 && kick->notes[1].y == 960, "both kick notes stay");
    }

    const auto second = import_applied("ubmplay-random-end-if.bms", {2});
    kick = wav_named(second, "kick.wav");
    snare = wav_named(second, "snare.wav");
    expect(kick != nullptr && kick->notes.size() == 1 && kick->notes[0].y == 960,
           "non-matching IF then END IF restores the later note");
    expect(snare != nullptr && snare->notes.size() == 1 && snare->notes[0].x == 2,
           "rondam 2 keeps IF 2");
}

void ubmplay_compact_case_is_insensitive()
{
    const auto maxima = ibms::collect_bms_random_maxima(load_fixture("ubmplay-random-case.bms"));
    expect(maxima.size() == 1 && maxima[0] == 2, "lowercase random2 is collected");
    expect_exclusive_branch(
        "ubmplay-random-case.bms", {1}, "kick.wav", 1, 1, "snare.wav", "lowercase if1 keeps kick");
    expect_exclusive_branch(
        "ubmplay-random-case.bms", {2}, "snare.wav", 1, 2, "kick.wav", "mixed-case If2 keeps snare");
}

void ubmplay_unknown_neighbors_stay_literal()
{
    const std::string source = load_fixture("ubmplay-random-unknown.bms");
    const auto maxima = ibms::collect_bms_random_maxima(source);
    expect(maxima.size() == 1 && maxima[0] == 2, "pattern and rondam4 are not random maxima");

    const std::string first = ibms::apply_bms_random(source, {1});
    expect(first.find("#WAV01 kick.wav\n") != std::string::npos, "spaced WAV command stays spaced");
    expect(first.find("#KEEP inside\n") != std::string::npos, "unknown inside the taken branch stays");
    expect(first.find("#00012:02") == std::string::npos, "value 1 drops the other note");
    expect(first.find("#RANDOMPATTERN 9\n") != std::string::npos, "RANDOMPATTERN stays unknown");
    expect(first.find("#RONDAM4\n") != std::string::npos, "compact RONDAM4 stays unknown");
    expect(first.find("#NOTRANDOM 1\n") != std::string::npos, "adjacent NOTRANDOM stays");
    expect(first.find("#00111:01\n") != std::string::npos, "channel row stays a channel row");
    expect(first.find("#RANDOM11:01\n") != std::string::npos, "colon row is not rewritten into RANDOM");

    const std::string second = ibms::apply_bms_random(source, {2});
    expect(second.find("#KEEP inside") == std::string::npos, "unknown inside the skipped branch is omitted");
    expect(second.find("#00012:02\n") != std::string::npos, "value 2 keeps IF2");
    expect(second.find("#RANDOMPATTERN 9\n") != std::string::npos, "RANDOMPATTERN still stays");
    expect(second.find("#RONDAM4\n") != std::string::npos, "RONDAM4 still stays");

    expect_exclusive_branch(
        "ubmplay-random-unknown.bms", {1}, "kick.wav", 2, 1, "snare.wav",
        "value 1 keeps both kick channel rows");
    const auto second_doc = import_applied("ubmplay-random-unknown.bms", {2});
    const auto* second_kick = wav_named(second_doc, "kick.wav");
    const auto* second_snare = wav_named(second_doc, "snare.wav");
    expect(second_snare != nullptr && second_snare->notes.size() == 1 && second_snare->notes[0].x == 2,
           "value 2 keeps the IF2 snare");
    expect(second_kick != nullptr && second_kick->notes.size() == 1 && second_kick->notes[0].y == 960,
           "value 2 still imports the channel row after ENDIF");
}

void ubmplay_crlf_and_raw_bytes_survive()
{
    const std::string unknown = std::string("#UNKNOWN ") + "\x82\xA0";
    const std::string source =
        "#TITLE Bytes\r\n"
        "#WAV01 kick.wav\r\n"
        "#RANDOM2\r\n"
        "#IF1\r\n"
        "#00011:01\r\n" +
        unknown + "\r\n"
        "#IF2\r\n"
        "#00012:02\r\n"
        "#END IF\r\n"
        "#00111:01\r\n";
    const std::string filtered = ibms::apply_bms_random(source, {1});
    expect(filtered.find(unknown + "\r\n") != std::string::npos, "unknown line keeps raw bytes and CRLF");
    expect(filtered.find("#WAV01 kick.wav\r\n") != std::string::npos, "CRLF WAV line stays intact");
    expect(filtered.find("#00012:02") == std::string::npos, "value 1 still drops IF2");
    expect(filtered.find("#00111:01\r\n") != std::string::npos, "END IF resumes the following CRLF note");

    const auto document = ibms::BmsDocument::from_bytes(filtered);
    expect(document.expansion().find(unknown) != std::string::npos, "imported expansion keeps the unknown bytes");
    expect(document.expansion().find("\r\n") != std::string::npos, "imported expansion keeps CRLF");
    const auto imported = ibms::bmson_from_bms(document, options_for("ubmplay-random-compact.bms"));
    const auto* kick = wav_named(imported, "kick.wav");
    expect(kick != nullptr && kick->notes.size() == 2, "CRLF chart still imports both kept notes");
}

void ubmplay_setrandom_else_endrandom_regression()
{
    const std::string source = load_fixture("ubmplay-random-setrandom.bms");
    const auto maxima = ibms::collect_bms_random_maxima(source);
    expect(maxima.empty(), "SETRANDOM is not a RANDOM maximum");

    const auto document = import_applied("ubmplay-random-setrandom.bms", {});
    const auto* kick = wav_named(document, "kick.wav");
    const auto* snare = wav_named(document, "snare.wav");
    expect(snare != nullptr && snare->notes.size() == 1 && snare->notes[0].x == 2,
           "SETRANDOM 2 keeps ELSEIF 2");
    expect(kick != nullptr && kick->notes.size() == 1 && kick->notes[0].y == 960,
           "ELSE is skipped and the note after ENDRANDOM remains");
    expect(ibms::apply_bms_random(source, {}).find("#00016:01") == std::string::npos,
           "ELSE scratch does not leak");

    const std::string set_one =
        "#WAV01 kick.wav\n#WAV02 snare.wav\n#SETRANDOM 1\n#IF 1\n#00011:01\n"
        "#ELSEIF 2\n#00012:02\n#ELSE\n#00016:01\n#ENDIF\n#ENDRANDOM\n#00111:01\n";
    const auto one = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(set_one, {})),
        options_for("ubmplay-random-setrandom.bms"));
    const auto* one_kick = wav_named(one, "kick.wav");
    const auto* one_snare = wav_named(one, "snare.wav");
    expect(one_kick != nullptr && one_kick->notes.size() == 2, "SETRANDOM 1 keeps IF 1 and the note after ENDRANDOM");
    expect(one_snare != nullptr && one_snare->notes.empty(), "SETRANDOM 1 drops ELSEIF 2");

    const std::string end_random =
        "#WAV01 kick.wav\n#RANDOM 1\n#IF 2\n#00012:02\n#ENDRANDOM\n#00011:01\n";
    const std::string ended = ibms::apply_bms_random(end_random, {1});
    expect(ended.find("#ENDRANDOM") == std::string::npos, "ENDRANDOM is still a control line");
    expect(ended.find("#00012:02") == std::string::npos, "failed IF stays skipped");
    expect(ended.find("#00011:01\n") != std::string::npos, "ENDRANDOM restores the following note");
}

void ubmplay_oversized_random_does_not_select_both()
{
    const std::string at_limit =
        "#WAV01 kick.wav\n#RANDOM 2147483647\n#IF 2\n#00011:01\n#ENDIF\n";
    const auto limit_maxima = ibms::collect_bms_random_maxima(at_limit);
    expect(limit_maxima.size() == 1 && limit_maxima[0] == 2147483647, "INT_MAX is a usable RANDOM maximum");
    const auto limit_doc = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(at_limit, {2})),
        options_for("ubmplay-random-compact.bms"));
    const auto* limit_kick = wav_named(limit_doc, "kick.wav");
    expect(limit_kick != nullptr && limit_kick->notes.size() == 1, "INT_MAX still accepts value 2");

    const std::string truncated =
        "#WAV01 kick.wav\n#WAV02 snare.wav\n#RANDOM 4294967298\n#IF 1\n#00011:01\n#IF 2\n#00012:02\n#ENDIF\n";
    const auto truncated_maxima = ibms::collect_bms_random_maxima(truncated);
    expect(truncated_maxima.size() == 1 && truncated_maxima[0] == 1,
           "a long that does not fit in int is an invalid maximum");
    const auto truncated_doc = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(truncated, {2})),
        options_for("ubmplay-random-compact.bms"));
    const auto* kick = wav_named(truncated_doc, "kick.wav");
    const auto* snare = wav_named(truncated_doc, "snare.wav");
    expect(kick != nullptr && kick->notes.size() == 1, "invalid huge RANDOM resolves inside 1..1");
    expect(snare != nullptr && snare->notes.empty(), "truncated long is not RANDOM 2");

    const std::string bomb =
        "#WAV01 kick.wav\n#WAV02 snare.wav\n#RANDOM " + std::string(64, '9') +
        "\n#IF 1\n#00011:01\n#IF 2\n#00012:02\n#ENDIF\n";
    const auto bomb_doc = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(ibms::apply_bms_random(bomb, {2})),
        options_for("ubmplay-random-compact.bms"));
    const auto* bomb_kick = wav_named(bomb_doc, "kick.wav");
    const auto* bomb_snare = wav_named(bomb_doc, "snare.wav");
    expect(bomb_kick != nullptr && bomb_kick->notes.size() == 1, "digit bomb keeps a single branch");
    expect(bomb_snare != nullptr && bomb_snare->notes.empty(), "digit bomb does not keep both branches");
}

void channel_rows_without_random_are_unchanged()
{
    const std::string rows = "#WAV01 kick.wav\n#00011:01\n#00111:01\n";
    expect(ibms::apply_bms_random(rows, {1, 2}) == rows, "channel rows are copied unchanged");
    const std::string end_foo = "#END FOO\n#WAV01 kick.wav\n#00011:01\n";
    const std::string kept = ibms::apply_bms_random(end_foo, {});
    expect(kept.find("#END FOO\n") != std::string::npos, "END FOO stays in the chart text");
    const auto document = ibms::bmson_from_bms(
        ibms::BmsDocument::from_bytes(kept), options_for("ubmplay-random-compact.bms"));
    const auto* kick = wav_named(document, "kick.wav");
    expect(kick != nullptr && kick->notes.size() == 1, "END FOO does not hide the following note");
}

void import_bga_events_and_headers()
{
    const auto document = import_fixture("bga-and-layer.bms");
    expect(document.bga_headers().size() == 3, "BMP00 / 01 / 02");
    expect(document.bga_headers()[0].id == 0 && document.bga_headers()[0].name == "miss.png", "BMP00");
    expect(document.bga_headers()[1].id == 1 && document.bga_headers()[1].name == "bg.png", "BMP01");
    expect(document.bga_headers()[2].id == 2 && document.bga_headers()[2].name == "layer.png", "BMP02");
    expect(document.bga_events().size() == 1, "one BGA event");
    expect(document.bga_events()[0].y == 0 && document.bga_events()[0].id == 1, "04 at y=0 id=1");
    expect(document.layer_events().size() == 1, "one layer event");
    expect(document.layer_events()[0].y == 960 && document.layer_events()[0].id == 2, "07 at y=960 id=2");
    expect(document.poor_events().size() == 1, "miss default");
    expect(document.poor_events()[0].y == 0 && document.poor_events()[0].id == 0, "BMP00 at y=0");
    const std::string json = document.to_json();
    expect(json.find("\"bga_header\"") != std::string::npos, "writes 1.0 header key");
    expect(json.find("\"poor_events\"") != std::string::npos, "writes 1.0 poor key");
}

}  // namespace

int main()
{
    try {
        lane_map_mode_7k();
        minimal_7k_fixture();
        scratch_and_key_lanes();
        measure_one_and_long_note();
        detect_and_import_other_modes();
        random_if_selects_branch();
        ubmplay_compact_random_selects_one_branch();
        ubmplay_nested_outer_skips_inner();
        ubmplay_nested_inactive_inherits();
        ubmplay_rondam_and_end_if_resume();
        ubmplay_compact_case_is_insensitive();
        ubmplay_unknown_neighbors_stay_literal();
        ubmplay_crlf_and_raw_bytes_survive();
        ubmplay_setrandom_else_endrandom_regression();
        ubmplay_oversized_random_does_not_select_both();
        channel_rows_without_random_are_unchanged();
        import_bga_events_and_headers();
    } catch (const std::exception& exception) {
        std::cerr << "Unhandled exception: " << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_bmson_from_bms_tests passed\n";
    return 0;
}
