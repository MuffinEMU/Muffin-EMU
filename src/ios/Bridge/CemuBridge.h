//
//  CemuBridge.h
//  MuffinEMU's Swift <-> engine bridge.
//
//  Pure-C interface so it can be imported from Swift via the bridging header. The
//  implementation (CemuBridge.mm) runs on the Cemu core and is compiled into
//  Cemu.framework next to it; the app target never sees an engine header.
//
#ifndef CEMU_BRIDGE_H
#define CEMU_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

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

/// Which of the two registered surfaces the renderer actually draws to this frame,
/// without touching whether either is registered at all. This is what Settings >
/// Screen Layout's swap button uses: both the TV and GamePad surfaces stay registered
/// the whole time a title runs, and swapping which one is on screen is just this call,
/// not a register/release cycle - the difference between an instant tap and rebuilding
/// a CAMetalLayer on every tap. cemu_bridge_register_pad_render_surface() /
/// cemu_bridge_release_pad_render_surface() already call this internally at the
/// moments they need to (see CemuBridge.mm); call it directly only to change which
/// already-registered surface(s) are visible without registering or releasing anything.
void cemu_bridge_set_visible_outputs(bool tv, bool pad);

/// The GamePad's own touchscreen - a real Wii U input, and a distinct one from every
/// button on the pad. `x`/`y` are in the SAME physical-pixel space
/// cemu_bridge_resize_render_surface()'s width/height already are for the pad surface
/// (points times the render scale actually in effect, not raw SwiftUI points) - the core
/// maps them into Wii U touchscreen coordinates by treating them as a position inside
/// the GamePad window's current phys size, the same way the desktop build's wxWidgets
/// pad-window mouse/gesture handlers already do. `down` false on release; the position
/// on that final call does not matter, only the transition does.
void cemu_bridge_set_pad_touch(double x, double y, bool down);

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
    // Always 0 on this core, which does not count OSScreen scanouts separately.
    unsigned long long os_screen_scanouts;
    unsigned int guest_flip_requests;
} CemuBridgeProgress;

/// Fills `out` with the counters above. Zeroed, with `gx2_init_reached` false, when no
/// title is running or the core is not in this build - all of which are true statements
/// rather than placeholders. Safe to call from any thread, cheap enough to poll.
void cemu_bridge_get_progress(CemuBridgeProgress* out);

/// Decrypt-to-Files / Decrypt-to-WUA: takes a WUD/WUX (or a folder/NUS dump) the app
/// already has a working key for and writes a fully decrypted copy of it to destPath,
/// in one of two shapes depending on `toWua`:
///   - false: destPath is a FOLDER, filled with the same code/, content/, meta/ layout
///     a folder dump already has - importable and bootable exactly like one.
///   - true: destPath is a single .wua FILE - a portable archive of the same decrypted
///     contents, matching the format the "Full dump folder" / desktop WUA workflow
///     already produces and imports.
/// The source at srcPath is opened read-only and never modified either way.
///
/// Starts the extraction on a background thread and returns immediately; true if it
/// started, false on a bad argument or if a decrypt is already running (only one runs
/// at a time - poll cemu_bridge_get_decrypt_progress() and wait for `completed` before
/// starting another). No decryption logic lives on this side of the bridge at all: it
/// reuses FSTVolume / TitleInfo, the same engine code every ordinary boot already
/// depends on to read a disc.
bool cemu_bridge_start_decrypt(const char* srcPath, const char* destPath, bool toWua);

typedef struct {
    bool is_running;
    bool completed;
    int result_status; // valid once completed is true - IOS_DECRYPT_* from IOSTitleDecrypt.cpp
    unsigned long long bytes_written;
    unsigned int files_written;
} CemuBridgeDecryptProgress;

/// Snapshot of the current (or most recently finished) decrypt. Zeroed when nothing has
/// ever been started. Safe to poll from the main thread while a decrypt runs elsewhere.
void cemu_bridge_get_decrypt_progress(CemuBridgeDecryptProgress* out);

/// Asks the running decrypt to stop at the next safe point (between files, or between
/// chunks of a large one) rather than completing. Whatever was already written to
/// destFolderPath is left as-is - a partial, incomplete folder tree, not cleaned up
/// automatically, since the caller is in a better position than the engine to decide
/// whether a partial extraction is worth keeping or deleting. No-op if nothing is
/// running.
void cemu_bridge_cancel_decrypt(void);

/// Derives the 6-character GameTDB Game ID (e.g. "AGME01") from romPath's own
/// meta.xml, for fetching real box art automatically on import - see
/// IOSCoverArt_DeriveGameTdbId() in IOSCoverArt.cpp for the exact derivation and why
/// it needs no separate region lookup. Writes into outGameID (must be at least 7
/// bytes: 6 characters plus the null terminator) and returns true on success; returns
/// false and leaves outGameID untouched if no real ID could be derived (homebrew,
/// unset metadata, or a title format this doesn't apply to) - not every game has box
/// art to fetch, and that is a normal outcome, not an error.
bool cemu_bridge_derive_gametdb_id(const char* romPath, char* outGameID, size_t outGameIDSize);

/// The title's long name from its own meta.xml ("Super Mario 3D World"), for the library.
/// Writes a null-terminated UTF-8 string, truncated to fit, and returns true; returns false
/// and leaves outName untouched when there is no usable meta.xml (homebrew, a bare RPX).
/// Parses the dump, so call it off the main thread.
bool cemu_bridge_get_title_name(const char* romPath, char* outName, size_t outNameSize);

/// Derives the raw 64-bit title ID from romPath's own meta.xml/app.xml (via
/// TitleInfo::GetAppTitleId() - see IOSDlcUpdateImport.cpp), for matching an imported
/// DLC or update against the base game already in the library. Returns false and
/// leaves outTitleId untouched if romPath isn't a valid, fully-parsed title.
bool cemu_bridge_derive_title_id(const char* romPath, uint64_t* outTitleId);

/// Reduces any title ID - base, update, or AOC/DLC - to its base title's ID, using the
/// same bit-math CafeTitleList::FindBaseTitleId() already uses for the real boot path.
/// Two different titles with the same base ID belong to the same game; this is how the
/// import flow finds which installed game a DLC/update belongs to.
uint64_t cemu_bridge_derive_base_title_id(uint64_t titleId);

/// Returns the raw title-type byte for titleId (TitleIdParser::TITLE_TYPE from
/// TitleId.h: 0x00 base, 0x0E update, 0x0C AOC/DLC, 0xFF unknown, etc.) - lets the
/// import flow reject a file that isn't actually the type the user said it was (e.g.
/// "Import DLC" on something that's really an update).
int cemu_bridge_get_title_type(uint64_t titleId);

/// Writes the two path components the engine's own MLC scanner expects under
/// <mlc>/usr/title/ for titleId: the type-prefix directory (upper 32 bits, e.g.
/// "0005000c" for AOC) into outUpperHex, then the title's own directory (lower 32
/// bits, holding code/content/meta) into outLowerHex. Both buffers must be at least 9
/// bytes (8 hex chars plus the null terminator). Pass the DLC/update's own title ID
/// here, not its base-reduced form - a DLC/update installs under its own ID, not the
/// base game's.
void cemu_bridge_get_mlc_title_path_components(uint64_t titleId, char* outUpperHex, char* outLowerHex);

/// TitleInfo::InvalidReason values, mirrored here for the Swift side of the DLC/update
/// import flow - see TitleInfo.h for the authoritative definitions and the reasoning
/// behind each one.
typedef enum {
    CemuTitleValid = 0,
    CemuTitleBadPathOrInaccessible = 1,
    CemuTitleUnknownFormat = 2,
    CemuTitleNoDiscKey = 3,
    CemuTitleNoTicket = 4,
    CemuTitleMissingXmlFiles = 5,
} CemuTitleInvalidReason;

/// Inspects romPath as a candidate DLC/update import in one pass: on success (true),
/// fills outTitleId/outVersion/outRegion (outRegion is a CafeConsoleRegion bitmask
/// value, e.g. 0x2 for USA) and leaves outInvalidReason at CemuTitleValid. On failure
/// (false), fills only outInvalidReason with the specific reason - not a generic
/// "import failed" - and leaves the others untouched. Any out-pointer may be NULL if
/// the caller doesn't need that field.
bool cemu_bridge_inspect_title(const char* romPath, uint64_t* outTitleId, uint16_t* outVersion,
    int* outRegion, int* outInvalidReason);

/// The reverse of cemu_bridge_derive_base_title_id: what baseTitleId's update (isUpdate
/// true) or AOC/DLC (isUpdate false) title ID would be. Returns 0 (never a real title
/// ID) if baseTitleId can't have that kind of content at all. Lets removal locate an
/// installed DLC/update on disk without needing a file to re-derive it from.
uint64_t cemu_bridge_derive_content_title_id(uint64_t baseTitleId, bool isUpdate);

/// Rescans Documents/mlc/graphicPacks/ for graphic packs (GraphicPack2::LoadAll) - call
/// once at startup and again whenever the user might have dropped in new pack folders.
/// A no-op, not an error, while a title is currently running.
void cemu_bridge_graphic_packs_refresh(void);

/// One pack per record, most-recently-scanned order. Records are separated by 0x1E,
/// fields within a record by 0x1F: index, name, description, "1"/"0" for enabled, then
/// a comma-joined list of the pack's own title IDs (16 lowercase hex chars each, empty
/// if the pack applies to everything). index is stable only until the next refresh -
/// pass it straight back to cemu_bridge_graphic_pack_set_enabled.
///
/// Same ownership as cemu_bridge_device_report and friends: the returned pointer is
/// into a static buffer this function owns, valid until the next call to this same
/// function - copy it (e.g. String(cString:)) before calling again, never free it.
const char* cemu_bridge_graphic_packs_list(void);

/// Enables or disables the pack at `index` (from the most recent
/// cemu_bridge_graphic_packs_list call) and persists the change immediately - it will
/// still be enabled/disabled the same way after the next refresh or app relaunch.
void cemu_bridge_graphic_pack_set_enabled(int index, bool enabled);

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

/// Speed first, or accuracy first. MuffinEMU is tuned for speed by default: the multi-core
/// recompiler (the multi-core interpreter when no JIT enabler is attached), shaders built
/// in the background, and the work that only buys accuracy - accurate Vulkan barriers and
/// GX2DrawDone synchronisation - skipped. On, this takes Cemu's most compatible choice for
/// each instead: one emulated CPU core, every shader built before the frame that needs it,
/// accurate barriers and draw-done sync. For the titles that glitch, desync or crash on
/// the fast path. Read when a title starts.
void cemu_bridge_set_favour_accuracy(bool enabled);
bool cemu_bridge_favour_accuracy(void);

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


/// VSync for both Wii U screens' Metal layers - CAMetalLayer.displaySyncEnabled, which
/// nothing on this port has ever set before (Cemu's own `vsync` config value only ever
/// reached the Vulkan backend's swapchain present-mode selection - VulkanRenderer.cpp/
/// SwapchainInfoVk.cpp - and does nothing for Metal). Metal's own default for a freshly
/// created CAMetalLayer is true (synced), so leaving this untouched changed nothing for
/// anyone; on means nextDrawable() paces to the display's refresh (smoother, capped at
/// the screen's rate, no tearing), off lets a title that can render faster than that do
/// so uncapped, at the cost of possible tearing. Applied in
/// MetalRenderer::InitializeLayer() right after setPixelFormat(), so - like the other
/// settings on this page - it takes effect on the NEXT title launch, not the one already
/// running.
void cemu_bridge_set_vsync_enabled(bool enabled);

bool cemu_bridge_vsync_enabled(void);

/// Frame stretching. Drives the engine's own fullscreen_scaling, the same config value
/// desktop's "Fullscreen scaling" radio box sets - kStretch fills the window,
/// kKeepAspectRatio letterboxes 1280x720 inside it. Re-read every time the output blit
/// is sized, so unlike vsync above it takes effect on the next frame, not the next launch.
///
/// This declaration is the half of the pair that the ea2d6e05 engine restore dropped:
/// f57b840c put the definition back into CemuBridge.mm but not this line, and Swift only
/// sees what this header declares - SettingsView.swift and GameManager.swift both call
/// it, so without it the app target does not compile. The comm(1) check described on the
/// definition in CemuBridge.mm has to be run against this file as well as the .mm.
void cemu_bridge_set_stretch_to_fill(bool enabled);

/// Which renderer the next title uses: 2 = Metal (the native path and the default), 1 =
/// Vulkan through MoltenVK. Anything else falls back to Metal. Read by CemuRun() when a
/// title starts, so it cannot change the renderer of a running title.
void cemu_bridge_set_graphics_api(int api);
int cemu_bridge_graphics_api(void);

/// Filters for scaling the 1280x720 (or GamePad 854x480) image to the screen: 0 linear,
/// 1 bicubic, 2 bicubic hermite, 3 nearest neighbour. Upscale defaults to bicubic,
/// downscale to linear - the core's own defaults. Out-of-range values are ignored.
void cemu_bridge_set_upscale_filter(int filter);
void cemu_bridge_set_downscale_filter(int filter);

// ---------------------------------------------------------------------------
// Screen orientation, gamma and the on-screen performance overlay.
//
// All three are config values the desktop core has carried for years (render_upside_down,
// userDisplayGamma, the `overlay` struct in CemuConfig.h) that nothing on this port had
// ever wired to the UI - the engine already reads them correctly, they just always held
// their compiled-in defaults. Grouped here because they are the graphics-adjacent options
// that round out Settings without touching anything the accuracy profile already drives
// (see cemu_bridge_set_favour_accuracy() and ios_apply_render_profile() in CemuBridge.mm
// for what IS driven automatically: gx2drawdone_sync, vk_accurate_barriers, async_compile).

/// Flips both Wii U outputs vertically before they reach the screen. Wraps
/// CemuConfig's render_upside_down, which the renderer reads on the output blit path -
/// same "next frame, not next launch" timing as cemu_bridge_set_stretch_to_fill(). Exists
/// for panels or capture rigs that present the image inverted; almost nobody wants this on.
void cemu_bridge_set_render_upside_down(bool enabled);
bool cemu_bridge_render_upside_down(void);

/// Display gamma applied to the final image. Mirrors CemuConfig's own comment on
/// userDisplayGamma verbatim: 0 means sRGB (the display's own curve, untouched), any
/// value above 0 is a gamma exponent applied on top of it. The UI range is clamped to
/// 1.0-3.0 for any nonzero value - 1.0 is a no-op gamma (visually identical to sRGB but
/// taking the "gamma" code path instead of the "sRGB" one), 2.2 is the conventional
/// display gamma and the core's own compiled-in default, and 3.0 is already far enough
/// past normal viewing conditions that nothing past it is a real user choice rather than
/// a fat-fingered slider. A caller that wants sRGB back passes exactly 0; anything else
/// at or below 0 also collapses to 0 rather than being rejected, since "negative gamma"
/// has no meaning to reject it in favour of.
void cemu_bridge_set_display_gamma(float gamma);
float cemu_bridge_display_gamma(void);

/// Where the performance overlay is drawn, as CemuConfig.h's own ScreenPosition enum
/// value (0 = kDisabled, 1..6 walk the four corners plus top/bottom center - see
/// CemuConfig.h for the exact ordering). Out-of-range values are ignored, same defensive
/// shape as cemu_bridge_set_upscale_filter(). kDisabled turns the whole overlay off
/// regardless of which of the fps/cpu/ram switches below are individually on.
void cemu_bridge_set_overlay_position(int position);
int cemu_bridge_overlay_position(void);

/// The three overlay rows this app exposes, each a direct passthrough to the matching
/// field in CemuConfig's `overlay` struct (overlay.fps / overlay.cpu_usage /
/// overlay.ram_usage). text_color, text_scale, cpu_mode, drawcalls, cpu_per_core_usage,
/// vram_usage and debug are real fields on the same struct but are deliberately not
/// exposed here - out of scope for this pass, not forgotten.
void cemu_bridge_set_overlay_fps(bool enabled);
bool cemu_bridge_overlay_fps(void);
void cemu_bridge_set_overlay_cpu_usage(bool enabled);
bool cemu_bridge_overlay_cpu_usage(void);
void cemu_bridge_set_overlay_ram_usage(bool enabled);
bool cemu_bridge_overlay_ram_usage(void);

// MARK: - Audio
//
// Six of CemuConfig's audio fields, plain (not ConfigValue-wrapped) sint32/bool/enum
// members read directly by IAudioAPI and ax_out.cpp - see GetVolume()/GetChannels() in
// IAudioAPI.cpp and the enable checks around g_tvAudio/g_padAudio in ax_out.cpp. audio_delay,
// microphone_enabled, input_channels/input_volume and every *_device string are deliberately
// not exposed here: audio_delay and microphone_enabled are out of scope for this settings
// page, input_* belongs to the Wii Remote/mic input path rather than output, and device
// selection has no meaning on iOS, where CoreAudio owns the single active output route.
//
// AudioChannels crosses this plain-C boundary as a bare int, the same pattern
// cemu_bridge_set_graphics_api and cemu_bridge_set_upscale_filter already use for their own
// C++ enums: 0 = kMono, 1 = kStereo, 2 = kSurround (CemuConfig.h's `enum AudioChannels`).
// Out-of-range values are ignored, same as the upscale/downscale filters above.

/// Whether the TV screen's audio track plays at all. ax_out.cpp tears down or (re)creates
/// g_tvAudio's CoreAudio output the moment this flips, so - unlike most of the settings on
/// this page - it takes effect immediately, not on the next title launch.
void cemu_bridge_set_tv_audio_enabled(bool enabled);
bool cemu_bridge_tv_audio_enabled(void);

/// TV audio output level, 0-100. Clamped to that range in the setter, the same way
/// cemu_bridge_set_upscale_filter clamps its filter argument. Read by
/// IAudioAPI::GetVolume() and applied to g_tvAudio every audio callback, so a change is
/// audible on the very next buffer, not just the next launch.
void cemu_bridge_set_tv_volume(int volume);
int cemu_bridge_tv_volume(void);

/// TV channel layout: mono, stereo, or surround (see the encoding note above). Read by
/// IAudioAPI::GetChannels() and by ax_out.cpp's mixer setup, so it only takes effect the
/// next time the TV's audio device is (re)created - toggling TV audio off and back on, or
/// the next title launch.
void cemu_bridge_set_tv_channels(int channels);
int cemu_bridge_tv_channels(void);

/// Whether the GamePad screen's own audio track plays. Independent of the dual-screen
/// video routing in DisplayRouter.swift - this is a separate audio device the engine
/// mixes to (g_padAudio in ax_out.cpp) regardless of which physical display the GamePad's
/// picture is currently sent to, so it stays meaningful even with no second screen
/// attached. Same immediate-effect behaviour as TV audio enable, above.
void cemu_bridge_set_pad_audio_enabled(bool enabled);
bool cemu_bridge_pad_audio_enabled(void);

/// GamePad audio output level, 0-100. Same clamping and same "audible on the next buffer"
/// timing as TV volume above.
void cemu_bridge_set_pad_volume(int volume);
int cemu_bridge_pad_volume(void);

/// GamePad channel layout. Same encoding and same "takes effect when the pad audio device
/// is next (re)created" timing as TV channels above.
void cemu_bridge_set_pad_channels(int channels);
int cemu_bridge_pad_channels(void);

/// Which MoltenVK build the Vulkan renderer uses this launch: "1.4.3" (the default)
/// or "1.2.8". Chosen from the muffin.render.moltenVK setting when the engine
/// initializes; a loaded MoltenVK cannot be swapped inside a running process, so a change
/// applies on the next app launch. "" before initialize.
const char* cemu_bridge_active_moltenvk(void);

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

/// Freezes the running title's guest RAM to `path` (any slot file the caller wants -
/// naming/organizing save slots is entirely the UI's job). Pauses the title if it isn't
/// already paused, waits for it to genuinely go idle (not just "asked to pause" - see the
/// long comment in IOSSaveState.cpp for why that distinction matters), writes the file,
/// then resumes if this call was the one that paused it. Returns false, and never leaves
/// a partial file behind, if no title is running, the title never fully quiesces (a guest
/// thread stuck in a long call, or the GPU command queue never drains) within a few
/// seconds, or the file couldn't be written.
///
/// Deliberately narrow: this captures guest RAM only, not GPU/renderer state (textures,
/// shaders, command buffers). A texture or shader that changed since the save may show
/// briefly stale content right after a load, until the game's own next GX2 call refreshes
/// it - a visual glitch, not a correctness problem. See IOSSaveState.cpp for the full
/// reasoning.
bool cemu_bridge_save_state(const char* path);

/// Restores guest RAM from a file `cemu_bridge_save_state()` wrote, into the SAME
/// still-running title instance the save was taken from - not "the same game relaunched".
/// Refuses (returns false, touches no memory) unless the currently running title's ID,
/// active guest thread list, and mapped memory layout all match the save exactly; a
/// mismatch means the save doesn't line up with the live session and there is no safe way
/// to reconcile that. On success, forces the recompiler to drop any JIT-compiled code that
/// may now be stale (safe under the interpreter too - a no-op there).
bool cemu_bridge_load_state(const char* path);

/// Human-readable one-liner describing engine/bridge state, for display in the UI.
/// Never NULL. Points to static/thread-local storage; copy if you need to keep it.
const char* cemu_bridge_status_text(void);

/// Appends a timestamped-by-nothing (just ordered) line to Documents/CemuCrashLog.txt.
/// Written via a raw synchronous write() so it survives even an abrupt/uncatchable
/// process termination (e.g. a GPU driver panic) - call this at every meaningful
/// startup milestone from Swift so a crash's location can be narrowed down from the
/// surviving log alone.
void cemu_bridge_log_checkpoint(const char* message);

/// One line describing the machine: model identifier, iOS version, RAM, core layout,
/// how much memory iOS will let this app have, and the build. Stable for the process's
/// lifetime, owned by the bridge, safe to hold.
///
/// This exists so a report from a device nobody here owns is answerable. Every finding
/// on this port so far has depended on knowing the target hardware, and until now the
/// log never recorded it.
const char* cemu_bridge_device_report(void);

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

// ---------------------------------------------------------------------------
// Wii U console accounts and each one's Network Service.
//
// An "account" here is a real emulated Wii U console account - the account.dat files
// under mlc/usr/save/system/act/, the same ones desktop Cemu creates, lists and boots
// under (Cafe/Account/Account.h). Network Service is which online backend an account's
// traffic goes to: Nintendo's own (long since shut down for the Wii U), Pretendo
// (Pretendo Network, a community-run reimplementation - see pretendo.network), a
// hand-configured Custom service, or Offline. Neither concept is MuffinEMU- or
// MeloCafe-specific; this is desktop Cemu's own account/online system, which had no iOS
// surface at all before this.

/// One account per record, most-recently-refreshed order (Account::GetAccounts()).
/// Records separated by 0x1E, fields by 0x1F: persistentId (8 lowercase hex chars),
/// miiName, birthYear, birthMonth, birthDay, gender ("0" male, "1" female - Account's own
/// encoding), email, country (an NCrypto country index, see cemu_bridge_countries_list),
/// "1"/"0" for isValidOnline. miiName/email are free text an account owner could type on
/// a real Wii U or into this app's own create form, so IOSAccounts.cpp strips the two
/// separator characters out of them before they cross this boundary - the same shape
/// cemu_bridge_graphic_packs_list() uses for its own records/fields. Call
/// cemu_bridge_accounts_refresh() first if accounts may have changed on disk.
const char* cemu_bridge_accounts_list(void);

/// Rescans mlc/usr/save/system/act/ for account.dat files (Account::RefreshAccounts()).
/// Always leaves at least one account - the core creates and saves a "default" one the
/// moment the list would otherwise be empty, same as desktop Cemu.
void cemu_bridge_accounts_refresh(void);

/// True while a 12th account slot would still fit (Account::HasFreeAccountSlots()) - the
/// Wii U's own limit on how many accounts fit in usr/save/system/act/.
bool cemu_bridge_accounts_has_free_slot(void);

/// The persistent id a new account would get if the caller doesn't have one already
/// picked (Account::GetNextPersistentId()) - purely a suggestion; any id at or above
/// cemu_bridge_accounts_min_persistent_id() that isn't already in use is valid to pass to
/// cemu_bridge_account_create().
uint32_t cemu_bridge_accounts_next_persistent_id(void);

/// The lowest valid persistent id (Account::kMinPersistendId, 0x80000001). Account's own
/// CheckValid() rejects anything below it.
uint32_t cemu_bridge_accounts_min_persistent_id(void);

/// True while account controls should be disabled in the UI (CafeSystem::IsTitleRunning())
/// - changing the active account or its Network Service mid-title wouldn't take effect
/// until the next boot but would look like it did, so MeloCafe's own AccountSettingsView
/// locks the picker instead while a title runs, and this mirrors that.
bool cemu_bridge_accounts_locked(void);

/// Creates a real Account (Cafe/Account/Account.h) with every field the on-disk format
/// carries and saves it immediately: miiName (truncated to 10 UTF-16 units, Account's own
/// on-disk limit), birth date, gender, email and country. Returns true and leaves the
/// account list refreshed on success. Returns false without creating anything if
/// persistentId is already in use, below cemu_bridge_accounts_min_persistent_id(), no
/// slots remain, miiName is empty, or the underlying Account::Save() fails - the caller is
/// expected to have already checked the first three against cemu_bridge_accounts_list(),
/// cemu_bridge_accounts_min_persistent_id() and cemu_bridge_accounts_has_free_slot(), the
/// same order MeloCafe's own CreateAccountView validates in, so it can show a specific
/// reason instead of one generic failure.
bool cemu_bridge_account_create(uint32_t persistentId, const char* miiName, uint16_t birthYear,
    uint8_t birthMonth, uint8_t birthDay, int gender, const char* email, int country);

/// Deletes persistentId's account.dat and refreshes the account list. Refuses (returns
/// false, deletes nothing) if it's the only account: RefreshAccounts() always recreates a
/// "default" one the moment the list would be empty, so a delete that got past this check
/// would silently resurrect an account rather than actually removing the last one.
bool cemu_bridge_account_delete(uint32_t persistentId);

/// Field-by-field edits to an already-created account: each loads persistentId's
/// account.dat, changes the one field, saves, and refreshes the account list. Return false
/// if the account doesn't exist or the save fails.
bool cemu_bridge_account_set_mii_name(uint32_t persistentId, const char* miiName);
bool cemu_bridge_account_set_gender(uint32_t persistentId, int gender);
bool cemu_bridge_account_set_email(uint32_t persistentId, const char* email);
bool cemu_bridge_account_set_country(uint32_t persistentId, int country);
bool cemu_bridge_account_set_birthdate(uint32_t persistentId, uint16_t year, uint8_t month, uint8_t day);

/// The active account - CemuConfig's account.m_persistent_id, the same value
/// Account::GetCurrentAccount() boots a title under. Persisted immediately; unlike most
/// settings on this bridge there is no separate "next launch" delay because nothing reads
/// it until a title actually boots.
uint32_t cemu_bridge_active_account_persistent_id(void);
void cemu_bridge_set_active_account_persistent_id(uint32_t persistentId);

/// account.dat's own online-readiness check (Account::IsValidOnlineAccount(): does it have
/// a cached NNID/PNID login at all) - distinct from which Network Service is selected
/// below, which only decides WHERE an online-capable account connects.
bool cemu_bridge_account_is_online_valid(uint32_t persistentId);

/// Real Wii U country codes, for the same picker desktop Cemu's account editor uses
/// (NCrypto::GetCountryCount()/GetCountryAsString()). Records separated by 0x1E, fields
/// by 0x1F: code (decimal), name. Index 0's placeholder entry is included; NCrypto's
/// internal "NN" (unused) slots are skipped, same filter CemuConfigWrapper.mm's own
/// `countries` applies.
const char* cemu_bridge_countries_list(void);

typedef enum {
    CEMU_BRIDGE_NETWORK_OFFLINE  = 0,
    CEMU_BRIDGE_NETWORK_NINTENDO = 1,
    CEMU_BRIDGE_NETWORK_PRETENDO = 2,
    CEMU_BRIDGE_NETWORK_CUSTOM   = 3,
} CemuBridgeNetworkService;

/// Which Network Service persistentId connects through (CemuConfig::GetAccountNetworkService/
/// SetAccountSelectedService, keyed per-account exactly like the desktop config). Nintendo's
/// and Pretendo's server hostnames are already baked into the engine (NintendoURLs/
/// PretendoURLs in config/NetworkSettings.h) - selecting either needs no address from the
/// user. Custom is the one exception: the engine replays whatever account/ECS/NUS/etc URLs
/// are already in Documents/mlc/network_services.xml, which this bridge does not create or
/// edit - see cemu_bridge_custom_network_service_available(). Setting Custom while that file
/// doesn't exist is accepted here but the engine itself falls back to Offline at the point it
/// would actually connect (CemuConfig::GetAccountNetworkService() enforces this), so the UI
/// should disable Custom rather than let it look chosen and silently do nothing.
CemuBridgeNetworkService cemu_bridge_network_service(uint32_t persistentId);
void cemu_bridge_set_network_service(uint32_t persistentId, CemuBridgeNetworkService service);

/// Whether NetworkService::Custom is actually usable right now (NetworkConfig::XMLExists()).
/// Custom has no in-app configuration UI on any Cemu port, including this one: it only
/// works once the user has placed a hand-written network_services.xml in the mlc folder
/// themselves, so there is no server URL to prompt for here - see the type comment above.
bool cemu_bridge_custom_network_service_available(void);

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
