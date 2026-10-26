// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// Settings > Settings mode. Basic hides the advanced settings and keeps them at their defaults;
/// Advanced shows everything. Stored under a "muffin." key so "Reset settings to defaults" puts it
/// back to Basic along with everything else.
enum SettingsMode: String, CaseIterable, Identifiable {
    case basic
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic:    return "Basic"
        case .advanced: return "Advanced"
        }
    }

    static let storageKey = "muffin.settings.mode"
    static let defaultValue: SettingsMode = .basic

    static var current: SettingsMode {
        SettingsMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? defaultValue
    }

    /// Plain UserDefaults read, so it is safe from the launch task and the title-switch thread.
    static var isAdvanced: Bool { current == .advanced }

    /// For a view holding the stored raw value in an @AppStorage.
    static func isAdvanced(raw: String) -> Bool { raw == SettingsMode.advanced.rawValue }

    /// Once, on the first launch after updating from a version without Settings mode: someone who
    /// already changed an advanced setting (a game's own Favour accuracy or CPU cores, say, set so it
    /// would boot) starts in Advanced, so nothing they set is switched off or hidden by the update.
    /// Everyone else, and every new install, starts in Basic. Main thread, at launch.
    static func chooseInitialModeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: storageKey) == nil else { return }
        defaults.set((AdvancedSettings.hasCustomisedValues ? SettingsMode.advanced : .basic).rawValue, forKey: storageKey)
    }
}

/// One advanced setting: its UserDefaults key and the value the app uses when the key is absent.
/// A nil default means "no stored value is the default" (Emulated Clock, where any stored value
/// is an explicit choice).
struct AdvancedSetting {
    let key: String
    let defaultValue: Any?

    init(_ key: String, _ defaultValue: Any?) {
        self.key = key
        self.defaultValue = defaultValue
    }

    /// Absent counts as default, since every reader falls back to its own default for a missing key.
    func isAtDefault(in defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: key) else { return true }
        guard let defaultValue else { return false }
        return (stored as AnyObject).isEqual(defaultValue)
    }
}

/// Settings that belong together and share one way of telling the engine about a change.
struct AdvancedGroup {
    let name: String
    let settings: [AdvancedSetting]
    /// Pushes the stored values to the bridge, for settings the engine holds a copy of. Read from
    /// UserDefaults at call time, so it serves both "back to defaults" and "restored".
    let applyToBridge: (() -> Void)?
}

/// The registry of advanced settings. A new advanced setting is added to `groups` below, once:
/// that is what Basic resets, what the snapshot saves and Restore brings back, and what Settings >
/// Reset clears. The rows themselves are hidden in Basic by the section that draws them
/// (`SettingsMode.isAdvanced`), and per-game options register through `GameOverrides`
/// (see `advancedFields` at the bottom).
///
/// Switching to Basic saves the current advanced values (a snapshot in UserDefaults), then sets
/// every one back to its default: they are paused, not lost. Switching back to Advanced brings the
/// snapshot back on its own.
enum AdvancedSettings {
    /// What the app keeps while Basic is on, so Restore has something to bring back. The "muffin."
    /// prefix means a settings reset removes both.
    private static let snapshotKey = "muffin.settings.advancedSnapshot"
    private static let perGameSnapshotKey = "muffin.settings.advancedSnapshot.perGame"

    // The performance profile's three switches are Basic (see formerlyAdvanced); the bridge push below
    // still sends them, so a restore leaves the engine agreeing with Settings.
    private static let cpuAndPerformance = AdvancedGroup(name: "CPU and performance", settings: [
        AdvancedSetting(CoreMode.storageKey, CoreMode.defaultValue.rawValue),
        AdvancedSetting(ThermalSettings.thresholdKey, ThermalSettings.defaultThreshold.rawValue),
        // The switch CPU cores replaced. CoreMode.current falls back to it when the new key is absent.
        AdvancedSetting("muffin.cpu.multicore", nil),
    ]) {
        let defaults = UserDefaults.standard
        cemu_bridge_set_favour_accuracy(defaults.object(forKey: "muffin.cpu.favourAccuracy") as? Bool ?? false)
        cemu_bridge_set_favour_performance(FavourPerformance.isEnabled)
        cemu_bridge_set_low_power_mode(OneCoreMode.isEnabled)
        cemu_bridge_set_cpu_core_mode(CoreMode.current.bridgeValue)
    }

    private static let fullSpeedRenders = AdvancedGroup(name: "Steady frame rate", settings: [
        AdvancedSetting(FullSpeedRenders.storageKey, FullSpeedRenders.defaultValue),
        AdvancedSetting(FullSpeedRenders.shaderModeKey, FullSpeedRenders.defaultShaderMode.rawValue),
    ]) {
        FullSpeedRenders.applyToBridge()
    }

    // The bridge reads these at launch, so there is nothing to push.
    private static let rendererAndFilters = AdvancedGroup(name: "Renderer and filters", settings: [
        AdvancedSetting(RendererAPI.storageKey, RendererAPI.defaultValue.rawValue),
        AdvancedSetting(MoltenVKBuild.storageKey, MoltenVKBuild.defaultValue.rawValue),
        AdvancedSetting(UpscaleFilterSetting.storageKey, UpscaleFilterSetting.defaultValue.rawValue),
        AdvancedSetting(DownscaleFilterSetting.storageKey, DownscaleFilterSetting.defaultValue.rawValue),
    ], applyToBridge: nil)

    private static let picture = AdvancedGroup(name: "Picture", settings: [
        AdvancedSetting("muffin.render.upsideDown", false),
        AdvancedSetting("muffin.render.framebufferFetch", true),
        AdvancedSetting("muffin.render.emulateMissingEffects", false),
        AdvancedSetting(DisplayGammaSetting.storageKey, DisplayGammaSetting.defaultValue),
        AdvancedSetting("muffin.render.overrideAppGamma", false),
        AdvancedSetting(OverrideGammaSetting.storageKey, OverrideGammaSetting.defaultValue),
    ]) {
        let defaults = UserDefaults.standard
        cemu_bridge_set_render_upside_down(defaults.object(forKey: "muffin.render.upsideDown") as? Bool ?? false)
        cemu_bridge_set_framebuffer_fetch(defaults.object(forKey: "muffin.render.framebufferFetch") as? Bool ?? true)
        cemu_bridge_set_emulate_missing_effects(defaults.object(forKey: "muffin.render.emulateMissingEffects") as? Bool ?? false)
        cemu_bridge_set_display_gamma(Float(
            defaults.object(forKey: DisplayGammaSetting.storageKey) as? Double ?? DisplayGammaSetting.defaultValue))
        cemu_bridge_set_override_app_gamma(defaults.object(forKey: "muffin.render.overrideAppGamma") as? Bool ?? false)
        cemu_bridge_set_override_gamma_value(Float(
            defaults.object(forKey: OverrideGammaSetting.storageKey) as? Double ?? OverrideGammaSetting.defaultValue))
    }

    private static let emulatedClock = AdvancedGroup(name: "Emulated clock", settings: [
        AdvancedSetting(TimebaseScale.storageKey, nil),
    ]) {
        // A stored choice is applied; otherwise the engine goes back to its automatic ladder.
        if TimebaseScale.hasExplicitChoice {
            TimebaseScale.applyStoredChoiceIfAny()
        } else {
            TimebaseScale.clearChoice()
        }
    }

    // Position and Show FPS stay in Basic: they are the overlay's on/off.
    private static let overlayDetails = AdvancedGroup(name: "Overlay details", settings: [
        AdvancedSetting(OverlaySettings.textColorKey, OverlaySettings.defaultTextColor),
        AdvancedSetting(OverlaySettings.textScaleKey, OverlaySettings.defaultTextScale),
        AdvancedSetting(OverlaySettings.drawcallsKey, OverlaySettings.defaultDrawcalls),
        AdvancedSetting(OverlaySettings.cpuUsageKey, OverlaySettings.defaultCpuUsage),
        AdvancedSetting(OverlaySettings.cpuPerCoreUsageKey, OverlaySettings.defaultCpuPerCoreUsage),
        AdvancedSetting(OverlaySettings.ramUsageKey, OverlaySettings.defaultRamUsage),
        AdvancedSetting(OverlaySettings.vramUsageKey, OverlaySettings.defaultVramUsage),
        AdvancedSetting(OverlaySettings.debugKey, OverlaySettings.defaultDebug),
    ]) {
        let defaults = UserDefaults.standard
        cemu_bridge_set_overlay_text_color(UInt32(truncatingIfNeeded:
            defaults.object(forKey: OverlaySettings.textColorKey) as? Int ?? OverlaySettings.defaultTextColor))
        cemu_bridge_set_overlay_text_scale(Int32(clamping:
            defaults.object(forKey: OverlaySettings.textScaleKey) as? Int ?? OverlaySettings.defaultTextScale))
        cemu_bridge_set_overlay_drawcalls(
            defaults.object(forKey: OverlaySettings.drawcallsKey) as? Bool ?? OverlaySettings.defaultDrawcalls)
        cemu_bridge_set_overlay_cpu_usage(
            defaults.object(forKey: OverlaySettings.cpuUsageKey) as? Bool ?? OverlaySettings.defaultCpuUsage)
        cemu_bridge_set_overlay_cpu_per_core_usage(
            defaults.object(forKey: OverlaySettings.cpuPerCoreUsageKey) as? Bool ?? OverlaySettings.defaultCpuPerCoreUsage)
        cemu_bridge_set_overlay_ram_usage(
            defaults.object(forKey: OverlaySettings.ramUsageKey) as? Bool ?? OverlaySettings.defaultRamUsage)
        cemu_bridge_set_overlay_vram_usage(
            defaults.object(forKey: OverlaySettings.vramUsageKey) as? Bool ?? OverlaySettings.defaultVramUsage)
        cemu_bridge_set_overlay_debug(
            defaults.object(forKey: OverlaySettings.debugKey) as? Bool ?? OverlaySettings.defaultDebug)
    }

    private static let notificationLooks = AdvancedGroup(name: "Notification looks", settings: [
        AdvancedSetting(NotificationSettings.textColorKey, NotificationSettings.defaultTextColor),
        AdvancedSetting(NotificationSettings.textScaleKey, NotificationSettings.defaultTextScale),
    ]) {
        let defaults = UserDefaults.standard
        cemu_bridge_set_notification_text_color(UInt32(truncatingIfNeeded:
            defaults.object(forKey: NotificationSettings.textColorKey) as? Int ?? NotificationSettings.defaultTextColor))
        cemu_bridge_set_notification_text_scale(Int32(clamping:
            defaults.object(forKey: NotificationSettings.textScaleKey) as? Int ?? NotificationSettings.defaultTextScale))
    }

    private static let audioChannels = AdvancedGroup(name: "Audio channels", settings: [
        AdvancedSetting(AudioSettings.tvChannelsKey, AudioSettings.defaultTvChannels),
        AdvancedSetting(AudioSettings.padChannelsKey, AudioSettings.defaultPadChannels),
    ]) {
        let defaults = UserDefaults.standard
        cemu_bridge_set_tv_channels(Int32(clamping:
            defaults.object(forKey: AudioSettings.tvChannelsKey) as? Int ?? AudioSettings.defaultTvChannels))
        cemu_bridge_set_pad_channels(Int32(clamping:
            defaults.object(forKey: AudioSettings.padChannelsKey) as? Int ?? AudioSettings.defaultPadChannels))
    }

    // Motion on/off, where it comes from, sensitivity, the reverse switches and Recentre are Basic.
    private static let motionTuning = AdvancedGroup(name: "Motion log", settings: [
        AdvancedSetting(MotionSettings.diagnosticKey, false),
    ]) {
        MotionSettings.applyToBridge()
    }

    // The pad reads these through @AppStorage, so removing them is enough.
    private static let stickFeel = AdvancedGroup(name: "Stick feel", settings: [
        AdvancedSetting(ControllerLayoutSettings.stickGateKey, ControllerLayoutSettings.defaultStickGateRaw),
        AdvancedSetting(ControllerLayoutSettings.deadzoneKey, ControllerLayoutSettings.defaultDeadzone),
        AdvancedSetting(ControllerLayoutSettings.stickCurveKey, ControllerLayoutSettings.defaultStickCurve),
    ] + perStickSettings, applyToBridge: nil)

    // Each stick's own fine-tuning. A stick's deadzone and curve have no default of their own: absent
    // means "use the shared one above".
    private static let perStickSettings: [AdvancedSetting] = [true, false].flatMap { left in
        SharedStick.Setting.allCases.map { setting -> AdvancedSetting in
            switch setting {
            case .innerDeadzone, .curve: return AdvancedSetting(SharedStick.key(setting, left: left), nil)
            case .outerDeadzone, .antiDeadzone: return AdvancedSetting(SharedStick.key(setting, left: left), 0.0)
            case .sensitivityX, .sensitivityY: return AdvancedSetting(SharedStick.key(setting, left: left), 1.0)
            case .invertX, .invertY: return AdvancedSetting(SharedStick.key(setting, left: left), false)
            }
        }
    }

    private static let topBar = AdvancedGroup(name: "Top bar", settings: [
        AdvancedSetting(TopBarAutoHide.hideDelayKey, TopBarAutoHide.defaultHideDelaySeconds),
        AdvancedSetting(TopBarAutoHide.handleSizeKey, TopBarAutoHide.defaultHandleSize.rawValue),
    ], applyToBridge: nil)

    private static let diagnostics = AdvancedGroup(name: "Diagnostics", settings: [
        AdvancedSetting(LaunchLogSettings.showKey, false),
        AdvancedSetting(PadDiagnostics.enabledKey, PadDiagnostics.defaultEnabled),
    ], applyToBridge: nil)

    static let groups: [AdvancedGroup] = [
        cpuAndPerformance,
        fullSpeedRenders,
        rendererAndFilters,
        picture,
        emulatedClock,
        overlayDetails,
        notificationLooks,
        audioChannels,
        motionTuning,
        stickFeel,
        topBar,
        diagnostics,
    ]

    /// Settings that were Advanced in an earlier version and are Basic now. Someone who was in Basic
    /// when they changed has them in the snapshot; releaseFormerlyAdvanced hands them back.
    private static let formerlyAdvanced: [String] = [
        "muffin.cpu.favourAccuracy", FavourPerformance.storageKey, OneCoreMode.storageKey,
        MotionSettings.sourceKey, MotionSettings.sensitivityKey,
        MotionSettings.invertHorizontalKey, MotionSettings.invertVerticalKey,
        LibraryGrouping.storageKey, LibraryFilter.storageKey,
    ]

    /// At launch: values Basic set aside for settings that are Basic now go back to work, in the app and
    /// in each game's own options, unless they've been set again since. They leave the snapshot, so this
    /// does nothing the second time.
    static func releaseFormerlyAdvanced() {
        let defaults = UserDefaults.standard
        if var values = defaults.dictionary(forKey: snapshotKey) {
            for key in formerlyAdvanced {
                guard let saved = values.removeValue(forKey: key) else { continue }
                if defaults.object(forKey: key) == nil { defaults.set(saved, forKey: key) }
            }
            if values.isEmpty { defaults.removeObject(forKey: snapshotKey) } else { defaults.set(values, forKey: snapshotKey) }
        }
        guard let data = defaults.data(forKey: perGameSnapshotKey),
              let saved = try? JSONDecoder().decode([String: GameOverrides].self, from: data) else { return }
        let perGame = PerGameSettingsStore.shared
        var live = perGame.overridesByGame
        for (game, snapshot) in saved {
            live[game] = (live[game] ?? .identity).filling(basicFieldsFrom: snapshot)
        }
        perGame.replaceOverrides(live)
        let rest = saved.mapValues { $0.advancedFields }.filter { !$0.value.isIdentity }
        if rest.isEmpty {
            defaults.removeObject(forKey: perGameSnapshotKey)
        } else if let encoded = try? JSONEncoder().encode(rest) {
            defaults.set(encoded, forKey: perGameSnapshotKey)
        }
    }

    static var allSettings: [AdvancedSetting] { groups.flatMap { $0.settings } }

    /// Whether anything advanced is away from its default, in the app or in a game's own options.
    static var hasCustomisedValues: Bool {
        allSettings.contains { !$0.isAtDefault() }
            || PerGameSettingsStore.shared.overridesByGame.values.contains { !$0.advancedFields.isIdentity }
    }

    /// Whether Basic is holding saved advanced values for the next switch to Advanced.
    static var hasSnapshot: Bool {
        let defaults = UserDefaults.standard
        let values = defaults.dictionary(forKey: snapshotKey) ?? [:]
        return !values.isEmpty || defaults.data(forKey: perGameSnapshotKey) != nil
    }

    /// Basic: saves the current advanced values (only when some differ from the defaults, so a
    /// snapshot Basic made earlier isn't overwritten by an all-default one), then puts every
    /// advanced setting back to its default and tells the engine.
    static func switchToBasic() {
        let defaults = UserDefaults.standard
        let perGame = PerGameSettingsStore.shared
        if hasCustomisedValues {
            var values: [String: Any] = [:]
            for setting in allSettings {
                if let stored = defaults.object(forKey: setting.key) { values[setting.key] = stored }
            }
            defaults.set(values, forKey: snapshotKey)
            let advancedPerGame = perGame.overridesByGame
                .mapValues { $0.advancedFields }
                .filter { !$0.value.isIdentity }
            if advancedPerGame.isEmpty {
                defaults.removeObject(forKey: perGameSnapshotKey)
            } else if let data = try? JSONEncoder().encode(advancedPerGame) {
                defaults.set(data, forKey: perGameSnapshotKey)
            }
        }
        clearAdvanced()
        NotificationCenter.default.post(name: .muffinSettingsWereReset, object: nil)
    }

    /// Every advanced setting back to its default, in the app and in each game's own options, pushed to the
    /// engine. What Basic means; a settings import into Basic uses it too.
    static func clearAdvanced() {
        let defaults = UserDefaults.standard
        let perGame = PerGameSettingsStore.shared
        for setting in allSettings { defaults.removeObject(forKey: setting.key) }
        perGame.replaceOverrides(perGame.overridesByGame.mapValues { $0.removingAdvancedFields() })
        applyToBridge()
    }

    /// Brings the saved values back and pushes them to the engine.
    static func restoreSnapshot() {
        let defaults = UserDefaults.standard
        let values = defaults.dictionary(forKey: snapshotKey) ?? [:]
        let known = Set(allSettings.map { $0.key })
        for (key, value) in values where known.contains(key) {
            defaults.set(value, forKey: key)
        }
        if let data = defaults.data(forKey: perGameSnapshotKey),
           let saved = try? JSONDecoder().decode([String: GameOverrides].self, from: data) {
            let perGame = PerGameSettingsStore.shared
            var next = perGame.overridesByGame
            for (game, advanced) in saved {
                next[game] = (next[game] ?? .identity).adopting(advancedFieldsOf: advanced)
            }
            perGame.replaceOverrides(next)
        }
        discardSnapshot()
        applyToBridge()
        NotificationCenter.default.post(name: .muffinSettingsWereReset, object: nil)
    }

    /// Forgets what Basic saved (a settings import replaces it).
    static func discardSnapshot() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: perGameSnapshotKey)
    }

    /// Settings > Reset: back to Basic, snapshot gone. The generic "muffin." sweep would remove
    /// these keys too; this keeps the rule in one place next to the registry.
    static func resetModeAndSnapshot() {
        discardSnapshot()
        UserDefaults.standard.removeObject(forKey: SettingsMode.storageKey)
    }

    /// How many advanced settings Basic is holding away from their defaults, in the app and in each
    /// game's own options: what Settings mode says is paused.
    static var pausedCount: Int {
        let defaults = UserDefaults.standard
        let values = defaults.dictionary(forKey: snapshotKey) ?? [:]
        let app = allSettings.filter { setting in
            guard let saved = values[setting.key] else { return false }
            guard let defaultValue = setting.defaultValue else { return true }
            return !(saved as AnyObject).isEqual(defaultValue)
        }.count
        var games = 0
        if let data = defaults.data(forKey: perGameSnapshotKey),
           let saved = try? JSONDecoder().decode([String: GameOverrides].self, from: data) {
            games = saved.values.reduce(0) { $0 + $1.advancedFields.customCount }
        }
        return app + games
    }

    /// Tells the engine every advanced setting's current stored value.
    static func applyToBridge() {
        for group in groups { group.applyToBridge?() }
    }
}

/// Per-game options and Settings mode. Basic keeps the per-game rows whose Settings row is Basic too:
/// Compile shaders in the background, the performance profile, Resolution, Screen layout, the
/// performance overlay and hiding the controls with a controller. Everything else in GameOverrides is
/// Advanced, so a field added to GameOverrides is Advanced unless it is added to takeBasicFields.
extension GameOverrides {
    /// Copies the options Basic keeps from `source`.
    private mutating func takeBasicFields(from source: GameOverrides) {
        preCompileShaders = source.preCompileShaders
        favourAccuracy = source.favourAccuracy
        favourPerformance = source.favourPerformance
        oneCoreMode = source.oneCoreMode
        renderScale = source.renderScale
        screenLayout = source.screenLayout
        autoHideControls = source.autoHideControls
        performanceOverlay = source.performanceOverlay
    }

    /// A copy holding only the Advanced options, for the snapshot.
    var advancedFields: GameOverrides {
        var copy = self
        copy.takeBasicFields(from: .identity)
        return copy
    }

    /// What Basic uses: the Advanced options cleared, the Basic ones kept.
    func removingAdvancedFields() -> GameOverrides {
        var copy = GameOverrides()
        copy.takeBasicFields(from: self)
        return copy
    }

    /// Restore: takes the Advanced options from `other` and leaves the Basic ones as they are now.
    func adopting(advancedFieldsOf other: GameOverrides) -> GameOverrides {
        var copy = other
        copy.takeBasicFields(from: self)
        return copy
    }

    /// releaseFormerlyAdvanced: each Basic option this game doesn't set, taken from an older snapshot.
    /// The profile's three switches move together, so a game never ends up with half of two profiles.
    func filling(basicFieldsFrom snapshot: GameOverrides) -> GameOverrides {
        var copy = self
        if favourAccuracy == nil && favourPerformance == nil && oneCoreMode == nil {
            copy.favourAccuracy = snapshot.favourAccuracy
            copy.favourPerformance = snapshot.favourPerformance
            copy.oneCoreMode = snapshot.oneCoreMode
        }
        copy.renderScale = renderScale ?? snapshot.renderScale
        copy.screenLayout = screenLayout ?? snapshot.screenLayout
        copy.autoHideControls = autoHideControls ?? snapshot.autoHideControls
        copy.performanceOverlay = performanceOverlay ?? snapshot.performanceOverlay
        return copy
    }
}

extension PerGameSettingsStore {
    /// What a launch uses: this game's overrides, without the Advanced ones while Settings mode is
    /// Basic (they are hidden there, and a reset that keeps per-game options can leave them stored).
    func activeOverrides(for gameID: String) -> GameOverrides {
        let stored = overrides(for: gameID)
        return SettingsMode.isAdvanced ? stored : stored.removingAdvancedFields()
    }
}
