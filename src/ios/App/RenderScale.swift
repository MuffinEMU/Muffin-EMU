import Foundation
#if os(iOS)
import UIKit
#endif

/// How many real pixels the Wii U screen is presented at, as a fraction of the display's
/// own backing scale.
///
/// This is the cheapest performance lever in the app. The 2026-08-27 device log presented
/// at 2732x2048 - full native retina on the iPad Pro - which is 5.6 million pixels of
/// swapchain, blit and composite work every single frame, for a console whose own
/// framebuffer is 1280x720. `.balanced` quarters that pixel count.
///
/// What this does NOT change is worth being precise about, because "resolution setting"
/// in an emulator usually means the opposite of what it means here: the engine's internal
/// Latte render targets are untouched. The game is still drawn at the resolution the game
/// asks for, and every emulated result is bit-for-bit what it was. This scales only the
/// host surface that finished image is presented into - the last blit and the compositor -
/// so no emulation behaviour can change with it.
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

    /// `.balanced`, not `.native`, on purpose. Every launch so far has run the PPC
    /// interpreter with the recompiler off (see `cemu_bridge_cpu_mode`), so the CPU is
    /// the bottleneck by an enormous margin and there is nothing to be gained by also
    /// asking the GPU for four times the pixels. Someone who never opens Settings should
    /// get the setting that makes the emulator fastest, not the one that makes a still
    /// screenshot sharpest.
    static var current: RenderScale {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = RenderScale(rawValue: raw) else { return .balanced }
        return value
    }
}

/// One emulated CPU core instead of three, for heat and battery.
///
/// # Why this is the lever, measured rather than guessed
///
/// Reported 2026-09-15: the same title runs cool on MeloCafe and gets hot fast on
/// MuffinEMU. MeloCafe is not doing anything clever - it is doing a third of the work.
///
/// On iOS the core's `GetCPUMode()` returns the config value unresolved, and
/// `_LaunchTitleThread()` only starts the three emulated CPU cores on their own host
/// threads for the two explicit Multicore modes. MeloCafe's default is `Auto`, which
/// therefore runs every title on ONE host thread. MuffinEMU's bridge always writes an
/// explicit mode (it has to - see `ios_apply_cpu_mode`) and picks Multicore, because
/// speed first is this port's whole point. So MuffinEMU runs THREE.
///
/// Those host threads live in the `while (true)` loop at the bottom of
/// `coreinit_Thread.cpp`, which reschedules without ever sleeping. Three of them resident
/// on a fanless A12Z is about three times the sustained CPU power draw of one. There is
/// no frame limiter in the engine to cap it and no thermal governor of our own.
///
/// # What this does NOT do, deliberately
///
/// It does not touch shader compilation, Vulkan barriers or GX2DrawDone sync. That is
/// what `Favour accuracy` does, and all three of those make the machine do MORE work -
/// the opposite of what something called Low Power should do. The two settings both end
/// up asking for one core, for unrelated reasons, and are kept separate for that reason.
///
/// It also does not change Render Scale. That is a real GPU-side lever and it is already
/// a four-way setting the user controls directly (`RenderScale` above, defaulting to
/// `.balanced`); quietly overriding someone's explicit choice from a different switch is
/// worse than leaving it to them. Anyone chasing heat should turn this on AND drop Render
/// Scale - the footer says so.
///
/// # Honesty
///
/// This costs frame rate, roughly in proportion to what it saves. It is a trade, not a
/// free win, and the toggle's own subtitle says so rather than selling it.
enum LowPowerMode {
    static let storageKey = "muffin.cpu.lowPowerMode"
    /// Off. MuffinEMU's stated direction is speed and raw power first, and silently
    /// shipping everyone the slow path to fix a thermal complaint would be choosing for
    /// people who did not ask.
    static let defaultValue = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

/// Whether the picture fills the view's own aspect ratio instead of keeping the Wii U's
/// 1280x720, letterboxed. A viewer choice, not a correctness fix: it exists for someone
/// who would rather fill every pixel of an odd-shaped screen than see bars on two sides.
///
/// This key is the storage; the behaviour lives in the engine. SettingsView pushes changes
/// through cemu_bridge_set_stretch_to_fill() and GameManager re-applies the stored value
/// before each boot, which sets Cemu's own fullscreen_scaling - the value
/// LatteRenderTarget_getScreenImageArea() uses to size the real output blit.
///
/// It previously described createScreenQuad() in src/ios/Rendering/MetalRenderer.swift as
/// the consumer. That function is real but unreachable: it belongs to
/// AdvancedMetalRenderer, which nothing in the tree ever instantiates, so isEnabled below
/// had no reachable reader and the Settings toggle did nothing. Reading it directly is
/// therefore not how the setting takes effect - see the two call sites above.
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
    ///
    /// Floored at 0.5 rather than at 1.0. `CAMetalLayer` is perfectly happy with a
    /// `contentsScale` below 1, and the floor exists only so that the bridge's
    /// points-to-pixels conversion (`phys_width = width * dpiScale`) can never round a
    /// real dimension down toward zero on some future 1x display.
    var effectiveRenderScale: Double {
        max(0.5, Double(scale) * RenderScale.current.factor)
    }
}
#endif
