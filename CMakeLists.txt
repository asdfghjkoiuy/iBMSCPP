cmake_minimum_required(VERSION 3.26)

if(CMAKE_HOST_APPLE AND NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS deployment target")
endif()

project(iBMSCPP LANGUAGES CXX)

include(CheckCXXSourceCompiles)
check_cxx_source_compiles([[ 
int main() {
    __int128 signed_value = 1;
    unsigned __int128 unsigned_value = 1;
    return static_cast<int>(static_cast<unsigned __int128>(signed_value) + unsigned_value - 2);
}
]] IBMS_HAS_INT128)
if(NOT IBMS_HAS_INT128)
    message(FATAL_ERROR "ibms_core requires compiler support for __int128 (supported by Clang and GCC); MSVC requires a future wide-integer backend.")
endif()

if(APPLE)
    set(_ibms_build_macos_app_default ON)
else()
    set(_ibms_build_macos_app_default OFF)
endif()

option(IBMS_BUILD_MACOS_APP "Build the native macOS application when its sources are available" ${_ibms_build_macos_app_default})

add_subdirectory(core)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

if(APPLE AND IBMS_BUILD_MACOS_APP AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/macos/CMakeLists.txt")
    add_subdirectory(macos)
endif()
