# ApplyBeat four modes. This fragment owns the test so the batch does not
# edit tests/CMakeLists.txt.

add_executable(ibms_bms_beat_tests bms_beat_test.cpp)
target_link_libraries(ibms_bms_beat_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_beat_tests COMMAND ibms_bms_beat_tests)
