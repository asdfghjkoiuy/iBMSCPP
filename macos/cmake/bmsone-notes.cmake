# BMSON Beat sidebar. Filename sorts after bmsone-model.cmake.
# Do not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonBeat.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonBarLine.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonChannel.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonSelectedObjects.swift"
)

if(TARGET IBMSNativeBmsONEDocumentTests)
    target_sources(IBMSNativeBmsONEDocumentTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonBeat.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonBarLine.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonChannel.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonSelectedObjects.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsONEPreferences.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyBeat.swift"
    )
endif()
