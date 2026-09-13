#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <vector>

#include <ibms/beat_position.hpp>

namespace ibms {

/// iBMSC `BPMx1296` / `STOPx1296`. Off: hex `01`–`FF`. On: base36 `01`–`ZZ`.
/// Channel `03` is always hex and ignores this. Default is off.
class IndexedTimingRadix final {
public:
    static void set(bool bpm_x1296, bool stop_x1296) noexcept;
    [[nodiscard]] static bool bpm_x1296() noexcept;
    [[nodiscard]] static bool stop_x1296() noexcept;

private:
    static bool bpm_x1296_;
    static bool stop_x1296_;
};

class IndexedTimingRadixScope final {
public:
    IndexedTimingRadixScope(bool bpm_x1296, bool stop_x1296);
    ~IndexedTimingRadixScope();
    IndexedTimingRadixScope(const IndexedTimingRadixScope&) = delete;
    IndexedTimingRadixScope& operator=(const IndexedTimingRadixScope&) = delete;

private:
    bool previous_bpm_;
    bool previous_stop_;
};

enum class BmsTimingEventKind { bpm, stop };

struct BmsTimingDiagnostic {
    std::size_t source_line = 0;
    std::string message;
};

struct BmsTimingEvent {
    int measure = 0;
    BeatPosition fraction;
    BeatPosition beat;
    BeatPosition value;
    BmsTimingEventKind kind = BmsTimingEventKind::bpm;
    std::string channel;
    std::string token;
    std::size_t source_line = 0;
};

struct BmsTimingPoint {
    BeatPosition beat;
    BeatPosition bpm_after;
    double seconds_before_stop = 0.0;
    double seconds_after_stop = 0.0;
};

class BmsTiming final {
public:
    BeatPosition initial_bpm = BeatPosition{120};
    std::vector<BmsTimingEvent> events;
    std::vector<BmsTimingPoint> points;
    std::vector<BmsTimingDiagnostic> diagnostics;
    bool available = true;
    std::string unavailable_reason;

    /// Returns pre-stop or post-stop time at an exact non-negative beat.
    [[nodiscard]] std::optional<double> seconds_at(BeatPosition beat, bool after_stop) const;

    /// Arrival time at beat, excluding a STOP that begins at that beat.
    [[nodiscard]] std::optional<double> time_before_stop(BeatPosition beat) const;

    /// Time after a STOP that begins at beat has completed.
    [[nodiscard]] std::optional<double> time_after_stop(BeatPosition beat) const;
};

}  // namespace ibms
