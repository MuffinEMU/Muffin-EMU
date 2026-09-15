import SwiftUI

/// The accent families a Settings section header can belong to. Five, not twenty-two:
/// a header colour here means "what kind of thing is this section", so two sections
/// that do the same kind of work share a colour and the eye learns the grouping while
/// scrolling. Giving every section its own hue would be a rainbow, which reads as
/// decoration; giving every section the same hue throws away the only cheap signal a
/// 22-section Form has. Every case resolves through a real MuffinTheme token, so a
/// custom theme (see MuffinThemeStore) recolours the whole header system with it.
enum SettingsSectionAccent {
    /// What decides whether a game runs at all - CPU, Graphics, shaders, clock.
    case core
    /// What the player touches and what reaches their senses - controls, display, audio.
    case io
    /// What the app holds on their behalf - library, keys, accounts, emulated hardware.
    case content
    /// Identity and the paid tier. The warmest accent, used the least.
    case identity
    /// Housekeeping - paths, device report, diagnostics, version. Deliberately quiet:
    /// these sections should recede when someone is scanning for a setting to change.
    case system
    /// The one section that is not shipping-quality yet. Orange on purpose - it is a
    /// warning marker, not a family, and it is the only header that breaks the palette.
    case preview

    var color: Color {
        switch self {
        case .core: return MuffinTheme.pixelBlue
        case .io: return MuffinTheme.blueberryNavy
        case .content: return MuffinTheme.muffinTopDark
        case .identity: return MuffinTheme.blushPink
        case .system: return MuffinTheme.brownMid
        case .preview: return .orange
        }
    }
}

/// Every Settings section header in the app. Before this they were 22 plain `Text`
/// headers in two different idioms (`Section("X")` shorthand in four files, an
/// explicit `header:` closure in the rest), which meant a long Form scrolled past as
/// one undifferentiated grey list and the two idioms drifted apart whenever a section
/// was added.
///
/// `.textCase(nil)` is not decoration: SwiftUI's grouped-list style pushes an
/// uppercasing text case into the environment for section headers, and without this
/// the title would render as "ON-SCREEN CONTROLS" - which fights a rounded, warm
/// typeface rather than sitting in it.
struct SettingsSectionHeader: View {
    let title: String
    let icon: String
    var accent: SettingsSectionAccent = .core

    init(_ title: String, icon: String, accent: SettingsSectionAccent = .core) {
        self.title = title
        self.icon = icon
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent.color)
                // A tinted chip rather than a bare glyph: at 11pt a bare SF Symbol on a
                // grouped-list background reads as a speck, and the chip is what gives
                // the header a baseline height that stays constant whether the symbol is
                // wide ("antenna.radiowaves.left.and.right") or narrow ("key").
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent.color.opacity(0.16))
                )

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(MuffinTheme.brownDark)
                .textCase(nil)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
