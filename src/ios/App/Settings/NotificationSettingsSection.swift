import SwiftUI

/// Settings keys for every row this section exposes - the full set of fields on
/// CemuConfig's `notification` struct, one @AppStorage key each. This is a second,
/// independent on-screen draw from the performance overlay (LatteOverlay_RenderNotifications()
/// in LatteOverlay.cpp, its own ImGui window with its own position/color/scale), not a
/// Swift-drawn toast layered on top - the engine itself decides when a controller-profile,
/// low-battery, shader-compiling or friends notification fires and draws it.
enum NotificationSettings {
    static let positionKey = "muffin.notification.position"
    static let defaultPosition = ScreenPosition.topLeft // matches CemuConfig's notification.position default

    static let textColorKey = "muffin.notification.textColor"
    // Int, not UInt32 - see OverlaySettingsSection.swift's identical note on textColor.
    static let defaultTextColor: Int = 0xFFFFFFFF // opaque white, matches CemuConfig's default

    static let textScaleKey = "muffin.notification.textScale"
    static let defaultTextScale = 100 // percent, matches CemuConfig's notification.text_scale default

    static let controllerProfilesKey = "muffin.notification.controllerProfiles"
    static let defaultControllerProfiles = true // matches CemuConfig's notification.controller_profiles default

    static let controllerBatteryKey = "muffin.notification.controllerBattery"
    static let defaultControllerBattery = false // matches CemuConfig's notification.controller_battery default

    static let shaderCompilingKey = "muffin.notification.shaderCompiling"
    static let defaultShaderCompiling = true // matches CemuConfig's notification.shader_compiling default

    static let friendsKey = "muffin.notification.friends"
    static let defaultFriends = true // matches CemuConfig's notification.friends default
}

/// Toasts the engine itself draws for controller pairing/battery, shader compile progress
/// and friend activity - same "app owns the @AppStorage, GameManager pushes it before
/// boot" split as OverlaySettingsSection, and the same ScreenPosition this app's
/// Performance Overlay uses, since both are corner-anchored ImGui windows drawn by the
/// same LatteOverlay.cpp.
///
/// The rows below are visually disabled rather than hidden when position is Off, for the
/// same reason as the overlay section: picking which notifications you want before
/// turning the feature on somewhere is a normal way to use this.
struct NotificationSettingsSection: View {
    @AppStorage(NotificationSettings.positionKey) private var positionRaw = NotificationSettings.defaultPosition.rawValue
    @AppStorage(NotificationSettings.textColorKey) private var textColor = NotificationSettings.defaultTextColor
    @AppStorage(NotificationSettings.textScaleKey) private var textScale = NotificationSettings.defaultTextScale
    @AppStorage(NotificationSettings.controllerProfilesKey) private var controllerProfilesEnabled = NotificationSettings.defaultControllerProfiles
    @AppStorage(NotificationSettings.controllerBatteryKey) private var controllerBatteryEnabled = NotificationSettings.defaultControllerBattery
    @AppStorage(NotificationSettings.shaderCompilingKey) private var shaderCompilingEnabled = NotificationSettings.defaultShaderCompiling
    @AppStorage(NotificationSettings.friendsKey) private var friendsEnabled = NotificationSettings.defaultFriends

    private var position: ScreenPosition {
        ScreenPosition(rawValue: positionRaw) ?? .disabled
    }

    private var isOff: Bool { position == .disabled }

    var body: some View {
        Section {
            positionPicker
            textColorField
            textScaleSlider
            controllerProfilesToggle
            controllerBatteryToggle
            shaderCompilingToggle
            friendsToggle
        } header: {
            Text("Notifications")
        } footer: {
            InfoButton.footer(
                "On-screen toasts for controller pairing, low battery, shader compiling and friend activity. The rows below only draw once a corner is picked.",
                title: "Notifications",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var positionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Position")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("Position", selection: $positionRaw) {
                ForEach(ScreenPosition.allCases) { position in
                    Text(position.title).tag(position.rawValue)
                }
            }
        }
        .onChange(of: positionRaw) { newValue in
            cemu_bridge_set_notification_position(Int32(newValue))
        }
    }

    // Same 0xAARRGGBB packing and same 6/8-digit hex parsing as OverlaySettingsSection's
    // textColorHex - see its doc comment for why.
    private var textColorHex: Binding<String> {
        Binding {
            String(format: "#%08X", UInt32(textColor))
        } set: { newValue in
            let cleaned = newValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
            guard let parsed = UInt32(cleaned, radix: 16) else { return }
            switch cleaned.count {
            case 6: textColor = Int(0xFF000000 | parsed)
            case 8: textColor = Int(parsed)
            default: return
            }
        }
    }

    private var textColorField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Text Color")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            TextField("AARRGGBB", text: textColorHex)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .disabled(isOff)
        .onChange(of: textColor) { newValue in
            cemu_bridge_set_notification_text_color(UInt32(newValue))
        }
    }

    private var textScaleSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Text Scale")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(textScale)%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(get: { Double(textScale) }, set: { textScale = Int($0) }),
                in: 50...200, step: 25)
        }
        .disabled(isOff)
        .onChange(of: textScale) { newValue in
            cemu_bridge_set_notification_text_scale(Int32(newValue))
        }
    }

    private var controllerProfilesToggle: some View {
        Toggle(isOn: $controllerProfilesEnabled) {
            Text("Controller Profiles")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: controllerProfilesEnabled) { newValue in
            cemu_bridge_set_notification_controller_profiles(newValue)
        }
    }

    private var controllerBatteryToggle: some View {
        Toggle(isOn: $controllerBatteryEnabled) {
            Text("Low Battery")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: controllerBatteryEnabled) { newValue in
            cemu_bridge_set_notification_controller_battery(newValue)
        }
    }

    private var shaderCompilingToggle: some View {
        Toggle(isOn: $shaderCompilingEnabled) {
            Text("Shader Compiling")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: shaderCompilingEnabled) { newValue in
            cemu_bridge_set_notification_shader_compiling(newValue)
        }
    }

    private var friendsToggle: some View {
        Toggle(isOn: $friendsEnabled) {
            Text("Friends")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: friendsEnabled) { newValue in
            cemu_bridge_set_notification_friends(newValue)
        }
    }

    private var fullText: String {
        """
        Notifications are a second on-screen readout from the same engine that draws the Performance Overlay - its own corner-anchored window, with its own position, color and scale, independent of whether the overlay is on. Position picks which corner (or top/bottom center) it appears in; Off leaves it out of the picture entirely, and the rows below have no effect until a position is chosen.

        Controller Profiles fires when a controller's saved profile is applied. Low Battery warns when a paired controller's battery is running down. Shader Compiling shows while the engine is building a shader in the background. Friends surfaces friend-related activity from the account system.
        """
    }
}
