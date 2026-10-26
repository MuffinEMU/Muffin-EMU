// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import UniformTypeIdentifiers

/// Where the user supplies their own keys.txt, dumped from their own console. Optional:
/// homebrew, .rpx and already-decrypted games work without it.
struct KeysSettingsSection: View {
    @State private var showingKeysImporter = false
    @State private var showingKeysRemovalConfirmation = false
    @State private var keyCount = WiiUKeys.installedKeyCount()
    @State private var keysErrorMessage: String?

    var body: some View {
        Section {
            Button(action: { showingKeysImporter = true }) {
                Label(WiiUKeys.keysFileExists() ? "Replace keys.txt".localized : "Import keys.txt".localized,
                      systemImage: "key")
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            if WiiUKeys.keysFileExists() {
                SettingsRow(label: "Keys loaded".localized, value: "\(keyCount)")
                Button(role: .destructive, action: { showingKeysRemovalConfirmation = true }) {
                    DestructiveSettingsLabel(title: "Remove keys.txt".localized, systemImage: "trash")
                }
            }
        } header: {
            SettingsSectionHeader("Wii U Keys".localized, icon: "key", accent: .content)
        } footer: {
            InfoButton.footer(
                "Only needed for encrypted games. Homebrew and already-decrypted dumps don't need keys.".localized,
                title: "Wii U Keys".localized,
                text: "Encrypted games (.wux, .wud, .iso) need AES keys dumped from your own Wii U, in a text file called keys.txt with one key per line. MuffinEMU doesn't include keys.\n\nYou can also open MuffinEMU in the Files app and drop keys.txt into the \"keys\" folder.\n\nNew keys are used the next time you start a game. If you've already started a game since opening MuffinEMU, quit and reopen MuffinEMU first.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        // .item: a keys.txt may carry no useful type; WiiUKeys.importKeys checks the contents.
        .fileImporter(
            isPresented: $showingKeysImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleKeysImport(result)
        }
        .alert("Couldn't import keys", isPresented: .constant(keysErrorMessage != nil), presenting: keysErrorMessage) { _ in
            Button("OK") { keysErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog("Remove keys.txt?", isPresented: $showingKeysRemovalConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                do {
                    try WiiUKeys.removeKeys()
                } catch {
                    keysErrorMessage = String(format: "Couldn't remove keys.txt: %@".localized, error.localizedDescription)
                }
                keyCount = WiiUKeys.installedKeyCount()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Encrypted games won't run until you import a keys.txt again. Homebrew is unaffected.")
        }
    }

    private func handleKeysImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                keyCount = try WiiUKeys.importKeys(from: url)
            } catch {
                keysErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            keysErrorMessage = error.localizedDescription
        }
    }
}
