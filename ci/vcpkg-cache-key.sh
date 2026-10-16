#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# The Actions cache key for vcpkg's binary cache (.vcpkg-archives) of the arm64-ios core build.
# One definition, used by build-ios-app.yml, build-audit-ipa.yml and vcpkg-cache.yml, so the job that
# fills the cache and the jobs that read it can never drift apart.
#
#   ci/vcpkg-cache-key.sh [REPO_ROOT]     prints two lines, ready for $GITHUB_OUTPUT:
#     prefix=vcpkg-arm64-ios-<vcpkg commit>-<toolchain>-
#     key=<prefix><dependency inputs>
#
# This key only decides which archive set is downloaded. What is actually reused is decided by vcpkg
# itself, per port, by its own ABI hash (compiler, SDK, triplet, port files), so a wrong key can only
# cost time, never put a stale library into a build. The toolchain is in the key for the time it
# saves: when the runner image moves to a new Xcode every ABI hash changes, the old archives are
# useless, and a key without the toolchain would keep restoring them while blocking a fresh save
# (an Actions cache entry can never be overwritten).
#
# Needs no submodule checkout: the vcpkg submodule counts by the commit the tree pins.
set -eo pipefail
cd "${1:-$(dirname "$0")/..}"

# The core, and so its dependencies, are built under the Xcode build-ios-app.yml's first
# "Select full Xcode" step picks (ci/core-cache-key.sh pins the same one).
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# A tool that fails or prints nothing stops the script: an empty toolchain line would make every
# toolchain look the same.
need() {
  local out
  out=$("$@" 2>&1) || { echo "vcpkg-cache-key: '$*' failed: $out" >&2; return 1; }
  [ -n "$out" ] || { echo "vcpkg-cache-key: '$*' printed nothing" >&2; return 1; }
  printf '%s\n' "$out"
}

# Each tool runs in a plain assignment, where set -e stops the script on a failure (inside a
# command substitution's pipeline it would not).
REV=$(need git rev-parse HEAD:dependencies/vcpkg)
XCODE=$(need xcodebuild -version)
SDKBUILD=$(need xcrun --sdk iphoneos --show-sdk-build-version)
CMAKEV=$(need cmake --version)
TOOLCHAIN=$(printf '%s\n' "$XCODE" "iphoneos $SDKBUILD" "${CMAKEV%%$'\n'*}" "$(uname -m)" | shasum -a 256 | cut -c1-12)
# The same inputs the key always covered (vcpkg.json, the triplets, the overlay ports used on Apple),
# by git blob id.
INPUTS=$(git ls-files -s -- vcpkg.json triplets dependencies/vcpkg_overlay_ports dependencies/vcpkg_overlay_ports_mac \
  | shasum -a 256 | cut -c1-16)

PREFIX="vcpkg-arm64-ios-$REV-$TOOLCHAIN-"
echo "prefix=$PREFIX"
echo "key=$PREFIX$INPUTS"
