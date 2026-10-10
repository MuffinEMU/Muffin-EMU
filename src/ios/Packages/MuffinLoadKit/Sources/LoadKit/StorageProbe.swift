import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum StorageProbe {
    public static func filesystemName(atPath path: String) -> String? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return withUnsafePointer(to: &stats.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
    }

    public struct Candidate: Equatable {
        public var path: String
        public var size: UInt64
    }

    public static func gatherFiles(under path: String, using fs: FileInspecting, limit: Int = 4000, maxDepth: Int = 5) -> (largest: [Candidate], undownloaded: Bool, unreadable: Bool) {
        var seen = 0
        var files: [Candidate] = []
        var undownloaded = false
        var unreadable = false
        func walk(_ dir: String, _ depth: Int) {
            guard seen < limit else { return }
            guard let kids = fs.children(of: dir) else {
                if depth == 0 { unreadable = true }
                return
            }
            for kid in kids {
                seen += 1
                if seen >= limit { return }
                if GameSourceValidator.isPlaceholder(kid.name) { undownloaded = true; continue }
                if kid.name.hasPrefix(".") { continue }
                let full = joinPath(dir, kid.name)
                if kid.isDirectory {
                    if depth < maxDepth { walk(full, depth + 1) }
                } else {
                    files.append(Candidate(path: full, size: kid.size))
                }
            }
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
            files = [Candidate(path: path, size: fs.size(of: path) ?? 0)]
        } else {
            walk(path, 0)
        }
        files.sort { $0.size > $1.size }
        return (files, undownloaded, unreadable)
    }

    public static func collect(path: String, using fs: FileInspecting = DiskInspector(), samples: Int = 8, chunk: Int = 64 * 1024) -> StorageFacts {
        var facts = StorageFacts()
        let url = URL(fileURLWithPath: path)
        facts.filesystem = filesystemName(atPath: path)
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            facts.isLocalVolume = values.volumeIsLocal ?? true
            facts.isRemovable = values.volumeIsRemovable ?? false
            facts.isInternalVolume = values.volumeIsInternal ?? true
        }
        let gathered = gatherFiles(under: path, using: fs)
        facts.hasUndownloadedFiles = gathered.undownloaded
        facts.unreadable = gathered.unreadable
        facts.largestFileBytes = gathered.largest.first?.size ?? 0
        guard let target = gathered.largest.first, target.size > 0 else { return facts }
        sample(target, samples: samples, chunk: chunk, into: &facts)
        return facts
    }

    static func sample(_ target: Candidate, samples: Int, chunk: Int, into facts: inout StorageFacts) {
        let descriptor = open(target.path, O_RDONLY)
        guard descriptor >= 0 else {
            facts.sampleAttempts = 1
            facts.sampleFailures = 1
            return
        }
        defer { close(descriptor) }
        if lseek(descriptor, 0, SEEK_END) < 0 { facts.seekUnsupported = true; return }
        var buffer = [UInt8](repeating: 0, count: chunk)
        let span = target.size > UInt64(chunk) ? target.size - UInt64(chunk) : 0
        let count = max(1, samples)
        for index in 0..<count {
            let offset = off_t(span == 0 ? 0 : (span / UInt64(count)) * UInt64(index) + (span / UInt64(count * 2)))
            let want = Int(min(UInt64(chunk), target.size - UInt64(offset)))
            let started = DispatchTime.now().uptimeNanoseconds
            let got = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, want, offset) }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            facts.sampleAttempts += 1
            if got != want {
                facts.sampleFailures += 1
            } else {
                facts.sampledReadMillis.append(elapsed)
            }
        }
    }
}
