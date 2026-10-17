// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// Host-side helpers for built-in JIT: where the pairing file lives, whether the
// tunnel is reachable, which DDI format this OS uses, and the LiveContainer and
// version facts the setup screen checks. None of this touches the device-link
// library — that only ever runs in the helper — so the host can show its checks
// without loading anything that needs iOS 17.4.

import Foundation
import Network

/// The imported pairing file. Stored in the app's Documents so it survives updates
/// and can be replaced from Files; never logged.
enum JITPairing {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("MuffinJIT", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("pairingFile.plist") }

    static var isImported: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Replaces the stored pairing file atomically. `data` is bytes read from the
    /// picked file (with security-scoped access) or produced by on-device pairing.
    static func store(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    static func read() -> Data? { try? Data(contentsOf: fileURL) }

    static func remove() { try? FileManager.default.removeItem(at: fileURL) }
}

/// Facts the setup screen checks, none of which need the helper.
enum JITEnvironment {
    /// JIT needs iOS 17.4 or later.
    static var meetsMinimumOS: Bool {
        if #available(iOS 17.4, *) { return true } else { return false }
    }

    /// LiveContainer runs apps in a way that breaks the attach; detect it so the
    /// setup screen can explain rather than fail silently.
    static var isLiveContainer: Bool { getenv("LC_HOME_PATH") != nil }

    /// iOS 26.4 is the cutover from the personalized DDI to the cryptex DDI.
    static var usesCryptexDDI: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 26 || (v.majorVersion == 26 && v.minorVersion >= 4)
    }

    /// Whether this device enforces TXM, so the recompiler must bless each region.
    /// Mirrors ios_has_txm() in CemuBridge.mm via the bridge.
    static var isTXM: Bool { cemu_bridge_has_txm() }
}

/// A quick, host-side reachability check of the tunnel endpoint — a plain TCP connect,
/// so the setup screen can show "tunnel up?" without the device-link library.
enum JITReachability {
    static func check(host: String = JITHelperRequest.defaultDeviceIP,
                      port: UInt16 = JITHelperRequest.defaultRSDPort,
                      timeout: TimeInterval = 3,
                      completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { completion(false); return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "muffin.jit.reach")
        var finished = false
        func finish(_ ok: Bool) {
            queue.async {
                guard !finished else { return }
                finished = true
                connection.cancel()
                DispatchQueue.main.async { completion(ok) }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .cancelled: finish(false)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
}
