// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import TouchLabCore

/// The one stick maths and the one set of stick settings, for every control scheme: this pad,
/// the new pad system (preview) and each TouchLab style. The maths itself lives in the
/// TouchLab package (`StickMath.value`), so a deadzone, curve, gate or calibration means the
/// same thing wherever it is read. Keys and defaults are `ControllerLayoutSettings`'.
enum SharedStick {
    /// The stored calibration string for a stick ("" = none).
    static func calibrationKey(left: Bool) -> String {
        left ? ControllerLayoutSettings.stickCalibrationLeftKey : ControllerLayoutSettings.stickCalibrationRightKey
    }

    static func calibration(left: Bool, defaults: UserDefaults = .standard) -> StickCalibration {
        StickCalibration(encoded: defaults.string(forKey: calibrationKey(left: left)) ?? "")
    }

    static func save(_ calibration: StickCalibration, left: Bool, defaults: UserDefaults = .standard) {
        if calibration.isIdentity {
            defaults.removeObject(forKey: calibrationKey(left: left))
        } else {
            defaults.set(calibration.encoded, forKey: calibrationKey(left: left))
        }
    }

    static func resetCalibration(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: calibrationKey(left: true))
        defaults.removeObject(forKey: calibrationKey(left: false))
    }

    static func tuning(deadzone: Double, curve: Double, gateRaw: String) -> StickTuning {
        StickTuning(deadzone: deadzone, curve: curve,
                    gate: StickTuning.Gate(rawValue: gateRaw) ?? .octagon)
    }

    // MARK: Fine-tuning

    /// One per-stick setting. The stored key is `muffin.controls.stick.<name>.left|right`.
    enum Setting: String, CaseIterable {
        case innerDeadzone = "deadzone"
        case curve
        case outerDeadzone = "outer"
        case antiDeadzone = "anti"
        case sensitivityX = "sensx"
        case sensitivityY = "sensy"
        case invertX = "invx"
        case invertY = "invy"
    }

    static func key(_ setting: Setting, left: Bool) -> String {
        "muffin.controls.stick.\(setting.rawValue).\(left ? "left" : "right")"
    }

    /// Every per-stick key, both sticks, for the reset registry and the settings backup.
    static var allFeelKeys: [String] {
        Setting.allCases.flatMap { [key($0, left: true), key($0, left: false)] }
    }

    /// What an @AppStorage double holds while the stick has no value of its own (the shared
    /// deadzone or curve then applies).
    static let unset: Double = -1

    /// This stick's fine-tuning as stored. A deadzone or curve it has no value of its own for falls back
    /// to the shared one (`deadzoneKey` / `stickCurveKey`, what every stick used before), and if that was
    /// never set either, to `fallbackDeadzone` (the pad's own default) and linear. So nothing changes for
    /// anyone who has not opened the fine-tuning page.
    static func feel(left: Bool, fallbackDeadzone: Double = ControllerLayoutSettings.defaultDeadzone,
                     defaults: UserDefaults = .standard) -> StickFeel {
        func stored(_ k: String) -> Double? {
            guard let v = defaults.object(forKey: k) as? Double, v >= 0 else { return nil }
            return v
        }
        func own(_ s: Setting) -> Double? { stored(key(s, left: left)) }
        return StickFeel(
            innerDeadzone: own(.innerDeadzone) ?? stored(ControllerLayoutSettings.deadzoneKey) ?? fallbackDeadzone,
            curve: own(.curve) ?? stored(ControllerLayoutSettings.stickCurveKey) ?? ControllerLayoutSettings.defaultStickCurve,
            outerDeadzone: own(.outerDeadzone) ?? 0,
            antiDeadzone: own(.antiDeadzone) ?? 0,
            sensitivityX: own(.sensitivityX) ?? 1,
            sensitivityY: own(.sensitivityY) ?? 1,
            invertX: defaults.bool(forKey: key(.invertX, left: left)),
            invertY: defaults.bool(forKey: key(.invertY, left: left)))
    }

    /// Back to the shared values for one stick.
    static func reset(left: Bool, defaults: UserDefaults = .standard) {
        for s in Setting.allCases { defaults.removeObject(forKey: key(s, left: left)) }
    }

    /// The shared Deadzone and Fine control sliders set both sticks, so they drop each stick's own value.
    static func clearInnerAndCurveOverrides(defaults: UserDefaults = .standard) {
        for left in [true, false] {
            defaults.removeObject(forKey: key(.innerDeadzone, left: left))
            defaults.removeObject(forKey: key(.curve, left: left))
        }
    }

    /// What the TouchLab package is given as its one deadzone and curve. It reads a single pair for both
    /// sticks, so it gets the smaller of the two (it can only take away, never add back what it cut), and
    /// `refine` brings each stick to its own from there.
    static func packageBase(defaults: UserDefaults = .standard) -> StickBase {
        let l = feel(left: true, defaults: defaults).clamped, r = feel(left: false, defaults: defaults).clamped
        return StickBase(deadzone: min(l.innerDeadzone, r.innerDeadzone), curve: min(l.curve, r.curve))
    }

    /// A stick value that already has `base`'s deadzone and curve in it (what the package or
    /// `StickMath` produced), taken the rest of the way to this stick's fine-tuning.
    ///
    /// In order: inner and outer deadzone (the deadzone edge becomes 0, the outer edge becomes full), the
    /// curve on the magnitude, the anti-deadzone floor, sensitivity per axis (kept inside the unit circle),
    /// then invert. Deflection comes first from calibration and the gate, in `StickMath`. When the
    /// deadzone and curve are already `base`'s and everything else is at its default, the value goes
    /// back untouched.
    static func refine(_ value: StickValue, feel: StickFeel, base: StickBase,
                       calibration: StickCalibration) -> StickValue {
        let f = feel.clamped
        let b = base.clamped
        let m0 = value.magnitude
        guard m0 > 0 else { return .zero }
        let cal = calibration.clamped
        // The resting wobble is a floor under the deadzone, as in StickMath.
        let rest = cal.jitter / cal.fullThrow
        let baseDead = max(b.deadzone, rest), dead = max(f.innerDeadzone, rest)
        let ux = value.x / m0, uy = value.y / m0
        var m = m0
        if f.outerDeadzone > 0 || dead != baseDead || f.curve != b.curve {
            // Back to the deflection, then forward again with this stick's own numbers.
            var raw = m0
            if b.curve != 1 { raw = pow(raw, 1 / b.curve) }
            let deflection = baseDead + raw * (1 - baseDead)
            guard deflection > dead else { return .zero }
            m = min((deflection - dead) / max(1 - dead - f.outerDeadzone, 0.05), 1)
            if f.curve != 1 { m = pow(m, f.curve) }
        }
        if f.antiDeadzone > 0 { m = f.antiDeadzone + m * (1 - f.antiDeadzone) }
        // Only a changed magnitude or a sensitivity can move the value, so only then can it need
        // pulling back inside the unit circle. Otherwise the input's own numbers go through as they are
        // (dividing a unit-length value by its own length can move it by an ulp).
        let reshaped = m != m0 || f.sensitivityX != 1 || f.sensitivityY != 1
        var x = m == m0 ? value.x : ux * m
        var y = m == m0 ? value.y : uy * m
        if f.sensitivityX != 1 { x *= f.sensitivityX }
        if f.sensitivityY != 1 { y *= f.sensitivityY }
        if reshaped {
            let len = (x * x + y * y).squareRoot()
            if len > 1 { x /= len; y /= len }
        }
        if f.invertX { x = -x }
        if f.invertY { y = -y }
        return StickValue(x: x, y: y)
    }

    /// A finger's offset from the stick's centre (points, +y down) as the stick value the
    /// console reads (+y up, at most 1 long). The one function MuffinEMU's pad and the new pad
    /// use, and what the fine-tuning page's test view draws.
    static func output(dx: CGFloat, dy: CGFloat, travel: CGFloat, feel: StickFeel,
                       gateRaw: String, calibrationRaw: String) -> CGPoint {
        let f = feel.clamped
        let calibration = StickCalibration(encoded: calibrationRaw)
        let v = StickMath.value(offset: CGPoint(x: dx, y: dy), travel: travel,
                                tuning: tuning(deadzone: f.innerDeadzone, curve: f.curve, gateRaw: gateRaw),
                                calibration: calibration, fixedBase: true)
        let r = refine(v, feel: f, base: StickBase(deadzone: f.innerDeadzone, curve: f.curve), calibration: calibration)
        return CGPoint(x: r.x, y: r.y)
    }

    /// Everything the TouchLab pad needs, from the same keys Gen 1 reads.
    static func padSettings(scale: Double, opacity: Double, haptics: Bool, deadzone: Double, curve: Double,
                            gateRaw: String, stickSpacing: Double, shoulderOffset: Double,
                            followsThumb: Bool = false, relativeCentre: Bool = false,
                            colourPreset: ShowcaseColourPreset? = nil, showcaseStyle: Bool = true,
                            defaults: UserDefaults = .standard) -> PadSettings {
        var stick = tuning(deadzone: deadzone, curve: curve, gateRaw: gateRaw)
        stick.followsThumb = followsThumb
        stick.relativeCentre = relativeCentre
        return PadSettings(stick: stick,
                    calibration: StickCalibrations(left: calibration(left: true, defaults: defaults),
                                                   right: calibration(left: false, defaults: defaults)),
                    scale: CGFloat(scale), opacity: CGFloat(opacity), haptics: haptics,
                    stickSpacing: CGFloat(stickSpacing), shoulderOffset: CGFloat(shoulderOffset),
                    colourPreset: colourPreset, showcaseStyle: showcaseStyle)
    }
}

/// The deadzone and curve a value already has applied.
struct StickBase: Equatable {
    var deadzone: Double
    var curve: Double

    var clamped: StickBase {
        let t = StickTuning(deadzone: deadzone, curve: curve).clamped
        return StickBase(deadzone: t.deadzone, curve: t.curve)
    }
}

/// One stick's fine-tuning. The defaults, with the shared deadzone and curve, give the output the
/// sticks always had.
struct StickFeel: Equatable {
    /// Where the output starts, as a fraction of travel (0 to 0.30).
    var innerDeadzone: Double
    /// 1 = linear, higher = finer near the middle (1 to 2.5).
    var curve: Double
    /// How far short of the edge the output already reaches full (0 to 0.30).
    var outerDeadzone: Double = 0
    /// The least output once past the inner deadzone, for games with a deadzone of their own (0 to 0.50).
    var antiDeadzone: Double = 0
    var sensitivityX: Double = 1
    var sensitivityY: Double = 1
    var invertX = false
    var invertY = false

    static let outerRange: ClosedRange<Double> = 0.0...0.30
    static let antiRange: ClosedRange<Double> = 0.0...0.50
    static let sensitivityRange: ClosedRange<Double> = 0.25...1.5

    /// Every number inside its range (a stored value can be out of range, or not a number).
    var clamped: StickFeel {
        func fit(_ v: Double, _ r: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : fallback
        }
        var f = self
        let t = StickTuning(deadzone: innerDeadzone, curve: curve).clamped
        f.innerDeadzone = t.deadzone
        f.curve = t.curve
        f.outerDeadzone = fit(outerDeadzone, Self.outerRange, 0)
        f.antiDeadzone = fit(antiDeadzone, Self.antiRange, 0)
        f.sensitivityX = fit(sensitivityX, Self.sensitivityRange, 1)
        f.sensitivityY = fit(sensitivityY, Self.sensitivityRange, 1)
        return f
    }
}
