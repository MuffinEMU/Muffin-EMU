// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// Thermal settings and state that other code reads from anywhere. Outside the main-actor class below
/// so RenderScale.current and the Advanced registry can use them without hopping actors.
enum ThermalSettings {
    static let scaleKey = "muffin.thermal.scaleBeforeThrottle"

    /// The remembered Resolution is stored for as long as a throttle is in effect.
    static var isHoldingScale: Bool { UserDefaults.standard.string(forKey: scaleKey) != nil }

    /// Which thermal state starts the automatic cool-down (Settings > CPU, Advanced mode).
    static let thresholdKey = "muffin.thermal.coolDownThreshold"
    static let defaultThreshold = Threshold.serious

    enum Threshold: String, CaseIterable, Identifiable {
        /// iOS has started to throttle. The default: lowering the pixel count gives frames back.
        case serious
        /// iOS is throttling hard. The game keeps full quality for longer.
        case critical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .serious:  return "Serious"
            case .critical: return "Critical"
            }
        }

        var summary: String {
            switch self {
            case .serious:  return "Cools down as soon as iOS starts slowing the device."
            case .critical: return "Waits until iOS is slowing the device hard. The game keeps its quality longer, and may stutter or run hot first."
            }
        }
    }

    static var threshold: Threshold {
        Threshold(rawValue: UserDefaults.standard.string(forKey: thresholdKey) ?? "") ?? defaultThreshold
    }
}

/// Reads `ProcessInfo.thermalState` and, when the device gets hot, lowers Render Scale to
/// battery saver and (at `.critical`) slows the emulated cores until it cools.
///
/// The response is Render Scale rather than core count because core count is fixed when the
/// title's host threads start, while Render Scale takes effect on the next frame. At
/// `.serious` and above iOS is already throttling the CPU and GPU, so rendering fewer pixels
/// at a stable rate beats rendering more at a collapsing one.
@MainActor
final class ThermalMonitor: ObservableObject {
    static let shared = ThermalMonitor()

    /// Whether the automatic response is armed. On by default.
    static let autoThrottleKey = "muffin.thermal.autoReduceQuality"
    static let autoThrottleDefault = true

    @Published private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// The scale the user actually chose, remembered so it can be restored exactly when
    /// the device cools.
    private var userChosenScale: RenderScale? {
        get { RenderScale(rawValue: UserDefaults.standard.string(forKey: Self.scaleBeforeThrottleKey) ?? "") }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.scaleBeforeThrottleKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.scaleBeforeThrottleKey)
            }
        }
    }

    /// Persisted so a restore survives the app being killed while hot; otherwise Render Scale
    /// would stay pinned at battery saver with nothing remembering the previous value.
    private static let scaleBeforeThrottleKey = ThermalSettings.scaleKey
    private var isThrottling = false
    private var observing = false

    /// Told, in words for a player, when the automatic response starts or ends. GameManager
    /// shows it over the game; the response used to lower the picture quality with no sign
    /// at all. Not called for the title stopping or the setting being switched off.
    var onNotice: (@MainActor (String) -> Void)?

    private init() {}

    var autoThrottleEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoThrottleKey) as? Bool ?? Self.autoThrottleDefault
    }

    /// Human-readable, for the device report and the launch log.
    var description: String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious (iOS is throttling)"
        case .critical: return "critical (iOS is throttling hard)"
        @unknown default: return "unknown"
        }
    }

    /// Undoes a throttle the app never got to release. If the key is set on a cold start,
    /// the last run was killed mid-throttle and the stored render scale is ours.
    private func restoreScaleIfKilledWhileThrottled() {
        guard let chosen = userChosenScale else { return }
        UserDefaults.standard.set(chosen.rawValue, forKey: RenderScale.storageKey)
        userChosenScale = nil
        cemu_bridge_log_line("iOS thermal: last run ended while throttled; restored render scale to \(chosen.rawValue)")
    }

    /// The threshold was changed in Settings: apply it to the state the device is in now.
    func thresholdChanged() {
        applyAutoThrottleIfNeeded()
    }

    /// Idempotent.
    func startObserving() {
        guard !observing else { return }
        observing = true
        // Before anything reads Render Scale.
        restoreScaleIfKilledWhileThrottled()
        state = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                // Hop to the main actor rather than assuming the delivery queue.
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

    /// Microseconds of sleep per reschedule for each emulated core. `.serious` doesn't sleep
    /// (iOS has already lowered the clocks and the resolution drop is the relief);
    /// `.critical` uses a small sleep to get out of the danger zone quickly.
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
            cooldownTask?.cancel()
            cooldownTask = nil
            if isThrottling { unwind(reason: "auto-reduce turned off") }
            return
        }

        // Serious and critical by default; with the threshold on Critical, only critical.
        let shouldThrottle = state == .critical || (state == .serious && ThermalSettings.threshold == .serious)

        // Re-applied on every change while hot so .serious -> .critical escalates.
        let micros: UInt32 = shouldThrottle ? throttleMicros(for: state) : 0
        cemu_bridge_set_thermal_throttle_micros(micros)

        if shouldThrottle && !isThrottling {
            // Remember the user's choice before overwriting it.
            userChosenScale = RenderScale.storedChoice
            // Battery saver, and only from .serious upward.
            UserDefaults.standard.set(RenderScale.battery.rawValue, forKey: RenderScale.storageKey)
            isThrottling = true
            DisplayRouter.shared.reapplyRenderScale(reason: "thermal state \(description)")
            cemu_bridge_log_line("iOS thermal: reduced render scale to battery saver while hot")
            onNotice?("The device is hot, so MuffinEMU made the picture softer to keep the game running. It goes back when the device cools.")
            cooldownTask?.cancel()
            cooldownTask = nil
        } else if shouldThrottle {
            cooldownTask?.cancel()
            cooldownTask = nil
        } else if isThrottling && cooldownTask == nil {
            cooldownTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.cooldownTask = nil
                guard self.isThrottling else { return }
                self.unwind(reason: "cooled to \(self.description)")
                self.onNotice?("The device has cooled down. The picture is back to normal.")
            }
        }
    }

    private var cooldownTask: Task<Void, Never>?

    /// Puts everything back. Shared by every exit path: cooling down, the setting being
    /// switched off, and the title stopping.
    private func unwind(reason: String) {
        cemu_bridge_set_thermal_throttle_micros(0)
        restoreChosenScale()
        isThrottling = false
        DisplayRouter.shared.reapplyRenderScale(reason: "thermal: \(reason)")
        cemu_bridge_log_line("iOS thermal: released the governor and restored the chosen render scale (\(reason))")
    }

    /// Puts the remembered Resolution back, unless the user picked a different one while
    /// throttled (then their new choice stands).
    private func restoreChosenScale() {
        if let restored = userChosenScale, RenderScale.storedChoice == .battery {
            UserDefaults.standard.set(restored.rawValue, forKey: RenderScale.storageKey)
        }
        userChosenScale = nil
    }

    /// Called when a title stops (and before a settings reset), so a throttle is never left
    /// holding the user's Render Scale at battery saver.
    func titleStopped() {
        cooldownTask?.cancel()
        cooldownTask = nil
        // Cleared unconditionally: the governor is a C++ atomic that outlives any one title.
        cemu_bridge_set_thermal_throttle_micros(0)
        guard isThrottling else { return }
        restoreChosenScale()
        isThrottling = false
        cemu_bridge_log_line("iOS thermal: title stopped while throttled; governor released and render scale restored")
    }
}
