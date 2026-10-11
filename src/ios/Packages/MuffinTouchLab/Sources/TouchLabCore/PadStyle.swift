import CoreGraphics
import Foundation

// One look for the classic schemes (Zone, Float, Adaptive, Frame, Racing).
//
// A scheme only says WHAT is on screen (`RenderElement`s: role, shape, label, lit). This file
// decides how it looks, and does it once for all five: one corner-radius rule, a hairline
// outline, a soft shadow, a thin rim lit from above, a pressed state that is visible on every
// control, and one type scale. It is the Showcase recipe (`SceneBuilder`) applied to the
// classic controls, as a `ShowcaseScene`, so the previews and the device draw the same list.
//
// Colour: `PadLook` wraps a Showcase colour file, so a preset the player picks for Showcase is
// a preset for every scheme. nil (the default) is the classic look these schemes always had:
// pale buttons, a dark stick dish, and a yellow pressed state.

/// A colour file plus the few things a `.muffinclr` has no field for.
public struct PadLook: Equatable {
    public var colours: ShowcaseColourFile
    /// Fill of a held control. nil = the Showcase way (a step darker, or lighter on dark).
    public var lit: ShowcaseRGBA?
    public var litInk: ShowcaseRGBA
    /// Stick dish. nil = the stick's own fill, translucent, as Showcase does.
    public var dish: ShowcaseRGBA?
    /// Catchment hints (floating zones, Racing's steering area).
    public var tint: ShowcaseRGBA
}


public enum PadStyle {
    /// Schemes drawn with this style. Arc and Showcase have their own looks.
    public static let schemeIDs: Set<String> = ["zone", "float", "adaptive", "frame", "racing"]
    public static func appliesTo(_ schemeID: String) -> Bool { schemeIDs.contains(schemeID) }

    public static let tint = ShowcaseRGBA("#7FA8FF")

    /// The look these schemes had before presets: same greys, same yellow.
    public static let classicColours = ShowcaseColourFile(
        name: "Classic",
        fills: ["face": ShowcaseRGBA("#EDEDED", 0.72), "dpad": ShowcaseRGBA("#CCCCCC", 0.72),
                "shoulderL": ShowcaseRGBA("#949494", 0.72), "shoulderR": ShowcaseRGBA("#949494", 0.72),
                "start": ShowcaseRGBA("#666666", 0.80), "select": ShowcaseRGBA("#666666", 0.80),
                "home": ShowcaseRGBA("#666666", 0.80),
                "stickL": ShowcaseRGBA("#BFBFBF", 0.85), "stickR": ShowcaseRGBA("#BFBFBF", 0.85),
                "default": ShowcaseRGBA("#EDEDED", 0.72)],
        glyphs: ["default": ShowcaseRGBA("#1F1F1F"), "shoulderL": ShowcaseRGBA("#0D0D0D"), "shoulderR": ShowcaseRGBA("#0D0D0D"),
                 "start": ShowcaseRGBA("#FFFFFF"), "select": ShowcaseRGBA("#FFFFFF"), "home": ShowcaseRGBA("#FFFFFF")],
        outline: ShowcaseRGBA("#E4E4EA"),
        pressedAlphaBoost: 0.12)

    /// nil = Classic.
    public static func look(_ preset: ShowcaseColourPreset?) -> PadLook {
        guard let preset else {
            return PadLook(colours: classicColours, lit: ShowcaseRGBA("#FFC93C", 0.95), litInk: ShowcaseRGBA("#1A1400"),
                           dish: ShowcaseRGBA("#383840", 0.62), tint: tint)
        }
        return PadLook(colours: preset.file, lit: nil, litInk: ShowcaseRGBA("#1A1400"), dish: nil, tint: tint)
    }

    public static func name(_ preset: ShowcaseColourPreset?) -> String { preset?.file.name ?? "Classic" }

    /// Every choice a settings screen offers, in order: Classic first.
    public static var choices: [ShowcaseColourPreset?] { [nil] + ShowcaseColourPreset.allCases.map { Optional($0) } }

    /// The elements as a scene. `opacity` is the player's pad opacity.
    public static func scene(elements: [RenderElement], size: CGSize, look: PadLook = PadStyle.look(nil),
                             opacity: CGFloat = PadSettings.defaultOpacity) -> ShowcaseScene {
        var b = ClassicBuilder(look: look)
        for e in elements { b.add(e) }
        return ShowcaseScene(size: size, opacity: Double(opacity), primitives: b.out)
    }

    /// The one corner rule for every rectangle: about a quarter of its short side, never more than 18.
    public static func cornerRadius(width: CGFloat, height: CGFloat) -> CGFloat {
        min(min(width, height) * 0.26, 18)
    }

    /// The one type scale. Everything a label says comes from one of three sizes, by the
    /// height of what it sits on: buttons and pedals, hints, and the tiny click-dot tag.
    public enum TypeScale {
        public static func button(_ height: CGFloat) -> CGFloat { max(min(height * 0.42, 24), 11) }
        public static let hint: CGFloat = 13
        public static func tag(_ diameter: CGFloat) -> CGFloat { max(min(diameter * 0.40, 12), 9) }
    }
}

struct ClassicBuilder {
    let look: PadLook
    let sb: SceneBuilder
    var out: [ShowcasePrimitive] = []
    var colours: ShowcaseColourFile { look.colours }

    init(look: PadLook) {
        self.look = look
        sb = SceneBuilder(colours: look.colours)
    }

    // MARK: Helpers

    private func faded(_ p: ShowcasePrimitive, _ k: Double) -> ShowcasePrimitive {
        guard k < 1 else { return p }
        func paint(_ x: ShowcasePaint?) -> ShowcasePaint? {
            switch x {
            case .solid(let c)?: return .solid(c.withAlpha(c.a * k))
            case .vertical(let s)?: return .vertical(s.map { ShowcaseStop(offset: $0.offset, colour: $0.colour.withAlpha($0.colour.a * k)) })
            case nil: return nil
            }
        }
        var q = p
        q.fill = paint(p.fill)
        q.stroke = paint(p.stroke)
        if let s = p.shadow { q.shadow = ShowcaseShadow(blur: s.blur, dy: s.dy, opacity: s.opacity * k) }
        if let t = p.textColour { q.textColour = t.withAlpha(t.a * k) }
        return q
    }

    private mutating func put(_ p: ShowcasePrimitive, fade k: Double = 1) { out.append(faded(p, k)) }

    /// Colour id of an element, so presets and `.muffinclr` keys line up with Showcase's.
    static func id(_ e: RenderElement) -> String {
        switch e.role {
        case .face: return e.label
        case .dpad: return "dpad"
        case .shoulder:
            return ["L", "R", "ZL", "ZR"].contains(e.label) ? e.label : "L"
        case .system:
            switch e.label {
            case "+": return "plus"
            case "\u{2212}", "-": return "minus"
            case "\u{2302}": return "HOME"
            default: return "plus"
            }
        case .stickKnob, .stickBase: return e.label == "R" ? "stickR" : "stickL"
        default: return "default"
        }
    }

    private func make(_ s: PadShape, k: CGFloat) -> ((CGFloat) -> ShowcaseShape, CGFloat) {
        switch s {
        case .circle(let c, let r):
            let rr = r * k
            return ({ .circle(c, rr - $0) }, 2 * rr)
        case .roundedRect(let rect, _):
            let nr = CGRect(center: rect.center, size: CGSize(width: rect.width * k, height: rect.height * k))
            let cr = PadStyle.cornerRadius(width: nr.width, height: nr.height)
            return ({ .rect(nr.insetBy(dx: $0, dy: $0), max(cr - $0, 0)) }, min(nr.width, nr.height))
        }
    }

    private func bodyFill(_ id: String, lit: Bool, alpha: Double?) -> ShowcaseRGBA {
        if lit, let l = look.lit { return alpha == nil ? l : l.withAlpha(max(l.a * 0.95, alpha ?? 0)) }
        var f = colours.fill(id)
        f = f.withAlpha(alpha ?? colours.alpha(id, pressed: lit))
        if lit { f = f.isLight ? f.mixed(.black, 0.16) : f.mixed(.white, 0.18) }
        return f
    }

    private func ink(_ id: String, lit: Bool) -> ShowcaseRGBA {
        if lit, look.lit != nil { return look.litInk }
        return colours.glyph(id).legible(on: colours.fill(id).withAlpha(1), minimum: 3)
    }

    /// Body, outline, rim and shadow. The held state is smaller, filled differently, with the rim
    /// inverted and the shadow tightened, as in Showcase.
    @discardableResult
    private mutating func body(_ s: PadShape, id: String, lit: Bool, alpha: Double? = nil, fade k: Double = 1,
                               shadow: ShowcaseShadow = ShowcaseShadow(blur: 1.6, dy: 1.2, opacity: 0.30)) -> CGFloat {
        let (mk, minDim) = make(s, k: lit ? 0.95 : 1)
        let fill = bodyFill(id, lit: lit, alpha: alpha)
        let w = min(max(minDim * 0.03, 1), 1.8)
        put(ShowcasePrimitive(shape: mk(0), fill: .solid(fill), stroke: nil,
                              shadow: lit ? ShowcaseShadow(blur: 0.8, dy: 0.5, opacity: 0.18) : shadow), fade: k)
        put(ShowcasePrimitive(shape: mk(0.5), fill: nil, stroke: .solid(colours.outline.withAlpha(0.9)), strokeWidth: 1), fade: k)
        put(ShowcasePrimitive(shape: mk(1 + w / 2), fill: nil, stroke: sb.rim(fill.withAlpha(1), pressed: lit), strokeWidth: w), fade: k)
        return minDim
    }

    private mutating func text(_ s: String, at c: CGPoint, size: CGFloat, colour: ShowcaseRGBA, fade k: Double = 1) {
        put(ShowcasePrimitive(shape: .circle(c, 0), text: s, textSize: size, textColour: colour), fade: k)
    }

    private mutating func stroke(_ cmds: [ShowcasePathCommand], _ colour: ShowcaseRGBA, _ width: CGFloat) {
        out.append(ShowcasePrimitive(shape: .path(cmds), fill: nil, stroke: .solid(colour), strokeWidth: width))
    }

    // MARK: Elements

    mutating func add(_ e: RenderElement) {
        let box = e.shape.boundingBox
        let k: Double = e.ghost ? 0.5 : 1
        let id = Self.id(e)
        switch e.role {
        case .touchscreen:
            return

        case .zone:
            // A floating control's catchment: a faint plate, a hair brighter while a thumb is in it.
            let (mk, _) = make(e.shape, k: 1)
            let r = max(PadStyle.cornerRadius(width: box.width, height: box.height), 0)
            _ = mk
            let rect = CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height)
            out.append(ShowcasePrimitive(shape: .rect(rect, r), fill: .solid(look.tint.withAlpha(e.lit ? 0.14 : 0.07)),
                                         stroke: .solid(look.tint.withAlpha(e.lit ? 0.40 : 0.22)), strokeWidth: 1))

        case .area:
            let rect = box
            let r = PadStyle.cornerRadius(width: rect.width, height: rect.height)
            out.append(ShowcasePrimitive(shape: .rect(rect, r), fill: .solid(look.tint.withAlpha(e.lit ? 0.30 : 0.17)),
                                         stroke: .solid(look.tint.withAlpha(e.lit ? 0.70 : 0.45)), strokeWidth: 1))
            if !e.label.isEmpty {
                text(e.label, at: rect.center, size: PadStyle.TypeScale.hint + 2, colour: ShowcaseRGBA("#DCE7FF", 0.9))
            }

        case .pedal:
            body(e.shape, id: "dpad", lit: e.lit, alpha: e.lit ? 0.90 : 0.55)
            if !e.label.isEmpty {
                text(e.label, at: box.center, size: PadStyle.TypeScale.button(box.height), colour: ink("dpad", lit: e.lit))
            }

        case .face:
            body(e.shape, id: id, lit: e.lit, fade: k)
            text(e.label, at: box.center, size: PadStyle.TypeScale.button(box.height), colour: ink(id, lit: e.lit), fade: k)

        case .shoulder:
            body(e.shape, id: id, lit: e.lit, fade: k)
            text(e.label, at: box.center, size: PadStyle.TypeScale.button(box.height), colour: ink(id, lit: e.lit), fade: k)

        case .system:
            body(e.shape, id: id, lit: e.lit, fade: k)
            glyph(e, id: id)

        case .dpad:
            body(e.shape, id: "dpad", lit: e.lit, fade: k)
            arrow(e)

        case .dot:
            dimple(e)

        case .stickBase:
            guard case .circle(let c, let R) = e.shape else { return }
            let fill = bodyFill(id, lit: false, alpha: 1)
            let dish = look.dish ?? fill.withAlpha(0.42)
            let engaged = dish.withAlpha(min(1, dish.a * (e.lit ? 1.3 : 1)))
            put(ShowcasePrimitive(shape: .circle(c, R), fill: .solid(engaged)), fade: k)
            put(ShowcasePrimitive(shape: .circle(c, R - 0.5), fill: nil, stroke: .solid(colours.outline.withAlpha(0.8)), strokeWidth: 1), fade: k)
            let w = min(max(R * 0.04, 1), 1.8)
            put(ShowcasePrimitive(shape: .circle(c, R - 1 - w / 2), fill: nil,
                                  stroke: .vertical([ShowcaseStop(offset: 0, colour: ShowcaseRGBA.black.withAlpha(0.28)),
                                                     ShowcaseStop(offset: 0.5, colour: ShowcaseRGBA.black.withAlpha(0)),
                                                     ShowcaseStop(offset: 1, colour: ShowcaseRGBA.white.withAlpha(0.35))]),
                                  strokeWidth: w), fade: k)

        case .stickKnob:
            body(e.shape, id: id, lit: e.lit, fade: k, shadow: ShowcaseShadow(blur: 2.6, dy: 2, opacity: 0.34))
            if case .circle(let c, let r) = e.shape {
                put(ShowcasePrimitive(shape: .circle(c, r * 0.52), fill: nil,
                                      stroke: .solid(colours.glyph(id).withAlpha(0.28)), strokeWidth: 1), fade: k)
            }
            if !e.label.isEmpty {
                text(e.label, at: box.center, size: PadStyle.TypeScale.button(box.height * 0.8), colour: ink(id, lit: e.lit).withAlpha(0.9), fade: k)
            }

        case .guide, .handle:
            // Arc's own roles; the shared look is never applied to Arc.
            return
        }
    }

    /// The + / minus / HOME marks are drawn, not typed, so they are the same weight at every size.
    private mutating func glyph(_ e: RenderElement, id: String) {
        guard case .circle(let c, let r0) = e.shape else { return }
        let r = e.lit ? r0 * 0.95 : r0
        let colour = ink(id, lit: e.lit)
        let a = r * 0.36
        switch e.label {
        case "+":
            stroke([.move(CGPoint(x: c.x - a, y: c.y)), .line(CGPoint(x: c.x + a, y: c.y))], colour, r * 0.17)
            stroke([.move(CGPoint(x: c.x, y: c.y - a)), .line(CGPoint(x: c.x, y: c.y + a))], colour, r * 0.17)
        case "\u{2212}", "-":
            stroke([.move(CGPoint(x: c.x - a, y: c.y)), .line(CGPoint(x: c.x + a, y: c.y))], colour, r * 0.17)
        case "\u{2302}":
            let s = r * 0.52
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y + y * s - 0.04 * s) }
            out.append(ShowcasePrimitive(shape: .path([.move(p(-1, 0.05)), .line(p(0, -0.95)), .line(p(1, 0.05)), .line(p(0.72, 0.05)),
                                                       .line(p(0.72, 0.9)), .line(p(0.2, 0.9)), .line(p(0.2, 0.35)), .line(p(-0.2, 0.35)),
                                                       .line(p(-0.2, 0.9)), .line(p(-0.72, 0.9)), .line(p(-0.72, 0.05)), .close]),
                                         fill: .solid(colour)))
        default:
            // Racing's X (rear view) and C (recentre): a letter, on the same type scale.
            text(e.label, at: c, size: PadStyle.TypeScale.button(2 * r0), colour: colour)
        }
    }

    /// A d-pad arm's arrowhead: pointing out, quiet until held.
    private mutating func arrow(_ e: RenderElement) {
        let box = e.shape.boundingBox
        let c = box.center
        let (dx, dy): (CGFloat, CGFloat)
        switch e.label {
        case "\u{25B2}": (dx, dy) = (0, -1)
        case "\u{25BC}": (dx, dy) = (0, 1)
        case "\u{25C0}": (dx, dy) = (-1, 0)
        default: (dx, dy) = (1, 0)
        }
        let size = min(box.width, box.height)
        let s = size * 0.2
        let nx = -dy, ny = dx
        let mid = CGPoint(x: c.x + dx * size * 0.04, y: c.y + dy * size * 0.04)
        let apex = CGPoint(x: mid.x + dx * s, y: mid.y + dy * s)
        let p1 = CGPoint(x: mid.x - dx * s * 0.55 + nx * s * 1.1, y: mid.y - dy * s * 0.55 + ny * s * 1.1)
        let p2 = CGPoint(x: mid.x - dx * s * 0.55 - nx * s * 1.1, y: mid.y - dy * s * 0.55 - ny * s * 1.1)
        let colour = ink("dpad", lit: e.lit).withAlpha(e.lit ? 0.95 : 0.7)
        out.append(ShowcasePrimitive(shape: .path([.move(apex), .line(p1), .line(p2), .close]), fill: .solid(colour)))
    }

    /// L3 / R3 and the anchor dots: a shallow dimple, not a button.
    private mutating func dimple(_ e: RenderElement) {
        guard case .circle(let c, let r) = e.shape else { return }
        let base = colours.fill("dpad").withAlpha(1)
        let tone = e.lit ? (base.isLight ? base.mixed(.black, 0.26) : base.mixed(.white, 0.28))
                         : (base.isLight ? base.mixed(.black, 0.12) : base.mixed(.white, 0.10))
        out.append(ShowcasePrimitive(shape: .circle(c, r), fill: .solid(tone.withAlpha(0.9))))
        out.append(ShowcasePrimitive(shape: .circle(c, max(r - 0.5, 0)), fill: nil,
                                     stroke: .vertical([ShowcaseStop(offset: 0, colour: ShowcaseRGBA.black.withAlpha(0.20)),
                                                        ShowcaseStop(offset: 0.5, colour: ShowcaseRGBA.black.withAlpha(0)),
                                                        ShowcaseStop(offset: 1, colour: ShowcaseRGBA.white.withAlpha(base.isLight ? 0.55 : 0.18))]),
                                     strokeWidth: 1))
        if !e.label.isEmpty {
            text(e.label, at: c, size: PadStyle.TypeScale.tag(2 * r), colour: ink("dpad", lit: false).withAlpha(0.85))
        }
    }
}
