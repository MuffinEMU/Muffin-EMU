// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// The host side of built-in JIT: gather what the helper needs, launch it, and keep
// the result. The actual device-link work runs in the helper extension; the host only
// assembles the request (its own PID, the pairing file, the TXM and DDI-format facts)
// and reads the result and log back.

import Foundation

@MainActor
final class JITCoordinator: ObservableObject {
    static let shared = JITCoordinator()

    /// The helper extension's bundle identifier (see the helper's Info.plist).
    static let helperIdentifier = "com.void.muffinemu.jithelper"

    @Published var isRunning = false
    @Published var lastMessage: String?
    /// The most recent helper log, folded into Copy bug report.
    @Published private(set) var lastLog: [String] = []

    enum CoordinatorError: LocalizedError {
        case oldOS
        case liveContainer
        case noEntitlement
        case noPairing
        case helper(String)

        var errorDescription: String? {
            switch self {
            case .oldOS:
                return "Built-in JIT needs iOS 17.4 or later."
            case .liveContainer:
                return "Built-in JIT can't run inside LiveContainer. Open MuffinEMU on its own, or use a JIT enabler."
            case .noEntitlement:
                return "This install doesn't have get-task-allow, so JIT can't attach. Reinstall MuffinEMU with a signing method that keeps it."
            case .noPairing:
                return "Import a pairing file first (or pair on this device on iOS 27)."
            case .helper(let message):
                return message
            }
        }
    }

    /// Runs the full enable flow for this process. Returns the final status line.
    @discardableResult
    func enableJIT() async throws -> String {
        guard JITEnvironment.meetsMinimumOS else { throw CoordinatorError.oldOS }
        guard !JITEnvironment.isLiveContainer else { throw CoordinatorError.liveContainer }
        guard JITEntitlement.hasGetTaskAllow else { throw CoordinatorError.noEntitlement }
        guard let pairing = JITPairing.read() else { throw CoordinatorError.noPairing }

        let request = JITHelperRequest(
            targetPID: getpid(),
            pairingFile: pairing,
            deviceIP: JITHelperRequest.defaultDeviceIP,
            rsdPort: JITHelperRequest.defaultRSDPort,
            usesCryptexDDI: JITEnvironment.usesCryptexDDI,
            txm: JITEnvironment.isTXM)
        let requestData = try JSONEncoder().encode(request)

        isRunning = true
        defer { isRunning = false }

        let resultData = try await runHelper(requestData)
        let result = try JSONDecoder().decode(JITHelperResult.self, from: resultData)
        lastLog = result.log
        lastMessage = result.message
        if !result.success {
            throw CoordinatorError.helper(result.message)
        }
        return result.message
    }

    /// The JIT log for the bug report: the last run's stages, newest run only.
    var bugReportLines: [String] {
        guard !lastLog.isEmpty else { return [] }
        return ["--- built-in JIT ---"] + lastLog
    }

    private func runHelper(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            MuffinJITLauncher.run(withExtensionIdentifier: Self.helperIdentifier, requestData: data) { resultData, error in
                if let resultData {
                    continuation.resume(returning: resultData)
                } else {
                    let message = error?.localizedDescription ?? "The JIT helper didn't respond."
                    continuation.resume(throwing: CoordinatorError.helper(message))
                }
            }
        }
    }
}
