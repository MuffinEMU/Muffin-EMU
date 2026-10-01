#!/bin/bash
# Turns one built MuffinEMU.app into the two IPAs a release ships, stamping the build name and
# version on the way:
#
#   MuffinEMU.ipa             ad-hoc signed with Sideload.entitlements (get-task-allow only), for
#                             SideStore / AltStore / LiveContainer, which re-sign it
#   MuffinEMU-fakesigned.ipa  ad-hoc signed with the full Cemu.entitlements, for TrollStore and
#                             jailbroken installs that do not re-sign
#
# Usage: ci/package-ipas.sh PATH/TO/MuffinEMU.app   (run from where the IPAs should land)
# Needs MUFFIN_LABEL, MUFFIN_VERSION and GITHUB_RUN_NUMBER (set by "Choose the version"), and takes
# MUFFIN_RELEASE_COMMIT and MUFFIN_CORE_FP (7 characters each) for the launch log line.
#
# The input may be a fresh unsigned build or an app unzipped from an IPA an earlier run already
# built. That is what lets a release reuse a pull request's build: the version stamp is an
# Info.plist edit, the plist is covered by the code signature, so the app is re-signed after it and
# nothing about the compiled code is touched. Any earlier signature is discarded first, so the two
# inputs end up in the same state.
set -eo pipefail

BASE_APP="${1:?usage: package-ipas.sh PATH/TO/MuffinEMU.app}"
: "${MUFFIN_LABEL:?}" "${MUFFIN_VERSION:?}" "${GITHUB_RUN_NUMBER:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PWD"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pb() { /usr/libexec/PlistBuddy "$@"; }

rm -rf "$OUT/MuffinEMU.ipa" "$OUT/MuffinEMU-fakesigned.ipa"

# Stamp a private copy. LiveContainer and SideStore tell builds apart by name and version.
# CFBundleIdentifier is not touched: it keys the app's data container.
mkdir -p "$WORK/stamped"
cp -R "$BASE_APP" "$WORK/stamped/MuffinEMU.app"
APP="$WORK/stamped/MuffinEMU.app"
find "$APP" -name _CodeSignature -type d -prune -exec rm -rf {} +
PL="$APP/Info.plist"
pb -c "Set :CFBundleDisplayName MuffinEMU $MUFFIN_LABEL" "$PL" 2>/dev/null \
  || pb -c "Add :CFBundleDisplayName string MuffinEMU $MUFFIN_LABEL" "$PL"
pb -c "Set :CFBundleShortVersionString $MUFFIN_VERSION" "$PL" 2>/dev/null \
  || pb -c "Add :CFBundleShortVersionString string $MUFFIN_VERSION" "$PL"
pb -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER}" "$PL" 2>/dev/null \
  || pb -c "Add :CFBundleVersion string ${GITHUB_RUN_NUMBER}" "$PL"
# Which release and which core this is, for the launch log line (src/ios/App/CemuApp.swift). Custom
# keys, so nothing that identifies the app to iOS changes.
pb -c "Set :MuffinReleaseCommit ${MUFFIN_RELEASE_COMMIT:-unstamped}" "$PL" 2>/dev/null \
  || pb -c "Add :MuffinReleaseCommit string ${MUFFIN_RELEASE_COMMIT:-unstamped}" "$PL"
pb -c "Set :MuffinCoreFingerprint ${MUFFIN_CORE_FP:-unstamped}" "$PL" 2>/dev/null \
  || pb -c "Add :MuffinCoreFingerprint string ${MUFFIN_CORE_FP:-unstamped}" "$PL"
echo "stamped display name: $(pb -c 'Print :CFBundleDisplayName' "$PL")"
echo "stamped version:      $(pb -c 'Print :CFBundleShortVersionString' "$PL")"
echo "stamped build:        $(pb -c 'Print :CFBundleVersion' "$PL")"
ls "$APP/Frameworks"

# sign_and_zip VARIANT_DIR ENTITLEMENTS_FILE OUTPUT_IPA
# Frameworks first: a signed app containing unsigned frameworks does not load. An IPA is a zip
# whose top-level entry is Payload/ - zipping the app directly produces an archive every
# installer rejects.
sign_and_zip() {
  local dir="$1" ents="$2" ipa="$3"
  mkdir -p "$dir/Payload"
  cp -R "$APP" "$dir/Payload/MuffinEMU.app"
  local fw
  for fw in "$dir"/Payload/MuffinEMU.app/Frameworks/*.framework; do
    codesign -f -s - "$fw"
  done
  codesign -f -s - --entitlements "$ents" --generate-entitlement-der "$dir/Payload/MuffinEMU.app"
  ( cd "$dir" && zip -qry "$ipa" Payload )
}

# --- MuffinEMU.ipa: minimal entitlements. Without an entitlements dict, JIT enablers cannot list
# the app. Only get-task-allow - see src/ios/Sideload.entitlements for why reusing Cemu.entitlements
# here would make things worse rather than better.
sign_and_zip "$WORK/sideload" "$ROOT/src/ios/Sideload.entitlements" "$OUT/MuffinEMU.ipa"
# Verified, not assumed. Shipping this without get-task-allow would reproduce exactly the bug it
# exists to fix, and it would look identical from outside. increased-memory-limit is carried
# deliberately but is allowed to be dropped by a re-signer, so it is reported rather than required -
# only get-task-allow decides whether a JIT enabler can see the app.
codesign -d --entitlements - --xml "$WORK/sideload/Payload/MuffinEMU.app" 2>/dev/null \
  | python3 -c "import sys,plistlib; d=sys.stdin.buffer.read(); i=d.find(b'<?xml'); print('embedded entitlements:', ', '.join(sorted(plistlib.loads(d[i:]))) if i>=0 else '(none)')"
if ! codesign -d --entitlements - --xml "$WORK/sideload/Payload/MuffinEMU.app" 2>/dev/null \
     | python3 -c "import sys,plistlib; d=sys.stdin.buffer.read(); i=d.find(b'<?xml'); sys.exit(0 if i>=0 and plistlib.loads(d[i:]).get('get-task-allow') is True else 1)"; then
  echo "::error::MuffinEMU.ipa was signed without get-task-allow - JIT enablers would not see it"
  exit 1
fi
echo "IPA size: $(du -h "$OUT/MuffinEMU.ipa" | cut -f1)"

# --- MuffinEMU-fakesigned.ipa: the plain IPA carries no entitlements of its own; entitlements only
# exist inside a signature. This variant embeds the full set for install paths that do not re-sign.
sign_and_zip "$WORK/fakesigned" "$ROOT/src/ios/Cemu.entitlements" "$OUT/MuffinEMU-fakesigned.ipa"
COUNT=$(codesign -d --entitlements - --xml "$WORK/fakesigned/Payload/MuffinEMU.app" 2>/dev/null \
  | python3 -c "import sys,plistlib; d=sys.stdin.buffer.read(); i=d.find(b'<?xml'); print(0 if i<0 else len(plistlib.loads(d[i:])))")
echo "embedded entitlements: $COUNT"
if [ "$COUNT" -lt 4 ]; then
  echo "::error::ad-hoc signing embedded $COUNT entitlements, expected at least 4"
  exit 1
fi
echo "fake-signed IPA size: $(du -h "$OUT/MuffinEMU-fakesigned.ipa" | cut -f1)"
