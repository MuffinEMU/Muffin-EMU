#!/bin/bash
# The fingerprint of Cemu.framework: a hash of EVERYTHING that can change a byte of it.
#
# Two builds with the same fingerprint would compile the same framework, so a verified copy of it
# can be reused instead of compiled again. Two builds with different fingerprints never share
# anything. That is the whole rule; docs/CI.md explains how the workflow uses it.
#
#   ci/core-cache-key.sh                 print the fingerprint (40 hex digits)
#   ci/core-cache-key.sh --manifest      print the text the fingerprint is the SHA-256 of
#   ci/core-cache-key.sh --cmake-flags   print the CMake flags of the core build, one per line
#   ci/core-cache-key.sh --stamp DIR     write DIR/core-fingerprint.txt and DIR/core-manifest.txt next
#                                        to DIR/Cemu.framework (the record that travels with a cached core)
#   ci/core-cache-key.sh --verify DIR    re-derive the fingerprint from the tree as it is NOW and check the
#                                        core in DIR against it. Exit 1 on any mismatch, and say why.
#   ci/core-cache-key.sh --rev           the newest commit that changed a core input
#
# What goes in the manifest:
#   * the toolchain the core is compiled with: the Xcode that build step selects, its iOS SDK (version,
#     build and a hash of its SDKSettings), the compiler, linker and CMake versions, the host OS, and the
#     environment variables that change compiler or linker behaviour
#   * every flag and define of the core build, and the deployment target
#   * every tracked file the core build reads, by git blob id. A submodule counts by the commit it
#     pins, so vcpkg, cubeb, imgui and the rest are covered without being checked out. dependencies/
#     includes the vendored MoltenVK builds, so a MoltenVK change is a core change.
#
# What is deliberately NOT in it: the Swift app (src/ios/App, Emulation, Rendering, Resources and the
# Xcode project files), the docs, the workflow files and the rest of ci/. None of them reach the core.
#
# Adding an input to the core build means adding it below. The manifest lists its own contents, so
# adding a path changes every fingerprint, which is the safe direction. NEVER remove a path or a
# tool line to make a fingerprint "match": a fingerprint that matches when it should not is how a
# stale core ships.
set -eo pipefail
cd "$(dirname "$0")/.."

# The core is built under the Xcode the first build step selects. Pin it here so the fingerprint is
# the same wherever in the job it is computed.
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

CORE_PATHS=(
  CMakeLists.txt cmake triplets vcpkg.json .gitmodules dependencies src
  ':(exclude)src/ios/App' ':(exclude)src/ios/Emulation' ':(exclude)src/ios/Rendering'
  ':(exclude)src/ios/Resources' ':(exclude)src/ios/project.yml'
  ':(exclude)src/ios/Info-AlternateIcons.plist'
  ':(exclude)src/ios/Cemu.entitlements' ':(exclude)src/ios/Sideload.entitlements'
)

CMAKE_FLAGS=(
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
  -DVCPKG_TARGET_TRIPLET=arm64-ios
  -DBUILD_HEADLESS_DYLIB=ON
  -DCMAKE_MACOSX_BUNDLE=OFF
  -DCMAKE_BUILD_TYPE=Release
)

# Run a tool and insist on an answer. A fingerprint computed from an empty "toolchain" line would
# match every other empty one, so a tool that fails or prints nothing stops the script instead.
need() {
  local out
  out=$("$@" 2>&1) || { echo "core-cache-key: '$*' failed: $out" >&2; return 1; }
  [ -n "$out" ] || { echo "core-cache-key: '$*' printed nothing" >&2; return 1; }
  printf '%s' "$out"
}

manifest() {
  local developer xcode sdkpath sdkver sdkbuild clang clangpp cmakev host
  developer=$(need xcode-select -p)
  xcode=$(need xcodebuild -version | tr '\n' ' ')
  sdkpath=$(need xcrun --sdk iphoneos --show-sdk-path)
  sdkver=$(need xcrun --sdk iphoneos --show-sdk-version)
  sdkbuild=$(need xcrun --sdk iphoneos --show-sdk-build-version)
  clang=$(need xcrun --sdk iphoneos clang --version | tr '\n' ' ')
  clangpp=$(need xcrun --sdk iphoneos -f clang++)
  cmakev=$(need cmake --version | head -n1)
  host="$(need sw_vers -productName) $(need sw_vers -productVersion) $(need sw_vers -buildVersion) $(uname -m)"
  echo "schema: 1"
  echo "== toolchain"
  echo "developer-dir: $developer"
  echo "xcode: $xcode"
  echo "sdk: iphoneos $sdkver build $sdkbuild"
  if [ -f "$sdkpath/SDKSettings.json" ]; then
    echo "sdk-settings-sha256: $(shasum -a 256 "$sdkpath/SDKSettings.json" | cut -d' ' -f1)"
  else
    echo "sdk-settings-sha256: none"
  fi
  echo "clang: $clang"
  echo "clang++-sha256: $(shasum -a 256 "$clangpp" | cut -d' ' -f1)"
  echo "ld: $( (xcrun --sdk iphoneos ld -v 2>&1 || true) | head -n1)"
  echo "cmake: $cmakev"
  echo "host: $host"
  # Printed even when empty, so that setting one of these later changes the fingerprint.
  local v
  for v in SDKROOT IPHONEOS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET CC CXX CFLAGS CXXFLAGS \
           CPPFLAGS OBJCFLAGS OBJCXXFLAGS LDFLAGS CMAKE_GENERATOR CMAKE_TOOLCHAIN_FILE VCPKG_ROOT; do
    echo "env $v=${!v}"
  done
  echo "== build"
  echo "generator: Ninja"
  echo "target: CemuBin"
  local f
  for f in "${CMAKE_FLAGS[@]}"; do echo "flag $f"; done
  echo "== tracked inputs (mode blob path)"
  git ls-files -s -- "${CORE_PATHS[@]}"
}

fingerprint() {
  local m
  m=$(mktemp); trap 'rm -f "$m"' RETURN
  manifest > "$m"
  shasum -a 256 "$m" | cut -c1-40
}

uuid_of() { otool -l "$1" | awk '/LC_UUID/{getline; getline; print $2; exit}'; }

case "${1:-}" in
  "")            fingerprint ;;
  --manifest)    manifest ;;
  --rev)         git log -1 --format=%h -- "${CORE_PATHS[@]}" ;;
  --cmake-flags) printf '%s\n' "${CMAKE_FLAGS[@]}" ;;
  --stamp)
    DIR="${2:?usage: --stamp DIR}"
    BIN="$DIR/Cemu.framework/Cemu"
    [ -f "$BIN" ] || { echo "core-cache-key: no $BIN to stamp" >&2; exit 1; }
    manifest > "$DIR/core-manifest.txt"
    {
      echo "fingerprint: $(shasum -a 256 "$DIR/core-manifest.txt" | cut -c1-40)"
      echo "binary-sha256: $(shasum -a 256 "$BIN" | cut -d' ' -f1)"
      echo "binary-uuid: $(uuid_of "$BIN")"
      echo "built-from-commit: ${GITHUB_SHA:-$(git rev-parse HEAD)}"
      echo "built-by-run: ${GITHUB_RUN_ID:-local}"
    } > "$DIR/core-fingerprint.txt"
    cat "$DIR/core-fingerprint.txt"
    ;;
  --verify)
    DIR="${2:?usage: --verify DIR}"
    BIN="$DIR/Cemu.framework/Cemu"
    for f in "$BIN" "$DIR/core-fingerprint.txt" "$DIR/core-manifest.txt"; do
      [ -f "$f" ] || { echo "core-cache-key: FAIL: $f is missing" >&2; exit 1; }
    done
    NOW=$(mktemp); trap 'rm -f "$NOW"' EXIT
    manifest > "$NOW"
    WANT=$(shasum -a 256 "$NOW" | cut -c1-40)
    HAVE=$(sed -n 's/^fingerprint: //p' "$DIR/core-fingerprint.txt")
    if [ "$WANT" != "$HAVE" ]; then
      echo "core-cache-key: FAIL: the cached core was built for fingerprint $HAVE, this tree is $WANT" >&2
      diff "$DIR/core-manifest.txt" "$NOW" | head -n 40 >&2 || true
      exit 1
    fi
    # The stored manifest must be what the stored fingerprint says, and the binary what it recorded.
    if [ "$(shasum -a 256 "$DIR/core-manifest.txt" | cut -c1-40)" != "$HAVE" ]; then
      echo "core-cache-key: FAIL: the cached manifest does not hash to its own fingerprint" >&2; exit 1
    fi
    if [ "$(shasum -a 256 "$BIN" | cut -d' ' -f1)" != "$(sed -n 's/^binary-sha256: //p' "$DIR/core-fingerprint.txt")" ]; then
      echo "core-cache-key: FAIL: the cached framework binary is not the one that was stamped" >&2; exit 1
    fi
    if [ "$(uuid_of "$BIN")" != "$(sed -n 's/^binary-uuid: //p' "$DIR/core-fingerprint.txt")" ]; then
      echo "core-cache-key: FAIL: the cached framework's LC_UUID changed since it was stamped" >&2; exit 1
    fi
    echo "core-cache-key: ok - cached core matches fingerprint $HAVE"
    ;;
  *) echo "usage: $0 [--manifest|--rev|--cmake-flags|--stamp DIR|--verify DIR]" >&2; exit 2 ;;
esac
