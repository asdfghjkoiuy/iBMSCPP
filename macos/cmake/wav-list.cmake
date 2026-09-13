target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyWavList.swift"
)

if(TARGET IBMSNativeSessionTests)
    target_sources(IBMSNativeSessionTests PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyWavList.swift"
    )
endif()

if(TARGET IBMSNativeClipboardSessionTests)
    target_sources(IBMSNativeClipboardSessionTests PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyWavList.swift"
    )
endif()

if(BUILD_TESTING)
    add_executable(IBMSNativeWavListTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyWavListTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyWavList.swift"
    )
    target_link_libraries(IBMSNativeWavListTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeWavListTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeWavListTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeWavListTests COMMAND IBMSNativeWavListTests)
endif()
