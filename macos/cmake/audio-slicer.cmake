# Shared audio slicer. One window, bmhelper and woslicer cut-point backends.
# Do not edit macos/CMakeLists.txt.

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/AudioSlice.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/AudioSlicerLayout.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/AudioSlicerWindowController.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerSplit.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerTrim.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerWaveform.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeAudioSliceTests
        "${CMAKE_CURRENT_SOURCE_DIR}/Tests/AudioSliceTests.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/AudioSlice.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/AudioSlicerLayout.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmhelperLayout.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmhelperMidi.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmhelperWavSplit.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerLayout.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerSplit.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerTrim.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/WoslicerWaveform.swift"
    )
    target_link_libraries(IBMSNativeAudioSliceTests PRIVATE
        IBMSNativeAudioBridge
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeAudioSliceTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
        "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
        "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSAudio-Bridging-Header.h>"
    )
    target_link_options(IBMSNativeAudioSliceTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeAudioSliceTests COMMAND IBMSNativeAudioSliceTests)
    set_tests_properties(IBMSNativeAudioSliceTests PROPERTIES
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    )
endif()
