// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
//
// The device link: a reachability probe and a connected session over the device's
// RemoteServiceDiscovery endpoint.
//
// On a sideloaded install the endpoint is the LocalDevVPN loopback tunnel (default
// 10.7.0.1:49152). Reaching the device's services over it is a chain: open the raw
// RPPairing socket, pair-verify with the stored pairing file, ask the device for a
// tunnel listener, bring up the TLS-PSK tunnel, and run the software TCP stack over
// it. The RSD handshake and every service connection then ride that adapter.

use std::ffi::{c_char, c_void};
use std::net::{IpAddr, SocketAddr};
use std::time::Duration;

use idevice::remote_pairing::{
    connect_tls_psk_tunnel_native, RemotePairingClient, RpPairingFile, RpPairingSocket,
};
use idevice::rsd::RsdHandshake;
use idevice::tcp::adapter::Adapter;
use idevice::tcp::handle::AdapterHandle;

use crate::ffi::{cstr, report, MjProgress};
use crate::{err_out, set_err, MjStatus};

const HOST_LABEL: &str = "MuffinEMU";

/// A live session: the software-tunnel adapter (the RSD provider for every service)
/// and the completed RSD handshake.
pub struct MuffinJitLink {
    pub(crate) provider: AdapterHandle,
    pub(crate) handshake: RsdHandshake,
    /// Which DDI format this OS uses: true for the iOS 26.4+ cryptex, false for the
    /// pre-26.4 personalized image. Decided on the Swift side from the exact version.
    pub(crate) cryptex: bool,
}

/// TCP-reachability probe of the RSD endpoint. Returns Ok only if a connection is
/// established within `timeout_ms`. This is the "is the tunnel up?" check.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_probe(
    device_ip: *const c_char,
    rsd_port: u16,
    timeout_ms: u32,
    out_err: *mut *mut c_char,
) -> i32 {
    let res = (|| {
        let ip: IpAddr = cstr(device_ip, "device_ip")?
            .parse()
            .map_err(|e| format!("device_ip was not an IP address: {e}"))?;
        crate::run_blocking(async move {
            let fut = tokio::net::TcpStream::connect((ip, rsd_port));
            match tokio::time::timeout(Duration::from_millis(timeout_ms as u64), fut).await {
                Ok(Ok(_)) => Ok(()),
                Ok(Err(e)) => Err(format!("could not reach {ip}:{rsd_port}: {e}")),
                Err(_) => Err(format!("{ip}:{rsd_port} did not answer within {timeout_ms} ms")),
            }
        })
    })();
    err_out(res, out_err, MjStatus::Unreachable).0
}

/// Opens a session: pair-verifies with the given pairing file, brings up the tunnel,
/// and completes the RSD handshake. The returned handle is freed with
/// `muffin_jit_link_free`.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_connect(
    pairing: *const u8,
    pairing_len: usize,
    device_ip: *const c_char,
    rsd_port: u16,
    ddi_cryptex: i32,
    cb: MjProgress,
    ctx: *mut c_void,
    out_link: *mut *mut MuffinJitLink,
    out_err: *mut *mut c_char,
) -> i32 {
    if out_link.is_null() {
        set_err(out_err, "out_link was null");
        return MjStatus::InvalidArg as i32;
    }
    *out_link = std::ptr::null_mut();

    // Pairing data: read into an RpPairingFile and then drop the bytes. Never logged.
    let parsed = (|| {
        if pairing.is_null() || pairing_len == 0 {
            return Err("pairing file was empty".to_string());
        }
        let bytes = std::slice::from_raw_parts(pairing, pairing_len);
        RpPairingFile::from_bytes(bytes).map_err(|e| format!("pairing file could not be read: {e}"))
    })();
    let mut pairing_file = match parsed {
        Ok(p) => p,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::PairingInvalid as i32;
        }
    };

    let ip_res = cstr(device_ip, "device_ip").and_then(|s| {
        s.parse::<IpAddr>()
            .map_err(|e| format!("device_ip was not an IP address: {e}"))
    });
    let ip = match ip_res {
        Ok(ip) => ip,
        Err(e) => {
            set_err(out_err, e);
            return MjStatus::InvalidArg as i32;
        }
    };
    let addr = SocketAddr::new(ip, rsd_port);

    report(cb, ctx, 1, "Connecting to the device over the tunnel");
    let res = crate::run_blocking(async move {
        let stream = tokio::net::TcpStream::connect(addr)
            .await
            .map_err(|e| format!("could not reach the device at {addr}: {e}"))?;
        let conn = RpPairingSocket::new(stream);
        let mut rpc = RemotePairingClient::new(conn, HOST_LABEL);
        // Already paired: pair-verify succeeds and the PIN callback is never used.
        rpc.connect(&mut pairing_file, || async { String::new() })
            .await
            .map_err(|e| format!("the device would not verify this pairing: {e}"))?;

        report(cb, ctx, 2, "Opening the secure tunnel");
        let (provider, handshake) = finish_tunnel(&mut rpc, addr).await?;
        Ok::<_, String>((provider, handshake))
    });

    match res {
        Ok((provider, handshake)) => {
            report(cb, ctx, 3, "Connected");
            let link = Box::new(MuffinJitLink {
                provider,
                handshake,
                cryptex: ddi_cryptex != 0,
            });
            *out_link = Box::into_raw(link);
            MjStatus::Ok as i32
        }
        Err(e) => {
            set_err(out_err, e);
            MjStatus::Unreachable as i32
        }
    }
}

/// Given a verified pairing client, ask the device for a tunnel listener, bring up
/// the TLS-PSK tunnel and the software TCP stack, and hand back the adapter and the
/// RSD handshake that rides it.
async fn finish_tunnel(
    rpc: &mut RemotePairingClient<impl idevice::remote_pairing::RpPairingSocketProvider>,
    connect_addr: SocketAddr,
) -> Result<(AdapterHandle, RsdHandshake), String> {
    let tunnel_port = rpc
        .create_tcp_listener()
        .await
        .map_err(|e| format!("the device would not open a tunnel: {e}"))?;
    let mut tunnel_addr = connect_addr;
    tunnel_addr.set_port(tunnel_port);
    let tunnel_stream = tokio::net::TcpStream::connect(tunnel_addr)
        .await
        .map_err(|e| format!("could not open the tunnel port: {e}"))?;
    let tunnel = connect_tls_psk_tunnel_native(tunnel_stream, rpc.encryption_key())
        .await
        .map_err(|e| format!("the secure tunnel handshake failed: {e}"))?;

    let client_ip: IpAddr = tunnel
        .info
        .client_address
        .parse()
        .map_err(|e| format!("tunnel gave a bad client address: {e}"))?;
    let server_ip: IpAddr = tunnel
        .info
        .server_address
        .parse()
        .map_err(|e| format!("tunnel gave a bad server address: {e}"))?;
    let mtu = tunnel.info.mtu as usize;
    let rsd_port = tunnel.info.server_rsd_port;

    let raw = tunnel.into_inner();
    let mut adapter = Adapter::new(Box::new(raw), client_ip, server_ip);
    adapter.set_mss(mtu.saturating_sub(60));
    let mut handle = adapter.to_async_handle();

    let rsd_stream = handle
        .connect(rsd_port)
        .await
        .map_err(|e| format!("could not reach RSD over the tunnel: {e}"))?;
    let handshake = RsdHandshake::new(rsd_stream)
        .await
        .map_err(|e| format!("the device refused the service handshake: {e}"))?;

    Ok((handle, handshake))
}

/// Frees a link opened by `muffin_jit_connect`.
#[no_mangle]
pub unsafe extern "C" fn muffin_jit_link_free(link: *mut MuffinJitLink) {
    if !link.is_null() {
        drop(Box::from_raw(link));
    }
}
