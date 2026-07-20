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
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>
#include <fcntl.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>

// The app crashed on the very first real on-device launch, before any game was even
// tapped - meaning before cemu_bridge_initialize()/CafeSystem::Initialize() ever run.
// Root cause turned out to be a GPU/AGX driver panic (BIF0 page fault), which is NOT
// delivered to the app as a normal POSIX signal - it's a hardware/firmware-level
// event, so the signal handler below is a supplement, not the primary diagnostic.
// The checkpoint trail is what actually matters here: written via synchronous
// write() calls that hit disk immediately, so even an abrupt un-catchable
// termination leaves a record of exactly how far execution got. The signal handler
// is installed via a high-priority (101 - earliest allowed for user code) C++
// constructor rather than from Swift/App init, in case there's also a CPU-side
// crash in one of the ~90 linked Cemu engine libraries' static initializers, which
// run before main() - too early for a Swift-installed handler to catch. Writes to
// Documents/CemuCrashLog.txt - already Finder/Files-visible thanks to
// UIFileSharingEnabled - so it's unambiguously "the" Cemu crash, not some unrelated
// system daemon's diagnostic (which is what happened hunting through iOS's own
// Analytics Data crash list, and why LiveContainer's own crash reports don't help
// either - it hosts the guest binary in its own process, so OS-level reports get
// attributed to "LiveContainer", not "Cemu").
namespace {
    int g_crashLogFd = -1;

    void cemu_crash_write(const char* s) {
        if (g_crashLogFd >= 0 && s) write(g_crashLogFd, s, strlen(s));
    }

    // Only async-signal-safe calls (write/backtrace_symbols_fd) inside the handler
    // itself - no malloc, no snprintf, no Objective-C/Swift runtime calls.
    void cemu_crash_signal_handler(int signum) {
        cemu_crash_write("\n=== CEMU CRASH: signal ");
        char digits[16];
        int n = signum, i = 0;
        if (n == 0) digits[i++] = '0';
        while (n > 0) { digits[i++] = '0' + (n % 10); n /= 10; }
        for (int j = 0; j < i / 2; j++) { char t = digits[j]; digits[j] = digits[i - 1 - j]; digits[i - 1 - j] = t; }
        if (g_crashLogFd >= 0) write(g_crashLogFd, digits, i);
        cemu_crash_write(" ===\n");

        void* frames[64];
        int count = backtrace(frames, 64);
        if (g_crashLogFd >= 0) backtrace_symbols_fd(frames, count, g_crashLogFd);

        // Re-raise with the default handler so iOS still generates its own real
        // crash report too - this is a supplement, not a replacement.
        signal(signum, SIG_DFL);
        raise(signum);
    }

    // Not signal-handler code - runs at normal startup, snprintf is fine here.
    void cemu_crash_open_log() {
        if (g_crashLogFd >= 0)
            return;
        const char* home = getenv("HOME");
        if (!home)
            return;
        char path[1024];
        snprintf(path, sizeof(path), "%s/Documents/CemuCrashLog.txt", home);
        g_crashLogFd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);

        // backtrace() isn't async-signal-safe (it can lazily allocate/lock on first
        // use), which is exactly the risk on the crashes it's meant to catch - a call
        // from inside the signal handler could hang/deadlock instead of completing.
        // Pre-warm its one-time internal state here, during normal startup, so the
        // handler's later call is just a fast, already-initialized path.
        void* warm[4];
        backtrace(warm, 4);
    }
}

extern "C" __attribute__((constructor(101)))
void cemu_bridge_install_early_crash_handler() {
    cemu_crash_open_log();
    cemu_crash_write("=== Cemu process started (early constructor) ===\n");
    int sigs[] = {SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE};
    for (int s : sigs)
        signal(s, cemu_crash_signal_handler);
}

void cemu_bridge_log_checkpoint(const char* message) {
    cemu_crash_open_log(); // idempotent; in case the constructor somehow didn't run
    cemu_crash_write(message);
    cemu_crash_write("\n");
}

#if defined(CEMU_CORE_AVAILABLE)
    // Real Cemu engine headers. These only resolve once the core is built for iOS.
    #include "Cafe/CafeSystem.h"
    #include "config/ActiveSettings.h"
    #include "config/LaunchSettings.h"
    #include "Cafe/HW/Latte/Core/LatteDraw.h"
    #include "gui/interface/WindowSystem.h"
    #include "Cafe/HW/Latte/Renderer/Renderer.h"
    #include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
    #include "Cafe/HW/Espresso/PPCState.h"
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

    std::string& statusBuf() {
        // Static storage; single-writer from the emulation control path is fine for a status string.
        static thread_local std::string buf;
        return buf;
    }

    const char* setStatus(const char* s) {
        statusBuf() = s ? s : "";
        return statusBuf().c_str();
    }

    // Read-only: does NOT overwrite the buffer, unlike setStatus(). Used by
    // cemu_bridge_status_text() so it returns whatever the last real setStatus() call
    // actually said (e.g. "Invalid RPX", a specific boot failure reason) instead of
    // silently discarding it in favor of a freshly recomputed generic string.
    const char* getStatus() {
        return statusBuf().c_str();
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
    // Desktop Cemu only ever calls PPCTimer_init() from main.cpp's CemuCommonInit(),
    // which this iOS bridge never runs (it goes straight to CafeSystem::Initialize()).
    // Without it, _rdtscFrequency stays 0 forever, and LaunchForegroundTitle() calls
    // PPCTimer_waitForInit() - `while (!PPCTimer_isReady()) sleep_for(10ms);` -
    // synchronously on whatever thread boot() runs on (the main/UI thread here, since
    // GameManager.launchGame() never dispatches off @MainActor). Nothing was ever
    // going to make that loop exit: the freeze on tapping play (checkpoint log stops
    // right after "about to call engine.boot()", never reaches "returned") was this
    // spin loop running forever, not a crash and not slow interpreter execution. Call
    // it here, as early as possible per the original comment - it spawns its own
    // ~3-second background calibration thread, so this doesn't block anything itself.
    PPCTimer_init();
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

    // ActiveSettings::GetCPUMode() resolves CPUMode::Auto (the default with no game
    // profile loaded) to a recompiler/JIT mode on every device - it never picks the
    // interpreter on its own (config/ActiveSettings.cpp). That means
    // PPCRecompiler_init() (CafeSystem.cpp's PrepareForegroundTitleFromStandaloneRPX)
    // always reaches PPCRecompilerAArch64Gen_generateRecompilerInterfaceFunctions(),
    // which - even after the eager-static-init fix - still eventually calls
    // Xbyak_aarch64::MmapAllocator::alloc() (mmap with PROT_EXEC) on first actual
    // boot. Whether a sideloaded/unsigned iOS process can ever get genuine
    // executable-memory allocation via mmap (as opposed to LiveContainer's JIT trick
    // only re-flagging already-mapped pages executable) is a separate, harder
    // open question. Force the interpreter for now so title boot doesn't depend on
    // that answer - M2's exit test is about the interpreter/OS-HLE stack, not JIT
    // performance (see ROADMAP.md: the JIT and "a full PPC interpreter fallback"
    // are explicitly two distinct capabilities).
    LaunchSettings::SetForceInterpreter(true);

    CafeSystem::Initialize();
    setStatus("Cemu core initialized.");
#else
    (void)mlcPath;
    setStatus("Real engine not compiled into this build yet (see ROADMAP.md M1).");
#endif
}

void cemu_bridge_register_render_surface(void* uiView, int width, int height, double dpiScale) {
#if defined(CEMU_CORE_AVAILABLE)
    // M3 groundwork (ROADMAP.md): the real native Metal renderer
    // (Cafe/HW/Latte/Renderer/Metal/) has never actually been wired to a surface on
    // iOS - MetalRenderer::InitializeLayer() is, upstream, only ever called from the
    // desktop wx GUI's MetalCanvas.cpp (excluded from this build entirely), so
    // g_renderer was permanently null and WindowSystem::GetWindowInfo().window_main
    // was permanently unset before this. Call this once, from Swift, as soon as a
    // real UIView exists - and before booting a title, since
    // Latte_ThreadEntry() (LatteThread.cpp) reads WindowSystem::GetWindowPhysSize()
    // synchronously at GPU-thread startup, before any frame is drawn.
    auto& windowInfo = WindowSystem::GetWindowInfo();
    windowInfo.window_main.surface = uiView;
    windowInfo.width = width;
    windowInfo.height = height;
    windowInfo.phys_width = (int32_t)(width * dpiScale);
    windowInfo.phys_height = (int32_t)(height * dpiScale);
    windowInfo.dpi_scale = dpiScale;

    if (!g_renderer)
        g_renderer = std::make_unique<MetalRenderer>();

    // width/height here are logical (point) size, matching desktop's wxSize usage -
    // MetalLayerHandle internally multiplies by the layer's own contentsScaleFactor
    // (computed in MetalLayer.mm's CreateMetalLayer) to get the physical drawable size.
    MetalRenderer::GetInstance()->InitializeLayer({width, height}, /*mainWindow=*/true);
    setStatus("Render surface registered.");
#else
    (void)uiView; (void)width; (void)height; (void)dpiScale;
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
    // Don't unconditionally recompute a generic string here - that was discarding
    // the specific message the last setStatus() call actually set (e.g. "Invalid
    // RPX", a boot failure reason) on every single read. Only fall back to a
    // computed default when nothing specific has been set yet.
    if (statusBuf().empty())
        setStatus(CafeSystem::IsTitleRunning() ? "Title running." : "Core ready (no title running).");
    return getStatus();
#else
    if (statusBuf().empty())
        setStatus("Real engine not compiled into this build yet (see ROADMAP.md M1).");
    return getStatus();
#endif
}
