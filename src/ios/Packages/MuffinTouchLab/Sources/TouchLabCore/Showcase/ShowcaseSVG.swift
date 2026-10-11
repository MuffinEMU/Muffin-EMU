import CoreGraphics
import Foundation

/// Writes a `ShowcaseScene` as SVG, inside the same frame (safe-area dashes, picture
/// rects, caption) the other schemes' previews use. Not used on device.
public enum ShowcaseSVG {
    public enum Backdrop: Sendable { case dark, light }

    public static func svg(scene: ShowcaseScene, videoRects: [CGRect], safe: CGRect, title: String,
                           backdrop: Backdrop = .dark) -> String {
        let size = scene.size
        let (bg, dash, video, videoText, caption) = backdrop == .dark
            ? ("#101014", "#2a2a33", "#23324a", "#4d6690", "#8888a0")
            : ("#eef1f6", "#c5cbd8", "#d6dfee", "#8da0c0", "#6b7385")
        var defs = ""
        var body = ""
        var ids = 0
        var filters: [String: String] = [:]

        func filter(_ sh: ShowcaseShadow) -> String {
            let key = "\(sh.blur)/\(sh.dy)/\(sh.opacity)"
            if let id = filters[key] { return id }
            let id = "sh\(filters.count)"
            filters[key] = id
            defs += "<filter id=\"\(id)\" x=\"-40%\" y=\"-40%\" width=\"180%\" height=\"190%\" color-interpolation-filters=\"sRGB\">"
                + "<feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"\(n(sh.blur / 2))\"/><feOffset dy=\"\(n(sh.dy))\" result=\"o\"/>"
                + "<feComponentTransfer><feFuncA type=\"linear\" slope=\"\(n(CGFloat(sh.opacity)))\"/></feComponentTransfer>"
                + "<feMerge><feMergeNode/><feMergeNode in=\"SourceGraphic\"/></feMerge></filter>\n"
            return id
        }
        func paint(_ p: ShowcasePaint) -> (String, String) {
            switch p {
            case .solid(let c):
                return ("#" + hex(c), c.a < 1 ? " opacity" : "")
            case .vertical(let stops):
                ids += 1
                let id = "g\(ids)"
                defs += "<linearGradient id=\"\(id)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
                    + stops.map { "<stop offset=\"\(n(CGFloat($0.offset)))\" stop-color=\"#\(hex($0.colour))\" stop-opacity=\"\(f($0.colour.a))\"/>" }.joined()
                    + "</linearGradient>\n"
                return ("url(#\(id))", "")
            }
        }
        func attrs(_ p: ShowcasePrimitive) -> String {
            var a = ""
            if let fill = p.fill {
                let (v, _) = paint(fill)
                a += " fill=\"\(v)\""
                if case .solid(let c) = fill, c.a < 1 { a += " fill-opacity=\"\(f(c.a))\"" }
            } else { a += " fill=\"none\"" }
            if let stroke = p.stroke {
                let (v, _) = paint(stroke)
                a += " stroke=\"\(v)\" stroke-width=\"\(n(p.strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
                if case .solid(let c) = stroke, c.a < 1 { a += " stroke-opacity=\"\(f(c.a))\"" }
            }
            if let sh = p.shadow { a += " filter=\"url(#\(filter(sh)))\"" }
            return a
        }

        for p in scene.primitives {
            if let text = p.text {
                let c = p.shape.centre
                let col = p.textColour ?? .black
                body += "<text x=\"\(n(c.x))\" y=\"\(n(c.y + p.textSize * 0.36))\" fill=\"#\(hex(col))\" font-size=\"\(n(p.textSize))\" "
                    + "font-weight=\"600\" text-anchor=\"middle\"\(col.a < 1 ? " fill-opacity=\"\(f(col.a))\"" : "")>\(escape(text))</text>\n"
                continue
            }
            switch p.shape {
            case .circle(let c, let r):
                body += "<circle cx=\"\(n(c.x))\" cy=\"\(n(c.y))\" r=\"\(n(r))\"\(attrs(p))/>\n"
            case .rect(let r, let cr):
                body += "<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" rx=\"\(n(cr))\"\(attrs(p))/>\n"
            case .path(let cmds):
                body += "<path d=\"\(d(cmds))\"\(attrs(p))/>\n"
            }
        }

        var s = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(size.width))" height="\(Int(size.height))" \
        viewBox="0 0 \(n(size.width)) \(n(size.height))" font-family="-apple-system, Helvetica, sans-serif">
        <defs>
        \(defs)</defs>
        <rect width="100%" height="100%" fill="\(bg)"/>
        <rect x="\(n(safe.minX))" y="\(n(safe.minY))" width="\(n(safe.width))" height="\(n(safe.height))" fill="none" stroke="\(dash)" stroke-dasharray="6 6"/>

        """
        for (i, r) in videoRects.enumerated() {
            s += "<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" fill=\"\(video)\"/>\n"
            let label = videoRects.count == 2 ? (i == 0 ? "TV" : "GamePad") : "GamePad"
            s += "<text x=\"\(n(r.midX))\" y=\"\(n(r.midY))\" fill=\"\(videoText)\" font-size=\"22\" text-anchor=\"middle\">\(label)</text>\n"
        }
        s += "<g opacity=\"\(f(scene.opacity))\">\n\(body)</g>\n"
        s += "<text x=\"12\" y=\"\(n(size.height - 10))\" fill=\"\(caption)\" font-size=\"13\">\(escape(title))</text>\n</svg>\n"
        return s
    }

    private static func d(_ cmds: [ShowcasePathCommand]) -> String {
        cmds.map { c -> String in
            switch c {
            case .move(let p): return "M\(n(p.x)) \(n(p.y))"
            case .line(let p): return "L\(n(p.x)) \(n(p.y))"
            case .quad(let c, let p): return "Q\(n(c.x)) \(n(c.y)) \(n(p.x)) \(n(p.y))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    private static func hex(_ c: ShowcaseRGBA) -> String {
        func b(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", b(c.r), b(c.g), b(c.b))
    }
    private static func n(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }
    private static func f(_ v: Double) -> String { String(format: "%.3f", v) }
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}

extension ShowcaseShape {
    var centre: CGPoint {
        switch self {
        case .circle(let c, _): return c
        case .rect(let r, _): return r.center
        case .path: return .zero
        }
    }
}
