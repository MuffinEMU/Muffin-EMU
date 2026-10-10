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

    public init(deadzone: Double = 0.06, curve: Double = 1.0, gate: Gate = .octagon) {
        self.deadzone = deadzone
        self.curve = curve
        self.gate = gate
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
    /// The deadzone is radial and RESCALED - output ramps from 0 at the deadzone edge
    /// instead of jumping to `deadzone` - so a slow push starts slow. The curve is applied
    /// to the rescaled magnitude, then the gate caps it.
    public static func value(offset: CGPoint, travel: CGFloat, tuning: StickTuning) -> StickValue {
        guard travel > 0 else { return .zero }
        let raw = offset.length / travel
        guard raw > tuning.deadzone else { return .zero }
        let angle = offset.screenAngle
        let limit = gateFraction(tuning.gate, angle: angle)
        let live = min((Double(raw) - tuning.deadzone) / max(1 - tuning.deadzone, 0.0001), 1)
        let shaped = min(pow(live, tuning.curve), Double(limit))
        return StickValue(x: shaped * Double(cos(angle)), y: shaped * Double(sin(angle)))
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
