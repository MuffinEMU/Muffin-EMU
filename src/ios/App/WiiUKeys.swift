import Foundation

/// Wii U decryption keys - the user's own, dumped from their own console.
///
/// Real Wii U games are shipped encrypted. Cemu decrypts them with AES-128 keys read
/// from a plain text file called keys.txt, one key per line; when it opens a disc image
/// it simply tries every key it has until one decrypts the header to zeroes. Muffin
/// ships no keys, derives no keys and has no way to obtain a key it was not given - if
/// keys.txt is absent, encrypted games do not run and homebrew is completely unaffected.
/// Getting the file is the user's side of the deal: it is dumped from a Wii U they own.
///
/// The file lives in the same directory the engine already uses for everything else,
/// Documents/mlc, because that is what `ActiveSettings::GetUserDataPath()` resolves to
/// on iOS (see CemuBridge.mm's SetPaths call). UIFileSharingEnabled is on, so it is also
/// directly visible and editable in the Files app - importing through the app is the
/// convenient route, not the only one.
enum WiiUKeys {
    /// Mirrors GameManager's own `documentsPath/mlc` construction, which is what gets
    /// handed to `cemu_bridge_initialize()`. If one of these two ever moves, the other
    /// has to move with it or the app would be writing keys where the engine does not
    /// read them.
    static var directoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("mlc")
    }

    static var fileURL: URL? {
        directoryURL?.appendingPathComponent("keys.txt")
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

    /// A keys.txt is a few hundred bytes in practice. The cap exists so that picking a
    /// 4 GB disc image by mistake fails immediately instead of being read into memory
    /// first and rejected afterwards.
    private static let maximumFileSize = 1 << 20 // 1 MiB

    /// Counts the usable 128-bit keys in a keys.txt, applying exactly the rules
    /// `KeyCache_Prepare()` applies in src/Cafe/Filesystem/FST/KeyCache.cpp: truncate
    /// each line at the first # or ;, strip spaces, tabs, dashes and underscores, and
    /// accept what is left if it is 32 hex characters. Anything else - including the
    /// commented-out example key the engine writes into a fresh file - does not count.
    ///
    /// Duplicated here rather than asked of the engine because the engine cannot answer
    /// until it has been initialized, and the answer is needed at import time, which is
    /// usually before any game has ever been launched.
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

    /// Copies a user-picked keys.txt into place and returns how many keys it contains.
    ///
    /// Same ordering discipline as the ROM importer: the security scope granted by the
    /// picker is the only window in which the source is readable at all, so the read
    /// happens inside it. Unlike the ROM importer nothing is staged - the file is small
    /// enough to validate entirely in memory, so an unusable one never touches disk and
    /// cannot clobber a working keys.txt.
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
        // Not necessarily UTF-8: a file exported from a Windows tool is just as likely to
        // be Latin-1. Every character that matters here is ASCII, so fall back rather
        // than reject a file whose keys are perfectly readable.
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

    /// Deletes the installed keys.txt.
    ///
    /// Worth having as a deliberate action rather than something only the Files app can
    /// do: these are the user's console keys sitting in their own sandbox, and they
    /// should be able to take them back out from the same screen that put them there.
    static func removeKeys() throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
