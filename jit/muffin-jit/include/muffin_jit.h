// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// C interface to muffin-jit, MuffinEMU's own device-link layer (built on idevice,
// MIT). The helper app extension imports this through module.modulemap and links
// libmuffin_jit.a. Every call is synchronous and blocking; run them on one serial
// background queue in the helper.
//
// Return codes: 0 is success. Negative values match MjStatus in lib.rs:
//   -1 invalid argument, -2 unreachable, -3 pairing invalid, -4 DDI failed,
//   -5 attach failed, -6 protocol failed, -7 not mounted, -100 internal.
// On any non-zero return, *out_err (when provided) holds a caller-owned message to
// free with muffin_jit_string_free.

#ifndef MUFFIN_JIT_H
#define MUFFIN_JIT_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque connected session, created by muffin_jit_connect, freed by muffin_jit_link_free.
typedef struct MuffinJitLink MuffinJitLink;

// Progress callback. `stage` is a small code the UI maps to a label; `message` is a
// human-readable detail line (never a secret). `ctx` is passed straight through.
typedef void (*MuffinJitProgress)(void *ctx, int32_t stage, const char *message);

// PIN callback for on-device pairing: invoked with the setup code to show the user.
typedef void (*MuffinJitPinCallback)(void *ctx, const char *pin);

// Frees a string returned through an out_err / out_* char pointer.
void muffin_jit_string_free(char *s);

// Frees a byte buffer returned by muffin_jit_pair_on_device.
void muffin_jit_bytes_free(uint8_t *ptr, size_t len);

// A static one-line version string (do not free).
const char *muffin_jit_version(void);

// TCP-reachability probe of the RSD endpoint (is the tunnel up?).
int32_t muffin_jit_probe(const char *device_ip, uint16_t rsd_port,
                         uint32_t timeout_ms, char **out_err);

// Opens a session: pair-verifies with the pairing file, brings up the tunnel, and
// completes the RSD handshake. `ddi_cryptex` is 1 for iOS 26.4+ (cryptex DDI), else 0.
int32_t muffin_jit_connect(const uint8_t *pairing, size_t pairing_len,
                           const char *device_ip, uint16_t rsd_port,
                           int32_t ddi_cryptex,
                           MuffinJitProgress cb, void *ctx,
                           MuffinJitLink **out_link, char **out_err);

void muffin_jit_link_free(MuffinJitLink *link);

// Is a Developer Disk Image already mounted? *out_mounted is set to 0 or 1.
int32_t muffin_jit_ddi_mounted(MuffinJitLink *link, int32_t *out_mounted, char **out_err);

// Mount the personalized DDI (iOS before 26.4).
int32_t muffin_jit_mount_personalized(MuffinJitLink *link,
                                      const char *image_path,
                                      const char *trustcache_path,
                                      const char *manifest_path,
                                      MuffinJitProgress cb, void *ctx, char **out_err);

// Install the cryptex DDI (iOS 26.4+). `restore_dir` holds BuildManifest.plist and
// the Cryptex1 payloads.
int32_t muffin_jit_mount_cryptex(MuffinJitLink *link, const char *restore_dir,
                                 MuffinJitProgress cb, void *ctx, char **out_err);

// Enable JIT for `target_pid`. Pass txm=1 on a TXM device (runs the breakpoint
// protocol); txm=0 on a non-TXM device (plain attach/detach).
int32_t muffin_jit_enable(MuffinJitLink *link, int32_t target_pid, int32_t txm,
                          MuffinJitProgress cb, void *ctx, char **out_err);

// On-device pairing (iOS 27+): advertise as a pairable host and accept one
// device-initiated pairing. On success the pairing file bytes are written to
// *out_pairing / *out_pairing_len (free with muffin_jit_bytes_free). The PIN
// callback is invoked with the code to show the user.
int32_t muffin_jit_pair_on_device(const char *name, const char *model,
                                  uint32_t timeout_ms,
                                  MuffinJitPinCallback pin_cb, void *pin_ctx,
                                  MuffinJitProgress cb, void *ctx,
                                  uint8_t **out_pairing, size_t *out_pairing_len,
                                  char **out_err);

#ifdef __cplusplus
}
#endif

#endif // MUFFIN_JIT_H
