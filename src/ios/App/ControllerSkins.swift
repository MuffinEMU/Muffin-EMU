// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

struct WiiUControllerSkin {
    let name: String
    let dpadColor: Color
    let buttonColors: [String: Color]
    let backgroundColor: Color
    let borderColor: Color
    let shadowOpacity: Double
    let cornerRadius: CGFloat
}
