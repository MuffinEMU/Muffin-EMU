// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Settings keys for the three toy-to-life peripherals the engine emulates (nsyshid:
/// Skylander.cpp, Infinity.cpp, Dimensions.cpp). Also read by ContentView.swift to decide
/// whether to show the in-game "Emulated Devices" button.
enum EmulatedDevicesSettings {
    static let skylanderPortalKey = "muffin.emulatedDevices.skylanderPortal"
    static let infinityBaseKey = "muffin.emulatedDevices.infinityBase"
    static let dimensionsToypadKey = "muffin.emulatedDevices.dimensionsToypad"
    static let defaultEnabled = false // matches CemuConfig's emulated_usb_devices defaults
}

/// Three enable toggles plus a Manage Figures entry point, pushed through AppStorage ->
/// cemu_bridge_set_emulate_* -> GameManager's pre-boot push (same shape as OverlaySettingsSection).
struct EmulatedDevicesSettingsSection: View {
    @AppStorage(EmulatedDevicesSettings.skylanderPortalKey) private var skylanderPortalEnabled = EmulatedDevicesSettings.defaultEnabled
    @AppStorage(EmulatedDevicesSettings.infinityBaseKey) private var infinityBaseEnabled = EmulatedDevicesSettings.defaultEnabled
    @AppStorage(EmulatedDevicesSettings.dimensionsToypadKey) private var dimensionsToypadEnabled = EmulatedDevicesSettings.defaultEnabled

    var body: some View {
        Section {
            Toggle(isOn: $skylanderPortalEnabled) {
                Text("Skylanders portal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: skylanderPortalEnabled) { newValue in
                cemu_bridge_set_emulate_skylander_portal(newValue)
            }
            Toggle(isOn: $infinityBaseEnabled) {
                Text("Disney Infinity base")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: infinityBaseEnabled) { newValue in
                cemu_bridge_set_emulate_infinity_base(newValue)
            }
            Toggle(isOn: $dimensionsToypadEnabled) {
                Text("LEGO Dimensions toypad")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: dimensionsToypadEnabled) { newValue in
                cemu_bridge_set_emulate_dimensions_toypad(newValue)
            }
            NavigationLink("Manage figures") {
                EmulatedDevicesView()
            }
        } header: {
            SettingsSectionHeader("Figure portals", icon: "square.stack.3d.up", accent: .content)
        } footer: {
            InfoButton.footer(
                "Turn on the one your game uses. Applies the next time you start a game.",
                title: "Figure portals",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var fullText: String {
        """
        Some games (Skylanders, Disney Infinity, LEGO Dimensions) read toy figures from a USB portal, base or toypad. MuffinEMU can pretend to be one. Turn on the one your game uses.

        Manage figures lets you load a figure file you own, create a new save for a figure, or clear a slot. MuffinEMU doesn't include any figure data.
        """
    }
}
