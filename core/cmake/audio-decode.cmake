# WAV / Ogg Vorbis / MP3 decode for built-in preview, slice, and BmsONE mix.
# Do not edit core/CMakeLists.txt.
# Root project() only enables CXX; stb_vorbis.c is C.

enable_language(C)

target_sources(ibms_core PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../src/audio_decode.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../../third_party/stb/stb_vorbis.c"
)
target_include_directories(ibms_core PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../third_party/stb"
    "${CMAKE_CURRENT_LIST_DIR}/../../third_party/minimp3"
)
