import Foundation

public enum StorageFault: Equatable {
    case unreachable
    case readErrors(Int)

    public static func detect(pathReachable: Bool, faultCount: Int, baseline: Int) -> StorageFault? {
        if !pathReachable { return .unreachable }
        if faultCount > baseline { return .readErrors(faultCount - baseline) }
        return nil
    }

    public func message(game: String) -> String {
        switch self {
        case .unreachable:
            return "The drive or folder holding \"\(game)\" was disconnected. Connect it again, then start the game again. Your progress up to your last save is kept."
        case .readErrors:
            return "\"\(game)\" stopped because its files could not be read. The drive may have been disconnected or has a bad connection. Reconnect it, or copy the game into MuffinEMU, then start it again. Your progress up to your last save is kept."
        }
    }

    public var shortLabel: String {
        switch self {
        case .unreachable: return "drive disconnected"
        case .readErrors: return "read error"
        }
    }
}
