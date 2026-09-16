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

    /// Same trait-adaptive provider as `init(light:dark:)`, but with a different alpha
    /// per appearance.
    ///
    /// This exists for the lighting passes below (`MuffinTheme.surfaceSheen` and
    /// friends), which are plain white and black at a low opacity rather than palette
    /// colours - and the opacity a lighting pass needs is not the same in both modes.
    /// A light card is already near-white, so a specular highlight on it has to be
    /// weak or it blows the top of the card out; a dark umber card needs a noticeably
    /// stronger one before the eye reads the surface as lit at all. `.opacity()` on a
    /// single Color cannot express that split, because it resolves once for both
    /// appearances - baking the alpha into the dynamic provider can.
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

/// Linear sRGB mix of two "#RRGGBB" strings, returned in the same form.
///
/// Every derived token in MuffinTheme goes through here rather than being written as a
/// new hex constant, and that is the whole point: there are thirty-one palettes in
/// MuffinThemePresets, all of them generated from real icon artwork, and a hand-picked
/// "edge highlight" hex would be correct for exactly one of them and wrong for the
/// other thirty. Deriving it instead means a rim light is always this theme's own
/// wrapper colour lifted, a pressed control is always this theme's own muffin-top
/// deepened, and a theme Void adds next year inherits the whole depth system for
/// free without touching this file.
///
/// Mixing in sRGB rather than a perceptual space on purpose. These are all small
/// nudges between two already-related colours, where sRGB and Oklab land within a
/// couple of levels of each other, and sRGB is what `Color(hex:)` above already
/// speaks - a perceptual round-trip here would be more machinery than the job needs.
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
///
/// Everything from `MARK: - Derived surface tokens` down is the newer layer: depth,
/// type, spacing, and motion, all derived from the fourteen palette tokens above them
/// rather than adding new palette colours. The split matters - the tokens above are
/// what a theme *is*, the ones below are how a surface made from them catches light.
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

    // MARK: - Derived surface tokens

    /// The lit top edge of a cream surface: this theme's own wrapper colour pulled
    /// most of the way to white in light mode, a third of the way in dark.
    ///
    /// The asymmetry is the point, and it is the single biggest difference between
    /// this and the flat 1pt outline it replaces. On a light ground a drop shadow does
    /// almost all the work of saying "this card is above the background", so the rim
    /// only has to be a whisper. On a dark ground a drop shadow is nearly invisible -
    /// Bakery's own shadowDark is #000000, and black-on-near-black is not a shadow,
    /// it's nothing - so in dark mode the rim light IS the elevation cue and has to
    /// carry the whole effect by itself. Same token, two different jobs.
    static var surfaceHighlight: Color {
        Color(light: muffinLift(t.wrapperLight, 0.70), dark: muffinLift(t.wrapperDark, 0.34))
    }

    /// The unlit bottom edge of a cream surface - the wrapper colour deepened, so the
    /// underside of a card falls away instead of being outlined like a sticker.
    static var surfaceShade: Color {
        Color(light: muffinDeepen(t.wrapperLight, 0.14), dark: muffinDeepen(t.wrapperDark, 0.40))
    }

    /// Top-to-bottom rim for cream surfaces: lit edge, the theme's real wrapper colour
    /// through the middle, unlit edge. Drawn with `.strokeBorder` rather than
    /// `.stroke` at every call site below so the hairline sits fully inside the
    /// clipped bounds instead of spilling half its width past the corner radius.
    static var edgeStroke: LinearGradient {
        // Classic UI: the flat 1pt wrapper outline v2.0's MuffinCard drew
        // (`.stroke(MuffinTheme.wrapper, lineWidth: 1)`), expressed as a gradient so the
        // call sites keep the same type and do not need a branch of their own.
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

    /// The same rim, for saturated muffin-top controls rather than cream surfaces.
    /// Derived from the muffin-top pair instead of the wrapper so a primary button's
    /// edge stays in its own colour family - a cream-derived rim on an orange button
    /// reads as a mismatched outline, not as light falling on orange.
    static var controlEdgeStroke: LinearGradient {
        // Classic UI: v2.0's secondary button drew a flat wrapper outline and its
        // primary drew none at all. Flat here covers both without the styles branching.
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

    /// The muffin-top gradient under a finger: both stops deepened by the same amount,
    /// so the hue and the internal contrast of the gradient are preserved and only its
    /// level drops.
    ///
    /// A derived fill rather than a `.brightness(-0.04)` filter on the rendered button,
    /// which is what an earlier draft of this file used. Two reasons, and the second is
    /// the one that matters. First, a filter dims the label and the rim along with the
    /// fill, so the text loses contrast at exactly the moment the user is looking at
    /// it. Second, `.brightness` is a render-effect modifier: it forces the button into
    /// an offscreen pass, and MuffinSecondaryButtonStyle below is what the in-game top
    /// bar is built from, which means that offscreen pass would sit directly on top of
    /// the emulator's live CAMetalLayer while a controls-responsiveness regression is
    /// still unexplained. Swapping a colour costs nothing and cannot be the cause of
    /// anything.
    static var muffinTopGradientPressed: LinearGradient {
        LinearGradient(
            colors: [
                Color(light: muffinDeepen(t.muffinTopLightLight, 0.10), dark: muffinDeepen(t.muffinTopLightDark, 0.10)),
                Color(light: muffinDeepen(t.muffinTopDarkLight, 0.10), dark: muffinDeepen(t.muffinTopDarkDark, 0.10))
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Cream under a finger. Deepened in light mode, lifted in dark - in both cases
    /// moving AWAY from the surrounding surface rather than in a fixed direction,
    /// which is the only way one token can read as "pressed" on both a near-white and
    /// a near-black card.
    static var creamPressed: Color {
        Color(light: muffinDeepen(t.creamLight, 0.07), dark: muffinLift(t.creamDark, 0.10))
    }

    /// A cream surface lifted a step - nested groups, the selected row in a list,
    /// anything that has to separate from the card it sits on without introducing a
    /// second colour. Mixed toward wrapper rather than toward white so it stays warm.
    static var surfaceRaised: Color {
        Color(light: muffinMixHex(t.creamLight, t.wrapperLight, 0.45),
              dark: muffinMixHex(t.creamDark, t.wrapperDark, 0.55))
    }

    /// A cream surface pushed a step back - the well a control sits in (track of a
    /// slider, the unfilled part of a progress bar, an inset field).
    static var surfaceSunken: Color {
        Color(light: muffinDeepen(muffinMixHex(t.creamLight, t.wrapperLight, 0.8), 0.04),
              dark: muffinDeepen(t.creamDark, 0.35))
    }

    /// Separator colour for rows inside a card. The wrapper colour carried a little
    /// way toward the mid-brown ink, because wrapper alone against cream is a colour
    /// change rather than a line - visible as a band, not readable as a division.
    static var hairline: Color {
        Color(light: muffinMixHex(t.wrapperLight, t.brownMidLight, 0.22),
              dark: muffinMixHex(t.wrapperDark, t.brownMidDark, 0.18))
    }

    /// One device pixel, not one point. A 1pt separator on a 3x screen is three pixels
    /// of solid ink and it is the difference between a list that looks drawn and a
    /// list that looks ruled - the single most recognisable "this was made by someone
    /// who cares" detail in an iOS list, and the cheapest.
    static var hairlineWidth: CGFloat {
        let scale = UITraitCollection.current.displayScale
        return scale > 0 ? 1.0 / scale : 0.5
    }

    /// Dimming layer behind a sheet or a modal. Deliberately the theme's own shadow
    /// colour rather than plain black, so a warm theme dims warm.
    static var scrim: Color {
        Color(light: t.shadowLight, lightAlpha: 0.26, dark: "#000000", darkAlpha: 0.48)
    }

    // MARK: - Lighting

    // The two gradients below are white and black at low alpha - the only place in
    // this file that is not a palette colour, and intentionally so. They are a light
    // source, not a pigment: a specular highlight down the top of a surface and an
    // ambient-occlusion falloff at the bottom, composited OVER whatever real palette
    // colour the surface is filled with. That is why they work on a cream card, an
    // orange button and a caller-supplied custom fill alike without any of them
    // needing a hand-authored gradient of their own, and why adding a theme never
    // needs a matching sheen added here.
    //
    // They are ordinary gradient fills drawn into the surface, not backdrop effects -
    // nothing here samples what is behind the view. That distinction is why these are
    // safe on the in-game chrome and interactive Liquid Glass was not: a fill is
    // rasterised once and reused until the view changes, while glass re-reads the
    // layer underneath it every frame.

    static var sheenHighlight: Color {
        Color(light: "#FFFFFF", lightAlpha: 0.32, dark: "#FFFFFF", darkAlpha: 0.075)
    }

    static var sheenOcclusion: Color {
        Color(light: "#000000", lightAlpha: 0.035, dark: "#000000", darkAlpha: 0.11)
    }

    /// Lighting pass for a large surface (cards, sheets). The highlight is spent in
    /// the top ~40% and the occlusion only starts in the bottom ~30%, leaving the
    /// middle completely untouched - a sheen that runs edge to edge reads as a
    /// gradient fill, which is exactly the look this is meant to avoid.
    static var surfaceSheen: LinearGradient {
        // The lighting pass IS the glassy part. It is a white/black alpha wash over the
        // real fill - not Apple's Liquid Glass material (there is no `.glassEffect` left
        // in this tree), but it is what still reads as "glassy" on a card, and so it is
        // what "Disable Liquid Glass" has to turn off to mean anything. A fully clear
        // gradient leaves the fill untouched and costs nothing to composite.
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

    /// Lighting pass for a small control (buttons, chips). Tighter than the surface
    /// version: on a 36pt-tall button a 40% highlight band is most of the control, so
    /// it is pulled in to the top third to stay a glint rather than a wash.
    static var controlSheen: LinearGradient {
        // Same reasoning as surfaceSheen: this glint is the glassy part of a button.
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

    /// How far off its ground a surface sits.
    ///
    /// Every level is TWO shadows, and that is the substance of this type rather than
    /// an implementation detail. A single mid-radius shadow - which is what this app
    /// had everywhere, `radius: 10, y: 4, opacity: 0.18` - has to be either tight
    /// enough to define the edge or wide enough to suggest a room, and it cannot be
    /// both, so it ends up neither and the result is the slightly-floaty look that
    /// reads as "made in SwiftUI" at a glance. Real light gives you two: a small
    /// near-opaque contact shadow that anchors the object to what it is resting on,
    /// and a wide faint ambient one cast by everything else in the room. Split them
    /// and a card looks placed instead of pasted.
    ///
    /// The two scale together but not at the same rate - as something lifts, the
    /// contact shadow stays small and fades while the ambient one grows and spreads,
    /// which is what actually reads as height.
    enum Elevation {
        /// No shadow at all. The pressed state of a button, or a surface that is
        /// genuinely flush with its ground.
        case flush
        /// A card at rest on the background. Also what the in-game chrome uses - see
        /// MuffinSecondaryButtonStyle for why that is deliberately restrained rather
        /// than the `.floating` the situation would otherwise call for.
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

    /// The app's type ramp, in one place.
    ///
    /// Before this, sizes were written inline at every call site as
    /// `.system(size: 15, weight: .semibold, design: .rounded)` and friends, which is
    /// how a codebase ends up with 14, 15 and 16pt row labels on three different
    /// screens and a UI-consistency audit to go and find them. The names below are the
    /// conventions that audit settled on, made checkable: a row label IS 15 semibold
    /// rounded, an empty-state caption IS 13 rounded, a Settings sub-caption IS 12 and
    /// deliberately NOT rounded (it pairs with `.secondary`, and rounded-plus-secondary
    /// at that size reads as blurry rather than quiet).
    ///
    /// `.rounded` stays on everything that carries voice. It is not decoration here -
    /// it is the same softness as the icon's own lettering, and switching the app to
    /// the default system face would read as more "professional" and would be wrong.
    ///
    /// Fixed sizes rather than Dynamic Type, matching exactly what these call sites
    /// render today. Several screens - the pad editor and the in-game overlay in
    /// particular - are laid out against measured control geometry that a scaled font
    /// would push apart, so moving the app onto `relativeTo:` metrics is a real piece
    /// of work with real layout consequences and not something to smuggle in under a
    /// typography cleanup. Deliberately left for its own pass.
    enum Font {
        /// Screen-owning titles.
        static var display: SwiftUI.Font { .system(size: 28, weight: .bold, design: .rounded) }
        /// Titles inside a screen, sheet headers.
        static var title: SwiftUI.Font { .system(size: 22, weight: .bold, design: .rounded) }
        /// Section headers in a Form or List.
        static var sectionTitle: SwiftUI.Font { .system(size: 17, weight: .semibold, design: .rounded) }
        /// The leading label of a settings row or a list item. The app's workhorse.
        static var rowLabel: SwiftUI.Font { .system(size: 15, weight: .semibold, design: .rounded) }
        /// The trailing value on that same row - same size, unemphasised.
        static var rowValue: SwiftUI.Font { .system(size: 15, design: .rounded) }
        /// Running text, and empty-state copy.
        static var caption: SwiftUI.Font { .system(size: 13, design: .rounded) }
        /// The explanatory line under a settings row. Not rounded - see above.
        static var subCaption: SwiftUI.Font { .system(size: 12) }
        /// Counts, badges, the smallest readable label.
        static var micro: SwiftUI.Font { .system(size: 11) }
        /// MuffinPrimaryButtonStyle's label.
        static var primaryButton: SwiftUI.Font { .system(size: 14, weight: .bold, design: .rounded) }
        /// MuffinSecondaryButtonStyle's label.
        static var secondaryButton: SwiftUI.Font { .system(size: 13, weight: .semibold, design: .rounded) }
        /// Version strings, title IDs, hashes - anything that must not be kerned into
        /// prose. Monospaced rather than rounded on purpose; it is data, not voice.
        static var monoTag: SwiftUI.Font { .system(size: 12, weight: .semibold, design: .monospaced) }
    }

    // MARK: - Spacing and shape

    /// Padding and gap sizes on a 4pt rhythm. The point is not that 12 is better than
    /// 13, it is that a screen built from six named steps has a rhythm and a screen
    /// built from whatever number looked right that afternoon does not.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let regular: CGFloat = 12
        static let comfy: CGFloat = 16
        static let loose: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// Corner radii. `card` is 18 to match MuffinCard's existing default exactly,
    /// `control` is 14 to match MuffinPrimaryButtonStyle's and `chip` is 12 to match
    /// MuffinSecondaryButtonStyle's - these name what the app already does rather than
    /// proposing new numbers, so adopting them is never a visual change. Every one of
    /// them is drawn `.continuous`; iOS's circular corner against a continuous one is
    /// the other instantly-recognisable tell.
    enum Radius {
        static let chip: CGFloat = 12
        static let control: CGFloat = 14
        static let card: CGFloat = 18
        static let sheet: CGFloat = 28
    }

    // MARK: - Motion

    /// Timing curves.
    ///
    /// The old press animation was `.easeOut(duration: 0.12)` in both directions, and
    /// symmetric press feedback is subtly wrong: a real button under a finger has no
    /// travel time going down - contact is instantaneous - and then springs back when
    /// released. Matching that is `press(isPressed:reduceMotion:)` below, which returns
    /// a very short ease on the way down and an underdamped spring on the way up. It is
    /// a few milliseconds of difference and it is most of why one app feels responsive
    /// and another feels laggy at identical frame rates.
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

        /// The curve for a press transition in the given direction.
        ///
        /// Reduce Motion gets a plain symmetric ease rather than nothing at all. The
        /// setting asks for no springs and no bounce; it does not ask for controls
        /// that give no feedback, and removing the response entirely would make the
        /// app less usable for exactly the people who turned it on.
        static func press(isPressed: Bool, reduceMotion: Bool) -> SwiftUI.Animation {
            if reduceMotion { return .easeOut(duration: 0.12) }
            return isPressed ? pressDown : pressRelease
        }
    }
}

// MARK: - Haptics

/// Taptic feedback for app chrome - buttons, selections, sheet confirmations.
///
/// Deliberately separate from `PadHaptics` in ControllerPad.swift rather than shared
/// with it, because the two have opposite requirements. The pad fires `.rigid` dozens
/// of times a second during play and is tuned to feel like a physical button under a
/// thumb. Chrome fires once when someone taps Save, and wants `.soft` - the same
/// weight iOS itself uses for UI confirmation. One generator serving both would have
/// to pick a style that is wrong for one of them, and re-`prepare()`ing a shared
/// generator between a game input and a UI tap would add latency to the pad, which is
/// the one place in this app where latency actually matters.
enum MuffinHaptics {
    /// Single switch for every chrome haptic in the app. Flip to `false` to silence
    /// the lot without touching a call site - the pad is unaffected either way.
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
        // Order matters: the contact shadow is applied first so the ambient one is
        // cast by the silhouette plus its contact shadow, which is what happens
        // physically. Reversed, the tight shadow gets drawn over the soft one and the
        // edge stops reading as anchored.
        // Classic UI: exactly the one shadow v2.0's MuffinCard had -
        // `.shadow(color: MuffinTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 4)` -
        // at every level. v2.0 had no elevation scale, so flattening all five levels to
        // its single value is the faithful answer rather than an approximation.
        if UIStyle.isClassic {
            return AnyView(content.shadow(color: MuffinTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 4))
        }
        return AnyView(content
            .shadow(color: MuffinTheme.shadow.opacity(contact.opacity), radius: contact.radius, x: 0, y: contact.y)
            .shadow(color: MuffinTheme.shadow.opacity(ambient.opacity), radius: ambient.radius, x: 0, y: ambient.y))
    }
}

extension View {
    /// Two-layer depth at the given level. See MuffinTheme.Elevation for why two.
    func muffinElevation(_ level: MuffinTheme.Elevation) -> some View {
        modifier(MuffinElevationModifier(level: level))
    }

    /// The app's standard screen ground: the current theme's background gradient,
    /// edge to edge behind the content.
    func muffinScreenBackground() -> some View {
        background(MuffinTheme.backgroundGradient.ignoresSafeArea())
    }

    // The five below pair a font with the colour that font is always used with, which
    // is the half of the convention a bare type scale cannot enforce. Nearly every
    // drift finding in the UI audit was a right-size/wrong-colour or right-colour/
    // wrong-size pair rather than a wholly invented style, so binding them together is
    // what actually stops the drift coming back.

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

    /// 12 plain, `.secondary`. The explanatory line under a settings row - system
    /// secondary rather than a MuffinTheme ink on purpose, because these sit inside a
    /// stock `Form` and have to agree with the rest of the system chrome around them.
    func muffinSubCaption() -> some View {
        font(MuffinTheme.Font.subCaption).foregroundColor(.secondary)
    }
}

/// A warm cream card with a soft rounded corner and gentle drop shadow - the base
/// surface for library cards, settings sections, and picker rows.
///
/// Renders three things the flat version did not: a lighting pass over the fill
/// (`MuffinTheme.surfaceSheen`), a rim that is lit at the top and shaded at the bottom
/// instead of a uniform outline (`MuffinTheme.edgeStroke`), and two-layer depth
/// (`.muffinElevation`). The API is unchanged - `cornerRadius` still defaults to 18
/// and `fill` still defaults to cream - so all five existing call sites in
/// IconPickerView, ThemePickerView and OnboardingView pick this up untouched, and a
/// caller passing a custom `fill` gets the lighting over their colour rather than
/// losing it.
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
            // strokeBorder, not stroke: stroke centres the line on the path and throws
            // half of it outside the shape, where the clipShape above has already cut
            // it off - so a 1pt "outline" draws as a ragged 0.5pt one that thins at
            // the corners. strokeBorder insets first and draws the whole line inside.
            .overlay(shape.strokeBorder(MuffinTheme.edgeStroke, lineWidth: 1))
            .muffinElevation(.resting)
    }
}

/// Rounded, friendly primary button (muffin-top gradient fill, cream text).
///
/// This deliberately does NOT use Liquid Glass on iOS 26+, and that is a revert, not
/// an oversight. `.glassEffect(.regular.tint(...).interactive(), ...)` was added here
/// at 2:16 PM on 2026-09-15 and is the only change in the 1:00-2:30 PM window that
/// can reach the controls: MuffinSecondaryButtonStyle below is what every in-game
/// top-bar button uses, so that change put live, interactive, refractive glass
/// directly over the emulator's own CAMetalLayer. Interactive glass re-samples and
/// re-composites whatever is behind it continuously, and what is behind it here is a
/// drawable being replaced every frame - a far better match for "buttons don't
/// register unless held ~1.5 seconds" (a render/main-thread stall, which delays every
/// touch equally) than anything in HeldControl's gesture code, which was read in full
/// and contains no timer, no minimumDuration, and no delay of any kind.
///
/// Not proven on device. It is the best-supported suspect in the window, reverted so
/// the symptom can be re-tested against a build that does not have it.
///
/// The painted rendering below is therefore not a fallback waiting to be replaced -
/// it is the only path, on every OS version, and it is built to be good at being
/// paint rather than to approximate glass. What paint on a lit surface actually has:
/// a glint along the top edge (`controlSheen`), a rim that is lighter above and
/// deeper below (`controlEdgeStroke`), and two-layer depth underneath
/// (`muffinElevation`). Nothing in it samples the backdrop, so none of it can do what
/// the reverted glass is suspected of doing - see the note on
/// `MuffinTheme.muffinTopGradientPressed` for why even the pressed state is a colour
/// swap rather than a `.brightness` filter.
struct MuffinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The press behaviour reads @Environment, and a ButtonStyle is not a View, so
        // it cannot hold environment values itself. Routing makeBody through a private
        // nested View is the standard way to get them - and it is what lets this style
        // honour Reduce Motion at all.
        StyleBody(configuration: configuration)
    }

    /// Named StyleBody, NOT Body. A nested type literally called `Body` is picked up by
    /// Swift's name-based associated-type inference as the witness for ButtonStyle's own
    /// `Body` associatedtype - and because this one is `private` while the style is
    /// internal, that fails with "struct 'Body' must be as accessible as its enclosing
    /// type", which reads as an access-control problem when it is really a name
    /// collision. makeBody already returns `some View`, so the witness should come from
    /// the opaque return type; any other name lets it.
    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: MuffinTheme.Radius.control, style: .continuous)
        }

        var body: some View {
            let pressed = configuration.isPressed
            // Classic UI: v2.0's primary button, exactly - opaque muffin-top gradient,
            // 14pt corner, one shadow that tightens on press, 0.97 scale, 0.12s easeOut.
            // No sheen, no rim, no two-layer elevation, because v2.0 had none of them.
            if UIStyle.isClassic {
                return AnyView(configuration.label
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(MuffinTheme.sparkleCream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MuffinTheme.muffinTopGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: pressed ? 2 : 6, x: 0, y: pressed ? 1 : 3)
                    .scaleEffect(pressed ? 0.97 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: pressed))
            }
            // Hoisted out of the modifier chain rather than written inline. SwiftUI's
            // type checker solves a view chain as one expression, and a chain this
            // long with four ternaries in it is exactly the shape that tips over into
            // "unable to type-check in reasonable time" - which is a build failure,
            // not a warning. Naming the sub-expressions costs nothing and removes the
            // risk entirely.
            let fill = (pressed ? MuffinTheme.muffinTopGradientPressed : MuffinTheme.muffinTopGradient)
                .overlay(MuffinTheme.controlSheen)
            return AnyView(configuration.label
                .font(MuffinTheme.Font.primaryButton)
                .foregroundColor(MuffinTheme.sparkleCream)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fill)
                .clipShape(shape)
                .overlay(shape.strokeBorder(MuffinTheme.controlEdgeStroke, lineWidth: 1))
                // Pressing DROPS the elevation rather than only scaling the button. A
                // control that shrinks while casting the same shadow reads as "moved
                // away from the viewer", which is not what a press is; losing the
                // shadow as it scales is what makes it read as pushed INTO the surface.
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

/// Rounded pill button for secondary/chrome actions (cream fill, brown text).
///
/// This is the style every in-game top-bar button (pause, save states, controller
/// switcher, hide-controls, swap, emulated devices) uses - i.e. the buttons that
/// float directly over the running emulator. That is exactly why the Liquid Glass
/// version of this style was reverted; see MuffinPrimaryButtonStyle above for the
/// full reasoning. Anything added here renders on top of a live Metal drawable, so
/// it is never "just cosmetic".
///
/// Which is why the polish here is the restrained kind. Everything this style draws
/// is an ordinary fill, stroke or drop shadow: all of them are rasterised from the
/// button's own content and cached until that content changes, and none of them reads
/// a single pixel of the drawable underneath. That is the whole distinction from the
/// reverted glass, and it is the test any future addition to this style has to pass.
///
/// It also takes `.resting` rather than the `.floating` that chrome over unpredictable
/// content would normally get. `.floating` means a 24pt blur radius, and a blur that
/// wide over a live drawable is precisely the class of thing worth not adding while a
/// controls-responsiveness regression is still unexplained. `.resting` separates the
/// button from the game perfectly well and costs a 9pt one.
///
/// The pressed state used to be `cream.opacity(0.7)`, which over game content made the
/// button go semi-transparent under the finger and read as disabled rather than
/// pressed - dimming is how iOS spells "unavailable". It presses the way the primary
/// style does now: a real pressed fill, a small scale, and the elevation dropping away.
struct MuffinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    /// Named StyleBody, NOT Body. A nested type literally called `Body` is picked up by
    /// Swift's name-based associated-type inference as the witness for ButtonStyle's own
    /// `Body` associatedtype - and because this one is `private` while the style is
    /// internal, that fails with "struct 'Body' must be as accessible as its enclosing
    /// type", which reads as an access-control problem when it is really a name
    /// collision. makeBody already returns `some View`, so the witness should come from
    /// the opaque return type; any other name lets it.
    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: MuffinTheme.Radius.chip, style: .continuous)
        }

        var body: some View {
            let pressed = configuration.isPressed
            // Classic UI: v2.0's secondary button, exactly - cream fill that dims to 0.7
            // on press, 12pt corner, flat 1pt wrapper outline, no shadow and no scale.
            // The dim-on-press is restored here even though the modern style deliberately
            // moved away from it (dimming reads as "disabled" over game content); this
            // switch exists to reproduce the old look, and that WAS the old look.
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
            // Hoisted for the same reason as in MuffinPrimaryButtonStyle above.
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
