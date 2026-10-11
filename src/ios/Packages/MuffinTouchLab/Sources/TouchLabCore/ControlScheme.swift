import CoreGraphics
import Foundation

/// How a steering area turns a finger into a stick.
///
/// Horizontal travel is the steering and gets nearly the whole range. Vertical travel only
/// matters for throwing an item forward or back, so it has its own, larger dead zone: a
/// thumb that wanders up or down while turning must not throw anything.
public struct SteerSpec: Equatable, Sendable {
    public var stick: PadStick
    /// Finger travel for full lock, in points.
    public var lockX: CGFloat
    /// Finger travel for full forward / back, in points.
    public var lockY: CGFloat
    /// Fraction of `lockY` that is ignored.
    public var deadY: Double
    /// Once the finger is this many `lockX` away the anchor follows it, so turning back
    /// is as quick as turning in, however far the thumb overshot.
    public var followPast: CGFloat
    /// Steering X comes from the device's motion; the finger only gives Y.
    public var tilt: Bool

    public init(stick: PadStick = .left, lockX: CGFloat, lockY: CGFloat, deadY: Double = 0.45,
                followPast: CGFloat = 1.3, tilt: Bool = false) {
        self.stick = stick
        self.lockX = lockX
        self.lockY = lockY
        self.deadY = deadY
        self.followPast = followPast
        self.tilt = tilt
    }
}

public enum SteerMath {
    /// A finger offset from the anchor (view points, +y down) as a console-convention stick
    /// value (+y up). Each axis has its own dead zone, rescaled so the output ramps from
    /// zero rather than jumping, and its own full-travel distance.
    public static func value(offset: CGPoint, spec: SteerSpec, deadX: Double, deadY: Double, curve: Double) -> StickValue {
        func axis(_ travel: CGFloat, _ lock: CGFloat, _ dead: Double, _ curve: Double) -> Double {
            guard lock > 0 else { return 0 }
            let raw = Double(abs(travel) / lock)
            guard raw > dead else { return 0 }
            let live = min((raw - dead) / max(1 - dead, 0.0001), 1)
            let shaped = pow(live, curve)
            return travel < 0 ? -shaped : shaped
        }
        let x = axis(offset.x, spec.lockX, deadX, curve)
        let y = -axis(offset.y, spec.lockY, deadY, 1)
        return StickValue(x: x, y: y == 0 ? 0 : y)
    }
}

/// One on-screen control, declaratively. Schemes are mostly just functions from a
/// `LayoutContext` to a list of these; `ControlScheme` does the touch handling for all of
/// them, so the four schemes differ in layout and in a few hooks, not in four separate
/// copies of hit testing.
public struct PadControl {
    public enum Kind {
        /// Held while a finger is on it.
        case button(PadButton)
        /// Eight-way d-pad. `shape` is the whole catchment; arms are drawn at `armOffset`
        /// (x, y) from its centre, `armSize` across. A finger that STARTS inside
        /// `clickRadius` holds `click` (L3 on the Wii U layout) until it leaves.
        case dpad(click: PadButton?, clickRadius: CGFloat, armOffset: CGPoint, armSize: CGFloat)
        /// Analog stick with a fixed base at `shape.center`.
        case stick(PadStick, travel: CGFloat, click: PadButton?)
        /// Analog stick whose base appears wherever the finger lands inside `shape`.
        /// `rest` is where the idle ghost is drawn. With `follow`, dragging past full
        /// travel drags the base along, so reversing direction is instant.
        case floatingStick(PadStick, travel: CGFloat, rest: CGPoint, follow: Bool, click: PadButton?)
        /// Relative "camera swipe": deflection follows finger VELOCITY, not position, and
        /// decays to centre when the finger stops. `fullSpeed` is points/second for full
        /// deflection.
        case swipeStick(PadStick, fullSpeed: CGFloat)
        /// A large held zone that presses a SET of buttons (A alone, A and R together, ...).
        /// A finger slides between the pedals of one `group` without lifting, with hysteresis
        /// so a thumb resting on a boundary doesn't flicker between them.
        case pedal(Set<PadButton>)
        /// Steering area: a stick whose anchor appears under the thumb, read mostly sideways.
        /// See `SteerSpec`.
        case steer(SteerSpec)
        /// Tap to take the current device angle as straight ahead (tilt steering).
        case recentre
    }

    public var kind: Kind
    public var shape: PadShape
    public var role: RenderElement.Role
    public var label: String
    /// Fingers may slide between BUTTONS of the same group (rolling a thumb from B to A).
    /// Group 0 = no sliding.
    public var group: Int
    /// Adaptive layouts move whole clusters; -1 = fixed.
    public var cluster: Int
    /// Catchment beyond the drawn edge, in points.
    public var reach: CGFloat
    /// Higher wins when several controls catch a finger. Buttons 1, zones 0, so a zone
    /// never steals a touch from a button drawn inside it.
    public var priority: Int
    /// Takes part in between-button chords (thumb across the gap presses both).
    public var chords: Bool

    public init(_ kind: Kind, shape: PadShape, role: RenderElement.Role, label: String = "",
                group: Int = 0, cluster: Int = -1, reach: CGFloat = 0, priority: Int = 1, chords: Bool = false) {
        self.kind = kind
        self.shape = shape
        self.role = role
        self.label = label
        self.group = group
        self.cluster = cluster
        self.reach = reach
        self.priority = priority
        self.chords = chords
    }

    public var button: PadButton? {
        if case .button(let b) = kind { return b }
        return nil
    }

    public var isZone: Bool {
        switch kind {
        case .floatingStick, .swipeStick, .steer: return true
        default: return false
        }
    }
}

/// Shared touch handling for control-list schemes. Subclasses override `makeControls`
/// and, optionally, the hooks.
open class ControlScheme: TouchScheme {
    public let info: SchemeInfo

    public private(set) var context = LayoutContext(size: .zero)
    /// Controls as laid out, before any cluster offset.
    public private(set) var baseControls: [PadControl] = []
    /// Controls as currently drawn and hit-tested.
    public private(set) var controls: [PadControl] = []
    /// Per-cluster displacement, for adaptive layouts. Applied on top of `baseControls`.
    public var clusterOffsets: [Int: CGPoint] = [:] {
        didSet { applyOffsets() }
    }

    /// Chord band, in units: a finger about equally far from two chording buttons (the
    /// two edge distances within this much of each other) presses both. That is what a
    /// thumb resting in the gap between them looks like.
    public var chordBand: CGFloat = 0.16
    /// Double-tap window for stick clicks.
    public var doubleTapInterval: Double = 0.30

    struct Track {
        var control: Int
        var start: CGPoint
        var startTime: Double
        var last: CGPoint
        var lastTime: Double
        var buttons: Set<PadButton> = []
        var origin: CGPoint = .zero          // stick base (floating sticks move it)
        var knob: CGPoint = .zero            // knob offset for drawing
        var clickHeld = false
        var velocity: CGPoint = .zero        // swipe sticks
        var stickValue: StickValue = .zero
    }

    var tracks: [TouchID: Track] = [:]
    /// Control indices by slide group, rebuilt whenever the controls are, so a finger moving
    /// doesn't scan the whole list for its neighbours on every sample.
    private var groupCache: [Int: [Int]] = [:]
    /// Last short, still tap per control - the first half of a double-tap.
    private var lastTap: [Int: (time: Double, point: CGPoint)] = [:]

    public init(info: SchemeInfo) {
        self.info = info
    }

    // MARK: - Subclass surface

    open func makeControls(_ context: LayoutContext) -> [PadControl] { [] }

    /// A finger has resolved onto a control at touch-down.
    open func didBegin(control index: Int, at point: CGPoint) {}

    /// A finger lifted normally (not cancelled). `track.start` is where it landed.
    open func didEnd(control index: Int, start: CGPoint, end: CGPoint, duration: Double) {}

    /// The last finger has lifted.
    open func didBecomeIdle() {}

    /// A finger landed on a recentre control.
    open func recentreRequested() {}

    // MARK: - TouchScheme

    public func layout(_ context: LayoutContext) {
        self.context = context
        tracks.removeAll()
        baseControls = makeControls(context).map { applyTolerance($0, context) }
        applyOffsets()
    }

    /// The player's touch tolerance: a button or pedal reaches at least as far past its drawn
    /// edge as MuffinEMU's own pad would let a touch miss by. Never less than the scheme's own.
    private func applyTolerance(_ c: PadControl, _ ctx: LayoutContext) -> PadControl {
        guard let tolerance = ctx.tolerance else { return c }
        switch c.kind {
        case .button, .pedal: break
        default: return c
        }
        let box = c.shape.boundingBox
        let radius = min(box.width, box.height) / 2
        var out = c
        out.reach = max(c.reach, (tolerance.reachFactor - 1) * radius)
        return out
    }

    private func applyOffsets() {
        defer {
            groupCache = [:]
            for (i, c) in controls.enumerated() where c.group != 0 { groupCache[c.group, default: []].append(i) }
        }
        controls = baseControls.map { c in
            guard c.cluster >= 0, let d = clusterOffsets[c.cluster], d != .zero else { return c }
            var moved = c
            moved.shape = c.shape.offset(by: d)
            if case let .floatingStick(s, travel, rest, follow, click) = c.kind {
                moved.kind = .floatingStick(s, travel: travel, rest: rest + d, follow: follow, click: click)
            }
            return moved
        }
    }

    public func claims(_ point: CGPoint) -> Bool {
        resolve(point) != nil
    }

    /// Best control for a finger landing at `point`, by priority then edge distance.
    func resolve(_ point: CGPoint) -> Int? {
        var best: (index: Int, priority: Int, distance: CGFloat)?
        for (i, c) in controls.enumerated() {
            let d = c.shape.edgeDistance(to: point)
            guard d <= c.reach else { continue }
            if let b = best {
                if c.priority < b.priority { continue }
                if c.priority == b.priority && d >= b.distance { continue }
            }
            best = (i, c.priority, d)
        }
        return best?.index
    }

    /// The button(s) under a finger among `candidates`, including a chord partner.
    func buttons(at point: CGPoint, among candidates: [Int]) -> (primary: Int, pressed: Set<PadButton>)? {
        let scored = candidates.compactMap { i -> (Int, CGFloat)? in
            let c = controls[i]
            guard c.button != nil else { return nil }
            let d = c.shape.edgeDistance(to: point)
            return d <= c.reach ? (i, d) : nil
        }.sorted { $0.1 < $1.1 }
        guard let first = scored.first, let b1 = controls[first.0].button else { return nil }
        var pressed: Set<PadButton> = [b1]
        let band = chordBand * context.unit
        if scored.count > 1, controls[first.0].chords {
            let second = scored[1]
            if controls[second.0].chords, second.1 - first.1 < band, second.1 > -band,
               let b2 = controls[second.0].button {
                pressed.insert(b2)
            }
        }
        return (first.0, pressed)
    }

    /// The pedal under a finger among `candidates`: the one whose edge the finger is deepest
    /// inside, or nearest to when it is in a gap.
    func pedals(at point: CGPoint, among candidates: [Int]) -> Int? {
        candidates
            .compactMap { i -> (Int, CGFloat)? in
                guard case .pedal = controls[i].kind else { return nil }
                let d = controls[i].shape.edgeDistance(to: point)
                return d <= controls[i].reach ? (i, d) : nil
            }
            .min { $0.1 < $1.1 }?.0
    }

    func pedalButtons(_ index: Int) -> Set<PadButton> {
        if case .pedal(let set) = controls[index].kind { return set }
        return []
    }

    public func began(_ touch: TouchID, at point: CGPoint, time: Double) -> Contribution? {
        guard let index = resolve(point) else { return nil }
        let c = controls[index]
        var t = Track(control: index, start: point, startTime: time, last: point, lastTime: time)

        switch c.kind {
        case .button:
            let hit = buttons(at: point, among: groupMembers(of: index)) ?? (index, [c.button!])
            t.control = hit.primary
            t.buttons = hit.pressed
        case let .dpad(click, clickRadius, _, _):
            if click != nil, point.distance(to: c.shape.center) <= clickRadius { t.clickHeld = true }
        case .stick(_, _, let click):
            // Relative: the centre is where the thumb landed, so landing is never a push.
            t.origin = context.stick.relativeCentre ? point : c.shape.center
            t.clickHeld = click != nil && isDoubleTap(index, point, time)
        case let .floatingStick(_, travel, _, _, click):
            t.origin = floatingOrigin(for: point, travel: travel)
            t.clickHeld = click != nil && isDoubleTap(index, point, time)
        case .swipeStick:
            break
        case .pedal:
            let hit = pedals(at: point, among: groupMembers(of: index)) ?? index
            t.control = hit
        case .steer:
            t.origin = point
        case .recentre:
            recentreRequested()
        }
        tracks[touch] = t
        didBegin(control: t.control, at: point)
        return contribution(for: &tracks[touch]!, at: point, time: time)
    }

    public func moved(_ touch: TouchID, to point: CGPoint, time: Double) -> Contribution {
        guard tracks[touch] != nil else { return .none }
        return contribution(for: &tracks[touch]!, at: point, time: time)
    }

    public func ended(_ touch: TouchID, at point: CGPoint, time: Double) {
        guard let t = tracks.removeValue(forKey: touch) else { return }
        let cancelled = point.x.isNaN
        // Only a tap arms a double-tap. Letting go of a stick after a flick and grabbing it
        // again quickly is ordinary play, and must not click L3.
        if !cancelled, time - t.startTime < 0.25, t.start.distance(to: t.last) < 0.3 * context.unit {
            lastTap[t.control] = (time, t.start)
        } else {
            lastTap[t.control] = nil
        }
        if !cancelled {
            didEnd(control: t.control, start: t.start, end: point, duration: time - t.startTime)
        }
        if tracks.isEmpty { didBecomeIdle() }
    }

    /// Set by a subclass that steers from the device's motion: replaces the finger's X on a
    /// steering area. nil = the finger steers.
    var steerOverrideX: Double?

    open func ambient() -> Contribution? { nil }
    open var wantsMotion: Bool { false }
    open func motion(angle: Double) -> [TouchID: Contribution] { [:] }

    public var needsTicks: Bool {
        tracks.values.contains { t in
            if case .swipeStick = controls[t.control].kind { return true }
            return false
        }
    }

    public func tick(time: Double) -> [TouchID: Contribution] {
        var out: [TouchID: Contribution] = [:]
        for (id, t) in tracks {
            guard case let .swipeStick(stick, fullSpeed) = controls[t.control].kind else { continue }
            // No move event for a while = the finger is resting; let the camera settle.
            let idle = time - t.lastTime
            guard idle > 1.0 / 90 else { continue }
            var track = t
            let decay = CGFloat(exp(-idle / 0.06))
            track.velocity = t.velocity * decay
            track.stickValue = swipeValue(track.velocity, fullSpeed: fullSpeed, stick: stick)
            tracks[id] = track
            out[id] = Contribution(stick: stick, stickValue: track.stickValue)
        }
        return out
    }

    // MARK: - Per-finger state machine

    private func groupMembers(of index: Int) -> [Int] {
        let g = controls[index].group
        guard g != 0 else { return [index] }
        return groupCache[g] ?? [index]
    }

    private func isDoubleTap(_ index: Int, _ point: CGPoint, _ time: Double) -> Bool {
        guard let last = lastTap[index] else { return false }
        return time - last.time <= doubleTapInterval && point.distance(to: last.point) <= 1.5 * context.unit
    }

    private func floatingOrigin(for point: CGPoint, travel: CGFloat) -> CGPoint {
        // Exactly under the thumb, even at the screen edge. Nudging the base inward would
        // make the landing itself a push - the stick would move before the thumb did.
        point
    }

    func contribution(for t: inout Track, at point: CGPoint, time: Double) -> Contribution {
        let c = controls[t.control]
        defer { t.last = point; t.lastTime = time }

        switch c.kind {
        case .button:
            // Slide: re-resolve within the group, with hysteresis - stay on the current
            // button until another is clearly closer, and let go only well past reach.
            let members = groupMembers(of: t.control)
            if let hit = buttons(at: point, among: members) {
                if hit.primary != t.control {
                    let current = c.shape.edgeDistance(to: point)
                    let challenger = controls[hit.primary].shape.edgeDistance(to: point)
                    // Switch when the other button is clearly closer, or when this one is
                    // no longer under the finger at all.
                    if challenger < current - 0.08 * context.unit || current > c.reach {
                        t.control = hit.primary
                    }
                }
                t.buttons = hit.primary == t.control ? hit.pressed : [controls[t.control].button!]
            } else if c.shape.edgeDistance(to: point) > c.reach + 0.5 * context.unit {
                // Well clear of everything: let go, but keep tracking so sliding back
                // presses again. Between reach and this, what was held stays held.
                t.buttons = []
            }
            return Contribution(buttons: t.buttons)

        case let .dpad(click, clickRadius, _, _):
            let offset = point - c.shape.center
            if t.clickHeld, offset.length > clickRadius * 1.3 { t.clickHeld = false }
            var pressed: Set<PadButton> = []
            if t.clickHeld, let click { pressed.insert(click) }
            if offset.length > clickRadius * 0.6 {
                pressed.formUnion(DPadMath.directions(angle: offset.screenAngle))
            }
            if t.clickHeld { pressed.subtract([.up, .down, .left, .right]) }
            t.buttons = pressed
            return Contribution(buttons: pressed)

        case let .stick(stick, travel, click):
            return stickContribution(&t, stick: stick, travel: travel, click: click, point: point,
                                     follow: context.stick.followsThumb, fixedBase: !context.stick.relativeCentre)

        case let .floatingStick(stick, travel, _, follow, click):
            return stickContribution(&t, stick: stick, travel: travel, click: click, point: point,
                                     follow: follow || context.stick.followsThumb, fixedBase: false)

        case .pedal:
            let members = groupMembers(of: t.control)
            if let best = pedals(at: point, among: members) {
                if best != t.control {
                    let current = c.shape.edgeDistance(to: point)
                    let challenger = controls[best].shape.edgeDistance(to: point)
                    // Hand over when the other pedal is clearly nearer, or this one has let go
                    // of the finger altogether.
                    if challenger < current - 0.08 * context.unit || current > c.reach {
                        t.control = best
                    }
                }
                t.buttons = pedalButtons(t.control)
            } else if c.shape.edgeDistance(to: point) > c.reach + 0.5 * context.unit {
                // Well clear of every pedal: let go, but keep tracking so sliding back presses again.
                t.buttons = []
            }
            return Contribution(buttons: t.buttons)

        case let .steer(spec):
            var offset = point - t.origin
            let follow = spec.lockX * spec.followPast
            if abs(offset.x) > follow {
                // Past the end of the travel: the anchor comes along, keeping the finger
                // `follow` away from it.
                t.origin.x += offset.x > 0 ? offset.x - follow : offset.x + follow
                offset = point - t.origin
            }
            // The player's calibration for this stick: their comfortable throw is full lock, and
            // their rest wobble is never steered on.
            let cal = context.calibration[spec.stick].clamped
            let tuning = context.stick.clamped
            var calibrated = spec
            calibrated.lockX = spec.lockX * CGFloat(cal.fullThrow)
            var value = SteerMath.value(offset: offset, spec: calibrated,
                                        deadX: max(tuning.deadzone, cal.jitter / cal.fullThrow), deadY: spec.deadY,
                                        curve: tuning.curve)
            var knobX = min(max(offset.x, -spec.lockX), spec.lockX)
            if let tilt = steerOverrideX {
                value.x = tilt
                knobX = CGFloat(tilt) * spec.lockX
            }
            t.knob = CGPoint(x: knobX, y: min(max(offset.y, -spec.lockY), spec.lockY))
            t.stickValue = value
            return Contribution(stick: spec.stick, stickValue: value)

        case .recentre:
            return .none

        case let .swipeStick(stick, fullSpeed):
            let dt = max(time - t.lastTime, 1.0 / 240)
            let instant = (point - t.last) * CGFloat(1 / dt)
            t.velocity = t.velocity * 0.45 + instant * 0.55
            t.stickValue = swipeValue(t.velocity, fullSpeed: fullSpeed, stick: stick)
            return Contribution(stick: stick, stickValue: t.stickValue)
        }
    }

    private func stickContribution(_ t: inout Track, stick: PadStick, travel: CGFloat, click: PadButton?,
                                   point: CGPoint, follow: Bool, fixedBase: Bool) -> Contribution {
        var offset = point - t.origin
        let reach = travel + StickMath.overtravel(travel)
        if follow, offset.length > reach {
            t.origin = t.origin + offset * (1 - reach / offset.length)
            offset = point - t.origin
        }
        t.knob = StickMath.knobOffset(offset: offset, travel: travel, gate: context.stick.gate)
        t.stickValue = StickMath.value(offset: offset, travel: travel, tuning: context.stick,
                                       calibration: context.calibration[stick], fixedBase: fixedBase)
        var buttons: Set<PadButton> = []
        if t.clickHeld, let click { buttons.insert(click) }
        t.buttons = buttons
        return Contribution(buttons: buttons, stick: stick, stickValue: t.stickValue)
    }

    private func swipeValue(_ v: CGPoint, fullSpeed: CGFloat, stick: PadStick) -> StickValue {
        var x = Double(v.x / fullSpeed), y = Double(-v.y / fullSpeed)
        let m = (x * x + y * y).squareRoot()
        if m > 1 { x /= m; y /= m }
        // A swipe has no travel to calibrate, but the player's rest wobble still isn't a swipe.
        if m < max(context.stick.deadzone, context.calibration[stick].clamped.jitter) { return .zero }
        return StickValue(x: x, y: y)
    }

    // MARK: - Rendering

    public func render(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> [RenderElement] {
        var out: [RenderElement] = []
        let active = Dictionary(tracks.values.map { ($0.control, $0) }, uniquingKeysWith: { a, _ in a })

        for (i, c) in controls.enumerated() {
            switch c.kind {
            case .button(let b):
                out.append(RenderElement(shape: c.shape, role: c.role, label: c.label, lit: pressed.contains(b)))

            case let .dpad(click, clickRadius, arm, size):
                let o = c.shape.center
                let arms: [(PadButton, CGPoint)] = [(.up, CGPoint(x: 0, y: -arm.y)), (.down, CGPoint(x: 0, y: arm.y)),
                                                    (.left, CGPoint(x: -arm.x, y: 0)), (.right, CGPoint(x: arm.x, y: 0))]
                for (b, d) in arms {
                    let rect = CGRect(center: o + d, size: CGSize(width: size, height: size))
                    out.append(RenderElement(shape: .roundedRect(rect, cornerRadius: size * 0.28), role: .dpad,
                                             label: b.description, lit: pressed.contains(b)))
                }
                if let click {
                    out.append(RenderElement(shape: .circle(center: o, radius: clickRadius), role: .dot,
                                             lit: pressed.contains(click)))
                }

            case let .stick(_, travel, click):
                let t = active[i]
                // The base stays put unless a finger has moved it (relative centre, follow).
                let base = t?.origin ?? c.shape.center
                out.append(RenderElement(shape: .circle(center: base, radius: travel + knobRadius), role: .stickBase,
                                         lit: t != nil))
                out.append(RenderElement(shape: .circle(center: base + (t?.knob ?? .zero), radius: knobRadius),
                                         role: .stickKnob, label: c.label,
                                         lit: click.map { pressed.contains($0) } ?? false))

            case let .floatingStick(_, travel, rest, _, click):
                out.append(RenderElement(shape: c.shape, role: .zone, ghost: true))
                if let t = active[i] {
                    out.append(RenderElement(shape: .circle(center: t.origin, radius: travel + knobRadius), role: .stickBase, lit: true))
                    out.append(RenderElement(shape: .circle(center: t.origin + t.knob, radius: knobRadius), role: .stickKnob,
                                             label: c.label, lit: click.map { pressed.contains($0) } ?? false))
                } else {
                    out.append(RenderElement(shape: .circle(center: rest, radius: travel + knobRadius), role: .stickBase, ghost: true))
                    out.append(RenderElement(shape: .circle(center: rest, radius: knobRadius), role: .stickKnob,
                                             label: c.label, ghost: true))
                }

            case .swipeStick:
                out.append(RenderElement(shape: c.shape, role: .zone, label: c.label, lit: active[i] != nil, ghost: true))

            case let .pedal(set):
                out.append(RenderElement(shape: c.shape, role: c.role, label: c.label, lit: set.isSubset(of: pressed)))

            case let .steer(spec):
                out.append(RenderElement(shape: c.shape, role: .area, label: c.label, lit: active[i] != nil))
                if spec.tilt {
                    // The wheel: a resting track and a knob that follows the device's angle.
                    let mid = c.shape.center
                    out.append(RenderElement(shape: .circle(center: mid, radius: spec.lockX + knobRadius), role: .stickBase, ghost: true))
                    let x = CGFloat(sticks[spec.stick]?.x ?? 0) * spec.lockX
                    out.append(RenderElement(shape: .circle(center: mid + CGPoint(x: x, y: 0), radius: knobRadius), role: .stickKnob,
                                             lit: x != 0, ghost: x == 0))
                } else if let t = active[i] {
                    out.append(RenderElement(shape: .circle(center: t.origin, radius: knobRadius * 0.3), role: .dot))
                    out.append(RenderElement(shape: .circle(center: t.origin + t.knob, radius: knobRadius), role: .stickKnob, lit: true))
                }

            case .recentre:
                out.append(RenderElement(shape: c.shape, role: c.role, label: c.label, lit: active[i] != nil))
            }
        }
        return out
    }

    public var knobRadius: CGFloat { context.unit * 0.575 }
}
