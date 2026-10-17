#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Compiles libCemu.so (the Cemu core with the Android JNI bridge) for arm64 Android from scratch and
# leaves it, with the NDK's libc++_shared.so, in build-android/out. The Android counterpart of
# ci/build-core.sh: a fresh build directory, vcpkg building the dependencies during configure (cached
# in .vcpkg-archives), then the core.
#
#   ci/build-core-android.sh                   configure, then build the core
#   ci/build-core-android.sh --configure-only  configure only (fills the vcpkg binary cache)
#
# Needs ANDROID_NDK_HOME (the vcpkg Android triplet reads it too).
set -eo pipefail
cd "$(dirname "$0")/.."

CONFIGURE_ONLY=false
case "${1:-}" in
  "") ;;
  --configure-only) CONFIGURE_ONLY=true ;;
  *) echo "usage: $0 [--configure-only]" >&2; exit 2 ;;
esac

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "::error::ANDROID_NDK_HOME is not set"
  exit 1
fi
export ANDROID_NDK="$ANDROID_NDK_HOME"

rm -rf build-android
mkdir -p .vcpkg-archives

FLAGS=(
  -DCMAKE_SYSTEM_NAME=Android
  -DCMAKE_SYSTEM_VERSION=29
  -DANDROID_PLATFORM=android-29
  -DANDROID_ABI=arm64-v8a
  -DANDROID_STL=c++_shared
  "-DANDROID_NDK=$ANDROID_NDK_HOME"
  "-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
  -DVCPKG_TARGET_TRIPLET=arm64-android
  -DVCPKG_HOST_TRIPLET=x64-linux
  -DBUILD_HEADLESS_DYLIB=ON
  -DCMAKE_BUILD_TYPE=Release
)

# Configure is retried for the same reason as the iOS build: vcpkg downloads ports from third-party
# hosts during configure and treats a DNS failure as final. Everything already built stays cached.
configure() {
  cmake -S . -B build-android -G Ninja "${FLAGS[@]}" 2>&1 | tee configure.log
}
configured=no
for attempt in 1 2 3; do
  if configure; then configured=yes; break; fi
  if [ "$attempt" = 3 ]; then
    echo "::error::configure failed three times - see configure.log"
    exit 1
  fi
  echo "configure attempt $attempt failed; waiting $((attempt * 30))s"
  sleep $((attempt * 30))
done

: > build-android/vcpkg-deps-complete
if [ "$CONFIGURE_ONLY" = true ]; then exit 0; fi

cmake --build build-android --target CemuBin 2>&1 | tee build.log
SO=$(find build-android -name libCemu.so -not -path '*/CMakeFiles/*' | head -n1)
if [ -z "$SO" ]; then echo "::error::the build finished but produced no libCemu.so"; exit 1; fi
rm -rf build-android/out && mkdir -p build-android/out
cp "$SO" build-android/out/
cp "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so build-android/out/
ls -l build-android/out
