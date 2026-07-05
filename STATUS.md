# Cemu iOS — Honest Status

_Last verified by inspection: 2026-07-05. This file describes what the code **actually does today**, not what it's meant to do. If something here is wrong, the code changed — fix this file._

## TL;DR

**This does not boot or play any Wii U game yet.** It is an in-progress port with a real UI shell and the genuine Cemu C++ engine present in-tree, but the two are not yet connected and the engine has never been built for iOS in this repo. There is a lot of real work still ahead. See `ROADMAP.md`.

## What is real and works

- **The real Cemu engine source is in-tree** (`src/Cafe`, `src/Common`, `src/config`, `src/input`, etc.). This is upstream Cemu — a mature, correct Wii U emulator for desktop.
- **A real iOS platform seam exists**: `src/gui/iosgui/IOSWindowSystem.cpp` implements Cemu's actual `WindowSystem` interface (mostly as stubs) so the core *could* be linked into an iOS app.
- **A SwiftUI app shell exists** (`src/ios/App`): game browser, controller-skin picker, Metal view. It runs as an iOS app; it just has nothing real behind it yet.

## What is fake / non-functional (do not trust)

- **`src/ios/Emulation/CPUCore.swift` (`WiiUCPU`)** — a hand-rolled PowerPC interpreter written in Swift. ~18 of its instruction handlers are empty stubs that `return 1` and do nothing. It cannot execute real game code and is a **dead end** — Cemu already has a correct C++ PPC interpreter/recompiler; we should bridge to that, not finish this.
- **`src/ios/Emulation/EmulationEngine.swift`** — "loads a ROM" by reading raw file bytes and dumping them at a fixed address. Wii U titles (`.wua`/`.wud`/`.rpx`) are packaged/encrypted formats; this is not how they load. Fake.
- **The Swift app never calls the real engine.** There is no bridge from Swift into `CafeSystem`. The toy engine and the real engine coexist and never speak.
- **The archived docs in `docs/_archive_original_claims/`** (`DELIVERY_COMPLETE.md`, `IMPLEMENTATION_COMPLETE.md`, `PHASE*_FINAL_STATUS.md`, the "benchmarks" in the old optimization guide, etc.) describe a finished product that does not exist. They are kept only for history. **Do not treat any of them as accurate.**

## Hard external constraints (not code problems — reality)

1. **JIT.** Cemu's fast CPU path is an **x86-64** recompiler. There is no ARM64 JIT backend, so on iOS the only working CPU path today is the **C++ interpreter** (slow but real). iOS also blocks JIT for normal apps — you need SideStore/AltStore/TrollStore + a JIT-enable step. _(Device side is handled: the target iPad Pro has JIT enabled via SideStore/LiveContainer.)_
2. **GPU.** Cemu renders with **Vulkan** or OpenGL. On iOS the realistic path is Vulkan → **MoltenVK** (Vulkan-on-Metal). This has to be built and wired in; none of it is done here.
3. **Performance.** Interpreter-only Wii U emulation on an A-series/M-series chip will be slow. Getting from "boots" to "playable" is its own mountain.

## Bottom line

Treat this as **"real engine present, port not started in earnest."** The immediate honest goal is not "play a game" — it is the first genuine milestone in `ROADMAP.md`: get the real Cemu core to **compile for iOS arm64**.
