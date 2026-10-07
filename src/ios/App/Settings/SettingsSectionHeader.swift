// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// The accent families a Settings section header can belong to. A colour means "what kind of
/// section is this", so sections that do similar work share one. Every case resolves through
/// a MuffinTheme token, so a custom theme recolours the headers too.
enum SettingsSectionAccent {
    /// What decides whether a game runs at all - CPU, Graphics, shaders, clock.
    case core
    /// What the player touches and what reaches their senses - controls, display, audio.
    case io
    /// What the app holds on their behalf - library, keys, accounts, emulated hardware.
    case content
    /// Identity and the paid tier. The warmest accent, used the least.
    case identity
    /// Housekeeping: paths, device report, diagnostics, version. Deliberately quiet.
    case system
    /// The unfinished preview section. Orange marks it as a warning, not a family.
    case preview

    var color: Color {
        switch self {
        // Readable versions: these are glyphs on the grouped background, and several
        // themes' raw accents (a yellow pixelBlue, Galaxy's near-black muffin-top in dark
        // mode) didn't show against it.
        case .core: return MuffinTheme.accentText
        case .io: return MuffinTheme.readable(\.blueberryNavyLight, \.blueberryNavyDark)
        case .content: return MuffinTheme.readable(\.muffinTopDarkLight, \.muffinTopDarkDark)
        case .identity: return MuffinTheme.alertText
        case .system: return MuffinTheme.brownMid
        case .preview: return MuffinTheme.cautionText
        }
    }
}

/// Every Settings section header in the app. `.textCase(nil)` stops the grouped-list style
/// from uppercasing the title.
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
        // Classic UI: the plain `Text` header from v2.0, before the icon chips existed.
        if UIStyle.isClassic {
            Text(title)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        } else {
            modernHeader
        }
    }

    private var modernHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent.color)
                // A tinted chip gives the header a constant height regardless of glyph width.
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
