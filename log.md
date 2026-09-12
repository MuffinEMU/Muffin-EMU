# Project log

A journal. Dated entries, newest first — what happened, what it looked like on
device, and what we learned. The other docs say what is true *now*; this one
says how it got that way.

**Why it exists.** On 2026-09-11 a bug that had defeated a day of reading was
solved by one sentence: *"it started the day we did the themes."* Nothing in the
repo could have told us that. Symptoms, dates and what was being chased at the
time are real diagnostic data, and they only survive if somebody writes them
down.

**What goes here** — one entry per working session or per notable day:
- what was actually attempted, including the things that failed
- what the device showed, in the words used at the time ("bright coloured
  blobs", not "rendering artifacts" — the precise wording is the evidence)
- what was learned, especially where an assumption turned out wrong
- the release tag anyone should install to reproduce that day's state

**What does not go here.** Current truth → `STATUS.md`. Milestones →
`ROADMAP.md`. Incident analysis → `docs/postmortems/`. Planned work →
`docs/MUFFIN_WORK_BACKLOG.md`. Link to those instead of restating them.

**House style.** Same as everywhere else in this repo: say what is actually
known, mark what is only believed, and never upgrade "written" to "works"
without evidence. An entry recording a failed theory is worth as much as one
recording a fix — arguably more, because it stops the next person re-walking it.

---

## 2026-09-11 (later still) — One A12Z log, four defects, and the mode nobody knew we were in

**Device:** iPad Pro A12Z (`iPad8,11`), iOS 26.6.1, FAST Racing NEO. A real user log,
66 seconds of it, plus an on-screen overlay from the same session. Everything below is read
off that log rather than reasoned about.

**The headline nobody had stated:** every confirmed run of this port, ever, has been
interpreter-only — and it was playable anyway. The log says why:

```
JIT check: mmap(MAP_JIT, executable at map time) refused (errno 22) ... Forcing the interpreter
Emulated timebase: shift 6 (0.125x real time)
```

`ios_jit_is_permitted()` asked for `PROT_READ|WRITE|EXEC` at `mmap()` time. That is the
x86_64 shape of this API; on an APRR core a `MAP_JIT` region is governed by the per-thread
`pthread_jit_write_protect_np()` switch — you map it and toggle it. So the probe failed with
`EINVAL` on hardware that was perfectly capable, on every launch, including fake-signed
TrollStore builds with the entitlements genuinely embedded. The probe now maps `RW`,
verifies `max_protection` carries `VM_PROT_EXECUTE`, resolves the toggle through `dlsym` and
actually opens and closes the write switch. `MAP_JIT` is still required — this does not
regress to the `mprotect`-promoted path the old comment rightly warns SIGBUSes on.

The 0.125x clock was a *consequence*, not a separate bug: `CemuBridge.mm` sets
`set_timebase_shift(jitPermitted ? 3 : 6)`, and the `jitPermitted` branch had never once been
taken. With the probe fixed it should lift on its own for a device that passes.

And the interpreter, at an eighth of real time, was still turning in **50.00 MIPS then
190.64 MIPS three seconds later**, with the on-screen framerate swinging 21–61 FPS in one
scene. Interpreter-only reaching playable on a 2020 tablet is a real result. It has been
sitting in the logs looking like a failure mode.

**Second fix, in the same family.** `processAllJumps()` rewinds with `setSize(jumpStart)` per
patch and never restored it, so `getSize()` afterwards reported the end of the *last* patched
jump. `readyRE()`, the icache flush and `PPCRecFunction->x86Size` all read that. Every byte
after the final jump was never marked executable and never invalidated — and Apple arm64 is
not I/D coherent. That is a strong candidate for the SIGBUS that got the probe tightened in
the first place, which would mean the original evidence for "only `PROT_EXEC`-at-map-time is
safe" was confounded by a bug nobody had found yet. Worth remembering the shape of that: a
second bug can manufacture the evidence for the wrong fix to the first.

**Third and fourth, on the Metal side.** Six pipelines per session failing with *"Shaders
reads from a color attachment whose pixel format is MTLPixelFormatInvalid"* — and each one
then poisoned its cache entry forever, because a failed compile stayed in `m_pipelineCache`
with `m_pipeline == nullptr` and every later draw on that hash was skipped for the rest of
the session. The log says exactly that, in those words. `CalculatePipelineHash()` also
`continue`d on `INVALID_FORMAT`, so present-but-invalid and absent hashed the same and two
attachment configurations could share one entry: one failing poisoned the other.

**Earlier the same day, from the same log:** geometry-shader/RECTS emulation had never once
run on any device. The flag was latched into `MetalRenderer` at construction and the only
push happened in `launchGame()`, after the renderer existed. 44,001 dropped draws, 39,098 of
them RECTS — which is the full-screen copy and post-processing path, so the tonemap and
composite chain never ran and the raw render targets went to screen. That is the
"violently oversaturated" picture, explained.

**Caveat, recorded rather than buried:** the four fixes in `cc76be80` are complete but their
adversarial review never ran — the review stage was killed when the disk filled.
`BackendAArch64.cpp` type-checks locally; the Metal files need metal-cpp headers the local
stub set does not carry and `CemuBridge.mm` is ObjC++, so CI and the device are the first
real check on three of the four.

**Still open, and named so the next log can be read against them:**
- **282,032,513 idle spins in 66 seconds, +19M per heartbeat.** That counter ticks once per
  iteration of coreinit's per-core idle fiber — a core alive but with nothing runnable,
  spinning rather than sleeping. Cause not established.
- **1991 new shaders (1699 async) and 25 pipelines (24 async) in one session.** This is the
  stutter being reported. Async compile is on by default, which turns a hitch into something
  appearing late; it does not remove the work.
- **BC1–BC5 decompressed on the CPU**, because no Apple GPU through the A12Z has the
  hardware and Metal aborts the process rather than refusing the descriptor. Costs CPU per
  upload and memory per texture (BC1: half a byte per texel becomes four) on a device
  already at 2416 MB with 2191 MB of headroom.
- **Audio still never confirmed to make a sound on a device.**

**Also this session:** three Settings controls out of 23 were traced end-to-end and found
inert, each by a different mechanism — the timer-shift picker was restart-only (and the
automatic clock ladder wholly so, logging steps it never applied), VSYNC was the
geometry-shader latching bug again, and the preview-pad default disagreed with itself across
two files. "Enable Frame Stretching" was pointed at
`LatteRenderTarget_getScreenImageArea()`, which is the mechanism that already does that job,
instead of at a Swift class nothing instantiates.

**Docs:** `README.md` and the site were rewritten against this, and against the release list,
rather than against the previous revision of themselves. They had been saying "does it play
games yet? No" and "no game confirmed playable end to end" while the owner was playing one.

**Releases:** `v5.1-rects-emulation-actually-on` carries the RECTS fix (built from
`6617d179`). The JIT probe, icache, and pipeline-poisoning fixes (`cc76be80`) are on
`muffin/next-wave` and are published in **v5.2-jit-and-rects**. Check the
`Init Cemu <sha>` line before judging a build.

---

## 2026-09-11 (later) — v4.9 shipped a binary older than its own tag

**What was wrong:** the `v4.9-disable-binary-archive` release advertised three
commits it did not contain. The tag points at `3b0f0ee0`; the `Cemu.ipa` attached
to it was built from `04d33d14`. Missing from the installable binary: the CI
ad-hoc signing step (`6c867e43`), the separate TrollStore source (`7f9391df`),
and the fix for the app reporting its version as "0.4" (`3b0f0ee0`) — so v4.9
reported the wrong version, which is precisely the bug its own tag names as
fixed, and it shipped no `Cemu-fakesigned.ipa` at all.

**How it happened**, from the timestamps rather than from guessing: the build was
dispatched at 17:44:41Z against `04d33d14`. Three more commits landed on main
while it ran. The release was created at 17:53:05Z at the new main tip, and when
the run finished at 18:07:13Z its release step uploaded the older binary into the
tag that already existed. Nothing failed; every step was green.

**Why it is worth an entry:** this is the `v40-icon-matched-themes` trap again —
"newest release" not meaning "newest code" — but by a different mechanism. There
the *branch* was stale. Here the branch was fine and the *tag moved on while the
build was running*. Knowing the first version of the trap would not have caught
this one.

**Fixed so it cannot recur:** `build-ios-app.yml` gains a gate before the release
step (`Refuse to publish into a tag that names different code`). If the requested
tag already exists and points at a commit other than the one being built, the
build fails before uploading anything, naming both shas. Verified against the
real v4.9 case — tag `3b0f0ee0` vs build `04d33d14` fails, the three legitimate
cases (no tag, new tag, tag matching the build) pass.

**Also worth knowing:** two CI paths had never actually executed before this.
`6c867e43` added the ad-hoc signing step and `7f9391df` added the TrollStore
source feed, both committed *after* the last app build was dispatched — so the
fake-signed IPA on every release up to v4.8 was made by hand, and v4.9 has none.
The entitlements gate in that step requires at least 4 embedded entitlements and
`src/ios/Cemu.entitlements` declares exactly 4, so it passes with no margin: add
an entitlement and it still passes, remove one and the build fails. The feed
generator was dry-run against the real releases before publishing — `apps.json`
72 versions, `trollstore.json` 5, both passing the workflow's own gate.

**Releases:** `v5.0-trollstore-jit-ipa` is the first build made from a tag that
matches its own binary, and the first with a CI-built `Cemu-fakesigned.ipa`.

---

## 2026-09-11 — The blobs, and where they came from

**Device:** everything rendering as shifting bright coloured blobs. Described at
the time as "truly nauseating". Persisted across reinstalls.

**Cause found:** `GetResourceOptions()` in `MetalBufferAllocator.h` was marking
every Shared buffer `CPUCacheModeWriteCombined`. Full write-up in
[`docs/postmortems/2026-09-11-write-combined-blobs.md`](docs/postmortems/2026-09-11-write-combined-blobs.md).

Short version: the original test was `options & MTL::ResourceStorageModeShared`,
and that enum is `0`, so it was always false — write-combined had never been
applied to anything, ever. A correct one-line fix to that always-false test
switched it on for the entire buffer path at once, on hardware where essentially
every buffer is Shared. Cemu's buffer cache does read-modify-write against guest
memory, which write-combined memory cannot support. Corrupt vertex data tears
geometry; corrupt texture data samples as random bright colour.

**How it was nearly missed.** The regression was reported straight after an
unrelated batch of work, so that batch got investigated first — for hours. The
trigger was days older. The breakthrough was being told *when* it started, then
reading that day's commits rather than the suspected ones.

**Also mis-stated along the way, which cost time:** the symptom was described at
different moments as "nothing renders", "everything is black" and "bright
coloured blobs". Those have three completely different mechanisms. The last one
is what identified it.

**Other work this session** — a swarm of agents auditing and fixing in parallel:

- Display geometry: the render surface was sized to the whole screen rather than
  the view hosting it, so the picture ran off the bottom. Also every resize was
  starting a quarter-second implicit Core Animation animation, because the repo
  had no `CATransaction` anywhere.
- `MTLBinaryArchive` had no version and nothing ever expired it. The pipeline
  hash had been omitting which geometry shader was bound, so colliding keys got
  written to disk — and no later fix could undo the file, because it lives under
  `Documents` and survives reinstalling. Now versioned in the filename, with
  stale versions deleted on launch.
- `Compile()` returned `true` while handing back a null pipeline; the null was
  cached forever and every draw using it was silently skipped.
- Missing autorelease pool on the shader-cache load path — a leak that grows with
  the size of a title's cache, i.e. worse the more you play, ending in SIGSEGV
  during boot.
- Latte/GPU thread was running a priority tier *below* the three PPC threads
  while doing all Metal encoding; the main core's idle loop span a performance
  core at 100% with no yield.
- Exiting a game hung the app — pause suspends the guest threads, shutdown has to
  join them, and a suspended thread never finishes. Mine, introduced and fixed
  the same session.
- Docs across the repo were roughly a month stale and actively misleading; all
  rewritten against the code.

**Corrections I had to make, recorded because they were all the same mistake** —
trusting a reading instead of checking: claimed the shader binary cache didn't
exist (checked the wrong header — it existed); claimed Metal never commits at the
frame boundary (it always has, since the backend's first commit); claimed
interpreter-only can't reach playable (contradicted by working iOS emulators).

**Releases:** `v41`…`v47`. Install `v47-blob-fix` — it carries the
write-combined fix *alone*, deliberately without the texture-decoder work, so the
blob result is readable on its own.

---

## 2026-09-05 / 09-06 — Themes, DLC import, and the release that went backwards

Icon-matched themes, DLC/update import, graphic packs exposed in Settings, cover
art. Also the day colour problems in FAST Racing Neo were being chased — most
coloured textures rendering flat black or grey.

**Trap discovered later:** `v40-icon-matched-themes` was published as "Latest"
but was built from a branch cut *before* that week's rendering fixes and 50
commits behind main. It shipped without the DLC keycache fix, both geometry-shader
compile fixes, the 3D/cubemap texel-fetch fix and RECTS-via-compute. Installing
the newest-dated release silently reverted a week of rendering work. Fixed on
2026-09-10 by merging that branch into main so "newest" and "best" stop diverging.

---

## 2026-09-04 — Geometry shaders and texel fetch

Two geometry shaders that could never compile on Metal (`gl_PrimitiveIDIn`, a
GLSL builtin, emitted verbatim into MSL; and `pointSize` written to a struct with
no such member). Texel fetch on array textures emitting `read()` with no
coordinates, then the same again for 3D and cubemap. A geometry shader that does
not compile means the geometry it was meant to produce is simply absent.

---

## 2026-08-31 / 09-02 — Recompiler and Metal audits

The heaviest days by commit count (34 and 106). Recompiler audit work, Metal
storage-mode fixes, the `MTLBinaryArchive` shader cache, shader-compile-failure
capture, and the per-window/per-target logging fixes that made later diagnosis
possible at all.

Two of the storage-mode "fixes" from 09-01 are the ones that caused the blobs.
Neither looked remotely risky at the time — see the post-mortem.

---

## Earlier

Before this log existed. `git log` and `ROADMAP.md` carry that history: the
engine compiling for arm64-ios (M1), the app linking end-to-end and shipping an
installable IPA (M2), and the long black-screen hunt that ended in a picture on
screen (M3).
