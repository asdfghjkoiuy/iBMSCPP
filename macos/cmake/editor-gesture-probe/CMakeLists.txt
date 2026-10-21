cmake_minimum_required(VERSION 3.26)

if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version")
endif()

project(EditorGestureProbe LANGUAGES Swift)

if(NOT APPLE)
    message(FATAL_ERROR "EditorGestureProbe must be built on macOS.")
endif()

if(CMAKE_OSX_ARCHITECTURES)
    list(LENGTH CMAKE_OSX_ARCHITECTURES _editor_arch_count)
    if(NOT _editor_arch_count EQUAL 1)
        message(FATAL_ERROR "EditorGestureProbe supports one architecture.")
    endif()
    list(GET CMAKE_OSX_ARCHITECTURES 0 EDITOR_GESTURE_ARCH)
else()
    set(EDITOR_GESTURE_ARCH "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()

set(EDITOR_GESTURE_TARGET "${EDITOR_GESTURE_ARCH}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(EDITOR_MACOS "${CMAKE_CURRENT_SOURCE_DIR}/../..")

add_executable(EditorGestureProbe
    "${EDITOR_MACOS}/Tests/EditorGestureProbe.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/ChartRenderer.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/ChartLayout.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/ChartTheme.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyChartPaint.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyPanelGuides.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyLabelMatch.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyWavList.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyTimeSelection.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyTimeSelectionOps.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyClipboard.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyNTConvert.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyPanelScroll.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyWaveform.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyColorMath.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyErrorCheck.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyChromeIcons.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyLoadProgress.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyMyO2.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyChartQuery.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/LegacyGotoMeasure.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/EditorSettings.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/OptionDialogLayout.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/TimingPanel.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/NativeLocalization.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/BmsONELayout.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/BmsonChartMapping.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/BmsonChannel.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/BmsONEMasterExport.swift"
    "${EDITOR_MACOS}/Sources/IBMSNative/MainWindowChrome.swift"
)

target_link_libraries(EditorGestureProbe PRIVATE
    "-framework Cocoa"
    "-framework Metal"
    "-framework MetalKit"
    "-framework AVFoundation"
    "-framework CoreMedia"
    "-framework QuartzCore"
)

target_compile_options(EditorGestureProbe PRIVATE
    "-swift-version" "6"
    "-target" "${EDITOR_GESTURE_TARGET}"
)

target_link_options(EditorGestureProbe PRIVATE
    "-target" "${EDITOR_GESTURE_TARGET}"
)
