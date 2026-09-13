#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace ibms {

/// Interleaved PCM16. Used by preview and BmsONE mix. This is not a BMS chart.
struct DecodedAudio {
    int sample_rate = 0;
    int channels = 0;
    std::vector<std::int16_t> samples;
};

/// iBMSC `Audio.vb` `CheckFilename` and BmsONE `OpenSourceFile`:
/// if the requested `.wav` / `.ogg` is missing, try the other extension.
/// The returned path may still be missing.
std::string resolve_audio_path(std::string_view requested);

/// Decode PCM16 WAV, Ogg Vorbis, or MP3. `hint_ext` is `.wav` / `.ogg` / `.mp3`
/// or empty to sniff.
std::optional<DecodedAudio> decode_audio_bytes(
    const std::vector<std::uint8_t>& bytes, std::string_view hint_ext);

/// Resolve the path, then decode the file that exists.
std::optional<DecodedAudio> decode_audio_file(std::string_view path);

/// Wrap decoded PCM as a 16-bit WAV so `AVAudioPlayer` can play it.
std::vector<std::uint8_t> encode_pcm16_wav(const DecodedAudio& audio);

}  // namespace ibms
