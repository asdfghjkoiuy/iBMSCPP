# ChartIO.SaveBMS rewrite. This fragment owns the source so the batch does not
# edit core/CMakeLists.txt.

target_sources(ibms_core PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../src/bms_save.cpp")
