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

    /// Where it starts when the player has not chosen: `.balanced` on most devices, because the
    /// CPU is the bottleneck and extra GPU pixels buy nothing, and `.high` on an A17 Pro or later
    /// and on M-series iPads, which have room for them (`DeviceCapabilities.defaultRenderScale`).
    static var defaultValue: RenderScale { DeviceCapabilities.current.defaultRenderScale }

    static var current: RenderScale {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = RenderScale(rawValue: raw) else { return defaultValue }
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

/// Whether the three emulated Espresso cores get three host threads or share one.
///
/// One is the default: three host threads on a fanless device such as the A12Z iPad Pro
/// draw about three times the power, the SoC heats up within a minute and iOS lowers the
/// clocks, so it usually runs slower than one thread. Kept as a switch because a
/// better-cooled device may come out ahead.
enum MulticoreMode {
    static let storageKey = "muffin.cpu.multicore"
    static let defaultValue = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
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
        let choice = RenderScale.current
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
