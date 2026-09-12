# Cemu — iOS port (Wii U emulator), work in progress

An iOS port of [Cemu](https://github.com/cemu-project/Cemu), the Wii U emulator written in
C/C++. This fork builds the genuine Cemu engine for iOS arm64 and drives it from a SwiftUI
shell — it is not a reimplementation.

**Where it actually is, as of 2026-09-12:** one retail game has been confirmed running at a
playable speed, on one device, by the owner — FAST Racing NEO on an iPad Pro (A12Z,
`iPad8,11`, iOS 26.6.1). That is the entire body of "it works" evidence. One game, one
device, and — as the next section spells out — a picture and a framerate, not a confirmed
controller and not a confirmed sound.

Every line below is meant to be checkable against a commit, a tag, or a device log. Where
something has not been checked, it says so. A document that overstates costs somebody a
debugging session to disprove, which is worse than having no document.

## Confirmed on device

- **The engine runs a retail title end to end at playable speed, rendering correctly.**
  FAST Racing NEO, A12Z iPad Pro, confirmed by the owner on the v3.8 IPA — which is the
  build this line is restored from (`ea2d6e05`). He installed it, launched a game, played,
  and it worked.
- **The v3.9 IPA did not.** Same owner, same device, minutes apart: garbled geometry and
  wrong colours. Both releases are tagged at the same commit (`fbcff902`), so on paper they
  are the same build. They are not — see below.
- **That was the interpreter, every time.** The JIT capability probe demands `PROT_EXEC` at
  `mmap` time, which iOS arm64 never grants, so it has never passed on any device. Every
  hour anyone has spent in this emulator has been interpreter-only, at 50–190 MIPS. That is
  a more interesting result than it first sounds, and it is not a claim about the JIT being
  good — it is a statement that the JIT is untested.

## Why this line was restored, and from where

A GitHub release records a target of `main` and resolves it when published, while the IPA
comes from whatever `main` was when the build ran. The two drifted:

| Release | Published | Built | From commit | Result |
|---|---|---|---|---|
| v3.8 | 22:09 | 21:42 | `ea2d6e05` | plays a game correctly |
| v3.9 | 01:33 | 01:14 | `8bcca9c8` | garbled geometry |

Two commits separate them and only one can render anything: `8bcca9c8`, *"Metal: emulate
RECTS with compute, not just real geometry shaders"*. Its own message ends with *"Whether
the colours come back with it is the open question this was built to answer."* The device
answered no.

**What is NOT the cause, because the obvious conclusion is wrong.** `ea2d6e05` already
contains compute-based geometry-shader and RECTS emulation — `f125dbd3` added it,
`ea2d6e05` switched it on — and that build works. It was *extending* that emulation in
`8bcca9c8` that broke it. Removing RECTS emulation wholesale would throw away the working
half.

CI now refuses to publish into a tag pointing at different code, so this particular way of
losing a week cannot recur.

## Versioning

Every release goes up by 0.1. The version lives in `ci/VERSION` and nowhere else; CI reads
it and refuses to publish when a dotted tag disagrees. It is **not** derived from the tag,
because that broke three times: `v47` shipped reporting itself as `"47"`, the fix for that
taught Python both tag schemes and not the shell so `v4.8` stamped `"0.4"`, and the rule is
undecidable at three digits — a `v138` tag reads as 13.8 by arithmetic and means 1.38.

This line starts at **3.8**, because that is what it is. It works back up from there rather
than renaming itself into a number it has not earned.

## Install

Two sources, because the two install paths need different builds:

- **SideStore / AltStore / LiveContainer** — `https://kiddreads.github.io/cemu-ios-muffin/apps.json`
  (`Cemu.ipa`, unsigned on purpose; these tools re-sign with your own Apple ID at install).
- **TrollStore / jailbroken** — `https://kiddreads.github.io/muffin-emu/trollstore.json`
  (`Cemu-fakesigned.ipa`, ad-hoc signed with the JIT entitlements genuinely embedded, which
  a SideStore re-sign would strip).

iPhone and iPad, iOS 15.0 or later. Both IPAs are attached to every release from this line. Ad-hoc signing has no
certificate and no team ID, so most tools describe the fake-signed build as "not signed" —
that is what fake-signing is, not a fault; `codesign -dv Payload/Cemu.app` reports
`Signature=adhoc`.

The interpreter needs no JIT permission at all, and it is what every confirmed run of this
port has used. JIT permission only matters for the recompiler, which is off by default and
unproven.

Bring your own games. Nothing copyrighted is distributed here — not titles, not system
files, not keys.

## The two CPU modes are equals

The recompiler and the interpreter are both first-class here and neither is the answer to a
bug in the other. Interpreter-only reached playable speed on an A12Z; the recompiler has
never run at all. "Use the JIT" is not a fix for anything in this repository, and a change
that only helps one mode has to say so.

Under the interpreter the guest clock is deliberately slowed (`shift 6`, an eighth of real
time) because the emulated CPU is orders of magnitude slower than the Espresso it stands in
for, and a guest whose deadlines are all already expired spends its timeslices on overdue
work. That compensation is not needed once the recompiler is doing the work, so a device
that passes the probe gets real time instead.

## The docs, and what each is for

- [`STATUS.md`](STATUS.md) — the long-form inspection: what was verified, what is written
  but unproven, what is dead code, with a citation per claim.
- [`ROADMAP.md`](ROADMAP.md) — the milestone gates. None is checked off without a
  demonstration.
- [`log.md`](log.md) — the journal. Dated entries: what was tried, what the device showed in
  the words used at the time, which theories died. It exists because a bug that survived a
  day of code reading was solved by one sentence about *when* the symptom started, and
  nothing else in the repo could have supplied that.
- [`docs/postmortems/`](docs/postmortems/) — regressions worth never repeating.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — the SwiftUI shell drives the real Cemu core through
  a thin C bridge, guarded by `CEMU_CORE_AVAILABLE`.

The original version of this repository shipped ~20 markdown files calling the project
"complete" and "production-ready". None of it was true. Those files are kept only as
history, under [`docs/_archive_original_claims/`](docs/_archive_original_claims/), and
should not be trusted.

## Building

- The Xcode project is generated from `src/ios/project.yml` via
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`, which is what CI
  does, then `cd src/ios && xcodegen generate`.
- Device builds need a Mac with **full Xcode** (iOS SDK); Command Line Tools alone are not
  enough.
- `ci/syntax-check.sh` type-checks the Espresso CPU core in seconds against stub headers,
  so a recompiler edit does not need a 25-minute CI run to find a typo. It covers
  `src/Cafe/HW/Espresso` **only** — not Latte (needs metal-cpp), not `.mm`, not Swift — and
  a pass means "the parse and the types survived", not "the build is green".
- Each release names the commit in its binary, and the app logs it as `Init Cemu <sha>` at
  the top of every run. That line is the only reliable way to tell two builds apart: a
  release tag has shipped a binary older than itself before (see `log.md`, 2026-09-11).

## License

Cemu is licensed under [Mozilla Public License 2.0](/LICENSE.txt). Files under
`dependencies/` and some individual `src/` files carry their original licenses as noted in
their headers.
