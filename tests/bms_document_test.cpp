#include <ibms/bms_document.hpp>

#include <array>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

int failures = 0;

[[nodiscard]] std::string load_fixture(std::string_view filename) {
    const std::filesystem::path path = std::filesystem::path{IBMS_BMS_FIXTURE_DIR} / filename;
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("unable to open BMS fixture: " + path.string());
    }
    return {std::istreambuf_iterator<char>{input}, std::istreambuf_iterator<char>{}};
}

void expect(bool condition, std::string_view expression) {
    if (!condition) {
        std::cerr << "Expectation failed: " << expression << '\n';
        ++failures;
    }
}

void expect_header(
    const ibms::BmsDocument& document, std::string_view key,
    std::optional<std::string_view> expected, std::string_view expression) {
    const std::optional<std::string> actual = document.header(key);
    expect(actual.has_value() == expected.has_value(), expression);
    if (actual.has_value() && expected.has_value()) {
        expect(*actual == *expected, expression);
    }
}

template <typename Exception, typename Operation>
void expect_throws(Operation&& operation, std::string_view expression) {
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

void raw_round_trip_and_lookup() {
    const std::string bom{"\xEF\xBB\xBF", 3};
    const std::string source = bom + "  #TITLE First \r\n#UNKNOWN \x80\n#TITLE\tLast\t\r#TITLEIMAGE ignored";
    const ibms::BmsDocument document = ibms::BmsDocument::from_bytes(source);

    expect(document.serialize() == source, "unmodified document serializes byte-for-byte");
    expect_header(document, "title", "Last", "last duplicate header is effective");
    expect_header(document, "TITLEIMAGE", "ignored", "exact key lookup permits the full directive");
    expect(document.line_count() == 4, "mixed line endings count physical lines");
    expect(!document.dirty() && !document.can_undo() && !document.can_redo(), "new document starts clean");
}

void compound_two_headers_is_one_undo()
{
    auto document = ibms::BmsDocument::from_bytes("#WAV01 a.wav\n#WAV02 b.wav\n#00011:02\n");
    document.begin_compound();
    document.set_header("WAV01", "b.wav");
    document.set_header("WAV02", "a.wav");
    document.end_compound();
    expect(document.header("WAV01") == "b.wav" && document.header("WAV02") == "a.wav",
           "compound writes both WAV slots");
    expect(document.can_undo() && document.dirty(), "compound is one undo");
    expect(document.undo() && document.header("WAV01") == "a.wav" && document.header("WAV02") == "b.wav",
           "one undo restores both slots");
    expect(!document.can_undo(), "compound does not leave extra undo steps");

    document.begin_compound();
    document.set_header("WAV01", "a.wav");
    document.abort_compound();
    expect(document.header("WAV01") == "a.wav" && !document.can_undo(),
           "abort_compound drops the half-finished edit");

    auto notes = ibms::BmsDocument::from_bytes("#00011:01\n#00012:01\n");
    notes.begin_compound();
    notes.erase_note(0, "11", ibms::BeatPosition{});
    notes.insert_note(0, "11", ibms::BeatPosition{}, "02");
    notes.erase_note(0, "12", ibms::BeatPosition{});
    notes.insert_note(0, "12", ibms::BeatPosition{}, "02");
    static_cast<void>(notes.chart());
    notes.end_compound();
    expect(notes.undo(), "compound note edits are one undo");
    std::size_t restored = 0;
    for (const auto& event : notes.chart().events)
        if (event.token == "01")
            ++restored;
    expect(restored == 2, "undo after in-compound chart() restores both labels");
    expect(!notes.can_undo(), "compound note edits do not leave extra undo steps");
}

void discard_history_keeps_bytes_and_dirty()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE Old\n");
    document.set_header("TITLE", "New");
    expect(document.can_undo() && document.dirty(), "edit creates history");
    document.discard_history();
    expect(!document.can_undo() && !document.can_redo(), "discard_history drops patches");
    expect(document.dirty() && document.header("TITLE") == "New", "current bytes and dirty stay");
}

void metadata_edit_preserves_framing() {
    const std::string source = "\t#TITLE  first  \r\n#TITLE\tlast \t\n#TITLEIMAGE ignored\r";
    auto document = ibms::BmsDocument::from_bytes(source);

    document.set_header("TiTlE", "New");
    expect(document.serialize() == "\t#TITLE  first  \r\n#TITLE\tNew \t\n#TITLEIMAGE ignored\r",
           "only the final matching value range changes");
    expect_header(document, "TITLE", "New", "edited header reads its new value");
    expect(document.dirty() && document.can_undo() && !document.can_redo(), "edit updates history and dirty state");

    expect(document.undo(), "undo applies the metadata patch");
    expect(document.serialize() == source, "undo restores every original byte");
    expect(document.redo(), "redo reapplies the metadata patch");
    expect_header(document, "TITLE", "New", "redo restores the new metadata value");
    const std::string after_redo = document.serialize();
    document.set_header("TITLE", " \tNew  ");
    expect(document.serialize() == after_redo, "repeated whitespace-framed value is a no-op");
    expect(document.undo() && document.serialize() == source,
           "whitespace-framed no-op does not add another history entry");
}

void metadata_boundary_regressions() {
    auto no_separator = ibms::BmsDocument::from_bytes("#TITLE\n");
    expect_header(no_separator, "TITLE", "", "directive without a separator has an empty value");
    no_separator.set_header("TITLE", "Name");
    expect(no_separator.serialize() == "#TITLE Name\n", "editing a separator-less directive adds one separator");
    expect(no_separator.undo() && no_separator.serialize() == "#TITLE\n",
           "undo restores a separator-less directive exactly");

    const std::string whitespace_only = "#TITLE \t \n";
    auto whitespace_document = ibms::BmsDocument::from_bytes(whitespace_only);
    whitespace_document.set_header("TITLE", " \tValue \t");
    const std::string edited = "#TITLE \t Value\n";
    expect(whitespace_document.serialize() == edited,
           "editing a whitespace-only value preserves the original separator without growth");
    whitespace_document.set_header("TITLE", "");
    expect(whitespace_document.serialize() == whitespace_only,
           "clearing restores the original whitespace-only framing");
    expect(whitespace_document.undo() && whitespace_document.serialize() == edited,
           "undoing clear restores the edited range without extra whitespace");
    expect(whitespace_document.undo() && whitespace_document.serialize() == whitespace_only,
           "undoing edit restores whitespace-only source bytes exactly");
}

void append_handles_empty_bom_and_missing_newline() {
    auto empty = ibms::BmsDocument::from_bytes({});
    empty.set_header("TITLE", "Empty");
    expect(empty.serialize() == "#TITLE Empty\r\n", "empty documents append CRLF by default");
    expect(empty.undo() && empty.serialize().empty(), "undo removes an appended empty-document header exactly");

    const std::string bom{"\xEF\xBB\xBF", 3};
    auto bom_document = ibms::BmsDocument::from_bytes(bom);
    bom_document.set_header("GENRE", "Game");
    expect(bom_document.serialize() == bom + "#GENRE Game\r\n", "BOM-only documents append after the BOM");
    expect(bom_document.undo() && bom_document.serialize() == bom, "BOM-only append undo restores only the BOM");

    auto no_terminal_newline = ibms::BmsDocument::from_bytes("#ARTIST Old");
    no_terminal_newline.set_header("TITLE", "New");
    expect(no_terminal_newline.serialize() == "#ARTIST Old\r\n#TITLE New\r\n",
           "append inserts a default EOL before and after a new line");
    expect(no_terminal_newline.undo() && no_terminal_newline.serialize() == "#ARTIST Old",
           "undo restores a missing terminal newline exactly");
}

void conditional_directives_gate_metadata() {
    constexpr std::array<std::string_view, 13> directives = {
        "RANDOM", "SETRANDOM", "IF", "ELSEIF", "ELSE", "ENDIF", "ENDRANDOM",
        "SWITCH", "SETSWITCH", "CASE", "SKIP", "DEF", "ENDSW",
    };
    for (const std::string_view directive : directives) {
        auto document = ibms::BmsDocument::from_bytes("#" + std::string(directive) + " 1\n#TITLE Original\n");
        expect(document.has_conditionals(), "each exact conditional directive is recognized");
        expect_header(document, "TITLE", std::nullopt, "conditional documents hide metadata values");
        const std::string source = document.serialize();
        expect_throws<std::logic_error>([&document] { document.set_header("TITLE", "Blocked"); },
                                        "conditional documents reject metadata edits");
        expect(document.serialize() == source && !document.can_undo(), "failed conditional edit preserves source and history");
    }

    auto boundary_document = ibms::BmsDocument::from_bytes("#RANDOMIZE 1\n#RANDOMIZER 1\n#IFX 1\n#TITLE Allowed\n");
    expect(!boundary_document.has_conditionals(), "longer directive names do not match conditional tokens");
    boundary_document.set_header("TITLE", "Edited");
    expect_header(boundary_document, "TITLE", "Edited", "exact-boundary document remains editable");
}

void extra_header_keys() {
    auto document = ibms::BmsDocument::from_bytes("#TITLE Song\n");
    document.set_header("PLAYER", "2");
    expect_header(document, "PLAYER", "2", "PLAYER is writable");
    document.set_header("RANK", "3");
    expect_header(document, "RANK", "3", "RANK is writable");
    document.set_header("PLAYLEVEL", "12");
    expect_header(document, "PLAYLEVEL", "12", "PLAYLEVEL is writable");
    document.set_header("STAGEFILE", "stage.png");
    expect_header(document, "STAGEFILE", "stage.png", "STAGEFILE is writable");
    document.set_header("DEFEXRANK", "80");
    expect_header(document, "DEFEXRANK", "80", "DEFEXRANK is writable");
    const std::string bytes = document.serialize();
    expect(bytes.find("#PLAYER 2") != std::string::npos, "PLAYER is appended when missing");
    expect(bytes.find("#PLAYLEVEL 12") != std::string::npos, "PLAYLEVEL is appended when missing");
    expect(bytes.find("#STAGEFILE stage.png") != std::string::npos, "STAGEFILE is appended when missing");
    expect(bytes.find("#DEFEXRANK 80") != std::string::npos, "DEFEXRANK is appended when missing");
}

void empty_optional_headers_remove_the_line()
{
    auto document = ibms::BmsDocument::from_bytes(
        "#TITLE Song\n#SUBTITLE Extra\n#STAGEFILE stage.png\n#DIFFICULTY 3\n#COMMENT \"hi\"\n");
    document.set_header("SUBTITLE", "");
    document.set_header("STAGEFILE", "");
    document.set_header("DIFFICULTY", "0");
    document.set_header("COMMENT", "");
    const std::string bytes = document.serialize();
    expect(bytes.find("#TITLE Song") != std::string::npos, "required TITLE stays");
    expect(bytes.find("#SUBTITLE") == std::string::npos, "GenerateHeaderMeta omits empty SUBTITLE");
    expect(bytes.find("#STAGEFILE") == std::string::npos, "GenerateHeaderMeta omits empty STAGEFILE");
    expect(bytes.find("#DIFFICULTY") == std::string::npos, "SelectedIndex 0 omits DIFFICULTY");
    expect(bytes.find("#COMMENT") == std::string::npos, "GenerateHeaderMeta omits empty COMMENT");
    expect(!document.header("STAGEFILE").has_value() || document.header("STAGEFILE")->empty(),
           "cleared STAGEFILE is not an empty tag");
}

void comment_writes_quoted_and_reads_unquoted()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE Song\n");
    document.set_header("COMMENT", "hello");
    expect(document.serialize().find("#COMMENT \"hello\"") != std::string::npos,
           "ChartIO writes #COMMENT with quotes");
    expect_header(document, "COMMENT", "hello", "header() strips the wrapping quotes");
    document.set_header("COMMENT", "hello");
    expect(document.serialize().find("#COMMENT \"hello\"") != std::string::npos && !document.can_redo(),
           "rewriting the same comment is a no-op");

    auto quoted = ibms::BmsDocument::from_bytes("#COMMENT \"quoted\"\n");
    expect_header(quoted, "COMMENT", "quoted", "load strips one leading and one trailing quote");
    auto leading = ibms::BmsDocument::from_bytes("#COMMENT \"hello\n");
    expect_header(leading, "COMMENT", "hello", "load strips a leading quote alone");
    auto trailing = ibms::BmsDocument::from_bytes("#COMMENT hello\"\n");
    expect_header(trailing, "COMMENT", "hello", "load strips a trailing quote alone");
}

void failures_noops_and_save_state() {
    auto document = ibms::BmsDocument::from_bytes("#TITLE One\n");
    document.set_header("TITLE", "Two");
    const std::string after_edit = document.serialize();
    expect_throws<std::invalid_argument>([&document] { document.set_header("BPM", "120"); },
                                         "unsupported metadata key is rejected");
    expect(document.serialize() == after_edit && document.can_undo() && !document.can_redo(),
           "rejected BPM edit preserves content and history");
    document.set_header("LNOBJ", "ZZ");
    expect(document.serialize().find("#LNOBJ ZZ") != std::string::npos, "LNOBJ header is writable");
    expect(document.undo() && document.serialize() == after_edit && document.can_redo(),
           "undo LNOBJ write returns to the previous header edit");
    expect_throws<std::invalid_argument>([&document] { document.set_header("TITLE", "bad\nvalue"); },
                                         "line-breaking metadata value is rejected");
    expect(document.serialize() == after_edit && document.can_undo() && document.can_redo(),
           "failed edits preserve content and history");

    document.mark_saved();
    expect(!document.dirty(), "mark_saved records the current revision");
    document.set_header("TITLE", "Three");
    expect(document.dirty(), "new edit after save is dirty");
    expect(document.undo() && !document.dirty(), "undo back to saved revision is clean");
    expect(document.redo() && document.dirty(), "redo away from saved revision is dirty");
    expect(document.undo(), "undo prepares a history branch");
    document.set_header("TITLE", "Branch");
    expect(document.dirty() && !document.can_redo(), "new branch clears redo and remains dirty");
    expect(document.undo() && !document.dirty(), "undoing the branch reaches the saved revision");

    auto no_op = ibms::BmsDocument::from_bytes("#TITLE One\n");
    no_op.set_header("TITLE", "Two");
    expect(no_op.undo() && no_op.can_redo(), "undo creates redo history");
    no_op.set_header("TITLE", "One");
    expect(no_op.can_redo(), "no-op edit keeps redo history intact");
    expect_throws<std::invalid_argument>([&no_op] { no_op.set_header("TITLE", "bad\rvalue"); },
                                         "CR value is rejected without changing redo");
    expect_throws<std::invalid_argument>([&no_op] { no_op.set_header("TITLE", std::string_view{"bad\0value", 9}); },
                                         "NUL value is rejected without changing redo");
    expect(no_op.serialize() == "#TITLE One\n" && no_op.can_redo(),
           "invalid values preserve the undone document and redo history");
    expect(no_op.redo(), "redo remains available after a no-op edit");

    auto abandoned_saved_revision = ibms::BmsDocument::from_bytes("#TITLE One\n");
    abandoned_saved_revision.set_header("TITLE", "Saved");
    abandoned_saved_revision.mark_saved();
    abandoned_saved_revision.set_header("TITLE", "Later");
    expect(abandoned_saved_revision.undo() && !abandoned_saved_revision.dirty(),
           "undo reaches the explicitly saved revision");
    expect(abandoned_saved_revision.undo() && abandoned_saved_revision.dirty(),
           "undoing before the saved revision is dirty");
    abandoned_saved_revision.set_header("TITLE", "Branch");
    expect(abandoned_saved_revision.dirty() && !abandoned_saved_revision.can_redo(),
           "branch at the saved history depth remains dirty after the saved revision is abandoned");
}

void unsupported_encodings_and_raw_bytes() {
    expect_throws<std::invalid_argument>([] {
        static_cast<void>(ibms::BmsDocument::from_bytes(std::string{"\xFF\xFE", 2}));
    }, "UTF-16 BOM is rejected");
    expect_throws<std::invalid_argument>([] {
        static_cast<void>(ibms::BmsDocument::from_bytes(std::string{"\x00\x00\xFE\xFF", 4}));
    }, "UTF-32 BOM is rejected");
    expect_throws<std::invalid_argument>([] {
        static_cast<void>(ibms::BmsDocument::from_bytes(std::string{"#TITLE A\0B", 10}));
    }, "embedded NUL is rejected");

    auto document = ibms::BmsDocument::from_bytes(std::string{"#TITLE \x80\xFF\n", 10});
    expect_header(document, "TITLE", std::string_view{"\x80\xFF", 2}, "non-UTF-8 metadata bytes remain visible");
    document.set_header("ARTIST", std::string_view{"\x81", 1});
    expect(document.serialize() == std::string{"#TITLE \x80\xFF\n#ARTIST \x81\n", 20},
           "non-UTF-8 bytes round-trip through a metadata append");
}

void fixture_round_trips() {
    struct Fixture {
        std::string_view filename;
        bool has_conditionals;
    };
    constexpr std::array<Fixture, 6> fixtures = {{
        {"01-mixed-endings-no-final-newline.bms", false},
        {"02-utf8-bom-metadata.bms", false},
        {"03-shiftjis-japanese-metadata.bms", false},
        {"04-duplicate-headers-titleimage-boundary.bms", false},
        {"05-nested-random-if-unknown-directives.bms", true},
        {"06-malformed-channel-valid-records.bms", false},
    }};

    for (const Fixture fixture : fixtures) {
        const std::string source = load_fixture(fixture.filename);
        auto document = ibms::BmsDocument::from_bytes(source);
        expect(document.serialize() == source, "fixture document round-trips all source bytes");
        expect(document.has_conditionals() == fixture.has_conditionals,
               "fixture conditional state matches its known source form");
        if (fixture.has_conditionals) {
            expect_header(document, "TITLE", std::nullopt, "conditional fixture hides metadata values");
            expect_throws<std::logic_error>([&document] { document.set_header("TITLE", "Blocked"); },
                                            "conditional fixture rejects metadata edits");
            expect(document.serialize() == source, "rejected conditional fixture edit preserves source bytes");
        }
    }

    auto duplicate_headers = ibms::BmsDocument::from_bytes(load_fixture("04-duplicate-headers-titleimage-boundary.bms"));
    expect_header(duplicate_headers, "TITLE", "Second", "fixture TITLE uses its final exact-key occurrence");
    expect_header(duplicate_headers, "TITLEIMAGE", "bg.png", "fixture TITLEIMAGE remains a distinct directive");

    auto shift_jis = ibms::BmsDocument::from_bytes(load_fixture("03-shiftjis-japanese-metadata.bms"));
    const std::string expected_title{"\x93\xFA\x96\x7B\x8C\xEA\x83\x81\x83\x5E\x83\x66\x81\x5B\x83\x5E", 16};
    expect_header(shift_jis, "TITLE", expected_title, "fixture Shift-JIS title bytes remain raw and exact");
}

}  // namespace

int main() {
    raw_round_trip_and_lookup();
    compound_two_headers_is_one_undo();
    discard_history_keeps_bytes_and_dirty();
    metadata_edit_preserves_framing();
    metadata_boundary_regressions();
    append_handles_empty_bom_and_missing_newline();
    conditional_directives_gate_metadata();
    extra_header_keys();
    empty_optional_headers_remove_the_line();
    comment_writes_quoted_and_reads_unquoted();
    failures_noops_and_save_state();
    unsupported_encodings_and_raw_bytes();
    fixture_round_trips();

    if (failures != 0) {
        std::cerr << failures << " test expectation(s) failed\n";
        return 1;
    }
    return 0;
}
