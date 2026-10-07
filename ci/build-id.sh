#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# A fingerprint of everything in the tree that can change what CI builds: the content of every
# tracked file (git's own blob hashes, so this is fast and needs no submodule checkout, and a
# submodule counts by the commit it pins) minus the paths that cannot change the binary.
#
# Two runs with the same build id compile the same IPA. That is what lets the run that publishes a
# release reuse the pull request run that already built the same code (see "Plan" in
# .github/workflows/build-ios-app.yml) instead of compiling it a second time.
#
# The excluded paths are the workflow's `paths-ignore` list, plus the other workflows, which do not
# touch this build. Root-level *.md only: a Markdown file under src/ or bin/ could be bundled into
# the app, so it stays in. The workflow file itself and ci/ stay in, so changing how the build
# works is never mistaken for "nothing changed".
set -eo pipefail
cd "$(dirname "$0")/.."
git ls-files -s -- . \
  ':(exclude)docs' ':(exclude)bench' ':(exclude)homebrew' ':(exclude)dist' \
  ':(exclude).github/ISSUE_TEMPLATE' ':(exclude).gitignore' \
  ':(exclude)ci/generate-sidestore-source.py' \
  ':(exclude,glob)*.md' \
  ':(exclude).github/workflows/build-bench-ipa.yml' \
  ':(exclude).github/workflows/build-bench-rpx.yml' \
  ':(exclude).github/workflows/build-rainbow-rpx.yml' \
  ':(exclude).github/workflows/update-sidestore-source.yml' \
  ':(exclude).github/workflows/community-stats.yml' \
  | shasum -a 256 | cut -c1-40
