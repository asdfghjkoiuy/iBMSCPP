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

void set_bmp_writes_and_replaces_definition()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE Demo\n");
    document.set_header("BMP01", "bg.png");
    const std::string first = document.serialize();
    expect(first.find("#BMP01 bg.png") != std::string::npos, "Browse writes #BMP01 filename");
    expect(document.header("BMP01") == "bg.png", "header(BMP01) reads the file name");

    document.set_header("BMP01", "layer.jpg");
    expect(document.serialize().find("#BMP01 layer.jpg") != std::string::npos, "Browse replaces the same token");
    expect(document.serialize().find("bg.png") == std::string::npos, "the old file name is gone");
}

void empty_bmp_removes_the_line()
{
    auto document = ibms::BmsDocument::from_bytes("#BMP01 bg.png\n#BMP02 poor.bmp\n");
    document.set_header("BMP01", "");
    const std::string text = document.serialize();
    expect(text.find("#BMP01") == std::string::npos, "Remove deletes the #BMP line");
    expect(text.find("#BMP02 poor.bmp") != std::string::npos, "other definitions stay");
    expect(!document.header("BMP01").has_value() || document.header("BMP01")->empty(),
           "removed BMP01 is empty");
}

void bmp00_and_line_breaks_are_rejected()
{
    auto document = ibms::BmsDocument::from_bytes("#TITLE Demo\n");
    expect_throws<std::invalid_argument>([&document] { document.set_header("BMP00", "bg.png"); },
                                         "BMP00 is not a list slot");
    expect_throws<std::invalid_argument>([&document] { document.set_header("BMP01", "bad\nname"); },
                                         "CR/LF in a file name is rejected");
}

void wav_and_bmp_slots_do_not_overwrite_each_other()
{
    auto document = ibms::BmsDocument::from_bytes("#WAV01 kick.wav\n");
    document.set_header("BMP01", "bg.png");
    const std::string text = document.serialize();
    expect(text.find("#WAV01 kick.wav") != std::string::npos, "WAV01 stays");
    expect(text.find("#BMP01 bg.png") != std::string::npos, "BMP01 is added");
}

} // namespace

int main()
{
    try {
        set_bmp_writes_and_replaces_definition();
        empty_bmp_removes_the_line();
        bmp00_and_line_breaks_are_rejected();
        wav_and_bmp_slots_do_not_overwrite_each_other();
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return 1;
    }
    if (failures != 0) {
        std::cerr << failures << " BMP header expectation(s) failed\n";
        return 1;
    }
    return 0;
}
