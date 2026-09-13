# Two releases, one commit, two different binaries

**2026-09-12.**

## What the user saw

He installed the v3.8 IPA, launched a retail game, played it — rendered
correctly. A few minutes later he installed v3.9 on the same device and got
garbled geometry and wrong colours. His take: these have to be different
commits, how else would this happen?

## What the repository said

```
v38-geometry-rects-emulation -> fbcff902  tree b26f6e54
v39-rects-emulation          -> fbcff902  tree b26f6e54
```

Same SHA, same tree, zero commits between them. I checked this twice and told
him both times: the two releases are the same build, so whatever he was
seeing had to be something else — stale install, cache, device quirk.

That was wrong. It was also verifiable and precise, which is what made it
wrong in an expensive way — it answered a question nobody had asked. He
didn't ask what the tags pointed at. He asked why two IPAs behaved
differently. Turns out those aren't the same question.

## The mechanism

A GitHub release doesn't record the commit its assets were built from.

When a release targets `main`, it resolves `main` at publish time. The IPA
attached to it comes from whatever a workflow run built — and that run
resolved its own `headSha` when it *started*. Nothing keeps those two in
sync, and nothing flags it when they drift.

Lining up the release publish times against the workflow run times:

| Release | Published | Build ran | Built from | Result |
|---|---|---|---|---|
| v3.8 | 22:09 | 21:42 | `ea2d6e05` | plays a game correctly |
| v3.9 | 01:33 | 01:14 | `8bcca9c8` | garbled geometry |

Neither IPA actually came from `fbcff902`, the commit both tags name. The
tags were cut early, the builds ran later against a moving `main`, and each
release just picked up whatever artifact was newest at publish time. So the
tags really did point at the same commit, and the two IPAs really were
different code — both true at once, which is exactly why checking the tags
felt conclusive and told us nothing.

Two commits separate the two builds:

```
db312d0d  CI: stamp a build name and version into the IPA   (workflow file only)
8bcca9c8  Metal: emulate RECTS with compute, not just real geometry shaders
          MetalPipelineCompiler.cpp +172  .h +10  MetalRenderer.cpp +79
```

`8bcca9c8` is the regression. Its own commit message ends with "Whether the
colours come back with it is the open question this was built to answer."
Answer: no, and it broke geometry too.

## The part that's easy to get wrong

Obvious next move: rip out RECTS emulation. That's wrong, and I reached for
it before checking.

`ea2d6e05` — the build that works — already has compute-based geometry-shader
and RECTS emulation. `f125dbd3` added it, `ea2d6e05` switched it on. So the
working build already has the feature; `8bcca9c8` broke rendering by
extending it further. Pulling the feature out entirely would've thrown away
the working half and produced a third, differently-broken line.

## What this changed

If you need to know what's actually in a binary, ask the build, not the tag:

```sh
gh run list --workflow "<name>" --json databaseId,headSha,createdAt
```

then line the timestamps up against the release. Better yet, have the build
stamp its own commit into the artifact so the binary can answer the question
by itself.

Also added a guard: `.github/workflows/build-ios-app.yml` now refuses to
publish when the requested tag already exists and points at a different
commit than the one being built. Same guard catches the v4.9 case from the
day before, where the shipped IPA was three commits older than its own tag.

Twice in this one I said "these are the same commit," with evidence, and
twice that was useless — the user was going on "I installed one and it
worked, I installed the other and it didn't," and he was right both times.
