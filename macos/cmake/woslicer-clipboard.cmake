# woslicer BMSE clipboard. Shared Audio Slicer window; do not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerClipboard.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeWoslicerClipboardTests
        "${CMAKE_CURRENT_SOURCE_DIR}/Tests/WoslicerClipboardTests.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerClipboard.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerSplit.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyClipboard.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyNTConvert.swift"
    )
    target_link_libraries(IBMSNativeWoslicerClipboardTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeWoslicerClipboardTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeWoslicerClipboardTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeWoslicerClipboardTests COMMAND IBMSNativeWoslicerClipboardTests)
endif()
