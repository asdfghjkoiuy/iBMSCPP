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

# libsamplerate 0.2.2 is C. The root project() enables CXX only. core may
# already have enabled C for its own directory; that does not install C
# compile rules into this macos directory. Enable C here, not in the root
# project() line. soxr is not a dependency.
enable_language(C)

set(IBMS_LIBSAMPLERATE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libsamplerate")
set(IBMS_LIBSAMPLERATE_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/ibms-libsamplerate")

include(CheckCSourceCompiles)
include(CheckCSourceRuns)
include(CheckIncludeFile)

set(_ibms_src_saved_required_flags "${CMAKE_REQUIRED_FLAGS}")
set(CMAKE_REQUIRED_FLAGS "-target ${IBMS_NATIVE_SWIFT_TARGET}")
check_include_file(stdbool.h IBMS_SRC_HAVE_STDBOOL_H)
check_c_source_runs("
#include <math.h>
int main(void)
{
    double fval;
    int k, ival;
    fval = 1.0 * 0x7FFFFFFF;
    for (k = 0; k < 100; k++) {
        ival = (lrint(fval)) >> 24;
        if (ival != 127)
            return 1;
        fval *= 1.2499999;
    }
    return 0;
}
" IBMS_SRC_CPU_CLIPS_POSITIVE)
check_c_source_runs("
#include <math.h>
int main(void)
{
    double fval;
    int k, ival;
    fval = -8.0 * 0x10000000;
    for (k = 0; k < 100; k++) {
        ival = (lrint(fval)) >> 24;
        if (ival != -128)
            return 1;
        fval *= 1.2499999;
    }
    return 0;
}
" IBMS_SRC_CPU_CLIPS_NEGATIVE)
set(CMAKE_REQUIRED_FLAGS "-target ${IBMS_NATIVE_SWIFT_TARGET} -fvisibility=hidden -Werror")
check_c_source_compiles("
__attribute__((visibility(\"default\"))) int foo(void);
__attribute__((visibility(\"hidden\"))) int bar(void);
int foo(void) { return 0; }
int bar(void) { return 1; }
int main(void) { return 0; }
" IBMS_SRC_HAVE_VISIBILITY)
set(CMAKE_REQUIRED_FLAGS "${_ibms_src_saved_required_flags}")

if(IBMS_SRC_CPU_CLIPS_POSITIVE)
    set(IBMS_SRC_CPU_CLIPS_POSITIVE 1)
else()
    set(IBMS_SRC_CPU_CLIPS_POSITIVE 0)
endif()
if(IBMS_SRC_CPU_CLIPS_NEGATIVE)
    set(IBMS_SRC_CPU_CLIPS_NEGATIVE 1)
else()
    set(IBMS_SRC_CPU_CLIPS_NEGATIVE 0)
endif()
if(IBMS_SRC_HAVE_STDBOOL_H)
    set(HAVE_STDBOOL_H 1)
else()
    unset(HAVE_STDBOOL_H)
endif()
if(IBMS_SRC_HAVE_VISIBILITY)
    set(HAVE_VISIBILITY 1)
else()
    unset(HAVE_VISIBILITY)
endif()
message(STATUS
    "libsamplerate 0.2.2 clips positive=${IBMS_SRC_CPU_CLIPS_POSITIVE} negative=${IBMS_SRC_CPU_CLIPS_NEGATIVE}")
file(MAKE_DIRECTORY "${IBMS_LIBSAMPLERATE_CONFIG_DIR}")
configure_file(
    "${IBMS_LIBSAMPLERATE_ROOT}/config.h.in"
    "${IBMS_LIBSAMPLERATE_CONFIG_DIR}/config.h"
    @ONLY
)
unset(HAVE_STDBOOL_H)
unset(HAVE_VISIBILITY)

add_library(ibms_libsamplerate STATIC
    "${IBMS_LIBSAMPLERATE_ROOT}/src/samplerate.c"
    "${IBMS_LIBSAMPLERATE_ROOT}/src/src_linear.c"
    "${IBMS_LIBSAMPLERATE_ROOT}/src/src_sinc.c"
    "${IBMS_LIBSAMPLERATE_ROOT}/src/src_zoh.c"
)
set_target_properties(ibms_libsamplerate PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)
target_compile_definitions(ibms_libsamplerate PRIVATE HAVE_CONFIG_H)
target_include_directories(ibms_libsamplerate
    PUBLIC "${IBMS_LIBSAMPLERATE_ROOT}/include"
    PRIVATE "${IBMS_LIBSAMPLERATE_ROOT}/src" "${IBMS_LIBSAMPLERATE_CONFIG_DIR}"
)
target_compile_options(ibms_libsamplerate PRIVATE
    "-target" "${IBMS_NATIVE_SWIFT_TARGET}"
)

add_library(IBMSPreviewMixBridge STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/PreviewAudio/IBMSPreviewMixBridge.cpp"
)
set_target_properties(IBMSPreviewMixBridge PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)
target_include_directories(IBMSPreviewMixBridge PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge"
)
target_compile_options(IBMSPreviewMixBridge PRIVATE
    "-target" "${IBMS_NATIVE_SWIFT_TARGET}"
)
target_link_libraries(IBMSPreviewMixBridge PUBLIC ibms_libsamplerate)

add_library(IBMSPreviewGroupedMixer STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/PreviewAudio/IBMSPreviewGroupedMixer.cpp"
)
set_target_properties(IBMSPreviewGroupedMixer PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)
target_include_directories(IBMSPreviewGroupedMixer PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge"
)
target_compile_options(IBMSPreviewGroupedMixer PRIVATE
    "-target" "${IBMS_NATIVE_SWIFT_TARGET}"
)
target_link_libraries(IBMSPreviewGroupedMixer PRIVATE
    IBMSPreviewMixBridge
    ibms_libsamplerate
    "-framework AudioToolbox"
)

target_sources(IBMSNative PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyPreviewAudio.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/LegacyBmsonPreview.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewPlayfieldView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewBGAView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewUbmStyle.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewUbmInfoView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewUbmBehavior.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewBmsSource.swift"
)

target_link_libraries(IBMSNative PRIVATE
    IBMSNativeAudioBridge
    "-framework AVFoundation"
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
)

# Official uBMplay 1.5.2 runtime files, atlas, readme, and the original zip.
# The default archive lives in this source tree. Runtime still uses the
# extracted image directory. The zip is staged unchanged for redistribution.
# Windows EXE and DLLs are data and are not executed. IDA databases, hidden
# files, and analysis leftovers are left out. Nothing is downloaded and
# nothing is written back into the source tree.
set(IBMS_UBMPLAY_REFERENCE_SHA256
    "d10c38ae09881ba6d1223a840a34a5c58d45bccfe31c2f283de460b732c16ada")
set(IBMS_UBMPLAY_REFERENCE_INPUT
    "${CMAKE_CURRENT_SOURCE_DIR}/Resources/UbmplayReference/ubmplay_152.zip"
    CACHE FILEPATH
    "Official uBMplay 1.5.2 zip, or a local extracted directory. Default is the vendored archive. This build never downloads it.")

set(_ibms_ubm_required
    image/font.png
    image/skin_00.png
    image/skin_01.png
    image/skin_02.png
    image/skin_03.png
    image.dll
    libogg.dll
    libvorbis.dll
    libvorbisfile.dll
    movie.dll
    readme.txt
    sound/engine.ogg
    sound.dll
    uBMplay.exe
)

function(ibms_ubmplay_path_excluded relative_path result_name)
    set(_excluded FALSE)
    string(REPLACE "\\" "/" _path "${relative_path}")
    if(_path MATCHES "(^|/)\\.\\.(/|$)" OR _path MATCHES "^/" OR _path MATCHES "^[A-Za-z]:")
        set(_excluded TRUE)
    endif()
    string(REPLACE "/" ";" _parts "${_path}")
    foreach(_part IN LISTS _parts)
        if(_part MATCHES "^\\." OR _part STREQUAL "__MACOSX")
            set(_excluded TRUE)
        endif()
    endforeach()
    get_filename_component(_ext "${_path}" LAST_EXT)
    string(TOLOWER "${_ext}" _ext)
    if(_ext MATCHES "^\\.(id0|id1|id2|nam|til|idb|i64|asm)$")
        set(_excluded TRUE)
    endif()
    set(${result_name} ${_excluded} PARENT_SCOPE)
endfunction()

function(ibms_ubmplay_require_zip_hash zip_path)
    if(NOT EXISTS "${zip_path}" OR IS_DIRECTORY "${zip_path}")
        message(FATAL_ERROR
            "uBMplay 1.5.2 reference zip does not exist:\n  ${zip_path}\n"
            "Set IBMS_UBMPLAY_REFERENCE_INPUT to the local official zip or a complete extracted directory. "
            "This build does not download it, and the preview skin is not left empty.")
    endif()
    file(SHA256 "${zip_path}" _actual)
    if(NOT _actual STREQUAL IBMS_UBMPLAY_REFERENCE_SHA256)
        message(FATAL_ERROR
            "uBMplay reference zip SHA256 mismatch.\n"
            "  file: ${zip_path}\n"
            "  actual: ${_actual}\n"
            "  expected: ${IBMS_UBMPLAY_REFERENCE_SHA256}\n"
            "Refusing to stage a different package. No download is attempted.")
    endif()
endfunction()

function(ibms_ubmplay_require_complete relative_paths)
    set(_missing "")
    foreach(_need IN LISTS _ibms_ubm_required)
        list(FIND relative_paths "${_need}" _found)
        if(_found LESS 0)
            list(APPEND _missing "${_need}")
        endif()
    endforeach()
    if(_missing)
        list(JOIN _missing "\n  " _missing_text)
        message(FATAL_ERROR
            "uBMplay 1.5.2 reference is incomplete. Missing:\n  ${_missing_text}\n"
            "Input: ${IBMS_UBMPLAY_REFERENCE_INPUT}\n"
            "The preview skin is not left empty. Provide the official zip "
            "(SHA256 ${IBMS_UBMPLAY_REFERENCE_SHA256}) or a complete local runtime tree. "
            "This build does not download it.")
    endif()
endfunction()

set(_ibms_ubm_mode "")
set(_ibms_ubm_zip "")
set(_ibms_ubm_archive "")
set(_ibms_ubm_payload "")
set(_ibms_ubm_rels "")
if(NOT EXISTS "${IBMS_UBMPLAY_REFERENCE_INPUT}")
    message(FATAL_ERROR
        "uBMplay 1.5.2 reference was not found:\n  ${IBMS_UBMPLAY_REFERENCE_INPUT}\n"
        "The default is macos/Resources/UbmplayReference/ubmplay_152.zip "
        "(SHA256 ${IBMS_UBMPLAY_REFERENCE_SHA256}). "
        "IBMS_UBMPLAY_REFERENCE_INPUT is a cache override; a missing override is a configure error. "
        "This build does not download it, and the preview skin is not left empty.")
elseif(IS_DIRECTORY "${IBMS_UBMPLAY_REFERENCE_INPUT}")
    if(EXISTS "${IBMS_UBMPLAY_REFERENCE_INPUT}/ubmplay_152.zip" AND NOT IS_DIRECTORY "${IBMS_UBMPLAY_REFERENCE_INPUT}/ubmplay_152.zip")
        set(_ibms_ubm_mode "zip")
        set(_ibms_ubm_zip "${IBMS_UBMPLAY_REFERENCE_INPUT}/ubmplay_152.zip")
    elseif(EXISTS "${IBMS_UBMPLAY_REFERENCE_INPUT}/ubmplay/image/skin_00.png")
        set(_ibms_ubm_mode "mirror")
        set(_ibms_ubm_payload "${IBMS_UBMPLAY_REFERENCE_INPUT}/ubmplay")
    elseif(EXISTS "${IBMS_UBMPLAY_REFERENCE_INPUT}/image/skin_00.png")
        set(_ibms_ubm_mode "mirror")
        set(_ibms_ubm_payload "${IBMS_UBMPLAY_REFERENCE_INPUT}")
    else()
        message(FATAL_ERROR
            "IBMS_UBMPLAY_REFERENCE_INPUT is a directory without ubmplay_152.zip or image/skin_00.png:\n"
            "  ${IBMS_UBMPLAY_REFERENCE_INPUT}\n"
            "The preview skin is not left empty.")
    endif()
else()
    set(_ibms_ubm_mode "zip")
    set(_ibms_ubm_zip "${IBMS_UBMPLAY_REFERENCE_INPUT}")
endif()

if(_ibms_ubm_mode STREQUAL "zip")
    set(_ibms_ubm_archive "${_ibms_ubm_zip}")
    ibms_ubmplay_require_zip_hash("${_ibms_ubm_zip}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar tf "${_ibms_ubm_zip}"
        RESULT_VARIABLE _ibms_ubm_tar_rc
        OUTPUT_VARIABLE _ibms_ubm_tar_out
        ERROR_VARIABLE _ibms_ubm_tar_err
    )
    if(NOT _ibms_ubm_tar_rc EQUAL 0)
        message(FATAL_ERROR
            "Cannot list uBMplay reference zip ${_ibms_ubm_zip}:\n${_ibms_ubm_tar_err}")
    endif()
    string(REPLACE "\r\n" "\n" _ibms_ubm_tar_out "${_ibms_ubm_tar_out}")
    string(REPLACE "\n" ";" _ibms_ubm_entries "${_ibms_ubm_tar_out}")
    foreach(_ibms_ubm_entry IN LISTS _ibms_ubm_entries)
        if(_ibms_ubm_entry STREQUAL "" OR _ibms_ubm_entry MATCHES "/$")
            continue()
        endif()
        if(NOT _ibms_ubm_entry MATCHES "^ubmplay/")
            message(FATAL_ERROR "uBMplay zip entry is outside ubmplay/: ${_ibms_ubm_entry}")
        endif()
        string(REGEX REPLACE "^ubmplay/" "" _ibms_ubm_rel "${_ibms_ubm_entry}")
        ibms_ubmplay_path_excluded("${_ibms_ubm_rel}" _ibms_ubm_skip)
        if(_ibms_ubm_skip)
            continue()
        endif()
        list(APPEND _ibms_ubm_rels "${_ibms_ubm_rel}")
    endforeach()
else()
    get_filename_component(_ibms_ubm_parent "${_ibms_ubm_payload}" DIRECTORY)
    if(EXISTS "${_ibms_ubm_parent}/ubmplay_152.zip" AND NOT IS_DIRECTORY "${_ibms_ubm_parent}/ubmplay_152.zip")
        ibms_ubmplay_require_zip_hash("${_ibms_ubm_parent}/ubmplay_152.zip")
        set(_ibms_ubm_archive "${_ibms_ubm_parent}/ubmplay_152.zip")
        message(STATUS "uBMplay mirror checked sibling zip ${_ibms_ubm_parent}/ubmplay_152.zip")
    else()
        message(STATUS
            "uBMplay mirror has no sibling ubmplay_152.zip; staging files on disk without a zip hash")
    endif()
    file(GLOB_RECURSE _ibms_ubm_found LIST_DIRECTORIES false "${_ibms_ubm_payload}/*")
    foreach(_ibms_ubm_abs IN LISTS _ibms_ubm_found)
        file(RELATIVE_PATH _ibms_ubm_rel "${_ibms_ubm_payload}" "${_ibms_ubm_abs}")
        string(REPLACE "\\" "/" _ibms_ubm_rel "${_ibms_ubm_rel}")
        ibms_ubmplay_path_excluded("${_ibms_ubm_rel}" _ibms_ubm_skip)
        if(_ibms_ubm_skip)
            continue()
        endif()
        list(APPEND _ibms_ubm_rels "${_ibms_ubm_rel}")
    endforeach()
endif()

list(REMOVE_DUPLICATES _ibms_ubm_rels)
list(SORT _ibms_ubm_rels)
ibms_ubmplay_require_complete("${_ibms_ubm_rels}")
list(LENGTH _ibms_ubm_rels _ibms_ubm_count)
if(_ibms_ubm_archive STREQUAL "")
    set(_ibms_ubm_archive_note "")
else()
    set(_ibms_ubm_archive_note " archive=${_ibms_ubm_archive}")
endif()
message(STATUS
    "uBMplay 1.5.2 reference: mode=${_ibms_ubm_mode} files=${_ibms_ubm_count}${_ibms_ubm_archive_note} input=${IBMS_UBMPLAY_REFERENCE_INPUT}")

set(_ibms_ubm_script "${CMAKE_CURRENT_BINARY_DIR}/ibms-stage-ubmplay-reference.cmake")
set(_ibms_ubm_manifest "${CMAKE_CURRENT_BINARY_DIR}/ibms-ubmplay-reference-manifest.txt")
set(_ibms_ubm_stage "${CMAKE_CURRENT_BINARY_DIR}/ubmplay-reference-stage/UbmplayReference")
set(_ibms_ubm_stamp "${CMAKE_CURRENT_BINARY_DIR}/ubmplay-reference-stage/ibms-ubmplay-reference.stamp")
set(_ibms_ubm_work "${CMAKE_CURRENT_BINARY_DIR}/ubmplay-152-extract")
list(JOIN _ibms_ubm_rels "\n" _ibms_ubm_manifest_text)
file(WRITE "${_ibms_ubm_manifest}" "${_ibms_ubm_manifest_text}\n")
file(WRITE "${_ibms_ubm_script}" [=[
if(NOT DEFINED MODE OR NOT DEFINED STAGE OR NOT DEFINED STAMP OR NOT DEFINED MANIFEST)
    message(FATAL_ERROR "uBMplay stage script is missing MODE, STAGE, STAMP, or MANIFEST")
endif()
file(STRINGS "${MANIFEST}" _rels)
if(MODE STREQUAL "zip")
    if(NOT DEFINED ZIP OR NOT DEFINED EXPECTED OR NOT DEFINED WORK)
        message(FATAL_ERROR "uBMplay zip staging is missing ZIP, EXPECTED, or WORK")
    endif()
    if(NOT EXISTS "${ZIP}" OR IS_DIRECTORY "${ZIP}")
        message(FATAL_ERROR "uBMplay reference zip disappeared: ${ZIP}")
    endif()
    file(SHA256 "${ZIP}" _actual)
    if(NOT _actual STREQUAL EXPECTED)
        message(FATAL_ERROR
            "uBMplay reference zip SHA256 mismatch.\n  file: ${ZIP}\n  actual: ${_actual}\n  expected: ${EXPECTED}\nThe preview skin was not staged.")
    endif()
    file(REMOVE_RECURSE "${WORK}")
    file(MAKE_DIRECTORY "${WORK}")
    file(ARCHIVE_EXTRACT INPUT "${ZIP}" DESTINATION "${WORK}" TOUCH)
    set(_root "${WORK}/ubmplay")
elseif(MODE STREQUAL "mirror")
    if(NOT DEFINED ROOT)
        message(FATAL_ERROR "uBMplay mirror staging is missing ROOT")
    endif()
    set(_root "${ROOT}")
else()
    message(FATAL_ERROR "Unknown uBMplay stage mode ${MODE}")
endif()
file(MAKE_DIRECTORY "${STAGE}")
foreach(_rel IN LISTS _rels)
    if(_rel MATCHES "(^|/)\\.\\.(/|$)" OR _rel MATCHES "^/" OR _rel MATCHES "^[A-Za-z]:")
        message(FATAL_ERROR "Refusing uBMplay path ${_rel}")
    endif()
    set(_src "${_root}/${_rel}")
    if(NOT EXISTS "${_src}" OR IS_DIRECTORY "${_src}")
        message(FATAL_ERROR "uBMplay reference file is missing: ${_src}")
    endif()
    get_filename_component(_dest_dir "${STAGE}/${_rel}" DIRECTORY)
    file(MAKE_DIRECTORY "${_dest_dir}")
    file(COPY "${_src}" DESTINATION "${_dest_dir}")
    get_filename_component(_ext "${_rel}" LAST_EXT)
    string(TOLOWER "${_ext}" _ext)
    if(_ext STREQUAL ".exe" OR _ext STREQUAL ".dll")
        file(CHMOD "${STAGE}/${_rel}" FILE_PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ)
    endif()
endforeach()
if(MODE STREQUAL "zip")
    file(REMOVE "${STAGE}/ubmplay_152.zip")
    file(COPY_FILE "${ZIP}" "${STAGE}/ubmplay_152.zip")
endif()
file(WRITE "${STAMP}" "staged\n")
]=])

set(_ibms_ubm_outputs "")
set(_ibms_ubm_sources "")
foreach(_ibms_ubm_rel IN LISTS _ibms_ubm_rels)
    list(APPEND _ibms_ubm_outputs "${_ibms_ubm_stage}/${_ibms_ubm_rel}")
    list(APPEND _ibms_ubm_sources "${_ibms_ubm_stage}/${_ibms_ubm_rel}")
endforeach()
if(_ibms_ubm_mode STREQUAL "zip")
    list(APPEND _ibms_ubm_outputs "${_ibms_ubm_stage}/ubmplay_152.zip")
    list(APPEND _ibms_ubm_sources "${_ibms_ubm_stage}/ubmplay_152.zip")
endif()
list(APPEND _ibms_ubm_outputs "${_ibms_ubm_stamp}")

if(_ibms_ubm_mode STREQUAL "zip")
    add_custom_command(
        OUTPUT ${_ibms_ubm_outputs}
        COMMAND "${CMAKE_COMMAND}"
                "-DMODE=zip"
                "-DZIP=${_ibms_ubm_zip}"
                "-DEXPECTED=${IBMS_UBMPLAY_REFERENCE_SHA256}"
                "-DSTAGE=${_ibms_ubm_stage}"
                "-DSTAMP=${_ibms_ubm_stamp}"
                "-DMANIFEST=${_ibms_ubm_manifest}"
                "-DWORK=${_ibms_ubm_work}"
                -P "${_ibms_ubm_script}"
        DEPENDS "${_ibms_ubm_zip}" "${_ibms_ubm_script}" "${_ibms_ubm_manifest}"
        COMMENT "Stage uBMplay 1.5.2 reference from the official zip"
        VERBATIM
    )
else()
    set(_ibms_ubm_depends "${_ibms_ubm_script}" "${_ibms_ubm_manifest}")
    foreach(_ibms_ubm_rel IN LISTS _ibms_ubm_rels)
        list(APPEND _ibms_ubm_depends "${_ibms_ubm_payload}/${_ibms_ubm_rel}")
    endforeach()
    add_custom_command(
        OUTPUT ${_ibms_ubm_outputs}
        COMMAND "${CMAKE_COMMAND}"
                "-DMODE=mirror"
                "-DROOT=${_ibms_ubm_payload}"
                "-DSTAGE=${_ibms_ubm_stage}"
                "-DSTAMP=${_ibms_ubm_stamp}"
                "-DMANIFEST=${_ibms_ubm_manifest}"
                -P "${_ibms_ubm_script}"
        DEPENDS ${_ibms_ubm_depends}
        COMMENT "Stage local uBMplay 1.5.2 reference files"
        VERBATIM
    )
endif()

# Keep the staged files on the target so Ninja emits the zip staging command.
# HEADER_FILE_ONLY stops CMake from compiling PNG/DLL/EXE. LINK_DEPENDS makes
# an atlas change rerun the Swift link, whose POST_BUILD copies into the bundle.
# MACOSX_PACKAGE_LOCATION is not enough: this Swift link step never builds it.
set_source_files_properties(${_ibms_ubm_sources} PROPERTIES
    GENERATED TRUE
    HEADER_FILE_ONLY TRUE
)
target_sources(IBMSNative PRIVATE ${_ibms_ubm_sources})
set_property(TARGET IBMSNative APPEND PROPERTY LINK_DEPENDS ${_ibms_ubm_sources})
if(_ibms_ubm_archive STREQUAL "")
    add_custom_command(TARGET IBMSNative POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_directory
                "${_ibms_ubm_stage}"
                "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/UbmplayReference"
        COMMENT "Copy uBMplay 1.5.2 reference into the app bundle"
        VERBATIM
    )
else()
    add_custom_command(TARGET IBMSNative POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_directory
                "${_ibms_ubm_stage}"
                "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/UbmplayReference"
        COMMAND "${CMAKE_COMMAND}" -E copy
                "${_ibms_ubm_archive}"
                "$<TARGET_BUNDLE_DIR:IBMSNative>/Contents/Resources/UbmplayReference/ubmplay_152.zip"
        COMMENT "Copy uBMplay 1.5.2 reference and original archive into the app bundle"
        VERBATIM
    )
endif()

function(ibms_preview_add_swift_test name)
    cmake_parse_arguments(IBMS_PREVIEW_TEST "" "" "SOURCES;FRAMEWORKS" ${ARGN})
    add_executable(${name} ${IBMS_PREVIEW_TEST_SOURCES})
    set(_framework_links "")
    foreach(_framework IN LISTS IBMS_PREVIEW_TEST_FRAMEWORKS)
        list(APPEND _framework_links "-framework ${_framework}")
    endforeach()
    target_link_libraries(${name} PRIVATE ${_framework_links})
    target_compile_options(${name} PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
    )
    target_link_options(${name} PRIVATE "-target" "${IBMS_NATIVE_SWIFT_TARGET}")
    add_test(NAME ${name} COMMAND ${name})
endfunction()

# Link the mix bridge. A target that already has -import-objc-header keeps
# that header; the new declarations arrive through its existing import.
function(ibms_preview_attach_mix_bridge target_name)
    target_sources(${target_name} PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewUnifiedAudioSession.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSNative/PreviewUnifiedAudioWorker.swift"
    )
    target_link_libraries(${target_name} PRIVATE
        IBMSPreviewMixBridge
        IBMSPreviewGroupedMixer
    )
    get_target_property(_ibms_preview_opts ${target_name} COMPILE_OPTIONS)
    set(_ibms_preview_has_bridge FALSE)
    if(_ibms_preview_opts)
        foreach(_ibms_preview_opt IN LISTS _ibms_preview_opts)
            if(_ibms_preview_opt MATCHES "import-objc-header")
                set(_ibms_preview_has_bridge TRUE)
            endif()
        endforeach()
    endif()
    if(NOT _ibms_preview_has_bridge)
        target_compile_options(${target_name} PRIVATE
            "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
            "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSAudio-Bridging-Header.h>"
        )
    endif()
endfunction()

ibms_preview_attach_mix_bridge(IBMSNative)

if(BUILD_TESTING)
    ibms_preview_add_swift_test(IBMSNativePreviewAudioTests
        SOURCES
            Tests/LegacyPreviewAudioTests.swift
            Sources/IBMSNative/LegacyPreviewAudio.swift
        FRAMEWORKS Foundation AVFoundation
    )

    ibms_preview_add_swift_test(IBMSNativeBmsonPreviewTests
        SOURCES
            Tests/LegacyBmsonPreviewTests.swift
            Sources/IBMSNative/LegacyBmsonPreview.swift
            Sources/IBMSNative/LegacyPreviewAudio.swift
            Sources/IBMSNative/BmsonChartMapping.swift
            Sources/IBMSNative/BmsONELayout.swift
        FRAMEWORKS Foundation CoreGraphics AVFoundation
    )
    target_compile_options(IBMSNativeBmsonPreviewTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
    )

    # 谱面读回用 ImageIO/CGImage 写像素，不引用 AVFoundation。
    ibms_preview_add_swift_test(IBMSNativePreviewPlayfieldTests
        SOURCES
            Tests/PreviewPlayfieldTests.swift
            Sources/IBMSNative/PreviewPlayfieldView.swift
            Sources/IBMSNative/PreviewUbmStyle.swift
            Sources/IBMSNative/LegacyPreviewAudio.swift
        FRAMEWORKS Cocoa ImageIO Metal MetalKit QuartzCore
    )

    ibms_preview_add_swift_test(IBMSNativePreviewBGATests
        SOURCES
            Tests/PreviewBGATests.swift
            Sources/IBMSNative/PreviewBGAView.swift
            Sources/IBMSNative/LegacyPreviewAudio.swift
        FRAMEWORKS Cocoa AVFoundation AudioToolbox CoreMedia CoreVideo ImageIO QuartzCore UniformTypeIdentifiers
    )

    ibms_preview_add_swift_test(IBMSNativePreviewWindowTests
        SOURCES
            Tests/PreviewWindowTests.swift
            Sources/IBMSNative/PreviewWindowController.swift
            Sources/IBMSNative/PreviewUbmInfoView.swift
            Sources/IBMSNative/PreviewUbmBehavior.swift
            Sources/IBMSNative/PreviewBmsSource.swift
            Sources/IBMSNative/PreviewUbmStyle.swift
            Sources/IBMSNative/PreviewPlayfieldView.swift
            Sources/IBMSNative/PreviewBGAView.swift
            Sources/IBMSNative/LegacyPreviewAudio.swift
            Sources/IBMSNative/NativeLocalization.swift
            Sources/IBMSNative/BmsONEPreferences.swift
            Sources/IBMSNative/BmsONELayout.swift
        FRAMEWORKS Cocoa AVFoundation ImageIO Metal MetalKit QuartzCore
    )

    ibms_preview_add_swift_test(IBMSNativePreviewUbmBehaviorTests
        SOURCES
            Tests/PreviewUbmBehaviorTests.swift
            Sources/IBMSNative/PreviewUbmBehavior.swift
        FRAMEWORKS Foundation
    )

    add_executable(IBMSNativePreviewBmsSourceTests
        Tests/PreviewBmsSourceTests.swift
        Sources/IBMSNative/PreviewBmsSource.swift
        Sources/IBMSNative/DocumentSession.swift
        Sources/IBMSNative/ChartLayout.swift
        Sources/IBMSNative/LegacyChartPaint.swift
        Sources/IBMSNative/ChartTheme.swift
        Sources/IBMSNative/TimingPanel.swift
        Sources/IBMSNative/LegacyClipboard.swift
        Sources/IBMSNative/LegacyNTConvert.swift
        Sources/IBMSNative/LegacyWavList.swift
        Sources/IBMSNative/LegacyPanelGuides.swift
        Sources/IBMSNative/NativeLocalization.swift
    )
    target_link_libraries(IBMSNativePreviewBmsSourceTests PRIVATE
        IBMSNativeBridge
        IBMSNativeBmsonBridge
        "-framework Foundation"
        "-framework Cocoa"
    )
    target_compile_options(IBMSNativePreviewBmsSourceTests PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-swift-version>"
        "$<$<COMPILE_LANGUAGE:Swift>:6>"
        "$<$<COMPILE_LANGUAGE:Swift>:-target>"
        "$<$<COMPILE_LANGUAGE:Swift>:${IBMS_NATIVE_SWIFT_TARGET}>"
        "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:-import-objc-header>"
        "$<$<COMPILE_LANGUAGE:Swift>:${CMAKE_CURRENT_SOURCE_DIR}/Sources/IBMSBridge/IBMSNative-Bridging-Header.h>"
    )
    target_link_options(IBMSNativePreviewBmsSourceTests PRIVATE
        "-target"
        "${IBMS_NATIVE_SWIFT_TARGET}"
    )
    add_test(NAME IBMSNativePreviewBmsSourceTests COMMAND IBMSNativePreviewBmsSourceTests)

    foreach(_ibms_legacy_preview IN ITEMS
        IBMSNativePreviewAudioTests
        IBMSNativeBmsonPreviewTests
        IBMSNativePreviewPlayfieldTests
        IBMSNativePreviewBGATests
        IBMSNativePreviewWindowTests
    )
        ibms_preview_attach_mix_bridge(${_ibms_legacy_preview})
    endforeach()

    # Test executables are not the app bundle. They may fall back to the local
    # reference tree. The app target must not define this flag.
    foreach(_ibms_skin_test IN ITEMS
        IBMSNativePreviewPlayfieldTests
        IBMSNativePreviewWindowTests
    )
        target_compile_options(${_ibms_skin_test} PRIVATE
            "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-D IBMS_PREVIEW_DEV_SKIN_FALLBACK>"
        )
    endforeach()
endif()
