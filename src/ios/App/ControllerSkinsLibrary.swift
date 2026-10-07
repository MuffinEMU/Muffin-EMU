// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// Where the chosen on-screen pad skin's name is kept.
enum ControllerSkinStorage {
    static let key = "muffin.pad.skin"
}

struct ControllerSkinLibrary {
    static let allSkins: [WiiUControllerSkin] = [
        .standard,
        .sky,
        .indigo,
        .primary,
        .lilacGrey,
        .redAndCream,
        .charcoal,
        .blueAndRose,
        .green,
        .slate,
        .arcadeCabinet,
        .blackAndGold,
        .minimal,
        .glass,
        .neon,
        .darkMode,
        .lightMode,
        .custom,
        .sunsetOrange,
        .forestGold,
    ]

    static func getSkin(by name: String) -> WiiUControllerSkin? {
        // Renamed skins keep resolving the name a player stored earlier.
        let renamed: [String: String] = [
            "Custom": "Violet",
            "GameCube": "Indigo",
            "Nintendo 64": "Primary",
            "Super Nintendo": "Lilac Grey",
            "NES": "Red and Cream",
            "Switch Pro": "Charcoal",
            "Wii U Original": "Sky",
            "Mario Theme": "Sunset Orange",
            "Zelda Theme": "Forest Gold",
            "PlayStation": "Blue and Rose",
            "Xbox": "Green",
            "Steam Deck": "Slate",
            "Sega Genesis": "Black and Gold",
        ]
        let current = renamed[name] ?? name
        return allSkins.first { $0.name == current }
    }
}

extension WiiUControllerSkin {
    // MARK: - Core

    static let standard = WiiUControllerSkin(
        name: "Standard",
        dpadColor: ControllerSkinPalette.Standard.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Standard.a,
            "B": ControllerSkinPalette.Standard.b,
            "X": ControllerSkinPalette.Standard.x,
            "Y": ControllerSkinPalette.Standard.y
        ],
        backgroundColor: ControllerSkinPalette.Standard.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.4,
        cornerRadius: 24
    )

    static let sky = WiiUControllerSkin(
        name: "Sky",
        dpadColor: ControllerSkinPalette.Sky.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Sky.a,
            "B": ControllerSkinPalette.Sky.b,
            "X": ControllerSkinPalette.Sky.x,
            "Y": ControllerSkinPalette.Sky.y
        ],
        backgroundColor: ControllerSkinPalette.Sky.background,
        borderColor: Color.white.opacity(0.12),
        shadowOpacity: 0.45,
        cornerRadius: 22
    )

    static let indigo = WiiUControllerSkin(
        name: "Indigo",
        dpadColor: ControllerSkinPalette.Indigo.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Indigo.a,
            "B": ControllerSkinPalette.Indigo.b,
            "X": ControllerSkinPalette.Indigo.x,
            "Y": ControllerSkinPalette.Indigo.y
        ],
        backgroundColor: ControllerSkinPalette.Indigo.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    static let primary = WiiUControllerSkin(
        name: "Primary",
        dpadColor: ControllerSkinPalette.Primary.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Primary.a,
            "B": ControllerSkinPalette.Primary.b,
            "X": ControllerSkinPalette.Primary.x,
            "Y": ControllerSkinPalette.Primary.y
        ],
        backgroundColor: ControllerSkinPalette.Primary.background,
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.4,
        cornerRadius: 18
    )

    static let lilacGrey = WiiUControllerSkin(
        name: "Lilac Grey",
        dpadColor: ControllerSkinPalette.LilacGrey.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.LilacGrey.a,
            "B": ControllerSkinPalette.LilacGrey.b,
            "X": ControllerSkinPalette.LilacGrey.x,
            "Y": ControllerSkinPalette.LilacGrey.y
        ],
        backgroundColor: ControllerSkinPalette.LilacGrey.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.35,
        cornerRadius: 16
    )

    static let redAndCream = WiiUControllerSkin(
        name: "Red and Cream",
        dpadColor: ControllerSkinPalette.RedAndCream.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.RedAndCream.a,
            "B": ControllerSkinPalette.RedAndCream.b,
            "X": ControllerSkinPalette.RedAndCream.x,
            "Y": ControllerSkinPalette.RedAndCream.y
        ],
        backgroundColor: ControllerSkinPalette.RedAndCream.background,
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.3,
        cornerRadius: 12
    )

    static let charcoal = WiiUControllerSkin(
        name: "Charcoal",
        dpadColor: ControllerSkinPalette.Charcoal.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Charcoal.a,
            "B": ControllerSkinPalette.Charcoal.b,
            "X": ControllerSkinPalette.Charcoal.x,
            "Y": ControllerSkinPalette.Charcoal.y
        ],
        backgroundColor: ControllerSkinPalette.Charcoal.background,
        borderColor: Color.white.opacity(0.12),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    // MARK: - Colour sets

    static let blueAndRose = WiiUControllerSkin(
        name: "Blue and Rose",
        dpadColor: ControllerSkinPalette.BlueAndRose.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.BlueAndRose.a,
            "B": ControllerSkinPalette.BlueAndRose.b,
            "X": ControllerSkinPalette.BlueAndRose.x,
            "Y": ControllerSkinPalette.BlueAndRose.y
        ],
        backgroundColor: ControllerSkinPalette.BlueAndRose.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.55,
        cornerRadius: 22
    )

    static let green = WiiUControllerSkin(
        name: "Green",
        dpadColor: ControllerSkinPalette.Green.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Green.a,
            "B": ControllerSkinPalette.Green.b,
            "X": ControllerSkinPalette.Green.x,
            "Y": ControllerSkinPalette.Green.y
        ],
        backgroundColor: ControllerSkinPalette.Green.background,
        borderColor: ControllerSkinPalette.Green.border.opacity(0.3),
        shadowOpacity: 0.5,
        cornerRadius: 18
    )

    static let slate = WiiUControllerSkin(
        name: "Slate",
        dpadColor: ControllerSkinPalette.Slate.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Slate.a,
            "B": ControllerSkinPalette.Slate.b,
            "X": ControllerSkinPalette.Slate.x,
            "Y": ControllerSkinPalette.Slate.y
        ],
        backgroundColor: ControllerSkinPalette.Slate.background,
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.45,
        cornerRadius: 20
    )

    // MARK: - Retro & Arcade

    static let arcadeCabinet = WiiUControllerSkin(
        name: "Arcade Cabinet",
        dpadColor: ControllerSkinPalette.ArcadeCabinet.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.ArcadeCabinet.a,
            "B": ControllerSkinPalette.ArcadeCabinet.b,
            "X": ControllerSkinPalette.ArcadeCabinet.x,
            "Y": ControllerSkinPalette.ArcadeCabinet.y
        ],
        backgroundColor: ControllerSkinPalette.ArcadeCabinet.background,
        borderColor: ControllerSkinPalette.ArcadeCabinet.border.opacity(0.5),
        shadowOpacity: 0.6,
        cornerRadius: 12
    )

    static let blackAndGold = WiiUControllerSkin(
        name: "Black and Gold",
        dpadColor: ControllerSkinPalette.BlackAndGold.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.BlackAndGold.a,
            "B": ControllerSkinPalette.BlackAndGold.b,
            "X": ControllerSkinPalette.BlackAndGold.x,
            "Y": ControllerSkinPalette.BlackAndGold.y
        ],
        backgroundColor: ControllerSkinPalette.BlackAndGold.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.4,
        cornerRadius: 14
    )

    // MARK: - Minimalist & Modern

    static let minimal = WiiUControllerSkin(
        name: "Minimal",
        dpadColor: Color.white.opacity(0.8),
        buttonColors: [
            "A": Color.white.opacity(0.7),
            "B": Color.white.opacity(0.7),
            "X": Color.white.opacity(0.7),
            "Y": Color.white.opacity(0.7)
        ],
        backgroundColor: Color.black.opacity(0.6),
        borderColor: Color.white.opacity(0.2),
        shadowOpacity: 0.2,
        cornerRadius: 12
    )

    static let glass = WiiUControllerSkin(
        name: "Glass",
        dpadColor: Color.white.opacity(0.6),
        buttonColors: [
            "A": ControllerSkinPalette.Glass.a.opacity(0.7),
            "B": ControllerSkinPalette.Glass.b.opacity(0.7),
            "X": ControllerSkinPalette.Glass.x.opacity(0.7),
            "Y": ControllerSkinPalette.Glass.y.opacity(0.7)
        ],
        backgroundColor: Color.black.opacity(0.3),
        borderColor: Color.white.opacity(0.3),
        shadowOpacity: 0.15,
        cornerRadius: 16
    )

    static let neon = WiiUControllerSkin(
        name: "Neon",
        dpadColor: ControllerSkinPalette.Neon.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Neon.a,
            "B": ControllerSkinPalette.Neon.b,
            "X": ControllerSkinPalette.Neon.x,
            "Y": ControllerSkinPalette.Neon.y
        ],
        backgroundColor: ControllerSkinPalette.Neon.background,
        borderColor: ControllerSkinPalette.Neon.border.opacity(0.4),
        shadowOpacity: 0.6,
        cornerRadius: 20
    )

    static let darkMode = WiiUControllerSkin(
        name: "Dark Mode",
        dpadColor: ControllerSkinPalette.DarkMode.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.DarkMode.a,
            "B": ControllerSkinPalette.DarkMode.b,
            "X": ControllerSkinPalette.DarkMode.x,
            "Y": ControllerSkinPalette.DarkMode.y
        ],
        backgroundColor: ControllerSkinPalette.DarkMode.background,
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.6,
        cornerRadius: 18
    )

    static let lightMode = WiiUControllerSkin(
        name: "Light Mode",
        dpadColor: ControllerSkinPalette.LightMode.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.LightMode.a,
            "B": ControllerSkinPalette.LightMode.b,
            "X": ControllerSkinPalette.LightMode.x,
            "Y": ControllerSkinPalette.LightMode.y
        ],
        backgroundColor: ControllerSkinPalette.LightMode.background,
        borderColor: Color.black.opacity(0.1),
        shadowOpacity: 0.15,
        cornerRadius: 20
    )

    static let custom = WiiUControllerSkin(
        name: "Violet",
        dpadColor: ControllerSkinPalette.Custom.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Custom.a,
            "B": ControllerSkinPalette.Custom.b,
            "X": ControllerSkinPalette.Custom.x,
            "Y": ControllerSkinPalette.Custom.y
        ],
        backgroundColor: ControllerSkinPalette.Custom.background,
        borderColor: ControllerSkinPalette.Custom.dpad.opacity(0.3),
        shadowOpacity: 0.4,
        cornerRadius: 20
    )

    // MARK: - Colour themes

    static let sunsetOrange = WiiUControllerSkin(
        name: "Sunset Orange",
        dpadColor: ControllerSkinPalette.SunsetOrange.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.SunsetOrange.a,
            "B": ControllerSkinPalette.SunsetOrange.b,
            "X": ControllerSkinPalette.SunsetOrange.x,
            "Y": ControllerSkinPalette.SunsetOrange.y
        ],
        backgroundColor: ControllerSkinPalette.SunsetOrange.background.opacity(0.1),
        borderColor: ControllerSkinPalette.SunsetOrange.dpad.opacity(0.3),
        shadowOpacity: 0.4,
        cornerRadius: 20
    )

    static let forestGold = WiiUControllerSkin(
        name: "Forest Gold",
        dpadColor: ControllerSkinPalette.ForestGold.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.ForestGold.a,
            "B": ControllerSkinPalette.ForestGold.b,
            "X": ControllerSkinPalette.ForestGold.x,
            "Y": ControllerSkinPalette.ForestGold.y
        ],
        backgroundColor: ControllerSkinPalette.ForestGold.background,
        borderColor: ControllerSkinPalette.ForestGold.dpad.opacity(0.25),
        shadowOpacity: 0.45,
        cornerRadius: 20
    )
}
