// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

struct FilesSettingsSection: View {
    var body: some View {
        Section {
            Text(Self.documentsPathHint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MuffinTheme.secondaryText)
                .textSelection(.enabled)
        } header: {
            SettingsSectionHeader("Your Files", icon: "folder", accent: .system)
        } footer: {
            InfoButton.footer(
                "ROMs, saves, shader caches and keys.txt live in this folder.",
                title: "Your Files",
                text: "Normally this is Files \u{2192} On My iPhone/iPad \u{2192} MuffinEMU. If you installed through LiveContainer, iOS lists the folder under LiveContainer instead; use the path shown above to find it.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    /// Computed live: only the OS knows where Documents resolved for this install (normal and
    /// sideloaded installs differ).
    private static var documentsPathHint: String {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "Could not resolve a Documents folder for this install."
        }
        return url.path
    }
}
