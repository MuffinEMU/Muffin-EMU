import Foundation
import LoadKit

var failures = 0
var passes = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    if ok { passes += 1 } else { failures += 1; print("FAIL: \(what())") }
}

struct MemoryFS: FileInspecting {
    var tree: [String: [FileEntry]] = [:]
    var files: [String: [UInt8]] = [:]
    var unreadable: Set<String> = []

    func children(of path: String) -> [FileEntry]? {
        if unreadable.contains(path) { return nil }
        return tree[path]
    }
    func size(of path: String) -> UInt64? { files[path].map { UInt64($0.count) } }
    func head(of path: String, count: Int) -> [UInt8]? {
        guard let bytes = files[path], bytes.count >= count else { return nil }
        return Array(bytes.prefix(count))
    }
}

func dir(_ name: String) -> FileEntry { FileEntry(name: name, isDirectory: true) }
func file(_ name: String, _ size: UInt64 = 10) -> FileEntry { FileEntry(name: name, isDirectory: false, size: size) }

func issue(_ result: Result<SourceFinding, SourceIssue>) -> SourceIssue? {
    if case .failure(let issue) = result { return issue }
    return nil
}
func finding(_ result: Result<SourceFinding, SourceIssue>) -> SourceFinding? {
    if case .success(let finding) = result { return finding }
    return nil
}

// Folders
do {
    var fs = MemoryFS()
    fs.tree["/g"] = [dir("code"), dir("content"), dir("meta")]
    fs.tree["/g/code"] = [file("game.rpx"), file("lib.rpl")]
    check(finding(GameSourceValidator.validateFolder("/g", using: fs))?.kind == .dumpFolder, "complete dump accepted")

    fs.tree["/g"] = [dir("code"), dir("content")]
    check(issue(GameSourceValidator.validateFolder("/g", using: fs)) == .missingMeta("g"), "missing meta reported")

    fs.tree["/g"] = [dir("meta"), dir("content")]
    check(issue(GameSourceValidator.validateFolder("/g", using: fs)) == .missingCode("g"), "missing code reported")

    fs.tree["/g"] = [dir("code"), dir("meta")]
    fs.tree["/g/code"] = [file("lib.rpl")]
    check(issue(GameSourceValidator.validateFolder("/g", using: fs)) == .noExecutable("g"), "no rpx reported")

    fs.tree["/g/code"] = [file("game.rpx", 0)]
    check(issue(GameSourceValidator.validateFolder("/g", using: fs)) == .emptyFile("game.rpx"), "zero-byte rpx reported")

    fs.tree["/g/code"] = [file("game.rpx")]
    check(finding(GameSourceValidator.validateFolder("/g", using: fs))?.warnings.count == 1, "missing content is a warning")

    fs.tree["/g/code"] = [file(".game.rpx.icloud")]
    if case .notDownloaded(let names)? = issue(GameSourceValidator.validateFolder("/g", using: fs)) {
        check(names == ["game.rpx"], "placeholder names the real file")
    } else { check(false, "placeholder in code reported") }
}

do {
    var fs = MemoryFS()
    fs.tree["/n"] = [file("title.tmd", 100), file("title.tik", 100), file("00000000.app", 5000), file("00000001.app", 5000)]
    check(finding(GameSourceValidator.validateFolder("/n", using: fs))?.kind == .nusFolder, "NUS folder accepted")

    fs.tree["/n"] = [file("TITLE.TMD", 100), file("00000000.APP", 5000)]
    let noTik = finding(GameSourceValidator.validateFolder("/n", using: fs))
    check(noTik?.kind == .nusFolder && noTik?.warnings.count == 1, "missing tik warns, case-insensitive names")

    fs.tree["/n"] = [file("title.tmd", 100), file("title.tik", 100)]
    check(issue(GameSourceValidator.validateFolder("/n", using: fs)) == .nusNoContent("n"), "NUS without content reported")
}

do {
    var fs = MemoryFS()
    fs.tree["/lib"] = [dir("A"), dir("B"), file("notes.txt")]
    fs.tree["/lib/A"] = [dir("code"), dir("meta")]
    fs.tree["/lib/A/code"] = [file("a.rpx")]
    fs.tree["/lib/B"] = [dir("code"), dir("meta")]
    fs.tree["/lib/B/code"] = [file("b.rpx")]
    check(finding(GameSourceValidator.validateFolder("/lib", using: fs))?.kind == .gameCollection(count: 2), "collection of two games")

    fs.tree["/lib/B"] = [dir("code")]
    check(finding(GameSourceValidator.validateFolder("/lib", using: fs))?.kind == .gameCollection(count: 1), "one good game beats one broken one")

    fs.tree["/x"] = [dir("Documents"), file("a.txt")]
    fs.tree["/x/Documents"] = [file("b.txt")]
    if case .notAGame("x", let seen)? = issue(GameSourceValidator.validateFolder("/x", using: fs)) {
        check(seen == ["Documents", "a.txt"], "not-a-game lists contents")
    } else { check(false, "plain folder rejected") }

    fs.tree["/e"] = []
    check(issue(GameSourceValidator.validateFolder("/e", using: fs)) == .emptyFolder("e"), "empty folder")

    fs.unreadable = ["/gone"]
    check(issue(GameSourceValidator.validateFolder("/gone", using: fs)) == .unreadable("gone"), "unreadable folder")

    fs.tree["/p/game/code"] = [file("a.rpx")]
    fs.tree["/p/game/content"] = []
    fs.tree["/p/game"] = [dir("code"), dir("content")]
    fs.tree["/p/game/meta"] = []
    check(issue(GameSourceValidator.validateFolder("/p/game/code", using: fs)) != nil, "code folder alone is not a game")
    fs.tree["/z"] = [file("game.zip")]
    check(issue(GameSourceValidator.validateFolder("/z", using: fs)) == .archiveUnsupported("game.zip"), "zip in folder explained")
}

// Files
do {
    var fs = MemoryFS()
    fs.files["/a.rpx"] = [0x7F, 0x45, 0x4C, 0x46, 1, 2]
    fs.files["/b.wux"] = [0x57, 0x55, 0x58, 0x30, 0, 0]
    fs.files["/bad.wux"] = [0, 0, 0, 0, 0]
    fs.files["/c.wua"] = [1, 2, 3, 4, 5]
    fs.files["/d.wud"] = [1, 2, 3, 4, 5]
    fs.files["/e.wua"] = []
    fs.files["/f.zip"] = [1, 2, 3, 4]
    fs.files["/g.txt"] = [1, 2, 3, 4]
    fs.files["/h.wuhb"] = [0x57, 0x55, 0x48, 0x42, 0]
    for name in ["a.rpx", "b.wux", "c.wua", "d.wud", "h.wuhb"] {
        check(finding(GameSourceValidator.validateFile("/" + name, using: fs)) != nil, "\(name) accepted")
    }
    check(issue(GameSourceValidator.validateFile("/bad.wux", using: fs)) != nil, "bad wux signature rejected")
    check(issue(GameSourceValidator.validateFile("/e.wua", using: fs)) == .emptyFile("e.wua"), "empty wua")
    check(issue(GameSourceValidator.validateFile("/f.zip", using: fs)) == .archiveUnsupported("f.zip"), "zip explained")
    check(issue(GameSourceValidator.validateFile("/g.txt", using: fs)) == .unsupportedExtension("g.txt"), "txt rejected")
    check(issue(GameSourceValidator.validateFile("/missing.wua", using: fs)) == .unreadable("missing.wua"), "missing file")
    check(issue(GameSourceValidator.validateFile("/.c.wua.icloud", using: fs)) == .notDownloaded(["c.wua"]), "icloud placeholder")
    for error in [SourceIssue.emptyFile("x"), .badSignature("x", expected: "y"), .notDownloaded(["x"]), .truncatedOnFat("x"), .wrongLevel("a", parent: "b")] {
        check(!(error.errorDescription ?? "").isEmpty, "message for \(error)")
    }
}

// Storage verdicts
do {
    let fast = StorageFacts(filesystem: "apfs", sampledReadMillis: [0.2, 0.3, 0.2, 0.4], sampleAttempts: 4)
    check(StorageAssessment.evaluate(fast).level == .good, "fast local disk is good")

    let slow = StorageFacts(filesystem: "exfat", isRemovable: true, sampledReadMillis: [40, 60, 80, 50], sampleAttempts: 4)
    let slowVerdict = StorageAssessment.evaluate(slow)
    check(slowVerdict.level == .caution && slowVerdict.canPlayAnyway && slowVerdict.canCopy, "slow drive: caution, play anyway offered")

    let crawl = StorageFacts(filesystem: "exfat", sampledReadMillis: [300, 400, 500], sampleAttempts: 3)
    check(StorageAssessment.evaluate(crawl).level == .unsuitable && StorageAssessment.evaluate(crawl).canPlayAnyway, "very slow: unsuitable, still allowed")

    let placeholder = StorageFacts(isLocalVolume: false, hasUndownloadedFiles: true)
    let placeholderVerdict = StorageAssessment.evaluate(placeholder)
    check(placeholderVerdict.level == .unsuitable && !placeholderVerdict.canPlayAnyway && !placeholderVerdict.canCopy, "undownloaded: nothing to play or copy")

    let flaky = StorageFacts(filesystem: "exfat", sampledReadMillis: [1, 1], sampleFailures: 2, sampleAttempts: 4)
    check(!StorageAssessment.evaluate(flaky).canPlayAnyway && StorageAssessment.evaluate(flaky).canCopy, "failed reads: no play anyway")

    let truncated = StorageFacts(filesystem: "msdos", largestFileBytes: 0xFFFF_FFFF)
    check(StorageAssessment.evaluate(truncated).level == .unsuitable && !StorageAssessment.evaluate(truncated).canPlayAnyway, "FAT32 4GB-1 file is treated as cut")

    let fat = StorageFacts(filesystem: "msdos", largestFileBytes: 3_000_000_000, sampledReadMillis: [1], sampleAttempts: 1)
    let fatVerdict = StorageAssessment.evaluate(fat)
    check(fatVerdict.level == .good && fatVerdict.notes.contains { $0.contains("FAT32") }, "FAT32 with small files only notes the limit")

    let smb = StorageFacts(filesystem: "smbfs", isLocalVolume: false, sampledReadMillis: [3], sampleAttempts: 1)
    check(StorageAssessment.evaluate(smb).level == .caution && StorageAssessment.evaluate(smb).reasons.count == 1, "network share: one caution")

    check(StorageAssessment.evaluate(StorageFacts(unreadable: true)).canCopy == false, "unreadable: cannot copy")
    check(StorageAssessment.evaluate(StorageFacts(seekUnsupported: true)).canPlayAnyway == false, "no seek: cannot play")
    check(StorageAssessment.isFAT("MSDOS") && !StorageAssessment.isFAT("exfat"), "FAT detection")
}

// Install identity: a game keeps its key when moved between locations
do {
    check(InstallIdentity.key(id: "Mario", bootPath: "/Volumes/D/Mario.wua", isDumpDirectory: false) == "install:Mario.wua", "external file key")
    check(InstallIdentity.key(id: "Mario", bootPath: "/var/Documents/Roms/Mario.wua", isDumpDirectory: false) == "install:Mario.wua", "internal file key matches")
    check(InstallIdentity.key(id: "Kart", bootPath: "/Volumes/D/Kart/code/Kart.rpx", isDumpDirectory: false) == "install:Kart", "unavailable dump record keys by folder")
    check(InstallIdentity.key(id: "Kart", bootPath: "/Volumes/D/Kart/code/Kart.rpx", isDumpDirectory: true) == "install:Kart", "dump keys by folder")
    check(InstallIdentity.key(id: "NUS", bootPath: "/x/NUS/title.tmd", isDumpDirectory: false) == "install:NUS", "nus keys by folder")
}

// Storage fault policy
do {
    check(StorageFault.detect(pathReachable: true, faultCount: 0, baseline: 0) == nil, "no fault when healthy")
    check(StorageFault.detect(pathReachable: false, faultCount: 0, baseline: 0) == .unreachable, "unreachable path")
    check(StorageFault.detect(pathReachable: true, faultCount: 3, baseline: 1) == .readErrors(2), "new read errors counted from baseline")
    check(StorageFault.detect(pathReachable: true, faultCount: 1, baseline: 1) == nil, "old read errors ignored")
    check(StorageFault.unreachable.message(game: "G").contains("\"G\""), "message names the game")
}

// Real disk: probe of a temp folder, then reads from a removed file are failures not crashes
do {
    let root = NSTemporaryDirectory() + "loadkit-check-\(getpid())"
    try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }
    let path = root + "/blob.wua"
    FileManager.default.createFile(atPath: path, contents: Data(repeating: 7, count: 600_000))
    let facts = StorageProbe.collect(path: path)
    check(facts.sampleAttempts == 8 && facts.sampleFailures == 0, "probe reads a real file (\(facts.sampleAttempts) attempts, \(facts.sampleFailures) failures)")
    check(facts.largestFileBytes == 600_000, "probe sees the size")
    check(facts.filesystem != nil, "probe names the filesystem")
    check(StorageAssessment.evaluate(facts).level == .good, "temp disk assessed good (\(StorageAssessment.evaluate(facts).reasons))")

    var vanished = StorageFacts()
    StorageProbe.sample(StorageProbe.Candidate(path: root + "/gone.wua", size: 1_000_000), samples: 4, chunk: 4096, into: &vanished)
    check(vanished.sampleFailures == 1, "unopenable file is a counted failure")
    check(StorageProbe.gatherFiles(under: root + "/nope", using: DiskInspector()).unreadable, "missing directory flagged unreadable")
    check(GameSourceValidator.validateFolder(root + "/nope", using: DiskInspector()) == .failure(.unreadable("nope")), "disk: missing folder")
}

print("loadkit-check: \(passes) passed, \(failures) failed")
exit(Int32(min(failures, 125)))
