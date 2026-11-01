// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// On-device pairing (iOS 27 and later). From iOS 27 the device itself starts a pairing to
// a "pairable host" it finds over Bonjour: the person taps it in iOS, and types the code
// the host shows. Here the host is MuffinEMU, on the same device, so no computer is needed
// to make the pairing file built-in JIT uses.
//
// It runs in the app, not the helper extension, because the code has to appear on screen
// while iOS waits for it. The pairing code lives in MuffinJITPairing.framework (built from
// the same device-link library as the helper, by ci/build-jit-ffi.sh). The framework is
// embedded but not linked: it needs iOS 17.4 and the app supports iOS 15, so it's opened
// with dlopen only on iOS 27, and older systems never load it.
//
// The library binds the pairing port; this file publishes it through the system's Bonjour
// (NetService), because sending mDNS from the library's own sockets would need the
// multicast entitlement, which sideloaded apps can't have.

import Foundation

enum JITOnDevicePairing {
    /// iOS 27 or later, with the pairing framework in the app. Everything about on-device
    /// pairing is hidden when this is false.
    static var isAvailable: Bool {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)) else { return false }
        return FileManager.default.fileExists(atPath: libraryPath)
    }

    private static var libraryPath: String {
        (Bundle.main.privateFrameworksPath ?? "") + "/MuffinJITPairing.framework/MuffinJITPairing"
    }

    enum Failure: LocalizedError {
        case unavailable
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Pairing on this device needs iOS 27 or later."
            case .failed(let message): return message
            }
        }
    }

    // The C entry points, as the header declares them (muffin_jit.h).
    private typealias PinFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
    private typealias AdvertiseFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?,
                                                    UnsafePointer<CChar>?, UInt16, UnsafePointer<CChar>?) -> Void
    private typealias ProgressFn = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void
    private typealias PairFn = @convention(c) (
        UnsafePointer<CChar>?, UnsafePointer<CChar>?, UInt32,
        PinFn?, UnsafeMutableRawPointer?,
        AdvertiseFn?, UnsafeMutableRawPointer?,
        ProgressFn?, UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias BytesFreeFn = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void
    private typealias StringFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    /// What the pairing reports while it runs. Called on the main queue.
    struct Callbacks {
        var code: (String) -> Void
        var step: (String) -> Void
    }

    /// One pairing attempt: holds the callbacks and the Bonjour advertisement while the
    /// library waits for iOS. Passed to C as the context pointer.
    private final class Session: NSObject {
        let callbacks: Callbacks
        var service: NetService?
        var cancelled = false
        init(_ callbacks: Callbacks) { self.callbacks = callbacks }

        func publish(type: String, name: String, port: UInt16, txt: String) {
            // "_remotepairing-pairable-host._tcp.local." -> type "_remotepairing-pairable-host._tcp."
            let bareType = type.hasSuffix("local.") ? String(type.dropLast("local.".count)) : type
            var records: [String: Data] = [:]
            for line in txt.split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                records[String(line[..<eq])] = Data(line[line.index(after: eq)...].utf8)
            }
            DispatchQueue.main.async {
                guard !self.cancelled else { return }
                let service = NetService(domain: "local.", type: bareType, name: name, port: Int32(port))
                service.setTXTRecord(NetService.data(fromTXTRecord: records))
                service.publish()
                self.service = service
            }
        }

        func stop() {
            DispatchQueue.main.async {
                self.service?.stop()
                self.service = nil
            }
        }
    }

    private static var current: Session?

    /// Waits up to `timeout` for iOS to start a pairing with MuffinEMU, shows the code
    /// through `callbacks`, and returns the pairing file. Blocks, so call it off the main thread.
    static func pair(timeout: TimeInterval = 180, callbacks: Callbacks) throws -> Data {
        guard isAvailable, let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            throw Failure.unavailable
        }
        guard let pairSym = dlsym(handle, "muffin_jit_pair_on_device"),
              let bytesFreeSym = dlsym(handle, "muffin_jit_bytes_free"),
              let stringFreeSym = dlsym(handle, "muffin_jit_string_free") else {
            throw Failure.failed("The pairing component in this build is incomplete.")
        }
        let pairFn = unsafeBitCast(pairSym, to: PairFn.self)
        let bytesFree = unsafeBitCast(bytesFreeSym, to: BytesFreeFn.self)
        let stringFree = unsafeBitCast(stringFreeSym, to: StringFreeFn.self)

        let session = Session(callbacks)
        current = session
        defer {
            session.stop()
            if current === session { current = nil }
        }
        let ctx = Unmanaged.passUnretained(session).toOpaque()

        let onCode: PinFn = { ctx, pin in
            guard let ctx, let pin else { return }
            let session = Unmanaged<Session>.fromOpaque(ctx).takeUnretainedValue()
            let code = String(cString: pin)
            DispatchQueue.main.async { if !session.cancelled { session.callbacks.code(code) } }
        }
        let onAdvertise: AdvertiseFn = { ctx, type, name, port, txt in
            guard let ctx, let type, let name else { return }
            let session = Unmanaged<Session>.fromOpaque(ctx).takeUnretainedValue()
            session.publish(type: String(cString: type), name: String(cString: name), port: port,
                            txt: txt.map { String(cString: $0) } ?? "")
        }
        let onStep: ProgressFn = { ctx, _, message in
            guard let ctx, let message else { return }
            let session = Unmanaged<Session>.fromOpaque(ctx).takeUnretainedValue()
            let text = String(cString: message)
            DispatchQueue.main.async { if !session.cancelled { session.callbacks.step(text) } }
        }

        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        var outErr: UnsafeMutablePointer<CChar>?
        let status = pairFn("MuffinEMU", JITOnDevicePairing.modelIdentifier, UInt32(timeout * 1000),
                            onCode, ctx, onAdvertise, ctx, onStep, ctx, &outPtr, &outLen, &outErr)
        if session.cancelled {
            if let outPtr { bytesFree(outPtr, outLen) }
            if let outErr { stringFree(outErr) }
            throw CancellationError()
        }
        guard status == 0, let outPtr, outLen > 0 else {
            let message = outErr.map { String(cString: $0) } ?? "pairing did not complete (code \(status))"
            if let outErr { stringFree(outErr) }
            throw Failure.failed("Pairing didn't finish: \(message).")
        }
        defer { bytesFree(outPtr, outLen) }
        return Data(bytes: outPtr, count: outLen)
    }

    /// Stops advertising, so iOS no longer offers MuffinEMU. The waiting call ends at its
    /// timeout; its result is thrown away.
    static func cancel() {
        guard let session = current else { return }
        session.cancelled = true
        session.stop()
    }

    /// This device's model identifier (e.g. "iPad8,11"), which the pairable host presents.
    private static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
