#!/bin/bash
# Generates a linker response file listing every static lib produced by the CMake
# build (build-ios/) and every third-party dep vcpkg installed for arm64-ios, so the
# Xcode app target can link against them without hand-maintaining ~90 library names
# (and their exact build-tree locations) in project.yml. Run as an Xcode
# preBuildScript (see project.yml) before every build.
#
# Uses full paths (not -l<name> + LIBRARY_SEARCH_PATHS): CMake scatters .a outputs
# across many subdirectories (src/Cafe, src/gui/iosgui, vcpkg_installed/.../lib,
# dependencies/ih264d, dependencies/xbyak_aarch64, ...), and every time a new one
# turned up somewhere not already hand-listed in LIBRARY_SEARCH_PATHS, linking failed
# with "library X not found" even though the .a existed. Full paths sidestep the
# whole search-path problem - if find locates it, the linker can find it too.
set -euo pipefail

OUT="${1:?usage: generate-link-flags.sh <output-file>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build-ios"

: > "$OUT"

# vcpkg also builds a debug/lib variant of everything (e.g. libSDL2maind.a) which
# this Release build never wants. sort -u dedupes (some libs get visited more than
# once) to quiet the linker's "ignoring duplicate libraries" warning.
if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -name "*.a" -not -path "*/debug/*" | sort -u >> "$OUT"
fi

echo "-framework Foundation" >> "$OUT"
echo "-framework Metal" >> "$OUT"
echo "-framework MetalKit" >> "$OUT"
echo "-framework UIKit" >> "$OUT"

echo "generate-link-flags.sh: wrote $(wc -l < "$OUT") linker args to $OUT"
