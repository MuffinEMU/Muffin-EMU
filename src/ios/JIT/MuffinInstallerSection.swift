// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// Settings > Storage > MuffinInstaller: the install dashboard. What this copy is signed with and until
// when (however it was installed), how it was installed, the Apple ID, the device link and JIT, and the
// actions: sign in, refresh, update to the latest release, install a signed IPA, refresh automatically.

import BackgroundTasks
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MuffinInstallerModel: ObservableObject {
    enum Sheet: Identifiable {
        case signIn
        case code(textedTo: String?)
        var id: String {
            switch self {
            case .signIn: return "signIn"
            case .code: return "code"
            }
        }
    }

    @Published var signature = InstalledSignature.current
    @Published var appleID = MuffinInstaller.appleID
    @Published var team = UserDefaults.standard.string(forKey: MuffinInstaller.teamKey)
    @Published var signedIn = MuffinInstaller.isSignedIn
    @Published var latestVersion: String?
    @Published var busy = false
    @Published var step: String?
    @Published var statusLine: String?
    @Published var errorLine: String?
    @Published var sheet: Sheet?
    private var codeReply: ((MuffinInstaller.CodeAnswer?) -> Void)?

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var methodText: String {
        switch MuffinInstaller.method {
        case "appleID": return "MuffinInstaller, with your Apple ID"
        case "signedIPA": return "MuffinInstaller, from a signed IPA"
        default:
            return signature.expires == nil
                ? "TrollStore or another ad-hoc install"
                : "Another installer (SideStore, AltStore or a computer)"
        }
    }

    func refresh() {
        signature = InstalledSignature.current
        appleID = MuffinInstaller.appleID
        team = UserDefaults.standard.string(forKey: MuffinInstaller.teamKey)
        signedIn = MuffinInstaller.isSignedIn
        JITPillModel.shared.refresh()
        Task { latestVersion = await MuffinInstaller.latestReleaseVersion() }
    }

    private var callbacks: MuffinInstaller.Callbacks {
        MuffinInstaller.Callbacks(
            step: { [weak self] text in self?.step = text },
            askCode: { [weak self] textedTo, reply in
                guard let self else { reply(nil); return }
                self.codeReply = reply
                self.sheet = .code(textedTo: textedTo)
            })
    }

    func answerCode(_ answer: MuffinInstaller.CodeAnswer?) {
        let reply = codeReply
        codeReply = nil
        sheet = nil
        reply?(answer)
    }

    /// A sheet closed without an answer (swiped away): cancel whatever is waiting for a code.
    func sheetDismissed() {
        if let reply = codeReply {
            codeReply = nil
            reply(nil)
        }
    }

    private func run(_ start: String, _ work: @escaping (MuffinInstaller.Callbacks) throws -> String) {
        guard !busy else { return }
        busy = true
        step = start
        statusLine = nil
        errorLine = nil
        let callbacks = self.callbacks
        Task.detached(priority: .userInitiated) {
            let result = Result { try work(callbacks) }
            await MainActor.run {
                self.busy = false
                self.step = nil
                switch result {
                case .success(let message): self.statusLine = message
                case .failure(let error):
                    self.errorLine = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                self.refresh()
            }
        }
    }

    func signIn(appleID: String, password: String) {
        run("Signing in…") { callbacks in
            let team = try MuffinInstaller.signIn(appleID: appleID, password: password, callbacks: callbacks)
            return team.isEmpty ? "Signed in." : "Signed in. MuffinEMU signs with \(team)."
        }
    }

    func signOut() {
        MuffinInstaller.signOut()
        MuffinInstallerAutoRefresh.cancel()
        statusLine = "Signed out. Your password is removed from this device."
        refresh()
    }

    func refreshNow() {
        let app = Bundle.main.bundleURL
        run("Refreshing…") { callbacks in
            try MuffinInstaller.signAndInstall(appPath: app, callbacks: callbacks)
            return "Refreshed."
        }
    }

    func updateToLatest() {
        guard !busy else { return }
        busy = true
        step = "Downloading the latest release…"
        errorLine = nil
        statusLine = nil
        Task {
            do {
                let ipa = try await MuffinInstaller.downloadLatestRelease()
                busy = false
                run("Installing the update…") { callbacks in
                    try MuffinInstaller.signAndInstall(appPath: ipa, callbacks: callbacks)
                    return "Updated."
                }
            } catch {
                busy = false
                step = nil
                errorLine = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func installSigned(_ picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("MuffinInstaller-signed.ipa")
        do {
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: picked, to: copy)
        } catch {
            errorLine = "Couldn't read that IPA: \(error.localizedDescription)"
            return
        }
        run("Installing…") { callbacks in
            try MuffinInstaller.installSigned(ipa: copy, callbacks: callbacks)
            return "Installed."
        }
    }
}

struct MuffinInstallerSection: View {
    @StateObject private var model = MuffinInstallerModel()
    @ObservedObject private var pill = JITPillModel.shared
    @AppStorage(MuffinInstaller.autoRefreshKey) private var autoRefresh = false
    @AppStorage(MuffinInstaller.anisetteKey) private var anisetteURL = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirm: Confirm?
    @State private var pickingIPA = false

    private enum Confirm: Identifiable {
        case refresh, update
        var id: Int { self == .refresh ? 0 : 1 }
    }

    var body: some View {
        Section {
            if MuffinInstaller.isAvailable {
                content
            } else {
                Text("MuffinInstaller needs iOS 17.4 or later.")
                    .font(.system(size: 13))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        } header: {
            SettingsSectionHeader("MuffinInstaller", icon: "arrow.down.app", accent: .system)
        } footer: {
            Text("MuffinInstaller signs and installs MuffinEMU with your own Apple ID, right on this device, over the same tunnel as built-in JIT. Your password stays in this device's Keychain and goes only to Apple. A free Apple ID signs for 7 days; MuffinInstaller can renew it on its own.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear(perform: model.refresh)
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.refresh() }
        }
        .onChange(of: autoRefresh) { on in
            if on { MuffinInstallerAutoRefresh.schedule() } else { MuffinInstallerAutoRefresh.cancel() }
        }
        .sheet(item: $model.sheet, onDismiss: model.sheetDismissed) { sheet in
            switch sheet {
            case .signIn: InstallerSignInSheet(model: model)
            case .code(let textedTo): InstallerCodeSheet(model: model, textedTo: textedTo)
            }
        }
        .confirmationDialog("MuffinEMU closes when its new copy installs. Open it again afterwards.",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button(confirm == .update ? "Update" : "Refresh") {
                if confirm == .update { model.updateToLatest() } else { model.refreshNow() }
                confirm = nil
            }
            Button("Cancel", role: .cancel) { confirm = nil }
        }
        .fileImporter(isPresented: $pickingIPA, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { result in
            if case .success(let url) = result { model.installSigned(url) }
        }
    }

    @ViewBuilder
    private var content: some View {
        signatureRow
        row("Installed with", model.methodText)
        if let id = model.appleID, model.signedIn {
            row("Apple ID", model.team.map { "\(id) (\($0))" } ?? id)
        }
        row("Pairing file", JITPairing.isImported ? "Imported" : "Missing")
        row("JIT", jitText)
        row("This version", versionText)

        if model.signedIn {
            Toggle(isOn: $autoRefresh) {
                Text("Refresh automatically")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            Button { confirm = .refresh } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
                .disabled(model.busy)
            if let latest = model.latestVersion, latest != model.currentVersion {
                Button { confirm = .update } label: { Label("Update to \(latest)", systemImage: "arrow.down.circle") }
                    .disabled(model.busy)
            }
            Button(role: .destructive) { model.signOut() } label: {
                Label("Sign out", systemImage: "person.crop.circle.badge.xmark")
            }
            .disabled(model.busy)
        } else {
            Button { model.sheet = .signIn } label: {
                Label("Sign in with your Apple ID", systemImage: "person.crop.circle")
            }
            .disabled(model.busy)
        }
        Button { pickingIPA = true } label: { Label("Install a signed IPA", systemImage: "square.and.arrow.down") }
            .disabled(model.busy)

        if let step = model.step {
            HStack(spacing: 8) {
                ProgressView()
                Text(step).font(.system(size: 13))
            }
        }
        if let status = model.statusLine {
            Text(status).font(.footnote).foregroundColor(MuffinTheme.accentText)
        }
        if let error = model.errorLine {
            Text(error)
                .font(.footnote)
                .foregroundColor(MuffinTheme.cautionText)
                .fixedSize(horizontal: false, vertical: true)
        }
        DisclosureGroup("Anisette server") {
            TextField("Default server", text: $anisetteURL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)
            Text("Apple's sign-in needs anisette data. Leave this empty for the default server, or enter your own.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
        }
    }

    private var jitText: String {
        switch pill.state {
        case .active: return "On"
        case .off: return "Off"
        case .attention: return pill.problem ?? "Needs attention"
        }
    }

    private var versionText: String {
        guard let latest = model.latestVersion else { return model.currentVersion }
        return model.currentVersion + (latest == model.currentVersion ? " (latest)" : " (latest is \(latest))")
    }

    private var signatureRow: some View {
        let sig = model.signature
        var text = "No expiry"
        if let expires = sig.expires {
            let days = sig.daysLeft ?? 0
            text = DateFormatter.localizedString(from: expires, dateStyle: .medium, timeStyle: .short)
                + (days >= 0 ? " (\(days) day\(days == 1 ? "" : "s") left)" : " (expired)")
        }
        let warn = (sig.daysLeft ?? 99) < 2
        return HStack {
            Text("Signed until").font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(warn ? MuffinTheme.cautionText : MuffinTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(MuffinTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct InstallerSignInSheet: View {
    @ObservedObject var model: MuffinInstallerModel
    @Environment(\.dismiss) private var dismiss
    @State private var appleID = MuffinInstaller.appleID ?? ""
    @State private var password = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Apple ID (email)", text: $appleID)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Your password is checked with Apple and kept in this device's Keychain, so MuffinInstaller can refresh MuffinEMU. It isn't sent anywhere else.")
                }
                if let step = model.step {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(step)
                    }
                }
                if let error = model.errorLine {
                    Text(error)
                        .foregroundColor(MuffinTheme.cautionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign in") {
                        model.signIn(appleID: appleID.trimmingCharacters(in: .whitespaces), password: password)
                    }
                    .disabled(appleID.isEmpty || password.isEmpty || model.busy)
                }
            }
            .onChange(of: model.signedIn) { signedIn in
                if signedIn { dismiss() }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct InstallerCodeSheet: View {
    @ObservedObject var model: MuffinInstallerModel
    let textedTo: String?
    @State private var code = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Verification code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                } footer: {
                    Text(textedTo.map { "Apple sent a code by text to \($0)." } ?? "Apple sent a code to your other devices.")
                }
                if textedTo != nil {
                    Button("Send it to my devices instead") { model.answerCode(.sendToDevices) }
                }
            }
            .navigationTitle("Verification code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.answerCode(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { model.answerCode(.code(code)) }
                        .disabled(code.count < 6)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// Refreshes MuffinEMU in the background before its signature runs out, when the person turned it on.
/// It never asks for a two-factor code in the background: if Apple wants one, it stops, and the
/// dashboard asks the next time it's opened.
enum MuffinInstallerAutoRefresh {
    static let identifier = "com.void.muffinemu.refresh"

    /// Call once while the app launches.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task)
        }
    }

    static func schedule() {
        guard UserDefaults.standard.bool(forKey: MuffinInstaller.autoRefreshKey), MuffinInstaller.isSignedIn else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        // Two days before the signature ends (a free Apple ID's lasts 7), and never sooner than an hour from now.
        let expires = InstalledSignature.current.expires ?? Date().addingTimeInterval(5 * 86_400)
        request.earliestBeginDate = max(expires.addingTimeInterval(-2 * 86_400), Date().addingTimeInterval(3_600))
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    private static func handle(_ task: BGProcessingTask) {
        task.expirationHandler = { schedule() }
        let worker = Thread {
            let callbacks = MuffinInstaller.Callbacks(step: { _ in }, askCode: { _, reply in reply(nil) })
            do {
                try MuffinInstaller.signAndInstall(appPath: Bundle.main.bundleURL, callbacks: callbacks)
                task.setTaskCompleted(success: true)
            } catch {
                schedule()
                task.setTaskCompleted(success: false)
            }
        }
        worker.start()
    }
}
