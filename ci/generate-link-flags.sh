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
# AND every vcpkg dependency (boost, fmt, curl, ...) in one pass. vcpkg also builds a
# debug/lib variant of everything (e.g. libSDL2maind.a); those aren't on this Release
# build's LIBRARY_SEARCH_PATHS, so "library not found" if included - exclude them.
# sort -u dedupes (some libs get visited more than once) to quiet linker warnings.
if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -name "*.a" -not -path "*/debug/*" | while read -r lib; do
        name=$(basename "$lib" .a)
        name=${name#lib}
        echo "-l${name}"
    done | sort -u >> "$OUT"
fi

echo "-framework Foundation" >> "$OUT"
echo "-framework Metal" >> "$OUT"
echo "-framework MetalKit" >> "$OUT"
echo "-framework UIKit" >> "$OUT"

echo "generate-link-flags.sh: wrote $(wc -l < "$OUT") linker args to $OUT"
