import SwiftUI

/// Where the GamePad's motion (gyro and accelerometer) comes from, and how it is tuned.
///
/// Games such as Splatoon aim with the GamePad's gyro. On an iPad the device itself plays that
/// part: hold it like the GamePad and tilt or turn it. The keys live here rather than in an
/// `@AppStorage` alone because the engine cannot see a property wrapper: `applyToBridge()` pushes
/// the stored values before a title boots, and the Settings rows push changes as they happen.
enum MotionSettings {
    static let enabledKey = "muffin.motion.enabled"
    static let sensitivityKey = "muffin.motion.sensitivity"
    static let sourceKey = "muffin.motion.source"
    static let invertHorizontalKey = "muffin.motion.invertHorizontal"
    static let invertVerticalKey = "muffin.motion.invertVertical"
    static let diagnosticKey = "muffin.motion.diagnostic"

    /// On by default: a title that does not use motion never notices, and one that does expects it.
    static let defaultEnabled = true
    static let defaultSensitivity = 1.0
    static let minSensitivity = 0.25
    static let maxSensitivity = 3.0

    /// Match CemuBridgeMotionSource / CemuBridgeMotionStatus in IOSMotion.h.
    static let sourceDevice = 0
    static let sourceController = 1
    static let defaultSource = sourceDevice
    static let statusOff = 0
    static let statusDevice = 1
    static let statusController = 2
    static let statusUnavailable = 3

    static func applyToBridge() {
        let defaults = UserDefaults.standard
        cemu_bridge_set_motion_enabled(defaults.object(forKey: enabledKey) as? Bool ?? defaultEnabled)
        let sensitivity = defaults.object(forKey: sensitivityKey) as? Double ?? defaultSensitivity
        cemu_bridge_set_motion_sensitivity(Float(sensitivity))
        cemu_bridge_set_motion_source(Int32(defaults.object(forKey: sourceKey) as? Int ?? defaultSource))
        cemu_bridge_set_motion_invert(defaults.bool(forKey: invertHorizontalKey), defaults.bool(forKey: invertVerticalKey))
        cemu_bridge_set_motion_diagnostic(defaults.bool(forKey: diagnosticKey))
    }
}

/// Settings > Motion & Aiming.
struct MotionSettingsSection: View {
    @AppStorage(MotionSettings.enabledKey)
    private var motionEnabled = MotionSettings.defaultEnabled
    @AppStorage(MotionSettings.sensitivityKey)
    private var sensitivity = MotionSettings.defaultSensitivity
    @AppStorage(MotionSettings.sourceKey)
    private var source = MotionSettings.defaultSource
    @AppStorage(MotionSettings.invertHorizontalKey)
    private var invertHorizontal = false
    @AppStorage(MotionSettings.invertVerticalKey)
    private var invertVertical = false
    @AppStorage(MotionSettings.diagnosticKey)
    private var logValues = false
    @State private var recentred = false
    @AppStorage(SettingsMode.storageKey)
    private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    private var statusText: String {
        switch Int(cemu_bridge_motion_status()) {
        case MotionSettings.statusDevice:
            return "Using this device's gyroscope and accelerometer."
        case MotionSettings.statusController:
            return "Using a connected controller's motion sensors."
        case MotionSettings.statusUnavailable:
            return "This device has no motion sensors, so the GamePad will stay still."
        default:
            return "Motion is off. Games see a GamePad that never moves."
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: $motionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Motion aiming")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(motionEnabled
                         ? "Tilt and turn the device to aim, like the GamePad."
                         : "Stick only. The GamePad never moves.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: motionEnabled) { _ in MotionSettings.applyToBridge() }

            if motionEnabled {
                if advanced {
                    motionOptions
                } else {
                    recentreButton
                }
            }
        } header: {
            SettingsSectionHeader("Motion & Aiming", icon: "gyroscope", accent: .io)
        } footer: {
            InfoButton.footer(
                "For games that aim with the GamePad's gyro, such as Splatoon.",
                title: "Motion & Aiming",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @ViewBuilder private var motionOptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Motion from", selection: $source) {
                Text("This device").tag(MotionSettings.sourceDevice)
                Text("Controller").tag(MotionSettings.sourceController)
            }
            .pickerStyle(.segmented)
            .onChange(of: source) { _ in MotionSettings.applyToBridge() }
            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sensitivity")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.2fx", sensitivity))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            Slider(value: $sensitivity, in: MotionSettings.minSensitivity...MotionSettings.maxSensitivity)
                .onChange(of: sensitivity) { _ in MotionSettings.applyToBridge() }
        }

        DisclosureGroup("If aim feels backwards") {
            Toggle("Reverse left and right", isOn: $invertHorizontal)
                .onChange(of: invertHorizontal) { _ in MotionSettings.applyToBridge() }
            Toggle("Reverse up and down", isOn: $invertVertical)
                .onChange(of: invertVertical) { _ in MotionSettings.applyToBridge() }
            Toggle("Log motion values", isOn: $logValues)
                .onChange(of: logValues) { _ in MotionSettings.applyToBridge() }
            Text("Leave these off unless aiming turns the wrong way. The log writes one line a second to the engine log, to report when something looks off.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))

        recentreButton
    }

    private var recentreButton: some View {
        Button {
            cemu_bridge_motion_recenter()
            recentred = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { recentred = false }
        } label: {
            Label(recentred ? "Recentred" : "Recentre aim", systemImage: "scope")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    private var fullText: String {
        "Motion aiming feeds this device's gyroscope and accelerometer to the emulated GamePad, so games that aim by moving the GamePad work the way they do on a Wii U. Hold the device like the GamePad, screen toward you, and tilt or turn it. It follows the way the screen is turned, so it works in every orientation.\n\nMotion from: This device uses the iPad or iPhone itself. Controller uses the motion sensors of a connected controller that has them (DualShock 4, DualSense, Switch Pro Controller) and falls back to the device when there is none. Controller motion has had little testing.\n\nSensitivity is how far the GamePad turns for a given movement. 1.00x matches the real GamePad. Turn it up if you have to move the device a long way to turn.\n\nRecentre aim forgets where the GamePad has been pointing and treats the current position as straight ahead. Use it when aim has drifted, or after turning in your seat. Many games also have their own recentre button.\n\nIf aiming turns the wrong way, \"If aim feels backwards\" reverses left and right, or up and down.\n\nTurn Motion aiming off to aim with the sticks only. A game with its own motion option, Splatoon included, should have that switched off as well."
    }
}
