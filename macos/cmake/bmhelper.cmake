target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperAudioSplitterWindowController.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDefinitions.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivision.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivisionWindowController.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidi.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidiWindowController.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperProject.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperWavSplit.swift"
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperWindowController.swift"
)

if(BUILD_TESTING)
    add_executable(IBMSNativeBmhelperWindowLayoutTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperWindowLayoutTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/FlippedDialogViewSupport.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/NativeLocalization.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperWindowController.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidi.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidiWindowController.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDefinitions.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivision.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivisionWindowController.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperProject.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperWavSplit.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/AudioSlicerWindowController.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/AudioSlicerLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/AudioSlice.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/WoslicerSplit.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/WoslicerTrim.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/WoslicerWaveform.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/WoslicerClipboard.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
    )
    target_link_libraries(IBMSNativeBmhelperWindowLayoutTests PRIVATE "-framework Cocoa" "-framework AVFoundation")
    target_compile_options(IBMSNativeBmhelperWindowLayoutTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>" "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>" "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperWindowLayoutTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperWindowLayoutTests COMMAND IBMSNativeBmhelperWindowLayoutTests)

    add_executable(IBMSNativeBmhelperTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperLayoutTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
    )
    target_link_libraries(IBMSNativeBmhelperTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmhelperTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperTests COMMAND IBMSNativeBmhelperTests)

    add_executable(IBMSNativeBmhelperMidiTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperMidiTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidi.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
    )
    target_link_libraries(IBMSNativeBmhelperMidiTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmhelperMidiTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperMidiTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperMidiTests COMMAND IBMSNativeBmhelperMidiTests)

    add_executable(IBMSNativeBmhelperDefinitionTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperDefinitionTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDefinitions.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
    )
    target_link_libraries(IBMSNativeBmhelperDefinitionTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmhelperDefinitionTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperDefinitionTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperDefinitionTests COMMAND IBMSNativeBmhelperDefinitionTests)

    add_executable(IBMSNativeBmhelperDivisionTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperDivisionTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivision.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDefinitions.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidi.swift"
    )
    target_link_libraries(IBMSNativeBmhelperDivisionTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmhelperDivisionTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperDivisionTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperDivisionTests COMMAND IBMSNativeBmhelperDivisionTests)

    add_executable(IBMSNativeBmhelperWavSplitTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperWavSplitTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperWavSplit.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivision.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDefinitions.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidi.swift"
    )
    target_link_libraries(IBMSNativeBmhelperWavSplitTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmhelperWavSplitTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperWavSplitTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperWavSplitTests COMMAND IBMSNativeBmhelperWavSplitTests)

    add_executable(IBMSNativeBmhelperProjectTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/BmhelperProjectTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperProject.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDivision.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperDefinitions.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperLayout.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/BmhelperMidi.swift"
    )
    target_link_libraries(IBMSNativeBmhelperProjectTests PRIVATE
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmhelperProjectTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeBmhelperProjectTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeBmhelperProjectTests COMMAND IBMSNativeBmhelperProjectTests)
endif()
