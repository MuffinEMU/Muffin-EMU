// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// The JIT helper's engine. It runs inside the helper app extension (the only place
// that links the device-link library), takes a request from the host, and does the
// whole flow: connect over the tunnel, make sure the Developer Disk Image is mounted,
// then enable JIT for the host process. Blocking; the helper calls it on one serial
// background queue, never splitting the ordered steps across threads.

import Foundation

enum JITHelperCore {
    /// Runs the enable flow and collects a log the host can fold into a bug report.
    static func run(_ request: JITHelperRequest) -> JITHelperResult {
        var log: [String] = []
        func note(_ line: String) { if log.last != line { log.append(line) } }

        note("MuffinEMU JIT helper (\(MuffinJIT.version))")
        do {
            let link = try MuffinJITLink(
                pairingFile: request.pairingFile,
                deviceIP: request.deviceIP,
                rsdPort: request.rsdPort,
                usesCryptexDDI: request.usesCryptexDDI,
                progress: { _, message in note(message) })

            if try link.isDDIMounted() {
                note("Developer Disk Image already mounted")
            } else {
                note("Preparing the Developer Disk Image")
                let ddi = try JITDeveloperDiskImage.prepare(cryptex: request.usesCryptexDDI,
                                                            progress: { note($0) })
                switch ddi {
                case .cryptex(let dir):
                    try link.mountCryptexDDI(restoreDir: dir, progress: { _, message in note(message) })
                case .personalized(let image, let trustcache, let manifest):
                    try link.mountPersonalizedDDI(imagePath: image, trustcachePath: trustcache,
                                                  manifestPath: manifest,
                                                  progress: { _, message in note(message) })
                }
            }

            try link.enableJIT(targetPID: request.targetPID, txm: request.txm,
                               progress: { _, message in note(message) })

            note("JIT is active")
            return JITHelperResult(success: true, message: "JIT is active", log: log)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failure(message, log: log)
        }
    }

    /// Decodes a request, runs it, and encodes the result — the shape the transport uses.
    static func runData(_ data: Data) -> Data {
        let result: JITHelperResult
        do {
            let request = try JSONDecoder().decode(JITHelperRequest.self, from: data)
            result = run(request)
        } catch {
            result = .failure("The helper couldn't read the request: \(error.localizedDescription)")
        }
        return (try? JSONEncoder().encode(result)) ?? Data()
    }
}
