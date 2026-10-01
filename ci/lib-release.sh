#!/bin/bash
# Shared by the publishing scripts. Sourced, not run.
#
# Every command that WRITES to GitHub goes through `w`. With DRY_RUN=1 it prints what it would run
# and does nothing, which is how the channel rules are proven without touching a real release
# (.github/workflows/channel-dryrun.yml in the PR that added it). Reads run for real.
REPO="${GITHUB_REPOSITORY:?}"
DRY_RUN="${DRY_RUN:-0}"

w() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "DRY-RUN WOULD RUN: $*"
    echo "$*" >> "${DRY_RUN_LOG:-/dev/null}"
  else
    "$@"
  fi
}

# Paths that cannot change the binary (the workflow's paths-ignore list). A push to main that only
# touches these - the install-source bot commits docs/*.json after every build - does not make an
# in-flight build stale.
IGNORABLE_EXCLUDES=(
  ':(exclude)docs' ':(exclude)bench' ':(exclude)homebrew' ':(exclude)dist'
  ':(exclude).github/ISSUE_TEMPLATE' ':(exclude).gitignore'
  ':(exclude)ci/generate-sidestore-source.py' ':(exclude,glob)*.md'
  ':(exclude).github/workflows/build-bench-ipa.yml' ':(exclude).github/workflows/build-bench-rpx.yml'
  ':(exclude).github/workflows/build-rainbow-rpx.yml' ':(exclude).github/workflows/update-sidestore-source.yml'
  ':(exclude).github/workflows/community-stats.yml'
)

# move_tag TAG SHA: point a lightweight tag at SHA, creating it if needed.
move_tag() {
  local tag="$1" sha="$2"
  if gh api "repos/$REPO/git/ref/tags/$tag" >/dev/null 2>&1; then
    w gh api -X PATCH "repos/$REPO/git/refs/tags/$tag" -f "sha=$sha" -F force=true
  else
    w gh api -X POST "repos/$REPO/git/refs" -f "ref=refs/tags/$tag" -f "sha=$sha"
  fi
}
