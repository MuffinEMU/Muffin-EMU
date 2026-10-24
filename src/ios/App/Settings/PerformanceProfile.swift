// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// One choice for the three CPU trade-offs that used to be separate switches: Favour accuracy, Favour
/// performance and One-core mode. A profile sets all three under their own keys (and, per game, in
/// GameOverrides), so the launch and the bridge read them exactly as before; only the screen changed.
///
/// Custom is the one combination no profile makes, Speed with one core, possible before the picker
/// existed. It is listed only while it is what's stored, so the picker never hides what is on.
enum PerformanceProfile: String, CaseIterable, Identifiable {
    case balanced, speed, accuracy, batterySaver, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .speed: return "Speed"
        case .accuracy: return "Accuracy"
        case .batterySaver: return "Battery saver"
        case .custom: return "Custom"
        }
    }

    var summary: String {
        switch self {
        case .balanced: return "The normal balance of speed and picture quality."
        case .speed: return "Faster, but the picture is softer and some games look wrong."
        case .accuracy: return "Slower but more accurate, on one CPU core. Try it if a game glitches or crashes."
        case .batterySaver: return "One CPU core whatever CPU cores says, for less heat and battery use. Costs some frame rate."
        case .custom: return "Speed with one CPU core, set before this choice existed. Pick a profile to replace it."
        }
    }

    /// The profiles offered in a picker: Custom only while it's what is stored.
    static func choices(including current: PerformanceProfile) -> [PerformanceProfile] {
        let listed: [PerformanceProfile] = [.balanced, .speed, .accuracy, .batterySaver]
        return current == .custom ? listed + [.custom] : listed
    }

    /// The three switches this profile sets. Nil for Custom, which can't be picked.
    var switches: (accuracy: Bool, performance: Bool, oneCore: Bool)? {
        switch self {
        case .balanced: return (false, false, false)
        case .speed: return (false, true, false)
        case .accuracy: return (true, false, false)
        case .batterySaver: return (false, false, true)
        case .custom: return nil
        }
    }

    /// The profile three switches amount to. Accuracy wins over the others, as it does in the bridge,
    /// and already runs on one core.
    init(accuracy: Bool, performance: Bool, oneCore: Bool) {
        switch (accuracy, performance, oneCore) {
        case (true, _, _): self = .accuracy
        case (false, true, false): self = .speed
        case (false, true, true): self = .custom
        case (false, false, true): self = .batterySaver
        case (false, false, false): self = .balanced
        }
    }

    /// What Settings has now, read the way GameManager reads the three keys.
    static var current: PerformanceProfile {
        PerformanceProfile(accuracy: UserDefaults.standard.object(forKey: "muffin.cpu.favourAccuracy") as? Bool ?? false,
                           performance: FavourPerformance.isEnabled,
                           oneCore: OneCoreMode.isEnabled)
    }
}
