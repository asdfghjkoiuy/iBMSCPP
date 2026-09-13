#include <ibms/audio_decode.hpp>

#include <cstdint>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

namespace {

int failures = 0;

void expect(bool condition, std::string_view expression)
{
    if (!condition) {
        std::cerr << "Expectation failed: " << expression << '\n';
        ++failures;
    }
}

std::filesystem::path fixture(std::string_view name)
{
    return std::filesystem::path{IBMS_AUDIO_FIXTURE_DIR} / name;
}

std::vector<std::uint8_t> pcm16_wav(std::int16_t sample)
{
    const std::uint32_t data_size = 2;
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
    append_u16(1);
    append_u32(44100);
    append_u32(88200);
    append_u16(2);
    append_u16(16);
    bytes.insert(bytes.end(), {'d', 'a', 't', 'a'});
    append_u32(data_size);
    append_u16(static_cast<std::uint16_t>(sample));
    return bytes;
}

void resolve_swaps_wav_and_ogg()
{
    const auto folder = std::filesystem::temp_directory_path() / "ibms-audio-check";
    std::filesystem::create_directories(folder);
    const auto wav = folder / "kick.wav";
    const auto ogg = folder / "kick.ogg";
    std::filesystem::remove(wav);
    std::filesystem::remove(ogg);
    {
        std::ofstream out(wav, std::ios::binary);
        out.put('W');
    }
    const auto from_ogg = ibms::resolve_audio_path((folder / "kick.ogg").string());
    expect(from_ogg == wav.string(), "missing ogg uses wav");
    std::filesystem::remove(wav);
    {
        std::ofstream out(ogg, std::ios::binary);
        out.put('O');
    }
    const auto from_wav = ibms::resolve_audio_path((folder / "kick.wav").string());
    expect(from_wav == ogg.string(), "missing wav uses ogg");
    const auto missing = ibms::resolve_audio_path((folder / "snare.ogg").string());
    expect(missing == (folder / "snare.ogg").string(), "neither file keeps the requested path");
    std::filesystem::remove_all(folder);
}

void decode_pcm16_wav_bytes()
{
    const auto bytes = pcm16_wav(10000);
    const auto decoded = ibms::decode_audio_bytes(bytes, ".wav");
    expect(decoded.has_value(), "pcm16 decodes");
    expect(decoded && decoded->sample_rate == 44100, "wav rate");
    expect(decoded && decoded->channels == 1, "wav mono");
    expect(decoded && decoded->samples.size() == 1 && decoded->samples[0] == 10000, "wav sample");
}

void decode_ogg_fixture()
{
    const auto decoded = ibms::decode_audio_file(fixture("sine-440.ogg").string());
    expect(decoded.has_value(), "ogg decodes");
    expect(decoded && decoded->sample_rate == 44100, "ogg rate");
    expect(decoded && decoded->channels == 2, "ogg stereo");
    expect(decoded && decoded->samples.size() >= 4000, "ogg has frames");
    std::int16_t peak = 0;
    if (decoded) {
        for (const auto sample : decoded->samples) {
            const auto abs = sample < 0 ? static_cast<std::int16_t>(-sample) : sample;
            if (abs > peak)
                peak = abs;
        }
    }
    expect(peak > 1000, "ogg sine has energy");
}

void decode_rejects_garbage()
{
    const std::vector<std::uint8_t> garbage{'n', 'o', 't', ' ', 'a', 'u', 'd', 'i', 'o'};
    expect(!ibms::decode_audio_bytes(garbage, ".ogg").has_value(), "garbage ogg");
    expect(!ibms::decode_audio_bytes(garbage, ".wav").has_value(), "garbage wav");
    expect(!ibms::decode_audio_bytes(garbage, ".mp3").has_value(), "garbage mp3");
}

void decode_mp3_fixture()
{
    const auto decoded = ibms::decode_audio_file(fixture("sine-440.mp3").string());
    expect(decoded.has_value(), "mp3 decodes");
    expect(decoded && decoded->sample_rate == 44100, "mp3 rate");
    expect(decoded && decoded->channels == 2, "mp3 stereo");
    expect(decoded && decoded->samples.size() >= 2000, "mp3 has frames");
    std::int16_t peak = 0;
    if (decoded) {
        for (const auto sample : decoded->samples) {
            const auto abs = sample < 0 ? static_cast<std::int16_t>(-sample) : sample;
            if (abs > peak)
                peak = abs;
        }
    }
    expect(peak > 1000, "mp3 sine has energy");
}

}  // namespace

int main()
{
    try {
        resolve_swaps_wav_and_ogg();
        decode_pcm16_wav_bytes();
        decode_ogg_fixture();
        decode_mp3_fixture();
        decode_rejects_garbage();
    } catch (const std::exception& exception) {
        std::cerr << "Unhandled exception: " << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " expectation(s) failed\n";
        return 1;
    }
    std::cout << "ibms_audio_decode_tests passed\n";
    return 0;
}
