if(TARGET IBMSNative)
    add_custom_command(TARGET IBMSNative POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${CMAKE_CURRENT_LIST_DIR}/../../iBMSC/iBMSC/ImageButtonsSmall/x16ShowFileName.png"
            "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/LegacyChrome/x16ShowFileName.png"
        VERBATIM
    )
endif()
