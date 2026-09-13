#include <ibms/bms_document.hpp>

#include <iostream>
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

ibms::BmsLongNotePosition position(int measure, std::int64_t numerator, std::int64_t denominator = 1)
{
    return {measure, ibms::BeatPosition{numerator, denominator}};
}

void pairs_keep_exact_measure_positions()
{
    auto document = ibms::BmsDocument::from_bytes(
        "#00102:0.5\n"
        "#00051:0100\n"
        "#00151:0001\n");
    const ibms::BmsLongNotes& notes = document.long_notes();
    expect(notes.editable && notes.notes.size() == 1, "paired long-channel endpoints produce one editable hold");
    const ibms::BmsLongNote& note = notes.notes.front();
    expect(note.encoding == ibms::BmsLongNoteEncoding::long_channel && note.channel == "51",
           "long-channel pair retains its encoding and source channel");
    expect(note.start.position.measure == 0 && note.start.position.fraction == ibms::BeatPosition{} &&
               note.end.position.measure == 1 && note.end.position.fraction == ibms::BeatPosition{1, 2},
           "endpoints retain exact source measure fractions");
    expect(note.start.beat == ibms::BeatPosition{} && note.end.beat == ibms::BeatPosition{5},
           "measure-ratio timeline supplies exact cross-measure beats");
    expect(document.chart().editable, "fully validated long-channel pairs no longer make the chart read-only");
}

void long_channel_edits_are_atomic_and_preserve_pairs()
{
    const std::string source = "#BPM 120\r\n#00051:01000100\r\n";
    auto document = ibms::BmsDocument::from_bytes(source);
    document.mark_saved();
    document.insert_timing_event(0, "08", ibms::BeatPosition{3, 4}, "180");
    const std::string after_timing = document.serialize();

    document.insert_long_note("52", position(1, 0), position(1, 1, 2), "a1", "b2");
    const std::string after_insert = document.serialize();
    expect(after_insert.find("#00152:A1") != std::string::npos && after_insert.find("#00152:00B2") != std::string::npos,
           "long-channel insertion appends exact sparse endpoint rows");
    expect(document.long_notes().notes.size() == 2, "insertion adds one pair without changing the existing pair");

    document.move_long_note("52", position(1, 0), "52", position(1, 1, 2), position(1, 3, 4));
    expect(document.long_notes().notes.size() == 2 &&
               document.long_notes().notes.back().start.position.fraction == ibms::BeatPosition{1, 2},
           "move may reuse its vacated end cell as the new start");

    document.resize_long_note("52", position(1, 1, 2), position(2, 0));
    expect(document.long_notes().notes.back().end.position.measure == 2,
           "resize moves only the selected pair tail");
    document.erase_long_note("52", position(1, 1, 2));
    expect(document.long_notes().notes.size() == 1, "delete removes both selected endpoints as one pair");

    expect(document.undo() && document.undo() && document.undo() && document.undo(),
           "delete, resize, move, and insert each have one undo record");
    expect(document.serialize() == after_timing, "long-note undo preserves the preceding timing edit exactly");
    expect(document.undo() && document.serialize() == source,
           "shared timing and long-note history returns to the original bytes");
}

void invalid_or_repairing_operations_are_rejected_without_mutation()
{
    const std::string source = "#00051:01000001\n";
    auto document = ibms::BmsDocument::from_bytes(source);
    const std::string before = document.serialize();
    expect_throws<std::logic_error>([&document] {
        document.insert_long_note("51", position(0, 1, 4), position(0, 1, 2), "02", "03");
    }, "inserting inside an existing paired interval cannot silently split it");
    expect(document.serialize() == before && !document.can_undo(), "rejected interval split is atomic");

    auto unmatched = ibms::BmsDocument::from_bytes("#00051:0100\n");
    expect(unmatched.long_notes().editable && unmatched.chart().editable && unmatched.long_notes().notes.empty() &&
               !unmatched.long_notes().diagnostics.empty(),
           "a leftover long-channel endpoint stays editable and reports a diagnostic");
    unmatched.insert_note(0, "51", ibms::BeatPosition{1, 2}, "02");
    expect(unmatched.long_notes().editable && unmatched.chart().editable && unmatched.long_notes().notes.size() == 1,
           "a second leftover endpoint completes one pair");

    auto leftover = ibms::BmsDocument::from_bytes("#BPM 120\n");
    leftover.insert_note(0, "51", ibms::BeatPosition{}, "01");
    expect(leftover.chart().editable && leftover.long_notes().editable && leftover.long_notes().notes.empty() &&
               leftover.serialize().find("#00051:") != std::string::npos,
           "insert_note can write a single 51 without locking the chart");

    auto after_pair = ibms::BmsDocument::from_bytes("#00051:01000001\n");
    after_pair.insert_note(1, "51", ibms::BeatPosition{}, "03");
    expect(after_pair.chart().editable && after_pair.long_notes().notes.size() == 1 &&
               !after_pair.long_notes().diagnostics.empty(),
           "a leftover after a complete pair stays editable");

    const std::string paired = "#00051:01000001\n";
    auto split = ibms::BmsDocument::from_bytes(paired);
    const std::string before_split = split.serialize();
    expect_throws<std::logic_error>([&split] { split.insert_note(0, "51", ibms::BeatPosition{1, 4}, "03"); },
                                    "insert_note cannot silently re-pair an existing long-channel interval");
    expect(split.serialize() == before_split && !split.can_undo(), "rejected 51 split is atomic");

    auto lntype_two = ibms::BmsDocument::from_bytes("#LNTYPE 2\n#00051:010001\n");
    expect(!lntype_two.long_notes().editable && !lntype_two.chart().editable,
           "LNTYPE 2 remains conservatively unavailable");
}

void lnobj_pairs_are_editable_without_repairing_normal_notes()
{
    auto document = ibms::BmsDocument::from_bytes(
        "#LNOBJ ZZ\n"
        "#00011:0100ZZ00\n"
        "#00111:0001\n");
    expect(document.long_notes().editable && document.long_notes().lnobj_token == "ZZ" &&
               document.long_notes().notes.size() == 1 &&
               document.long_notes().notes.front().encoding == ibms::BmsLongNoteEncoding::lnobj,
           "a strict ordinary-head to LNOBJ-tail pair is editable and exposes its marker");

    const std::string before_repair_attempt = document.serialize();
    expect_throws<std::logic_error>([&document] {
        document.insert_note(0, "11", ibms::BeatPosition{1, 4}, "02");
    }, "ordinary note insertion cannot silently re-pair an LNOBJ tail");
    expect(document.serialize() == before_repair_attempt, "re-pairing rejection preserves raw bytes");

    document.insert_note(2, "11", ibms::BeatPosition{}, "03");
    expect(document.long_notes().notes.size() == 1, "ordinary notes outside an LNOBJ interval remain editable");
    document.insert_long_note("11", position(3, 0), position(3, 1, 2), "A1", "");
    expect(document.long_notes().notes.size() == 2 &&
               document.long_notes().notes.back().end.token == "ZZ",
           "LNOBJ insertion writes the declared marker automatically");
    document.erase_long_note("11", position(3, 0));
    expect(document.long_notes().notes.size() == 1, "LNOBJ delete removes its ordinary head and marker tail together");
}

void malformed_and_ambiguous_long_note_forms_are_read_only()
{
    auto marker_first = ibms::BmsDocument::from_bytes(
        "#LNOBJ ZZ\n"
        "#00011:ZZ01\n");
    expect(!marker_first.long_notes().editable && !marker_first.long_notes().diagnostics.empty() &&
               !marker_first.chart().editable,
           "an LNOBJ marker without a preceding ordinary head is read-only");

    auto same_beat_heads = ibms::BmsDocument::from_bytes(
        "#LNOBJ ZZ\n"
        "#00011:01\n"
        "#00011:02\n"
        "#00111:ZZ\n");
    expect(!same_beat_heads.long_notes().editable && !same_beat_heads.long_notes().diagnostics.empty(),
           "same-beat LNOBJ head candidates are read-only");

    auto mixed_encodings = ibms::BmsDocument::from_bytes(
        "#LNOBJ ZZ\n"
        "#00011:01ZZ\n"
        "#00051:0100\n"
        "#00151:0001\n");
    expect(!mixed_encodings.long_notes().editable && !mixed_encodings.chart().editable,
           "mixed long-channel and LNOBJ encodings are read-only");

    auto zero_marker = ibms::BmsDocument::from_bytes("#LNOBJ 00\n#00011:0100\n");
    expect(!zero_marker.long_notes().editable && !zero_marker.chart().editable,
           "a zero LNOBJ marker is malformed and read-only");

    auto tail_collision = ibms::BmsDocument::from_bytes(
        "#00051:0100\n"
        "#00151:0001\n"
        "#00111:01\n");
    expect(!tail_collision.long_notes().editable && !tail_collision.chart().editable,
           "an ordinary note sharing a long-channel tail is read-only");
}

void set_header_lnobj_rebuilds_pairs()
{
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n#00011:01ZZ\n");
    expect(document.long_notes().notes.empty() && document.long_notes().lnobj_token.empty(),
           "ordinary 01ZZ is not a pair without #LNOBJ");
    document.set_header("LNOBJ", "ZZ");
    expect(document.serialize().find("#LNOBJ ZZ") != std::string::npos, "writes #LNOBJ ZZ");
    expect(document.long_notes().editable && document.long_notes().lnobj_token == "ZZ" &&
               document.long_notes().notes.size() == 1,
           "setting LNOBJ pairs the preceding ordinary note with ZZ");
    document.set_header("LNOBJ", "");
    expect(document.serialize().find("#LNOBJ") == std::string::npos, "None removes the #LNOBJ line");
    expect(document.long_notes().notes.empty() && document.long_notes().lnobj_token.empty(),
           "clearing LNOBJ unpairs without leaving an empty header");
    expect_throws<std::invalid_argument>([&document] { document.set_header("LNOBJ", "00"); },
                                         "LNOBJ 00 is rejected");
}

void unsupported_long_channel_gaps_are_rejected_atomically()
{
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    const std::string source = document.serialize();
    expect_throws<std::invalid_argument>([&document] {
        document.insert_long_note("57", position(0, 0), position(0, 1, 2), "01", "02");
    }, "channel 57 is not a supported long-note channel");
    expect_throws<std::invalid_argument>([&document] {
        document.insert_long_note("67", position(0, 0), position(0, 1, 2), "01", "02");
    }, "channel 67 is not a supported long-note channel");
    expect(document.serialize() == source && !document.can_undo(),
           "unsupported long-note channels leave source and history unchanged");
}

}  // namespace

int main()
{
    pairs_keep_exact_measure_positions();
    long_channel_edits_are_atomic_and_preserve_pairs();
    invalid_or_repairing_operations_are_rejected_without_mutation();
    lnobj_pairs_are_editable_without_repairing_normal_notes();
    set_header_lnobj_rebuilds_pairs();
    malformed_and_ambiguous_long_note_forms_are_read_only();
    unsupported_long_channel_gaps_are_rejected_atomically();
    return failures == 0 ? 0 : 1;
}
