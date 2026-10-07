import Foundation
import SwiftUI

/// One game found in a linked location, remembered so the library can still list it (greyed out, "Connect the drive to
/// play") while the drive is unplugged or the bookmark won't resolve.
struct ExternalGameRecord: Codable, Equatable {
    var id: String
    /// The library entry (the file, or the dump's top folder) relative to the location's root. "" for a linked single file.
    var itemRel: String
    /// What the core boots (the file, the .rpx inside code/, or title.tmd) relative to the location's root.
    var bootRel: String
    var titleId: UInt64?
}

/// A folder or a single game file the player linked instead of importing. Nothing in it is ever copied, moved or deleted.
struct LinkedLocation: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case folder, file }

    let id: String
    var kind: Kind
    var name: String
    /// Security-scoped bookmark, made while the picker's access was still held.
    var bookmark: Data
    /// Where the bookmark last resolved to. Only used to build a path to show for an unavailable game.
    var lastPath: String
    /// Library entries (relative to the root) the player removed from the library. The files stay where they are.
    var hidden: [String] = []
    /// What the last successful scan found here.
    var games: [ExternalGameRecord] = []
}

/// Linked locations: the bookmarks, the access that keeps them readable, and the walk that finds games in them.
///
/// Access is held in exactly two situations: while the library scans (or reads a game's files for covers and names), and
/// from the moment a game from the location starts until it stops. Both go through `acquire` / `release`, which keep the
/// same resolved URL object for the start and the matching stop.
final class ExternalLibrary: ObservableObject, @unchecked Sendable {
    static let shared = ExternalLibrary()

    /// For the Settings list. Written on the main thread only; `stored` below is the source of truth.
    @Published private(set) var locations: [LinkedLocation] = []
    /// Whether each location was readable at the last scan.
    @Published private(set) var availability: [String: Bool] = [:]

    private let lock = NSLock()
    private var stored: [LinkedLocation] = []
    private var resolved: [String: URL] = [:]
    private let fileURL: URL

    static let unavailableMessage = "Connect the drive to play"

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("MuffinEMU", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("LinkedLocations.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([LinkedLocation].self, from: data) {
            stored = decoded
            locations = decoded
        }
    }

    // MARK: State

    func snapshot() -> [LinkedLocation] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func location(_ id: String) -> LinkedLocation? {
        lock.lock(); defer { lock.unlock() }
        return stored.first { $0.id == id }
    }

    private func mutate(_ body: (inout [LinkedLocation]) -> Void) {
        lock.lock()
        let before = stored
        body(&stored)
        let after = stored
        lock.unlock()
        guard after != before else { return }
        if let data = try? JSONEncoder().encode(after) {
            try? data.write(to: fileURL, options: .atomic)
        }
        DispatchQueue.main.async { self.locations = after }
    }

    func setAvailability(_ value: [String: Bool]) {
        DispatchQueue.main.async { if self.availability != value { self.availability = value } }
    }

    // MARK: Access

    /// Proof that access to a location is held. Pass it to `release` when done.
    struct Hold {
        let locationID: String
        let url: URL
        fileprivate let scoped: Bool
    }

    /// Resolves the location's bookmark (refreshing a stale one), then starts security-scoped access. Nil when the bookmark
    /// won't resolve, which is what an unplugged drive looks like.
    func acquire(_ id: String, reresolve: Bool = false) -> Hold? {
        guard let url = resolve(id, force: reresolve) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        return Hold(locationID: id, url: url, scoped: scoped)
    }

    func release(_ hold: Hold) {
        if hold.scoped { hold.url.stopAccessingSecurityScopedResource() }
    }

    private func resolve(_ id: String, force: Bool) -> URL? {
        lock.lock()
        if !force, let cached = resolved[id] { lock.unlock(); return cached }
        let bookmark = stored.first { $0.id == id }?.bookmark
        lock.unlock()
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            lock.lock(); resolved[id] = nil; lock.unlock()
            return nil
        }
        lock.lock(); resolved[id] = url; lock.unlock()
        if stale { refreshBookmark(id, url) }
        return url
    }

    /// A bookmark iOS says is stale still resolves; making a fresh one from the resolved URL keeps it working next time.
    private func refreshBookmark(_ id: String, _ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == id }) {
                list[index].bookmark = data
                list[index].lastPath = url.path
            }
        }
    }

    /// True when `path` can be read right now. Used before a launch and every couple of seconds while a linked game runs.
    static func isReachable(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Resolves the location again, holds access just long enough to see that the game's file is there, and lets go.
    func probe(_ id: String, path: String) -> Bool {
        guard let hold = acquire(id, reresolve: true) else { return false }
        defer { release(hold) }
        return Self.isReachable(path: path)
    }

    // MARK: Linking

    enum LinkError: LocalizedError {
        case accessDenied
        case notReadable(String)
        case unsupportedFile(String)
        case bookmarkFailed(Error)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Couldn't access that location."
            case .notReadable(let name):
                return "MuffinEMU can't read \"\(name)\". If it's on a drive, make sure the drive is connected."
            case .unsupportedFile(let name):
                return "\"\(name)\" isn't a Wii U game file MuffinEMU can read. It accepts .wua, .wux, .wud, .iso, .rpx, .elf and .wuhb files."
            case .bookmarkFailed(let error):
                return "Couldn't keep access to that location: \(error.localizedDescription)"
            }
        }
    }

    /// Links a folder or a game file the picker handed back, in place. `picked` carries the picker's security scope; the
    /// bookmark is made while that scope is held, and nothing is copied.
    @discardableResult
    func link(_ picked: URL) throws -> LinkedLocation {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDirectory) else {
            throw LinkError.accessDenied
        }
        let kind: LinkedLocation.Kind = isDirectory.boolValue ? .folder : .file
        switch kind {
        case .folder:
            guard (try? FileManager.default.contentsOfDirectory(atPath: picked.path)) != nil else {
                throw LinkError.notReadable(picked.lastPathComponent)
            }
        case .file:
            guard GameManager.supportedROMExtensions.contains(picked.pathExtension.lowercased()),
                  GameManager.isValidROMFile(at: picked) else {
                throw LinkError.unsupportedFile(picked.lastPathComponent)
            }
        }

        let path = picked.standardizedFileURL.path
        if let existing = snapshot().first(where: { $0.lastPath == path && $0.kind == kind }) {
            return existing
        }

        let data: Data
        do {
            data = try picked.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw LinkError.bookmarkFailed(error)
        }
        let location = LinkedLocation(id: UUID().uuidString, kind: kind, name: picked.lastPathComponent, bookmark: data, lastPath: path)
        mutate { $0.append(location) }
        lock.lock(); resolved[location.id] = picked; lock.unlock()
        return location
    }

    /// Forgets a linked location. Only the bookmark and the list of what was found go; nothing on the drive is touched.
    func unlink(_ id: String) {
        lock.lock(); resolved[id] = nil; lock.unlock()
        mutate { $0.removeAll { $0.id == id } }
    }

    /// Takes one library entry out of the library without touching its file. A linked single file is the whole location, so
    /// that one is unlinked instead.
    func removeFromLibrary(locationID: String, gameID: String) {
        guard let location = location(locationID) else { return }
        if location.kind == .file { unlink(locationID); return }
        guard let record = location.games.first(where: { $0.id == gameID }) else { return }
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == locationID }), !list[index].hidden.contains(record.itemRel) {
                list[index].hidden.append(record.itemRel)
                list[index].games.removeAll { $0.id == gameID }
            }
        }
    }

    func restoreHidden(_ id: String) {
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == id }) { list[index].hidden = [] }
        }
    }

    func updateRecords(_ id: String, _ records: [ExternalGameRecord], path: String) {
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == id }) {
                list[index].games = records
                list[index].lastPath = path
            }
        }
    }

    // MARK: Finding games

    /// Library entries inside a linked location, recursively, in the same shape the Roms scan works on: a game file, or the
    /// top folder of a dump. Nil when the location can't be read, which the library treats as "drive not connected".
    func discover(_ location: LinkedLocation, root: URL) -> [URL]? {
        switch location.kind {
        case .file:
            return FileManager.default.fileExists(atPath: root.path) ? [root] : nil
        case .folder:
            guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else { return nil }
            var found: [URL] = []
            Self.walk(root, depth: 0, into: &found)
            return found
        }
    }

    private static let maxDepth = 10
    private static let skippedFolderNames: Set<String> = ["$recycle.bin", "system volume information", "lost+found"]

    private static func walk(_ directory: URL, depth: Int, into found: inout [URL]) {
        // A dump (code/content/meta) is one game; its insides are not games.
        if GameManager.looksLikeWiiUDump(directory) {
            if GameManager.executableInDump(directory) != nil { found.append(directory) }
            return
        }
        // An encrypted game folder with its own title.tmd.
        if GameManager.titleTmdInDump(directory) != nil {
            found.append(directory)
            return
        }
        // "Game (USA)" holding Game, Update and DLC folders: one base game plus companions is a single game.
        let tmdChildren = GameManager.nusTitleFolders(in: directory, maxDepth: 1)
        if tmdChildren.filter({ $0.kind == .base }).count == 1, tmdChildren.count > 1 {
            found.append(directory)
            return
        }
        guard depth < maxDepth,
              let children = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = child.lastPathComponent
            // Hidden files and the "._Game.wua" AppleDouble companions exFAT drives collect.
            if name.hasPrefix(".") || skippedFolderNames.contains(name.lowercased()) { continue }
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                walk(child, depth: depth + 1, into: &found)
            } else if GameManager.supportedROMExtensions.contains(child.pathExtension.lowercased()) {
                found.append(child)
            }
        }
    }

    static func relativePath(of url: URL, under root: URL) -> String {
        let path = url.path
        let base = root.path
        if path == base { return "" }
        if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        return url.lastPathComponent
    }
}
