// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

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
