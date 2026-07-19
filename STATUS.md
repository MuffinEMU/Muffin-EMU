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

- **This section is out of date as of 2026-07-19 — the toy engine described below is gone.** `src/ios/Emulation/CPUCore.swift`/`WiiUCPU` no longer exist in this tree. `src/ios/Emulation/EmulationEngine.swift` is now a thin, honest wrapper that calls the real `CemuBridge` C functions (`cemu_bridge_initialize`, `cemu_bridge_boot_rpx`, ...) — no fake ROM-loading. `GameManager.swift` already uses it. What's still missing is upstream of the Swift code: the compiled core isn't linked into the app yet (M2), so today `cemu_bridge_core_available()` returns `false` and every call honestly reports "engine not built yet."
- **The archived docs in `docs/_archive_original_claims/`** (`DELIVERY_COMPLETE.md`, `IMPLEMENTATION_COMPLETE.md`, `PHASE*_FINAL_STATUS.md`, the "benchmarks" in the old optimization guide, etc.) describe a finished product that does not exist. They are kept only for history. **Do not treat any of them as accurate.**

## Hard external constraints (not code problems — reality)

1. **JIT.** Corrected 2026-07-19 (the previous version of this file was wrong): Cemu has a real **ARM64** recompiler backend (`src/Cafe/HW/Espresso/Recompiler/BackendAArch64`), not just the x86-64 one, and it compiles clean for iOS — confirmed in the M1 build log (`[405/410] Building CXX object .../BackendAArch64.cpp.o`). So the fast JIT path is available, not just the C++ interpreter fallback. iOS still blocks JIT for normal apps — you need SideStore/AltStore/TrollStore + a JIT-enable step. _(Device side is handled: the target iPad Pro has JIT enabled via SideStore/LiveContainer.)_ Whether the recompiler actually *works* correctly on iOS (vs. just compiles) is untested — that's a M2+ question.
2. **GPU.** Corrected 2026-07-19 (the previous version of this file was wrong): no MoltenVK needed. Cemu also has a **native Metal renderer** (`src/Cafe/HW/Latte/Renderer/Metal/`), which is what this fork builds for iOS — Vulkan and OpenGL are excluded from the iOS target entirely (see ROADMAP.md M1/M3). What's left is platform glue: backing the Metal renderer's swapchain with the app's `CAMetalLayer` and finishing `IOSWindowSystem`'s stubs (M3).
3. **Performance.** Wii U emulation on an A-series/M-series chip will be slow if it falls back to the interpreter; the ARM64 JIT recompiler (#1) should help once verified working, not just compiling. Getting from "boots" to "playable" is its own mountain.

## Bottom line

Treat this as **"real engine present, port not started in earnest."** The immediate honest goal is not "play a game" — it is the first genuine milestone in `ROADMAP.md`: get the real Cemu core to **compile for iOS arm64**.
