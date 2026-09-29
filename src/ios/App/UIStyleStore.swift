import SwiftUI
import Combine

/// Two switches over how the app is *styled*, with no effect on what it can do.
///
/// Both exist because UI work landed on 2026-09-15 that not everyone wants. Rather than
/// argue about taste in a changelog, the styling layer became switchable - every control,
/// row, section and setting stays exactly where it is and does exactly what it did, only
/// the presentation changes.
///
/// # Why this is implementable at all
///
/// Because that UI work was centralised into shared components rather than sprinkled
/// through call sites. Twenty-four Settings sections call `SettingsSectionHeader`, rows go
/// through `SettingsRow` and `DestructiveSettingsLabel`, screens go through `ScreenChrome`,
/// and depth/type/spacing all resolve through `MuffinTheme`. Flipping a flag inside those
/// components changes the whole app without touching a single call site.
///
/// # What Classic UI honestly is, and is not
///
/// It restores the **styling** the app had at v2.0 - flat cards with one soft shadow,
/// plain text section headers, system-font rows, no chips or badges or lighting passes.
///
/// It is NOT a v2.0 build, and cannot be. v2.0's view code does not contain Low Power
/// Mode, cover-art override, graphic packs, emulated devices, accounts, or anything else
/// added since; mounting those old views would delete features, which is the opposite of
/// what was asked for. So this reverts the look and keeps the app. Expect "the classic
/// styling", not a pixel-exact v2.0 screenshot.
///
/// # Why Liquid Glass gets its own switch
///
/// It is a strictly smaller ask than Classic UI: keep the new layout and typography, drop
/// only the translucent/refractive material. Folding the two together would force someone
/// who dislikes glass to also give up the new Settings organisation, which is not what
/// they asked for. Classic UI implies glass-off; glass-off does not imply Classic UI.
///
/// As of today there is no `.glassEffect` left in the tree - the iOS 26 Liquid Glass
/// adoption was reverted on 2026-09-15 because it made the UI feel clunky. So this switch has two jobs: it turns off the *glass-adjacent* material
/// that remains (the sheen and lighting passes in MuffinTheme's newer layer, which is what
/// still reads as glassy), and it is the permanent gate any future `glassEffect` must sit
/// behind, so real Liquid Glass can never come back ungated.
final class UIStyleStore: ObservableObject {
    static let shared = UIStyleStore()

    static let classicUIKey = "muffin.ui.classic"
    static let disableLiquidGlassKey = "muffin.ui.disableLiquidGlass"

    /// Both default OFF: the new styling is what the app ships as, and these are opt-outs
    /// for people who want the old look, not a quiet admission that the new one is wrong.
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

    /// Re-reads both keys from UserDefaults.
    ///
    /// Needed because `SettingsDefaults.reset()` deletes every `muffin.*` key directly
    /// rather than going through this object, so without this the store would keep
    /// serving the pre-reset values until the next launch - the same class of staleness
    /// PreviewPadSection's doc comment already warns about for @AppStorage shadowing a
    /// store.
    func reloadFromDefaults() {
        let defaults = UserDefaults.standard
        let classic = defaults.object(forKey: Self.classicUIKey) as? Bool ?? Self.classicUIDefault
        let noGlass = defaults.object(forKey: Self.disableLiquidGlassKey) as? Bool ?? Self.disableLiquidGlassDefault
        if useClassicUI != classic { useClassicUI = classic }
        if disableLiquidGlass != noGlass { disableLiquidGlass = noGlass }
    }
}

/// Static read side, for the places that style things but are not themselves Views and so
/// cannot hold an `@ObservedObject` - `ButtonStyle`s, `MuffinTheme`'s computed tokens,
/// and the shared row/header components.
///
/// Reading through the store rather than UserDefaults directly is deliberate: it means
/// there is one value in the process, and a view that DOES observe the store re-renders
/// its whole subtree when either flag changes, which is what makes the switch take effect
/// immediately instead of at the next launch. `ContentView` and `SettingsView` observe it
/// for exactly that reason.
enum UIStyle {
    /// True when the styling layer added after v2.0 should be bypassed entirely.
    static var isClassic: Bool { UIStyleStore.shared.useClassicUI }

    /// True when translucent / refractive / lighting-pass material must not be drawn.
    /// Classic UI implies this - v2.0 had no such material to begin with.
    static var glassDisabled: Bool {
        UIStyleStore.shared.disableLiquidGlass || UIStyleStore.shared.useClassicUI
    }

    /// The gate every real `glassEffect` call site must sit behind if one is ever added
    /// back. Written as its own name rather than `!glassDisabled` so the intent is
    /// greppable: searching for `allowsLiquidGlass` finds every place glass could appear.
    static var allowsLiquidGlass: Bool { !glassDisabled }
}
