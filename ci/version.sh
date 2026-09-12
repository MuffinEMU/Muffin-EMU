#!/bin/sh
# The single source of truth for the version this line ships.
#
# WHY A FILE AND NOT ARITHMETIC ON THE TAG: the previous scheme derived the
# version by splitting a flat tag number into major.minor (v47 -> 4.7), and it
# broke in three separate ways that each cost a release to notice.
#
#   * v47 shipped to a device reporting its version as "47", as though this were
#     a mature product on its forty-seventh major release.
#   * The fix for that handled dotted tags in Python but not in the shell, so a
#     build tagged v4.8 stamped itself "0.4" - the owner caught it in a screenshot.
#   * The rule is genuinely ambiguous for three digits. This repository contains a
#     v138 tag, which the arithmetic reads as 13.8 and which actually means 1.38,
#     from the DOTTED scheme that came first. No amount of care in the sed makes
#     that decidable.
#
# A tag is a label. It is not a number to do sums on. The version lives in
# ci/VERSION, is bumped by hand, and CI refuses to publish when a dotted tag
# disagrees with it - so the two cannot drift the way the tag and the binary did
# when v4.9 shipped an IPA three commits older than its own tag.
#
# It lives in ci/ and NOT at the repository root, which matters more than it looks:
# macOS is case-insensitive, the compiler is invoked with -I . , and C++20 has a
# standard header called <version>. A root-level VERSION file is found by
# #include <version> and shadows it - which took the CPU-core type-check from
# 31/31 clean to 0/31 with errors pointing inside libc++, and would have done the
# same to the real build.
#
# The rule the owner set: every release goes up by 0.1.
set -eu
cd "$(dirname "$0")/.."
VER=$(tr -d ' \t\n\r' < ci/VERSION)
case "$VER" in
  [0-9]*.[0-9]*) ;;
  *) echo "ci/VERSION must be major.minor, got '$VER'" >&2; exit 1 ;;
esac
echo "$VER"
