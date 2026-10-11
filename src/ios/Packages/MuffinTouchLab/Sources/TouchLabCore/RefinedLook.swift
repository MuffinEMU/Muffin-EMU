import CoreGraphics
import Foundation

/// An RGBA colour, platform-free, so the SVG previews and the UIKit drawer read the same numbers.
public struct LookRGBA: Equatable, Sendable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public init(white: Double, _ a: Double = 1) { self.init(white, white, white, a) }

    public func withAlpha(_ alpha: Double) -> LookRGBA { LookRGBA(r, g, b, alpha) }
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// "rgb(...)" for SVG; opacity is returned separately by the caller.
    var css: String { "rgb(\(Int((r * 255).rounded())),\(Int((g * 255).rounded())),\(Int((b * 255).rounded())))" }
}

/// Arc's control recipe, the same for every control so the pad reads as one object (the recipe
/// Showcase uses): a flat body, a hairline outline, a soft drop shadow, a thin rim lit from
/// above, and a held state that sinks. Radii are consistent: round buttons are circles,
/// everything rectangular is a pill.
public struct RefinedLook: Equatable, Sendable {
    public var body: LookRGBA
    public var outline: LookRGBA
    /// Rim stroked just inside the top edge.
    public var rim: LookRGBA
    public var text: LookRGBA
    public var shadowBlur: CGFloat
    public var shadowDY: CGFloat
    public var shadowOpacity: Double
    /// Scale of the body about its centre (a held button sinks).
    public var scale: CGFloat
    public var outlineWidth: CGFloat

    public static let accent = LookRGBA(0.35, 0.78, 0.98)
    public static let good = LookRGBA(0.38, 0.85, 0.55)
    public static let warn = LookRGBA(1.0, 0.70, 0.25)
    public static let lit = LookRGBA(1.0, 0.79, 0.24)

    public static func tone(_ t: RenderElement.Tone) -> LookRGBA {
        switch t {
        case .neutral: return LookRGBA(white: 1)
        case .accent: return accent
        case .good: return good
        case .warn: return warn
        }
    }

    /// Smallest label drawn on a refined control, in points.
    public static let minimumLabelSize: CGFloat = 12

    public static func labelSize(for box: CGRect) -> CGFloat {
        max(min(box.height * 0.46, 26), minimumLabelSize)
    }

    public static func of(_ e: RenderElement) -> RefinedLook {
        func dark(_ white: Double, _ a: Double, text: LookRGBA) -> RefinedLook {
            RefinedLook(body: LookRGBA(white: white, a), outline: LookRGBA(white: 1, 0.42), rim: LookRGBA(white: 1, 0.22),
                        text: text, shadowBlur: 5, shadowDY: 1.5, shadowOpacity: 0.40, scale: 1, outlineWidth: 0.75)
        }
        func light(_ white: Double, _ a: Double) -> RefinedLook {
            RefinedLook(body: LookRGBA(white: white, a), outline: LookRGBA(white: 0, 0.30), rim: LookRGBA(white: 1, 0.65),
                        text: LookRGBA(white: 0.09), shadowBlur: 5, shadowDY: 1.5, shadowOpacity: 0.40, scale: 1, outlineWidth: 0.75)
        }
        var look: RefinedLook
        switch e.role {
        case .face: look = light(0.94, 0.90)
        case .dpad: look = light(0.85, 0.90)
        case .shoulder: look = light(0.66, 0.88)
        case .system: look = dark(0.20, 0.88, text: LookRGBA(white: 1))
        case .stickBase:
            look = dark(0.10, 0.50, text: LookRGBA(white: 1))
            look.shadowOpacity = 0.20
        case .stickKnob: look = light(0.80, 0.94)
        case .handle:
            look = RefinedLook(body: accent.withAlpha(0.20), outline: accent.withAlpha(0.95), rim: LookRGBA(white: 1, 0.0),
                               text: LookRGBA(white: 1), shadowBlur: 4, shadowDY: 1, shadowOpacity: 0.35, scale: 1, outlineWidth: 1.5)
        default: look = dark(0.30, 0.8, text: LookRGBA(white: 1))
        }
        if e.lit, e.role != .stickBase, e.role != .handle {
            // Held: sinks 5%, the shadow tightens, the rim inverts to a shade.
            look.body = lit
            look.outline = LookRGBA(white: 1, 0.9)
            look.rim = LookRGBA(white: 0, 0.20)
            look.text = LookRGBA(0.14, 0.10, 0.0)
            look.shadowBlur = 2
            look.shadowDY = 0.5
            look.shadowOpacity = 0.30
            look.scale = 0.95
        } else if e.lit, e.role == .stickBase {
            look.outline = LookRGBA(white: 1, 0.7)
        }
        if e.role == .system, e.tone != .neutral {
            look.outline = tone(e.tone).withAlpha(0.95)
            look.outlineWidth = 1.25
        }
        if e.lit, e.role == .handle {
            look.body = accent.withAlpha(0.55)
            look.scale = 0.92
        }
        return look
    }
}
