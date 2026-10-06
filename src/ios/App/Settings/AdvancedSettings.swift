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
/// every one back to its default. Switching back to Advanced offers to restore the snapshot.
enum AdvancedSettings {
    /// What the app keeps while Basic is on, so Restore has something to bring back. The "muffin."
    /// prefix means a settings reset removes both.
    private static let snapshotKey = "muffin.settings.advancedSnapshot"
    private static let perGameSnapshotKey = "muffin.settings.advancedSnapshot.perGame"

    private static let cpuAndPerformance = AdvancedGroup(name: "CPU and performance", settings: [
        AdvancedSetting("muffin.cpu.favourAccuracy", false),
        AdvancedSetting(FavourPerformance.storageKey, FavourPerformance.defaultValue),
        AdvancedSetting(OneCoreMode.storageKey, OneCoreMode.defaultValue),
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
        AdvancedSetting(DisplayGammaSetting.storageKey, DisplayGammaSetting.defaultValue),
        AdvancedSetting("muffin.render.overrideAppGamma", false),
        AdvancedSetting(OverrideGammaSetting.storageKey, OverrideGammaSetting.defaultValue),
    ]) {
        let defaults = UserDefaults.standard
        cemu_bridge_set_render_upside_down(defaults.object(forKey: "muffin.render.upsideDown") as? Bool ?? false)
        cemu_bridge_set_framebuffer_fetch(defaults.object(forKey: "muffin.render.framebufferFetch") as? Bool ?? true)
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

    // Motion on/off and Recentre stay in Basic.
    private static let motionTuning = AdvancedGroup(name: "Motion tuning", settings: [
        AdvancedSetting(MotionSettings.sourceKey, MotionSettings.defaultSource),
        AdvancedSetting(MotionSettings.sensitivityKey, MotionSettings.defaultSensitivity),
        AdvancedSetting(MotionSettings.invertHorizontalKey, false),
        AdvancedSetting(MotionSettings.invertVerticalKey, false),
        AdvancedSetting(MotionSettings.diagnosticKey, false),
    ]) {
        MotionSettings.applyToBridge()
    }

    // The pad reads these through @AppStorage, so removing them is enough.
    private static let stickFeel = AdvancedGroup(name: "Stick feel", settings: [
        AdvancedSetting(ControllerLayoutSettings.stickGateKey, ControllerLayoutSettings.defaultStickGateRaw),
        AdvancedSetting(ControllerLayoutSettings.deadzoneKey, ControllerLayoutSettings.defaultDeadzone),
        AdvancedSetting(ControllerLayoutSettings.stickCurveKey, ControllerLayoutSettings.defaultStickCurve),
    ], applyToBridge: nil)

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

    static var allSettings: [AdvancedSetting] { groups.flatMap { $0.settings } }

    /// Whether anything advanced is away from its default, in the app or in a game's own options.
    static var hasCustomisedValues: Bool {
        allSettings.contains { !$0.isAtDefault() }
            || PerGameSettingsStore.shared.overridesByGame.values.contains { !$0.advancedFields.isIdentity }
    }

    /// Whether a snapshot is waiting for the person to restore or discard it.
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

    /// "Keep defaults": forgets what Basic saved.
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

    /// Tells the engine every advanced setting's current stored value.
    static func applyToBridge() {
        for group in groups { group.applyToBridge?() }
    }
}

/// Per-game options and Settings mode. Everything in GameOverrides is Advanced except
/// `preCompileShaders` (the Compile shaders in the background escape hatch, which Basic keeps), so a
/// field added to GameOverrides is Advanced without anything else to register.
extension GameOverrides {
    /// A copy holding only the Advanced options, for the snapshot.
    var advancedFields: GameOverrides {
        var copy = self
        copy.preCompileShaders = nil
        return copy
    }

    /// What Basic uses: the Advanced options cleared, the shader choice kept.
    func removingAdvancedFields() -> GameOverrides {
        var copy = GameOverrides()
        copy.preCompileShaders = preCompileShaders
        return copy
    }

    /// Restore: takes the Advanced options from `other` and leaves the shader choice as it is now.
    func adopting(advancedFieldsOf other: GameOverrides) -> GameOverrides {
        var copy = other
        copy.preCompileShaders = preCompileShaders
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
