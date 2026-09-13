target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
)

if(TARGET IBMSNativeSessionTests)
    target_sources(IBMSNativeSessionTests PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
    )
endif()

if(BUILD_TESTING)
    add_executable(IBMSNativeClipboardTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyClipboardTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
    )
    target_link_libraries(IBMSNativeClipboardTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeClipboardTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeClipboardTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeClipboardTests COMMAND IBMSNativeClipboardTests)

    add_executable(IBMSNativeClipboardSessionTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyClipboardSessionTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/DocumentSession.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/ChartLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyChartPaint.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/ChartTheme.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/TimingPanel.swift"
    )
    target_link_libraries(IBMSNativeClipboardSessionTests PRIVATE
        IBMSNativeBridge
        "-framework Foundation"
        "-framework Cocoa"
    )
    target_compile_options(IBMSNativeClipboardSessionTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
        "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
        "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSNative-Bridging-Header.h>"
    )
    target_link_options(IBMSNativeClipboardSessionTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeClipboardSessionTests COMMAND IBMSNativeClipboardSessionTests)
endif()
