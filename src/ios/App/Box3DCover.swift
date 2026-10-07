import SwiftUI
import QuartzCore

/// A Wii U case drawn in 3D from any flat image: the cover on the front face and a spine of real
/// thickness on the left, turned the way 3D box art from the packs is (spine toward you, front
/// receding to the right). Used by the 3D cards whenever a game has no 3D pack art, so covers you
/// add yourself, square images and GameTDB covers all become boxes automatically.
///
/// Proportions are a real Wii U case: 135 x 190 mm front, 14 mm deep. Both faces are projected with
/// the same rotation and perspective about the box's centre, so the spine meets the front edge.
struct Box3DCover<Front: View, Spine: View>: View {
    @ViewBuilder let front: () -> Front
    @ViewBuilder let spine: () -> Spine

    /// Turn of the case toward the viewer. Positive turns the spine side toward you.
    private let turn: Double = 24

    var body: some View {
        GeometryReader { geo in
            let a = turn * .pi / 180
            // Tallest case that fits the slot once turned: projected width is fw*cos + depth*sin.
            let fh = min(geo.size.height * 0.94,
                         geo.size.width * 0.92 / ((135.0 / 190) * cos(a) + (14.0 / 190) * sin(a)))
            let fw = fh * 135 / 190
            let dw = fw * 14 / 135
            // Projected widths, to centre the whole case in the slot.
            let projected = fw * cos(a) + dw * sin(a)
            let left = (geo.size.width - projected) / 2 + dw * sin(a)
            let top = (geo.size.height - fh) / 2
            let centreX = left + (fw * cos(a) - dw * sin(a)) / 2
            let distance = fw * 3.5

            ZStack(alignment: .topLeading) {
                spine()
                    .frame(width: dw, height: fh)
                    .clipped()
                    .overlay(Color.black.opacity(0.32))
                    .projectionEffect(Self.face(pivotX: dw, angle: a - .pi / 2,
                                                centreX: centreX - (left - dw), centreY: fh / 2, distance: distance))
                    .offset(x: left - dw, y: top)
                front()
                    .frame(width: fw, height: fh)
                    .clipped()
                    .overlay(
                        LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.12)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .projectionEffect(Self.face(pivotX: 0, angle: a,
                                                centreX: centreX - left, centreY: fh / 2, distance: distance))
                    .offset(x: left, y: top)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, x: 4, y: 6)
        }
    }

    /// Rotates a face about the vertical line x = pivotX (its edge on the shared spine corner), then
    /// applies perspective about the box's centre, all in the face's own coordinates.
    private static func face(pivotX: CGFloat, angle: Double, centreX: CGFloat, centreY: CGFloat, distance: CGFloat) -> ProjectionTransform {
        var t = CATransform3DMakeTranslation(-pivotX, -centreY, 0)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(angle), 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(pivotX - centreX, 0, 0))
        var p = CATransform3DIdentity
        p.m34 = -1 / distance
        t = CATransform3DConcat(t, p)
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(centreX, centreY, 0))
        return ProjectionTransform(t)
    }
}

extension Box3DCover where Front == AnyView, Spine == AnyView {
    /// A case made from a cover image: the front is the image filled and cropped to the case, and the
    /// spine is the image's own left edge, so square and custom images get a matching spine.
    static func image(_ path: String) -> Box3DCover<AnyView, AnyView> {
        Box3DCover<AnyView, AnyView>(
            front: { AnyView(CoverImage(path: path, fill: true)) },
            spine: { AnyView(GeometryReader { g in
                CoverImage(path: path, fill: true)
                    .frame(width: g.size.height * 135 / 190, height: g.size.height)
                    .frame(width: g.size.width, alignment: .leading)
                    .clipped()
            }) }
        )
    }

    /// The case for a game with no art at all: the controller glyph on the card gradient.
    static var noCover: Box3DCover<AnyView, AnyView> {
        Box3DCover<AnyView, AnyView>(
            front: { AnyView(ZStack {
                MuffinTheme.muffinTopGradient
                Image(systemName: "gamecontroller.fill").font(.system(size: 34)).foregroundColor(MuffinTheme.onMuffinTop)
            }) },
            spine: { AnyView(MuffinTheme.muffinTopGradient) }
        )
    }
}
