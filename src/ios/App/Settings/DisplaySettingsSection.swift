import SwiftUI

/// Two features share this section:
///
/// - Screen Layout (ScreenLayout in DisplayRouter.swift): how the TV and GamePad screens
///   share this device's own screen (Single Screen / Adaptive / GamePad top right).
/// - External display routing (DisplayLayoutSettings in DisplayRouter.swift): which screen
///   goes to a second physical display when one is connected. Inert without one.
///
/// Screen Layout applies whenever no external display is taking the TV; each mode has its
/// own swap button.
struct DisplaySettingsSection: View {
    // Initialised from `ScreenLayout.initialValue` so a value migrated from an older install is
    // picked up the first time this row reads the key.
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
                // The row's own Text is the label; a menu picker in a Form row prints its label as well.
                .labelsHidden()
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
                    Text("Off by default. Turn it on before connecting a second display.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            // Re-routes immediately, both when turned on and when turned off.
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
                // Re-routes immediately if a title is already running in .dualScreen.
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
            SettingsSectionHeader("Display", icon: "rectangle.on.rectangle", accent: .io)
        } footer: {
            InfoButton.footer(
                "Screen Layout arranges the TV and GamePad on this device. External display output is off until you enable it, and needs a second screen that MuffinEMU can open a window on; AirPlay mirroring doesn't count.",
                title: "Display",
                text: "The Wii U has two screens: the TV and the GamePad.\n\nScreen Layout: Single Screen shows one at a time with a swap button; Adaptive shows both, stacked in portrait and side by side in landscape; Both Screens (GamePad Top Right) keeps the TV full size with a small GamePad inset.\n\nExternal display output is off by default; turn it on before connecting a display. It is experimental and hasn't been tested on much hardware.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @State private var screenLayoutInfoShown = false
}
