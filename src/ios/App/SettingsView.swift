// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// One section of Settings. Each is its own View struct (most under Settings/); this enum is the
/// index that places it on a page and makes it searchable. Moving a section between pages never
/// touches its storage keys.
enum SettingsItem: String, CaseIterable, Identifiable {
    case cpu, jit, graphics, shaderCache, emulatedClock
    case onScreenControls, motion, emulatedDevices
    case display, audio, overlay, notifications
    case library, coverArt, keys, wiiUMenu
    case account, network, premium
    case appearance
    case files, backup, migration
    case deviceReport, diagnostics, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .jit: return "JIT"
        case .graphics: return "Graphics"
        case .shaderCache: return "Shader cache"
        case .emulatedClock: return "Emulated clock"
        case .onScreenControls: return "On-screen controls"
        case .motion: return "Motion and aiming"
        case .emulatedDevices: return "Figure portals"
        case .display: return "Display"
        case .audio: return "Audio"
        case .overlay: return "Performance overlay"
        case .notifications: return "Notifications"
        case .library: return "Library layout"
        case .coverArt: return "Cover art"
        case .keys: return "Wii U keys"
        case .wiiUMenu: return "Wii U Menu"
        case .account: return "Account"
        case .network: return "Online service"
        case .premium: return "Premium"
        case .appearance: return "Appearance"
        case .files: return "Files"
        case .backup: return "Back up settings"
        case .migration: return "Move to another device"
        case .deviceReport: return "Device report"
        case .diagnostics: return "Diagnostics"
        case .about: return "About"
        }
    }

    /// Words people search for besides the title.
    var keywords: String {
        switch self {
        case .cpu: return "cores threads multicore interpreter speed processor performance"
        case .jit: return "recompiler stikjit stikdebug pairing debugger enabler"
        case .graphics: return "resolution upscale vsync vulkan metal renderer filter gamma frame rate"
        case .shaderCache: return "shaders stutter precompile cache compile"
        case .emulatedClock: return "timing advanced clock speed"
        case .onScreenControls: return "pad gamepad touch layout buttons skin controller sticks"
        case .motion: return "gyro motion controller aim gyroscope"
        case .emulatedDevices: return "skylanders disney infinity lego dimensions toypad portal figures toys amiibo devices"
        case .display: return "screen external tv layout single screen gamepad position orientation"
        case .audio: return "sound volume latency channels music"
        case .overlay: return "fps counter stats hud"
        case .notifications: return "alerts messages banners"
        case .library: return "games sort list grid cards covers size tap layout"
        case .coverArt: return "covers images artwork box"
        case .keys: return "keys.txt decrypt online files"
        case .wiiUMenu: return "home menu launcher"
        case .account: return "mii profile sign in"
        case .network: return "online pretendo nintendo network service servers custom"
        case .premium: return "supporter unlock purchase restore"
        case .appearance: return "theme colours colors icon dark light classic flat"
        case .files: return "storage folders paths location"
        case .backup: return "backup restore export import reset defaults"
        case .migration: return "migration export move transfer new device saves games"
        case .deviceReport: return "device info ram chip hardware"
        case .diagnostics: return "logs crash report debug"
        case .about: return "version credits licences licenses reset support"
        }
    }

    /// Hidden while Settings mode is Basic (matches what the old single page did).
    var advancedOnly: Bool { self == .emulatedClock }
}

/// The pages of Settings. They follow the header colours (SettingsSectionAccent): what decides
/// whether a game runs, what the player touches, sees and hears, what the app holds for them,
/// how it looks, then housekeeping.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case emulation, controls, screenAndSound, library, accountOnline, appearance, storage, support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emulation: return "Emulation"
        case .controls: return "Controls"
        case .screenAndSound: return "Screen and sound"
        case .library: return "Games and library"
        case .accountOnline: return "Account and online"
        case .appearance: return "Appearance"
        case .storage: return "Storage and backup"
        case .support: return "Help and about"
        }
    }

    /// The line under the title on the hub.
    var blurb: String {
        switch self {
        case .emulation: return "CPU, JIT, graphics and shaders. These decide how well games run."
        case .controls: return "On-screen pad, motion aiming and figure portals."
        case .screenAndSound: return "Screen layout, audio, the performance overlay and alerts."
        case .library: return "How the library looks, cover art, Wii U keys and the Wii U Menu."
        case .accountOnline: return "Your profile and the online service."
        case .appearance: return "Theme, colours, the app icon and Premium."
        case .storage: return "Where files live, settings backups and moving everything to another device."
        case .support: return "Device report, diagnostics, credits and reset."
        }
    }

    /// A short note at the top of the page about what matters there.
    var intro: String {
        switch self {
        case .emulation: return "The defaults suit most games, so change one thing at a time. Switch Settings mode to Advanced on the main list to see more."
        case .controls: return "Button size, sticks and opacity are under On-screen controls. Figure portals are for Skylanders, Disney Infinity and LEGO Dimensions."
        case .screenAndSound: return "Display covers screen layout and external screens. Audio, the performance overlay and pop-up notifications are here too."
        case .library: return "Choose how your games look and where cover art comes from. Add Wii U keys and the Wii U Menu here."
        case .accountOnline: return "An account is only needed for online play. The online service decides which servers games connect to."
        case .appearance: return "Looks only. None of this changes how games run."
        case .storage: return "Back up your settings before a big change or an update (Advanced mode). Move to another device exports your saves and settings, and your games if you choose."
        case .support: return "Copy the device report and send it when you ask for help."
        }
    }

    var icon: String {
        switch self {
        case .emulation: return "cpu"
        case .controls: return "gamecontroller"
        case .screenAndSound: return "tv"
        case .library: return "square.grid.2x2"
        case .accountOnline: return "person.crop.circle"
        case .appearance: return "paintpalette"
        case .storage: return "externaldrive"
        case .support: return "questionmark.circle"
        }
    }

    var accent: SettingsSectionAccent {
        switch self {
        case .emulation: return .core
        case .controls, .screenAndSound: return .io
        case .library: return .content
        case .accountOnline, .appearance: return .identity
        case .storage, .support: return .system
        }
    }

    var items: [SettingsItem] {
        switch self {
        case .emulation: return [.cpu, .jit, .graphics, .shaderCache, .emulatedClock]
        case .controls: return [.onScreenControls, .motion, .emulatedDevices]
        case .screenAndSound: return [.display, .audio, .overlay, .notifications]
        case .library: return [.library, .coverArt, .keys, .wiiUMenu]
        case .accountOnline: return [.account, .network]
        case .appearance: return [.appearance, .premium]
        case .storage: return [.files, .backup, .migration]
        case .support: return [.deviceReport, .diagnostics, .about]
        }
    }

    func visibleItems(advanced: Bool) -> [SettingsItem] {
        items.filter { advanced || !$0.advancedOnly }
    }

    /// The hub's titled groups.
    static let groups: [(title: String, categories: [SettingsCategory])] = [
        ("Playing games", [.emulation, .controls, .screenAndSound]),
        ("Library and online", [.library, .accountOnline]),
        ("The app", [.appearance, .storage, .support]),
    ]

    func owns(_ item: SettingsItem) -> Bool { items.contains(item) }

    static func category(of item: SettingsItem) -> SettingsCategory {
        allCases.first { $0.owns(item) } ?? .support
    }
}

/// Settings opens on a short list of pages (with search), and each page holds its sections. Every
/// section is its own View struct, so the type checker isn't asked to infer one huge Form
/// expression. Searching lists matching sections and opens them directly.
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

    private var isAdvanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    @ViewBuilder private func sectionView(_ item: SettingsItem) -> some View {
        switch item {
        case .cpu: CPUSettingsSection()
        case .jit: JITEnablerSection()
        case .graphics: GraphicsSettingsSection()
        case .shaderCache: ShaderCacheSection()
        case .emulatedClock: EmulatedClockSection()
        case .onScreenControls: OnScreenControlsSection()
        case .motion: MotionSettingsSection()
        case .emulatedDevices: EmulatedDevicesSettingsSection()
        case .display: DisplaySettingsSection()
        case .audio: AudioSettingsSection()
        case .overlay: OverlaySettingsSection()
        case .notifications: NotificationSettingsSection()
        case .library: LibrarySettingsSection(gameManager: gameManager)
        case .coverArt: CoverDataSettingsSection(gameManager: gameManager)
        case .keys: KeysSettingsSection()
        case .wiiUMenu: WiiUMenuSettingsSection()
        case .account: AccountSettingsSection()
        case .network: NetworkServiceSettingsSection()
        case .premium: PremiumSettingsSection()
        case .appearance:
            AppearanceSettingsSection(showingIconPicker: $showingIconPicker, showingThemePicker: $showingThemePicker)
        case .files: FilesSettingsSection()
        case .backup: SettingsBackupSection()
        case .migration: MigrationSettingsSection()
        case .deviceReport: DeviceReportSection()
        case .diagnostics: DiagnosticsSection()
        case .about: AboutSettingsSection()
        }
    }

    private func pageBackground<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            MuffinTheme.backgroundGradient
                .ignoresSafeArea()

            Form {
                content()
            }
        }
        .navigationTitle(title)
        .muffinOpaqueNavigationBar(MuffinTheme.formGround)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryPage(_ category: SettingsCategory) -> some View {
        pageBackground(category.title) {
            Section {
                Text(category.intro)
                    .font(.system(size: 13))
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(category.visibleItems(advanced: isAdvanced)) { item in
                sectionView(item)
            }
        }
    }

    private func iconChip(_ icon: String, _ accent: SettingsSectionAccent) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(accent.color)
            .frame(width: 34, height: 34)
            .background(accent.color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func hubRow(_ category: SettingsCategory) -> some View {
        NavigationLink {
            categoryPage(category)
        } label: {
            HStack(spacing: 12) {
                iconChip(category.icon, category.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(category.blurb)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func resultRow(_ item: SettingsItem) -> some View {
        let category = SettingsCategory.category(of: item)
        return NavigationLink {
            pageBackground(item.title) { sectionView(item) }
        } label: {
            HStack(spacing: 12) {
                iconChip(category.icon, category.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("In \(category.title)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }

    /// Sections matching a search: by title, by keyword, or because their page's title matches.
    private var results: [SettingsItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return SettingsItem.allCases.filter { item in
            guard isAdvanced || !item.advancedOnly else { return false }
            return item.title.lowercased().contains(q)
                || item.keywords.contains(q)
                || SettingsCategory.category(of: item).title.lowercased().contains(q)
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    @ViewBuilder private var hub: some View {
        Form {
            if isSearching {
                if results.isEmpty {
                    Section {
                        Text("Nothing in Settings matches \"\(query)\".")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section(header: Text("Results")) {
                        ForEach(results) { item in
                            resultRow(item)
                        }
                    }
                }
            } else {
                SettingsModeSection()
                ForEach(SettingsCategory.groups, id: \.title) { group in
                    Section(header: Text(group.title)) {
                        ForEach(group.categories) { category in
                            hubRow(category)
                        }
                    }
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
