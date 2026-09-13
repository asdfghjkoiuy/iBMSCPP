# BMSON in the main editor. Mapping + open/save/write hooks.
# Do not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonChartAdapter.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonChartMapping.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeBmsonChartTests
        "${CMAKE_CURRENT_SOURCE_DIR}/Tests/BmsonChartMappingTests.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonChartMapping.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsONELayout.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyLoadProgress.swift"
    )
    target_link_libraries(IBMSNativeBmsonChartTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmsonChartTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmsonChartTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeBmsonChartTests COMMAND IBMSNativeBmsonChartTests)
    set_tests_properties(IBMSNativeBmsonChartTests PROPERTIES
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    )
endif()
