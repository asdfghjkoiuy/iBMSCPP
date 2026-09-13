add_library(ibms_core STATIC
    src/bms_document.cpp
    src/bms_long_note.cpp
    src/bms_timing.cpp
)
add_library(ibms::core ALIAS ibms_core)

# Per-feature build fragments (extra sources via target_sources(ibms_core ...)).
file(GLOB IBMS_CORE_FEATURE_FRAGMENTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/*.cmake")
list(SORT IBMS_CORE_FEATURE_FRAGMENTS)
foreach(_ibms_fragment IN LISTS IBMS_CORE_FEATURE_FRAGMENTS)
    include("${_ibms_fragment}")
endforeach()

target_compile_features(ibms_core PUBLIC cxx_std_20)
target_include_directories(ibms_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)
