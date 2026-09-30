//
//  ThumbnailPNG.swift
//  Writes a captured frame's thumbnail as a PNG (enlarged with nearest-neighbour so the cells stay
//  visible) for the failures a person will want to look at. ImageIO only, so it works on iOS and macOS.
//
import Foundation
import CoreGraphics
import ImageIO

enum ThumbnailPNG {
    @discardableResult
    static func write(_ frame: CapturedFrame, scale: Int = 4, to url: URL) -> Bool {
        guard frame.isUsable, scale >= 1 else { return false }
        let w = frame.thumbWidth * scale, h = frame.thumbHeight * scale
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = frame.pixel(x / scale, y / scale)
                let i = (y * w + x) * 4
                rgba[i] = UInt8(r); rgba[i + 1] = UInt8(g); rgba[i + 2] = UInt8(b)
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
