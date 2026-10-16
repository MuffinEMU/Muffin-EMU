// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

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
    /// A controller with motion sensors wins when one is connected; with none, the device is used
    /// anyway. Defaulting to the device would leave a DualShock 4 or Joy-Con unused unless the
    /// player found the picker, which only shows in Advanced mode.
    static let defaultSource = sourceController
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
            return "Motion is off. Games see a GamePad that doesn't move."
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
                         : "Sticks only. The GamePad doesn't move.")
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
            SettingsSectionHeader("Motion and aiming", icon: "gyroscope", accent: .io)
        } footer: {
            InfoButton.footer(
                "For games that aim by tilting the GamePad, such as Splatoon.",
                title: "Motion and aiming",
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
            Text("Leave these off unless aiming turns the wrong way. The log writes one line a second to the app log, for bug reports.")
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
        "Motion aiming uses your device's motion sensors as the GamePad's gyro, so games like Splatoon can aim by tilting. Hold the device like the GamePad, screen toward you, and tilt or turn it. It works in any orientation.\n\nMotion from: This device uses the iPad or iPhone itself. Controller uses a connected controller with motion sensors (DualShock 4, DualSense, Switch Pro Controller) and falls back to the device if there isn't one. Controller motion has had little testing.\n\nSensitivity sets how far the aim moves for a given tilt. 1.00x matches the real GamePad.\n\nRecentre aim treats the way you're holding the device as straight ahead. Use it if aim drifts.\n\nIf aim feels backwards, use the options under it to reverse left and right, or up and down.\n\nTurn Motion aiming off to aim with the sticks only. If a game has its own motion option, switch that off as well."
    }
}
