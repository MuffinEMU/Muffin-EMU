// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// Enabling JIT, as MuffinEMU's recompiler expects it.
//
//   Non-TXM devices: attaching a debugger sets CS_DEBUGGED, which persists after
//   detach. So we attach and immediately detach; the recompiler then maps RX pages
//   with plain mmap (see PPCRecompiler_readTXMEnvVar() returning false).
//
//   TXM devices: CS_DEBUGGED alone is not enough. Each executable region must be
//   prepared through the debug connection while the debugger is attached. The
//   recompiler signals this with `brk #0xf00d`: x16=1 asks us to prepare a region
//   (BreakGetJITMapping), x16=0 asks us to detach (JIT26Detach). We run the stop
//   loop over the GDB remote protocol and service those breakpoints directly — no
//   JavaScript interpreter, no injected script, just the wire protocol the
//   recompiler already speaks.
//
// This is the whole "universal" protocol expressed in native code: `c` to run,
// read the stopped thread's pc/x16/x0/x1, step past the breakpoint, allocate or
// bless the RX region, hand the address back in x0, and continue until detach.

use std::ffi::{c_char, c_void};

use idevice::debug_proxy::{DebugProxyClient, DebugserverCommand};
// `connect_rsd` is a method on the RsdService trait; it must be in scope to call it.
use idevice::RsdService;

use crate::ffi::{report, MjProgress};
use crate::link::MuffinJitLink;
use crate::{err_out, set_err, MjStatus};

const JIT_PAGE: u64 = 16384;
const BRK_IMM_JITCALL: u32 = 0xf00d;
const CMD_DETACH: u64 = 0;
const CMD_PREPARE_REGION: u64 = 1;

/// Enables JIT for `target_pid`. On a TXM device set `txm` to 1 so the breakpoint
/// protocol runs; on a non-TXM device pass 0 for the plain attach/detach.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_enable(
    link: *mut MuffinJitLink,
    target_pid: i32,
    txm: i32,
    cb: MjProgress,
    ctx: *mut c_void,
    out_err: *mut *mut c_char,
) -> i32 {
    if link.is_null() {
        set_err(out_err, "link was null");
        return MjStatus::InvalidArg as i32;
    }
    if target_pid <= 0 {
        set_err(out_err, "target pid was not valid");
        return MjStatus::InvalidArg as i32;
    }
    let link = &mut *link;

    report(cb, ctx, 20, "Attaching the debugger");
    let res = crate::run_blocking(enable(link, target_pid as u32, txm != 0, cb, ctx));
    let (code, _) = err_out(res, out_err, MjStatus::AttachFailed);
    code
}

async fn enable(
    link: &mut MuffinJitLink,
    pid: u32,
    txm: bool,
    cb: MjProgress,
    ctx: *mut c_void,
) -> Result<(), String> {
    let mut dp = DebugProxyClient::connect_rsd(&mut link.provider, &mut link.handshake)
        .await
        .map_err(|e| format!("could not open the debug connection: {e}"))?;

    // Attach. The target stops; the attach reply is the first stop packet.
    send(&mut dp, &format!("vAttach;{pid:x}")).await?;

    if !txm {
        // CS_DEBUGGED is now set and will survive the detach on a non-TXM device.
        report(cb, ctx, 24, "Releasing the debugger");
        send(&mut dp, "D").await?;
        report(cb, ctx, 25, "JIT is active");
        return Ok(());
    }

    report(cb, ctx, 21, "Preparing executable memory");
    let mut regions = 0u32;
    loop {
        // Run until the next breakpoint. This blocks until the recompiler calls one
        // of its jitcalls during its own init.
        let stop = send(&mut dp, "c").await?;
        let Some(stop) = stop else {
            return Err("the debug connection closed before JIT finished".to_string());
        };

        let tid = field(&stop, "thread:").ok_or("stop reply had no thread id")?;
        let pc = reg(&stop, "20").ok_or("stop reply had no pc")?;
        let x16 = reg(&stop, "10").ok_or("stop reply had no x16")?;

        // Confirm this really is a brk, and read its immediate.
        let instr = send_expect(&mut dp, &format!("m{pc:x},4")).await?;
        let word = le_hex_to_u32(&instr).ok_or("could not read the instruction at pc")?;
        if (word & 0xFFE0_001F) != 0xD420_0000 {
            // Not a breakpoint we planted. Forward the signal and keep going.
            if let Some(sig) = stop.get(1..3) {
                let _ = send(&mut dp, &format!("vCont;S{sig}:{tid}")).await;
            }
            continue;
        }
        let imm = ((word >> 5) & 0xFFFF) as u64;
        if imm != BRK_IMM_JITCALL as u64 {
            // Some other breakpoint; step past it and continue.
            step_past(&mut dp, pc, &tid).await?;
            continue;
        }

        let x0 = reg(&stop, "00").ok_or("stop reply had no x0")?;
        let x1 = reg(&stop, "01").ok_or("stop reply had no x1")?;

        // Step the thread past the brk before servicing it.
        step_past(&mut dp, pc, &tid).await?;

        match x16 {
            CMD_DETACH => {
                send(&mut dp, "D").await?;
                report(cb, ctx, 25, "JIT is active");
                return Ok(());
            }
            CMD_PREPARE_REGION => {
                if x0 == 0 && x1 == 0 {
                    continue;
                }
                let region = if x0 == 0 {
                    // The recompiler asked us to allocate the RX mapping.
                    let resp = send_expect(&mut dp, &format!("_M{x1:x},rx")).await?;
                    u64::from_str_radix(resp.trim(), 16)
                        .map_err(|_| format!("device did not return an RX address (got {resp:?})"))?
                } else {
                    x0
                };
                bless_region(&mut dp, region, x1).await?;
                // Hand the prepared address back in x0.
                set_reg(&mut dp, "00", region, &tid).await?;
                regions += 1;
                if regions == 1 {
                    report(cb, ctx, 22, "Blessing executable pages");
                }
            }
            other => {
                // Unknown jitcall; leave x0 untouched and keep going.
                let _ = other;
            }
        }
    }
}

/// Writes the one-byte "prepare" marker to the first byte of every 16 KB page in
/// the region, which is how the attached debugger is told to prepare that page.
async fn bless_region(
    dp: &mut DebugProxyClient<Box<dyn idevice::ReadWrite>>,
    address: u64,
    length: u64,
) -> Result<(), String> {
    let pages = length.div_ceil(JIT_PAGE).max(1);
    for p in 0..pages {
        let addr = address + p * JIT_PAGE;
        send(dp, &format!("M{addr:x},1:69")).await?;
    }
    Ok(())
}

async fn step_past(
    dp: &mut DebugProxyClient<Box<dyn idevice::ReadWrite>>,
    pc: u64,
    tid: &str,
) -> Result<(), String> {
    set_reg(dp, "20", pc + 4, tid).await?;
    Ok(())
}

async fn set_reg(
    dp: &mut DebugProxyClient<Box<dyn idevice::ReadWrite>>,
    reg: &str,
    value: u64,
    tid: &str,
) -> Result<(), String> {
    send(dp, &format!("P{reg}={};thread:{tid};", u64_to_le_hex(value))).await?;
    Ok(())
}

// --- GDB remote helpers ---------------------------------------------------------

async fn send(
    dp: &mut DebugProxyClient<Box<dyn idevice::ReadWrite>>,
    command: &str,
) -> Result<Option<String>, String> {
    dp.send_command(DebugserverCommand::new(command.to_string(), vec![]))
        .await
        .map_err(|e| format!("debug command {command:?} failed: {e}"))
}

async fn send_expect(
    dp: &mut DebugProxyClient<Box<dyn idevice::ReadWrite>>,
    command: &str,
) -> Result<String, String> {
    send(dp, command)
        .await?
        .ok_or_else(|| format!("debug command {command:?} returned no response"))
}

/// Reads a `;key:value;` field out of a stop reply.
fn field(reply: &str, key: &str) -> Option<String> {
    let start = reply.find(key)? + key.len();
    let rest = &reply[start..];
    let end = rest.find(';').unwrap_or(rest.len());
    Some(rest[..end].to_string())
}

/// Reads a register value (little-endian hex) out of a stop reply, e.g. "20" -> pc.
fn reg(reply: &str, num: &str) -> Option<u64> {
    let needle = format!("{num}:");
    // Registers appear as ";NN:<hex>;" — find one that is preceded by ';' or start.
    let mut from = 0;
    while let Some(i) = reply[from..].find(&needle) {
        let at = from + i;
        let prev_ok = at == 0 || reply.as_bytes()[at - 1] == b';';
        if prev_ok {
            let rest = &reply[at + needle.len()..];
            let end = rest.find(';').unwrap_or(rest.len());
            return le_hex_to_u64(&rest[..end]);
        }
        from = at + needle.len();
    }
    None
}

fn le_hex_to_u64(hex: &str) -> Option<u64> {
    let bytes = decode_hex(hex)?;
    let mut v = 0u64;
    for (i, b) in bytes.iter().take(8).enumerate() {
        v |= (*b as u64) << (8 * i);
    }
    Some(v)
}

fn le_hex_to_u32(hex: &str) -> Option<u32> {
    let bytes = decode_hex(hex)?;
    let mut v = 0u32;
    for (i, b) in bytes.iter().take(4).enumerate() {
        v |= (*b as u32) << (8 * i);
    }
    Some(v)
}

fn u64_to_le_hex(mut v: u64) -> String {
    let mut out = String::with_capacity(16);
    for _ in 0..8 {
        out.push_str(&format!("{:02x}", v & 0xff));
        v >>= 8;
    }
    out
}

fn decode_hex(hex: &str) -> Option<Vec<u8>> {
    let hex = hex.trim();
    if hex.len() % 2 != 0 {
        return None;
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect()
}
