target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyChromeMenu.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeChromeMenuTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyChromeMenuTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyChromeMenu.swift"
    )
    target_link_libraries(IBMSNativeChromeMenuTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeChromeMenuTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeChromeMenuTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeChromeMenuTests COMMAND IBMSNativeChromeMenuTests)
endif()
