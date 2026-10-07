// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

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
    @AppStorage(WiiUMenuSettings.showAsCardKey) private var showAsCard = WiiUMenuSettings.defaultShowAsCard
    @AppStorage(WiiUMenuSettings.hideKey) private var hideMenu = WiiUMenuSettings.defaultHidden
    @State private var showingUninstallConfirmation = false
    @State private var isUninstalling = false

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

            installedMenuRows
        } header: {
            SettingsSectionHeader("Wii U Menu", icon: "house", accent: .content)
        } footer: {
            InfoButton.footer(
                "Experimental. Files must be dumped from your own Wii U. Nothing is included.",
                title: "Wii U Menu",
                text: "Experimental. The Wii U Menu and its support files must come from your own Wii U, dumped with Dumpling. MuffinEMU includes none of them.\n\nImport Wii U Menu: pick the package folder (the one containing mlc01 and cafeLibs), an mlc01 folder, a sys folder, a cafeLibs folder, or the Menu's own title folder. Files are merged one by one into MuffinEMU's storage; anything replaced is saved first, and your saves are never touched.\n\nImport console files: pick otp.bin and seeprom.bin. Only online features need them; the Menu may start without.\n\nOnce the Menu is installed it appears at the top of the library. Games in your library show up in it. You can show it as a card in the game grid instead, or hide it from the library; hiding doesn't uninstall it.\n\nUninstall Wii U Menu deletes only the Menu itself. Shared data, system apps, cafeLibs, otp.bin and seeprom.bin stay, since games can use them. Your saves and your games are never touched.")
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

    /// Library placement and uninstall: only while a Menu title is installed. A separate
    /// property so the Section's own builder stays under the 10-child limit.
    @ViewBuilder private var installedMenuRows: some View {
        if status.menuInstalled {
            libraryToggles
            Button(role: .destructive, action: { showingUninstallConfirmation = true }) {
                DestructiveSettingsLabel(title: "Uninstall Wii U Menu", systemImage: "trash")
            }
            .disabled(isImporting || isUninstalling)
            .alert("Uninstall the Wii U Menu?", isPresented: $showingUninstallConfirmation) {
                Button("Uninstall", role: .destructive) { uninstall() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This deletes the Wii U Menu from MuffinEMU's storage. Shared data, system apps, cafeLibs, otp.bin and seeprom.bin stay, since games can use them. Your saves and your games aren't touched. You can import the Menu again from Settings > Wii U Menu.")
            }
        }
    }

    /// How the installed Menu appears in the library. Hiding wins: a hidden Menu has no
    /// card to place, so the card toggle is dimmed while it is on.
    @ViewBuilder private var libraryToggles: some View {
        Toggle(isOn: $showAsCard) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show Wii U Menu as a game card")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Puts the Menu in the game grid instead of a bar above it.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
        .tint(MuffinTheme.accentText)
        .disabled(hideMenu)

        Toggle(isOn: $hideMenu) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hide the installed Wii U Menu")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Takes it out of the library. It stays installed; turn this off to bring it back.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
        .tint(MuffinTheme.accentText)
    }

    private func uninstall() {
        isUninstalling = true
        Task {
            let outcome: Result<Int, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try WiiUMenu.uninstallMenu())
                } catch {
                    return .failure(error)
                }
            }.value
            isUninstalling = false
            store.refresh()
            switch outcome {
            case .success:
                resultTitle = "Uninstalled"
                resultMessage = "The Wii U Menu was removed. Your saves and games weren't touched."
            case .failure(let error):
                resultTitle = "Couldn't uninstall"
                resultMessage = error.localizedDescription
            }
        }
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
