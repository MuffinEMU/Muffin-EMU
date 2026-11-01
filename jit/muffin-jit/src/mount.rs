// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// Developer Disk Image: is one mounted, and if not, mount it. Two formats:
//   - personalized, before iOS 26.4 (image + trust cache + build manifest, signed
//     per-device through Apple's TSS using the device's UniqueChipID), and
//   - cryptex, iOS 26.4 and later (a Restore directory; cryptexd personalizes and
//     installs it).
// The Swift side downloads the files and decides the format from the OS version;
// this module just does what it is told and reports mounted / not-mounted.

use std::ffi::{c_char, c_void};

use idevice::mobile_image_mounter::ImageMounter;
use idevice::services::cryptexd;
use idevice::services::cryptexd::assets::Cryptex1Assets;
use idevice::lockdown::LockdownClient;
// `connect_rsd` is a method on the RsdService trait; it must be in scope to call it.
use idevice::RsdService;

use crate::ffi::{cstr, report, MjProgress};
use crate::link::MuffinJitLink;
use crate::{err_out, set_err, MjStatus};

/// Reports whether a Developer Disk Image is already mounted. `out_mounted` is set
/// to 1 or 0 on success.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_ddi_mounted(
    link: *mut MuffinJitLink,
    out_mounted: *mut i32,
    out_err: *mut *mut c_char,
) -> i32 {
    if link.is_null() || out_mounted.is_null() {
        set_err(out_err, "link or out_mounted was null");
        return MjStatus::InvalidArg as i32;
    }
    *out_mounted = 0;
    let link = &mut *link;
    let cryptex = link.cryptex;

    let res = crate::run_blocking(async {
        if cryptex {
            let installed = cryptexd::installed_ddi(&mut link.provider, &mut link.handshake)
                .await
                .map_err(|e| format!("could not query the DDI cryptex: {e}"))?;
            Ok::<bool, String>(installed.is_some())
        } else {
            let mut mounter = ImageMounter::connect_rsd(&mut link.provider, &mut link.handshake)
                .await
                .map_err(|e| format!("could not reach the image mounter: {e}"))?;
            let devices = mounter
                .copy_devices()
                .await
                .map_err(|e| format!("could not list mounted images: {e}"))?;
            Ok(!devices.is_empty())
        }
    });

    let (code, val) = err_out(res, out_err, MjStatus::DdiFailed);
    if let Some(m) = val {
        *out_mounted = if m { 1 } else { 0 };
    }
    code
}

/// Mounts the personalized DDI (iOS before 26.4). Paths point to the downloaded
/// image, its trust cache, and the build manifest.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_mount_personalized(
    link: *mut MuffinJitLink,
    image_path: *const c_char,
    trustcache_path: *const c_char,
    manifest_path: *const c_char,
    cb: MjProgress,
    ctx: *mut c_void,
    out_err: *mut *mut c_char,
) -> i32 {
    if link.is_null() {
        set_err(out_err, "link was null");
        return MjStatus::InvalidArg as i32;
    }
    let link = &mut *link;

    let paths = (|| {
        Ok::<_, String>((
            cstr(image_path, "image_path")?.to_string(),
            cstr(trustcache_path, "trustcache_path")?.to_string(),
            cstr(manifest_path, "manifest_path")?.to_string(),
        ))
    })();
    let (image_path, trustcache_path, manifest_path) = match paths {
        Ok(p) => p,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };

    report(cb, ctx, 10, "Reading the disk image");
    let res = crate::run_blocking(async {
        let image = tokio::fs::read(&image_path)
            .await
            .map_err(|e| format!("could not read {image_path}: {e}"))?;
        let trustcache = tokio::fs::read(&trustcache_path)
            .await
            .map_err(|e| format!("could not read {trustcache_path}: {e}"))?;
        let manifest = tokio::fs::read(&manifest_path)
            .await
            .map_err(|e| format!("could not read {manifest_path}: {e}"))?;

        report(cb, ctx, 11, "Asking the device for its chip ID");
        let unique_chip_id = fetch_unique_chip_id(link).await?;

        report(cb, ctx, 12, "Uploading and mounting");
        let mut mounter = ImageMounter::connect_rsd(&mut link.provider, &mut link.handshake)
            .await
            .map_err(|e| format!("could not reach the image mounter: {e}"))?;

        let cbx = ProgressBridge { cb, ctx };
        mounter
            .mount_personalized_with_callback_rsd(
                &mut link.provider,
                &mut link.handshake,
                image,
                trustcache,
                &manifest,
                None,
                unique_chip_id,
                |((n, d), st): ((usize, usize), ProgressBridge)| async move {
                    let pct = if d > 0 { (n as f64 / d as f64) * 100.0 } else { 0.0 };
                    st.say(13, &format!("Uploading image {pct:.0}%"));
                },
                cbx,
            )
            .await
            .map_err(|e| format!("mounting the disk image failed: {e}"))?;
        Ok::<(), String>(())
    });

    err_out(res, out_err, MjStatus::DdiFailed).0
}

/// Installs the cryptex DDI (iOS 26.4+). `restore_dir` is the unpacked Restore
/// directory holding BuildManifest.plist and the Cryptex1 payloads.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_mount_cryptex(
    link: *mut MuffinJitLink,
    restore_dir: *const c_char,
    cb: MjProgress,
    ctx: *mut c_void,
    out_err: *mut *mut c_char,
) -> i32 {
    if link.is_null() {
        set_err(out_err, "link was null");
        return MjStatus::InvalidArg as i32;
    }
    let link = &mut *link;
    let dir = match cstr(restore_dir, "restore_dir") {
        Ok(d) => d.to_string(),
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };

    report(cb, ctx, 10, "Reading the disk image");
    let res = crate::run_blocking(async {
        let assets = Cryptex1Assets::load(&dir)
            .await
            .map_err(|e| format!("could not load the DDI files in {dir}: {e}"))?;
        report(cb, ctx, 12, "Personalizing and installing");
        cryptexd::install_ddi(&mut link.provider, &mut link.handshake, &assets)
            .await
            .map_err(|e| format!("installing the disk image failed: {e}"))?;
        Ok::<(), String>(())
    });

    err_out(res, out_err, MjStatus::DdiFailed).0
}

// A copyable progress sink so it can cross the mounter's callback bound (S: Clone).
#[derive(Clone, Copy)]
struct ProgressBridge {
    cb: MjProgress,
    ctx: *mut c_void,
}
unsafe impl Send for ProgressBridge {}
unsafe impl Sync for ProgressBridge {}
impl ProgressBridge {
    fn say(&self, stage: i32, msg: &str) {
        report(self.cb, self.ctx, stage, msg);
    }
}

async fn fetch_unique_chip_id(link: &mut MuffinJitLink) -> Result<u64, String> {
    let mut lockdown = LockdownClient::connect_rsd(&mut link.provider, &mut link.handshake)
        .await
        .map_err(|e| format!("could not reach lockdown: {e}"))?;
    let value = lockdown
        .get_value(Some("UniqueChipID"), None)
        .await
        .map_err(|e| format!("could not read the chip ID: {e}"))?;
    value
        .as_unsigned_integer()
        .ok_or_else(|| "the device returned an unexpected chip ID".to_string())
}
