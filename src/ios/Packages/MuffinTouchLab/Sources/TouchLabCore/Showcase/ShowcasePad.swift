import CoreGraphics
import Foundation

/// Scheme 5 - Showcase.
///
/// TouchLab's rendition of the showcase pad in MuffinEMU: the Wii U GamePad's own measured
/// layout, at the GamePad's real size, drawn clean. What is carried over, as pure Swift:
///
/// - `ShowcaseLayout` - the hardware geometry (clusters, stick arms, the +/- and HOME
///   slots) in face-button diameters, turned into points by the screen's points-per-inch, so
///   a button is 10.6 mm across wherever it fits and smaller only as far as it must.
/// - `ShowcaseFitter` / `ShowcaseLayoutPreset` - the cross-device transplant of the
///   "iPad Pro 12.9" and "Compact" layouts.
/// - `ShowcaseColourFile` / `ShowcaseColourPreset` - colour schemes, `.muffinclr` JSON.
///
/// What is not: `HeldControl` and SwiftUI hit testing. Input is `ControlScheme`'s, the same
/// engine as Zone - gap-free nearest catchment, sliding between buttons, two-button
/// chords, an eight-way d-pad, and sticks read through `StickMath` and `context.stick`, so
/// the shared stick settings reach it without any code here.
///
/// Settings are the showcase pad's three: layout preset, colour (preset or an imported
/// `.muffinclr`) and display mode.
///
/// - Native: the GamePad as the hardware has it. In landscape the clusters sit where they
///   do on the real controller and the picture goes in the gap between them
///   (`pictureRect`); upright, the picture goes along the top and the clusters take the
///   bottom corners. Nothing ever covers the picture. The host should place the video at
///   `pictureRect` - on a phone that is a small picture, the accepted cost of Native.
/// - Fit: the picture stays where the host put it (`LayoutContext.videoRects`) and the
///   pad is fitted around it, shrunk from life size as far as it must (never below
///   `minimumUnit`, 44 pt). When the resolver's rigid clusters cannot clear the picture,
///   `ShowcaseFitSolver` packs the blocks into the free space instead: each side sized on its
///   own, shoulders stacked or moved, the face diamond flattened. Where the margin is too thin for that - a full-screen picture on a
///   phone - it floats over the outer thirds of the picture instead, as the showcase's Fit
///   does, and `arrangement` says so. An iPhone held upright is always Native.
public final class ShowcasePad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "showcase",
        name: "Showcase",
        summary: "The GamePad at its real size and proportions, clean and sleek. Native keeps the picture clear; Fit wraps the pad around it.")

    public enum Arrangement: Equatable, Sendable {
        /// Native: the layout's own picture rect, clear of every control.
        case native
        /// Fit, and the pad fitted into the margin around the host's picture.
        case clear
        /// Fit, with no usable margin: floating over the outer thirds of the picture.
        case overlay
    }

    // MARK: Settings (the showcase pad's three)

    public var layoutPreset: ShowcaseLayoutPreset = .native { didSet { settingChanged() } }
    public var colourPreset: ShowcaseColourPreset = .wiiUWhite {
        // As in the showcase, picking a preset drops an imported colour file.
        didSet { customColours = nil }
    }
    /// An imported `.muffinclr`. Wins over `colourPreset` until a preset is picked again.
    public var customColours: ShowcaseColourFile?
    public var displayMode: ShowcaseLayout.DisplayMode = .fit { didSet { settingChanged() } }
    public var colours: ShowcaseColourFile { customColours ?? colourPreset.file }
    /// Optional glass look: bodies a little see-through, a sheen across the top of each button.
    /// Off by default; works with any colour preset or `.muffinclr`.
    public var glass: Bool = false

    /// Eases controls into and out of their held look when `scene(...time:)` is given a clock.
    var pressAnimator = ShowcasePressAnimator()
    /// True while a control is still easing; the host redraws next frame while it is.
    public var isAnimatingPress: Bool { pressAnimator.isAnimating }

    /// Physical density of the screen, in points per inch. Hosts set this from
    /// `ShowcaseDeviceMetrics.measurement` (hw.machine, native pixels); until they do, an
    /// estimate from the screen size is used.
    public var pointsPerInch: CGFloat? { didSet { settingChanged() } }

    /// Smallest button size, in points, Fit will shrink to before it floats over the picture.
    public var minimumUnit: CGFloat = 44

    // MARK: Layout results

    public private(set) var arrangement: Arrangement = .overlay
    /// Native only: where the picture goes. nil in Fit.
    public private(set) var pictureRect: CGRect?
    /// One GamePad face-button diameter, in points, as laid out.
    public private(set) var unitPoints: CGFloat = 0
    /// Fraction of the real GamePad's size the buttons came out at.
    public private(set) var lifeSizeFraction: CGFloat = 1
    public private(set) var notes: [String] = []
    private var pendingRelayout = false

    public init() { super.init(info: Self.schemeInfo) }

    private func settingChanged() {
        guard context.size != .zero else { return }
        if tracks.isEmpty { layout(context) } else { pendingRelayout = true }
    }

    override public func didBecomeIdle() {
        if pendingRelayout { pendingRelayout = false; layout(context) }
    }

    // MARK: Solving

    override public func makeControls(_ ctx: LayoutContext) -> [PadControl] {
        let ppi = pointsPerInch ?? ShowcaseDeviceMetrics.estimatePointsPerInch(size: ctx.size, insets: ctx.safeInsets)
        let isPhone = min(ctx.size.width, ctx.size.height) < 600
        let safe = ctx.safeBounds
        let mode = ShowcaseResolver.effectiveDisplayMode(displayMode, container: ctx.size, isPhone: isPhone)
        let videos = ctx.videoRects.filter { !$0.isEmpty }

        var preset = layoutPreset
        func resolve(_ s: CGFloat, _ m: ShowcaseLayout.DisplayMode) -> ShowcaseResolved {
            ShowcaseResolver.resolve(preset: preset, displayMode: m, container: ctx.size, safeArea: safe,
                                     pointsPerInch: ppi, isPhone: isPhone, userScale: ctx.scale * s)
        }
        func clear(_ controls: [PadControl], of rects: [CGRect]) -> Bool {
            for c in controls where !c.isZone {
                let box = c.shape.boundingBox
                if rects.contains(where: { $0.insetBy(dx: 1, dy: 1).intersects(box) }) { return false }
            }
            return true
        }

        // Fit: look for a size at which the pad sits wholly in the margin around the picture.
        if mode == .fit, !videos.isEmpty {
            var s: CGFloat = 1
            while s > 0.25 {
                let r = resolve(s, .fit)
                if r.unit < minimumUnit { break }
                let c = Self.controls(from: r, safe: safe, avoid: videos)
                if LayoutCheck.problems(c, in: safe).isEmpty, clear(c, of: videos) {
                    return adopt(r, c, .clear, picture: nil, ppi: ppi, ctx: ctx)
                }
                s *= 0.96
            }
        }

        // The resolver could not clear the picture: pack the pad's blocks into what is left.
        if mode == .fit, !videos.isEmpty {
            let wanted = ShowcaseHardware.unitMM * ppi / 25.4 * ctx.scale * layoutPreset.sizeFactor
            if let sol = ShowcaseFitSolver.solve(safe: safe, avoid: videos, wanted: wanted, floor: minimumUnit) {
                let unit = (sol.leftUnit + sol.rightUnit) / 2
                var notes = ["packed around the picture"]
                if abs(sol.leftUnit - sol.rightUnit) > 0.5 {
                    notes.append(String(format: "left %.0f pt, right %.0f pt buttons", sol.leftUnit, sol.rightUnit))
                }
                let r = ShowcaseResolved(video: videos[0], controls: sol.placements, unit: unit, notes: notes, mode: .overlay)
                let c = Self.controls(from: r, safe: safe, avoid: videos, asPlaced: true)
                if LayoutCheck.problems(c, in: safe).isEmpty, clear(c, of: videos) {
                    return adopt(r, c, .clear, picture: nil, ppi: ppi, ctx: ctx)
                }
            }
        }

        // Otherwise the layout's own arrangement, shrunk only as far as it has to be to be
        // valid (and, in Native, to keep clear of its own picture).
        // A transplanted preset that cannot be made to fit (the fitter never goes below the
        // touch floor, so shrinking does not always help) gives way to this device's own layout.
        var r = resolve(1, mode)
        var c = Self.controls(from: r, safe: safe, avoid: mode == .native ? [r.video] : [])
        func ok() -> Bool {
            LayoutCheck.problems(c, in: safe).isEmpty && (mode == .fit || clear(c, of: [r.video]))
        }
        for attempt in 0..<2 {
            var s: CGFloat = 1
            for _ in 0..<40 {
                if ok() { break }
                s *= 0.94
                r = resolve(s, mode)
                c = Self.controls(from: r, safe: safe, avoid: mode == .native ? [r.video] : [])
            }
            if ok() || preset == .native || attempt == 1 { break }
            preset = .native
            r = resolve(1, mode)
            c = Self.controls(from: r, safe: safe, avoid: mode == .native ? [r.video] : [])
        }
        return adopt(r, c, mode == .native ? .native : .overlay, picture: mode == .native ? r.video : nil,
                     ppi: ppi, ctx: ctx)
    }

    private func adopt(_ r: ShowcaseResolved, _ controls: [PadControl], _ a: Arrangement, picture: CGRect?,
                       ppi: CGFloat, ctx: LayoutContext) -> [PadControl] {
        arrangement = a
        pictureRect = picture
        unitPoints = r.unit
        lifeSizeFraction = r.unit / (ShowcaseHardware.unitMM * ppi / 25.4)
        notes = r.notes
        return controls
    }

    /// The control list for a resolved layout. The showcase leaves HOME in the pause menu
    /// when nothing on the pad clears for it; TouchLab has no pause menu, so HOME is always
    /// found a spot.
    /// `asPlaced` takes + and - and HOME exactly where the resolver left them (the Fit solver
    /// positions them itself) instead of regrouping them.
    static func controls(from r: ShowcaseResolved, safe: CGRect, avoid: [CGRect], asPlaced: Bool = false) -> [PadControl] {
        let D = r.unit
        var out: [PadControl] = []

        func circle(_ id: String) -> (c: CGPoint, r: CGFloat)? {
            if case let .circle(c, d)? = r.controls[id] { return (c, d / 2) }
            return nil
        }
        func button(_ id: String, _ b: PadButton, role: RenderElement.Role, reach: CGFloat, group: Int = 0,
                    chords: Bool = false, priority: Int = 1, label: String? = nil) {
            guard let (c, rad) = circle(id) else { return }
            out.append(PadControl(.button(b), shape: .circle(center: c, radius: rad), role: role,
                                  label: label ?? b.description, group: group, reach: reach, priority: priority,
                                  chords: chords))
        }

        for (id, b, g) in [("ZL", PadButton.zl, PadParts.Group.leftShoulders), ("L", .l, PadParts.Group.leftShoulders),
                           ("ZR", .zr, PadParts.Group.rightShoulders), ("R", .r, PadParts.Group.rightShoulders)] {
            if case let .pill(c, size, corner)? = r.controls[id] {
                out.append(PadControl(.button(b), shape: .roundedRect(CGRect(center: c, size: size), cornerRadius: corner),
                                      role: .shoulder, label: b.description, group: g, reach: 0.3 * D))
            }
        }
        for (id, s) in [("stickL", PadStick.left), ("stickR", .right)] {
            if let (c, rad) = circle(id) {
                out.append(PadControl(.stick(s, travel: rad, click: nil), shape: .circle(center: c, radius: rad),
                                      role: .stickBase, label: s == .left ? "L" : "R", reach: 0.25 * D))
            }
        }
        if case let .cross(c, size, arm)? = r.controls["dpad"] {
            let dot = circle("L3")?.r ?? 0.353 * D
            out.append(PadControl(.dpad(click: .stickL, clickRadius: dot,
                                        armOffset: CGPoint(x: (size.width - arm) / 2, y: (size.height - arm) / 2),
                                        armSize: arm),
                                  shape: .circle(center: c, radius: max(size.width, size.height) / 2),
                                  role: .dpad, reach: 0.3 * D))
        }
        for (id, b) in [("X", PadButton.x), ("Y", .y), ("A", .a), ("B", .b)] {
            button(id, b, role: .face, reach: 0.4 * D, group: PadParts.Group.face, chords: true)
        }
        if let (c, rad) = circle("R3") {
            out.append(PadControl(.button(.stickR), shape: .circle(center: c, radius: rad), role: .dot, label: "R3",
                                  reach: 0.08 * D, priority: 2))
        }
        // + then - as a pair on one row, + nudged a little left to make room, - on its right.
        if let (pc, pr) = circle("plus"), let (mc, mr) = circle("minus") {
            let plus = asPlaced ? pc : CGPoint(x: pc.x - 0.3 * D, y: pc.y)
            let minus = asPlaced ? mc : CGPoint(x: plus.x + pr + mr + 0.3 * D, y: pc.y)
            out.append(PadControl(.button(.plus), shape: .circle(center: plus, radius: pr), role: .system,
                                  label: PadButton.plus.description, reach: 0.25 * D))
            out.append(PadControl(.button(.minus), shape: .circle(center: minus, radius: mr), role: .system,
                                  label: PadButton.minus.description, reach: 0.25 * D))
        }
        // HOME keeps its hardware slot unless that is on the picture.
        if let (c, rad) = circle("HOME"),
           asPlaced || !avoid.contains(where: { $0.insetBy(dx: 1, dy: 1).intersects(PadShape.circle(center: c, radius: rad).boundingBox) }) {
            button("HOME", .home, role: .system, reach: 0.25 * D)
        }

        if !out.contains(where: { $0.button == .home }) {
            let rad = ShowcaseHardware.homeDiameter / 2 * D
            if let c = homeSpot(radius: rad, among: out, safe: safe, avoid: avoid, unit: D) {
                out.append(PadControl(.button(.home), shape: .circle(center: c, radius: rad), role: .system,
                                      label: PadButton.home.description, reach: 0.25 * D))
            }
        }
        return out
    }

    /// The first free spot for HOME, scanning up from the bottom edge outward from centre.
    private static func homeSpot(radius: CGFloat, among: [PadControl], safe: CGRect, avoid: [CGRect],
                                 unit: CGFloat) -> CGPoint? {
        var y = safe.maxY - radius - 0.35 * unit
        while y > safe.minY + radius {
            var dx: CGFloat = 0
            while dx <= safe.width / 2 - radius {
                for sign: CGFloat in dx == 0 ? [1] : [1, -1] {
                    let c = CGPoint(x: safe.midX + sign * dx, y: y)
                    let shape = PadShape.circle(center: c, radius: radius)
                    let box = shape.boundingBox
                    if avoid.contains(where: { $0.intersects(box) }) { continue }
                    if !among.contains(where: { $0.role != .dot && $0.shape.overlaps(shape, margin: -2) }) { return c }
                }
                dx += 0.25 * unit
            }
            y -= 0.3 * unit
        }
        return nil
    }

    // MARK: Rendering for the generic drawer

    /// The plain element list, for any drawer that only knows `RenderElement`s (the sticks
    /// sit at the knob's travelled position). The designed look is `scene(pressed:sticks:)`.
    override public func render(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> [RenderElement] {
        var out: [RenderElement] = []
        let active = Dictionary(tracks.values.map { ($0.control, $0) }, uniquingKeysWith: { a, _ in a })
        for (i, c) in controls.enumerated() {
            switch c.kind {
            case .button(let b):
                out.append(RenderElement(shape: c.shape, role: c.role, label: c.role == .dot ? "" : c.label,
                                         lit: pressed.contains(b)))
            case let .dpad(click, clickRadius, arm, size):
                let o = c.shape.center
                for (b, d) in [(PadButton.up, CGPoint(x: 0, y: -arm.y)), (.down, CGPoint(x: 0, y: arm.y)),
                               (.left, CGPoint(x: -arm.x, y: 0)), (.right, CGPoint(x: arm.x, y: 0))] {
                    out.append(RenderElement(shape: .roundedRect(CGRect(center: o + d, size: CGSize(width: size, height: size)),
                                                                 cornerRadius: size * 0.2),
                                             role: .dpad, label: b.description, lit: pressed.contains(b)))
                }
                if let click {
                    out.append(RenderElement(shape: .circle(center: o, radius: clickRadius), role: .dot, lit: pressed.contains(click)))
                }
            case let .stick(_, travel, _):
                let t = active[i]
                // The base stays put unless a finger moved it (relative centre, follow).
                let base = t?.origin ?? c.shape.center
                let knobR = travel * ShowcaseHardware.stickKnob / ShowcaseHardware.stickBase
                out.append(RenderElement(shape: .circle(center: base, radius: travel), role: .stickBase, lit: t != nil))
                out.append(RenderElement(shape: .circle(center: base + (t?.knob ?? .zero) * Self.knobTravelRatio(travel, knobR), radius: knobR),
                                         role: .stickKnob, label: c.label, lit: false))
            default:
                break
            }
        }
        return out
    }

    /// The knob is drawn inside the dish: the finger's travel is the dish radius, the
    /// knob's is what is left of it once the cap is in.
    static func knobTravelRatio(_ dishRadius: CGFloat, _ knobRadius: CGFloat) -> CGFloat {
        dishRadius > 0 ? (dishRadius - knobRadius) / dishRadius : 0
    }
}

// MARK: - Screens

public extension ShowcaseDeviceMetrics {
    /// A guess from the screen size alone, for a host that has not measured. Phones with a
    /// notch or island are the 460 ppi OLEDs (153 pt/in); the rest 326 ppi at 2x (163);
    /// iPads are 132 except the mini's 744 pt short side (163). Hosts should do better: see
    /// `measurement(identifier:nativePixels:scale:isPad:calibrated:)`.
    static func estimatePointsPerInch(size: CGSize, insets: Insets) -> CGFloat {
        let short = min(size.width, size.height)
        if short < 600 {
            let notched = insets.left > 0 || insets.right > 0 || insets.top > 30 || insets.bottom > 30
            return notched ? 460 / 3 : 163
        }
        return abs(short - 744) < 1 ? 163 : 132
    }
}

public extension TargetDevice {
    /// The exact density of each device in `TargetDevice.all` (and its portrait twin).
    var showcasePointsPerInch: CGFloat {
        let n = name.replacingOccurrences(of: " portrait", with: "")
        switch n {
        case "iPhone SE 1st gen", "iPhone SE": return 163
        case "iPhone 16", "iPhone 16 Pro Max": return 460 / 3
        case "iPhone 8 Plus": return 401 / 2.608
        case "iPad mini": return 163
        default: return 132
        }
    }

    /// The five reference devices, each in both orientations, with upright safe areas.
    static var showcaseReview: [TargetDevice] {
        let landscape = all.filter { ["iPhone SE", "iPhone 16 Pro Max", "iPad mini", "iPad Pro 11 (A12Z)", "iPad Pro 13"].contains($0.name) }
        return landscape.flatMap { d -> [TargetDevice] in
            let notched = d.insets.left > 0
            let up = Insets(top: notched ? d.insets.left : d.insets.top, left: 0,
                            bottom: notched ? 34 : d.insets.bottom, right: 0)
            return [d, TargetDevice(name: d.name + " portrait", size: CGSize(width: d.size.height, height: d.size.width), insets: up)]
        }
    }
}

/// A fixed set of fingers down, for previews and checks: A and B (a chord), the d-pad
/// up-right, ZR, and the right stick pushed. Reads the control positions it needs from the pad.
public enum ShowcaseDemo {
    public static func press(_ engine: PadEngine, _ pad: ShowcasePad) {
        func centre(_ b: PadButton) -> CGPoint? { pad.controls.first { $0.button == b }?.shape.center }
        var id = 1
        func down(_ p: CGPoint?) {
            guard let p else { return }
            engine.began(id, at: p, time: 0)
            id += 1
        }
        if let a = centre(.a), let b = centre(.b) { down(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)) }
        down(centre(.zr))
        if let d = pad.controls.first(where: { if case .dpad = $0.kind { return true }; return false }) {
            let r = d.shape.boundingBox.width / 2
            down(d.shape.center + CGPoint(x: 0.5 * r, y: -0.5 * r))
        }
        if let s = pad.controls.first(where: { if case .stick(.right, _, _) = $0.kind { return true }; return false }) {
            let r = s.shape.boundingBox.width / 2
            let start = id
            down(s.shape.center)
            engine.moved(start, to: s.shape.center + CGPoint(x: 0.6 * r, y: -0.5 * r), time: 0.1)
        }
    }
}


// MARK: - Press animation

/// Per-button easing between up (0) and held (1): about 60 ms down, 150 ms back up, so a tap
/// reads as a quick dip rather than a flash. With Reduce Motion on, a button just snaps.
public struct ShowcasePressAnimator {
    public static let attack: Double = 0.06
    public static let release: Double = 0.15

    private var raw: [PadButton: Double] = [:]
    private var targets: [PadButton: Double] = [:]
    private var last: Double?

    public init() {}

    public mutating func step(pressed: Set<PadButton>, time: Double, reduceMotion: Bool) {
        // A first frame, or a long gap (the view was off screen), settles at once.
        let dt = last.map { min(max(time - $0, 0), 0.1) } ?? 1
        last = time
        for b in pressed { targets[b] = 1 }
        for b in targets.keys where !pressed.contains(b) { targets[b] = 0 }
        for (b, target) in targets {
            let now = raw[b] ?? 0
            if reduceMotion || dt >= 1 { raw[b] = target }
            else if target > now { raw[b] = min(target, now + dt / Self.attack) }
            else if target < now { raw[b] = max(target, now - dt / Self.release) }
            if raw[b] == 0, target == 0 { raw[b] = nil; targets[b] = nil }
        }
    }

    /// Smoothstepped, so the start and end of an ease are gentle.
    public var eased: [PadButton: CGFloat] {
        raw.mapValues { v in CGFloat(v * v * (3 - 2 * v)) }
    }

    public var isAnimating: Bool {
        targets.contains { (b, t) in (raw[b] ?? 0) != t }
    }
}
