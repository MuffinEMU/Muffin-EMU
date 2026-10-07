#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Publishes the rolling Nightly release. Structurally unable to publish anything but an eligible
# build of main: it re-verifies every condition itself and FAILS the job if a caller got it wrong.
#
# Eligible means: a push to main (or a dispatch run on main), the build and every verification
# before this step succeeded (the job only reaches here if they did), the commit is on main's
# first-parent history, this build is not older than the nightly already published (a re-run of an
# old main build must not move Nightly backwards), and main has not moved on to code this build
# does not contain (a newer build will publish its own).
#
# Environment: EVENT REF SHA CHANNEL GITHUB_REPOSITORY, files in $PWD (MuffinEMU.ipa,
# MuffinEMU-fakesigned.ipa). DRY_RUN=1 prints the writes instead of performing them.
set -eo pipefail
cd "$(dirname "$0")/.."
. ci/lib-release.sh

EVENT="${EVENT:?}"; REF="${REF:?}"; SHA="${SHA:?}"; CHANNEL="${CHANNEL:?}"
die() { echo "::error::Nightly guard: $1"; exit 1; }

# ---- hard guards: these can only fail through a bug in the caller -----------------------------
[ "$REF" = "refs/heads/main" ]                        || die "ref is '$REF', not refs/heads/main"
[ "$EVENT" = "push" ] || [ "$EVENT" = "workflow_dispatch" ] || die "event is '$EVENT'"
[ "$CHANNEL" = "main" ]                               || die "channel is '$CHANNEL', not main"
for f in MuffinEMU.ipa MuffinEMU-fakesigned.ipa; do [ -s "$f" ] || die "$f is missing"; done

git fetch -q --force origin main
MAIN=$(git rev-parse origin/main)
# (a case pattern, not `| grep -q`: grep exiting early would SIGPIPE the producer under pipefail)
FIRST_PARENT=$(git rev-list --first-parent origin/main)
case "
$FIRST_PARENT
" in
  *"
$SHA
"*) ;;
  *) die "$SHA is not on main's first-parent history" ;;
esac

# ---- eligibility: these end the step quietly, the build just is not the newest ----------------
skip() { echo "::notice title=Nightly not updated::$1"; exit 0; }

CURRENT=$(gh api "repos/$REPO/commits/nightly" -q .sha 2>/dev/null || true)
if [ -n "$CURRENT" ] && [ "$CURRENT" != "$SHA" ]; then
  if git cat-file -e "$CURRENT^{commit}" 2>/dev/null && git merge-base --is-ancestor "$CURRENT" origin/main; then
    git merge-base --is-ancestor "$CURRENT" "$SHA" \
      || skip "the nightly already published ($CURRENT) is newer than this build ($SHA)"
  else
    echo "::warning::the current nightly ($CURRENT) is not on main; this eligible build replaces it"
  fi
fi
if [ "$MAIN" != "$SHA" ] && ! git diff --quiet "$SHA" "$MAIN" -- . "${IGNORABLE_EXCLUDES[@]}"; then
  skip "main has moved to $MAIN with code this build ($SHA) does not contain; that build publishes its own nightly"
fi

# ---- publish -----------------------------------------------------------------------------------
BODY=$(mktemp)
cat > "$BODY" <<NOTES
The newest build of MuffinEMU, from commit $SHA on \`main\`.

**Known issue:** the on-screen controls don't respond reliably yet. A fix is on the way.

This tag moves. Every eligible build of main replaces it, so the download here is
always the newest code, never a version you can come back to. For that, use a
numbered release.

This build has not been tested. If you want the version that is known to
work, install the latest numbered release instead.
NOTES

# Assets first, then the tag and the notes: a failure partway leaves the old tag beside the old
# notes, never a new tag beside assets that are not its own.
if gh release view nightly >/dev/null 2>&1; then
  w gh release upload nightly MuffinEMU.ipa MuffinEMU-fakesigned.ipa --clobber
  w gh release edit nightly --title Nightly --prerelease --latest=false --notes-file "$BODY"
else
  w gh release create nightly MuffinEMU.ipa MuffinEMU-fakesigned.ipa --target "$SHA" \
    --title Nightly --prerelease --latest=false --notes-file "$BODY"
fi
move_tag nightly "$SHA"
echo "Nightly now points at $SHA"
