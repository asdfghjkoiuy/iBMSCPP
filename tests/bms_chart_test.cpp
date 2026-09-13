#include <ibms/bms_document.hpp>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>

namespace
{
int failures = 0;
void expect(bool value, const char* message)
{
    if (!value) {
        std::cerr << "Expectation failed: " << message << '\n';
        ++failures;
    }
}
template <class Exception, class F> void throws(F&& f, const char* message)
{
    try {
        f();
        expect(false, message);
    } catch (const Exception&) {
    } catch (...) {
        expect(false, message);
    }
}
std::string fixture(const char* name)
{
    const std::filesystem::path path = std::filesystem::path(IBMS_BMS_CHART_FIXTURE_DIR) / name;
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("fixture is missing: " + path.string());
    }
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}
const ibms::BmsEvent* event(const ibms::BmsChart& chart, std::string_view channel, ibms::BeatPosition fraction)
{
    for (const auto& item : chart.events)
        if (item.channel == channel && item.fraction == fraction)
            return &item;
    return nullptr;
}

void source_positions_and_kinds()
{
    auto document = ibms::BmsDocument::from_bytes(fixture("02-thirds-and-12grid.bms"));
    const auto& chart = document.chart();
    expect(chart.editable, "thirds fixture is editable");
    const auto* third = event(chart, "11", ibms::BeatPosition{1, 3});
    expect(third && third->token == "02" && third->beat == ibms::BeatPosition{4, 3},
           "third slot is exact 1/3 and 4/3 beats");
    const auto* twelfth = event(chart, "12", ibms::BeatPosition{11, 12});
    expect(twelfth && twelfth->beat == ibms::BeatPosition{23, 3}, "12-grid absolute beat is exact");
    expect(&chart == &document.chart(), "unchanged chart read returns cached snapshot");

    auto ratios = ibms::BmsDocument::from_bytes(fixture("03-measure-ratios-0.5-1.5.bms"));
    const auto& ratio_chart = ratios.chart();
    expect(ratio_chart.measures[1].start == ibms::BeatPosition{4} &&
               ratio_chart.measures[1].length == ibms::BeatPosition{2},
           "0.5 measure ratio is two beats");
    expect(ratio_chart.measures[2].start == ibms::BeatPosition{6} &&
               ratio_chart.measures[2].length == ibms::BeatPosition{6},
           "1.5 measure ratio starts and length are exact");

    auto radix = ibms::BmsDocument::from_bytes(fixture("10-radix-edge-hex-bpm-vs-base36-object.bms"));
    expect(event(radix.chart(), "11", ibms::BeatPosition{}) != nullptr, "G1 is accepted as a base36 normal-note token");
    expect(event(radix.chart(), "03", ibms::BeatPosition{}) == nullptr, "G1 is rejected as a hexadecimal BPM token");
}

void retention_and_readonly_gates()
{
    auto duplicate = ibms::BmsDocument::from_bytes(fixture("04-duplicate-bgm-and-normal-rows.bms"));
    const auto& chart = duplicate.chart();
    std::size_t bgm = 0, normal = 0;
    for (const auto& item : chart.events) {
        bgm += item.kind == ibms::BmsEventKind::bgm;
        normal += item.kind == ibms::BmsEventKind::normal_note;
    }
    expect(bgm == 2 && normal == 2, "duplicate BGM and normal rows remain independent events");
    auto conditional = ibms::BmsDocument::from_bytes(fixture("08-readonly-conditional-branch.bms"));
    expect(!conditional.chart().editable && conditional.chart().events.empty(),
           "conditional chart exposes no unevaluated branch events");
    auto malformed = ibms::BmsDocument::from_bytes(fixture("09-readonly-malformed-channel.bms"));
    expect(!malformed.chart().editable, "malformed normal channel gates editing");
    auto lnobj = ibms::BmsDocument::from_bytes(fixture("06-readonly-lnobj-candidate.bms"));
    // Both cells use the declared marker, so this candidate has no unambiguous head.
    expect(!lnobj.chart().editable, "ambiguous LNOBJ marker candidates remain read-only");
    auto lntype = ibms::BmsDocument::from_bytes(fixture("07-readonly-ln-endpoint.bms"));
    // Long-channel endpoints are editable after exact pairing validation.
    expect(lntype.chart().editable, "validated long-channel endpoints no longer gate chart editing");

    auto malformed_measure = ibms::BmsDocument::from_bytes("#00002\n#00011:0100\n");
    expect(!malformed_measure.chart().editable, "malformed measure-length row gates editing");
    expect(!malformed_measure.chart().diagnostics.empty(), "malformed measure-length row produces a diagnostic");
}

void edits_history_and_failures()
{
    const std::string source = "#TITLE One\r\n#00011:0100\n#00012:0001";
    auto document = ibms::BmsDocument::from_bytes(source);
    document.set_header("TITLE", "Two");
    document.insert_note(0, "13", ibms::BeatPosition{1, 3}, "a1");
    expect(document.serialize().find("#00013:00A100") != std::string::npos,
           "insert appends an exact sparse normalized token row");
    document.move_note(0, "13", ibms::BeatPosition{1, 3}, 1, "14", ibms::BeatPosition{1, 2});
    const auto moved = document.serialize();
    expect(moved.find("#00114:00A1") != std::string::npos, "move writes destination token at exact fraction");
    expect(document.undo(), "move has one undo record");
    expect(document.undo(), "insert follows metadata in shared chronology");
    expect(document.undo() && document.serialize() == source, "metadata and note undo restore original raw bytes");
    expect(document.redo() && document.redo() && document.redo() && document.serialize() == moved,
           "redo restores interleaved history");
    throws<std::logic_error>([&] { document.insert_note(0, "11", ibms::BeatPosition{}, "02"); },
                             "collision is rejected");
    const auto stable = document.serialize();
    throws<std::length_error>([&] { document.insert_note(0, "15", ibms::BeatPosition{1, 65537}, "01"); },
                              "slot expansion cap is enforced");
    expect(document.serialize() == stable, "failed edits are atomic");
}

void hidden_and_mine_channels_are_writable()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE One\n#00011:01\n");
    document.insert_note(0, "31", ibms::BeatPosition{1, 2}, "02");
    expect(document.serialize().find("#00031:0002") != std::string::npos, "hidden insert writes channel 31");
    expect(document.chart().events.size() == 2, "visible 11 and hidden 31 coexist");
    document.insert_note(1, "D1", ibms::BeatPosition{}, "03");
    expect(document.serialize().find("#001D1:03") != std::string::npos, "mine insert writes channel D1");
    document.erase_note(0, "31", ibms::BeatPosition{1, 2});
    expect(document.serialize().find("#00031:") == std::string::npos ||
               document.serialize().find("#00031:0000") != std::string::npos,
           "hidden erase clears the 31 cell");
    document.insert_note(0, "B1", ibms::BeatPosition{1, 2}, "04");
    expect(document.serialize().find("#00001:0004") != std::string::npos ||
               document.serialize().find("#00001:04") != std::string::npos,
           "B1 writes the first #01 row");
}

void bgm_rows_are_independent_columns()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE One\n#00001:01\n#00001:02\n");
    const auto& events = document.chart().events;
    expect(events.size() == 2, "two #01 rows become two BGM events");
    expect(events[0].channel == "01" && events[0].token == "01" && events[0].bgm_lane == 0,
           "first #01 row is B1");
    expect(events[1].channel == "01" && events[1].token == "02" && events[1].bgm_lane == 1,
           "second #01 row is B2");

    document.insert_note(0, "B2", ibms::BeatPosition{1, 2}, "03");
    expect(document.chart().events.size() == 3, "B2 insert merges into the second #01 row");
    bool found_lane1_half = false;
    for (const auto& event : document.chart().events) {
        if (event.bgm_lane == 1 && event.token == "03")
            found_lane1_half = true;
    }
    expect(found_lane1_half, "03 lands on B2");
    expect(document.serialize().find("#00001:01") != std::string::npos, "B1 row is unchanged");

    document.insert_note(1, "B3", ibms::BeatPosition{}, "05");
    int max_lane = 0;
    for (const auto& event : document.chart().events)
        max_lane = std::max(max_lane, event.bgm_lane);
    expect(max_lane == 2, "writing B3 creates the third #01 row");
    document.erase_note(0, "B1", ibms::BeatPosition{});
    bool b1_gone = true;
    for (const auto& event : document.chart().events)
        if (event.measure == 0 && event.bgm_lane == 0 && event.token == "01")
            b1_gone = false;
    expect(b1_gone, "erasing B1 clears the first-row cell");
}

void hidden_convert_keeps_the_same_fraction()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE One\n#00011:01\n");
    document.move_note(0, "11", ibms::BeatPosition{}, 0, "31", ibms::BeatPosition{});
    expect(document.serialize().find("#00031:01") != std::string::npos, "→ Hidden writes channel 31");
    expect(document.serialize().find("#00011:") == std::string::npos ||
               document.serialize().find("#00011:00") != std::string::npos,
           "→ Hidden clears the visible cell");
    document.move_note(0, "31", ibms::BeatPosition{}, 0, "11", ibms::BeatPosition{});
    expect(document.serialize().find("#00011:01") != std::string::npos, "→ Visible writes channel 11");
}

void bga_channels_are_writable()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE One\n");
    document.insert_note(0, "04", ibms::BeatPosition{1, 2}, "01");
    expect(document.serialize().find("#00004:0001") != std::string::npos ||
               document.serialize().find("#00004:01") != std::string::npos,
           "BGA insert writes channel 04");
    document.insert_note(1, "07", ibms::BeatPosition{}, "02");
    expect(document.serialize().find("#00107:02") != std::string::npos, "LAYER insert writes channel 07");
    document.erase_note(0, "04", ibms::BeatPosition{1, 2});
    expect(document.serialize().find("#00004:") == std::string::npos ||
               document.serialize().find("#00004:0000") != std::string::npos,
           "BGA erase clears the 04 cell");
}
} // namespace
int main()
{
    source_positions_and_kinds();
    retention_and_readonly_gates();
    edits_history_and_failures();
    hidden_and_mine_channels_are_writable();
    bgm_rows_are_independent_columns();
    hidden_convert_keeps_the_same_fraction();
    bga_channels_are_writable();
    return failures == 0 ? 0 : 1;
}
