import SwiftUI
import UniformTypeIdentifiers

private extension Bundle {
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

struct SettingsView: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingKeysImporter = false
    @State private var showingKeysRemovalConfirmation = false
    @State private var keyCount = WiiUKeys.installedKeyCount()
    @State private var keysErrorMessage: String?
    /// Shared with EmulatorViewOptimized by key, not by binding - the emulator view is
    /// not in this sheet's hierarchy, and AppStorage is what makes the setting outlive
    /// the sheet anyway.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = false

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section("Appearance") {
                        Button(action: { showingIconPicker = true }) {
                            Label("App Icon", systemImage: "app.badge")
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                    }

                    // Off by default: the log is a diagnostic, not a feature, and a
                    // wall of monospaced text over the boot is not what someone who
                    // just wants to play a game should meet. Collection is always on
                    // regardless (see IOSLiveLog.h) - gating that too would mean the
                    // toggle could only ever show the boot AFTER the one that failed.
                    Section {
                        Toggle(isOn: $showLaunchLog) {
                            Label("Show launch log", systemImage: "text.alignleft")
                        }
                        .tint(MuffinTheme.pixelBlue)
                    } header: {
                        Text("Diagnostics")
                    } footer: {
                        Text("Shows what the emulator is doing, with timestamps, while a game boots. Useful when a game starts but the screen stays black.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Real Wii U games are encrypted and Muffin ships no keys. This is
                    // where the user supplies their own, dumped from their own console.
                    // Optional by design: without it, everything that worked before -
                    // homebrew, .rpx, anything already decrypted - still works.
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
                        Text("Wii U keys")
                    } footer: {
                        Text("Optional. Encrypted games (.wux, .wud, .iso, .wua) need the AES keys dumped from your own Wii U, in a plain text file called keys.txt - one key per line. Muffin ships no keys and can't obtain them. Homebrew and already-decrypted dumps need none of this.\n\nYou can also skip this button entirely: open Muffin in the Files app and drop keys.txt straight into the \"keys\" folder. It's picked up on the next launch, no restart needed.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("Library") {
                        SettingsRow(label: "Games", value: "\(gameManager.games.count)")
                        SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("About") {
                        SettingsRow(label: "Version", value: Bundle.main.appVersionString)
                        Link(destination: URL(string: "https://github.com/bward-dev1/cemu-ios-muffin")!) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView()
            }
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
        .navigationViewStyle(.stack)
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

/// LabeledContent needs iOS 16+; this project's deployment target is 15.0.
private struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(MuffinTheme.brownMid)
        }
    }
}
