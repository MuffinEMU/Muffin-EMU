// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Shader cache size across every game, when it last changed, and the two clear actions (compiled shaders
/// only, or everything including learned ones), each behind a confirmation. Per game: the game's Game page and Game settings.
struct ShaderCacheSection: View {
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @AppStorage("muffin.shaders.asyncCompile") private var asyncShaderCompile = true
    @State private var learnedCacheBytes: Int64 = 0
    @State private var compiledCacheBytes: Int64 = 0
    @State private var lastUpdated: Date?
    @State private var confirmClearCompiled = false
    @State private var confirmClearLearned = false
    @State private var cacheStatusMessage: String?
    @State private var cacheStatusIsError = false

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
            PerGameOverrideNote(field: .preCompileShaders)
            SettingsRow(label: "Size on disk", value: Self.formatBytes(learnedCacheBytes + compiledCacheBytes))
            SettingsRow(label: "Last updated", value: ShaderCacheInfo.formatDate(lastUpdated))
            if SettingsMode.isAdvanced(raw: settingsModeRaw) {
                SettingsRow(label: "Learned shaders", value: Self.formatBytes(learnedCacheBytes))
                SettingsRow(label: "Compiled shaders", value: Self.formatBytes(compiledCacheBytes))
            }
            Button { confirmClearCompiled = true } label: {
                Label("Clear compiled shaders", systemImage: "arrow.counterclockwise")
            }
            .disabled(compiledCacheBytes <= 0)
            Button(role: .destructive) { confirmClearLearned = true } label: {
                DestructiveSettingsLabel(title: "Clear all shaders, including learned", systemImage: "trash")
            }
            .disabled(learnedCacheBytes <= 0 && compiledCacheBytes <= 0)
            if let cacheStatusMessage {
                Text(cacheStatusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(cacheStatusIsError ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Shader cache", icon: "externaldrive", accent: .core)
        } footer: {
            InfoButton.footer("Games save the shaders they need so they start faster and stutter less. Clear compiled shaders to free space; they rebuild the next time you play. Clear all also removes learned shaders, so games stutter until they relearn them. To clear one game, use its page in the library. Close the game first.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear(perform: refreshCacheStats)
        .confirmationDialog("Clear compiled shaders for every game?", isPresented: $confirmClearCompiled, titleVisibility: .visible) {
            Button("Clear compiled shaders") { clear(includeLearned: false) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Each game is slow to start once while it rebuilds. Nothing else is lost.")
        }
        .confirmationDialog("Clear all shaders for every game?", isPresented: $confirmClearLearned, titleVisibility: .visible) {
            Button("Clear all shaders", role: .destructive) { clear(includeLearned: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Games will stutter for a while until they build their shaders again.")
        }
    }

    private func clear(includeLearned: Bool) {
        let freed = cemu_bridge_clear_shader_cache(0, includeLearned)
        if freed < 0 {
            cacheStatusMessage = "Close the game first, then clear the cache."
            cacheStatusIsError = true
        } else {
            cacheStatusMessage = "Freed \(Self.formatBytes(freed)). "
                + (includeLearned ? "Games will stutter while they relearn their shaders." : "Each game starts slowly once while it rebuilds.")
            cacheStatusIsError = false
        }
        refreshCacheStats()
    }

    private func refreshCacheStats() {
        var learned: Int64 = 0
        var compiled: Int64 = 0
        _ = cemu_bridge_shader_cache_stats(0, &learned, &compiled)
        learnedCacheBytes = learned
        compiledCacheBytes = compiled
        DispatchQueue.global(qos: .userInitiated).async {
            let newest = ShaderCacheInfo.directory.flatMap { ShaderCacheInfo.newestModification(in: $0, namePrefix: "") }
            DispatchQueue.main.async { lastUpdated = newest }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String { ShaderCacheInfo.formatBytes(bytes) }
}
