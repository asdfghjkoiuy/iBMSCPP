if(BUILD_TESTING)
    add_executable(IBMSNativeChartRenderPerformanceBench
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/ChartRenderPerformanceBench.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/ChartLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyPanelGuides.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyChartPaint.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/ChartTheme.swift"
    )
    target_link_libraries(IBMSNativeChartRenderPerformanceBench PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeChartRenderPerformanceBench PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>" "$<$<COMPILE_LANGUAGE:Swift>:6>" "$<$<COMPILE_LANGUAGE:Swift>:-target>" "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>")
    target_link_options(IBMSNativeChartRenderPerformanceBench PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
endif()
