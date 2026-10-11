import CoreGraphics
import Foundation

/// How a stick feels. Defaults match the shipping Muffin pad's
/// (ControllerLayoutSettings: deadzone 0.06, curve 1.0, octagonal gate).
public struct StickTuning: Equatable, Sendable {
    public enum Gate: String, CaseIterable, Sendable {
        case octagon, round
    }

    public var deadzone: Double
    /// Response exponent: 1 = linear, higher = finer control near centre.
    public var curve: Double
    public var gate: Gate
    /// Off by default. On, a thumb that goes past the ring takes the stick's base along with
    /// it, so turning back is as quick as turning out (the slight follow Gen 1 has). Only
    /// the base moves: the output is the same full deflection either way.
    public var followsThumb: Bool
    /// Off by default. On, a fixed stick's centre is wherever the thumb lands inside its
    /// zone, so the first touch is never a push.
    public var relativeCentre: Bool

    public init(deadzone: Double = 0.06, curve: Double = 1.0, gate: Gate = .octagon,
                followsThumb: Bool = false, relativeCentre: Bool = false) {
        self.deadzone = deadzone
        self.curve = curve
        self.gate = gate
        self.followsThumb = followsThumb
        self.relativeCentre = relativeCentre
    }

    /// The ranges MuffinEMU's settings offer.
    public static let deadzoneRange: ClosedRange<Double> = 0.0...0.30
    public static let curveRange: ClosedRange<Double> = 1.0...2.5

    /// Both numbers inside their ranges (a stored value can be out of range, or not a number).
    public var clamped: StickTuning {
        var t = self
        t.deadzone = deadzone.isFinite ? min(max(deadzone, Self.deadzoneRange.lowerBound), Self.deadzoneRange.upperBound) : 0.06
        t.curve = curve.isFinite ? min(max(curve, Self.curveRange.lowerBound), Self.curveRange.upperBound) : 1
        return t
    }
}

public enum StickMath {
    /// How far the gate lies from centre along `angle`, as a fraction of full travel.
    /// Ported from ControllerGeometry.StickGate.radiusFraction - the real GamePad's octagonal
    /// gate reaches full travel on the eight main directions, ~8% less on the flats.
    public static func gateFraction(_ gate: StickTuning.Gate, angle: CGFloat) -> CGFloat {
        switch gate {
        case .round:
            return 1
        case .octagon:
            let wedge = CGFloat.pi / 4
            var offset = angle.truncatingRemainder(dividingBy: wedge)
            if offset < 0 { offset += wedge }
            return cos(wedge / 2) / cos(offset - wedge / 2)
        }
    }

    /// How far past full travel the knob keeps following a finger that already owns the stick.
    /// Output is unaffected: it is full from `travel` on.
    public static func overtravel(_ travel: CGFloat) -> CGFloat { travel * 0.15 }

    /// Converts a finger offset from the stick's centre (view points, +y down) into a
    /// console-convention stick value (+y up).
    ///
    /// This is MuffinEMU's own pad's stick maths, and the only copy: every scheme and the pad
    /// itself call it, so a deadzone, curve or gate means the same in all of them. The gate caps
    /// how far the thumb counts, the deadzone is radial and RESCALED (output ramps from 0 at its
    /// edge instead of jumping), and the curve is applied to the magnitude alone, so the
    /// direction the thumb holds is never bent.
    ///
    /// `calibration` maps the player's own reach and rest onto the same output: the offset is
    /// taken from where their thumb rests (`fixedBase` sticks only), full output is reached at
    /// their comfortable throw, and the deadzone is never smaller than their rest wobble. The
    /// identity calibration changes nothing.
    public static func value(offset: CGPoint, travel: CGFloat, tuning: StickTuning,
                             calibration: StickCalibration = .identity, fixedBase: Bool = true) -> StickValue {
        guard travel > 0 else { return .zero }
        let tuning = tuning.clamped
        let cal = calibration.clamped
        var dx = offset.x, dy = offset.y
        if fixedBase {
            dx -= cal.centre.x * travel
            dy -= cal.centre.y * travel
        }
        let distance = (dx * dx + dy * dy).squareRoot()
        let gate = gateFraction(tuning.gate, angle: atan2(dy, dx))
        let reach = travel * gate
        let full = CGFloat(cal.fullThrow)
        let deflection: CGFloat = cal.fullThrow == 1
            ? min(distance, reach) / travel
            : min(min(distance, reach) / (travel * full), gate)
        // The rest wobble is measured in travel; the deflection here is in throws.
        let dead = CGFloat(max(tuning.deadzone, cal.jitter / cal.fullThrow))
        guard deflection > dead, distance > 0 else { return .zero }
        var magnitude = (deflection - dead) / (1 - dead)
        if tuning.curve != 1 { magnitude = CGFloat(pow(Double(magnitude), tuning.curve)) }
        return StickValue(x: Double(dx / distance * magnitude), y: Double(-dy / distance * magnitude))
    }

    /// Where to draw the knob for a finger offset: along the finger's direction, no farther
    /// than the gate allows.
    public static func knobOffset(offset: CGPoint, travel: CGFloat, gate: StickTuning.Gate) -> CGPoint {
        let len = offset.length
        guard len > 0 else { return .zero }
        let maxLen = travel * gateFraction(gate, angle: offset.screenAngle) + overtravel(travel)
        return len <= maxLen ? offset : offset * (maxLen / len)
    }
}

/// Eight-way direction from an angle, for d-pads.
///
/// Cardinals get wider sectors than diagonals (`cardinalHalfWidth` either side of each
/// axis), because an accidental diagonal while walking straight is the classic touch d-pad
/// complaint, and a deliberate diagonal is a bigger, more obvious thumb movement.
public enum DPadMath {
    public static let cardinalHalfWidth: CGFloat = 27.5 * .pi / 180

    public static func directions(angle: CGFloat, cardinalHalfWidth: CGFloat = cardinalHalfWidth) -> Set<PadButton> {
        // Angle of the nearest cardinal axis and how far off it we are.
        let quarter = CGFloat.pi / 2
        let k = (angle / quarter).rounded()
        let off = abs(angle - k * quarter)
        let cardinal: PadButton
        switch (Int(k) % 4 + 4) % 4 {
        case 0: cardinal = .right
        case 1: cardinal = .up
        case 2: cardinal = .left
        default: cardinal = .down
        }
        if off <= cardinalHalfWidth { return [cardinal] }
        // Diagonal: the cardinal plus its neighbour on whichever side we are.
        let side: CGFloat = angle > k * quarter ? 1 : -1
        let neighbourIndex = ((Int(k) + Int(side)) % 4 + 4) % 4
        let neighbour: PadButton = [.right, .up, .left, .down][neighbourIndex]
        return [cardinal, neighbour]
    }
}
