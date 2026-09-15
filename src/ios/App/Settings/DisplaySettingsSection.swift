import SwiftUI

/// Two related but genuinely different features share this section:
///
/// - Screen Layout (ScreenLayout in DisplayRouter.swift): how the TV and GamePad
///   screens share THIS device's own screen. Ported from MeloCafe, which already had
///   exactly this - Single Screen / Adaptive / GamePad-inset - and this app never did.
/// - External display routing (DisplayLayoutSettings in DisplayRouter.swift): which of
///   the two screens goes to a genuine SECOND physical display when one is connected.
///   Inert without one; the footer says so rather than hiding the controls, since a
///   control nobody can see failing silently reads as broken.
///
/// Screen Layout applies whenever there's no external display taking the TV; external
/// display routing only matters once one is attached. They cannot both be "in charge"
/// of the same screen at the same moment, which is why each gets its own swap button
/// with its own name, rather than trying to share one.
struct DisplaySettingsSection: View {
    // Matches MeloCafe's own SettingsView exactly: `= ScreenLayout.initialValue`, not a
    // plain constant, so a value migrated from a pre-ScreenLayout install (see
    // `ScreenLayout.initialValue`'s doc comment) is picked up the first time this row
    // ever reads the key, not just the first time EmulatorViewOptimized does.
    @AppStorage(LocalScreenLayoutSettings.layoutKey)
    private var screenLayout = ScreenLayout.initialValue
    @AppStorage(LocalScreenLayoutSettings.showSwapButtonKey)
    private var showLocalSwapButton = LocalScreenLayoutSettings.defaultShowSwapButton

    @AppStorage(ExternalDisplaySystemSettings.enabledKey)
    private var externalDisplaySystemEnabled = ExternalDisplaySystemSettings.defaultEnabled
    @AppStorage(DisplayLayoutSettings.swapKey)
    private var swapScreens = DisplayLayoutSettings.defaultSwap
    @AppStorage(DisplayLayoutSettings.showSwapButtonKey)
    private var showSwapButton = DisplayLayoutSettings.defaultShowSwapButton

    var body: some View {
        Section {
            HStack {
                Text("Screen Layout")
                Button {
                    // Same info-button-next-to-a-picker shape MeloCafe's own Settings
                    // row uses for this exact control.
                    screenLayoutInfoShown = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .foregroundColor(.secondary)
                .buttonStyle(.plain)

                Spacer()

                Picker("Screen Layout", selection: $screenLayout) {
                    ForEach(ScreenLayout.allCases) { layout in
                        Text(layout.string).tag(layout)
                    }
                }
                .pickerStyle(.menu)
                .tint(MuffinTheme.pixelBlue)
            }
            .alert("Screen Layout", isPresented: $screenLayoutInfoShown) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(screenLayout.description)
            }

            if screenLayout == .singleScreen {
                Toggle(isOn: $showLocalSwapButton) {
                    Text("Show Swap Button (TV ⇄ Pad)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .tint(MuffinTheme.pixelBlue)
            }

            Divider()

            Toggle(isOn: $externalDisplaySystemEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable External Display System")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Off by default. While off, the two settings below don't exist - MuffinEMU never looks for a second display, connected or not.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            // Same "re-route right now, not just next launch" reasoning as the two
            // toggles below - see reapplyForExternalDisplaySystemToggle's own doc
            // comment for why this direction needs it too, not just turning ON.
            .onChange(of: externalDisplaySystemEnabled) { _ in
                DisplayRouter.shared.reapplyForExternalDisplaySystemToggle()
            }

            if externalDisplaySystemEnabled {
                Toggle(isOn: $swapScreens) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("External display: which screen goes there")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(swapScreens
                             ? "GamePad screen on the external display, TV screen on this device."
                             : "TV screen on the external display, GamePad screen on this device.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .tint(MuffinTheme.pixelBlue)
                // Live, not just for the next launch: rerouteForScreenLayoutChange()
                // re-routes immediately if a title is already running in .dualScreen, the
                // same effect the on-screen swap button below has. Skip the router's own
                // UserDefaults write here - it would just be writing the value @AppStorage
                // already wrote - and only ask it to re-route.
                .onChange(of: swapScreens) { _ in
                    DisplayRouter.shared.rerouteForScreenLayoutChange()
                }

                Toggle(isOn: $showSwapButton) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show swap button (to external display)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("A small on-screen button while playing with an external display connected, so the setting above can be flipped without leaving the game.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .tint(MuffinTheme.pixelBlue)
            }
        } header: {
            Text("Display")
        } footer: {
            InfoButton.footer(
                "Screen Layout arranges the TV and GamePad on this device. External display routing is off until you turn it on above, and even then only takes effect with a second screen actually connected and this app given a window on it - plain AirPlay/screen mirroring doesn't count.",
                title: "Display",
                text: "The Wii U has two screens, the TV and the GamePad.\n\nScreen Layout decides how both share THIS device's screen: Single Screen shows one at a time with a swap button to switch; Adaptive shows both at once, stacked in portrait and side by side in landscape; the GamePad-top-right layout keeps the TV full size with a small GamePad inset.\n\n\"Enable External Display System\" is off by default - MuffinEMU never even checks for a second display until it's on, so plugging one in does nothing until you flip this. Once it's on, the two settings underneath only matter once a genuine second display is connected and this app has a window on it - the launch log says \"placement=dualScreen\" when that's active, and Screen Layout stands down in favour of it.\n\nDual-screen output to a real external display is new and has not been exercised on real hardware yet - if it doesn't behave as described, the launch log's placement line is the first thing to check.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @State private var screenLayoutInfoShown = false
}
