add_executable(ibms_bmson_tests bmson_test.cpp)
target_link_libraries(ibms_bmson_tests PRIVATE ibms::core)
target_compile_definitions(ibms_bmson_tests PRIVATE
    IBMS_BMSON_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bmson"
)
add_test(NAME ibms_bmson_tests COMMAND ibms_bmson_tests)
