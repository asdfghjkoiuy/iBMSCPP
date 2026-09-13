target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyLabelMatch.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeLabelMatchTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyLabelMatchTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyLabelMatch.swift"
    )
    target_link_libraries(IBMSNativeLabelMatchTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeLabelMatchTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeLabelMatchTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeLabelMatchTests COMMAND IBMSNativeLabelMatchTests)
endif()
