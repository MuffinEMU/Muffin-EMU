// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation

/// How the library shows covers: flat, or as 3D boxes. That's the whole choice.
/// Flat: GameTDB's HD cover, then an installed 2D pack, then GameTDB's standard cover, then the
/// game's own icon, then the controller glyph. 3D: a 3D pack's box when one is installed, otherwise
/// the flat cover built into a box by the card itself (Box3DCover), so every game gets a 3D box.
enum CoverStylePreference: String, CaseIterable, Identifiable {
    case flat
    case threeD = "3d"

    static let storageKey = "muffin.cover.style"
    static let defaultValue: CoverStylePreference = .flat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: return "Flat"
        case .threeD: return "3D"
        }
    }

    /// Manifest `style` values of the packs this mode reads.
    var packStyles: [String] {
        switch self {
        case .flat: return ["2d"]
        case .threeD: return ["3d"]
        }
    }

    /// Reads the stored mode. Values from 7.9 to 8.0.1 ("auto", "hd2d", "disc", "box3d") map onto
    /// the two modes, so nobody's library breaks on update.
    init(stored raw: String?) {
        switch raw {
        case "3d", "box3d": self = .threeD
        default: self = .flat
        }
    }

    static var current: CoverStylePreference {
        CoverStylePreference(stored: UserDefaults.standard.string(forKey: storageKey))
    }
}

/// 8.0 and 8.0.1 had an art pack "Apply" that changed the theme, card style and size, sort and
/// grouping, and kept the player's own settings in a snapshot. Apply is gone; on the first launch
/// after it, put that snapshot back once so nobody is left with 8.0's changes.
enum LegacyArtPackApply {
    static func migrateOnce() {
        let d = UserDefaults.standard
        // 7.9's "3D boxes" card style is now Covers > 3D with the default layout.
        if d.string(forKey: "muffin.library.cardStyle") == "box3d" {
            d.set(CoverStylePreference.threeD.rawValue, forKey: CoverStylePreference.storageKey)
            d.removeObject(forKey: "muffin.library.cardStyle")
        }
        defer { d.removeObject(forKey: "muffin.art.appliedPack"); d.removeObject(forKey: "muffin.art.preApplySnapshot") }
        guard let data = d.data(forKey: "muffin.art.preApplySnapshot"),
              let snap = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        func put(_ field: String, _ key: String) {
            if let value = snap[field] as? String { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
        put("cardStyle", "muffin.library.cardStyle")
        put("grouping", "muffin.library.grouping")
        put("sort", "muffin.library.sortOrder")
        put("coverStyle", CoverStylePreference.storageKey)
        if let size = snap["cardSize"] as? Double { d.set(size, forKey: "muffin.library.cardSize") } else { d.removeObject(forKey: "muffin.library.cardSize") }
        if let id = snap["themeID"] as? String, let theme = MuffinThemePresets.all.first(where: { $0.id == id }) {
            DispatchQueue.main.async { MuffinThemeStore.shared.select(theme) }
        }
    }
}

/// Where everything this feature stores lives: Application Support, never Documents, so none of
/// it shows up in the Files app. Excluded from device backups because it can all be downloaded again.
enum ArtLocations {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var url = base.appendingPathComponent("MuffinEMU", isDirectory: true).appendingPathComponent("Art", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }

    static var packsDirectory: URL { directory("Packs") }
    static var downloadsDirectory: URL { directory("Downloads") }
    static var dataDirectory: URL { directory("GameData") }
    static var genericDirectory: URL { directory("Generic") }

    static func packDirectory(_ id: String) -> URL { packsDirectory.appendingPathComponent(id, isDirectory: true) }

    private static func directory(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Free space the system will let the app use, or nil when it can't say.
    static func availableBytes() -> Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// The manifest's own normalisation, applied the same way to every title that is compared with an
/// art pack: lowercase; drop a leading "the " or a trailing ", The"; drop (region) and [tag]
/// groups, punctuation, trademark and registered symbols; collapse spaces. Roman numerals stay.
/// Checked against all 2,525 entries of the live manifest: it reproduces every `normalizedTitle`.
enum ArtTitleNormalizer {
    /// A forgiving key for matching game names to pack file names, which often differ in
    /// punctuation and word order ("Legend of Zelda, The - Breath of the Wild" vs "The Legend of
    /// Zelda: Breath of the Wild"): drops "the" anywhere, "&"/"and", and everything that isn't a
    /// letter or digit.
    static func loose(_ title: String) -> String {
        let words = normalize(title.replacingOccurrences(of: "&", with: " and "))
            .split(separator: " ").filter { $0 != "the" && $0 != "and" }
        return words.joined().filter { $0.isLetter || $0.isNumber }
    }

    static func normalize(_ title: String) -> String {
        var t = title.lowercased()
        t = t.replacingOccurrences(of: "\\([^)]*\\)|\\[[^\\]]*\\]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\u{2122}", with: "").replacingOccurrences(of: "\u{00AE}", with: "")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = t.range(of: ",\\s*the$", options: .regularExpression) { t.removeSubrange(range) }
        if let range = t.range(of: "^the\\s+", options: .regularExpression) { t.removeSubrange(range) }
        let kept = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) || $0 == "_" }
        t = String(String.UnicodeScalarView(kept))
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Install and GameTDB regions as one small vocabulary, so "USA/EUR", "NTSC-U", "Europe" and
/// "(Usa)" can be compared.
enum RegionCode: String, CaseIterable {
    case usa = "USA", eur = "EUR", jpn = "JPN", kor = "KOR", chn = "CHN", twn = "TWN"

    var name: String {
        switch self {
        case .usa: return "North America"
        case .eur: return "Europe"
        case .jpn: return "Japan"
        case .kor: return "South Korea"
        case .chn: return "China"
        case .twn: return "Taiwan"
        }
    }

    /// Every region a free-form string mentions.
    static func codes(in text: String?) -> Set<RegionCode> {
        guard let text = text?.lowercased(), !text.isEmpty else { return [] }
        var out = Set<RegionCode>()
        if text.contains("usa") || text.contains("ntsc-u") || text.contains("america") || text.contains("canada") || text == "us" { out.insert(.usa) }
        if text.contains("eur") || text.contains("pal") || text.contains("australia") || text.contains("uk") { out.insert(.eur) }
        if text.contains("jpn") || text.contains("japan") || text.contains("ntsc-j") { out.insert(.jpn) }
        if text.contains("kor") || text.contains("ntsc-k") { out.insert(.kor) }
        if text.contains("chn") || text.contains("china") { out.insert(.chn) }
        if text.contains("twn") || text.contains("taiwan") { out.insert(.twn) }
        return out
    }

    /// The region a GameTDB ID's fourth character stands for (E, P, J, K...).
    static func code(forGameTdbId id: String) -> RegionCode? {
        guard id.count >= 4 else { return nil }
        switch id[id.index(id.startIndex, offsetBy: 3)] {
        case "E": return .usa
        case "P", "D", "F", "I", "S", "U", "X", "Y", "Z": return .eur
        case "J": return .jpn
        case "K": return .kor
        case "W": return .twn
        default: return nil
        }
    }
}
