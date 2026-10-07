import Foundation
import UIKit

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
    /// The install's region label ("USA", "EUR", "USA/EUR"), when known.
    var region: String? = nil
    /// Names the install is known by (the title's own name, then its folder or file name), best first.
    var titles: [String] = []
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
/// background pass walks the same order to fill gaps. A custom upload (`<gameID>_cover.*`,
/// GameManager.findCover) always sits above this whole chain, as step one.
///
/// The order, after the custom upload:
///   GameTDB HQ -> installed art pack in the chosen style -> GameTDB standard -> extracted icon
///   -> nothing: the cards then draw the gamecontroller.fill glyph on the card gradient, so no card is ever blank.
/// When the player picks "3D box" or "Disc" explicitly, the pack moves above GameTDB HQ: asking
/// for 3D boxes and getting a flat cover whenever GameTDB has one would make the setting pointless.
/// To add a source, implement `CoverSource` and insert it in `sources(for:)`.
enum CoverSourceChain {
    static var sources: [CoverSource] { sources(for: CoverStylePreference.current) }

    static func sources(for style: CoverStylePreference) -> [CoverSource] {
        let pack = ArtPackCoverSource(style: style)
        let hq = GameTDBHQCoverSource()
        let rest: [CoverSource] = [GameTDBStandardCoverSource(), ExtractedIconCoverSource()]
        let base = (style.packBeatsGameTDB ? [pack, hq] : [hq, pack]) + rest
        // An applied art pack wins over everything else except a custom upload; games it doesn't have fall through.
        if let applied = ArtPackApplyStore.appliedID, ArtPackIndex.shared.isInstalled(applied) {
            return [AppliedPackCoverSource(packID: applied)] + base
        }
        return base
    }

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
    func needsAcquire(_ c: CoverContext) -> Bool {
        (c.currentCoverPath == nil || GenericCover.isGeneric(c.currentCoverPath)) && c.dumpDirectoryPath != nil
    }
    func acquire(_ c: CoverContext) async -> String? {
        guard let dump = c.dumpDirectoryPath else { return nil }
        return WiiUIcon.cachedIconPath(for: c.gameID, dump: URL(fileURLWithPath: dump), in: c.libraryDirectory)
    }
}

/// Art from an installed pack, in the chosen style. Matching is by title, using the manifest's own
/// normalisation: the GameTDB entry the game was matched to supplies the most reliable titles
/// (its name in every language), the install's own names come after. Art for the install's region
/// is preferred. Nothing here touches the network; packs are downloaded in Settings.
struct ArtPackCoverSource: CoverSource {
    let id = "art-pack"
    let style: CoverStylePreference

    func cachedPath(_ c: CoverContext) -> String? {
        guard ArtPackIndex.shared.hasAnyPack else { return nil }
        return ArtPackMatching.hit(for: c, style: style)?.path
    }
}

/// Art from the pack the player applied, ahead of the rest of the chain.
struct AppliedPackCoverSource: CoverSource {
    let id = "applied-art-pack"
    let packID: String

    func cachedPath(_ c: CoverContext) -> String? {
        guard let style = ArtPackIndex.shared.meta(packID)?.style else { return nil }
        var regions = RegionCode.codes(in: c.region)
        if regions.isEmpty, let match = GameDataStore.shared.match(for: c.gameID), let r = RegionCode.code(forGameTdbId: match.tdbID) { regions = [r] }
        return ArtPackIndex.shared.lookup(candidates: ArtPackMatching.candidates(for: c), styles: [style], regions: regions, onlyPack: packID)?.path
    }
}

enum ArtPackMatching {
    /// Normalised title candidates, most trustworthy first.
    static func candidates(for c: CoverContext) -> [String] {
        var out: [String] = []
        if let info = GameDataStore.shared.info(for: c.gameID) {
            let preferred = GameInfo.preferredLanguages + ["EN"]
            for lang in preferred { if let t = info.titles[lang] { out.append(ArtTitleNormalizer.normalize(t)) } }
            out.append(ArtTitleNormalizer.normalize(info.name))
            for t in info.titles.values { out.append(ArtTitleNormalizer.normalize(t)) }
        }
        out.append(contentsOf: c.titles.map(ArtTitleNormalizer.normalize))
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func hit(for c: CoverContext, style: CoverStylePreference) -> PackArtHit? {
        var regions = RegionCode.codes(in: c.region)
        if regions.isEmpty, let match = GameDataStore.shared.match(for: c.gameID), let r = RegionCode.code(forGameTdbId: match.tdbID) { regions = [r] }
        return ArtPackIndex.shared.lookup(candidates: candidates(for: c), styles: style.packStyles, regions: regions)
    }

    private static let boxLock = NSLock()
    private static var boxCache: [String: String] = [:]
    private static var boxCacheStamp = ""

    /// `box3DPath` remembered per game, for a card that asks on every render. Dropped whenever packs
    /// or game data change (`revision` is the game data's change counter).
    static func cachedBox3DPath(for game: GameMetadata, revision: Int) -> String? {
        let stamp = "\(ArtPackIndex.shared.generation)|\(revision)|\(ArtPackApplyStore.appliedID ?? "")"
        boxLock.lock(); defer { boxLock.unlock() }
        if boxCacheStamp != stamp { boxCache = [:]; boxCacheStamp = stamp }
        if let hit = boxCache[game.id] { return hit.isEmpty ? nil : hit }
        boxLock.unlock()
        let path = box3DPath(for: game)
        boxLock.lock()
        boxCache[game.id] = path ?? ""
        return path
    }

    /// 3D pack art for a game, whatever the cover style is: what the "3D boxes" card style draws.
    static func box3DPath(for game: GameMetadata) -> String? {
        guard ArtPackIndex.shared.hasAnyPack else { return nil }
        let c = CoverContext(gameID: game.id, romPath: game.romPath, dumpDirectoryPath: nil, libraryDirectory: URL(fileURLWithPath: "/"),
                             currentCoverPath: nil, region: game.region, titles: [game.displayTitle, game.title].compactMap { $0 })
        let regions = RegionCode.codes(in: game.region)
        let names = candidates(for: c)
        if let applied = ArtPackApplyStore.appliedID, ArtPackIndex.shared.meta(applied)?.style == "3d",
           let hit = ArtPackIndex.shared.lookup(candidates: names, styles: ["3d"], regions: regions, onlyPack: applied) {
            return hit.path
        }
        return ArtPackIndex.shared.lookup(candidates: names, styles: ["3d"], regions: regions)?.path
    }
}

/// Older builds stored a generic no-cover file as a game's cover; it still counts as no cover.
enum GenericCover {
    static func isGeneric(_ path: String?) -> Bool {
        guard let path else { return false }
        return (path as NSString).deletingLastPathComponent == ArtLocations.genericDirectory.path
    }
}
