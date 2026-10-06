import Foundation
import SwiftUI

/// The Wii U Menu (system menu): files from the user's own console, where they go, what
/// state they are in, and the library entry that launches it. MuffinEMU includes none of it
/// and downloads none of it; the user dumps it from their own Wii U (for example with
/// Dumpling) and imports it here. Experimental.
///
/// Where things live (all under the app's Documents folder, the same one Files.app shows):
///   Documents/mlc/mlc01/sys/title/00050010/10040X00   the Menu (X = 0 JPN, 1 USA, 2 EUR)
///   Documents/mlc/mlc01/sys/title/0005001b            shared data the Menu needs (fonts, Mii)
///   Documents/mlc/mlc01/sys/title/00050030, 0005000e  system applets and libraries
///   Documents/mlc/cafeLibs/*.rpl                      the console's cafeLibs
///   Documents/mlc/otp.bin, seeprom.bin                console identity, only for online features
/// The engine reads exactly these paths (rpl.cpp for cafeLibs, IOSU crypto for otp/seeprom,
/// CafeTitleList for the MLC), so this file and src/ios/Bridge/Core/IOSTitleLaunch.cpp must
/// agree on them.
enum WiiUMenuRegion: CaseIterable {
    case usa, eur, jpn

    var titleID: UInt64 {
        switch self {
        case .jpn: return 0x0005001010040000
        case .usa: return 0x0005001010040100
        case .eur: return 0x0005001010040200
        }
    }

    /// Directory name under sys/title/00050010.
    var folderName: String {
        switch self {
        case .jpn: return "10040000"
        case .usa: return "10040100"
        case .eur: return "10040200"
        }
    }

    var displayName: String {
        switch self {
        case .jpn: return "Japan"
        case .usa: return "USA"
        case .eur: return "Europe"
        }
    }

    /// Accepts the 16-digit title id from a meta.xml.
    init?(titleIDText text: String) {
        guard let match = WiiUMenuRegion.allCases.first(where: {
            String(format: "%016llx", $0.titleID) == text.lowercased()
        }) else { return nil }
        self = match
    }
}

/// How the installed Menu shows up in the library. Both default to off, which is the original
/// look: a bar pinned above the grid. Keys live under "muffin." so Reset settings covers them.
enum WiiUMenuSettings {
    /// Show the Menu as a card in the game grid instead of the bar at the top.
    static let showAsCardKey = "muffin.wiiuMenu.showAsCard"
    static let defaultShowAsCard = false
    /// Leave the Menu out of the library. It stays installed.
    static let hideKey = "muffin.wiiuMenu.hidden"
    static let defaultHidden = false
}

/// What is present, what launching needs and lacks.
struct WiiUMenuStatus: Equatable {
    var installedRegions: [WiiUMenuRegion] = []
    var hasSharedData = false
    var cafeLibsPresent = 0
    var hasSystemApps = false
    var hasOTP = false
    var hasSeeprom = false
    /// System titles whose files are incomplete, as "00050010/10040100: meta/meta.xml".
    /// The core skips or warns about these ("Title has missing meta .xml files").
    var incompleteTitles: [String] = []

    var menuInstalled: Bool { !installedRegions.isEmpty }
    var cafeLibsComplete: Bool { cafeLibsPresent == WiiUMenu.cafeLibNames.count }

    /// Pieces the Menu is known not to work without. Empty means the pre-flight passes.
    var missingRequired: [String] {
        var missing: [String] = []
        if !menuInstalled { missing.append("the Wii U Menu title") }
        if !hasSharedData { missing.append("shared data (sys/title/0005001b: fonts, Mii)") }
        if !cafeLibsComplete {
            missing.append("cafeLibs (\(cafeLibsPresent) of \(WiiUMenu.cafeLibNames.count) files)")
        }
        if let broken = incompleteTitles.first(where: { $0.hasPrefix("00050010/1004") && WiiUMenu.isMenuFolderName(String($0.dropFirst(9).prefix(8))) }) {
            missing.append("complete Wii U Menu files (\(broken))")
        }
        return missing
    }

    /// The incomplete titles as lines for a message, capped so a bad dump doesn't produce a wall of text.
    func incompleteTitlesSummary(limit: Int = 8) -> String? {
        guard !incompleteTitles.isEmpty else { return nil }
        var lines = incompleteTitles.prefix(limit).map { "  " + $0 }
        if incompleteTitles.count > limit { lines.append("  and \(incompleteTitles.count - limit) more") }
        return "\(incompleteTitles.count) system title\(incompleteTitles.count == 1 ? " has" : "s have") missing files (re-dump them, or the Menu may fail to list or start them):\n" + lines.joined(separator: "\n")
    }

    /// Optional: only online features need these.
    var missingOptional: [String] {
        var missing: [String] = []
        if !hasOTP { missing.append("otp.bin") }
        if !hasSeeprom { missing.append("seeprom.bin") }
        return missing
    }
}

enum WiiUMenu {
    static let cafeLibNames = ["drmapp", "erreula", "nn_sl", "nsyskbd", "snd_user", "snduser2", "swkbd"]

    /// Library entry id and title-id path scheme. cemu_bridge_boot_title() accepts
    /// "mlc-title:<16 hex digits>" and launches that MLC title by id.
    static let libraryID = "wiiu-menu"
    static func bootPath(for region: WiiUMenuRegion) -> String {
        "mlc-title:" + String(format: "%016llx", region.titleID)
    }

    // MARK: Paths

    static var documentsURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    /// Documents/mlc: the engine's user-data root (keys.txt, otp.bin, seeprom.bin, cafeLibs).
    static var mlcRootURL: URL? { documentsURL?.appendingPathComponent("mlc") }
    /// Documents/mlc/mlc01: the emulated console's storage.
    static var mlc01URL: URL? { mlcRootURL?.appendingPathComponent("mlc01") }
    static var cafeLibsURL: URL? { mlcRootURL?.appendingPathComponent("cafeLibs") }

    private static func menuFolder(_ region: WiiUMenuRegion) -> URL? {
        mlc01URL?.appendingPathComponent("sys/title/00050010/\(region.folderName)")
    }

    // MARK: Status

    static func status() -> WiiUMenuStatus {
        var result = WiiUMenuStatus()
        let fm = FileManager.default
        func isDir(_ url: URL?) -> Bool {
            guard let url else { return false }
            var directory: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        // USA first: the order the tile prefers when more than one region is installed.
        for region in [WiiUMenuRegion.usa, .eur, .jpn] where isDir(menuFolder(region)?.appendingPathComponent("code")) {
            result.installedRegions.append(region)
        }
        if let shared = mlc01URL?.appendingPathComponent("sys/title/0005001b"),
           let children = try? fm.contentsOfDirectory(atPath: shared.path) {
            result.hasSharedData = !children.isEmpty
        }
        result.hasSystemApps = isDir(mlc01URL?.appendingPathComponent("sys/title/00050030"))
        result.incompleteTitles = incompleteSystemTitles()
        if let libs = cafeLibsURL {
            result.cafeLibsPresent = cafeLibNames.filter {
                fm.fileExists(atPath: libs.appendingPathComponent("\($0).rpl").path)
            }.count
        }
        if let root = mlcRootURL {
            result.hasOTP = fm.fileExists(atPath: root.appendingPathComponent("otp.bin").path)
            result.hasSeeprom = fm.fileExists(atPath: root.appendingPathComponent("seeprom.bin").path)
        }
        return result
    }

    static func isMenuFolderName(_ name: String) -> Bool {
        WiiUMenuRegion.allCases.contains { $0.folderName == name.lowercased() }
    }

    /// Walks mlc01/sys/title/<group>/<id> and reports titles that have a code, content or meta
    /// folder but not the files the core needs to read them: code/app.xml, code/cos.xml and
    /// meta/meta.xml. Titles with none of those folders (data-only titles) are not titles the
    /// core loads and are not reported.
    static func incompleteSystemTitles() -> [String] {
        guard let base = mlc01URL?.appendingPathComponent("sys/title") else { return [] }
        let fm = FileManager.default
        var result: [String] = []
        let groups = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted()
        for group in groups {
            let groupURL = base.appendingPathComponent(group)
            let ids = ((try? fm.contentsOfDirectory(atPath: groupURL.path)) ?? []).sorted()
            for id in ids {
                let dir = groupURL.appendingPathComponent(id)
                func isDir(_ name: String) -> Bool {
                    var directory: ObjCBool = false
                    return fm.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &directory) && directory.boolValue
                }
                func isFile(_ name: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(name).path) }
                let hasCode = isDir("code"), hasContent = isDir("content"), hasMeta = isDir("meta")
                guard hasCode || hasContent && hasMeta else { continue }
                var missing: [String] = []
                if !hasCode { missing.append("code folder") }
                if !hasMeta { missing.append("meta folder") }
                if hasCode && !isFile("code/app.xml") { missing.append("code/app.xml") }
                if hasCode && !isFile("code/cos.xml") { missing.append("code/cos.xml") }
                if hasMeta && !isFile("meta/meta.xml") { missing.append("meta/meta.xml") }
                if !missing.isEmpty { result.append("\(group)/\(id): \(missing.joined(separator: ", "))") }
            }
        }
        return result
    }

    /// The library entry for the installed Menu, nil when no Menu title is installed.
    static func libraryEntry(for status: WiiUMenuStatus) -> GameMetadata? {
        guard let region = status.installedRegions.first else { return nil }
        return GameMetadata(
            id: libraryID,
            title: "Wii U Menu",
            romPath: bootPath(for: region),
            region: region.displayName,
            releaseDate: "",
            genre: "System",
            titleId: region.titleID,
            displayTitle: "Wii U Menu"
        )
    }

    // MARK: Uninstall

    /// What uninstalling removes: the Menu title folder for every region, and nothing else.
    /// Shared data (0005001b), system apps, cafeLibs, otp.bin and seeprom.bin stay: games use
    /// them too. Saves (mlc01/usr), other titles and import backups are never touched.
    static func uninstallableMenuFolders() -> [URL] {
        let fm = FileManager.default
        return WiiUMenuRegion.allCases.compactMap { region in
            guard let folder = menuFolder(region), fm.fileExists(atPath: folder.path) else { return nil }
            return folder
        }
    }

    /// Deletes the Menu title folder(s). Blocking: call off the main thread. Returns how many
    /// folders were removed; throws on the first one that could not be.
    @discardableResult
    static func uninstallMenu() throws -> Int {
        let fm = FileManager.default
        var removed = 0
        for folder in uninstallableMenuFolders() {
            do {
                try fm.removeItem(at: folder)
                removed += 1
            } catch {
                throw ImportError.failed("Couldn't remove \(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return removed
    }

    // MARK: Import errors and reports

    enum ImportError: LocalizedError {
        case accessDenied
        case nothingRecognised
        case notTheMenu(String)
        case wrongSize(String, expected: Int)
        case notEnoughSpace(needed: Int64, available: Int64)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Couldn't access that item."
            case .nothingRecognised:
                return "Nothing recognisable in that folder. Pick the package folder (the one containing mlc01 and cafeLibs), an mlc01 folder, a sys folder, a cafeLibs folder, or the Wii U Menu title folder itself."
            case .notTheMenu(let id):
                return "That title folder isn't a Wii U Menu (title id \(id)). The Menu is 0005001010040000, 0005001010040100 or 0005001010040200."
            case .wrongSize(let name, let expected):
                return "\(name) should be exactly \(expected) bytes."
            case .notEnoughSpace(let needed, let available):
                let format = ByteCountFormatter()
                return "Not enough free space: the import needs about \(format.string(fromByteCount: needed)) and this device has \(format.string(fromByteCount: available)) free."
            case .failed(let message):
                return message
            }
        }
    }

    struct ImportReport {
        var copied = 0
        var replaced = 0
        var skipped = 0
        var backupFolder: String?
        var notes: [String] = []

        var summary: String {
            var lines = notes
            lines.append("\(copied) new file\(copied == 1 ? "" : "s") copied, \(replaced) replaced, \(skipped) already present.")
            if let backupFolder {
                lines.append("Files that were replaced were first saved in \(backupFolder).")
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: Console files (otp.bin, seeprom.bin)

    private static let otpSize = 1024
    private static let seepromSize = 512

    /// Copies the picked otp.bin and/or seeprom.bin to Documents/mlc. Files are recognised
    /// by name, then by size (otp.bin is 1024 bytes, seeprom.bin 512). An existing file is
    /// renamed with a timestamp first, never overwritten in place.
    static func importConsoleFiles(from urls: [URL]) throws -> [String] {
        guard let root = mlcRootURL else { throw ImportError.accessDenied }
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        var lines: [String] = []
        var seenOTP = false, seenSeeprom = false
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { throw ImportError.accessDenied }
            let name = url.lastPathComponent.lowercased()
            let target: String
            if name.contains("otp") && !name.contains("seeprom") {
                target = "otp.bin"
            } else if name.contains("seeprom") {
                target = "seeprom.bin"
            } else if data.count == otpSize {
                target = "otp.bin"
            } else if data.count == seepromSize {
                target = "seeprom.bin"
            } else {
                throw ImportError.failed("\(url.lastPathComponent) isn't otp.bin or seeprom.bin. otp.bin is \(otpSize) bytes and seeprom.bin is \(seepromSize) bytes.")
            }
            let expected = target == "otp.bin" ? otpSize : seepromSize
            guard data.count == expected else { throw ImportError.wrongSize(target, expected: expected) }
            let destination = root.appendingPathComponent(target)
            if fm.fileExists(atPath: destination.path) {
                let backup = root.appendingPathComponent("\(target).backup-\(timestamp())")
                try fm.moveItem(at: destination, to: backup)
                lines.append("Existing \(target) saved as \(backup.lastPathComponent).")
            }
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                throw ImportError.failed("Couldn't save \(target): \(error.localizedDescription)")
            }
            if target == "otp.bin" { seenOTP = true } else { seenSeeprom = true }
        }
        if seenOTP { lines.append("otp.bin imported.") }
        if seenSeeprom { lines.append("seeprom.bin imported.") }
        return lines
    }

    // MARK: System files

    private enum Piece {
        /// A cafeLibs folder: merged into Documents/mlc/cafeLibs.
        case cafeLibs(URL)
        /// An mlc01-shaped folder (contains sys and/or usr): merged into Documents/mlc/mlc01.
        case mlc01(URL)
        /// Just a sys folder: merged into mlc01/sys.
        case sys(URL)
        /// A system title folder (code/content/meta): merged into mlc01/sys/title/00050010/<id>.
        case menuTitle(URL, WiiUMenuRegion)
    }

    private struct Operation {
        let source: URL
        let destination: URL
        let relative: String
        let size: Int64
        let replacing: Bool
    }

    private static func child(_ url: URL, named name: String) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        guard let match = names.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        let candidate = url.appendingPathComponent(match)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory), directory.boolValue else { return nil }
        return candidate
    }

    /// Reads title_id out of meta/meta.xml without a full XML parse: the file is small and
    /// the element is unambiguous.
    private static func metaTitleID(in titleFolder: URL) -> String? {
        guard let metaFolder = child(titleFolder, named: "meta") else { return nil }
        let metaXML = metaFolder.appendingPathComponent("meta.xml")
        guard let text = try? String(contentsOf: metaXML, encoding: .utf8) else { return nil }
        guard let open = text.range(of: "<title_id"), let close = text.range(of: "</title_id>", range: open.upperBound..<text.endIndex),
              let gt = text.range(of: ">", range: open.upperBound..<close.lowerBound) else { return nil }
        return String(text[gt.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Works out what the picked folder is. A package root can hold several pieces at once.
    private static func recognise(_ root: URL) throws -> [Piece] {
        var pieces: [Piece] = []
        let fm = FileManager.default
        // The folder is itself a system title folder.
        if child(root, named: "code") != nil, child(root, named: "meta") != nil {
            guard let id = metaTitleID(in: root), let region = WiiUMenuRegion(titleIDText: id) else {
                throw ImportError.notTheMenu(metaTitleID(in: root) ?? "unknown")
            }
            return [.menuTitle(root, region)]
        }
        if let libs = child(root, named: "cafeLibs") { pieces.append(.cafeLibs(libs)) }
        if let mlc01 = child(root, named: "mlc01") { pieces.append(.mlc01(mlc01)) }
        if child(root, named: "sys") != nil || child(root, named: "usr") != nil { pieces.append(.mlc01(root)) }
        if pieces.isEmpty {
            // A cafeLibs folder picked directly, or a sys folder picked directly.
            let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            if root.lastPathComponent.lowercased() == "cafelibs" || names.contains(where: { $0.lowercased().hasSuffix(".rpl") }) {
                pieces.append(.cafeLibs(root))
            } else if root.lastPathComponent.lowercased() == "sys" || child(root, named: "title") != nil {
                pieces.append(.sys(root))
            }
        }
        if pieces.isEmpty { throw ImportError.nothingRecognised }
        return pieces
    }

    /// Lists what merging `source` into `destination` would do. Files that already exist
    /// with the same size are skipped. A file that exists and differs is replaced only when
    /// `replaceDiffering` is true (system files, after a backup); otherwise it is left alone,
    /// which is how usr/ (saves live there) is protected.
    private static func plan(source: URL, destination: URL, relativePrefix: String, replaceDiffering: Bool,
                             operations: inout [Operation], skipped: inout Int) throws {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            // AppleDouble and Finder litter from exFAT/APFS drives.
            if name.hasPrefix("._") || name == ".DS_Store" { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if values?.isSymbolicLink == true { continue }
            let target = destination.appendingPathComponent(name)
            let relative = relativePrefix.isEmpty ? name : relativePrefix + "/" + name
            if values?.isDirectory == true {
                try plan(source: entry, destination: target, relativePrefix: relative, replaceDiffering: replaceDiffering,
                         operations: &operations, skipped: &skipped)
                continue
            }
            let size = Int64(values?.fileSize ?? 0)
            if let existing = try? fm.attributesOfItem(atPath: target.path), let existingSize = existing[.size] as? NSNumber {
                if existingSize.int64Value == size || !replaceDiffering {
                    skipped += 1
                } else {
                    operations.append(Operation(source: entry, destination: target, relative: relative, size: size, replacing: true))
                }
            } else {
                operations.append(Operation(source: entry, destination: target, relative: relative, size: size, replacing: false))
            }
        }
    }

    /// Imports Wii U Menu files from a folder the user picked. Merges file by file; never
    /// replaces mlc01 or usr wholesale. Blocking and I/O heavy: call off the main thread.
    static func importSystemFiles(from folder: URL) throws -> ImportReport {
        guard let mlc01 = mlc01URL, let cafeLibs = cafeLibsURL, let mlcRoot = mlcRootURL else { throw ImportError.accessDenied }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default

        let pieces = try recognise(folder)
        var operations: [Operation] = []
        var skipped = 0
        var notes: [String] = []
        for piece in pieces {
            switch piece {
            case .cafeLibs(let source):
                notes.append("Found cafeLibs.")
                try plan(source: source, destination: cafeLibs, relativePrefix: "cafeLibs", replaceDiffering: true,
                         operations: &operations, skipped: &skipped)
            case .mlc01(let source):
                if let sys = child(source, named: "sys") {
                    notes.append("Found sys (system titles).")
                    try plan(source: sys, destination: mlc01.appendingPathComponent("sys"), relativePrefix: "mlc01/sys",
                             replaceDiffering: true, operations: &operations, skipped: &skipped)
                }
                if let usr = child(source, named: "usr") {
                    notes.append("Found usr. Existing files there (including saves) are never replaced.")
                    try plan(source: usr, destination: mlc01.appendingPathComponent("usr"), relativePrefix: "mlc01/usr",
                             replaceDiffering: false, operations: &operations, skipped: &skipped)
                }
            case .sys(let source):
                notes.append("Found sys (system titles).")
                try plan(source: source, destination: mlc01.appendingPathComponent("sys"), relativePrefix: "mlc01/sys",
                         replaceDiffering: true, operations: &operations, skipped: &skipped)
            case .menuTitle(let source, let region):
                notes.append("Found the Wii U Menu title (\(region.displayName)).")
                let destination = mlc01.appendingPathComponent("sys/title/00050010/\(region.folderName)")
                try plan(source: source, destination: destination, relativePrefix: "mlc01/sys/title/00050010/\(region.folderName)",
                         replaceDiffering: true, operations: &operations, skipped: &skipped)
            }
        }

        // Disk is finite: refuse up front instead of failing halfway through a merge.
        let needed = operations.reduce(Int64(0)) { $0 + $1.size }
        let probe = fm.fileExists(atPath: mlcRoot.path) ? mlcRoot : (documentsURL ?? mlcRoot)
        if let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage,
           available < needed + 256 * 1024 * 1024 {
            throw ImportError.notEnoughSpace(needed: needed, available: available)
        }

        var report = ImportReport()
        report.notes = notes
        report.skipped = skipped
        let backupRoot = mlcRoot.appendingPathComponent("import-backup-\(timestamp())")
        for operation in operations {
            do {
                try fm.createDirectory(at: operation.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if operation.replacing {
                    let backup = backupRoot.appendingPathComponent(operation.relative)
                    try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: operation.destination, to: backup)
                    report.backupFolder = backupRoot.lastPathComponent
                    report.replaced += 1
                } else {
                    report.copied += 1
                }
                try fm.copyItem(at: operation.source, to: operation.destination)
            } catch {
                throw ImportError.failed("Stopped at \(operation.relative): \(error.localizedDescription). Nothing that already existed was lost; run the import again to continue.")
            }
        }
        return report
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

/// Published Menu status for the library and Settings.
@MainActor
final class WiiUMenuStore: ObservableObject {
    static let shared = WiiUMenuStore()
    @Published private(set) var status = WiiUMenu.status()

    func refresh() {
        let latest = WiiUMenu.status()
        if latest != status { status = latest }
    }
}
