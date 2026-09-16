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
#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cemu/Logging/CemuLogging.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"
#include "Common/version.h"
#include "gui/interface/WindowSystem.h"
#include "input/api/iOS/GCControllerProvider.h"
#include "input/emulated/EmulatedController.h"

// The core's C entry points. Defined inside extern "C" blocks in src/main.cpp and
// src/gui/uikit/WindowSystem.mm, and only ever declared in MeloCafe's own app target, so
// they are declared again here.
extern "C" {
void CemuInitialize(const char* execPath, const char* user_data_path, const char* config_path, const char* cache_path, const char* data_path);
void CemuRun(void);
void CemuShutdown(void);
void CemuUIKit_SetMainWindow(UIWindow* window);
void CemuUIKit_SetMainView(UIView* view);
void CemuUIKit_SetPadView(UIView* view);
void CemuUIKit_InitializeLayer(bool main);
void CemuUIKit_UpdateMainWindowSize(CGFloat width, CGFloat height, CGFloat scale);
void CemuUIKit_UpdatePadWindowSize(void);
void CemuUIKit_SetVisibleOutputs(bool tv, bool pad);
void CemuUIKit_SetPadTouch(CGFloat x, CGFloat y, bool down);
void* GCControllerBridge_add(const GCBridgeControllerDesc* desc);
void GCControllerBridge_remove(void* handle);
void GCControllerBridge_notifyChanged(void);
int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);
}

// Muffin's glue, in Core/. Plain C++ linkage: only this file calls them.
int IOSTitleLaunch_PrepareForegroundTitle(const char* path);
int IOSTitleLaunch_ReloadAndCountKeys();
int IOSTitleDecrypt_ExtractToFolder(const char* srcPath, const char* destFolderPath,
    std::atomic_bool& cancelRequested,
    const std::function<void(uint64_t bytesWritten, uint32_t filesWritten)>& progressCallback);
int IOSTitleDecrypt_ExtractToWua(const char* srcPath, const char* destPath,
    std::atomic_bool& cancelRequested,
    const std::function<void(uint64_t bytesWritten, uint32_t filesWritten)>& progressCallback);
std::string IOSCoverArt_DeriveGameTdbId(const char* romPath);
std::string IOSCoverArt_GetTitleName(const char* romPath);
bool IOSDlcUpdateImport_DeriveTitleId(const char* romPath, uint64_t* titleIdOut);
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

// The raw model identifier rather than a marketing name: a lookup table is out of date
// the day a device ships, and a wrong name is worse than an identifier.
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
    // BUILD_VERSION_STRING is a parenthesised expression, not a bare literal.
    g_deviceReport += " | build ";
    g_deviceReport += BUILD_VERSION_STRING;
    return g_deviceReport.c_str();
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
// A port of MeloCafe's own launch-time checks (MeloCafeApp.configureJITEnvironment and
// ProcessInfo.hasTXM), because its recompiler reads the answers from the environment:
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
    // THE dominant thermal difference between this port and MeloCafe, and it is by
    // design rather than a bug. On iOS the core's GetCPUMode() returns the config value
    // unresolved and _LaunchTitleThread() only starts the three emulated cores on their
    // own host threads for the two explicit Multicore modes - so MeloCafe's default
    // (Auto) runs every title on ONE host thread. This bridge always writes an explicit
    // mode, and Speed first means Multicore, so MuffinEMU runs THREE.
    //
    // Those host threads sit in PPCCore_boostBaseTime's `while (true)` loop
    // (coreinit_Thread.cpp), which reschedules without sleeping. Three of them resident
    // on a fanless A12Z is roughly three times the sustained CPU power draw of one, which
    // is exactly the "hot fast, while MeloCafe stays cool" report - MeloCafe is not doing
    // something clever, it is doing a third of the work.
    //
    // So single-core is the single biggest lever available, and Low Power Mode pulls it
    // without dragging in Favour accuracy's extra GPU work.
    const bool singleCore = accuracy || lowPower;
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
        GCBridgeControllerState s{};
        s.buttons = g_touchButtons | g_physicalButtons;
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
    // Same values MeloCafe's app sets: asynchronous queue submits, and enough active
    // command buffers per queue that Cemu's pipeline compiles do not stall the frame.
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
    // NUS dump already in the library) before this point, which permanently latches the
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
    catch (const std::exception& ex)
    {
        std::string message = std::string("initialize: CemuInitialize() threw: ") + ex.what();
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
    // Real time under the recompiler; an eighth under the interpreter, where the guest's
    // own deadlines are otherwise overdue before they are serviced. Swift overrides this
    // straight after when the user has picked a value.
    cemu_bridge_set_timebase_shift(g_cpuMode.load() == kCpuModeRecompiler ? 3 : 6);

    ios_input_start();
    ios_stats_start();
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

CemuBridgeStatus cemu_bridge_boot_title(const char* path) {
    if (!path || path[0] == '\0') {
        setStatus("boot_title: empty path.");
        return CEMU_BRIDGE_BAD_ARG;
    }
    if (!g_initialized.load()) {
        setStatus("The emulator core is not initialized.");
        return CEMU_BRIDGE_CORE_NOT_BUILT;
    }

    cemu_bridge_log_checkpoint("boot_title: about to prepare title");
    const int prepared = IOSTitleLaunch_PrepareForegroundTitle(path);
    cemu_bridge_log_checkpoint("boot_title: prepare returned");

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
            setStatus("This game is encrypted and no key in keys.txt opens it. Put the keys.txt you dumped from your own Wii U in Muffin's \"keys\" folder in the Files app (or import it in Settings), then relaunch Muffin and try again.");
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
    catch (const std::exception& ex)
    {
        std::string message = std::string("boot_title: CemuRun() threw: ") + ex.what();
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
        int status = toWua
            ? IOSTitleDecrypt_ExtractToWua(src.c_str(), dest.c_str(), g_decryptCancelRequested, progress)
            : IOSTitleDecrypt_ExtractToFolder(src.c_str(), dest.c_str(), g_decryptCancelRequested, progress);
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
    static std::string g_graphicPacksList;
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
    static std::string g_accountsList;
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
    static std::string g_countriesList;
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
    static std::string g_usbDeviceSlotNames;
    g_usbDeviceSlotNames = IOSEmulatedDevices_SlotNames((int)device);
    return g_usbDeviceSlotNames.c_str();
}

const char* cemu_bridge_usb_device_figure_list(CemuBridgeUSBDevice device, int slot) {
    static std::string g_usbDeviceFigureList;
    g_usbDeviceFigureList = IOSEmulatedDevices_FigureList((int)device, slot);
    return g_usbDeviceFigureList.c_str();
}

const char* cemu_bridge_usb_device_load(CemuBridgeUSBDevice device, int slot, const char* path) {
    static std::string g_usbDeviceLoadError;
    g_usbDeviceLoadError = IOSEmulatedDevices_Load((int)device, slot, path);
    return g_usbDeviceLoadError.empty() ? nullptr : g_usbDeviceLoadError.c_str();
}

const char* cemu_bridge_usb_device_clear(CemuBridgeUSBDevice device, int slot) {
    static std::string g_usbDeviceClearError;
    g_usbDeviceClearError = IOSEmulatedDevices_Clear((int)device, slot);
    return g_usbDeviceClearError.empty() ? nullptr : g_usbDeviceClearError.c_str();
}

const char* cemu_bridge_usb_device_create(CemuBridgeUSBDevice device, uint32_t figureId, uint16_t variant, const char* path) {
    static std::string g_usbDeviceCreateError;
    g_usbDeviceCreateError = IOSEmulatedDevices_Create((int)device, figureId, variant, path);
    return g_usbDeviceCreateError.empty() ? nullptr : g_usbDeviceCreateError.c_str();
}

const char* cemu_bridge_usb_device_move_dimensions(int fromSlot, int toSlot) {
    static std::string g_usbDeviceMoveError;
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
            cemuLog_log(LogType::Force,
                "Emulated timebase: the ladder is at its floor - shift {} (1/64 real time) - and after "
                "{:.1f}s the title still has not reached GX2Init. The guest's clock is not what is holding "
                "this title, so the ladder stops rather than making the console slower to no purpose.",
                shift, elapsed);
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
    return g_titleRunning.load() && CafeSystem::IsTitleRunning() && !IOSSystemImplementation_TitleExited(nullptr);
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
    cemu_bridge_release_all_buttons();
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
    std::lock_guard lock(g_inputMutex);
    if (pressed)
        g_touchButtons |= (1u << bit);
    else
        g_touchButtons &= ~(1u << bit);
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
    g_touchButtons = 0;
    g_touchSticks[0] = g_touchSticks[1] = GCBridgeVec2{};
}

const char* cemu_bridge_status_text(void) {
    int exitStatus = 0;
    if (g_titleRunning.load() && IOSSystemImplementation_TitleExited(&exitStatus))
    {
        char line[96];
        snprintf(line, sizeof(line), "The game closed itself (exit status %d).", exitStatus);
        setStatus(line);
    }
    // Only fall back to a computed default when nothing specific has been set, so a boot
    // failure's reason is not overwritten by a generic line on the next read.
    if (statusIsEmpty())
        setStatus(cemu_bridge_is_title_running() ? "Title running." : "Core ready (no title running).");
    return getStatus();
}
