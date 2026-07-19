#!/bin/bash
# Generates a linker response file listing every static lib produced by the CMake
# build (build-ios/) and every third-party dep vcpkg installed for arm64-ios, so the
# Xcode app target can link against them without hand-maintaining ~90 library names
# here. Run as an Xcode preBuildScript (see project.yml) before every build.
set -euo pipefail

OUT="${1:?usage: generate-link-flags.sh <output-file>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-ios"
VCPKG_LIB_DIR="$HOME/vcpkg/installed/arm64-ios/lib"

: > "$OUT"

if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -name "*.a" | while read -r lib; do
        name=$(basename "$lib" .a)
        name=${name#lib}
        echo "-l${name}" >> "$OUT"
    done
fi

if [ -d "$VCPKG_LIB_DIR" ]; then
    find "$VCPKG_LIB_DIR" -maxdepth 1 -name "*.a" | while read -r lib; do
        name=$(basename "$lib" .a)
        name=${name#lib}
        echo "-l${name}" >> "$OUT"
    done
fi

echo "-framework Foundation" >> "$OUT"
echo "-framework Metal" >> "$OUT"
echo "-framework MetalKit" >> "$OUT"
echo "-framework UIKit" >> "$OUT"

echo "generate-link-flags.sh: wrote $(wc -l < "$OUT") linker args to $OUT"
