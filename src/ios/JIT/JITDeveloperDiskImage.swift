// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// Downloads the Developer Disk Image the mount step needs, into the helper
// extension's own Library (which persists across launches), and caches it there. Runs
// in the helper, not the host, so the files sit in the same container the mount reads
// from — no App Group, no paths crossing the process boundary.
//
// Two formats, matched to the OS: the three-file personalized image before iOS 26.4,
// and the five-file cryptex image from 26.4. Files come from the public DDI mirror.

import Foundation

enum JITDeveloperDiskImage {
    /// What the mount step needs back: either the personalized trio or the cryptex
    /// Restore directory.
    enum Prepared {
        case personalized(imagePath: String, trustcachePath: String, manifestPath: String)
        case cryptex(restoreDir: String)
    }

    private static let mirror = "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages"

    private static var cacheRoot: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("MuffinJIT/DDI", isDirectory: true)
    }

    /// Ensures the matching DDI is present on disk, downloading any missing files, and
    /// returns the paths the mount step uses. `progress` gets a line per file.
    static func prepare(cryptex: Bool, progress: (String) -> Void) throws -> Prepared {
        let folder = cacheRoot.appendingPathComponent(cryptex ? "cryptex" : "personalized", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let files = cryptex
            ? ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache", "Image.dmg.cryptex_info", "Image.dmg.root_hash"]
            : ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
        let base = "\(mirror)/\(cryptex ? "Xcode_iOS_DDI_Cryptex" : "Xcode_iOS_DDI_Personalized")"

        for name in files {
            let dest = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            guard let url = URL(string: "\(base)/\(name)") else {
                throw MuffinJITError.ddiFailed("Bad DDI URL for \(name)")
            }
            progress("Downloading \(name)")
            try download(url, to: dest)
        }

        if cryptex {
            return .cryptex(restoreDir: folder.path)
        }
        return .personalized(
            imagePath: folder.appendingPathComponent("Image.dmg").path,
            trustcachePath: folder.appendingPathComponent("Image.dmg.trustcache").path,
            manifestPath: folder.appendingPathComponent("BuildManifest.plist").path)
    }

    private static func download(_ url: URL, to dest: URL) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var fetchError: Error?
        var tempURL: URL?
        let task = URLSession.shared.downloadTask(with: url) { location, response, error in
            defer { semaphore.signal() }
            if let error { fetchError = error; return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                fetchError = MuffinJITError.ddiFailed("HTTP \(http.statusCode) for \(url.lastPathComponent)")
                return
            }
            tempURL = location
        }
        task.resume()
        semaphore.wait()
        if let fetchError { throw fetchError }
        guard let tempURL else { throw MuffinJITError.ddiFailed("No file downloaded for \(url.lastPathComponent)") }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
    }
}
