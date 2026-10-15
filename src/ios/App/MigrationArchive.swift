// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// One archive that carries a MuffinEMU install to another one: the move to a new app identity, or a
/// restore after a reinstall. A different bundle identifier is a different app with an empty container,
/// so everything the player would miss has to travel in a file.
///
/// A zip would not do. Games push an archive past 4 GB, which needs Zip64 (MiniZip refuses it), and MiniZip
/// maps the whole file to read it. This is a plain sequential container instead, written and read in
/// 1 MB pieces so memory stays flat however large the archive is:
///
///     "MFNMOVE1"
///     per file:   u16 path length, path (UTF-8), u64 size, the bytes, u32 CRC-32          (little-endian)
///     manifest    JSON, see Manifest
///     trailer     u64 manifest offset, u64 manifest length, "MFNMEND1"
///
/// The manifest comes last because the CRCs are only known once the files are written. The reader finds it
/// from the trailer, checks it, and then seeks straight to the files it wants. Paths are relative to
/// Documents; `_meta/` entries are the settings and app state, which are applied rather than written to disk.
///
/// Importing merges. A file that isn't here is added, an older one is replaced, and a file here that is newer
/// than the archive's is a conflict the person decides on before anything is written. Each file is written to
/// a temporary name, checked against its CRC-32 and only then moved into place, so a stop half way leaves
/// whole files only and running the import again picks up where it left off.
enum MigrationArchive {
    static let formatName = "MuffinEMU move"
    static let currentVersion = 1
    static let fileExtension = "muffinmove"
    /// Where exports are written, in Documents so Files lists them.
    static let folderName = "Migration"

    static let settingsPath = "_meta/settings.json"
    static let statePath = "_meta/appstate.json"

    private static let headMagic = Data("MFNMOVE1".utf8)
    private static let tailMagic = Data("MFNMEND1".utf8)
    private static let trailerSize = 24
    private static let chunkSize = 1 << 20
    private static let maxManifestBytes: UInt64 = 128 << 20
    private static let maxMetaBytes: Int64 = 16 << 20
    /// Two seconds either way counts as the same moment; file systems round modification times differently.
    private static let timeTolerance: Int64 = 2
    private static let gameExtensions: Set<String> = ["rpx", "wux", "wud", "wua", "wup", "iso"]

    enum MigrationError: LocalizedError {
        case notAnArchive
        case newerVersion(Int)
        case damaged(String)
        case notEnoughSpace(needed: Int64, free: Int64)
        case changedWhileReading(String)
        case noDocuments
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notAnArchive:
                return "That isn't a MuffinEMU move file."
            case .newerVersion(let version):
                return "That file was made by a newer MuffinEMU (move file version \(version)). Update the app, then try again."
            case .damaged(let what):
                return "The move file is damaged (\(what)). Nothing in it was trusted past that point."
            case .notEnoughSpace(let needed, let free):
                return "Not enough free space. This needs about \(MigrationArchive.format(needed)) and the device has \(MigrationArchive.format(free)) free."
            case .changedWhileReading(let name):
                return "\(name) changed while it was being read. Make sure no game is running, then try again."
            case .noDocuments:
                return "MuffinEMU couldn't find its Documents folder."
            case .cancelled:
                return "Cancelled."
            }
        }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    // MARK: - Manifest

    struct Manifest: Codable {
        struct File: Codable {
            let path: String
            let size: Int64
            /// Modification time, seconds since 1970.
            let modified: Int64
            let crc32: UInt32
            /// Where the file's bytes start in the archive.
            let offset: Int64
        }

        let format: String
        let version: Int
        let sourceBundleID: String
        let appVersion: String
        let created: String
        let includesGames: Bool
        let files: [File]
    }

    static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Free space for something the person asked for, the way iOS itself counts it (purgeable space included).
    static func freeSpace() -> Int64? {
        guard let documents,
              let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }

    /// What has to be free before writing `bytes`: the bytes plus a margin for the system.
    static func spaceNeeded(for bytes: Int64) -> Int64 {
        bytes + max(bytes / 50, 64 << 20)
    }

    // MARK: - What an export holds

    struct Item {
        let relativePath: String
        let url: URL
        let size: Int64
        let modified: Int64
        /// Game files: the Roms folder and base games installed into the Wii U storage.
        let isGame: Bool
    }

    struct Plan {
        var items: [Item] = []

        var coreBytes: Int64 { items.lazy.filter { !$0.isGame }.reduce(0) { $0 + $1.size } }
        var gameBytes: Int64 { items.lazy.filter { $0.isGame }.reduce(0) { $0 + $1.size } }

        func chosen(includeGames: Bool) -> [Item] { includeGames ? items : items.filter { !$0.isGame } }

        /// The archive's size: the files plus a header and a manifest entry for each. Settings are a few kilobytes.
        func archiveBytes(includeGames: Bool) -> Int64 {
            let files = chosen(includeGames: includeGames)
            let bytes = files.reduce(Int64(0)) { $0 + $1.size + Int64($1.relativePath.utf8.count) + 14 + 160 }
            return bytes + (1 << 20)
        }
    }

    /// Walks Documents and lists what an export would carry. Reads sizes, not contents.
    static func scan(isCancelled: () -> Bool = { false }) -> Plan {
        var plan = Plan()
        guard let documents else { return plan }
        walk(documents, parts: [], inGame: false, into: &plan.items, isCancelled: isCancelled)
        return plan
    }

    private static let scanKeys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]

    private static func walk(_ directory: URL, parts: [String], inGame: Bool, into items: inout [Item], isCancelled: () -> Bool) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: scanKeys, options: []) else { return }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if isCancelled() { return }
            guard let values = try? child.resourceValues(forKeys: Set(scanKeys)),
                  values.isSymbolicLink != true else { continue }
            let isDirectory = values.isDirectory == true
            let childParts = parts + [child.lastPathComponent]
            let decision = decide(for: childParts, isDirectory: isDirectory, inGame: inGame)
            guard decision.include else { continue }
            if isDirectory {
                walk(child, parts: childParts, inGame: decision.game, into: &items, isCancelled: isCancelled)
            } else if values.isRegularFile == true {
                let modified = Int64((values.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970)
                items.append(Item(relativePath: childParts.joined(separator: "/"), url: child,
                                  size: Int64(values.fileSize ?? 0), modified: modified, isGame: decision.game))
            }
        }
    }

    /// Whether an entry travels, and whether it counts as a game. A folder's verdict covers what is inside it.
    private static func decide(for parts: [String], isDirectory: Bool, inGame: Bool) -> (include: Bool, game: Bool) {
        let lower = parts.map { $0.lowercased() }
        let name = lower[lower.count - 1]
        // Staging folders, caches the app rebuilds, Finder leftovers.
        if name.hasPrefix(".") { return (false, false) }
        if inGame { return (true, true) }

        if parts.count == 1, ["migration", "recordings", "save-backups", "inbox"].contains(name) {
            return (false, false)
        }
        if lower[0] == "roms" {
            if parts.count == 1 { return (true, false) }
            // A dump folder is a game. A loose file is one too unless it's a cover or other small companion.
            if isDirectory { return (true, true) }
            return (true, gameExtensions.contains((name as NSString).pathExtension))
        }
        if lower[0] == "mlc" {
            if parts.count == 2, name == "logs" || (!isDirectory && name.hasPrefix("log")) { return (false, false) }
            // Of the engine's caches only the compiled shaders are worth carrying: they save a long recompile.
            if parts.count >= 3, lower[1] == "cache", lower[2] != "shadercache" { return (false, false) }
            if parts.count >= 5, lower[1] == "mlc01", lower[2] == "usr", lower[3] == "title", lower[4] == "00050000" {
                return (true, true)
            }
        }
        return (true, false)
    }

    // MARK: - Export

    struct ExportResult {
        let url: URL
        let bytes: Int64
        let fileCount: Int
    }

    /// Writes the archive into Documents/Migration. `progress` gets (bytes done, bytes total, current file).
    static func export(plan: Plan,
                       includeGames: Bool,
                       progress: (Int64, Int64, String) -> Void,
                       isCancelled: () -> Bool) throws -> ExportResult {
        guard let documents else { throw MigrationError.noDocuments }
        let fm = FileManager.default
        let items = plan.chosen(includeGames: includeGames)
        let total = items.reduce(Int64(0)) { $0 + $1.size }

        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let estimate = plan.archiveBytes(includeGames: includeGames)
        // A same-day export is replaced, so its space counts as free.
        let name = "MuffinEMU move \(dayStamp()).\(fileExtension)"
        let final = folder.appendingPathComponent(name)
        let partial = folder.appendingPathComponent(name + ".partial")
        try? fm.removeItem(at: partial)
        let reusable = ((try? fm.attributesOfItem(atPath: final.path))?[.size] as? NSNumber)?.int64Value ?? 0
        let needed = spaceNeeded(for: estimate)
        if let free = freeSpace(), free + reusable < needed {
            throw MigrationError.notEnoughSpace(needed: needed, free: free + reusable)
        }

        guard fm.createFile(atPath: partial.path, contents: nil) else { throw MigrationError.noDocuments }
        let out = try FileHandle(forWritingTo: partial)
        var finished = false
        defer {
            try? out.close()
            if !finished { try? fm.removeItem(at: partial) }
        }

        var position: Int64 = 0
        func put(_ data: Data) throws {
            try out.write(contentsOf: data)
            position += Int64(data.count)
        }

        try put(headMagic)
        var entries: [Manifest.File] = []
        entries.reserveCapacity(items.count + 2)
        var done: Int64 = 0
        let now = Int64(Date().timeIntervalSince1970)

        // Settings and app state first: small, and the importer applies them last.
        let meta = [(settingsPath, try SettingsBackup.exportData()), (statePath, try SettingsBackup.exportStateData())]
        for (path, data) in meta {
            let pathBytes = Data(path.utf8)
            try put(littleEndian(UInt16(pathBytes.count)))
            try put(pathBytes)
            try put(littleEndian(UInt64(data.count)))
            let offset = position
            try put(data)
            let crc = MiniZip.crc32(data)
            try put(littleEndian(crc))
            entries.append(Manifest.File(path: path, size: Int64(data.count), modified: now, crc32: crc, offset: offset))
        }

        for item in items {
            if isCancelled() { throw MigrationError.cancelled }
            progress(done, total, item.relativePath)
            guard let reader = try? FileHandle(forReadingFrom: item.url) else {
                throw MigrationError.changedWhileReading(item.relativePath)
            }
            defer { try? reader.close() }

            let pathBytes = Data(item.relativePath.utf8)
            try put(littleEndian(UInt16(pathBytes.count)))
            try put(pathBytes)
            try put(littleEndian(UInt64(item.size)))
            let offset = position

            var crc: UInt32 = 0
            var remaining = item.size
            while remaining > 0 {
                if isCancelled() { throw MigrationError.cancelled }
                try autoreleasepool {
                    let want = Int(min(Int64(chunkSize), remaining))
                    guard let chunk = try reader.read(upToCount: want), !chunk.isEmpty else {
                        throw MigrationError.changedWhileReading(item.relativePath)
                    }
                    crc = MiniZip.crc32(continuing: crc, with: chunk)
                    try put(chunk)
                    remaining -= Int64(chunk.count)
                    done += Int64(chunk.count)
                    progress(done, total, item.relativePath)
                }
            }
            try put(littleEndian(crc))
            entries.append(Manifest.File(path: item.relativePath, size: item.size, modified: item.modified, crc32: crc, offset: offset))
        }

        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "0") + " (" + (info?["CFBundleVersion"] as? String ?? "0") + ")"
        let manifest = Manifest(format: formatName, version: currentVersion,
                                sourceBundleID: Bundle.main.bundleIdentifier ?? "unknown",
                                appVersion: version, created: ISO8601DateFormatter().string(from: Date()),
                                includesGames: includeGames, files: entries)
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestOffset = position
        try put(manifestData)
        try put(littleEndian(UInt64(manifestOffset)))
        try put(littleEndian(UInt64(manifestData.count)))
        try put(tailMagic)
        try out.synchronize()
        try out.close()

        try? fm.removeItem(at: final)
        try fm.moveItem(at: partial, to: final)
        finished = true
        // The archive can be large and is a copy of data that is already here: keep it out of device backups.
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var target = final
        try? target.setResourceValues(excluded)
        return ExportResult(url: final, bytes: position, fileCount: items.count)
    }

    /// Archives already in Documents/Migration, newest first.
    static func existingExports() -> [(url: URL, bytes: Int64)] {
        guard let documents else { return [] }
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == fileExtension }
            .compactMap { url -> (URL, Int64, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.2 > $1.2 }
            .map { ($0.0, $0.1) }
    }

    // MARK: - Import: reading

    /// Reads and checks the header, trailer and manifest. Nothing is written.
    static func readManifest(of url: URL) throws -> Manifest {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw MigrationError.notAnArchive }
        defer { try? handle.close() }
        return try readManifest(from: handle)
    }

    private static func readManifest(from handle: FileHandle) throws -> Manifest {
        let size = (try? handle.seekToEnd()) ?? 0
        guard size >= UInt64(headMagic.count + trailerSize) else { throw MigrationError.notAnArchive }
        try handle.seek(toOffset: 0)
        guard try readExactly(handle, headMagic.count) == headMagic else { throw MigrationError.notAnArchive }

        try handle.seek(toOffset: size - UInt64(trailerSize))
        let trailer = try readExactly(handle, trailerSize)
        guard trailer.suffix(8) == tailMagic else { throw MigrationError.damaged("the end of the file is missing") }
        let manifestOffset = readUInt64(trailer, 0)
        let manifestLength = readUInt64(trailer, 8)
        guard manifestLength > 0, manifestLength <= maxManifestBytes,
              manifestOffset >= UInt64(headMagic.count),
              manifestOffset + manifestLength <= size - UInt64(trailerSize) else {
            throw MigrationError.damaged("the file list position")
        }

        try handle.seek(toOffset: manifestOffset)
        let data = try readExactly(handle, Int(manifestLength))
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.format == formatName else { throw MigrationError.damaged("the file list") }
        guard manifest.version <= currentVersion else { throw MigrationError.newerVersion(manifest.version) }

        for file in manifest.files {
            let isMeta = file.path == settingsPath || file.path == statePath
            guard isMeta || destinationParts(for: file.path) != nil,
                  file.size >= 0, file.offset >= Int64(headMagic.count),
                  UInt64(file.offset + file.size) <= manifestOffset else {
                throw MigrationError.damaged("an entry in the file list: \(file.path)")
            }
        }
        return manifest
    }

    /// The cleaned path components for a file, or nil if it would leave Documents or isn't a real file path.
    private static func destinationParts(for path: String) -> [String]? {
        guard let parts = try? MiniZip.safeComponents(path), !parts.isEmpty, parts.joined(separator: "/") == path,
              parts[0] != "_meta" else { return nil }
        return parts
    }

    private static func destination(for path: String) -> URL? {
        guard let documents, let parts = destinationParts(for: path) else { return nil }
        return parts.reduce(documents) { $0.appendingPathComponent($1) }
    }

    // MARK: - Import: comparing

    struct Analysis {
        let url: URL
        let manifest: Manifest
        var newFiles: [Manifest.File] = []
        /// Here already, but older than the archive's copy.
        var updatedFiles: [Manifest.File] = []
        /// Here already and newer than the archive's copy, with different contents.
        var conflicts: [Manifest.File] = []
        var identicalCount = 0
        /// Something that isn't a file is in the way.
        var blockedCount = 0
        var hasSettings = false
        var hasState = false

        var bytesToWrite: Int64 { (newFiles + updatedFiles).reduce(0) { $0 + $1.size } }
        var conflictBytes: Int64 { conflicts.reduce(0) { $0 + $1.size } }
        var fileCount: Int { newFiles.count + updatedFiles.count + conflicts.count + identicalCount + blockedCount }
        var isFromThisApp: Bool { manifest.sourceBundleID == Bundle.main.bundleIdentifier }
    }

    /// Compares the archive with what is on the device, without changing anything.
    static func analyse(url: URL, isCancelled: () -> Bool) throws -> Analysis {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let manifest = try readManifest(of: url)
        var analysis = Analysis(url: url, manifest: manifest)
        let fm = FileManager.default

        for file in manifest.files {
            if isCancelled() { throw MigrationError.cancelled }
            if file.path == settingsPath { analysis.hasSettings = true; continue }
            if file.path == statePath { analysis.hasState = true; continue }
            guard let target = destination(for: file.path) else { throw MigrationError.damaged(file.path) }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
                analysis.newFiles.append(file)
                continue
            }
            if isDirectory.boolValue { analysis.blockedCount += 1; continue }

            let attributes = try? fm.attributesOfItem(atPath: target.path)
            let localSize = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let localTime = Int64(((attributes?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970)
            if localSize == file.size, abs(localTime - file.modified) <= timeTolerance {
                analysis.identicalCount += 1
            } else if localTime > file.modified + timeTolerance {
                // Newer here. A copy with the same contents is not a conflict, whatever its date says.
                if localSize == file.size, try crc32(of: target, isCancelled: isCancelled) == file.crc32 {
                    analysis.identicalCount += 1
                } else {
                    analysis.conflicts.append(file)
                }
            } else {
                analysis.updatedFiles.append(file)
            }
        }
        return analysis
    }

    // MARK: - Import: writing

    struct RestoreResult {
        var written = 0
        var bytes: Int64 = 0
        /// Files the person chose to keep because the ones here were newer.
        var keptNewer = 0
        /// Folder holding the saves that were replaced, if any were.
        var savesBackup: URL?
        var settingsData: Data?
        var stateData: Data?
    }

    /// Writes the files the comparison marked, and reads the settings and state back out for the caller to apply.
    /// `replaceNewer` decides the conflicts: false keeps the files here, true replaces them with the archive's.
    static func restore(_ analysis: Analysis,
                        replaceNewer: Bool,
                        progress: (Int64, Int64, String) -> Void,
                        isCancelled: () -> Bool) throws -> RestoreResult {
        guard let documents else { throw MigrationError.noDocuments }
        let scoped = analysis.url.startAccessingSecurityScopedResource()
        defer { if scoped { analysis.url.stopAccessingSecurityScopedResource() } }

        let todo = analysis.newFiles + analysis.updatedFiles + (replaceNewer ? analysis.conflicts : [])
        let total = todo.reduce(Int64(0)) { $0 + $1.size }
        let needed = spaceNeeded(for: total)
        if let free = freeSpace(), free < needed { throw MigrationError.notEnoughSpace(needed: needed, free: free) }

        guard let reader = try? FileHandle(forReadingFrom: analysis.url) else { throw MigrationError.notAnArchive }
        defer { try? reader.close() }

        var result = RestoreResult(keptNewer: replaceNewer ? 0 : analysis.conflicts.count)
        let fm = FileManager.default
        let backupRoot = documents.appendingPathComponent("save-backups/migration-\(fileStamp())", isDirectory: true)
        var done: Int64 = 0

        for file in todo {
            if isCancelled() { throw MigrationError.cancelled }
            progress(done, total, file.path)
            guard let target = destination(for: file.path) else { throw MigrationError.damaged(file.path) }
            let folder = target.deletingLastPathComponent()
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let temporary = folder.appendingPathComponent(".\(UUID().uuidString).moving")
            guard fm.createFile(atPath: temporary.path, contents: nil) else { throw MigrationError.noDocuments }
            let writer = try FileHandle(forWritingTo: temporary)
            var moved = false
            defer {
                try? writer.close()
                if !moved { try? fm.removeItem(at: temporary) }
            }

            try reader.seek(toOffset: UInt64(file.offset))
            var crc: UInt32 = 0
            var remaining = file.size
            while remaining > 0 {
                if isCancelled() { throw MigrationError.cancelled }
                try autoreleasepool {
                    let want = Int(min(Int64(chunkSize), remaining))
                    guard let chunk = try reader.read(upToCount: want), !chunk.isEmpty else {
                        throw MigrationError.damaged("\(file.path) is cut short")
                    }
                    crc = MiniZip.crc32(continuing: crc, with: chunk)
                    try writer.write(contentsOf: chunk)
                    remaining -= Int64(chunk.count)
                    done += Int64(chunk.count)
                    progress(done, total, file.path)
                }
            }
            try writer.close()
            guard crc == file.crc32 else { throw MigrationError.damaged("checksum of \(file.path)") }

            if fm.fileExists(atPath: target.path) {
                if file.path.lowercased().hasPrefix("mlc/mlc01/usr/save/") {
                    // A save that is replaced is moved aside, never deleted. Outside mlc on purpose, so
                    // the engine doesn't scan the backup as another title.
                    let aside = backupRoot.appendingPathComponent(file.path)
                    try fm.createDirectory(at: aside.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: target, to: aside)
                    result.savesBackup = backupRoot
                    try fm.moveItem(at: temporary, to: target)
                } else {
                    _ = try fm.replaceItemAt(target, withItemAt: temporary)
                }
            } else {
                try fm.moveItem(at: temporary, to: target)
            }
            moved = true
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: TimeInterval(file.modified))], ofItemAtPath: target.path)
            result.written += 1
            result.bytes += file.size
        }

        for file in analysis.manifest.files where file.path == settingsPath || file.path == statePath {
            guard file.size <= maxMetaBytes else { throw MigrationError.damaged(file.path) }
            try reader.seek(toOffset: UInt64(file.offset))
            let data = try readExactly(reader, Int(file.size))
            guard MiniZip.crc32(data) == file.crc32 else { throw MigrationError.damaged("checksum of \(file.path)") }
            if file.path == settingsPath { result.settingsData = data } else { result.stateData = data }
        }
        progress(total, total, "")
        return result
    }

    // MARK: - Bytes

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func readUInt64(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(data[data.startIndex + offset + index]) << UInt64(8 * index) }
        return value
    }

    /// Exactly `count` bytes, or an error: a short read means the file ends early.
    private static func readExactly(_ handle: FileHandle, _ count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let piece = try handle.read(upToCount: count - data.count), !piece.isEmpty else {
                throw MigrationError.damaged("the file ends early")
            }
            data.append(piece)
        }
        return data
    }

    private static func crc32(of url: URL, isCancelled: () -> Bool) throws -> UInt32 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        var crc: UInt32 = 0
        var finished = false
        while !finished {
            if isCancelled() { throw MigrationError.cancelled }
            try autoreleasepool {
                if let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                    crc = MiniZip.crc32(continuing: crc, with: chunk)
                } else {
                    finished = true
                }
            }
        }
        return crc
    }

    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func fileStamp() -> String {
        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}
