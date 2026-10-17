set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
# API 29 (Android 10): the first release where every arm64 device ships a Vulkan 1.1 driver.
set(VCPKG_CMAKE_SYSTEM_VERSION 29)
