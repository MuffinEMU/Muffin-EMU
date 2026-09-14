//
//  CrashDump.swift
//  MeloCafe
//
//  Created by Codex on 18/7/2026.
//

import Foundation

enum CrashDump: Int, CaseIterable {
    case disabled = 0
    case enabled = 1

    init(_ config: ObjCCrashDump) {
        self = CrashDump(rawValue: config.rawValue) ?? .disabled
    }

    var config: ObjCCrashDump {
        ObjCCrashDump(rawValue: self.rawValue) ?? .disabled
    }

    var string: String {
        switch self {
        case .disabled: return "Disabled"
        case .enabled: return "Enabled"
        }
    }
}
