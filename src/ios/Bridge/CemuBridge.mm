//
//  CemuBridge.mm
//  MuffinEMU's Swift <-> engine bridge, running on the Cemu core.
//
//  Swift talks to the engine only through the C functions in CemuBridge.h. This file
//  implements them against the core and nothing else:
//    * src/main.cpp            - CemuInitialize / CemuRun / CemuShutdown
//    * src/gui/uikit/          - CemuUIKit_* (surfaces, window geometry, visible outputs)
//    * src/input/api/iOS/      - GCControllerBridge_* (controllers)
//    * Core/*.cpp next to this - title launch, decrypt, DLC/update import, graphic packs,
//                                pause - built only from functions the core already exports
//
//  It is compiled into Cemu.framework by CMake (see src/CMakeLists.txt), so it sees the
//  core's headers and precompiled header directly. The Xcode app only ever sees
//  CemuBridge.h, which is plain C.
//
#include "Common/precompiled.h"
#include <cxxabi.h>
#include <typeinfo>
#import "CemuBridge.h"
#import "IOSLiveLog.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <sys/sysctl.h>
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
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <exception>
#include <typeinfo>
#include <filesystem>
#include <set>
#include <mach/mach.h>
#include <os/proc.h>
#include <dlfcn.h>

#include "Cafe/CafeSystem.h"
#include "Cafe/Filesystem/FST/KeyCache.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Core/LatteWaitInfo.h"
#include "util/Fiber/Fiber.h"
#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cemu/Logging/CemuLogging.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"
#include "Common/version.h"
#include "gui/interface/WindowSystem.h"
#include "input/api/iOS/GCControllerProvider.h"
#include "input/emulated/EmulatedController.h"
#include "input/emulated/VPADController.h"
#include "input/InputManager.h"
#include "util/crypto/aes128.h"

// Library scans open encrypted game folders (title.tmd + title.tik + .app files) before
// the engine starts, and the AES routines are null until AES128_init() runs. Initialise
// them as soon as the framework loads; AES128_init() is safe to call again from
// CemuInitialize().
__attribute__((constructor)) static void ios_crypto_init_at_load() { AES128_init(); }

// Forward-declared here because coreinit_Thread.h pulls the whole scheduler surface into
// this ARC-compiled translation unit. Must stay OUTSIDE the extern "C" block: a namespace
// nested inside extern "C" keeps C linkage, so the reference would not match the mangled
// C++ definition and the framework would fail to link.
namespace coreinit { void OSSetThermalThrottleMicros(uint32 micros); }

// The core's C entry points. Defined inside extern "C" blocks in src/main.cpp and
// src/gui/uikit/WindowSystem.mm, and not declared in any header this
// bridge includes, so they are declared again here.
extern "C" {
void CemuInitialize(const char* execPath, const char* user_data_path, const char* config_path, const char* cache_path, const char* data_path);
void CemuRun(void);
void CemuPrepareRenderer(void);
void CemuShutdown(void);
void CemuUIKit_SetMainWindow(UIWindow* window);
void CemuUIKit_SetMainView(UIView* view);
void CemuUIKit_SetPadView(UIView* view);
void CemuUIKit_InitializeLayer(bool main);
void CemuUIKit_UpdateMainWindowSize(CGFloat width, CGFloat height, CGFloat scale);

void CemuUIKit_UpdatePadWindowSize(void);
void CemuUIKit_SetVisibleOutputs(bool tv, bool pad);
void CemuUIKit_DescribeMainSurface(char* out, size_t outSize);
void CemuUIKit_SetPadTouch(CGFloat x, CGFloat y, bool down);
void* GCControllerBridge_add(const GCBridgeControllerDesc* desc);
void GCControllerBridge_remove(void* handle);
void GCControllerBridge_notifyChanged(void);
int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);
}

// Muffin's glue, in Core/. Plain C++ linkage: only this file calls them.
int IOSTitleLaunch_PrepareForegroundTitle(const char* path);
const char* IOSTitleLaunch_LastErrorDetail();
int IOSTitleLaunch_ReloadAndCountKeys();
int IOSTitleLaunch_PrepareForegroundTitleById(uint64_t titleId);
int IOSTitleDecrypt_ExtractToFolder(const char* srcPath, const char* destFolderPath,
    std::atomic_bool& cancelRequested,
    const std::function<void(uint64_t bytesWritten, uint32_t filesWritten)>& progressCallback);
int IOSTitleDecrypt_ExtractToWua(const char* srcPath, const char* destPath,
    std::atomic_bool& cancelRequested,
    const std::function<void(uint64_t bytesWritten, uint32_t filesWritten)>& progressCallback);
std::string IOSCoverArt_DeriveGameTdbId(const char* romPath);
std::string IOSCoverArt_GetTitleName(const char* romPath);
bool IOSDlcUpdateImport_DeriveTitleId(const char* romPath, uint64_t* titleIdOut);
bool IOSDlcUpdateImport_ReadTmdTitleId(const char* tmdPath, uint64_t* titleIdOut);
uint64_t IOSDlcUpdateImport_DeriveBaseTitleId(uint64_t titleId);
int IOSDlcUpdateImport_GetTitleType(uint64_t titleId);
void IOSDlcUpdateImport_GetMlcTitlePathComponents(uint64_t titleId, char* outUpperHex, char* outLowerHex);
bool IOSDlcUpdateImport_Inspect(const char* romPath, uint64_t* outTitleId, uint16_t* outVersion,
    int* outRegion, int* outInvalidReason);
uint64_t IOSDlcUpdateImport_DeriveContentTitleId(uint64_t baseTitleId, bool isUpdate);
int IOSEmulatedDevices_SlotCount(int device);
std::string IOSEmulatedDevices_SlotNames(int device);
std::string IOSEmulatedDevices_FigureList(int device, int slot);
std::string IOSEmulatedDevices_Load(int device, int slot, const char* path);
std::string IOSEmulatedDevices_Clear(int device, int slot);
std::string IOSEmulatedDevices_Create(int device, uint32_t figureId, uint16_t variant, const char* path);
std::string IOSEmulatedDevices_MoveDimensions(int fromSlot, int toSlot);
std::string IOSGraphicPacks_List();
void IOSGraphicPacks_Refresh();
void IOSGraphicPacks_SetEnabled(int index, bool enabled);
void IOSAccounts_Refresh();
std::string IOSAccounts_List();
bool IOSAccounts_HasFreeSlot();
uint32_t IOSAccounts_NextPersistentId();
uint32_t IOSAccounts_MinPersistentId();
bool IOSAccounts_Locked();
bool IOSAccounts_Create(uint32_t persistentId, const char* miiName, uint16_t birthYear,
    uint8_t birthMonth, uint8_t birthDay, int gender, const char* email, int country);
bool IOSAccounts_Delete(uint32_t persistentId);
bool IOSAccounts_SetMiiName(uint32_t persistentId, const char* miiName);
bool IOSAccounts_SetGender(uint32_t persistentId, int gender);
bool IOSAccounts_SetEmail(uint32_t persistentId, const char* email);
bool IOSAccounts_SetCountry(uint32_t persistentId, int country);
bool IOSAccounts_SetBirthdate(uint32_t persistentId, uint16_t year, uint8_t month, uint8_t day);
uint32_t IOSAccounts_ActivePersistentId();
void IOSAccounts_SetActivePersistentId(uint32_t persistentId);
bool IOSAccounts_IsOnlineValid(uint32_t persistentId);
std::string IOSAccounts_CountriesList();
int IOSAccounts_NetworkService(uint32_t persistentId);
void IOSAccounts_SetNetworkService(uint32_t persistentId, int service);
bool IOSAccounts_CustomNetworkServiceAvailable();
bool IOSTitlePause_Pause();
bool IOSTitlePause_Resume();
bool IOSTitlePause_IsPaused();
void IOSTitlePause_Forget();
bool IOSSaveState_Save(const char* path);
bool IOSSaveState_Load(const char* path);
void IOSSystemImplementation_Install();
bool IOSSystemImplementation_TitleExited(int* statusOut);
bool IOSSystemImplementation_TitleSwitchFailed();
void IOSSystemImplementation_ReportFatal(const char* reason);
const char* IOSSystemImplementation_FatalReason();
void IOSSystemImplementation_ResetExit();

// ---------------------------------------------------------------------------
// Crash trail
//
// A GPU driver panic or a jetsam kill is not delivered as a catchable signal, so the
// checkpoint trail below is what survives one: every line is a synchronous write() to
// Documents/CemuCrashLog.txt that is on disk before the next line of code runs. The
// signal and terminate handlers are installed from a constructor(101) so a crash in any
// engine static initializer, before main(), is still caught.
namespace {
    int g_crashLogFd = -1;
    char g_crashLogPath[1024] = {0};

    void cemu_crash_write(const char* s) {
        if (g_crashLogFd >= 0 && s) write(g_crashLogFd, s, strlen(s));
    }

    // Async-signal-safe calls only.
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

        // Re-raise so iOS still writes its own report as well.
        signal(signum, SIG_DFL);
        raise(signum);
    }

    void cemu_crash_open_log() {
        if (g_crashLogFd >= 0)
            return;
        const char* home = getenv("HOME");
        if (!home)
            return;
        char path[1024];
        snprintf(path, sizeof(path), "%s/Documents/CemuCrashLog.txt", home);
        g_crashLogFd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        // Recorded because under LiveContainer $HOME is redirected per hosted app, so the
        // file is not where it would be for a normal install. The app prints this path.
        snprintf(g_crashLogPath, sizeof(g_crashLogPath), "%s", path);
        // Pre-warm backtrace()'s lazy state outside signal context.
        void* warm[4];
        backtrace(warm, 4);
    }

    std::terminate_handler g_previousTerminateHandler = nullptr;

    // std::terminate is the one place an escaping exception's type and what() are still
    // recoverable. Write both, then chain so the signal handler still adds its backtrace.
    void cemu_terminate_handler() {
        cemu_crash_open_log();
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
    g_previousTerminateHandler = std::set_terminate(cemu_terminate_handler);
}

const char* cemu_bridge_crash_log_path(void) {
    cemu_crash_open_log();
    return g_crashLogPath;
}

void cemu_bridge_log_checkpoint(const char* message) {
    cemu_crash_open_log();
    cemu_crash_write(message);
    cemu_crash_write("\n");
    // Mirrored into the live ring so the on-screen launch log is one timeline.
    ios_live_log_push(message);
}

// ---------------------------------------------------------------------------
// Memory trail
//
// Jetsam delivers no signal and takes any buffered log with it, so these samples go
// through the synchronous checkpoint write, not cemuLog.
namespace {
    std::atomic<bool> g_memWatchRunning{false};

    // phys_footprint is what jetsam bills; resident_size undercounts.
    uint64_t cemu_mem_footprint_bytes() {
        task_vm_info_data_t info{};
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
            return 0;
        return (uint64_t)info.phys_footprint;
    }

    // Total address space the process has mapped or reserved. On iOS this can run out long before RAM does
    // (the guest's 4 GB reservation and the JIT arena are all address space), so it is logged beside RAM.
    uint64_t cemu_mem_virtual_bytes() {
        task_vm_info_data_t info{};
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
            return 0;
        return (uint64_t)info.virtual_size;
    }

    void cemu_mem_write_line(const char* tag, uint64_t availableBytes, uint64_t footprintBytes) {
        char line[720];
        int n = snprintf(line, sizeof(line),
                 "MEM %s: %llu MB still available to this process, %llu MB in use",
                 tag,
                 (unsigned long long)(availableBytes / (1024ull * 1024ull)),
                 (unsigned long long)(footprintBytes / (1024ull * 1024ull)));
        // Where the GPU side's memory is, as last published by the GPU thread (LatteWaitInfo.h), so one
        // line can name what grew. Absent until a Metal renderer has published once.
        if (n > 0 && n < (int)sizeof(line))
        {
            int m = snprintf(line + n, sizeof(line) - n, " | address space reserved %llu MB", (unsigned long long)(cemu_mem_virtual_bytes() / (1024ull * 1024ull)));
            if (m > 0) n += m;
        }
        auto& w = LatteWait::Get();
        if (n > 0 && n < (int)sizeof(line) && w.memStatsValid.load())
        {
            snprintf(line + n, sizeof(line) - n,
                     " | GPU: device %u MB (host-mapped %u MB), textures %u = %u MB, staging %u MB, index %u MB, snapshots %u MB, "
                     "buffer cache %u MB, streamout %u MB, readback %u MB, command buffers in flight %u, textures evicted %u",
                     (unsigned)w.memDeviceMB.load(), (unsigned)w.memHostMappedMB.load(), (unsigned)w.memTextureCount.load(), (unsigned)w.memTextureMB.load(),
                     (unsigned)w.memStagingMB.load(), (unsigned)w.memIndexMB.load(), (unsigned)w.memSnapshotMB.load(), (unsigned)w.memBufferCacheMB.load(),
                     (unsigned)w.memXfbMB.load(), (unsigned)w.memReadbackMB.load(), (unsigned)w.executingCommandBuffers.load(), (unsigned)w.texturesEvicted.load());
        }
        cemu_bridge_log_checkpoint(line);
    }
}

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

// The raw model identifier rather than a marketing name: a lookup table is out of date
// the day a device ships, and a wrong name is worse than an identifier.
// Built once, under the thread-safe static initialiser, so concurrent first callers can't
// observe a half-built string; the returned pointer stays valid for the process lifetime.
// Describes the exception currently being handled. Call only from inside a catch block.
static std::string cemu_describe_current_exception(void)
{
    try { throw; }
    catch (const std::exception& ex) { return std::string(typeid(ex).name()) + ": " + ex.what(); }
    catch (...)
    {
        const std::type_info* type = abi::__cxa_current_exception_type();
        return std::string("non-standard exception ") + (type ? type->name() : "of unknown type");
    }
}

static std::string cemu_build_device_report(void)
{
    std::string report;
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
    report = buf;

    if (pcores && ecores)
    {
        snprintf(buf, sizeof(buf), " (%llu perf + %llu eff)",
                 (unsigned long long)pcores, (unsigned long long)ecores);
        report += buf;
    }
    if (avail)
    {
        snprintf(buf, sizeof(buf), " | %llu MB available to this app before iOS kills it",
                 (unsigned long long)(avail / (1024ull * 1024ull)));
        report += buf;
    }
    // BUILD_VERSION_STRING is a parenthesised expression, not a bare literal.
    report += " | build ";
    report += BUILD_VERSION_STRING;
    return report;
}

extern "C" const char* cemu_bridge_device_report(void)
{
    static const std::string report = cemu_build_device_report();
    return report.c_str();
}

// Declared here rather than in a header: PPCRecompiler.h is a core header the bridge does
// not otherwise pull in, and this is one symbol.
size_t PPCRecompiler_getJitArenaSize();
size_t PPCRecompiler_getJitArenaUsed();

const char* cemu_bridge_memory_headroom_summary(void) {
    static thread_local std::string summary;
    const uint64_t avail = (uint64_t)os_proc_available_memory();
    const uint64_t arena = (uint64_t)PPCRecompiler_getJitArenaSize();

    // Reports what iOS actually granted, not which entitlements were requested; the JIT
    // arena size shows whether the recompiler got room to work.
    char buf[256];
    if (arena == 0) {
        snprintf(buf, sizeof(buf),
            "%llu MB headroom - no JIT arena, so this launch is running the interpreter",
            (unsigned long long)(avail / (1024ull * 1024ull)));
    } else {
        // Reserved address space costs almost nothing; "in use" is what the process holds.
        const uint64_t used = (uint64_t)PPCRecompiler_getJitArenaUsed();
        snprintf(buf, sizeof(buf), "%llu MB headroom - JIT arena %llu MB reserved, %llu MB in use%s",
            (unsigned long long)(avail / (1024ull * 1024ull)),
            (unsigned long long)(arena / (1024ull * 1024ull)),
            (unsigned long long)(used / (1024ull * 1024ull)),
            arena < (1024ull << 20) ? " (reduced - less room than the JIT asked for)" : "");
    }
    summary = buf;
    return summary.c_str();
}

bool cemu_bridge_memory_status(unsigned long long* availableBytes, unsigned long long* footprintBytes) {
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

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
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
        // Bucketed so a steady footprint writes nothing; once a minute otherwise, to show
        // the sampler is alive without burying the log.
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

            const uint64_t footBucket = foot / (32ull << 20);
            const uint64_t availBucket = avail / (64ull << 20);
            const auto now = std::chrono::steady_clock::now();

            bool report = footBucket > lastFootBucket || availBucket < lastAvailBucket;
            if (now - lastForced >= std::chrono::seconds(60)) report = true;
            lastFootBucket = footBucket;
            lastAvailBucket = availBucket;

            if (report)
            {
                cemu_mem_write_line("sample", avail, foot);
                lastForced = now;
            }

            if (!criticalAnnounced && avail > 0 && avail < (128ull << 20))
            {
                criticalAnnounced = true;
                cemu_mem_write_line("CRITICAL - a kill by iOS is likely imminent", avail, foot);
            }
        }
    }).detach();
}

// ---------------------------------------------------------------------------
// Bridge state
namespace {
    std::atomic<bool> g_initialized{false};

    // One status string for the whole bridge, not one per thread: the boot runs on a
    // background task and the UI reads it from the main thread.
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

    // Copied under the lock into a per-thread snapshot; String(cString:) copies at once.
    const char* getStatus() {
        static thread_local std::string snapshot;
        {
            std::lock_guard<std::mutex> lock(g_statusMutex);
            snapshot = g_statusText;
        }
        return snapshot.c_str();
    }

    // 0 = not decided yet, 1 = interpreter, 2 = recompiler. 0 is not 1: "nothing has
    // looked" is a different claim from "the interpreter".
    constexpr int kCpuModeUndecided   = 0;
    constexpr int kCpuModeInterpreter = 1;
    constexpr int kCpuModeRecompiler  = 2;

    std::atomic<int> g_cpuMode{kCpuModeUndecided};
    std::atomic<bool> g_recompilerRequested{false};
    std::atomic<bool> g_favourAccuracy{false};
    // Low Power Mode. Separate from Favour accuracy on purpose: both end up asking for
    // one emulated CPU core, but for opposite reasons and with different side effects.
    // Favour accuracy also forces synchronous shader compilation, accurate Vulkan
    // barriers and GX2DrawDone sync - all of which cost MORE work, not less, and are the
    // last thing a device that is already too hot needs. Low power wants the core count
    // down and nothing else changed.
    std::atomic<bool> g_lowPowerMode{false};
    // Off by default: see ios_apply_cpu_mode() for the measurement that made one core
    // the default rather than three.
    std::atomic<bool> g_multicoreRequested{false};
    std::mutex g_cpuModeDetailMutex;
    std::string g_cpuModeDetail;

    void setCpuModeDetail(std::string detail) {
        std::lock_guard<std::mutex> lock(g_cpuModeDetailMutex);
        g_cpuModeDetail = std::move(detail);
    }

    const char* getCpuModeDetail() {
        static thread_local std::string snapshot;
        {
            std::lock_guard<std::mutex> lock(g_cpuModeDetailMutex);
            snapshot = g_cpuModeDetail;
        }
        return snapshot.c_str();
    }

    std::atomic<bool> g_titleRunning{false};
    std::atomic<bool> g_padRegistered{false};
    // The MoltenVK build selected for this launch, "" before initialize.
    std::string g_activeMoltenVK;
}

static void ios_timebase_ladder_start();
static void ios_timebase_ladder_stop();

// ---------------------------------------------------------------------------
// JIT environment
//
// Launch-time checks for the JIT (dual-mapped memory and TXM detection), because the
// recompiler reads the answers from the environment:
// DUAL_MAPPED_JIT selects the dual-mapped arena that iOS 26 needs, and HAS_TXM tells it
// whether the Trusted Execution Monitor is enforcing, which changes how that arena has
// to be mapped. Set before CemuInitialize(), and never changed afterwards.
namespace {

NSString* ios_first_entry_with_length(NSString* dir, NSUInteger length)
{
    NSArray<NSString*>* entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString* entry in entries)
        if (entry.length == length)
            return [dir stringByAppendingPathComponent:entry];
    return nil;
}

bool ios_has_txm_classic()
{
    if ([NSProcessInfo processInfo].isiOSAppOnMac)
        return false;
    static NSString* const kImg4 = @"usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4";
    if (NSString* boot = ios_first_entry_with_length(@"/System/Volumes/Preboot", 36))
    {
        if (NSString* file = ios_first_entry_with_length([boot stringByAppendingPathComponent:@"boot"], 96))
            return access([[file stringByAppendingPathComponent:kImg4] fileSystemRepresentation], F_OK) == 0;
    }
    if (NSString* preboot = ios_first_entry_with_length(@"/private/preboot", 96))
        return access([[preboot stringByAppendingPathComponent:kImg4] fileSystemRepresentation], F_OK) == 0;
    return false;
}

// "Apple M2" -> ('M', 2), "Apple A12Z GPU" -> ('A', 12).
bool ios_chip(char& series, int& number)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device)
        return false;
    NSString* name = device.name.uppercaseString;
    NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"APPLE\\s+([MA])(\\d+)" options:0 error:nil];
    NSTextCheckingResult* m = [re firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (!m)
        return false;
    series = (char)[[name substringWithRange:[m rangeAtIndex:1]] characterAtIndex:0];
    number = [[name substringWithRange:[m rangeAtIndex:2]] intValue];
    return true;
}

bool ios_os_at_least(NSInteger major, NSInteger minor)
{
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){major, minor, 0}];
}

bool ios_has_txm()
{
    char series = 0;
    int number = 0;
    const bool known = ios_chip(series, number);
    if (ios_os_at_least(27, 0))
    {
        // A12 is the last A-series chip without TXM.
        if (known && series == 'A')
            return number > 12;
        return true;
    }
    if (ios_os_at_least(26, 6) && !ios_has_txm_classic())
    {
        if (!known)
            return false;
        return series == 'M' ? number >= 2 : number >= 15;
    }
    return ios_has_txm_classic();
}

void ios_configure_jit_environment()
{
    if (ios_os_at_least(19, 0))
    {
        const bool txm = ![NSProcessInfo processInfo].isiOSAppOnMac && ios_has_txm();
        setenv("DUAL_MAPPED_JIT", "1", 1);
        setenv("HAS_TXM", txm ? "1" : "0", 1);
    }
    else
    {
        setenv("HAS_TXM", "0", 1);
    }
    cemu_bridge_log_checkpoint((std::string("JIT environment: DUAL_MAPPED_JIT=") + (getenv("DUAL_MAPPED_JIT") ? getenv("DUAL_MAPPED_JIT") : "unset") +
        " HAS_TXM=" + (getenv("HAS_TXM") ? getenv("HAS_TXM") : "unset")).c_str());
}

// CS_DEBUGGED waives the signature check at instruction fetch. It is what every JIT
// enabler (StikJIT, SideStore, LiveContainer, a debugger) produces, and it is the same
// flag the core's recompiler checks before it generates code.
bool ios_process_is_debugged(uint32_t& flagsOut)
{
    flagsOut = 0;
    return csops(getpid(), 0 /* CS_OPS_STATUS */, &flagsOut, sizeof(flagsOut)) == 0 && (flagsOut & 0x10000000u) != 0;
}

// Decides the CPU path for the next boot from the two Settings toggles and what the
// process can actually do, and records both the answer and the reason. Written into the
// engine's own config, which is what the core's CafeSystem reads when a title starts.
//
// Always an explicit mode, never Auto. On iOS the core's GetCPUMode() returns the config
// value unresolved, and _LaunchTitleThread() only starts the three emulated cores on their
// own host threads for the two Multicore modes - so Auto, the core's default, ran every
// title on one thread. Speed first means Multicore; Favour accuracy means Singlecore, the
// mode Cemu is most compatible in.
void ios_apply_cpu_mode()
{
    uint32_t csFlags = 0;
    const bool debugged = ios_process_is_debugged(csFlags);
    const bool accuracy = g_favourAccuracy.load();
    const bool lowPower = g_lowPowerMode.load();
    // Single-core is the default; multi-core has to be requested (cemu_bridge_set_multicore_enabled).
    // On iOS the core starts the three emulated cores on their own host threads only for the
    // explicit Multicore modes, and those threads reschedule without sleeping. On a fanless
    // A12Z iPad Pro running Wind Waker HD, one core held 40-60fps while three managed 4-20:
    // the extra power draw heats the SoC within a minute and the clocks drop.
    const bool singleCore = accuracy || lowPower || !g_multicoreRequested.load();
    const char* cores = singleCore ? "single-core" : "multi-core";
    auto& config = GetConfig();
    char detail[320];

    if (!g_recompilerRequested.load() || !debugged)
    {
        // Without CS_DEBUGGED the interpreter is the only option, not a preference: the
        // kernel kills the process the moment it runs generated code, and an explicit
        // recompiler mode skips the debugger check the core applies to Auto.
        config.cpu_mode = singleCore ? CPUMode::SinglecoreInterpreter : CPUMode::MulticoreInterpreter;
        g_cpuMode.store(kCpuModeInterpreter);
        if (!g_recompilerRequested.load())
            snprintf(detail, sizeof(detail), "The recompiler is off in Settings, so the %s interpreter is running.", cores);
        else
            snprintf(detail, sizeof(detail), "The recompiler is on in Settings, but no JIT enabler is attached (cs_flags 0x%08x), "
                "so the %s interpreter is running. Launch through StikJIT, SideStore or LiveContainer to use the recompiler.", csFlags, cores);
        setCpuModeDetail(detail);
        return;
    }
    config.cpu_mode = singleCore ? CPUMode::SinglecoreRecompiler : CPUMode::MulticoreRecompiler;
    g_cpuMode.store(kCpuModeRecompiler);
    snprintf(detail, sizeof(detail), "A JIT enabler is attached, so the AArch64 recompiler runs this launch, %s%s.",
        cores, lowPower ? " because Low Power Mode is on" : (accuracy ? " because Favour accuracy is on" : ""));
    setCpuModeDetail(detail);
}

// The GPU half of Favour accuracy. Off, the accuracy-only work is skipped and shader
// compilation is left to the Swift side's per-game choice; on, every shader is built
// before the frame that needs it, Vulkan barriers are placed exactly, and the CPU waits
// for the GPU at GX2DrawDone the way the console does.
void ios_apply_render_profile()
{
    auto& config = GetConfig();
    const bool accuracy = g_favourAccuracy.load();
    config.vk_accurate_barriers = accuracy;
    config.gx2drawdone_sync = accuracy;
    if (accuracy)
        config.async_compile = false;
    cemuLog_log(LogType::Force, "iOS: {} - async shaders {}, accurate barriers {}, GX2DrawDone sync {}",
        accuracy ? "favouring accuracy" : "favouring speed",
        config.async_compile.GetValue(), config.vk_accurate_barriers.GetValue(), config.gx2drawdone_sync.GetValue());
}

}  // namespace

// ---------------------------------------------------------------------------
// Live launch log
//
// The core's logger writes log.txt and nothing else, so the engine's own lines reach the
// on-screen launch log by tailing that file. Checkpoints and bridge lines are pushed into
// the same ring directly, so the two interleave in the order they were written.
namespace {
    std::atomic<bool> g_logTailRunning{false};

    void ios_log_tail_start()
    {
        if (g_logTailRunning.exchange(true))
            return;
        const std::string path = _pathToUtf8(ActiveSettings::GetUserDataPath("log.txt"));
        std::thread([path] {
            long offset = 0;
            std::string partial;
            char chunk[4096];
            while (g_logTailRunning.load())
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                FILE* f = fopen(path.c_str(), "rb");
                if (!f)
                    continue;
                fseek(f, 0, SEEK_END);
                const long size = ftell(f);
                // A smaller file is a new log (the core truncates at start); read it from the top.
                if (size < offset)
                {
                    offset = 0;
                    partial.clear();
                }
                fseek(f, offset, SEEK_SET);
                size_t n;
                while ((n = fread(chunk, 1, sizeof(chunk), f)) > 0)
                {
                    offset += (long)n;
                    partial.append(chunk, n);
                    size_t nl;
                    while ((nl = partial.find('\n')) != std::string::npos)
                    {
                        std::string line = partial.substr(0, nl);
                        if (!line.empty() && line.back() == '\r')
                            line.pop_back();
                        ios_live_log_push(line.c_str());
                        partial.erase(0, nl + 1);
                    }
                }
                fclose(f);
            }
        }).detach();
    }
}

// ---------------------------------------------------------------------------
// Frame statistics
//
// The core's window system discards the FPS the performance monitor reports, so the rate
// is measured here from the GPU state the core already keeps: LatteGPUState.frameCounter
// is incremented once per frame the emulated GPU finishes. Fractional on purpose - a
// title rendering at 0.4 frames per second is slow, not stopped.
namespace {
    std::atomic<double> g_framesPerSecond{0.0};
    std::atomic<bool> g_statsRunning{false};

    void ios_stats_start()
    {
        if (g_statsRunning.exchange(true))
            return;
        std::thread([] {
            uint32 lastFrames = 0;
            auto lastTime = std::chrono::steady_clock::now();
            bool haveBaseline = false;
            while (g_statsRunning.load())
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(500));
                if (!g_titleRunning.load() || IOSTitlePause_IsPaused())
                {
                    g_framesPerSecond.store(0.0);
                    haveBaseline = false;
                    continue;
                }
                const uint32 frames = LatteGPUState.frameCounter;
                const auto now = std::chrono::steady_clock::now();
                if (haveBaseline && frames >= lastFrames)
                {
                    const double dt = std::chrono::duration<double>(now - lastTime).count();
                    if (dt > 0.0)
                        g_framesPerSecond.store((double)(frames - lastFrames) / dt);
                }
                lastFrames = frames;
                lastTime = now;
                haveBaseline = true;
            }
        }).detach();
    }
}

// ---------------------------------------------------------------------------
// Render-stall watchdog
//
// The game's audio and input run on the guest CPU, the picture on the GPU thread, and the
// two are not tied together (the speed setting "Full sync at GX2DrawDone" is off), so the
// GPU side can stop while everything else carries on. LatteGPUState.frameCounter is bumped
// once per emulated frame; if it stops moving for a few seconds while a title is running and
// not paused, the picture has stopped. The watchdog raises a flag for the UI and writes one
// snapshot of everything the GPU thread's breadcrumbs (LatteWaitInfo.h) can say about why.
namespace {
    std::atomic<bool> g_videoStalled{false};
    std::atomic<int> g_videoStallKind{0}; // 0 none, 1 picture stopped, 2 GPU error
    std::atomic<bool> g_stallWatchRunning{false};
    std::atomic<bool> g_appIsActive{true};

    // Clears the stall flag, the stall kind and the GPU-fault state (a failed command buffer, a
    // presumed-lost GPU, the drawable-failure count). Used when a title ends and when a title
    // switch replaces the renderer: those flags describe the renderer that is being thrown away,
    // and left set they would make the watchdog report the new title as stalled, or as
    // GPU-faulted, before it has drawn a frame.
    void ios_reset_video_stall_state()
    {
        g_videoStalled.store(false);
        g_videoStallKind.store(0);
        auto& w = LatteWait::Get();
        w.gpuError.store(false);
        w.gpuErrorCode.store(0);
        w.gpuPresumedLost.store(false);
        w.memStatsValid.store(false);
        w.drawableFailuresInARow.store(0);
    }

    void ios_stall_log_snapshot(double stalledSeconds)
    {
        auto& w = LatteWait::Get();
        const char* reason = w.reason.load();
        const int64_t reasonMs = reason ? (LatteWait::NowMs() - w.reasonSinceMs.load()) : 0;
        const char* lastTimeout = w.lastTimeoutReason.load();
        auto& info = WindowSystem::GetWindowInfo();

        char surface[640];
        CemuUIKit_DescribeMainSurface(surface, sizeof(surface));

        if (w.gpuError.load())
            cemuLog_log(LogType::Force, "VIDEO STALL: GPU ERROR - a command buffer failed with code {}; iOS stops running this app's GPU work after that", w.gpuErrorCode.load());
        else if (w.drawableFailuresInARow.load() >= 8)
            cemuLog_log(LogType::Force, "VIDEO STALL: OUT OF MEMORY FOR THE SCREEN - {} drawable requests in a row failed (iOS cannot give the layer a new frame buffer)", w.drawableFailuresInARow.load());
        else
            cemuLog_log(LogType::Force, "VIDEO STALL: no frame for {:.1f} s while the title is running and not paused (frame {}, flips {}, draw calls {})",
                stalledSeconds, (uint32)LatteGPUState.frameCounter, (uint32)LatteGPUState.flipCounter, (uint32)LatteGPUState.drawCallCounter);
        if (reason)
            cemuLog_log(LogType::Force, "VIDEO STALL: GPU thread is blocked: {} (for {} ms)", reason, reasonMs);
        else
            cemuLog_log(LogType::Force, "VIDEO STALL: GPU thread is not in a known wait (it is running, or stuck somewhere without a breadcrumb)");
        cemuLog_log(LogType::Force, "VIDEO STALL: last PM4 opcode 0x{:02x}, guest flip requests {}, GX2Init calls {}",
            w.lastPM4Opcode.load(), (uint64)LatteGPUState.flipRequestCount.load(), (uint32)LatteGPUState.gx2InitCalled);
        cemuLog_log(LogType::Force, "VIDEO STALL: pending: {} occlusion queries, {} texture readbacks, {} command buffers on the GPU, {} command buffers failed so far",
            w.queriesInFlight.load(), w.readbacksPending.load(), w.executingCommandBuffers.load(), w.erroredCommandBuffers.load());
        cemuLog_log(LogType::Force, "VIDEO STALL: waits that gave up: {} (last: {}), GPU presumed lost: {}",
            w.timeouts.load(), lastTimeout ? lastTimeout : "none", w.gpuPresumedLost.load() ? "yes" : "no");
        cemuLog_log(LogType::Force, "VIDEO STALL: presented frames {}, TV drawable held: {}, drawable failures {} ({} in a row), TV drawable size {}x{}, layer device {}",
            w.presentedFrames.load(), w.tvDrawableHeld.load() ? "yes" : "no", w.drawableFailures.load(), w.drawableFailuresInARow.load(),
            w.tvDrawableWidth.load(), w.tvDrawableHeight.load(), w.tvLayerHasDevice.load() ? "set" : "unknown/missing");
        cemuLog_log(LogType::Force, "VIDEO STALL: window {}x{} points at {:.2f}x scale ({}x{} px), visible outputs mask {}",
            (int)info.width, (int)info.height, (double)info.dpi_scale.load(), (int)info.phys_width, (int)info.phys_height, (uint32)info.visible_outputs.load());
        cemuLog_log(LogType::Force, "VIDEO STALL: TV view: {}", surface);
    }

    void ios_stall_watchdog_start()
    {
        if (g_stallWatchRunning.exchange(true))
            return;

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
            usingBlock:^(NSNotification*) { g_appIsActive.store(false); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
            usingBlock:^(NSNotification*) { g_appIsActive.store(false); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
            usingBlock:^(NSNotification*) { g_appIsActive.store(true); }];

        std::thread([] {
            constexpr double kStallSeconds = 4.0;
            constexpr double kBootStallSeconds = 45.0;
            uint32 lastFrames = 0;
            auto lastChange = std::chrono::steady_clock::now();
            auto lastReport = lastChange;
            bool haveBaseline = false;
            while (g_stallWatchRunning.load())
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(250));

                // Only judge a title that is really expected to be drawing: running, past GX2Init,
                // not paused, and the app in the foreground (iOS stops the GPU in the background).
                const bool expectFrames = g_titleRunning.load() && CafeSystem::IsTitleRunning()
                    && LatteGPUState.gx2InitCalled > 0 && !IOSTitlePause_IsPaused() && g_appIsActive.load();
                const auto now = std::chrono::steady_clock::now();
                const uint32 frames = LatteGPUState.frameCounter;

                // A failed GPU submission is reported at once and stays reported: after a page fault iOS
                // ignores the rest of this process's GPU work, so frames will not come back.
                if (g_titleRunning.load() && LatteWait::Get().gpuError.load())
                {
                    if (!g_videoStalled.exchange(true))
                    {
                        g_videoStallKind.store(2);
                        ios_stall_log_snapshot(0.0);
                    }
                    continue;
                }

                // Nearly out of memory: iOS is about to end the app. Say so now, while Save State still works.
                if (g_titleRunning.load() && (g_videoStallKind.load() < 2 || g_videoStallKind.load() == 4))
                {
                    const uint64_t availableNow = (uint64_t)os_proc_available_memory();
                    if (availableNow > 0 && availableNow < (160ull << 20))
                    {
                        g_videoStallKind.store(4);
                        if (!g_videoStalled.exchange(true))
                        {
                            cemuLog_log(LogType::Force, "VIDEO STALL: OUT OF MEMORY - only {} MB left before iOS ends the app", availableNow >> 20);
                            ios_stall_log_snapshot(0.0);
                        }
                        continue;
                    }
                    if (g_videoStallKind.load() == 4)
                    {
                        if (availableNow < (300ull << 20))
                            continue; // still tight, keep the card up
                        g_videoStalled.store(false);
                        g_videoStallKind.store(0);
                        cemuLog_log(LogType::Force, "VIDEO STALL: memory has recovered ({} MB free)", availableNow >> 20);
                    }
                }

                // Repeated failures to get a drawable from the layer: the screen itself is out of memory.
                if (g_titleRunning.load() && LatteWait::Get().drawableFailuresInARow.load() >= 8)
                {
                    if (g_videoStallKind.load() != 3)
                    {
                        g_videoStallKind.store(3);
                        g_videoStalled.store(true);
                        ios_stall_log_snapshot(0.0);
                    }
                    continue;
                }
                if (g_videoStallKind.load() == 3)
                {
                    g_videoStalled.store(false);
                    g_videoStallKind.store(0);
                    cemuLog_log(LogType::Force, "VIDEO STALL: drawables are available again");
                }

                if (!expectFrames || !haveBaseline || frames != lastFrames)
                {
                    if (g_videoStalled.exchange(false))
                        cemuLog_log(LogType::Force, "VIDEO STALL: frames are arriving again (frame {})", frames);
                    g_videoStallKind.store(0);
                    haveBaseline = expectFrames;
                    lastFrames = frames;
                    lastChange = now;
                    lastReport = now;
                    continue;
                }

                // Loading can go a long time without finishing a frame (3D World was flagged at frame 0),
                // so a title that has not drawn its first frames gets a much longer grace period.
                const double stalled = std::chrono::duration<double>(now - lastChange).count();
                if (stalled < (frames < 30 ? kBootStallSeconds : kStallSeconds))
                    continue;
                if (!g_videoStalled.exchange(true))
                {
                    g_videoStallKind.store(1);
                    ios_stall_log_snapshot(stalled);
                    lastReport = now;
                }
                else if (now - lastReport >= std::chrono::seconds(15))
                {
                    lastReport = now;
                    const char* reason = LatteWait::Get().reason.load();
                    cemuLog_log(LogType::Force, "VIDEO STALL: still stalled after {:.0f} s ({})", stalled, reason ? reason : "no known wait");
                }
            }
        }).detach();
    }
}

bool cemu_bridge_video_stalled(void) {
    return g_videoStalled.load();
}

int cemu_bridge_video_stall_kind(void) {
    return g_videoStalled.load() ? g_videoStallKind.load() : 0;
}

// ---------------------------------------------------------------------------
// Input
//
// One emulated GamePad fed from two sources at once: the on-screen pad (set from Swift)
// and the first physical GameController. Both are merged inside one GCBridge controller
// registered with the core's input manager, so the touch pad and an MFi controller work
// together and neither cancels the other. A button is down if either source holds it; a
// stick follows the touch pad while it is deflected and hands back to the physical stick
// at centre.
//
// Bit layout is the core's (src/input/api/iOS/GCController.mm), which its default VPAD
// mapping in InputManager.cpp binds to the GamePad buttons.
namespace {
    constexpr int kBitA = 0, kBitB = 1, kBitX = 2, kBitY = 3;
    constexpr int kBitL = 4, kBitR = 5, kBitZL = 6, kBitZR = 7;
    constexpr int kBitMinus = 8, kBitPlus = 9, kBitStickL = 10, kBitStickR = 11;
    constexpr int kBitUp = 16, kBitDown = 17, kBitLeft = 18, kBitRight = 19;

    std::mutex g_inputMutex;
    uint32_t g_touchButtons = 0;

    // Press latching for the on-screen pad. The core only looks at g_touchButtons when the
    // title calls VPADRead, which on a slow-running title can be 100ms or more apart in real
    // time - longer than an ordinary tap. A tap that went down and up between two reads was
    // never seen, which is why presses only registered when the finger was dragged (and so
    // held for longer). A released button now stays down until at least one read has seen
    // it AND kMinTouchHold has passed, then the release is applied on a later read.
    //
    // A second press that lands while the first is still being held back (mashing a
    // button) must not merge into one long press, or the title sees one press instead of
    // two. If a read has already seen the first press, the second is queued: the release
    // goes out on one read and the new press on the next.
    constexpr auto kMinTouchHold = std::chrono::milliseconds(50);
    uint32_t g_touchSeen = 0;            // pressed bits a poll has reported since the press
    uint32_t g_touchPendingRelease = 0;  // released by the finger, not yet by the latch
    uint32_t g_touchRepress = 0;         // pressed again while a release was pending
    uint32_t g_touchRepressQueued = 0;   // re-presses to apply at the next poll
    uint32_t g_touchRepressReleased = 0; // re-presses whose finger has already lifted
    std::chrono::steady_clock::time_point g_touchPressedAt[32] = {};

    bool ios_touch_release_due(int bit, std::chrono::steady_clock::time_point now)
    {
        return (g_touchSeen & (1u << bit)) && now - g_touchPressedAt[bit] >= kMinTouchHold;
    }
    GCBridgeVec2 g_touchSticks[2] = {};
    uint32_t g_physicalButtons = 0;
    GCBridgeVec2 g_physicalSticks[2] = {};
    float g_physicalTriggers[2] = {};

    void* g_inputHandle = nullptr;
    GCController* g_boundController = nil;
    bool g_homeWarned = false;

    int ios_button_bit(CemuBridgeButton button)
    {
        switch (button)
        {
        case CEMU_BRIDGE_BUTTON_A: return kBitA;
        case CEMU_BRIDGE_BUTTON_B: return kBitB;
        case CEMU_BRIDGE_BUTTON_X: return kBitX;
        case CEMU_BRIDGE_BUTTON_Y: return kBitY;
        case CEMU_BRIDGE_BUTTON_L: return kBitL;
        case CEMU_BRIDGE_BUTTON_R: return kBitR;
        case CEMU_BRIDGE_BUTTON_ZL: return kBitZL;
        case CEMU_BRIDGE_BUTTON_ZR: return kBitZR;
        case CEMU_BRIDGE_BUTTON_PLUS: return kBitPlus;
        case CEMU_BRIDGE_BUTTON_MINUS: return kBitMinus;
        case CEMU_BRIDGE_BUTTON_UP: return kBitUp;
        case CEMU_BRIDGE_BUTTON_DOWN: return kBitDown;
        case CEMU_BRIDGE_BUTTON_LEFT: return kBitLeft;
        case CEMU_BRIDGE_BUTTON_RIGHT: return kBitRight;
        case CEMU_BRIDGE_BUTTON_STICK_L: return kBitStickL;
        case CEMU_BRIDGE_BUTTON_STICK_R: return kBitStickR;
        default: return -1;
        }
    }

    GCBridgeControllerState ios_poll_state(void* context)
    {
        (void)context;
        std::lock_guard lock(g_inputMutex);
        const auto now = std::chrono::steady_clock::now();
        // Re-presses queued by the previous poll, which reported their release.
        if (g_touchRepressQueued)
        {
            for (int bit = 0; bit < 32; ++bit)
                if (g_touchRepressQueued & (1u << bit))
                    g_touchPressedAt[bit] = now;
            g_touchButtons |= g_touchRepressQueued;
            g_touchSeen &= ~g_touchRepressQueued;
            g_touchPendingRelease |= g_touchRepressReleased & g_touchRepressQueued;
            g_touchRepressReleased &= ~g_touchRepressQueued;
            g_touchRepressQueued = 0;
        }
        // Apply releases the latch was holding back, but only ones an EARLIER poll already
        // reported, so the poll that first sees a press still reports it.
        if (g_touchPendingRelease)
        {
            for (int bit = 0; bit < 32; ++bit)
            {
                const uint32_t mask = 1u << bit;
                if ((g_touchPendingRelease & mask) && ios_touch_release_due(bit, now))
                {
                    g_touchButtons &= ~mask;
                    g_touchPendingRelease &= ~mask;
                    g_touchSeen &= ~mask;
                    if (g_touchRepress & mask)
                    {
                        g_touchRepress &= ~mask;
                        g_touchRepressQueued |= mask;
                    }
                }
            }
        }
        GCBridgeControllerState s{};
        s.buttons = g_touchButtons | g_physicalButtons;
        g_touchSeen |= g_touchButtons;
        for (int i = 0; i < 2; i++)
        {
            const GCBridgeVec2& touch = g_touchSticks[i];
            const GCBridgeVec2 chosen = (touch.x != 0.0f || touch.y != 0.0f) ? touch : g_physicalSticks[i];
            (i == 0 ? s.leftStick : s.rightStick) = chosen;
        }
        s.leftTrigger = std::max(g_physicalTriggers[0], (g_touchButtons & (1u << kBitZL)) ? 1.0f : 0.0f);
        s.rightTrigger = std::max(g_physicalTriggers[1], (g_touchButtons & (1u << kBitZR)) ? 1.0f : 0.0f);
        return s;
    }

    void ios_update_physical(GCExtendedGamepad* pad)
    {
        uint32_t buttons = 0;
        auto bit = [&](BOOL pressed, int b) { if (pressed) buttons |= (1u << b); };
        bit(pad.buttonA.isPressed, kBitA);
        bit(pad.buttonB.isPressed, kBitB);
        bit(pad.buttonX.isPressed, kBitX);
        bit(pad.buttonY.isPressed, kBitY);
        bit(pad.leftShoulder.isPressed, kBitL);
        bit(pad.rightShoulder.isPressed, kBitR);
        bit(pad.leftTrigger.isPressed, kBitZL);
        bit(pad.rightTrigger.isPressed, kBitZR);
        bit(pad.buttonOptions ? pad.buttonOptions.isPressed : NO, kBitMinus);
        bit(pad.buttonMenu.isPressed, kBitPlus);
        bit(pad.leftThumbstickButton ? pad.leftThumbstickButton.isPressed : NO, kBitStickL);
        bit(pad.rightThumbstickButton ? pad.rightThumbstickButton.isPressed : NO, kBitStickR);
        bit(pad.dpad.up.isPressed, kBitUp);
        bit(pad.dpad.down.isPressed, kBitDown);
        bit(pad.dpad.left.isPressed, kBitLeft);
        bit(pad.dpad.right.isPressed, kBitRight);

        std::lock_guard lock(g_inputMutex);
        g_physicalButtons = buttons;
        g_physicalSticks[0] = GCBridgeVec2{pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value};
        g_physicalSticks[1] = GCBridgeVec2{pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value};
        g_physicalTriggers[0] = pad.leftTrigger.value;
        g_physicalTriggers[1] = pad.rightTrigger.value;
    }

    void ios_clear_physical()
    {
        std::lock_guard lock(g_inputMutex);
        g_physicalButtons = 0;
        g_physicalSticks[0] = g_physicalSticks[1] = GCBridgeVec2{};
        g_physicalTriggers[0] = g_physicalTriggers[1] = 0.0f;
    }

    // Main thread only - GameController objects are not thread-safe.
    void ios_bind_first_controller()
    {
        if (g_boundController)
            return;
        for (GCController* controller in [GCController controllers])
        {
            GCExtendedGamepad* pad = controller.extendedGamepad;
            if (!pad)
                continue;
            g_boundController = controller;
            pad.valueChangedHandler = ^(GCExtendedGamepad* gamepad, GCControllerElement* element) {
                (void)element;
                ios_update_physical(gamepad);
            };
            ios_update_physical(pad);
            cemuLog_log(LogType::Force, "iOS input: physical controller bound to the GamePad: {}",
                controller.vendorName ? controller.vendorName.UTF8String : "MFi controller");
            return;
        }
    }

    void ios_input_start()
    {
        if (g_inputHandle)
            return;
        GCBridgeControllerDesc desc{};
        desc.context = nullptr;
        desc.display_name = "Muffin GamePad";
        desc.controllerType = (uint8)EmulatedController::Type::VPAD;
        desc.poll_state = ios_poll_state;
        desc.poll_motion = nullptr;
        desc.rumble = nullptr;
        desc.release = nullptr;
        g_inputHandle = GCControllerBridge_add(&desc);
        if (!g_inputHandle)
        {
            cemu_bridge_log_checkpoint("iOS input: the core's GameController provider refused the GamePad - no input will reach titles");
            return;
        }
        GCControllerBridge_notifyChanged();
        cemu_bridge_log_checkpoint("iOS input: GamePad registered with the core (on-screen pad + first physical controller)");

        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
            [center addObserverForName:GCControllerDidConnectNotification object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification* note) { (void)note; ios_bind_first_controller(); }];
            [center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification* note) {
                                if (note.object == g_boundController)
                                {
                                    g_boundController = nil;
                                    ios_clear_physical();
                                    ios_bind_first_controller();
                                }
                            }];
            ios_bind_first_controller();
        });
    }

    UIWindow* ios_key_window()
    {
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes)
        {
            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;
            for (UIWindow* window in ((UIWindowScene*)scene).windows)
                if (window.isKeyWindow)
                    return window;
        }
        return nil;
    }
}

// ---------------------------------------------------------------------------
// Shader cache maintenance
namespace {

// Both caches name files with the title id as 16 lowercase hex digits.
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

long long cemu_bridge_clear_shader_cache(unsigned long long titleId, bool includeLearned) {
    // Refused while a title runs: both caches are open and would be rewritten on close.
    if (cemu_bridge_is_title_running()) {
        cemuLog_log(LogType::Force, "Shader cache: refusing to clear while a title is running");
        return -1;
    }
    long long freed = IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/precompiled"), titleId, true);
    if (includeLearned)
        freed += IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/transferable"), titleId, true);
    cemuLog_log(LogType::Force, "Shader cache: cleared {} bytes ({})", freed, includeLearned ? "compiled and learned" : "compiled only");
    return freed;
}

int cemu_bridge_shader_cache_stats(unsigned long long titleId, long long* outLearnedBytes, long long* outCompiledBytes) {
    if (outLearnedBytes)
        *outLearnedBytes = IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/transferable"), titleId, false);
    if (outCompiledBytes)
        *outCompiledBytes = IOSShaderCacheSweep(ActiveSettings::GetCachePath("shaderCache/precompiled"), titleId, false);
    return 0;
}

// ---------------------------------------------------------------------------
// Settings pushed from Swift. Each writes the engine's own config value, which the core
// reads when a title starts (or, for scaling, every time the output blit is sized).

void cemu_bridge_set_async_shader_compile(bool enabled) {
    GetConfig().async_compile = enabled;
}

bool cemu_bridge_async_shader_compile(void) {
    return GetConfig().async_compile.GetValue();
}

void cemu_bridge_set_stretch_to_fill(bool enabled) {
    GetConfig().fullscreen_scaling = enabled ? (sint32)kStretch : (sint32)kKeepAspectRatio;
}

void cemu_bridge_set_graphics_api(int api) {
    GetConfig().graphic_api = (api == (int)kVulkan) ? kVulkan : kMetal;
}

int cemu_bridge_graphics_api(void) {
    return (int)GetConfig().graphic_api.GetValue();
}

void cemu_bridge_set_upscale_filter(int filter) {
    if (filter >= kLinearFilter && filter <= kNearestNeighborFilter)
        GetConfig().upscale_filter = (sint32)filter;
}

void cemu_bridge_set_downscale_filter(int filter) {
    if (filter >= kLinearFilter && filter <= kNearestNeighborFilter)
        GetConfig().downscale_filter = (sint32)filter;
}

void cemu_bridge_set_framebuffer_fetch(bool enabled) {
    GetConfig().framebuffer_fetch = enabled;
}

bool cemu_bridge_framebuffer_fetch(void) {
    return GetConfig().framebuffer_fetch.GetValue();
}

// ---------------------------------------------------------------------------
// Screen orientation, gamma and the on-screen performance overlay. See the doc comments
// on the declarations in CemuBridge.h for what each one does and why the gamma range is
// 1.0-3.0. overlay.* are plain (non-ConfigValue) fields, same as the audio block below.

void cemu_bridge_set_render_upside_down(bool enabled) {
    GetConfig().render_upside_down = enabled;
}

bool cemu_bridge_render_upside_down(void) {
    return GetConfig().render_upside_down.GetValue();
}

void cemu_bridge_set_display_gamma(float gamma) {
    if (gamma <= 0.0f) {
        GetConfig().userDisplayGamma = 0.0f; // sRGB
        return;
    }
    if (gamma < 1.0f)
        gamma = 1.0f;
    else if (gamma > 3.0f)
        gamma = 3.0f;
    GetConfig().userDisplayGamma = gamma;
}

float cemu_bridge_display_gamma(void) {
    return GetConfig().userDisplayGamma.GetValue();
}

void cemu_bridge_set_override_app_gamma(bool enabled) {
    GetConfig().overrideAppGammaPreference = enabled;
}

bool cemu_bridge_override_app_gamma(void) {
    return GetConfig().overrideAppGammaPreference.GetValue();
}

void cemu_bridge_set_override_gamma_value(float gamma) {
    // Mirrors CemuConfig::Load()'s own graphic.xml clamp for this field (a negative value
    // means the XML predates it or was hand-edited wrong, not "as low as possible") rather
    // than cemu_bridge_set_display_gamma()'s 1.0-3.0 clamp - this field has no 0-means-sRGB
    // special case to preserve, so out-of-range here only ever means "reset to default".
    if (gamma < 0.0f)
        gamma = 2.2f;
    GetConfig().overrideGammaValue = gamma;
}

float cemu_bridge_override_gamma_value(void) {
    return GetConfig().overrideGammaValue.GetValue();
}

void cemu_bridge_set_overlay_position(int position) {
    if (position >= (int)ScreenPosition::kDisabled && position <= (int)ScreenPosition::kBottomRight)
        GetConfig().overlay.position = (ScreenPosition)position;
}

int cemu_bridge_overlay_position(void) {
    return (int)GetConfig().overlay.position;
}

void cemu_bridge_set_overlay_fps(bool enabled) {
    GetConfig().overlay.fps = enabled;
}

bool cemu_bridge_overlay_fps(void) {
    return GetConfig().overlay.fps;
}

void cemu_bridge_set_overlay_cpu_usage(bool enabled) {
    GetConfig().overlay.cpu_usage = enabled;
}

bool cemu_bridge_overlay_cpu_usage(void) {
    return GetConfig().overlay.cpu_usage;
}

void cemu_bridge_set_overlay_ram_usage(bool enabled) {
    GetConfig().overlay.ram_usage = enabled;
}

bool cemu_bridge_overlay_ram_usage(void) {
    return GetConfig().overlay.ram_usage;
}

void cemu_bridge_set_overlay_text_color(uint32_t color) {
    GetConfig().overlay.text_color = color;
}

uint32_t cemu_bridge_overlay_text_color(void) {
    return GetConfig().overlay.text_color;
}

void cemu_bridge_set_overlay_text_scale(int scale) {
    GetConfig().overlay.text_scale = (sint32)std::clamp(scale, 50, 200);
}

int cemu_bridge_overlay_text_scale(void) {
    return GetConfig().overlay.text_scale;
}

void cemu_bridge_set_overlay_cpu_mode(bool enabled) {
    GetConfig().overlay.cpu_mode = enabled;
}

bool cemu_bridge_overlay_cpu_mode(void) {
    return GetConfig().overlay.cpu_mode;
}

void cemu_bridge_set_overlay_drawcalls(bool enabled) {
    GetConfig().overlay.drawcalls = enabled;
}

bool cemu_bridge_overlay_drawcalls(void) {
    return GetConfig().overlay.drawcalls;
}

void cemu_bridge_set_overlay_cpu_per_core_usage(bool enabled) {
    GetConfig().overlay.cpu_per_core_usage = enabled;
}

bool cemu_bridge_overlay_cpu_per_core_usage(void) {
    return GetConfig().overlay.cpu_per_core_usage;
}

void cemu_bridge_set_overlay_vram_usage(bool enabled) {
    GetConfig().overlay.vram_usage = enabled;
}

bool cemu_bridge_overlay_vram_usage(void) {
    return GetConfig().overlay.vram_usage;
}

void cemu_bridge_set_overlay_debug(bool enabled) {
    GetConfig().overlay.debug = enabled;
}

bool cemu_bridge_overlay_debug(void) {
    return GetConfig().overlay.debug;
}

void cemu_bridge_set_notification_position(int position) {
    if (position >= (int)ScreenPosition::kDisabled && position <= (int)ScreenPosition::kBottomRight)
        GetConfig().notification.position = (ScreenPosition)position;
}

int cemu_bridge_notification_position(void) {
    return (int)GetConfig().notification.position;
}

void cemu_bridge_set_notification_text_color(uint32_t color) {
    GetConfig().notification.text_color = color;
}

uint32_t cemu_bridge_notification_text_color(void) {
    return GetConfig().notification.text_color;
}

void cemu_bridge_set_notification_text_scale(int scale) {
    GetConfig().notification.text_scale = (sint32)std::clamp(scale, 50, 200);
}

int cemu_bridge_notification_text_scale(void) {
    return GetConfig().notification.text_scale;
}

void cemu_bridge_set_notification_controller_profiles(bool enabled) {
    GetConfig().notification.controller_profiles = enabled;
}

bool cemu_bridge_notification_controller_profiles(void) {
    return GetConfig().notification.controller_profiles;
}

void cemu_bridge_set_notification_controller_battery(bool enabled) {
    GetConfig().notification.controller_battery = enabled;
}

bool cemu_bridge_notification_controller_battery(void) {
    return GetConfig().notification.controller_battery;
}

void cemu_bridge_set_notification_shader_compiling(bool enabled) {
    GetConfig().notification.shader_compiling = enabled;
}

bool cemu_bridge_notification_shader_compiling(void) {
    return GetConfig().notification.shader_compiling;
}

void cemu_bridge_set_notification_friends(bool enabled) {
    GetConfig().notification.friends = enabled;
}

bool cemu_bridge_notification_friends(void) {
    return GetConfig().notification.friends;
}

// MARK: - Audio
//
// tv_audio_enabled/pad_audio_enabled/tv_channels/pad_channels/tv_volume/pad_volume/
// microphone_enabled/input_volume are all plain fields on CemuConfig, not ConfigValue-wrapped,
// so they're read and written directly rather than through .GetValue(). See CemuBridge.h's
// Audio section for what's deliberately left out (audio_delay, input_channels, every
// *_device) and why.

void cemu_bridge_set_tv_audio_enabled(bool enabled) {
    GetConfig().tv_audio_enabled = enabled;
}

bool cemu_bridge_tv_audio_enabled(void) {
    return GetConfig().tv_audio_enabled;
}

void cemu_bridge_set_tv_volume(int volume) {
    GetConfig().tv_volume = std::clamp(volume, 0, 100);
}

int cemu_bridge_tv_volume(void) {
    return GetConfig().tv_volume;
}

void cemu_bridge_set_tv_channels(int channels) {
    if (channels >= kMono && channels <= kSurround)
        GetConfig().tv_channels = (AudioChannels)channels;
}

int cemu_bridge_tv_channels(void) {
    return (int)GetConfig().tv_channels;
}

void cemu_bridge_set_pad_audio_enabled(bool enabled) {
    GetConfig().pad_audio_enabled = enabled;
}

bool cemu_bridge_pad_audio_enabled(void) {
    return GetConfig().pad_audio_enabled;
}

void cemu_bridge_set_pad_volume(int volume) {
    GetConfig().pad_volume = std::clamp(volume, 0, 100);
}

int cemu_bridge_pad_volume(void) {
    return GetConfig().pad_volume;
}

void cemu_bridge_set_pad_channels(int channels) {
    if (channels >= kMono && channels <= kSurround)
        GetConfig().pad_channels = (AudioChannels)channels;
}

int cemu_bridge_pad_channels(void) {
    return (int)GetConfig().pad_channels;
}

void cemu_bridge_set_microphone_enabled(bool enabled) {
    GetConfig().microphone_enabled = enabled;
}

bool cemu_bridge_microphone_enabled(void) {
    return GetConfig().microphone_enabled;
}

void cemu_bridge_set_input_volume(int volume) {
    GetConfig().input_volume = std::clamp(volume, 0, 100);
}

int cemu_bridge_input_volume(void) {
    return GetConfig().input_volume;
}

void cemu_bridge_set_vsync_enabled(bool enabled) {
    GetConfig().vsync = enabled ? 1 : 0;
}

bool cemu_bridge_vsync_enabled(void) {
    return GetConfig().vsync.GetValue() != 0;
}

void cemu_bridge_set_recompiler_enabled(bool enabled) {
    g_recompilerRequested.store(enabled);
    // Before initialize the config is not loaded yet; cemu_bridge_initialize() applies it.
    if (g_initialized.load())
        ios_apply_cpu_mode();
}

bool cemu_bridge_recompiler_enabled(void) {
    return g_recompilerRequested.load();
}

void cemu_bridge_set_favour_accuracy(bool enabled) {
    g_favourAccuracy.store(enabled);
    if (g_initialized.load())
        ios_apply_cpu_mode();
}

bool cemu_bridge_favour_accuracy(void) {
    return g_favourAccuracy.load();
}

// Best-effort real device temperature, in degrees Celsius. NaN when unavailable.
//
// iOS does NOT publish a device temperature to apps. There is no public API for it at
// all - ProcessInfo.thermalState is a four-level signal and that is the whole of the
// supported surface. So this reaches for the battery's own sensor through IOKit, which
// is a PRIVATE framework on iOS, and it is written to fail cleanly rather than to
// succeed:
//
//   - Everything is resolved with dlopen/dlsym rather than linked. IOKit is not in the
//     iOS SDK, so linking it would not build; and a symbol that moves or disappears in a
//     future iOS turns into a nil pointer here instead of a launch-time crash.
//   - The sandbox blocks IOKit user-client access to power services for a normally
//     sideloaded app. This is expected to return NaN on a SideStore/AltStore install and
//     has a real chance of working on TrollStore or jailbroken, where the process is not
//     confined the same way.
//   - On failure it returns NaN. It never estimates, never derives a number from
//     thermalState, and never returns a plausible-looking value it did not read. A made-up
//     temperature presented in degrees is worse than no temperature at all, because it
//     looks authoritative.
//
// It is also the BATTERY's temperature, not the SoC's. The battery is what has a sensor
// anything outside the kernel can reach; it lags the chip and reads lower under a short
// burst. Useful as a trend, not as a CPU die temperature, and the UI says so.
double cemu_bridge_device_temperature_celsius(void) {
    static dispatch_once_t once;
    static void* ioKitHandle = nullptr;
    static uint32_t (*fnServiceGetMatchingService)(uint32_t, CFDictionaryRef) = nullptr;
    static CFMutableDictionaryRef (*fnServiceMatching)(const char*) = nullptr;
    static CFTypeRef (*fnRegistryEntryCreateCFProperty)(uint32_t, CFStringRef, CFAllocatorRef, uint32_t) = nullptr;
    static int (*fnObjectRelease)(uint32_t) = nullptr;

    dispatch_once(&once, ^{
        ioKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (!ioKitHandle)
            return;
        fnServiceGetMatchingService = (uint32_t (*)(uint32_t, CFDictionaryRef))dlsym(ioKitHandle, "IOServiceGetMatchingService");
        fnServiceMatching = (CFMutableDictionaryRef (*)(const char*))dlsym(ioKitHandle, "IOServiceMatching");
        fnRegistryEntryCreateCFProperty = (CFTypeRef (*)(uint32_t, CFStringRef, CFAllocatorRef, uint32_t))dlsym(ioKitHandle, "IORegistryEntryCreateCFProperty");
        fnObjectRelease = (int (*)(uint32_t))dlsym(ioKitHandle, "IOObjectRelease");
    });

    if (!fnServiceGetMatchingService || !fnServiceMatching || !fnRegistryEntryCreateCFProperty)
        return NAN;

    // Two service names, because which one carries the sensor differs by device and OS.
    static const char* kServices[] = { "AppleSmartBattery", "IOPMPowerSource" };
    for (const char* service : kServices)
    {
        CFMutableDictionaryRef match = fnServiceMatching(service);
        if (!match)
            continue;
        // IOServiceGetMatchingService CONSUMES the matching dictionary, so it must not be
        // released here on either path.
        uint32_t entry = fnServiceGetMatchingService(0 /* kIOMainPortDefault */, match);
        if (!entry)
            continue;
        CFTypeRef value = fnRegistryEntryCreateCFProperty(entry, CFSTR("Temperature"), kCFAllocatorDefault, 0);
        if (fnObjectRelease)
            fnObjectRelease(entry);
        if (!value)
            continue;
        double celsius = NAN;
        if (CFGetTypeID(value) == CFNumberGetTypeID())
        {
            int32_t raw = 0;
            if (CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &raw))
            {
                // Reported in hundredths of a degree on some devices and tenths on
                // others. Pick by magnitude rather than by device table: a battery is
                // never at 300 C, and never at 3 C inside a running iPad either, so the
                // scale is unambiguous from the value itself.
                if (raw > 1000)      celsius = raw / 100.0;
                else if (raw > 100)  celsius = raw / 10.0;
                else                 celsius = (double)raw;
            }
        }
        CFRelease(value);
        // Sanity-gate the result. A sensor that reports something physically impossible
        // is a misread, and passing it through as a temperature would be exactly the
        // fabrication this function exists to avoid.
        if (!std::isnan(celsius) && celsius > -20.0 && celsius < 120.0)
            return celsius;
    }
    return NAN;
}

void cemu_bridge_set_thermal_throttle_micros(uint32_t micros) {
    // Straight through to the core. No g_initialized guard and no stored copy: the atomic
    // lives in coreinit and defaults to 0, so setting it before a title exists is
    // harmless, and the host thread loop picks it up on its very next reschedule.
    coreinit::OSSetThermalThrottleMicros(micros);
}

void cemu_bridge_set_multicore_enabled(bool enabled) {
    g_multicoreRequested.store(enabled);
}

void cemu_bridge_set_low_power_mode(bool enabled) {
    g_lowPowerMode.store(enabled);
    // Same shape as Favour accuracy above: recompute the mode now so Settings reports
    // the truth immediately, but the core count itself only changes on the next launch -
    // _LaunchTitleThread() has already started however many host threads it started.
    if (g_initialized.load())
        ios_apply_cpu_mode();
}

bool cemu_bridge_low_power_mode(void) {
    return g_lowPowerMode.load();
}

int cemu_bridge_cpu_mode(void) {
    return g_cpuMode.load();
}

const char* cemu_bridge_cpu_mode_detail(void) {
    const char* detail = getCpuModeDetail();
    if (detail[0] == '\0')
        return "Not decided yet - the CPU path is chosen when the engine initializes, on the first launch.";
    return detail;
}

const char* cemu_bridge_active_moltenvk(void) {
    return g_activeMoltenVK.c_str();
}

bool cemu_bridge_core_available(void) {
    return true;
}

// ---------------------------------------------------------------------------
// Lifecycle

void cemu_bridge_initialize(const char* mlcPath) {
    if (g_initialized.exchange(true))
        return;
    {
        std::string where = "Crash log and checkpoints are being written to: ";
        const char* crashPath = cemu_bridge_crash_log_path();
        where += (crashPath && crashPath[0]) ? crashPath : "(nowhere - $HOME was not set, so no file could be opened)";
        cemu_bridge_log_checkpoint(where.c_str());
    }
    cemu_bridge_start_memory_watchdog();
    ios_configure_jit_environment();
    // MoltenVK reads these once, when CemuInitialize() loads it for the Vulkan backend.
    // Asynchronous queue submits, so Cemu's pipeline compiles do not stall the frame.
    setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "0", 1);
    setenv("MVK_CONFIG_DEBUG", "0", 1);
    setenv("MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE", "128", 1);

    // User data, config and mlc under Documents/mlc (writable, visible in Files); the
    // data path is the read-only CemuData directory the build copies into the bundle
    // (shared fonts, game profiles). CemuData rather than the bundle root, because a
    // top-level directory named `resources` makes CFBundle misread the whole bundle.
    fs::path userDataPath = (mlcPath && mlcPath[0] != '\0') ? fs::path(mlcPath) : fs::path(".");
    std::error_code ec;
    fs::create_directories(userDataPath / "cache", ec);
    fs::path dataPath = userDataPath;
    NSString* bundleResourcePath = [[NSBundle mainBundle] resourcePath];
    if (bundleResourcePath.length > 0)
        dataPath = fs::path(bundleResourcePath.fileSystemRepresentation) / "CemuData";
    NSString* executablePath = [[NSBundle mainBundle] executablePath] ?: @"";

    const std::string userData = userDataPath.string();
    const std::string cache = (userDataPath / "cache").string();
    const std::string data = dataPath.string();

    // Which MoltenVK the Vulkan renderer loads this launch. Both builds are embedded and
    // neither is linked, so exactly one is ever loaded: two copies in one process would
    // register the same Objective-C classes twice. The core's loader tries this path first
    // (VulkanAPI.cpp), and a loaded MoltenVK stays for the life of the process, so a change
    // in Settings applies on the next launch.
    {
        NSString* choice = [[NSUserDefaults standardUserDefaults] stringForKey:@"muffin.render.moltenVK"];
        const bool legacy = [choice isEqualToString:@"1.2.8"];
        NSString* path = [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:
            legacy ? @"MoltenVK128.framework/MoltenVK128" : @"MoltenVK.framework/MoltenVK"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            setenv("MUFFIN_MOLTENVK_PATH", path.fileSystemRepresentation, 1);
            g_activeMoltenVK = legacy ? "1.2.8" : "1.4.3";
            cemu_bridge_log_checkpoint(("MoltenVK: using " + g_activeMoltenVK + " for the Vulkan renderer this launch").c_str());
        }
        else
        {
            cemu_bridge_log_checkpoint((std::string("MoltenVK: ") + path.fileSystemRepresentation +
                " is missing from the bundle - the core falls back to its own search").c_str());
        }
    }

    // The library screen can call KeyCache_Prepare() (via a TitleInfo for a .wud/.wux/
    // encrypted game folder already in the library) before this point, which permanently latches the
    // key cache against whatever keys.txt path was in effect before CemuInitialize() (the
    // only thing that calls ActiveSettings::SetPaths() on this core) has run. Re-arm the
    // latch right before that call, so the next KeyCache_Prepare() reads keys.txt from
    // the real path instead of leaving the cache believing there are none for the session.
    KeyCache_ResetForNewPaths();

    cemu_bridge_log_checkpoint("initialize: about to call CemuInitialize()");
    try
    {
        CemuInitialize(executablePath.fileSystemRepresentation, userData.c_str(), userData.c_str(), cache.c_str(), data.c_str());
    }
    catch (...)
    {
        std::string message = "initialize: CemuInitialize() threw: " + cemu_describe_current_exception();
        cemu_bridge_log_checkpoint(message.c_str());
        setStatus("The emulator core failed to start (see the crash log).");
        g_initialized.store(false);
        return;
    }
    cemu_bridge_log_checkpoint("initialize: CemuInitialize() returned");
    // Before any title can run: CafeSystem calls back through this without a null check.
    IOSSystemImplementation_Install();

    // OSReport and the OS libs' parameter errors are what homebrew narrates its progress
    // through. Without these a ROM that is working looks exactly like one that never started.
    cemuLog_setActiveLoggingFlags(cemuLog_getFlag(LogType::CoreinitLogging) | cemuLog_getFlag(LogType::APIErrors));
    cemuLog_log(LogType::Force, "iOS {}", cemu_bridge_device_report());
    {
        std::error_code fontsEc, profilesEc;
        const bool haveFonts = fs::exists(dataPath / "resources" / "sharedFonts" / "CafeStd.ttf", fontsEc);
        const bool haveProfiles = fs::exists(dataPath / "gameProfiles" / "default", profilesEc);
        cemuLog_log(LogType::Force, "iOS data path: {} (shared fonts present: {}, default game profiles present: {})",
            _pathToUtf8(dataPath), haveFonts, haveProfiles);
    }

    ios_apply_cpu_mode();
    // Real time, always. This used to drop to shift 6 whenever the recompiler was not
    // available, and shift 6 is not a tuning constant - ActiveSettings.h spells it out:
    //
    //     s_timer_shift = 3;  // right shift factor, 0 -> 8x, 3 -> 1x, 4 -> 0.5x
    //
    // so 6 is ONE EIGHTH SPEED. The reasoning was that the guest's own deadlines go
    // overdue before they are serviced when the interpreter cannot keep up, and slowing
    // the guest clock keeps its internal timing self-consistent. What it actually did
    // was cap the frame rate at an eighth of whatever the machine could manage, by
    // choice, on every install without a JIT enabler attached - which is the default.
    //
    // Measured on one device, one ROM: Wind Waker HD at a steady 4.6fps with shift 6
    // against a steady 45 at the engine default of 3. Wind Waker targets 30, and 30/8 is
    // 3.75 - that single difference is most of the gap.
    //
    // Slowing the clock stays available as Settings > CPU > Timebase for a title that
    // genuinely needs it, where it is a choice somebody made rather than a tax nobody
    // was told about. TimebaseScale.applyStoredChoiceIfAny() applies it at title start.
    cemu_bridge_set_timebase_shift(3);

    ios_input_start();
    ios_stats_start();
    ios_stall_watchdog_start();
    Fiber::SetStackFailureHandlers(
        [] {
            // Ask the GPU thread to drop unused textures, and give it a moment to do so.
            auto& w = LatteWait::Get();
            const uint32 passes = w.evictionPasses.load();
            w.evictionRequested.store(true);
            for (int i = 0; i < 150 && w.evictionPasses.load() == passes; ++i)
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
        },
        [] {
            cemuLog_log(LogType::Force, "out of address space creating a game thread");
            cemu_bridge_log_checkpoint("out of address space creating a game thread");
            IOSSystemImplementation_ReportFatal("Out of memory address space creating a game thread. Restart the app and try again.");
        });
    ios_log_tail_start();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIWindow* window = ios_key_window())
            CemuUIKit_SetMainWindow(window);
    });

    setStatus("Cemu core initialized.");
}

void cemu_bridge_register_render_surface(void* uiView, int width, int height, double dpiScale) {
    // First thing in a title launch, so it is where the launch log's +0.000s belongs.
    ios_live_log_begin_run();
    if (!uiView)
        return;
    UIView* view = (__bridge UIView*)uiView;
    if (![view.layer isKindOfClass:[CAMetalLayer class]])
    {
        cemu_bridge_log_checkpoint("register_render_surface: the TV view is not CAMetalLayer-backed - the core renders into the view's own layer, so nothing can be drawn");
        setStatus("Render surface registration failed (see crash log).");
        return;
    }
    // The core stores view.layer as the surface for both backends: Metal draws into it,
    // MoltenVK builds its Vulkan surface from it.
    CemuUIKit_SetMainView(view);
    // After SetMainView, which resets contentsScale to the screen's native scale: the
    // user's render-scale setting arrives here as dpiScale and has to win.
    ((CAMetalLayer*)view.layer).contentsScale = dpiScale;
    CemuUIKit_UpdateMainWindowSize(width, height, dpiScale);
    setStatus("Render surface registered.");
}

void cemu_bridge_register_pad_render_surface(void* uiView, int width, int height, double dpiScale) {
    if (!uiView || width <= 0 || height <= 0)
        return;
    UIView* view = (__bridge UIView*)uiView;
    if (![view.layer isKindOfClass:[CAMetalLayer class]])
    {
        cemuLog_log(LogType::Force, "iOS: cannot register the GamePad surface - the view is not CAMetalLayer-backed");
        return;
    }
    CemuUIKit_SetPadView(view);
    ((CAMetalLayer*)view.layer).contentsScale = dpiScale;
    g_padRegistered.store(true);
    // A running title gets its pad layer now; otherwise CemuRun() initializes it at boot.
    if (g_titleRunning.load())
        CemuUIKit_InitializeLayer(false);
    CemuUIKit_SetVisibleOutputs(true, true);
    cemuLog_log(LogType::Force, "iOS: GamePad (DRC) screen surface registered, {}x{} points at {}x scale", width, height, dpiScale);
}

void cemu_bridge_release_pad_render_surface(void) {
    // The pad layer is not torn down under a running GPU thread. The pad output is hidden
    // instead, which stops every pad draw; the Swift side keeps the view (and so the layer)
    // alive, and the next boot starts without a pad view at all.
    g_padRegistered.store(false);
    CemuUIKit_SetVisibleOutputs(true, false);
    if (!g_titleRunning.load())
        CemuUIKit_SetPadView(nil);
    cemuLog_log(LogType::Force, "iOS: GamePad (DRC) screen output hidden");
}

bool cemu_bridge_has_pad_render_surface(void) {
    return g_padRegistered.load();
}

void cemu_bridge_set_visible_outputs(bool tv, bool pad) {
    CemuUIKit_SetVisibleOutputs(tv, pad);
}

void cemu_bridge_set_pad_touch(double x, double y, bool down) {
    CemuUIKit_SetPadTouch((CGFloat)x, (CGFloat)y, down);
}

void cemu_bridge_resize_render_surface(int width, int height, double dpiScale, bool mainWindow) {
    if (width <= 0 || height <= 0)
        return;
    if (mainWindow)
    {
        CemuUIKit_UpdateMainWindowSize(width, height, dpiScale);
    }
    else
    {
        if (!g_padRegistered.load())
            return;
        CemuUIKit_UpdatePadWindowSize();
    }
    // The CAMetalLayer backs a UIView, so its drawable follows the view's bounds; Vulkan
    // recreates its swapchain when the layer reports a new size at the next present.
    cemuLog_log(LogType::Force, "iOS: {} surface resized to {}x{} points at {}x scale", mainWindow ? "TV" : "GamePad", width, height, dpiScale);
}

void cemu_bridge_log_line(const char* message) {
    if (!message)
        return;
    // The string_view overload: a message containing braces is logged verbatim rather than
    // parsed as a format string.
    cemuLog_log(LogType::Force, std::string_view(message));
}

static CemuBridgeStatus ios_boot_prepared_title(int prepared);

CemuBridgeStatus cemu_bridge_boot_title(const char* path) {
    if (!path || path[0] == '\0') {
        setStatus("boot_title: empty path.");
        return CEMU_BRIDGE_BAD_ARG;
    }
    if (!g_initialized.load()) {
        setStatus("The emulator core is not initialized.");
        return CEMU_BRIDGE_CORE_NOT_BUILT;
    }

    // "mlc-title:<16 hex digits>" boots a title installed in the MLC by its id (the Wii U
    // Menu tile uses this), through the same tail as a path launch.
    static const char kMlcTitlePrefix[] = "mlc-title:";
    if (strncmp(path, kMlcTitlePrefix, sizeof(kMlcTitlePrefix) - 1) == 0) {
        char* end = nullptr;
        const unsigned long long titleId = strtoull(path + sizeof(kMlcTitlePrefix) - 1, &end, 16);
        if (end == path + sizeof(kMlcTitlePrefix) - 1 || *end != '\0' || titleId == 0) {
            setStatus("boot_title: bad title id.");
            return CEMU_BRIDGE_BAD_ARG;
        }
        return cemu_bridge_boot_title_id(titleId);
    }

    cemu_bridge_log_checkpoint("boot_title: about to prepare title");
    const int prepared = IOSTitleLaunch_PrepareForegroundTitle(path);
    cemu_bridge_log_checkpoint("boot_title: prepare returned");
    return ios_boot_prepared_title(prepared);
}

CemuBridgeStatus cemu_bridge_boot_title_id(uint64_t titleId) {
    if (titleId == 0) {
        setStatus("boot_title_id: empty title id.");
        return CEMU_BRIDGE_BAD_ARG;
    }
    if (!g_initialized.load()) {
        setStatus("The emulator core is not initialized.");
        return CEMU_BRIDGE_CORE_NOT_BUILT;
    }
    cemu_bridge_log_checkpoint("boot_title_id: about to prepare title");
    const int prepared = IOSTitleLaunch_PrepareForegroundTitleById(titleId);
    cemu_bridge_log_checkpoint("boot_title_id: prepare returned");
    return ios_boot_prepared_title(prepared);
}

// Everything after the title has been prepared: report a failed prepare, otherwise bring up
// the surfaces and start the title thread. Shared by the path and title-id launches.
static CemuBridgeStatus ios_boot_prepared_title(int prepared) {
    switch (prepared) {
        case 0:
            break;
        case 1:
            setStatus("Invalid RPX.");
            return CEMU_BRIDGE_INVALID_RPX;
        case 2:
            setStatus("Unable to mount title (bad/outdated path).");
            return CEMU_BRIDGE_UNABLE_TO_MOUNT;
        case 3:
            setStatus("This game is encrypted and no key in keys.txt opens it. Put the keys.txt you dumped from your own Wii U in MuffinEMU's \"keys\" folder in the Files app (or import it in Settings), then relaunch MuffinEMU and try again.");
            return CEMU_BRIDGE_NO_DISC_KEY;
        case 4:
            setStatus("This game folder is missing title.tik (the ticket), which MuffinEMU needs to decrypt it. Copy title.tik into the folder next to title.tmd, or add this game's title key to keys.txt.");
            return CEMU_BRIDGE_NO_TITLE_TIK;
        case 7:
            setStatus("This game folder's title.tmd couldn't be read. The file may be damaged or incomplete - copy the whole folder again.");
            return CEMU_BRIDGE_BAD_TITLE_TMD;
        case 8:
            setStatus("This game folder's title.tik (the ticket) couldn't be read, so MuffinEMU can't decrypt it. The file may be damaged - copy it again, or add this game's title key to keys.txt.");
            return CEMU_BRIDGE_BAD_TITLE_TIK;
        case 9:
            setStatus("MuffinEMU couldn't decrypt this game folder. Its title.tik doesn't unlock the .app files (the ticket may belong to another console, or the files are damaged). Check that title.tmd, title.tik and the .app files are from the same download.");
            return CEMU_BRIDGE_TITLE_KEY_INVALID;
        case 10: {
            const std::string missingFile = IOSTitleLaunch_LastErrorDetail();
            setStatus(("This game folder is missing " + (missingFile.empty() ? std::string("a .app file") : missingFile) + ", which title.tmd lists. Copy every .app file from the download into the folder.").c_str());
            return CEMU_BRIDGE_MISSING_CONTENT;
        }
        case 6:
            setStatus("That looks like an update or DLC. Launch the base game instead.");
            return CEMU_BRIDGE_BASE_NOT_FOUND;
        case 11:
            setStatus("That system title isn't installed. Import it in Settings > Wii U Menu.");
            return CEMU_BRIDGE_UNABLE_TO_MOUNT;
        default:
            setStatus("Not a Wii U title this build can launch.");
            return CEMU_BRIDGE_UNSUPPORTED;
    }

    // A pad view left over from an earlier title must not be initialized by this one.
    if (!g_padRegistered.load())
        CemuUIKit_SetPadView(nil);
    CemuUIKit_SetVisibleOutputs(true, g_padRegistered.load());
    // CPU mode is written into the config at initialize and on every toggle; re-applied
    // here so a JIT enabler attached after the app started still counts for this boot.
    ios_apply_cpu_mode();
    ios_apply_render_profile();

    IOSSystemImplementation_ResetExit();
    cemu_bridge_log_checkpoint("boot_title: about to call CemuRun()");
    try
    {
        // Constructs the renderer for the configured graphics API, initializes the TV
        // (and, if registered, GamePad) layers and starts the title thread.
        CemuRun();
    }
    catch (...)
    {
        std::string message = "boot_title: CemuRun() threw: " + cemu_describe_current_exception();
        cemu_bridge_log_checkpoint(message.c_str());
        setStatus("The title failed to start (see the crash log).");
        return CEMU_BRIDGE_UNABLE_TO_MOUNT;
    }
    cemu_bridge_log_checkpoint("boot_title: CemuRun() returned");
    g_titleRunning.store(true);
    ios_timebase_ladder_start();
    setStatus("Title launched.");
    return CEMU_BRIDGE_OK;
}

CemuBridgeStatus cemu_bridge_boot_rpx(const char* rpxPath) {
    // The launch path handles a standalone RPX/ELF itself.
    return cemu_bridge_boot_title(rpxPath);
}

int cemu_bridge_reload_and_count_keys(void) {
    // keys.txt resolves against the user data path initialize sets up; before that there is
    // no file to count, and "cannot answer" is not "zero keys".
    if (!g_initialized.load())
        return -1;
    return IOSTitleLaunch_ReloadAndCountKeys();
}

double cemu_bridge_get_fps(void) {
    return g_framesPerSecond.load();
}

void cemu_bridge_get_progress(CemuBridgeProgress* out) {
    if (!out)
        return;
    *out = CemuBridgeProgress{};
    if (!g_titleRunning.load() || !CafeSystem::IsTitleRunning())
        return;
    out->gx2_init_reached = LatteGPUState.gx2InitCalled > 0;
    out->gx2_frame_count = LatteGPUState.frameCounter;
    out->gx2_frames_per_second = g_framesPerSecond.load();
    out->os_screen_scanouts = 0;
    out->guest_flip_requests = (unsigned int)LatteGPUState.flipRequestCount.load();
}

// ---------------------------------------------------------------------------
// Decrypt-to-Files / Decrypt-to-WUA. One at a time by design.
static std::atomic<bool> g_decryptRunning{false};
static std::atomic<bool> g_decryptCompleted{false};
static std::atomic<bool> g_decryptCancelRequested{false};
static std::atomic<int> g_decryptResultStatus{0};
static std::atomic<uint64_t> g_decryptBytesWritten{0};
static std::atomic<uint32_t> g_decryptFilesWritten{0};
static std::thread g_decryptThread;
static std::mutex g_decryptThreadMutex;

bool cemu_bridge_start_decrypt(const char* srcPath, const char* destPath, bool toWua) {
    if (!srcPath || srcPath[0] == '\0' || !destPath || destPath[0] == '\0')
        return false;
    if (g_decryptRunning.exchange(true))
        return false;

    std::lock_guard lock{g_decryptThreadMutex};
    if (g_decryptThread.joinable())
        g_decryptThread.join();
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
        int status = 5; // IOS_DECRYPT_INCOMPLETE: an exception means the output can't be trusted
        try {
            status = toWua
                ? IOSTitleDecrypt_ExtractToWua(src.c_str(), dest.c_str(), g_decryptCancelRequested, progress)
                : IOSTitleDecrypt_ExtractToFolder(src.c_str(), dest.c_str(), g_decryptCancelRequested, progress);
        } catch (...) {
            std::string message = "decrypt: threw: " + cemu_describe_current_exception();
            cemu_bridge_log_checkpoint(message.c_str());
        }
        g_decryptResultStatus.store(status);
        g_decryptCompleted.store(true);
        g_decryptRunning.store(false);
    });
    return true;
}

void cemu_bridge_get_decrypt_progress(CemuBridgeDecryptProgress* out) {
    if (!out)
        return;
    *out = CemuBridgeDecryptProgress{};
    out->is_running = g_decryptRunning.load();
    out->completed = g_decryptCompleted.load();
    out->result_status = g_decryptResultStatus.load();
    out->bytes_written = g_decryptBytesWritten.load();
    out->files_written = g_decryptFilesWritten.load();
}

void cemu_bridge_cancel_decrypt(void) {
    g_decryptCancelRequested.store(true);
}

bool cemu_bridge_derive_gametdb_id(const char* romPath, char* outGameID, size_t outGameIDSize) {
    if (!romPath || !outGameID || outGameIDSize < 7)
        return false;
    std::string id = IOSCoverArt_DeriveGameTdbId(romPath);
    if (id.size() != 6)
        return false;
    memcpy(outGameID, id.c_str(), 7);
    return true;
}

bool cemu_bridge_get_title_name(const char* romPath, char* outName, size_t outNameSize) {
    if (!romPath || !outName || outNameSize == 0)
        return false;
    const std::string name = IOSCoverArt_GetTitleName(romPath);
    if (name.empty())
        return false;
    // Truncate on a UTF-8 boundary, so a long Japanese title never ends in half a character.
    size_t length = std::min(name.size(), outNameSize - 1);
    while (length > 0 && length < name.size() && ((unsigned char)name[length] & 0xC0) == 0x80)
        length--;
    memcpy(outName, name.data(), length);
    outName[length] = '\0';
    return true;
}

bool cemu_bridge_derive_title_id(const char* romPath, uint64_t* outTitleId) {
    if (!romPath || !outTitleId)
        return false;
    return IOSDlcUpdateImport_DeriveTitleId(romPath, outTitleId);
}

bool cemu_bridge_read_tmd_title_id(const char* tmdPath, uint64_t* outTitleId) {
    return IOSDlcUpdateImport_ReadTmdTitleId(tmdPath, outTitleId);
}

uint64_t cemu_bridge_derive_base_title_id(uint64_t titleId) {
    return IOSDlcUpdateImport_DeriveBaseTitleId(titleId);
}

int cemu_bridge_get_title_type(uint64_t titleId) {
    return IOSDlcUpdateImport_GetTitleType(titleId);
}

void cemu_bridge_get_mlc_title_path_components(uint64_t titleId, char* outUpperHex, char* outLowerHex) {
    if (!outUpperHex || !outLowerHex)
        return;
    IOSDlcUpdateImport_GetMlcTitlePathComponents(titleId, outUpperHex, outLowerHex);
}

bool cemu_bridge_inspect_title(const char* romPath, uint64_t* outTitleId, uint16_t* outVersion,
    int* outRegion, int* outInvalidReason) {
    return IOSDlcUpdateImport_Inspect(romPath, outTitleId, outVersion, outRegion, outInvalidReason);
}

uint64_t cemu_bridge_derive_content_title_id(uint64_t baseTitleId, bool isUpdate) {
    return IOSDlcUpdateImport_DeriveContentTitleId(baseTitleId, isUpdate);
}

void cemu_bridge_graphic_packs_refresh(void) {
    IOSGraphicPacks_Refresh();
}

const char* cemu_bridge_graphic_packs_list(void) {
    static thread_local std::string g_graphicPacksList;
    g_graphicPacksList = IOSGraphicPacks_List();
    return g_graphicPacksList.c_str();
}

void cemu_bridge_graphic_pack_set_enabled(int index, bool enabled) {
    IOSGraphicPacks_SetEnabled(index, enabled);
}

// ---------------------------------------------------------------------------
// Wii U console accounts and each one's Network Service. See the doc comments in
// CemuBridge.h for the record/field shapes and what Custom does and doesn't need; the
// actual Account/NetworkService C++ calls live in IOSAccounts.cpp, same split as the
// graphic pack functions above.

const char* cemu_bridge_accounts_list(void) {
    static thread_local std::string g_accountsList;
    g_accountsList = IOSAccounts_List();
    return g_accountsList.c_str();
}

void cemu_bridge_accounts_refresh(void) {
    IOSAccounts_Refresh();
}

bool cemu_bridge_accounts_has_free_slot(void) {
    return IOSAccounts_HasFreeSlot();
}

uint32_t cemu_bridge_accounts_next_persistent_id(void) {
    return IOSAccounts_NextPersistentId();
}

uint32_t cemu_bridge_accounts_min_persistent_id(void) {
    return IOSAccounts_MinPersistentId();
}

bool cemu_bridge_accounts_locked(void) {
    return IOSAccounts_Locked();
}

bool cemu_bridge_account_create(uint32_t persistentId, const char* miiName, uint16_t birthYear,
    uint8_t birthMonth, uint8_t birthDay, int gender, const char* email, int country) {
    return IOSAccounts_Create(persistentId, miiName, birthYear, birthMonth, birthDay, gender, email, country);
}

bool cemu_bridge_account_delete(uint32_t persistentId) {
    return IOSAccounts_Delete(persistentId);
}

bool cemu_bridge_account_set_mii_name(uint32_t persistentId, const char* miiName) {
    return IOSAccounts_SetMiiName(persistentId, miiName);
}

bool cemu_bridge_account_set_gender(uint32_t persistentId, int gender) {
    return IOSAccounts_SetGender(persistentId, gender);
}

bool cemu_bridge_account_set_email(uint32_t persistentId, const char* email) {
    return IOSAccounts_SetEmail(persistentId, email);
}

bool cemu_bridge_account_set_country(uint32_t persistentId, int country) {
    return IOSAccounts_SetCountry(persistentId, country);
}

bool cemu_bridge_account_set_birthdate(uint32_t persistentId, uint16_t year, uint8_t month, uint8_t day) {
    return IOSAccounts_SetBirthdate(persistentId, year, month, day);
}

uint32_t cemu_bridge_active_account_persistent_id(void) {
    return IOSAccounts_ActivePersistentId();
}

void cemu_bridge_set_active_account_persistent_id(uint32_t persistentId) {
    IOSAccounts_SetActivePersistentId(persistentId);
}

bool cemu_bridge_account_is_online_valid(uint32_t persistentId) {
    return IOSAccounts_IsOnlineValid(persistentId);
}

const char* cemu_bridge_countries_list(void) {
    static thread_local std::string g_countriesList;
    g_countriesList = IOSAccounts_CountriesList();
    return g_countriesList.c_str();
}

CemuBridgeNetworkService cemu_bridge_network_service(uint32_t persistentId) {
    return (CemuBridgeNetworkService)IOSAccounts_NetworkService(persistentId);
}

void cemu_bridge_set_network_service(uint32_t persistentId, CemuBridgeNetworkService service) {
    IOSAccounts_SetNetworkService(persistentId, (int)service);
}

bool cemu_bridge_custom_network_service_available(void) {
    return IOSAccounts_CustomNetworkServiceAvailable();
}

// ---------------------------------------------------------------------------
// Emulated toy-to-life devices. Enable flags are plain ConfigValue<bool>s nsyshid's own
// AttachDefaultBackends() reads when a title's nsyshid module loads (see
// Cafe/OS/libs/nsyshid/BackendEmulated.cpp) - same "takes effect next launch" timing as
// the other settings on this page. Figure management forwards to IOSEmulatedDevices.cpp,
// which owns the slot bookkeeping and talks to nsyshid::g_skyportal/g_infinitybase/
// g_dimensionstoypad directly. `device` crosses this boundary as CemuBridgeUSBDevice's
// own int values (0/1/2) - IOSEmulatedDevices.cpp mirrors them 1:1 as plain ints, the
// same convention IOSTitleLaunch.cpp uses for CemuBridgeStatus.

void cemu_bridge_set_emulate_skylander_portal(bool enabled) {
    GetConfig().emulated_usb_devices.emulate_skylander_portal = enabled;
}

bool cemu_bridge_emulate_skylander_portal(void) {
    return GetConfig().emulated_usb_devices.emulate_skylander_portal.GetValue();
}

void cemu_bridge_set_emulate_infinity_base(bool enabled) {
    GetConfig().emulated_usb_devices.emulate_infinity_base = enabled;
}

bool cemu_bridge_emulate_infinity_base(void) {
    return GetConfig().emulated_usb_devices.emulate_infinity_base.GetValue();
}

void cemu_bridge_set_emulate_dimensions_toypad(bool enabled) {
    GetConfig().emulated_usb_devices.emulate_dimensions_toypad = enabled;
}

bool cemu_bridge_emulate_dimensions_toypad(void) {
    return GetConfig().emulated_usb_devices.emulate_dimensions_toypad.GetValue();
}

int cemu_bridge_usb_device_slot_count(CemuBridgeUSBDevice device) {
    return IOSEmulatedDevices_SlotCount((int)device);
}

const char* cemu_bridge_usb_device_slot_names(CemuBridgeUSBDevice device) {
    static thread_local std::string g_usbDeviceSlotNames;
    g_usbDeviceSlotNames = IOSEmulatedDevices_SlotNames((int)device);
    return g_usbDeviceSlotNames.c_str();
}

const char* cemu_bridge_usb_device_figure_list(CemuBridgeUSBDevice device, int slot) {
    static thread_local std::string g_usbDeviceFigureList;
    g_usbDeviceFigureList = IOSEmulatedDevices_FigureList((int)device, slot);
    return g_usbDeviceFigureList.c_str();
}

const char* cemu_bridge_usb_device_load(CemuBridgeUSBDevice device, int slot, const char* path) {
    static thread_local std::string g_usbDeviceLoadError;
    g_usbDeviceLoadError = IOSEmulatedDevices_Load((int)device, slot, path);
    return g_usbDeviceLoadError.empty() ? nullptr : g_usbDeviceLoadError.c_str();
}

const char* cemu_bridge_usb_device_clear(CemuBridgeUSBDevice device, int slot) {
    static thread_local std::string g_usbDeviceClearError;
    g_usbDeviceClearError = IOSEmulatedDevices_Clear((int)device, slot);
    return g_usbDeviceClearError.empty() ? nullptr : g_usbDeviceClearError.c_str();
}

const char* cemu_bridge_usb_device_create(CemuBridgeUSBDevice device, uint32_t figureId, uint16_t variant, const char* path) {
    static thread_local std::string g_usbDeviceCreateError;
    g_usbDeviceCreateError = IOSEmulatedDevices_Create((int)device, figureId, variant, path);
    return g_usbDeviceCreateError.empty() ? nullptr : g_usbDeviceCreateError.c_str();
}

const char* cemu_bridge_usb_device_move_dimensions(int fromSlot, int toSlot) {
    static thread_local std::string g_usbDeviceMoveError;
    g_usbDeviceMoveError = IOSEmulatedDevices_MoveDimensions(fromSlot, toSlot);
    return g_usbDeviceMoveError.empty() ? nullptr : g_usbDeviceMoveError.c_str();
}

// ---------------------------------------------------------------------------
// Emulated timebase
//
// PPCTimer computes elapsedTick = (elapsedTick << 3) >> shift on a uint64, so a large
// enough shift stops the guest's clock outright. 10 is 1/128 real time.
static constexpr int kTimebaseShiftMin = 0;
static constexpr int kTimebaseShiftMax = 10;

void cemu_bridge_set_timebase_shift(int shift) {
    if (shift < kTimebaseShiftMin) shift = kTimebaseShiftMin;
    if (shift > kTimebaseShiftMax) shift = kTimebaseShiftMax;
    ActiveSettings::SetTimerShiftFactor((uint8)shift);
    cemuLog_log(LogType::Force, "Emulated timebase: shift {} ({:.4g}x real time)",
        shift, 8.0 / (double)(1u << shift));
}

int cemu_bridge_get_timebase_shift(void) {
    return (int)ActiveSettings::GetTimerShiftFactor();
}

// The automatic clock ladder: while an interpreter boot has not reached GX2Init, step the
// guest's clock down a notch every twelve seconds, to a floor of 1/64, and log the value
// that got it through. A hand-picked value turns it off for good.
static constexpr int kLadderFloorShift = 9;
static constexpr int kLadderStepSeconds = 12;

static std::atomic<bool> g_timebaseAutoEnabled{true};
static std::atomic<bool> g_timebaseLadderRunning{false};
static std::thread g_timebaseLadderThread;
static std::mutex g_timebaseLadderMutex;

void cemu_bridge_set_timebase_auto_enabled(bool enabled) {
    const bool was = g_timebaseAutoEnabled.exchange(enabled);
    if (was == enabled)
        return;
    cemuLog_log(LogType::Force, "Emulated timebase: automatic clock ladder {}",
        enabled ? "enabled" : "disabled - a value was chosen by hand, so it stands");
}

bool cemu_bridge_timebase_auto_enabled(void) {
    return g_timebaseAutoEnabled.load();
}

static void ios_timebase_ladder_entry() {
    const auto start = std::chrono::steady_clock::now();
    // The clock this ladder inherited, so it can be put back.
    //
    // Everything below is a SEARCH, and a search that does not restore what it changed
    // is just damage. Without this the ladder would step the guest's clock down while a
    // title was slow to boot, watch the title boot anyway, conclude the slow clock was
    // "the value that worked", and leave it there for the rest of the session - so a
    // title that took 36 seconds to reach GX2Init then ran at an eighth speed forever.
    const int startShift = cemu_bridge_get_timebase_shift();
    auto lastStep = start;
    // Baselines from the first poll, not zero: a title that drew one frame and stopped
    // must not read as advancing.
    bool baselineTaken = false;
    unsigned long long baseGX2Frames = 0;
    unsigned int baseGuestFlipRequests = 0;
    while (g_timebaseLadderRunning.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        if (!g_timebaseLadderRunning.load() || !g_timebaseAutoEnabled.load() || !CafeSystem::IsTitleRunning())
            return;
        if (IOSTitlePause_IsPaused())
            continue;

        CemuBridgeProgress progress{};
        cemu_bridge_get_progress(&progress);
        const auto now = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(now - start).count();

        if (!baselineTaken) {
            baselineTaken = true;
            baseGX2Frames = progress.gx2_frame_count;
            baseGuestFlipRequests = progress.guest_flip_requests;
        }

        const bool advancing = progress.gx2_init_reached ||
                               progress.gx2_frame_count > baseGX2Frames ||
                               progress.guest_flip_requests > baseGuestFlipRequests;
        if (advancing) {
            const int shift = cemu_bridge_get_timebase_shift();
            // Put the clock back once the title is advancing: it got past the stall because
            // it finished booting, not because the console was slowed, and keeping the slow
            // clock costs frame rate for the rest of the session. A title that needs a
            // slower clock has Settings > CPU > Timebase.
            if (shift != startShift) {
                cemuLog_log(LogType::Force,
                    "Emulated timebase: the title is advancing ({}) after {:.1f}s. Restoring the clock from "
                    "shift {} ({:.4g}x real time) to shift {} ({:.4g}x) - the ladder was searching for a way "
                    "past the stall, not choosing a speed to run at.",
                    progress.gx2_init_reached ? "GX2Init reached" : "guest output moving", elapsed,
                    shift, 8.0 / (double)(1u << shift),
                    startShift, 8.0 / (double)(1u << startShift));
                cemu_bridge_set_timebase_shift(startShift);
            } else {
                cemuLog_log(LogType::Force,
                    "Emulated timebase: the title is advancing ({}) after {:.1f}s with the clock untouched at "
                    "shift {} ({:.4g}x real time). Ladder stopped without having had to step.",
                    progress.gx2_init_reached ? "GX2Init reached" : "guest output moving",
                    elapsed, shift, 8.0 / (double)(1u << shift));
            }
            return;
        }

        if (now - lastStep < std::chrono::seconds(kLadderStepSeconds))
            continue;
        lastStep = now;

        const int shift = cemu_bridge_get_timebase_shift();
        if (shift >= kLadderFloorShift) {
            // And put it back on the way out. This branch has already concluded that the
            // guest's clock is not what is holding the title - so every step the ladder
            // took was wrong, and leaving the console at 1/64 speed on the strength of a
            // theory it just disproved is the worst of both.
            cemuLog_log(LogType::Force,
                "Emulated timebase: the ladder is at its floor - shift {} ({:.4g}x real time) - and after "
                "{:.1f}s the title still has not reached GX2Init. The guest's clock is not what is holding "
                "this title, so every step taken was wrong; restoring shift {} ({:.4g}x) and stopping.",
                shift, 8.0 / (double)(1u << shift), elapsed,
                startShift, 8.0 / (double)(1u << startShift));
            if (shift != startShift)
                cemu_bridge_set_timebase_shift(startShift);
            return;
        }

        cemuLog_log(LogType::Force,
            "Emulated timebase: no GX2Init after {:.1f}s, stepping the guest's clock down to shift {} "
            "({:.4g}x real time). This is the ladder searching, not a value anyone chose.",
            elapsed, shift + 1, 8.0 / (double)(1u << (shift + 1)));
        cemu_bridge_set_timebase_shift(shift + 1);
    }
}

static void ios_timebase_ladder_stop() {
    std::lock_guard lock{g_timebaseLadderMutex};
    g_timebaseLadderRunning.store(false);
    if (g_timebaseLadderThread.joinable())
        g_timebaseLadderThread.join();
}

static void ios_timebase_ladder_start() {
    ios_timebase_ladder_stop();
    if (!g_timebaseAutoEnabled.load())
        return;
    // Not under the recompiler, where the guest's clock and CPU are already in step.
    if (g_cpuMode.load() != kCpuModeInterpreter)
        return;
    std::lock_guard lock{g_timebaseLadderMutex};
    g_timebaseLadderRunning.store(true);
    g_timebaseLadderThread = std::thread(ios_timebase_ladder_entry);
    cemuLog_log(LogType::Force,
        "Emulated timebase: automatic clock ladder armed - if the title has not reached GX2Init after "
        "{}s the clock steps down one notch, to a floor of 1/64 real time.", kLadderStepSeconds);
}

bool cemu_bridge_is_title_running(void) {
    // A title that called coreinit exit() has finished even though CafeSystem still holds it,
    // and the UI should see that as the end of the game rather than a frozen one.
    // A title switch (the Wii U Menu launching a game) has CafeSystem::IsTitleRunning() false
    // for a moment between the old title's shutdown and the new one's start. That is not the
    // end of the session, and reporting it as one would tear the emulator view down.
    if (g_titleRunning.load() && CafeSystem::IsTitleSwitchInProgress())
        return true;
    return g_titleRunning.load() && CafeSystem::IsTitleRunning() && !IOSSystemImplementation_TitleExited(nullptr);
}

// Called by the iOS SystemImplementation from the title-switch launcher thread. The
// renderer has to be rebuilt (ShutdownTitle() destroyed it), and desktop Cemu does its
// equivalent - recreating the canvas - on the UI thread, so this runs on the main thread
// and blocks until it is done. If the main thread is not responding within 10 seconds it is
// done on the calling thread instead rather than deadlocking the switch.
bool IOSBridge_RecreateRenderSurface() {
    struct State {
        std::atomic_bool claimed{false};
        std::atomic_bool ok{true};
    };
    auto state = std::make_shared<State>();
    auto work = [state]() {
        if (state->claimed.exchange(true))
            return;
        try
        {
            // The outgoing title's GPU state must not carry into the new renderer.
            ios_reset_video_stall_state();
            ios_apply_render_profile();
            CemuPrepareRenderer();
        }
        catch (...)
        {
            state->ok.store(false);
            std::string message = "title switch: rebuilding the renderer threw: " + cemu_describe_current_exception();
            cemu_bridge_log_checkpoint(message.c_str());
        }
    };
    if ([NSThread isMainThread]) {
        work();
        return state->ok.load();
    }
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_main_queue(), ^{ work(); });
    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
        cemuLog_log(LogType::Force, "iOS: title switch - the main thread did not respond in 10s, rebuilding the renderer on the launcher thread");
        work();
        // work() returns at once if the main thread got there first; wait for it to finish.
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    }
    return state->ok.load();
}

void cemu_bridge_pause(void) {
    IOSTitlePause_Pause();
}

void cemu_bridge_resume(void) {
    IOSTitlePause_Resume();
}

bool cemu_bridge_save_state(const char* path) {
    if (!path || !*path)
        return false;
    return IOSSaveState_Save(path);
}

bool cemu_bridge_load_state(const char* path) {
    if (!path || !*path)
        return false;
    return IOSSaveState_Load(path);
}

void cemu_bridge_shutdown_title(void) {
    cemu_bridge_memory_note("before title shutdown");
    ios_timebase_ladder_stop();
    // Suspended guest threads cannot be joined, so a paused title is resumed first.
    IOSTitlePause_Resume();
    IOSTitlePause_Forget();
    if (CafeSystem::IsTitleRunning())
        CafeSystem::ShutdownTitle();
    // ShutdownTitle() stops the GPU thread but leaves g_renderer constructed. Dropped here
    // so the next CemuRun() builds a fresh one for whatever graphics API is configured then,
    // instead of reusing a renderer whose layers belong to views Swift has since replaced.
    g_renderer.reset();
    g_titleRunning.store(false);
    g_framesPerSecond.store(0.0);
    ios_reset_video_stall_state();
    cemu_bridge_release_all_buttons();
    cemu_bridge_memory_note("after title shutdown");
    setStatus("Title shut down.");
}

void cemu_bridge_shutdown(void) {
    cemu_bridge_shutdown_title();
    CemuShutdown();
    g_initialized.store(false);
    setStatus("Cemu core shut down.");
}

void cemu_bridge_refresh_input_devices(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ios_bind_first_controller();
    });
}

void cemu_bridge_set_button_state(CemuBridgeButton button, bool pressed) {
    const int bit = ios_button_bit(button);
    if (bit < 0)
    {
        if (button == CEMU_BRIDGE_BUTTON_HOME && !g_homeWarned)
        {
            g_homeWarned = true;
            cemuLog_log(LogType::Force, "iOS input: HOME has no binding in the core's GamePad mapping, so it is ignored");
        }
        return;
    }
    const uint32_t mask = 1u << bit;
    const auto now = std::chrono::steady_clock::now();
    std::lock_guard lock(g_inputMutex);
    if (pressed)
    {
        // Already queued to come back down: the finger is simply down again.
        if ((g_touchRepress | g_touchRepressQueued) & mask)
        {
            g_touchRepressReleased &= ~mask;
            return;
        }
        if (!(g_touchButtons & mask))
        {
            g_touchButtons |= mask;
            g_touchSeen &= ~mask;
            g_touchPendingRelease &= ~mask;
            g_touchPressedAt[bit] = now;
            return;
        }
        if (g_touchPendingRelease & mask)
        {
            // Lifted and pressed again before the latch let go. If a read saw the first
            // press, the title needs an up and a second down; if none did, there is only
            // one press to report and it simply continues.
            if (g_touchSeen & mask)
                g_touchRepress |= mask;
            else
                g_touchPendingRelease &= ~mask;
        }
        // Otherwise a repeat "down" for a held button: a no-op, so the pad may re-assert
        // a press freely without restarting the latch.
    }
    else
    {
        if ((g_touchRepress | g_touchRepressQueued) & mask)
        {
            g_touchRepressReleased |= mask;
            return;
        }
        if (!(g_touchButtons & mask))
            return;
        if (ios_touch_release_due(bit, now))
        {
            g_touchButtons &= ~mask;
            g_touchSeen &= ~mask;
            g_touchPendingRelease &= ~mask;
        }
        else
        {
            g_touchPendingRelease |= mask;
        }
    }
}

// ---------------------------------------------------------------------------
// Input introspection
//
// The GamePad's button mappings live in C++ (InputManager / EmulatedController) and are
// persisted to controllerProfiles/controller{N} on the device. These functions let Swift
// see them, so a state where every on-screen button is dead but the sticks work can be
// diagnosed from the app.
//
// Axes reach the emulated controller directly, while every button goes through the
// mapping table, so "sticks respond but no button does" means the controller has no
// button mappings (for example from a stale profile on disk). These functions report
// the binding count and the profile name, and reset the bindings.

int cemu_bridge_input_button_mapping_count(void) {
    auto vpad = InputManager::instance().get_vpad_controller(0);
    if (!vpad)
        return -1;   // no GamePad wired at all - distinct from "wired, zero bindings"
    int count = 0;
    // Buttons only: the ids from A up to StickR. Everything at StickL_Up and beyond is an
    // AXIS mapping (VPADController::is_axis_mapping), and counting those would report a
    // healthy number for exactly the broken case this is meant to detect - sticks bound,
    // buttons not.
    for (uint64 id = VPADController::kButtonId_A; id < VPADController::kButtonId_StickL_Up; ++id)
    {
        if (vpad->get_mapping_controller(id))
            count++;
    }
    return count;
}

const char* cemu_bridge_input_profile_name(void) {
    static thread_local std::string name;
    auto vpad = InputManager::instance().get_vpad_controller(0);
    name = vpad ? vpad->get_profile_name() : std::string("<no controller>");
    return name.c_str();
}

bool cemu_bridge_reset_controller_bindings(void) {
    // Deletes the persisted profile as well as the in-memory controller, then re-runs the
    // provider wiring - which is the one path that calls apply_default_gc_mappings(). A
    // reset that only cleared memory would be undone by the same bad profile on the next
    // launch, which is the failure it exists to cure.
    InputManager::instance().delete_controller(0, /*delete_profile*/ true);
    InputManager::instance().load_gc_controllers();
    const int bindings = cemu_bridge_input_button_mapping_count();
    cemuLog_log(LogType::Force, "iOS input: controller bindings reset; GamePad now has {} button mappings", bindings);
    return bindings > 0;
}

void cemu_bridge_set_stick_axis(CemuBridgeStick stick, float x, float y) {
    // Clamped by magnitude so a diagonal cannot ask for more deflection than a stick has.
    const float magnitude = std::sqrt(x * x + y * y);
    if (magnitude > 1.0f) {
        x /= magnitude;
        y /= magnitude;
    }
    if (std::isnan(x) || std::isnan(y))
        return;
    // CemuBridge's convention (+y up) is also GCBridge's.
    std::lock_guard lock(g_inputMutex);
    g_touchSticks[stick == CEMU_BRIDGE_STICK_RIGHT ? 1 : 0] = GCBridgeVec2{x, y};
}

void cemu_bridge_release_all_buttons(void) {
    std::lock_guard lock(g_inputMutex);
    // Immediate, bypassing the latch: this is the "nothing may stay held" path (pause,
    // pad hidden, app backgrounded).
    g_touchButtons = 0;
    g_touchSeen = 0;
    g_touchPendingRelease = 0;
    g_touchRepress = 0;
    g_touchRepressQueued = 0;
    g_touchRepressReleased = 0;
    g_touchSticks[0] = g_touchSticks[1] = GCBridgeVec2{};
}

const char* cemu_bridge_status_text(void) {
    int exitStatus = 0;
    if (const char* fatal = IOSSystemImplementation_FatalReason())
    {
        setStatus(fatal);
    }
    else if (g_titleRunning.load() && IOSSystemImplementation_TitleExited(&exitStatus))
    {
        char line[96];
        snprintf(line, sizeof(line), "The game closed itself (exit status %d).", exitStatus);
        setStatus(line);
    }
    if (g_titleRunning.load() && IOSSystemImplementation_TitleSwitchFailed())
        setStatus("The Wii U Menu tried to open another title and it couldn't be started. Check that game is in your library and its keys are installed, then launch it from the library instead.");
    // Only fall back to a computed default when nothing specific has been set, so a boot
    // failure's reason is not overwritten by a generic line on the next read.
    if (statusIsEmpty())
        setStatus(cemu_bridge_is_title_running() ? "Title running." : "Core ready (no title running).");
    return getStatus();
}
