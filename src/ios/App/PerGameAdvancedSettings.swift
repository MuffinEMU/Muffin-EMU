// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Per-game options that exist in Advanced mode only (see AdvancedSettings): Resolution, scaling
/// filters, Favour performance, Steady frame rate, One-core mode, screen layout, controller auto-hide
/// and the performance overlay. Each follows the matching global setting until a game is given its own
/// value. The values live in GameOverrides and the screen is GameOptionsView (PerGameSettings.swift);
/// this file reads them back and gives that screen its bindings.
///
/// Every `effective...` function ends up in GameManager's launch push and TitleSwitchSettings.apply,
/// like the three older per-game options, and ignores the Advanced ones while Settings mode is Basic.
extension PerGameSettingsStore {
    /// Changes one game's overrides in place. Setting a field back to nil follows the global setting again.
    func updateOverrides(for gameID: String, _ change: (inout GameOverrides) -> Void) {
        var next = overrides(for: gameID)
        change(&next)
        setOverrides(next, for: gameID)
    }

    // MARK: Bindings for GameOptionsView's menus

    /// An on/off override as a three-way choice: nil follows Settings.
    func onOffChoice(_ path: WritableKeyPath<GameOverrides, Bool?>, for gameID: String) -> Binding<OverrideChoice> {
        Binding(
            get: {
                switch self.overrides(for: gameID)[keyPath: path] {
                case .none: return .followSettings
                case .some(true): return .on
                case .some(false): return .off
                }
            },
            set: { choice in
                self.updateOverrides(for: gameID) { next in
                    switch choice {
                    case .followSettings: next[keyPath: path] = nil
                    case .on: next[keyPath: path] = true
                    case .off: next[keyPath: path] = false
                    }
                }
            })
    }

    /// "" follows Settings, otherwise the value's own raw string. An unknown stored value reads as "".
    func textChoice(_ path: WritableKeyPath<GameOverrides, String?>, known: [String], for gameID: String) -> Binding<String> {
        Binding(
            get: {
                guard let raw = self.overrides(for: gameID)[keyPath: path], known.contains(raw) else { return "" }
                return raw
            },
            set: { raw in self.updateOverrides(for: gameID) { $0[keyPath: path] = raw.isEmpty ? nil : raw } })
    }

    /// -1 follows Settings, otherwise the value's own raw number. An unknown stored value reads as -1.
    func numberChoice(_ path: WritableKeyPath<GameOverrides, Int?>, known: [Int], for gameID: String) -> Binding<Int> {
        Binding(
            get: {
                guard let raw = self.overrides(for: gameID)[keyPath: path], known.contains(raw) else { return -1 }
                return raw
            },
            set: { raw in self.updateOverrides(for: gameID) { $0[keyPath: path] = raw < 0 ? nil : raw } })
    }

    // MARK: Global values, read the way GameManager reads them

    var globalFavourPerformance: Bool {
        UserDefaults.standard.object(forKey: FavourPerformance.storageKey) as? Bool ?? FavourPerformance.defaultValue
    }

    var globalFullSpeedRenders: Bool {
        UserDefaults.standard.object(forKey: FullSpeedRenders.storageKey) as? Bool ?? FullSpeedRenders.defaultValue
    }

    var globalFullSpeedShaderMode: FullSpeedRenders.ShaderMode {
        FullSpeedRenders.ShaderMode(rawValue: UserDefaults.standard.object(forKey: FullSpeedRenders.shaderModeKey) as? Int
            ?? FullSpeedRenders.defaultShaderMode.rawValue) ?? FullSpeedRenders.defaultShaderMode
    }

    var globalOneCoreMode: Bool {
        UserDefaults.standard.object(forKey: OneCoreMode.storageKey) as? Bool ?? OneCoreMode.defaultValue
    }

    var globalUpscaleFilter: ScaleFilter {
        ScaleFilter(rawValue: UserDefaults.standard.object(forKey: UpscaleFilterSetting.storageKey) as? Int
            ?? UpscaleFilterSetting.defaultValue.rawValue) ?? UpscaleFilterSetting.defaultValue
    }

    var globalDownscaleFilter: ScaleFilter {
        ScaleFilter(rawValue: UserDefaults.standard.object(forKey: DownscaleFilterSetting.storageKey) as? Int
            ?? DownscaleFilterSetting.defaultValue.rawValue) ?? DownscaleFilterSetting.defaultValue
    }

    var globalScreenLayout: ScreenLayout { ScreenLayout.initialValue }

    var globalAutoHideControls: Bool {
        UserDefaults.standard.object(forKey: ControllerLayoutSettings.autoHideWithControllerKey) as? Bool
            ?? ControllerLayoutSettings.defaultAutoHideWithController
    }

    var globalOverlayPosition: ScreenPosition {
        ScreenPosition(rawValue: UserDefaults.standard.object(forKey: OverlaySettings.positionKey) as? Int
            ?? OverlaySettings.defaultPosition.rawValue) ?? OverlaySettings.defaultPosition
    }

    // MARK: What a launch uses: the game's own value first, the global one underneath

    func effectiveRenderScale(for gameID: String) -> RenderScale {
        activeOverrides(for: gameID).renderScale.flatMap(RenderScale.init(rawValue:)) ?? RenderScale.storedChoice
    }

    func effectiveUpscaleFilter(for gameID: String) -> ScaleFilter {
        activeOverrides(for: gameID).upscaleFilter.flatMap(ScaleFilter.init(rawValue:)) ?? globalUpscaleFilter
    }

    func effectiveDownscaleFilter(for gameID: String) -> ScaleFilter {
        activeOverrides(for: gameID).downscaleFilter.flatMap(ScaleFilter.init(rawValue:)) ?? globalDownscaleFilter
    }

    func effectiveFavourPerformance(for gameID: String) -> Bool {
        activeOverrides(for: gameID).favourPerformance ?? globalFavourPerformance
    }

    func effectiveFullSpeedRenders(for gameID: String) -> Bool {
        activeOverrides(for: gameID).fullSpeedRenders ?? globalFullSpeedRenders
    }

    func effectiveFullSpeedShaderMode(for gameID: String) -> FullSpeedRenders.ShaderMode {
        activeOverrides(for: gameID).fullSpeedShaderMode.flatMap(FullSpeedRenders.ShaderMode.init(rawValue:))
            ?? globalFullSpeedShaderMode
    }

    func effectiveOneCoreMode(for gameID: String) -> Bool {
        activeOverrides(for: gameID).oneCoreMode ?? globalOneCoreMode
    }

    /// The overlay's corner for this game. Off turns it off; On uses the corner chosen in Settings, or top
    /// left when Settings has the overlay off.
    func effectiveOverlayPosition(for gameID: String) -> ScreenPosition {
        switch activeOverrides(for: gameID).performanceOverlay {
        case .none:        return globalOverlayPosition
        case .some(false): return .disabled
        case .some(true):  return globalOverlayPosition == .disabled ? .topLeft : globalOverlayPosition
        }
    }

    /// The two filters a launch pushes (upscale, downscale). Favour performance swaps both for linear, the
    /// cheapest blend, unless the game favours accuracy, which wins as it does in the bridge.
    func filtersToPush(for gameID: String) -> (upscale: Int32, downscale: Int32) {
        if effectiveFavourPerformance(for: gameID) && !effectiveFavourAccuracy(for: gameID) {
            return (Int32(ScaleFilter.linear.rawValue), Int32(ScaleFilter.linear.rawValue))
        }
        return (Int32(effectiveUpscaleFilter(for: gameID).rawValue), Int32(effectiveDownscaleFilter(for: gameID).rawValue))
    }

    /// Pushes Steady frame rate for this game (both the switch and the shader choice).
    func applyFullSpeedRenders(for gameID: String) {
        cemu_bridge_set_full_speed_renders(effectiveFullSpeedRenders(for: gameID),
                                           Int32(effectiveFullSpeedShaderMode(for: gameID).rawValue))
    }
}
