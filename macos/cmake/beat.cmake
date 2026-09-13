target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyBeat.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeBeatTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyBeatTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyBeat.swift"
    )
    target_link_libraries(IBMSNativeBeatTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeBeatTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBeatTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBeatTests COMMAND IBMSNativeBeatTests)
endif()
