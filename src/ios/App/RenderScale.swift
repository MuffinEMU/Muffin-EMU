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
    /// is not being downsampled below its source at this setting.
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

    /// Until someone picks a value: `.balanced` on most devices, because the CPU is usually the
    /// bottleneck and extra GPU pixels buy nothing. iPads with 8 GB or more (M-series, whose GPUs
    /// and memory bandwidth are several times an A12Z's) start at `.high`.
    static var deviceDefault: RenderScale {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad && ProcessInfo.processInfo.physicalMemory >= 7_500_000_000 {
            return .high
        }
        #endif
        return .balanced
    }

    static var current: RenderScale {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = RenderScale(rawValue: raw) else { return deviceDefault }
        return value
    }
}

/// Forces one emulated CPU core, for heat and battery. Costs frame rate roughly in
/// proportion to what it saves.
///
/// Independent of `Favour accuracy` (which also ends up on one core, for a different
/// reason) and of Render Scale, which stays the user's own choice.
enum LowPowerMode {
    static let storageKey = "muffin.cpu.lowPowerMode"
    /// Off by default.
    static let defaultValue = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
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
/// core, because on a fanless A12Z iPad Pro three host threads drew about three times the power,
/// the SoC throttled within a minute, and Wind Waker HD ran 4-20 fps against 40-60 on one. Three
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
        case .auto:   return "Picks per game and per device. Uses one core unless the game's profile asks for three and this device has the headroom."
        case .single: return "One core. Cooler, and usually faster on this hardware."
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
    var effectiveRenderScale: Double {
        max(0.5, Double(scale) * RenderScale.current.factor)
    }
}
#endif
