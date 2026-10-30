// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Combine
import SwiftUI

/// One setting as search and "Changed from default" see it: its name as its row shows it, the section
/// that holds it, extra words people search for, and, for a setting stored under one key, that key and
/// its default. Rows that act (Reset, Export) or keep their value elsewhere (theme, accounts) have no key:
/// they are found by search but never listed as changed.
struct SettingEntry: Identifiable, Hashable {
    let title: String
    let item: SettingsItem
    let keywords: String
    let key: String?
    /// The value the app uses when nothing is stored. Nil with a key means any stored value is a choice
    /// (Emulated clock). An enum default is compared by its raw value, the way @AppStorage stores it.
    let defaultValue: AnyHashable?

    var id: String { "\(item.rawValue)/\(title)" }

    static func == (lhs: SettingEntry, rhs: SettingEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Whether the stored value differs from the default.
    func isChanged(in defaults: UserDefaults = .standard) -> Bool {
        guard let key, let stored = defaults.object(forKey: key) else { return false }
        guard let defaultValue else { return true }
        return !(stored as AnyObject).isEqual(Self.plain(defaultValue.base))
    }

    private static func plain(_ value: Any) -> Any {
        if let raw = value as? any RawRepresentable { return raw.rawValue }
        return value
    }

    func matches(_ query: String) -> Bool {
        title.lowercased().contains(query) || title.localized.lowercased().contains(query) || keywords.contains(query)
    }
}

/// Every setting row, so search can find a setting by its own name and "Changed from default" can list
/// what differs. Grouped by section in page order. A row added to a section is added here too; titles
/// match the row's label.
@MainActor
enum SettingsIndex {
    private static func row(_ title: String, _ item: SettingsItem, _ keywords: String = "") -> SettingEntry {
        SettingEntry(title: title, item: item, keywords: keywords, key: nil, defaultValue: nil)
    }

    private static func stored(_ title: String, _ item: SettingsItem, _ key: String, _ defaultValue: AnyHashable?,
                               _ keywords: String = "") -> SettingEntry {
        SettingEntry(title: title, item: item, keywords: keywords, key: key, defaultValue: defaultValue)
    }

    static let entries: [SettingEntry] = general + emulation + controls + screenAndSound + library + accountOnline + housekeeping

    private static let general: [SettingEntry] = [
        stored("Language", .language, AppLanguage.storageKey, AppLanguage.system.rawValue, "translation"),
        row("Settings mode", .settingsMode, "basic advanced"),
        row("Theme", .appearance, "colours colors"),
        row("App Icon", .appearance, "icon pro"),
        row("Flat surfaces", .appearance, "glass flat"),
        row("Use Classic UI", .appearance, "classic old look"),
        row("Unlock", .premium, "buy purchase"),
        row("View on GitHub", .about, "source code issue bug"),
        row("Open-source licences", .about, "licenses legal"),
        row("Show welcome guide again", .about, "onboarding intro tutorial"),
        row("Reset settings to defaults", .about, "reset defaults"),
    ]

    private static let emulation: [SettingEntry] = [
        // The profile is stored as three switches; each is listed as changed under the profile it means.
        stored("Performance profile: Accuracy", .performance, "muffin.cpu.favourAccuracy", false, "favour accuracy glitch crash fix"),
        stored("Performance profile: Speed", .performance, FavourPerformance.storageKey, FavourPerformance.defaultValue, "favour performance fast"),
        stored("Performance profile: Battery saver", .performance, OneCoreMode.storageKey, OneCoreMode.defaultValue, "one-core mode single core low power heat"),
        stored("Steady frame rate", .performance, FullSpeedRenders.storageKey, FullSpeedRenders.defaultValue, "full speed stutter vsync"),
        stored("First time a new effect appears", .performance, FullSpeedRenders.shaderModeKey, FullSpeedRenders.defaultShaderMode.rawValue, "shader"),
        // Also listed under Display, where they are drawn too; Changed from default lists each key once.
        stored("Pause the TV screen when it isn't shown", .performance, HiddenScreenSettings.pauseHiddenTVKey, false, "battery heat hidden"),
        stored("Pause the GamePad screen when it isn't shown", .performance, HiddenScreenSettings.pauseHiddenPadKey, false, "battery heat hidden"),
        stored("Cool down automatically", .performance, ThermalMonitor.autoThrottleKey, ThermalMonitor.autoThrottleDefault, "heat thermal hot throttle"),
        stored("Cool down starts at", .performance, ThermalSettings.thresholdKey, ThermalSettings.defaultThreshold.rawValue, "heat thermal"),
        stored("Device heat", .performance, HeatDisplayMode.storageKey, HeatDisplayMode.word.rawValue, "temperature show as"),
        stored("CPU cores", .cpu, CoreMode.storageKey, CoreMode.defaultValue.rawValue, "multicore threads"),
        stored("Use the recompiler (JIT)", .jit, "muffin.cpu.recompiler", true, "interpreter"),
        stored("JIT enabler", .jit, JITEnabler.storageKey, JITEnabler.none.rawValue, "stikdebug stikjit"),
        stored("JIT enabler link", .jit, JITEnabler.customURLKey, "", "url custom"),
        row("Test it now", .jit, "test enabler"),
        stored("Renderer", .graphics, RendererAPI.storageKey, RendererAPI.defaultValue.rawValue, "metal vulkan"),
        stored("MoltenVK", .graphics, MoltenVKBuild.storageKey, MoltenVKBuild.defaultValue.rawValue, "vulkan"),
        stored("Resolution", .graphics, RenderScale.storageKey, RenderScale.deviceDefault.rawValue, "upscale render scale 1080p 720p"),
        stored("Filter when enlarging", .graphics, UpscaleFilterSetting.storageKey, UpscaleFilterSetting.defaultValue.rawValue, "upscale bilinear bicubic"),
        stored("Filter when shrinking", .graphics, DownscaleFilterSetting.storageKey, DownscaleFilterSetting.defaultValue.rawValue, "downscale"),
        stored("Display gamma", .graphics, DisplayGammaSetting.storageKey, DisplayGammaSetting.defaultValue, "dark bright"),
        stored("Fast blending", .graphics, "muffin.render.framebufferFetch", true, "framebuffer fetch"),
        stored("Emulate missing effects", .graphics, "muffin.render.emulateMissingEffects", false, "geometry shaders"),
        stored("Override the game's gamma", .graphics, "muffin.render.overrideAppGamma", false, "dark bright"),
        stored("Override gamma", .graphics, OverrideGammaSetting.storageKey, OverrideGammaSetting.defaultValue, "dark bright"),
        row("Graphic Packs", .graphics, "mods resolution fps patches"),
        stored("Compile shaders in the background", .shaderCache, "muffin.shaders.asyncCompile", true, "async stutter"),
        row("Clear compiled shaders", .shaderCache, "delete free space"),
        row("Clear everything, including learned", .shaderCache, "delete clear all"),
        stored("Speed", .emulatedClock, TimebaseScale.storageKey, nil, "clock timing"),
        stored("Console date and time", .consoleClock, ConsoleClock.offsetKey, nil, "date time day calendar clock"),
    ]

    private static let controls: [SettingEntry] = [
        stored("Control style", .onScreenControls, TouchLabSettings.schemeKey, TouchLabSettings.defaultScheme, "touchlab zone adaptive layout"),
        stored("Use Melo-Controller", .onScreenControls, MeloControlsSetting.storageKey, MeloControlsSetting.defaultValue, "melo"),
        stored("Add analog sticks", .onScreenControls, ControllerLayoutSettings.joystickKey, ControllerLayoutSettings.defaultJoystick, "joystick"),
        stored("Button size", .onScreenControls, ControllerLayoutSettings.scaleKey, ControllerLayoutSettings.defaultScale, "scale bigger smaller"),
        stored("Opacity", .onScreenControls, ControllerLayoutSettings.opacityKey, ControllerLayoutSettings.defaultOpacity, "transparent see-through"),
        stored("Haptic feedback", .onScreenControls, ControllerLayoutSettings.hapticsKey, ControllerLayoutSettings.defaultHaptics, "vibration buzz"),
        row("Shoulder button height", .onScreenControls, "l r zl zr triggers"),
        row("Calibrate sticks", .onScreenControls, "calibration reach"),
        row("Stick fine-tuning", .onScreenControls, "invert sensitivity tune each stick"),
        row("Reset stick calibration", .onScreenControls),
        stored("Stick follows thumb", .onScreenControls, TouchLabSettings.stickFollowKey, false),
        stored("Relative stick", .onScreenControls, TouchLabSettings.stickRelativeKey, false),
        stored("Comfort controls", .onScreenControls, ControllerLayoutSettings.comfortControlsKey, ControllerLayoutSettings.defaultComfortControls),
        stored("Stick spacing", .onScreenControls, ControllerLayoutSettings.stickSpacingKey, ControllerLayoutSettings.defaultStickSpacing, "hands"),
        stored("Stick gate", .onScreenControls, ControllerLayoutSettings.stickGateKey, ControllerLayoutSettings.defaultStickGateRaw, "octagon round"),
        stored("Stick deadzone", .onScreenControls, ControllerLayoutSettings.deadzoneKey, ControllerLayoutSettings.defaultDeadzone, "drift"),
        stored("Fine control", .onScreenControls, ControllerLayoutSettings.stickCurveKey, ControllerLayoutSettings.defaultStickCurve, "curve"),
        stored("Hide the top bar while playing", .onScreenControls, TopBarAutoHide.overrideKey, TopBarAutoHide.followDevice),
        stored("Top bar hides after", .onScreenControls, TopBarAutoHide.hideDelayKey, TopBarAutoHide.defaultHideDelaySeconds),
        stored("Reveal handle", .onScreenControls, TopBarAutoHide.handleSizeKey, TopBarAutoHide.defaultHandleSize.rawValue),
        stored("Pause while moving the controls", .onScreenControls, ControllerLayoutSettings.pauseWhileEditingKey, ControllerLayoutSettings.defaultPauseWhileEditing),
        stored("Hide the on-screen controls in the home menu", .onScreenControls, HiddenScreenSettings.hideControlsInHomeMenuKey, false),
        stored("Hide on-screen controls when a controller is connected", .onScreenControls, ControllerLayoutSettings.autoHideWithControllerKey, ControllerLayoutSettings.defaultAutoHideWithController, "gamepad paired"),
        stored("Use the new pad system", .onScreenControls, PreviewPadStore.enabledKey, PreviewPadStore.defaultEnabled, "preview"),
        row("Reset controls to default", .onScreenControls),
        row("Reset controller bindings", .onScreenControls, "buttons do nothing"),
        stored("Motion aiming", .motion, MotionSettings.enabledKey, MotionSettings.defaultEnabled),
        stored("Motion from", .motion, MotionSettings.sourceKey, MotionSettings.defaultSource),
        stored("Sensitivity", .motion, MotionSettings.sensitivityKey, MotionSettings.defaultSensitivity, "gyro"),
        stored("Reverse left and right", .motion, MotionSettings.invertHorizontalKey, false, "invert"),
        stored("Reverse up and down", .motion, MotionSettings.invertVerticalKey, false, "invert"),
        stored("Log motion values", .motion, MotionSettings.diagnosticKey, false),
        stored("Skylanders Portal", .emulatedDevices, EmulatedDevicesSettings.skylanderPortalKey, EmulatedDevicesSettings.defaultEnabled),
        stored("Disney Infinity Base", .emulatedDevices, EmulatedDevicesSettings.infinityBaseKey, EmulatedDevicesSettings.defaultEnabled),
        stored("LEGO Dimensions Toypad", .emulatedDevices, EmulatedDevicesSettings.dimensionsToypadKey, EmulatedDevicesSettings.defaultEnabled),
    ]

    private static let screenAndSound: [SettingEntry] = [
        stored("Screen Layout", .display, LocalScreenLayoutSettings.layoutKey, LocalScreenLayoutSettings.defaultLayout.rawValue, "single adaptive both"),
        stored("Show swap button", .display, LocalScreenLayoutSettings.showSwapButtonKey, LocalScreenLayoutSettings.defaultShowSwapButton),
        stored("Pause the TV screen when it isn't shown", .display, HiddenScreenSettings.pauseHiddenTVKey, false, "battery heat"),
        stored("Pause the GamePad screen when it isn't shown", .display, HiddenScreenSettings.pauseHiddenPadKey, false, "battery heat"),
        stored("Stretch picture to fill the screen", .display, FrameStretch.storageKey, FrameStretch.defaultValue, "aspect ratio"),
        stored("Flip screen upside down", .display, "muffin.render.upsideDown", false, "rotate"),
        stored("Allow portrait during games", .display, OrientationPolicy.allowPortraitKey, OrientationPolicy.defaultAllowPortrait, "upright rotate"),
        stored("Brightness boost", .display, BrightnessBoost.key, BrightnessBoost.defaultValue),
        stored("Max screen brightness while playing", .display, ScreenBrightness.maxWhilePlayingKey, ScreenBrightness.defaultMaxWhilePlaying),
        stored("Use an external display", .externalDisplay, ExternalDisplaySystemSettings.enabledKey, ExternalDisplaySystemSettings.defaultEnabled, "tv monitor"),
        stored("GamePad screen on the external display", .externalDisplay, DisplayLayoutSettings.swapKey, DisplayLayoutSettings.defaultSwap),
        stored("When a TV is connected, this device shows", .externalDisplay, DisplayLayoutSettings.deviceShowsKey, DisplayLayoutSettings.defaultDeviceShows),
        stored("Show swap button during play", .externalDisplay, DisplayLayoutSettings.showSwapButtonKey, DisplayLayoutSettings.defaultShowSwapButton),
        stored("TV audio", .audio, AudioSettings.tvEnabledKey, AudioSettings.defaultTvEnabled, "sound"),
        stored("TV volume", .audio, AudioSettings.tvVolumeKey, AudioSettings.defaultTvVolume, "sound loud quiet"),
        stored("TV channels", .audio, AudioSettings.tvChannelsKey, AudioSettings.defaultTvChannels, "stereo surround"),
        stored("GamePad audio", .audio, AudioSettings.padEnabledKey, AudioSettings.defaultPadEnabled, "sound"),
        stored("GamePad volume", .audio, AudioSettings.padVolumeKey, AudioSettings.defaultPadVolume, "sound loud quiet"),
        stored("GamePad channels", .audio, AudioSettings.padChannelsKey, AudioSettings.defaultPadChannels, "stereo"),
        stored("Use the microphone", .audio, AudioSettings.microphoneEnabledKey, AudioSettings.defaultMicrophoneEnabled, "mic blow"),
        stored("Microphone volume", .audio, AudioSettings.inputVolumeKey, AudioSettings.defaultInputVolume, "mic"),
        stored("Save all audio automatically", .audio, AudioRecorder.autoRecordKey, false, "record recording m4a"),
        stored("Overlay position", .overlay, OverlaySettings.positionKey, OverlaySettings.defaultPosition.rawValue, "corner on off"),
        stored("Overlay text colour", .overlay, OverlaySettings.textColorKey, OverlaySettings.defaultTextColor, "color"),
        stored("Overlay text size", .overlay, OverlaySettings.textScaleKey, OverlaySettings.defaultTextScale),
        stored("Show FPS", .overlay, OverlaySettings.fpsKey, OverlaySettings.defaultFps),
        stored("Show draw calls", .overlay, OverlaySettings.drawcallsKey, OverlaySettings.defaultDrawcalls),
        stored("Show CPU usage", .overlay, OverlaySettings.cpuUsageKey, OverlaySettings.defaultCpuUsage),
        stored("Show CPU usage per core", .overlay, OverlaySettings.cpuPerCoreUsageKey, OverlaySettings.defaultCpuPerCoreUsage),
        stored("Show RAM usage", .overlay, OverlaySettings.ramUsageKey, OverlaySettings.defaultRamUsage, "memory"),
        stored("Show VRAM usage", .overlay, OverlaySettings.vramUsageKey, OverlaySettings.defaultVramUsage, "memory"),
        stored("Show debug info", .overlay, OverlaySettings.debugKey, OverlaySettings.defaultDebug, "renderer"),
        stored("Notification position", .notifications, NotificationSettings.positionKey, NotificationSettings.defaultPosition.rawValue, "corner on off"),
        stored("Notification text colour", .notifications, NotificationSettings.textColorKey, NotificationSettings.defaultTextColor, "color"),
        stored("Notification text size", .notifications, NotificationSettings.textScaleKey, NotificationSettings.defaultTextScale),
        stored("Controller profiles", .notifications, NotificationSettings.controllerProfilesKey, NotificationSettings.defaultControllerProfiles),
        stored("Low controller battery", .notifications, NotificationSettings.controllerBatteryKey, NotificationSettings.defaultControllerBattery),
        stored("Shader compiling", .notifications, NotificationSettings.shaderCompilingKey, NotificationSettings.defaultShaderCompiling),
        stored("Friends", .notifications, NotificationSettings.friendsKey, NotificationSettings.defaultFriends),
    ]

    private static let library: [SettingEntry] = [
        row("Import keys.txt", .keys, "replace"),
        row("Remove keys.txt", .keys, "delete"),
        stored("Covers", .library, CoverStylePreference.storageKey, CoverStylePreference.defaultValue.rawValue, "flat 3d box"),
        stored("Show games as", .library, LibraryCardStyle.storageKey, LibraryCardStyle.defaultValue.rawValue, "grid list cards"),
        stored("Card size", .library, LibraryCardStyle.sizeStorageKey, 1.0, "bigger smaller"),
        stored("Tap a game to", .library, LibraryTapAction.storageKey, LibraryTapAction.defaultValue.rawValue, "open play"),
        stored("Sort by", .library, "muffin.library.sortOrder", LibrarySortOrder.title.rawValue, "order"),
        stored("Group by", .library, LibraryGrouping.storageKey, LibraryGrouping.defaultValue.rawValue),
        stored("Show", .library, LibraryFilter.storageKey, LibraryFilter.defaultValue.rawValue, "filter"),
        row("Link a folder", .library, "external drive usb"),
        row("Link a game file", .library, "external"),
        row("Check for packs", .coverArt, "art packs download"),
        row("Scrape now", .coverArt, "download game data gametdb"),
    ]

    private static let accountOnline: [SettingEntry] = [
        row("Active account", .account, "switch"),
        row("Create", .account, "new account add"),
        row("Custom servers", .network, "pretendo server"),
        stored("Show Wii U Menu as a game card", .wiiUMenu, WiiUMenuSettings.showAsCardKey, WiiUMenuSettings.defaultShowAsCard),
        stored("Hide the installed Wii U Menu", .wiiUMenu, WiiUMenuSettings.hideKey, WiiUMenuSettings.defaultHidden),
        row("Import Wii U Menu", .wiiUMenu, "system dump install"),
        row("Uninstall Wii U Menu", .wiiUMenu, "remove delete"),
    ]

    private static let housekeeping: [SettingEntry] = [
        row("Export all settings", .backup, "save file json"),
        row("Import settings", .backup, "restore load"),
        row("Export everything", .migration, "move transfer"),
        row("Include games (Roms folder)", .migration, "export"),
        row("Import from the old MuffinEMU", .migration, "restore"),
        row("Copy device report", .deviceReport, "bug report chip memory"),
        stored("Play the launch intro", .diagnostics, "muffin.showLaunchIntro", true, "animation"),
        stored("Show launch log", .diagnostics, LaunchLogSettings.showKey, false, "boot"),
        stored("Show controls diagnostic", .diagnostics, PadDiagnostics.enabledKey, PadDiagnostics.defaultEnabled, "input buttons"),
    ]

    /// Settings whose rows match a search, in page order.
    static func search(_ query: String, advanced: Bool) -> [SettingEntry] {
        entries.filter { (advanced || !$0.item.advancedOnly) && $0.matches(query) }
    }

    /// Settings stored away from their defaults right now, in page order. A setting drawn in two sections
    /// is listed once, under the first.
    static func changed(in defaults: UserDefaults = .standard) -> [SettingEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            guard entry.isChanged(in: defaults), let key = entry.key else { return false }
            return seen.insert(key).inserted
        }
    }
}

// MARK: Per-game links

/// A per-game override field, so a global row can say which games set it differently.
enum PerGameField: CaseIterable {
    case preCompileShaders, favourAccuracy, coreMode, renderScale, upscaleFilter, downscaleFilter
    case favourPerformance, fullSpeedRenders, fullSpeedShaderMode, oneCoreMode, screenLayout
    case autoHideControls, performanceOverlay
    /// Any of the three switches a performance profile sets (see PerformanceProfile).
    case performanceProfile

    func isSet(in overrides: GameOverrides) -> Bool {
        switch self {
        case .preCompileShaders: return overrides.preCompileShaders != nil
        case .favourAccuracy: return overrides.favourAccuracy != nil
        case .coreMode: return overrides.coreMode != nil
        case .renderScale: return overrides.renderScale != nil
        case .upscaleFilter: return overrides.upscaleFilter != nil
        case .downscaleFilter: return overrides.downscaleFilter != nil
        case .favourPerformance: return overrides.favourPerformance != nil
        case .fullSpeedRenders: return overrides.fullSpeedRenders != nil
        case .fullSpeedShaderMode: return overrides.fullSpeedShaderMode != nil
        case .oneCoreMode: return overrides.oneCoreMode != nil
        case .screenLayout: return overrides.screenLayout != nil
        case .autoHideControls: return overrides.autoHideControls != nil
        case .performanceOverlay: return overrides.performanceOverlay != nil
        case .performanceProfile:
            return overrides.favourAccuracy != nil || overrides.favourPerformance != nil || overrides.oneCoreMode != nil
        }
    }

    /// Matches GameOverrides.takeBasicFields: the rest are ignored while Settings mode is Basic (see
    /// activeOverrides).
    var isAdvanced: Bool {
        switch self {
        case .preCompileShaders, .favourAccuracy, .favourPerformance, .oneCoreMode, .performanceProfile,
             .renderScale, .screenLayout, .autoHideControls, .performanceOverlay:
            return false
        case .coreMode, .upscaleFilter, .downscaleFilter, .fullSpeedRenders, .fullSpeedShaderMode:
            return true
        }
    }
}

private struct SettingsLibraryGamesKey: EnvironmentKey {
    static let defaultValue: [GameMetadata] = []
}

extension EnvironmentValues {
    /// The library, for the rows in Settings that list games by name. Set by SettingsView; empty
    /// anywhere else, where those rows stay hidden.
    var settingsLibraryGames: [GameMetadata] {
        get { self[SettingsLibraryGamesKey.self] }
        set { self[SettingsLibraryGamesKey.self] = newValue }
    }
}

/// Under a global row that games can override: how many games set it differently, opening the list
/// of them and each one's Game settings. Nothing when no game does.
struct PerGameOverrideNote: View {
    let field: PerGameField
    @ObservedObject private var store = PerGameSettingsStore.shared
    @Environment(\.settingsLibraryGames) private var games
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var overriding: [GameMetadata] {
        guard !field.isAdvanced || SettingsMode.isAdvanced(raw: settingsModeRaw) else { return [] }
        return games.filter { field.isSet(in: store.overrides(for: $0.settingsKey)) }
    }

    var body: some View {
        let list = overriding
        if !list.isEmpty {
            NavigationLink {
                GamesWithOwnSettingsList(games: list, store: store)
            } label: {
                Label(list.count == 1 ? "Set differently for 1 game".localized : String(format: "Set differently for %d games".localized, list.count), systemImage: "gamecontroller")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.accentText)
            }
        }
    }
}

/// Games by name, each opening its Game settings.
struct GamesWithOwnSettingsList: View {
    let games: [GameMetadata]
    @ObservedObject var store: PerGameSettingsStore

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()
            Form {
                Section {
                    ForEach(games) { game in
                        NavigationLink {
                            GameOptionsView(game: game, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.cardName.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                let count = store.activeOverrides(for: game.settingsKey).customCount
                                Text(count == 1 ? "1 setting of its own".localized : String(format: "%d settings of its own".localized, count))
                                    .font(.system(size: 12))
                                    .foregroundColor(MuffinTheme.secondaryText)
                            }
                        }
                    }
                } footer: {
                    InfoButton.footer("Each of these games keeps its own value instead of following Settings. Open one to change it or reset it.".localized)
                }
            }
        }
        .navigationTitle("Games with their own settings")
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

// MARK: Changed from default

/// General > Changed from default: every setting not at its default, each opening its section, and
/// every game with settings of its own. The "where did I change that?" answer.
struct ChangedSettingsSection: View {
    /// Opens a section on its own screen; SettingsView owns the section views.
    let open: (SettingsItem) -> AnyView
    @ObservedObject private var store = PerGameSettingsStore.shared
    @Environment(\.settingsLibraryGames) private var games
    @State private var changed: [SettingEntry] = []

    private var gamesWithOwn: [GameMetadata] {
        games.filter { !store.activeOverrides(for: $0.settingsKey).isIdentity }
    }

    var body: some View {
        Section {
            if changed.isEmpty {
                Text("Everything is at its default.")
                    .font(.system(size: 13))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            ForEach(changed) { entry in
                NavigationLink {
                    open(entry.item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.title.localized)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(String(format: "%@ \u{203A} %@".localized, SettingsCategory.category(of: entry.item).title.localized, entry.item.title.localized))
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
            }
            let own = gamesWithOwn
            if !own.isEmpty {
                NavigationLink {
                    GamesWithOwnSettingsList(games: own, store: store)
                } label: {
                    Label(own.count == 1 ? "1 game has settings of its own".localized : String(format: "%d games have settings of their own".localized, own.count), systemImage: "gamecontroller")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
        } header: {
            SettingsSectionHeader("Changed from default".localized, icon: "slider.horizontal.3", accent: .system)
        } footer: {
            InfoButton.footer("Every setting you've changed, wherever it is. Tap one to go to it.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear { changed = SettingsIndex.changed() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            changed = SettingsIndex.changed()
        }
    }
}
