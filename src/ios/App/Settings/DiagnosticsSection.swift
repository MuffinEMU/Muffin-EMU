import SwiftUI
import UIKit

/// MuffinEMU installs on any arm64 iPhone or iPad running iOS 15 or later, and
/// almost none of those have ever run it. Every finding on this port so far - no
/// BC texture formats, no mesh shaders, the memory ceiling - depended on knowing
/// exactly which chip was under it, and a report from hardware nobody here owns is
/// unanswerable without that. One tap to copy is the difference between a bug
/// report that can be acted on and one that cannot. Its own section, above
/// Diagnostics, because it is the thing to send FIRST when something is wrong.
struct DeviceReportSection: View {
    @State private var deviceReportCopied = false
    /// Computed on demand. The bridge owns the string and it is stable for the
    /// process's lifetime, so there is nothing to refresh and nothing to invalidate.
    ///
    /// PlatformCapabilities.summary is appended rather than added to the bridge's own
    /// report because it answers a question the bridge cannot: the bridge knows the
    /// running OS, but only the Swift side knows which SDK this binary was compiled
    /// against, and "iOS 27 device, pre-27 SDK" is the single most likely reason for a
    /// report that a new-OS feature did nothing. Putting it in the copied text means it
    /// travels with every bug report instead of having to be asked for.
    private var deviceReport: String {
        String(cString: cemu_bridge_device_report())
            + "\n" + PlatformCapabilities.summary
            + "\nthermal: " + ThermalMonitor.shared.description
    }

    var body: some View {
        Section {
            Text(deviceReport)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
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
            // Already one short pair of sentences - nothing to move behind an info button.
            InfoButton.footer("Send this with any bug report. It says which chip, how much memory, and which build - which is what makes everything else in a log mean something.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Was ON by default while no Wii U title had been shown to boot - the log was not a
/// diagnostic sitting on top of the feature, it WAS the feature, and the only thing a
/// failed launch produced that was worth anything. Titles boot now (FAST Racing NEO
/// renders correctly, full speed, on real hardware), so that default started actively
/// working against the normal experience: it also gates the launch intro (see
/// ContentView.swift), so an ON-by-default log meant the intro silently never played on
/// a stock install, every single launch, with nothing in the UI explaining why. OFF by
/// default now; still one tap away for anyone chasing a black screen.
struct DiagnosticsSection: View {
    /// Shared with EmulatorViewOptimized by key, not by binding - the emulator view is
    /// not in this sheet's hierarchy, and AppStorage is what makes the setting outlive
    /// the sheet anyway.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = false
    @AppStorage("muffin.showLaunchIntro") private var launchIntroEnabled = true

    var body: some View {
        // Collection is always on regardless (see IOSLiveLog.h) - gating that too would
        // mean the toggle could only ever show the boot AFTER the one that failed.
        //
        // The intro is deliberately in the same section as the launch log and directly
        // above it, because they occupy the same screen at the same moment and turning
        // the log on hides the intro. Putting them apart would make that look like a bug.
        Section {
            Toggle(isOn: $launchIntroEnabled) {
                Label {
                    Text("Play the launch intro")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .tint(MuffinTheme.pixelBlue)

            Toggle(isOn: $showLaunchLog) {
                Label {
                    Text("Show launch log")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                } icon: {
                    Image(systemName: "text.alignleft")
                }
            }
            .tint(MuffinTheme.pixelBlue)
        } header: {
            SettingsSectionHeader("Diagnostics", icon: "stethoscope", accent: .system)
        } footer: {
            InfoButton.footer(
                "The launch log takes priority over the intro and shows what the emulator is doing during boot.",
                title: "Diagnostics",
                text: "The intro plays over the boot rather than before it, so it costs no extra waiting. The launch log takes priority when both are on: shows what the emulator is doing, with timestamps, while a game boots, which is what you want when a game starts but the screen stays black.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
