add_executable(ibms_bms_wav_tests bms_wav_test.cpp)
target_link_libraries(ibms_bms_wav_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_wav_tests COMMAND ibms_bms_wav_tests)
