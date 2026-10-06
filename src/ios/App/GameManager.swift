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
    /// Root of the dumped title directory (code/content/meta, or an encrypted game folder with title.tmd, title.tik and .app files) -
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
    private static let versionKey = "muffin.library.metadataCacheVersion"
    private static let currentVersion = 2

    /// Before version 2 a disc image that could not be opened (the scan runs before the engine has its keys) was stored as
    /// "checked, nothing there" and never asked again, so it kept its file name and no region for good. Those entries cannot be
    /// told apart from a real "nothing there", so they are dropped once and derived again.
    static func discardEntriesFromBeforeVersion2() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        defaults.removeObject(forKey: regionKey)
        defaults.removeObject(forKey: titleNameKey)
        defaults.set(currentVersion, forKey: versionKey)
    }

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
    /// A short note about how the last launch differed from what was asked for (for example Vulkan not starting so
    /// Metal was used). Shown as a banner over the game for a few seconds.
    @Published var launchNotice: String?
    /// True when the last game stopped in a way that makes starting another one in this process unsafe (the GPU stopped
    /// running the app's work, or the engine could not fully reset). Only closing and reopening the app clears it, so the
    /// launch is refused with a message and a button that closes the app. Never set by a normal stop.
    @Published private(set) var needsCleanRestart = false
    /// True when the engine ended the running title itself (the game quit, the GPU thread hit an exception, a fatal error such as
    /// running out of address space, or a Wii U Menu switch that could not start the next title). `lastStatusMessage` then says why.
    @Published private(set) var titleEndedByEngine = false
    /// Real emulator frame rate, polled from the bridge once a second while a title
    /// is running (see startFrameRateMonitor()). 0 whenever nothing is rendering.
    @Published private(set) var frameRate: Int = 0
    /// True while the picture has stopped although the game is still running (the bridge's
    /// render-stall watchdog, `cemu_bridge_video_stalled()`). Polled with the frame rate.
    @Published private(set) var videoStalled = false
    /// 1 = the GPU stopped finishing frames, 2 = the GPU reported an error, 3 = out of memory for the screen,
    /// 4 = low-memory warning, 5 = the screen stopped taking frames (`cemu_bridge_video_stall_kind()`).
    /// Kinds 1, 3 and 5 are heuristics and clear by themselves when frames resume.
    @Published private(set) var videoStallKind = 0
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
    private var didSweepStaging = false
    private let gameListFile = "games.json"
    private var emulationEngine: EmulationEngine?
    private var surfaceRegistered = false
    private static let favoriteIDsKey = "muffin.library.favoriteGameIDs"

    init() {
        // The Wii U Menu can start a game without going through launchGame(); the engine tells us which title it is switching to
        // and the per-game settings that a library launch pushes before boot are pushed here too.
        cemu_bridge_set_title_switch_callback { titleId in
            TitleSwitchSettings.apply(titleId: titleId)
        }
        emulationEngine = EmulationEngine()
        // Thermal throttling lowers the picture quality on its own; say so over the game.
        ThermalMonitor.shared.onNotice = { [weak self] text in
            guard let self, self.emulationState == .running else { return }
            self.showLaunchNotice(text)
        }
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

        let sweepStaging = !didSweepStaging
        didSweepStaging = true
        // The scan opens every dump through the bridge and reads the disk, so it runs off
        // the main actor; only the published results are applied here.
        let discovered = await Task.detached(priority: .userInitiated) {
            Self.scanRoms(romsPath: romsPath, sweepStaging: sweepStaging)
        }.value
        guard let discovered else {
            print("Error scanning Roms directory")
            return
        }
        self.games = discovered.sorted { $0.title < $1.title }
        TitleSwitchSettings.shared.update(games: self.games)
        self.favorites = self.games.filter { $0.isFavorite }
        enrichMissingCoverArt()
    }

    /// Scans Roms/ for games. Pure disk and bridge work with no main-actor state, so it is
    /// safe to run detached. Returns nil if the directory can't be read.
    private nonisolated static func scanRoms(romsPath: URL, sweepStaging: Bool) -> [GameMetadata]? {
        let fileManager = FileManager.default
        LibraryMetadataCache.discardEntriesFromBeforeVersion2()

        // Staging folders hold partial copies from an import that was killed or ran out of
        // space. Nothing else can be importing at launch, so clear them once per launch.
        if sweepStaging {
            let staging = romsPath.appendingPathComponent(stagingDirectoryName)
            try? fileManager.removeItem(at: staging)
            let dlcStaging = romsPath.deletingLastPathComponent().appendingPathComponent("mlc").appendingPathComponent(".incoming-dlcupdate")
            try? fileManager.removeItem(at: dlcStaging)
        }

        // Imports from earlier versions that went one folder too high never reached the engine.
        // Moved here, before any game can start, rather than the first time a screen looks.
        DlcUpdateImport.migrateMisplacedContentIfNeeded()
        GameSaveTransfer.migrateMisplacedSavesIfNeeded()

        guard let contents = try? fileManager.contentsOfDirectory(at: romsPath, includingPropertiesForKeys: nil) else {
            return nil
        }
        // Encrypted disc images need the key cache loaded before TitleInfo can open them
        // (DLC/update matching and cover derivation both do); loading it here keeps it
        // off the main thread.
        //
        // This scan runs at app start, before the engine is initialized (that happens at the first launch), when the
        // core still has no user data folder to find keys.txt in. Tell the key cache where the files are, or every
        // .wux/.wud below fails to open ("no key in keys.txt decrypts this disc image"), is listed without a title id,
        // region, name or box art, and the result is remembered (see deriveAndApplyRegionAndTitleName).
        let mlcFolder = romsPath.deletingLastPathComponent().appendingPathComponent("mlc").path
        mlcFolder.withCString { cemu_bridge_prepare_keys_before_init($0) }
        _ = cemu_bridge_reload_and_count_keys()

        // Stable order so duplicate-id resolution below is deterministic.
        let sortedContents = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var discoveredGames: [GameMetadata] = []
        var usedIDs = Set<String>()
        for item in sortedContents {
            // A Roms entry is either a single-file dump or a dumped game DIRECTORY.
            // For a directory the engine still boots an .rpx, but it must be the one
            // sitting inside code/ so Cemu sees the real layout next to it - boot it
            // from anywhere else and it falls back to standalone mode and logs
            // "incorrect layout or missing meta files", losing the title metadata.
            var gameID: String
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
                } else if let tmd = Self.nusBaseTitleTmd(in: item) {
                    // Encrypted game folder: boot path points straight at title.tmd,
                    // matching TitleInfo::DetectFormat's own NUS-format detection. The
                    // base game may be the folder itself or a subfolder of it (e.g.
                    // "Game (USA)/Game"); its update and DLC subfolders are found by the
                    // engine at launch (IOSTitleLaunch_FindCompanionTitles).
                    gameID = item.lastPathComponent
                    bootPath = tmd.path
                    dumpDirectory = tmd.deletingLastPathComponent()
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

            // Ids are the filename without extension, so Game.wud and Game.wux (or a file and a
            // folder with the same base name) would collide. The first keeps the plain id, so
            // existing favourites and settings stay attached; later ones use the full filename.
            if !usedIDs.insert(gameID).inserted {
                gameID = item.lastPathComponent
                usedIDs.insert(gameID)
            }

            let addedDate = (try? fileManager.attributesOfItem(atPath: item.path))?[.creationDate] as? Date

            let gameMetadata = GameMetadata(
                id: gameID,
                title: gameID,
                romPath: bootPath,
                coverPath: Self.findCover(for: gameID, romPath: bootPath, in: romsPath),
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

        return discoveredGames
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

    /// An encrypted game folder - the flat "title.tmd, title.tik and a pile of encrypted
    /// .app files" layout produced by NUS downloaders - as opposed to the
    /// code/content/meta layout above. TitleInfo::DetectFormat (TitleInfo.cpp) recognizes
    /// this shape whenever it is pointed straight at title.tmd - boost::iequals, so the
    /// match here is case-insensitive too, matching the engine rather than guessing.
    nonisolated static func titleTmdInDump(_ directory: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries.first { $0.lastPathComponent.caseInsensitiveCompare("title.tmd") == .orderedSame }
    }

    /// What a title.tmd's title ID says the folder holds. The high word is the title type:
    /// 00050000 base game, 0005000E update, 0005000C DLC.
    enum NUSFolderKind {
        case base
        case update
        case dlc

        var titleIdHighWord: UInt32 {
            switch self {
            case .base: return 0x00050000
            case .update: return 0x0005000E
            case .dlc: return 0x0005000C
            }
        }
    }

    /// Classifies a title.tmd by its title ID (read straight from the file, no keys
    /// needed). A tmd that can't be read counts as a base game, so a damaged folder still
    /// shows up in the library and fails with a specific message at launch instead of
    /// silently vanishing.
    nonisolated static func nusKind(ofTmd tmd: URL) -> NUSFolderKind {
        var titleId: UInt64 = 0
        let ok = tmd.path.withCString { cemu_bridge_read_tmd_title_id($0, &titleId) }
        guard ok else { return .base }
        switch UInt32(truncatingIfNeeded: titleId >> 32) {
        case NUSFolderKind.update.titleIdHighWord: return .update
        case NUSFolderKind.dlc.titleIdHighWord: return .dlc
        default: return .base
        }
    }

    /// Every folder at or below `directory` (down to two levels) that has its own
    /// title.tmd, in name order, with what each one is. `directory` itself comes first
    /// when it has one.
    nonisolated static func nusTitleFolders(in directory: URL, maxDepth: Int = 2) -> [(tmd: URL, kind: NUSFolderKind)] {
        var found: [(tmd: URL, kind: NUSFolderKind)] = []
        if let tmd = titleTmdInDump(directory) {
            found.append((tmd, nusKind(ofTmd: tmd)))
            return found
        }
        guard maxDepth > 0 else { return found }
        let subfolders = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for subfolder in subfolders {
            found.append(contentsOf: nusTitleFolders(in: subfolder, maxDepth: maxDepth - 1))
        }
        return found
    }

    /// The title.tmd of the base game in `directory`: the folder's own when it is a base
    /// game, otherwise the first base game among its subfolders (a "Game (USA)" folder with
    /// Game, Update and DLC inside). nil when there is no base game, e.g. an update or DLC
    /// folder on its own.
    nonisolated static func nusBaseTitleTmd(in directory: URL) -> URL? {
        nusTitleFolders(in: directory).first { $0.kind == .base }?.tmd
    }

    /// The folder for `kind` (update or DLC) inside a parent folder that holds several
    /// encrypted game folders, or nil when `directory` is itself a single title folder.
    nonisolated static func nusSubfolder(in directory: URL, kind: NUSFolderKind) -> URL? {
        guard titleTmdInDump(directory) == nil else { return nil }
        return nusTitleFolders(in: directory).first { $0.kind == kind }?.tmd.deletingLastPathComponent()
    }

    nonisolated static func looksLikeNUSDump(_ directory: URL) -> Bool {
        nusBaseTitleTmd(in: directory) != nil
    }

    /// Wraps cemu_bridge_derive_title_id + cemu_bridge_derive_base_title_id (see
    /// CemuBridge.h) to get a game's identity for DLC/update matching in one call.
    /// Already reduced to the BASE title ID - a library entry is always a base game
    /// (see the loadGames() switch above), so there is nothing here that could itself
    /// be a DLC/update needing the reduction skipped.
    /// Not private: GameSaveTransfer needs the same answer for a library entry whose
    /// stored titleId is nil, and deriving it there rather than giving up is the
    /// difference between the save import working and refusing to run.
    ///
    /// nonisolated because it is a pure function of its argument - a path in, two C
    /// bridge calls, a number out, touching nothing this class owns. Without it the
    /// only reason it was main-actor bound was the @MainActor on the class, which made
    /// GameSaveTransfer's own nonisolated lookup fail to compile.
    nonisolated static func deriveBaseTitleId(romPath: String) -> UInt64? {
        var titleId: UInt64 = 0
        let ok = romPath.withCString { cPath in
            cemu_bridge_derive_title_id(cPath, &titleId)
        }
        guard ok else { return nil }
        return cemu_bridge_derive_base_title_id(titleId)
    }

    /// The three extensions a hand-placed `<gameID>_cover.*` override can use -
    /// shared with CoverArtPickerView (via setManualCover/removeManualCover/
    /// hasManualCoverOverride below) so the picker writes into exactly the set
    /// findCover() checks, rather than a second, possibly-drifting copy of the list.
    static let manualCoverExtensions = ["jpg", "jpeg", "png"]

    /// Art for a game's card, in the order a person would expect it: whatever they put
    /// there themselves first, then real box art already fetched. The dump's own icon
    /// (meta/iconTex.tga) is a THIRD tier below both, applied later by the background
    /// enrichment pass rather than here - see enrichMissingCoverArt().
    ///
    /// Before this existed at all, nothing in the app ever wrote a `<gameID>_cover.png`,
    /// so every card fell through to the placeholder controller glyph no matter what
    /// was installed.
    private nonisolated static func findCover(for gameID: String, romPath: String, in directory: URL) -> String? {
        let fileManager = FileManager.default

        // A hand-placed cover wins. Someone who dropped a file in specifically to
        // override the icon should not be overruled by the icon.
        for ext in Self.manualCoverExtensions {
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
        // Sequential on purpose: TitleInfo mounts through fsc, and fsc_ensureRootNodes()
        // covers the pre-boot case where the mount roots don't exist yet.
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

    /// Documents/Roms - the same directory findCover()/loadGames() already scan and
    /// that CoverArtFetcher caches box art alongside, exposed read-only so
    /// CoverArtPickerView writes/deletes a manual `<gameID>_cover.*` override into
    /// exactly the place findCover() already checks, rather than guessing or
    /// inventing a second location.
    var romsDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(romsDirectory)
    }

    /// True if `gameID` currently has a hand-placed `<gameID>_cover.*` override on
    /// disk, under any of the three extensions findCover() checks. Lets
    /// CoverArtPickerView/GameContextMenu decide whether "Remove Custom Cover" has
    /// anything to do, without duplicating findCover()'s own extension list.
    func hasManualCoverOverride(forGameID gameID: String) -> Bool {
        guard let romsPath = romsDirectoryURL else { return false }
        return Self.manualCoverExtensions.contains {
            FileManager.default.fileExists(atPath: romsPath.appendingPathComponent("\(gameID)_cover.\($0)").path)
        }
    }

    /// Re-runs findCover()'s priority order for one game and applies whatever it
    /// returns - including `nil`, unlike applyCoverPath() above, which only ever
    /// applies a newly-found path - to `games`/`favorites`. Called after
    /// setManualCover()/removeManualCover() write or delete a `<gameID>_cover.*`
    /// override, so the library card picks up the change immediately: `games` and
    /// `favorites` are both @Published, and GameCardOptimized reads `game.coverPath`
    /// straight from the struct it was handed, so mutating the array in place is the
    /// same refresh mechanism loadGames()'s own background enrichment already uses -
    /// no reload, no relaunch, no separate cache to invalidate.
    private func refreshCoverPath(forGameID gameID: String) {
        guard let index = games.firstIndex(where: { $0.id == gameID }), let romsPath = romsDirectoryURL else { return }
        let newCoverPath = Self.findCover(for: gameID, romPath: games[index].romPath, in: romsPath)
        games[index].coverPath = newCoverPath
        if let favIndex = favorites.firstIndex(where: { $0.id == gameID }) {
            favorites[favIndex].coverPath = newCoverPath
        }
    }

    /// Writes `imageData` as `gameID`'s manual cover override, replacing any
    /// existing override under a DIFFERENT extension first - findCover() checks
    /// jpg, then jpeg, then png and returns the first match, so switching a .png
    /// override to a .jpg one without removing the stale .png would leave the old
    /// image winning forever. `ext` must be one of `manualCoverExtensions`; the
    /// caller (CoverArtPickerView) is responsible for converting whatever format the
    /// source image actually is (HEIC from Photos, say) to one of those three before
    /// calling this - this function only ever writes the bytes it's handed.
    func setManualCover(imageData: Data, ext: String, forGameID gameID: String) throws {
        guard Self.manualCoverExtensions.contains(ext) else {
            throw CoverOverrideError.unsupportedExtension
        }
        guard let romsPath = romsDirectoryURL else {
            throw CoverOverrideError.noLibraryDirectory
        }
        for staleExt in Self.manualCoverExtensions where staleExt != ext {
            try? FileManager.default.removeItem(at: romsPath.appendingPathComponent("\(gameID)_cover.\(staleExt)"))
        }
        let destination = romsPath.appendingPathComponent("\(gameID)_cover.\(ext)")
        try imageData.write(to: destination, options: .atomic)
        refreshCoverPath(forGameID: gameID)
    }

    /// Deletes `gameID`'s manual cover override, if any exists (under any of the
    /// three extensions), then refreshes so the card falls back to whatever
    /// findCover()'s next tier finds - real box art already fetched, then the
    /// console's own icon, then the placeholder - exactly as if the override file
    /// had never been placed.
    func removeManualCover(forGameID gameID: String) {
        guard let romsPath = romsDirectoryURL else { return }
        for ext in Self.manualCoverExtensions {
            try? FileManager.default.removeItem(at: romsPath.appendingPathComponent("\(gameID)_cover.\(ext)"))
        }
        refreshCoverPath(forGameID: gameID)
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
        // A title that could not be opened for want of a key (3 no disc key, 4 no ticket, 8 key invalid) says nothing
        // about its meta.xml: the answer changes the moment keys.txt does. Remembering it as "nothing there" would keep
        // the card on its file name with no region for good, so it is left unanswered and asked again next scan.
        if !inspected && (invalidReason == 3 || invalidReason == 4 || invalidReason == 8) {
            return
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
                return "This isn't a valid Wii U game file."
            case .notAWiiUDump(let name):
                return "\"\(name)\" isn't a Wii U game dump. A dump folder needs code, content and meta folders inside it, or an encrypted game folder: title.tmd and title.tik next to its .app files."
            case .accessDenied:
                return "Couldn't access that file."
            case .copyFailed(let error):
                return "Couldn't copy the ROM: \(error.localizedDescription)"
            }
        }
    }

    /// setManualCover()'s two honest failure modes - a real one (couldn't find
    /// Documents/Roms at all, which would mean something is very wrong with the
    /// sandbox) and a programmer error (a caller passing an extension that isn't
    /// jpg/jpeg/png), kept as separate cases rather than folded into ROMImportError
    /// above since neither is actually about importing a ROM.
    enum CoverOverrideError: LocalizedError {
        case unsupportedExtension
        case noLibraryDirectory

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension:
                return "That image couldn't be saved in a supported format."
            case .noLibraryDirectory:
                return "Couldn't find the game library folder."
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
            // layout or an encrypted game folder (title.tmd, title.tik and .app files).
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

    /// Identifies the current launch. Changed by launchGame and stopEmulation so a boot that
    /// finishes after the user has gone back can tell it is stale.
    private var launchToken = UUID()

    func launchGame(_ game: GameMetadata) {
        // A second tap on a card (or the Wii U Menu tile) before the library has gone away would
        // restart the launch underneath the one already booting. Every way back to the library
        // goes through stopEmulation(), which leaves the state at .idle.
        guard emulationState == .idle else { return }
        launchToken = UUID()
        currentGame = game
        surfaceRegistered = false

        // A real problem was found when the previous game stopped: starting another on top of it is likely to fault. The
        // bridge only says so for a real leftover (a GPU fault, state that could not be reset), never after a normal stop.
        if cemu_bridge_clean_start_required() {
            needsCleanRestart = true
            let reason = String(cString: cemu_bridge_clean_start_reason())
            lastStatusMessage = "MuffinEMU has to be closed and reopened before it can start another game."
                + (reason.isEmpty ? "" : "\n\nWhat happened: \(reason).")
            emulationState = .error
            return
        }
        needsCleanRestart = false
        titleEndedByEngine = false
        emulationState = .loading

        guard let engine = emulationEngine else {
            emulationState = .error
            return
        }

        // Delegate to the Cemu core via the bridge.
        guard engine.coreAvailable else {
            lastStatusMessage = engine.statusText
            emulationState = .error
            return
        }

        // Actual init/boot is deferred to registerRenderSurface(...) below, called by
        // MetalViewIOS once its view has mounted while emulationState == .loading (see
        // ContentView.swift). WindowSystem::GetWindowPhysSize() is read synchronously
        // by the GPU thread the instant boot() spawns it (CemuBridge.mm), so a real
        // surface must be registered with the bridge before boot() runs.
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

        // Starting points for titles that need more than the defaults (Splatoon wants sticks and the GamePad screen).
        GameControlHints.applyBeforeLaunch(titleId: game.titleId)

        let romPath = game.romPath
        let gameID = game.id
        let token = launchToken
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
            // Global. The bridge ignores it when Favour accuracy is on for this game.
            cemu_bridge_set_favour_performance(FavourPerformance.isEnabled)
            // Per-game override first, global default underneath it - PerGameSettingsStore
            // reads the same UserDefaults key directly for exactly the reason above: an
            // override that only lived in a @Published property would revert the moment
            // this background task started fresh on a relaunch.
            cemu_bridge_set_async_shader_compile(
                PerGameSettingsStore.shared.effectivePreCompileShaders(for: game.id))
            // Global, and read here for the same reason as the calls above: the core
            // count is fixed the moment _LaunchTitleThread() starts its host threads, so
            // a Settings change only takes effect on the next launch and has to be pushed
            // before boot rather than when the toggle moved.
            cemu_bridge_set_low_power_mode(LowPowerMode.isEnabled)
            // Motion aiming (Settings > Motion & Aiming): on by default. It takes effect live, but the
            // stored choice has to reach the engine at least once per launch.
            MotionSettings.applyToBridge()
            // Read at title start like the rest: the core count is fixed once the
            // scheduler threads exist, so this has to be right before the title runs.
            // Per-game choice first, Settings underneath; Auto then decides in the bridge from the
            // game's profile, this device and its thermal state. The second call tells Auto whether
            // an earlier three-core run of this title went badly.
            cemu_bridge_set_cpu_core_mode(PerGameSettingsStore.shared.effectiveCoreMode(for: game.id).bridgeValue)
            cemu_bridge_set_cpu_auto_demoted(AutoCoreHistory.isDemotedAtLaunch(gameID: game.id))
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
                Int32(clamping: UserDefaults.standard.object(forKey: "muffin.render.graphicsAPI") as? Int ?? 2))
            // Favour performance swaps both for linear, the cheapest blend, unless this game favours
            // accuracy (which wins, as in the bridge).
            let cheapFilters = FavourPerformance.isEnabled
                && !PerGameSettingsStore.shared.effectiveFavourAccuracy(for: game.id)
            cemu_bridge_set_upscale_filter(cheapFilters ? Int32(ScaleFilter.linear.rawValue) :
                Int32(clamping: UserDefaults.standard.object(forKey: "muffin.render.upscaleFilter") as? Int ?? 1))
            cemu_bridge_set_downscale_filter(cheapFilters ? Int32(ScaleFilter.linear.rawValue) :
                Int32(clamping: UserDefaults.standard.object(forKey: "muffin.render.downscaleFilter") as? Int ?? 0))

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
                Int32(clamping: UserDefaults.standard.object(forKey: OverlaySettings.positionKey) as? Int
                    ?? OverlaySettings.defaultPosition.rawValue))
            cemu_bridge_set_overlay_text_color(
                UInt32(clamping: UserDefaults.standard.object(forKey: OverlaySettings.textColorKey) as? Int
                    ?? OverlaySettings.defaultTextColor))
            cemu_bridge_set_overlay_text_scale(
                Int32(clamping: UserDefaults.standard.object(forKey: OverlaySettings.textScaleKey) as? Int
                    ?? OverlaySettings.defaultTextScale))
            cemu_bridge_set_overlay_fps(
                UserDefaults.standard.object(forKey: OverlaySettings.fpsKey) as? Bool
                    ?? OverlaySettings.defaultFps)
            cemu_bridge_set_overlay_drawcalls(
                UserDefaults.standard.object(forKey: OverlaySettings.drawcallsKey) as? Bool
                    ?? OverlaySettings.defaultDrawcalls)
            cemu_bridge_set_overlay_cpu_usage(
                UserDefaults.standard.object(forKey: OverlaySettings.cpuUsageKey) as? Bool
                    ?? OverlaySettings.defaultCpuUsage)
            cemu_bridge_set_overlay_cpu_per_core_usage(
                UserDefaults.standard.object(forKey: OverlaySettings.cpuPerCoreUsageKey) as? Bool
                    ?? OverlaySettings.defaultCpuPerCoreUsage)
            cemu_bridge_set_overlay_ram_usage(
                UserDefaults.standard.object(forKey: OverlaySettings.ramUsageKey) as? Bool
                    ?? OverlaySettings.defaultRamUsage)
            cemu_bridge_set_overlay_vram_usage(
                UserDefaults.standard.object(forKey: OverlaySettings.vramUsageKey) as? Bool
                    ?? OverlaySettings.defaultVramUsage)
            cemu_bridge_set_overlay_debug(
                UserDefaults.standard.object(forKey: OverlaySettings.debugKey) as? Bool
                    ?? OverlaySettings.defaultDebug)

            // Notifications - a second, independent overlay draw (see
            // NotificationSettingsSection.swift's header comment); same push-before-boot
            // reasoning as the performance overlay above.
            cemu_bridge_set_notification_position(
                Int32(clamping: UserDefaults.standard.object(forKey: NotificationSettings.positionKey) as? Int
                    ?? NotificationSettings.defaultPosition.rawValue))
            cemu_bridge_set_notification_text_color(
                UInt32(clamping: UserDefaults.standard.object(forKey: NotificationSettings.textColorKey) as? Int
                    ?? NotificationSettings.defaultTextColor))
            cemu_bridge_set_notification_text_scale(
                Int32(clamping: UserDefaults.standard.object(forKey: NotificationSettings.textScaleKey) as? Int
                    ?? NotificationSettings.defaultTextScale))
            cemu_bridge_set_notification_controller_profiles(
                UserDefaults.standard.object(forKey: NotificationSettings.controllerProfilesKey) as? Bool
                    ?? NotificationSettings.defaultControllerProfiles)
            cemu_bridge_set_notification_controller_battery(
                UserDefaults.standard.object(forKey: NotificationSettings.controllerBatteryKey) as? Bool
                    ?? NotificationSettings.defaultControllerBattery)
            cemu_bridge_set_notification_shader_compiling(
                UserDefaults.standard.object(forKey: NotificationSettings.shaderCompilingKey) as? Bool
                    ?? NotificationSettings.defaultShaderCompiling)
            cemu_bridge_set_notification_friends(
                UserDefaults.standard.object(forKey: NotificationSettings.friendsKey) as? Bool
                    ?? NotificationSettings.defaultFriends)

            // Emulated toy-to-life devices. Same "push from UserDefaults before boot"
            // reasoning as everything above: nsyshid's AttachDefaultBackends() reads
            // these three config flags once, when this title's nsyshid module loads, so
            // a toggle flipped in Settings during a previous session needs pushing here
            // to reach a fresh launch at all.
            cemu_bridge_set_emulate_skylander_portal(
                UserDefaults.standard.object(forKey: EmulatedDevicesSettings.skylanderPortalKey) as? Bool
                    ?? EmulatedDevicesSettings.defaultEnabled)
            cemu_bridge_set_emulate_infinity_base(
                UserDefaults.standard.object(forKey: EmulatedDevicesSettings.infinityBaseKey) as? Bool
                    ?? EmulatedDevicesSettings.defaultEnabled)
            cemu_bridge_set_emulate_dimensions_toypad(
                UserDefaults.standard.object(forKey: EmulatedDevicesSettings.dimensionsToypadKey) as? Bool
                    ?? EmulatedDevicesSettings.defaultEnabled)

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
                Int32(clamping: UserDefaults.standard.object(forKey: AudioSettings.tvVolumeKey) as? Int ?? AudioSettings.defaultTvVolume))
            cemu_bridge_set_tv_channels(
                Int32(clamping: UserDefaults.standard.object(forKey: AudioSettings.tvChannelsKey) as? Int ?? AudioSettings.defaultTvChannels))
            cemu_bridge_set_pad_audio_enabled(
                UserDefaults.standard.object(forKey: AudioSettings.padEnabledKey) as? Bool ?? AudioSettings.defaultPadEnabled)
            cemu_bridge_set_pad_volume(
                Int32(clamping: UserDefaults.standard.object(forKey: AudioSettings.padVolumeKey) as? Int ?? AudioSettings.defaultPadVolume))
            cemu_bridge_set_pad_channels(
                Int32(clamping: UserDefaults.standard.object(forKey: AudioSettings.padChannelsKey) as? Int ?? AudioSettings.defaultPadChannels))
            // Mic input, same "sync from UserDefaults before boot" reason - mic.cpp only
            // reads microphone_enabled/input_volume the moment a title calls MICInit, which
            // can happen any time after boot, not just here, so this is what makes a change
            // from a previous session reach the first MICInit call of a fresh one.
            cemu_bridge_set_microphone_enabled(
                UserDefaults.standard.object(forKey: AudioSettings.microphoneEnabledKey) as? Bool ?? AudioSettings.defaultMicrophoneEnabled)
            cemu_bridge_set_input_volume(
                Int32(clamping: UserDefaults.standard.object(forKey: AudioSettings.inputVolumeKey) as? Int ?? AudioSettings.defaultInputVolume))

            cemu_bridge_log_checkpoint("launchGame: about to call engine.boot() [background]")
            let status = EmulationEngine.bootBlocking(path: romPath)
            cemu_bridge_log_checkpoint("launchGame: engine.boot() returned [background]")

            await MainActor.run {
                guard let self else { return }
                guard self.launchToken == token, self.emulationState == .loading else {
                    // Back was pressed (or another launch started) while this boot ran.
                    // Don't flip the UI to .running; shut down a title that did boot.
                    if status == CEMU_BRIDGE_OK, self.currentGame == nil {
                        self.stopEmulation()
                    }
                    return
                }
                engine.refreshStatus()
                self.lastStatusMessage = engine.statusText
                var notice = String(cString: cemu_bridge_take_launch_notice())
                // iOS slows the CPU and GPU in Low Power Mode, which no setting here can undo. Say so, but never over a more specific note.
                if notice.isEmpty && status == CEMU_BRIDGE_OK && ProcessInfo.processInfo.isLowPowerModeEnabled {
                    notice = "Low Power Mode is on, so games may run slowly. Turn it off in Control Center for full speed."
                }
                if !notice.isEmpty {
                    self.showLaunchNotice(notice)
                }
                self.emulationState = (status == CEMU_BRIDGE_OK) ? .running : .error
                if self.emulationState == .running {
                    self.startFrameRateMonitor()
                    if cemu_bridge_cpu_auto_picked_multicore() {
                        AutoCoreHistory.sessionStarted(gameID: gameID)
                    }
                }
            }
        }

        return true
    }
    #endif

    /// Also used for the in-game heat notice (InGameNotices.swift): same banner, same fade.
    func showLaunchNotice(_ notice: String) {
        launchNotice = notice
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if self?.launchNotice == notice {
                self?.launchNotice = nil
            }
        }
    }

    func stopEmulation() {
        launchToken = UUID()
        if let gameID = currentGame?.id {
            // A three-core run that Auto chose and that ended with the picture stopped is not retried.
            AutoCoreHistory.sessionEnded(gameID: gameID, stalled: videoStalled && videoStallKind == 1)
        }
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
                // The engine can end a title by itself and only raises a flag for it (coreinit exit(), the GPU thread's catch-all, the
                // out-of-address-space handler, a failed Wii U Menu switch). Nothing else reads that flag, so check here and stop the title
                // the way the Back button does. cemu_bridge_is_title_running() stays true for the whole of a Wii U Menu switch, so a switch
                // in progress is not mistaken for an end.
                if self.emulationState == .running && !cemu_bridge_is_title_running() {
                    self.stopTitleEndedByEngine()
                    return
                }
                let fps = Int(cemu_bridge_get_fps().rounded())
                if fps != self.frameRate {
                    self.frameRate = fps
                }
                let stalled = cemu_bridge_video_stalled()
                if stalled != self.videoStalled {
                    self.videoStalled = stalled
                }
                let kind = Int(cemu_bridge_video_stall_kind())
                if kind != self.videoStallKind {
                    self.videoStallKind = kind
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
        videoStalled = false
        videoStallKind = 0
        progress = EmulatorProgress()
    }

    /// Runs the normal stop for a title the engine has already ended, and keeps the reason on screen. The reason is read before
    /// the stop because the stop path overwrites the bridge's status line.
    private func stopTitleEndedByEngine() {
        let reason = String(cString: cemu_bridge_status_text())
        let game = currentGame
        stopEmulation()
        guard let game else { return }
        currentGame = game
        lastStatusMessage = reason
        titleEndedByEngine = true
        emulationState = .error
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
                return String(format: "%.1f FPS", gx2FramesPerSecond)
            }
            return String(format: "%llu frames", gx2FrameCount)
        }
        if gx2InitReached {
            // Past handover with nothing drawn. This is the case that is a real bug
            // rather than a slow one, so it says so instead of showing a rate of zero.
            return "Started, no picture yet"
        }
        if osScreenScanouts > 0 || guestFlipRequests > 0 {
            return "Booting..."
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

/// Applies a game's own settings when the Wii U Menu switches to it, exactly as a library launch does before boot:
/// "Favour accuracy", "Compile shaders in the background" and "CPU cores" (the per-game overrides), and the starting controls and
/// screen layout for titles that need them (GameControlHints). Settings that are global (renderer, audio, overlays, ...) were
/// already pushed when the Menu itself was launched and stay as they are. Runs on the engine's title-switch thread, so it only
/// touches thread-safe state.
final class TitleSwitchSettings {
    static let shared = TitleSwitchSettings()
    private let lock = NSLock()
    private var gameIDByTitleId: [UInt64: String] = [:]

    func update(games: [GameMetadata]) {
        var map: [UInt64: String] = [:]
        for game in games {
            if let titleId = game.titleId { map[titleId] = game.id }
        }
        lock.lock()
        gameIDByTitleId = map
        lock.unlock()
    }

    private func gameID(for titleId: UInt64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return gameIDByTitleId[titleId]
    }

    static func apply(titleId: UInt64) {
        // A title that is not in the library has no overrides, so it gets the global defaults.
        let id = shared.gameID(for: titleId) ?? ""
        // The core count is decided when the incoming title's threads start, which is after this
        // call, so the game's own choice (and Auto's memory of a three-core run that went badly)
        // has to be in place now. Each setter recomputes the CPU mode, so the order does not matter.
        cemu_bridge_set_cpu_auto_demoted(AutoCoreHistory.isDemoted(gameID: id))
        cemu_bridge_set_cpu_core_mode(PerGameSettingsStore.shared.effectiveCoreMode(for: id).bridgeValue)
        cemu_bridge_set_favour_accuracy(PerGameSettingsStore.shared.effectiveFavourAccuracy(for: id))
        cemu_bridge_set_favour_performance(FavourPerformance.isEnabled)
        cemu_bridge_set_async_shader_compile(PerGameSettingsStore.shared.effectivePreCompileShaders(for: id))
        #if os(iOS)
        GameControlHints.applyBeforeLaunch(titleId: titleId)
        #endif
    }
}
