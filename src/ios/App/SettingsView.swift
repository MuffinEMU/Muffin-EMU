// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// One section of Settings. Each is its own View struct (most under Settings/); this enum is the
/// index that places it on a page and makes it searchable. Moving a section between pages never
/// touches its storage keys.
enum SettingsItem: String, CaseIterable, Identifiable {
    case language, settingsMode, changedSettings, appearance, about
    case performance, cpu, jit, graphics, shaderCache, emulatedClock
    case onScreenControls, motion, emulatedDevices
    case display, externalDisplay, audio, overlay, notifications
    case library, coverArt, keys, wiiUMenu
    case account, network, premium
    case files, backup, migration
    case deviceReport, diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .language: return "Language".localized
        case .settingsMode: return "Settings mode".localized
        case .changedSettings: return "Changed from default".localized
        case .appearance: return "Appearance".localized
        case .about: return "About".localized
        case .performance: return "Performance".localized
        case .cpu: return "CPU".localized
        case .jit: return "JIT".localized
        case .graphics: return "Graphics".localized
        case .shaderCache: return "Shaders".localized
        case .emulatedClock: return "Emulated Clock".localized
        case .onScreenControls: return "On-screen Controls".localized
        case .motion: return "Motion & Aiming".localized
        case .emulatedDevices: return "Emulated Devices".localized
        case .display: return "Display".localized
        case .externalDisplay: return "External Display".localized
        case .audio: return "Audio".localized
        case .overlay: return "Performance Overlay".localized
        case .notifications: return "Notifications".localized
        case .library: return "Library".localized
        case .coverArt: return "Cover + data scraping".localized
        case .keys: return "Wii U Keys".localized
        case .wiiUMenu: return "Wii U Menu".localized
        case .account: return "Account".localized
        case .network: return "Network Service".localized
        case .premium: return "Premium".localized
        case .files: return "Your Files".localized
        case .backup: return "Back up settings".localized
        case .migration: return "Move to the new MuffinEMU".localized
        case .deviceReport: return "This Device".localized
        case .diagnostics: return "Diagnostics".localized
        }
    }

    /// One line saying what the section holds: under its name in a page's list of sections, so you can
    /// tell which one you want before opening it.
    var summary: String {
        switch self {
        case .language: return "The language MuffinEMU's menus are in.".localized
        case .settingsMode: return "Basic or Advanced: how many options Settings shows.".localized
        case .changedSettings: return "Every setting you've changed, and games with settings of their own.".localized
        case .appearance: return "Theme, app icon, Flat surfaces and Classic UI.".localized
        case .about: return "Version, credits, licences and reset.".localized
        case .performance: return "The performance profile, pausing a hidden screen, and cooling down.".localized
        case .cpu: return "What the CPU runs, CPU cores and memory.".localized
        case .jit: return "The recompiler, whether JIT is on, and the enabler that turns it on.".localized
        case .graphics: return "Renderer, resolution, filtering, frame rate and graphic packs.".localized
        case .shaderCache: return "Compiling in the background, cache size and clearing.".localized
        case .emulatedClock: return "The emulated console's clock speed.".localized
        case .onScreenControls: return "The touch pad: size, opacity, sticks and when it hides.".localized
        case .motion: return "Aiming by tilting this device or a controller.".localized
        case .emulatedDevices: return "Skylanders, Disney Infinity and LEGO Dimensions.".localized
        case .display: return "Screen layout, stretching, portrait and brightness.".localized
        case .externalDisplay: return "A TV or second screen.".localized
        case .audio: return "TV and GamePad sound, the microphone and recording.".localized
        case .overlay: return "The FPS and usage readout over the game: what it lists, and where.".localized
        case .notifications: return "Pop-ups during games: which ones, and where.".localized
        case .library: return "How the library looks, and linked folders and files.".localized
        case .coverArt: return "Cover style, art packs and data scraping.".localized
        case .keys: return "The keys.txt encrypted games need.".localized
        case .wiiUMenu: return "The Wii U Menu and its system files.".localized
        case .account: return "Your Wii U accounts.".localized
        case .network: return "Which servers games connect to.".localized
        case .premium: return "The pro app icons.".localized
        case .files: return "Where MuffinEMU keeps its files.".localized
        case .backup: return "Export or import your settings.".localized
        case .migration: return "Export everything, or import from the old MuffinEMU.".localized
        case .deviceReport: return "Copy a device report to send with a bug report.".localized
        case .diagnostics: return "The launch intro, launch log and controls diagnostic.".localized
        }
    }

    /// Words people search for besides the title.
    var keywords: String {
        switch self {
        case .language: return "language translation translate idioma langue sprache lingua"
        case .settingsMode: return "basic advanced simple more options hidden"
        case .changedSettings: return "changed modified custom different defaults per game overrides"
        case .appearance: return "theme colours colors icon dark light classic flat look"
        case .about: return "version credits licences licenses reset support defaults github documentation"
        case .performance: return "speed performance profile accuracy balanced battery saver heat thermal cool hot throttle pause hidden screen tv gamepad"
        case .cpu: return "cores threads multicore interpreter processor memory"
        case .jit: return "recompiler interpreter stikjit stikdebug pairing debugger enabler"
        case .graphics: return "resolution upscale vsync vulkan metal renderer filter gamma frame rate texture filtering anisotropic sharp blurry distance steady graphic packs mods patches"
        case .shaderCache: return "shaders stutter precompile cache compile background"
        case .emulatedClock: return "timing advanced clock speed"
        case .onScreenControls: return "pad gamepad touch layout buttons skin controller sticks haptic opacity size deadzone top bar hide"
        case .motion: return "gyro motion controller aim gyroscope tilt sensitivity"
        case .emulatedDevices: return "skylanders disney infinity lego dimensions toypad portal figures toys amiibo devices"
        case .display: return "screen layout single screen gamepad position orientation portrait brightness swap stretch aspect ratio flip upside down"
        case .externalDisplay: return "tv external second screen monitor hdmi airplay swap"
        case .audio: return "sound volume latency channels music microphone mic record"
        case .overlay: return "fps counter stats hud performance overlay readout frame rate speed cpu ram"
        case .notifications: return "alerts messages banners pop-ups battery"
        case .library: return "games sort list grid cards covers size tap layout linked folders drive removed restore"
        case .coverArt: return "covers images artwork box art packs"
        case .keys: return "keys.txt decrypt online files encrypted"
        case .wiiUMenu: return "home menu launcher system"
        case .account: return "mii profile sign in"
        case .network: return "online service pretendo nintendo network servers custom play"
        case .premium: return "supporter unlock purchase restore pro icons"
        case .files: return "storage folders paths location"
        case .backup: return "backup restore export import settings file"
        case .migration: return "migration export move transfer new device saves games"
        case .deviceReport: return "device info ram chip hardware bug report problem help log crash share"
        case .diagnostics: return "logs crash report debug launch intro readout"
        }
    }

    /// Hidden while Settings mode is Basic (matches what the old single page did).
    var advancedOnly: Bool { self == .emulatedClock }
}

/// The pages of Settings. They follow the header colours (SettingsSectionAccent): the app itself,
/// then what decides whether a game runs, what the player touches, sees and hears, what the app
/// holds for them, then housekeeping.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, emulation, controls, screenAndSound, library, accountOnline, storage, support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General".localized
        case .emulation: return "Performance and graphics".localized
        case .controls: return "Controls".localized
        case .screenAndSound: return "Screen and sound".localized
        case .library: return "Games and library".localized
        case .accountOnline: return "Account and online".localized
        case .storage: return "Storage and backup".localized
        case .support: return "Help".localized
        }
    }

    /// The line under the title on the one-column list of pages.
    var blurb: String {
        switch self {
        case .general: return "Language, Settings mode, how MuffinEMU looks, Premium and About.".localized
        case .emulation: return "How fast games run and how they look: the performance profile, JIT, CPU, resolution and shaders.".localized
        case .controls: return "The on-screen pad, motion aiming and figure portals.".localized
        case .screenAndSound: return "Screen layout, a TV or second screen, audio, the performance overlay and alerts.".localized
        case .library: return "Wii U keys, how the library looks and cover art.".localized
        case .accountOnline: return "Your Wii U accounts, online play and the Wii U Menu.".localized
        case .storage: return "Where files live, settings backups and moving to the new MuffinEMU.".localized
        case .support: return "This device's report for bug reports, and diagnostics.".localized
        }
    }

    /// A short note at the top of the page about what matters there.
    var intro: String {
        switch self {
        case .general: return "None of this changes how games run. Switch Settings mode to Advanced to see every option on the other pages.".localized
        case .emulation: return "The defaults suit most games, so change one thing at a time. Performance profile, at the top, is the quickest way to trade speed against accuracy or battery. A single game can have its own values: open it in the library, then Game settings.".localized
        case .controls: return "Button size, sticks and opacity are under On-screen Controls. Emulated Devices are the Skylanders, Disney Infinity and LEGO Dimensions portals.".localized
        case .screenAndSound: return "Display is this device's screen. External Display is a TV or second screen. Audio, the performance overlay and pop-up notifications are here too.".localized
        case .library: return "Encrypted games need Wii U keys, so they come first. Then how your games look and where cover art comes from.".localized
        case .accountOnline: return "An account is only needed for online play. Network Service decides which servers games connect to. The Wii U Menu is the console's own home screen and system files.".localized
        case .storage: return "Back up your settings before a big change or an update. Move to the new MuffinEMU exports your saves and settings, and your games if you choose.".localized
        case .support: return "Copy device report lists your chip, memory and app build. Send it with any bug report.".localized
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .emulation: return "cpu"
        case .controls: return "gamecontroller"
        case .screenAndSound: return "tv"
        case .library: return "square.grid.2x2"
        case .accountOnline: return "person.crop.circle"
        case .storage: return "externaldrive"
        case .support: return "questionmark.circle"
        }
    }

    var accent: SettingsSectionAccent {
        switch self {
        case .emulation: return .core
        case .controls, .screenAndSound: return .io
        case .library: return .content
        case .accountOnline: return .identity
        case .general, .storage, .support: return .system
        }
    }

    var items: [SettingsItem] {
        switch self {
        case .general: return [.language, .settingsMode, .changedSettings, .appearance, .premium, .about]
        case .emulation: return [.performance, .cpu, .jit, .graphics, .shaderCache, .emulatedClock]
        case .controls: return [.onScreenControls, .motion, .emulatedDevices]
        case .screenAndSound: return [.display, .externalDisplay, .audio, .overlay, .notifications]
        case .library: return [.keys, .library, .coverArt]
        case .accountOnline: return [.account, .network, .wiiUMenu]
        case .storage: return [.files, .backup, .migration]
        case .support: return [.deviceReport, .diagnostics]
        }
    }

    func visibleItems(advanced: Bool) -> [SettingsItem] {
        items.filter { advanced || !$0.advancedOnly }
    }

    /// The titled groups under General.
    static let groups: [(title: String, categories: [SettingsCategory])] = [
        ("Playing".localized, [.emulation, .controls, .screenAndSound]),
        ("Your games".localized, [.library, .accountOnline]),
        ("This app".localized, [.storage, .support]),
    ]

    /// Something on this page that needs the player's attention, shown in place of the blurb: the two
    /// things that most often make MuffinEMU look broken. Nil when all is well.
    @MainActor
    var attention: String? {
        switch self {
        case .emulation: return JITStatus.isActive ? nil : "JIT is off, so games run slower. Open to set it up.".localized
        case .library: return WiiUKeys.keysFileExists() ? nil : "No keys.txt yet, so encrypted games won't start.".localized
        default: return nil
        }
    }

    func owns(_ item: SettingsItem) -> Bool { items.contains(item) }

    static func category(of item: SettingsItem) -> SettingsCategory {
        allCases.first { $0.owns(item) } ?? .general
    }
}

/// What the detail pane is showing: a whole page, or a page scrolled to one of its sections (picked in
/// the sidebar or from a search result).
enum SettingsRoute: Hashable {
    case category(SettingsCategory)
    case item(SettingsItem)
    /// A setting found by search, shown as the section that holds it. Its own case so each result row
    /// in the sidebar has its own selection tag.
    case setting(SettingEntry)

    var category: SettingsCategory {
        switch self {
        case .category(let category): return category
        case .item(let item): return SettingsCategory.category(of: item)
        case .setting(let entry): return SettingsCategory.category(of: entry.item)
        }
    }

    var item: SettingsItem? {
        switch self {
        case .category: return nil
        case .item(let item): return item
        case .setting(let entry): return entry.item
        }
    }
}

/// Settings has two shapes, both built from the same pages and sections:
///
/// - A wide screen (iPad, iOS 16+) shows a sidebar beside the open page. The open page's sections
///   are listed under it in the sidebar, so one tap scrolls to the one you want and you can always
///   see where you are.
/// - A narrow screen (iPhone, Slide Over, iOS 15) opens a page as a short list of its sections, each
///   with a line saying what it holds, and a section on its own screen. No long scroll past
///   sections you didn't come for.
///
/// Every section is its own View struct, so the type checker isn't asked to infer one huge Form
/// expression. Searching lists matching sections and opens them.
struct SettingsView: View {
    // Observed so flipping Classic UI or Flat surfaces repaints this subtree immediately.
    @ObservedObject private var uiStyle = UIStyleStore.shared

    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingIconPicker = false
    @State private var showingThemePicker = false
    @State private var query = ""
    /// Which page the detail pane shows in the sidebar layout. Opens on General, the page at the
    /// top of the sidebar.
    @State private var selection: SettingsRoute? = .category(.general)
    @ObservedObject private var accountSheets = AccountSheetRouter.shared
    /// Basic hides the advanced rows (see AdvancedSettings); the pages need it for whole sections.
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var isAdvanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    /// Narrow: pages open as lists of sections. Wide: the sidebar lists the open page's sections.
    private var isCompact: Bool { horizontalSizeClass != .regular }

    @ViewBuilder private func sectionView(_ item: SettingsItem) -> some View {
        switch item {
        case .language: LanguageSettingsSection()
        case .settingsMode: SettingsModeSection()
        case .changedSettings: ChangedSettingsSection(open: { AnyView(sectionPage($0)) })
        case .appearance:
            AppearanceSettingsSection(showingIconPicker: $showingIconPicker, showingThemePicker: $showingThemePicker)
        case .about: AboutSettingsSection()
        case .performance: PerformanceSettingsSection()
        case .cpu: CPUSettingsSection()
        case .jit: JITEnablerSection()
        case .graphics: GraphicsSettingsSection()
        case .shaderCache: ShaderCacheSection()
        case .emulatedClock: EmulatedClockSection()
        case .onScreenControls: OnScreenControlsSection()
        case .motion: MotionSettingsSection()
        case .emulatedDevices: EmulatedDevicesSettingsSection()
        case .display: DisplaySettingsSection()
        case .externalDisplay: ExternalDisplaySettingsSection()
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
        case .files: FilesSettingsSection()
        case .backup: SettingsBackupSection()
        case .migration: MigrationSettingsSection()
        case .deviceReport: DeviceReportSection()
        case .diagnostics: DiagnosticsSection()
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
        // A large title here reads roomier than the old centred inline one and fills the
        // top of the detail pane instead of leaving it bare.
        .navigationBarTitleDisplayMode(.large)
    }

    private func introRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(MuffinTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Pages

    /// A whole page, every section in turn (wide screens). `focus` is the section to scroll to.
    private func fullPage(_ category: SettingsCategory, focus: SettingsItem?) -> some View {
        ScrollViewReader { reader in
            pageBackground(category.title) {
                Section {
                    introRow(category.intro)
                }
                ForEach(category.visibleItems(advanced: isAdvanced)) { item in
                    sectionView(item)
                        .id(item)
                }
            }
            .onAppear { scroll(reader, to: focus, animated: false) }
            .onChange(of: focus) { scroll(reader, to: $0, animated: true) }
        }
    }

    private func scroll(_ reader: ScrollViewProxy, to item: SettingsItem?, animated: Bool) {
        guard let item else { return }
        // A beat for the Form to lay out its rows before there is anything to scroll to.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(item, anchor: .top) }
            } else {
                reader.scrollTo(item, anchor: .top)
            }
        }
    }

    /// A page as a list of its sections (narrow screens): each says what it holds and opens on its own.
    private func sectionList(_ category: SettingsCategory) -> some View {
        pageBackground(category.title) {
            Section {
                introRow(category.intro)
            }
            Section {
                ForEach(category.visibleItems(advanced: isAdvanced)) { item in
                    NavigationLink {
                        sectionPage(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(item.summary)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    /// One section on its own screen, saying which page it belongs to.
    private func sectionPage(_ item: SettingsItem) -> some View {
        let category = SettingsCategory.category(of: item)
        return pageBackground(item.title) {
            Section {
                Label(String(format: "In %@".localized, category.title), systemImage: category.icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            sectionView(item)
        }
    }

    private func page(_ category: SettingsCategory) -> some View {
        Group {
            if isCompact {
                sectionList(category)
            } else {
                fullPage(category, focus: nil)
            }
        }
    }

    /// A page's icon on a tinted tile in its accent colour, like the section headers' chips, larger.
    private func iconChip(_ icon: String, _ accent: SettingsSectionAccent) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(accent.color)
            .frame(width: 34, height: 34)
            .background(accent.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: Search

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Sections matching a search: by title, by keyword, or because their page's title matches.
    private var results: [SettingsItem] {
        let q = normalizedQuery
        guard !q.isEmpty else { return [] }
        return SettingsItem.allCases.filter { item in
            guard isAdvanced || !item.advancedOnly else { return false }
            return item.title.lowercased().contains(q)
                || item.summary.lowercased().contains(q)
                || item.keywords.contains(q)
                || SettingsCategory.category(of: item).title.lowercased().contains(q)
        }
    }

    /// Single settings matching a search by their own name, so "haptic" finds Haptic feedback and says
    /// where it is.
    private var settingResults: [SettingEntry] {
        let q = normalizedQuery
        guard !q.isEmpty else { return [] }
        return Array(SettingsIndex.search(q, advanced: isAdvanced).prefix(40))
    }

    private func path(of entry: SettingEntry) -> String {
        String(format: "%@ \u{203A} %@".localized, SettingsCategory.category(of: entry.item).title, entry.item.title)
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var noResults: some View {
        Text(String(format: "Nothing in Settings matches \"%@\".".localized, query))
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }

    // MARK: One-column list of pages (iOS 15)

    private func hubRow(_ category: SettingsCategory) -> some View {
        NavigationLink {
            page(category)
        } label: {
            HStack(spacing: 12) {
                iconChip(category.icon, category.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    if let attention = category.attention {
                        Label(attention, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MuffinTheme.cautionText)
                            .lineLimit(2)
                    } else {
                        Text(category.blurb)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func resultRow(_ item: SettingsItem) -> some View {
        let category = SettingsCategory.category(of: item)
        return NavigationLink {
            sectionPage(item)
        } label: {
            HStack(spacing: 12) {
                iconChip(category.icon, category.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(String(format: "In %@".localized, category.title))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder private var hub: some View {
        Form {
            if isSearching {
                if results.isEmpty && settingResults.isEmpty {
                    Section { noResults }
                }
                if !settingResults.isEmpty {
                    Section(header: Text("Settings")) {
                        ForEach(settingResults) { entry in
                            NavigationLink {
                                sectionPage(entry.item)
                            } label: {
                                settingResultLabel(entry)
                            }
                        }
                    }
                }
                if !results.isEmpty {
                    Section(header: Text("Sections")) {
                        ForEach(results) { item in
                            resultRow(item)
                        }
                    }
                }
            } else {
                Section {
                    hubRow(.general)
                }
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

    // MARK: Sidebar layout (iOS 16+)

    private func sidebarRow(_ category: SettingsCategory) -> some View {
        HStack(spacing: 11) {
            iconChip(category.icon, category.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if category == .general {
                    Text(isAdvanced ? "Advanced mode · theme · about".localized : "Basic mode · theme · about".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            if category.attention != nil {
                Spacer(minLength: 4)
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(MuffinTheme.cautionText)
            }
        }
        .padding(.vertical, 5)
    }

    /// A section under its page in the sidebar: indented, with a thin line in the page's colour leading
    /// back to it.
    private func sidebarSectionRow(_ item: SettingsItem, in category: SettingsCategory) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(category.accent.color.opacity(0.55))
                .frame(width: 2, height: 20)
            Text(item.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
        }
        .padding(.leading, 16)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: "%@, in %@".localized, item.title, category.title))
    }

    /// A setting found by search: its name, and the page and section it's in.
    private func settingResultLabel(_ entry: SettingEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(path(of: entry))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func searchResultRow(_ item: SettingsItem) -> some View {
        let category = SettingsCategory.category(of: item)
        return HStack(spacing: 11) {
            iconChip(category.icon, category.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(String(format: "In %@".localized, category.title))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }

    /// A page in the sidebar, with its sections under it while it's the one open (wide screens only;
    /// a collapsed sidebar opens the page straight away).
    @available(iOS 16.0, *)
    @ViewBuilder private func sidebarEntry(_ category: SettingsCategory) -> some View {
        sidebarRow(category)
            .tag(SettingsRoute.category(category))
        if !isCompact, selection?.category == category {
            ForEach(category.visibleItems(advanced: isAdvanced)) { item in
                sidebarSectionRow(item, in: category)
                    .tag(SettingsRoute.item(item))
            }
        }
    }

    @available(iOS 16.0, *)
    @ViewBuilder private var sidebar: some View {
        List(selection: $selection) {
            if isSearching {
                if results.isEmpty && settingResults.isEmpty {
                    Section { noResults }
                }
                if !settingResults.isEmpty {
                    Section(header: Text("Settings")) {
                        ForEach(settingResults) { entry in
                            settingResultLabel(entry)
                                .padding(.vertical, 3)
                                .tag(SettingsRoute.setting(entry))
                        }
                    }
                }
                if !results.isEmpty {
                    Section(header: Text("Sections")) {
                        ForEach(results) { item in
                            searchResultRow(item)
                                .tag(SettingsRoute.item(item))
                        }
                    }
                }
            } else {
                Section {
                    sidebarEntry(.general)
                }
                ForEach(SettingsCategory.groups, id: \.title) { group in
                    Section(header: Text(group.title)) {
                        ForEach(group.categories) { category in
                            sidebarEntry(category)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: 0.2), value: selection?.category)
        // The selected row pops in the theme's own accent (Bakery's is the blueberry), the same
        // accent main uses, instead of the muted system default.
        .tint(MuffinTheme.pixelBlue)
        .navigationTitle("Settings")
        .muffinOpaqueNavigationBar(MuffinTheme.formGround)
        .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(MuffinTheme.accentText)
            }
        }
    }

    /// Wide: the whole page, scrolled to the section picked. Narrow: a page is its list of sections,
    /// and a section picked from search opens on its own.
    @ViewBuilder private var detail: some View {
        let route = selection ?? .category(.general)
        if isCompact {
            if let item = route.item {
                sectionPage(item)
            } else {
                sectionList(route.category)
            }
        } else {
            // One view per page, so moving between sections of the same page scrolls instead of
            // rebuilding it.
            fullPage(route.category, focus: route.item)
                .id(route.category)
        }
    }

    @available(iOS 16.0, *)
    private var splitBody: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: One-column fallback (iOS 15)

    private var legacyBody: some View {
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
        }
        .navigationViewStyle(.stack)
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                splitBody
            } else {
                legacyBody
            }
        }
        // The rows that name games (Changed from default, "Set differently for 2 games") read the library here.
        .environment(\.settingsLibraryGames, gameManager.games)
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
}
