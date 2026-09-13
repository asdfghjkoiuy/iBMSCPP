#include <ibms/bms_document.hpp>
#include <ibms/bms_timing.hpp>

#include <cstdio>
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

bool contains(const std::string& text, std::string_view needle)
{
    return text.find(needle) != std::string::npos;
}

/// `ChartIO.SaveBMS` `GenerateHeaderMeta` for `#TITLE song` and no other headers.
void title_only_writes_header_banner_and_defaults()
{
    const auto document = ibms::BmsDocument::from_bytes("#TITLE song\n#00011:01\n");
    const std::string text = document.save_bms();
    expect(contains(text,
                    "\r\n*---------------------- HEADER FIELD\r\n\r\n"
                    "#PLAYER 1\r\n#GENRE \r\n#TITLE song\r\n#ARTIST \r\n"
                    "#BPM 120\r\n#PLAYLEVEL \r\n#RANK 3\r\n\r\n\r\n"
                    "#LNTYPE 1\r\n\r\n"),
           "SaveBMS writes required headers and Easy rank");
    expect(contains(text, "*---------------------- MAIN DATA FIELD\r\n\r\n"),
           "SaveBMS writes the MAIN DATA FIELD banner");
    expect(contains(text, "#00011:01\r\n"), "the playable note is in the main field");
    expect(!contains(text, "*---------------------- EXPANSION FIELD"),
           "empty TExpansion omits the expansion banner");
    expect(document.serialize() == "#TITLE song\n#00011:01\n",
           "save_bms does not replace serialize()");
}

/// `#00011:0100` is one cell at the start of a 4-slot row. GCD collapses it to `:01`.
void gcd_compresses_leading_padding()
{
    const auto document = ibms::BmsDocument::from_bytes("#00011:0100\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#00011:01\r\n"), "GCD(192, 0) keeps one slot");
    expect(!contains(text, "#00011:0100"), "SaveBMS does not keep the padded row");
}

/// Half-measure note: relative vpos 96, GCD(192, 96) = 96 → two slots.
void gcd_keeps_half_measure_slot()
{
    const auto document = ibms::BmsDocument::from_bytes("#00011:0001\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#00011:0001\r\n"), "GCD(192, 96) writes two slots");
}

void unused_indexed_bpm_is_dropped()
{
    const auto document = ibms::BmsDocument::from_bytes("#BPM01 140\n#BPM02 180\n#00008:02\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#BPM01 180\r\n"), "first seen 08 value is #BPM01");
    expect(!contains(text, "#BPM02"), "unused 140 is not written");
    expect(contains(text, "#00008:01\r\n"), "the cell is reindexed to 01");
}

void unused_stop_and_scroll_are_dropped()
{
    const auto document = ibms::BmsDocument::from_bytes(
        "#STOP01 48\n#STOP02 96\n#SCROLL01 0.5\n#SCROLL02 2\n#00009:02\n#000SC:02\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#STOP01 96\r\n"), "first seen STOP value is #STOP01");
    expect(!contains(text, "#STOP02"), "unused STOP 48 is not written");
    expect(contains(text, "#00009:01\r\n"), "STOP cell is reindexed to 01");
    expect(contains(text, "#SCROLL01 2\r\n"), "first seen SCROLL value is #SCROLL01");
    expect(!contains(text, "#SCROLL02"), "unused SCROLL 0.5 is not written");
    expect(contains(text, "#000SC:01\r\n"), "SCROLL cell is reindexed to 01");
}

void expansion_banner_wraps_texpansion()
{
    const auto document = ibms::BmsDocument::from_bytes("#TITLE x\n#FOO bar\n#00011:01\n");
    const std::string text = document.save_bms();
    expect(contains(text, "*---------------------- EXPANSION FIELD\r\n#FOO bar\n\r\n"),
           "SaveBMS writes the expansion banner then TExpansion.Text");
}

void wav_and_bmp_keep_occupied_slots()
{
    const auto document = ibms::BmsDocument::from_bytes("#WAV02 b.wav\n#BMP01 bg.png\n#00011:01\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#WAV02 b.wav\r\n"), "empty WAV01 is skipped, WAV02 stays");
    expect(contains(text, "#BMP01 bg.png\r\n"), "occupied BMP slots are written");
    expect(!contains(text, "#WAV01"), "empty WAV slots are omitted");
}

void measure_ratio_uses_dot_decimal()
{
    const auto document = ibms::BmsDocument::from_bytes("#00002:0.5\n#00011:01\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#00002:0.5\r\n"), "non-default #mmm02 is rewritten with a dot");
}

void nt_lnobj_pair_writes_long_channel()
{
    const auto document = ibms::BmsDocument::from_bytes("#LNOBJ ZZ\n#00011:01\n#00111:ZZ\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#LNOBJ ZZ\r\n"), "CHLnObj still writes #LNOBJ");
    expect(contains(text, "#00051:01\r\n"), "ConvertNT2BMSE + GetBMSChannelBy writes 51 at the start");
    expect(contains(text, "#00151:01\r\n"), "the end copies the start value");
    expect(!contains(text, "#00011:"), "ordinary 11 is not left behind");
}

void empty_b1_is_written_when_b2_has_a_note()
{
    const auto document = ibms::BmsDocument::from_bytes("#00001:00\n#00001:01\n");
    const std::string text = document.save_bms();
    const auto first = text.find("#00001:00\r\n");
    const auto second = text.find("#00001:01\r\n");
    expect(first != std::string::npos && second != std::string::npos && first < second,
           "GenerateBackgroundTracks writes empty B1 then B2");
}

void channel_03_stays_hex_and_needs_no_definition()
{
    const auto document = ibms::BmsDocument::from_bytes("#00003:8C\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#00003:8C\r\n"), "integer BPM 140 is Hex 8C");
    expect(!contains(text, "#BPM01"), "channel 03 does not allocate #BPM");
}

void lnobj_stays_when_nt_is_off()
{
    const auto document = ibms::BmsDocument::from_bytes("#LNOBJ ZZ\n#00011:01\n#00111:ZZ\n");
    const std::string text = document.save_bms(false);
    expect(contains(text, "#00011:01\r\n"), "BMSE LNOBJ start stays on 11");
    expect(contains(text, "#00111:ZZ\r\n"), "BMSE LNOBJ end keeps ZZ");
    expect(!contains(text, "#00051:"), "NT off does not call ConvertNT2BMSE");
}

void conditionals_keep_source_bytes()
{
    const std::string source = "#RANDOM 2\n#IF 1\n#00011:01\n#ENDIF\n";
    const auto document = ibms::BmsDocument::from_bytes(source);
    expect(document.save_bms() == source, "RANDOM files are not rewritten");
}

void saved_rank_and_player_follow_headers()
{
    const auto document = ibms::BmsDocument::from_bytes("#PLAYER 2\n#RANK 1\n#DIFFICULTY 3\n#00011:01\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#PLAYER 2\r\n"), "SelectedIndex + 1");
    expect(contains(text, "#RANK 1\r\n"), "RANK is the combo index");
    expect(contains(text, "#DIFFICULTY 3\r\n"), "nonzero difficulty is written");
}

void comment_is_quoted()
{
    const auto document = ibms::BmsDocument::from_bytes("#COMMENT \"hi\"\n#00011:01\n");
    const std::string text = document.save_bms();
    expect(contains(text, "#COMMENT \"hi\"\r\n"), "SaveBMS wraps COMMENT in quotes");
}

/// Two `#00011` cells at vpos 0 share one GCD slot. The later value wins.
void same_slot_sets_overlapping()
{
    const auto document = ibms::BmsDocument::from_bytes("#00011:01\n#00011:02\n");
    const auto report = document.save_bms_report();
    expect(report.overlapping, "xStrKey already occupied sets hasOverlapping");
    expect(contains(report.text, "#00011:02\r\n"), "the later cell overwrites the slot");
    expect(report.bpm_count == 0 && report.stop_count == 0 && report.scroll_count == 0,
           "no indexed timing on this chart");
}

/// Default `BMSGridLimit` is 1, so vpos 0 and 1 stay in different slots.
void default_grid_limit_keeps_adjacent_vpos()
{
    std::string payload = "0102";
    payload.append(380, '0');
    const auto document = ibms::BmsDocument::from_bytes("#00011:" + payload + "\n");
    const auto report = document.save_bms_report(true, 1.0);
    expect(!report.overlapping, "GCD 1 keeps slot 0 and slot 1 apart");
    expect(contains(report.text, "#00011:0102"), "vpos 1 stays in the second cell");
}

/// `BMSGridLimit = 192 / 8 = 24`. GCD(192, 1) stops at 192, both notes land on slot 0.
void coarse_grid_limit_collapses_adjacent_vpos()
{
    std::string payload = "0102";
    payload.append(380, '0');
    const auto document = ibms::BmsDocument::from_bytes("#00011:" + payload + "\n");
    const auto report = document.save_bms_report(true, 24.0);
    expect(report.overlapping, "coarse GCD maps both notes onto one slot");
    expect(contains(report.text, "#00011:02\r\n"), "the later slot value remains");
    expect(!contains(report.text, "#00011:0102"), "the 192-cell row is gone");
}

std::string base36_token(int value)
{
    constexpr char digits[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    if (value < 1)
        value = 1;
    if (value > 1295)
        value = 1295;
    return {digits[value / 36], digits[value % 36]};
}

/// 256 unique `#BPM` values: `UBound(hBPM) == 256`. Hex mode cap is 255.
void two_hundred_fifty_six_bpm_counts_as_overflow()
{
    ibms::IndexedTimingRadixScope scope(true, false);
    std::string source;
    for (int index = 1; index <= 256; ++index) {
        const std::string token = base36_token(index);
        source += "#BPM" + token + " " + std::to_string(300 + index) + "\n";
        char measure[8];
        std::snprintf(measure, sizeof(measure), "%03d", index - 1);
        source += "#";
        source += measure;
        source += "08:" + token + "\n";
    }
    const auto document = ibms::BmsDocument::from_bytes(source);
    const auto report = document.save_bms_report();
    expect(report.bpm_count == 256, "SaveBMS interns every unique 08 value");
    expect(report.stop_count == 0 && report.scroll_count == 0, "only BPM was allocated");
}

void two_scrolls_are_counted()
{
    const auto document = ibms::BmsDocument::from_bytes("#SCROLL01 0.5\n#SCROLL02 2\n#000SC:01\n#001SC:02\n");
    const auto report = document.save_bms_report();
    expect(report.scroll_count == 2, "UBound(hSCROLL) is the unique SCROLL count");
}

}  // namespace

int main()
{
    title_only_writes_header_banner_and_defaults();
    gcd_compresses_leading_padding();
    gcd_keeps_half_measure_slot();
    unused_indexed_bpm_is_dropped();
    unused_stop_and_scroll_are_dropped();
    expansion_banner_wraps_texpansion();
    wav_and_bmp_keep_occupied_slots();
    measure_ratio_uses_dot_decimal();
    nt_lnobj_pair_writes_long_channel();
    empty_b1_is_written_when_b2_has_a_note();
    channel_03_stays_hex_and_needs_no_definition();
    lnobj_stays_when_nt_is_off();
    conditionals_keep_source_bytes();
    saved_rank_and_player_follow_headers();
    comment_is_quoted();
    same_slot_sets_overlapping();
    default_grid_limit_keeps_adjacent_vpos();
    coarse_grid_limit_collapses_adjacent_vpos();
    two_hundred_fifty_six_bpm_counts_as_overflow();
    two_scrolls_are_counted();
    if (failures != 0) {
        std::cerr << failures << " SaveBMS expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_bms_save_tests passed\n";
    return 0;
}
