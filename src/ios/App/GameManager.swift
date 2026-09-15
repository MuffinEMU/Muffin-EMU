import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct GameMetadata: Codable, Identifiable {
    let id: String
    let title: String
    let romPath: String
    var coverPath: String?
    // Was a hardcoded "Unknown" for every game. Optional now: nil means "not derived
    // yet, or the dump has no console region to report" and the card hides the label
    // rather than showing a placeholder value. See GameManager.enrichMissingCoverArt.
    var region: String?
    let releaseDate: String
    let genre: String
    var isFavorite: Bool = false
    // The base game's title ID (already reduced via cemu_bridge_derive_base_title_id -
    // never a DLC/update ID) - nil for a title the bridge couldn't parse, which import
    // matching then has no choice but to fall back to manual selection for. See
    // DlcUpdateImport.swift.
    var titleId: UInt64?
    /// Root of the dumped title directory (code/content/meta, or a flat NUS dump) -
    /// nil for a single-file dump (.wux/.wud/.wua), whose meta/ lives inside the
    /// container where only the engine can read it. Lets the background enrichment
    /// pass in enrichMissingCoverArt() find meta/iconTex.tga without re-deriving a
    /// dump path from romPath.
    var dumpDirectoryPath: String?
    /// The title's real display name, from meta.xml via cemu_bridge_get_title_name -
    /// filled in by the background enrichment pass, same as `region` above. nil until
    /// that pass has run, or if the title's own meta.xml has no name at all: `title`
    /// (the filename) is what the card falls back to showing, and what search always
    /// matches against, so a dump with no derivable name is never unfindable.
    var displayTitle: String?
    /// The ROM/dump's own file creation date, for "recently added" sorting. Not part
    /// of CodingKeys - games.json isn't actually used (see gameListFile) and this is
    /// cheap enough to just re-read from the filesystem on every loadGames().
    var addedDate: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, romPath, coverPath, region, releaseDate, genre, titleId, dumpDirectoryPath, displayTitle
    }
}

/// Mid-flight state of GameManager.importROM()'s own byte copy. Published so the UI
/// can show something other than a frozen screen while a multi-GB .wud/.wux/folder
/// moves - the copy itself no longer runs on the main actor (see importROM), but
/// something still has to tell the UI it is happening.
enum ImportState: Equatable {
    case idle
    case copying(name: String)
}

/// Region and real title name are both derived from a dump's own meta.xml via the
/// bridge - real answers, but not free ones (region needs cemu_bridge_inspect_title to
/// open and parse the title; the name needs a second bridge call on top of that) - so
/// both are cached by game ID the first time they're derived, rather than re-derived
/// on every launch. UserDefaults, not a file: this is a handful of short strings per
/// game, nowhere near what would justify its own cache file the way CoverArtFetcher's
/// image cache does.
private enum LibraryMetadataCache {
    private static let regionKey = "muffin.library.regionByGameID"
    private static let titleNameKey = "muffin.library.titleNameByGameID"

    /// nil means "never checked yet." "" means "checked - meta.xml genuinely has
    /// nothing here." Both are real, distinct answers, and the difference is the
    /// whole reason this isn't just a plain optional cache: only the first one should
    /// ever trigger another trip through the bridge.
    static func cachedRegion(for gameID: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: regionKey) as? [String: String])?[gameID]
    }

    static func setCachedRegion(_ region: String?, for gameID: String) {
        var stored = (UserDefaults.standard.dictionary(forKey: regionKey) as? [String: String]) ?? [:]
        stored[gameID] = region ?? ""
        UserDefaults.standard.set(stored, forKey: regionKey)
    }

    static func cachedTitleName(for gameID: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: titleNameKey) as? [String: String])?[gameID]
    }

    static func setCachedTitleName(_ name: String?, for gameID: String) {
        var stored = (UserDefaults.standard.dictionary(forKey: titleNameKey) as? [String: String]) ?? [:]
        stored[gameID] = name ?? ""
        UserDefaults.standard.set(stored, forKey: titleNameKey)
    }
}

@MainActor
class GameManager: ObservableObject {
    @Published var games: [GameMetadata] = []
    @Published var favorites: [GameMetadata] = []
    @Published var isLoading = false
    @Published var currentGame: GameMetadata?
    @Published var emulationState: EmulationState = .idle
    /// Last human-readable message from the engine bridge (e.g. "engine not built yet").
    @Published var lastStatusMessage: String = ""
    /// Real emulator frame rate, polled from the bridge once a second while a title
    /// is running (see startFrameRateMonitor()). 0 whenever nothing is rendering.
    @Published private(set) var frameRate: Int = 0
    /// Refreshed alongside `frameRate`. See `EmulatorProgress` below for why a second
    /// source of frame information is not redundant with the first.
    @Published private(set) var progress = EmulatorProgress()
    @Published private(set) var importState: ImportState = .idle
    /// Set by the UI (ContentView) to ask "a game/dump named `name` already exists in
    /// the library - replace it?" before importROM() overwrites anything. Returning
    /// false, or leaving this nil (nobody wired up a prompt), cancels the import
    /// outright rather than ever silently deleting what was already there.
    var confirmOverwrite: ((String) async -> Bool)?
    private var frameRateTimer: Timer?

    private let romsDirectory = "Roms"
    private let gameListFile = "games.json"
    private var emulationEngine: EmulationEngine?
    private var surfaceRegistered = false
    private static let favoriteIDsKey = "muffin.library.favoriteGameIDs"

    init() {
        emulationEngine = EmulationEngine()
        Task {
            await loadGames()
        }
    }

    func loadGames() async {
        isLoading = true
        defer { isLoading = false }

        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let romsPath = documentsPath.appendingPathComponent(romsDirectory)

        try? fileManager.createDirectory(at: romsPath, withIntermediateDirectories: true)

        // Same treatment for the keys folder, and for the same reason the Roms folder
        // gets it: a folder that does not exist is not a folder anyone can drop a file
        // into. This is the first code to run that touches Documents, so it is what
        // makes Documents/keys visible in the Files app on a fresh install, before any
        // game has been launched and before the engine has ever been initialized.
        WiiUKeys.ensureDirectoryExists()

        // Without this, every encrypted disc image (.wud/.wux/.iso - i.e. almost every
        // real Wii U game) fails TitleInfo's construction with NO_DISC_KEY right here,
        // even when keys.txt is present and correct: KeyCache_Reload() was previously
        // only ever called from the launch path (IOSTitleLaunch.cpp), never before this
        // scan. That silently broke both DLC/update title-ID matching below and cover-
        // art derivation (IOSCoverArt.cpp does the same TitleInfo construction) for
        // every game on first launch, with no error surfaced anywhere - it just looked
        // like "the updates and DLC stuff doesn't work" and "no cover art ever shows up
        // until later." Reusing the exact same reload already proven safe on the launch
        // path, not writing a new one.
        _ = cemu_bridge_reload_and_count_keys()

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: romsPath,
                includingPropertiesForKeys: nil
            )

            var discoveredGames: [GameMetadata] = []

            for item in contents {
                // A Roms entry is either a single-file dump or a dumped game DIRECTORY.
                // For a directory the engine still boots an .rpx, but it must be the one
                // sitting inside code/ so Cemu sees the real layout next to it - boot it
                // from anywhere else and it falls back to standalone mode and logs
                // "incorrect layout or missing meta files", losing the title metadata.
                let gameID: String
                let bootPath: String
                // The dump directory, when the entry is one. Only a directory dump keeps
                // its meta/ on disk where the icon can be read from; a single-file dump
                // keeps meta/ inside the container, where only the engine can reach it.
                let dumpDirectory: URL?

                var isDirectory: ObjCBool = false
                _ = fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)

                if isDirectory.boolValue {
                    if Self.looksLikeWiiUDump(item), let rpx = Self.executableInDump(item) {
                        gameID = item.lastPathComponent
                        bootPath = rpx.path
                        dumpDirectory = item
                    } else if let tmd = Self.titleTmdInDump(item) {
                        // NUS dump: boot path points straight at title.tmd, matching
                        // TitleInfo::DetectFormat's own NUS-format detection.
                        gameID = item.lastPathComponent
                        bootPath = tmd.path
                        dumpDirectory = item
                    } else {
                        continue
                    }
                } else {
                    let pathExtension = item.pathExtension.lowercased()
                    guard Self.supportedROMExtensions.contains(pathExtension) else { continue }
                    gameID = item.deletingPathExtension().lastPathComponent
                    bootPath = item.path
                    dumpDirectory = nil
                }

                let addedDate = (try? fileManager.attributesOfItem(atPath: item.path))?[.creationDate] as? Date

                let gameMetadata = GameMetadata(
                    id: gameID,
                    title: gameID,
                    romPath: bootPath,
                    coverPath: findCover(for: gameID, romPath: bootPath, in: romsPath),
                    region: Self.nonEmptyOrNil(LibraryMetadataCache.cachedRegion(for: gameID)),
                    releaseDate: "Unknown",
                    genre: "Game",
                    titleId: Self.deriveBaseTitleId(romPath: bootPath),
                    dumpDirectoryPath: dumpDirectory?.path,
                    displayTitle: Self.nonEmptyOrNil(LibraryMetadataCache.cachedTitleName(for: gameID)),
                    addedDate: addedDate
                )

                discoveredGames.append(gameMetadata)
            }

            // Favorites used to be rebuilt false on every scan - nothing anywhere
            // wrote them back out, so a favorited game forgot it the moment the app
            // relaunched. Applied here, against a real on-disk record, before the
            // array is even published.
            let favoriteIDs = Self.loadFavoriteIDs()
            for index in discoveredGames.indices {
                discoveredGames[index].isFavorite = favoriteIDs.contains(discoveredGames[index].id)
            }

            self.games = discoveredGames.sorted { $0.title < $1.title }
            self.favorites = self.games.filter { $0.isFavorite }
            enrichMissingCoverArt()
        } catch {
            print("Error scanning Roms directory: \(error)")
        }
    }

    /// A dumped Wii U title is a directory containing code/, content/ and meta/.
    /// code/ is the one that actually matters (it holds the .rpx we boot); meta/ is
    /// required too because its absence is exactly what makes Cemu drop to standalone.
    nonisolated static func looksLikeWiiUDump(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        for required in ["code", "meta"] {
            let sub = directory.appendingPathComponent(required)
            guard fileManager.fileExists(atPath: sub.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return false
            }
        }
        return true
    }

    /// The .rpx inside a dump's code/ directory. Case matters on nothing here, but the
    /// extension does: code/ also holds .rpl libraries, which are not entry points.
    nonisolated static func executableInDump(_ directory: URL) -> URL? {
        let codePath = directory.appendingPathComponent("code")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: codePath,
            includingPropertiesForKeys: nil
        )) ?? []

        return entries
            .filter { $0.pathExtension.lowercased() == "rpx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// A decrypted NUS dump - the flat "title.tmd plus a pile of .app files" layout
    /// produced by NUS downloaders/decryptors, as opposed to the code/content/meta
    /// layout above. TitleInfo::DetectFormat (TitleInfo.cpp) already recognizes this
    /// shape whenever it is pointed straight at title.tmd - boost::iequals, so the
    /// match here is case-insensitive too, matching the engine rather than guessing.
    nonisolated static func titleTmdInDump(_ directory: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries.first { $0.lastPathComponent.caseInsensitiveCompare("title.tmd") == .orderedSame }
    }

    nonisolated static func looksLikeNUSDump(_ directory: URL) -> Bool {
        titleTmdInDump(directory) != nil
    }

    /// Wraps cemu_bridge_derive_title_id + cemu_bridge_derive_base_title_id (see
    /// CemuBridge.h) to get a game's identity for DLC/update matching in one call.
    /// Already reduced to the BASE title ID - a library entry is always a base game
    /// (see the loadGames() switch above), so there is nothing here that could itself
    /// be a DLC/update needing the reduction skipped.
    private static func deriveBaseTitleId(romPath: String) -> UInt64? {
        var titleId: UInt64 = 0
        let ok = romPath.withCString { cPath in
            cemu_bridge_derive_title_id(cPath, &titleId)
        }
        guard ok else { return nil }
        return cemu_bridge_derive_base_title_id(titleId)
    }

    /// Art for a game's card, in the order a person would expect it: whatever they put
    /// there themselves first, then real box art already fetched. The dump's own icon
    /// (meta/iconTex.tga) is a THIRD tier below both, applied later by the background
    /// enrichment pass rather than here - see enrichMissingCoverArt().
    ///
    /// Before this existed at all, nothing in the app ever wrote a `<gameID>_cover.png`,
    /// so every card fell through to the placeholder controller glyph no matter what
    /// was installed.
    private func findCover(for gameID: String, romPath: String, in directory: URL) -> String? {
        let fileManager = FileManager.default

        // A hand-placed cover wins. Someone who dropped a file in specifically to
        // override the icon should not be overruled by the icon.
        for ext in ["jpg", "jpeg", "png"] {
            let coverPath = directory.appendingPathComponent("\(gameID)_cover.\(ext)")
            if fileManager.fileExists(atPath: coverPath.path) {
                return coverPath.path
            }
        }

        // Real box art already fetched by CoverArtFetcher (see enrichMissingCoverArt())
        // beats the in-game icon - it is what a person actually recognizes the game by.
        if let boxArt = CoverArtFetcher.cachedCoverPath(for: gameID, romPath: romPath, in: directory) {
            return boxArt
        }

        // No icon fallback here any more. Decoding meta/iconTex.tga used to happen
        // inline, right here, on the main actor, for every dump loadGames() found -
        // real work (a TGA decode, sometimes a PNG write) blocking the whole library
        // from appearing. It happens in enrichMissingCoverArt() instead, off the main
        // actor, using GameMetadata.dumpDirectoryPath.
        return nil
    }

    /// Kicks off a background box-art fetch for every game loadGames() just found that
    /// doesn't already have real cover art (or a remembered "nothing to find" result -
    /// see CoverArtFetcher.shouldAttemptFetch()). Runs after the fact rather than
    /// inline in loadGames() itself, since loadGames() has to stay synchronous-feeling
    /// (it runs on every launch and blocks the library from appearing) and a handful of
    /// network fetches at even a few hundred ms each would make every launch feel
    /// slower for a feature that is purely cosmetic upside, never something the app
    /// depends on to function.
    private func enrichMissingCoverArt() {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let romsPath = documentsPath.appendingPathComponent(romsDirectory)

        // One Task, sequential, not one Task per game. CoverArtFetcher's ID lookup
        // constructs a real TitleInfo, and TitleInfo's constructor auto-mounts through
        // fsc_mount() as a side effect of parsing meta.xml.
        //
        // CORRECTION to what this comment said before: fsc.cpp is NOT unlocked. It
        // declares `std::recursive_mutex s_fscMutex` (fsc.cpp:69) and takes it at 21
        // sites, including wrapped directly around the tree mutation this comment used
        // to blame:
        //
        //     fscEnter();
        //     FSCMountPathNode* node = fsc_createMountPath(parsedMountPath, priority);
        //     node->AssignDevice(fscDevice, ctx, targetPathWithSlash);
        //     fscLeave();
        //
        // So concurrent TitleInfo constructions were already serialised by that mutex,
        // and a data race there was not what produced the signal 11 in the crash log.
        //
        // The actual cause was a null root: s_fscRootNodePerPrio is `{}` at file scope
        // and is only ever populated by fsc_reset() <- fsc_init() <-
        // CafeSystem::Initialize(), which runs at TITLE BOOT. Cover art builds a
        // TitleInfo during loadGames at app launch, before any title has booted, so
        // fsc_createMountPath read a null root and dereferenced nodeParent->subnodes.
        // Deterministic, single-threaded, on the first call - which is why it crashed
        // every launch rather than intermittently. Fixed in fsc.cpp by
        // fsc_ensureRootNodes(), which allocates any missing root under that same mutex.
        //
        // The sequential pass below is KEPT, on its own merits rather than as the crash
        // fix: one TitleInfo mount at a time is less startup load than N concurrent
        // ones, and doing the eligibility check off the main actor keeps it off the UI
        // thread. It would not, by itself, have fixed a null dereference - the first
        // call still hits it.
        //
        // The correction matters because "fsc.cpp has no locking anywhere" is the kind
        // of premise that gets a second mutex added to a file that already has one, or
        // gets the next crash in it misdiagnosed.
        let candidates = games
        guard !candidates.isEmpty else { return }

        Task.detached { [weak self, romsPath] in
            for game in candidates {
                // Box art, when there's a real ID to look it up by and nothing already
                // cached (or already known-missing) for it.
                if CoverArtFetcher.shouldAttemptFetch(gameID: game.id, romPath: game.romPath, in: romsPath),
                   let coverPath = await CoverArtFetcher.fetchAndCache(gameID: game.id, romPath: game.romPath, in: romsPath) {
                    await self?.applyCoverPath(coverPath, forGameID: game.id)
                } else if game.coverPath == nil, let dumpPath = game.dumpDirectoryPath {
                    // No box art (or none to look up) and nothing already found by
                    // loadGames()'s own findCover() - fall back to the console's own
                    // icon. This is the TGA decode that used to run inline inside
                    // loadGames() on the main actor for every freshly-discovered dump;
                    // it runs here instead so the library appears immediately and
                    // icons fill in afterward rather than the whole scan waiting on
                    // every dump's decode.
                    if let iconPath = WiiUIcon.cachedIconPath(
                        for: game.id, dump: URL(fileURLWithPath: dumpPath), in: romsPath
                    ) {
                        await self?.applyCoverPath(iconPath, forGameID: game.id)
                    }
                }

                // Region and the title's real name both come from the same
                // cemu_bridge_inspect_title()/cemu_bridge_get_title_name() pass over
                // meta.xml - real, but not free, so both are cached by game ID (see
                // LibraryMetadataCache) and only re-derived once per game, ever.
                if LibraryMetadataCache.cachedRegion(for: game.id) == nil
                    || LibraryMetadataCache.cachedTitleName(for: game.id) == nil {
                    await self?.deriveAndApplyRegionAndTitleName(for: game)
                }
            }
        }
    }

    /// Applies a newly-found cover path (box art or the console's own icon) to `games`
    /// and, if present, its mirror in `favorites` - the two arrays hold independent
    /// copies of the same struct, so a change to one is invisible to the other unless
    /// both are updated. Runs on the main actor like every other mutation of
    /// `games`/`favorites`; the background pass in enrichMissingCoverArt() hops here
    /// with `await` rather than mutating either array directly off-actor.
    private func applyCoverPath(_ coverPath: String, forGameID gameID: String) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].coverPath = coverPath
        if let favIndex = favorites.firstIndex(where: { $0.id == gameID }) {
            favorites[favIndex].coverPath = coverPath
        }
    }

    /// Derives `game`'s real region and title name (both from meta.xml, via the
    /// bridge) off the main actor, caches whatever was found - including a definite
    /// "nothing there," so a title with no name or no region isn't re-inspected on
    /// every future launch - then applies the result on the main actor. Called at most
    /// once per game per cold start of the cache; see enrichMissingCoverArt().
    private nonisolated func deriveAndApplyRegionAndTitleName(for game: GameMetadata) async {
        var version: UInt16 = 0
        var regionBitmask: Int32 = 0
        var invalidReason: Int32 = 0
        let inspected = game.romPath.withCString { cPath in
            cemu_bridge_inspect_title(cPath, nil, &version, &regionBitmask, &invalidReason)
        }
        let region = inspected ? Self.regionLabel(forBitmask: regionBitmask) : nil
        LibraryMetadataCache.setCachedRegion(region, for: game.id)

        // 256 bytes is generous for a Wii U meta.xml longname (in practice UTF-8 and a
        // few dozen bytes at most) - this only needs to be big enough to never
        // truncate a real name, not tight.
        var nameBuffer = [CChar](repeating: 0, count: 256)
        let hasName = game.romPath.withCString { cPath in
            nameBuffer.withUnsafeMutableBufferPointer { buffer in
                cemu_bridge_get_title_name(cPath, buffer.baseAddress, buffer.count)
            }
        }
        let titleName = hasName ? Self.nonEmptyOrNil(String(cString: nameBuffer)) : nil
        LibraryMetadataCache.setCachedTitleName(titleName, for: game.id)

        await MainActor.run { [weak self] in
            guard let self else { return }
            if let index = self.games.firstIndex(where: { $0.id == game.id }) {
                self.games[index].region = region
                self.games[index].displayTitle = titleName
            }
            if let favIndex = self.favorites.firstIndex(where: { $0.id == game.id }) {
                self.favorites[favIndex].region = region
                self.favorites[favIndex].displayTitle = titleName
            }
        }
    }

    /// Human-readable region for the console-region bitmask cemu_bridge_inspect_title
    /// hands back (0x1 JPN, 0x2 USA, 0x4 EUR, 0x8 CHN, 0x10 KOR, 0x20 TWN). A real dump
    /// is very often flagged for more than one region at once, so every set bit is
    /// listed rather than only the first one found. nil for 0 (nothing set) - the card
    /// treats that as "no known region" and hides the label, rather than showing an
    /// empty string.
    private nonisolated static func regionLabel(forBitmask bitmask: Int32) -> String? {
        var labels: [String] = []
        if bitmask & 0x1  != 0 { labels.append("JPN") }
        if bitmask & 0x2  != 0 { labels.append("USA") }
        if bitmask & 0x4  != 0 { labels.append("EUR") }
        if bitmask & 0x8  != 0 { labels.append("CHN") }
        if bitmask & 0x10 != 0 { labels.append("KOR") }
        if bitmask & 0x20 != 0 { labels.append("TWN") }
        return labels.isEmpty ? nil : labels.joined(separator: "/")
    }

    /// nil for both nil and "" - the second is LibraryMetadataCache's own way of
    /// recording "checked, there's nothing here" (see that type), and both mean the
    /// same thing to a caller that just wants a value to show or store.
    private nonisolated static func nonEmptyOrNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    enum ROMImportError: LocalizedError {
        case invalidROM
        case notAWiiUDump(String)
        case accessDenied
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidROM:
                // Deliberately one fixed sentence rather than a per-reason variant. The
                // check runs against the copy we already made, and every way it can fail
                // - unsupported extension, supported extension over the wrong bytes -
                // means the same thing to the person holding the iPad.
                return "This is not a valid Wii U ROM format."
            case .notAWiiUDump(let name):
                return "\"\(name)\" doesn't look like a Wii U dump - a dumped game folder has code/, content/ and meta/ inside it, or (for a decrypted NUS dump) a title.tmd alongside its .app files."
            case .accessDenied:
                return "Couldn't access that file."
            case .copyFailed(let error):
                return "Couldn't copy the ROM: \(error.localizedDescription)"
            }
        }
    }

    /// .wux is the compressed dump format most Wii U rips are distributed in and was
    /// missing here, so importing one failed with "isn't a supported ROM format" even
    /// though the picker had happily handed it over.
    ///
    /// .wuhb (Wii U Homebrew Bundle) is a single-file container the core already reads -
    /// src/Cafe/Filesystem/WUHB/WUHBReader.cpp and fscDeviceWuhb.cpp are upstream Cemu,
    /// not new engineering - so this is only the iOS-side import allowlist catching up to
    /// what the engine underneath it already supports.
    ///
    /// .elf is the same story: IOSTitleLaunch_PrepareForegroundTitle already recognizes
    /// CafeTitleFileType::ELF and boots it through the exact same
    /// PrepareForegroundTitleFromStandaloneRPX() path as a .rpx (desktop's own file-open
    /// filter has always been "*.rpx;*.elf" together) - this allowlist was just never
    /// updated to let one reach that code.
    static let supportedROMExtensions: Set<String> = ["wux", "wud", "wua", "iso", "rpx", "wuhb", "elf"]

    /// Staging directory inside Documents/Roms. A single-file import lands here first
    /// and is only moved up into Roms/ once it has passed validation. Two reasons: a
    /// rejected import can never clobber an existing ROM that happens to share its
    /// filename, and the library scan can never catch a half-copied file mid-import.
    ///
    /// Leading dot so it reads as scratch space. loadGames() skips it regardless - a
    /// directory only counts as a game if it has code and meta subdirectories inside.
    private static let stagingDirectoryName = ".incoming"

    /// First count bytes of url, or nil if they cannot be read (missing, unreadable, or
    /// shorter than count). Only ever called on a file already copied into our own
    /// sandbox, so a failure here says something about the file, not about permissions.
    private nonisolated static func fileMagic(at url: URL, count: Int = 4) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: count), data.count == count else {
            return nil
        }
        return data
    }

    /// Validates an already-copied ROM file.
    ///
    /// The extension check is mandatory: it is the only signal that exists for every
    /// format we accept. The magic-byte check is an extra gate applied ONLY where there
    /// is a signature worth betting an import on. An .rpx is a Nintendo-flavoured ELF
    /// and keeps the standard ELF e_ident (0x7F 45 4C 46) at offset 0; a .wux opens
    /// with the ASCII magic WUX0.
    ///
    /// A .wud, .wua or .iso passes on the extension alone, on purpose. There is no
    /// offset-0 signature for them reliable enough to reject a real dump over, and
    /// wrongly refusing one is a far worse failure than accepting a mislabelled file
    /// the engine will refuse a moment later anyway. So a renamed archive named
    /// game.rpx or game.wux is caught here; one named game.wud is not.
    nonisolated static func isValidROMFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedROMExtensions.contains(ext) else { return false }

        switch ext {
        case "rpx", "elf":
            return fileMagic(at: url) == Data([0x7F, 0x45, 0x4C, 0x46])
        case "wux":
            return fileMagic(at: url) == Data([0x57, 0x55, 0x58, 0x30])
        case "wuhb":
            // WUHBReader.h's own s_headerMagicValue - "WUHB" in ASCII at offset 0.
            return fileMagic(at: url) == Data([0x57, 0x55, 0x48, 0x42])
        default:
            return true
        }
    }

    /// Copies a user-picked ROM (from .fileImporter, so source is a security-scoped
    /// URL outside our sandbox - Files app, iCloud Drive, another app share sheet)
    /// into Documents/Roms, then reloads the library so it shows up immediately.
    ///
    /// The order is the whole point. The picker now offers every file rather than a
    /// type-filtered list, because iOS has no built-in UTType for .rpx, .wux, .wud or
    /// .wua and any type filter therefore greys out precisely the files we want.
    /// That moves the whole burden of deciding what is a ROM onto this function, and it
    /// cannot be discharged against source: the security scope dies with the picker, and
    /// the magic bytes have to be read from somewhere we are still allowed to read.
    /// So the copy happens first, inside the scope, and the copy is what gets judged -
    /// and deleted again if it fails, leaving nothing behind.
    func importROM(from source: URL) async throws {
        // Security scope has to be claimed BEFORE anything reads the URL. For a folder
        // pick, the scope covers the whole tree, so the recursive copy below inherits
        // it - but only while the claim is held, hence the copy happening inside it.
        // The claim stays live for as long as this function hasn't returned, which
        // includes the whole `await` on the detached copy task below - `defer` runs at
        // function exit, not when execution merely suspends.
        guard source.startAccessingSecurityScopedResource() else {
            throw ROMImportError.accessDenied
        }
        defer { source.stopAccessingSecurityScopedResource() }

        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)
        guard exists else { throw ROMImportError.accessDenied }

        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ROMImportError.accessDenied
        }

        // Documents/Roms is what loadGames() scans on every launch, so anything that
        // lands here is in the library after the next restart, not just this one.
        let romsPath = documentsPath.appendingPathComponent(romsDirectory)
        try? fileManager.createDirectory(at: romsPath, withIntermediateDirectories: true)

        let destination = romsPath.appendingPathComponent(source.lastPathComponent)

        // Ask before clobbering something already in the library under this name.
        // This used to just delete whatever was there - fine for our own scratch
        // staging directory, not fine for a game or dump someone already imported.
        // Checked (and asked about) up front, before any of the actual copying below,
        // so declining costs nothing: no multi-GB copy was wasted getting here.
        if fileManager.fileExists(atPath: destination.path) {
            let shouldReplace = await confirmOverwrite?(destination.lastPathComponent) ?? false
            guard shouldReplace else { return }
        }

        if isDirectory.boolValue {
            // A dumped game is a directory, not a file, and it is the one case where
            // copy-then-validate is the wrong order: the structural check is free to run
            // against source, whereas copying first would mean recursively duplicating
            // whatever the user tapped - a 30 GB Downloads folder - before earning the
            // right to say no. Check, then copy. Accepts either the code/content/meta
            // layout or a decrypted NUS dump (title.tmd plus its .app files).
            guard Self.looksLikeWiiUDump(source) || Self.looksLikeNUSDump(source) else {
                throw ROMImportError.notAWiiUDump(source.lastPathComponent)
            }

            let stagingPath = romsPath.appendingPathComponent(Self.stagingDirectoryName)
            try? fileManager.createDirectory(at: stagingPath, withIntermediateDirectories: true)

            importState = .copying(name: source.lastPathComponent)
            defer { importState = .idle }

            // GameManager is @MainActor, and copyItem/moveItem on a multi-GB directory
            // are real, slow disk I/O - running them inline here blocked the main
            // thread (and therefore all of SwiftUI) for as long as the copy took.
            // Task.detached calls a `nonisolated` static function with no `self`, so
            // this actually runs off the main actor rather than just hoping the
            // caller's context wasn't already on it.
            try await Task.detached {
                try Self.stageAndPromoteDirectory(source: source, destination: destination, stagingPath: stagingPath)
            }.value

            await loadGames()
            return
        }

        // Single file. Copy into staging first - still inside the security scope, which
        // is the only window in which source is readable at all - then validate what
        // actually landed, then promote it.
        let stagingPath = romsPath.appendingPathComponent(Self.stagingDirectoryName)
        try? fileManager.createDirectory(at: stagingPath, withIntermediateDirectories: true)

        importState = .copying(name: source.lastPathComponent)
        defer { importState = .idle }

        try await Task.detached {
            try Self.stageAndPromoteFile(source: source, destination: destination, stagingPath: stagingPath)
        }.value

        await loadGames()
    }

    /// The actual byte-moving for a directory-dump import: stage, re-validate the
    /// staged COPY (not the source), then promote. `nonisolated` and `static` (no
    /// `self`) so Task.detached in importROM() above genuinely runs it off the main
    /// actor - see that function for why this used to block the UI thread.
    private nonisolated static func stageAndPromoteDirectory(source: URL, destination: URL, stagingPath: URL) throws {
        let fileManager = FileManager.default
        let stagedDirectory = stagingPath.appendingPathComponent(source.lastPathComponent)

        // Same reasoning as the single-file path below: a multi-GB dump copy is
        // exactly the kind of operation that can get cut short - backgrounded mid-copy
        // and reclaimed, a full disk, a yanked USB drive. Staging it under .incoming
        // first and only renaming it into Roms/ once the COPY (not just the source)
        // has been re-validated means a cut-short copy never reaches the catalog at
        // all, rather than reaching it in a broken, unrecoverable half-state that
        // loadGames() would silently skip forever.
        do {
            if fileManager.fileExists(atPath: stagedDirectory.path) {
                try fileManager.removeItem(at: stagedDirectory)
            }
            try fileManager.copyItem(at: source, to: stagedDirectory)
        } catch {
            try? fileManager.removeItem(at: stagedDirectory)
            throw ROMImportError.copyFailed(error)
        }

        let copyIsComplete = (looksLikeWiiUDump(stagedDirectory) && executableInDump(stagedDirectory) != nil)
            || looksLikeNUSDump(stagedDirectory)
        guard copyIsComplete else {
            try? fileManager.removeItem(at: stagedDirectory)
            throw ROMImportError.copyFailed(CocoaError(.fileReadCorruptFile))
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // Same volume, so this is a rename, not a second copy of the bytes -
            // same reasoning as the single-file promotion below.
            try fileManager.moveItem(at: stagedDirectory, to: destination)
        } catch {
            try? fileManager.removeItem(at: stagedDirectory)
            throw ROMImportError.copyFailed(error)
        }
    }

    /// The single-file counterpart to stageAndPromoteDirectory above - same shape,
    /// same reason for being `nonisolated static`.
    private nonisolated static func stageAndPromoteFile(source: URL, destination: URL, stagingPath: URL) throws {
        let fileManager = FileManager.default
        let staged = stagingPath.appendingPathComponent(source.lastPathComponent)

        do {
            if fileManager.fileExists(atPath: staged.path) {
                try fileManager.removeItem(at: staged)
            }
            try fileManager.copyItem(at: source, to: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw ROMImportError.copyFailed(error)
        }

        guard isValidROMFile(at: staged) else {
            // Leave no orphans: the copy the user never asked to keep goes away before
            // the error message reaches them, so a rejected import changes nothing on
            // disk and the library looks exactly as it did a second earlier.
            try? fileManager.removeItem(at: staged)
            throw ROMImportError.invalidROM
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // Same volume, so this is a rename, not a second copy of the bytes.
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw ROMImportError.copyFailed(error)
        }
    }

    func toggleFavorite(_ game: GameMetadata) {
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index].isFavorite.toggle()

            if games[index].isFavorite {
                favorites.append(games[index])
            } else {
                favorites.removeAll { $0.id == game.id }
            }

            // Written immediately, not batched - a toggle that only lived in memory
            // is exactly what made favorites forget themselves on every relaunch.
            var favoriteIDs = Self.loadFavoriteIDs()
            if games[index].isFavorite {
                favoriteIDs.insert(game.id)
            } else {
                favoriteIDs.remove(game.id)
            }
            Self.saveFavoriteIDs(favoriteIDs)
        }
    }

    private nonisolated static func loadFavoriteIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: favoriteIDsKey) ?? [])
    }

    private nonisolated static func saveFavoriteIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: favoriteIDsKey)
    }

    func launchGame(_ game: GameMetadata) {
        currentGame = game
        emulationState = .loading
        surfaceRegistered = false

        guard let engine = emulationEngine else {
            emulationState = .error
            return
        }

        // Delegate to the real Cemu core via the bridge. Pre-M1 (core not compiled
        // for iOS yet) this honestly reports "engine not built" rather than faking a run.
        guard engine.coreAvailable else {
            lastStatusMessage = engine.statusText
            emulationState = .error
            return
        }

        // Actual init/boot is deferred to registerRenderSurface(...) below, called by
        // MetalViewIOS once its view has mounted while emulationState == .loading (see
        // ContentView.swift). WindowSystem::GetWindowPhysSize() is read synchronously
        // by the GPU thread the instant boot() spawns it (M3, CemuBridge.mm), so a real
        // surface must be registered with the bridge before boot() runs, not after -
        // this view previously only appeared once emulationState == .running, i.e.
        // strictly after boot() had already returned.
    }

    /// Called by DisplayRouter once it has decided which display the Wii U TV screen
    /// belongs on, while emulationState == .loading. Registers the render surface (fast,
    /// safe to run synchronously on the calling - main - thread: sets a few WindowSystem
    /// fields and constructs the renderer, doesn't touch the GPU thread), then runs
    /// the actual init/boot on a detached background task so a slow interpreter boot -
    /// or any bug in it - can't freeze the UI, regardless of how well-behaved the C++
    /// side turns out to be.
    ///
    /// Returns whether this call is the one that registered. The router needs a real
    /// answer rather than an assumption: it only creates a GamePad surface once a TV
    /// surface exists, because InitializeLayer(mainWindow=false) needs the renderer that
    /// the TV registration constructs.
    #if os(iOS)
    @discardableResult
    func registerRenderSurface(uiView: UIView, width: Int32, height: Int32, dpiScale: Double) -> Bool {
        guard emulationState == .loading, !surfaceRegistered,
              let game = currentGame, let engine = emulationEngine else { return false }
        surfaceRegistered = true

        // passRetained, not passUnretained - deliberately keeping this one view alive
        // for the app's lifetime. Confirmed via a live device SIGSEGV inside
        // MetalRenderer::BeginFrame() -> AcquireDrawable() -> nextDrawable():
        // CreateMetalLayer() (MetalLayer.mm) adds the real CAMetalLayer as a sublayer
        // of this view's CALayer, and the C++ side (MetalLayerHandle) holds a bare,
        // ARC-invisible `CA::MetalLayer*` to it with no retain of its own. If the view
        // is deallocated - SwiftUI is free to tear down and rebuild a
        // UIViewRepresentable's underlying view on essentially any hierarchy change,
        // e.g. the .loading -> .running transition removing the "Booting..." overlay -
        // its layer, and therefore our sublayer, goes with it while the GPU thread
        // still holds a raw pointer, and the very next draw call reads freed memory.
        //
        // Belt and braces as of the display-routing work: the view handed in here is
        // DisplayRouter.shared.tvRenderView, which that singleton also holds strongly
        // and which SwiftUI never owns - it is reparented between the on-device
        // container and an external display's window rather than recreated. This
        // retain is now the second reason it survives rather than the only one, and is
        // kept because the C++ side's ownership is still the thing that is wrong; the
        // real fix would have it own this lifetime properly.
        let surfacePtr = Unmanaged.passRetained(uiView).toOpaque()
        cemu_bridge_register_render_surface(surfacePtr, width, height, dpiScale)

        let romPath = game.romPath
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let mlcPath = documentsPath.appendingPathComponent("mlc").path
            try? FileManager.default.createDirectory(atPath: mlcPath, withIntermediateDirectories: true)

            cemu_bridge_log_checkpoint("launchGame: about to call engine.initialize() [background]")
            EmulationEngine.initializeBlocking(mlcPath: mlcPath)
            cemu_bridge_log_checkpoint("launchGame: engine.initialize() returned [background]")

            // After initialize, never before: the engine picks its own timebase default
            // from the CPU mode that launch actually got, and that decision is made
            // inside cemu_bridge_initialize(). This only overrides it when the user has
            // explicitly chosen a value, so someone who never opens Settings keeps the
            // default that was chosen with the CPU mode in hand.
            TimebaseScale.applyStoredChoiceIfAny()

            // Read here rather than only from the switches, because the engine reads both
            // of these once while a title starts and cannot see UserDefaults. A switch
            // that silently reverts on every relaunch is worse than no switch.
            //
            // The recompiler defaults ON: the recompiler is the fast path, and the
            // bridge falls back to the interpreter by itself when no JIT enabler is attached.
            cemu_bridge_set_recompiler_enabled(
                UserDefaults.standard.object(forKey: "muffin.cpu.recompiler") as? Bool ?? true)
            // Per-game override first, the global switch underneath it.
            cemu_bridge_set_favour_accuracy(
                PerGameSettingsStore.shared.effectiveFavourAccuracy(for: game.id))
            // Per-game override first, global default underneath it - PerGameSettingsStore
            // reads the same UserDefaults key directly for exactly the reason above: an
            // override that only lived in a @Published property would revert the moment
            // this background task started fresh on a relaunch.
            cemu_bridge_set_async_shader_compile(
                PerGameSettingsStore.shared.effectivePreCompileShaders(for: game.id))
            // Global, not per-game - see CemuBridge.h's cemu_bridge_set_vsync_enabled().
            // Applied once per layer (re)init, so reading it here before boot is what
            // makes a mid-session Settings change take effect on the next launch.
            cemu_bridge_set_vsync_enabled(
                UserDefaults.standard.object(forKey: "muffin.render.vsync") as? Bool ?? true)
            // Same "sync from UserDefaults before boot" reason as the calls above, but for a
            // different lifetime: fullscreen_scaling is re-read every time the output blit
            // is sized, so Settings can change it mid-title and the next frame honours it.
            // This call is still needed, because a value set in Settings during a previous
            // session only lives in UserDefaults until something pushes it into the engine.
            cemu_bridge_set_stretch_to_fill(
                UserDefaults.standard.object(forKey: FrameStretch.storageKey) as? Bool
                    ?? FrameStretch.defaultValue)

            // Renderer and scaling filters. CemuRun() constructs the renderer for whichever
            // API is configured when the title starts, so these are pushed here, before
            // boot, like everything above. Defaults match Settings: Metal, bicubic up,
            // linear down.
            cemu_bridge_set_graphics_api(
                Int32(UserDefaults.standard.object(forKey: "muffin.render.graphicsAPI") as? Int ?? 2))
            cemu_bridge_set_upscale_filter(
                Int32(UserDefaults.standard.object(forKey: "muffin.render.upscaleFilter") as? Int ?? 1))
            cemu_bridge_set_downscale_filter(
                Int32(UserDefaults.standard.object(forKey: "muffin.render.downscaleFilter") as? Int ?? 0))

            // Screen flip, gamma and the performance overlay - same "push from UserDefaults
            // before boot" reasoning as everything above: the engine reads all of these once
            // at the points cited on their bridge declarations, not from UserDefaults itself.
            cemu_bridge_set_render_upside_down(
                UserDefaults.standard.object(forKey: "muffin.render.upsideDown") as? Bool ?? false)
            // Metal only, but harmless to push unconditionally - MetalRenderer.cpp is the
            // only reader, and Vulkan (VulkanRenderer.cpp) never looks at this field.
            cemu_bridge_set_framebuffer_fetch(
                UserDefaults.standard.object(forKey: "muffin.render.framebufferFetch") as? Bool ?? true)
            cemu_bridge_set_display_gamma(Float(
                UserDefaults.standard.object(forKey: DisplayGammaSetting.storageKey) as? Double
                    ?? DisplayGammaSetting.defaultValue))
            cemu_bridge_set_override_app_gamma(
                UserDefaults.standard.object(forKey: "muffin.render.overrideAppGamma") as? Bool ?? false)
            cemu_bridge_set_override_gamma_value(Float(
                UserDefaults.standard.object(forKey: OverrideGammaSetting.storageKey) as? Double
                    ?? OverrideGammaSetting.defaultValue))
            cemu_bridge_set_overlay_position(
                Int32(UserDefaults.standard.object(forKey: OverlaySettings.positionKey) as? Int
                    ?? OverlaySettings.defaultPosition.rawValue))
            cemu_bridge_set_overlay_fps(
                UserDefaults.standard.object(forKey: OverlaySettings.fpsKey) as? Bool
                    ?? OverlaySettings.defaultFps)
            cemu_bridge_set_overlay_cpu_usage(
                UserDefaults.standard.object(forKey: OverlaySettings.cpuUsageKey) as? Bool
                    ?? OverlaySettings.defaultCpuUsage)
            cemu_bridge_set_overlay_ram_usage(
                UserDefaults.standard.object(forKey: OverlaySettings.ramUsageKey) as? Bool
                    ?? OverlaySettings.defaultRamUsage)

            // Audio. tv_audio_enabled/pad_audio_enabled and the volumes take effect the
            // moment ax_out.cpp next looks at them (see CemuBridge.h's Audio section), but
            // the channel layouts only apply when their device is (re)created, so - like
            // everything else in this block - pushing them here before boot is what makes
            // a change made in Settings during a previous session actually reach a fresh
            // launch. Defaults match AudioSettingsSection.swift/CemuConfig.h: TV on,
            // GamePad off, both stereo, both at 50.
            cemu_bridge_set_tv_audio_enabled(
                UserDefaults.standard.object(forKey: AudioSettings.tvEnabledKey) as? Bool ?? AudioSettings.defaultTvEnabled)
            cemu_bridge_set_tv_volume(
                Int32(UserDefaults.standard.object(forKey: AudioSettings.tvVolumeKey) as? Int ?? AudioSettings.defaultTvVolume))
            cemu_bridge_set_tv_channels(
                Int32(UserDefaults.standard.object(forKey: AudioSettings.tvChannelsKey) as? Int ?? AudioSettings.defaultTvChannels))
            cemu_bridge_set_pad_audio_enabled(
                UserDefaults.standard.object(forKey: AudioSettings.padEnabledKey) as? Bool ?? AudioSettings.defaultPadEnabled)
            cemu_bridge_set_pad_volume(
                Int32(UserDefaults.standard.object(forKey: AudioSettings.padVolumeKey) as? Int ?? AudioSettings.defaultPadVolume))
            cemu_bridge_set_pad_channels(
                Int32(UserDefaults.standard.object(forKey: AudioSettings.padChannelsKey) as? Int ?? AudioSettings.defaultPadChannels))

            cemu_bridge_log_checkpoint("launchGame: about to call engine.boot() [background]")
            let status = EmulationEngine.bootBlocking(path: romPath)
            cemu_bridge_log_checkpoint("launchGame: engine.boot() returned [background]")

            await MainActor.run {
                guard let self else { return }
                engine.refreshStatus()
                self.lastStatusMessage = engine.statusText
                self.emulationState = (status == CEMU_BRIDGE_OK) ? .running : .error
                if self.emulationState == .running {
                    self.startFrameRateMonitor()
                }
            }
        }

        return true
    }
    #endif

    func stopEmulation() {
        stopFrameRateMonitor()
        #if os(iOS)
        // Resume before stopping, unconditionally, even though nothing here knows or
        // cares whether the title was paused.
        //
        // stop() is CafeSystem::ShutdownTitle(), which has to join the guest threads
        // before it can tear the title down. cemu_bridge_pause() suspends exactly those
        // threads (SuspendActiveThreads(), via PauseTitle()), and a suspended thread
        // never reaches the end of itself - so shutting down a paused title deadlocks
        // in the join, with the UI already switched to "paused" and the whole app hung
        // behind it. That is a hang, not a slow exit: nothing later un-suspends them,
        // because the view whose .onChange(of: scenePhase) would have called resume has
        // already gone away by then.
        //
        // It also clears the Metal GPU thread's drawable gate, the other half
        // cemu_bridge_pause() sets. That half does NOT survive the title - the gate is a
        // member of the renderer, and CemuBridge.mm resets g_renderer on shutdown, so
        // the next launch builds a fresh one already ungated. It is cleared here because
        // the gate has to be open for the frames the shutdown path itself still draws,
        // not to protect the next title.
        //
        // Unconditional on purpose. ResumeTitle() no-ops when no title is running and
        // clearing an already-clear flag costs nothing, so there is no state to check
        // and therefore no way for this to get out of sync with whatever paused it.
        cemu_bridge_resume()
        #endif
        emulationEngine?.stop()
        #if os(iOS)
        // engine.stop() is CafeSystem::ShutdownTitle(), which reaches
        // LatteThread_Exit() and `delete renderer` - so every surface registered with
        // the C++ side is gone by the time this returns, and the router has to know
        // that or the next launch would try to reuse a view whose layer no longer has
        // an owner on the C++ side. Ordered after stop() deliberately: the views must
        // outlive the renderer, not the other way round.
        DisplayRouter.shared.titleStopped()
        #endif
        surfaceRegistered = false
        emulationState = .idle
        currentGame = nil
    }

    func getEmulationEngine() -> EmulationEngine? {
        return emulationEngine
    }

    /// Always nil, and correctly so: the native C++ Metal renderer presents straight
    /// into its own CAMetalLayer (added as a sublayer of the registered UIView by
    /// CreateMetalLayer(), MetalLayer.mm) and never hands a texture back across the
    /// bridge. This exists only for the Swift-side placeholder MTKView renderers
    /// (Rendering/MetalRenderer.swift and MetalView.swift's macOS path), which have
    /// nothing to draw as a result.
    func getFrameTexture() -> MTLTexture? {
        return nil
    }

    /// Real frame rate as measured by the emulator itself, refreshed by
    /// `startFrameRateMonitor()` below. Not a Swift-side estimate: the number comes
    /// from LattePerformanceMonitor via WindowSystem::UpdateWindowTitles().
    /// 0 means "not currently rendering", which is a true statement, not a placeholder.
    func getFrameRate() -> Int {
        return frameRate
    }

    /// The HUD used to call a getFrameRate() that returned a hardcoded 0, so it
    /// permanently read "0 FPS" no matter what the emulator was doing - worse than
    /// showing nothing, because it looked like a live measurement of a stalled
    /// emulator. Poll the bridge instead.
    ///
    /// 1s cadence deliberately: LattePerformanceMonitor only recomputes fps about
    /// once a second, so anything faster would just re-read the same value and churn
    /// SwiftUI. A Timer (rather than reading the bridge inline from `body`) is what
    /// makes the reading actually refresh - `body` is only re-evaluated when
    /// published state changes, which a plain function call cannot trigger.
    private func startFrameRateMonitor() {
        frameRateTimer?.invalidate()
        frameRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let fps = Int(cemu_bridge_get_fps().rounded())
                if fps != self.frameRate {
                    self.frameRate = fps
                }
                let snapshot = EmulatorProgress.read()
                if snapshot != self.progress {
                    self.progress = snapshot
                }
            }
        }
    }

    private func stopFrameRateMonitor() {
        frameRateTimer?.invalidate()
        frameRateTimer = nil
        frameRate = 0
        progress = EmulatorProgress()
    }
}

/// The engine's own progress counters, as the heartbeat measures them.
///
/// The reason this exists next to `frameRate` rather than replacing it: `frameRate`
/// comes from LattePerformanceMonitor, which reports whole frames per second. Every rate
/// this port has actually produced under the interpreter rounds to zero there, so the
/// HUD read "-- FPS" during runs that were genuinely rendering - the same readout it
/// shows for a title that has stopped dead. These counters tell those two apart, on the
/// device, without anyone exporting log.txt and mailing it anywhere.
struct EmulatorProgress: Equatable {
    var gx2InitReached: Bool = false
    var gx2FrameCount: UInt64 = 0
    /// Fractional on purpose. 0.4 frames per second is the answer, and rounding it to
    /// "0 FPS" destroys exactly the information being asked for.
    var gx2FramesPerSecond: Double = 0
    var osScreenScanouts: UInt64 = 0
    var guestFlipRequests: UInt32 = 0

    static func read() -> EmulatorProgress {
        var raw = CemuBridgeProgress()
        cemu_bridge_get_progress(&raw)
        return EmulatorProgress(
            gx2InitReached: raw.gx2_init_reached,
            gx2FrameCount: raw.gx2_frame_count,
            gx2FramesPerSecond: raw.gx2_frames_per_second,
            osScreenScanouts: raw.os_screen_scanouts,
            guestFlipRequests: raw.guest_flip_requests)
    }

    /// What the HUD shows, and the whole point of the struct: one short string that
    /// distinguishes slow from stuck.
    ///
    /// `wholeFramesPerSecond` is LattePerformanceMonitor's number and stays in charge
    /// whenever it is non-zero, so a build that reaches a normal frame rate reads exactly
    /// as it always did.
    func hudText(wholeFramesPerSecond: Int) -> String {
        if wholeFramesPerSecond > 0 {
            return "\(wholeFramesPerSecond) FPS"
        }
        if gx2FrameCount > 0 {
            // Running past the first frame, just below one frame per second. Show the
            // rate AND the count: the rate says how slow, the count is the thing whose
            // movement proves it is not stuck.
            if gx2FramesPerSecond > 0 {
                return String(format: "%.2f fps · %llu frames", gx2FramesPerSecond, gx2FrameCount)
            }
            return String(format: "%llu frames", gx2FrameCount)
        }
        if gx2InitReached {
            // Past handover with nothing drawn. This is the case that is a real bug
            // rather than a slow one, so it says so instead of showing a rate of zero.
            return "GX2 · no frames yet"
        }
        if osScreenScanouts > 0 || guestFlipRequests > 0 {
            return "Booting · \(osScreenScanouts) scanouts"
        }
        return "-- FPS"
    }
}

enum EmulationState {
    case idle
    case loading
    case running
    case paused
    case error
}
