# Release channels

A build is distributed to exactly one place, decided once, by `ci/decide-channel.sh`, and never
inferred from "the last job that finished". There are three channels and everything else publishes
nothing.

| Channel | What it is | Where it comes from | Install source |
|---|---|---|---|
| **Stable** | Numbered releases, `vX.Y`, titled `MuffinEMU X.Y` | A push to `main`, or a dispatch run on `main` | `apps.json`, `trollstore.json` |
| **Nightly** | The rolling `nightly` release, titled `Nightly`: the newest eligible build of `main` | The same main builds, if eligible (below) | `nightly.json`, `nightly-trollstore.json` |
| **Experimental** | One pre-release per experiment, `experimental-<branch-slug>-<sha7>`, titled `Experimental: <name> (<branch> @ <sha7>)`, plus a rolling `experimental` release | A `workflow_dispatch` on a branch other than `main` with `channel: experimental` | `experimental.json`, `experimental-trollstore.json` (per-experiment releases only) |
| Nothing | Run artifacts only, no release | Pull requests, pushes to other branches, dispatches without `channel: experimental`, audit builds | none |

Why this exists: the rolling nightly used to be updated by every non-PR build, including dispatches of
feature branches, so two experimental branch builds became the public Nightly feed. Now publishing to
Nightly is structurally impossible for anything but an eligible build of `main`.

## Numbered releases only move forward

"Choose the version" takes the next vX.Y from the tags, so an old build of `main` that is re-run would ship old
code as the newest version. `ci/check-stable.sh` refuses: a numbered release is published only if this build's
commit strictly contains the commit of the latest vX.Y release (that commit is an ancestor, and the two
differ). Otherwise the build publishes no numbered release (`MUFFIN_PUBLISH=false`, with a notice in the log).
Nightly has its own, separate check (below).

## Nightly eligibility

`ci/publish-nightly.sh` runs in its own job, `publish-nightly`, and publishes only if all of these hold
(the first four are hard guards that fail the job if a caller got them wrong):

1. the ref is `refs/heads/main`
2. the event is a push, or a dispatch on `main`
3. the channel decision was `main`
4. the commit is on `main`'s first-parent history
5. the build, and every verification in it, succeeded (the job only starts then)
6. this build is not older than the nightly already published. A re-run of an old build of `main`
   finds the nightly's commit is not an ancestor of it and leaves Nightly alone. (If the current nightly's
   commit is not on `main` at all, as after the incident, an eligible build repairs it.)
7. `main` has not moved on to code this build does not contain. Commits that only touch documentation,
   the install sources or other workflows (the `paths-ignore` set) do not count, so the source bot's
   own commits never make a build stale. A newer build publishes its own nightly.

There are four independent barriers: the `if:` on the job (ref, event, channel), the `nightly`
environment, whose deployment-branch rule allows `main` only (a job on any other branch is rejected
before it starts), the guards inside the script, and the source generator's check that the nightly's
commit is reachable from `main`.

## Experimental

Dispatch `build-ios-app.yml` on a branch with `channel: experimental` (and optionally
`experiment_name`, which becomes the `<name>` in the title, defaulting to the branch name).
`ci/publish-experimental.sh` then publishes:

- `experimental-<branch-slug>-<sha7>`: a pre-release titled `Experimental: <name> (<branch> @ <sha7>)`. Its
  notes say it is experimental, which feature and branch, what it is based on (main sha and the latest
  version), that it replaces an installed MuffinEMU (same bundle identifier, games and saves carry over),
  and that it is only in the Experimental source, plus the branch's `Release-note:` trailers.
- `experimental`: a rolling pre-release, tag reused, always the most recently published experimental build.
  No install source ever references it.

It touches neither Nightly, nor a numbered release, nor the Stable or Nightly sources. The `Experimental:`
title prefix is the visible label on GitHub.

## Install sources

`ci/generate-sidestore-source.py` builds every feed from real releases and refuses to write any of them
(leaving the published ones as they were, and failing `update-sidestore-source.yml`) if:

- a stable or nightly feed mentions any `/experimental` URL
- an experimental feed mentions nightly, a numbered release, or the rolling `experimental` release
- a feed entry's release title does not match its channel (`MuffinEMU X.Y`, `Nightly`, `Experimental: ...`)
- the `nightly` release's commit is not reachable from `main`

The Experimental source has one app, "MuffinEMU Experimental", with each eligible experiment as its own
version, newest first (versions look like `2026.9.30.2129`, four parts so they sort above Nightly's date and
every numbered release), a news entry per experiment, and a per-version description naming the experiment,
branch, commit, base and date, followed by the release notes. It lists at most the last 10 experiments and
drops any whose branch has been merged into `main` or deleted (the GitHub releases themselves stay).
Eligible means: a pre-release titled `Experimental: ...` whose tag is `experimental-<slug>-<sha7>`, or
one of the first two experiments, tagged `auto-<sha>` and retitled by hand (accepted by title rather than
re-tagged, because a tag is part of every download URL already shared).

`python3 ci/test-generator.py` exercises all of this offline. `.github/workflows/channel-dryrun.yml`,
in the pull request that added this, proved the publishing scripts against a dry-run flag.
