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
#import <Foundation/Foundation.h>

#include <string>
#include <atomic>
#include <mutex>
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>
#include <fcntl.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <exception>
#include <typeinfo>

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

    // The signal handler above catches the SIGABRT but cannot answer the question
    // that abort actually poses. A trace ending
    //   CafeSystem::Initialize -> cemuLog_log<char const*&> -> fmt::detail::vformat_to
    //   -> fmt::v12::report_error -> abort
    // says an fmt formatting failure reached std::terminate out of a log call, but
    // not WHICH log call and not what fmt objected to. Worse, it should not have been
    // fatal at all: cemuLogDetail::iosFormatOrRaw() (CemuLogging.h) wraps the whole
    // fmt::vformat() call in try / catch(const std::exception&) / catch(...) for
    // exactly this reason, and that guard is present in the build that crashed. So
    // one of two quite different things is true - either the throw escapes from a
    // path that guard does not cover, or the abort is not an escaping C++ exception
    // in the first place (fmt built with FMT_THROW mapped to assert_fail, or an
    // unwind that cannot find the landing pad) - and the backtrace alone cannot
    // distinguish them.
    //
    // std::terminate is the one place both questions are answerable: the in-flight
    // exception is still recoverable there via std::current_exception(). Rethrow it
    // to get its dynamic type and what(), write both to the crash log, then chain to
    // the previous handler (_objc_terminate, installed by the Objective-C runtime)
    // and abort so the signal handler still appends its backtrace exactly as before.
    // Purely additive: nothing that used to be reported stops being reported.
    //
    // Not signal-handler context, so typeid/what()/malloc are all legitimate here.
    std::terminate_handler g_previousTerminateHandler = nullptr;

    void cemu_terminate_handler() {
        cemu_crash_open_log(); // idempotent
        cemu_crash_write("\n=== CEMU TERMINATE ===\n");
        if (std::exception_ptr pending = std::current_exception())
        {
            try
            {
                std::rethrow_exception(pending);
            }
            catch (const std::exception& ex)
            {
                cemu_crash_write("uncaught C++ exception, type: ");
                cemu_crash_write(typeid(ex).name());
                cemu_crash_write("\nwhat(): ");
                cemu_crash_write(ex.what() ? ex.what() : "(none)");
                cemu_crash_write("\n");
            }
            catch (...)
            {
                cemu_crash_write("uncaught exception not derived from std::exception\n");
            }
        }
        else
        {
            // This branch is itself the answer to the second hypothesis: it means the
            // abort did NOT come from an escaping C++ throw, so no catch block
            // anywhere could ever have stopped it.
            cemu_crash_write("terminate called with no in-flight exception\n");
        }
        if (g_previousTerminateHandler && g_previousTerminateHandler != cemu_terminate_handler)
            g_previousTerminateHandler();
        abort();
    }
}

extern "C" __attribute__((constructor(101)))
void cemu_bridge_install_early_crash_handler() {
    cemu_crash_open_log();
    cemu_crash_write("=== Cemu process started (early constructor) ===\n");
    int sigs[] = {SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE};
    for (int s : sigs)
        signal(s, cemu_crash_signal_handler);
    // Installed from the same constructor, and for the same reason: an uncaught throw
    // out of one of the ~90 linked engine libraries' static initializers happens
    // before main(), too early for anything installed from Swift to see it.
    g_previousTerminateHandler = std::set_terminate(cemu_terminate_handler);
}

void cemu_bridge_log_checkpoint(const char* message) {
    cemu_crash_open_log(); // idempotent; in case the constructor somehow didn't run
    cemu_crash_write(message);
    cemu_crash_write("\n");
}

#if defined(CEMU_CORE_AVAILABLE)
    // Real Cemu engine headers. These only resolve once the core is built for iOS.
    #include "Cafe/CafeSystem.h"
    #include "Cemu/Logging/CemuLogging.h"
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

    // One status string for the whole bridge, not one per thread. It used to be a
    // `static thread_local std::string`, which quietly broke the only thing this
    // string exists for. The writers and the reader are never on the same thread:
    // GameManager.registerRenderSurface() runs the whole init/boot sequence inside a
    // Task.detached, so "Invalid RPX.", "Unable to mount title", "Title launched."
    // and friends were written to a background thread's copy - while the UI reads it
    // from `await MainActor.run { engine.refreshStatus() }`, i.e. the main thread,
    // whose copy those writes never touched.
    //
    // Worse than just losing them, because the main thread's copy is not empty
    // either: cemu_bridge_register_render_surface() is called from makeUIView() and
    // therefore does write "Render surface registered." there. So the empty-check in
    // cemu_bridge_status_text() found a value, returned it, and the UI showed a
    // success message from the surface registration no matter how the boot afterwards
    // actually went - including on the .error path, which is precisely where the
    // specific reason was needed. The comment on that function already described
    // preserving the last real message as the whole point; thread_local made it
    // impossible.
    std::mutex g_statusMutex;
    std::string g_statusText;

    void setStatus(const char* s) {
        std::lock_guard<std::mutex> lock(g_statusMutex);
        g_statusText = s ? s : "";
    }

    bool statusIsEmpty() {
        std::lock_guard<std::mutex> lock(g_statusMutex);
        return g_statusText.empty();
    }

    // Returns a pointer that stays valid until the SAME thread calls this again.
    // Handing out g_statusText.c_str() directly would be a data race - a background
    // boot thread can reassign that string while the main thread is reading it - so
    // copy it under the lock into a per-thread snapshot and return that. Swift's
    // String(cString:) copies immediately, so one call's worth of lifetime is all any
    // caller needs.
    const char* getStatus() {
        static thread_local std::string snapshot;
        {
            std::lock_guard<std::mutex> lock(g_statusMutex);
            snapshot = g_statusText;
        }
        return snapshot.c_str();
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

    // The DATA path is the one exception, and it used to be wrong: it was passed
    // userDataPath along with everything else, but nothing writes to it - it is where
    // Cemu reads the files it ships with. Two consumers survive into the iOS build:
    // CafeSystem::LoadSharedData() reads GetDataPath("resources/sharedFonts/*.ttf")
    // and GameProfile::Load() falls back to GetDataPath("gameProfiles/default/
    // <titleid>.ini"). Pointing it at Documents/mlc meant both looked in a directory
    // that only ever contains user data, so LoadSharedData() logged "Shared font
    // CafeCn.ttf is not present" and installed a stub region, and every per-title
    // game profile silently resolved to the default - including the position
    // invariance MetalRenderer::ResolvePositionInvariance() reads at Initialize().
    // Those files now ship in the app bundle (ci/copy-bundle-data.sh, wired up as a
    // postBuildScript in src/ios/project.yml), so point the data path there.
    //
    // The bundle is read-only, which is fine: SetPaths() only TestWriteAccess()es
    // userDataPath, configPath and cachePath. GameProfile::Save() likewise writes to
    // GetConfigPath("gameProfiles"), not here.
    fs::path dataPath = userDataPath;
    NSString* bundleResourcePath = [[NSBundle mainBundle] resourcePath];
    if (bundleResourcePath.length > 0)
        dataPath = fs::path(bundleResourcePath.fileSystemRepresentation);

    std::set<fs::path> failedWriteAccess;
    ActiveSettings::SetPaths(/*isPortableMode=*/true, userDataPath, userDataPath, userDataPath,
        userDataPath / "cache", dataPath, failedWriteAccess);

    // Open log.txt here rather than leaving it to the first cemu_initForGame(), which
    // is several hundred lines and one whole CafeSystem::Initialize() later. Until it
    // is open, every cemuLog_log() line sits in LogContext.text_cache in RAM and is
    // discarded outright if the process dies first - which is precisely what happened
    // on the crash this is being changed for: the run that aborted inside
    // CafeSystem::Initialize() left a log.txt with not one line in it, so the only
    // evidence of a failure inside a LOGGING call was a backtrace. Every launch that
    // got past Initialize() wrote a complete log, which is the opposite of the
    // selection you want from a diagnostic. cemuLog_GetLogFilePath() resolves against
    // ActiveSettings, so this has to come after SetPaths() above, not before.
    cemuLog_createLogFile(false);

    // Say outright whether the bundled data actually made it into this build, so a
    // device log answers the question instead of it having to be inferred from a
    // downstream symptom several hundred lines later. The error_code overloads, not
    // the throwing ones: an unhandled exception this early in boot is std::terminate
    // with nothing useful logged, and "could not tell" is reported the same as "no".
    std::error_code fontsEc, profilesEc;
    const bool haveFonts = fs::exists(dataPath / "resources" / "sharedFonts" / "CafeStd.ttf", fontsEc);
    const bool haveProfiles = fs::exists(dataPath / "gameProfiles" / "default", profilesEc);
    cemuLog_log(LogType::Force, "iOS data path: {} (shared fonts present: {}, default game profiles present: {})",
        _pathToUtf8(dataPath), haveFonts, haveProfiles);

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

    // MetalRenderer's constructor (and InitializeLayer(), transitively) makes real
    // Objective-C/Metal API calls - device/queue/texture creation, and compiling
    // utilityShaderSource (a raw MSL string) via newLibrary(source:...) at runtime.
    // The first-ever live device test of this path threw an uncaught NSException
    // from inside the constructor (confirmed via dSYM symbolication of the crash
    // address to MetalRenderer::MetalRenderer() specifically) - this .cpp file can't
    // @try/@catch it (plain C++, not Objective-C++), but this .mm file can, since
    // ObjC and C++ exceptions share one unwinding mechanism on Darwin. M2's actual
    // exit criteria is the interpreter/OS-HLE stack, not working rendering (that's
    // M3, separately) - so a renderer construction failure shouldn't be allowed to
    // take down the whole app. Catch it, log the real reason (rather than continuing
    // to guess blind), and proceed without a renderer.
    @try {
        if (!g_renderer)
            g_renderer = std::make_unique<MetalRenderer>();

        // width/height are LOGICAL POINTS, matching the desktop caller
        // (wxgui/canvas/MetalCanvas.cpp passes a wxSize). Points get converted to
        // physical pixels exactly once on each path that needs them: phys_width/
        // phys_height above, and MetalLayerHandle's ctor -> setDrawableSize()
        // (points * the layer's backing scale) below.
        //
        // This used to be passed as pixels (MetalView.swift multiplied by
        // UIScreen.main.scale before calling in), which meant BOTH of those
        // conversions multiplied by the scale a second time. An earlier version of
        // this comment dismissed that as "wasteful but not visually broken", on the
        // grounds that phys_width/phys_height were inflated by the same factor so
        // the output-blit viewport (LatteRenderTarget_getScreenImageArea, driven by
        // GetWindowPhysSize()) stayed proportionally consistent with the oversized
        // drawable. That reasoning only covers geometry, and geometry was never the
        // risk. On a 2x iPad the drawable came out around 4096x5464 - roughly 89 MB
        // per drawable, ~268 MB for a triple-buffered swapchain - and nextDrawable()
        // is entitled to simply return nil rather than hand that out. When it does,
        // MetalRenderer::SwapBuffer() and DrawBackbufferQuad() both return silently
        // (see AcquireDrawable's callers), so the symptom is a black screen with no
        // error anywhere: exactly the failure being chased. A 4x allocation
        // overshoot is not a cosmetic issue when allocation is what fails.
        MetalRenderer::GetInstance()->InitializeLayer({width, height}, /*mainWindow=*/true);
        setStatus("Render surface registered.");
    } @catch (NSException* exception) {
        g_renderer.reset();
        std::string message = "MetalRenderer construction/InitializeLayer threw: ";
        message += exception.name.UTF8String;
        message += " - ";
        message += exception.reason.UTF8String;
        cemu_bridge_log_checkpoint(message.c_str());
        setStatus("Render surface registration failed (see crash log).");
    }
#else
    (void)uiView; (void)width; (void)height; (void)dpiScale;
#endif
}

void cemu_bridge_register_pad_render_surface(void* uiView, int width, int height, double dpiScale) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!uiView || width <= 0 || height <= 0)
        return;
    if (!g_renderer) {
        // The TV surface is registered first and constructs the renderer; without it
        // there is nothing to attach a second layer to. Say so rather than silently
        // doing nothing, because the caller's whole display-routing decision is now
        // wrong and only the log can tell anyone that.
        cemuLog_log(LogType::Force, "iOS: cannot register the GamePad surface - no renderer yet (the TV surface must be registered first)");
        return;
    }

    // pad_open drives WindowSystem::GetPadWindowSize/PhysSize/DPIScale, which
    // LatteRenderTarget_getScreenImageArea() uses to letterbox the DRC image. Left
    // false those all report 0 and the pad blit would be laid out into nothing.
    auto& windowInfo = WindowSystem::GetWindowInfo();
    windowInfo.window_pad.surface = uiView;
    windowInfo.pad_width = width;
    windowInfo.pad_height = height;
    windowInfo.phys_pad_width = (int32_t)(width * dpiScale);
    windowInfo.phys_pad_height = (int32_t)(height * dpiScale);
    windowInfo.pad_dpi_scale = dpiScale;
    windowInfo.pad_open = true;

    // Same @try/@catch reasoning as the TV surface above: InitializeLayer() makes real
    // Objective-C/Metal calls and a throw here must not take down a running title. If
    // it does throw, undo pad_open so the engine goes back to believing there is no
    // pad window at all - which is a configuration it handles correctly - rather than
    // one it thinks exists but has no layer.
    @try {
        MetalRenderer::GetInstance()->InitializeLayer({width, height}, /*mainWindow=*/false);
        cemuLog_log(LogType::Force, "iOS: GamePad (DRC) screen surface registered, {}x{} points at {}x scale", width, height, dpiScale);
    } @catch (NSException* exception) {
        windowInfo.pad_open = false;
        windowInfo.window_pad.surface = nullptr;
        std::string message = "GamePad surface InitializeLayer threw: ";
        message += exception.name.UTF8String;
        message += " - ";
        message += exception.reason.UTF8String;
        cemu_bridge_log_checkpoint(message.c_str());
        cemuLog_log(LogType::Force, "iOS: {}", message);
    }
#else
    (void)uiView; (void)width; (void)height; (void)dpiScale;
#endif
}

void cemu_bridge_release_pad_render_surface(void) {
#if defined(CEMU_CORE_AVAILABLE)
    auto& windowInfo = WindowSystem::GetWindowInfo();
    // Flip pad_open first. Every Latte-side consumer of the pad geometry reads it, so
    // this stops new pad work being laid out even before the layer is actually gone.
    windowInfo.pad_open = false;
    windowInfo.pad_width = 0;
    windowInfo.pad_height = 0;
    windowInfo.phys_pad_width = 0;
    windowInfo.phys_pad_height = 0;
    if (!g_renderer)
        return;
    // Deferred on purpose - see MetalRenderer::RequestPadLayerRelease(). The hosting
    // view must stay alive and must keep the layer as a sublayer: the C++ side only
    // drops the +1 that CreateMetalLayer() took, and the view's own reference is what
    // keeps the CAMetalLayer from being deallocated on the GPU thread.
    MetalRenderer::GetInstance()->RequestPadLayerRelease();
    cemuLog_log(LogType::Force, "iOS: GamePad (DRC) surface release requested - the GPU thread will drop it at its next frame boundary");
#endif
}

bool cemu_bridge_has_pad_render_surface(void) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!g_renderer)
        return false;
    return MetalRenderer::GetInstance()->IsPadWindowActive();
#else
    return false;
#endif
}

void cemu_bridge_resize_render_surface(int width, int height, double dpiScale, bool mainWindow) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!g_renderer || width <= 0 || height <= 0)
        return;

    auto& windowInfo = WindowSystem::GetWindowInfo();
    if (mainWindow) {
        windowInfo.width = width;
        windowInfo.height = height;
        windowInfo.phys_width = (int32_t)(width * dpiScale);
        windowInfo.phys_height = (int32_t)(height * dpiScale);
        windowInfo.dpi_scale = dpiScale;
    } else {
        if (!windowInfo.pad_open)
            return;
        windowInfo.pad_width = width;
        windowInfo.pad_height = height;
        windowInfo.phys_pad_width = (int32_t)(width * dpiScale);
        windowInfo.phys_pad_height = (int32_t)(height * dpiScale);
        windowInfo.pad_dpi_scale = dpiScale;
    }

    @try {
        MetalRenderer::GetInstance()->ResizeLayerAndFrame({width, height}, (float)dpiScale, mainWindow);
        cemuLog_log(LogType::Force, "iOS: resized the {} surface to {}x{} points at {}x scale", mainWindow ? "TV" : "GamePad", width, height, dpiScale);
    } @catch (NSException* exception) {
        cemuLog_log(LogType::Force, "iOS: resizing the {} surface threw: {} - {}", mainWindow ? "TV" : "GamePad", exception.name.UTF8String, exception.reason.UTF8String);
    }
#else
    (void)width; (void)height; (void)dpiScale; (void)mainWindow;
#endif
}

void cemu_bridge_log_line(const char* message) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!message)
        return;
    // Deliberately the zero-argument form: the iOS cemuLog_log() template forwards a
    // call with no varargs straight to the std::string_view overload without going
    // through fmt, so a caller-supplied string containing braces is logged verbatim
    // instead of being treated as a format string and throwing fmt::format_error
    // (see the block comment in CemuLogging.h - an unhandled throw out of a log call
    // is std::terminate).
    cemuLog_log(LogType::Force, message);
#else
    (void)message;
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

    // Last chance to have a renderer before the GPU thread starts, so retry
    // construction here if cemu_bridge_register_render_surface()'s own attempt (which
    // has its own @try/@catch) failed and left g_renderer null.
    //
    // On the actual ordering - an earlier version of this comment claimed
    // PrepareForegroundTitleFromStandaloneRPX() -> PrepareExecutable() calls
    // Latte_Start() and then spins on g_isGPUInitFinished before returning. It does
    // NOT. PrepareExecutable() is CafeSystem.cpp:775 and does neither of those
    // things; PrepareForegroundTitleFromStandaloneRPX() only mounts the RPX, derives
    // a placeholder title id, loads the game profile and sets up memory/recompiler,
    // then returns. Latte_Start() is called from cemu_initForGame()
    // (CafeSystem.cpp:416), which runs later on the DETACHED TITLE THREAD spawned by
    // LaunchForegroundTitle() -> _LaunchTitleThread(), i.e. after
    // cemu_bridge_boot_rpx() has already returned to Swift. Anyone tracing a hang or
    // a black screen from that old comment would have been looking at the wrong
    // thread and the wrong function entirely.
    //
    // What that means practically: this retry still has to happen before
    // LaunchForegroundTitle(), because Latte_ThreadEntry() (LatteThread.cpp) reaches
    // g_renderer->Initialize() with no null check of its own. Same @try/@catch
    // reasoning as above - a renderer construction failure is real (confirmed via
    // live device crash) but shouldn't block M2's exit criteria (interpreter/OS-HLE
    // stack), only M3 (rendering). If this also fails, g_renderer stays null and
    // Latte_ThreadEntry() handles that case: it signals both flags callers spin on
    // (sLatteThreadFinishedInit, g_isGPUInitFinished) without touching g_renderer,
    // rather than null-dereferencing or leaving those waits hanging forever.
    if (!g_renderer)
    {
        @try {
            g_renderer = std::make_unique<MetalRenderer>();
        } @catch (NSException* exception) {
            g_renderer.reset();
            std::string message = "MetalRenderer construction (retry, boot_rpx) threw: ";
            message += exception.name.UTF8String;
            message += " - ";
            message += exception.reason.UTF8String;
            cemu_bridge_log_checkpoint(message.c_str());
        }
    }

    namespace fs = std::filesystem;
    cemu_bridge_log_checkpoint("boot_rpx: about to call PrepareForegroundTitleFromStandaloneRPX");
    auto status = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(fs::path(rpxPath));
    cemu_bridge_log_checkpoint("boot_rpx: PrepareForegroundTitleFromStandaloneRPX returned");
    switch (status) {
        case CafeSystem::PREPARE_STATUS_CODE::SUCCESS:
            cemu_bridge_log_checkpoint("boot_rpx: about to call LaunchForegroundTitle");
            CafeSystem::LaunchForegroundTitle();
            cemu_bridge_log_checkpoint("boot_rpx: LaunchForegroundTitle returned");
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

#if defined(CEMU_CORE_AVAILABLE)
// Defined in src/gui/iosgui/IOSWindowSystem.cpp - the platform shim that receives
// the engine's fps readings via WindowSystem::UpdateWindowTitles(). That shim has no
// header of its own, so declare it here rather than inventing one for a single
// function.
double IOSWindowSystem_GetLastFPS();
#endif

double cemu_bridge_get_fps(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return IOSWindowSystem_GetLastFPS();
#else
    return 0.0;
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
    if (statusIsEmpty())
        setStatus(CafeSystem::IsTitleRunning() ? "Title running." : "Core ready (no title running).");
    return getStatus();
#else
    if (statusIsEmpty())
        setStatus("Real engine not compiled into this build yet (see ROADMAP.md M1).");
    return getStatus();
#endif
}
