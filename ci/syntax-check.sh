#!/bin/sh
# Fast local type-check for the Espresso CPU core.
#
# WHY: the real build needs vcpkg (boost, fmt, ...) which CI has and a laptop usually does
# not, so without this the only signal that a recompiler edit compiles is a ~25 minute CI
# run. That is far too slow to edit a JIT against. ci/syntax-stubs/ supplies just enough
# fake boost/fmt for the compiler to get through the headers.
#
# WHAT IT IS NOT: proof the build is green. The stubs implement signatures, not semantics,
# and nothing here links or runs. CI is still the authority. Treat a pass as "I did not
# break the parse or the types", which is exactly the mistake this catches cheaply.
#
# Usage:  ci/syntax-check.sh [file.cpp ...]     (default: the whole Espresso CPU core)
set -u
cd "$(dirname "$0")/.." || exit 2
STUBS=ci/syntax-stubs
INCS="-I $STUBS -I src -I src/Cafe -I src/Common -I dependencies/xbyak_aarch64/xbyak_aarch64 -I ."
FLAGS="-fsyntax-only -std=c++20 -arch arm64 -DARCH_ARM64 -DCEMU_PLATFORM_IOS -Wno-everything -include src/Common/precompiled.h"

if [ "$#" -gt 0 ]; then FILES="$*"; else
  FILES=$(find src/Cafe/HW/Espresso -name '*.cpp' | sort)
fi

fail=0; n=0
for f in $FILES; do
  n=$((n+1))
  out=$(clang++ $FLAGS $INCS "$f" 2>&1)
  if [ -n "$out" ]; then
    echo "FAIL $f"
    echo "$out" | grep -E 'error:' | head -8 | sed 's/^/     /'
    fail=$((fail+1))
  else
    echo "ok   $f"
  fi
done
echo "---"
echo "$((n-fail))/$n clean"
[ "$fail" -eq 0 ] || exit 1
