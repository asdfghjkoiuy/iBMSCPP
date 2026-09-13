add_executable(ibms_bmson_from_bms_tests bmson_from_bms_test.cpp)
target_link_libraries(ibms_bmson_from_bms_tests PRIVATE ibms::core)
target_compile_definitions(ibms_bmson_from_bms_tests PRIVATE
    IBMS_BMS_IMPORT_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms-import"
)
add_test(NAME ibms_bmson_from_bms_tests COMMAND ibms_bmson_from_bms_tests)
