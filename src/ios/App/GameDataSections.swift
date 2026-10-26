// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
// For UTType.folder, which the import picker is restricted to.
import UniformTypeIdentifiers

/// A game's own save on its Game page: export it, or import one from another Cemu install. Moving a
/// game's data in and out lives on the Game page, beside its save states and shader cache; Game settings
/// only holds settings.
struct GameSavesSection: View {
    let game: GameMetadata

    /// One line of feedback under the buttons rather than an alert. An alert for a
    /// success is a second tap for something the person already knows they did; the
    /// failures here are all short enough to read in place.
    @State private var message: String?
    @State private var failed = false
    @State private var showingImportConfirmation = false

    var body: some View {
        Section {
            exportButton
            importButton
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(failed ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Game saves".localized, icon: "externaldrive", accent: .io)
        } footer: {
            InfoButton.footer(
                "The save the game itself writes. Not a save state. Export is available once the game has saved.".localized,
                title: "Game saves".localized,
                text: "This is the save the game itself writes. It uses the Wii U\'s own format, so it can move between MuffinEMU, desktop Cemu and a real console. A save state is a snapshot of the whole emulated console and only MuffinEMU can read it.\n\nExport writes a folder named after the game and title ID. Import accepts that folder, a folder named after the title ID from another Cemu install, or its \'user\' folder. Importing replaces the current save; the old one is first copied to save-backups in MuffinEMU\'s Documents folder.".localized
            )
        }
        .confirmationDialog("Import a save folder?", isPresented: $showingImportConfirmation, titleVisibility: .visible) {
            Button("Choose folder", role: .destructive, action: pickSaveFolder)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(format: "This replaces %@\'s current save. The one you have now is backed up first, and the game should be closed before you do this.".localized, game.title))
        }
    }

    private var exportButton: some View {
        Button {
            GameSaveTransfer.export(game) { result in
                switch result {
                case .success(let note):
                    message = note
                    failed = false
                case .failure(let error):
                    message = error.localizedDescription
                    // Backing out of the picker is not an error, so it is not shown as one.
                    if case GameSaveTransfer.TransferError.cancelled = error {
                        failed = false
                    } else {
                        failed = true
                    }
                }
            }
        } label: {
            Label("Export game saves", systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .disabled(!GameSaveTransfer.hasSave(for: game))
    }

    // Confirmed, unlike export: this one replaces what is already there. It is backed up
    // either way, but someone should know they are about to swap their progress out before
    // the picker opens, not after.
    private var importButton: some View {
        Button(role: .destructive) {
            showingImportConfirmation = true
        } label: {
            Label("Import game save folder", systemImage: "square.and.arrow.down")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    private func pickSaveFolder() {
        DocumentImport.present(contentTypes: [.folder]) { result in
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { return }
                do {
                    message = try GameSaveTransfer.importSave(game, from: picked)
                    failed = false
                } catch {
                    message = error.localizedDescription
                    failed = true
                }
            case .failure(let error):
                message = error.localizedDescription
                failed = true
            }
        }
    }
}

/// Importing a shader cache from desktop Cemu or another MuffinEMU, on the Game page under the game's
/// own shader cache (GameShaderCacheSection).
struct GameShaderImportSection: View {
    let game: GameMetadata
    /// The whole library, so a cache file that belongs to another game can say which one.
    let libraryGames: [GameMetadata]

    /// One line under the buttons, red when nothing was imported.
    @State private var message: String?
    @State private var failed = false
    @State private var busy = false
    /// A pipeline cache whose name doesn't say which renderer made it, waiting for the answer.
    @State private var pendingPipeline: PendingPipeline?

    private struct PendingPipeline: Identifiable {
        let id = UUID()
        let staged: URL
        let name: String
    }

    var body: some View {
        Section {
            Button {
                pickCacheFile(.shaders)
            } label: {
                Label("Import learned shaders", systemImage: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .disabled(busy)
            Button {
                pickCacheFile(.pipeline)
            } label: {
                Label("Import shader pipeline caches", systemImage: "square.and.arrow.down.on.square")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .disabled(busy)
            if busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Importing\u{2026}")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(failed ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Import shader caches".localized, icon: "hammer", accent: .core)
        } footer: {
            InfoButton.footer(
                "Add a shader cache from desktop Cemu or another MuffinEMU, so this game starts with its shaders already learned.".localized,
                title: "Shader caches".localized,
                text: "Learned shaders are what a game has revealed by drawing with them. Importing adds them to this game's own file: anything the game already has stays as it is, and the file is never replaced.\n\nThe file has to be this game's: MuffinEMU checks the version stamp inside it, not the name. Desktop Cemu's files work: learned shaders are named like 000500001010ec00_shaders.bin and are converted the first time the game starts. MuffinEMU's are named ..._mtlshaders.bin. Desktop caches from before Cemu 1.16 use another format and can't be converted.\n\nPipeline caches are named ..._vkpipeline.bin (desktop Cemu, Vulkan) or ..._mtlpipeline.bin (MuffinEMU, Metal). A Vulkan one only helps the Vulkan renderer and a Metal one only the Metal renderer; it's stored either way and used when you switch. Each also needs the game's learned shaders. Import with the game closed. The sizes in Settings update the next time you open it.".localized
            )
        }
        .confirmationDialog("Which renderer made this pipeline cache?", isPresented: Binding(
            get: { pendingPipeline != nil },
            set: { if !$0 { pendingPipeline = nil } }
        ), titleVisibility: .visible, presenting: pendingPipeline) { pending in
            Button("Vulkan (desktop Cemu)") { answerPipelineRenderer(pending, vulkan: true) }
            Button("Metal (MuffinEMU)") { answerPipelineRenderer(pending, vulkan: false) }
            Button("Cancel", role: .cancel) { discardPending(pending) }
        } message: { pending in
            Text(String(format: "\"%@\" doesn't say. Desktop Cemu's are named ..._vkpipeline.bin and MuffinEMU's ..._mtlpipeline.bin. It's stored under the matching name either way.".localized, pending.name))
        }
    }

    private func pickCacheFile(_ kind: ShaderCacheImport.Kind) {
        DocumentImport.present(contentTypes: ShaderCacheImport.pickerTypes) { result in
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { return }
                let name = picked.lastPathComponent
                busy = true
                message = nil
                DispatchQueue.global(qos: .userInitiated).async {
                    let staged: URL
                    do {
                        staged = try ShaderCacheImport.stage(picked)
                    } catch {
                        DispatchQueue.main.async {
                            finish(ShaderCacheImport.Outcome(message: String(format: "Couldn't read \"%@\": %@".localized, name, error.localizedDescription), failed: true))
                        }
                        return
                    }
                    if kind == .pipeline, ShaderCacheImport.pipelineIsVulkan(fileName: name) == nil {
                        // the contents don't say which renderer wrote it, so ask
                        DispatchQueue.main.async {
                            busy = false
                            pendingPipeline = PendingPipeline(staged: staged, name: name)
                        }
                        return
                    }
                    runImport(kind, staged: staged, name: name, pipelineIsVulkan: ShaderCacheImport.pipelineIsVulkan(fileName: name))
                }
            case .failure(let error):
                finish(ShaderCacheImport.Outcome(message: error.localizedDescription, failed: true))
            }
        }
    }

    /// Runs on a background queue.
    private func runImport(_ kind: ShaderCacheImport.Kind, staged: URL, name: String, pipelineIsVulkan: Bool?) {
        let outcome = ShaderCacheImport.run(kind: kind, game: game, library: libraryGames, staged: staged,
                                            originalName: name, pipelineIsVulkan: pipelineIsVulkan)
        DispatchQueue.main.async { finish(outcome) }
    }

    private func finish(_ outcome: ShaderCacheImport.Outcome) {
        busy = false
        message = outcome.message
        failed = outcome.failed
    }

    private func answerPipelineRenderer(_ pending: PendingPipeline, vulkan: Bool) {
        pendingPipeline = nil
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            runImport(.pipeline, staged: pending.staged, name: pending.name, pipelineIsVulkan: vulkan)
        }
    }

    private func discardPending(_ pending: PendingPipeline) {
        try? FileManager.default.removeItem(at: pending.staged)
    }
}
