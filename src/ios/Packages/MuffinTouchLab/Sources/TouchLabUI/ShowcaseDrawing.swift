#if canImport(UIKit)
import TouchLabCore
import UIKit

/// Draws a `ShowcaseScene` (the Showcase look as data) with CoreGraphics: shadow, body, rim,
/// dish and octagonal gate exactly as the scene lists them. A dumb loop over the primitives.
enum ShowcaseDrawing {
    static func draw(_ scene: ShowcaseScene, in g: CGContext, opacity: CGFloat) {
        // The scene's own opacity at the default; the shared opacity setting scales it.
        let alpha = min(1, CGFloat(scene.opacity) * opacity / PadSettings.defaultOpacity)
        g.saveGState()
        g.setAlpha(alpha)
        g.beginTransparencyLayer(auxiliaryInfo: nil)
        for p in scene.primitives { draw(p, in: g) }
        g.endTransparencyLayer()
        g.restoreGState()
    }

    private static func colour(_ c: ShowcaseRGBA) -> CGColor {
        CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    private static func path(_ shape: ShowcaseShape) -> CGPath {
        switch shape {
        case .circle(let c, let r):
            return CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
        case .rect(let rect, let radius):
            let r = min(radius, min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .path(let commands):
            let p = CGMutablePath()
            for c in commands {
                switch c {
                case .move(let a): p.move(to: a)
                case .line(let a): p.addLine(to: a)
                case .quad(let to, let control): p.addQuadCurve(to: to, control: control)
                case .close: p.closeSubpath()
                }
            }
            return p
        }
    }

    private static func fill(_ paint: ShowcasePaint, _ path: CGPath, in g: CGContext) {
        switch paint {
        case .solid(let c):
            g.addPath(path); g.setFillColor(colour(c)); g.fillPath()
        case .vertical(let stops):
            guard let first = stops.first else { return }
            let box = path.boundingBox
            let space = CGColorSpaceCreateDeviceRGB()
            guard stops.count > 1,
                  let gradient = CGGradient(colorsSpace: space, colors: stops.map { colour($0.colour) } as CFArray,
                                            locations: stops.map { CGFloat($0.offset) }) else {
                g.addPath(path); g.setFillColor(colour(first.colour)); g.fillPath(); return
            }
            g.saveGState()
            g.addPath(path); g.clip()
            g.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
            g.restoreGState()
        }
    }

    private static func stroke(_ paint: ShowcasePaint, width: CGFloat, _ path: CGPath, in g: CGContext) {
        guard width > 0 else { return }
        g.saveGState()
        g.addPath(path)
        g.setLineWidth(width)
        g.replacePathWithStrokedPath()
        let outline = g.path
        g.clip()
        if let outline { fill(paint, outline, in: g) }
        g.restoreGState()
    }

    private static func draw(_ p: ShowcasePrimitive, in g: CGContext) {
        let shape = path(p.shape)
        if let f = p.fill {
            if let s = p.shadow {
                // The shadow comes from a solid copy of the body, so a gradient body casts the same one.
                g.saveGState()
                g.setShadow(offset: CGSize(width: 0, height: s.dy), blur: s.blur, color: CGColor(gray: 0, alpha: CGFloat(s.opacity)))
                switch f {
                case .solid(let c): g.setFillColor(colour(c))
                case .vertical(let stops): g.setFillColor(colour(stops.first?.colour ?? ShowcaseRGBA(r: 0, g: 0, b: 0)))
                }
                g.addPath(shape); g.fillPath()
                g.restoreGState()
            }
            fill(f, shape, in: g)
        }
        if let s = p.stroke { stroke(s, width: p.strokeWidth, shape, in: g) }
        if let text = p.text, let c = p.textColour, p.textSize > 0 {
            let box = shape.boundingBox
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: p.textSize, weight: .semibold),
                .foregroundColor: UIColor(cgColor: colour(c)),
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            UIGraphicsPushContext(g)
            (text as NSString).draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attrs)
            UIGraphicsPopContext()
        }
    }
}
#endif
