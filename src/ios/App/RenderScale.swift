// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation
#if os(iOS)
import UIKit
#endif

/// How many real pixels the Wii U screen is presented at, as a fraction of the display's
/// own backing scale.
///
/// This only scales the host surface the finished image is presented into (the last blit
/// and the compositor). The engine's internal render targets are untouched, so emulation
/// results don't change.
enum RenderScale: String, CaseIterable, Identifiable {
    /// The display's own scale. Sharpest, and by a wide margin the most expensive.
    case native
    /// Three quarters of native.
    case high
    /// Half of native. On a 2x screen that is one pixel per point - 1366x1024 on the
    /// iPad Pro, still comfortably above the Wii U's own 1280x720, so the console image
    /// is not being downsampled below its source at this setting. On a 3x iPhone that
    /// would be 1.5 pixels per point, under 720 lines in landscape, so `effectiveRenderScale`
    /// raises it to 720 lines there.
    case balanced
    /// Three eighths of native, for when frame rate matters more than edges do.
    case battery

    var id: String { rawValue }

    /// Multiplier applied to the display's backing scale.
    var factor: Double {
        switch self {
        case .native:   return 1.0
        case .high:     return 0.75
        case .balanced: return 0.5
        case .battery:  return 0.375
        }
    }

    var title: String {
        switch self {
        case .native:   return "Native"
        case .high:     return "High"
        case .balanced: return "Balanced"
        case .battery:  return "Battery saver"
        }
    }

    /// One line, in the UI, saying what this costs and what it buys.
    var summary: String {
        switch self {
        case .native:   return "Sharpest. Four times the pixels of Balanced, and the shortest battery life."
        case .high:     return "Slightly softer than Native, noticeably cheaper to draw."
        case .balanced: return "Still above the Wii U's own 720p. The best trade on most games."
        case .battery:  return "Softest, coolest, longest-running. Use it when a game won't hold its frame rate."
        }
    }

    static let storageKey = "renderScale"

    /// What the person chose in Settings, or the preset picked for this device (`deviceDefault`) if they never did.
    static var storedChoice: RenderScale {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = RenderScale(rawValue: raw) else { return deviceDefault }
        return value
    }

    /// What the picture is drawn at now: the running game's own Resolution if it has one (Advanced mode,
    /// see ActiveGameSettings), otherwise `storedChoice`. While the thermal governor is holding Resolution at
    /// battery saver, that wins over the game's own.
    static var current: RenderScale {
        if !ThermalSettings.isHoldingScale,
           let own = ActiveGameSettings.overrides.renderScale.flatMap(RenderScale.init(rawValue:)) {
            return own
        }
        return storedChoice
    }

    /// The preset for someone who never touched Resolution, worked out from this device. The only place
    /// that default is decided.
    ///
    /// Emulation is usually CPU-bound, so extra pixels buy little; the goal is the cheapest preset that still
    /// presents about as many pixels across as the Wii U renders (1280). Most iPads and iPhones land on
    /// Balanced (the newest chips with 7 GiB or more start at High, see below). A small-screened device, where Balanced would be well under 720p (an iPhone SE, say), steps up
    /// to a sharper one. The memory of the device bounds how many pixels that may be, so a 3 GB iPad does not
    /// default to a larger surface than it can afford, and a device with more memory may go further. Battery
    /// saver is only ever chosen by hand.
    static var deviceDefault: RenderScale {
        #if os(iOS)
        // A17 Pro or later and every M-series chip with 7 GiB or more (8 GB and 16 GB iPads and the
        // 8 GB Pro iPhones) have GPU, bandwidth and thermal room for `.high`; see
        // `DeviceCapabilities.startsAtHighRenderScale`. Everything else goes by screen and memory below.
        if DeviceCapabilities.current.startsAtHighRenderScale {
            return .high
        }
        let screen = UIScreen.main
        let nativeScale = Double(screen.scale)
        let longEdge = Double(max(screen.bounds.width, screen.bounds.height)) * nativeScale
        let shortEdge = Double(min(screen.bounds.width, screen.bounds.height)) * nativeScale
        let memoryGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        // Presented pixels the device can comfortably afford, by memory class.
        let pixelBudget: Double = memoryGiB >= 5.0 ? 2_500_000 : (memoryGiB >= 3.0 ? 2_000_000 : 1_600_000)
        let ladder: [RenderScale] = [.balanced, .high, .native]
        func pixels(_ scale: RenderScale) -> Double { longEdge * scale.factor * shortEdge * scale.factor }
        let sharpEnough = ladder.first { longEdge * $0.factor >= 1_100 } ?? .native
        if pixels(sharpEnough) <= pixelBudget { return sharpEnough }
        return ladder.last { pixels($0) <= pixelBudget } ?? .balanced
        #else
        return .balanced
        #endif
    }
}

/// Forces one emulated CPU core, for heat and battery. Costs frame rate roughly in
/// proportion to what it saves.
///
/// Independent of `Favour accuracy` (which also ends up on one core, for a different
/// reason) and of Render Scale, which stays the user's own choice.
enum OneCoreMode {
    static let storageKey = "muffin.cpu.lowPowerMode"
    /// Off by default.
    static let defaultValue = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

/// Speed before picture quality. On, the bridge builds shaders without strict multiply, always
/// compiles them in the background and skips crash breadcrumbs (see
/// cemu_bridge_set_favour_performance), and the app presents the picture at Balanced at most with
/// linear scaling. It never writes `RenderScale.storageKey`: ThermalMonitor already uses that key
/// to remember the person's own choice while it throttles, so the cap is applied on read instead.
/// Favour accuracy wins for everything but the resolution cap, which is global (it changes only the
/// presented picture, never the emulation).
enum FavourPerformance {
    static let storageKey = "muffin.cpu.favourPerformance"
    /// Off by default.
    static let defaultValue = false

    /// The running game's own choice if it has one (Advanced mode), otherwise Settings. Read by the
    /// resolution cap in `effectiveRenderScale`; the launch push uses PerGameSettingsStore directly.
    static var isEnabled: Bool {
        ActiveGameSettings.overrides.favourPerformance
            ?? UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

/// "Full speed renders!" (Settings > Graphics). See cemu_bridge_set_full_speed_renders.
enum FullSpeedRenders {
    static let storageKey = "muffin.render.fullSpeedRenders"
    static let defaultValue = false
    /// What happens the first time a game needs a shader it has never built.
    static let shaderModeKey = "muffin.render.fullSpeedShaderMode"
    enum ShaderMode: Int, CaseIterable, Identifiable {
        /// Build it before drawing: a short hitch, never a missing or flickering object.
        case waitForIt = 0
        /// Draw without it this once: never a hitch, the object can be missing for a moment.
        case keepGoing = 1
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .waitForIt: return "Wait for it"
            case .keepGoing: return "Keep going"
            }
        }
        var summary: String {
            switch self {
            case .waitForIt: return "Never flickers. A short hitch the first time a new effect appears."
            case .keepGoing: return "Never freezes. A new effect can be missing for a moment the first time."
            }
        }
    }
    static let defaultShaderMode = ShaderMode.waitForIt

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
    }
    static var shaderMode: ShaderMode {
        ShaderMode(rawValue: UserDefaults.standard.object(forKey: shaderModeKey) as? Int ?? defaultShaderMode.rawValue)
            ?? defaultShaderMode
    }
    static func applyToBridge() {
        cemu_bridge_set_full_speed_renders(isEnabled, Int32(shaderMode.rawValue))
    }
}

/// How the GamePad surface is sized. The console's GamePad screen is 854x480, so the surface
/// needs no more than about twice that across its long side whatever the display's own scale is.
enum PadSurfaceScale {
    static let maxLongSidePixels: Double = 1708

    static func scale(forPoints size: CGSize, renderScale: Double) -> Double {
        let longSide = Double(max(size.width, size.height))
        guard longSide > 0 else { return renderScale }
        return max(0.5, min(renderScale, maxLongSidePixels / longSide))
    }
}

/// Whether the three emulated Espresso cores get three host threads or share one.
///
/// `auto` decides per game at launch: from the game's own profile, the device's performance-core
/// count and its thermal state (see ios_decide_core_count in CemuBridge.mm). It leans to one
/// core unless the device qualifies (four or more performance cores, memory Tier High or above,
/// nominal thermal state) or the game's profile asks for three, because three host threads draw
/// about three times the power and a part that throttles can end up slower than on one. Three
/// cores stay available as a labelled experiment, globally and per game.
enum CoreMode: String, CaseIterable, Identifiable {
    case auto, single, multi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:   return "Auto"
        case .single: return "One core"
        case .multi:  return "Three cores (Experimental)"
        }
    }

    var summary: String {
        switch self {
        case .auto:   return "Picks per game and per device. Uses three cores when the game's profile asks for them or this device has the performance cores, memory and cooling headroom, and one core otherwise."
        case .single: return "One core. Cooler, and often faster on devices without spare performance cores."
        case .multi:  return "Three cores. Can be faster on a device with spare performance cores and cooling, but heats up quickly on most iPads and has hung some games."
        }
    }

    /// The value cemu_bridge_set_cpu_core_mode() takes.
    var bridgeValue: Int32 {
        switch self {
        case .auto:   return 0
        case .single: return 1
        case .multi:  return 2
        }
    }

    static let storageKey = "muffin.cpu.coreMode"
    /// The on/off switch this replaced. Kept readable so an explicit choice made with it survives.
    private static let legacyKey = "muffin.cpu.multicore"
    static let defaultValue: CoreMode = .auto

    static var current: CoreMode {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: storageKey), let value = CoreMode(rawValue: raw) {
            return value
        }
        if let legacy = defaults.object(forKey: legacyKey) as? Bool {
            return legacy ? .multi : .single
        }
        return defaultValue
    }
}

/// Titles where Auto stays on one core because an earlier three-core run that Auto chose either
/// ended without a clean stop (crash, hang, the app killed) or stalled. Remembered per title.
enum AutoCoreHistory {
    private static let demotedKey = "muffin.cpu.autoDemoted"
    private static let pendingKey = "muffin.cpu.autoMultiPending"

    /// Call at launch. Settles a run that never ended cleanly, then says whether this title is demoted.
    static func isDemotedAtLaunch(gameID: String) -> Bool {
        let defaults = UserDefaults.standard
        var demoted = Set(defaults.stringArray(forKey: demotedKey) ?? [])
        if let pending = defaults.string(forKey: pendingKey) {
            defaults.removeObject(forKey: pendingKey)
            if demoted.insert(pending).inserted {
                defaults.set(demoted.sorted(), forKey: demotedKey)
                cemu_bridge_log_line("CPU cores: \(pending) ended a three-core run without a clean stop, so Auto keeps it on one core from now on")
            }
        }
        return demoted.contains(gameID)
    }

    /// Whether Auto keeps this title on one core, without settling a pending run. For a launch
    /// that does not go through `isDemotedAtLaunch` (the Wii U Menu starting a game).
    static func isDemoted(gameID: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: demotedKey) ?? []).contains(gameID)
    }

    /// Carries a title's entry over when its settings key changes from the file-name id to the title ID. Its pending run is
    /// left alone: that is a live session, settled by the key it started under.
    static func adoptTitleIDKey(from oldID: String, to newID: String) {
        let defaults = UserDefaults.standard
        var demoted = Set(defaults.stringArray(forKey: demotedKey) ?? [])
        guard demoted.contains(oldID) else { return }
        demoted.remove(oldID)
        demoted.insert(newID)
        defaults.set(demoted.sorted(), forKey: demotedKey)
    }

    /// Call once a title that Auto put on three cores has booted.
    static func sessionStarted(gameID: String) {
        UserDefaults.standard.set(gameID, forKey: pendingKey)
    }

    /// Call when the title stops normally.
    static func sessionEnded(gameID: String, stalled: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: pendingKey) == gameID else { return }
        defaults.removeObject(forKey: pendingKey)
        guard stalled else { return }
        var demoted = Set(defaults.stringArray(forKey: demotedKey) ?? [])
        if demoted.insert(gameID).inserted {
            defaults.set(demoted.sorted(), forKey: demotedKey)
            cemu_bridge_log_line("CPU cores: a three-core run of \(gameID) stalled, so Auto keeps it on one core from now on")
        }
    }
}

/// Whether the picture fills the view's own aspect ratio instead of keeping the Wii U's
/// 1280x720, letterboxed.
///
/// This key is the storage; the behaviour lives in the engine. SettingsView pushes changes
/// through cemu_bridge_set_stretch_to_fill() and GameManager re-applies the stored value
/// before each boot, which sets Cemu's fullscreen_scaling.
enum FrameStretch {
    static let storageKey = "muffin.render.stretchToFit"
    static let defaultValue = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

#if os(iOS)
extension UIScreen {
    /// The backing scale to hand the renderer, after the user's render-scale setting.
    /// Floored at 0.5 so the points-to-pixels conversion can't round a dimension to zero.
    ///
    /// Every choice but Battery saver keeps at least the Wii U's own 720 lines on the short side
    /// of the screen, as far as the panel has them: a phone's 390 pt landscape height at half of
    /// a 3x scale is only 585 pixels, which is below the picture the game draws. Devices whose
    /// screen is already taller than that at the chosen scale (every iPad) are unaffected.
    var effectiveRenderScale: Double {
        var choice = RenderScale.current
        // Favour performance caps the picture at Balanced without touching the stored choice.
        if FavourPerformance.isEnabled && choice.factor > RenderScale.balanced.factor {
            choice = .balanced
        }
        var value = Double(scale) * choice.factor
        if choice != .battery {
            let shortSide = Double(min(bounds.width, bounds.height))
            if shortSide > 0 {
                value = max(value, min(720.0 / shortSide, Double(scale)))
            }
        }
        return max(0.5, value)
    }
}
#endif
