import Foundation

/// Imports a DLC or update dump into Documents/mlc, where the engine's MLC scanner finds it.
/// Copies to a staging folder first and validates the copy, since the destination path
/// comes from the title ID inside the file.
enum DlcUpdateImport {
    enum ContentKind {
        case dlc
        case update

        /// TitleIdParser::TITLE_TYPE byte values from TitleId.h.
        fileprivate var expectedTypeByte: Int32 {
            switch self {
            case .dlc: return 0x0C // AOC
            case .update: return 0x0E // BASE_TITLE_UPDATE
            }
        }

        var displayName: String {
            switch self {
            case .dlc: return "DLC"
            case .update: return "update"
            }
        }
    }

    enum ImportError: LocalizedError {
        case accessDenied
        case copyFailed(Error)
        // Raw CemuTitleInvalidReason value from CemuBridge.h.
        case invalidTitle(Int32)
        case wrongType(expected: ContentKind, actual: String)
        case noBaseGameMatch
        case alreadyInstalledSameOrNewer(installed: UInt16, imported: UInt16)
        case wuaReadFailed
        case noMatchingTitleInWua
        case wuaHasOtherContent
        case differentGame

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Couldn't access that file."
            case .copyFailed(let error):
                return "Couldn't copy the file: \(error.localizedDescription)"
            case .invalidTitle(let reason):
                // Values match the CemuTitleInvalidReason typedef in CemuBridge.h.
                switch reason {
                case 1: // CemuTitleBadPathOrInaccessible
                    return "That file couldn't be read."
                case 2: // CemuTitleUnknownFormat
                    return "This isn't a Wii U DLC or update file."
                case 3: // CemuTitleNoDiscKey
                    return "This file is encrypted and no matching key is installed. Add your keys.txt in Settings first."
                case 4: // CemuTitleNoTicket
                    return "This folder is missing title.tik (the ticket), which MuffinEMU needs to decrypt it."
                case 5: // CemuTitleMissingXmlFiles
                    return "Meta files (app.xml, meta.xml, cos.xml) are missing or damaged."
                case 6: // CemuTitleBadTitleTmd
                    return "This encrypted folder's title.tmd couldn't be read."
                case 7: // CemuTitleBadTitleTik
                    return "This encrypted folder's title.tik couldn't be read."
                case 8: // CemuTitleKeyInvalid
                    return "MuffinEMU couldn't decrypt this folder. Its title.tik doesn't unlock the .app files."
                case 9: // CemuTitleMissingContentFile
                    return "This encrypted folder is missing one or more .app files listed in its title.tmd."
                default:
                    return "That file is corrupted or incomplete."
                }
            case .wrongType(let expected, let actual):
                return "This is \(actual), not \(expected == .dlc ? "DLC" : "an update"). Use the other import option."
            case .noBaseGameMatch:
                return "No game in your library matches this content."
            case .alreadyInstalledSameOrNewer(let installed, let imported):
                return "Version \(imported) isn't newer than what's already installed (version \(installed))."
            case .wuaReadFailed:
                return "The .wua file couldn't be read. It may be corrupted."
            case .noMatchingTitleInWua:
                return "The .wua doesn't contain a matching update or DLC for this game."
            case .wuaHasOtherContent:
                return "This .wua holds more than the one update or DLC for this game. Use a .wua with just that content."
            case .differentGame:
                return "This content is for a different game or region than the one you picked."
            }
        }
    }

    struct ImportedContent {
        let titleId: UInt64
        let baseTitleId: UInt64
        let matchedGame: GameMetadata?
    }

    private static let stagingDirectoryName = ".incoming-dlcupdate"

    private static func mlcRoot() -> URL? {
        _ = migratedMisplacedContent
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("mlc")
    }

    /// Earlier versions installed DLC and updates into `Documents/mlc/usr/title`, one level above
    /// where the engine looks (`Documents/mlc/mlc01/usr/title`), so they never reached the game.
    /// Moves each installed title folder into the real location, once per launch, only when that
    /// title is not installed there already. Anything that can't be moved stays where it is.
    private static let migratedMisplacedContent: Void = {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let wrongRoot = docs.appendingPathComponent("mlc/usr/title", isDirectory: true)
        let rightRoot = docs.appendingPathComponent("mlc/mlc01/usr/title", isDirectory: true)
        guard let highs = try? fm.contentsOfDirectory(at: wrongRoot, includingPropertiesForKeys: nil) else { return }
        for high in highs {
            guard let lows = try? fm.contentsOfDirectory(at: high, includingPropertiesForKeys: nil) else { continue }
            let rightHigh = rightRoot.appendingPathComponent(high.lastPathComponent, isDirectory: true)
            for low in lows {
                let target = rightHigh.appendingPathComponent(low.lastPathComponent, isDirectory: true)
                if fm.fileExists(atPath: target.path) { continue }
                try? fm.createDirectory(at: rightHigh, withIntermediateDirectories: true)
                try? fm.moveItem(at: low, to: target)
            }
        }
    }()

    /// Moves content that earlier versions installed in the wrong folder, if there is any. Called
    /// once at launch, so a game started straight from the library already sees its update and DLC;
    /// without it the move waited for the first import or the first long-press on a game.
    static func migrateMisplacedContentIfNeeded() {
        _ = migratedMisplacedContent
    }

    private static func titleTypeName(forByte byte: Int32) -> String {
        switch byte {
        case 0x00: return "a base game"
        case 0x02: return "a demo"
        case 0x0E: return "an update"
        case 0x0C: return "DLC"
        case 0x0F: return "homebrew"
        default: return "not a recognizable game title"
        }
    }

    /// Copies `source` into Documents/mlc as `kind`, matching it against `library` by
    /// base title ID. `manualMatch`, when provided, skips auto-matching and is trusted
    /// as the base game instead - the fallback path for a title the auto-match couldn't
    /// place (see ImportError.noBaseGameMatch).
    static func `import`(
        from source: URL,
        kind: ContentKind,
        library: [GameMetadata],
        manualMatch: GameMetadata? = nil,
        strictMatch: Bool = false,
        allowReinstall: Bool = false
    ) async throws -> ImportedContent {
        guard source.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        // Held until `import` returns, including across the await below.
        defer { source.stopAccessingSecurityScopedResource() }

        guard let mlcRoot = mlcRoot() else { throw ImportError.accessDenied }
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ImportError.accessDenied
        }

        // A .wua stays whole: it is copied in and the engine adds the titles inside it.
        if !isDirectory.boolValue {
            let ext = (source.path as NSString).pathExtension.lowercased()
            guard ext == "wua" else {
                throw ImportError.accessDenied
            }
            return try await Task.detached {
                try importFromWua(
                    source: source, kind: kind, library: library, manualMatch: manualMatch,
                    allowReinstall: allowReinstall, mlcRoot: mlcRoot
                )
            }.value
        }

        // A parent folder holding the game, update and DLC as separate encrypted folders
        // ("Game (USA)/{Game, Update, DLC}") is fine to pick: the subfolder that matches
        // `kind` is the one to install.
        let kindForFolder: GameManager.NUSFolderKind = kind == .dlc ? .dlc : .update
        let installSource = GameManager.nusSubfolder(in: source, kind: kindForFolder) ?? source

        // Copying and inspecting can take a while on a large dump, so run it off the main actor.
        return try await Task.detached {
            try copyInspectAndInstall(
                source: installSource, kind: kind, library: library, manualMatch: manualMatch,
                strictMatch: strictMatch, allowReinstall: allowReinstall, mlcRoot: mlcRoot
            )
        }.value
    }

    /// The copy, inspect and install work for `import(from:kind:library:manualMatch:)`.
    private static func copyInspectAndInstall(
        source: URL,
        kind: ContentKind,
        library: [GameMetadata],
        manualMatch: GameMetadata?,
        strictMatch: Bool,
        allowReinstall: Bool,
        mlcRoot: URL
    ) throws -> ImportedContent {
        let fileManager = FileManager.default
        let stagingRoot = mlcRoot.appendingPathComponent(stagingDirectoryName)
        try? fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let staged = stagingRoot.appendingPathComponent(source.lastPathComponent)

        do {
            if fileManager.fileExists(atPath: staged.path) {
                try fileManager.removeItem(at: staged)
            }
            try fileManager.copyItem(at: source, to: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw ImportError.copyFailed(error)
        }

        // Everything from here judges the staged copy, not the source.
        func cleanupStaged() { try? fileManager.removeItem(at: staged) }

        var titleId: UInt64 = 0
        var version: UInt16 = 0
        var region: Int32 = 0
        var invalidReason: Int32 = 0
        let valid = staged.path.withCString { cPath in
            cemu_bridge_inspect_title(cPath, &titleId, &version, &region, &invalidReason)
        }

        guard valid else {
            cleanupStaged()
            throw ImportError.invalidTitle(invalidReason)
        }

        let actualTypeByte = cemu_bridge_get_title_type(titleId)
        guard actualTypeByte == kind.expectedTypeByte else {
            cleanupStaged()
            throw ImportError.wrongType(expected: kind, actual: titleTypeName(forByte: actualTypeByte))
        }

        let baseTitleId = cemu_bridge_derive_base_title_id(titleId)

        let matchedGame: GameMetadata?
        if let manualMatch {
            matchedGame = manualMatch
        } else if let found = library.first(where: { $0.titleId == baseTitleId }) {
            matchedGame = found
        } else {
            matchedGame = nil
        }
        guard matchedGame != nil else {
            cleanupStaged()
            throw ImportError.noBaseGameMatch
        }
        if strictMatch, let manualMatch, manualMatch.titleId != baseTitleId {
            cleanupStaged()
            throw ImportError.differentGame
        }

        var upperHexBuf = [CChar](repeating: 0, count: 9)
        var lowerHexBuf = [CChar](repeating: 0, count: 9)
        cemu_bridge_get_mlc_title_path_components(titleId, &upperHexBuf, &lowerHexBuf)
        let upperHex = String(cString: upperHexBuf)
        let lowerHex = String(cString: lowerHexBuf)

        let destination = mlcRoot
            .appendingPathComponent("mlc01/usr/title")
            .appendingPathComponent(upperHex)
            .appendingPathComponent(lowerHex)

        // Judge the existing install by the folder on disk.
        if fileManager.fileExists(atPath: destination.path) {
            var existingVersion: UInt16 = 0
            let existingValid = destination.path.withCString { cPath in
                cemu_bridge_inspect_title(cPath, nil, &existingVersion, nil, nil)
            }
            if existingValid && !versionAllowed(installed: existingVersion, imported: version, allowReinstall: allowReinstall) {
                cleanupStaged()
                throw ImportError.alreadyInstalledSameOrNewer(installed: existingVersion, imported: version)
            }
        }
        // One copy of each title: a .wua copy of the same content counts as installed too.
        if let wuaVersion = installedWuaVersion(kind: kind, baseTitleId: baseTitleId, mlcRoot: mlcRoot),
           !versionAllowed(installed: wuaVersion, imported: version, allowReinstall: allowReinstall) {
            cleanupStaged()
            throw ImportError.alreadyInstalledSameOrNewer(installed: wuaVersion, imported: version)
        }

        // Keep any existing install aside until the new one is in place, so a failed
        // move cannot leave the player with neither.
        let backup = stagingRoot.appendingPathComponent(lowerHex + ".previous")
        var movedAside = false
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: backup)
                try fileManager.moveItem(at: destination, to: backup)
                movedAside = true
            }

            // Same volume as staging, so this is a rename, not a second copy.
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if movedAside && !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            cleanupStaged()
            throw ImportError.copyFailed(error)
        }
        if movedAside { try? fileManager.removeItem(at: backup) }
        try? fileManager.removeItem(at: wuaCopyURL(kind: kind, baseTitleId: baseTitleId, mlcRoot: mlcRoot))

        return ImportedContent(titleId: titleId, baseTitleId: baseTitleId, matchedGame: matchedGame)
    }

    /// Newer always installs; the same version only when the caller confirmed a reinstall.
    private static func versionAllowed(installed: UInt16, imported: UInt16, allowReinstall: Bool) -> Bool {
        imported > installed || (allowReinstall && imported == installed)
    }

    // MARK: .wua content

    /// Where the .wua holding `kind` for a base game is kept: one file per kind per game.
    private static func wuaCopyURL(kind: ContentKind, baseTitleId: UInt64, mlcRoot: URL) -> URL {
        mlcRoot
            .appendingPathComponent("wua-content")
            .appendingPathComponent(String(format: "%016llx", baseTitleId))
            .appendingPathComponent(kind == .update ? "update.wua" : "dlc.wua")
    }

    /// The title roots in a .wua, or nil when it can't be read or holds none.
    private static func wuaTitles(at path: String) -> [(id: UInt64, version: UInt16)]? {
        var buffer = [CChar](repeating: 0, count: 64 * 1024)
        let count = cemu_bridge_wua_list_titles(path, &buffer, buffer.count)
        guard count > 0 else { return nil }
        var titles: [(id: UInt64, version: UInt16)] = []
        for line in String(cString: buffer).split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let id = UInt64(parts[0], radix: 16), let version = UInt16(parts[1]) else {
                return nil
            }
            titles.append((id, version))
        }
        return titles.isEmpty ? nil : titles
    }

    private static func installedWuaVersion(kind: ContentKind, baseTitleId: UInt64, mlcRoot: URL) -> UInt16? {
        let url = wuaCopyURL(kind: kind, baseTitleId: baseTitleId, mlcRoot: mlcRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return wuaTitles(at: url.path)?.first?.version ?? 0
    }

    /// Installs a .wua holding only `kind` for one game. The file is copied to staging and
    /// judged there before anything installed is replaced.
    private static func importFromWua(
        source: URL,
        kind: ContentKind,
        library: [GameMetadata],
        manualMatch: GameMetadata?,
        allowReinstall: Bool,
        mlcRoot: URL
    ) throws -> ImportedContent {
        let fileManager = FileManager.default
        let stagingRoot = mlcRoot.appendingPathComponent(stagingDirectoryName)
        try? fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let staged = stagingRoot.appendingPathComponent("incoming-\(UUID().uuidString).wua")
        defer { try? fileManager.removeItem(at: staged) }

        do {
            try fileManager.copyItem(at: source, to: staged)
        } catch {
            throw ImportError.copyFailed(error)
        }

        guard let titles = wuaTitles(at: staged.path) else { throw ImportError.wuaReadFailed }

        let matching = titles.filter { cemu_bridge_get_title_type($0.id) == kind.expectedTypeByte }
        guard !matching.isEmpty else { throw ImportError.noMatchingTitleInWua }
        // One title of the chosen kind and nothing else, so no title ends up stored twice.
        guard matching.count == titles.count, titles.count == 1 else { throw ImportError.wuaHasOtherContent }

        let title = titles[0]
        let baseTitleId = cemu_bridge_derive_base_title_id(title.id)
        let matchedGame: GameMetadata?
        if let manualMatch {
            guard manualMatch.titleId == baseTitleId else { throw ImportError.differentGame }
            matchedGame = manualMatch
        } else if let found = library.first(where: { $0.titleId == baseTitleId }) {
            matchedGame = found
        } else {
            throw ImportError.noBaseGameMatch
        }

        // Judge the existing install, folder or .wua, before replacing anything.
        let folderVersion: UInt16? = {
            guard let destination = mlcDestination(forContentTitleId: title.id) else { return nil }
            var existing: UInt16 = 0
            let valid = destination.path.withCString { cemu_bridge_inspect_title($0, nil, &existing, nil, nil) }
            return valid ? existing : nil
        }()
        for existing in [folderVersion, installedWuaVersion(kind: kind, baseTitleId: baseTitleId, mlcRoot: mlcRoot)] {
            if let existing, !versionAllowed(installed: existing, imported: title.version, allowReinstall: allowReinstall) {
                throw ImportError.alreadyInstalledSameOrNewer(installed: existing, imported: title.version)
            }
        }

        let destination = wuaCopyURL(kind: kind, baseTitleId: baseTitleId, mlcRoot: mlcRoot)
        let backup = stagingRoot.appendingPathComponent("wua-\(kind == .update ? "update" : "dlc").previous")
        var movedAside = false
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: backup)
                try fileManager.moveItem(at: destination, to: backup)
                movedAside = true
            }
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if movedAside && !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw ImportError.copyFailed(error)
        }
        if movedAside { try? fileManager.removeItem(at: backup) }
        // The .wua is the one copy now; drop a folder copy of the same title.
        if let folder = mlcDestination(forContentTitleId: title.id) {
            try? fileManager.removeItem(at: folder)
        }

        return ImportedContent(titleId: title.id, baseTitleId: baseTitleId, matchedGame: matchedGame)
    }

    /// Whether `game` has an installed update and/or DLC, read from Documents/mlc.
    static func installedContent(for game: GameMetadata) -> (hasUpdate: Bool, hasDLC: Bool) {
        guard let baseTitleId = game.titleId else { return (false, false) }
        let root = mlcRoot()
        func wuaInstalled(_ kind: ContentKind) -> Bool {
            guard let root else { return false }
            return FileManager.default.fileExists(atPath: wuaCopyURL(kind: kind, baseTitleId: baseTitleId, mlcRoot: root).path)
        }
        return (
            hasUpdate: mlcDestination(forContentTitleId: cemu_bridge_derive_content_title_id(baseTitleId, true)) != nil
                || wuaInstalled(.update),
            hasDLC: mlcDestination(forContentTitleId: cemu_bridge_derive_content_title_id(baseTitleId, false)) != nil
                || wuaInstalled(.dlc)
        )
    }

    /// Deletes `kind`'s installed content for `game`. Returns false when there was nothing to remove.
    @discardableResult
    static func remove(kind: ContentKind, for game: GameMetadata) throws -> Bool {
        guard let baseTitleId = game.titleId else { return false }
        let contentTitleId = cemu_bridge_derive_content_title_id(baseTitleId, kind == .update)
        var removed = false
        if let root = mlcRoot() {
            let wua = wuaCopyURL(kind: kind, baseTitleId: baseTitleId, mlcRoot: root)
            if FileManager.default.fileExists(atPath: wua.path) {
                try FileManager.default.removeItem(at: wua)
                removed = true
            }
        }
        if let destination = mlcDestination(forContentTitleId: contentTitleId) {
            try FileManager.default.removeItem(at: destination)
            removed = true
        }
        return removed
    }

    /// The installed folder for `kind` on `game`, or nil when there is none.
    static func installedFolder(kind: ContentKind, for game: GameMetadata) -> URL? {
        guard let baseTitleId = game.titleId else { return nil }
        return mlcDestination(forContentTitleId: cemu_bridge_derive_content_title_id(baseTitleId, kind == .update))
    }

    /// nil for titleId 0 (not applicable) or a path that is not there.
    private static func mlcDestination(forContentTitleId titleId: UInt64) -> URL? {
        guard titleId != 0, let mlcRoot = mlcRoot() else { return nil }

        var upperHexBuf = [CChar](repeating: 0, count: 9)
        var lowerHexBuf = [CChar](repeating: 0, count: 9)
        cemu_bridge_get_mlc_title_path_components(titleId, &upperHexBuf, &lowerHexBuf)

        let destination = mlcRoot
            .appendingPathComponent("mlc01/usr/title")
            .appendingPathComponent(String(cString: upperHexBuf))
            .appendingPathComponent(String(cString: lowerHexBuf))
        return FileManager.default.fileExists(atPath: destination.path) ? destination : nil
    }
}
