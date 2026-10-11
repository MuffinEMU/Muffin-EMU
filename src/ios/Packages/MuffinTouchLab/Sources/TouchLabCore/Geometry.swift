import CoreGraphics
import Foundation

extension CGPoint {
    public static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }

    public var length: CGFloat { (x * x + y * y).squareRoot() }

    public func distance(to other: CGPoint) -> CGFloat { (self - other).length }

    /// Angle in view coordinates (+y down), radians, 0 = right, counter-clockwise ON SCREEN
    /// is positive. i.e. "up" on screen is +pi/2 - the y flip is folded in here so every
    /// direction test in the package reads the way it looks.
    public var screenAngle: CGFloat { atan2(-y, x) }

    public func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, rect.minX), rect.maxX), y: min(max(y, rect.minY), rect.maxY))
    }
}

extension CGRect {
    public var center: CGPoint { CGPoint(x: midX, y: midY) }

    public init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2,
                  width: size.width, height: size.height)
    }
}

/// A control's touch-and-draw outline.
public enum PadShape: Equatable, Sendable {
    case circle(center: CGPoint, radius: CGFloat)
    case roundedRect(CGRect, cornerRadius: CGFloat)

    public var center: CGPoint {
        switch self {
        case .circle(let c, _): return c
        case .roundedRect(let r, _): return r.center
        }
    }

    public var boundingBox: CGRect {
        switch self {
        case .circle(let c, let r): return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        case .roundedRect(let rect, _): return rect
        }
    }

    /// Distance from `p` to the shape's EDGE; zero or negative inside. This, not distance
    /// to centre, is what catchment compares - otherwise a big shoulder loses a touch on
    /// its own corner to a small button whose centre happens to be nearer.
    public func edgeDistance(to p: CGPoint) -> CGFloat {
        switch self {
        case .circle(let c, let r):
            return p.distance(to: c) - r
        case .roundedRect(let rect, let cr):
            let r = min(cr, min(rect.width, rect.height) / 2)
            let inner = rect.insetBy(dx: r, dy: r)
            let dx = max(inner.minX - p.x, 0, p.x - inner.maxX)
            let dy = max(inner.minY - p.y, 0, p.y - inner.maxY)
            if dx == 0 && dy == 0 {
                // Inside the inner rect: negative distance to the nearest outer edge.
                let toEdge = min(p.x - rect.minX, rect.maxX - p.x, p.y - rect.minY, rect.maxY - p.y)
                return -toEdge
            }
            return (dx * dx + dy * dy).squareRoot() - r
        }
    }

    public func contains(_ p: CGPoint) -> Bool { edgeDistance(to: p) <= 0 }

    public func offset(by d: CGPoint) -> PadShape {
        switch self {
        case .circle(let c, let r): return .circle(center: c + d, radius: r)
        case .roundedRect(let rect, let cr): return .roundedRect(rect.offsetBy(dx: d.x, dy: d.y), cornerRadius: cr)
        }
    }

    /// Conservative overlap test used by the layout checks: exact for circle/circle,
    /// box-based otherwise.
    public func overlaps(_ other: PadShape, margin: CGFloat = 0) -> Bool {
        switch (self, other) {
        case let (.circle(c1, r1), .circle(c2, r2)):
            return c1.distance(to: c2) < r1 + r2 - margin
        default:
            // Circle vs rect: distance from the circle centre to the rect edge.
            if case let .circle(c, r) = self { return other.edgeDistance(to: c) < r - margin }
            if case let .circle(c, r) = other { return self.edgeDistance(to: c) < r - margin }
            return boundingBox.insetBy(dx: margin / 2, dy: margin / 2)
                .intersects(other.boundingBox.insetBy(dx: margin / 2, dy: margin / 2))
        }
    }
}

/// Where the pad is being drawn, in view points (+y down).
public struct LayoutContext: Equatable, Sendable {
    public var size: CGSize
    /// Safe-area insets; controls stay inside them.
    public var safeInsets: Insets
    /// Rects the game video occupies. Schemes that fit themselves to the margins
    /// (FramePad) read this; the others draw over it.
    public var videoRects: [CGRect]
    /// Where the GamePad image is on screen. A touch there that no control claims becomes a
    /// GamePad-touchscreen touch. nil = no passthrough.
    public var touchscreenRect: CGRect?
    /// User size multiplier on top of the automatic button size.
    public var scale: CGFloat
    /// Stick feel.
    public var stick: StickTuning
    /// The player's own reach and rest on each stick (see `StickCalibration`).
    public var calibration: StickCalibrations
    /// How far off a button a touch still counts. nil = each control's own reach.
    public var tolerance: PadTolerance?
    /// Moves each stick sideways from where the layout puts it, in button widths: positive
    /// toward its screen edge, negative toward the middle. A hand-size setting. Layouts
    /// with fixed sticks honour as much of it as fits without overlapping anything.
    public var stickSpacing: CGFloat
    /// Moves the whole shoulder cluster (L, R, ZL, ZR) down from where the layout puts it,
    /// in button widths, keeping the four buttons' layout relative to each other. Zero is
    /// the layout's own place; negative values are ignored, because the shoulders already
    /// start against the top of the safe area. The layouts that place the shoulders
    /// themselves honour as much of it as fits without leaving the safe area or touching
    /// a stick, d-pad or face button. A hand-size setting, meant for iPad.
    public var shoulderOffset: CGFloat
    /// The polished "Showcase style" look (see `PadStyle`, and Arc's own refined look). Off draws the
    /// flat look the schemes had before it. Drawing only: no layout or input depends on it.
    public var showcaseStyle: Bool

    public init(size: CGSize,
                safeInsets: Insets = .zero,
                videoRects: [CGRect] = [],
                touchscreenRect: CGRect? = nil,
                scale: CGFloat = 1,
                stick: StickTuning = StickTuning(),
                stickSpacing: CGFloat = 0,
                shoulderOffset: CGFloat = 0,
                calibration: StickCalibrations = StickCalibrations(),
                tolerance: PadTolerance? = nil,
                showcaseStyle: Bool = true) {
        self.showcaseStyle = showcaseStyle
        self.size = size
        self.safeInsets = safeInsets
        self.videoRects = videoRects
        self.touchscreenRect = touchscreenRect
        self.scale = scale
        self.stick = stick
        self.calibration = calibration
        self.tolerance = tolerance
        self.stickSpacing = stickSpacing
        self.shoulderOffset = shoulderOffset
    }

    /// The context a pad with these settings is laid out in.
    public init(size: CGSize, safeInsets: Insets = .zero, videoRects: [CGRect] = [],
                touchscreenRect: CGRect? = nil, settings: PadSettings) {
        self.init(size: size, safeInsets: safeInsets, videoRects: videoRects, touchscreenRect: touchscreenRect,
                  scale: settings.scale, stick: settings.stick, stickSpacing: settings.stickSpacing,
                  shoulderOffset: settings.shoulderOffset, calibration: settings.calibration,
                  tolerance: settings.tolerance, showcaseStyle: settings.showcaseStyle)
    }

    public var bounds: CGRect { CGRect(origin: .zero, size: size) }

    public var safeBounds: CGRect {
        CGRect(x: safeInsets.left, y: safeInsets.top,
               width: size.width - safeInsets.left - safeInsets.right,
               height: size.height - safeInsets.top - safeInsets.bottom)
    }

    /// One face-button diameter, in points. Same rule the shipping Muffin pad uses
    /// (ControllerGeometry.automaticDiameter): track the short side, clamp to thumb size,
    /// so a phone and a 13" iPad both get buttons a thumb can find.
    public var unit: CGFloat {
        let shortSide = min(size.width, size.height)
        return min(max(shortSide * 0.115, 46), 72) * scale
    }
}

public struct Insets: Equatable, Sendable {
    public var top, left, bottom, right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static let zero = Insets()
}

public enum PadScreenGeometry {
    /// The largest rect of the given aspect ratio (width / height) centred in `rect`.
    public static func aspectFit(_ aspect: CGFloat, in rect: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0, aspect > 0 else { return rect }
        var w = rect.width, h = w / aspect
        if h > rect.height { h = rect.height; w = h * aspect }
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
