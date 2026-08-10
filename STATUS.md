# Cemu iOS — Honest Status

_Last verified by inspection: 2026-08-10. This file describes what the code **actually does today**, not what it's meant to do. If something here is wrong, the code changed — fix this file._

## TL;DR

**No Wii U title has been shown to boot yet.** What is proven is narrower and still real: the genuine upstream Cemu C++ core compiles for `arm64-apple-ios`, and the SwiftUI app links against it end-to-end and ships as an installable unsigned IPA. M1 is done. M2 is *written* in full — paths, boot call, logging — but its exit test has never been met, because no on-device run has been recorded since the last round of fixes. M3 (Metal) is partly built rather than untouched: the native Metal renderer is wired to a real `CAMetalLayer`, and `IOSWindowSystem` reports real sizes/DPI/FPS instead of stubs. Nobody has seen a frame.

The last several weeks of commits are a black-screen/crash hunt on device — read `git log` for the trail, each commit message states the actual root cause it found. See `ROADMAP.md` for the gates.

This repo (`cemu-ios-muffin`) consolidates the two prior forks (`cemu-ios-playable`, `cemu-ios-a-chip`) onto the more advanced one (`playable`'s bridge-to-real-C++-engine strategy). `a-chip`'s from-scratch Swift reimplementation of the Latte-shader-to-MSL translator was not carried forward — it duplicated logic upstream Cemu already has in `HW/Latte/LegacyShaderDecompiler/LatteDecompilerEmitMSL.cpp`, which this repo's native Metal renderer already uses.

## What is real and verified

- **The real Cemu engine compiles for iOS arm64** (`libCemuCafe.a`, M1). Verified in CI, 410/410 objects, zero errors — Bitrise `build-ios-core` #3 (2026-07-19), and re-verified by every `Build iOS Core (bring-up)` run since (latest: GitHub Actions [30925927945](https://github.com/bward-dev1/cemu-ios-muffin/actions/runs/30925927945), 2026-08-04). This includes the ARM64 JIT recompiler backend, the C++ PPC interpreter, the full HLE OS stack, and the native Metal GPU renderer with its Latte-shader-to-MSL compiler.
- **The app target links end-to-end and produces an installable IPA.** GitHub Actions `Build iOS App (M2)` — first green 2026-07-19 (run 29679018901), latest [30925953638](https://github.com/bward-dev1/cemu-ios-muffin/actions/runs/30925953638) (2026-08-04). `** BUILD SUCCEEDED **`, real `Ld .../Cemu.app/Cemu`, a compiled `default.metallib`, plus an unsigned `Payload/Cemu.app` IPA and a dSYM as artifacts. Not code-signed (CI runs `CODE_SIGNING_ALLOWED=NO`); SideStore/AltStore re-sign at install.
- **`CEMU_CORE_AVAILABLE` is genuinely defined**, so `src/ios/Bridge/CemuBridge.mm` calls the real `CafeSystem`, not the honest-stub path. `cemu_bridge_core_available()` compiles to `return true`.
- **A real iOS platform seam exists**: `src/gui/iosgui/IOSWindowSystem.cpp` implements Cemu's actual `WindowSystem` interface. Window size, physical size, DPI scale and the frame-rate readout are real; input/error-dialog/game-list hooks are still no-ops.
- **The app has been run on device.** That is how the last ~15 commits' root causes were found (JIT alloc at static init, `PPCTimer_init()` never called, a `MetalLayerHandle` double-release, a zero-sized `CAMetalLayer`, a `fmt` null-pointer abort). Those are real crashes that were really diagnosed and really fixed — they are not evidence that anything *works*.

## Written but NOT verified (the honest middle ground)

Everything here is implemented against the real API and compiles. None of it has been demonstrated to do its job on a device.

- **Boot sequence.** `GameManager.registerRenderSurface()` → `cemu_bridge_initialize()` (`ActiveSettings::SetPaths()` under `Documents/mlc`, `PPCTimer_init()`, `LaunchSettings::SetForceInterpreter(true)`, `CafeSystem::Initialize()`) → `cemu_bridge_boot_rpx()` (`PrepareForegroundTitleFromStandaloneRPX()` → `LaunchForegroundTitle()`). Whether a title actually reaches its entry point is unknown.
- **Logging.** Two sinks: `Documents/log.txt` (Files-visible via `UIFileSharingEnabled`) and, as of 2026-08-10, `os_log` under subsystem `com.cemu.ios` so the boot can be watched live. Formatted log lines work on iOS as of 2026-08-03; before that every line with `{}` arguments was silently dropped. Separately, `Documents/CemuCrashLog.txt` carries synchronous checkpoint/signal-handler output.
- **Metal surface.** The C++ renderer's `CAMetalLayer` is created as a sublayer of a real `UIView` and sized in points. No frame has been confirmed on screen.
- **Interpreter, not JIT.** `SetForceInterpreter(true)` is deliberate: whether a sideloaded iOS process can get genuinely executable mmap'd memory is an open question, and M2 is about the OS/HLE stack, not speed.

## What is fake / non-functional (do not trust)

- **The archived docs in `docs/_archive_original_claims/`** (`DELIVERY_COMPLETE.md`, `IMPLEMENTATION_COMPLETE.md`, `PHASE*_FINAL_STATUS.md`, the "benchmarks" in the old optimization guide, etc.) describe a finished product that does not exist. They are kept only for history. **Do not treat any of them as accurate.**
- **`src/ios/Rendering/MetalRenderer.swift` and `MetalView.swift`'s macOS path** are placeholder MTKView renderers with nothing to draw: they consume `GameManager.getFrameTexture()`, which always returns nil and correctly so — the C++ renderer presents into its own layer and never hands a texture back. Dead weight, not a feature.
- **The on-screen controller skins** are drawn and selectable, but `OptimizedControlPanel`'s `onDPadInput`/`onButtonInput` callbacks are empty closures. Nothing is wired to Cemu's input layer (that is M4).
- **No audio backend exists** (also M4).

## Hard external constraints (not code problems — reality)

1. **JIT.** Cemu has a real **ARM64** recompiler backend (`src/Cafe/HW/Espresso/Recompiler/BackendAArch64`) and it compiles clean for iOS. iOS still blocks JIT for normal apps — you need SideStore/AltStore/TrollStore + a JIT-enable step. _(Device side is handled: the target iPad Pro has JIT enabled via SideStore/LiveContainer.)_ It is currently force-disabled anyway (see above). Whether it *works* on iOS is untested.
2. **GPU.** No MoltenVK needed. Cemu ships a **native Metal renderer** (`src/Cafe/HW/Latte/Renderer/Metal/`), which is what this fork builds; Vulkan and OpenGL are excluded from the iOS target entirely.
3. **Performance.** Wii U emulation on an A-/M-series chip will be slow on the interpreter. Getting from "boots" to "playable" is its own mountain.

## Bottom line

Treat this as **"real engine, real app binary, unproven emulation."** The next honest goal is unchanged: get a title to its entry point and show it in a log (`ROADMAP.md` M2's exit test). That gate needs a device run, not more code.
