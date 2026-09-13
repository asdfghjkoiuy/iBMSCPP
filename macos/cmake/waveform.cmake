target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyWaveform.swift"
)

if(TARGET IBMSNative)
    add_custom_command(TARGET IBMSNative POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${IBMS_LEGACY_IBMSC}/MiscButtons/WAVTransparency.png"
            "${IBMS_LEGACY_IBMSC}/MiscButtons/WAVSaturation.png"
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/LegacyChrome"
        VERBATIM
    )
endif()

if(BUILD_TESTING)
    add_executable(IBMSNativeWaveformTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyWaveformTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyWaveform.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyColorMath.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/ChartTheme.swift"
    )
    target_link_libraries(IBMSNativeWaveformTests PRIVATE
        "-framework Foundation"
        "-framework Cocoa"
    )
    target_compile_options(IBMSNativeWaveformTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeWaveformTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeWaveformTests COMMAND IBMSNativeWaveformTests)
endif()
