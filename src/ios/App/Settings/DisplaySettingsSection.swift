import SwiftUI

/// Wii U TV/GamePad screen routing when a genuine second display is connected - see
/// DisplayRouter.swift for the mechanism (.dualScreen placement) and why plain AirPlay/
/// screen mirroring doesn't count. Both settings here are inert without one connected;
/// the footer says so plainly rather than hiding the section, since a control nobody
/// can see failing silently reads as broken.
struct DisplaySettingsSection: View {
    @AppStorage(DisplayLayoutSettings.swapKey)
    private var swapScreens = DisplayLayoutSettings.defaultSwap
    @AppStorage(DisplayLayoutSettings.showSwapButtonKey)
    private var showSwapButton = DisplayLayoutSettings.defaultShowSwapButton

    var body: some View {
        Section {
            Toggle(isOn: $swapScreens) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen layout")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(swapScreens
                         ? "GamePad screen on the external display, TV screen on this device."
                         : "TV screen on the external display, GamePad screen on this device.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            // Live, not just for the next launch: DisplayRouter.toggleScreenLayout()
            // re-routes immediately if a title is already running in .dualScreen, the
            // same effect the on-screen swap button has. Skip the router's own
            // UserDefaults write here - it would just be writing the value @AppStorage
            // already wrote - and only ask it to re-route.
            .onChange(of: swapScreens) { _ in
                DisplayRouter.shared.rerouteForScreenLayoutChange()
            }

            Toggle(isOn: $showSwapButton) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show swap button (TV ⇄ Pad)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("A small on-screen button while playing with an external display connected, so the screen layout above can be flipped without leaving the game.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
        } header: {
            Text("External Display")
        } footer: {
            InfoButton.footer(
                "Only takes effect with a second screen actually connected and this app given a window on it - plain AirPlay/screen mirroring doesn't count.",
                title: "External Display",
                text: "The Wii U has two screens, the TV and the GamePad. MuffinEMU can only show both at once with a genuine second display connected, not mirroring - the launch log says \"placement=dualScreen\" when that's active. Otherwise the GamePad screen isn't rendered at all, and these settings have nothing to act on yet.\n\nScreen layout picks which of the two goes to the external display and which stays on this device. The swap button repeats that choice as a button on screen during play, so it can be changed without leaving the game.\n\nDual-screen output is new and has not been exercised on real hardware yet - if it doesn't behave as described, the launch log's placement line is the first thing to check.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
