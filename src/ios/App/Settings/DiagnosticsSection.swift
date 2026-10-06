import SwiftUI
import UIKit

/// One-tap copy of the chip, memory and build details a bug report needs. Its own section
/// above Diagnostics because it is the first thing to send when something is wrong.
struct DeviceReportSection: View {
    @State private var deviceReportCopied = false
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

    var body: some View {
        Section {
            Text(deviceReport)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = deviceReport
                deviceReportCopied = true
            } label: {
                Label(deviceReportCopied ? "Copied" : "Copy device report",
                      systemImage: deviceReportCopied ? "checkmark" : "doc.on.doc")
            }
        } header: {
            SettingsSectionHeader("This Device", icon: "iphone", accent: .system)
        } footer: {
            InfoButton.footer("Tap Copy device report, then paste it into a report from Settings > About > Report a problem. It lists your chip, memory and app build.")
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
                            Text("Show controls diagnostic")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("A small readout over the game showing whether your button presses are reaching the game, and why not if they aren't.")
                                .font(.caption)
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
                "The launch log shows boot progress and replaces the intro while it's on.",
                title: "Diagnostics",
                text: "The intro plays during the boot. If you turn on the launch log it takes the screen instead, so you can see timestamped boot steps when a game starts but stays black.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
