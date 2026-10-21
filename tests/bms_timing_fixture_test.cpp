#include <ibms/bms_document.hpp>

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

using ibms::BeatPosition;
using ibms::BmsDocument;
using ibms::BmsTimingEvent;
using ibms::BmsTimingEventKind;

int failures = 0;

BeatPosition beat(std::int64_t numerator, std::int64_t denominator = 1) {
    return BeatPosition{numerator, denominator};
}

void expect(bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

template <typename Function>
void expect_reject(Function&& function, const std::string& message) {
    try {
        function();
        expect(false, message + " (no exception)");
    } catch (const std::exception&) {
    } catch (...) {
        expect(false, message + " (non-standard exception)");
    }
}

std::string read_fixture(const std::filesystem::path& directory, std::string_view name) {
    const auto path = directory / std::string{name};
    std::ifstream input(path, std::ios::binary);
    if (!input)
        throw std::runtime_error("fixture is missing: " + path.string());
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}

const BmsTimingEvent* find_event(const ibms::BmsTiming& timing, std::string_view channel,
                                 int measure, BeatPosition fraction) {
    for (const auto& event : timing.events) {
        if (event.channel == channel && event.measure == measure && event.fraction == fraction)
            return &event;
    }
    return nullptr;
}

void expect_seconds(const ibms::BmsTiming& timing, BeatPosition position, double expected,
                    std::string_view label, double tolerance = 1e-12) {
    const auto actual = timing.seconds_at(position, false);
    expect(actual.has_value(), std::string{label} + ": seconds_at is available");
    if (actual.has_value())
        expect(std::abs(*actual - expected) <= tolerance,
               std::string{label} + ": exact timeline oracle agrees within double output tolerance");
}

void check_fixture_bytes_and_timing(const std::filesystem::path& directory, std::string_view filename) {
    const std::string source = read_fixture(directory, filename);
    auto document = BmsDocument::from_bytes(source);
    expect(document.serialize() == source, std::string{filename} + ": source bytes round-trip before edits");

    if (filename == "12-measure-overflow.bms") {
        bool threw = false;
        try {
            const auto& timing = document.timing();
            expect(!timing.available, "12: overflow timing is unavailable");
            expect(!timing.diagnostics.empty(), "12: overflow timing has a diagnostic");
        } catch (const std::exception& exception) {
            threw = true;
            expect(false, std::string{"12: timing() must return an unavailable snapshot, not throw: "} + exception.what());
        } catch (...) {
            threw = true;
            expect(false, "12: timing() must not throw an unknown exception");
        }
        expect(!threw, "12: reading overflow timing does not throw");
        return;
    }

    const auto& timing = document.timing();

    if (filename == "01-default-bpm.bms") {
        expect(timing.available, "01: default timing is available");
        expect(timing.initial_bpm == beat(120), "01: default initial BPM is 120");
        expect_seconds(timing, beat(0), 0.0, "01 beat 0");
        expect_seconds(timing, beat(4), 2.0, "01 beat 4");
        expect_seconds(timing, beat(5), 2.5, "01 beat 5");
    } else if (filename == "02-ratio-future-bpm-stop.bms") {
        expect(timing.available, "02: ratio/BPM/STOP timing is available");
        expect_seconds(timing, beat(3), 1.5, "02 query before future BPM");
        expect_seconds(timing, beat(4), 2.0, "02 BPM change beat");
        expect_seconds(timing, beat(5), 2.25, "02 beat 5");
        expect_seconds(timing, beat(6), 2.5, "02 exact STOP arrival before stop");
        expect_seconds(timing, beat(7), 3.0, "02 after STOP");
        expect_seconds(timing, beat(12), 4.25, "02 later measure ratio");
        const auto* bpm = find_event(timing, "08", 1, beat(0));
        const auto* stop = find_event(timing, "09", 2, beat(0));
        expect(bpm && bpm->beat == beat(4) && bpm->value == beat(240), "02: BPM event has exact beat/value");
        expect(stop && stop->beat == beat(6) && stop->value == beat(48), "02: STOP event has exact beat/value");
    } else if (filename == "03-stop-same-beat.bms") {
        expect(timing.available, "03: STOP timing is available");
        expect_seconds(timing, beat(4), 2.0, "03 exact STOP arrival");
        expect_seconds(timing, beat(5), 3.5, "03 after STOP");
    } else if (filename == "04-same-beat-order.bms") {
        expect(timing.available, "04: duplicate timing rows remain usable");
        expect(timing.events.size() == 6, "04: all duplicate raw timing events remain visible");
        const auto* bpm03_at_zero = find_event(timing, "03", 0, beat(0));
        const auto* bpm08_at_zero = find_event(timing, "08", 0, beat(0));
        const auto* bpm03_at_four = find_event(timing, "03", 1, beat(0));
        const auto* bpm08_at_four = find_event(timing, "08", 1, beat(0));
        const auto* stop_first = find_event(timing, "09", 1, beat(0));
        expect(bpm03_at_zero && bpm03_at_zero->token == "78" && bpm03_at_zero->value == beat(0x78),
               "04: channel 03 keeps its uppercase token and hex value at beat 0");
        expect(bpm08_at_zero && bpm08_at_zero->token == "01" && bpm08_at_zero->value == beat(240),
               "04: channel 08 event at beat 0 retains its own definition");
        expect(bpm03_at_four && bpm03_at_four->token == "96" && bpm03_at_four->value == beat(150),
               "04: channel 03 event at the shared BPM/STOP beat is retained");
        expect(bpm08_at_four && bpm08_at_four->token == "02" && bpm08_at_four->value == beat(300),
               "04: channel 08 event at the shared BPM/STOP beat is retained");
        expect(stop_first && stop_first->token == "01" && stop_first->value == beat(48),
               "04: first STOP remains observable before effective last-source selection");
        expect_seconds(timing, beat(3), 1.5, "04 before same-beat BPM and STOP");
        expect_seconds(timing, beat(4), 2.0, "04 exact same-beat arrival before STOP");
        const auto at_stop_after = timing.seconds_at(beat(4), true);
        expect(at_stop_after.has_value() && std::abs(*at_stop_after - 2.4) <= 1e-12,
               "04 same-beat BPM is applied before STOP duration");
        expect_seconds(timing, beat(5), 2.6, "04 duplicate STOP last-source-wins, not VB sum");
        expect(!timing.diagnostics.empty(), "04: duplicate timing selection retains diagnostics");
    } else if (filename == "05-invalid-numeric-undefined.bms") {
        expect(!timing.available, "05: invalid numeric/undefined timing is unavailable");
        expect(!timing.seconds_at(beat(0), false).has_value(), "05: unavailable timing does not default to 120 BPM");
        expect(timing.events.empty(), "05: invalid timing does not expose a partial evaluated event list");
    } else if (filename == "06-shared-resources.bms") {
        expect(timing.available, "06: shared definitions are available");
        expect_seconds(timing, beat(4), 5.0 / 3.0, "06 shared BPM at beat 4");
        expect_seconds(timing, beat(5), 7.0 / 3.0, "06 shared STOP at beat 4");
        const auto* second_bpm = find_event(timing, "08", 1, beat(0));
        const auto* second_stop = find_event(timing, "09", 1, beat(0));
        expect(second_bpm && second_bpm->value == beat(180), "06: second BPM event uses the shared definition");
        expect(second_stop && second_stop->value == beat(48), "06: second STOP event uses the shared definition");
    } else if (filename == "07-runtime-resource-exhaustion-seed.bms") {
        expect(timing.available, "07: seed is available before generated stress input");
    } else if (filename == "08-bom-case-insensitive.bms") {
        expect(timing.available, "08: BOM/indented case-insensitive timing is available");
        expect(timing.initial_bpm == beat(60), "08: BOM followed by spaces still recognizes #bpm 60");
        const auto* stop = find_event(timing, "09", 0, beat(0));
        expect(stop && stop->token == "A1" && stop->value == beat(48),
               "08: lowercase #stopa1 preserves canonical token and definition value");
        expect_seconds(timing, beat(0), 0.0, "08 exact STOP arrival");
        const auto after = timing.seconds_at(beat(0), true);
        expect(after.has_value() && *after == 1.0, "08 STOP at BPM 60 contributes one second after arrival");
        expect(document.serialize().substr(0, 3) == std::string("\xef\xbb\xbf", 3), "08: BOM remains raw source data");
    } else if (filename == "09-malformed-timing-lines.bms") {
        expect(!timing.available, "09: aggregate malformed 03/08/02 rows make timing unavailable");
        expect(!timing.seconds_at(beat(0), false).has_value(), "09: malformed rows are not silently skipped");
        expect(!timing.diagnostics.empty(), "09: aggregate malformed input retains at least one diagnostic");
    } else if (filename == "10-zero-stop.bms") {
        expect(timing.available, "10: zero STOP definition is valid");
        const auto* stop = find_event(timing, "09", 0, beat(0));
        expect(stop && stop->value == beat(0), "10: zero STOP value is retained as an event");
        expect_seconds(timing, beat(1), 0.5, "10 zero STOP has no duration");
    } else if (filename == "11-base62-unavailable.bms") {
        expect(!timing.available, "11: #BASE 62 is unavailable in this Base36 timing profile");
        expect(!timing.diagnostics.empty(), "11: unsupported base has a diagnostic");
    } else if (filename == "13-tiny-stop.bms") {
        expect(timing.available, "13: tiny positive STOP remains available");
        const auto* stop = find_event(timing, "09", 0, beat(0));
        expect(stop && stop->value == beat(1, 1'000'000'000'000'000'000LL),
               "13: tiny STOP is retained exactly as a rational value");
        const auto after = timing.seconds_at(beat(0), true);
        constexpr double expected_seconds = 1.0 / (48.0 * 1'000'000'000'000'000'000.0);
        expect(after.has_value() && std::isfinite(*after) && *after > 0.0,
               "13: tiny STOP produces a finite positive seconds value");
        if (after.has_value())
            expect(std::abs(*after - expected_seconds) <= 1e-30,
                   "13: tiny STOP seconds match raw-value/48 at BPM 60");
    } else if (filename == "14-empty-initial-bpm.bms") {
        expect(!timing.available, "14: empty #BPM definitions do not fall back to 120 BPM");
        expect(!timing.diagnostics.empty(), "14: empty #BPM has a diagnostic");
        expect(timing.diagnostics.front().source_line < document.line_count(),
               "14: empty #BPM diagnostic points to a source line");
    }
}

void empty_initial_bpm_forms_are_individually_unavailable() {
    constexpr std::string_view cases[] = {
        "#BPM\n#00011:0100\n",
        "#BPM   \n#00011:0100\n",
    };
    constexpr std::string_view labels[] = {"lone #BPM", "space-only #BPM"};
    for (std::size_t index = 0; index < 2; ++index) {
        auto document = BmsDocument::from_bytes(std::string{cases[index]});
        const auto& timing = document.timing();
        expect(!timing.available, std::string{labels[index]} + ": timing is unavailable");
        expect(!timing.diagnostics.empty(), std::string{labels[index]} + ": timing has a diagnostic");
        expect(!timing.seconds_at(beat(0), false).has_value(),
               std::string{labels[index]} + ": timing does not fall back to default 120");
    }
}

void malformed_timing_rows_are_individually_unavailable() {
    constexpr std::string_view cases[] = {
        "#BPM 120\n#00003\n",
        "#BPM 120\n#00008:\n",
        "#BPM 120\n#00002:bad\n",
    };
    constexpr std::string_view labels[] = {"malformed 03", "malformed 08", "malformed 02"};
    for (std::size_t index = 0; index < 3; ++index) {
        auto document = BmsDocument::from_bytes(std::string{cases[index]});
        bool threw = false;
        try {
            const auto& timing = document.timing();
            expect(!timing.available, std::string{labels[index]} + ": timing is unavailable");
            expect(!timing.diagnostics.empty(), std::string{labels[index]} + ": timing has a diagnostic");
            expect(!timing.seconds_at(beat(0), false).has_value(),
                   std::string{labels[index]} + ": unavailable timing has no seconds oracle");
        } catch (const std::exception& exception) {
            threw = true;
            expect(false, std::string{labels[index]} + ": timing() does not throw: " + exception.what());
        } catch (...) {
            threw = true;
            expect(false, std::string{labels[index]} + ": timing() does not throw an unknown exception");
        }
        expect(!threw, std::string{labels[index]} + ": runtime case completes without throwing");
    }
}

std::string base36(std::size_t value) {
    constexpr std::string_view digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    std::string result(2, '0');
    result[0] = digits[value / 36];
    result[1] = digits[value % 36];
    return result;
}

void runtime_resource_stress() {
    ibms::IndexedTimingRadixScope scope(true, true);
    std::string source = "#TITLE Generated timing resources\n#BPM 120\n";
    for (std::size_t id = 0; id < 1296; ++id) {
        source += "#BPM" + base36(id) + " 120\n";
        source += "#STOP" + base36(id) + " 1\n";
    }
    source += "#00008:01\n#00009:01\n";

    bool threw = false;
    try {
        auto document = BmsDocument::from_bytes(source);
        const auto& timing = document.timing();
        expect(timing.available, "generated 1296-entry timing resource input remains available");
        expect(timing.events.size() == 2, "generated resource input emits only its two referenced events");

        document.set_header("TITLE", "changed");
        expect(document.undo(), "resource exhaustion setup creates a redo record");
        const std::string before_failure = document.serialize();
        const bool dirty_before = document.dirty();
        const bool undo_before = document.can_undo();
        const bool redo_before = document.can_redo();
        expect_reject([&] {
            document.insert_timing_event(1, "08", beat(0), "240");
        }, "inserting a new indexed BPM fails when all 1296 ids are reserved");
        expect(document.serialize() == before_failure && document.dirty() == dirty_before &&
                   document.can_undo() == undo_before && document.can_redo() == redo_before,
               "failed indexed BPM insertion preserves bytes, dirty, undo, and redo state");
        expect_reject([&] {
            document.replace_timing_event(0, "08", beat(0), "240");
        }, "replacing an indexed BPM fails when no replacement id is available");
        expect(document.serialize() == before_failure && document.dirty() == dirty_before &&
                   document.can_undo() == undo_before && document.can_redo() == redo_before,
               "failed indexed BPM replacement preserves bytes, dirty, undo, and redo state");
    } catch (const std::exception& exception) {
        threw = true;
        expect(false, std::string{"generated timing resources do not throw: "} + exception.what());
    } catch (...) {
        threw = true;
        expect(false, "generated timing resources do not throw an unknown exception");
    }
    expect(!threw, "generated resource stress completes without an exception");
}

void timing_edit_preservation_and_history(const std::filesystem::path& directory) {
    const std::string shared_source = read_fixture(directory, "06-shared-resources.bms");
    auto shared = BmsDocument::from_bytes(shared_source);
    const std::size_t original_event_count = shared.timing().events.size();
    shared.replace_timing_event(0, "08", beat(0), "240");
    expect(shared.timing().events.size() == original_event_count,
           "replacing one timing event does not append a duplicate event row");
    expect(shared.serialize().find("#BPM01 180") != std::string::npos,
           "replacing one timing event preserves the shared BPM definition bytes");
    expect(shared.serialize().find("#STOP01 48") != std::string::npos,
           "replacing one timing event preserves the shared STOP definition bytes");
    const auto* replaced_bpm = find_event(shared.timing(), "08", 0, beat(0));
    const auto* untouched_bpm = find_event(shared.timing(), "08", 1, beat(0));
    expect(replaced_bpm && replaced_bpm->value == beat(240),
           "replacing one timing event changes only the requested event value");
    expect(untouched_bpm && untouched_bpm->value == beat(180),
           "replacing one timing event does not change the other event using the resource");

    shared.replace_timing_event(0, "08", beat(0), "300");
    expect(shared.timing().events.size() == original_event_count,
           "replacing the same coordinate again keeps the event count stable");
    replaced_bpm = find_event(shared.timing(), "08", 0, beat(0));
    expect(replaced_bpm && replaced_bpm->value == beat(300),
           "replacing the same coordinate again updates the existing event");
    expect(shared.undo(), "second timing replacement can be undone");
    expect(shared.undo(), "first timing replacement can be undone");
    expect(shared.serialize() == shared_source, "timing replacement undo restores exact source bytes");

    auto erase_replace = BmsDocument::from_bytes(shared_source);
    erase_replace.erase_timing_event(0, "08", beat(0));
    expect(erase_replace.timing().events.size() + 1 == original_event_count,
           "erasing one timing event removes only that event");
    erase_replace.replace_timing_event(0, "08", beat(0), "240");
    expect(erase_replace.timing().events.size() == original_event_count,
           "replacing an erased coordinate recreates one event without duplication");
    expect(find_event(erase_replace.timing(), "08", 0, beat(0)) != nullptr,
           "replacing an erased coordinate succeeds at the same position");
    expect(find_event(erase_replace.timing(), "08", 1, beat(0)) != nullptr,
           "erase/replace leaves the other shared event present");

    auto history = BmsDocument::from_bytes(shared_source);
    history.set_header("TITLE", "changed");
    expect(history.undo(), "history setup creates a redo record");
    const std::string before_failed_insert = history.serialize();
    expect(history.can_redo(), "history setup has a pending redo");
    expect_reject([&] {
        history.insert_timing_event(0, "08", beat(1, 65537), "240");
    }, "timing source/id exhaustion rejects insertion");
    expect(history.serialize() == before_failed_insert, "failed timing insertion preserves source bytes");
    expect(history.can_redo(), "failed timing insertion preserves redo history");
    expect(history.redo(), "preserved redo remains executable after failed timing insertion");

    const std::string initial_bpm_source = "#BPM\n#00011:0100\n";
    auto initial_bpm = BmsDocument::from_bytes(initial_bpm_source);
    initial_bpm.set_initial_bpm("120");
    expect(initial_bpm.serialize() == "#BPM 120\n#00011:0100\n",
           "setting a lone #BPM inserts the required separator rather than producing #BPM120");
    expect(initial_bpm.undo() && initial_bpm.serialize() == initial_bpm_source,
           "initial BPM formatting edit undo restores exact source bytes");

    const std::string ratio_source = std::string("\xef\xbb\xbf", 3) +
        "  #00002:1  \r\n#BPM 120\r\n#00008:0100\r\n";
    auto ratio = BmsDocument::from_bytes(ratio_source);
    ratio.set_measure_ratio(0, "2");
    expect(ratio.serialize() == std::string("\xef\xbb\xbf", 3) +
               "  #00002:2  \r\n#BPM 120\r\n#00008:0100\r\n",
           "measure-ratio edit changes only the value and preserves BOM, indent, spaces, and CRLF");
    expect(ratio.undo() && ratio.serialize() == ratio_source,
           "measure-ratio edit undo restores exact source bytes");

    const std::string base62_source = read_fixture(directory, "11-base62-unavailable.bms");
    auto base62 = BmsDocument::from_bytes(base62_source);
    base62.mark_saved();
    const std::string base62_before = base62.serialize();
    expect_reject([&] {
        base62.insert_timing_event(0, "08", beat(0), "240");
    }, "timing insertion on #BASE 62 rejects instead of allocating a Base36 resource");
    expect(base62.serialize() == base62_before && !base62.dirty() &&
               !base62.can_undo() && !base62.can_redo(),
           "#BASE 62 insertion rejection preserves bytes, dirty, undo, and redo state");

    auto overflow = BmsDocument::from_bytes("#TITLE Ratio overflow\n#00002:1\n#00011:0100\n");
    overflow.mark_saved();
    const std::string overflow_before = overflow.serialize();
    expect_reject([&] {
        overflow.set_measure_ratio(0, "9223372036854775807");
    }, "enormous new measure ratio rejects before committing an invalid timeline");
    expect(overflow.serialize() == overflow_before && !overflow.dirty() && !overflow.can_undo(),
           "failed measure-ratio overflow is atomic and leaves history unchanged");
}

void huge_int64_measure_ratio_timing_is_unavailable() {
    auto document = BmsDocument::from_bytes("#TITLE Huge ratio\n#BPM 120\n#00002:9223372036854775807\n");
    bool threw = false;
    try {
        const auto& timing = document.timing();
        expect(!timing.available, "9223372036854775807 measure ratio makes timing unavailable");
        expect(timing.events.empty() && timing.points.empty(),
               "INT64_MAX measure ratio does not expose a partial timing snapshot");
        bool mentions_range = false;
        for (const auto& diagnostic : timing.diagnostics) {
            mentions_range = mentions_range
                || diagnostic.message.find("measure ratio exceeds the representable beat range") != std::string::npos;
        }
        expect(mentions_range,
               "9223372036854775807 is accepted as an int64 decimal, then rejected when beats overflow");
        expect(!timing.seconds_at(beat(0), false).has_value(),
               "unavailable huge-ratio timing has no seconds oracle");
    } catch (const std::exception& exception) {
        threw = true;
        expect(false, std::string{"INT64_MAX measure ratio timing() does not throw: "} + exception.what());
    } catch (...) {
        threw = true;
        expect(false, "INT64_MAX measure ratio timing() does not throw an unknown exception");
    }
    expect(!threw, "INT64_MAX measure ratio completes without throwing");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "usage: bms_timing_fixture_test FIXTURE_DIRECTORY\n";
        return 2;
    }
    const std::filesystem::path directory = argv[1];
    try {
        constexpr std::string_view fixtures[] = {
            "01-default-bpm.bms", "02-ratio-future-bpm-stop.bms", "03-stop-same-beat.bms",
            "04-same-beat-order.bms", "05-invalid-numeric-undefined.bms", "06-shared-resources.bms",
            "07-runtime-resource-exhaustion-seed.bms", "08-bom-case-insensitive.bms",
            "09-malformed-timing-lines.bms", "10-zero-stop.bms", "11-base62-unavailable.bms",
            "12-measure-overflow.bms", "13-tiny-stop.bms", "14-empty-initial-bpm.bms",
        };
        for (const auto fixture : fixtures) {
            try {
                check_fixture_bytes_and_timing(directory, fixture);
            } catch (const std::exception& exception) {
                expect(false, std::string{fixture} + ": unexpected exception: " + exception.what());
            }
        }
        empty_initial_bpm_forms_are_individually_unavailable();
        malformed_timing_rows_are_individually_unavailable();
        runtime_resource_stress();
        timing_edit_preservation_and_history(directory);
        huge_int64_measure_ratio_timing_is_unavailable();
    } catch (const std::exception& exception) {
        std::cerr << "FATAL: " << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " independent timing expectation(s) failed\n";
        return 1;
    }
    std::cout << "independent timing fixture regressions passed\n";
    return 0;
}
