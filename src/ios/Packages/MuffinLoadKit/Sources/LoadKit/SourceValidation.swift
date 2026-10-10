import Foundation

public enum SourceKind: Equatable {
    case dumpFolder
    case nusFolder
    case gameCollection(count: Int)
    case file(ext: String)
}

public struct SourceFinding: Equatable {
    public var kind: SourceKind
    public var displayName: String
    public var warnings: [String]

    public var gameCount: Int {
        if case .gameCollection(let count) = kind { return count }
        return 1
    }
}

public enum SourceIssue: Error, Equatable, LocalizedError {
    case unreadable(String)
    case emptyFolder(String)
    case missingMeta(String)
    case missingCode(String)
    case noExecutable(String)
    case nusNoContent(String)
    case wrongLevel(String, parent: String)
    case notAGame(String, seen: [String])
    case archiveUnsupported(String)
    case unsupportedExtension(String)
    case emptyFile(String)
    case badSignature(String, expected: String)
    case notDownloaded([String])
    case truncatedOnFat(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "MuffinEMU can't read \"\(name)\". If it's on a drive, make sure the drive is connected and unlocked, then try again."
        case .emptyFolder(let name):
            return "\"\(name)\" is empty. If it's on a drive or cloud service, the files may not be available yet."
        case .missingMeta(let name):
            return "\"\(name)\" has a code folder but no meta folder. A decrypted game needs code, content and meta side by side; without meta the game loses its name and title ID. Copy the whole dump, including meta/meta.xml."
        case .missingCode(let name):
            return "\"\(name)\" has a meta folder but no code folder, so there is no .rpx to start. Copy the whole dump, including code/."
        case .noExecutable(let name):
            return "\"\(name)\" has a code folder but no .rpx file inside it. The dump looks incomplete."
        case .nusNoContent(let name):
            return "\"\(name)\" has a title.tmd but no .app content files next to it. The download looks incomplete."
        case .wrongLevel(let name, let parent):
            return "\"\(name)\" is a folder inside a game, not the game itself. Choose \"\(parent)\" instead."
        case .notAGame(let name, let seen):
            let found = seen.isEmpty ? "" : " It contains: \(seen.prefix(5).joined(separator: ", "))."
            return "\"\(name)\" isn't a Wii U game folder.\(found) A game folder has code, content and meta folders, or title.tmd with its .app files. To load a single file, use Load from File."
        case .archiveUnsupported(let name):
            return "\"\(name)\" is an archive. MuffinEMU can't open .zip files: extract it first, or use a .wua, .wux or .wud file."
        case .unsupportedExtension(let name):
            return "\"\(name)\" isn't a file type MuffinEMU loads. It accepts .wua, .wux, .wud, .iso, .rpx, .elf and .wuhb files."
        case .emptyFile(let name):
            return "\"\(name)\" is empty (0 bytes). The copy or download probably didn't finish."
        case .badSignature(let name, let expected):
            return "\"\(name)\" doesn't look like a \(expected) file: its first bytes are wrong. It may be corrupt, incomplete, or renamed from another format."
        case .notDownloaded(let names):
            let list = names.prefix(3).joined(separator: ", ")
            return "\(list) hasn't been downloaded from the cloud yet, so only a placeholder is on this device. Open Files, download it, and try again."
        case .truncatedOnFat(let name):
            return "\"\(name)\" is exactly 4 GB minus one byte on a FAT32 drive, which is the size a larger file gets cut to. It is almost certainly incomplete. Re-copy it from an exFAT or APFS drive."
        }
    }
}

public enum GameSourceValidator {
    public static let fileExtensions: Set<String> = ["wux", "wud", "wua", "iso", "rpx", "wuhb", "elf"]

    static let signatures: [String: (bytes: [UInt8], label: String)] = [
        "rpx": ([0x7F, 0x45, 0x4C, 0x46], "Wii U executable (.rpx)"),
        "elf": ([0x7F, 0x45, 0x4C, 0x46], "Wii U executable (.elf)"),
        "wux": ([0x57, 0x55, 0x58, 0x30], "compressed disc image (.wux)"),
        "wuhb": ([0x57, 0x55, 0x48, 0x42], "Wii U homebrew bundle (.wuhb)"),
    ]

    public static func isPlaceholder(_ name: String) -> Bool {
        name.hasPrefix(".") && name.lowercased().hasSuffix(".icloud")
    }

    public static func placeholderTarget(_ name: String) -> String {
        var stripped = String(name.dropFirst())
        stripped.removeLast(".icloud".count)
        return stripped
    }

    public static func validateFile(_ path: String, using fs: FileInspecting) -> Result<SourceFinding, SourceIssue> {
        let name = (path as NSString).lastPathComponent
        if isPlaceholder(name) { return .failure(.notDownloaded([placeholderTarget(name)])) }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "zip" { return .failure(.archiveUnsupported(name)) }
        guard fileExtensions.contains(ext) else { return .failure(.unsupportedExtension(name)) }
        guard let size = fs.size(of: path) else { return .failure(.unreadable(name)) }
        if size == 0 { return .failure(.emptyFile(name)) }
        if let signature = signatures[ext] {
            guard let head = fs.head(of: path, count: signature.bytes.count) else { return .failure(.unreadable(name)) }
            if head != signature.bytes { return .failure(.badSignature(name, expected: signature.label)) }
        } else if fs.head(of: path, count: 4) == nil {
            return .failure(.unreadable(name))
        }
        var warnings: [String] = []
        if ext == "rpx" || ext == "elf" {
            warnings.append("A bare .rpx has no game data next to it, so it only works if it needs no files from a disc.")
        }
        return .success(SourceFinding(kind: .file(ext: ext), displayName: name, warnings: warnings))
    }

    private enum Inspection {
        case game(SourceKind, [String])
        case problem(SourceIssue)
        case none
    }

    private static func child(_ entries: [FileEntry], _ name: String) -> FileEntry? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func inspect(_ path: String, entries: [FileEntry], fs: FileInspecting) -> Inspection {
        let name = (path as NSString).lastPathComponent
        let code = child(entries, "code").flatMap { $0.isDirectory ? $0 : nil }
        let meta = child(entries, "meta").flatMap { $0.isDirectory ? $0 : nil }
        let content = child(entries, "content").flatMap { $0.isDirectory ? $0 : nil }

        if code != nil || meta != nil {
            guard let codeEntry = code else { return .problem(.missingCode(name)) }
            guard meta != nil else { return .problem(.missingMeta(name)) }
            let codeChildren = fs.children(of: joinPath(path, codeEntry.name)) ?? []
            if let holder = codeChildren.first(where: { isPlaceholder($0.name) }) {
                return .problem(.notDownloaded([placeholderTarget(holder.name)]))
            }
            let rpx = codeChildren.first { !$0.isDirectory && ($0.name as NSString).pathExtension.lowercased() == "rpx" }
            guard let rpx else { return .problem(.noExecutable(name)) }
            if rpx.size == 0 { return .problem(.emptyFile(rpx.name)) }
            var warnings: [String] = []
            if content == nil {
                warnings.append("There is no content folder. Games that read assets from it will fail.")
            }
            return .game(.dumpFolder, warnings)
        }

        if let tmd = entries.first(where: { !$0.isDirectory && $0.name.caseInsensitiveCompare("title.tmd") == .orderedSame }) {
            if let holder = entries.first(where: { isPlaceholder($0.name) }) {
                return .problem(.notDownloaded([placeholderTarget(holder.name)]))
            }
            let apps = entries.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".app") }
            guard !apps.isEmpty, tmd.size > 0 else { return .problem(.nusNoContent(name)) }
            var warnings: [String] = []
            if child(entries, "title.tik") == nil {
                warnings.append("There is no title.tik. The game only starts if its key is in keys.txt.")
            }
            if apps.contains(where: { $0.size == 0 }) {
                return .problem(.emptyFile(apps.first { $0.size == 0 }!.name))
            }
            return .game(.nusFolder, warnings)
        }
        return .none
    }

    public static func validateFolder(_ path: String, using fs: FileInspecting, maxDepth: Int = 2) -> Result<SourceFinding, SourceIssue> {
        let name = (path as NSString).lastPathComponent
        guard let entries = fs.children(of: path) else { return .failure(.unreadable(name)) }
        let visible = entries.filter { !$0.name.hasPrefix(".") || isPlaceholder($0.name) }
        if visible.isEmpty { return .failure(.emptyFolder(name)) }

        switch inspect(path, entries: entries, fs: fs) {
        case .game(let kind, let warnings):
            return .success(SourceFinding(kind: kind, displayName: name, warnings: warnings))
        case .problem(let issue):
            return .failure(issue)
        case .none:
            break
        }

        let lower = name.lowercased()
        if ["code", "content", "meta"].contains(lower) {
            let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return .failure(.wrongLevel(name, parent: parent.isEmpty ? "the folder that holds code, content and meta" : parent))
        }

        var games = 0
        var firstProblem: SourceIssue?
        var baseKinds: [SourceKind] = []
        var warnings: [String] = []
        func search(_ dir: String, _ list: [FileEntry], depth: Int) {
            for entry in list.sorted(by: { $0.name < $1.name }) {
                if entry.name.hasPrefix(".") {
                    if isPlaceholder(entry.name), firstProblem == nil {
                        let target = placeholderTarget(entry.name)
                        if fileExtensions.contains((target as NSString).pathExtension.lowercased()) {
                            firstProblem = .notDownloaded([target])
                        }
                    }
                    continue
                }
                let full = joinPath(dir, entry.name)
                if entry.isDirectory {
                    guard let kids = fs.children(of: full) else { continue }
                    switch inspect(full, entries: kids, fs: fs) {
                    case .game(let kind, let w):
                        games += 1
                        baseKinds.append(kind)
                        warnings.append(contentsOf: w.map { "\(entry.name): \($0)" })
                    case .problem(let issue):
                        if firstProblem == nil { firstProblem = issue }
                    case .none:
                        if depth < maxDepth { search(full, kids, depth: depth + 1) }
                    }
                } else if fileExtensions.contains((entry.name as NSString).pathExtension.lowercased()), entry.size > 0 {
                    games += 1
                }
            }
        }
        search(path, entries, depth: 1)

        if games > 0 {
            let nus = baseKinds.filter { $0 == .nusFolder }.count
            if nus == games, games > 1, looksLikeBaseWithCompanions(path, entries: entries, fs: fs) {
                return .success(SourceFinding(kind: .nusFolder, displayName: name, warnings: warnings))
            }
            return .success(SourceFinding(kind: .gameCollection(count: games), displayName: name, warnings: warnings))
        }
        if let firstProblem { return .failure(firstProblem) }

        if entries.contains(where: { ($0.name as NSString).pathExtension.lowercased() == "zip" }) {
            let zip = entries.first { ($0.name as NSString).pathExtension.lowercased() == "zip" }!
            return .failure(.archiveUnsupported(zip.name))
        }
        return .failure(.notAGame(name, seen: visible.map { $0.name }.sorted()))
    }

    private static func looksLikeBaseWithCompanions(_ path: String, entries: [FileEntry], fs: FileInspecting) -> Bool {
        let folders = entries.filter { $0.isDirectory && !$0.name.hasPrefix(".") }
        let names = folders.map { $0.name.lowercased() }
        return names.contains { $0.contains("update") || $0.contains("dlc") || $0.contains("aoc") }
    }
}
