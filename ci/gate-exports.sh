#!/bin/bash
# Gate: every function Swift can call is in the framework, and the framework is an arm64 iOS
# library. Runs against a freshly built core and against a cached one alike, so a core that is
# reused is held to exactly the standard of one that was just compiled.
#
# Usage: ci/gate-exports.sh [path/to/Cemu.framework]   (default build-ios/out/Cemu.framework)
set -eo pipefail
cd "$(dirname "$0")/.."
FW="${1:-build-ios/out/Cemu.framework}"
BIN="$FW/Cemu"
[ -f "$BIN" ] || { echo "::error::no framework binary at $BIN"; exit 1; }

# A declared-but-undefined bridge function otherwise only shows up as a linker error deep inside
# xcodebuild. POSIX classes, not \s: the runner's BSD sed reads \s as a literal "s", which stripped
# the last letter off every name ending in s (get_fps -> get_fp) and reported ten exported
# functions as missing.
grep -hoE '(cemu_bridge|ios_live_log)_[a-z0-9_]+[[:space:]]*\(' src/ios/Bridge/CemuBridge.h src/ios/Bridge/IOSLiveLog.h \
  | sed -E 's/[[:space:]]*\($//' | sort -u > declared.txt
nm -gU "$BIN" | grep -oE '_(cemu_bridge|ios_live_log)_[a-z0-9_]+$' \
  | sed 's/^_//' | sort -u > defined.txt
MISSING=$(comm -23 declared.txt defined.txt)
if [ -n "$MISSING" ]; then
  echo "::error::declared in the bridge headers but not exported by Cemu.framework:"
  echo "$MISSING"
  exit 1
fi
echo "all $(wc -l < declared.txt | tr -d ' ') bridge functions are exported"

ARCHS=$(lipo -archs "$BIN")
if [ "$ARCHS" != "arm64" ]; then
  echo "::error::Cemu.framework is [$ARCHS], expected exactly arm64"
  exit 1
fi
PLATFORM=$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/{f=1} f && /platform/{print $2; exit}')
case "$PLATFORM" in
  2|IOS) echo "Cemu.framework is an arm64 iOS library" ;;
  "")    echo "::warning::could not read the platform of Cemu.framework; arm64 was checked" ;;
  *)     echo "::error::Cemu.framework targets platform '$PLATFORM', not iOS"; exit 1 ;;
esac
