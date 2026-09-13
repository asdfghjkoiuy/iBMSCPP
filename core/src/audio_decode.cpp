#include <ibms/audio_decode.hpp>

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
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
            if (!pcm || bits != 16 || channels <= 0 || sample_rate <= 0) {
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
    if (ext == ".wav" || (ext.empty() && starts_with(bytes, 0, "RIFF"))) {
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
    std::vector<std::uint8_t> bytes(
        (std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    return decode_audio_bytes(bytes, extension_of(resolved));
}

std::vector<std::uint8_t> encode_pcm16_wav(const DecodedAudio& audio)
{
    const int channels = audio.channels > 0 ? audio.channels : 1;
    const int rate = audio.sample_rate > 0 ? audio.sample_rate : 44100;
    const auto data_size = static_cast<std::uint32_t>(audio.samples.size() * 2);
    const std::uint32_t riff_size = 36 + data_size;
    std::vector<std::uint8_t> bytes;
    auto append_u16 = [&](std::uint16_t value) {
        bytes.push_back(static_cast<std::uint8_t>(value));
        bytes.push_back(static_cast<std::uint8_t>(value >> 8));
    };
    auto append_u32 = [&](std::uint32_t value) {
        bytes.push_back(static_cast<std::uint8_t>(value));
        bytes.push_back(static_cast<std::uint8_t>(value >> 8));
        bytes.push_back(static_cast<std::uint8_t>(value >> 16));
        bytes.push_back(static_cast<std::uint8_t>(value >> 24));
    };
    bytes.insert(bytes.end(), {'R', 'I', 'F', 'F'});
    append_u32(riff_size);
    bytes.insert(bytes.end(), {'W', 'A', 'V', 'E', 'f', 'm', 't', ' '});
    append_u32(16);
    append_u16(1);
    append_u16(static_cast<std::uint16_t>(channels));
    append_u32(static_cast<std::uint32_t>(rate));
    append_u32(static_cast<std::uint32_t>(rate * channels * 2));
    append_u16(static_cast<std::uint16_t>(channels * 2));
    append_u16(16);
    bytes.insert(bytes.end(), {'d', 'a', 't', 'a'});
    append_u32(data_size);
    for (const auto sample : audio.samples) {
        append_u16(static_cast<std::uint16_t>(sample));
    }
    return bytes;
}

}  // namespace ibms
