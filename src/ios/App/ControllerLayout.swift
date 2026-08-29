import SwiftUI

/// Where the on-screen pad's adjustable values live, so the settings sheet, the emulator
/// view and the pad itself agree on the keys without any of them importing the others -
/// the same arrangement `LaunchLogSettings` already uses for its one key.
///
/// Offsets are stored in POINTS, not in layout units. A drag is something the user did
/// with a finger at a particular size, and re-interpreting it against a different unit
/// when the size slider moves would make the cluster wander every time it was resized.
enum ControllerLayoutSettings {
    static let scaleKey = "muffin.controls.scale"
    static let opacityKey = "muffin.controls.opacity"
    static let leftOffsetXKey = "muffin.controls.left.dx"
    static let leftOffsetYKey = "muffin.controls.left.dy"
    static let rightOffsetXKey = "muffin.controls.right.dx"
    static let rightOffsetYKey = "muffin.controls.right.dy"

    static let defaultScale: Double = 1.0
    static let defaultOpacity: Double = 0.85
    static let minScale: Double = 0.6
    static let maxScale: Double = 1.6

    /// Puts every adjustment back where the measured layout says it goes. Removing the
    /// keys rather than writing the defaults into them is deliberate: `@AppStorage` falls
    /// back to its declared default for a missing key, so one list here cannot drift out
    /// of step with the defaults declared at each use site.
    static func reset() {
        let defaults = UserDefaults.standard
        for key in [scaleKey, opacityKey,
                    leftOffsetXKey, leftOffsetYKey,
                    rightOffsetXKey, rightOffsetYKey] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// The on-screen pad's arrangement, taken by measurement from the layout Void sent
/// (bward-dev1/Wiiuios, IMG_3278.jpeg) rather than re-invented, because the last version
/// of this file re-invented it and the result was unusable.
///
/// Measured button centres in that screenshot (1080x498 px, face-button diameter 59.5 px):
///
///     ZL(126,175)   L(245.5,175)            R(833.5,175)   ZR(953.5,175)
///        up(186,273.5)   -(326,282)           +(753,282)     X(893.5,273.5)
///     left(112,342.5) o(186,343) right(259.5,342.5)
///                                          Y(819.5,342.5) o(894,343) A(967.5,342.5)
///        down(186,411.5)                                    B(893.5,411.5)
///
/// The right-hand half is an exact mirror of the left about x = 540 (every measured pair
/// agrees to within a pixel), so only one half is written out below and the other is that
/// one with x negated. Note the two things the previous layout got wrong and this one
/// does not: the face buttons are X-top / Y-left / A-right / B-bottom, and the d-pad is a
/// diamond of circles, not a column of squares.
///
/// Every number is expressed in units of one face-button diameter, so the arrangement
/// survives being drawn at any size: change the unit and the whole cluster scales without
/// a single relationship between two buttons shifting. That is what makes the automatic
/// sizing below safe - it only ever chooses the unit.
enum ControllerGeometry {
    /// Small grey centre circle, 42/59.5.
    static let stickDiameter: CGFloat = 0.706
    /// Plus and minus, 46/59.5.
    static let systemDiameter: CGFloat = 0.773
    /// Shoulders are rounded rects, not circles: 68.5 x 52, over 59.5.
    static let shoulderSize = CGSize(width: 1.151, height: 0.874)
    static let shoulderCornerRadius: CGFloat = 0.235

    /// Where the cluster's centre dot sits when nothing has been dragged: 186 px in from
    /// the near edge and 155 px up from the bottom, both over 59.5. Margins in units of
    /// the button size rather than fractions of the screen, so spacing grows with the
    /// buttons instead of with the display.
    static let centreFromNearEdge: CGFloat = 3.126
    static let centreFromBottom: CGFloat = 2.605

    /// Picks the face-button diameter, in points, for a container of this size.
    ///
    /// The screenshot is a phone, where the cluster covers 59% of the screen height.
    /// Holding that fraction on a 1024-point iPad would ask for 600 points of buttons, so
    /// the proportion is not what carries across form factors - the button size is. This
    /// tracks the short side (the one that changes least between a phone and a tablet in
    /// landscape) and clamps it into a range that stays thumb-sized on both ends.
    static func automaticDiameter(in size: CGSize) -> CGFloat {
        let shortSide = min(size.width, size.height)
        return min(max(shortSide * 0.115, 46), 72)
    }

    enum Style {
        case dpad       // the skin's d-pad colour
        case face       // the skin's per-letter A/B/X/Y colour
        case shoulder   // neutral, as in the screenshot
        case system     // neutral, as in the screenshot
        case stick      // neutral, as in the screenshot
    }

    enum Shape {
        case circle(CGFloat)              // diameter, in layout units
        case roundedRect(CGSize, CGFloat) // size and corner radius, in layout units
    }

    /// One control: what it is called on the wire, what it draws, and where it sits
    /// relative to its cluster's centre dot. +x is right, +y is down.
    struct Control: Identifiable {
        let id: String        // the label the bridge translation switches on
        let glyph: String
        let offset: CGPoint
        let shape: Shape
        let style: Style
    }

    // The cross is measurably wider than it is tall in the source (73.75 vs 68.75 px);
    // that asymmetry is in the screenshot, so it is kept rather than tidied away.
    private static let crossX: CGFloat = 1.240
    private static let crossY: CGFloat = 1.155
    private static let systemOffset = CGPoint(x: 2.353, y: -1.025)
    private static let shoulderSpreadX: CGFloat = 1.004
    private static let shoulderY: CGFloat = -2.824

    private static let button = Shape.circle(1.0)
    private static let stick = Shape.circle(stickDiameter)
    private static let system = Shape.circle(systemDiameter)
    private static let shoulder = Shape.roundedRect(shoulderSize, shoulderCornerRadius)

    /// D-pad, minus, L and ZL, around the left centre dot.
    static let leftCluster: [Control] = [
        Control(id: "up",    glyph: "\u{25B2}", offset: CGPoint(x: 0, y: -crossY), shape: button, style: .dpad),
        Control(id: "left",  glyph: "\u{25C0}", offset: CGPoint(x: -crossX, y: 0), shape: button, style: .dpad),
        Control(id: "right", glyph: "\u{25B6}", offset: CGPoint(x: crossX, y: 0),  shape: button, style: .dpad),
        Control(id: "down",  glyph: "\u{25BC}", offset: CGPoint(x: 0, y: crossY),  shape: button, style: .dpad),
        Control(id: "L3",    glyph: "",         offset: .zero,                     shape: stick,  style: .stick),
        Control(id: "minus", glyph: "\u{2212}", offset: systemOffset,              shape: system, style: .system),
        Control(id: "L",     glyph: "L",  offset: CGPoint(x: shoulderSpreadX, y: shoulderY),  shape: shoulder, style: .shoulder),
        Control(id: "ZL",    glyph: "ZL", offset: CGPoint(x: -shoulderSpreadX, y: shoulderY), shape: shoulder, style: .shoulder)
    ]

    /// A/B/X/Y, plus, R and ZR, around the right centre dot. Mirroring the left half is
    /// not a shortcut - it is what the measurements say the layout is - but the ids and
    /// glyphs differ, so the positions are mirrored and the identities written out.
    static let rightCluster: [Control] = [
        Control(id: "X", glyph: "X", offset: CGPoint(x: 0, y: -crossY), shape: button, style: .face),
        Control(id: "Y", glyph: "Y", offset: CGPoint(x: -crossX, y: 0), shape: button, style: .face),
        Control(id: "A", glyph: "A", offset: CGPoint(x: crossX, y: 0),  shape: button, style: .face),
        Control(id: "B", glyph: "B", offset: CGPoint(x: 0, y: crossY),  shape: button, style: .face),
        Control(id: "R3",   glyph: "",        offset: .zero, shape: stick, style: .stick),
        Control(id: "plus", glyph: "\u{FF0B}", offset: CGPoint(x: -systemOffset.x, y: systemOffset.y), shape: system, style: .system),
        Control(id: "R",    glyph: "R",  offset: CGPoint(x: -shoulderSpreadX, y: shoulderY), shape: shoulder, style: .shoulder),
        Control(id: "ZR",   glyph: "ZR", offset: CGPoint(x: shoulderSpreadX, y: shoulderY),  shape: shoulder, style: .shoulder)
    ]

    /// The rectangle a cluster actually covers, in layout units, relative to its centre
    /// dot. Derived from the control list rather than written down, so it cannot drift out
    /// of step with it - it is what the drag handle is sized to and what keeps a dragged
    /// cluster from being pushed off the edge and lost.
    static func bounds(of cluster: [Control]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for control in cluster {
            let size: CGSize
            switch control.shape {
            case .circle(let diameter):    size = CGSize(width: diameter, height: diameter)
            case .roundedRect(let box, _): size = box
            }
            minX = min(minX, control.offset.x - size.width / 2)
            maxX = max(maxX, control.offset.x + size.width / 2)
            minY = min(minY, control.offset.y - size.height / 2)
            maxY = max(maxY, control.offset.y + size.height / 2)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
