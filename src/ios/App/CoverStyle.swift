import Foundation

/// Which look of cover art the library prefers. The art itself comes from the cover chain
/// (CoverSources.swift); this only decides which source is asked first and which kind of art pack
/// counts as "the chosen style".
enum CoverStylePreference: String, CaseIterable, Identifiable {
    case auto
    case hd2d
    case box3d
    case disc

    static let storageKey = "muffin.cover.style"
    static let defaultValue: CoverStylePreference = .auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto (best available)"
        case .hd2d: return "HD 2D (GameTDB)"
        case .box3d: return "3D box (art packs)"
        case .disc: return "Disc (art packs)"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "GameTDB first, then any art pack you have installed."
        case .hd2d: return "Flat front covers from GameTDB, then 2D art packs."
        case .box3d: return "3D box art from an installed pack when there is one."
        case .disc: return "Disc art from an installed pack when there is one."
        }
    }

    /// Manifest `style` values of the packs this preference reads, best first.
    var packStyles: [String] {
        switch self {
        case .auto: return ["3d", "2d", "disc"]
        case .hd2d: return ["2d"]
        case .box3d: return ["3d"]
        case .disc: return ["disc"]
        }
    }

    /// True when an installed pack of the chosen style should win over GameTDB's own cover.
    var packBeatsGameTDB: Bool { self == .box3d || self == .disc }

    static var current: CoverStylePreference {
        CoverStylePreference(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? defaultValue
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
