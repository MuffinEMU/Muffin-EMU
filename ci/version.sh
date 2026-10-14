#!/bin/sh
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# The first MuffinEMU release number, and the version stamped into test builds.
#
# Releases are numbered by CI, not by hand. Every build of main publishes the next
# version, X.Y.Z: the newest numbered tag plus one in Z, with .9 rolling over
# (1.0.9 -> 1.1.0). See ci/release_version.py. This file only supplies the number used
# when no numbered tag exists yet, and the version stamped into builds of other branches.
# See "Choose the version" in .github/workflows/build-ios-app.yml.
#
# It lives in ci/ and NOT at the repository root: macOS is case-insensitive, the
# compiler is invoked with -I . , and C++20 has a standard header called <version>, so a
# root-level VERSION file shadows it and breaks the build.
set -eu
cd "$(dirname "$0")/.."
VER=$(tr -d ' \t\n\r' < ci/VERSION)
case "$VER" in
  [0-9]*.[0-9]*) ;;
  *) echo "ci/VERSION must be major.minor, got '$VER'" >&2; exit 1 ;;
esac
echo "$VER"
