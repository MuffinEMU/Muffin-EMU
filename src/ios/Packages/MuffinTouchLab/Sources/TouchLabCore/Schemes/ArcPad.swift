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

    /// Arc's own settings (mirror for left-handed play, quiet mode over video, idle fade,
    /// snap guides). Changing `swapHands` re-lays the pad out.
    public var options = ArcOptions() {
        didSet {
            guard options != oldValue else { return }
            if options.swapHands != oldValue.swapHands { tuneTracks.removeAll(); relayout() }
            lastActivity = nil
            idleFactor = 1
            onOptions?(options)
            notify()
        }
    }
    /// Called with the new options after a change that should be saved.
    public var onOptions: ((ArcOptions) -> Void)?
    /// Draw the calibration prompt and notes on the pad itself. `ArcCalibrationView` turns
    /// this off because its card shows them; the previews and bare hosts keep it on.
    public var drawsPrompts = true
    /// Seconds on the same clock as touch timestamps. Replaceable so checks can drive time.
    public var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    /// Pins the animation phase (the guide's travelling dot), for previews. nil = the clock.
    public var animationTime: Double?

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
            chipUntil = clock() + Self.chipSeconds
        }
        save()
        notify()
    }

    /// "Locked" or "Unlocked", for a settings row or a badge of the host's own.
    public var statusText: String { isLocked ? "Locked" : "Unlocked" }

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
        if profiles[orientation] != nil { pushUndo() }
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

    /// "Left thumb, 1 of 2" style progress for the card; nil outside calibration.
    public var calibrationStep: String? {
        switch calibrator?.phase {
        case .left?: return "Left thumb, 1 of 2"
        case .right?: return "Right thumb, 2 of 2"
        case .review?: return "Review"
        case nil: return nil
        }
    }

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

    /// What was wrong with a sweep, in words a player can act on. Every one ends the same way.
    static func message(for issue: SweepIssue) -> String {
        switch issue {
        case .tooShort: return "That sweep was too short. Try a longer, smoother sweep."
        case .wobbly: return "That sweep was a little wobbly. Try a longer, smoother sweep."
        case .notAnArc: return "That didn't curve like a thumb sweep. Try a longer, smoother sweep, low in the corner and up toward the middle."
        }
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
        cal.live = nil
        if cal.phase == .review { cal.preview = reviewPreview(cal.fits) }
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
        pushUndo()
        chipUntil = clock() + Self.chipSeconds
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

    public enum SweepIssue: Equatable, Sendable { case tooShort, wobbly, notAnArc }

    /// How a sweep scored: the fit it would save (nil when unusable), what was wrong with it,
    /// and the raw circle for drawing the live preview.
    struct SweepAssessment {
        var fit: ArcHandFit?
        var issue: SweepIssue?
        var circle: CircleFit?
        /// Angular span of the sweep (95th minus 5th percentile), in radians.
        var span: CGFloat = 0
    }

    /// A sweep shorter than this many buttons of path is a tap or a twitch.
    static let minimumSweepLength: CGFloat = 2.5
    /// Radial scatter beyond this fraction of the radius is a wobble, not a thumb.
    static let maximumWobble: CGFloat = 0.10

    /// Scores a sweep. Used live (every few samples, to draw the fitted arc under the thumb)
    /// and when the thumb lifts (to accept or ask again).
    static func assess(side: ArcSide, samples: [CGPoint], ctx: LayoutContext) -> SweepAssessment {
        let u = ctx.unit
        let size = ctx.size
        var a = SweepAssessment()
        guard size.width > 0, size.height > 0, samples.count >= 12 else { a.issue = .tooShort; return a }
        var length: CGFloat = 0
        for (p, q) in zip(samples, samples.dropFirst()) { length += p.distance(to: q) }
        guard length >= minimumSweepLength * u else { a.issue = .tooShort; return a }
        guard let fit = ArcMath.fitCircle(samples) else { a.issue = .notAnArc; return a }
        a.circle = fit
        guard fit.radius >= 3 * u, fit.radius <= 16 * u else { a.issue = .notAnArc; return a }
        guard fit.center.x > -size.width, fit.center.x < 2 * size.width,
              fit.center.y > -size.height, fit.center.y < 2 * size.height else { a.issue = .notAnArc; return a }
        let probe = ArcHand(side: side, pivot: fit.center, radius: fit.radius, spread: fit.rms,
                            rest: 0, lo: 0, hi: 0, calibrated: true)
        let phis = samples.map { probe.polar($0).phi }
        let med = ArcMath.quantile(phis, 0.5)
        // The sweep has to be above the pivot and run toward the middle of the screen.
        guard med > 0.05, med < 1.6 else { a.issue = .notAnArc; return a }
        let lo = ArcMath.quantile(phis, 0.05), hi = ArcMath.quantile(phis, 0.95)
        a.span = hi - lo
        guard hi - lo >= 0.35 else { a.issue = .tooShort; return a }
        // Wobbly: scattered off the circle, or going back and forth along it. The angle is
        // smoothed first so ordinary finger noise doesn't count as going back.
        if fit.rms / fit.radius > maximumWobble { a.issue = .wobbly; return a }
        let window = 7
        if phis.count > 2 * window {
            var smooth: [CGFloat] = []
            for i in 0...(phis.count - window) { smooth.append(phis[i..<(i + window)].reduce(0, +) / CGFloat(window)) }
            var travel: CGFloat = 0
            for (p, q) in zip(smooth, smooth.dropFirst()) { travel += abs(q - p) }
            let net = abs(smooth[smooth.count - 1] - smooth[0])
            if travel > 1.7 * net + 0.15 { a.issue = .wobbly; return a }
        }
        let short = min(size.width, size.height)
        a.fit = ArcHandFit(pivotX: Double(fit.center.x / size.width), pivotY: Double(fit.center.y / size.height),
                           radius: Double(fit.radius / short), spread: Double(fit.rms / short),
                           rest: Double(med), lo: Double(lo), hi: Double(hi))
        return a
    }

    /// Turns raw sweep samples into a stored hand, or nil when they do not describe a
    /// thumb arc (too few, too short, nearly straight, wobbly, pivot nowhere near the screen).
    static func makeFit(side: ArcSide, samples: [CGPoint], ctx: LayoutContext) -> ArcHandFit? {
        assess(side: side, samples: samples, ctx: ctx).fit
    }

    /// The finished layout the sweeps would give, drawn at full strength for the review.
    private func reviewPreview(_ fits: [ArcSide: ArcHandFit]) -> [RenderElement] {
        var p = profiles[orientation] ?? ArcProfile()
        for (side, fit) in fits {
            if side == .left { p.left = fit; p.leftTweaks = nil } else { p.right = fit; p.rightTweaks = nil }
        }
        p.locked = true
        let tmp = ArcPad(profiles: [orientation: p])
        tmp.options = options
        tmp.showsChrome = false
        tmp.layout(context)
        return tmp.render(pressed: [], sticks: [:])
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
        /// The control's tweak when the finger landed, and how far the finger has really
        /// moved since (before snapping), so a snap never eats the drag.
        var start: ArcTweak
        var raw = (dphi: CGFloat(0), dr: CGFloat(0))
        var snapPhi: CGFloat?
        var snapR: CGFloat?
    }

    private struct Calibrator {
        var phase: CalibrationPhase = .left
        var samples: [ArcSide: [CGPoint]] = [:]
        var fits: [ArcSide: ArcHandFit] = [:]
        var active: TouchID?
        var note: String?
        /// The fit under the thumb right now, redrawn as it moves.
        var live: SweepAssessment?
        var sinceLive = 0
        /// The finished layout, once both sweeps are in (the review).
        var preview: [RenderElement] = []
        var side: ArcSide { phase == .right ? .right : .left }
    }

    /// One fine-tune or calibration state to go back to.
    private struct UndoEntry: Equatable {
        var left, right: ArcHandFit?
        var leftTweaks, rightTweaks: [String: ArcTweak]?
    }

    private var arcSets: [ArcSet] = []
    private var arcTracks: [TouchID: ArcTrack] = [:]
    private var tuneTracks: [TouchID: TuneTrack] = [:]
    private var tuning = false
    /// The arc band, as polylines along each hand's arc (gaps where it would cross the video).
    private var bands: [(set: Int, side: ArcSide, points: [[CGPoint]])] = []
    private var calibrator: Calibrator?

    // Undo, per orientation. A fine-tune drag, an accepted calibration and a reset each push one.
    private var undoStacks: [String: [UndoEntry]] = [:]
    private var pendingUndo: UndoEntry?
    private static let undoLimit = 30
    private var snapPending = false

    // Quiet mode and idle fade.
    private var glow: [ArcSide: CGFloat] = [.left: 0, .right: 0]
    private var fingerSides: [TouchID: ArcSide] = [:]
    private var lastActivity: Double?
    private var idleFactor: CGFloat = 1
    private var lastTick: Double?
    private var chipUntil: Double?
    static let chipSeconds: Double = 3
    /// Resting opacity of the controls in quiet mode, and the floor when idle-faded.
    static let quietRest: CGFloat = 0.62
    static let idleFloor: CGFloat = 0.12
    /// Off for the throwaway layout drawn in the calibration review.
    var showsChrome = true

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
        // `right` is the logical cluster (A/B/X/Y, right stick, plus) wherever it sits:
        // swapped hands put it on the left edge. All geometry stays with the physical side.
        let right = options.swapHands ? h0.side == .left : h0.side == .right
        var h = h0
        h.faces = right
        h.radius = h0.radius + tweak("arc").dr
        let R = h.radius
        guard R > u else { return nil }
        let restArc = rest + tweak("arc").dphi
        let minDelta = 1.28 * u / R, maxDelta = 1.9 * u / R
        let delta = tight ? minDelta : h.calibrated ? ArcMath.clamp((h.hi - h.lo) / 3.6, minDelta, maxDelta) : 1.4 * u / R
        // The arc reads from the top end down: A, B, X, Y on the right; Up, Down, Left, Right on the left.
        let buttons: [PadButton] = right ? [.a, .b, .x, .y] : [.up, .down, .left, .right]
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
        bands = []
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
            bands = makeBands(p.sets, room: room)
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

    private func makeBands(_ sets: [ArcSet], room: Room) -> [(set: Int, side: ArcSide, points: [[CGPoint]])] {
        var out: [(set: Int, side: ArcSide, points: [[CGPoint]])] = []
        for (si, set) in sets.enumerated() {
            let h = set.hand
            let dphi = 0.25 * room.u / h.radius
            var phi = set.phis[0] - 1.0 * set.delta
            let end = set.phis[3] + 1.0 * set.delta
            var segments: [[CGPoint]] = []
            var cur: [CGPoint] = []
            while phi <= end + 1e-6 {
                let p = h.point(r: h.radius, phi: phi)
                if room.safe.contains(p), room.soft || !room.keep.contains(where: { $0.contains(p) }) {
                    cur.append(p)
                } else {
                    if cur.count > 1 { segments.append(cur) }
                    cur = []
                }
                phi += dphi
            }
            if cur.count > 1 { segments.append(cur) }
            out.append((set: si, side: h.side, points: segments))
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
                       rest: .pi / 4, lo: 0.2, hi: 1.2, calibrated: false, faces: side == .right)
    }

    // MARK: Input

    override public func claims(_ point: CGPoint) -> Bool {
        if calibrator != nil { return true }
        if tuning { return tuningPill(at: point) != nil || tuneTarget(at: point) != nil }
        return arcHit(at: point, expand: 0) != nil || super.claims(point)
    }

    /// Remembers which half of the screen a finger is on and when it last did anything, for
    /// quiet mode and the idle fade.
    private func touched(_ touch: TouchID, at point: CGPoint, time: Double) {
        fingerSides[touch] = point.x < context.size.width / 2 ? .left : .right
        if time > 0 { lastActivity = time }
    }

    override public func began(_ touch: TouchID, at point: CGPoint, time: Double) -> Contribution? {
        touched(touch, at: point, time: time)
        if var cal = calibrator {
            if cal.phase != .review, cal.active == nil {
                cal.active = touch
                cal.samples[cal.side] = [point]
                cal.note = nil
                cal.live = nil
                cal.sinceLive = 0
                calibrator = cal
                notify()
            }
            return Contribution.none
        }
        if tuning {
            if let pill = tuningPill(at: point) {
                switch pill.action {
                case .undo: undoLastChange()
                case .done: setFineTuning(false)
                }
                return Contribution.none
            }
            guard let (side, key) = tuneTarget(at: point) else { return nil }
            if tuneTracks.isEmpty { pendingUndo = snapshot() }
            var t = TuneTrack(side: side, key: key, last: point, start: currentTweak(side, key))
            // A control already at a snap position starts snapped, without a tick.
            let targets = snapTargets(side: side, key: key)
            t.snapPhi = targets.phi.first { abs($0 - CGFloat(t.start.dphi)) < 1e-6 }
            t.snapR = targets.r.first { abs($0 - CGFloat(t.start.dr)) < 1e-6 }
            tuneTracks[touch] = t
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
        touched(touch, at: point, time: time)
        if var cal = calibrator {
            if cal.active == touch {
                let side = cal.side
                let last = cal.samples[side]?.last
                if last == nil || last!.distance(to: point) >= 2 {
                    cal.samples[side, default: []].append(point)
                    cal.sinceLive += 1
                    if cal.sinceLive >= 3, let pts = cal.samples[side], pts.count >= 12 {
                        cal.sinceLive = 0
                        // Long sweeps are thinned so the live fit stays cheap.
                        let stride = max(1, pts.count / 240)
                        let used = stride == 1 ? pts : pts.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
                        cal.live = Self.assess(side: side, samples: used, ctx: context)
                    }
                    calibrator = cal
                }
            }
            return Contribution.none
        }
        if tuning {
            guard var t = tuneTracks[touch], let hand = hands.first(where: { $0.side == t.side }) else { return .none }
            let a = hand.polar(t.last), b = hand.polar(point)
            t.raw.dphi += b.phi - a.phi
            t.raw.dr += b.r - a.r
            applyDrag(&t)
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
        fingerSides.removeValue(forKey: touch)
        if time > 0 { lastActivity = time }
        if var cal = calibrator {
            guard cal.active == touch else { return }
            cal.active = nil
            cal.live = nil
            let side = cal.side
            if !point.x.isNaN {
                let result = Self.assess(side: side, samples: cal.samples[side] ?? [], ctx: context)
                if let fit = result.fit {
                    cal.fits[side] = fit
                    cal.phase = cal.phase == .left ? .right : .review
                    cal.note = nil
                    if cal.phase == .review { cal.preview = reviewPreview(cal.fits) }
                } else {
                    cal.samples[side] = []
                    cal.note = Self.message(for: result.issue ?? .tooShort)
                }
            } else {
                cal.samples[side] = []
            }
            calibrator = cal
            notify()
            return
        }
        if tuneTracks.removeValue(forKey: touch) != nil {
            if tuneTracks.isEmpty {
                if !point.x.isNaN { save() }
                if let before = pendingUndo {
                    if before != snapshot() { pushUndo(before) }
                    pendingUndo = nil
                }
                notify()
            }
            return
        }
        if arcTracks.removeValue(forKey: touch) != nil { return }
        super.ended(touch, at: point, time: time)
    }

    // MARK: Fine-tune

    /// The side a layout's logical side lands on: mirrored when hands are swapped.
    private func physical(_ logical: ArcSide) -> ArcSide {
        guard options.swapHands else { return logical }
        return logical == .left ? .right : .left
    }

    /// Which hand and fine-tune group a control belongs to, or nil for a control that can't be moved.
    private func tuneKey(of c: PadControl) -> (ArcSide, String)? {
        switch c.kind {
        case .stick(let s, _, _): return (physical(s == .left ? .left : .right), "stick")
        case .button(let b):
            switch b {
            case .zl: return (physical(.left), "s0")
            case .l: return (physical(.left), "s1")
            case .zr: return (physical(.right), "s0")
            case .r: return (physical(.right), "s1")
            case .minus: return (physical(.left), "sys")
            case .plus: return (physical(.right), "sys")
            case .home: return (physical(.left), "home")
            default: return (physical(c.group == Self.leftPadGroup ? .left : .right), "arc")
            }
        default: return nil
        }
    }

    private func tuneTarget(at p: CGPoint) -> (ArcSide, String)? {
        if let hit = arcHit(at: p, expand: 0.5 * layoutUnit) { return (arcSets[hit.set].hand.side, "arc") }
        guard let i = resolve(p) else { return nil }
        return tuneKey(of: controls[i])
    }

    private func currentTweak(_ side: ArcSide, _ key: String) -> ArcTweak {
        let p = profiles[orientation]
        return ((side == .left ? p?.leftTweaks : p?.rightTweaks) ?? [:])[key] ?? ArcTweak(dphi: 0, dr: 0)
    }

    private func setTweak(_ side: ArcSide, _ key: String, _ t: ArcTweak) {
        var p = profiles[orientation] ?? ArcProfile()
        var tw = (side == .left ? p.leftTweaks : p.rightTweaks) ?? [:]
        tw[key] = t
        if side == .left { p.leftTweaks = tw } else { p.rightTweaks = tw }
        profiles[orientation] = p
    }

    /// Where a dragged control settles: its default (0), and the positions that make the
    /// spacing along the outer ring equal, or line the stick up with the arc. Values are
    /// tweak values (radians along the arc, fraction of the short side in and out).
    private func snapTargets(side: ArcSide, key: String) -> (phi: [CGFloat], r: [CGFloat]) {
        let p = profiles[orientation]
        let tw = (side == .left ? p?.leftTweaks : p?.rightTweaks) ?? [:]
        func d(_ k: String) -> CGFloat { CGFloat(tw[k]?.dphi ?? 0) }
        func rr(_ k: String) -> CGFloat { CGFloat(tw[k]?.dr ?? 0) }
        var phi: [CGFloat] = [0], r: [CGFloat] = [0]
        let faces = hands.first { $0.side == side }?.faces ?? (side == .right)
        let outer = faces ? ["s0", "s1", "sys"] : ["s0", "s1", "sys", "home"]
        if let i = outer.firstIndex(of: key) {
            if i > 0, i < outer.count - 1 {
                phi.append((d(outer[i - 1]) + d(outer[i + 1])) / 2)
            } else if i == 0 {
                phi.append(2 * d(outer[1]) - d(outer[2]))
            } else {
                phi.append(2 * d(outer[i - 1]) - d(outer[i - 2]))
            }
            r += outer.filter { $0 != key }.map(rr)
        } else if key == "stick" {
            phi.append(d("arc"))
        } else if key == "arc" {
            phi.append(d("stick"))
        }
        func unique(_ v: [CGFloat]) -> [CGFloat] {
            var out: [CGFloat] = []
            for x in v where !out.contains(where: { abs($0 - x) < 1e-6 }) { out.append(x) }
            return out
        }
        return (unique(phi), unique(r))
    }

    static let snapAngle: CGFloat = 0.035
    static let snapRadiusUnits: CGFloat = 0.16

    private func applyDrag(_ t: inout TuneTrack) {
        let short = min(context.size.width, context.size.height)
        guard short > 0 else { return }
        var dphi = ArcMath.clamp(CGFloat(t.start.dphi) + t.raw.dphi, -1.2, 1.2)
        var dr = ArcMath.clamp(CGFloat(t.start.dr) + t.raw.dr / short, -0.4, 0.4)
        if options.snapGuides {
            let targets = snapTargets(side: t.side, key: t.key)
            func settle(_ v: CGFloat, _ list: [CGFloat], _ threshold: CGFloat, _ engaged: CGFloat?) -> CGFloat? {
                // Sticky: once on a target, it takes a clearly bigger pull to leave.
                if let e = engaged, abs(v - e) < threshold * 1.7 { return e }
                return list.filter { abs($0 - v) < threshold }.min { abs($0 - v) < abs($1 - v) }
            }
            let phi = settle(dphi, targets.phi, Self.snapAngle, t.snapPhi)
            let rad = settle(dr, targets.r, Self.snapRadiusUnits * layoutUnit / short, t.snapR)
            if let p = phi, p != t.snapPhi { snapPending = true }
            if let r = rad, r != t.snapR { snapPending = true }
            t.snapPhi = phi
            t.snapR = rad
            if let p = phi { dphi = p }
            if let r = rad { dr = r }
        }
        setTweak(t.side, t.key, ArcTweak(dphi: Double(dphi), dr: Double(dr)))
    }

    /// True once after a drag newly settled on a snap position; the host plays a haptic tick.
    public func takeSnapTick() -> Bool {
        defer { snapPending = false }
        return snapPending
    }

    // MARK: Undo

    private func snapshot() -> UndoEntry {
        let p = profiles[orientation]
        return UndoEntry(left: p?.left, right: p?.right, leftTweaks: p?.leftTweaks, rightTweaks: p?.rightTweaks)
    }

    private func pushUndo(_ entry: UndoEntry? = nil) {
        var stack = undoStacks[orientation] ?? []
        stack.append(entry ?? snapshot())
        if stack.count > Self.undoLimit { stack.removeFirst(stack.count - Self.undoLimit) }
        undoStacks[orientation] = stack
    }

    /// Something to undo here, and positions are not locked.
    public var canUndo: Bool { !isLocked && !(undoStacks[orientation]?.isEmpty ?? true) }

    /// Puts back the state before the last fine-tune drag, accepted calibration or reset in
    /// this orientation. Refused (false) while locked or with nothing to undo.
    @discardableResult
    public func undoLastChange() -> Bool {
        guard !isLocked, var stack = undoStacks[orientation], let entry = stack.popLast() else { return false }
        undoStacks[orientation] = stack
        var p = profiles[orientation] ?? ArcProfile()
        p.left = entry.left
        p.right = entry.right
        p.leftTweaks = entry.leftTweaks
        p.rightTweaks = entry.rightTweaks
        let empty = p.left == nil && p.right == nil && p.leftTweaks == nil && p.rightTweaks == nil && p.locked == nil
        profiles[orientation] = empty ? nil : p
        tuneTracks.removeAll()
        save()
        relayout()
        notify()
        return true
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

    /// Over the video with quiet mode on: thinner arc, controls resting dim.
    private var quiet: Bool { options.quietOverVideo && context.showcaseStyle && (avoidance == .none || usingFallback) }

    private var fadesAtRest: Bool { calibrator == nil && !tuning }

    private func restFade(_ side: ArcSide) -> CGFloat {
        guard fadesAtRest else { return 1 }
        var f: CGFloat = 1
        if quiet { f = Self.quietRest + (1 - Self.quietRest) * (glow[side] ?? 0) }
        return f * idleFactor
    }

    private func screenSide(_ p: CGPoint) -> ArcSide { p.x < context.size.width / 2 ? .left : .right }

    /// Arc's look for a list of the generic controls' elements: pill shoulders, hairline
    /// outline, shadow and sinking press (`RenderElement.Style.refined`).
    private func styled(_ list: [RenderElement], fadeAll: CGFloat? = nil) -> [RenderElement] {
        list.map { e in
            var e = e
            // "Showcase style" off keeps the flat look the controls had before it.
            if context.showcaseStyle {
                e.style = .refined
                if e.role == .shoulder, case .roundedRect(let r, _) = e.shape {
                    e.shape = .roundedRect(r, cornerRadius: min(r.width, r.height) / 2)
                }
            }
            e.fade = fadeAll ?? restFade(screenSide(e.shape.center))
            return e
        }
    }

    private struct Banner {
        var elements: [RenderElement] = []
        var bottom: CGFloat
    }

    /// Greedy word wrap for a pill about `width` wide at `font` points.
    static func wrap(_ text: String, width: CGFloat, font: CGFloat) -> [String] {
        let perLine = max(Int((width - 2 * font) / (font * 0.56)), 10)
        var lines: [String] = []
        var cur = ""
        for w in text.split(separator: " ") {
            if cur.isEmpty { cur = String(w) } else if cur.count + 1 + w.count <= perLine { cur += " " + w } else {
                lines.append(cur)
                cur = String(w)
            }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    private var pillHeight: CGFloat { max(0.62 * context.unit, 28) }

    /// A message as one or more centred pills under `top`, wrapped to fit the screen.
    private func banner(_ text: String, top: CGFloat, tone: RenderElement.Tone = .neutral, fade: CGFloat = 1) -> Banner {
        let u = context.unit
        let h = pillHeight
        let font = RefinedLook.labelSize(for: CGRect(x: 0, y: 0, width: 1, height: h))
        let maxW = min(context.safeBounds.width - 0.8 * u, 14 * u)
        var out = Banner(bottom: top)
        for line in Self.wrap(text, width: maxW, font: font) {
            let w = min(maxW, CGFloat(line.count) * font * 0.56 + 2 * font)
            let rect = CGRect(x: context.size.width / 2 - w / 2, y: out.bottom, width: w, height: h)
            out.elements.append(RenderElement(shape: .roundedRect(rect, cornerRadius: h / 2), role: .system, label: line,
                                              style: .refined, tone: tone, fade: fade))
            out.bottom += h + 0.12 * u
        }
        return out
    }

    private enum PillAction { case undo, done }

    private struct Pill {
        var action: PillAction
        var rect: CGRect
        var label: String
    }

    private var tuningHint: String {
        options.snapGuides ? "Drag a control along its arc, or in and out. It snaps to even spacing."
                           : "Drag a control along its arc, or in and out."
    }

    /// The fine-tune banner and its Undo and Done pills. The hit test and the drawing both
    /// come from here, so they can't drift apart.
    private func tuningChrome() -> (hint: Banner, pills: [Pill]) {
        let u = context.unit
        let hint = banner(tuningHint, top: context.safeBounds.minY + 0.35 * u, tone: .accent)
        let h = max(0.7 * u, 32), w = max(2.2 * u, 84)
        let y = hint.bottom + 0.08 * u
        let mid = context.size.width / 2
        let gap = 0.2 * u
        return (hint, [
            Pill(action: .undo, rect: CGRect(x: mid - gap / 2 - w, y: y, width: w, height: h), label: "Undo"),
            Pill(action: .done, rect: CGRect(x: mid + gap / 2, y: y, width: w, height: h), label: "Done"),
        ])
    }

    private func tuningPill(at p: CGPoint) -> Pill? {
        let slop = 0.2 * context.unit
        return tuningChrome().pills.first { $0.rect.insetBy(dx: -slop, dy: -slop).contains(p) }
    }

    override public func render(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> [RenderElement] {
        if let cal = calibrator { return renderCalibration(cal) }
        var out = bandElements()
        out += styled(super.render(pressed: tuning ? [] : pressed, sticks: sticks))
        if tuning { out += tuningOverlay() } else if showsChrome { out += lockBadge() }
        return out
    }

    // MARK: Band

    private func bandElements() -> [RenderElement] {
        guard !usingFallback else { return [] }
        let u = layoutUnit
        var out: [RenderElement] = []
        let quietNow = quiet
        for band in bands {
            let held = arcTracks.values.contains { $0.set == band.set }
            let f = restFade(band.side)
            for seg in band.points where seg.count > 1 {
                let origin = RenderShape.point(seg[0])
                if !quietNow {
                    // The track the thumb rides: wide and faint.
                    out.append(RenderElement(shape: origin, role: .guide, ghost: true, style: .refined,
                                             fade: min(1, (held ? 0.8 : 0.4) * f), path: seg, width: 0.95 * u))
                }
                out.append(RenderElement(shape: origin, role: .guide, lit: held, style: .refined,
                                         fade: (quietNow ? 0.6 : 0.8) * f, path: seg, width: quietNow ? 1.0 : 1.6))
            }
        }
        return out
    }

    private func lockBadge() -> [RenderElement] {
        guard isLocked else { return [] }
        let now = animationTime ?? clock()
        let timed = chipUntil.map { now < $0 } ?? false
        guard timed || (options.lockBadge && context.showcaseStyle && !quiet) else { return [] }
        let f: CGFloat = timed ? CGFloat(min(1, max(0, (chipUntil! - now) / 0.6))) : 0.65
        let h = max(0.55 * context.unit, 26), w = max(2.6 * context.unit, 92)
        let rect = CGRect(x: context.size.width / 2 - w / 2, y: context.safeBounds.minY + 4, width: w, height: h)
        return [RenderElement(shape: .roundedRect(rect, cornerRadius: h / 2), role: .system, label: statusText,
                              style: .refined, tone: .good, fade: f * idleFactor)]
    }

    // MARK: Fine-tune overlay

    private func tuningOverlay() -> [RenderElement] {
        var out: [RenderElement] = []
        let chrome = tuningChrome()
        out += chrome.hint.elements
        for pill in chrome.pills {
            let dim = pill.action == .undo && !canUndo
            out.append(RenderElement(shape: .roundedRect(pill.rect, cornerRadius: pill.rect.height / 2), role: .system,
                                     label: pill.label, style: .refined, tone: dim ? .neutral : .accent, fade: dim ? 0.45 : 1))
        }
        let dragging = Set(tuneTracks.values.map { "\($0.side.rawValue)/\($0.key)" })
        // A ring around everything that can be moved; the group being dragged lights up.
        for c in controls where !c.isZone {
            guard let (side, key) = tuneKey(of: c) else { continue }
            let box = c.shape.boundingBox
            let shape: PadShape
            switch c.shape {
            case .circle(let ctr, let r):
                // A stick's ring goes round the whole base.
                if case .stick(_, let travel, _) = c.kind { shape = .circle(center: ctr, radius: travel + knobRadius + 4) }
                else { shape = .circle(center: ctr, radius: r + 4) }
            case .roundedRect(let r, _):
                let big = r.insetBy(dx: -4, dy: -4)
                shape = .roundedRect(big, cornerRadius: min(big.width, big.height) / 2)
            }
            _ = box
            out.append(RenderElement(shape: shape, role: .handle, lit: dragging.contains("\(side.rawValue)/\(key)"), style: .refined))
        }
        out += snapGuideElements()
        return out
    }

    /// Ticks across the arc at each position the dragged control would snap to; the one it
    /// is settled on turns green.
    private func snapGuideElements() -> [RenderElement] {
        guard options.snapGuides else { return [] }
        let u = layoutUnit
        let short = min(context.size.width, context.size.height)
        var out: [RenderElement] = []
        for t in tuneTracks.values {
            guard let hand = hands.first(where: { $0.side == t.side }) else { continue }
            let centre: CGPoint?
            if t.key == "arc" {
                centre = arcSets.first(where: { $0.hand.side == t.side }).map { set in
                    hand.point(r: set.hand.radius, phi: (set.phis[0] + set.phis[3]) / 2)
                }
            } else {
                centre = controls.first(where: { tuneKey(of: $0).map { $0.0 == t.side && $0.1 == t.key } ?? false })?.shape.center
            }
            guard let c = centre else { continue }
            let (r0, phi0) = hand.polar(c)
            let now = currentTweak(t.side, t.key)
            let targets = snapTargets(side: t.side, key: t.key)
            for target in targets.phi {
                let phi = phi0 + (target - CGFloat(now.dphi))
                let on = t.snapPhi.map { abs($0 - target) < 1e-6 } ?? false
                let pts = [hand.point(r: r0 - 0.75 * u, phi: phi), hand.point(r: r0 + 0.75 * u, phi: phi)]
                out.append(RenderElement(shape: RenderShape.point(pts[0]), role: .guide, lit: on, ghost: !on, style: .refined,
                                         tone: on ? .good : .accent, fade: 1, path: pts, width: on ? 3 : 1.5))
            }
            for target in targets.r {
                let r = r0 + (target - CGFloat(now.dr)) * short
                let on = t.snapR.map { abs($0 - target) < 1e-6 } ?? false
                let half = 0.3 * u / max(r, 1)
                let pts = (0...6).map { hand.point(r: r, phi: phi0 - half + 2 * half * CGFloat($0) / 6) }
                out.append(RenderElement(shape: RenderShape.point(pts[0]), role: .guide, lit: on, ghost: !on, style: .refined,
                                         tone: on ? .good : .accent, fade: 1, path: pts, width: on ? 3 : 1.5))
            }
        }
        return out
    }

    // MARK: Calibration drawing

    /// Points along `hand`'s arc between two angles, a few per button.
    private func arcPoints(_ hand: ArcHand, from lo: CGFloat, to hi: CGFloat, radius: CGFloat? = nil) -> [CGPoint] {
        let r = radius ?? hand.radius
        guard r > 1, hi > lo else { return [] }
        let step = max(0.25 * context.unit / r, 0.01)
        var out: [CGPoint] = []
        var phi = lo
        while phi < hi { out.append(hand.point(r: r, phi: phi)); phi += step }
        out.append(hand.point(r: r, phi: hi))
        return out
    }

    private func renderCalibration(_ cal: Calibrator) -> [RenderElement] {
        var out: [RenderElement] = []
        let u = context.unit
        if cal.phase == .review {
            // The finished layout, as it will play.
            out += cal.preview
        } else {
            // Controls fade back; the sweep draws itself under the thumbs.
            out += styled(super.render(pressed: [], sticks: [:]), fadeAll: 0.22)
        }
        if drawsPrompts {
            var y = context.safeBounds.minY + 0.35 * u
            let prompt = banner(calibrationPrompt, top: y, tone: .accent)
            out += prompt.elements
            y = prompt.bottom
            if let note = cal.note {
                out += banner(note, top: y, tone: .warn).elements
            }
        }
        guard cal.phase != .review else { return out }

        // Hands already accepted stay drawn on their fitted arc.
        for (side, fit) in cal.fits {
            let h = Self.hand(side, fit: fit, context)
            let pts = arcPoints(h, from: h.lo, to: h.hi)
            out.append(RenderElement(shape: RenderShape.point(pts.first ?? .zero), role: .guide, style: .refined, tone: .good,
                                     fade: 0.8, path: pts, width: 4))
        }

        let side = cal.side
        if cal.active == nil {
            out += sweepDemo(side: side)
        }
        // The fitted arc under the thumb, redrawn as it moves: green while it would be
        // accepted, amber while it wouldn't.
        if let live = cal.live, let c = live.circle, cal.active != nil, let samples = cal.samples[side] {
            let probe = ArcHand(side: side, pivot: c.center, radius: c.radius, spread: c.rms, rest: 0, lo: 0, hi: 0, calibrated: true)
            let phis = samples.map { probe.polar($0).phi }
            let lo = ArcMath.quantile(phis, 0.02), hi = ArcMath.quantile(phis, 0.98)
            let pts = arcPoints(probe, from: lo - 0.12, to: hi + 0.12)
            if pts.count > 1 {
                out.append(RenderElement(shape: RenderShape.point(pts[0]), role: .guide, lit: true, style: .refined,
                                         tone: live.issue == nil ? .good : .warn, fade: 1, path: pts, width: 7))
            }
        }
        for s in [ArcSide.left, .right] {
            guard let samples = cal.samples[s], samples.count > 1 else { continue }
            let stride = max(1, samples.count / 200)
            let pts = samples.enumerated().filter { $0.offset % stride == 0 || $0.offset == samples.count - 1 }.map(\.element)
            out.append(RenderElement(shape: RenderShape.point(pts[0]), role: .guide, lit: true, style: .refined,
                                     fade: 0.95, path: pts, width: 2.5))
        }
        return out
    }

    /// The animated example: a dot sweeps along the default arc for this thumb, leaving a
    /// short trail, then rests and fades before it goes again.
    private func sweepDemo(side: ArcSide) -> [RenderElement] {
        let h = Self.hand(side, fit: nil, context)
        let u = context.unit
        let track = arcPoints(h, from: h.lo, to: h.hi)
        guard track.count > 1 else { return [] }
        let now = animationTime ?? clock()
        let period = 2.8
        let t = now.truncatingRemainder(dividingBy: period) / period
        let move = min(t / 0.7, 1)
        let eased = move * move * (3 - 2 * move)
        let phi = h.lo + (h.hi - h.lo) * CGFloat(eased)
        let dotFade = t < 0.7 ? 1 : CGFloat(max(0, 1 - (t - 0.7) / 0.3))
        let trail = arcPoints(h, from: max(h.lo, phi - 0.28), to: phi)
        var out = [RenderElement(shape: RenderShape.point(track[0]), role: .guide, ghost: true, style: .refined, tone: .accent,
                                 fade: 1, path: track, width: 3, dash: 8)]
        if trail.count > 1 {
            out.append(RenderElement(shape: RenderShape.point(trail[0]), role: .guide, lit: true, style: .refined, tone: .accent,
                                     fade: dotFade, path: trail, width: 6))
        }
        out.append(RenderElement(shape: .circle(center: h.point(r: h.radius, phi: phi), radius: 0.42 * u), role: .handle,
                                 lit: true, style: .refined, fade: dotFade))
        return out
    }

    // MARK: Ticks

    override public var needsTicks: Bool {
        if super.needsTicks { return true }
        if let c = calibrator, c.phase != .review, c.active == nil { return true }
        if let until = chipUntil, (animationTime ?? clock()) < until + 0.05 { return true }
        if quiet, fadesAtRest {
            for side in [ArcSide.left, .right] {
                let target: CGFloat = fingerSides.values.contains(side) ? 1 : 0
                if abs((glow[side] ?? 0) - target) > 0.01 { return true }
            }
        }
        if options.validIdleFade != nil, !(idleFactor <= Self.idleFloor + 0.001 && fingerSides.isEmpty) { return true }
        return false
    }

    override public func tick(time: Double) -> [TouchID: Contribution] {
        let dt = CGFloat(min(max(time - (lastTick ?? time), 0), 0.1))
        lastTick = time
        for side in [ArcSide.left, .right] {
            let target: CGFloat = fingerSides.values.contains(side) ? 1 : 0
            let g = glow[side] ?? 0
            glow[side] = abs(target - g) < 0.01 ? target : g + (target - g) * min(1, dt * (target > g ? 14 : 3))
        }
        if let n = options.validIdleFade {
            if !fingerSides.isEmpty || lastActivity == nil { lastActivity = time }
            let idle = time - (lastActivity ?? time)
            let target: CGFloat = fingerSides.isEmpty && idle > n ? Self.idleFloor : 1
            idleFactor = abs(target - idleFactor) < 0.005 ? target
                : idleFactor + (target - idleFactor) * min(1, dt * (target < idleFactor ? 1.5 : 12))
        } else {
            idleFactor = 1
        }
        return super.tick(time: time)
    }
}

/// Shapes for elements that draw from a path, not a shape: a zero-size marker at the start.
enum RenderShape {
    static func point(_ p: CGPoint) -> PadShape { .circle(center: p, radius: 0) }
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
    /// This hand carries A/B/X/Y, the right stick and plus (false: the d-pad, left stick,
    /// minus and HOME). The right hand, unless the hands are swapped.
    public var faces: Bool = true

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
