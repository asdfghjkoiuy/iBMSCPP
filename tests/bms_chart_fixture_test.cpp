#include <ibms/bms_document.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using ibms::BeatPosition;
using ibms::BmsEvent;
using ibms::BmsEventKind;
using ibms::BmsDocument;

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

template <typename Exception, typename Function>
void expect_throw(Function&& function, const std::string& message) {
    try {
        function();
        expect(false, message + " (no exception)");
    } catch (const Exception&) {
    } catch (const std::exception& exception) {
        expect(false, message + " (wrong exception: " + exception.what() + ")");
    } catch (...) {
        expect(false, message + " (unknown exception)");
    }
}

std::string read_fixture(const std::filesystem::path& directory, std::string_view name) {
    const auto path = directory / std::string{name};
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("fixture is missing: " + path.string());
    }
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}

struct ExpectedEvent {
    int measure;
    std::string_view channel;
    std::string_view token;
    BeatPosition fraction;
    BeatPosition absolute_beat;
    BmsEventKind kind;
};

bool same_event(const BmsEvent& actual, const ExpectedEvent& expected) {
    return actual.measure == expected.measure
        && actual.channel == expected.channel
        && actual.token == expected.token
        && actual.fraction == expected.fraction
        && actual.beat == expected.absolute_beat
        && actual.kind == expected.kind;
}

std::vector<ExpectedEvent> expected_events(std::string_view filename) {
    if (filename == "01-normal-1p-2p-lanes.bms") {
        return {
            {0, "11", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "12", "01", beat(1, 8), beat(1, 2), BmsEventKind::normal_note},
            {0, "13", "01", beat(1, 4), beat(1), BmsEventKind::normal_note},
            {0, "14", "01", beat(3, 8), beat(3, 2), BmsEventKind::normal_note},
            {0, "15", "01", beat(1, 2), beat(2), BmsEventKind::normal_note},
            {0, "16", "01", beat(5, 8), beat(5, 2), BmsEventKind::normal_note},
            {0, "18", "01", beat(3, 4), beat(3), BmsEventKind::normal_note},
            {0, "19", "01", beat(7, 8), beat(7, 2), BmsEventKind::normal_note},
            {0, "21", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "22", "01", beat(1, 8), beat(1, 2), BmsEventKind::normal_note},
            {0, "23", "01", beat(1, 4), beat(1), BmsEventKind::normal_note},
            {0, "24", "01", beat(3, 8), beat(3, 2), BmsEventKind::normal_note},
            {0, "25", "01", beat(1, 2), beat(2), BmsEventKind::normal_note},
            {0, "26", "01", beat(5, 8), beat(5, 2), BmsEventKind::normal_note},
            {0, "28", "01", beat(3, 4), beat(3), BmsEventKind::normal_note},
            {0, "29", "01", beat(7, 8), beat(7, 2), BmsEventKind::normal_note},
        };
    }
    if (filename == "02-thirds-and-12grid.bms") {
        return {
            {0, "11", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "11", "02", beat(1, 3), beat(4, 3), BmsEventKind::normal_note},
            {0, "11", "03", beat(2, 3), beat(8, 3), BmsEventKind::normal_note},
            {1, "12", "01", beat(0), beat(4), BmsEventKind::normal_note},
            {1, "12", "0B", beat(11, 12), beat(23, 3), BmsEventKind::normal_note},
        };
    }
    if (filename == "03-measure-ratios-0.5-1.5.bms") {
        return {
            {1, "11", "01", beat(0), beat(4), BmsEventKind::normal_note},
            {1, "11", "02", beat(1, 2), beat(5), BmsEventKind::normal_note},
            {2, "12", "01", beat(0), beat(6), BmsEventKind::normal_note},
            {2, "12", "02", beat(1, 3), beat(8), BmsEventKind::normal_note},
            {2, "12", "03", beat(2, 3), beat(10), BmsEventKind::normal_note},
        };
    }
    if (filename == "04-duplicate-bgm-and-normal-rows.bms") {
        return {
            {0, "01", "01", beat(0), beat(0), BmsEventKind::bgm},
            {0, "01", "01", beat(1, 2), beat(2), BmsEventKind::bgm},
            {0, "11", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "11", "01", beat(1, 2), beat(2), BmsEventKind::normal_note},
        };
    }
    if (filename == "05-bom-mixed-eol-no-final-newline.bms") {
        return {
            {0, "11", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "11", "01", beat(1, 2), beat(2), BmsEventKind::normal_note},
            {1, "12", "01", beat(1, 2), beat(6), BmsEventKind::normal_note},
        };
    }
    if (filename == "06-readonly-lnobj-candidate.bms") {
        return {
            {0, "11", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "11", "01", beat(2, 3), beat(8, 3), BmsEventKind::normal_note},
        };
    }
    if (filename == "07-readonly-ln-endpoint.bms") {
        return {
            {0, "51", "01", beat(0), beat(0), BmsEventKind::long_note},
            {0, "51", "01", beat(2, 3), beat(8, 3), BmsEventKind::long_note},
        };
    }
    if (filename == "08-readonly-conditional-branch.bms") {
        return {};
    }
    if (filename == "09-readonly-malformed-channel.bms") {
        return {
            {0, "11", "01", beat(0), beat(0), BmsEventKind::normal_note},
            {0, "12", "01", beat(1, 2), beat(2), BmsEventKind::normal_note},
        };
    }
    if (filename == "10-radix-edge-hex-bpm-vs-base36-object.bms") {
        return {
            {0, "11", "G1", beat(0), beat(0), BmsEventKind::normal_note},
        };
    }
    throw std::logic_error("no manual oracle for fixture: " + std::string{filename});
}

bool expects_read_only(std::string_view filename) {
    return filename == "06-readonly-lnobj-candidate.bms"
        || filename == "08-readonly-conditional-branch.bms"
        || filename == "09-readonly-malformed-channel.bms"
        || filename == "10-radix-edge-hex-bpm-vs-base36-object.bms";
}

void compare_fixture(const std::filesystem::path& directory, std::string_view filename) {
    const std::string source = read_fixture(directory, filename);
    BmsDocument document = BmsDocument::from_bytes(source);
    const auto& chart = document.chart();

    expect(document.serialize() == source, std::string{filename} + ": initial bytes round-trip exactly");
    const auto expected = expected_events(filename);
    std::vector<const BmsEvent*> supported;
    for (const auto& event : chart.events) {
        if (event.kind != BmsEventKind::unknown) {
            supported.push_back(&event);
        }
    }
    expect(supported.size() == expected.size(),
           std::string{filename} + ": supported event count matches the manual oracle");
    const auto count = std::min(supported.size(), expected.size());
    for (std::size_t i = 0; i < count; ++i) {
        expect(same_event(*supported[i], expected[i]),
               std::string{filename} + ": supported event " + std::to_string(i) + " matches measure/channel/token/fraction/beat");
    }

    if (filename == "01-normal-1p-2p-lanes.bms") {
        std::size_t unknown_count = 0;
        for (const auto& event : chart.events) {
            if (event.kind == BmsEventKind::unknown) {
                ++unknown_count;
                expect(event.channel == "17" || event.channel == "27",
                       "fixture 01: unknown rows remain unknown rather than becoming 8-lane events");
            }
        }
        expect(unknown_count == 2, "fixture 01: both raw 17/27 rows remain observable as unknown events");
    }
    if (filename == "08-readonly-conditional-branch.bms") {
        expect(chart.events.empty(), "fixture 08: conditional chart exposes no evaluated events");
        expect(document.has_conditionals(), "fixture 08: conditional directive is detected");
    }
    if (expects_read_only(filename)) {
        expect(!chart.editable, std::string{filename} + ": chart is read-only with a diagnostic reason");
        expect(!chart.editing_reason.empty(), std::string{filename} + ": read-only chart provides an editing reason");
    }
    if (filename == "10-radix-edge-hex-bpm-vs-base36-object.bms") {
        expect(chart.diagnostics.size() >= 1, "fixture 10: invalid hexadecimal BPM token produces a diagnostic");
        for (const auto& event : chart.events) {
            expect(event.channel != "03", "fixture 10: invalid #00003:G1 is not emitted as a BPM event");
        }
    }
}

void all_real_fixtures(const std::filesystem::path& directory) {
    constexpr std::array<std::string_view, 10> fixtures = {
        "01-normal-1p-2p-lanes.bms",
        "02-thirds-and-12grid.bms",
        "03-measure-ratios-0.5-1.5.bms",
        "04-duplicate-bgm-and-normal-rows.bms",
        "05-bom-mixed-eol-no-final-newline.bms",
        "06-readonly-lnobj-candidate.bms",
        "07-readonly-ln-endpoint.bms",
        "08-readonly-conditional-branch.bms",
        "09-readonly-malformed-channel.bms",
        "10-radix-edge-hex-bpm-vs-base36-object.bms",
    };
    for (const auto fixture : fixtures) {
        try {
            compare_fixture(directory, fixture);
        } catch (const std::exception& exception) {
            expect(false, std::string{fixture} + ": unexpected test exception: " + exception.what());
        }
    }
}

void no_final_newline_appends_parseable_rows(const std::filesystem::path& directory) {
    BmsDocument document = BmsDocument::from_bytes(read_fixture(directory, "05-bom-mixed-eol-no-final-newline.bms"));
    document.insert_note(0, "13", beat(1, 2), "a1");
    const auto after_insert = document.serialize();
    expect(after_insert.find("#TITLE BOM mixed") != std::string::npos,
           "no-final-newline insert preserves the title header");
    expect(after_insert.find("#BPM 120") != std::string::npos,
           "no-final-newline insert preserves the BPM header");
    expect(after_insert.find("#00013:00A1") != std::string::npos,
           "no-final-newline insert appends a complete channel row");
    const auto& inserted_chart = document.chart();
    expect(std::any_of(inserted_chart.events.begin(), inserted_chart.events.end(), [](const BmsEvent& event) {
        return event.channel == "13" && event.token == "A1" && event.fraction == beat(1, 2);
    }), "appended channel 13 row parses as its own event");

    document.move_note(0, "13", beat(1, 2), 0, "14", beat(1, 2));
    const auto after_move = document.serialize();
    expect(after_move.find("#00014:00A1") != std::string::npos,
           "no-final-newline move appends a complete destination row");
    expect(after_move.find("#00013:00A1") == std::string::npos,
           "no-final-newline move removes the source token without corrupting headers");
    const auto& moved_chart = document.chart();
    expect(std::any_of(moved_chart.events.begin(), moved_chart.events.end(), [](const BmsEvent& event) {
        return event.channel == "14" && event.token == "A1" && event.fraction == beat(1, 2);
    }), "appended channel 14 row parses after move");
}

void lowercase_raw_token_erase_move_and_undo() {
    const std::string source = "#TITLE Lowercase\n#00011:g100";
    auto erased = BmsDocument::from_bytes(source);
    erased.erase_note(0, "11", beat(0));
    expect(erased.serialize() == "#TITLE Lowercase\n#00011:0000",
           "erase changes only the lowercase source token span");
    expect(erased.undo(), "lowercase erase creates an undo record");
    expect(erased.serialize() == source, "undo restores lowercase source bytes exactly");

    auto moved = BmsDocument::from_bytes(source);
    moved.move_note(0, "11", beat(0), 0, "12", beat(1, 2));
    expect(moved.serialize().find("#00012:00g1") != std::string::npos,
           "move preserves the lowercase raw token in the appended row");
    expect(moved.undo(), "lowercase move creates an undo record");
    expect(moved.serialize() == source, "move undo restores lowercase source bytes exactly");
}

void missing_same_position_move_is_atomic() {
    const std::string source = "#TITLE Same position\n#00011:0100\n";
    auto document = BmsDocument::from_bytes(source);
    document.mark_saved();
    expect_throw<std::out_of_range>([&] {
        document.move_note(0, "11", beat(1, 2), 0, "11", beat(1, 2));
    }, "same-position move with a missing source rejects");
    expect(document.serialize() == source, "missing same-position move leaves bytes unchanged");
    expect(!document.dirty(), "missing same-position move leaves the document clean");
    expect(!document.can_undo() && !document.can_redo(),
           "missing same-position move leaves history unchanged");
}

void collision_failure_preserves_redo() {
    const std::string source = "#00011:0100\n#00012:0100\n";
    auto document = BmsDocument::from_bytes(source);
    document.insert_note(0, "13", beat(1, 2), "AA");
    expect(document.undo(), "setup insertion can be undone");
    expect(document.can_redo(), "setup undo creates a redo record");
    expect_throw<std::logic_error>([&] {
        document.move_note(0, "11", beat(0), 0, "12", beat(0));
    }, "move into an occupied destination rejects");
    expect(document.serialize() == source, "collision failure leaves bytes unchanged");
    expect(document.can_redo(), "collision failure preserves the pending redo record");
    expect(document.redo(), "preserved redo remains executable after collision failure");
    expect(document.serialize().find("#00013:00AA") != std::string::npos,
           "preserved redo restores the appended note row");
}

void move_metadata_saved_state_chronology() {
    const std::string source = "#TITLE Before\n#00011:0100\n";
    auto document = BmsDocument::from_bytes(source);
    document.mark_saved();
    document.move_note(0, "11", beat(0), 1, "12", beat(1, 2));
    expect(document.dirty(), "move after save makes the document dirty");
    document.mark_saved();
    document.set_header("TITLE", "After");
    expect(document.dirty(), "metadata edit after the saved move makes the document dirty");

    expect(document.undo(), "undo removes metadata after the move");
    expect(!document.dirty(), "undo to the saved post-move state is clean");
    expect(document.header("TITLE") == std::optional<std::string>{"Before"},
           "metadata undo restores the prior title");
    expect(document.serialize().find("#00112:0001") != std::string::npos,
           "metadata undo leaves the earlier move in place");

    expect(document.undo(), "second undo removes the earlier move");
    expect(document.dirty(), "undo before the saved state is dirty");
    expect(document.serialize() == source, "second undo restores the original bytes");
    expect(document.redo(), "redo restores the move in chronology");
    expect(!document.dirty(), "redo to the saved post-move state is clean");
    expect(document.redo(), "redo restores metadata after the move");
    expect(document.dirty(), "redo beyond the saved state is dirty");
    expect(document.header("TITLE") == std::optional<std::string>{"After"},
           "redo restores metadata after the move");
}

void huge_ratio_is_read_only_diagnostic_and_lossless() {
    const std::string source = "#TITLE Huge ratio\n#00002:9223372036854775807\n";
    auto document = BmsDocument::from_bytes(source);
    bool threw = false;
    const ibms::BmsChart* chart = nullptr;
    try {
        chart = &document.chart();
    } catch (const std::exception& exception) {
        threw = true;
        expect(false, std::string{"huge ratio chart construction does not throw: "} + exception.what());
    } catch (...) {
        threw = true;
        expect(false, "huge ratio chart construction does not throw an unknown exception");
    }
    expect(!threw && chart != nullptr, "huge ratio produces a chart snapshot");
    if (chart != nullptr) {
        expect(!chart->editable, "huge ratio makes the chart read-only");
        expect(!chart->diagnostics.empty(), "huge ratio produces a chart diagnostic");
        bool mentions_overflow = false;
        for (const auto& diagnostic : chart->diagnostics) {
            mentions_overflow = mentions_overflow
                || diagnostic.message.find("overflow") != std::string::npos
                || diagnostic.message.find("representable") != std::string::npos;
        }
        expect(mentions_overflow, "huge ratio diagnostic identifies representable-range overflow");
    }
    expect(document.serialize() == source, "huge ratio preserves raw bytes after chart inspection");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "usage: bms_chart_fixture_test FIXTURE_DIRECTORY\n";
        return 2;
    }
    const std::filesystem::path fixture_directory = argv[1];
    try {
        all_real_fixtures(fixture_directory);
        no_final_newline_appends_parseable_rows(fixture_directory);
        lowercase_raw_token_erase_move_and_undo();
        missing_same_position_move_is_atomic();
        collision_failure_preserves_redo();
        move_metadata_saved_state_chronology();
        huge_ratio_is_read_only_diagnostic_and_lossless();
    } catch (const std::exception& exception) {
        std::cerr << "FATAL: " << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " independent chart expectation(s) failed\n";
        return 1;
    }
    std::cout << "independent chart fixture regressions passed\n";
    return 0;
}
