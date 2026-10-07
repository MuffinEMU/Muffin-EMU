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
/// The turn, depth and perspective are fitted to the pack's own renders (the far edge stands at about
/// 90% of the near edge's height, the spine is about 6% of the case's width), and the case's edges,
/// banner and rating box are measured from them. Everything is sized from the case's own height, so
/// it holds at any card size or screen.
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
    /// True when the image already has the case's blue edges printed on it (the art packs' 2D boxes),
    /// so it fills the whole face instead of sitting inside the case's own edges.
    var coverHasEdges = false
    @ViewBuilder let front: () -> Front

    /// Fitted to Robin55's renders: the case is turned 27 degrees, and its spine reads about 20 mm
    /// deep at this turn (the renders are a little deeper than a real 14 mm case).
    private let turn: Double = 27
    private let depthMM: Double = 20
    private let perspective: CGFloat = 4.4
    /// Top and bottom case edge as a share of the face's height, the right edge as a share of its width.
    private let edgeY: CGFloat = 0.015
    private let edgeX: CGFloat = 0.028

    static var caseBlue: Color { Color(red: 22 / 255, green: 161 / 255, blue: 200 / 255) }
    static var titleBlue: Color { Color(red: 46 / 255, green: 109 / 255, blue: 180 / 255) }

    var body: some View {
        GeometryReader { geo in
            let a = turn * .pi / 180
            // Tallest case that fits the slot once turned: projected width is fw*cos + depth*sin.
            let fh = min(geo.size.height * 0.94,
                         geo.size.width * 0.94 / ((135.0 / 190) * cos(a) + (depthMM / 190) * sin(a)))
            let fw = fh * 135 / 190
            let dw = fw * depthMM / 135
            let projected = fw * cos(a) + dw * sin(a)
            let left = (geo.size.width - projected) / 2 + dw * sin(a)
            let top = (geo.size.height - fh) / 2
            let centreX = left + (fw * cos(a) - dw * sin(a)) / 2
            let distance = fw * perspective

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
            .shadow(color: .black.opacity(0.35), radius: fh * 0.03, x: fh * 0.012, y: fh * 0.02)
        }
    }

    // MARK: Faces

    private func frontFace(width: CGFloat, height: CGFloat) -> some View {
        // Measured from the Robin55 renders: blue case edges about 1.5% of the height top and bottom and
        // 2.8% of the width on the right, rounded corners about 3.5% of the width, the banner across the
        // top of the cover, and the ESRB box about 12% of the width in the bottom-left corner.
        let capY = coverHasEdges ? 0 : height * edgeY
        let capX = coverHasEdges ? 0 : width * edgeX
        let innerW = width - capX
        let innerH = height - 2 * capY
        let banner = innerW * 200 / 1165
        let ratingW = innerW * 0.121
        let ratingH = ratingW * 202 / 138
        return ZStack(alignment: .topLeading) {
            Self.caseBlue
            front()
                .frame(width: innerW, height: innerH)
                .clipped()
                .offset(y: capY)
            if addBanner {
                Image("BoxWiiUBanner").resizable()
                    .frame(width: innerW, height: banner)
                    .offset(y: capY)
                if let esrb {
                    Image("BoxRating" + esrb).resizable()
                        .frame(width: ratingW, height: ratingH)
                        .offset(x: innerW * 0.026, y: height - capY - innerH * 0.0062 - ratingH)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.035, style: .continuous))
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
                .font(.system(size: width * 0.46, weight: .heavy, design: .default))
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
                // The glyph is sized from the face, so it keeps its place at any card size.
                AnyView(GeometryReader { g in
                    ZStack {
                        MuffinTheme.muffinTopGradient
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: g.size.width * 0.28))
                            .foregroundColor(MuffinTheme.onMuffinTop)
                    }
                    .frame(width: g.size.width, height: g.size.height)
                })
            }
        }
        let shape = CoverShape.shape(of: coverPath)
        return Box3DCover<AnyView>(title: title, addBanner: !shape.isSleeve, nintendoPublished: nintendo,
                                   esrb: esrb, spineTilePath: coverPath, coverHasEdges: shape.hasCaseEdges) {
            AnyView(CoverImage(path: coverPath, fill: true))
        }
    }
}

/// Whether an image already has a Wii U sleeve's shape, and whether it already carries the case's blue
/// edges (the art packs' 2D boxes do, GameTDB's covers don't). Read from the file once and remembered.
enum CoverShape {
    struct Result { let isSleeve: Bool; let hasCaseEdges: Bool }

    private static var cache: [String: Result] = [:]
    private static let lock = NSLock()

    static func isSleeve(_ path: String) -> Bool { shape(of: path).isSleeve }

    static func shape(of path: String) -> Result {
        lock.lock(); if let hit = cache[path] { lock.unlock(); return hit }; lock.unlock()
        var result = Result(isSleeve: false, hasCaseEdges: false)
        if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let rawW = props[kCGImagePropertyPixelWidth] as? CGFloat, let rawH = props[kCGImagePropertyPixelHeight] as? CGFloat, rawH > 0 {
            // A phone photo or scan can be stored turned; the picture's own orientation decides its shape.
            let turned = [5, 6, 7, 8].contains((props[kCGImagePropertyOrientation] as? Int) ?? 1)
            let ratio = turned ? rawH / rawW : rawW / rawH
            let sleeve = ratio > 0.64 && ratio < 0.76
            result = Result(isSleeve: sleeve, hasCaseEdges: sleeve && carriesCaseEdges(src))
        }
        lock.lock(); cache[path] = result; lock.unlock()
        return result
    }

    /// Looks at a small copy of the picture: the right edge and the top and bottom edges are the case's
    /// blue on every row sampled.
    private static func carriesCaseEdges(_ src: CGImageSource) -> Bool {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return false }
        let w = cg.width, h = cg.height
        guard w >= 40, h >= 40 else { return false }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return false }
        func isCaseBlue(_ x: Int, _ y: Int) -> Bool {
            let o = (y * w + x) * 4
            let r = Int(pixels[o]), g = Int(pixels[o + 1]), b = Int(pixels[o + 2])
            return r < 90 && g > 110 && g < 205 && b > 150 && b > r + 80
        }
        func share(_ points: [(Int, Int)]) -> Double {
            Double(points.filter { isCaseBlue($0.0, $0.1) }.count) / Double(max(points.count, 1))
        }
        let rows = stride(from: h / 5, through: h * 4 / 5, by: 3).map { $0 }
        let cols = stride(from: w / 5, through: w * 4 / 5, by: 3).map { $0 }
        let right = share(rows.map { (w - 2, $0) })
        let top = share(cols.map { ($0, 0) })
        let bottom = share(cols.map { ($0, h - 1) })
        return right > 0.8 && top > 0.7 && bottom > 0.7
    }
}
