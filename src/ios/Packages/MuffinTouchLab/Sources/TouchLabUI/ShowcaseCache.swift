#if canImport(UIKit)
import TouchLabCore
import UIKit

/// The still part of a Showcase scene, rasterised once into a bitmap and patched in place.
///
/// Drawing the whole scene is the expensive thing: every control carries a blurred shadow and
/// a gradient rim. A stick drag changes only the knob, so the pad keeps `base` here and, per
/// frame, composites it with the knobs over a small dirty rect. When the base itself changes
/// (a button easing, a layout move, a colour), only the primitives that differ are redrawn,
/// inside the rect they cover. The result is the same picture the scene lists: the bitmap holds
/// the group at full opacity, and `composite` lays the pad's opacity over base and knobs together,
/// exactly as `ShowcaseDrawing.draw` does for a whole scene.
final class ShowcaseCache {
    private var base: [ShowcasePrimitive] = []
    private var bitmap: CGContext?
    private var size: CGSize = .zero
    private var scale: CGFloat = 0
    private var snapshot: CGImage?

    /// Whether the bitmap was made for this size and screen scale.
    func matches(size s: CGSize, scale k: CGFloat) -> Bool { bitmap != nil && size == s && scale == k }

    func reset() {
        base = []
        bitmap = nil
        snapshot = nil
        size = .zero
    }

    /// Brings the bitmap to `next`. Returns the area (view coordinates) whose pixels changed:
    /// nil when nothing did, `.infinite` when all of it did.
    func update(_ next: [ShowcasePrimitive], size newSize: CGSize, scale newScale: CGFloat) -> CGRect? {
        guard newSize.width >= 1, newSize.height >= 1, newScale > 0 else { reset(); return .infinite }
        if bitmap == nil || newSize != size || newScale != scale {
            let w = Int((newSize.width * newScale).rounded(.up)), h = Int((newSize.height * newScale).rounded(.up))
            guard let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { reset(); return .infinite }
            // The bitmap is addressed like a view: points, origin top left.
            g.translateBy(x: 0, y: CGFloat(h))
            g.scaleBy(x: newScale, y: -newScale)
            bitmap = g
            size = newSize
            scale = newScale
            base = []
            render(next, only: nil)
            base = next
            snapshot = nil
            return .infinite
        }
        // Equal head and tail are untouched; what lies between them changed.
        var head = 0
        while head < base.count, head < next.count, base[head] == next[head] { head += 1 }
        var tail = 0
        while tail < base.count - head, tail < next.count - head,
              base[base.count - 1 - tail] == next[next.count - 1 - tail] { tail += 1 }
        if head == base.count, head == next.count { return nil }
        var dirty = CGRect.null
        for p in base[head..<(base.count - tail)] { dirty = dirty.union(p.bounds) }
        for p in next[head..<(next.count - tail)] { dirty = dirty.union(p.bounds) }
        base = next
        snapshot = nil
        guard !dirty.isNull else { return nil }
        // Whole device pixels, inside the view.
        dirty = dirty.intersection(CGRect(origin: .zero, size: size))
        guard !dirty.isNull, dirty.width > 0, dirty.height > 0 else { return nil }
        let px = scale
        let x0 = floor(dirty.minX * px) / px, y0 = floor(dirty.minY * px) / px
        let x1 = ceil(dirty.maxX * px) / px, y1 = ceil(dirty.maxY * px) / px
        dirty = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        render(next, only: dirty)
        return dirty
    }

    /// Draws `prims` into the bitmap; with `only`, just that area: cleared, then every primitive that reaches it.
    private func render(_ prims: [ShowcasePrimitive], only area: CGRect?) {
        guard let g = bitmap else { return }
        g.saveGState()
        if let area {
            g.clip(to: area)
            g.clear(area)
        }
        for p in prims where area == nil || p.bounds.intersects(area!) { ShowcaseDrawing.draw(p, in: g) }
        g.restoreGState()
    }

    /// Lays the cached base and the moving `knobs` into the view's context at the pad's opacity.
    func composite(knobs: [ShowcasePrimitive], opacity: Double, in g: CGContext) {
        guard let bitmap else { return }
        if snapshot == nil { snapshot = bitmap.makeImage() }
        let alpha = min(1, max(0, CGFloat(opacity)))
        g.saveGState()
        g.setAlpha(alpha)
        g.beginTransparencyLayer(auxiliaryInfo: nil)
        if let snapshot {
            // Exactly the bitmap's own pixels, so nothing is resampled.
            let drawn = CGSize(width: CGFloat(snapshot.width) / scale, height: CGFloat(snapshot.height) / scale)
            UIImage(cgImage: snapshot, scale: scale, orientation: .up).draw(in: CGRect(origin: .zero, size: drawn))
        }
        for p in knobs { ShowcaseDrawing.draw(p, in: g) }
        g.endTransparencyLayer()
        g.restoreGState()
    }
}
#endif
