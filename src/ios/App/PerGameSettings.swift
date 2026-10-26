// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation
import SwiftUI
// For UTType.folder, which the import picker is restricted to.
import UniformTypeIdentifiers

/// Per-game overrides on top of the global defaults in Settings.
///
/// `nil` means "follow whatever the global setting currently says" - a real third state,
/// not the same as `false`. A game nobody has ever overridden should keep tracking the
/// global default as it changes, not freeze at whatever that default happened to be the
/// first time the game was seen.
struct GameOverrides: Codable, Equatable {
    /// Exists because Nano Assault Neo specifically breaks with background shader
    /// compilation on, while every other tested game is fine with it on. A single global
    /// toggle cannot be right for both at once, so this is the escape hatch: nil follows
    /// Settings' "Compile shaders in the background", true/false pin this one game.
    var preCompileShaders: Bool?

    /// Same escape hatch, for Settings' "Favour accuracy". Decodes to nil for overrides saved
    /// before this field existed (follow the global default).
    var favourAccuracy: Bool?

    /// CoreMode.rawValue ("auto", "single", "multi"), or nil to follow Settings > CPU. A string
    /// rather than the enum so an unknown value from a future version decodes instead of
    /// throwing away every override.
    var coreMode: String?

    // The options below are Advanced mode only (see AdvancedSettings and PerGameAdvancedSettings.swift).
    // Each nil follows the global setting. Raw values rather than enums, like coreMode.
    /// RenderScale.rawValue.
    var renderScale: String?
    /// ScaleFilter.rawValue, for the upscale and downscale filters.
    var upscaleFilter: Int?
    var downscaleFilter: Int?
    var favourPerformance: Bool?
    var fullSpeedRenders: Bool?
    /// FullSpeedRenders.ShaderMode.rawValue.
    var fullSpeedShaderMode: Int?
    var oneCoreMode: Bool?
    /// ScreenLayout.rawValue.
    var screenLayout: String?
    /// Hide the on-screen controls while a controller is connected.
    var autoHideControls: Bool?
    /// On shows the performance overlay, off hides it.
    var performanceOverlay: Bool?

    static let identity = GameOverrides()
    var isIdentity: Bool { self == GameOverrides.identity }
}

/// Where per-game overrides live, keyed by `GameMetadata.settingsKey` (the game's title ID, or its file-name id when no title ID
/// could be read).
///
/// One JSON blob rather than a key per game per setting - the same shape
/// `ControllerCustomLayout` already uses for per-element pad overrides - because the game
/// list is open-ended and `@AppStorage` needs a key known at compile time.
final class PerGameSettingsStore: ObservableObject {
    static let shared = PerGameSettingsStore()
    static let storageKey = "muffin.perGame.overrides"

    @Published private(set) var overridesByGame: [String: GameOverrides]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: GameOverrides].self, from: data) {
            overridesByGame = decoded
        } else {
            overridesByGame = [:]
        }
    }

    func overrides(for gameID: String) -> GameOverrides {
        overridesByGame[gameID] ?? .identity
    }

    /// What will actually reach the bridge for this game at launch: its own override if
    /// it has one, otherwise the global default read the same way GameManager already
    /// reads it (`UserDefaults` directly, since the engine cannot see `@AppStorage` and a
    /// value that only lived in a SwiftUI property wrapper would silently revert on every
    /// relaunch).
    func effectivePreCompileShaders(for gameID: String) -> Bool {
        overrides(for: gameID).preCompileShaders ?? globalPreCompileShaders
    }

    /// What Settings says right now, for the screens that show it beside a game's own choice.
    var globalPreCompileShaders: Bool {
        defaults.object(forKey: "muffin.shaders.asyncCompile") as? Bool ?? true
    }

    var globalFavourAccuracy: Bool {
        defaults.object(forKey: "muffin.cpu.favourAccuracy") as? Bool ?? false
    }

    func setPreCompileShaders(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.preCompileShaders = value
        write(next, for: gameID)
    }

    /// Per-game override first, global default underneath. Read before boot (see
    /// cemu_bridge_set_favour_accuracy's call site).
    func effectiveFavourAccuracy(for gameID: String) -> Bool {
        activeOverrides(for: gameID).favourAccuracy ?? globalFavourAccuracy
    }

    func setFavourAccuracy(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.favourAccuracy = value
        write(next, for: gameID)
    }

    /// Per-game core count first, Settings' choice underneath. Read before boot.
    func effectiveCoreMode(for gameID: String) -> CoreMode {
        if let raw = activeOverrides(for: gameID).coreMode, let mode = CoreMode(rawValue: raw) {
            return CoreMode.resolved(mode)
        }
        return CoreMode.current
    }

    func setCoreMode(_ value: CoreMode?, for gameID: String) {
        var next = overrides(for: gameID)
        next.coreMode = value?.rawValue
        write(next, for: gameID)
    }

    /// Moves overrides saved under the game's file-name id (before settings were keyed by title ID) to its title-ID key. An entry
    /// already under the title-ID key is never overwritten, and the old one is only removed once it has been moved.
    func adoptTitleIDKey(for game: GameMetadata) {
        let key = game.settingsKey
        guard key != game.id, let legacy = overridesByGame[game.id], overridesByGame[key] == nil else { return }
        overridesByGame[key] = legacy
        overridesByGame.removeValue(forKey: game.id)
        persist()
    }

    /// Replaces every game's overrides at once. Settings mode uses it to clear the Advanced options
    /// when switching to Basic and to put them back on Restore (see AdvancedSettings).
    func replaceOverrides(_ next: [String: GameOverrides]) {
        overridesByGame = next.filter { !$0.value.isIdentity }
        persist()
    }

    /// Writes one game's overrides. An empty set is removed, like every other write.
    func setOverrides(_ value: GameOverrides, for gameID: String) {
        write(value, for: gameID)
    }

    /// Puts one game back on the global settings.
    func clearOverrides(for gameID: String) {
        write(.identity, for: gameID)
    }

    /// Clears every per-game override at once - used by Settings > About > "Reset
    /// settings and every game's settings", the only path that touches this store from
    /// the global reset. Ordinary "Reset Settings" leaves it alone entirely.
    func removeAllOverrides() {
        overridesByGame = [:]
        persist()
    }

    private func write(_ value: GameOverrides, for gameID: String) {
        if value.isIdentity {
            overridesByGame.removeValue(forKey: gameID)
        } else {
            overridesByGame[gameID] = value
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(overridesByGame) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Carries everything a game's settings stored under its file name over to its title-ID key (GameMetadata.settingsKey): the
/// per-game overrides, Auto's memory of a bad three-core run, and the pad layouts. Run on every library scan. Each step only
/// acts on a game that still has something under the old name and nothing under the new key, so it is safe to repeat and a
/// game attached later (a disc image whose key arrived after the first scan) is picked up too. Nothing is deleted that was
/// not moved or copied first. Save states, covers, favourites and the library's own caches stay keyed by file name.
enum PerGameKeyMigration {
    @MainActor static func run(games: [GameMetadata]) {
        for game in games where game.titleId != nil && game.settingsKey != game.id {
            PerGameSettingsStore.shared.adoptTitleIDKey(for: game)
            AutoCoreHistory.adoptTitleIDKey(from: game.id, to: game.settingsKey)
            TouchLabSettings.adoptAdaptiveKey(from: game.id, to: game.settingsKey)
            MeloControlsSetting.adoptLayout(from: game.id, to: game.settingsKey)
        }
    }
}

/// The long-press menu on a game, and the "..." button on its card: just the quick actions.
/// Everything else (settings, save states, shader cache, DLC and updates) is on the game's page.
struct GameContextMenu: View {
    let game: GameMetadata
    @ObservedObject var gameManager: GameManager
    let onPlay: () -> Void
    let onOpenPage: () -> Void
    let onChangeCoverArt: () -> Void
    let onRename: () -> Void

    var body: some View {
        if let installLabel = game.installLabel {
            Text("\(game.cardName.name) \u{2022} \(installLabel)")
            Divider()
        }
        Button(action: onPlay) {
            Label("Play", systemImage: "play.fill")
        }
        Button(action: onOpenPage) {
            Label("Game page", systemImage: "info.circle")
        }
        Button {
            gameManager.toggleFavorite(game)
        } label: {
            Label(game.isFavorite ? "Unfavourite" : "Favourite",
                  systemImage: game.isFavorite ? "heart.slash" : "heart")
        }
        Button(action: onRename) {
            Label("Rename\u{2026}", systemImage: "pencil")
        }
        Button(action: onChangeCoverArt) {
            Label("Change cover\u{2026}", systemImage: "photo")
        }
    }
}


/// A per-game on/off choice. Following Settings is a real third state you can go back to, not
/// wherever a toggle happens to land.
enum OverrideChoice: Hashable {
    case followSettings, on, off

    /// The menu for an on/off row. The first option says what Settings has, so the row shows what
    /// applies without a caption under it.
    @ViewBuilder static func options(settingsHas value: Bool) -> some View {
        Text("Same as Settings (\(value ? "On" : "Off"))").tag(OverrideChoice.followSettings)
        Text("On").tag(OverrideChoice.on)
        Text("Off").tag(OverrideChoice.off)
    }
}

/// The label of a per-game menu's first option, naming what Settings has now.
func sameAsSettings(_ value: String) -> String { "Same as Settings (\(value))" }

/// One per-game choice: the setting's name, a dot while this game has its own value, its menu, and a
/// note under it only when there is something to warn about.
struct GameOverrideRow<Selection: Hashable, Options: View>: View {
    let title: String
    let isCustom: Bool
    let note: String?
    let selection: Binding<Selection>
    let options: Options

    init(_ title: String, isCustom: Bool, note: String? = nil, selection: Binding<Selection>,
         @ViewBuilder options: () -> Options) {
        self.title = title
        self.isCustom = isCustom
        self.note = note
        self.selection = selection
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(selection: selection) {
                options
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if isCustom {
                        Circle()
                            .fill(MuffinTheme.accentText)
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(isCustom ? "Set for this game" : "")
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.accentText)
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension GameOverrides {
    /// How many settings this game has its own value for, counted the way the screen shows them. A field
    /// added to GameOverrides goes in this list too.
    var customCount: Int {
        let fields: [Any?] = [preCompileShaders, coreMode, renderScale, upscaleFilter, downscaleFilter,
                              fullSpeedRenders, fullSpeedShaderMode, screenLayout, autoHideControls, performanceOverlay]
        // The three switches a performance profile sets are one row (see PerformanceProfile).
        let hasProfile = favourAccuracy != nil || favourPerformance != nil || oneCoreMode != nil
        return fields.filter { $0 != nil }.count + (hasProfile ? 1 : 0)
    }
}

/// A game's own settings, pushed from its Game page. The rows sit under the same page names, icons and
/// colours as Settings, so a choice is found in the same place in both. Each menu starts with what
/// Settings has; anything else sets it for this game only, and a dot marks the rows that are.
///
/// Only reachable from the library, so a game is never running while these change: every choice here is
/// read when the game next starts. Saves and shader cache imports are on the Game page itself.
struct GameOptionsView: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @State private var coreWarning: CoreMode?
    @State private var confirmReset = false

    private var key: String { game.settingsKey }
    private var own: GameOverrides { store.overrides(for: key) }
    private var isAdvanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    /// What a launch uses in the current Settings mode (see activeOverrides).
    private var active: GameOverrides { isAdvanced ? own : own.removingAdvancedFields() }

    /// "" is Same as Settings; otherwise CoreMode.rawValue. A value saved by a newer version reads as
    /// Same as Settings, which is what the launch does with it.
    private var coreModeChoice: Binding<String> {
        Binding(
            get: {
                guard let raw = own.coreMode, CoreMode(rawValue: raw) != nil else { return "" }
                return raw
            },
            set: {
                let mode = CoreMode(rawValue: $0)
                store.updateOverrides(for: key) { $0.coreMode = mode?.rawValue }
                if let mode, !mode.isAvailable { coreWarning = mode }
            })
    }

    private var profileIsCustom: Bool {
        own.favourAccuracy != nil || own.favourPerformance != nil || own.oneCoreMode != nil
    }

    /// This game's own profile, its values over Settings' for any switch it doesn't set. Nil while it
    /// follows Settings for all three.
    private var ownProfile: PerformanceProfile? {
        guard profileIsCustom else { return nil }
        return PerformanceProfile(accuracy: own.favourAccuracy ?? store.globalFavourAccuracy,
                                  performance: own.favourPerformance ?? store.globalFavourPerformance,
                                  oneCore: own.oneCoreMode ?? store.globalOneCoreMode)
    }

    private var profileNote: String? { ownProfile.map(\.summary) }

    /// "" follows Settings for all three switches; a profile sets all three for this game.
    private var profileChoice: Binding<String> {
        Binding(
            get: { ownProfile?.rawValue ?? "" },
            set: { raw in
                store.updateOverrides(for: key) { next in
                    if let switches = PerformanceProfile(rawValue: raw)?.switches {
                        next.favourAccuracy = switches.accuracy
                        next.favourPerformance = switches.performance
                        next.oneCoreMode = switches.oneCore
                    } else {
                        next.favourAccuracy = nil
                        next.favourPerformance = nil
                        next.oneCoreMode = nil
                    }
                }
            })
    }

    /// Only said when something else decides the core count, or the choice may not work here.
    private var coreModeNote: String? {
        let effective = store.effectiveCoreMode(for: key)
        if !effective.isAvailable { return "May not work on this device." }
        guard effective != .single else { return nil }
        if store.effectiveFavourAccuracy(for: key) {
            return "The Accuracy profile runs this game on one core whatever this says."
        }
        if store.effectiveOneCoreMode(for: key) {
            return "The Battery saver profile runs this game on one core whatever this says."
        }
        return nil
    }

    /// The same settings for every game, opened from here so changing what "Same as Settings" means
    /// doesn't mean leaving the game for Settings. These are Settings' own sections.
    private func allGamesLink<Sections: View>(@ViewBuilder _ sections: () -> Sections) -> some View {
        let content = sections()
        return NavigationLink {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()
                Form { content }
            }
            .navigationTitle("Settings for all games")
            .foregroundColor(MuffinTheme.brownDarkest)
        } label: {
            Label("Change for all games", systemImage: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(MuffinTheme.accentText)
        }
    }

    private func pageHeader(_ category: SettingsCategory) -> some View {
        SettingsSectionHeader(category.title, icon: category.icon, accent: category.accent)
    }

    // MARK: Sections

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.cardName.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(summaryLine)
                    .font(.system(size: 13))
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            if !active.isIdentity {
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    DestructiveSettingsLabel(title: "Reset this game's settings", systemImage: "arrow.uturn.backward")
                }
            }
        } footer: {
            InfoButton.footer(
                "Changes apply the next time you start the game.",
                title: "Game settings",
                text: "Every menu here starts with \"Same as Settings\", which follows the matching setting in Settings, even if you change it later. Picking anything else sets it for this game only and puts a dot beside it.\n\nScreen layout and Hide on-screen controls when a controller is connected are put in place when the game starts, and your own choices come back when it stops. A layout change you make during the game is not kept.\n\nPerformance overlay On uses the corner chosen in Settings, or the top left if Settings has it off.\n\nChanges apply the next time you start the game.")
        }
    }

    private var summaryLine: String {
        let count = active.customCount
        if count == 0 { return "Follows Settings for everything. Pick a value below to set it for this game only." }
        return "\(count) setting\(count == 1 ? "" : "s") set for this game only, marked with a dot. Everything else follows Settings."
    }

    private var performanceSection: some View {
        Section {
            GameOverrideRow("Compile shaders in the background", isCustom: own.preCompileShaders != nil,
                            selection: store.onOffChoice(\.preCompileShaders, for: key)) {
                OverrideChoice.options(settingsHas: store.globalPreCompileShaders)
            }
            GameOverrideRow("Performance profile", isCustom: profileIsCustom, note: profileNote, selection: profileChoice) {
                Text(sameAsSettings(PerformanceProfile.current.title)).tag("")
                ForEach(PerformanceProfile.choices(including: ownProfile ?? .balanced)) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            }
            resolutionRow
            // The rest are Advanced mode only, like their rows in Settings.
            if isAdvanced {
                GameOverrideRow("CPU cores", isCustom: own.coreMode != nil, note: coreModeNote, selection: coreModeChoice) {
                    Text(sameAsSettings(CoreMode.current.title)).tag("")
                    ForEach(CoreMode.listed) { mode in
                        Text(mode.isAvailable ? mode.title : mode.title + ", may not work").tag(mode.rawValue)
                    }
                }
                graphicsRows
            }
            allGamesLink {
                PerformanceSettingsSection()
                ShaderCacheSection()
                CPUSettingsSection()
                GraphicsSettingsSection()
            }
        } header: {
            pageHeader(.emulation)
        } footer: {
            if isAdvanced {
                InfoButton.footer(
                    "How fast this game runs and how it looks.",
                    title: "Performance and graphics",
                    text: "Compile shaders in the background builds shaders while the game keeps running. Most games want this on; Nano Assault Neo breaks with it.\n\nPerformance profile picks the trade-off for this game: Speed, Accuracy (slower but more accurate, on one CPU core; can fix a game that glitches or crashes) or Battery saver (one CPU core).\n\nResolution and the two scaling filters change how the picture is drawn for this game.\n\nCPU cores picks how many cores run the game. Auto decides for each game and device.")
            } else {
                InfoButton.footer(
                    "CPU cores, the scaling filters and Steady frame rate can be set per game too when Settings mode is Advanced (Settings > General).",
                    title: "Performance and graphics",
                    text: "Compile shaders in the background builds shaders while the game keeps running. Most games want this on; Nano Assault Neo breaks with it, so it can be set per game.\n\nPerformance profile picks the trade-off for this game: Speed, Accuracy (slower but more accurate, on one CPU core; can fix a game that glitches or crashes) or Battery saver (one CPU core).\n\nResolution changes how large the picture is drawn for this game.\n\nSwitch Settings mode to Advanced on Settings > General to set CPU cores, the scaling filters and Steady frame rate for this game too.")
            }
        }
    }

    private var resolutionRow: some View {
        GameOverrideRow("Resolution", isCustom: own.renderScale != nil,
                        selection: store.textChoice(\.renderScale, known: RenderScale.allCases.map(\.rawValue), for: key)) {
            Text(sameAsSettings(RenderScale.storedChoice.title)).tag("")
            ForEach(RenderScale.allCases) { scale in
                Text(scale.title).tag(scale.rawValue)
            }
        }
    }

    @ViewBuilder private var graphicsRows: some View {
        GameOverrideRow("Filter when enlarging", isCustom: own.upscaleFilter != nil,
                        selection: store.numberChoice(\.upscaleFilter, known: ScaleFilter.allCases.map(\.rawValue), for: key)) {
            Text(sameAsSettings(store.globalUpscaleFilter.title)).tag(-1)
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        GameOverrideRow("Filter when shrinking", isCustom: own.downscaleFilter != nil,
                        note: favourPerformanceNote,
                        selection: store.numberChoice(\.downscaleFilter, known: ScaleFilter.allCases.map(\.rawValue), for: key)) {
            Text(sameAsSettings(store.globalDownscaleFilter.title)).tag(-1)
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        GameOverrideRow("Steady frame rate", isCustom: own.fullSpeedRenders != nil,
                        selection: store.onOffChoice(\.fullSpeedRenders, for: key)) {
            OverrideChoice.options(settingsHas: store.globalFullSpeedRenders)
        }
        if own.fullSpeedRenders ?? store.globalFullSpeedRenders {
            GameOverrideRow("First time a new effect appears", isCustom: own.fullSpeedShaderMode != nil,
                            selection: store.numberChoice(\.fullSpeedShaderMode,
                                                          known: FullSpeedRenders.ShaderMode.allCases.map(\.rawValue), for: key)) {
                Text(sameAsSettings(store.globalFullSpeedShaderMode.title)).tag(-1)
                ForEach(FullSpeedRenders.ShaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        }
    }

    /// The same note Settings > Graphics shows: with Favour performance on (and accuracy off), the filters
    /// above are overridden at launch (filtersToPush).
    private var favourPerformanceNote: String? {
        store.effectiveFavourPerformance(for: key) && !store.effectiveFavourAccuracy(for: key)
            ? "The Speed profile is on for this game, so the picture is drawn at Balanced at most, with linear scaling."
            : nil
    }

    private var screenSection: some View {
        Section {
            GameOverrideRow("Screen layout", isCustom: own.screenLayout != nil,
                            selection: store.textChoice(\.screenLayout, known: ScreenLayout.allCases.map(\.rawValue), for: key)) {
                Text(sameAsSettings(store.globalScreenLayout.string)).tag("")
                ForEach(ScreenLayout.allCases) { layout in
                    Text(layout.string).tag(layout.rawValue)
                }
            }
            GameOverrideRow("Performance overlay", isCustom: own.performanceOverlay != nil,
                            selection: store.onOffChoice(\.performanceOverlay, for: key)) {
                OverrideChoice.options(settingsHas: store.globalOverlayPosition != .disabled)
            }
            allGamesLink {
                DisplaySettingsSection()
                OverlaySettingsSection()
            }
        } header: {
            pageHeader(.screenAndSound)
        }
    }

    private var controlsSection: some View {
        Section {
            GameOverrideRow("Hide on-screen controls when a controller is connected", isCustom: own.autoHideControls != nil,
                            selection: store.onOffChoice(\.autoHideControls, for: key)) {
                OverrideChoice.options(settingsHas: store.globalAutoHideControls)
            }
            allGamesLink {
                OnScreenControlsSection()
            }
        } header: {
            pageHeader(.controls)
        }
    }

    private var graphicPacksSection: some View {
        Section {
            NavigationLink {
                GraphicPacksView(game: game)
            } label: {
                Label("Graphic Packs", systemImage: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Graphic packs", icon: "paintpalette", accent: .core)
        } footer: {
            InfoButton.footer(
                "Resolution, frame rate, fixes and mods for this game. They apply the next time you start it.",
                title: "Graphic packs",
                text: "Graphic packs change how a game looks or plays: higher resolutions, frame-rate patches, fixes for known glitches and mods. Download the community packs, turn on the ones you want for this game, and pick their options. Nothing is turned on automatically.\n\nHigher resolutions cost speed and memory, and what is reasonable depends on the device, so the options show a suggestion for this one.\n\nPacks listed under All games apply to every game, not just this one. Packs apply the next time you start the game."
            )
        }
    }

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient
                .ignoresSafeArea()

            Form {
                summarySection
                performanceSection
                screenSection
                controlsSection
                graphicPacksSection
            }
        }
        .confirmationDialog("Reset this game's settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.clearOverrides(for: key) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(game.cardName.name) goes back to following Settings for everything.")
        }
        .alert("May not work on this device", isPresented: Binding(
            get: { coreWarning != nil },
            set: { if !$0 { coreWarning = nil } }
        ), presenting: coreWarning) { _ in
            Button("OK", role: .cancel) { }
        } message: { mode in
            Text(mode.limitWarning)
        }
        .navigationTitle("Game settings")
        .muffinOpaqueNavigationBar(MuffinTheme.formGround)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
