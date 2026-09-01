//
//  IOSLiveLog.h
//  A third log sink for iOS, readable from inside the app while the boot is running.
//
//  log.txt and os_log both already exist and neither one helps the person holding the
//  iPad. log.txt is not opened until cemu_initForGame(), so it is empty for the whole
//  of CafeSystem::Initialize(), and reading it at all means backgrounding the app and
//  going through Files. os_log needs a cable and a Mac. On a sideloaded build under
//  LiveContainer, with no debugger and no console, a boot that stalls or renders black
//  is completely silent from the device's point of view - which is exactly the state
//  this port keeps ending up in.
//
//  So: a bounded in-memory ring of the most recent engine log lines, each stamped at
//  the moment the ENGINE emitted it (not when the UI polled for it), that the SwiftUI
//  layer can render as an on-screen launch log.
//
//  Pull, not push. The tap runs on whichever thread happened to log - the title
//  thread, the GPU thread, a coreinit thread - and calling back into Swift from any of
//  those means hopping to the main actor per line, at whatever rate the RPL loader
//  feels like logging. Instead the writer only appends under a short mutex, and the UI
//  drains on its own schedule from the main thread. A stalled or absent reader costs
//  the engine nothing.
//
//  Everything here is inert off iOS.
//
#ifndef CEMU_IOS_LIVE_LOG_H
#define CEMU_IOS_LIVE_LOG_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Turns collection on and off. Off is genuinely free on the writer side - one relaxed
/// atomic load per log line, no allocation - so the settings toggle that drives this is
/// not just hiding a view that is still doing the work.
///
/// Defaults to ON, while the overlay that displays it defaults to OFF. Nothing appears
/// on screen unless the user asks for it, but the buffer is populated from the first
/// line either way: a toggle that also gated collection could only ever show the boot
/// AFTER the one that went wrong.
void ios_live_log_set_enabled(bool enabled);
bool ios_live_log_is_enabled(void);

/// Appends one line. Called from cemuLog_writeLineToSystemConsole() - the single point
/// every engine log line passes through exactly once on iOS - and from
/// cemu_bridge_log_checkpoint(), so the Swift-side milestones land in the same stream
/// as the engine's own output instead of in a separate file nobody correlates.
///
/// `line` is copied. Over-long lines are truncated, and the truncation is marked in the
/// text rather than silent.
void ios_live_log_push(const char* line);

/// Resets the "+0.000s" origin the relative timestamps are measured from and drops
/// everything already buffered. Called when a title launch starts, so the elapsed
/// column answers "how far into THIS boot" rather than "how long since the process
/// started" - under LiveContainer those are not the same thing, because the guest can
/// be launched more than once inside one host process.
void ios_live_log_begin_run(void);

/// Copies out every line newer than `*inoutCursor`, joined with '\n', and advances the
/// cursor past them. Returns "" when there is nothing new.
///
/// The returned pointer is thread-local storage owned by this module, valid only until
/// the next drain on the same thread - copy it if you need to keep it. Same contract as
/// cemu_bridge_status_text().
///
/// `outDropped`, if non-null, receives the number of lines evicted from the ring before
/// this caller reached them. A UI that shows the gap honestly is worth more than one
/// that silently renumbers.
const char* ios_live_log_drain(uint64_t* inoutCursor, uint64_t* outDropped);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CEMU_IOS_LIVE_LOG_H
