import Foundation

public struct StorageFacts: Equatable {
    public var filesystem: String?
    public var isLocalVolume: Bool
    public var isRemovable: Bool
    public var isInternalVolume: Bool
    public var hasUndownloadedFiles: Bool
    public var largestFileBytes: UInt64
    public var sampledReadMillis: [Double]
    public var sampleFailures: Int
    public var sampleAttempts: Int
    public var seekUnsupported: Bool
    public var unreadable: Bool

    public init(
        filesystem: String? = nil,
        isLocalVolume: Bool = true,
        isRemovable: Bool = false,
        isInternalVolume: Bool = true,
        hasUndownloadedFiles: Bool = false,
        largestFileBytes: UInt64 = 0,
        sampledReadMillis: [Double] = [],
        sampleFailures: Int = 0,
        sampleAttempts: Int = 0,
        seekUnsupported: Bool = false,
        unreadable: Bool = false
    ) {
        self.filesystem = filesystem
        self.isLocalVolume = isLocalVolume
        self.isRemovable = isRemovable
        self.isInternalVolume = isInternalVolume
        self.hasUndownloadedFiles = hasUndownloadedFiles
        self.largestFileBytes = largestFileBytes
        self.sampledReadMillis = sampledReadMillis
        self.sampleFailures = sampleFailures
        self.sampleAttempts = sampleAttempts
        self.seekUnsupported = seekUnsupported
        self.unreadable = unreadable
    }
}

public enum StorageLevel: Int, Comparable {
    case good = 0
    case caution = 1
    case unsuitable = 2

    public static func < (lhs: StorageLevel, rhs: StorageLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct StorageVerdict: Equatable {
    public var level: StorageLevel
    public var reasons: [String]
    public var notes: [String]
    public var canPlayAnyway: Bool
    public var canCopy: Bool

    public var summary: String {
        switch level {
        case .good: return "This location looks fine for playing in place."
        case .caution: return "Playing from here may be unreliable."
        case .unsuitable: return "This location isn't reliable enough to play from."
        }
    }
}

public enum StorageAssessment {
    public static let fatLimit: UInt64 = 0xFFFF_FFFF
    public static let slowMedianMillis = 25.0
    public static let verySlowMedianMillis = 250.0
    public static let slowWorstMillis = 400.0

    static let networkFilesystems: Set<String> = ["smbfs", "nfs", "afpfs", "webdav", "cifs", "ftp", "fuse", "macfuse", "osxfuse"]
    static let fatFilesystems: Set<String> = ["msdos", "fat32", "fat", "vfat"]

    public static func isFAT(_ filesystem: String?) -> Bool {
        guard let fs = filesystem?.lowercased() else { return false }
        return fatFilesystems.contains(fs)
    }

    public static func evaluate(_ facts: StorageFacts) -> StorageVerdict {
        var level = StorageLevel.good
        var reasons: [String] = []
        var notes: [String] = []
        var canPlayAnyway = true
        var canCopy = true

        func raise(_ new: StorageLevel, _ reason: String) {
            level = max(level, new)
            reasons.append(reason)
        }

        if facts.unreadable {
            raise(.unsuitable, "MuffinEMU can't read files from this location right now.")
            canPlayAnyway = false
            canCopy = false
        }
        if facts.hasUndownloadedFiles {
            raise(.unsuitable, "Some files are cloud placeholders that haven't been downloaded. Reads would stall or fail while the game runs.")
            canPlayAnyway = false
            canCopy = false
        }
        if facts.sampleFailures > 0 {
            raise(.unsuitable, "\(facts.sampleFailures) of \(facts.sampleAttempts) test reads failed. The drive or its connection is not dependable.")
            canPlayAnyway = false
        }
        if facts.seekUnsupported {
            raise(.unsuitable, "This location doesn't support jumping to a position in a file, which games need for random access.")
            canPlayAnyway = false
        }
        if isFAT(facts.filesystem) {
            if facts.largestFileBytes == fatLimit {
                raise(.unsuitable, "A file is exactly 4 GB minus one byte on a FAT32 drive. FAT32 cuts larger files to that size, so the game is almost certainly incomplete.")
                canPlayAnyway = false
                canCopy = false
            } else {
                notes.append("FAT32 can't hold files over 4 GB. This game's files fit, but don't copy a larger image back to this drive.")
            }
        }
        if let fs = facts.filesystem?.lowercased(), networkFilesystems.contains(fs) {
            raise(.caution, "This is a network location (\(fs)). Network drops stop the game, and latency makes it stutter.")
        } else if !facts.isLocalVolume {
            raise(.caution, "This location isn't a local disk, so reads depend on a network or a cloud service staying connected.")
        }

        let sorted = facts.sampledReadMillis.sorted()
        if !sorted.isEmpty {
            let median = sorted[sorted.count / 2]
            let worst = sorted[sorted.count - 1]
            if median >= verySlowMedianMillis {
                raise(.unsuitable, "Random reads take about \(Int(median)) ms each. Games read in small pieces constantly, so they would freeze and stutter.")
            } else if median >= slowMedianMillis || worst >= slowWorstMillis {
                raise(.caution, "Random reads are slow here (typically \(Int(median)) ms, up to \(Int(worst)) ms). Expect loading pauses and stutter.")
            }
        } else if facts.sampleAttempts == 0 && !facts.unreadable {
            notes.append("Read speed wasn't measured.")
        }

        if facts.isRemovable && facts.isLocalVolume {
            notes.append("This is a removable drive. If it's unplugged, the game stops safely and your saves are kept.")
        }

        return StorageVerdict(level: level, reasons: reasons, notes: notes, canPlayAnyway: canPlayAnyway, canCopy: canCopy)
    }
}
