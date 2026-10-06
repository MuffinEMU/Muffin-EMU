import SwiftUI

/// Basic / Advanced, at the very top of Settings. Basic hides the advanced rows and keeps those
/// settings at their defaults; switching back offers to bring the old values back. The switching
/// itself lives in AdvancedSettings.
struct SettingsModeSection: View {
    @AppStorage(SettingsMode.storageKey) private var modeRaw = SettingsMode.defaultValue.rawValue
    @State private var askRestore = false

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
                    askRestore = AdvancedSettings.hasSnapshot
                }
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
                     : "Only the settings most people need. The rest are off, at their defaults.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            InfoButton.footer(
                "Basic hides the advanced settings and puts them back to their defaults.",
                title: "Settings mode",
                text: "Basic keeps Settings short. The advanced settings are turned off, which means every one of them goes back to its default, and their rows are hidden.\n\nAdvanced shows all of them: the renderer, scaling filters, gamma, Steady frame rate, CPU cores and the other performance switches, the emulated clock, overlay details, motion tuning, stick feel, audio channels, diagnostics, and the extra options for each game.\n\nWhen you switch to Basic, MuffinEMU first saves what your advanced settings were. When you switch back to Advanced it asks whether to restore them or keep the defaults.\n\nReset settings to defaults (under About) also puts this back to Basic and forgets the saved values.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .alert("Restore your previous advanced settings?", isPresented: $askRestore) {
            Button("Restore") { AdvancedSettings.restoreSnapshot() }
            Button("Keep defaults", role: .cancel) { AdvancedSettings.discardSnapshot() }
        } message: {
            Text("They were saved when you switched to Basic. Keep defaults forgets them.")
        }
    }
}
