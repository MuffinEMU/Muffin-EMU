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
                         : "Multi-core CPU, shaders built in the background, accuracy-only work skipped.")
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
                         ? "One CPU core. Cooler and longer-running, and slower."
                         : "Three CPU cores. Fastest, and by far the hottest.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            .onChange(of: lowPowerMode) { newValue in
                cemu_bridge_set_low_power_mode(newValue)
            }
        } header: {
            SettingsSectionHeader("CPU", icon: "cpu", accent: .core)
        } footer: {
            InfoButton.footer(
                "MuffinEMU runs for speed first - turn on Favour accuracy only for a game that glitches, desyncs or crashes, and Low Power Mode if the device gets too hot. Restart the game after changing any of these.",
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
