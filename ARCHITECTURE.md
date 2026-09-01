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
| Input | `src/input` | wired — `cemu_bridge_set_button_state()`/`cemu_bridge_set_stick_axis()` write into `IOSInput_*`'s override state, which `is_mapping_down()`/axis reads already consult ahead of any physical mapping; both the on-screen pad and an attached MFi controller work without either cancelling the other |
| Audio | Cemu audio backend | **not wired** — cubeb is disabled for iOS in `CMakeLists.txt`; needs CoreAudio (M4) |
| CPU | PPC interpreter + AArch64 recompiler | both compile; the recompiler is conditionally permitted at runtime by `ios_jit_is_permitted()` (`CemuBridge.mm`) based on whether the process has executable-page access and `CS_DEBUGGED` (a JIT enabler like StikJIT/SideStore/LiveContainer attached) — not a hard `SetForceInterpreter(true)`. A crash-sentinel file guards the recompiler's first run per boot; see "Shader & pipeline caches" below for the equivalent JIT-survival callback that clears it correctly |

There is **no MoltenVK and no Vulkan** in this build — an earlier version of this table said otherwise. Vulkan and OpenGL are excluded from the iOS target entirely.

## Shader & pipeline caches — which one is which

Two genuinely different caching systems exist under `shaderCache/`, easy to conflate because both are gated by the same Settings toggle:

- **Persistent Shader Cache (the Settings toggle).** Controls whether either cache below is opened at all this session — `g_shaderCachePersistenceEnabled` (`LatteShader.h`/`LatteShaderCache.cpp`), checked once at the top of `LatteShaderCache_Load()`. Off skips both reading and writing; every writer already no-ops on a null cache handle, so this is a single, safe gate for both systems.
  - `shaderCache/transferable/<id>_mtlshaders.bin` — the Wii U bytecode of every shader a title has revealed by drawing with it. Lets a second launch skip re-decompiling GPU microcode it already saw. This is the "learned" cache in Settings' cache-stats screen.
  - `shaderCache/precompiled/<id>_mtlpipeline.bin` (`MetalPipelineCache`) — which shader/fixed-function-state *combinations* form a real pipeline, so the loading screen can eagerly warm those up instead of discovering them mid-gameplay. This is the "compiled" cache in Settings.
- **MTLBinaryArchive-backed binary cache (`metal-shader-binary-archive` branch, not yet merged).** Neither system above skips the actual `newRenderPipelineState()` machine-code compile — that ran fresh every launch regardless of either cache being warm. `shaderCache/precompiled/<id>_mtlbinaries.bin` is a real `MTL::BinaryArchive`, attached to every plain (non-mesh) render-pipeline descriptor in `MetalPipelineCompiler::Compile()` before compiling, so Metal can serve a matching binary instead of recompiling. Reuses the same `g_shaderCachePersistenceEnabled` toggle rather than adding a second one. This is the piece that was previously dead/commented-out code (`RendererShaderMtl.cpp`'s AIR-cache attempt, abandoned because it shelled out to macOS's `xcrun` metal compiler, which cannot run on-device).

A future session: "Persistent Shader Cache" in Settings is the on/off switch for all of the above; "the transferable/precompiled caches" are the two systems that predate this session; "the binary archive" is the newest, third piece, still unverified on real hardware.
