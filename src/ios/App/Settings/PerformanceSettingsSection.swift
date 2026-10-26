// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// The top of Performance and graphics: the one choice most people need (the performance profile), the
/// two switches that save heat and battery by not drawing a hidden screen, and cooling down.
struct PerformanceSettingsSection: View {
    // Must keep matching GameManager's defaults for the same keys: the engine reads them at title start.
    @AppStorage("muffin.cpu.favourAccuracy") private var favourAccuracy = false
    @AppStorage(FavourPerformance.storageKey) private var favourPerformance = FavourPerformance.defaultValue
    @AppStorage(OneCoreMode.storageKey) private var oneCoreMode = OneCoreMode.defaultValue
    @AppStorage(ThermalMonitor.autoThrottleKey) private var autoReduceWhenHot = ThermalMonitor.autoThrottleDefault
    @AppStorage(ThermalSettings.thresholdKey) private var coolDownThresholdRaw = ThermalSettings.defaultThreshold.rawValue
    @ObservedObject private var thermal = ThermalMonitor.shared
    @AppStorage(HeatDisplayMode.storageKey) private var heatDisplayMode = HeatDisplayMode.word.rawValue
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    private var profile: PerformanceProfile {
        PerformanceProfile(accuracy: favourAccuracy, performance: favourPerformance, oneCore: oneCoreMode)
    }

    /// Sets all three switches and tells the engine, as the three toggles each used to.
    private var profileChoice: Binding<PerformanceProfile> {
        Binding(
            get: { profile },
            set: { choice in
                guard let switches = choice.switches else { return }
                favourAccuracy = switches.accuracy
                favourPerformance = switches.performance
                oneCoreMode = switches.oneCore
                cemu_bridge_set_favour_accuracy(switches.accuracy)
                cemu_bridge_set_favour_performance(switches.performance)
                cemu_bridge_set_low_power_mode(switches.oneCore)
            })
    }

    var body: some View {
        Section {
            // Basic and Advanced. One choice for Favour accuracy, Favour performance and One-core mode,
            // stored under their own keys as before (see PerformanceProfile).
            VStack(alignment: .leading, spacing: 4) {
                Picker(selection: profileChoice) {
                    ForEach(PerformanceProfile.choices(including: profile)) { choice in
                        Text(choice.title).tag(choice)
                    }
                } label: {
                    Text("Performance profile")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .pickerStyle(.menu)
                .tint(MuffinTheme.accentText)
                Text(profile.summary)
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PerGameOverrideNote(field: .performanceProfile)

            HiddenScreenPauseRows(explainsLayout: true)

            // On by default: at .serious iOS is already throttling, so lowering the pixel count
            // gives frames back.
            Toggle(isOn: $autoReduceWhenHot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cool down automatically")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("When iOS reports the device is overheating, lowers resolution and CPU load until it cools.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)

            // When the cool-down starts: Advanced mode only (see AdvancedSettings).
            if advanced && autoReduceWhenHot {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cool down starts at")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Picker("Cool down starts at", selection: $coolDownThresholdRaw) {
                        ForEach(ThermalSettings.Threshold.allCases) { threshold in
                            Text(threshold.title).tag(threshold.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: coolDownThresholdRaw) { _ in
                        thermal.thresholdChanged()
                    }
                    Text((ThermalSettings.Threshold(rawValue: coolDownThresholdRaw) ?? ThermalSettings.defaultThreshold).summary)
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // What iOS reports for the device's thermal state.
            HStack(spacing: 10) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MuffinTheme.brownMid)
                    .frame(width: 20)
                Text("Device heat")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer(minLength: 12)
                HeatStatusBadge()
            }
            .frame(minHeight: 30)

            // Only shown when a numeric temperature is actually available.
            if HeatStatus.hasRealTemperature {
                Picker("Show as", selection: $heatDisplayMode) {
                    ForEach(HeatDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            SettingsSectionHeader("Performance".localized, icon: "gauge", accent: .core)
        } footer: {
            InfoButton.footer(
                "The profile applies the next time you start a game. Cool down automatically only acts when the device overheats; Battery saver is the always-on version.".localized,
                title: "Performance".localized,
                text: "Performance profile picks one trade-off. Balanced is the default.\n\nAccuracy is slower but can fix a game that glitches, desyncs or crashes. It runs on one CPU core and builds every shader before it is needed, whatever Compile shaders in the background is set to.\n\nSpeed is the opposite trade: everything runs as fast as MuffinEMU can make it, and some quality goes. The picture is drawn at Balanced at most with linear scaling, so it's softer. Shaders skip the Wii U's exact multiply rule, which is faster but can make lighting or shadows look wrong in some games. Shaders always compile in the background, so things can pop in for a moment instead of the game pausing. Crash reports carry less detail.\n\nBattery saver runs on one CPU core whatever CPU cores is set to, for less heat and battery use, at some cost in frame rate.\n\nA game can have its own profile in its Game settings.\n\nPause the TV screen and Pause the GamePad screen stop drawing whichever Wii U screen is out of sight while Screen Layout is Single Screen. The game keeps running and the screen picks up again the moment you swap to it. The same two switches are under Display.\n\nCool down automatically acts when iOS reports the device is overheating, and Device heat shows that same state. In Advanced mode, Cool down starts at picks the point: Serious (the default) acts as soon as iOS starts throttling, Critical waits until iOS is throttling hard.\n\nThe profile applies the next time you start a game.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
