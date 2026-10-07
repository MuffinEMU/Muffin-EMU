#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Publishes an experimental build: one "Experimental: ..." pre-release per build, and the rolling
# `experimental` release that always points at the newest of them. Neither is ever referenced by the
# Stable or Nightly install sources; the Experimental source (docs/experimental*.json) lists only the
# per-build releases, never the rolling one.
#
# Fails the job if called for anything but an experimental dispatch on a branch other than main.
#
# Environment: EVENT REF REF_NAME SHA CHANNEL TAG TITLE SHORT_NAME GITHUB_REPOSITORY, files in $PWD
# (MuffinEMU.ipa, MuffinEMU-fakesigned.ipa, MuffinEMU.app.dSYM.zip). DRY_RUN=1 prints the writes.
set -eo pipefail
cd "$(dirname "$0")/.."
. ci/lib-release.sh

EVENT="${EVENT:?}"; REF="${REF:?}"; REF_NAME="${REF_NAME:?}"; SHA="${SHA:?}"; CHANNEL="${CHANNEL:?}"
TAG="${TAG:?}"; TITLE="${TITLE:?}"; SHORT_NAME="${SHORT_NAME:?}"
die() { echo "::error::Experimental guard: $1"; exit 1; }

[ "$CHANNEL" = "experimental" ]       || die "channel is '$CHANNEL', not experimental"
[ "$EVENT" = "workflow_dispatch" ]    || die "event is '$EVENT', not workflow_dispatch"
[ "$REF" != "refs/heads/main" ]       || die "this is main; experimental builds come from branches"
case "$TAG" in experimental-*-???????) ;; *) die "tag '$TAG' is not experimental-<slug>-<sha7>" ;; esac
case "$TITLE" in "Experimental: "*) ;; *) die "title '$TITLE' does not start with 'Experimental: '" ;; esac
for f in MuffinEMU.ipa MuffinEMU-fakesigned.ipa; do [ -s "$f" ] || die "$f is missing"; done

git fetch -q --force origin main
BASE=$(git merge-base origin/main "$SHA")
BASE7=$(printf '%s' "$BASE" | cut -c1-7)
BASE_VER=$(git describe --tags --match 'v[0-9]*' --abbrev=0 "$BASE" 2>/dev/null || echo "no numbered release")
AHEAD=$(git rev-list --count "$BASE..$SHA")
SHA7=$(printf '%s' "$SHA" | cut -c1-7)

BODY=$(mktemp)
{
  echo "**Experimental build.** Unfinished test software, published by hand from a branch to be tried and discussed. It is not a release. For normal play use the latest numbered release."
  echo
  echo "- **Experiment:** $SHORT_NAME"
  echo "- **Branch:** \`$REF_NAME\` at \`$SHA7\`"
  echo "- **Based on:** main \`$BASE7\` ($BASE_VER), plus $AHEAD commit(s) on the branch"
  echo "- **Installing it replaces** an installed MuffinEMU: it has the same bundle identifier, so your games, saves and settings carry over."
  echo "- **Where it is listed:** only in the Experimental install source, for testers. It is in neither the Stable nor the Nightly source."
  echo
  ./ci/release-notes.sh "$BASE" "$SHA"
} > "$BODY"

FILES=(MuffinEMU.ipa MuffinEMU-fakesigned.ipa)
[ -s MuffinEMU.app.dSYM.zip ] && FILES+=(MuffinEMU.app.dSYM.zip)

# 1. The release for this build. Re-running the same build updates it in place.
if gh release view "$TAG" >/dev/null 2>&1; then
  w gh release upload "$TAG" "${FILES[@]}" --clobber
  w gh release edit "$TAG" --title "$TITLE" --prerelease --latest=false --notes-file "$BODY"
else
  w gh release create "$TAG" "${FILES[@]}" --target "$SHA" --title "$TITLE" --prerelease --latest=false --notes-file "$BODY"
fi

# 2. The rolling release: one tag, reused, always the most recently published experimental build.
ROLL=$(mktemp)
{
  echo "The most recently published **experimental** build. This tag moves: every experimental build replaces it. For a build you can come back to, use the per-experiment release it names below."
  echo
  echo "Latest: [$TITLE](https://github.com/$REPO/releases/tag/$TAG)"
  echo
  cat "$BODY"
} > "$ROLL"
ROLL_TITLE="Experimental: latest - $SHORT_NAME ($REF_NAME @ $SHA7)"
if gh release view experimental >/dev/null 2>&1; then
  w gh release upload experimental MuffinEMU.ipa MuffinEMU-fakesigned.ipa --clobber
  w gh release edit experimental --title "$ROLL_TITLE" --prerelease --latest=false --notes-file "$ROLL"
else
  w gh release create experimental MuffinEMU.ipa MuffinEMU-fakesigned.ipa --target "$SHA" --title "$ROLL_TITLE" --prerelease --latest=false --notes-file "$ROLL"
fi
move_tag experimental "$SHA"
echo "Published $TAG and the rolling experimental release"
