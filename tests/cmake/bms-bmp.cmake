add_executable(ibms_bms_bmp_tests bms_bmp_test.cpp)
target_link_libraries(ibms_bms_bmp_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_bmp_tests COMMAND ibms_bms_bmp_tests)
