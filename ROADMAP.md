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

## M2 — Bring-up: boot to a title's entry point (no graphics)  ✅ DONE (2026-08-10)
- [x] Link `libCemuCafe.a` (+ every other CMake-built static lib: `iosgui`, `CemuAudio`, `CemuComponents`, `CemuCommon`, `CemuConfig`, `imguiImpl`, `CemuInput`, `CemuResource`, `CemuUtil`, plus vcpkg's arm64-ios deps) into the SwiftUI app's Xcode target; `CEMU_CORE_AVAILABLE`/`CEMU_PLATFORM_IOS`/`ENABLE_METAL` are defined so `CemuBridge.mm` calls the real `CafeSystem` instead of reporting `CEMU_BRIDGE_CORE_NOT_BUILT`.
  - **Done (2026-07-19):** GitHub Actions run [29679018901](https://github.com/bward-dev1/cemu-ios-muffin/actions/runs/29679018901) (`Build iOS App (M2)`) — every step green, including `Build the Cemu iOS app`. Log tail: `** BUILD SUCCEEDED **`, with `Ld .../Cemu.app/Cemu` actually linking the full binary (zero `error:`/`Undefined symbols` — the only string containing "error:" in the whole log is a source-code format-string literal, not a build failure), a Metal shader library compiled to `Cemu.app/default.metallib`, dSYM generated, and the bundle validated. This is the first time the app target has linked end-to-end; the ~950-line undefined-symbols cascade from prior rounds is fully resolved. Not code-signed (CI runs with `CODE_SIGNING_ALLOWED=NO`) and not yet run on a device/simulator — that's the next gate below.
- [x] Provide MLC/NAND paths, keys (`keys.txt`), and a title on the device's Documents dir.
  - **Done.** `cemu_bridge_initialize()` calls `ActiveSettings::SetPaths()` with a `Documents/mlc`-rooted user-data path (portable mode), and the app enables `UIFileSharingEnabled` plus an in-app ROM import button, so a title can reach `Documents/Roms`. No `keys.txt` is provided — not needed for the standalone-RPX path this milestone uses, but it will be for real discs/WUAs. (Note for anyone reading a device log: the `Documents/…/Documents/mlc/mlc01` nesting is LiveContainer's container layout, not a path built twice. See `STATUS.md`.)
- [x] From Swift, call the bridge: `Initialize()` → `PrepareForegroundTitleFromStandaloneRPX()` → `LaunchForegroundTitle()`.
  - **Done.** `GameManager.registerRenderSurface()` runs the whole sequence on a detached task, and a device log has now been captured showing it complete.
- [x] Route Cemu's logging to the iOS console so we can see how far it gets.
  - **Done, and it is what produced the M2 evidence.** Three sinks: `Documents/log.txt` (the engine's own), `os_log` under subsystem `com.cemu.ios` (added 2026-08-10 — the only one that survives the several boot paths that call `exit()` before the log file is ever opened, and the only one watchable live), and `Documents/CemuCrashLog.txt` for synchronous checkpoints and the signal handler. Formatted (`{}`-argument) log lines only started working on iOS on 2026-08-03; every one of them was silently dropped before that, which is worth knowing when reading any older device log.
- **Exit test — MET (2026-08-10):** the first device log to get past the last round of crash fixes shows, in order, the RPL link time, the HLE export scan, `Loaded module 'helloworld (1)'`, the `------- Active settings -------` block and `------- Run title -------`. `Run title` is logged by `cemu_initForGame()` *after* `Latte_Start()` returned and before `_LaunchTitleThread()` enters the scheduler, so the GPU thread initialized, the RPX loaded and linked, and the title thread took over — the C++ interpreter running Cafe OS on an iPad. What runs is the **single-core interpreter**, not the ARM64 JIT: `cemu_bridge_initialize()` forces it, and `_LaunchTitleThread()` therefore calls `OSSchedulerBegin(1)`. The log used to claim otherwise (`CPU-Mode: Multi-core recompiler`, printed from the config regardless of the override) — fixed 2026-08-10.

## M3 — Graphics: present a frame via the native Metal renderer
Correction from the original plan: this repo does **not** need MoltenVK/Vulkan. Upstream Cemu already ships a native Metal renderer (`src/Cafe/HW/Latte/Renderer/Metal/`, 42 files, incl. its own Latte-shader→MSL compiler in `HW/Latte/LegacyShaderDecompiler/LatteDecompilerEmitMSL.cpp`) — mature, real, and part of what M1 just compiled. Vulkan and OpenGL are excluded from the iOS build entirely (see M1); there is no MoltenVK dependency to build.
- [ ] Back the Metal renderer's swapchain with the app's `CAMetalLayer` (the existing `MetalView`/`MetalLayer.mm`).
  - **Built; the layer demonstrably exists, the picture does not.** `CreateMetalLayer()` adds a real `CAMetalLayer` as a sublayer of a plain `UIView` (marked opaque as of 2026-08-10), and `cemu_bridge_register_render_surface()` calls `MetalRenderer::InitializeLayer({w,h}, mainWindow=true)` before boot so the GPU thread finds a surface. Most of the crash-hunt commits since 2026-07-20 are about this path.
- [x] Decide at runtime which physical display each Wii U screen goes to.
  - **Done for detection and the on-device cases; written but unexercised for dual-screen.** `src/ios/App/DisplayRouter.swift` watches `UIScreen` connect/disconnect and scene activation from app launch and re-routes on every change. `deviceOnly` and `deviceMirrored` (AirPlay/screen mirroring, where the app gets no separate surface) both put the Wii U TV screen on the device and register no GamePad surface; `dualScreen` puts the TV screen on the external display and the GamePad screen on the device. Every evaluation is written into the engine log with the reason, so a device log says which branch ran.
  - **No configuration leaves a Cemu window without a layer.** Every renderer entry point that touches the pad window now tests `IsPadWindowActive()` first, matching the check the Latte core's GX2 path always did, so `AcquireDrawable` finding no layer is a bug marker rather than a routine event. Moving the TV screen reparents the hosting `UIView` instead of rebuilding its `CAMetalLayer`; the only real teardown (dropping the pad surface when its display goes away) is deferred to the GPU thread's next frame boundary.
- [ ] Implement the real bits of `IOSWindowSystem` (size, canvas recreate) instead of stubs.
  - **Partly done.** Window size, physical size, DPI scale and the frame-rate readout are real. Canvas recreate is not, and the size that gets registered is wrong in a way that will matter once something renders: `MetalViewIOS.makeUIView()` passes `UIScreen.main.bounds`, i.e. the **whole screen**, while the view it hands over occupies only the middle of a `VStack` between the header bar and the control panel. That was a deliberate trade — `view.bounds` is frequently still `CGRectZero` at that point, and boot waits on registration happening at all — but it means both `GetWindowPhysSize()` and the `CAMetalLayer` frame describe a surface larger than the view, anchored at the view's origin. Expect the image to sit low and overhang the bottom. The real fix is a resize path (`MetalRenderer::ResizeLayer()` exists; no bridge function exposes it, and `MetalLayerHandle::Resize()` only updates the drawable size, not the `CALayer` frame that `MetalLayer.mm` owns), which also covers rotation and split view. Not worth doing before a frame appears at all — it would change the geometry mid-diagnosis.
- **Exit test:** a title renders at least one correct frame on-device. **Not met.**

### Where the M3 investigation actually stands (updated 2026-08-10)

**Drawable starvation is no longer the leading suspicion.** The theory was that `MetalLayerHandle::AcquireDrawable()` stores a `+0` autoreleased `nextDrawable()` with no autorelease pool on the Latte thread, starving the layer's drawable pool. Its diagnostic — `"layer {} failed to acquire next drawable"` (`LogType::Force`, and *not* rate-limited) — does not appear in the first successful device log at all. The two lines that do appear (`AcquireDrawable: … mainWindow=false`, `SwapBuffer: … mainWindow=false`) are the **pad** window, which has no layer, so `nextDrawable()` was never called for it. That is a different failure and an expected one. The theory is unsupported by the evidence available; it is not disproven for a long-running session, since the captured log is short. Do not add a per-frame autorelease pool on a guess — `SwapBuffers()` is reached from several call sites and the acquire/present span crosses function boundaries.

**What the log could not say, and now can.** `cemuLog_logOnce()` keys its one-shot flag on the call site, so the pad window's first failure permanently silenced the TV window at the same call site — meaning the log carried no information whatsoever about whether the TV window ever presented. Fixed 2026-08-10: the flags are per-window, and there is a positive marker, `MetalRenderer: presented the first frame to the TV window (WxH pixels)`. The next device run splits M3 cleanly in two:

- **If that line appears:** the engine is acquiring and presenting drawables on the TV layer. The remaining problem is where that layer sits on screen — the known geometry defect below — or that the title never wrote anything into the drawable.
- **If it does not:** look for `Scan buffer dropped: renderTarget=… showDRC=… pad window active=…` (added in `LatteRenderTarget_itHLECopyColorBufferToScanBuffer`) and the existing `GX2SwapScanBuffers() reached for the first time` marker in `GX2.cpp`. Between them they say whether the title produced a frame at all, and whether it was routed to a window that does not exist. A DRC-only title on a touch-only host hits exactly that: `drawToPad` needs a pad window, `drawToMain` needs `showDRC`, which is toggled by Tab or a VPAD screen button — neither of which exists here.

`DrawEmptyFrame()` also now clears its drawable to opaque black instead of presenting undefined contents, so "presented an empty frame" is a definite state rather than whatever the drawable's memory happened to hold. On iOS that is currently the only frame that reaches the screen before a title scans out, because `LatteThread.cpp`'s pre-title wait loop never executes — `LaunchForegroundTitle()` sets `sSystemRunning` before spawning the thread that starts Latte, so `CafeSystem::IsTitleRunning()` is already true the first time the loop is evaluated.

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
