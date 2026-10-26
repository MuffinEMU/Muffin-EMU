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
    @AppStorage(FrameStretch.storageKey) private var frameStretchEnabled = FrameStretch.defaultValue
    @AppStorage("muffin.render.upsideDown") private var upsideDownEnabled = false
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

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
                Text("Screen Layout")
                Button {
                    screenLayoutInfoShown = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .accessibilityLabel("About Screen Layout")

                Spacer()

                Picker("Screen Layout", selection: $screenLayout) {
                    ForEach(ScreenLayout.allCases) { layout in
                        Text(layout.string).tag(layout)
                    }
                }
                .pickerStyle(.menu)
                // The row's own Text is the label; a menu picker in a Form row prints its label as well.
                .labelsHidden()
                .tint(MuffinTheme.accentText)
            }
            .alert("Screen Layout", isPresented: $screenLayoutInfoShown) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(screenLayout.description)
            }
            PerGameOverrideNote(field: .screenLayout)

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

                // Also under Performance, since they save heat and battery.
                HiddenScreenPauseRows()
            }

            Toggle(isOn: $frameStretchEnabled) {
                Text("Stretch picture to fill the screen")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: frameStretchEnabled) { newValue in
                cemu_bridge_set_stretch_to_fill(newValue)
            }

            // Advanced mode only: Basic keeps it at its default (see AdvancedSettings).
            if SettingsMode.isAdvanced(raw: settingsModeRaw) {
                Toggle(isOn: $upsideDownEnabled) {
                    Text("Flip screen upside down")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .tint(MuffinTheme.accentText)
                .onChange(of: upsideDownEnabled) { newValue in
                    cemu_bridge_set_render_upside_down(newValue)
                }
            }

            // iPhone only: iPad stays landscape, and the menus on every device do.
            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle(isOn: $allowPortrait) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow portrait during games")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Hold the phone upright to play: the picture goes along the top and the controls below it. Off keeps games in landscape.")
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
                Text("Brightness boost lightens the game picture beyond your screen's maximum. Higher settings wash out dark areas.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }

            Toggle(isOn: $maxBrightnessWhilePlaying) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max screen brightness while playing")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Sets your screen to full brightness during a game and puts it back afterwards.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)

        } header: {
            SettingsSectionHeader("Display".localized, icon: "rectangle.on.rectangle", accent: .io)
        } footer: {
            InfoButton.footer(
                "Screen Layout arranges the TV and GamePad on this device. A TV or second screen is under External display.".localized,
                title: "Display".localized,
                text: "The Wii U has two screens: the TV and the GamePad.\n\nScreen Layout: Single Screen shows one at a time with a swap button; Adaptive shows both, stacked in portrait and side by side in landscape; Both Screens (GamePad Top Right) keeps the TV full size with a small GamePad inset.\n\nWith Single Screen, Pause the TV screen and Pause the GamePad screen stop drawing whichever screen is out of sight, to save heat and battery. The game keeps running. They are under Performance too.\n\nStretch picture to fill the screen fills the screen's own shape instead of keeping the Wii U's 1280x720 proportions, which otherwise letterboxes with bars on two sides. Off keeps the picture undistorted; on trades that for using every pixel. Takes effect on the very next frame.\n\nFlip screen upside down (Advanced mode) turns both Wii U screens vertically before they reach the screen. Off for everyone except a panel or capture rig that presents the image inverted.\n\nAllow portrait during games (iPhone): hold the phone upright and the picture goes along the top with the controls below it. Menus stay in landscape. Turn it off if you'd rather a game never turns when the phone tilts; the iOS rotation lock works too.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @State private var screenLayoutInfoShown = false
}
