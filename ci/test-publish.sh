#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# Proves ci/publish-nightly.sh and ci/publish-experimental.sh against a throwaway git history and a
# stand-in `gh`, with DRY_RUN=1: every write is printed instead of performed, every read is answered
# from the fixture. Nothing real is touched. Run: ci/test-publish.sh
set -eo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GITHUB_REPOSITORY=acme/muffin DRY_RUN=1 DRY_RUN_LOG="$T/writes.log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ---- fixture: origin with main c1..c5 (c4 changes code, c5 only docs) and a feature branch off c2
git init -q --bare "$T/origin.git"
git init -q -b main "$T/work"; cd "$T/work"
git remote add origin "$T/origin.git"
mkdir -p ci docs src
cp "$REAL/ci/check-stable.sh" ci/; cp "$REAL/ci/lib-release.sh" "$REAL/ci/publish-nightly.sh" "$REAL/ci/publish-experimental.sh" "$REAL/ci/release-notes.sh" ci/
commit() { echo "$2" >> "$1"; git add -A; git commit -q -m "$3"; git rev-parse HEAD; }
C1=$(commit src/a.cpp 1 "c1")
C2=$(commit src/a.cpp 2 "c2")
git checkout -q -b feature/x; F1=$(commit src/f.cpp 1 "feature work

Release-note: A feature note"); git checkout -q main
C3=$(commit src/a.cpp 3 "c3")
C4=$(commit src/a.cpp 4 "c4")
C5=$(commit docs/apps.json 5 "Update install sources for main")
git tag v1.0 "$C1"
git push -q origin main feature/x --tags; git fetch -q origin
git checkout -q --detach "$C4"   # a run checks out its own commit, not the branch

# ---- stand-in gh: reads answered from env, everything else recorded and refused
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'SH'
#!/bin/bash
case "$*" in
  "api repos/"*"/commits/nightly -q .sha") [ -n "$NIGHTLY_SHA" ] && { echo "$NIGHTLY_SHA"; exit 0; } || exit 1 ;;
  "release view nightly"*) [ "$NIGHTLY_EXISTS" = 1 ] && exit 0 || exit 1 ;;
  "release view experimental"*) [ "$ROLLING_EXISTS" = 1 ] && exit 0 || exit 1 ;;
  "release view experimental-"*) exit 1 ;;
  "api repos/"*"/git/ref/tags/"*) exit 1 ;;
  *) echo "UNEXPECTED gh call: $*" >&2; echo "UNEXPECTED $*" >> "$DRY_RUN_LOG"; exit 99 ;;
esac
SH
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
touch MuffinEMU.ipa MuffinEMU-fakesigned.ipa MuffinEMU.app.dSYM.zip; echo x > MuffinEMU.ipa; echo x > MuffinEMU-fakesigned.ipa; echo x > MuffinEMU.app.dSYM.zip

FAILS=0
ok()   { echo "ok:   $1"; }
bad()  { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
writes() { cat "$DRY_RUN_LOG" 2>/dev/null || true; }
run_nightly() {   # run_nightly NAME EXPECT(publish|skip|refuse) then env assignments...
  local name="$1" expect="$2"; shift 2
  : > "$DRY_RUN_LOG"
  local out rc=0
  out=$(env "$@" ./ci/publish-nightly.sh 2>&1) || rc=$?
  case "$expect" in
    publish) [ $rc -eq 0 ] && writes | grep -q 'git/refs/tags/nightly\|git/refs -f ref=refs/tags/nightly' && ok "$name" || { bad "$name (rc=$rc)"; echo "$out"; } ;;
    skip)    [ $rc -eq 0 ] && [ -z "$(writes)" ] && echo "$out" | grep -q 'Nightly not updated' && ok "$name" || { bad "$name (rc=$rc)"; echo "$out"; writes; } ;;
    refuse)  [ $rc -ne 0 ] && [ -z "$(writes)" ] && echo "$out" | grep -q 'Nightly guard' && ok "$name" || { bad "$name (rc=$rc)"; echo "$out"; writes; } ;;
  esac
}
MAIN="EVENT=push REF=refs/heads/main CHANNEL=main"

# ---- nightly: eligible
run_nightly "eligible build of main publishes (the newer main commit only touches docs)" publish $MAIN SHA="$C4" NIGHTLY_SHA="$C3" NIGHTLY_EXISTS=1
writes | grep -q 'gh release upload nightly' && writes | grep -q 'gh release edit nightly' && ok "  ...it uploads to, and edits, the nightly release" || bad "  ...nightly writes missing"
writes | grep -v 'nightly' | grep -q . && bad "  ...it wrote something that is not nightly: $(writes | grep -v nightly)" || ok "  ...and touched nothing but nightly"
run_nightly "a dispatch on main is eligible too" publish EVENT=workflow_dispatch REF=refs/heads/main CHANNEL=main SHA="$C4" NIGHTLY_SHA="$C2" NIGHTLY_EXISTS=1
run_nightly "no nightly yet: it is created" publish $MAIN SHA="$C4" NIGHTLY_SHA= NIGHTLY_EXISTS=0
writes | grep -q 'gh release create nightly' && ok "  ...with gh release create" || bad "  ...create missing"
run_nightly "the current nightly is not on main (the incident): an eligible build repairs it" publish $MAIN SHA="$C4" NIGHTLY_SHA="$F1" NIGHTLY_EXISTS=1
run_nightly "the same build again is idempotent" publish $MAIN SHA="$C4" NIGHTLY_SHA="$C4" NIGHTLY_EXISTS=1

# ---- nightly: not the newest build -> quietly not updated
run_nightly "a re-run of an OLD main build must not move Nightly backwards" skip $MAIN SHA="$C2" NIGHTLY_SHA="$C4" NIGHTLY_EXISTS=1
run_nightly "main has moved on to code this build lacks: a newer build publishes" skip $MAIN SHA="$C3" NIGHTLY_SHA="$C2" NIGHTLY_EXISTS=1

# ---- nightly: structurally impossible for anything else (hard guards fail the job)
run_nightly "a feature-branch ref" refuse EVENT=workflow_dispatch REF=refs/heads/feature/x CHANNEL=main SHA="$F1" NIGHTLY_SHA="$C2" NIGHTLY_EXISTS=1
run_nightly "a feature-branch ref even with channel=experimental" refuse EVENT=workflow_dispatch REF=refs/heads/feature/x CHANNEL=experimental SHA="$F1" NIGHTLY_SHA="$C2" NIGHTLY_EXISTS=1
run_nightly "a pull request" refuse EVENT=pull_request REF=refs/heads/main CHANNEL=main SHA="$C4"
run_nightly "channel none" refuse EVENT=push REF=refs/heads/main CHANNEL=none SHA="$C4"
run_nightly "a commit that is not on main's first-parent history, claiming to be main" refuse $MAIN SHA="$F1" NIGHTLY_SHA="$C2" NIGHTLY_EXISTS=1
mv MuffinEMU.ipa "$T/hold"; run_nightly "a missing IPA" refuse $MAIN SHA="$C4" NIGHTLY_SHA="$C3" NIGHTLY_EXISTS=1; mv "$T/hold" MuffinEMU.ipa

# ---- experimental
run_exp() {
  local name="$1" expect="$2"; shift 2
  : > "$DRY_RUN_LOG"
  local out rc=0
  out=$(env "$@" ./ci/publish-experimental.sh 2>&1) || rc=$?
  if [ "$expect" = refuse ]; then
    [ $rc -ne 0 ] && [ -z "$(writes)" ] && echo "$out" | grep -q 'Experimental guard' && ok "$name" || { bad "$name (rc=$rc)"; echo "$out"; writes; }
  else
    [ $rc -eq 0 ] && ok "$name" || { bad "$name (rc=$rc)"; echo "$out"; }
  fi
}
EXP=(EVENT=workflow_dispatch REF=refs/heads/feature/x REF_NAME=feature/x CHANNEL=experimental SHA="$F1" TAG="experimental-feature-x-${F1:0:7}" TITLE="Experimental: Shader cache (feature/x @ ${F1:0:7})" SHORT_NAME="Shader cache")
run_exp "an experimental dispatch on a branch publishes" publish "${EXP[@]}"
W=$(writes)
echo "$W" | grep -q "gh release create experimental-feature-x-${F1:0:7} .* --prerelease" && ok "  ...a per-experiment pre-release" || bad "  ...per-experiment release missing: $W"
echo "$W" | grep -q -- "--title Experimental: Shader cache (feature/x @ ${F1:0:7})" && ok "  ...titled 'Experimental: <name> (<branch> @ <sha7>)'" || bad "  ...title wrong"
echo "$W" | grep -q "gh release create experimental MuffinEMU.ipa" && ok "  ...and the rolling 'experimental' release" || bad "  ...rolling release missing"
echo "$W" | grep -q "refs/tags/experimental" && ok "  ...and its tag moved" || bad "  ...tag move missing"
echo "$W" | grep -E 'nightly|release (create|edit|upload) v[0-9]|trollstore|docs/' && bad "  ...it touched nightly, a numbered release or a source" || ok "  ...and touched neither nightly, a numbered release nor any source"
run_exp "a re-dispatch of the same experiment updates in place" publish "${EXP[@]}" ROLLING_EXISTS=1
run_exp "main is refused" refuse EVENT=workflow_dispatch REF=refs/heads/main REF_NAME=main CHANNEL=experimental SHA="$C4" TAG=experimental-main-${C4:0:7} TITLE="Experimental: x (main @ ${C4:0:7})" SHORT_NAME=x
run_exp "a push is refused" refuse EVENT=push REF=refs/heads/feature/x REF_NAME=feature/x CHANNEL=experimental SHA="$F1" TAG=experimental-feature-x-${F1:0:7} TITLE="Experimental: x (feature/x @ ${F1:0:7})" SHORT_NAME=x
run_exp "channel none is refused" refuse EVENT=workflow_dispatch REF=refs/heads/feature/x REF_NAME=feature/x CHANNEL=none SHA="$F1" TAG=experimental-feature-x-${F1:0:7} TITLE="Experimental: x (feature/x @ ${F1:0:7})" SHORT_NAME=x
run_exp "a tag that is not experimental-<slug>-<sha7> is refused" refuse EVENT=workflow_dispatch REF=refs/heads/feature/x REF_NAME=feature/x CHANNEL=experimental SHA="$F1" TAG=nightly TITLE="Experimental: x (feature/x @ ${F1:0:7})" SHORT_NAME=x
run_exp "a title without the Experimental: prefix is refused" refuse EVENT=workflow_dispatch REF=refs/heads/feature/x REF_NAME=feature/x CHANNEL=experimental SHA="$F1" TAG=experimental-feature-x-${F1:0:7} TITLE="MuffinEMU 7.0" SHORT_NAME=x

# ---- the stable guard: a numbered release must strictly contain the latest one
stable() { ./ci/check-stable.sh "$1" "$2" >/dev/null 2>&1; }
stable v1.0 "$C4" && ok "a build newer than the latest release may cut the next one" || bad "newer build refused"
stable v1.0 "$C2" && ok "  ...including one that is only a little newer" || bad "c2 refused"
stable v1.0 "$C1" && bad "the commit the latest release was cut from was allowed again" || ok "a second run of the build that cut the latest release is refused"
git tag -f v1.1 "$C3" >/dev/null
stable v1.1 "$C2" && bad "an OLD re-run was allowed to cut a new release" || ok "a re-run of an old main build (older than the latest release) is refused"
stable v1.1 "$F1" && bad "a commit off main was allowed" || ok "a commit that does not contain the latest release is refused"
stable v9.9 "$C4" && bad "a missing tag was allowed" || ok "a tag that does not exist is refused"

# ---- the release notes the experimental body carries
BODY_OUT=$(./ci/release-notes.sh "$C2" "$F1")
echo "$BODY_OUT" | grep -q -- '- A feature note' && ok "release notes come from the branch's Release-note trailers" || bad "release notes: $BODY_OUT"

[ "$FAILS" -eq 0 ] && echo "all publish tests passed" || { echo "$FAILS publish test(s) failed"; exit 1; }
