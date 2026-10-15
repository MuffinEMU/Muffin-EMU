#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Decides, once, where a build is distributed. Every publishing step is gated on the answer AND on
# the ref and event directly (a bug here must not be able to promote a build on its own).
#
#   main          a push to main, or a dispatch run ON main. Publishes the next numbered release (the
#                 stable channel) and, if eligible, the rolling Nightly (ci/publish-nightly.sh).
#   experimental  a workflow_dispatch on a non-main ref with channel=experimental. Publishes an
#                 "Experimental: ..." pre-release and the rolling `experimental` one
#                 (ci/publish-experimental.sh). Never in the Stable or Nightly sources.
#   none          everything else: pull requests, pushes to other branches, dispatches without
#                 channel=experimental, audit builds. Run artifacts only, no release of any kind.
#
# Environment: EVENT, REF, REF_NAME, SHA, INPUT_CHANNEL, INPUT_NAME (all from the github context).
# Writes channel, slug, sha7, tag, title and short_name to $GITHUB_OUTPUT (or stdout without it).
set -eo pipefail

EVENT="${EVENT:?}"; REF="${REF:?}"; REF_NAME="${REF_NAME:?}"; SHA="${SHA:?}"
INPUT_CHANNEL="${INPUT_CHANNEL:-}"; INPUT_NAME="${INPUT_NAME:-}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

CHANNEL=none
WHY=""
case "$EVENT" in
  pull_request)
    WHY="a pull request build publishes nothing" ;;
  push|workflow_dispatch)
    if [ "$REF" = "refs/heads/main" ]; then
      if [ "$INPUT_CHANNEL" = "experimental" ]; then
        echo "::error::channel=experimental was chosen on main. Experimental builds come from branches; main builds are stable releases."
        exit 1
      fi
      CHANNEL=main
      WHY="$EVENT on main: the next numbered release, and Nightly if eligible"
    elif [ "$EVENT" = "workflow_dispatch" ] && [ "$INPUT_CHANNEL" = "release" ]; then
      # Opt-in, by hand only: the next numbered release built from this branch. Nightly stays
      # main-only (its job checks the ref), and the version step refuses a branch that doesn't
      # contain the latest release.
      CHANNEL=release
      WHY="dispatched on $REF_NAME with channel=release: the next numbered release, from this branch"
    elif [ "$EVENT" = "workflow_dispatch" ] && [ "$INPUT_CHANNEL" = "experimental" ]; then
      CHANNEL=experimental
      WHY="dispatched on $REF_NAME with channel=experimental"
    else
      WHY="$EVENT on $REF with no channel=experimental: run artifacts only"
    fi ;;
  *)
    WHY="event '$EVENT' publishes nothing" ;;
esac

SHA7=$(printf '%s' "$SHA" | cut -c1-7)
SLUG=$(printf '%s' "$REF_NAME" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-40 | sed 's/-$//')
[ -n "$SLUG" ] || SLUG=branch
SHORT="${INPUT_NAME:-$REF_NAME}"
TAG=""; TITLE=""
if [ "$CHANNEL" = experimental ]; then
  TAG="experimental-$SLUG-$SHA7"
  TITLE="Experimental: $SHORT ($REF_NAME @ $SHA7)"
fi

{
  echo "channel=$CHANNEL"
  echo "slug=$SLUG"
  echo "sha7=$SHA7"
  echo "tag=$TAG"
  echo "short_name=$SHORT"
  # A title can hold characters that break a multi-line output, so it is written on one line.
  echo "title=$(printf '%s' "$TITLE" | tr '\n\r' '  ')"
} >> "$OUT"

echo "::notice title=Distribution channel::$CHANNEL - $WHY"
echo "=============================================================="
echo " DISTRIBUTION CHANNEL: $CHANNEL"
echo "   $WHY"
case "$CHANNEL" in
  main)         echo "   releases: next numbered release; Nightly only if ci/publish-nightly.sh finds this build eligible" ;;
  release)      echo "   releases: next numbered release (Latest) from $REF_NAME. Nightly NOT touched" ;;
  experimental) echo "   releases: $TAG and the rolling 'experimental'. Nightly, stable and every source are NOT touched" ;;
  none)         echo "   releases: NONE. This build is run artifacts only" ;;
esac
echo "=============================================================="
