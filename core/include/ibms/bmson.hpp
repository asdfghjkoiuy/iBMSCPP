#pragma once

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace ibms {

/// Parse or semantic error for a BMSON document. Never used for BMS charts.
class BmsonParseError : public std::invalid_argument {
public:
    explicit BmsonParseError(const std::string& message);
};

/// BmsONE / BMSON 1.0.0 chart info. JSON keys are camelCase (modeHint, initBPM).
///
/// This is not BMS metadata: there is no measure index, no `#xxx11:` channel
/// row, and no conditional branch.
struct BmsonInfo {
    std::string title;
    std::string subtitle;
    std::string artist;
    std::vector<std::string> subartists;
    std::string genre;
    std::string mode_hint = "beat-7k";
    std::string chart_name;
    int level = 1;
    double init_bpm = 120.0;
    double judge_rank = 100.0;
    double total = 100.0;
    int resolution = 240;
};

/// Bar line at pulse `y`. One beat is `info.resolution` pulses (default 240).
struct BmsonBarLine {
    std::int64_t y = 0;
};

/// Tempo change. JSON object is `{ "y", "v" }` (BmsONE), not a BMS `#BPM` line.
struct BmsonBpmNote {
    std::int64_t y = 0;
    double v = 0.0;
};

/// Stop. JSON object is `{ "y", "v" }`; `v` is duration in pulses.
struct BmsonStopNote {
    std::int64_t y = 0;
    double v = 0.0;
};

/// One note on a sound channel. `x` is a BMSON lane, `l` is pulse length
/// (0 = short), `c` is continue (do not restart the sample).
struct BmsonNote {
    std::int64_t x = 0;
    std::int64_t y = 0;
    std::int64_t l = 0;
    bool c = false;
};

struct BmsonSoundChannel {
    std::string name;
    std::vector<BmsonNote> notes;
};

/// BmsONE `BgaHeader`. JSON is `{ "id", "name" }` (1.0) or `{ "ID", "name" }` (0.21).
struct BmsonBgaHeader {
    int id = 0;
    std::string name;
};

/// BmsONE `BgaEvent`. JSON is `{ "y", "id" }` (1.0) or `{ "y", "ID" }` (0.21).
struct BmsonBgaEvent {
    std::int64_t y = 0;
    int id = 0;
};

/// Shared editor columns `04` / `07` / `06`. Not BMS channels on this document.
enum class BmsonBgaLane {
    bga,
    layer,
    poor,
};

/// BMSON document for BmsONE. Independent of `BmsDocument` / `BmsChart`.
///
/// JSON root (missing fields use BmsONE defaults):
/// `version`, `info{ title, subtitle, artist, subartists, genre, modeHint,
/// chartName, level, initBPM, judgeRank, total, resolution }`,
/// `lines[{ y }]`, `bpmNotes[{ y, v }]`, `stopNotes[{ y, v }]`,
/// `soundChannels[{ name, notes[{ x, y, l, c }] }]`,
/// `bga{ bga_header[{ id, name }], bga_events[{ y, id }],
/// layer_events[{ y, id }], poor_events[{ y, id }] }`.
///
/// `bga` also accepts BmsONE 0.21 keys `bgaHeader` / `bgaNotes` /
/// `layerNotes` / `poorNotes` and `ID`. `to_json()` writes the 1.0 keys.
/// Empty BGA (no headers, events, or extras) is omitted.
///
/// Unknown object keys on the root, `info`, `bga`, and the listed array
/// items are kept and written back by `to_json()`. This model does not
/// interpret them.
class BmsonDocument final {
public:
    [[nodiscard]] static BmsonDocument empty();
    [[nodiscard]] static BmsonDocument from_json(std::string_view text);
    [[nodiscard]] std::string to_json() const;

    /// Insert or replace a BMSON note on one sound channel. This is not `BmsDocument::insert_note`.
    /// Same pulse on the same channel updates the note (BmsONE `InsertNote`).
    /// A playable lane (`x > 0`) that overlaps another channel is refused.
    /// `x` is a BMSON lane, `y`/`l` are pulses. Missing channels create one empty channel.
    /// An out-of-range index uses the first channel.
    void insert_sound_note(std::size_t channel_index, BmsonNote note);

    /// Remove the note at pulse `y` on that channel (BmsONE `RemoveNote`).
    /// Returns false if the channel or pulse is missing.
    bool erase_sound_note(std::size_t channel_index, std::int64_t y);

    /// Move or resize the note at pulse `old_y` on that channel.
    /// Missing pulse or a playable overlap throws `BmsonParseError`.
    /// Extra fields on that index stay (BmsONE Selected Objects Length).
    void replace_sound_note(std::size_t channel_index, std::int64_t old_y, BmsonNote note);

    /// Extra JSON object on the note at pulse `y` (keys other than x, y, l, c).
    /// Missing pulse throws. Empty extras are `{}`.
    [[nodiscard]] std::string note_extra_object_json(std::size_t channel_index, std::int64_t y) const;

    /// Replace extra fields on the note at pulse `y`. `object_json` must be a JSON object.
    /// Known keys `x`, `y`, `l`, `c` are ignored. Missing pulse or invalid JSON throws.
    /// This does not call `replace_sound_channels` and keeps `l` / `c`.
    void replace_note_extra_object_json(
        std::size_t channel_index, std::int64_t y, std::string_view object_json);

    /// Insert or replace a tempo change at pulse `y`. `v` must be positive.
    void upsert_bpm_note(BmsonBpmNote note);

    /// Remove the tempo change at pulse `y`. Returns false if that pulse is missing.
    bool erase_bpm_note(std::int64_t y);

    /// Insert or replace a stop at pulse `y`. `v` is duration in pulses and must be positive.
    void upsert_stop_note(BmsonStopNote note);

    /// Remove the stop at pulse `y`. Returns false if that pulse is missing.
    bool erase_stop_note(std::int64_t y);

    /// Used by BMS → BMSON import. These replace whole collections; they do not
    /// merge with existing notes.
    void replace_info(BmsonInfo info);

    /// Official BMSON 1.0.0 info keys that stay in `extra_info_`
    /// (`banner`, `backImage`, `eyecatchImage`, `titleImage`, `previewMusic`).
    /// Missing or non-string extras are an empty string.
    [[nodiscard]] std::string info_extra_string(std::string_view key) const;

    /// Write a string extra. Empty `value` removes the key. First-class info
    /// keys (`title`, `modeHint`, …) are refused.
    void set_info_extra_string(std::string key, std::string value);

    /// Unknown `info` extras as a JSON object. Official image keys
    /// (`banner`, `backImage`, `eyecatchImage`, `titleImage`, `previewMusic`)
    /// stay out of this object; they have dedicated Header / Info fields.
    /// Keys are sorted. Empty extras are `{}`.
    [[nodiscard]] std::string info_extra_object_json() const;

    /// Replace unknown `info` extras. `object_json` must be a JSON object.
    /// First-class keys and official image keys are ignored. Official image
    /// extras already on the document stay. Invalid JSON throws.
    void replace_info_extra_object_json(std::string_view object_json);

    void replace_lines(std::vector<BmsonBarLine> lines);
    void replace_bpm_notes(std::vector<BmsonBpmNote> notes);
    void replace_stop_notes(std::vector<BmsonStopNote> notes);
    void replace_sound_channels(std::vector<BmsonSoundChannel> channels);

    /// Replace BGA headers and events. Same `id` / `y` keeps the last item.
    void replace_bga(
        std::vector<BmsonBgaHeader> headers,
        std::vector<BmsonBgaEvent> bga_events,
        std::vector<BmsonBgaEvent> layer_events,
        std::vector<BmsonBgaEvent> poor_events);

    /// Insert or replace a header with the same `id`.
    void upsert_bga_header(BmsonBgaHeader header);

    /// Insert or replace an event at pulse `y` on that BGA lane. `id` may be 0.
    void upsert_bga_event(BmsonBgaLane lane, BmsonBgaEvent event);

    /// Remove the event at pulse `y` on that BGA lane.
    bool erase_bga_event(BmsonBgaLane lane, std::int64_t y);

    /// BmsONE `Document::ConvertResolution`. Pulses become
    /// `y * new_resolution / old_resolution` (C++ toward-zero integer division).
    /// Legal range is 48…24000 (`InfoView.cpp`). Same value is a no-op.
    /// `bpmNotes.v` is tempo and stays. `stopNotes.v` is pulse duration and
    /// scales; BmsONE still has `TODO: Stop Events`, this completes that.
    void convert_resolution(int new_resolution);

    /// BmsONE `GetAcceptableResolutionDivider`: GCD of the current resolution
    /// and every pulse location (and long-note ends). Stop pulses are included.
    [[nodiscard]] int acceptable_resolution_divider() const;

    /// True when `new_resolution % (resolution / divider) != 0`.
    [[nodiscard]] bool resolution_conversion_loses_information(int new_resolution) const;

    [[nodiscard]] const std::string& version() const noexcept { return version_; }
    [[nodiscard]] const BmsonInfo& info() const noexcept { return info_; }
    [[nodiscard]] const std::vector<BmsonBarLine>& lines() const noexcept { return lines_; }
    [[nodiscard]] const std::vector<BmsonBpmNote>& bpm_notes() const noexcept { return bpm_notes_; }
    [[nodiscard]] const std::vector<BmsonStopNote>& stop_notes() const noexcept { return stop_notes_; }
    [[nodiscard]] const std::vector<BmsonSoundChannel>& sound_channels() const noexcept
    {
        return sound_channels_;
    }
    [[nodiscard]] const std::vector<BmsonBgaHeader>& bga_headers() const noexcept
    {
        return bga_headers_;
    }
    [[nodiscard]] const std::vector<BmsonBgaEvent>& bga_events() const noexcept { return bga_events_; }
    [[nodiscard]] const std::vector<BmsonBgaEvent>& layer_events() const noexcept
    {
        return layer_events_;
    }
    [[nodiscard]] const std::vector<BmsonBgaEvent>& poor_events() const noexcept
    {
        return poor_events_;
    }

private:
    using ExtraJson = std::vector<std::pair<std::string, std::string>>;

    std::string version_ = "1.0.0";
    BmsonInfo info_{};
    std::vector<BmsonBarLine> lines_;
    std::vector<BmsonBpmNote> bpm_notes_;
    std::vector<BmsonStopNote> stop_notes_;
    std::vector<BmsonSoundChannel> sound_channels_;
    std::vector<BmsonBgaHeader> bga_headers_;
    std::vector<BmsonBgaEvent> bga_events_;
    std::vector<BmsonBgaEvent> layer_events_;
    std::vector<BmsonBgaEvent> poor_events_;
    ExtraJson extra_root_;
    ExtraJson extra_info_;
    ExtraJson extra_bga_;
    std::vector<ExtraJson> extra_lines_;
    std::vector<ExtraJson> extra_bpm_notes_;
    std::vector<ExtraJson> extra_stop_notes_;
    std::vector<ExtraJson> extra_channels_;
    std::vector<std::vector<ExtraJson>> extra_notes_;
    std::vector<ExtraJson> extra_bga_headers_;
    std::vector<ExtraJson> extra_bga_events_;
    std::vector<ExtraJson> extra_layer_events_;
    std::vector<ExtraJson> extra_poor_events_;
};

}  // namespace ibms
