target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyRecent.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeRecentTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyRecentTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyRecent.swift"
    )
    target_link_libraries(IBMSNativeRecentTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeRecentTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeRecentTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeRecentTests COMMAND IBMSNativeRecentTests)
endif()
