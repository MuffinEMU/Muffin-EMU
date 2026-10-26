// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

enum HiddenScreenSettings {
    static let pauseHiddenTVKey = "muffin.display.pauseHiddenTV"
    static let pauseHiddenPadKey = "muffin.display.pauseHiddenGamePad"
    static let hideControlsInHomeMenuKey = "muffin.controls.hideInHomeMenu"
}

/// Pause the TV / GamePad screen when it isn't shown. Drawn in Display (under Single Screen, where they
/// act) and in Performance (they save heat and battery), both on the same keys.
struct HiddenScreenPauseRows: View {
    /// Says when the switches act, for a section that isn't next to Screen Layout.
    var explainsLayout = false

    @AppStorage(HiddenScreenSettings.pauseHiddenTVKey) private var pauseHiddenTV = false
    @AppStorage(HiddenScreenSettings.pauseHiddenPadKey) private var pauseHiddenPad = false
    @AppStorage(LocalScreenLayoutSettings.layoutKey) private var screenLayout = ScreenLayout.initialValue

    var body: some View {
        Toggle(isOn: $pauseHiddenTV) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pause the TV screen when it isn't shown")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Stops drawing the TV while the GamePad is up. The game keeps running. Saves heat and battery.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
        .tint(MuffinTheme.accentText)

        Toggle(isOn: $pauseHiddenPad) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pause the GamePad screen when it isn't shown")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Stops drawing the GamePad while the TV is up. The game keeps running. Saves heat and battery.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
        .tint(MuffinTheme.accentText)

        // Only Single Screen hides a screen; the other layouts show both, so there is nothing to pause.
        if explainsLayout && screenLayout != .singleScreen {
            Text("These act when Screen Layout is Single Screen (Screen and sound > Display). Your layout shows both screens, so nothing is paused now.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
