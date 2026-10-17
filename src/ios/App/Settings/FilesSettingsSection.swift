// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

struct FilesSettingsSection: View {
    var body: some View {
        Section {
            Text(Self.documentsPathHint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MuffinTheme.secondaryText)
                .textSelection(.enabled)
        } header: {
            SettingsSectionHeader("Files", icon: "folder", accent: .system)
        } footer: {
            InfoButton.footer(
                "Game files, saves, shader caches and keys.txt are stored in this folder.",
                title: "Files",
                text: "Normally this is Files \u{2192} On My iPhone/iPad \u{2192} MuffinEMU. If you installed through LiveContainer, iOS lists the folder under LiveContainer instead; use the path shown above to find it.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    /// Computed live: only the OS knows where Documents resolved for this install (normal and
    /// sideloaded installs differ).
    private static var documentsPathHint: String {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "Couldn't find the Documents folder for this install."
        }
        return url.path
    }
}
