import CoreGraphics
import Foundation

/// The guided stick calibration, as a pure state machine so the same code runs on the device
/// and in the checks.
///
/// One continuous touch: the thumb comes down on the stick and rests for a moment (that gives
/// the rest centre and the wobble), then pushes to every edge, then lets go. Let go with enough
/// of the ring covered and the result is the player's comfortable full throw; let go too early
/// and nothing is saved, so a stray touch never changes anyone's setup.
public struct StickCalibrationSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case waiting, rest, sweep, finished }

    /// How long the thumb rests before the sweep starts, in seconds.
    public static let restDuration: Double = 1.2
    /// Sweep sectors around the stick, each 45 degrees, the first centred on "right".
    public static let sectorCount = 8
    /// Sectors that must be reached before letting go counts as a finished calibration.
    public static let minimumSectors = 6
    /// A rest that wanders further than this (a fraction of travel) starts again.
    public static let restWander: Double = 0.30
    /// A throw this close to the whole ring is the whole ring, so a player who already uses all
    /// of it keeps the default exactly.
    public static let snapToFull: Double = 0.97
    /// A resting spot this close to the middle is the middle.
    public static let snapToCentre: Double = 0.02

    public private(set) var phase: Phase = .waiting
    public private(set) var result: StickCalibration?
    /// Full travel of the stick being calibrated, in points.
    public let travel: CGFloat
    public let gate: StickTuning.Gate

    private var restStart = 0.0
    private var restSamples: [CGPoint] = []
    private var centre = CGPoint.zero
    private var reached: [Int: Double] = [:]

    public init(travel: CGFloat, gate: StickTuning.Gate = .octagon) {
        self.travel = max(travel, 1)
        self.gate = gate
    }

    public var coveredSectors: Set<Int> { Set(reached.keys) }
    public var coverage: Double { Double(reached.count) / Double(Self.sectorCount) }
    /// Seconds of rest still to go, for the progress ring (0 once resting is done).
    public func restRemaining(at time: Double) -> Double {
        phase == .rest ? max(0, Self.restDuration - (time - restStart)) : 0
    }

    public static func sector(of angle: CGFloat) -> Int {
        let step = CGFloat.pi / 4
        let a = (angle + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        return Int(((a < 0 ? a + 2 * .pi : a) / step).rounded(.down)) % sectorCount
    }

    /// A thumb came down at `offset` from the stick's centre (view points, +y down).
    public mutating func begin(at offset: CGPoint, time: Double) {
        guard phase == .waiting else { return }
        phase = .rest
        restStart = time
        restSamples = [offset]
    }

    public mutating func move(to offset: CGPoint, time: Double) {
        switch phase {
        case .rest:
            restSamples.append(offset)
            let mean = Self.mean(restSamples)
            if offset.distance(to: mean) > CGFloat(Self.restWander) * travel {
                // Not resting: start the rest over from here.
                restStart = time
                restSamples = [offset]
            } else if time - restStart >= Self.restDuration {
                centre = mean
                phase = .sweep
            }
        case .sweep:
            let v = CGPoint(x: offset.x - centre.x, y: offset.y - centre.y)
            let r = Double(v.length / travel)
            guard r > 0.15 else { return }
            let angle = atan2(-v.y, v.x)
            let limit = Double(StickMath.gateFraction(gate, angle: angle))
            let s = Self.sector(of: angle)
            reached[s] = max(reached[s] ?? 0, min(r / limit, StickCalibration.fullThrowRange.upperBound))
        case .waiting, .finished:
            break
        }
    }

    /// The thumb lifted. Returns the calibration if the sweep was complete enough, else nil and
    /// the session is ready to go again.
    @discardableResult
    public mutating func lift() -> StickCalibration? {
        defer { if phase != .finished { self = StickCalibrationSession(travel: travel, gate: gate) } }
        guard phase == .sweep, reached.count >= Self.minimumSectors else { return nil }
        var throwFraction = reached.values.reduce(0, +) / Double(reached.count)
        if throwFraction >= Self.snapToFull { throwFraction = 1 }
        var c = CGPoint(x: centre.x / travel, y: centre.y / travel)
        if Double(c.length) < Self.snapToCentre { c = .zero }
        let distances = restSamples.map { Double($0.distance(to: centre)) / Double(travel) }.sorted()
        let jitter = distances.isEmpty ? 0 : distances[min(distances.count - 1, Int(Double(distances.count) * 0.95))]
        let cal = StickCalibration(fullThrow: throwFraction, centre: c, jitter: jitter).clamped
        result = cal
        phase = .finished
        return cal
    }

    private static func mean(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let n = CGFloat(pts.count)
        return CGPoint(x: pts.reduce(0) { $0 + $1.x } / n, y: pts.reduce(0) { $0 + $1.y } / n)
    }
}
