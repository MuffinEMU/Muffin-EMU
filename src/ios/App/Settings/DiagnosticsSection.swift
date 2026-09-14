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
    private var deviceReport: String { String(cString: cemu_bridge_device_report()) }

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
            Text("This Device")
        } footer: {
            // Already one short pair of sentences - nothing to move behind an info button.
            Text("Send this with any bug report. It says which chip, how much memory, and which build - which is what makes everything else in a log mean something.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// ON by default, which is the reverse of what shipping software should do, and
/// deliberate while this port is what it is. The release notes say it plainly: no
/// Wii U title has been shown to boot. Until one does, the log is not a diagnostic
/// sitting on top of the feature - it IS the feature, and the only thing a failed
/// launch produces that is worth anything.
///
/// The concrete reason it flipped: four builds went out asking for a boot log and
/// none came back, because seeing one first required knowing this toggle existed
/// and finding it. On screen it can just be screenshotted. Turn it off here once a
/// game actually boots.
struct DiagnosticsSection: View {
    /// Shared with EmulatorViewOptimized by key, not by binding - the emulator view is
    /// not in this sheet's hierarchy, and AppStorage is what makes the setting outlive
    /// the sheet anyway.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = true
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
                Label("Play the launch intro", systemImage: "sparkles")
            }
            .tint(MuffinTheme.pixelBlue)

            Toggle(isOn: $showLaunchLog) {
                Label("Show launch log", systemImage: "text.alignleft")
            }
            .tint(MuffinTheme.pixelBlue)
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("The intro plays over the boot rather than before it, so it costs no extra waiting. The launch log takes priority when both are on: shows what the emulator is doing, with timestamps, while a game boots, which is what you want when a game starts but the screen stays black.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
