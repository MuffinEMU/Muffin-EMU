import Foundation

public struct FileEntry: Equatable {
    public var name: String
    public var isDirectory: Bool
    public var size: UInt64

    public init(name: String, isDirectory: Bool, size: UInt64 = 0) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

public protocol FileInspecting {
    func children(of path: String) -> [FileEntry]?
    func size(of path: String) -> UInt64?
    func head(of path: String, count: Int) -> [UInt8]?
}

public func joinPath(_ base: String, _ name: String) -> String {
    base.hasSuffix("/") ? base + name : base + "/" + name
}

public struct DiskInspector: FileInspecting {
    public init() {}

    public func children(of path: String) -> [FileEntry]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        return names.map { name in
            var isDir: ObjCBool = false
            let full = joinPath(path, name)
            _ = FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            let size = isDir.boolValue ? 0 : (self.size(of: full) ?? 0)
            return FileEntry(name: name, isDirectory: isDir.boolValue, size: size)
        }
    }

    public func size(of path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let number = attrs[.size] as? NSNumber else { return nil }
        return number.uint64Value
    }

    public func head(of path: String, count: Int) -> [UInt8]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}
