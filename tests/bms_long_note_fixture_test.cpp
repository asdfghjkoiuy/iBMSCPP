#include <ibms/bms_document.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using ibms::BeatPosition;
using ibms::BmsDocument;
using ibms::BmsEvent;
using ibms::BmsEventKind;
using ibms::BmsLongNote;
using ibms::BmsLongNoteEncoding;
using ibms::BmsLongNotePosition;

[[noreturn]] void fail(const std::string& message)
{
    throw std::runtime_error(message);
}

void check(bool condition, const std::string& message)
{
    if (!condition)
        fail(message);
}

std::string read_fixture(const std::filesystem::path& directory, std::string_view name)
{
    std::ifstream input(directory / name, std::ios::binary);
    if (!input)
        fail("cannot open fixture " + std::string(name));
    std::ostringstream bytes;
    bytes << input.rdbuf();
    return bytes.str();
}

BeatPosition q(std::int64_t numerator, std::int64_t denominator = 1)
{
    return BeatPosition(numerator, denominator);
}

BmsLongNotePosition at(int measure, std::int64_t numerator, std::int64_t denominator = 1)
{
    return {measure, q(numerator, denominator)};
}

void check_event(const BmsEvent& actual, int measure, std::string_view channel, std::string_view token,
                 BeatPosition fraction, BeatPosition beat, BmsEventKind kind, std::size_t source_line,
                 std::string_view label)
{
    check(actual.measure == measure, std::string(label) + ": wrong measure");
    check(actual.channel == channel, std::string(label) + ": wrong channel");
    check(actual.token == token, std::string(label) + ": wrong canonical token");
    check(actual.fraction == fraction, std::string(label) + ": wrong source fraction");
    check(actual.beat == beat, std::string(label) + ": wrong absolute beat");
    check(actual.kind == kind, std::string(label) + ": wrong event kind");
    check(actual.source_line == source_line, std::string(label) + ": wrong source line");
}

void check_long(const BmsLongNote& actual, std::string_view channel, BmsLongNoteEncoding encoding,
                BmsLongNotePosition start, BmsLongNotePosition end, std::string_view start_token,
                std::string_view end_token, BeatPosition start_beat, BeatPosition end_beat,
                std::string_view label)
{
    check(actual.channel == channel, std::string(label) + ": wrong long-note channel");
    check(actual.encoding == encoding, std::string(label) + ": wrong long-note encoding");
    check(actual.start.position.measure == start.measure && actual.start.position.fraction == start.fraction,
          std::string(label) + ": wrong long-note start position");
    check(actual.end.position.measure == end.measure && actual.end.position.fraction == end.fraction,
          std::string(label) + ": wrong long-note end position");
    check(actual.start.token == start_token, std::string(label) + ": wrong start token");
    check(actual.end.token == end_token, std::string(label) + ": wrong end token");
    check(actual.start.beat == start_beat, std::string(label) + ": wrong start beat");
    check(actual.end.beat == end_beat, std::string(label) + ": wrong end beat");
}

template <typename Function>
void expect_throw(Function&& function, std::string_view label)
{
    bool threw = false;
    try {
        function();
    } catch (const std::exception&) {
        threw = true;
    }
    check(threw, std::string(label) + ": expected rejection");
}

void check_source_events(const std::filesystem::path& directory)
{
    {
        const auto source = read_fixture(directory, "01-lntype-cross-ratio.bms");
        auto document = BmsDocument::from_bytes(source);
        const auto& chart = document.chart();
        check(chart.editable, "01: valid long-channel pair should remain editable through long API");
        check(chart.events.size() == 2, "01: expected two raw long-channel events");
        check_event(chart.events[0], 0, "51", "01", q(0), q(0), BmsEventKind::long_note, 4, "01 head");
        check_event(chart.events[1], 1, "51", "ZZ", q(1, 2), q(5), BmsEventKind::long_note, 5, "01 tail");
        const auto& notes = document.long_notes();
        check(notes.editable && notes.notes.size() == 1, "01: expected one editable long-channel pair");
        check_long(notes.notes[0], "51", BmsLongNoteEncoding::long_channel, at(0, 0), at(1, 1, 2),
                   "01", "ZZ", q(0), q(5), "01 pair");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "02-duplicate-unmatched.bms"));
        const auto& chart = document.chart();
        check(chart.events.size() == 4, "02: duplicate and unmatched rows must remain visible");
        check_event(chart.events[0], 0, "51", "01", q(0), q(0), BmsEventKind::long_note, 2, "02 duplicate 1");
        check_event(chart.events[1], 0, "51", "01", q(0), q(0), BmsEventKind::long_note, 3, "02 duplicate 2");
        check_event(chart.events[2], 1, "51", "01", q(1, 2), q(6), BmsEventKind::long_note, 4, "02 tail");
        check_event(chart.events[3], 2, "61", "01", q(0), q(8), BmsEventKind::long_note, 5, "02 unmatched P2");
        const auto& notes = document.long_notes();
        check(!notes.editable && notes.notes.empty() && !notes.diagnostics.empty(),
              "02: ambiguous or unmatched endpoints must be read-only with diagnostics");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "03-overlap-crossing-lanes.bms"));
        const auto& chart = document.chart();
        check(chart.events.size() == 7, "03: expected all long and overlapping normal events");
        check_event(chart.events[0], 0, "51", "10", q(0), q(0), BmsEventKind::long_note, 2, "03 P1 head");
        check_event(chart.events[1], 1, "51", "01", q(0), q(4), BmsEventKind::long_note, 3, "03 P1 tail");
        check_event(chart.events[2], 0, "61", "10", q(1, 2), q(2), BmsEventKind::long_note, 4, "03 P2 head");
        check_event(chart.events[3], 1, "61", "ZZ", q(0), q(4), BmsEventKind::long_note, 5, "03 P2 tail");
        check_event(chart.events[4], 0, "11", "01", q(0), q(0), BmsEventKind::normal_note, 6, "03 P1 overlap");
        check_event(chart.events[5], 0, "11", "01", q(1, 4), q(1), BmsEventKind::normal_note, 6, "03 P1 inner note");
        check_event(chart.events[6], 0, "21", "10", q(1, 4), q(1), BmsEventKind::normal_note, 7, "03 P2 overlap");
        const auto& notes = document.long_notes();
        check(!notes.editable && notes.notes.size() == 2 && !notes.diagnostics.empty(),
              "03: pair geometry remains visible while overlapping normal notes are diagnosed and gated");
        check_long(notes.notes[0], "51", BmsLongNoteEncoding::long_channel, at(0, 0), at(1, 0),
                   "10", "01", q(0), q(4), "03 P1 pair");
        check_long(notes.notes[1], "61", BmsLongNoteEncoding::long_channel, at(0, 1, 2), at(1, 0),
                   "10", "ZZ", q(2), q(4), "03 P2 pair");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "04-lnobj-marker-not-wav.bms"));
        const auto& chart = document.chart();
        check(chart.events.size() == 3, "04: #WAV declaration must not become a note event");
        check_event(chart.events[0], 0, "11", "01", q(0), q(0), BmsEventKind::normal_note, 3, "04 head");
        check_event(chart.events[1], 1, "11", "ZZ", q(1, 2), q(6), BmsEventKind::normal_note, 4, "04 LNOBJ tail");
        check_event(chart.events[2], 2, "11", "01", q(0), q(8), BmsEventKind::normal_note, 5, "04 outside note");
        const auto& notes = document.long_notes();
        check(notes.editable && notes.notes.size() == 1, "04: validated LNOBJ pair should be editable through long API");
        check_long(notes.notes[0], "11", BmsLongNoteEncoding::lnobj, at(0, 0), at(1, 1, 2),
                   "01", "ZZ", q(0), q(6), "04 LNOBJ pair");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "05-lntype-mixed-bom-edit-undo.bms"));
        const auto& chart = document.chart();
        check(chart.editable && chart.events.size() == 3, "05: LNTYPE 1 without endpoints keeps ordinary editing available");
        check(document.long_notes().editable && document.long_notes().notes.empty(), "05: no long pair is invented");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "06-lnobj-duplicate-marker.bms"));
        const auto& chart = document.chart();
        check(chart.events.size() == 3, "06: duplicate LNOBJ marker events must remain visible");
        const auto& notes = document.long_notes();
        check(!notes.editable && notes.notes.size() == 1 && !notes.diagnostics.empty(),
              "06: valid partial pair plus duplicate marker must stay read-only");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "07-placement-guards.bms"));
        const auto& chart = document.chart();
        check(chart.editable && chart.events.size() == 4, "07: both source pairs must be visible");
        check_event(chart.events[0], 0, "51", "01", q(0), q(0), BmsEventKind::long_note, 2, "07 first head");
        check_event(chart.events[1], 1, "51", "01", q(0), q(4), BmsEventKind::long_note, 3, "07 first tail");
        check_event(chart.events[2], 1, "51", "01", q(1, 2), q(6), BmsEventKind::long_note, 3, "07 second head");
        check_event(chart.events[3], 2, "51", "01", q(0), q(8), BmsEventKind::long_note, 4, "07 second tail");
        const auto& notes = document.long_notes();
        check(notes.editable && notes.notes.size() == 2, "07: expected two validated pairs");
        check_long(notes.notes[0], "51", BmsLongNoteEncoding::long_channel, at(0, 0), at(1, 0),
                   "01", "01", q(0), q(4), "07 first pair");
        check_long(notes.notes[1], "51", BmsLongNoteEncoding::long_channel, at(1, 1, 2), at(2, 0),
                   "01", "01", q(6), q(8), "07 second pair");
    }

    {
        auto document = BmsDocument::from_bytes(read_fixture(directory, "08-single-pair-move.bms"));
        const auto& chart = document.chart();
        check(chart.editable && chart.events.size() == 2, "08: expected one movable source pair");
        check_event(chart.events[0], 0, "51", "01", q(0), q(0), BmsEventKind::long_note, 2, "08 head");
        check_event(chart.events[1], 1, "51", "ZZ", q(0), q(4), BmsEventKind::long_note, 3, "08 tail");
        const auto& notes = document.long_notes();
        check(notes.editable && notes.notes.size() == 1, "08: expected one validated pair");
        check_long(notes.notes[0], "51", BmsLongNoteEncoding::long_channel, at(0, 0), at(1, 0),
                   "01", "ZZ", q(0), q(4), "08 pair");
    }
}

void check_long_edit_history(const std::filesystem::path& directory)
{
    const auto mixed_source = read_fixture(directory, "05-lntype-mixed-bom-edit-undo.bms");
    auto mixed = BmsDocument::from_bytes(mixed_source);
    mixed.mark_saved();
    mixed.insert_long_note("51", at(0, 1, 4), at(1, 3, 4), "0A", "ZZ");
    check(mixed.dirty() && mixed.can_undo() && !mixed.can_redo(), "05: insert long note creates one history record");
    check(mixed.serialize().substr(0, 3) == std::string("\xef\xbb\xbf", 3), "05: edit preserves UTF-8 BOM");
    check(mixed.long_notes().notes.size() == 1, "05: inserted pair is observable");
    check(mixed.undo() && mixed.serialize() == mixed_source && !mixed.dirty(),
          "05: undo restores all mixed-EOL/no-final-newline bytes");
    check(mixed.can_redo() && mixed.redo() && mixed.long_notes().notes.size() == 1,
          "05: redo restores the inserted pair");
    check(mixed.undo() && mixed.serialize() == mixed_source, "05: final undo returns to exact source");

    const auto cross_source = read_fixture(directory, "01-lntype-cross-ratio.bms");
    auto cross = BmsDocument::from_bytes(cross_source);
    cross.move_long_note("51", at(0, 0), "61", at(2, 0), at(2, 1, 2));
    check(cross.long_notes().notes.size() == 1 && cross.long_notes().notes[0].channel == "61",
          "01: move changes lane through the long-note API");
    check(cross.undo() && cross.serialize() == cross_source, "01: move undo restores exact source");

    auto resized = BmsDocument::from_bytes(cross_source);
    resized.resize_long_note("51", at(0, 0), at(1, 3, 4));
    check(resized.long_notes().notes[0].end.position.fraction == q(3, 4), "01: resize changes exact endpoint");
    check(resized.undo() && resized.serialize() == cross_source, "01: resize undo restores exact source");

    auto erased = BmsDocument::from_bytes(cross_source);
    erased.erase_long_note("51", at(0, 0));
    check(erased.long_notes().notes.empty(), "01: erase removes the validated pair");
    check(erased.undo() && erased.serialize() == cross_source, "01: erase undo restores exact source");

    const auto guard_source = read_fixture(directory, "07-placement-guards.bms");
    auto guard_insert = BmsDocument::from_bytes(guard_source);
    expect_throw([&] {
        guard_insert.insert_long_note("51", at(0, 1, 4), at(0, 1, 2), "01", "01");
    }, "07: nested insertion must not repartition the 0-4 and 6-8 pairs");
    check(guard_insert.serialize() == guard_source && !guard_insert.can_undo(),
          "07: rejected nested insertion is atomic");

    auto guard_resize = BmsDocument::from_bytes(guard_source);
    expect_throw([&] {
        guard_resize.resize_long_note("51", at(0, 0), at(1, 3, 4));
    }, "07: resize past the neighboring pair must be rejected");
    check(guard_resize.serialize() == guard_source && !guard_resize.can_undo(),
          "07: rejected crossing resize is atomic");

    const auto move_source = read_fixture(directory, "08-single-pair-move.bms");
    auto whole_move = BmsDocument::from_bytes(move_source);
    whole_move.move_long_note("51", at(0, 0), "51", at(1, 0), at(2, 0));
    check(whole_move.long_notes().notes.size() == 1 && whole_move.long_notes().notes[0].start.position.measure == 1 &&
              whole_move.long_notes().notes[0].end.position.measure == 2 &&
              whole_move.long_notes().notes[0].start.token == "01" &&
              whole_move.long_notes().notes[0].end.token == "ZZ",
          "08: whole-pair move vacates 0-4, creates 4-8, and preserves endpoint tokens");
    check(whole_move.undo() && whole_move.serialize() == move_source,
          "08: whole-pair move undo restores exact source");
}

void check_lnobj_edit_rules(const std::filesystem::path& directory)
{
    const auto source = read_fixture(directory, "04-lnobj-marker-not-wav.bms");

    auto ordinary = BmsDocument::from_bytes(source);
    ordinary.mark_saved();
    ordinary.insert_note(3, "11", q(0), "02");
    check(ordinary.dirty(), "04: ordinary note outside LN interval remains editable");
    check(ordinary.undo() && ordinary.serialize() == source, "04: outside ordinary edit undo restores source");

    auto protected_interval = BmsDocument::from_bytes(source);
    expect_throw([&] { protected_interval.insert_note(0, "11", q(1, 2), "03"); },
                 "04: ordinary note inside LNOBJ interval");
    check(protected_interval.serialize() == source && !protected_interval.can_undo(),
          "04: rejected inside edit does not change bytes or history");

    auto marker_before_existing = BmsDocument::from_bytes(source);
    expect_throw([&] { marker_before_existing.insert_note(0, "11", q(1, 2), "ZZ"); },
                 "04: marker beside an existing ordinary head must not re-pair that head");
    check(marker_before_existing.serialize() == source && !marker_before_existing.can_undo(),
          "04: rejected marker insertion before the existing tail is atomic");

    auto protected_marker = BmsDocument::from_bytes(source);
    expect_throw([&] { protected_marker.insert_note(3, "11", q(0), "ZZ"); },
                 "04: new normal note using LNOBJ marker");
    expect_throw([&] { protected_marker.move_note(0, "11", q(0), 3, "11", q(0)); },
                 "04: moving LNOBJ head through ordinary-note API");
    expect_throw([&] { protected_marker.erase_note(1, "11", q(1, 2)); },
                 "04: erasing LNOBJ tail through ordinary-note API");
    check(protected_marker.serialize() == source && !protected_marker.can_undo(),
          "04: protected ordinary operations are atomic");

    auto moved = BmsDocument::from_bytes(source);
    moved.move_long_note("11", at(0, 0), "11", at(3, 1, 4), at(4, 3, 4));
    check(moved.long_notes().notes.size() == 1 && moved.long_notes().notes[0].encoding == BmsLongNoteEncoding::lnobj &&
              moved.long_notes().notes[0].start.position.measure == 3 &&
              moved.long_notes().notes[0].start.position.fraction == q(1, 4) &&
              moved.long_notes().notes[0].end.position.measure == 4 &&
              moved.long_notes().notes[0].end.position.fraction == q(3, 4),
          "04: moving LNOBJ head and tail uses the long-note API");
    check(moved.undo() && moved.serialize() == source, "04: LNOBJ move undo restores exact source");

    auto erased = BmsDocument::from_bytes(source);
    erased.erase_long_note("11", at(0, 0));
    check(erased.long_notes().notes.empty(), "04: removing LNOBJ pair uses the long-note API");
    check(erased.undo() && erased.serialize() == source, "04: LNOBJ erase undo restores exact source");
}

}  // namespace

int main(int argc, char** argv)
{
    if (argc != 2) {
        std::cerr << "usage: bms_long_note_fixture_test FIXTURE_DIRECTORY\n";
        return 2;
    }
    try {
        const std::filesystem::path directory = argv[1];
        check_source_events(directory);
        check_long_edit_history(directory);
        check_lnobj_edit_rules(directory);
        std::cout << "bms long-note fixture checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "bms long-note fixture check failed: " << error.what() << '\n';
        return 1;
    }
}
