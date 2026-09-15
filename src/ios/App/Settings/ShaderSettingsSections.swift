import SwiftUI

/// Whether a shader is built while the game keeps running, or the game waits for
/// it. Its own section rather than folded into Graphics or Shader Cache - it used
/// to share a single "Performance" section with resolution/stretch/vsync, which
/// read as one bundled decision when it is not: Nano Assault Neo needs this OFF
/// while every other tested game wants it ON, and that only makes sense as a real
/// per-setting choice. The per-game override for this one lives in the library's
/// long-press menu, not here - this is the global default it falls back to.
struct ShaderCompilationSection: View {
    @AppStorage("muffin.shaders.asyncCompile") private var asyncShaderCompile = true

    var body: some View {
        Section {
            Toggle(isOn: $asyncShaderCompile) {
                Text("Compile shaders in the background")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: asyncShaderCompile) { newValue in
                cemu_bridge_set_async_shader_compile(newValue)
            }
        } header: {
            Text("Shader Compilation")
        } footer: {
            InfoButton.footer(
                "On, the game keeps running while a new shader builds, which can flicker or appear late the first time it's drawn. Nano Assault Neo needs its own per-game override (long-press it in your library) instead of this off for everyone.",
                title: "Shader Compilation",
                text: "On, the game keeps running while new shaders are built, and you may see something flicker or appear late the first time it is drawn. Off, the game waits for each one, which stutters instead. Neither can build a shader before the game first uses it - the Wii U only reveals them as it draws.\n\nNano Assault Neo specifically breaks with this on - use its own per-game override (long-press the game in your library) rather than turning this off for everyone.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Storage and clearing, split out of what used to be "Performance" into its own
/// section - a shader cache is disk state, not a performance knob, and the two
/// clear actions cost very different things (a slow next launch vs. throwing away
/// something only playing can earn back), which is exactly why there are two
/// buttons here rather than one "clear cache" button that hides that difference.
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
                    ? "Cannot clear this while a game is running."
                    : "Freed \(Self.formatBytes(freed)). The next launch of each game is slow once, then back to normal."
                refreshCacheStats()
            } label: {
                Label("Clear compiled shaders", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) { confirmClearLearned = true } label: {
                Label("Clear everything, including learned", systemImage: "trash")
            }
            if let cacheStatusMessage {
                Text(cacheStatusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Shader Cache")
        } footer: {
            // Already one short sentence pair - nothing to cut behind an info button.
            Text("Learned shaders are what a game has revealed by drawing with them, saved so the next launch skips rebuilding them. Compiled shaders rebuild on their own.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear(perform: refreshCacheStats)
        .confirmationDialog("Clear learned shaders too?", isPresented: $confirmClearLearned, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                let freed = cemu_bridge_clear_shader_cache(0, true)
                cacheStatusMessage = freed < 0
                    ? "Cannot clear this while a game is running."
                    : "Freed \(Self.formatBytes(freed)). Games will stutter while they relearn their shaders."
                refreshCacheStats()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone by pressing a button - each game only relearns its shaders by being played again.")
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
