add_executable(ibms_audio_decode_tests audio_decode_test.cpp)
target_link_libraries(ibms_audio_decode_tests PRIVATE ibms::core)
target_compile_definitions(ibms_audio_decode_tests PRIVATE
    IBMS_AUDIO_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures/audio"
)
add_test(NAME ibms_audio_decode_tests COMMAND ibms_audio_decode_tests)
