//
//  CemuBridge.h
//  Real Swift <-> Cemu C++ engine bridge.
//
//  Pure-C interface so it can be imported from Swift via the bridging header.
//  The implementation (CemuBridge.mm) calls the genuine CafeSystem API.
//
//  Until the real Cemu core is compiled for iOS (ROADMAP.md M1), this is built
//  WITHOUT the CEMU_CORE_AVAILABLE flag and every call honestly reports
//  CEMU_BRIDGE_CORE_NOT_BUILT instead of pretending to emulate.
//
#ifndef CEMU_BRIDGE_H
#define CEMU_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    CEMU_BRIDGE_OK              = 0,   // title prepared/started (maps CafeSystem SUCCESS)
    CEMU_BRIDGE_INVALID_RPX     = 1,   // maps PREPARE_STATUS_CODE::INVALID_RPX
    CEMU_BRIDGE_UNABLE_TO_MOUNT = 2,   // maps PREPARE_STATUS_CODE::UNABLE_TO_MOUNT
    CEMU_BRIDGE_CORE_NOT_BUILT  = 100, // real engine not linked into this build yet (pre-M1)
    CEMU_BRIDGE_BAD_ARG         = 101, // null/empty path etc.
} CemuBridgeStatus;

/// True only when the real Cemu C++ engine is compiled and linked into this build.
/// Swift uses this to decide whether to show the honest "not built yet" state.
bool cemu_bridge_core_available(void);

/// One-time engine initialization. `mlcPath` = MLC/NAND root inside the app sandbox.
/// Safe (no-op) when the core is not available.
void cemu_bridge_initialize(const char* mlcPath);

/// Boot a standalone .rpx. Returns CEMU_BRIDGE_OK when the title starts.
/// Wraps CafeSystem::PrepareForegroundTitleFromStandaloneRPX + LaunchForegroundTitle.
CemuBridgeStatus cemu_bridge_boot_rpx(const char* rpxPath);

/// M3 (ROADMAP.md): wires the real native Metal renderer to an actual on-screen
/// surface. `uiView` must be a UIView* (bridged as void*); `width`/`height` are its
/// client size in LOGICAL POINTS (not physical pixels - the points -> pixels
/// conversion is applied downstream, exactly once per consumer, using `dpiScale`;
/// see the comment at this function's definition in CemuBridge.mm), `dpiScale` its
/// contentScaleFactor. Must be called before
/// cemu_bridge_boot_rpx() - the GPU thread reads the window size synchronously at
/// startup. Safe (no-op) when the core is not available.
void cemu_bridge_register_render_surface(void* uiView, int width, int height, double dpiScale);

/// Registers a SECOND surface for the Wii U GamePad (DRC) screen, so the two Wii U
/// outputs can be shown at once when there is somewhere to put them - the TV screen on
/// an external display (AirPlay / screen mirroring / a cable) and the GamePad screen on
/// the device. Same units as above: LOGICAL POINTS plus a scale.
///
/// When this is never called, `MetalRenderer::IsPadWindowActive()` stays false and the
/// renderer skips every pad-window code path outright rather than failing inside one.
/// That - not a second layer - is what "TV only" means here, and it is the normal
/// configuration on a device with no external display.
///
/// Main thread only: it creates a CAMetalLayer inside `uiView`. Safe (no-op) when the
/// core is not available.
void cemu_bridge_register_pad_render_surface(void* uiView, int width, int height, double dpiScale);

/// Asks for the pad surface to be dropped, because its display went away. The teardown
/// itself happens on the GPU thread at its next frame boundary - the pad layer belongs
/// to that thread while a title runs - so this returns immediately and the caller must
/// NOT free the hosting view. Safe to call when no pad surface exists.
void cemu_bridge_release_pad_render_surface(void);

/// True while a pad surface is registered. Reflects the renderer's own
/// IsPadWindowActive(), i.e. it only goes false once the GPU thread has actually
/// completed a release requested above.
bool cemu_bridge_has_pad_render_surface(void);

/// Re-sizes an already-registered surface after its hosting view moved or its display
/// changed - both the drawable and the CALayer's own frame/backing scale, which nothing
/// else maintains for a manually added sublayer. `mainWindow` selects TV vs GamePad.
/// Main thread only (Core Animation geometry). Safe (no-op) when the core is not
/// available or that surface was never registered.
void cemu_bridge_resize_render_surface(int width, int height, double dpiScale, bool mainWindow);

/// Writes a line into the engine's own log (log.txt + the os_log mirror) at
/// LogType::Force. Exists so Swift-side decisions that determine what the renderer
/// does - above all which physical display each Wii U screen was routed to - land in
/// the same timeline as the renderer's own lines, instead of in a separate iOS log
/// nobody correlates. Not a substitute for cemu_bridge_log_checkpoint(), which uses a
/// synchronous write() and survives an abrupt kill; this one goes through the engine's
/// buffered logger.
void cemu_bridge_log_line(const char* message);

/// Last frame rate actually measured by the emulator, or 0 when no title is
/// producing frames (idle, loading, or not yet rendering). This is the engine's own
/// number - LattePerformanceMonitor computes it and pushes it through
/// WindowSystem::UpdateWindowTitles() about once a second - not an estimate made on
/// the Swift side. Safe to call at any time; returns 0 when the core is not
/// available.
double cemu_bridge_get_fps(void);

bool cemu_bridge_is_title_running(void);
void cemu_bridge_pause(void);
void cemu_bridge_resume(void);
void cemu_bridge_shutdown_title(void);
void cemu_bridge_shutdown(void);

/// Human-readable one-liner describing engine/bridge state, for display in the UI.
/// Never NULL. Points to static/thread-local storage; copy if you need to keep it.
const char* cemu_bridge_status_text(void);

/// Appends a timestamped-by-nothing (just ordered) line to Documents/CemuCrashLog.txt.
/// Written via a raw synchronous write() so it survives even an abrupt/uncatchable
/// process termination (e.g. a GPU driver panic) - call this at every meaningful
/// startup milestone from Swift so a crash's location can be narrowed down from the
/// surviving log alone.
void cemu_bridge_log_checkpoint(const char* message);

/// Rescans for physical controllers and binds the first one found to player 1's
/// emulated GamePad if nothing is bound yet.
///
/// Normally unnecessary - SDL's own device-added event already triggers this - but it
/// costs nothing and closes the window where a controller pairs during app startup,
/// before the hotplug hook was installed. Safe to call at any time; a no-op until
/// cemu_bridge_initialize() has run.
///
/// NOTE: there is no touch-based input path. Player 1 needs a real MFi/Bluetooth
/// controller; the on-screen pad in ControllerSkins.swift is not wired to the engine.
void cemu_bridge_refresh_input_devices(void);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CEMU_BRIDGE_H
