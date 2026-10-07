import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Everything about cover pixels that isn't network: encoding a player's own cover at
/// full resolution (up to 4K) and decoding stored covers at the size a card needs.
enum CoverImageLoader {
    /// Longest side kept for a player's own cover. Anything larger is downscaled to this;
    /// anything at or under it is stored untouched.
    static let maxStoredPixels = 3840

    // MARK: - Storing a custom cover

    /// Prepares picked image bytes for storage as `<gameID>_cover.<ext>` at original
    /// resolution. JPEG and PNG within the limit are stored byte-for-byte. PNG stays PNG
    /// when it has to be downscaled; everything else (HEIC, TIFF, WebP, GIF...) becomes
    /// high-quality JPEG (0.95). Downscaling happens only above `maxStoredPixels` on the
    /// long side. No thumbnail path is involved: thumbnails are decoded separately from
    /// the stored file by `decode(path:maxPixel:)` and never written back.
    static func prepareCustomCover(from data: Data) -> (data: Data, ext: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { return nil }

        let type = CGImageSourceGetType(source) as String?
        let isPNG = type == UTType.png.identifier
        let isJPEG = type == UTType.jpeg.identifier
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        let longSide = max(w, h)

        if longSide <= maxStoredPixels, orientation == 1, isPNG || isJPEG {
            return (data, isPNG ? "png" : "jpg")
        }

        // Re-encode (format conversion, EXIF rotation to bake in, or downscale above 4K).
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longSide, maxStoredPixels),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        let outType = isPNG ? UTType.png.identifier : UTType.jpeg.identifier
        guard let dest = CGImageDestinationCreateWithData(out, outType as CFString, 1, nil) else { return nil }
        let dprops: [CFString: Any] = isPNG ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.95]
        CGImageDestinationAddImage(dest, cg, dprops as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, isPNG ? "png" : "jpg")
    }

    // MARK: - Decoding for display

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // Budget derived from the device's own RAM, never a model name.
        c.totalCostLimit = Int(min(ProcessInfo.processInfo.physicalMemory / 24, 192 * 1024 * 1024))
        return c
    }()

    /// Pixel size a view of `points` needs on this device: its longest side times the
    /// screen's scale, rounded up to a 64 px bucket (fewer cache variants), never above
    /// the stored 4K cap.
    static func targetPixels(forPoints points: CGSize) -> Int {
        let scale = max(UIScreen.main.scale, 1)
        let raw = Int((max(points.width, points.height) * scale).rounded(.up))
        return min(max(((raw + 63) / 64) * 64, 64), maxStoredPixels)
    }

    private static func key(_ path: String, _ px: Int) -> NSString {
        let m = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(path)|\(px)|\(m)" as NSString
    }

    static func cached(path: String, maxPixel: Int) -> UIImage? {
        cache.object(forKey: key(path, maxPixel))
    }

    /// Decodes the file at no more than `maxPixel` on its long side (ImageIO downsamples
    /// during decode, so a 4K cover never sits fully decoded in memory for a small card).
    static func decode(path: String, maxPixel: Int) -> UIImage? {
        let k = key(path, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, srcOpts as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: k, cost: cg.width * cg.height * 4)
        return image
    }
}

/// A cover drawn at the pixel size its slot needs on this device. Decodes off the main
/// thread; a cache hit renders on the first frame. Fits (never crops) like the old inline code.
struct CoverImage: View {
    let path: String
    var padding: CGFloat = 0
    /// File modification stamp, so replacing a cover in place (same path) re-renders the card.
    private let stamp: TimeInterval

    init(path: String, padding: CGFloat = 0) {
        self.path = path
        self.padding = padding
        self.stamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
    }

    @State private var loaded: UIImage?
    @State private var loadedKey = ""

    var body: some View {
        GeometryReader { geo in
            let px = CoverImageLoader.targetPixels(forPoints: geo.size)
            let tag = "\(path)|\(px)|\(stamp)"
            let image = CoverImageLoader.cached(path: path, maxPixel: px) ?? (loadedKey == tag ? loaded : nil)
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: tag) {
                guard CoverImageLoader.cached(path: path, maxPixel: px) == nil else { return }
                let p = path
                let result = await Task.detached(priority: .utility) {
                    CoverImageLoader.decode(path: p, maxPixel: px)
                }.value
                loaded = result
                loadedKey = tag
            }
        }
        .padding(padding)
    }
}
