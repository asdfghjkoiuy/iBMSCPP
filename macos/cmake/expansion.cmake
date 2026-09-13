target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyExpansion.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeExpansionTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyExpansionTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyExpansion.swift"
    )
    target_link_libraries(IBMSNativeExpansionTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeExpansionTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeExpansionTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeExpansionTests COMMAND IBMSNativeExpansionTests)
endif()
