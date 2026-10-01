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
# Every header src/ios/Bridge/Cemu-Bridging-Header.h hands to Swift, not only the first two: the device
# capability, motion and graphic-pack APIs added in 6.x are called from the app too (muffin_gp_*,
# cemu_device_caps_*; the motion functions are cemu_bridge_*).
grep -hoE '(cemu_bridge|ios_live_log|cemu_device_caps|muffin_gp)_[a-z0-9_]+[[:space:]]*\(' \
  src/ios/Bridge/CemuBridge.h src/ios/Bridge/IOSLiveLog.h src/ios/Bridge/IOSMotion.h \
  src/ios/Bridge/IOSGraphicPackBridge.h src/ios/Bridge/CemuDeviceCaps.h \
  | sed -E 's/[[:space:]]*\($//' | sort -u > declared.txt
nm -gU "$BIN" | grep -oE '_(cemu_bridge|ios_live_log|cemu_device_caps|muffin_gp)_[a-z0-9_]+$' \
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

# The Audit hooks (src/ios/Bridge/IOSAudit*, tools/audit-app) belong to the audit workflow's own core, built
# with -DMUFFIN_AUDIT_HOOKS=ON, and nowhere else. Nothing in a shipping build sets that flag, so this
# should never fire; it is here because a core that carried them would be shipped, cached and reused
# without anything else noticing (the flag is not part of what the declared-function check above reads).
# A plain byte search, so it catches symbol names, log strings and a renamed symbol table alike.
if LC_ALL=C grep -aqE 'cemu_audit_|IOSAudit|MUFFIN_AUDIT' "$BIN"; then
  echo "::error::Cemu.framework contains the Audit hooks (cemu_audit_*, MUFFIN_AUDIT_HOOKS). A shipping core must not."
  exit 1
fi
echo "Cemu.framework carries no Audit hooks"
