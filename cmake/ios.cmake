# iOS CMake Toolchain for Cemu
# Phase 0: Build as ARM64 cross-compile, skip strict iOS SDK checks

set(PLATFORM_IOS ON CACHE BOOL "Building for iOS")

# ARM64 cross-compilation for iOS
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_SYSTEM_NAME Darwin)

# C++20 required
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compiler
set(CMAKE_C_COMPILER /usr/bin/clang CACHE STRING "Clang C compiler")
set(CMAKE_CXX_COMPILER /usr/bin/clang++ CACHE STRING "Clang C++ compiler")

# Compiler flags for ARM64 iOS
set(CMAKE_C_FLAGS_INIT "-arch arm64 -fPIC -fembed-bitcode=off" CACHE STRING "C flags")
set(CMAKE_CXX_FLAGS_INIT "-arch arm64 -fPIC -fvisibility=hidden -std=c++20 -fembed-bitcode=off" CACHE STRING "C++ flags")

# Framework linking
set(CMAKE_EXE_LINKER_FLAGS_INIT "-arch arm64 -lSystem" CACHE STRING "Linker flags")

# iOS minimum deployment
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "iOS deployment target")
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "iOS architectures")
