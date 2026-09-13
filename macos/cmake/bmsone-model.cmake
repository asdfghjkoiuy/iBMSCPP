# BmsONE document model. Links `ibms::core` through a dedicated ObjC++ bridge
# so this batch does not edit macos/CMakeLists.txt or IBMSDocumentBridge.mm.

add_library(IBMSNativeBmsonBridge STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSBmsonBridge.mm"
)
target_link_libraries(IBMSNativeBmsonBridge PRIVATE
    ibms::core
    "-framework Foundation"
)
target_include_directories(IBMSNativeBmsonBridge PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge"
)
target_compile_options(IBMSNativeBmsonBridge PRIVATE
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsONEDocument.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonHeaderMapping.swift"
)
target_link_libraries(IBMSNative PRIVATE IBMSNativeBmsonBridge)

if(BUILD_TESTING)
    add_executable(IBMSNativeBmsONEDocumentTests
        "${CMAKE_CURRENT_SOURCE_DIR}/Tests/BmsONEDocumentTests.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsONEDocument.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsONELayout.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonChartMapping.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/BmsonHeaderMapping.swift"
    )
    target_link_libraries(IBMSNativeBmsONEDocumentTests PRIVATE
        IBMSNativeBmsonBridge
        "-framework Foundation"
        "-framework CoreGraphics"
    )
    target_compile_options(IBMSNativeBmsONEDocumentTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
        "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
        "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSBmson-Bridging-Header.h>"
    )
    target_link_options(IBMSNativeBmsONEDocumentTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativeBmsONEDocumentTests COMMAND IBMSNativeBmsONEDocumentTests)
    set_tests_properties(IBMSNativeBmsONEDocumentTests PROPERTIES
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    )
endif()
