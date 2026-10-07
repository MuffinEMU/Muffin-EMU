// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// The pill that brings the top bar back, in a smaller target than TopBarRevealHandle's.
///
/// While the bar is hidden, TopBarRevealHandle takes every touch in a 220 by 72 point rectangle at the top of the
/// screen. Over the TV that costs nothing, but where the GamePad screen is on this device (both screens, the small
/// GamePad, or dual screen) it is part of the touchscreen a game can use, and a tap there brought the bar back
/// instead of reaching the game. This one is 96 by 44, and only taps and downward swipes count.
///
/// The frame itself is what limits the target (never negative padding: hit testing clips to the frame).
struct CompactTopBarRevealHandle: View {
    let onReveal: () -> Void

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.6))
            // A hairline of shadow so it still reads over a white title screen.
            .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 0.5)
            .frame(width: 80, height: 8)
            .padding(.top, 8)
            .frame(width: 140, height: 52, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { onReveal() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Show top bar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onReveal() }
    }
}
