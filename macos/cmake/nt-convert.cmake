target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
)

foreach(_nt_convert_target
    IBMSNativeSessionTests
)
    if(TARGET ${_nt_convert_target})
        target_sources(${_nt_convert_target} PRIVATE
            "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
        )
    endif()
endforeach()

if(BUILD_TESTING)
    add_executable(IBMSNativeNTConvertTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyNTConvertTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyNTConvert.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyClipboard.swift"
    )
    target_link_libraries(IBMSNativeNTConvertTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeNTConvertTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeNTConvertTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeNTConvertTests COMMAND IBMSNativeNTConvertTests)
endif()
