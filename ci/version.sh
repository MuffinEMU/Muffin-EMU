#!/bin/sh
# The first MuffinEMU release number, and the version stamped into test builds.
#
# Releases are numbered by CI, not by hand. Every build of main publishes the next
# version: the highest vX.Y tag plus 0.1, with .9 rolling over to the next whole number
# (1.9 -> 2.0). That is the rule the owner set. This file only supplies the number used
# when no vX.Y tag exists yet, and the version stamped into builds of other branches.
# See "Choose the version" in .github/workflows/build-ios-app.yml.
#
# Tags always have a single-digit minor (v1.0 ... v1.9, v2.0), so the arithmetic never
# has to guess what a tag means. Guessing is what broke Muffin's old flat tags (v47,
# v138).
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
