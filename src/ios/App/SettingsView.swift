// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// The five groups Settings is split into. They follow the header colours (SettingsSectionAccent):
/// what decides whether a game runs, what the player touches, sees and hears, what the app holds
/// for them, how it looks, then housekeeping with About last.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case emulation, playing, library, appearance, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emulation: return "Emulation"
        case .playing: return "Controls, display and sound"
        case .library: return "Games and accounts"
        case .appearance: return "Appearance"
        case .system: return "Files, backup and about"
        }
    }

    var icon: String {
        switch self {
        case .emulation: return "cpu"
        case .playing: return "gamecontroller"
        case .library: return "square.grid.2x2"
        case .appearance: return "paintpalette"
        case .system: return "gearshape"
        }
    }

    var accent: SettingsSectionAccent {
        switch self {
        case .emulation: return .core
        case .playing: return .io
        case .library: return .content
        case .appearance: return .identity
        case .system: return .system
        }
    }

    /// Every section on the page, with words people search for. The first entry is what the row shows.
    var items: [(title: String, keywords: String)] {
        switch self {
        case .emulation:
            return [("CPU", "cores threads multicore interpreter speed"),
                    ("JIT", "recompiler stikjit stikdebug pairing debugger enabler"),
                    ("Graphics", "resolution upscale vsync vulkan metal renderer"),
                    ("Shader cache", "shaders stutter precompile cache"),
                    ("Emulated clock", "timing advanced")]
        case .playing:
            return [("On-screen controls", "pad gamepad touch layout buttons skin"),
                    ("Motion and aiming", "gyro motion controller aim"),
                    ("Display", "screen external tv layout single screen"),
                    ("Audio", "sound volume latency"),
                    ("Performance overlay", "fps counter stats"),
                    ("Notifications", "alerts messages")]
        case .library:
            return [("Library", "games folders import sort"),
                    ("Cover art", "covers images artwork"),
                    ("Wii U keys", "keys.txt decrypt"),
                    ("Wii U Menu", "home menu"),
                    ("Account", "mii profile"),
                    ("Network service", "online pretendo nintendo network"),
                    ("Emulated devices", "controllers wiimote usb")]
        case .appearance:
            return [("Appearance", "theme colours icon dark light"),
                    ("Premium", "supporter unlock")]
        case .system:
            return [("Files", "storage folders paths"),
                    ("Back up settings", "backup restore export"),
                    ("Migration", "import move transfer"),
                    ("Device report", "device info ram chip"),
                    ("Diagnostics", "logs crash report debug"),
                    ("About", "version credits licences reset")]
        }
    }

    /// Items matching a search, or all of them when the query is empty.
    func matches(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return items.map { $0.title } }
        if title.lowercased().contains(q) { return items.map { $0.title } }
        return items.filter { $0.title.lowercased().contains(q) || $0.keywords.contains(q) }.map { $0.title }
    }
}

/// Settings opens on a list of five groups (with search) and each group opens its own page, instead
/// of one long list of every section. Every section is still its own View struct (most under
/// Settings/), so the type checker isn't asked to infer one huge Form expression; ViewBuilder allows
/// at most 10 children per block, which each page stays under.
struct SettingsView: View {
    // Observed so flipping Classic UI or Flat surfaces repaints this subtree immediately.
    @ObservedObject private var uiStyle = UIStyleStore.shared

    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingThemePicker = false
    @State private var query = ""
    @ObservedObject private var accountSheets = AccountSheetRouter.shared
    /// Basic hides the advanced rows (see AdvancedSettings); the pages need it for whole sections.
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    @ViewBuilder private func page(_ category: SettingsCategory) -> some View {
        switch category {
        case .emulation:
            CPUSettingsSection()
            JITEnablerSection()
            GraphicsSettingsSection()
            ShaderCacheSection()
            if SettingsMode.isAdvanced(raw: settingsModeRaw) {
                EmulatedClockSection()
            }
        case .playing:
            OnScreenControlsSection()
            MotionSettingsSection()
            DisplaySettingsSection()
            AudioSettingsSection()
            OverlaySettingsSection()
            NotificationSettingsSection()
        case .library:
            LibrarySettingsSection(gameManager: gameManager)
            CoverDataSettingsSection(gameManager: gameManager)
            KeysSettingsSection()
            WiiUMenuSettingsSection()
            AccountSettingsSection()
            NetworkServiceSettingsSection()
            EmulatedDevicesSettingsSection()
        case .appearance:
            AppearanceSettingsSection(showingIconPicker: $showingIconPicker, showingThemePicker: $showingThemePicker)
            PremiumSettingsSection()
        case .system:
            FilesSettingsSection()
            SettingsBackupSection()
            MigrationSettingsSection()
            DeviceReportSection()
            DiagnosticsSection()
            AboutSettingsSection()
        }
    }

    /// Plain Form on iOS's grouped background. Hiding the background makes the text
    /// unreadable with the current colours.
    private func categoryPage(_ category: SettingsCategory) -> some View {
        ZStack {
            MuffinTheme.backgroundGradient
                .ignoresSafeArea()

            Form {
                page(category)
            }
        }
        .navigationTitle(category.title)
        .muffinOpaqueNavigationBar(MuffinTheme.formGround)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hubRow(_ category: SettingsCategory, matches: [String]) -> some View {
        NavigationLink {
            categoryPage(category)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(category.accent.color)
                    .frame(width: 34, height: 34)
                    .background(category.accent.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(matches.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private var hub: some View {
        let shown = SettingsCategory.allCategoryMatches(query)
        return Form {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                SettingsModeSection()
            }
            Section {
                ForEach(shown, id: \.category.id) { entry in
                    hubRow(entry.category, matches: entry.titles)
                }
            }
            if shown.isEmpty {
                Section {
                    Text("Nothing in Settings matches \"\(query)\".")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                hub
            }
            .navigationTitle("Settings")
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.accentText)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView()
            }
            .sheet(isPresented: $showingThemePicker) {
                ThemePickerView()
            }
            .sheet(isPresented: $accountSheets.showingCreateAccount, onDismiss: accountSheets.sheetClosed) {
                CreateAccountView()
            }
        }
        .navigationViewStyle(.stack)
    }
}

private extension SettingsCategory {
    /// The groups that match a search, each with the section names that matched.
    static func allCategoryMatches(_ query: String) -> [(category: SettingsCategory, titles: [String])] {
        allCases.compactMap { category in
            let titles = category.matches(query)
            return titles.isEmpty ? nil : (category, titles)
        }
    }
}
