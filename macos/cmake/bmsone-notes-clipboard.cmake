# BMSON clipboard uses LegacyClipboard encode / decode.
# Filename sorts after bmsone-model.cmake so the document test target exists.
# Do not edit macos/CMakeLists.txt.

if(TARGET IBMSNativeBmsONEDocumentTests)
    target_sources(IBMSNativeBmsONEDocumentTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyClipboard.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyNTConvert.swift"
    )
endif()
