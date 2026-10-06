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

    /// Trait-collection-adaptive color from two hex strings, light and dark. Every MuffinTheme
    /// token is built this way, so dark mode works everywhere without touching call sites.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }

    /// Like `init(light:dark:)` with a different alpha per appearance, for the lighting passes
    /// (a highlight that is right on a light card is too weak on a dark one).
    init(light: String, lightAlpha: Double, dark: String, darkAlpha: Double) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark)).withAlphaComponent(CGFloat(darkAlpha))
                : UIColor(Color(hex: light)).withAlphaComponent(CGFloat(lightAlpha))
        })
    }
}

// MARK: - Palette arithmetic

/// The three channels of a "#RRGGBB" string, 0...255.
private func muffinHexChannels(_ hex: String) -> (Double, Double, Double) {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    var value: UInt64 = 0
    Scanner(string: s).scanHexInt64(&value)
    return (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
}

/// Linear sRGB mix of two "#RRGGBB" strings, returned in the same form. Every derived token
/// goes through here instead of a new hex constant, so every theme inherits the depth system.
private func muffinMixHex(_ a: String, _ b: String, _ amount: Double) -> String {
    let k = min(max(amount, 0), 1)
    let (ar, ag, ab) = muffinHexChannels(a)
    let (br, bg, bb) = muffinHexChannels(b)
    let r = UInt64((ar + (br - ar) * k).rounded())
    let g = UInt64((ag + (bg - ag) * k).rounded())
    let b2 = UInt64((ab + (bb - ab) * k).rounded())
    return String(format: "#%02llX%02llX%02llX", r, g, b2)
}

/// Toward white - a lit edge.
private func muffinLift(_ hex: String, _ amount: Double) -> String {
    muffinMixHex(hex, "#FFFFFF", amount)
}

/// Toward black - an edge falling away from the light, or a surface pushed in.
private func muffinDeepen(_ hex: String, _ amount: Double) -> String {
    muffinMixHex(hex, "#000000", amount)
}

// MARK: - Contrast

/// WCAG 2 relative luminance of a "#RRGGBB" string.
private func muffinLuminance(_ hex: String) -> Double {
    let (r, g, b) = muffinHexChannels(hex)
    func linear(_ v: Double) -> Double {
        let c = v / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

/// WCAG 2 contrast ratio between two "#RRGGBB" strings, 1 to 21.
private func muffinContrast(_ a: String, _ b: String) -> Double {
    let la = muffinLuminance(a)
    let lb = muffinLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// The lowest contrast `hex` has against any of `grounds`.
private func muffinWorstContrast(_ hex: String, on grounds: [String]) -> Double {
    grounds.map { muffinContrast(hex, $0) }.min() ?? 21
}

/// `hex` moved toward `toward` (black or white) only as far as it takes to reach `minimum`
/// contrast against every colour in `grounds`. A colour that already passes comes back
/// unchanged, so a theme that was already readable looks exactly as it did.
private func muffinReadable(_ hex: String, on grounds: [String], minimum: Double, toward: String) -> String {
    var amount = 0.0
    while amount < 1.0 {
        let candidate = muffinMixHex(hex, toward, amount)
        if muffinWorstContrast(candidate, on: grounds) >= minimum { return candidate }
        amount += 0.05
    }
    return toward
}

/// Brand palette from the app icon: warm cream cards, soft rounded corners, gentle shadows.
/// Every token is light/dark adaptive (see Color(light:dark:)); the dark set is a warm
/// umber palette rather than an inversion.
///
/// Tokens read through MuffinThemeStore.shared.current, so the selected theme applies
/// everywhere (see MuffinThemeStore.swift, MuffinThemePresets.swift, ThemePickerView.swift).
///
/// From `MARK: - Derived surface tokens` down is the depth, type, spacing and motion layer,
/// derived from the fourteen palette tokens above it.
enum MuffinTheme {
    private static var t: MuffinThemeDefinition { MuffinThemeStore.shared.current }

    // Background gradient. Dark keeps the hue family, deepened and desaturated.
    static var backgroundTop: Color { Color(light: t.backgroundTopLight, dark: t.backgroundTopDark) }
    static var backgroundBottom: Color { Color(light: t.backgroundBottomLight, dark: t.backgroundBottomDark) }

    // Muffin-top gradient: stays close to its light values so buttons stay muffin-coloured.
    static var muffinTopLight: Color { Color(light: t.muffinTopLightLight, dark: t.muffinTopLightDark) }
    static var muffinTopDark: Color { Color(light: t.muffinTopDarkLight, dark: t.muffinTopDarkDark) }

    // Cream / wrapper: card and background fills; dark mode uses deep umber.
    static var cream: Color { Color(light: t.creamLight, dark: t.creamDark) }
    static var wrapper: Color { Color(light: t.wrapperLight, dark: t.wrapperDark) }

    // Blueberry navy accent, lightened for dark mode.
    static var blueberryNavy: Color { Color(light: t.blueberryNavyLight, dark: t.blueberryNavyDark) }

    // Pixel-blue accent, brightened slightly for dark mode.
    static var pixelBlue: Color { Color(light: t.pixelBlueLight, dark: t.pixelBlueDark) }

    // Blush pink, warmed slightly for dark mode.
    static var blushPink: Color { Color(light: t.blushPinkLight, dark: t.blushPinkDark) }

    // Text and line work: dark browns on cream flip to light creams on umber. Each one is held
    // to 4.5:1 against every surface text sits on (readableInk), so a palette whose mid brown
    // was a shade too light on white Form rows reads properly without its hex changing.
    static var brownDarkest: Color { readableInk(light: t.brownDarkestLight, dark: t.brownDarkestDark) }
    static var brownDark: Color { readableInk(light: t.brownDarkLight, dark: t.brownDarkDark) }
    static var brownMid: Color { readableInk(light: t.brownMidLight, dark: t.brownMidDark) }

    // Sparkle cream: light in both modes. Button text on the muffin-top gradient goes through
    // onMuffinTop, which swaps it for a dark ink on the pale gradients where cream won't read.
    static var sparkleCream: Color { Color(light: t.sparkleCreamLight, dark: t.sparkleCreamDark) }

    // Shadow: dark mode uses a colour with more contrast against its ground.
    static var shadow: Color { Color(light: t.shadowLight, dark: t.shadowDark) }

    // MARK: - Readable text tokens

    /// Every surface text sits on in light mode: the system Form row and its grouped ground
    /// (Settings and most sheets), and the theme's cream, wrapper and sunken surfaces.
    private static var lightTextGrounds: [String] {
        ["#FFFFFF", "#F2F2F7", t.creamLight, t.wrapperLight,
         muffinDeepen(muffinMixHex(t.creamLight, t.wrapperLight, 0.8), 0.04)]
    }

    /// The same in dark mode, including the lifted row colour a Form gets inside a sheet.
    private static var darkTextGrounds: [String] {
        ["#000000", "#1C1C1E", "#2C2C2E", t.creamDark, t.wrapperDark]
    }

    /// A light/dark pair held to 4.5:1 on every text surface: darkened in light mode,
    /// lightened in dark mode, and only as far as it takes.
    private static func readableInk(light: String, dark: String) -> Color {
        Color(light: muffinReadable(light, on: lightTextGrounds, minimum: 4.5, toward: "#000000"),
              dark: muffinReadable(dark, on: darkTextGrounds, minimum: 4.5, toward: "#FFFFFF"))
    }

    /// pixelBlue for text, glyphs and control tints (menu picker values, links, toggles).
    /// Several themes use a pale accent - ADHD Awareness' is yellow - which vanished as text
    /// on a white row. pixelBlue itself stays for fills and strokes.
    static var accentText: Color { readableInk(light: t.pixelBlueLight, dark: t.pixelBlueDark) }

    /// blushPink for warning text and status glyphs on a light or dark surface. blushPink
    /// itself stays for fills.
    static var alertText: Color { readableInk(light: t.blushPinkLight, dark: t.blushPinkDark) }

    /// Any palette pair as text or a glyph on a row or card, held to 4.5:1 like the inks.
    static func readable(_ light: KeyPath<MuffinThemeDefinition, String>,
                         _ dark: KeyPath<MuffinThemeDefinition, String>) -> Color {
        readableInk(light: t[keyPath: light], dark: t[keyPath: dark])
    }

    /// Text on a pixelBlue fill (status chips): cream or the dark ink, whichever reads on that
    /// theme's accent. Cream on ADHD Awareness' yellow accent was 1.2:1.
    static var onAccent: Color {
        Color(light: inkOn(t.pixelBlueLight, cream: t.sparkleCreamLight),
              dark: inkOn(t.pixelBlueDark, cream: t.sparkleCreamDark))
    }

    private static func inkOn(_ fill: String, cream: String) -> String {
        muffinContrast(cream, fill) >= muffinContrast(t.brownDarkestLight, fill) ? cream : t.brownDarkestLight
    }

    /// Orange status text ("Experimental", the preview warnings). System orange is about 2:1
    /// on cream, so it is darkened to an amber in light mode.
    static var cautionText: Color { readableInk(light: "#FF9500", dark: "#FF9F0A") }

    /// Secondary text and captions. The system's `.secondary` grey is about 3.4:1 on a white
    /// row and under 3:1 on some wrappers, too faint for 12pt captions; this is the same
    /// neutral grey held to 4.5:1.
    static var secondaryText: Color { readableInk(light: "#8A8A8E", dark: "#9C9CA3") }

    /// The accent on the always-dark panels (launch log, in-game top bar, error screen),
    /// whatever the appearance. Several light-mode accents are deep navies and reds that
    /// were dark on dark there.
    static var accentOnDark: Color {
        Color(hex: muffinReadable(t.pixelBlueDark, on: darkPanelGrounds, minimum: 4.5, toward: "#FFFFFF"))
    }

    /// blushPink on those same dark panels.
    static var alertOnDark: Color {
        Color(hex: muffinReadable(t.blushPinkDark, on: darkPanelGrounds, minimum: 4.5, toward: "#FFFFFF"))
    }

    /// The dark panels: black at 50 to 85% over a game frame or the gradient. The lightest
    /// of them over a bright frame is about #404040.
    private static var darkPanelGrounds: [String] { ["#000000", "#262626", "#404040"] }

    /// Text and glyphs painted on the muffin-top gradient (primary buttons, the placeholder
    /// cover). sparkleCream where it reads on that gradient; otherwise a deep ink in the
    /// gradient's own hue. Pale gradients (Lemon Zest, Strawberry, Mint Matcha) made cream
    /// button labels all but disappear.
    static var onMuffinTop: Color {
        Color(light: onMuffinTopHex(dark: false), dark: onMuffinTopHex(dark: true))
    }

    private static func onMuffinTopHex(dark: Bool) -> String {
        let top = dark ? t.muffinTopLightDark : t.muffinTopLightLight
        let bottom = dark ? t.muffinTopDarkDark : t.muffinTopDarkLight
        // Where a label actually sits on a diagonal gradient: the middle half of it.
        let grounds = [0.25, 0.5, 0.75].map { muffinMixHex(top, bottom, $0) }
        let cream = dark ? t.sparkleCreamDark : t.sparkleCreamLight
        let creamWorst = muffinWorstContrast(cream, on: grounds)
        if creamWorst >= 3.0 { return cream }
        let ink = muffinDeepen(t.muffinTopDarkLight, 0.78)
        return muffinWorstContrast(ink, on: grounds) > creamWorst ? ink : cream
    }

    /// The grouped background a Form or List draws, for a navigation bar that should match it.
    static var formGround: Color { Color(UIColor.systemGroupedBackground) }

    /// The background gradient's colours, top to bottom, for the tokens below.
    private static func backgroundSamples(dark: Bool) -> [String] {
        let lightStops = t.backgroundStopsLight
        let darkStops = t.backgroundStopsDark
        if lightStops.count >= 2 && lightStops.count == darkStops.count {
            return dark ? darkStops : lightStops
        }
        let top = dark ? t.backgroundTopDark : t.backgroundTopLight
        let bottom = dark ? t.backgroundBottomDark : t.backgroundBottomLight
        return [0.0, 0.25, 0.5, 0.75, 1.0].map { muffinMixHex(top, bottom, $0) }
    }

    /// Text drawn straight onto the background gradient (the library header, the decrypt
    /// screen): whichever of the theme's dark ink and sparkleCream reads better against
    /// the whole gradient, pushed further if it still falls short. Several themes - Neon
    /// Cyber, Spooky, Double Chocolate, the flags - have a dark gradient in light mode, where
    /// the usual dark ink was dark on dark; the orange ones made cream text light on light.
    static var onBackground: Color {
        Color(light: onBackgroundHex(dark: false), dark: onBackgroundHex(dark: true))
    }

    /// Secondary text on the background gradient: a step softer than onBackground, still 4.5:1.
    static var onBackgroundMuted: Color {
        Color(light: onBackgroundMutedHex(dark: false), dark: onBackgroundMutedHex(dark: true))
    }

    /// The accent (pixelBlue) on the background gradient, for large text and glyphs (3:1).
    static var onBackgroundAccent: Color {
        Color(light: onBackgroundAccentHex(dark: false), dark: onBackgroundAccentHex(dark: true))
    }

    private static func onBackgroundHex(dark: Bool) -> String {
        let samples = backgroundSamples(dark: dark)
        // The light-mode ink in both appearances: some dark-mode gradients (Lemon Zest's
        // mustard) are light enough that dark text is the one that reads.
        let ink = t.brownDarkestLight
        let cream = dark ? t.sparkleCreamDark : t.sparkleCreamLight
        let chosen = muffinWorstContrast(ink, on: samples) >= muffinWorstContrast(cream, on: samples) ? ink : cream
        return muffinReadable(chosen, on: samples, minimum: 4.5, toward: onBackgroundPole(chosen))
    }

    private static func onBackgroundMutedHex(dark: Bool) -> String {
        let samples = backgroundSamples(dark: dark)
        let primary = onBackgroundHex(dark: dark)
        let softened = muffinMixHex(primary, samples[samples.count / 2], 0.3)
        return muffinReadable(softened, on: samples, minimum: 4.5, toward: onBackgroundPole(primary))
    }

    private static func onBackgroundAccentHex(dark: Bool) -> String {
        let samples = backgroundSamples(dark: dark)
        let accent = dark ? t.pixelBlueDark : t.pixelBlueLight
        return muffinReadable(accent, on: samples, minimum: 3.0, toward: onBackgroundPole(onBackgroundHex(dark: dark)))
    }

    /// Which way to push a colour that sits on the gradient: toward black for dark ink,
    /// toward white for light ink.
    private static func onBackgroundPole(_ ink: String) -> String {
        muffinLuminance(ink) < 0.18 ? "#000000" : "#FFFFFF"
    }

    static var backgroundGradient: LinearGradient {
        // A theme may define more than two stops (backgroundStopsLight); each index is a
        // light/dark pair. Falls back to top -> bottom if the arrays are absent or differ in length.
        let lightStops = t.backgroundStopsLight
        let darkStops = t.backgroundStopsDark
        if lightStops.count >= 2 && lightStops.count == darkStops.count {
            let colors = zip(lightStops, darkStops).map { Color(light: $0, dark: $1) }
            let locations = t.backgroundStopLocations
            // Straight top-to-bottom so bands sit at a specific height.
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

    // MARK: - Derived surface tokens

    /// The lit top edge of a cream surface: the wrapper colour lifted toward white. Stronger in
    /// dark mode, where the drop shadow is nearly invisible and the rim carries the elevation.
    static var surfaceHighlight: Color {
        Color(light: muffinLift(t.wrapperLight, 0.70), dark: muffinLift(t.wrapperDark, 0.34))
    }

    /// The unlit bottom edge of a cream surface: the wrapper colour deepened.
    static var surfaceShade: Color {
        Color(light: muffinDeepen(t.wrapperLight, 0.14), dark: muffinDeepen(t.wrapperDark, 0.40))
    }

    /// Top-to-bottom rim for cream surfaces: lit edge, wrapper colour, unlit edge. Draw with
    /// `.strokeBorder` so the line sits inside the clip.
    static var edgeStroke: LinearGradient {
        // Classic UI: flat 1pt wrapper outline.
        if UIStyle.isClassic {
            return LinearGradient(colors: [wrapper, wrapper], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: surfaceHighlight, location: 0.0),
                Gradient.Stop(color: wrapper, location: 0.55),
                Gradient.Stop(color: surfaceShade, location: 1.0)
            ]),
            startPoint: .top, endPoint: .bottom)
    }

    /// The same rim for muffin-top controls, derived from the muffin-top pair so the edge stays
    /// in the control's own colour family.
    static var controlEdgeStroke: LinearGradient {
        // Classic UI: flat wrapper outline.
        if UIStyle.isClassic {
            return LinearGradient(colors: [wrapper, wrapper], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [
                Color(light: muffinLift(t.muffinTopLightLight, 0.42), dark: muffinLift(t.muffinTopLightDark, 0.34)),
                Color(light: muffinDeepen(t.muffinTopDarkLight, 0.20), dark: muffinDeepen(t.muffinTopDarkDark, 0.26))
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// The muffin-top gradient under a finger: both stops deepened equally. A derived fill
    /// rather than a `.brightness` filter, which would dim the label and force an offscreen
    /// render pass over the live Metal layer.
    static var muffinTopGradientPressed: LinearGradient {
        LinearGradient(
            colors: [
                Color(light: muffinDeepen(t.muffinTopLightLight, 0.10), dark: muffinDeepen(t.muffinTopLightDark, 0.10)),
                Color(light: muffinDeepen(t.muffinTopDarkLight, 0.10), dark: muffinDeepen(t.muffinTopDarkDark, 0.10))
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Cream under a finger: deepened in light mode, lifted in dark.
    static var creamPressed: Color {
        Color(light: muffinDeepen(t.creamLight, 0.07), dark: muffinLift(t.creamDark, 0.10))
    }

    /// A cream surface lifted a step, mixed toward wrapper to stay warm.
    static var surfaceRaised: Color {
        Color(light: muffinMixHex(t.creamLight, t.wrapperLight, 0.45),
              dark: muffinMixHex(t.creamDark, t.wrapperDark, 0.55))
    }

    /// A cream surface pushed a step back (slider track, inset field).
    static var surfaceSunken: Color {
        Color(light: muffinDeepen(muffinMixHex(t.creamLight, t.wrapperLight, 0.8), 0.04),
              dark: muffinDeepen(t.creamDark, 0.35))
    }

    /// Separator colour for rows inside a card.
    static var hairline: Color {
        Color(light: muffinMixHex(t.wrapperLight, t.brownMidLight, 0.22),
              dark: muffinMixHex(t.wrapperDark, t.brownMidDark, 0.18))
    }

    /// One device pixel, not one point.
    static var hairlineWidth: CGFloat {
        let scale = UITraitCollection.current.displayScale
        return scale > 0 ? 1.0 / scale : 0.5
    }

    /// Dimming layer behind a sheet or modal, tinted with the theme's shadow colour.
    static var scrim: Color {
        Color(light: t.shadowLight, lightAlpha: 0.26, dark: "#000000", darkAlpha: 0.48)
    }

    // MARK: - Lighting

    // The sheen gradients are white and black at low alpha, composited over whatever fill the
    // surface has. They are ordinary gradient fills, not backdrop effects, so they are safe
    // over the in-game chrome.

    static var sheenHighlight: Color {
        Color(light: "#FFFFFF", lightAlpha: 0.32, dark: "#FFFFFF", darkAlpha: 0.075)
    }

    static var sheenOcclusion: Color {
        Color(light: "#000000", lightAlpha: 0.035, dark: "#000000", darkAlpha: 0.11)
    }

    /// Lighting pass for a large surface (cards, sheets): highlight in the top ~40%, occlusion
    /// in the bottom ~30%, nothing in the middle.
    static var surfaceSheen: LinearGradient {
        // Flat surfaces: a clear gradient leaves the fill untouched.
        if UIStyle.glassDisabled {
            return LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: sheenHighlight, location: 0.0),
                Gradient.Stop(color: .clear, location: 0.40),
                Gradient.Stop(color: .clear, location: 0.70),
                Gradient.Stop(color: sheenOcclusion, location: 1.0)
            ]),
            startPoint: .top, endPoint: .bottom)
    }

    /// Lighting pass for a small control (buttons, chips): a tighter glint on the top third.
    static var controlSheen: LinearGradient {
        if UIStyle.glassDisabled {
            return LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: sheenHighlight, location: 0.0),
                Gradient.Stop(color: .clear, location: 0.30),
                Gradient.Stop(color: .clear, location: 0.78),
                Gradient.Stop(color: sheenOcclusion, location: 1.0)
            ]),
            startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Elevation

    /// How far off its ground a surface sits. Every level is two shadows: a small, fairly
    /// opaque contact shadow that anchors the object, and a wide faint ambient one. As a
    /// surface lifts, the contact shadow stays small while the ambient one grows.
    enum Elevation {
        /// No shadow at all. The pressed state of a button, or a surface that is
        /// genuinely flush with its ground.
        case flush
        /// A card at rest on the background. Also used by the in-game chrome.
        case resting
        /// A button, or a card under the finger.
        case raised
        /// Chrome floating over busy, unpredictable content.
        case floating
        /// A sheet or popover over the whole app.
        case overlay

        /// Tight, anchoring, relatively opaque.
        var contact: (radius: CGFloat, y: CGFloat, opacity: Double) {
            switch self {
            case .flush:    return (0, 0, 0)
            case .resting:  return (1.5, 1, 0.13)
            case .raised:   return (2, 1, 0.15)
            case .floating: return (3, 2, 0.17)
            case .overlay:  return (4, 2, 0.19)
            }
        }

        /// Wide, soft, faint.
        var ambient: (radius: CGFloat, y: CGFloat, opacity: Double) {
            switch self {
            case .flush:    return (0, 0, 0)
            case .resting:  return (9, 3, 0.10)
            case .raised:   return (15, 6, 0.12)
            case .floating: return (24, 11, 0.13)
            case .overlay:  return (36, 18, 0.17)
            }
        }
    }

    // MARK: - Type scale

    /// The app's type ramp: a row label is 15 semibold rounded, an empty-state caption is 13
    /// rounded, and a Settings sub-caption is 12 and not rounded (it pairs with secondaryText).
    /// `.rounded` is the app's voice. Each token is a text style, so it follows the Dynamic Type setting, and
    /// at the default setting it is the size it always was: 28 title, 22 title2, 17 headline, 15 subheadline,
    /// 13 footnote, 12 caption, 11 caption2. The in-game bar and pads are capped at Extra Large where they are
    /// drawn, because they are laid out against measured geometry. MuffinPrimaryButtonStyle's 14 has no
    /// matching text style and stays fixed.
    enum Font {
        /// Screen-owning titles.
        static var display: SwiftUI.Font { .system(.title, design: .rounded).weight(.bold) }
        /// Titles inside a screen, sheet headers.
        static var title: SwiftUI.Font { .system(.title2, design: .rounded).weight(.bold) }
        /// Section headers in a Form or List.
        static var sectionTitle: SwiftUI.Font { .system(.headline, design: .rounded) }
        /// The leading label of a settings row or a list item. The app's workhorse.
        static var rowLabel: SwiftUI.Font { .system(.subheadline, design: .rounded).weight(.semibold) }
        /// The trailing value on that same row - same size, unemphasised.
        static var rowValue: SwiftUI.Font { .system(.subheadline, design: .rounded) }
        /// Running text, and empty-state copy.
        static var caption: SwiftUI.Font { .system(.footnote, design: .rounded) }
        /// The explanatory line under a settings row. Not rounded - see above.
        static var subCaption: SwiftUI.Font { .system(.caption) }
        /// Counts, badges, the smallest readable label.
        static var micro: SwiftUI.Font { .system(.caption2) }
        /// MuffinPrimaryButtonStyle's label.
        static var primaryButton: SwiftUI.Font { .system(size: 14, weight: .bold, design: .rounded) }
        /// MuffinSecondaryButtonStyle's label.
        static var secondaryButton: SwiftUI.Font { .system(.footnote, design: .rounded).weight(.semibold) }
        /// Version strings, title IDs, hashes - anything that must not be kerned into
        /// prose. Monospaced rather than rounded on purpose; it is data, not voice.
        static var monoTag: SwiftUI.Font { .system(.caption, design: .monospaced).weight(.semibold) }
    }

    // MARK: - Spacing and shape

    /// Padding and gap sizes on a 4pt rhythm.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let regular: CGFloat = 12
        static let comfy: CGFloat = 16
        static let loose: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// Corner radii, matching the existing defaults (card 18, control 14, chip 12); all drawn
    /// `.continuous`.
    enum Radius {
        static let chip: CGFloat = 12
        static let control: CGFloat = 14
        static let card: CGFloat = 18
        static let sheet: CGFloat = 28
    }

    // MARK: - Motion

    /// Timing curves. Press feedback is asymmetric: a very short ease down and an underdamped
    /// spring back up (`press(isPressed:reduceMotion:)`).
    enum Motion {
        /// Going down. Short enough to be perceived as immediate.
        static var pressDown: SwiftUI.Animation { .easeOut(duration: 0.07) }
        /// Coming back up. Slightly underdamped, so it overshoots once and settles.
        static var pressRelease: SwiftUI.Animation { .spring(response: 0.34, dampingFraction: 0.60, blendDuration: 0) }
        /// A discrete state change - selection moving, a toggle, chrome appearing.
        static var state: SwiftUI.Animation { .spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0) }
        /// A large move - navigation, a panel sliding, a layout reflow. Critically
        /// damped; big things that bounce read as cheap.
        static var layout: SwiftUI.Animation { .spring(response: 0.42, dampingFraction: 0.90, blendDuration: 0) }

        /// How far a control shrinks under a finger. Small on purpose - the scale is
        /// there to confirm the touch landed, not to animate.
        static let pressScale: CGFloat = 0.97
        /// Slightly more for the smaller secondary control, so the effect reads at
        /// its size rather than being proportionally invisible.
        static let compactPressScale: CGFloat = 0.955

        /// The curve for a press transition. Reduce Motion gets a plain symmetric ease instead of
        /// no feedback at all.
        static func press(isPressed: Bool, reduceMotion: Bool) -> SwiftUI.Animation {
            if reduceMotion { return .easeOut(duration: 0.12) }
            return isPressed ? pressDown : pressRelease
        }
    }
}

// MARK: - Haptics

/// Taptic feedback for app chrome (buttons, selections, confirmations). Separate from
/// `PadHaptics` in ControllerPad.swift: chrome wants a `.soft` tap, the pad wants `.rigid`
/// and must not pay any extra latency.
enum MuffinHaptics {
    /// Single switch for every chrome haptic; the pad is unaffected.
    static let isEnabled = true

    /// A control was pressed.
    static func tap() {
        guard isEnabled else { return }
        MuffinHapticEngine.shared.tap()
    }

    /// A value changed - a picker moved, a row was selected.
    static func select() {
        guard isEnabled else { return }
        MuffinHapticEngine.shared.select()
    }
}

/// Holder for the prepared generators. Same reasoning as PadHaptics: a generator built
/// fresh per event pays Taptic Engine spin-up latency on every single event, which
/// arrives as a haptic that lands after the animation it was meant to accompany.
private final class MuffinHapticEngine {
    static let shared = MuffinHapticEngine()

    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        impact.prepare()
        selection.prepare()
    }

    func tap() {
        impact.impactOccurred()
        impact.prepare()
    }

    func select() {
        selection.selectionChanged()
        selection.prepare()
    }
}

// MARK: - Elevation modifier

private struct MuffinElevationModifier: ViewModifier {
    let level: MuffinTheme.Elevation

    func body(content: Content) -> some View {
        let contact = level.contact
        let ambient = level.ambient
        // Classic UI: the single flat shadow at every level. Otherwise the contact shadow is
        // applied first so the ambient one is cast by the silhouette plus it.
        if UIStyle.isClassic {
            return AnyView(content.shadow(color: MuffinTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 4))
        }
        return AnyView(content
            .shadow(color: MuffinTheme.shadow.opacity(contact.opacity), radius: contact.radius, x: 0, y: contact.y)
            .shadow(color: MuffinTheme.shadow.opacity(ambient.opacity), radius: ambient.radius, x: 0, y: ambient.y))
    }
}

extension View {
    /// A solid navigation bar. On iOS 26 and later the bar has no background of its own and
    /// relies on the scroll edge blur, which CemuApp turns off app-wide, so titles and Done
    /// sat directly on whatever row or card scrolled under them. On earlier versions the bar
    /// is see-through at the top of the scroll, so on the gradient sheets the title and Done
    /// sat on the gradient (black on Neon Cyber's navy, system blue on Bakery's orange).
    /// Painted, not a material, so it adds no blur. Pass `MuffinTheme.formGround` on Form and
    /// List screens so the bar matches the rows' ground. iOS 15 keeps the system bar.
    @ViewBuilder func muffinOpaqueNavigationBar(_ fill: Color = MuffinTheme.cream) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(fill, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    /// Two-layer depth at the given level. See MuffinTheme.Elevation for why two.
    func muffinElevation(_ level: MuffinTheme.Elevation) -> some View {
        modifier(MuffinElevationModifier(level: level))
    }

    /// The app's standard screen ground: the current theme's background gradient,
    /// edge to edge behind the content.
    func muffinScreenBackground() -> some View {
        background(MuffinTheme.backgroundGradient.ignoresSafeArea())
    }

    // The five below pair a font with the colour it is always used with.

    /// 15 semibold rounded, darkest ink. The leading label of a row.
    func muffinRowLabel() -> some View {
        font(MuffinTheme.Font.rowLabel).foregroundColor(MuffinTheme.brownDarkest)
    }

    /// 15 rounded, mid ink. The trailing value on that row.
    func muffinRowValue() -> some View {
        font(MuffinTheme.Font.rowValue).foregroundColor(MuffinTheme.brownMid)
    }

    /// 17 semibold rounded, dark ink. A section header.
    func muffinSectionTitle() -> some View {
        font(MuffinTheme.Font.sectionTitle).foregroundColor(MuffinTheme.brownDark)
    }

    /// 13 rounded, mid ink. Empty-state copy and running captions.
    func muffinCaption() -> some View {
        font(MuffinTheme.Font.caption).foregroundColor(MuffinTheme.brownMid)
    }

    /// 12 plain, secondaryText. The explanatory line under a settings row: the system grey,
    /// held to 4.5:1 (`.secondary` is about 3.4:1 on a white row).
    func muffinSubCaption() -> some View {
        font(MuffinTheme.Font.subCaption).foregroundColor(MuffinTheme.secondaryText)
    }
}

/// A warm cream card with a soft rounded corner and gentle drop shadow: the base surface for
/// library cards, settings sections and picker rows. Draws a lighting pass over the fill
/// (`MuffinTheme.surfaceSheen`), a lit-top/shaded-bottom rim (`MuffinTheme.edgeStroke`) and
/// two-layer depth (`.muffinElevation`); a custom `fill` gets the same treatment.
struct MuffinCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var fill: Color = MuffinTheme.cream
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .background(fill.overlay(MuffinTheme.surfaceSheen))
            .clipShape(shape)
            // strokeBorder keeps the whole line inside the clip shape.
            .overlay(shape.strokeBorder(MuffinTheme.edgeStroke, lineWidth: 1))
            .muffinElevation(.resting)
    }
}

/// Rounded primary button (muffin-top gradient fill, cream text where cream reads on it -
/// see MuffinTheme.onMuffinTop).
///
/// Painted, not Liquid Glass: nothing here samples the backdrop, so it is safe over the live
/// Metal layer. It has a glint along the top edge (`controlSheen`), a rim that is lighter above
/// and deeper below (`controlEdgeStroke`) and two-layer depth (`muffinElevation`); the pressed
/// state is a colour swap rather than a `.brightness` filter.
struct MuffinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // A nested View is needed to read @Environment (Reduce Motion) from a ButtonStyle.
        StyleBody(configuration: configuration)
    }

    /// Named StyleBody, not Body: a nested `Body` collides with ButtonStyle's associated type.
    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: MuffinTheme.Radius.control, style: .continuous)
        }

        var body: some View {
            let pressed = configuration.isPressed
            // Classic UI: opaque muffin-top gradient, 14pt corner, one shadow, 0.97 scale.
            if UIStyle.isClassic {
                return AnyView(configuration.label
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(MuffinTheme.onMuffinTop)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MuffinTheme.muffinTopGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: pressed ? 2 : 6, x: 0, y: pressed ? 1 : 3)
                    .scaleEffect(pressed ? 0.97 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: pressed))
            }
            // Hoisted out of the modifier chain to keep type checking fast.
            let fill = (pressed ? MuffinTheme.muffinTopGradientPressed : MuffinTheme.muffinTopGradient)
                .overlay(MuffinTheme.controlSheen)
            return AnyView(configuration.label
                .font(MuffinTheme.Font.primaryButton)
                .foregroundColor(MuffinTheme.onMuffinTop)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fill)
                .clipShape(shape)
                .overlay(shape.strokeBorder(MuffinTheme.controlEdgeStroke, lineWidth: 1))
                // Pressing drops the elevation as well as scaling, so it reads as pushed in.
                .muffinElevation(pressed ? .flush : .raised)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(pressed ? MuffinTheme.Motion.pressScale : 1)
                .animation(MuffinTheme.Motion.press(isPressed: pressed, reduceMotion: reduceMotion), value: pressed)
                .onChange(of: pressed) { nowPressed in
                    if nowPressed { MuffinHaptics.tap() }
                })
        }
    }
}

/// Rounded pill button for secondary/chrome actions (cream fill, brown text). Every in-game
/// top-bar button uses it, so it is drawn over the live Metal drawable: only ordinary fills,
/// strokes and shadows (nothing that samples the backdrop), and `.resting` elevation rather
/// than a wide blur. The pressed state is a real pressed fill, a small scale and the
/// elevation dropping away, not a dim.
struct MuffinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    /// Named StyleBody, not Body (see MuffinPrimaryButtonStyle).
    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: MuffinTheme.Radius.chip, style: .continuous)
        }

        var body: some View {
            let pressed = configuration.isPressed
            // Classic UI: cream fill that dims to 0.7 on press, 12pt corner, flat 1pt outline.
            if UIStyle.isClassic {
                return AnyView(configuration.label
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MuffinTheme.cream.opacity(pressed ? 0.7 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MuffinTheme.wrapper, lineWidth: 1)))
            }
            let fill = (pressed ? MuffinTheme.creamPressed : MuffinTheme.cream)
                .overlay(MuffinTheme.controlSheen)
            return AnyView(configuration.label
                .font(MuffinTheme.Font.secondaryButton)
                .foregroundColor(MuffinTheme.brownDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(fill)
                .clipShape(shape)
                .overlay(shape.strokeBorder(MuffinTheme.edgeStroke, lineWidth: 1))
                .muffinElevation(pressed ? .flush : .resting)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(pressed ? MuffinTheme.Motion.compactPressScale : 1)
                .animation(MuffinTheme.Motion.press(isPressed: pressed, reduceMotion: reduceMotion), value: pressed)
                .onChange(of: pressed) { nowPressed in
                    if nowPressed { MuffinHaptics.tap() }
                })
        }
    }
}
