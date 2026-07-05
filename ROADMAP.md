# Cemu iOS — Real Roadmap to Playing a Game

Honest, ordered milestones. Each is a gate: you cannot skip ahead. "Done" means demonstrated, not documented.

The strategy is **bridge to the real Cemu engine**, not finish the Swift toy. Cemu already has a correct PowerPC interpreter and a full Wii U OS/HLE stack in C++ (`src/Cafe`). Our job is to build that for iOS and drive it from the SwiftUI shell.

---

## M0 — Honesty + architecture (this session)
- [x] Fork isolated from the original (`origin` remote removed).
- [x] Purge/relabel the false "completed" docs → `docs/_archive_original_claims/`.
- [x] Write truthful `STATUS.md`, this roadmap, and `ARCHITECTURE.md`.
- [x] Scaffold the real Swift↔C++ bridge (`src/ios/Bridge/`) that targets the actual `CafeSystem` API, and rewire the Swift app to call it instead of the fake `WiiUCPU`.
- **Note:** the bridge is real code against the real API but is **not yet compiled/linked** — that requires M1.

## M1 — Compile the real core for iOS arm64  ← **the true starting gate**
The single most important unknown. Until the engine builds for `arm64-apple-ios`, there is nothing to bridge.
- [ ] Get a working iOS CMake toolchain (`ios-cmake` / `leetal`).
- [ ] Resolve the dependency tree for arm64-ios (boost, zlib, zstd, libzip, openssl, fmt, etc.) — most via vcpkg with an ios triplet, some vendored.
- [ ] Compile `CemuCommon` + `CemuCafe` + `CemuConfig` + `CemuInput` as static libs for the device.
- [ ] Link them with `IOSWindowSystem.cpp` into a `CemuCore` static library that the Xcode app embeds.
- **Exit test:** `CemuCore.a` builds for `arm64-apple-ios` and the sample app links against it without unresolved symbols.

## M2 — Bring-up: boot to a title's entry point (no graphics)
- [ ] Provide MLC/NAND paths, keys (`keys.txt`), and a title on the device's Documents dir.
- [ ] From Swift, call the bridge: `Initialize()` → `PrepareForegroundTitleFromStandaloneRPX()` → `LaunchForegroundTitle()`.
- [ ] Route Cemu's logging to the iOS console so we can see how far it gets.
- **Exit test:** the core loads an RPX and starts executing PPC via the C++ interpreter without immediately crashing; logs show OS/HLE init progress.

## M3 — Graphics: MoltenVK + present a frame
- [ ] Build MoltenVK for iOS; select Cemu's Vulkan renderer.
- [ ] Back Cemu's swapchain with the app's `CAMetalLayer` (the existing `MetalView`).
- [ ] Implement the real bits of `IOSWindowSystem` (size, canvas recreate) instead of stubs.
- **Exit test:** a title renders at least one correct frame on-device.

## M4 — Input + audio
- [ ] Map on-screen controller skins + MFi/Bluetooth controllers to Cemu's `src/input` (emulate a GamePad/Pro Controller).
- [ ] Wire an iOS audio backend (CoreAudio) to Cemu's audio.
- **Exit test:** you can move a character and hear sound.

## M5 — Actually playable
- [ ] Performance pass (interpreter is slow — profile, cache, threading).
- [ ] Save states / persistent saves through the iOS sandbox.
- [ ] Stability on the JIT-enabled iPad Pro via SideStore/LiveContainer.
- **Exit test:** boot a real game from the menu and play it.

---

## Reality checks
- **This is a large, multi-month effort.** M1 alone (dependency + toolchain wrangling) is substantial.
- The Swift `WiiUCPU`/`EmulationEngine` toy will be **retired**, not finished — kept only until the bridge replaces it.
- Every milestone's "done" must be a demonstrated behavior, logged here with the date and how it was shown. No milestone gets checked off on the strength of a document.
