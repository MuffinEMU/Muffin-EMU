// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation
import CryptoKit
import SwiftUI

// MARK: - Manifest

/// The art pack manifest published at github.com/MuffinEMU/MuffinEMU-Art. Only the fields the app
/// reads are declared; anything else in the file is ignored.
struct ArtManifest: Codable {
    var version: Int?
    var normalization: String?
    var packs: [ArtPack]
    var generic: [ArtGenericImage]?
    var index: [ArtIndexEntry]
}

struct ArtPackFile: Codable {
    let name: String
    let size: Int64
    let sha256: String
    let url: String
}

struct ArtPack: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    /// "3d", "2d" or "disc".
    let style: String
    let credits: String
    let files: [ArtPackFile]
    let imageCount: Int
    let imageSize: String

    var downloadBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var styleTitle: String {
        switch style {
        case "3d": return "3D box"
        case "disc": return "Disc"
        default: return "2D cover"
        }
    }
}

struct ArtGenericImage: Codable {
    let id: String
    let style: String
    let url: String
}

struct ArtIndexEntry: Codable {
    let file: String
    let title: String
    let normalizedTitle: String
    let region: String?
    let pack: String
}

// MARK: - Installed packs, read from disk

/// What is stored with one installed pack, next to its images.
struct InstalledPackMeta: Codable {
    var id: String
    var name: String
    var style: String
    var credits: String
    var imageCount: Int
    var bytesOnDisk: Int64
    var installedAt: Date
    /// Position in the manifest, so ties between packs of one style resolve the same way every time.
    var order: Int
}

struct PackIndexRecord: Codable {
    let file: String
    let normalizedTitle: String
    let region: String?
}

struct PackArtHit {
    let packID: String
    let path: String
    /// The art's own region matched one of the install's regions.
    let regionMatched: Bool
}

/// Thread-safe, synchronous lookup over every installed pack's index. Loaded lazily from disk and
/// reloaded after an install or a delete. Cover lookups call this on every library scan, so it is
/// plain dictionaries behind a lock and never touches the network.
final class ArtPackIndex {
    static let shared = ArtPackIndex()

    private struct Loaded {
        var meta: InstalledPackMeta
        var byTitle: [String: [PackIndexRecord]]
        var directory: URL
    }

    private let lock = NSLock()
    private var packs: [String: Loaded]?
    /// Changes on every reload, so callers that cache lookups know to drop them.
    private(set) var generation = 0

    static func metaURL(_ id: String) -> URL { ArtLocations.packDirectory(id).appendingPathComponent("meta.json") }
    static func indexURL(_ id: String) -> URL { ArtLocations.packDirectory(id).appendingPathComponent("index.json") }
    static func filesURL(_ id: String) -> URL { ArtLocations.packDirectory(id).appendingPathComponent("files", isDirectory: true) }

    func reload() {
        lock.lock(); packs = nil; generation += 1; lock.unlock()
    }

    private func loaded() -> [String: Loaded] {
        lock.lock(); defer { lock.unlock() }
        if let packs { return packs }
        var result: [String: Loaded] = [:]
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: ArtLocations.packsDirectory.path)) ?? []
        for id in ids {
            guard let metaData = try? Data(contentsOf: Self.metaURL(id)),
                  let meta = try? JSONDecoder.iso.decode(InstalledPackMeta.self, from: metaData),
                  let indexData = try? Data(contentsOf: Self.indexURL(id)),
                  let records = try? JSONDecoder().decode([PackIndexRecord].self, from: indexData) else { continue }
            var map: [String: [PackIndexRecord]] = [:]
            for r in records {
                map[r.normalizedTitle, default: []].append(r)
                let loose = ArtTitleNormalizer.loose(r.normalizedTitle)
                if !loose.isEmpty, loose != r.normalizedTitle { map[loose, default: []].append(r) }
            }
            result[id] = Loaded(meta: meta, byTitle: map, directory: Self.filesURL(id))
        }
        packs = result
        return result
    }

    var installedMeta: [InstalledPackMeta] {
        loaded().values.map { $0.meta }.sorted { $0.order < $1.order }
    }

    func isInstalled(_ id: String) -> Bool { loaded()[id] != nil }
    func meta(_ id: String) -> InstalledPackMeta? { loaded()[id]?.meta }
    var hasAnyPack: Bool { !loaded().isEmpty }

    /// Paths of up to `count` images from one installed pack, spread across its index, for previews.
    func samplePaths(_ id: String, count: Int) -> [String] {
        guard let pack = loaded()[id] else { return [] }
        let files = pack.byTitle.keys.sorted().compactMap { pack.byTitle[$0]?.first?.file }
        guard !files.isEmpty, count > 0 else { return [] }
        let step = max(files.count / count, 1)
        return stride(from: 0, to: files.count, by: step).prefix(count).map { pack.directory.appendingPathComponent(files[$0]).path }
    }

    /// Art for the first candidate title (best first) that any installed pack of one of `styles`
    /// has. Styles are tried in the order given, packs of one style in manifest order. Within a
    /// pack, art whose region matches the install wins over art for another region.
    func lookup(candidates: [String], styles: [String], regions: Set<RegionCode>, onlyPack: String? = nil) -> PackArtHit? {
        let all = loaded()
        guard !all.isEmpty, !candidates.isEmpty else { return nil }
        for style in styles {
            let ofStyle = all.values.filter { $0.meta.style == style && (onlyPack == nil || $0.meta.id == onlyPack) }.sorted { $0.meta.order < $1.meta.order }
            var keys: [String] = []
            for c in candidates where !c.isEmpty {
                for k in [c, ArtTitleNormalizer.loose(c)] where !k.isEmpty && !keys.contains(k) { keys.append(k) }
            }
            for candidate in keys {
                for pack in ofStyle {
                    guard let records = pack.byTitle[candidate] else { continue }
                    let matched = records.first { r in
                        !regions.isEmpty && !RegionCode.codes(in: r.region).isDisjoint(with: regions)
                    }
                    guard let pick = matched ?? records.first else { continue }
                    let path = pack.directory.appendingPathComponent(pick.file).path
                    if FileManager.default.fileExists(atPath: path) {
                        return PackArtHit(packID: pack.meta.id, path: path, regionMatched: matched != nil)
                    }
                }
            }
        }
        // Last resort: one pack title that starts with the game's loose name, or the other way round
        // ("mario kart 8" vs "mario kart 8 deluxe edition"). Only taken when exactly one title fits,
        // so a short or generic name never grabs the wrong game's art.
        let looseKeys = candidates.map(ArtTitleNormalizer.loose).filter { $0.count >= 8 }
        for style in styles {
            let ofStyle = all.values.filter { $0.meta.style == style && (onlyPack == nil || $0.meta.id == onlyPack) }.sorted { $0.meta.order < $1.meta.order }
            for loose in looseKeys {
                for pack in ofStyle {
                    let fits = pack.byTitle.keys.filter { !$0.contains(" ") && $0.count >= 8 && ($0.hasPrefix(loose) || loose.hasPrefix($0)) }
                    guard fits.count == 1, let key = fits.first, let records = pack.byTitle[key] else { continue }
                    let matched = records.first { r in !regions.isEmpty && !RegionCode.codes(in: r.region).isDisjoint(with: regions) }
                    guard let pick = matched ?? records.first else { continue }
                    let path = pack.directory.appendingPathComponent(pick.file).path
                    if FileManager.default.fileExists(atPath: path) {
                        return PackArtHit(packID: pack.meta.id, path: path, regionMatched: matched != nil)
                    }
                }
            }
        }
        return nil
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

// MARK: - Store

enum ArtPackError: LocalizedError {
    case notEnoughSpace(need: Int64, have: Int64)
    case badChecksum(String)
    case http(Int)
    case noManifest
    case failed(String)

    var errorDescription: String? {
        let fmt = { (b: Int64) in ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        switch self {
        case .notEnoughSpace(let need, let have):
            return "Not enough free space. This pack needs about \(fmt(need)) while it installs (the download plus the unpacked images), and this device has \(fmt(have)) free. Free some space and try again."
        case .badChecksum(let name):
            return "The download of \(name) didn't match its checksum, so it was thrown away. Try again."
        case .http(let code):
            return "The download server answered with error \(code)."
        case .noManifest:
            return "The art pack list couldn't be loaded. Check your connection and try again."
        case .failed(let message):
            return message
        }
    }
}

/// Where the art pack list, downloads, unpacking and indexing happen. The UI observes this.
final class ArtPackStore: ObservableObject {
    static let shared = ArtPackStore()
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/MuffinEMU/MuffinEMU-Art/main/manifest.json")!
    static let repoURL = URL(string: "https://github.com/MuffinEMU/MuffinEMU-Art")!

    struct PackProgress: Equatable {
        var phase: String
        var fraction: Double
    }

    @Published private(set) var manifest: ArtManifest?
    @Published private(set) var isLoadingManifest = false
    @Published private(set) var manifestError: String?
    @Published private(set) var installed: [InstalledPackMeta] = []
    @Published private(set) var progress: [String: PackProgress] = [:]
    @Published private(set) var errors: [String: String] = [:]

    private final class CancelFlag {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }
    private var flags: [String: CancelFlag] = [:]
    private var downloaders: [String: PackDownload] = [:]

    private static var cachedManifestURL: URL { ArtLocations.dataDirectory.appendingPathComponent("art-manifest.json") }

    private init() {
        installed = ArtPackIndex.shared.installedMeta
        if let data = try? Data(contentsOf: Self.cachedManifestURL), let m = try? JSONDecoder().decode(ArtManifest.self, from: data) {
            manifest = m
        }
    }

    func isBusy(_ id: String) -> Bool { progress[id] != nil }

    // MARK: Manifest

    func refreshManifest() {
        guard !isLoadingManifest else { return }
        isLoadingManifest = true
        manifestError = nil
        Task {
            do {
                var request = URLRequest(url: Self.manifestURL)
                request.setValue("MuffinEMU", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 30
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw ArtPackError.http(http.statusCode) }
                let decoded = try JSONDecoder().decode(ArtManifest.self, from: data)
                try? data.write(to: Self.cachedManifestURL, options: .atomic)
                await MainActor.run { self.manifest = decoded; self.isLoadingManifest = false }
            } catch {
                await MainActor.run {
                    self.isLoadingManifest = false
                    self.manifestError = self.manifest == nil
                        ? "Couldn't load the art pack list: \(error.localizedDescription)"
                        : "Couldn't check for new packs. Showing the last list MuffinEMU saved."
                }
            }
        }
    }

    // MARK: Install

    func cancel(_ id: String) {
        flags[id]?.set()
        downloaders[id]?.cancel()
    }

    func install(_ pack: ArtPack) {
        guard progress[pack.id] == nil else { return }
        // Space for the zip and the unpacked images together, plus a margin; both exist at once.
        let need = pack.downloadBytes * 2 + 64 * 1024 * 1024
        if let have = ArtLocations.availableBytes(), have < need {
            errors[pack.id] = ArtPackError.notEnoughSpace(need: need, have: have).errorDescription
            return
        }
        errors[pack.id] = nil
        let flag = CancelFlag()
        flags[pack.id] = flag
        progress[pack.id] = PackProgress(phase: "Starting", fraction: 0)
        let order = manifest?.packs.firstIndex { $0.id == pack.id } ?? 0
        let entries = manifest?.index.filter { $0.pack == pack.id } ?? []

        Task {
            do {
                try await self.run(pack, order: order, entries: entries, flag: flag)
                await MainActor.run {
                    self.finish(pack.id)
                    self.installed = ArtPackIndex.shared.installedMeta
                    NotificationCenter.default.post(name: .muffinCoverArtSourcesChanged, object: nil)
                }
            } catch {
                await MainActor.run {
                    self.finish(pack.id)
                    if flag.isSet || error is CancellationError {
                        self.errors[pack.id] = nil
                    } else {
                        self.errors[pack.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
        }
    }

    private func finish(_ id: String) {
        progress[id] = nil
        flags[id] = nil
        downloaders[id] = nil
    }

    private func setProgress(_ id: String, _ phase: String, _ fraction: Double) {
        DispatchQueue.main.async { if self.flags[id] != nil { self.progress[id] = PackProgress(phase: phase, fraction: fraction) } }
    }

    private func run(_ pack: ArtPack, order: Int, entries: [ArtIndexEntry], flag: CancelFlag) async throws {
        let fm = FileManager.default
        let partial = ArtLocations.packsDirectory.appendingPathComponent(".\(pack.id).partial", isDirectory: true)
        try? fm.removeItem(at: partial)
        let files = partial.appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: files, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: partial) }

        var imageCount = 0
        let totalFiles = max(pack.files.count, 1)
        for (n, file) in pack.files.enumerated() {
            guard let url = URL(string: file.url) else { throw ArtPackError.failed("The pack's download address is invalid.") }
            let zip = ArtLocations.downloadsDirectory.appendingPathComponent("\(pack.id)-\(n).zip")
            try? fm.removeItem(at: zip)
            defer { try? fm.removeItem(at: zip) }

            // 1. Download
            let downloader = PackDownload(url: url, destination: zip) { [weak self] done, total in
                let expected = total > 0 ? total : file.size
                self?.setProgress(pack.id, "Downloading", expected > 0 ? Double(done) / Double(expected) : 0)
            }
            await MainActor.run { self.downloaders[pack.id] = downloader }
            try await downloader.start()
            if flag.isSet { throw CancellationError() }

            // 2. Verify and 3. unpack, off the main thread
            let pid = pack.id
            imageCount += try await Task.detached(priority: .utility) { [weak self] () -> Int in
                self?.setProgress(pid, "Checking", 0)
                let digest = try Self.sha256(of: zip, isCancelled: { flag.isSet }) { f in self?.setProgress(pid, "Checking", f) }
                guard digest.caseInsensitiveCompare(file.sha256) == .orderedSame else { throw ArtPackError.badChecksum(file.name) }
                let archive = try MiniZip(url: zip, limits: .artPack(zipBytes: file.size))
                // Unpacking needs room for every image while the zip is still on disk.
                let need = Int64(archive.totalUncompressedSize) + 32 * 1024 * 1024
                if let have = ArtLocations.availableBytes(), have < need {
                    throw ArtPackError.notEnoughSpace(need: need, have: have)
                }
                let count = try archive.extract(to: files, progress: { f in
                    self?.setProgress(pid, "Unpacking", (Double(n) + f) / Double(totalFiles))
                }, isCancelled: { flag.isSet })
                return count
            }.value
        }

        // 4. Index
        setProgress(pack.id, "Indexing", 1)
        let records = Self.buildIndex(in: files, manifestEntries: entries)
        guard !records.isEmpty else { throw ArtPackError.failed("The pack unpacked, but no images were found in it.") }
        try JSONEncoder().encode(records).write(to: partial.appendingPathComponent("index.json"), options: .atomic)
        let meta = InstalledPackMeta(
            id: pack.id, name: pack.name, style: pack.style, credits: pack.credits, imageCount: records.count,
            bytesOnDisk: Self.directorySize(files), installedAt: Date(), order: order)
        try JSONEncoder.iso.encode(meta).write(to: partial.appendingPathComponent("meta.json"), options: .atomic)
        _ = imageCount

        // 5. Swap into place (the zip is deleted by the defer above)
        let final = ArtLocations.packDirectory(pack.id)
        try? fm.removeItem(at: final)
        try fm.moveItem(at: partial, to: final)
        ArtPackIndex.shared.reload()
    }

    func delete(_ id: String) {
        guard progress[id] == nil else { return }
        try? FileManager.default.removeItem(at: ArtLocations.packDirectory(id))
        ArtPackIndex.shared.reload()
        installed = ArtPackIndex.shared.installedMeta
        NotificationCenter.default.post(name: .muffinCoverArtSourcesChanged, object: nil)
    }

    // MARK: Helpers

    /// The manifest's index entries for files that are really there, plus an entry derived from the
    /// file name for any image the manifest doesn't list, so nothing unpacked goes unused.
    private static func buildIndex(in directory: URL, manifestEntries: [ArtIndexEntry]) -> [PackIndexRecord] {
        let fm = FileManager.default
        // Flatten anything the zip put in folders, so a file's name is its path.
        var present: [String: String] = [:]
        if let walker = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg", "webp"].contains(ext) else { continue }
                let rel = String(url.path.dropFirst(directory.path.count + 1))
                present[url.lastPathComponent] = rel
            }
        }
        var records: [PackIndexRecord] = []
        var covered = Set<String>()
        for e in manifestEntries {
            let name = (e.file as NSString).lastPathComponent
            guard let rel = present[name] else { continue }
            records.append(PackIndexRecord(file: rel, normalizedTitle: e.normalizedTitle, region: e.region))
            covered.insert(name)
        }
        for (name, rel) in present where !covered.contains(name) {
            let base = (name as NSString).deletingPathExtension
            var region: String?
            if let r = base.range(of: "\\(([^)]*)\\)\\s*$", options: .regularExpression) {
                region = String(base[r]).trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            }
            records.append(PackIndexRecord(file: rel, normalizedTitle: ArtTitleNormalizer.normalize(base), region: region))
        }
        return records
    }

    private static func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in walker { total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        }
        return total
    }

    /// SHA-256 of a file read in 4 MB pieces, so a 450 MB pack never sits in memory.
    private static func sha256(of url: URL, isCancelled: () -> Bool, progress: (Double) -> Void) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = max((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 1, 1)
        var hasher = SHA256()
        var done: Int64 = 0
        while true {
            if isCancelled() { throw CancellationError() }
            let chunk = try autoreleasepool { try handle.read(upToCount: 4 * 1024 * 1024) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            done += Int64(chunk.count)
            progress(Double(done) / Double(total))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    /// Posted when an art pack is installed or deleted, the cover style changes or game data is scraped:
    /// anything that can change which cover a game gets.
    static let muffinCoverArtSourcesChanged = Notification.Name("muffin.coverArtSourcesChanged")
}

// MARK: - Download

/// One cancellable download with progress. Written to disk by URLSession, never held in memory.
final class PackDownload: NSObject, URLSessionDownloadDelegate {
    private let url: URL
    private let destination: URL
    private let onProgress: (Int64, Int64) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    private var cancelled = false

    init(url: URL, destination: URL, onProgress: @escaping (Int64, Int64) -> Void) {
        self.url = url
        self.destination = destination
        self.onProgress = onProgress
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock()
            if cancelled { lock.unlock(); c.resume(throwing: CancellationError()); return }
            continuation = c
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.waitsForConnectivity = true
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session = s
            var request = URLRequest(url: url)
            request.setValue("MuffinEMU", forHTTPHeaderField: "User-Agent")
            let t = s.downloadTask(with: request)
            task = t
            lock.unlock()
            t.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        guard let c else { return }
        switch result {
        case .success: c.resume()
        case .failure(let e): c.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(ArtPackError.http(http.statusCode)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as? URLError)?.code == .cancelled { finish(.failure(CancellationError())) } else { finish(.failure(error)) }
    }
}
