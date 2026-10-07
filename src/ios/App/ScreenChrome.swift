// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
#if os(iOS)
import UIKit
#endif

// Shared empty states, status callouts, badges and row-action styles for standalone screens
// (those reached from the library, the in-game top bar or Settings links). Everything uses
// MuffinTheme tokens, so it follows the selected theme and light/dark.

// MARK: - Empty states

/// The empty state for a list/grid screen with nothing to show: a symbol, a headline, a
/// caption, and optionally one primary action.
struct ScreenEmptyState: View {
    let systemImage: String
    let headline: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        // Classic UI: plain 13pt caption text; headline and body are still both shown.
        if UIStyle.isClassic {
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                    Text(message)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                }
                .fixedSize(horizontal: false, vertical: true)
            )
        }
        return AnyView(modernBody)
    }

    private var modernBody: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MuffinTheme.wrapper)
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(LegibleInk.ensure(MuffinTheme.pixelBlue, on: MuffinTheme.wrapper,
                                                       minimum: LegibleInk.glyph))
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            Text(headline)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(MuffinTheme.brownMid)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(MuffinPrimaryButtonStyle())
                .padding(.top, 2)
            }
        }
        // Width capped and centred so captions don't span a landscape iPad.
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Status callouts

/// A short result message with a symbol, shown after an action finishes or is refused. It
/// sits in place instead of interrupting like an alert.
struct ScreenStatusCallout: View {
    enum Tone {
        /// Something worked, or is simply informational.
        case info
        /// Something was refused or went wrong, but not badly enough for an alert.
        case warning

        var symbol: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        var accent: Color {
            switch self {
            case .info: return MuffinTheme.pixelBlue
            case .warning: return MuffinTheme.blushPink
            }
        }
    }

    let tone: Tone
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tone.accent)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Badges

/// The small leading marker on a slot row (save-state slot, emulated-device figure slot):
/// filled when the slot holds something, hollow when empty.
struct ScreenSlotBadge: View {
    let label: String
    let isFilled: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isFilled ? MuffinTheme.pixelBlue : MuffinTheme.wrapper)
            if isFilled {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(LegibleInk.on(MuffinTheme.pixelBlue, light: MuffinTheme.sparkleCream))
            } else {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(LegibleInk.ensure(MuffinTheme.brownMid, on: MuffinTheme.wrapper))
            }
        }
        .frame(width: 30, height: 30)
        // The row's own "Slot N" label already speaks the number.
        .accessibilityHidden(true)
    }
}

/// A short count/metadata chip - "3 games", "None" - for the trailing end of a row where
/// a second line of grey text would add height for very little information.
struct ScreenChip: View {
    let text: String
    var isMuted = true

    var body: some View {
        // Classic UI: a plain 11pt secondary caption line instead of a capsule.
        if UIStyle.isClassic {
            return AnyView(
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            )
        }
        return AnyView(modernBody)
    }

    private var modernBody: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(isMuted
                             ? LegibleInk.ensure(MuffinTheme.brownMid, on: MuffinTheme.wrapper)
                             : LegibleInk.on(MuffinTheme.pixelBlue, light: MuffinTheme.sparkleCream))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isMuted ? MuffinTheme.wrapper : MuffinTheme.pixelBlue)
            )
    }
}

// MARK: - Selection

/// Press response for selectable grid cards (used instead of `.buttonStyle(.plain)`, which
/// gives no feedback). Scales less than MuffinPrimaryButtonStyle because the cards are large.
struct ScreenCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A compact action button for inside a list row ("Load", "Clear", "Create"). The padding
/// makes the target somewhat larger than the text (about 30pt tall).
struct ScreenRowActionStyle: ButtonStyle {
    /// Destructive actions use the palette's "something is off" colour instead of system red.
    var isDestructive = false
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .screenRowActionChrome(isDestructive: isDestructive,
                                  isProminent: isProminent,
                                  isPressed: configuration.isPressed)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    /// The capsule an in-row action wears. Factored out so a NavigationLink or Menu, which
    /// don't reliably take a ButtonStyle, can share it.
    func screenRowActionChrome(isDestructive: Bool = false,
                              isProminent: Bool = false,
                              isPressed: Bool = false) -> some View {
        let foreground: Color = isProminent
            ? LegibleInk.on(MuffinTheme.pixelBlue, light: MuffinTheme.sparkleCream)
            : LegibleInk.ensure(isDestructive ? MuffinTheme.blushPink : MuffinTheme.pixelBlue,
                                on: MuffinTheme.wrapper)

        return self
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isProminent ? MuffinTheme.pixelBlue : MuffinTheme.wrapper)
                    .opacity(isPressed ? 0.65 : 1.0)
            )
            // Makes the whole capsule tappable inside a List row.
            .contentShape(Capsule())
    }
}

// MARK: - Contrast

/// Ink that stays readable on the colour it sits on.
///
/// Theme palettes are sampled from icon artwork, so a theme's accent can be a pale yellow or
/// a pastel exactly where text sits on it or inside it, and the controller skins put one
/// glyph colour on every button colour from navy to lemon. These resolve per appearance,
/// against the colours the current theme or skin actually produces, so every combination
/// reads without each preset having to be checked by hand. Both return dynamic colours, so
/// they follow light and dark mode like the theme tokens they are built from.
enum LegibleInk {
    /// WCAG AA: 4.5:1 for text, 3:1 for icons, glyphs and large bold text.
    static let text: CGFloat = 4.5
    static let glyph: CGFloat = 3.0

    /// `light` or `dark`, whichever reads better on `fill`. A translucent fill is judged
    /// over mid grey, which is what a game frame behind it averages out to.
    static func on(_ fill: Color, light: Color = .white, dark: Color = Color(white: 0.12)) -> Color {
        let fill = UIColor(fill), light = UIColor(light), dark = UIColor(dark)
        return Color(uiColor: UIColor { traits in
            let bg = opaque(fill.resolvedColor(with: traits))
            let l = light.resolvedColor(with: traits), d = dark.resolvedColor(with: traits)
            return contrast(l, bg) >= contrast(d, bg) ? l : d
        })
    }

    /// `ink` itself when it already reaches `minimum` against `background`. Otherwise `ink`
    /// moved toward black or white, whichever gets there sooner, and only as far as it
    /// takes, so the hue a theme or a colour file chose survives wherever it can.
    static func ensure(_ ink: Color, on background: Color, minimum: CGFloat = text) -> Color {
        let ink = UIColor(ink), background = UIColor(background)
        return Color(uiColor: UIColor { traits in
            adjusted(ink.resolvedColor(with: traits),
                     on: opaque(background.resolvedColor(with: traits)), minimum: minimum)
        })
    }

    static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func adjusted(_ ink: UIColor, on bg: UIColor, minimum: CGFloat) -> UIColor {
        if contrast(ink, bg) >= minimum { return ink }
        var best: (step: Int, colour: UIColor)?
        for target in [UIColor.black, UIColor.white] {
            for step in 1...20 {
                let candidate = mix(ink, target, CGFloat(step) / 20)
                if contrast(candidate, bg) >= minimum {
                    if step < (best?.step ?? .max) { best = (step, candidate) }
                    break
                }
            }
        }
        // Only reachable for a minimum beyond what black or white can do on this background.
        return best?.colour ?? (contrast(.white, bg) >= contrast(.black, bg) ? .white : .black)
    }

    private static func components(_ c: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if !c.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            if c.getWhite(&w, alpha: &a) { r = w; g = w; b = w }
        }
        func unit(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
        return (unit(r), unit(g), unit(b), unit(a))
    }

    private static func opaque(_ c: UIColor) -> UIColor {
        let x = components(c)
        guard x.a < 1 else { return c }
        let grey = 0.5 * (1 - x.a)
        return UIColor(red: x.r * x.a + grey, green: x.g * x.a + grey, blue: x.b * x.a + grey, alpha: 1)
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ k: CGFloat) -> UIColor {
        let x = components(a), y = components(b)
        return UIColor(red: x.r + (y.r - x.r) * k, green: x.g + (y.g - x.g) * k,
                       blue: x.b + (y.b - x.b) * k, alpha: x.a)
    }

    private static func luminance(_ c: UIColor) -> CGFloat {
        let x = components(c)
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return CGFloat(0.2126 * linear(x.r) + 0.7152 * linear(x.g) + 0.0722 * linear(x.b))
    }
}

// MARK: - Haptics

/// Haptics for genuine selection changes (theme or icon picks), never for ignored taps or
/// scrolling.
enum ScreenHaptics {
    static func selectionChanged() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// For a tap that deliberately did nothing, such as a locked Pro icon.
    static func rejected() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
