cmake_minimum_required(VERSION 3.26)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
        set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS version")
    endif()
    project(IBMSNativeShell LANGUAGES Swift OBJCXX)
else()
    get_property(IBMS_NATIVE_ENABLED_LANGUAGES GLOBAL PROPERTY ENABLED_LANGUAGES)
    list(FIND IBMS_NATIVE_ENABLED_LANGUAGES "Swift" IBMS_NATIVE_SWIFT_LANGUAGE_INDEX)
    if(IBMS_NATIVE_SWIFT_LANGUAGE_INDEX EQUAL -1)
        enable_language(Swift)
    endif()
    list(FIND IBMS_NATIVE_ENABLED_LANGUAGES "OBJCXX" IBMS_NATIVE_OBJCXX_LANGUAGE_INDEX)
    if(IBMS_NATIVE_OBJCXX_LANGUAGE_INDEX EQUAL -1)
        enable_language(OBJCXX)
    endif()
endif()

if(NOT APPLE)
    message(FATAL_ERROR "IBMSNative is a native macOS application and must be built on macOS.")
endif()

add_library(IBMSNativeBridge STATIC
    Sources/IBMSBridge/IBMSDocumentBridge.mm
)

target_link_libraries(IBMSNativeBridge PRIVATE
    ibms::core
    "-framework Foundation"
)

target_include_directories(IBMSNativeBridge PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge"
)

target_compile_options(IBMSNativeBridge PRIVATE
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

add_executable(IBMSNative MACOSX_BUNDLE
    Sources/IBMSNative/AppDelegate.swift
    Sources/IBMSNative/AboutWindowController.swift
    Sources/IBMSNative/ApplicationState.swift
    Sources/IBMSNative/ColorPickerWindowController.swift
    Sources/IBMSNative/ChartRenderer.swift
    Sources/IBMSNative/ChartLayout.swift
    Sources/IBMSNative/LegacyChartPaint.swift
    Sources/IBMSNative/LegacyChromeIcons.swift
    Sources/IBMSNative/ChartTheme.swift
    Sources/IBMSNative/DocumentSession.swift
    Sources/IBMSNative/EditorSettings.swift
    Sources/IBMSNative/EditorThemeController.swift
    Sources/IBMSNative/FindWindowController.swift
    Sources/IBMSNative/GeneralOptionsWindowController.swift
    Sources/IBMSNative/ImportSMWindowController.swift
    Sources/IBMSNative/LegacyColorMath.swift
    Sources/IBMSNative/LegacyIBMSC.swift
    Sources/IBMSNative/LegacyImportLayout.swift
    Sources/IBMSNative/LegacyLoadProgress.swift
    Sources/IBMSNative/LegacyTimeSelection.swift
    Sources/IBMSNative/LegacyTimeSelectionOps.swift
    Sources/IBMSNative/Legacy1296Write.swift
    Sources/IBMSNative/LegacyErrorCheck.swift
    Sources/IBMSNative/LegacyMyO2.swift
    Sources/IBMSNative/LegacySMImport.swift
    Sources/IBMSNative/LoadProgressWindowController.swift
    Sources/IBMSNative/LegacyDialogLayout.swift
    Sources/IBMSNative/LegacyChartQuery.swift
    Sources/IBMSNative/MainToolbar.swift
    Sources/IBMSNative/MainWindowChrome.swift
    Sources/IBMSNative/MainWindowContentView.swift
    Sources/IBMSNative/MainWindowController.swift
    Sources/IBMSNative/MyO2WindowController.swift
    Sources/IBMSNative/MenuBuilder.swift
    Sources/IBMSNative/OptionDialogControls.swift
    Sources/IBMSNative/OptionDialogLayout.swift
    Sources/IBMSNative/OptionsSidebar.swift
    Sources/IBMSNative/PlayerOptionsWindowController.swift
    Sources/IBMSNative/PreviewWindowController.swift
    Sources/IBMSNative/SplashWindowController.swift
    Sources/IBMSNative/StatisticsWindowController.swift
    Sources/IBMSNative/VisualOptionsWindowController.swift
    Sources/IBMSNative/StatusStrip.swift
    Sources/IBMSNative/TimeSelectionStrip.swift
    Sources/IBMSNative/TimingPanel.swift
)

file(GLOB IBMS_NATIVE_THEME_RESOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Themes/*.Theme.xml")
set_source_files_properties(${IBMS_NATIVE_THEME_RESOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/Themes")
target_sources(IBMSNative PRIVATE ${IBMS_NATIVE_THEME_RESOURCES})
add_custom_command(TARGET IBMSNative POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/Themes"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different ${IBMS_NATIVE_THEME_RESOURCES}
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/Themes"
    VERBATIM
)

set(IBMS_LEGACY_IBMSC "${CMAKE_CURRENT_SOURCE_DIR}/../iBMSC/iBMSC")
set(IBMS_CHROME_ICONS
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16New.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Open.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Save.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16SaveAs.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Cut.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Copy.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Paste.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Find.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Statistics.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16MyO2.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16CheckError.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16CheckErrorN.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtons/ImageError.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16PreviewOnClick.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16ShowFileNameN.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16NTInput.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Undo.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Redo.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16TimeSelection.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Select.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Pen.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16PlayB.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Play.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Stop.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16PlayerOptions.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16VisualOptions.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16GeneralOptions.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Language.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Theme.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Storm.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Up.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Down.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Import2.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Export.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtonsSmall/x16Refresh.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtons/ConvertNotes.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtons/Shortcut.png"
    "${IBMS_LEGACY_IBMSC}/ImageButtons/Statistics3.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/lgheight.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/lgwidth.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/lgpartition.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/x16Lock.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/x16PlayerBrowse.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/x16Remove.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/WAVLeft.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/WAVWidth.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/WAVPrecision.png"
    "${IBMS_LEGACY_IBMSC}/MiscButtons/WAVOffset.png"
    "${CMAKE_CURRENT_SOURCE_DIR}/Resources/LegacyChrome/x16WavIncrease.png"
    "${IBMS_LEGACY_IBMSC}/About.png"
    "${IBMS_LEGACY_IBMSC}/SplashScreenx.png"
    "${IBMS_LEGACY_IBMSC}/TransparentBG.png"
)
add_custom_command(TARGET IBMSNative POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/LegacyChrome"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different ${IBMS_CHROME_ICONS}
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/LegacyChrome"
    VERBATIM
)

set(IBMS_NATIVE_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}")
if(NOT IBMS_NATIVE_DEPLOYMENT_TARGET)
    set(IBMS_NATIVE_DEPLOYMENT_TARGET "14.0")
endif()

if(CMAKE_OSX_ARCHITECTURES)
    list(LENGTH CMAKE_OSX_ARCHITECTURES IBMS_NATIVE_ARCHITECTURE_COUNT)
    if(IBMS_NATIVE_ARCHITECTURE_COUNT GREATER 1)
        message(FATAL_ERROR
            "IBMSNative currently supports one CMAKE_OSX_ARCHITECTURES value per build. "
            "Universal application bundles are not implemented in this shell.")
    endif()
    list(GET CMAKE_OSX_ARCHITECTURES 0 IBMS_NATIVE_ARCHITECTURE)
else()
    set(IBMS_NATIVE_ARCHITECTURE "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()

set(IBMS_NATIVE_SWIFT_TARGET
    "${IBMS_NATIVE_ARCHITECTURE}-apple-macosx${IBMS_NATIVE_DEPLOYMENT_TARGET}")

set_target_properties(IBMSNative PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "IBMSNative"
    MACOSX_BUNDLE_GUI_IDENTIFIER "org.ibmsc.native"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
)

target_link_libraries(IBMSNative PRIVATE
    IBMSNativeBridge
    "-framework Cocoa"
    "-framework Metal"
    "-framework MetalKit"
)

target_compile_options(IBMSNative PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
    "$<$<COMPILE_LANGUAGE:Swift>:6>"
    "$<$<COMPILE_LANGUAGE:Swift>:-target>"
    "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
    "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSNative-Bridging-Header.h>"
)

target_link_options(IBMSNative PRIVATE
    "-target"
    "${IBMS_NATIVE_SWIFT_TARGET}"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeBridgeTests
        Tests/IBMSDocumentBridgeTests.mm
    )
    target_link_libraries(IBMSNativeBridgeTests PRIVATE
        IBMSNativeBridge
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeBridgeTests PRIVATE
        "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
    )
    add_test(NAME IBMSNativeBridgeTests COMMAND IBMSNativeBridgeTests)

    add_executable(IBMSNativeSessionTests
        Tests/DocumentSessionTests.swift
        Sources/IBMSNative/DocumentSession.swift
        Sources/IBMSNative/ChartLayout.swift
        Sources/IBMSNative/LegacyChartPaint.swift
        Sources/IBMSNative/ChartTheme.swift
        Sources/IBMSNative/TimingPanel.swift
    )
    target_link_libraries(IBMSNativeSessionTests PRIVATE
        IBMSNativeBridge
        "-framework Foundation"
        "-framework Cocoa"
    )
    target_compile_options(IBMSNativeSessionTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
        "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
        "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSNative-Bridging-Header.h>"
    )
    target_link_options(IBMSNativeSessionTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeSessionTests COMMAND IBMSNativeSessionTests)

    add_executable(IBMSNativeChartLayoutTests
        Tests/ChartLayoutTests.swift
        Sources/IBMSNative/ChartLayout.swift
        Sources/IBMSNative/LegacyPanelGuides.swift
        Sources/IBMSNative/LegacyChartPaint.swift
        Sources/IBMSNative/ChartTheme.swift
    )
    target_link_libraries(IBMSNativeChartLayoutTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeChartLayoutTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeChartLayoutTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeChartLayoutTests COMMAND IBMSNativeChartLayoutTests)

    add_executable(IBMSNativeChartThemeTests
        Tests/ChartThemeTests.swift
        Sources/IBMSNative/ChartTheme.swift
    )
    target_link_libraries(IBMSNativeChartThemeTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeChartThemeTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeChartThemeTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeChartThemeTests COMMAND IBMSNativeChartThemeTests)
    set_tests_properties(IBMSNativeChartThemeTests PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

    add_executable(IBMSNativeEditorThemeControllerTests
        Tests/EditorThemeControllerTests.swift
        Sources/IBMSNative/EditorThemeController.swift
        Sources/IBMSNative/ChartTheme.swift
        Sources/IBMSNative/NativeLocalization.swift
    )
    target_link_libraries(IBMSNativeEditorThemeControllerTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeEditorThemeControllerTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeEditorThemeControllerTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeEditorThemeControllerTests COMMAND IBMSNativeEditorThemeControllerTests)
    set_tests_properties(IBMSNativeEditorThemeControllerTests PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

    add_executable(IBMSNativeChromeTests
        Tests/MainWindowChromeTests.swift
        Sources/IBMSNative/MainWindowChrome.swift
    )
    target_compile_options(IBMSNativeChromeTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeChromeTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeChromeTests COMMAND IBMSNativeChromeTests)

    add_executable(IBMSNativeChartQueryTests
        Tests/LegacyChartQueryTests.swift
        Sources/IBMSNative/LegacyChartQuery.swift
        Sources/IBMSNative/MainWindowChrome.swift
        Sources/IBMSNative/ChartLayout.swift
        Sources/IBMSNative/LegacyChartPaint.swift
        Sources/IBMSNative/ChartTheme.swift
        Sources/IBMSNative/TimingPanel.swift
    )
    target_link_libraries(IBMSNativeChartQueryTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeChartQueryTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeChartQueryTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeChartQueryTests COMMAND IBMSNativeChartQueryTests)

    add_executable(IBMSNativeOptionDialogTests
        Tests/OptionDialogTests.swift
        Sources/IBMSNative/OptionDialogLayout.swift
        Sources/IBMSNative/EditorSettings.swift
        Sources/IBMSNative/ChartTheme.swift
    )
    target_link_libraries(IBMSNativeOptionDialogTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeOptionDialogTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeOptionDialogTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeOptionDialogTests COMMAND IBMSNativeOptionDialogTests)

    add_executable(IBMSNativeGeneralOptionsLocalizationTests
        Tests/GeneralOptionsLocalizationTests.swift
        Tests/FlippedDialogViewSupport.swift
        Sources/IBMSNative/GeneralOptionsWindowController.swift
        Sources/IBMSNative/OptionDialogControls.swift
        Sources/IBMSNative/OptionDialogLayout.swift
        Sources/IBMSNative/EditorSettings.swift
        Sources/IBMSNative/ChartTheme.swift
        Sources/IBMSNative/MainWindowChrome.swift
        Sources/IBMSNative/LegacyChromeIcons.swift
        Sources/IBMSNative/NativeLocalization.swift
    )
    target_link_libraries(IBMSNativeGeneralOptionsLocalizationTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeGeneralOptionsLocalizationTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeGeneralOptionsLocalizationTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeGeneralOptionsLocalizationTests COMMAND IBMSNativeGeneralOptionsLocalizationTests)

    add_executable(IBMSNativeSelectedObjectsViewTests
        Tests/SelectedObjectsViewTests.swift
        Tests/FlippedDialogViewSupport.swift
        Sources/IBMSNative/BmsONESelectedObjectsView.swift
        Sources/IBMSNative/BmsonSelectedObjects.swift
        Sources/IBMSNative/BmsONELayout.swift
        Sources/IBMSNative/NativeLocalization.swift
    )
    target_link_libraries(IBMSNativeSelectedObjectsViewTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeSelectedObjectsViewTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeSelectedObjectsViewTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeSelectedObjectsViewTests COMMAND IBMSNativeSelectedObjectsViewTests)

    add_executable(IBMSNativeDialogTests
        Tests/LegacyDialogTests.swift
        Sources/IBMSNative/LegacyColorMath.swift
        Sources/IBMSNative/LegacyDialogLayout.swift
        Sources/IBMSNative/ChartTheme.swift
    )
    target_link_libraries(IBMSNativeDialogTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeDialogTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeDialogTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeDialogTests COMMAND IBMSNativeDialogTests)

    add_executable(IBMSNativeImportTests
        Tests/LegacyImportTests.swift
        Sources/IBMSNative/LegacyImportLayout.swift
        Sources/IBMSNative/LegacySMImport.swift
        Sources/IBMSNative/LegacyIBMSC.swift
        Sources/IBMSNative/LegacyMyO2.swift
        Sources/IBMSNative/LegacyChartQuery.swift
        Sources/IBMSNative/MainWindowChrome.swift
        Sources/IBMSNative/ChartLayout.swift
        Sources/IBMSNative/ChartTheme.swift
        Sources/IBMSNative/LegacyChartPaint.swift
        Sources/IBMSNative/TimingPanel.swift
    )
    target_link_libraries(IBMSNativeImportTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeImportTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeImportTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeImportTests COMMAND IBMSNativeImportTests)

    add_executable(IBMSNativeLoadProgressTests
        Tests/LegacyLoadProgressTests.swift
        Sources/IBMSNative/LegacyLoadProgress.swift
    )
    target_link_libraries(IBMSNativeLoadProgressTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeLoadProgressTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeLoadProgressTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeLoadProgressTests COMMAND IBMSNativeLoadProgressTests)

    add_executable(IBMSNativeTimeSelectionTests
        Tests/LegacyTimeSelectionTests.swift
        Sources/IBMSNative/LegacyTimeSelection.swift
        Sources/IBMSNative/LegacyTimeSelectionOps.swift
        Sources/IBMSNative/Legacy1296Write.swift
        Sources/IBMSNative/LegacyErrorCheck.swift
        Sources/IBMSNative/LegacyChartPaint.swift
        Sources/IBMSNative/ChartTheme.swift
    )
    target_link_libraries(IBMSNativeTimeSelectionTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeTimeSelectionTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeTimeSelectionTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeTimeSelectionTests COMMAND IBMSNativeTimeSelectionTests)
endif()

# Per-feature build fragments. Each fragment owns its own sources and tests so
# that independent feature batches do not edit this file concurrently.
file(GLOB IBMS_NATIVE_FEATURE_FRAGMENTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/*.cmake")
list(SORT IBMS_NATIVE_FEATURE_FRAGMENTS)
foreach(_ibms_fragment IN LISTS IBMS_NATIVE_FEATURE_FRAGMENTS)
    include("${_ibms_fragment}")
endforeach()
