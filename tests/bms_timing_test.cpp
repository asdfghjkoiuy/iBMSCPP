#include <ibms/bms_document.hpp>

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
    expect(std::abs(actual - expected) < 1e-12, expression);
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

std::string load_fixture(const std::filesystem::path& fixture_directory, std::string_view filename)
{
    const std::filesystem::path path = fixture_directory / filename;
    std::ifstream input(path, std::ios::binary);
    if (!input)
        throw std::runtime_error("unable to open timing fixture: " + path.string());
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}

void derived_timing_uses_exact_positions(const std::filesystem::path& fixture_directory)
{
    auto default_document = ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, "01-default-bpm.bms"));
    const ibms::BmsTiming& default_timing = default_document.timing();
    expect(default_timing.available, "default timing is available");
    expect(default_timing.initial_bpm == ibms::BeatPosition{120}, "default fixture has its declared BPM");
    expect_near(*default_timing.seconds_at(ibms::BeatPosition{4}, false), 2.0, "four beats at 120 BPM take two seconds");

    auto ratio_document = ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, "02-ratio-future-bpm-stop.bms"));
    const ibms::BmsTiming& ratio_timing = ratio_document.timing();
    expect(ratio_timing.available && ratio_timing.events.size() == 2, "ratio fixture derives two timing events");
    expect(ratio_timing.events[0].measure == 1 && ratio_timing.events[0].fraction == ibms::BeatPosition{} &&
               ratio_timing.events[0].beat == ibms::BeatPosition{4},
           "timing events expose exact measure and fraction coordinates");
    expect_near(*ratio_timing.seconds_at(ibms::BeatPosition{3}, false), 1.5,
                "querying before a future BPM does not integrate that future segment");
    expect_near(*ratio_timing.seconds_at(ibms::BeatPosition{12}, false), 4.25,
                "measure ratios, BPM, and STOP contribute to later time");

    auto stop_document = ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, "03-stop-same-beat.bms"));
    const ibms::BmsTiming& stop_timing = stop_document.timing();
    expect_near(*stop_timing.seconds_at(ibms::BeatPosition{4}, false), 2.0,
                "time before a STOP is the arrival time at that beat");
    expect_near(*stop_timing.seconds_at(ibms::BeatPosition{4}, true), 3.0,
                "time after a STOP includes its duration");
    expect_near(*stop_timing.time_before_stop(ibms::BeatPosition{4}), 2.0,
                "named pre-stop query returns the arrival time");
    expect_near(*stop_timing.time_after_stop(ibms::BeatPosition{4}), 3.0,
                "named post-stop query includes the STOP duration");
    expect_near(*stop_timing.seconds_at(ibms::BeatPosition{5}, false), 3.5,
                "time after a STOP advances using the active BPM");

    auto same_beat_document = ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, "04-same-beat-order.bms"));
    const ibms::BmsTiming& same_beat_timing = same_beat_document.timing();
    expect(same_beat_timing.available, "same-beat timing profile is available");
    expect_near(*same_beat_timing.seconds_at(ibms::BeatPosition{4}, true), 2.4,
                "last BPM and last STOP source events win, with BPM applied before STOP");

    for (const std::string_view filename : {"05-invalid-numeric-undefined.bms", "08-bom-case-insensitive.bms",
                                            "09-malformed-timing-lines.bms", "11-base62-unavailable.bms",
                                            "12-measure-overflow.bms", "14-empty-initial-bpm.bms"}) {
        const ibms::BmsDocument document = ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, filename));
        const ibms::BmsTiming& timing = document.timing();
        if (filename == "08-bom-case-insensitive.bms")
            expect(timing.available, "BOM-prefixed, case-insensitive timing syntax is accepted");
        else {
            const std::string expression = std::string(filename) + " is unavailable with diagnostics";
            expect(!timing.available && !timing.diagnostics.empty(), expression);
            expect(timing.events.empty() && timing.points.empty(),
                   std::string(filename) + " has no partial timing events or prefix points");
        }
    }

    const ibms::BmsDocument zero_stop_document =
        ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, "10-zero-stop.bms"));
    const ibms::BmsTiming& zero_stop = zero_stop_document.timing();
    expect(zero_stop.available, "a zero STOP definition is valid");
    const ibms::BmsDocument tiny_stop_document =
        ibms::BmsDocument::from_bytes(load_fixture(fixture_directory, "13-tiny-stop.bms"));
    const ibms::BmsTiming& tiny_stop = tiny_stop_document.timing();
    expect(tiny_stop.available && tiny_stop.seconds_at(ibms::BeatPosition{1}, false).has_value(),
           "a tiny exact STOP does not overflow timing derivation");

    const ibms::BmsDocument bare_stop_document = ibms::BmsDocument::from_bytes("#BPM 120\n#STOP\n");
    expect(!bare_stop_document.timing().available,
           "a bare STOP definition is diagnosed instead of being silently ignored");
}

void timing_edits_preserve_raw_framing_and_history()
{
    auto initial = ibms::BmsDocument::from_bytes("#BPM\n");
    initial.set_initial_bpm("120.5");
    expect(initial.serialize() == "#BPM 120.5\n", "initial BPM adds a separator to a bare directive");
    expect(initial.undo() && initial.serialize() == "#BPM\n", "undo restores a bare BPM directive exactly");

    const std::string bom{"\xEF\xBB\xBF", 3};
    const std::string ratio_source = bom + "\t#00102: \t0.5 \t\r\n#00111:0100\r\n";
    auto ratio = ibms::BmsDocument::from_bytes(ratio_source);
    ratio.set_measure_ratio(1, "1.5");
    expect(ratio.serialize() == bom + "\t#00102: \t1.5 \t\r\n#00111:0100\r\n",
           "measure-ratio editing replaces only the numeric payload");
    expect(ratio.undo() && ratio.serialize() == ratio_source, "ratio undo restores BOM, indentation, and trailing whitespace");

    auto overflow = ibms::BmsDocument::from_bytes("#00011:0100\n");
    const std::string overflow_source = overflow.serialize();
    expect_throws<std::overflow_error>([&overflow] { overflow.set_measure_ratio(0, "4611686018427387904"); },
                                       "ratio overflow is rejected before commit");
    expect(overflow.serialize() == overflow_source && !overflow.can_undo(),
           "rejected ratio overflow keeps source and history unchanged");

    auto events = ibms::BmsDocument::from_bytes("#BPM 120\n");
    events.insert_timing_event(0, "08", ibms::BeatPosition{}, "240");
    const std::string after_bpm = events.serialize();
    expect(after_bpm.find("#BPM01 240") != std::string::npos && after_bpm.find("#00008:01") != std::string::npos,
           "extended BPM insertion allocates a fresh resource and sparse row");
    events.replace_timing_event(0, "08", ibms::BeatPosition{}, "180");
    const std::string after_replace = events.serialize();
    expect(after_replace.find("#BPM01 240") != std::string::npos && after_replace.find("#BPM02 180") != std::string::npos &&
               after_replace.find("#00008:02") != std::string::npos,
           "extended BPM replacement allocates a fresh resource and leaves the old definition untouched");
    expect(events.timing().events.size() == 1,
           "indexed BPM replacement preserves the timing-event count at its original coordinate");
    events.erase_timing_event(0, "08", ibms::BeatPosition{});
    expect(events.timing().events.empty(), "an indexed timing event can be erased after replacement");
    expect(events.undo() && events.serialize() == after_replace,
           "erase undo restores the replaced indexed timing event without ambiguity");
    expect(events.undo() && events.serialize() == after_bpm, "replacement undo removes definition and restores source token together");
    events.insert_timing_event(0, "09", ibms::BeatPosition{1, 2}, "0");
    expect(events.serialize().find("#STOP01 0") != std::string::npos, "zero STOP insertion uses a nonzero resource token");
    events.insert_timing_event(0, "03", ibms::BeatPosition{1, 3}, "180");
    expect(events.serialize().find("#00003:00B400") != std::string::npos,
           "channel 03 insertion writes an exact hexadecimal BPM token");
    expect_throws<std::invalid_argument>([&events] {
        events.insert_timing_event(0, "03", ibms::BeatPosition{2, 3}, "256");
    }, "channel 03 rejects BPM values above FF");
    events.erase_timing_event(0, "03", ibms::BeatPosition{1, 3});
    expect(events.serialize().find("#00003:000000") != std::string::npos,
           "timing erase replaces only the selected token with zero");
    events.insert_timing_event(0, "SC", ibms::BeatPosition{1, 2}, "0.5");
    expect(events.serialize().find("#SCROLL01 0.5") != std::string::npos &&
               events.serialize().find("#000SC:0001") != std::string::npos,
           "SCROLL insertion allocates #SCROLL and a sparse SC row");
    events.insert_timing_event(0, "SC", ibms::BeatPosition{1, 4}, "-0.5");
    expect(events.serialize().find("#SCROLL02 -0.5") != std::string::npos &&
               events.serialize().find("#000SC:") != std::string::npos,
           "SCROLL insertion keeps a negative decimal from PanelEvents PE-025");
    expect_throws<std::invalid_argument>([&events] {
        events.insert_timing_event(0, "03", ibms::BeatPosition{3, 4}, "-120");
    }, "channel 03 still rejects a leading minus");
    events.erase_timing_event(0, "SC", ibms::BeatPosition{1, 2});
    expect(events.serialize().find("#000SC:") == std::string::npos ||
               events.serialize().find("#000SC:0000") != std::string::npos,
           "SCROLL erase clears the SC cell");

    auto protected_chart = ibms::BmsDocument::from_bytes("#BASE 62\n#BPM 120\n");
    expect_throws<std::logic_error>([&protected_chart] {
        protected_chart.insert_timing_event(0, "08", ibms::BeatPosition{}, "180");
    }, "timing insertion rejects a chart with unsupported token semantics");
}

}  // namespace

int main(int argc, char** argv)
{
    if (argc != 2) {
        std::cerr << "expected timing fixture directory argument\n";
        return 2;
    }
    const std::filesystem::path fixture_directory = argv[1];
    try {
        derived_timing_uses_exact_positions(fixture_directory);
        timing_edits_preserve_raw_framing_and_history();
    } catch (const std::exception& exception) {
        std::cerr << "Unexpected test exception: " << exception.what() << '\n';
        return 1;
    }
    return failures == 0 ? 0 : 1;
}
