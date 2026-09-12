import SwiftUI
import Combine

/// One full MuffinTheme palette as data instead of hardcoded constants. Every token is
/// stored as a light/dark hex pair, same shape as the `Color(light:dark:)` calls
/// MuffinTheme.swift already hand-wrote for the Bakery theme - this just makes that
/// shape swappable at runtime instead of fixed at compile time.
///
/// The thirty icon-matched themes in MuffinThemePresets.swift are a systematic
/// derivation from each icon's own real artwork (see that file's header), not hand
/// art-directed - a from-scratch pass per icon was out of scope for "one theme per
/// icon". Bakery is the one exception: it's the app's existing hand-tuned palette,
/// copied over as literal constants rather than re-derived, so this system changes
/// nothing for anyone who never opens the theme picker.
struct MuffinThemeDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    /// Matches AppIconOption.id from IconManifest, when this theme was derived from a
    /// specific icon's art - lets the theme picker show "matches your current icon"
    /// without a second hand-maintained mapping table.
    let iconId: String

    let backgroundTopLight: String, backgroundTopDark: String
    let backgroundBottomLight: String, backgroundBottomDark: String
    let muffinTopLightLight: String, muffinTopLightDark: String
    let muffinTopDarkLight: String, muffinTopDarkDark: String
    let creamLight: String, creamDark: String
    let wrapperLight: String, wrapperDark: String
    let blueberryNavyLight: String, blueberryNavyDark: String
    let pixelBlueLight: String, pixelBlueDark: String
    let blushPinkLight: String, blushPinkDark: String
    let brownDarkestLight: String, brownDarkestDark: String
    let brownDarkLight: String, brownDarkDark: String
    let brownMidLight: String, brownMidDark: String
    let sparkleCreamLight: String, sparkleCreamDark: String
    let shadowLight: String, shadowDark: String

    /// Optional multi-stop background gradient. Empty means "use backgroundTop ->
    /// backgroundBottom", which is what every theme did before this existed and what
    /// all but one still do - so adding it changed nothing for them.
    ///
    /// It exists because a two-stop gradient cannot express a rainbow, and some themes
    /// genuinely want one: the neurodiversity symbol this app's autism icon is drawn
    /// from is a rainbow infinity, and flattening that to two colours loses the thing
    /// the icon is actually about. The two arrays must be the same length - each index
    /// is one stop's light/dark pair, so the gradient stays trait-adaptive the same way
    /// every other token is.
    var backgroundStopsLight: [String] = []
    var backgroundStopsDark: [String] = []

    /// Where each stop sits, 0 at the top of the screen and 1 at the bottom. Empty
    /// means spread them evenly, which is what a plain LinearGradient(colors:) does.
    ///
    /// Needed because "a rainbow header over a calm body" is not an even spread - the
    /// colour has to be spent in the top third and then hold one value for the rest,
    /// otherwise the whole screen including Settings is rainbow and nothing on it is
    /// readable. Must be the same length as the stop arrays and ascending; anything
    /// else falls back to the even spread rather than rendering something arbitrary.
    var backgroundStopLocations: [Double] = []

    static func == (lhs: MuffinThemeDefinition, rhs: MuffinThemeDefinition) -> Bool { lhs.id == rhs.id }
}

/// The single source of truth for "which MuffinTheme palette is active right now".
/// MuffinTheme's own static properties read through this rather than fixed constants,
/// so every one of MuffinTheme's 120+ existing call sites goes on working unmodified -
/// they just now resolve to whichever theme is selected instead of always Bakery.
///
/// Deliberately independent of IconPickerView: picking an icon does not touch this,
/// and picking a theme does not touch the icon. A theme's `iconId` is only ever used to
/// label it "matches your icon" in the picker UI - never to force a coupling neither
/// picker enforces. That's the actual feature request: every icon gets a theme that
/// matches it by default availability, but nothing stops mixing any theme with any icon.
final class MuffinThemeStore: ObservableObject {
    static let shared = MuffinThemeStore()

    @Published private(set) var current: MuffinThemeDefinition

    private static let storageKey = "muffin.theme.selectedId"

    private init() {
        let storedId = UserDefaults.standard.string(forKey: Self.storageKey)
        current = MuffinThemePresets.all.first(where: { $0.id == storedId }) ?? MuffinThemePresets.bakery
    }

    func select(_ theme: MuffinThemeDefinition) {
        guard theme.id != current.id else { return }
        current = theme
        UserDefaults.standard.set(theme.id, forKey: Self.storageKey)
    }
}
