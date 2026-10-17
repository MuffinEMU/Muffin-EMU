// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// muffin-jit: MuffinEMU's own device-link layer for enabling the recompiler (JIT)
// on iOS 17.4+. Written from scratch; the only outside dependency is `idevice`
// (jkcoxson, MIT) for the lockdown / RSD / tunnel / image-mounter / debug-proxy
// transports. The JIT breakpoint protocol it speaks is MuffinEMU's own, already
// implemented in the recompiler (BreakGetJITMapping / JIT26Detach in
// src/Cafe/HW/Espresso/Recompiler/PPCRecompiler.cpp). No code is taken from
// StikJIT, StikDebug, EspressU or Husk.
//
// Everything here is a thin C ABI over async idevice calls, driven on a private
// single-thread Tokio runtime. The helper app extension (a separate process, since
// a process cannot debug itself) links this archive and calls these functions on a
// dedicated serial queue.

#![allow(clippy::missing_safety_doc)]

mod ffi;
mod jit;
mod link;
mod mount;
mod pairing;

use std::ffi::{c_char, CString};
use std::future::Future;

pub(crate) use ffi::{err_out, set_err};

/// Error codes returned across the C ABI. 0 is success; everything else is a
/// category the Swift side can branch on without parsing the message.
#[repr(i32)]
pub enum MjStatus {
    Ok = 0,
    InvalidArg = -1,
    Unreachable = -2,
    PairingInvalid = -3,
    DdiFailed = -4,
    AttachFailed = -5,
    ProtocolFailed = -6,
    NotMounted = -7,
    Internal = -100,
}

/// One shared current-thread runtime. The helper runs the whole protocol on one
/// serial queue, so a single-thread runtime is enough and keeps the archive small.
fn run_blocking<F: Future>(fut: F) -> F::Output {
    use std::sync::OnceLock;
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    let rt = RT.get_or_init(|| {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("muffin-jit: failed to build Tokio runtime")
    });
    rt.block_on(fut)
}

/// Frees a string handed back through an `out_err`/`out_*` char pointer.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// A human-readable one-line version string, for the credits / bug report.
#[no_mangle]
pub extern "C" fn muffin_jit_version() -> *const c_char {
    // Static, never freed.
    concat!("muffin-jit ", env!("CARGO_PKG_VERSION"), " on idevice 0.1.68\0").as_ptr() as *const c_char
}
