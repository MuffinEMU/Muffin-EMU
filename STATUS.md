# Cemu iOS — Honest Status

_Last verified by inspection: 2026-07-19. This file describes what the code **actually does today**, not what it's meant to do. If something here is wrong, the code changed — fix this file._

## TL;DR

**This does not boot or play any Wii U game yet — but the engine now compiles for iOS.** M1 (ROADMAP.md) is done and verified: the genuine upstream Cemu C++ core builds clean for `arm64-apple-ios` as `libCemuCafe.a` (Bitrise build #3, 2026-07-19, 410/410 objects linked, zero errors). It is not yet linked into the SwiftUI app, and no title has booted. There is a lot of real work still ahead. See `ROADMAP.md`.

This repo (`cemu-ios-muffin`) consolidates the two prior forks (`cemu-ios-playable`, `cemu-ios-a-chip`) onto the more advanced one (`playable`'s bridge-to-real-C++-engine strategy). `a-chip`'s from-scratch Swift reimplementation of the Latte-shader-to-MSL translator was not carried forward — it duplicated logic upstream Cemu already has in `HW/Latte/LegacyShaderDecompiler/LatteDecompilerEmitMSL.cpp`, which this repo's native Metal renderer already uses.

## What is real and works

- **The real Cemu engine compiles for iOS arm64** (`libCemuCafe.a`, M1 — see ROADMAP.md). Not just present in-tree: verified building clean via Bitrise CI, 410/410 objects, zero errors. This includes the ARM64 JIT recompiler backend, the C++ PPC interpreter, the full HLE OS stack, and the native Metal GPU renderer with its Latte-shader-to-MSL compiler.
- **A real iOS platform seam exists**: `src/gui/iosgui/IOSWindowSystem.cpp` implements Cemu's actual `WindowSystem` interface (mostly as stubs) so the core *could* be linked into an iOS app.
- **A SwiftUI app shell exists** (`src/ios/App`): game browser, controller-skin picker, Metal view. It runs as an iOS app; it just has nothing real behind it yet.
- **The bridge is real and ready**: `src/ios/Bridge/CemuBridge.{h,mm}` already implements the honest `CEMU_CORE_AVAILABLE`-gated calls into `CafeSystem`. It has not been linked/activated yet — that's M2's first task.

## What is fake / non-functional (do not trust)

- **`src/ios/Emulation/CPUCore.swift` (`WiiUCPU`)** — a hand-rolled PowerPC interpreter written in Swift. ~18 of its instruction handlers are empty stubs that `return 1` and do nothing. It cannot execute real game code and is a **dead end** — Cemu already has a correct C++ PPC interpreter/recompiler; we should bridge to that, not finish this.
- **`src/ios/Emulation/EmulationEngine.swift`** — "loads a ROM" by reading raw file bytes and dumping them at a fixed address. Wii U titles (`.wua`/`.wud`/`.rpx`) are packaged/encrypted formats; this is not how they load. Fake.
- **The Swift app never calls the real engine.** There is no bridge from Swift into `CafeSystem`. The toy engine and the real engine coexist and never speak.
- **The archived docs in `docs/_archive_original_claims/`** (`DELIVERY_COMPLETE.md`, `IMPLEMENTATION_COMPLETE.md`, `PHASE*_FINAL_STATUS.md`, the "benchmarks" in the old optimization guide, etc.) describe a finished product that does not exist. They are kept only for history. **Do not treat any of them as accurate.**

## Hard external constraints (not code problems — reality)

1. **JIT.** Corrected 2026-07-19 (the previous version of this file was wrong): Cemu has a real **ARM64** recompiler backend (`src/Cafe/HW/Espresso/Recompiler/BackendAArch64`), not just the x86-64 one, and it compiles clean for iOS — confirmed in the M1 build log (`[405/410] Building CXX object .../BackendAArch64.cpp.o`). So the fast JIT path is available, not just the C++ interpreter fallback. iOS still blocks JIT for normal apps — you need SideStore/AltStore/TrollStore + a JIT-enable step. _(Device side is handled: the target iPad Pro has JIT enabled via SideStore/LiveContainer.)_ Whether the recompiler actually *works* correctly on iOS (vs. just compiles) is untested — that's a M2+ question.
2. **GPU.** Cemu renders with **Vulkan** or OpenGL. On iOS the realistic path is Vulkan → **MoltenVK** (Vulkan-on-Metal). This has to be built and wired in; none of it is done here.
3. **Performance.** Interpreter-only Wii U emulation on an A-series/M-series chip will be slow. Getting from "boots" to "playable" is its own mountain.

## Bottom line

Treat this as **"real engine present, port not started in earnest."** The immediate honest goal is not "play a game" — it is the first genuine milestone in `ROADMAP.md`: get the real Cemu core to **compile for iOS arm64**.
