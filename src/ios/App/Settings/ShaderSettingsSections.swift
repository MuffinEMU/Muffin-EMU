import SwiftUI

/// Whether a shader is built while the game keeps running, or the game waits for it. This is
/// the global default; the per-game override is in the library's long-press menu.
struct ShaderCompilationSection: View {
    @AppStorage("muffin.shaders.asyncCompile") private var asyncShaderCompile = true

    var body: some View {
        Section {
            Toggle(isOn: $asyncShaderCompile) {
                Text("Compile shaders in the background")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: asyncShaderCompile) { newValue in
                cemu_bridge_set_async_shader_compile(newValue)
            }
        } header: {
            SettingsSectionHeader("Shader Compilation", icon: "hammer", accent: .core)
        } footer: {
            InfoButton.footer(
                "On keeps the game running while a shader builds; things may flicker the first time they appear. Off waits for each shader and stutters instead.",
                title: "Shader Compilation",
                text: "On, the game keeps running while new shaders are built, and you may see something flicker or appear late the first time it is drawn. Off, the game waits for each one, which stutters instead.\n\nNano Assault Neo breaks with this on. Set it off for that game only: long-press it in your library.\n\nFavour accuracy (under CPU) always waits for each shader, whatever this is set to. It applies the next time you start a game.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Shader cache sizes and the two clear actions (compiled shaders only, or everything
/// including learned ones).
struct ShaderCacheSection: View {
    @State private var learnedCacheBytes: Int64 = 0
    @State private var compiledCacheBytes: Int64 = 0
    @State private var confirmClearLearned = false
    @State private var cacheStatusMessage: String?

    var body: some View {
        Section {
            SettingsRow(label: "Compiled shaders", value: Self.formatBytes(compiledCacheBytes))
            SettingsRow(label: "Learned shaders", value: Self.formatBytes(learnedCacheBytes))
            Button {
                let freed = cemu_bridge_clear_shader_cache(0, false)
                cacheStatusMessage = freed < 0
                    ? "Close the game first, then clear the cache."
                    : "Freed \(Self.formatBytes(freed)). The next launch of each game is slow once."
                refreshCacheStats()
            } label: {
                Label("Clear compiled shaders", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) { confirmClearLearned = true } label: {
                DestructiveSettingsLabel(title: "Clear everything, including learned", systemImage: "trash")
            }
            if let cacheStatusMessage {
                Text(cacheStatusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        } header: {
            SettingsSectionHeader("Shader Cache", icon: "externaldrive", accent: .core)
        } footer: {
            InfoButton.footer("Learned shaders are what a game has revealed by drawing with them, saved so the next launch skips rebuilding them. Compiled shaders rebuild on their own.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear(perform: refreshCacheStats)
        .confirmationDialog("Clear learned shaders too?", isPresented: $confirmClearLearned, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                let freed = cemu_bridge_clear_shader_cache(0, true)
                cacheStatusMessage = freed < 0
                    ? "Close the game first, then clear the cache."
                    : "Freed \(Self.formatBytes(freed)). Games will stutter while they relearn their shaders."
                refreshCacheStats()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Games will stutter while they rebuild their shaders.")
        }
    }

    private func refreshCacheStats() {
        var learned: Int64 = 0
        var compiled: Int64 = 0
        _ = cemu_bridge_shader_cache_stats(0, &learned, &compiled)
        learnedCacheBytes = learned
        compiledCacheBytes = compiled
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "none" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 { value /= 1024; unit += 1 }
        return unit == 0 ? "\(Int(value)) B" : String(format: "%.1f %@", value, units[unit])
    }
}
