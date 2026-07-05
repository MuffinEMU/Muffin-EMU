# Cemu iOS — Architecture (real vs. toy)

## Two engines currently live in this repo

```
                 ┌─────────────────────────────────────────────┐
                 │                SwiftUI shell                 │
                 │   src/ios/App  (browser, skins, MetalView)   │
                 └───────────────┬─────────────────┬────────────┘
                                 │                 │
              (today, fake)      │                 │   (target, real)
                                 ▼                 ▼
        src/ios/Emulation/EmulationEngine   src/ios/Bridge/CemuBridge.{h,mm}
        + WiiUCPU  ← TOY, to be retired      = C API → real CafeSystem
                                                         │
                                                         ▼
                                        src/Cafe, src/Common, src/config …
                                        (REAL upstream Cemu C++ engine)
                                                         │
                                                         ▼
                                   src/gui/iosgui/IOSWindowSystem.cpp
                                   (implements Cemu's WindowSystem seam)
```

- **Toy path (left):** `EmulationEngine` + `WiiUCPU`. Non-functional stubs. Being replaced.
- **Real path (right):** `CemuBridge` is a thin C interface that calls the genuine `CafeSystem` API. This is the path we build out.

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

- **Flag undefined (today, pre-M1):** the bridge compiles to honest "core not built" responses. The app builds and truthfully shows *"Real engine not compiled into this build yet."* — it does **not** pretend to emulate.
- **Flag defined (after M1 links the core):** the bridge calls the real `CafeSystem`.

This lets the SwiftUI shell build and run now while keeping the seam honest, and flips to the real engine the moment the core compiles for arm64 (see `ROADMAP.md` M1).

## Platform seams Cemu needs on iOS

| Seam | Cemu interface | iOS status |
|------|----------------|-----------|
| Window / canvas | `WindowSystem` (`src/gui/interface`) | stubbed in `IOSWindowSystem.cpp`; needs real size/canvas |
| GPU | Vulkan renderer | **not wired** — needs MoltenVK on `CAMetalLayer` (M3) |
| Input | `src/input` | **not wired** — map skins + MFi controllers (M4) |
| Audio | Cemu audio backend | **not wired** — CoreAudio (M4) |
| CPU | PPC interpreter (C++) | present in core; no ARM JIT — interpreter only |
