import SwiftUI

/// First section in the Form on purpose: this is the single decision worth more to
/// speed than everything below it combined, and it is not really "a setting" - it
/// is decided by HOW the app was launched, which is exactly why CPUModeRow needs
/// saying up top rather than buried under Graphics or Diagnostics.
struct CPUSettingsSection: View {
    // Must keep matching GameManager's defaults for the same keys: the engine reads
    // them at title start, and a disagreement here would show a switch in the wrong
    // position.
    @AppStorage("muffin.cpu.recompiler") private var recompilerEnabled = true
    @AppStorage("muffin.cpu.favourAccuracy") private var favourAccuracy = false
    @AppStorage(LowPowerMode.storageKey) private var lowPowerMode = LowPowerMode.defaultValue
    @AppStorage(MulticoreMode.storageKey) private var multicoreEnabled = MulticoreMode.defaultValue
    @AppStorage(ThermalMonitor.autoThrottleKey) private var autoReduceWhenHot = ThermalMonitor.autoThrottleDefault
    @ObservedObject private var thermal = ThermalMonitor.shared
    @AppStorage(HeatDisplayMode.storageKey) private var heatDisplayMode = HeatDisplayMode.word.rawValue

    var body: some View {
        Section {
            CPUModeRow()

            // On by default: the recompiler is the fast path this build
            // exists for. Without a JIT enabler attached it cannot run at all, and
            // the bridge falls back to the interpreter by itself.
            Toggle(isOn: $recompilerEnabled) {
                Text("Use the recompiler (JIT)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: recompilerEnabled) { newValue in
                cemu_bridge_set_recompiler_enabled(newValue)
            }

            Toggle(isOn: $favourAccuracy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Favour accuracy")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(favourAccuracy
                         ? "One CPU core, shaders built before they are drawn, accurate barriers and draw-done sync."
                         : "Shaders built in the background, accuracy-only work skipped.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: favourAccuracy) { newValue in
                cemu_bridge_set_favour_accuracy(newValue)
            }

            // Sits with the CPU settings rather than under Graphics because the core
            // count is what it actually changes, and that is a CPU decision. See
            // LowPowerMode in RenderScale.swift for why one emulated core is the lever
            // that matters for heat and what it costs.
            Toggle(isOn: $lowPowerMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Low Power Mode")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(lowPowerMode
                         ? "One CPU core, and holds it there even if the switch below is on."
                         : "Follows the core setting below.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: lowPowerMode) { newValue in
                cemu_bridge_set_low_power_mode(newValue)
            }

            // Off by default, and that default is measured rather than assumed. On an
            // A12Z iPad Pro running Wind Waker HD, MeloCafe on one core holds 40-60fps
            // and MuffinEMU on three managed 4-20. Three host threads on a fanless part
            // do not buy three times the work - they buy three times the power draw, and
            // the SoC takes the clocks back within a minute. The multi-core win is real
            // on a desktop with a fan; this is not that.
            //
            // Kept as a switch rather than deleted because a newer, better-cooled device
            // may well come out ahead, and that is worth being able to find out.
            Toggle(isOn: $multicoreEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use all three CPU cores")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(multicoreEnabled
                         ? "Three CPU cores. Faster in theory, but it heats this device up fast and usually ends up slower."
                         : "One CPU core, the way MeloCafe runs. Cooler, and on this hardware normally faster.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: multicoreEnabled) { newValue in
                cemu_bridge_set_multicore_enabled(newValue)
            }

            // Defaults ON, unlike Low Power Mode. Not a contradiction: at .serious iOS is
            // ALREADY throttling the CPU and GPU, so the frame rate has already dropped.
            // Cutting the pixel count is how those frames come back, and how the device
            // gets to a temperature where the OS stops throttling at all. This protects
            // speed rather than trading it away.
            Toggle(isOn: $autoReduceWhenHot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cool down automatically")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("While iOS reports the device is overheating, eases off the CPU and drops to Battery saver resolution. Everything goes back on its own once it cools.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            // Memory headroom and what the recompiler got out of it.
            //
            // The JIT reserves its arena in one piece, and if that reservation fails the
            // recompiler is switched off and the title runs on the interpreter instead -
            // about an order of magnitude slower. So the arena size is the number worth
            // showing: it says whether the increased-memory-limit and
            // extended-virtual-addressing entitlements were actually honoured on this
            // device, which no amount of asking for them can tell you.
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
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // What iOS itself reports, shown because until now nothing in the app could
            // see it - the only way to know was a third-party thermal app.
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

            // The picker only appears when the numeric modes can actually do something.
            // iOS publishes no device temperature to apps, and on most installs the
            // battery sensor is unreachable too - so on those builds there is exactly one
            // honest way to show this, and offering a choice between one real option and
            // two that silently fall back to it is worse than offering no choice at all.
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
                "MuffinEMU runs for speed first. Cool down automatically handles overheating on its own; Low Power Mode is the permanent version of it. Restart the game after changing the top three.",
                title: "CPU",
                text: "MuffinEMU runs for speed first. The recompiler needs a JIT enabler (StikJIT, SideStore or LiveContainer); without one the interpreter runs instead, and the line above says which you got. Turn on Favour accuracy for a game that glitches, desyncs or crashes - it is slower. Start the game again after changing either.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Reports whether this launch got the PPC recompiler or the interpreter, and why.
///
/// This exists because the answer was previously only obtainable by pulling
/// CemuCrashLog.txt off the device and reading a cs_flags hex value out of it - an absurd
/// thing to ask of someone whose actual question is "did launching through StikJIT do
/// anything". The bridge decides this once at engine init, so a plain `let` read in
/// `init` is correct; there is no path that changes it while this sheet is open.
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
        // Amber rather than red for the interpreter: it is slow, but it is a working,
        // correct emulator, and it is the state every launch has been in so far. Red
        // would be claiming something is broken when nothing is.
        switch mode {
        case 2:  return MuffinTheme.pixelBlue
        case 1:  return .orange
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
