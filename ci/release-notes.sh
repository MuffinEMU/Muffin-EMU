#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Prints the "What changed" section of release notes for the commits in FROM..TO (default TO=HEAD),
# built from each commit's `Release-note:` trailer. Used for numbered releases (FROM is the previous
# release tag) and for experimental builds (FROM is where the branch left main), so both describe
# what is actually in them by the same rules.
#
# A commit says its own user-facing line with a `Release-note:` trailer:
#
#     Run one CPU core by default
#
#     ...why, at length, for whoever reads the history...
#
#     Release-note: Games run much faster on hot devices. MuffinEMU now uses one
#     Release-note: CPU core by default.
#
# Commits without the trailer fall back to their subject line. Repeating the trailer wraps one long
# note across lines; it does not make two bullets. `Release-note: skip` leaves the commit out.
#
# Usage: ci/release-notes.sh FROM [TO]
set -eo pipefail
FROM="${1:?usage: release-notes.sh FROM [TO]}"
TO="${2:-HEAD}"
# actions/checkout does not fetch notes, and a missing notes ref must not fail the build - it only
# means nobody has written one.
git fetch -q --force origin 'refs/notes/release-notes:refs/notes/release-notes' 2>/dev/null || true
BODY=$(git log --no-merges --reverse --format='%H' "$FROM..$TO" | while read -r sha; do
  subj=$(git show -s --format='%s' "$sha")
  # Housekeeping the installer writes back to the repo. It is not a change
  # anybody installed the build for. Written as a prefix strip rather than
  # a case statement: bash 3.2, which is what macOS runners still ship,
  # mis-parses a case pattern's ')' inside $( ).
  if [ "${subj#Update install sources}" != "$subj" ]; then continue; fi
  # Repeated trailers are ONE note that was wrapped across lines, so they
  # join back into a single bullet. Prefixing each line instead turned a
  # wrapped sentence into two bullets, the second starting mid-sentence.
  note=$(git show -s --format='%(trailers:key=Release-note,valueonly)' "$sha" \
         | sed '/^[[:space:]]*$/d' | paste -sd' ' -)
  # Second chance for a commit that is already pushed. Its message cannot
  # be edited without rewriting main, so the note lives beside it instead:
  #
  #     git notes --ref=release-notes add -m "what this means" <sha>
  #     git push origin refs/notes/release-notes
  #
  # The trailer still wins where both exist, so adding one never silently
  # overrides what the commit itself said.
  if [ -z "$note" ]; then
    note=$(git notes --ref=release-notes show "$sha" 2>/dev/null \
           | sed '/^[[:space:]]*$/d' | paste -sd' ' -)
  fi
  # `Release-note: skip` leaves a commit out entirely - for work that is
  # real but has no user-facing half, like build tooling. Better than
  # padding the notes with lines nobody installed the build for.
  if [ "$(printf '%s' "$note" | tr '[:upper:]' '[:lower:]')" = "skip" ]; then continue; fi
  if [ -n "$note" ]; then
    printf -- '- %s\n' "$note"
  else
    printf -- '- %s\n' "$subj"
  fi
# An identical note from two commits (say a fix-up repeating the original's
# note) is one change, so it gets one bullet. First occurrence wins.
done | awk '!seen[$0]++')
if [ -n "$BODY" ]; then
  printf '## What changed\n\n%s\n\n' "$BODY"
fi
