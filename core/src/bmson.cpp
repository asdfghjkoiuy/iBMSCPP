#include <ibms/bmson.hpp>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdint>
#include <limits>
#include <locale>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ibms {
namespace {

constexpr int k_default_resolution = 240;
constexpr int k_min_convert_resolution = 48;
constexpr int k_max_convert_resolution = 24000;
constexpr int k_max_json_depth = 64;

/// BmsONE `ResolutionUtil::ConvertTicks`: `original * new / old`, toward zero.
[[nodiscard]] std::int64_t convert_ticks(std::int64_t original, int new_resolution, int old_resolution)
{
    const std::int64_t next = new_resolution;
    const std::int64_t old = old_resolution;
#if defined(__SIZEOF_INT128__)
    const __int128 product = static_cast<__int128>(original) * static_cast<__int128>(next);
    return static_cast<std::int64_t>(product / static_cast<__int128>(old));
#else
    return (original / old) * next + (original % old) * next / old;
#endif
}

[[nodiscard]] double convert_pulse_value(double original, int new_resolution, int old_resolution)
{
    return original * static_cast<double>(new_resolution) / static_cast<double>(old_resolution);
}

[[nodiscard]] int positive_resolution(int resolution)
{
    return resolution > 0 ? resolution : k_default_resolution;
}

struct JsonValue {
    enum class Kind { null, boolean, number, string, array, object };

    Kind kind = Kind::null;
    bool boolean = false;
    double number = 0.0;
    std::string text;
    std::vector<JsonValue> array;
    std::vector<std::pair<std::string, JsonValue>> object;
};

class JsonParser {
public:
    explicit JsonParser(std::string_view text) : text_(text) {}

    JsonValue parse_document()
    {
        skip_bom();
        skip_ws();
        if (at_end()) {
            throw BmsonParseError("BMSON JSON is empty");
        }
        JsonValue value = parse_value(0);
        skip_ws();
        if (!at_end()) {
            throw BmsonParseError("BMSON JSON has trailing text");
        }
        return value;
    }

private:
    std::string_view text_;
    std::size_t pos_ = 0;

    [[nodiscard]] bool at_end() const { return pos_ >= text_.size(); }

    [[nodiscard]] char peek() const { return at_end() ? '\0' : text_[pos_]; }

    char take()
    {
        if (at_end()) {
            throw BmsonParseError("unexpected end of BMSON JSON");
        }
        return text_[pos_++];
    }

    void skip_bom()
    {
        if (text_.size() >= 3 && static_cast<unsigned char>(text_[0]) == 0xEF &&
            static_cast<unsigned char>(text_[1]) == 0xBB &&
            static_cast<unsigned char>(text_[2]) == 0xBF) {
            pos_ = 3;
        }
    }

    void skip_ws()
    {
        while (!at_end() && (text_[pos_] == ' ' || text_[pos_] == '\t' || text_[pos_] == '\n' ||
                             text_[pos_] == '\r')) {
            ++pos_;
        }
    }

    void expect_char(char expected)
    {
        skip_ws();
        if (take() != expected) {
            throw BmsonParseError(std::string("expected '") + expected + "' in BMSON JSON");
        }
    }

    JsonValue parse_value(int depth)
    {
        if (depth > k_max_json_depth) {
            throw BmsonParseError("BMSON JSON is nested too deeply");
        }
        skip_ws();
        const char head = peek();
        if (head == '{') {
            return parse_object(depth + 1);
        }
        if (head == '[') {
            return parse_array(depth + 1);
        }
        if (head == '"') {
            JsonValue value;
            value.kind = JsonValue::Kind::string;
            value.text = parse_string();
            return value;
        }
        if (head == 't' || head == 'f') {
            return parse_literal_bool();
        }
        if (head == 'n') {
            return parse_null();
        }
        if (head == '-' || (head >= '0' && head <= '9')) {
            return parse_number();
        }
        throw BmsonParseError("invalid BMSON JSON value");
    }

    JsonValue parse_object(int depth)
    {
        expect_char('{');
        JsonValue value;
        value.kind = JsonValue::Kind::object;
        skip_ws();
        if (peek() == '}') {
            take();
            return value;
        }
        while (true) {
            skip_ws();
            if (peek() != '"') {
                throw BmsonParseError("BMSON JSON object key must be a string");
            }
            std::string key = parse_string();
            expect_char(':');
            value.object.emplace_back(std::move(key), parse_value(depth));
            skip_ws();
            const char next = take();
            if (next == '}') {
                break;
            }
            if (next != ',') {
                throw BmsonParseError("expected ',' or '}' in BMSON JSON object");
            }
            skip_ws();
            if (peek() == '}') {
                throw BmsonParseError("trailing comma in BMSON JSON object");
            }
        }
        return value;
    }

    JsonValue parse_array(int depth)
    {
        expect_char('[');
        JsonValue value;
        value.kind = JsonValue::Kind::array;
        skip_ws();
        if (peek() == ']') {
            take();
            return value;
        }
        while (true) {
            value.array.push_back(parse_value(depth));
            skip_ws();
            const char next = take();
            if (next == ']') {
                break;
            }
            if (next != ',') {
                throw BmsonParseError("expected ',' or ']' in BMSON JSON array");
            }
            skip_ws();
            if (peek() == ']') {
                throw BmsonParseError("trailing comma in BMSON JSON array");
            }
        }
        return value;
    }

    JsonValue parse_literal_bool()
    {
        JsonValue value;
        value.kind = JsonValue::Kind::boolean;
        if (text_.substr(pos_, 4) == "true") {
            pos_ += 4;
            value.boolean = true;
            return value;
        }
        if (text_.substr(pos_, 5) == "false") {
            pos_ += 5;
            value.boolean = false;
            return value;
        }
        throw BmsonParseError("invalid boolean in BMSON JSON");
    }

    JsonValue parse_null()
    {
        if (text_.substr(pos_, 4) != "null") {
            throw BmsonParseError("invalid null in BMSON JSON");
        }
        pos_ += 4;
        JsonValue value;
        value.kind = JsonValue::Kind::null;
        return value;
    }

    JsonValue parse_number()
    {
        const std::size_t start = pos_;
        if (peek() == '-') {
            take();
        }
        if (peek() == '0') {
            take();
        } else if (peek() >= '1' && peek() <= '9') {
            while (peek() >= '0' && peek() <= '9') {
                take();
            }
        } else {
            throw BmsonParseError("invalid number in BMSON JSON");
        }
        if (peek() == '.') {
            take();
            if (peek() < '0' || peek() > '9') {
                throw BmsonParseError("invalid fraction in BMSON JSON");
            }
            while (peek() >= '0' && peek() <= '9') {
                take();
            }
        }
        if (peek() == 'e' || peek() == 'E') {
            take();
            if (peek() == '+' || peek() == '-') {
                take();
            }
            if (peek() < '0' || peek() > '9') {
                throw BmsonParseError("invalid exponent in BMSON JSON");
            }
            while (peek() >= '0' && peek() <= '9') {
                take();
            }
        }
        JsonValue value;
        value.kind = JsonValue::Kind::number;
        value.text = std::string(text_.substr(start, pos_ - start));
        try {
            value.number = std::stod(value.text);
        } catch (const std::exception&) {
            throw BmsonParseError("BMSON JSON number is out of range");
        }
        if (!std::isfinite(value.number)) {
            throw BmsonParseError("BMSON JSON number must be finite");
        }
        return value;
    }

    std::string parse_string()
    {
        if (take() != '"') {
            throw BmsonParseError("expected string in BMSON JSON");
        }
        std::string result;
        while (true) {
            const char ch = take();
            if (ch == '"') {
                return result;
            }
            if (static_cast<unsigned char>(ch) < 0x20) {
                throw BmsonParseError("unescaped control character in BMSON JSON string");
            }
            if (ch != '\\') {
                result.push_back(ch);
                continue;
            }
            const char esc = take();
            switch (esc) {
            case '"':
            case '\\':
            case '/':
                result.push_back(esc);
                break;
            case 'b':
                result.push_back('\b');
                break;
            case 'f':
                result.push_back('\f');
                break;
            case 'n':
                result.push_back('\n');
                break;
            case 'r':
                result.push_back('\r');
                break;
            case 't':
                result.push_back('\t');
                break;
            case 'u':
                append_utf8(result, parse_hex4());
                break;
            default:
                throw BmsonParseError("invalid escape in BMSON JSON string");
            }
        }
    }

    unsigned parse_hex4()
    {
        unsigned code = 0;
        for (int i = 0; i < 4; ++i) {
            const char ch = take();
            code <<= 4;
            if (ch >= '0' && ch <= '9') {
                code += static_cast<unsigned>(ch - '0');
            } else if (ch >= 'a' && ch <= 'f') {
                code += static_cast<unsigned>(ch - 'a' + 10);
            } else if (ch >= 'A' && ch <= 'F') {
                code += static_cast<unsigned>(ch - 'A' + 10);
            } else {
                throw BmsonParseError("invalid \\u escape in BMSON JSON");
            }
        }
        return code;
    }

    static void append_utf8(std::string& out, unsigned code)
    {
        if (code <= 0x7F) {
            out.push_back(static_cast<char>(code));
        } else if (code <= 0x7FF) {
            out.push_back(static_cast<char>(0xC0 | (code >> 6)));
            out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xE0 | (code >> 12)));
            out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
        }
    }
};

void write_json_string(std::string& out, std::string_view value)
{
    out.push_back('"');
    for (const unsigned char ch : value) {
        switch (ch) {
        case '"':
            out += "\\\"";
            break;
        case '\\':
            out += "\\\\";
            break;
        case '\b':
            out += "\\b";
            break;
        case '\f':
            out += "\\f";
            break;
        case '\n':
            out += "\\n";
            break;
        case '\r':
            out += "\\r";
            break;
        case '\t':
            out += "\\t";
            break;
        default:
            if (ch < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof(buf), "\\u%04x", ch);
                out += buf;
            } else {
                out.push_back(static_cast<char>(ch));
            }
            break;
        }
    }
    out.push_back('"');
}

void write_json_number(std::string& out, double value)
{
    if (!std::isfinite(value)) {
        throw BmsonParseError("cannot write a non-finite BMSON number");
    }
    if (std::trunc(value) == value && value >= static_cast<double>(std::numeric_limits<std::int64_t>::min()) &&
        value <= static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
        out += std::to_string(static_cast<std::int64_t>(value));
        return;
    }
    std::ostringstream stream;
    stream.imbue(std::locale::classic());
    stream.precision(15);
    stream << value;
    out += stream.str();
}

void write_indent(std::string& out, int indent)
{
    out.append(static_cast<std::size_t>(indent) * 2, ' ');
}

[[nodiscard]] const JsonValue* find_field(const JsonValue& object, std::string_view key)
{
    if (object.kind != JsonValue::Kind::object) {
        return nullptr;
    }
    for (const auto& field : object.object) {
        if (field.first == key) {
            return &field.second;
        }
    }
    return nullptr;
}

[[nodiscard]] const JsonValue* find_field_any(
    const JsonValue& object, std::initializer_list<std::string_view> keys)
{
    for (const std::string_view key : keys) {
        if (const JsonValue* found = find_field(object, key)) {
            return found;
        }
    }
    return nullptr;
}

[[nodiscard]] std::string compact_json(const JsonValue& value);

void write_compact(std::string& out, const JsonValue& value)
{
    switch (value.kind) {
    case JsonValue::Kind::null:
        out += "null";
        break;
    case JsonValue::Kind::boolean:
        out += value.boolean ? "true" : "false";
        break;
    case JsonValue::Kind::number:
        if (!value.text.empty()) {
            out += value.text;
        } else {
            write_json_number(out, value.number);
        }
        break;
    case JsonValue::Kind::string:
        write_json_string(out, value.text);
        break;
    case JsonValue::Kind::array: {
        out += '[';
        for (std::size_t i = 0; i < value.array.size(); ++i) {
            if (i != 0) {
                out += ',';
            }
            write_compact(out, value.array[i]);
        }
        out += ']';
        break;
    }
    case JsonValue::Kind::object: {
        out += '{';
        for (std::size_t i = 0; i < value.object.size(); ++i) {
            if (i != 0) {
                out += ',';
            }
            write_json_string(out, value.object[i].first);
            out += ':';
            write_compact(out, value.object[i].second);
        }
        out += '}';
        break;
    }
    }
}

std::string compact_json(const JsonValue& value)
{
    std::string out;
    write_compact(out, value);
    return out;
}

using ExtraJson = std::vector<std::pair<std::string, std::string>>;

void take_extras(const JsonValue& object, const std::vector<std::string_view>& known, ExtraJson& extras)
{
    extras.clear();
    if (object.kind != JsonValue::Kind::object) {
        return;
    }
    for (const auto& field : object.object) {
        bool is_known = false;
        for (const auto key : known) {
            if (field.first == key) {
                is_known = true;
                break;
            }
        }
        if (!is_known) {
            extras.emplace_back(field.first, compact_json(field.second));
        }
    }
}

[[nodiscard]] std::string require_string(const JsonValue* value, std::string_view field)
{
    if (value == nullptr) {
        return {};
    }
    if (value->kind != JsonValue::Kind::string) {
        throw BmsonParseError(std::string(field) + " must be a string");
    }
    return value->text;
}

[[nodiscard]] bool require_bool(const JsonValue* value, bool fallback, std::string_view field)
{
    if (value == nullptr) {
        return fallback;
    }
    if (value->kind != JsonValue::Kind::boolean) {
        throw BmsonParseError(std::string(field) + " must be a boolean");
    }
    return value->boolean;
}

[[nodiscard]] double require_number(const JsonValue* value, double fallback, std::string_view field)
{
    if (value == nullptr) {
        return fallback;
    }
    if (value->kind != JsonValue::Kind::number) {
        throw BmsonParseError(std::string(field) + " must be a number");
    }
    return value->number;
}

[[nodiscard]] std::int64_t require_pulse(const JsonValue* value, std::int64_t fallback, std::string_view field)
{
    if (value == nullptr) {
        return fallback;
    }
    if (value->kind != JsonValue::Kind::number) {
        throw BmsonParseError(std::string(field) + " must be an integer pulse");
    }
    const double nearest = std::round(value->number);
    if (std::abs(value->number - nearest) > 1e-9) {
        throw BmsonParseError(std::string(field) + " must be an integer pulse");
    }
    if (nearest < static_cast<double>(std::numeric_limits<std::int64_t>::min()) ||
        nearest > static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
        throw BmsonParseError(std::string(field) + " is outside the pulse range");
    }
    return static_cast<std::int64_t>(nearest);
}

[[nodiscard]] int require_int(const JsonValue* value, int fallback, std::string_view field)
{
    const std::int64_t pulse = require_pulse(value, fallback, field);
    if (pulse < std::numeric_limits<int>::min() || pulse > std::numeric_limits<int>::max()) {
        throw BmsonParseError(std::string(field) + " is outside the integer range");
    }
    return static_cast<int>(pulse);
}

void parse_bga_headers(
    const JsonValue* array,
    std::string_view field,
    std::vector<BmsonBgaHeader>& headers,
    std::vector<ExtraJson>& extras)
{
    headers.clear();
    extras.clear();
    if (array == nullptr) {
        return;
    }
    if (array->kind != JsonValue::Kind::array) {
        throw BmsonParseError(std::string(field) + " must be an array");
    }
    std::map<int, std::pair<BmsonBgaHeader, ExtraJson>> by_id;
    for (const auto& item : array->array) {
        if (item.kind != JsonValue::Kind::object) {
            throw BmsonParseError(std::string(field) + " entries must be objects");
        }
        BmsonBgaHeader header;
        header.id = require_int(find_field_any(item, {"id", "ID"}), 0, field);
        header.name = require_string(find_field(item, "name"), field);
        ExtraJson extra;
        take_extras(item, {"id", "ID", "name"}, extra);
        by_id[header.id] = {std::move(header), std::move(extra)};
    }
    for (auto& [_, item] : by_id) {
        headers.push_back(std::move(item.first));
        extras.push_back(std::move(item.second));
    }
}

void parse_bga_events(
    const JsonValue* array,
    std::string_view field,
    std::vector<BmsonBgaEvent>& events,
    std::vector<ExtraJson>& extras)
{
    events.clear();
    extras.clear();
    if (array == nullptr) {
        return;
    }
    if (array->kind != JsonValue::Kind::array) {
        throw BmsonParseError(std::string(field) + " must be an array");
    }
    std::map<std::int64_t, std::pair<BmsonBgaEvent, ExtraJson>> by_y;
    for (const auto& item : array->array) {
        if (item.kind != JsonValue::Kind::object) {
            throw BmsonParseError(std::string(field) + " entries must be objects");
        }
        BmsonBgaEvent event;
        event.y = require_pulse(find_field(item, "y"), 0, field);
        event.id = require_int(find_field_any(item, {"id", "ID"}), 0, field);
        ExtraJson extra;
        take_extras(item, {"y", "id", "ID"}, extra);
        by_y[event.y] = {event, std::move(extra)};
    }
    for (auto& [_, item] : by_y) {
        events.push_back(item.first);
        extras.push_back(std::move(item.second));
    }
}

void append_field(std::vector<std::pair<std::string, std::string>>& fields, std::string key, std::string value)
{
    fields.emplace_back(std::move(key), std::move(value));
}

std::string quote_string(std::string_view value)
{
    std::string out;
    write_json_string(out, value);
    return out;
}

std::string format_number(double value)
{
    std::string out;
    write_json_number(out, value);
    return out;
}

std::string format_int(std::int64_t value)
{
    return std::to_string(value);
}

void write_pretty_value(std::string& out, std::string_view compact, int indent);

void write_pretty_object(std::string& out, const std::vector<std::pair<std::string, std::string>>& fields, int indent)
{
    if (fields.empty()) {
        out += "{}";
        return;
    }
    out += "{\n";
    for (std::size_t i = 0; i < fields.size(); ++i) {
        write_indent(out, indent + 1);
        write_json_string(out, fields[i].first);
        out += ": ";
        write_pretty_value(out, fields[i].second, indent + 1);
        out += (i + 1 < fields.size()) ? ",\n" : "\n";
    }
    write_indent(out, indent);
    out += '}';
}

void write_pretty_array(std::string& out, const std::vector<std::string>& items, int indent)
{
    if (items.empty()) {
        out += "[]";
        return;
    }
    out += "[\n";
    for (std::size_t i = 0; i < items.size(); ++i) {
        write_indent(out, indent + 1);
        write_pretty_value(out, items[i], indent + 1);
        out += (i + 1 < items.size()) ? ",\n" : "\n";
    }
    write_indent(out, indent);
    out += ']';
}

void write_pretty_value(std::string& out, std::string_view compact, int indent)
{
    if (compact.empty()) {
        out += "null";
        return;
    }
    const char head = compact.front();
    if (head != '{' && head != '[') {
        out.append(compact);
        return;
    }
    const JsonValue parsed = JsonParser(compact).parse_document();
    if (parsed.kind == JsonValue::Kind::object) {
        std::vector<std::pair<std::string, std::string>> fields;
        fields.reserve(parsed.object.size());
        for (const auto& field : parsed.object) {
            fields.emplace_back(field.first, compact_json(field.second));
        }
        write_pretty_object(out, fields, indent);
        return;
    }
    if (parsed.kind == JsonValue::Kind::array) {
        std::vector<std::string> items;
        items.reserve(parsed.array.size());
        for (const auto& item : parsed.array) {
            items.push_back(compact_json(item));
        }
        write_pretty_array(out, items, indent);
        return;
    }
    out.append(compact);
}

}  // namespace

BmsonParseError::BmsonParseError(const std::string& message) : std::invalid_argument(message) {}

BmsonDocument BmsonDocument::empty()
{
    return {};
}

BmsonDocument BmsonDocument::from_json(std::string_view text)
{
    const JsonValue root = JsonParser(text).parse_document();
    if (root.kind != JsonValue::Kind::object) {
        throw BmsonParseError("BMSON root must be a JSON object");
    }

    BmsonDocument document;
    if (const JsonValue* version = find_field(root, "version")) {
        document.version_ = require_string(version, "version");
        if (document.version_.empty()) {
            document.version_ = "1.0.0";
        }
    }

    const JsonValue* info_value = find_field(root, "info");
    if (info_value != nullptr && info_value->kind != JsonValue::Kind::object) {
        throw BmsonParseError("info must be a JSON object");
    }
    const JsonValue info_object = info_value == nullptr ? JsonValue{} : *info_value;
    if (info_value == nullptr) {
        document.info_ = BmsonInfo{};
    } else {
        document.info_.title = require_string(find_field(info_object, "title"), "title");
        document.info_.subtitle = require_string(find_field(info_object, "subtitle"), "subtitle");
        document.info_.artist = require_string(find_field(info_object, "artist"), "artist");
        document.info_.genre = require_string(find_field(info_object, "genre"), "genre");
        document.info_.mode_hint = require_string(find_field(info_object, "modeHint"), "modeHint");
        if (document.info_.mode_hint.empty()) {
            document.info_.mode_hint = "beat-7k";
        }
        document.info_.chart_name = require_string(find_field(info_object, "chartName"), "chartName");
        document.info_.level = require_int(find_field(info_object, "level"), 1, "level");
        document.info_.init_bpm = require_number(find_field(info_object, "initBPM"), 120.0, "initBPM");
        document.info_.judge_rank = require_number(find_field(info_object, "judgeRank"), 100.0, "judgeRank");
        document.info_.total = require_number(find_field(info_object, "total"), 100.0, "total");
        document.info_.resolution = require_int(find_field(info_object, "resolution"), k_default_resolution, "resolution");
        if (document.info_.resolution < 0) {
            throw BmsonParseError("resolution must not be negative");
        }
        if (document.info_.resolution == 0) {
            document.info_.resolution = k_default_resolution;
        }
        if (const JsonValue* subartists = find_field(info_object, "subartists")) {
            if (subartists->kind != JsonValue::Kind::array) {
                throw BmsonParseError("subartists must be an array");
            }
            for (const auto& entry : subartists->array) {
                if (entry.kind != JsonValue::Kind::string) {
                    throw BmsonParseError("subartists entries must be strings");
                }
                document.info_.subartists.push_back(entry.text);
            }
        }
        take_extras(
            info_object,
            {"title", "subtitle", "artist", "subartists", "genre", "modeHint", "chartName", "level",
             "initBPM", "judgeRank", "total", "resolution"},
            document.extra_info_);
    }

    document.extra_lines_.clear();
    if (const JsonValue* lines = find_field(root, "lines")) {
        if (lines->kind != JsonValue::Kind::array) {
            throw BmsonParseError("lines must be an array");
        }
        for (const auto& item : lines->array) {
            if (item.kind != JsonValue::Kind::object) {
                throw BmsonParseError("lines entries must be objects");
            }
            BmsonBarLine line;
            line.y = require_pulse(find_field(item, "y"), 0, "lines.y");
            ExtraJson extra;
            take_extras(item, {"y"}, extra);
            document.lines_.push_back(line);
            document.extra_lines_.push_back(std::move(extra));
        }
    }

    if (const JsonValue* notes = find_field(root, "bpmNotes")) {
        if (notes->kind != JsonValue::Kind::array) {
            throw BmsonParseError("bpmNotes must be an array");
        }
        for (const auto& item : notes->array) {
            if (item.kind != JsonValue::Kind::object) {
                throw BmsonParseError("bpmNotes entries must be objects");
            }
            BmsonBpmNote note;
            note.y = require_pulse(find_field(item, "y"), 0, "bpmNotes.y");
            note.v = require_number(find_field(item, "v"), 0.0, "bpmNotes.v");
            ExtraJson extra;
            take_extras(item, {"y", "v"}, extra);
            document.bpm_notes_.push_back(note);
            document.extra_bpm_notes_.push_back(std::move(extra));
        }
    }

    if (const JsonValue* notes = find_field(root, "stopNotes")) {
        if (notes->kind != JsonValue::Kind::array) {
            throw BmsonParseError("stopNotes must be an array");
        }
        for (const auto& item : notes->array) {
            if (item.kind != JsonValue::Kind::object) {
                throw BmsonParseError("stopNotes entries must be objects");
            }
            BmsonStopNote note;
            note.y = require_pulse(find_field(item, "y"), 0, "stopNotes.y");
            note.v = require_number(find_field(item, "v"), 0.0, "stopNotes.v");
            ExtraJson extra;
            take_extras(item, {"y", "v"}, extra);
            document.stop_notes_.push_back(note);
            document.extra_stop_notes_.push_back(std::move(extra));
        }
    }

    if (const JsonValue* channels = find_field(root, "soundChannels")) {
        if (channels->kind != JsonValue::Kind::array) {
            throw BmsonParseError("soundChannels must be an array");
        }
        for (const auto& item : channels->array) {
            if (item.kind != JsonValue::Kind::object) {
                throw BmsonParseError("soundChannels entries must be objects");
            }
            BmsonSoundChannel channel;
            channel.name = require_string(find_field(item, "name"), "soundChannels.name");
            ExtraJson note_parent_extra;
            std::vector<ExtraJson> note_extras;
            if (const JsonValue* notes = find_field(item, "notes")) {
                if (notes->kind != JsonValue::Kind::array) {
                    throw BmsonParseError("soundChannels.notes must be an array");
                }
                for (const auto& note_value : notes->array) {
                    if (note_value.kind != JsonValue::Kind::object) {
                        throw BmsonParseError("soundChannels.notes entries must be objects");
                    }
                    BmsonNote note;
                    note.x = require_pulse(find_field(note_value, "x"), 0, "notes.x");
                    note.y = require_pulse(find_field(note_value, "y"), 0, "notes.y");
                    note.l = require_pulse(find_field(note_value, "l"), 0, "notes.l");
                    if (note.l < 0) {
                        throw BmsonParseError("notes.l must not be negative");
                    }
                    note.c = require_bool(find_field(note_value, "c"), false, "notes.c");
                    ExtraJson extra;
                    take_extras(note_value, {"x", "y", "l", "c"}, extra);
                    channel.notes.push_back(note);
                    note_extras.push_back(std::move(extra));
                }
            }
            take_extras(item, {"name", "notes"}, note_parent_extra);
            document.sound_channels_.push_back(std::move(channel));
            document.extra_channels_.push_back(std::move(note_parent_extra));
            document.extra_notes_.push_back(std::move(note_extras));
        }
    }

    if (const JsonValue* bga = find_field(root, "bga")) {
        if (bga->kind != JsonValue::Kind::object) {
            throw BmsonParseError("bga must be a JSON object");
        }
        parse_bga_headers(
            find_field_any(*bga, {"bga_header", "bgaHeader"}),
            "bga.bga_header",
            document.bga_headers_,
            document.extra_bga_headers_);
        parse_bga_events(
            find_field_any(*bga, {"bga_events", "bgaNotes"}),
            "bga.bga_events",
            document.bga_events_,
            document.extra_bga_events_);
        parse_bga_events(
            find_field_any(*bga, {"layer_events", "layerNotes"}),
            "bga.layer_events",
            document.layer_events_,
            document.extra_layer_events_);
        parse_bga_events(
            find_field_any(*bga, {"poor_events", "poorNotes"}),
            "bga.poor_events",
            document.poor_events_,
            document.extra_poor_events_);
        take_extras(
            *bga,
            {"bga_header", "bgaHeader", "bga_events", "bgaNotes", "layer_events", "layerNotes",
             "poor_events", "poorNotes"},
            document.extra_bga_);
    }

    take_extras(
        root,
        {"version", "info", "lines", "bpmNotes", "stopNotes", "soundChannels", "bga"},
        document.extra_root_);
    return document;
}

namespace {

void append_extras(std::vector<std::pair<std::string, std::string>>& fields, const ExtraJson& extras)
{
    for (const auto& extra : extras) {
        fields.push_back(extra);
    }
}

std::string object_json(const std::vector<std::pair<std::string, std::string>>& fields)
{
    std::string out;
    write_pretty_object(out, fields, 0);
    return out;
}

}  // namespace

namespace {

bool pulses_overlap(std::int64_t left_y, std::int64_t left_l, std::int64_t right_y, std::int64_t right_l)
{
    return left_y <= right_y + right_l && right_y <= left_y + left_l;
}

void require_note_length(const BmsonNote& note)
{
    if (note.l < 0) {
        throw BmsonParseError("notes.l must not be negative");
    }
}

[[nodiscard]] bool is_first_class_info_key(std::string_view key)
{
    static constexpr std::string_view known[] = {
        "title", "subtitle", "artist", "subartists", "genre", "modeHint", "chartName",
        "level", "initBPM", "judgeRank", "total", "resolution"};
    for (const auto item : known) {
        if (item == key) {
            return true;
        }
    }
    return false;
}

/// Official BMSON 1.0.0 image / preview keys stored in `extra_info_`.
/// BmsONE `DocumentInfo::SupportedKeys` treats these as first-class fields.
[[nodiscard]] bool is_official_info_extra_key(std::string_view key)
{
    static constexpr std::string_view known[] = {
        "banner", "backImage", "eyecatchImage", "titleImage", "previewMusic"};
    for (const auto item : known) {
        if (item == key) {
            return true;
        }
    }
    return false;
}

[[nodiscard]] std::string extra_object_json(const ExtraJson& extras)
{
    std::string out = "{";
    for (std::size_t i = 0; i < extras.size(); ++i) {
        if (i != 0) {
            out += ',';
        }
        out += quote_string(extras[i].first);
        out += ':';
        out += extras[i].second;
    }
    out += '}';
    return out;
}

void require_no_lane_conflict(
    const std::vector<BmsonSoundChannel>& channels,
    std::size_t channel_index,
    const BmsonNote& note,
    std::optional<std::int64_t> skip_y)
{
    if (note.x <= 0) {
        if (channel_index >= channels.size()) {
            return;
        }
        for (const auto& existing : channels[channel_index].notes) {
            if (existing.y != note.y || existing.x > 0) {
                continue;
            }
            if (skip_y.has_value() && existing.y == *skip_y) {
                continue;
            }
            throw BmsonParseError("Overlapping notes");
        }
        return;
    }
    for (std::size_t other_index = 0; other_index < channels.size(); ++other_index) {
        for (const auto& existing : channels[other_index].notes) {
            if (existing.x <= 0 || existing.x != note.x) {
                continue;
            }
            if (skip_y.has_value() && other_index == channel_index && existing.y == *skip_y) {
                continue;
            }
            if (pulses_overlap(existing.y, existing.l, note.y, note.l)) {
                throw BmsonParseError("Overlapping notes");
            }
        }
    }
}

}  // namespace

void BmsonDocument::insert_sound_note(std::size_t channel_index, BmsonNote note)
{
    require_note_length(note);
    if (sound_channels_.empty()) {
        sound_channels_.emplace_back();
        extra_channels_.emplace_back();
        extra_notes_.emplace_back();
        channel_index = 0;
    } else if (channel_index >= sound_channels_.size()) {
        channel_index = 0;
    }
    if (extra_channels_.size() < sound_channels_.size()) {
        extra_channels_.resize(sound_channels_.size());
    }
    if (extra_notes_.size() < sound_channels_.size()) {
        extra_notes_.resize(sound_channels_.size());
    }
    auto& notes = sound_channels_[channel_index].notes;
    if (note.x <= 0) {
        require_no_lane_conflict(sound_channels_, channel_index, note, std::nullopt);
    } else {
        require_no_lane_conflict(sound_channels_, channel_index, note, note.y);
    }
    for (auto& existing : notes) {
        if (existing.y == note.y) {
            existing = note;
            return;
        }
    }
    notes.push_back(note);
    extra_notes_[channel_index].emplace_back();
}

bool BmsonDocument::erase_sound_note(std::size_t channel_index, std::int64_t y)
{
    if (channel_index >= sound_channels_.size()) {
        return false;
    }
    auto& notes = sound_channels_[channel_index].notes;
    for (std::size_t index = 0; index < notes.size(); ++index) {
        if (notes[index].y != y) {
            continue;
        }
        notes.erase(notes.begin() + static_cast<std::ptrdiff_t>(index));
        if (channel_index < extra_notes_.size() && index < extra_notes_[channel_index].size()) {
            extra_notes_[channel_index].erase(
                extra_notes_[channel_index].begin() + static_cast<std::ptrdiff_t>(index));
        }
        return true;
    }
    return false;
}

void BmsonDocument::replace_sound_note(std::size_t channel_index, std::int64_t old_y, BmsonNote note)
{
    require_note_length(note);
    if (channel_index >= sound_channels_.size()) {
        throw BmsonParseError("no sound note at the requested pulse");
    }
    auto& notes = sound_channels_[channel_index].notes;
    std::size_t found = notes.size();
    for (std::size_t index = 0; index < notes.size(); ++index) {
        if (notes[index].y == old_y) {
            found = index;
            continue;
        }
        if (notes[index].y == note.y) {
            throw BmsonParseError("Overlapping notes");
        }
    }
    if (found == notes.size()) {
        throw BmsonParseError("no sound note at the requested pulse");
    }
    require_no_lane_conflict(sound_channels_, channel_index, note, old_y);
    notes[found] = note;
}

namespace {

[[nodiscard]] std::size_t require_note_index(
    const std::vector<BmsonSoundChannel>& channels,
    std::size_t channel_index,
    std::int64_t y)
{
    if (channel_index >= channels.size()) {
        throw BmsonParseError("no sound note at the requested pulse");
    }
    const auto& notes = channels[channel_index].notes;
    for (std::size_t index = 0; index < notes.size(); ++index) {
        if (notes[index].y == y) {
            return index;
        }
    }
    throw BmsonParseError("no sound note at the requested pulse");
}

}  // namespace

std::string BmsonDocument::note_extra_object_json(std::size_t channel_index, std::int64_t y) const
{
    const std::size_t index = require_note_index(sound_channels_, channel_index, y);
    ExtraJson extras;
    if (channel_index < extra_notes_.size() && index < extra_notes_[channel_index].size()) {
        extras = extra_notes_[channel_index][index];
    }
    return extra_object_json(extras);
}

void BmsonDocument::replace_note_extra_object_json(
    std::size_t channel_index, std::int64_t y, std::string_view object_json)
{
    const std::size_t index = require_note_index(sound_channels_, channel_index, y);
    const JsonValue root = JsonParser(object_json).parse_document();
    if (root.kind != JsonValue::Kind::object) {
        throw BmsonParseError("note extra fields must be a JSON object");
    }
    ExtraJson extras;
    take_extras(root, {"x", "y", "l", "c"}, extras);
    if (extra_notes_.size() < sound_channels_.size()) {
        extra_notes_.resize(sound_channels_.size());
    }
    extra_notes_[channel_index].resize(sound_channels_[channel_index].notes.size());
    extra_notes_[channel_index][index] = std::move(extras);
}

void BmsonDocument::upsert_bpm_note(BmsonBpmNote note)
{
    if (!(note.v > 0.0) || !std::isfinite(note.v)) {
        throw BmsonParseError("bpmNotes.v must be positive");
    }
    if (extra_bpm_notes_.size() < bpm_notes_.size()) {
        extra_bpm_notes_.resize(bpm_notes_.size());
    }
    for (auto& existing : bpm_notes_) {
        if (existing.y == note.y) {
            existing = note;
            return;
        }
    }
    bpm_notes_.push_back(note);
    extra_bpm_notes_.emplace_back();
}

bool BmsonDocument::erase_bpm_note(std::int64_t y)
{
    for (std::size_t index = 0; index < bpm_notes_.size(); ++index) {
        if (bpm_notes_[index].y != y) {
            continue;
        }
        bpm_notes_.erase(bpm_notes_.begin() + static_cast<std::ptrdiff_t>(index));
        if (index < extra_bpm_notes_.size()) {
            extra_bpm_notes_.erase(extra_bpm_notes_.begin() + static_cast<std::ptrdiff_t>(index));
        }
        return true;
    }
    return false;
}

void BmsonDocument::upsert_stop_note(BmsonStopNote note)
{
    if (!(note.v > 0.0) || !std::isfinite(note.v)) {
        throw BmsonParseError("stopNotes.v must be positive");
    }
    if (extra_stop_notes_.size() < stop_notes_.size()) {
        extra_stop_notes_.resize(stop_notes_.size());
    }
    for (auto& existing : stop_notes_) {
        if (existing.y == note.y) {
            existing = note;
            return;
        }
    }
    stop_notes_.push_back(note);
    extra_stop_notes_.emplace_back();
}

bool BmsonDocument::erase_stop_note(std::int64_t y)
{
    for (std::size_t index = 0; index < stop_notes_.size(); ++index) {
        if (stop_notes_[index].y != y) {
            continue;
        }
        stop_notes_.erase(stop_notes_.begin() + static_cast<std::ptrdiff_t>(index));
        if (index < extra_stop_notes_.size()) {
            extra_stop_notes_.erase(extra_stop_notes_.begin() + static_cast<std::ptrdiff_t>(index));
        }
        return true;
    }
    return false;
}

void BmsonDocument::replace_info(BmsonInfo info)
{
    info_ = std::move(info);
}

std::string BmsonDocument::info_extra_string(std::string_view key) const
{
    for (const auto& extra : extra_info_) {
        if (extra.first != key) {
            continue;
        }
        try {
            JsonParser parser(extra.second);
            const JsonValue value = parser.parse_document();
            if (value.kind == JsonValue::Kind::string) {
                return value.text;
            }
        } catch (const BmsonParseError&) {
            return {};
        }
        return {};
    }
    return {};
}

void BmsonDocument::set_info_extra_string(std::string key, std::string value)
{
    if (key.empty()) {
        throw BmsonParseError("info extra key must not be empty");
    }
    if (is_first_class_info_key(key)) {
        throw BmsonParseError("info extra key collides with a first-class field");
    }
    const auto matches = [&](const ExtraJson::value_type& extra) { return extra.first == key; };
    const auto it = std::find_if(extra_info_.begin(), extra_info_.end(), matches);
    if (value.empty()) {
        if (it != extra_info_.end()) {
            extra_info_.erase(it);
        }
        return;
    }
    std::string quoted = quote_string(value);
    if (it != extra_info_.end()) {
        it->second = std::move(quoted);
        return;
    }
    extra_info_.emplace_back(std::move(key), std::move(quoted));
}

std::string BmsonDocument::info_extra_object_json() const
{
    ExtraJson unknown;
    for (const auto& extra : extra_info_) {
        if (is_official_info_extra_key(extra.first) || is_first_class_info_key(extra.first)) {
            continue;
        }
        unknown.push_back(extra);
    }
    std::sort(
        unknown.begin(),
        unknown.end(),
        [](const ExtraJson::value_type& left, const ExtraJson::value_type& right) {
            return left.first < right.first;
        });
    return extra_object_json(unknown);
}

void BmsonDocument::replace_info_extra_object_json(std::string_view object_json)
{
    const JsonValue root = JsonParser(object_json).parse_document();
    if (root.kind != JsonValue::Kind::object) {
        throw BmsonParseError("info extra fields must be a JSON object");
    }
    ExtraJson incoming;
    take_extras(root, {}, incoming);

    ExtraJson next;
    for (const auto& extra : extra_info_) {
        if (is_official_info_extra_key(extra.first)) {
            next.push_back(extra);
        }
    }
    for (auto& extra : incoming) {
        if (extra.first.empty()) {
            throw BmsonParseError("info extra key must not be empty");
        }
        if (is_first_class_info_key(extra.first) || is_official_info_extra_key(extra.first)) {
            continue;
        }
        next.push_back(std::move(extra));
    }
    extra_info_ = std::move(next);
}

void BmsonDocument::replace_lines(std::vector<BmsonBarLine> lines)
{
    lines_ = std::move(lines);
    extra_lines_.assign(lines_.size(), ExtraJson{});
}

void BmsonDocument::replace_bpm_notes(std::vector<BmsonBpmNote> notes)
{
    bpm_notes_ = std::move(notes);
    extra_bpm_notes_.assign(bpm_notes_.size(), ExtraJson{});
}

void BmsonDocument::replace_stop_notes(std::vector<BmsonStopNote> notes)
{
    stop_notes_ = std::move(notes);
    extra_stop_notes_.assign(stop_notes_.size(), ExtraJson{});
}

void BmsonDocument::replace_sound_channels(std::vector<BmsonSoundChannel> channels)
{
    sound_channels_ = std::move(channels);
    extra_channels_.assign(sound_channels_.size(), ExtraJson{});
    extra_notes_.assign(sound_channels_.size(), std::vector<ExtraJson>{});
    for (std::size_t index = 0; index < sound_channels_.size(); ++index) {
        extra_notes_[index].assign(sound_channels_[index].notes.size(), ExtraJson{});
    }
}

void BmsonDocument::replace_bga(
    std::vector<BmsonBgaHeader> headers,
    std::vector<BmsonBgaEvent> bga_events,
    std::vector<BmsonBgaEvent> layer_events,
    std::vector<BmsonBgaEvent> poor_events)
{
    std::map<int, BmsonBgaHeader> headers_by_id;
    for (auto& header : headers) {
        headers_by_id[header.id] = std::move(header);
    }
    bga_headers_.clear();
    extra_bga_headers_.clear();
    for (auto& [_, header] : headers_by_id) {
        bga_headers_.push_back(std::move(header));
        extra_bga_headers_.emplace_back();
    }

    auto assign_events = [](std::vector<BmsonBgaEvent> incoming,
                            std::vector<BmsonBgaEvent>& dest,
                            std::vector<ExtraJson>& extras) {
        std::map<std::int64_t, BmsonBgaEvent> by_y;
        for (const auto& event : incoming) {
            by_y[event.y] = event;
        }
        dest.clear();
        extras.clear();
        for (const auto& [_, event] : by_y) {
            dest.push_back(event);
            extras.emplace_back();
        }
    };
    assign_events(std::move(bga_events), bga_events_, extra_bga_events_);
    assign_events(std::move(layer_events), layer_events_, extra_layer_events_);
    assign_events(std::move(poor_events), poor_events_, extra_poor_events_);
}

void BmsonDocument::upsert_bga_header(BmsonBgaHeader header)
{
    if (extra_bga_headers_.size() < bga_headers_.size()) {
        extra_bga_headers_.resize(bga_headers_.size());
    }
    for (auto& existing : bga_headers_) {
        if (existing.id == header.id) {
            existing = std::move(header);
            return;
        }
    }
    bga_headers_.push_back(std::move(header));
    extra_bga_headers_.emplace_back();
}

void BmsonDocument::upsert_bga_event(BmsonBgaLane lane, BmsonBgaEvent event)
{
    auto* events = &bga_events_;
    auto* extras = &extra_bga_events_;
    if (lane == BmsonBgaLane::layer) {
        events = &layer_events_;
        extras = &extra_layer_events_;
    } else if (lane == BmsonBgaLane::poor) {
        events = &poor_events_;
        extras = &extra_poor_events_;
    }
    if (extras->size() < events->size()) {
        extras->resize(events->size());
    }
    for (auto& existing : *events) {
        if (existing.y == event.y) {
            existing = event;
            return;
        }
    }
    events->push_back(event);
    extras->emplace_back();
}

bool BmsonDocument::erase_bga_event(BmsonBgaLane lane, std::int64_t y)
{
    auto* events = &bga_events_;
    auto* extras = &extra_bga_events_;
    if (lane == BmsonBgaLane::layer) {
        events = &layer_events_;
        extras = &extra_layer_events_;
    } else if (lane == BmsonBgaLane::poor) {
        events = &poor_events_;
        extras = &extra_poor_events_;
    }
    for (std::size_t index = 0; index < events->size(); ++index) {
        if ((*events)[index].y != y) {
            continue;
        }
        events->erase(events->begin() + static_cast<std::ptrdiff_t>(index));
        if (index < extras->size()) {
            extras->erase(extras->begin() + static_cast<std::ptrdiff_t>(index));
        }
        return true;
    }
    return false;
}

int BmsonDocument::acceptable_resolution_divider() const
{
    std::int64_t divider = positive_resolution(info_.resolution);
    auto consider = [&](std::int64_t location) {
        location = location < 0 ? -location : location;
        if (location == 0 || divider <= 0) {
            return;
        }
        const std::int64_t remainder = location % divider;
        if (remainder != 0) {
            divider = std::gcd(divider, remainder);
        }
    };
    for (const auto& line : lines_) {
        consider(line.y);
    }
    for (const auto& note : bpm_notes_) {
        consider(note.y);
    }
    for (const auto& note : stop_notes_) {
        consider(note.y);
        consider(static_cast<std::int64_t>(std::llround(note.v)));
    }
    for (const auto& channel : sound_channels_) {
        for (const auto& note : channel.notes) {
            consider(note.y);
            if (note.l != 0) {
                consider(note.y + note.l);
            }
        }
    }
    for (const auto& event : bga_events_) {
        consider(event.y);
    }
    for (const auto& event : layer_events_) {
        consider(event.y);
    }
    for (const auto& event : poor_events_) {
        consider(event.y);
    }
    if (divider <= 0) {
        return 1;
    }
    if (divider > std::numeric_limits<int>::max()) {
        return std::numeric_limits<int>::max();
    }
    return static_cast<int>(divider);
}

bool BmsonDocument::resolution_conversion_loses_information(int new_resolution) const
{
    const int old = positive_resolution(info_.resolution);
    const int divider = acceptable_resolution_divider();
    if (divider <= 0) {
        return true;
    }
    const int unit = old / divider;
    if (unit <= 0) {
        return true;
    }
    return new_resolution % unit != 0;
}

void BmsonDocument::convert_resolution(int new_resolution)
{
    if (new_resolution < k_min_convert_resolution || new_resolution > k_max_convert_resolution) {
        throw BmsonParseError("resolution must be between 48 and 24000");
    }
    const int old = positive_resolution(info_.resolution);
    if (new_resolution == old) {
        return;
    }
    info_.resolution = new_resolution;
    for (auto& line : lines_) {
        line.y = convert_ticks(line.y, new_resolution, old);
    }
    for (auto& note : bpm_notes_) {
        note.y = convert_ticks(note.y, new_resolution, old);
    }
    for (auto& note : stop_notes_) {
        note.y = convert_ticks(note.y, new_resolution, old);
        note.v = convert_pulse_value(note.v, new_resolution, old);
    }
    for (auto& channel : sound_channels_) {
        for (auto& note : channel.notes) {
            note.y = convert_ticks(note.y, new_resolution, old);
            note.l = convert_ticks(note.l, new_resolution, old);
        }
    }
    for (auto& event : bga_events_) {
        event.y = convert_ticks(event.y, new_resolution, old);
    }
    for (auto& event : layer_events_) {
        event.y = convert_ticks(event.y, new_resolution, old);
    }
    for (auto& event : poor_events_) {
        event.y = convert_ticks(event.y, new_resolution, old);
    }
}

std::string BmsonDocument::to_json() const
{
    std::vector<std::pair<std::string, std::string>> info_fields;
    append_field(info_fields, "title", quote_string(info_.title));
    append_field(info_fields, "subtitle", quote_string(info_.subtitle));
    append_field(info_fields, "artist", quote_string(info_.artist));
    std::vector<std::string> subartists;
    subartists.reserve(info_.subartists.size());
    for (const auto& name : info_.subartists) {
        subartists.push_back(quote_string(name));
    }
    std::string subartists_json;
    write_pretty_array(subartists_json, subartists, 2);
    append_field(info_fields, "subartists", std::move(subartists_json));
    append_field(info_fields, "genre", quote_string(info_.genre));
    append_field(info_fields, "modeHint", quote_string(info_.mode_hint));
    append_field(info_fields, "chartName", quote_string(info_.chart_name));
    append_field(info_fields, "level", format_int(info_.level));
    append_field(info_fields, "initBPM", format_number(info_.init_bpm));
    append_field(info_fields, "judgeRank", format_number(info_.judge_rank));
    append_field(info_fields, "total", format_number(info_.total));
    append_field(info_fields, "resolution", format_int(info_.resolution));
    append_extras(info_fields, extra_info_);

    std::string info_json;
    write_pretty_object(info_json, info_fields, 1);

    auto line_json = [&](std::size_t index) {
        std::vector<std::pair<std::string, std::string>> fields;
        append_field(fields, "y", format_int(lines_[index].y));
        if (index < extra_lines_.size()) {
            append_extras(fields, extra_lines_[index]);
        }
        return object_json(fields);
    };
    auto bpm_json = [&](std::size_t index) {
        std::vector<std::pair<std::string, std::string>> fields;
        append_field(fields, "y", format_int(bpm_notes_[index].y));
        append_field(fields, "v", format_number(bpm_notes_[index].v));
        if (index < extra_bpm_notes_.size()) {
            append_extras(fields, extra_bpm_notes_[index]);
        }
        return object_json(fields);
    };
    auto stop_json = [&](std::size_t index) {
        std::vector<std::pair<std::string, std::string>> fields;
        append_field(fields, "y", format_int(stop_notes_[index].y));
        append_field(fields, "v", format_number(stop_notes_[index].v));
        if (index < extra_stop_notes_.size()) {
            append_extras(fields, extra_stop_notes_[index]);
        }
        return object_json(fields);
    };
    auto note_json = [&](std::size_t channel, std::size_t index) {
        std::vector<std::pair<std::string, std::string>> fields;
        const auto& note = sound_channels_[channel].notes[index];
        append_field(fields, "x", format_int(note.x));
        append_field(fields, "y", format_int(note.y));
        append_field(fields, "l", format_int(note.l));
        append_field(fields, "c", std::string(note.c ? "true" : "false"));
        if (channel < extra_notes_.size() && index < extra_notes_[channel].size()) {
            append_extras(fields, extra_notes_[channel][index]);
        }
        return object_json(fields);
    };
    auto bga_header_json = [&](std::size_t index) {
        std::vector<std::pair<std::string, std::string>> fields;
        append_field(fields, "id", format_int(bga_headers_[index].id));
        append_field(fields, "name", quote_string(bga_headers_[index].name));
        if (index < extra_bga_headers_.size()) {
            append_extras(fields, extra_bga_headers_[index]);
        }
        return object_json(fields);
    };
    auto bga_event_json = [&](const std::vector<BmsonBgaEvent>& events,
                              const std::vector<ExtraJson>& extras,
                              std::size_t index) {
        std::vector<std::pair<std::string, std::string>> fields;
        append_field(fields, "y", format_int(events[index].y));
        append_field(fields, "id", format_int(events[index].id));
        if (index < extras.size()) {
            append_extras(fields, extras[index]);
        }
        return object_json(fields);
    };
    auto channel_json = [&](std::size_t index) {
        std::vector<std::string> notes;
        notes.reserve(sound_channels_[index].notes.size());
        for (std::size_t i = 0; i < sound_channels_[index].notes.size(); ++i) {
            notes.push_back(note_json(index, i));
        }
        std::string notes_json;
        write_pretty_array(notes_json, notes, 3);
        std::vector<std::pair<std::string, std::string>> fields;
        append_field(fields, "name", quote_string(sound_channels_[index].name));
        append_field(fields, "notes", std::move(notes_json));
        if (index < extra_channels_.size()) {
            append_extras(fields, extra_channels_[index]);
        }
        return object_json(fields);
    };

    std::vector<std::string> lines;
    for (std::size_t i = 0; i < lines_.size(); ++i) {
        lines.push_back(line_json(i));
    }
    std::vector<std::string> bpm_notes;
    for (std::size_t i = 0; i < bpm_notes_.size(); ++i) {
        bpm_notes.push_back(bpm_json(i));
    }
    std::vector<std::string> stop_notes;
    for (std::size_t i = 0; i < stop_notes_.size(); ++i) {
        stop_notes.push_back(stop_json(i));
    }
    std::vector<std::string> channels;
    for (std::size_t i = 0; i < sound_channels_.size(); ++i) {
        channels.push_back(channel_json(i));
    }

    std::string lines_json;
    write_pretty_array(lines_json, lines, 1);
    std::string bpm_json_text;
    write_pretty_array(bpm_json_text, bpm_notes, 1);
    std::string stop_json_text;
    write_pretty_array(stop_json_text, stop_notes, 1);
    std::string channels_json;
    write_pretty_array(channels_json, channels, 1);

    std::vector<std::pair<std::string, std::string>> root;
    append_field(root, "version", quote_string(version_));
    append_field(root, "info", std::move(info_json));
    append_field(root, "lines", std::move(lines_json));
    append_field(root, "bpmNotes", std::move(bpm_json_text));
    append_field(root, "stopNotes", std::move(stop_json_text));
    append_field(root, "soundChannels", std::move(channels_json));
    const bool write_bga = !bga_headers_.empty() || !bga_events_.empty() || !layer_events_.empty()
        || !poor_events_.empty() || !extra_bga_.empty();
    if (write_bga) {
        std::vector<std::pair<std::string, std::string>> bga_fields;
        if (!bga_headers_.empty()) {
            std::vector<std::string> headers;
            for (std::size_t i = 0; i < bga_headers_.size(); ++i) {
                headers.push_back(bga_header_json(i));
            }
            std::string headers_json;
            write_pretty_array(headers_json, headers, 2);
            append_field(bga_fields, "bga_header", std::move(headers_json));
        }
        auto write_events = [&](const char* key,
                                const std::vector<BmsonBgaEvent>& events,
                                const std::vector<ExtraJson>& extras) {
            if (events.empty()) {
                return;
            }
            std::vector<std::string> items;
            for (std::size_t i = 0; i < events.size(); ++i) {
                items.push_back(bga_event_json(events, extras, i));
            }
            std::string items_json;
            write_pretty_array(items_json, items, 2);
            append_field(bga_fields, key, std::move(items_json));
        };
        write_events("bga_events", bga_events_, extra_bga_events_);
        write_events("layer_events", layer_events_, extra_layer_events_);
        write_events("poor_events", poor_events_, extra_poor_events_);
        append_extras(bga_fields, extra_bga_);
        std::string bga_json;
        write_pretty_object(bga_json, bga_fields, 1);
        append_field(root, "bga", std::move(bga_json));
    }
    append_extras(root, extra_root_);

    std::string out;
    write_pretty_object(out, root, 0);
    out += '\n';
    return out;
}

}  // namespace ibms
