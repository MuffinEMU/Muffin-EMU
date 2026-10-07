import Foundation

/// What a cover source needs to know about one install. `gameID` is `GameMetadata.id`, which
/// is derived from the install's own file/folder name inside Roms (two installs of one title
/// never share it, same scope as `GameMetadata.installKey`), so everything a source caches
/// under `gameID` is already per install, not per title. Sources that need a title-level key
/// (GameTDB ID, title ID) derive it from `romPath`.
struct CoverContext {
    let gameID: String
    let romPath: String
    let dumpDirectoryPath: String?
    let libraryDirectory: URL
    /// The cover the card shows right now, if any.
    let currentCoverPath: String?
}

/// One link in the cover chain. `cachedPath` is synchronous and never touches the network
/// (loadGames() calls it on every scan); `needsAcquire`/`acquire` run in the background pass.
protocol CoverSource {
    var id: String { get }
    /// An already-stored cover from this source, if any.
    func cachedPath(_ context: CoverContext) -> String?
    /// Whether the background pass should call `acquire` for this install now.
    func needsAcquire(_ context: CoverContext) -> Bool
    /// Fetch, generate or extract a cover, store it, and return its path. nil when nothing new.
    func acquire(_ context: CoverContext) async -> String?
}

extension CoverSource {
    func needsAcquire(_ context: CoverContext) -> Bool { false }
    func acquire(_ context: CoverContext) async -> String? { nil }
}

/// The ordered cover chain: first source with a stored cover wins on screen, and the
/// background pass walks the same order to fill gaps. A hand-placed `<gameID>_cover.*`
/// override (GameManager.findCover) always sits above this whole chain.
///
/// Intended order, with the sources still to be added marked:
///   GameTDB HQ -> GameTDB standard -> installed art pack (TODO) -> generated 3D (TODO)
///   -> extracted icon -> generic no-cover (TODO; the card draws the controller glyph today)
/// To add one, implement `CoverSource` and insert it at its place in `sources`.
enum CoverSourceChain {
    static var sources: [CoverSource] = [
        GameTDBHQCoverSource(),
        GameTDBStandardCoverSource(),
        ExtractedIconCoverSource(),
    ]

    static func cachedPath(_ context: CoverContext) -> String? {
        for source in sources {
            if let path = source.cachedPath(context) { return path }
        }
        return nil
    }

    /// Runs on a background task. Returns the new cover path from the first source that
    /// needed work and produced something.
    static func acquireMissing(_ context: CoverContext) async -> String? {
        for source in sources where source.needsAcquire(context) {
            if let path = await source.acquire(context) { return path }
        }
        return nil
    }
}

/// GameTDB coverHQ. Also the single place that downloads from GameTDB (HQ, then standard
/// as its fallback, and the one-time upgrade of older standard covers), so the chain does not
/// hit the service twice for one game.
struct GameTDBHQCoverSource: CoverSource {
    let id = "gametdb-hq"
    func cachedPath(_ c: CoverContext) -> String? { CoverArtFetcher.cachedHQCoverPath(for: c.gameID, in: c.libraryDirectory) }
    func needsAcquire(_ c: CoverContext) -> Bool {
        CoverArtFetcher.shouldAttemptFetch(gameID: c.gameID, romPath: c.romPath, in: c.libraryDirectory)
    }
    func acquire(_ c: CoverContext) async -> String? {
        await CoverArtFetcher.fetchAndCache(gameID: c.gameID, romPath: c.romPath, in: c.libraryDirectory)
    }
}

/// GameTDB standard cover: the stored fallback (and what every pre-HQ install already has).
struct GameTDBStandardCoverSource: CoverSource {
    let id = "gametdb-standard"
    func cachedPath(_ c: CoverContext) -> String? { CoverArtFetcher.cachedStandardCoverPath(for: c.gameID, in: c.libraryDirectory) }
}

/// The console's own icon from meta/iconTex.tga, used only when nothing better exists.
struct ExtractedIconCoverSource: CoverSource {
    let id = "extracted-icon"
    func cachedPath(_ c: CoverContext) -> String? { WiiUIcon.existingCachedIconPath(for: c.gameID, in: c.libraryDirectory) }
    func needsAcquire(_ c: CoverContext) -> Bool { c.currentCoverPath == nil && c.dumpDirectoryPath != nil }
    func acquire(_ c: CoverContext) async -> String? {
        guard let dump = c.dumpDirectoryPath else { return nil }
        return WiiUIcon.cachedIconPath(for: c.gameID, dump: URL(fileURLWithPath: dump), in: c.libraryDirectory)
    }
}
