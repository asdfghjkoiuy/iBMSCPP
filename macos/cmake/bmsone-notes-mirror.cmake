# BMSON Conversions → Mirror uses ChartConvert.mirrorChannel.
# Filename sorts after bmsone-model.cmake so the document test target exists.
# Do not edit macos/CMakeLists.txt.

if(TARGET IBMSNativeBmsONEDocumentTests)
    target_sources(IBMSNativeBmsONEDocumentTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/ChartLayout.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyChartPaint.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/ChartTheme.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyPanelGuides.swift"
    )
    target_link_libraries(IBMSNativeBmsONEDocumentTests PRIVATE "-framework Cocoa")
endif()
