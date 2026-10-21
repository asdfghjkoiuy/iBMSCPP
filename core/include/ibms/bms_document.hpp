#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include <ibms/bms_chart.hpp>
#include <ibms/bms_long_note.hpp>
#include <ibms/bms_timing.hpp>

namespace ibms {

/// `ChartIO.SaveBMS` write result. `bpm_count` / `stop_count` / `scroll_count`
/// match `UBound(hBPM)` / `hSTOP` / `hSCROLL` after encounter-order intern.
struct BmsSaveReport {
    std::string text;
    bool overlapping = false;
    std::size_t bpm_count = 0;
    std::size_t stop_count = 0;
    std::size_t scroll_count = 0;
};

/// `MainWindow.vb` `BeatChangeMode`: CBeatPreserve / Measure / Cut / Scale.
enum class BmsBeatChangeMode {
    preserve = 0,
    measure = 1,
    cut = 2,
    scale = 3,
};

/// A lossless BMS byte document with a deliberately limited metadata editor.
///
/// The document preserves all source bytes except explicit byte-range edits.
/// chart() derives a read-only snapshot; it never evaluates conditionals or
/// decodes text.
class BmsDocument final {
public:
    /// Rejects UTF-16/UTF-32 byte-order marks and embedded NUL bytes.
    [[nodiscard]] static BmsDocument from_bytes(std::string bytes);

    /// Returns the current document bytes.
    ///
    /// `#BPM` / `#STOP` definitions and channel `08` / `09` cells are rewritten
    /// from the radix they were loaded or last written with to the current
    /// `IndexedTimingRadix`, matching `ChartIO.SaveBMS` (`C10to36` vs `Hex`).
    /// Unchanged radix keeps the source bytes. Channel `03` stays hexadecimal.
    /// `#SCROLL` / `SC` stay base36. Conditional documents are not rewritten.
    /// New 08 / 09 labels follow `IndexedTimingRadix`: hex `01`–`FF` when
    /// the matching switch is off, base36 `01`–`ZZ` when it is on.
    /// `build_bms_timing` and `make_chart` use the same radix.
    [[nodiscard]] std::string serialize() const;

    /// `ChartIO.SaveBMS`. Rewrites the whole table with HEADER / MAIN banners,
    /// GCD-compressed rows, and BPM / STOP / SCROLL definitions in encounter
    /// order. Does not change in-memory bytes. Conditional files return
    /// `serialize()`. `nt_input` default matches `NTInput = True`.
    /// `grid_limit` is `BMSGridLimit` (`192 / gridPartition`, default `1`).
    [[nodiscard]] std::string save_bms(bool nt_input = true, double grid_limit = 1.0) const;

    /// Same rewrite as `save_bms`, plus the overlap flag and `UBound` counts
    /// used by the four SaveBMS warning boxes.
    [[nodiscard]] BmsSaveReport save_bms_report(bool nt_input = true, double grid_limit = 1.0) const;

    [[nodiscard]] std::optional<std::string> header(std::string_view key) const;

    /// Changes one allow-listed header. Title fields plus PLAYER, RANK,
    /// PLAYLEVEL, STAGEFILE, BANNER, BACKBMP, DIFFICULTY, DEFEXRANK, TOTAL,
    /// COMMENT, LNOBJ, WAV list slots `WAV01`–`WAVZZ`, and BMP list slots
    /// `BMP01`–`BMPZZ`. Not BPM. `BACKBMP` stays the header field, not a list
    /// slot.
    ///
    /// Keys are ASCII case-insensitive. Values are raw bytes, except CR, LF,
    /// and NUL are rejected. LNOBJ must be empty (None, which removes the
    /// `#LNOBJ` line) or a base-36 token `01`–`ZZ`. Empty `WAVxx` / `BMPxx`
    /// removes that `#WAV` / `#BMP` line. Empty optional headers match
    /// `GenerateHeaderMeta`: SUBTITLE, SUBARTIST, STAGEFILE, BANNER, BACKBMP,
    /// DEFEXRANK, TOTAL, and COMMENT drop the line. DIFFICULTY `0` is
    /// `SelectedIndex = 0` and also drops the line. Required fields TITLE /
    /// ARTIST / GENRE / PLAYER / RANK / PLAYLEVEL keep an empty tag.
    /// COMMENT is stored with wrapping quotes, matching ChartIO
    /// save; `header()` strips one leading and one trailing quote. Any
    /// recognized conditional directive rejects all metadata edits because
    /// this batch does not evaluate conditional blocks.
    void set_header(std::string_view key, std::string_view value);

    /// `ChartIO.OpenBMS` `TExpansion`: unknown `#` lines, plus every `#` line
    /// while `#IF` / `#SWITCH` / `#SETSWITCH` is open. Known headers, `#mmm02`,
    /// and mapped channels stay out. `set_expansion` replaces those collected
    /// lines as one undo and does not require an editable chart.
    [[nodiscard]] std::string expansion() const;
    void set_expansion(std::string_view text);

    /// A derived snapshot cached by content revision. Diagnostic source_line is
    /// the zero-based physical source-line index. Conditional charts expose no
    /// events because no branch is evaluated.
    [[nodiscard]] const BmsChart& chart() const;
    [[nodiscard]] const BmsLongNotes& long_notes() const;

    /// A cached, immutable timing snapshot. It returns unavailable rather than
    /// inventing a timeline for conditionals, malformed timing syntax, or an
    /// unsupported token base.
    [[nodiscard]] const BmsTiming& timing() const;

    /// Edits a visible, hidden, mine, or BGM note at an exact measure fraction.
    /// Hidden uses 31–39 / 41–49. Mines use D1–D9 / E1–E9. BGM uses `01` or
    /// `B1`…`B999`; each `#mmm01` row is one B column.
    void insert_note(int measure, std::string_view channel, BeatPosition fraction, std::string_view token);
    void erase_note(int measure, std::string_view channel, BeatPosition fraction);
    void move_note(
        int source_measure, std::string_view source_channel, BeatPosition source_fraction,
        int destination_measure, std::string_view destination_channel, BeatPosition destination_fraction);

    /// Replaces the final plain #BPM decimal or appends one. Positive decimals
    /// are exact and input whitespace is not written.
    void set_initial_bpm(std::string_view decimal);

    /// Changes only #mmm02's numeric payload. This is the scale-within-measure
    /// operation; it requires chart().editable and validates the full result.
    void set_measure_ratio(int measure, std::string_view decimal);

    /// `MainWindow.ApplyBeat` / `BeatChangeMode`. Case 3 is `set_measure_ratio`.
    /// Cases 0–2 re-home object-edit notes, BPM / STOP / SC cells, and NT holds
    /// (long-channel pairs and LNOBJ pairs) by absolute beat. Case 2 NT trims a
    /// hold that ends in the cut to `xUpAfter - 1` vpos. An empty measure list
    /// is a no-op. Several measures are one undo.
    void apply_beat(const std::vector<int>& measures, std::string_view decimal, BmsBeatChangeMode mode);

    /// Inserts, replaces, or erases one exact 03, 08, 09, or SC timing cell.
    /// Cell edits require chart().editable. Indexed replacements allocate a
    /// fresh resource definition and never rewrite a shared definition.
    /// Channel 03 tokens are always hexadecimal 01–FF. `#BPM` / `#STOP` and
    /// 08 / 09 tokens follow `IndexedTimingRadix`. `#SCROLL` / SC always use
    /// base36 `01`–`ZZ`. SC accepts 0 and a leading minus; channel 03 does not.
    void insert_timing_event(int measure, std::string_view channel, BeatPosition fraction, std::string_view decimal);
    void replace_timing_event(int measure, std::string_view channel, BeatPosition fraction, std::string_view decimal);
    void erase_timing_event(int measure, std::string_view channel, BeatPosition fraction);

    /// Edits a validated long-channel pair (51..56, 58, 59, 61..66, 68, 69)
    /// or an LNOBJ pair on its ordinary playable channel as one history transaction.
    /// Coordinates are exact source-row fractions.  LNOBJ insertion writes
    /// the declared marker at the end; pass an empty end token or that marker.
    void insert_long_note(
        std::string_view channel, BmsLongNotePosition start, BmsLongNotePosition end,
        std::string_view start_token, std::string_view end_token);
    void move_long_note(
        std::string_view source_channel, BmsLongNotePosition source_start,
        std::string_view destination_channel, BmsLongNotePosition destination_start,
        BmsLongNotePosition destination_end);
    void resize_long_note(
        std::string_view channel, BmsLongNotePosition start, BmsLongNotePosition end);
    void erase_long_note(std::string_view channel, BmsLongNotePosition start);

    [[nodiscard]] bool undo();
    [[nodiscard]] bool redo();
    [[nodiscard]] bool can_undo() const noexcept;
    [[nodiscard]] bool can_redo() const noexcept;
    [[nodiscard]] bool dirty() const noexcept;
    [[nodiscard]] bool has_conditionals() const noexcept;
    void mark_saved() noexcept;
    /// Drops undo / redo patches. Current bytes and dirty stay as they are.
    void discard_history() noexcept;
    /// Groups later edits into one undo. `AddUndo` after WAV Up / `fdrReplaceL`.
    void begin_compound();
    void end_compound();
    void abort_compound();
    [[nodiscard]] bool compounding() const noexcept;
    [[nodiscard]] std::size_t line_count() const noexcept;

private:
    struct BytePatch {
        std::size_t offset;
        std::string before;
        std::string after;
    };

    struct Patch {
        std::vector<BytePatch> bytes;
        std::size_t before_revision;
        std::size_t after_revision;
    };

    BmsDocument(std::string bytes, bool has_conditionals) noexcept;
    [[nodiscard]] static std::string apply_patch_bytes(const std::string& source, const Patch& patch, bool forward);
    [[nodiscard]] static std::string make_sparse_note_row(
        std::string_view source, int measure, std::string_view channel,
        BeatPosition fraction, std::string_view token);
    void commit_chart_edit_patch(Patch patch);
    void commit_long_note_patch(Patch patch, std::vector<BmsLongNote> expected_notes);
    void commit_normal_note_patch(Patch patch);
    void commit_patch(Patch patch);
    void record_undo(Patch patch);
    /// One scan of header lines. Keys are ASCII-uppercased. A later exact key
    /// replaces an earlier one, matching `header()`. COMMENT quotes are stripped.
    [[nodiscard]] std::unordered_map<std::string, std::string> header_index() const;
    void align_indexed_timing_labels();

    std::string bytes_;
    bool compounding_ = false;
    std::string compound_before_;
    bool bpm_label_x1296_ = false;
    bool stop_label_x1296_ = false;
    std::vector<Patch> undo_;
    std::vector<Patch> redo_;
    std::size_t current_revision_ = 0;
    std::size_t saved_revision_ = 0;
    std::size_t next_revision_ = 1;
    bool has_conditionals_ = false;
    mutable BmsChart chart_cache_;
    mutable std::size_t chart_revision_ = static_cast<std::size_t>(-1);
    mutable bool chart_cache_bpm_x1296_ = false;
    mutable bool chart_cache_stop_x1296_ = false;
    mutable BmsTiming timing_cache_;
    mutable std::size_t timing_revision_ = static_cast<std::size_t>(-1);
    mutable bool timing_cache_bpm_x1296_ = false;
    mutable bool timing_cache_stop_x1296_ = false;
    mutable BmsLongNotes long_note_cache_;
    mutable std::size_t long_note_revision_ = static_cast<std::size_t>(-1);
};

}  // namespace ibms
