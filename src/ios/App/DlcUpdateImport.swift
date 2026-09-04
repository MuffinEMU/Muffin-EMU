import Foundation

/// Imports a DLC or update dump into Documents/mlc, where the engine's own MLC scanner
/// (CafeTitleList::ScanMLCPath) already finds and mounts it alongside its base game -
/// see IOSTitleLaunch.cpp's PrepareForegroundTitle for the discovery-gap fix that makes
/// a freshly-imported title actually get picked up before the base game's next launch.
///
/// Follows the exact staged-copy-then-promote shape GameManager.importROM already
/// proved out: copy inside the security scope first, then validate and derive
/// everything else from the COPY, not the source - a cut-short copy or a source the
/// picker only half-handed over must never reach the point of being judged valid.
/// The one real difference from importROM is that the destination path isn't known
/// until after inspection (it's derived from the title ID inside the file itself), so
/// staging happens under a scratch name and only gets its real mlc path once inspected.
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
        // Raw CemuTitleInvalidReason value from CemuBridge.h - kept as the plain Int32
        // the bridge function actually hands back (its outInvalidReason parameter is
        // typed `int*`, not the enum, specifically so this side never has to guess how
        // the Clang importer would bridge that C typedef's case names into Swift).
        case invalidTitle(Int32)
        case wrongType(expected: ContentKind, actual: String)
        case noBaseGameMatch
        case alreadyInstalledSameOrNewer(installed: UInt16, imported: UInt16)
        case wuaNotYetSupported

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
                    return "That doesn't look like a Wii U DLC or update - the engine didn't recognize its format."
                case 3: // CemuTitleNoDiscKey
                    return "This file is encrypted and there's no matching decryption key installed. Add keys.txt in Settings first."
                case 4: // CemuTitleNoTicket
                    return "This dump is missing its ticket (title.tik) - it's an incomplete copy."
                case 5: // CemuTitleMissingXmlFiles
                    return "This dump is missing or has corrupted meta files (app.xml/meta.xml/cos.xml)."
                default:
                    return "That file is corrupted or incomplete."
                }
            case .wrongType(let expected, let actual):
                return "That's \(actual), not \(expected.displayName) - pick the matching import option instead."
            case .noBaseGameMatch:
                return "Couldn't find a matching game already in your library for this content."
            case .alreadyInstalledSameOrNewer(let installed, let imported):
                return "Version \(imported) isn't newer than what's already installed (version \(installed))."
            case .wuaNotYetSupported:
                return "Single-file .wua DLC/update archives aren't supported yet - import the dumped folder (code/content/meta) instead."
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
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("mlc")
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
        manualMatch: GameMetadata? = nil
    ) async throws -> ImportedContent {
        guard source.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { source.stopAccessingSecurityScopedResource() }

        guard let mlcRoot = mlcRoot() else { throw ImportError.accessDenied }
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ImportError.accessDenied
        }
        // CafeTitleList::ScanMLCPath only ever looks for a code/content/meta directory
        // under usr/title/<type>/<id>/ - it has no notion of a loose .wua file sitting
        // there, so placing one would silently never be found at the next boot. A .wua
        // would need extracting into that layout first, which this doesn't do yet.
        guard isDirectory.boolValue else {
            throw ImportError.wuaNotYetSupported
        }

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

        // Everything from here judges the staged copy, never source - source's security
        // scope is about to end, and a copy that was cut short must be caught here, not
        // silently accepted because the original file happened to be fine.
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

        var upperHexBuf = [CChar](repeating: 0, count: 9)
        var lowerHexBuf = [CChar](repeating: 0, count: 9)
        cemu_bridge_get_mlc_title_path_components(titleId, &upperHexBuf, &lowerHexBuf)
        let upperHex = String(cString: upperHexBuf)
        let lowerHex = String(cString: lowerHexBuf)

        let destination = mlcRoot
            .appendingPathComponent("usr/title")
            .appendingPathComponent(upperHex)
            .appendingPathComponent(lowerHex)

        // Already installed? Judge the EXISTING install's own version, not any record we
        // might separately be keeping - the folder on disk is the only source of truth
        // the engine itself will read from at boot.
        if fileManager.fileExists(atPath: destination.path) {
            var existingVersion: UInt16 = 0
            let existingValid = destination.path.withCString { cPath in
                cemu_bridge_inspect_title(cPath, nil, &existingVersion, nil, nil)
            }
            if existingValid && existingVersion >= version {
                cleanupStaged()
                throw ImportError.alreadyInstalledSameOrNewer(installed: existingVersion, imported: version)
            }
        }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            // Same volume as staging, so this is a rename, not a second copy.
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            cleanupStaged()
            throw ImportError.copyFailed(error)
        }

        return ImportedContent(titleId: titleId, baseTitleId: baseTitleId, matchedGame: matchedGame)
    }
}
