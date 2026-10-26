// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// A second physical display (DisplayLayoutSettings in DisplayRouter.swift): which Wii U screen goes to
/// it and what this device shows beside it. Inert without one. Its own section, so its swap button isn't
/// confused with Single Screen's under Display. The HOME menu's External display page holds the same
/// settings.
struct ExternalDisplaySettingsSection: View {
    @AppStorage(ExternalDisplaySystemSettings.enabledKey)
    private var externalDisplaySystemEnabled = ExternalDisplaySystemSettings.defaultEnabled
    @AppStorage(DisplayLayoutSettings.swapKey)
    private var swapScreens = DisplayLayoutSettings.defaultSwap
    @AppStorage(DisplayLayoutSettings.showSwapButtonKey)
    private var showSwapButton = DisplayLayoutSettings.defaultShowSwapButton
    @AppStorage(DisplayLayoutSettings.deviceShowsKey)
    private var deviceShows = DisplayLayoutSettings.defaultDeviceShows

    var body: some View {
        Section {
            Toggle(isOn: $externalDisplaySystemEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use an external display")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Experimental. Turn it on before connecting a second screen.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            // Re-routes immediately, both when turned on and when turned off.
            .onChange(of: externalDisplaySystemEnabled) { _ in
                DisplayRouter.shared.reapplyForExternalDisplaySystemToggle()
            }

            if externalDisplaySystemEnabled {
                Toggle(isOn: $swapScreens) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GamePad screen on the external display")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(swapScreens
                             ? "On: the external display shows the GamePad screen.".localized
                             : "Off: the external display shows the TV screen.".localized)
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
                // Re-routes immediately if a title is already running in .dualScreen.
                .onChange(of: swapScreens) { _ in
                    DisplayRouter.shared.rerouteForScreenLayoutChange()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("When a TV is connected, this device shows")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Picker("When a TV is connected, this device shows", selection: $deviceShows) {
                            ForEach(DeviceScreenMode.allCases) { mode in
                                Text(mode.string).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(MuffinTheme.accentText)
                    }
                    Text(deviceShowsCaption)
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
                // Applies at once in a running game; with none running it is used the next time a game starts.
                .onChange(of: deviceShows) { _ in
                    DisplayRouter.shared.rerouteForScreenLayoutChange()
                }

                Toggle(isOn: $showSwapButton) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show swap button during play")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("A small button over the game while an external display is connected, to flip the setting above without leaving the game.")
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
            }
        } header: {
            SettingsSectionHeader("External Display".localized, icon: "tv", accent: .io)
        } footer: {
            InfoButton.footer(
                "Off until you turn it on. It needs a second screen that MuffinEMU can open a window on; AirPlay mirroring doesn't count.".localized,
                title: "External Display".localized,
                text: "The external display is off by default; turn it on before connecting a display. Then choose which Wii U screen it shows, and what this device shows next to it: the other screen, the same screen, or only the controls. It is experimental and hasn't been tested on much hardware.\n\nThe HOME menu has the same settings during a game.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    /// What the choice above does with the swap setting as it is now.
    private var deviceShowsCaption: String {
        let tvScreen = swapScreens ? "GamePad screen".localized : "TV screen".localized
        let otherScreen = swapScreens ? "TV screen".localized : "GamePad screen".localized
        switch deviceShows {
        case .otherScreen:
            return String(format: "The external display shows the %@ and this device shows the %@.".localized, tvScreen, otherScreen)
        case .sameScreen:
            return String(format: "Both show the %@.".localized, tvScreen)
        case .nothing:
            return String(format: "The external display shows the %@. This device shows only the on-screen controls on black.".localized, tvScreen)
        }
    }
}
