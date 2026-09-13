#include <ibms/bms_document.hpp>

#include <cmath>
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

void insert_sixteen_extended_bpms(ibms::BmsDocument& document)
{
    for (int measure = 0; measure < 16; ++measure)
        document.insert_timing_event(measure, "08", ibms::BeatPosition{}, std::to_string(160 + measure));
}

void default_write_uses_hex_for_sixteenth_label()
{
    ibms::IndexedTimingRadixScope scope(false, false);
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    insert_sixteen_extended_bpms(document);
    const std::string text = document.serialize();
    expect(text.find("#BPM10 175") != std::string::npos, "switch off writes hex 10 for the 16th BPM");
    expect(text.find("#BPM0G") == std::string::npos, "switch off does not write base36 0G");
    expect(text.find("#01508:10") != std::string::npos, "channel 08 uses the same hex token");
    expect(document.timing().available, "hex 10 round-trips when the switch is off");
    expect(document.timing().events.size() == 16, "sixteen extended BPM events");
}

void switch_on_write_uses_base36_for_sixteenth_label()
{
    ibms::IndexedTimingRadixScope scope(true, true);
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    insert_sixteen_extended_bpms(document);
    const std::string text = document.serialize();
    expect(text.find("#BPM0G 175") != std::string::npos, "switch on writes base36 0G for the 16th BPM");
    expect(text.find("#BPM10 ") == std::string::npos, "switch on does not write hex 10");
    expect(text.find("#01508:0G") != std::string::npos, "channel 08 uses the same base36 token");
    expect(document.timing().available, "base36 0G round-trips when the switch is on");
}

void hex_mode_rejects_base36_only_label()
{
    ibms::IndexedTimingRadixScope scope(false, false);
    const auto document = ibms::BmsDocument::from_bytes("#BPM 120\n#BPM0G 160\n#00008:0G\n");
    expect(!document.timing().available, "0G is not a hex label when the switch is off");
    expect(!document.chart().diagnostics.empty(), "chart diagnoses the non-hex 08 token");
}

void base36_mode_reads_0g()
{
    ibms::IndexedTimingRadixScope scope(true, true);
    const auto document = ibms::BmsDocument::from_bytes("#BPM 120\n#BPM0G 160\n#00008:0G\n");
    expect(document.timing().available, "0G is valid when the switch is on");
    expect(document.timing().events.size() == 1, "one extended BPM");
    expect(document.timing().events[0].value == ibms::BeatPosition{160}, "0G maps to #BPM0G");
}

void channel_03_stays_hex()
{
    ibms::IndexedTimingRadixScope scope(true, true);
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    document.insert_timing_event(0, "03", ibms::BeatPosition{}, "16");
    expect(document.serialize().find("#00003:10") != std::string::npos, "channel 03 is hex even with 1296 on");
    expect(document.timing().available && document.timing().events.size() == 1, "03 timing is available");
    expect(document.timing().events[0].value == ibms::BeatPosition{16}, "hex 10 on 03 is BPM 16");
}

void save_rewrites_hex_labels_when_switch_turns_on()
{
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    {
        ibms::IndexedTimingRadixScope scope(false, false);
        insert_sixteen_extended_bpms(document);
        const std::string hex_saved = document.serialize();
        expect(hex_saved.find("#BPM10 175") != std::string::npos, "same radix keeps hex 10");
        expect(hex_saved.find("#01508:10") != std::string::npos, "same radix keeps hex 08 cell");
    }
    ibms::IndexedTimingRadixScope scope(true, true);
    const std::string text = document.serialize();
    expect(text.find("#BPM0G 175") != std::string::npos, "save with 1296 on rewrites hex 10 to 0G");
    expect(text.find("#BPM10 175") == std::string::npos, "hex 10 must not remain after 1296 save");
    expect(text.find("#01508:0G") != std::string::npos, "channel 08 uses the rewritten token");
    expect(text.find("#00003:") == std::string::npos, "channel 03 is not invented by the rewrite");
}

void save_rewrites_base36_labels_when_switch_turns_off()
{
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    {
        ibms::IndexedTimingRadixScope scope(true, true);
        insert_sixteen_extended_bpms(document);
        expect(document.serialize().find("#BPM0G 175") != std::string::npos, "same radix keeps 0G");
    }
    ibms::IndexedTimingRadixScope scope(false, false);
    const std::string text = document.serialize();
    expect(text.find("#BPM10 175") != std::string::npos, "save with 1296 off rewrites 0G to hex 10");
    expect(text.find("#BPM0G") == std::string::npos, "0G must not remain after hex save");
    expect(text.find("#01508:10") != std::string::npos, "channel 08 uses the rewritten hex token");
}

void save_rewrites_stop_labels()
{
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    {
        ibms::IndexedTimingRadixScope scope(false, false);
        for (int measure = 0; measure < 16; ++measure)
            document.insert_timing_event(measure, "09", ibms::BeatPosition{}, "1");
        expect(document.serialize().find("#STOP10 1") != std::string::npos, "hex STOP 10");
    }
    ibms::IndexedTimingRadixScope scope(false, true);
    const std::string text = document.serialize();
    expect(text.find("#STOP0G 1") != std::string::npos, "STOP switch on rewrites 10 to 0G");
    expect(text.find("#01509:0G") != std::string::npos, "channel 09 uses the rewritten token");
}

void save_does_not_rewrite_conditionals()
{
    const std::string source = "#RANDOM 2\n#IF 1\n#BPM10 175\n#00008:10\n#ENDIF\n";
    const auto document = ibms::BmsDocument::from_bytes(source);
    ibms::IndexedTimingRadixScope scope(true, true);
    expect(document.serialize() == source, "conditional files keep source tokens");
}

void insert_after_switch_change_does_not_collide()
{
    auto document = ibms::BmsDocument::from_bytes("#BPM 120\n");
    {
        ibms::IndexedTimingRadixScope scope(false, false);
        insert_sixteen_extended_bpms(document);
    }
    ibms::IndexedTimingRadixScope scope(true, true);
    document.insert_timing_event(16, "08", ibms::BeatPosition{}, "200");
    const std::string text = document.serialize();
    expect(text.find("#BPM0G 175") != std::string::npos, "existing 16th BPM is 0G after align");
    expect(text.find("#BPM0H 200") != std::string::npos, "next free base36 id after 16 is 0H");
    const auto first = text.find("#BPM0G");
    const auto second = text.find("#BPM0G", first + 1);
    expect(second == std::string::npos, "align prevents two #BPM0G definitions");
}

}  // namespace

int main()
{
    try {
        default_write_uses_hex_for_sixteenth_label();
        switch_on_write_uses_base36_for_sixteenth_label();
        hex_mode_rejects_base36_only_label();
        base36_mode_reads_0g();
        channel_03_stays_hex();
        save_rewrites_hex_labels_when_switch_turns_on();
        save_rewrites_base36_labels_when_switch_turns_off();
        save_rewrites_stop_labels();
        save_does_not_rewrite_conditionals();
        insert_after_switch_change_does_not_collide();
    } catch (const std::exception& exception) {
        std::cerr << "Unhandled exception: " << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_bms_1296_tests passed\n";
    return 0;
}
