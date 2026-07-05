# Real iOS CMake toolchain for Cemu (arm64, device).
#
# Unlike the earlier cmake/ios.cmake (which set CMAKE_SYSTEM_NAME=Darwin and used
# plain /usr/bin/clang with no iOS sysroot — i.e. it targeted arm64 *macOS*), this
# toolchain actually cross-compiles for iOS: real SYSTEM_NAME iOS, the iPhoneOS
# sysroot resolved via xcrun, and a minimum deployment version.
#
# Usage:
#   cmake -B build-ios -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
#         -DVCPKG_TARGET_TRIPLET=arm64-ios ...
#
# Requires a machine with FULL Xcode (iOS SDK). Command Line Tools alone are not enough.

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS arch")

if(NOT DEFINED IOS_DEPLOYMENT_TARGET)
  set(IOS_DEPLOYMENT_TARGET "15.0")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET "${IOS_DEPLOYMENT_TARGET}" CACHE STRING "iOS min version")

# Resolve the iPhoneOS SDK path from the active (full) Xcode.
execute_process(
  COMMAND xcrun --sdk iphoneos --show-sdk-path
  OUTPUT_VARIABLE IOS_SDK_PATH
  OUTPUT_STRIP_TRAILING_WHITESPACE
  RESULT_VARIABLE _sdk_result)
if(NOT _sdk_result EQUAL 0 OR IOS_SDK_PATH STREQUAL "")
  message(FATAL_ERROR "iPhoneOS SDK not found. Full Xcode is required (Command Line Tools are not enough).")
endif()
set(CMAKE_OSX_SYSROOT "${IOS_SDK_PATH}" CACHE STRING "iOS sysroot")

set(CMAKE_C_COMPILER   clang)
set(CMAKE_CXX_COMPILER clang++)

# Search host tools on the host, but libraries/headers in the iOS sysroot only.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Signal to Cemu's build that this is the iOS platform and the engine bridge is live.
add_compile_definitions(PLATFORM_IOS=1 CEMU_CORE_AVAILABLE=1)

# This CMake build produces static libs + helper executables (e.g. ZArchive's
# zarchiveTool), never app bundles. iOS otherwise treats executables as
# MACOSX_BUNDLE, which makes their install() rules fail without a BUNDLE
# DESTINATION. The real iOS .app is built separately via Xcode (src/ios/project.yml).
set(CMAKE_MACOSX_BUNDLE OFF)
