import SwiftUI

/// "Updates & DLC" on a game's page: what is installed for this game, removing it, and packing the
/// game with its installed update and DLC into one .wua you can keep or move to another device.
/// Installing new content stays in the library's import menu (DlcUpdateImport).
struct GameContentSection: View {
    let game: GameMetadata
    @State private var hasUpdate = false
    @State private var hasDLC = false
    @State private var confirmRemove: DlcUpdateImport.ContentKind?
    @State private var message: String?
    @State private var packing = false
    @State private var progress = DecryptProgress()
    @State private var pollTimer: Timer?
    @State private var packedFile: URL?

    var body: some View {
        Section {
            row("Update", installed: hasUpdate, kind: .update)
            row("DLC", installed: hasDLC, kind: .dlc)

            if packing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Packing into one .wua... \(progress.filesWritten) files, "
                        + ByteCountFormatter.string(fromByteCount: Int64(progress.bytesWritten), countStyle: .file))
                        .font(.system(size: 13, design: .rounded))
                    Button("Cancel", role: .destructive) { cemu_bridge_cancel_decrypt() }
                }
            } else {
                Button {
                    startPacking()
                } label: {
                    Label("Pack game, update and DLC into one .wua", systemImage: "shippingbox")
                }
                .disabled(packSources().isEmpty || cemu_bridge_is_title_running())
            }
            if let packedFile {
                Button {
                    DocumentImport.presentExport([packedFile]) { _ in }
                } label: {
                    Label("Save \(packedFile.lastPathComponent)...", systemImage: "square.and.arrow.up")
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        } header: {
            Text("Updates & DLC")
        } footer: {
            Text("Add an update or DLC from the library's import menu. Packing leaves your installed files where they are.")
        }
        .onAppear { refresh() }
        .onDisappear { pollTimer?.invalidate(); pollTimer = nil }
        .alert(item: Binding(
            get: { confirmRemove.map { RemoveRequest(kind: $0) } },
            set: { confirmRemove = $0?.kind }
        )) { request in
            Alert(
                title: Text("Remove \(request.kind.displayName)?"),
                message: Text("The game itself and your saves are not touched."),
                primaryButton: .destructive(Text("Remove")) { remove(request.kind) },
                secondaryButton: .cancel())
        }
    }

    private struct RemoveRequest: Identifiable {
        let kind: DlcUpdateImport.ContentKind
        var id: String { kind.displayName }
    }

    private func row(_ name: String, installed: Bool, kind: DlcUpdateImport.ContentKind) -> some View {
        HStack {
            Text(name)
            Spacer()
            if installed {
                Text("Installed").foregroundColor(MuffinTheme.secondaryText)
                Button("Remove", role: .destructive) { confirmRemove = kind }
                    .buttonStyle(.borderless)
                    .disabled(cemu_bridge_is_title_running())
            } else {
                Text("None").foregroundColor(MuffinTheme.secondaryText)
            }
        }
    }

    private func refresh() {
        let installed = DlcUpdateImport.installedContent(for: game)
        hasUpdate = installed.hasUpdate
        hasDLC = installed.hasDLC
    }

    private func remove(_ kind: DlcUpdateImport.ContentKind) {
        do {
            _ = try DlcUpdateImport.remove(kind: kind, for: game)
            message = "Removed the \(kind.displayName)."
        } catch {
            message = "Couldn't remove it: \(error.localizedDescription)"
        }
        refresh()
    }

    /// The base title first, then the installed update and DLC folders. Empty when the base can't be
    /// read as a title on its own (a loose .rpx or an existing .wua).
    private func packSources() -> [String] {
        var sources: [String] = []
        if let dump = game.dumpDirectoryPath {
            sources.append(dump)
        } else {
            let ext = (game.romPath as NSString).pathExtension.lowercased()
            guard ext == "wud" || ext == "wux" else { return [] }
            sources.append(game.romPath)
        }
        for kind in [DlcUpdateImport.ContentKind.update, .dlc] {
            if let folder = DlcUpdateImport.installedFolder(kind: kind, for: game) {
                sources.append(folder.path)
            }
        }
        return sources
    }

    private func startPacking() {
        let sources = packSources()
        guard !sources.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let destination = docs?.appendingPathComponent("Decrypted/\(game.id)-complete.wua") else { return }
        message = nil
        packedFile = nil
        guard cemu_bridge_start_wua_build(sources.joined(separator: "\n"), destination.path) else {
            message = "Another export is already running."
            return
        }
        packing = true
        progress = DecryptProgress()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                let snapshot = DecryptProgress.read()
                progress = snapshot
                guard snapshot.completed else { return }
                pollTimer?.invalidate()
                pollTimer = nil
                packing = false
                if snapshot.isSuccess {
                    packedFile = destination
                    message = "Done. The .wua holds the game with its update and DLC."
                } else {
                    message = failureText(snapshot.resultStatus)
                }
            }
        }
    }

    private func failureText(_ status: Int32) -> String {
        switch status {
        case 1: return "One of the files couldn't be read as a Wii U title."
        case 3: return "Couldn't write the .wua. The device may be out of space."
        case 4: return "Cancelled."
        case 5: return "Some files couldn't be read, so no .wua was made."
        case 9: return "The update or DLC belongs to a different game."
        case 10: return "The same title was added twice."
        default: return "Couldn't build the .wua."
        }
    }
}
