// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation

/// Mirrors icon-manifest.json (bundled as a resource) - the single source of
/// truth for id/name/tier/tagline. Decoded at runtime rather than hand-copied into
/// Swift so a manifest update doesn't require touching this file.
struct AppIconOption: Codable, Identifiable {
    let id: String
    let name: String
    let tier: String
    let tagline: String
    /// Present when the icon was redrawn: the original art still ships, as "AltIcon-<id>-classic",
    /// with its original tagline, for players who prefer it (IconStyle.classic).
    let classic: ClassicVersion?

    struct ClassicVersion: Codable {
        let tagline: String
    }

    var isPro: Bool { tier == "pro" }

    /// Matches the "AltIcon-<id>" naming used for both the asset catalog appiconsets
    /// and the CFBundleAlternateIcons keys in Info-AlternateIcons.plist.
    var alternateIconName: String { "AltIcon-\(id)" }

    /// The icon to use in a given style; icons that were never redrawn look the same in both.
    func alternateIconName(_ style: IconStyle) -> String {
        style == .classic && classic != nil ? "AltIcon-\(id)-classic" : alternateIconName
    }

    func tagline(_ style: IconStyle) -> String {
        style == .classic ? (classic?.tagline ?? tagline) : tagline
    }
}

/// Which art the icon picker shows and applies: the revamped icons (default) or the originals.
enum IconStyle: String, CaseIterable, Identifiable {
    case revamped, classic

    var id: String { rawValue }
    var title: String { self == .revamped ? "Revamped" : "Classic" }

    static let defaultsKey = "muffin.icons.style"
    static var current: IconStyle {
        get { IconStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .revamped }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

private struct IconManifestFile: Codable {
    let icons: [AppIconOption]
}

enum IconManifest {
    /// All pickable icons, in manifest order ("original" first). mono-black/mono-white
    /// are watermark marks, not homescreen candidates, and were never included in the
    /// source manifest's "icons" list to begin with.
    static let all: [AppIconOption] = {
        guard let url = Bundle.main.url(forResource: "icon-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(IconManifestFile.self, from: data) else {
            return []
        }
        return file.icons
    }()

    /// The manifest id behind a system alternate icon name, in either style
    /// ("AltIcon-galaxy-space-classic" -> "galaxy-space"); nil means the main icon.
    static func id(forAlternateIconName name: String?) -> String? {
        guard var s = name else { return nil }
        if s.hasPrefix("AltIcon-") { s.removeFirst("AltIcon-".count) }
        if s.hasSuffix("-classic") { s.removeLast("-classic".count) }
        return s
    }
}
