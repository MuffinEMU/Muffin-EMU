set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
# API 29 (Android 10): the first release where every arm64 device ships a Vulkan 1.1 driver.
set(VCPKG_CMAKE_SYSTEM_VERSION 29)
# vcpkg's Android toolchain leaves the ABI to the NDK's default (32-bit armeabi-v7a) unless the triplet
# names it, so every port came out 32-bit the first time. Same two lines as vcpkg's own arm64-android.
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
