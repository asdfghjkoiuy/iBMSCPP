target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/NativeLocalization.swift"
)

# TimingPanel 现在使用本地化 API；这些测试目标会单独编译它。
foreach(_ibms_native_localization_target
    IBMSNativeSessionTests
    IBMSNativeChartQueryTests
    IBMSNativeImportTests
    IBMSNativeClipboardSessionTests
)
    if(TARGET ${_ibms_native_localization_target})
        target_sources(${_ibms_native_localization_target} PRIVATE
            "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/NativeLocalization.swift"
        )
    endif()
endforeach()

if(BUILD_TESTING)
    add_executable(IBMSNativeLocalizationTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/NativeLocalizationTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/NativeLocalization.swift"
    )
    target_link_libraries(IBMSNativeLocalizationTests PRIVATE "-framework Cocoa")
    target_compile_options(IBMSNativeLocalizationTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeLocalizationTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeLocalizationTests COMMAND IBMSNativeLocalizationTests)
endif()
