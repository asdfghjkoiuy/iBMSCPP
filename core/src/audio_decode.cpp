#include <ibms/audio_decode.hpp>

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"

extern "C" int stb_vorbis_decode_memory(
    const unsigned char* mem, int len, int* channels, int* sample_rate, short** output);

namespace ibms {
namespace {

std::string lower_ascii(std::string text)
{
    for (char& character : text) {
        character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    }
    return text;
}

std::string extension_of(std::string_view path)
{
    const auto file = std::filesystem::path{std::string(path)};
    return lower_ascii(file.extension().string());
}

std::uint16_t read_u16(const std::vector<std::uint8_t>& bytes, std::size_t offset)
{
    return static_cast<std::uint16_t>(bytes[offset] | (bytes[offset + 1] << 8));
}

std::uint32_t read_u32(const std::vector<std::uint8_t>& bytes, std::size_t offset)
{
    return static_cast<std::uint32_t>(
        bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24));
}

bool starts_with(const std::vector<std::uint8_t>& bytes, std::size_t offset, std::string_view text)
{
    if (offset + text.size() > bytes.size()) {
        return false;
    }
    return std::equal(text.begin(), text.end(), bytes.begin() + static_cast<std::ptrdiff_t>(offset));
}

std::optional<DecodedAudio> decode_wav(const std::vector<std::uint8_t>& bytes)
{
    if (bytes.size() < 44 || !starts_with(bytes, 0, "RIFF") || !starts_with(bytes, 8, "WAVE")) {
        return std::nullopt;
    }
    std::size_t offset = 12;
    int sample_rate = 0;
    int channels = 0;
    int bits = 0;
    bool pcm = false;
    while (offset + 8 <= bytes.size()) {
        const std::string id(reinterpret_cast<const char*>(bytes.data() + offset), 4);
        const auto size = static_cast<std::size_t>(read_u32(bytes, offset + 4));
        const std::size_t body = offset + 8;
        if (id == "fmt " && size >= 16 && body + 16 <= bytes.size()) {
            pcm = read_u16(bytes, body) == 1;
            channels = static_cast<int>(read_u16(bytes, body + 2));
            sample_rate = static_cast<int>(read_u32(bytes, body + 4));
            bits = static_cast<int>(read_u16(bytes, body + 14));
        } else if (id == "data") {
            if (!pcm || bits != 16 || channels <= 0 || channels > 32 || sample_rate <= 0) {
                return std::nullopt;
            }
            const std::size_t byte_count = std::min(size, bytes.size() - body);
            const std::size_t even = byte_count - (byte_count % 2);
            DecodedAudio audio;
            audio.sample_rate = sample_rate;
            audio.channels = channels;
            audio.samples.resize(even / 2);
            for (std::size_t index = 0; index < audio.samples.size(); ++index) {
                audio.samples[index] = static_cast<std::int16_t>(read_u16(bytes, body + index * 2));
            }
            return audio;
        }
        offset = body + size + (size % 2);
    }
    return std::nullopt;
}

std::optional<DecodedAudio> decode_ogg(const std::vector<std::uint8_t>& bytes)
{
    if (bytes.empty()) {
        return std::nullopt;
    }
    int channels = 0;
    int sample_rate = 0;
    short* pcm = nullptr;
    const int frames = stb_vorbis_decode_memory(
        bytes.data(), static_cast<int>(bytes.size()), &channels, &sample_rate, &pcm);
    if (frames <= 0 || pcm == nullptr || channels <= 0 || sample_rate <= 0) {
        if (pcm != nullptr) {
            std::free(pcm);
        }
        return std::nullopt;
    }
    DecodedAudio audio;
    audio.sample_rate = sample_rate;
    audio.channels = channels;
    audio.samples.assign(pcm, pcm + static_cast<std::size_t>(frames) * static_cast<std::size_t>(channels));
    std::free(pcm);
    return audio;
}

bool looks_like_ogg(const std::vector<std::uint8_t>& bytes)
{
    return starts_with(bytes, 0, "OggS");
}

bool looks_like_mp3(const std::vector<std::uint8_t>& bytes)
{
    if (starts_with(bytes, 0, "ID3")) {
        return true;
    }
    return bytes.size() >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
}

std::optional<DecodedAudio> decode_mp3(const std::vector<std::uint8_t>& bytes)
{
    if (bytes.empty()) {
        return std::nullopt;
    }
    mp3dec_t decoder;
    mp3dec_init(&decoder);
    DecodedAudio audio;
    const std::uint8_t* cursor = bytes.data();
    int remaining = static_cast<int>(bytes.size());
    while (remaining > 0) {
        mp3dec_frame_info_t info{};
        short pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];
        const int frames = mp3dec_decode_frame(&decoder, cursor, remaining, pcm, &info);
        if (info.frame_bytes <= 0) {
            break;
        }
        cursor += info.frame_bytes;
        remaining -= info.frame_bytes;
        if (frames <= 0 || info.channels <= 0 || info.hz <= 0) {
            continue;
        }
        if (audio.sample_rate == 0) {
            audio.sample_rate = info.hz;
            audio.channels = info.channels;
        }
        audio.samples.insert(
            audio.samples.end(), pcm, pcm + static_cast<std::size_t>(frames) * static_cast<std::size_t>(info.channels));
    }
    if (audio.samples.empty() || audio.sample_rate <= 0 || audio.channels <= 0) {
        return std::nullopt;
    }
    return audio;
}

}  // namespace

std::string resolve_audio_path(std::string_view requested)
{
    const std::filesystem::path path{std::string(requested)};
    if (std::filesystem::exists(path)) {
        return path.string();
    }
    const auto ext = lower_ascii(path.extension().string());
    std::filesystem::path other = path;
    if (ext == ".ogg") {
        other.replace_extension(".wav");
    } else if (ext == ".wav") {
        other.replace_extension(".ogg");
    } else {
        return path.string();
    }
    if (std::filesystem::exists(other)) {
        return other.string();
    }
    return path.string();
}

std::optional<DecodedAudio> decode_audio_bytes(
    const std::vector<std::uint8_t>& bytes, std::string_view hint_ext)
{
    const auto ext = lower_ascii(std::string(hint_ext));
    if (ext == ".wav") {
        if (auto wav = decode_wav(bytes); wav.has_value()) {
            return wav;
        }
        if (looks_like_ogg(bytes)) {
            return decode_ogg(bytes);
        }
        if (looks_like_mp3(bytes)) {
            return decode_mp3(bytes);
        }
        return std::nullopt;
    }
    if (ext.empty() && starts_with(bytes, 0, "RIFF")) {
        return decode_wav(bytes);
    }
    if (ext == ".ogg" || looks_like_ogg(bytes)) {
        return decode_ogg(bytes);
    }
    if (ext == ".mp3" || looks_like_mp3(bytes)) {
        return decode_mp3(bytes);
    }
    if (auto wav = decode_wav(bytes); wav.has_value()) {
        return wav;
    }
    if (auto ogg = decode_ogg(bytes); ogg.has_value()) {
        return ogg;
    }
    return decode_mp3(bytes);
}

std::optional<DecodedAudio> decode_audio_file(std::string_view path)
{
    const auto resolved = resolve_audio_path(path);
    std::ifstream input(resolved, std::ios::binary);
    if (!input) {
        return std::nullopt;
    }
    input.seekg(0, std::ios::end);
    const std::streamoff end = input.tellg();
    if (!input || end < 0) {
        return std::nullopt;
    }
    input.clear();
    input.seekg(0, std::ios::beg);
    std::vector<std::uint8_t> bytes;
    const auto size = static_cast<std::size_t>(end);
    bytes.reserve(size);
    bytes.resize(size);
    if (!bytes.empty()) {
        input.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        const auto read = input.gcount();
        if (read < 0) {
            return std::nullopt;
        }
        if (static_cast<std::size_t>(read) < bytes.size()) {
            bytes.resize(static_cast<std::size_t>(read));
        }
    }
    return decode_audio_bytes(bytes, extension_of(resolved));
}

std::vector<std::uint8_t> encode_pcm16_wav(const DecodedAudio& audio)
{
    const int channels = audio.channels > 0 && audio.channels <= 32 ? audio.channels : 1;
    const int rate = audio.sample_rate > 0 ? audio.sample_rate : 44100;
    const std::uint64_t channel_count = static_cast<std::uint64_t>(channels);
    const std::uint64_t byte_rate_wide =
        static_cast<std::uint64_t>(static_cast<std::uint32_t>(rate)) * channel_count * 2u;
    const std::uint64_t pcm_bytes = static_cast<std::uint64_t>(audio.samples.size()) * 2u;
    const auto saturate_u32 = [](std::uint64_t value) {
        return value > std::numeric_limits<std::uint32_t>::max()
            ? std::numeric_limits<std::uint32_t>::max()
            : static_cast<std::uint32_t>(value);
    };
    const std::uint32_t data_size = saturate_u32(pcm_bytes);
    const std::uint32_t riff_size = saturate_u32(36ull + static_cast<std::uint64_t>(data_size));
    std::uint8_t header[44];
    auto write_u16 = [&](std::size_t offset, std::uint16_t value) {
        header[offset] = static_cast<std::uint8_t>(value);
        header[offset + 1] = static_cast<std::uint8_t>(value >> 8);
    };
    auto write_u32 = [&](std::size_t offset, std::uint32_t value) {
        header[offset] = static_cast<std::uint8_t>(value);
        header[offset + 1] = static_cast<std::uint8_t>(value >> 8);
        header[offset + 2] = static_cast<std::uint8_t>(value >> 16);
        header[offset + 3] = static_cast<std::uint8_t>(value >> 24);
    };
    header[0] = 'R';
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';
    write_u32(4, riff_size);
    header[8] = 'W';
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';
    header[12] = 'f';
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';
    write_u32(16, 16);
    write_u16(20, 1);
    write_u16(22, static_cast<std::uint16_t>(channels));
    write_u32(24, static_cast<std::uint32_t>(rate));
    write_u32(28, saturate_u32(byte_rate_wide));
    write_u16(32, static_cast<std::uint16_t>(channel_count * 2u));
    write_u16(34, 16);
    header[36] = 'd';
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';
    write_u32(40, data_size);

    std::vector<std::uint8_t> bytes;
    const std::uint64_t reserved = 44ull + pcm_bytes;
    if (reserved <= static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())) {
        bytes.reserve(static_cast<std::size_t>(reserved));
    }
    bytes.insert(bytes.end(), header, header + 44);
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    if (!audio.samples.empty()) {
        const auto* raw = reinterpret_cast<const std::uint8_t*>(audio.samples.data());
        const auto pcm_span = static_cast<std::size_t>(pcm_bytes);
        bytes.insert(bytes.end(), raw, raw + pcm_span);
    }
#else
    for (const auto sample : audio.samples) {
        const auto value = static_cast<std::uint16_t>(sample);
        bytes.push_back(static_cast<std::uint8_t>(value));
        bytes.push_back(static_cast<std::uint8_t>(value >> 8));
    }
#endif
    return bytes;
}

}  // namespace ibms
