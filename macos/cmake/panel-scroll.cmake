target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyPanelScroll.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/ChartEditorPane.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativePanelScrollTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyPanelScrollTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyPanelScroll.swift"
    )
    target_link_libraries(IBMSNativePanelScrollTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativePanelScrollTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativePanelScrollTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativePanelScrollTests COMMAND IBMSNativePanelScrollTests)
endif()
