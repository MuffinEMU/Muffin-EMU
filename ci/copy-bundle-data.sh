#!/bin/bash
# Copies Cemu's own data files into the built app bundle. Run as an Xcode
# postBuildScript (see src/ios/project.yml), after the resource-copy phase has
# already put src/ios/Resources in place.
#
# Why this exists: project.yml's `sources:` list only ever named directories under
# src/ios, so nothing under bin/ reached Cemu.app even though both trees are in the
# repo. Two things were missing on device, and both showed up in the first successful
# boot log (see STATUS.md):
#
#   * bin/resources/sharedFonts - CafeSystem::LoadSharedData() looks for these at
#     ActiveSettings::GetDataPath("resources/sharedFonts/<name>.ttf") and, finding
#     neither them nor a dumped MLC copy, logs "Shared font CafeCn.ttf is not
#     present" and installs a stub shared-data region instead.
#   * bin/gameProfiles - GameProfile::Load() falls back to
#     ActiveSettings::GetDataPath("gameProfiles/default/<titleid>.ini") when the user
#     has no profile of their own. With the directory absent, every per-title
#     workaround silently resolves to the built-in default. That includes the
#     position-invariance setting MetalRenderer::ResolvePositionInvariance() reads at
#     Initialize() for BOTW, Mario Kart 8 and others - i.e. this is a rendering
#     correctness problem, not only a compatibility one.
#
# The layout below is dictated by those two GetDataPath() calls, which hardcode the
# "resources/" and "gameProfiles/" prefixes. That relative layout is preserved exactly,
# but under a "CemuData" subdirectory rather than at the top level of the bundle, and
# CemuBridge.mm points ActiveSettings' data path at that subdirectory to match.
#
# The nesting is not tidiness, it is the fix for the bug that broke v1.14 and v1.15.
# Staging straight into the bundle put a directory literally named `resources` at the
# top level of Cemu.app. iOS filesystems are case-insensitive, so CFBundle's probe for
# the reserved `Resources` directory matched it, reclassified the bundle from flat to
# Resources-style, and then looked for Info.plist inside that directory instead of at
# the top level where ours is. The result is a bundle with every file present and
# intact for which -bundleIdentifier, -infoDictionary and -executablePath are all nil.
# Under LiveContainer that installs fine (it reads Info.plist off disk directly) and
# then fails at launch with "App's executable path not found. Please try force
# re-signing or reinstalling this app." - which is what Void hit on device.
#
# So: nothing at the top level of the bundle may carry a name CFBundle reserves.
# ci/verify-ipa.sh enforces that, and also asserts a real NSBundle can resolve the
# packaged bundle, so this cannot silently return.
#
# Deliberately NOT copied: bin/resources/<lang>/ (the ~1.1 MB of wxWidgets .mo
# translation catalogs). Their only reader is CemuApp.cpp's
# wxFileTranslationsLoader, and the whole wx GUI is excluded from the iOS target, so
# they would be dead weight in the IPA.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_FONTS="$REPO_ROOT/bin/resources/sharedFonts"
SRC_PROFILES="$REPO_ROOT/bin/gameProfiles"

# UNLOCALIZED_RESOURCES_FOLDER_PATH is "Cemu.app" on iOS (it is Contents/Resources
# only on macOS). Taking it from the environment rather than hardcoding the name
# keeps this correct if PRODUCT_NAME ever changes.
DEST="${BUILT_PRODUCTS_DIR:?not running inside an Xcode build}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"

# Fail loudly rather than producing an app that silently has no fonts again - a
# missing source tree here is a broken checkout (bin/ is tracked in git, 259 files),
# not a condition to shrug at.
for d in "$SRC_FONTS" "$SRC_PROFILES"; do
    if [ ! -d "$d" ]; then
        echo "error: copy-bundle-data.sh: required data directory not found: $d" >&2
        exit 1
    fi
done

DATA_ROOT="$DEST/CemuData"
mkdir -p "$DATA_ROOT/resources"
rsync -a --delete "$SRC_FONTS/" "$DATA_ROOT/resources/sharedFonts/"
rsync -a --delete "$SRC_PROFILES/" "$DATA_ROOT/gameProfiles/"

# Clean up the pre-CemuData layout if an incremental build left it behind. Without
# this an existing DerivedData tree keeps the top-level `resources` directory that
# caused the bug, and a local rebuild would reproduce it while a clean CI build did
# not - the worst kind of difference to debug.
rm -rf "$DEST/resources" "$DEST/gameProfiles"

echo "copy-bundle-data.sh: $(find "$DATA_ROOT/resources/sharedFonts" -type f | wc -l | tr -d ' ') shared font(s), $(find "$DATA_ROOT/gameProfiles" -type f | wc -l | tr -d ' ') game profile(s) -> $DATA_ROOT"
