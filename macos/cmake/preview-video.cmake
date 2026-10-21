# WMV/ASF preview clock. Static LGPL FFmpeg, not Homebrew dylibs.
# build-static.sh stamps script, config, arch, deployment target, and compiler.
# A missing avcodec/avformat/avutil/swscale archive rebuilds the prefix.
# Included by macos/CMakeLists.txt's sorted cmake/*.cmake glob, after preview-audio.

set(IBMS_PREVIEW_FFMPEG_PREFIX "${CMAKE_BINARY_DIR}/ffmpeg-lgpl-prefix")
set(IBMS_PREVIEW_FFMPEG_SCRIPT
    "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg-lgpl/build-static.sh")

if(CMAKE_OSX_ARCHITECTURES)
    set(IBMS_PREVIEW_FFMPEG_ARCH "${CMAKE_OSX_ARCHITECTURES}")
else()
    set(IBMS_PREVIEW_FFMPEG_ARCH "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(IBMS_PREVIEW_FFMPEG_MIN "14.0")
else()
    set(IBMS_PREVIEW_FFMPEG_MIN "${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()

set(IBMS_PREVIEW_FFMPEG_LIBS
    "${IBMS_PREVIEW_FFMPEG_PREFIX}/lib/libavcodec.a"
    "${IBMS_PREVIEW_FFMPEG_PREFIX}/lib/libavformat.a"
    "${IBMS_PREVIEW_FFMPEG_PREFIX}/lib/libswscale.a"
    "${IBMS_PREVIEW_FFMPEG_PREFIX}/lib/libavutil.a"
)
add_custom_command(
    OUTPUT
        ${IBMS_PREVIEW_FFMPEG_LIBS}
        "${IBMS_PREVIEW_FFMPEG_PREFIX}/include/libavcodec/avcodec.h"
    COMMAND /bin/bash "${IBMS_PREVIEW_FFMPEG_SCRIPT}"
            "${IBMS_PREVIEW_FFMPEG_PREFIX}"
            "${CMAKE_C_COMPILER}"
            "${IBMS_PREVIEW_FFMPEG_ARCH}"
            "${IBMS_PREVIEW_FFMPEG_MIN}"
    DEPENDS "${IBMS_PREVIEW_FFMPEG_SCRIPT}"
    COMMENT "Build LGPL static FFmpeg for WMV/ASF"
    VERBATIM
)
add_custom_target(ibms_preview_ffmpeg
    DEPENDS ${IBMS_PREVIEW_FFMPEG_LIBS}
)

add_library(IBMSPreviewVideo STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/PreviewVideo/IBMSPreviewVideo.cpp"
)
set_target_properties(IBMSPreviewVideo PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)
add_dependencies(IBMSPreviewVideo ibms_preview_ffmpeg)
target_include_directories(IBMSPreviewVideo PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge"
    "${IBMS_PREVIEW_FFMPEG_PREFIX}/include"
)
target_compile_options(IBMSPreviewVideo PRIVATE
    "-target" "${IBMS_NATIVE_SWIFT_TARGET}"
)
target_link_libraries(IBMSPreviewVideo PUBLIC
    ${IBMS_PREVIEW_FFMPEG_LIBS}
    "-lc++"
)

set(IBMS_PREVIEW_VIDEO_SWIFT
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewVideoClock.swift")

if(TARGET IBMSNative)
    target_sources(IBMSNative PRIVATE "${IBMS_PREVIEW_VIDEO_SWIFT}")
    target_link_libraries(IBMSNative PRIVATE IBMSPreviewVideo)
endif()

if(TARGET IBMSNativePreviewBGATests)
    target_sources(IBMSNativePreviewBGATests PRIVATE "${IBMS_PREVIEW_VIDEO_SWIFT}")
    target_link_libraries(IBMSNativePreviewBGATests PRIVATE IBMSPreviewVideo)
endif()

if(TARGET IBMSNativePreviewWindowTests)
    target_sources(IBMSNativePreviewWindowTests PRIVATE "${IBMS_PREVIEW_VIDEO_SWIFT}")
    target_link_libraries(IBMSNativePreviewWindowTests PRIVATE IBMSPreviewVideo)
endif()

if(BUILD_TESTING)
    ibms_preview_add_swift_test(IBMSNativePreviewVideoTests
        SOURCES
            "${CMAKE_CURRENT_SOURCE_DIR}/Tests/PreviewVideoTests.swift"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewVideoClock.swift"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewBGAView.swift"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyPreviewAudio.swift"
        FRAMEWORKS Cocoa AVFoundation CoreGraphics CoreMedia ImageIO QuartzCore
    )
    target_link_libraries(IBMSNativePreviewVideoTests PRIVATE IBMSPreviewVideo)
    ibms_preview_attach_mix_bridge(IBMSNativePreviewVideoTests)
endif()
