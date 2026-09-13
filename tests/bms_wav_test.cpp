#include <ibms/bms_document.hpp>

#include <iostream>
#include <stdexcept>
#include <string>

namespace {

int failures = 0;

void expect(bool condition, const char* message)
{
    if (!condition) {
        std::cerr << "Expectation failed: " << message << '\n';
        ++failures;
    }
}

template <class Exception, class Action>
void expect_throws(Action action, const char* message)
{
    try {
        action();
        std::cerr << "Expectation failed: " << message << " (no exception)\n";
        ++failures;
    } catch (const Exception&) {
    } catch (...) {
        std::cerr << "Expectation failed: " << message << " (wrong exception)\n";
        ++failures;
    }
}

void set_wav_writes_and_replaces_definition()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE Demo\n");
    document.set_header("WAV01", "kick.wav");
    const std::string first = document.serialize();
    expect(first.find("#WAV01 kick.wav") != std::string::npos, "Browse writes #WAV01 filename");
    expect(document.header("WAV01") == "kick.wav", "header(WAV01) reads the file name");

    document.set_header("WAV01", "snare.ogg");
    expect(document.serialize().find("#WAV01 snare.ogg") != std::string::npos, "Browse replaces the same token");
    expect(document.serialize().find("kick.wav") == std::string::npos, "the old file name is gone");
}

void empty_wav_removes_the_line()
{
    auto document = ibms::BmsDocument::from_bytes("#WAV01 kick.wav\n#WAV02 hat.wav\n");
    document.set_header("WAV01", "");
    const std::string text = document.serialize();
    expect(text.find("#WAV01") == std::string::npos, "Remove deletes the #WAV line");
    expect(text.find("#WAV02 hat.wav") != std::string::npos, "other definitions stay");
    expect(!document.header("WAV01").has_value() || document.header("WAV01")->empty(),
           "removed WAV01 is empty");
}

void wav00_and_line_breaks_are_rejected()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE Demo\n");
    expect_throws<std::invalid_argument>([&document] { document.set_header("WAV00", "kick.wav"); },
                                         "WAV00 is not a list slot");
    expect_throws<std::invalid_argument>([&document] { document.set_header("WAV01", "bad\nname"); },
                                         "CR/LF in a file name is rejected");
}

} // namespace

int main()
{
    try {
        set_wav_writes_and_replaces_definition();
        empty_wav_removes_the_line();
        wav00_and_line_breaks_are_rejected();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " WAV header expectation(s) failed\n";
        return 1;
    }
    return 0;
}
