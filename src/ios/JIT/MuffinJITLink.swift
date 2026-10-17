// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// Swift over the muffin-jit C ABI (jit/muffin-jit, built on idevice). This compiles
// into the JIT helper app extension, never the host app, because the attach has to
// run from a second process. Every call is synchronous and blocking; the helper runs
// them on one serial queue.

import Foundation
import MuffinJitFFI

/// What a device-link call failed at. The message is already human-readable.
enum MuffinJITError: LocalizedError {
    case invalidArgument(String)
    case unreachable(String)
    case pairingInvalid(String)
    case ddiFailed(String)
    case attachFailed(String)
    case protocolFailed(String)
    case notMounted(String)
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let m), .unreachable(let m), .pairingInvalid(let m),
             .ddiFailed(let m), .attachFailed(let m), .protocolFailed(let m),
             .notMounted(let m), .failure(let m):
            return m
        }
    }

    static func make(_ code: Int32, _ message: String) -> MuffinJITError {
        switch code {
        case -1: return .invalidArgument(message)
        case -2: return .unreachable(message)
        case -3: return .pairingInvalid(message)
        case -4: return .ddiFailed(message)
        case -5: return .attachFailed(message)
        case -6: return .protocolFailed(message)
        case -7: return .notMounted(message)
        default: return .failure(message)
        }
    }
}

/// Holds a progress closure so a `@convention(c)` trampoline can reach it through a
/// context pointer.
private final class ProgressBox {
    let onStage: (Int32, String) -> Void
    init(_ onStage: @escaping (Int32, String) -> Void) { self.onStage = onStage }
}

private let progressTrampoline: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void = { ctx, stage, message in
    guard let ctx else { return }
    let box = Unmanaged<ProgressBox>.fromOpaque(ctx).takeUnretainedValue()
    box.onStage(stage, message.map { String(cString: $0) } ?? "")
}

/// Runs a C call that returns a status code and may write an `out_err` string.
private func check(_ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32) throws {
    var err: UnsafeMutablePointer<CChar>?
    let code = body(&err)
    defer { if let err { muffin_jit_string_free(err) } }
    if code != 0 {
        throw MuffinJITError.make(code, err.map { String(cString: $0) } ?? "unknown error")
    }
}

/// Runs a C call that also takes a progress callback, wiring a Swift closure through.
private func checkProgress(
    _ progress: ((Int32, String) -> Void)?,
    _ body: (MuffinJitProgress?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
) throws {
    if let progress {
        let box = ProgressBox(progress)
        let ctx = Unmanaged.passRetained(box).toOpaque()
        defer { Unmanaged<ProgressBox>.fromOpaque(ctx).release() }
        try check { body(progressTrampoline, ctx, $0) }
    } else {
        try check { body(nil, nil, $0) }
    }
}

/// A connected device-link session. Create it with a pairing file and the tunnel
/// endpoint; use it to check or mount the DDI and to enable JIT. Frees the native
/// session on deinit.
final class MuffinJITLink {
    private let handle: OpaquePointer

    /// Opens the session: pair-verify, tunnel, RSD handshake.
    init(pairingFile: Data, deviceIP: String, rsdPort: UInt16, usesCryptexDDI: Bool,
         progress: ((Int32, String) -> Void)? = nil) throws {
        var created: OpaquePointer?
        try pairingFile.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            try checkProgress(progress) { cb, ctx, err in
                muffin_jit_connect(bytes.baseAddress, bytes.count, deviceIP, rsdPort,
                                   usesCryptexDDI ? 1 : 0, cb, ctx, &created, err)
            }
        }
        guard let created else { throw MuffinJITError.failure("the session did not open") }
        handle = created
    }

    deinit { muffin_jit_link_free(handle) }

    /// Whether a Developer Disk Image is already mounted.
    func isDDIMounted() throws -> Bool {
        var mounted: Int32 = 0
        try check { muffin_jit_ddi_mounted(handle, &mounted, $0) }
        return mounted != 0
    }

    /// Mounts the personalized DDI (iOS before 26.4).
    func mountPersonalizedDDI(imagePath: String, trustcachePath: String, manifestPath: String,
                              progress: ((Int32, String) -> Void)? = nil) throws {
        try checkProgress(progress) { cb, ctx, err in
            muffin_jit_mount_personalized(handle, imagePath, trustcachePath, manifestPath, cb, ctx, err)
        }
    }

    /// Installs the cryptex DDI (iOS 26.4+). `restoreDir` holds BuildManifest.plist and payloads.
    func mountCryptexDDI(restoreDir: String, progress: ((Int32, String) -> Void)? = nil) throws {
        try checkProgress(progress) { cb, ctx, err in
            muffin_jit_mount_cryptex(handle, restoreDir, cb, ctx, err)
        }
    }

    /// Enables JIT for the target process. `txm` runs the breakpoint protocol on a TXM device.
    func enableJIT(targetPID: Int32, txm: Bool, progress: ((Int32, String) -> Void)? = nil) throws {
        try checkProgress(progress) { cb, ctx, err in
            muffin_jit_enable(handle, targetPID, txm ? 1 : 0, cb, ctx, err)
        }
    }
}

/// Stateless entry points: the version string, the reachability probe, and on-device pairing.
enum MuffinJIT {
    static var version: String { String(cString: muffin_jit_version()) }

    /// Is the tunnel reachable within the timeout?
    static func probe(deviceIP: String, rsdPort: UInt16, timeoutMs: UInt32) throws {
        try check { muffin_jit_probe(deviceIP, rsdPort, timeoutMs, $0) }
    }

    /// On-device pairing (iOS 27+). Advertises as a pairable host and accepts one
    /// device-initiated pairing. `pin` is called with the setup code to show the user.
    /// Returns the pairing file bytes to store securely.
    static func pairOnDevice(name: String, model: String, timeoutMs: UInt32,
                             pin: @escaping (String) -> Void,
                             progress: ((Int32, String) -> Void)? = nil) throws -> Data {
        final class PinBox { let onPin: (String) -> Void; init(_ f: @escaping (String) -> Void) { onPin = f } }
        let pinTrampoline: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { ctx, code in
            guard let ctx else { return }
            let box = Unmanaged<PinBox>.fromOpaque(ctx).takeUnretainedValue()
            box.onPin(code.map { String(cString: $0) } ?? "")
        }
        let pinBox = PinBox(pin)
        let pinCtx = Unmanaged.passRetained(pinBox).toOpaque()
        defer { Unmanaged<PinBox>.fromOpaque(pinCtx).release() }

        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen: Int = 0
        try checkProgress(progress) { cb, ctx, err in
            muffin_jit_pair_on_device(name, model, timeoutMs, pinTrampoline, pinCtx, cb, ctx, &outPtr, &outLen, err)
        }
        guard let outPtr, outLen > 0 else { throw MuffinJITError.pairingInvalid("no pairing file was produced") }
        defer { muffin_jit_bytes_free(outPtr, outLen) }
        return Data(bytes: outPtr, count: outLen)
    }
}
