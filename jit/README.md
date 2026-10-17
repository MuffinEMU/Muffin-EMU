# Built-in JIT

MuffinEMU's own way to turn on the recompiler (JIT) on iOS 17.4 and later, without
handing off to another app. It is all MuffinEMU code on top of **idevice** (jkcoxson,
MIT). Nothing is taken from StikJIT, StikDebug, EspressU or Husk; the breakpoint
protocol it speaks is the one MuffinEMU's own recompiler already implements
(`BreakGetJITMapping` / `JIT26Detach` in
`src/Cafe/HW/Espresso/Recompiler/PPCRecompiler.cpp`).

## Why a separate process

A process cannot attach a debugger to itself, so the attach runs from a helper app
extension — a second process that shares the install's `get-task-allow`. The host app
hands it the target PID, the pairing data and the DDI paths; the helper does the
reachable / mount / attach work and reports back.

## The device-link crate (`jit/muffin-jit`)

A small Rust static library, GPL-3.0, that the helper links. It exposes a narrow C
ABI (`include/muffin_jit.h`) and does everything over idevice's transports:

- **probe** — is the LocalDevVPN loopback tunnel up (default `10.7.0.1:49152`)?
- **connect** — pair-verify with the pairing file, bring up the TLS-PSK tunnel and the
  software TCP stack, complete the RSD handshake. Every service rides that adapter.
- **ddi_mounted / mount_personalized / mount_cryptex** — the Developer Disk Image, in
  both shapes: the three-file personalized image before iOS 26.4, the five-file
  cryptex from 26.4. A mount lasts until the device reboots.
- **enable** — attach the debugger to the host PID. On a non-TXM device that is the
  whole job (CS_DEBUGGED survives the detach). On a TXM device the recompiler asks for
  each executable region with `brk #0xf00d`; the crate runs the stop loop and services
  those breakpoints **in native code** — no JavaScript interpreter and no injected
  script, just the GDB-remote wire protocol.
- **pair_on_device** — iOS 27+ on-device pairing: MuffinEMU advertises itself as a
  pairable host, accepts the device-initiated pairing, shows the setup code, and keeps
  the pairing file. No computer needed.

### Building

`ci/build-jit-ffi.sh` builds `libmuffin_jit.a` for `aarch64-apple-ios`. Pure Rust plus
idevice with the `rustcrypto` backend, so no C toolchain is needed. The helper
extension links the archive and imports the `MuffinJitFFI` module from `include/`.

## Better than a hand-off enabler

- Background-prepares and mounts the DDI at app start, so Play only has to attach.
- One setup screen with live checks and a fix for each: Developer Mode, get-task-allow,
  a pairing file valid for this device, the tunnel, the DDI, TXM.
- Plain stage progress and specific errors, and the JIT log in Copy bug report.
- On-device pairing on iOS 27, which drops the need for a computer.
- Turns JIT on inside MuffinEMU, so there's no switching to another app and back.

## Status

- [x] Device-link crate: probe, connect, DDI mount (both formats), native TXM loop,
      on-device pairing. C ABI + header.
- [x] CI build script for the static library.
- [ ] Helper app extension that links the crate and runs the protocol off one serial
      queue, launched without costing a free account an extra App ID.
- [ ] Host-side coordinator (get-task-allow check, pairing import, DDI download) and
      the setup UI with live checks.
- [ ] Launch integration and background pre-warm.

Legal: new code under MuffinEMU's copyright (GPL-3.0). idevice is MIT; its notice is in
the repository's NOTICE/credits.
