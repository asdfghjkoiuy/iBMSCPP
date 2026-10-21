#include <ibms/bms_import_random.hpp>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <limits>
#include <optional>
#include <random>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ibms {
namespace {

std::string_view trim(std::string_view text)
{
    while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) {
        text.remove_prefix(1);
    }
    while (!text.empty()
        && (text.back() == ' ' || text.back() == '\t' || text.back() == '\r')) {
        text.remove_suffix(1);
    }
    return text;
}

std::string ascii_upper(std::string_view text)
{
    std::string out(text);
    for (char& c : out) {
        if (c >= 'a' && c <= 'z') {
            c = static_cast<char>(c - 'a' + 'A');
        }
    }
    return out;
}

int parse_int(std::string_view text)
{
    const std::string owned{trim(text)};
    if (owned.empty()) {
        return 0;
    }
    errno = 0;
    char* end = nullptr;
    const long value = std::strtol(owned.c_str(), &end, 10);
    if (end == owned.c_str()) {
        return 0;
    }
    // Values outside int are invalid. BmsONE `toInt` fails the same way, and
    // HandleRANDOM already turns a non-positive result into 1. Truncating the
    // long would be implementation-defined and can look like a small max.
    if (errno == ERANGE || value > static_cast<long>(std::numeric_limits<int>::max())
        || value < static_cast<long>(std::numeric_limits<int>::min())) {
        return 0;
    }
    return static_cast<int>(value);
}

bool digits_only(std::string_view text)
{
    if (text.empty()) {
        return false;
    }
    for (const char c : text) {
        if (c < '0' || c > '9') {
            return false;
        }
    }
    return true;
}

bool is_control(std::string_view command)
{
    return command == "RANDOM" || command == "SETRANDOM" || command == "IF"
        || command == "ELSEIF" || command == "ELSE" || command == "ENDIF"
        || command == "ENDRANDOM";
}

struct HeaderCommand {
    std::string command;
    std::string value;
    bool channel = false;
};

// uBMplay 1.5.2 rewrites compact `#RANDOMdigits` / `#IFdigits`, exact `#RONDAM`,
// and `#END` whose argument is exactly `IF`. Channel rows and other commands,
// including `#RANDOMPATTERN` and `#RONDAM4`, stay as written.
void normalize_ubmplay_command(HeaderCommand& parsed)
{
    if (parsed.channel) {
        return;
    }
    if (parsed.value.empty()) {
        const std::string_view command = parsed.command;
        if (command.size() > 6 && command.substr(0, 6) == "RANDOM" && digits_only(command.substr(6))) {
            parsed.value.assign(command.substr(6));
            parsed.command = "RANDOM";
            return;
        }
        if (command.size() > 2 && command.substr(0, 2) == "IF" && digits_only(command.substr(2))) {
            parsed.value.assign(command.substr(2));
            parsed.command = "IF";
            return;
        }
    }
    if (parsed.command == "RONDAM") {
        parsed.command = "RANDOM";
        return;
    }
    if (parsed.command == "END" && ascii_upper(parsed.value) == "IF") {
        parsed.command = "ENDIF";
        parsed.value.clear();
    }
}

std::optional<HeaderCommand> parse_line(std::string_view raw)
{
    const std::string_view line = trim(raw);
    if (line.empty() || line.front() != '#') {
        return std::nullopt;
    }
    std::size_t delimiter = std::string_view::npos;
    for (std::size_t i = 1; i < line.size(); ++i) {
        const char c = line[i];
        if (c == ':' || c == ' ' || c == '\t') {
            delimiter = i;
            break;
        }
    }
    HeaderCommand parsed;
    if (delimiter != std::string_view::npos && line[delimiter] == ':') {
        parsed.channel = true;
        parsed.command = ascii_upper(line.substr(1, delimiter - 1));
        parsed.value = std::string(trim(line.substr(delimiter + 1)));
        return parsed;
    }
    const std::string_view header =
        delimiter == std::string_view::npos ? line.substr(1) : line.substr(1, delimiter - 1);
    parsed.command = ascii_upper(trim(header));
    parsed.value = delimiter == std::string_view::npos
        ? std::string()
        : std::string(trim(line.substr(delimiter + 1)));
    normalize_ubmplay_command(parsed);
    return parsed;
}

int resolve_random_value(int requested, int random_max)
{
    const int max = random_max > 0 ? random_max : 1;
    if (requested > 0 && requested <= max) {
        return requested;
    }
    thread_local std::mt19937 generator = [] {
        try {
            std::random_device device;
            return std::mt19937{device()};
        } catch (...) {
            return std::mt19937{0xB5C011u};
        }
    }();
    std::uniform_int_distribution<int> distribution(1, max);
    return distribution(generator);
}

struct RandomFrame {
    int value = 0;
    bool skip_before = false;
    // Opened inside an IF that was already inactive. uBMplay copies the parent
    // activity flag, so a matching inner #IF must not turn the body back on.
    bool sealed = false;
    bool if_open = false;
};

struct RandomState {
    std::vector<RandomFrame> frames;
    std::vector<int> if_labels;
    bool skipping = false;
    bool skip_between = false;
    bool loose_if_open = false;
    std::size_t value_index = 0;
    const std::vector<int>* values = nullptr;

    bool contains_label(int value) const
    {
        return std::find(if_labels.begin(), if_labels.end(), value) != if_labels.end();
    }

    bool any_sealed() const
    {
        for (const RandomFrame& frame : frames) {
            if (frame.sealed) {
                return true;
            }
        }
        return false;
    }

    bool current_if_open() const
    {
        return frames.empty() ? loose_if_open : frames.back().if_open;
    }

    void set_if_open(bool open)
    {
        if (frames.empty()) {
            loose_if_open = open;
        } else {
            frames.back().if_open = open;
        }
    }

    void push_frame(int value)
    {
        RandomFrame frame;
        frame.value = value;
        frame.skip_before = skipping;
        frame.sealed = skipping && current_if_open();
        frames.push_back(frame);
        skipping = frame.sealed ? true : skip_between;
    }

    void finish_if_chain()
    {
        if_labels.clear();
        skipping = any_sealed() ? true : skip_between;
    }

    void handle(const HeaderCommand& command)
    {
        if (command.command == "RANDOM") {
            int random_max = parse_int(command.value);
            if (random_max <= 0) {
                random_max = 1;
            }
            int requested = 1;
            if (values != nullptr && value_index < values->size()) {
                requested = (*values)[value_index];
            }
            ++value_index;
            push_frame(resolve_random_value(requested, random_max));
            return;
        }
        if (command.command == "SETRANDOM") {
            push_frame(parse_int(command.value));
            return;
        }
        if (command.command == "IF") {
            const int cond = parse_int(command.value);
            if (frames.empty() || any_sealed()) {
                skipping = true;
            } else {
                skipping = frames.back().value != cond;
            }
            if_labels.clear();
            if_labels.push_back(cond);
            set_if_open(true);
            return;
        }
        if (command.command == "ELSEIF") {
            const int cond = parse_int(command.value);
            if (frames.empty() || any_sealed()) {
                skipping = true;
            } else if (skipping) {
                skipping = contains_label(frames.back().value) || frames.back().value != cond;
            } else {
                skipping = true;
            }
            if_labels.push_back(cond);
            set_if_open(true);
            return;
        }
        if (command.command == "ELSE") {
            if (frames.empty() || any_sealed()) {
                skipping = true;
            } else if (skipping) {
                skipping = contains_label(frames.back().value);
            } else {
                skipping = true;
            }
            set_if_open(true);
            return;
        }
        if (command.command == "ENDIF") {
            if (current_if_open()) {
                set_if_open(false);
                finish_if_chain();
                return;
            }
            // The open IF on this frame is already closed. A following ENDIF
            // ends the frame RANDOM pushed inside the parent IF.
            if (!frames.empty()) {
                frames.pop_back();
                if (current_if_open()) {
                    set_if_open(false);
                }
            }
            finish_if_chain();
            return;
        }
        if (command.command == "ENDRANDOM") {
            if (!frames.empty()) {
                const bool restore = frames.back().skip_before;
                frames.pop_back();
                skipping = restore;
            }
        }
    }
};

template <typename Fn>
void for_each_line(std::string_view bytes, Fn&& fn)
{
    std::size_t offset = 0;
    while (offset < bytes.size()) {
        std::size_t end = offset;
        while (end < bytes.size() && bytes[end] != '\n' && bytes[end] != '\r') {
            ++end;
        }
        std::size_t raw_end = end;
        if (raw_end < bytes.size() && bytes[raw_end] == '\r') {
            ++raw_end;
            if (raw_end < bytes.size() && bytes[raw_end] == '\n') {
                ++raw_end;
            }
        } else if (raw_end < bytes.size() && bytes[raw_end] == '\n') {
            ++raw_end;
        }
        fn(bytes.substr(offset, end - offset), bytes.substr(offset, raw_end - offset));
        offset = raw_end;
    }
}

}  // namespace

std::vector<int> collect_bms_random_maxima(std::string_view bytes)
{
    std::vector<int> maxima;
    for_each_line(bytes, [&](std::string_view content, std::string_view) {
        const auto parsed = parse_line(content);
        if (!parsed || parsed->channel || parsed->command != "RANDOM") {
            return;
        }
        int random_max = parse_int(parsed->value);
        if (random_max <= 0) {
            random_max = 1;
        }
        maxima.push_back(random_max);
    });
    return maxima;
}

std::string apply_bms_random(
    std::string_view bytes,
    const std::vector<int>& values,
    bool skip_between_random_and_if)
{
    RandomState state;
    state.skip_between = skip_between_random_and_if;
    state.values = &values;
    std::string out;
    out.reserve(bytes.size());
    for_each_line(bytes, [&](std::string_view content, std::string_view raw) {
        const auto parsed = parse_line(content);
        if (parsed && !parsed->channel && is_control(parsed->command)) {
            state.handle(*parsed);
            return;
        }
        if (!state.skipping) {
            out.append(raw);
        }
    });
    return out;
}

}  // namespace ibms
