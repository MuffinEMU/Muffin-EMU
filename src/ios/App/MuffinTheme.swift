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
enum MuffinTheme {
    // Background gradient (warm orange) - dark keeps the same hue family, deepened
    // and desaturated slightly so a full-screen gradient isn't retina-searing at
    // night, the same way iOS's own dark backgrounds are never just "black".
    static let backgroundTop = Color(light: "#F6A94F", dark: "#7A4A22")
    static let backgroundBottom = Color(light: "#E5652E", dark: "#4A2410")

    // Muffin-top gradient - kept closer to its light values than most tokens here,
    // since this gradient fills buttons/accents that need to stay recognizably
    // "muffin-colored" and readable against dark surfaces, not blend into them.
    static let muffinTopLight = Color(light: "#E3A254", dark: "#C98A46")
    static let muffinTopDark = Color(light: "#A8622A", dark: "#8A4E20")

    // Cream / wrapper - the big one. These are card/background fills, so dark mode
    // needs them to actually be dark (deep umber, not just a duller cream) for
    // every MuffinCard-backed screen to read as a real dark theme rather than a
    // slightly-tinted light one.
    static let cream = Color(light: "#FDF6EC", dark: "#241813")
    static let wrapper = Color(light: "#F0DFC3", dark: "#3A2A1E")

    // Blueberry navy accent - lightened for dark mode so it still reads as a
    // distinct accent against dark cream/wrapper surfaces instead of nearly
    // vanishing into them.
    static let blueberryNavy = Color(light: "#453765", dark: "#8177AD")

    // Pixel-blue accent (the "EMU" nod) - brightened slightly, same reasoning as
    // blueberryNavy: an accent this saturated needs a touch more lightness to keep
    // reading as an accent once the surfaces around it go dark instead of cream.
    static let pixelBlue = Color(light: "#6C63FF", dark: "#8A82FF")

    // Blush pink - warmed slightly rather than lightened, keeps it feeling like the
    // same pink instead of turning pastel-on-dark.
    static let blushPink = Color(light: "#F2A6A0", dark: "#E08880")

    // Dark brown (text / line work) - these were always meant to be "ink on cream",
    // so in dark mode they flip to light cream tones and become "ink on umber"
    // instead. brownDarkest (highest-contrast text) becomes the lightest of the
    // three, mirroring its light-mode role as the highest-contrast choice.
    static let brownDarkest = Color(light: "#2E1B10", dark: "#FBEBD8")
    static let brownDark = Color(light: "#5C2E10", dark: "#E8CBA8")
    static let brownMid = Color(light: "#7A4A22", dark: "#C9A47C")

    // Sparkle cream - stays light in both modes on purpose: it's used as button
    // text painted onto the muffin-top gradient fill, which stays a mid-warm-orange
    // in both themes, so the same light, high-contrast text color works for both.
    static let sparkleCream = Color(light: "#FFF3DD", dark: "#FFF3DD")

    // Shadow - lightened rather than darkened. A shadow needs to read as "recessed
    // relative to its surface" in both themes; #4A2410 against the light cream
    // background reads as a shadow, but the same color against the dark umber
    // background (#241813) is barely distinguishable from the surface itself, so
    // dark mode needs a shadow color with more contrast against ITS ground, not a
    // literal darkening.
    static let shadow = Color(light: "#4A2410", dark: "#000000")

    static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let muffinTopGradient = LinearGradient(
        colors: [muffinTopLight, muffinTopDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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

/// Rounded, friendly primary button (muffin-top gradient fill, cream text).
struct MuffinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(MuffinTheme.sparkleCream)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MuffinTheme.muffinTopGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Rounded pill button for secondary/chrome actions (cream fill, brown text).
struct MuffinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(MuffinTheme.brownDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MuffinTheme.cream.opacity(configuration.isPressed ? 0.7 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MuffinTheme.wrapper, lineWidth: 1)
            )
    }
}
