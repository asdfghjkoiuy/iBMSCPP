target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyGotoMeasure.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeGotoMeasureTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyGotoMeasureTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyGotoMeasure.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
    )
    target_link_libraries(IBMSNativeGotoMeasureTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeGotoMeasureTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeGotoMeasureTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeGotoMeasureTests COMMAND IBMSNativeGotoMeasureTests)
endif()
