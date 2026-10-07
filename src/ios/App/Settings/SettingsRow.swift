// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// Read-only label/value row shared by the Settings sections (LabeledContent needs iOS 16+;
/// the deployment target is 15.0). The label uses the app's 15pt semibold rounded style.
struct SettingsRow: View {
    let label: String
    let value: String
    /// Optional leading glyph, brownMid so it supports the label rather than competing
    /// with the section header's accent chip.
    var icon: String? = nil

    var body: some View {
        // Classic UI: the v2.0 row - system font, no leading glyph, no height floor.
        if UIStyle.isClassic {
            HStack {
                Text(label)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } else {
            modernRow
        }
    }

    private var modernRow: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MuffinTheme.brownMid)
                    .frame(width: 20)
            }

            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(MuffinTheme.brownMid)
                .multilineTextAlignment(.trailing)
        }
        // Matches the height a Toggle or Picker row settles at, so a section mixing
        // read-only rows with controls scrolls at one rhythm instead of two.
        .frame(minHeight: 30)
    }
}

/// The label every destructive row in Settings wears - Remove keys.txt, Reset layout,
/// Clear everything, Remove DLC/Update/Custom Cover, Reset settings to defaults.
///
/// The explicit red is the point. `Button(role: .destructive)` tints itself, but every
/// one of these buttons sits inside a Section carrying
/// `.foregroundColor(MuffinTheme.brownDarkest)`, and that ancestor colour propagates
/// into the Label's own text and glyph - so the rows that delete things were rendering
/// in exactly the same warm brown as the rows that don't. Setting the colour on the
/// label itself puts the role's intent back on screen, where someone about to tap it
/// can see it.
struct DestructiveSettingsLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        // The explicit red survives Classic UI deliberately. It is not styling - it is
        // the one thing on screen telling someone this row deletes something, and it
        // only exists because the Section's own foregroundColor was swallowing the
        // destructive role's tint. v2.0 had that bug; reproducing a bug is not what
        // "classic look" means.
        if UIStyle.isClassic {
            Label(title, systemImage: systemImage)
                .foregroundColor(.red)
        } else {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.red)
        }
    }
}
