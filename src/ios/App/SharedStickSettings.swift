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

    /// A finger's offset from the stick's centre (points, +y down) as the stick value the
    /// console reads (+y up, at most 1 long).
    static func output(dx: CGFloat, dy: CGFloat, travel: CGFloat, deadzone: Double, curve: Double,
                       gateRaw: String, calibrationRaw: String) -> CGPoint {
        let v = StickMath.value(offset: CGPoint(x: dx, y: dy), travel: travel,
                                tuning: tuning(deadzone: deadzone, curve: curve, gateRaw: gateRaw),
                                calibration: StickCalibration(encoded: calibrationRaw), fixedBase: true)
        return CGPoint(x: v.x, y: v.y)
    }

    /// Everything the TouchLab pad needs, from the same keys Gen 1 reads.
    static func padSettings(scale: Double, opacity: Double, haptics: Bool, deadzone: Double, curve: Double,
                            gateRaw: String, stickSpacing: Double, shoulderOffset: Double,
                            followsThumb: Bool = false, relativeCentre: Bool = false,
                            colourPreset: ShowcaseColourPreset? = nil,
                            defaults: UserDefaults = .standard) -> PadSettings {
        var stick = tuning(deadzone: deadzone, curve: curve, gateRaw: gateRaw)
        stick.followsThumb = followsThumb
        stick.relativeCentre = relativeCentre
        return PadSettings(stick: stick,
                    calibration: StickCalibrations(left: calibration(left: true, defaults: defaults),
                                                   right: calibration(left: false, defaults: defaults)),
                    scale: CGFloat(scale), opacity: CGFloat(opacity), haptics: haptics,
                    stickSpacing: CGFloat(stickSpacing), shoulderOffset: CGFloat(shoulderOffset),
                    colourPreset: colourPreset)
    }
}
