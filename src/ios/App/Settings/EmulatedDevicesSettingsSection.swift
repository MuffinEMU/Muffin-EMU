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
                Text("Skylanders Portal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: skylanderPortalEnabled) { newValue in
                cemu_bridge_set_emulate_skylander_portal(newValue)
            }
            Toggle(isOn: $infinityBaseEnabled) {
                Text("Disney Infinity Base")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: infinityBaseEnabled) { newValue in
                cemu_bridge_set_emulate_infinity_base(newValue)
            }
            Toggle(isOn: $dimensionsToypadEnabled) {
                Text("LEGO Dimensions Toypad")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: dimensionsToypadEnabled) { newValue in
                cemu_bridge_set_emulate_dimensions_toypad(newValue)
            }
            NavigationLink("Manage Figures") {
                EmulatedDevicesView()
            }
        } header: {
            SettingsSectionHeader("Emulated Devices", icon: "square.stack.3d.up", accent: .content)
        } footer: {
            InfoButton.footer(
                "Emulates a Skylanders Portal, Disney Infinity Base or LEGO Dimensions Toypad. Changes apply the next time you start a game.",
                title: "Emulated Devices",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var fullText: String {
        """
        Some games (Skylanders, Disney Infinity, LEGO Dimensions) read toy figures from a USB portal, base or toypad. Turn on the one your game uses; it applies the next time you start a game.

        Manage Figures lets you load a figure dump you own, create a new save for a figure, or clear a slot. No figure data is included with MuffinEMU.
        """
    }
}
