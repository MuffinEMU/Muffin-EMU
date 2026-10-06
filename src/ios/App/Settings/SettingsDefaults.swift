import Foundation

extension Notification.Name {
    /// Posted after "Reset settings to defaults" has cleared and re-pushed everything, for
    /// sections that keep their own copy of a value (@State, not @AppStorage) to re-read it.
    static let muffinSettingsWereReset = Notification.Name("muffin.settings.wereReset")
}

/// What "Reset settings to defaults" (Settings > About) resets: every UserDefaults key
/// under the "muffin." prefix that is a setting, plus Resolution ("renderScale") and
/// Emulated Clock ("timebaseShift"), which predate the prefix.
///
/// Never touched: the premium unlock, the selected theme, the onboarding-completed flag,
/// and per-game overrides (only removed if the person picks "Reset Settings and Per-Game
/// Options"). Also never touched: the library's own records (favorites, the region and
/// title-name cache, graphic pack release info) and results the app worked out by itself
/// (cores Auto keeps on one, a Vulkan start failure, the one-time clock repair flag). They
/// share the "muffin." prefix but are data, not settings, and the confirmation says the
/// library and favorites are not affected.
enum SettingsDefaults {
    /// muffin.*-prefixed keys this reset always leaves alone, regardless of which
    /// choice is picked.
    private static let alwaysExcludedKeys: Set<String> = [
        "muffin.premium.token",
        "muffin.premium.ik",
        "muffin.theme.selectedId",
        OnboardingState.completedKey,
        // Recorded results. Resetting them would forget what the app learned (and re-run the
        // one-time repair, which would then erase a clock speed chosen after this reset).
        "muffin.cpu.autoDemoted",
        "muffin.cpu.autoMultiPending",
        "muffin.render.vulkanFailedBuild",
        "muffin.render.vulkanFailureReason",
        "muffin.timebase.clearedAccidentalChoice",
    ]

    /// Key prefixes this reset always leaves alone: favorites and the region/title-name cache
    /// ("muffin.library.") and the installed/latest graphic pack release ("muffin.graphicPacks.").
    private static let alwaysExcludedPrefixes = ["muffin.library.", "muffin.graphicPacks."]

    /// Per-game, like the overrides in PerGameSettingsStore: Adaptive's learned layout for each
    /// game. Kept unless the person picks "Reset Settings and Per-Game Options".
    private static let perGamePrefix = "muffin.touchlab.adaptive."

    /// @MainActor: touches UIStyleStore and ThermalMonitor, which are main-actor isolated.
    @MainActor
    static func reset(includingPerGameOverrides: Bool) {
        let defaults = UserDefaults.standard
        // Unwind an active thermal throttle first: it restores the Resolution the user
        // chose from a muffin.* key that the loop below deletes.
        ThermalMonitor.shared.titleStopped()
        var excluded = alwaysExcludedKeys
        if !includingPerGameOverrides {
            excluded.insert(PerGameSettingsStore.storageKey)
        }
        // Resolution and Emulated Clock predate the "muffin." prefix, so the loop below
        // doesn't cover them.
        defaults.removeObject(forKey: RenderScale.storageKey)
        DisplayRouter.shared.reapplyRenderScale(reason: "settings reset")
        TimebaseScale.clearChoice()
        // Back to Basic, with the saved advanced values forgotten. The sweep below would remove
        // these keys too; this keeps the rule next to the registry.
        AdvancedSettings.resetModeAndSnapshot()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("muffin.") {
            if excluded.contains(key) { continue }
            if alwaysExcludedPrefixes.contains(where: { key.hasPrefix($0) }) { continue }
            if !includingPerGameOverrides && key.hasPrefix(perGamePrefix) { continue }
            defaults.removeObject(forKey: key)
        }
        if includingPerGameOverrides {
            PerGameSettingsStore.shared.removeAllOverrides()
        }
        // The style store caches its keys, so it must re-read them after the loop above.
        UIStyleStore.shared.reloadFromDefaults()
        // Same for these two: they hold their values in memory and would otherwise keep the
        // old pad layout until the next launch, then silently change back.
        ControllerCustomLayout.shared.resetAll()
        PreviewPadStore.shared.reloadFromDefaults()
        pushDefaultsToBridge()
        NotificationCenter.default.post(name: .muffinSettingsWereReset, object: nil)
    }

    /// Tells the running engine the default values. Removing a key reverts its @AppStorage on
    /// its own, but no onChange fires for it, so the engine has to be told directly.
    @MainActor
    private static func pushDefaultsToBridge() {
        cemu_bridge_set_recompiler_enabled(true)
        cemu_bridge_set_favour_accuracy(false)
        cemu_bridge_set_favour_performance(FavourPerformance.defaultValue)
        cemu_bridge_set_full_speed_renders(FullSpeedRenders.defaultValue, Int32(FullSpeedRenders.defaultShaderMode.rawValue))
        cemu_bridge_set_low_power_mode(OneCoreMode.defaultValue)
        MotionSettings.applyToBridge() // its keys were just removed, so this pushes the defaults
        cemu_bridge_set_cpu_core_mode(CoreMode.defaultValue.bridgeValue)
        cemu_bridge_set_async_shader_compile(true)
        cemu_bridge_set_vsync_enabled(true)
        cemu_bridge_set_stretch_to_fill(FrameStretch.defaultValue)
        cemu_bridge_set_render_upside_down(false)
        cemu_bridge_set_framebuffer_fetch(true)
        cemu_bridge_set_display_gamma(Float(DisplayGammaSetting.defaultValue))
        cemu_bridge_set_override_app_gamma(false)
        cemu_bridge_set_override_gamma_value(Float(OverrideGammaSetting.defaultValue))

        cemu_bridge_set_tv_audio_enabled(AudioSettings.defaultTvEnabled)
        cemu_bridge_set_tv_volume(Int32(AudioSettings.defaultTvVolume))
        cemu_bridge_set_tv_channels(Int32(AudioSettings.defaultTvChannels))
        cemu_bridge_set_pad_audio_enabled(AudioSettings.defaultPadEnabled)
        cemu_bridge_set_pad_volume(Int32(AudioSettings.defaultPadVolume))
        cemu_bridge_set_pad_channels(Int32(AudioSettings.defaultPadChannels))
        cemu_bridge_set_microphone_enabled(AudioSettings.defaultMicrophoneEnabled)
        cemu_bridge_set_input_volume(Int32(AudioSettings.defaultInputVolume))

        cemu_bridge_set_overlay_position(Int32(OverlaySettings.defaultPosition.rawValue))
        cemu_bridge_set_overlay_text_color(UInt32(truncatingIfNeeded: OverlaySettings.defaultTextColor))
        cemu_bridge_set_overlay_text_scale(Int32(OverlaySettings.defaultTextScale))
        cemu_bridge_set_overlay_fps(OverlaySettings.defaultFps)
        cemu_bridge_set_overlay_drawcalls(OverlaySettings.defaultDrawcalls)
        cemu_bridge_set_overlay_cpu_usage(OverlaySettings.defaultCpuUsage)
        cemu_bridge_set_overlay_cpu_per_core_usage(OverlaySettings.defaultCpuPerCoreUsage)
        cemu_bridge_set_overlay_ram_usage(OverlaySettings.defaultRamUsage)
        cemu_bridge_set_overlay_vram_usage(OverlaySettings.defaultVramUsage)
        cemu_bridge_set_overlay_debug(OverlaySettings.defaultDebug)

        cemu_bridge_set_notification_position(Int32(NotificationSettings.defaultPosition.rawValue))
        cemu_bridge_set_notification_text_color(UInt32(truncatingIfNeeded: NotificationSettings.defaultTextColor))
        cemu_bridge_set_notification_text_scale(Int32(NotificationSettings.defaultTextScale))
        cemu_bridge_set_notification_controller_profiles(NotificationSettings.defaultControllerProfiles)
        cemu_bridge_set_notification_controller_battery(NotificationSettings.defaultControllerBattery)
        cemu_bridge_set_notification_shader_compiling(NotificationSettings.defaultShaderCompiling)
        cemu_bridge_set_notification_friends(NotificationSettings.defaultFriends)
    }
}
