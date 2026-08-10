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

## M1 — Compile the real core for iOS arm64  ← **the true starting gate**  ✅ DONE (2026-07-19)
The single most important unknown. Until the engine builds for `arm64-apple-ios`, there is nothing to bridge. **This must run on a machine with full Xcode or on CI — it cannot compile on a Command-Line-Tools-only Mac.**
- [x] Real iOS CMake toolchain (`cmake/ios.toolchain.cmake` — proper `SYSTEM_NAME iOS`, iPhoneOS sysroot via xcrun, min-version). Replaces the fake `cmake/ios.cmake` that targeted arm64 macOS.
- [x] Gate desktop-only deps off for iOS (`wxwidgets` → `!ios` in `vcpkg.json`).
- [x] Real CI build loop (`.github/workflows/build-ios-core.yml`, mirrored to a Bitrise `build-ios-core` workflow on macOS `osx-xcode-16.4.x`) that cross-compiles deps for `arm64-ios`, builds the core, and uploads real logs — no `|| true` masking.
- [x] **Iterate the CI loop until the core compiles.** Fixed: missing iOS branch on `CPU_swapEndianU32/64/16` (MMU.h), `tick_cached`/`HighResolutionTimer::now`/`GetTickCount` falling off the end of non-void functions on iOS, `_BitScanReverse`/`_strcmpi` undefined on iOS, `executeCommand`'s `system()` call (unavailable/sandboxed on iOS, and dead code besides), and excluded ~40 Vulkan/OpenGL renderer files + the libusb-dependent `BackendLibusb`/`SkylanderXbox360` (real-USB-hardware-only, no vcpkg arm64-ios libusb port) from the iOS target entirely.
- [ ] Link into a `CemuCore` static lib the Xcode **app** embeds; define `CEMU_CORE_AVAILABLE`. (The engine builds as its own static lib now — `libCemuCafe.a` — but isn't yet wired into the SwiftUI app's Xcode project. That's the first task of M2.)
- **Exit test — MET:** Bitrise build `build-ios-core` #3 (2026-07-19, https://app.bitrise.io/app/77ea58d7-5b9f-4052-b424-7b4c5c5f6103/build/39e10ffd-d6ac-4c93-80ab-5634d632091e) finished green. Build log tail: `[410/410] Linking CXX static library src/Cafe/libCemuCafe.a` — all 410 translation units compiled, zero errors (14 deprecation warnings only). The genuine upstream Cemu engine now compiles for `arm64-apple-ios`.

## M2 — Bring-up: boot to a title's entry point (no graphics)
- [x] Link `libCemuCafe.a` (+ every other CMake-built static lib: `iosgui`, `CemuAudio`, `CemuComponents`, `CemuCommon`, `CemuConfig`, `imguiImpl`, `CemuInput`, `CemuResource`, `CemuUtil`, plus vcpkg's arm64-ios deps) into the SwiftUI app's Xcode target; `CEMU_CORE_AVAILABLE`/`CEMU_PLATFORM_IOS`/`ENABLE_METAL` are defined so `CemuBridge.mm` calls the real `CafeSystem` instead of reporting `CEMU_BRIDGE_CORE_NOT_BUILT`.
  - **Done (2026-07-19):** GitHub Actions run [29679018901](https://github.com/bward-dev1/cemu-ios-muffin/actions/runs/29679018901) (`Build iOS App (M2)`) — every step green, including `Build the Cemu iOS app`. Log tail: `** BUILD SUCCEEDED **`, with `Ld .../Cemu.app/Cemu` actually linking the full binary (zero `error:`/`Undefined symbols` — the only string containing "error:" in the whole log is a source-code format-string literal, not a build failure), a Metal shader library compiled to `Cemu.app/default.metallib`, dSYM generated, and the bundle validated. This is the first time the app target has linked end-to-end; the ~950-line undefined-symbols cascade from prior rounds is fully resolved. Not code-signed (CI runs with `CODE_SIGNING_ALLOWED=NO`) and not yet run on a device/simulator — that's the next gate below.
- [ ] Provide MLC/NAND paths, keys (`keys.txt`), and a title on the device's Documents dir.
  - **Written, not demonstrated.** `cemu_bridge_initialize()` calls `ActiveSettings::SetPaths()` with a `Documents/mlc`-rooted user-data path (portable mode), and the app enables `UIFileSharingEnabled` plus an in-app ROM import button, so a title can reach `Documents/Roms`. No `keys.txt` is provided — not needed for the standalone-RPX path this milestone uses, but it will be for real discs/WUAs.
- [ ] From Swift, call the bridge: `Initialize()` → `PrepareForegroundTitleFromStandaloneRPX()` → `LaunchForegroundTitle()`.
  - **Written, not demonstrated.** `GameManager.registerRenderSurface()` runs the whole sequence on a detached task. Whether it gets through is exactly what the exit test below is for.
- [ ] Route Cemu's logging to the iOS console so we can see how far it gets.
  - **Written, not demonstrated.** Three sinks now exist: `Documents/log.txt` (the engine's own), `os_log` under subsystem `com.cemu.ios` (added 2026-08-10 — the only one that survives the several boot paths that call `exit()` before the log file is ever opened, and the only one watchable live), and `Documents/CemuCrashLog.txt` for synchronous checkpoints and the signal handler. Formatted (`{}`-argument) log lines only started working on iOS on 2026-08-03; every one of them was silently dropped before that, which is worth knowing when reading any older device log.
- **Exit test:** the core loads an RPX and starts executing PPC via the C++ interpreter without immediately crashing; logs show OS/HLE init progress. **Not met.** Several rounds of on-device testing have found and fixed real crashes (see `git log`), but no run has yet been recorded reaching OS/HLE init. This gate needs a device, not more code.

## M3 — Graphics: present a frame via the native Metal renderer
Correction from the original plan: this repo does **not** need MoltenVK/Vulkan. Upstream Cemu already ships a native Metal renderer (`src/Cafe/HW/Latte/Renderer/Metal/`, 42 files, incl. its own Latte-shader→MSL compiler in `HW/Latte/LegacyShaderDecompiler/LatteDecompilerEmitMSL.cpp`) — mature, real, and part of what M1 just compiled. Vulkan and OpenGL are excluded from the iOS build entirely (see M1); there is no MoltenVK dependency to build.
- [ ] Back the Metal renderer's swapchain with the app's `CAMetalLayer` (the existing `MetalView`/`MetalLayer.mm`).
  - **Built, not demonstrated.** `CreateMetalLayer()` adds a real `CAMetalLayer` as a sublayer of a plain `UIView`, and `cemu_bridge_register_render_surface()` calls `MetalRenderer::InitializeLayer()` before boot so the GPU thread finds a surface. Most of the crash-hunt commits since 2026-07-20 are about this path.
- [ ] Implement the real bits of `IOSWindowSystem` (size, canvas recreate) instead of stubs.
  - **Partly done.** Window size, physical size, DPI scale and the frame-rate readout are real. Canvas recreate is not, and the size that gets registered is wrong in a way that will matter once something renders: `MetalViewIOS.makeUIView()` passes `UIScreen.main.bounds`, i.e. the **whole screen**, while the view it hands over occupies only the middle of a `VStack` between the header bar and the control panel. That was a deliberate trade — `view.bounds` is frequently still `CGRectZero` at that point, and boot waits on registration happening at all — but it means both `GetWindowPhysSize()` and the `CAMetalLayer` frame describe a surface larger than the view, anchored at the view's origin. Expect the image to sit low and overhang the bottom. The real fix is a resize path (`MetalRenderer::ResizeLayer()` exists; no bridge function exposes it, and `MetalLayerHandle::Resize()` only updates the drawable size, not the `CALayer` frame that `MetalLayer.mm` owns), which also covers rotation and split view. Not worth doing before a frame appears at all — it would change the geometry mid-diagnosis.
- **Exit test:** a title renders at least one correct frame on-device. **Not met.**

### Open M3 suspicion, not yet proven
`MetalLayerHandle::AcquireDrawable()` stores the `nextDrawable()` result raw, and `nextDrawable()` is `+0` autoreleased. There is no autorelease pool anywhere on the Latte/GPU thread — the pools in `MetalRenderer.cpp` are all narrow, around command-buffer and encoder creation only. If drawables are therefore never released back to the layer, `nextDrawable()` starves after a few frames and returns nil, which `MetalRenderer::SwapBuffer()`/`DrawBackbufferQuad()` handle by bailing out — i.e. a black screen. The diagnostic for this already exists (`"layer {} failed to acquire next drawable"`, `LogType::Force`), so **check the device log for that line before changing anything**: if it appears repeatedly, this is the cause; if it never appears, this theory is wrong and the drawables are fine. Do not add a per-frame autorelease pool on a guess — `SwapBuffers()` is reached from several call sites and the acquire/present span crosses function boundaries.

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
