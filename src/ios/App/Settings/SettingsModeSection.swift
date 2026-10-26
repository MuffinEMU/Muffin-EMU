// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Basic / Advanced, at the top of General. Basic hides the advanced rows and runs those settings at
/// their defaults; switching back to Advanced brings your own values back, with nothing to answer.
/// The switching itself lives in AdvancedSettings.
struct SettingsModeSection: View {
    @AppStorage(SettingsMode.storageKey) private var modeRaw = SettingsMode.defaultValue.rawValue
    /// Re-read after each switch, since it lives in AdvancedSettings' snapshot rather than a key here.
    @State private var pausedCount = AdvancedSettings.pausedCount

    private var choice: Binding<String> {
        Binding(
            get: { modeRaw },
            set: { newValue in
                guard newValue != modeRaw, let mode = SettingsMode(rawValue: newValue) else { return }
                modeRaw = newValue
                switch mode {
                case .basic:
                    AdvancedSettings.switchToBasic()
                case .advanced:
                    if AdvancedSettings.hasSnapshot { AdvancedSettings.restoreSnapshot() }
                }
                pausedCount = AdvancedSettings.pausedCount
            })
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings mode")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Picker("Settings mode", selection: choice) {
                    ForEach(SettingsMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(SettingsMode.isAdvanced(raw: modeRaw)
                     ? "Everything is shown, including the settings most people never need."
                     : "Only the settings most people need. The advanced ones run at their defaults until you switch back.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !SettingsMode.isAdvanced(raw: modeRaw) && pausedCount > 0 {
                    Label("\(pausedCount) advanced setting\(pausedCount == 1 ? " is" : "s are") paused. Switch to Advanced to bring \(pausedCount == 1 ? "it" : "them") back.",
                          systemImage: "pause.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MuffinTheme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            InfoButton.footer(
                "Basic hides the advanced settings and runs them at their defaults until you switch back.",
                title: "Settings mode",
                text: "Basic keeps Settings short. The advanced settings run at their defaults and their rows are hidden.\n\nAdvanced shows all of them: the renderer, scaling filters, gamma, Steady frame rate, CPU cores, when cooling down starts, the emulated clock, overlay details, stick feel, audio channels, diagnostics, and a game's own CPU cores, filters and Steady frame rate. The performance profile, motion aiming, library grouping and settings backups are in both.\n\nWhen you switch to Basic, MuffinEMU sets your advanced settings, and each game's, aside and uses the defaults. Switching back to Advanced puts them all back as they were.\n\nReset settings to defaults (under About) also puts this back to Basic and forgets the saved values.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onReceive(NotificationCenter.default.publisher(for: .muffinSettingsWereReset)) { _ in
            pausedCount = AdvancedSettings.pausedCount
        }
    }
}
