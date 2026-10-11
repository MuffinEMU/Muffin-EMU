import CoreGraphics
import Foundation

/// How far off a button a touch still counts. The same three levels as MuffinEMU's own pad,
/// with the same numbers, so a choice means the same thing in every scheme.
public enum PadTolerance: Int, CaseIterable, Sendable {
    case normal = 0, generous = 1, veryGenerous = 2

    /// Reach beyond the drawn edge, as a multiple of the button's radius.
    public var reachFactor: CGFloat {
        switch self {
        case .normal: return 1.15
        case .generous: return 1.4
        case .veryGenerous: return 1.7
        }
    }

    /// Points a touch is nudged toward where the thumb's contact lands.
    public var biasPoints: CGFloat {
        switch self {
        case .normal: return 0
        case .generous: return 3
        case .veryGenerous: return 6
        }
    }
}

/// What one player's thumb does on one stick, measured by the calibration flow.
///
/// Everything is a fraction of the stick's full travel, so a calibration made on one scheme's
/// stick is correct on every other scheme's, whatever size either is drawn at.
public struct StickCalibration: Equatable, Sendable {
    /// How far the thumb comfortably goes, as a fraction of full travel. The output is full
    /// there. 1 = the whole ring; the default.
    public var fullThrow: Double
    /// Where the thumb rests, as an offset from the stick's centre. Only meaningful for a stick
    /// with a fixed base; a floating stick's base appears under the thumb, so its rest is zero.
    public var centre: CGPoint
    /// How much the resting thumb wobbles, as a fraction of full travel. The effective
    /// deadzone is never smaller than this.
    public var jitter: Double

    public static let fullThrowRange: ClosedRange<Double> = 0.4...1.15
    public static let maxCentre: Double = 0.35
    public static let maxJitter: Double = 0.25

    public static let identity = StickCalibration()
    public var isIdentity: Bool { self == .identity }

    public init(fullThrow: Double = 1, centre: CGPoint = .zero, jitter: Double = 0) {
        self.fullThrow = fullThrow
        self.centre = centre
        self.jitter = jitter
    }

    /// In range, and finite. Anything unusable falls back to the identity value for that part.
    public var clamped: StickCalibration {
        var c = self
        c.fullThrow = fullThrow.isFinite ? min(max(fullThrow, Self.fullThrowRange.lowerBound), Self.fullThrowRange.upperBound) : 1
        c.jitter = jitter.isFinite ? min(max(jitter, 0), Self.maxJitter) : 0
        if centre.x.isFinite, centre.y.isFinite {
            let len = Double(hypot(centre.x, centre.y))
            if len > Self.maxCentre {
                let k = CGFloat(Self.maxCentre / len)
                c.centre = CGPoint(x: centre.x * k, y: centre.y * k)
            }
        } else {
            c.centre = .zero
        }
        return c
    }

    /// The stored form: "fullThrow,centreX,centreY,jitter". Empty for the identity.
    public var encoded: String {
        isIdentity ? "" : [fullThrow, Double(centre.x), Double(centre.y), jitter].map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    public init(encoded: String) {
        let p = encoded.split(separator: ",").compactMap { Double($0) }
        guard p.count == 4 else { self = .identity; return }
        self = StickCalibration(fullThrow: p[0], centre: CGPoint(x: p[1], y: p[2]), jitter: p[3]).clamped
    }
}

/// The calibration of each stick.
public struct StickCalibrations: Equatable, Sendable {
    public var left: StickCalibration
    public var right: StickCalibration

    public init(left: StickCalibration = .identity, right: StickCalibration = .identity) {
        self.left = left
        self.right = right
    }

    public subscript(stick: PadStick) -> StickCalibration {
        get { stick == .left ? left : right }
        set { if stick == .left { left = newValue } else { right = newValue } }
    }
}

/// The player's controller setup, the same for every control scheme. A value here means the
/// same thing in all of them, and the defaults are what each scheme did before any of this
/// was set.
public struct PadSettings: Equatable, Sendable {
    /// Stick feel: deadzone, response curve, gate. Same maths as MuffinEMU's own pad.
    public var stick: StickTuning
    /// Per-stick calibration; the identity until the player runs the calibration flow.
    public var calibration: StickCalibrations
    /// nil = the scheme's own reach. Set = at least this much reach on every button.
    public var tolerance: PadTolerance?
    /// Size multiplier on the automatic button size.
    public var scale: CGFloat
    public var opacity: CGFloat
    public var haptics: Bool
    /// Sideways stick placement, in button widths.
    public var stickSpacing: CGFloat
    /// Shoulder cluster drop, in button widths.
    public var shoulderOffset: CGFloat
    /// Colour preset for the classic schemes (see `PadStyle`); nil = their own Classic look.
    public var colourPreset: ShowcaseColourPreset?

    public static let defaultOpacity: CGFloat = 0.85

    public init(stick: StickTuning = StickTuning(),
                calibration: StickCalibrations = StickCalibrations(),
                tolerance: PadTolerance? = nil,
                scale: CGFloat = 1,
                opacity: CGFloat = PadSettings.defaultOpacity,
                haptics: Bool = true,
                stickSpacing: CGFloat = 0,
                shoulderOffset: CGFloat = 0,
                colourPreset: ShowcaseColourPreset? = nil) {
        self.colourPreset = colourPreset
        self.stick = stick
        self.calibration = calibration
        self.tolerance = tolerance
        self.scale = scale
        self.opacity = opacity
        self.haptics = haptics
        self.stickSpacing = stickSpacing
        self.shoulderOffset = shoulderOffset
    }
}
