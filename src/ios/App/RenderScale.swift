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

    /// What the person chose, or the preset picked for this device (`deviceDefault`) if they never did.
    static var current: RenderScale {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = RenderScale(rawValue: raw) else { return deviceDefault }
        return value
    }

    /// The preset for someone who never touched Resolution, worked out from this device.
    ///
    /// Emulation is usually CPU-bound, so extra pixels buy little; the goal is the cheapest preset that still
    /// presents about as many pixels across as the Wii U renders (1280). An iPad Pro or iPhone Pro lands on
    /// Balanced. A small-screened device, where Balanced would be well under 720p (an iPhone SE, say), steps up
    /// to a sharper one. The memory of the device bounds how many pixels that may be, so a 3 GB iPad does not
    /// default to a larger surface than it can afford, and a device with more memory may go further. Battery
    /// saver is only ever chosen by hand.
    static var deviceDefault: RenderScale {
        #if os(iOS)
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
    var effectiveRenderScale: Double {
        max(0.5, Double(scale) * RenderScale.current.factor)
    }
}
#endif
