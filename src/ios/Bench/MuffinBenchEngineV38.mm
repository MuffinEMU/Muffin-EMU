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

namespace {
    bool s_initialized = false;
    std::string s_logPath;
}

int mbench_api_version(void) { return MBENCH_API_VERSION; }
const char* mbench_engine_id(void) { return "muffin-v38"; }
const char* mbench_engine_name(void) { return "Muffin v3.8 engine"; }
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
    s_logPath = _pathToUtf8(cemuLog_GetLogFilePath());
    s_initialized = true;
    return MBENCH_OK;
}

bool mbench_jit_permitted(void)
{
    // This engine also runs its own JIT probe at initialize (mmap MAP_JIT and more); the
    // recompiler is only usable when both agree, which cemu_bridge_cpu_mode() reports as 2.
    return mbench_common_process_is_debugged() && (!s_initialized || cemu_bridge_cpu_mode() == 2);
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
