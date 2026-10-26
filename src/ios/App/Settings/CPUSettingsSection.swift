// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// What the CPU runs: whether this launch got the recompiler, how many cores games use, and how much
/// memory the JIT got. The recompiler switch is under JIT; the profile and cooling down are under
/// Performance.
struct CPUSettingsSection: View {
    // Must keep matching GameManager's default for the same key: the engine reads it at title start,
    // and a disagreement here would show the wrong choice.
    @AppStorage(CoreMode.storageKey) private var coreModeRaw = CoreMode.current.rawValue
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    @State private var coreWarning: CoreMode?

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    private var selectedModeUnavailable: Bool { advanced && !(CoreMode(rawValue: coreModeRaw)?.isAvailable ?? true) }

    var body: some View {
        Section {
            CPUModeRow()

            // Advanced mode only: Basic keeps it at its default (see AdvancedSettings).
            if advanced {
                // Auto by default: decides per game from its profile, this device's performance cores and
                // its thermal state, and leans to one core (see CoreMode in RenderScale.swift).
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CPU cores")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Picker("CPU cores", selection: $coreModeRaw) {
                            ForEach(CoreMode.listed) { mode in
                                Text(mode.isAvailable ? mode.title : mode.title + ", may not work").tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        // The row's own Text is the label; a menu picker in a Form row prints its label as well.
                        .labelsHidden()
                        .tint(MuffinTheme.accentText)
                        .disabled(!CoreMode.hasMultiOption && !advanced)
                    }
                    Text(!CoreMode.hasMultiOption && !advanced
                         ? DeviceCapabilities.oneCoreOnlyText
                         : CoreMode.resolved(CoreMode(rawValue: coreModeRaw) ?? CoreMode.defaultValue).summary
                            + (selectedModeUnavailable ? " May not work on this device." : ""))
                        .font(.system(size: 12))
                        .foregroundColor(selectedModeUnavailable ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: coreModeRaw) { newValue in
                    let mode = CoreMode(rawValue: newValue) ?? CoreMode.defaultValue
                    cemu_bridge_set_cpu_core_mode(CoreMode.resolved(mode).bridgeValue)
                    if advanced, !mode.isAvailable { coreWarning = mode }
                }
                .alert("May not work on this device", isPresented: Binding(
                    get: { coreWarning != nil },
                    set: { if !$0 { coreWarning = nil } }
                ), presenting: coreWarning) { _ in
                    Button("OK", role: .cancel) { }
                } message: { mode in
                    Text(mode.limitWarning)
                }
                .onAppear {
                    if !advanced, let saved = CoreMode(rawValue: coreModeRaw), !saved.isAvailable {
                        coreModeRaw = CoreMode.resolved(saved).rawValue
                    }
                }
                PerGameOverrideNote(field: .coreMode)
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
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            SettingsSectionHeader("CPU", icon: "cpu", accent: .core)
        } footer: {
            InfoButton.footer(
                advanced
                    ? "CPU cores applies the next time you start a game. The recompiler switch is under JIT."
                    : "Shows whether games get the fast recompiler or the slow interpreter. The switch is under JIT.",
                title: "CPU",
                text: "The CPU line shows what this launch got: the recompiler (JIT), which is the fast way, or the interpreter, which is much slower. The recompiler needs a JIT enabler (StikJIT, SideStore or LiveContainer); both are set under JIT.\n\nCPU cores (Advanced mode) picks how many cores run a game. Auto decides for each game and device. The Accuracy and Battery saver performance profiles run on one core whatever this says.\n\nMemory shows how much the recompiler reserved. If it couldn't reserve any, the interpreter runs instead.\n\nCPU cores applies the next time you start a game.")
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
