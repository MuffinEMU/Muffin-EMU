import Foundation

public enum InstallIdentity {
    public static func itemName(id: String, bootPath: String, isDumpDirectory: Bool) -> String {
        let bootName = (bootPath as NSString).lastPathComponent
        if isDumpDirectory { return id }
        if bootName.lowercased() == "title.tmd" { return id }
        let parent = ((bootPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
        if parent.lowercased() == "code", (bootName as NSString).pathExtension.lowercased() == "rpx" { return id }
        return bootName.isEmpty ? id : bootName
    }

    public static func key(id: String, bootPath: String, isDumpDirectory: Bool) -> String {
        "install:" + itemName(id: id, bootPath: bootPath, isDumpDirectory: isDumpDirectory)
    }
}
