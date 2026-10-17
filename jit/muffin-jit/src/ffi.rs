// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// Small helpers shared by the C ABI entry points: turning Rust strings and errors
// into caller-owned `char*` out-parameters, and a progress callback type.

use std::ffi::{c_char, CStr, CString};

/// Progress callback the Swift side passes in. `stage` is a small code the UI maps
/// to a label; `message` is a detail line (never a secret — pairing data is never
/// logged or passed here). `ctx` is opaque to us.
pub type MjProgress = Option<extern "C" fn(ctx: *mut std::ffi::c_void, stage: i32, message: *const c_char)>;

/// Writes `msg` into `*out` as a freshly allocated C string the caller frees with
/// `muffin_jit_string_free`. Safe to call with a null `out`.
pub(crate) fn set_err(out: *mut *mut c_char, msg: impl AsRef<str>) {
    if out.is_null() {
        return;
    }
    let c = CString::new(msg.as_ref().replace('\0', " ")).unwrap_or_default();
    unsafe { *out = c.into_raw() };
}

/// Maps a `Result` to a status code, writing any error text to `out_err`.
pub(crate) fn err_out<T>(
    res: Result<T, String>,
    out_err: *mut *mut c_char,
    code: crate::MjStatus,
) -> (i32, Option<T>) {
    match res {
        Ok(v) => (crate::MjStatus::Ok as i32, Some(v)),
        Err(e) => {
            set_err(out_err, e);
            (code as i32, None)
        }
    }
}

/// Reads a required C string argument. Returns an Err string on null/!utf8.
pub(crate) fn cstr<'a>(p: *const c_char, name: &str) -> Result<&'a str, String> {
    if p.is_null() {
        return Err(format!("{name} was null"));
    }
    unsafe { CStr::from_ptr(p) }
        .to_str()
        .map_err(|_| format!("{name} was not valid UTF-8"))
}

/// Reports progress through the callback, if one was given.
pub(crate) fn report(cb: MjProgress, ctx: *mut std::ffi::c_void, stage: i32, message: &str) {
    if let Some(cb) = cb {
        if let Ok(c) = CString::new(message) {
            cb(ctx, stage, c.as_ptr());
        }
    }
}
