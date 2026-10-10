import CoreGraphics
import Foundation

// The Showcase look, as data. A scene is an ordered list of vector primitives with their
// fills, strokes and shadows already decided, so a drawer is a dumb loop: `ShowcaseSVG`
// writes the previews, and a CoreGraphics or UIKit drawer is the same loop over the same
// list. Nothing here knows about UIKit.
//
// The recipe is one for every control, so the pad reads as a single object:
//   - a flat body in the colour file's fill, a hairline outline in its outline colour,
//   - a soft drop shadow so it lifts off any picture, light or dark,
//   - a thin rim inside the edge, lit from above (highlight on top, shade underneath),
//   - held: the rim inverts, the body shrinks 5% and moves a step darker (lighter, on a dark
//     button), the shadow tightens. No colour is borrowed from outside the colour file.

public enum ShowcasePathCommand: Equatable {
    case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), close
}

public enum ShowcaseShape: Equatable {
    case circle(CGPoint, CGFloat)
    case rect(CGRect, CGFloat)
    case path([ShowcasePathCommand])
}

public enum ShowcasePaint: Equatable {
    case solid(ShowcaseRGBA)
    /// Top to bottom of the shape's bounds: (offset 0...1, colour).
    case vertical([ShowcaseStop])
}

public struct ShowcaseStop: Equatable {
    public var offset: Double
    public var colour: ShowcaseRGBA
}

public struct ShowcaseShadow: Equatable {
    public var blur: CGFloat, dy: CGFloat, opacity: Double
}

public struct ShowcasePrimitive: Equatable {
    public var shape: ShowcaseShape
    public var fill: ShowcasePaint?
    public var stroke: ShowcasePaint?
    public var strokeWidth: CGFloat = 0
    public var shadow: ShowcaseShadow?
    /// Text drawn at the shape's centre instead of (or as well as) the shape.
    public var text: String?
    public var textSize: CGFloat = 0
    public var textColour: ShowcaseRGBA?
}

public struct ShowcaseScene: Equatable {
    public var size: CGSize
    /// Whole-pad opacity; the video shows faintly through, as in the showcase.
    public var opacity: Double
    public var primitives: [ShowcasePrimitive]
}

// MARK: - Colour helpers

extension ShowcaseRGBA {
    func mixed(_ other: ShowcaseRGBA, _ t: Double) -> ShowcaseRGBA {
        ShowcaseRGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }
    func withAlpha(_ alpha: Double) -> ShowcaseRGBA { ShowcaseRGBA(r: r, g: g, b: b, a: alpha) }
    static let white = ShowcaseRGBA(r: 1, g: 1, b: 1)
    static let black = ShowcaseRGBA(r: 0, g: 0, b: 0)

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    var isLight: Bool { luminance > 0.35 }

    static func contrast(_ a: ShowcaseRGBA, _ b: ShowcaseRGBA) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `self` when it already reaches `minimum` on `background`, otherwise moved toward black
    /// or white - whichever gets there sooner, and only as far as it has to - so the hue a
    /// colour file chose survives wherever it can. (The showcase's `LegibleInk.ensure`.)
    func legible(on background: ShowcaseRGBA, minimum: Double = 3) -> ShowcaseRGBA {
        if Self.contrast(self, background) >= minimum { return self }
        for step in 1...20 {
            let t = Double(step) / 20
            for target in [ShowcaseRGBA.black, .white] {
                let c = mixed(target, t).withAlpha(a)
                if Self.contrast(c, background) >= minimum { return c }
            }
        }
        return background.isLight ? .black : .white
    }
}

// MARK: - Building the scene

extension ShowcasePad {
    /// The pad as it should be drawn right now. `pressed` and `sticks` are the mixer's.
    public func scene(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> ShowcaseScene {
        var b = SceneBuilder(colours: colours)
        let active = Dictionary(tracks.values.map { ($0.control, $0) }, uniquingKeysWith: { a, _ in a })
        let gate = context.stick.gate

        // Back to front: the sticks' dishes, then the clusters, then the shoulders and system
        // row, so nothing's shadow is cut by a neighbour drawn later.
        for (i, c) in controls.enumerated() {
            if case let .stick(stick, travel, _) = c.kind {
                b.stick(stick, centre: c.shape.center, dish: travel, gate: gate, track: active[i], held: pressed.contains(stick == .left ? .stickL : .stickR))
            }
        }
        for c in controls {
            switch c.kind {
            case .dpad:
                if case let .circle(centre, _) = c.shape { b.dpad(centre: centre, pad: c, pressed: pressed) }
            case .button(let btn):
                let on = pressed.contains(btn)
                switch c.role {
                case .face: b.round(id: btn.description, shape: c.shape, pressed: on, glyph: .letter(btn.description))
                case .shoulder: b.pill(id: btn.description, shape: c.shape, pressed: on, label: btn.description)
                case .system:
                    let glyph: SceneBuilder.Glyph = btn == .plus ? .plus : btn == .minus ? .minus : .home
                    b.round(id: btn == .plus ? "plus" : btn == .minus ? "minus" : "HOME", shape: c.shape, pressed: on, glyph: glyph)
                case .dot: b.dimple(id: "R3", shape: c.shape, pressed: on)
                default: break
                }
            default: break
            }
        }
        return ShowcaseScene(size: context.size, opacity: 0.94, primitives: b.out)
    }
}

struct SceneBuilder {
    let colours: ShowcaseColourFile
    var out: [ShowcasePrimitive] = []

    enum Glyph { case letter(String), plus, minus, home, none }

    init(colours: ShowcaseColourFile) { self.colours = colours }

    // Rim stops: lit from above while up, from below while held.
    private func rim(_ fill: ShowcaseRGBA, pressed: Bool) -> ShowcasePaint {
        let light = fill.isLight
        let hi = ShowcaseRGBA.white.withAlpha(light ? 0.85 : 0.30)
        let lo = ShowcaseRGBA.black.withAlpha(light ? 0.16 : 0.45)
        let clear = ShowcaseRGBA.white.withAlpha(0)
        return pressed
            ? .vertical([ShowcaseStop(offset: 0, colour: lo), ShowcaseStop(offset: 0.45, colour: clear.withAlpha(0)),
                         ShowcaseStop(offset: 1, colour: hi.withAlpha(hi.a * 0.5))])
            : .vertical([ShowcaseStop(offset: 0, colour: hi), ShowcaseStop(offset: 0.5, colour: clear),
                         ShowcaseStop(offset: 1, colour: lo)])
    }

    /// Body + outline + rim + shadow for any shape; `make(inset)` rebuilds it smaller.
    mutating func body(_ make: (CGFloat) -> ShowcaseShape, minDim: CGFloat, id: String, pressed: Bool,
                       shadow: ShowcaseShadow = ShowcaseShadow(blur: 1.6, dy: 1.2, opacity: 0.30)) {
        var fill = colours.fill(id).withAlpha(colours.alpha(id, pressed: pressed))
        if pressed {
            fill = fill.isLight ? fill.mixed(.black, 0.16) : fill.mixed(.white, 0.18)
        }
        let w = min(max(minDim * 0.03, 1), 1.8)
        out.append(ShowcasePrimitive(shape: make(0), fill: .solid(fill), stroke: nil, shadow: pressed
            ? ShowcaseShadow(blur: 0.8, dy: 0.5, opacity: 0.18) : shadow))
        out.append(ShowcasePrimitive(shape: make(0.5), fill: nil, stroke: .solid(colours.outline.withAlpha(0.9)), strokeWidth: 1))
        out.append(ShowcasePrimitive(shape: make(1 + w / 2), fill: nil, stroke: rim(fill, pressed: pressed), strokeWidth: w))
    }

    private func ink(_ id: String) -> ShowcaseRGBA {
        colours.glyph(id).legible(on: colours.fill(id).withAlpha(1), minimum: 3)
    }

    private func scaled(_ r: CGFloat, pressed: Bool) -> CGFloat { pressed ? r * 0.95 : r }

    mutating func round(id: String, shape: PadShape, pressed: Bool, glyph: Glyph) {
        guard case let .circle(c, r0) = shape else { return }
        let r = scaled(r0, pressed: pressed)
        body({ ShowcaseShape.circle(c, r - $0) }, minDim: 2 * r, id: id, pressed: pressed)
        let colour = ink(id)
        switch glyph {
        case .letter(let s):
            out.append(ShowcasePrimitive(shape: .circle(c, 0), text: s, textSize: Self.textSize(2 * r0), textColour: colour))
        case .plus:
            let a = r * 0.36
            stroke([.move(CGPoint(x: c.x - a, y: c.y)), .line(CGPoint(x: c.x + a, y: c.y))], colour, r * 0.17)
            stroke([.move(CGPoint(x: c.x, y: c.y - a)), .line(CGPoint(x: c.x, y: c.y + a))], colour, r * 0.17)
        case .minus:
            let a = r * 0.36
            stroke([.move(CGPoint(x: c.x - a, y: c.y)), .line(CGPoint(x: c.x + a, y: c.y))], colour, r * 0.17)
        case .home:
            let s = r * 0.52
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y + y * s - 0.04 * s) }
            out.append(ShowcasePrimitive(shape: .path([.move(p(-1, 0.05)), .line(p(0, -0.95)), .line(p(1, 0.05)), .line(p(0.72, 0.05)),
                                                       .line(p(0.72, 0.9)), .line(p(0.2, 0.9)), .line(p(0.2, 0.35)), .line(p(-0.2, 0.35)),
                                                       .line(p(-0.2, 0.9)), .line(p(-0.72, 0.9)), .line(p(-0.72, 0.05)), .close]),
                                         fill: .solid(colour)))
        case .none: break
        }
    }

    mutating func pill(id: String, shape: PadShape, pressed: Bool, label: String) {
        guard case let .roundedRect(rect0, cr0) = shape else { return }
        let k: CGFloat = pressed ? 0.95 : 1
        let rect = CGRect(center: rect0.center, size: CGSize(width: rect0.width * k, height: rect0.height * k))
        let cr = cr0 * k
        body({ ShowcaseShape.rect(rect.insetBy(dx: $0, dy: $0), max(cr - $0, 0)) }, minDim: rect.height, id: id, pressed: pressed)
        out.append(ShowcasePrimitive(shape: .circle(rect0.center, 0), text: label, textSize: Self.textSize(rect0.height),
                                     textColour: ink(id)))
    }

    /// The L3/R3 click: a shallow dimple at the middle of its cluster, not a button.
    mutating func dimple(id: String, shape: PadShape, pressed: Bool) {
        guard case let .circle(c, r) = shape else { return }
        let base = colours.fill("dpad").withAlpha(1)
        let tone = pressed ? (base.isLight ? base.mixed(.black, 0.26) : base.mixed(.white, 0.28))
                           : (base.isLight ? base.mixed(.black, 0.08) : base.mixed(.white, 0.07))
        out.append(ShowcasePrimitive(shape: .circle(c, r), fill: .solid(tone)))
        out.append(ShowcasePrimitive(shape: .circle(c, r - 0.5), fill: nil,
                                     stroke: .vertical([ShowcaseStop(offset: 0, colour: ShowcaseRGBA.black.withAlpha(0.20)),
                                                        ShowcaseStop(offset: 0.5, colour: ShowcaseRGBA.black.withAlpha(0)),
                                                        ShowcaseStop(offset: 1, colour: ShowcaseRGBA.white.withAlpha(base.isLight ? 0.55 : 0.18))]),
                                     strokeWidth: 1))
    }

    mutating func dpad(centre c: CGPoint, pad: PadControl, pressed: Set<PadButton>) {
        guard case let .dpad(_, clickRadius, armOffset, armSize) = pad.kind else { return }
        let w = armOffset.x * 2 + armSize, h = armOffset.y * 2 + armSize
        let corner = min(armSize * 0.24, armSize / 2 - 0.5)
        let down = pressed.intersection([.up, .down, .left, .right])
        body({ i in ShowcaseShape.path(Self.cross(c, w - 2 * i, h - 2 * i, armSize - 2 * i, max(corner - i * 0.6, 0.5))) },
             minDim: armSize, id: "dpad", pressed: false)
        // A held direction shades its own arm, so a diagonal reads as two.
        for d in down {
            let a = armSize / 2 - 1
            let r: CGRect
            switch d {
            case .up: r = CGRect(x: c.x - a, y: c.y - h / 2 + 1, width: 2 * a, height: h / 2 - 1)
            case .down: r = CGRect(x: c.x - a, y: c.y, width: 2 * a, height: h / 2 - 1)
            case .left: r = CGRect(x: c.x - w / 2 + 1, y: c.y - a, width: w / 2 - 1, height: 2 * a)
            default: r = CGRect(x: c.x, y: c.y - a, width: w / 2 - 1, height: 2 * a)
            }
            let base = colours.fill("dpad")
            out.append(ShowcasePrimitive(shape: .rect(r, corner),
                                         fill: .solid((base.isLight ? ShowcaseRGBA.black : .white).withAlpha(base.isLight ? 0.20 : 0.22))))
        }
        // Arrowheads, quiet until held.
        let ink = self.ink("dpad")
        let tipR = max(w, h) / 2
        for (d, dx, dy) in [(PadButton.up, 0.0, -1.0), (.down, 0, 1), (.left, -1, 0), (.right, 1, 0)] {
            let mid = CGPoint(x: c.x + CGFloat(dx) * tipR * 0.68, y: c.y + CGFloat(dy) * tipR * 0.68)
            let s = armSize * 0.2
            let nx = CGFloat(-dy), ny = CGFloat(dx)
            let apex = CGPoint(x: mid.x + CGFloat(dx) * s, y: mid.y + CGFloat(dy) * s)
            let p1 = CGPoint(x: mid.x - CGFloat(dx) * s * 0.55 + nx * s * 1.1, y: mid.y - CGFloat(dy) * s * 0.55 + ny * s * 1.1)
            let p2 = CGPoint(x: mid.x - CGFloat(dx) * s * 0.55 - nx * s * 1.1, y: mid.y - CGFloat(dy) * s * 0.55 - ny * s * 1.1)
            out.append(ShowcasePrimitive(shape: .path([.move(apex), .line(p1), .line(p2), .close]),
                                         fill: .solid(ink.withAlpha(down.contains(d) ? 0.95 : 0.5))))
        }
        // L3: the dimple in the middle.
        let held = pressed.contains(.stickL)
        dimple(id: "L3", shape: .circle(center: c, radius: clickRadius), pressed: held)
    }

    mutating func stick(_ s: PadStick, centre c: CGPoint, dish R: CGFloat, gate: StickTuning.Gate, track: ControlScheme.Track?,
                        held: Bool) {
        let id = s == .left ? "stickL" : "stickR"
        let fill = colours.fill(id).withAlpha(1)
        let engaged = track != nil
        // Dish: a shallow recess, the lit edge underneath.
        let dishFill = fill.withAlpha(engaged ? 0.58 : 0.42)
        out.append(ShowcasePrimitive(shape: .circle(c, R), fill: .solid(dishFill)))
        out.append(ShowcasePrimitive(shape: .circle(c, R - 0.5), fill: nil, stroke: .solid(colours.outline.withAlpha(0.8)), strokeWidth: 1))
        let w = min(max(R * 0.04, 1), 1.8)
        out.append(ShowcasePrimitive(shape: .circle(c, R - 1 - w / 2), fill: nil,
                                     stroke: .vertical([ShowcaseStop(offset: 0, colour: ShowcaseRGBA.black.withAlpha(0.28)),
                                                        ShowcaseStop(offset: 0.5, colour: ShowcaseRGBA.black.withAlpha(0)),
                                                        ShowcaseStop(offset: 1, colour: ShowcaseRGBA.white.withAlpha(0.45))]),
                                     strokeWidth: w))
        // Gate: the shape the cap can reach, drawn as a thin ring.
        let ring = colours.glyph(id).legible(on: dishFill.mixed(.white, 0.0).withAlpha(1), minimum: 2)
        let gr = R * 0.8
        out.append(ShowcasePrimitive(shape: gate == .round ? .circle(c, gr) : .path(Self.octagon(c, gr)), fill: nil,
                                     stroke: .solid(ring.withAlpha(engaged ? 0.7 : 0.4)), strokeWidth: 1))
        // Cap: solid, travelling inside the dish.
        let kr = R * ShowcaseHardware.stickKnob / ShowcaseHardware.stickBase
        let k = (track?.knob ?? .zero) * ((R - kr) / max(R, 1))
        let kc = CGPoint(x: c.x + k.x, y: c.y + k.y)
        let pressed = held || engaged
        body({ ShowcaseShape.circle(kc, (pressed ? kr * 0.97 : kr) - $0) }, minDim: 2 * kr, id: id, pressed: held,
             shadow: ShowcaseShadow(blur: 2.6, dy: 2, opacity: 0.34))
        if engaged && !held {
            out.append(ShowcasePrimitive(shape: .circle(kc, kr * 0.97 - 1.5), fill: .solid(ShowcaseRGBA.black.withAlpha(fill.isLight ? 0.08 : 0)),
                                         stroke: nil))
        }
        // A fine concentric mark on the cap, so its position reads at a glance.
        out.append(ShowcasePrimitive(shape: .circle(kc, kr * 0.52), fill: nil,
                                     stroke: .solid(colours.glyph(id).withAlpha(0.28)), strokeWidth: 1))
    }

    private mutating func stroke(_ cmds: [ShowcasePathCommand], _ colour: ShowcaseRGBA, _ width: CGFloat) {
        out.append(ShowcasePrimitive(shape: .path(cmds), fill: nil, stroke: .solid(colour), strokeWidth: width))
    }

    // MARK: Geometry

    /// Type size on a control `height` tall: the other schemes' rule (42% of it, 10...26 pt).
    static func textSize(_ height: CGFloat) -> CGFloat { max(min(height * 0.42, 26), 10) }

    static func octagon(_ c: CGPoint, _ r: CGFloat) -> [ShowcasePathCommand] {
        // The gate reaches full travel on the eight main directions and ~8% less on the flats
        // (StickMath.gateFraction), so the ring is an octagon with its corners on them.
        let pts = (0..<8).map { k -> CGPoint in
            let a = CGFloat(k) * .pi / 4
            return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        return rounded(pts, radius: r * 0.12)
    }

    /// The d-pad's cross, centred on `c`, `w` x `h` overall, arms `arm` wide.
    static func cross(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ arm: CGFloat, _ radius: CGFloat) -> [ShowcasePathCommand] {
        let a = arm / 2, hw = w / 2, hh = h / 2
        let pts: [CGPoint] = [
            CGPoint(x: -a, y: -hh), CGPoint(x: a, y: -hh), CGPoint(x: a, y: -a), CGPoint(x: hw, y: -a),
            CGPoint(x: hw, y: a), CGPoint(x: a, y: a), CGPoint(x: a, y: hh), CGPoint(x: -a, y: hh),
            CGPoint(x: -a, y: a), CGPoint(x: -hw, y: a), CGPoint(x: -hw, y: -a), CGPoint(x: -a, y: -a),
        ].map { CGPoint(x: c.x + $0.x, y: c.y + $0.y) }
        return rounded(pts, radius: radius)
    }

    /// A closed polygon with every corner rounded by `radius` (quadratic corners).
    static func rounded(_ pts: [CGPoint], radius: CGFloat) -> [ShowcasePathCommand] {
        let n = pts.count
        var cmds: [ShowcasePathCommand] = []
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            let d1 = prev.distance(to: cur), d2 = cur.distance(to: next)
            let r = min(radius, d1 / 2, d2 / 2)
            let a = CGPoint(x: cur.x + (prev.x - cur.x) * r / max(d1, 0.001), y: cur.y + (prev.y - cur.y) * r / max(d1, 0.001))
            let b = CGPoint(x: cur.x + (next.x - cur.x) * r / max(d2, 0.001), y: cur.y + (next.y - cur.y) * r / max(d2, 0.001))
            cmds.append(i == 0 ? .move(a) : .line(a))
            cmds.append(.quad(cur, b))
        }
        cmds.append(.close)
        return cmds
    }
}
