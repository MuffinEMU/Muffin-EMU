#!/bin/bash
# Structural verification of a packaged IPA. Run in CI immediately after the zip is
# created and BEFORE anything uploads or publishes it, so a structurally broken IPA
# can never reach a Release.
#
# Usage: ci/verify-ipa.sh <path-to-ipa>
#
# Why this exists: on 2026-08-23 a v1.15 install failed on device with
# "App's executable path not found. Please try force re-signing or reinstalling this
# app." That string is LiveContainer's, from LCBootstrap.m, and it fires when
# NSBundle cannot resolve CFBundleExecutable inside LiveContainer's OWN copy of the
# app - i.e. it describes the state of the app on the device, not the state of the
# IPA. Answering "is the IPA actually fine?" took a manual unpack and a pass with
# otool. That answer should be a build artifact, not an investigation. Every check
# below is one that was performed by hand that day.
#
# These checks are all cheap and all structural. None of them can tell you the
# emulator works; they tell you the package is a well-formed, installable, unsigned
# arm64 iOS app, which is precisely the class of doubt that cost a day.
set -euo pipefail

IPA="${1:?usage: verify-ipa.sh <path-to-ipa>}"
[ -f "$IPA" ] || { echo "error: no such file: $IPA" >&2; exit 1; }

fail() { echo "verify-ipa: FAIL: $*" >&2; exit 1; }
ok()   { echo "verify-ipa: ok   - $*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# -Z is zipinfo mode: it reports the stored unix mode bits and entry type, which a
# plain extract-then-stat would lose on a filesystem that does not preserve them.
unzip -Z "$IPA" > "$WORK/zipinfo.txt" || fail "cannot read zip central directory"
unzip -Z1 "$IPA" > "$WORK/names.txt"

# --- 1. nothing outside Payload/ -------------------------------------------------
# An installer only looks at Payload/. Anything else is either junk that inflates the
# download (__MACOSX/, .DS_Store) or something that should not be shipped at all.
if grep -v '^Payload/' "$WORK/names.txt" > "$WORK/stray.txt" && [ -s "$WORK/stray.txt" ]; then
    fail "entries outside Payload/: $(tr '\n' ' ' < "$WORK/stray.txt")"
fi
ok "no entries outside Payload/"

# --- 2. exactly one .app ---------------------------------------------------------
# BSD sed has no \?, so match the trailing slash plus anything after it - that covers
# both the bare directory entry and every file nested under it.
APP_NAME="$(sed -n 's|^Payload/\([^/][^/]*\.app\)/.*|\1|p' "$WORK/names.txt" | sort -u)"
[ "$(printf '%s\n' "$APP_NAME" | grep -c .)" -eq 1 ] \
    || fail "expected exactly one Payload/*.app, got: $(printf '%s ' $APP_NAME)"
ok "single app bundle: $APP_NAME"

# --- 3. no symlinks --------------------------------------------------------------
# zipinfo renders the entry type as the first character of the mode string. A symlink
# in an unsigned IPA is both a signing hazard and a way for the executable to be a
# dangling pointer that only breaks on device.
if awk '$1 ~ /^l/ {print $NF}' "$WORK/zipinfo.txt" | grep . > "$WORK/links.txt"; then
    fail "symlinks present: $(tr '\n' ' ' < "$WORK/links.txt")"
fi
ok "no symlinks"

# --- 4. no case-insensitive collisions -------------------------------------------
# iOS's filesystem is case-insensitive. Two entries differing only in case extract
# over each other, and which one survives is a function of zip order - so a build can
# be correct on the case-insensitive macOS runner and lose a file on device. Cemu's
# gameProfiles are named by title ID in mixed hex case, which is exactly the shape
# that produces this.
if tr 'A-Z' 'a-z' < "$WORK/names.txt" | sort | uniq -d > "$WORK/dupes.txt" && [ -s "$WORK/dupes.txt" ]; then
    fail "case-insensitive collisions: $(tr '\n' ' ' < "$WORK/dupes.txt")"
fi
ok "no case-insensitive collisions"

# --- 5. Info.plist declares an executable ----------------------------------------
unzip -q -o "$IPA" "Payload/$APP_NAME/Info.plist" -d "$WORK" || fail "no Info.plist"
PLIST="$WORK/Payload/$APP_NAME/Info.plist"
plutil -lint "$PLIST" >/dev/null || fail "Info.plist does not parse"
EXEC_NAME="$(plutil -extract CFBundleExecutable raw -o - "$PLIST" 2>/dev/null)" \
    || fail "Info.plist has no CFBundleExecutable"
[ -n "$EXEC_NAME" ] || fail "CFBundleExecutable is empty"
ok "CFBundleExecutable = $EXEC_NAME"

# --- 6. that executable is actually in the zip -----------------------------------
# This is the check that maps directly to the reported error: LiveContainer resolves
# CFBundleExecutable against the bundle and gets nil when the named file is absent.
EXEC_ENTRY="Payload/$APP_NAME/$EXEC_NAME"
grep -qxF "$EXEC_ENTRY" "$WORK/names.txt" || fail "executable missing from IPA: $EXEC_ENTRY"
ok "executable present at $EXEC_ENTRY"

# --- 7. the exec bit survived the zip --------------------------------------------
# zip stores unix modes in the external attributes; some packaging paths drop them,
# and a non-executable Mach-O fails at exec time with a message that blames the app.
EXEC_MODE="$(awk -v e="$EXEC_ENTRY" '$NF == e {print $1}' "$WORK/zipinfo.txt")"
[ -n "$EXEC_MODE" ] || fail "could not read stored mode for $EXEC_ENTRY"
case "$EXEC_MODE" in
    -*x*) ok "exec bit set in archive ($EXEC_MODE)" ;;
    *)    fail "exec bit NOT set on $EXEC_ENTRY (mode $EXEC_MODE)" ;;
esac

# --- 8-10. Mach-O shape ----------------------------------------------------------
unzip -q -o "$IPA" "$EXEC_ENTRY" -d "$WORK"
BIN="$WORK/$EXEC_ENTRY"

# -hv prints the header symbolically: cputype and filetype as names rather than the
# raw constants, so this stays readable when it fails.
HDR="$(otool -hv "$BIN" | tail -n +3)"
grep -q 'ARM64' <<<"$HDR"   || fail "not an arm64 binary: $HDR"
grep -q 'EXECUTE' <<<"$HDR" || fail "not MH_EXECUTE (a dylib or bundle will not launch): $HDR"
ok "Mach-O arm64 MH_EXECUTE"

# LC_MAIN is the entry point. A binary without one has no way in; LiveContainer will
# load it and then have nothing to call.
otool -l "$BIN" | grep -q 'LC_MAIN' || fail "no LC_MAIN load command (no entry point)"
ok "LC_MAIN present"

# cryptid != 0 means an App Store-encrypted binary, which cannot be re-signed and
# will be rejected outright by LiveContainer with its own encryption error.
CRYPTID="$(otool -l "$BIN" | awk '/LC_ENCRYPTION_INFO/{f=1} f && /cryptid/{print $2; exit}')"
if [ -n "${CRYPTID:-}" ] && [ "$CRYPTID" != "0" ]; then
    fail "binary is encrypted (cryptid=$CRYPTID)"
fi
ok "not encrypted (cryptid=${CRYPTID:-absent})"

# --- 11. the LiveContainer spare ------------------------------------------------
# See ci/stage-livecontainer-spare.sh for why this file exists. It is only useful if
# it is byte-identical to the executable, because LiveContainer may rename it into
# place as the executable without ever comparing the two.
SPARE_ENTRY="Payload/$APP_NAME/${EXEC_NAME}_LiveContainerPatchBackUp"
if grep -qxF "$SPARE_ENTRY" "$WORK/names.txt"; then
    unzip -q -o "$IPA" "$SPARE_ENTRY" -d "$WORK"
    if [ "$(shasum -a 256 < "$BIN" | cut -d' ' -f1)" \
       = "$(shasum -a 256 < "$WORK/$SPARE_ENTRY" | cut -d' ' -f1)" ]; then
        ok "LiveContainer spare present and byte-identical"
    else
        fail "LiveContainer spare differs from the executable - renaming it into place would install the wrong binary"
    fi
else
    echo "verify-ipa: warn - no LiveContainer spare (stage-livecontainer-spare.sh did not run)" >&2
fi

echo "verify-ipa: PASS  $(basename "$IPA") ($(du -h "$IPA" | cut -f1))"
