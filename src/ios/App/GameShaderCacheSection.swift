import SwiftUI

/// What the shader cache settings screens show about a cache beyond its size. Everything here reads the
/// cache folder or opens a cache file read-only (cemu_bridge_cache_file_inspect), so it never changes one.
enum ShaderCacheInfo {
    struct Overview {
        var shaders: Int?
        var pipelines: Int?
        var updated: Date?
    }

    static var directory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("mlc/cache/shaderCache/transferable", isDirectory: true)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        bytes <= 0 ? "none" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formatDate(_ date: Date?) -> String {
        guard let date else { return "never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Counts the entries in the cache files for the renderer that is selected. Blocking: call it off the
    /// main thread. Counts stay nil while a game is running, because its cache files are open for writing.
    static func overview(titleId: UInt64) -> Overview {
        guard let directory else { return Overview() }
        let prefix = String(format: "%016llx", titleId)
        let vulkan = ShaderCacheImport.selectedRenderer == .vulkan
        let shaderName = prefix + (vulkan ? "_shaders.bin" : "_mtlshaders.bin")
        let pipelineName = prefix + (vulkan ? "_vkpipeline.bin" : "_mtlpipeline.bin")
        var result = Overview()
        result.updated = newestModification(in: directory, namePrefix: prefix)
        if cemu_bridge_is_title_running() { return result }
        result.shaders = entryCount(directory.appendingPathComponent(shaderName), titleId: titleId)
        result.pipelines = entryCount(directory.appendingPathComponent(pipelineName), titleId: titleId)
        return result
    }

    /// The newest change to any cache file in the folder whose name starts with `namePrefix` (every game
    /// when it is empty).
    static func newestModification(in directory: URL, namePrefix: String) -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "bin" && $0.lastPathComponent.hasPrefix(namePrefix) }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    private static func entryCount(_ file: URL, titleId: UInt64) -> Int? {
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        var info = CemuCacheFileInfo()
        file.path.withCString { cemu_bridge_cache_file_inspect(titleId, $0, &info) }
        return Int(info.status) == Int(CEMU_CACHE_STATUS_OK.rawValue) ? Int(info.entryCount) : nil
    }

    static func countText(_ count: Int?) -> String {
        guard let count else { return "not available" }
        return count == 0 ? "none" : count.formatted()
    }
}

/// One game's shader cache on its options screen: how much is cached and when it last changed, clearing
/// it for this game alone, and (Advanced mode) the counts, the learned/compiled split and exporting it.
/// Settings > Shader Cache does the same for every game at once.
///
/// "Learned" is what the game has revealed by drawing with it (Wii U shader bytecode), "compiled" is the
/// output built from that, which rebuilds by itself. See cemu_bridge_clear_shader_cache.
struct GameShaderCacheSection: View {
    let game: GameMetadata
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @State private var learnedBytes: Int64 = 0
    @State private var compiledBytes: Int64 = 0
    @State private var overview = ShaderCacheInfo.Overview()
    @State private var exportableFiles: [URL] = []
    @State private var confirmClear = false
    @State private var message: String?
    @State private var messageIsError = false

    /// The Metal cache files the engine writes next to the learned shaders, named by the title ID in
    /// lowercase hex.
    private static let exportSuffixes = ["_mtlshaders.bin", "_mtlpipeline.bin"]

    private var cacheDirectory: URL? { ShaderCacheInfo.directory }

    private static func formatBytes(_ bytes: Int64) -> String { ShaderCacheInfo.formatBytes(bytes) }

    private var isAdvanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    var body: some View {
        if game.titleId != nil || isAdvanced {
            Section {
                if game.titleId != nil {
                    SettingsRow(label: "Size on disk", value: Self.formatBytes(learnedBytes + compiledBytes))
                    SettingsRow(label: "Last updated", value: ShaderCacheInfo.formatDate(overview.updated))
                    if isAdvanced {
                        SettingsRow(label: "Learned shaders", value: Self.formatBytes(learnedBytes))
                        SettingsRow(label: "Compiled shaders", value: Self.formatBytes(compiledBytes))
                        SettingsRow(label: "Shaders cached", value: ShaderCacheInfo.countText(overview.shaders))
                        SettingsRow(label: "Pipelines cached", value: ShaderCacheInfo.countText(overview.pipelines))
                    }
                    Button {
                        confirmClear = true
                    } label: {
                        Label("Clear this game's shaders", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .disabled(learnedBytes <= 0 && compiledBytes <= 0)
                    if isAdvanced {
                        Button {
                            exportShaders()
                        } label: {
                            Label("Export this game's shaders", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .disabled(exportableFiles.isEmpty)
                    }
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
                    "What this game has saved so it starts faster. Clearing needs the game closed.",
                    title: "Shader cache",
                    text: "A shader cache is what a game has saved so the next start skips building its shaders again. Size on disk is everything saved for this game, and Last updated is the last time any of it changed.\n\nClear this game's shaders lets you remove just the compiled ones (one slow start, nothing else lost) or everything including the learned ones (the game stutters while it relearns them).\n\nAdvanced mode also shows how many shaders and pipelines are saved for the renderer you've selected, splits the size into learned and compiled, and can export this game's Metal shader files to Files, for backing up or moving to another device. The counts are hidden while a game is running. The settings under Settings > Shader Cache cover every game at once.")
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
        DispatchQueue.global(qos: .userInitiated).async {
            let fresh = ShaderCacheInfo.overview(titleId: titleId)
            DispatchQueue.main.async { overview = fresh }
        }
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
