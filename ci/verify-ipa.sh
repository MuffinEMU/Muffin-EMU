#!/bin/bash
# Structural verification of a packaged IPA. Run in CI immediately after the zip is
# created and BEFORE anything uploads or publishes it, so a structurally broken IPA
# can never reach a Release.
#
# Usage: ci/verify-ipa.sh <path-to-ipa>
#
# Why this exists: on 2026-08-23 a v1.15 install failed on device with
# "App's executable path not found. Please try force re-signing or reinstalling this
# app." That string is LiveContainer's, from LCBootstrap.m, and it fires when NSBundle
# returns nil for -executablePath. The cause turned out to be ours: the bundle carried
# a directory named `resources` at its top level, iOS filesystems are case-insensitive,
# and CFBundle's probe for the reserved `Resources` directory matched it. CFBundle then
# looked for Info.plist inside that directory instead of at the top level, found none,
# and handed back a bundle with a nil identifier, a nil CFBundleExecutable and a nil
# executable path - every file present, none of them reachable.
#
# The lesson for this script is check 12. Checks 1-11 are structural, cheap, and were
# all performed by hand that day - and every single one of them PASSES on the broken
# v1.15 IPA. otool cannot see this bug. Only asking CFBundle can, so the gate ends by
# asking CFBundle.
#
# None of these can tell you the emulator works; together they tell you the package is
# a well-formed, installable, unsigned arm64 iOS app that CFBundle can actually read,
# which is precisely the class of doubt that cost a day.
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

# --- 11. no CFBundle-reserved name at the top level of the bundle ----------------
# CFBundle decides what KIND of bundle it is looking at by probing for these
# directories, and on a case-insensitive filesystem any casing of them matches. A flat
# iOS bundle that happens to contain one gets reclassified, after which CFBundle looks
# for Info.plist somewhere it is not. That is the v1.14/v1.15 bug, and `resources` -
# the name Cemu's own GetDataPath() callers use - is on this list.
#
# Only the top level matters: nested copies are invisible to this probe, which is why
# the data files now live under Cemu.app/CemuData/resources/sharedFonts and this check
# passes.
RESERVED='Contents|Resources|Support Files|MacOS|Frameworks|PlugIns|SharedFrameworks|SharedSupport|Versions'
TOP_LEVEL="$(sed -n "s|^Payload/$APP_NAME/\([^/][^/]*\)/.*|\1|p" "$WORK/names.txt" | sort -u)"
while IFS= read -r d; do
    [ -n "$d" ] || continue
    if printf '%s\n' "$d" | grep -Eiqx "$RESERVED"; then
        fail "reserved CFBundle directory name at the bundle root: $d (case-insensitively matches one of: $RESERVED). This makes CFBundle misread the bundle - see check 12."
    fi
done <<< "$TOP_LEVEL"
ok "no CFBundle-reserved directory at the bundle root"

# --- 12. CFBundle can actually read the bundle -----------------------------------
# The one check that would have caught the shipped bug. Everything above passes on the
# broken v1.15 IPA; this does not. Extract the whole bundle and ask a real NSBundle -
# same CoreFoundation code path the device runs, and the same one LiveContainer's
# LCBootstrap.m uses when it reports "App's executable path not found".
#
# macOS reads flat iOS bundles with the same CFBundle implementation, and the failure
# reproduces here identically, so this is a genuine test and not an approximation.
unzip -q -o "$IPA" "Payload/$APP_NAME/*" -d "$WORK/full" || fail "could not extract bundle for the CFBundle check"

cat > "$WORK/bundleprobe.m" <<'PROBE'
#import <Foundation/Foundation.h>
// Exits non-zero and says which one is missing, so a failure names the problem rather
// than just reporting a mismatch.
int main(int argc, char **argv) {
    @autoreleasepool {
        NSBundle *b = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        if (!b) { fprintf(stderr, "NSBundle could not open the bundle at all\n"); return 1; }
        NSString *ident = b.bundleIdentifier;
        NSString *exec  = b.infoDictionary[@"CFBundleExecutable"];
        NSString *path  = b.executablePath;
        int bad = 0;
        if (!ident) { fprintf(stderr, "bundleIdentifier is nil\n"); bad = 1; }
        if (!exec)  { fprintf(stderr, "CFBundleExecutable is nil\n"); bad = 1; }
        if (!path)  { fprintf(stderr, "executablePath is nil\n"); bad = 1; }
        if (bad) {
            fprintf(stderr, "CFBundle read %lu Info.plist key(s) - an empty or tiny count means it "
                            "looked for Info.plist somewhere other than the bundle root\n",
                    (unsigned long)b.infoDictionary.count);
            return 1;
        }
        printf("%s|%s|%s\n", ident.UTF8String, exec.UTF8String, path.lastPathComponent.UTF8String);
    }
    return 0;
}
PROBE
clang -fobjc-arc -framework Foundation -o "$WORK/bundleprobe" "$WORK/bundleprobe.m" \
    || fail "could not build the CFBundle probe"

PROBE_OUT="$("$WORK/bundleprobe" "$WORK/full/Payload/$APP_NAME")" \
    || fail "CFBundle cannot resolve the packaged bundle - this is the v1.14/v1.15 failure. LiveContainer will install it and then refuse to launch it with \"App's executable path not found\"."
ok "CFBundle resolves the bundle (identifier|executable|binary = $PROBE_OUT)"

# Belt and braces: what CFBundle resolved must be the executable we checked above, not
# a name-based fallback that happens to land somewhere plausible.
PROBE_EXEC="$(printf '%s' "$PROBE_OUT" | cut -d'|' -f2)"
[ "$PROBE_EXEC" = "$EXEC_NAME" ] \
    || fail "CFBundle resolved CFBundleExecutable as '$PROBE_EXEC' but Info.plist says '$EXEC_NAME'"
ok "CFBundle's executable name matches Info.plist"

echo "verify-ipa: PASS  $(basename "$IPA") ($(du -h "$IPA" | cut -f1))"
