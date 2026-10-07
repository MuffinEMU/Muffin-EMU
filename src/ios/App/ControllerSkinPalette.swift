// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// Controller skin colours; deliberately independent of MuffinTheme.
enum ControllerSkinPalette {
    enum Standard {
        static let dpad = Color(red: 0.7, green: 0.7, blue: 0.7)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.3, blue: 0.2)
        static let x = Color(red: 0.1, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.1)
        static let background = Color(red: 0.15, green: 0.15, blue: 0.17)
    }

    enum Sky {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.1, green: 0.7, blue: 0.2)
        static let b = Color(red: 0.95, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.3, blue: 0.95)
        static let y = Color(red: 0.99, green: 0.75, blue: 0.0)
        static let background = Color(red: 0.18, green: 0.18, blue: 0.19)
    }

    enum Indigo {
        static let dpad = Color(red: 0.15, green: 0.15, blue: 0.15)
        static let a = Color(red: 0.15, green: 0.75, blue: 0.25)
        static let b = Color(red: 1.0, green: 0.1, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.3, blue: 0.95)
        static let y = Color(red: 0.95, green: 0.65, blue: 0.0)
        static let background = Color(red: 0.1, green: 0.1, blue: 0.15)
    }

    enum Primary {
        static let dpad = Color(red: 0.8, green: 0.1, blue: 0.1)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.8, blue: 0.0)
        static let x = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.0)
        static let background = Color(red: 0.12, green: 0.12, blue: 0.2)
    }

    enum LilacGrey {
        static let dpad = Color(red: 0.7, green: 0.7, blue: 0.7)
        static let a = Color(red: 0.15, green: 0.75, blue: 0.2)
        static let b = Color(red: 0.95, green: 0.15, blue: 0.15)
        static let x = Color(red: 0.15, green: 0.4, blue: 0.95)
        static let y = Color(red: 0.95, green: 0.7, blue: 0.05)
        static let background = Color(red: 0.2, green: 0.15, blue: 0.25)
    }

    enum RedAndCream {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let b = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let x = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let y = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let background = Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    enum Charcoal {
        static let dpad = Color(red: 0.3, green: 0.3, blue: 0.3)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.3, blue: 0.2)
        static let x = Color(red: 0.1, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.1)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.1)
    }

    enum BlueAndRose {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.2, green: 0.6, blue: 1.0)
        static let b = Color(red: 1.0, green: 0.2, blue: 0.3)
        static let x = Color(red: 1.0, green: 0.4, blue: 0.2)
        static let y = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    }

    enum Green {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.1, green: 0.7, blue: 0.2)
        static let b = Color(red: 1.0, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.15, green: 0.4, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.75, blue: 0.0)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.08)
        static let border = Color(red: 0.0, green: 0.8, blue: 0.0)
    }

    enum Slate {
        static let dpad = Color(red: 0.15, green: 0.15, blue: 0.15)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.3, blue: 0.2)
        static let x = Color(red: 0.1, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.1)
        static let background = Color(red: 0.1, green: 0.1, blue: 0.11)
    }

    enum ArcadeCabinet {
        static let dpad = Color(red: 0.95, green: 0.4, blue: 0.0)
        static let a = Color(red: 0.95, green: 0.1, blue: 0.1)
        static let b = Color(red: 0.1, green: 0.8, blue: 0.95)
        static let x = Color(red: 0.95, green: 0.95, blue: 0.1)
        static let y = Color(red: 0.1, green: 0.95, blue: 0.4)
        static let background = Color(red: 0.02, green: 0.02, blue: 0.02)
        static let border = Color(red: 0.95, green: 0.4, blue: 0.0)
    }

    enum BlackAndGold {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.95, green: 0.15, blue: 0.15)
        static let b = Color(red: 0.15, green: 0.95, blue: 0.15)
        static let x = Color(red: 0.15, green: 0.15, blue: 0.95)
        static let y = Color(red: 0.95, green: 0.95, blue: 0.15)
        static let background = Color(red: 0.05, green: 0.05, blue: 0.05)
    }

    enum Glass {
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.3, blue: 0.2)
        static let x = Color(red: 0.1, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.1)
    }

    enum Neon {
        static let dpad = Color(red: 0.0, green: 1.0, blue: 0.8)
        static let a = Color(red: 0.0, green: 1.0, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.0, blue: 0.5)
        static let x = Color(red: 0.0, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.85, blue: 0.0)
        static let background = Color(red: 0.02, green: 0.02, blue: 0.05)
        static let border = Color(red: 0.0, green: 1.0, blue: 0.8)
    }

    enum DarkMode {
        static let dpad = Color(red: 0.4, green: 0.4, blue: 0.4)
        static let a = Color(red: 0.1, green: 0.6, blue: 0.2)
        static let b = Color(red: 0.8, green: 0.15, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.35, blue: 0.9)
        static let y = Color(red: 0.9, green: 0.65, blue: 0.0)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.1)
    }

    enum LightMode {
        static let dpad = Color(red: 0.5, green: 0.5, blue: 0.5)
        static let a = Color(red: 0.1, green: 0.8, blue: 0.2)
        static let b = Color(red: 1.0, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.3, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.0)
        static let background = Color(red: 0.9, green: 0.9, blue: 0.92)
    }

    enum Custom {
        static let dpad = Color(red: 0.4, green: 0.6, blue: 0.8)
        static let a = Color(red: 0.6, green: 0.3, blue: 0.8)
        static let b = Color(red: 0.8, green: 0.3, blue: 0.6)
        static let x = Color(red: 0.3, green: 0.8, blue: 0.6)
        static let y = Color(red: 0.8, green: 0.6, blue: 0.3)
        static let background = Color(red: 0.1, green: 0.12, blue: 0.15)
    }

    enum SunsetOrange {
        static let dpad = Color(red: 0.95, green: 0.3, blue: 0.0)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 0.95, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.95, green: 0.8, blue: 0.0)
        static let y = Color(red: 0.2, green: 0.4, blue: 0.95)
        static let background = Color(red: 0.95, green: 0.4, blue: 0.0)
    }

    enum ForestGold {
        static let dpad = Color(red: 0.8, green: 0.7, blue: 0.2)
        static let a = Color(red: 0.8, green: 0.7, blue: 0.2)
        static let b = Color(red: 0.3, green: 0.6, blue: 0.2)
        static let x = Color(red: 0.2, green: 0.5, blue: 0.8)
        static let y = Color(red: 0.8, green: 0.2, blue: 0.2)
        static let background = Color(red: 0.1, green: 0.08, blue: 0.12)
    }
}
