// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import UniformTypeIdentifiers

/// Export all settings to one file and import them back (Advanced mode only). The file and its checks
/// are SettingsBackup; this is the buttons, the confirmation and the one-line result.
struct SettingsBackupSection: View {
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @State private var pending: SettingsBackup.Preview?
    @State private var confirmImport = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        if SettingsMode.isAdvanced(raw: settingsModeRaw) {
            Section {
                Button {
                    exportSettings()
                } label: {
                    Label("Export settings", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                Button {
                    chooseFile()
                } label: {
                    Label("Import settings", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(messageIsError ? .red : MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SettingsSectionHeader("Back up settings", icon: "doc.text", accent: .system)
            } footer: {
                InfoButton.footer(
                    "Writes every setting and every game's own options to one file you can keep or move to another device.",
                    title: "Back up settings",
                    text: "Export settings saves your settings and each game's own settings to one .json file in Files. It doesn't include your library, favourites, Wii U keys, accounts, theme or Premium.\n\nImport settings reads such a file, checks it, and asks before replacing anything. Your settings and each game's settings are replaced by the file's, and anything the file doesn't mention goes back to its default. Some changes apply the next time you start a game.")
            }
            .foregroundColor(MuffinTheme.brownDarkest)
            .confirmationDialog("Replace your settings?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Import and replace", role: .destructive) {
                    guard let pending else { return }
                    SettingsBackup.apply(pending)
                    message = "Settings imported. Some changes apply the next time you start a game."
                    messageIsError = false
                    self.pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text(confirmationText)
            }
        }
    }

    private var confirmationText: String {
        guard let pending else { return "" }
        let games = pending.gameCount == 1 ? "1 game's own options" : "\(pending.gameCount) games' own options"
        var text = "This file has \(pending.settingCount) settings and \(games). Importing replaces all of your settings and every game's own options. Your library, keys, accounts and premium unlock aren't touched."
        if pending.skippedCount > 0 {
            text += " \(pending.skippedCount) entries in the file can't be used and are skipped."
        }
        return text
    }

    private func exportSettings() {
        do {
            let url = try SettingsBackup.exportFile()
            DocumentImport.presentExport([url]) { result in
                switch result {
                case .success(let urls):
                    // An empty array is a cancel, not a failure.
                    guard let saved = urls.first else { return }
                    message = "Saved \(saved.lastPathComponent)."
                    messageIsError = false
                case .failure(let error):
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
        } catch {
            message = "Couldn't write the settings file. \(error.localizedDescription)"
            messageIsError = true
        }
    }

    private func chooseFile() {
        DocumentImport.present(contentTypes: [.json]) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    pending = try SettingsBackup.preview(of: url)
                    message = nil
                    confirmImport = true
                } catch {
                    message = error.localizedDescription
                    messageIsError = true
                }
            case .failure(let error):
                message = error.localizedDescription
                messageIsError = true
            }
        }
    }
}
