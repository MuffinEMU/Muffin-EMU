import Foundation

/// What "Reset settings to defaults" (Settings > About) actually resets.
///
/// Scoped narrowly, on purpose: only UserDefaults keys under the "muffin." prefix
/// that are themselves settings. Two keys predate that prefix convention and are
/// NOT namespaced under it - RenderScale's "renderScale" and TimebaseScale's
/// "timebaseShift" - so this reset does not touch Resolution or the Emulated
/// Clock's chosen speed; picking those back to a default has to be done by hand,
/// same as choosing them the first time.
///
/// Three groups of "muffin."-prefixed keys are deliberately never touched here, no
/// matter which reset choice is picked:
///   - the premium unlock token and its install-key wrapper (PremiumUnlock) - a
///     paid unlock must never be a casualty of clearing performance settings
///   - the selected theme (MuffinThemeStore) - an appearance choice, not a setting,
///     grouped the same way "Appearance" sits apart from the rest of this Form
///   - per-game overrides (PerGameSettingsStore) - only removed if the person
///     explicitly picks "Reset Settings and Per-Game Options"
/// The library and favorites lists, and Wii U keys, are not "muffin."-prefixed keys
/// at all, so the prefix filter alone already leaves them alone.
enum SettingsDefaults {
    /// muffin.*-prefixed keys this reset always leaves alone, regardless of which
    /// choice is picked.
    private static let alwaysExcludedKeys: Set<String> = [
        "muffin.premium.token",
        "muffin.premium.ik",
        "muffin.theme.selectedId",
    ]

    /// @MainActor because it touches two main-actor-isolated stores on the way out:
    /// UIStyleStore (to repaint after the style keys are deleted) and ThermalMonitor
    /// (to unwind a throttle that was active when the reset happened). Both callers are
    /// in AboutSettingsSection's view body, which is already on the main actor, so this
    /// costs them nothing.
    @MainActor
    static func reset(includingPerGameOverrides: Bool) {
        let defaults = UserDefaults.standard
        var excluded = alwaysExcludedKeys
        if !includingPerGameOverrides {
            excluded.insert(PerGameSettingsStore.storageKey)
        }
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
        // No bridge call - the thermal response lives entirely on the Swift side. The
        // reset loop already removed the key, so this just makes sure a throttle that was
        // active at the moment of the reset is unwound rather than left holding the user's
        // Render Scale at battery saver.
        ThermalMonitor.shared.titleStopped()
        cemu_bridge_set_async_shader_compile(true)
        cemu_bridge_set_vsync_enabled(true)
        cemu_bridge_set_stretch_to_fill(FrameStretch.defaultValue)
    }
}
