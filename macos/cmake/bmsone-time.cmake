# BMSON time selection / MyO2 writeback.
# Filename sorts after bmsone-model.cmake so the document test target exists.
# Do not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonTimeSelection.swift"
)

if(TARGET IBMSNativeBmsONEDocumentTests)
    target_sources(IBMSNativeBmsONEDocumentTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonTimeSelection.swift"
    )
endif()
