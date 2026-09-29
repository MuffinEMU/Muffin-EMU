import Foundation

/// Automatic box art: on import, derive the game's real GameTDB Game ID from its own
/// dump metadata (see IOSCoverArt.cpp for the derivation, verified against GameTDB's
/// live site rather than guessed) and fetch real cover art for it - no picker, no
/// manual step. A picker UI was considered and rejected.
///
/// This only ever adds a cover for games GameManager.findCover() couldn't already
/// answer for (a hand-placed override always wins, and this never touches a game with
/// one), so it can safely run in the background after loadGames() and quietly do
/// nothing when it has nothing useful to offer - a homebrew .rpx, or any dump whose
/// metadata doesn't resolve to a real ID.
enum CoverArtFetcher {
    /// Separate from WiiUIcon's own ".covers" cache directory (the in-game icon
    /// extracted from meta/iconTex.tga) so the two can never collide on the same
    /// cached filename for the same game - this is real box art, that is the console's
    /// own small icon, and findCover() below chooses between them in a fixed order.
    private static let cacheDirectoryName = ".boxart"

    /// GameTDB's own regions, tried in this order - the first that resolves wins. Not
    /// every game's art is filed under every region, which is why this is a list and
    /// not a single guess (see IOSCoverArt.cpp's header comment for how this was
    /// verified against the real service rather than assumed).
    private static let regions = ["US", "EN", "JA", "DE", "FR"]
    private static let extensions = ["jpg", "png"]

    /// Marker written after a fetch attempt finds nothing anywhere, so a game with no
    /// listed art (homebrew misidentified as a real title, a very obscure release)
    /// doesn't get hit again over the network on every single launch.
    private static func notFoundMarkerPath(for gameID: String, in libraryDirectory: URL) -> URL {
        libraryDirectory.appendingPathComponent(cacheDirectoryName).appendingPathComponent("\(gameID).notfound")
    }

    private static func cachedImagePath(for gameID: String, in libraryDirectory: URL) -> String? {
        let cacheDirectory = libraryDirectory.appendingPathComponent(cacheDirectoryName)
        for ext in extensions {
            let candidate = cacheDirectory.appendingPathComponent("\(gameID).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    /// Wraps cemu_bridge_derive_gametdb_id - see CemuBridge.h for what it does and why
    /// it can honestly return nothing for a game with no real identity to look up.
    private static func deriveGameTdbId(romPath: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 7)
        let ok = romPath.withCString { cPath in
            buffer.withUnsafeMutableBufferPointer { buf in
                cemu_bridge_derive_gametdb_id(cPath, buf.baseAddress, buf.count)
            }
        }
        guard ok else { return nil }
        return String(cString: buffer)
    }

    /// Already-cached art (or a already-known "nothing to find") for a game, without
    /// touching the network - what GameManager.findCover() calls synchronously on
    /// every loadGames() scan, same as it already does for WiiUIcon.
    static func cachedCoverPath(for gameID: String, romPath: String, in libraryDirectory: URL) -> String? {
        cachedImagePath(for: gameID, in: libraryDirectory)
    }

    /// True if this game is worth a background fetch attempt at all: it derives to a
    /// real ID, and neither a cached image nor a "checked, nothing there" marker
    /// already exists for it. Called synchronously (cheap - no network) so
    /// GameManager knows which games to hand to fetchAndCache without doing the actual
    /// fetch inline during loadGames().
    static func shouldAttemptFetch(gameID: String, romPath: String, in libraryDirectory: URL) -> Bool {
        guard deriveGameTdbId(romPath: romPath) != nil else { return false }
        if cachedImagePath(for: gameID, in: libraryDirectory) != nil { return false }
        if FileManager.default.fileExists(atPath: notFoundMarkerPath(for: gameID, in: libraryDirectory).path) { return false }
        return true
    }

    /// Thrown by fetchArt(forGameTdbId:) for an actual transport failure (offline,
    /// DNS, timeout) - kept distinct from that same function's plain `nil` return
    /// (every region/extension combination came back 404/empty, i.e. GameTDB
    /// genuinely has nothing under that ID), so a caller that has a person waiting on
    /// the answer - CoverArtPickerView's manual "Try a specific GameTDB ID" - can
    /// honestly say "you're offline" instead of "GameTDB doesn't have this," which
    /// would be a real, checkable claim this couldn't back up.
    enum LookupError: LocalizedError {
        case network(Error)
        var errorDescription: String? {
            switch self {
            case .network(let error):
                return "Couldn't reach GameTDB: \(error.localizedDescription)"
            }
        }
    }

    /// The region/extension probe against GameTDB for one explicit Game ID - the
    /// same loop fetchAndCache() below has always run for an ID it derived itself,
    /// extracted so CoverArtPickerView's manual "Try a specific GameTDB ID" path can
    /// reuse it for an ID a person typed in, rather than duplicating it. Returns the
    /// found bytes and which extension they came back as on success, `nil` when
    /// every combination tried came back 404/empty (a normal, expected outcome - see
    /// `fetch()` below), and throws only for a real transport failure. Does no
    /// caching or disk I/O of any kind - callers decide what to do with the bytes.
    static func fetchArt(forGameTdbId tdbId: String) async throws -> (data: Data, ext: String)? {
        for region in regions {
            for ext in extensions {
                guard let url = URL(string: "https://art.gametdb.com/wiiu/cover/\(region)/\(tdbId).\(ext)") else { continue }
                do {
                    if let data = try await fetch(url), !data.isEmpty {
                        return (data, ext)
                    }
                } catch {
                    throw LookupError.network(error)
                }
            }
        }
        return nil
    }

    /// Fetches and caches real box art for one game, trying region/extension
    /// combinations in order and stopping at the first one that actually resolves.
    /// Returns the cached file's path on success, nil on any failure (no network, no
    /// art listed anywhere tried) - writes the "nothing there" marker in the latter
    /// case so the next launch doesn't try again for nothing.
    ///
    /// Reuses fetchArt(forGameTdbId:) for the actual probing rather than running its
    /// own copy of the loop. `try?` here restores this path's original behavior of
    /// treating a network failure exactly like "nothing found anywhere" - a
    /// background fetch has nobody to report "you're offline" to, and gets another
    /// chance on a later launch regardless. One difference from the pre-extraction
    /// version: that version kept trying further region/extension combinations if
    /// the disk write of an already-found image failed; this one does not, since a
    /// write failure right after a successful fetch (disk full, permissions) is not
    /// something a different region's bytes would fix either. Immaterial in
    /// practice - the write is a few KB to a directory this same call just created -
    /// but noted because it is a real, if unreachable, behavior change.
    static func fetchAndCache(gameID: String, romPath: String, in libraryDirectory: URL) async -> String? {
        guard let tdbId = deriveGameTdbId(romPath: romPath) else { return nil }

        let cacheDirectory = libraryDirectory.appendingPathComponent(cacheDirectoryName)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        if let found = (try? await fetchArt(forGameTdbId: tdbId)) ?? nil {
            let cached = cacheDirectory.appendingPathComponent("\(gameID).\(found.ext)")
            if (try? found.data.write(to: cached, options: .atomic)) != nil {
                return cached.path
            }
        }

        // Tried every region/extension combination and found nothing real - remember
        // that rather than hitting the network again on every future launch.
        FileManager.default.createFile(atPath: notFoundMarkerPath(for: gameID, in: libraryDirectory).path, contents: nil)
        return nil
    }

    /// A 404 from GameTDB is a normal, expected outcome (most region/extension guesses
    /// miss), not a network error - only actual transport failures should throw here,
    /// so a non-200 response is treated the same as "nothing at this URL" rather than
    /// surfaced as data (an HTML error page is never mistaken for image bytes: it is
    /// simply discarded by the 200-only check below).
    private static func fetch(_ url: URL) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }
}
