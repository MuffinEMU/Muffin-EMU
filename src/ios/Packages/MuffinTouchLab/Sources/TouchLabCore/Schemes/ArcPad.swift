import CoreGraphics
import Foundation

/// Scheme 6 - Arc Pad.
///
/// Controls fitted to the player's own hands. A thumb pivots on its base joint, so what it
/// sweeps is an arc: a circle around the joint. Every other scheme draws a button grid and
/// leaves the hand to cope. Arc measures the hand and puts the controls on its arcs.
///
/// Calibration (guided: left thumb, then right, then Done or Redo; `startCalibration()` runs
/// it again while unlocked): each hand's sweep is fitted with a
/// least-squares circle (pivot and radius, see `ArcMath.fitCircle`); the radial spread of
/// the samples gives the comfortable reach band, and the middle of the sweep is where the
/// thumb rests.
///
/// Layout, per hand, in the hand's own polar frame (radius from the pivot, angle measured
/// from straight up toward the middle of the screen):
/// - Right: A/B/X/Y on the arc at the comfortable radius, the same thumb travel apart
///   (equal angle), with A and B astride the rest angle. The right stick on the inner
///   ring at the rest angle. ZR/R on the outer ring toward the top.
/// - Left: the same, mirrored: the stick at the rest angle on the inner ring, the d-pad's
///   four directions on the arc, ZL/L on the outer ring.
/// - Plus, minus and HOME ride the outer ring beyond the shoulders, off the swept arc, so
///   a thumb moving between buttons never brushes them.
///
/// Input: a finger on the arc is assigned in ANGULAR coordinates around the pivot. A thumb
/// reaches too far or stops short far more often than it drifts sideways, and reach error
/// is radial while the choice of button is angular, so over- and undershoot never change
/// the button. Sliding along the arc rolls from one button to the next, and a finger
/// resting between two (or a wide contact patch spanning two) presses both.
///
/// Without calibration the arc comes from the device size and the usual thumb pivot at
/// the bottom corners, so it works with no setup. Calibration is stored per orientation
/// (`ArcPad.encode`/`decode`), as fractions of the screen so it survives window changes.
///
/// The layout never covers the video if there is any room beside it: it first avoids every
/// video rect, then only the GamePad touchscreen, and only on screens with no margin at
/// all (a 16:9 video filling a phone) does it fall back to drawing over the video.
public final class ArcPad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "arc",
        name: "Arc",
        summary: "Measures how each thumb sweeps and puts every control on that arc, picked by angle so reaching a bit far or short still hits the right button.")

    public enum Avoidance: String, Sendable {
        /// Clear of every video rect (or there was nothing to avoid).
        case video
        /// Clear of the GamePad touchscreen only; the TV image is covered.
        case gamepad
        /// Over the video: no margin was big enough, so this is the placement that covers
        /// the least of it.
        case none
    }

    public enum CalibrationPhase: Equatable, Sendable {
        case left, right, review
    }

    // MARK: Public state

    public private(set) var profiles: [String: ArcProfile]
    /// Called with the new profiles after any change that should be saved.
    public var onProfiles: (([String: ArcProfile]) -> Void)?
    /// Called whenever lock, fine-tune or calibration state changes, so a settings UI can
    /// rebind. Not called for ordinary presses.
    public var onSettingsChange: (() -> Void)?
    /// The hands as laid out (radius is the one actually used, which may be smaller than
    /// the fitted one when the screen has no room for it).
    public private(set) var hands: [ArcHand] = []
    public private(set) var avoidance: Avoidance = .none
    /// True when the arc layout could not be fitted at any size and Zone-style
    /// controls are shown instead.
    public private(set) var usingFallback = false
    /// The size of one button as laid out, in points.
    public private(set) var layoutUnit: CGFloat = 0
    /// Contact major radius of the finger about to be delivered (`UITouch.majorRadius`),
    /// in points. The host sets it before `began`/`moved`; 0 when unknown. A bigger patch
    /// is a more generous radial catchment and a wider chord.
    public var contactRadius: CGFloat = 0

    /// Where messages about forced fallbacks go (once per screen situation).
    public static var logSink: (String) -> Void = { NSLog("%@", $0) }
    public static var logged = Set<String>()

    // MARK: Settings API (lock, fine-tune, calibration)

    /// Whether positions are locked for the current orientation. Off until the first
    /// calibration completes, then on automatically. While locked, nothing moves: no
    /// calibration, no fine-tuning, positions are exactly the saved ones.
    public var isLocked: Bool { profiles[orientation]?.locked ?? false }

    public func setLocked(_ on: Bool) {
        var p = profiles[orientation] ?? ArcProfile()
        guard (p.locked ?? false) != on else { return }
        p.locked = on
        profiles[orientation] = p
        if on {
            tuneTracks.removeAll()
            tuning = false
            if calibrator != nil { calibrator = nil }
        }
        save()
        notify()
    }

    /// True once the current orientation has a saved calibration for either hand.
    public var hasCalibration: Bool {
        guard let p = profiles[orientation] else { return false }
        return p.left != nil || p.right != nil
    }

    public var isFineTuning: Bool { tuning }

    /// Fine-tune mode: drag any control along its arc (angle) or in and out (radius) and
    /// that hand's layout follows; each hand is tuned on its own and the result is saved
    /// per orientation. Refused (false) while locked. Presses do nothing in this mode.
    @discardableResult
    public func setFineTuning(_ on: Bool) -> Bool {
        if on {
            guard !isLocked, calibrator == nil else { return false }
        }
        tuning = on
        tuneTracks.removeAll()
        notify()
        return true
    }

    /// Back to the default arc for the current orientation: calibration, fine-tuning and
    /// the lock are all cleared.
    public func resetToDefault() {
        profiles[orientation] = nil
        tuning = false
        tuneTracks.removeAll()
        calibrator = nil
        save()
        relayout()
        notify()
    }

    /// Old name for `resetToDefault`.
    public func resetCalibration() { resetToDefault() }

    // MARK: Calibration

    public var isCalibrating: Bool { calibrator != nil }
    public var calibrationPhase: CalibrationPhase? { calibrator?.phase }
    /// Shown under the prompt when the last sweep could not be used.
    public var calibrationNote: String? { calibrator?.note }

    public var calibrationPrompt: String {
        switch calibrator?.phase {
        case .left?: return "Sweep your left thumb in a comfortable arc."
        case .right?: return "Sweep your right thumb in a comfortable arc."
        case .review?: return "Happy with these arcs? Tap Done, or Redo."
        case nil: return ""
        }
    }

    /// Begin the guided sweep: left thumb, then right, then a review. Refused (false)
    /// while positions are locked; unlock first.
    @discardableResult
    public func startCalibration() -> Bool {
        guard !isLocked else { return false }
        arcTracks.removeAll()
        tracks.removeAll()
        tuneTracks.removeAll()
        tuning = false
        calibrator = Calibrator()
        notify()
        return true
    }

    /// Leave the hand being swept as it is (its default or previous arc) and move on.
    public func skipCalibrationHand() {
        guard var cal = calibrator else { return }
        switch cal.phase {
        case .left: cal.phase = .right
        case .right: cal.phase = .review
        case .review: break
        }
        cal.note = nil
        calibrator = cal
        notify()
    }

    /// Throw the sweeps away and start again with the left thumb.
    public func redoCalibration() {
        guard calibrator != nil else { return }
        calibrator = Calibrator()
        notify()
    }

    /// Leave calibration without changing anything.
    public func cancelCalibration() {
        guard calibrator != nil else { return }
        calibrator = nil
        notify()
    }

    /// Old name for `cancelCalibration`.
    public func skipCalibration() { cancelCalibration() }

    /// Accept the reviewed arcs: save them, and lock positions.
    public func acceptCalibration() {
        guard let cal = calibrator else { return }
        calibrator = nil
        guard !cal.fits.isEmpty else { notify(); return }
        var p = profiles[orientation] ?? ArcProfile()
        for (side, fit) in cal.fits {
            if side == .left { p.left = fit; p.leftTweaks = nil } else { p.right = fit; p.rightTweaks = nil }
        }
        p.locked = true
        profiles[orientation] = p
        save()
        relayout()
        notify()
    }

    /// Turns raw sweep samples into a stored hand, or nil when they do not describe a
    /// thumb arc (too few, too short, nearly straight, pivot nowhere near the screen).
    static func makeFit(side: ArcSide, samples: [CGPoint], ctx: LayoutContext) -> ArcHandFit? {
        let u = ctx.unit
        let size = ctx.size
        guard size.width > 0, size.height > 0, samples.count >= 12,
              let fit = ArcMath.fitCircle(samples) else { return nil }
        guard fit.radius >= 3 * u, fit.radius <= 16 * u else { return nil }
        guard fit.center.x > -size.width, fit.center.x < 2 * size.width,
              fit.center.y > -size.height, fit.center.y < 2 * size.height else { return nil }
        let probe = ArcHand(side: side, pivot: fit.center, radius: fit.radius, spread: fit.rms,
                            rest: 0, lo: 0, hi: 0, calibrated: true)
        let phis = samples.map { probe.polar($0).phi }
        let med = ArcMath.quantile(phis, 0.5)
        // The sweep has to be above the pivot and run toward the middle of the screen.
        guard med > 0.05, med < 1.6 else { return nil }
        let lo = ArcMath.quantile(phis, 0.05), hi = ArcMath.quantile(phis, 0.95)
        guard hi - lo >= 0.35 else { return nil }
        let short = min(size.width, size.height)
        return ArcHandFit(pivotX: Double(fit.center.x / size.width), pivotY: Double(fit.center.y / size.height),
                          radius: Double(fit.radius / short), spread: Double(fit.rms / short),
                          rest: Double(med), lo: Double(lo), hi: Double(hi))
    }

    // MARK: Private state

    struct ArcSet {
        var hand: ArcHand
        var phis: [CGFloat]
        var delta: CGFloat
        var buttons: [PadButton]
    }

    private struct ArcTrack {
        var set: Int
        var slot: Int
        var buttons: Set<PadButton>
    }

    private struct TuneTrack {
        var side: ArcSide
        var key: String
        var last: CGPoint
    }

    private struct Calibrator {
        var phase: CalibrationPhase = .left
        var samples: [ArcSide: [CGPoint]] = [:]
        var fits: [ArcSide: ArcHandFit] = [:]
        var active: TouchID?
        var note: String?
        var side: ArcSide { phase == .right ? .right : .left }
    }

    private var arcSets: [ArcSet] = []
    private var arcTracks: [TouchID: ArcTrack] = [:]
    private var tuneTracks: [TouchID: TuneTrack] = [:]
    private var tuning = false
    private var guides: [CGPoint] = []
    private var calibrator: Calibrator?

    static let leftPadGroup = 22

    public init(profiles: [String: ArcProfile] = [:]) {
        self.profiles = profiles
        super.init(info: Self.schemeInfo)
    }

    private var orientation: String { Self.orientationKey(context.size) }

    private func save() { onProfiles?(profiles) }
    private func notify() { onSettingsChange?() }
    private func relayout() { if context.size != .zero { layout(context) } }

    // MARK: Persistence

    public static func encode(_ profiles: [String: ArcProfile]) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(profiles) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String) -> [String: ArcProfile] {
        guard let p = try? JSONDecoder().decode([String: ArcProfile].self, from: Data(json.utf8)) else { return [:] }
        // Anything non-finite or absurd is dropped rather than trusted.
        return p.filter { $0.value.isSane }
    }

    public static func orientationKey(_ size: CGSize) -> String {
        size.width >= size.height ? "landscape" : "portrait"
    }

    // MARK: Layout

    override public func layout(_ context: LayoutContext) {
        arcTracks.removeAll()
        super.layout(context)
    }

    private struct Placement {
        var controls: [PadControl]
        var sets: [ArcSet]
        var cost: CGFloat = 0
    }

    private struct Room {
        let safe: CGRect
        let keep: [CGRect]
        let u: CGFloat
        let short: CGFloat
        /// Soft rooms may overlap `keep`; the layout then minimises how much.
        let soft: Bool

        func inside(_ shape: PadShape) -> Bool {
            let b = shape.boundingBox
            return b.minX >= safe.minX && b.maxX <= safe.maxX && b.minY >= safe.minY && b.maxY <= safe.maxY
        }

        func clear(_ shape: PadShape) -> Bool {
            let b = shape.boundingBox.insetBy(dx: -2, dy: -2)
            return !keep.contains { $0.intersects(b) }
        }

        func fits(_ c: PadControl, _ placed: [PadControl], needClear: Bool) -> Bool {
            guard inside(c.shape) else { return false }
            if needClear, !clear(c.shape) { return false }
            return !placed.contains { c.shape.overlaps($0.shape, margin: -0.1 * u) }
        }

        /// Area of the controls that lies over `keep`, in squared buttons.
        func cost(_ controls: [PadControl]) -> CGFloat {
            var total: CGFloat = 0
            for c in controls where !c.isZone {
                let b = c.shape.boundingBox
                for k in keep {
                    let i = b.intersection(k)
                    if !i.isNull { total += i.width * i.height }
                }
            }
            return total / (u * u)
        }
    }

    /// Grid of offsets around an ideal point, nearest first, in button units.
    private static let unitOffsets: [CGPoint] = {
        var out: [CGPoint] = []
        var y = -3.6
        while y <= 3.601 {
            var x = -3.6
            while x <= 3.601 {
                out.append(CGPoint(x: x, y: y))
                x += 0.3
            }
            y += 0.3
        }
        return out.sorted { $0.length < $1.length }
    }()

    /// The valid control nearest to `ideal`: how the shoulder row, the system buttons and
    /// the stick find a spot when the exact polar one is off the screen or taken. In a
    /// soft room it prefers a spot clear of the video and only then settles for one over it.
    private func nearest(_ ideal: CGPoint, room: Room, placed: [PadControl],
                         accept: (PadControl) -> Bool = { _ in true },
                         make: (CGPoint) -> PadControl) -> PadControl? {
        for needClear in room.soft ? [true, false] : [true] {
            for off in Self.unitOffsets {
                let c = make(CGPoint(x: ideal.x + off.x * room.u, y: ideal.y + off.y * room.u))
                if room.fits(c, placed, needClear: needClear), accept(c) { return c }
            }
        }
        return nil
    }

    private func build(hand h0: ArcHand, rest: CGFloat, tight: Bool, stickScale: CGFloat,
                       tweaks tw: [String: ArcTweak], room: Room, placed: [PadControl]) -> Placement? {
        let u = room.u
        func tweak(_ key: String) -> (dphi: CGFloat, dr: CGFloat) {
            guard let t = tw[key] else { return (0, 0) }
            return (CGFloat(t.dphi), CGFloat(t.dr) * room.short)
        }
        var h = h0
        h.radius = h0.radius + tweak("arc").dr
        let R = h.radius
        guard R > u else { return nil }
        let restArc = rest + tweak("arc").dphi
        let minDelta = 1.28 * u / R, maxDelta = 1.9 * u / R
        let delta = tight ? minDelta : h.calibrated ? ArcMath.clamp((h.hi - h.lo) / 3.6, minDelta, maxDelta) : 1.4 * u / R
        let right = h.side == .right
        // The arc reads from the outer end inward: A, B, X, Y on the right.
        let buttons: [PadButton] = right ? [.a, .b, .x, .y] : [.up, .right, .down, .left]
        var out: [PadControl] = []
        var phis: [CGFloat] = []

        // The arc itself: exact positions, equal angle apart, centred on the rest angle so
        // no button is harder to reach than another.
        for (k, b) in buttons.enumerated() {
            let phi = restArc + (CGFloat(k) - 1.5) * delta
            let c = PadControl(.button(b), shape: .circle(center: h.point(r: R, phi: phi), radius: u / 2),
                               role: right ? .face : .dpad, label: b.description,
                               group: right ? PadParts.Group.face : Self.leftPadGroup,
                               reach: 0.2 * u, chords: true)
            guard room.fits(c, placed + out, needClear: !room.soft) else { return nil }
            out.append(c)
            phis.append(phi)
        }

        // Stick on the inner ring, at the rest angle.
        let ts = tweak("stick")
        let rIn = max(h0.radius - 3.1 * u + ts.dr, 0.6 * u)
        let stickSide: PadStick = right ? .right : .left
        guard let stick = nearest(h.point(r: rIn, phi: rest + ts.dphi), room: room, placed: placed + out, make: {
            PadParts.stick(stickSide, at: $0, u: u, scale: stickScale, click: right ? .stickR : .stickL)
        }) else { return nil }
        out.append(stick)

        // Shoulders and system buttons on the outer ring, toward the top.
        let rOut = h0.radius + 2.5 * u
        // Nothing but the arc's own buttons may sit in the arc's band: a thumb reaching a
        // little far must not land on a shoulder or HOME.
        let sector = (lo: phis[0] - 0.9 * delta - 0.25, hi: phis[3] + 0.9 * delta + 0.25)
        func offBand(_ c: PadControl) -> Bool {
            let (r, phi) = h.polar(c.shape.center)
            let b = c.shape.boundingBox
            return phi < sector.lo || phi > sector.hi || r - max(b.width, b.height) / 2 >= R + 1.65 * u
        }
        let step = 1.75 * u / rOut
        let phi0: CGFloat = 0.16
        let shoulderSize = CGSize(width: 1.5 * u, height: 0.9 * u)
        let group = right ? PadParts.Group.rightShoulders : PadParts.Group.leftShoulders
        func ideal(_ key: String, _ slot: CGFloat) -> CGPoint {
            let t = tweak(key)
            return h.point(r: rOut + t.dr, phi: phi0 + slot * step + t.dphi)
        }
        func shoulder(_ b: PadButton, _ key: String, _ slot: CGFloat) -> PadControl? {
            nearest(ideal(key, slot), room: room, placed: placed + out, accept: offBand, make: {
                PadParts.shoulder(b, CGRect(center: $0, size: shoulderSize), u: u, group: group)
            })
        }
        func system(_ b: PadButton, _ key: String, _ slot: CGFloat) -> PadControl? {
            nearest(ideal(key, slot), room: room, placed: placed + out, accept: offBand, make: {
                PadParts.system(b, at: $0, u: u)
            })
        }
        guard let outer = shoulder(right ? .zr : .zl, "s0", 0) else { return nil }
        out.append(outer)
        guard let inner = shoulder(right ? .r : .l, "s1", 1) else { return nil }
        out.append(inner)
        guard let sys = system(right ? .plus : .minus, "sys", 2) else { return nil }
        out.append(sys)
        if !right {
            guard let home = system(.home, "home", 3) else { return nil }
            out.append(home)
        }
        return Placement(controls: out, sets: [ArcSet(hand: h, phis: phis, delta: delta, buttons: buttons)],
                         cost: room.soft ? room.cost(out) : 0)
    }

    private func bestHand(_ h: ArcHand, tweaks: [String: ArcTweak], room: Room, placed: [PadControl]) -> Placement? {
        let radii: [CGFloat] = h.calibrated ? [1, 0.92, 0.84, 0.76, 0.68, 0.55] : [1, 0.88, 0.76, 0.64, 0.52, 0.4]
        let shifts: [CGFloat] = [0, -0.08, -0.16, -0.24, -0.32, -0.4, -0.48, -0.56, -0.64, -0.72, -0.8,
                                 0.08, 0.16, 0.24, 0.32, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
        var best: Placement?
        // A soft room (the video fills the screen) never reaches zero cost, so it searches a
        // coarser grid than a strict one, which stops at the first fit.
        for ss in room.soft ? [CGFloat(1)] : [CGFloat(1), 0.82] {
            for rs in room.soft ? Array(radii.prefix(3)) : radii {
                var hand = h
                hand.radius = h.radius * rs
                for tight in [false, true] {
                    for d in room.soft ? shifts.enumerated().filter({ $0.offset % 2 == 0 }).map(\.element) : shifts {
                        guard let p = build(hand: hand, rest: h.rest + d, tight: tight, stickScale: ss,
                                            tweaks: tweaks, room: room, placed: placed) else { continue }
                        if !room.soft || p.cost == 0 { return p }
                        if best == nil || p.cost < best!.cost { best = p }
                    }
                }
            }
        }
        return best
    }

    private func attempt(left: ArcHand, right: ArcHand, tweaks: (left: [String: ArcTweak], right: [String: ArcTweak]),
                         room: Room) -> Placement? {
        guard let r = bestHand(right, tweaks: tweaks.right, room: room, placed: []),
              let l = bestHand(left, tweaks: tweaks.left, room: room, placed: r.controls) else { return nil }
        let all = r.controls + l.controls
        guard LayoutCheck.problems(all, in: room.safe).isEmpty else { return nil }
        return Placement(controls: all, sets: r.sets + l.sets, cost: r.cost + l.cost)
    }

    override public func makeControls(_ ctx: LayoutContext) -> [PadControl] {
        arcSets = []
        hands = []
        guides = []
        usingFallback = false
        layoutUnit = ctx.unit
        let s = ctx.safeBounds
        guard s.width > 0, s.height > 0 else { avoidance = .none; return [] }

        let profile = profiles[Self.orientationKey(ctx.size)]
        let right = Self.hand(.right, fit: profile?.right, ctx)
        let left = Self.hand(.left, fit: profile?.left, ctx)
        let tweaks = (left: profile?.leftTweaks ?? [:], right: profile?.rightTweaks ?? [:])
        let short = min(ctx.size.width, ctx.size.height)

        var everything = ctx.videoRects
        if let t = ctx.touchscreenRect { everything.append(t) }
        var strict: [(Avoidance, [CGRect])] = [(.video, everything)]
        if let t = ctx.touchscreenRect, everything.count > 1 { strict.append((.gamepad, [t])) }

        func adopt(_ p: Placement, _ room: Room, _ av: Avoidance) -> [PadControl] {
            avoidance = av
            layoutUnit = room.u
            arcSets = p.sets
            hands = p.sets.map(\.hand)
            guides = makeGuides(p.sets, room: room)
            return p.controls
        }

        // No margin worth searching (the video fills the screen): go straight to the
        // least-overlap placement.
        let hull = everything.reduce(CGRect.null) { $0.union($1) }
        let freeW = hull.isNull ? s.width : max(hull.minX - s.minX, s.maxX - hull.maxX)
        let freeH = hull.isNull ? s.height : max(hull.minY - s.minY, s.maxY - hull.maxY)
        let hopeless = !hull.isNull && max(freeW, freeH) < 1.6 * ctx.unit
        for (av, keep) in strict where !hopeless {
            var k: CGFloat = 1
            while k >= 0.4 - 0.001 {
                let room = Room(safe: s, keep: keep, u: ctx.unit * k, short: short, soft: false)
                if let p = attempt(left: left, right: right, tweaks: tweaks, room: room) { return adopt(p, room, av) }
                k *= 0.92
            }
        }

        // No room beside the video (it fills the screen): hug the edges and cover as
        // little of it as possible.
        var best: (Placement, Room)?
        for k in [CGFloat(1), 0.8, 0.6] {
            let room = Room(safe: s, keep: everything, u: ctx.unit * k, short: short, soft: true)
            guard let p = attempt(left: left, right: right, tweaks: tweaks, room: room) else { continue }
            let score = p.cost + (1 - k) * 2
            if best == nil || score < best!.0.cost + (1 - best!.1.u / ctx.unit) * 2 { best = (p, room) }
        }
        if let (p, room) = best {
            logOnce("Arc: no room beside the video on \(Int(ctx.size.width))x\(Int(ctx.size.height)); using the placement that covers the least (\(String(format: "%.1f", Double(p.cost))) buttons of overlap)")
            return adopt(p, room, .none)
        }
        // Nothing fits (a tiny window): the same safe arrangement the other schemes use.
        avoidance = .none
        usingFallback = true
        logOnce("Arc: \(Int(ctx.size.width))x\(Int(ctx.size.height)) is too small for the arc layout; using the plain arrangement")
        return GamePadArrangement.build(ctx)
    }

    private func logOnce(_ message: String) {
        let key = "\(message)|\(context.videoRects)"
        guard !Self.logged.contains(key) else { return }
        Self.logged.insert(key)
        Self.logSink(message)
    }

    private func makeGuides(_ sets: [ArcSet], room: Room) -> [CGPoint] {
        var out: [CGPoint] = []
        for set in sets {
            let h = set.hand
            let dphi = 0.3 * room.u / h.radius
            var phi = set.phis[0] - 1.5 * set.delta
            let end = set.phis[3] + 1.5 * set.delta
            while phi <= end {
                let p = h.point(r: h.radius, phi: phi)
                if room.safe.contains(p), room.soft || !room.keep.contains(where: { $0.contains(p) }) { out.append(p) }
                phi += dphi
            }
        }
        return out
    }

    /// Defaults before calibration: the thumb pivots just below the bottom corner of the
    /// safe area, and the comfortable reach is about five buttons.
    static func hand(_ side: ArcSide, fit: ArcHandFit?, _ ctx: LayoutContext) -> ArcHand {
        let s = ctx.safeBounds
        let u = ctx.unit
        let short = min(ctx.size.width, ctx.size.height)
        if let f = fit {
            return ArcHand(side: side,
                           pivot: CGPoint(x: CGFloat(f.pivotX) * ctx.size.width, y: CGFloat(f.pivotY) * ctx.size.height),
                           radius: CGFloat(f.radius) * short, spread: CGFloat(f.spread) * short,
                           rest: CGFloat(f.rest), lo: CGFloat(f.lo), hi: CGFloat(f.hi), calibrated: true)
        }
        return ArcHand(side: side,
                       pivot: CGPoint(x: side == .right ? s.maxX : s.minX, y: s.maxY + 0.4 * u),
                       radius: 5.2 * u, spread: 0.55 * u,
                       rest: .pi / 4, lo: 0.2, hi: 1.2, calibrated: false)
    }

    // MARK: Input

    override public func claims(_ point: CGPoint) -> Bool {
        if calibrator != nil { return true }
        if tuning { return tuneTarget(at: point) != nil }
        return arcHit(at: point, expand: 0) != nil || super.claims(point)
    }

    override public func began(_ touch: TouchID, at point: CGPoint, time: Double) -> Contribution? {
        if var cal = calibrator {
            if cal.phase != .review, cal.active == nil {
                cal.active = touch
                cal.samples[cal.side] = [point]
                cal.note = nil
                calibrator = cal
                notify()
            }
            return Contribution.none
        }
        if tuning {
            guard let (side, key) = tuneTarget(at: point) else { return nil }
            tuneTracks[touch] = TuneTrack(side: side, key: key, last: point)
            return Contribution.none
        }
        if let hit = arcHit(at: point, expand: 0), !onOtherControl(point) {
            let t = ArcTrack(set: hit.set, slot: hit.slot, buttons: hit.pressed)
            arcTracks[touch] = t
            return Contribution(buttons: t.buttons)
        }
        return super.began(touch, at: point, time: time)
    }

    override public func moved(_ touch: TouchID, to point: CGPoint, time: Double) -> Contribution {
        if calibrator != nil {
            if calibrator!.active == touch {
                let side = calibrator!.side
                let last = calibrator!.samples[side]?.last
                if last == nil || last!.distance(to: point) >= 2 { calibrator!.samples[side, default: []].append(point) }
            }
            return Contribution.none
        }
        if tuning {
            guard var t = tuneTracks[touch], let hand = hands.first(where: { $0.side == t.side }) else { return .none }
            let a = hand.polar(t.last), b = hand.polar(point)
            applyTweak(side: t.side, key: t.key, dphi: b.phi - a.phi, dr: b.r - a.r)
            t.last = point
            tuneTracks[touch] = t
            relayout()
            return Contribution.none
        }
        guard var t = arcTracks[touch] else { return super.moved(touch, to: point, time: time) }
        let set = arcSets[t.set]
        if let hit = arcHit(at: point, expand: 0), hit.set == t.set {
            if hit.slot == t.slot {
                t.buttons = hit.pressed
            } else {
                // Hysteresis: stay on the current button until the other is clearly closer.
                let phi = set.hand.polar(point).phi
                if abs(phi - set.phis[hit.slot]) < abs(phi - set.phis[t.slot]) - 0.12 * set.delta {
                    t.slot = hit.slot
                    t.buttons = hit.pressed
                } else {
                    t.buttons = [set.buttons[t.slot]]
                }
            }
        } else if arcHit(at: point, expand: 0.7 * layoutUnit, preferSet: t.set) == nil {
            // Well clear of the arc: let go, but keep following so sliding back presses again.
            t.buttons = []
        }
        arcTracks[touch] = t
        return Contribution(buttons: t.buttons)
    }

    override public func ended(_ touch: TouchID, at point: CGPoint, time: Double) {
        if var cal = calibrator {
            guard cal.active == touch else { return }
            cal.active = nil
            let side = cal.side
            if !point.x.isNaN,
               let fit = Self.makeFit(side: side, samples: cal.samples[side] ?? [], ctx: context) {
                cal.fits[side] = fit
                cal.phase = cal.phase == .left ? .right : .review
                cal.note = nil
            } else {
                cal.samples[side] = []
                cal.note = "That sweep was too short or too straight. Try a longer, smoother arc."
            }
            calibrator = cal
            notify()
            return
        }
        if tuneTracks.removeValue(forKey: touch) != nil {
            if tuneTracks.isEmpty, !point.x.isNaN { save(); notify() }
            return
        }
        if arcTracks.removeValue(forKey: touch) != nil { return }
        super.ended(touch, at: point, time: time)
    }

    // MARK: Fine-tune

    private func tuneTarget(at p: CGPoint) -> (ArcSide, String)? {
        if let hit = arcHit(at: p, expand: 0.5 * layoutUnit) { return (arcSets[hit.set].hand.side, "arc") }
        guard let i = resolve(p) else { return nil }
        let c = controls[i]
        switch c.kind {
        case .stick(let s, _, _): return (s == .left ? .left : .right, "stick")
        case .button(let b):
            switch b {
            case .zl: return (.left, "s0")
            case .l: return (.left, "s1")
            case .zr: return (.right, "s0")
            case .r: return (.right, "s1")
            case .minus: return (.left, "sys")
            case .plus: return (.right, "sys")
            case .home: return (.left, "home")
            default: return (c.group == Self.leftPadGroup ? .left : .right, "arc")
            }
        default: return nil
        }
    }

    private func applyTweak(side: ArcSide, key: String, dphi: CGFloat, dr: CGFloat) {
        let short = min(context.size.width, context.size.height)
        guard short > 0 else { return }
        var p = profiles[orientation] ?? ArcProfile()
        var tw = (side == .left ? p.leftTweaks : p.rightTweaks) ?? [:]
        var t = tw[key] ?? ArcTweak(dphi: 0, dr: 0)
        t.dphi = Double(ArcMath.clamp(CGFloat(t.dphi) + dphi, -1.2, 1.2))
        t.dr = Double(ArcMath.clamp(CGFloat(t.dr) + dr / short, -0.4, 0.4))
        tw[key] = t
        if side == .left { p.leftTweaks = tw } else { p.rightTweaks = tw }
        profiles[orientation] = p
    }

    /// A shoulder or system button the finger is directly on beats the arc.
    private func onOtherControl(_ p: CGPoint) -> Bool {
        controls.contains { c in
            guard !c.isZone, c.group != PadParts.Group.face, c.group != Self.leftPadGroup else { return false }
            // The arc outranks the stick base where they touch: the stick has the whole
            // inner ring, the arc buttons have only their band.
            if case .stick = c.kind { return false }
            return c.shape.edgeDistance(to: p) <= 0
        }
    }

    struct ArcHit {
        var set: Int
        var slot: Int
        var pressed: Set<PadButton>
    }

    /// The arc button a finger at `p` means, if any. Radius only decides whether the
    /// finger is on the arc's band at all; WHICH button is decided by angle alone.
    func arcHit(at p: CGPoint, expand: CGFloat, preferSet: Int? = nil) -> ArcHit? {
        let u = layoutUnit
        let contact = min(contactRadius, 0.9 * u)
        var best: (hit: ArcHit, err: CGFloat)?
        for (si, set) in arcSets.enumerated() {
            if let want = preferSet, want != si { continue }
            let (r, phi) = set.hand.polar(p)
            let R = set.hand.radius
            let slack = contact * 0.5 + expand
            guard r >= R - 1.05 * u - slack, r <= R + 1.6 * u + slack else { continue }
            let angSlack = expand / max(r, 1)
            guard phi >= set.phis[0] - 0.9 * set.delta - angSlack,
                  phi <= set.phis[3] + 0.9 * set.delta + angSlack else { continue }
            let dists = set.phis.map { abs($0 - phi) }
            var k = 0
            for i in 1..<dists.count where dists[i] < dists[k] { k = i }
            var pressed: Set<PadButton> = [set.buttons[k]]
            // A thumb between two buttons presses both; a wide contact patch counts as
            // reaching further toward its neighbour.
            let band = (self.chordBand * u + contact * 0.6) / max(r, 1)
            var second: Int?
            if k > 0, (second == nil || dists[k - 1] < dists[second!]) { second = k - 1 }
            if k < dists.count - 1, (second == nil || dists[k + 1] < dists[second!]) { second = k + 1 }
            if let s2 = second, dists[s2] - dists[k] < band, dists[s2] < set.delta {
                pressed.insert(set.buttons[s2])
            }
            let hit = ArcHit(set: si, slot: k, pressed: pressed)
            if best == nil || dists[k] < best!.err { best = (hit, dists[k]) }
        }
        return best?.hit
    }

    // MARK: Rendering

    override public func render(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> [RenderElement] {
        var out: [RenderElement] = []
        let u = context.unit
        func banner(_ text: String, row: CGFloat) {
            let pill = CGRect(center: CGPoint(x: context.size.width / 2, y: context.safeBounds.minY + (1.1 + row * 1.1) * u),
                              size: CGSize(width: min(context.size.width - 2 * u, 12 * u), height: 0.9 * u))
            out.append(RenderElement(shape: .roundedRect(pill, cornerRadius: 0.45 * u), role: .system, label: text))
        }
        if let cal = calibrator {
            // Controls fade back; the sweep draws itself under the thumbs.
            out = super.render(pressed: [], sticks: [:]).map { e in
                var g = e; g.ghost = true; return g
            }
            banner(calibrationPrompt, row: 0)
            if let note = cal.note { banner(note, row: 1) }
            for side in [ArcSide.left, .right] {
                for p in (cal.samples[side] ?? []).suffix(200) {
                    out.append(RenderElement(shape: .circle(center: p, radius: 3), role: .dot, lit: true))
                }
            }
            if cal.phase == .review {
                for (side, fit) in cal.fits {
                    let h = Self.hand(side, fit: fit, context)
                    var phi = h.lo
                    while phi <= h.hi {
                        out.append(RenderElement(shape: .circle(center: h.point(r: h.radius, phi: phi), radius: 2), role: .dot))
                        phi += 0.3 * u / h.radius
                    }
                }
            }
            return out
        }
        for g in guides {
            out.append(RenderElement(shape: .circle(center: g, radius: 1.7), role: .dot, ghost: true))
        }
        out += super.render(pressed: tuning ? [] : pressed, sticks: sticks)
        if tuning { banner("Drag a control along its arc, or in and out", row: 0) }
        return out
    }
}

// MARK: - Hand model

public enum ArcSide: String, Codable, Hashable, Sendable {
    case left, right
    /// Which way is the middle of the screen: +1 for the left hand, -1 for the right.
    var inboard: CGFloat { self == .right ? -1 : 1 }
}

/// A thumb's reach as laid out, in view points. Angles are measured from straight up
/// toward the middle of the screen, so both hands use the same numbers mirrored.
public struct ArcHand: Equatable, Sendable {
    public var side: ArcSide
    public var pivot: CGPoint
    public var radius: CGFloat
    /// Radial spread of the sweep (standard deviation), the width of the comfortable band.
    public var spread: CGFloat
    /// Angle the thumb rests at: the middle of its sweep.
    public var rest: CGFloat
    public var lo: CGFloat
    public var hi: CGFloat
    public var calibrated: Bool

    public func point(r: CGFloat, phi: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + side.inboard * r * sin(phi), y: pivot.y - r * cos(phi))
    }

    public func polar(_ p: CGPoint) -> (r: CGFloat, phi: CGFloat) {
        let dx = (p.x - pivot.x) * side.inboard
        let dy = pivot.y - p.y
        return ((dx * dx + dy * dy).squareRoot(), atan2(dx, dy))
    }
}

/// One hand's calibration, stored as fractions of the screen so it survives window
/// changes: pivot as a fraction of width and height, lengths as fractions of the short side.
public struct ArcHandFit: Codable, Equatable, Sendable {
    public var pivotX, pivotY: Double
    public var radius, spread: Double
    public var rest, lo, hi: Double

    var isSane: Bool {
        [pivotX, pivotY, radius, spread, rest, lo, hi].allSatisfy { $0.isFinite }
            && radius > 0.05 && radius < 3 && spread >= 0 && spread < 1
            && abs(pivotX) < 4 && abs(pivotY) < 4 && lo <= hi
    }
}

/// A fine-tune offset for one control group: an angle along the arc and a radial move, the
/// latter as a fraction of the screen's short side.
public struct ArcTweak: Codable, Equatable, Sendable {
    public var dphi: Double
    public var dr: Double

    public init(dphi: Double, dr: Double) {
        self.dphi = dphi
        self.dr = dr
    }

    var isSane: Bool { dphi.isFinite && dr.isFinite && abs(dphi) <= 1.2 && abs(dr) <= 0.4 }
}

/// Everything saved for one orientation. A hand that was never fitted keeps its default.
public struct ArcProfile: Codable, Equatable, Sendable {
    public var left: ArcHandFit?
    public var right: ArcHandFit?
    /// Fine-tune offsets by control group ("arc", "stick", "s0", "s1", "sys", "home").
    public var leftTweaks: [String: ArcTweak]?
    public var rightTweaks: [String: ArcTweak]?
    /// Positions are locked: nothing can move or be recalibrated.
    public var locked: Bool?

    public init(left: ArcHandFit? = nil, right: ArcHandFit? = nil) {
        self.left = left
        self.right = right
    }

    var isSane: Bool {
        (left?.isSane ?? true) && (right?.isSane ?? true)
            && (leftTweaks?.values.allSatisfy(\.isSane) ?? true) && (rightTweaks?.values.allSatisfy(\.isSane) ?? true)
    }
}

public extension TargetDevice {
    /// The phones and iPads the Arc checks cover, turned upright.
    static var portraitVariants: [TargetDevice] {
        let names = ["iPhone SE", "iPhone 16 Pro Max", "iPad mini", "iPad Pro 13"]
        return all.filter { names.contains($0.name) }.map { d in
            let phone = min(d.size.width, d.size.height) < 600
            let notch = d.insets.left > 0
            let insets = phone ? (notch ? Insets(top: 59, bottom: 34) : Insets(top: 20)) : Insets(top: 24, bottom: 20)
            return TargetDevice(name: d.name + " portrait",
                                size: CGSize(width: d.size.height, height: d.size.width), insets: insets)
        }
    }
}

extension ArcSide {
    /// +1 / -1 along x toward the middle of the screen, for building sweeps in tests.
    public var inboardSign: CGFloat { inboard }
}
