import SwiftUI

/// Where the help pages and the issue tracker live. Settings shows the two links near the top and again in About.
enum HelpLinks {
    static let docs = URL(string: "https://muffinemu.github.io/MuffinEMU/docs/")!
    static let reportProblem = URL(string: "https://github.com/MuffinEMU/Muffin-EMU/issues/new/choose")!
}

/// The two help rows, as About and the quick-help section at the top of Settings both show them.
struct HelpLinkRows: View {
    var body: some View {
        Link(destination: HelpLinks.docs) {
            Label("Help & troubleshooting", systemImage: "questionmark.circle")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        Link(destination: HelpLinks.reportProblem) {
            Label("Report a problem", systemImage: "exclamationmark.bubble")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }
}

/// Just under the Settings mode picker: the things a player reaches for when something is wrong.
struct QuickHelpSection: View {
    private let jit = JITStatus()

    var body: some View {
        Section {
            NavigationLink {
                SlowGameView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tortoise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MuffinTheme.brownMid)
                        .frame(width: 20)
                    Text("Game runs slowly?")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer(minLength: 12)
                    Text(jit.rowValue)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(jit.tint)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: 30)
            }
            Link(destination: HelpLinks.docs) {
                Label("Help & troubleshooting", systemImage: "questionmark.circle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Need help?", icon: "lifepreserver", accent: .system)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// "Game runs slowly?": whether the JIT is on, then Resolution, then Cool down, in the order they usually help.
struct SlowGameView: View {
    private let jit = JITStatus()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Recompiler (JIT)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(jit.rowValue)
                        .foregroundColor(jit.tint)
                }
                Text(jit.detail)
                    .font(.footnote)
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SettingsSectionHeader("1. Is the JIT on?", icon: "cpu", accent: .core)
            } footer: {
                InfoButton.footer("Games run much slower without a JIT enabler (StikJIT, SideStore or LiveContainer). Start MuffinEMU through one of them.")
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            Section {
                ResolutionPickerRows()
            } header: {
                SettingsSectionHeader("2. Lower the resolution", icon: "cube.transparent", accent: .core)
            } footer: {
                InfoButton.footer("Battery saver draws the fewest pixels. It's the quickest fix for a game that won't keep up.")
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            Section {
                CoolDownToggle()
            } header: {
                SettingsSectionHeader("3. Keep it cool", icon: "thermometer.medium", accent: .core)
            } footer: {
                InfoButton.footer("A hot device slows itself down. This lowers the picture for you when that starts to happen.")
            }
            .foregroundColor(MuffinTheme.brownDarkest)
        }
        .navigationTitle("Game runs slowly?")
        .muffinOpaqueNavigationBar(MuffinTheme.formGround)
        .navigationBarTitleDisplayMode(.inline)
    }
}
