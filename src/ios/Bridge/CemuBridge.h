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
    CEMU_BRIDGE_NO_TITLE_TIK    = 4,   // encrypted game folder with no title.tik (and no matching title key in keys.txt)
    CEMU_BRIDGE_UNSUPPORTED     = 5,   // not a title and not a loadable executable
    CEMU_BRIDGE_BASE_NOT_FOUND  = 6,   // an update/DLC was launched without its base game
    CEMU_BRIDGE_BAD_TITLE_TMD   = 7,   // encrypted game folder whose title.tmd can't be read
    CEMU_BRIDGE_BAD_TITLE_TIK   = 8,   // encrypted game folder whose title.tik can't be read
    CEMU_BRIDGE_TITLE_KEY_INVALID = 9, // ticket read, but it (and keys.txt) don't decrypt the .app files
    CEMU_BRIDGE_MISSING_CONTENT = 10,  // a .app file listed in title.tmd is not in the folder
    CEMU_BRIDGE_CORE_NOT_BUILT  = 100, // real engine not linked into this build yet (never returned by current builds)
    CEMU_BRIDGE_BAD_ARG         = 101, // null/empty path etc.
} CemuBridgeStatus;

/// True only when the real Cemu C++ engine is compiled and linked into this build.
/// Swift uses this to decide whether to show the honest "not built yet" state.
bool cemu_bridge_core_available(void);

/// One-time engine initialization. `mlcPath` = MLC/NAND root inside the app sandbox.
/// Safe (no-op) when the core is not available.
void cemu_bridge_initialize(const char* mlcPath);

/// Boot whatever the user picked: an encrypted disc image (.wux/.wud/.iso), a Wii U
/// archive (.wua), a dumped game folder, an encrypted game folder (title.tmd, title.tik and .app files), or a standalone homebrew .rpx. Returns
/// CEMU_BRIDGE_OK when the title starts.
///
/// Real games are decrypted with the user's OWN console keys, read from keys.txt in the
/// app's Documents/mlc directory. Nothing is bundled, derived or worked around: with no
/// keys.txt the disc paths report CEMU_BRIDGE_NO_DISC_KEY and homebrew keeps working
/// exactly as before. The engine's key cache reads keys.txt once per app launch, so a
/// keys.txt imported mid-session is only used after the app is relaunched.
CemuBridgeStatus cemu_bridge_boot_title(const char* path);

/// Boot a title that is installed in the MLC (Documents/mlc/mlc01/{sys,usr}/title/...) by
/// its 64-bit title id, e.g. the Wii U Menu: 0005001010040000 (JPN), ...0100 (USA),
/// ...0200 (EUR). Returns CEMU_BRIDGE_UNABLE_TO_MOUNT with a status text when the title
/// is not installed. cemu_bridge_boot_title() also accepts "mlc-title:<16 hex digits>"
/// as its path and routes it here, so callers that only carry a path string (the library)
/// need no second entry point.
///
/// The Menu additionally needs the console's cafeLibs, the shared data under
/// sys/title/0005001b and (for online features) otp.bin/seeprom.bin. The engine logs which
/// of those are missing at launch; the Menu may still start without them.
CemuBridgeStatus cemu_bridge_boot_title_id(uint64_t titleId);

/// Boot a standalone .rpx and nothing else. Kept as the narrow homebrew entry point;
/// cemu_bridge_boot_title() is what the app calls, and it falls through to this same
/// engine path for an RPX/ELF.
/// Wraps CafeSystem::PrepareForegroundTitleFromStandaloneRPX + LaunchForegroundTitle.
CemuBridgeStatus cemu_bridge_boot_rpx(const char* rpxPath);

/// Re-reads the keys.txt FILE and returns how many 128-bit keys it holds (same acceptance
/// rule as the engine's parser). This does not reload the engine's key cache, which is
/// read once per app launch, so a newly imported file is counted immediately but only
/// used to decrypt after a relaunch. 0 means the file is absent, empty, or contains nothing usable. Cheap; safe to call
/// from the UI.
///
/// Returns -1, meaning "cannot answer", when the engine has not been initialized yet
/// (keys.txt is resolved against the user data path cemu_bridge_initialize() sets up) or
/// when the core is not in this build. That is deliberately distinct from 0, which is a
/// real answer about a real file.
int cemu_bridge_reload_and_count_keys(void);

/// Tells the core's key cache where keys.txt will be, so that a disc image (.wux/.wud) can be opened BEFORE
/// cemu_bridge_initialize() has run. The library scan (title id, region, name, box art), DLC/update inspection and
/// Decrypt to Files all open disc images at app start, and until the core's user data path exists the key cache has no
/// file to read, so every one of them failed with "no key in keys.txt decrypts this disc image" even with keys installed.
/// mlcPath is the same folder cemu_bridge_initialize() is given (Documents/mlc). The keys are read from
/// Documents/keys/keys.txt (the copy the user sees) or else Documents/mlc/keys.txt, read-only, nothing is created. Cheap
/// and safe to call repeatedly; ignored once the core is initialized.
void cemu_bridge_prepare_keys_before_init(const char* mlcPath);

/// Wires the real native Metal renderer to an actual on-screen
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

/// Which Wii U screen each registered surface shows. By default the TV surface shows the TV screen and the
/// GamePad surface the GamePad screen. `mainShowsGamePad` makes the TV surface show the GamePad screen instead
/// and `padShowsTV` makes the GamePad surface show the TV screen, so a second display can repeat the first.
/// Takes effect on the next frame; no surface is created or released.
void cemu_bridge_set_output_sources(bool mainShowsGamePad, bool padShowsTV);

/// True once the renderer has a layer behind the registered GamePad surface, i.e. frames can reach it.
/// Registered without this is a surface nothing draws to.
bool cemu_bridge_pad_layer_active(void);

/// Gives a registered GamePad surface its layer if it has none. A no-op otherwise.
void cemu_bridge_ensure_pad_layer(void);

/// Frames presented to the GamePad surface since launch, for judging whether it is being drawn to.
uint32_t cemu_bridge_pad_present_count(void);

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

/// True while a running, unpaused title has stopped producing frames for several seconds
/// even though the emulator itself is still alive (the game's audio and input carry on
/// while the picture is frozen or black). Set by a watchdog inside the bridge, which also
/// writes a one-off diagnostic snapshot to log.txt when it trips, and cleared as soon as
/// frames start arriving again. Safe to poll from the UI at any time.
bool cemu_bridge_video_stalled(void);

/// Why the picture is flagged by cemu_bridge_video_stalled(): 0 = not flagged, 1 = no new
/// frames for several seconds, 2 = the GPU reported an error (a page fault, for example) and
/// iOS is no longer running this app's GPU work, 3 = the screen's layer cannot get frame
/// buffers (out of memory for the screen), 4 = the app is nearly out of memory. Kind 2 does not clear until the title stops; 3
/// clears when drawables come back.
int cemu_bridge_video_stall_kind(void);

/// The four counters the engine's own progress heartbeat prints, readable on demand.
/// cemu_bridge_get_fps() rounds to whole frames per second, so a title running below one
/// frame per second reads 0, the same as one that stopped. These separate the two:
///
///   gx2FrameCount climbing, however slowly  -> running, just slow
///   gx2FrameCount pinned, gx2InitReached    -> stalled after handing over to GX2
///   gx2InitReached false, others climbing   -> still in OSScreen boot
///   nothing moving at all                   -> a real deadlock, not slowness
///
/// `gx2FramesPerSecond` is fractional and is the heartbeat's own measurement, so the
/// number on screen matches the log.
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

/// Decrypt-to-Files / Decrypt-to-WUA: takes a WUD/WUX (or an encrypted game folder: title.tmd, title.tik and .app files) the app
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

/// Packs several titles of one game (base, update, DLC) into a single .wua, given as
/// newline-separated paths (folders, NUS dumps, WUD/WUX; one title each). Shares the
/// decrypt progress / cancel calls below. Validates before writing: sources from
/// different games finish with result_status 9, the same title twice with 10. Writes to
/// destPath + ".part" and renames on success, so an existing destPath survives a failure.
/// Skips ._* and .DS_Store entries.
bool cemu_bridge_start_wua_build(const char* sourcePathsNewlineSeparated, const char* destPath);

/// Lists the title roots in a .wua as "titleIdHex16 version" lines into outLines.
/// Returns the number of titles, or -1 on a bad argument. 0 when it can't be opened.
int cemu_bridge_wua_list_titles(const char* wuaPath, char* outLines, size_t outSize);

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

/// Reads the 64-bit title ID from a title.tmd file without decrypting anything, so an
/// encrypted game folder can be told apart as base game (high word 00050000), update
/// (0005000E) or DLC (0005000C) even before its ticket or keys are checked. Returns
/// false if the file can't be read or isn't a valid title.tmd.
bool cemu_bridge_read_tmd_title_id(const char* tmdPath, uint64_t* outTitleId);

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
    CemuTitleBadTitleTmd = 6,
    CemuTitleBadTitleTik = 7,
    CemuTitleKeyInvalid = 8,
    CemuTitleMissingContentFile = 9,
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
/// into a thread-local buffer this function owns, valid until the next call to this same
/// function on the same thread - copy it (e.g. String(cString:)) before calling again, never free it.
const char* cemu_bridge_graphic_packs_list(void);

/// Enables or disables the pack at `index` (from the most recent
/// cemu_bridge_graphic_packs_list call) and persists the change immediately - it will
/// still be enabled/disabled the same way after the next refresh or app relaunch.
void cemu_bridge_graphic_pack_set_enabled(int index, bool enabled);

// ---------------------------------------------------------------------------
// Emulated toy-to-life devices: Skylanders Portal, Disney Infinity Base, LEGO
// Dimensions Toypad - USB peripherals some Wii U titles read via nsyshid
// (Cafe/OS/libs/nsyshid/Skylander.cpp, Infinity.cpp, Dimensions.cpp). The core already
// implements all three in full; nothing on this port had ever surfaced them. Each is
// attached to the emulated USB bus by nsyshid's own AttachDefaultBackends(), which runs
// when a title's nsyshid module loads and reads the matching enable flag below AT THAT
// MOMENT - so, like the other settings on this page, enabling/disabling one here takes
// effect on the next title launch, not one already running. Figure load/create/clear/
// move below act on the core's own always-live g_skyportal/g_infinitybase/
// g_dimensionstoypad state directly and work regardless of whether a title is running.
//
// No figure/NFC dump data ships with this: the figure list below is the core's own
// built-in (ID, variant, name) table for the real toys each game recognizes, and create
// writes fresh, empty save data for one of those - the same blank state a physical
// figure has before a game ever plays on it.

/// Which of the three peripherals a call below is about.
typedef enum {
    CEMU_BRIDGE_USB_DEVICE_SKYLANDERS = 0,
    CEMU_BRIDGE_USB_DEVICE_INFINITY   = 1,
    CEMU_BRIDGE_USB_DEVICE_DIMENSIONS = 2,
} CemuBridgeUSBDevice;

void cemu_bridge_set_emulate_skylander_portal(bool enabled);
bool cemu_bridge_emulate_skylander_portal(void);
void cemu_bridge_set_emulate_infinity_base(bool enabled);
bool cemu_bridge_emulate_infinity_base(void);
void cemu_bridge_set_emulate_dimensions_toypad(bool enabled);
bool cemu_bridge_emulate_dimensions_toypad(void);

/// Fixed slot count for `device`: 16 Skylanders, 9 Infinity (the play set plus two power
/// discs, then each of two players' own figure and two ability pieces), 7 Dimensions
/// toypad positions - nsyshid's own MAX_SKYLANDERS/MAX_FIGURES, and the fixed 7-position
/// toypad layout Dimensions.cpp implements.
int cemu_bridge_usb_device_slot_count(CemuBridgeUSBDevice device);

/// One record per slot, in slot order, separated by 0x1E - same convention as
/// cemu_bridge_graphic_packs_list(). An empty slot is an empty record (never omitted),
/// so record index always equals slot index. Thread-local storage owned by this call,
/// valid until the next call to this function on the same thread; copy before that.
const char* cemu_bridge_usb_device_slot_names(CemuBridgeUSBDevice device);

/// The core's own built-in figure table for `device`, restricted to the entries valid in
/// `slot` (Infinity's 9 positions each only accept certain figure ID ranges - see
/// InfinityUSB's own CreateFigure restriction, mirrored in IOSEmulatedDevices.cpp). One
/// record per figure, separated by 0x1E; each record is figureId\x1Fvariant\x1Fname
/// (fields separated by 0x1F). Metadata only - an ID/variant/name triple, never
/// copyrighted figure/save data. Same static-storage lifetime as
/// cemu_bridge_usb_device_slot_names() above.
const char* cemu_bridge_usb_device_figure_list(CemuBridgeUSBDevice device, int slot);

/// Loads the figure file at `path` (already written by create, below, or imported by the
/// user) into `slot`. Returns NULL on success; on failure, a static, human-readable
/// reason (file too small for this device, already loaded in another slot, portal has no
/// free slots) valid until the next call to the same function on the same thread - copy it before that.
const char* cemu_bridge_usb_device_load(CemuBridgeUSBDevice device, int slot, const char* path);

/// Tells the emulated device the figure in `slot` was lifted off - the game sees a real
/// removal - without touching its file on disk. NULL on success, a reason string (same
/// lifetime as above) on failure.
const char* cemu_bridge_usb_device_clear(CemuBridgeUSBDevice device, int slot);

/// Writes a brand-new figure save-data file at `path` (must not already exist) for
/// (figureId, variant); the caller then loads it into a slot with the call above. A
/// Dimensions figureId of 0 makes a blank vehicle/gadget tag for the game to write its
/// own data into, same as the desktop figure creator. NULL on success, a reason string
/// on failure (ID out of range for this device, or path already exists).
const char* cemu_bridge_usb_device_create(CemuBridgeUSBDevice device, uint32_t figureId, uint16_t variant, const char* path);

/// Dimensions-only: relocates the figure in toypad slot `fromSlot` to `toSlot` without a
/// file round-trip, preserving in-game state the way unload+reload through a file would
/// not (physical toypad position is meaningful to several Dimensions puzzles). NULL on
/// success, a reason string otherwise - always fails when either slot doesn't hold/admit
/// a Dimensions figure, since only the toypad has a physical position to move between.
const char* cemu_bridge_usb_device_move_dimensions(int fromSlot, int toSlot);

/// Taps an amiibo on the emulated NFC reader: the core's nnNfp_touchNfcTagFromFile (desktop
/// Cemu's "Load amiibo / NFC file"). `path` is a full NTAG215 dump (.bin/.nfc, 532 to 572
/// bytes). NULL on success; otherwise a short reason to show the player: no game has started
/// the NFC library yet, the file can't be read, or it isn't an amiibo dump. The amiibo
/// master keys are built into the core, so no key file is needed. The tag stays on the reader
/// for about 1.5 seconds, as a real tap does.
const char* cemu_bridge_touch_amiibo(const char* path);

/// How fast the emulated console believes time is passing, as a right-shift factor:
/// 3 = real time (1x), 4 = half (0.5x), 5 = quarter, 6 = an eighth, and so on
/// (ActiveSettings::SetTimerShiftFactor(), desktop Cemu's Timer Speed).
///
/// Under the interpreter the emulated CPU is far slower than the real console while the
/// guest clock follows the host's wall clock, so periodic deadlines (alarms, audio
/// callbacks, thread quanta) can be overdue faster than they are serviced and the title
/// appears to hang. Raising the shift slows the guest clock so it runs in slow motion
/// instead. It can be changed while a title runs; time still only moves forward. It
/// compensates for a slow emulator and does not make it faster.
void cemu_bridge_set_timebase_shift(int shift);

/// The shift currently in effect. See above for the scale.
int cemu_bridge_get_timebase_shift(void);

/// Turns the automatic clock ladder on or off.
///
/// While a title boots on the interpreter and has not reached GX2Init, the ladder steps
/// the guest clock down one notch every twelve seconds (floor 1/64). Once the title is
/// advancing, the clock is restored to its starting value. Enabled unless the user has
/// chosen a value by hand, which turns it off; never runs under the recompiler.
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
/// Each one isolates a subsystem so a problem can be narrowed down without a rebuild.
void cemu_bridge_set_recompiler_enabled(bool enabled);
bool cemu_bridge_recompiler_enabled(void);

/// Speed first, or accuracy first. By default MuffinEMU runs one emulated CPU core (the
/// recompiler when a JIT enabler is attached, otherwise the interpreter; multi-core is
/// opt-in through cemu_bridge_set_multicore_enabled), builds shaders in the background,
/// and skips the work that only buys accuracy - accurate Vulkan barriers and GX2DrawDone
/// synchronisation. On, this takes Cemu's most compatible choice for each instead: one
/// emulated CPU core, every shader built before the frame that needs it, accurate
/// barriers and draw-done sync. For the titles that glitch, desync or crash on
/// the fast path. Read when a title starts.
void cemu_bridge_set_favour_accuracy(bool enabled);

/// Speed before picture quality, one step past the default speed path. On: shaders are built
/// without Cemu's strict 0*anything=0 multiply (fewer GPU instructions, possible lighting or
/// shadow glitches), shaders always compile in the background (no stalls, objects can pop in
/// briefly), and the per-draw crash breadcrumbs are skipped (less detail in a crash report).
/// The Swift side also caps the presented resolution at Balanced and uses linear scaling.
/// Favour accuracy wins when both are on, including a per-game accuracy override. Read when a
/// title starts.
void cemu_bridge_set_favour_performance(bool enabled);
bool cemu_bridge_favour_performance(void);

/// "Full speed renders!": everything for smooth, complete frames at the game's own Wii U frame
/// rate. On, the GPU thread runs at the highest scheduling class, each frame is presented no
/// sooner than the game's own frame interval (steady pacing, never faster than the console), and
/// per-draw crash breadcrumbs are skipped. `shaderMode` decides the first time a never-seen shader
/// is needed: 0 waits for it (a short hitch, never a missing or flickering object), 1 keeps going
/// (never a hitch, the object can be missing for a moment). This choice wins over Favour accuracy,
/// Favour performance and Compile shaders in the background. Read when a title starts.
void cemu_bridge_set_full_speed_renders(bool enabled, int shaderMode);
bool cemu_bridge_full_speed_renders(void);

/// Best-effort real device temperature in Celsius, or NaN when it cannot be read.
///
/// iOS publishes NO device temperature to apps - ProcessInfo.thermalState's four levels
/// are the entire supported surface - so this reaches the battery sensor through IOKit,
/// a private framework, resolved by dlsym and written to fail cleanly. Expect NaN on a
/// normally sideloaded install, where the sandbox blocks it; it has a real chance of
/// working under TrollStore or a jailbreak.
///
/// It is the BATTERY's temperature, not the SoC's, so it lags the chip and reads low
/// under a short burst. Never estimated and never derived from thermalState: callers get
/// a number that was actually read, or NaN.
double cemu_bridge_device_temperature_celsius(void);


/// Thermal governor: microseconds each emulated core sleeps at its reschedule point.
///
/// 0 (the default, and the value whenever the device is not hot) means no sleep and the
/// core loop is unchanged. Unlike cemu_bridge_set_low_power_mode(), this takes
/// effect on a RUNNING title - it is the CPU-side lever for a device overheating right
/// now, where core count cannot move until the next launch.
///
/// Costs emulation speed in proportion to the sleep. Applied only while iOS reports
/// serious or critical thermal pressure, at which point iOS is already throttling the
/// hardware, and set back to 0 the moment it cools. See ThermalMonitor.swift.
void cemu_bridge_set_thermal_throttle_micros(uint32_t micros);

/// Run the three emulated Espresso cores on three host threads instead of one.
///
/// Off by default. Three host threads draw about three times the power of one, and a part
/// that runs out of thermal headroom heats up and has its clocks taken back, which can
/// leave it slower than one core. Auto only picks three on a device that qualifies from
/// its own performance-core count, memory tier and thermal state (ios_decide_core_count).
void cemu_bridge_set_multicore_enabled(bool enabled);

/// How many host threads run the three emulated cores: 0 = Auto, 1 = one core, 2 = three
/// cores (experimental). Auto decides per title at launch from the title's game profile, the
/// device (performance-core count) and its thermal state, and leans to one core; see
/// ios_decide_core_count() in CemuBridge.mm. The choice made, and why, is written to the
/// launch log as "CPU cores: ...". Read when a title starts.
void cemu_bridge_set_cpu_core_mode(int mode);

/// Tells Auto that an earlier three-core run of the title about to launch crashed or hung, so
/// it stays on one core. Set before boot for every launch; ignored by an explicit core choice.
void cemu_bridge_set_cpu_auto_demoted(bool demoted);

/// Host threads running the emulated cores for the current/last boot (1 or 3), and whether Auto
/// (rather than an explicit choice) is what picked three.
int cemu_bridge_cpu_cores_running(void);
bool cemu_bridge_cpu_auto_picked_multicore(void);

/// Per-draw breadcrumb recording in the Metal renderer (a record of recent draws kept to
/// explain a GPU fault). On by default; off saves a little CPU per draw.
void cemu_bridge_set_draw_breadcrumbs(bool enabled);

/// The most recent performance line (the same text that is logged every ~5 s while a title
/// runs), or an empty string before the first one. Copy it; the pointer is per-thread.
const char* cemu_bridge_perf_line(void);

/// "iPad14,3, Apple M1 GPU, 4 performance + 4 efficiency cores, 7500 MB RAM": what the
/// performance log and reports use to tell devices apart.
const char* cemu_bridge_device_summary(void);

/// One-core mode: run one emulated CPU core and nothing else changes. Separate from
/// cemu_bridge_set_favour_accuracy(), which also forces synchronous shader compilation
/// and accurate barriers (more work, the wrong lever for a device that is already hot).
/// Read when a title starts - the core count cannot change under a running title.
void cemu_bridge_set_low_power_mode(bool enabled);
bool cemu_bridge_low_power_mode(void);
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


/// Stores Cemu's `vsync` config value. It has no visible effect on iOS and Settings no longer
/// offers it: iOS always syncs presents to the display (CAMetalLayer.displaySyncEnabled is
/// macOS-only, and nothing on this port sets it), so the Metal renderer never reads this value,
/// and the Vulkan renderer's iOS path (SwapchainInfoVk::ChoosePresentMode) uses FIFO whatever
/// it says. Kept so the saved "muffin.render.vsync" key and the audit harness still work.
void cemu_bridge_set_vsync_enabled(bool enabled);

bool cemu_bridge_vsync_enabled(void);

/// Frame stretching. Drives the engine's own fullscreen_scaling, the same config value
/// desktop's "Fullscreen scaling" radio box sets - kStretch fills the window,
/// kKeepAspectRatio letterboxes 1280x720 inside it. Re-read every time the output blit
/// is sized, so unlike vsync above it takes effect on the next frame, not the next launch.
///
/// Swift only sees what this header declares, and the CI symbol check compares it against
/// the exported functions, so a definition in CemuBridge.mm needs a declaration here.
void cemu_bridge_set_stretch_to_fill(bool enabled);

/// Which renderer the next title uses: 2 = Metal (the native path and the default), 1 =
/// Vulkan through MoltenVK. Anything else falls back to Metal. Read by CemuRun() when a
/// title starts, so it cannot change the renderer of a running title.
void cemu_bridge_set_graphics_api(int api);
int cemu_bridge_graphics_api(void);

/// A one-line note for the player about how the last launch differed from what they asked for, for example
/// Vulkan not starting so Metal was used. Empty when there is nothing to say; reading it clears it. The string
/// is only valid until the next call on the same thread.
const char* cemu_bridge_take_launch_notice(void);

/// Filters for scaling the 1280x720 (or GamePad 854x480) image to the screen: 0 linear,
/// 1 bicubic, 2 bicubic hermite, 3 nearest neighbour. Upscale defaults to bicubic,
/// downscale to linear - the core's own defaults. Out-of-range values are ignored.
void cemu_bridge_set_upscale_filter(int filter);
void cemu_bridge_set_downscale_filter(int filter);

/// Metal-only: lets eligible textures read the pixel already sitting in the framebuffer
/// from within the same fragment shader instead of a separate blend pass -
/// MetalRenderer::Initialize() gates m_supportsFramebufferFetch on this AND the GPU
/// reporting Apple GPU family 2, a floor every device this app targets clears, so unlike
/// force_mesh_shaders in CemuConfig.h (gated on an Intel-only code path with no Intel GPU
/// on iOS, and deliberately not exposed here for that reason) this one is a real, live
/// switch on this platform. On by default, matching the core's own compiled-in default.
/// Read when the Metal layer initializes, so - like the renderer picker itself - it takes
/// effect on the next launch. Vulkan (MoltenVK) never reads this field.
void cemu_bridge_set_framebuffer_fetch(bool enabled);
bool cemu_bridge_framebuffer_fetch(void);

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

/// A gamma stage upstream of Display Gamma, not a duplicate of it. RendererOuputShader.cpp
/// reads both as separate shader inputs (targetGamma and displayGamma): targetGamma comes
/// from here plus whatever gamma the game itself requested via GX2SetTVGamma/GX2SetDRCGamma
/// (LatteGPUState.tvGamma/drcGamma, 0 if the game never asked), while displayGamma is
/// cemu_bridge_set_display_gamma()'s value applied on top of that result. With this off, the
/// game's own request still passes through added to overrideGammaValue; on, ActiveSettings::
/// GetTVGamma()/GetDRCGamma() drop the game's request entirely and use only overrideGammaValue.
/// Mirrors CemuConfig's own graphic.xml load-time clamp: a negative overrideGammaValue is
/// rejected back to 2.2 rather than clamped, since a caller sending negative meant "reset",
/// not "as low as possible" - unlike display gamma's 0-means-sRGB special case, negative has
/// no meaning at all here to preserve.
void cemu_bridge_set_override_app_gamma(bool enabled);
bool cemu_bridge_override_app_gamma(void);
void cemu_bridge_set_override_gamma_value(float gamma);
float cemu_bridge_override_gamma_value(void);

/// Where the performance overlay is drawn, as CemuConfig.h's own ScreenPosition enum
/// value (0 = kDisabled, 1..6 walk the four corners plus top/bottom center - see
/// CemuConfig.h for the exact ordering). Out-of-range values are ignored, same defensive
/// shape as cemu_bridge_set_upscale_filter(). kDisabled turns the whole overlay off
/// regardless of which of the toggles below are individually on.
void cemu_bridge_set_overlay_position(int position);
int cemu_bridge_overlay_position(void);

/// Every field on CemuConfig's `overlay` struct, each a direct passthrough (this is the
/// full set - nothing on that struct is left unexposed after this pass). fps / cpu_usage /
/// cpu_per_core_usage / ram_usage / vram_usage / drawcalls / debug are read by
/// LatteOverlay_renderOverlay() to decide which lines it draws; cpu_mode round-trips to
/// the config file like the rest but the renderer does not currently act on it (same as
/// upstream) - exposed anyway because a real, persisted field deserves a real control
/// rather than a silent gap in the settings page.
///
/// text_color is packed 0xAARRGGBB (ImGui::ColorConvertU32ToFloat4 reads it that way);
/// text_scale is a percentage of the base 14pt overlay font, clamped in the setter to the
/// 50-200 range this app's own slider offers - see cemu_bridge_set_display_gamma()'s doc
/// comment for why a bridge clamp mirrors a settings page's own range.
void cemu_bridge_set_overlay_fps(bool enabled);
bool cemu_bridge_overlay_fps(void);
void cemu_bridge_set_overlay_cpu_usage(bool enabled);
bool cemu_bridge_overlay_cpu_usage(void);
void cemu_bridge_set_overlay_ram_usage(bool enabled);
bool cemu_bridge_overlay_ram_usage(void);
void cemu_bridge_set_overlay_text_color(uint32_t color);
uint32_t cemu_bridge_overlay_text_color(void);
void cemu_bridge_set_overlay_text_scale(int scale);
int cemu_bridge_overlay_text_scale(void);
void cemu_bridge_set_overlay_cpu_mode(bool enabled);
bool cemu_bridge_overlay_cpu_mode(void);
void cemu_bridge_set_overlay_drawcalls(bool enabled);
bool cemu_bridge_overlay_drawcalls(void);
void cemu_bridge_set_overlay_cpu_per_core_usage(bool enabled);
bool cemu_bridge_overlay_cpu_per_core_usage(void);
void cemu_bridge_set_overlay_vram_usage(bool enabled);
bool cemu_bridge_overlay_vram_usage(void);
void cemu_bridge_set_overlay_debug(bool enabled);
bool cemu_bridge_overlay_debug(void);

/// CemuConfig's `notification` struct - a second, independent on-screen draw
/// (LatteOverlay_RenderNotifications()) covering controller/friends/shader-compile
/// toasts rather than the performance readout above. Same ScreenPosition encoding as
/// the overlay, same 0xAARRGGBB text_color packing, same 50-200 text_scale range and
/// clamp - it is a sibling of the overlay struct, not a UI-only concept, so it gets the
/// same bridge shape rather than something bespoke.
void cemu_bridge_set_notification_position(int position);
int cemu_bridge_notification_position(void);
void cemu_bridge_set_notification_text_color(uint32_t color);
uint32_t cemu_bridge_notification_text_color(void);
void cemu_bridge_set_notification_text_scale(int scale);
int cemu_bridge_notification_text_scale(void);
void cemu_bridge_set_notification_controller_profiles(bool enabled);
bool cemu_bridge_notification_controller_profiles(void);
void cemu_bridge_set_notification_controller_battery(bool enabled);
bool cemu_bridge_notification_controller_battery(void);
void cemu_bridge_set_notification_shader_compiling(bool enabled);
bool cemu_bridge_notification_shader_compiling(void);
void cemu_bridge_set_notification_friends(bool enabled);
bool cemu_bridge_notification_friends(void);

/// Native overlay. By default the core draws the overlay and notifications above with ImGui
/// into the game's render surface, whose reduced backing scale makes the text soft. When this
/// is on the core stops drawing them and the app draws the same text itself, at full screen
/// resolution, from cemu_bridge_native_overlay_text(). Off (the default) is the old ImGui
/// path. Turn it off again whenever nothing is polling the text.
void cemu_bridge_set_native_overlay(bool enabled);
bool cemu_bridge_native_overlay(void);

/// The overlay text the core would have drawn, built from the same settings and timing. One
/// string: the stats block's lines separated by '\n', then one record separator (0x1E) and
/// each notification after it, also separated by 0x1E (a notification's own lines are
/// separated by '\n'). The stats block may be empty. Empty string when the native overlay is
/// off. Polling consumes the one-shot shader/pipeline counters, so only one caller should
/// poll. Copy it; the pointer is per-thread. Call from the main thread.
const char* cemu_bridge_native_overlay_text(void);

// MARK: - Audio
//
// Eight of CemuConfig's audio fields, plain (not ConfigValue-wrapped) sint32/bool/enum
// members read directly by IAudioAPI, ax_out.cpp and mic.cpp - see GetVolume()/GetChannels()
// in IAudioAPI.cpp, the enable checks around g_tvAudio/g_padAudio in ax_out.cpp, and
// mic_isConnected()/MICInit() in mic.cpp. audio_delay, input_channels and every *_device
// string are deliberately not exposed here: audio_delay is out of scope for this settings
// page, input_channels has no effect even in desktop Cemu (GeneralSettings2.cpp forces it to
// kMono regardless of UI selection - see the commented-out assignment there), and device
// selection has no meaning on iOS, where CoreAudio owns the single active output route -
// including for input: mic.cpp's `#if BOOST_OS_IOS` path always uses IOSAudioInputAPI's one
// device, a real AVAudioSession/AudioUnit-backed mic capture path (iOSAudioInputAPI.mm), not
// a stub, so microphone_enabled and input_volume below are genuinely functional on this fork.
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

/// Whether a title's request to open the GamePad microphone (MICInit, mic.cpp) is honoured.
/// Gates mic_isConnected() before anything else about the mic - off means a title's MICInit
/// call fails with NOT_CONNECTED and IOSAudioInputAPI is never even constructed, the same way
/// a real console with no microphone attached would behave; on, the first title that calls
/// MICInit opens the real device and holds it for the rest of the session (mic.cpp caches
/// g_inputAudio once created). Defaults to false, matching CemuConfig.h - the mic usage
/// string in project.yml exists for the moment a title actually asks, not for this switch.
void cemu_bridge_set_microphone_enabled(bool enabled);
bool cemu_bridge_microphone_enabled(void);

/// Microphone input level, 0-100, clamped the same way the output volumes above are. Applied
/// once via IOSAudioInputAPI's SetVolume() when the mic device is first created (MICInit),
/// so - unlike the TV/GamePad volumes, which apply on the next audio buffer - a change here
/// only takes effect the next time a title opens the mic (next title launch, in practice).
void cemu_bridge_set_input_volume(int volume);
int cemu_bridge_input_volume(void);

/// Simulated blow into the GamePad microphone (the in-game "Blow" button). While on, the
/// game's mic buffer is fed synthetic wind noise instead of microphone audio: no real
/// microphone and no permission involved, works whether or not the real-mic setting above is
/// on. Safe to call from any thread at any time, including with no title running. The core
/// clears it when the title that owned the mic goes away, so read it back with
/// cemu_bridge_mic_blow() rather than assuming your last write stuck.
void cemu_bridge_set_mic_blow(bool blowing);
bool cemu_bridge_mic_blow(void);

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

/// Importing a learned-shader or pipeline cache file for one title (per-game options screen). Both read the
/// file with the engine's own cache reader (FileCache), so desktop Cemu files (V3, or the older V2 header) and
/// MuffinEMU files (including ones with the entry checksums) are handled alike. Desktop shader entries are
/// converted by the loader the first time the game starts; nothing is converted here.
///
/// Which kind of file it is and which game it belongs to come from the version stamp in the file header, never
/// from the file name. Only call these with no title running.
typedef enum {
    CEMU_CACHE_FILE_UNKNOWN  = 0, // not a cache this title can use; see the status
    CEMU_CACHE_FILE_SHADERS  = 1, // learned shaders (<titleid>_mtlshaders.bin / <titleid>_shaders.bin)
    CEMU_CACHE_FILE_PIPELINE = 2, // shader pipelines (<titleid>_mtlpipeline.bin / <titleid>_vkpipeline.bin)
} CemuCacheFileKind;

typedef enum {
    CEMU_CACHE_STATUS_OK            = 0,
    CEMU_CACHE_STATUS_NOT_A_CACHE   = 1, // not a FileCache file, or its header/file table is damaged
    CEMU_CACHE_STATUS_OTHER_GAME    = 2, // version stamp belongs to a different title
    CEMU_CACHE_STATUS_OLD_FORMAT    = 3, // learned shaders from desktop Cemu before 1.16 (keyed by the RPX hash): can't be converted
    CEMU_CACHE_STATUS_NOTHING_USABLE = 4, // a cache for this title, but none of its entries is usable
    CEMU_CACHE_STATUS_TITLE_RUNNING = 5,
} CemuCacheStatus;

typedef struct {
    int kind;               // CemuCacheFileKind
    int status;             // CemuCacheStatus
    unsigned int stamp;     // the file's version stamp
    int entryCount;         // entries in the file
    int usableCount;        // entries that look like valid shader entries (learned shaders only; pipelines: = entryCount)
    int damagedCount;       // entries that failed their checksum and were dropped from the copy being read
} CemuCacheFileInfo;

/// Looks at `path` without changing anything and says what it is and whether `titleId` can use it.
void cemu_bridge_cache_file_inspect(unsigned long long titleId, const char* path, CemuCacheFileInfo* outInfo);

/// What a version stamp stands for when it isn't the title's own: returns the CemuCacheFileKind that `stamp` is
/// for `titleId` (SHADERS or PIPELINE), or UNKNOWN. Lets the app name the game a wrong file belongs to by trying
/// the stamp against each title in the library.
int cemu_bridge_cache_stamp_kind(unsigned long long titleId, unsigned int stamp);

/// Merges the entries of `path` into the title's cache file. Entries already in the title's file win; the file
/// itself is never replaced. Learned shaders go to `<titleid>_mtlshaders.bin` when `renderer` is 2 (Metal) or
/// `<titleid>_shaders.bin` when it is 1 (Vulkan). A pipeline cache goes to `<titleid>_vkpipeline.bin` when
/// `pipelineIsVulkan`, else `<titleid>_mtlpipeline.bin`, whatever the current renderer is. Returns a
/// CemuCacheStatus (the file is checked again here), or a negative number if the title's own file could not be
/// opened or has another title's stamp (nothing is changed then). Counts may be null.
int cemu_bridge_cache_file_import(unsigned long long titleId, const char* path, int kind, int renderer, bool pipelineIsVulkan,
                                  int* outAdded, int* outAlreadyThere, int* outSkipped);


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

/// True when starting another title in this process is not safe and the app has to be closed and reopened first. Set only
/// when a real problem was found while stopping a title (the GPU stopped running this app's work, or the post-stop check
/// found emulator state that could not be reset), never by a normal stop. Stays true until the app restarts.
bool cemu_bridge_clean_start_required(void);

/// Called on the title-switch thread when the Wii U Menu switches to a game, after the Menu has been shut down and before the
/// game is prepared. The app applies that title's per-game settings here, the same ones a library launch pushes before boot.
typedef void (*CemuTitleSwitchCallback)(uint64_t titleId);
void cemu_bridge_set_title_switch_callback(CemuTitleSwitchCallback callback);

/// What a physical controller's buttons mean to the app's own menus rather than to the game.
/// HOME is reported whether or not menu capture is on; the other four only while it is.
typedef enum {
    CEMU_BRIDGE_MENU_HOME    = 0, // the controller's HOME / guide button went down
    CEMU_BRIDGE_MENU_UP      = 1, // d-pad up, or the left stick pushed up
    CEMU_BRIDGE_MENU_DOWN    = 2,
    CEMU_BRIDGE_MENU_CONFIRM = 3, // A
    CEMU_BRIDGE_MENU_BACK    = 4, // B
} CemuBridgeMenuEvent;

/// Called on the main thread, once per press, for the events above.
typedef void (*CemuMenuInputCallback)(CemuBridgeMenuEvent event);
void cemu_bridge_set_menu_input_callback(CemuMenuInputCallback callback);

/// While on, the bound physical controller drives the app's menu instead of the game: the game sees none of its
/// buttons, sticks or triggers, and the menu events above are delivered. Turning it off hands the controller back to
/// the game, and anything still held at that moment stays ignored until it is let go, so the press that chose a menu
/// row is never also a press in the game. Touch input is unaffected. Call from the main thread.
void cemu_bridge_set_menu_capture(bool capture);
/// A one-line reason for the log and the message, valid until the next call on the same thread.
const char* cemu_bridge_clean_start_reason(void);

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
/// Every launch of a title has its own session token, stored in the save file; a file from
/// another launch is refused before the game is even paused (see
/// `cemu_bridge_save_state_inspect()` and IOSSaveState.cpp for why it cannot be made to
/// work across launches).
/// Refuses (returns false, touches no memory) unless the currently running title's ID,
/// active guest thread list, and mapped memory layout all match the save exactly; a
/// mismatch means the save doesn't line up with the live session and there is no safe way
/// to reconcile that. On success, forces the recompiler to drop any JIT-compiled code that
/// may now be stale (safe under the interpreter too - a no-op there).
bool cemu_bridge_load_state(const char* path);

/// Why the last `cemu_bridge_save_state()` or `cemu_bridge_load_state()` returned false: a sentence meant to be shown to the
/// player as it is, valid until the next call on the same thread. Empty after a success. Read it on the thread that made
/// the call (the save queue), right after it returned: the text belongs to the most recent save or load.
const char* cemu_bridge_save_state_last_error(void);

/// The same failure as a code, for the UI to branch on. 0 none, 1 no path, 2 no game running, 3 couldn't pause, 4 a CPU
/// core never went idle (a long loading call), 5 the GPU never drained, 6 not enough storage, 7 couldn't create the file,
/// 8 write failed, 9 file missing, 10 not a save state, 11 older format, 12 a different game, 13 from an earlier session,
/// 14 the game's thread set changed since the save, 15 its memory layout changed, 16 file damaged, 17 damaged mid-restore
/// (the game should be restarted).
int cemu_bridge_save_state_last_error_code(void);

/// What a slot file is, judged from its header alone (nothing is paused, no memory is read). 0 unreadable or not a save
/// state, 1 loadable now (taken in this launch of the running game), 2 from an earlier session (the game or the app was
/// relaunched since: kept on disk but can't be loaded), 3 saved by a different game, 4 an older file format.
int cemu_bridge_save_state_inspect(const char* path);

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
/// A press is latched: a release arriving before the title's next VPADRead has seen
/// the press (or within 50ms of it) is deferred until both have happened, so a quick tap
/// is never lost between two reads. Repeated "down" calls for a held button are no-ops.
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
// hand-configured Custom service, or Offline. Neither concept is MuffinEMU-specific; this is desktop Cemu's own account/online system, which had no iOS
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
/// until the next boot but would look like it did, so the account screen
/// locks the picker while a title runs.
bool cemu_bridge_accounts_locked(void);

/// Creates a real Account (Cafe/Account/Account.h) with every field the on-disk format
/// carries and saves it immediately: miiName (truncated to 10 UTF-16 units, Account's own
/// on-disk limit), birth date, gender, email and country. Returns true and leaves the
/// account list refreshed on success. Returns false without creating anything if
/// persistentId is already in use, below cemu_bridge_accounts_min_persistent_id(), no
/// slots remain, miiName is empty, or the underlying Account::Save() fails - the caller is
/// expected to have already checked the first three against cemu_bridge_accounts_list(),
/// cemu_bridge_accounts_min_persistent_id() and cemu_bridge_accounts_has_free_slot(), the
/// same order a UI would validate in, so it can show a specific
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

/// Why persistentId can't play online, from Account::GetOnlineAccountError():
/// 0 none (valid), 1 no account ID, 2 password not cached, 3 password cache empty,
/// 4 no principal ID, -1 no such account. Call cemu_bridge_accounts_refresh() first
/// if the account.dat may have just changed.
int cemu_bridge_account_online_error(uint32_t persistentId);

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
/// are already in Documents/mlc/network_services.xml, which the app writes
/// (CustomServers.swift) - see cemu_bridge_custom_network_service_available(). Setting Custom while that file
/// doesn't exist is accepted here but the engine itself falls back to Offline at the point it
/// would actually connect (CemuConfig::GetAccountNetworkService() enforces this), so the UI
/// should disable Custom rather than let it look chosen and silently do nothing.
CemuBridgeNetworkService cemu_bridge_network_service(uint32_t persistentId);
void cemu_bridge_set_network_service(uint32_t persistentId, CemuBridgeNetworkService service);

/// Whether NetworkService::Custom is actually usable right now (NetworkConfig::XMLExists()).
/// True only for a file that parses and lists at least one http(s) address. The app's
/// Network Service > Custom servers section (CustomServers.swift) writes and swaps that file.
bool cemu_bridge_custom_network_service_available(void);

/// Reads Documents/mlc/network_services.xml again after the app replaced or removed it, and
/// returns whether it's now a usable Custom Network Service. Without this the engine keeps
/// the file as it was when the app started.
bool cemu_bridge_reload_custom_network_service(void);

/// Whether the file at path is a usable network_services.xml (parses, has <content> and at
/// least one http(s) address under <urls>). Doesn't touch the active file.
bool cemu_bridge_network_services_xml_is_valid(const char* path);

/// What network the device is on, as reported by the app's path monitor.
typedef enum {
    CEMU_BRIDGE_DEVICE_NETWORK_OFFLINE  = 0,
    CEMU_BRIDGE_DEVICE_NETWORK_WIFI     = 1,
    CEMU_BRIDGE_DEVICE_NETWORK_CELLULAR = 2,
    /// Wired or any other usable path (Ethernet adapter, hotspot link, ...).
    CEMU_BRIDGE_DEVICE_NETWORK_OTHER    = 3,
} CemuBridgeDeviceNetwork;

/// Tells the core whether the device has a network path. The emulated Wii U's nn_ac library
/// reports connected only while this is true and online play is set up. One relaxed atomic
/// store; safe from any thread, before or during a game.
void cemu_bridge_set_device_network(CemuBridgeDeviceNetwork kind);

/// Whether the emulated console currently appears connected: follows the device only.
bool cemu_bridge_console_appears_connected(void);

/// Whether online play is set up (valid online account on Pretendo or Custom, with the online files).
bool cemu_bridge_online_play_enabled(void);

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

/// How many GamePad BUTTONS currently have a binding. -1 when no GamePad is wired at all,
/// which is a different problem from one that is wired with zero bindings.
///
/// Buttons only, deliberately. Axes reach the emulated controller without consulting the
/// mapping table, so a controller with sticks bound and buttons unbound - the exact state
/// that makes every on-screen button dead while the joysticks still respond - would report
/// a healthy number if axis mappings were counted too.
/// One line describing how much memory iOS is letting this process have, and how much of
/// it the recompiler actually got.
///
/// Reports what was obtained rather than which entitlements were requested. An entitlement
/// is a request - whether the system honoured it shows up only in the numbers, and a
/// readout saying "increased memory limit: on" beside a 64 MB JIT arena would be a
/// reassuring lie. The arena size is the number that says whether the recompiler got room.
/// The returned pointer is into a thread-local buffer, valid until the next call to this
/// function on the same thread; copy it before calling again.
const char* cemu_bridge_memory_headroom_summary(void);

/// Record the game's TV audio to an M4A (AAC, 256 kbps, stereo) file at `path`. The folder must
/// exist. Returns false when a recording is already on. The samples are copied from the TV
/// device's feed on the audio thread into a lock-free ring; a background thread encodes them.
bool cemu_bridge_audio_record_start(const char* path);

/// Stops the recording and finishes the file. Blocks until the encoder has closed it, so call it
/// off the main thread. Does nothing when no recording is on.
void cemu_bridge_audio_record_stop(void);

bool cemu_bridge_audio_record_active(void);

/// Seconds of audio written to the current (or last) recording.
double cemu_bridge_audio_record_seconds(void);

int cemu_bridge_input_button_mapping_count(void);

/// Which controller profile the GamePad is on ("default" when none was loaded). Owned by
/// the bridge and valid until the next call on the same thread.
const char* cemu_bridge_input_profile_name(void);

/// Delete the GamePad's persisted profile and re-apply the default mappings. Returns true
/// when the GamePad ends up with at least one button binding.
///
/// Deletes the FILE, not just the in-memory controller: a reset that only cleared memory
/// would be undone by the same bad profile at the next launch, which is precisely the
/// failure this exists to cure.
bool cemu_bridge_reset_controller_bindings(void);


/// Stops the core compositing a Wii U screen that no output is showing. The game, GX2 swaps and
/// vsync are untouched; only the host copy to the hidden screen's layer is skipped. Off by default.
void cemu_bridge_set_skip_hidden_screen(bool tv, bool pad);


#ifdef __cplusplus
} // extern "C"
#endif

#endif // CEMU_BRIDGE_H
