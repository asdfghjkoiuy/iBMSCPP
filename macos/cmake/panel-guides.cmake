target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyPanelGuides.swift"
)

foreach(_panel_guides_target
    IBMSNativeChartLayoutTests
    IBMSNativeImportTests
    IBMSNativeSessionTests
    IBMSNativeChartQueryTests
    IBMSNativeClipboardSessionTests
)
    if(TARGET ${_panel_guides_target})
        target_sources(${_panel_guides_target} PRIVATE
            "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyPanelGuides.swift"
        )
    endif()
endforeach()

if(BUILD_TESTING)
    add_executable(IBMSNativePanelGuidesTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyPanelGuidesTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyPanelGuides.swift"
    )
    target_link_libraries(IBMSNativePanelGuidesTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativePanelGuidesTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativePanelGuidesTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativePanelGuidesTests COMMAND IBMSNativePanelGuidesTests)
endif()
