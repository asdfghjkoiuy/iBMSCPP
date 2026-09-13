# OpenBMS TExpansion extract / replace. This fragment owns the test so the
# batch does not edit tests/CMakeLists.txt.

add_executable(ibms_bms_expansion_tests bms_expansion_test.cpp)
target_link_libraries(ibms_bms_expansion_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_expansion_tests COMMAND ibms_bms_expansion_tests)
