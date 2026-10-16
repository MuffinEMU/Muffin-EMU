// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Settings > JIT enabler: which app MuffinEMU hands off to when JIT isn't active.
struct JITEnablerSection: View {
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

            Picker("JIT enabler", selection: $enablerRaw) {
                ForEach(JITEnabler.allCases) { Text($0.name).tag($0.rawValue) }
            }

            if enabler == .custom {
                TextField(JITEnabler.customPlaceholder, text: $customURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                if !customURL.isEmpty && !customValid {
                    Text("The link must be a valid URL and include {bundleId}.")
                        .font(.footnote)
                        .foregroundColor(MuffinTheme.cautionText)
                }
            }

            if enabler != .none {
                Button("Test enabler") { test() }
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
            Text("JIT makes games run much faster, and iOS only allows it with an enabler app. If JIT is off when you open MuffinEMU, it asks once whether to open your enabler. In a custom link, {bundleId} is replaced with MuffinEMU's app ID.")
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
