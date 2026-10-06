import Foundation

/// Automatic box art: on import, derive the game's real GameTDB Game ID from its own
/// dump metadata (see IOSCoverArt.cpp for the derivation, verified against GameTDB's
/// live site rather than guessed) and fetch real cover art for it - no picker, no
/// manual step.
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

    /// Resolution tiers, tried in this order. GameTDB serves `coverHQ` (high resolution
    /// front cover) beside `cover` (standard). Verified with `curl -sI` against the live
    /// service (ARDE01 under US: coverHQ 200, cover 200; coverHQ under EN 404).
    private enum Tier: String, CaseIterable {
        case hq = "coverHQ"
        case standard = "cover"
    }

    /// A cached HQ cover lives at `<id>.hq.<ext>`; a standard one at `<id>.<ext>` (also what
    /// every cover cached before HQ support looks like). The filename is the recorded tier.
    private static func hqPrefix(_ gameID: String) -> String { "\(gameID).hq" }

    /// Marker written after a fetch attempt finds nothing anywhere, so a game with no
    /// listed art doesn't get hit again over the network on every single launch. It
    /// expires (see notFoundRetryInterval) so a title GameTDB adds later is picked up.
    private static func notFoundMarkerPath(for gameID: String, in libraryDirectory: URL) -> URL {
        libraryDirectory.appendingPathComponent(cacheDirectoryName).appendingPathComponent("\(gameID).notfound")
    }

    /// Marker for "this game has standard art cached and GameTDB has no HQ version", so
    /// the one-time background upgrade never re-asks.
    private static func noHQMarkerPath(for gameID: String, in libraryDirectory: URL) -> URL {
        libraryDirectory.appendingPathComponent(cacheDirectoryName).appendingPathComponent("\(gameID).nohq")
    }

    private static let notFoundRetryInterval: TimeInterval = 30 * 24 * 3600
    private static let networkBackoff: TimeInterval = 120

    private static func existing(_ name: String, in dir: URL) -> String? {
        let p = dir.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    private static func cachedHQPath(for gameID: String, in libraryDirectory: URL) -> String? {
        let dir = libraryDirectory.appendingPathComponent(cacheDirectoryName)
        for ext in extensions { if let p = existing("\(hqPrefix(gameID)).\(ext)", in: dir) { return p } }
        return nil
    }

    private static func cachedStandardPath(for gameID: String, in libraryDirectory: URL) -> String? {
        let dir = libraryDirectory.appendingPathComponent(cacheDirectoryName)
        for ext in extensions { if let p = existing("\(gameID).\(ext)", in: dir) { return p } }
        return nil
    }

    private static func cachedImagePath(for gameID: String, in libraryDirectory: URL) -> String? {
        cachedHQPath(for: gameID, in: libraryDirectory) ?? cachedStandardPath(for: gameID, in: libraryDirectory)
    }

    /// Serializes every GameTDB request app-wide (one at a time, with a pause between),
    /// whichever caller (background pass or the picker's manual lookup) makes it.
    private actor RequestGate {
        private var busy = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func acquire() async {
            if !busy { busy = true; return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
    }
    private static let gate = RequestGate()
    private static let requestSpacing: UInt64 = 300_000_000

    private final class NetworkState {
        private let lock = NSLock()
        private var failedAt: Date?
        func noteFailure() { lock.lock(); failedAt = Date(); lock.unlock() }
        func noteSuccess() { lock.lock(); failedAt = nil; lock.unlock() }
        func isBackingOff(_ interval: TimeInterval) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let f = failedAt else { return false }
            return Date().timeIntervalSince(f) < interval
        }
    }
    private static let networkState = NetworkState()

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

    /// True if this game is worth a background fetch attempt: it has no hand-placed
    /// cover, derives to a real ID, and is either missing art (and not recently found
    /// absent), or only has standard-resolution art that was never checked for an HQ
    /// version (the one-time upgrade). Cheap checks first; no network. After an offline
    /// failure this stays false for a couple of minutes so an offline pass doesn't churn.
    static func shouldAttemptFetch(gameID: String, romPath: String, in libraryDirectory: URL) -> Bool {
        let fm = FileManager.default
        if networkState.isBackingOff(networkBackoff) { return false }
        for ext in ["jpg", "jpeg", "png"] where fm.fileExists(atPath: libraryDirectory.appendingPathComponent("\(gameID)_cover.\(ext)").path) {
            return false
        }
        if cachedHQPath(for: gameID, in: libraryDirectory) != nil { return false }
        if cachedStandardPath(for: gameID, in: libraryDirectory) != nil {
            if fm.fileExists(atPath: noHQMarkerPath(for: gameID, in: libraryDirectory).path) { return false }
        } else {
            let marker = notFoundMarkerPath(for: gameID, in: libraryDirectory).path
            if let attrs = try? fm.attributesOfItem(atPath: marker),
               let when = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(when) < notFoundRetryInterval {
                return false
            }
        }
        return deriveGameTdbId(romPath: romPath) != nil
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

    /// The tier/region/extension probe against GameTDB for one explicit Game ID, shared by
    /// the automatic pass and CoverArtPickerView's manual "Try a specific GameTDB ID".
    /// HQ is tried across every region first, then standard. `tiers` limits it (the
    /// upgrade pass asks for HQ only). Returns the bytes, extension and whether it is HQ;
    /// `nil` when everything came back 404; throws only for a transport failure. No
    /// caching or disk I/O.
    static func fetchArt(forGameTdbId tdbId: String) async throws -> (data: Data, ext: String, isHQ: Bool)? {
        try await fetchArt(forGameTdbId: tdbId, tiers: Tier.allCases)
    }

    private static func fetchArt(forGameTdbId tdbId: String, tiers: [Tier]) async throws -> (data: Data, ext: String, isHQ: Bool)? {
        guard tdbId.range(of: "^[A-Za-z0-9]{4,6}$", options: .regularExpression) != nil else { return nil }
        for tier in tiers {
            for region in regions {
                for ext in extensions {
                    guard let url = URL(string: "https://art.gametdb.com/wiiu/\(tier.rawValue)/\(region)/\(tdbId).\(ext)") else { continue }
                    do {
                        if let data = try await fetch(url), isImage(data) {
                            networkState.noteSuccess()
                            return (data, ext, tier == .hq)
                        }
                    } catch {
                        networkState.noteFailure()
                        throw LookupError.network(error)
                    }
                }
            }
        }
        networkState.noteSuccess()
        return nil
    }

    /// Fetches and caches box art for one game, HQ first and standard as the fallback; for
    /// a game that only has standard art cached it tries HQ once and records the outcome.
    /// Returns the new cached file's path, or nil when nothing new was cached. The "not
    /// listed" marker is written only when GameTDB definitively has nothing. A transport
    /// failure or failed write writes no marker, so a later launch retries.
    static func fetchAndCache(gameID: String, romPath: String, in libraryDirectory: URL) async -> String? {
        guard let tdbId = deriveGameTdbId(romPath: romPath) else { return nil }

        let cacheDirectory = libraryDirectory.appendingPathComponent(cacheDirectoryName)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let upgrading = cachedStandardPath(for: gameID, in: libraryDirectory) != nil
        let found: (data: Data, ext: String, isHQ: Bool)?
        do {
            found = try await fetchArt(forGameTdbId: tdbId, tiers: upgrading ? [.hq] : Tier.allCases)
        } catch {
            return nil
        }

        guard let found else {
            if upgrading {
                FileManager.default.createFile(atPath: noHQMarkerPath(for: gameID, in: libraryDirectory).path, contents: nil)
            } else {
                FileManager.default.createFile(atPath: notFoundMarkerPath(for: gameID, in: libraryDirectory).path, contents: nil)
            }
            return nil
        }

        let name = found.isHQ ? "\(hqPrefix(gameID)).\(found.ext)" : "\(gameID).\(found.ext)"
        let cached = cacheDirectory.appendingPathComponent(name)
        guard (try? found.data.write(to: cached, options: .atomic)) != nil else { return nil }
        try? FileManager.default.removeItem(at: notFoundMarkerPath(for: gameID, in: libraryDirectory))
        if found.isHQ {
            // The standard copy is superseded; remove it (and the HQ-absent marker) once the HQ one is safely on disk.
            for ext in extensions { try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("\(gameID).\(ext)")) }
            try? FileManager.default.removeItem(at: noHQMarkerPath(for: gameID, in: libraryDirectory))
        } else {
            FileManager.default.createFile(atPath: noHQMarkerPath(for: gameID, in: libraryDirectory).path, contents: nil)
        }
        return cached.path
    }

    /// JPEG or PNG magic bytes, so an error or captive-portal page served with 200 is never
    /// cached as art.
    private static func isImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(4))
        return b.starts(with: [0xFF, 0xD8, 0xFF]) || b == [0x89, 0x50, 0x4E, 0x47]
    }

    /// 200 returns the body, 404 returns nil (GameTDB has nothing at this URL, a normal
    /// outcome for most region/extension guesses). Anything else (transport error, 5xx,
    /// rate limiting) throws so it is not mistaken for "no art".
    private static func fetch(_ url: URL) async throws -> Data? {
        await gate.acquire()
        defer { Task { try? await Task.sleep(nanoseconds: requestSpacing); await gate.release() } }
        var request = URLRequest(url: url)
        request.setValue("MuffinEMU", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200: return data
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }
}
