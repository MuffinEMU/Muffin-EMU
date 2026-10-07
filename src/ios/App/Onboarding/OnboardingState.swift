// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// Whether the first-launch onboarding has run (see OnboardingView.swift for the flow) and
/// the row that brings it back on purpose.
enum OnboardingState {
    /// The one persisted flag; OnboardingView's `@AppStorage(OnboardingState.completedKey)`
    /// reads and writes the same key.
    static let completedKey = "muffin.onboarding.completed"

    /// Plain UserDefaults read so it works from a static context before any view exists.
    static var hasCompleted: Bool {
        UserDefaults.standard.object(forKey: completedKey) as? Bool ?? false
    }

    /// What ContentView seeds its presentation @State with at appear.
    static var shouldPresentOnFirstLaunch: Bool {
        !hasCompleted
    }

    /// Called by OnboardingView once "Start playing" is tapped.
    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Clears the flag so the flow is due again. Presenting it is the caller's job (see
    /// SettingsOnboardingRow).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}

/// Posted to ask ContentView to present OnboardingView again. SettingsOnboardingRow clears
/// the completed flag and posts this; ContentView owns the presentation state.
extension Notification.Name {
    static let muffinReopenOnboarding = Notification.Name("muffin.onboarding.reopen")
}

struct SettingsOnboardingRow: View {
    var onRequestReopen: () -> Void

    var body: some View {
        Button {
            OnboardingState.reset()
            onRequestReopen()
        } label: {
            Label("Show welcome guide again", systemImage: "hand.wave")
        }
        .accessibilityHint("Reopens the first-launch guide to keys, games, speed and controls.")
    }
}
