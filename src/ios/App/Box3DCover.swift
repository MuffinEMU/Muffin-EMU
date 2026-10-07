import SwiftUI
import QuartzCore
import ImageIO

/// A Wii U game case drawn in 3D, modelled on the art packs' own 3D boxes (Robin55 1.3 and the
/// 3D BOXES set) so a built case sits beside pack art without looking different:
/// - the case is Wii U blue plastic, showing as rounded lips at the top and bottom of the spine;
/// - the spine is the white insert, with "Wii U" running down the top and the game's title in blue
///   running down the middle;
/// - the front is the cover. Official cover scans already carry the blue "Wii U" banner; any other
///   image (square, custom, an icon) gets that banner added across the top.
///
/// Proportions are a real Wii U case (135 x 190 mm front, 14 mm deep), turned 38 degrees with the
/// far edge at about 90% of the near edge's height, as measured from the pack renders.
struct Box3DCover<Front: View>: View {
    let title: String
    /// False for an official cover scan, which already has the banner printed on it.
    let addBanner: Bool
    @ViewBuilder let front: () -> Front

    private let turn: Double = 38

    static var caseBlue: Color { Color(red: 22 / 255, green: 161 / 255, blue: 200 / 255) }
    static var titleBlue: Color { Color(red: 46 / 255, green: 109 / 255, blue: 180 / 255) }

    var body: some View {
        GeometryReader { geo in
            let a = turn * .pi / 180
            // Tallest case that fits the slot once turned: projected width is fw*cos + depth*sin.
            let fh = min(geo.size.height * 0.94,
                         geo.size.width * 0.94 / ((135.0 / 190) * cos(a) + (14.0 / 190) * sin(a)))
            let fw = fh * 135 / 190
            let dw = fw * 14 / 135
            let projected = fw * cos(a) + dw * sin(a)
            let left = (geo.size.width - projected) / 2 + dw * sin(a)
            let top = (geo.size.height - fh) / 2
            let centreX = left + (fw * cos(a) - dw * sin(a)) / 2
            let distance = fw * 5.5

            ZStack(alignment: .topLeading) {
                spineFace(width: dw, height: fh)
                    .projectionEffect(Self.face(pivotX: dw, angle: a - .pi / 2,
                                                centreX: centreX - (left - dw), centreY: fh / 2, distance: distance))
                    .offset(x: left - dw, y: top)
                frontFace(width: fw, height: fh)
                    .projectionEffect(Self.face(pivotX: 0, angle: a,
                                                centreX: centreX - left, centreY: fh / 2, distance: distance))
                    .offset(x: left, y: top)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, x: 4, y: 6)
        }
    }

    // MARK: Faces

    private func frontFace(width: CGFloat, height: CGFloat) -> some View {
        let banner = height * 0.085
        return ZStack(alignment: .top) {
            front()
                .frame(width: width, height: addBanner ? height - banner : height)
                .clipped()
                .frame(width: width, height: height, alignment: .bottom)
            if addBanner {
                ZStack {
                    Self.caseBlue
                    Text("Wii U")
                        .font(.system(size: banner * 0.55, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: width, height: banner)
            }
        }
        .frame(width: width, height: height)
        // The plastic: a thin blue edge round the sleeve, rounded like the case.
        .overlay(RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
            .strokeBorder(Self.caseBlue.opacity(0.85), lineWidth: max(1, width * 0.012)))
        .clipShape(RoundedRectangle(cornerRadius: width * 0.03, style: .continuous))
        .overlay(LinearGradient(colors: [Color.white.opacity(0.12), .clear, Color.black.opacity(0.10)],
                                startPoint: .leading, endPoint: .trailing))
    }

    private func spineFace(width: CGFloat, height: CGFloat) -> some View {
        let lip = height * 0.022
        return ZStack {
            Color(white: 0.985)
            VStack(spacing: 0) {
                Self.caseBlue.frame(height: lip)
                // "Wii U" down the top of the spine, then the title down the middle, both reading
                // top to bottom like the real insert.
                Text("Wii U")
                    .font(.system(size: width * 0.62, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.55))
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: width, height: height * 0.16)
                Spacer(minLength: height * 0.06)
                Text(title.uppercased())
                    .font(.system(size: width * 0.5, weight: .heavy, design: .rounded))
                    .foregroundColor(Self.titleBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(width: height * 0.6, height: width)
                    .rotationEffect(.degrees(90))
                    .frame(width: width, height: height * 0.6)
                Spacer(minLength: 0)
                Self.caseBlue.frame(height: lip)
            }
        }
        .frame(width: width, height: height)
        .overlay(Color.black.opacity(0.18))
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

extension Box3DCover where Front == AnyView {
    /// A case from a cover image. An image shaped like a Wii U sleeve (about 0.70 wide per unit of
    /// height, which official scans are) is used as is; any other shape is filled and cropped under
    /// an added "Wii U" banner.
    static func image(_ path: String, title: String) -> Box3DCover<AnyView> {
        Box3DCover<AnyView>(title: title, addBanner: !CoverShape.isSleeve(path)) {
            AnyView(CoverImage(path: path, fill: true))
        }
    }

    /// The case for a game with no art at all: the controller glyph on the card gradient.
    static func noCover(title: String) -> Box3DCover<AnyView> {
        Box3DCover<AnyView>(title: title, addBanner: true) {
            AnyView(ZStack {
                MuffinTheme.muffinTopGradient
                Image(systemName: "gamecontroller.fill").font(.system(size: 34)).foregroundColor(MuffinTheme.onMuffinTop)
            })
        }
    }
}

/// Whether an image already has a Wii U sleeve's shape, read from its header once and remembered.
enum CoverShape {
    private static var cache: [String: Bool] = [:]
    private static let lock = NSLock()

    static func isSleeve(_ path: String) -> Bool {
        lock.lock(); if let hit = cache[path] { lock.unlock(); return hit }; lock.unlock()
        var result = false
        if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat, h > 0 {
            let ratio = w / h
            result = ratio > 0.64 && ratio < 0.76
        }
        lock.lock(); cache[path] = result; lock.unlock()
        return result
    }
}
