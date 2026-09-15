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
            Link(destination: URL(string: "https://github.com/kiddreads/MuffinEMU")!) {
                Label("View on GitHub", systemImage: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Text("MuffinEMU is built on Cemu. Some MeloCafe cores and bug fixes have been brought over to MuffinEMU, and the optional melo-controls pad is Melo-Controller by stossy11.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)
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
            Text("This puts every emulation, graphics and control setting back to how MuffinEMU ships. Your library, favorites, keys.txt, theme, app icon and premium unlock are untouched, unless you pick the per-game option too.")
        }
    }
}
