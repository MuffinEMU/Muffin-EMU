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
                    .foregroundColor(MuffinTheme.sparkleCream)
            } else {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownMid)
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
            .foregroundColor(isMuted ? MuffinTheme.brownMid : MuffinTheme.sparkleCream)
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
            // Makes the whole capsule tappable inside a List row.
            .contentShape(Capsule())
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
