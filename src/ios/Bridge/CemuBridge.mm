//
//  CemuBridge.mm
//  Objective-C++ implementation of the Swift <-> Cemu bridge.
//
//  Build modes:
//    * CEMU_CORE_AVAILABLE defined  -> calls the real CafeSystem (ROADMAP.md M1+).
//    * otherwise                    -> honest no-op stubs that report CORE_NOT_BUILT.
//
//  There is deliberately NO fake emulation here. When the core isn't linked we
//  say so; we never pretend a game is running.
//
#import "CemuBridge.h"

#include <string>
#include <atomic>

#if defined(CEMU_CORE_AVAILABLE)
    // Real Cemu engine headers. These only resolve once the core is built for iOS.
    #include "Cafe/CafeSystem.h"
    #include "config/ActiveSettings.h"
    #include "Cafe/HW/Latte/Core/LatteDraw.h"
    #include <filesystem>
    #include <set>

    // Globals/functions desktop Cemu defines outside any library CMake target links
    // into this app, so they were undefined at link time:
    //   - g_isGPUInitFinished (Cafe/CafeSystem.h) is defined in src/main.cpp, which
    //     belongs to the desktop CemuBin executable target - never linked here.
    //   - g_vulkan_available (Vulkan/VulkanAPI.h) is defined in VulkanAPI.cpp, which
    //     is intentionally excluded from the iOS build entirely (no Vulkan/MoltenVK -
    //     this fork renders via the native Metal backend, see ROADMAP.md M3).
    // Both are referenced via extern by code that does build (CafeSystem.cpp,
    // Renderer.cpp), so something has to provide the definition.
    std::atomic_bool g_isGPUInitFinished = false;
    bool g_vulkan_available = false;

    // LatteDraw_cleanupAfterFrame (Cafe/HW/Latte/Core/LatteDraw.h) is only defined in
    // OpenGLRendererCore.cpp (excluded on iOS), but called unconditionally every
    // frame from shared Latte code regardless of active backend. Its real body
    // evicts OpenGL's own index-buffer cache - nothing Metal needs, so a no-op here
    // is correct, not just a stopgap.
    void LatteDraw_cleanupAfterFrame() {}
#endif

namespace {
    std::atomic<bool> g_initialized{false};

    const char* setStatus(const char* s) {
        // Static storage; single-writer from the emulation control path is fine for a status string.
        static thread_local std::string buf;
        buf = s ? s : "";
        return buf.c_str();
    }
}

bool cemu_bridge_core_available(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return true;
#else
    return false;
#endif
}

void cemu_bridge_initialize(const char* mlcPath) {
#if defined(CEMU_CORE_AVAILABLE)
    if (g_initialized.exchange(true))
        return;
    // CafeSystem::Initialize() calls ActiveSettings::GetMlcPath() in its very first
    // few lines (to log "mlc01 path: ..."), which without SetPaths() first resolves
    // against a default-constructed (empty) s_user_data_path - i.e. a relative
    // "mlc01" path resolved against whatever the process's cwd happens to be (the
    // read-only app bundle, on iOS), not the writable Documents dir GameManager.swift
    // actually passes in here. Route everything (user data, config, cache, mlc01)
    // under that same Documents-rooted path so it's writable and, since
    // UIFileSharingEnabled is on, visible/pullable via Finder/Files for diagnosis.
    namespace fs = std::filesystem;
    fs::path userDataPath = (mlcPath && mlcPath[0] != '\0') ? fs::path(mlcPath) : fs::path(".");
    std::error_code ec;
    fs::create_directories(userDataPath, ec);
    std::set<fs::path> failedWriteAccess;
    ActiveSettings::SetPaths(/*isPortableMode=*/true, userDataPath, userDataPath, userDataPath,
        userDataPath / "cache", userDataPath, failedWriteAccess);
    CafeSystem::Initialize();
    setStatus("Cemu core initialized.");
#else
    (void)mlcPath;
    setStatus("Real engine not compiled into this build yet (see ROADMAP.md M1).");
#endif
}

CemuBridgeStatus cemu_bridge_boot_rpx(const char* rpxPath) {
    if (!rpxPath || rpxPath[0] == '\0') {
        setStatus("boot_rpx: empty path.");
        return CEMU_BRIDGE_BAD_ARG;
    }
#if defined(CEMU_CORE_AVAILABLE)
    if (!g_initialized.load())
        CafeSystem::Initialize();

    namespace fs = std::filesystem;
    auto status = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(fs::path(rpxPath));
    switch (status) {
        case CafeSystem::PREPARE_STATUS_CODE::SUCCESS:
            CafeSystem::LaunchForegroundTitle();
            setStatus("Title launched.");
            return CEMU_BRIDGE_OK;
        case CafeSystem::PREPARE_STATUS_CODE::INVALID_RPX:
            setStatus("Invalid RPX.");
            return CEMU_BRIDGE_INVALID_RPX;
        case CafeSystem::PREPARE_STATUS_CODE::UNABLE_TO_MOUNT:
            setStatus("Unable to mount title (bad/outdated path).");
            return CEMU_BRIDGE_UNABLE_TO_MOUNT;
    }
    setStatus("Unknown prepare status.");
    return CEMU_BRIDGE_UNABLE_TO_MOUNT;
#else
    (void)rpxPath;
    setStatus("Cannot boot: real engine not compiled into this build yet (ROADMAP.md M1).");
    return CEMU_BRIDGE_CORE_NOT_BUILT;
#endif
}

bool cemu_bridge_is_title_running(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return CafeSystem::IsTitleRunning();
#else
    return false;
#endif
}

void cemu_bridge_pause(void) {
#if defined(CEMU_CORE_AVAILABLE)
    CafeSystem::PauseTitle();
#endif
}

void cemu_bridge_resume(void) {
#if defined(CEMU_CORE_AVAILABLE)
    CafeSystem::ResumeTitle();
#endif
}

void cemu_bridge_shutdown_title(void) {
#if defined(CEMU_CORE_AVAILABLE)
    CafeSystem::ShutdownTitle();
    setStatus("Title shut down.");
#endif
}

void cemu_bridge_shutdown(void) {
#if defined(CEMU_CORE_AVAILABLE)
    CafeSystem::Shutdown();
    g_initialized.store(false);
    setStatus("Cemu core shut down.");
#endif
}

const char* cemu_bridge_status_text(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return setStatus(CafeSystem::IsTitleRunning() ? "Title running." : "Core ready (no title running).");
#else
    return setStatus("Real engine not compiled into this build yet (see ROADMAP.md M1).");
#endif
}
