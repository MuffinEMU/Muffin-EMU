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
        pushDefaultsToBridge()
    }

    /// The same five calls GameManager already makes before every boot, and
    /// SettingsView's own onChange handlers make on every toggle. Removing a key
    /// makes its @AppStorage revert to the declared default on its own, but nothing
    /// re-runs an onChange for a change SwiftUI didn't originate here, so the
    /// running engine needs telling directly rather than left to notice.
    private static func pushDefaultsToBridge() {
        cemu_bridge_set_recompiler_enabled(true)
        cemu_bridge_set_favour_accuracy(false)
        cemu_bridge_set_low_power_mode(LowPowerMode.defaultValue)
        cemu_bridge_set_async_shader_compile(true)
        cemu_bridge_set_vsync_enabled(true)
        cemu_bridge_set_stretch_to_fill(FrameStretch.defaultValue)
    }
}
