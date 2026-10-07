import SwiftUI
import QuartzCore
import ImageIO

/// A Wii U game case drawn in 3D, built from Robin55's own case template (Nintendo Wii U 3D Boxes
/// 1.3): the real spine with its blue case lips and Wii U logo, the Wii U banner, and the Nintendo and
/// ESRB badges, cut out of those renders and flattened (BoxSpineTemplate, BoxWiiUBanner,
/// BoxSpineNintendo, BoxRating*). This game's own cover, spine tile and title go in it.
/// - Official cover scans (sleeve-shaped) are used as they are: they already carry the banner and
///   rating. Any other image gets the banner, and the ESRB box when GameTDB knows the rating.
/// - The Nintendo badge only appears on games GameTDB lists as published by Nintendo.
///
/// Proportions are a real Wii U case (135 x 190 mm front, 14 mm deep), turned 38 degrees with the
/// far edge at about 90% of the near edge's height, as measured from the pack renders.
struct Box3DCover<Front: View>: View {
    let title: String
    /// False for an official cover scan, which already has the banner and rating printed on it.
    let addBanner: Bool
    /// The Nintendo badge on the spine: only for games GameTDB lists as published by Nintendo.
    var nintendoPublished = false
    /// "E", "E10", "T" or "M": the game's ESRB rating from GameTDB. Nil draws no rating box,
    /// so nothing is made up for a game whose rating isn't known.
    var esrb: String? = nil
    /// A small picture for the spine's tile under the logo, as on real Wii U spines.
    var spineTilePath: String? = nil
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
        // Proportions from the Robin55 renders: banner about 7.4% of the height, rating box about
        // 19% of the width in the bottom-left corner, thin blue case lips top and bottom.
        let banner = height * 0.074
        let lip = height * 0.012
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if addBanner {
                    Image("BoxWiiUBanner").resizable().frame(width: width, height: banner)
                }
                front()
                    .frame(width: width, height: addBanner ? height - banner : height)
                    .clipped()
            }
            if addBanner, let esrb {
                Image("BoxRating" + esrb).resizable()
                    .frame(width: width * 0.19, height: width * 0.19 * 202 / 138)
                    .offset(x: width * 0.045, y: height - lip - height * 0.035 - width * 0.19 * 202 / 138)
            }
            VStack(spacing: 0) {
                Self.caseBlue.frame(height: lip)
                Spacer(minLength: 0)
                Self.caseBlue.frame(height: lip)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.02, style: .continuous))
        .overlay(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.10)],
                                startPoint: .leading, endPoint: .trailing))
    }

    /// Robin55's spine with its own title and tile removed (BoxSpineTemplate: the case lips, the white
    /// insert and the Wii U logo), with this game's tile, title and, for Nintendo games, the badge.
    private func spineFace(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("BoxSpineTemplate").resizable().frame(width: width, height: height)
            if let spineTilePath {
                CoverImage(path: spineTilePath, fill: true)
                    .frame(width: width * 0.70, height: height * 0.049)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.06, style: .continuous))
                    .offset(x: width * 0.15, y: height * 0.219)
            }
            Text(title)
                .font(.system(size: width * 0.52, weight: .heavy, design: .default))
                .foregroundColor(Self.titleBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .frame(width: height * 0.62, height: width * 0.8)
                .rotationEffect(.degrees(90))
                .frame(width: width, height: height * 0.62)
                .offset(y: height * 0.31)
            if nintendoPublished {
                Image("BoxSpineNintendo").resizable()
                    .frame(width: width, height: height * 0.031)
                    .offset(y: height * 0.955)
            }
        }
        .frame(width: width, height: height)
        .overlay(Color.black.opacity(0.16))
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
    /// A case for a library game: its cover (or the controller glyph when it has none), its title on
    /// the spine, and the Nintendo badge and ESRB box only where GameTDB says they apply.
    static func game(_ game: GameMetadata, coverPath: String?) -> Box3DCover<AnyView> {
        let info = GameDataStore.shared.info(for: game.id)
        let nintendo = info?.publisher?.localizedCaseInsensitiveContains("nintendo") ?? false
        var esrb: String?
        if info?.ratingType?.uppercased() == "ESRB" {
            switch info?.ratingValue?.uppercased() {
            case "E", "EC": esrb = "E"
            case "E10+", "E10": esrb = "E10"
            case "T": esrb = "T"
            case "M": esrb = "M"
            default: esrb = nil
            }
        }
        let title = game.cardName.name
        guard let coverPath else {
            return Box3DCover<AnyView>(title: title, addBanner: true, nintendoPublished: nintendo, esrb: esrb, spineTilePath: nil) {
                AnyView(ZStack {
                    MuffinTheme.muffinTopGradient
                    Image(systemName: "gamecontroller.fill").font(.system(size: 34)).foregroundColor(MuffinTheme.onMuffinTop)
                })
            }
        }
        return Box3DCover<AnyView>(title: title, addBanner: !CoverShape.isSleeve(coverPath), nintendoPublished: nintendo,
                                   esrb: esrb, spineTilePath: coverPath) {
            AnyView(CoverImage(path: coverPath, fill: true))
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
