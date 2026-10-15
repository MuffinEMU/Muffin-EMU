// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// True once the player has unlocked premium with an unlock code. Gates the pro app icons.
enum Entitlements {
    static var hasProPlan: Bool {
        PremiumUnlock.isUnlocked
    }
}
