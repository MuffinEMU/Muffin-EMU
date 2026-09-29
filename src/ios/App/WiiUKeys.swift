import Foundation

/// Wii U decryption keys: the user's own keys.txt, dumped from their own console. Cemu
/// decrypts disc images with AES-128 keys read from keys.txt (one per line), trying each
/// until one decrypts the header. MuffinEMU includes no keys; without keys.txt, encrypted
/// games don't run and homebrew is unaffected.
///
/// The user-facing file is Documents/keys (visible in the Files app, so a keys.txt can be
/// dragged in). The engine reads Documents/mlc/keys.txt, so `IOSTitleLaunch_AdoptDroppedKeys()`
/// (src/ios/Bridge/Core/IOSTitleLaunch.cpp) copies the first into the second before each
/// launch. The engine reads keys once per app session, so keys added after a game has
/// already been started need an app restart. That function and this type must agree on both
/// paths.
enum WiiUKeys {
    /// Where the user puts keys, and the only path this type writes to.
    static var directoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("keys")
    }

    static var fileURL: URL? {
        directoryURL?.appendingPathComponent("keys.txt")
    }

    /// Where the engine reads from (Documents/mlc/keys.txt). Removal has to reach it too, or the
    /// next adopt would copy the keys back.
    private static var engineFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("mlc")
            .appendingPathComponent("keys.txt")
    }

    /// Creates the drop folder at startup so it is visible in the Files app.
    static func ensureDirectoryExists() {
        guard let directoryURL else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    enum ImportError: LocalizedError {
        case accessDenied
        case unreadable
        case noKeysFound
        case tooLarge
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Couldn't access that file."
            case .unreadable:
                return "That file isn't readable text - keys.txt is a plain text file with one key per line."
            case .noKeysFound:
                return "No keys found in that file. Each key is 32 hex characters on its own line; anything after a # is a comment."
            case .tooLarge:
                return "That file is far too big to be a keys.txt."
            case .writeFailed(let error):
                return "Couldn't save keys.txt: \(error.localizedDescription)"
            }
        }
    }

    /// A keys.txt is a few hundred bytes; the cap makes picking a disc image by mistake fail fast.
    private static let maximumFileSize = 1 << 20 // 1 MiB

    /// Counts the usable 128-bit keys in a keys.txt using the same rules as `KeyCache_Prepare()`
    /// (src/Cafe/Filesystem/FST/KeyCache.cpp): truncate at the first # or ;, strip spaces,
    /// tabs, dashes and underscores, and accept 32 hex characters. Done here because the
    /// engine can't answer before it is initialized.
    static func usableKeyCount(in text: String) -> Int {
        var count = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = Substring(rawLine)
            if let commentStart = line.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                line = line[line.startIndex..<commentStart]
            }
            let stripped = line.filter { $0 != " " && $0 != "\t" && $0 != "-" && $0 != "_" }
            guard stripped.count == 32 else { continue }
            guard stripped.allSatisfy({ $0.isHexDigit }) else { continue }
            count += 1
        }
        return count
    }

    /// Keys currently installed, or 0 if there is no keys.txt yet.
    static func installedKeyCount() -> Int {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        return usableKeyCount(in: text)
    }

    static func keysFileExists() -> Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Copies a user-picked keys.txt into place and returns how many keys it contains. The
    /// file is read inside the picker's security scope and validated in memory, so an
    /// unusable file never overwrites a working keys.txt.
    @discardableResult
    static func importKeys(from source: URL) throws -> Int {
        guard source.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { source.stopAccessingSecurityScopedResource() }

        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        if let size = attributes?[.size] as? Int, size > maximumFileSize {
            throw ImportError.tooLarge
        }

        guard let data = try? Data(contentsOf: source) else {
            throw ImportError.accessDenied
        }
        // Fall back to Latin-1: files from Windows tools may not be UTF-8, and only ASCII matters.
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }

        let count = usableKeyCount(in: text)
        guard count > 0 else { throw ImportError.noKeysFound }

        guard let directoryURL, let fileURL else { throw ImportError.accessDenied }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ImportError.writeFailed(error)
        }
        return count
    }

    /// Deletes the installed keys.txt: both the visible copy and the engine's, otherwise the
    /// next adopt would restore it.
    static func removeKeys() throws {
        let manager = FileManager.default
        var firstError: Error?
        for url in [fileURL, engineFileURL].compactMap({ $0 }) {
            guard manager.fileExists(atPath: url.path) else { continue }
            do {
                try manager.removeItem(at: url)
            } catch {
                // Keep going so a failure on one copy doesn't leave the other behind.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }
}
