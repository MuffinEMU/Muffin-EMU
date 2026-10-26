// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Settings > JIT: the recompiler switch, and which app MuffinEMU hands off to when JIT isn't active.
struct JITEnablerSection: View {
    // Must keep matching GameManager's default: the engine reads it at title start.
    @AppStorage("muffin.cpu.recompiler") private var recompilerEnabled = true
    @AppStorage(JITEnabler.storageKey) private var enablerRaw = JITEnabler.none.rawValue
    @AppStorage(JITEnabler.customURLKey) private var customURL = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var active = JITStatus.isActive
    @State private var testNote: String?

    private var enabler: JITEnabler { JITEnabler(rawValue: enablerRaw) ?? .none }
    private var customValid: Bool {
        customURL.contains("{bundleId}") && JITEnabler.url(for: .custom, custom: customURL) != nil
    }

    var body: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(active ? "JIT is active" : "JIT is not active")
                    .foregroundColor(active ? MuffinTheme.accentText : MuffinTheme.cautionText)
            }

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

            Picker("JIT enabler", selection: $enablerRaw) {
                ForEach(JITEnabler.allCases) { Text($0.name).tag($0.rawValue) }
            }

            if enabler == .custom {
                TextField(JITEnabler.customPlaceholder, text: $customURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                if !customURL.isEmpty && !customValid {
                    Text("The link needs {bundleId} in it, and has to be a valid URL.")
                        .font(.footnote)
                        .foregroundColor(MuffinTheme.cautionText)
                }
            }

            if enabler != .none {
                Button("Test it now") { test() }
                    .disabled(enabler == .custom && !customValid)
                if let testNote {
                    Text(testNote)
                        .font(.footnote)
                        .foregroundColor(MuffinTheme.brownMid)
                }
            }
        } header: {
            SettingsSectionHeader("JIT", icon: "bolt.fill", accent: .core)
        } footer: {
            Text("When JIT isn't active, MuffinEMU asks once each time it opens, and offers to open the enabler. It never asks during a game. A custom link is filled in with MuffinEMU's bundle ID wherever it says {bundleId}.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear { active = JITStatus.isActive }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                active = JITStatus.isActive
                // The enabler may have attached a moment after we returned.
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    active = JITStatus.isActive
                }
            }
        }
        .onChange(of: enablerRaw) { _ in testNote = nil }
    }

    private func test() {
        guard let url = JITEnabler.url(for: enabler, custom: customURL) else {
            testNote = "That link isn't valid."
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            Task { @MainActor in
                testNote = opened
                    ? "Opened \(enabler.name). Come back to MuffinEMU to see the status."
                    : "MuffinEMU couldn't open that link. Check that \(enabler.name) is installed."
            }
        }
    }
}
