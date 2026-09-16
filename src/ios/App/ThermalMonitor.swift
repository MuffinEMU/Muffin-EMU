import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// What iOS itself thinks the device's temperature is, and an optional automatic response
/// to it.
///
/// # Why this exists
///
/// Reported 2026-09-15, measured with a third-party thermal app: running a title in
/// MuffinEMU drives the device to "HOT!", while the same title on MeloCafe sits at "warm,
/// but a little bit hot". Until now the app had no idea - there was not a single read of
/// `ProcessInfo.thermalState` anywhere in the tree, so the emulator could not see what a
/// third-party app could, could not say so, and could not react.
///
/// The underlying cause is already understood and is not a mystery: MuffinEMU runs three
/// emulated CPU cores on three host threads where MeloCafe's default runs one (see
/// `LowPowerMode`). This does not replace that. It is the part that cannot be fixed by a
/// setting someone has to know to find, because thermal pressure arrives mid-game.
///
/// # Why the response is render scale and not core count
///
/// Core count is fixed the moment `_LaunchTitleThread()` starts its host threads, so it
/// cannot change without relaunching the title - useless as a response to something
/// happening right now. Render scale can: `DisplayRouter.tvGeometry()` reads
/// `UIScreen.effectiveRenderScale` fresh on every call, and
/// `cemu_bridge_resize_render_surface` pushes it into `phys_width/phys_height` and the
/// layer's drawable size, so it takes effect on the next frame.
///
/// # Why reducing quality when hot is not a loss
///
/// This is the part worth being precise about, because "it gets worse when it is hot"
/// sounds like a downgrade. At `.serious` and `.critical`, **iOS is already throttling the
/// CPU and GPU itself** - the frame rate has already dropped, and it will keep dropping
/// while the device stays there. Cutting the pixel count is how you give those frames
/// back. Rendering fewer pixels at a stable rate beats rendering more at a collapsing one,
/// and it is also the fastest route back to a temperature where the OS stops throttling at
/// all. So this protects speed rather than trading it away, which is why it can default on
/// in a port whose stated direction is speed first.
@MainActor
final class ThermalMonitor: ObservableObject {
    static let shared = ThermalMonitor()

    /// Whether the automatic response is armed. See the type's doc comment for why this
    /// defaults ON even though MuffinEMU otherwise defaults to the fast path.
    static let autoThrottleKey = "muffin.thermal.autoReduceQuality"
    static let autoThrottleDefault = true

    @Published private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// The scale the user actually chose, remembered so it can be restored exactly when
    /// the device cools. Without this, "restore" would have to guess, and a guess here
    /// silently overwrites a deliberate choice - the same mistake Low Power Mode
    /// deliberately avoids by not touching Render Scale at all.
    private var userChosenScale: RenderScale?
    private var isThrottling = false
    private var observing = false

    private init() {}

    var autoThrottleEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoThrottleKey) as? Bool ?? Self.autoThrottleDefault
    }

    /// Human-readable, for the device report and the launch log. Deliberately says what
    /// iOS reports rather than inventing a temperature - the app has no thermometer, only
    /// this four-state signal.
    var description: String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious (iOS is throttling)"
        case .critical: return "critical (iOS is throttling hard)"
        @unknown default: return "unknown"
        }
    }

    /// Idempotent. Called from the same place DisplayRouter's observation starts, so there
    /// is no new lifecycle to get wrong.
    func startObserving() {
        guard !observing else { return }
        observing = true
        state = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                // The notification is documented to arrive on an arbitrary queue despite
                // the .main queue argument in some OS versions; hopping through a
                // MainActor Task rather than assuming is the same defensive shape
                // DisplayRouter.startObserving() already uses for its own observers.
                Task { @MainActor in self?.thermalStateChanged() }
            }
        cemu_bridge_log_line("iOS thermal: monitoring started, state \(description)")
    }

    private func thermalStateChanged() {
        let newState = ProcessInfo.processInfo.thermalState
        guard newState != state else { return }
        state = newState
        cemu_bridge_log_line("iOS thermal: state changed to \(description)")
        applyAutoThrottleIfNeeded()
    }

    /// How hard each emulated core is slowed, in microseconds of sleep per reschedule.
    ///
    /// Two steps rather than one switch, because the two thermal states mean different
    /// things. `.serious` is "iOS has started throttling"; `.critical` is "iOS is
    /// throttling hard and may start killing things". Applying the heavier value at
    /// `.serious` would cost speed nobody asked for; applying only the lighter one at
    /// `.critical` would not buy enough headroom to get back out.
    ///
    /// These were 250us and 1000us, and calling them "small" was the mistake. The sleep
    /// is per RESCHEDULE, not per frame, and a reschedule is over in tens of
    /// microseconds - so the number is not a small addition to a long timeslice, it is a
    /// multiplier on a short one. 1000us per reschedule does not shave a few percent off
    /// the duty cycle, it can cost an order of magnitude.
    ///
    /// Worse, sleep_for under a millisecond does not sleep for what it is asked on
    /// Darwin. Timer granularity and scheduler wakeup latency put a floor of roughly
    /// 50-100us under any sleep, and coalescing can stretch a sub-millisecond request
    /// toward a full millisecond - so the 250us step was likely costing several times
    /// what it read as.
    ///
    /// So `.serious` no longer sleeps at all. It still drops the render scale, which is
    /// real thermal relief with a predictable cost, and it lets iOS's own throttling do
    /// the CPU-side work rather than stacking ours on top of it - at `.serious` iOS has
    /// already taken the clocks down, and sleeping the cores as well was paying twice.
    /// `.critical` keeps a much smaller sleep, because "may start killing the process"
    /// is worth real speed to escape.
    ///
    /// The other half of this is that single-core is now the default (see
    /// ios_apply_cpu_mode), so the device reaches these states far less often.
    private func throttleMicros(for state: ProcessInfo.ThermalState) -> UInt32 {
        switch state {
        case .serious:  return 0
        case .critical: return 125
        default:        return 0
        }
    }

    private func applyAutoThrottleIfNeeded() {
        guard autoThrottleEnabled else {
            // Turning the setting off mid-throttle has to unwind, not freeze in place.
            if isThrottling { unwind(reason: "auto-reduce turned off") }
            return
        }

        let shouldThrottle = (state == .serious || state == .critical)

        // The CPU governor is re-applied on EVERY change while hot, not only on the
        // transition into it, because .serious -> .critical has to escalate.
        // throttleMicros() already returns 0 for every state below .serious, so this is
        // the same value either way - written out rather than relying on the ternary to
        // infer UInt32 for the literal.
        let micros: UInt32 = shouldThrottle ? throttleMicros(for: state) : 0
        cemu_bridge_set_thermal_throttle_micros(micros)

        if shouldThrottle && !isThrottling {
            // Remember what the user picked BEFORE overwriting it, so cooling restores
            // their choice rather than a default.
            userChosenScale = RenderScale.current
            // .battery, not .balanced, and only from .serious upward. By the time iOS
            // says serious it is already throttling, so a half-measure spends the cost of
            // a resolution change without buying enough headroom to get back out of it.
            UserDefaults.standard.set(RenderScale.battery.rawValue, forKey: RenderScale.storageKey)
            isThrottling = true
            DisplayRouter.shared.reapplyRenderScale(reason: "thermal state \(description)")
            cemu_bridge_log_line("iOS thermal: reduced render scale to battery saver while hot")
        } else if !shouldThrottle && isThrottling {
            unwind(reason: "cooled to \(description)")
        }
    }

    /// Puts everything back, in one place, so every exit path unwinds identically -
    /// cooling down, the setting being switched off, the title stopping, and a settings
    /// reset. Four callers with four slightly different unwinds is how one of them ends
    /// up leaving the user's Render Scale pinned at battery saver forever.
    private func unwind(reason: String) {
        cemu_bridge_set_thermal_throttle_micros(0)
        if let restored = userChosenScale {
            UserDefaults.standard.set(restored.rawValue, forKey: RenderScale.storageKey)
        }
        userChosenScale = nil
        isThrottling = false
        DisplayRouter.shared.reapplyRenderScale(reason: "thermal: \(reason)")
        cemu_bridge_log_line("iOS thermal: released the governor and restored the chosen render scale (\(reason))")
    }

    /// Called when a title stops. A throttle left armed across launches would leave the
    /// user's Render Scale permanently overwritten with battery saver, which is exactly
    /// the "silently overwrote a deliberate choice" failure this class is built to avoid.
    func titleStopped() {
        // The core governor is cleared unconditionally, even when this monitor does not
        // think it is throttling: it lives in a C++ atomic that outlives any one title,
        // and a stale non-zero value would silently slow the NEXT launch with no UI
        // anywhere admitting it.
        cemu_bridge_set_thermal_throttle_micros(0)
        guard isThrottling else { return }
        if let restored = userChosenScale {
            UserDefaults.standard.set(restored.rawValue, forKey: RenderScale.storageKey)
        }
        userChosenScale = nil
        isThrottling = false
        cemu_bridge_log_line("iOS thermal: title stopped while throttled; governor released and render scale restored")
    }
}
