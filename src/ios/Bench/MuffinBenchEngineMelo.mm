//
//  MuffinBenchEngineMelo.mm
//  The benchmark contract (MuffinBenchEngine.h) on MeloCafe's engine, through
//  MuffinEMU's Swift bridge (CemuBridge.h) exactly as the MuffinEMU app drives it.
//
#include "MuffinBenchEngine.h"
#include "MuffinBenchCommon.h"
#include "CemuBridge.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "config/ActiveSettings.h"

#include <string>

namespace {
    bool s_initialized = false;
    std::string s_logPath;
}

int mbench_api_version(void) { return MBENCH_API_VERSION; }
const char* mbench_engine_id(void) { return "melocafe"; }
const char* mbench_engine_name(void) { return "MeloCafe engine"; }
const char* mbench_engine_commit(void) { return MBENCH_COMMIT; }

MBenchStatus mbench_initialize(const char* dataDir)
{
    if (!dataDir || !dataDir[0])
        return MBENCH_ERR_BAD_ARG;
    if (s_initialized)
        return MBENCH_ERR_STATE;
    // Same settings every engine gets: no clock ladder, no accuracy mode, and the
    // recompiler decided per boot.
    cemu_bridge_set_timebase_auto_enabled(false);
    cemu_bridge_set_favour_accuracy(false);
    cemu_bridge_set_recompiler_enabled(false);
    cemu_bridge_initialize(dataDir);
    // -1 means the engine never initialized (the bridge answers "cannot answer" then).
    if (cemu_bridge_reload_and_count_keys() < 0)
        return MBENCH_ERR_INIT;
    cemu_bridge_set_timebase_shift(3);
    s_logPath = _pathToUtf8(ActiveSettings::GetUserDataPath("log.txt"));
    s_initialized = true;
    return MBENCH_OK;
}

bool mbench_jit_permitted(void)
{
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
    // Favour accuracy stays off, so the bridge writes the multi-core mode for either path.
    cemu_bridge_set_recompiler_enabled(recompiler);
    cemu_bridge_set_graphics_api(2); // Metal
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
