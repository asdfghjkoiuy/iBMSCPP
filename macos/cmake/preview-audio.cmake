# Built-in preview audio. This fragment owns sources and tests so the
# batch does not edit macos/CMakeLists.txt.

add_library(IBMSNativeAudioBridge STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSAudioBridge.mm"
)
target_link_libraries(IBMSNativeAudioBridge PRIVATE
    ibms::core
    "-framework Foundation"
)
target_include_directories(IBMSNativeAudioBridge PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge"
)
target_compile_options(IBMSNativeAudioBridge PRIVATE
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyPreviewAudio.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyBmsonPreview.swift"
)

target_link_libraries(IBMSNative PRIVATE
    IBMSNativeAudioBridge
    "-framework AVFoundation"
)

if(BUILD_TESTING)
    add_executable(IBMSNativePreviewAudioTests
        Tests/LegacyPreviewAudioTests.swift
        Sources/IBMSNative/LegacyPreviewAudio.swift
    )
    target_link_libraries(IBMSNativePreviewAudioTests PRIVATE
        "-framework Foundation"
        "-framework AVFoundation"
    )
    target_compile_options(IBMSNativePreviewAudioTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativePreviewAudioTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativePreviewAudioTests COMMAND IBMSNativePreviewAudioTests)

    add_executable(IBMSNativeBmsonPreviewTests
        Tests/LegacyBmsonPreviewTests.swift
        Sources/IBMSNative/LegacyBmsonPreview.swift
        Sources/IBMSNative/LegacyPreviewAudio.swift
        Sources/IBMSNative/BmsonChartMapping.swift
        Sources/IBMSNative/BmsONELayout.swift
    )
    target_link_libraries(IBMSNativeBmsonPreviewTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
        "-framework AVFoundation"
    )
    target_compile_options(IBMSNativeBmsonPreviewTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmsonPreviewTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmsonPreviewTests COMMAND IBMSNativeBmsonPreviewTests)
endif()
