import CoreGraphics
import Foundation

/// Renders a render list as SVG, for the previews and for eyeballing layout checks. Not
/// used on device - TouchPadView draws the same list with UIKit.
public enum SVGRenderer {
    public static func svg(size: CGSize, videoRects: [CGRect], safe: CGRect, title: String,
                           elements: [RenderElement]) -> String {
        var s = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(size.width))" height="\(Int(size.height))" \
        viewBox="0 0 \(n(size.width)) \(n(size.height))" font-family="-apple-system, Helvetica, sans-serif">
        <rect width="100%" height="100%" fill="#101014"/>
        <rect x="\(n(safe.minX))" y="\(n(safe.minY))" width="\(n(safe.width))" height="\(n(safe.height))" \
        fill="none" stroke="#2a2a33" stroke-dasharray="6 6"/>

        """
        for (i, r) in videoRects.enumerated() {
            s += "<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" fill=\"#23324a\"/>\n"
            let label = videoRects.count == 2 ? (i == 0 ? "TV" : "GamePad") : "GamePad"
            s += "<text x=\"\(n(r.midX))\" y=\"\(n(r.midY))\" fill=\"#4d6690\" font-size=\"22\" text-anchor=\"middle\">\(label)</text>\n"
        }
        if elements.contains(where: { $0.style == .refined }) {
            s += """
            <defs>
            <filter id="rs" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="1.5" stdDeviation="2.5" flood-color="#000" flood-opacity="0.4"/></filter>
            <filter id="rsl" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="0.5" stdDeviation="1" flood-color="#000" flood-opacity="0.3"/></filter>
            </defs>

            """
        }
        for e in elements { s += element(e) }
        s += "<text x=\"12\" y=\"\(n(size.height - 10))\" fill=\"#8888a0\" font-size=\"13\">\(escape(title))</text>\n"
        s += "</svg>\n"
        return s
    }

    static func element(_ e: RenderElement) -> String {
        if e.role == .guide { return guide(e) }
        if e.style == .refined { return refined(e) }
        let (fill, stroke, text) = colours(e)
        let opacity = e.ghost ? (e.role == .zone || e.role == .touchscreen ? 0.12 : 0.3)
            : (e.role == .area ? (e.lit ? 0.35 : 0.22) : (e.role == .pedal ? (e.lit ? 0.85 : 0.5) : 0.9))
        var out = ""
        let fillAttr = e.role == .touchscreen ? "none" : fill
        switch e.shape {
        case .circle(let c, let r):
            out += "<circle cx=\"\(n(c.x))\" cy=\"\(n(c.y))\" r=\"\(n(r))\" fill=\"\(fillAttr)\" stroke=\"\(stroke)\" stroke-width=\"1.5\" opacity=\"\(opacity)\"/>\n"
        case .roundedRect(let rect, let cr):
            out += "<rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\" width=\"\(n(rect.width))\" height=\"\(n(rect.height))\" rx=\"\(n(cr))\" fill=\"\(fillAttr)\" stroke=\"\(stroke)\" stroke-width=\"1.5\" opacity=\"\(opacity)\"/>\n"
        }
        if !e.label.isEmpty, e.role != .zone || e.ghost {
            let box = e.shape.boundingBox
            let size = max(min(box.height * 0.42, 26), 10)
            out += "<text x=\"\(n(box.midX))\" y=\"\(n(box.midY + size * 0.36))\" fill=\"\(text)\" font-size=\"\(n(size))\" font-weight=\"600\" text-anchor=\"middle\" opacity=\"\(e.ghost ? 0.5 : 1)\">\(escape(e.label))</text>\n"
        }
        return out
    }

    static func colours(_ e: RenderElement) -> (String, String, String) {
        if e.lit && e.role != .zone && e.role != .touchscreen && e.role != .area { return ("#ffc93c", "#fff1c1", "#2a2000") }
        switch e.role {
        case .face: return ("#e9e9ef", "#ffffff", "#24242c")
        case .dpad: return ("#c9c9d2", "#ededf3", "#24242c")
        case .shoulder: return ("#8d8d99", "#b5b5c0", "#111116")
        case .system: return ("#6e6e7a", "#9a9aa6", "#f2f2f6")
        case .dot: return ("#55555f", "#8a8a96", "#e0e0e8")
        case .stickBase: return ("#3a3a44", "#6a6a76", "#c0c0cc")
        case .stickKnob: return ("#b8b8c4", "#e0e0ea", "#24242c")
        case .zone: return (e.lit ? "#ffc93c" : "#7fa8ff", "#7fa8ff", "#7fa8ff")
        case .area: return (e.lit ? "#ffc93c" : "#7fa8ff", "#9bbcff", "#c4d6ff")
        case .pedal: return ("#d9d9e2", "#ffffff", "#24242c")
        case .touchscreen: return ("none", e.lit ? "#ffc93c" : "#4d6690", "#4d6690")
        case .guide: return ("none", "#ffffff", "#ffffff")
        case .handle: return ("#5ac8fa", "#5ac8fa", "#ffffff")
        }
    }

    static func guide(_ e: RenderElement) -> String {
        guard e.path.count > 1 else { return "" }
        let c = RefinedLook.tone(e.tone)
        let alpha = (e.ghost ? 0.28 : (e.lit ? 0.9 : 0.6)) * Double(e.fade)
        let pts = e.path.map { "\(n($0.x)),\(n($0.y))" }.joined(separator: " ")
        let dash = e.dash > 0 ? " stroke-dasharray=\"\(n(e.dash)) \(n(e.dash * 1.4))\"" : ""
        return "<polyline points=\"\(pts)\" fill=\"none\" stroke=\"\(c.css)\" stroke-opacity=\"\(String(format: "%.2f", alpha))\" stroke-width=\"\(n(max(e.width, 1)))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dash)/>\n"
    }

    /// Arc's look: hairline outline, soft shadow, a rim lit from above, a held state that sinks.
    static func refined(_ e: RenderElement) -> String {
        let look = RefinedLook.of(e)
        let opacity = (e.ghost ? 0.3 : 1) * Double(e.fade)
        let box = e.shape.boundingBox
        let id = "g\(Int(box.midX * 10))_\(Int(box.midY * 10))_\(Int(box.width))"
        var out = ""
        func op(_ c: LookRGBA) -> String { String(format: "%.2f", c.a) }
        let k = look.scale
        var shape = ""
        func geometry(inset: CGFloat) -> String {
            switch e.shape {
            case .circle(let c, let r):
                return "cx=\"\(n(c.x))\" cy=\"\(n(c.y))\" r=\"\(n(max(r * k - inset, 0.5)))\""
            case .roundedRect(let rect, let cr):
                let w = rect.width * k - 2 * inset, h = rect.height * k - 2 * inset
                return "x=\"\(n(rect.midX - w / 2))\" y=\"\(n(rect.midY - h / 2))\" width=\"\(n(w))\" height=\"\(n(h))\" rx=\"\(n(max(min(cr * k, min(w, h) / 2), 0)))\""
            }
        }
        let tag: String
        if case .circle = e.shape { tag = "circle" } else { tag = "rect" }
        shape = "<\(tag) \(geometry(inset: 0)) fill=\"\(look.body.css)\" fill-opacity=\"\(op(look.body))\" stroke=\"\(look.outline.css)\" stroke-opacity=\"\(op(look.outline))\" stroke-width=\"\(n(look.outlineWidth))\" filter=\"url(#\(e.lit ? "rsl" : "rs"))\"/>\n"
        out += "<g opacity=\"\(String(format: "%.2f", opacity))\">\n" + shape
        if look.rim.a > 0.01 {
            let top = look.rim
            out += "<linearGradient id=\"\(id)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(top.css)\" stop-opacity=\"\(op(top))\"/><stop offset=\"0.55\" stop-color=\"\(top.css)\" stop-opacity=\"0\"/></linearGradient>\n"
            out += "<\(tag) \(geometry(inset: 1.4)) fill=\"none\" stroke=\"url(#\(id))\" stroke-width=\"1\"/>\n"
        }
        if !e.label.isEmpty, e.role != .stickBase {
            let size = RefinedLook.labelSize(for: box)
            let halo = look.text.luminance < 0.5 ? "#ffffff" : "#000000"
            out += "<text x=\"\(n(box.midX))\" y=\"\(n(box.midY + size * 0.36))\" fill=\"\(look.text.css)\" font-size=\"\(n(size))\" font-weight=\"600\" text-anchor=\"middle\" stroke=\"\(halo)\" stroke-opacity=\"0.35\" stroke-width=\"2\" paint-order=\"stroke\">\(escape(e.label))</text>\n"
        }
        return out + "</g>\n"
    }

    static func n(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
