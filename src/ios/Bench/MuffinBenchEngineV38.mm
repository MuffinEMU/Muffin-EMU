//
//  MuffinBenchEngineV38.mm
//  The benchmark contract (MuffinBenchEngine.h) on Muffin's v3.8 engine, through the
//  engine's own Swift bridge (CemuBridge.h) exactly as the Muffin app drives it.
//
#include "MuffinBenchEngine.h"
#include "MuffinBenchCommon.h"
#include "CemuBridge.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cemu/Logging/CemuLogging.h"
#include "config/CemuConfig.h"
#include "config/LaunchSettings.h"

#include <string>

// Engine A and engine C build this same file, so both are driven identically. Only the
// label differs, chosen by the build.
#if defined(MBENCH_VARIANT_MELOFIXES)
#define MBENCH_ENGINE_ID "muffin-v38-melofixes"
#define MBENCH_ENGINE_NAME "Muffin v3.8 engine + MeloCafe changes"
#else
#define MBENCH_ENGINE_ID "muffin-v38"
#define MBENCH_ENGINE_NAME "Muffin v3.8 engine"
#endif

namespace {
    bool s_initialized = false;
    std::string s_logPath;
}

int mbench_api_version(void) { return MBENCH_API_VERSION; }
const char* mbench_engine_id(void) { return MBENCH_ENGINE_ID; }
const char* mbench_engine_name(void) { return MBENCH_ENGINE_NAME; }
const char* mbench_engine_commit(void) { return MBENCH_COMMIT; }

MBenchStatus mbench_initialize(const char* dataDir)
{
    if (!dataDir || !dataDir[0])
        return MBENCH_ERR_BAD_ARG;
    if (s_initialized)
        return MBENCH_ERR_STATE;
    // The automatic clock ladder would change guest timing mid-run, differently from the
    // other engines; off before initialize so it never arms.
    cemu_bridge_set_timebase_auto_enabled(false);
    cemu_bridge_initialize(dataDir);
    if (!cemu_bridge_core_available())
        return MBENCH_ERR_INIT;
    // Real-time guest clock. The bridge defaults to an eighth under the interpreter, which
    // would throttle the GPU workload's frame pacing and make engines incomparable.
    cemu_bridge_set_timebase_shift(3);
    // The markers the host times are guest OSReport lines, which Cemu logs as
    // LogType::CoreinitLogging. Each bridge enables its own mix of log types at initialize;
    // every engine is set to exactly Force + CoreinitLogging so logging costs the same.
    cemuLog_setActiveLoggingFlags(cemuLog_getFlag(LogType::CoreinitLogging));
    s_logPath = _pathToUtf8(cemuLog_GetLogFilePath());
    s_initialized = true;
    return MBENCH_OK;
}

bool mbench_jit_permitted(void)
{
    // The same process-level answer every engine gives, so the host picks the same CPU
    // modes for all of them. This engine's own extra JIT probe is applied in mbench_boot.
    return mbench_common_process_is_debugged();
}

MBenchStatus mbench_attach_surface(void* uiView, int widthPoints, int heightPoints, double scale)
{
    if (!uiView || widthPoints <= 0 || heightPoints <= 0)
        return MBENCH_ERR_BAD_ARG;
    cemu_bridge_register_render_surface(uiView, widthPoints, heightPoints, scale);
    return MBENCH_OK;
}

MBenchStatus mbench_boot(const char* rpxPath, MBenchCpuMode cpu)
{
    if (!s_initialized)
        return MBENCH_ERR_STATE;
    if (!rpxPath || !rpxPath[0])
        return MBENCH_ERR_BAD_ARG;
    const bool recompiler = (cpu == MBENCH_CPU_RECOMPILER);
    if (recompiler && !mbench_jit_permitted())
        return MBENCH_ERR_NO_JIT;
    // This engine also runs its own JIT probe at initialize (MAP_JIT and more) and only
    // allows the recompiler when it passed, which cemu_bridge_cpu_mode() reports as 2.
    if (recompiler && cemu_bridge_cpu_mode() != 2)
        return MBENCH_ERR_NO_JIT;
    // Multi-core in both modes, the same for every engine.
    LaunchSettings::SetForceInterpreter(false);
    LaunchSettings::SetForceMultiCoreInterpreter(!recompiler);
    cemu_bridge_set_recompiler_enabled(recompiler);
    GetConfig().graphic_api = kMetal;
    cemu_bridge_set_timebase_shift(3);
    return cemu_bridge_boot_title(rpxPath) == CEMU_BRIDGE_OK ? MBENCH_OK : MBENCH_ERR_BOOT;
}

const char* mbench_log_path(void) { return s_logPath.c_str(); }
uint64_t mbench_frame_count(void) { return LatteGPUState.frameCounter; }
bool mbench_title_running(void) { return cemu_bridge_is_title_running(); }
void mbench_stop_title(void) { cemu_bridge_shutdown_title(); }

void mbench_shutdown(void)
{
    cemu_bridge_shutdown_title();
    cemu_bridge_shutdown();
    s_initialized = false;
}
