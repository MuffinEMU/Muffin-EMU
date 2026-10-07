// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import Combine

/// Two styling switches: Classic UI (the flat v2.0 look: plain cards, text headers,
/// system-font rows) and Flat surfaces (removes the highlight and shading passes). Both
/// default off, and neither changes what the app can do.
///
/// Styling is centralised in shared components (`SettingsSectionHeader`, `SettingsRow`,
/// `ScreenChrome`, `MuffinTheme`), so flipping a flag there restyles the whole app without
/// touching call sites. Classic UI implies Flat surfaces, not the reverse. There is no
/// `.glassEffect` in the tree; `UIStyle.allowsLiquidGlass` is the gate any future one must sit
/// behind.
final class UIStyleStore: ObservableObject {
    static let shared = UIStyleStore()

    static let classicUIKey = "muffin.ui.classic"
    static let disableLiquidGlassKey = "muffin.ui.disableLiquidGlass"

    /// Both default off.
    static let classicUIDefault = false
    static let disableLiquidGlassDefault = false

    @Published var useClassicUI: Bool {
        didSet {
            guard oldValue != useClassicUI else { return }
            UserDefaults.standard.set(useClassicUI, forKey: Self.classicUIKey)
        }
    }

    @Published var disableLiquidGlass: Bool {
        didSet {
            guard oldValue != disableLiquidGlass else { return }
            UserDefaults.standard.set(disableLiquidGlass, forKey: Self.disableLiquidGlassKey)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        useClassicUI = defaults.object(forKey: Self.classicUIKey) as? Bool ?? Self.classicUIDefault
        disableLiquidGlass = defaults.object(forKey: Self.disableLiquidGlassKey) as? Bool ?? Self.disableLiquidGlassDefault
    }

    /// Re-reads both keys from UserDefaults; `SettingsDefaults.reset()` deletes them directly.
    func reloadFromDefaults() {
        let defaults = UserDefaults.standard
        let classic = defaults.object(forKey: Self.classicUIKey) as? Bool ?? Self.classicUIDefault
        let noGlass = defaults.object(forKey: Self.disableLiquidGlassKey) as? Bool ?? Self.disableLiquidGlassDefault
        if useClassicUI != classic { useClassicUI = classic }
        if disableLiquidGlass != noGlass { disableLiquidGlass = noGlass }
    }
}

/// Static read side for code that isn't a View (`ButtonStyle`s, `MuffinTheme` tokens, shared
/// row/header components). Views that observe the store re-render when a flag changes;
/// `ContentView` and `SettingsView` do.
enum UIStyle {
    /// True when the styling layer added after v2.0 should be bypassed entirely.
    static var isClassic: Bool { UIStyleStore.shared.useClassicUI }

    /// True when translucent / refractive / lighting-pass material must not be drawn.
    /// Classic UI implies this - v2.0 had no such material to begin with.
    static var glassDisabled: Bool {
        UIStyleStore.shared.disableLiquidGlass || UIStyleStore.shared.useClassicUI
    }

    /// The gate every `glassEffect` call site must sit behind if one is ever added.
    static var allowsLiquidGlass: Bool { !glassDisabled }
}
