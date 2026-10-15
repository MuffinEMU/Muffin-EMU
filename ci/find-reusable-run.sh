#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Prints the id of an earlier run of this workflow that already built exactly this tree and passed
# every check, or nothing. Usage: ci/find-reusable-run.sh BUILD_ID   (needs GH_TOKEN)
#
# A run that got through verification uploads an artifact named built-<build id> (see "Record this
# build"), so the lookup is one API call by name rather than a scan of run history. The run is then
# re-checked, not trusted: it must be complete and green, be this workflow's own file, and come from
# this repository (a fork's pull request can upload an artifact with any name).
set -eo pipefail
BID="${1:?usage: find-reusable-run.sh BUILD_ID}"
REPO="${GITHUB_REPOSITORY:?}"
WORKFLOW=".github/workflows/build-ios-app.yml"

RUNS=$(gh api "repos/$REPO/actions/artifacts?name=built-$BID&per_page=50" \
  --jq '.artifacts[] | select(.expired == false) | .workflow_run.id' 2>/dev/null | sort -rn | uniq || true)
for rid in $RUNS; do
  [ "$rid" = "${GITHUB_RUN_ID:-0}" ] && continue
  INFO=""
  # A run that is still finishing (its last steps after the upload) gets a couple of minutes.
  for _ in 1 2 3 4 5 6 7 8; do
    INFO=$(gh api "repos/$REPO/actions/runs/$rid" \
      --jq '[.status, (.conclusion // ""), .path, .head_repository.full_name] | @tsv' 2>/dev/null) || break
    STATUS=$(printf '%s' "$INFO" | cut -f1)
    [ "$STATUS" = "completed" ] && break
    sleep 15
  done
  [ -n "$INFO" ] || continue
  CONCLUSION=$(printf '%s' "$INFO" | cut -f2)
  RUNPATH=$(printf '%s' "$INFO" | cut -f3)
  HEAD_REPO=$(printf '%s' "$INFO" | cut -f4)
  if [ "$CONCLUSION" = "success" ] && [ "${RUNPATH%%@*}" = "$WORKFLOW" ] && [ "$HEAD_REPO" = "$REPO" ]; then
    echo "$rid"
    exit 0
  fi
  echo "run $rid is not reusable (conclusion=$CONCLUSION path=$RUNPATH repo=$HEAD_REPO)" >&2
done

exit 0
