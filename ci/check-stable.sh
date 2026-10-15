#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Is this commit allowed to become the next numbered release?
#
# Only if it strictly contains the commit of the latest numbered release: that release's commit is an
# ancestor of this one, and the two differ. A re-run of an old build of main, or a second run of the
# build that already cut the latest release, finds it is not and must not publish a NEW release number
# for old (or identical) code; "Choose the version" takes the next vX.Y from the tags, so without this
# an old re-run would ship as the newest version.
#
# Usage: ci/check-stable.sh LATEST_TAG [COMMIT]   (COMMIT defaults to HEAD). Exit 0 = may publish.
set -eo pipefail
TAG="${1:?usage: check-stable.sh LATEST_TAG [COMMIT]}"
HEAD_SHA=$(git rev-parse "${2:-HEAD}^{commit}")
LAST=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}") || {
  echo "::warning title=No numbered release::tag $TAG does not resolve to a commit; not publishing a numbered release"; exit 1; }
if [ "$LAST" = "$HEAD_SHA" ]; then
  echo "::notice title=No numbered release::this commit ($HEAD_SHA) is the one $TAG was already cut from"
  exit 1
fi
if ! git merge-base --is-ancestor "$LAST" "$HEAD_SHA"; then
  echo "::notice title=No numbered release::$TAG ($LAST) is not an ancestor of this build ($HEAD_SHA): an older build cannot cut a new release"
  exit 1
fi
