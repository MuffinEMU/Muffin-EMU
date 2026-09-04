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
#include <sys/sysctl.h>
#include "Cemu/Logging/IOSLiveLog.h"

#include <string>
#include <cstring>
#include <atomic>
#include <thread>
#include <chrono>
#include <mutex>
#include <functional>
#include <cstdarg>
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <cstring>
#include <cmath>   // std::sqrt/std::isnan, for the stick-axis clamp
#include <cstdlib>
#include <cstdio>
#include <exception>
#include <typeinfo>
#include <mach/mach.h>
#include <os/proc.h>

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
    char g_crashLogPath[1024] = {0};

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
        // Kept, because "where is the crash log" turned out not to be answerable from
        // outside. The on-screen hint said Files > On My iPad > Cemu, which is where this
        // lands for a normally installed app and is not where it lands under
        // LiveContainer: LiveContainer redirects HOME per hosted app, so $HOME here is
        // its container and not Cemu's, and the file appears under LiveContainer's own
        // Documents. Guessing which of the two applies - and it depends on how early this
        // constructor runs relative to the redirect - is not something a person holding an
        // iPad should have to do. The path is right here at the moment it is opened, so
        // record it and let the app print the real one.
        snprintf(g_crashLogPath, sizeof(g_crashLogPath), "%s", path);

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

const char* cemu_bridge_crash_log_path(void) {
    cemu_crash_open_log(); // idempotent; the path is set as a side effect of opening
    return g_crashLogPath;
}

void cemu_bridge_log_checkpoint(const char* message) {
    cemu_crash_open_log(); // idempotent; in case the constructor somehow didn't run
    cemu_crash_write(message);
    cemu_crash_write("\n");
    // These checkpoints are the only record of the earliest part of a launch - they
    // bracket engine.initialize() and engine.boot(), and they are written before
    // cemuLog has a file to write to at all. Mirroring them into the live ring is what
    // makes the on-screen launch log a single timeline instead of the engine's half of
    // one. Cheap and safe: ios_live_log_push() copies, takes a short mutex of its own,
    // and is a relaxed atomic load away from free when collection is off.
    ios_live_log_push(message);
}

// ---------------------------------------------------------------------------
// Memory-pressure trail
//
// The commercial-title launch dies leaving an EMPTY crash log. The signal
// handler above caught nothing, the terminate handler caught nothing, and the
// launch log simply stops mid-boot. That combination is itself the diagnosis:
// nothing in-process was given a chance to run. On iOS the killer that behaves
// that way is jetsam - the OS reclaiming a process that crossed its memory
// limit. It is not a signal and it cannot be caught, so the only way to see it
// is to have already written the number down before the kill lands.
//
// Which is why every line here goes through cemu_bridge_log_checkpoint() - the
// raw synchronous write() to the crash-log fd - and not through cemuLog.
// cemuLog buffers, and a jetsam kill takes the buffer with it. A measurement is
// only evidence if it is on disk at the moment the process stops existing.
//
// This is instrumentation, not a fix. If the trail ends with a few MB available
// then jetsam is confirmed and the work moves to footprint. If it ends with
// plenty of headroom, jetsam is ruled out and this cost one log line - which is
// worth as much, because it is currently the leading theory.
namespace {
    std::atomic<bool> g_memWatchRunning{false};

    // phys_footprint is the figure jetsam actually bills the process for. Not
    // resident_size, which undercounts compressed and IOKit-backed pages and would
    // read as comfortable right up until the kill.
    uint64_t cemu_mem_footprint_bytes() {
        task_vm_info_data_t info{};
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
            return 0;
        return (uint64_t)info.phys_footprint;
    }

    void cemu_mem_write_line(const char* tag, uint64_t availableBytes, uint64_t footprintBytes) {
        char line[320];
        snprintf(line, sizeof(line),
                 "MEM %s: %llu MB still available to this process, %llu MB in use",
                 tag,
                 (unsigned long long)(availableBytes / (1024ull * 1024ull)),
                 (unsigned long long)(footprintBytes / (1024ull * 1024ull)));
        cemu_bridge_log_checkpoint(line);
    }
}

// A description of the machine this is running on, written once at startup and
// available to the UI on demand.
//
// WHY: until now the log recorded RAM and the iOS version and never once said WHICH
// DEVICE it ran on. Every diagnosis on this port so far has quietly depended on
// knowing the target is an A12Z iPad Pro - that is how "no BC texture formats" and
// "no mesh shaders" were reached at all. A log from anybody else's device would have
// been unactionable, because the first question about any of those findings is "what
// hardware?" and nothing in the file could answer it.
//
// The raw model identifier (iPad8,11 and so on) rather than a marketing name: there is
// no way to map identifiers to names without shipping a table that is out of date the
// moment a new device exists, and a wrong name is worse than an identifier anyone can
// look up.
static std::string g_deviceReport;

static std::string cemu_sysctl_string(const char* name)
{
    size_t len = 0;
    if (sysctlbyname(name, nullptr, &len, nullptr, 0) != 0 || len == 0)
        return std::string();
    std::string out(len, '\0');
    if (sysctlbyname(name, out.data(), &len, nullptr, 0) != 0)
        return std::string();
    if (!out.empty() && out.back() == '\0') out.pop_back();
    return out;
}

static uint64_t cemu_sysctl_u64(const char* name)
{
    uint64_t v = 0; size_t len = sizeof(v);
    if (sysctlbyname(name, &v, &len, nullptr, 0) == 0) return v;
    uint32_t v32 = 0; len = sizeof(v32);
    if (sysctlbyname(name, &v32, &len, nullptr, 0) == 0) return v32;
    return 0;
}

extern "C" const char* cemu_bridge_device_report(void)
{
    if (!g_deviceReport.empty())
        return g_deviceReport.c_str();

    const std::string model = cemu_sysctl_string("hw.machine");
    const uint64_t memBytes = cemu_sysctl_u64("hw.memsize");
    const uint64_t cores    = cemu_sysctl_u64("hw.ncpu");
    const uint64_t pcores   = cemu_sysctl_u64("hw.perflevel0.logicalcpu");
    const uint64_t ecores   = cemu_sysctl_u64("hw.perflevel1.logicalcpu");

    unsigned long long avail = 0, foot = 0;
    cemu_bridge_memory_status(&avail, &foot);

    char buf[1024];
    snprintf(buf, sizeof(buf),
        "device: %s | iOS %s | RAM %llu MB | cores %llu",
        model.empty() ? "unknown" : model.c_str(),
        [[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String],
        (unsigned long long)(memBytes / (1024ull * 1024ull)),
        (unsigned long long)cores);
    g_deviceReport = buf;

    if (pcores && ecores)
    {
        snprintf(buf, sizeof(buf), " (%llu perf + %llu eff)",
                 (unsigned long long)pcores, (unsigned long long)ecores);
        g_deviceReport += buf;
    }
    if (avail)
    {
        snprintf(buf, sizeof(buf), " | %llu MB available to this app before iOS kills it",
                 (unsigned long long)(avail / (1024ull * 1024ull)));
        g_deviceReport += buf;
    }
    // Two appends, not literal juxtaposition. BUILD_VERSION_STRING is a parenthesised
    // expression - ("2" "." "0" ...) - not a bare string literal, so writing
    // " | build " BUILD_VERSION_STRING parses as calling a char array.
    g_deviceReport += " | build ";
    g_deviceReport += BUILD_VERSION_STRING;
    return g_deviceReport.c_str();
}

bool cemu_bridge_memory_status(unsigned long long* availableBytes, unsigned long long* footprintBytes) {
    // os_proc_available_memory() is the headroom left before jetsam, as the OS
    // computes it. Distinct from free system RAM, and the only number that
    // predicts the kill. Returns 0 if called outside an app context.
    const uint64_t avail = (uint64_t)os_proc_available_memory();
    const uint64_t foot = cemu_mem_footprint_bytes();
    if (availableBytes) *availableBytes = (unsigned long long)avail;
    if (footprintBytes) *footprintBytes = (unsigned long long)foot;
    return avail != 0 || foot != 0;
}

void cemu_bridge_memory_note(const char* tag) {
    unsigned long long avail = 0, foot = 0;
    cemu_bridge_memory_status(&avail, &foot);
    cemu_mem_write_line(tag && tag[0] ? tag : "checkpoint", avail, foot);
}

void cemu_bridge_start_memory_watchdog(void) {
    if (g_memWatchRunning.exchange(true))
        return;

    // Named by string rather than via the UIKit constant so this file keeps its
    // existing Foundation-only dependency - the render-surface calls already take
    // a void* UIView for the same reason. The value is the documented one.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"UIApplicationDidReceiveMemoryWarningNotification"
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification* note) {
                    (void)note;
                    unsigned long long avail = 0, foot = 0;
                    cemu_bridge_memory_status(&avail, &foot);
                    cemu_mem_write_line("WARNING - iOS is asking for memory back", avail, foot);
                }];

    cemu_bridge_memory_note("baseline at startup");

    std::thread([] {
        // 100ms, because the launch this exists to explain died 563ms after
        // GX2Init. A sampler slower than that would have produced no samples at
        // all between the handover and the kill - which is exactly what the
        // 3-second Latte heartbeat did.
        uint64_t lastFootBucket = 0;
        uint64_t lastAvailBucket = UINT64_MAX;
        bool criticalAnnounced = false;
        auto lastForced = std::chrono::steady_clock::now();
        while (g_memWatchRunning.load())
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            unsigned long long avail = 0, foot = 0;
            if (!cemu_bridge_memory_status(&avail, &foot))
                continue;

            // Bucketed so a steady state costs nothing and only real movement is
            // written. An unbucketed 10 Hz sampler would bury the one line that
            // matters under thousands of identical ones.
            const uint64_t footBucket = foot / (32ull << 20);   // per 32 MB gained
            const uint64_t availBucket = avail / (64ull << 20); // per 64 MB lost
            const auto now = std::chrono::steady_clock::now();

            bool report = false;
            if (footBucket > lastFootBucket) report = true;
            if (availBucket < lastAvailBucket) report = true;
            if (now - lastForced >= std::chrono::seconds(5)) report = true;
            lastFootBucket = footBucket;
            lastAvailBucket = availBucket;

            if (report)
            {
                cemu_mem_write_line("sample", avail, foot);
                lastForced = now;
            }

            // One-shot, and phrased as a verdict because by the time headroom is
            // this low the kill is the expected outcome, not a possibility. If
            // this line is the last thing in the crash log, the question is
            // answered.
            if (!criticalAnnounced && avail > 0 && avail < (128ull << 20))
            {
                criticalAnnounced = true;
                cemu_mem_write_line("CRITICAL - a kill by iOS is likely imminent", avail, foot);
            }
        }
    }).detach();
}

#if defined(CEMU_CORE_AVAILABLE)
    // Real Cemu engine headers. These only resolve once the core is built for iOS.
    #include "Cafe/CafeSystem.h"
    #include "Cemu/Logging/CemuLogging.h"
    #include "config/ActiveSettings.h"
    #include "config/LaunchSettings.h"
    #include "Cafe/HW/Latte/Core/LatteDraw.h"
    #include "Cafe/HW/Latte/Core/Latte.h"
    #include "Cafe/HW/Latte/Core/LatteShader.h"
    #include "gui/interface/WindowSystem.h"
    #include "Cafe/HW/Latte/Renderer/Renderer.h"
    #include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
    #if defined(ENABLE_VULKAN)
    #include "Cafe/HW/Latte/Renderer/Vulkan/VulkanRenderer.h"
    #endif
    #include "config/CemuConfig.h"
    #include "audio/IAudioAPI.h"
    #include "Cafe/HW/Espresso/PPCState.h"
    #include "Cafe/HW/Espresso/Recompiler/PPCRecompiler.h"
    #include "util/crypto/aes128.h"
    #include "Common/version.h"
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

    // Defined at the bottom of src/input/InputManager.cpp, behind the same
    // CEMU_PLATFORM_IOS guard. Declared here rather than #including InputManager.h,
    // which drags in SDL2/SDL.h, VPADController.h and the rest of the input stack - all
    // of which build fine under CMake but would have to be made to work a second time
    // inside Xcode's own build of this one file. Same approach, and same reason, as the
    // IOSWindowSystem_GetLastFPS() declaration further down.
    void IOSInput_Initialize();
    void IOSInput_RefreshDevices();
    void IOSInput_SetButtonState(int button, bool pressed);
    void IOSInput_SetStickAxis(int stick, float x, float y);
    void IOSInput_ReleaseAllButtons();

    // Defined in src/gui/iosgui/IOSTitleLaunch.cpp - the real-title launch path, kept on
    // the CMake side for the same reason as the input shims above: TitleInfo.h and
    // TitleList.h drag in pugixml, ZArchive and the config stack, all of which the CMake
    // build already resolves and Xcode's build of this one file would have to be taught
    // a second time. The int it returns is the IOS_TITLE_LAUNCH_* enum in that file,
    // whose values are deliberately identical to the CemuBridgeStatus values below.
    void IOSTitleLaunch_InitializeTitleList();
    int IOSTitleLaunch_PrepareForegroundTitle(const char* path);
    int IOSTitleLaunch_ReloadAndCountKeys();

    // Defined in src/gui/iosgui/IOSTitleDecrypt.cpp - same "header-heavy code stays on
    // the CMake side" reasoning as IOSTitleLaunch_* above (FST.h pulls in the ncrypto/
    // config stack). Not wrapped in extern "C" like the Swift-facing functions below:
    // std::atomic_bool& and std::function aren't C-compatible types, and this is only
    // ever called from within this same C++ binary, never across the Swift boundary
    // directly - cemu_bridge_start_decrypt() below is what Swift actually calls.
    int IOSTitleDecrypt_ExtractToFolder(const char* srcPath, const char* destFolderPath,
        std::atomic_bool& cancelRequested,
        const std::function<void(uint64_t bytesWritten, uint32_t filesWritten)>& progressCallback);

    // Same file, same reasoning - writes a single .wua archive instead of a loose
    // code/, content/, meta/ tree. destPath here is the .wua FILE to create, not a
    // folder (cemu_bridge_start_decrypt's destFolderPath is a folder either way; which
    // one destPath means is decided entirely by the toWua flag it is called with).
    int IOSTitleDecrypt_ExtractToWua(const char* srcPath, const char* destPath,
        std::atomic_bool& cancelRequested,
        const std::function<void(uint64_t bytesWritten, uint32_t filesWritten)>& progressCallback);

    // Defined in src/gui/iosgui/IOSCoverArt.cpp - same "header-heavy code stays on the
    // CMake side" reasoning (TitleInfo.h pulls in pugixml and the config stack).
    std::string IOSCoverArt_DeriveGameTdbId(const char* romPath);

    // Defined in src/gui/iosgui/IOSDlcUpdateImport.cpp - same reasoning as
    // IOSCoverArt_DeriveGameTdbId above.
    bool IOSDlcUpdateImport_DeriveTitleId(const char* romPath, uint64_t* titleIdOut);
    uint64_t IOSDlcUpdateImport_DeriveBaseTitleId(uint64_t titleId);
    int IOSDlcUpdateImport_GetTitleType(uint64_t titleId);
    void IOSDlcUpdateImport_GetMlcTitlePathComponents(uint64_t titleId, char* outUpperHex, char* outLowerHex);
    bool IOSDlcUpdateImport_Inspect(const char* romPath, uint64_t* outTitleId, uint16_t* outVersion,
        int* outRegion, int* outInvalidReason);
    uint64_t IOSDlcUpdateImport_DeriveContentTitleId(uint64_t baseTitleId, bool isUpdate);

    // SDL's iOS joystick backend is a GameController.framework client, so bring it up on
    // the main thread even though cemu_bridge_initialize() itself runs on GameManager's
    // detached launch task. dispatch_sync is safe here specifically because that task is
    // fire-and-forget - registerRenderSurface() spawns it and returns immediately, so the
    // main thread is never waiting on this one and cannot deadlock against it.
    static void cemu_bridge_bring_up_input_on_main_thread() {
        void (^work)(void) = ^{
            @try {
                IOSInput_Initialize();
            } @catch (NSException* exception) {
                std::string message = "IOSInput_Initialize threw: ";
                message += exception.name.UTF8String;
                message += " - ";
                message += exception.reason.UTF8String;
                cemu_bridge_log_checkpoint(message.c_str());
            }
        };
        if ([NSThread isMainThread])
            work();
        else
            dispatch_sync(dispatch_get_main_queue(), work);
    }
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

    // BW-184: which CPU path this launch actually got, recorded at the point the
    // decision is made so the app can state it outright. Until this existed, the only
    // way to know whether the recompiler was live was to read cs_flags out of a crash
    // log after the fact - which is a thing the person who deliberately launched
    // through a JIT enabler to turn the recompiler ON should not have to do to find out
    // whether it worked.
    //
    // 0 is deliberately distinct from 1: "nothing has decided yet" (the engine has not
    // initialized) is not the same answer as "the interpreter". Written once from
    // whatever thread runs cemu_bridge_initialize(), read from the UI thread.
    [[maybe_unused]] constexpr int kCpuModeUndecided   = 0;
    [[maybe_unused]] constexpr int kCpuModeInterpreter = 1;
    [[maybe_unused]] constexpr int kCpuModeRecompiler  = 2;

    std::atomic<int> g_cpuMode{kCpuModeUndecided};
    std::mutex g_cpuModeDetailMutex;
    std::string g_cpuModeDetail;

    // vsnprintf rather than fmt::format: this runs inside the JIT probe, before the
    // engine is up, and a diagnostic string is not worth making dependent on Cemu's
    // formatting library being in this translation unit.
    [[maybe_unused]] __attribute__((format(printf, 1, 2)))
    std::string cpuModeDetailf(const char* format, ...) {
        char buffer[512];
        va_list args;
        va_start(args, format);
        const int written = vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);
        if (written < 0)
            return std::string();
        return std::string(buffer);
    }

    // The detail is set by the probe, which is the only code that knows WHICH of the
    // several disqualifying conditions applied. The mode is set by the probe's caller,
    // from its return value - two calls rather than one, so a specific reason can never
    // be overwritten by a generic one at the call site.
    [[maybe_unused]] void setCpuModeDetail(std::string detail) {
        std::lock_guard<std::mutex> lock(g_cpuModeDetailMutex);
        g_cpuModeDetail = std::move(detail);
    }

    // Same per-thread-snapshot contract as getStatus() above, for the same reason.
    [[maybe_unused]] const char* getCpuModeDetail() {
        static thread_local std::string snapshot;
        {
            std::lock_guard<std::mutex> lock(g_cpuModeDetailMutex);
            snapshot = g_cpuModeDetail;
        }
        return snapshot.c_str();
    }
}

// Defined further down, next to the rest of the timebase code, but called from
// cemu_bridge_boot_title() and cemu_bridge_shutdown_title() which both appear before it.
static void ios_timebase_ladder_start();
static void ios_timebase_ladder_stop();

#if defined(CEMU_CORE_AVAILABLE)
// ---------------------------------------------------------------------------
// BW-112: ask the kernel whether this process actually gets executable memory,
// instead of assuming it does not.
//
// Every iOS build up to now called LaunchSettings::SetForceInterpreter(true)
// unconditionally a few lines below. That was a bring-up hedge from a point where
// nobody knew whether a sideloaded process can obtain genuine PROT_EXEC pages from
// mmap - which is exactly what Xbyak_aarch64::MmapAllocator::alloc() needs - or
// whether LiveContainer's JIT trick only re-flags pages that were already mapped.
// The question was never answered, only routed around, and the hedge kept shipping.
// Worse, PPCRecompiler.cpp:696 prints "(forced, overriding Multi-core recompiler)"
// whenever that flag is set however it was set, so the launcher named a
// --force-interpreter argument that nobody ever passed. That is why turning JIT on
// in the UI looked like the app lying about it. Answer it at runtime.
//
// The first version of this answered the question by executing the page. That is not
// a probe, it is a coin flip with the process as the stake: on iOS a code-signing
// violation arrives as an uncatchable SIGKILL, so "can we execute our own memory"
// cannot be asked by executing our own memory - a "no" is indistinguishable from the
// app dying. The sentinel meant to make that failure sticky only ever got written on
// the launch that died, and the device log ends exactly there, on "Entering stage 2 -
// calling into the page", on every single launch.
//
// So nothing is executed here any more. Two non-fatal facts are checked instead:
//
//   1. mmap RW + mprotect R+X. If either is refused we have the answer plus an errno,
//      and the recompiler could never work here regardless. The page is never entered.
//   2. csops(CS_OPS_STATUS) & CS_DEBUGGED. Marking a page executable is not the
//      permission that matters on iOS - the kernel checks code signing at the moment
//      of the instruction fetch. CS_DEBUGGED is the flag that waives that check, and
//      it is what every JIT-enabling path on a sideloaded device actually produces (a
//      debugger attached over debugserver, StikJIT/SideStore/LiveContainer arranging
//      the same thing, or a real dynamic-codesigning entitlement). Without it,
//      mprotect(R+X) succeeding means nothing: the jump is still fatal. That is
//      precisely the state this device was in - stage 1 passed, stage 2 was death.
//
// The sentinel stays, but it now guards the thing that is genuinely dangerous: a whole
// boot with the recompiler live, since PPCRecompiler_init() generates and enters real
// code long after this function has returned. It is armed only when JIT is being left
// enabled, and disarmed once a title has actually launched. A sentinel present at
// startup therefore means "the last launch that trusted JIT did not survive it", and
// this install falls back to the interpreter from then on rather than dying forever.
//
// The caveat that must not get lost: the AArch64 recompiler has only ever been proven
// to COMPILE for iOS. It has never executed one instruction on device. A passing check
// makes the JIT testable. It does not make it correct and it does not make it fast.
// ---------------------------------------------------------------------------

// csops() lives in libSystem, but <sys/codesign.h> is not in the iOS SDK, so the two
// things needed from it are declared here.
extern "C" int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

namespace {

constexpr unsigned int kCsOpsStatus = 0;       // CS_OPS_STATUS
constexpr uint32_t     kCsDebugged  = 0x10000000u; // CS_DEBUGGED

std::filesystem::path g_jitSentinelPath;
std::atomic<bool> g_jitSentinelArmed{false};

// Reads back the build id stamped on the sentinel's first line. Returns an empty string
// for a sentinel written by a build that predates the stamp, which reads as "not this
// build" and therefore gets a retry - the desired answer for exactly those builds.
std::string ios_jit_read_sentinel_build(const std::filesystem::path& sentinelPath)
{
	const int fd = open(sentinelPath.string().c_str(), O_RDONLY);
	if (fd < 0)
		return {};
	char buf[128] = {};
	const ssize_t n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return {};

	std::string firstLine(buf, (size_t)n);
	const size_t nl = firstLine.find('\n');
	if (nl != std::string::npos)
		firstLine.resize(nl);
	// Anything with whitespace in it is prose from a pre-stamp sentinel, not a build id.
	if (firstLine.empty() || firstLine.find(' ') != std::string::npos)
		return {};
	return firstLine;
}

// Defined further down; forward-declared so ios_jit_is_permitted() below can register it
// as PPCRecompiler's survived-first-entry callback before its own definition is reached.
void ios_jit_survived_boot();

bool ios_jit_is_permitted(const std::filesystem::path& sentinelPath)
{
	namespace fs = std::filesystem;
	std::error_code ec;

	if (fs::exists(sentinelPath, ec))
	{
		// The sentinel records WHICH build died, not just that one did. Making it sticky
		// forever was right while every build shared the same recompiler; it is wrong the
		// moment a build ships specifically to fix the crash that armed it, because the
		// fix would then never get to run and the only way out would be deleting a file by
		// hand in the Files app. So: same build as the one that died -> still sticky. A
		// different build -> that is a new claim, clear it and let the new code be tested.
		const std::string armedBy = ios_jit_read_sentinel_build(sentinelPath);
		if (armedBy == BUILD_VERSION_STRING)
		{
			cemuLog_log(LogType::Force,
				"JIT check: this exact build ({}) enabled the recompiler before and did not survive it "
				"(sentinel still present) - forcing the interpreter. Delete {} to make it try again.",
				BUILD_VERSION_STRING, _pathToUtf8(sentinelPath));
			setCpuModeDetail("This build turned the recompiler on and did not survive it, so it stays on "
				"the interpreter. Install a newer build, or delete jit_enabled_boot_did_not_finish in "
				"Muffin's Documents folder, to let it try again.");
			return false;
		}

		cemuLog_log(LogType::Force,
			"JIT check: the crash sentinel was left by a different build ({}); this one is {}. Clearing it "
			"and re-testing the recompiler.",
			armedBy.empty() ? std::string("unknown") : armedBy, BUILD_VERSION_STRING);
		fs::remove(sentinelPath, ec);
	}

	const size_t pageSize = (size_t)sysconf(_SC_PAGESIZE);
	void* page = mmap(nullptr, pageSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
	if (page == MAP_FAILED)
	{
		const int err = errno;
		cemuLog_log(LogType::Force,
			"JIT check: mmap(RW) refused (errno {} - {}). Forcing the interpreter.",
			err, strerror(err));
		setCpuModeDetail(cpuModeDetailf("The system refused to hand this process a writable page at all "
			"(mmap errno %d - %s), so the recompiler has nowhere to emit code.", err, strerror(err)));
		return false;
	}

	const bool canMarkExecutable = mprotect(page, pageSize, PROT_READ | PROT_EXEC) == 0;
	const int mprotectErr = errno;
	munmap(page, pageSize);

	if (!canMarkExecutable)
	{
		cemuLog_log(LogType::Force,
			"JIT check: mprotect(R+X) refused (errno {} - {}). This process cannot get executable pages at "
			"all, so the recompiler could never work here. Forcing the interpreter.",
			mprotectErr, strerror(mprotectErr));
		setCpuModeDetail(cpuModeDetailf("This process cannot obtain executable memory (mprotect R+X "
			"errno %d - %s), so the recompiler could not work here under any launcher.",
			mprotectErr, strerror(mprotectErr)));
		return false;
	}

	uint32_t csFlags = 0;
	if (csops(getpid(), kCsOpsStatus, &csFlags, sizeof(csFlags)) != 0)
	{
		const int err = errno;
		cemuLog_log(LogType::Force,
			"JIT check: csops(CS_OPS_STATUS) failed (errno {} - {}), so whether this process may execute its "
			"own pages is unknown. Unknown is not yes. Forcing the interpreter.",
			err, strerror(err));
		setCpuModeDetail(cpuModeDetailf("Could not ask the kernel whether this process may execute its "
			"own pages (csops errno %d - %s). Unknown is not yes, so the interpreter it is.",
			err, strerror(err)));
		return false;
	}

	if ((csFlags & kCsDebugged) == 0)
	{
		cemuLog_log(LogType::Force,
			"JIT check: pages can be marked executable, but CS_DEBUGGED is not set (cs_flags 0x{:08x}), so the "
			"kernel kills this process the moment it fetches an instruction from one. Forcing the interpreter. "
			"To get JIT here, launch through a JIT enabler (StikJIT / SideStore / LiveContainer) or install a "
			"build that actually carries dynamic-codesigning.",
			csFlags);
		setCpuModeDetail(cpuModeDetailf("Executable pages are available, but CS_DEBUGGED is not set "
			"(cs_flags 0x%08x) - the kernel would kill Muffin the moment it ran recompiled code. Launch "
			"through StikJIT, SideStore or LiveContainer to turn the recompiler on. That is the single "
			"biggest speed difference available here, and it needs no new build.",
			(unsigned int)csFlags));
		return false;
	}

	// The check above (mmap RW, then mprotect to RX) is NOT the same guarantee as this
	// one, and a real crash log is why this exists. AppleJitAllocator (BackendAArch64.cpp)
	// tries four strategies in order; only the first - mmap(..., PROT_EXEC, MAP_JIT) -
	// maps pages that are BOTH executable at map time AND rooted in the process's actual
	// JIT region. Every fallback strategy, including the mprotect-promoted RW->RX path
	// this function was already testing, can succeed at the syscall level - mprotect()
	// returns 0 - and still SIGBUS the instant code-signing enforcement sees the first
	// instruction fetch from a page that was never MAP_JIT to begin with. That is exactly
	// what happened on-device: CS_DEBUGGED was set, mprotect(R+X) succeeded, this check
	// returned true, MAP_JIT itself then failed inside the real allocator and it fell
	// back to the mprotect-promoted path, and PPCRecompiler_enter's first jump into
	// generated code took signal 10. Test the actual mechanism the allocator depends on,
	// not a stand-in for it.
	{
		const size_t jitPageSize = (size_t)sysconf(_SC_PAGESIZE);
		void* jitPage = mmap(nullptr, jitPageSize, PROT_READ | PROT_WRITE | PROT_EXEC,
			MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
		if (jitPage == MAP_FAILED)
		{
			const int err = errno;
			cemuLog_log(LogType::Force,
				"JIT check: mmap(MAP_JIT, executable at map time) refused (errno {} - {}), even though "
				"CS_DEBUGGED is set. This is the one allocation strategy that has ever been confirmed to "
				"survive execution on iOS - every fallback strategy can pass its own syscalls and still "
				"SIGBUS on first entry into generated code, which is what happened before this check "
				"existed. Forcing the interpreter rather than handing the recompiler a mapping already "
				"known to be unsafe.",
				err, strerror(err));
			setCpuModeDetail(cpuModeDetailf("Executable pages are available and CS_DEBUGGED is set, but "
				"mmap(MAP_JIT) itself was refused (errno %d - %s). Every other way to get executable "
				"memory here is known to crash the instant recompiled code actually runs, so the "
				"interpreter is the only safe choice on this launch.", err, strerror(err)));
			return false;
		}
		munmap(jitPage, jitPageSize);
	}

	// Arm the sentinel for the whole recompiler-enabled boot, not for a single call.
	// Disarmed by ios_jit_survived_boot() once a title has actually launched.
	const std::string sentinelNative = sentinelPath.string();
	const int sentinelFd = open(sentinelNative.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (sentinelFd < 0)
	{
		const int err = errno;
		cemuLog_log(LogType::Force,
			"JIT check: could not create the crash sentinel at {} (errno {} - {}). Refusing to hand the "
			"recompiler an untested device with no way to record that it killed us. Forcing the interpreter.",
			_pathToUtf8(sentinelPath), err, strerror(err));
		setCpuModeDetail(cpuModeDetailf("JIT is permitted here, but the crash sentinel could not be "
			"written (errno %d - %s), and the recompiler is not handed an untested device with no way to "
			"record that it killed us.", err, strerror(err)));
		return false;
	}
	// The build id on the first line is what makes the sentinel clearable by shipping a
	// fix rather than by hand. ios_jit_read_sentinel_build() reads exactly this back.
	const std::string sentinelNote = std::string(BUILD_VERSION_STRING) +
		"\ncemu-ios enabled the PPC recompiler and did not reach a launched title\n";
	(void)write(sentinelFd, sentinelNote.data(), sentinelNote.size());
	(void)fsync(sentinelFd);
	close(sentinelFd);

	g_jitSentinelPath = sentinelPath;
	g_jitSentinelArmed.store(true);

	// Registers the ONLY correct place left to clear this sentinel: PPCRecompiler_enter()
	// already calls this back the first time control returns alive from generated code
	// (see its own comment - "the first and only proof that the recompiler actually
	// works on this machine"), but nothing ever registered a callback, so that mechanism
	// has been a complete no-op since it was written. This bridge instead cleared the
	// sentinel itself, synchronously, right after LaunchForegroundTitle() returned - and
	// LaunchForegroundTitle() only spawns and detaches the title thread, it does not wait
	// for it. So the sentinel was disarmed the instant a launch was REQUESTED, not
	// launched, which is exactly the ~3-second-too-early clear that let a crash-looping
	// recompiler re-arm itself clean on every single boot. Idempotent to call more than
	// once (it is just a store), so registering it here on every JIT-permitted boot is
	// harmless.
	PPCRecompiler_setSurvivedFirstEntryCallback(ios_jit_survived_boot);

	cemuLog_log(LogType::Force,
		"JIT check: PASSED - executable pages are available and CS_DEBUGGED is set (cs_flags 0x{:08x}), so the "
		"recompiler is left enabled. Nothing was executed to prove that, on purpose. The AArch64 recompiler has "
		"never run a PPC instruction on iOS, so this boot is its first run, not a known-good path; if it does "
		"not survive, the sentinel at {} makes the next launch fall back to the interpreter.",
		csFlags, _pathToUtf8(sentinelPath));
	setCpuModeDetail(cpuModeDetailf("Executable pages are available and CS_DEBUGGED is set (cs_flags "
		"0x%08x), so the PPC recompiler is enabled. Nothing was executed to prove that, on purpose - "
		"this is the recompiler's first run on this device, not a known-good path.",
		(unsigned int)csFlags));
	return true;
}

// Called once a title has actually launched with the recompiler live. Until this runs,
// the sentinel on disk says the last JIT boot did not finish.
void ios_jit_survived_boot()
{
	if (!g_jitSentinelArmed.exchange(false))
		return;
	std::error_code ec;
	std::filesystem::remove(g_jitSentinelPath, ec);
	cemuLog_log(LogType::Force,
		"JIT check: a title launched with the recompiler enabled - clearing the crash sentinel.");
}

}  // namespace
#endif




#if defined(CEMU_CORE_AVAILABLE)
namespace {

// Both caches name their files with the title id as 16 lowercase hex digits, so one
// prefix test serves for either directory.
bool IOSShaderCacheFileMatches(const std::filesystem::path& file, unsigned long long titleId)
{
    if (titleId == 0)
        return true;
    char prefix[32];
    snprintf(prefix, sizeof(prefix), "%016llx", titleId);
    return file.filename().string().rfind(prefix, 0) == 0;
}

long long IOSShaderCacheSweep(const std::filesystem::path& dir, unsigned long long titleId, bool deleteThem)
{
    namespace sfs = std::filesystem;
    std::error_code ec;
    if (!sfs::exists(dir, ec))
        return 0;
    long long bytes = 0;
    for (auto& entry : sfs::directory_iterator(dir, ec))
    {
        if (ec)
            break;
        if (!entry.is_regular_file(ec))
            continue;
        if (!IOSShaderCacheFileMatches(entry.path(), titleId))
            continue;
        std::error_code sizeEc;
        const auto size = sfs::file_size(entry.path(), sizeEc);
        if (sizeEc)
            continue;
        if (deleteThem)
        {
            std::error_code rmEc;
            if (!sfs::remove(entry.path(), rmEc) || rmEc)
                continue;
        }
        bytes += (long long)size;
    }
    return bytes;
}

} // namespace
#endif

long long cemu_bridge_clear_shader_cache(unsigned long long titleId, bool includeLearned) {
#if defined(CEMU_CORE_AVAILABLE)
    // Refused while a title runs: both caches are open and the pipeline cache serializes
    // on close, so a delete now would either be undone a moment later or take the file
    // out from under a live write.
    if (cemu_bridge_is_title_running()) {
        cemuLog_log(LogType::Force, "Shader cache: refusing to clear while a title is running");
        return -1;
    }
    long long freed = IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/precompiled"), titleId, true);
    if (includeLearned)
        freed += IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/transferable"), titleId, true);
    cemuLog_log(LogType::Force, "Shader cache: cleared {} bytes ({})", freed, includeLearned ? "compiled and learned" : "compiled only");
    return freed;
#else
    (void)titleId; (void)includeLearned; return -1;
#endif
}

int cemu_bridge_shader_cache_stats(unsigned long long titleId, long long* outLearnedBytes, long long* outCompiledBytes) {
#if defined(CEMU_CORE_AVAILABLE)
    if (outLearnedBytes)
        *outLearnedBytes = IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/transferable"), titleId, false);
    if (outCompiledBytes)
        *outCompiledBytes = IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/precompiled"), titleId, false);
    return 0;
#else
    (void)titleId;
    if (outLearnedBytes) *outLearnedBytes = 0;
    if (outCompiledBytes) *outCompiledBytes = 0;
    return -1;
#endif
}

void cemu_bridge_set_shader_cache_persistence(bool enabled) {
#if defined(CEMU_CORE_AVAILABLE)
    g_shaderCachePersistenceEnabled.store(enabled, std::memory_order_relaxed);
#else
    (void)enabled;
#endif
}

bool cemu_bridge_shader_cache_persistence(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return g_shaderCachePersistenceEnabled.load(std::memory_order_relaxed);
#else
    return true;
#endif
}

void cemu_bridge_set_async_shader_compile(bool enabled) {
#if defined(CEMU_CORE_AVAILABLE)
    GetConfig().async_compile = enabled;
#else
    (void)enabled;
#endif
}

bool cemu_bridge_async_shader_compile(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return GetConfig().async_compile;
#else
    return true;
#endif
}

void cemu_bridge_set_reduce_encoder_splitting(bool enabled) {
#if defined(CEMU_CORE_AVAILABLE)
    g_metal_reduceEncoderSplitting.store(enabled, std::memory_order_relaxed);
#else
    (void)enabled;
#endif
}

bool cemu_bridge_reduce_encoder_splitting(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return g_metal_reduceEncoderSplitting.load(std::memory_order_relaxed);
#else
    return false;
#endif
}

void cemu_bridge_set_vsync_enabled(bool enabled) {
#if defined(CEMU_CORE_AVAILABLE)
    g_metal_vsyncEnabled.store(enabled, std::memory_order_relaxed);
#else
    (void)enabled;
#endif
}

bool cemu_bridge_vsync_enabled(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return g_metal_vsyncEnabled.load(std::memory_order_relaxed);
#else
    return true;
#endif
}

void cemu_bridge_set_recompiler_enabled(bool enabled) {
#if defined(CEMU_CORE_AVAILABLE)
    PPCRecompiler_setForceDisabled(!enabled);
#else
    (void)enabled;
#endif
}

bool cemu_bridge_recompiler_enabled(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return !PPCRecompiler_isForceDisabled();
#else
    return false;
#endif
}

void cemu_bridge_set_legacy_timebase(bool useLegacy) {
#if defined(CEMU_CORE_AVAILABLE)
    PPCTimer_setUseLegacyTimebase(useLegacy);
#else
    (void)useLegacy;
#endif
}

bool cemu_bridge_legacy_timebase(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return PPCTimer_usingLegacyTimebase();
#else
    return false;
#endif
}

int cemu_bridge_cpu_mode(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return g_cpuMode.load();
#else
    return 0;
#endif
}

const char* cemu_bridge_cpu_mode_detail(void) {
#if defined(CEMU_CORE_AVAILABLE)
    const char* detail = getCpuModeDetail();
    // Empty means cemu_bridge_initialize() has not run yet. That is a real state with a
    // real explanation, so give it rather than returning "".
    if (detail[0] == '\0')
        return "Not decided yet - the CPU path is chosen when the engine initializes, on the first launch.";
    return detail;
#else
    return "This build does not contain the Cemu core, so there is no CPU path to choose.";
#endif
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
    // First line of every launch, deliberately. A crash log nobody can find is the same
    // as no crash log, and this is the only place the real path is known for certain.
    // Goes through the checkpoint call so it lands in the on-screen launch log as well as
    // in the file it names.
    {
        std::string where = "Crash log and checkpoints are being written to: ";
        const char* crashPath = cemu_bridge_crash_log_path();
        where += (crashPath && crashPath[0]) ? crashPath : "(nowhere - $HOME was not set, so no file could be opened)";
        cemu_bridge_log_checkpoint(where.c_str());
    }
    // Started here rather than from the early constructor: this needs the ObjC
    // runtime and a notification centre, and constructor(101) runs before either is
    // guaranteed. Still well ahead of any title boot, which is the only part that
    // has to be covered.
    cemu_bridge_start_memory_watchdog();
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
    // Same gap, different desktop-only init: CemuCommonInit() also calls AES128_init(),
    // which is what actually assigns the AES128_CBC_decrypt function pointer (it starts
    // out nullptr - see aes128.cpp). Nothing else on this port's boot path calls it, so
    // that pointer stayed null through an entire process lifetime, and the first disc
    // mount to call through it (FSTVolume::FindDiscKey(), decrypting the header to find
    // the disc's AES key) jumped through a null function pointer - a signal 11 landing
    // inside FindDiscKey with no frame below it, which is exactly the shape of the crash
    // reported: boot reaches "title list initialized" fine (nothing touches AES before a
    // disc is actually mounted), then SIGSEGVs the instant a WUD/WUX title is launched.
    AES128_init();
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
    //
    // The data root is a "CemuData" SUBDIRECTORY of the bundle, not the bundle
    // itself, and that indirection is load-bearing. GetDataPath()'s callers hardcode
    // a "resources/" prefix, so making the bundle the data root put a directory
    // literally named `resources` at the top level of Cemu.app - and iOS filesystems
    // are case-insensitive, so CFBundle's probe for the reserved `Resources`
    // directory matched it. That reclassifies the bundle from a flat one (Info.plist
    // at the top level, which is where ours is) into a Resources-style one (Info.plist
    // expected inside), and CFBundle then reads no Info.plist at all: -bundleIdentifier,
    // -infoDictionary[@"CFBundleExecutable"] and -executablePath all come back nil for
    // a bundle whose files are every one of them present and intact.
    //
    // That is what broke v1.14 and v1.15 under LiveContainer. LiveContainer reads
    // Info.plist directly off disk to install, so installs succeeded; then
    // LCBootstrap.m asked NSBundle for -executablePath at launch, got nil, and
    // reported "App's executable path not found. Please try force re-signing or
    // reinstalling this app." Nothing was missing and nothing was being deleted.
    // v1.13 worked only because its bundle was flat and had no such directory.
    // Confirmed by isolation against a real CFBundle: the v1.13 bundle plus one empty
    // directory named `resources` reproduces it exactly, v1.13 plus `gameProfiles`
    // does not, and the v1.15 bundle with that one directory renamed resolves cleanly.
    //
    // Nesting keeps Cemu's own relative layout (CemuData/resources/sharedFonts,
    // CemuData/gameProfiles) exactly as GetDataPath()'s callers expect, while leaving
    // the top level of the bundle with no name CFBundle reserves. ci/verify-ipa.sh
    // now fails the build on both halves of this - a reserved directory name at the
    // bundle root, and a bundle NSBundle cannot resolve - so it cannot return in some
    // other form.
    fs::path dataPath = userDataPath;
    NSString* bundleResourcePath = [[NSBundle mainBundle] resourcePath];
    if (bundleResourcePath.length > 0)
        dataPath = fs::path(bundleResourcePath.fileSystemRepresentation) / "CemuData";

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

    // cemuLog_log() filters every line against s_loggingFlagMask, and that mask starts
    // out as Force alone. On desktop the wx frontend calls cemuLog_setActiveLoggingFlags()
    // out of the config during startup; there is no wx here and nothing on this path was
    // calling it, so every OSReport a title made was dropped before it reached log.txt.
    // The cost of that is not cosmetic: it makes a homebrew ROM that narrates its own
    // progress look exactly like one that never started, which is the worst possible
    // failure mode for a diagnostic. CoreinitLogging is the channel OSReport ends up on;
    // APIErrors is where the OS libs report bad parameters, which is the class of mistake
    // homebrew actually makes. setActiveLoggingFlags ORs Force back in, so the existing
    // Force-level boot log is unaffected.
    cemuLog_setActiveLoggingFlags(cemuLog_getFlag(LogType::CoreinitLogging) |
        cemuLog_getFlag(LogType::APIErrors));

    // Say outright whether the bundled data actually made it into this build, so a
    // device log answers the question instead of it having to be inferred from a
    // downstream symptom several hundred lines later. The error_code overloads, not
    // the throwing ones: an unhandled exception this early in boot is std::terminate
    // with nothing useful logged, and "could not tell" is reported the same as "no".
    std::error_code fontsEc, profilesEc;
    const bool haveFonts = fs::exists(dataPath / "resources" / "sharedFonts" / "CafeStd.ttf", fontsEc);
    const bool haveProfiles = fs::exists(dataPath / "gameProfiles" / "default", profilesEc);
    // First line of every boot, before anything that might fail. If a log reaches us
    // from a device nobody here owns, this is the line that makes the rest of it mean
    // something.
    cemuLog_log(LogType::Force, "iOS {}", cemu_bridge_device_report());

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
    //
    // That open question is now asked directly rather than assumed - see
    // ios_jit_is_permitted() above. The interpreter is forced whenever the answer is no,
    // or unknown, or a previous JIT-enabled launch died; the only case that leaves the
    // recompiler enabled is executable pages being obtainable AND the kernel having been
    // told to stop checking their signature. Nothing is executed to find that out,
    // because on iOS the wrong answer to that experiment is the process dying.
    const fs::path jitSentinel = userDataPath / "jit_enabled_boot_did_not_finish";
    const bool jitPermitted = ios_jit_is_permitted(jitSentinel);
    if (!jitPermitted)
    {
        // Multi-core, not single-core. Both run the exact same interpreter; the only
        // difference is _LaunchTitleThread()'s OSSchedulerBegin(3) vs OSSchedulerBegin(1)
        // - whether the Wii U's three PPC cores get three host threads or take turns on
        // one. Every iOS launch up to and including v1.17 took turns on one, on an
        // 8-core M2, while a title that schedules work across all three cores sat
        // waiting on the two that were not running.
        //
        // SetForceInterpreter(false) matters as much as the line under it. CafeSystem.cpp
        // gates the three-thread path on
        //     ForceMultiCoreInterpreter() && !ForceInterpreter()
        // so leaving the single-core flag set would silently win and this whole change
        // would be a no-op that still logged "Single-core interpreter". Clearing it is
        // safe because PPCRecompiler_init() returns early on
        //     ForceInterpreter() || ForceMultiCoreInterpreter()
        // - it never reaches Xbyak's PROT_EXEC mmap - so the recompiler stays just as
        // off as it was, and nothing here weakens the CS_DEBUGGED reasoning above.
        //
        // What this is NOT: a substitute for the recompiler, or anything close to one.
        // Interpreting Espresso stays roughly two orders of magnitude off recompiling
        // it, and three threads of that is still three threads of that. It is simply
        // the only CPU-side gain that exists while CS_DEBUGGED is unset, and it costs
        // nothing to take.
        LaunchSettings::SetForceInterpreter(false);
        LaunchSettings::SetForceMultiCoreInterpreter(true);
    }
    // The probe has already recorded WHY. This records WHICH, from the probe's own
    // return value, so the two can never disagree about the same launch.
    g_cpuMode.store(jitPermitted ? kCpuModeRecompiler : kCpuModeInterpreter);

    // Emulated timebase. See cemu_bridge_set_timebase_shift() in CemuBridge.h for why
    // this is not cosmetic on this port.
    //
    // Under the interpreter the emulated CPU is roughly two orders of magnitude slower
    // than the Espresso it stands in for, while the guest's own clock keeps advancing at
    // host wall-clock rate. Every deadline the title sets for itself is then already
    // expired when it is serviced, so coreinit can spend a whole timeslice on overdue
    // alarm and AX work and hand the title's thread nothing - one frame presented, then
    // apparent silence. Slowing the guest's clock is the compensation Cemu already ships
    // for exactly this (desktop exposes it as the Timer Speed menu); iOS simply never
    // set it, so every launch to date ran at 3 - real time - regardless of CPU mode.
    //
    // 6 (an eighth of real time) is a starting point, not a measured optimum, which is
    // why Settings exposes the whole range rather than this being hardcoded. Swift
    // overrides it immediately after this call when the user has chosen a value.
    //
    // With the recompiler the premise does not hold, so the default there is real time.
    cemu_bridge_set_timebase_shift(jitPermitted ? 3 : 6);

    // Audio had TWO independent faults, and fixing either one alone still leaves a
    // silent device:
    //
    //   1. IAudioAPI::InitializeStatic() is only ever called from src/main.cpp - the
    //      desktop entry point, which iOS never runs. So s_availableApis stayed all
    //      false no matter which backends were compiled in, and the boot log's
    //      "------- Init Audio backend -------" block reported every API as "not
    //      supported" even for ones that were present.
    //   2. CemuConfig defaults audio_api to 0, which is DirectSound - a Windows-only
    //      backend. There is no iOS settings UI to change it, so even once a working
    //      backend exists the configured API would never have matched one.
    //
    // Together those are the whole reason AXOut_init() logged "can't initialize tv
    // audio: failed to find selected device" on hardware with working speakers: the
    // device list for the configured API was empty, so no DeviceDescription could
    // ever match tv_device.
    IAudioAPI::InitializeStatic();
#if HAS_COREAUDIO
    {
        auto& audioConfig = GetConfig();
        if (!IAudioAPI::IsAudioAPIAvailable((IAudioAPI::AudioAPI)audioConfig.audio_api))
        {
            audioConfig.audio_api = IAudioAPI::CoreAudio;
            // CoreAudioAPI::GetDevices() publishes exactly this identifier, and it is
            // also CemuConfig's default, so this only matters if a config ever lands
            // here with it cleared.
            if (audioConfig.tv_device.empty())
                audioConfig.tv_device = L"default";
            cemuLog_log(LogType::Force,
                "Audio: the configured backend is not available on iOS, using CoreAudio instead.");
        }
    }
#endif

    CafeSystem::Initialize();

    // Nothing on iOS had ever constructed InputManager or loaded a controller profile:
    // desktop Cemu does both from src/main.cpp, which this app never runs, and there is
    // no input-settings UI to do it by hand. So SDL was never initialized and every
    // title ran with zero emulated controllers attached. Do it here, right after
    // CafeSystem::Initialize() - it needs ActiveSettings::SetPaths() (above) to resolve
    // controllerProfiles/, and the loaded config for controller defaults.
    cemu_bridge_bring_up_input_on_main_thread();

    setStatus("Cemu core initialized.");
#else
    (void)mlcPath;
    setStatus("Real engine not compiled into this build yet (see ROADMAP.md M1).");
#endif
}

#if defined(CEMU_CORE_AVAILABLE)
// Which renderer this build actually constructs on iOS.
//
// Until now this was hardcoded to Metal in two places. It is a choice again because
// the native Metal backend is no longer the only iOS option: Cemu's Vulkan backend
// now builds for iOS against a statically linked MoltenVK (see cmake/MoltenVK.cmake),
// which is the combination the one shipping iOS Cemu build renders through.
//
// Selection goes through GetConfig().graphic_api, the same mechanism desktop uses,
// so it is switchable on device without a rebuild. NOTE that CemuConfig's default for
// that value is kVulkan, so a build off this branch with no config written is a
// VULKAN-FIRST build, not the Metal behaviour that shipped before it. That is
// intentional for testing this path and is the reason this branch is not
// merge-ready as-is -- merging it should first decide what the iOS default ought to
// be, rather than inheriting the desktop one by accident.
//
// kOpenGL is not reachable on iOS (ENABLE_OPENGL is forced off) and falls through to
// Metal rather than returning nothing.
static std::unique_ptr<Renderer> cemu_bridge_make_renderer(const char*& outName)
{
#if defined(ENABLE_VULKAN)
    if (GetConfig().graphic_api == kVulkan)
    {
        outName = "Vulkan/MoltenVK";
        return std::make_unique<VulkanRenderer>();
    }
#endif
    outName = "Metal";
    return std::make_unique<MetalRenderer>();
}

// True when the constructed renderer is the Vulkan one. Everything below has to ask,
// because MetalRenderer::GetInstance() is an UNCHECKED static_cast of g_renderer -
// calling it while a VulkanRenderer sits in that slot is undefined behaviour, not a
// null check that fails safely.
static bool cemu_bridge_renderer_is_vulkan()
{
#if defined(ENABLE_VULKAN)
    return g_renderer && g_renderer->GetType() == RendererAPI::Vulkan;
#else
    return false;
#endif
}

// Attach a just-registered UIView to whichever renderer was constructed.
//
// The two backends neither share this entry point nor read the view handle from the
// same place:
//   Metal  -> InitializeLayer(), reads window_main / window_pad
//   Vulkan -> InitializeSurface(), which builds a SwapchainInfoVk that reads
//             canvas_main / canvas_pad (SwapchainInfoVk.cpp) and hands that pointer to
//             CreateCocoaSurface()
// On desktop the canvas_* fields are filled by initHandleContextFromWxWidgetsWindow()
// inside VulkanCanvas's constructor - a file this build does not compile - so on iOS
// the caller has to set them itself, or the Vulkan surface gets created from nullptr.
static void cemu_bridge_initialize_render_surface(bool mainWindow, int width, int height)
{
#if defined(ENABLE_VULKAN)
    if (cemu_bridge_renderer_is_vulkan())
    {
        VulkanRenderer::GetInstance()->InitializeSurface({width, height}, mainWindow);
        return;
    }
#endif
    MetalRenderer::GetInstance()->InitializeLayer({width, height}, mainWindow);
}
#endif

void cemu_bridge_register_render_surface(void* uiView, int width, int height, double dpiScale) {
    // First thing that happens in a title launch, so it is where the launch log's
    // "+0.000s" belongs. Not the process start: under LiveContainer the guest can be
    // launched more than once inside one host process (Void's 2026-08-19 device log
    // has three "=== Cemu process started (early constructor) ===" blocks in a row),
    // and an elapsed column measured from the first of those would be meaningless by
    // the third.
    ios_live_log_begin_run();

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
    // canvas_main is the field the VULKAN path reads (SwapchainInfoVk's ctor ->
    // CreateFramebufferSurface -> CreateCocoaSurface). Metal reads window_main. Set
    // both from the one UIView: iOS has a single view per screen, so the desktop
    // window/canvas distinction has nothing to distinguish here.
    windowInfo.canvas_main.surface = uiView;
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
        {
            const char* rendererName = "";
            g_renderer = cemu_bridge_make_renderer(rendererName);
            cemu_bridge_log_checkpoint((std::string("Renderer constructed: ") + rendererName).c_str());
        }

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
        cemu_bridge_initialize_render_surface(/*mainWindow=*/true, width, height);
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
    windowInfo.canvas_pad.surface = uiView;  // the Vulkan path's handle - see the TV surface above
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
        cemu_bridge_initialize_render_surface(/*mainWindow=*/false, width, height);
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
#if defined(ENABLE_VULKAN)
    if (cemu_bridge_renderer_is_vulkan())
    {
        // Vulkan owns no CAMetalLayer of its own to hand back - the pad's swapchain is
        // torn down through StopUsingPadAndWait(), which blocks until the GPU thread
        // has stopped submitting pad work. pad_open is already false above, so no new
        // work is being laid out by the time this returns.
        VulkanRenderer::GetInstance()->StopUsingPadAndWait();
        windowInfo.window_pad.surface = nullptr;
        windowInfo.canvas_pad.surface = nullptr;
        cemuLog_log(LogType::Force, "iOS: GamePad (DRC) Vulkan pad swapchain released");
        return;
    }
#endif
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
    // Virtual on Renderer and overridden by both backends, so ask the base pointer
    // rather than downcasting to one of them.
    return g_renderer->IsPadWindowActive();
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

#if defined(ENABLE_VULKAN)
    if (cemu_bridge_renderer_is_vulkan())
    {
        // Nothing to call. The window sizes were just updated above, and Vulkan's
        // RecreateSwapchain() re-reads them itself via WindowSystem::GetWindowPhysSize()
        // /GetPadWindowPhysSize(); it is triggered when the resized layer makes
        // vkAcquireNextImageKHR/vkQueuePresentKHR report OUT_OF_DATE or SUBOPTIMAL.
        // ResizeLayerAndFrame() is a Metal-only entry point and calling it here would
        // be a bad downcast.
        cemuLog_log(LogType::Force, "iOS: {} surface resized to {}x{} points at {}x scale - Vulkan swapchain will recreate at the next present", mainWindow ? "TV" : "GamePad", width, height, dpiScale);
        return;
    }
#endif

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

#if defined(CEMU_CORE_AVAILABLE)
namespace {
    void cemu_bridge_ensure_renderer(const char* callerTag) {
        // Shared by both boot entry points below.
        //
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
            const char* rendererName = "";
            @try {
                g_renderer = cemu_bridge_make_renderer(rendererName);
            } @catch (NSException* exception) {
                g_renderer.reset();
                std::string message = std::string(rendererName) + " renderer construction (retry, " + callerTag + ") threw: ";
                message += exception.name.UTF8String;
                message += " - ";
                message += exception.reason.UTF8String;
                cemu_bridge_log_checkpoint(message.c_str());
            }
        }
    }
}
#endif

CemuBridgeStatus cemu_bridge_boot_rpx(const char* rpxPath) {
    if (!rpxPath || rpxPath[0] == '\0') {
        setStatus("boot_rpx: empty path.");
        return CEMU_BRIDGE_BAD_ARG;
    }
#if defined(CEMU_CORE_AVAILABLE)
    if (!g_initialized.load())
        CafeSystem::Initialize();

    cemu_bridge_ensure_renderer("boot_rpx");

    namespace fs = std::filesystem;
    cemu_bridge_log_checkpoint("boot_rpx: about to call PrepareForegroundTitleFromStandaloneRPX");
    auto status = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(fs::path(rpxPath));
    cemu_bridge_log_checkpoint("boot_rpx: PrepareForegroundTitleFromStandaloneRPX returned");
    switch (status) {
        case CafeSystem::PREPARE_STATUS_CODE::SUCCESS:
            cemu_bridge_log_checkpoint("boot_rpx: about to call LaunchForegroundTitle");
            CafeSystem::LaunchForegroundTitle();
            cemu_bridge_log_checkpoint("boot_rpx: LaunchForegroundTitle returned");
            // The sentinel is no longer cleared here - LaunchForegroundTitle() only
            // spawns and detaches the title thread, it does not wait for generated code
            // to actually run, so clearing at this point was ~3 seconds too early to mean
            // anything. See ios_jit_is_permitted()'s PPCRecompiler_setSurvivedFirstEntryCallback
            // registration for where this now happens correctly.
            // After the launch call, not before: the ladder measures time from a title that
            // is actually running, and starting it during prepare would spend its first step
            // on disc mounting rather than on anything the clock affects.
            ios_timebase_ladder_start();
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

CemuBridgeStatus cemu_bridge_boot_title(const char* path) {
    if (!path || path[0] == '\0') {
        setStatus("boot_title: empty path.");
        return CEMU_BRIDGE_BAD_ARG;
    }
#if defined(CEMU_CORE_AVAILABLE)
    if (!g_initialized.load())
        CafeSystem::Initialize();

    cemu_bridge_ensure_renderer("boot_title");

    // Everything format-specific happens on the CMake side (IOSTitleLaunch.cpp): key
    // cache reload, title-list registration, disc mount, and the choice between
    // PrepareForegroundTitle() and PrepareForegroundTitleFromStandaloneRPX(). What is
    // left here is the launch itself and turning a reason code into a sentence someone
    // holding an iPad can act on.
    cemu_bridge_log_checkpoint("boot_title: about to prepare title");
    int prepared = IOSTitleLaunch_PrepareForegroundTitle(path);
    cemu_bridge_log_checkpoint("boot_title: prepare returned");

    switch (prepared) {
        case 0: // IOS_TITLE_LAUNCH_OK
            cemu_bridge_log_checkpoint("boot_title: about to call LaunchForegroundTitle");
            CafeSystem::LaunchForegroundTitle();
            cemu_bridge_log_checkpoint("boot_title: LaunchForegroundTitle returned");
            // No sentinel clear here either - see the matching comment in
            // cemu_bridge_boot_rpx() above for why, and ios_jit_is_permitted() for where
            // it now actually happens.
            // EmulationEngine.bootBlocking() goes to cemu_bridge_boot_title() for
            // everything: disc images, archives, dumped folders, and standalone homebrew
            // alike (the RPX case falls through inside IOSTitleLaunch_PrepareForegroundTitle,
            // not out here). So every launch that has ever happened on a device took this
            // branch, and the automatic clock ladder - the thing written specifically to
            // search for a timebase that gets a title past GX2Init - was never once armed.
            // It was reachable only from a function nothing calls.
            //
            // That matters most for exactly the titles it was meant for. Homebrew on OSScreen
            // does not need the ladder and its own counters say so, so the ladder stopping
            // early there costs nothing. A commercial title is the case that has to reach
            // GX2Init, and it is the case that has been running the whole time at whatever
            // fixed shift the boot happened to start at, with nothing measuring whether that
            // clock was ever the thing holding it. Arming it here does not by itself make a
            // retail game boot, but it is a precondition for the ladder's own log lines to
            // exist at all, and those lines are the difference between "it crashed" and
            // knowing whether the guest's clock was ever a factor.
            ios_timebase_ladder_start();
            setStatus("Title launched.");
            return CEMU_BRIDGE_OK;
        case 1:
            setStatus("Invalid RPX.");
            return CEMU_BRIDGE_INVALID_RPX;
        case 2:
            setStatus("Unable to mount title (bad/outdated path).");
            return CEMU_BRIDGE_UNABLE_TO_MOUNT;
        case 3:
            // Deliberately says whose keys and where they go. This is the one failure
            // the user can actually fix, and the fix is not guessable from "decryption
            // failed".
            setStatus("This game is encrypted and no key in keys.txt opens it. Put the keys.txt you dumped from your own Wii U in Muffin's \"keys\" folder in the Files app (or import it in Settings), then try again.");
            return CEMU_BRIDGE_NO_DISC_KEY;
        case 4:
            setStatus("This title has no usable title.tik, so its content cannot be decrypted.");
            return CEMU_BRIDGE_NO_TITLE_TIK;
        case 6:
            setStatus("That looks like an update or DLC. Launch the base game instead.");
            return CEMU_BRIDGE_BASE_NOT_FOUND;
        default:
            setStatus("Not a Wii U title this build can launch.");
            return CEMU_BRIDGE_UNSUPPORTED;
    }
#else
    (void)path;
    setStatus("Cannot boot: real engine not compiled into this build yet (ROADMAP.md M1).");
    return CEMU_BRIDGE_CORE_NOT_BUILT;
#endif
}

int cemu_bridge_reload_and_count_keys(void) {
#if defined(CEMU_CORE_AVAILABLE)
    // keys.txt is resolved against the user data path that cemu_bridge_initialize()
    // establishes, so before that call there is no file to count and any number
    // returned here would be about the wrong directory. Say "cannot answer" rather than
    // "zero keys" - the difference is the whole point, since zero is also what a real,
    // empty keys.txt looks like.
    if (!g_initialized.load())
        return -1;
    return IOSTitleLaunch_ReloadAndCountKeys();
#else
    return -1;
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

void cemu_bridge_get_progress(CemuBridgeProgress* out) {
    if (!out)
        return;
    // Zero first and unconditionally, so every early return below is a complete answer
    // rather than a partly written struct the caller cannot tell apart from a full one.
    *out = CemuBridgeProgress{};
#if defined(CEMU_CORE_AVAILABLE)
    // The counters live in LatteGPUState, which is only meaningful while a title owns the
    // GPU. Reading them with nothing running would report the last title's totals as if
    // they were this one's.
    if (!CafeSystem::IsTitleRunning())
        return;
    LatteProgressSnapshot snapshot{};
    LatteThread_GetProgress(snapshot);
    out->gx2_init_reached = snapshot.gx2InitReached;
    out->gx2_frame_count = snapshot.gx2FrameCount;
    out->gx2_frames_per_second = snapshot.gx2FramesPerSecond;
    out->os_screen_scanouts = snapshot.osScreenScanouts;
    out->guest_flip_requests = snapshot.guestFlipRequests;
#endif
}

// Decrypt-to-Files state. One at a time by design - a second call while one is already
// running is a no-op (see cemu_bridge_start_decrypt()) rather than something that would
// need its own queue, since this is a foreground action the user explicitly started and
// is watching progress for, not a background service.
#if defined(CEMU_CORE_AVAILABLE)
static std::atomic<bool> g_decryptRunning{false};
static std::atomic<bool> g_decryptCompleted{false};
static std::atomic<bool> g_decryptCancelRequested{false};
static std::atomic<int> g_decryptResultStatus{0};
static std::atomic<uint64_t> g_decryptBytesWritten{0};
static std::atomic<uint32_t> g_decryptFilesWritten{0};
static std::thread g_decryptThread;
static std::mutex g_decryptThreadMutex;
#endif

bool cemu_bridge_start_decrypt(const char* srcPath, const char* destPath, bool toWua) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!srcPath || srcPath[0] == '\0' || !destPath || destPath[0] == '\0')
        return false;
    if (g_decryptRunning.exchange(true))
        return false; // already running - caller polls progress instead of starting a second one

    std::lock_guard lock{g_decryptThreadMutex};
    if (g_decryptThread.joinable())
        g_decryptThread.join(); // previous run's thread object, already finished - reap it before replacing
    g_decryptCompleted.store(false);
    g_decryptCancelRequested.store(false);
    g_decryptBytesWritten.store(0);
    g_decryptFilesWritten.store(0);

    std::string src(srcPath);
    std::string dest(destPath);
    g_decryptThread = std::thread([src, dest, toWua]() {
        auto progress = [](uint64_t bytesWritten, uint32_t filesWritten) {
            g_decryptBytesWritten.store(bytesWritten);
            g_decryptFilesWritten.store(filesWritten);
        };
        int status = toWua
            ? IOSTitleDecrypt_ExtractToWua(src.c_str(), dest.c_str(), g_decryptCancelRequested, progress)
            : IOSTitleDecrypt_ExtractToFolder(src.c_str(), dest.c_str(), g_decryptCancelRequested, progress);
        g_decryptResultStatus.store(status);
        g_decryptCompleted.store(true);
        g_decryptRunning.store(false);
    });
    return true;
#else
    return false;
#endif
}

void cemu_bridge_get_decrypt_progress(CemuBridgeDecryptProgress* out) {
    if (!out)
        return;
    *out = CemuBridgeDecryptProgress{};
#if defined(CEMU_CORE_AVAILABLE)
    out->is_running = g_decryptRunning.load();
    out->completed = g_decryptCompleted.load();
    out->result_status = g_decryptResultStatus.load();
    out->bytes_written = g_decryptBytesWritten.load();
    out->files_written = g_decryptFilesWritten.load();
#endif
}

void cemu_bridge_cancel_decrypt(void) {
#if defined(CEMU_CORE_AVAILABLE)
    g_decryptCancelRequested.store(true);
#endif
}

bool cemu_bridge_derive_gametdb_id(const char* romPath, char* outGameID, size_t outGameIDSize) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!romPath || !outGameID || outGameIDSize < 7)
        return false;
    std::string id = IOSCoverArt_DeriveGameTdbId(romPath);
    if (id.size() != 6)
        return false;
    memcpy(outGameID, id.c_str(), 7); // includes the null terminator
    return true;
#else
    return false;
#endif
}

bool cemu_bridge_derive_title_id(const char* romPath, uint64_t* outTitleId) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!romPath || !outTitleId)
        return false;
    return IOSDlcUpdateImport_DeriveTitleId(romPath, outTitleId);
#else
    return false;
#endif
}

uint64_t cemu_bridge_derive_base_title_id(uint64_t titleId) {
#if defined(CEMU_CORE_AVAILABLE)
    return IOSDlcUpdateImport_DeriveBaseTitleId(titleId);
#else
    return titleId;
#endif
}

int cemu_bridge_get_title_type(uint64_t titleId) {
#if defined(CEMU_CORE_AVAILABLE)
    return IOSDlcUpdateImport_GetTitleType(titleId);
#else
    return 0xFF; // TitleIdParser::TITLE_TYPE::UNKNOWN
#endif
}

void cemu_bridge_get_mlc_title_path_components(uint64_t titleId, char* outUpperHex, char* outLowerHex) {
#if defined(CEMU_CORE_AVAILABLE)
    if (!outUpperHex || !outLowerHex)
        return;
    IOSDlcUpdateImport_GetMlcTitlePathComponents(titleId, outUpperHex, outLowerHex);
#else
    if (outUpperHex) outUpperHex[0] = '\0';
    if (outLowerHex) outLowerHex[0] = '\0';
#endif
}

bool cemu_bridge_inspect_title(const char* romPath, uint64_t* outTitleId, uint16_t* outVersion,
    int* outRegion, int* outInvalidReason) {
#if defined(CEMU_CORE_AVAILABLE)
    return IOSDlcUpdateImport_Inspect(romPath, outTitleId, outVersion, outRegion, outInvalidReason);
#else
    if (outInvalidReason) *outInvalidReason = CemuTitleBadPathOrInaccessible;
    return false;
#endif
}

uint64_t cemu_bridge_derive_content_title_id(uint64_t baseTitleId, bool isUpdate) {
#if defined(CEMU_CORE_AVAILABLE)
    return IOSDlcUpdateImport_DeriveContentTitleId(baseTitleId, isUpdate);
#else
    return 0;
#endif
}

// Clamped rather than trusted. PPCTimer_getFromRDTSC() computes
//     elapsedTick = (elapsedTick << 3) >> shift
// on a uint64, so a large enough shift makes every elapsed tick zero and the guest's
// clock stops entirely - which is not slow motion, it is a stopped console, and it would
// hang far more convincingly than the problem this setting exists to relieve. 10 is
// 1/128th of real time, already well past anything useful.
static constexpr int kTimebaseShiftMin = 0;   // 8x real time
static constexpr int kTimebaseShiftMax = 10;  // 1/128 real time

void cemu_bridge_set_timebase_shift(int shift) {
    if (shift < kTimebaseShiftMin) shift = kTimebaseShiftMin;
    if (shift > kTimebaseShiftMax) shift = kTimebaseShiftMax;
#if defined(CEMU_CORE_AVAILABLE)
    ActiveSettings::SetTimerShiftFactor((uint8)shift);
    // Logged at Force because this changes how the guest perceives time, and a log that
    // does not say which value was in effect cannot be used to compare two runs.
    cemuLog_log(LogType::Force, "Emulated timebase: shift {} ({:.4g}x real time)",
        shift, 8.0 / (double)(1u << shift));
#endif
}

int cemu_bridge_get_timebase_shift(void) {
#if defined(CEMU_CORE_AVAILABLE)
    return (int)ActiveSettings::GetTimerShiftFactor();
#else
    return 3;
#endif
}

// The automatic clock ladder. See cemu_bridge_set_timebase_auto_enabled() in
// CemuBridge.h for why this exists rather than leaving the picker to do the job.
//
// The floor is 9 (1/64) rather than kTimebaseShiftMax, because past that the search has
// stopped being a search: a title that will not reach GX2Init with its clock at a
// sixty-fourth is not being held up by its clock, and stepping further only makes the
// console slower while proving nothing. The ladder says so and stops instead of running
// the number down to where the guest's clock stops advancing at all.
static constexpr int kLadderFloorShift = 9;    // 1/64 real time
static constexpr int kLadderStepSeconds = 12;  // long enough that a slow boot is not mistaken for a stuck one

static std::atomic<bool> g_timebaseAutoEnabled{true};
static std::atomic<bool> g_timebaseLadderRunning{false};
static std::thread g_timebaseLadderThread;
// Guards the thread object itself, not the flag. Launch runs on GameManager's background
// queue and shutdown can come from the UI thread, so without this a shutdown arriving
// during a launch would be reading a std::thread another thread is assigning to.
static std::mutex g_timebaseLadderMutex;

void cemu_bridge_set_timebase_auto_enabled(bool enabled) {
    const bool was = g_timebaseAutoEnabled.exchange(enabled);
    if (was == enabled)
        return;
#if defined(CEMU_CORE_AVAILABLE)
    // Logged because a run where the ladder moved the clock and a run where a person did
    // are not the same experiment, and the log is the only place that distinction survives.
    cemuLog_log(LogType::Force, "Emulated timebase: automatic clock ladder {}",
        enabled ? "enabled" : "disabled - a value was chosen by hand, so it stands");
#endif
}

bool cemu_bridge_timebase_auto_enabled(void) {
    return g_timebaseAutoEnabled.load();
}

#if defined(CEMU_CORE_AVAILABLE)
static void ios_timebase_ladder_entry() {
    const auto start = std::chrono::steady_clock::now();
    auto lastStep = start;
    // Baselines, taken from the first poll rather than assumed to be zero. Compared against
    // literal zero instead, a title that presented exactly one frame and then stopped - the
    // precise symptom this whole thing exists for - would read as "advancing" on the first
    // pass and the ladder would congratulate itself and quit before taking a single step.
    bool baselineTaken = false;
    unsigned long long baseGX2Frames = 0;
    unsigned long long baseOSScreenScanouts = 0;
    unsigned int baseGuestFlipRequests = 0;
    while (g_timebaseLadderRunning.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        if (!g_timebaseLadderRunning.load())
            return;
        // Checked every pass, not just at the start: this is what makes opening Settings
        // mid-boot take effect. The user's pick wins immediately and the ladder does not
        // get to take another step on top of it.
        if (!g_timebaseAutoEnabled.load())
            return;
        if (!CafeSystem::IsTitleRunning())
            return;

        CemuBridgeProgress progress{};
        cemu_bridge_get_progress(&progress);
        const auto now = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(now - start).count();

        if (!baselineTaken) {
            baselineTaken = true;
            baseGX2Frames = progress.gx2_frame_count;
            baseOSScreenScanouts = progress.os_screen_scanouts;
            baseGuestFlipRequests = progress.guest_flip_requests;
        }

        // Success, and the only line in this whole file worth reading first.
        //
        // More than one signal, because "made progress" is not the same question as "reached
        // GX2Init". A homebrew title on OSScreen never calls GX2Init at all, so testing that
        // alone would walk a title that is visibly scanning out down to the floor and then
        // report it as a failure - the opposite of what its own counters say. Movement in any
        // of them means the guest is past the point this exists to get it past.
        //
        // gx2_init_reached is the exception and is read as a latch, not compared to a
        // baseline: if it is already true when the ladder starts, there is nothing here left
        // to search for.
        const bool advancing = progress.gx2_init_reached ||
                               progress.gx2_frame_count > baseGX2Frames ||
                               progress.os_screen_scanouts > baseOSScreenScanouts ||
                               progress.guest_flip_requests > baseGuestFlipRequests;
        if (advancing) {
            const int shift = cemu_bridge_get_timebase_shift();
            cemuLog_log(LogType::Force,
                "Emulated timebase: the title is advancing ({}) after {:.1f}s with the clock at shift {} "
                "({:.4g}x real time). Ladder stopped - that is the value that worked.",
                progress.gx2_init_reached ? "GX2Init reached" : "guest output moving",
                elapsed, shift, 8.0 / (double)(1u << shift));
            return;
        }

        if (now - lastStep < std::chrono::seconds(kLadderStepSeconds))
            continue;
        lastStep = now;

        const int shift = cemu_bridge_get_timebase_shift();
        if (shift >= kLadderFloorShift) {
            PPCGuestLiveness guest{};
            PPCCore_getLiveness(guest);
            cemuLog_log(LogType::Force,
                "Emulated timebase: the ladder is at its floor - shift {} (1/64 real time) - and after "
                "{:.1f}s the title still has not reached GX2Init ({} guest instructions retired). The "
                "guest's clock is not what is holding this title, so the ladder stops rather than making "
                "the console slower to no purpose.",
                shift, elapsed, guest.cyclesRetired);
            return;
        }

        cemuLog_log(LogType::Force,
            "Emulated timebase: no GX2Init after {:.1f}s, stepping the guest's clock down to shift {} "
            "({:.4g}x real time). This is the ladder searching, not a value anyone chose.",
            elapsed, shift + 1, 8.0 / (double)(1u << (shift + 1)));
        cemu_bridge_set_timebase_shift(shift + 1);
    }
}
#endif

// Started once a title is actually running, and joined before another can start, so two
// ladders can never be walking the same clock in opposite directions.
static void ios_timebase_ladder_stop() {
#if defined(CEMU_CORE_AVAILABLE)
    std::lock_guard lock{g_timebaseLadderMutex};
    g_timebaseLadderRunning.store(false);
    if (g_timebaseLadderThread.joinable())
        g_timebaseLadderThread.join();
#endif
}

static void ios_timebase_ladder_start() {
#if defined(CEMU_CORE_AVAILABLE)
    ios_timebase_ladder_stop();
    if (!g_timebaseAutoEnabled.load())
        return;
    // Not under the recompiler. There the guest's clock and the emulated CPU are in roughly
    // the right relationship already, and slowing the clock would be a pure loss.
    if (g_cpuMode.load() != kCpuModeInterpreter)
        return;
    std::lock_guard lock{g_timebaseLadderMutex};
    g_timebaseLadderRunning.store(true);
    g_timebaseLadderThread = std::thread(ios_timebase_ladder_entry);
    cemuLog_log(LogType::Force,
        "Emulated timebase: automatic clock ladder armed - if the title has not reached GX2Init after "
        "{}s the clock steps down one notch, to a floor of 1/64 real time.", kLadderStepSeconds);
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
    ios_timebase_ladder_stop();
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

// Declared in CemuBridge.h since the emulated-GamePad commit but never actually defined
// here, which nothing noticed only because no caller existed yet. It does now.
void cemu_bridge_refresh_input_devices(void) {
#if defined(CEMU_CORE_AVAILABLE)
    IOSInput_RefreshDevices();
#endif
}

void cemu_bridge_set_button_state(CemuBridgeButton button, bool pressed) {
#if defined(CEMU_CORE_AVAILABLE)
    // Passed as a plain int, and translated back on the other side. IOSInput_* is
    // declared here by hand rather than by #including InputManager.h - that header pulls
    // in SDL2/SDL.h and the whole input stack, which build under CMake but would have to
    // be made to work a second time inside Xcode's build of this one file - so the
    // declaration cannot name a type Cemu's own headers do not define, and CemuBridge.h
    // is not something src/input should be forced to include just for a signature.
    IOSInput_SetButtonState((int)button, pressed);
#else
    (void)button; (void)pressed;
#endif
}

void cemu_bridge_set_stick_axis(CemuBridgeStick stick, float x, float y) {
#ifdef CEMU_CORE_AVAILABLE
    // Clamped here rather than in Swift so every caller gets the same guarantee, and by
    // magnitude rather than per-component: clamping x and y separately would let a
    // corner-of-the-square input through as 1.41 units of deflection.
    const float magnitude = std::sqrt(x * x + y * y);
    if (magnitude > 1.0f) {
        x /= magnitude;
        y /= magnitude;
    }
    // NaN survives every comparison above, and a NaN written into the override would be
    // neither zero (so it wins over the physical controller) nor a usable deflection.
    if (std::isnan(x) || std::isnan(y))
        return;
    IOSInput_SetStickAxis((int)stick, x, y);
#else
    (void)stick; (void)x; (void)y;
#endif
}

void cemu_bridge_release_all_buttons(void) {
#if defined(CEMU_CORE_AVAILABLE)
    IOSInput_ReleaseAllButtons();
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
