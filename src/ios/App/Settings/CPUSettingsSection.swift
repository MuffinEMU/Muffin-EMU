import SwiftUI

/// First section in the Form: whether the recompiler is running is decided by how the app
/// was launched, and matters more to speed than anything below it.
struct CPUSettingsSection: View {
    // Must keep matching GameManager's defaults for the same keys: the engine reads
    // them at title start, and a disagreement here would show a switch in the wrong
    // position.
    @AppStorage("muffin.cpu.recompiler") private var recompilerEnabled = true
    @AppStorage("muffin.cpu.favourAccuracy") private var favourAccuracy = false
    @AppStorage(LowPowerMode.storageKey) private var lowPowerMode = LowPowerMode.defaultValue
    @AppStorage(CoreMode.storageKey) private var coreModeRaw = CoreMode.current.rawValue
    @AppStorage(ThermalMonitor.autoThrottleKey) private var autoReduceWhenHot = ThermalMonitor.autoThrottleDefault
    @ObservedObject private var thermal = ThermalMonitor.shared
    @AppStorage(HeatDisplayMode.storageKey) private var heatDisplayMode = HeatDisplayMode.word.rawValue

    var body: some View {
        Section {
            CPUModeRow()

            // On by default. Without a JIT enabler the bridge falls back to the interpreter.
            Toggle(isOn: $recompilerEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use the recompiler (JIT)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The fast way to run games. Needs a JIT enabler; without one the slow interpreter runs instead.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: recompilerEnabled) { newValue in
                cemu_bridge_set_recompiler_enabled(newValue)
            }

            Toggle(isOn: $favourAccuracy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Favour accuracy")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(favourAccuracy
                         ? "Slower but more accurate: one CPU core and stricter GPU syncing."
                         : "Faster, with some accuracy shortcuts.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: favourAccuracy) { newValue in
                cemu_bridge_set_favour_accuracy(newValue)
            }

            // See LowPowerMode in RenderScale.swift.
            Toggle(isOn: $lowPowerMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Low Power Mode")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(lowPowerMode
                         ? "One CPU core, whatever CPU cores is set to below."
                         : "Follows the CPU cores setting below.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: lowPowerMode) { newValue in
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
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: coreModeRaw) { newValue in
                cemu_bridge_set_cpu_core_mode((CoreMode(rawValue: newValue) ?? CoreMode.defaultValue).bridgeValue)
            }

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
            SettingsSectionHeader("CPU", icon: "cpu", accent: .core)
        } footer: {
            InfoButton.footer(
                "Changes to the CPU switches apply the next time you start a game. Cool down automatically only acts when the device overheats; Low Power Mode is the always-on version.",
                title: "CPU",
                text: "The recompiler needs a JIT enabler (StikJIT, SideStore or LiveContainer). Without one the interpreter runs instead, which is much slower; the CPU line above shows which you got.\n\nFavour accuracy is slower but can fix a game that glitches, desyncs or crashes. It also builds every shader before it is needed, whatever Compile shaders in the background is set to.\n\nCool down automatically acts when iOS reports the device is overheating, and Device heat shows that same state.\n\nThe recompiler, Favour accuracy, Low Power Mode and CPU cores apply the next time you start a game.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Reports whether this launch got the PPC recompiler or the interpreter, and why. The
/// bridge decides once at engine init, so a plain `let` read is correct.
private struct CPUModeRow: View {
    private let mode = cemu_bridge_cpu_mode()
    private let detail = String(cString: cemu_bridge_cpu_mode_detail())

    private var title: String {
        switch mode {
        case 2:  return "Recompiler (JIT)"
        case 1:  return "Interpreter"
        default: return "Not decided yet"
        }
    }

    private var tint: Color {
        // Amber rather than red for the interpreter: it is slow, but it works.
        switch mode {
        case 2:  return MuffinTheme.accentText
        case 1:  return MuffinTheme.cautionText
        default: return MuffinTheme.brownMid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU")
                Spacer()
                Text(title)
                    .foregroundColor(tint)
            }
            Text(detail)
                .font(.footnote)
                .foregroundColor(MuffinTheme.brownMid)
                .fixedSize(horizontal: false, vertical: true)

        }
    }
}
