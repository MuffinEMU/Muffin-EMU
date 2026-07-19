#!/bin/bash
# Generates a linker response file listing every static lib produced by the CMake
# build (build-ios/) and every third-party dep vcpkg installed for arm64-ios, so the
# Xcode app target can link against them without hand-maintaining ~90 library names
# here. Run as an Xcode preBuildScript (see project.yml) before every build.
set -euo pipefail

OUT="${1:?usage: generate-link-flags.sh <output-file>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-ios"

: > "$OUT"

# CMake's manifest-mode vcpkg installs to build-ios/vcpkg_installed/arm64-ios/lib —
# nested inside BUILD_DIR — so this one find picks up CemuCafe/iosgui's own .a files
# AND every vcpkg dependency (boost, fmt, curl, ...) in one pass.
if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -name "*.a" | while read -r lib; do
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
