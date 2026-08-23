#!/bin/bash
# Places a pristine second copy of the app executable inside the bundle, at the exact
# path LiveContainer uses for its own patch backup.
#
# Usage: ci/stage-livecontainer-spare.sh <path-to-Foo.app>
#
# ---------------------------------------------------------------------------------
# THE BUG THIS DEFENDS AGAINST (in LiveContainer, not in us)
#
# LiveContainer patches an app's Mach-O on install and after its own patch revision
# bumps. LiveContainerSwiftUI/Models/LCAppInfo.m, patchExecAndSignIfNeed:
#
#     int currentPatchRev = 7;
#     bool needPatch = [info[@"LCPatchRevision"] intValue] < currentPatchRev;
#     if (needPatch || forceSign) {
#         // copy-delete-move to avoid EXC_BAD_ACCESS (SIGKILL - CODESIGNING)
#         NSString *backupPath = [NSString stringWithFormat:@"%@/%@_LiveContainerPatchBackUp",
#                                 appPath, _infoPlist[@"CFBundleExecutable"]];
#         NSError *err;
#         [fm copyItemAtPath:execPath toPath:backupPath error:&err];
#         [fm removeItemAtPath:execPath error:&err];
#         [fm moveItemAtPath:backupPath toPath:execPath error:&err];
#     }
#
# Three filesystem calls, one shared `err`, and not one of them is checked. If the
# copy fails, the remove runs regardless and the move then has no source. The app's
# executable is destroyed, permanently, and every later launch reports:
#
#     App's executable path not found. Please try force re-signing or reinstalling
#     this app.                                    (LCBootstrap.m, executablePath nil)
#
# The advice in that message is wrong for this failure - there is no binary left to
# re-sign - and "force re-sign" sets forceSign=YES, which runs the same destructive
# three lines again.
#
# THE FIX
#
# We cannot patch LiveContainer. We can make its sequence safe by construction:
# ship the backup file already in place, byte-identical to the executable.
#
#     copy   -> fails, NSFileWriteFileExistsError (destination exists). Harmless:
#               the destination already holds exactly the bytes the copy would
#               have written.
#     remove -> deletes the executable, as before.
#     move   -> renames OUR pristine spare into place as the executable.
#
# The outcome is identical to a healthy run, and it no longer depends on the copy
# succeeding. Whatever made the copy fail - low storage, an I/O error, an install
# interrupted midway - stops being able to destroy the binary.
#
# Cost: +5.9 MB in the IPA, +17 MB extracted on device (Cemu compresses to ~36%).
#
# LIMITS - be honest about these:
#   * It protects one patch cycle. After the move consumes the spare, a later patch
#     (LiveContainer bumping currentPatchRev, or the user tapping force re-sign) is
#     back on the fragile path.
#   * If a future LiveContainer checks that copy's error and bails, our pre-staged
#     spare turns a silent brick into a clean failure - it bails BEFORE the remove,
#     so the executable survives either way.
#   * It does nothing for SideStore/AltStore, which do not run this code. It is
#     inert weight there.
set -euo pipefail

APP="${1:?usage: stage-livecontainer-spare.sh <path-to-Foo.app>}"
[ -d "$APP" ] || { echo "error: not a directory: $APP" >&2; exit 1; }

PLIST="$APP/Info.plist"
[ -f "$PLIST" ] || { echo "error: no Info.plist in $APP" >&2; exit 1; }

EXEC_NAME="$(plutil -extract CFBundleExecutable raw -o - "$PLIST")"
EXEC="$APP/$EXEC_NAME"
[ -f "$EXEC" ] || { echo "error: executable not found: $EXEC" >&2; exit 1; }

# The name is not ours to choose - it is the format string above, verbatim. If
# LiveContainer ever renames it, this file becomes inert weight rather than a hazard,
# and ci/verify-ipa.sh will still confirm the real executable is intact.
SPARE="$APP/${EXEC_NAME}_LiveContainerPatchBackUp"

cp "$EXEC" "$SPARE"
# Match the executable's mode. The move makes this file the executable, so if the
# exec bit were missing the restored app would not launch.
chmod --reference="$EXEC" "$SPARE" 2>/dev/null || chmod "$(stat -f '%Lp' "$EXEC")" "$SPARE"

if ! cmp -s "$EXEC" "$SPARE"; then
    echo "error: staged spare differs from executable" >&2
    exit 1
fi

echo "stage-livecontainer-spare.sh: $(basename "$SPARE") staged, $(du -h "$SPARE" | cut -f1), mode $(stat -f '%Sp' "$SPARE")"
