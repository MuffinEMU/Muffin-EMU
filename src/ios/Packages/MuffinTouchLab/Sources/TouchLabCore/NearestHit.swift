import CoreGraphics

/// One pressable control, as the nearest-button test sees it.
public struct HitTarget: Equatable, Sendable {
    public var id: String
    public var centre: CGPoint
    public var halfSize: CGSize
    public var isCircle: Bool

    public init(id: String, centre: CGPoint, halfSize: CGSize, isCircle: Bool) {
        self.id = id
        self.centre = centre
        self.halfSize = halfSize
        self.isCircle = isCircle
    }

    public var radius: CGFloat { min(halfSize.width, halfSize.height) }

    /// Distance from `p` to the button's full bounding box; negative inside. Round buttons
    /// use the box too, so every point the old rectangular frame pressed still presses.
    public func edgeDistance(to p: CGPoint) -> CGFloat {
        let ox = abs(p.x - centre.x) - halfSize.width
        let oy = abs(p.y - centre.y) - halfSize.height
        if ox > 0 || oy > 0 { return hypot(max(ox, 0), max(oy, 0)) }
        return max(ox, oy)
    }
}

/// Which button a touch belongs to. A touch inside a button always belongs to it; one in the
/// gap or just outside goes to the nearest button whose edge is within reach, so the space
/// between buttons is not dead and a thumb landing off-centre still counts.
public enum HitResolver {
    /// - reachFactor: how far out a touch still counts, as a multiple of the button's radius
    ///   (1.4 = a ring 0.4 radii wide around every button).
    /// - contactRadius: half the finger's contact area, added to the reach.
    /// - bias: points added to the touch location before testing.
    /// - current: the button this finger is already holding. It is kept until another
    ///   button is nearer by more than `hysteresis` points, so a finger resting on the seam
    ///   does not flicker between two buttons.
    public static func resolve(_ touch: CGPoint, targets: [HitTarget], reachFactor: CGFloat,
                               contactRadius: CGFloat = 0, bias: CGPoint = .zero,
                               current: String? = nil, hysteresis: CGFloat = 4) -> String? {
        let p = CGPoint(x: touch.x + bias.x, y: touch.y + bias.y)
        var best: (id: String, d: CGFloat)?
        var held: CGFloat?
        for t in targets {
            let d = t.edgeDistance(to: p)
            guard d <= (reachFactor - 1) * t.radius + contactRadius else { continue }
            if t.id == current { held = d }
            if best == nil || d < best!.d { best = (t.id, d) }
        }
        guard let best else { return nil }
        // Inside a button the finger belongs to it; hysteresis only applies outside.
        if best.d >= 0, let held, let current, held <= best.d + hysteresis { return current }
        return best.id
    }
}
