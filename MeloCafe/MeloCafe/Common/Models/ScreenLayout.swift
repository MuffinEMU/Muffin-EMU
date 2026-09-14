//
//  ScreenLayout.swift
//  MeloCafe
//
//  Created by Stossy11 on 12/9/2026.
//

import Foundation

enum ScreenLayout: String, CaseIterable {
    case singleScreen
    case bothScreens
    case smallGamePadTopRight

    var string: String {
        switch self {
        case .singleScreen: return "Single Screen"
        case .bothScreens: return "Adaptive (Both Screens)"
        case .smallGamePadTopRight: return "Both Screens (GamePad Top Right)"
        }
    }

    var description: String {
        switch self {
        case .singleScreen:
            return "Only the selected screen renders. Use the swap button to switch between TV and GamePad."
        case .bothScreens:
            return "TV and GamePad automatically adjust: stacked in portrait and side by side in landscape."
        case .smallGamePadTopRight:
            return "A small GamePad appears at the top right in its own column beside the TV View."
        }
    }
    
    var showsBothScreens: Bool { self != .singleScreen }

    static var initialValue: ScreenLayout {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "screenLayout"),
           let layout = ScreenLayout(rawValue: stored) {
            return layout
        }
        let layout: ScreenLayout = defaults.bool(forKey: "showBothScreens") ? (defaults.bool(forKey: "smallGamePadTopRight") ? .smallGamePadTopRight : .bothScreens) : .singleScreen
        defaults.set(layout.rawValue, forKey: "screenLayout")
        return layout
    }
}
