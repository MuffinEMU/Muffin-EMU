// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// The request and result that cross from the host app to the JIT helper extension.
// Both are plain Codable so they can ride whatever transport the launch uses; the
// host encodes a request to Data, the helper decodes it, runs the device-link work,
// and returns an encoded result. Pairing data crosses here as bytes the helper writes
// to a short-lived file and deletes right after; it is never logged.

import Foundation

/// What the host asks the helper to do: enable JIT for a process, having prepared the
/// pieces the helper can't get on its own (the pairing file, the downloaded DDI).
struct JITHelperRequest: Codable {
    /// The process to enable JIT for — the host app itself (`getpid()` on the host side).
    var targetPID: Int32
    /// The device pairing file bytes (an RpPairingFile).
    var pairingFile: Data
    /// The tunnel endpoint. Defaults match LocalDevVPN's loopback.
    var deviceIP: String
    var rsdPort: UInt16
    /// iOS 26.4+ uses the cryptex DDI; earlier uses the personalized image. The helper
    /// downloads the matching Developer Disk Image into its own container and caches it
    /// there, so nothing about the DDI has to cross the process boundary.
    var usesCryptexDDI: Bool
    /// Whether this device enforces TXM, so the breakpoint protocol must run.
    var txm: Bool

    static let defaultDeviceIP = "10.7.0.1"
    static let defaultRSDPort: UInt16 = 49152
}

/// How the helper did. `log` is the ordered stage lines, which the host folds into
/// Copy bug report. `message` is the final line — "JIT is active" or the error.
struct JITHelperResult: Codable {
    var success: Bool
    var message: String
    var log: [String]

    static func failure(_ message: String, log: [String] = []) -> JITHelperResult {
        JITHelperResult(success: false, message: message, log: log + [message])
    }
}
