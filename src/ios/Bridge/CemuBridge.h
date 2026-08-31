//
//  CemuBridge.h
//  Real Swift <-> Cemu C++ engine bridge.
//
//  Pure-C interface so it can be imported from Swift via the bridging header.
//  The implementation (CemuBridge.mm) calls the genuine CafeSystem API.
//
//  Until the real Cemu core is compiled for iOS (ROADMAP.md M1), this is built
//  WITHOUT the CEMU_CORE_AVAILABLE flag and every call honestly reports
//  CEMU_BRIDGE_CORE_NOT_BUILT instead of pretending to emulate.
//
#ifndef CEMU_BRIDGE_H
#define CEMU_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    CEMU_BRIDGE_OK              = 0,   // title prepared/started (maps CafeSystem SUCCESS)
    CEMU_BRIDGE_INVALID_RPX     = 1,   // maps PREPARE_STATUS_CODE::INVALID_RPX
    CEMU_BRIDGE_UNABLE_TO_MOUNT = 2,   // maps PREPARE_STATUS_CODE::UNABLE_TO_MOUNT
    // The disc image is real and readable, but no key in keys.txt decrypts it - either
    // there is no keys.txt yet, or it does not contain the key for THIS disc. Cemu tries
    // every key it has against the disc header, so this is never a "wrong key selected"
    // problem, only a "key not present" one.
    CEMU_BRIDGE_NO_DISC_KEY     = 3,
    CEMU_BRIDGE_NO_TITLE_TIK    = 4,   // installed title with no usable title.tik
    CEMU_BRIDGE_UNSUPPORTED     = 5,   // not a title and not a loadable executable
    CEMU_BRIDGE_BASE_NOT_FOUND  = 6,   // an update/DLC was launched without its base game
    CEMU_BRIDGE_CORE_NOT_BUILT  = 100, // real engine not linked into this build yet (pre-M1)
    CEMU_BRIDGE_BAD_ARG         = 101, // null/empty path etc.
} CemuBridgeStatus;

/// True only when the real Cemu C++ engine is compiled and linked into this build.
/// Swift uses this to decide whether to show the honest "not built yet" state.
bool cemu_bridge_core_available(void);

/// One-time engine initialization. `mlcPath` = MLC/NAND root inside the app sandbox.
/// Safe (no-op) when the core is not available.
void cemu_bridge_initialize(const char* mlcPath);

/// Boot whatever the user picked: an encrypted disc image (.wux/.wud/.iso), a Wii U
/// archive (.wua), a dumped game folder, or a standalone homebrew .rpx. Returns
/// CEMU_BRIDGE_OK when the title starts.
///
/// Real games are decrypted with the user's OWN console keys, read from keys.txt in the
/// app's Documents/mlc directory. Nothing is bundled, derived or worked around: with no
/// keys.txt the disc paths report CEMU_BRIDGE_NO_DISC_KEY and homebrew keeps working
/// exactly as before. keys.txt is re-read on every call, so importing one mid-session
/// takes effect on the next launch attempt rather than after an app restart.
CemuBridgeStatus cemu_bridge_boot_title(const char* path);

/// Boot a standalone .rpx and nothing else. Kept as the narrow homebrew entry point;
/// cemu_bridge_boot_title() is what the app calls, and it falls through to this same
/// engine path for an RPX/ELF.
/// Wraps CafeSystem::PrepareForegroundTitleFromStandaloneRPX + LaunchForegroundTitle.
CemuBridgeStatus cemu_bridge_boot_rpx(const char* rpxPath);

/// Re-reads keys.txt and returns how many 128-bit keys the engine's own parser accepted.
/// 0 means the file is absent, empty, or contains nothing usable. Cheap; safe to call
/// from the UI.
///
/// Returns -1, meaning "cannot answer", when the engine has not been initialized yet
/// (keys.txt is resolved against the user data path cemu_bridge_initialize() sets up) or
/// when the core is not in this build. That is deliberately distinct from 0, which is a
/// real answer about a real file.
int cemu_bridge_reload_and_count_keys(void);

/// M3 (ROADMAP.md): wires the real native Metal renderer to an actual on-screen
/// surface. `uiView` must be a UIView* (bridged as void*); `width`/`height` are its
/// client size in LOGICAL POINTS (not physical pixels - the points -> pixels
/// conversion is applied downstream, exactly once per consumer, using `dpiScale`;
/// see the comment at this function's definition in CemuBridge.mm), `dpiScale` its
/// contentScaleFactor. Must be called before
/// cemu_bridge_boot_rpx() - the GPU thread reads the window size synchronously at
/// startup. Safe (no-op) when the core is not available.
void cemu_bridge_register_render_surface(void* uiView, int width, int height, double dpiScale);

/// Registers a SECOND surface for the Wii U GamePad (DRC) screen, so the two Wii U
/// outputs can be shown at once when there is somewhere to put them - the TV screen on
/// an external display (AirPlay / screen mirroring / a cable) and the GamePad screen on
/// the device. Same units as above: LOGICAL POINTS plus a scale.
///
/// When this is never called, `MetalRenderer::IsPadWindowActive()` stays false and the
/// renderer skips every pad-window code path outright rather than failing inside one.
/// That - not a second layer - is what "TV only" means here, and it is the normal
/// configuration on a device with no external display.
///
/// Main thread only: it creates a CAMetalLayer inside `uiView`. Safe (no-op) when the
/// core is not available.
void cemu_bridge_register_pad_render_surface(void* uiView, int width, int height, double dpiScale);

/// Asks for the pad surface to be dropped, because its display went away. The teardown
/// itself happens on the GPU thread at its next frame boundary - the pad layer belongs
/// to that thread while a title runs - so this returns immediately and the caller must
/// NOT free the hosting view. Safe to call when no pad surface exists.
void cemu_bridge_release_pad_render_surface(void);

/// True while a pad surface is registered. Reflects the renderer's own
/// IsPadWindowActive(), i.e. it only goes false once the GPU thread has actually
/// completed a release requested above.
bool cemu_bridge_has_pad_render_surface(void);

/// Re-sizes an already-registered surface after its hosting view moved or its display
/// changed - both the drawable and the CALayer's own frame/backing scale, which nothing
/// else maintains for a manually added sublayer. `mainWindow` selects TV vs GamePad.
/// Main thread only (Core Animation geometry). Safe (no-op) when the core is not
/// available or that surface was never registered.
void cemu_bridge_resize_render_surface(int width, int height, double dpiScale, bool mainWindow);

/// Writes a line into the engine's own log (log.txt + the os_log mirror) at
/// LogType::Force. Exists so Swift-side decisions that determine what the renderer
/// does - above all which physical display each Wii U screen was routed to - land in
/// the same timeline as the renderer's own lines, instead of in a separate iOS log
/// nobody correlates. Not a substitute for cemu_bridge_log_checkpoint(), which uses a
/// synchronous write() and survives an abrupt kill; this one goes through the engine's
/// buffered logger.
void cemu_bridge_log_line(const char* message);

/// Last frame rate actually measured by the emulator, or 0 when no title is
/// producing frames (idle, loading, or not yet rendering). This is the engine's own
/// number - LattePerformanceMonitor computes it and pushes it through
/// WindowSystem::UpdateWindowTitles() about once a second - not an estimate made on
/// the Swift side. Safe to call at any time; returns 0 when the core is not
/// available.
double cemu_bridge_get_fps(void);

/// The four counters the engine's own progress heartbeat prints, readable on demand.
///
/// This exists because `cemu_bridge_get_fps()` cannot answer the question that actually
/// matters on this port. It reports whole frames per second, so a title genuinely
/// rendering at a fraction of a frame per second - the normal case under the forced
/// interpreter - rounds to 0 and the HUD reads "-- FPS", identical to a title that
/// stopped dead. These counters separate the two, on screen, without anyone having to
/// export log.txt:
///
///   gx2FrameCount climbing, however slowly  -> running past the first frame, just slow
///   gx2FrameCount pinned, gx2InitReached    -> stalled after handing over to GX2
///   gx2InitReached false, others climbing   -> still in OSScreen boot
///   nothing moving at all                   -> a real deadlock, not slowness
///
/// `gx2FramesPerSecond` is fractional on purpose and is the heartbeat's own measurement,
/// not a second one taken here, so the number on screen and the number in the log are
/// the same number rather than two samples that disagree.
typedef struct {
    bool gx2_init_reached;
    unsigned long long gx2_frame_count;
    double gx2_frames_per_second;
    unsigned long long os_screen_scanouts;
    unsigned int guest_flip_requests;
} CemuBridgeProgress;

/// Fills `out` with the counters above. Zeroed, with `gx2_init_reached` false, when no
/// title is running or the core is not in this build - all of which are true statements
/// rather than placeholders. Safe to call from any thread, cheap enough to poll.
void cemu_bridge_get_progress(CemuBridgeProgress* out);

/// How fast the emulated console believes time is passing, as a right-shift factor:
/// 3 = real time (1x), 4 = half (0.5x), 5 = quarter, 6 = an eighth, and so on. This is
/// Cemu's own `ActiveSettings::SetTimerShiftFactor()`, which desktop Cemu exposes as its
/// Timer Speed menu; nothing on iOS was setting it, so it sat at 3 on every launch.
///
/// It matters here far more than it does on desktop. Under the forced interpreter the
/// emulated CPU retires instructions on the order of a hundred times slower than the
/// hardware it is pretending to be, while `PPCTimer_getFromRDTSC()` keeps deriving the
/// guest's clock from the host's wall clock. The guest therefore experiences a console
/// whose CPU has effectively stopped: every periodic deadline it sets - coreinit alarms,
/// the AX audio callback, thread quanta - is already long overdue by the time it is
/// serviced, so the scheduler can spend all of its time on overdue timer work and never
/// return to the title's own thread. The visible result is a title that presents one
/// frame and then appears to hang, which is not a hang.
///
/// Raising the shift makes the guest's clock advance more slowly, so its deadlines stay
/// reachable and it runs in honest slow motion instead of drowning. It changes no
/// emulated result: it is the rate a monotonic counter accumulates, applied per call, so
/// it can be changed while a title runs and time still only ever moves forward.
///
/// This is a compensation for an emulator that is too slow. It does not make it faster.
void cemu_bridge_set_timebase_shift(int shift);

/// The shift currently in effect. See above for the scale.
int cemu_bridge_get_timebase_shift(void);

/// Turns the automatic clock ladder on or off.
///
/// The Emulated clock setting above is only useful if somebody knows which value to pick,
/// and nothing knows that in advance - it depends on how tight a particular title's own
/// deadlines are. Left to a person it means launch, wait, decide it is still stuck, open
/// Settings, step down one, wait again. On a port with one test device that loop is the
/// bottleneck, not the code.
///
/// So the engine walks it itself. While a title is booting on the interpreter and has not
/// reached GX2Init, the ladder steps the guest's clock down one notch every twelve seconds
/// to a floor of 1/64, and stops the moment GX2 is reached - logging which value got there,
/// which is a measurement this port has never had.
///
/// Enabled unless the user has chosen a value by hand; choosing one turns it off for good,
/// because a search that overrides a deliberate choice is a bug rather than a convenience.
/// It never runs under the recompiler, where the premise does not hold. Stepping is always
/// downward, so a step that was not needed costs slow motion, never a hang.
void cemu_bridge_set_timebase_auto_enabled(bool enabled);

/// Whether the ladder is allowed to run. See above.
bool cemu_bridge_timebase_auto_enabled(void);

/// Which CPU path this launch actually got: 0 = not decided yet (the engine has not
/// initialized), 1 = interpreter, 2 = PPC recompiler (JIT).
///
/// 0 and 1 are deliberately different values. "Nothing has chosen yet" is not the same
/// claim as "the interpreter", and a caller that collapsed them would tell the user the
/// recompiler is off before anything had looked.
///
/// Decided once, in cemu_bridge_initialize(), and constant for the process after that -
/// LaunchSettings::SetForceInterpreter() is read by PPCRecompiler_init() during title
/// boot and nothing changes it later. Safe to call from any thread.
int cemu_bridge_cpu_mode(void);

/// Diagnostic switches, all read when a title starts rather than while one runs.
///
/// These exist because two builds in a row were unusable and neither of us could tell
/// which change was responsible without a twenty-minute rebuild per guess. Each one
/// isolates a subsystem that has been wrong before.
void cemu_bridge_set_recompiler_enabled(bool enabled);
bool cemu_bridge_recompiler_enabled(void);
/// Falls back to the original spinlock timebase. The rewritten one had an overflow that
/// ran the emulated console's clock 65 times too slow.
void cemu_bridge_set_legacy_timebase(bool useLegacy);
bool cemu_bridge_legacy_timebase(void);

/// Whether shaders and pipelines are compiled in the background instead of the game
/// waiting for each one.
///
/// This is the real setting. There is also a `precompiled_shaders` option in the config
/// header, and it is INERT here: ActiveSettings::GetPrecompiledShadersOption() returns a
/// hardcoded Auto with its lookup commented out, and the only code that reads it is the
/// OpenGL backend. Exposing that one would be a switch that moves and changes nothing.
/// async_compile is read by MetalPipelineCache on every pipeline it builds.
void cemu_bridge_set_async_shader_compile(bool enabled);
bool cemu_bridge_async_shader_compile(void);

/// Shader cache maintenance. Two different things get called "the shader cache" and
/// deleting them has very different consequences, so they are separate:
///
///   learned  - shaderCache/transferable. The Wii U bytecode of every shader a title has
///              ever revealed. A title only reveals a shader by drawing with it, so this
///              is the only reason anything can be compiled before you play. Deleting it
///              throws that away until those parts are played again.
///   compiled - shaderCache/precompiled. Compiled output. Rebuilds by itself, so deleting
///              it costs one slow launch and nothing else.
///
/// titleId 0 means every title. Returns bytes freed, or -1 on error.
long long cemu_bridge_clear_shader_cache(unsigned long long titleId, bool includeLearned);
/// Returns 0 on success. Either out pointer may be null.
int cemu_bridge_shader_cache_stats(unsigned long long titleId, long long* outLearnedBytes, long long* outCompiledBytes);

/// The reason behind cemu_bridge_cpu_mode(), in a sentence the person holding the iPad
/// can act on - which is the point: the answer used to be obtainable only by reading a
/// cs_flags hex value out of a crash log. Never NULL. Points to thread-local storage the
/// next call ON THE SAME THREAD overwrites; Swift's String(cString:) copies, so that is
/// enough lifetime for any caller here.
const char* cemu_bridge_cpu_mode_detail(void);

bool cemu_bridge_is_title_running(void);
void cemu_bridge_pause(void);
void cemu_bridge_resume(void);
void cemu_bridge_shutdown_title(void);
void cemu_bridge_shutdown(void);

/// Human-readable one-liner describing engine/bridge state, for display in the UI.
/// Never NULL. Points to static/thread-local storage; copy if you need to keep it.
const char* cemu_bridge_status_text(void);

/// Appends a timestamped-by-nothing (just ordered) line to Documents/CemuCrashLog.txt.
/// Written via a raw synchronous write() so it survives even an abrupt/uncatchable
/// process termination (e.g. a GPU driver panic) - call this at every meaningful
/// startup milestone from Swift so a crash's location can be narrowed down from the
/// surviving log alone.
void cemu_bridge_log_checkpoint(const char* message);

/// Current memory position of this process, in bytes. `availableBytes` is the
/// headroom iOS will allow before it kills the process (os_proc_available_memory),
/// `footprintBytes` is what the process is currently billed for (phys_footprint).
/// Either pointer may be NULL. Returns false if neither could be read.
///
/// Note this is NOT free system RAM. A device can have a gigabyte free and still
/// kill this process, and that gap is the whole reason the figure is reported.
bool cemu_bridge_memory_status(unsigned long long* availableBytes, unsigned long long* footprintBytes);

/// Writes one memory-position line, tagged with `tag`, to the crash log. Use at
/// points where a jump in footprint would be meaningful - the GX2 handover being
/// the obvious one, since that is where a retail title starts allocating for real.
void cemu_bridge_memory_note(const char* tag);

/// Starts the 10 Hz memory sampler and subscribes to iOS memory warnings. Both
/// write to the crash log via synchronous write(), because the termination they
/// exist to explain (jetsam) delivers no signal and takes any buffered log with
/// it. Idempotent; safe to call more than once.
void cemu_bridge_start_memory_watchdog(void);

/// Absolute path of the file cemu_bridge_log_checkpoint() and the crash handler write
/// to. Never NULL, but empty if $HOME was unset and the log was never opened. Points to
/// static storage; copy if you need to keep it.
///
/// Exists because the answer is not guessable from the UI side. Under LiveContainer
/// $HOME is redirected per hosted app, so the file is not where it would be for a
/// normally installed app, and telling someone the wrong folder is worse than telling
/// them nothing - they conclude the crash log does not exist. Print this instead.
const char* cemu_bridge_crash_log_path(void);

/// Rescans for physical controllers and binds the first one found to player 1's
/// emulated GamePad if nothing is bound yet.
///
/// Normally unnecessary - SDL's own device-added event already triggers this - but it
/// costs nothing and closes the window where a controller pairs during app startup,
/// before the hotplug hook was installed. Safe to call at any time; a no-op until
/// cemu_bridge_initialize() has run.
void cemu_bridge_refresh_input_devices(void);

/// A button on player 1's emulated Wii U GamePad, as the iOS app names it.
///
/// Deliberately its own enum rather than VPADController::ButtonId. These values are
/// baked into Swift call sites, so they have to stay put; ButtonId is Cemu's internal
/// numbering and is free to be reordered upstream at any time. InputManager.cpp maps
/// one to the other in a single explicit switch, which is the only place that has to be
/// revisited if either side changes.
typedef enum {
    CEMU_BRIDGE_BUTTON_NONE    = 0,

    CEMU_BRIDGE_BUTTON_A       = 1,
    CEMU_BRIDGE_BUTTON_B       = 2,
    CEMU_BRIDGE_BUTTON_X       = 3,
    CEMU_BRIDGE_BUTTON_Y       = 4,

    CEMU_BRIDGE_BUTTON_L       = 5,
    CEMU_BRIDGE_BUTTON_R       = 6,
    CEMU_BRIDGE_BUTTON_ZL      = 7,
    CEMU_BRIDGE_BUTTON_ZR      = 8,

    CEMU_BRIDGE_BUTTON_PLUS    = 9,
    CEMU_BRIDGE_BUTTON_MINUS   = 10,

    CEMU_BRIDGE_BUTTON_UP      = 11,
    CEMU_BRIDGE_BUTTON_DOWN    = 12,
    CEMU_BRIDGE_BUTTON_LEFT    = 13,
    CEMU_BRIDGE_BUTTON_RIGHT   = 14,

    CEMU_BRIDGE_BUTTON_STICK_L = 15, // left stick pressed in (L3)
    CEMU_BRIDGE_BUTTON_STICK_R = 16, // right stick pressed in (R3)

    CEMU_BRIDGE_BUTTON_HOME    = 17,

    CEMU_BRIDGE_BUTTON_COUNT   = 18,
} CemuBridgeButton;

/// Holds or releases one GamePad button from the on-screen controls.
///
/// This is press-and-release, not "tap": `pressed` stays true for as long as the finger
/// is down, because holding a direction is most of playing anything. Calling it twice
/// with the same value is harmless.
///
/// The state is an override that sits in FRONT of whatever physical controller is bound
/// (EmulatedController::is_mapping_down checks it first), so the touch pad and an
/// MFi controller work at the same time and neither cancels the other. The flip side:
/// a button left true is held forever as far as the title is concerned, so every press
/// must be paired with a release - see cemu_bridge_release_all_buttons() for the case
/// where the UI cannot be sure it will get one.
///
/// Safe to call from the main thread while the emulated title polls from its own; a
/// no-op until cemu_bridge_initialize() has brought input up.
void cemu_bridge_set_button_state(CemuBridgeButton button, bool pressed);

/// Releases every GamePad button at once, and re-centres both analog sticks. For the
/// cases where the UI knows a press can no longer be tracked to its natural end - the
/// control panel being dismissed, the app going to the background, a gesture the system
/// cancelled out from under it - and would otherwise leave the title holding a direction
/// with nothing on screen touching it.
void cemu_bridge_release_all_buttons(void);

/// Which analog stick an axis call is about.
typedef enum {
    CEMU_BRIDGE_STICK_LEFT  = 0,
    CEMU_BRIDGE_STICK_RIGHT = 1,
} CemuBridgeStick;

/// Positions one analog stick on player 1's emulated GamePad from the on-screen controls.
///
/// This is the axis counterpart to cemu_bridge_set_button_state(), and it exists because
/// there was no way to express a stick at all: CEMU_BRIDGE_BUTTON_STICK_L/R are the
/// *clicks* (L3/R3), and Cemu deliberately skips the eight kButtonId_Stick*_ entries in
/// its button loop because VPADRead derives the sticks from get_axis() instead. Sending a
/// direction as a button press is therefore not a rough approximation of a stick - it
/// does nothing at all.
///
/// `x` and `y` are in -1..1 and use the CONSOLE's convention, not the screen's: +x is
/// right and +y is UP. A caller working in view coordinates has to negate y, and the
/// on-screen pad does. Values outside the unit circle are clamped by magnitude rather
/// than per-component, so a diagonal cannot ask for more deflection than the hardware can
/// produce (Cemu normalizes anything longer than 1 anyway; clamping here keeps the number
/// the engine reports equal to the number that was sent).
///
/// Same override semantics as the buttons: it sits in front of any bound physical
/// controller, and a zero on both components hands the stick back to that controller
/// rather than pinning it to centre. So (0,0) is both "released" and "not overridden",
/// which is what lets an MFi stick and the on-screen one coexist.
///
/// Safe to call from the main thread while the title polls from its own; a no-op until
/// cemu_bridge_initialize() has brought input up. Repeated identical values cost nothing.
void cemu_bridge_set_stick_axis(CemuBridgeStick stick, float x, float y);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CEMU_BRIDGE_H
