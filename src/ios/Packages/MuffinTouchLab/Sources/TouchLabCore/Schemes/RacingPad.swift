import CoreGraphics
import Foundation

/// Scheme 5 - Racing Pad.
///
/// Built for Mario Kart 8, and for any racing game that plays like it: steer with one thumb,
/// accelerate with the other, and everything else a flick away. The controls MK8 uses on the
/// GamePad are A (accelerate), B (brake and reverse), L or ZL (use an item), R or ZR (hop and
/// drift), X (rear view), + (pause), and the left stick: sideways to steer, up or down while
/// using an item to throw it forward or back.
///
/// - Left side, one large steering area. The anchor appears where the thumb lands, sideways
///   travel is the steering (a small dead zone, full lock a fixed distance away that comes
///   from the screen), and up or down travel is only the item throw, behind a bigger dead
///   zone so steering never throws anything. Past full lock the anchor follows the thumb.
/// - Right side, a stack of pedals the thumb rests on: Accelerate (A) at the bottom with
///   Brake (B) beside it, then an A+R strip that holds both, then Drift (R). Sliding up from A
///   through the strip to R hands the press over without lifting, so a drift is one roll of
///   the thumb. Between them the zones leave no gaps.
/// - Item (L) sits in the middle where either thumb can reach it and neither lands on it by
///   accident. Rear view (X), pause (+) and HOME are small, along the top.
/// - Options: auto-accelerate holds A for the player (the Brake zone overrides it), and tilt
///   steering takes the sideways steering from the device's motion, turned like a wheel.
///
/// Every size comes from the screen: the button unit is `LayoutContext.unit`, and the layout
/// shrinks it step by step until nothing overlaps and everything is inside the safe area.
public final class RacingPad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "racing",
        name: "Racing",
        summary: "Made for Mario Kart 8: a big steering area, Accelerate, Brake and Drift pedals where your thumb rests, and an A+R zone for drifting.")

    public struct Options: Equatable, Sendable {
        /// Holds A for the player. The Brake zone releases it while it is touched.
        public var autoAccelerate: Bool
        /// Steers from the device's motion instead of the thumb. The thumb still throws items.
        public var tilt: Bool
        /// Where the item button (L) sits. Mario Kart uses items constantly, and the middle of the
        /// screen is a long way from either thumb.
        public var itemPlacement: ItemPlacement
        /// A bigger item button (about 1.4 times), easier to hit without looking.
        public var largeItem: Bool
        public init(autoAccelerate: Bool = false, tilt: Bool = false,
                    itemPlacement: ItemPlacement = .centre, largeItem: Bool = false) {
            self.autoAccelerate = autoAccelerate
            self.tilt = tilt
            self.itemPlacement = itemPlacement
            self.largeItem = largeItem
        }
    }

    public enum ItemPlacement: String, CaseIterable, Sendable {
        /// Between the steering area and the pedals (the original place).
        case centre
        /// Just above the steering area, where the steering thumb can flick to it.
        case aboveSteering
        /// Just above the Drift pedal, where the accelerating thumb can reach without leaving A.
        case abovePedals
    }

    public let options: Options
    /// A's size as a multiple of its usual one (1...1.8): the Accelerate pedal grows with it.
    public let aScale: CGFloat

    /// How far the device is turned, from straight ahead, for full lock: 35 degrees.
    public static let tiltFullLock: Double = 35 * .pi / 180

    private var lastAngle: Double?
    private var centreAngle: Double?
    /// Steering from the device's motion, -1...1. Zero until the first sample.
    public private(set) var tiltValue: Double = 0

    public init(options: Options = Options(), aScale: CGFloat = 1) {
        self.options = options
        self.aScale = aScale
        super.init(info: Self.schemeInfo)
    }

    // MARK: Layout

    override public func makeControls(_ context: LayoutContext) -> [PadControl] {
        RacingPad.build(context, options: options, aScale: aScale)
    }

    /// The layout at the largest size that fits: the context's own unit, then 8% smaller
    /// each step until nothing overlaps, everything is inside the safe area and the steering
    /// area is still wide enough to use.
    public static func build(_ ctx: LayoutContext, options: Options = Options(), aScale: CGFloat = 1) -> [PadControl] {
        var u = ctx.unit
        for _ in 0..<12 {
            if let set = arrangement(ctx, u: u, options: options, aScale: aScale),
               LayoutCheck.problems(set, in: ctx.safeBounds).isEmpty {
                return set
            }
            u *= 0.92
        }
        return arrangement(ctx, u: u, options: options, aScale: aScale, force: true) ?? []
    }

    /// Group the pedals slide within.
    static let pedalGroup = 31

    static func arrangement(_ ctx: LayoutContext, u: CGFloat, options: Options, aScale: CGFloat = 1, force: Bool = false) -> [PadControl]? {
        let s = ctx.safeBounds
        guard s.width > 0, s.height > 0 else { return nil }
        let landscape = s.width >= s.height
        // Held upright, the picture is along the top, so the controls take the lower part.
        let bandHeight = landscape ? s.height : min(s.height, max(8.5 * u, 0.46 * s.height))
        let bandTop = s.maxY - bandHeight
        let gap = 0.05 * u            // drawn gap between neighbouring zones; the catchment closes it
        // The pedals and the steering area stop this far short of the screen edge (rounded display
        // corners, a thumb's own edge), and reach back out to it, so the edge is still live.
        let edge = min(0.12 * u, 8)

        // Pedals, bottom right. Widths and heights in units of a thumb-sized button.
        let a = PadParts.clampedAScale(aScale)
        let wA = 2.7 * a * u, wB = 1.8 * u
        let hA = 2.3 * a * u, hC = 1.5 * u, hR = 1.3 * u
        let xA = s.maxX - edge - wA, xB = xA - wB
        let yA = s.maxY - edge - hA, yC = yA - hC, yR = yC - hR
        func inset(_ r: CGRect) -> CGRect { r.insetBy(dx: gap / 2, dy: gap / 2) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { inset(CGRect(x: x, y: y, width: w, height: h)) }
        let corner = 0.3 * u
        let reach = gap + edge

        func pedal(_ buttons: Set<PadButton>, _ r: CGRect, _ role: RenderElement.Role, _ label: String) -> PadControl {
            PadControl(.pedal(buttons), shape: .roundedRect(r, cornerRadius: corner), role: role, label: label,
                       group: pedalGroup, reach: reach, chords: false)
        }
        var controls: [PadControl] = [
            pedal([.a], rect(xA, yA, wA, hA), .pedal, "A"),
            pedal([.b], rect(xB, yC, wB, hA + hC), .pedal, "B"),
            pedal([.a, .r], rect(xA, yC, wA, hC), .pedal, "A+R"),
            pedal([.r], rect(xB, yR, wB + wA, hR), .pedal, "R"),
        ]

        // The room between the steering area and the pedals.
        let steerMax = 0.36 * s.width
        let itemGrow: CGFloat = options.largeItem ? 1.4 : 1
        let itemW = 1.7 * u * itemGrow, itemH = 1.25 * u * itemGrow
        let margin = 0.6 * u
        let centreRoom = xB + edge - s.minX - steerMax
        var steerRight = s.minX + steerMax
        var steerTop = bandTop + (landscape ? 0.25 : 0.08) * bandHeight
        let itemRect: CGRect
        if options.itemPlacement == .abovePedals, yR - itemH - 0.3 * u > bandTop + 1.1 * u {
            // Over the right-hand pedals, flush with their right edge, clear of the top buttons.
            itemRect = CGRect(x: xA + wA - itemW, y: yR - itemH - 0.3 * u, width: itemW, height: itemH)
        } else if options.itemPlacement == .aboveSteering, steerTop - itemH - 0.3 * u > bandTop + 1.1 * u {
            // Over the steering area's top edge, towards its inner side, so a flick from the steering thumb lands on it.
            itemRect = CGRect(x: steerRight - itemW - 0.3 * u, y: steerTop - itemH - 0.3 * u, width: itemW, height: itemH)
        } else if centreRoom >= itemW + 2 * margin {
            // In the middle, level with the pedals' upper half: either thumb reaches it, and a
            // thumb sliding off Brake or Drift has to go a long way to find it.
            let cx = (steerRight + xB) / 2
            itemRect = CGRect(x: cx - itemW / 2, y: yC - 0.2 * u, width: itemW, height: itemH)
        } else {
            // No room beside the pedals (a phone held upright): top left of the steering area,
            // with the steering area starting below it.
            itemRect = CGRect(x: s.minX + 0.3 * u, y: bandTop + 0.3 * u, width: itemW, height: itemH)
            steerTop = max(steerTop, itemRect.maxY + 0.35 * u)
            steerRight = min(steerRight, xB - 0.4 * u)
        }
        controls.append(PadControl(.button(.l), shape: .roundedRect(itemRect, cornerRadius: corner), role: .shoulder, label: "L",
                                   reach: 0.2 * u, priority: 2))

        // Steering: the whole left side from just under the top, down to the bottom edge.
        let lockX = max(1.2 * u, min(0.3 * (steerRight - s.minX), 2.2 * u))
        let lockY = 1.2 * lockX
        let steer = CGRect(x: s.minX + edge, y: steerTop, width: steerRight - s.minX - edge, height: s.maxY - edge - steerTop)
        guard steer.width >= 2.8 * u, steer.height >= 3 * u || force else { return force ? controls : nil }
        let spec = SteerSpec(stick: .left, lockX: lockX, lockY: lockY, deadY: 0.45, followPast: 1.3, tilt: options.tilt)
        controls.append(PadControl(.steer(spec), shape: .roundedRect(inset(steer), cornerRadius: corner), role: .area,
                                   label: options.tilt ? "TILT" : "STEER", reach: edge + gap, priority: 0))

        // Small buttons along the top, centred: rear view, pause, HOME (and recentre for tilt).
        let rowY = bandTop + 0.2 * u + 0.4 * u
        let step = 1.3 * u
        var row: [PadControl] = [
            PadControl(.button(.x), shape: .circle(center: CGPoint(x: s.midX - step, y: rowY), radius: PadParts.systemDiameter / 2 * u),
                       role: .system, label: "X", reach: 0.25 * u, priority: 2),
            PadParts.system(.plus, at: CGPoint(x: s.midX, y: rowY), u: u),
            PadParts.system(.home, at: CGPoint(x: s.midX + step, y: rowY), u: u),
        ]
        if options.tilt {
            row.append(PadControl(.recentre, shape: .circle(center: CGPoint(x: s.midX + 2 * step, y: rowY), radius: PadParts.systemDiameter / 2 * u),
                                  role: .system, label: "C", reach: 0.25 * u, priority: 2))
        }
        for i in row.indices { row[i].priority = 2 }
        controls += row
        return controls
    }

    // MARK: Steering from motion

    override public var wantsMotion: Bool { options.tilt }

    /// Takes the current angle as straight ahead.
    public func recentre() {
        centreAngle = lastAngle
        applyTilt()
    }

    override public func recentreRequested() { recentre() }

    override public func motion(angle: Double) -> [TouchID: Contribution] {
        guard options.tilt else { return [:] }
        lastAngle = angle
        if centreAngle == nil { centreAngle = angle }
        applyTilt()
        var out: [TouchID: Contribution] = [:]
        for (id, t) in tracks {
            if case .steer = controls[t.control].kind {
                out[id] = contribution(for: &tracks[id]!, at: t.last, time: t.lastTime)
            }
        }
        return out
    }

    /// Turn from straight ahead as -1...1, with the same dead zone and curve as the sticks.
    private func applyTilt() {
        guard options.tilt, let angle = lastAngle, let centre = centreAngle else {
            tiltValue = 0
            steerOverrideX = options.tilt ? 0 : nil
            return
        }
        var d = angle - centre
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        // Same deadzone, curve and calibration as the steering stick (the left one) it replaces.
        let tuning = context.stick.clamped
        let cal = context.calibration.left.clamped
        let dead = max(tuning.deadzone, cal.jitter / cal.fullThrow)
        let raw = abs(d) / (Self.tiltFullLock * cal.fullThrow)
        var v = 0.0
        if raw > dead {
            let live = min((raw - dead) / max(1 - dead, 0.0001), 1)
            v = pow(live, tuning.curve)
        }
        tiltValue = d < 0 ? -v : v
        steerOverrideX = tiltValue
    }

    // MARK: Ambient input

    override public func ambient() -> Contribution? {
        var buttons: Set<PadButton> = []
        if options.autoAccelerate {
            // The Brake zone is the player saying stop: while any finger is on it, A is theirs.
            let braking = tracks.values.contains { $0.buttons.contains(.b) }
            if !braking { buttons.insert(.a) }
        }
        var stick: PadStick?
        var value = StickValue.zero
        if options.tilt {
            // With a thumb on the steering area its contribution already carries the tilt.
            let steering = tracks.values.contains { if case .steer = controls[$0.control].kind { return true }; return false }
            if !steering { stick = .left; value = StickValue(x: tiltValue, y: 0) }
        }
        if buttons.isEmpty && stick == nil { return nil }
        return Contribution(buttons: buttons, stick: stick, stickValue: value)
    }

    override public func layout(_ context: LayoutContext) {
        super.layout(context)
        applyTilt()
    }
}
