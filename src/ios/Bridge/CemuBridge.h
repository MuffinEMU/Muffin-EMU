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
/// surface. `uiView` must be a UIView* (bridged as void*), `width`/`height` its
/// logical (point) size, `dpiScale` its contentScaleFactor. Must be called before
/// cemu_bridge_boot_rpx() - the GPU thread reads the window size synchronously at
/// startup. Safe (no-op) when the core is not available.
void cemu_bridge_register_render_surface(void* uiView, int width, int height, double dpiScale);

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

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CEMU_BRIDGE_H
