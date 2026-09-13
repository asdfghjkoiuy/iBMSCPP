# 1296 BPM/STOP radix. This fragment owns the test so the batch does not
# edit tests/CMakeLists.txt.

add_executable(ibms_bms_1296_tests bms_1296_test.cpp)
target_link_libraries(ibms_bms_1296_tests PRIVATE ibms::core)
add_test(NAME ibms_bms_1296_tests COMMAND ibms_bms_1296_tests)
