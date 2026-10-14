// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Thread-safe stop flag the background work polls.
final class MigrationCancelFlag {
    private let lock = NSLock()
    private var flag = false

    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}

/// Drives the export and the import: the work itself is MigrationArchive, run off the main thread; this
/// holds what the screen shows while it runs.
@MainActor
final class MigrationModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case exporting
        case analysing
        case confirming
        case importing
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var plan: MigrationArchive.Plan?
    @Published private(set) var progress = 0.0
    @Published private(set) var detail = ""
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false
    /// Which section the message belongs under: Import, or Export.
    @Published private(set) var messageIsFromImport = false
    @Published private(set) var lastExport: (url: URL, bytes: Int64)?
    @Published var analysis: MigrationArchive.Analysis?

    private var cancelFlag = MigrationCancelFlag()

    var isBusy: Bool { phase != .idle && phase != .confirming }

    // MARK: Plan

    func refresh() {
        lastExport = MigrationArchive.existingExports().first
        guard phase == .idle else { return }
        phase = .scanning
        Task {
            let scanned = await Task.detached(priority: .utility) { MigrationArchive.scan() }.value
            plan = scanned
            if phase == .scanning { phase = .idle }
        }
    }

    // MARK: Export

    func export(includeGames: Bool) {
        guard phase == .idle, let plan else { return }
        begin(.exporting)
        let flag = cancelFlag
        let relay = progressRelay()
        Task {
            let outcome: Result<MigrationArchive.ExportResult, Error> = await Task.detached(priority: .userInitiated) {
                var lastTick = Date.distantPast
                do {
                    return .success(try MigrationArchive.export(
                        plan: plan, includeGames: includeGames,
                        progress: { done, total, name in
                            // About ten updates a second is plenty to watch.
                            guard Date().timeIntervalSince(lastTick) > 0.1 else { return }
                            lastTick = Date()
                            relay(done, total, name)
                        },
                        isCancelled: { flag.isSet }))
                } catch {
                    return .failure(error)
                }
            }.value
            finish()
            switch outcome {
            case .success(let result):
                lastExport = (result.url, result.bytes)
                say("Saved \(result.url.lastPathComponent) (\(MigrationArchive.format(result.bytes))). It's in Files under MuffinEMU, in the Migration folder.", error: false)
            case .failure(let error):
                say(Self.describe(error), error: true)
            }
        }
    }

    func deleteLastExport() {
        guard let export = lastExport else { return }
        try? FileManager.default.removeItem(at: export.url)
        lastExport = MigrationArchive.existingExports().first
        say("Deleted \(export.url.lastPathComponent).", error: false)
    }

    func shareLastExport() {
        guard let export = lastExport else { return }
        DocumentImport.presentShare([export.url])
    }

    // MARK: Import

    func choose() {
        guard phase == .idle else { return }
        DocumentImport.present(contentTypes: [.data]) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    self?.analyse(url)
                case .failure(let error):
                    self?.say(error.localizedDescription, error: true, fromImport: true)
                }
            }
        }
    }

    private func analyse(_ url: URL) {
        begin(.analysing)
        let flag = cancelFlag
        Task {
            let outcome: Result<MigrationArchive.Analysis, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try MigrationArchive.analyse(url: url, isCancelled: { flag.isSet }))
                } catch {
                    return .failure(error)
                }
            }.value
            switch outcome {
            case .success(let found):
                analysis = found
                finish()
                phase = .confirming
            case .failure(let error):
                finish()
                say(Self.describe(error), error: true, fromImport: true)
            }
        }
    }

    func cancelConfirmation() {
        analysis = nil
        phase = .idle
    }

    func restore(replaceNewer: Bool, restoreSettings: Bool) {
        guard phase == .confirming, let found = analysis else { return }
        begin(.importing)
        let flag = cancelFlag
        let relay = progressRelay()
        Task {
            let outcome: Result<MigrationArchive.RestoreResult, Error> = await Task.detached(priority: .userInitiated) {
                var lastTick = Date.distantPast
                do {
                    return .success(try MigrationArchive.restore(
                        found, replaceNewer: replaceNewer,
                        progress: { done, total, name in
                            guard Date().timeIntervalSince(lastTick) > 0.1 else { return }
                            lastTick = Date()
                            relay(done, total, name)
                        },
                        isCancelled: { flag.isSet }))
                } catch {
                    return .failure(error)
                }
            }.value
            finish()
            analysis = nil
            switch outcome {
            case .success(let result):
                var parts = ["Imported \(result.written) files (\(MigrationArchive.format(result.bytes)))."]
                if result.keptNewer > 0 {
                    parts.append("Kept \(result.keptNewer) newer files that were already here.")
                }
                if let backup = result.savesBackup {
                    parts.append("Saves that were replaced are in \(backup.lastPathComponent) under save-backups.")
                }
                if restoreSettings {
                    if let data = result.settingsData, let preview = try? SettingsBackup.preview(of: data) {
                        SettingsBackup.apply(preview)
                        parts.append("Settings restored.")
                    }
                    if let data = result.stateData, SettingsBackup.mergeState(data) > 0 {
                        parts.append("Favourites and appearance restored.")
                    }
                }
                parts.append("Close MuffinEMU and open it again to finish.")
                say(parts.joined(separator: " "), error: false, fromImport: true)
            case .failure(let error):
                say(Self.describe(error) + (error is MigrationArchive.MigrationError ? "" : " Files already copied are complete; you can run the import again."), error: true, fromImport: true)
            }
        }
    }

    // MARK: Shared

    func cancel() { cancelFlag.set() }

    private func begin(_ next: Phase) {
        cancelFlag = MigrationCancelFlag()
        progress = 0
        detail = ""
        message = nil
        phase = next
        // The screen stays on while the work runs; it only goes on while MuffinEMU is in front.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func finish() {
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
    }

    /// Hands progress from the background thread to the main actor.
    private func progressRelay() -> @Sendable (Int64, Int64, String) -> Void {
        return { [weak self] done, total, name in
            Task { @MainActor in self?.report(done: done, total: total, name: name) }
        }
    }

    private func report(done: Int64, total: Int64, name: String) {
        guard phase == .exporting || phase == .importing else { return }
        progress = total > 0 ? Double(done) / Double(total) : 0
        detail = "\(MigrationArchive.format(done)) of \(MigrationArchive.format(total))" + (name.isEmpty ? "" : "  \(name)")
    }

    private func say(_ text: String, error: Bool, fromImport: Bool = false) {
        message = text
        messageIsError = error
        messageIsFromImport = fromImport
    }

    private static func describe(_ error: Error) -> String {
        if let migration = error as? MigrationArchive.MigrationError, case .cancelled = migration {
            return "Stopped. Nothing half-written was kept."
        }
        return error.localizedDescription
    }
}

/// Settings > Move to the new MuffinEMU. Two sections: export from this app, import into one.
struct MigrationSettingsSection: View {
    @StateObject private var model = MigrationModel()
    @State private var includeGames = false
    @State private var restoreSettings = true
    @State private var confirmDelete = false

    var body: some View {
        Group {
            exportSection
            importSection
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear { model.refresh() }
    }

    // MARK: Export

    private var archiveBytes: Int64 { model.plan?.archiveBytes(includeGames: includeGames) ?? 0 }
    private var freeBytes: Int64? { MigrationArchive.freeSpace() }

    private var shortOfSpace: Bool {
        guard model.plan != nil, let free = freeBytes else { return false }
        return free < MigrationArchive.spaceNeeded(for: archiveBytes)
    }

    private var exportSection: some View {
        Section {
            Text("MuffinEMU is moving to a new app identity, and the new one is a separate app that starts empty. This version stops getting updates after this release. Export your data here, install the new MuffinEMU, then import it there.")
                .font(.system(size: 13))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $includeGames) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include games (Roms folder)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(gamesCaption)
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .disabled(model.isBusy)

            if model.plan != nil {
                SettingsRow(label: "Export size", value: MigrationArchive.format(archiveBytes), icon: "archivebox")
                SettingsRow(label: "Free space", value: freeBytes.map(MigrationArchive.format) ?? "unknown", icon: "internaldrive")
            }

            if shortOfSpace {
                Text("Not enough free space for this export. It needs about \(MigrationArchive.format(MigrationArchive.spaceNeeded(for: archiveBytes))). Free up space" + (includeGames ? ", or turn off Include games." : "."))
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.phase == .exporting {
                runningRows(title: "Exporting")
            } else {
                Button {
                    model.export(includeGames: includeGames)
                } label: {
                    Label("Export everything", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .disabled(model.isBusy || model.plan == nil || shortOfSpace)
            }

            if let export = model.lastExport, !model.isBusy {
                SettingsRow(label: export.url.lastPathComponent, value: MigrationArchive.format(export.bytes), icon: "doc.zipper")
                Button {
                    model.shareLastExport()
                } label: {
                    Label("Share the export", systemImage: "square.and.arrow.up.on.square")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete the export", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }

            if let message = model.message, !model.messageIsFromImport {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(model.messageIsError ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Move to the new MuffinEMU", icon: "arrow.right.circle", accent: .system)
        } footer: {
            InfoButton.footer(
                "Keep MuffinEMU open on screen while it runs.",
                title: "Move to the new MuffinEMU",
                text: "Export everything writes one file to Files, in MuffinEMU > Migration. It holds your saves, installed updates and DLC, accounts, keys.txt, otp.bin and seeprom.bin, compiled shader caches, graphic packs, save states, settings, favourites and appearance.\n\nGames (the Roms folder, and base games installed into the Wii U storage) are left out unless you turn on Include games. Without them the export is much smaller, and you can copy your games into the new app in Files. Screen recordings, save backups, logs and other caches are never included. The premium unlock isn't carried over; enter it again in the new app.\n\nThe export runs only while MuffinEMU is open on screen, and keeps the screen awake. You can stop it at any time. Before it starts, MuffinEMU checks that there's enough free space, and the file is kept out of device backups.\n\nWhen it's done, share the file to the new MuffinEMU's Files folder or to another device, install the new MuffinEMU, and choose Import from the old MuffinEMU there. Delete the export afterwards to get the space back.")
        }
        .confirmationDialog("Delete this export?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteLastExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your games, saves and settings in MuffinEMU aren't touched.")
        }
    }

    private var gamesCaption: String {
        guard let plan = model.plan else { return "Off by default." }
        return "Adds about \(MigrationArchive.format(plan.gameBytes)). Off by default."
    }

    private func runningRows(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: model.progress)
            Text("\(title)\u{2026} \(Int(model.progress * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(model.detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(MuffinTheme.secondaryText)
                .lineLimit(2)
            Text("Keep MuffinEMU open on screen until this finishes.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
            Button("Stop", role: .cancel) { model.cancel() }
        }
        .padding(.vertical, 2)
    }

    // MARK: Import

    private var importSection: some View {
        Section {
            Toggle(isOn: $restoreSettings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore settings too")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Replaces the settings here with the ones in the file.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .disabled(model.isBusy || model.phase == .confirming)

            switch model.phase {
            case .analysing:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the export\u{2026}")
                        .font(.system(size: 13))
                    Spacer()
                    Button("Stop", role: .cancel) { model.cancel() }
                }
            case .importing:
                runningRows(title: "Importing")
            default:
                Button {
                    model.choose()
                } label: {
                    Label("Import from the old MuffinEMU", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .disabled(model.isBusy || model.phase == .confirming)
            }

            if let message = model.message, model.messageIsFromImport {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(model.messageIsError ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Import an export", icon: "tray.and.arrow.down", accent: .system)
        } footer: {
            InfoButton.footer(
                "Merges with what's here. A newer file is never replaced without asking.",
                title: "Import an export",
                text: "Pick the .muffinmove file you exported from the old MuffinEMU. It can be on this device or in iCloud Drive. This also works to restore your data after reinstalling MuffinEMU.\n\nMuffinEMU checks the file first and shows what it would change. Files that aren't here yet are added, and files that are older than the export's are updated. If a file here is newer than the export's copy, you choose whether to keep it or replace it; saves that are replaced are moved to save-backups first, not deleted. Every file is checked as it is copied, so a damaged export can't leave a half-written file behind, and an interrupted import can simply be run again.\n\nIt works only while MuffinEMU is open on screen. When it finishes, close MuffinEMU and open it again.")
        }
        .confirmationDialog("Import this export?", isPresented: confirming, titleVisibility: .visible) {
            if let found = model.analysis {
                if found.conflicts.isEmpty {
                    Button("Import") { model.restore(replaceNewer: false, restoreSettings: restoreSettings) }
                } else {
                    Button("Import, keep my newer files") { model.restore(replaceNewer: false, restoreSettings: restoreSettings) }
                    Button("Import, replace with the export's files", role: .destructive) {
                        model.restore(replaceNewer: true, restoreSettings: restoreSettings)
                    }
                }
            }
            Button("Cancel", role: .cancel) { model.cancelConfirmation() }
        } message: {
            Text(confirmationText)
        }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { model.phase == .confirming }, set: { if !$0 && model.phase == .confirming { model.cancelConfirmation() } })
    }

    private var confirmationText: String {
        guard let found = model.analysis else { return "" }
        let source = found.isFromThisApp ? "this app" : "another MuffinEMU install"
        var text = "Made by \(source), version \(found.manifest.appVersion). It adds \(found.newFiles.count) files and updates \(found.updatedFiles.count), about \(MigrationArchive.format(found.bytesToWrite)); \(found.identicalCount) are already here."
        if !found.manifest.includesGames { text += " Games aren't in this export." }
        if !found.conflicts.isEmpty {
            text += " \(found.conflicts.count) files here are newer than the export's copy (\(MigrationArchive.format(found.conflictBytes)))."
        }
        if found.blockedCount > 0 {
            text += " \(found.blockedCount) can't be imported because a folder with the same name is in the way."
        }
        if restoreSettings && found.hasSettings { text += " Settings in the export replace the ones here." }
        return text
    }
}
