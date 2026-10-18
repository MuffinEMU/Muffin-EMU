// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

// A card-based settings kit: grouped rounded cards holding a column of rows divided by hairline
// insets, under uppercased tracked headers. It gives Settings depth and a crisp, deliberate
// hierarchy instead of flat full-width system rows. On Liquid Glass each card is a glass card
// (rim + lift through muffinGlassSurface); below iOS 26 it is the painted cream MuffinCard look.
// This is MuffinEMU's own design, drawn in MuffinTheme tokens.

/// A rounded card holding a column of rows. Pass rows and `MuffinCardDivider`s as content.
struct MuffinGroupCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .muffinGlassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A hairline divider between two rows in a card, inset so it starts past the icon column.
struct MuffinCardDivider: View {
    var inset: CGFloat = 58
    var body: some View {
        Rectangle()
            .fill(MuffinTheme.edgeStroke)
            .frame(height: 1)
            .padding(.leading, inset)
            .padding(.trailing, 16)
    }
}

/// An uppercased, letter-spaced group header above a card.
struct MuffinGroupHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundColor(MuffinGlass.secondaryInk(MuffinTheme.brownMid))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A generous row for a card: a glass icon chip, the title and optional subtitle, and a trailing
/// control (a value, a toggle, or a chevron). Keep the vertical rhythm roomy — this is the "more
/// depth, less one-liner" row.
struct MuffinCardRow<Trailing: View>: View {
    var icon: String?
    var accent: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(icon: String? = nil,
         accent: Color = MuffinTheme.accentText,
         title: String,
         subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.accent = accent
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 13) {
            if let icon {
                MuffinGlassIconChip(systemName: icon, accent: accent, size: 32, cornerRadius: 9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinGlass.ink(MuffinTheme.brownDarkest))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(MuffinGlass.secondaryInk(MuffinTheme.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// The trailing chevron for a row that pushes to another page.
struct MuffinRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(MuffinGlass.secondaryInk(MuffinTheme.brownMid))
    }
}

/// A plain trailing value label for a row (version string, "Void", etc.).
struct MuffinRowValue: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 15, design: .rounded))
            .foregroundColor(MuffinGlass.secondaryInk(MuffinTheme.brownMid))
    }
}
