#include <ibms/bms_document.hpp>

#include <iostream>
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

bool has_note(
    const ibms::BmsChart& chart, int measure, std::string_view channel, ibms::BeatPosition fraction,
    std::string_view token)
{
    for (const auto& event : chart.events) {
        if (event.kind == ibms::BmsEventKind::normal_note && event.measure == measure &&
            event.channel == channel && event.fraction == fraction && event.token == token)
            return true;
    }
    return false;
}

int note_count(const ibms::BmsChart& chart, std::string_view channel)
{
    int count = 0;
    for (const auto& event : chart.events) {
        if (event.kind == ibms::BmsEventKind::normal_note && event.channel == channel)
            ++count;
    }
    return count;
}

bool has_kind(
    const ibms::BmsChart& chart, ibms::BmsEventKind kind, int measure, std::string_view channel,
    ibms::BeatPosition fraction)
{
    for (const auto& event : chart.events) {
        if (event.kind == kind && event.measure == measure && event.channel == channel &&
            event.fraction == fraction)
            return true;
    }
    return false;
}

int kind_count(const ibms::BmsChart& chart, ibms::BmsEventKind kind, std::string_view channel)
{
    int count = 0;
    for (const auto& event : chart.events) {
        if (event.kind == kind && event.channel == channel)
            ++count;
    }
    return count;
}

bool has_hold(
    const ibms::BmsLongNotes& notes, std::string_view channel, int start_measure,
    ibms::BeatPosition start_fraction, int end_measure, ibms::BeatPosition end_fraction)
{
    for (const auto& note : notes.notes) {
        if (note.channel == channel && note.start.position.measure == start_measure &&
            note.start.position.fraction == start_fraction && note.end.position.measure == end_measure &&
            note.end.position.fraction == end_fraction)
            return true;
    }
    return false;
}

void scale_keeps_measure_fractions()
{
    auto document = ibms::BmsDocument::from_bytes("#00011:01\n#00111:02\n");
    document.apply_beat({0}, "2", ibms::BmsBeatChangeMode::scale);
    expect(document.serialize().find("#00002:2") != std::string::npos, "Case 3 writes #00002:2");
    expect(document.chart().measures[0].length == ibms::BeatPosition{8}, "Case 3 measure 0 is 8 beats");
    expect(has_note(document.chart(), 0, "11", ibms::BeatPosition{}, "01"), "Case 3 keeps #00011:01");
    expect(has_note(document.chart(), 1, "11", ibms::BeatPosition{}, "02"), "Case 3 keeps #00111:02");
    expect(document.undo() && document.serialize() == "#00011:01\n#00111:02\n", "Case 3 is one undo");
}

void preserve_rehomes_later_note()
{
    auto document = ibms::BmsDocument::from_bytes("#00011:01\n#00111:02\n");
    document.apply_beat({0}, "2", ibms::BmsBeatChangeMode::preserve);
    expect(document.serialize().find("#00002:2") != std::string::npos, "Case 0 writes #00002:2");
    expect(has_note(document.chart(), 0, "11", ibms::BeatPosition{}, "01"), "Case 0 keeps the note at beat 0");
    expect(has_note(document.chart(), 0, "11", ibms::BeatPosition{1, 2}, "02"),
           "Case 0 moves beat 4 into measure 0 at 1/2");
    expect(!has_note(document.chart(), 1, "11", ibms::BeatPosition{}, "02"),
           "Case 0 does not leave the note in measure 1");
}

void measure_overflows_half_note()
{
    auto document = ibms::BmsDocument::from_bytes("#00011:0001\n");
    document.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::measure);
    expect(document.serialize().find("#00002:0.5") != std::string::npos, "Case 1 writes #00002:0.5");
    expect(!has_note(document.chart(), 0, "11", ibms::BeatPosition{1, 2}, "01"),
           "Case 1 does not keep the half-measure note in measure 0");
    expect(has_note(document.chart(), 1, "11", ibms::BeatPosition{}, "01"),
           "Case 1 overflows the half-measure note into #00111");
}

void cut_deletes_overflow()
{
    auto document = ibms::BmsDocument::from_bytes("#00011:0001\n");
    document.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::cut);
    expect(document.serialize().find("#00002:0.5") != std::string::npos, "Case 2 writes #00002:0.5");
    expect(note_count(document.chart(), "11") == 0, "Case 2 deletes the note in the cut range");
}

void empty_selection_is_noop()
{
    const std::string source = "#00011:01\n";
    auto document = ibms::BmsDocument::from_bytes(source);
    document.apply_beat({}, "2", ibms::BmsBeatChangeMode::scale);
    expect(document.serialize() == source && !document.can_undo(), "empty LBeat selection does not write");
}

void scale_keeps_long_note_and_scroll_fractions()
{
    auto document = ibms::BmsDocument::from_bytes("#SCROLL01 0.5\n#00051:01\n#00151:01\n#001SC:01\n");
    document.apply_beat({0}, "2", ibms::BmsBeatChangeMode::scale);
    expect(has_hold(document.long_notes(), "51", 0, ibms::BeatPosition{}, 1, ibms::BeatPosition{}),
           "Case 3 keeps the 51 pair on its source measures");
    expect(has_kind(document.chart(), ibms::BmsEventKind::scroll, 1, "SC", ibms::BeatPosition{}),
           "Case 3 keeps SC on measure 1");
}

void preserve_rehomes_long_note_and_scroll()
{
    auto document = ibms::BmsDocument::from_bytes("#SCROLL01 0.5\n#00051:01\n#00151:01\n#001SC:01\n");
    document.apply_beat({0}, "2", ibms::BmsBeatChangeMode::preserve);
    expect(has_hold(document.long_notes(), "51", 0, ibms::BeatPosition{}, 0, ibms::BeatPosition{1, 2}),
           "Case 0 moves the 51 end at beat 4 into measure 0 at 1/2");
    expect(has_kind(document.chart(), ibms::BmsEventKind::scroll, 0, "SC", ibms::BeatPosition{1, 2}),
           "Case 0 moves the SC at beat 4 into measure 0 at 1/2");
    expect(kind_count(document.chart(), ibms::BmsEventKind::scroll, "SC") == 1, "Case 0 keeps one SC cell");
    expect(document.serialize().find("0.5") != std::string::npos, "Case 0 keeps the SCROLL decimal");
}

void measure_overflows_hold_end_and_scroll()
{
    auto hold = ibms::BmsDocument::from_bytes("#00051:0101\n");
    hold.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::measure);
    expect(has_hold(hold.long_notes(), "51", 0, ibms::BeatPosition{}, 1, ibms::BeatPosition{}),
           "Case 1 overflows a half-measure 51 end into measure 1");

    auto scroll = ibms::BmsDocument::from_bytes("#SCROLL01 0.5\n#000SC:0001\n");
    scroll.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::measure);
    expect(has_kind(scroll.chart(), ibms::BmsEventKind::scroll, 1, "SC", ibms::BeatPosition{}),
           "Case 1 overflows the half-measure SC into measure 1");
}

void cut_trims_hold_end_and_deletes_scroll()
{
    auto hold = ibms::BmsDocument::from_bytes("#00051:0101\n");
    hold.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::cut);
    expect(has_hold(hold.long_notes(), "51", 0, ibms::BeatPosition{}, 0, ibms::BeatPosition{95, 96}),
           "Case 2 NT trims a hold ending in the cut to xUpAfter - 1 vpos");
    expect(hold.long_notes().notes.size() == 1, "Case 2 NT keeps the trimmed hold editable");

    auto scroll = ibms::BmsDocument::from_bytes("#SCROLL01 0.5\n#000SC:0001\n");
    scroll.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::cut);
    expect(kind_count(scroll.chart(), ibms::BmsEventKind::scroll, "SC") == 0,
           "Case 2 deletes the SC cell in the cut range");
}

void cut_deletes_hold_inside_range()
{
    auto document = ibms::BmsDocument::from_bytes("#00051:00000101\n");
    document.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::cut);
    expect(document.long_notes().notes.empty(), "Case 2 NT deletes a hold that starts and ends in the cut");
}

void measure_grows_spanning_hold()
{
    auto document = ibms::BmsDocument::from_bytes("#00051:01\n#00251:01\n");
    document.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::measure);
    expect(has_hold(document.long_notes(), "51", 0, ibms::BeatPosition{}, 2, ibms::BeatPosition{}),
           "Case 1 shortens a spanning hold by dLength and leaves the end on measure 2");
}

void preserve_rehomes_lnobj_hold()
{
    auto document = ibms::BmsDocument::from_bytes("#LNOBJ ZZ\n#00011:01\n#00111:ZZ\n");
    document.apply_beat({0}, "2", ibms::BmsBeatChangeMode::preserve);
    expect(has_hold(document.long_notes(), "11", 0, ibms::BeatPosition{}, 0, ibms::BeatPosition{1, 2}),
           "Case 0 moves the LNOBJ end at beat 4 into measure 0 at 1/2");
    expect(document.long_notes().notes.front().end.token == "ZZ", "Case 0 keeps the LNOBJ marker");
}

void cut_trims_lnobj_hold()
{
    auto document = ibms::BmsDocument::from_bytes("#LNOBJ ZZ\n#00011:01ZZ\n");
    document.apply_beat({0}, "0.5", ibms::BmsBeatChangeMode::cut);
    expect(has_hold(document.long_notes(), "11", 0, ibms::BeatPosition{}, 0, ibms::BeatPosition{95, 96}),
           "Case 2 NT trims an LNOBJ end in the cut to xUpAfter - 1 vpos");
    expect(document.long_notes().notes.front().end.token == "ZZ", "Case 2 NT keeps the LNOBJ marker");
}

}  // namespace

int main()
{
    scale_keeps_measure_fractions();
    preserve_rehomes_later_note();
    measure_overflows_half_note();
    cut_deletes_overflow();
    empty_selection_is_noop();
    scale_keeps_long_note_and_scroll_fractions();
    preserve_rehomes_long_note_and_scroll();
    measure_overflows_hold_end_and_scroll();
    cut_trims_hold_end_and_deletes_scroll();
    cut_deletes_hold_inside_range();
    measure_grows_spanning_hold();
    preserve_rehomes_lnobj_hold();
    cut_trims_lnobj_hold();
    if (failures != 0) {
        std::cerr << failures << " Beat Apply expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_bms_beat_tests passed\n";
    return 0;
}
