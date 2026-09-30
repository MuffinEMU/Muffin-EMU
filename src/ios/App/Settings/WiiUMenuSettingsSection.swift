import SwiftUI
import UniformTypeIdentifiers

/// Import for the Wii U Menu and the console files it needs. Everything comes from the
/// user's own Wii U; nothing is included with MuffinEMU. Experimental.
struct WiiUMenuSettingsSection: View {
    @ObservedObject private var store = WiiUMenuStore.shared

    private enum Mode { case consoleFiles, menuFolder }
    @State private var importMode: Mode = .consoleFiles
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var resultTitle = ""
    @State private var resultMessage: String?

    private var status: WiiUMenuStatus { store.status }

    var body: some View {
        Section {
            SettingsRow(label: "Wii U Menu",
                        value: status.menuInstalled
                            ? status.installedRegions.map(\.displayName).joined(separator: ", ")
                            : "Not installed")
            SettingsRow(label: "Shared data (0005001b)", value: status.hasSharedData ? "Found" : "Missing")
            SettingsRow(label: "cafeLibs", value: "\(status.cafeLibsPresent) of \(WiiUMenu.cafeLibNames.count)")
            if !status.incompleteTitles.isEmpty {
                SettingsRow(label: "Incomplete system titles", value: "\(status.incompleteTitles.count)")
            }
            SettingsRow(label: "otp.bin", value: status.hasOTP ? "Found" : "Missing")
            SettingsRow(label: "seeprom.bin", value: status.hasSeeprom ? "Found" : "Missing")

            Button(action: { importMode = .menuFolder; showingImporter = true }) {
                Label("Import Wii U Menu", systemImage: "folder.badge.plus")
            }
            .disabled(isImporting)
            .foregroundColor(MuffinTheme.brownDarkest)

            Button(action: { importMode = .consoleFiles; showingImporter = true }) {
                Label("Import console files", systemImage: "key")
            }
            .disabled(isImporting)
            .foregroundColor(MuffinTheme.brownDarkest)

            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Importing. This can take a few minutes for a full system dump.")
                        .font(.footnote)
                        .foregroundColor(MuffinTheme.brownMid)
                }
            }
        } header: {
            SettingsSectionHeader("Wii U Menu", icon: "house", accent: .content)
        } footer: {
            InfoButton.footer(
                "Experimental. Files must be dumped from your own Wii U. Nothing is included.",
                title: "Wii U Menu",
                text: "Experimental. The Wii U Menu and its support files must come from your own Wii U, dumped with Dumpling. MuffinEMU includes none of them.\n\nImport Wii U Menu: pick the package folder (the one containing mlc01 and cafeLibs), an mlc01 folder, a sys folder, a cafeLibs folder, or the Menu's own title folder. Files are merged one by one into MuffinEMU's storage; anything replaced is saved first, and your saves are never touched.\n\nImport console files: pick otp.bin and seeprom.bin. Only online features need them; the Menu may start without.\n\nOnce the Menu is installed it appears at the top of the library. Games in your library show up in it.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        // One importer for both buttons: two .fileImporter modifiers on the same view only
        // honour the last one.
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importMode == .menuFolder ? [.folder] : [.item],
            allowsMultipleSelection: importMode == .consoleFiles
        ) { result in
            handle(result)
        }
        .alert(resultTitle, isPresented: .constant(resultMessage != nil), presenting: resultMessage) { _ in
            Button("OK") { resultMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear { store.refresh() }
    }

    private func handle(_ result: Result<[URL], Error>) {
        let mode = importMode
        switch result {
        case .failure(let error):
            resultTitle = "Couldn't import"
            resultMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImporting = true
            Task {
                let outcome: Result<String, Error> = await Task.detached(priority: .userInitiated) {
                    do {
                        switch mode {
                        case .consoleFiles:
                            return .success(try WiiUMenu.importConsoleFiles(from: urls).joined(separator: "\n"))
                        case .menuFolder:
                            return .success(try WiiUMenu.importSystemFiles(from: urls[0]).summary)
                        }
                    } catch {
                        return .failure(error)
                    }
                }.value
                isImporting = false
                store.refresh()
                switch outcome {
                case .success(let message):
                    resultTitle = "Imported"
                    resultMessage = message + "\n\n" + statusSummary()
                case .failure(let error):
                    resultTitle = "Couldn't import"
                    resultMessage = error.localizedDescription
                }
            }
        }
    }

    /// What is present after an import, and what the Menu still lacks.
    private func statusSummary() -> String {
        var lines: [String] = []
        if let region = status.installedRegions.first {
            lines.append("Wii U Menu found (\(region.displayName)).")
        }
        let missing = status.missingRequired
        if missing.isEmpty {
            lines.append("Everything the Menu needs to start is present.")
        } else {
            lines.append("Still missing: " + missing.joined(separator: ", ") + ".")
        }
        if let incomplete = status.incompleteTitlesSummary() {
            lines.append(incomplete)
        }
        let optional = status.missingOptional
        if !optional.isEmpty {
            lines.append("Optional, for online features: " + optional.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }
}
