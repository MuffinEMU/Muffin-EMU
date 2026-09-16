import SwiftUI

/// LabeledContent needs iOS 16+; this project's deployment target is 15.0. Shared
/// across several Settings sections now that the Form is split into per-section
/// files, rather than re-declared privately in each one.
///
/// The label carries the app's row-label convention - 15pt semibold rounded, the same
/// face 39 hand-built rows across 12 section files already use. This was the one row
/// type still falling through to the system default, so read-only rows (Version,
/// Games, Keys loaded, shader cache sizes) rendered in a visibly different, lighter
/// typeface than the toggle and picker rows sitting directly above and below them.
struct SettingsRow: View {
    let label: String
    let value: String
    /// Optional leading glyph, brownMid so it supports the label rather than competing
    /// with the section header's accent chip.
    var icon: String? = nil

    var body: some View {
        // Classic UI: the v2.0 row - system font, no leading glyph, no height floor.
        // This row type was the one still falling through to the system default before
        // the 2026-09-15 pass, so "classic" here really is just the system default.
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
