# Project log

Dated entries, newest first — what happened, what it looked like on device,
what we learned. `../STATUS.md` says what's true now; this says how it got that
way.

Started this because a bug that had eaten a full day of reading got solved by
one sentence: "it started the day we did the themes." Nothing in the repo
would've told us that — dates and symptoms are diagnostic data, but only if
someone writes them down.

Each entry is roughly: what was tried (including what failed), what the
device actually showed (in the words used at the time — "bright coloured
blobs," not "rendering artifacts," because the exact wording turned out to
matter), what we learned, and the release tag to install if you want to
reproduce that day's state.

Current truth lives in `../STATUS.md`, milestones in `../ROADMAP.md`, incident
write-ups in `docs/postmortems/`, planned work in
`docs/MUFFIN_WORK_BACKLOG.md` — link to those instead of repeating them here.

---

## 2026-09-12 — v3.9 was the traitor, and the tags could never have told us

The owner installed the v3.8 IPA, launched a retail game, played it —
rendered fine. Installed v3.9 on the same device and got garbled geometry and
wrong colours. His take: these have to be different commits.

I'd checked twice and told him they weren't:

```
v38-geometry-rects-emulation -> fbcff902  tree b26f6e54
v39-rects-emulation          -> fbcff902  tree b26f6e54
```

Same SHA, same tree, zero commits between. Correct answer to the wrong
question — he wasn't asking what the tags pointed at, he was asking why the
two binaries behaved differently.

Turns out a GitHub release doesn't record what commit its assets were
actually built from. It resolves its target at publish time; the IPA comes
from whichever workflow run resolved its own `headSha` when *that run
started*. Nothing keeps the two in sync.

| Release | Published | Build ran | Built from | Result |
|---|---|---|---|---|
| v3.8 | 22:09 | 21:42 | `ea2d6e05` | plays a game correctly |
| v3.9 | 01:33 | 01:14 | `8bcca9c8` | garbled geometry |

Both tags really did point at one commit, and the two IPAs really were
different code. Both true, which is why checking the tags felt conclusive and
settled nothing.

The culprit is `8bcca9c8`, "Metal: emulate RECTS with compute, not just real
geometry shaders" — the only commit between the two builds that touches
rendering at all. Its own commit message ends: "Whether the colours come
back with it is the open question this was built to answer." Answer: no.

The owner had actually told me this on day one — "the second that session
worked on texture colours and fixing them, everything broke" — he was
describing this exact commit. Took a week and an abandoned repo to catch up
to what he already knew.

Tempting fix: rip out RECTS emulation. Wrong — `ea2d6e05`, the build that
works, already has compute-based geometry-shader and RECTS emulation
(`f125dbd3` added it, `ea2d6e05` turned it on). `8bcca9c8` broke things by
extending that feature further, not by introducing it. Ripping it out would've
killed the working half too.

What we did: restored the line at `ea2d6e05` as `kiddreads/muffin-emu`,
carried over everything with no emulation surface (app shell, themes, docs,
tooling, CI), left the emulation files byte-identical, and set `ci/VERSION`
back to 3.8 — because that's what it actually is.

`MetalRenderer.cpp` and `MetalPipelineCompiler.cpp` are off limits to agents
for now — that's where `8bcca9c8` lived.

Took about a week on the wrong line, plus one abandoned repo and two wrong
guesses at the culprit (write-combined buffers, then the binary archive)
before landing on the real one. Full write-up:
`docs/postmortems/2026-09-12-two-tags-one-commit.md`.

Lesson in passing: when someone's device disagrees with the repo, believe the
device.

---

## 2026-09-11 (later still) — One A12Z log, four defects, and the mode nobody knew we were in

**Device:** iPad Pro A12Z (`iPad8,11`), iOS 26.6.1, FAST Racing NEO. A real
user log, 66 seconds of it, plus an on-screen overlay from the same session.
Everything below is read off that log, not reasoned about.

Here's the big one: every confirmed run of this port, ever, has been
interpreter-only — and it was playable anyway. The log explains why:

```
JIT check: mmap(MAP_JIT, executable at map time) refused (errno 22) ... Forcing the interpreter
Emulated timebase: shift 6 (0.125x real time)
```

`ios_jit_is_permitted()` was asking for `PROT_READ|WRITE|EXEC` at `mmap()`
time — that's the x86_64 shape of this API. On an APRR core, a `MAP_JIT`
region is governed by the per-thread `pthread_jit_write_protect_np()` switch:
you map it, then toggle it. So the probe failed with `EINVAL` on hardware
that could actually do this, every launch, including fake-signed TrollStore
builds with the entitlements genuinely embedded. Fixed the probe to map
`RW`, verify `max_protection` carries `VM_PROT_EXECUTE`, resolve the toggle
through `dlsym`, and actually flip it. `MAP_JIT` is still required — this
doesn't regress to the `mprotect`-promoted path the old comment warns
SIGBUSes on.

The 0.125x clock was downstream of that, not a separate bug: `CemuBridge.mm`
sets `set_timebase_shift(jitPermitted ? 3 : 6)`, and the `jitPermitted`
branch had never once been taken. Should lift on its own now for devices that
pass the probe.

And interpreter-only, at an eighth of real time, was still turning in 50.00
MIPS then 190.64 MIPS three seconds later, with on-screen framerate swinging
21-61 FPS in one scene. That's a genuinely good result that's been sitting in
the logs looking like a failure.

**Second fix, same family.** `processAllJumps()` rewinds with
`setSize(jumpStart)` per patch and never restores it, so `getSize()`
afterward reports the end of the *last* patched jump. `readyRE()`, the icache
flush, and `PPCRecFunction->x86Size` all read that value. Everything after
the final jump was never marked executable and never invalidated — and Apple
arm64 isn't I/D coherent. Good candidate for the SIGBUS that got the JIT
probe tightened in the first place, which would mean the original evidence
for "only PROT_EXEC-at-map-time is safe" was confounded by a bug nobody had
found yet. Worth remembering: a second bug can manufacture the evidence for
the wrong fix to the first.

**Third and fourth, on the Metal side.** Six pipelines per session failing
with "Shaders reads from a color attachment whose pixel format is
MTLPixelFormatInvalid" — and each one then poisoned its cache entry
permanently, because a failed compile stayed in `m_pipelineCache` with
`m_pipeline == nullptr`, and every later draw on that hash got skipped for
the rest of the session. `CalculatePipelineHash()` also `continue`d on
`INVALID_FORMAT`, so present-but-invalid and absent hashed the same — two
attachment configs could share one entry, and one failing poisoned the other.

**Earlier the same day, same log:** geometry-shader/RECTS emulation had never
once run on any device. The flag got latched into `MetalRenderer` at
construction, but the only place that set it was `launchGame()`, after the
renderer already existed. 44,001 dropped draws, 39,098 of them RECTS — which
is the full-screen copy and post-processing path, so tonemap and composite
never ran and raw render targets went straight to screen. That's the
"violently oversaturated" picture, explained.

Caveat: the four fixes in `cc76be80` are complete but never got an
adversarial review — that stage got killed when the disk filled.
`BackendAArch64.cpp` type-checks locally; the Metal files need metal-cpp
headers the local stub set doesn't carry, and `CemuBridge.mm` is ObjC++, so
CI and the device are the first real check on three of the four.

Still open:
- 282,032,513 idle spins in 66 seconds, +19M per heartbeat. Ticks once per
  iteration of coreinit's per-core idle fiber — a core alive with nothing
  runnable, spinning instead of sleeping. Cause unknown.
- 1991 new shaders (1699 async), 25 pipelines (24 async) in one session.
  This is the stutter people are seeing. Async compile is on by default,
  which turns a hitch into something that shows up late rather than removing
  the work.
- BC1-BC5 decompressed on the CPU, because no Apple GPU through the A12Z has
  the hardware and Metal aborts the process rather than refusing the
  descriptor. Costs CPU per upload and memory per texture (BC1: half a byte
  per texel becomes four) on a device already at 2416 MB with 2191 MB of
  headroom.
- Audio still hasn't been confirmed to make a sound on a device.

Also this session: three Settings controls out of 23 got traced end to end
and found inert, each a different mechanism — the timer-shift picker was
restart-only (the automatic clock ladder too, and it logged steps it never
applied), VSYNC hit the same geometry-shader latching bug as above, and the
preview-pad default disagreed with itself across two files. "Enable Frame
Stretching" pointed at `LatteRenderTarget_getScreenImageArea()` — which
already does that job — instead of at a Swift class nothing instantiates.

Docs: `README.md` and the site got rewritten against the actual code and the
release list, not against their own previous revision. They'd been saying
"does it play games yet? No" and "no game confirmed playable end to end"
while the owner was playing one.

Releases: `v5.1-rects-emulation-actually-on` carries the RECTS fix (built
from `6617d179`). The JIT probe, icache, and pipeline-poisoning fixes
(`cc76be80`) are on `muffin/next-wave`, published as `v5.2-jit-and-rects`.
Check the `Init Cemu <sha>` line before trusting a build.

---

## 2026-09-11 (later) — v4.9 shipped a binary older than its own tag

`v4.9-disable-binary-archive` advertised three commits it didn't contain. The
tag points at `3b0f0ee0`; the `Cemu.ipa` attached to it was built from
`04d33d14`. Missing from the actual binary: the CI ad-hoc signing step
(`6c867e43`), the separate TrollStore source (`7f9391df`), and the fix for
the app reporting its version as "0.4" (`3b0f0ee0`) — so v4.9 reported the
wrong version, which is exactly the bug its own tag claims to fix, and it
shipped no `Cemu-fakesigned.ipa` at all.

How it happened, from the timestamps: the build was dispatched at 17:44:41Z
against `04d33d14`. Three more commits landed on main while it ran. The
release got created at 17:53:05Z at the new main tip, and when the run
finished at 18:07:13Z its release step uploaded the older binary into the tag
that already existed. Nothing failed — every step was green.

Same family of trap as `v40-icon-matched-themes` (newest release ≠ newest
code) but a different mechanism. There the branch was stale. Here the branch
was fine and the tag moved on while the build was still running.

Fix: `build-ios-app.yml` now has a gate before the release step ("Refuse to
publish into a tag that names different code"). If the requested tag already
exists and points at a different commit than the one being built, the build
fails before uploading anything and names both SHAs. Tested against the real
v4.9 case (tag `3b0f0ee0` vs build `04d33d14` fails) and the three legitimate
cases (no tag, new tag, tag matching the build all pass).

Also found: two CI paths had never actually run before this. `6c867e43`
added the ad-hoc signing step and `7f9391df` added the TrollStore source
feed, both committed after the last app build was dispatched — so every
fake-signed IPA up through v4.8 was made by hand, and v4.9 has none. The
entitlements gate in that step requires at least 4 embedded entitlements, and
`src/ios/Cemu.entitlements` declares exactly 4 — passes with zero margin.
Dry-ran the feed generator against the real releases before publishing:
`apps.json` 72 versions, `trollstore.json` 5, both passing the workflow's own
gate.

Releases: `v5.0-trollstore-jit-ipa` is the first build made from a tag that
actually matches its own binary, and the first with a CI-built
`Cemu-fakesigned.ipa`.

---

## 2026-09-11 — The blobs, and where they came from

Device: everything rendering as shifting bright coloured blobs. "Truly
nauseating" at the time. Survived reinstalling.

Cause: `GetResourceOptions()` in `MetalBufferAllocator.h` was marking every
Shared buffer `CPUCacheModeWriteCombined`. Full write-up:
[`docs/postmortems/2026-09-11-write-combined-blobs.md`](docs/postmortems/2026-09-11-write-combined-blobs.md).

Short version: the original test was `options & MTL::ResourceStorageModeShared`,
and that enum is `0`, so it was always false — write-combined had never
actually been applied to anything. The one-line fix to that always-false test
turned it on for the whole buffer path at once, on hardware where basically
every buffer is Shared. Cemu's buffer cache does read-modify-write against
guest memory, which write-combined memory can't support. Corrupt vertex data
tears geometry; corrupt texture data samples as random bright colour.

It nearly got missed because the regression was reported right after an
unrelated batch of work, so that got investigated first, for hours. The
actual trigger was days older. What broke it open was being told when it
started, then reading that day's commits instead of the suspected ones.

Also cost time: the symptom got described differently at different moments —
"nothing renders," "everything is black," "bright coloured blobs." Three
different mechanisms. The last one is what actually identified it.

Other work this session — a swarm of agents auditing and fixing in parallel:

- Display geometry: the render surface was sized to the whole screen instead
  of the view hosting it, so the picture ran off the bottom. Also every
  resize kicked off a quarter-second implicit Core Animation animation,
  because there was no `CATransaction` anywhere in the repo.
- `MTLBinaryArchive` had no version and nothing ever expired it. The
  pipeline hash had been omitting which geometry shader was bound, so
  colliding keys got written to disk — and no later fix could undo that,
  because the file lives under `Documents` and survives reinstalls. Now
  versioned in the filename, with stale versions deleted on launch.
- `Compile()` returned `true` while handing back a null pipeline. The null
  got cached forever and every draw using it was silently skipped.
- Missing autorelease pool on the shader-cache load path — a leak that grows
  with the size of a title's cache, ending in SIGSEGV during boot.
- Latte/GPU thread was running a priority tier below the three PPC threads
  while doing all the Metal encoding; the main core's idle loop spun a
  performance core at 100% with no yield.
- Exiting a game hung the app — pause suspends the guest threads, shutdown
  has to join them, and a suspended thread never finishes. Mine, introduced
  and fixed the same session.
- Docs across the repo were about a month stale and actively misleading.
  Rewrote them against the code.

A few corrections I had to make along the way, all the same mistake —
trusting a reading instead of checking: claimed the shader binary cache
didn't exist (I'd checked the wrong header — it existed); claimed Metal never
commits at the frame boundary (it always has, since the backend's first
commit); claimed interpreter-only can't reach playable (contradicted by
working iOS emulators).

Releases: v41 through v47. Install `v47-blob-fix` — it carries the
write-combined fix alone, deliberately without the texture-decoder work, so
the blob result is readable on its own.

---

## 2026-09-05 / 09-06 — Themes, DLC import, and the release that went backwards

Icon-matched themes, DLC/update import, graphic packs exposed in Settings,
cover art. Also the day colour problems in FAST Racing Neo were being chased
— most coloured textures rendering flat black or grey.

Found later: `v40-icon-matched-themes` was published as "Latest" but was
built from a branch cut before that week's rendering fixes — 50 commits
behind main. Shipped without the DLC keycache fix, both geometry-shader
compile fixes, the 3D/cubemap texel-fetch fix, and RECTS-via-compute.
Installing the newest-dated release silently reverted a week of rendering
work. Fixed on 2026-09-10 by merging that branch into main so "newest" and
"best" stop diverging.

---

## 2026-09-04 — Geometry shaders and texel fetch

Two geometry shaders that could never compile on Metal: `gl_PrimitiveIDIn`
(a GLSL builtin) emitted verbatim into MSL, and `pointSize` written to a
struct with no such member. Texel fetch on array textures was emitting
`read()` with no coordinates, same bug again for 3D and cubemap. A geometry
shader that doesn't compile means the geometry it was supposed to produce is
just absent.

---

## 2026-08-31 / 09-02 — Recompiler and Metal audits

Heaviest days by commit count (34 and 106). Recompiler audit work, Metal
storage-mode fixes, the `MTLBinaryArchive` shader cache, shader-compile-failure
capture, and the per-window/per-target logging fixes that made later
diagnosis possible at all.

Two of the storage-mode "fixes" from 09-01 are the ones that caused the
blobs a week later. Neither looked risky at the time — see the postmortem.

---

## Earlier

Before this log existed. `git log` and `../ROADMAP.md` cover that history: the
engine compiling for arm64-ios (M1), the app linking end-to-end and shipping
an installable IPA (M2), and the long black-screen hunt that ended in a
picture on screen (M3).
