target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyLocale.swift"
)

set(IBMS_LANG_XML
    "${CMAKE_CURRENT_LIST_DIR}/../../iBMSC/misc/Data/eng.Lang.xml"
    "${CMAKE_CURRENT_LIST_DIR}/../../iBMSC/misc/Data/chs.Lang.xml"
    "${CMAKE_CURRENT_LIST_DIR}/../../iBMSC/misc/Data/jpn.Lang.xml"
    "${CMAKE_CURRENT_LIST_DIR}/../../iBMSC/misc/Data/kor.Lang.xml"
)

if(TARGET IBMSNative)
    add_custom_command(TARGET IBMSNative POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/Data"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            ${IBMS_LANG_XML}
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/Data"
        VERBATIM
    )
endif()

if(BUILD_TESTING)
    add_executable(IBMSNativeLocaleTests
        "${CMAKE_CURRENT_LIST_DIR}/../Tests/LegacyLocaleTests.swift"
        "${CMAKE_CURRENT_LIST_DIR}/../Sources/IBMSNative/LegacyLocale.swift"
    )
    target_link_libraries(IBMSNativeLocaleTests PRIVATE
        "-framework Foundation"
    )
    target_compile_options(IBMSNativeLocaleTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(IBMSNativeLocaleTests PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME IBMSNativeLocaleTests COMMAND IBMSNativeLocaleTests)
endif()
