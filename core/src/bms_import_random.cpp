#include <ibms/bms_import_random.hpp>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <optional>
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
    char* end = nullptr;
    const long value = std::strtol(owned.c_str(), &end, 10);
    if (end == owned.c_str()) {
        return 0;
    }
    return static_cast<int>(value);
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
    return parsed;
}

int resolve_random_value(int requested, int random_max)
{
    const int max = random_max > 0 ? random_max : 1;
    if (requested > 0 && requested <= max) {
        return requested;
    }
    return 1 + (std::rand() % max);
}

struct RandomState {
    std::vector<int> randoms;
    std::vector<bool> skipping_stack;
    std::vector<int> if_labels;
    bool skipping = false;
    bool skip_between = false;
    std::size_t value_index = 0;
    const std::vector<int>* values = nullptr;

    bool contains_label(int value) const
    {
        return std::find(if_labels.begin(), if_labels.end(), value) != if_labels.end();
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
            skipping_stack.push_back(skipping);
            randoms.push_back(resolve_random_value(requested, random_max));
            skipping = skip_between;
            return;
        }
        if (command.command == "SETRANDOM") {
            randoms.push_back(parse_int(command.value));
            skipping = skip_between;
            return;
        }
        if (command.command == "IF") {
            const int cond = parse_int(command.value);
            if (randoms.empty()) {
                skipping = true;
            } else {
                skipping = randoms.back() != cond;
            }
            if_labels.clear();
            if_labels.push_back(cond);
            return;
        }
        if (command.command == "ELSEIF") {
            const int cond = parse_int(command.value);
            if (randoms.empty()) {
                skipping = true;
            } else if (skipping) {
                skipping = contains_label(randoms.back()) || randoms.back() != cond;
            } else {
                skipping = true;
            }
            if_labels.push_back(cond);
            return;
        }
        if (command.command == "ELSE") {
            if (randoms.empty()) {
                skipping = true;
            } else if (skipping) {
                skipping = contains_label(randoms.back());
            } else {
                skipping = true;
            }
            return;
        }
        if (command.command == "ENDIF") {
            skipping = skip_between;
            if_labels.clear();
            return;
        }
        if (command.command == "ENDRANDOM") {
            if (!randoms.empty()) {
                randoms.pop_back();
            }
            if (!skipping_stack.empty()) {
                skipping = skipping_stack.back();
                skipping_stack.pop_back();
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
