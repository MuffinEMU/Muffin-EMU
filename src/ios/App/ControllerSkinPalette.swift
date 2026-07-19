import SwiftUI

/// Named color constants for each controller skin preset (ControllerSkinsLibrary.swift,
/// ControllerSkins.swift's .pro/.dark). These are deliberate, console-accurate colors -
/// GameCube's green/red/blue/yellow, PlayStation's blue/red/orange/green, N64's red
/// D-pad, etc. - not app chrome, so they intentionally do NOT reference MuffinTheme:
/// collapsing every skin into the bakery brand palette would make every preset look
/// identically orange and defeat the point of a skin picker with visually distinct
/// options. Centralizing them here (instead of inline Color(red:...) literals) is
/// purely about removing magic numbers, not rebranding them.
enum ControllerSkinPalette {
    enum Standard {
        static let dpad = Color(red: 0.7, green: 0.7, blue: 0.7)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.3, blue: 0.2)
        static let x = Color(red: 0.1, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.1)
        static let background = Color(red: 0.15, green: 0.15, blue: 0.17)
    }

    enum WiiUOriginal {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.1, green: 0.7, blue: 0.2)
        static let b = Color(red: 0.95, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.3, blue: 0.95)
        static let y = Color(red: 0.99, green: 0.75, blue: 0.0)
        static let background = Color(red: 0.18, green: 0.18, blue: 0.19)
    }

    enum GameCube {
        static let dpad = Color(red: 0.15, green: 0.15, blue: 0.15)
        static let a = Color(red: 0.15, green: 0.75, blue: 0.25)
        static let b = Color(red: 1.0, green: 0.1, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.3, blue: 0.95)
        static let y = Color(red: 0.95, green: 0.65, blue: 0.0)
        static let background = Color(red: 0.1, green: 0.1, blue: 0.15)
    }

    enum Nintendo64 {
        static let dpad = Color(red: 0.8, green: 0.1, blue: 0.1)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.8, blue: 0.0)
        static let x = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.0)
        static let background = Color(red: 0.12, green: 0.12, blue: 0.2)
    }

    enum SuperNintendo {
        static let dpad = Color(red: 0.7, green: 0.7, blue: 0.7)
        static let a = Color(red: 0.15, green: 0.75, blue: 0.2)
        static let b = Color(red: 0.95, green: 0.15, blue: 0.15)
        static let x = Color(red: 0.15, green: 0.4, blue: 0.95)
        static let y = Color(red: 0.95, green: 0.7, blue: 0.05)
        static let background = Color(red: 0.2, green: 0.15, blue: 0.25)
    }

    enum NES {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let b = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let x = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let y = Color(red: 0.95, green: 0.2, blue: 0.2)
        static let background = Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    enum SwitchPro {
        static let dpad = Color(red: 0.3, green: 0.3, blue: 0.3)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 1.0, green: 0.3, blue: 0.2)
        static let x = Color(red: 0.1, green: 0.5, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.8, blue: 0.1)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.1)
    }

    enum PlayStation {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.2, green: 0.6, blue: 1.0)
        static let b = Color(red: 1.0, green: 0.2, blue: 0.3)
        static let x = Color(red: 1.0, green: 0.4, blue: 0.2)
        static let y = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    }

    enum Xbox {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.1, green: 0.7, blue: 0.2)
        static let b = Color(red: 1.0, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.15, green: 0.4, blue: 1.0)
        static let y = Color(red: 1.0, green: 0.75, blue: 0.0)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.08)
        static let border = Color(red: 0.0, green: 0.8, blue: 0.0)
    }

    enum SteamDeck {
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

    enum SegaGenesis {
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

    enum MarioTheme {
        static let dpad = Color(red: 0.95, green: 0.3, blue: 0.0)
        static let a = Color(red: 0.2, green: 0.8, blue: 0.3)
        static let b = Color(red: 0.95, green: 0.2, blue: 0.1)
        static let x = Color(red: 0.95, green: 0.8, blue: 0.0)
        static let y = Color(red: 0.2, green: 0.4, blue: 0.95)
        static let background = Color(red: 0.95, green: 0.4, blue: 0.0)
    }

    enum ZeldaTheme {
        static let dpad = Color(red: 0.8, green: 0.7, blue: 0.2)
        static let a = Color(red: 0.8, green: 0.7, blue: 0.2)
        static let b = Color(red: 0.3, green: 0.6, blue: 0.2)
        static let x = Color(red: 0.2, green: 0.5, blue: 0.8)
        static let y = Color(red: 0.8, green: 0.2, blue: 0.2)
        static let background = Color(red: 0.1, green: 0.08, blue: 0.12)
    }

    // ControllerSkins.swift's .pro / .dark (defined separately from the main library)
    enum Pro {
        static let dpad = Color(red: 0.2, green: 0.2, blue: 0.2)
        static let a = Color(red: 0.15, green: 0.7, blue: 0.25)
        static let b = Color(red: 0.9, green: 0.2, blue: 0.15)
        static let x = Color(red: 0.0, green: 0.4, blue: 0.95)
        static let y = Color(red: 0.95, green: 0.7, blue: 0.0)
        static let background = Color(red: 0.1, green: 0.1, blue: 0.12)
    }

    enum Dark {
        static let dpad = Color(red: 0.4, green: 0.4, blue: 0.4)
        static let a = Color(red: 0.1, green: 0.6, blue: 0.2)
        static let b = Color(red: 0.8, green: 0.15, blue: 0.1)
        static let x = Color(red: 0.0, green: 0.35, blue: 0.9)
        static let y = Color(red: 0.9, green: 0.65, blue: 0.0)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.1)
    }
}
