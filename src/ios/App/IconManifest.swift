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

    var isPro: Bool { tier == "pro" }

    /// Matches the "AltIcon-<id>" naming used for both the asset catalog appiconsets
    /// and the CFBundleAlternateIcons keys in Info-AlternateIcons.plist.
    var alternateIconName: String { "AltIcon-\(id)" }
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
}
