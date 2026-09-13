target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEExtraDialogs.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEImportWindowController.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONELayout.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEFooter.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEScratch.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONELaneOrder.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEPlainLanes.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEColorScheme.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEWheel.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEMasterExport.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEPreferences.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEWindowController.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONESelectedObjectsView.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEInfoDockView.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEExternalViewer.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEExternalViewerDialog.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeBmsONETests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmsONELayoutTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONELayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEFooter.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEScratch.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONELaneOrder.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEPlainLanes.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEColorScheme.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEWheel.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEPreferences.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsonSelectedObjects.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEExternalViewer.swift"
    )
    target_link_libraries(IBMSNativeBmsONETests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmsONETests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmsONETests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeBmsONETests COMMAND IBMSNativeBmsONETests)

    add_executable(IBMSNativeBmsONEExportTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmsONEExportWavTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONEMasterExport.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmsONELayout.swift"
    )
    target_link_libraries(IBMSNativeBmsONEExportTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmsONEExportTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmsONEExportTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeBmsONEExportTests COMMAND IBMSNativeBmsONEExportTests)
endif()
