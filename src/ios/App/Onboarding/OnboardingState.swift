import SwiftUI

/// First-launch onboarding: whether it has run, and the one flag everything else
/// hangs off. See OnboardingView.swift for the flow itself and for the exact hook
/// ContentView needs to add to present it - this file only owns the persisted state
/// and the row that lets someone bring the flow back on purpose.
enum OnboardingState {
    /// The single source of truth for "has this device been through the onboarding
    /// flow." OnboardingView's own `@AppStorage(OnboardingState.completedKey)` binding
    /// reads and writes this exact key, so the two can never disagree about what
    /// "done" means - there is one flag, read two different ways.
    static let completedKey = "muffin.onboarding.completed"

    /// Plain UserDefaults read rather than @AppStorage: this needs to be callable from
    /// a static context - ContentView deciding, at launch, whether to present the flow
    /// at all - before any view exists to own a property wrapper. Defaults to false,
    /// same as @AppStorage(completedKey) would for a key that has never been set.
    static var hasCompleted: Bool {
        UserDefaults.standard.object(forKey: completedKey) as? Bool ?? false
    }

    /// What ContentView should seed its presentation @State with at appear. Named for
    /// the decision being made, not for the stored bit, even though today the two are
    /// the same value - see the wiring notes at the top of OnboardingView.swift.
    static var shouldPresentOnFirstLaunch: Bool {
        !hasCompleted
    }

    /// Called by OnboardingView itself once "Start playing" is tapped. Not meant to be
    /// called from anywhere else - calling it early would make a real first launch
    /// skip the flow silently.
    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Clears the flag so the flow is due again. Used by SettingsOnboardingRow below;
    /// on its own this does not make anything reappear on screen - see that type for
    /// the rest of the story.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}

/// A row for AboutSettingsSection (or wherever the lead prefers to put it) that lets
/// someone bring the first-launch guide back on purpose. This is the only way back
/// into the flow once it has been completed once, since ContentView only ever checks
/// OnboardingState.shouldPresentOnFirstLaunch a single time, at its own appearance.
///
/// This row clears the completed flag itself, but it cannot present OnboardingView by
/// itself - that presentation lives in ContentView's body (see the hook notes in
/// OnboardingView.swift), and a Settings row has no path to a @State var that lives
/// three sheets up. `onRequestReopen` is that missing path: wire it to whatever flips
/// your presentation state - a Binding<Bool> threaded down through
/// SettingsView/AboutSettingsSection, a small shared ObservableObject flag if that
/// plumbing is unwelcome, or anything else that ends in ContentView's
/// `showingOnboarding` becoming true.
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
