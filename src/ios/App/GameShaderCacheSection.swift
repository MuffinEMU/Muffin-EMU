import SwiftUI

/// One game's shader cache on its options screen (Advanced mode only): how big it is, clearing it for this
/// game alone, and exporting it. Settings > Shader Cache does the same for every game at once.
///
/// "Learned" is what the game has revealed by drawing with it (Wii U shader bytecode), "compiled" is the
/// output built from that, which rebuilds by itself. See cemu_bridge_clear_shader_cache.
struct GameShaderCacheSection: View {
    let game: GameMetadata
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @State private var learnedBytes: Int64 = 0
    @State private var compiledBytes: Int64 = 0
    @State private var exportableFiles: [URL] = []
    @State private var confirmClear = false
    @State private var message: String?
    @State private var messageIsError = false

    /// The Metal cache files the engine writes next to the learned shaders, named by the title ID in
    /// lowercase hex.
    private static let exportSuffixes = ["_mtlshaders.bin", "_mtlpipeline.bin"]

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("mlc/cache/shaderCache/transferable", isDirectory: true)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        bytes <= 0 ? "none" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        if SettingsMode.isAdvanced(raw: settingsModeRaw) {
            Section {
                if game.titleId != nil {
                    SettingsRow(label: "Learned shaders", value: Self.formatBytes(learnedBytes))
                    SettingsRow(label: "Compiled shaders", value: Self.formatBytes(compiledBytes))
                    Button {
                        confirmClear = true
                    } label: {
                        Label("Clear this game's shaders", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .disabled(learnedBytes <= 0 && compiledBytes <= 0)
                    Button {
                        exportShaders()
                    } label: {
                        Label("Export this game's shaders", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .disabled(exportableFiles.isEmpty)
                    if let message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(messageIsError ? .red : MuffinTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("This game's shaders are listed once the game has been identified. Start it once.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SettingsSectionHeader("Shader cache", icon: "externaldrive", accent: .core)
            } footer: {
                InfoButton.footer(
                    "This game's shaders only. Clearing needs the game closed.",
                    title: "Shader cache",
                    text: "Learned shaders are what this game has revealed by drawing with them, saved so the next start skips rebuilding them. Compiled shaders are built from those and rebuild on their own.\n\nClear this game's shaders lets you remove just the compiled ones (one slow start, nothing else lost) or everything including the learned ones (the game stutters while it relearns them).\n\nExport this game's shaders saves the Metal shader files for this game to Files, for backing up or moving to another device. The settings under Settings > Shader Cache cover every game at once.")
            }
            .foregroundColor(MuffinTheme.brownDarkest)
            .onAppear {
                if let titleId = game.titleId { refresh(titleId: titleId) }
            }
            .confirmationDialog("Clear this game's shaders?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear compiled shaders") { clear(includeLearned: false) }
                Button("Clear everything, including learned", role: .destructive) { clear(includeLearned: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(game.title) is slow to start once while it rebuilds. Clearing the learned shaders as well makes it stutter while it relearns them.")
            }
        }
    }

    private func refresh(titleId: UInt64) {
        var learned: Int64 = 0
        var compiled: Int64 = 0
        _ = cemu_bridge_shader_cache_stats(titleId, &learned, &compiled)
        learnedBytes = learned
        compiledBytes = compiled
        exportableFiles = shaderFiles(titleId: titleId)
    }

    private func shaderFiles(titleId: UInt64) -> [URL] {
        guard let directory = cacheDirectory else { return [] }
        let prefix = String(format: "%016llx", titleId)
        return Self.exportSuffixes
            .map { directory.appendingPathComponent(prefix + $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func clear(includeLearned: Bool) {
        guard let titleId = game.titleId else { return }
        let freed = cemu_bridge_clear_shader_cache(titleId, includeLearned)
        if freed < 0 {
            message = "Close the game first, then clear its shaders."
            messageIsError = true
        } else {
            message = "Freed \(Self.formatBytes(freed)). "
                + (includeLearned ? "The game stutters while it relearns its shaders." : "The next start of this game is slow once.")
            messageIsError = false
        }
        refresh(titleId: titleId)
    }

    /// Hands the shader files to the Files picker as copies, so whatever it does cannot reach the live cache.
    private func exportShaders() {
        guard let titleId = game.titleId else { return }
        let files = shaderFiles(titleId: titleId)
        guard !files.isEmpty else {
            message = "There are no shader files for this game yet. Play it first."
            messageIsError = true
            return
        }
        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("shader-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var copies: [URL] = []
            for file in files {
                let copy = staging.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: copy)
                copies.append(copy)
            }
            DocumentImport.presentExport(copies) { result in
                switch result {
                case .success(let urls):
                    // An empty array is a cancel, not a failure.
                    guard !urls.isEmpty else { return }
                    message = "Saved \(urls.count == 1 ? "1 file" : "\(urls.count) files") to Files."
                    messageIsError = false
                case .failure(let error):
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}
