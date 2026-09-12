# Two releases, one commit, two different binaries

**2026-09-12.** Cost: roughly a week of work on the wrong line, one abandoned
repository, and a diagnosis that named the wrong culprit twice.

## What the user saw

He installed the **v3.8** IPA, launched a retail game, played it. It rendered
correctly. Minutes later he installed the **v3.9** IPA on the same device and got
garbled geometry and wrong colours. He said, in effect: these must be different
commits, how else would this be?

## What the repository said

```
v38-geometry-rects-emulation -> fbcff902  tree b26f6e54
v39-rects-emulation          -> fbcff902  tree b26f6e54
```

Same SHA. Same tree. Zero commits between them. I checked this twice and told him
so both times: the two releases are the same build, so whatever he was seeing had
to be something else — a stale install, a cache, a device difference.

That was wrong, and it was wrong in the most expensive way available: it was
*verifiable*, it was *precise*, and it was answering a question nobody had asked.
He did not ask what the tags pointed at. He asked why two IPAs behaved
differently. Those turn out not to be the same question.

## The mechanism

**A GitHub release does not record the commit its assets were built from.**

When a release is created with a target of `main`, it resolves `main` at publish
time. The IPA attached to it comes from whatever a workflow run built, and that
run had its own `headSha` — resolved when the run *started*. Nothing forces those
two to agree, and nothing reports it when they do not.

Lining the release publish times up against the workflow run times:

| Release | Published | Build ran | Built from | Result |
|---|---|---|---|---|
| v3.8 | 22:09 | 21:42 | `ea2d6e05` | plays a game correctly |
| v3.9 | 01:33 | 01:14 | `8bcca9c8` | garbled geometry |

Neither IPA came from `fbcff902`, the commit both tags name. The tags were
created early, the builds ran later against a moving `main`, and each release
picked up the artifact that happened to be newest. Two tags genuinely pointed at
one commit *and* the two IPAs were genuinely different code. Both facts were
true at once, which is why checking the tags felt conclusive and settled nothing.

Two commits separate the two builds:

```
db312d0d  CI: stamp a build name and version into the IPA   (workflow file only)
8bcca9c8  Metal: emulate RECTS with compute, not just real geometry shaders
          MetalPipelineCompiler.cpp +172  .h +10  MetalRenderer.cpp +79
```

`8bcca9c8` is the regression. Its own commit message closes with *"Whether the
colours come back with it is the open question this was built to answer."* The
device answered: no, and it broke geometry as well.

## The part that is easy to get wrong

The obvious conclusion — *RECTS emulation is the problem, rip it out* — is wrong,
and I reached for it before checking.

`ea2d6e05`, the build that **works**, already contains compute-based
geometry-shader and RECTS emulation. `f125dbd3` added it and `ea2d6e05` switched
it on. The working build has the feature. `8bcca9c8` broke rendering by
*extending* it.

So the boundary is not "with emulation" versus "without". It is one specific
commit that went further than the working one. Removing the feature wholesale
would have thrown away a working half and produced a third broken line.

## Rules this produced

### A tag is a label, not a provenance record

If you need to know what code is in a binary, ask the **build**, not the tag:

```sh
gh run list --workflow "<name>" --json databaseId,headSha,createdAt
```

and line the timestamps up against the release. Better: have the build stamp its
own commit into the artifact, so the binary answers the question by itself.

### When someone's device disagrees with your repository, the device is right

The repository describes what *should* be true. A device describes what *is*. When
they conflict, the model is wrong somewhere — and the interesting work is finding
where, not restating the model more confidently.

Twice in this incident the answer was "those are the same commit," delivered with
evidence, and twice it was useless. The user held his ground on plainly empirical
grounds — *I installed one and it worked, I installed the other and it did not* —
and he was right both times.

### Answer the question that was asked

"Why do these two binaries behave differently?" is not "what do these two tags
point at?". The second is easier, checkable, and satisfying to answer. That is
exactly what makes it a trap: a precise answer to the adjacent question reads as
a resolution and stops the investigation.

### Never publish into a tag that names different code

`.github/workflows/build-ios-app.yml` now refuses to publish when the requested
tag already exists and points at a commit other than the one being built. This
incident is why, and it is the same guard that caught v4.9 shipping an IPA three
commits older than its own tag with every step green.
