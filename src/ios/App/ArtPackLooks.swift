import SwiftUI
import ImageIO

// MARK: - Look table

/// The library look that goes with one art pack: card style and size, cover style, grouping,
/// sort and a theme. Every value is a raw value of the setting it changes, so applying a look
/// writes the same keys the Settings screens write. This table is the only place looks are defined.
struct ArtPackLook {
    enum PreviewShape { case box, square, disc, tile }

    let name: String
    let cardStyle: LibraryCardStyle
    let cardSize: Double
    let coverStyle: CoverStylePreference
    let grouping: LibraryGrouping
    let sort: LibrarySortOrder
    /// An id from `MuffinThemePresets.all`, picked to sit with the pack's art.
    let themeID: String
    let preview: PreviewShape

    /// One line per pack. Themes are the existing presets: Double Chocolate (warm browns of
    /// box spines), Blueberry Blast (eShop blue), Diamond Ice (disc silver), Retro Console (VC).
    static let table: [String: ArtPackLook] = [
        "3d-boxes": shelf(cover: .box3d, size: 1.1, theme: "double-chocolate"),
        "robin55-3d-8bit": shelf(cover: .box3d, size: 1.0, theme: "retro"),
        "robin55-3d-32bit": shelf(cover: .box3d, size: 1.0, theme: "blueberry-blast"),
        "2d-eshop": ArtPackLook(name: "eShop Grid", cardStyle: .largeCovers, cardSize: 1.0, coverStyle: .hd2d,
                                grouping: .none, sort: .title, themeID: "blueberry-blast", preview: .square),
        "2d-disc": ArtPackLook(name: "Disc Collection", cardStyle: .standard, cardSize: 1.05, coverStyle: .disc,
                               grouping: .none, sort: .title, themeID: "pro-diamond-ice", preview: .disc),
        "vc-2d": ArtPackLook(name: "Virtual Console", cardStyle: .compact, cardSize: 0.9, coverStyle: .hd2d,
                             grouping: .alphabet, sort: .title, themeID: "retro", preview: .tile),
        "vc-3d": ArtPackLook(name: "Virtual Console", cardStyle: .compact, cardSize: 0.9, coverStyle: .box3d,
                             grouping: .alphabet, sort: .title, themeID: "retro", preview: .tile),
    ]

    private static func shelf(cover: CoverStylePreference, size: Double, theme: String) -> ArtPackLook {
        ArtPackLook(name: "3D Shelf", cardStyle: .box3d, cardSize: size, coverStyle: cover,
                    grouping: .alphabet, sort: .title, themeID: theme, preview: .box)
    }

    /// The look for a pack; a pack the table doesn't know gets one from its style.
    static func look(for packID: String, style: String) -> ArtPackLook {
        if let known = table[packID] { return known }
        switch style {
        case "disc": return table["2d-disc"]!
        case "2d": return table["2d-eshop"]!
        default: return table["3d-boxes"]!
        }
    }
}

// MARK: - Apply, snapshot, restore

/// Which pack is applied, and the settings the player had before the first apply.
enum ArtPackApplyStore {
    static let appliedKey = "muffin.art.appliedPack"
    private static let snapshotKey = "muffin.art.preApplySnapshot"

    private struct Snapshot: Codable {
        var cardStyle: String?
        var cardSize: Double?
        var coverStyle: String?
        var grouping: String?
        var sort: String?
        var themeID: String?
    }

    static var appliedID: String? {
        let id = UserDefaults.standard.string(forKey: appliedKey)
        return (id?.isEmpty ?? true) ? nil : id
    }

    /// Applies a pack's look. The snapshot is saved only when nothing was applied yet, so going
    /// from one pack to another and then back to default returns to the original settings.
    static func apply(_ meta: InstalledPackMeta) {
        let d = UserDefaults.standard
        if appliedID == nil {
            let snap = Snapshot(
                cardStyle: d.string(forKey: LibraryCardStyle.storageKey),
                cardSize: d.object(forKey: LibraryCardStyle.sizeStorageKey) as? Double,
                coverStyle: d.string(forKey: CoverStylePreference.storageKey),
                grouping: d.string(forKey: LibraryGrouping.storageKey),
                sort: d.string(forKey: "muffin.library.sortOrder"),
                themeID: MuffinThemeStore.shared.current.id)
            if let data = try? JSONEncoder().encode(snap) { d.set(data, forKey: snapshotKey) }
        }
        // Applying a pack is about its art. Only the card style follows it, so 3D art shows as 3D
        // boxes; theme, size, sort and grouping stay as the player set them.
        if meta.style == "3d" { d.set(LibraryCardStyle.box3d.rawValue, forKey: LibraryCardStyle.storageKey) }
        d.set(meta.id, forKey: appliedKey)
        changed()
    }

    /// Puts back what the player had before the first apply and clears the applied pack.
    static func restoreDefault() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: snapshotKey), let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            func put(_ value: String?, _ key: String) { if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) } }
            // Put back everything the snapshot holds. Snapshots from 8.0, when Apply also changed the
            // theme, size, sort and grouping, restore all of those, so "Stop using" fully undoes them.
            put(snap.cardStyle, LibraryCardStyle.storageKey)
            if let size = snap.cardSize { d.set(size, forKey: LibraryCardStyle.sizeStorageKey) } else { d.removeObject(forKey: LibraryCardStyle.sizeStorageKey) }
            put(snap.coverStyle, CoverStylePreference.storageKey)
            put(snap.grouping, LibraryGrouping.storageKey)
            put(snap.sort, "muffin.library.sortOrder")
            if let id = snap.themeID, let theme = MuffinThemePresets.all.first(where: { $0.id == id }) { MuffinThemeStore.shared.select(theme) }
        }
        d.removeObject(forKey: snapshotKey)
        d.removeObject(forKey: appliedKey)
        changed()
    }

    /// A deleted pack can't stay applied.
    static func packDeleted(_ id: String) {
        if appliedID == id { restoreDefault() }
    }

    private static func changed() {
        NotificationCenter.default.post(name: .muffinCoverArtSourcesChanged, object: nil)
        NotificationCenter.default.post(name: .muffinArtPackAppliedChanged, object: nil)
    }
}

extension Notification.Name {
    static let muffinArtPackAppliedChanged = Notification.Name("muffin.artPackAppliedChanged")
}

// MARK: - Preview

enum PackThumbnail {
    private static let cache = NSCache<NSString, UIImage>()

    /// A small decoded copy, so a pack of 800 MB never decodes a full-size image for a 60 pt preview.
    static func load(_ path: String, maxPixels: Int = 180) async -> UIImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image: UIImage? = await Task.detached(priority: .utility) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCache: false,
            ]
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}

/// Three or four of an installed pack's own images, drawn the way its look draws cards.
struct PackLookPreview: View {
    let packID: String
    let shape: ArtPackLook.PreviewShape
    @State private var images: [UIImage] = []

    private var height: CGFloat { shape == .tile ? 48 : 64 }

    var body: some View {
        HStack(spacing: shape == .box ? -6 : 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: shape == .box ? .fit : .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .shadow(color: MuffinTheme.shadow.opacity(shape == .box ? 0.5 : 0.25), radius: shape == .box ? 3 : 2, x: 1, y: 2)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height + 4)
        .accessibilityHidden(true)
        .task(id: packID) {
            let paths = ArtPackIndex.shared.samplePaths(packID, count: 4)
            var out: [UIImage] = []
            for p in paths { if let i = await PackThumbnail.load(p) { out.append(i) } }
            images = out
        }
    }

    private var width: CGFloat {
        switch shape {
        case .box: return 46
        case .square, .disc: return height
        case .tile: return 48
        }
    }

    private var radius: CGFloat {
        switch shape {
        case .disc: return height / 2
        case .box: return 2
        default: return 6
        }
    }
}
