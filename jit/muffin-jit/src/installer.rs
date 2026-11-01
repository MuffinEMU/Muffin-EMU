// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// MuffinInstaller: MuffinEMU signs and installs itself with the person's own Apple ID, on the
// device, over the same tunnel built-in JIT uses. Built on isideload (nab138, MIT): GrandSlam
// sign-in with two-factor, the developer portal (team, device, certificate, app IDs, profiles),
// code signing, and installation over RSD (AFC upload + installation_proxy).
//
// The password is passed in for each call and never stored or logged here; the app keeps it in
// the Keychain. The signing key, certificate and anisette state live in `storage_dir` (the app's
// own Application Support), so a refresh reuses one certificate instead of making a new one.
//
// When an account already has its maximum number of certificates we stop with an error rather
// than revoke one: revoking would break apps another installer (SideStore) signed with it.

use std::ffi::{c_char, c_void, CStr, CString};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Once};

use isideload::anisette::remote_v3::RemoteV3AnisetteProvider;
use isideload::auth::apple_account::{AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse};
use isideload::dev::developer_session::DeveloperSession;
use isideload::dev::devices::DevicesApi;
use isideload::sideload::builder::MaxCertsBehavior;
use isideload::sideload::install::install_app_rsd;
use isideload::sideload::{SideloaderBuilder, TeamSelection};
use isideload::util::callbacks::{ExtensionsBehaviorCallbackBox, MaxCertsCallbackBox};
use isideload::util::fs_storage::FsStorage;

use crate::ffi::{cstr, report, MjProgress};
use crate::link::MuffinJitLink;
use crate::{err_out, set_err, MjStatus};

/// Two-factor callback: called (blocking) when Apple asks for a code. `via_sms` is 1 when the code
/// went by text to `destination`, 0 when it went to the person's devices. Write the code into
/// `out_code` (NUL-terminated, at most `out_cap` bytes) and return 1; return 2 to have it sent to the
/// person's devices instead; return 0 to cancel.
pub type MiTwoFactor = Option<
    extern "C" fn(ctx: *mut c_void, via_sms: i32, destination: *const c_char, out_code: *mut c_char, out_cap: usize) -> i32,
>;

struct SendPtr(*mut c_void);
unsafe impl Send for SendPtr {}
unsafe impl Sync for SendPtr {}

fn init_once() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let _ = isideload::init();
    });
}

fn storage(dir: &Path) -> Box<FsStorage> {
    Box::new(FsStorage::new(dir.to_path_buf()))
}

async fn sign_in(
    apple_id: &str,
    password: &str,
    anisette_url: &str,
    dir: &Path,
    tfa: MiTwoFactor,
    tfa_ctx: SendPtr,
) -> Result<AppleAccount, String> {
    let ctx = Arc::new(tfa_ctx);
    let get_code = move |params: TwoFactorCallbackParams| {
        let ctx = ctx.clone();
        async move {
            let Some(cb) = tfa else { return Ok(TwoFactorCallbackResponse::Abort) };
            let destination = if params.sms {
                params
                    .selected_number_id
                    .and_then(|id| params.numbers.iter().find(|n| n.id == id))
                    .map(|n| n.number_with_dial_code.clone())
                    .unwrap_or_default()
            } else {
                String::new()
            };
            let c_dest = CString::new(destination).unwrap_or_default();
            let mut buf = [0 as c_char; 64];
            let answer = cb(ctx.0, params.sms as i32, c_dest.as_ptr(), buf.as_mut_ptr(), buf.len());
            Ok(match answer {
                1 => {
                    let code = unsafe { CStr::from_ptr(buf.as_ptr()) }.to_string_lossy().trim().to_string();
                    TwoFactorCallbackResponse::SubmitCode(code)
                }
                2 => TwoFactorCallbackResponse::SendToDevices,
                _ => TwoFactorCallbackResponse::Abort,
            })
        }
    };
    let mut anisette = RemoteV3AnisetteProvider::default()
        .map_err(|e| format!("couldn't reach the anisette server: {e}"))?
        .set_serial_number("2".to_string())
        .set_storage(storage(dir));
    if !anisette_url.is_empty() {
        anisette = anisette.set_url(anisette_url);
    }
    AppleAccount::builder(apple_id)
        .anisette_provider(anisette)
        .login(password, get_code)
        .await
        .map_err(|e| format!("Apple didn't accept the sign-in: {e}"))
}

fn copy_out(out: *mut *mut c_char, value: &str) {
    if !out.is_null() {
        if let Ok(c) = CString::new(value) {
            unsafe { *out = c.into_raw() };
        }
    }
}

/// Checks an Apple ID: signs in (asking for a two-factor code through `tfa` if Apple wants one) and
/// opens the developer account. On success `*out_team` is the team MuffinEMU will sign with (free
/// with muffin_jit_string_free).
#[no_mangle]
pub unsafe extern "C" fn muffin_installer_sign_in(
    apple_id: *const c_char,
    password: *const c_char,
    anisette_url: *const c_char,
    storage_dir: *const c_char,
    tfa: MiTwoFactor,
    tfa_ctx: *mut c_void,
    out_team: *mut *mut c_char,
    out_err: *mut *mut c_char,
) -> i32 {
    init_once();
    let args = (|| {
        Ok::<_, String>((
            cstr(apple_id, "apple_id")?.to_string(),
            cstr(password, "password")?.to_string(),
            if anisette_url.is_null() { String::new() } else { cstr(anisette_url, "anisette_url")?.to_string() },
            PathBuf::from(cstr(storage_dir, "storage_dir")?),
        ))
    })();
    let (apple_id, password, anisette_url, dir) = match args {
        Ok(v) => v,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };
    let ctx = SendPtr(tfa_ctx);
    let res = crate::run_blocking(async move {
        let mut account = sign_in(&apple_id, &password, &anisette_url, &dir, tfa, ctx).await?;
        let session = DeveloperSession::from_account(&mut account)
            .await
            .map_err(|e| format!("couldn't open the developer account: {e}"))?;
        let mut sideloader = SideloaderBuilder::<MaxCertsCallbackBox, ExtensionsBehaviorCallbackBox>::new(session, apple_id.clone())
            .team_selection(TeamSelection::First)
            .max_certs_behavior(MaxCertsBehavior::Error)
            .storage(storage(&dir))
            .machine_name("MuffinEMU".to_string())
            .build();
        let team = sideloader.get_team().await.map_err(|e| format!("couldn't read the account's team: {e}"))?;
        Ok::<String, String>(team.name.unwrap_or(team.team_id))
    });
    let (code, val) = err_out(res, out_err, MjStatus::Internal);
    if let Some(team) = val {
        copy_out(out_team, &team);
    }
    code
}

/// Signs `app_path` (an .app folder or an .ipa) with the Apple ID and installs it on this device over
/// `link` (from muffin_jit_connect). Registers the device with the team first. For MuffinEMU itself
/// this is a refresh or an update; iOS closes the app when its new copy installs.
#[no_mangle]
pub unsafe extern "C" fn muffin_installer_sign_and_install(
    link: *mut MuffinJitLink,
    apple_id: *const c_char,
    password: *const c_char,
    anisette_url: *const c_char,
    storage_dir: *const c_char,
    app_path: *const c_char,
    tfa: MiTwoFactor,
    tfa_ctx: *mut c_void,
    cb: MjProgress,
    ctx: *mut c_void,
    out_err: *mut *mut c_char,
) -> i32 {
    init_once();
    if link.is_null() {
        set_err(out_err, "no device link");
        return MjStatus::InvalidArg as i32;
    }
    let link = &mut *link;
    let args = (|| {
        Ok::<_, String>((
            cstr(apple_id, "apple_id")?.to_string(),
            cstr(password, "password")?.to_string(),
            if anisette_url.is_null() { String::new() } else { cstr(anisette_url, "anisette_url")?.to_string() },
            PathBuf::from(cstr(storage_dir, "storage_dir")?),
            PathBuf::from(cstr(app_path, "app_path")?),
        ))
    })();
    let (apple_id, password, anisette_url, dir, app) = match args {
        Ok(v) => v,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };
    let tfa_ptr = SendPtr(tfa_ctx);
    let udid = link
        .handshake
        .properties
        .get("UniqueDeviceID")
        .and_then(|v| v.as_string())
        .map(str::to_string)
        .unwrap_or_else(|| link.handshake.uuid.clone());
    let device_name = link
        .handshake
        .properties
        .get("DeviceName")
        .and_then(|v| v.as_string())
        .unwrap_or("MuffinEMU device")
        .to_string();

    report(cb, ctx, 40, "Signing in to Apple");
    let res = crate::run_blocking(async {
        let mut account = sign_in(&apple_id, &password, &anisette_url, &dir, tfa, tfa_ptr).await?;
        let session = DeveloperSession::from_account(&mut account)
            .await
            .map_err(|e| format!("couldn't open the developer account: {e}"))?;
        let mut sideloader = SideloaderBuilder::<MaxCertsCallbackBox, ExtensionsBehaviorCallbackBox>::new(session, apple_id.clone())
            .team_selection(TeamSelection::First)
            .max_certs_behavior(MaxCertsBehavior::Error)
            .storage(storage(&dir))
            .machine_name("MuffinEMU".to_string())
            .build();
        let team = sideloader.get_team().await.map_err(|e| format!("couldn't read the account's team: {e}"))?;
        report(cb, ctx, 41, "Registering this device");
        sideloader
            .get_dev_session()
            .ensure_device_registered(&team, &device_name, &udid, None)
            .await
            .map_err(|e| format!("couldn't register this device with the account: {e}"))?;
        report(cb, ctx, 42, "Signing MuffinEMU");
        let (signed, _) = sideloader
            .sign_app(app, Some(team), true, None::<fn(f32) -> std::future::Ready<()>>, None, Some(&udid))
            .await
            .map_err(|e| format!("signing failed: {e}"))?;
        report(cb, ctx, 43, "Installing");
        install_app_rsd(&mut link.provider, &mut link.handshake, &signed, |_| {})
            .await
            .map_err(|e| format!("installing failed: {e}"))?;
        Ok::<(), String>(())
    });
    let (code, _) = err_out(res, out_err, MjStatus::Internal);
    if code == 0 {
        report(cb, ctx, 44, "Installed");
    }
    code
}

/// Installs an app that is already signed (an .ipa or an .app folder) over `link`, unchanged.
#[no_mangle]
pub unsafe extern "C" fn muffin_installer_install_signed(
    link: *mut MuffinJitLink,
    app_path: *const c_char,
    work_dir: *const c_char,
    cb: MjProgress,
    ctx: *mut c_void,
    out_err: *mut *mut c_char,
) -> i32 {
    init_once();
    if link.is_null() {
        set_err(out_err, "no device link");
        return MjStatus::InvalidArg as i32;
    }
    let link = &mut *link;
    let args = (|| Ok::<_, String>((PathBuf::from(cstr(app_path, "app_path")?), PathBuf::from(cstr(work_dir, "work_dir")?))))();
    let (app, work) = match args {
        Ok(v) => v,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };
    report(cb, ctx, 50, "Unpacking");
    let res = crate::run_blocking(async {
        let bundle = if app.extension().map(|e| e.eq_ignore_ascii_case("ipa")).unwrap_or(false) {
            unpack_ipa(&app, &work)?
        } else {
            app.clone()
        };
        report(cb, ctx, 51, "Installing");
        install_app_rsd(&mut link.provider, &mut link.handshake, &bundle, |_| {})
            .await
            .map_err(|e| format!("installing failed: {e}"))?;
        Ok::<(), String>(())
    });
    let (code, _) = err_out(res, out_err, MjStatus::Internal);
    if code == 0 {
        report(cb, ctx, 52, "Installed");
    }
    code
}

/// Unzips an .ipa into `work` and returns the Payload/*.app inside it.
fn unpack_ipa(ipa: &Path, work: &Path) -> Result<PathBuf, String> {
    let _ = std::fs::remove_dir_all(work);
    std::fs::create_dir_all(work).map_err(|e| format!("couldn't make a work folder: {e}"))?;
    let file = std::fs::File::open(ipa).map_err(|e| format!("couldn't open the IPA: {e}"))?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| format!("that IPA isn't a valid archive: {e}"))?;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i).map_err(|e| format!("couldn't read the IPA: {e}"))?;
        let Some(rel) = entry.enclosed_name() else { continue };
        let out = work.join(rel);
        if entry.is_dir() {
            std::fs::create_dir_all(&out).map_err(|e| format!("couldn't unpack the IPA: {e}"))?;
            continue;
        }
        if let Some(parent) = out.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("couldn't unpack the IPA: {e}"))?;
        }
        let mut data = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut data).map_err(|e| format!("couldn't unpack the IPA: {e}"))?;
        std::fs::write(&out, &data).map_err(|e| format!("couldn't unpack the IPA: {e}"))?;
        #[cfg(unix)]
        if let Some(mode) = entry.unix_mode() {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&out, std::fs::Permissions::from_mode(mode));
        }
    }
    let payload = work.join("Payload");
    std::fs::read_dir(&payload)
        .map_err(|e| format!("that IPA has no Payload folder: {e}"))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .find(|p| p.extension().map(|x| x == "app").unwrap_or(false))
        .ok_or_else(|| "that IPA has no app inside Payload".to_string())
}

// ---------------------------------------------------------------------------------------------
// Signing with the person's own certificate (a .p12 and a .mobileprovision they made), instead
// of an Apple ID. Same signer (isideload::sideload::sign), same install over the link.

/// The parts of a provisioning profile the signer needs, read from its CMS-wrapped plist.
struct ProfileInfo {
    team_id: String,
    team_name: Option<String>,
    app_id: String,
    name: String,
    uuid: String,
    expires: Option<plist::Date>,
    entitlements: plist::Dictionary,
}

fn read_profile(bytes: &[u8]) -> Result<ProfileInfo, String> {
    let start = find(bytes, b"<?xml").ok_or("that file isn't a provisioning profile")?;
    let end = find(&bytes[start..], b"</plist>").ok_or("that file isn't a provisioning profile")? + start + 8;
    let value = plist::Value::from_reader_xml(&bytes[start..end]).map_err(|e| format!("couldn't read the profile: {e}"))?;
    let dict = value.as_dictionary().ok_or("couldn't read the profile")?;
    let entitlements = dict.get("Entitlements").and_then(|v| v.as_dictionary()).cloned().unwrap_or_default();
    let team_id = dict
        .get("TeamIdentifier")
        .and_then(|v| v.as_array())
        .and_then(|a| a.first())
        .and_then(|v| v.as_string())
        .ok_or("the profile has no team")?
        .to_string();
    let app_id = entitlements
        .get("application-identifier")
        .and_then(|v| v.as_string())
        .ok_or("the profile has no app ID")?
        .to_string();
    Ok(ProfileInfo {
        team_name: dict.get("TeamName").and_then(|v| v.as_string()).map(str::to_string),
        name: dict.get("Name").and_then(|v| v.as_string()).unwrap_or("Profile").to_string(),
        uuid: dict.get("UUID").and_then(|v| v.as_string()).unwrap_or_default().to_string(),
        expires: dict.get("ExpirationDate").and_then(|v| v.as_date()),
        team_id,
        app_id,
        entitlements,
    })
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

fn read_identity(p12: &[u8], password: &str) -> Result<isideload::sideload::cert_identity::CertificateIdentity, String> {
    use rsa::pkcs8::DecodePrivateKey;
    use x509_cert::der::Decode;
    let store = p12_keystore::KeyStore::from_pkcs12(p12, password, p12_keystore::Pkcs12ImportPolicy::Relaxed)
        .map_err(|e| format!("couldn't open the certificate (check its password): {e}"))?;
    let (_, chain) = store.private_key_chain().ok_or("the certificate file has no private key")?;
    let cert_der = chain.certs().first().ok_or("the certificate file has no certificate")?.as_der();
    let private_key = rsa::RsaPrivateKey::from_pkcs8_der(chain.key().as_der())
        .map_err(|e| format!("the certificate's key isn't an RSA key MuffinInstaller can use: {e}"))?;
    let certificate = x509_cert::Certificate::from_der(cert_der).map_err(|e| format!("couldn't read the certificate: {e}"))?;
    Ok(isideload::sideload::cert_identity::CertificateIdentity {
        machine_id: String::new(),
        machine_name: "MuffinEMU".to_string(),
        private_key,
        certificate,
    })
}

/// Signs `app_path` (an .app folder the caller can modify; pass a copy) with the person's own certificate
/// and profile, and installs it over `link`. A profile for one exact app ID renames the app to that ID and
/// leaves out its app extensions (the profile can't cover them); `*out_note` then says so (free with
/// muffin_jit_string_free).
#[no_mangle]
pub unsafe extern "C" fn muffin_installer_sign_with_certificate_and_install(
    link: *mut MuffinJitLink,
    app_path: *const c_char,
    p12: *const u8,
    p12_len: usize,
    p12_password: *const c_char,
    profile: *const u8,
    profile_len: usize,
    cb: MjProgress,
    ctx: *mut c_void,
    out_note: *mut *mut c_char,
    out_err: *mut *mut c_char,
) -> i32 {
    init_once();
    if link.is_null() || p12.is_null() || p12_len == 0 || profile.is_null() || profile_len == 0 {
        set_err(out_err, "missing link, certificate or profile");
        return MjStatus::InvalidArg as i32;
    }
    let link = &mut *link;
    let p12 = std::slice::from_raw_parts(p12, p12_len).to_vec();
    let profile_bytes = std::slice::from_raw_parts(profile, profile_len).to_vec();
    let args = (|| {
        Ok::<_, String>((
            PathBuf::from(cstr(app_path, "app_path")?),
            if p12_password.is_null() { String::new() } else { cstr(p12_password, "p12_password")?.to_string() },
        ))
    })();
    let (path, password) = match args {
        Ok(v) => v,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };
    report(cb, ctx, 60, "Reading your certificate");
    let res = crate::run_blocking(async {
        use isideload::dev::app_ids::Profile;
        use isideload::dev::teams::DeveloperTeam;
        use isideload::sideload::application::Application;

        let identity = read_identity(&p12, &password)?;
        let info = read_profile(&profile_bytes)?;
        let team = DeveloperTeam { name: info.team_name.clone(), team_id: info.team_id.clone(), r#type: None, status: None };

        let mut app = Application::new(path.clone()).map_err(|e| format!("couldn't read the app: {e}"))?;
        let main_id = app.main_bundle_id().map_err(|e| format!("couldn't read the app's ID: {e}"))?;
        // "TEAMID.com.example.app", "TEAMID.com.example.*" or "TEAMID.*".
        let pattern = info.app_id.strip_prefix(&format!("{}.", info.team_id)).unwrap_or(&info.app_id).to_string();
        let mut note = String::new();
        let new_id = if let Some(prefix) = pattern.strip_suffix('*') {
            if prefix.is_empty() || main_id.starts_with(prefix) { main_id.clone() } else { format!("{prefix}muffinemu") }
        } else {
            // An exact app ID covers the main app only: leave the extensions out.
            if !app.bundle.app_extensions().is_empty() {
                let plugins = app.bundle.bundle_dir.join("PlugIns");
                std::fs::remove_dir_all(&plugins).map_err(|e| format!("couldn't leave out the app extensions: {e}"))?;
                app = Application::new(path.clone()).map_err(|e| format!("couldn't read the app: {e}"))?;
                note = "This profile is for one app ID, so the built-in JIT helper was left out. Use a wildcard profile to keep it.".to_string();
            }
            pattern.clone()
        };
        if new_id != main_id {
            app.update_bundle_id(&main_id, &new_id).map_err(|e| format!("couldn't set the app ID: {e}"))?;
        }
        app.bundle.write_info().map_err(|e| format!("couldn't update the app: {e}"))?;
        for ext in app.bundle.app_extensions() {
            ext.write_info().map_err(|e| format!("couldn't update an app extension: {e}"))?;
        }

        let profile = Profile {
            encoded_profile: plist::Data::new(profile_bytes.clone()),
            filename: "embedded.mobileprovision".to_string(),
            provisioning_profile_id: info.uuid.clone(),
            name: info.name.clone(),
            status: "Active".to_string(),
            r#type: String::new(),
            distribution_method: String::new(),
            pro_pro_platorm: None,
            uuid: info.uuid.clone(),
            date_expire: info.expires.unwrap_or_else(|| plist::Date::from(std::time::SystemTime::now())),
            managing_app: None,
            app_id_id: String::new(),
            is_template_profile: false,
            is_team_profile: None,
            is_free_provisioning_profile: None,
        };
        // A wildcard profile's entitlements name "TEAMID.*"; the signature has to name the real ID.
        let entitlements_for = |bundle_id: &str| {
            let mut e = info.entitlements.clone();
            e.insert("application-identifier".to_string(), plist::Value::String(format!("{}.{}", info.team_id, bundle_id)));
            e
        };
        let mut all_profiles = vec![(new_id.clone(), profile.clone(), entitlements_for(&new_id))];
        for ext in app.bundle.app_extensions() {
            if let Some(id) = ext.bundle_identifier() {
                all_profiles.push((id.to_string(), profile.clone(), entitlements_for(id)));
            }
        }

        report(cb, ctx, 61, "Signing MuffinEMU");
        isideload::sideload::sign::sign(
            &mut app,
            &identity,
            &profile,
            &mut all_profiles,
            &None,
            &team,
            None::<fn(f32) -> std::future::Ready<()>>,
        )
        .await
        .map_err(|e| format!("signing failed: {e}"))?;

        report(cb, ctx, 62, "Installing");
        install_app_rsd(&mut link.provider, &mut link.handshake, &app.bundle.bundle_dir, |_| {})
            .await
            .map_err(|e| format!("installing failed: {e}"))?;
        Ok::<String, String>(note)
    });
    let (code, val) = err_out(res, out_err, MjStatus::Internal);
    if let Some(note) = val {
        if !note.is_empty() {
            copy_out(out_note, &note);
        }
        report(cb, ctx, 63, "Installed");
    }
    code
}
