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
        case certificate
        case versions
        case code(textedTo: String?)
        var id: String {
            switch self {
            case .signIn: return "signIn"
            case .certificate: return "certificate"
            case .versions: return "versions"
            case .code: return "code"
            }
        }
    }

    @Published var signature = InstalledSignature.current
    @Published var appleID = MuffinInstaller.appleID
    @Published var team = UserDefaults.standard.string(forKey: MuffinInstaller.teamKey)
    @Published var signedIn = MuffinInstaller.isSignedIn
    @Published var hasCertificate = MuffinInstaller.hasCertificate
    @Published var latestVersion: String?
    @Published var releases: [MuffinInstaller.Release] = []
    @Published var busy = false
    @Published var step: String?
    @Published var statusLine: String?
    @Published var errorLine: String?
    @Published var sheet: Sheet?
    private var codeReply: ((MuffinInstaller.CodeAnswer?) -> Void)?

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var methodText: String {
        switch MuffinInstaller.method {
        case "appleID": return "MuffinInstaller, with your Apple ID".localized
        case "certificate": return "MuffinInstaller, with your own certificate".localized
        case "signedIPA": return "MuffinInstaller, from a signed IPA".localized
        default:
            return signature.expires == nil
                ? "TrollStore or another ad-hoc install".localized
                : "Another installer (SideStore, AltStore or a computer)".localized
        }
    }

    func refresh() {
        signature = InstalledSignature.current
        appleID = MuffinInstaller.appleID
        team = UserDefaults.standard.string(forKey: MuffinInstaller.teamKey)
        signedIn = MuffinInstaller.isSignedIn
        hasCertificate = MuffinInstaller.hasCertificate
        JITPillModel.shared.refresh()
        Task {
            releases = await MuffinInstaller.releases()
            latestVersion = releases.first(where: { !$0.isPrerelease })?.version
        }
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

    /// A sheet closed without an answer (swiped away): cancel whatever is waiting for a code. Not when one
    /// sheet was swapped for another (sign-in turning into the code sheet), which SwiftUI also reports as a dismissal.
    func sheetDismissed() {
        guard sheet == nil else { return }
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
        run("Signing in…".localized) { callbacks in
            let team = try MuffinInstaller.signIn(appleID: appleID, password: password, callbacks: callbacks)
            return team.isEmpty ? "Signed in.".localized : "Signed in. MuffinEMU signs with \(team)."
        }
    }

    func signOut() {
        MuffinInstaller.signOut()
        MuffinInstallerAutoRefresh.cancel()
        statusLine = "Signed out. Your password is removed from this device.".localized
        refresh()
    }

    func refreshNow() {
        let app = Bundle.main.bundleURL
        run("Refreshing…".localized) { callbacks in
            try MuffinInstaller.resign(appPath: app, callbacks: callbacks)
            return "Refreshed.".localized
        }
    }

    func updateToLatest() {
        guard !busy else { return }
        busy = true
        step = "Downloading the latest release…".localized
        errorLine = nil
        statusLine = nil
        Task {
            do {
                let ipa = try await MuffinInstaller.downloadLatestRelease()
                busy = false
                run("Installing the update…".localized) { callbacks in
                    try MuffinInstaller.resign(appPath: ipa, callbacks: callbacks)
                    return "Updated.".localized
                }
            } catch {
                busy = false
                step = nil
                errorLine = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Keeps the picked certificate, profile and password, then signs and installs MuffinEMU with them.
    func useCertificate(p12: URL, profile: URL, password: String) {
        func read(_ url: URL) throws -> Data {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }
        do {
            try MuffinInstaller.storeCertificate(p12: read(p12), password: password, profile: read(profile))
        } catch {
            errorLine = "Couldn't read those files: \(error.localizedDescription)"
            return
        }
        sheet = nil
        let app = Bundle.main.bundleURL
        run("Signing with your certificate…".localized) { callbacks in
            let note = try MuffinInstaller.signWithCertificateAndInstall(appPath: app, callbacks: callbacks)
            return note ?? "Installed with your certificate.".localized
        }
    }

    func removeCertificate() {
        MuffinInstaller.removeCertificate()
        statusLine = "Your certificate is removed from this device.".localized
        refresh()
    }

    /// Installs any release: newer (an update) or older (a downgrade), signed the way MuffinInstaller signs.
    func install(_ release: MuffinInstaller.Release) {
        guard !busy else { return }
        sheet = nil
        busy = true
        step = String(format: "Downloading MuffinEMU %@…".localized, release.version)
        errorLine = nil
        statusLine = nil
        Task {
            do {
                let ipa = try await MuffinInstaller.download(release)
                busy = false
                run(String(format: "Installing MuffinEMU %@…".localized, release.version)) { callbacks in
                    try MuffinInstaller.resign(appPath: ipa, callbacks: callbacks)
                    return String(format: "MuffinEMU %@ is installed.".localized, release.version)
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
        run("Installing…".localized) { callbacks in
            try MuffinInstaller.installSigned(ipa: copy, callbacks: callbacks)
            return "Installed.".localized
        }
    }
}

struct MuffinInstallerSection: View {
    @StateObject private var model = MuffinInstallerModel()
    @ObservedObject private var pill = JITPillModel.shared
    @AppStorage(MuffinInstaller.autoRefreshKey) private var autoRefresh = false
    @AppStorage(MuffinInstaller.autoUpdateKey) private var autoUpdate = true
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
            case .certificate: InstallerCertificateSheet(model: model)
            case .versions: InstallerVersionsSheet(model: model)
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
        row("Installed with".localized, model.methodText)
        if let id = model.appleID, model.signedIn {
            row("Apple ID".localized, model.team.map { "\(id) (\($0))" } ?? id)
        }
        row("Pairing file".localized, JITPairing.isImported ? "Imported".localized : "Missing".localized)
        row("JIT".localized, jitText)
        row("This version".localized, versionText)

        if model.signedIn || model.hasCertificate {
            Toggle(isOn: $autoRefresh) {
                Text("Refresh automatically")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            if autoRefresh {
                Toggle(isOn: $autoUpdate) {
                    Text("Install updates automatically")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .tint(MuffinTheme.accentText)
            }
            Button { confirm = .refresh } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
                .disabled(model.busy)
            if let latest = model.latestVersion, latest != model.currentVersion {
                Button { confirm = .update } label: { Label("Update to \(latest)", systemImage: "arrow.down.circle") }
                    .disabled(model.busy)
            }
            Button { model.sheet = .versions } label: { Label("Choose a version", systemImage: "list.bullet.rectangle") }
                .disabled(model.busy)
        }
        if model.signedIn {
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
        if model.hasCertificate {
            Button(role: .destructive) { model.removeCertificate() } label: {
                Label("Remove your certificate", systemImage: "trash")
            }
            .disabled(model.busy)
        } else {
            Button { model.sheet = .certificate } label: {
                Label("Use your own certificate", systemImage: "doc.badge.gearshape")
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
        case .active: return "On".localized
        case .off: return "Off".localized
        case .attention: return pill.problem ?? "Needs attention".localized
        }
    }

    private var versionText: String {
        guard let latest = model.latestVersion else { return model.currentVersion }
        return model.currentVersion + (latest == model.currentVersion ? " (latest)" : " (latest is \(latest))")
    }

    private var signatureRow: some View {
        let sig = model.signature
        var text = "No expiry".localized
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

/// Your own certificate: a .p12 with its password and a matching .mobileprovision.
private struct InstallerCertificateSheet: View {
    @ObservedObject var model: MuffinInstallerModel
    @Environment(\.dismiss) private var dismiss
    @State private var p12: URL?
    @State private var profile: URL?
    @State private var password = ""
    @State private var picking: Picking?

    private enum Picking: Identifiable {
        case p12, profile
        var id: Int { self == .p12 ? 0 : 1 }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button { picking = .p12 } label: {
                        row("Certificate (.p12)".localized, p12?.lastPathComponent ?? "Choose…".localized)
                    }
                    SecureField("Certificate password", text: $password)
                        .textContentType(.password)
                    Button { picking = .profile } label: {
                        row("Profile (.mobileprovision)".localized, profile?.lastPathComponent ?? "Choose…".localized)
                    }
                } footer: {
                    Text("Use a development or ad hoc certificate from your own developer account, with a profile that includes this device. A wildcard profile keeps built-in JIT's helper. Both stay on this device, and the password goes into its Keychain.")
                }
                if let error = model.errorLine {
                    Text(error).foregroundColor(MuffinTheme.cautionText).fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Your certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign and install") {
                        if let p12, let profile { model.useCertificate(p12: p12, profile: profile, password: password) }
                    }
                    .disabled(p12 == nil || profile == nil || model.busy)
                }
            }
            .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                          allowedContentTypes: picking == .profile
                              ? [UTType(filenameExtension: "mobileprovision") ?? .data]
                              : [UTType(filenameExtension: "p12") ?? .data, .pkcs12]) { result in
                if case .success(let url) = result {
                    if picking == .profile { profile = url } else { p12 = url }
                }
                picking = nil
            }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(MuffinTheme.brownDarkest)
            Spacer()
            Text(value).foregroundColor(MuffinTheme.secondaryText).lineLimit(1)
        }
    }
}

/// Every release with an IPA: install any of them, newer or older than this one.
private struct InstallerVersionsSheet: View {
    @ObservedObject var model: MuffinInstallerModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: MuffinInstaller.Release?

    var body: some View {
        NavigationView {
            List {
                if model.releases.isEmpty {
                    Text("Couldn't load the list of releases. Check the connection and try again.")
                        .foregroundColor(MuffinTheme.secondaryText)
                }
                ForEach(model.releases) { release in
                    Button { chosen = release } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(release.isPrerelease ? release.title : "MuffinEMU " + release.version)
                                    .foregroundColor(MuffinTheme.brownDarkest)
                                if let date = release.published {
                                    Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                                        .font(.system(size: 12))
                                        .foregroundColor(MuffinTheme.secondaryText)
                                }
                            }
                            Spacer()
                            Text(badge(for: release))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MuffinTheme.secondaryText)
                        }
                    }
                    .disabled(release.version == model.currentVersion)
                }
            }
            .navigationTitle("Choose a version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog(chosen.map { String(format: "Install MuffinEMU %@? MuffinEMU closes when it installs. Your games and saves stay.".localized, $0.version) } ?? "",
                                isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                                titleVisibility: .visible) {
                Button("Install") {
                    if let release = chosen { model.install(release) }
                    chosen = nil
                }
                Button("Cancel", role: .cancel) { chosen = nil }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func badge(for release: MuffinInstaller.Release) -> String {
        if release.version == model.currentVersion { return "Installed".localized }
        if release.isPrerelease { return "Nightly".localized }
        return MuffinInstaller.isNewer(release.version, than: model.currentVersion) ? "Update".localized : "Older".localized
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
        // iOS throws (and the app crashes at launch) when registering an identifier its Info.plist doesn't
        // list, so never register unless the bundle actually lists it.
        guard isPermitted else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task)
        }
    }

    private static var isPermitted: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.contains(identifier) ?? false
    }

    static func schedule() {
        guard isPermitted, UserDefaults.standard.bool(forKey: MuffinInstaller.autoRefreshKey), MuffinInstaller.canSign else { return }
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

    /// The newest numbered release's IPA, downloaded, when it's newer than this copy. Blocks (background thread).
    private static func newerRelease() -> URL? {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let done = DispatchSemaphore(value: 0)
        var result: URL?
        Task {
            if let latest = await MuffinInstaller.releases().first(where: { !$0.isPrerelease }),
               MuffinInstaller.isNewer(latest.version, than: current) {
                result = try? await MuffinInstaller.download(latest)
            }
            done.signal()
        }
        done.wait()
        return result
    }

    private static func handle(_ task: BGProcessingTask) {
        task.expirationHandler = { schedule() }
        let worker = Thread {
            let callbacks = MuffinInstaller.Callbacks(step: { _ in }, askCode: { _, reply in reply(nil) })
            do {
                var app = Bundle.main.bundleURL
                if UserDefaults.standard.object(forKey: MuffinInstaller.autoUpdateKey) as? Bool ?? true,
                   let newer = newerRelease() {
                    app = newer
                }
                try MuffinInstaller.resign(appPath: app, callbacks: callbacks)
                task.setTaskCompleted(success: true)
            } catch {
                schedule()
                task.setTaskCompleted(success: false)
            }
        }
        worker.start()
    }
}
