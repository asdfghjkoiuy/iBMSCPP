# Native woslicer II / III shell. This fragment owns sources and tests so the
# batch does not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerLayout.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerWindowController.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeWoslicerLayoutTests
        Tests/WoslicerLayoutTests.swift
        Sources/IBMSNative/WoslicerLayout.swift
    )
    target_link_libraries(IBMSNativeWoslicerLayoutTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeWoslicerLayoutTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeWoslicerLayoutTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeWoslicerLayoutTests COMMAND IBMSNativeWoslicerLayoutTests)
endif()
