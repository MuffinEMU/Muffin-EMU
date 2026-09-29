import Foundation

/// What "Reset settings to defaults" (Settings > About) resets: every UserDefaults key
/// under the "muffin." prefix that is a setting, plus Resolution ("renderScale") and
/// Emulated Clock ("timebaseShift"), which predate the prefix.
///
/// Never touched: the premium unlock, the selected theme, the onboarding-completed flag,
/// and per-game overrides (only removed if the person picks "Reset Settings and Per-Game
/// Options"). The library, favorites and Wii U keys aren't "muffin." keys at all.
enum SettingsDefaults {
    /// muffin.*-prefixed keys this reset always leaves alone, regardless of which
    /// choice is picked.
    private static let alwaysExcludedKeys: Set<String> = [
        "muffin.premium.token",
        "muffin.premium.ik",
        "muffin.theme.selectedId",
        OnboardingState.completedKey,
    ]

    /// @MainActor because it touches two main-actor-isolated stores on the way out:
    /// UIStyleStore (to repaint after the style keys are deleted) and ThermalMonitor
    /// (to unwind a throttle that was active when the reset happened). Both callers are
    /// in AboutSettingsSection's view body, which is already on the main actor, so this
    /// costs them nothing.
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
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("muffin.") && !excluded.contains(key) {
            defaults.removeObject(forKey: key)
        }
        if includingPerGameOverrides {
            PerGameSettingsStore.shared.removeAllOverrides()
        }
        // The style store caches both UI keys in @Published properties, and the loop
        // above removed them from UserDefaults without going through it - so without
        // this the app would keep rendering the pre-reset styling until relaunch.
        UIStyleStore.shared.reloadFromDefaults()
        pushDefaultsToBridge()
    }

    /// The same five calls GameManager already makes before every boot, and
    /// SettingsView's own onChange handlers make on every toggle. Removing a key
    /// makes its @AppStorage revert to the declared default on its own, but nothing
    /// re-runs an onChange for a change SwiftUI didn't originate here, so the
    /// running engine needs telling directly rather than left to notice.
    /// @MainActor for the ThermalMonitor call below. Its only caller, reset(), is already
    /// isolated, but a private static func is nonisolated by default in Swift 6 - it does
    /// not inherit isolation from whoever calls it.
    @MainActor
    private static func pushDefaultsToBridge() {
        cemu_bridge_set_recompiler_enabled(true)
        cemu_bridge_set_favour_accuracy(false)
        cemu_bridge_set_low_power_mode(LowPowerMode.defaultValue)
        cemu_bridge_set_multicore_enabled(MulticoreMode.defaultValue)
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
        cemu_bridge_set_overlay_cpu_mode(OverlaySettings.defaultCpuMode)
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
