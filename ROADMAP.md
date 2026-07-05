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

## Assets already in this tree (verified 2026-07-05) — better than expected
The two scariest pieces of a Wii U-on-iOS port already exist upstream in this codebase:
- **ARM64 CPU JIT:** `src/Cafe/HW/Espresso/Recompiler/BackendAArch64` (plus a full PPC interpreter fallback). With on-device JIT (SideStore/LiveContainer) this is the fast path.
- **Native Metal GPU renderer:** `src/Cafe/HW/Latte/Renderer/Metal/` (42 files). Its **only** platform glue was one 23-line file (`MetalLayer.mm`) — now adapted to UIKit/iOS in this fork.
So the port is real engineering, not a rewrite.

## M1 — Compile the real core for iOS arm64  ← **the true starting gate**
The single most important unknown. Until the engine builds for `arm64-apple-ios`, there is nothing to bridge. **This must run on a machine with full Xcode or on CI — it cannot compile on a Command-Line-Tools-only Mac.**
- [x] Real iOS CMake toolchain (`cmake/ios.toolchain.cmake` — proper `SYSTEM_NAME iOS`, iPhoneOS sysroot via xcrun, min-version). Replaces the fake `cmake/ios.cmake` that targeted arm64 macOS.
- [x] Gate desktop-only deps off for iOS (`wxwidgets` → `!ios` in `vcpkg.json`).
- [x] Real CI build loop (`.github/workflows/build-ios-core.yml`) that cross-compiles deps for `arm64-ios`, builds the core, and uploads real logs — no `|| true` masking.
- [ ] **Iterate the CI loop until the core compiles** (dependency fixes, desktop-assumption fixes). This is the grind. Needs the fork on GitHub to run.
- [ ] Link into a `CemuCore` static lib the Xcode app embeds; define `CEMU_CORE_AVAILABLE`.
- **Exit test:** `build-ios-core` CI job goes green — the core builds for `arm64-apple-ios`.

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
