import SwiftUI

/// Settings keys for the three toy-to-life peripherals nsyshid already emulates in full
/// (Cafe/OS/libs/nsyshid/Skylander.cpp, Infinity.cpp, Dimensions.cpp) - a complete,
/// already-working engine feature that had no iOS surface before this, same story as
/// GraphicPacksView's graphic packs. Read from ContentView.swift too, to decide whether
/// the in-game "Emulated Devices" button is worth showing at all.
enum EmulatedDevicesSettings {
    static let skylanderPortalKey = "muffin.emulatedDevices.skylanderPortal"
    static let infinityBaseKey = "muffin.emulatedDevices.infinityBase"
    static let dimensionsToypadKey = "muffin.emulatedDevices.dimensionsToypad"
    static let defaultEnabled = false // matches CemuConfig's emulated_usb_devices defaults
}

/// Mirrors MeloCafe's own "Emulated Devices" settings section content (three enable
/// toggles plus a manage-figures entry point), pushed through this app's own
/// AppStorage -> cemu_bridge_set_emulate_* -> GameManager pre-boot-push pipeline instead
/// of MeloCafe's shared ConfigManager object - see OverlaySettingsSection.swift for the
/// same three-part shape this section follows.
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
