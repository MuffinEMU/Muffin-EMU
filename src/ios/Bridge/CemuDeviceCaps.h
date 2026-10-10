//
//  CemuDeviceCaps.h
//  The device capability snapshot, for Swift. Plain C, like CemuBridge.h.
//
//  One snapshot is taken at launch (what this device is, what its GPU supports, how much
//  memory it has, what size of screen it has) and every budget in the app and the engine is
//  derived from it. Nothing else should carry a number that was measured on one device.
//
#ifndef CEMU_DEVICE_CAPS_H
#define CEMU_DEVICE_CAPS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CemuDeviceCaps {
    int32_t  chipNumber;              // 12 for A12Z, 2 for M2; 0 if unknown
    int32_t  chipSeries;              // 'A' or 'M'; 0 if unknown
    int32_t  tier;                    // 0 low (under 4.5 GiB), 1 standard, 2 high (7 GiB and up)
    int32_t  appleGpuFamily;          // highest MTLGPUFamilyAppleN supported; 0 if unknown
    bool     gpuKnown;
    bool     metal3;
    bool     meshShaders;
    bool     bcTextures;              // native BC; false means BC is transcoded to ASTC
    bool     astcHdr;
    bool     isHighEndSoc;            // A17 Pro and later, or any M-series
    bool     multicoreViable;         // enough RAM and host cores to run the three emulated cores in parallel
    bool     isPad;
    uint64_t maxBufferLength;
    uint64_t recommendedMaxWorkingSet;
    uint64_t physicalMemory;
    uint64_t availableAtLaunch;
    uint64_t bufferCacheBytes;
    uint64_t stagingChunkBytes;
    uint64_t minBootHeadroomBytes;
    uint32_t jitArenaStartMB;
    uint32_t logicalCores;
    uint32_t maxHostThreads;          // most host threads the emulated cores may use on this device (1 to 3)
    uint32_t perfCores;
    uint32_t effCores;
    int32_t  screenClass;             // 0 unknown, 1 phone-compact, 2 phone, 3 pad, 4 pad-large
    uint32_t screenShortPoints;
    uint32_t screenLongPoints;
    uint32_t screenScale;
} CemuDeviceCaps;

/// The screen, measured by the app in points (orientation independent). Call before
/// cemu_device_caps_initialize(); later calls refresh the screen class only.
void cemu_device_caps_set_screen(double shortSidePoints, double longSidePoints, double nativeScale, bool isPad);

/// Takes the snapshot (idempotent) and publishes it to the engine. The launch code calls it
/// first, before the renderer or the recompiler exist.
void cemu_device_caps_initialize(void);

/// Fills `out` from the snapshot, taking it first if nobody has.
void cemu_device_caps_get(struct CemuDeviceCaps* out);

/// "DEVICE iPad8,11 | chip A12Z | tier standard | ..." - the first line of every device log.
const char* cemu_device_caps_line(void);

/// hw.machine, e.g. "iPhone17,1"; and the chip name from the GPU, e.g. "A17 Pro". Valid until the next call on the same thread.
const char* cemu_device_caps_machine(void);
const char* cemu_device_caps_chip(void);

#ifdef __cplusplus
}
#endif

#endif
