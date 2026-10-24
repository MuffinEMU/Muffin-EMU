// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// This device's own screen: Screen Layout (ScreenLayout in DisplayRouter.swift), how the TV and
/// GamePad screens share it (Single Screen / Adaptive / GamePad top right), plus portrait and
/// brightness. A second physical display has its own section (ExternalDisplaySettingsSection).
///
/// Screen Layout applies whenever no external display is taking the TV.
struct DisplaySettingsSection: View {
    // Initialised from `ScreenLayout.initialValue` so a value migrated from an older install is
    // picked up the first time this row reads the key.
    @AppStorage(LocalScreenLayoutSettings.layoutKey)
    private var screenLayout = ScreenLayout.initialValue
    @AppStorage(LocalScreenLayoutSettings.showSwapButtonKey)
    private var showLocalSwapButton = LocalScreenLayoutSettings.defaultShowSwapButton
    @AppStorage(HiddenScreenSettings.pauseHiddenTVKey)
    private var pauseHiddenTV = false
    @AppStorage(HiddenScreenSettings.pauseHiddenPadKey)
    private var pauseHiddenPad = false

    // Read by OrientationPolicy each time UIKit asks which way the app may turn, so there is nothing to push.
    @AppStorage(OrientationPolicy.allowPortraitKey)
    private var allowPortrait = OrientationPolicy.defaultAllowPortrait

    @AppStorage(BrightnessBoost.key)
    private var brightnessBoost = BrightnessBoost.defaultValue
    @AppStorage(ScreenBrightness.maxWhilePlayingKey)
    private var maxBrightnessWhilePlaying = ScreenBrightness.defaultMaxWhilePlaying

    var body: some View {
        Section {
            HStack {
                Text("Screen layout")
                Button {
                    screenLayoutInfoShown = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .accessibilityLabel("About screen layout")

                Spacer()

                Picker("Screen layout", selection: $screenLayout) {
                    ForEach(ScreenLayout.allCases) { layout in
                        Text(layout.string).tag(layout)
                    }
                }
                .pickerStyle(.menu)
                // The row's own Text is the label; a menu picker in a Form row prints its label as well.
                .labelsHidden()
                .tint(MuffinTheme.accentText)
            }
            .alert("Screen layout", isPresented: $screenLayoutInfoShown) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(screenLayout.description)
            }

            if screenLayout == .singleScreen {
                Toggle(isOn: $showLocalSwapButton) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show swap button")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("A small button on screen to switch between the TV and GamePad screens.")
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)

                Toggle(isOn: $pauseHiddenTV) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause the TV screen when it isn't shown")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Stops drawing the TV while the GamePad is shown. The game keeps running. Can reduce heat and battery use.")
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)

                Toggle(isOn: $pauseHiddenPad) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause the GamePad screen when it isn't shown")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Stops drawing the GamePad while the TV is shown. The game keeps running. Can reduce heat and battery use.")
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
            }

            // iPhone only: iPad stays landscape, and the menus on every device do.
            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle(isOn: $allowPortrait) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow portrait during games")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Hold the phone upright to play, with the picture on top and controls below. Off keeps games in landscape.")
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Brightness boost")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(BrightnessBoost.label(for: brightnessBoost))
                        .font(.system(size: 13))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
                HStack(spacing: 8) {
                    Text("Off").font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
                    Slider(value: $brightnessBoost, in: 0...BrightnessBoost.maxValue)
                        .tint(MuffinTheme.accentText)
                        .accessibilityLabel("Brightness boost")
                    Text("Strong").font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
                }
                Text("Makes the picture brighter than your screen's normal maximum. Higher settings can wash out dark areas.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }

            Toggle(isOn: $maxBrightnessWhilePlaying) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full screen brightness while playing")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Sets your screen to full brightness during a game and puts it back afterwards.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)

        } header: {
            SettingsSectionHeader("Display", icon: "rectangle.on.rectangle", accent: .io)
        } footer: {
            InfoButton.footer(
                "Screen layout sets how the TV and GamePad share this device's screen.",
                title: "Display",
                text: "The Wii U has two screens: the TV and the GamePad. Screen layout sets how they share this device's screen.\n\nSingle Screen shows one at a time, with a swap button. Adaptive shows both, stacked in portrait and side by side in landscape. Both Screens (GamePad Top Right) shows the TV full size with a small GamePad in the corner.\n\nAllow portrait during games (iPhone) lets you hold the phone upright, with the picture on top and the controls below. Menus stay in landscape. Turn it off if you don't want games to turn when you tilt the phone.\n\nBrightness boost and Full screen brightness while playing make the picture brighter during games.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @State private var screenLayoutInfoShown = false
}
