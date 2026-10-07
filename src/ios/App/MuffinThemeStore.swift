// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import Combine

/// One full MuffinTheme palette as data: every token is a light/dark hex pair, so themes are
/// swappable at runtime. The icon-matched themes in MuffinThemePresets.swift are derived
/// from each icon's artwork; Bakery is the app's original palette.
struct MuffinThemeDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    /// Matches AppIconOption.id from IconManifest when this theme was derived from an icon's
    /// art; lets the picker show "matches your current icon".
    let iconId: String

    let backgroundTopLight: String, backgroundTopDark: String
    let backgroundBottomLight: String, backgroundBottomDark: String
    let muffinTopLightLight: String, muffinTopLightDark: String
    let muffinTopDarkLight: String, muffinTopDarkDark: String
    let creamLight: String, creamDark: String
    let wrapperLight: String, wrapperDark: String
    let blueberryNavyLight: String, blueberryNavyDark: String
    let pixelBlueLight: String, pixelBlueDark: String
    let blushPinkLight: String, blushPinkDark: String
    let brownDarkestLight: String, brownDarkestDark: String
    let brownDarkLight: String, brownDarkDark: String
    let brownMidLight: String, brownMidDark: String
    let sparkleCreamLight: String, sparkleCreamDark: String
    let shadowLight: String, shadowDark: String

    /// Optional multi-stop background gradient. Empty means backgroundTop -> backgroundBottom.
    /// The two arrays must be the same length; each index is one stop's light/dark pair.
    var backgroundStopsLight: [String] = []
    var backgroundStopsDark: [String] = []

    /// Where each stop sits, 0 at the top of the screen and 1 at the bottom. Empty spreads them
    /// evenly. Must match the stop arrays in length and ascend; otherwise the even spread is used.
    var backgroundStopLocations: [Double] = []

    static func == (lhs: MuffinThemeDefinition, rhs: MuffinThemeDefinition) -> Bool { lhs.id == rhs.id }
}

/// The source of truth for which MuffinTheme palette is active. MuffinTheme's static
/// properties read through it.
///
/// Independent of the icon picker: choosing an icon doesn't change the theme and vice versa;
/// a theme's `iconId` is only used to label it "matches your icon".
final class MuffinThemeStore: ObservableObject {
    static let shared = MuffinThemeStore()

    @Published private(set) var current: MuffinThemeDefinition

    private static let storageKey = "muffin.theme.selectedId"

    private init() {
        let storedId = UserDefaults.standard.string(forKey: Self.storageKey)
        current = MuffinThemePresets.all.first(where: { $0.id == storedId }) ?? MuffinThemePresets.bakery
    }

    func select(_ theme: MuffinThemeDefinition) {
        guard theme.id != current.id else { return }
        current = theme
        UserDefaults.standard.set(theme.id, forKey: Self.storageKey)
    }
}
