# BMSON Move to Key / BGM. Filename sorts after bmsone-model.cmake.
# Do not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonNoteTransfer.swift"
)

if(TARGET IBMSNativeBmsONEDocumentTests)
    target_sources(IBMSNativeBmsONEDocumentTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonNoteTransfer.swift"
    )
endif()
