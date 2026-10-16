#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Compiles Cemu.framework (the Cemu core with the Swift bridge and its glue) for arm64 iOS from
# scratch and leaves it in build-ios/out. A fresh build directory, no compiler cache, no partial
# results from any earlier build: see docs/CI.md for why the core is only ever built whole or
# reused whole. The CMake flags live in ci/core-cache-key.sh, because they are part of what the
# core's fingerprint covers.
#
#   ci/build-core.sh                   configure (which builds the vcpkg dependencies), then build the core
#   ci/build-core.sh --configure-only  configure only: what .github/workflows/vcpkg-cache.yml runs to fill
#                                      vcpkg's binary cache without compiling the core
set -eo pipefail
cd "$(dirname "$0")/.."

CONFIGURE_ONLY=false
case "${1:-}" in
  "") ;;
  --configure-only) CONFIGURE_ONLY=true ;;
  *) echo "usage: $0 [--configure-only]" >&2; exit 2 ;;
esac

rm -rf build-ios
mkdir -p .vcpkg-archives

FLAGS=()
while IFS= read -r f; do FLAGS+=("$f"); done < <(./ci/core-cache-key.sh --cmake-flags)

# CMAKE_MACOSX_BUNDLE=OFF (in the flags): for an iOS target CMake makes every executable an app
# bundle by default, and the ZArchive submodule's zarchiveTool install rule has no bundle
# destination, which stops configure. Cemu.framework is a library and is unaffected.
#
# Configure is retried: vcpkg downloads its ports from third-party hosts during configure, and a
# build died here on "curl operation failed with error code 6 (Couldn't resolve host name)" for
# libtiff. vcpkg classifies a DNS failure as NON-transient and refuses to retry it itself, which is
# exactly backwards - name resolution is the most transient failure there is. Re-running is safe:
# everything vcpkg already built stays in the binary cache, so a retry resumes rather than starting
# over.
configure() {
  cmake -S . -B build-ios -G Ninja "${FLAGS[@]}" 2>&1 | tee configure.log
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

# Configure succeeded, so vcpkg installed every dependency and .vcpkg-archives holds the complete set.
# The workflows save that cache only when this marker exists: a configure that died partway (a
# download failure) leaves a partial set, and saved under the exact key it would be restored by every
# later run, which then rebuilds the missing ports each time and never saves the complete set (an
# exact cache hit skips the save).
: > build-ios/vcpkg-deps-complete
if [ "$CONFIGURE_ONLY" = true ]; then exit 0; fi

cmake --build build-ios --target CemuBin 2>&1 | tee build.log
FW=$(find build-ios bin -type d -name Cemu.framework -not -path '*/CMakeFiles/*' 2>/dev/null | head -n1)
if [ -z "$FW" ]; then echo "::error::the build finished but produced no Cemu.framework"; exit 1; fi
rm -rf build-ios/out && mkdir -p build-ios/out
cp -R "$FW" build-ios/out/
file build-ios/out/Cemu.framework/Cemu
