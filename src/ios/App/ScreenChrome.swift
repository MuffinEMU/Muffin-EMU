import SwiftUI
#if os(iOS)
import UIKit
#endif

// Shared chrome for the app's standalone screens - the ones reached from the library,
// the in-game top bar, or Settings' links, as opposed to the Settings form itself.
//
// WHY THIS FILE EXISTS
//
// Every screen here had already converged on the same design-system rules (see the row
// label / sub-caption / empty-state caption conventions repeated across
// GraphicPacksView, SaveStateView, EmulatedDevicesView and the pickers), but each one
// re-implemented the SHAPE of those rules by hand: an empty state was a lone sentence of
// brownMid text in a Section, a status message was an unadorned Text, a selectable card
// in a grid had no press response at all. The tokens matched; the treatment didn't.
//
// These types are the treatment, in one place. They deliberately keep the established
// fonts and colours rather than introducing new ones - an empty-state caption here is
// still .system(size: 13, design: .rounded) in brownMid, it just now sits under a symbol
// and a headline instead of floating alone in a list row.
//
// Nothing in here paints a colour that isn't a MuffinTheme token, so every one of these
// follows the selected theme and light/dark exactly like the rest of the app.

// MARK: - Empty states

/// The empty state every list/grid screen shows when it genuinely has nothing: a symbol,
/// a short headline, the explanatory caption, and - only where there is a single obvious
/// thing to do about it - one primary action.
///
/// `message` keeps the established empty-state caption styling rather than inventing a
/// new one, so a screen that previously showed just that sentence reads as the same
/// sentence, better framed.
struct ScreenEmptyState: View {
    let systemImage: String
    let headline: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MuffinTheme.wrapper)
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(MuffinTheme.pixelBlue)
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
        // Capped and centred rather than left to stretch: these run full-width inside a
        // List section or a ScrollView, and a centred three-line caption spanning a
        // landscape iPad reads as a paragraph nobody finished.
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Status callouts

/// A one-line-or-two result message with a symbol - what a screen says after an action
/// finished, succeeded, or was refused. Distinct from an error alert, which interrupts:
/// this sits in place and can be ignored.
struct ScreenStatusCallout: View {
    enum Tone {
        /// Something worked, or is simply informational.
        case info
        /// Something was refused or went wrong, but not badly enough to interrupt with an
        /// alert. blushPink is the palette's own "something is off" colour - see its use
        /// for error text in the onboarding pages and LaunchLogView's severity colouring.
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

/// The small leading marker on a slot row - a save-state slot, an emulated-device figure
/// slot. Filled in the accent when the slot holds something, hollow when it doesn't, so
/// occupancy is readable down the left edge of the list without reading a word of it.
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
                    .foregroundColor(MuffinTheme.sparkleCream)
            } else {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownMid)
            }
        }
        .frame(width: 30, height: 30)
        // The number is already read out by the row's own "Slot N" label; repeating it
        // here would make VoiceOver say it twice.
        .accessibilityHidden(true)
    }
}

/// A short count/metadata chip - "3 games", "None" - for the trailing end of a row where
/// a second line of grey text would add height for very little information.
struct ScreenChip: View {
    let text: String
    var isMuted = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(isMuted ? MuffinTheme.brownMid : MuffinTheme.sparkleCream)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isMuted ? MuffinTheme.wrapper : MuffinTheme.pixelBlue)
            )
    }
}

// MARK: - Selection

/// The press response every selectable card in a grid was missing. `.buttonStyle(.plain)`
/// - what ThemePickerView and IconPickerView both used - renders the label and nothing
/// else: no highlight, no scale, no indication a tap landed at all, which on a grid of
/// thirty icon tiles reads as an unresponsive screen rather than a fast one.
///
/// Deliberately quieter than MuffinPrimaryButtonStyle's 0.97: these cards are large, and
/// a large surface scaling the same amount as a small pill looks like it lurched.
struct ScreenCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A compact action button for inside a list row - "Load", "Clear", "Create".
///
/// The rows these replace used bare `.buttonStyle(.borderless)` at 12pt, which gives a
/// tap target the height of the text and nothing more; several of them sat 20pt apart in
/// a single HStack, well under the 44pt minimum, so the wrong one was easy to hit. This
/// keeps the compact look and pads the target out to something a thumb can actually
/// land on.
struct ScreenRowActionStyle: ButtonStyle {
    /// Destructive actions take the palette's own "something is off" colour rather than
    /// the system red, which reads as a foreign element on a cream surface.
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
    /// The capsule an in-row action wears. Factored out of ScreenRowActionStyle so a
    /// NavigationLink or a Menu - neither of which is a Button and neither of which
    /// reliably takes a ButtonStyle - can sit in the same row wearing the same chrome,
    /// instead of a styled pill next to a bare blue word.
    func screenRowActionChrome(isDestructive: Bool = false,
                              isProminent: Bool = false,
                              isPressed: Bool = false) -> some View {
        let foreground: Color = isProminent
            ? MuffinTheme.sparkleCream
            : (isDestructive ? MuffinTheme.blushPink : MuffinTheme.pixelBlue)

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
            // The capsule is the visual; this is the target. Without it only the glyph
            // and its padding are tappable, and a List row swallows the rest.
            .contentShape(Capsule())
    }
}

// MARK: - Haptics

/// The one thing that makes picking a theme or an icon feel like picking something rather
/// than like a redraw. Used only on genuine selection changes - never on a tap that was
/// ignored, and never on scrolling.
enum ScreenHaptics {
    static func selectionChanged() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// For a tap that deliberately did nothing - a locked Pro icon, for instance. A soft
    /// bump plus a visible explanation beats silence, which reads as a broken button.
    static func rejected() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
