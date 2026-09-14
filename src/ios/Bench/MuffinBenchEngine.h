//
//  MuffinBenchEngine.h
//  The one contract every benchmarked engine implements, so all three are driven and
//  timed by exactly the same host code.
//
//  Engines (one framework each, all embedded in the benchmark IPA):
//    muffin-v38            Muffin's own engine at 53e77328 (v3.12, the v3.8 engine restore)
//    melocafe              MeloCafe's engine (MuffinEMU main)
//    muffin-v38-melofixes  Muffin's v3.8 engine with MeloCafe's engine changes applied
//
//  Isolation rules every engine framework must be built with, because all three are
//  loaded into one process in sequence and iOS never unloads a framework:
//    -fvisibility=hidden -fvisibility-inlines-hidden
//    -Wl,-exported_symbols_list,<file listing exactly the _mbench_* symbols below>
//  Without them dyld coalesces identically named weak C++ symbols (inline functions,
//  template statics, vtables) across the frameworks, and one engine silently runs
//  another engine's code - which would make every comparison meaningless.
//
//  Timing is NOT done here. The host tails mbench_log_path() and times the guest's
//  MUFFINBENCH BEGIN/END markers by wall clock, identically for every engine. The engine
//  only boots, runs, reports counters and shuts down.
//
#ifndef MUFFIN_BENCH_ENGINE_H
#define MUFFIN_BENCH_ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MBENCH_API_VERSION 1

// Multi-core for every engine: Muffin's v3.8 engine resolves Auto to the multi-core
// recompiler on an 8-core device and has no clean single-core recompiler switch for a
// standalone RPX, so all three run their multi-core modes. The workloads are
// single-threaded, so every engine carries the same scheduler overhead.
typedef enum {
    MBENCH_CPU_INTERPRETER = 0,  // multi-core interpreter
    MBENCH_CPU_RECOMPILER  = 1,  // multi-core recompiler; requires mbench_jit_permitted()
} MBenchCpuMode;

typedef enum {
    MBENCH_OK          = 0,
    MBENCH_ERR_INIT    = 1,  // engine failed to initialize
    MBENCH_ERR_BOOT    = 2,  // the RPX did not start
    MBENCH_ERR_NO_JIT  = 3,  // recompiler requested but this process cannot run generated code
    MBENCH_ERR_BAD_ARG = 4,
    MBENCH_ERR_STATE   = 5,  // called in the wrong order (e.g. boot before initialize)
} MBenchStatus;

/// Always MBENCH_API_VERSION. The host refuses an engine that disagrees.
int mbench_api_version(void);

/// Stable id: "muffin-v38", "melocafe" or "muffin-v38-melofixes".
const char* mbench_engine_id(void);

/// Human-readable name for the report.
const char* mbench_engine_name(void);

/// Short commit sha of the engine source, baked in at build time.
const char* mbench_engine_commit(void);

/// One-time engine setup. Every file the engine writes (config, log.txt, caches, mlc)
/// goes under dataDir, which the host deletes after this engine's run.
MBenchStatus mbench_initialize(const char* dataDir);

/// True when this process may execute generated code (CS_DEBUGGED set). Same answer for
/// every engine in one process; the host skips recompiler tests for all of them when false.
bool mbench_jit_permitted(void);

/// Registers the render surface. uiView is a UIView* whose layer is a CAMetalLayer, sized
/// in points with its screen scale. Call on the main thread, before mbench_boot.
MBenchStatus mbench_attach_surface(void* uiView, int widthPoints, int heightPoints, double scale);

/// Boots a standalone RPX with the Metal renderer and the given CPU mode, single core.
/// Returns once the title thread has been launched; the host then waits for markers.
MBenchStatus mbench_boot(const char* rpxPath, MBenchCpuMode cpu);

/// Absolute path of the log.txt the engine writes OSReport output into. The host tails it.
const char* mbench_log_path(void);

/// Frames the emulated GPU has finished (LatteGPUState.frameCounter). 0 when idle.
uint64_t mbench_frame_count(void);

/// True while a booted title is running.
bool mbench_title_running(void);

/// Stops the running title and releases what a title holds: guest memory, the renderer,
/// the recompiler's code cache. Safe to call when nothing is running.
void mbench_stop_title(void);

/// Releases everything the engine can before the next engine is loaded. After this the
/// host deletes dataDir. The framework itself stays mapped (iOS cannot unload it).
void mbench_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif // MUFFIN_BENCH_ENGINE_H
