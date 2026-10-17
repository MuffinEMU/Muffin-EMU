// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import UIKit

/// One-tap copy of everything a bug report needs: the device, the main settings, the engine's last
/// status and the tail of the launch log (BugReport.swift), plus the device line on its own and the
/// log files for the share sheet. Its own section above Diagnostics because it is the first thing to
/// send when something is wrong.
struct DeviceReportSection: View {
    @State private var deviceReportCopied = false
    @State private var bugReportCopied = false
    /// Computed on demand. PlatformCapabilities.summary is appended because only the Swift side
    /// knows which SDK this binary was built against. @MainActor because ThermalMonitor and
    /// HeatStatus are main-actor isolated.
    @MainActor
    private var deviceReport: String {
        String(cString: cemu_bridge_device_report())
            + "\n" + PlatformCapabilities.summary
            + "\nthermal: " + ThermalMonitor.shared.description
            + " · heat " + HeatStatus.band.word
            + (HeatStatus.temperatureCelsius.map { String(format: " (battery %.0f C)", $0) } ?? " (no sensor reading)")
    }

    /// ShareLink where it exists (iOS 16 and later), the same share sheet through UIKit before that.
    @ViewBuilder private var shareLogsButton: some View {
        let files = BugReport.logFiles
        if !files.isEmpty {
            if #available(iOS 16.0, *) {
                ShareLink(items: files) { Label("Share log files", systemImage: "square.and.arrow.up") }
            } else {
                Button { DocumentImport.presentShare(files) } label: { Label("Share log files", systemImage: "square.and.arrow.up") }
            }
        }
    }

    var body: some View {
        Section {
            Button {
                UIPasteboard.general.string = BugReport.text(game: nil)
                bugReportCopied = true
            } label: {
                Label(bugReportCopied ? "Copied" : "Copy bug report",
                      systemImage: bugReportCopied ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Text("Your device, your main settings, what the engine last reported and the end of the launch log, as one text to paste into a message or a GitHub issue. No account names or files.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            shareLogsButton

            Text(deviceReport)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = deviceReport
                deviceReportCopied = true
            } label: {
                Label(deviceReportCopied ? "Copied" : "Copy device report only",
                      systemImage: deviceReportCopied ? "checkmark" : "doc.on.doc")
            }
        } header: {
            SettingsSectionHeader("Report a problem", icon: "iphone", accent: .system)
        } footer: {
            InfoButton.footer("Copy bug report gathers what a helper asks for first. Share log files sends the full logs.",
                title: "Report a problem",
                text: "Copy bug report puts one text on the clipboard: your device (chip, memory, app build), the settings that decide how games run (CPU mode, JIT, renderer, resolution), the game you last started, what the engine last reported and the last lines of the launch log. Paste it into your message when you ask for help. While a game is running, the HOME menu has the same row.\n\nShare log files sends the engine's full log.txt and the crash log, for the cases where the short report isn't enough.\n\nThe launch log is always collected; Show launch log under Diagnostics only decides whether it is drawn over the screen while a game starts.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// The first things to try, in the order a helper would ask about them. Each line names the page the
/// fix is on, so a new player can go there without knowing the app yet.
struct TroubleshootingSection: View {
    private struct Step: Identifiable {
        let id: Int
        let symptom: String
        let fix: String
    }

    private let steps: [Step] = [
        Step(id: 0, symptom: "An encrypted game won't start.",
             fix: "It needs the keys.txt dumped from your own Wii U. Add it under Games and library > Wii U keys, or from the game's page."),
        Step(id: 1, symptom: "Games run slowly.",
             fix: "Check JIT under Performance and graphics > JIT. Without a JIT enabler attached, MuffinEMU runs the slower interpreter. The library shows a line while JIT is off."),
        Step(id: 2, symptom: "A game glitches, desyncs or crashes.",
             fix: "Turn on Favour accuracy for that game (its page > Game settings) or for every game under Performance and graphics > CPU (Advanced mode), and try one core."),
        Step(id: 3, symptom: "The screen stays black after the game starts.",
             fix: "Turn on Show launch log under Help > Diagnostics (Advanced mode) and start the game again: the log shows how far it got. Try the other renderer under Performance and graphics > Graphics (Advanced mode)."),
        Step(id: 4, symptom: "MuffinEMU closes while a game loads.",
             fix: "It ran out of memory. Close other apps, lower the resolution under Performance and graphics > Graphics, and restart the device if it keeps happening."),
        Step(id: 5, symptom: "Buttons don't reach the game.",
             fix: "Turn on Show button press readout under Help > Diagnostics (Advanced mode); it says whether presses arrive and why not. Reset the controller bindings under Controls > On-screen controls."),
    ]

    var body: some View {
        Section {
            ForEach(steps) { step in
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.symptom)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(step.fix)
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        } header: {
            SettingsSectionHeader("Game won't start?", icon: "questionmark.circle", accent: .system)
        } footer: {
            Text("Still stuck? Copy bug report below (or in the HOME menu while the game runs) and paste it when you ask for help.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Launch intro, launch log and controls diagnostic toggles. The launch log is off by default
/// and, while on, replaces the launch intro (see ContentView.swift).
struct DiagnosticsSection: View {
    /// Shared with EmulatorViewOptimized by key; that view isn't in this sheet's hierarchy.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = false
    @AppStorage("muffin.showLaunchIntro") private var launchIntroEnabled = true
    @AppStorage(PadDiagnostics.enabledKey) private var padOverlayEnabled = PadDiagnostics.defaultEnabled
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    var body: some View {
        // Log collection is always on (see IOSLiveLog.h). The intro sits directly above the log
        // toggle because turning the log on hides the intro.
        Section {
            Toggle(isOn: $launchIntroEnabled) {
                Label {
                    Text("Play the launch intro")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .tint(MuffinTheme.accentText)

            // The log and the controls readout are Advanced mode only (see AdvancedSettings).
            if advanced {
                Toggle(isOn: $showLaunchLog) {
                    Label {
                        Text("Show launch log")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    } icon: {
                        Image(systemName: "text.alignleft")
                    }
                }
                .tint(MuffinTheme.accentText)

                Toggle(isOn: $padOverlayEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show button press readout")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Shows a small readout over the game of whether button presses reach it, and why not if they don't.")
                                .font(.system(size: 12))
                                .foregroundColor(MuffinTheme.secondaryText)
                        }
                    } icon: {
                        Image(systemName: "gamecontroller.badge.exclamationmark")
                    }
                }
                .tint(MuffinTheme.accentText)
            }
        } header: {
            SettingsSectionHeader("Diagnostics", icon: "stethoscope", accent: .system)
        } footer: {
            InfoButton.footer(
                // Show launch log is Advanced mode only, so Basic doesn't describe it.
                advanced ? "The launch log shows boot progress and replaces the intro while it's on." : "The intro plays while a game starts.",
                title: "Diagnostics",
                text: "The intro plays when a game starts. If you turn on the launch log, it shows boot steps with timestamps instead. That helps when a game starts but stays black.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
