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

void unknown_hash_line_is_expansion()
{
    const auto document = ibms::BmsDocument::from_bytes("#TITLE x\n#FOO bar\n#00011:01\n");
    expect(document.expansion() == "#FOO bar\n", "OpenBMS puts unknown # lines in TExpansion");
    expect(document.expansion().find("#TITLE") == std::string::npos, "known headers stay out of expansion");
    expect(document.expansion().find("#00011") == std::string::npos, "known channels stay out of expansion");
}

void measure_ratio_is_not_expansion()
{
    const auto document = ibms::BmsDocument::from_bytes("#00002:2\n#00011:01\n");
    expect(document.expansion().empty(), "#mmm02 is MeasureLength, not TExpansion");
}

void unknown_channel_is_expansion()
{
    const auto document = ibms::BmsDocument::from_bytes("#00005:AA\n#00011:01\n");
    expect(document.expansion() == "#00005:AA\n", "unmapped channels go to TExpansion");
}

void nested_if_collects_inner_headers()
{
    const auto document = ibms::BmsDocument::from_bytes(
        "#TITLE Outside\n#RANDOM 2\n#IF 1\n#TITLE In IF\n#IF 1\n#UNKNOWN nested-value\n"
        "#ENDIF\n#ENDIF\n#ENDRANDOM\n#UNKNOWN outside-value\n#BPM 150\n#WAV01 tone.wav\n"
        "#00111:01\n");
    expect(document.expansion() ==
               "#RANDOM 2\n#IF 1\n#TITLE In IF\n#IF 1\n#UNKNOWN nested-value\n"
               "#ENDIF\n#ENDIF\n#ENDRANDOM\n#UNKNOWN outside-value\n",
           "xStack > 0 sends every # line to TExpansion, including #TITLE");
    expect(document.has_conditionals(), "RANDOM / IF keep the document conditional");
}

void set_expansion_replaces_collected_lines()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE x\n#FOO bar\n#00011:01\n");
    document.set_expansion("#FOO baz\n#BAR 1\n");
    expect(document.serialize() == "#TITLE x\n#FOO baz\n#BAR 1\n#00011:01\n",
           "set_expansion replaces only collected lines");
    expect(document.expansion() == "#FOO baz\n#BAR 1\n", "read-back matches the replacement");
    expect(document.undo() && document.serialize() == "#TITLE x\n#FOO bar\n#00011:01\n",
           "expansion write is one undo");
}

void clearing_expansion_drops_conditionals()
{
    auto document = ibms::BmsDocument::from_bytes("#RANDOM 2\n#IF 1\n#ENDIF\n#00011:01\n");
    expect(document.has_conditionals() && !document.chart().editable, "IF makes the chart read-only");
    document.set_expansion("");
    expect(document.expansion().empty(), "empty TExpansion removes collected lines");
    expect(!document.has_conditionals(), "removing IF / RANDOM clears the conditional flag");
    expect(document.chart().editable, "the chart becomes editable after expansion is cleared");
    expect(document.serialize() == "#00011:01\n", "known channel rows stay");
    expect(document.undo() && document.has_conditionals() && !document.chart().editable,
           "undo restores conditionals and the read-only chart");
}

void appends_when_expansion_was_empty()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE x\n#00011:01\n");
    document.set_expansion("#PREVIEW movie.mpg");
    expect(document.serialize() == "#TITLE x\n#00011:01\n#PREVIEW movie.mpg\n",
           "new expansion text is appended with the document line ending");
}

void same_text_is_noop()
{
    const std::string source = "#TITLE x\n#FOO bar\n";
    auto document = ibms::BmsDocument::from_bytes(source);
    document.set_expansion("#FOO bar");
    expect(document.serialize() == source && !document.can_undo(),
           "rewriting the same expansion lines does not create history");
}

}  // namespace

int main()
{
    unknown_hash_line_is_expansion();
    measure_ratio_is_not_expansion();
    unknown_channel_is_expansion();
    nested_if_collects_inner_headers();
    set_expansion_replaces_collected_lines();
    clearing_expansion_drops_conditionals();
    appends_when_expansion_was_empty();
    same_text_is_noop();
    if (failures != 0) {
        std::cerr << failures << " Expansion expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_bms_expansion_tests passed\n";
    return 0;
}
