import SwiftUI

/// First section in the Form: whether the recompiler is running is decided by how the app
/// was launched, and matters more to speed than anything below it.
struct CPUSettingsSection: View {
    // Must keep matching GameManager's defaults for the same keys: the engine reads
    // them at title start, and a disagreement here would show a switch in the wrong
    // position.
    @AppStorage("muffin.cpu.recompiler") private var recompilerEnabled = true
    @AppStorage("muffin.cpu.favourAccuracy") private var favourAccuracy = false
    @AppStorage(FavourPerformance.storageKey) private var favourPerformance = FavourPerformance.defaultValue
    @AppStorage(OneCoreMode.storageKey) private var oneCoreMode = OneCoreMode.defaultValue
    @AppStorage(CoreMode.storageKey) private var coreModeRaw = CoreMode.current.rawValue
    @AppStorage(ThermalMonitor.autoThrottleKey) private var autoReduceWhenHot = ThermalMonitor.autoThrottleDefault
    @AppStorage(ThermalSettings.thresholdKey) private var coolDownThresholdRaw = ThermalSettings.defaultThreshold.rawValue
    @ObservedObject private var thermal = ThermalMonitor.shared
    @AppStorage(HeatDisplayMode.storageKey) private var heatDisplayMode = HeatDisplayMode.word.rawValue
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    var body: some View {
        Section {
            CPUModeRow()

            // On by default. Without a JIT enabler the bridge falls back to the interpreter.
            Toggle(isOn: $recompilerEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use the recompiler (JIT)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The fast way to run games. Needs a JIT enabler; without one the slow interpreter runs instead.")
                        .font(.caption)
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: recompilerEnabled) { newValue in
                cemu_bridge_set_recompiler_enabled(newValue)
            }

            // Advanced mode only: Basic keeps these at their defaults (see AdvancedSettings).
            if advanced {
                Toggle(isOn: $favourAccuracy) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favour accuracy")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(favourAccuracy
                             ? "Slower but more accurate: one CPU core and stricter GPU syncing."
                             : "Faster, with some accuracy shortcuts.")
                            .font(.caption)
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
                .onChange(of: favourAccuracy) { newValue in
                    cemu_bridge_set_favour_accuracy(newValue)
                    // Opposite trades, so turning one on turns the other off.
                    if newValue { favourPerformance = false }
                }

                Toggle(isOn: $favourPerformance) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favour performance")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(favourPerformance
                             ? "As fast as possible: a softer picture, rougher lighting in some games, and shaders that may pop in."
                             : "Off: the normal balance of speed and quality.")
                            .font(.caption)
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
                .onChange(of: favourPerformance) { newValue in
                    cemu_bridge_set_favour_performance(newValue)
                    if newValue { favourAccuracy = false }
                }

                // See OneCoreMode in RenderScale.swift.
                Toggle(isOn: $oneCoreMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("One-core mode")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(oneCoreMode
                             ? "One CPU core, whatever CPU cores is set to below."
                             : "Follows the CPU cores setting below.")
                            .font(.caption)
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                .tint(MuffinTheme.accentText)
                .onChange(of: oneCoreMode) { newValue in
                    cemu_bridge_set_low_power_mode(newValue)
                }

                // Auto by default: decides per game from its profile, this device's performance cores and
                // its thermal state, and leans to one core (see CoreMode in RenderScale.swift).
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CPU cores")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Picker("CPU cores", selection: $coreModeRaw) {
                            ForEach(CoreMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        // The row's own Text is the label; a menu picker in a Form row prints its label as well.
                        .labelsHidden()
                        .tint(MuffinTheme.accentText)
                        .disabled(!DeviceCapabilities.current.multicoreViable)
                    }
                    Text(DeviceCapabilities.current.multicoreViable
                         ? (CoreMode(rawValue: coreModeRaw) ?? CoreMode.defaultValue).summary
                         : DeviceCapabilities.oneCoreOnlyText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: coreModeRaw) { newValue in
                    cemu_bridge_set_cpu_core_mode((CoreMode(rawValue: newValue) ?? CoreMode.defaultValue).bridgeValue)
                }
            }

            CoolDownToggle()

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
                        .font(.caption)
                        .foregroundColor(MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Memory headroom. If the JIT's memory reservation fails, the recompiler is switched
            // off and the interpreter runs, so the arena size shows whether the memory
            // entitlements were honoured on this device.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "memorychip")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MuffinTheme.brownMid)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(String(cString: cemu_bridge_memory_headroom_summary()))
                        .font(.caption)
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
            SettingsSectionHeader("CPU", icon: "cpu", accent: .core)
        } footer: {
            InfoButton.footer(
                "Changes to the CPU switches apply the next time you start a game. Cool down automatically only acts when the device overheats; One-core mode is the always-on version.",
                title: "CPU",
                text: "The recompiler needs a JIT enabler (StikJIT, SideStore or LiveContainer). Without one the interpreter runs instead, which is much slower; the CPU line above shows which you got.\n\nFavour accuracy is slower but can fix a game that glitches, desyncs or crashes. It also builds every shader before it is needed, whatever Compile shaders in the background is set to.\n\nFavour performance is the opposite trade: everything runs as fast as MuffinEMU can make it, and some quality goes. The picture is drawn at Balanced at most with linear scaling, so it's softer. Shaders skip the Wii U's exact multiply rule, which is faster but can make lighting or shadows look wrong in some games. Shaders always compile in the background, so things can pop in for a moment instead of the game pausing. Crash reports carry less detail. Favour accuracy and Favour performance turn each other off, and a game set to favour accuracy in its own options still does.\n\nCool down automatically acts when iOS reports the device is overheating, and Device heat shows that same state. In Advanced mode, Cool down starts at picks the point: Serious (the default) acts as soon as iOS starts throttling, Critical waits until iOS is throttling hard.\n\nThe recompiler, Favour accuracy, Favour performance, One-core mode and CPU cores apply the next time you start a game.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Whether this launch got the PPC recompiler or the interpreter, and why. The bridge decides once at
/// engine init, so a plain `let` read is correct. Shared by the CPU section and "Game runs slowly?".
struct JITStatus {
    private let mode = cemu_bridge_cpu_mode()
    private let bridgeDetail = String(cString: cemu_bridge_cpu_mode_detail())

    /// True once the engine has settled on one or the other, which only happens when a game first starts.
    var isKnown: Bool { mode == 1 || mode == 2 }

    var title: String {
        switch mode {
        case 2:  return "Recompiler (JIT)"
        case 1:  return "Interpreter"
        default: return "Not checked yet"
        }
    }

    /// The short form for a row with little room.
    var rowValue: String {
        switch mode {
        case 2:  return "JIT is on"
        case 1:  return "JIT is off"
        default: return "Not checked yet"
        }
    }

    var detail: String {
        // The engine's own text for this case reads like a status code, so say what it means to a player.
        if !isKnown {
            return "MuffinEMU checks for a JIT enabler the first time you start a game. Come back here after that to see the result."
        }
        return bridgeDetail
    }

    var tint: Color {
        // Amber rather than red for the interpreter: it is slow, but it works.
        switch mode {
        case 2:  return MuffinTheme.accentText
        case 1:  return MuffinTheme.cautionText
        default: return MuffinTheme.brownMid
        }
    }
}

private struct CPUModeRow: View {
    private let status = JITStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU")
                Spacer()
                Text(status.title)
                    .foregroundColor(status.tint)
            }
            Text(status.detail)
                .font(.footnote)
                .foregroundColor(MuffinTheme.brownMid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Cool down automatically", in the CPU section and again under "Game runs slowly?".
struct CoolDownToggle: View {
    @AppStorage(ThermalMonitor.autoThrottleKey) private var autoReduceWhenHot = ThermalMonitor.autoThrottleDefault

    var body: some View {
        // On by default: at .serious iOS is already throttling, so lowering the pixel count
        // gives frames back.
        Toggle(isOn: $autoReduceWhenHot) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cool down automatically")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("When iOS reports the device is overheating, lowers resolution and CPU load until it cools.")
                    .font(.caption)
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
        .tint(MuffinTheme.accentText)
    }
}
