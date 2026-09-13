add_executable(ibms_core_tests beat_position_test.cpp)
target_link_libraries(ibms_core_tests PRIVATE ibms::core)
add_test(NAME ibms_core_tests COMMAND ibms_core_tests)

add_executable(ibms_bms_document_tests bms_document_test.cpp)
target_link_libraries(ibms_bms_document_tests PRIVATE ibms::core)
target_compile_definitions(ibms_bms_document_tests PRIVATE
    IBMS_BMS_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms"
)
add_test(NAME ibms_bms_document_tests COMMAND ibms_bms_document_tests)

add_executable(ibms_bms_chart_tests bms_chart_test.cpp)
target_link_libraries(ibms_bms_chart_tests PRIVATE ibms::core)
target_compile_definitions(ibms_bms_chart_tests PRIVATE
    IBMS_BMS_CHART_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms-chart"
)
add_test(NAME ibms_bms_chart_tests COMMAND ibms_bms_chart_tests)

add_executable(ibms_bms_chart_fixture_tests bms_chart_fixture_test.cpp)
target_link_libraries(ibms_bms_chart_fixture_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_chart_fixture_tests
    COMMAND ibms_bms_chart_fixture_tests "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms-chart"
)

add_executable(ibms_bms_timing_tests bms_timing_test.cpp)
target_link_libraries(ibms_bms_timing_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_timing_tests
    COMMAND ibms_bms_timing_tests "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms-timing"
)

add_executable(ibms_bms_timing_fixture_tests bms_timing_fixture_test.cpp)
target_link_libraries(ibms_bms_timing_fixture_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_timing_fixture_tests
    COMMAND ibms_bms_timing_fixture_tests "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms-timing"
)

add_executable(ibms_bms_long_note_tests bms_long_note_test.cpp)
target_link_libraries(ibms_bms_long_note_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_long_note_tests COMMAND ibms_bms_long_note_tests)

add_executable(ibms_bms_long_note_fixture_tests bms_long_note_fixture_test.cpp)
target_link_libraries(ibms_bms_long_note_fixture_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_long_note_fixture_tests
    COMMAND ibms_bms_long_note_fixture_tests "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bms-long-notes"
)

# Per-feature test fragments.
file(GLOB IBMS_TEST_FEATURE_FRAGMENTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/*.cmake")
list(SORT IBMS_TEST_FEATURE_FRAGMENTS)
foreach(_ibms_fragment IN LISTS IBMS_TEST_FEATURE_FRAGMENTS)
    include("${_ibms_fragment}")
endforeach()
