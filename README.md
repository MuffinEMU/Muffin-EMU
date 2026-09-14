# Muffin — Wii U emulation on iOS

Muffin is an iOS port of [Cemu](https://github.com/cemu-project/Cemu), the Wii U emulator. It
builds Cemu's real C/C++ engine for iOS arm64 and drives it from a SwiftUI shell — the actual
emulation core, not a reimplementation.

## Status

A retail Wii U game runs end to end at playable speed, rendering correctly, on an iPad Pro
A12Z (`iPad8,11`, iOS 26.6.1). The game is FAST Racing NEO — installed, launched, and played.

It runs on the PowerPC interpreter. The recompiler exists in the codebase, but its capability
probe has never succeeded on iOS, so it has never executed a single instruction. Measured
guest throughput on the interpreter is 50–190 MIPS, using a predecoded instruction cache
rather than re-decoding each instruction on every pass.

The renderer is Metal. On GPUs without mesh shader support (the A12Z and similar), geometry
shaders and RECTS primitives are emulated with compute passes. Those same GPUs don't decode BC
textures in hardware either, so BC1–BC5 textures are decompressed on the CPU using NEON.

### Not yet confirmed

- **Audio** — the backend initialises, but no sound has been confirmed on a device.
- **Controller input** — works at a basic level; not tested systematically beyond that.
- **The recompiler** — untested, because it has never run.
- **Compatibility** — unmeasured beyond the one confirmed game.

## Install

Two IPAs are attached to every release, because the two install paths need different signing:

- **SideStore / AltStore / LiveContainer** — add
  `https://kiddreads.github.io/cemu-ios-muffin/apps.json` as a source. These tools take the
  standard unsigned IPA and re-sign it with your own Apple ID at install.
- **TrollStore** — add `https://kiddreads.github.io/cemu-ios-muffin/trollstore.json` as a
  source, or download the ad-hoc signed IPA directly from
  [Releases](https://github.com/kiddreads/cemu-ios-muffin/releases).

Requires iPhone or iPad, iOS 15 or later. Landscape orientation.

Bring your own games — nothing copyrighted is distributed here: not titles, not system files,
not keys.

## Building

- The Xcode project is generated from `src/ios/project.yml` via
  [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`, then
  `cd src/ios && xcodegen generate`. CI does the same.
- Device builds need a Mac with full Xcode (iOS SDK); Command Line Tools alone aren't enough.
- `ci/syntax-check.sh` type-checks the Espresso CPU core in seconds against stub headers, so a
  recompiler edit doesn't need a full CI run to catch a typo. It covers
  `src/Cafe/HW/Espresso` only.
- Versions go up by 0.1 per release. The current version is 3.9.

## Themes

31 app icons, each with a matching colour theme. Three are premium, unlocked by code.

## Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how the SwiftUI shell drives the Cemu core through a
  thin C bridge
- [`STATUS.md`](STATUS.md) — detailed subsystem status
- [`ROADMAP.md`](ROADMAP.md) — planned work

#### AI generated contributions:

We ask that all code submitted is written and understood by a human. You can use AI for planning, designing, reviewing and for asking questions about the codebase, but the code itself needs to be written by you. As a small exception you can use intellisense-style AI code autocompletion for pure boilerplate code as long as it's only a small part of your submission. To further clarify, when we ask for "human written" that excludes letting an AI write the code and then paraphrasing it. In other words, we are asking for human effort.

Why this policy exists:

We have relatively low reviewing capacity and requiring human-written code increases the quality and trustworthyness of submitted pull requests. There are also general concerns with AI usage in emulation:
- LLMs tend to make up solutions that work on the surface but are generally not accurate in the emulation sense
- There is evidence that LLMs have been trained on leaked proprietary SDKs and we cannot verify the origin of the knowledge. This is especially a problem for core emulation logic

Please keep these points in mind when contributing to Cemu. Contributions that do not follow this policy may be rejected.

## License
Cemu is licensed under [Mozilla Public License 2.0](/LICENSE.txt). Exempt from this are all files in the dependencies directory for which the licenses of the original code apply as well as some individual files in the src folder, as specified in those file headers respectively.
