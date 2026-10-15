// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

private extension Bundle {
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

struct AboutSettingsSection: View {
    @State private var showingResetConfirmation = false
    @State private var resetMessage: String?

    var body: some View {
        Section {
            SettingsRow(label: "Version", value: Bundle.main.appVersionString, icon: "number")
            SettingsRow(label: "Created by", value: "Void", icon: "person.fill")
            Link(destination: URL(string: "https://github.com/MuffinEMU/Muffin-EMU")!) {
                Label("View on GitHub", systemImage: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Link(destination: URL(string: "https://muffinemu.github.io/MuffinEMU/docs/licenses.html")!) {
                Label("Open-source licences", systemImage: "doc.text")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Text("MuffinEMU is built on Cemu, and its core includes code from MeloCafe by stossy11. The optional Melo-Controller pad is also by stossy11.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)

            // GPL-3.0 section 5(d): the "Appropriate Legal Notices" every interactive interface must show.
            Text("© 2026 MuffinEMU Development Team (Void). MuffinEMU is free software: you can redistribute it under the GNU GPL 3.0 with the attribution terms in ATTRIBUTION.md, and its core under the MPL 2.0. It comes with no warranty. The licences are under Open-source licences above.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)

            // Resets the completion flag, which ContentView watches, so the guide reopens.
            SettingsOnboardingRow(onRequestReopen: {
                NotificationCenter.default.post(name: .muffinReopenOnboarding, object: nil)
            })

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                DestructiveSettingsLabel(title: "Reset settings to defaults", systemImage: "arrow.counterclockwise")
            }

            if let resetMessage {
                Text(resetMessage)
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        } header: {
            SettingsSectionHeader("About", icon: "info.circle", accent: .system)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .confirmationDialog("Reset settings to defaults?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset Settings", role: .destructive) {
                SettingsDefaults.reset(includingPerGameOverrides: false)
                resetMessage = "Settings reset to defaults."
            }
            Button("Reset Settings and Per-Game Options", role: .destructive) {
                SettingsDefaults.reset(includingPerGameOverrides: true)
                resetMessage = "Settings and per-game options reset to defaults."
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Puts every option in Settings back to its default, including controls, graphics, audio, overlay and appearance. Your library, favourites, keys.txt, accounts, theme, app icon and premium unlock are not affected. Per-game options stay unless you pick the second button.")
        }
    }
}
