# Cemu iOS — Architecture (real vs. toy)

## One engine, one path

The "two engines" this file used to describe are gone. `WiiUCPU` — the Swift toy CPU — was deleted; `EmulationEngine.swift` is now a thin wrapper over the bridge, with no emulation of its own.

```
                 ┌─────────────────────────────────────────────┐
                 │                SwiftUI shell                 │
                 │   src/ios/App  (browser, skins, MetalView)   │
                 └───────────────┬─────────────────┬────────────┘
                                 │                 │
                                 ▼                 ▼
        src/ios/Emulation/EmulationEngine   src/ios/Bridge/CemuBridge.{h,mm}
        (thin Swift wrapper, no logic) ───▶  = C API → real CafeSystem
                                                         │
                                                         ▼
                                        src/Cafe, src/Common, src/config …
                                        (REAL upstream Cemu C++ engine)
                                                         │
                                                         ▼
                                   src/gui/iosgui/IOSWindowSystem.cpp
                                   (implements Cemu's WindowSystem seam)
```

`CemuBridge` is a thin C interface that calls the genuine `CafeSystem` API. Everything below it is unmodified-in-spirit upstream Cemu.

## The real boot sequence (from upstream `src/main.cpp`)

The genuine way to run a title, which the bridge mirrors:

```cpp
CafeSystem::Initialize();
// … set up renderer + paths …
auto status = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(path);  // or PrepareForegroundTitle(titleId)
if (status == PREPARE_STATUS_CODE::SUCCESS)
    CafeSystem::LaunchForegroundTitle();
```

`PREPARE_STATUS_CODE` is exactly `{ SUCCESS, INVALID_RPX, UNABLE_TO_MOUNT }` — the bridge maps these 1:1.

## The bridge (`src/ios/Bridge/`)

`CemuBridge.h` is a pure-C header (Swift-importable via the bridging header). `CemuBridge.mm` is Objective-C++ that includes the real Cemu headers and calls the real API.

It is guarded by the `CEMU_CORE_AVAILABLE` compile flag:

- **Flag undefined:** the bridge compiles to honest "core not built" responses. The app builds and truthfully shows *"Real engine not compiled into this build yet."* — it does **not** pretend to emulate.
- **Flag defined (the iOS app build, since M2):** the bridge calls the real `CafeSystem`.

The stub half is still in the tree because it is what keeps the seam honest if the core ever stops being linked. It is not the live path.

## Platform seams Cemu needs on iOS

| Seam | Cemu interface | iOS status |
|------|----------------|-----------|
| Window / canvas | `WindowSystem` (`src/gui/interface`) | size/phys-size/DPI/fps are real; input, error dialogs and game-list hooks are no-ops |
| GPU | native Metal renderer (`Renderer/Metal/`) | wired to a real `CAMetalLayer` sublayer; no frame confirmed on device (M3) |
| Input | `src/input` | **not wired** — skin buttons call empty closures; no MFi (M4) |
| Audio | Cemu audio backend | **not wired** — cubeb is disabled for iOS in `CMakeLists.txt`; needs CoreAudio (M4) |
| CPU | PPC interpreter + AArch64 recompiler | both compile; the recompiler is force-disabled via `LaunchSettings::SetForceInterpreter(true)` |

There is **no MoltenVK and no Vulkan** in this build — an earlier version of this table said otherwise. Vulkan and OpenGL are excluded from the iOS target entirely.
