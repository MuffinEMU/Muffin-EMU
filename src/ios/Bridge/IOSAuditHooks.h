//
//  IOSAuditHooks.h
//  What the MuffinEMU Audit app (tools/audit-app) needs from the core that the regular bridge
//  does not offer. Plain C, like CemuBridge.h, so the audit app's bridging header can import it.
//
//  Everything behind this header is compiled ONLY when the core is configured with
//  -DMUFFIN_AUDIT_HOOKS=ON (src/CMakeLists.txt), which only the audit workflow does. The shipping
//  MuffinEMU framework does not contain these functions, and the three places in shared files that
//  call into them (MetalRenderer.cpp, iOSAudioAPI.mm, src/CMakeLists.txt) are each wrapped in
//  #if MUFFIN_AUDIT_HOOKS, so with the flag off they preprocess to nothing.
//
//  Design notes are in docs/AUDIT.md (probe protocol, capture path, snapshot schema).
//
#ifndef CEMU_IOS_AUDIT_HOOKS_H
#define CEMU_IOS_AUDIT_HOOKS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Bumped whenever a struct or function in this header changes meaning. The app refuses a core
/// whose answer differs from the one it was built for.
#define CEMU_AUDIT_API_VERSION 1

int cemu_audit_api_version(void);

/// One-line JSON describing how the hooks were compiled in ("hooks":1,"metal":true,...). Static
/// storage. Goes into every report next to the core fingerprint.
const char* cemu_audit_build_info(void);

/// The clock every timestamp in an audit report uses (nanoseconds, monotonic, does not advance in
/// sleep). The same clock the core stamps frames with, so host and core times compare directly.
uint64_t cemu_audit_now_ns(void);

// ---------------------------------------------------------------------------
// Logging

/// 0 = guest OSReport lines only (the probe protocol), 1 = audit set (adds GX2, texture cache,
/// sound, input, API-error and texture-readback categories), 2 = verbose (adds coreinit memory and
/// thread-sync categories). Call after cemu_bridge_initialize(), which sets its own mix.
void cemu_audit_set_log_profile(int profile);

// ---------------------------------------------------------------------------
// Guest memory: the probe mailbox lives in the guest program's .bss and its address is announced
// on the log. Only the guest's MEM1/MEM2 data range is readable and writable here.

bool cemu_audit_guest_read(uint32_t guestAddress, void* out, uint32_t length);
bool cemu_audit_guest_write(uint32_t guestAddress, const void* data, uint32_t length);

// ---------------------------------------------------------------------------
// State snapshot

/// JSON object with the renderer, GPU-thread, texture-cache, memory, audio and timing counters the
/// core keeps, read at the moment of the call. Schema: docs/AUDIT.md "State snapshot". The pointer
/// is thread-local storage valid until the next call on the same thread; copy it.
const char* cemu_audit_snapshot_json(void);

// ---------------------------------------------------------------------------
// Framebuffer readback (Metal). Each captured frame is what the guest presented to the scan
// buffer, read back before the output shader scales it to the screen.

#define CEMU_AUDIT_VIEW_TV  1u
#define CEMU_AUDIT_VIEW_PAD 2u

#define CEMU_AUDIT_FRAME_OK                 0u
#define CEMU_AUDIT_FRAME_UNSUPPORTED_FORMAT 1u  // pixelFormat names the Metal format that could not be read
#define CEMU_AUDIT_FRAME_READBACK_FAILED    2u

typedef struct CemuAuditFrame {
    uint32_t seq;            // 1, 2, 3... in delivery order since the last arm
    uint32_t view;           // CEMU_AUDIT_VIEW_*
    uint32_t status;         // CEMU_AUDIT_FRAME_*
    uint32_t latteFrame;     // LatteGPUState.frameCounter at readback
    uint64_t timestampNs;    // cemu_audit_now_ns() at readback
    uint32_t srcWidth;
    uint32_t srcHeight;
    uint32_t pixelFormat;    // raw MTLPixelFormat of the source texture
    uint32_t thumbWidth;
    uint32_t thumbHeight;    // the thumbnail is thumbWidth*thumbHeight*3 bytes of RGB
    float    meanR;          // 0..255 over the whole frame
    float    meanG;
    float    meanB;
    float    blackFraction;  // share of pixels with every channel <= 8
    float    whiteFraction;  // share of pixels with every channel >= 247
    uint32_t minLuma;
    uint32_t maxLuma;
    uint64_t hash;           // equal for two bit-identical frames
} CemuAuditFrame;

/// Asks for `count` frames of the views in `viewMask`, each reduced to a thumbWidth x thumbHeight
/// RGB thumbnail. Replaces any capture in progress and clears the queue. Frames are read back one
/// per presented frame while armed (each readback waits for the GPU, so armed capture lowers frame
/// rate; that is reported, not hidden).
void cemu_audit_capture_arm(uint32_t viewMask, uint32_t count, uint32_t thumbWidth, uint32_t thumbHeight);

/// Stops capturing and drops anything queued.
void cemu_audit_capture_cancel(void);

/// Frames delivered and not yet popped.
uint32_t cemu_audit_capture_pending(void);

/// Pops the oldest frame. Copies thumbWidth*thumbHeight*3 bytes to `thumbRGB` when `thumbCapacity`
/// allows; returns false when the queue is empty.
bool cemu_audit_capture_pop(CemuAuditFrame* header, uint8_t* thumbRGB, uint32_t thumbCapacity);

// ---------------------------------------------------------------------------
// Frame pacing: the timestamp of every TV present, taken on the GPU thread.

void cemu_audit_frame_timing_enable(bool enabled);

/// Copies out up to `capacity` present timestamps (cemu_audit_now_ns clock) newer than the last
/// drain and sets *dropped to how many were lost to the ring wrapping. Returns how many it wrote.
uint32_t cemu_audit_frame_timing_drain(uint64_t* outNs, uint32_t capacity, uint32_t* dropped);

// ---------------------------------------------------------------------------
// Audio output: measured on the audio render thread, on what is actually handed to the device.

typedef struct CemuAuditAudioStats {
    uint64_t callbacks;          // device render callbacks since reset, while playing
    uint64_t frames;             // sample frames the device asked for
    uint64_t validFrames;        // of those, the frames that came from the emulated AX rather than padding
    uint64_t underrunCallbacks;  // callbacks the ring buffer could not fill completely
    uint64_t underrunFrames;     // sample frames that were padded with silence
    uint64_t feedRejects;        // blocks the emulated AX refused to queue because the ring was full
    uint64_t silentCallbacks;    // callbacks that were entirely zero
    uint64_t discontinuities;    // sample-to-sample jumps above 12000 (a click, or a hard clip)
    uint32_t maxStep;            // the largest sample-to-sample jump seen
    uint32_t peak;               // largest absolute sample, 0..32768
    uint32_t longestZeroRun;     // longest run of all-channels-zero frames inside a callback that was not padding
    uint32_t channels;           // of the most recent callback
    double   rms;                // 0..1 over every frame since reset
} CemuAuditAudioStats;

void cemu_audit_audio_reset(void);
void cemu_audit_audio_get(CemuAuditAudioStats* out);

// Called from iOSAudioAPI.mm (audio render thread and AX feeder thread).
void cemu_audit_audio_note_render(const void* device, const int16_t* samples, uint32_t bytesValid,
                                  uint32_t bytesRequested, uint32_t channels, uint32_t bitsPerSample);
void cemu_audit_audio_note_feed_reject(void);

#ifdef __cplusplus
} // extern "C"

// Renderer side, C++ only (MetalRenderer.cpp calls these through IOSAuditMetal.cpp).
bool cemu_audit_capture_wants(bool tv);
void cemu_audit_capture_deliver(bool tv, uint32_t latteFrame, uint32_t srcWidth, uint32_t srcHeight,
                                uint32_t rawPixelFormat, int layout /* ios_audit::PixelLayout, -1 unsupported */,
                                const uint8_t* pixels, uint32_t rowBytes, bool readbackFailed);
#endif

#endif // CEMU_IOS_AUDIT_HOOKS_H
