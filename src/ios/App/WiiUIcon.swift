import Foundation
import UIKit

/// Pulls the game's own icon out of a dumped Wii U title so the library cards show the
/// game rather than a generic controller glyph.
///
/// A dump keeps its icon at `meta/iconTex.tga` - a 128x128 TGA. UIImage cannot read
/// TGA at all (there is no ImageIO decoder for it on iOS), which is why simply pointing
/// coverPath at that file would have produced nothing. So it is decoded here and cached
/// as a PNG, and everything downstream keeps loading an ordinary image file.
///
/// Single-file dumps (.wux/.wud/.wua) are archives: their meta/ lives inside the
/// container and only the emulator core can read it. Those keep the placeholder, and
/// that is a limit of where the bytes are, not an oversight.
enum WiiUIcon {
    /// Hidden so it does not appear as clutter next to the user's games in the Files
    /// app. The leading dot also keeps loadGames() from ever considering it a title -
    /// it is a directory with no code/ or meta/ inside, so the dump check rejects it
    /// either way, but two reasons are better than one for something that sits in the
    /// same folder as the library.
    private static let cacheDirectoryName = ".covers"

    /// Path to a PNG of the dump's icon, extracting and caching it on first use.
    /// Returns nil when the dump has no readable icon - the card falls back to its
    /// placeholder, which is the correct outcome, not an error worth surfacing.
    static func cachedIconPath(for gameID: String, dump: URL, in libraryDirectory: URL) -> String? {
        let fileManager = FileManager.default
        let cacheDirectory = libraryDirectory.appendingPathComponent(cacheDirectoryName)
        let cached = cacheDirectory.appendingPathComponent("\(gameID).png")

        let source = dump.appendingPathComponent("meta/iconTex.tga")
        guard fileManager.fileExists(atPath: source.path) else { return nil }

        // Re-extract when the dump's icon is newer than what was cached, so replacing a
        // dump in place does not leave the old game's picture on the card forever.
        if let cachedDate = modificationDate(of: cached),
           let sourceDate = modificationDate(of: source),
           cachedDate >= sourceDate {
            return cached.path
        }

        guard let data = try? Data(contentsOf: source),
              let image = decodeTGA(data),
              let png = image.pngData() else {
            return nil
        }

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        do {
            try png.write(to: cached, options: .atomic)
        } catch {
            return nil
        }
        return cached.path
    }

    private static func modificationDate(of url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    // MARK: - TGA

    /// Decodes the TGA flavours a Wii U dump actually contains: uncompressed truecolour
    /// (type 2) and run-length encoded truecolour (type 10), at 24 or 32 bits per pixel.
    /// Palettised and greyscale TGAs are not handled because no iconTex.tga is one, and
    /// a decoder that quietly mis-renders a format is worse than one that declines it.
    static func decodeTGA(_ data: Data) -> UIImage? {
        let bytes = [UInt8](data)
        guard bytes.count > 18 else { return nil }

        let idLength = Int(bytes[0])
        let colorMapType = bytes[1]
        let imageType = bytes[2]
        let width = Int(bytes[12]) | (Int(bytes[13]) << 8)
        let height = Int(bytes[14]) | (Int(bytes[15]) << 8)
        let pixelDepth = Int(bytes[16])
        let descriptor = bytes[17]

        guard colorMapType == 0,
              imageType == 2 || imageType == 10,
              pixelDepth == 24 || pixelDepth == 32,
              width > 0, height > 0,
              width <= 4096, height <= 4096 else {
            return nil
        }

        let bytesPerPixel = pixelDepth / 8
        let pixelCount = width * height
        var offset = 18 + idLength
        guard offset <= bytes.count else { return nil }

        // TGA stores channels as BGR(A); the buffer handed to CoreGraphics is RGBA.
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)

        // Takes the buffer as a parameter rather than capturing it. A local function
        // that captures `rgba` keeps an access to it alive, and passing `&rgba` to the
        // flip below would then be overlapping exclusive access - a compile error, not
        // a subtlety worth risking on a build we cannot type-check locally.
        func writePixel(_ buffer: inout [UInt8], _ index: Int, _ b: UInt8, _ g: UInt8, _ r: UInt8, _ a: UInt8) {
            let destination = index * 4
            buffer[destination] = r
            buffer[destination + 1] = g
            buffer[destination + 2] = b
            buffer[destination + 3] = a
        }

        if imageType == 2 {
            guard offset + pixelCount * bytesPerPixel <= bytes.count else { return nil }
            for index in 0..<pixelCount {
                let source = offset + index * bytesPerPixel
                writePixel(
                    &rgba,
                    index,
                    bytes[source],
                    bytes[source + 1],
                    bytes[source + 2],
                    bytesPerPixel == 4 ? bytes[source + 3] : 255
                )
            }
        } else {
            var written = 0
            while written < pixelCount {
                guard offset < bytes.count else { return nil }
                let packet = bytes[offset]
                offset += 1
                // The low 7 bits are "one less than the run length" in both packet
                // kinds, which is the detail every hand-rolled TGA reader gets wrong
                // once: a stored 0 means one pixel, not zero.
                let runLength = Int(packet & 0x7F) + 1
                guard written + runLength <= pixelCount else { return nil }

                if packet & 0x80 != 0 {
                    guard offset + bytesPerPixel <= bytes.count else { return nil }
                    let b = bytes[offset]
                    let g = bytes[offset + 1]
                    let r = bytes[offset + 2]
                    let a = bytesPerPixel == 4 ? bytes[offset + 3] : 255
                    offset += bytesPerPixel
                    for step in 0..<runLength {
                        writePixel(&rgba, written + step, b, g, r, a)
                    }
                } else {
                    guard offset + runLength * bytesPerPixel <= bytes.count else { return nil }
                    for step in 0..<runLength {
                        let source = offset + step * bytesPerPixel
                        writePixel(
                            &rgba,
                            written + step,
                            bytes[source],
                            bytes[source + 1],
                            bytes[source + 2],
                            bytesPerPixel == 4 ? bytes[source + 3] : 255
                        )
                    }
                    offset += runLength * bytesPerPixel
                }
                written += runLength
            }
        }

        // Some Wii U icons carry an all-zero alpha channel. Honouring it renders a
        // fully transparent card, which reads as "the icon did not load" - so an image
        // that is entirely transparent is treated as opaque instead.
        if bytesPerPixel == 4 {
            var sawOpaque = false
            for index in stride(from: 3, to: rgba.count, by: 4) where rgba[index] != 0 {
                sawOpaque = true
                break
            }
            if !sawOpaque {
                for index in stride(from: 3, to: rgba.count, by: 4) {
                    rgba[index] = 255
                }
            }
        }

        // Bit 5 of the descriptor set means the first row in the file is the TOP row.
        // Clear means bottom-up, which is the TGA default and would show the icon
        // upside down if ignored.
        if descriptor & 0x20 == 0 {
            flipVertically(&rgba, width: width, height: height)
        }

        // Premultiply. CGImage can be told the alpha is straight, but every consumer
        // downstream (PNG encode, SwiftUI's Image) then has to agree, and getting that
        // wrong shows up as haloed edges rather than as an error.
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Int(rgba[index + 3])
            if alpha == 255 { continue }
            rgba[index] = UInt8(Int(rgba[index]) * alpha / 255)
            rgba[index + 1] = UInt8(Int(rgba[index + 1]) * alpha / 255)
            rgba[index + 2] = UInt8(Int(rgba[index + 2]) * alpha / 255)
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func flipVertically(_ rgba: inout [UInt8], width: Int, height: Int) {
        let rowBytes = width * 4
        for row in 0..<(height / 2) {
            let top = row * rowBytes
            let bottom = (height - 1 - row) * rowBytes
            for byte in 0..<rowBytes {
                rgba.swapAt(top + byte, bottom + byte)
            }
        }
    }
}
