import SwiftUI
import UIKit

extension Color {
    /// Hex string in "#RRGGBB" or "RRGGBB" form. Used only to define MuffinTheme's
    /// tokens below from the app icon's actual brand palette - not a general-purpose
    /// color-parsing utility, so no alpha/3-digit/8-digit support is needed.
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Trait-collection-adaptive color from two hex strings, light and dark. Every
    /// MuffinTheme token is built this way instead of a plain Color(hex:), which is
    /// what makes dark mode work everywhere MuffinTheme is already used (120+ call
    /// sites across 9 files) without touching a single one of them - UIColor's
    /// dynamic provider re-evaluates on every trait change (including Settings >
    /// Display & Brightness while the app is running, not just at next launch), and
    /// SwiftUI's Color(UIColor:) wraps that directly rather than resolving once.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

/// Brand palette lifted directly from muffin-emu-icon.svg (the app icon's source
/// art) - kawaii-bakery: warm cream cards, soft rounded corners, gentle shadows,
/// no translucent dark glass. Every token below is light/dark-adaptive (see
/// Color(light:dark:) above) rather than a plain Color(hex:) - the app had no dark
/// mode at all before this, every screen stayed the bright cream/orange light
/// palette regardless of the system setting.
///
/// The dark set is not an inversion - a straight invert of a cream-and-orange
/// bakery theme reads as a muddy grey app, nothing like the brand. Instead it's the
/// same palette pushed into a warm midnight-bakery register: deep chocolate/umber
/// surfaces instead of cream, the same muffin-top oranges and pixel-blue accent
/// pulled slightly warmer/brighter so they still pop against a dark ground instead
/// of washing out, and text flipped from dark-brown-on-cream to cream-on-dark-brown.
///
/// Every token below used to be a `static let` hardcoded to the Bakery hex pair
/// above. They're `static var`s reading through MuffinThemeStore.shared.current now,
/// so every one of this enum's 120+ existing call sites across 9 files picks up
/// whichever theme is selected (see MuffinThemeStore.swift, MuffinThemePresets.swift,
/// ThemePickerView.swift) without any of those call sites changing - `MuffinTheme.
/// pixelBlue` still means "the current theme's accent", it's just no longer
/// hardcoded to Bakery's.
enum MuffinTheme {
    private static var t: MuffinThemeDefinition { MuffinThemeStore.shared.current }

    // Background gradient (warm orange in Bakery) - dark keeps the same hue family,
    // deepened and desaturated slightly so a full-screen gradient isn't
    // retina-searing at night, the same way iOS's own dark backgrounds are never
    // just "black".
    static var backgroundTop: Color { Color(light: t.backgroundTopLight, dark: t.backgroundTopDark) }
    static var backgroundBottom: Color { Color(light: t.backgroundBottomLight, dark: t.backgroundBottomDark) }

    // Muffin-top gradient - kept closer to its light values than most tokens here,
    // since this gradient fills buttons/accents that need to stay recognizably
    // "muffin-colored" and readable against dark surfaces, not blend into them.
    static var muffinTopLight: Color { Color(light: t.muffinTopLightLight, dark: t.muffinTopLightDark) }
    static var muffinTopDark: Color { Color(light: t.muffinTopDarkLight, dark: t.muffinTopDarkDark) }

    // Cream / wrapper - the big one. These are card/background fills, so dark mode
    // needs them to actually be dark (deep umber, not just a duller cream) for
    // every MuffinCard-backed screen to read as a real dark theme rather than a
    // slightly-tinted light one.
    static var cream: Color { Color(light: t.creamLight, dark: t.creamDark) }
    static var wrapper: Color { Color(light: t.wrapperLight, dark: t.wrapperDark) }

    // Blueberry navy accent - lightened for dark mode so it still reads as a
    // distinct accent against dark cream/wrapper surfaces instead of nearly
    // vanishing into them.
    static var blueberryNavy: Color { Color(light: t.blueberryNavyLight, dark: t.blueberryNavyDark) }

    // Pixel-blue accent (the "EMU" nod) - brightened slightly, same reasoning as
    // blueberryNavy: an accent this saturated needs a touch more lightness to keep
    // reading as an accent once the surfaces around it go dark instead of cream.
    static var pixelBlue: Color { Color(light: t.pixelBlueLight, dark: t.pixelBlueDark) }

    // Blush pink - warmed slightly rather than lightened, keeps it feeling like the
    // same pink instead of turning pastel-on-dark.
    static var blushPink: Color { Color(light: t.blushPinkLight, dark: t.blushPinkDark) }

    // Dark brown (text / line work) - these were always meant to be "ink on cream",
    // so in dark mode they flip to light cream tones and become "ink on umber"
    // instead. brownDarkest (highest-contrast text) becomes the lightest of the
    // three, mirroring its light-mode role as the highest-contrast choice.
    static var brownDarkest: Color { Color(light: t.brownDarkestLight, dark: t.brownDarkestDark) }
    static var brownDark: Color { Color(light: t.brownDarkLight, dark: t.brownDarkDark) }
    static var brownMid: Color { Color(light: t.brownMidLight, dark: t.brownMidDark) }

    // Sparkle cream - stays light in both modes on purpose: it's used as button
    // text painted onto the muffin-top gradient fill, which stays a mid-warm-orange
    // in both themes, so the same light, high-contrast text color works for both.
    static var sparkleCream: Color { Color(light: t.sparkleCreamLight, dark: t.sparkleCreamDark) }

    // Shadow - lightened rather than darkened. A shadow needs to read as "recessed
    // relative to its surface" in both themes; a light-mode shadow colour against
    // the dark cream/wrapper surface is often barely distinguishable from the
    // surface itself, so dark mode needs a shadow colour with more contrast against
    // ITS ground, not a literal darkening.
    static var shadow: Color { Color(light: t.shadowLight, dark: t.shadowDark) }

    static var backgroundGradient: LinearGradient {
        // A theme may define more than two stops (see backgroundStopsLight). Each index
        // is a light/dark pair built through the same Color(light:dark:) provider as
        // every other token, so a multi-stop background re-evaluates on a trait change
        // exactly like a two-stop one does. Falls back to top -> bottom whenever the
        // stops are absent or the two arrays disagree in length, which is every theme
        // but one and also the only sane thing to do with a malformed pair.
        let lightStops = t.backgroundStopsLight
        let darkStops = t.backgroundStopsDark
        if lightStops.count >= 2 && lightStops.count == darkStops.count {
            let colors = zip(lightStops, darkStops).map { Color(light: $0, dark: $1) }
            let locations = t.backgroundStopLocations
            // Straight top-to-bottom rather than the diagonal the two-stop path uses.
            // A multi-stop background exists to put specific colour at a specific HEIGHT
            // - a rainbow across the header, one calm colour under the content - and a
            // diagonal smears every band across the corners, which reads as a mess
            // rather than as bands.
            if locations.count == colors.count {
                let stops = zip(colors, locations).map { Gradient.Stop(color: $0, location: $1) }
                return LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
            }
            return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var muffinTopGradient: LinearGradient {
        LinearGradient(colors: [muffinTopLight, muffinTopDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A warm cream card with a soft rounded corner and gentle drop shadow - the base
/// surface for library cards, settings sections, and picker rows.
struct MuffinCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var fill: Color = MuffinTheme.cream
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MuffinTheme.wrapper, lineWidth: 1)
            )
            .shadow(color: MuffinTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

/// Rounded, friendly primary button (muffin-top gradient fill, cream text) on iOS 25
/// and under. On iOS 26+, where Liquid Glass exists, the fill becomes real glass
/// (System's own translucent, refractive material) tinted with the same muffin-top
/// color instead of an opaque gradient - every one of this style's ~20 call sites
/// across the app (ContentView, DecryptROMView, IconPickerView, ThemePickerView,
/// SaveStateView) gets the upgrade automatically from this one place, with no other
/// file needing to know or care which OS it's running on.
struct MuffinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(MuffinTheme.sparkleCream)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

        if #available(iOS 26.0, *) {
            label
                .glassEffect(.regular.tint(MuffinTheme.muffinTopLight).interactive(), in: .rect(cornerRadius: 14))
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            label
                .background(MuffinTheme.muffinTopGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Rounded pill button for secondary/chrome actions (cream fill, brown text) on iOS 25
/// and under; real Liquid Glass, tinted cream, on iOS 26+ - same reasoning and same
/// automatic reach across every existing call site as MuffinPrimaryButtonStyle above.
/// This is the style every in-game top-bar button (pause, save states, controller
/// switcher, hide-controls, swap, emulated devices) already uses, which is exactly
/// where floating glass controls over game content are Liquid Glass's own showcase
/// use case.
struct MuffinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(MuffinTheme.brownDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

        if #available(iOS 26.0, *) {
            label
                .glassEffect(.regular.tint(MuffinTheme.cream).interactive(), in: .capsule)
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            label
                .background(MuffinTheme.cream.opacity(configuration.isPressed ? 0.7 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MuffinTheme.wrapper, lineWidth: 1)
                )
        }
    }
}
