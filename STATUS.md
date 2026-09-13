# Status

A retail Wii U game runs end to end, at playable speed, rendering correctly, on an iPad Pro
A12Z (iPad8,11, iOS 26.6.1). The game is FAST Racing NEO — installed, launched, played.

## Engine

Runs on the C++ PowerPC interpreter, the real upstream Cemu core compiled for
`arm64-apple-ios`. Uses a predecoded instruction cache instead of re-decoding every
instruction on each pass. Measured throughput: 50–190 MIPS.

The ARM64 JIT recompiler is in the tree and compiles clean, but its capability probe has
never succeeded on iOS. It has never executed a single instruction.

## Renderer

Metal, wired to a real `CAMetalLayer`. Presents correctly on device.

GPUs without mesh shader support (A12Z and similar) emulate geometry shaders and RECTS
primitives with compute passes. The same GPUs don't decode BC textures in hardware, so
BC1–BC5 textures are decompressed on the CPU with NEON.

## Distribution

Two IPAs per release:
- Ad-hoc signed, for TrollStore.
- Unsigned, for SideStore / AltStore / LiveContainer.

Source feeds at kiddreads.github.io/cemu-ios-muffin/apps.json and /trollstore.json.

31 app icons with matching themes, three premium (unlocked by code).

iOS 15+, iPhone and iPad, landscape. Current version 3.9; versions step by 0.1.

## Not yet confirmed

- Audio — backend initializes, no sound confirmed on device.
- Controller input — basic response only, not tested systematically.
- The recompiler — untested, has never run.
- Compatibility — unmeasured beyond the one confirmed game.

## Milestones

- M1 — core compiles for iOS arm64. Done.
- M2 — boots a title to its entry point. Done.
- M3 — renders a frame via Metal. Done — a full game renders correctly and runs at playable
  speed.
- M4 — input + audio. Partial. Controller responds at a basic level; audio backend
  initializes but no sound confirmed.
- M5 — actually playable. Met for one game. Broader compatibility, performance, and
  stability work is still ahead — see ROADMAP.md.
