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
            SettingsSectionHeader("JIT enabler", icon: "bolt.fill", accent: .core)
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
