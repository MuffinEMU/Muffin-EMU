// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// The built-in JIT setup page: the status, the live checks with a fix for each, and
// the one button that turns JIT on. The work runs in the helper; this view assembles
// the request through JITCoordinator and shows what came back.

import SwiftUI
import UniformTypeIdentifiers

/// One live check with its state and, where it helps, what to do about it.
fileprivate struct JITCheck: Identifiable {
    enum State { case checking, ok, warn, info }
    let id: String
    let title: String
    let state: State
    let detail: String
}

@MainActor
final class BuiltInJITModel: ObservableObject {
    @Published var jitActive = JITStatus.isActive
    @Published var pairingImported = JITPairing.isImported
    @Published var reachable: Bool? = nil
    @Published fileprivate var checks: [JITCheck] = []
    @Published var running = false
    @Published var statusLine: String?
    @Published var errorLine: String?

    func refresh() {
        jitActive = JITStatus.isActive
        pairingImported = JITPairing.isImported
        rebuildChecks()
        JITReachability.check { [weak self] ok in
            self?.reachable = ok
            self?.rebuildChecks()
        }
    }

    private func rebuildChecks() {
        var list: [JITCheck] = []

        list.append(JITCheck(
            id: "os",
            title: "iOS 17.4 or later",
            state: JITEnvironment.meetsMinimumOS ? .ok : .warn,
            detail: JITEnvironment.meetsMinimumOS ? "" : "Built-in JIT needs iOS 17.4 or later."))

        if JITEnvironment.isLiveContainer {
            list.append(JITCheck(id: "lc", title: "Not in LiveContainer", state: .warn,
                detail: "You're running inside LiveContainer, where the attach can't work. Open MuffinEMU on its own, or use a JIT enabler."))
        }

        list.append(JITCheck(
            id: "gta",
            title: "App can be debugged",
            state: JITEntitlement.hasGetTaskAllow ? .ok : .warn,
            detail: JITEntitlement.hasGetTaskAllow ? "get-task-allow is set."
                : "This install has no get-task-allow, so JIT can't attach. Reinstall with a signing method that keeps it."))

        list.append(JITCheck(
            id: "pair",
            title: "Pairing file",
            state: pairingImported ? .ok : .warn,
            detail: pairingImported ? "A pairing file is imported."
                : "Import a pairing file, or pair on this device (iOS 27)."))

        let reachState: JITCheck.State = reachable == nil ? .checking : (reachable == true ? .ok : .warn)
        list.append(JITCheck(
            id: "tunnel",
            title: "Tunnel reachable",
            state: reachState,
            detail: reachable == false ? "Couldn't reach \(JITHelperRequest.defaultDeviceIP):\(JITHelperRequest.defaultRSDPort). Turn on LocalDevVPN (StosVPN) and try again." : ""))

        list.append(JITCheck(
            id: "txm",
            title: JITEnvironment.isTXM ? "TXM: on this device" : "TXM: not on this device",
            state: .info,
            detail: JITEnvironment.isTXM
                ? "The recompiler prepares each code region through the debugger. MuffinEMU does this itself."
                : "Attaching once is enough on this device."))

        checks = list
    }

    func enable() {
        guard !running else { return }
        running = true
        errorLine = nil
        statusLine = "Setting up JIT…"
        Task {
            do {
                let message = try await JITCoordinator.shared.enableJIT()
                statusLine = message
                errorLine = nil
            } catch {
                statusLine = nil
                errorLine = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            running = false
            refresh()
        }
    }

    func importPairing(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try JITPairing.store(data)
            errorLine = nil
            statusLine = "Pairing file imported."
        } catch {
            errorLine = "Couldn't import that pairing file: \(error.localizedDescription)"
        }
        refresh()
    }
}

/// The JIT page content. Built-in setup first, with a JIT enabler offered as an
/// alternative below (see JITEnablerSection).
struct BuiltInJITSection: View {
    @StateObject private var model = BuiltInJITModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false

    var body: some View {
        Section {
            statusRow
            ForEach(model.checks) { check in
                checkRow(check)
            }
            if let status = model.statusLine {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(MuffinTheme.accentText)
            }
            if let error = model.errorLine {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(MuffinTheme.cautionText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.enable()
            } label: {
                HStack {
                    if model.running { ProgressView().padding(.trailing, 4) }
                    Text(model.running ? "Setting up JIT…" : "Turn JIT on")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
            .disabled(model.running || model.jitActive)

            Button("Import pairing file") { importing = true }
                .disabled(model.running)
        } header: {
            SettingsSectionHeader("Built-in JIT", icon: "bolt.fill", accent: .core)
        } footer: {
            Text("MuffinEMU turns JIT on itself over the device's own debug tunnel, so games run with the fast recompiler. It needs LocalDevVPN (StosVPN) and a pairing file. On iOS 27 you can pair right on this device.")
        }
        .onAppear(perform: model.refresh)
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.refresh() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .xml, .data]) { result in
            if case .success(let url) = result { model.importPairing(url) }
        }
    }

    private var statusRow: some View {
        HStack {
            Image(systemName: model.jitActive ? "bolt.fill" : "bolt.slash.fill")
                .foregroundColor(model.jitActive ? MuffinTheme.accentText : MuffinTheme.cautionText)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.jitActive ? "JIT is active" : "JIT is off")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(model.jitActive ? MuffinTheme.accentText : MuffinTheme.cautionText)
                Text(model.jitActive ? "Games run with the fast recompiler."
                     : "Games run with the slower interpreter until JIT is on.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func checkRow(_ check: JITCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            icon(for: check.state)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.system(size: 14, weight: .medium))
                if !check.detail.isEmpty {
                    Text(check.detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func icon(for state: JITCheck.State) -> some View {
        switch state {
        case .checking: ProgressView()
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundColor(MuffinTheme.accentText)
        case .warn: Image(systemName: "exclamationmark.circle.fill").foregroundColor(MuffinTheme.cautionText)
        case .info: Image(systemName: "info.circle").foregroundColor(.secondary)
        }
    }
}
