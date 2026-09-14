import SwiftUI
import UniformTypeIdentifiers

/// Real Wii U games are encrypted and MuffinEMU ships no keys. This is where the user
/// supplies their own, dumped from their own console. Optional by design: without
/// it, everything that worked before - homebrew, .rpx, anything already decrypted -
/// still works.
struct KeysSettingsSection: View {
    @State private var showingKeysImporter = false
    @State private var showingKeysRemovalConfirmation = false
    @State private var keyCount = WiiUKeys.installedKeyCount()
    @State private var keysErrorMessage: String?

    var body: some View {
        Section {
            Button(action: { showingKeysImporter = true }) {
                Label(WiiUKeys.keysFileExists() ? "Replace keys.txt" : "Import keys.txt",
                      systemImage: "key")
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            if WiiUKeys.keysFileExists() {
                SettingsRow(label: "Keys loaded", value: "\(keyCount)")
                Button(role: .destructive, action: { showingKeysRemovalConfirmation = true }) {
                    Label("Remove keys.txt", systemImage: "trash")
                }
            }
        } header: {
            Text("Wii U Keys")
        } footer: {
            InfoButton.footer(
                "Optional - encrypted games need keys.txt, with the AES keys dumped from your own Wii U inside. Homebrew and already-decrypted dumps need none of this.",
                title: "Wii U Keys",
                text: "Optional. Encrypted games (.wux, .wud, .iso, .wua) need the AES keys dumped from your own Wii U, in a plain text file called keys.txt - one key per line. MuffinEMU ships no keys and can't obtain them. Homebrew and already-decrypted dumps need none of this.\n\nYou can also skip this button entirely: open MuffinEMU in the Files app and drop keys.txt straight into the \"keys\" folder. It's picked up on the next launch, no restart needed.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        // .item for the same reason the ROM picker uses it: a keys.txt exported by
        // some other tool may carry no useful type at all, and a type filter would
        // grey out the one file this button exists to select. WiiUKeys.importKeys
        // decides what it actually is, by reading it.
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
        .alert("Remove keys.txt?", isPresented: $showingKeysRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                try? WiiUKeys.removeKeys()
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
