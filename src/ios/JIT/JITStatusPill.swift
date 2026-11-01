// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// The JIT pill in the library's top bar, beside Settings: a small bolt that says at a glance
// whether JIT is on. Tapping it opens the JIT page in a popup, to check, fix or turn JIT on
// without going into Settings. Settings > JIT > Show JIT status in the top bar hides it.

import SwiftUI

/// What the pill shows.
enum JITPillState {
    /// JIT is on (the process carries CS_DEBUGGED, what the recompiler checks).
    case active
    /// JIT is off and nothing is wrong: it simply hasn't been turned on yet.
    case off
    /// JIT is off and something in the setup is in the way.
    case attention
}

@MainActor
final class JITPillModel: ObservableObject {
    static let shared = JITPillModel()

    @Published private(set) var state: JITPillState = .off
    /// One line on what's wrong, when `state` is `.attention`.
    @Published private(set) var problem: String?

    /// Set by JITCoordinator: whether the last built-in attempt to turn JIT on failed.
    nonisolated static let lastRunFailedKey = "muffin.jit.lastRunFailed"
    nonisolated static let showKey = "muffin.jit.showStatusPill"

    func refresh() {
        if JITStatus.isActive {
            set(.active, nil)
            return
        }
        if let problem = Self.setupProblem() {
            set(.attention, problem)
            return
        }
        set(.off, nil)
        // Someone who has a pairing file is using built-in JIT; an unreachable tunnel is then the usual reason.
        guard JITPairing.isImported, JITEnvironment.meetsMinimumOS else { return }
        JITReachability.check { ok in
            DispatchQueue.main.async {
                guard !ok, !JITStatus.isActive else { return }
                self.set(.attention, "LocalDevVPN isn't connected.")
            }
        }
    }

    private func set(_ state: JITPillState, _ problem: String?) {
        if self.state != state { self.state = state }
        if self.problem != problem { self.problem = problem }
    }

    /// Something that stops JIT from turning on, for someone who has started setting it up.
    private static func setupProblem() -> String? {
        let startedSetup = JITPairing.isImported || UserDefaults.standard.bool(forKey: lastRunFailedKey)
        guard startedSetup else { return nil }
        if JITEnvironment.isLiveContainer { return "Built-in JIT can't work inside LiveContainer." }
        if !JITEnvironment.meetsMinimumOS { return "Built-in JIT needs iOS 17.4 or later." }
        if !JITEntitlement.hasGetTaskAllow { return "This install can't be debugged (no get-task-allow)." }
        if UserDefaults.standard.bool(forKey: lastRunFailedKey) { return "The last try to turn JIT on didn't finish." }
        return nil
    }
}

struct JITStatusPill: View {
    @AppStorage(JITPillModel.showKey) private var show = true
    @ObservedObject private var model = JITPillModel.shared
    @State private var showingPopup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if show {
            Button { showingPopup = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(tint)
                        .frame(width: 30, height: 24)
                        .background(Capsule().fill(tint.opacity(0.16)))
                        .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
                    if model.state == .attention {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(tint)
                            .background(Circle().fill(Color(.systemBackground)).padding(1))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 36, minHeight: 44)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Shows the JIT status and setup.")
            .popover(isPresented: $showingPopup) {
                JITStatusPopup()
            }
            .onAppear { model.refresh() }
            .onChange(of: showingPopup) { open in
                if !open { model.refresh() }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { model.refresh() }
            }
        }
    }

    private var tint: Color {
        switch model.state {
        case .active: return .green
        case .off: return .red
        case .attention: return Color(red: 0.86, green: 0.62, blue: 0.0)
        }
    }

    private var accessibilityText: String {
        switch model.state {
        case .active: return "JIT is on"
        case .off: return "JIT is off"
        case .attention: return "JIT needs attention: " + (model.problem ?? "")
        }
    }
}

/// The JIT page as a popup: status, checks with a fix for each, Turn JIT on, pairing, and
/// the JIT enabler alternative. The same sections Settings > JIT shows.
struct JITStatusPopup: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                BuiltInJITSection()
                JITEnablerSection()
            }
            .navigationTitle("JIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 560, idealHeight: 640)
    }
}
