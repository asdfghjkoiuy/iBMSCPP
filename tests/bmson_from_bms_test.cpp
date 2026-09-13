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
